cat > /root/ultimate_xbz_2026.sh << 'ULTIMATE_EOF'
#!/bin/bash

# ================= 配置变量区 =================
#子域名前缀
MY_SUB="sg"
#域名                             
DOMAIN="xbz.email"  
   
#免流域名
ML_HOST="v9-y.douyinvod.com"  
#Cloudflare API Token                              
CF_TOKEN="Wfzj8EiELSTTnKbctM9qTuyv8ga23WTW3W-Lj3KJ" 
MY_GUID="41d4f8b3-2a45-4531-a33b-938e2eebb939"
HY2_OBFS="sbxbz19890604"
PORT=443
PORT_CDN_VX=2083   
PORT_XHTTP_REALITY=2053         
#reality伪装域名
DEST_DOMAIN="itunes.apple.com"
#（灰云）直连仅DNS的子域名
SUB_DOMAIN="${MY_SUB}.${DOMAIN}" 
#（灰云）xray的ws无tls节点用的直连域名         
VX_DOMAIN80="${MY_SUB}80.${DOMAIN}"            
#（橙云）xray的xhttp+tls节点用的cdn域名         
VX_DOMAIN="${MY_SUB}vx$PORT_CDN_VX.${DOMAIN}"                  
#singbox配置文件
SBOX_CONF="/etc/bz/config.json"   
#xray配置文件                 
XBZ_CONF="/etc/xbz/config.json"
#证书存放目录                    
CERT_DIR="/etc/bz/certs"
#singbox和xray可执行文件路径
BZ_BIN="/usr/local/bin/bz"                          
XBZ_BIN="/usr/local/bin/xbz"
#Reality密钥存放文件                        
REALITY_ENV="/etc/bz/reality.env"
#更新singbox和xray的脚本路径
BZ_UPD_SH="/root/bz-update.sh"
XBZ_UPD_SH="/root/xbz-update.sh"
EMAIL="${MY_SUB}@$DOMAIN"
echo "=================================================================" 
echo "      ✨ 1. 环境准备"
echo "            停止旧程序（如果有）"
systemctl stop bz xbz 2>/dev/null
echo "            杀掉占用端口的进程"
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
echo "开通防火墙端口：TCP：80 443 $PORT_CDN_VX $PORT_XHTTP_REALITY; UDP:443"
if command -v ufw >/dev/null; then 
    ufw allow 443/tcp; ufw allow 443/udp; ufw allow 80/tcp; 
    ufw allow $PORT_CDN_VX/tcp; ufw allow $PORT_XHTTP_REALITY/tcp; 
