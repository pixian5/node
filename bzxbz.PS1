#VLESS+XHTTP+Reality、VLESS+TCP+Reality（XTLS-Vision）、Hysteria2、VLESS+XHTTP+TLS（CDN）
cat > /root/ultimate_xbz_2026_fixed.sh << 'ULTIMATE_EOF'
#!/bin/bash

# ================= 配置变量区 =================
MY_SUB="o10"                                       
DOMAIN="xbz.email"                                 
CF_TOKEN="Wfzj8EiELSTTnKbctM9qTuyv8ga23WTW3W-Lj3KJ" 

MY_GUID="41d4f8b3-2a45-4531-a33b-938e2eebb939"
HY2_OBFS="sbxbz19890604"
PORT=443
PORT_CDN=2083   
PORT_XHTTP_REALITY=2053                                   
DEST_DOMAIN="www.microsoft.com"

SUB_DOMAIN="${MY_SUB}.${DOMAIN}"                   
VX_DOMAIN="${MY_SUB}vx.${DOMAIN}"                  

SBOX_CONF="/etc/bz/config.json"                    
XBZ_CONF="/etc/xbz/config.json"                    
CERT_DIR="/etc/bz/certs"
BZ_BIN="/usr/local/bin/bz"                         
XBZ_BIN="/usr/local/bin/xbz"                       
REALITY_ENV="/etc/bz/reality.env"
BZ_UPD_SH="/root/bz-update.sh"
XBZ_UPD_SH="/root/xbz-update.sh"
EMAIL="${MY_SUB}@$DOMAIN"
# =============================================

# 1. 环境准备
systemctl stop bz xbz 2>/dev/null
fuser -k 443/tcp 443/udp 80/tcp 2083/tcp 2053/tcp 2>/dev/null

bootstrap_cf_deps() {
  local miss=0
  command -v curl >/dev/null 2>&1 || miss=1
  command -v jq   >/dev/null 2>&1 || miss=1

  if [ "$miss" -eq 1 ]; then
    echo "检测到缺少 curl/jq，需先最小化安装以便调用 Cloudflare API..."
    apt-get install -y curl jq ca-certificates
  fi
}
bootstrap_cf_deps

