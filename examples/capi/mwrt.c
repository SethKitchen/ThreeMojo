/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Noncommercial use is free; commercial use requires a paid license.
 * See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
 *
 * A freestanding runtime for Mojo code that was retargeted to wasm32.
 *
 * Mojo 1.1 has no WebAssembly backend, so retarget.py turns the host's LLVM
 * IR into wasm32 IR. That IR still calls the functions that the Mojo runtime
 * and the C library supply on a host. This file supplies them for a
 * browser, in five groups:
 *
 *   1. An allocator. Mojo's `alloc` calls KGEN_CompilerRT_AlignedAlloc, and
 *      both of its arguments are 64 bits wide, because Mojo wrote the IR for
 *      a 64-bit host.
 *   2. The math functions that the host's libm supplies and wasm lacks.
 *   3. The file functions. There is no file system, so each one fails. The
 *      app that reads a file must also work without it.
 *   4. A runtime for TaskGroup. With one thread, a task runs when it is
 *      launched, so `Wait` has nothing to wait for. Compiled with
 *      -DMW_THREADS, the tasks go to a queue that a pool of Web Workers
 *      empties, and `Wait` runs queued tasks until its own are done.
 *   5. The functions that only an abort or a stack trace reaches. They trap
 *      or do nothing.
 *
 * It is a runtime for a module that draws a frame at a time. It is not a
 * general C library.
 */
#include <stddef.h>
#include <stdint.h>

#define PAGE 65536u

/* One lock is a spin on one word. It is used only with threads: a build
 * for one thread has nothing to lock against. */
#ifdef MW_THREADS
static void lock(uint32_t *word) {
  while (__atomic_exchange_n(word, 1, __ATOMIC_ACQUIRE)) {
  }
}
static void unlock(uint32_t *word) { __atomic_store_n(word, 0, __ATOMIC_RELEASE); }
#else
#define lock(word) ((void)(word))
#define unlock(word) ((void)(word))
#endif

/* ---- 1. The allocator ------------------------------------------------- */

/* Memory is a row of blocks from __heap_base to heap_top. Each block starts
 * with a 16-byte header, and its payload follows. Free blocks are joined
 * when they meet. A block that is free sits on a list that runs through its
 * header. */
typedef struct block {
  uint32_t size;      /* the whole block, header included. Bit 0 is "in use". */
  uint32_t before;    /* the size of the block before this one, or 0 */
  uint32_t next_free; /* addresses on the free list, or 0 */
  uint32_t prev_free;
} block;

#define HEADER 16u
#define IN_USE 1u
#define OFFSET_MARK 0xFFFFFFF0u /* a header that points back to a block */

extern unsigned char __heap_base;
static uint32_t heap_lock;
static uint32_t heap_start, heap_top;
static block *last;      /* the block that ends at heap_top */
static block *free_head; /* the free list */

static uint32_t block_size(const block *b) { return b->size & ~IN_USE; }
static int block_free(const block *b) { return !(b->size & IN_USE); }
static block *block_after(const block *b) { return (block *)((uintptr_t)b + block_size(b)); }

static void list_remove(block *b) {
  if (b->prev_free) ((block *)(uintptr_t)b->prev_free)->next_free = b->next_free;
  else free_head = (block *)(uintptr_t)b->next_free;
  if (b->next_free) ((block *)(uintptr_t)b->next_free)->prev_free = b->prev_free;
}

static void list_insert(block *b) {
  b->prev_free = 0;
  b->next_free = (uint32_t)(uintptr_t)free_head;
  if (free_head) free_head->prev_free = (uint32_t)(uintptr_t)b;
  free_head = b;
}

/* Make sure that memory reaches `end`. Returns 0 if it cannot. */
static int reach(uint64_t end) {
  uint64_t have = (uint64_t)__builtin_wasm_memory_size(0) * PAGE;
  if (end > 0xFFFFFFFFu) return 0;
  if (end > have) {
    uint32_t pages = (uint32_t)((end - have + PAGE - 1) / PAGE);
    if (__builtin_wasm_memory_grow(0, pages) == (size_t)-1) return 0;
  }
  return 1;
}

