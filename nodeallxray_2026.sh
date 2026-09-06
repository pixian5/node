cat > /root/ultimate_allxray_2026.sh << 'ULTIMATE_EOF'
#!/bin/bash
# =====================================================================
# nodeallxray_2026.sh — xray 承载全部 TCP 节点，sing-box 只留 Hysteria2(UDP)
# 基于 node6.sh 重构。把 Reality(8443)、WS-TLS(443/TCP) 从 sing-box 迁入 xray。
# sing-box 精简为仅承载 hy2(443/UDP)。
# 版本：0.0.1
# =====================================================================

# ================= 配置变量区 =================
MY_SUB="l"
DOMAIN="sbbz.tech"
ML_HOST="v9-y.douyinvod.com"
cf_domain=bestcf.top
CF_TOKEN="Wfzj8EiELSTTnKbctM9qTuyv8ga23WTW3W-Lj3KJ"
MY_GUID="41d4f8b3-2a45-4531-a33b-938e2eebb939"
HY2_OBFS="sbxbz19890604"
PORT=443
PORT_CDN_VX=2083
PORT_XHTTP_REALITY=2053
DEST_DOMAIN="itunes.apple.com"
SUB_DOMAIN="${MY_SUB}.${DOMAIN}"
VX_DOMAIN80="${MY_SUB}80.${DOMAIN}"
VX_DOMAIN="${MY_SUB}vx$PORT_CDN_VX.${DOMAIN}"
SBOX_CONF="/etc/bz/config.json"
XBZ_CONF="/etc/xbz/config.json"
CERT_DIR="/etc/bz/certs"
BZ_BIN="/usr/local/bin/bz"
XBZ_BIN="/usr/local/bin/xbz"
REALITY_ENV="/etc/bz/reality.env"
BZ_UPD_SH="/root/bz-update.sh"
XBZ_UPD_SH="/root/xbz-update.sh"
EMAIL="${MY_SUB}@$DOMAIN"
ZEROSSL_EAB_KID="BJtDKkx_g19006Zm9sHe2A"
ZEROSSL_EAB_HMAC="9hHy6efkq82j1jEdXeJKuV7SxftQXOJcZP9EZdb1b2rC5p4uiLuZVQVnoP7bP7YxsEnXD8RZgEkSkKDW3zhhgw"
GTS_EAB_KID="878a7b1b4d9971e19f43502f08c00605"
GTS_EAB_HMAC="BgILC_5utbdBOM4gFi_0bPbZnzCqwA3P0G7Ka-G1sLXyHWMDrE5sp_es1bd_jXcZET8QXd75cBEqZS9xf4CGcZg"

echo "================================================================="
echo "      ✨ allxray 0.0.1：xray 承载全部 TCP，sing-box 只留 hy2"
systemctl stop bz xbz 2>/dev/null
fuser -k 443/udp 443/tcp 80/tcp 8443/tcp 2083/tcp 2053/tcp 2>/dev/null

bootstrap_cf_deps() {
  local miss=0
  command -v curl >/dev/null 2>&1 || miss=1
  command -v jq   >/dev/null 2>&1 || miss=1
  if [ "$miss" -eq 1 ]; then apt-get install -y curl jq ca-certificates; fi
}
bootstrap_cf_deps
echo "开通防火墙端口"
if command -v ufw >/dev/null; then
    ufw allow 443/tcp; ufw allow 443/udp; ufw allow 80/tcp; ufw allow 8443/tcp;
    ufw allow $PORT_CDN_VX/tcp; ufw allow $PORT_XHTTP_REALITY/tcp;
fi

