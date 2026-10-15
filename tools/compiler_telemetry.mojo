# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Observe one CPU-suite compiler without changing its workload or time limit.

    compiler_telemetry --suite SUITE [--log-fd LOG_FD] [--] COMMAND...

Only THREEMOJO_COMPILER_TELEMETRY=1 on Linux enables sampling. Otherwise
the tool replaces itself with the command. When sampling, the tool reads
only the command's best-effort descendant tree and its readable cgroup-v2
OOM counters. It never reads command lines, environment, process memory,
stacks or unrelated processes, and it never changes resource limits.

The tool writes one JSON record per line to the log descriptor: a sample
when the compiler starts and every `INTERVAL` seconds, and a
`compiler-exit` record with the shell status. A logging failure cannot fail
the build. SIGINT, SIGTERM and SIGHUP go to the compiler's private process
group, and the tool exits with the compiler's shell status.
"""

from std.ffi import OwnedDLHandle, c_int, external_call
from std.memory import Pointer
from std.os import getenv
from std.os.path import realpath
from std.sys import CompilationTarget, argv, exit, stderr

from tools._owned_process import (
    ECHILD,
    ExecPlan,
    SIGHUP,
    SIGINT,
    SIGTERM,
    SignalHold,
    close_fd,
    exec_error_status,
    hold_signals,
    monotonic_seconds,
    nap,
    o_cloexec,
    o_directory,
    o_nofollow,
    at_cwd,
    c_bytes,
    errno,
    open_at,
    signal_group,
    spawn,
    strerror,
    take_signal,
    try_wait,
)
from tools._python_float import parse_float
from tools._python_json import PyJson, dumps_canonical, py_repr
from tools._python_math import float_sum, round_half_even
from tools._python_stats import format_fixed, true_divide

comptime INTERVAL = 60.0
"""The seconds between samples."""
comptime MAX_PROCESSES = 8
"""The most processes one sample reads."""
comptime MAX_THREADS = 32
"""The most threads one process's sample reads."""
comptime MAX_CHILDREN = 32
"""The most children one thread's sample follows."""
comptime MAX_LINE = 4096
"""The most bytes of one record."""
comptime OOM_KEYS = ["oom", "oom_kill", "oom_group_kill"]
"""The cgroup counters a record keeps."""
comptime OOM_FILES = ["memory.events", "memory.events.local"]
"""The cgroup files that hold the counters."""

comptime PROGRAM = "compiler_telemetry.mojo"
"""The program name in usage messages."""
comptime USAGE = (
    "usage: compiler_telemetry.mojo [-h] --suite SUITE [--log-fd LOG_FD] ...\n"
)
"""The usage line, as `argparse` writes it."""
comptime HELP = (
    "\nObserve one CPU-suite compiler without changing its workload or time"
    " limit.\n\npositional arguments:\n  command\n\noptions:\n  -h, --help  "
    "     show this help message and exit\n  --suite SUITE\n  --log-fd"
    " LOG_FD\n"
)
"""The help text after the usage line."""


# --- Python text rules -------------------------------------------------------


def _is_space(byte: UInt8) -> Bool:
    """Return whether an ASCII byte is whitespace to `str.split`."""
    return (
        byte == 0x20
        or (byte >= 0x09 and byte <= 0x0D)
        or (byte >= 0x1C and byte <= 0x1F)
    )


def py_split(text: String) -> List[String]:
    """Split at runs of whitespace, as Python's `str.split()` does.

    Args:
        text: ASCII text, where other characters are never whitespace.

    Returns:
        The words.
    """
    var out = List[String]()
    var bytes = text.as_bytes()
    var start = -1
    for i in range(len(bytes)):
        if _is_space(bytes[i]):
            if start >= 0:
                out.append(String(unsafe_from_utf8=Span(bytes)[start:i]))
                start = -1
        elif start < 0:
            start = i
    if start >= 0:
        out.append(String(unsafe_from_utf8=Span(bytes)[start:]))
    return out^


def py_strip_empty(text: String) -> Bool:
    """Return whether `text.strip()` is empty.

    Args:
        text: The text.

    Returns:
        True when every byte is whitespace.
    """
    for byte in text.as_bytes():
        if not _is_space(byte):
            return False
    return True


def is_decimal(text: String) -> Bool:
    """Return `text.isdecimal()` for text whose only digits are ASCII.

    Args:
        text: The text.

    Returns:
        True when the text is one or more ASCII digits.
    """
    if text.byte_length() == 0:
        return False
    for byte in text.as_bytes():
        if byte < 0x30 or byte > 0x39:
            return False
    return True


def py_int(text: String) raises -> Int:
    """Return `int(text)` for ASCII text.

    Args:
        text: The text: whitespace, a sign, and digits that single
            underscores can separate.

    Returns:
        The value.

    Raises:
        Error: As Python's `ValueError`, or when the value does not fit.
    """
    var bytes = text.as_bytes()
    var begin = 0
    var end = len(bytes)
    while begin < end and _is_space(bytes[begin]):
        begin += 1
    while end > begin and _is_space(bytes[end - 1]):
        end -= 1
    var negative = False
    if begin < end and (bytes[begin] == 0x2B or bytes[begin] == 0x2D):
        negative = bytes[begin] == 0x2D
        begin += 1
    if begin == end:
        raise Error("ValueError: invalid literal for int()")
    var value = 0
    var previous_digit = False
    for i in range(begin, end):
        var byte = bytes[i]
        if byte == 0x5F:
            if not previous_digit or i + 1 == end:
                raise Error("ValueError: invalid literal for int()")
            previous_digit = False
            continue
        if byte < 0x30 or byte > 0x39:
            raise Error("ValueError: invalid literal for int()")
        if value > (0x7FFFFFFFFFFFFFFF - 9) // 10:
            raise Error("OverflowError: int too large")
        value = value * 10 + Int(byte - 0x30)
        previous_digit = True
    return -value if negative else value


def ascii_text(bytes: Span[UInt8, _]) -> String:
    """Decode bytes as Python's `ascii` codec with `errors='replace'`.

    Args:
        bytes: The bytes.

    Returns:
        The text, with U+FFFD for each byte above 0x7F.
    """
    var out = List[UInt8](capacity=len(bytes))
    for byte in bytes:
        if byte < 0x80:
            out.append(byte)
        else:
            out.append(0xEF)
            out.append(0xBF)
            out.append(0xBD)
    return String(unsafe_from_utf8=out)


def round3(value: Float64) raises -> Float64:
    """Return Python's `round(value, 3)`.

    Args:
        value: A finite float.

    Returns:
        The float nearest to the value rounded to three decimals, with ties
        to even on the exact value.

    Raises:
        Error: If the value is not finite.
    """
    return parse_float(format_fixed(value, 3))


def _join(base: String, name: String) -> String:
    """Join two path parts as `pathlib` does for a relative name."""
    if name.startswith("/"):
        return name
    if base.byte_length() == 0 or base == ".":
        return name
    if base.endswith("/"):
        return base + name
    return base + "/" + name


# --- Paths -------------------------------------------------------------------


