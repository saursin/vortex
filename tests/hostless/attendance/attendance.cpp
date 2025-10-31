#include <stdio.h>
#include <vx_intrinsics.h>
#include <vx_spawn.h>
#include <vx_print.h>
#include "utils.h"

#define global_barrier() vx_global_barrier()

////////////////////////////////////////////////////////////////////////////////
// Kernel

struct kernel_args_t {
    int* attendance;
    int N;
};

// Simple print kernel to be spawned on all threads
void attendance_kernel(kernel_args_t* __UNIFORM__ args) {
    int* attendance = reinterpret_cast<int*>(args->attendance);

    // Use simple linear thread ID
    int g_tid = blockIdx.x * blockDim.x + threadIdx.x;

    vx_printf("(C:%2d, W:%2d, T:%2d): GTID %3d - I am present!\n",
            vx_core_id(), vx_warp_id(), vx_thread_id(), g_tid);

    // Mark attendance with bounds check
    if (g_tid < args->N) {
        attendance[g_tid] = 1;
        vx_fence();
    }
}

int check_attendance(int* attendance, int N) {
    int not_present = 0;
    for (int i = 0; i < N; i++) {
        if (attendance[i] == 0) {
            vx_printf(">> ERROR: Thread %d did not attend!\n", i);
            not_present++;
        }
    }
    return not_present;
}

////////////////////////////////////////////////////////////////////////////////
// Host Code

// Global Variables that all cores can access
int *g_attendance;
kernel_args_t args;

int main() {
    int core_id = vx_core_id();
    
    // Calculate total threads across all cores
    int num_total_threads = vx_num_cores() * vx_num_warps() * vx_num_threads();

    // Core 0 is the main thread - handles initialization
    if (core_id == 0) {
        g_attendance = (int*)vx_malloc(sizeof(int) * num_total_threads);
        for (int i = 0; i < num_total_threads; i++) {
            g_attendance[i] = 0;    // Initialize attendance to 0
        }       
        vx_printf(">> Hostless Attendance Test (All Threads)\n");
        vx_printf(">> Total threads: %d (cores=%d, warps=%d, threads=%d)\n", 
                  num_total_threads, vx_num_cores(), vx_num_warps(), vx_num_threads());
        vx_printf(">> Launching attendance kernel on all threads\n");

        // All cores set the same attendance pointer
        args.attendance = g_attendance;
        args.N = num_total_threads;
    }
    
    // Global barrier - all cores wait for core 0 to finish initialization
    global_barrier();
    
    // Launch all threads at once
    uint32_t grid_dim = num_total_threads;
    uint32_t block_dim = 1;

    vx_spawn_threads(1, &grid_dim, &block_dim, (vx_kernel_func_cb)attendance_kernel, &args);

    // Global barrier - all cores wait for all threads to complete
    global_barrier();

    // Only core 0 does verification
    if (core_id == 0) {
        vx_printf(">> Attendance kernel complete\n");
        // Verify attendance
        int not_present = check_attendance(g_attendance, num_total_threads);
        if (not_present > 0) {
            vx_printf(">> ERROR: %d threads did not attend!\n", not_present);
            vx_printf(">> Attendance test: FAILED\n");
        } else {
            vx_printf(">> All threads attended successfully!\n");
            vx_printf(">> Attendance test: PASSED\n");
        }
        vx_free(g_attendance);
    }
    return 0;
}
