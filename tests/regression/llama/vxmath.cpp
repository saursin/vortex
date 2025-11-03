#include <iostream>
#include <unistd.h>
#include <string.h>
#include <vortex.h>
#include <vector>
#include "common.h"

#ifdef DEBUG
    #define D(x) x
#else
    #define D(x)
#endif

#define RT_CHECK(_expr)                                         \
    do {                                                         \
        int _ret = _expr;                                          \
        if (0 == _ret)                                             \
            break;                                                   \
        printf("Error: '%s' returned %d!\n", #_expr, (int)_ret);   \
        exit(-1);                                                  \
    } while (false)


////////////////////////////////////////////////////////////////////////////////
static uint64_t num_cores, num_warps, num_threads, num_total_threads;
vx_device_h device = nullptr;

void vx_init() {
    std::cout << "open device connection" << std::endl;
    RT_CHECK(vx_dev_open(&device));
    RT_CHECK(vx_dev_caps(device, VX_CAPS_NUM_CORES, &num_cores));
    RT_CHECK(vx_dev_caps(device, VX_CAPS_NUM_WARPS, &num_warps));
    RT_CHECK(vx_dev_caps(device, VX_CAPS_NUM_THREADS, &num_threads));
    num_total_threads = num_cores * num_warps * num_threads;
}

////////////////////////////////////////////////////////////////////////////////
// Matmul
vx_buffer_h matmul_A_buffer = nullptr;
vx_buffer_h matmul_B_buffer = nullptr;
vx_buffer_h matmul_C_buffer = nullptr;
vx_buffer_h matmul_krnl_buffer = nullptr;
vx_buffer_h matmul_args_buffer = nullptr;
matmul_kernel_args_t matmul_kernel_arg = {};
char *kernel = "kernel.vxbin";

void matmul_cleanup() {
    if (device) {
        vx_mem_free(matmul_A_buffer);
        vx_mem_free(matmul_B_buffer);
        vx_mem_free(matmul_C_buffer);
        vx_mem_free(matmul_krnl_buffer);
        vx_mem_free(matmul_args_buffer);
        vx_dev_close(device);
    }
}

void vx_matmul(float* C, float* A, float* B, int M, int N, int K) {
    size_t A_sz = M * K * sizeof(float);
    size_t B_sz = K * N * sizeof(float);
    size_t C_sz = M * N * sizeof(float);

    // prepare kernel argument
    matmul_kernel_arg.M = M;
    matmul_kernel_arg.N = N;
    matmul_kernel_arg.K = K;

    const uint32_t BLOCK_SIZE = 4;  // 4x4 threads per block for 16x16 matrices
    matmul_kernel_arg.block_dim[0] = BLOCK_SIZE;
    matmul_kernel_arg.block_dim[1] = (N == 1) ? 1 : BLOCK_SIZE;  // Use 1D for matrix-vector
    matmul_kernel_arg.grid_dim[0] = (M + BLOCK_SIZE - 1) / BLOCK_SIZE;
    matmul_kernel_arg.grid_dim[1] = (N + matmul_kernel_arg.block_dim[1] - 1) / matmul_kernel_arg.block_dim[1];

    RT_CHECK(vx_mem_alloc(device, A_sz, VX_MEM_READ, &matmul_A_buffer));
    RT_CHECK(vx_mem_address(matmul_A_buffer, &matmul_kernel_arg.A_addr));
    RT_CHECK(vx_mem_alloc(device, B_sz, VX_MEM_READ, &matmul_B_buffer));
    RT_CHECK(vx_mem_address(matmul_B_buffer, &matmul_kernel_arg.B_addr));
    RT_CHECK(vx_mem_alloc(device, C_sz, VX_MEM_WRITE, &matmul_C_buffer));
    RT_CHECK(vx_mem_address(matmul_C_buffer, &matmul_kernel_arg.C_addr));

    D(std::cout << "A_addr=0x" << std::hex << matmul_kernel_arg.A_addr << std::endl;)
    D(std::cout << "B_addr=0x" << std::hex << matmul_kernel_arg.B_addr << std::endl;)
    D(std::cout << "C_addr=0x" << std::hex << matmul_kernel_arg.C_addr << std::endl;)

    // upload source buffer A
    D(std::cout << "upload source buffer A" << std::endl;)
    RT_CHECK(vx_copy_to_dev(matmul_A_buffer, A, 0, A_sz));

    // upload source buffer B
    D(std::cout << "upload source buffer B" << std::endl;)
    RT_CHECK(vx_copy_to_dev(matmul_B_buffer, B, 0, B_sz));

    // upload kernel
    D(std::cout << "upload program" << std::endl;)
    RT_CHECK(vx_upload_kernel_file(device, kernel, &matmul_krnl_buffer));

    // upload kernel argument
    D(std::cout << "upload kernel argument" << std::endl;)
    RT_CHECK(vx_upload_bytes(device, &matmul_kernel_arg, sizeof(matmul_kernel_args_t), &matmul_args_buffer));

    // start device
    D(std::cout << "start device" << std::endl;)
    RT_CHECK(vx_start(device, matmul_krnl_buffer, matmul_args_buffer));

    // wait for completion
    D(std::cout << "wait for completion" << std::endl;)
    RT_CHECK(vx_ready_wait(device, VX_MAX_TIMEOUT));

    // download result buffer C
    D(std::cout << "download result buffer C" << std::endl;)
    RT_CHECK(vx_copy_from_dev(C, matmul_C_buffer, 0, C_sz));

    // free device memory but keep device open for reuse
    vx_mem_free(matmul_A_buffer);
    vx_mem_free(matmul_B_buffer);
    vx_mem_free(matmul_C_buffer);
    vx_mem_free(matmul_krnl_buffer);
    vx_mem_free(matmul_args_buffer);
}
