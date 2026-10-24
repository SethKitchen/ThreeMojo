# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Verify complete coverage vectors under recursion, abandonment, and tasks.

Builds use the pinned compiler and `-Werror`. Each test keeps its five-second
limit. Concurrent captures are actual POSIX pipes. No GPU or network is used.

    check_coverage_protocol --mojo .venv/bin/mojo

Run it from the repository root. `make test-coverage-tool` does.
"""

from std.collections import Dict, Set
from std.ffi import c_int, external_call
from std.os import listdir, remove, rmdir
from std.pathlib import Path
from std.sys import CompilationTarget, argv, exit, stderr
from std.tempfile import mkdtemp

from tools._cli import absolute_path
from tools._owned_process import (
    ExecPlan,
    at_cwd,
    c_bytes,
    close_fd,
    errno,
    make_pipe,
    o_cloexec,
    open_at,
    strerror,
    wait_blocking,
)
from tools._process import ProcessResult, run_program
from tools.run_suite import result_errors, slow_tests

comptime _MAX_RECORD_BYTES = 512
"""The largest accepted evaluation record, including its newline."""


struct EvidenceReducer(Movable):
    """Keep distinct hits and complete version 2 evaluation records.

    Completed vectors are assembled inside each function invocation, so the
    reducer needs no pending operands. This is the uncached evidence reducer.
    Its written records match the caching reducer on every accepted stream.
    """

    var payloads: Set[String]
    """Hit payloads already written."""
    var evaluations: Set[String]
    """Evaluation and branch keys already written."""
    var written: List[String]
    """The reduced records, each ending with a newline when the input did."""

    def __init__(out self):
        """Make an empty reducer."""
        self.payloads = Set[String]()
        self.evaluations = Set[String]()
        self.written = List[String]()

    def text(self) -> String:
        """Return the reduced records joined in write order.

        Returns:
            The reduced stream.
        """
        return "".join(self.written)

    def feed(mut self, line: String) raises:
        """Read one raw line and refuse a malformed probe record.

        Args:
            line: One raw record, usually including its newline.

        Raises:
            Error: If the record is malformed or ambiguous.
        """
        var record = _strip(line)
        if record.startswith("COVLINE:"):
            self._payload(String(record[byte=8:]))
            return
        if record.startswith("COVEVAL2:"):
            self._evaluation(line, record)
            return
        if not record.startswith("COVBRANCH:"):
            self.written.append(line)
            return
        var payload = String(record[byte=10:])
        var parts = _rpartition(payload, ":")
        if parts[1] and parts[2] != "T" and parts[2] != "F":
            raise Error("Malformed branch outcome: " + record)
        if not parts[1]:
            self.written.append(line)
            return
        if parts[0].find(".") >= 0:
            raise Error(
                "Legacy compound coverage is ambiguous; recapture with"
                " protocol 2"
            )
        var identity = _rpartition(parts[0], ":")
        if (
            not identity[1]
            or identity[0].byte_length() == 0
            or not _digits(identity[2])
            or _number(identity[2]) < 1
        ):
            raise Error("Malformed branch decision ID: " + record)
        self._payload(payload)
        var key = parts[0] + "\n\n" + parts[2]
        if not (key in self.evaluations):
            self.evaluations.add(key)
            self.written.append(record + "\n")

    def _payload(mut self, payload: String):
        """Write one hit payload the first time it appears."""
        if payload in self.payloads:
            return
        self.payloads.add(payload)
        self.written.append("COVLINE:" + payload + "\n")

    def _evaluation(mut self, line: String, record: String) raises:
        """Validate one `COVEVAL2` record and write its first copy."""
        if (
            record.byte_length() + 1 > _MAX_RECORD_BYTES
            or not record.endswith(";")
            or not line.endswith("\n")
        ):
            raise Error("Malformed or truncated evaluation record: " + record)
        var body = String(record[byte = 9 : record.byte_length() - 1])
        var vector_parts = _rpartition(body, ":")
        var outcome_parts = _rpartition(vector_parts[0], ":")
        var decision = outcome_parts[0]
        var outcome = outcome_parts[2]
        var vector = vector_parts[2]
        if not outcome_parts[1] or (outcome != "T" and outcome != "F"):
            raise Error("Malformed evaluation outcome: " + record)
        var identity = _rpartition(decision, ":")
        if (
            not identity[1]
            or identity[0].byte_length() == 0
            or not _digits(identity[2])
            or _number(identity[2]) < 1
        ):
            raise Error("Malformed evaluation decision ID: " + record)
        if vector.find("?") >= 0:
            raise Error(
                "Inconsistent repeated truth conversion; "
                "MC/DC cannot be certified: "
                + record
            )
        if not vector_parts[1] or not _vector_ok(vector):
            raise Error("Malformed evaluation vector: " + record)
        var key = decision + "\n" + vector + "\n" + outcome
        if not (key in self.evaluations):
            self.evaluations.add(key)
            self.written.append(record + "\n")


def _is_space(byte: UInt8) -> Bool:
    """Return whether `byte` is ASCII whitespace, as `bytes.strip` does."""
    return (
        byte == 9
        or byte == 10
        or byte == 11
        or byte == 12
        or byte == 13
        or byte == 32
    )


def _strip(text: String) -> String:
    """Return `text` without leading or trailing ASCII whitespace."""
    var raw = text.as_bytes()
    var first = 0
    var last = len(raw)
    while first < last and _is_space(raw[first]):
        first += 1
    while last > first and _is_space(raw[last - 1]):
        last -= 1
    if first == 0 and last == len(raw):
        return text
    var copy = text
    return String(copy[byte=first:last])


def _rpartition(text: String, separator: String) -> Tuple[String, Bool, String]:
    """Return the split at the last `separator`, and whether it was found."""
    var at = text.rfind(separator)
    if at < 0:
        return (String(), False, text)
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + separator.byte_length() :])
    return (head, True, tail)


def _digits(text: String) -> Bool:
    """Return whether `text` is one or more ASCII digits."""
    if text.byte_length() == 0:
        return False
    for byte in text.as_bytes():
        if byte < 48 or byte > 57:
            return False
    return True


def _number(text: String) -> Int:
    """Return the integer value of an ASCII digit string."""
    var value = 0
    for byte in text.as_bytes():
        value = value * 10 + Int(byte) - 48
    return value


def _vector_ok(vector: String) -> Bool:
    """Return whether `vector` is a non-empty `T`/`F`/`-` vector with a truth.
    """
    if vector.byte_length() < 2:
        return False
    var saw = False
    for byte in vector.as_bytes():
        if byte != 84 and byte != 70 and byte != 45:
            return False
        if byte == 84 or byte == 70:
            saw = True
    return saw


def _keep_newlines(text: String) -> List[String]:
    """Return the lines of `text`, each keeping its newline."""
    var lines = List[String]()
    var rest = text
    while True:
        var at = rest.find("\n")
        if at < 0:
            if rest.byte_length() > 0:
                lines.append(rest)
            return lines^
        var end = at + 1
        var piece = String(rest[byte=:end])
        lines.append(piece)
        var next = String(rest[byte=end:])
        rest = next


def reduce_text(text: String) raises -> String:
    """Reduce one coverage stream.

    Args:
        text: The raw standard error.

    Returns:
        The distinct hits and complete vectors.

    Raises:
        Error: If a record is malformed.
    """
    var reducer = EvidenceReducer()
    var lines = _keep_newlines(text)
    for line in lines:
        reducer.feed(line)
    return reducer.text()


def _fixture(name: String) raises -> String:
    """Return one protocol probe source."""
    return Path("tools/fixtures/" + name).read_text()


def _decision(source: String, marker: String) raises -> Int:
    """Return the 1-based line that contains `marker`."""
    var number = 1
    for line in source.splitlines():
        if String(line).find(marker) >= 0:
            return number
        number += 1
    raise Error("missing marker: " + marker)


def _vector_records(raw: String, line: Int) -> List[String]:
    """Return the vector tails recorded for one source line."""
    var prefix = "COVEVAL2:fixture:" + String(line) + ":"
    var records = List[String]()
    for row in raw.splitlines():
        var text = String(row)
        if text.startswith(prefix):
            records.append(String(text[byte = prefix.byte_length() :]))
    return records^


def _check_case(
    raw: String, source: String, marker: String, expected_text: String
) raises:
    """Refuse one vector whose tails differ from `expected_text`."""
    var expected = List[String]()
    for part in expected_text.split(","):
        expected.append(String(part))
    var actual = _vector_records(raw, _decision(source, marker))
    if not _same(actual, expected):
        raise Error("vector changed: " + marker)


def _same(actual: List[String], expected: List[String]) -> Bool:
    """Return whether two lists hold the same strings in order."""
    if len(actual) != len(expected):
        return False
    var index = 0
    while index < len(actual):
        if actual[index] != expected[index]:
            return False
        index += 1
    return True


def check_vectors(raw: String, source: String) raises:
    """Refuse a capture whose vectors or overlap differ from the fixture.

    Args:
        raw: The instrumented standard error.
        source: The fixture source whose line numbers the records use.

    Raises:
        Error: If a vector, a count, or the overlap is wrong.
    """
    _check_case(raw, source, "if mark(depth > 0", "F:F-;,F:TF;,F:TF;,F:TF;")
    _check_case(raw, source, 'if mark(True, order, "b")', "F:TF;")
    _check_case(raw, source, "if mark(index != 1", "F:F-;,T:TT;")
    _check_case(raw, source, "while mark(index < 2", "T:TT;,T:TT;,F:F-;")
    _check_case(raw, source, "elif mark(choice == 1", "T:TT;,F:F-;")
    _check_case(raw, source, "if value and False:", "F:TF;")
    _check_case(raw, source, 'if mark(True, order, "n")', "F:TF;")
    _check_case(raw, source, "if mark(_cov_eval_state0", "F:TF;")
    _check_case(raw, source, "if mark(List == 7", "T:TT;")
    _check_case(raw, source, 'if mark(True, order, "t")', "F:TF;")
    var concurrent_line = _decision(source, "if paused(")
    var concurrent = _vector_records(raw, concurrent_line)
    var counts = Dict[String, Int]()
    for record in concurrent:
        var seen = counts.get(record).or_else(0)
        counts[record] = seen + 1
    if (
        counts.get("F:F-;").or_else(0) != 400
        or counts.get("F:TF;").or_else(0) != 200
        or counts.get("T:TT;").or_else(0) != 200
        or len(counts) != 3
    ):
        raise Error("concurrent vector counts changed")
    var active = 0
    var peak = 0
    var hit_prefix = "COVLINE:fixture:" + String(concurrent_line) + ".0:"
    var vector_prefix = "COVEVAL2:fixture:" + String(concurrent_line) + ":"
    for row in raw.splitlines():
        var text = String(row)
        if text.startswith(hit_prefix):
            active += 1
            if active > peak:
                peak = active
        elif text.startswith(vector_prefix):
            active -= 1
    if active != 0 or peak < 2:
        raise Error("no actual overlap observed")
    var abandoned = _decision(source, "if mark(index != 1")
    var needle = "COVLINE:fixture:" + String(abandoned) + ".0:T\n"
    if _count(raw, needle) != 2:
        raise Error("abandoned condition hit changed")


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs in `text`."""
    var count = 0
    var rest = text
    var width = needle.byte_length()
    while True:
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        var next = String(rest[byte = at + width :])
        rest = next


