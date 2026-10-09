/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0 */
/* Source-inclusion harness for the exact private transport implementation.
 * This is test evidence, not production code. The driver supplies its path.
 * All operating-system effects are replaced with deterministic local fakes.
 */
#define _GNU_SOURCE
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef TRANSPORT_SOURCE
#error "Define TRANSPORT_SOURCE to the exact coverage_hit_cache.c path"
#endif

static char *fake_getenv(const char *name);
static pid_t fake_getpid(void);
static int fake_open(const char *path, int flags, ...);
static int fake_close(int descriptor);
static int fake_fstat(int descriptor, struct stat *value);
static int fake_fcntl(int descriptor, int command, ...);
static int fake_poll(struct pollfd *descriptors, nfds_t count, int timeout);
static int fake_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void));
static ssize_t fake_write(int descriptor, const void *bytes, size_t size);
static void fake_abort(void) __attribute__((noreturn));

/* System headers are already included. Only disable the production startup
 * attributes so each test can invoke/reset initialization explicitly. */
#define __attribute__(...)
#define getenv fake_getenv
#define getpid fake_getpid
#define open fake_open
#define close fake_close
#define fstat fake_fstat
#define fcntl fake_fcntl
#define poll fake_poll
#define pthread_atfork fake_atfork
#define write fake_write
#define abort fake_abort
#include TRANSPORT_SOURCE
#undef __attribute__
#undef getenv
#undef getpid
#undef open
#undef close
#undef fstat
#undef fcntl
#undef poll
#undef pthread_atfork
#undef write
#undef abort

enum { PRIVATE_FD = 91, MAX_CALLS = 32, MAX_CAPTURE = 16384 };
enum outcome { FULL, INTERRUPTED, SHORT, ZERO, IO_ERROR };
static const char *device_text, *inode_text, *fault;
static pid_t fake_pid;
static int private_open, opened_flags, private_flags, closes, aborts;
static unsigned fstats, fcntls, polls, pids;
static int close_errno;
static int poll_result, poll_error;
static short poll_events;
static void (*prepare_handler)(void), (*parent_handler)(void), (*child_handler)(void);
static jmp_buf fatal;
static int fatal_armed;
static enum outcome outcomes[MAX_CALLS];
static unsigned planned, calls;
static struct {
    int descriptor;
    size_t size;
    unsigned char bytes[HIT_BYTES];
    enum outcome outcome;
} attempts[MAX_CALLS];
static unsigned char captured[MAX_CAPTURE];
static size_t captured_size;
static int expect_uncached_write;
static unsigned assertions_run;

static int fault_is(const char *name) { return strcmp(fault, name) == 0; }

static struct hit_slot *record_slot(const unsigned char *bytes, size_t size) {
    uint64_t hash = UINT64_C(14695981039346656037);
    for (size_t i = 0; i < size; ++i) {
        hash ^= bytes[i];
        hash *= UINT64_C(1099511628211);
    }
    return &slots[hash % HIT_SLOTS];
}

static int cached(const unsigned char *bytes, size_t size) {
    struct hit_slot *slot = record_slot(bytes, size);
    return size != 0 && slot->size == size && memcmp(slot->bytes, bytes, size) == 0;
}

static char *fake_getenv(const char *name) {
    if (!strcmp(name, "THREEMOJO_COVERAGE_PIPE_DEVICE")) return (char *)device_text;
    assert(!strcmp(name, "THREEMOJO_COVERAGE_PIPE_INODE"));
    return (char *)inode_text;
}

static pid_t fake_getpid(void) { ++pids; return fake_pid; }

static int fake_open(const char *path, int flags, ...) {
    assert(!strcmp(path, "/proc/self/fd/2"));
    opened_flags = flags;
    if (fault_is("open-emfile") || fault_is("open-enxio")) {
        errno = fault_is("open-emfile") ? EMFILE : ENXIO;
        return -1;
    }
    private_open = 1;
    private_flags = flags & ~O_CLOEXEC;
    return PRIVATE_FD;
}