echo "      ✨ 2. Cloudflare 回源规则 (CDN 2083)"
CF_API="https://api.cloudflare.com/client/v4"
IP=$(curl -s https://api.ip.sb/ip || curl -s https://checkip.amazonaws.com)
get_zone_id() {
  local zid
  zid=$(curl -s -X GET "${CF_API}/zones?name=${DOMAIN}&status=active&per_page=50" -H "Authorization: Bearer ${CF_TOKEN}" -H "Content-Type: application/json" | jq -r '.result[0].id // empty')
  [ -n "$zid" ] && echo "$zid" || { echo "❌ 获取 ZONE_ID 失败" >&2; return 1; }
}
ZONE_ID="$(get_zone_id)" || exit 1
setup_origin_rule_batch() {
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

echo "      ✨ 3. 安装/更新 sing-box 与 xray 内核"
apt-get install -y psmisc tar unzip ca-certificates
cat > "$BZ_UPD_SH" << 'BZ_UPD_SHEOF'
#!/bin/bash
BZ_BIN="/usr/local/bin/bz"; BZ_SVC="bz"; BZ_PORTS="443"
LATEST=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/v//')
CURRENT=""; [ -f "$BZ_BIN" ] && CURRENT=$($BZ_BIN version | head -n1 | awk '{print $3}')
if [ -n "$CURRENT" ] && [ "$CURRENT" = "$LATEST" ]; then echo "sing-box 已最新 $LATEST"; exit 0; fi
case "$(uname -m)" in x86_64|amd64) S_ARCH="amd64" ;; aarch64|arm64) S_ARCH="arm64" ;; s390x) S_ARCH="s390x" ;; *) exit 1 ;; esac
tmp=$(mktemp -d)
curl -sLo "$tmp/sb.tar.gz" "https://github.com/SagerNet/sing-box/releases/download/v${LATEST}/sing-box-${LATEST}-linux-${S_ARCH}.tar.gz" || exit 1
tar -zxf "$tmp/sb.tar.gz" -C "$tmp" || exit 1
cp -f "$BZ_BIN" "$tmp/bz.old" 2>/dev/null
cp -f "$tmp"/sing-box-*/sing-box "$BZ_BIN" && chmod +x "$BZ_BIN"
systemctl restart "$BZ_SVC"; sleep 2
systemctl is-active --quiet "$BZ_SVC" || { cp -f "$tmp/bz.old" "$BZ_BIN"; chmod +x "$BZ_BIN"; systemctl restart "$BZ_SVC"; exit 1; }
rm -rf "$tmp"
BZ_UPD_SHEOF
cat > "$XBZ_UPD_SH" << 'XBZ_UPD_SHEOF'
#!/bin/bash
XBZ_BIN="/usr/local/bin/xbz"; XBZ_SVC="xbz"; XBZ_PORTS="80 443 8443 2053 2083"
LATEST=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name | sed 's/v//')
CURRENT=""; [ -f "$XBZ_BIN" ] && CURRENT=$($XBZ_BIN version | head -n1 | awk '{print $2}')
if [ -n "$CURRENT" ] && [ "$CURRENT" = "$LATEST" ]; then echo "xray 已最新 $LATEST"; exit 0; fi
case "$(uname -m)" in x86_64|amd64) X_ARCH="64" ;; aarch64|arm64) X_ARCH="arm64-v8a" ;; s390x) X_ARCH="s390x" ;; *) exit 1 ;; esac
tmp=$(mktemp -d)
curl -sLo "$tmp/xr.zip" "https://github.com/XTLS/Xray-core/releases/download/v${LATEST}/Xray-linux-${X_ARCH}.zip" || exit 1
unzip -q "$tmp/xr.zip" -d "$tmp" || exit 1
cp -f "$XBZ_BIN" "$tmp/xr.old" 2>/dev/null
cp -f "$tmp/xray" "$XBZ_BIN" && chmod +x "$XBZ_BIN"
systemctl restart "$XBZ_SVC"; sleep 2
systemctl is-active --quiet "$XBZ_SVC" || { cp -f "$tmp/xr.old" "$XBZ_BIN"; chmod +x "$XBZ_BIN"; systemctl restart "$XBZ_SVC"; exit 1; }
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

echo "      ✨ 5. 写入配置"
mkdir -p "$CERT_DIR"