def _must(
    command: List[String], seconds: Float64, directory: String = ""
) raises -> ProcessResult:
    """Run a command and refuse a non-zero status."""
    var result = run_program(
        command, seconds, merge_errors=False, directory=directory
    )
    if result.timed_out or result.status != 0:
        raise Error(result.output + "\n" + result.errors)
    return result^


def _with_env(prefix: List[String], command: List[String]) -> List[String]:
    """Return `env` plus `prefix` plus `command`."""
    var words = List[String]()
    words.append("env")
    for word in prefix:
        words.append(word)
    for word in command:
        words.append(word)
    return words^


def _copy_tree(root: String, folder: String) raises:
    """Copy the coverage package and the task adapter into `folder`."""
    _ = _must(
        ["cp", "-a", root + "/coverage", folder + "/coverage"],
        30,
    )
    var build = folder + "/coverage/build"
    if Path(build).exists():
        _ = _must(["rm", "-rf", build], 30)
    _ = _must(["mkdir", "-p", folder + "/render"], 10)
    for name in ["__init__.mojo", "tasks.mojo"]:
        _ = _must(
            ["cp", "-a", root + "/render/" + name, folder + "/render/" + name],
            10,
        )


def _rows(stdout: String) -> List[String]:
    """Return the `RESULT` lines of a suite."""
    var rows = List[String]()
    for line in stdout.splitlines():
        var text = String(line)
        if text.startswith("RESULT "):
            rows.append(text)
    return rows^


