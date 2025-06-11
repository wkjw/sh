#!/bin/bash

# === 基本配置 ===
START_PORT=10000
USERNAME="w001"
PASSWORD="w001"
INTERFACE="eth0"

# === 安装 dante-server ===
apt update && apt install -y dante-server

# === 获取公网 IPv6 列表 ===
IPV6_LIST=($(ip -o -6 addr show dev "$INTERFACE" scope global | awk '{print $4}' | cut -d/ -f1 | grep -v '::1'))

if [ ${#IPV6_LIST[@]} -eq 0 ]; then
    echo "❌ 未找到公网 IPv6 地址"
    exit 1
fi

echo "✅ 检测到 ${#IPV6_LIST[@]} 个 IPv6 地址"

# === 清空配置并生成 socks5_list.txt 文件 ===
> /etc/danted.conf
> socks5_list.txt

# === 逐个配置 ===
for ((i = 0; i < ${#IPV6_LIST[@]}; i++)); do
    PORT=$((START_PORT + i))
    IPV6=${IPV6_LIST[$i]}

cat <<EOT >> /etc/danted.conf
logoutput: /var/log/danted-$PORT.log
internal: $INTERFACE port = $PORT
external: $IPV6
method: username
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: connect
    log: connect disconnect error
}

EOT

    # 写入 socks5 代理信息
    echo "[${IPV6}]:${PORT}:${USERNAME}:${PASSWORD}" >> socks5_list.txt
done

# === 创建认证用户 ===
useradd -M -s /usr/sbin/nologin $USERNAME 2>/dev/null
echo "$USERNAME:$PASSWORD" | chpasswd

# === 重启服务并设置开机自启 ===
systemctl restart danted
systemctl enable danted

# === 输出信息 ===
echo -e "\n🎉 所有 Socks5 代理配置完成"
echo "📁 已保存列表到：$(realpath socks5_list.txt)"
cat socks5_list.txt
