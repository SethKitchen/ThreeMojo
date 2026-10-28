# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Capture one instrumented suite and keep each probe record once.

    coverage_io capture --out SUITE.out --err SUITE.txt.gz -- COMMAND...

The command runs in its own session. Its standard error is reduced: each
`COVLINE` payload, each branch, and each complete `COVEVAL2` record is kept
once. A passed group deadline, SIGINT, SIGTERM, or SIGHUP stops the session.
It prints the start, the first probe, a running line every 60 seconds, and completion. A failed
capture prints the last 30 lines of standard output and the last 30
standard-error lines that do not start with `COV`. A compiled capture
writes a phase file and reports a missing finish record.

Each capture creates a private temporary directory. Its parent is the
resolved `TMPDIR` when that variable is set. The command sees the directory
as `TMPDIR` and as `THREEMOJO_TEST_TMPDIR`. The compiler cache is inside
the directory. The tool removes the directory after any outcome. An archive path
that cannot be written stops the session.
"""

from std.collections import Dict
from std.ffi import c_int, external_call
from std.memory import OpaquePointer
from std.os import getenv, listdir, remove, setenv, unsetenv
from std.os.path import exists, realpath
from std.pathlib import Path
from std.sys import CompilationTarget, argv, exit, stderr
from std.tempfile import mkdtemp

from tools._carla_files import (
    fstat_id,
    lstat_id,
    make_temporary,
    o_nofollow_flag,
    o_nonblock,
    o_rdonly,
    os_error,
    read_some,
    remove_file,
    replace_file,
)
from tools._owned_process import (
    EPERM,
    ESRCH,
    SIGHUP,
    SIGINT,
    SIGKILL,
    SIGTERM,
    ExecPlan,
    SignalHold,
    SignalSet,
    at_cwd,
    c_bytes,
    close_fd,
    errno,
    hold_signals,
    make_pipe,
    mask_how_set,
    open_at,
    python_monotonic,
    signal_group,
    spawn,
    strerror,
    take_signal,
    try_wait,
    wait_blocking,
)
from tools._json_tools import quote_ascii
from tools._process import run_program, shell_quote
from tools._python_float import parse_float
from tools._python_json import MISSING, PY_BOOL, PY_STR, PyJson
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
        + " [--progress-seconds N] -- COMMAND..."
    )


def _now() -> Float64:
    """Return Python's `time.monotonic()` in seconds."""
    return python_monotonic()


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


def _require_archive(path: String) raises:
    """Create or truncate the archive while the captured command is alive.

    Args:
        path: The `.txt.gz` path.

    Raises:
        Error: If the path cannot be written. A directory is refused.
    """
    Path(path).write_text("")


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


def _compiled(command: List[String]) -> Bool:
    """Return whether `command` is an `aot` or `aot-hits` profile."""
    var profile = String()
    var named = False
    var index = 0
    while index < len(command):
        if command[index] == "coverage_hit_aot":
            named = True
        if command[index] == "--profile" and index + 1 < len(command):
            profile = command[index + 1]
        index += 1
    return named and (profile == "aot" or profile == "aot-hits")


def _file_stem(path: String) -> String:
    """Return `Path(path).stem`.

    Args:
        path: A path.

    Returns:
        The last component without its last suffix.
    """
    var slash = path.rfind("/")
    var name = path if slash < 0 else String(path[byte = slash + 1 :])
    var dot = name.rfind(".")
    if dot <= 0:
        return name
    return String(name[byte=:dot])


def _phases_path(out_path: String) raises -> String:
    """Return the absolute phase path beside `out_path`.

    Args:
        out_path: The standard-output file.

    Returns:
        `Path(out_path).with_suffix('.phases.jsonl').absolute()`. A link
        in the path stays unresolved.

    Raises:
        Error: If the working directory cannot be read.
    """
    var slash = out_path.rfind("/")
    var name = out_path if slash < 0 else String(out_path[byte = slash + 1 :])
    var head = "" if slash < 0 else String(out_path[byte = : slash + 1])
    var dot = name.rfind(".")
    var base = name
    if dot > 0:
        base = String(name[byte=:dot])
    var relative = head + base + ".phases.jsonl"
    if relative.startswith("/"):
        return relative
    var cwd = realpath(".")
    if cwd.endswith("/"):
        return cwd + relative
    return cwd + "/" + relative


