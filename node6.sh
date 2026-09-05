cat > /root/ultimate_xbz_2026.sh << 'ULTIMATE_EOF'
#!/bin/bash

# ================= 配置变量区 =================
#子域名前缀
MY_SUB="l"
#域名                             
DOMAIN="sbbz.tech"  

#免流域名
ML_HOST="v9-y.douyinvod.com"  
#优选域名
cf_domain=bestcf.top
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
# ZeroSSL EAB 信息（需要先到 ZeroSSL 平台申请）
ZEROSSL_EAB_KID="BJtDKkx_g19006Zm9sHe2A"
ZEROSSL_EAB_HMAC="9hHy6efkq82j1jEdXeJKuV7SxftQXOJcZP9EZdb1b2rC5p4uiLuZVQVnoP7bP7YxsEnXD8RZgEkSkKDW3zhhgw"
# Google ACME EAB 信息（需要先到 GTS/Google Cloud 申请）
GTS_EAB_KID="878a7b1b4d9971e19f43502f08c00605"
GTS_EAB_HMAC="BgILC_5utbdBOM4gFi_0bPbZnzCqwA3P0G7Ka-G1sLXyHWMDrE5sp_es1bd_jXcZET8QXd75cBEqZS9xf4CGcZg"
echo "=================================================================" 
echo "      ✨ 1. 环境准备"
echo "            停止旧程序（如果有）"
systemctl stop bz xbz 2>/dev/null
echo "            杀掉占用端口的进程"
fuser -k 443/tcp 443/udp 80/tcp 2083/tcp 2053/tcp 8443/tcp 2>/dev/null

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
echo "开通防火墙端口：TCP：80 443 8443 $PORT_CDN_VX $PORT_XHTTP_REALITY; UDP:443"
if command -v ufw >/dev/null; then 
    ufw allow 443/tcp; ufw allow 443/udp; ufw allow 80/tcp; ufw allow 8443/tcp;
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
apt-get install -y psmisc tar unzip ca-certificates
echo "      ✅ 软件包安装完成"
echo "配置 Cloudflare 规则..."
setup_origin_rule_batch() {
    # 配置 Origin Rules (回源端口)
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
}
setup_origin_rule_batch
echo "      ✅ Cloudflare 路由及 SSL 规则配置完成"

echo "      ✨ 3. 安装/更新singbox、xray最新内核"
echo "         3.1 安装/更新singbox内核"

cat > "$BZ_UPD_SH" << 'BZ_UPD_SHEOF'
#!/bin/bash
# sing-box 自动更新：下载→备份→覆盖→重启→健康检查，失败自动回滚
BZ_BIN="/usr/local/bin/bz"
BZ_SVC="bz"
BZ_PORTS="443 8443"
LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/v//')
CURRENT=""
[ -f "$BZ_BIN" ] && CURRENT=$($BZ_BIN version | head -n1 | awk '{print $3}')
if [ -n "$CURRENT" ] && [ "$CURRENT" = "$LATEST" ]; then
    echo "      ✅ Sing-box 已是最新版本 ($LATEST)，跳过下载。"
    exit 0
fi
case "$(uname -m)" in
    x86_64|amd64)          S_ARCH="amd64" ;;
    aarch64|arm64)         S_ARCH="arm64" ;;
    s390x)                 S_ARCH="s390x" ;;
    *) echo "❌ 不支持的 CPU 架构: $(uname -m)"; exit 1 ;;
esac
tmp=$(mktemp -d)
if ! curl -sLo "$tmp/sb.tar.gz" "https://github.com/SagerNet/sing-box/releases/download/v${LATEST}/sing-box-${LATEST}-linux-${S_ARCH}.tar.gz" || [ ! -s "$tmp/sb.tar.gz" ]; then
    echo "❌ 下载失败，保留当前版本 ${CURRENT:-未安装}"; rm -rf "$tmp"; exit 1
fi
tar -zxf "$tmp/sb.tar.gz" -C "$tmp" || { echo "❌ 解压失败"; rm -rf "$tmp"; exit 1; }
cp -f "$BZ_BIN" "$tmp/bz.old" 2>/dev/null
cp -f "$tmp"/sing-box-*/sing-box "$BZ_BIN" && chmod +x "$BZ_BIN"
systemctl restart "$BZ_SVC"; sleep 2
health_ok=1
systemctl is-active --quiet "$BZ_SVC" || health_ok=0
for p in $BZ_PORTS; do
    timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/$p" 2>/dev/null || { health_ok=0; break; }
