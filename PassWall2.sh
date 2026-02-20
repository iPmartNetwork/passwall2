#!/bin/sh
clear

echo "=============================================="
echo " PassWall2 AX6S Enterprise Installer"
echo " Target: Xiaomi Redmi Router AX6S"
echo "=============================================="

### Hardware info ###
MODEL=$(cat /tmp/sysinfo/model)
RAM_MB=$(free | awk '/Mem:/ {print int($2/1024)}')
ARCH=$(opkg print-architecture | awk 'NR==1{print $2}')

echo "[HW] Model: $MODEL"
echo "[HW] RAM: ${RAM_MB}MB"
echo "[HW] Arch: $ARCH"

### Sanity check ###
if [ "$RAM_MB" -lt 256 ]; then
  echo "[ERROR] This profile requires >=256MB RAM"
  exit 1
fi

### Remove conflicts ###
echo "[1/9] Removing conflicts..."
opkg remove openclash clash luci-app-ssr-plus luci-app-passwall passwall 2>/dev/null

### Update ###
echo "[2/9] Updating feeds..."
opkg update || exit 1

### Base deps ###
echo "[3/9] Installing base dependencies..."
opkg install \
  ca-bundle ca-certificates \
  ipset ip-full \
  kmod-tun kmod-inet-diag \
  curl wget unzip \
  dnsmasq-full \
  luci-compat

### TProxy / nft ###
echo "[4/9] Installing nftables TProxy..."
opkg install \
  kmod-nft-tproxy \
  kmod-nft-socket \
  kmod-nft-core

### Core ###
echo "[5/9] Installing Xray-core..."
opkg install xray-core || exit 1

### PassWall2 ###
echo "[6/9] Installing PassWall2..."
opkg install \
  luci-app-passwall2 \
  passwall2 \
  chinadns-ng \
  dns2socks \
  microsocks

### DNS (FakeDNS ready) ###
echo "[7/9] Optimizing DNS..."
uci set dhcp.@dnsmasq[0].noresolv='1'
uci add_list dhcp.@dnsmasq[0].server='127.0.0.1#5353'
uci set dhcp.@dnsmasq[0].cachesize='10000'
uci commit dhcp

### Auto Rule (IR / CN bypass) ###
echo "[8/9] Applying smart rules..."
uci set passwall2.@global[0].tcp_proxy_mode='gfwlist'
uci set passwall2.@global[0].udp_proxy_mode='gfwlist'
uci set passwall2.@global[0].chn_list='1'
uci set passwall2.@global[0].chnroute='1'
uci set passwall2.@global[0].proxy_mode='global'
uci commit passwall2

### DPI Hardening ###
echo "[9/9] DPI Hardening..."
uci set passwall2.@global[0].tls_fragment='1'
uci set passwall2.@global[0].tcp_fast_open='1'
uci set passwall2.@global[0].fake_dns='1'
uci commit passwall2

### Kernel tuning ###
sysctl -w net.ipv4.tcp_fastopen=3
sysctl -w net.ipv4.tcp_mtu_probing=1
sysctl -w net.ipv4.icmp_ratelimit=0
sysctl -w net.ipv4.conf.all.rp_filter=0

### DPI detection log ###
LOG="/var/log/passwall-dpi.log"
echo "[$(date)] DPI detection enabled (AX6S)" >> $LOG
iptables -A OUTPUT -p tcp --tcp-flags RST RST -j LOG --log-prefix "DPI_RST: " --log-level 4

### Restart ###
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart
/etc/init.d/passwall2 restart
/etc/init.d/uhttpd restart

echo "=============================================="
echo " PassWall2 Enterprise READY on AX6S"
echo " LuCI → Services → PassWall2"
echo "=============================================="
