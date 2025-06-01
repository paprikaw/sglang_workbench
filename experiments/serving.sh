#!/usr/bin/env bash
set -euo pipefail

# === 配置部分 ===
MODEL_PATH="/root/.cache/huggingface/Qwen2.5-32B-Instruct-AWQ/"
DIST_ADDR="sg-head:20000"
PP_SIZE=2
NNODES=2
CONFIG_NAME=${CONFIG_NAME:-"DEFAULT"}
PROJECT_NAME="SERVING"
# 日志文件
LOG_DIR="/root/sglang_workbench/logs/${CONFIG_NAME}/${PROJECT_NAME}"
mkdir -p "${LOG_DIR}"
HEAD_LOG="${LOG_DIR}/sg-head.log"
WORKER1_LOG="${LOG_DIR}/sg-worker1.log"

# === 启动 head 节点 ===
echo "[INFO] 启动 sg-head 上的 SGLang 服务..."
python3 -m sglang.launch_server \
    --model-path "${MODEL_PATH}" \
    --pp "${PP_SIZE}" \
    --dist-init-addr "${DIST_ADDR}" \
    --nnodes "${NNODES}" \
    --node-rank 0 \
    --disable-cuda-graph \
    > "${HEAD_LOG}" 2>&1 &

HEAD_PID=$!

# === SSH 到 worker1 上启动 SGLang 服务 ===
echo "[INFO] SSH 到 sg-worker1 上，启动 SGLang 服务..."
sshpass -p "123456" ssh sg-worker1 bash -c "'
    set -euo pipefail
    python3 -m sglang.launch_server \
        --model-path \"${MODEL_PATH}\" \
        --pp \"${PP_SIZE}\" \
        --dist-init-addr \"${DIST_ADDR}\" \
        --nnodes \"${NNODES}\" \
        --node-rank 1 \
        --disable-cuda-graph \
        2>&1
'" | tee "${WORKER1_LOG}" &

WORKER1_PID=$!

# === 等待两个进程结束 ===
echo "[INFO] 等待两个进程结束..."
wait ${HEAD_PID}
wait ${WORKER1_PID}

echo "[DONE] 两个 SGLang 服务都已退出，日志保存在 ${LOG_DIR}/"