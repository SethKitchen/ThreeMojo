/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 *
 * A low-current-RSS parent for one benchmark child. Python can have a large
 * resident heap; measuring its immediate child can preserve that pre-exec
 * floor in ru_maxrss. This program first execs into a small address space,
 * then forks the measured child and reports that child's wait4 result only.
 */
#define _DEFAULT_SOURCE 1
#define _DARWIN_C_SOURCE 1
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#if defined(__linux__)
#define RSS_UNIT "KiB"
#define RSS_MULTIPLIER 1024LL
#elif defined(__APPLE__) && defined(__MACH__)
#define RSS_UNIT "bytes"
#define RSS_MULTIPLIER 1LL
#else
#error "Unsupported wait4 ru_maxrss platform; do not guess its units"
#endif

static int fail(const char *operation) {
    fprintf(stderr, "image_decode_rusage: %s: %s\n", operation, strerror(errno));
    return 125;
}

int main(int argc, char **argv) {
    int error_pipe[2];
    if (argc < 3 || strcmp(argv[1], "--") != 0) {
        fprintf(stderr, "Usage: image_decode_rusage -- PROGRAM [ARG ...]\n");
        return 64;
    }
    if (pipe(error_pipe) != 0) return fail("pipe");
    if (fcntl(error_pipe[1], F_SETFD, FD_CLOEXEC) == -1) {
        close(error_pipe[0]);
        close(error_pipe[1]);
        return fail("fcntl");
    }
    pid_t child = fork();
    if (child < 0) {
        close(error_pipe[0]);
        close(error_pipe[1]);
        return fail("fork");
    }
    if (child == 0) {
        close(error_pipe[0]);
        execvp(argv[2], &argv[2]);
        int saved = errno;
        /* An int is smaller than PIPE_BUF; retry only an interrupted write. */
        ssize_t written;
        do {
            written = write(error_pipe[1], &saved, sizeof(saved));
        } while (written < 0 && errno == EINTR);
        (void)written;
        _exit(127);
    }
    close(error_pipe[1]);
    int status = 0;
    struct rusage usage;
    memset(&usage, 0, sizeof(usage));
    pid_t waited;
    do {
        waited = wait4(child, &status, 0, &usage);
    } while (waited < 0 && errno == EINTR);
    if (waited < 0) {
        close(error_pipe[0]);
        return fail("wait4");
    }
    int exec_error = 0;
    ssize_t received;
    do {
        received = read(error_pipe[0], &exec_error, sizeof(exec_error));
    } while (received < 0 && errno == EINTR);
    close(error_pipe[0]);
    if (received < 0) return fail("read exec status");
    if (received != 0 && received != (ssize_t)sizeof(exec_error)) {
        fprintf(stderr, "image_decode_rusage: truncated exec status\n");
        return 125;
    }
    int exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    int child_signal = WIFSIGNALED(status) ? WTERMSIG(status) : 0;
    /* The leading newline separates the marker from an unterminated native
     * stderr line. stdout remains exclusively the measured program's. */
    fprintf(stderr,
        "\nTHREEMOJO_RUSAGE_V1 {\"schema\":1,\"child_pid\":%ld,"
        "\"rss_unit\":\"%s\",\"maxrss_raw\":%lld,\"peak_rss_bytes\":%lld,"
        "\"user_seconds\":%.9f,\"system_seconds\":%.9f,"
        "\"minor_faults\":%ld,\"major_faults\":%ld,"
        "\"voluntary_context_switches\":%ld,\"involuntary_context_switches\":%ld,"
        "\"native_exit_status\":%d,\"native_signal\":%d,\"exec_errno\":%d}\n",
        (long)child, RSS_UNIT, (long long)usage.ru_maxrss,
        (long long)usage.ru_maxrss * RSS_MULTIPLIER,
        (double)usage.ru_utime.tv_sec + (double)usage.ru_utime.tv_usec / 1000000.0,
        (double)usage.ru_stime.tv_sec + (double)usage.ru_stime.tv_usec / 1000000.0,
        usage.ru_minflt, usage.ru_majflt, usage.ru_nvcsw, usage.ru_nivcsw,
        exit_code, child_signal, exec_error);
    fflush(stderr);
    if (child_signal != 0) {
        sigset_t unblocked;
        sigemptyset(&unblocked);
        sigaddset(&unblocked, child_signal);
        sigprocmask(SIG_UNBLOCK, &unblocked, NULL);
        signal(child_signal, SIG_DFL);
        raise(child_signal);
        return 128 + child_signal;
    }
    return exit_code >= 0 ? exit_code : 125;
}
