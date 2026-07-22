// SM70 JIT smoke test for TileLang common.h (issue #105)
// Compiles a trivial kernel that includes common.h for sm_70.
// Fails on unpatched tilelang==0.1.9 (BF16 -> __hfma conversion error).
// Passes on tilelang>=0.1.10 or with the fma2 fallback patch applied.
//
// Build (from Dockerfile):
//   nvcc --cubin -O3 -lineinfo -arch=sm_70 -std=c++17 \
//     -I<tilelang>/src \
//     -I<tilelang>/3rdparty/cutlass/include \
//     -o sm70_jit_smoke.cubin sm70_jit_smoke.cu

#include <tl_templates/cuda/common.h>

extern "C" __global__ void int_float_only(const int* input, float* output) {
    if (threadIdx.x == 0) output[0] = static_cast<float>(input[0]);
}
