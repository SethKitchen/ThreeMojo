# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Record bounded compiler identity/target metadata; never compile a source.

    compiler_metadata [--compiler COMPILER]

The tool prints one JSON line and exits with 0. A diagnostic error is
reported as unavailable and does not replace or relax the CPU check that
follows. Only selected version and target fields and executable hashes are
logged:

- `launcher` and `driver`: the SHA-256 and the size of the compiler
  launcher, `.venv/bin/mojo` by default, and of the native driver that the
  launcher runs. The driver is found as the `mojo` wheel finds it, from the
  launcher's own virtual environment: `MODULAR_MOJO_MAX_DRIVER_PATH` when it
  is set, else `modular/bin/mojo` in its `site-packages`.
- `version`: the one line of `COMPILER --version`.
- `effective_target`: the target fields of `COMPILER build
  --print-effective-target`, which exits after flag resolution, before any
  compilation.

Each command has `TIMEOUT` seconds and `MAX_OUTPUT` bytes of standard
output; its standard error is discarded. The whole run has `TOTAL_TIMEOUT`
seconds. A command runs in its own process group, and the group is killed
when the command does not end in time. SIGINT and SIGTERM stop the command
group, and the tool then exits with 128 + N and prints nothing.
"""

from std.ffi import c_int, external_call
from std.os import getenv, listdir, stat
from std.os.path import exists, isdir, isfile, realpath
from std.sys import CompilationTarget, argv, exit, stderr

from tools._owned_process import (
    EPERM,
    ESRCH,
    SIGINT,
    SIGKILL,
    SIGTERM,
    SignalHold,
    close_fd,
    errno,
    hold_signals,
    make_pipe,
    monotonic_seconds,
    nap,
    signal_group,
    spawn,
    take_signal,
    try_wait,
)
from tools._python_json import PyJson, dumps_canonical, py_repr
from tools._sha256 import Sha256
from tools._text import split_lines

comptime MAX_OUTPUT = 8192
"""The most bytes of a command's output, and of the record."""
comptime MAX_BINARY = 512 * 1024 * 1024
"""The largest executable that is hashed."""
comptime TIMEOUT = 10.0
"""The seconds one command has."""
comptime TOTAL_TIMEOUT = 30.0
"""The seconds the whole run has."""
comptime TARGET_FIELDS = [
    "target-triple",
    "target-cpu",
    "target-features",
    "target-accelerator",
    "target-abi",
]
"""The target fields that are kept."""
comptime BUILD_ARGS = [
    "-I",
    ".",
    "--num-threads",
    "1",
    "--target-triple=x86_64-unknown-linux-gnu",
    "--target-cpu=x86-64-v3",
    "--Werror",
    "-o",
    ".cache/bin/test_exact_predicates",
    "tests/test_exact_predicates.mojo",
]
"""The flags of the CPU check, after `build --print-effective-target`."""

comptime DEADLINE = "MetadataDeadline"
"""The error text when the whole run's time is over."""
comptime CANCELLED = "Cancelled:"
"""The start of the error text when a signal cancels the run."""

comptime PROGRAM = "compiler_metadata.mojo"
"""The program name in usage messages."""
comptime USAGE = "usage: compiler_metadata.mojo [-h] [--compiler COMPILER]\n"
"""The usage line, as `argparse` writes it."""
comptime HELP = (
    "\nRecord bounded compiler identity/target metadata; never compile a"
    " source.\n\noptions:\n  -h, --help           show this help message"
    " and exit\n  --compiler COMPILER\n"
)
"""The help text after the usage line."""


