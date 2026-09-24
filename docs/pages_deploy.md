# c.sbbz.tech（Cloudflare Pages）订阅推送说明

> 核实时间：2026-09-25。本文结论均经实测验证，非推测。

## 结论：推送方式只有一种 —— git push

`c.sbbz.tech` 的 Pages 项目（`c`）绑定的是 **Git 集成**，生产分支 = `main`，构建根目录 = `pages/c_deploy`。
因此**改完 `pages/c_deploy/sub.yaml` 后，只需 commit + push 到 GitHub `pixian5/node` 的 main 分支，Cloudflare 自动拉取并部署**，无需任何本地脚本、无需 API 调用。

```bash
cd /Users/x/code/sh
git add pages/c_deploy/sub.yaml
git commit -m "订阅：xxx"
git push node main
```

推送后 **1~2 分钟**生效（CF 构建 + 全球缓存刷新）。

## 验证部署是否生效（必做）

```bash
# 线上与本地逐字节比对
curl -s --max-time 25 https://c.sbbz.tech/sub.yaml -o /tmp/c_sub_online.yaml
shasum -a 256 /tmp/c_sub_online.yaml | cut -c1-16
shasum -a 256 pages/c_deploy/sub.yaml | cut -c1-16
```

两个 hash 一致 = 部署完成。不一致 = 还在构建中，等 1 分钟再比。
另可看响应头是否带 `subscription-userinfo` / `profile-update-interval` / `content-disposition`，有则说明 `_headers` 生效。

**不要**用浏览器打开验证——`Content-Disposition: attachment` 会触发下载，且 CDN 可能给旧缓存。用 curl 对比 hash 最可靠。

## 目录里三个文件的作用

| 文件 | 作用 |
|---|---|
| `sub.yaml` | mihomo/clash 订阅正文（约 405KB） |
| `_headers` | 对所有路径加 `Content-Type: text/plain`、`Subscription-Userinfo`（流量/到期信息，客户端据此显示剩余流量）、`Profile-Update-Interval: 30`（自动更新间隔小时数）、`Content-Disposition: attachment` |
| `_redirects` | `/*  /sub.yaml  200` —— 任意路径都返回订阅内容，所以 `/`、`/sub`、`/sub.yaml` 三个地址等价 |

`_headers` 里的流量是**硬编码**（upload=0/download=0/total=100GB/expire=1893456000），改真实流量统计要改这个文件并 push。

## 死路：`pages_deploy_c.py` 现在跑不通

仓库根目录的 `pages_deploy_c.py` 走的是 **Direct Upload（直传）** 协议（upload-token → assets/upload → upsert-hashes → 创建 deployment 四步），与 Git 集成是**两套互斥的部署通道**。

它当前**无法执行**，原因有三：

1. **手里没有具备 Pages 权限的凭证。** 用户级长期记忆里的 Cloudflare 令牌 `cfut_Xttim...` 是 **zone 级 DNS 编辑令牌**，实测：
   - `GET /user/tokens/verify` → `active`（令牌本身有效）
   - `GET /zones` → 只能看到 `sbbz.tech`
   - `GET /accounts` → **空数组**（无任何账户级权限）
   - `GET /accounts/{id}/pages/projects` → `code 10000 Authentication error`
   
   要用 Direct Upload，必须新开一个 API Token：**权限 `Account > Cloudflare Pages > Edit`，账户资源选 "Xwn4@outlook.com's Account"（`e16771787e0f6f85e8976ba3befb0c1b`）**，或者用 Global API Key + `X-Auth-Email`/`X-Auth-Key`。
2. **脚本只实现了 Global API Key 认证**（`X-Auth-Email` + `X-Auth-Key`），不支持 API Token 的 `Authorization: Bearer`。而 `CF_API_KEY` 环境变量默认空字符串。
3. **依赖缺失**：需要 Python 包 `blake3`（wrangler 的 hashFile 算法 = blake3(base64(内容)+扩展名) 取前 32 位），项目 `.venv` 和本机 Python 都没装。

### 混用的风险

一旦用 Direct Upload 成功部署一次，该项目就同时存在两种来源的部署记录（Git 提交历史 vs Direct Upload 部署），后续 `git push` 仍会覆盖它，但 CF 面板里的部署来源会混乱、回滚时容易选错版本。**Git 集成正常工作的前提下，不要碰 Direct Upload。**

## 什么时候才需要 Direct Upload

只有在这几种情况才值得去开 Pages 权限令牌：
- GitHub 被墙/推不上去，临时应急
- 订阅内容由脚本在**服务器**上动态生成，不方便走 GitHub
- 想把部署动作写进自动化（比如节点脚本改完自动上传）

真要做，改造点：
- 支持 `Authorization: Bearer <API Token>`（优先）与 `X-Auth-Email/X-Auth-Key`（兜底）两种认证
- `PAGES_SRC_DIR` 默认值改成 `pages/c_deploy`（现在是 `/tmp/c_page`）
- `.venv/bin/pip install blake3`

## 当前状态（2026-09-25 本次更新）

本次把订阅整体切到新服务器 `aws.sbbz.tech`，已推送并验证线上生效：

- **删除** `l.sbbz.tech` 全部 7 个节点
- **新增** `aws.sbbz.tech` 6 个节点：80-WS-直连免流-aws、443-WS-TLS-免流-aws、歇斯底里aws、XHTTP-CDN-aws优选域名（server 用 `cf.090227.xyz`）、XHTTP-Reality-aws、Reality-aws
- **新 Reality 密钥对**（aws 服务器）：公钥 `MvldrbhFkWi5t-KZkW82-60qR8T5tId8QVfSW60iFlk`，short-id `7d21ec15eb6a8f21`
- 住宅1 换到 `96.62.46.16:9803`（新账密，开 udp）；新增台湾、日本1-Ver.7；新增氪金机场 11 节点
- 住宅入口改为选「台湾 / 🖤东京京X06」
- rules 直连段收窄：`148.100.0.0/16` → `148.100.112.30/32`；`agentrouter.org` 指定走加拿大003

推送后 **20 秒内**线上 hash 即与本地一致（`150305b4...`），说明 Git 集成构建很快。

### 待办：dy worker 尚未同步

`dy_worker.js` 里仍是 `l.sbbz.tech`（7 处）、旧 Reality 公钥 `IRn6xu8u...`、旧 sid `d5b2242f8d6a7641`，还有已废的 `bestcf.top`（NXDOMAIN）。
按第 7 条教训，两个订阅源必须同步，否则 v2rayN 那边的节点全是失效的。需要时执行：
```bash
npx wrangler deploy dy_worker.js --name dy --compatibility-date 2026-09-25
```

## 相关：另一个订阅源 dy.sbbz.tech 不走 Pages

`dy.sbbz.tech` 是 **Cloudflare Worker**（名 `dy`），节点**硬编码**在 `dy_worker.js` 里，更新方式是：
```bash
npx wrangler deploy dy_worker.js --name dy --compatibility-date <日期>
```
改节点时**两个源必须同步改**，否则一边新一边旧（见 `docs/server_migration_20260907.md` 第 7 条）。
