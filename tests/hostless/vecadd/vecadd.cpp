#include <stdio.h>
#include <vx_intrinsics.h>
#include <vx_spawn.h>
#include <vx_print.h>
#include "utils.h"
#include <cmath>
////////////////////////////////////////////////////////////////////////////////
// Int Vector Add Kernel

typedef struct {
    int* src0;
    int* src1;
    int* dst;
    int N;
} vecadd_int_args_t;

void vecadd_int_kernel(vecadd_int_args_t* __UNIFORM__ args) {
	auto src0_ptr = reinterpret_cast<int*>(args->src0);
	auto src1_ptr = reinterpret_cast<int*>(args->src1);
	auto dst_ptr = reinterpret_cast<int*>(args->dst);

    // Each thread computes one element
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < args->N) {
        dst_ptr[idx] = src0_ptr[idx] + src1_ptr[idx];
    }
}

int check_result_int(int* dst, int* dst_ref, int N) {
    int mismatches = 0;
    for (int i = 0; i < N; i++) {
        if (dst[i] != dst_ref[i]) {
            vx_printf("ERROR: Mismatch at idx=%d: dst=%d, dst_ref=%d\n", i, dst[i], dst_ref[i]);
            mismatches++;
        }
    }
    return mismatches;
}

////////////////////////////////////////////////////////////////////////////////
// Float Vector Add Kernel

#define EPSILON 1e-5f

typedef struct {
    float* src0;
    float* src1;
    float* dst;
    int N;
} vecadd_float_args_t;

void vecadd_float_kernel(vecadd_float_args_t* __UNIFORM__ args) {
    auto src0_ptr = reinterpret_cast<float*>(args->src0);
    auto src1_ptr = reinterpret_cast<float*>(args->src1);
    auto dst_ptr = reinterpret_cast<float*>(args->dst);

    // Each thread computes one element
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < args->N) {
        dst_ptr[idx] = src0_ptr[idx] + src1_ptr[idx];
    }
}

int check_result_float(float* dst, float* dst_ref, int N) {
    int mismatches = 0;
    for (int i = 0; i < N; i++) {
        float diff = std::abs(dst[i] - dst_ref[i]);
        if (diff > EPSILON) {
            vx_printf("ERROR: Mismatch at idx=%d: dst=%f, dst_ref=%f\n", i, dst[i], dst_ref[i]);
            mismatches++;
        }
    }
    return mismatches;
}

#define TILE_SIZE 8

void vecadd_float_tiled_kernel(vecadd_float_args_t* __UNIFORM__ args) {
    auto src0_ptr = reinterpret_cast<float*>(args->src0);
    auto src1_ptr = reinterpret_cast<float*>(args->src1);
    auto dst_ptr = reinterpret_cast<float*>(args->dst);

    // Allocate local memory for tiles
    auto local_ptr = __local_mem(2 * TILE_SIZE * sizeof(float));
    auto tile_src0 = (float*)local_ptr;
    auto tile_src1 = (float*)local_ptr + TILE_SIZE;

    int tid = threadIdx.x;
    int tileStart = (blockIdx.x * TILE_SIZE);
    int idx = tileStart + tid;

    // Load tiles into local memory
    if (idx < args->N) {
        tile_src0[tid] = src0_ptr[idx];
        tile_src1[tid] = src1_ptr[idx];
    } else {
        tile_src0[tid] = 0;
        tile_src1[tid] = 0;
    }

    // Synchronize to ensure all data is loaded
    __syncthreads();

    // Perform vector addition using local memory
    if (idx < args->N) {
        dst_ptr[idx] = tile_src0[tid] + tile_src1[tid];
    }
}

////////////////////////////////////////////////////////////////////////////////
// Host Code

// Global Variables that all cores can access
int *src0_i;
int *src1_i;
int *dst_i;
int *dst_ref_i;
vecadd_int_args_t args;

float *src0_f;
float *src1_f;
float *dst_f;
float *dst_ref_f;
vecadd_float_args_t fargs;

bool vecadd_int(int N) {
    int core_id = vx_core_id();
    if(core_id == 0) {
        vx_printf("===== Test 1: Vecadd test (int) =====\n");
        vx_printf(">> Allocating buffers\n");
        src0_i = (int*)vx_malloc(N * sizeof(int));
        src1_i = (int*)vx_malloc(N * sizeof(int));
        dst_i = (int*)vx_malloc(N * sizeof(int));
        dst_ref_i = (int*)vx_malloc(N * sizeof(int));

        vx_printf(">> Initializing buffers\n");
        for (int i = 0; i < N; i++) {
            src0_i[i] = vx_rand() % 100;
            src1_i[i] = vx_rand() % 100;
            dst_ref_i[i] = src0_i[i] + src1_i[i];
        }
        vx_printf(">> Launching kernel\n");
        // Set kernel arguments
        args.src0 = src0_i;
        args.src1 = src1_i;
        args.dst = dst_i;
        args.N = N;
    }

    vx_global_barrier();

    // Kernel Launch
    uint32_t block_dim = 16;
    uint32_t grid_dim = (N + block_dim - 1) / block_dim;
    vx_spawn_threads(1, &grid_dim, &block_dim, (vx_kernel_func_cb)vecadd_int_kernel, &args);
    vx_global_barrier();

    if(core_id == 0) {
        vx_printf(">> Validating results\n");
        int mismatches = check_result_int(dst_i, dst_ref_i, N);
        if (mismatches == 0) {
            vx_printf(">> Vecadd (int): PASSED\n");
        } else {
            vx_printf(">> Mismatches found: %d\n", mismatches);
            vx_printf(">> Vecadd (int): FAILED\n");
        }

        // Free buffers
        vx_free(src0_i);
        vx_free(src1_i);
        vx_free(dst_i);
        vx_free(dst_ref_i);
    }
    return 0;
}