def _before_suite(stdout: String) -> String:
    """Return the program output before the test runner's banner."""
    var at = stdout.find("\nRunning ")
    var head = stdout if at < 0 else String(stdout[byte=:at])
    return _strip(head)


def _expected_results() -> List[String]:
    """Return the fixture's result lines."""
    var rows = List[String]()
    rows.append("RESULT recursion False aaaa")
    rows.append("RESULT caught False bbc")
    rows.append("RESULT abandoned pxeppxy")
    rows.append("RESULT loop wzwzkwq0lr1l2")
    rows.append("RESULT nested False n")
    rows.append("RESULT collision False g")
    rows.append("RESULT types True s")
    rows.append("RESULT indentation False t")
    rows.append("RESULT concurrent [50, 0, 50, 0, 50, 0, 50, 0]")
    return rows^


def _linux() -> Bool:
    """Return whether the program runs on Linux."""
    return CompilationTarget.is_linux()


def _o_wronly() -> Int:
    """Return `O_WRONLY`."""
    return 1


def _o_trunc() -> Int:
    """Return `O_TRUNC`."""
    return 0x200 if _linux() else 0x400


def _o_nonblock() -> Int:
    """Return `O_NONBLOCK`."""
    return 0x800 if _linux() else 0x4


def _eagain() -> Int:
    """Return `EAGAIN`."""
    return 11 if _linux() else 35