static void *take(uint64_t size) {
  if (heap_start == 0) {
    heap_start = heap_top = ((uint32_t)(uintptr_t)&__heap_base + 15u) & ~15u;
  }
  uint64_t need = ((size + 15u) & ~(uint64_t)15u) + HEADER;
  if (need < 2 * HEADER) need = 2 * HEADER;
  if (need > 0xFFFFFFF0u) return 0;
  for (block *b = free_head; b; b = (block *)(uintptr_t)b->next_free) {
    if (block_size(b) < need) continue;
    list_remove(b);
    uint32_t spare = block_size(b) - (uint32_t)need;
    if (spare >= 2 * HEADER) {
      block *rest = (block *)((uintptr_t)b + need);
      rest->size = spare;
      rest->before = (uint32_t)need;
      block *after = block_after(rest);
      if ((uintptr_t)after < heap_top) after->before = spare;
      else last = rest;
      list_insert(rest);
      b->size = (uint32_t)need;
    }
    b->size |= IN_USE;
    return (char *)b + HEADER;
  }
  /* Nothing fits. A free block at the end can grow into new memory. */
  block *b;
  if (last && block_free(last)) {
    b = last;
    if (!reach((uint64_t)heap_top + (need - block_size(b)))) return 0;
    list_remove(b);
    heap_top += (uint32_t)need - block_size(b);
    b->size = (uint32_t)need;
  } else {
    if (!reach((uint64_t)heap_top + need)) return 0;
    b = (block *)(uintptr_t)heap_top;
    b->before = last ? block_size(last) : 0;
    b->size = (uint32_t)need;
    heap_top += (uint32_t)need;
    last = b;
  }
  b->size |= IN_USE;
  return (char *)b + HEADER;
}

void *KGEN_CompilerRT_AlignedAlloc(uint64_t alignment, uint64_t size) {
  lock(&heap_lock);
  void *result;
  if (alignment <= 16) {
    result = take(size);
  } else {
    /* Take extra, and give back the address that is aligned. A header just
     * before it says where the block starts. */
    char *raw = take(size + alignment + HEADER);
    result = 0;
    if (raw) {
      uintptr_t at = ((uintptr_t)raw + HEADER + alignment - 1) & ~(uintptr_t)(alignment - 1);
      block *mark = (block *)(at - HEADER);
      mark->size = OFFSET_MARK;
      mark->before = (uint32_t)(at - (uintptr_t)raw);
      result = (void *)at;
    }
  }
  unlock(&heap_lock);
  return result;
}

void KGEN_CompilerRT_AlignedFree(void *pointer) {
  if (!pointer) return;
  lock(&heap_lock);
  block *b = (block *)((char *)pointer - HEADER);
  if (b->size == OFFSET_MARK) b = (block *)((char *)pointer - b->before - HEADER);
  b->size &= ~IN_USE;
  block *after = block_after(b);
  if ((uintptr_t)after < heap_top && block_free(after)) {
    list_remove(after);
    b->size += block_size(after);
    block *next = block_after(b);
    if ((uintptr_t)next < heap_top) next->before = block_size(b);
    else last = b;
  }
  if (b->before) {
    block *behind = (block *)((uintptr_t)b - b->before);
    if (block_free(behind)) {
      list_remove(behind);
      behind->size += block_size(b);
      block *next = block_after(behind);
      if ((uintptr_t)next < heap_top) next->before = block_size(behind);
      else last = behind;
      b = behind;
    }
  }
  list_insert(b);
  unlock(&heap_lock);
}

/* ---- 2. Math ---------------------------------------------------------- */

float fmaxf(float a, float b) {
  if (a != a) return b;
  if (b != b) return a;
  return a > b ? a : b;
}
float fminf(float a, float b) {
  if (a != a) return b;
  if (b != b) return a;
  return a < b ? a : b;
}
double fmax(double a, double b) {
  if (a != a) return b;
  if (b != b) return a;
  return a > b ? a : b;
}
double fmin(double a, double b) {
  if (a != a) return b;
  if (b != b) return a;
  return a < b ? a : b;
}

/* a * b + c with one rounding of the product's error: the product is split
 * into two exact halves, so only the sum rounds. */
double fma(double a, double b, double c) {
  const double split = 134217729.0; /* 2^27 + 1 */
  double product = a * b;
  double ta = split * a, ahigh = ta - (ta - a), alow = a - ahigh;
  double tb = split * b, bhigh = tb - (tb - b), blow = b - bhigh;
  double error = ((ahigh * bhigh - product) + ahigh * blow + alow * bhigh) + alow * blow;
  double sum = product + c;
  double virtual_b = sum - product;
  double sum_error = (product - (sum - virtual_b)) + (c - virtual_b);
  return sum + (sum_error + error);
}

