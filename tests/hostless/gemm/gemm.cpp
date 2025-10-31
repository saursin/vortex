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
                vx_printf("ERROR: Mismatch at C[%d][%d]: C1=%f, C2=%f\n", m, n, C1[m*N + n], C2[m*N + n]);
                return false;
            }
        }
    }
    return true;
}

void initialize_matrix(float* mat, int rows, int cols, bool random=true) {
    for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
            mat[r * cols + c] = random ? (float)(vx_rand() % 100) : 0.0f;
        }
    }
}

////////////////////////////////////////////////////////////////////////////////

// Global variables visible to all cores
float* A;
float* B;
float* C;
float* C_tiled;
float* C_ref;

gemm_args_t args;

int gemm(int test_no, int M, int N, int K) {
    int core_id = vx_core_id();

    if(core_id == 0) {
        vx_printf("===== Test %d: GEMM of (%dx%d) x (%dx%d) matrices =====\n", test_no, M, K, K, N);
        // Allocate matrices using our simple heap allocator
        vx_printf(">> Allocating matrices\n");
        A = (float*)vx_malloc(M * K * sizeof(float));
        B = (float*)vx_malloc(K * N * sizeof(float));
        C = (float*)vx_malloc(M * N * sizeof(float));
        C_tiled = (float*)vx_malloc(M * N * sizeof(float));
        C_ref = (float*)vx_malloc(M * N * sizeof(float));

        vx_printf(">> Matrix A address: %p\n", A);
        vx_printf(">> Matrix B address: %p\n", B);
        vx_printf(">> Matrix C address: %p\n", C);
        vx_printf(">> Matrix C_ref address: %p\n", C_ref);

        // Initialize matrices A and B with random values
        initialize_matrix(A, M, K, true);
        initialize_matrix(B, K, N, true);
        initialize_matrix(C, M, N, false);
        initialize_matrix(C_tiled, M, N, false);
        initialize_matrix(C_ref, M, N, false);

        // 1. CPU Reference Implementation
        vx_printf(">> Running Reference GEMM\n");
        gemm_args_t ref_args;
        ref_args.A = A;
        ref_args.B = B;
        ref_args.C = C_ref;
        ref_args.M = M;
        ref_args.N = N;
        ref_args.K = K;
        gemm_ref(&ref_args);

        vx_printf(">> Running GPU GEMM\n");
        args.A = A;
        args.B = B;
        args.C = C;
        args.M = M;
        args.N = N;
        args.K = K;
    }

    vx_global_barrier();

    const uint32_t BLOCK_SIZE = 4;  // 4x4 threads per block for 16x16 matrices
    uint32_t grid_dim[2] = {(M + BLOCK_SIZE - 1) / BLOCK_SIZE, (N + BLOCK_SIZE - 1) / BLOCK_SIZE};
    uint32_t block_dim[2] = {BLOCK_SIZE, BLOCK_SIZE};   
    vx_spawn_threads(2, grid_dim, block_dim, (vx_kernel_func_cb)gemm_kernel_simple, &args);

    vx_global_barrier();

    if(core_id == 0) {
        vx_printf(">> Running Tiled GPU GEMM\n");
        args.C = C_tiled;
    }

    vx_global_barrier();

    vx_spawn_threads(2, grid_dim, block_dim, (vx_kernel_func_cb)gemm_kernel_tiled, &args);
    vx_global_barrier();

    if(core_id == 0) {
        // Verify results
        bool simple_pass = compare_matrices(C, C_ref, M, N);
        bool tiled_pass = compare_matrices(C_tiled, C_ref, M, N);
        
        if (simple_pass) {
            vx_printf(">> GEMM: PASSED\n");
        } else {
            vx_printf(">> GEMM: FAILED\n");
        }
        
        if (tiled_pass) {
            vx_printf(">> Tiled GEMM: PASSED\n");
        } else {
            vx_printf(">> Tiled GEMM: FAILED\n");
        }

        // Free matrices
        vx_free(A);
        vx_free(B);
        vx_free(C);
        vx_free(C_tiled);
        vx_free(C_ref);
    }
    return 0;
}


int main() {
    for (int t = 0; t < NUM_TESTS; t++) {
        int M = 4 * (t + 1);
        int N = 4 * (t + 1);
        int K = 4 * (t + 1);
        gemm(t+1, M, N, K);
    }
    return 0;
}