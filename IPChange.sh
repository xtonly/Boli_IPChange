cat << 'EOF' > IPChange.sh
#!/bin/bash

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
PLAIN="\033[0m"

TOKEN_FILE="/etc/boil_token.conf"
SCRIPT_PATH=$(readlink -f "$0")

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：请使用 root 用户运行此脚本！${PLAIN}"
    exit 1
fi

if ! command -v rdisc6 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    echo -e "${YELLOW}正在安装必要网络组件 (ndisc6, curl)...${PLAIN}"
    apt-get update && apt-get install -y ndisc6 curl
fi

if [ ! -f "$TOKEN_FILE" ]; then
    echo "63f3e8712edc9523" > "$TOKEN_FILE"
fi
API_TOKEN=$(cat "$TOKEN_FILE" | tr -d ' \n\r')

get_net_info() {
    IFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)
    [ -z "$IFACE" ] && IFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')
    IPV4_LOCAL=$(ip -4 addr show dev "$IFACE" | awk '/inet / {print $2; exit}')
    GW4=$(ip -4 route show default dev "$IFACE" | awk '{print $3; exit}')
    [ -z "$IPV4_LOCAL" ] && IPV4_LOCAL="192.168.209.37/24" && GW4="192.168.209.1"

    IPV6_CUSTOM=$(ip -6 addr show dev "$IFACE" scope global | awk '/::8888/ {print $2; exit}')
    IPV6_SLAAC=$(ip -6 addr show dev "$IFACE" scope global | awk '/inet6/ && !/::8888/ {print $2; exit}')
    [ -z "$IPV6_CUSTOM" ] && IPV6_CUSTOM="未绑定"
    [ -z "$IPV6_SLAAC" ] && IPV6_SLAAC="未获取到"
}