def _readlink(path: String) -> Optional[String]:
    """Return a symbolic link's target, or `None` for anything else."""
    var name = c_bytes(path)
    var buffer = List[UInt8](length=4097, fill=0)
    var count = external_call["readlink", Int](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(name.unsafe_ptr())),
        OpaquePointer[MutAnyOrigin](
            unsafe_from_address=Int(buffer.unsafe_ptr())
        ),
        4096,
    )
    if count < 0:
        return None
    buffer.resize(count, 0)
    return String(from_utf8_lossy=buffer)


def _cwd() raises -> String:
    """Return the current directory."""
    return realpath(".")


def _split_last(path: String) -> Tuple[String, String]:
    """Return `posixpath.split(path)`."""
    var at = path.rfind("/")
    var head = String(path[byte = : at + 1])
    var tail = String(path[byte = at + 1 :])
    if head.byte_length() > 0 and head != "/" * head.byte_length():
        while head.endswith("/"):
            var shorter = String(head[byte = : head.byte_length() - 1])
            head = shorter^
    return (head^, tail^)


def _join_real(
    var path: String, var rest: String, mut seen: Dict[String, String]
) raises -> Tuple[String, Bool]:
    """Follow `posixpath._joinrealpath` without `strict`."""
    if rest.startswith("/"):
        var tail = String(rest[byte=1:])
        rest = tail^
        path = "/"
    while rest.byte_length() > 0:
        var at = rest.find("/")
        var name: String
        if at < 0:
            name = rest
            rest = String()
        else:
            name = String(rest[byte=:at])
            var tail = String(rest[byte = at + 1 :])
            rest = tail^
        if name.byte_length() == 0 or name == ".":
            continue
        if name == "..":
            if path.byte_length() > 0:
                var parts = _split_last(path)
                path = parts[0]
                if parts[1] == "..":
                    path = _join(_join(path, ".."), "..")
            else:
                path = ".."
            continue
        var newpath = _join(path, name)
        var target = _readlink(newpath)
        if not target:
            path = newpath
            continue
        if newpath in seen:
            var known = seen[newpath]
            if known != "\x00":
                path = known
                continue
            return (newpath + "/" + rest, False)
        seen[newpath] = "\x00"
        var inner = _join_real(path, target.value(), seen)
        path = inner[0]
        if not inner[1]:
            return (path + "/" + rest, False)
        seen[newpath] = path
    return (path, True)


def normalize(path: String) -> String:
    """Return `posixpath.normpath` of an absolute path.

    Args:
        path: An absolute path.

    Returns:
        The path without empty, `.` and resolved `..` parts.
    """
    var parts = List[String]()
    for part in path.split("/"):
        var text = String(part)
        if text.byte_length() == 0 or text == ".":
            continue
        if text == "..":
            if len(parts) > 0:
                _ = parts.pop()
            continue
        parts.append(text)
    var out = String()
    for part in parts:
        out += "/" + part
    if out.byte_length() == 0:
        return "/"
    return out


def resolve(path: String) raises -> String:
    """Return `Path(path).resolve()`: the real path, as far as it exists.

    Args:
        path: The path.

    Returns:
        The absolute path with every existing symbolic link followed.

    Raises:
        Error: For a symbolic link loop, as `pathlib` raises one.
    """
    var start = path if path.startswith("/") else _join(_cwd(), path)
    var seen = Dict[String, String]()
    var result = _join_real(String(), start, seen)
    if not result[1]:
        raise Error("RuntimeError: Symlink loop from " + py_repr(result[0]))
    return normalize(result[0])


def _parts(path: String) -> List[String]:
    """Return the parts of a POSIX path after its root, as `PurePosixPath`."""
    var out = List[String]()
    for part in path.split("/"):
        var text = String(part)
        if text.byte_length() > 0 and text != ".":
            out.append(text)
    return out^


def relative_to(path: String, base: String) -> Optional[String]:
    """Return `PurePosixPath(path).relative_to(base)` for absolute paths.

    Args:
        path: An absolute path.
        base: An absolute path.

    Returns:
        The relative path, `.` for the same path, or `None` when `path` is
        not under `base`.
    """
    var mine = _parts(path)
    var theirs = _parts(base)
    if len(theirs) > len(mine):
        return None
    for i in range(len(theirs)):
        if mine[i] != theirs[i]:
            return None
    if len(mine) == len(theirs):
        return String(".")
    var out = String()
    for i in range(len(theirs), len(mine)):
        if out.byte_length() > 0:
            out += "/"
        out += mine[i]
    return out^


def _decode_mount(text: String) -> String:
    """Undo the octal escapes `\\040`, `\\011`, `\\012` and `\\134`."""
    var bytes = text.as_bytes()
    var out = List[UInt8]()
    var i = 0
    while i < len(bytes):
        if bytes[i] == 0x5C and i + 3 < len(bytes):
            var code = String(unsafe_from_utf8=Span(bytes)[i + 1 : i + 4])
            if code == "040":
                out.append(0x20)
                i += 4
                continue
            if code == "011":
                out.append(0x09)
                i += 4
                continue
            if code == "012":
                out.append(0x0A)
                i += 4
                continue
            if code == "134":
                out.append(0x5C)
                i += 4
                continue
        out.append(bytes[i])
        i += 1
    return String(unsafe_from_utf8=out)


def _lines(text: String) -> List[String]:
    """Return Python's `str.splitlines()` for ASCII text."""
    var out = List[String]()
    var bytes = text.as_bytes()
    var start = 0
    var i = 0
    while i < len(bytes):
        var byte = bytes[i]
        var width = 0
        if byte == 0x0D:
            width = 2 if i + 1 < len(bytes) and bytes[i + 1] == 0x0A else 1
        elif (
            byte == 0x0A
            or byte == 0x0B
            or byte == 0x0C
            or (byte >= 0x1C and byte <= 0x1E)
        ):
            width = 1
        if width > 0:
            out.append(String(unsafe_from_utf8=Span(bytes)[start:i]))
            i += width
            start = i
        else:
            i += 1
    if start < len(bytes):
        out.append(String(unsafe_from_utf8=Span(bytes)[start:]))
    return out^


# --- /proc -------------------------------------------------------------------


struct ProcStat(Copyable, Movable):
    """The scheduling and accounting fields of one `stat` file."""

    var pid: Int
    """The process ID."""
    var ppid: Int
    """The parent's ID."""
    var state: String
    """The state letter."""
    var ticks: Int
    """User and system CPU ticks."""
    var threads: Int
    """The thread count."""
    var start: Int
    """The start time in ticks, which tells a reused PID apart."""
    var rss_pages: Int
    """The resident pages, not below zero."""
    var thread_states: List[Tuple[String, Int]]
    """The sampled threads in each state, by state."""
    var thread_waits: List[Tuple[String, Int]]
    """The four most common wait channels and their counts."""
    var sampled_threads: Int
    """The threads whose state was read."""
    var wait_kinds_omitted: Int
    """The wait channels left out of `thread_waits`."""

    def __init__(out self):
        """Make an empty record."""
        self.pid = 0
        self.ppid = 0
        self.state = String()
        self.ticks = 0
        self.threads = 0
        self.start = 0
        self.rss_pages = 0
        self.thread_states = List[Tuple[String, Int]]()
        self.thread_waits = List[Tuple[String, Int]]()
        self.sampled_threads = 0
        self.wait_kinds_omitted = 0

    def identity(self) -> Tuple[Int, Int]:
        """Return the key that keeps CPU deltas apart across reused PIDs.

        Returns:
            The PID and the start time.
        """
        return (self.pid, self.start)