struct Budget(Copyable, Movable):
    """The whole run's time limit and its cancellation signals."""

    var deadline: Float64
    """The monotonic time when the run is over."""
    var hold: SignalHold
    """The held signals; inactive in a test."""

    def __init__(out self, seconds: Float64 = TOTAL_TIMEOUT):
        """Start a budget with no held signal.

        Args:
            seconds: The time from now.
        """
        self.deadline = monotonic_seconds() + seconds
        self.hold = SignalHold()

    def check(self, include_deadline: Bool = True) raises:
        """Stop the run when a signal came or the time is over.

        Args:
            include_deadline: False to check only the signals, as cleanup
                after the deadline does.

        Raises:
            Error: `Cancelled:N` for signal N, or `MetadataDeadline`.
        """
        var number = take_signal(self.hold)
        if number != 0:
            raise Error(CANCELLED + String(number))
        if include_deadline and monotonic_seconds() >= self.deadline:
            raise Error(DEADLINE)


struct Identity(Copyable, Movable):
    """What `file_identity` found."""

    var status: String
    """`ok`, `unavailable` or `changed-during-read`."""
    var sha256: String
    """The hexadecimal digest, when `ok`."""
    var bytes: Int
    """The size, when `ok`."""

    def __init__(out self, status: String, sha256: String = "", bytes: Int = 0):
        """Make an identity.

        Args:
            status: The status.
            sha256: The digest.
            bytes: The size.
        """
        self.status = status
        self.sha256 = sha256
        self.bytes = bytes

    def to_json(self, mut doc: PyJson) -> Int:
        """Add the identity as a dict.

        Args:
            doc: The document.

        Returns:
            The node.
        """
        var node = doc.new_dict()
        doc.set(node, "status", doc.new_str(self.status))
        if self.status == "ok":
            doc.set(node, "sha256", doc.new_str(self.sha256))
            doc.set(node, "bytes", doc.new_int(self.bytes))
        return node


def file_identity(
    path: String, budget: Budget, max_binary: Int = MAX_BINARY
) raises -> Identity:
    """Hash only the selected executable, with a finite read bound.

    Args:
        path: The file.
        budget: The run's budget, checked between reads.
        max_binary: The largest size that is hashed.

    Returns:
        The digest and size, or the reason there is none.

    Raises:
        Error: When the budget ends.
    """
    var size: Int
    try:
        size = Int(stat(path).st_size)
    except:
        return Identity("unavailable")
    if size > max_binary or not isfile(path):
        return Identity("unavailable")
    var digest = Sha256()
    var read = 0
    try:
        with open(path, "r") as stream:
            budget.check()
            while True:
                var part = stream.read_bytes(
                    min(1024 * 1024, max_binary + 1 - read)
                )
                if len(part) == 0:
                    break
                read += len(part)
                if read > max_binary:
                    return Identity("unavailable")
                digest.update(part)
                budget.check()
    except error:
        var text = String(error)
        if text == DEADLINE or text.startswith(CANCELLED):
            raise error^
        return Identity("unavailable")
    if read != size:
        return Identity("changed-during-read")
    return Identity("ok", digest^.hexdigest(), read)


def _parent(path: String) -> String:
    """Return a path's parent directory, as `PurePath.parent` does."""
    var at = path.rfind("/")
    if at <= 0:
        return "/" if at == 0 else "."
    return String(path[byte=:at])


def _same_file(a: String, b: String) raises -> Bool:
    """Return `os.path.samefile(a, b)`."""
    var first = stat(a)
    var second = stat(b)
    return first.st_dev == second.st_dev and first.st_ino == second.st_ino


