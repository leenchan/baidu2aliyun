#!/bin/sh
CUR_DIR=$(cd "$(dirname "$0")";pwd)
BIN_ALIYUN="aliyundrive-webdav"
BIN_BAIDUYUN="baidupcs"
BAIDUYUN_DOWNLOAD_DIR="$CUR_DIR/baiduyun_dl"
BAIDUYUN_CACHE_DIR="$BAIDUYUN_DOWNLOAD_DIR/.cache"
BAIDUYUN_DOWNLOAD_EXT=".BaiduPCS-Go-downloading"
ALIYUN_WEBDAV_PORT="8080"
ALIYUN_REFRESH_TOKEN="$REFRESH_TOKEN"
ALIYUN_MNT="$CUR_DIR/aliyun"

pre_check() {
	[ -z "$FROM_BAIDUYUN_PATH" ] && echo "Please choose a file / dir from BaiduYun" && return 1
	[ -z "$REFRESH_TOKEN" ] && echo "Please set Aliyun Token" && return 1
	[ -z "$TO_ALIYUN_DIR" ] && TO_ALIYUN_DIR="/Baiduyun"
	echo "$TO_ALIYUN_DIR" | grep -q '^/' || TO_ALIYUN_DIR="/${TO_ALIYUN_DIR}"
	return 0
}

install_required_packages() {
	sudo apt-get update && sudo apt-get install davfs2 inotify-tools
	sudo echo "if_match_bug    1" >> /etc/davfs2/davfs2.conf
	sudo echo "use_locks       0" >> /etc/davfs2/davfs2.conf
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
	tmux new-session -d -s aliyun_webdav "$BIN_ALIYUN --port $ALIYUN_WEBDAV_PORT --refresh-token $ALIYUN_REFRESH_TOKEN --auto-index"
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
	echo "$(id | grep -Eo '(uid|gid)=[0-9]+' | tr '\n' ',')file_mode=666,dir_mode=777"
	echo "" | awk '{print "";print ""}' | sudo mount -t davfs -o "$(id | grep -Eo '(uid|gid)=[0-9]+' | tr '\n' ',')file_mode=666,dir_mode=777" "127.0.0.1:$ALIYUN_WEBDAV_PORT" "$ALIYUN_MNT"
	sudo cat /etc/davfs2/davfs2.conf
	sudo mount
	exit 1
	[ -z "$(ls $ALIYUN_MNT)" ] && echo "[ERR] Failet to mount Aliyun." && return 1
	mkdir -p ~/.config/BaiduPCS-Go
	cp config/pcs_config.json ~/.config/BaiduPCS-Go/
	${BIN_BAIDUYUN} quota || {
		echo "[ERR] Failed to login Baiduyun"
		return 1
	}
	return 0
}

get_baiduyun_list() {
	[ -z "$1" ] && return 1
	_LIST_=$(${BIN_BAIDUYUN} tree "$1")
	echo "$_LIST_" | awk -F'   ' '{
		for (i=1;i<=NF;i++) {
			gsub("├── ", "", $i);
			gsub("└── ", "", $i);
			if ($i~/\/$/) {
			  DIR = i==1 ? $i : DIR $i;
			}
			if (i==NF) {
			  print $i~/\/$/ ? DIR : DIR $i;
			}
		}
	}'
	return 1
}

transfer_files() {
	echo "From Baiduyun: $FROM_BAIDUYUN_PATH"
	echo "To Aliyun: $TO_ALIYUN_DIR"
	LIST=$(${BIN_BAIDUYUN} ls "$FROM_BAIDUYUN_PATH" | grep -E '^\s*[0-9]+' | sed -E 's/^\s*//;s/\s{3,16}/  /g' | awk -F'  ' '{print $4}')
	if [ -z "$LIST" ]; then
		${BIN_BAIDUYUN} meta "$FROM_BAIDUYUN_PATH" | grep -q 'md5' || {
			echo "[ERR] Not found: \"${FROM_BAIDUYUN_PATH}\""
			return 1
		}
		TYPE="FILE"
		LIST="$FROM_BAIDUYUN_PATH"
	else
		TYPE="DIRECTORY"
		mkdir -p "$BAIDUYUN_CACHE_DIR"
		FROM_BAIDUYUN_PATH=$(echo "$FROM_BAIDUYUN_PATH" | sed 's/\/$//')
		get_baiduyun_list "$FROM_BAIDUYUN_PATH" > "$BAIDUYUN_CACHE_DIR/baiduyun_list"
		cp "$BAIDUYUN_CACHE_DIR/baiduyun_list" "$BAIDUYUN_CACHE_DIR/baiduyun_process"
		_TOTAL_=$(cat "$BAIDUYUN_CACHE_DIR/baiduyun_list" | grep -v '/$' | wc -l)
		_CURR_=0
		while read LINE
		do
			[ -z "$LINE" ] || {
				_SROUCE_PATH_="$BAIDUYUN_DOWNLOAD_DIR/$LINE"
				_TARGET_PATH_="$ALIYUN_MNT$TO_ALIYUN_DIR/$LINE"
				if echo "$LINE" | grep -q '/$'; then
					[ -d "$_SROUCE_PATH_" ] || mkdir -p "$_SROUCE_PATH_"
					[ -d "$_TARGET_PATH_" ] || mkdir -p "$_TARGET_PATH_"
				else
					_CURR_=$((_CURR_+1))
					_SKIP_="0"
					[ -f "$_TARGET_PATH_" ] && {
						if [ -f "${_TARGET_PATH_}${BAIDUYUN_DOWNLOAD_EXT}" ]; then
							cp -f "$_TARGET_PATH_" "$_SROUCE_PATH_"
							cp -f "${_TARGET_PATH_}${BAIDUYUN_DOWNLOAD_EXT}" "${_SROUCE_PATH_}${BAIDUYUN_DOWNLOAD_EXT}"
						else
							_SKIP_="1"
						fi
					}
					echo "[${_CURR_}/${_TOTAL_}] $_SROUCE_PATH_ => $_TARGET_PATH_$([ "${_SKIP_}" = "1" ] && echo " ...Skip")"
					[ "$_SKIP_" = "1" ] || {
						${BIN_BAIDUYUN} download "$FROM_BAIDUYUN_PATH/$LINE" --saveto "$(echo "$_SROUCE_PATH_" | grep -Eo '.*\/')" && {
							cp -f "$_SROUCE_PATH_" "$_TARGET_PATH_"
						}
					}
				fi
			}
		done <<-EOF
		$(cat $BAIDUYUN_CACHE_DIR/baiduyun_process)
		EOF
		cat "$BAIDUYUN_CACHE_DIR/baiduyun_list"
	fi
}

dispatch() {
	curl \
		-X POST https://api.github.com/repos/${GITHUB_REPO}/dispatches \
		-H "Accept: application/vnd.github.everest-preview+json" \
		-H "Authorization: token ${{ secrets.REPO_TOKEN }}" \
		-d "{\"event_type\": \"continue\", \"client_payload\": {\"from_baiduyun\": \"$FROM_BAIDUYUN_PATH\", \"to_aliyun\": \"$TO_ALIYUN_DIR\"}}"
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
	"transfer")
		transfer_files || exit 1
		;;
esac
