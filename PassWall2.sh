#!/bin/sh
clear

echo "=============================================="
echo " PassWall2 AX6S FINAL Installer"
echo " Target: Xiaomi Redmi Router AX6S"
echo " OpenWrt 24.x compatible"
echo "=============================================="

### Hardware detection ###
MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"
BOARD="$(cat /tmp/sysinfo/board_name 2>/dev/null)"
ARCH="$(opkg print-architecture | awk 'NR==1{print $2}')"
RAM_MB="$(free | awk '/Mem:/ {print int($2/1024)}')"
DISK_MB="$(df /overlay | awk 'NR==2 {print int($4/1024)}')"

echo "[HW] Model : $MODEL"
echo "[HW] Board : $BOARD"
echo "[HW] Arch  : $ARCH"
echo "[HW] RAM   : ${RAM_MB}MB (available)"
echo "[HW] Disk  : ${DISK_MB}MB free"

### Profile decision ###
PROFILE="SAFE"

case "$MODEL" in
  *AX6S*)
    PROFILE="HIGH"
    echo "[INFO] AX6S detected → Forcing HIGH profile"
    ;;
  *)
    if [ "$RAM_MB" -ge 180 ]; then
      PROFILE="MID"
    fi
    ;;
esac

echo "[INFO] Profile selected: $PROFILE"

### Remove conflicts ###
echo "[1/9] Removing conflicting packages..."
opkg remove openclash clash luci-app-ssr-plus luci-app-passwall passwall 2>/dev/null

### Update feeds ###
echo "[2/9] Updating opkg feeds..."
opkg update || exit 1

### Base dependencies ###
echo "[3/9] Installing base dependencies..."
opkg install \
  ca-bundle ca-certificates \
  ipset ip-full \
  kmod-tun kmod-inet-diag \
  curl wget unzip \
  dnsmasq-full \
  luci-compat || exit 1

### nftables + TProxy ###
echo "[4/9] Installing nftables TProxy modules..."
opkg install \
  kmod-nft-core \
  kmod-nft-socket \
  kmod-nft-tproxy || true

### Core (Xray) ###
echo "[5/9] Installing xray-core..."
opkg install xray-core || exit 1

### PassWall2 ###
echo "[6/9] Installing PassWall2..."
opkg install \
  luci-app-passwall2 \
  passwall2 \
  chinadns-ng \
  dns2socks \
  microsocks || exit 1

### DNS Optimization ###
echo "[7/9] Configuring DNS..."
uci set dhcp.@dnsmasq[0].noresolv='1'
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'
uci set dhcp.@dnsmasq[0].cachesize='10000'
uci commit dhcp

### PassWall rules ###
echo "[8/9] Applying smart routing rules..."
uci set passwall2.@global[0].tcp_proxy_mode='gfwlist'
uci set passwall2.@global[0].udp_proxy_mode='gfwlist'
uci set passwall2.@global[0].chn_list='1'
uci set passwall2.@global[0].chnroute='1'
uci set passwall2.@global[0].proxy_mode='global'

if [ "$PROFILE" = "HIGH" ]; then
  uci set passwall2.@global[0].fake_dns='1'
  uci set passwall2.@global[0].tls_fragment='1'
  uci set passwall2.@global[0].tcp_fast_open='1'
fi

uci commit passwall2

### Kernel hardening ###
echo "[9/9] Kernel & DPI hardening..."
sysctl -w net.ipv4.tcp_fastopen=3
sysctl -w net.ipv4.tcp_mtu_probing=1
sysctl -w net.ipv4.icmp_ratelimit=0
sysctl -w net.ipv4.conf.all.rp_filter=0

### DPI Detection log ###
LOG="/var/log/passwall-dpi.log"
echo "[$(date)] DPI detection enabled (AX6S)" >> "$LOG"
iptables -A OUTPUT -p tcp --tcp-flags RST RST -j LOG \
  --log-prefix "DPI_RST: " --log-level 4 2>/dev/null

### Restart services ###
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart
/etc/init.d/passwall2 restart
/etc/init.d/uhttpd restart

echo "=============================================="
echo " PassWall2 FINAL installation completed"
echo " Profile : $PROFILE"
echo " LuCI → Services → PassWall2"
echo "=============================================="
