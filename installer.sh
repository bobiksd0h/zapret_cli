#!/bin/sh
# Bootstrap for the zapret terminal installer (local-files design).
# Deploys this folder (scripts + bundled cfgs) to /opt/zapret.installer and
# launches the control menu. The engine binaries are fetched from bol-van/zapret2.

set -e

INSTALLER_DIR="/opt/zapret.installer"

install_prereq() {
    kernel="$(uname -s)"
    [ "$kernel" = "Linux" ] || return 0
    [ -f /etc/os-release ] && . /etc/os-release || return 0

    pm() {
        case "$1" in
            arch|artix|cachyos|endeavouros|manjaro|garuda) echo "$SUDO pacman -Sy --noconfirm --needed curl tar bash" ;;
            debian|ubuntu|mint) echo "$SUDO apt-get update -y && $SUDO apt-get install -y curl tar bash" ;;
            fedora|almalinux|rocky|rhel|centos|oracle|redos) echo "if command -v dnf >/dev/null 2>&1; then $SUDO dnf install -y curl tar bash; else $SUDO yum install -y curl tar bash; fi" ;;
            void)      echo "$SUDO xbps-install -Sy curl tar bash" ;;
            gentoo)    echo "$SUDO emerge --noreplace net-misc/curl app-arch/tar app-shells/bash" ;;
            opensuse*) echo "$SUDO zypper install -y curl tar bash" ;;
            openwrt)   echo "$SUDO opkg update && $SUDO opkg install curl tar bash" ;;
            altlinux)  echo "$SUDO apt-get update -y && $SUDO apt-get install -y curl tar bash" ;;
            alpine)    echo "$SUDO apk add curl tar bash" ;;
            *)         echo "" ;;
        esac
    }

    cmd="$(pm "$ID")"
    if [ -z "$cmd" ] && [ -n "$ID_LIKE" ]; then
        for like in $ID_LIKE; do
            cmd="$(pm "$like")" && [ -n "$cmd" ] && break
        done
    fi
    if [ -n "$cmd" ]; then
        eval "$cmd" || true
    fi
}

if [ "$(awk '$2 == "/" {print $4}' /proc/mounts)" = "ro" ]; then
    echo "Файловая система только для чтения, не могу продолжать."
    exit 1
fi

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

# resolve our own location (the repo root containing installer.sh, files/, cfgs/)
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
CFGS_SRC="$SELF_DIR/cfgs"

if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
    install_prereq
fi

# deploy to /opt unless we're already running from there
if [ "$SELF_DIR" != "$INSTALLER_DIR" ]; then
    [ -d "$CFGS_SRC" ] || { echo "Не найдена папка cfgs рядом с installer.sh ($CFGS_SRC)."; exit 1; }
    $SUDO mkdir -p "$INSTALLER_DIR"
    $SUDO cp -a "$SELF_DIR/installer.sh" "$SELF_DIR/zapret-control.sh" "$SELF_DIR/files" "$SELF_DIR/cfgs" "$INSTALLER_DIR/"
fi

$SUDO chmod +x "$INSTALLER_DIR/zapret-control.sh"
exec bash "$INSTALLER_DIR/zapret-control.sh"
