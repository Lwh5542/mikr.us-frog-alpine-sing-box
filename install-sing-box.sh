#!/bin/ash
# 严格按你的步骤执行；所有日志全量输出；先跑 WARP，再输出导入链接与二维码并保存
set -x

# —— 交互输入 —— #
printf "请输入域名: "
read DOMAIN

printf "请输入 Nginx 暴露端口(用于 VLESS，默认2053): "
read NGINX_VLESS_PORT; [ -z "$NGINX_VLESS_PORT" ] && NGINX_VLESS_PORT=2053
printf "请输入 Nginx 暴露端口(用于 VMESS，默认2083): "
read NGINX_VMESS_PORT; [ -z "$NGINX_VMESS_PORT" ] && NGINX_VMESS_PORT=2083
printf "请输入 Nginx 暴露端口(用于 TROJAN，默认2087): "
read NGINX_TROJAN_PORT; [ -z "$NGINX_TROJAN_PORT" ] && NGINX_TROJAN_PORT=2087

printf "请输入 Sing-Box 监听端口(用于 VLESS，默认3001): "
read SBOX_VLESS_PORT; [ -z "$SBOX_VLESS_PORT" ] && SBOX_VLESS_PORT=3001
printf "请输入 Sing-Box 监听端口(用于 VMESS，默认3002): "
read SBOX_VMESS_PORT; [ -z "$SBOX_VMESS_PORT" ] && SBOX_VMESS_PORT=3002
printf "请输入 Sing-Box 监听端口(用于 TROJAN，默认3003): "
read SBOX_TROJAN_PORT; [ -z "$SBOX_TROJAN_PORT" ] && SBOX_TROJAN_PORT=3003

# —— 自定义节点名称 —— #
printf "请输入 VLESS 节点名称(默认 vless-ws): "
read NAME_VLESS; [ -z "$NAME_VLESS" ] && NAME_VLESS="vless-ws"
printf "请输入 VMESS 节点名称(默认 vmess-ws): "
read NAME_VMESS; [ -z "$NAME_VMESS" ] && NAME_VMESS="vmess-ws"
printf "请输入 TROJAN 节点名称(默认 trojan-ws): "
read NAME_TROJAN; [ -z "$NAME_TROJAN" ] && NAME_TROJAN="trojan-ws"

# —— 前期安装准备 —— #
apk update
apk upgrade
apk add wget
apk add libqrencode-tools
apk add openssl
apk add nginx
rc-service nginx start
rc-update add nginx default

# —— 证书相关 —— #
apk add curl
curl https://get.acme.sh | sh
ln -s ~/.acme.sh/acme.sh /usr/local/bin/acme.sh
acme.sh --set-default-ca --server letsencrypt

# —— 添加源（查看-插入-查看）—— #
cat /etc/apk/repositories
EDGE_LINE="https://dl-cdn.alpinelinux.org/alpine/edge/community"
grep -qxF "$EDGE_LINE" /etc/apk/repositories || echo "$EDGE_LINE" >> /etc/apk/repositories
cat /etc/apk/repositories

# —— 先单独安装 sing-box，设置自启 —— #
apk update
apk add sing-box
rc-update add sing-box default

# —— 移除 edge/community（查看-移除-查看）—— #
cat /etc/apk/repositories
sed -i "\|^$EDGE_LINE$|d" /etc/apk/repositories
cat /etc/apk/repositories

# —— 创建 ACME 目录（仅此一个）—— #
mkdir -p /var/www/acme-challenges