def _unlink_name(path: String) raises:
    """Remove a file or symlink, as `Path.unlink(missing_ok=True)` does.

    Args:
        path: The path. A missing path stays missing.

    Raises:
        Error: With Python's `OSError` text when the name exists and
            cannot be removed.
    """
    try:
        remove_file(path)
    except error:
        var text = String(error)
        if text.find("No such file") < 0:
            raise error


def _exception_name(error: Error) -> String:
    """Return the class name at the start of `error`.

    Args:
        error: An error whose text starts with `Name:`.

    Returns:
        That name, or `OSError` when the text has none.
    """
    var text = String(error)
    var colon = text.find(":")
    if colon > 0:
        return String(text[byte=:colon])
    return "OSError"


def _header_json(suite: String, command: List[String]) -> String:
    """Return one phase header line, as `json.dumps` writes it.

    Args:
        suite: `Path(out_path).stem`.
        command: The captured command.

    Returns:
        The header object and its trailing newline.
    """
    var words = String("[")
    var index = 0
    for word in command:
        if index > 0:
            words += ", "
        words += quote_ascii(word)
        index += 1
    words += "]"
    var digest = sha256_hex(words.as_bytes())
    return (
        '{"schema": "coverage-exec-phases-v1", "suite": '
        + quote_ascii(suite)
        + ', "phase": "capture_header", "command_sha256": "'
        + digest
        + '", "semantics": "launch requests only; missing finish means'
        ' incomplete"}\n'
    )


def _universal_lines(text: String) -> List[String]:
    """Split text as a Python text-mode file does.

    Args:
        text: Decoded text.

    Returns:
        Each line. CR LF, CR and LF become LF. A final line with no break
        keeps its text.
    """
    var lines = List[String]()
    var bytes = text.as_bytes()
    var start = 0
    var index = 0
    var size = len(bytes)
    while index < size:
        var byte = bytes[index]
        if byte == 10 or byte == 13:
            lines.append(String(text[byte=start:index]) + "\n")
            index += 1
            if byte == 13 and index < size and bytes[index] == 10:
                index += 1
            start = index
            continue
        index += 1
    if start < size:
        lines.append(String(text[byte=start:size]))
    return lines^


def _last_text(lines: List[String], count: Int) -> String:
    """Join the last `count` lines.

    Args:
        lines: The lines. A line keeps its newline when it had one.
        count: How many lines to keep.

    Returns:
        The joined tail. It is empty when `lines` is empty.
    """
    var start = 0
    if len(lines) > count:
        start = len(lines) - count
    var out = String()
    while start < len(lines):
        out += lines[start]
        start += 1
    return out^


def _read_path(path: String) raises -> List[UInt8]:
    """Read every byte of a file.

    Args:
        path: The file.

    Returns:
        Its bytes.

    Raises:
        Error: If the file cannot be opened or read.
    """
    var fd = open_at(at_cwd(), c_bytes(path), 0)
    if fd < 0:
        raise Error("cannot read " + path + ": " + strerror(errno()))
    var out = List[UInt8]()
    try:
        while True:
            var block = read_some(fd, 4096)
            if len(block) == 0:
                break
            var index = 0
            while index < len(block):
                out.append(block[index])
                index += 1
    finally:
        close_fd(fd)
    return out^


def _failure_tail(
    command: List[String], out_path: String, reduced: String
) raises:
    """Print the last lines of a failed capture.

    Args:
        command: The captured command. The message names its last word.
        out_path: The standard-output file.
        reduced: The reduced standard error.

    Raises:
        Error: If the standard-output file cannot be read.
    """
    print(command[len(command) - 1] + " failed under instrumentation:")
    var raw = _read_path(out_path)
    print(
        _last_text(_universal_lines(String(from_utf8_lossy=Span(raw))), 30),
        end="",
    )
    var kept = List[String]()
    for line in _universal_lines(reduced):
        if not line.startswith("COV"):
            kept.append(line)
    print(_last_text(kept, 30), end="")


