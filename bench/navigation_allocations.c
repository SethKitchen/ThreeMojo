/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Linux/ELF, pinned Mojo 1.1.0, single-query-thread allocation measurements.
 * Build: cc -shared -fPIC -O2 bench/navigation_allocations.c -o /tmp/navalloc.so
 * Load with LD_PRELOAD and pass the same library to the budget benchmark.
 * This records Mojo runtime requested bytes, not allocator metadata or RSS.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/syscall.h>

#define SLOTS (1u << 18)
struct allocation { void *pointer; size_t bytes; uint64_t epoch; };
static struct allocation records[SLOTS];
static uint64_t epoch, live, peak, total, calls, overflow;
static _Atomic long owner;
static _Atomic int active;

static int recording(void) { return active && syscall(SYS_gettid) == owner; }
static struct allocation *slot(void *pointer) {
    uintptr_t start = ((uintptr_t)pointer >> 4) & (SLOTS - 1);
    for (uintptr_t i = 0; i < SLOTS; ++i) {
        struct allocation *entry = &records[(start + i) & (SLOTS - 1)];
        if (entry->epoch != epoch || entry->pointer == pointer) return entry;
    }
    overflow = 1;
    return NULL;
}
static void add(void *pointer, size_t bytes) {
    if (!pointer || !recording()) return;
    struct allocation *entry = slot(pointer);
    if (!entry) return;
    entry->pointer = pointer;
    entry->bytes = bytes;
    entry->epoch = epoch;
    live += bytes;
    total += bytes;
    calls += 1;
    if (live > peak) peak = live;
}
static void remove_record(void *pointer) {
    if (!pointer || !recording()) return;
    struct allocation *entry = slot(pointer);
    if (entry && entry->epoch == epoch) {
        live -= entry->bytes;
        entry->bytes = 0;
    }
}
/* The pinned Mojo 1.1.0 runtime uses these allocation entry points.
 * Its TCMalloc backing allocator bypasses glibc malloc interposition.
 * Forward unchanged to the real runtime; measure requested runtime bytes.
 */
void *KGEN_CompilerRT_AlignedAlloc(int64_t alignment, int64_t bytes) {
    typedef void *(*alloc_fn)(int64_t, int64_t);
    static _Atomic(alloc_fn) target;
    alloc_fn function = atomic_load(&target);
    if (!function) {
        function = (alloc_fn)dlsym(RTLD_NEXT, "KGEN_CompilerRT_AlignedAlloc");
        if (!function) abort();
        atomic_store(&target, function);
    }
    void *pointer = function(alignment, bytes);
    add(pointer, (size_t)bytes);
    return pointer;
}
void KGEN_CompilerRT_AlignedFree(void *pointer) {
    typedef void (*free_fn)(void *);
    static _Atomic(free_fn) target;
    free_fn function = atomic_load(&target);
    if (!function) {
        function = (free_fn)dlsym(RTLD_NEXT, "KGEN_CompilerRT_AlignedFree");
        if (!function) abort();
        atomic_store(&target, function);
    }
    remove_record(pointer);
    function(pointer);
}
uint64_t navigation_allocations_begin(void) {
    ++epoch; live=peak=total=calls=overflow=0;
    owner=syscall(SYS_gettid); active=1;
    return 0;
}
uint64_t navigation_allocations_end(void) { active=0; return peak; }
uint64_t navigation_allocations_total(void) { return total; }
uint64_t navigation_allocations_calls(void) { return calls; }
uint64_t navigation_allocations_overflow(void) { return overflow; }

uint64_t navigation_allocations_selftest(void) {
    navigation_allocations_begin();
    void *a = KGEN_CompilerRT_AlignedAlloc(8, 1024);
    void *b = KGEN_CompilerRT_AlignedAlloc(8, 2048);
    KGEN_CompilerRT_AlignedFree(a);
    void *c = KGEN_CompilerRT_AlignedAlloc(8, 4096);
    KGEN_CompilerRT_AlignedFree(b);
    KGEN_CompilerRT_AlignedFree(c);
    uint64_t result = navigation_allocations_end();
    return result == 6144 && live == 0 && total == 7168 && calls == 3 && !overflow;
}
