# dy_worker.js 自动同步

`sync_dy_worker.py`：从 `pages/c_deploy/sub.yaml` 自动提取自有服务器节点，生成 vless/hysteria2 通用链接，写回 `dy_worker.js`，部署到 Cloudflare Worker（名 `dy`），最后拉线上源码比对校验。

用于消除「`c.sbbz.tech`（mihomo）和 `dy.sbbz.tech`（v2rayN）两个订阅源手工维护、容易不同步」的问题——见 `docs/server_migration_20260907.md` 第 7 条。

## 用法

```bash
# 1. 配一次凭证
cp .env.example .env && vi .env

# 2. 先看会生成什么（不写文件、不部署）
DRY_RUN=1 python3 sync_dy_worker.py

# 3. 确认无误，真正执行
python3 sync_dy_worker.py
```

需要 `pyyaml`：没装就 `pip install pyyaml`。

## 环境变量

凭证放环境变量或脚本同目录的 **`.env`** 文件（脚本自动读取，不覆盖已有环境变量）。`.env` 已在 `.gitignore` 中——**仓库是公开的，凭证绝对不能提交**。

### 必填（部署时；`DRY_RUN=1` 可省）

| 变量 | 说明 |
|---|---|
| `CF_API_TOKEN` | API Token，需 Workers 写权限。**推荐**，优先级高于下面两项 |
| `CF_API_EMAIL` + `CF_API_KEY` | 账号邮箱 + Global API Key。没有 Token 时用这个（`~/.wrangler/config/default.toml` 里就有） |
| `CF_ACCOUNT_ID` | 账户 ID，当前是 `e16771787e0f6f85e8976ba3befb0c1b` |

### 可选

| 变量 | 默认 | 说明 |
|---|---|---|
| `SUB_YAML` | `./pages/c_deploy/sub.yaml` | 订阅源路径 |
| `DY_WORKER_JS` | `./dy_worker.js` | worker 源文件 |
| `CF_WORKER_NAME` | `dy` | worker 名 |
| `CF_COMPAT_DATE` | 自动读线上现有值 | `compatibility_date`，拿不到才退回 `2026-09-07` |
| `DY_DOMAINS` | `aws.sbbz.tech,awsvx2083.sbbz.tech` | **自有服务器域名白名单**，决定哪些节点进 dy |
| `DY_NODES` | 空 | 显式节点名白名单，设了就忽略 `DY_DOMAINS` |
| `DY_DEFAULT_FP` | `chrome` | 节点没写 `client-fingerprint` 时的默认指纹 |
| `DRY_RUN` | 空 | 设为 `1` 只打印不落地 |

## 哪些节点会被同步（关键）

默认规则：节点的 `server` / `servername` / `sni` / `host`（含 ws/xhttp 的 headers.Host）**任一精确等于** `DY_DOMAINS` 中某项，就入选。

当前 35 个节点里命中 6 个：

```
80-WS-直连免流-aws、443-WS-TLS-免流-aws、歇斯底里aws
XHTTP-CDN-aws优选域名（server 是 cf.090227.xyz，靠 host awsvx2083.sbbz.tech 命中）
XHTTP-Reality-aws、Reality-aws
```

被正确排除的：氪金机场 11 个、免费日本节点、台湾、`CF_V8~V13`（它们的 SNI 是 `ygwp.sbbz.tech` 但**不是**自有服务器，所以 `DY_DOMAINS` 必须写精确域名，不能写 `sbbz.tech` 这种宽泛后缀，否则会误选）。

**换服务器时**：改 `DY_DOMAINS` 即可，比如新域名是 `xxx.sbbz.tech` 就设 `DY_DOMAINS=xxx.sbbz.tech,xxxvx2083.sbbz.tech`。

想精确控制就设 `DY_NODES`，例如 `DY_NODES=Reality-aws,歇斯底里aws`；名字写错会直接报错退出，不会静默漏掉。

## 脚本做的事（按顺序）

1. 解析 `sub.yaml` 的 `proxies`
2. 按白名单挑节点，打印命中清单
3. 生成链接：`vless` / `hysteria2` 两种；其它类型（trojan/vmess/tuic/anytls）会**跳过并提示**，不会瞎造
4. 用正则替换 `dy_worker.js` 里 `<button onclick="copyText(this)">` 与 `</button>` 之间的内容，**HTML/CSS/响应头原样保留**；文件不存在则用内置模板新建；找不到按钮块会报错退出，不会破坏文件
5. 部署：`PUT /workers/scripts/dy`（纯 JS body，service-worker 格式）
6. **补 `compatibility_date`**：上一步会把它清空，脚本紧接着 `PATCH /settings` 恢复（该接口只收 multipart）
7. 拉线上源码，比对链接集合是否完全一致，不一致就报错

## 已知约束

- **别用 `npx wrangler deploy`**：wrangler 3 在非交互环境强制要 `CLOUDFLARE_API_TOKEN`，`~/.wrangler/config/default.toml` 里的 Global API Key 它不认。脚本直接走 CF API，不需要新令牌。
- dy 是 **service-worker 格式**（`addEventListener` 写法），不能用 modules/multipart 方式上传。
- 自定义域绑定 `dy.sbbz.tech → dy` 是独立资源，PUT 脚本不影响它；可用 `GET /accounts/{id}/workers/scripts/dy/domains` 核对。
- 判断线上 worker 是什么内容，用 `GET /accounts/{id}/workers/scripts/dy` 拉源码，**别看本地文件**——本地可能落后于线上（踩过一次）。
