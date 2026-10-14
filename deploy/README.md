# 从 GitHub 直接部署

服务器上 `git clone` 本仓库即可部署，无需手动上传任何文件。

## 镜像

由 GitHub Actions 构建并发布，公开可拉，支持 5 种架构：

```
ghcr.io/juziool/xrayr:latest
```

`linux/amd64`、`linux/arm64`、`linux/arm/v6`、`linux/arm/v7`、`linux/s390x`

## 快速部署

```bash
# 1. 装 Docker（已装可跳过）
curl -fsSL https://get.docker.com | bash
systemctl enable --now docker

# 2. 克隆仓库
git clone https://github.com/JuZiool/xrayr.git
cd xrayr

# 3. 填配置
vi deploy/config.yml.example        # 见下方「必改项」

# 4. 部署
sudo bash deploy/install.sh
```

> 第 3 步改的是 `deploy/config.yml.example`。脚本首次运行会把它复制成 `deploy/config/config.yml`。
> 如果你已经跑过一次脚本，直接改 `deploy/config/config.yml` 即可。

## 必改项

```yaml
Nodes:
  - PanelType: Xboard      # 面板类型
    ApiConfig:
      ApiHost: https://你的面板域名    # 面板地址
      ApiKey: 你的节点密钥             # 面板后台生成
      NodeID: 1                      # 面板里的节点 ID
      NodeType: Vless                # Vless / V2ray / Vmess / Trojan / Shadowsocks
```

`PanelType` 可选：`Xboard`、`SSpanel`、`V2board`、`NewV2board`、`PMpanel`、`Proxypanel`、`V2RaySocks`、`GoV2Panel`、`BunPanel`。

## install.sh 做的事

1. 检查 docker / docker compose / 架构
2. 从 `release/config/` 复制资源文件（geoip.dat、geosite.dat、dns.json、route.json 等）到 `deploy/config/`
3. 首次运行时从 `config.yml.example` 生成 `config/config.yml`
4. 校验配置里没有遗留的 `CHANGE_ME` 占位符（有则中止）
5. 从 GHCR 拉取镜像
6. 用镜像校验配置语法
7. 启动容器并打印状态与日志

脚本可重复运行：已有配置不会被覆盖，已有镜像不会重复拉取。

## 上线后诊断

```bash
docker exec xrayr XrayR doctor -c /etc/XrayR/config.yml --timeout 5s
```

逐项检查配置 schema、DNS 解析、TCP/TLS 连通性、面板 API 拉取节点与用户列表。面板对接有问题会在这里明确指出。

## 日常管理

```bash
cd deploy
docker compose logs -f --tail 100                    # 实时日志
docker compose restart                               # 重启（改配置后执行）
docker compose pull && docker compose up -d          # 更新镜像
docker compose down                                  # 停止并移除
```

## 注意事项

**用 host 网络。** compose 里已配 `network_mode: host`。XrayR 是后端，端口由面板下发且不固定，bridge 模式无法预知要映射哪些端口。

**防火墙只开节点端口。** 开面板分配给你的那些端口即可。证书若用 `CertMode: dns`（DNS 验证），不需要开放 80/443；用 `http` 需要 80，用 `tls` 需要 443。

**全局在线 IP 限制需要 Redis。** 要用得在宿主机装 Redis，并配好 `GlobalDeviceLimitConfig`。容器是 host 网络，直接连 `127.0.0.1:6379` 即可。

**首次启动若面板不可达会退出。** 日志报 `open /etc/XrayR/cache/<hash>.json: no such file or directory` 不是缺目录，是快照回退逻辑没找到历史快照（代码里用 `os.MkdirAll` 自建目录）。填对凭据后第一次成功启动会写出快照，之后面板短暂抖动可自动回退（默认 86400 秒）。有 `restart: always`，容器会自己重试。

**国内服务器拉 GHCR 可能超时。** 需给 docker 配置代理或镜像加速。若确实拉不到，可改用离线包：仓库的 Release 里附带各平台预编译二进制，或在能联网的机器上 `docker save` 后传入。

**更新镜像。** `latest` 标签在打 tag 时更新。触发方式：`git tag v0.9.9 && git push origin v0.9.9`，或在 GitHub Actions 页面手动触发 `Publish Docker image`。服务器上 `docker compose pull && docker compose up -d` 拉新版。