def _sigusr1() -> Int:
    """Return `SIGUSR1`."""
    return 10 if _linux() else 30


def _pointer(address: Int) -> OpaquePointer[MutAnyOrigin]:
    """Return an address as a C pointer."""
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=address)


def _open_write(path: String) raises -> Int:
    """Create or replace a file and return its descriptor."""
    Path(path).write_text("")
    var fd = open_at(
        at_cwd(),
        c_bytes(path),
        _o_wronly() | _o_trunc() | o_cloexec(),
    )
    if fd < 0:
        raise Error("OSError: [Errno ", errno(), "] ", strerror(errno()))
    return fd


def _set_nonblock(fd: Int, enabled: Bool) raises:
    """Set or clear `O_NONBLOCK` on `fd`."""
    var flags = external_call["fcntl", c_int](c_int(fd), c_int(3), c_int(0))
    if flags < 0:
        raise Error("OSError: [Errno ", errno(), "] ", strerror(errno()))
    var next = Int(flags)
    if enabled:
        next |= _o_nonblock()
    else:
        next &= ~_o_nonblock()
    if external_call["fcntl", c_int](c_int(fd), c_int(4), c_int(next)) < 0:
        raise Error("OSError: [Errno ", errno(), "] ", strerror(errno()))


def _limit_file_size() -> Int:
    """Set the file-size limit to 10 bytes. Return `errno`, or zero."""
    var limits = List[UInt64](length=2, fill=10)
    if (
        external_call["setrlimit", c_int](
            c_int(1), _pointer(Int(limits.unsafe_ptr()))
        )
        != 0
    ):
        return errno()
    return 0


def _exec_prepared(
    command: List[String],
    stdout_fd: Int,
    stderr_fd: Int,
    close_error: Bool,
    limit_file: Bool,
) raises -> Int:
    """Run `command` with prepared descriptors and return Python's status.

    Args:
        command: The program and its arguments.
        stdout_fd: The standard output to install, or -1 to discard it.
        stderr_fd: The standard error to install when `close_error` is false.
        close_error: True to close standard error instead of installing it.
        limit_file: True to set `RLIMIT_FSIZE` to 10 bytes.

    Returns:
        The exit status, or minus the signal number.

    Raises:
        Error: If the process cannot start.
    """
    var plan = ExecPlan(command)
    var discard = -1
    if stdout_fd < 0:
        discard = open_at(
            at_cwd(), c_bytes("/dev/null"), _o_wronly() | o_cloexec()
        )
    var pid = Int(external_call["fork", c_int]())
    if pid < 0:
        raise Error("OSError: [Errno ", errno(), "] ", strerror(errno()))
    if pid == 0:
        if stdout_fd >= 0:
            _ = external_call["dup2", c_int](c_int(stdout_fd), c_int(1))
        elif discard >= 0:
            _ = external_call["dup2", c_int](c_int(discard), c_int(1))
        if close_error:
            _ = external_call["close", c_int](c_int(2))
        else:
            _ = external_call["dup2", c_int](c_int(stderr_fd), c_int(2))
        if limit_file:
            _ = _limit_file_size()
        var failed = plan.run()
        external_call["_exit", NoneType](c_int(127 if failed == 2 else 126))
    if discard >= 0:
        close_fd(discard)
    if stdout_fd >= 0:
        close_fd(stdout_fd)
    if not close_error:
        close_fd(stderr_fd)
    var waited = wait_blocking(pid)
    if not waited.done:
        raise Error(
            "OSError: [Errno ", waited.error, "] ", strerror(waited.error)
        )
    return waited.status


def _read_exact(fd: Int, count: Int) raises -> List[UInt8]:
    """Read exactly `count` bytes."""
    var raw = List[UInt8](length=count, fill=0)
    var got = 0
    while got < count:
        var size = external_call["read", Int](
            Int32(fd),
            _pointer(Int(raw.unsafe_ptr()) + got),
            count - got,
        )
        if size < 0:
            if errno() == 4:
                continue
            raise Error("OSError: [Errno ", errno(), "] ", strerror(errno()))
        if size == 0:
            raise Error("short read")
        got += size
    return raw^