done
if [ "$health_ok" = "1" ]; then
    echo "      ✅ Sing-box 更新完成 ${CURRENT:-未安装} -> $LATEST，健康检查通过"
    rm -rf "$tmp"; exit 0
fi
echo "❌ 健康检查失败，回滚到 ${CURRENT:-旧版本}"
cp -f "$tmp/bz.old" "$BZ_BIN" 2>/dev/null; chmod +x "$BZ_BIN"
systemctl restart "$BZ_SVC"
rm -rf "$tmp"; exit 1
BZ_UPD_SHEOF
echo "         3.2 安装/更新xray内核"
cat > "$XBZ_UPD_SH" << 'XBZ_UPD_SHEOF'
#!/bin/bash
# xray 自动更新：下载→备份→覆盖→重启→健康检查，失败自动回滚
XBZ_BIN="/usr/local/bin/xbz"
XBZ_SVC="xbz"
XBZ_PORTS="80 2053 2083"
LATEST=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name | sed 's/v//')
CURRENT=""
[ -f "$XBZ_BIN" ] && CURRENT=$($XBZ_BIN version | head -n1 | awk '{print $2}')
if [ -n "$CURRENT" ] && [ "$CURRENT" = "$LATEST" ]; then
    echo "      ✅ Xray 已是最新版本 ($LATEST)，跳过下载。"
    exit 0
fi
case "$(uname -m)" in
    x86_64|amd64)          X_ARCH="64" ;;
    aarch64|arm64)         X_ARCH="arm64-v8a" ;;
    s390x)                 X_ARCH="s390x" ;;
    *) echo "❌ 不支持的 CPU 架构: $(uname -m)"; exit 1 ;;
esac
tmp=$(mktemp -d)
if ! curl -sLo "$tmp/xr.zip" "https://github.com/XTLS/Xray-core/releases/download/v${LATEST}/Xray-linux-${X_ARCH}.zip" || [ ! -s "$tmp/xr.zip" ]; then
    echo "❌ 下载失败，保留当前版本 ${CURRENT:-未安装}"; rm -rf "$tmp"; exit 1
fi
unzip -q "$tmp/xr.zip" -d "$tmp" || { echo "❌ 解压失败"; rm -rf "$tmp"; exit 1; }
cp -f "$XBZ_BIN" "$tmp/xr.old" 2>/dev/null
cp -f "$tmp/xray" "$XBZ_BIN" && chmod +x "$XBZ_BIN"
systemctl restart "$XBZ_SVC"; sleep 2
health_ok=1
systemctl is-active --quiet "$XBZ_SVC" || health_ok=0
for p in $XBZ_PORTS; do
    timeout 2 bash -c "echo > /dev/tcp/127.0.0.1/$p" 2>/dev/null || { health_ok=0; break; }
done
if [ "$health_ok" = "1" ]; then
    echo "      ✅ Xray 更新完成 ${CURRENT:-未安装} -> $LATEST，健康检查通过"
    rm -rf "$tmp"; exit 0
fi
echo "❌ 健康检查失败，回滚到 ${CURRENT:-旧版本}"
cp -f "$tmp/xr.old" "$XBZ_BIN" 2>/dev/null; chmod +x "$XBZ_BIN"
systemctl restart "$XBZ_SVC"
rm -rf "$tmp"; exit 1
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
        {"port": 80, "protocol": "vless", "settings": {"clients": [{"id": "$MY_GUID"}], "decryption": "none"}, "streamSettings": {"network": "ws", "wsSettings": {"path": "/videos", "headers": {"Host": "$ML_HOST"}}}},
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
cert_matches_domain() {
    # 检查证书 SAN 是否包含主域名和通配符域名
    local crt="$1"
    openssl x509 -in "$crt" -noout -text 2>/dev/null | \
      grep -q "DNS:${DOMAIN}" && \
    openssl x509 -in "$crt" -noout -text 2>/dev/null | \
      grep -q "DNS:\\*\\.${DOMAIN}"
}

