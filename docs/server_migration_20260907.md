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
  - TCP 443 → VLESS+TLS 端口复用（fallback）：`/videos` 分流 WS、`h2`/`/api/v1` 分流 XHTTP
  - TCP 8443 → VLESS+Reality
  - TCP 80 → VLESS+WS 直连
  - TCP 2083 → VLESS+XHTTP+CDN
  - TCP 2053 → VLESS+XHTTP+Reality
  - 内部 127.0.0.1:18443(WS) / 18444(XHTTP) 供 443 fallback 还原
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

### 4. WS-TLS 直连超时：证书 SNI 与节点不匹配（重要）
**现象**：订阅里 `443-WS-TLS` 节点超时，但直连端口 OK。
**根因**：服务器通配证书 SAN 只有 `*.sbbz.tech`，而订阅节点写 `servername: v9-y.douyinvod.com`（证书里没有该域名）。客户端一旦校验证书就握手失败（日志 `TLS handshake error ... unknown certificate`）；只有 `skip-cert-verify:true` 才勉强能连。
**解决**：把订阅节点 `servername`/`ws-opts.headers.Host` 从 `v9-y.douyinvod.com` 改为 `l.sbbz.tech`（证书 SAN 匹配），并关闭 `skip-cert-verify`。
**教训**：节点 SNI 必须使用证书实际覆盖的域名，不能随意用第三方域名伪装，否则校验必失败。

### 5. 443 端口复用（fallback）配置要点
把 WS 和 XHTTP 同时收口到公网 443，对外只暴露一个 TLS 入口，靠 path/ALPN 分流：
```json
"inbounds": [{
  "port": 443, "protocol": "vless",
  "settings": {
    "clients": [{"id": "41d4f8b3-2a45-4531-a33b-938e2eebb939"}],
    "decryption": "none",
    "fallbacks": [
      {"alpn": "h2", "dest": 18444},        // XHTTP (h2)
      {"path": "/videos", "dest": 18443}     // WS (http/1.1)
    ]
  },
  "streamSettings": {
    "network": "tcp", "security": "tls",
    "tlsSettings": {
      "certificates": [{"certificateFile": "/etc/bz/certs/server.crt", "keyFile": "/etc/bz/certs/server.key"}],
      "serverName": "l.sbbz.tech", "alpn": ["h2", "http/1.1"]
    }
  }
}, {"port": 18443, "listen": "127.0.0.1", "protocol": "vless", "streamSettings": {"network": "ws", "security": "none", "wsSettings": {"path": "/videos"}}},
   {"port": 18444, "listen": "127.0.0.1", "protocol": "vless", "streamSettings": {"network": "xhttp", "security": "none", "xhttpSettings": {"path": "/api/v1", "mode": "auto"}}}]
```
**关键点（易错）**：
- `fallbacks` 必须写在 `inbounds[].settings.fallbacks`（VLESS settings 内），**不是** `streamSettings.tlsSettings.fallbacks`。
- 主入口必须是 `network:tcp + security:tls` 且 `alpn` 含 `h2` + `http/1.1`。
- WS 走 `http/1.1` + `path` 分流；XHTTP 走 `h2` + `alpn` 分流。
- 内部端口 `127.0.0.1` 用裸协议（`security:none`），因为外层 443 已完成 TLS 终止。
- 订阅对应新增节点：`443-WS-TLS`（path /videos）、`443-XHTTP-get-v1`（path /api/v1）。

### 6. 重写配置时误删端口导致节点从外部超时
**现象**：某次完整重写 config.json 后，订阅里 `80-WS` 和 `2053-XHTTP-Reality` 节点突然不通。
**根因**：重写时只保留了 443/8443/2083，**忘了重新加入 80 和 2053 两个 inbound**，服务端根本没监听这两个端口。
**解决**：把 80（VLESS+WS 直连）和 2053（VLESS+XHTTP+Reality）两个 inbound 重新加回并 `systemctl restart xbz`。
**教训**：全量重写配置前，先列清现有订阅里所有节点对应的端口，确保每个端口都有对应 inbound，加回后逐一验证监听与连通。

