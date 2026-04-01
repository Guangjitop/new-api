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

---

如果你希望，我可以继续给你补一版：

- `MySQL` 专用部署模板
- `多节点 + 负载均衡 + 共享 Redis` 架构部署文档