int vecadd_float(int N) {
    int core_id = vx_core_id();
    if (core_id == 0) {
        vx_printf("===== Test2: Vecadd (float) =====\n");
        vx_printf(">> Allocating buffers\n");
        src0_f = (float*)vx_malloc(N * sizeof(float));
        src1_f = (float*)vx_malloc(N * sizeof(float));
        dst_f = (float*)vx_malloc(N * sizeof(float));
        dst_ref_f = (float*)vx_malloc(N * sizeof(float));
        vx_printf(">> Initializing buffers\n");
        for (int i = 0; i < N; i++) {
            src0_f[i] = static_cast<float>(vx_rand() % 100) / 10.0f;
            src1_f[i] = static_cast<float>(vx_rand() % 100) / 10.0f;
            dst_ref_f[i] = src0_f[i] + src1_f[i];
        }
        vx_printf(">> Launching vector add kernel\n");
        // Set kernel arguments
        fargs.src0 = src0_f;
        fargs.src1 = src1_f;
        fargs.dst = dst_f;
        fargs.N = N;
    }
    vx_global_barrier();

    // Kernel Launch
    uint32_t block_dim = 16;
    uint32_t grid_dim = (N + block_dim - 1) / block_dim;
    vx_spawn_threads(1, &grid_dim, &block_dim, (vx_kernel_func_cb)vecadd_float_kernel, &fargs);
    if (core_id == 0) {
        vx_printf(">> Validating results\n");
        int mismatches = check_result_float(dst_f, dst_ref_f, N);
        if (mismatches == 0) {
            vx_printf(">> Vecadd (float): PASSED\n");
        } else {
            vx_printf(">> Mismatches found: %d\n", mismatches);
            vx_printf(">> Vecadd (float): FAILED\n");
        }

        // Free buffers
        vx_free(src0_f);
        vx_free(src1_f);
        vx_free(dst_f);
        vx_free(dst_ref_f);
    }
    return 0;
}

int vecadd_float_tiled(int N) {
    int core_id = vx_core_id();
    if (core_id == 0) {
        vx_printf("===== Test3: Vecadd (float tiled) =====\n");
        vx_printf(">> Allocating buffers\n");
        src0_f = (float*)vx_malloc(N * sizeof(float));
        src1_f = (float*)vx_malloc(N * sizeof(float));
        dst_f = (float*)vx_malloc(N * sizeof(float));
        dst_ref_f = (float*)vx_malloc(N * sizeof(float));
        vx_printf(">> Initializing buffers\n");
        for (int i = 0; i < N; i++) {
            src0_f[i] = static_cast<float>(vx_rand() % 100) / 10.0f;
            src1_f[i] = static_cast<float>(vx_rand() % 100) / 10.0f;
            dst_ref_f[i] = src0_f[i] + src1_f[i];
        }
        vx_printf(">> Launching vector add tiled kernel\n");
        // Set kernel arguments
        fargs.src0 = src0_f;
        fargs.src1 = src1_f;
        fargs.dst = dst_f;
        fargs.N = N;
    }
    vx_global_barrier();

    // Kernel Launch
    uint32_t block_dim = TILE_SIZE;
    uint32_t grid_dim = (N + block_dim - 1) / block_dim;
    vx_spawn_threads(1, &grid_dim, &block_dim, (vx_kernel_func_cb)vecadd_float_tiled_kernel, &fargs);
    if (core_id == 0) {
        vx_printf(">> Validating results\n");
        int mismatches = check_result_float(dst_f, dst_ref_f, N);
        if (mismatches == 0) {
            vx_printf(">> Vecadd (float tiled): PASSED\n");
        } else {
            vx_printf(">> Mismatches found: %d\n", mismatches);
            vx_printf(">> Vecadd (float tiled): FAILED\n");
        }

        // Free buffers
        vx_free(src0_f);
        vx_free(src1_f);
        vx_free(dst_f);
        vx_free(dst_ref_f);
    }
    return 0;
}

int main() {
    const int N = 128;      // Test size
    vecadd_int(N);
    vecadd_float(2*N);
    vecadd_float_tiled(4*N);
    return 0;
}