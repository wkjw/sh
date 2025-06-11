#!/bin/bash

CONFIG_FILE="/etc/3proxy/3proxy.cfg"
USER_PASS_FILE="/root/socks5_accounts.txt"
INTERFACE="eth0"
BASE_PORT=10800
NUM_IP=100
FIXED_USER="myuser"
FIXED_PASS="mypassword"
PREFIX_TAG="#S5AUTO"

function check_3proxy_installed() {
    if ! command -v 3proxy >/dev/null 2>&1; then
        echo "未检测到 3proxy，正在安装..."
        apt update && apt install -y build-essential git
        git clone https://github.com/z3APA3A/3proxy.git /tmp/3proxy
        cd /tmp/3proxy
        make -f Makefile.Linux
        cp src/3proxy /usr/local/bin/
        mkdir -p /etc/3proxy/logs /etc/3proxy/stat
        touch $CONFIG_FILE
    fi
}

function write_base_config() {
    cat <<EOF > $CONFIG_FILE
daemon
maxconn 1000
nserver 8.8.8.8
nserver 2001:4860:4860::8888
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
log /etc/3proxy/logs/3proxy.log D
logformat "- +_L%t.%. %c:%c %C:%C %r %O %I %h %T"
archiver gz /bin/gzip
pidfile /var/run/3proxy.pid
users $FIXED_USER:CL:$FIXED_PASS $PREFIX_TAG
EOF
}

function generate_ipv6_socks5() {
    IPV6_BASE=$(ip -6 addr show $INTERFACE scope global | grep inet6 | head -n1 | awk '{print $2}' | cut -d/ -f1)
    [[ -z "$IPV6_BASE" ]] && echo "无法获取IPv6地址，请检查接口 $INTERFACE" && exit 1
    PREFIX=$(echo $IPV6_BASE | awk -F: '{print $1":"$2":"$3":"$4}')
    
    > $USER_PASS_FILE
    cp $CONFIG_FILE ${CONFIG_FILE}.bak_$(date +%F_%T)

    # 写入基础配置
    write_base_config

    for i in $(seq 1 $NUM_IP); do
        suffix=$(printf '%04x:%04x:%04x:%04x' $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)) $((RANDOM%65536)))
        ipv6="$PREFIX:$suffix"
        port=$((BASE_PORT + i - 1))

        echo "[$ipv6]:$port:$FIXED_USER:$FIXED_PASS" >> $USER_PASS_FILE

        echo "auth strong $PREFIX_TAG" >> $CONFIG_FILE
        echo "allow $FIXED_USER $PREFIX_TAG" >> $CONFIG_FILE
        echo "socks -6 -p$port -i0.0.0.0 -e$ipv6 -a $PREFIX_TAG" >> $CONFIG_FILE

        ip -6 addr add $ipv6 dev $INTERFACE
    done
}

function start_3proxy() {
    echo "启动 3proxy 服务..."
    pkill 3proxy >/dev/null 2>&1
    nohup 3proxy $CONFIG_FILE >/dev/null 2>&1 &
    sleep 1
    echo "3proxy 已启动。"
}

function stop_3proxy() {
    echo "停止 3proxy 服务..."
    pkill 3proxy
    echo "3proxy 已停止。"
}

function unload_ipv6() {
    echo "卸载绑定的 IPv6 地址..."
    grep '\[' $USER_PASS_FILE | cut -d[ -f2 | cut -d] -f1 | while read ip; do
        ip -6 addr del $ip dev $INTERFACE
    done
    echo "IPv6 地址已卸载。"
}

function show_status() {
    if pgrep 3proxy >/dev/null; then
        echo "✅ 3proxy 正在运行中。"
    else
        echo "❌ 3proxy 未运行。"
    fi
}

case "$1" in
    start)
        check_3proxy_installed
        generate_ipv6_socks5
        start_3proxy
        echo "✅ 已生成 Socks5 列表：$USER_PASS_FILE"
        ;;
    stop)
        stop_3proxy
        ;;
    status)
        show_status
        ;;
    unload)
        unload_ipv6
        ;;
    *)
        echo "用法："
        echo "  sudo $0 start   # 绑定IP并启动代理"
        echo "  sudo $0 stop    # 停止代理服务"
        echo "  sudo $0 status  # 查看服务状态"
        echo "  sudo $0 unload  # 卸载绑定的IPv6"
        ;;
esac
