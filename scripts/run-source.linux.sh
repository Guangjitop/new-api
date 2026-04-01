#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WEB_DIR="${REPO_ROOT}/web"
LOG_DIR="${REPO_ROOT}/logs"
BACKEND_LOG="${LOG_DIR}/dev-backend.log"

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "未检测到命令: ${cmd}" >&2
    exit 1
  fi
}

wait_http_ready() {
  local url="$1"
  local timeout="${2:-30}"
  local elapsed=0
  while (( elapsed < timeout )); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

cleanup() {
  if [[ -n "${BACKEND_PID:-}" ]] && kill -0 "${BACKEND_PID}" >/dev/null 2>&1; then
    echo "==> 正在停止后端进程 (${BACKEND_PID})..."
    kill "${BACKEND_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

require_cmd go
require_cmd node
require_cmd npm
require_cmd curl

mkdir -p "${LOG_DIR}"

echo "==> 安装前端依赖（web）..."
cd "${WEB_DIR}"
npm install

echo "==> 启动后端（go run main.go）..."
cd "${REPO_ROOT}"
go run main.go >"${BACKEND_LOG}" 2>&1 &
BACKEND_PID="$!"
echo "后端 PID: ${BACKEND_PID}"

if wait_http_ready "http://localhost:3000/api/status" 40; then
  echo "后端就绪: http://localhost:3000"
else
  echo "警告：后端 40 秒内未就绪，可查看日志: ${BACKEND_LOG}" >&2
fi

echo "==> 启动前端（npm run dev）..."
echo "按 Ctrl + C 可停止前端，并自动停止后端。"
cd "${WEB_DIR}"
npm run dev
