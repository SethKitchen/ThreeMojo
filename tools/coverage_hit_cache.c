/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Opt-in private probe transport. Complete evaluations are never cached.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define HIT_BYTES 512
#define HIT_SLOTS 4096
#if ATOMIC_INT_LOCK_FREE != 2
#error "coverage hit cache requires lock-free atomic integers"
#endif

struct hit_slot {
    atomic_uint busy;
    size_t size;
    unsigned char bytes[HIT_BYTES];
};

/* Atomics are initialized before any caller can enter the library. Cache
 * memory is fixed and never allocated per thread. */
static struct hit_slot slots[HIT_SLOTS];
static pid_t owner;
static dev_t pipe_device;
static ino_t pipe_inode;
static int enabled;
static int probe_sink = -1;

static void child_after_fork(void) {
    /* No locks or allocation in this callback. A fork child cannot retain a
     * hidden writer after redirecting stderr. Its probes use raw fd2 instead. */
    if (probe_sink >= 0)
        close(probe_sink);
    probe_sink = -1;
    enabled = 0;
}

__attribute__((constructor)) static void initialize_hit_cache(void) {
    int saved_errno = errno;
    const char *device = getenv("THREEMOJO_COVERAGE_PIPE_DEVICE");
    const char *inode = getenv("THREEMOJO_COVERAGE_PIPE_INODE");
    struct stat sink;
    owner = getpid();
    for (size_t i = 0; i < HIT_SLOTS; ++i)
        atomic_init(&slots[i].busy, 0);
    if (device && inode && fstat(2, &sink) == 0 && S_ISFIFO(sink.st_mode)) {
        char *device_end, *inode_end;
        errno = 0;
        unsigned long long expected_device = strtoull(device, &device_end, 10);
        unsigned long long expected_inode = strtoull(inode, &inode_end, 10);
        if (!errno && *device && *inode && !*device_end && !*inode_end &&
            expected_device == (unsigned long long)sink.st_dev &&
            expected_inode == (unsigned long long)sink.st_ino) {
            /* A separate open-file description keeps the private probe sink
             * blocking even if the program changes fd2's descriptor flags.
             * The wrapper loads this library before running any suite code. */
            int writer = open("/proc/self/fd/2", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
            struct stat opened;
            if (writer >= 0 && fstat(writer, &opened) == 0 &&
                S_ISFIFO(opened.st_mode) && opened.st_dev == sink.st_dev &&
                opened.st_ino == sink.st_ino &&
                fcntl(writer, F_SETFL, O_WRONLY) == 0 &&
                pthread_atfork(NULL, NULL, child_after_fork) == 0) {
                pipe_device = sink.st_dev;
                pipe_inode = sink.st_ino;
                probe_sink = writer;
                enabled = 1;
            } else if (writer >= 0) {
                close(writer);
            }
        }
    }
    /* A requested private transport must not silently lose probes through a
     * later fd2 redirection if initialization failed. */
    if ((device || inode) && !enabled)
        abort();
    errno = saved_errno;
}

__attribute__((destructor)) static void close_hit_cache(void) {
    if (getpid() == owner && probe_sink >= 0)
        close(probe_sink);
}

static void write_record(int descriptor, const unsigned char *bytes, size_t size) {
    for (;;) {
        ssize_t written = write(descriptor, bytes, size);
        if (written == (ssize_t)size)
            return;
        if (written != -1 || errno != EINTR)
            abort();
    }
}

static void require_private_sink(void) {
    struct stat sink;
    int flags = fcntl(probe_sink, F_GETFL);
    if (flags == -1 || (flags & O_ACCMODE) == O_RDONLY || (flags & O_NONBLOCK) ||
        fstat(probe_sink, &sink) != 0 || !S_ISFIFO(sink.st_mode) ||
        sink.st_dev != pipe_device || sink.st_ino != pipe_inode)
        abort();
}

/* This export has exactly one maintained caller: coverage.runtime._emit_hit.
 * Opted-in probes use the fixed private writer; ordinary diagnostics retain
 * fd2. The collector owns the pipe reader until process reaping. */
int threemojo_coverage_emit_hit(const unsigned char *bytes, size_t size, int entered_errno) {
    if (size > HIT_BYTES)
        abort();
    if (!enabled || getpid() != owner) {
        errno = entered_errno;
        write_record(2, bytes, size);
        return errno;
    }
    uint64_t hash = UINT64_C(14695981039346656037);
    for (size_t i = 0; i < size; ++i) {
        hash ^= bytes[i];
        hash *= UINT64_C(1099511628211);
    }
    struct hit_slot *slot = &slots[hash % HIT_SLOTS];
    if (!atomic_exchange_explicit(&slot->busy, 1, memory_order_acquire)) {
        int found = slot->size == size && size != 0 &&
            memcmp(slot->bytes, bytes, size) == 0;
        atomic_store_explicit(&slot->busy, 0, memory_order_release);
        if (found) {
            errno = entered_errno;
            return entered_errno;
        }
    }
    /* Only genuinely new evidence needs another sink operation. A cache hit
     * above denotes bytes already delivered to this same immutable capture. */
    require_private_sink();
    struct pollfd readiness = {probe_sink, POLLOUT, 0};
    int cacheable = poll(&readiness, 1, 0) >= 0 &&
        !(readiness.revents & (POLLERR | POLLHUP | POLLNVAL));
    errno = entered_errno;
    write_record(probe_sink, bytes, size);
    int written_errno = errno;
    /* Publish only after a complete successful write to this fixed sink.
     * A busy slot, collision, eviction or race can only produce duplicates. */
    if (cacheable && !atomic_exchange_explicit(&slot->busy, 1, memory_order_acquire)) {
        memcpy(slot->bytes, bytes, size);
        slot->size = size;
        atomic_store_explicit(&slot->busy, 0, memory_order_release);
    }
    errno = written_errno;
    return written_errno;
}

/* Complete evaluations are always written. No vector is sampled or cached. */
int threemojo_coverage_emit_evaluation(const unsigned char *bytes, size_t size, int entered_errno) {
    if (size > HIT_BYTES)
        abort();
    int descriptor = 2;
    if (enabled && getpid() == owner) {
        require_private_sink();
        descriptor = probe_sink;
    }
    errno = entered_errno;
    write_record(descriptor, bytes, size);
    return errno;
}
