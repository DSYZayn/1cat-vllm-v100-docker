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

The resulting stable image is published to:
- `ghcr.io/dsyzayn/1cat-vllm-v100-docker:<release-tag>` (e.g. `v1.3.0`)
- `ghcr.io/dsyzayn/1cat-vllm-v100-docker:latest`

Rolling wheels from the development repository are published separately, for
example:
- `ghcr.io/dsyzayn/1cat-vllm-v100-docker:v1.3.0-20260825`

Each rolling build also creates an immutable GitHub prerelease named
`rolling-v1.3.0-20260825` in this repository. The rolling image tag contains
only the stable version and wheel build date.
Rolling tags never update `latest` or any stable release tag. `latest` is only
updated by a build using the newest stable wheel from `1CatAI/1Cat-vLLM`.

## Build Triggers

| Trigger | Schedule | Action |
|---------|----------|--------|
| `Build Stable Docker Image` schedule | 03:00 UTC+8 every day | Check the newest stable wheel from `1CatAI/1Cat-vLLM` and build the stable image when needed. |
| `Build Rolling Docker Image` hook | After `DSYZayn/1Cat-vLLM` publishes a rolling wheel | Build the matching rolling image and create its daily release. |
| Manual | On demand | Run either workflow independently. Stable accepts a release `version`; rolling accepts a rolling `release_tag`. |

A new stable release published before the daily run will be available after
that run. A rolling image is triggered by the source repository's publish hook,
and each successful build is retained as a daily release. Rolling images are
never aliased to `latest`.

The source repository must define a `DOCKER_REPOSITORY_DISPATCH_TOKEN` secret
with permission to dispatch workflows in this repository. Without that secret,
the wheel publish still succeeds but the hook emits a warning and no rolling
image is built.

## Image Details

| Property | Value |
|----------|-------|
| Base image | `nvidia/cuda:12.8.1-runtime-ubuntu24.04` |
| Python | 3.12 |
| CUDA | 12.8.1 (last with full SM70 support; CUDA 13.0+ dropped V100) |
| 1Cat-vLLM | Stable or rolling cp312 Linux x86_64 wheel |
| Entrypoint | `/usr/local/bin/1cat-vllm-entrypoint` with a shared pre-start hook layer |
| vLLM CLI | `/usr/local/1cat-vllm/bin/vllm` wrapper -> original `vllm-real` |
| Image size | ~3.5 GB |

## Usage

### Startup hook layer

Every standard launch path passes through the image's startup hook layer
before the inference server process starts:

```text
Docker / GPUStack command
          |
          v
VLLM_PRESTART_HOOK (optional, fail-closed)
          |
          v
Original vLLM server entrypoint
```

The layer is part of the image contract, not a GPUStack-only feature. The
default Docker entrypoint handles the OpenAI API server invocation, while the
PATH-fronted `vllm` wrapper handles runtimes that replace the image entrypoint
with `vllm serve`. With no `VLLM_PRESTART_HOOK`, both paths forward directly to
the original vLLM implementation.

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

### Pre-start hook

The image has a generic `VLLM_PRESTART_HOOK` entrypoint hook. When set, its
value is executed once before the vLLM server starts. A non-zero hook exit
status stops container startup, which prevents serving with a partially
applied patch.

When the hook is unset, the wrapper is transparent: it forwards to the
original vLLM console script and preserves the normal Docker invocation.

For example, to apply the temporary Prometheus compatibility workaround:

```bash
docker run --gpus all -p 8000:8000 \
  -e 'VLLM_PRESTART_HOOK=python3 -m pip install --break-system-packages --no-deps --upgrade prometheus-fastapi-instrumentator==8.0.1' \
  -v /path/to/models:/models:ro \
  ghcr.io/dsyzayn/1cat-vllm-v100-docker:latest \
  --model /models/Qwen3.6-35B-A3B-AWQ
```

For a source patch, mount a script and point the hook at it:

```bash
-e VLLM_PRESTART_HOOK=/opt/patches/prestart.sh \
-v /path/to/patches:/opt/patches:ro
```

The mounted hook is run with `/bin/sh`. For a Python patch, make the hook
script invoke Python explicitly, for example:

```sh
#!/bin/sh
exec python3 /opt/patches/prestart.py
```

The same hook contract works for standard `docker run` and orchestration
runtimes. In GPUStack, keep the normal **Override Image Entrypoint** value
`vllm serve` and keep **Execution Command** as vLLM arguments only. The image
puts a `vllm` wrapper first in `PATH`, so this setting still runs
`VLLM_PRESTART_HOOK` immediately before `vllm serve`. Add the hook under
**Environment Variables**. If another runtime uses an absolute vLLM
executable path, set its entrypoint to `/usr/local/bin/1cat-vllm-entrypoint`
or use the image's default entrypoint.

To test a rolling build, replace the image with a date tag such as
`ghcr.io/dsyzayn/1cat-vllm-v100-docker:v1.3.0-20260825`. The corresponding
GitHub release is `rolling-v1.3.0-20260825`.

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
