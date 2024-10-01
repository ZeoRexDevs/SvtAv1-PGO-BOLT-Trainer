#!/bin/bash

echo -e "[</>] Getting Test Video list"
rclone lsf "ms365:Public/xTemp/svtproject_datadump/videos/" --include="*.ffv1.mkv" --max-depth=1 --fast-list 2>/dev/null | sort -u >filelist.txt

export filecount=$(wc -l < filelist.txt)
echo -e "\n[i] There are total ${filecount} media files to be worked on\n"

export fileArray=($(<filelist.txt))
rm filelist.txt

export matrix=[$(sed 's|\s|","|g' <<<"\"${fileArray[@]}\"")]
echo -e "\n[+] The Build Matrix: \n${matrix}\n"

echo "matrix=${matrix}" >>$GITHUB_OUTPUT