struct PhaseWatch(ImplicitlyCopyable, Movable):
    """The phase file a compiled capture must finish."""

    var path: String
    """The phase file, or empty when this capture keeps none."""
    var device: UInt64
    """The device recorded when the header was replaced into place."""
    var inode: UInt64
    """The inode recorded when the header was replaced into place."""
    var active: Bool
    """True when a header was published."""

    def __init__(out self):
        """Make an inactive watch."""
        self.path = ""
        self.device = 0
        self.inode = 0
        self.active = False


def _phase_header(command: List[String], out_path: String) -> PhaseWatch:
    """Replace the phase file when this capture is compiled.

    A raw capture still removes an old phase file. A write failure prints
    `phase diagnostics unavailable` and leaves the capture running.

    Args:
        command: The captured command.
        out_path: The standard-output file.

    Returns:
        The watch. It is inactive when this capture keeps no phases.
    """
    _ = unsetenv(_PHASE)
    _ = unsetenv(_PHASE + "_DEVICE")
    _ = unsetenv(_PHASE + "_INODE")
    var temporary = String()
    try:
        var path = _phases_path(out_path)
        _unlink_name(path)
        if not _compiled(command):
            return PhaseWatch()
        var slash = path.rfind("/")
        var directory = "." if slash < 0 else String(path[byte=:slash])
        if directory.byte_length() == 0:
            directory = "/"
        var name = path if slash < 0 else String(path[byte = slash + 1 :])
        temporary = make_temporary(directory, name + ".", "")
        Path(temporary).write_text(_header_json(_file_stem(out_path), command))
        var info = lstat_id(temporary)
        replace_file(temporary, path)
        _ = setenv(_PHASE, path, True)
        _ = setenv(_PHASE + "_DEVICE", String(info.device), True)
        _ = setenv(_PHASE + "_INODE", String(info.inode), True)
        var watch = PhaseWatch()
        watch.path = path
        watch.device = info.device
        watch.inode = info.inode
        watch.active = True
        return watch
    except error:
        if temporary.byte_length() > 0:
            try:
                remove_file(temporary)
            except:
                pass
        print(
            "Coverage "
            + _file_stem(out_path)
            + ": phase diagnostics unavailable ("
            + _exception_name(error)
            + "); ignore any existing phase file"
        )
        return PhaseWatch()


def _read_limit(fd: Int, limit: Int) raises -> List[UInt8]:
    """Read at most `limit` bytes, plus one when the file is longer.

    Args:
        fd: The descriptor.
        limit: The largest accepted size.

    Returns:
        The bytes read. One extra byte means the file is too long.

    Raises:
        Error: With Python's `OSError` text if a read fails.
    """
    var out = List[UInt8]()
    while len(out) <= limit:
        var block = read_some(fd, 4096)
        if len(block) == 0:
            return out^
        var index = 0
        while index < len(block) and len(out) <= limit:
            out.append(block[index])
            index += 1
    return out^


def _require_finish(watch: PhaseWatch) raises:
    """Raise unless the phase file still holds a complete finish record.

    Args:
        watch: The published header.

    Raises:
        Error: `OSError` when the file cannot be read, `JSONDecodeError`
            when the last line is not JSON, and `ValueError` when the
            finish record is missing or the file identity changed.
    """
    var flags = o_rdonly() | o_nonblock() | o_nofollow_flag()
    var fd = open_at(at_cwd(), c_bytes(watch.path), flags)
    if fd < 0:
        raise os_error(errno(), watch.path)
    var data: List[UInt8]
    try:
        var info = fstat_id(fd)
        if (
            not info.is_regular()
            or info.device != watch.device
            or info.inode != watch.inode
        ):
            raise Error("ValueError: phase file identity changed")
        data = _read_limit(fd, 128 * 1024)
    finally:
        close_fd(fd)
    if len(data) > 128 * 1024 or len(data) == 0 or data[len(data) - 1] != 10:
        raise Error("ValueError: phase file is incomplete")
    var text = String(from_utf8_lossy=Span(data))
    var parts = text.split("\n")
    if len(parts) < 2:
        raise Error("ValueError: phase file is incomplete")
    var last = String(parts[len(parts) - 2])
    var doc: PyJson
    try:
        doc = PyJson.parse(last)
    except error:
        raise Error("JSONDecodeError: " + String(error))
    var schema = doc.get(doc.root, "schema")
    var phase = doc.get(doc.root, "phase")
    var done = doc.get(doc.root, "diagnostics_complete")
    if (
        schema == MISSING
        or phase == MISSING
        or done == MISSING
        or doc.kind(schema) != PY_STR
        or doc.text(schema) != "coverage-exec-phases-v1"
        or doc.kind(phase) != PY_STR
        or doc.text(phase) != "adapter_finish"
        or doc.kind(done) != PY_BOOL
        or not doc.flag(done)
    ):
        raise Error("ValueError: no complete adapter finish")


