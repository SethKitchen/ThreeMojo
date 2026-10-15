# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Start, watch, signal and stop a child in its own session, through libc.

The compiler diagnostics in `tools/compiler_telemetry.mojo` and
`tools/compiler_metadata.mojo` own one child each. They must keep its exit
status, send a signal to its whole process group, and see a cancellation
signal that arrives while they wait. `std.subprocess` does none of these, so
this module calls the POSIX functions with `external_call`. It works on
Linux and on macOS.

Signals: a Mojo program starts worker threads before `main`, and a signal
sent to the process can go to any thread that does not block it. So
`hold_signals` blocks the signals and starts the program again with
`execv`: the new image and every thread it starts then block them. The
program takes each one with `take_signal` at a point where it can act on
it. An environment variable carries the signals that were blocked before
the first start, and a child gets the signal mask of that first start.

A child is started with `fork` and `execv`, as Python's `subprocess` does:
it gets a new session, the other descriptors close, and the program is
found on `PATH` in the parent. A failed `execv` reaches the parent as an
`errno` value through a pipe that closes on a successful `execv`.
"""

from std.ffi import c_int, external_call
from std.memory import Pointer
from std.os import getenv, setenv, unsetenv
from std.sys import CompilationTarget, argv
from std.time import perf_counter_ns

comptime SIGHUP = 1
"""The hang-up signal."""
comptime SIGINT = 2
"""The interrupt signal."""
comptime SIGKILL = 9
"""The kill signal."""
comptime SIGTERM = 15
"""The termination signal."""

comptime EPERM = 1
"""Operation not permitted."""
comptime ENOENT = 2
"""No such file or directory."""
comptime ESRCH = 3
"""No such process."""
comptime EINTR = 4
"""Interrupted system call."""
comptime ECHILD = 10
"""No child processes."""
comptime EACCES = 13
"""Permission denied."""
comptime ENOTDIR = 20
"""Not a directory."""

comptime WNOHANG = 1
"""`waitpid` returns at once when the child has not ended."""

comptime _MARK = "THREEMOJO_HELD_SIGNALS"
"""The environment variable that marks the second start."""
comptime _UNSET = "\x00unset"
"""A value that no environment variable can hold."""
comptime _SET_BYTES = 128
"""The bytes of a `sigset_t`: 128 on Linux, 4 on macOS."""


def _at(address: Int) -> OpaquePointer[MutAnyOrigin]:
    """Return an address as a C pointer; zero is `NULL`."""
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=address)


def _linux() -> Bool:
    """Return whether the program runs on Linux."""
    return CompilationTarget.is_linux()


def mask_how_block() -> c_int:
    """Return `SIG_BLOCK` for this platform.

    Returns:
        The value.
    """
    return c_int(0) if _linux() else c_int(1)


def mask_how_set() -> c_int:
    """Return `SIG_SETMASK` for this platform.

    Returns:
        The value.
    """
    return c_int(2) if _linux() else c_int(3)


def errno() -> Int:
    """Return the calling thread's `errno`.

    Returns:
        The value.
    """
    var address: Int
    comptime if CompilationTarget.is_linux():
        address = Int(
            external_call["__errno_location", OpaquePointer[MutAnyOrigin]]()
        )
    else:
        address = Int(external_call["__error", OpaquePointer[MutAnyOrigin]]())
    return Int(Pointer[Int32, MutAnyOrigin](unsafe_from_address=address)[])


def strerror(number: Int) -> String:
    """Return the C library's text for an `errno` value.

    Args:
        number: The value.

    Returns:
        The text.
    """
    var address = external_call["strerror", OpaquePointer[MutAnyOrigin]](
        c_int(number)
    )
    return c_text(Int(address))


def c_text(address: Int) -> String:
    """Return the NUL-terminated bytes at an address as text.

    Args:
        address: The first byte, or zero.

    Returns:
        The text; invalid UTF-8 becomes replacement characters.
    """
    var bytes = List[UInt8]()
    if address == 0:
        return String()
    var at = address
    while True:
        var byte = Pointer[UInt8, MutAnyOrigin](unsafe_from_address=at)[]
        if byte == 0:
            break
        bytes.append(byte)
        at += 1
    return String(from_utf8_lossy=bytes)


def c_bytes(text: String) -> List[UInt8]:
    """Return a string's bytes with a final NUL.

    Args:
        text: The string.

    Returns:
        The bytes.
    """
    var out = List[UInt8](capacity=text.byte_length() + 1)
    for byte in text.as_bytes():
        out.append(byte)
    out.append(0)
    return out^


def monotonic_seconds() -> Float64:
    """Return a monotonic clock reading in seconds.

    Returns:
        The seconds.
    """
    return Float64(perf_counter_ns()) / 1e9


def nap(seconds: Float64):
    """Sleep for a short time; a signal can end it early.

    Args:
        seconds: The time, at most about two seconds.
    """
    var micro = Int(seconds * 1e6)
    if micro <= 0:
        return
    _ = external_call["usleep", c_int](UInt32(micro))


comptime O_WRONLY = 1
"""Open for writing only."""


def at_cwd() -> Int:
    """Return `AT_FDCWD` for this platform.

    Returns:
        The value.
    """
    return -100 if _linux() else -2


def o_cloexec() -> Int:
    """Return `O_CLOEXEC` for this platform.

    Returns:
        The flag.
    """
    return 0x80000 if _linux() else 0x1000000


def o_directory() -> Int:
    """Return `O_DIRECTORY` for this platform.

    Returns:
        The flag.
    """
    comptime if CompilationTarget.is_linux():
        comptime if CompilationTarget.is_x86():
            return 0x10000
        else:
            return 0x4000
    else:
        return 0x100000


def o_nofollow() -> Int:
    """Return `O_NOFOLLOW` for this platform.

    Returns:
        The flag.
    """
    comptime if CompilationTarget.is_linux():
        comptime if CompilationTarget.is_x86():
            return 0x20000
        else:
            return 0x8000
    else:
        return 0x100


def open_at(directory: Int, path: List[UInt8], flags: Int) -> Int:
    """Open a file with `openat`.

    Args:
        directory: The directory descriptor, or `at_cwd()`.
        path: The path, with a final NUL.
        flags: The `O_` flags.

    Returns:
        The descriptor, or -1 with `errno` set.
    """
    return Int(
        external_call["openat", c_int](
            c_int(directory), _at(Int(path.unsafe_ptr())), c_int(flags)
        )
    )


def close_fd(fd: Int):
    """Close a descriptor and ignore an error.

    Args:
        fd: The descriptor.
    """
    _ = external_call["close", c_int](c_int(fd))


def set_cloexec(fd: Int):
    """Mark a descriptor to close on `exec`.

    Args:
        fd: The descriptor.
    """
    _ = external_call["fcntl", c_int](c_int(fd), c_int(2), c_int(1))


def make_pipe() raises -> Tuple[Int, Int]:
    """Make a pipe whose ends close on `exec`.

    Returns:
        The read end and the write end.

    Raises:
        Error: If `pipe` fails.
    """
    var ends = List[Int32](length=2, fill=0)
    if external_call["pipe", c_int](_at(Int(ends.unsafe_ptr()))) != 0:
        raise Error("OSError: [Errno ", errno(), "] ", strerror(errno()))
    var pair = (Int(ends[0]), Int(ends[1]))
    set_cloexec(pair[0])
    set_cloexec(pair[1])
    return pair


struct SignalSet(Movable):
    """A `sigset_t` in memory that this program owns."""

    var bytes: List[UInt8]
    """The storage, larger than any platform's `sigset_t`."""

    def __init__(out self):
        """Make an empty set."""
        self.bytes = List[UInt8](length=_SET_BYTES, fill=0)
        _ = external_call["sigemptyset", c_int](_at(self.address()))

    def address(self) -> Int:
        """Return the set's address.

        Returns:
            The address.
        """
        return Int(self.bytes.unsafe_ptr())

    def add(mut self, number: Int):
        """Add a signal.

        Args:
            number: The signal.
        """
        _ = external_call["sigaddset", c_int](
            _at(self.address()), c_int(number)
        )

    def remove(mut self, number: Int):
        """Remove a signal.

        Args:
            number: The signal.
        """
        _ = external_call["sigdelset", c_int](
            _at(self.address()), c_int(number)
        )

    def has(self, number: Int) -> Bool:
        """Return whether the set holds a signal.

        Args:
            number: The signal.

        Returns:
            True when the set holds it.
        """
        return (
            external_call["sigismember", c_int](
                _at(self.address()), c_int(number)
            )
            == 1
        )


