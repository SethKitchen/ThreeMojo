# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Append launch requests for one compiled coverage profile.

The capture publishes `THREEMOJO_COVERAGE_PHASES` and the file's device and
inode. This log checks that identity, then appends one JSON record for each
build, helper or program launch. The program record keeps the source path
and the count of later arguments. A write that cannot fit marks the trace
incomplete and leaves the profile running.
"""

from std.ffi import c_int, external_call
from std.memory import OpaquePointer, Pointer
from std.os import getenv
from std.sys import CompilationTarget

from tools._carla_files import fstat_id, o_nonblock, o_wronly
from tools._json_tools import quote_ascii
from tools._owned_process import (
    EINTR,
    at_cwd,
    c_bytes,
    close_fd,
    errno,
    o_nofollow,
    open_at,
    python_monotonic,
    set_cloexec,
    strerror,
)

comptime PHASE_ENV = "THREEMOJO_COVERAGE_PHASES"
"""The phase-file path set by the capture."""

comptime PHASE_SCHEMA = "coverage-exec-phases-v1"
"""The schema name on every phase record."""

comptime PHASE_MAX_BYTES = 128 * 1024
"""The largest phase file, in bytes."""

comptime PHASE_MAX_RECORD = 16 * 1024
"""The largest one phase record, in bytes."""

comptime PHASE_MAX_EVENTS = 32
"""The most launch requests one profile may record."""


def _digits(value: Int, width: Int) -> String:
    """Return `value` padded with zeros on the left."""
    var out = String(value)
    while out.byte_length() < width:
        out = "0" + out
    return out^


def _utc() -> String:
    """Return `datetime.now(timezone.utc).isoformat()`."""
    var now = List[Int64](length=2, fill=0)
    _ = external_call["clock_gettime", Int32](
        Int32(0), now.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    var seconds = Int(now[0])
    var micro = Int(now[1]) // 1000
    var days = seconds // 86400
    var rest = seconds - days * 86400
    var z = days + 719468
    var era = z // 146097
    var doe = z - era * 146097
    var yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    var doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    var mp = (5 * doy + 2) // 153
    var day = doy - (153 * mp + 2) // 5 + 1
    var month = mp + 3 if mp < 10 else mp - 9
    var year = yoe + era * 400 + Int(month <= 2)
    var out = (
        _digits(year, 4)
        + "-"
        + _digits(month, 2)
        + "-"
        + _digits(day, 2)
        + "T"
        + _digits(rest // 3600, 2)
        + ":"
        + _digits((rest // 60) % 60, 2)
        + ":"
        + _digits(rest % 60, 2)
    )
    if micro != 0:
        out += "." + _digits(micro, 6)
    return out + "+00:00"


def _monotonic() -> Float64:
    """Return `time.monotonic()` in seconds."""
    return python_monotonic()


def _json_number(value: Float64) -> String:
    """Return a JSON number for a finite float."""
    var text = String(value)
    if text == "nan" or text == "inf" or text == "-inf":
        return "0.0"
    var marked = False
    for byte in text.as_bytes():
        if byte == 46 or byte == 101 or byte == 69:
            marked = True
    if not marked:
        text += ".0"
    return text^


def _json_array(items: List[String]) -> String:
    """Return a JSON array of strings with Python's separators."""
    var out = "["
    var index = 0
    for item in items:
        if index > 0:
            out += ", "
        out += quote_ascii(item)
        index += 1
    return out + "]"


def _stem(path: String) -> String:
    """Return `Path(path).stem`."""
    var slash = path.rfind("/")
    var name = path if slash < 0 else String(path[byte = slash + 1 :])
    var dot = name.rfind(".")
    if dot > 0:
        return String(name[byte=:dot])
    return name^