def _read_available(fd: Int) raises -> List[UInt8]:
    """Read until `poll` reports no data, or the read returns zero."""
    var raw = List[UInt8]()
    while True:
        if not _poll_in(fd, 20):
            return raw^
        var chunk = List[UInt8](length=65536, fill=0)
        var size = external_call["read", Int](
            Int32(fd), _pointer(Int(chunk.unsafe_ptr())), 65536
        )
        if size < 0:
            if errno() == 4:
                continue
            raise Error("OSError: [Errno ", errno(), "] ", strerror(errno()))
        if size == 0:
            return raw^
        var index = 0
        while index < size:
            raw.append(chunk[index])
            index += 1


def _poll_in(fd: Int, milliseconds: Int) raises -> Bool:
    """Return whether `fd` can be read within `milliseconds`."""
    var slot = List[Int32](length=2, fill=0)
    slot[0] = Int32(fd)
    slot[1] = 1
    var result = external_call["poll", c_int](
        _pointer(Int(slot.unsafe_ptr())), c_int(1), c_int(milliseconds)
    )
    if result < 0:
        if errno() == 4:
            return False
        raise Error("OSError: [Errno ", errno(), "] ", strerror(errno()))
    return result > 0


def _fill_pipe(writer: Int) raises -> Int:
    """Write `x` until the pipe refuses more, and return the byte count."""
    _set_nonblock(writer, True)
    var chunk = List[UInt8](length=4096, fill=120)
    var filled = 0
    while True:
        var size = external_call["write", Int](
            Int32(writer), _pointer(Int(chunk.unsafe_ptr())), 4096
        )
        if size > 0:
            filled += size
            continue
        var number = errno()
        if number == 4:
            continue
        if number == _eagain():
            break
        raise Error("OSError: [Errno ", number, "] ", strerror(number))
    _set_nonblock(writer, False)
    return filled


def _bytes_equal(left: List[UInt8], right: List[UInt8]) -> Bool:
    """Return whether two byte lists are equal."""
    if len(left) != len(right):
        return False
    var index = 0
    while index < len(left):
        if left[index] != right[index]:
            return False
        index += 1
    return True


def _string_bytes(text: String) -> List[UInt8]:
    """Return the UTF-8 bytes of `text`."""
    var raw = List[UInt8]()
    for byte in text.as_bytes():
        raw.append(byte)
    return raw^


def _read_until_close(fd: Int) raises -> List[UInt8]:
    """Read a pipe until it closes or one second passes with no data."""
    var raw = List[UInt8]()
    var quiet = 0
    while quiet < 5:
        if not _poll_in(fd, 1000):
            quiet += 1
            continue
        quiet = 0
        var chunk = List[UInt8](length=65536, fill=0)
        var size = external_call["read", Int](
            Int32(fd), _pointer(Int(chunk.unsafe_ptr())), 65536
        )
        if size < 0:
            if errno() == 4:
                continue
            raise Error("OSError: [Errno ", errno(), "] ", strerror(errno()))
        if size == 0:
            return raw^
        var offset = 0
        while offset < size:
            raw.append(chunk[offset])
            offset += 1
    return raw^


