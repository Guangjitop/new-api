# New API 服务器部署教程（Ubuntu + Docker Compose + Nginx + HTTPS）

本文档提供一套可直接落地的生产部署流程，目标环境：

- 系统：Ubuntu 22.04 LTS
- 部署方式：Docker Compose
- 反向代理：Nginx
- HTTPS：Let's Encrypt（Certbot）
- 域名示例：`api.example.com`

## 1. 前置准备

准备以下信息：

- 一台公网 Linux 服务器（建议至少 `2C4G`）
- 一个已解析到服务器公网 IP 的域名（示例：`api.example.com`）
- 可用的 SSH 账号（具备 `sudo` 权限）

开放端口建议：

- `22`（SSH）
- `80`（HTTP，用于证书签发）
- `443`（HTTPS）

## 2. 安装 Docker 与 Compose 插件

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable docker
sudo systemctl start docker
docker --version
docker compose version
```

## 3. 准备项目目录

```bash
sudo mkdir -p /opt/new-api
sudo chown -R $USER:$USER /opt/new-api
cd /opt/new-api
```

将项目代码上传到服务器后，进入项目目录（示例）：

```bash
cd /opt/new-api/new-api
```

## 4. 生成生产密钥与环境变量

生成随机密钥：

```bash
openssl rand -hex 32
openssl rand -hex 32
```

把生成结果分别用于：

- `SESSION_SECRET`
- `CRYPTO_SECRET`

建议在项目根目录创建 `.env.prod`（不提交到仓库）：

```bash
cat > .env.prod <<'EOF'
TZ=Asia/Shanghai
SESSION_SECRET=替换为32字节以上随机串
CRYPTO_SECRET=替换为32字节以上随机串
SQL_DSN=postgresql://root:强密码@postgres:5432/new-api
REDIS_CONN_STRING=redis://redis:6379/0
ERROR_LOG_ENABLED=true
BATCH_UPDATE_ENABLED=true
EOF
```

## 5. 启动服务（Docker Compose）

项目已提供 `docker-compose.yml`，可直接用于单机生产部署。

启动前请先改掉默认数据库密码，并保证与 `SQL_DSN` 一致：

1. 编辑 `docker-compose.yml` 中 `new-api` 服务的 `SQL_DSN`
2. 编辑同文件 `postgres` 服务的 `POSTGRES_PASSWORD`
3. 两处密码必须一致（例如都改成 `YourStrongPassword`）

首次启动：

```bash
cd /opt/new-api/new-api
docker compose --env-file .env.prod up -d --build
```

查看状态：

```bash
docker compose ps
docker compose logs -f new-api
```

健康检查（服务内部）：

```bash
curl -sS http://127.0.0.1:3000/api/status
```

看到 `success: true` 说明主服务正常。

## 6. 配置 Nginx 反向代理

安装 Nginx：

```bash
sudo apt-get install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

创建站点配置：

```bash
sudo tee /etc/nginx/sites-available/new-api.conf > /dev/null <<'EOF'
server {
    listen 80;
    server_name api.example.com;

    client_max_body_size 50m;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 流式响应建议关闭缓冲，减少延迟
        proxy_buffering off;
        proxy_read_timeout 3600s;
    }
}
EOF
```

启用配置并检查：

```bash
sudo ln -sf /etc/nginx/sites-available/new-api.conf /etc/nginx/sites-enabled/new-api.conf
sudo nginx -t
sudo systemctl reload nginx
```

## 7. 签发 HTTPS 证书（Let's Encrypt）

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.example.com
```

按提示完成后，验证自动续期：

```bash
sudo certbot renew --dry-run
```

## 8. 防火墙与安全基线

如果使用 UFW：

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
sudo ufw status
```

生产建议：

- 修改数据库默认密码（`postgres` 服务中的 `POSTGRES_PASSWORD`）
- 不对公网暴露数据库与 Redis 端口
- `SESSION_SECRET` 和 `CRYPTO_SECRET` 必须为高强度随机值
- 定期备份 `data` 目录和数据库

