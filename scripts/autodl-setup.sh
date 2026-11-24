#!/bin/bash
# AutoDL 训练环境一键安装（2026-11-23 停机复盘版）——在实例上以 root 运行。
#
# 2026-11-23 的教训（T2 之后第二次环境安装翻车）：
#   1. pytorch.org 直连在国内卡死（24MB 十分钟不动）→ torch 一律走阿里云 PyPI 镜像
#      （torch 主包 + nvidia-* CUDA 依赖同源，实测国内满速）。
#   2. 远端 pip 挂在本地 ssh 会话下，本地工具调用一结束进程就被杀 → 必须
#      在远端 nohup 自持，日志写文件。
#   3. 装完第一步要做「保存镜像」（控制台：更多 → 保存镜像，命名 sinan-train），
#      以后手动开实例必选该镜像——开机即训，整个安装环节归零。
#
# 用法（本地一条命令，全程自持，断开 ssh 也继续）：
#   ssh -p <port> root@<host> "nohup bash /root/autodl-tmp/autodl-setup.sh > /root/autodl-tmp/setup.log 2>&1 &"
# 进度：ssh ... "tail -3 /root/autodl-tmp/setup.log"
set -e
MIRROR="https://mirrors.aliyun.com/pypi/simple/"

source /etc/network_turbo 2>/dev/null || true

if [ ! -d /root/autodl-tmp/miniconda3 ]; then
  wget -q https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-py311_24.7.1-0-Linux-x86_64.sh -O /tmp/mc.sh
  bash /tmp/mc.sh -b -p /root/autodl-tmp/miniconda3
fi
P=/root/autodl-tmp/miniconda3/bin
$P/conda create -y -n sinan python=3.11 2>/dev/null || true
PP=/root/autodl-tmp/miniconda3/envs/sinan/bin/pip

$PP install torch==2.4.0 --index-url $MIRROR
$PP install -q transformers==4.51.3 datasets accelerate peft trl setproctitle modelscope -i $MIRROR
$PP install -q llamafactory -i $MIRROR   # SFT 框架（自带 torch 依赖，版本不冲突则跳过重装）
$PP install -q llama-cpp-python -i $MIRROR || true   # GGUF 合并后本地冒烟（可选）

/root/autodl-tmp/miniconda3/envs/sinan/bin/python - <<'PY'
from modelscope import snapshot_download
print("MODEL_PATH:", snapshot_download("Qwen/Qwen3-0.6B"))
PY

echo "SETUP DONE — 下一步：控制台「保存镜像」命名 sinan-train，之后开实例必选它"
