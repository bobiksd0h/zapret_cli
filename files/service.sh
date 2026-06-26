#!/bin/bash



manage_service() {
    case "$INIT_SYSTEM" in
        systemd)
            SYSTEMD_PAGER=cat systemctl "$1" $SERVICE
            ;;
        openrc)
            rc-service $SERVICE "$1"
            ;;
        runit|runit-artix)
            sv "$1" $SERVICE
            ;;
        sysvinit)
            service $SERVICE "$1"
            ;;
        procd)
            service $SERVICE "$1"
    esac
}

manage_autostart() {
    case "$INIT_SYSTEM" in
        systemd)
            systemctl "$1" $SERVICE
            ;;
        runit)
            if [[ "$1" == "enable" ]]; then
                ln -fs $ZAPRET_BASE/init.d/runit/$SERVICE/ /var/service/
            else
                rm -f /var/service/$SERVICE
            fi
            ;;
        runit-artix)
            if [[ "$1" == "enable" ]]; then
                ln -fs $ZAPRET_BASE/init.d/runit/$SERVICE/ /run/runit/service/
            else
                rm -f /run/runit/service/$SERVICE
            fi
            ;;
        sysvinit)
            if [[ "$1" == "enable" ]]; then
                update-rc.d $SERVICE defaults
            else
                update-rc.d -f $SERVICE remove
            fi
            ;;
        openrc)
            if [[ "$1" == "enable" ]]; then
                rc-update add $SERVICE default
            else
                rc-update del $SERVICE
            fi
            ;;
        procd)
            service $SERVICE "$1"
    esac
}

check_zapret_exist() {
    case "$INIT_SYSTEM" in
        systemd)
            if [ -f /etc/systemd/system/timers.target.wants/${SERVICE}-list-update.timer ]; then
                service_exists=true
            else
                service_exists=false
            fi
            ;;
        procd)
            if [ -f /etc/init.d/$SERVICE ]; then
                service_exists=true
            else
                service_exists=false
            fi
            ;;
        runit)
            ls /var/service 2>/dev/null | grep -q "$SERVICE" && service_exists=true || service_exists=false
            ;;
        runit-artix)
            ls /run/runit/service 2>/dev/null | grep -q "$SERVICE" && service_exists=true || service_exists=false
            ;;
        openrc)
            rc-service -l 2>/dev/null | grep -q "$SERVICE" && service_exists=true || service_exists=false
            ;;
        sysvinit)
            [ -f /etc/init.d/$SERVICE ] && service_exists=true || service_exists=false
            ;;
        *)
            ZAPRET_EXIST=false
            return
            ;;
    esac

    if [ -d "$ZAPRET_BASE" ]; then
        dir_exists=true
        [ -d "$ZAPRET_BASE/binaries" ] && binaries_exists=true || binaries_exists=false
    else
        dir_exists=false
        binaries_exists=false
    fi

    if [ "$service_exists" = true ] && [ "$dir_exists" = true ] && [ "$binaries_exists" = true ]; then
        ZAPRET_EXIST=true
    else
        ZAPRET_EXIST=false
    fi
}

check_zapret_status() {
    case "$INIT_SYSTEM" in
        systemd)
        ZAPRET_ACTIVE=$(systemctl show -p ActiveState $SERVICE | cut -d= -f2 || true)
        ZAPRET_ENABLED=$(systemctl is-enabled $SERVICE 2>/dev/null || echo "false")
        ZAPRET_SUBSTATE=$(systemctl show -p SubState $SERVICE | cut -d= -f2)
        if [[ "$ZAPRET_ACTIVE" == "active" && "$ZAPRET_SUBSTATE" == "running" ]]; then
           ZAPRET_ACTIVE=true
        else
            ZAPRET_ACTIVE=false
        fi

        if [[ "$ZAPRET_ENABLED" == "enabled" ]]; then
            ZAPRET_ENABLED=true
        else
            ZAPRET_ENABLED=false
        fi
        if [[ "$ZAPRET_ENABLED" == "not-found" ]]; then
            ZAPRET_ENABLED=false
        fi
        ;;
        openrc)
            rc-service $SERVICE status >/dev/null 2>&1 && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            rc-update show | grep -q $SERVICE && ZAPRET_ENABLED=true || ZAPRET_ENABLED=false
            ;;
        procd)
            if /etc/init.d/$SERVICE status | grep -q "running"; then
                ZAPRET_ACTIVE=true
            else
                ZAPRET_ACTIVE=false
            fi
            if ls /etc/rc.d/ | grep -q $SERVICE >/dev/null 2>&1; then
                ZAPRET_ENABLED=true
            else
                ZAPRET_ENABLED=false
            fi
            ;;
        runit)
            sv status $SERVICE | grep -q "run" && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            ls /var/service | grep -q "$SERVICE" && ZAPRET_ENABLED=true || ZAPRET_ENABLED=false
            ;;
        runit-artix)
            sv status $SERVICE | grep -q "run" && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            ls /run/runit/service | grep -q "$SERVICE" && ZAPRET_ENABLED=true || ZAPRET_ENABLED=false
            ;;
        sysvinit)
            service $SERVICE status >/dev/null 2>&1 && ZAPRET_ACTIVE=true || ZAPRET_ACTIVE=false
            ;;
    esac
}

toggle_service() {
    while true; do
        clear
        echo -e "\e[1;36m╔═════════════════════════════════════════════════╗"
        echo -e "║          Управление сервисом Запрета            ║"
        echo -e "╚═════════════════════════════════════════════════╝\e[0m"

        if [[ $ZAPRET_ACTIVE == true ]]; then
            echo -e "  \e[1;32m Запрет запущен\e[0m"
        else
            echo -e "  \e[1;31m Запрет выключен\e[0m"
        fi

        if [[ $ZAPRET_ENABLED == true ]]; then
            echo -e "  \e[1;32m Запрет в автозагрузке\e[0m"
        else
            echo -e "  \e[1;33m Запрет не в автозагрузке\e[0m"
        fi

        echo ""

        echo -e "  \e[1;31m0)\e[0m Выйти в меню"
        echo -e "  \e[1;33m1)\e[0m $( [[ $ZAPRET_ENABLED == true ]] && echo "Убрать из автозагрузки" || echo "Добавить в автозагрузку" )"
        echo -e "  \e[1;32m2)\e[0m $( [[ $ZAPRET_ACTIVE == true ]] && echo "Выключить Запрет" || echo "Включить Запрет" )"
        echo -e "  \e[1;36m3)\e[0m Посмотреть статус Запрета"
        echo -e "  \e[1;35m4)\e[0m Перезапустить Запрет"

        echo ""

        read -p $'\e[1;36mВыберите действие: \e[0m' CHOICE
        case "$CHOICE" in
            1)
                [[ $ZAPRET_ENABLED == true ]] && manage_autostart disable || manage_autostart enable
                main_menu
                ;;
            2)
                [[ $ZAPRET_ACTIVE == true ]] && manage_service stop || manage_service start
                main_menu
                ;;
            3)
                manage_service status
                read -p $'\e[1;36mНажмите Enter для продолжения...\e[0m'
                main_menu
                ;;
            4)
                manage_service restart
                main_menu
                ;;
            0)
                main_menu
                ;;
            *)
                echo -e "\e[1;31m Неверный ввод! Попробуйте снова.\e[0m"
                sleep 2
                ;;
        esac
    done
}
