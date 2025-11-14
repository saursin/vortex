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

    // Mark attendance with bounds check
    if (g_tid < args->N) {
        attendance[g_tid] = 1;
        vx_fence();
    }
}

int check_attendance(int* attendance, int N, char *entity_name) {
    int not_present = 0;
    for (int i = 0; i < N; i++) {
        if (attendance[i] == 0) {
            vx_printf(">> ERROR: %s %d did not attend!\n", entity_name, i);
            not_present++;
        }
    }
    return not_present;
}

void print_attendance(int* attendance, int N, char *entity_name) {
    vx_printf(">> %s Attendance:\n", entity_name);
    for(int i = 0; i < N; i++) {
        vx_putchar(attendance[i] ? 'P' : '_');
        // newline after every 64 entries
        if (((i + 1) & 63) == 0) {
            vx_printf("\n");
        }
    }
    vx_printf("\n");
}

////////////////////////////////////////////////////////////////////////////////
// Host Code

// Global Variables that all cores can access
int *g_attendance;      // thread-level attendance array
int *g_core_attendance;      // core-level attendance array
kernel_args_t args;

int main() {
    int core_id = vx_core_id();
    
    // Calculate total threads across all cores
    int num_total_threads = vx_num_cores() * vx_num_warps() * vx_num_threads();

    // Core 0 is the main thread - handles initialization
    if (core_id == 0) {
        g_core_attendance = (int*)vx_malloc(sizeof(int) * vx_num_cores());
        for (int i = 0; i < vx_num_cores(); i++) {
            g_core_attendance[i] = 0;    // Initialize core attendance to 0
        }
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

    // All cores update their core attendance
    g_core_attendance[core_id] = 1;
    vx_fence();

    // We launch with n_warps_total (num_cores * num_warps) blocks
    // and 1 block = 1 warp to exercise all hardware threads in the system
    uint32_t grid_dim = vx_num_cores() * vx_num_warps();
    uint32_t block_dim = vx_num_threads();

    vx_spawn_threads(1, &grid_dim, &block_dim, (vx_kernel_func_cb)attendance_kernel, &args);

    // Global barrier - all cores wait for all threads to complete
    global_barrier();

    // Only core 0 does verification
    if (core_id == 0) {
        vx_printf(">> Attendance kernel complete\n");
        bool core_attendance_passed = true;
        bool thread_attendance_passed = true;

        // Verify core attendance
        vx_printf("===== Test-1: Core Attendance =====\n");
        print_attendance(g_core_attendance, vx_num_cores(), (char *)"Core");
        int cores_not_attended = check_attendance(g_core_attendance, vx_num_cores(), (char *)"Core");
        if (cores_not_attended > 0) {
            vx_printf(">> ERROR: %d cores did not attend!\n", cores_not_attended);
            core_attendance_passed = false;
        } else {
            vx_printf(">> All cores attended successfully!\n");
        }

        // Verify thread attendance
        vx_printf("===== Test-2: Thread Attendance =====\n");
        print_attendance(g_attendance, num_total_threads, (char *)"Thread");
        int threads_not_attended = check_attendance(g_attendance, num_total_threads, (char *)"Thread");
        if (threads_not_attended > 0) {
            vx_printf(">> ERROR: %d threads did not attend!\n", threads_not_attended);
            thread_attendance_passed = false;
        } else {
            vx_printf(">> All threads attended successfully!\n");
        }

        // Final result
        vx_printf(">> Attendance Test: ***%s***\n", (core_attendance_passed && thread_attendance_passed) ? "PASSED" : "FAILED");
        vx_free(g_attendance);
        vx_free(g_core_attendance);
    }
    return 0;
}
