#!/usr/bin/env bash
set -euo pipefail
# 定义清理函数
cleanup() {
    echo "[CLEANUP] 捕获到信号，准备终止两个服务进程..."
    ps aux | grep sglang | grep -v  /bin/bash | grep -v grep | awk '{print $2}' | xargs -r kill -9
    echo "[CLEANUP] 清理完毕！"

    # === 等待两个进程结束 ===
    echo "[INFO] 等待两个进程结束..."
    wait ${HEAD_PID}
    wait ${WORKER1_PID}

    echo "[DONE] 两个 SGLang 服务都已退出，日志保存在 ${LOG_DIR}/"
}

# 绑定信号处理（Ctrl+C、终止等）
trap cleanup SIGINT SIGTERM
# === 配置部分 ===
MODEL_PATH="/root/.cache/huggingface/Qwen2.5-32B-Instruct-AWQ/"
DIST_ADDR="sg-head:50000"
PP_SIZE=2
NNODES=2
CONFIG_NAME=${CONFIG_NAME:-"DEFAULT"}
PROJECT_NAME="SERVING"
SGLANG_PP_LAYER_PARTITION="13,51"
SGLANG_TORCH_PROFILER_DIR_HEAD=/root/sglang_workbench/logs/profile_log_head
SGLANG_TORCH_PROFILER_DIR_WORKER1=/root/sglang_workbench/logs/profile_log_worker1
# 日志文件
LOG_DIR="/root/sglang_workbench/logs/${CONFIG_NAME}/${PROJECT_NAME}"
mkdir -p "${LOG_DIR}"
mkdir -p "${SGLANG_TORCH_PROFILER_DIR_HEAD}"
mkdir -p "${SGLANG_TORCH_PROFILER_DIR_WORKER1}"
HEAD_LOG="${LOG_DIR}/sg-head.log"
WORKER1_LOG="${LOG_DIR}/sg-worker1.log"
# container之间延迟
DELAY=0ms

# === 配置tc ===
export DELAY=${DELAY}
./tc.sh


# === 启动 head 节点 ===
echo "[INFO] 启动 sg-head 上的 SGLang 服务..."
export SGLANG_PP_LAYER_PARTITION="${SGLANG_PP_LAYER_PARTITION}"
export SGLANG_TORCH_PROFILER_DIR="${SGLANG_TORCH_PROFILER_DIR_HEAD}"
python3 -m sglang.launch_server \
    --model-path "${MODEL_PATH}" \
    --pp "${PP_SIZE}" \
    --dist-init-addr "${DIST_ADDR}" \
    --nnodes "${NNODES}" \
    --node-rank 0 \
    --mem-fraction-static 0.7 \
    --disable-cuda-graph \
    > "${HEAD_LOG}" 2>&1 &

HEAD_PID=$!

# === SSH 到 worker1 上启动 SGLang 服务 ===
echo "[INFO] SSH 到 sg-worker1 上，启动 SGLang 服务..."
sshpass -p "123456" ssh sg-worker1 bash -c "
    set -euo pipefail
    export SGLANG_PP_LAYER_PARTITION=\"${SGLANG_PP_LAYER_PARTITION}\"
    export SGLANG_TORCH_PROFILER_DIR=\"${SGLANG_TORCH_PROFILER_DIR_WORKER1}\"
    python3 -m sglang.launch_server \
        --model-path \"${MODEL_PATH}\" \
        --pp \"${PP_SIZE}\" \
        --dist-init-addr \"${DIST_ADDR}\" \
        --nnodes \"${NNODES}\" \
        --node-rank 1 \
        --mem-fraction-static 0.7 \
        --disable-cuda-graph 
" > "${WORKER1_LOG}" 2>&1 &

WORKER1_PID=$!

tail -f /dev/null