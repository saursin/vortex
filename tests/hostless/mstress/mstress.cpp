#include <vx_intrinsics.h>
#include <vx_spawn.h>
#include <vx_print.h>
#include "utils.h"

#define NUM_LOADS 4
#define NUM_TESTS 3

struct kernel_arg_t {
    float* src_data;     // source data array
    uint32_t* addr_tbl;  // address indirection table
    float* dst;          // output array
    uint32_t num_points;
    uint32_t stride;
};

// -----------------------------------------------------------------------------
// Reference implementation (CPU-side check)
// -----------------------------------------------------------------------------
void indirect_ref(kernel_arg_t* args) {
    float* src = args->src_data;
    uint32_t* addr = args->addr_tbl;
    float* dst = args->dst;
    uint32_t N = args->num_points;

    for (uint32_t i = 0; i < N; ++i) {
        float value = 1.0f;
        for (uint32_t j = 0; j < NUM_LOADS; ++j) {
            uint32_t index = addr[i + j];
            value *= src[index];
        }
        dst[i] = value;
    }
}

// -----------------------------------------------------------------------------
// GPU kernel (runs on each thread group)
// -----------------------------------------------------------------------------
void indirect_kernel(kernel_arg_t* __UNIFORM__ args) {
    uint32_t* addr = args->addr_tbl;
    float* src     = args->src_data;
    float* dst     = args->dst;
    uint32_t stride = args->stride;

    uint32_t offset = blockIdx.x * stride;

    for (uint32_t i = 0; i < stride; ++i) {
        float value = 1.0f;
        for (uint32_t j = 0; j < NUM_LOADS; ++j) {
            uint32_t index = addr[offset + i + j];
            value *= src[index];
        }
        dst[offset + i] = value;
    }
}

// -----------------------------------------------------------------------------
// Utility: compare results
// -----------------------------------------------------------------------------
bool compare_vectors(float* ref, float* test, uint32_t N) {
    for (uint32_t i = 0; i < N; ++i) {
        float diff = ref[i] - test[i];
        if (diff < -0.01f || diff > 0.01f) {
            vx_printf("Mismatch at %d: ref=%f, test=%f\n", i, ref[i], test[i]);
            return false;
        }
    }
    return true;
}

// -----------------------------------------------------------------------------
// Main hostless test
// -----------------------------------------------------------------------------
float* src;
float* dst;
float* dst_ref;
uint32_t* addr_tbl;
kernel_arg_t args;

int indirect_test(int test_no, uint32_t num_points, uint32_t stride) {
    int core_id = vx_core_id();

    if (core_id == 0) {
        vx_printf("===== Test %d: Indirect Load Multiply (Points: %d, Stride: %d) =====\n", test_no, num_points, stride);
        uint32_t num_addrs = num_points + NUM_LOADS - 1;

        // Allocate arrays
        src      = (float*)vx_malloc(num_points * sizeof(float));
        addr_tbl = (uint32_t*)vx_malloc(num_addrs * sizeof(uint32_t));
        dst      = (float*)vx_malloc(num_points * sizeof(float));
        dst_ref  = (float*)vx_malloc(num_points * sizeof(float));

        // Initialize random data
        for (uint32_t i = 0; i < num_points; ++i)
            src[i] = (float)(vx_rand() % 10 + 1);  // avoid zeros
        for (uint32_t i = 0; i < num_addrs; ++i)
            addr_tbl[i] = vx_rand() % num_points;
        for (uint32_t i = 0; i < num_points; ++i)
            dst[i] = dst_ref[i] = 0.0f;

        // CPU reference
        kernel_arg_t ref_args = {src, addr_tbl, dst_ref, num_points, stride};
        indirect_ref(&ref_args);

        // Prepare GPU args
        args.src_data = src;
        args.addr_tbl = addr_tbl;
        args.dst      = dst;
        args.num_points = num_points;
        args.stride     = stride;
    }

    vx_global_barrier();

    // Each block handles one stride-sized chunk
    uint32_t grid_dim[1]  = {(args.num_points + args.stride - 1) / args.stride};
    vx_spawn_threads(1, grid_dim, nullptr, (vx_kernel_func_cb)indirect_kernel, &args);

    vx_global_barrier();

    if (core_id == 0) {
        bool pass = compare_vectors(dst_ref, dst, args.num_points);
        vx_printf(pass ? ">> Indirect Load Test: PASSED\n" : ">> Indirect Load Test: FAILED\n");

        vx_free(src);
        vx_free(addr_tbl);
        vx_free(dst);
        vx_free(dst_ref);
    }
    return 0;
}

// -----------------------------------------------------------------------------
// Entry point
// -----------------------------------------------------------------------------
int main() {
    for (int t = 0; t < NUM_TESTS; ++t) {
        uint32_t points = 64 * (t + 1);
        uint32_t stride = 8 * (t + 1);
        indirect_test(t + 1, points, stride);
    }
    return 0;
}
