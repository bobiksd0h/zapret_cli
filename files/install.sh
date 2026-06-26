#!/bin/bash


remote_latest_version() {
    rver=$(timeout 10s curl -s https://api.github.com/repos/$ZAPRET_REPO/releases/latest | \
          grep "tag_name" | \
          cut -d '"' -f 4 | \
          sed 's/^v//')
}

get_latest_version() {
    if [ -z "$rver" ]; then
        rver=$(timeout 10s curl -s -I https://github.com/$ZAPRET_REPO/releases/latest | grep -i "location:" | cut -d' ' -f2 | tr -d '\r' | grep -o "tag/v[0-9.]\+" | cut -d'/' -f2 | sed 's/^v//')
        if [ -z "$rver" ]; then
            echo "Неизвестно"
        else
            echo "$rver"
        fi
    else
        echo "$rver"
    fi
}

# fetch zapret2 binaries release into $ZAPRET_BASE (configs come from local $CFGS_DIR)
download_zapret_release() {
    local ver
    ver="$(get_latest_version)"
    [ "$ver" = "Неизвестно" ] && error_exit "не удалось определить последнюю версию запрета. Проверьте соединение с сетью."

    rm -rf "$ZAPRET_BASE"
    rm -rf "/opt/zapret2-v$ver"
    TEMP_DIR_BIN=$(mktemp -d)

    local url
    if [ "$SYSTEM" = openwrt ]; then
        url=$(curl -s https://api.github.com/repos/$ZAPRET_REPO/releases/latest | grep "browser_download_url.*openwrt.*tar.gz" | head -n 1 | cut -d '"' -f 4)
    else
        url=$(curl -s https://api.github.com/repos/$ZAPRET_REPO/releases/latest | grep "browser_download_url.*tar.gz" | grep -v "openwrt" | head -n 1 | cut -d '"' -f 4)
    fi
    [ -n "$url" ] || { rm -rf "$TEMP_DIR_BIN"; error_exit "не удалось определить ссылку на релиз запрета."; }

    if ! curl -L -o "$TEMP_DIR_BIN/latest.tar.gz" "$url"; then
        rm -rf "$TEMP_DIR_BIN"
        error_exit "не удалось получить релиз запрета."
    fi
    if ! tar -xzf "$TEMP_DIR_BIN/latest.tar.gz" -C /opt/; then
        rm -rf "$TEMP_DIR_BIN" "/opt/zapret2-v$ver"
        error_exit "не удалось разархивировать архив с релизом запрета."
    fi
    rm -rf "$TEMP_DIR_BIN"

    if [ -d "/opt/zapret2-v$ver" ]; then
        mv "/opt/zapret2-v$ver" "$ZAPRET_BASE"
    elif [ ! -d "$ZAPRET_BASE" ]; then
        # some archives may use a different top-level dir name
        local extracted
        extracted=$(find /opt -maxdepth 1 -type d -name 'zapret2-*' | head -n1)
        [ -n "$extracted" ] && mv "$extracted" "$ZAPRET_BASE"
    fi
    [ -d "$ZAPRET_BASE" ] || error_exit "релиз запрета распакован некорректно."
    echo "$ver" > "$VER_FILE"
}

install_dependencies() {
    kernel="$(uname -s)"
    if [ "$kernel" = "Linux" ]; then
        . /etc/os-release
        declare -A command_by_ID=(
            ["arch"]="pacman -S --noconfirm --needed iptables-nft ipset nftables"
            ["artix"]="pacman -S --noconfirm --needed iptables-nft ipset nftables"
            ["cachyos"]="pacman -S --noconfirm --needed iptables-nft ipset nftables"
            ["endeavouros"]="pacman -S --noconfirm --needed iptables-nft ipset nftables"
            ["manjaro"]="pacman -S --noconfirm --needed iptables-nft ipset nftables"
            ["debian"]="apt-get install -y iptables ipset nftables"
            ["fedora"]="dnf install -y iptables ipset nftables"
            ["ubuntu"]="apt-get install -y iptables ipset nftables"
            ["mint"]="apt-get install -y iptables ipset nftables"
            ["centos"]="yum install -y ipset iptables nftables"
            ["void"]="xbps-install -y iptables ipset nftables"
            ["gentoo"]="emerge --noreplace net-firewall/iptables net-firewall/ipset net-firewall/nftables"
            ["opensuse"]="zypper install -y iptables ipset nftables"
            ["openwrt"]="opkg install iptables ipset nftables"
            ["altlinux"]="apt-get install -y iptables ipset nftables"
            ["almalinux"]="dnf install -y iptables ipset nftables"
            ["rocky"]="dnf install -y iptables ipset nftables"
            ["alpine"]="apk add iptables ipset nftables"
        )
        if [[ -v command_by_ID[$ID] ]]; then
            eval "${command_by_ID[$ID]}" || true
        else
            for like in $ID_LIKE; do
                if [[ -n "${command_by_ID[$like]}" ]]; then
                    eval "${command_by_ID[$like]}" || true
                    break
                fi
            done
        fi
    elif [ "$kernel" = "Darwin" ]; then
        error_exit "macOS не поддерживается на данный момент."
    else
        echo "Неизвестная ОС: ${kernel}. Установите iptables/nftables и ipset самостоятельно."
        read -p "Нажмите Enter для продолжения..."
    fi
}

# auto-answer the upstream installer (avoid the brittle line-number hack of v1)
_run_install_easy() {
    cd "$ZAPRET_BASE" || error_exit "не удалось перейти в $ZAPRET_BASE"
    [ -f "$ZAPRET_BASE/install_easy.sh" ] || error_exit "не найден install_easy.sh в релизе запрета"
    sed -i 's/ask_yes_no N "do you want to continue"/ask_yes_no Y "do you want to continue"/' "$ZAPRET_BASE/install_easy.sh"
    yes "" | ./install_easy.sh
}

# nfqws2 aborts at startup if MODE_FILTER=autohostlist and the auto-hostlist file
# is missing or not writable by the daemon user (it drops privileges to WS_USER).
# Pre-create it and make it writable.
ensure_auto_hostlist() {
    local af="$ZAPRET_BASE/ipset/zapret-hosts-auto.txt"
    touch "$af" || error_exit "не удалось создать $af"
    local wsu
    wsu="$(. "$ZAPRET_BASE/config" >/dev/null 2>&1; echo "${WS_USER:-tpws}")"
    if id "$wsu" >/dev/null 2>&1; then
        chown "$wsu" "$af" 2>/dev/null
    fi
    chmod 666 "$af" 2>/dev/null
}

# copy local strategies/lists/bins into the freshly installed zapret2
_apply_local_cfgs() {
    mkdir -p "$ZAPRET_BASE/files/fake" "$ZAPRET_BASE/ipset"
    rm -f "$ZAPRET_BASE/config"
    cp -r "$CFGS_DIR/configurations/general" "$ZAPRET_BASE/config" || error_exit "не удалось автоматически скопировать конфиг"
    set_fwtype_in_config
    cp -r "$CFGS_DIR"/bin/* "$ZAPRET_BASE/files/fake/" || error_exit "не удалось автоматически скопировать fake bin"
    touch "$ZAPRET_BASE/ipset/ipset-game.txt" || error_exit "не удалось автоматически создать game ipset"
    rm -f "$ZAPRET_BASE/ipset/zapret-hosts-user.txt"
    cp -r "$CFGS_DIR/lists/list-basic.txt" "$ZAPRET_BASE/ipset/zapret-hosts-user.txt" || error_exit "не удалось автоматически скопировать хостлист"
    cp -r "$CFGS_DIR/lists/ipset-discord.txt" "$ZAPRET_BASE/ipset/ipset-discord.txt" || error_exit "не удалось автоматически скопировать ипсет"
    touch "$ZAPRET_BASE/ipset/zapret-hosts-user-exclude.txt"
    ensure_auto_hostlist
}

_link_control() {
    rm -f "$BIN_LINK"
    ln -s "$INSTALLER_DIR/zapret-control.sh" "$BIN_LINK" || error_exit "не удалось создать символическую ссылку"
}

install_zapret_release() {
    install_dependencies
    if [[ $dir_exists == true ]]; then
        read -p "На вашем компьютере был найден запрет ($ZAPRET_BASE). Для продолжения его необходимо удалить. Продолжить? (y/N): " answer
        case "$answer" in
            [Yy]* )
                if [[ -f "$ZAPRET_BASE/uninstall_easy.sh" ]]; then
                    cd "$ZAPRET_BASE"
                    yes "" | ./uninstall_easy.sh
                fi
                rm -rf "$ZAPRET_BASE"
                echo "Удаляю zapret..."
                cd /
                sleep 3
                ;;
            * )
                main_menu
                ;;
        esac
    fi
    echo -e "\e[35mСкачиваю последнюю версию запрета...\e[0m"
    download_zapret_release
    _run_install_easy
    _apply_local_cfgs
    _link_control
    if [[ "$INIT_SYSTEM" == systemd ]]; then
        systemctl daemon-reload
    fi
    if [[ "$INIT_SYSTEM" == runit ]]; then
        read -p "Для окончания установки необходимо перезапустить ваше устройство. Перезапустить сейчас? (Y/n): " answer
        case "$answer" in
            [Nn]* ) $TPUT_E; exit 1;;
            * ) reboot;;
        esac
    else
        manage_service restart
        configure_zapret_conf
    fi
}

update_zapret() {
    LIST_EXISTS=0
    CONF_EXISTS=0
    EXC_EXISTS=0
    TEMP_DIR_CONF=$(mktemp -d)
    if [[ -f "$ZAPRET_BASE/config" ]]; then
        cp -r "$ZAPRET_BASE/config" "$TEMP_DIR_CONF/config"
        CONF_EXISTS=1
    fi
    if [[ -f "$ZAPRET_BASE/ipset/zapret-hosts-user.txt" ]]; then
        cp -r "$ZAPRET_BASE/ipset/zapret-hosts-user.txt" "$TEMP_DIR_CONF/zapret-hosts-user.txt"
        LIST_EXISTS=1
    fi
    if [[ -f "$ZAPRET_BASE/ipset/zapret-hosts-user-exclude.txt" ]]; then
        cp -r "$ZAPRET_BASE/ipset/zapret-hosts-user-exclude.txt" "$TEMP_DIR_CONF/zapret-hosts-user-exclude.txt"
        EXC_EXISTS=1
    fi

    echo -e "\e[35mОбновляю запрет до последней версии...\e[0m"
    download_zapret_release
    echo -e "Запрет обновлён до версии $(cat "$VER_FILE")"
    _run_install_easy
    _apply_local_cfgs

    if [ "$CONF_EXISTS" = 1 ]; then
        rm -f "$ZAPRET_BASE/config"
        mv "$TEMP_DIR_CONF/config" "$ZAPRET_BASE/config"
        set_fwtype_in_config
    fi
    if [ "$LIST_EXISTS" = 1 ]; then
        rm -f "$ZAPRET_BASE/ipset/zapret-hosts-user.txt"
        mv "$TEMP_DIR_CONF/zapret-hosts-user.txt" "$ZAPRET_BASE/ipset/zapret-hosts-user.txt"
    fi
    if [ "$EXC_EXISTS" = 1 ]; then
        rm -f "$ZAPRET_BASE/ipset/zapret-hosts-user-exclude.txt"
        mv "$TEMP_DIR_CONF/zapret-hosts-user-exclude.txt" "$ZAPRET_BASE/ipset/zapret-hosts-user-exclude.txt"
    fi
    rm -rf "$TEMP_DIR_CONF"
    _link_control
    if [[ "$INIT_SYSTEM" == systemd ]]; then
        systemctl daemon-reload
    fi
    manage_service restart
    read -p "Нажмите Enter для продолжения..."
    exec "$0" "$@"
}

uninstall_zapret() {
    read -p "Вы действительно хотите удалить запрет? (y/N): " answer
    case "$answer" in
        [Yy]* )
            if [[ -f "$ZAPRET_BASE/uninstall_easy.sh" ]]; then
                cd "$ZAPRET_BASE"
                yes "" | ./uninstall_easy.sh
            fi
            rm -rf "$ZAPRET_BASE"
            rm -rf "$INSTALLER_DIR"
            rm -f "$BIN_LINK"
            rm -f "$VER_FILE"
            echo "Удаляю zapret..."
            sleep 3
            echo "Запрет удалён"
            $TPUT_E
            exit
            ;;
        * )
            main_menu
            ;;
    esac
}