def current_mask() -> SignalSet:
    """Return the calling thread's signal mask.

    Returns:
        The mask.
    """
    var mask = SignalSet()
    _ = external_call["pthread_sigmask", c_int](
        mask_how_block(), _at(0), _at(mask.address())
    )
    return mask^


struct SignalHold(Copyable, Movable):
    """The signals that this program takes itself, and their first state."""

    var numbers: List[Int]
    """The signals, blocked in every thread when `active`."""
    var first_blocked: List[Int]
    """The ones that were blocked before the first start."""
    var active: Bool
    """True when every thread blocks `numbers`."""

    def __init__(out self):
        """Hold no signal: a child gets the current mask."""
        self.numbers = List[Int]()
        self.first_blocked = List[Int]()
        self.active = False

    def child_mask(self) -> SignalSet:
        """Return the mask a child gets: the mask of the first start.

        Returns:
            The mask.
        """
        var mask = current_mask()
        for number in self.numbers:
            if number not in self.first_blocked:
                mask.remove(number)
        return mask^


def _executable() -> String:
    """Return the path of the running program, or empty."""
    var buffer = List[UInt8](length=4097, fill=0)
    comptime if CompilationTarget.is_linux():
        var path = c_bytes("/proc/self/exe")
        var count = external_call["readlink", Int](
            _at(Int(path.unsafe_ptr())), _at(Int(buffer.unsafe_ptr())), 4096
        )
        if count <= 0:
            return String()
        buffer.resize(count, 0)
        return String(from_utf8_lossy=buffer)
    else:
        var size = List[UInt32](length=1, fill=4096)
        if (
            external_call["_NSGetExecutablePath", c_int](
                _at(Int(buffer.unsafe_ptr())), _at(Int(size.unsafe_ptr()))
            )
            != 0
        ):
            return String()
        return c_text(Int(buffer.unsafe_ptr()))