def _finish_phases(watch: PhaseWatch):
    """Report a compiled capture whose phase file has no finish record.

    Args:
        watch: The header published for this capture. An inactive watch
            prints nothing.
    """
    if not watch.active:
        return
    try:
        _require_finish(watch)
    except error:
        print(
            "Coverage "
            + _file_stem(watch.path)
            + ": phase diagnostics incomplete ("
            + _exception_name(error)
            + "); last launch request is advisory"
        )


def _release_capture(folder: String) raises:
    """Remove the capture's private temporary root.

    Args:
        folder: The directory created for this capture.

    Raises:
        Error: If the removal command cannot start or remove the directory.
    """
    _ = unsetenv("TMPDIR")
    _ = unsetenv("THREEMOJO_TEST_TMPDIR")
    _ = unsetenv("MODULAR_CACHE_DIR")
    _ = unsetenv("XDG_CACHE_HOME")
    var removed = run_program(["rm", "-rf", folder], 30.0)
    if removed.status != 0:
        raise Error(removed.output)


def _start(
    command: List[String], output: Int, hold: SignalHold
) raises -> Tuple[Int, Int]:
    """Start `command` in a new session, with the first start's signal mask.

    The capture blocks its cancellation signals. The child must not inherit
    that block, or a `SIGTERM` that the command sends to itself waits until
    the command ends, and the command then reports success.

    Args:
        command: The program and its arguments.
        output: The standard-output descriptor.
        hold: The blocked cancellation signals.

    Returns:
        The process id and the standard-error read end.

    Raises:
        Error: If the program cannot start.
    """
    var plan = ExecPlan(command)
    var mask = hold.child_mask()
    var replaced = SignalSet()
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
        _ = external_call["pthread_sigmask", c_int](
            mask_how_set(),
            OpaquePointer[MutAnyOrigin](unsafe_from_address=mask.address()),
            OpaquePointer[MutAnyOrigin](unsafe_from_address=replaced.address()),
        )
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


def _emit(text: String):
    """Write `text` and a newline to standard output without buffering.

    Args:
        text: One progress line, without its newline.
    """
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    bytes.append(10)
    var pending = len(bytes)
    var sent = 0
    while sent < pending:
        var count = external_call["write", Int](
            Int32(1),
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(bytes.unsafe_ptr()) + sent
            ),
            pending - sent,
        )
        if count < 0:
            if errno() == 4:
                continue
            return
        if count == 0:
            return
        sent += count


def _progress(
    suite: String,
    stage: String,
    started: Float64,
    records: Int,
    saw_probe: Bool,
):
    """Print one capture progress line.

    Args:
        suite: The capture stem.
        stage: `start`, `running`, `first probe`, `complete`, or `aborted`.
        started: The monotonic time the capture started.
        records: How many standard-error lines have been read.
        saw_probe: True after the first coverage record.
    """
    var phase = "waiting for probes (compile/startup)"
    if saw_probe:
        phase = "runtime probes observed"
    _emit(
        "Coverage "
        + suite
        + ": "
        + stage
        + "; "
        + _tenth(_now() - started)
        + "s; "
        + phase
        + "; "
        + String(records)
        + " stderr records"
    )


