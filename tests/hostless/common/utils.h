#include <vx_print.h>
#pragma once
#include <vx_intrinsics.h>

////////////////////////////////////////////////////////////////////////////////
// Free-List Based Heap Allocator
////////////////////////////////////////////////////////////////////////////////

#define HEAP_SZ 16384   // 16 KB heap size
#define MIN_BLOCK_SIZE 16  // Minimum allocation size (must be >= sizeof(HeapBlock_t))

// Free block header structure
typedef struct HeapBlock_t {
    unsigned size;              // Size of this block (including header)
    struct HeapBlock_t* next;   // Next free block in the list
} HeapBlock_t;

static char __heap_pool[HEAP_SZ];      // memory pool
static HeapBlock_t* __free_list = nullptr;  // head of free list
static int __heap_initialized = 0;     // initialization flag

// Initialize the heap with one large free block
static void __heap_init() {
    if (__heap_initialized) return;

    __free_list = (HeapBlock_t*)__heap_pool;
    __free_list->size = HEAP_SZ;
    __free_list->next = nullptr;
    __heap_initialized = 1;
}

// Round up size to minimum block size and alignment
static unsigned __heap_block_round_size(unsigned size) {
    // Add header size and round up to minimum block size
    size += sizeof(HeapBlock_t);
    if (size < MIN_BLOCK_SIZE) {
        size = MIN_BLOCK_SIZE;
    }
    // Align to 8-byte boundary for better performance
    return (size + 7) & ~7;
}

// Split a free block if it's large enough
static void __heap_block_split(HeapBlock_t* block, unsigned size) {
    if (block->size >= size + MIN_BLOCK_SIZE) {
        // Create new free block from remainder
        HeapBlock_t* new_block = (HeapBlock_t*)((char*)block + size);
        new_block->size = block->size - size;
        new_block->next = block->next;
        
        // Update current block
        block->size = size;
        block->next = new_block;
    }
}

// Allocate memory from heap
void* vx_malloc(unsigned size) {
    if (size == 0) return nullptr;

    __heap_init();

    size = __heap_block_round_size(size);

    // Find first fit in free list
    HeapBlock_t** current = &__free_list;
    while (*current != nullptr) {
        if ((*current)->size >= size) {
            HeapBlock_t* block = *current;

            // Split block if it's much larger than needed
            __heap_block_split(block, size);
            
            // Remove from free list
            *current = block->next;
            
            // Return pointer past the header
            return (char*)block + sizeof(HeapBlock_t);
        }
        current = &((*current)->next);
    }
    
    vx_printf("HEAP: Out of memory (requested %u bytes)\n", size);
    return nullptr;
}

// Coalesce adjacent free blocks
static HeapBlock_t* __heap_block_coalesce(HeapBlock_t* block) {
    // Check if we can merge with next block
    char* block_end = (char*)block + block->size;
    if (block->next && (char*)block->next == block_end) {
        block->size += block->next->size;
        block->next = block->next->next;
    }
    
    // Check if previous block can merge with us
    HeapBlock_t** prev = &__free_list;
    while (*prev && *prev != block) {
        char* prev_end = (char*)*prev + (*prev)->size;
        if (prev_end == (char*)block) {
            // Merge previous block with current
            (*prev)->size += block->size;
            (*prev)->next = block->next;
            return *prev;
        }
        prev = &((*prev)->next);
    }
    
    return block;
}

// Free memory back to heap
void vx_free(void* ptr) {
    if (ptr == nullptr) return;
    
    // Get block header
    HeapBlock_t* block = (HeapBlock_t*)((char*)ptr - sizeof(HeapBlock_t));
    
    // Insert into free list (sorted by address for easier coalescing)
    HeapBlock_t** current = &__free_list;
    while (*current && *current < block) {
        current = &((*current)->next);
    }
    
    block->next = *current;
    *current = block;
    
    // Coalesce adjacent blocks
    __heap_block_coalesce(block);
}

// Debug function to print heap statistics
void vx_heap_stats() {
    __heap_init();
    
    unsigned total_free = 0;
    unsigned num_blocks = 0;
    HeapBlock_t* current = __free_list;

    vx_printf("HEAP STATS:\n");
    while (current) {
        vx_printf("  Free block at %p: %u bytes\n", current, current->size);
        total_free += current->size;
        num_blocks++;
        current = current->next;
    }

    vx_printf("  Total free: %u/%u bytes (%d blocks): %d%%\n", 
              total_free, HEAP_SZ, num_blocks, (total_free * 100) / HEAP_SZ);
    vx_printf("  Total used: %u bytes\n", HEAP_SZ - total_free);
}


////////////////////////////////////////////////////////////////////////////////
// Simple random number generator
////////////////////////////////////////////////////////////////////////////////
static unsigned __vx_rand_state = 1;

#define RAND_MAX 32767

void vx_rand_seed(unsigned seed) {
    __vx_rand_state = seed;
}

unsigned vx_rand() {
    __vx_rand_state = __vx_rand_state * 1103515245 + 12345;
    return (__vx_rand_state / 65536) % 32768;
}


////////////////////////////////////////////////////////////////////////////////
// Simple software global barrier implementation
////////////////////////////////////////////////////////////////////////////////
#define MAX_CORES 8 // Set this to the max number of cores in your system
volatile int g_barrier_sense = 0;
volatile int g_core_sense[MAX_CORES] = {0};

void vx_global_barrier() {
    int core_id = vx_core_id();
    int num_cores = vx_num_cores();

    // Use the next sense value for this barrier instance
    int current_sense = g_barrier_sense + 1;

    // 1. Arrival Phase: This core signals its arrival
    g_core_sense[core_id] = current_sense;
    vx_fence(); // Ensure the write is visible to other cores

    // 2. Wait Phase
    if (core_id == 0) {
        // Core 0 is the master: it waits for ALL cores to arrive
        for (int i = 0; i < num_cores; ++i) {
            while (g_core_sense[i] != current_sense) {
                // Spin...
                asm volatile("");
            }
        }
        // 3. Release Phase: Core 0 signals release
        g_barrier_sense = current_sense;
        vx_fence(); // Ensure the release signal is visible
    } else {
        // Worker cores wait for the release signal from Core 0
        while (g_barrier_sense != current_sense) {
            // Spin...
            asm volatile("");
        }
    }
}