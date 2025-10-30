#include <vx_intrinsics.h>
#include <vx_spawn.h>
#include <vx_print.h>
#include "utils.h"

#define NUM_TESTS 5

struct gemm_args_t {
    float* A;
    float* B;
    float* C;
    int M;
    int N;
    int K;
};

void gemm_ref(gemm_args_t* args) {
    for (int m = 0; m < args->M; m++) {
        for (int n = 0; n < args->N; n++) {
            args->C[m * args->N + n] = 0.0f;
            for (int k = 0; k < args->K; k++) {
                args->C[m * args->N + n] += args->A[m * args->K + k] * args->B[k * args->N + n];
            }
        }
    }
}

void gemm_kernel_simple(gemm_args_t* __UNIFORM__ args) {
    auto A = reinterpret_cast<float*>(args->A);
    auto B = reinterpret_cast<float*>(args->B);
    auto C = reinterpret_cast<float*>(args->C);

    int M = args->M;
    int N = args->N;
    int K = args->K;

    // Simple 2D indexing - each thread computes one output element
    int row = blockIdx.x * blockDim.x + threadIdx.x;
    int col = blockIdx.y * blockDim.y + threadIdx.y;

    if (row < M && col < N) {
        float sum = 0.0f;
        for (int k = 0; k < K; k++) {
            sum += A[row * K + k] * B[k * N + col];
        }
        C[row * N + col] = sum;
    }
}

void gemm_kernel_tiled(gemm_args_t* __UNIFORM__ args) {
    auto A = reinterpret_cast<float*>(args->A);
    auto B = reinterpret_cast<float*>(args->B);
    auto C = reinterpret_cast<float*>(args->C);

    int M = args->M;
    int N = args->N;
    int K = args->K;
    
    const int TILE_SIZE = 4;  // Must match block dimensions
    
    // Allocate local memory for tiles
    auto local_ptr = __local_mem(2 * TILE_SIZE * TILE_SIZE * sizeof(float));
    auto tile_A = (float*)local_ptr;
    auto tile_B = (float*)local_ptr + TILE_SIZE * TILE_SIZE;

    // Global and local thread indices
    int g_row = blockIdx.x * blockDim.x + threadIdx.x;
    int g_col = blockIdx.y * blockDim.y + threadIdx.y;
    int l_row = threadIdx.x;
    int l_col = threadIdx.y;

    float sum = 0.0f;

    // Loop over tiles of K dimension
    for (int tile_k = 0; tile_k < K; tile_k += TILE_SIZE) {
        // Load tile of A into local memory
        if (g_row < M && (tile_k + l_col) < K) {
            tile_A[l_row * TILE_SIZE + l_col] = A[g_row * K + (tile_k + l_col)];
        } else {
            tile_A[l_row * TILE_SIZE + l_col] = 0.0f;
        }
        
        // Load tile of B into local memory  
        if ((tile_k + l_row) < K && g_col < N) {
            tile_B[l_row * TILE_SIZE + l_col] = B[(tile_k + l_row) * N + g_col];
        } else {
            tile_B[l_row * TILE_SIZE + l_col] = 0.0f;
        }
        
        // Synchronize threads in the block
        __syncthreads();
        
        // Compute partial dot product using local tiles
        for (int k = 0; k < TILE_SIZE; k++) {
            sum += tile_A[l_row * TILE_SIZE + k] * tile_B[k * TILE_SIZE + l_col];
        }
        
        // Synchronize before loading next tile
        __syncthreads();
    }

    // Write result
    if (g_row < M && g_col < N) {
        C[g_row * N + g_col] = sum;
    }
}

bool compare_matrices(float* C1, float* C2, int M, int N) {
    for (int m = 0; m < M; m++) {
        for (int n = 0; n < N; n++) {
            float diff = C1[m * N + n] - C2[m * N + n];
            if (diff < -0.01f || diff > 0.01f) {
                vx_printf(">> MISMATCH at C[%d][%d]: C1=%f, C2=%f\n", m, n, C1[m*N + n], C2[m*N + n]);
                return false;
            }
        }
    }
    return true;
}


