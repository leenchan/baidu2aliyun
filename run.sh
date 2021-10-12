#!/bin/sh
CUR_DIR=$(cd "$(dirname "$0")";pwd)

install_required_packages() {
  pip install aliyundrive-webdav
  git clone https://github.com/qjfoidnh/BaiduPCS-Go.git baidupcs && \
    cd baidupcs && \
    go build && \
    sudo mv BaiduPCS-Go /usr/bin/baidupcs && \
    chmod +x /usr/bin/baidupcs
  cd $CUR_DIR
}

install_required_packages