/* A float product is exact in a double, so a double sum rounds it once. */
float fmaf(float a, float b, float c) { return (float)((double)a * (double)b + (double)c); }

float hypotf(float x, float y) { return (float)__builtin_sqrt((double)x * (double)x + (double)y * (double)y); }

/* Sine and cosine: reduce to a quarter turn, then the polynomials of
 * fdlibm's __kernel_sin and __kernel_cos. Good to about 1e-16 for arguments
 * up to about a million, which is far past a water clock. */
static const double PIO2_1 = 1.57079632673412561417e+00;
static const double PIO2_2 = 6.07710050630396597660e-11;
static const double PIO2_3 = 2.02226624871116645580e-21;
static const double TWO_OVER_PI = 6.36619772367581382433e-01;

static double kernel_sin(double x) {
  double z = x * x;
  return x + x * z *
                 (-1.66666666666666324348e-01 +
                  z * (8.33333333332248946124e-03 +
                       z * (-1.98412698298579493134e-04 +
                            z * (2.75573137070700676789e-06 +
                                 z * (-2.50507602534068634195e-08 + z * 1.58969099521155010221e-10)))));
}
static double kernel_cos(double x) {
  double z = x * x;
  return 1.0 - 0.5 * z +
         z * z *
             (4.16666666666666019037e-02 +
              z * (-1.38888888888741095749e-03 +
                   z * (2.48015872894767294178e-05 +
                        z * (-2.75573143513906633035e-07 +
                             z * (2.08757232129817482790e-09 + z * -1.13596475577881948265e-11)))));
}

/* Returns the quadrant and puts the remainder in *r. */
static int quarter_turns(double x, double *r) {
  double scaled = x * TWO_OVER_PI;
  double n = (double)(long long)(scaled + (scaled < 0 ? -0.5 : 0.5));
  *r = ((x - n * PIO2_1) - n * PIO2_2) - n * PIO2_3;
  return (int)((long long)n & 3);
}

double sin(double x) {
  if (x != x || x - x != 0) return x - x; /* NaN, or infinite */
  double r;
  switch (quarter_turns(x, &r)) {
    case 0: return kernel_sin(r);
    case 1: return kernel_cos(r);
    case 2: return -kernel_sin(r);
    default: return -kernel_cos(r);
  }
}
double cos(double x) {
  if (x != x || x - x != 0) return x - x;
  double r;
  switch (quarter_turns(x, &r)) {
    case 0: return kernel_cos(r);
    case 1: return -kernel_sin(r);
    case 2: return -kernel_cos(r);
    default: return kernel_sin(r);
  }
}
float sinf(float x) { return (float)sin((double)x); }
float cosf(float x) { return (float)cos((double)x); }
float tanf(float x) { return (float)(sin((double)x) / cos((double)x)); }

/* Arctangent: fdlibm's atan. An argument is brought into [-0.4375, 0.4375] by
 * one of four identities, and a polynomial finishes it. */
static const double ATAN_HIGH[] = {4.63647609000806093515e-01, 7.85398163397448278999e-01,
                                   9.82793723247329054082e-01, 1.57079632679489655800e+00};
static const double ATAN_LOW[] = {2.26987774529616870924e-17, 3.06161699786838301793e-17,
                                  1.39033110312309984516e-17, 6.12323399573676603587e-17};
static const double ATAN_POLY[] = {
    3.33333333333329318027e-01,  -1.99999999998764832476e-01, 1.42857142725034663711e-01,
    -1.11111104054623557880e-01, 9.09088713343650656196e-02,  -7.69187620504482999495e-02,
    6.66107313738753120669e-02,  -5.83357013379057348645e-02, 4.97687799461593236017e-02,
    -3.65315727442169155270e-02, 1.62858201153657823623e-02};
static const double PI = 3.14159265358979311600e+00;
static const double PI_LOW = 1.2246467991473531772e-16;

