#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_IMAGE_NAME="new-api:local"
DEFAULT_CONTAINER_NAME="new-api"
DEFAULT_HOST_PORT="3000"

MODE="compose"
ENV_FILE=""
ENV_FILE_SPECIFIED="false"
IMAGE_NAME="${DEFAULT_IMAGE_NAME}"
CONTAINER_NAME="${DEFAULT_CONTAINER_NAME}"
HOST_PORT="${DEFAULT_HOST_PORT}"
REPLACE_EXISTING="false"

usage() {
  cat <<'EOF'
用法：
  bash ./scripts/deploy.linux.sh [compose|docker] [选项]

模式：
  compose   使用 docker compose 部署（默认）
  docker    使用 docker build + docker run 部署

选项：
  --env-file <path>         指定环境变量文件
  --image-name <name>       docker 模式下的镜像名，默认 new-api:local
  --container-name <name>   docker 模式下的容器名，默认 new-api
  --host-port <port>        映射到宿主机的端口，默认 3000
  --replace-existing        docker 模式下若同名容器存在，先删除再重建
  -h, --help                显示帮助

示例：
  bash ./scripts/deploy.linux.sh
  bash ./scripts/deploy.linux.sh compose --env-file .env.prod
  bash ./scripts/deploy.linux.sh docker --container-name new-api-prod --host-port 3001
  bash ./scripts/deploy.linux.sh docker --env-file .env.prod --container-name new-api-prod
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "未检测到命令: ${cmd}" >&2
    exit 1
  fi
}

wait_http_ready() {
  local url="$1"
  local timeout="${2:-90}"
  local elapsed=0
  while (( elapsed < timeout )); do
    if curl -fsS "${url}" | grep -q '"success":true'; then
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

resolve_existing_env_file() {
  local requested="$1"
  if [[ -z "${requested}" ]]; then
    printf '\n'
    return 0
  fi
  if [[ -f "${REPO_ROOT}/${requested}" ]]; then
    printf '%s\n' "${REPO_ROOT}/${requested}"
    return 0
  fi
  if [[ -f "${requested}" ]]; then
    printf '%s\n' "${requested}"
    return 0
  fi
  printf '\n'
}

resolve_env_file() {
  if [[ "${ENV_FILE_SPECIFIED}" == "true" ]]; then
    local requested_path
    requested_path="$(resolve_existing_env_file "${ENV_FILE}")"
    if [[ -z "${requested_path}" ]]; then
      echo "未找到环境变量文件: ${ENV_FILE}" >&2
      exit 1
    fi
    printf '%s\n' "${requested_path}"
    return 0
  fi

  if [[ "${MODE}" == "compose" ]]; then
    local compose_env
    compose_env="$(resolve_existing_env_file ".env.prod")"
    if [[ -n "${compose_env}" ]]; then
      printf '%s\n' "${compose_env}"
      return 0
    fi
    compose_env="$(resolve_existing_env_file ".env")"
    if [[ -n "${compose_env}" ]]; then
      printf '%s\n' "${compose_env}"
      return 0
    fi
    printf '\n'
    return 0
  fi

  local docker_env
  docker_env="$(resolve_existing_env_file ".env")"
  printf '%s\n' "${docker_env}"
}

container_exists() {
  local name="$1"
  docker ps -a --format '{{.Names}}' | grep -Fxq "${name}"
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      compose|docker)
        MODE="$1"
        shift
        ;;
      --env-file)
        ENV_FILE="$2"
        ENV_FILE_SPECIFIED="true"
        shift 2
        ;;
      --image-name)
        IMAGE_NAME="$2"
        shift 2
        ;;
      --container-name)
        CONTAINER_NAME="$2"
        shift 2
        ;;
      --host-port)
        HOST_PORT="$2"
        shift 2
        ;;
      --replace-existing)
        REPLACE_EXISTING="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "未知参数: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

run_compose_mode() {
  local env_path="$1"
  local compose_args=(compose -f "docker-compose.yml")
  if [[ -n "${env_path}" ]]; then
    compose_args=(compose --env-file "${env_path}" -f "docker-compose.yml")
  else
    echo "==> 未找到环境变量文件，将使用 docker-compose.yml 内默认值"
  fi

  echo "==> 检查 Docker Compose 插件..."
  docker compose version >/dev/null

  echo "==> 开始部署（docker compose up -d --build）..."
  docker "${compose_args[@]}" up -d --build

  echo "==> 服务状态："
  docker "${compose_args[@]}" ps
}

run_docker_mode() {
  local env_path="$1"
  local data_dir="${REPO_ROOT}/data"
  local logs_dir="${REPO_ROOT}/logs"

  mkdir -p "${data_dir}" "${logs_dir}"

  echo "==> 构建镜像：${IMAGE_NAME}"
  docker build -t "${IMAGE_NAME}" "${REPO_ROOT}"

  if container_exists "${CONTAINER_NAME}"; then
    if [[ "${REPLACE_EXISTING}" == "true" ]]; then
      echo "==> 删除已存在容器：${CONTAINER_NAME}"
      docker rm -f "${CONTAINER_NAME}" >/dev/null
    else
      echo "检测到已存在同名容器：${CONTAINER_NAME}" >&2
      echo "如需替换，请显式添加 --replace-existing，或者改用 --container-name 指定新名称。" >&2
      exit 1
    fi
  fi

  local run_args=(
    run
    --name "${CONTAINER_NAME}"
    -d
    --restart always
    -p "${HOST_PORT}:3000"
    -v "${data_dir}:/data"
    -v "${logs_dir}:/app/logs"
    -e "TZ=Asia/Shanghai"
  )

  if [[ "${ENV_FILE_SPECIFIED}" != "true" ]]; then
    run_args+=(
      -e "SQL_DSN="
      -e "REDIS_CONN_STRING="
      -e "SQLITE_PATH=/data/new-api.db?_busy_timeout=30000"
    )
  fi

  if [[ -n "${env_path}" ]]; then
    run_args+=(--env-file "${env_path}")
  else
    echo "==> 未找到环境变量文件，将使用镜像内默认值"
  fi

  run_args+=("${IMAGE_NAME}" --log-dir /app/logs)

  echo "==> 开始部署（docker run）..."
  docker "${run_args[@]}"

  echo "==> 当前容器状态："
  docker ps --filter "name=^${CONTAINER_NAME}$"
}

parse_args "$@"

require_cmd docker
require_cmd curl

ENV_FILE_PATH="$(resolve_env_file "${ENV_FILE}")"
HEALTH_URL="http://localhost:${HOST_PORT}/api/status"

cd "${REPO_ROOT}"

case "${MODE}" in
  compose)
    run_compose_mode "${ENV_FILE_PATH}"
    ;;
  docker)
    run_docker_mode "${ENV_FILE_PATH}"
    ;;
  *)
    echo "不支持的部署模式: ${MODE}" >&2
    exit 1
    ;;
esac

if wait_http_ready "${HEALTH_URL}" 120; then
  echo "部署成功，服务可用: http://localhost:${HOST_PORT}"
else
  if [[ "${MODE}" == "compose" ]]; then
    echo "健康检查超时，建议执行：docker compose logs -f new-api" >&2
  else
    echo "健康检查超时，建议执行：docker logs -f ${CONTAINER_NAME}" >&2
  fi
fi
