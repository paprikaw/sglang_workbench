#!/bin/sh
# 在容器 head 内部执行，向 worker1 (10.89.1.3) 限制延迟为 100ms

DEV=eth0
TARGET_IP=$(getent hosts sg-worker1 | awk '{print $1; exit}')
DELAY="50ms"

echo "[INFO] 清除旧的 tc 规则（如果存在）"
tc qdisc del dev $DEV root 2>/dev/null

echo "[INFO] 添加 prio root qdisc"
tc qdisc add dev $DEV root handle 1: prio

echo "[INFO] 为发往 $TARGET_IP 的流量注入 $DELAY 延迟"
tc qdisc add dev $DEV parent 1:1 handle 10: netem delay $DELAY limit 100000
tc filter add dev $DEV protocol ip parent 1: prio 1 u32 match ip dst $TARGET_IP/32 flowid 1:1

echo "[DONE] 当前 tc 配置："
tc qdisc show dev $DEV
tc filter show dev $DEV