fi
echo "      ✅ 防火墙端口已开通"
echo "      ✨ 2. Cloudflare API 自动化"
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
update_dns "$VX_DOMAIN80" "false"
echo "      ✅ 域名 $SUB_DOMAIN、$VX_DOMAIN 和 $VX_DOMAIN80 已指向 IP：$IP"
echo "      ✅ 但是需要几十秒才能生效，趁这段时间我们安装必要软件包..."
#apt-get update -y
apt-get install -y psmisc tar unzip ca-certificates
echo "      ✅ 软件包安装完成"
echo "配置 Cloudflare 规则..."
setup_origin_rule_batch() {
    # 1. 配置 Origin Rules (回源端口)
    local phase_origin="http_request_origin"
    local rs_origin=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets" -H "Authorization: Bearer $CF_TOKEN")
    local rsid_origin=$(echo "$rs_origin" | jq -r ".result[]? | select(.phase==\"$phase_origin\") | .id")
    local rule_expr_origin="ends_with(http.host, \"$PORT_CDN_VX.${DOMAIN}\")"
    local rule_desc_origin="重定向到端口 $PORT_CDN_VX"
    local rule_obj_origin=$(jq -n --arg desc "$rule_desc_origin" --arg expr "$rule_expr_origin" --argjson port $PORT_CDN_VX '{description: $desc, expression: $expr, action: "route", action_parameters: {origin: {port: $port}}}')
    if [ -z "$rsid_origin" ] || [ "$rsid_origin" == "null" ]; then
        local p_origin=$(jq -n --arg phase "$phase_origin" --argjson rule "[$rule_obj_origin]" '{"name":"origin_rules","kind":"zone","phase":$phase,"rules":$rule}')
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets" -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" --data "$p_origin" >/dev/null
    else
        local curr_origin=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$rsid_origin" -H "Authorization: Bearer $CF_TOKEN" | jq -c '.result.rules // []')
        if ! echo "$curr_origin" | jq -e --arg expr "$rule_expr_origin" '.[] | select(.expression == $expr)' >/dev/null; then
            local up_origin=$(echo "$curr_origin" | jq -c --argjson newrule "$rule_obj_origin" '. + [$newrule]')
            curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$rsid_origin" -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" --data "{\"rules\": $up_origin}" >/dev/null
        fi
    fi

    # 2. 配置 Configuration Rules (SSL Flexible)
    local phase_config="http_config_settings"
    local rs_config=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets" -H "Authorization: Bearer $CF_TOKEN")
    local rsid_config=$(echo "$rs_config" | jq -r ".result[]? | select(.phase==\"$phase_config\") | .id")
    local rule_expr_config="ends_with(http.host, \"80.${DOMAIN}\")"
    local rule_desc_config="80端口免流域名设为Flexible"
    local rule_obj_config=$(jq -n --arg desc "$rule_desc_config" --arg expr "$rule_expr_config" '{description: $desc, expression: $expr, action: "set_config", action_parameters: {ssl: "flexible"}}')
    if [ -z "$rsid_config" ] || [ "$rsid_config" == "null" ]; then
        local p_config=$(jq -n --arg phase "$phase_config" --argjson rule "[$rule_obj_config]" '{"name":"config_rules","kind":"zone","phase":$phase,"rules":$rule}')
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets" -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" --data "$p_config" >/dev/null
    else
        local curr_config=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$rsid_config" -H "Authorization: Bearer $CF_TOKEN" | jq -c '.result.rules // []')
        if ! echo "$curr_config" | jq -e --arg expr "$rule_expr_config" '.[] | select(.expression == $expr)' >/dev/null; then
            local up_config=$(echo "$curr_config" | jq -c --argjson newrule "$rule_obj_config" '. + [$newrule]')
            curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/$rsid_config" -H "Authorization: Bearer $CF_TOKEN" -H "Content-Type: application/json" --data "{\"rules\": $up_config}" >/dev/null
        fi
    fi
}
setup_origin_rule_batch
echo "      ✅ Cloudflare 路由及 SSL 规则配置完成"

echo "      ✨ 3. 安装/更新singbox、xray最新内核"
echo "         3.1 安装/更新singbox内核"

cat > "$BZ_UPD_SH" << 'BZ_UPD_SHEOF'
#!/bin/bash
BZ_BIN="/usr/local/bin/bz"
LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/v//')
if [ -f "$BZ_BIN" ]; then
    CURRENT=$($BZ_BIN version | head -n1 | awk '{print $3}')
    if [ "$CURRENT" = "$LATEST" ]; then
        echo "      ✅ Sing-box 已是最新版本 ($LATEST)，跳过下载。"
        exit 0
    fi
fi
ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && S_ARCH="amd64" || S_ARCH="arm64"
tmp=$(mktemp -d); curl -Lo "$tmp/sb.tar.gz" "https://github.com/SagerNet/sing-box/releases/download/v${LATEST}/sing-box-${LATEST}-linux-${S_ARCH}.tar.gz"
if [ -s "$tmp/sb.tar.gz" ]; then
    tar -zxf "$tmp/sb.tar.gz" -C "$tmp" && mv "$tmp"/sing-box-*/sing-box $BZ_BIN && chmod +x $BZ_BIN
    echo "      ✅ Sing-box 已更新至 $LATEST"
fi
rm -rf "$tmp"
BZ_UPD_SHEOF
echo "         3.2 安装/更新xray内核"
cat > "$XBZ_UPD_SH" << 'XBZ_UPD_SHEOF'
#!/bin/bash
XBZ_BIN="/usr/local/bin/xbz"
LATEST=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name | sed 's/v//')
if [ -f "$XBZ_BIN" ]; then
    CURRENT=$($XBZ_BIN version | head -n1 | awk '{print $2}')
    if [ "$CURRENT" = "$LATEST" ]; then
        echo "      ✅ Xray 已是最新版本 ($LATEST)，跳过下载。"
        exit 0
    fi