cert_expired() {
    local crt="$1"
    local end
    end=$(openssl x509 -in "$crt" -noout -enddate 2>/dev/null | cut -d= -f2-)
    local end_ts now_ts
    end_ts=$(date -d "$end" +%s 2>/dev/null || echo 0)
    now_ts=$(date +%s)
    [ "$end_ts" -le "$now_ts" ]
}

show_cert_status() {
    local crt="$1"
    local end
    end=$(openssl x509 -in "$crt" -noout -enddate 2>/dev/null | cut -d= -f2-)
    if [ -n "$end" ]; then
        local end_ts now_ts days_left
        end_ts=$(date -d "$end" +%s 2>/dev/null || echo 0)
        now_ts=$(date +%s)
        days_left=$(( (end_ts - now_ts) / 86400 ))
        echo "      ✅ 证书有效期至：$end（剩余约 ${days_left} 天）"
    else
        echo "      ⚠️  无法读取证书有效期"
    fi
    local conf="$HOME/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.conf"
    if [ -s "$conf" ]; then
        local next_ts
        local next_str
        next_ts=$(grep -E '^Le_NextRenewTime=' "$conf" | cut -d= -f2 | tr -d "\"'")
        if [ -n "$next_ts" ]; then
            next_str=$(date -d "@$next_ts" "+%F %T %Z" 2>/dev/null)
            if [ -n "$next_str" ]; then
                echo "      ✅ 下次续期时间：$next_str"
            else
                echo "      ⚠️  无法解析下次续期时间"
            fi
        else
            echo "      ⚠️  未找到下次续期时间"
        fi
    else
        echo "      ⚠️  未找到 acme.sh 续期记录文件"
    fi
}

show_cert_ca() {
    local crt="$1"
    local issuer
    issuer=$(openssl x509 -in "$crt" -noout -issuer 2>/dev/null | sed 's/^issuer= //')
    if [ -n "$issuer" ]; then
        echo "      ✅ 当前证书颁发者：$issuer"
    else
        echo "      ⚠️  无法读取证书颁发者"
    fi
}

ca_friendly_name() {
    local ca="$1"
    case "$ca" in
        letsencrypt) echo "Let's Encrypt" ;;
        zerossl) echo "ZeroSSL" ;;
        google) echo "Google Trust Services" ;;
        *) echo "$ca" ;;
    esac
}

ca_from_issuer() {
    local crt="$1"
    local issuer
    issuer=$(openssl x509 -in "$crt" -noout -issuer 2>/dev/null)
    case "$issuer" in
        *"Let's Encrypt"*) echo "Let's Encrypt" ;;
        *"ZeroSSL"*) echo "ZeroSSL" ;;
        *"Google Trust Services"*) echo "Google Trust Services" ;;
        *) echo "" ;;
    esac
}

if [ -s "$CERT_DIR/server.crt" ] && [ -s "$CERT_DIR/server.key" ] && cert_matches_domain "$CERT_DIR/server.crt" && ! cert_expired "$CERT_DIR/server.crt"; then
    echo "      ✅ 已检测到匹配 ${DOMAIN} / *.${DOMAIN} 且未过期的证书，跳过申请与安装"
    CERT_OK=1