echo "      ✨ 5.1 xray 承载全部 TCP 节点 (Reality 8443 / WS-TLS 443 / WS直连 80 / XHTTP-CDN 2083 / XHTTP-Reality 2053)"
cat > "$XBZ_CONF" << X_JSON
{
    "log": { "loglevel": "info" },
    "inbounds": [
        {"port": 8443, "protocol": "vless", "settings": {"clients": [{"id": "$MY_GUID", "flow": "xtls-rprx-vision"}], "decryption": "none"}, "streamSettings": {"network": "tcp", "security": "reality", "realitySettings": {"show": false, "dest": "$DEST_DOMAIN:443", "xver": 0, "serverNames": ["$DEST_DOMAIN"], "privateKey": "$PRIVATE_KEY", "shortIds": ["$SHORT_ID"]}}},
        {"port": 443, "protocol": "vless", "settings": {"clients": [{"id": "$MY_GUID"}], "decryption": "none"}, "streamSettings": {"network": "ws", "security": "tls", "tlsSettings": {"certificates": [{"certificateFile": "$CERT_DIR/server.crt", "keyFile": "$CERT_DIR/server.key"}], "serverName": "$ML_HOST"}, "wsSettings": {"path": "/videos", "headers": {"Host": "$ML_HOST"}}}},
        {"port": 80, "protocol": "vless", "settings": {"clients": [{"id": "$MY_GUID"}], "decryption": "none"}, "streamSettings": {"network": "ws", "wsSettings": {"path": "/videos", "headers": {"Host": "$ML_HOST"}}}},
        {"port": $PORT_CDN_VX, "protocol": "vless", "settings": {"clients": [{"id": "$MY_GUID"}], "decryption": "none"}, "streamSettings": {"network": "xhttp", "security": "tls", "tlsSettings": {"certificates": [{"certificateFile": "$CERT_DIR/server.crt", "keyFile": "$CERT_DIR/server.key"}], "serverName": "$VX_DOMAIN"}, "xhttpSettings": {"path": "/videos"}}},
        {"port": $PORT_XHTTP_REALITY, "protocol": "vless", "settings": {"clients": [{"id": "$MY_GUID"}], "decryption": "none"}, "streamSettings": {"network": "xhttp", "security": "reality", "realitySettings": {"show": false, "dest": "$DEST_DOMAIN:443", "xver": 0, "serverNames": ["$DEST_DOMAIN"], "privateKey": "$PRIVATE_KEY", "shortIds": ["$SHORT_ID"]}, "xhttpSettings": {"path": "/videos"}}}
    ],
    "outbounds": [{ "protocol": "freedom" }]
}
X_JSON
echo "      ✅ xray 配置已写入 (5 个 TCP 入站)"

echo "      ✨ 5.2 sing-box 只保留 Hysteria2 (443/UDP)"
cat > "$SBOX_CONF" << CONFIG
{
  "log": { "level": "info", "timestamp": true },
  "inbounds": [
    { "type": "hysteria2", "tag": "hy2-in", "listen": "::", "listen_port": $PORT, "users": [{ "password": "$MY_GUID" }], "obfs": { "type": "salamander", "password": "$HY2_OBFS" }, "tls": { "enabled": true, "server_name": "$SUB_DOMAIN", "certificate_path": "$CERT_DIR/server.crt", "key_path": "$CERT_DIR/server.key" } }
  ],
  "outbounds": [{ "type": "direct" }]
}
CONFIG
echo "      ✅ sing-box 配置已写入 (仅 hy2)"

echo "      ✨ 5.3 创建 Systemd 服务"
cat > /etc/systemd/system/bz.service << SVC
[Unit]
Description=bz (sing-box / hysteria2) service
After=network.target
[Service]
ExecStart=$BZ_BIN run -c $SBOX_CONF
Restart=always
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
SVC
cat > /etc/systemd/system/xbz.service << SVC
[Unit]
Description=xbz (xray, all TCP) service
After=network.target
[Service]
ExecStart=$XBZ_BIN run -c $XBZ_CONF
Restart=always
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
SVC
systemctl daemon-reload