fi
ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && X_ARCH="64" || X_ARCH="arm64-v8a"
tmp=$(mktemp -d); curl -Lo "$tmp/xr.zip" "https://github.com/XTLS/Xray-core/releases/download/v${LATEST}/Xray-linux-${X_ARCH}.zip"
if [ -s "$tmp/xr.zip" ]; then
    unzip -q "$tmp/xr.zip" -d "$tmp" && mv "$tmp/xray" $XBZ_BIN && chmod +x $XBZ_BIN
    echo "      ✅ Xray 已更新至 $LATEST"
fi
rm -rf "$tmp"
XBZ_UPD_SHEOF

chmod +x "$BZ_UPD_SH" "$XBZ_UPD_SH"
bash "$BZ_UPD_SH" && bash "$XBZ_UPD_SH"

echo "      ✨ 4. Reality 密钥固化"
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
echo "      ✅ Reality 密钥已固化"

echo "      ✨ 5. 配置与服务初始化"
mkdir -p "$CERT_DIR"
echo "      ✨ 5.1.1 写入singbox配置文件"
cat > "$SBOX_CONF" << CONFIG
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    { "type": "vless", "tag": "v-reality", "listen": "::", "listen_port": 8443, "users": [{ "uuid": "$MY_GUID", "flow": "xtls-rprx-vision" }], "tls": { "enabled": true, "server_name": "$DEST_DOMAIN", "reality": { "enabled": true, "handshake": { "server": "$DEST_DOMAIN", "server_port": 443 }, "private_key": "$PRIVATE_KEY", "short_id": ["$SHORT_ID"] } } },
    { "type": "hysteria2", "tag": "hy2-in", "listen": "::", "listen_port": $PORT, "users": [{ "password": "$MY_GUID" }], "obfs": { "type": "salamander", "password": "$HY2_OBFS" }, "tls": { "enabled": true, "server_name": "$SUB_DOMAIN", "certificate_path": "$CERT_DIR/server.crt", "key_path": "$CERT_DIR/server.key" } },
    { "type": "vless", "tag": "vless-ws-tls-ml", "listen": "::", "listen_port": 443, "users": [{ "uuid": "$MY_GUID" }], "tls": { "enabled": true, "server_name": "$ML_HOST", "certificate_path": "$CERT_DIR/server.crt", "key_path": "$CERT_DIR/server.key" }, "transport": { "type": "ws", "path": "/videos", "headers": { "Host": "$ML_HOST" } } }
  ],
  "outbounds": [{ "type": "direct" }]
}
CONFIG
echo "      ✅ singbox配置文件已写入"
echo "      ✨ 5.1.2 写入xray配置文件"
cat > "$XBZ_CONF" << X_JSON
{
    "log": { "loglevel": "info" },
    "inbounds": [
        {"port": 80, "protocol": "vless", "settings": {"clients": [{"id": "$MY_GUID"}], "decryption": "none"}, "streamSettings": {"network": "ws", "wsSettings": {"path": "/videos"}}},
        {"port": $PORT_CDN_VX, "protocol": "vless", "settings": {"clients": [{"id": "$MY_GUID"}], "decryption": "none"}, "streamSettings": {"network": "xhttp", "security": "tls", "tlsSettings": {"certificates": [{"certificateFile": "$CERT_DIR/server.crt", "keyFile": "$CERT_DIR/server.key"}], "serverName": "$VX_DOMAIN"}, "xhttpSettings": {"path": "/videos"}}},
        {"port": $PORT_XHTTP_REALITY, "protocol": "vless", "settings": {"clients": [{"id": "$MY_GUID"}], "decryption": "none"}, "streamSettings": {"network": "xhttp", "security": "reality", "realitySettings": {"show": false, "dest": "$DEST_DOMAIN:443", "xver": 0, "serverNames": ["$DEST_DOMAIN"], "privateKey": "$PRIVATE_KEY", "shortIds": ["$SHORT_ID"]}, "xhttpSettings": {"path": "/videos"}}}
    ],
    "outbounds": [{ "protocol": "freedom" }]
}
X_JSON
echo "      ✅ xray配置文件已写入"
echo "      ✨ 5.2 创建 Systemd 服务文件"
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
systemctl daemon-reload
echo "      ✅ Systemd 服务文件已创建并重新加载"
echo "      ✨ 5.3 申请并安装通配符 TLS 证书"
[ ! -f "$HOME/.acme.sh/acme.sh" ] && curl https://get.acme.sh | sh -s email="$EMAIL"
export CF_Token="$CF_TOKEN"
if [ ! -s "$CERT_DIR/server.crt" ]; then
    "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf -d "$DOMAIN" -d "*.$DOMAIN" --keylength ec-256 --server letsencrypt
    "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" --ecc --key-file "$CERT_DIR/server.key" --fullchain-file "$CERT_DIR/server.crt" --reloadcmd "systemctl restart bz xbz"