def _interrupt_pipe(
    binary: String, size: String, library: String, preload: String
) raises:
    """Fill a pipe, interrupt its blocked write, and require the same record."""
    var data = make_pipe()
    var output = make_pipe()
    var filled = _fill_pipe(data[1])
    var command = List[String]()
    command.append("env")
    command.append(preload + "=" + library)
    command.append("THREEMOJO_WRITE_TEST=signal")
    command.append(binary)
    command.append(size)
    var plan = ExecPlan(command)
    var pid = Int(external_call["fork", c_int]())
    if pid < 0:
        raise Error("OSError: [Errno ", errno(), "] ", strerror(errno()))
    if pid == 0:
        _ = external_call["dup2", c_int](c_int(output[1]), c_int(1))
        _ = external_call["dup2", c_int](c_int(data[1]), c_int(2))
        var failed = plan.run()
        external_call["_exit", NoneType](c_int(127 if failed == 2 else 126))
    close_fd(data[1])
    close_fd(output[1])
    if not _poll_in(output[0], 5000):
        _ = external_call["kill", c_int](c_int(pid), c_int(9))
        _ = wait_blocking(pid)
        close_fd(data[0])
        close_fd(output[0])
        raise Error("write did not start")
    var ready = _read_exact(output[0], 6)
    if String(from_utf8_lossy=ready) != "READY\n":
        raise Error("write did not report READY")
    var notice = String()
    var spins = 0
    while notice.find("INTERRUPTED\n") < 0 and spins < 250:
        _ = external_call["kill", c_int](c_int(pid), c_int(_sigusr1()))
        if _poll_in(output[0], 20):
            var chunk = _read_available(output[0])
            notice += String(from_utf8_lossy=chunk)
        spins += 1
    if notice.find("INTERRUPTED\n") < 0:
        _ = external_call["kill", c_int](c_int(pid), c_int(9))
        _ = wait_blocking(pid)
        close_fd(data[0])
        close_fd(output[0])
        raise Error("no real write returned EINTR")
    var captured = _read_until_close(data[0])
    close_fd(output[0])
    var waited = wait_blocking(pid)
    close_fd(data[0])
    if waited.status != 0:
        raise Error("interrupted write exited " + String(waited.status))
    var plain = _must([binary, size], 10)
    if not _bytes_equal(captured, _pad(filled, _string_bytes(plain.errors))):
        raise Error("interrupted record changed or repeated")


def _pad(filled: Int, record: List[UInt8]) -> List[UInt8]:
    """Return `filled` bytes of `x` followed by `record`."""
    var combined = List[UInt8]()
    var cursor = 0
    while cursor < filled:
        combined.append(120)
        cursor += 1
    for byte in record:
        combined.append(byte)
    return combined^