def find_driver(compiler: String) raises -> String:
    """Return the native driver that a `mojo` wheel launcher runs.

    The launcher must sit in a virtual environment's `bin` directory beside
    the `mojo` package, as the Python tool required the launcher and its
    interpreter to share one environment. The `mojo` package's own rule
    then picks the driver: `MODULAR_MOJO_MAX_DRIVER_PATH` from the
    environment, else `modular/bin/mojo` in `site-packages`, else the
    environment's own `bin/mojo`.

    Args:
        compiler: The launcher.

    Returns:
        The driver's path.

    Raises:
        Error: When the launcher is not in such an environment.
    """
    if not isfile(compiler):
        raise Error("FileNotFoundError: no compiler")
    var slash = compiler.rfind("/")
    var bin = "." if slash < 0 else String(compiler[byte=:slash])
    if bin.byte_length() == 0:
        bin = "/"
    if not isfile(bin + "/python") or not _same_file(compiler, bin + "/mojo"):
        raise Error("ValueError: compiler and metadata interpreter differ")
    var lib = realpath(bin + "/..") + "/lib"
    var site = String()
    if isdir(lib):
        var names = List[String]()
        for name in listdir(lib):
            if name.startswith("python"):
                names.append(name)
        sort(names)
        for name in names:
            var candidate = lib + "/" + name + "/site-packages"
            if isfile(candidate + "/mojo/run.py"):
                site = candidate
                break
    if site.byte_length() == 0:
        raise Error("ModuleNotFoundError: No module named 'mojo'")
    var unset = "\x00unset"
    var override = getenv("MODULAR_MOJO_MAX_DRIVER_PATH", unset)
    var root = String()
    if exists(site + "/modular/bin/mojo"):
        root = site + "/modular"
    elif exists(_parent(_parent(_parent(site))) + "/bin/mojo"):
        root = _parent(_parent(_parent(site)))
    else:
        var venv = getenv("VIRTUAL_ENV", unset)
        if venv != unset:
            root = venv
        elif (
            getenv("MODULAR_DERIVED_PATH", unset) == unset
            and getenv("BUILD_WORKSPACE_DIRECTORY", unset) == unset
            and getenv("BAZEL_TEST", unset) == unset
        ):
            raise Error("RuntimeError: Unable to locate Modular SDK")
    if override != unset:
        return override
    if root.byte_length() == 0:
        raise Error("KeyError: 'MODULAR_MOJO_MAX_DRIVER_PATH'")
    return root + "/bin/mojo"


struct CommandResult(Copyable, Movable):
    """What `read_command` read."""

    var text: Optional[String]
    """The output, only when the status is `ok`."""
    var status: String
    """`ok`, `failed`, `timeout`, `output-limit` or `unavailable`."""

    def __init__(out self, text: Optional[String], status: String):
        """Make a result.

        Args:
            text: The output, or `None`.
            status: The status.
        """
        self.text = text
        self.status = status


def _ascii(bytes: List[UInt8]) -> String:
    """Decode with Python's `ascii` codec and `errors='replace'`."""
    var out = List[UInt8](capacity=len(bytes))
    for byte in bytes:
        if byte < 0x80:
            out.append(byte)
        else:
            out.append(0xEF)
            out.append(0xBF)
            out.append(0xBD)
    return String(unsafe_from_utf8=out)


struct _Owned:
    """One owned child and whether it can still be signaled."""

    var pid: Int
    """The child, or 0 before it starts."""
    var reaped: Bool
    """True once `waitpid` has reaped it."""
    var can_signal: Bool
    """True while its process group may be signaled."""
    var code: Int
    """The return code once reaped."""

    def __init__(out self):
        """Own no child yet."""
        self.pid = 0
        self.reaped = False
        self.can_signal = False
        self.code = 0

    def wait(
        mut self, seconds: Float64, budget: Budget, cleanup: Bool = False
    ) raises -> Bool:
        """Wait for the child to end, checking the budget.

        Args:
            seconds: The most time to wait.
            budget: The run's budget.
            cleanup: True to check only the signals, not the deadline.

        Returns:
            True when the child ended and was reaped.

        Raises:
            Error: For a failed `waitpid`, a signal, or the run's deadline.
        """
        # A reaped child keeps its code, as Python's `Popen.wait` does. On
        # Darwin, `kill_group` can reap the leader before the caller waits.
        if self.reaped:
            return True
        var deadline = monotonic_seconds() + seconds
        while True:
            var was_owned = self.can_signal
            self.can_signal = False
            var state = try_wait(self.pid)
            if state.error != 0:
                raise Error(
                    "ChildProcessError: [Errno ", state.error, "] wait failed"
                )
            if state.done:
                self.reaped = True
                self.code = state.status
                return True
            self.can_signal = was_owned
            var remaining = deadline - monotonic_seconds()
            if remaining <= 0:
                return False
            budget.check(not cleanup)
            nap(min(0.01, remaining))

    def kill_group(mut self, budget: Budget) raises:
        """Signal the owned group; accept Darwin EPERM only after proven
        absence.

        Args:
            budget: The run's budget.

        Raises:
            Error: When a live leader or a present or denied group remains.
        """
        var failure = signal_group(self.pid, SIGKILL)
        if failure == 0 or failure == ESRCH:
            return
        if not CompilationTarget.is_macos() or failure != EPERM:
            raise Error("PermissionError: [Errno ", failure, "] kill denied")
        # EPERM alone cannot tell a zombie-only group from a denial. Darwin
        # also answers EPERM while the leader is still exiting, so give it a
        # moment to become a zombie before calling the kill denied.
        if not self.wait(0.5, budget, True):
            raise Error("PermissionError: [Errno ", failure, "] kill denied")
        if signal_group(self.pid, 0) == ESRCH:
            return
        raise Error("PermissionError: [Errno ", failure, "] group remains")


