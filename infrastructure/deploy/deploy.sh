#!/usr/bin/env bash
#
# 把当前提交部署到生产。
#
# 用法（在仓库根目录）：
#   infrastructure/deploy/deploy.sh <部署机 IP 或 SSH 别名>
#
# 主机地址不在版本库里，所以必须显式传——见未跟踪的 LOCAL.md。
#
# 这个脚本是幂等的：重复跑一次等于重新部署当前提交，不会累积状态。
# 它只做部署，不碰数据卷；备份是 aim-backup.sh 的事。

set -euo pipefail

HOST="${1:?用法: deploy.sh <部署机 IP 或 SSH 别名>}"
SSH_USER="${AIM_SSH_USER:-root}"
REMOTE="${SSH_USER}@${HOST}"

# 部署密钥不叫 id_rsa 这类默认名字，ssh 不会自己找到它。用 AIM_SSH_KEY 指定，
# 不设就走 ssh 的默认发现（ssh-agent 或 ~/.ssh/config 里配好的情况）。
SSH_OPTS=()
if [ -n "${AIM_SSH_KEY:-}" ]; then
  SSH_OPTS=(-i "$AIM_SSH_KEY")
fi
ssh_() { ssh "${SSH_OPTS[@]}" "$@"; }
scp_() { scp "${SSH_OPTS[@]}" "$@"; }
APP_DIR=/opt/aim/app
COMPOSE_FILES="-f compose.yaml -f compose.prod.yaml"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# 未提交的改动不会进 git archive，跑完却看起来像部署了——先拦住。
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "工作区有未提交的改动，先提交或 stash。git archive 只打包已提交的内容。" >&2
  exit 1
fi

REVISION="$(git rev-parse --short HEAD)"
say "部署 ${REVISION} 到 ${REMOTE}"

# ---------------------------------------------------------------------------
# 1. 打包上传
#
# 用 git archive 而不是 rsync 整个目录：node_modules、.venv、构建产物都不该上传，
# 而 .gitignore 的规则 git archive 天然就遵守。
# ---------------------------------------------------------------------------
say "打包并上传"
# mktemp 建出来的那个文件本身就是要用的目标，不能再往名字后面缀 .tar.gz——
# 那样会写到另一个路径上，mktemp 建的空文件反而留在 /tmp 里没人清。
TARBALL="$(mktemp -t aim-deploy)"
trap 'rm -f "$TARBALL"' EXIT
git archive --format=tar.gz -o "$TARBALL" HEAD
scp_ -q "$TARBALL" "${REMOTE}:/tmp/aim-deploy.tar.gz"

say "解压到 ${APP_DIR}"
ssh_ "$REMOTE" bash -euo pipefail <<REMOTE_SCRIPT
  mkdir -p ${APP_DIR}
  # 只删代码，保住 .env（600 权限，不在版本库）和其它运行时文件。
  find ${APP_DIR} -mindepth 1 -maxdepth 1 ! -name '.env' -exec rm -rf {} +
  tar -xzf /tmp/aim-deploy.tar.gz -C ${APP_DIR}
  rm -f /tmp/aim-deploy.tar.gz
  test -f ${APP_DIR}/.env || { echo "缺少 ${APP_DIR}/.env，部署中止" >&2; exit 1; }
REMOTE_SCRIPT

# ---------------------------------------------------------------------------
# 2. 构建并起服务
#
# api 与 eve 必须同批部署：eve 的鉴权依赖 api 新增的
# /internal/agent-tools/resolve-session，先起 eve 会让所有 agent 请求 401。
# compose 一次性 up 就满足这个次序。
#
# 不设短超时：这台机器拉基础镜像慢（node:24 约 3 分钟），中途打断会让 dockerd
# context canceled 并清掉已下载的层，前功尽弃。
# ---------------------------------------------------------------------------
say "构建镜像并启动（较慢，勿中断）"
ssh_ "$REMOTE" bash -euo pipefail <<REMOTE_SCRIPT
  cd ${APP_DIR}/infrastructure/compose
  docker compose --env-file ${APP_DIR}/.env ${COMPOSE_FILES} up -d --build
REMOTE_SCRIPT

# ---------------------------------------------------------------------------
# 3. 验证
#
# 只看「起来了」不够：健康检查过了但鉴权坏掉的话，用户照样进不去。
# 所以既查健康，也查未授权请求确实被拒。
# ---------------------------------------------------------------------------
say "等待服务就绪"
ssh_ "$REMOTE" bash -euo pipefail <<REMOTE_SCRIPT
  cd ${APP_DIR}/infrastructure/compose
  for i in \$(seq 1 60); do
    if docker compose --env-file ${APP_DIR}/.env ${COMPOSE_FILES} ps --format '{{.Service}} {{.Health}}' \
       | grep -qv healthy; then sleep 5; else break; fi
  done
  docker compose --env-file ${APP_DIR}/.env ${COMPOSE_FILES} ps --format '{{.Service}}\t{{.Status}}'
REMOTE_SCRIPT

say "验证对外接口"
ssh_ "$REMOTE" bash -euo pipefail <<'REMOTE_SCRIPT'
  fail=0
  check() {
    local label="$1" expected="$2" url="$3"
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$url" || echo 000)"
    if [ "$code" = "$expected" ]; then
      printf '  ✓ %-28s HTTP %s\n' "$label" "$code"
    else
      printf '  ✗ %-28s HTTP %s（期望 %s）\n' "$label" "$code" "$expected"
      fail=1
    fi
  }
  check "网关健康"        200 "http://127.0.0.1/health"
  check "API 健康"        200 "http://127.0.0.1/api/v1/health"
  # 无票访问 Eve 必须 401。这条是这次安全修复的核心断言：
  # 身份只能从签名会话票推导，自报的 x-aim-* 头一概不作数。
  check "Eve 无票被拒"     401 "http://127.0.0.1/eve/v1/info"
  exit $fail
REMOTE_SCRIPT

say "验证伪造身份被拒"
ssh_ "$REMOTE" bash -euo pipefail <<'REMOTE_SCRIPT'
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
    -H 'x-aim-account-id: 11111111-1111-1111-1111-111111111111' \
    -H 'x-aim-family-id: 22222222-2222-2222-2222-222222222222' \
    -H 'x-aim-pregnancy-id: 33333333-3333-3333-3333-333333333333' \
    "http://127.0.0.1/eve/v1/info" || echo 000)"
  if [ "$code" = "401" ]; then
    printf '  ✓ %-28s HTTP %s\n' "自报 scope 头被拒" "$code"
  else
    printf '  ✗ %-28s HTTP %s（期望 401，说明鉴权洞还在）\n' "自报 scope 头被拒" "$code"
    exit 1
  fi
REMOTE_SCRIPT

say "部署完成：${REVISION}"
echo
echo "提醒：eve 升级会让升级前创建的对话读不回来（CORRUPTED_EVENT_LOG）。"
echo "     客户端会显示「这段对话的内容已不可用」，不会白屏。"
