#include <vx_intrinsics.h>
#include <vx_spawn.h>
#include <vx_print.h>
#include "utils.h"

#define FLOAT_ULP 6
typedef float TYPE;

// -----------------------------------------------------------------------------
// Kernel Arguments
// -----------------------------------------------------------------------------
struct stencil_arg_t {
    TYPE* A;
    TYPE* B;
    uint32_t size;
};

// -----------------------------------------------------------------------------
// Device kernel: 3D 3x3x3 stencil averaging
// -----------------------------------------------------------------------------
void stencil_kernel(stencil_arg_t* __UNIFORM__ arg) {
    auto A = arg->A;
    auto B = arg->B;
    auto size = arg->size;

    int col = blockIdx.x * blockDim.x + threadIdx.x;
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int dep = blockIdx.z * blockDim.z + threadIdx.z;

    if (col >= size || row >= size || dep >= size)
        return;

    TYPE sum = 0;
    int count = 0;

    // 3x3x3 stencil
    for (int dz = -1; dz <= 1; ++dz) {
        for (int dy = -1; dy <= 1; ++dy) {
            for (int dx = -1; dx <= 1; ++dx) {
                int nz = dep + dz;
                int ny = row + dy;
                int nx = col + dx;

                // Boundary replication
                if (nz < 0) nz = 0;
                else if (nz >= size) nz = size - 1;
                if (ny < 0) ny = 0;
                else if (ny >= size) ny = size - 1;
                if (nx < 0) nx = 0;
                else if (nx >= size) nx = size - 1;

                sum += A[nz * size * size + ny * size + nx];
                count++;
            }
        }
    }

    B[dep * size * size + row * size + col] = sum / count;
}

// -----------------------------------------------------------------------------
// CPU Reference Implementation
// -----------------------------------------------------------------------------
void stencil_ref(stencil_arg_t* args) {
    auto A = args->A;
    auto B = args->B;
    auto size = args->size;

    for (uint32_t z = 0; z < size; ++z) {
        for (uint32_t y = 0; y < size; ++y) {
            for (uint32_t x = 0; x < size; ++x) {
                TYPE sum = 0;
                int count = 0;
                for (int dz = -1; dz <= 1; ++dz) {
                    for (int dy = -1; dy <= 1; ++dy) {
                        for (int dx = -1; dx <= 1; ++dx) {
                            int nz = z + dz;
                            int ny = y + dy;
                            int nx = x + dx;
                            if (nz < 0) nz = 0;
                            else if (nz >= size) nz = size - 1;
                            if (ny < 0) ny = 0;
                            else if (ny >= size) ny = size - 1;
                            if (nx < 0) nx = 0;
                            else if (nx >= size) nx = size - 1;
                            sum += A[nz * size * size + ny * size + nx];
                            count++;
                        }
                    }
                }
                B[z * size * size + y * size + x] = sum / count;
            }
        }
    }
}

// -----------------------------------------------------------------------------
// Compare results
// -----------------------------------------------------------------------------
bool compare_arrays(TYPE* ref, TYPE* test, uint32_t size) {
    uint32_t total = size * size * size;
    for (uint32_t i = 0; i < total; ++i) {
        float a = ref[i];
        float b = test[i];
        int32_t ia = *((int32_t*)&a);
        int32_t ib = *((int32_t*)&b);
        int32_t d = (ia > ib) ? (ia - ib) : (ib - ia);
        if (d > FLOAT_ULP) {
            vx_printf("Mismatch at %d: ref=%f test=%f (ulp=%d)\n", i, a, b, d);
            return false;
        }
    }
    return true;
}

// -----------------------------------------------------------------------------
// Global variables visible to all cores
// -----------------------------------------------------------------------------
TYPE* A;
TYPE* B;
TYPE* B_ref;
stencil_arg_t args;

// -----------------------------------------------------------------------------
// Main test
// -----------------------------------------------------------------------------
int stencil_test(int test_no, uint32_t size) {
    int core_id = vx_core_id();

    if (core_id == 0) {
        vx_printf("===== Test %d: 3D Stencil (%dx%dx%d) =====\n", test_no, size, size, size);
        uint32_t total = size * size * size;

        // Allocate arrays
        A     = (TYPE*)vx_malloc(total * sizeof(TYPE));
        B     = (TYPE*)vx_malloc(total * sizeof(TYPE));
        B_ref = (TYPE*)vx_malloc(total * sizeof(TYPE));

        // Initialize input
        for (uint32_t i = 0; i < total; ++i)
            A[i] = (TYPE)(vx_rand() % 100) / 100.0f;
        for (uint32_t i = 0; i < total; ++i)
            B[i] = B_ref[i] = 0.0f;

        // CPU reference
        stencil_arg_t ref_args = {A, B_ref, size};
        stencil_ref(&ref_args);

        // Prepare GPU args
        args.A = A;
        args.B = B;
        args.size = size;
    }

    vx_global_barrier();

    // Launch GPU kernel
    uint32_t block_dim[3] = {2, 2, 2};
    uint32_t grid_dim[3]  = {(args.size + block_dim[0] - 1) / block_dim[0],
                             (args.size + block_dim[1] - 1) / block_dim[1],
                             (args.size + block_dim[2] - 1) / block_dim[2]};

    vx_spawn_threads(3, grid_dim, block_dim, (vx_kernel_func_cb)stencil_kernel, &args);

    vx_global_barrier();

    if (core_id == 0) {
        bool pass = compare_arrays(B_ref, B, args.size);
        vx_printf(pass ? ">> 3D Stencil: PASSED\n" : ">> 3D Stencil: FAILED\n");

        vx_free(A);
        vx_free(B);
        vx_free(B_ref);
    }

    return 0;
}

// -----------------------------------------------------------------------------
// Entry point
// -----------------------------------------------------------------------------
int main() {
    stencil_test(1, 4);
    stencil_test(2, 8);
    return 0;
}
