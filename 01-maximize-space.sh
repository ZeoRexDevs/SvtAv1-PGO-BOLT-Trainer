#!/bin/bash

echo -e "[#] root space cleanup"
sudo rm -rf /usr/local/lib/android /opt/hostedtoolcache /usr/local/share/vcpkg /usr/share/dotnet /opt/ghc

echo -e "[#] redundant docker images cleanup"
docker rmi -f $(docker images -q) 2>/dev/null || true

echo -e "[#] /data volume creation"
export ROOT_RESERVE_MB=${ROOT_RESERVE_MB:-12288} TEMP_RESERVE_MB=${TEMP_RESERVE_MB:-512} SWAP_SIZE_MB=${SWAP_SIZE_MB:-8192}
export cleanerAddr="https://gist.github.com/rokibhasansagar/27271d28d0d6fa2d4a8d3b6253ffb5cd"
export cleanRef=$(git ls-remote -q "${cleanerAddr}" HEAD | awk '{print $1}')
curl -sL --retry 8 --retry-connrefused "${cleanerAddr}/raw/${cleanRef}/maximize.space.sh" | bash 2>/dev/null