### 7. 双订阅源不同步（c.sbbz.tech vs dy.sbbz.tech）
**现象**：`dy.sbbz.tech` 打开的订阅比 `c.sbbz.tech` 少一个节点，且 WS-TLS 带旧 SNI、Reality 带旧密钥。
**根因**：两者是**完全独立**的订阅源且格式不同——`c.sbbz.tech` 是 Cloudflare Pages（mihomo/clash YAML，数据在 Git sub.yaml，push 自动部署），`dy.sbbz.tech` 是 Cloudflare Worker（vless 等通用 gc 链接，节点**硬编码**在 worker JS 里）。改节点只改了 c 的 sub.yaml，没更新 dy worker。
**解决**：改 `dy` worker 源码（对齐所有节点：SNI、pbk、sid、补充新节点），执行 `npx wrangler deploy dy_worker.js --name dy --compatibility-date 2026-09-03` 重新部署。
**教训**：本项目有**两个订阅源**（c 供 mihomo、dy 供 v2rayN 等），任何节点变更（增删节点、换证书 SNI、换 Reality 密钥）后，必须同时更新 `pages/c_deploy/sub.yaml` 和 `dy` worker 两处，并用 `curl` 分别核对两边节点列表与关键字段是否一致。

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
有两个独立订阅源，**格式不同、供不同客户端使用**，改动节点时**必须同步**：
1. **`https://c.sbbz.tech/`**（Cloudflare Pages，**mihomo/clash 格式**）
   - 数据源：`pages/c_deploy/sub.yaml`，push 到 GitHub `pixian5/node` main 分支自动部署
   - 因为站点根目录只有 sub.yaml 一个文件，Pages 会兜底返回：`/`、`/sub`、`/sub.yaml` 三个路径内容相同，**无需加 sub**
   - 供 mihomo、Clash Meta 等客户端导入
2. **`https://dy.sbbz.tech/`**（Cloudflare Worker，名 `dy`，**vless 等通用 pc 链接格式**）
   - 数据源：worker 内**硬编码**的 HTML，节点用 `vless://`、`hysteria2://` 明文链接写在代码里
   - 供 v2rayN、v2rayNG 等支持通用链接的客户端导入
   - 更新方式：改 worker 源码后执行 `npx wrangler deploy dy_worker.js --name dy --compatibility-date <日期>`
   - Cloudflare API token 见全局账号，账号 `e16771787e0f6f85e8976ba3befb0c1b`

## 测试结论
- 443 端口复用：✅ TLS1.3 握手 + `/videos`(WS) 返回 101 + VLESS 通道建立；`h2`(XHTTP) ALPN 握手成功
- WS 直连 80：✅ WS 101 升级 + VLESS 通道建立
- Reality 8443：✅ 公钥 `IRn6xu8uB2Fd5-HtjnxcxNZdpAO142tttM-KH8qVpUM` 与服务器私钥推导一致
- XHTTP-Reality 2053：✅ TCP 监听开放（Reality 需专用客户端，裸连接不响应属正常）
- XHTTP-CDN 2083 / hy2 443：服务监听正常

## 免流伪装与客户端兼容
- **免流原理**：把客户端节点 TLS 的 `sni` 和 HTTP `host` 头伪装成运营商白名单的视频域名（如 `v9-y.douyinvod.com`），运营商流量检测误判为免流视频流量
- **服务器 443 端口复用只看 path/alpn 分流、不看 SNI**，所以伪装不影响连接，客户端依然连真实服务器 IP `148.100.112.30`（经 `l.sbbz.tech` 解析）
- **mihomo 兼容性坑**：`c.sbbz.tech/sub`（mihomo 订阅）**新增节点必须同时挂入 `proxy-groups` 的"代理"select 组**，否则即使 `proxies:` 里已定义，客户端也只显示组内引用到的节点、看不到新节点。这通常是新增节点"不显示"的首查原因，其次才是节点字段兼容性（`vless + network:xhttp + tls` 带 `client-fingerprint` 时 mihomo 也可能丢弃，去掉即可）
- 两订阅源节点改动需同步：`pages/c_deploy/sub.yaml`（c）与 `dy_worker.js`（dy）