def owned_group_kill(
    pid: Int,
    macos: Bool,
    live: Bool,
    script: List[Int],
    mut calls: List[Int],
    reap_ready: Bool,
    mut waits: Int,
) raises -> Bool:
    """Signal an owned group and accept Darwin EPERM only after it is gone.

    A successful signal or a missing group returns without reaping. On
    Darwin, EPERM can mean the leader is already a zombie. This call then
    reaps without waiting. Signal 0 must show the group is gone. Any other
    denial stays a denial, and this call does not send a second SIGKILL.

    Args:
        pid: The leader, started in its own session.
        macos: True to apply the Darwin EPERM rule.
        live: True to call `killpg` and `waitpid`. False reads `script`.
        script: One errno per signal. The last value repeats.
        calls: Each signal number this call sends.
        reap_ready: True when a scripted reap has an exit status.
        waits: Incremented when this call reaps.

    Returns:
        True when this call reaped the leader.

    Raises:
        Error: When the group is denied, still present, or the wait fails.
    """
    var failure = _group_errno(pid, SIGKILL, live, script, calls)
    if failure == 0 or failure == ESRCH:
        return False
    if not macos or failure != EPERM:
        raise Error(
            "PermissionError: [Errno " + String(failure) + "] kill denied"
        )
    waits += 1
    var ready = reap_ready
    if live:
        var state = try_wait(pid)
        if state.error != 0:
            raise Error("wait failed: " + strerror(state.error))
        ready = state.done
    if not ready:
        raise Error(
            "PermissionError: [Errno " + String(failure) + "] kill denied"
        )
    var probe = _group_errno(pid, 0, live, script, calls)
    if probe == ESRCH:
        return True
    raise Error("PermissionError: [Errno " + String(failure) + "] kill denied")


def _group_errno(
    pid: Int,
    number: Int,
    live: Bool,
    script: List[Int],
    mut calls: List[Int],
) -> Int:
    """Return the errno for one group signal.

    Args:
        pid: The process group.
        number: The signal, or zero to probe.
        live: True to call `killpg`.
        script: Scripted errno values. The last value repeats.
        calls: The signals already sent. This call appends `number`.

    Returns:
        Zero, or the errno.
    """
    calls.append(number)
    if not live:
        if len(script) == 0:
            return 0
        var index = len(calls) - 1
        if index >= len(script):
            index = len(script) - 1
        return script[index]
    return signal_group(pid, number)


def kill_owned_group(pid: Int) raises -> Bool:
    """Signal `pid`'s group. Return True when this call reaped the leader.

    Args:
        pid: The leader, started in its own session.

    Returns:
        True when Darwin EPERM ended in a completed reap.

    Raises:
        Error: When a live leader or a present group is denied.
    """
    var script = List[Int]()
    var calls = List[Int]()
    var waits = 0
    return owned_group_kill(
        pid, CompilationTarget.is_macos(), True, script, calls, False, waits
    )


def _reap_killed(pid: Int, reaped: Bool):
    """Reap `pid` when the kill did not already reap it.

    Args:
        pid: The session leader.
        reaped: True when the kill already reaped the leader.
    """
    if reaped:
        return
    _ = wait_blocking(pid)


def _stop_session(pid: Int, status: Int) raises -> Int:
    """Kill `pid`'s session and return `status`.

    Args:
        pid: The session leader.
        status: The status the capture reports.

    Returns:
        `status`.

    Raises:
        Error: When the group cannot be killed.
    """
    var reaped = kill_owned_group(pid)
    _reap_killed(pid, reaped)
    return status


def _await_child(pid: Int, deadline: Float64, hold: SignalHold) raises -> Int:
    """Wait for `pid`, a deadline, or a cancellation signal.

    Args:
        pid: The session leader.
        deadline: The monotonic deadline, or a negative value when none is set.
        hold: The blocked cancellation signals.

    Returns:
        The child's status, 124 at the deadline, or 128 plus a signal.

    Raises:
        Error: When the wait fails or the group cannot be killed.
    """
    while True:
        var number = take_signal(hold)
        if number != 0:
            return _stop_session(pid, 128 + number)
        if deadline >= 0 and _now() >= deadline:
            return _stop_session(pid, 124)
        var waited = try_wait(pid)
        if waited.error != 0:
            raise Error("wait failed: " + strerror(waited.error))
        if waited.done:
            if waited.status < 0:
                return 128 - waited.status
            return waited.status
        _ = external_call["usleep", c_int](UInt32(20000))