def read_command(
    command: List[String],
    budget: Budget,
    timeout: Float64 = TIMEOUT,
    limit: Int = MAX_OUTPUT,
) raises -> CommandResult:
    """Read at most `limit` bytes; stop only the owned metadata process.

    The command's standard error goes to `/dev/null`. When the command does
    not end in time, or writes too much, its process group is killed and
    reaped before this returns.

    Args:
        command: The program and its arguments.
        budget: The run's budget.
        timeout: The seconds the command has.
        limit: The most bytes of output.

    Returns:
        The output and `ok`, or no output and the reason.

    Raises:
        Error: For a failed `waitpid`, a denied kill, a signal, or the run's
            deadline.
    """
    var owned = _Owned()
    var outcome = CommandResult(None, "unavailable")
    var pending = Optional[String](None)
    var read_end = -1
    try:
        var pipe = make_pipe()
        read_end = pipe[0]
        try:
            owned.pid = spawn(command, budget.hold, pipe[1], True)
        except:
            close_fd(pipe[1])
            return CommandResult(None, "unavailable")
        close_fd(pipe[1])
        owned.can_signal = True
        var data = List[UInt8]()
        var deadline = monotonic_seconds() + timeout
        var open = True
        var finished = False
        var poll = List[Int32](length=2, fill=0)
        var chunk = List[UInt8](length=4096, fill=0)
        while open:
            var remaining = deadline - monotonic_seconds()
            if remaining <= 0:
                outcome = CommandResult(None, "timeout")
                finished = True
                break
            budget.check()
            poll[0] = Int32(read_end)
            poll[1] = Int32(1)
            var ready = external_call["poll", c_int](
                OpaquePointer[MutAnyOrigin](
                    unsafe_from_address=Int(poll.unsafe_ptr())
                ),
                c_int(1),
                c_int(Int(min(remaining, 0.01) * 1000) + 1),
            )
            if ready < 0:
                if errno() == 4:
                    continue
                raise Error("OSError: poll failed")
            if ready == 0:
                continue
            var count = external_call["read", Int](
                read_end,
                OpaquePointer[MutAnyOrigin](
                    unsafe_from_address=Int(chunk.unsafe_ptr())
                ),
                min(4096, limit + 1 - len(data)),
            )
            if count < 0:
                if errno() == 4:
                    continue
                raise Error("OSError: read failed")
            if count == 0:
                open = False
            else:
                for i in range(count):
                    data.append(chunk[i])
                if len(data) > limit:
                    outcome = CommandResult(None, "output-limit")
                    finished = True
                    break
        if not finished:
            if not owned.wait(
                max(0.001, deadline - monotonic_seconds()), budget
            ):
                outcome = CommandResult(None, "timeout")
            elif owned.code == 0:
                outcome = CommandResult(_ascii(data), "ok")
            else:
                outcome = CommandResult(None, "failed")
    except error:
        var text = String(error)
        if text.startswith("OSError"):
            outcome = CommandResult(None, "unavailable")
        else:
            pending = text
    if owned.pid > 0 and not owned.reaped and owned.can_signal:
        # No wait has reaped this PID on an early return, so its owned
        # group cannot be confused with a reused PID or group.
        try:
            owned.kill_group(budget)
            if not owned.wait(1.0, budget, True):
                pending = String(DEADLINE)
        except error:
            pending = String(error)
    if read_end >= 0:
        close_fd(read_end)
    if pending:
        raise Error(pending.value())
    return outcome^