def parse_stat(text: String) raises -> ProcStat:
    """Read only the scheduling and accounting fields of a `stat` file.

    The process name sits in parentheses and can hold spaces and
    parentheses, so the fields start after the last `)`. The name is not
    kept.

    Args:
        text: The file's text.

    Returns:
        The fields.

    Raises:
        Error: As Python's `ValueError` or `IndexError` for a malformed
            text.
    """
    var end = text.rfind(")")
    if end < 0:
        raise Error("ValueError: missing process name delimiter")
    var fields = py_split(String(text[byte = end + 1 :]))
    if len(fields) < 22:
        raise Error("IndexError: list index out of range")
    var open = text.find("(")
    var head = text if open < 0 else String(text[byte=:open])
    var out = ProcStat()
    out.pid = py_int(head)
    out.ppid = py_int(fields[1])
    out.state = fields[0]
    out.ticks = py_int(fields[11]) + py_int(fields[12])
    out.threads = py_int(fields[17])
    out.start = py_int(fields[19])
    out.rss_pages = max(0, py_int(fields[21]))
    return out^


struct OomCounts(Copyable, Movable):
    """The OOM counters of one cgroup file, or `None`."""

    var present: Bool
    """False for Python's `None`: unreadable, or no counter."""
    var keys: List[String]
    """The counter names, in first-seen order."""
    var values: List[Int]
    """The counter values."""

    def __init__(out self):
        """Make `None`."""
        self.present = False
        self.keys = List[String]()
        self.values = List[Int]()

    def put(mut self, key: String, value: Int):
        """Set a counter, as a dict assignment does.

        Args:
            key: The name.
            value: The value.
        """
        for i in range(len(self.keys)):
            if self.keys[i] == key:
                self.values[i] = value
                return
        self.keys.append(key)
        self.values.append(value)
        self.present = True

    def find(self, key: String) -> Int:
        """Return a counter's position, or -1.

        Args:
            key: The name.

        Returns:
            The position.
        """
        for i in range(len(self.keys)):
            if self.keys[i] == key:
                return i
        return -1

    def to_json(self, mut doc: PyJson) -> Int:
        """Add the counters as a dict, or `None`.

        Args:
            doc: The document.

        Returns:
            The node.
        """
        if not self.present:
            return doc.new_none()
        var node = doc.new_dict()
        for i in range(len(self.keys)):
            doc.set(node, self.keys[i], doc.new_int(self.values[i]))
        return node

    def delta(self, previous: OomCounts, mut doc: PyJson) -> Int:
        """Add the counters that grew or stayed since `previous`.

        Args:
            previous: The earlier counters.
            doc: The document.

        Returns:
            A dict of the differences, or `None` when either side is
            `None`.
        """
        if not self.present or not previous.present:
            return doc.new_none()
        var node = doc.new_dict()
        for i in range(len(self.keys)):
            var at = previous.find(self.keys[i])
            if at >= 0 and self.values[i] >= previous.values[at]:
                doc.set(
                    node,
                    self.keys[i],
                    doc.new_int(self.values[i] - previous.values[at]),
                )
        return node


struct OomRead(Copyable, Movable):
    """The counters of both cgroup files, or `None` for no cgroup."""

    var present: Bool
    """False for Python's `None`."""
    var files: List[OomCounts]
    """The counters of each name in `OOM_FILES`."""

    def __init__(out self):
        """Make `None`."""
        self.present = False
        self.files = List[OomCounts]()

    def to_json(self, mut doc: PyJson) -> Int:
        """Add the counters as a dict by file, or `None`.

        Args:
            doc: The document.

        Returns:
            The node.
        """
        if not self.present:
            return doc.new_none()
        var node = doc.new_dict()
        var names = materialize[OOM_FILES]()
        for i in range(len(self.files)):
            doc.set(node, names[i], self.files[i].to_json(doc))
        return node

    def delta(self, previous: OomRead, mut doc: PyJson) -> Int:
        """Add each file's change since `previous`, as `Sampler` does.

        Args:
            previous: The earlier counters; `None` counts as `{}`.
            doc: The document.

        Returns:
            A dict by file.
        """
        var node = doc.new_dict()
        var names = materialize[OOM_FILES]()
        for i in range(len(self.files)):
            if previous.present:
                doc.set(
                    node, names[i], self.files[i].delta(previous.files[i], doc)
                )
            else:
                doc.set(node, names[i], doc.new_none())
        return node