static int fake_close(int descriptor) {
    assert(descriptor == PRIVATE_FD);
    assert(private_open);
    private_open = 0;
    ++closes;
    if (close_errno) errno = close_errno;
    return 0;
}

static int fake_fstat(int descriptor, struct stat *value) {
    ++fstats;
    assert(descriptor == 2 || descriptor == PRIVATE_FD);
    if ((descriptor == 2 && fault_is("stderr-stat")) ||
        (descriptor == PRIVATE_FD && fault_is("private-stat"))) {
        errno = EIO;
        return -1;
    }
    memset(value, 0, sizeof(*value));
    value->st_mode = S_IFIFO | 0600;
    value->st_dev = 17;
    value->st_ino = 23;
    if (descriptor == 2 && fault_is("stderr-regular")) value->st_mode = S_IFREG | 0600;
    if (descriptor == PRIVATE_FD && fault_is("private-regular")) value->st_mode = S_IFREG | 0600;
    if (descriptor == PRIVATE_FD && fault_is("private-identity")) value->st_ino = 24;
    return 0;
}

static int fake_fcntl(int descriptor, int command, ...) {
    ++fcntls;
    assert(descriptor == PRIVATE_FD);
    if (command == F_SETFL) {
        va_list arguments;
        va_start(arguments, command);
        int flags = va_arg(arguments, int);
        va_end(arguments);
        assert(flags == O_WRONLY);
        if (fault_is("setfl")) { errno = EIO; return -1; }
        private_flags = flags;
        return 0;
    }
    assert(command == F_GETFL);
    if (!private_open || fault_is("getfl")) { errno = EBADF; return -1; }
    return private_flags;
}

static int fake_poll(struct pollfd *descriptors, nfds_t count, int timeout) {
    ++polls;
    assert(count == 1 && timeout == 0 && descriptors[0].fd == PRIVATE_FD);
    assert(descriptors[0].events == POLLOUT);
    descriptors[0].revents = poll_events;
    if (poll_result < 0) errno = poll_error;
    return poll_result;
}

static int fake_atfork(void (*prepare)(void), void (*parent)(void), void (*child)(void)) {
    assert(prepare && parent && child);
    if (fault_is("atfork")) return ENOMEM;
    prepare_handler = prepare;
    parent_handler = parent;
    child_handler = child;
    return 0;
}

static ssize_t fake_write(int descriptor, const void *bytes, size_t size) {
    assert(calls < MAX_CALLS && size <= HIT_BYTES);
    if (expect_uncached_write) assert(!cached(bytes, size));
    enum outcome outcome = calls < planned ? outcomes[calls] : FULL;
    attempts[calls].descriptor = descriptor;
    attempts[calls].size = size;
    attempts[calls].outcome = outcome;
    memcpy(attempts[calls].bytes, bytes, size);
    ++calls;
    if (outcome == INTERRUPTED) { errno = EINTR; return -1; }
    if (outcome == IO_ERROR) { errno = EIO; return -1; }
    if (outcome == ZERO) { errno = EINTR; return 0; }
    size_t delivered = outcome == SHORT ? size - 1 : size;
    assert(captured_size + delivered <= MAX_CAPTURE);
    memcpy(captured + captured_size, bytes, delivered);
    captured_size += delivered;
    if (outcome == SHORT) errno = EINTR; /* Stale errno must not retry. */
    return (ssize_t)delivered;
}

static void fake_abort(void) {
    ++aborts;
    if (!fatal_armed) {
        fputs("Unexpected transport abort\n", stderr);
        exit(99);
    }
    longjmp(fatal, 1);
}