else
    CERT_OK=0
    issue_cert_try() {
        local server="$1"
        echo "      ⏳ 尝试 CA: $server"
        if [ "$server" = "zerossl" ]; then
            if [ -z "$ZEROSSL_EAB_KID" ] || [ -z "$ZEROSSL_EAB_HMAC" ]; then
                echo "      ⚠️  ZeroSSL 需要 EAB，未设置 ZEROSSL_EAB_KID / ZEROSSL_EAB_HMAC，跳过"
                return 1
            fi
            "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf -d "$DOMAIN" -d "*.$DOMAIN" --keylength ec-256 --server "$server" \
              --eab-kid "$ZEROSSL_EAB_KID" --eab-hmac-key "$ZEROSSL_EAB_HMAC"
            if [ $? -eq 0 ]; then CERT_CA="$server"; return 0; fi
            return 1
        fi
        if [ "$server" = "google" ]; then
            if [ -z "$GTS_EAB_KID" ] || [ -z "$GTS_EAB_HMAC" ]; then
                echo "      ⚠️  Google ACME 需要 EAB，未设置 GTS_EAB_KID / GTS_EAB_HMAC，跳过"
                return 1
            fi
            "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf -d "$DOMAIN" -d "*.$DOMAIN" --keylength ec-256 --server "$server" \
              --eab-kid "$GTS_EAB_KID" --eab-hmac-key "$GTS_EAB_HMAC"
            if [ $? -eq 0 ]; then CERT_CA="$server"; return 0; fi
            return 1
        fi
        "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf -d "$DOMAIN" -d "*.$DOMAIN" --keylength ec-256 --server "$server"
        if [ $? -eq 0 ]; then CERT_CA="$server"; return 0; fi
        return 1
    }
    issue_cert_try letsencrypt || issue_cert_try zerossl || issue_cert_try google
    if [ -s "$HOME/.acme.sh/${DOMAIN}_ecc/fullchain.cer" ]; then
        "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" --ecc --key-file "$CERT_DIR/server.key" --fullchain-file "$CERT_DIR/server.crt" --reloadcmd "systemctl restart bz xbz"
        if [ -s "$CERT_DIR/server.crt" ] && [ -s "$CERT_DIR/server.key" ] && cert_matches_domain "$CERT_DIR/server.crt"; then
            CERT_OK=1
        fi
    else
        echo "      ❌ 证书申请失败，未生成 fullchain.cer，跳过安装"
    fi
fi
if [ "${CERT_OK:-0}" -eq 1 ]; then
    echo "      ✅ 通配符证书已就绪"
    show_cert_status "$CERT_DIR/server.crt"
    if [ -n "$CERT_CA" ]; then
        echo "      ✅ 当前使用 CA：$(ca_friendly_name "$CERT_CA")"
    else
        local_ca="$(ca_from_issuer "$CERT_DIR/server.crt")"
        if [ -n "$local_ca" ]; then
            echo "      ✅ 当前使用 CA：$local_ca"
        else
            show_cert_ca "$CERT_DIR/server.crt"
        fi
    fi
else
    echo "      ❌ 通配符证书未就绪"
fi

systemctl enable bz xbz && systemctl restart bz xbz
echo "      ✅ Sing-box 和 Xray 服务已启动并设置开机自启"
echo "      ✨ 6. 开机自动运行一次、每天定时更新"

# 设置开机自启：每次开机运行一次主脚本
cat > /etc/systemd/system/ultimate-xbz-boot.service << 'SVC'
[Unit]
Description=Run ultimate_xbz_2026.sh at boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /root/ultimate_xbz_2026.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC

(crontab -l 2>/dev/null | grep -vE "acme.sh|bz-update|xbz-update"
 echo "0 20 * * * TZ=UTC \"$HOME/.acme.sh\"/acme.sh --cron --home \"$HOME/.acme.sh\" > /dev/null"
 echo "0 21 * * * TZ=UTC $BZ_UPD_SH >/dev/null 2>&1"
 echo "0 22 * * * TZ=UTC $XBZ_UPD_SH >/dev/null 2>&1") | crontab -
if crontab -l 2>/dev/null | grep -q "acme.sh --cron"; then
    echo "      ✅ 续期定时任务已设置（每日执行 acme.sh --cron）"
else
    echo "      ⚠️  未检测到 acme.sh 续期定时任务"