def _read_lines(
    pid: Int,
    fd: Int,
    mut reducer: Reducer,
    deadline: Float64,
    started: Float64,
    suite: String,
    interval: Float64,
    hold: SignalHold,
    err_path: String,
) raises -> Int:
    """Read the child's standard error until it ends or the deadline passes.

    Args:
        pid: The session leader.
        fd: The standard-error read end.
        reducer: The probe reducer.
        deadline: The monotonic deadline, or a negative value when none is set.
        started: The monotonic time the capture started.
        suite: The capture stem, used in progress lines.
        interval: The seconds between running lines.
        hold: The blocked cancellation signals.
        err_path: The archive. The first reduced line creates it.

    Returns:
        The child's status, 124 when the deadline wins, or 128 plus a signal.

    Raises:
        Error: If a probe record is malformed, the archive cannot be
            written, or the wait fails. The session is stopped before
            that error leaves this function.
    """
    var poll = List[Int32](length=2, fill=0)
    var chunk = List[UInt8](length=4096, fill=0)
    var pending = String()
    var announced = False
    var next_progress = started + interval
    var pipe_open = True
    var archive_ready = False
    var before = 0
    try:
        while True:
            var number = take_signal(hold)
            if number != 0:
                if pipe_open:
                    close_fd(fd)
                    pipe_open = False
                return _stop_session(pid, 128 + number)
            if _now() >= next_progress:
                _progress(
                    suite,
                    "running",
                    started,
                    reducer.records,
                    reducer.saw_probe,
                )
                next_progress = _now() + interval
            var limit = 0.05
            if deadline >= 0:
                limit = deadline - _now()
                if limit <= 0:
                    if pipe_open:
                        close_fd(fd)
                        pipe_open = False
                    return _stop_session(pid, 124)
                if limit > 0.05:
                    limit = 0.05
            var until_progress = next_progress - _now()
            if until_progress < limit:
                limit = until_progress
            if limit < 0.001:
                limit = 0.001
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
                before = reducer.output.byte_length()
                reducer.feed(line)
                if not archive_ready and reducer.output.byte_length() != before:
                    _require_archive(err_path)
                    archive_ready = True
                if not announced and reducer.saw_probe:
                    announced = True
                    _progress(
                        suite, "first probe", started, reducer.records, True
                    )
        if pending.byte_length() > 0:
            before = reducer.output.byte_length()
            reducer.feed(pending)
            if not archive_ready and reducer.output.byte_length() != before:
                _require_archive(err_path)
            if not announced and reducer.saw_probe:
                _progress(suite, "first probe", started, reducer.records, True)
        if pipe_open:
            close_fd(fd)
            pipe_open = False
        return _await_child(pid, deadline, hold)
    except error:
        if pipe_open:
            close_fd(fd)
        try:
            _ = _stop_session(pid, 1)
        except:
            pass
        raise error