/* The arctangent of a number that is not negative and not NaN. */
static double atan_positive(double x) {
  if (x > 7.378697629483821e19) return ATAN_HIGH[3] + ATAN_LOW[3]; /* 2^66 */
  int id = -1;
  if (x >= 0.4375) {
    if (x < 1.1875) {
      if (x < 0.6875) {
        id = 0;
        x = (2.0 * x - 1.0) / (2.0 + x);
      } else {
        id = 1;
        x = (x - 1.0) / (x + 1.0);
      }
    } else if (x < 2.4375) {
      id = 2;
      x = (x - 1.5) / (1.0 + 1.5 * x);
    } else {
      id = 3;
      x = -1.0 / x;
    }
  }
  double z = x * x, w = z * z;
  const double *a = ATAN_POLY;
  double s1 = z * (a[0] + w * (a[2] + w * (a[4] + w * (a[6] + w * (a[8] + w * a[10])))));
  double s2 = w * (a[1] + w * (a[3] + w * (a[5] + w * (a[7] + w * a[9]))));
  if (id < 0) return x - x * (s1 + s2);
  return ATAN_HIGH[id] - ((x * (s1 + s2) - ATAN_LOW[id]) - x);
}

static double atan2_double(double y, double x) {
  if (x != x || y != y) return x + y;
  int negative_y = __builtin_signbit(y);
  double sign = negative_y ? -1.0 : 1.0;
  int infinite_x = x - x != 0, infinite_y = y - y != 0;
  if (infinite_y) {
    if (!infinite_x) return sign * 1.57079632679489655800e+00;
    return sign * (x > 0 ? 0.78539816339744827900 : 2.35619449019234483700);
  }
  if (infinite_x) return x > 0 ? sign * 0.0 : sign * PI;
  if (x == 0.0) {
    if (y == 0.0) return __builtin_signbit(x) ? sign * PI : sign * 0.0;
    return sign * 1.57079632679489655800e+00;
  }
  double ratio = y / x;
  double angle = atan_positive(ratio < 0 ? -ratio : ratio);
  if (x > 0) return sign * angle;
  return sign * (PI - (angle - PI_LOW));
}
float atan2f(float y, float x) { return (float)atan2_double((double)y, (double)x); }

/* ---- 3. Files: there are none ----------------------------------------- */

#define ENOENT 2
static int errno_value = ENOENT;
void *__error(void) { return &errno_value; }
char *strerror(int code) {
  (void)code;
  return "No such file or directory";
}
int open(const char *path, int flags, ...) {
  (void)path;
  (void)flags;
  return -1;
}
int close(int fd) {
  (void)fd;
  return -1;
}
uint64_t read(uint64_t fd, void *bytes, uint64_t count) {
  (void)fd;
  (void)bytes;
  (void)count;
  return (uint64_t)-1;
}
int stat(const char *path, void *info) {
  (void)path;
  (void)info;
  return -1;
}
int lstat(const char *path, void *info) {
  (void)path;
  (void)info;
  return -1;
}
int mkdir(const char *path, uint64_t mode) {
  (void)path;
  (void)mode;
  return -1;
}

/* ---- 4. TaskGroup -------------------------------------------------- */

/* Mojo's TaskGroup counts its tasks, runs each one with Execute, and waits
 * on a chain that the last task completes. */
uint64_t KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice(void) { return 1; }
uint64_t KGEN_CompilerRT_AsyncRT_GetCurrentCPUDevice(void) { return 1; }
void KGEN_CompilerRT_AsyncRT_ReleaseCPUDevice(uint64_t device) { (void)device; }

#ifndef MW_THREADS

/* One thread: Execute runs the task before it returns, so every task has
 * finished when Wait is called. */
void KGEN_CompilerRT_AsyncRT_InitializeChain(void *chain) { (void)chain; }
void KGEN_CompilerRT_AsyncRT_Complete(void *chain) { (void)chain; }
void KGEN_CompilerRT_AsyncRT_Wait(void *chain) { (void)chain; }
void KGEN_CompilerRT_AsyncRT_DestroyChain(void *chain) { (void)chain; }
void KGEN_CompilerRT_AsyncRT_Execute(void (*task)(void *), void *context, uint64_t device) {
  (void)device;
  task(context);
}
uint64_t KGEN_CompilerRT_NumLogicalCores(void) { return 1; }

#else

/* Many threads. The module's memory is shared, and each Web Worker runs the
 * same module on it and calls mw_worker_main, which never returns. The tasks
 * wait in a ring. A chain is one word: 0 until the last task completes it. */
