#!/bin/bash

# Working Directory == /data

if [[ ! -s /data/localVS.tar.gz ]]; then
  echo -e "[#] Pulling localVS.tar.gz from Cloud"
  rclone copyto "ms365:Public/ArchVapourBuilds/vapoursynth-av1an-runtime.tar.gz" /data/localVS.tar.gz --fast-list --stats-one-line-date
  ls -lAog /data/localVS.tar.gz
fi
cat /data/localVS.tar.gz | docker import --change 'USER app' --change 'VOLUME ["/videos"]' --change 'WORKDIR /videos' --change 'ENTRYPOINT [ "/usr/bin/bash" ]' - ${VapourDockerImage}:latest

# Just make a docker container out of the imported image
docker run --privileged -v "/data/tmp:/tmp" -v "/data/tmp/svt-bolt-data:/tmp/svt-bolt-data" -v "/data/tmp/svt-pgo-data:tmp/svt-pgo-data" -v "/data/videos:/videos" -v "/data/svtproject:/svtproject" -v "/home/runner/.config/rclone/rclone.conf:/home/app/.config/rclone/rclone.conf" --workdir /tmp -i ${VapourDockerImage}:latest <<'EOT'
date
EOT

# Pass on ContainerInfo for later steps
export ContainerInfo=$(docker ps -all | grep "${VapourDockerImage}:latest")
export ContainerID=$(awk '{print $1}' <<<"${ContainerInfo}")
export ContainerName=$(awk '{print $NF}' <<<"${ContainerInfo}")

echo "ContainerID=${ContainerID}" >>$GITHUB_ENV
echo "ContainerName=${ContainerName}" >>$GITHUB_ENV

# Own back the folders to github runner
sudo chown -R runner /data/{tmp,videos,svtproject} /home/runner/.config/rclone/rclone.conf
