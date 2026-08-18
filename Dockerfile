ARG CUDA_VERSION=12.8
ARG PYTHON_VERSION=3.12

# pytorch/pytorch devel image includes: Python 3.12, pip, CUDA toolkit,
# nvcc, g++, PyTorch cu128, cudnn9. No extra toolchain needed.
FROM pytorch/pytorch:2.10.0-cuda${CUDA_VERSION}-cudnn9-devel

LABEL maintainer="renne"
LABEL description="1Cat-vLLM SM70/V100 optimized vLLM fork with OpenAI-compatible API server"

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install 1Cat-vLLM wheel
# Build arg: VLLM_WHEEL_URL must be provided
ARG VLLM_WHEEL_URL
RUN if [ -z "$VLLM_WHEEL_URL" ]; then \
        echo "ERROR: VLLM_WHEEL_URL build arg is required"; \
        exit 1; \
    fi

RUN pip install --no-cache-dir --break-system-packages \
        --extra-index-url https://download.pytorch.org/whl/cu128 \
        ${VLLM_WHEEL_URL}

# --- Patch tilelang 0.1.9 SM70 fma2 bug (1CatAI/1Cat-vLLM issue #105) ---
# tilelang==0.1.9 has broken BF16 fallback in common.h:778 — passes
# __nv_bfloat16 to __half-only intrinsic __hfma on sm_70, causing 6 nvcc
# errors. Fixed upstream in tilelang v0.1.10, but 1Cat-vLLM pins 0.1.9.
# This patch cherry-picks the minimal fix: BF16→float→arithmetic→BF16.
# Reporter of issue #105 validated this exact change.
# COPY patches/tilelang-0.1.9-sm70-fma2-fix.patch /tmp/tilelang-fix.patch
# RUN TILELANG_SRC=$(python3 -c "import tilelang; print(tilelang.__path__[0])") && \
#     cd "${TILELANG_SRC}" && \
#     patch -p1 --dry-run < /tmp/tilelang-fix.patch && \
#     patch -p1 < /tmp/tilelang-fix.patch && \
#     rm /tmp/tilelang-fix.patch && \
#     echo "tilelang SM70 fma2 patch applied successfully"

# Verify installation + SM70 JIT smoke test
# COPY tests/sm70_jit_smoke.cu /tmp/sm70_jit_smoke.cu
RUN python3 -c "\
import torch, vllm; \
import flash_attn_v100; \
print('torch', torch.__version__); \
print('torch_cuda', torch.version.cuda); \
print('vllm', vllm.__version__); \
print('flash_attn_v100', flash_attn_v100.__version__); \
print('nvcc', __import__('subprocess').check_output(['nvcc', '--version']).decode().strip().split()[-1]); \
print('GPUs available:', torch.cuda.device_count()); \
[print(f'  GPU {i}: {torch.cuda.get_device_name(i)}, cc {torch.cuda.get_device_capability(i)}') for i in range(torch.cuda.device_count())]"

# SM70 JIT smoke test: compile trivial kernel including common.h for sm_70.
# Fails on unpatched tilelang 0.1.9, passes after fma2 fix.
# RUN TILELANG_SRC=$(python3 -c "import tilelang; print(tilelang.__path__[0])") && \
#     nvcc --cubin -O3 -lineinfo -arch=sm_70 -std=c++17 \
#         -I"${TILELANG_SRC}/src" \
#         -I"${TILELANG_SRC}/3rdparty/cutlass/include" \
#         -o /tmp/sm70_jit_smoke.cubin /tmp/sm70_jit_smoke.cu && \
#     echo "SM70 JIT smoke test PASSED" && \
#     rm /tmp/sm70_jit_smoke.cu /tmp/sm70_jit_smoke.cubin

# Default entrypoint
ENTRYPOINT ["python3", "-m", "vllm.entrypoints.openai.api_server"]
CMD ["--host", "0.0.0.0", "--port", "8000"]