def check(mojo: String, output: String) raises:
    """Run the protocol checks.

    Args:
        mojo: The Mojo compiler.
        output: A directory for the evidence files, or empty to keep none.

    Raises:
        Error: If a vector, a write, or a build fails.
    """
    var root = absolute_path(".")
    var compiler = absolute_path(mojo)
    var work = mkdtemp(prefix="threemojo-protocol-")
    try:
        var native = work + "/native"
        var rewritten = work + "/rewritten"
        _ = _must(["mkdir", "-p", native, rewritten], 10)
        _copy_tree(root, native)
        _copy_tree(root, rewritten)
        var source = _fixture("coverage_protocol_suite.txt")
        Path(work + "/errno-probe.mojo").write_text(
            _fixture("coverage_protocol_errno.txt")
        )
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                work + "/errno-probe.mojo",
                "-o",
                work + "/errno-probe",
            ],
            120,
        )
        var cleared = _must(
            _with_env(
                [
                    "-u",
                    "LD_PRELOAD",
                    "-u",
                    "DYLD_INSERT_LIBRARIES",
                    "-u",
                    "THREEMOJO_WRITE_TEST",
                ],
                [work + "/errno-probe"],
            ),
            5,
        )
        if cleared.output.byte_length() > 0 or cleared.errors.byte_length() > 0:
            raise Error(cleared.output + cleared.errors)
        Path(native + "/fixture.mojo").write_text(source)
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                root,
                root + "/coverage/build_cli.mojo",
                "-o",
                work + "/build",
            ],
            180,
        )
        _ = _must([work + "/build", rewritten, "fixture.mojo"], 60, native)
        var rewritten_text = Path(rewritten + "/fixture.mojo").read_text()
        if rewritten_text.find("var _cov_eval__state") < 0:
            raise Error("instrumented fixture lost its evaluation state")
        var binaries = List[String]()
        for folder in [native, rewritten]:
            var binary = folder + "/suite"
            _ = _must(
                [
                    compiler,
                    "build",
                    "-Werror",
                    "-I",
                    folder,
                    folder + "/fixture.mojo",
                    "-o",
                    binary,
                ],
                180,
                folder,
            )
            binaries.append(binary)
        var expected = _expected_results()
        var repeat = 0
        while repeat < 5:
            var raw = String()
            var native_out = String()
            var instrumented_out = String()
            var index = 0
            for binary in binaries:
                var temp = mkdtemp(prefix="threemojo-test-")
                var ran = _must(
                    _with_env(
                        [
                            "TMPDIR=" + temp,
                            "THREEMOJO_TEST_TMPDIR=" + temp,
                        ],
                        [binary],
                    ),
                    10,
                )
                _ = _must(["rm", "-rf", temp], 10)
                if len(result_errors(ran.output)) > 0:
                    raise Error(ran.output)
                if len(slow_tests(ran.output, 5.0)) > 0:
                    raise Error(ran.output)
                if _before_suite(ran.output) != "\n".join(expected):
                    raise Error(ran.output)
                if not _same(_rows(ran.output), expected):
                    raise Error(ran.output)
                if index == 0:
                    native_out = ran.output
                else:
                    instrumented_out = ran.output
                    raw = ran.errors
                index += 1
            for row in raw.splitlines():
                var text = String(row)
                if not text.startswith("COVLINE:") and not text.startswith(
                    "COVEVAL2:"
                ):
                    raise Error("torn probe record")
                if text.byte_length() + 1 > 512:
                    raise Error("probe record exceeds 512 bytes")
            check_vectors(raw, source)
            var reduced = reduce_text(raw)
            Path(work + "/raw-" + String(repeat) + ".txt").write_text(raw)
            Path(work + "/reduced-" + String(repeat) + ".txt").write_text(
                reduced
            )
            Path(work + "/native-" + String(repeat) + ".txt").write_text(
                native_out
            )
            Path(work + "/instrumented-" + String(repeat) + ".txt").write_text(
                instrumented_out
            )
            repeat += 1
        Path(native + "/analyze.mojo").write_text(
            _fixture("coverage_protocol_analyzer.txt")
        )
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                native,
                native + "/analyze.mojo",
                "-o",
                work + "/analyze",
            ],
            120,
        )
        repeat = 0
        while repeat < 5:
            var raw_report = _must(
                [
                    work + "/analyze",
                    work + "/raw-" + String(repeat) + ".txt",
                ],
                10,
            )
            var reduced_report = _must(
                [
                    work + "/analyze",
                    work + "/reduced-" + String(repeat) + ".txt",
                ],
                10,
            )
            if raw_report.output != reduced_report.output:
                raise Error(
                    "raw/reduced vectors differ for concurrent capture "
                    + String(repeat)
                )
            Path(work + "/vectors-" + String(repeat) + ".txt").write_text(
                raw_report.output
            )
            repeat += 1
        Path(native + "/boundary.mojo").write_text(
            _fixture("coverage_protocol_boundary.txt")
        )
        _ = _must(
            [
                compiler,
                "build",
                "-Werror",
                "-I",
                native,
                native + "/boundary.mojo",
                "-o",
                work + "/boundary",
            ],
            120,
        )
        var literal = _must([work + "/boundary", "-1"], 10)
        var literal_expected = (
            "COVLINE:literal:1\n"
            "COVLINE:literal:2:T\n"
            "COVLINE:literal:4.0:T\n"
            "COVLINE:literal:4.1:F\n"
            "COVLINE:literal:4:F\n"
            "COVEVAL2:literal:4:F:TF;\n"
        )
        if literal.errors != literal_expected:
            raise Error(literal.errors)
        Path(work + "/literal-runtime-records.txt").write_text(literal.errors)
        for size in [511, 512]:
            var ran = _must([work + "/boundary", String(size)], 10)
            if ran.errors.byte_length() != size:
                raise Error("boundary " + String(size) + " changed size")
            _ = reduce_text(ran.errors)
            var path = work + "/boundary-" + String(size) + ".txt"
            Path(path).write_text(ran.errors)
            _ = _must([work + "/analyze", path], 10)
        for size in [511, 512]:
            var ran = _must([work + "/boundary", "-" + String(size)], 10)
            if ran.errors.byte_length() != size or not ran.errors.startswith(
                "COVLINE:"
            ):
                raise Error("hit boundary changed")
            Path(work + "/hit-boundary-" + String(size) + ".txt").write_text(
                ran.errors
            )
        var refused = run_program(
            [work + "/boundary", "-513"], 10, merge_errors=False
        )
        if refused.status == 0 or refused.errors.find("COVLINE:") >= 0:
            raise Error(refused.errors)
        var concurrent = _must([work + "/boundary", "0"], 10)
        var records = _keep_newlines(concurrent.errors)
        if len(records) != 800:
            raise Error("concurrent boundary record count changed")
        for record in records:
            if record.byte_length() != 512:
                raise Error("concurrent boundary record size changed")
        var reduced_concurrent = reduce_text(concurrent.errors)
        if len(_keep_newlines(reduced_concurrent)) != 1:
            raise Error("concurrent boundary did not reduce to one record")
        Path(work + "/boundary-concurrent.txt").write_text(concurrent.errors)
        _ = _must([work + "/analyze", work + "/boundary-concurrent.txt"], 10)
        var oversized = run_program(
            [work + "/boundary", "513"], 10, merge_errors=False
        )
        if oversized.status == 0 or oversized.errors.find("COVEVAL2:") >= 0:
            raise Error(oversized.errors)
        Path(work + "/boundary-513-status.txt").write_text(
            String(oversized.status) + "\n"
        )
        for mode in ["-1", "512"]:
            var stdout_path = work + "/closed-" + mode + ".out"
            var status = _exec_prepared(
                [work + "/boundary", mode],
                _open_write(stdout_path),
                -1,
                True,
                False,
            )
            if status != -6:
                raise Error(
                    "closed stderr status " + String(status) + " for " + mode
                )
            var short_path = work + "/short-" + mode + ".txt"
            var short_status = _exec_prepared(
                [work + "/boundary", mode],
                _open_write(work + "/short-" + mode + ".out"),
                _open_write(short_path),
                False,
                True,
            )
            if short_status == 0:
                raise Error("short write was accepted")
            if len(Path(short_path).read_bytes()) != 10:
                raise Error("short write length changed")
        var short_analyze = run_program(
            [work + "/analyze", work + "/short-512.txt"], 10, merge_errors=False
        )
        if short_analyze.status == 0:
            raise Error("short write became an accepted vector")
        var library = work + "/write-interposer.so"
        var flags = List[String]()
        if _linux():
            flags.append("-shared")
            flags.append("-fPIC")
        else:
            library = work + "/write-interposer.dylib"
            flags.append("-dynamiclib")
        var compile = List[String]()
        compile.append("cc")
        compile.append("-Wall")
        compile.append("-Wextra")
        compile.append("-Werror")
        for flag in flags:
            compile.append(flag)
        compile.append(root + "/tools/coverage_write_interposer.c")
        compile.append("-o")
        compile.append(library)
        compile.append("-ldl")
        _ = _must(compile, 30)
        var preload = "LD_PRELOAD" if _linux() else "DYLD_INSERT_LIBRARIES"
        for size in ["512", "-512"]:
            var expected_bytes = _must([work + "/boundary", size], 10).errors
            for mode in ["passthrough", "eintr", "error", "short", "zero"]:
                var ran = run_program(
                    _with_env(
                        [
                            preload + "=" + library,
                            "THREEMOJO_WRITE_TEST=" + mode,
                        ],
                        [work + "/boundary", size],
                    ),
                    5,
                    merge_errors=False,
                )
                if mode == "passthrough" or mode == "eintr":
                    if ran.status != 0 or ran.errors != expected_bytes:
                        raise Error(mode + "\n" + ran.errors)
                else:
                    if ran.status != 128 + 6 and ran.status != -6:
                        raise Error(mode + " status " + String(ran.status))
            _interrupt_pipe(work + "/boundary", size, library, preload)
        if output.byte_length() > 0:
            _ = _must(["mkdir", "-p", output], 10)
            for name in listdir(work):
                if name.endswith(".txt"):
                    _ = _must(
                        ["cp", "-a", work + "/" + name, output + "/" + name],
                        10,
                    )
            _ = _must(
                [
                    "cp",
                    "-a",
                    native + "/fixture.mojo",
                    output + "/native.mojo",
                ],
                10,
            )
            _ = _must(
                [
                    "cp",
                    "-a",
                    rewritten + "/fixture.mojo",
                    output + "/instrumented.mojo",
                ],
                10,
            )
            _ = _must(
                [
                    "cp",
                    "-a",
                    rewritten + "/manifest.txt",
                    output + "/manifest.txt",
                ],
                10,
            )
        print(
            "PASS: recursive and caught-inner-exception vectors, same-frame"
            " abandonment, while/elif/continue/else, nested callbacks, new"
            " evaluation-name/type shadowing, 5 real-pipe 8-task captures,"
            " exact raw/reduced vectors, UTF-8 511/512-byte writes and"
            " 513-byte refusal, standalone EBADF errno access, repeated EINTR"
            " and real-signal recovery, strict write-error refusal"
        )
    finally:
        _ = run_program(["rm", "-rf", work], 30)


def _fail(text: String):
    """Print `text` and stop with status 2."""
    print("check_coverage_protocol: " + text, file=stderr)
    exit(2)


def main() raises:
    """Check coverage protocol behavior from the command line."""
    var mojo = ".venv/bin/mojo"
    var output = String()
    var given = argv()
    var index = 1
    while index < len(given):
        var word = String(given[index])
        if word == "--mojo" or word == "--output":
            if index + 1 >= len(given):
                _fail(word + " needs a value")
            var value = String(given[index + 1])
            if word == "--mojo":
                mojo = value
            else:
                output = value
            index += 2
            continue
        _fail("unknown argument " + word)
    try:
        check(mojo, output)
    except error:
        print(String(error), file=stderr)
        exit(1)