def hold_signals(numbers: List[Int]) raises -> SignalHold:
    """Block signals in every thread, by starting the program again.

    The first start blocks the signals in its one thread, marks the
    environment, and replaces itself with `execv`. The second start removes
    the mark and returns. When `execv` fails, the program goes on with the
    signals unblocked, and their default actions apply.

    Args:
        numbers: The signals.

    Returns:
        What a child needs to get the first start's mask back.

    Raises:
        Error: Never in practice; the environment calls can raise.
    """
    var hold = SignalHold()
    hold.numbers = numbers.copy()
    var mark = getenv(_MARK, _UNSET)
    if mark != _UNSET:
        _ = unsetenv(_MARK)
        for word in mark.split(","):
            if word.byte_length() > 0:
                hold.first_blocked.append(Int(word))
        var mask = current_mask()
        hold.active = True
        for number in numbers:
            if not mask.has(number):
                hold.active = False
        return hold^
    var mask = current_mask()
    var text = String()
    var block = SignalSet()
    for number in numbers:
        if mask.has(number):
            hold.first_blocked.append(number)
            text += String(number) + ","
        block.add(number)
    var path = _executable()
    if path.byte_length() == 0:
        return hold^
    _ = setenv(_MARK, text, True)
    _ = external_call["pthread_sigmask", c_int](
        mask_how_block(), _at(block.address()), _at(0)
    )
    var words = List[List[UInt8]]()
    var given = argv()
    for index in range(len(given)):
        words.append(c_bytes(String(given[index])))
    var pointers = List[Int]()
    for index in range(len(words)):
        pointers.append(Int(words[index].unsafe_ptr()))
    pointers.append(0)
    var program = c_bytes(path)
    _ = external_call["execv", c_int](
        _at(Int(program.unsafe_ptr())), _at(Int(pointers.unsafe_ptr()))
    )
    # The program could not start again: undo the block and the mark.
    var undo = current_mask()
    for number in numbers:
        if number not in hold.first_blocked:
            undo.remove(number)
    _ = external_call["pthread_sigmask", c_int](
        mask_how_set(), _at(undo.address()), _at(0)
    )
    _ = unsetenv(_MARK)
    return hold^


def take_signal(hold: SignalHold) -> Int:
    """Take one held signal that is pending.

    Args:
        hold: The held signals.

    Returns:
        The signal, or zero when none is pending or none is held.
    """
    if not hold.active:
        return 0
    var pending = SignalSet()
    _ = external_call["sigpending", c_int](_at(pending.address()))
    for number in hold.numbers:
        if pending.has(number):
            var one = SignalSet()
            one.add(number)
            var taken = List[Int32](length=1, fill=0)
            _ = external_call["sigwait", c_int](
                _at(one.address()), _at(Int(taken.unsafe_ptr()))
            )
            return number
    return 0