struct ProcReader(Movable):
    """Read bounded kernel metadata, starting only from an owned compiler."""

    var root: String
    """The proc file system, `/proc` unless a test gives another."""
    var unavailable: Int
    """The reads that failed since the count was reset."""
    var truncated: Bool
    """True when a bound cut a read since the flag was reset."""
    var logging: Bool
    """True to keep each path read in `log`."""
    var log: List[String]
    """The paths read, when `logging`."""

    def __init__(out self, root: String = "/proc"):
        """Read a proc file system.

        Args:
            root: Its directory.
        """
        self.root = root
        self.unavailable = 0
        self.truncated = False
        self.logging = False
        self.log = List[String]()

    def open_dir(mut self, path: String, dir_fd: Int = -1) -> Int:
        """Open a directory without following a final symbolic link.

        Args:
            path: The directory.
            dir_fd: The directory `path` is relative to, or -1.

        Returns:
            The descriptor, or -1 after counting an unavailable read.
        """
        var fd = open_at(
            at_cwd() if dir_fd < 0 else dir_fd,
            c_bytes(path),
            o_directory() | o_nofollow() | o_cloexec(),
        )
        if fd < 0:
            self.unavailable += 1
            return -1
        return fd

    def read(
        mut self, path: String, limit: Int = 4096, dir_fd: Int = -1
    ) -> Optional[String]:
        """Read at most `limit` characters of a text file.

        The text is read as Python's text mode reads ASCII: universal
        newlines, and U+FFFD for a byte above 0x7F.

        Args:
            path: The file.
            limit: The most characters.
            dir_fd: The directory `path` is relative to, or -1.

        Returns:
            The text, or `None` when it is unreadable (counted) or longer
            than `limit` (marked truncated).
        """
        if self.logging:
            self.log.append(path)
        var fd = open_at(
            at_cwd() if dir_fd < 0 else dir_fd,
            c_bytes(path),
            o_nofollow() | o_cloexec(),
        )
        if fd < 0:
            self.unavailable += 1
            return None
        # Each character takes at most two bytes (CR LF), and one more byte
        # tells whether a last CR starts a CR LF.
        var want = 2 * (limit + 1) + 1
        var raw = List[UInt8](length=want, fill=0)
        var got = 0
        var failed = False
        while got < want:
            var count = external_call["read", Int](
                fd,
                OpaquePointer[MutAnyOrigin](
                    unsafe_from_address=Int(raw.unsafe_ptr()) + got
                ),
                want - got,
            )
            if count < 0:
                if errno() == 4:
                    continue
                failed = True
                break
            if count == 0:
                break
            got += count
        close_fd(fd)
        if failed:
            self.unavailable += 1
            return None
        raw.resize(got, 0)
        var chars = List[UInt8]()
        var count = 0
        var i = 0
        while i < len(raw) and count < limit + 1:
            if raw[i] == 0x0D:
                chars.append(0x0A)
                if i + 1 < len(raw) and raw[i + 1] == 0x0A:
                    i += 1
            else:
                chars.append(raw[i])
            i += 1
            count += 1
        if count > limit:
            self.truncated = True
            return None
        return ascii_text(chars)

    def entries(
        mut self, path: String, limit: Int, dir_fd: Int = -1
    ) -> List[Int]:
        """List the numeric names of a directory, reading at most `limit`.

        Args:
            path: The directory.
            limit: The most entries read.
            dir_fd: The directory `path` is relative to, or -1.

        Returns:
            The sorted numbers.
        """
        var fd = self.open_dir(path, dir_fd)
        if fd < 0:
            return List[Int]()
        var copy = Int(external_call["dup", c_int](c_int(fd)))
        close_fd(fd)
        if copy < 0:
            self.unavailable += 1
            return List[Int]()
        var names = List[String]()
        var stream = external_call["fdopendir", OpaquePointer[MutAnyOrigin]](
            c_int(copy)
        )
        if Int(stream) == 0:
            close_fd(copy)
            self.unavailable += 1
            return List[Int]()
        # The standard library declares `readdir` with another signature, so
        # on macOS it is found through the C library instead.
        var library = Optional[OwnedDLHandle](None)
        comptime if not CompilationTarget.is_linux():
            try:
                library = OwnedDLHandle("libSystem.B.dylib")
            except:
                _ = external_call["closedir", c_int](stream)
                self.unavailable += 1
                return List[Int]()
        while len(names) < limit + 1:
            var address: Int
            # Linux's `dirent64` holds its name at byte 19. The 64-bit inode
            # `dirent` of macOS holds it at byte 21.
            comptime if CompilationTarget.is_linux():
                address = Int(
                    external_call["readdir64", OpaquePointer[MutAnyOrigin]](
                        stream
                    )
                )
            else:
                address = Int(
                    library.value().call[
                        "readdir", OpaquePointer[MutAnyOrigin]
                    ](stream)
                )
            if address == 0:
                break
            var bytes = List[UInt8]()
            var at = address + (19 if CompilationTarget.is_linux() else 21)
            while True:
                var byte = Pointer[UInt8, MutAnyOrigin](
                    unsafe_from_address=at
                )[]
                if byte == 0:
                    break
                bytes.append(byte)
                at += 1
            var name = String(from_utf8_lossy=bytes)
            if name == "." or name == "..":
                continue
            names.append(name)
        _ = external_call["closedir", c_int](stream)
        if len(names) > limit:
            self.truncated = True
        var out = List[Int]()
        for i in range(min(limit, len(names))):
            if is_decimal(names[i]):
                try:
                    out.append(py_int(names[i]))
                except:
                    pass
        sort(out)
        return out^

    def stat(
        mut self, path: String = ".", dir_fd: Int = -1
    ) -> Optional[ProcStat]:
        """Read a `stat` file.

        Args:
            path: The process or task directory.
            dir_fd: The directory `path` is relative to, or -1.

        Returns:
            The fields, or `None` (counted) when unreadable or malformed.
        """
        var text = self.read(_join(path, "stat"), dir_fd=dir_fd)
        if text:
            try:
                return parse_stat(text.value())
            except:
                self.unavailable += 1
        return None

    def tree(
        mut self,
        root_pid: Int,
        root_identity: Optional[Tuple[Int, Int]] = None,
        root_fd: Int = -1,
    ) -> List[ProcStat]:
        """Read bounded descendants through pinned process directories.

        `children` is racy, so absent or reparented children can be missed.
        A pinned directory descriptor cannot retarget an unrelated reused
        PID. No scan of the system-wide PID directory is a fallback.

        Args:
            root_pid: The compiler.
            root_identity: The compiler's PID and start time, or `None`.
            root_fd: The compiler's open directory, or -1 to open it.

        Returns:
            One record per process, the compiler first.
        """
        if root_fd < 0:
            var fd = self.open_dir(_join(self.root, String(root_pid)))
            if fd < 0:
                return List[ProcStat]()
            var found = self.tree(root_pid, root_identity, fd)
            close_fd(fd)
            return found^
        var queue_pids = List[Int]()
        var queue_fds = List[Int]()
        queue_pids.append(root_pid)
        queue_fds.append(Int(external_call["dup", c_int](c_int(root_fd))))
        var seen = List[Int]()
        var records = List[ProcStat]()
        while len(queue_pids) > 0 and len(seen) < MAX_PROCESSES:
            var pid = queue_pids.pop(0)
            var fd = queue_fds.pop(0)
            if pid in seen:
                close_fd(fd)
                continue
            seen.append(pid)
            var first = self.stat(dir_fd=fd)
            if not first or first.value().pid != pid:
                close_fd(fd)
                continue
            var record = first.value().copy()
            if pid == root_pid and root_identity:
                var expected = root_identity.value()
                if expected[0] != record.pid or expected[1] != record.start:
                    close_fd(fd)
                    continue
            var states = List[Tuple[String, Int]]()
            var waits = List[Tuple[String, Int]]()
            var children = List[Int]()
            for tid in self.entries("task", MAX_THREADS, dir_fd=fd):
                var task = "task/" + String(tid)
                var thread = self.stat(task, dir_fd=fd)
                if thread:
                    _count(states, thread.value().state)
                var wait = self.read(task + "/wchan", 128, dir_fd=fd)
                if wait:
                    var name = String()
                    for byte in wait.value().as_bytes():
                        if (
                            (byte >= 0x41 and byte <= 0x5A)
                            or (byte >= 0x61 and byte <= 0x7A)
                            or (byte >= 0x30 and byte <= 0x39)
                            or byte == 0x5F
                        ):
                            if name.byte_length() < 48:
                                name += chr(Int(byte))
                    if name.byte_length() == 0:
                        name = "unavailable"
                    _count(waits, name)
                var child_text = self.read(task + "/children", 1024, dir_fd=fd)
                if child_text:
                    var words = py_split(child_text.value())
                    if len(words) > MAX_CHILDREN:
                        self.truncated = True
                    for i in range(min(len(words), MAX_CHILDREN)):
                        if is_decimal(words[i]):
                            try:
                                children.append(py_int(words[i]))
                            except:
                                pass
            var after = self.stat(dir_fd=fd)
            if not after or after.value().identity() != record.identity():
                close_fd(fd)
                continue
            _sort_by_key(states)
            record.thread_states = states.copy()
            record.thread_waits = _most_common(waits, 4)
            var sampled = 0
            for item in states:
                sampled += item[1]
            record.sampled_threads = sampled
            record.wait_kinds_omitted = max(0, len(waits) - 4)
            records.append(record.copy())
            sort(children)
            var previous = -1
            for child in children:
                if child == previous:
                    continue
                previous = child
                if child in seen:
                    continue
                if len(queue_pids) + len(seen) >= MAX_PROCESSES:
                    self.truncated = True
                    break
                var child_fd = self.open_dir(_join(self.root, String(child)))
                if child_fd < 0:
                    continue
                var child_stat = self.stat(dir_fd=child_fd)
                var parent_stat = self.stat(dir_fd=fd)
                if (
                    child_stat
                    and child_stat.value().ppid == pid
                    and parent_stat
                    and parent_stat.value().identity() == record.identity()
                ):
                    queue_pids.append(child)
                    queue_fds.append(child_fd)
                else:
                    close_fd(child_fd)
            close_fd(fd)
        if len(queue_pids) > 0:
            self.truncated = True
        for fd in queue_fds:
            close_fd(fd)
        return records^

    def inspect(
        mut self, pid: Int, expected: Optional[Tuple[Int, Int]]
    ) raises -> Tuple[List[ProcStat], Optional[String]]:
        """Read a compiler's tree and, when it has one, its cgroup.

        Args:
            pid: The compiler.
            expected: Its identity, or `None` before the first sample.

        Returns:
            The records and the cgroup directory.

        Raises:
            Error: For a symbolic link loop in the cgroup mount.
        """
        var fd = self.open_dir(_join(self.root, String(pid)))
        if fd < 0:
            return (List[ProcStat](), Optional[String](None))
        var records = self.tree(pid, expected, fd)
        var group = Optional[String](None)
        try:
            if len(records) > 0:
                group = self.cgroup(pid, fd)
        finally:
            close_fd(fd)
        return (records^, group^)

    def cgroup(
        mut self, pid: Int, root_fd: Int = -1
    ) raises -> Optional[String]:
        """Map unified membership through a readable cgroup2 mount, or decline.

        No global fallback group is read. In ambiguous namespaces or on
        cgroup v1, the group is unavailable. Paths are used internally and
        never printed.

        Args:
            pid: The process.
            root_fd: Its open directory, or -1 to read by path.

        Returns:
            The cgroup directory, or `None`.

        Raises:
            Error: For a symbolic link loop, as `pathlib` raises one.
        """
        var membership: Optional[String]
        if root_fd < 0:
            membership = self.read(
                _join(_join(self.root, String(pid)), "cgroup")
            )
        else:
            membership = self.read("cgroup", dir_fd=root_fd)
        var mounts = self.read(
            _join(_join(self.root, "self"), "mountinfo"), 65536
        )
        if not membership or not mounts:
            return None
        var member = Optional[String](None)
        for line in _lines(membership.value()):
            if line.startswith("0::"):
                member = String(line[byte=3:])
                break
        if not member:
            return None
        var path = member.value()
        if not path.startswith("/") or _has_dotdot(path):
            return None
        var lines = _lines(mounts.value())
        for index in range(min(len(lines), 512)):
            var line = lines[index]
            var at = line.find(" - ")
            if at < 0:
                continue
            var fields = py_split(String(line[byte=:at]))
            var right = py_split(String(line[byte = at + 3 :]))
            if len(right) == 0 or right[0] != "cgroup2" or len(fields) < 5:
                continue
            var mount_root = _decode_mount(fields[3])
            var mount_point = _decode_mount(fields[4])
            if not mount_root.startswith("/") or _has_dotdot(mount_root):
                continue
            var relative = relative_to(path, mount_root)
            if not relative:
                continue
            var base = resolve(mount_point)
            var candidate = resolve(_join(base, relative.value()))
            if not relative_to(candidate, base):
                continue
            return candidate
        return None

    def oom(mut self, directory: String = "", dir_fd: Int = -1) -> OomRead:
        """Read the OOM counters of a cgroup.

        Args:
            directory: The cgroup directory, used when `dir_fd` is -1.
            dir_fd: The cgroup's open directory, or -1.

        Returns:
            The counters of each file.
        """
        var out = OomRead()
        out.present = True
        for name in materialize[OOM_FILES]():
            var text: Optional[String]
            if dir_fd < 0:
                text = self.read(_join(directory, name))
            else:
                text = self.read(name, dir_fd=dir_fd)
            var counts = OomCounts()
            if text:
                for line in _lines(text.value()):
                    var fields = py_split(line)
                    if (
                        len(fields) == 2
                        and fields[0] in materialize[OOM_KEYS]()
                        and is_decimal(fields[1])
                    ):
                        try:
                            counts.put(fields[0], py_int(fields[1]))
                        except:
                            pass
            out.files.append(counts^)
        return out^