typedef struct {
  void (*task)(void *);
  void *context;
} job;

#define QUEUE_SIZE 4096u

static job queue[QUEUE_SIZE];
static uint32_t queue_lock;
static uint32_t queue_head, queue_tail;
static uint32_t queue_signal; /* changes at every push: workers wait on it */
static uint32_t thread_count = 1;

/* Tell the module how many threads there are, the caller's included. Call it
 * before the first frame. */
void mw_set_threads(uint32_t count) { thread_count = count ? count : 1; }

/* Make a stack for a worker, and return its top, where a stack starts. */
void *mw_stack(uint32_t size) {
  char *base = KGEN_CompilerRT_AlignedAlloc(16, size);
  return base ? base + size : 0;
}

static int pop(job *out) {
  int found = 0;
  lock(&queue_lock);
  if (queue_head != queue_tail) {
    *out = queue[queue_head % QUEUE_SIZE];
    queue_head++;
    found = 1;
  }
  unlock(&queue_lock);
  return found;
}

static int push(void (*task)(void *), void *context) {
  int pushed = 0;
  lock(&queue_lock);
  if (queue_tail - queue_head < QUEUE_SIZE) {
    queue[queue_tail % QUEUE_SIZE].task = task;
    queue[queue_tail % QUEUE_SIZE].context = context;
    queue_tail++;
    pushed = 1;
  }
  unlock(&queue_lock);
  return pushed;
}

void KGEN_CompilerRT_AsyncRT_InitializeChain(void *chain) { __atomic_store_n((uint32_t *)chain, 0, __ATOMIC_RELEASE); }
void KGEN_CompilerRT_AsyncRT_Complete(void *chain) { __atomic_store_n((uint32_t *)chain, 1, __ATOMIC_RELEASE); }
void KGEN_CompilerRT_AsyncRT_DestroyChain(void *chain) { (void)chain; }
uint64_t KGEN_CompilerRT_NumLogicalCores(void) { return thread_count; }

void KGEN_CompilerRT_AsyncRT_Execute(void (*task)(void *), void *context, uint64_t device) {
  (void)device;
  /* With one thread, or a full ring, run the task here and now. */
  if (thread_count < 2 || !push(task, context)) {
    task(context);
    return;
  }
  __atomic_add_fetch(&queue_signal, 1, __ATOMIC_RELEASE);
  __builtin_wasm_memory_atomic_notify((int *)&queue_signal, 1);
}

/* The caller runs queued tasks until the chain is done. A page's main thread
 * may not block, so it cannot sleep here, and it is one more thread of work. */
void KGEN_CompilerRT_AsyncRT_Wait(void *chain) {
  job next;
  while (!__atomic_load_n((uint32_t *)chain, __ATOMIC_ACQUIRE)) {
    if (pop(&next)) next.task(next.context);
  }
}

void mw_worker_main(void) {
  job next;
  for (;;) {
    uint32_t seen = __atomic_load_n(&queue_signal, __ATOMIC_ACQUIRE);
    if (pop(&next)) {
      next.task(next.context);
      continue;
    }
    __builtin_wasm_memory_atomic_wait32((int *)&queue_signal, (int)seen, -1);
  }
}

#endif

/* ---- 5. Only an abort or a stack trace gets here ---------------------- */

uint64_t KGEN_CompilerRT_GetOrCreateGlobal(uint64_t name, uint64_t size, void *make, void *drop) {
  (void)name;
  (void)size;
  (void)make;
  (void)drop;
  return 0;
}
uint64_t KGEN_CompilerRT_GetStackTrace(void *frames, uint64_t depth) {
  (void)frames;
  (void)depth;
  return 0;
}
int KGEN_CompilerRT_fprintf(uint64_t stream, const char *format, ...) {
  (void)stream;
  (void)format;
  return 0;
}
uint64_t write(uint64_t fd, const void *bytes, uint64_t count) {
  (void)fd;
  (void)bytes;
  (void)count;
  __builtin_trap();
}
int dup(int fd) {
  (void)fd;
  __builtin_trap();
}
uint64_t fdopen(int fd, const char *mode) {
  (void)fd;
  (void)mode;
  __builtin_trap();
}
int fflush(uint64_t stream) {
  (void)stream;
  __builtin_trap();
}
int fclose(uint64_t stream) {
  (void)stream;
  __builtin_trap();
}
