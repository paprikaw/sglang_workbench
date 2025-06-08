# syntax=docker.io/docker/dockerfile:1.7-labs
FROM nvcr.io/nvidia/cuda:12.2.2-devel-ubuntu22.04

ARG PYTHON_VERSION=3.12
WORKDIR /root
# Firstly download external dataset
# Install some package
RUN echo "start install packages"
RUN <<EOF
#!/bin/bash
# 添加 iputils-ping 和 iperf3
set -euo pipefail

apt-get update -y
apt-get upgrade -y

APT_PKGS=(
    wget
    vim
    iproute2
    iputils-ping
    iperf3
    openssh-server
    sshpass
    nload
)
apt-get install -y "${APT_PKGS[@]}"
EOF


RUN <<EOF
#!/bin/bash
set -euo pipefail
# 修改 SSH 配置允许 root 登录
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# 为 root 设置默认密码（可按需修改）
echo "root:123456" | chpasswd
service ssh restart
EOF


# RUN wget --progress=bar:force https://huggingface.co/datasets/anon8231489123/ShareGPT_Vicuna_unfiltered/resolve/main/ShareGPT_V3_unfiltered_cleaned_split.json



# Install Python and other dependencies
# Reference: https://github.com/vllm-project/vllm/blob/main/docker/Dockerfile
RUN export DEBIAN_FRONTEND=noninteractive \
    && echo 'tzdata tzdata/Areas select America' | debconf-set-selections \
    && echo 'tzdata tzdata/Zones/America select Los_Angeles' | debconf-set-selections \
    && apt-get update -y \
    && apt-get install -y ccache software-properties-common git curl sudo \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update -y \
    && apt-get install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-venv \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && update-alternatives --set python3 /usr/bin/python${PYTHON_VERSION} \
    && ln -sf /usr/bin/python${PYTHON_VERSION}-config /usr/bin/python3-config \
    && curl -sS https://bootstrap.pypa.io/get-pip.py | python${PYTHON_VERSION} \
    && python3 --version && python3 -m pip --version

# Install uv for faster pip installs
RUN --mount=type=cache,id=uv-cache-v1,target=/root/.cache/uv \
    python3 -m pip install uv

# This timeout (in seconds) is necessary when installing some dependencies via uv since it's likely to time out
# Reference: https://github.com/astral-sh/uv/pull/1694
ENV UV_HTTP_TIMEOUT=500
# Workaround for uv hardlink issue
# Reference: https://github.com/astral-sh/uv/issues/7285
ENV UV_LINK_MODE=copy


# COPY --exclude=.venv --exclude=logs . /root/sglang_workbench
# RUN <<EOF
# #!/bin/bash
# set -euo pipefail

# if [ "${VLLM_VERSION}" != "$(git -C /root/vllm tag --points-at HEAD)" ]; then 
#     echo "VLLM version mismatch, expected ${VLLM_VERSION}, but got $(git -C /root/vllm tag --points-at HEAD)" 
#     exit 1 
# fi
# EOF

ENV CCACHE_DIR=/root/.cache/ccache \
    CCACHE_LOGFILE=/root/ccache_logs/ccache.log \
    CCACHE_STATS_LOG=/root/ccache_logs/ccache.log \
    CCACHE_BASEDIR=/root/sglang_workbench \
    CCACHE_DEBUG=true \
    CCACHE_NOHASHDIR=true

RUN --mount=type=cache,id=uv-cache-v1,target=/root/.cache/uv \
    cd /root/sglang_workbench/sglang && uv pip install --system --upgrade pip

RUN --mount=type=cache,id=uv-cache-v1,target=/root/.cache/uv \
    cd /root/sglang_workbench/sglang && uv pip install --system -e "python[all]" 

RUN --mount=type=cache,id=uv-cache-v1,target=/root/.cache/uv \
    cd /root/sglang_workbench/sglang && uv pip install --system vllm==0.8.4 


ENTRYPOINT ["/bin/bash"]

# Install Nsight
# RUN <<EOF
# #!/bin/bash
# set -euo pipefail

# apt update \
#     && apt install -y --no-install-recommends gnupg
# echo "deb http://developer.download.nvidia.com/devtools/repos/ubuntu$(. /etc/lsb-release; echo "$DISTRIB_RELEASE" | tr -d .)/$(dpkg --print-architecture) /" | tee /etc/apt/sources.list.d/nvidia-devtools.list
# apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub
# apt update && apt install -y nsight-systems-cli
# EOF