trait MetadataSource:
    """Where `collect` runs commands and finds the driver."""

    def run(mut self, command: List[String]) raises -> CommandResult:
        """Run one metadata command.

        Args:
            command: The command.

        Returns:
            Its output and status.

        Raises:
            Error: When the run must stop.
        """
        ...

    def driver(mut self, compiler: String) raises -> String:
        """Find the native driver.

        Args:
            compiler: The launcher.

        Returns:
            The driver's path.

        Raises:
            Error: When there is none.
        """
        ...

    def budget(self) -> Budget:
        """Return the run's budget.

        Returns:
            The budget.
        """
        ...


struct RealSource(MetadataSource, Movable):
    """Run real commands within a budget."""

    var limits: Budget
    """The run's budget."""

    def __init__(out self, var limits: Budget):
        """Use a budget.

        Args:
            limits: The budget.
        """
        self.limits = limits^

    def run(mut self, command: List[String]) raises -> CommandResult:
        """Run one metadata command.

        Args:
            command: The command.

        Returns:
            Its output and status.

        Raises:
            Error: When the run must stop.
        """
        return read_command(command, self.limits)

    def driver(mut self, compiler: String) raises -> String:
        """Find the native driver.

        Args:
            compiler: The launcher.

        Returns:
            The driver's path.

        Raises:
            Error: When there is none.
        """
        return find_driver(compiler)

    def budget(self) -> Budget:
        """Return the run's budget.

        Returns:
            The budget.
        """
        return self.limits.copy()


def _is_version(line: String) -> Bool:
    """Return whether a line matches `Mojo [A-Za-z0-9. ()+_-]{1,80}`."""
    if not line.startswith("Mojo "):
        return False
    var rest = line.as_bytes()[5:]
    if len(rest) < 1 or len(rest) > 80:
        return False
    for byte in rest:
        if not (
            (byte >= 0x41 and byte <= 0x5A)
            or (byte >= 0x61 and byte <= 0x7A)
            or (byte >= 0x30 and byte <= 0x39)
            or byte == 0x2E
            or byte == 0x20
            or byte == 0x28
            or byte == 0x29
            or byte == 0x2B
            or byte == 0x5F
            or byte == 0x2D
        ):
            return False
    return True


def _target_field(line: String) -> Optional[Tuple[String, String]]:
    """Match `  --([a-z-]+) ([A-Za-z0-9_+.,:-]+)` against a whole line."""
    if not line.startswith("  --"):
        return None
    var rest = line.as_bytes()[4:]
    var space = -1
    for i in range(len(rest)):
        if rest[i] == 0x20:
            space = i
            break
    if space < 1 or space + 1 >= len(rest):
        return None
    for i in range(space):
        var byte = rest[i]
        if not ((byte >= 0x61 and byte <= 0x7A) or byte == 0x2D):
            return None
    for i in range(space + 1, len(rest)):
        var byte = rest[i]
        if not (
            (byte >= 0x41 and byte <= 0x5A)
            or (byte >= 0x61 and byte <= 0x7A)
            or (byte >= 0x30 and byte <= 0x39)
            or byte == 0x5F
            or byte == 0x2B
            or byte == 0x2E
            or byte == 0x2C
            or byte == 0x3A
            or byte == 0x2D
        ):
            return None
    return (
        String(unsafe_from_utf8=rest[:space]),
        String(unsafe_from_utf8=rest[space + 1 :]),
    )


