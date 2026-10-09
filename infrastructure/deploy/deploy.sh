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
# ---------------------------------------------------------------------------
# 0. 前端产物
#
# 对话面由网关和 /api/ /eve/ 一起提供，三者同源——事件流是长连接，只有同源的
# 真实网络请求 fetch 才能边收边解。产物不进版本库，所以在这里现构建现上传。
# ---------------------------------------------------------------------------
say "构建对话面前端"
npm ci --prefix apps/agent-web
npm run build --prefix apps/agent-web

say "上传前端产物到 /opt/aim/web"
# 三个临时包都在这一个 trap 里清；先注册再 mktemp，中途失败也不会留下文件。
# 变量用 ${X:-}：set -u 下还没赋值的名字直接展开会让 trap 自己报错。
trap 'rm -f "${TARBALL:-}" "${WEB_TARBALL:-}" "${LEGAL_TARBALL:-}"' EXIT
WEB_TARBALL="$(mktemp -t aim-web)"
tar -czf "$WEB_TARBALL" -C apps/agent-web/dist .
scp_ -q "$WEB_TARBALL" "${REMOTE}:/tmp/aim-web.tar.gz"
ssh_ "$REMOTE" bash -euo pipefail <<'REMOTE_SCRIPT'
  rm -rf /opt/aim/web
  mkdir -p /opt/aim/web
  tar -xzf /tmp/aim-web.tar.gz -C /opt/aim/web
  rm -f /tmp/aim-web.tar.gz
  # nginx 以 nginx 用户读这些文件，目录要可进入。
  chmod -R a+rX /opt/aim/web
REMOTE_SCRIPT

say "上传法律页面到 /opt/aim/legal"
LEGAL_TARBALL="$(mktemp -t aim-legal)"
tar -czf "$LEGAL_TARBALL" -C apps/legal .
scp_ -q "$LEGAL_TARBALL" "${REMOTE}:/tmp/aim-legal.tar.gz"
ssh_ "$REMOTE" bash -euo pipefail <<'REMOTE_SCRIPT'
  rm -rf /opt/aim/legal
  mkdir -p /opt/aim/legal
  tar -xzf /tmp/aim-legal.tar.gz -C /opt/aim/legal
  rm -f /tmp/aim-legal.tar.gz
  chmod -R a+rX /opt/aim/legal
REMOTE_SCRIPT

say "打包并上传"
# mktemp 建出来的那个文件本身就是要用的目标，不能再往名字后面缀 .tar.gz——
# 那样会写到另一个路径上，mktemp 建的空文件反而留在 /tmp 里没人清。
TARBALL="$(mktemp -t aim-deploy)"
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
say "更新网关配置"
ssh_ "$REMOTE" bash -euo pipefail <<REMOTE_SCRIPT
  cp ${APP_DIR}/infrastructure/deploy/nginx-aim.conf /etc/nginx/conf.d/aim.conf
  nginx -t
  nginx -s reload
REMOTE_SCRIPT

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
  # 只看有健康检查的服务。没有健康检查的服务 Health 是空串，
  # 拿它跟 healthy 比会永远不相等，循环就白等满 5 分钟。
  for i in \$(seq 1 60); do
    pending=\$(docker compose --env-file ${APP_DIR}/.env ${COMPOSE_FILES} ps \
      --format '{{.Health}}' | grep -c starting || true)
    [ "\$pending" = "0" ] && break
    sleep 5
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
  # 对话面必须和 API 同源，否则事件流在 WebView 里收不到。
  check "对话面页面"      200 "http://127.0.0.1/agent/"
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
