#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$project_dir"

fail() {
  printf '启动失败：%s\n' "$1" >&2
  if [[ -t 0 ]]; then
    read -r -p '按回车关闭窗口……' || true
  fi
  exit 1
}

# Finder 启动时的 PATH 可能不包含 Volta 或 Homebrew。
if ! command -v node >/dev/null 2>&1; then
  export PATH="${VOLTA_HOME:-$HOME/.volta}/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
fi
command -v node >/dev/null 2>&1 || fail '未找到 Node.js，请先安装 Node.js 20 或以上版本。'

port="${ONBOARDING_PORT:-4399}"
[[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] || fail 'ONBOARDING_PORT 必须是 1 到 65535 的整数。'
(( port <= 65535 )) || fail 'ONBOARDING_PORT 必须是 1 到 65535 的整数。'
console_url="http://127.0.0.1:$port"

is_ready() {
  /usr/bin/curl --noproxy '*' --fail --silent --max-time 1 \
    "$console_url/api/bootstrap" >/dev/null 2>&1
}

open_console() {
  if [[ "${TOSUB2_OPEN_BROWSER:-1}" != 0 ]]; then
    /usr/bin/open "$console_url" || printf '请在浏览器中打开：%s\n' "$console_url"
  fi
}

listener_pids="$(/usr/sbin/lsof -nP -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
if [[ -n "$listener_pids" ]]; then
  for listener_pid in $listener_pids; do
    listener_dir="$(/usr/sbin/lsof -a -p "$listener_pid" -d cwd -Fn 2>/dev/null | /usr/bin/sed -n 's/^n//p' || true)"
    listener_command="$(/bin/ps -p "$listener_pid" -o command= 2>/dev/null || true)"
    [[ "$listener_dir" == "$project_dir" && "$listener_command" == *src/console-server.mjs* ]] \
      || fail "端口 $port 已被其他程序占用，请使用其他 ONBOARDING_PORT。"
  done
  is_ready || fail "本项目已占用端口 $port，但控制台尚未就绪，请查看原启动窗口。"
  printf 'toSub2 已在运行：%s\n' "$console_url"
  open_console
  exit 0
fi

node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)' \
  || fail '需要 Node.js 20 或以上版本。'
[[ -d node_modules ]] || fail '缺少 Node.js 依赖，请先在项目目录运行 npm ci。'

export TOSUB2_PYTHON="${TOSUB2_PYTHON:-$project_dir/tmp/venv/bin/python}"
[[ -x "$TOSUB2_PYTHON" ]] || fail '未找到项目 Python 环境 tmp/venv，或 TOSUB2_PYTHON 指定的解释器不可用。'
"$TOSUB2_PYTHON" -c 'import sys, curl_cffi; sys.exit(0 if sys.version_info >= (3, 10) else 1)' \
  >/dev/null 2>&1 || fail 'Python 环境需要 3.10 或以上版本，并安装 requirements.txt 中的依赖。'

printf '正在启动 toSub2：%s\n保持此窗口运行，按 Ctrl+C 停止服务。\n' "$console_url"
launcher_pid=$$
(
  for ((attempt = 0; attempt < 30; attempt++)); do
    kill -0 "$launcher_pid" 2>/dev/null || exit 0
    if is_ready; then
      open_console
      exit 0
    fi
    sleep 0.5
  done
  printf '控制台仍未就绪，请查看上方启动日志。\n' >&2
) &

exec node src/console-server.mjs --host 127.0.0.1 --port "$port"