def _has_dotdot(path: String) -> Bool:
    """Return whether `'..' in path.split('/')`."""
    for part in path.split("/"):
        if part == "..":
            return True
    return False


def _count(mut counter: List[Tuple[String, Int]], key: String):
    """Add one to a key's count, keeping first-seen order."""
    for i in range(len(counter)):
        if counter[i][0] == key:
            counter[i] = (key, counter[i][1] + 1)
            return
    counter.append((key, 1))


def _sort_by_key(mut items: List[Tuple[String, Int]]):
    """Sort counts by key, as `sorted(dict.items())` does."""
    for i in range(1, len(items)):
        var j = i
        while j > 0 and items[j][0] < items[j - 1][0]:
            var swap = items[j - 1]
            items[j - 1] = items[j]
            items[j] = swap
            j -= 1


def _most_common(
    counter: List[Tuple[String, Int]], count: Int
) -> List[Tuple[String, Int]]:
    """Return `Counter.most_common(count)`: by count, ties in first-seen order.
    """
    var items = counter.copy()
    for i in range(1, len(items)):
        var j = i
        while j > 0 and items[j][1] > items[j - 1][1]:
            var swap = items[j - 1]
            items[j - 1] = items[j]
            items[j] = swap
            j -= 1
    var out = List[Tuple[String, Int]]()
    for i in range(min(count, len(items))):
        out.append(items[i])
    return out^


def _counts_json(mut doc: PyJson, items: List[Tuple[String, Int]]) -> Int:
    """Add counts as a dict."""
    var node = doc.new_dict()
    for item in items:
        doc.set(node, item[0], doc.new_int(item[1]))
    return node


# --- Sampling ----------------------------------------------------------------


trait CompilerSampler:
    """What `run_compiler` asks of a telemetry source."""

    def start(mut self, pid: Int) raises:
        """Begin to observe a compiler.

        Args:
            pid: The compiler.

        Raises:
            Error: When telemetry is unavailable.
        """
        ...

    def sample(mut self, mut doc: PyJson) raises -> Int:
        """Add one sample's fields as a dict.

        Args:
            doc: The document.

        Returns:
            The dict.

        Raises:
            Error: When telemetry fails.
        """
        ...

    def terminal(mut self, mut doc: PyJson) raises -> Int:
        """Add the fields read after the compiler ended, as a dict.

        Args:
            doc: The document.

        Returns:
            The dict.

        Raises:
            Error: When telemetry fails.
        """
        ...

    def close(mut self):
        """Release what the source holds."""
        ...