static void reset(void) {
    memset(slots, 0, sizeof(slots));
    owner = 0; pipe_device = 0; pipe_inode = 0; enabled = 0; probe_sink = -1;
    atomic_store(&forks_in_flight, 0);
    device_text = "17"; inode_text = "23"; fault = "none"; fake_pid = 1001;
    private_open = opened_flags = private_flags = closes = aborts = 0;
    fstats = fcntls = polls = pids = 0; close_errno = 0;
    prepare_handler = parent_handler = child_handler = NULL; fatal_armed = 0;
    poll_result = 1; poll_error = 0; poll_events = POLLOUT;
    planned = calls = 0; captured_size = 0; expect_uncached_write = 0;
    memset(attempts, 0, sizeof(attempts));
    memset(captured, 0, sizeof(captured));
}

static void initialize(void) {
    errno = ENOENT;
    initialize_hit_cache();
    assert(errno == ENOENT && enabled && probe_sink == PRIVATE_FD &&
           prepare_handler && parent_handler && child_handler);
    assert(opened_flags == (O_WRONLY | O_NONBLOCK | O_CLOEXEC));
    assert(private_flags == O_WRONLY);
}

static int hit_text(const char *text) {
    return threemojo_coverage_emit_hit((const unsigned char *)text, strlen(text), ENOENT);
}

static int evaluation_text(const char *text) {
    return threemojo_coverage_emit_evaluation((const unsigned char *)text, strlen(text), ENOENT);
}

/* Keep setjmp out of the case loops. The recovery frame owns no changing
 * automatic state, so a trapped abort cannot make a loop index indeterminate.
 * The caller's assertions still inspect the exact state at the abort. */
__attribute__((noinline)) static void expect_initialization_abort(void) {
    fatal_armed = 1;
    if (setjmp(fatal) == 0) {
        initialize_hit_cache();
        assert(!"Expected abort did not occur");
    }
    fatal_armed = 0;
    assert(aborts == 1);
}

__attribute__((noinline)) static void expect_record_abort(int evaluation, const char *record) {
    fatal_armed = 1;
    if (setjmp(fatal) == 0) {
        if (evaluation)
            (void)evaluation_text(record);
        else
            (void)hit_text(record);
        assert(!"Expected abort did not occur");
    }
    fatal_armed = 0;
    assert(aborts == 1);
}

static void startup_cases(void) {
    const char *failures[] = {"stderr-stat", "stderr-regular", "open-emfile", "open-enxio",
        "private-stat", "private-regular", "private-identity", "setfl", "atfork"};
    for (size_t i = 0; i < sizeof(failures) / sizeof(failures[0]); ++i) {
        reset(); fault = failures[i];
        expect_initialization_abort();
        assert(!enabled && probe_sink == -1 && !private_open && calls == 0);
        assert(closes == (i >= 4));
        ++assertions_run;
    }
    const char *identities[][2] = {{NULL,"23"}, {"17",NULL}, {"","23"},
        {"17",""}, {"junk","23"}, {"17","junk"}, {"18","23"}, {"17","24"},
        {"18446744073709551616","23"}, {"17","18446744073709551616"}};
    for (size_t i = 0; i < sizeof(identities) / sizeof(identities[0]); ++i) {
        reset(); device_text = identities[i][0]; inode_text = identities[i][1];
        expect_initialization_abort();
        assert(!enabled && probe_sink == -1 && !private_open && calls == 0);
        ++assertions_run;
    }
    reset(); device_text = inode_text = NULL; errno = ENOENT;
    initialize_hit_cache();
    assert(!enabled && errno == ENOENT && !private_open);
    assert(hit_text("COVLINE:raw:1\n") == ENOENT);
    assert(hit_text("COVLINE:raw:1\n") == ENOENT);
    assert(calls == 2 && attempts[0].descriptor == 2 && attempts[1].descriptor == 2);
    ++assertions_run;
}