def _capture(arguments: List[String], hold: SignalHold) raises -> Int:
    """Run one capture described by `arguments`.

    Args:
        arguments: The arguments after `capture`, without the program name.
        hold: The blocked cancellation signals.

    Returns:
        The captured command's status.

    Raises:
        Error: If the command line, a probe record, or the private
            directory is wrong.
    """
    var out_path = String()
    var err_path = String()
    var interval = 60.0
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
        if word == "--out" or word == "--err":
            if index + 1 >= len(arguments):
                raise Error(word + " needs a value")
            if word == "--out":
                out_path = arguments[index + 1]
            else:
                err_path = arguments[index + 1]
            index += 2
            continue
        if word == "--progress-seconds":
            if index + 1 >= len(arguments):
                raise Error(word + " needs a value")
            interval = parse_float(arguments[index + 1])
            index += 2
            continue
        if word.startswith("--progress-seconds="):
            interval = parse_float(String(word[byte=19:]))
            index += 1
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
    if not (interval == interval) or interval <= 0 or interval > 1e300:
        raise Error("progress interval must be positive")
    var deadline = Float64(-1)
    var text = getenv(_DEADLINE, "")
    if text.byte_length() > 0:
        deadline = parse_float(text)
        if not (deadline == deadline) or deadline > 1e300 or deadline < -1e300:
            raise Error("coverage deadline must be finite")
    var parent = getenv("TMPDIR")
    var folder: String
    if parent:
        folder = mkdtemp(prefix="threemojo-test-", dir=parent)
    else:
        folder = mkdtemp(prefix="threemojo-test-")
    var private: String
    try:
        private = realpath(folder)
    except error:
        _ = run_program(["rm", "-rf", folder], 30.0)
        raise error
    var compiler = private + "/mojo-cache"
    var xdg = private + "/xdg-cache"
    var made = run_program(["mkdir", "-p", compiler, xdg], 10.0)
    if made.status != 0:
        _ = run_program(["rm", "-rf", folder], 30.0)
        raise Error(made.output)
    _ = setenv("TMPDIR", private, True)
    _ = setenv("THREEMOJO_TEST_TMPDIR", private, True)
    _ = setenv("MODULAR_CACHE_DIR", compiler, True)
    _ = setenv("XDG_CACHE_HOME", xdg, True)
    var started = _now()
    var suite = _stem(out_path)
    _progress(suite, "start", started, 0, False)
    var records = 0
    var saw_probe = False
    var reduced = String()
    var watch = _phase_header(command, out_path)
    var status = 124
    try:
        if deadline >= 0 and _now() >= deadline:
            Path(out_path).write_text("")
            _gzip("", err_path)
        else:
            var output = _open_output(out_path)
            var child = _start(command, output, hold)
            var reducer = Reducer()
            status = _read_lines(
                child[0],
                child[1],
                reducer,
                deadline,
                started,
                suite,
                interval,
                hold,
                err_path,
            )
            records = reducer.records
            saw_probe = reducer.saw_probe
            reduced = reducer.output
            _gzip(reduced, err_path)
        _progress(
            suite,
            "complete (exit " + String(status) + ")",
            started,
            records,
            saw_probe,
        )
        if status != 0:
            _failure_tail(command, out_path, reduced)
    except error:
        _progress(suite, "aborted", started, records, saw_probe)
        _finish_phases(watch)
        _release_capture(folder)
        raise error
    _finish_phases(watch)
    _release_capture(folder)
    return status


def _sort_paths(mut names: List[String]):
    """Sort paths in byte order."""
    var index = 1
    while index < len(names):
        var item = names[index]
        var place = index
        while place > 0 and names[place - 1] > item:
            names[place] = names[place - 1]
            place -= 1
        names[place] = item
        index += 1


def _captures(directory: String) raises -> List[String]:
    """Return the `.txt.gz` captures in `directory`, in byte order.

    Args:
        directory: The capture directory.

    Returns:
        The capture paths.

    Raises:
        Error: If the directory cannot be read, or it has no captures.
    """
    var names = List[String]()
    for name in listdir(directory):
        var text = String(name)
        if text.endswith(".txt.gz"):
            names.append(directory + "/" + text)
    if len(names) == 0:
        raise Error("no coverage captures were found")
    _sort_paths(names)
    return names^


def _fifo(path: String) raises:
    """Create a FIFO at `path`.

    Args:
        path: The FIFO path.

    Raises:
        Error: If `mkfifo` fails.
    """
    var name = c_bytes(path)
    if (
        external_call["mkfifo", c_int](
            OpaquePointer[MutAnyOrigin](
                unsafe_from_address=Int(name.unsafe_ptr())
            ),
            c_int(420),
        )
        != 0
    ):
        raise Error("cannot create " + path + ": " + strerror(errno()))