def _exception_word(name: String) -> Bool:
    """Return whether `name` is one Pascal-case exception class."""
    if name.byte_length() < 6 or not name.endswith("Error"):
        return False
    var bytes = name.as_bytes()
    var first = bytes[0]
    if first < 65 or first > 90:
        return False
    var index = 1
    while index < len(bytes):
        var byte = bytes[index]
        var letter = (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
        if not letter:
            return False
        index += 1
    return True


def _exception_name(text: String) -> String:
    """Return the Python class name for an error raised by a profile."""
    var colon = text.find(": ")
    if colon > 0:
        var name = String(text[byte=:colon])
        if _exception_word(name):
            return name^
    if (
        text.startswith("coverage profile")
        or text.startswith("unknown profile")
        or text.startswith("private hit profile")
    ):
        return "ValueError"
    if (
        text.find("native test build failed") >= 0
        or text.find("compiler --version failed") >= 0
    ):
        return "CalledProcessError"
    if text.find("No such file") >= 0:
        return "FileNotFoundError"
    return "Error"


def _parse_u64(text: String) raises -> UInt64:
    """Return the decimal integer in `text`."""
    if text.byte_length() == 0:
        raise Error("ValueError: invalid literal")
    var value = UInt64(0)
    for byte in text.as_bytes():
        if byte < 48 or byte > 57:
            raise Error("ValueError: invalid literal")
        value = value * 10 + UInt64(Int(byte) - 48)
    return value


def _open_flags() -> Int:
    """Return the flags for the phase file."""
    var append = 0x400
    comptime if CompilationTarget.is_macos():
        append = 0x8
    return o_wronly() | append | o_nonblock() | o_nofollow()


def _write_once(fd: Int, data: Span[UInt8, _]) raises -> Int:
    """Write once, and retry only when the call is interrupted.

    Args:
        fd: The descriptor.
        data: The bytes.

    Returns:
        The number of bytes the call wrote.

    Raises:
        Error: `OSError` when the write fails.
    """
    var base = Int(data.unsafe_ptr())
    while True:
        var count = external_call["write", Int](
            Int32(fd),
            OpaquePointer[MutAnyOrigin](unsafe_from_address=base),
            len(data),
        )
        if count < 0:
            var number = errno()
            if number == EINTR:
                continue
            raise Error(
                "OSError: [Errno " + String(number) + "] " + strerror(number)
            )
        return Int(count)


def _file_size(fd: Int) raises -> Int:
    """Return the size of an open file."""
    var size = external_call["lseek", Int64](c_int(fd), Int64(0), c_int(2))
    if size < 0:
        raise Error(
            "OSError: [Errno " + String(errno()) + "] " + strerror(errno())
        )
    return Int(size)


struct PhaseLog(Movable):
    """The phase file for one compiled profile."""

    var descriptor: Int
    """The append descriptor, or -1 when it is closed."""
    var suite: String
    """The suite stem."""
    var mojo: String
    """The compiler named by the profile command."""
    var source: String
    """The suite argument, as the command writes it."""
    var cc: List[String]
    """The C compiler command, split as `shlex` splits it."""
    var flags: List[String]
    """The fixed C flags on a helper compile."""
    var size: Int
    """The bytes already in the phase file."""
    var events: Int
    """The launch requests seen so far."""
    var complete: Bool
    """False when a request or a write was lost."""
    var build_requested: Bool
    """True after the Mojo build request is recorded."""
    var armed: Bool
    """True when this profile owns a phase file."""

    def __init__(out self):
        """Make a closed log."""
        self.descriptor = -1
        self.suite = ""
        self.mojo = ""
        self.source = ""
        self.cc = List[String]()
        self.flags = List[String]()
        self.size = 0
        self.events = 0
        self.complete = True
        self.build_requested = False
        self.armed = False

    def close(mut self):
        """Close the descriptor.

        A second call does nothing.
        """
        if self.descriptor >= 0:
            close_fd(self.descriptor)
            self.descriptor = -1

    def attach(
        mut self,
        suite: String,
        mojo: String,
        source: String,
        cc: List[String],
        flags: List[String],
    ):
        """Open the phase file named by the environment.

        A missing file, a changed identity or a symlink leaves the log
        closed. The profile still runs.

        Args:
            suite: The suite path.
            mojo: The compiler path from the command.
            source: The suite argument.
            cc: The C compiler command.
            flags: The fixed C flags.
        """
        self.armed = True
        self.mojo = mojo
        self.source = source
        self.suite = _stem(suite)
        for word in cc:
            self.cc.append(word)
        for flag in flags:
            self.flags.append(flag)
        try:
            self._open()
        except:
            self.complete = False
            self.close()

    def _open(mut self) raises:
        """Open and check the phase file."""
        var path = getenv(PHASE_ENV, "")
        if path.byte_length() == 0:
            raise Error("ValueError: phase file is unset")
        var fd = open_at(at_cwd(), c_bytes(path), _open_flags())
        if fd < 0:
            raise Error(
                "OSError: [Errno " + String(errno()) + "] " + strerror(errno())
            )
        self.descriptor = fd
        set_cloexec(fd)
        var info = fstat_id(fd)
        var device = _parse_u64(getenv(PHASE_ENV + "_DEVICE", ""))
        var inode = _parse_u64(getenv(PHASE_ENV + "_INODE", ""))
        if (
            not info.is_regular()
            or info.device != device
            or info.inode != inode
        ):
            raise Error("ValueError: phase file identity changed")
        self.size = _file_size(fd)

    def _helper(self, argv: List[String]) -> Bool:
        """Return whether `argv` is a helper version or compile command."""
        var width = len(self.cc)
        if width == 0 or len(argv) < width:
            return False
        var index = 0
        while index < width:
            if argv[index] != self.cc[index]:
                return False
            index += 1
        var tail = width
        if len(argv) > width and argv[width] == "-pthread":
            tail += 1
        var tail_len = len(argv) - tail
        if tail_len == 1 and argv[tail] == "--version":
            return True
        var flag_count = len(self.flags)
        if tail_len != flag_count + 4:
            return False
        index = 0
        while index < flag_count:
            if argv[tail + index] != self.flags[index]:
                return False
            index += 1
        if argv[tail + flag_count] != "-c":
            return False
        return argv[len(argv) - 2] == "-o"

    def _line(self, phase: String, extra: String) -> String:
        """Return one JSON record and its newline."""
        return (
            '{"schema": "'
            + PHASE_SCHEMA
            + '", "suite": '
            + quote_ascii(self.suite)
            + ', "utc": '
            + quote_ascii(_utc())
            + ', "monotonic": '
            + _json_number(_monotonic())
            + ', "adapter_pid": '
            + String(Int(external_call["getpid", c_int]()))
            + ', "phase": '
            + quote_ascii(phase)
            + extra
            + "}\n"
        )

    def _write(mut self, phase: String, extra: String) raises:
        """Append one record, or raise when it cannot fit."""
        if self.descriptor < 0:
            return
        var line = self._line(phase, extra)
        var width = line.byte_length()
        if width > PHASE_MAX_RECORD or self.size + width > PHASE_MAX_BYTES:
            raise Error("ValueError: phase record size limit")
        var count = _write_once(self.descriptor, line.as_bytes())
        self.size += count
        if count != width:
            raise Error("OSError: short phase write")

    def _lost(mut self, error: Error):
        """Record that the trace is incomplete, then keep the descriptor."""
        self.complete = False
        try:
            var name = _exception_name(String(error))
            self._write(
                "diagnostics_incomplete", ', "exception": ' + quote_ascii(name)
            )
        except:
            self.close()

    def note(mut self, executable: String, argv: List[String]):
        """Record one launch request.

        An unknown command, a request past the limit, or a write that
        cannot fit marks the trace incomplete. The profile still starts
        the program.

        Args:
            executable: The program file.
            argv: The arguments the program sees.
        """
        if self.descriptor < 0 or not self.complete:
            return
        try:
            self.events += 1
            if self.events > PHASE_MAX_EVENTS:
                raise Error("ValueError: phase event limit")
            var phase: String
            var omitted = -1
            var shown = List[String]()
            if (
                not self.build_requested
                and len(argv) > 1
                and argv[0] == self.mojo
                and argv[1] == "build"
                and argv[len(argv) - 1] == self.source
            ):
                phase = "mojo_build_launch_request"
                self.build_requested = True
                for word in argv:
                    shown.append(word)
            elif (
                self.build_requested
                and len(argv) > 0
                and argv[0] == self.source
            ):
                phase = "native_runtime_launch_request"
                omitted = len(argv) - 1
                shown.append(argv[0])
            elif not self.build_requested and self._helper(argv):
                phase = "native_helper_launch_request"
                for word in argv:
                    shown.append(word)
            else:
                raise Error("ValueError: unrecognized subprocess request")
            var extra = (
                ', "executable": '
                + quote_ascii(executable)
                + ', "argv": '
                + _json_array(shown)
            )
            if omitted >= 0:
                extra += ', "omitted_program_arguments": ' + String(omitted)
            self._write(phase, extra)
        except error:
            self._lost(error)

    def _finish(mut self, outcome: String):
        """Append the finish record and close the file."""
        if not self.armed:
            return
        if self.events == 0 and self.complete:
            self._lost(Error("RuntimeError: no subprocess requests observed"))
        try:
            var flag = "false"
            if self.complete:
                flag = "true"
            self._write(
                "adapter_finish",
                ', "diagnostics_complete": ' + flag + outcome,
            )
        except error:
            self._lost(error)
        self.close()

    def finish_status(mut self, status: Int):
        """Append a finish record that carries `status`.

        Args:
            status: The profile status.
        """
        self._finish(', "status": ' + String(status))

    def finish_error(mut self, text: String):
        """Append a finish record that carries the error class.

        Args:
            text: The error text. A leading class name is kept.
        """
        self._finish(', "exception": ' + quote_ascii(_exception_name(text)))


def phase_address(ref log: PhaseLog) -> Int:
    """Return the address of `log`.

    Args:
        log: A live log. The caller keeps it at this address.

    Returns:
        The address. `phase_note` ignores 0.
    """
    return Int(Pointer(to=log))


def phase_note(log: Int, executable: String, argv: List[String]):
    """Record one launch when `log` is the address of a `PhaseLog`.

    Args:
        log: The address from `phase_address`, or 0.
        executable: The program file.
        argv: The arguments the program sees.
    """
    if log == 0:
        return
    var ptr = Pointer[PhaseLog, MutAnyOrigin](unsafe_from_address=log)
    ptr[].note(executable, argv)