struct Sampler(CompilerSampler, Movable):
    """Sample a compiler's tree and its cgroup's OOM counters."""

    var pid: Int
    """The compiler."""
    var reader: ProcReader
    """The proc reader."""
    var clock: List[Float64]
    """Readings a test gives the clock, or empty for the real clock."""
    var ticks: Int
    """The clock readings used."""
    var hz: Int
    """The clock ticks per second of `stat`."""
    var page_kib: Float64
    """The KiB per memory page."""
    var previous: List[Tuple[Int, Int, Int]]
    """The PID, start time and CPU ticks of each process last time."""
    var previous_at: Optional[Float64]
    """The time of the last sample."""
    var root_identity: Optional[Tuple[Int, Int]]
    """The compiler's PID and start time from the first sample."""
    var group: Optional[String]
    """The cgroup directory last time."""
    var group_fd: Int
    """The pinned cgroup directory, or -1."""
    var previous_oom: OomRead
    """The counters last time."""

    def __init__(out self, root: String = "/proc"):
        """Make a sampler for the proc file system at `root`.

        Args:
            root: The proc directory.
        """
        self.pid = 0
        self.reader = ProcReader(root)
        self.clock = List[Float64]()
        self.ticks = 0
        comptime if CompilationTarget.is_linux():
            self.hz = Int(external_call["sysconf", Int](c_int(2)))
            self.page_kib = (
                Float64(external_call["sysconf", Int](c_int(30))) / 1024
            )
        else:
            self.hz = Int(external_call["sysconf", Int](c_int(3)))
            self.page_kib = (
                Float64(external_call["sysconf", Int](c_int(29))) / 1024
            )
        self.previous = List[Tuple[Int, Int, Int]]()
        self.previous_at = None
        self.root_identity = None
        self.group = None
        self.group_fd = -1
        self.previous_oom = OomRead()

    def start(mut self, pid: Int) raises:
        """Begin to observe a compiler.

        Args:
            pid: The compiler.

        Raises:
            Error: Never.
        """
        self.pid = pid

    def _now(mut self) -> Float64:
        """Read the clock."""
        if len(self.clock) > 0:
            var value = self.clock[self.ticks % len(self.clock)]
            self.ticks += 1
            return value
        return monotonic_seconds()

    def sample(mut self, mut doc: PyJson) raises -> Int:
        """Read the tree, the CPU deltas and the OOM counters.

        Args:
            doc: The document.

        Returns:
            The sample's fields as a dict.

        Raises:
            Error: For a symbolic link loop in the cgroup mount.
        """
        var now = self._now()
        self.reader.unavailable = 0
        self.reader.truncated = False
        var inspected = self.reader.inspect(self.pid, self.root_identity)
        var records = inspected[0].copy()
        var group = inspected[1]
        if len(records) > 0 and not self.root_identity:
            self.root_identity = records[0].identity()
        var current = List[Tuple[Int, Int, Int]]()
        var processes = doc.new_list()
        var deltas = List[Float64]()
        var rss_total = 0
        for stat in records:
            current.append((stat.pid, stat.start, stat.ticks))
            var delta = Optional[Float64](None)
            for item in self.previous:
                if item[0] == stat.pid and item[1] == stat.start:
                    delta = true_divide(max(0, stat.ticks - item[2]), self.hz)
            if delta:
                deltas.append(delta.value())
            var process = doc.new_dict()
            doc.set(process, "pid", doc.new_int(stat.pid))
            doc.set(process, "ppid", doc.new_int(stat.ppid))
            doc.set(process, "state", doc.new_str(stat.state))
            doc.set(
                process,
                "cpu_s",
                doc.new_float(round3(true_divide(stat.ticks, self.hz))),
            )
            if delta:
                doc.set(
                    process, "cpu_delta_s", doc.new_float(round3(delta.value()))
                )
            else:
                doc.set(process, "cpu_delta_s", doc.new_none())
            var rss = Int(
                round_half_even(Float64(stat.rss_pages) * self.page_kib)
            )
            rss_total += rss
            doc.set(process, "rss_kib_approx", doc.new_int(rss))
            doc.set(process, "threads", doc.new_int(stat.threads))
            doc.set(
                process, "sampled_threads", doc.new_int(stat.sampled_threads)
            )
            doc.set(
                process, "thread_states", _counts_json(doc, stat.thread_states)
            )
            doc.set(
                process, "thread_waits", _counts_json(doc, stat.thread_waits)
            )
            doc.set(
                process,
                "wait_kinds_omitted",
                doc.new_int(stat.wait_kinds_omitted),
            )
            doc.append(processes, process)
        if not _same(group, self.group):
            self.close()
            if group:
                self.group_fd = self.reader.open_dir(group.value())
        var oom = OomRead()
        if self.group_fd >= 0:
            oom = self.reader.oom(dir_fd=self.group_fd)
        var result = doc.new_dict()
        if self.previous_at:
            doc.set(
                result,
                "interval_s",
                doc.new_float(round3(now - self.previous_at.value())),
            )
        else:
            doc.set(result, "interval_s", doc.new_none())
        if len(deltas) > 0:
            var total = float_sum(deltas)
            doc.set(
                result, "observed_cpu_delta_s", doc.new_float(round3(total))
            )
        else:
            doc.set(result, "observed_cpu_delta_s", doc.new_none())
        if len(records) > 0:
            doc.set(result, "tree_rss_kib_approx", doc.new_int(rss_total))
        else:
            doc.set(result, "tree_rss_kib_approx", doc.new_none())
        doc.set(result, "processes", processes)
        doc.set(result, "best_effort_tree", doc.new_bool(True))
        doc.set(result, "cgroup_oom_shared_context", oom.to_json(doc))
        if oom.present and _same(group, self.group):
            doc.set(
                result, "cgroup_oom_delta", oom.delta(self.previous_oom, doc)
            )
        else:
            doc.set(result, "cgroup_oom_delta", doc.new_none())
        doc.set(
            result, "unavailable_reads", doc.new_int(self.reader.unavailable)
        )
        doc.set(result, "truncated", doc.new_bool(self.reader.truncated))
        self.previous = current^
        self.previous_at = now
        self.group = group
        self.previous_oom = oom^
        return result

    def terminal(mut self, mut doc: PyJson) raises -> Int:
        """Read the already-pinned cgroup after exit, without a PID lookup.

        Args:
            doc: The document.

        Returns:
            The OOM counters and their change, as a dict.

        Raises:
            Error: Never.
        """
        var result = doc.new_dict()
        if self.group_fd < 0:
            doc.set(result, "cgroup_oom_shared_context", doc.new_none())
            doc.set(result, "cgroup_oom_delta", doc.new_none())
            return result
        var oom = self.reader.oom(dir_fd=self.group_fd)
        doc.set(result, "cgroup_oom_shared_context", oom.to_json(doc))
        doc.set(result, "cgroup_oom_delta", oom.delta(self.previous_oom, doc))
        return result

    def close(mut self):
        """Close the pinned cgroup directory."""
        if self.group_fd >= 0:
            close_fd(self.group_fd)
            self.group_fd = -1


def _same(a: Optional[String], b: Optional[String]) -> Bool:
    """Return whether two optional paths are equal."""
    if not a or not b:
        return not a and not b
    return a.value() == b.value()


# --- Records -----------------------------------------------------------------


