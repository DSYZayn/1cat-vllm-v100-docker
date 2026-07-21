ARG CUDA_VERSION=12.8.1
ARG UBUNTU_VERSION=24.04
ARG PYTHON_VERSION=3.12
ARG CUDA_MAJOR_MINOR=12-8

FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION} AS base

ARG PYTHON_VERSION
ARG CUDA_MAJOR_MINOR

# Install system dependencies
# gcc+g++: Triton JIT + nvcc host compiler
# cuda-nvcc: CUDA compiler for flash_qla/tilelang/tokenspeed JIT extension builds
RUN apt-get update && apt-get install -y --no-install-recommends \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-venv \
        python${PYTHON_VERSION}-dev \
        curl \
        ca-certificates \
        libgomp1 \
        gcc \
        g++ \
        cuda-nvcc-${CUDA_MAJOR_MINOR} \
    && rm -rf /var/lib/apt/lists/*

# Set Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 1

# Remove PEP 668 externally-managed marker (we're in a container, not a host)
RUN rm -f /usr/lib/python3*/EXTERNALLY-MANAGED

# Bootstrap pip
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3

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
print('GPUs available:', torch.cuda.device_count()); \
[print(f'  GPU {i}: {torch.cuda.get_device_name(i)}, cc {torch.cuda.get_device_capability(i)}') for i in range(torch.cuda.device_count())]"

# Default entrypoint
ENTRYPOINT ["python3", "-m", "vllm.entrypoints.openai.api_server"]
CMD ["--host", "0.0.0.0", "--port", "8000"]
