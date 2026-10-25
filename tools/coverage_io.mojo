# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Capture one instrumented suite and keep each probe record once.

    coverage_io capture --out SUITE.out --err SUITE.txt.gz -- COMMAND...

The command runs in its own session. Its standard error is reduced: each
`COVLINE` payload, each branch, and each complete `COVEVAL2` record is kept
once. A passed group deadline stops the session. When `--loop-proof` is
set, `tools/coverage_io.py` still checks and binds that receipt.
"""

from std.collections import Dict
from std.ffi import c_int, external_call
from std.memory import OpaquePointer
from std.os import getenv, remove, setenv, unsetenv
from std.pathlib import Path
from std.sys import CompilationTarget, argv, exit, stderr
from std.tempfile import mkdtemp

from tools._carla_files import lstat_id
from tools._owned_process import (
    SIGKILL,
    ExecPlan,
    at_cwd,
    c_bytes,
    close_fd,
    errno,
    make_pipe,
    open_at,
    signal_group,
    strerror,
    wait_blocking,
)
from tools._json_tools import quote_ascii
from tools._process import run_program, shell_quote
from tools._python_float import parse_float
from tools._sha256 import sha256_hex

comptime _LINE = "COVLINE:"
comptime _BRANCH = "COVBRANCH:"
comptime _EVAL = "COVEVAL2:"
comptime _MAX_RECORD = 512
comptime _CAPACITY = 4096
comptime _WINDOW = 1024
comptime _BYPASS = 16384
comptime _DEADLINE = "THREEMOJO_COVERAGE_DEADLINE"
comptime _PHASE = "THREEMOJO_COVERAGE_PHASES"


def _usage() -> String:
    """Return the usage line."""
    return (
        "usage: coverage_io capture --out FILE --err FILE"
        + " [--loop-proof FILE] [--loop-proof-root DIR] -- COMMAND..."
    )


def _now() -> Float64:
    """Return `CLOCK_MONOTONIC` in seconds."""
    var sample = List[Int64](length=2, fill=0)
    _ = external_call["clock_gettime", Int32](
        Int32(1), sample.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    return Float64(Int(sample[0])) + Float64(Int(sample[1])) / 1000000000.0


def _tenth(value: Float64) -> String:
    """Return `value` with one decimal place, half up."""
    var scaled = value * 10.0
    if scaled < 0:
        scaled -= 0.5
    else:
        scaled += 0.5
    var digits = Int(scaled)
    var whole = digits // 10
    var frac = digits - whole * 10
    if frac < 0:
        frac = -frac
    return String(whole) + "." + String(frac)


def _stem(path: String) -> String:
    """Return the file name of `path` without a trailing `.out`."""
    var base = path
    var slash = base.rfind("/")
    if slash >= 0:
        var tail = String(base[byte = slash + 1 :])
        base = tail
    if base.endswith(".out"):
        var end = base.byte_length() - 4
        var shortened = String(base[byte=:end])
        base = shortened
    return base


def _strip(text: String) -> String:
    """Return `text` without leading or trailing ASCII whitespace."""
    var bytes = text.as_bytes()
    var start = 0
    var end = len(bytes)
    while start < end:
        var byte = bytes[start]
        if (
            byte != 9
            and byte != 10
            and byte != 11
            and byte != 12
            and byte != 13
            and byte != 32
        ):
            break
        start += 1
    while end > start:
        var byte = bytes[end - 1]
        if (
            byte != 9
            and byte != 10
            and byte != 11
            and byte != 12
            and byte != 13
            and byte != 32
        ):
            break
        end -= 1
    return String(text[byte=start:end])


def _rpartition(text: String, mark: String) -> Tuple[String, String, String]:
    """Split `text` on the last `mark`, as `str.rpartition` does."""
    var at = text.rfind(mark)
    if at < 0:
        return (String(""), String(""), text)
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + mark.byte_length() :])
    return (head, mark, tail)


def _digits(text: String) -> Bool:
    """Return whether `text` is a positive decimal integer."""
    if text.byte_length() == 0:
        return False
    for byte in text.as_bytes():
        if byte < 48 or byte > 57:
            return False
    return True


struct Reducer:
    """The distinct probe records from one suite."""

    var output: String
    """The reduced standard error."""
    var payloads: Dict[String, Int]
    """`COVLINE` payloads already written."""
    var evaluations: Dict[String, Int]
    """Branch and evaluation keys already written."""
    var accepted: Dict[String, Int]
    """Raw lines remembered while reuse stays high."""
    var accepted_count: Int
    """How many raw lines `accepted` holds."""
    var remaining: Int
    """Lines left in the current sample window."""
    var hits: Int
    """Exact cache hits in the current window."""
    var bypassing: Bool
    """True while a cold window skips the cache."""
    var records: Int
    """How many raw lines were fed."""
    var saw_probe: Bool
    """True after the first coverage record."""

    def __init__(out self):
        """Make an empty reducer."""
        self.output = ""
        self.payloads = Dict[String, Int]()
        self.evaluations = Dict[String, Int]()
        self.accepted = Dict[String, Int]()
        self.accepted_count = 0
        self.remaining = _WINDOW
        self.hits = 0
        self.bypassing = False
        self.records = 0
        self.saw_probe = False

    def _write(mut self, text: String):
        """Append `text` to the reduced stream."""
        self.output += text

    def _payload(mut self, payload: String):
        """Write one `COVLINE` payload the first time it appears."""
        if not payload in self.payloads:
            self.payloads[payload] = 1
            self._write(_LINE + payload + "\n")

    def _remember(mut self, line: String):
        """Remember one accepted raw line while the cache has room."""
        if line.byte_length() > _MAX_RECORD or not line.endswith("\n"):
            return
        var record = _strip(line)
        var useful = (
            record.startswith(_LINE)
            or record.startswith(_EVAL)
            or (
                record.startswith(_BRANCH)
                and record.find(":") >= _BRANCH.byte_length()
            )
        )
        if not useful:
            return
        if self.accepted_count >= _CAPACITY:
            self.accepted = Dict[String, Int]()
            self.accepted_count = 0
        if not line in self.accepted:
            self.accepted[line] = 1
            self.accepted_count += 1

    def _window(mut self):
        """Start the next sample window, or a bypass after a cold one."""
        if self.bypassing:
            self.bypassing = False
            self.remaining = _WINDOW
        elif self.hits * 4 < _WINDOW:
            self.accepted = Dict[String, Int]()
            self.accepted_count = 0
            self.bypassing = True
            self.remaining = _BYPASS
        else:
            self.remaining = _WINDOW
        self.hits = 0

    def _evidence(mut self, line: String) raises:
        """Reduce one raw line."""
        var record = _strip(line)
        if record.startswith(_LINE):
            self._payload(String(record[byte = _LINE.byte_length() :]))
            return
        if record.startswith(_EVAL):
            if (
                record.byte_length() + 1 > _MAX_RECORD
                or not record.endswith(";")
                or not line.endswith("\n")
            ):
                raise Error("Malformed or truncated evaluation record")
            var body = String(
                record[byte = _EVAL.byte_length() : record.byte_length() - 1]
            )
            var head = _rpartition(body, ":")
            var decision = _rpartition(head[0], ":")
            var module = _rpartition(decision[0], ":")
            if decision[1] == "" or (decision[2] != "T" and decision[2] != "F"):
                raise Error("Malformed evaluation outcome")
            if (
                module[1] == ""
                or module[0].byte_length() == 0
                or not _digits(module[2])
                or module[2] == "0"
            ):
                raise Error("Malformed evaluation decision ID")
            if head[2].find("?") >= 0:
                raise Error("Inconsistent repeated truth conversion")
            if head[1] == "" or head[2].byte_length() < 2:
                raise Error("Malformed evaluation vector")
            var saw = False
            for byte in head[2].as_bytes():
                if byte != 84 and byte != 70 and byte != 45:
                    raise Error("Malformed evaluation vector")
                if byte == 84 or byte == 70:
                    saw = True
            if not saw:
                raise Error("Malformed evaluation vector")
            var key = decision[0] + "\n" + head[2] + "\n" + decision[2]
            if not key in self.evaluations:
                self.evaluations[key] = 1
                self._write(record + "\n")
            return
        if not record.startswith(_BRANCH):
            self._write(line)
            return
        var payload = String(record[byte = _BRANCH.byte_length() :])
        var parts = _rpartition(payload, ":")
        if parts[1] != "" and parts[2] != "T" and parts[2] != "F":
            raise Error("Malformed branch outcome")
        if parts[1] == "":
            self._write(line)
            return
        if parts[0].find(".") >= 0:
            raise Error("Legacy compound coverage is ambiguous")
        var module = _rpartition(parts[0], ":")
        if (
            module[1] == ""
            or module[0].byte_length() == 0
            or not _digits(module[2])
            or module[2] == "0"
        ):
            raise Error("Malformed branch decision ID")
        self._payload(payload)
        var key = parts[0] + "\n\n" + parts[2]
        if not key in self.evaluations:
            self.evaluations[key] = 1
            self._write(record + "\n")

    def feed(mut self, line: String) raises:
        """Reduce one raw line, using the bounded reuse cache.

        Args:
            line: One standard-error line, including its newline when the
                program wrote one.

        Raises:
            Error: If a probe record is malformed.
        """
        self.records += 1
        var probe = _strip(line)
        if (
            probe.startswith(_LINE)
            or probe.startswith(_BRANCH)
            or probe.startswith(_EVAL)
        ):
            self.saw_probe = True
        if self.remaining == 0:
            self._window()
        self.remaining -= 1
        if self.bypassing:
            self._evidence(line)
            return
        if line in self.accepted:
            self.hits += 1
            return
        self._evidence(line)
        self._remember(line)


def _open_output(path: String) raises -> Int:
    """Create or truncate `path` and return its descriptor.

    Args:
        path: The standard-output file.

    Returns:
        The descriptor.

    Raises:
        Error: If the file cannot be opened.
    """
    Path(path).write_text("")
    var flags = 1 | 512
    if not CompilationTarget.is_linux():
        flags = 1 | 0x400
    var fd = open_at(at_cwd(), c_bytes(path), flags)
    if fd < 0:
        raise Error("cannot open " + path + ": " + strerror(errno()))
    return fd


def _gzip(text: String, destination: String) raises:
    """Write `text` as a gzip file without a timestamp.

    Args:
        text: The reduced standard error.
        destination: The `.txt.gz` path.

    Raises:
        Error: If gzip cannot write the file.
    """
    var plain = destination + ".plain"
    Path(plain).write_text(text)
    var script = (
        "gzip -n -1 -c " + shell_quote(plain) + " > " + shell_quote(destination)
    )
    var ran = run_program(["sh", "-c", script], 30.0)
    remove(Path(plain))
    if ran.status != 0:
        raise Error("gzip failed: " + ran.output)


def _proof(
    mode: String,
    out_path: String,
    err_path: String,
    proof: String,
    root: String,
    command: List[String],
) raises:
    """Ask `tools/coverage_io.py` to check or bind the loop proof.

    Args:
        mode: `preflight` or `bind`.
        out_path: The standard-output file.
        err_path: The reduced capture.
        proof: The loop-proof receipt.
        root: The source root.
        command: The captured command.

    Raises:
        Error: If the proof check fails.
    """
    var arguments = List[String]()
    arguments.append("python3")
    arguments.append("tools/coverage_io.py")
    arguments.append(mode)
    arguments.append("--out")
    arguments.append(out_path)
    arguments.append("--err")
    arguments.append(err_path)
    arguments.append("--loop-proof")
    arguments.append(proof)
    arguments.append("--loop-proof-root")
    arguments.append(root)
    arguments.append("--")
    for word in command:
        arguments.append(word)
    var ran = run_program(arguments, 180.0, merge_errors=False)
    if ran.status != 0:
        var message = ran.errors
        if message.byte_length() == 0:
            message = ran.output
        raise Error(message)


def _compiled(command: List[String]) -> Bool:
    """Return whether `command` is an `aot` or `aot-hits` profile."""
    var profile = String()
    var named = False
    var index = 0
    while index < len(command):
        if (
            command[index] == "coverage_hit_aot"
            or command[index].endswith("/coverage_hit_aot.py")
            or command[index].endswith("coverage_hit_aot.py")
        ):
            named = True
        if command[index] == "--profile" and index + 1 < len(command):
            profile = command[index + 1]
        index += 1
    return named and (profile == "aot" or profile == "aot-hits")


def _phase_header(
    command: List[String], out_path: String, proof: String
) raises -> String:
    """Write the phase header when this capture is compiled.

    Args:
        command: The captured command.
        out_path: The standard-output file. The header replaces its
            `.phases.jsonl` neighbor.
        proof: The loop-proof path, or empty.

    Returns:
        The header path, or empty when this capture keeps no phases.

    Raises:
        Error: If the header cannot be written.
    """
    var path = out_path
    if path.endswith(".out"):
        var end = path.byte_length() - 4
        var shortened = String(path[byte=:end])
        path = shortened
    path += ".phases.jsonl"
    if Path(path).exists():
        remove(Path(path))
    if not _compiled(command):
        return ""
    var words = "["
    var index = 0
    for word in command:
        if index > 0:
            words += ", "
        words += quote_ascii(word)
        index += 1
    words += "]"
    var digest = sha256_hex(words.as_bytes())
    var proof_text = "null"
    if proof.byte_length() > 0:
        proof_text = '"' + proof + '"'
    var header = (
        '{"schema": "coverage-exec-phases-v1", "suite": "'
        + _stem(out_path)
        + '", "phase": "capture_header", "proof_sha256": '
        + proof_text
        + ', "command_sha256": "'
        + digest
        + '", "semantics": "launch requests only; missing finish means'
        ' incomplete"}\n'
    )
    Path(path).write_text(header)
    var info = lstat_id(path)
    _ = setenv(_PHASE, path, True)
    _ = setenv(_PHASE + "_DEVICE", String(info.device), True)
    _ = setenv(_PHASE + "_INODE", String(info.inode), True)
    return path


def _start(command: List[String], output: Int) raises -> Tuple[Int, Int]:
    """Start `command` in a new session.

    Args:
        command: The program and its arguments.
        output: The standard-output descriptor.

    Returns:
        The process id and the standard-error read end.

    Raises:
        Error: If the program cannot start.
    """
    var plan = ExecPlan(command)
    var errors = make_pipe()
    var report_pipe = make_pipe()
    var report = List[Int32](length=1, fill=0)
    var pid = Int(external_call["fork", c_int]())
    if pid == 0:
        _ = external_call["setsid", c_int]()
        _ = external_call["dup2", c_int](c_int(output), c_int(1))
        _ = external_call["dup2", c_int](c_int(errors[1]), c_int(2))
        close_fd(output)
        close_fd(errors[0])
        close_fd(errors[1])
        close_fd(report_pipe[0])
        report[0] = Int32(plan.run())
        _ = external_call["write", Int](
            Int32(report_pipe[1]),
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(report.unsafe_ptr())
            ),
            4,
        )
        external_call["_exit", NoneType](c_int(127))
    var fork_error = errno()
    close_fd(report_pipe[1])
    close_fd(errors[1])
    close_fd(output)
    if pid < 0:
        close_fd(errors[0])
        close_fd(report_pipe[0])
        raise Error("fork failed: " + strerror(fork_error))
    var got = 0
    while True:
        var count = external_call["read", Int](
            Int32(report_pipe[0]),
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(report.unsafe_ptr()) + got
            ),
            4 - got,
        )
        if count > 0:
            got += count
            if got == 4:
                break
            continue
        if count < 0 and errno() == 4:
            continue
        break
    close_fd(report_pipe[0])
    if got == 4:
        _ = wait_blocking(pid)
        close_fd(errors[0])
        raise Error(
            "cannot start " + command[0] + ": " + strerror(Int(report[0]))
        )
    return (pid, errors[0])


def _read_lines(
    pid: Int, fd: Int, mut reducer: Reducer, deadline: Float64, started: Float64
) raises -> Int:
    """Read the child's standard error until it ends or the deadline passes.

    Args:
        pid: The session leader.
        fd: The standard-error read end.
        reducer: The probe reducer.
        deadline: The monotonic deadline, or a negative value when none is set.
        started: The monotonic time the capture started.

    Returns:
        The child's status, or 124 when the deadline wins.

    Raises:
        Error: If a probe record is malformed or the wait fails.
    """
    var poll = List[Int32](length=2, fill=0)
    var chunk = List[UInt8](length=4096, fill=0)
    var pending = String()
    var records = 0
    var saw_probe = False
    var cancelled = False
    while True:
        var limit = 60.0
        if deadline >= 0:
            limit = deadline - _now()
            if limit <= 0:
                _ = signal_group(pid, SIGKILL)
                cancelled = True
                break
            if limit > 0.05:
                limit = 0.05
        poll[0] = Int32(fd)
        poll[1] = Int32(1)
        var ready = external_call["poll", c_int](
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(poll.unsafe_ptr())
            ),
            c_int(1),
            c_int(Int(limit * 1000.0) + 1),
        )
        if ready < 0:
            if errno() == 4:
                continue
            raise Error("poll failed: " + strerror(errno()))
        if ready == 0:
            continue
        var count = external_call["read", Int](
            Int32(fd),
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(chunk.unsafe_ptr())
            ),
            4096,
        )
        if count < 0:
            if errno() == 4:
                continue
            raise Error("read failed: " + strerror(errno()))
        if count == 0:
            break
        var raw = List[UInt8]()
        var offset = 0
        while offset < count:
            raw.append(chunk[offset])
            offset += 1
        var piece = String(from_utf8_lossy=Span(raw))
        pending += piece
        while True:
            var at = pending.find("\n")
            if at < 0:
                break
            var end = at + 1
            var line = String(pending[byte=:end])
            var rest = String(pending[byte=end:])
            pending = rest
            records += 1
            var probe = _strip(line)
            if not saw_probe and (
                probe.startswith(_LINE)
                or probe.startswith(_BRANCH)
                or probe.startswith(_EVAL)
            ):
                saw_probe = True
            reducer.feed(line)
        _ = records
        _ = started
        _ = saw_probe
    if pending.byte_length() > 0:
        records += 1
        reducer.feed(pending)
    close_fd(fd)
    var waited = wait_blocking(pid)
    if cancelled:
        return 124
    if not waited.done:
        raise Error("wait failed: " + strerror(waited.error))
    if waited.status < 0:
        return 128 - waited.status
    return waited.status


def _capture(arguments: List[String]) raises -> Int:
    """Run one capture described by `arguments`.

    Args:
        arguments: The arguments after `capture`, without the program name.

    Returns:
        The captured command's status.

    Raises:
        Error: If the command line, the proof, or a probe record is wrong.
    """
    var out_path = String()
    var err_path = String()
    var proof = String()
    var root = "."
    var command = List[String]()
    var index = 0
    while index < len(arguments):
        var word = arguments[index]
        if word == "--":
            index += 1
            while index < len(arguments):
                command.append(arguments[index])
                index += 1
            break
        if (
            word == "--out"
            or word == "--err"
            or word == "--loop-proof"
            or word == "--loop-proof-root"
        ):
            if index + 1 >= len(arguments):
                raise Error(word + " needs a value")
            var value = arguments[index + 1]
            if word == "--out":
                out_path = value
            elif word == "--err":
                err_path = value
            elif word == "--loop-proof":
                proof = value
            else:
                root = value
            index += 2
            continue
        if word == "--help" or word == "-h":
            raise Error(_usage())
        raise Error("unknown argument " + word)
    if (
        out_path.byte_length() == 0
        or err_path.byte_length() == 0
        or len(command) == 0
    ):
        raise Error(_usage())
    if proof.byte_length() > 0:
        _proof("preflight", out_path, err_path, proof, root, command)
    var deadline = Float64(-1)
    var text = getenv(_DEADLINE, "")
    if text.byte_length() > 0:
        deadline = parse_float(text)
        if not (deadline == deadline) or deadline > 1e300 or deadline < -1e300:
            raise Error("coverage deadline must be finite")
    var folder = mkdtemp(prefix="threemojo-test-")
    _ = setenv("TMPDIR", folder, True)
    _ = setenv("THREEMOJO_TEST_TMPDIR", folder, True)
    var compiler = folder + "/mojo-cache"
    var xdg = folder + "/xdg-cache"
    var made = run_program(["mkdir", "-p", compiler, xdg], 10.0)
    if made.status != 0:
        raise Error(made.output)
    _ = setenv("MODULAR_CACHE_DIR", compiler, True)
    _ = setenv("XDG_CACHE_HOME", xdg, True)
    _ = _phase_header(command, out_path, proof)
    var started = _now()
    print(
        "Coverage "
        + _stem(out_path)
        + ": start; 0.0s; waiting for probes (compile/startup); 0 stderr"
        " records"
    )
    var records = 0
    var saw_probe = False
    var status: Int
    if deadline >= 0 and _now() >= deadline:
        status = 124
        _gzip("", err_path)
    else:
        var output = _open_output(out_path)
        var child = _start(command, output)
        var reducer = Reducer()
        status = _read_lines(child[0], child[1], reducer, deadline, started)
        records = reducer.records
        saw_probe = reducer.saw_probe
        _gzip(reducer.output, err_path)
    var phase = "waiting for probes (compile/startup)"
    if saw_probe:
        phase = "runtime probes observed"
    print(
        "Coverage "
        + _stem(out_path)
        + ": complete (exit "
        + String(status)
        + "); "
        + _tenth(_now() - started)
        + "s; "
        + phase
        + "; "
        + String(records)
        + " stderr records"
    )
    if status == 0 and proof.byte_length() > 0:
        _proof("bind", out_path, err_path, proof, root, command)
    _ = unsetenv("TMPDIR")
    _ = unsetenv("THREEMOJO_TEST_TMPDIR")
    _ = run_program(["rm", "-rf", folder], 30.0)
    return status


def main() raises:
    """Capture one instrumented suite."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        if len(arguments) == 0 or arguments[0] != "capture":
            raise Error(_usage())
        var rest = List[String]()
        for index in range(1, len(arguments)):
            rest.append(arguments[index])
        exit(_capture(rest))
    except error:
        print("coverage_io: " + String(error), file=stderr)
        var text = String(error)
        if text.startswith("usage:"):
            exit(2)
        exit(1)
