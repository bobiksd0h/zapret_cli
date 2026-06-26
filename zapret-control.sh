#!/bin/bash

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SELF_DIR="$(dirname "$SELF")"

source "$SELF_DIR/files/vars.sh"
source "$SELF_DIR/files/utils.sh"
source "$SELF_DIR/files/config.sh"
source "$SELF_DIR/files/init.sh"
source "$SELF_DIR/files/menu.sh"
source "$SELF_DIR/files/service.sh"
source "$SELF_DIR/files/install.sh"

set -e

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo > /dev/null 2>&1; then
        SUDO="sudo"
    elif command -v doas > /dev/null 2>&1; then
        SUDO="doas"
    else
        echo "Скрипт не может быть выполнен не от имени суперпользователя."
        exit 1
    fi
fi

if [[ $EUID -ne 0 ]]; then
    exec $SUDO "$0" "$@"
fi

trap fast_exit SIGINT
check_openwrt
check_tput
$TPUT_B
check_fs
detect_init
remote_latest_version
main_menu