check_ipv6_alive() {
    if ping6 -c 2 -W 2 2606:4700:4700::1111 >/dev/null 2>&1 || ping6 -c 2 -W 2 ipv6.google.com >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

refresh_ipv6() {
    get_net_info
    echo -e "${YELLOW}>>> 正在向宿主机网关请求最新 IPv6 前缀并重写配置...${PLAIN}"

    printf "source /etc/network/interfaces.d/*\n\nauto lo\niface lo inet loopback\n\nauto %s\niface %s inet static\n    address %s\n    gateway %s\n    dns-nameservers 1.1.1.1\n    dns-nameservers 8.8.8.8\n    dns-nameservers 2606:4700:4700::1111\n    dns-nameservers 2001:4860:4860::8888\n\niface %s inet6 auto\n    accept_ra 2\n    autoconf 1\n    up sysctl -w net.ipv6.conf.%s.accept_ra=2\n    up sysctl -w net.ipv6.conf.%s.autoconf=1\n    post-up rdisc6 -1 %s >/dev/null 2>&1 || true\n    post-up sleep 2 && PREFIX=\$(ip -6 route show dev %s proto kernel | awk '/::\/64/ && !/^fe80/ {sub(/::\/64/, \"\", \$1); print \$1; exit}') && [ -n \"\$PREFIX\" ] && ip -6 addr add \${PREFIX}::8888/64 dev %s || true\n" "$IFACE" "$IFACE" "$IPV4_LOCAL" "$GW4" "$IFACE" "$IFACE" "$IFACE" "$IFACE" "$IFACE" "$IFACE" > /etc/network/interfaces

    ip -6 addr flush dev "$IFACE" scope global
    ip -6 route flush dev "$IFACE"
    sysctl -w net.ipv6.conf.all.accept_ra=2 >/dev/null 2>&1
    sysctl -w net.ipv6.conf.$IFACE.accept_ra=2 >/dev/null 2>&1
    sysctl -w net.ipv6.conf.$IFACE.autoconf=1 >/dev/null 2>&1

    systemctl restart networking
    rdisc6 -1 "$IFACE" >/dev/null 2>&1 || true
    sleep 3

    NEW_PREFIX=$(ip -6 route show dev "$IFACE" proto kernel | awk '/::\/64/ && !/^fe80/ {sub(/::\/64/, "", $1); print $1; exit}')
    if [ -n "$NEW_PREFIX" ]; then
        ip -6 addr add "${NEW_PREFIX}::8888/64" dev "$IFACE" 2>/dev/null || true
        echo -e "${GREEN}成功提取最新子网前缀并绑定: ${NEW_PREFIX}::8888/64${PLAIN}"
    else
        echo -e "${RED}警告：未能从路由表提取到 /64 前缀，请检查宿主机广播状态。${PLAIN}"
    fi

    sleep 2
    get_net_info
    if check_ipv6_alive; then
        echo -e "${GREEN}>>> IPv6 刷新成功，网络已恢复连通！${PLAIN}"
        IPV6_STATUS="${GREEN}正常连通 (已自动修复)${PLAIN}"
    else
        echo -e "${RED}>>> IPv6 刷新后仍无法 ping 通外部，请稍后重试。${PLAIN}"
        IPV6_STATUS="${RED}连接异常${PLAIN}"
    fi
}

if [ "$1" == "--cron" ]; then
    if ! check_ipv6_alive; then
        refresh_ipv6 >/var/log/boil-ipv6-refresh.log 2>&1
    fi
    exit 0
fi

get_net_info
if check_ipv6_alive; then
    IPV6_STATUS="${GREEN}正常连通 (无需刷新)${PLAIN}"
else
    refresh_ipv6
fi

while true; do
    get_net_info
    API_TOKEN=$(cat "$TOKEN_FILE" | tr -d ' \n\r')
    if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH --cron"; then
        CRON_STATUS="${GREEN}已开启 (每5分钟自动检测保活)${PLAIN}"
    else
        CRON_STATUS="${YELLOW}未开启${PLAIN}"
    fi

    echo -e "\n${CYAN}============================================================${PLAIN}"
    echo -e "            ${GREEN}Boil HKT 网络与 IP 综合管理面板${PLAIN}"
    echo -e "${CYAN}============================================================${PLAIN}"
    echo -e " 主网卡名称   : ${YELLOW}${IFACE}${PLAIN}"
    echo -e " 内网 IPv4    : ${YELLOW}${IPV4_LOCAL}${PLAIN} (网关: ${GW4})"
    echo -e " IPv6 状态    : ${IPV6_STATUS}"
    echo -e " 自定义 IPv6  : ${GREEN}${IPV6_CUSTOM}${PLAIN}"
    echo -e " 原生 IPv6    : ${GREEN}${IPV6_SLAAC}${PLAIN}"
    echo -e " 定时保活状态 : ${CRON_STATUS}"
    echo -e " 当前 Token   : ${CYAN}${API_TOKEN}${PLAIN}"
    echo -e "${CYAN}------------------------------------------------------------${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 手动强制刷新获取最新 IPv6 (重刷 SLAAC 前缀 + 绑定 ::8888)"
    echo -e "  ${GREEN}2.${PLAIN} 仅检测当前 IPv6 连通性 (可用则不刷新，不可用自动修复)"
    echo -e "  ${GREEN}3.${PLAIN} 开启/关闭 后台定时自动检测更新 IPv6 (Crontab 每5分钟)"
    echo -e "  ${GREEN}4.${PLAIN} 查询当前公网 IPv4 信息 (调用 Boil getIP 接口)"
    echo -e "  ${GREEN}5.${PLAIN} 一键更换公网 IPv4 地址 (调用 Boil changeIP 接口)"
    echo -e "  ${GREEN}6.${PLAIN} 更新/修改 Boil API Token"
    echo -e "  ${GREEN}0.${PLAIN} 退出管理面板"
    echo -e "${CYAN}============================================================${PLAIN}"
    read -p "请输入选项数字 [0-6]: " choice

    case "$choice" in
        1) refresh_ipv6 ;;
        2)
            if check_ipv6_alive; then
                IPV6_STATUS="${GREEN}正常连通 (无需刷新)${PLAIN}"
                echo -e "${GREEN}当前 IPv6 正常可用，无需刷新！${PLAIN}"
            else
                refresh_ipv6
            fi
            ;;
        3)
            if crontab -l 2>/dev/null | grep -q "$SCRIPT_PATH --cron"; then
                crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH --cron" | crontab -
                echo -e "${YELLOW}已关闭 IPv6 后台定时自动检测任务。${PLAIN}"
            else
                (crontab -l 2>/dev/null; echo "*/5 * * * * /bin/bash $SCRIPT_PATH --cron") | crontab -
                echo -e "${GREEN}已开启！系统将每 5 分钟在后台检测一次 IPv6，断联时自动更新前缀。${PLAIN}"
            fi
            ;;
        4)
            RESP=$(curl -s -X POST -H "Authorization: Bearer ${API_TOKEN}" https://ippanel.boil.network/api/v1/getIP)
            echo -e "API 响应结果: ${GREEN}${RESP}${PLAIN}"
            echo -e "本机实时检测公网 IPv4: ${YELLOW}$(curl -s -4 --max-time 5 ip.sb || echo '获取超时')${PLAIN}"
            ;;
        5)
            read -p "确定要调用 API 更换当前公网 IPv4 吗？[y/N]: " confirm
            if [[ "$confirm" =~ ^[yY]$ ]]; then
                RESP=$(curl -s -X POST -H "Authorization: Bearer ${API_TOKEN}" https://ippanel.boil.network/api/v1/changeIP)
                echo -e "API 响应结果: ${GREEN}${RESP}${PLAIN}"
                sleep 3
                echo -e "最新公网 IPv4: ${GREEN}$(curl -s -4 --max-time 5 ip.sb || echo '正在切换中，请稍后按 4 查询')${PLAIN}"
            else
                echo -e "已取消操作。"
            fi
            ;;
        6)
            read -p "请输入新的 Bearer Token (当前为 ${API_TOKEN}): " new_token
            new_token=$(echo "$new_token" | tr -d ' \n\r')
            if [ -n "$new_token" ]; then
                echo "$new_token" > "$TOKEN_FILE"
                echo -e "${GREEN}Token 已成功更新为: ${new_token}${PLAIN}"
            else
                echo -e "${RED}输入为空，未修改 Token。${PLAIN}"
            fi
            ;;
        0)
            echo -e "${GREEN}已退出面板。${PLAIN}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效输入，请输入 0 到 6 之间的数字。${PLAIN}"
            ;;
    esac
done
EOF
chmod +x IPChange.sh