def _open_reader(path: String, pid: Int, mut reaped: List[Int]) raises -> Int:
    """Open a FIFO for writing once its reader is waiting.

    Args:
        path: The FIFO.
        pid: The reporter. A finished reporter ends the wait.
        reaped: Set to the reporter status when `try_wait` reaps it.

    Returns:
        The write descriptor, or -1 when the reporter has finished.

    Raises:
        Error: If the open fails for a reason other than a missing reader.
    """
    var flags = 1 | 0x800
    if not CompilationTarget.is_linux():
        flags = 1 | 4
    var spins = 0
    while spins < 1000:
        var waited = try_wait(pid)
        if waited.done:
            var code = waited.status
            if code < 0:
                code = 128 - code
            reaped[0] = code
            return -1
        var probe = open_at(at_cwd(), c_bytes(path), flags)
        if probe >= 0:
            # Open the blocking end while the probe still holds the FIFO. A
            # reader that reads while no writer holds it sees the end of the
            # file and moves to the next FIFO, and this open would then wait
            # for it forever.
            var fd = open_at(at_cwd(), c_bytes(path), 1)
            close_fd(probe)
            return fd
        if errno() != 6:
            raise Error("cannot open " + path + ": " + strerror(errno()))
        _ = external_call["usleep", c_int](UInt32(10000))
        spins += 1
    raise Error("the reporter did not open " + path)


def _replay(command: List[String], captures: List[String]) raises -> Int:
    """Feed each capture through a FIFO, in order, to `command`.

    Args:
        command: The reporter.
        captures: The gzip captures, already sorted.

    Returns:
        The reporter's status, or 1 when a capture cannot be replayed.

    Raises:
        Error: If a FIFO cannot be created.
    """
    var folder = mkdtemp(prefix="threemojo-coverage-")
    var pipes = List[String]()
    var index = 0
    while index < len(captures):
        var path = folder + "/" + String(index)
        _fifo(path)
        pipes.append(path)
        index += 1
    var reporter = List[String]()
    for word in command:
        reporter.append(word)
    for path in pipes:
        reporter.append(path)
    var pid = spawn(reporter, SignalHold(), -1, False)
    var reaped = List[Int]()
    reaped.append(-1)
    var failed = False
    index = 0
    while index < len(pipes):
        var fd = _open_reader(pipes[index], pid, reaped)
        if fd < 0:
            break
        var gzip_pid = spawn(
            ["gzip", "-dc", captures[index]], SignalHold(), fd, False
        )
        var gzip_done = wait_blocking(gzip_pid)
        close_fd(fd)
        if not gzip_done.done or gzip_done.status != 0:
            failed = True
            _ = signal_group(pid, SIGKILL)
            break
        index += 1
    if reaped[0] >= 0:
        _ = run_program(["rm", "-rf", folder], 30.0)
        return reaped[0]
    var done = wait_blocking(pid)
    _ = run_program(["rm", "-rf", folder], 30.0)
    if failed:
        print("Coverage replay failed", file=stderr)
        return 1
    if not done.done:
        raise Error("wait failed: " + strerror(done.error))
    if done.status < 0:
        return 128 - done.status
    return done.status


def _report(arguments: List[String]) raises -> Int:
    """Replay captures for one report command.

    Args:
        arguments: The arguments after `report`.

    Returns:
        The reporter's status.

    Raises:
        Error: If the command line is wrong.
    """
    var directory = String()
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
        if word == "--capture-dir" and index + 1 < len(arguments):
            directory = arguments[index + 1]
            index += 2
            continue
        if word == "--help" or word == "-h":
            break
        raise Error("unknown argument " + word)
    if directory.byte_length() == 0 or len(command) == 0:
        raise Error("usage: coverage_io report --capture-dir DIR -- COMMAND...")
    return _replay(command, _captures(directory))


def main() raises:
    """Capture one suite, or replay captures to the reporter."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        if len(arguments) == 0:
            raise Error(_usage())
        var rest = List[String]()
        for index in range(1, len(arguments)):
            rest.append(arguments[index])
        if arguments[0] == "capture":
            var signals = List[Int]()
            signals.append(SIGHUP)
            signals.append(SIGINT)
            signals.append(SIGTERM)
            var hold = hold_signals(signals)
            exit(_capture(rest, hold))
        if arguments[0] == "report":
            exit(_report(rest))
        raise Error(_usage())
    except error:
        print("coverage_io: " + String(error), file=stderr)
        var text = String(error)
        if text.startswith("usage:"):
            exit(2)
        exit(1)