def target_command(compiler: String) -> List[String]:
    """Return the command that prints the effective target.

    Args:
        compiler: The launcher.

    Returns:
        `COMPILER build --print-effective-target` and `BUILD_ARGS`.
    """
    var command: List[String] = [compiler, "build", "--print-effective-target"]
    for word in materialize[BUILD_ARGS]():
        command.append(word)
    return command^


def collect[
    S: MetadataSource
](compiler: String, mut source: S) raises -> PyJson:
    """Gather the record.

    Parameters:
        S: The source's type.

    Args:
        compiler: The launcher.
        source: Where commands run and the driver is found.

    Returns:
        The record, as a document whose root is a dict.

    Raises:
        Error: When a signal or the deadline stops the run, or a command
            cannot be cleaned up.
    """
    var budget = source.budget()
    var doc = PyJson()
    var result = doc.new_dict()
    doc.root = result
    doc.set(result, "compiler_metadata", doc.new_int(1))
    doc.set(result, "launcher", file_identity(compiler, budget).to_json(doc))
    var driver = Identity("unavailable")
    try:
        var path = source.driver(compiler)
        budget.check()
        driver = file_identity(path, budget)
    except error:
        var text = String(error)
        if text == DEADLINE or text.startswith(CANCELLED):
            raise error^
    doc.set(result, "driver", driver.to_json(doc))
    var version = source.run([compiler, "--version"])
    var lines = List[String]()
    if version.text:
        lines = split_lines(version.text.value())
    doc.set(result, "version_status", doc.new_str(version.status))
    if len(lines) == 1 and _is_version(lines[0]):
        doc.set(result, "version", doc.new_str(lines[0]))
    elif version.status == "ok":
        doc.set(result, "version_status", doc.new_str("unrecognized-output"))
    var command = target_command(compiler)
    var target = source.run(command)
    doc.set(result, "target_status", doc.new_str(target.status))
    var listed = doc.new_list()
    for word in command:
        doc.append(listed, doc.new_str(word))
    doc.set(result, "target_command", listed)
    if target.text:
        var names = List[String]()
        var values = List[String]()
        var all_lines = split_lines(target.text.value())
        var valid = (
            len(all_lines) > 0
            and all_lines[0] == "Effective target configuration:"
        )
        for index in range(1, len(all_lines)):
            var line = all_lines[index]
            var field = _target_field(line)
            if (
                field
                and field.value()[0] in materialize[TARGET_FIELDS]()
                and field.value()[0] not in names
            ):
                names.append(field.value()[0])
                values.append(field.value()[1])
            elif not _blank(line):
                valid = False
        if (
            valid
            and "target-triple" in names
            and "target-cpu" in names
            and "target-features" in names
        ):
            var fields = doc.new_dict()
            for i in range(len(names)):
                doc.set(fields, names[i], doc.new_str(values[i]))
            doc.set(result, "effective_target", fields)
        else:
            doc.set(result, "target_status", doc.new_str("unrecognized-output"))
    return doc^


def _blank(line: String) -> Bool:
    """Return whether `line.strip()` is empty."""
    for byte in line.as_bytes():
        if not (
            byte == 0x20
            or (byte >= 0x09 and byte <= 0x0D)
            or (byte >= 0x1C and byte <= 0x1F)
        ):
            return False
    return True


def status_record(status: String) raises -> String:
    """Return the record that says only a status.

    Args:
        status: `unavailable` or `record-limit`.

    Returns:
        The JSON text.

    Raises:
        Error: Never in practice; JSON writing can raise.
    """
    var doc = PyJson()
    var node = doc.new_dict()
    doc.set(node, "compiler_metadata", doc.new_int(1))
    doc.set(node, "status", doc.new_str(status))
    return dumps_canonical(doc, node)