static void write_cases(void) {
    const char *hit = "COVLINE:fault:1\n";
    const char *vector = "COVEVAL2:fault:2:T:TT;\n";
    for (unsigned evaluation = 0; evaluation < 2; ++evaluation) {
        const char *record = evaluation ? vector : hit;
        reset(); initialize(); expect_uncached_write = 1;
        outcomes[0] = outcomes[1] = outcomes[2] = INTERRUPTED; outcomes[3] = FULL; planned = 4;
        int returned = evaluation ? evaluation_text(record) : hit_text(record);
        assert(returned == EINTR && errno == EINTR && calls == 4 && captured_size == strlen(record));
        assert(!memcmp(captured, record, strlen(record)));
        for (unsigned i = 0; i < calls; ++i) {
            assert(attempts[i].descriptor == PRIVATE_FD && attempts[i].size == strlen(record));
            assert(!memcmp(attempts[i].bytes, record, strlen(record)));
        }
        assert(cached((const unsigned char *)record, strlen(record)) == !evaluation);
        expect_uncached_write = 0;
        assert((evaluation ? evaluation_text(record) : hit_text(record)) == ENOENT);
        assert(calls == (evaluation ? 5u : 4u));
        ++assertions_run;
        const enum outcome failures[] = {SHORT, ZERO, IO_ERROR};
        for (unsigned i = 0; i < 3; ++i) {
            reset(); initialize(); expect_uncached_write = 1;
            outcomes[0] = failures[i]; planned = 1;
            expect_record_abort((int)evaluation, record);
            assert(calls == 1 && captured_size == (failures[i] == SHORT ? strlen(record) - 1 : 0));
            assert(!cached((const unsigned char *)record, strlen(record)));
            assert(record_slot((const unsigned char *)record, strlen(record))->size == 0);
            assert(atomic_load(&record_slot((const unsigned char *)record, strlen(record))->busy) == 0);
            /* A trapped abort is test-only. A real process cannot resume. Here
             * resumption proves a failed write did not pre-publish its key. */
            expect_uncached_write = 1;
            assert((evaluation ? evaluation_text(record) : hit_text(record)) == ENOENT);
            assert(calls == 2);
            ++assertions_run;
        }
    }
}

static void order_collision_and_poll_cases(void) {
    const char *a = "COVLINE:collision:9\n", *b = "COVLINE:collision:294\n";
    const char *vector = "COVEVAL2:ordered:2:T:TT;\n";
    assert(record_slot((const unsigned char *)a, strlen(a)) == record_slot((const unsigned char *)b, strlen(b)));
    reset(); initialize();
    hit_text(a); hit_text(a); evaluation_text(vector); hit_text(b); hit_text(b); evaluation_text(vector); hit_text(a);
    char expected[512];
    int length = snprintf(expected, sizeof(expected), "%s%s%s%s%s", a, vector, b, vector, a);
    assert(length > 0 && captured_size == (size_t)length && !memcmp(captured, expected, captured_size));
    assert(calls == 5); ++assertions_run;

    for (unsigned i = 0; i < 3; ++i) {
        reset(); initialize(); hit_text(a);
        outcomes[1] = (enum outcome[]){SHORT, ZERO, IO_ERROR}[i]; planned = 2;
        expect_record_abort(0, b);
        assert(cached((const unsigned char *)a, strlen(a)) && !cached((const unsigned char *)b, strlen(b)));
        assert(calls == 2); ++assertions_run;
    }
    reset(); initialize();
    struct hit_slot *slot = record_slot((const unsigned char *)a, strlen(a));
    atomic_store(&slot->busy, 1);
    hit_text(a); hit_text(a);
    assert(calls == 2 && slot->size == 0 && atomic_load(&slot->busy) == 1);
    atomic_store(&slot->busy, 0);
    hit_text(a); hit_text(a);
    assert(calls == 3 && cached((const unsigned char *)a, strlen(a))); ++assertions_run;

    const short poll_faults[] = {POLLERR, POLLHUP, POLLNVAL};
    for (unsigned i = 0; i < 4; ++i) {
        reset(); initialize();
        if (i == 3) { poll_result = -1; poll_error = EINTR; }
        else poll_events = poll_faults[i];
        assert(hit_text(a) == ENOENT && hit_text(a) == ENOENT);
        assert(calls == 2 && !cached((const unsigned char *)a, strlen(a))); ++assertions_run;
    }
    reset(); initialize(); poll_result = 0; poll_events = 0;
    hit_text(a); hit_text(a);
    assert(calls == 1 && cached((const unsigned char *)a, strlen(a))); ++assertions_run;
}