# 2. Cloudflare API 自动化
CF_API="https://api.cloudflare.com/client/v4"
IP=$(curl -s https://api.ip.sb/ip || curl -s https://checkip.amazonaws.com)
get_zone_id() {
  local zid
  zid=$(curl -s -X GET "${CF_API}/zones?name=${DOMAIN}&status=active&per_page=50" \
      -H "Authorization: Bearer ${CF_TOKEN}" \
      -H "Content-Type: application/json" | jq -r '.result[0].id // empty')
  if [ -z "$zid" ]; then
    echo "❌ 获取 ZONE_ID 失败" >&2
    return 1
  fi
  echo "$zid"
}

ZONE_ID="$(get_zone_id)" || exit 1
update_dns() {
    local name=$1 && local proxied=$2
    local rid=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$name" -H "Authorization: Bearer $CF_TOKEN" | jq -r '.result[0].id')
    local data=$(jq -n --arg type "A" --arg name "$name" --arg content "$IP" --argjson proxied $proxied '{"type":$type, "name":$name, "content":$content, "ttl":1, "proxied":$proxied}')
    if [ "$rid" != "null" ] && [ -n "$rid" ]; then
        curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$rid" -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" --data "$data" >/dev/null
    else
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" --data "$data" >/dev/null
    fi
}
update_dns "$SUB_DOMAIN" "false"
update_dns "$VX_DOMAIN" "true"

apt-get update -y
apt-get install -y openssl tar wget socat psmisc ca-certificates net-tools unzip curl jq

if command -v ufw >/dev/null; then 
    ufw allow 443/tcp; ufw allow 443/udp; ufw allow 80/tcp; 
    ufw allow $PORT_CDN/tcp; ufw allow $PORT_XHTTP_REALITY/tcp; 
fi

setup_origin_rule_batch() {
    local phase="http_request_origin"
    local rs_list=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets" -H "Authorization: Bearer $CF_TOKEN")
    local rsid=$(echo "$rs_list" | jq -r ".result[]? | select(.phase==\"$phase\") | .id")
    local rule_expr="ends_with(http.host, \"vx.${DOMAIN}\")"
    local rule_desc="域名结尾是vx.${DOMAIN} 的全部网页重定向到端口 $PORT_CDN"
    local rule_obj=$(jq -n --arg desc "$rule_desc" --arg expr "$rule_expr" --argjson port $PORT_CDN '{description: $desc, expression: $expr, action: "route", action_parameters: {origin: {port: $port}}}')
    if [ -z "$rsid" ] || [ "$rsid" == "null" ]; then
        local payload=$(jq -n --arg phase "$phase" --argjson rule "[$rule_obj]" '{"name":"default","kind":"zone","phase":$phase,"rules":$rule}')
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets" -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" --data "$payload" >/dev/null
    else
        local current_rules=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$rsid" -H "Authorization: Bearer $CF_TOKEN" | jq -c '.result.rules // []')
        if ! echo "$current_rules" | jq -e --arg desc "$rule_desc" --arg expr "$rule_expr" '.[] | select(.description == $desc or .expression == $expr)' >/dev/null; then
            local updated_rules=$(echo "$current_rules" | jq -c --argjson newrule "$rule_obj" '. + [$newrule]')
            curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$rsid" -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" --data "{\"rules\": $updated_rules}" >/dev/null
        fi
    fi
}
setup_origin_rule_batch

# 3. 安装内核
cat > "$BZ_UPD_SH" << 'BZ_UPD_SHEOF'
#!/bin/bash
BZ_BIN="/usr/local/bin/bz"
LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/v//')
ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && S_ARCH="amd64" || S_ARCH="arm64"
tmp=$(mktemp -d); curl -Lo "$tmp/sb.tar.gz" "https://github.com/SagerNet/sing-box/releases/download/v${LATEST}/sing-box-${LATEST}-linux-${S_ARCH}.tar.gz"
if [ -s "$tmp/sb.tar.gz" ]; then
    tar -zxf "$tmp/sb.tar.gz" -C "$tmp" && mv "$tmp"/sing-box-*/sing-box $BZ_BIN && chmod +x $BZ_BIN
fi
rm -rf "$tmp"
BZ_UPD_SHEOF

cat > "$XBZ_UPD_SH" << 'XBZ_UPD_SHEOF'
#!/bin/bash
XBZ_BIN="/usr/local/bin/xbz"
LATEST=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && X_ARCH="64" || X_ARCH="arm64-v8a"
tmp=$(mktemp -d); curl -Lo "$tmp/xr.zip" "https://github.com/XTLS/Xray-core/releases/download/${LATEST}/Xray-linux-${X_ARCH}.zip"
if [ -s "$tmp/xr.zip" ]; then
    unzip -q "$tmp/xr.zip" -d "$tmp" && mv "$tmp/xray" $XBZ_BIN && chmod +x $XBZ_BIN
fi
rm -rf "$tmp"
XBZ_UPD_SHEOF
chmod +x "$BZ_UPD_SH" "$XBZ_UPD_SH"
bash "$BZ_UPD_SH" && bash "$XBZ_UPD_SH"

# 4. Reality 密钥固化
mkdir -p /etc/bz /etc/xbz
if [ -s "$REALITY_ENV" ] && grep -q "PUBLIC_KEY=." "$REALITY_ENV"; then . "$REALITY_ENV"
else
    KEYPAIR=$($BZ_BIN generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYPAIR" | awk '/PrivateKey/ {print $2}')
    PUBLIC_KEY=$(echo "$KEYPAIR" | awk '/PublicKey/ {print $2}')
    SHORT_ID=$($BZ_BIN generate rand --hex 8)
    cat > "$REALITY_ENV" << REOF
PRIVATE_KEY=$PRIVATE_KEY
PUBLIC_KEY=$PUBLIC_KEY
SHORT_ID=$SHORT_ID
REOF
    chmod 600 "$REALITY_ENV"
fi

# 5. 证书与配置
mkdir -p "$CERT_DIR"
[ ! -f "$HOME/.acme.sh/acme.sh" ] && curl https://get.acme.sh | sh -s email="$EMAIL"
export CF_Token="$CF_TOKEN"
if [ ! -s "$CERT_DIR/server.crt" ]; then
    "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf -d "$SUB_DOMAIN" -d "$VX_DOMAIN" --keylength ec-256 --server letsencrypt
    "$HOME/.acme.sh/acme.sh" --install-cert -d "$SUB_DOMAIN" --ecc --key-file "$CERT_DIR/server.key" --fullchain-file "$CERT_DIR/server.crt" --reloadcmd "systemctl restart bz xbz"
fi

cat > "$SBOX_CONF" << CONFIG
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    { "type": "vless", "tag": "v-reality", "listen": "::", "listen_port": $PORT, "users": [{ "uuid": "$MY_GUID", "flow": "xtls-rprx-vision" }], "tls": { "enabled": true, "server_name": "$DEST_DOMAIN", "reality": { "enabled": true, "handshake": { "server": "$DEST_DOMAIN", "server_port": 443 }, "private_key": "$PRIVATE_KEY", "short_id": ["$SHORT_ID"] } } },
    { "type": "hysteria2", "tag": "hy2-in", "listen": "::", "listen_port": $PORT, "users": [{ "password": "$MY_GUID" }], "obfs": { "type": "salamander", "password": "$HY2_OBFS" }, "tls": { "enabled": true, "server_name": "$SUB_DOMAIN", "certificate_path": "$CERT_DIR/server.crt", "key_path": "$CERT_DIR/server.key" } }
  ],
  "outbounds": [{ "type": "direct" }]
}
CONFIG

