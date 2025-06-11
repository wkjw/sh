#!/bin/bash

# 配置项
IFACE="eth0"
THREEPROXY_CFG="/etc/3proxy/3proxy.cfg"
LOG_DIR="/var/log/3proxy"
OUTPUT_FILE="/etc/3proxy/socks5_list.txt"

USERNAME="user1"
PASSWORD="pass1"

NUM_IP=100
START_PORT=1080

# 用法提示
usage() {
  echo "用法: $0 {start|stop|unload|status}"
  echo "  start  - 绑定IPv6，生成配置，启动3proxy"
  echo "  stop   - 停止3proxy服务"
  echo "  unload - 卸载绑定的IPv6地址"
  echo "  status - 查看3proxy服务状态"
  exit 1
}

if [ $# -ne 1 ]; then
  usage
fi

ACTION=$1

# 生成随机IPv6地址函数
generate_ipv6() {
  local prefix=$1
  local suffix=""
  for i in {1..4}; do
    part=$(printf '%04x' $((RANDOM % 65536)))
    suffix="${suffix}${part}:"
  done
  suffix=${suffix%:}
  echo "${prefix}::${suffix}"
}

# 获取IPv6前缀
get_ipv6_prefix() {
  prefix=$(ip -6 addr show dev $IFACE scope global | grep "inet6" | head -n1 | awk '{print $2}' | cut -d: -f1-4)
  echo "$prefix"
}

# 绑定IPv6地址
bind_ipv6() {
  local prefix=$1
  echo "开始绑定 $NUM_IP 个 IPv6 地址..."
  for ((i=0; i<NUM_IP; i++)); do
    ip=$(generate_ipv6 $prefix)
    ip_cidr="${ip}/64"
    sudo ip -6 addr add $ip_cidr dev $IFACE 2>/dev/null || echo "$ip_cidr 可能已绑定"
    IPV6_ADDRS[i]=$ip
  done
  echo "绑定完毕。"
}

# 卸载IPv6地址
unload_ipv6() {
  local prefix=$1
  echo "开始卸载 $NUM_IP 个 IPv6 地址..."
  for ((i=0; i<NUM_IP; i++)); do
    ip=$(generate_ipv6 $prefix)
    ip_cidr="${ip}/64"
    sudo ip -6 addr del $ip_cidr dev $IFACE 2>/dev/null && echo "卸载 $ip_cidr"
  done
  echo "卸载完成。"
}

# 生成3proxy配置并启动
generate_and_start_3proxy() {
  echo "生成3proxy配置文件..."
  sudo mkdir -p $LOG_DIR
  sudo tee $THREEPROXY_CFG > /dev/null <<EOF
auth strong
users $USERNAME:CL:$PASSWORD

log $LOG_DIR/3proxy.log
logformat "L%d-%m-%Y %H:%M:%S %U %C:%c %R:%r %O %I %h %T"
EOF

  # 清空代理列表文件
  sudo bash -c "echo -n > $OUTPUT_FILE"

  for ((i=0; i<NUM_IP; i++)); do
    port=$((START_PORT + i))
    out_ip=${IPV6_ADDRS[$i]}
    sudo tee -a $THREEPROXY_CFG > /dev/null <<EOF
socks -6 -p$port -i:: -e$out_ip
EOF
    echo "[$out_ip]:$port:$USERNAME:$PASSWORD" | sudo tee -a $OUTPUT_FILE > /dev/null
  done

  echo "重启3proxy服务..."
  sudo systemctl restart 3proxy

  echo "完成！启动了 $NUM_IP 个 SOCKS5 代理端口，认证用户名密码如下："
  echo "用户名: $USERNAME"
  echo "密码: $PASSWORD"
  echo "端口范围: $START_PORT - $((START_PORT + NUM_IP -1))"
  echo "代理列表文件：$OUTPUT_FILE"
  echo "代理列表内容："
  sudo cat $OUTPUT_FILE
}

# 读取已绑定的IP（这里简单用文件记录，防止reload时地址变）
IP_LIST_FILE="/etc/3proxy/ipv6_list.txt"

save_ip_list() {
  echo "${IPV6_ADDRS[@]}" | tr ' ' '\n' | sudo tee $IP_LIST_FILE > /dev/null
}

load_ip_list() {
  if [ -f $IP_LIST_FILE ]; then
    mapfile -t IPV6_ADDRS < $IP_LIST_FILE
  else
    echo "IP列表文件不存在，请先运行start"
    exit 1
  fi
}

case $ACTION in
  start)
    PREFIX=$(get_ipv6_prefix)
    if [ -z "$PREFIX" ]; then
      echo "未检测到 $IFACE 的 IPv6 地址或前缀，退出。"
      exit 1
    fi
    echo "检测到 IPv6 前缀: $PREFIX::/64"
    bind_ipv6 $PREFIX
    save_ip_list
    generate_and_start_3proxy
    ;;
  stop)
    echo "停止3proxy服务..."
    sudo systemctl stop 3proxy
    ;;
  unload)
    load_ip_list
    echo "开始卸载已绑定的IPv6地址..."
    for ip in "${IPV6_ADDRS[@]}"; do
      ip_cidr="${ip}/64"
      sudo ip -6 addr del $ip_cidr dev $IFACE 2>/dev/null && echo "卸载 $ip_cidr"
    done
    sudo rm -f $IP_LIST_FILE $OUTPUT_FILE
    ;;
  status)
    sudo systemctl status 3proxy
    ;;
  *)
    usage
    ;;
esac
