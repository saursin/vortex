#include <vx_intrinsics.h>
#include <vx_spawn.h>
#include <vx_print.h>
#include "utils.h"

#define NUM_TESTS 3
typedef float TYPE;

typedef struct {
  uint32_t num_points;
  uint64_t src_addr;
  uint64_t dst_addr;
} kernel_arg_t;

void gen_src_data(TYPE *src_data, uint32_t size) {
  for (uint32_t i = 0; i < size; ++i) {
    auto r = static_cast<float>(vx_rand()) / RAND_MAX;
    auto value = static_cast<TYPE>(r * size);
    src_data[i] = value;
  }
}

void gen_ref_data(TYPE *ref_data, const TYPE *src_data, uint32_t size) {
  for (uint32_t i = 0; i < size; ++i) {
    TYPE ref_value = src_data[i];
    uint32_t pos = 0;
    for (uint32_t j = 0; j < size; ++j) {
      TYPE cur_value = src_data[j];
      pos += (cur_value < ref_value) || (cur_value == ref_value && j < i);
    }
    ref_data[pos] = ref_value;
  }
}


void kernel_body(kernel_arg_t* __UNIFORM__ arg) {
	uint32_t num_points = arg->num_points;
	auto src_ptr = (TYPE*)arg->src_addr;
	auto dst_ptr = (TYPE*)arg->dst_addr;

	auto ref_value = src_ptr[blockIdx.x];

	uint32_t pos = 0;
	for (uint32_t i = 0; i < num_points; ++i) {
		auto cur_value = src_ptr[i];
		pos += (cur_value < ref_value) || ((cur_value == ref_value) && (i < blockIdx.x));
	}
	dst_ptr[pos] = ref_value;
}

// -----------------------------------------------------------------------------
// Compare two arrays
// -----------------------------------------------------------------------------
bool compare_vectors(TYPE* ref, TYPE* test, uint32_t N) {
    for (uint32_t i = 0; i < N; ++i) {
        if (ref[i] != test[i]) {
            vx_printf("Mismatch at %u: ref=%f, test=%f\n", i, ref[i], test[i]);
            return false;
        }
    }
    return true;
}

// -----------------------------------------------------------------------------
// Global state
// -----------------------------------------------------------------------------
TYPE* src;
TYPE* dst;
TYPE* dst_ref;
kernel_arg_t args;

// -----------------------------------------------------------------------------
// Main test
// -----------------------------------------------------------------------------
int rank_sort_test(int test_no, uint32_t count) {
    uint32_t total_threads = vx_num_cores() * vx_num_warps() * vx_num_threads();
    uint32_t num_points = count * total_threads;
    uint32_t buf_size   = num_points * sizeof(TYPE);

    int core_id = vx_core_id();
    if (core_id == 0) {
        vx_printf("===== Test %d: Rank Sort =====\n", test_no);
        vx_printf(">> Number of points: %u\n", num_points);
        vx_printf(">> Buffer size: %u bytes\n", buf_size);

        // Allocate memory
        src     = (TYPE*)vx_malloc(buf_size);
        dst     = (TYPE*)vx_malloc(buf_size);
        dst_ref = (TYPE*)vx_malloc(buf_size);

        // Generate random data
        gen_src_data(src, num_points);

        // Generate reference data
        gen_ref_data(dst_ref, src, num_points);

        // Prepare GPU args
        args.src_addr = (uint64_t)src;
        args.dst_addr = (uint64_t)dst;
        args.num_points = num_points;
    }

    vx_global_barrier();

    // Launch kernel: exactly one block per element; one thread per block
    vx_spawn_threads(1, &num_points, nullptr, (vx_kernel_func_cb)kernel_body, &args);

    vx_global_barrier();

    if (core_id == 0) {
        bool pass = compare_vectors(dst_ref, dst, num_points);
        vx_printf(pass ? ">> Rank Sort: PASSED\n" : ">> Rank Sort: FAILED\n");

        vx_free(src);
        vx_free(dst);
        vx_free(dst_ref);
    }

    return 0;
}

// -----------------------------------------------------------------------------
// Entry point
// -----------------------------------------------------------------------------
int main() {
    rank_sort_test(1, 2);
    return 0;
}
