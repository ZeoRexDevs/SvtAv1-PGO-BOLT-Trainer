#!/bin/bash

###>>
## `svt_encode` scriptlet
###>>

# WARNING: This part MUST be sourced in a matrix job inside the container

white="\e[1;37m" green="\e[1;32m" red="\e[1;31m" nc="\e[0m"

# Set Encode Parameters

# Use:
# - preset {1..5}
# - crf {24..42}
# - tune {0,2,3}
# - VB {1,2} + VO {1..6}

SVT_AV1AN_COMMAND_1="--progress 2 --preset 3 --crf 30 --keyint 0 --irefresh-type 1 --film-grain 6 --film-grain-denoise 0 --enable-overlays 1 --scd 0 --tune 2 --enable-tf 0 --enable-qm 1 --qm-min 5 --qm-max 12"
SVT_AV1AN_COMMAND_2="--progress 2 --preset 4 --crf 28 --keyint 0 --irefresh-type 1 --enable-overlays 1 --scd 0 --tune 2 --enable-tf 0 --enable-qm 1 --qm-min 4 --qm-max 13"
SVT_AV1AN_COMMAND_3="--progress 2 --preset 2 --crf 26 --keyint 0 --irefresh-type 1 --enable-overlays 1 --scd 0 --tune 0 --enable-tf 0 --enable-qm 1 --qm-min 0 --qm-max 15"
SVT_AV1AN_COMMAND_4="--progress 2 --preset 5 --crf 35 --keyint 0 --irefresh-type 1 --enable-overlays 1 --scd 0 --tune 1 --enable-tf 0 --enable-qm 1 --qm-min 5 --qm-max 9 --variance-boost-strength 1 --variance-octile 6"
SVT_AV1AN_COMMAND_5="--progress 2 --preset 3 --crf 32 --keyint 0 --irefresh-type 1 --film-grain 5 --film-grain-denoise 1 --enable-overlays 1 --scd 0 --tune 0 --enable-tf 0 --enable-qm 1 --qm-min 1 --qm-max 15"

export av1an_opts=(
  --verbose
  --log-file av1an_log
  --split-method av-scenechange
  --sc-method standard
  --sc-pix-format yuv420p
  --sc-downscale-height 540
  --chunk-method lsmash
  --pix-format yuv420p10le
  --concat mkvmerge
)

# Add our new svt-av1 binary to the ${PATH} because you're unable to tell Av1an what binary to use.
export PATH="${srcdir}/${_repo}/Bin/Release:${PATH}"

function svt_encode() {
  shopt -s nullglob

  echo -e "\n ->> media_file = ${media_file}"
  basename="${media_file##*/}"

  for x in {1..5}; do
    if [[ ${x} -eq 1 ]]; then
      echo -e "${green}SCDetect:${nc}${white} ${basename}${nc}"
      # shellcheck disable=SC2068
      LD_LIBRARY_PATH="${srcdir}/${_repo}/Bin/Release${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
      av1an -e svt-av1 "${av1an_opts[@]}" --scenes "${media_file}.scenes.json" \
        --sc-only -i "/videos/${media_file}" -o "/videos/${media_file}.${x}.av1an.mkv"
      sed -i -e '1d;$d' -e 's/DEBUG \[rav1e::scenechange\] //g;s/\[SC-Detect\] //g;s/^DEBUG //g;s/^INFO //g;s/  No cut$//g' av1an_log.log
      sed -n '$p' av1an_log.log 2>/dev/null && echo
      rm av1an_log.log
    fi

    echo -e "${green}Encoding:${nc}${white} ${basename}${nc} with ${white}SVT_AV1AN_COMMAND_${x}${nc}"
    case ${x} in
      1) export SVTCOMM="${SVT_AV1AN_COMMAND_1}" ;;
      2) export SVTCOMM="${SVT_AV1AN_COMMAND_2}" ;;
      3) export SVTCOMM="${SVT_AV1AN_COMMAND_3}" ;;
      4) export SVTCOMM="${SVT_AV1AN_COMMAND_4}" ;;
      5) export SVTCOMM="${SVT_AV1AN_COMMAND_5}" ;;
    esac
    # shellcheck disable=SC2068
    LD_LIBRARY_PATH="${srcdir}/${_repo}/Bin/Release${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
      av1an -e svt-av1 "${av1an_opts[@]}" --scenes "${media_file}.scenes.json" \
        -v " ${SVTCOMM} " -i "/videos/${media_file}" -o "/videos/${media_file}.${x}.av1an.mkv"

    mv av1an_log.log av1an_log.${x}.log

    # move profraw
    # shellcheck disable=SC2012
    if ! test "$(ls /tmp/svt-pgo-data/*.profraw 2>/dev/null | wc -l)" -eq 0; then
      (
        for profraw in /tmp/svt-pgo-data/*.profraw; do
          basename_profraw="${profraw##*/}"
          profraw_newname="${basename_profraw%.*}.$(echo ${RANDOM} | md5sum | head -c 5).profraw-real"
          mv -vf "${profraw}" "/tmp/svt-pgo-data/${profraw_newname}"
        done
        profraw_arcbase="profraw.$(echo ${RANDOM} | md5sum | head -c 5)"
        tar -I'zstd -19 -T2' -cvf "/tmp/svt-pgo-data/${profraw_arcbase}.tzst" /tmp/svt-pgo-data/*.profraw-real
        curl -s -F"file=@/tmp/svt-pgo-data/${profraw_arcbase}.tzst" https://temp.sh/upload && echo
      )
    fi

    # move fdata
    # This might not be needed with --instrumentation-file-append-pid (in same machine)
    if test "${BOLT}" == "enabled"; then
      echo -e "${green}Bolt is enabled, checking for .fdata file(s)${nc}"
      # shellcheck disable=SC2012
      if ! test "$(ls /tmp/svt-bolt-data/*.fdata 2>/dev/null | wc -l)" -eq 0; then
        echo -e "${green}Found fdata file in svt-bolt-data${nc}"
        (
          fdata_arcbase="fdata.$(echo ${RANDOM} | md5sum | head -c 5)"
          tar -I'zstd -19 -T2' -cvf "/tmp/svt-bolt-data/${fdata_arcbase}.tzst" /tmp/svt-bolt-data/*.fdata
          curl -s -F"file=@/tmp/svt-bolt-data/${fdata_arcbase}.tzst" https://temp.sh/upload && echo
        )
      else
        echo -e "${red}No fdata file found in svt-bolt-data${nc}"
      fi
    fi
  done

  # Cleanup converted videos and logs
  tar -I'zstd -19 -T2' -cf /tmp/av1an_log.all.tzst av1an_log.*.log
  curl -s -F"file=@/tmp/av1an_log.all.tzst" https://temp.sh/upload && echo
  rm -- "/videos/${media_file}".*.av1an.mkv ${media_file}.scenes.json av1an_log.*
}

svt_encode

# Generate a prefix for artifact naming under the matrix
echo "pgo_bolt_pfx=$(echo ${RANDOM} | md5sum | head -c 5)" >>$GITHUB_ENV