## 9. 日常运维命令

更新并重建：

```bash
cd /opt/new-api/new-api
git pull
docker compose --env-file .env.prod up -d --build
```

查看日志：

```bash
docker compose logs -f --tail=200 new-api
```

重启服务：

```bash
docker compose restart new-api
```

停止服务：

```bash
docker compose down
```

## 10. 升级与回滚建议

推荐流程：

1. 先备份数据库与 `data` 目录
2. 在测试环境验证新版本
3. 生产执行 `docker compose up -d --build`
4. 观察日志和 `/api/status` 健康状态

快速回滚思路：

- 切回旧版本代码或旧镜像标签
- 重新执行 `docker compose up -d`

## 11. 常见问题排查

### 11.1 页面打不开

- 检查进程：`docker compose ps`
- 检查端口：`ss -lntp | grep -E '3000|80|443'`
- 检查 Nginx：`sudo nginx -t`

### 11.2 登录状态异常（多实例尤其明显）

- 检查是否设置 `SESSION_SECRET`
- 多实例必须保持 `SESSION_SECRET` 一致

### 11.3 使用 Redis 后解密失败

- 检查是否设置 `CRYPTO_SECRET`
- 多实例必须保持 `CRYPTO_SECRET` 一致

### 11.4 数据库连接失败

- 校验 `SQL_DSN` 用户名、密码、库名、地址
- 进入容器检查：`docker compose exec new-api env | grep SQL_DSN`

## 12. 保姆级源码部署（非 Docker）

这一节是纯源码部署，适合你不想用 Docker，或者要接入公司已有运维体系（systemd、日志采集、主机监控）的场景。

### 12.1 路线选择

- 路线 A（先跑起来）：`SQLite` 单机部署，最快
- 路线 B（生产推荐）：`PostgreSQL + Redis`，更稳

### 12.2 服务器初始化

以下命令以 `Ubuntu 22.04` 为例，先装基础依赖：

```bash
sudo apt-get update
sudo apt-get install -y git curl unzip build-essential nginx
```

安装 Go（建议与项目 Dockerfile 对齐，使用 `1.26.1`）：

```bash
cd /tmp
curl -LO https://go.dev/dl/go1.26.1.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.26.1.linux-amd64.tar.gz
echo 'export PATH=/usr/local/go/bin:$PATH' | sudo tee /etc/profile.d/go.sh > /dev/null
source /etc/profile.d/go.sh
go version
```

安装 Bun（前端构建要用）：

```bash
curl -fsSL https://bun.sh/install | bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
bun --version
```

### 12.3 拉代码并构建

```bash
sudo mkdir -p /opt/new-api
sudo chown -R $USER:$USER /opt/new-api
cd /opt/new-api
git clone <你的仓库地址> new-api
cd /opt/new-api/new-api
```

构建前端静态资源（生成 `web/dist`）：

```bash
cd /opt/new-api/new-api/web
bun install
DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat /opt/new-api/new-api/VERSION) bun run build
```

构建后端二进制：

```bash
cd /opt/new-api/new-api
go mod download
go build -ldflags "-s -w -X 'github.com/Guangjitop/new-api/common.Version=$(cat VERSION)'" -o new-api
```

验证二进制：

```bash
./new-api --help
```

### 12.4 配置运行目录和环境变量

创建目录：

```bash
mkdir -p /opt/new-api/new-api/logs
mkdir -p /opt/new-api/new-api/data
```

#### 路线 A：SQLite（先跑通）

```bash
cat > /opt/new-api/new-api/.env.prod <<'EOF'
TZ=Asia/Shanghai
PORT=3000
SQLITE_PATH=/opt/new-api/new-api/data/one-api.db?_busy_timeout=30000
SESSION_SECRET=替换为随机字符串
CRYPTO_SECRET=替换为随机字符串
ERROR_LOG_ENABLED=true
EOF
```