int main() {
    // We start in single threaded mode 
    // core0, thread0 runs the host part of the program and initializes
    // the buffers and the kernel arguments.
    vx_printf(">> Starting host part of the GEMM test in hostless mode (coreid=%d, warpid=%d, threadid=%d)\n", 
        vx_core_id(), vx_warp_id(), vx_thread_id());

    vx_printf(">> Hostless GEMM Test\n");

    const int M = 16;
    const int N = 16;
    const int K = 16;
    
    // Allocate matrices using our simple heap allocator
    vx_printf(">> Allocating matrices\n");
    float* A = (float*)vx_malloc(M * K * sizeof(float));
    float* B = (float*)vx_malloc(K * N * sizeof(float));
    float* C_ref = (float*)vx_malloc(M * N * sizeof(float));
    float* C_simple = (float*)vx_malloc(M * N * sizeof(float));
    float* C_tiled = (float*)vx_malloc(M * N * sizeof(float));

    vx_printf(">> Matrix A address: %p\n", A);
    vx_printf(">> Matrix B address: %p\n", B);
    vx_printf(">> Matrix C_ref address: %p\n", C_ref);
    vx_printf(">> Matrix C_simple address: %p\n", C_simple);
    vx_printf(">> Matrix C_tiled address: %p\n", C_tiled);

    rand_seed(0x123);
    bool all_passed = true;
    for (int i=0; i<NUM_TESTS; i++) {
        vx_printf(">> ========== Test %d ==========\n", i+1);
        
        // Initialize matrices A and B with random values
        for (int m = 0; m < M; m++) {
            for (int k = 0; k < K; k++) {
                A[m*K + k] = (float)(rand() % 100);
            }
        }
        for (int k = 0; k < K; k++) {
            for (int n = 0; n < N; n++) {
                B[k*N + n] = (float)(rand() % 100);
            }
        }
        
        // Initialize all output matrices to zero
        for (int m = 0; m < M; m++) {
            for (int n = 0; n < N; n++) {
                C_ref[m*N + n] = 0.0f;
                C_simple[m*N + n] = 0.0f;
                C_tiled[m*N + n] = 0.0f;
            }
        }

        // 1. CPU Reference Implementation
        vx_printf(">> Running CPU Reference GEMM\n");
        gemm_args_t ref_args;
        ref_args.A = A;
        ref_args.B = B;
        ref_args.C = C_ref;
        ref_args.M = M;
        ref_args.N = N;
        ref_args.K = K;
        gemm_ref(&ref_args);
        vx_printf(">> CPU Reference completed\n");

        // 2. GPU Simple Kernel (No Tiling)
        vx_printf(">> Running GPU Simple GEMM (no tiling)\n");
        gemm_args_t simple_args;
        simple_args.A = A;
        simple_args.B = B;
        simple_args.C = C_simple;
        simple_args.M = M;
        simple_args.N = N;
        simple_args.K = K;
        
        const uint32_t BLOCK_SIZE = 4;  // 4x4 threads per block for 16x16 matrices
        uint32_t grid_dim[2] = {(M + BLOCK_SIZE - 1) / BLOCK_SIZE, (N + BLOCK_SIZE - 1) / BLOCK_SIZE};
        uint32_t block_dim[2] = {BLOCK_SIZE, BLOCK_SIZE};
        
        vx_spawn_threads(2, grid_dim, block_dim, (vx_kernel_func_cb)gemm_kernel_simple, &simple_args);
        vx_printf(">> GPU Simple GEMM completed\n");

        // 3. GPU Tiled Kernel
        vx_printf(">> Running GPU Tiled GEMM (with tiling)\n");
        gemm_args_t tiled_args;
        tiled_args.A = A;
        tiled_args.B = B;
        tiled_args.C = C_tiled;
        tiled_args.M = M;
        tiled_args.N = N;
        tiled_args.K = K;
        
        vx_spawn_threads(2, grid_dim, block_dim, (vx_kernel_func_cb)gemm_kernel_tiled, &tiled_args);
        vx_printf(">> GPU Tiled GEMM completed\n");

        // Verify results
        bool simple_pass = compare_matrices(C_simple, C_ref, M, N);
        bool tiled_pass = compare_matrices(C_tiled, C_ref, M, N);
        
        if (simple_pass) {
            vx_printf(">> Simple Kernel: PASSED\n");
        } else {
            vx_printf(">> Simple Kernel: FAILED\n");
            all_passed = false;
        }
        
        if (tiled_pass) {
            vx_printf(">> Tiled Kernel: PASSED\n");
        } else {
            vx_printf(">> Tiled Kernel: FAILED\n");
            all_passed = false;
        }
        
        if (simple_pass && tiled_pass) {
            vx_printf(">> Test %d: ALL IMPLEMENTATIONS PASSED\n", i+1);
        } else {
            vx_printf(">> Test %d: SOME IMPLEMENTATIONS FAILED\n", i+1);
        }
    }

    if (all_passed) {
        vx_printf(">> ALL TESTS PASSED\n");
    } else {
        vx_printf(">> SOME TESTS FAILED\n");
    }

    vx_free(A);
    vx_free(B);
    vx_free(C_ref);
    vx_free(C_simple);
    vx_free(C_tiled);
    return 0;
}