fi
echo "      ✅ 通配符证书已申请并安装"

systemctl enable bz xbz && systemctl restart bz xbz
echo "      ✅ Sing-box 和 Xray 服务已启动并设置开机自启"
echo "      ✨ 6. 定时任务"
(crontab -l 2>/dev/null | grep -vE "acme.sh|bz-update|xbz-update"
 echo "0 20 * * * TZ=UTC \"$HOME/.acme.sh\"/acme.sh --cron --home \"$HOME/.acme.sh\" > /dev/null"
 echo "0 21 * * * TZ=UTC $BZ_UPD_SH >/dev/null 2>&1"
 echo "0 22 * * * TZ=UTC $XBZ_UPD_SH >/dev/null 2>&1") | crontab -
echo "      ✅ 定时任务已设置（每日自动续签证书及更新内核）"
echo "      ✨ 7. 节点输出"
clear
echo "=================================================================="
echo "               ✨ ✨      Xbz  2026 新年快乐      ✨ ✨  "
echo "=================================================================="
echo "            ✨ ✨ 【1】Clash Party （Mihomo） 配置 ✨ ✨ "
echo ""
echo "- {name: \"歇斯底里${MY_SUB}\", type: hysteria2, server: $SUB_DOMAIN, port: 443, password: $MY_GUID, obfs: salamander, obfs-password: $HY2_OBFS, sni: $SUB_DOMAIN}"
echo "- {name: \"Reality-${MY_SUB}\", type: vless, server: $SUB_DOMAIN, port: 8443, uuid: $MY_GUID, network: tcp, tls: true, flow: xtls-rprx-vision, servername: $DEST_DOMAIN, reality-opts: {public-key: $PUBLIC_KEY, short-id: $SHORT_ID}, client-fingerprint: firefox}"
echo ""
echo ""
echo "- 歇斯底里${MY_SUB}"
echo "- Reality-${MY_SUB}"
echo ""
echo "=================================================================="
echo "               ✨ ✨ 【2】通用分享链接 ✨ ✨ "
echo ""
echo "vless://$MY_GUID@$VX_DOMAIN80:80?encryption=none&security=none&type=ws&host=$VX_DOMAIN80&path=/videos#80-WS-免流-CDN-${MY_SUB}"
echo "vless://$MY_GUID@$SUB_DOMAIN:443?encryption=none&security=tls&sni=$ML_HOST&type=ws&host=$ML_HOST&path=/videos&allowInsecure=1#443-WS-TLS-免流-${MY_SUB}"
echo "hysteria2://$MY_GUID@$SUB_DOMAIN:443/?obfs=salamander&obfs-password=$HY2_OBFS&sni=$SUB_DOMAIN#歇斯底里${MY_SUB}"
echo "vless://$MY_GUID@$VX_DOMAIN:443?encryption=none&security=tls&sni=$VX_DOMAIN&type=xhttp&path=/videos#XHTTP-CDN-${MY_SUB}"
echo "vless://$MY_GUID@${MY_SUB}.cf.cname.vvhan.com:443?encryption=none&security=tls&sni=$VX_DOMAIN&type=xhttp&path=/videos#XHTTP-CDN-${MY_SUB}优选域名"
echo "vless://$MY_GUID@$SUB_DOMAIN:$PORT_XHTTP_REALITY?security=reality&pbk=$PUBLIC_KEY&sid=$SHORT_ID&fp=firefox&type=xhttp&path=/videos&sni=$DEST_DOMAIN#XHTTP-Reality-${MY_SUB}"
echo "vless://$MY_GUID@$SUB_DOMAIN:8443?security=reality&pbk=$PUBLIC_KEY&sid=$SHORT_ID&fp=firefox&type=tcp&flow=xtls-rprx-vision&sni=$DEST_DOMAIN#Reality-${MY_SUB}"
echo ""
echo "✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ "
ULTIMATE_EOF

bash /root/ultimate_xbz_2026.sh