def utc_now() -> String:
    """Return `datetime.now(timezone.utc).isoformat(timespec='seconds')`.

    Returns:
        The time, such as `2026-01-02T03:04:05+00:00`.
    """
    var now = List[Int](length=1, fill=0)
    _ = external_call["time", Int](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(now.unsafe_ptr()))
    )
    var fields = List[Int32](length=16, fill=0)
    _ = external_call["gmtime_r", OpaquePointer[MutAnyOrigin]](
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(now.unsafe_ptr())),
        OpaquePointer[MutAnyOrigin](
            unsafe_from_address=Int(fields.unsafe_ptr())
        ),
    )
    return (
        _digits(Int(fields[5]) + 1900, 4)
        + "-"
        + _digits(Int(fields[4]) + 1, 2)
        + "-"
        + _digits(Int(fields[3]), 2)
        + "T"
        + _digits(Int(fields[2]), 2)
        + ":"
        + _digits(Int(fields[1]), 2)
        + ":"
        + _digits(Int(fields[0]), 2)
        + "+00:00"
    )


def _digits(value: Int, width: Int) -> String:
    """Return a number with leading zeros."""
    var text = String(value)
    while text.byte_length() < width:
        text = "0" + text
    return text


def safe_suite(suite: String) -> String:
    """Return the suite's name when it is a test path, else `unlabeled`.

    Args:
        suite: The `--suite` value.

    Returns:
        A name that matches `tests/test_[A-Za-z0-9_]+\\.mojo`, cut to 120
        characters, or `unlabeled`.
    """
    if (
        suite.startswith("tests/test_")
        and suite.endswith(".mojo")
        and suite.byte_length() > 16
    ):
        var middle = suite.as_bytes()[11 : suite.byte_length() - 5]
        var good = True
        for byte in middle:
            if not (
                (byte >= 0x41 and byte <= 0x5A)
                or (byte >= 0x61 and byte <= 0x7A)
                or (byte >= 0x30 and byte <= 0x39)
                or byte == 0x5F
            ):
                good = False
        if good:
            return String(suite[byte = : min(120, suite.byte_length())])
    return "unlabeled"


def emit(fd: Int, suite: String, mut doc: PyJson, payload: Int) raises:
    """Write a single bounded record; a logging failure cannot fail the build.

    Processes are dropped from the end until the line fits in `MAX_LINE`
    bytes. A record that cannot fit is not written.

    Args:
        fd: The log descriptor.
        suite: The suite.
        doc: The document that holds the payload.
        payload: A dict of the record's fields.

    Raises:
        Error: Never in practice; JSON writing can raise.
    """
    var record = doc.new_dict()
    doc.set(record, "compiler_telemetry", doc.new_int(1))
    doc.set(record, "utc", doc.new_str(utc_now()))
    doc.set(record, "suite", doc.new_str(safe_suite(suite)))
    for i in range(doc.length(payload)):
        doc.set(record, doc.key(payload, i), doc.value(payload, i))
    var omitted = 0
    doc.set(record, "processes_omitted_from_log", doc.new_int(0))
    var data: String
    while True:
        data = dumps_canonical(doc, record) + "\n"
        if data.byte_length() <= MAX_LINE:
            break
        var processes = doc.find(record, "processes")
        if processes >= 0 and doc.length(processes) > 0:
            var shorter = doc.new_list()
            for i in range(doc.length(processes) - 1):
                doc.append(shorter, doc.item(processes, i))
            doc.set(record, "processes", shorter)
            omitted += 1
            doc.set(record, "processes_omitted_from_log", doc.new_int(omitted))
        else:
            return
    _ = external_call["write", Int](
        fd,
        OpaquePointer[MutAnyOrigin](unsafe_from_address=Int(data.unsafe_ptr())),
        data.byte_length(),
    )


def shell_status(code: Int) -> Int:
    """Return the shell's status for Python's `returncode`.

    Args:
        code: The exit status, or minus the signal.

    Returns:
        The status, 128 + N for signal N.
    """
    return 128 - code if code < 0 else code


# --- The wrapper -------------------------------------------------------------


trait SignalControl:
    """Where `run_compiler` takes signals from and sends them to."""

    def take(mut self) -> Int:
        """Take one pending cancellation signal.

        Returns:
            The signal, or zero.
        """
        ...

    def send(mut self, pid: Int, number: Int):
        """Send a signal to a process group; failures are ignored.

        Args:
            pid: The group.
            number: The signal.
        """
        ...


struct HeldSignals(Movable, SignalControl):
    """The signals that `hold_signals` blocked in every thread."""

    var hold: SignalHold
    """The held signals."""

    def __init__(out self, var hold: SignalHold):
        """Take signals from a hold.

        Args:
            hold: The hold.
        """
        self.hold = hold^

    def take(mut self) -> Int:
        """Take one pending held signal.

        Returns:
            The signal, or zero.
        """
        return take_signal(self.hold)

    def send(mut self, pid: Int, number: Int):
        """Send a signal to a process group.

        Args:
            pid: The group.
            number: The signal.
        """
        _ = signal_group(pid, number)


def _unavailable(mut doc: PyJson) -> Int:
    """Add the `telemetry-unavailable` payload."""
    var payload = doc.new_dict()
    doc.set(payload, "event", doc.new_str("telemetry-unavailable"))
    return payload


def run_compiler[
    S: CompilerSampler, C: SignalControl
](
    command: List[String],
    suite: String,
    fd: Int,
    interval: Float64,
    mut sampler: S,
    mut control: C,
    hold: SignalHold = SignalHold(),
) raises -> Int:
    """Observe a compiler while waiting; never kill it or add a time limit.

    The compiler keeps this program's standard streams, so the Makefile's
    capture is kept, and runs in a private process group, so a forwarded
    cancellation reaches only this build.

    Parameters:
        S: The telemetry source's type.
        C: The signal source's type.

    Args:
        command: The compiler command.
        suite: The suite, for the records.
        fd: The log descriptor.
        interval: The seconds between samples.
        sampler: The telemetry source.
        control: The signal source.
        hold: The held signals, whose first mask the compiler gets.

    Returns:
        The compiler's shell status, or 128 + N when signal N came first.

    Raises:
        Error: `OSError: [Errno N] ...` when the compiler cannot start.
    """
    var received = control.take()
    if received != 0:
        return 128 + received
    var started = monotonic_seconds()
    var pid = spawn(command, hold, -1, False)
    var exited = Optional[Int](None)
    while True:
        var number = control.take()
        if number == 0:
            break
        received = number
        var state = try_wait(pid)
        if state.done:
            exited = state.status
        if not exited:
            control.send(pid, number)
    var sampling = True
    try:
        sampler.start(pid)
    except:
        sampling = False
        var doc = PyJson()
        emit(fd, suite, doc, _unavailable(doc))
    var code = 0
    while True:
        if sampling:
            var doc = PyJson()
            try:
                var fields = sampler.sample(doc)
                var payload = doc.new_dict()
                doc.set(payload, "event", doc.new_str("sample"))
                for i in range(doc.length(fields)):
                    doc.set(payload, doc.key(fields, i), doc.value(fields, i))
                emit(fd, suite, doc, payload)
            except:
                var plain = PyJson()
                emit(fd, suite, plain, _unavailable(plain))
                sampler.close()
                sampling = False
        var deadline = monotonic_seconds() + interval
        var finished = False
        while True:
            var number = control.take()
            if number != 0:
                received = number
                if not exited:
                    var state = try_wait(pid)
                    if state.done:
                        exited = state.status
                if not exited:
                    control.send(pid, number)
            if not exited:
                var state = try_wait(pid)
                if state.done:
                    exited = state.status
                elif state.error == ECHILD:
                    # Python's `Popen.wait` reads a lost child as status 0.
                    exited = 0
                elif state.error != 0:
                    raise Error(
                        "ChildProcessError: [Errno ",
                        state.error,
                        "] ",
                        strerror(state.error),
                    )
            if exited:
                code = exited.value()
                finished = True
                break
            if sampling and monotonic_seconds() >= deadline:
                break
            nap(0.01)
        if finished:
            break
    var status = shell_status(code)
    if received != 0 and status == 0:
        status = 128 + received
    var doc = PyJson()
    var payload = doc.new_dict()
    doc.set(payload, "event", doc.new_str("compiler-exit"))
    doc.set(payload, "pid", doc.new_int(pid))
    doc.set(payload, "exit", doc.new_int(status))
    doc.set(
        payload,
        "elapsed_s",
        doc.new_float(round3(monotonic_seconds() - started)),
    )
    if sampling:
        try:
            var fields = sampler.terminal(doc)
            for i in range(doc.length(fields)):
                doc.set(payload, doc.key(fields, i), doc.value(fields, i))
        except:
            doc.set(
                payload, "terminal_telemetry_unavailable", doc.new_bool(True)
            )
        sampler.close()
    emit(fd, suite, doc, payload)
    return status