## 新服务器一键完整部署（nodeallxray_2026.sh v0.0.3）
**用途**：在任何一台全新 Ubuntu 服务器上一条龙创建全部 7 节点（6 xray TCP + 1 sing-box hy2）。
**运行前（人工/控制台）**：
1. 把 `/Users/x/ed25519.pub`（`ssh-ed25519 ... root`）加入服务器 `linux1` 和 `root` 的 `~/.ssh/authorized_keys`
2. 确认本机出口 IP 不被服务器 IP 白名单拦截（否则握手前即被断）
3. 如需改子域名，先改脚本变量区 `MY_SUB`（默认 `l`）
**脚本会自动**：
- `apt update` + 装 `psmisc/tar/unzip/ca-certificates/openssl/curl/jq`
- 停止并释放 80/443/8443/2053/2083 端口
- ufw 放行全部 TCP 端口 + udp 443
- Cloudflare：创建/更新 `l.sbbz.tech`、`lvx2083.sbbz.tech`(CDN代理)、`l80.sbbz.tech` 三条 A 记录指向本机；配置 2083 回源规则
- 下载安装最新 sing-box（`/usr/local/bin/bz`）与 xray（`/usr/local/bin/xbz`），`uname -m` 自动探测架构，已覆盖 x86_64/aarch64/armv7/armv6/armv5/s390x/riscv64/ppc64le/ppc64/mips64/mips64le/i386
- 固化 Reality 密钥对到 `/etc/bz/reality.env`（新机自动生成，需同步更新两订阅源）
- 写入 xray 与 sing-box 配置、systemd 服务、通配符证书（acme.sh DNS-01，LE/ZeroSSL/GTS 依次重试）
- 配置开机自启 + 每日 acme/内核更新定时任务
- 末尾打印全部 7 节点 Clash 配置与通用分享链接
**节点-端口-内核对应**（端口全开放给 xray TCP / sing-box UDP）：
- TCP 443：xray fallback 复用 → WS-TLS（`/videos`）+ XHTTP 免流（`/api/v1`）
- TCP 80：WS 直连；TCP 8443：Reality；TCP 2083：XHTTP-CDN；TCP 2053：XHTTP-Reality
- UDP 443：hy2（sing-box）
**部署后仍需手动同步**：`pages/c_deploy/sub.yaml`（c 订阅）与 `dy_worker.js`（dy 订阅）中的 Reality `public-key`/`short-id`（如新服务器重新生成了密钥对）。

## WS-TLS vs XHTTP（传输方案选型对比）

**一句话**：WS-TLS = WebSocket 跑在 HTTP/1.1 上（流量升级成 WebSocket 隧道）；XHTTP = 伪装成现代 HTTP/2 (h2) 请求（每一帧都像普通 HTTP 请求）。底层机制不同，适用于不同目标。

| 维度 | WS-TLS（WebSocket） | XHTTP（splithttp） |
|---|---|---|
| 底层协议 | WebSocket，**官方明确只走 http/1.1** | 基于 **HTTP/2 (h2)**，新一代传输 |
| 握手形态 | `Upgrade: websocket` → **101**（特征明显） | 标准 HTTP 请求/响应（**200/204**，无升级痕迹）|
| 多路复用 | 无，每条 WS 单连接 | **有**，h2 多路复用 + 流控 |
| 抗 DPI 伪装 | 中等，101 升级是已知特征 | **更强**，流量近似普通 h2 网页请求 |
| CDN 兼容 | 好（CF/Nginx 均支持） | 好，专为 CDN 设计 |
| 客户端支持 | 极广（v2rayN/sing-box/mihomo）| 较新，需较新客户端版本 |
| 性能 | 单路，队头阻塞 | h2 多路，整体更高 |
| 服务器复用识别 | `path`（http/1.1+path 分流）| `alpn: h2`（或 path）分流 |
| 延迟 | 一次升级后复用连接 | 每请求 h2 帧，开销略高但多路补偿 |

**要点**：
- **安全性两者等同**——都靠外层 TLS 加密成数据。HTTP/1.1 vs h2 不影响安全；WS 不是"因为 http/1.1 就更弱"，而是 XHTTP 的**伪装性**更强。
- WS 的 ALPN 固定 `http/1.1`，官方明确"不要加 h2"（参考 Xray-core 官方教程 trojan+ws+tls 段）。要在 h2 上跑的同类能力是独立的 `h2`/`gRPC` transport，不是 WS。
- **端口复用靠 ALPN 天然区分，零阉割**：一个 443 入口用 `fallbacks` 按 `path`/`SNI`/`ALPN` 分流到内部不同 transport 的 inbound。各套 transport 都用自身标准 ALPN，不存在为省端口砍功能。这正是单端口多协议复用的意义（参考 XTLS/Xray-examples All-in-one-fallbacks-Nginx）。
- 本服务器 443 正是这套复用：WS `/videos`(http/1.1+path) 分流 18443；XHTTP `/api/v1`(alpn:h2) 分流 18444，主入口 443 TCP+TLS+alpn[h2,http/1.1]。

**选型建议**：
- 担心老客户端连不上 → 主用 WS-TLS
- 看重免流/伪装/抗 DPI → 主用 XHTTP
- 走 CDN 加速 → 两者皆可，XHTTP 更契合现代 CDN

**教训**：不要把"复用让 WS 走 http/1.1"理解为阉割——WS 本来就是 http/1.1。复用的价值在于零牺牲地把多种 transport 收口到单一外网 443 端口，伪装 + 抗封。