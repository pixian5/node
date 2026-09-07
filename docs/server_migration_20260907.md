# 服务器迁移记录（新服务器 148.100.112.30）

## 背景
- 旧服务器（uk/sf/l.sbbz.tech）全部被删除/回收，服务全线下线。
- 新服务器：`148.100.112.30`（Marist 大学 LinuxONE 实例，s390x 架构）
- 登录：`ssh linux1@148.100.112.30`，私钥 `/Users/x/ed25519`
- 提权：`sudo -i`（linux1 免密 sudo）

## 架构兼容性
- **s390x（IBM Z 大型机）**：ubuntu 6.8.0-124-generic，3核 3.9G 内存，50G 磁盘
- `xray` 官方 release 支持 s390x：`Xray-linux-s390x.zip`
- `sing-box` 官方 release 支持 s390x：`sing-box-*-linux-s390x.tar.gz`
- 部署脚本 `nodeallxray_2026.sh` 的架构分支已含 s390x，可直接复用

## 部署内容
采用 **allxray 方案**（xray 承载全部 TCP，sing-box 只留 hy2）：
- **xray (xbz 服务)** `/usr/local/bin/xbz`，配置 `/etc/xbz/config.json`
  - TCP 8443 → VLESS+Reality
  - TCP 443 → VLESS+WS+TLS (SNI: v9-y.douyinvod.com)
  - TCP 80 → VLESS+WS 直连
  - TCP 2083 → VLESS+XHTTP+CDN
  - TCP 2053 → VLESS+XHTTP+Reality
- **sing-box (bz 服务)** `/usr/local/bin/bz`，配置 `/etc/bz/config.json`
  - UDP 443 → Hysteria2
- 证书：acme.sh 通配符 `sbbz.tech`，位置 `/etc/bz/certs/`，有效期约 3 个月

## 本次踩坑与解决

### 1. xray 二进制缺失（status=203/EXEC）
部署脚本首次运行 xray 下载失败，`/usr/local/bin/xbz` 不存在导致 xbz 服务 failed。
解决：手动执行 `/root/xbz-update.sh` 重下 Xray s390x 包，然后 `systemctl restart xbz`。

### 2. 端口从外部全部不通（iptables 拦截）
新服务器默认 iptables INPUT 规则只有：
- 放行 TCP 22（SSH）
- 放行 ICMP
- 其余全部 REJECT

导致 80/443/8443/2053/2083 从外部全部 closed，且 nc 探测表现异常（超时）。
解决：
```bash
iptables -I INPUT -p tcp --dport 80 -j ACCEPT
iptables -I INPUT -p tcp --dport 443 -j ACCEPT
iptables -I INPUT -p tcp --dport 8443 -j ACCEPT
iptables -I INPUT -p tcp --dport 2053 -j ACCEPT
iptables -I INPUT -p tcp --dport 2083 -j ACCEPT
iptables -I INPUT -p udp --dport 443 -j ACCEPT
```
固化（重启不丢）：
```bash
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
# rc.local:
cat > /etc/rc.local <<'EOF'
#!/bin/bash
iptables-restore < /etc/iptables/rules.v4
exit 0
EOF
chmod +x /etc/rc.local
```

### 3. DNS 记录未自动更新
`nodeallxray_2026.sh`（allxray 版本）**没有** `update_dns` 函数（该逻辑在旧 node6.sh）。
部署后 l.sbbz.tech / l80 / lvx2083 仍指向旧 IP。
解决：手动用 Cloudflare API 更新 3 条 A 记录到 `148.100.112.30`。

## DNS 记录（最终）
| 子域名 | 指向 | proxied |
|---|---|---|
| l.sbbz.tech | 148.100.112.30 | false (灰云) |
| l80.sbbz.tech | 148.100.112.30 | false (灰云) |
| lvx2083.sbbz.tech | 148.100.112.30 | true (橙云/CDN) |

## Reality 密钥（新服务器生成）
- PrivateKey: `UEUM8YfuBgcTPseCHdMAaq3ZlibW7jmi4ZFUFFsnQ1g`
- PublicKey: `IRn6xu8uB2Fd5-HtjnxcxNZdpAO142tttM-KH8qVpUM`
- ShortID: `d5b2242f8d6a7641`
- 存在 `/etc/bz/reality.env`

## 订阅
- 订阅地址：`https://c.sbbz.tech/sub`（小火箭通用）
- 配置文件：`pages/c_deploy/sub.yaml`，push 到 GitHub `pixian5/node` main 分支自动部署到 Cloudflare Pages

## 测试结论
- WS-TLS 443：✅ TLS1.3 握手 + WS 101 升级 + VLESS 通道建立
- WS 直连 80：✅ WS 101 升级 + VLESS 通道建立
- Reality 8443 / XHTTP 2053 / XHTTP-CDN 2083 / hy2 443：服务监听正常（Reality/XHTTP 需专用客户端，裸连接不响应属正常）