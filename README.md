# sglang_workbench

This repository provides utilities to manage distributed `sglang` servers using
`docker compose`. Each container runs a small Python daemon that exposes an API
for launching `sglang` with arbitrary commands. A helper CLI script can call
all daemons to start the cluster at once.

## Usage

1. Build the Docker image and start the containers:

   ```bash
   docker compose up -d
   ```

   The compose file launches two containers (`sg-head` and `sg-worker1`) each
   running `daemon.py`. The daemon listens on ports `18000` and `18001`
   respectively.

2. Start `sglang` on all containers with `start_daemons.py`:

   ```bash
   python3 start_daemons.py \
       --hosts sg-head:18000 sg-worker1:18001 \
       --command "python3 -m sglang.launch_server --node-rank RANK"
   ```

   Replace the command with the actual `sglang` launch command you wish to run.