def record_text[
    S: MetadataSource
](compiler: String, mut source: S) raises -> String:
    """Return the line to print, as the Python tool's `main` does.

    Parameters:
        S: The source's type.

    Args:
        compiler: The launcher.
        source: Where commands run and the driver is found.

    Returns:
        The record, `record-limit` when it is longer than `MAX_OUTPUT`
        bytes, or `unavailable` when collecting failed.

    Raises:
        Error: `Cancelled:N` when signal N stopped the run.
    """
    try:
        var doc = collect(compiler, source)
        var encoded = dumps_canonical(doc, doc.root)
        if encoded.byte_length() > MAX_OUTPUT:
            return status_record("record-limit")
        return encoded
    except error:
        if String(error).startswith(CANCELLED):
            raise error^
        return status_record("unavailable")


struct Options(Movable):
    """The parsed command line, or the text and status to exit with."""

    var compiler: String
    """The `--compiler` value."""
    var message: String
    """The help or error text, or empty to run."""
    var status: Int
    """The exit status with `message`: 0 for help, 2 for an error."""

    def __init__(out self):
        """Make the default options."""
        self.compiler = ".venv/bin/mojo"
        self.message = String()
        self.status = 0


def _usage_error(problem: String) -> Options:
    """Return the options that print a usage error and exit with 2."""
    var out = Options()
    out.message = USAGE + PROGRAM + ": error: " + problem + "\n"
    out.status = 2
    return out^


def _looks_like_option(word: String) -> Bool:
    """Return whether `argparse` reads a word as an option."""
    if not word.startswith("-") or word == "-":
        return False
    if " " in word:
        return False
    var bytes = word.as_bytes()
    var digits = 0
    var dot = 0
    for i in range(1, len(bytes)):
        if bytes[i] >= 0x30 and bytes[i] <= 0x39:
            digits += 1
        elif bytes[i] == 0x2E:
            dot += 1
        else:
            return True
    # A negative number is a value, since no option looks like one.
    if dot == 0:
        return digits == 0
    return dot > 1 or bytes[len(bytes) - 1] == 0x2E


def parse_options(arguments: List[String]) -> Options:
    """Read the command line as the Python tool's `argparse` parser does.

    Args:
        arguments: The arguments after the program name.

    Returns:
        The options, or the message and status to exit with.
    """
    var options = Options()
    var extras = List[String]()
    var i = 0
    while i < len(arguments):
        var word = arguments[i]
        if word == "--":
            for j in range(i, len(arguments)):
                extras.append(arguments[j])
            break
        if not _looks_like_option(word):
            extras.append(word)
            i += 1
            continue
        var name = String()
        var value = Optional[String](None)
        if word.startswith("--"):
            var at = word.find("=")
            var stem = word if at < 0 else String(word[byte=:at])
            if at >= 0:
                value = String(word[byte = at + 1 :])
            if stem.byte_length() > 2:
                if "--compiler".startswith(stem):
                    name = "--compiler"
                elif "--help".startswith(stem):
                    name = "--help"
        elif word.startswith("-h"):
            name = "--help"
        if name.byte_length() == 0:
            extras.append(word)
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
            if i + 1 >= len(arguments):
                return _usage_error(
                    "argument --compiler: expected one argument"
                )
            var candidate = arguments[i + 1]
            if candidate == "--" or _looks_like_option(candidate):
                return _usage_error(
                    "argument --compiler: expected one argument"
                )
            value = candidate
            i += 1
        options.compiler = value.value()
        i += 1
    if len(extras) > 0:
        var text = String()
        for word in extras:
            if text.byte_length() > 0:
                text += " "
            text += word
        return _usage_error("unrecognized arguments: " + text)
    return options^


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
    var budget = Budget()
    budget.hold = hold_signals([SIGINT, SIGTERM])
    var source = RealSource(budget.copy())
    var line = String()
    try:
        line = record_text(options.compiler, source)
        var number = take_signal(budget.hold)
        if number != 0:
            exit(128 + number)
    except error:
        var text = String(error)
        exit(128 + Int(String(text[byte = CANCELLED.byte_length() :])))
    print(line)