cat > "$XBZ_CONF" << X_JSON
{
    "log": { "loglevel": "info" },
    "inbounds": [
        {
            "port": $PORT_CDN, "protocol": "vless", "settings": { "clients": [{ "id": "$MY_GUID" }], "decryption": "none" },
            "streamSettings": { "network": "xhttp", "security": "tls", "tlsSettings": { "certificates": [{ "certificateFile": "$CERT_DIR/server.crt", "keyFile": "$CERT_DIR/server.key" }], "serverName": "$VX_DOMAIN" }, "xhttpSettings": { "path": "/xbz-vx" } }
        },
        {
            "port": $PORT_XHTTP_REALITY, "protocol": "vless", "settings": { "clients": [{ "id": "$MY_GUID" }], "decryption": "none" },
            "streamSettings": { 
                "network": "xhttp", 
                "security": "reality", 
                "realitySettings": { "show": false, "dest": "$DEST_DOMAIN:443", "xver": 0, "serverNames": ["$DEST_DOMAIN"], "privateKey": "$PRIVATE_KEY", "shortIds": ["$SHORT_ID"] },
                "xhttpSettings": { "path": "/xbz-xr" } 
            }
        }
    ],
    "outbounds": [{ "protocol": "freedom" }]
}
X_JSON

for s in bz xbz; do
cat > /etc/systemd/system/$s.service << SVC
[Unit]
Description=$s service
After=network.target
[Service]
ExecStart=$( [ "$s" == "bz" ] && echo "$BZ_BIN run -c $SBOX_CONF" || echo "$XBZ_BIN run -c $XBZ_CONF" )
Restart=always
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
SVC
done
systemctl daemon-reload && systemctl enable bz xbz && systemctl restart bz xbz

# 6. 定时任务
(crontab -l 2>/dev/null | grep -vE "acme.sh|bz-update|xbz-update"
 echo "0 20 * * * TZ=UTC \"$HOME/.acme.sh\"/acme.sh --cron --home \"$HOME/.acme.sh\" > /dev/null"
 echo "0 21 * * * TZ=UTC $BZ_UPD_SH >/dev/null 2>&1"
 echo "0 22 * * * TZ=UTC $XBZ_UPD_SH >/dev/null 2>&1") | crontab -

# 7. 节点输出
clear
echo "=================================================================="
echo "✨ ✨ Xbz Ultimate 2026 (Added XHTTP Reality) ✨ ✨"
echo "------------------------------------------------------------------"
echo "✨ ✨ 【1】Clash Meta (Mihomo) 配置参考 ✨ ✨ "
echo ""
echo "- {name: \"Hy2-${MY_SUB}\", type: hysteria2, server: $SUB_DOMAIN, port: 443, password: $MY_GUID, obfs: salamander, obfs-password: $HY2_OBFS, sni: $SUB_DOMAIN}"
echo "- {name: \"Reality-${MY_SUB}\", type: vless, server: $SUB_DOMAIN, port: 443, uuid: $MY_GUID, network: tcp, tls: true, flow: xtls-rprx-vision, servername: $DEST_DOMAIN, reality-opts: {public-key: $PUBLIC_KEY, short-id: $SHORT_ID}, client-fingerprint: firefox}"
echo "- {name: \"XR-XHTTP-Reality-${MY_SUB}\", type: vless, server: $SUB_DOMAIN, port: $PORT_XHTTP_REALITY, uuid: $MY_GUID, network: xhttp, tls: true, servername: $DEST_DOMAIN, reality-opts: {public-key: $PUBLIC_KEY, short-id: $SHORT_ID}, xhttp-opts: {path: /xbz-xr}, client-fingerprint: firefox}"
echo "- {name: \"XHTTP-CDN-${MY_SUB}\", type: vless, server: $VX_DOMAIN, port: 443, uuid: $MY_GUID, tls: true, servername: $VX_DOMAIN, network: xhttp, xhttp-opts: {path: /xbz-vx}}"
echo ""
echo "------------------------------------------------------------------"
echo "✨ ✨ 【2】分享链接 ✨ ✨ "
echo ""
echo "hysteria2://$MY_GUID@$SUB_DOMAIN:443/?obfs=salamander&obfs-password=$HY2_OBFS&sni=$SUB_DOMAIN#Hy2-${MY_SUB}"
echo "vless://$MY_GUID@$SUB_DOMAIN:$PORT_XHTTP_REALITY?security=reality&pbk=$PUBLIC_KEY&sid=$SHORT_ID&fp=firefox&type=xhttp&path=/xbz-xr&sni=$DEST_DOMAIN#XR-XHTTP-Reality-${MY_SUB}"
echo "vless://$MY_GUID@$SUB_DOMAIN:443?security=reality&pbk=$PUBLIC_KEY&sid=$SHORT_ID&fp=firefox&type=tcp&flow=xtls-rprx-vision&sni=$DEST_DOMAIN#Reality-${MY_SUB}"
echo "vless://$MY_GUID@$VX_DOMAIN:443?encryption=none&security=tls&sni=$VX_DOMAIN&type=xhttp&path=/xbz-vx#XHTTP-CDN-${MY_SUB}"
echo ""
echo "=================================================================="
ULTIMATE_EOF

bash /root/ultimate_xbz_2026_fixed.sh