echo "      ✨ 5.4 通配符证书 (已存在则跳过)"
[ ! -f "$HOME/.acme.sh/acme.sh" ] && curl https://get.acme.sh | sh -s email="$EMAIL"
export CF_Token="$CF_TOKEN"
cert_matches_domain() {
    local crt="$1"
    openssl x509 -in "$crt" -noout -text 2>/dev/null | grep -q "DNS:${DOMAIN}" && \
    openssl x509 -in "$crt" -noout -text 2>/dev/null | grep -q "DNS:\\*\\.${DOMAIN}"
}
cert_expired() {
    local crt="$1"; local end
    end=$(openssl x509 -in "$crt" -noout -enddate 2>/dev/null | cut -d= -f2-)
    local end_ts now_ts
    end_ts=$(date -d "$end" +%s 2>/dev/null || echo 0); now_ts=$(date +%s)
    [ "$end_ts" -le "$now_ts" ]
}
issue_cert_try() {
    local server="$1"; echo "      尝试 CA: $server"
    if [ "$server" = "zerossl" ]; then
        [ -z "$ZEROSSL_EAB_KID" ] || [ -z "$ZEROSSL_EAB_HMAC" ] && return 1
        "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf -d "$DOMAIN" -d "*.$DOMAIN" --keylength ec-256 --server "$server" --eab-kid "$ZEROSSL_EAB_KID" --eab-hmac-key "$ZEROSSL_EAB_HMAC"; return $?
    fi
    if [ "$server" = "google" ]; then
        [ -z "$GTS_EAB_KID" ] || [ -z "$GTS_EAB_HMAC" ] && return 1
        "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf -d "$DOMAIN" -d "*.$DOMAIN" --keylength ec-256 --server "$server" --eab-kid "$GTS_EAB_KID" --eab-hmac-key "$GTS_EAB_HMAC"; return $?
    fi
    "$HOME/.acme.sh/acme.sh" --issue --dns dns_cf -d "$DOMAIN" -d "*.$DOMAIN" --keylength ec-256 --server "$server"
}
if [ -s "$CERT_DIR/server.crt" ] && [ -s "$CERT_DIR/server.key" ] && cert_matches_domain "$CERT_DIR/server.crt" && ! cert_expired "$CERT_DIR/server.crt"; then
    echo "      证书已就绪，跳过"
    CERT_OK=1
else
    CERT_OK=0
    issue_cert_try letsencrypt || issue_cert_try zerossl || issue_cert_try google
    if [ -s "$HOME/.acme.sh/${DOMAIN}_ecc/fullchain.cer" ]; then
        "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" --ecc --key-file "$CERT_DIR/server.key" --fullchain-file "$CERT_DIR/server.crt" --reloadcmd "systemctl restart bz xbz"
        [ -s "$CERT_DIR/server.crt" ] && [ -s "$CERT_DIR/server.key" ] && cert_matches_domain "$CERT_DIR/server.crt" && CERT_OK=1
    fi
fi

systemctl enable bz xbz && systemctl restart bz xbz
sleep 2
echo "      ✅ 服务状态: bz=$(systemctl is-active bz) xbz=$(systemctl is-active xbz)"

echo "      ✨ 6. 定时任务"
cat > /etc/systemd/system/ultimate-allxray-boot.service << 'SVC'
[Unit]
Description=Run ultimate_allxray_2026.sh at boot
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/bin/bash /root/ultimate_allxray_2026.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
SVC
(crontab -l 2>/dev/null | grep -vE "acme.sh|bz-update|xbz-update"
 echo "0 20 * * * TZ=UTC \"$HOME/.acme.sh\"/acme.sh --cron --home \"$HOME/.acme.sh\" > /dev/null"
 echo "0 21 * * * TZ=UTC $BZ_UPD_SH >/dev/null 2>&1"
 echo "0 22 * * * TZ=UTC $XBZ_UPD_SH >/dev/null 2>&1") | crontab -

echo "      ✨ 7. 端口归属确认"
echo "   TCP: 443(WS-TLS) 80(WS) 8443(Reality) 2083(XHTTP-CDN) 2053(XHTTP-Reality) = xray"
echo "   UDP: 443(hy2) = sing-box"
echo "✅ xray 承载全部 TCP，sing-box 只留 hy2，部署完成"
ULTIMATE_EOF
bash /root/ultimate_allxray_2026.sh
systemctl daemon-reload
systemctl enable ultimate-allxray-boot.service
systemctl status ultimate-allxray-boot.service