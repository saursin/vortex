#include <vx_print.h>
#pragma once

////////////////////////////////////////////////////////////////////////////////
// Simple Heap Implementation for Hostless Tests
// 
// This is a very basic malloc/free implementation for use in hostless tests.
// It uses a fixed-size memory pool defined as a global array.
// This implementation does not support freeing memory.

#define HEAP_SZ 8192    // 8 KB heap size

static char __heap_pool[HEAP_SZ];      // memory pool
static int __heap_pool_offset = 0;     // tracks used memory

void* vx_malloc(unsigned size) {
    if (__heap_pool_offset + size > HEAP_SZ) {
        vx_printf("HEAP: Out of memory\n");
        return nullptr;  // not enough memory
    }
    void* ptr = &__heap_pool[__heap_pool_offset];
    __heap_pool_offset += size;
    return ptr;
}

void vx_free(void* ptr) {
    // no-op, memory is not actually freed
}


////////////////////////////////////////////////////////////////////////////////
// Simple random number generator for hostless tests
static unsigned rand_state = 1;

void rand_seed(unsigned seed) {
    rand_state = seed;
}

unsigned rand() {
    rand_state = rand_state * 1103515245 + 12345;
    return (rand_state / 65536) % 32768;
}