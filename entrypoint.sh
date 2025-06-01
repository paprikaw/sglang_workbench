#!/bin/bash
set -euo pipefail

echo "[INFO] GPU 状态："
nvidia-smi

echo "[INFO] 运行自定义 GPU benchmark"
/root/GPU_benchmark/test

git config --global user.name "BAI Xu"
git config --global user.email "baixu.must@gmail.com"

service ssh restart
tail -f /dev/null
# if [ "$COMPOSE_RUNNING_MODE" == "EXPERIMENT" ]; then
#     if [ "$ROLE" == "head" ]; then
#         ray start --block --head --port=$RAY_PORT --dashboard-host=0.0.0.0 &
#     fi

#     if [ "$ROLE" == "worker" ]; then
#         ray start --block --address=head:$RAY_PORT &
#     fi
#     /root/sglang_workbench/experiment.sh
# else
#     if [ "$ROLE" == "head" ]; then
#         python3 -m sglang.launch_server --model-path /root/.cache/huggingface/Qwen2.5-32B-Instruct-AWQ/ --pp 2 --dist-init-addr sg-head:20000 --nnodes 2 --node-rank 0
#     fi

#     if [ "$ROLE" == "worker" ]; then
#         python3 -m sglang.launch_server --model-path /root/.cache/huggingface/Qwen2.5-32B-Instruct-AWQ/ --pp 2 --dist-init-addr sg-head:20000 --nnodes 2 --node-rank 1
#     fi
# fi