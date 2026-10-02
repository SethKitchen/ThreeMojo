/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Deterministic libc errors for the coverage runtime regression only.
 */
#define _GNU_SOURCE
#ifndef __APPLE__
#include <dlfcn.h>
#endif
#include <errno.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <unistd.h>

static void catch_signal(int number) { (void)number; }

static ssize_t coverage_test_write(int fd, const void *buffer, size_t count) {
    static unsigned interruptions;
#ifdef __APPLE__
    /* dyld does not interpose references from the image defining the tuple.
     * dlsym(RTLD_NEXT, "write") is different: dyld interposes that lookup too,
     * so it can return coverage_test_write and recurse instead of forwarding.
     */
    ssize_t (*real_write)(int, const void *, size_t) = write;
#else
    ssize_t (*real_write)(int, const void *, size_t) = dlsym(RTLD_NEXT, "write");
    if (!real_write) abort();
#endif
    const char *mode = getenv("THREEMOJO_WRITE_TEST");
    if (fd == 2 && count >= 3 && memcmp(buffer, "COV", 3) == 0 && mode) {
        if (strcmp(mode, "signal") == 0) {
            static int armed;
            if (!armed) {
                struct sigaction action;
                memset(&action, 0, sizeof(action));
                action.sa_handler = catch_signal;
                sigemptyset(&action.sa_mask);
                if (sigaction(SIGUSR1, &action, NULL) != 0) abort();
                armed = 1;
                real_write(1, "READY\n", 6);
            }
            ssize_t result = real_write(fd, buffer, count);
            int saved_errno = errno;
            if (result == -1 && saved_errno == EINTR)
                real_write(1, "INTERRUPTED\n", 12);
            errno = saved_errno;
            return result;
        }
        if (strcmp(mode, "eintr") == 0 && interruptions++ < 3) {
            errno = EINTR;
            return -1;
        }
        if (strcmp(mode, "error") == 0) {
            errno = EIO;
            return -1;
        }
        if (strcmp(mode, "short") == 0) {
            ssize_t result = real_write(fd, buffer, count - 1);
            errno = EINTR; /* A stale errno must not turn this into a retry. */
            return result;
        }
        if (strcmp(mode, "zero") == 0) {
            errno = EINTR;
            return 0;
        }
    }
    return real_write(fd, buffer, count);
}

#ifdef __APPLE__
__attribute__((used)) static struct {
    const void *replacement;
    const void *replacee;
} interpose_write __attribute__((section("__DATA,__interpose"))) = {
    (const void *)coverage_test_write, (const void *)write
};
#else
ssize_t write(int fd, const void *buffer, size_t count) {
    return coverage_test_write(fd, buffer, count);
}
#endif
