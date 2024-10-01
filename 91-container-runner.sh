#!/bin/bash

# Working Directory == /data

docker container start ${ContainerName} 1>/dev/null
docker exec -i --privileged -e escript -e dscript --workdir /tmp ${ContainerID} bash <<'EOZ'
sudo chown -R app /home/app /{tmp,videos,svtproject} /home/app/.config/rclone/rclone.conf
cd /tmp
source /tmp/${dscript}
rm /tmp/${dscript}
exit
EOZ

# Own back the folders to github runner
sudo chown -R runner /data/{tmp,videos,svtproject} /home/runner/.config/rclone/rclone.conf