def exec_path() -> String:
    """Return the search path of `os.get_exec_path`: `PATH`, or the default.

    Returns:
        The colon-separated directories.
    """
    return getenv("PATH", "/bin:/usr/bin")


def exec_candidates(program: String) -> List[String]:
    """Return the files to try for a program, as Python's `execvp` does.

    Args:
        program: The program, with or without a directory.

    Returns:
        `program` itself when it holds a slash, otherwise each `PATH`
        directory joined to it.
    """
    var out = List[String]()
    if "/" in program:
        out.append(program)
        return out^
    for directory in exec_path().split(":"):
        var text = String(directory)
        if text.byte_length() == 0:
            out.append(program)
        elif text.endswith("/"):
            out.append(text + program)
        else:
            out.append(text + "/" + program)
    return out^


struct ExecPlan(Movable):
    """The C strings that `execv` needs, made before `fork`."""

    var files: List[List[UInt8]]
    """Each file to try."""
    var words: List[List[UInt8]]
    """The arguments."""
    var pointers: List[Int]
    """The argument addresses, then zero."""

    def __init__(out self, command: List[String]):
        """Make the strings.

        Args:
            command: The program and its arguments.
        """
        self.files = List[List[UInt8]]()
        for file in exec_candidates(command[0]):
            self.files.append(c_bytes(file))
        self.words = List[List[UInt8]]()
        for word in command:
            self.words.append(c_bytes(word))
        self.pointers = List[Int]()
        for index in range(len(self.words)):
            self.pointers.append(Int(self.words[index].unsafe_ptr()))
        self.pointers.append(0)

    def run(self) -> Int:
        """Try each file with `execv`, as Python's `os.execvp` does.

        Returns:
            The `errno` to report, only when no file started: the first
            error that is not `ENOENT` or `ENOTDIR`, else the last one.
        """
        var saved = 0
        var last = ENOENT
        for index in range(len(self.files)):
            _ = external_call["execv", c_int](
                _at(Int(self.files[index].unsafe_ptr())),
                _at(Int(self.pointers.unsafe_ptr())),
            )
            last = errno()
            if last != ENOENT and last != ENOTDIR and saved == 0:
                saved = last
        return saved if saved != 0 else last


def exec_error_status(number: Int) -> Int:
    """Return the status Python's tools give when a program cannot start.

    Args:
        number: The `errno`.

    Returns:
        127 for a missing file, 126 for a denied one, otherwise 1.
    """
    if number == ENOENT:
        return 127
    if number == EACCES or number == EPERM:
        return 126
    return 1


def _close_from(first: Int, keep: Int):
    """Close every descriptor from `first` up, except `keep`. Fork-safe."""
    comptime if CompilationTarget.is_linux():
        if keep > first:
            _ = external_call["close_range", c_int](
                UInt32(first), UInt32(keep - 1), c_int(0)
            )
        _ = external_call["close_range", c_int](
            UInt32(max(first, keep + 1)), UInt32(0xFFFFFFFF), c_int(0)
        )
    else:
        var top = external_call["getdtablesize", c_int]()
        for fd in range(first, min(Int(top), 65536)):
            if fd != keep:
                _ = external_call["close", c_int](c_int(fd))