# --- The command line --------------------------------------------------------


struct Options(Movable):
    """The parsed command line, or the text and status to exit with."""

    var suite: String
    """The `--suite` value."""
    var log_fd: Int
    """The `--log-fd` value."""
    var command: List[String]
    """The compiler command."""
    var message: String
    """The help or error text, or empty to run."""
    var status: Int
    """The exit status with `message`: 0 for help, 2 for an error."""

    def __init__(out self):
        """Make empty options."""
        self.suite = String()
        self.log_fd = 3
        self.command = List[String]()
        self.message = String()
        self.status = 0


def _is_negative_number(text: String) -> Bool:
    """Return whether `argparse` reads text as a negative number."""
    var bytes = text.as_bytes()
    if len(bytes) < 2 or bytes[0] != 0x2D:
        return False
    var dot = False
    var digits_after_dot = 0
    var digits = 0
    for i in range(1, len(bytes)):
        if bytes[i] == 0x2E:
            if dot:
                return False
            dot = True
        elif bytes[i] >= 0x30 and bytes[i] <= 0x39:
            digits += 1
            if dot:
                digits_after_dot += 1
        else:
            return False
    return digits_after_dot > 0 if dot else digits > 0


def _match_long(text: String) -> String:
    """Return the long option a word names, or empty."""
    var names: List[String] = ["--help", "--suite", "--log-fd"]
    var found = List[String]()
    for name in names:
        if name == text:
            return name
    if text.byte_length() <= 2:
        return String()
    for name in names:
        if name.startswith(text):
            found.append(name)
    if len(found) == 1:
        return found[0]
    return String()


def _usage_error(problem: String) -> Options:
    """Return the options that print a usage error and exit with 2."""
    var out = Options()
    out.message = USAGE + PROGRAM + ": error: " + problem + "\n"
    out.status = 2
    return out^


def parse_options(arguments: List[String]) -> Options:
    """Read the command line as the Python tool's `argparse` parser does.

    Args:
        arguments: The arguments after the program name.

    Returns:
        The options, or the message and status to exit with.
    """
    var options = Options()
    var unknown = List[String]()
    var has_suite = False
    var i = 0
    while i < len(arguments):
        var word = arguments[i]
        if word == "--" or not word.startswith("-") or word == "-":
            break
        if _is_negative_number(word) or " " in word:
            break
        var name = String()
        var value = Optional[String](None)
        if word.startswith("--"):
            var at = word.find("=")
            if at >= 0:
                name = _match_long(String(word[byte=:at]))
                value = String(word[byte = at + 1 :])
            else:
                name = _match_long(word)
        elif word == "-h" or word.startswith("-h"):
            name = "--help"
        if name.byte_length() == 0:
            unknown.append(word)
            i += 1
            continue
        if name == "--help":
            if value:
                return _usage_error(
                    "argument -h/--help: ignored explicit argument "
                    + py_repr(value.value())
                )
            var out = Options()
            out.message = USAGE + HELP
            return out^
        if not value:
            var next = i + 1
            if next >= len(arguments):
                return _usage_error(
                    "argument " + name + ": expected one argument"
                )
            var candidate = arguments[next]
            if candidate == "--" or (
                candidate.startswith("-")
                and candidate != "-"
                and not _is_negative_number(candidate)
                and " " not in candidate
            ):
                return _usage_error(
                    "argument " + name + ": expected one argument"
                )
            value = candidate
            i += 1
        if name == "--suite":
            options.suite = value.value()
            has_suite = True
        else:
            try:
                options.log_fd = py_int(value.value())
            except:
                return _usage_error(
                    "argument --log-fd: invalid int value: "
                    + py_repr(value.value())
                )
        i += 1
    while i < len(arguments):
        options.command.append(arguments[i])
        i += 1
    if not has_suite:
        return _usage_error("the following arguments are required: --suite")
    if len(unknown) > 0:
        var text = String()
        for word in unknown:
            if text.byte_length() > 0:
                text += " "
            text += word
        return _usage_error("unrecognized arguments: " + text)
    if len(options.command) > 0 and options.command[0] == "--":
        _ = options.command.pop(0)
    if len(options.command) == 0:
        return _usage_error("a compiler command is required")
    return options^


def _report_exec_error(number: Int, program: String) -> Int:
    """Print an error that Python would raise, and return its status."""
    var status = exec_error_status(number)
    if status == 1:
        print(
            "OSError: [Errno ",
            number,
            "] ",
            strerror(number),
            ": ",
            py_repr(program),
            sep="",
            file=stderr,
        )
    return status


def _errno_of(message: String) -> Int:
    """Return the number in an `OSError: [Errno N] ...` message, or 0."""
    var start = message.find("[Errno ")
    if start < 0:
        return 0
    var end = message.find("]", start)
    try:
        return Int(String(message[byte = start + 7 : end]))
    except:
        return 0


def main() raises:
    """Run the command line.

    Raises:
        Error: Never; each failure exits with its status.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var options = parse_options(arguments)
    if options.message.byte_length() > 0:
        if options.status == 0:
            print(options.message, end="")
        else:
            print(options.message, end="", file=stderr)
        exit(options.status)
    if (
        getenv("THREEMOJO_COMPILER_TELEMETRY") != "1"
        or not CompilationTarget.is_linux()
    ):
        var plan = ExecPlan(options.command)
        exit(_report_exec_error(plan.run(), options.command[0]))
    var hold = hold_signals([SIGINT, SIGTERM, SIGHUP])
    var control = HeldSignals(hold.copy())
    var sampler = Sampler()
    try:
        exit(
            run_compiler(
                options.command,
                options.suite,
                options.log_fd,
                INTERVAL,
                sampler,
                control,
                hold,
            )
        )
    except error:
        var number = _errno_of(String(error))
        if number == 0:
            print(error, file=stderr)
            exit(1)
        exit(_report_exec_error(number, options.command[0]))
