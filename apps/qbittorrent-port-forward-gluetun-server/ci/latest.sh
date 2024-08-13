#!/usr/bin/env bash
git clone --quiet https://github.com/mjmeli/qbittorrent-port-forward-gluetun-server.git /tmp/qbittorrent-port-forward-gluetun-server
sed -i '/\gtn_addr="/a mam_location="${MAM_ID_PATH}"' ./apps/qbittorrent-port-forward-gluetun-server/main.sh
sed -i '/\echo "Successfully updated port"/i curl -c $mam_location -b $mam_location https://t.myanonamouse.net/json/dynamicSeedbox.php\n' /tmp/qbittorrent-port-forward-gluetun-server/main.sh
pushd /tmp/qbittorrent-port-forward-gluetun-server > /dev/null || exit
version=$(git rev-list --count --first-parent HEAD)
popd > /dev/null || exit
rm -rf /tmp/qbittorrent-port-forward-gluetun-server
printf "1.0.%d" "${version}"