fi
echo "      ✅ 定时任务已设置（每日自动续签证书及更新内核）"
echo "      ✨ 7. 节点输出"
clear
echo "=================================================================="
echo "               ✨ ✨      Xbz  2026 新年快乐      ✨ ✨  "
echo "=================================================================="
echo "            ✨ ✨ 【1】Clash Party （Mihomo） 配置 ✨ ✨ "
echo ""
echo "- {name: \"80-WS-直连免流-${MY_SUB}\", type: vless, server: $SUB_DOMAIN, port: 80, uuid: $MY_GUID, network: ws, tls: false, ws-opts: {path: /videos, headers: {Host: $ML_HOST}}}"
echo "- {name: \"443-WS-TLS-免流-${MY_SUB}\", type: vless, server: $SUB_DOMAIN, port: 443, uuid: $MY_GUID, network: ws, tls: true, skip-cert-verify: true, servername: $ML_HOST, ws-opts: {path: /videos, headers: {Host: $ML_HOST}}}"
echo "- {name: \"歇斯底里${MY_SUB}\", type: hysteria2, server: $SUB_DOMAIN, port: 443, password: $MY_GUID, obfs: salamander, obfs-password: $HY2_OBFS, sni: $SUB_DOMAIN}"
echo "- {name: \"Reality-${MY_SUB}\", type: vless, server: $SUB_DOMAIN, port: 8443, uuid: $MY_GUID, network: tcp, tls: true, flow: xtls-rprx-vision, servername: $DEST_DOMAIN, reality-opts: {public-key: $PUBLIC_KEY, short-id: $SHORT_ID}, client-fingerprint: firefox}"
echo "- {name: \"XHTTP-Reality-${MY_SUB}\", type: vless, server: $SUB_DOMAIN, port: $PORT_XHTTP_REALITY, uuid: $MY_GUID, network: xhttp, tls: true, udp: true, servername: $DEST_DOMAIN, client-fingerprint: firefox, reality-opts: {public-key: $PUBLIC_KEY, short-id: $SHORT_ID}, xhttp-opts: {path: /videos, mode: auto}}"
echo "- {name: \"XHTTP-CDN-${MY_SUB}优选域名\", type: vless, server: $cf_domain, port: 443, uuid: $MY_GUID, network: xhttp, tls: true, udp: true, servername: $VX_DOMAIN, skip-cert-verify: true, xhttp-opts: {path: /videos, host: $VX_DOMAIN, mode: auto}}"
echo ""
echo "- 80-WS-直连免流-${MY_SUB}"
echo "- 443-WS-TLS-免流-${MY_SUB}"
echo "- 歇斯底里${MY_SUB}"
echo "- Reality-${MY_SUB}"
echo "- XHTTP-Reality-${MY_SUB}"
echo "- XHTTP-CDN-${MY_SUB}优选域名"
echo ""
echo "=================================================================="
echo "               ✨ ✨ 【2】通用分享链接 ✨ ✨ "
echo ""
echo "vless://$MY_GUID@$SUB_DOMAIN:80?encryption=none&security=none&type=ws&host=$ML_HOST&path=/videos#80-WS-直连免流-${MY_SUB}"
echo "vless://$MY_GUID@$SUB_DOMAIN:443?encryption=none&security=tls&sni=$ML_HOST&type=ws&host=$ML_HOST&path=/videos&allowInsecure=1#443-WS-TLS-免流-${MY_SUB}"
echo "hysteria2://$MY_GUID@$SUB_DOMAIN:443/?obfs=salamander&obfs-password=$HY2_OBFS&sni=$SUB_DOMAIN#歇斯底里${MY_SUB}"
#echo "vless://$MY_GUID@$VX_DOMAIN:443?encryption=none&security=tls&sni=$VX_DOMAIN&type=xhttp&path=/videos#XHTTP-CDN-${MY_SUB}"
echo "vless://$MY_GUID@$cf_domain:443?encryption=none&security=tls&sni=$VX_DOMAIN&type=xhttp&path=/videos#XHTTP-CDN-${MY_SUB}优选域名"
echo "vless://$MY_GUID@$SUB_DOMAIN:$PORT_XHTTP_REALITY?security=reality&pbk=$PUBLIC_KEY&sid=$SHORT_ID&fp=firefox&type=xhttp&path=/videos&sni=$DEST_DOMAIN#XHTTP-Reality-${MY_SUB}"
echo "vless://$MY_GUID@$SUB_DOMAIN:8443?security=reality&pbk=$PUBLIC_KEY&sid=$SHORT_ID&fp=firefox&type=tcp&flow=xtls-rprx-vision&sni=$DEST_DOMAIN#Reality-${MY_SUB}"
echo ""
echo "✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ ✅ "
ULTIMATE_EOF
bash /root/ultimate_xbz_2026.sh
systemctl daemon-reload
systemctl enable ultimate-xbz-boot.service
#echo "✅ 已设置开机自启：/root/ultimate_xbz_2026.sh"
systemctl status ultimate-xbz-boot.service