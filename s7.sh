#!/bin/bash

PROXY_BIN="/usr/local/bin/3proxy"
PROXY_CFG="/etc/3proxy/3proxy.cfg"
ACCOUNT_FILE="/root/socks5_accounts.txt"
BIND_PREFIX_FILE="/root/socks5_ipv6_used.txt"
PORT_BASE=10000
COUNT=100
USERNAME="user1"
PASSWORD="pass1"
INTERFACE="eth0"

function install_3proxy() {
    if ! [ -f "$PROXY_BIN" ]; then
        echo "⚙️ 安装 3proxy 中..."
        apt update && apt install git build-essential -y
        git clone https://github.com/z3APA3A/3proxy.git /opt/3proxy
        cd /opt/3proxy && make -f Makefile.Linux
        cp /opt/3proxy/src/3proxy $PROXY_BIN
        chmod +x $PROXY_BIN
        echo "✅ 3proxy 安装完成。"
    fi
}

function generate_ipv6_list() {
    IPV6_BASE=$(ip -6 addr show "$INTERFACE" | grep -oP 'inet6 \K[0-9a-f:]+(?=/)' | grep -v fe80 | head -n 1)
    echo "🧠 基础 IPv6 地址：$IPV6_BASE"
    IPV6_PREFIX=${IPV6_PREFIX/%::/}

    > "$ACCOUNT_FILE"
    > "$BIND_PREFIX_FILE"
    > "$PROXY_CFG"

    cat <<EOF >> "$PROXY_CFG"
daemon
maxconn 1000
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
users $USERNAME:CL:$PASSWORD
auth strong
log /var/log/3proxy.log D
EOF

    for ((i=0; i<$COUNT; i++)); do
        HEX=$(printf '%x:%x:%x:%x' $RANDOM $RANDOM $RANDOM $RANDOM)
        FULL_IPV6="${IPV6_BASE}::${HEX}"
        PORT=$((PORT_BASE + i))

        # 绑定 IPv6
        ip -6 addr add "$FULL_IPV6"/64 dev "$INTERFACE"
        echo "$FULL_IPV6" >> "$BIND_PREFIX_FILE"

        # 写入 Socks5 配置
        echo "proxy -6 -n -a -p$PORT -i0.0.0.0 -e$FULL_IPV6" >> "$PROXY_CFG"

        # 保存账号
        echo "[$FULL_IPV6]:$PORT:$USERNAME:$PASSWORD" >> "$ACCOUNT_FILE"
    done
}

function start_proxy() {
    install_3proxy
    generate_ipv6_list
    echo "🚀 启动 3proxy 服务..."
    pkill 3proxy
    nohup $PROXY_BIN $PROXY_CFG > /dev/null 2>&1 &
    echo "✅ 3proxy 已启动。"
    echo "✅ 已生成 Socks5 列表：$ACCOUNT_FILE"
}

function stop_proxy() {
    echo "🛑 停止 3proxy..."
    pkill 3proxy || echo "未检测到运行中的 3proxy。"
}

function status_proxy() {
    pgrep -x 3proxy > /dev/null && echo "✅ 3proxy 正在运行。" || echo "❌ 3proxy 未运行。"
}

function unload_ipv6() {
    echo "🧹 卸载绑定的 IPv6..."
    while read ip; do
        ip -6 addr del "$ip"/64 dev "$INTERFACE"
    done < "$BIND_PREFIX_FILE"
    echo "✅ 卸载完成。"
}

case "$1" in
    start)
        start_proxy
        ;;
    stop)
        stop_proxy
        ;;
    status)
        status_proxy
        ;;
    unload)
        unload_ipv6
        ;;
    *)
        echo "用法: $0 {start|stop|status|unload}"
        ;;
esac
