DEFAULT_START_PORT=20000                         # 默认起始端口
DEFAULT_SOCKS_USERNAME="userb"                   # 默认 SOCKS 账号
DEFAULT_SOCKS_PASSWORD="passwordb"               # 默认 SOCKS 密码
DEFAULT_UUID=$(cat /proc/sys/kernel/random/uuid) # 默认随机 UUID
DEFAULT_WS_PATH="/ws"                            # 默认 WebSocket 路径
DEFAULT_SHADOWSOCKS_PASSWORD="password_ss"       # 默认 Shadowsocks 密码
DEFAULT_SHADOWSOCKS_METHOD="chacha20-ietf-poly1305"          # 默认 Shadowsocks 加密方式

IPV6_ADDRESSES=($(ip -6 addr show scope global | grep inet6 | awk '{print $2}' | cut -d'/' -f1))  # 获取所有 IPv6 地址

install_xray() {
    echo "安装 Xray..."
    apt-get install unzip -y || yum install unzip -y
    wget https://github.com/XTLS/Xray-core/releases/download/v1.8.3/Xray-linux-64.zip
    unzip Xray-linux-64.zip
    mv xray /usr/local/bin/xrayL
    chmod +x /usr/local/bin/xrayL
    cat <<EOF >/etc/systemd/system/xrayL.service
[Unit]
Description=XrayL Service
After=network.target

[Service]
ExecStart=/usr/local/bin/xrayL -c /etc/xrayL/config.toml
Restart=on-failure
User=nobody
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xrayL.service
    systemctl start xrayL.service
    echo "Xray 安装完成."
}

config_xray() {
    config_type=$1
    mkdir -p /etc/xrayL
    if [ "$config_type" != "socks" ] && [ "$config_type" != "vmess" ] && [ "$config_type" != "shadowsocks" ]; then
        echo "类型错误！仅支持 socks、vmess 和 shadowsocks."
        exit 1
    fi

    read -p "起始端口 (默认 $DEFAULT_START_PORT): " START_PORT
    START_PORT=${START_PORT:-$DEFAULT_START_PORT}
    
    if [ "$config_type" == "socks" ]; then
        read -p "SOCKS 账号 (默认 $DEFAULT_SOCKS_USERNAME): " SOCKS_USERNAME
        SOCKS_USERNAME=${SOCKS_USERNAME:-$DEFAULT_SOCKS_USERNAME}

        read -p "SOCKS 密码 (默认 $DEFAULT_SOCKS_PASSWORD): " SOCKS_PASSWORD
        SOCKS_PASSWORD=${SOCKS_PASSWORD:-$DEFAULT_SOCKS_PASSWORD}
    elif [ "$config_type" == "vmess" ]; then
        read -p "UUID (默认随机): " UUID
        UUID=${UUID:-$DEFAULT_UUID}
        read -p "WebSocket 路径 (默认 $DEFAULT_WS_PATH): " WS_PATH
        WS_PATH=${WS_PATH:-$DEFAULT_WS_PATH}
    elif [ "$config_type" == "shadowsocks" ]; then
        read -p "Shadowsocks 密码 (默认 $DEFAULT_SHADOWSOCKS_PASSWORD): " SS_PASSWORD
        SS_PASSWORD=${SS_PASSWORD:-$DEFAULT_SHADOWSOCKS_PASSWORD}
        read -p "Shadowsocks 加密方式 (默认 $DEFAULT_SHADOWSOCKS_METHOD): " SS_METHOD
        SS_METHOD=${SS_METHOD:-$DEFAULT_SHADOWSOCKS_METHOD}
    fi

    config_content=""
    port_counter=$START_PORT  # 端口计数器

    for ((i = 0; i < ${#IPV6_ADDRESSES[@]}; i++)); do
        ipv6=${IPV6_ADDRESSES[i]}
        port=$((port_counter + i))  # 计算当前节点的端口
        
        if [ "$config_type" == "shadowsocks" ]; then
            config_content+="- { name: $ipv6, type: ss, server: \"$ipv6\", port: $port, cipher: $SS_METHOD, password: $SS_PASSWORD, udp: true }\n"
        fi
    done

    # 输出配置内容
    echo -e "$config_content"

    # 保存配置文件
    echo -e "$config_content" >/etc/xrayL/config.toml

    # 重启 Xray 服务
    systemctl restart xrayL.service
    systemctl --no-pager status xrayL.service

    echo ""
    echo "生成 $config_type 配置完成"
    echo "起始端口: $START_PORT"
    echo "结束端口: $(($START_PORT + ${#IPV6_ADDRESSES[@]} - 1))"
    if [ "$config_type" == "socks" ]; then
        echo "SOCKS账号: $SOCKS_USERNAME"
        echo "SOCKS密码: $SOCKS_PASSWORD"
    elif [ "$config_type" == "vmess" ]; then
        echo "UUID: $UUID"
        echo "WebSocket路径: $WS_PATH"
    elif [ "$config_type" == "shadowsocks" ]; then
        echo "Shadowsocks密码: $SS_PASSWORD"
        echo "Shadowsocks加密方式: $SS_METHOD"
    fi
    echo ""
}

main() {
    [ -x "$(command -v xrayL)" ] || install_xray
    if [ $# -eq 1 ]; then
        config_type="$1"
    else
        read -p "选择生成的节点类型 (socks/vmess/shadowsocks): " config_type
    fi

    if [ "$config_type" == "vmess" ]; then
        config_xray "vmess"
    elif [ "$config_type" == "socks" ]; then
        config_xray "socks"
    elif [ "$config_type" == "shadowsocks" ]; then
        config_xray "shadowsocks"
    else
        echo "未正确选择类型，使用默认 socks 配置."
        config_xray "socks"
    fi
}

main "$@"
