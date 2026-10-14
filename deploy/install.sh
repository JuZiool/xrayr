#!/bin/bash
# XrayR 一键部署脚本（标准 Docker）
#
# 用法（在 clone 出来的仓库根目录）:
#   sudo bash deploy/install.sh
#
# 脚本做的事:
#   1. 检查 docker / docker compose
#   2. 把 release/config/ 下的资源文件复制到 deploy/config/
#   3. 首次运行时从模板生成 deploy/config/config.yml
#   4. 从 GHCR 拉取镜像
#   5. 校验配置并启动容器

set -e

# 定位到仓库根目录（本脚本在 deploy/ 下）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; PLAIN='\033[0m'
info() { echo -e "${GREEN}[+]${PLAIN} $*"; }
warn() { echo -e "${YELLOW}[!]${PLAIN} $*"; }
err()  { echo -e "${RED}[x]${PLAIN} $*"; }

IMAGE="ghcr.io/juziool/xrayr:latest"

# ---------- 1. 环境检查 ----------
if ! command -v docker >/dev/null 2>&1; then
    err "未找到 docker，请先安装："
    err "  curl -fsSL https://get.docker.com | bash"
    exit 1
fi
info "docker: $(docker --version)"

if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DC="docker-compose"
else
    err "未找到 docker compose，请安装 compose 插件。"
    exit 1
fi
info "compose: $DC"

if [ "$(id -u)" -ne 0 ]; then
    warn "当前非 root，docker 命令可能因权限失败。建议 sudo 运行。"
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|aarch64|armv7l|armv6l|s390x)
        info "架构: $ARCH（镜像支持 amd64/arm64/armv6/armv7/s390x）" ;;
    *)
        warn "架构 $ARCH 不在镜像支持列表内，可能无法运行。" ;;
esac

# ---------- 2. 准备配置目录与资源文件 ----------
mkdir -p config

SRC="$REPO_ROOT/release/config"
if [ -d "$SRC" ]; then
    for f in geoip.dat geosite.dat dns.json route.json \
             custom_inbound.json custom_outbound.json rulelist; do
        if [ -f "$SRC/$f" ]; then
            if [ ! -f "config/$f" ]; then
                cp "$SRC/$f" "config/$f"
                info "复制 config/$f"
            fi
        fi
    done
else
    warn "未找到 $SRC，跳过资源文件复制。"
fi

# ---------- 3. 生成配置 ----------
if [ -f config/config.yml ]; then
    info "config/config.yml 已存在，保留现有配置。"
else
    cp config.yml.example config/config.yml
    warn "已从模板生成 config/config.yml，必须先填写面板信息再启动。"
fi

if grep -q "CHANGE_ME" config/config.yml 2>/dev/null; then
    err "config/config.yml 仍含 CHANGE_ME 占位符。"
    err "请编辑该文件填入 ApiHost / ApiKey / NodeID / NodeType，然后重新运行本脚本。"
    exit 1
fi
info "配置检查通过（未发现占位符）。"

# ---------- 4. 准备镜像 ----------
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    info "镜像 $IMAGE 已存在，跳过拉取。"
elif docker pull "$IMAGE"; then
    info "镜像拉取完成。"
else
    err "镜像拉取失败。若服务器在墙内，请为 docker 配置代理或镜像加速后重试。"
    exit 1
fi

# ---------- 5. 校验配置 ----------
info "校验配置文件..."
docker run --rm \
    -v "$(pwd)/config:/etc/XrayR" \
    --entrypoint /usr/local/bin/XrayR \
    "$IMAGE" config check -c /etc/XrayR/config.yml

# ---------- 6. 启动 ----------
info "启动容器..."
$DC up -d

sleep 5
echo
info "容器状态:"
$DC ps
echo
info "最近日志:"
$DC logs --tail 25 || true
echo
echo "----------------------------------------------------------"
echo " 常用命令:"
echo "   $DC logs -f --tail 100          # 实时日志"
echo "   $DC restart                     # 重启（改配置后执行）"
echo "   $DC pull && $DC up -d           # 更新镜像"
echo "   $DC down                        # 停止并移除"
echo
echo " 诊断（推荐先跑）:"
echo "   docker exec xrayr XrayR doctor -c /etc/XrayR/config.yml --timeout 5s"
echo "----------------------------------------------------------"
