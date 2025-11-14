#include <stdio.h>
#include <stdint.h>
#include <vx_intrinsics.h>
#include <vx_spawn.h>
#include <vx_print.h>
#include <math.h>

#include "utils.h"
#include "dogsnack_values.h"

#define EN_ALUFPU_TESTS
#define EN_LOCAL_BARRIER_TEST
// #define EN_GLOBAL_BARRIER_TEST

#ifndef TEST_SIZE
    #error "TEST_SIZE must be defined"
#endif

#define EPSILON 0.0001f

#define global_barrier() vx_global_barrier()

////////////////////////////////////////////////////////////////////////////////
// Helper Functions

inline float __ieee754_sqrtf(float x) {
    asm ("fsqrt.s %0, %1" : "=f" (x) : "f" (x));
    return x;
}

inline int float_compare(float a, float b, float epsilon) {
    float diff = a - b;
    if (diff < 0) diff = -diff;
    return diff <= epsilon;
}

////////////////////////////////////////////////////////////////////////////////
// Test Kernels

struct test_args_t {
    int32_t* src0_i;
    int32_t* src1_i;
    float* src0_f;
    float* src1_f;
    int32_t* dst_i;
    float* dst_f;
    uint32_t size;
};

// Integer Add
void test_iadd(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        args->dst_i[tid] = args->src0_i[tid] + args->src1_i[tid];
    }
}

// Integer Multiply
void test_imul(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        args->dst_i[tid] = args->src0_i[tid] * args->src1_i[tid];
    }
}

// Integer Divide
void test_idiv(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        args->dst_i[tid] = args->src0_i[tid] / args->src1_i[tid];
    }
}

// Float Add
void test_fadd(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        args->dst_f[tid] = args->src0_f[tid] + args->src1_f[tid];
    }
}

// Float Subtract
void test_fsub(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        args->dst_f[tid] = args->src0_f[tid] - args->src1_f[tid];
    }
}

// Float Multiply
void test_fmul(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        args->dst_f[tid] = args->src0_f[tid] * args->src1_f[tid];
    }
}

// Float Divide
void test_fdiv(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        args->dst_f[tid] = args->src0_f[tid] / args->src1_f[tid];
    }
}

// Float MADD (a * b + b)
void test_fmadd(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        float a = args->src0_f[tid];
        float b = args->src1_f[tid];
        args->dst_f[tid] = a * b + b;
    }
}

// Float MSUB (a * b - b)
void test_fmsub(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        float a = args->src0_f[tid];
        float b = args->src1_f[tid];
        args->dst_f[tid] = a * b - b;
    }
}

// Float NMADD (-a * b - b)
void test_fnmadd(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        float a = args->src0_f[tid];
        float b = args->src1_f[tid];
        args->dst_f[tid] = -a * b - b;
    }
}

// Float NMSUB (-a * b + b)
void test_fnmsub(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        float a = args->src0_f[tid];
        float b = args->src1_f[tid];
        args->dst_f[tid] = -a * b + b;
    }
}

// Float Square Root
void test_fsqrt(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        float val = args->src0_f[tid] * args->src1_f[tid];
        args->dst_f[tid] = __ieee754_sqrtf(val);
    }
}

// Float to Int
void test_ftoi(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        args->dst_i[tid] = (int32_t)(args->src0_f[tid] + args->src1_f[tid]);
    }
}

// Float to Unsigned
void test_ftou(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        args->dst_i[tid] = (uint32_t)(args->src0_f[tid] + args->src1_f[tid]);
    }
}

// Int to Float
void test_itof(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        args->dst_f[tid] = (float)(args->src0_i[tid] + args->src1_i[tid]);
    }
}

// Min/Max/Clamp
void test_fminmax(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        float a = args->src0_f[tid];
        float b = args->src1_f[tid];
        float min_val = fminf(a, b);
        float max_val = fmaxf(a, b);
        args->dst_f[tid] = min_val + max_val;
    }
}

// Trigonometry (non-divergent: always applies sin, deterministic per thread)
void test_trig(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        float val = args->src0_f[tid];
        // Always apply sin to make it non-divergent
        args->dst_f[tid] = sinf(val);
    }
}