static void ownership_cases(void) {
    const char *a = "COVLINE:owner:1\n", *b = "COVLINE:owner:2\n";
    reset(); initialize(); hit_text(a);
    unsigned old_fstats = fstats, old_fcntls = fcntls, old_polls = polls;
    private_open = 0;
    assert(hit_text(a) == ENOENT && calls == 1);
    assert(fstats == old_fstats && fcntls == old_fcntls && polls == old_polls);
    expect_record_abort(0, b);
    assert(calls == 1 && !cached((const unsigned char *)b, strlen(b))); ++assertions_run;

    reset(); initialize(); hit_text(a);
    fake_pid = 1002; child_handler();
    assert(!enabled && probe_sink == -1 && !private_open && closes == 1);
    hit_text(a); hit_text(a);
    assert(calls == 3 && attempts[1].descriptor == 2 && attempts[2].descriptor == 2);
    close_hit_cache(); assert(closes == 1); ++assertions_run;

    reset(); initialize(); close_hit_cache();
    assert(closes == 1 && !private_open); ++assertions_run;
}

__attribute__((noinline)) static void expect_callback_abort(void (*callback)(void)) {
    fatal_armed = 1;
    if (setjmp(fatal) == 0) {
        callback();
        assert(!"Expected callback abort did not occur");
    }
    fatal_armed = 0;
    assert(aborts == 1);
}