#### 路线 B：PostgreSQL + Redis（生产推荐）

```bash
cat > /opt/new-api/new-api/.env.prod <<'EOF'
TZ=Asia/Shanghai
PORT=3000
SESSION_SECRET=替换为随机字符串
CRYPTO_SECRET=替换为随机字符串
SQL_DSN=postgresql://newapi_user:强密码@127.0.0.1:5432/new-api
REDIS_CONN_STRING=redis://127.0.0.1:6379/0
ERROR_LOG_ENABLED=true
BATCH_UPDATE_ENABLED=true
EOF
```

生成随机串（建议至少 32 字节）：

```bash
openssl rand -hex 32
openssl rand -hex 32
```

### 12.5 先手动启动验活

```bash
cd /opt/new-api/new-api
set -a
source ./.env.prod
set +a
./new-api --port "${PORT:-3000}" --log-dir /opt/new-api/new-api/logs
```

新开一个终端检查：

```bash
curl -sS http://127.0.0.1:3000/api/status
```

返回 `success: true` 后，`Ctrl + C` 停掉，继续做 systemd 托管。

### 12.6 配置 systemd 守护进程

创建 service 文件：

```bash
sudo tee /etc/systemd/system/new-api.service > /dev/null <<'EOF'
[Unit]
Description=New API Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/new-api/new-api
EnvironmentFile=/opt/new-api/new-api/.env.prod
ExecStart=/opt/new-api/new-api/new-api --port 3000 --log-dir /opt/new-api/new-api/logs
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
```

加载并启动：

```bash
sudo systemctl daemon-reload
sudo systemctl enable new-api
sudo systemctl restart new-api
sudo systemctl status new-api --no-pager
```

日志查看：

```bash
journalctl -u new-api -f
```

### 12.7 接入 Nginx 与 HTTPS

源码部署的 Nginx/HTTPS 配置与上文第 `6`、第 `7` 节完全一致，直接复用即可。

### 12.8 源码部署升级流程

```bash
cd /opt/new-api/new-api
git pull

cd /opt/new-api/new-api/web
bun install
DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat /opt/new-api/new-api/VERSION) bun run build

cd /opt/new-api/new-api
go build -ldflags "-s -w -X 'github.com/Guangjitop/new-api/common.Version=$(cat VERSION)'" -o new-api
sudo systemctl restart new-api
```

升级后验活：

```bash
curl -sS http://127.0.0.1:3000/api/status
```

## 13. 一次真实上线的经验总结（Debian 13 + 1G 小机 + Cloudflare）

这一节不是“理论推荐”，而是一次真实落地后的复盘，适合下面这种环境：

- 系统：`Debian 13`
- 机器配置：`1C1G` + `1G swap`
- 域名接入：`Cloudflare` 代理
- 最终方案：`源码部署 + SQLite + systemd + Nginx + Let's Encrypt`

### 13.1 小内存机器别硬刚 Docker 构建

如果你的服务器只有 `1G` 左右内存，不建议直接在机器上执行 `docker compose up -d --build` 或本地源码全量构建：

- 前端构建需要 `bun install` + `bun run build`
- 后端构建需要 `go build`
- 两段叠在一起，特别容易把小机内存打满

更稳的做法有两种：

1. 本地先构建 Linux 二进制和 `web/dist`，再上传到服务器
2. 服务器直接走“源码部署”，但要接受构建时间更长、资源更紧张

如果只是先把服务跑起来，`SQLite + systemd` 往往比 `Docker + PostgreSQL + Redis` 更省心。

### 13.2 源码部署时别忘了 `web/dist`

源码部署最容易踩的坑是：仓库里默认**不包含** `web/dist`。

这意味着你如果只是：

```bash
git clone ...
go build ...
```

后端虽然能启动，但前端页面不一定完整。正确方式是二选一：

