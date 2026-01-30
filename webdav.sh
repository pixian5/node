cat > install_webdav.sh <<'EOF'
#!/bin/bash
set -e

### ====== 配置区域（你只需要改这里） ======
DOMAIN="hk.xbz.email"
USERNAME="x"             # ← 用户名
PASSWORD="0"             # ← 密码
DATA_DIR="/data/webdav"
PASS_FILE="/etc/nginx/webdav.passwd"
CONF_FILE="/etc/nginx/sites-available/webdav"
EMAIL="admin@hk.xbz.email"      #申请证书使用的邮箱
### =========================================

echo "==== 1. 安装依赖 ===="
apt update
apt install -y nginx nginx-extras certbot python3-certbot-nginx apache2-utils

systemctl enable nginx --now

echo "==== 2. 创建存储目录 ===="
mkdir -p ${DATA_DIR}
chown -R www-data:www-data ${DATA_DIR}
chmod -R 775 ${DATA_DIR}

echo "==== 3. 自动创建 WebDAV 用户密码 ===="
echo "${PASSWORD}" | htpasswd -ci ${PASS_FILE} ${USERNAME}

echo "==== 4. 写入 Nginx WebDAV 配置 ===="
cat > ${CONF_FILE} <<EOC
server {
    listen 80;
    server_name ${DOMAIN};

    location /webdav/ {
        alias ${DATA_DIR}/;

        dav_methods PUT DELETE MKCOL COPY MOVE;
        dav_ext_methods PROPFIND OPTIONS;

        create_full_put_path on;
        dav_access user:rw group:rw all:rw;

        auth_basic "WebDAV";
        auth_basic_user_file ${PASS_FILE};

        client_max_body_size 0;

        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;

        charset utf-8;
    }
}
EOC

echo "==== 5. 启用站点 ===="
ln -sf ${CONF_FILE} /etc/nginx/sites-enabled/webdav
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl reload nginx

echo "==== 6. 申请 TLS 证书（HTTPS） ===="
echo "确保域名 ${DOMAIN} 已解析到本机，并开放 80/443 端口"

certbot --nginx -d ${DOMAIN} --redirect \
  --non-interactive --agree-tos -m ${EMAIL}

echo "==== 安装完成！===="
echo ""
echo "WebDAV 地址："
echo "  https://${DOMAIN}/webdav/"
echo ""
echo "文件存储目录："
echo "  ${DATA_DIR}"
echo ""
echo "用户名：${USERNAME}"
echo "密码：${PASSWORD}"
EOF

chmod +x install_webdav.sh
bash install_webdav.sh