static void fork_transition_cases(void) {
    const char *a = "COVLINE:fork:1\n", *b = "COVLINE:fork:2\n";
    const char *vector = "COVEVAL2:fork:3:T:TT;\n";

    /* The ordinary path still writes every vector and does no PID lookup. */
    reset(); initialize(); unsigned initial_pids = pids;
    hit_text(a); hit_text(a); evaluation_text(vector); evaluation_text(vector);
    assert(pids == initial_pids && calls == 3);
    assert(attempts[0].descriptor == PRIVATE_FD && attempts[1].descriptor == PRIVATE_FD);
    ++assertions_run;

    /* Earlier/later parent callbacks retain private routing and caching. */
    reset(); initialize(); hit_text(a); initial_pids = pids;
    errno = EBUSY; prepare_handler();
    assert(errno == EBUSY && atomic_load(&forks_in_flight) == 1);
    hit_text(a); evaluation_text(vector);
    assert(calls == 2 && pids == initial_pids + 2 && attempts[1].descriptor == PRIVATE_FD);
    errno = EAGAIN; parent_handler();
    assert(errno == EAGAIN && atomic_load(&forks_in_flight) == 0);
    initial_pids = pids; hit_text(a);
    assert(calls == 2 && pids == initial_pids);
    ++assertions_run;

    /* A child callback registered earlier than ours sees no inherited hits. */
    reset(); initialize(); hit_text(a); prepare_handler(); fake_pid = 1002;
    hit_text(a); hit_text(a); hit_text(b); evaluation_text(vector);
    assert(calls == 5 && private_open && enabled);
    for (unsigned i = 1; i < calls; ++i) assert(attempts[i].descriptor == 2);
    assert(!cached((const unsigned char *)b, strlen(b)));
    close_errno = EINTR; errno = ENOENT; child_handler();
    assert(errno == ENOENT && !enabled && probe_sink == -1 && !private_open && closes == 1);
    initial_pids = pids; hit_text(a); evaluation_text(vector);
    assert(pids == initial_pids && calls == 7 && attempts[6].descriptor == 2);
    ++assertions_run;

    /* Out-of-order parent completions cannot clear another outstanding fork. */
    reset(); initialize(); hit_text(a); prepare_handler(); prepare_handler();
    assert(atomic_load(&forks_in_flight) == 2);
    parent_handler(); assert(atomic_load(&forks_in_flight) == 1);
    initial_pids = pids; hit_text(a); assert(pids == initial_pids + 1 && calls == 1);
    parent_handler(); assert(atomic_load(&forks_in_flight) == 0);
    initial_pids = pids; hit_text(a); assert(pids == initial_pids && calls == 1);
    ++assertions_run;

    /* A child of the still-pending fork inherits a positive count. */
    reset(); initialize(); hit_text(a); prepare_handler(); prepare_handler(); parent_handler();
    fake_pid = 1002; hit_text(a); evaluation_text(vector);
    assert(calls == 3 && attempts[1].descriptor == 2 && attempts[2].descriptor == 2);
    child_handler(); assert(!enabled && closes == 1);
    ++assertions_run;

    /* A nested failure in an earlier child callback leaves its outer guard. */
    reset(); initialize(); hit_text(a); prepare_handler(); fake_pid = 1002;
    prepare_handler(); errno = EAGAIN; parent_handler();
    assert(errno == EAGAIN && atomic_load(&forks_in_flight) == 1);
    hit_text(a); assert(calls == 2 && attempts[1].descriptor == 2);
    child_handler(); assert(!enabled && closes == 1);
    ++assertions_run;

    /* A nested successful fork also stays raw before either child hook. */
    reset(); initialize(); hit_text(a); prepare_handler(); fake_pid = 1002;
    prepare_handler(); fake_pid = 1003; hit_text(a); evaluation_text(vector);
    assert(atomic_load(&forks_in_flight) == 2 && calls == 3);
    assert(attempts[1].descriptor == 2 && attempts[2].descriptor == 2);
    child_handler(); assert(!enabled && closes == 1);
    ++assertions_run;

    /* Failed fork returns through the parent handler without changing errno. */
    reset(); initialize(); hit_text(a); prepare_handler(); errno = ENOMEM; parent_handler();
    assert(errno == ENOMEM && atomic_load(&forks_in_flight) == 0);
    initial_pids = pids; hit_text(a); assert(calls == 1 && pids == initial_pids);
    ++assertions_run;

    /* Overflow never publishes zero, and underflow never wraps. */
    reset(); initialize(); atomic_store(&forks_in_flight, UINT_MAX);
    expect_callback_abort(prepare_handler);
    assert(atomic_load(&forks_in_flight) == UINT_MAX);
    ++assertions_run;
    reset(); initialize(); expect_callback_abort(parent_handler);
    assert(atomic_load(&forks_in_flight) == 0);
    ++assertions_run;
}

static void *overlap_worker(void *argument) {
    int expected_errno = *(int *)argument;
    for (unsigned i = 0; i < 10000; ++i) {
        errno = expected_errno; before_fork();
        assert(errno == expected_errno);
        after_parent_fork(); assert(errno == expected_errno);
    }
    return NULL;
}

static void concurrent_transition_case(void) {
    reset(); initialize();
    pthread_t workers[4]; int codes[4] = {ENOENT, EAGAIN, ENOMEM, EBUSY};
    for (unsigned i = 0; i < 4; ++i) assert(!pthread_create(&workers[i], NULL, overlap_worker, &codes[i]));
    for (unsigned i = 0; i < 4; ++i) assert(!pthread_join(workers[i], NULL));
    assert(atomic_load(&forks_in_flight) == 0);
    ++assertions_run;
}

int main(void) {
    startup_cases();
    write_cases();
    order_collision_and_poll_cases();
    ownership_cases();
    fork_transition_cases();
    concurrent_transition_case();
    printf("PASS %u deterministic transport cases\n", assertions_run);
    return 0;
}