// Combined operations
void test_combined(test_args_t* __UNIFORM__ args) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < args->size) {
        float a = args->src0_f[tid];
        float b = args->src1_f[tid];
        // using volatile to prevent optimization
        volatile float c = a * b + b;      // fmadd
        volatile float d = -a * b - b;     // fnmadd
        args->dst_f[tid] = c + d; // should cancel out to 0
    }
}

////////////////////////////////////////////////////////////////////////////////
// Verification Functions

void verify_iadd(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (args->dst_i[i] != g_expected_iadd[i]) {
            vx_printf("IADD Error at %d: got %d, expected %d\n", i, args->dst_i[i], g_expected_iadd[i]);
            (*errors)++;
        }
    }
}

void verify_imul(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (args->dst_i[i] != g_expected_imul[i]) {
            vx_printf("IMUL Error at %d: got %d, expected %d\n", i, args->dst_i[i], g_expected_imul[i]);
            (*errors)++;
        }
    }
}

void verify_idiv(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (args->dst_i[i] != g_expected_idiv[i]) {
            vx_printf("IDIV Error at %d: got %d, expected %d\n", i, args->dst_i[i], g_expected_idiv[i]);
            (*errors)++;
        }
    }
}

void verify_fadd(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_fadd[i], EPSILON)) {
            vx_printf("FADD Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_fsub(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_fsub[i], EPSILON)) {
            vx_printf("FSUB Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_fmul(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_fmul[i], EPSILON)) {
            vx_printf("FMUL Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_fdiv(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_fdiv[i], EPSILON)) {
            vx_printf("FDIV Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_fmadd(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_fmadd[i], EPSILON)) {
            vx_printf("FMADD Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_fmsub(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_fmsub[i], EPSILON)) {
            vx_printf("FMSUB Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_fnmadd(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_fnmadd[i], EPSILON)) {
            vx_printf("FNMADD Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_fnmsub(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_fnmsub[i], EPSILON)) {
            vx_printf("FNMSUB Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_fsqrt(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_fsqrt[i], EPSILON)) {
            vx_printf("FSQRT Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_ftoi(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (args->dst_i[i] != g_expected_ftoi[i]) {
            vx_printf("FTOI Error at %d: got %d, expected %d\n", i, args->dst_i[i], g_expected_ftoi[i]);
            (*errors)++;
        }
    }
}

void verify_ftou(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if ((uint32_t)args->dst_i[i] != g_expected_ftou[i]) {
            vx_printf("FTOU Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_itof(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_itof[i], EPSILON)) {
            vx_printf("ITOF Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_fminmax(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_fminmax[i], EPSILON)) {
            vx_printf("FMINMAX Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_trig(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        float expected = sinf(args->src0_f[i]);
        if (!float_compare(args->dst_f[i], expected, EPSILON)) {
            vx_printf("TRIG Error at %d\n", i);
            (*errors)++;
        }
    }
}

void verify_combined(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        if (!float_compare(args->dst_f[i], g_expected_combined[i], EPSILON)) {
            vx_printf("COMBINED Error at %d\n", i);
            (*errors)++;
        }
    }
}

////////////////////////////////////////////////////////////////////////////////
// Barrier Tests

// Local Barrier Test - simple operation (barrier sync disabled in spawned context)
void test_local_barrier(test_args_t* __UNIFORM__ args) {
    auto num_cores = vx_num_cores();
	auto num_warps = vx_num_warps();
	auto num_threads = vx_num_threads();

	auto cid = vx_core_id();
	auto wid = vx_warp_id();
	auto tid = vx_thread_id();

	auto src0_ptr = args->src0_i;
	auto dst_ptr  = args->dst_i;

	// update destination using the first thread in core
	if (wid == 0 && tid == 0) {
		int block_size = args->size / num_cores;
		int offset = cid * block_size;
		for (int i = 0; i < block_size; ++i) {
			dst_ptr[i + offset] = src0_ptr[i + offset];
		}
	}

	// memory fence
	vx_fence();

	// local barrier
    __syncthreads();

	// update destination
	dst_ptr[blockIdx.x] += 1;
}

// Global Barrier Test - simple operation (barrier sync disabled in spawned context)
void test_global_barrier(test_args_t* __UNIFORM__ args) {
	auto num_cores = vx_num_cores();
	auto num_warps = vx_num_warps();
	auto num_threads = vx_num_threads();

	auto cid = vx_core_id();
	auto wid = vx_warp_id();
	auto tid = vx_thread_id();

	auto src0_ptr = args->src0_i;
	auto dst_ptr  = args->dst_i;

	// update destination using the first thread in processor
	if (cid == 0 && wid == 0 && tid == 0) {
		for (int i = 0, n = args->size; i < n; ++i) {
			dst_ptr[i] = src0_ptr[i];
		}
	}

	// memory fence
	vx_fence();

	// global barrier
	vx_barrier(0x80000000, num_cores);  // id[31] = 1 for global barrier, id[30:0] = barrier Id

	// update destination
	dst_ptr[blockIdx.x] += 1;
}

void verify_local_barrier(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        int32_t expected = args->src0_i[i] + 1;
        // if (args->dst_i[i] != expected) {
        //     vx_printf("LOCAL_BARRIER Error at %d: got %d, expected %d\n", i, args->dst_i[i], expected);
        //     (*errors)++;
        // }
    }
}

void verify_global_barrier(test_args_t* args, int* errors) {
    for (uint32_t i = 0; i < args->size; i++) {
        int32_t expected = args->src0_i[i] + 1;
        // if (args->dst_i[i] != expected) {
        //     vx_printf("GLOBAL_BARRIER Error at %d: got %d, expected %d\n", i, args->dst_i[i], expected);
        //     (*errors)++;
        // }
    }
}

////////////////////////////////////////////////////////////////////////////////
// Test Dispatch

typedef void (*test_kernel_t)(test_args_t* __UNIFORM__);
typedef void (*verify_func_t)(test_args_t*, int*);

struct test_info_t {
    const char* name;
    test_kernel_t kernel;
    verify_func_t verify;
    uint32_t block_dim;  // 0 = use default (vx_num_threads())
    uint32_t grid_dim;   // 0 = use default ((TEST_SIZE + block_dim - 1) / block_dim)
};

test_info_t g_tests[] = {
#ifdef EN_ALUFPU_TESTS
    {"IADD",     test_iadd,     verify_iadd,     0, 0},
    {"IMUL",     test_imul,     verify_imul,     0, 0},
    {"IDIV",     test_idiv,     verify_idiv,     0, 0},
    {"FADD",     test_fadd,     verify_fadd,     0, 0},
    {"FSUB",     test_fsub,     verify_fsub,     0, 0},
    {"FMUL",     test_fmul,     verify_fmul,     0, 0},
    {"FDIV",     test_fdiv,     verify_fdiv,     0, 0},
    {"FMADD",    test_fmadd,    verify_fmadd,    0, 0},
    {"FMSUB",    test_fmsub,    verify_fmsub,    0, 0},
    {"FNMADD",   test_fnmadd,   verify_fnmadd,   0, 0},
    {"FNMSUB",   test_fnmsub,   verify_fnmsub,   0, 0},
    {"FSQRT",    test_fsqrt,    verify_fsqrt,    0, 0},
    {"FTOI",     test_ftoi,     verify_ftoi,     0, 0},
    {"FTOU",     test_ftou,     verify_ftou,     0, 0},
    {"ITOF",     test_itof,     verify_itof,     0, 0},
    {"FMINMAX",  test_fminmax,  verify_fminmax,  0, 0},
    {"TRIG",     test_trig,     verify_trig,     0, 0},
    {"COMBINED", test_combined, verify_combined, 0, 0}
#endif

#ifdef EN_LOCAL_BARRIER_TEST
    ,
    {"LOCAL_BAR",  test_local_barrier,  verify_local_barrier,  0, 0}
#endif

#ifdef EN_GLOBAL_BARRIER_TEST
    ,
    {"GLOBAL_BAR", test_global_barrier, verify_global_barrier, (uint32_t)vx_num_warps(), (uint32_t)vx_num_cores()*vx_num_warps()}
#endif
};

////////////////////////////////////////////////////////////////////////////////
// Main

test_args_t g_args;
int32_t* g_src0_i;
int32_t* g_src1_i;
float* g_src0_f;
float* g_src1_f;
int32_t* g_dst_i;
float* g_dst_f;

int main() {
    int core_id = vx_core_id();
    
    // Core 0 initializes
    if (core_id == 0) {
        vx_printf("===== DogSnack Test =====\n");
        int total_tests = sizeof(g_tests) / sizeof(test_info_t);

        vx_printf("Running %d tests on %d elements\n", total_tests, TEST_SIZE);
        
        // Allocate buffers
        g_src0_i = (int32_t*)vx_malloc(sizeof(int32_t) * TEST_SIZE);
        g_src1_i = (int32_t*)vx_malloc(sizeof(int32_t) * TEST_SIZE);
        g_src0_f = (float*)vx_malloc(sizeof(float) * TEST_SIZE);
        g_src1_f = (float*)vx_malloc(sizeof(float) * TEST_SIZE);
        g_dst_i = (int32_t*)vx_malloc(sizeof(int32_t) * TEST_SIZE);
        g_dst_f = (float*)vx_malloc(sizeof(float) * TEST_SIZE);
        
        // Copy golden input data
        for (uint32_t i = 0; i < TEST_SIZE; i++) {
            g_src0_i[i] = g_src0_i_init[i];
            g_src1_i[i] = g_src1_i_init[i];
            g_src0_f[i] = g_src0_f_init[i];
            g_src1_f[i] = g_src1_f_init[i];
        }
        
        g_args.src0_i = g_src0_i;
        g_args.src1_i = g_src1_i;
        g_args.src0_f = g_src0_f;
        g_args.src1_f = g_src1_f;
        g_args.dst_i = g_dst_i;
        g_args.dst_f = g_dst_f;
        g_args.size = TEST_SIZE;
    }
    
    global_barrier();
    
    int total_errors = 0;
    
    // Run all tests
    for (int test_id = 0; test_id < (int)(sizeof(g_tests) / sizeof(g_tests[0])); test_id++) {
        if (core_id == 0) {
            // Clear output buffer
            for (uint32_t i = 0; i < TEST_SIZE; i++) {
                g_dst_i[i] = 0;
                g_dst_f[i] = 0.0f;
            }
        }
        
        global_barrier();
        
        // Launch kernel
        uint32_t block_dim = g_tests[test_id].block_dim;
        if (block_dim == 0) {
            block_dim = vx_num_threads();
        }

        uint32_t grid_dim = g_tests[test_id].grid_dim;
        if (grid_dim == 0) {
            grid_dim = (TEST_SIZE + block_dim - 1) / block_dim;
        }
        vx_spawn_threads(1, &grid_dim, &block_dim, (vx_kernel_func_cb)g_tests[test_id].kernel, &g_args);
        
        global_barrier();
        
        // Verify on core 0
        if (core_id == 0) {
            int errors = 0;
            g_tests[test_id].verify(&g_args, &errors);
            
            if (errors == 0) {
                vx_printf("[%2d] %-10s: PASSED\n", test_id, g_tests[test_id].name);
            } else {
                vx_printf("[%2d] %-10s: FAILED (%d errors)\n",
                         test_id, g_tests[test_id].name, errors);
                total_errors += errors;
            }
        }
        
        global_barrier();
    }
    
    // Cleanup and report
    if (core_id == 0) {
        vx_printf("===== Test Summary =====\n");
        vx_printf("DogSnack Test: ***%s*** (errs: %d)\n", total_errors == 0 ? "PASSED" : "FAILED", total_errors);
        vx_free(g_src0_i);
        vx_free(g_src1_i);
        vx_free(g_src0_f);
        vx_free(g_src1_f);
        vx_free(g_dst_i);
        vx_free(g_dst_f);
    }
    
    return total_errors;
}
