#!/bin/sh
CUR_DIR=$(cd "$(dirname "$0")";pwd)
BIN_ALIYUN="aliyundrive-webdav"
BIN_BAIDUYUN="baidupcs"
ALIYUN_WEBDAV_PORT="8080"
ALIYUN_REFRESH_TOKEN="$REFRESH_TOKEN"
ALIYUN_MNT="$CUR_DIR/aliyun"

pre_check() {
  [ -z "$FROM_BAIDUYUN_PATH" ] && echo "Please choose a file / dir from BaiduYun" && return 1
  [ -z "$REFRESH_TOKEN" ] && echo "Please set Aliyun Token" && return 1
  return 0
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
  $BIN_ALIYUN --port $ALIYUN_WEBDAV_PORT --refresh-token $ALIYUN_REFRESH_TOKEN --auto-index 2>/dev/null &
  RETRY="0"
  ALIYUN_OK="0"
  while true
  do
    [ "$RETRY" -gt 10 ] && break
    echo "Checking Aliyun ($RETRY)"
    curl -sI 127.0.0.1:$ALIYUN_WEBDAV_PORT | grep -q "200" && ALIYUN_OK="1" && break
    RETRY=$((RETRY+1))
    sleep 1
  done
  [ "$ALIYUN_OK" = "0" ] && echo "[ERR] Failed to run Aliyun." && return 1
  mkdir -p $ALIYUN_MNT
  echo "" | awk '{print "";print ""}' | sudo mount -t davfs -o uid=1001,gid=121,rw "127.0.0.1:$ALIYUN_WEBDAV_PORT" "$ALIYUN_MNT"
  [ -z "$(ls $ALIYUN_MNT)" ] && echo "[ERR] Failet to mount Aliyun." && return 1
  mkdir -p ~/.config/BaiduPCS-Go
  cp config/pcs_config.json ~/.config/BaiduPCS-Go/
  ${BIN_BAIDUYUN} quota || {
    echo "[ERR] Failed to login Baiduyun"
    return 1
  }
  return 0
}

copy_files() {
  echo "From Baiduyun: $FROM_BAIDUYUN_PATH"
  echo "To Aliyun: $TO_ALIYUN_DIR"
  ${BIN_BAIDUYUN} ls "$FROM_BAIDUYUN_PATH" | grep -E '^\s*[0-9]+' | sed -E 's/^\s*//;s/\s{3,16}/  /g' | awk -F'  ' '{print $4}'
  return 0
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
  "copy_files")
    copy_files || exit 1
    ;;
esac
