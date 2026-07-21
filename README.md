# 1Cat-vLLM V100 Docker Image

Auto-built Docker image of [1Cat-vLLM](https://github.com/1CatAI/1Cat-vLLM) for
NVIDIA Tesla V100 (Volta, SM70) with CUDA 12.8.1.

Upstream vLLM does **not** support V100 (requires SM75+). 1Cat-vLLM patches
vLLM with SM70 Marlin kernels, FlashAttention-V100, and TurboMind kernels
to serve Qwen3.x-class AWQ/FP8 models on Volta GPUs.

## What This Repo Builds

A Docker image that installs the latest 1Cat-vLLM Python wheel on top of
`nvidia/cuda:12.8.1-runtime-ubuntu24.04`. The wheel bundles all SM70 CUDA
extensions (flash_attn_v100, paged_kv_utils, Marlin SM70) -- no source
compilation needed during Docker build.

The resulting image is published to:
- `ghcr.io/renne/1cat-vllm-v100:<release-tag>` (e.g. `v1.2.2`)
- `ghcr.io/renne/1cat-vllm-v100:latest`

## Build Triggers

| Trigger | Schedule | Action |
|---------|----------|--------|
| Daily cron | 03:00 UTC every day | Check 1CatAI/1Cat-vLLM latest release. If new tag since last build, build + push. If unchanged, skip (no minutes wasted). |
| Manual | On demand | Workflow dispatch with optional version override. Always builds + pushes. |

A new 1Cat-vLLM release published today will be available as a Docker image
by 03:00 UTC the following day.

## Image Details

| Property | Value |
|----------|-------|
| Base image | `nvidia/cuda:12.8.1-runtime-ubuntu24.04` |
| Python | 3.12 |
| CUDA | 12.8.1 (last with full SM70 support; CUDA 13.0+ dropped V100) |
| 1Cat-vLLM | Latest release wheel (cp312 linux_x86_64) |
| Entrypoint | `python -m vllm.entrypoints.openai.api_server` |
| Image size | ~3.5 GB |

## Usage

```bash
docker run --gpus all -p 8000:8000 \
  -v /path/to/models:/models:ro \
  ghcr.io/renne/1cat-vllm-v100:latest \
  --model /models/Qwen3.6-35B-A3B-AWQ \
  --attention-backend FLASH_ATTN_V100 \
  --tensor-parallel-size 2 \
  --gpu-memory-utilization 0.88 \
  --max-model-len 262144 \
  --max-num-seqs 4 \
  --kv-cache-dtype fp8_e5m2 \
  --enable-prefix-caching \
  --enable-chunked-prefill \
  --host 0.0.0.0 --port 8000
```

See the [1Cat-vLLM skill](https://github.com/1CatAI/1Cat-vLLM) for full
launch parameters, model recommendations, and V100-specific notes.

## Important Notes

- **V100 only**: This image is built for SM70 (Volta). It will not work on
  newer GPUs (use upstream vLLM instead) or older GPUs (P100 = SM60).
- **Qwen3.x validated**: 1Cat-vLLM validates Qwen3.x-class AWQ models only.
  Other architectures (Gemma, GLM, Llama) may work but are untested on SM70.
- **No CUDA graphs by default**: V100 supports CUDA graphs, but 1Cat-vLLM
  recommends `--enforce-eager` for stability. Enable at your own risk.
- **TP must be power of 2**: Use `--tensor-parallel-size 1, 2, or 4`.
  Odd GPU counts (3) are not supported by vLLM tensor parallelism.
- **First request is slow**: V100 warmup is very slow. Exclude from
  throughput benchmarks. Use a warmup request before measuring.

## License

Apache License 2.0 -- same as upstream [1Cat-vLLM](https://github.com/1CatAI/1Cat-vLLM)
and [vLLM](https://github.com/vllm-project/vllm). See [LICENSE](LICENSE).

This project is a Docker packaging of 1Cat-vLLM. All inference code,
kernels, and modifications belong to the 1Cat-vLLM contributors.
This repo contains only a Dockerfile and GitHub Actions workflow -- no
source code from upstream is included or modified.