```bash
cd /opt/new-api/new-api/web
bun install
DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat /opt/new-api/new-api/VERSION) bun run build
```

或者：

- 在本地构建好 `web/dist`
- 和 Linux 二进制一起上传到服务器

### 13.3 `systemd` 托管比后台挂进程稳得多

单机部署推荐直接用 `systemd` 托管，不要长期依赖 `nohup` 或手工开终端顶着：

```ini
[Unit]
Description=New API Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/new-api/new-api
EnvironmentFile=/opt/new-api/new-api/.env.prod
ExecStart=/opt/new-api/new-api/new-api --port 3000 --log-dir /opt/new-api/new-api/logs
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
```

最少要保证这些目录存在：

- `/opt/new-api/new-api/logs`
- `/opt/new-api/new-api/data`

### 13.4 Cloudflare 出现 `521`，先查源站 `80/443`

如果域名挂了 `Cloudflare` 代理，浏览器里看到 `521`，不要一上来怀疑项目代码，先查这几个点：

1. 源站 `80/443` 是否真的在监听
2. `Nginx` 是否已经启动
3. Cloudflare DNS 记录是否真的指向当前服务器公网 IP
4. 服务器防火墙是否放行 `80/443`

实战里最常见的情况是：

- `new-api` 在 `3000` 跑着
- 但 `Nginx` 没装、没启动，或者没正确接管 `80/443`
- 结果 Cloudflare 回源失败，直接给你一个 `521`

排查命令：

```bash
ss -lntp | grep -E ':80|:443|:3000'
systemctl status nginx --no-pager
curl -sS http://127.0.0.1:3000/api/status
curl -sS http://127.0.0.1/api/status
```

### 13.5 健康检查优先用 `GET /api/status`

实战里建议统一用：

```bash
curl -sS http://127.0.0.1:3000/api/status
curl -sS https://your-domain/api/status
```

不要把 `HEAD /api/status` 当成唯一判断依据。某些代理链路下，`HEAD` 的返回并不稳定，容易误判成服务挂了。

### 13.6 Nginx 先求稳，先打通再谈优雅

如果你发现域名能打开默认欢迎页、但接口没反代成功，不要跟默认站点死磕太久。对于单域名单服务，最稳的方式是先让 `Nginx` 直接接管默认站点：

```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _ your-domain;

    client_max_body_size 50m;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_read_timeout 3600s;
    }
}
```

先确认 `http://your-domain/api/status` 返回 `success: true`，再交给 `certbot` 接手 HTTPS。

### 13.7 证书申请完成后要做两次验收

证书不是申请成功就完事，至少补这两步：

```bash
curl -I https://your-domain/
curl -sS https://your-domain/api/status
certbot renew --dry-run
```

重点看三件事：

- `443` 已正常监听
- 业务接口能返回 JSON，而不是跳错页面
- 自动续期模拟能通过

### 13.8 初始化完成后别忘了改正式域名配置

首次部署完成后，后台初始化时还会带着一些默认值。至少要检查：

- 站点地址是否还是 `http://localhost:3000`
- Passkey / OAuth / 回调域名是否仍是本地地址

如果你已经切到正式域名，建议在后台把相关配置统一改成你的线上地址，否则后面做登录、Passkey、三方回调时会继续踩坑。

### 13.9 一份够用的上线后自检清单

上线后至少确认以下项目：

- `systemctl is-active new-api` 返回 `active`
- `systemctl is-active nginx` 返回 `active`
- `curl -sS http://127.0.0.1:3000/api/status` 成功
- `curl -sS https://your-domain/api/status` 成功
- `https://your-domain/api/setup` 能正常返回初始化状态
- `certbot renew --dry-run` 成功
- `journalctl -u new-api -f` 中没有持续报错

---

如果你希望，我可以继续给你补一版：

- `MySQL` 专用部署模板
- `多节点 + 负载均衡 + 共享 Redis` 架构部署文档