def spawn(
    command: List[String], hold: SignalHold, stdout_fd: Int, quiet_errors: Bool
) raises -> Int:
    """Start a program in a new session.

    The child keeps the standard input, gets `stdout_fd` as its standard
    output when it is not negative, and `/dev/null` as its standard error
    when `quiet_errors`. Every other descriptor closes.

    Args:
        command: The program and its arguments.
        hold: The held signals, whose first mask the child gets.
        stdout_fd: The standard output, or -1 to keep this program's.
        quiet_errors: True to send the standard error to `/dev/null`.

    Returns:
        The child's process ID.

    Raises:
        Error: `OSError: [Errno N] ...` when the program cannot start; the
            child is then reaped.
    """
    if len(command) == 0:
        raise Error("OSError: [Errno ", ENOENT, "] no program")
    var plan = ExecPlan(command)
    var mask = hold.child_mask()
    var null_fd = -1
    if quiet_errors:
        var null_path = c_bytes("/dev/null")
        null_fd = Int(open_at(at_cwd(), null_path, O_WRONLY | o_cloexec()))
        if null_fd < 0:
            var number = errno()
            raise Error("OSError: [Errno ", number, "] ", strerror(number))
    var pipe = make_pipe()
    var report = List[Int32](length=1, fill=0)
    var pid = Int(external_call["fork", c_int]())
    if pid == 0:
        # The child: only async-signal-safe calls from here on.
        _ = external_call["setsid", c_int]()
        if stdout_fd >= 0:
            if stdout_fd == 1:
                _ = external_call["fcntl", c_int](c_int(1), c_int(2), c_int(0))
            else:
                _ = external_call["dup2", c_int](c_int(stdout_fd), c_int(1))
        if null_fd >= 0:
            _ = external_call["dup2", c_int](c_int(null_fd), c_int(2))
        _ = external_call["pthread_sigmask", c_int](
            mask_how_set(), _at(mask.address()), _at(0)
        )
        _close_from(3, pipe[1])
        report[0] = Int32(plan.run())
        _ = external_call["write", Int](
            pipe[1], _at(Int(report.unsafe_ptr())), 4
        )
        external_call["_exit", NoneType](c_int(255))
    var fork_error = errno()
    close_fd(pipe[1])
    if null_fd >= 0:
        close_fd(null_fd)
    if pid < 0:
        close_fd(pipe[0])
        raise Error("OSError: [Errno ", fork_error, "] ", strerror(fork_error))
    var got = 0
    while True:
        var count = external_call["read", Int](
            pipe[0], _at(Int(report.unsafe_ptr()) + got), 4 - got
        )
        if count > 0:
            got += count
            if got == 4:
                break
            continue
        if count < 0 and errno() == EINTR:
            continue
        break
    close_fd(pipe[0])
    if got == 4:
        _ = wait_blocking(pid)
        var number = Int(report[0])
        raise Error(
            "OSError: [Errno ",
            number,
            "] ",
            strerror(number),
            ": ",
            repr(command[0]),
        )
    return pid


struct WaitResult(ImplicitlyCopyable, Movable):
    """What `waitpid` said about one child."""

    var done: Bool
    """True when the child ended and is reaped."""
    var status: Int
    """Python's `returncode`: the exit status, or minus the signal."""
    var error: Int
    """The `errno` of a failed `waitpid`, otherwise zero."""

    def __init__(out self, done: Bool, status: Int, error: Int):
        """Make a result.

        Args:
            done: True when the child ended.
            status: The return code.
            error: The `errno`, or zero.
        """
        self.done = done
        self.status = status
        self.error = error


def _decode(raw: Int) -> Int:
    """Return Python's `returncode` for a raw wait status."""
    var low = raw & 0x7F
    if low == 0:
        return (raw >> 8) & 0xFF
    return -low


def try_wait(pid: Int) -> WaitResult:
    """Reap a child if it has ended, without waiting.

    Args:
        pid: The child.

    Returns:
        Whether it ended, its return code, and any `errno`.
    """
    var raw = List[Int32](length=1, fill=0)
    while True:
        var got = external_call["waitpid", c_int](
            c_int(pid), _at(Int(raw.unsafe_ptr())), c_int(WNOHANG)
        )
        if got == 0:
            return WaitResult(False, 0, 0)
        if got < 0:
            var number = errno()
            if number == EINTR:
                continue
            return WaitResult(False, 0, number)
        return WaitResult(True, _decode(Int(raw[0])), 0)


def wait_blocking(pid: Int) -> WaitResult:
    """Wait for a child to end and reap it.

    Args:
        pid: The child.

    Returns:
        Its return code, or the `errno` of a failed `waitpid`.
    """
    var raw = List[Int32](length=1, fill=0)
    while True:
        var got = external_call["waitpid", c_int](
            c_int(pid), _at(Int(raw.unsafe_ptr())), c_int(0)
        )
        if got < 0:
            var number = errno()
            if number == EINTR:
                continue
            return WaitResult(False, 0, number)
        return WaitResult(True, _decode(Int(raw[0])), 0)


def signal_group(pid: Int, number: Int) -> Int:
    """Send a signal to a process group.

    Args:
        pid: The group, which is the ID of its leader.
        number: The signal, or zero to probe.

    Returns:
        Zero, or the `errno` of the failure.
    """
    if external_call["killpg", c_int](c_int(pid), c_int(number)) == 0:
        return 0
    return errno()
