#!/bin/bash

###>
## This script MUST run inside docker container
###>

# Change working directory to /tmp (=>/data/tmp) from source script beforehand

export PARU_OPTS=(--skipreview --noprovides --removemake --cleanafter --useask --combinedupgrade --batchinstall --nokeepsrc)

echo -e " ->> Updating paru Database"
( paru -S --noconfirm || true )

echo -e " ->> Installing Required makedeps"
( paru -S --noconfirm --needed "${PARU_OPTS[@]}" cmake ninja clang lld mold nasm openmp nano less tree mediainfo wget aria2 unzip rclone ) 1>/dev/null

# targetmarch=['x86-64-v2','x86-64-v3','native']
case ${targetmarch} in
  x86-64-v[23]) export native="OFF" ;;
  native) export native="ON" ;;
esac

if grep -q "pgocompileuse\|svtboltgen" <<<"${job_name}"; then
  # get prebuilt llvm-bolt
  rclone copy "ms365:Public/xTemp/llvm-bolt-18.1.8-4-x86_64.pkg.tar.zst" /tmp/ --fast-list --stats-one-line-date -v
fi

if [[ ${targetmarch} != "native" ]]; then
  # get prebuilt libdovi+libhdr10plus with matching targetmarch to install
  rclone copy "ms365:Public/ArchVapourBuilds/${targetmarch}/Step_Zero2/" --include="libdovi-git-*-x86_64.pkg.tar.zst" --include="libhdr10plus-rs-git-*-x86_64.pkg.tar.zst" --max-depth=1 /tmp/ --fast-list --stats-one-line-date -v 2>/dev/null
  tree -a -h /tmp
  # remove libdovi-git and libhdr10plus-git and re-install from files
  ( sudo pacman -Rdd libdovi-git libhdr10plus-git --noconfirm 2>/dev/null )
  # install them
  sudo pacman -U --noconfirm /tmp/*.pkg.tar.zst
fi

echo -e " ->> Removing old svt-av1-psy-git now"
( sudo pacman -Rdd svt-av1-psy-git --noconfirm || true )
echo -e " ->> Removing Redundant official svt-av1 arch package, if retained"
( sudo pacman -Rdd svt-av1 --noconfirm || true )

###>
## Main Process Starts Here
###>

# Start-off in /tmp again
cd /tmp

export projectdir="/svtproject"
export srcdir="${projectdir}/src"
export _repo="svt-av1-psy"

# Change directory to ${srcdir} where we will work
mkdir -p ${srcdir}
cd ${srcdir}/

if [[ ${job_name} == "pgocompilegen" ]]; then
  # Clone SvtAv1Psy Source
  git clone --filter=blob:none https://github.com/gianni-rosato/${_repo}
  export pkgver=$(git -C ${_repo} describe --long --tags --abbrev=7 | sed 's/\([^-]*-g\)/r\1/;s/-/./g;s/^v//')

  # Build SVT-AV1 to generate our PGO data.
  # Add for GCC Builds: (-DCMAKE_CXX_FLAGS="-fno-reorder-blocks-and-partition")
  export CC='/usr/bin/clang' CXX='/usr/bin/clang++'
  export LD='/usr/bin/ld.mold' LDFLAGS="$LDFLAGS -Wl,-z,noexecstack -Wl,--emit-relocs"
  export SuppressorFlags=(
    -Wno-dev -Wno-unused-parameter -Wno-unused-result
    -Wno-unused-variable -Wno-implicit-function-declaration
  )
  export CFLAGS_PGO_GEN="-march=${targetmarch} -Ofast -flto=full"
  export ninjaDir="build"
  cmake -S "${_repo}" -B ${ninjaDir} -G Ninja \
    -DCMAKE_INSTALL_PREFIX='/usr' \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS='OFF' \
    -DSVT_AV1_LTO='OFF' \
    -DENABLE_AVX512='OFF' \
    -DNATIVE="${native}" \
    -DBUILD_TESTING='OFF' \
    -DBUILD_DEC='OFF' \
    -DCMAKE_C_FLAGS="$CFLAGS_PGO_GEN -DNDEBUG" \
    -DCMAKE_CXX_FLAGS="$CFLAGS_PGO_GEN -DNDEBUG" \
    -DCMAKE_EXE_LINKER_FLAGS="$CFLAGS_PGO_GEN -fuse-ld=mold -Wl,-z,noexecstack -Wl,--emit-relocs" \
    -DSVT_AV1_PGO='ON' \
    -DSVT_AV1_PGO_DIR="/tmp/svt-pgo-data" \
    -DLIBDOVI_FOUND=1 \
    -DLIBHDR10PLUS_RS_FOUND=1 \
    -DCMAKE_ASM_NASM_COMPILER="nasm" \
    "${SuppressorFlags[@]}"
  ninja PGOCompileGen -C ${ninjaDir}

  export state="PGOCompileGen"
  # Pass the state to next step
  echo "PGOCompileGen=pass" >>$GITHUB_ENV

  # Keep a Backup of Built Codes and Binaries
  tar -I'xz -9e -T2' -cf ${projectdir}/${_repo}_${state}_gitrepo.txz ${_repo}
  tar -I'xz -9e -T2' -cf ${projectdir}/${_repo}_${state}_ninja.txz ${ninjaDir}
  pushd ${_repo}/Bin/Release/ 1>/dev/null
  tar -I'xz -9e -T2' -cf ${projectdir}/${_repo}_${state}_binaries.txz *
  popd 1>/dev/null
  for x in gitrepo ninja binaries; do
    ls -lAog ${projectdir}/${_repo}_${state}_${x}.txz
    curl -s -F"file=@${projectdir}/${_repo}_${state}_${x}.txz" https://temp.sh/upload && echo
  done
  # Make sure to unpack them from (under) ${srcdir}/
elif [[ ${job_name} == "pgodatagen" ]]; then
  # Extract from artifacts (under ${srcdir})
  export state="PGOCompileGen"
  for x in gitrepo ninja; do
    ls -lAog ${projectdir}/${_repo}_${state}_${x}.txz
    tar -xf ${projectdir}/${_repo}_${state}_${x}.txz
    rm ${projectdir}/${_repo}_${state}_${x}.txz
  done
  ls -lAog

  echo -e "[</>] Getting Test Video"
  rclone copy "ms365:Public/xTemp/svtproject_datadump/videos/${media_file}" --fast-list /videos/ 2>/dev/null

  ## Encode in ${projectdir}
  cd ${projectdir}

  unset BOLT 2>/dev/null || true
  bash ${projectdir}/43-av1an-encode-containered.sh
elif [[ ${job_name} == "pgocompileuse" ]]; then
  # Extract from artifacts (under ${srcdir})
  export state="PGOCompileGen"
  for x in gitrepo ninja; do
    ls -lAog ${projectdir}/${_repo}_${state}_${x}.txz
    tar -xf ${projectdir}/${_repo}_${state}_${x}.txz
    rm ${projectdir}/${_repo}_${state}_${x}.txz
  done
  ls -lAog

  echo -e "[#] Merge the generated profraw data into something useable"
  pushd /tmp/svt-pgo-data/ &>/dev/null
  for i in *.tzst; do
    tar -xf ${i} && rm ${i}
  done
  # llvm17{,-libs} is preinstalled due to akarinVS plugin
  /usr/bin/llvm-profdata-17 merge *.profraw-real --output default.profdata
  rm *.profraw-real
  tar -I'zstd -19 -T2' default.profdata.tzst default.profdata
  popd &>/dev/null
  curl -s -F"file=@/tmp/svt-pgo-data/default.profdata.tzst" https://temp.sh/upload && echo

  echo -e "[#] Compile SVT-AV1 again using our new PGO data"
  # Add for GCC Builds: (-DCMAKE_CXX_FLAGS="-fno-reorder-blocks-and-partition")
  export CC='/usr/bin/clang' CXX='/usr/bin/clang++'
  export LD='/usr/bin/ld.mold' LDFLAGS="$LDFLAGS -Wl,-z,noexecstack -Wl,--emit-relocs"
  export SuppressorFlags=(
    -Wno-dev -Wno-unused-parameter -Wno-unused-result
    -Wno-unused-variable -Wno-implicit-function-declaration
  )
  export CFLAGS_PGO_USE="-march=${targetmarch} -O3 -flto=full"
  export ninjaDir="xbuild"
  cmake -S "${_repo}" -B ${ninjaDir} -G Ninja \
    -DCMAKE_INSTALL_PREFIX='/usr' \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS='OFF' \
    -DSVT_AV1_LTO='OFF' \
    -DENABLE_AVX512='OFF' \
    -DNATIVE="${native}" \
    -DBUILD_TESTING='OFF' \
    -DBUILD_DEC='OFF' \
    -DCMAKE_C_FLAGS="$CFLAGS_PGO_USE -DNDEBUG" \
    -DCMAKE_CXX_FLAGS="$CFLAGS_PGO_USE -DNDEBUG" \
    -DCMAKE_EXE_LINKER_FLAGS="$CFLAGS_PGO_USE -fuse-ld=mold -Wl,-z,noexecstack -Wl,--emit-relocs" \
    -DSVT_AV1_PGO='ON' \
    -DSVT_AV1_PGO_DIR="/tmp/svt-pgo-data" \
    -DLIBDOVI_FOUND=1 \
    -DLIBHDR10PLUS_RS_FOUND=1 \
    -DCMAKE_ASM_NASM_COMPILER="nasm" \
    "${SuppressorFlags[@]}"
  ninja PGOCompileUse -C ${ninjaDir}    # FIXME: maybe use a different directory instead of `build`

  export state="PGOCompileUse"
  echo "PGOCompileUse=pass" >>$GITHUB_ENV

  # Keep a Backup of Built Codes and Binaries
  tar -I'xz -9e -T2' -cf ${projectdir}/${_repo}_${state}_gitrepo.txz ${_repo}
  tar -I'xz -9e -T2' -cf ${projectdir}/${_repo}_${state}_ninja.txz ${ninjaDir}
  pushd ${_repo}/Bin/Release/ 1>/dev/null
  tar -I'xz -9e -T2' -cf ${projectdir}/${_repo}_${state}_binaries.txz *
  popd 1>/dev/null
  for x in gitrepo ninja binaries; do
    ls -lAog ${projectdir}/${_repo}_${state}_${x}.txz
    curl -s -F"file=@${projectdir}/${_repo}_${state}_${x}.txz" https://temp.sh/upload && echo
  done
  # Make sure to unpack them from (under) ${srcdir}/

  # Use Bolt on SVT-AV1 for further generate profile data. This is different from PGO and more confusing.
  mv "${_repo}/Bin/Release/SvtAv1EncApp" "${_repo}/Bin/Release/non-bolt-SvtAv1EncApp"
  llvm-bolt "${_repo}/Bin/Release/non-bolt-SvtAv1EncApp" \
    --instrument \
    --instrumentation-file-append-pid \
    --instrumentation-file="${srcdir}"/svt-bolt-data/svt-data.fdata \
    -o "${_repo}/Bin/Release/SvtAv1EncApp"
  ls -lAog "${_repo}/Bin/Release/"
  rm "${_repo}/Bin/Release/non-bolt-SvtAv1EncApp" 2>/dev/null || true

  export state="PGOPreBolted"
  echo "PGOPreBolted=pass" >>$GITHUB_ENV

  # Keep a Backup of Built Codes and Binaries
  tar -I'xz -9e -T2' -cf ${projectdir}/${_repo}_${state}_gitrepo.txz ${_repo}
  pushd ${_repo}/Bin/Release/ 1>/dev/null
  tar -I'xz -9e -T2' -cf ${projectdir}/${_repo}_${state}_binaries.txz *
  popd 1>/dev/null
  for x in gitrepo binaries; do
    ls -lAog ${projectdir}/${_repo}_${state}_${x}.txz
    curl -s -F"file=@${projectdir}/${_repo}_${state}_${x}.txz" https://temp.sh/upload && echo
  done
  # Make sure to unpack them from (under) ${srcdir}/
elif [[ ${job_name} == "boltdatagen" ]]; then
  # Extract from artifacts (under ${srcdir})
  # maybe the *_ninja is not needed here but on last job
  for x in PGOPreBolted_gitrepo; do
    ls -lAog ${projectdir}/${_repo}_${x}.txz
    tar -xf ${projectdir}/${_repo}_${x}.txz
    rm ${projectdir}/${_repo}_${x}.txz
  done
  ls -lAog

  echo -e "[</>] Getting Test Video"
  rclone copy "ms365:Public/xTemp/svtproject_datadump/videos/${media_file}" --fast-list /videos/ 2>/dev/null

  ## Encode in ${projectdir}
  cd ${projectdir}

  export BOLT="enabled"
  bash ${projectdir}/43-av1an-encode-containered.sh
elif [[ ${job_name} == "svtboltgen" ]]; then
  # Extract from artifacts (under ${srcdir})
  for x in PGOPreBolted_gitrepo PGOCompileUse_ninja PGOCompileGen_ninja; do
    ls -lAog ${projectdir}/${_repo}_${x}.txz
    tar -xf ${projectdir}/${_repo}_${x}.txz
    rm ${projectdir}/${_repo}_${x}.txz
  done
  ls -lAog

  # compile all of our fdata files into one
  merge-fdata "${srcdir}/svt-bolt-data"/*.fdata > "${srcdir}/svt-bolt-data/final.fdata-real"

  # Finally Bolt on our generated data to the SVT binary using llvm-bolt.
  mv "${_repo}/Bin/Release/SvtAv1EncApp" "${_repo}/Bin/Release/pre-bolt-SvtAv1EncApp"
  llvm-bolt "${_repo}/Bin/Release/non-bolt-SvtAv1EncApp" \
    --data="${srcdir}/svt-bolt-data/final.fdata-real" \
    -reorder-blocks=ext-tsp \
    -reorder-functions=hfsort+ \
    -split-functions \
    -split-all-cold \
    -split-eh \
    -dyno-stats \
    -icf=1 \
    -use-gnu-stack \
    -plt=hot \
    -o "${_repo}/Bin/Release/SvtAv1EncApp"
    # -icp-eliminate-loads \
    # -indirect-call-promotion=all \
    # -jump-tables=basic \
    # -align-macro-fusion=hot \
  ls -lAog "${_repo}/Bin/Release/"
  rm "${_repo}/Bin/Release/non-bolt-SvtAv1EncApp" 2>/dev/null || true

  export state="SvtPGOBolted"
  echo "SvtPGOBolted=pass" >>$GITHUB_ENV

  # Keep a Final Backup of Built Codes and Binaries
  tar -I'xz -9e -T2' -cf ${projectdir}/${_repo}_${state}_gitrepo.txz ${_repo}
  pushd ${_repo}/Bin/Release/ 1>/dev/null
  tar -I'xz -9e -T2' -cf ${projectdir}/${_repo}_${state}_binaries.txz *
  popd 1>/dev/null
  for x in gitrepo binaries; do
    ls -lAog ${projectdir}/${_repo}_${state}_${x}.txz
    curl -s -F"file=@${projectdir}/${_repo}_${state}_${x}.txz" https://temp.sh/upload && echo
  done

  # Intall on Portable Folder
  export ninjaDir="xbuild"
  export pkgver=$(git -C ${_repo} describe --long --tags --abbrev=7 | sed 's/\([^-]*-g\)/r\1/;s/-/./g;s/^v//')
  DESTDIR="${projectdir}/bolted" cmake --install ${ninjaDir}
  install -Dm 644 "${_repo}"/{LICENSE,PATENTS}.md -t "${projectdir}/bolted/usr/share/licenses/svt-av1/"
  pushd ${projectdir}/bolted/ 1>/dev/null
  tar -I'xz -9e -T2' -cf ${projectdir}/${_repo}-pgo-bolt-git-${pkgver}.txz *
  popd 1>/dev/null
fi

