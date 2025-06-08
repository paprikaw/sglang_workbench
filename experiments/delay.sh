#!/bin/bash
set -euo pipefail
# 加上一个trap，如果脚本被中断，则打印当前的进程信息
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
trap cleanup INT ERR


###############################
# ===== 参数配置区域 ========
###############################
# MPS
if [ -z "${CUDA_MPS_ACTIVE_THREAD_PERCENTAGE+x}" ]; then
    echo "错误: CUDA_MPS_ACTIVE_THREAD_PERCENTAGE 环境变量未设置"
    exit 1
fi

export NCCL_DEBUG=INFO
export NCCL_CUMEM_HOST_ENABLE=0
export VLLM_NCCL_SO_PATH="/usr/lib/x86_64-linux-gnu/libnccl.so.2.21.5"
export LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libnccl.so.2.21.5"
# export VLLM_USE_RAY_COMPILED_DAG_CHANNEL_TYPE="nccl"


# 日志与目录
CONFIG_NAME=${CONFIG_NAME:-"DEBUG"} # 容器的GPU和Memory的配置
PROJECT_NAME=${PROJECT_NAME:-"deep_dive"} # 当前expeirment的purpose
LOG_DIR=${LOG_DIR:-/root/sglang_workbench/logs/$PROJECT_NAME/$CONFIG_NAME}
mkdir -p "$LOG_DIR"

SGLANG_PP_LAYER_PARTITION="13,51"
SGLANG_TORCH_PROFILER_DIR_HEAD=/root/sglang_workbench/logs/profile_log_head
SGLANG_TORCH_PROFILER_DIR_WORKER1=/root/sglang_workbench/logs/profile_log_worker1
# 模型与数据
MODEL_PATH=${MODEL_PATH:-/root/.cache/huggingface/Qwen2.5-32B-Instruct-AWQ/}
MODEL_NAME=${MODEL_NAME:-Qwen2.5-32B}
DATASET_PATH=${DATASET_PATH:-/root/ShareGPT_V3_unfiltered_cleaned_split.json}

# vLLM 配置
PIPELINE_PARALLEL_SIZE=${PIPELINE_PARALLEL_SIZE:-2}
GPU_MEMORY_UTILIZATION=${GPU_MEMORY_UTILIZATION:-0.9}
MAX_MODEL_LEN=${MAX_MODEL_LEN:-5000}

# 延迟配置
DELAY_LIST=(100ms)

# Benchmark 配置
NUM_REQUESTS=${NUM_REQUESTS:-1}
# REQUEST_RATE_LIST=(0.5 1.0 3.0 5.0)
REQUEST_RATE_LIST=(1.0)
VLLM_PP_LAYER_PARTITION_LIST=("16,48")
PROFILE=${PROFILE:-false}
###############################
# ===== 启动服务部分 ========
###############################

# Print 重要的实验参数
echo "[INFO] 重要的实验参数："
echo "--------------------------------"
echo "DATASET_PATH: $DATASET_PATH"
echo "PIPELINE_PARALLEL_SIZE: $PIPELINE_PARALLEL_SIZE"
echo "GPU_MEMORY_UTILIZATION: $GPU_MEMORY_UTILIZATION"
echo "CUDA_MPS_ACTIVE_THREAD_PERCENTAGE: $CUDA_MPS_ACTIVE_THREAD_PERCENTAGE"
echo "NUM_REQUESTS: $NUM_REQUESTS"
echo "REQUEST_RATE_LIST: ${REQUEST_RATE_LIST[@]}"
echo "--------------------------------"


for DELAY in "${DELAY_LIST[@]}"; do
    export DELAY=$DELAY
    echo "[INFO] 设置网络延迟: $DELAY"
    bash ../tc.sh
    for VLLM_PP_LAYER_PARTITION in "${VLLM_PP_LAYER_PARTITION_LIST[@]}"; do
      export VLLM_PP_LAYER_PARTITION=$VLLM_PP_LAYER_PARTITION
      echo "[INFO] 正式运行 vLLM, 模型并行层数: $VLLM_PP_LAYER_PARTITION"
      CUR_LOG_DIR="$LOG_DIR/${DELAY}-${VLLM_PP_LAYER_PARTITION}"
      mkdir -p "$CUR_LOG_DIR"
      SERVER_LOG_FILE="$CUR_LOG_DIR/vllm-server.log"
      # 构造 vLLM serve 参数
      SERVE_ARGS="--pipeline-parallel-size $PIPELINE_PARALLEL_SIZE \
                  --gpu-memory-utilization $GPU_MEMORY_UTILIZATION \
                  --max-model-len $MAX_MODEL_LEN \
                  --served-model-name $MODEL_NAME \
                  --distributed-executor-backend ray \
                  --disable-log-requests \
                  --no-enable-prefix-caching"
      
      [ "$CHUNKED_PREFILL" = "true" ] && SERVE_ARGS="$SERVE_ARGS --enable-chunked-prefill"
      [ "$ENABLE_CUDA_GRAPH" = "false" ] && SERVE_ARGS="$SERVE_ARGS --enforce-eager"
      [ "$ENABLE_NSIGHT" = "true" ] && SERVE_ARGS="$SERVE_ARGS --ray-workers-use-nsight"

      set +e
        vllm serve "$MODEL_PATH" $SERVE_ARGS  > "${SERVER_LOG_FILE}" 2>&1 &
      set -e
      tail -f /dev/null

      for REQUEST_RATE in "${REQUEST_RATE_LIST[@]}"; do
        BENCHMARK_ARGS="--num-prompts $NUM_REQUESTS \
              --request-rate $REQUEST_RATE \
              --backend openai-chat \
              --model "$MODEL_PATH" \
              --endpoint /v1/chat/completions \
              --dataset-name sharegpt \
              --dataset-path "$DATASET_PATH" \
              --base-url http://head:$VLLM_PORT \
              --served-model-name "$MODEL_NAME" \
              --goodput tpot:300 ttft:5000 \
              --temperature 0 \
              --seed 42"
        [ "$PROFILE" = "true" ] && BENCHMARK_ARGS="$BENCHMARK_ARGS --profile"
        echo "[INFO] 开始 Benchmark 测试, 请求速率: $REQUEST_RATE"
        BENCHMARK_LOG_FILE="$CUR_LOG_DIR/benchmark-${REQUEST_RATE}.log"
        python3 /root/vllm_workbench/vllm/benchmarks/benchmark_serving.py \
        $BENCHMARK_ARGS > "$BENCHMARK_LOG_FILE" 2>&1
      done
      ps aux | grep vllm | grep -v grep | awk '{print $2}' | xargs -r kill -9
      ray stop &
      sleep 30
    done
done
echo "[INFO] Benchmark 完成 ✅"
