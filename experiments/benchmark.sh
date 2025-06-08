#!/usr/bin/env bash
set -euo pipefail
# 定义清理函数
cleanup() {
    echo "[CLEANUP] 捕获到信号，准备终止两个服务进程..."
    ps aux | grep sglang | grep -v  /bin/bash | grep -v grep | awk '{print $2}' | xargs -r kill -9
    echo "[CLEANUP] 清理完毕！"
}

# 绑定信号处理（Ctrl+C、终止等）
trap cleanup SIGINT SIGTERM EXIT
# === 配置部分 ===
MODEL_PATH="/root/.cache/huggingface/Qwen2.5-32B-Instruct-AWQ/"
DIST_ADDR="sg-head:50000"
PP_SIZE=2
NNODES=2
CONFIG_NAME=${CONFIG_NAME:-"DEFAULT"}
PROJECT_NAME="INIT_EXPERIMENT"
IS_PROFILE=false
# 定义不同的层划分配置
SGLANG_PP_LAYER_PARTITION_LIST=("13,51" "16,48" "20,44")
SGLANG_TORCH_PROFILER_DIR_HEAD=/root/sglang_workbench/logs/profile_log_head
SGLANG_TORCH_PROFILER_DIR_WORKER1=/root/sglang_workbench/logs/profile_log_worker1
# 日志文件
LOG_DIR="/root/sglang_workbench/logs/${CONFIG_NAME}/${PROJECT_NAME}"
mkdir -p "${LOG_DIR}"
mkdir -p "${SGLANG_TORCH_PROFILER_DIR_HEAD}"
mkdir -p "${SGLANG_TORCH_PROFILER_DIR_WORKER1}"
# container之间延迟
DELAY=0ms

# 定义请求速率列表
REQUEST_RATE_LIST=(1.0)
NUM_REQUESTS=128
# === 配置tc ===
export DELAY=${DELAY}
./tc.sh

# 遍历不同的层划分配置
for SGLANG_PP_LAYER_PARTITION in "${SGLANG_PP_LAYER_PARTITION_LIST[@]}"; do
    echo "[INFO] 使用层划分配置: ${SGLANG_PP_LAYER_PARTITION}"
    
    # 为当前配置创建日志目录
    CURRENT_LOG_DIR="${LOG_DIR}/${SGLANG_PP_LAYER_PARTITION}"
    mkdir -p "${CURRENT_LOG_DIR}"
    HEAD_LOG="${CURRENT_LOG_DIR}/sg-head.log"
    WORKER1_LOG="${CURRENT_LOG_DIR}/sg-worker1.log"
    SERVER_ARGS=$(cat <<EOF
    --model-path ${MODEL_PATH} \
    --pp ${PP_SIZE} \
    --dist-init-addr ${DIST_ADDR} \
    --nnodes ${NNODES} \
    --mem-fraction-static 0.7 \
    --disable-cuda-graph
EOF
    )

    # === 启动 head 节点 ===
    echo "[INFO] 启动 sg-head 上的 SGLang 服务..."
    export SGLANG_PP_LAYER_PARTITION="${SGLANG_PP_LAYER_PARTITION}"
    export SGLANG_TORCH_PROFILER_DIR="${SGLANG_TORCH_PROFILER_DIR_HEAD}"
    python3 -m sglang.launch_server --node-rank 0 ${SERVER_ARGS} > "${HEAD_LOG}" 2>&1 &

    # === SSH 到 worker1 上启动 SGLang 服务 ===
    echo "[INFO] SSH 到 sg-worker1 上，启动 SGLang 服务..."
    # 在这里我们需要手动传入环境变量，sshpass的
    sshpass -p "123456" ssh sg-worker1 bash "
    export SGLANG_PP_LAYER_PARTITION=${SGLANG_PP_LAYER_PARTITION}
    export SGLANG_TORCH_PROFILER_DIR=${SGLANG_TORCH_PROFILER_DIR_WORKER1}
    export CUDA_MPS_PINNED_DEVICE_MEM_LIMIT=0=24GB
    export CUDA_MPS_PPE_DIRECTORY=/tmp/nvidia-mps
    export CUDA_MPS_ACTIVE_THREAD_PERCENTAGE=80
    python3 -m sglang.launch_server --node-rank 1 ${SERVER_ARGS} > "${WORKER1_LOG}" 2>&1
    "
    sleep 100
    # 遍历不同的请求速率进行基准测试
    for REQUEST_RATE in "${REQUEST_RATE_LIST[@]}"; do
        BENCHMARK_ARGS="--backend sglang \
            --num-prompt ${NUM_REQUESTS} \
            --request-rate ${REQUEST_RATE} \
        "
        if [ "$IS_PROFILE" = true ]; then
            BENCHMARK_ARGS="${BENCHMARK_ARGS} --profile"
        fi
        echo "[INFO] 运行基准测试，请求速率: ${REQUEST_RATE} req/s..."
        BENCHMARK_LOG="${CURRENT_LOG_DIR}/benchmark-${REQUEST_RATE}.log"
        python3 -m sglang.bench_serving  ${BENCHMARK_ARGS}  > "${BENCHMARK_LOG}" 2>&1
    done
done