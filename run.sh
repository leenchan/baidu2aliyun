#!/bin/sh
CUR_DIR=$(cd "$(dirname "$0")";pwd)
BIN_ALIYUN="aliyundrive-webdav"
BIN_BAIDUYUN="baidupcs"
ALIYUN_WEBDAV_PORT="8080"
ALIYUN_REFRESH_TOKEN="$REFRESH_TOKEN"
ALIYUN_MNT="$CUR_DIR/aliyun"

pre_check() {
  [ -z "$FROM_BAIDUYUN_PATH" ] && echo "Please choose a file / dir from BaiduYun"
  [ -z "$REFRESH_TOKEN" ] && echo "Please set Aliyun Token"
}

install_required_packages() {
  sudo apt-get update && sudo apt-get install davfs2 inotify-tools
  pip install aliyundrive-webdav
  git clone https://github.com/qjfoidnh/BaiduPCS-Go.git baidupcs && \
    cd baidupcs && \
    go build && \
    sudo mv BaiduPCS-Go /usr/bin/$BIN_BAIDUYUN && \
    chmod +x /usr/bin/$BIN_BAIDUYUN
  ${BIN_ALIYUN} --version
  ${BIN_BAIDUYUN} --version
  cd $CUR_DIR
  return 0
}

run_cloud() {
  $BIN_ALIYUN --port $ALIYUN_WEBDAV_PORT --refresh-token $ALIYUN_REFRESH_TOKEN --auto-index &
  sleep 5
  curl -sI 127.0.0.1:$ALIYUN_WEBDAV_PORT | grep -q "200" || (echo "[ERR] Failed to run Aliyun."; return 1)
  mkdir -p $ALIYUN_MNT
  sudo mount -t davfs -o user_id=1001,group_id=121,rw 127.0.0.1:$ALIYUN_WEBDAV_PORT $ALIYUN_MNT || ("[ERR] Failet to mount Aliyun."; return 1)
  [ -z "$(ls $ALIYUN_MNT)" ] && return 1
  mkdir -p ~/.config/BaiduPCS-Go
  cp config/pcs_config.json ~/.config/BaiduPCS-Go/
  ${BIN_BAIDUYUN} quota || {
    echo "[ERR] Failed to login Baiduyun"
    return 1
  }
  return 0
}

copy_file_or_dir() {
  echo "From Baiduyun: $FROM_BAIDUYUN_PATH"
  echo "To Aliyun: $TO_ALIYUN_DIR"
}

case "$1" in
  "precheck")
    pre_check || exit 1
    ;;
  "prepare")
    install_required_packages || exit 1
    ;;
  "run_cloud")
    run_cloud || exit 1
    ;;
esac
