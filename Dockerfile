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

RUN pip install --no-cache-dir \
        --extra-index-url https://download.pytorch.org/whl/cu128 \
        ${VLLM_WHEEL_URL}

# Verify installation
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

# Default entrypoint
ENTRYPOINT ["python3", "-m", "vllm.entrypoints.openai.api_server"]
CMD ["--host", "0.0.0.0", "--port", "8000"]