# —— 写入仅80端口的 Nginx 配置（用于申请证书）—— #
NGINX_CONF="/etc/nginx/http.d/${DOMAIN}.conf"
cat > "$NGINX_CONF" <<EOF
server {
    listen [::]:80;
    server_name ${DOMAIN};

    # ACME
    location /.well-known/acme-challenge/ {
        root /var/www/acme-challenges;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF

# —— 证书申请前：nginx -t → reload → cat —— #
nginx -t
rc-service nginx reload
cat "/etc/nginx/http.d/${DOMAIN}.conf"

# —— 申请证书 —— #
acme.sh --issue -d "${DOMAIN}" --webroot /var/www/acme-challenges --keylength ec-256

# —— 删除80-only配置并检查 —— #
rm -rf "/etc/nginx/http.d/${DOMAIN}.conf"
ls /etc/nginx/http.d/

# —— 新建完整反代配置（VLESS/VMESS/TROJAN + map）—— #
cat > "$NGINX_CONF" <<EOF
server {
    listen [::]:80;
    server_name ${DOMAIN};

    # ACME
    location /.well-known/acme-challenge/ {
        root /var/www/acme-challenges;
    }

    location / {
        root /var/www/html;
        index index.html;
    }
}

map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }

server {
    listen [::]:${NGINX_VLESS_PORT} ssl;
    http2 on;
    server_name ${DOMAIN};

    ssl_certificate     /root/.acme.sh/${DOMAIN}_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key;

    ssl_session_timeout 1d;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location = /vless {
        proxy_pass         http://127.0.0.1:${SBOX_VLESS_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection \$connection_upgrade;
        proxy_set_header   Host \$host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location / { return 404; }
}

server {
    listen [::]:${NGINX_VMESS_PORT} ssl;
    http2 on;
    server_name ${DOMAIN};

    ssl_certificate     /root/.acme.sh/${DOMAIN}_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key;

    ssl_session_timeout 1d;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location = /vmess {
        proxy_pass         http://127.0.0.1:${SBOX_VMESS_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection \$connection_upgrade;
        proxy_set_header   Host \$host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location / { return 404; }
}

server {
    listen [::]:${NGINX_TROJAN_PORT} ssl;
    http2 on;
    server_name ${DOMAIN};

    ssl_certificate     /root/.acme.sh/${DOMAIN}_ecc/fullchain.cer;
    ssl_certificate_key /root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key;

    ssl_session_timeout 1d;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location = /trojan {
        proxy_pass         http://127.0.0.1:${SBOX_TROJAN_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection \$connection_upgrade;
        proxy_set_header   Host \$host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location / { return 404; }
}
EOF

# —— 插入完整配置后：cat → nginx -t → reload —— #
cat "/etc/nginx/http.d/${DOMAIN}.conf"
nginx -t
rc-service nginx reload

# —— Sing-Box：打印 → 删除默认 —— #
ls /etc/sing-box/
rm -rf /etc/sing-box/config.json

# —— 删除后再检查一遍 —— #
ls /etc/sing-box/

# —— 生成 UUID/密码 → 写配置 —— #
VMESS_UUID="$(cat /proc/sys/kernel/random/uuid)"
VLESS_UUID="$(cat /proc/sys/kernel/random/uuid)"
TROJAN_PWD="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 18)"

cat > /etc/sing-box/config.json <<EOF
{
  "log": { "level": "info", "timestamp": true },

  "dns": {
    "servers": [
      { "type": "https", "tag": "cf4", "server": "1.1.1.1", "detour": "direct-warp" },
      { "type": "https", "tag": "cf6", "server": "2606:4700:4700::1111" }
    ],
    "rules": [
      { "query_type": ["A"], "server": "cf4" },
      { "query_type": ["AAAA"], "server": "cf6" }
    ],
    "strategy": "prefer_ipv6"
  },

  "inbounds": [
    {
      "type": "vless",
      "tag": "in-vless-ws",
      "listen": "127.0.0.1",
      "listen_port": ${SBOX_VLESS_PORT},
      "users": [ { "uuid": "${VLESS_UUID}" } ],
      "transport": { "type": "ws", "path": "/vless" }
    },
    {
      "type": "vmess",
      "tag": "in-vmess-ws",
      "listen": "127.0.0.1",
      "listen_port": ${SBOX_VMESS_PORT},
      "users": [ { "uuid": "${VMESS_UUID}", "alterId": 0 } ],
      "transport": { "type": "ws", "path": "/vmess" }
    },
    {
      "type": "trojan",
      "tag": "in-trojan-ws",
      "listen": "127.0.0.1",
      "listen_port": ${SBOX_TROJAN_PORT},
      "users": [ { "password": "${TROJAN_PWD}" } ],
      "transport": { "type": "ws", "path": "/trojan" }
    }
  ],

  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-v6",
      "inet6_bind_address": "::",
      "domain_resolver": { "server": "cf6", "strategy": "prefer_ipv6" }
    },
    {
      "type": "direct",
      "tag": "direct-warp",
      "bind_interface": "warp",
      "domain_resolver": { "server": "cf4" }
    },
    { "type": "block", "tag": "block" }
  ],

  "route": {
    "default_domain_resolver": { "server": "cf6", "strategy": "prefer_ipv6" },
    "rules": [
      { "action": "hijack-dns", "protocol": "dns" },
      { "action": "resolve" },
      { "ip_cidr": ["::/0"], "outbound": "direct-v6" },
      { "ip_cidr": ["0.0.0.0/0"], "outbound": "direct-warp" }
    ],
    "final": "direct-warp"
  }
}
EOF

# —— 写入完成后立刻 cat 查看 —— #
cat /etc/sing-box/config.json

# —— 运行 WARP 菜单脚本（需要 bash；若无则装）—— #
command -v bash >/dev/null 2>&1 || apk add bash
wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh

# —— 生成导入链接与二维码并保存（名称可自定义） —— #
VMESS_JSON=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","type":"none","host":"%s","path":"/vmess","tls":"tls","sni":"%s"}' \
  "$NAME_VMESS" "$DOMAIN" "$NGINX_VMESS_PORT" "$VMESS_UUID" "$DOMAIN" "$DOMAIN")
VMESS_B64=$(printf "%s" "$VMESS_JSON" | base64 | tr -d '\n')
VMESS_URL="vmess://${VMESS_B64}"

VLESS_URL="vless://${VLESS_UUID}@${DOMAIN}:${NGINX_VLESS_PORT}?encryption=none&security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2Fvless#${NAME_VLESS}"
TROJAN_URL="trojan://${TROJAN_PWD}@${DOMAIN}:${NGINX_TROJAN_PORT}?security=tls&sni=${DOMAIN}&type=ws&host=${DOMAIN}&path=%2Ftrojan#${NAME_TROJAN}"

INFO_DIR="/root/singbox"
INFO_FILE="${INFO_DIR}/节点信息.txt"
mkdir -p "$INFO_DIR"

{
  echo "================= 导入链接 ================="
  echo "VLESS:  ${VLESS_URL}"
  echo "VMess:  ${VMESS_URL}"
  echo "Trojan: ${TROJAN_URL}"
  echo "==========================================="
  echo
  echo "[VLESS 二维码]"
  qrencode -t ASCIIi -m 1 "${VLESS_URL}"
  echo
  echo "[VMess 二维码]"
  qrencode -t ASCIIi -m 1 "${VMESS_URL}"
  echo
  echo "[Trojan 二维码]"
  qrencode -t ASCIIi -m 1 "${TROJAN_URL}"
} | tee "${INFO_FILE}"

# —— 启动 sing-box 并显示状态 —— #
rc-service sing-box start
rc-service sing-box status

exit 0
