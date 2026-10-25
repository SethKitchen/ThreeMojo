# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Build test-only C dependencies for ordinary and instrumented Mojo suites.

One inventory controls linking, per-suite keys and coverage-tree copies.
The fixtures never enter the production-module denominator. A dependent
suite fails if its fixture or compiler is unavailable. No test is skipped.

    native_test_support run --root . --suite SUITE --cache .cache/native -- \\
        mojo build -o BINARY SUITE
    native_test_support copy --root . --destination coverage/build
    native_test_support fingerprint --cc cc

`make test-cpu` runs the first form. `make coverage` runs this program for
each raw capture and for the fixture copy. A fixture suite is built and
then run in that capture's process group. The fixture table here and in
`tools/suite_key.mojo` is the same.
"""

from std.collections import Set
from std.ffi import c_int, external_call
from std.memory import OpaquePointer
from std.os import getenv, listdir, remove, rmdir
from std.pathlib import Path
from std.sys import CompilationTarget, argv, exit, stderr
from std.tempfile import mkdtemp

from tools._imports import SourceCache, closure, mojo_files
from tools._owned_process import (
    EINTR,
    ExecPlan,
    c_bytes,
    close_fd,
    errno,
    make_pipe,
    strerror,
    wait_blocking,
)
from tools._process import run_program
from tools._sha256 import sha256_hex

comptime C_FLAGS = [
    "-std=c11",
    "-O2",
    "-fPIC",
    "-Wall",
    "-Wextra",
    "-Werror",
]
"""The flags for every test-only C object."""

comptime FIXTURE_SUITES = [
    "tests/test_carla_sum2_environment.mojo",
    "tests/test_carla_junction_endpoint_refusals.mojo",
]
"""Suites that link `tools/fixtures/carla_sum2_fp_state.c`."""

comptime FIXTURE = "tools/fixtures/carla_sum2_fp_state.c"
"""The one C fixture those suites link."""


def fixture_inputs(files: List[String]) -> List[String]:
    """Return the sorted C fixtures that a set of files links.

    Args:
        files: A suite's import closure, or the suite path itself.

    Returns:
        Each fixture once. The list is empty when no suite needs one.
    """
    var needed = False
    for name in files:
        for suite in materialize[FIXTURE_SUITES]():
            if name == suite:
                needed = True
    if not needed:
        return List[String]()
    var found = List[String]()
    found.append(FIXTURE)
    return found^


def _json_string(text: String) -> String:
    """Return `text` as a JSON string, as `json.dumps` writes ASCII."""
    var out = '"'
    for byte in text.as_bytes():
        if byte == 34:
            out += '\\"'
        elif byte == 92:
            out += "\\\\"
        elif byte == 10:
            out += "\\n"
        elif byte == 13:
            out += "\\r"
        elif byte == 9:
            out += "\\t"
        elif byte < 32:
            var digits = "0123456789abcdef".as_bytes()
            var raw = List[UInt8]()
            raw.append(92)
            raw.append(117)
            raw.append(48)
            raw.append(48)
            raw.append(digits[Int(byte) // 16])
            raw.append(digits[Int(byte) % 16])
            out += String(from_utf8_lossy=raw)
        else:
            var raw = List[UInt8]()
            raw.append(byte)
            out += String(from_utf8_lossy=raw)
    return out + '"'


def _json_strings(items: List[String]) -> String:
    """Return a JSON array of strings with Python's separators."""
    var out = "["
    var first = True
    for item in items:
        if not first:
            out += ", "
        first = False
        out += _json_string(item)
    return out + "]"


def _sort(mut names: List[String]):
    """Sort strings in byte order."""
    var index = 1
    while index < len(names):
        var item = names[index]
        var place = index
        while place > 0 and names[place - 1] > item:
            names[place] = names[place - 1]
            place -= 1
        names[place] = item
        index += 1


struct CompilerIdentity(Copyable, Movable):
    """The C compiler inputs that invalidate a fixture object."""

    var command: List[String]
    """The compiler and its fixed arguments, split as `shlex` splits them."""
    var version: String
    """The standard output of `compiler --version`."""
    var files: List[String]
    """Resolved compiler files, sorted."""
    var digests: List[String]
    """SHA-256 of each file, in the same order."""
    var system: String
    """`uname` sysname."""
    var machine: String
    """`uname` machine."""

    def __init__(
        out self,
        var command: List[String],
        version: String,
        var files: List[String],
        var digests: List[String],
        system: String,
        machine: String,
    ):
        self.command = command^
        self.version = version
        self.files = files^
        self.digests = digests^
        self.system = system
        self.machine = machine

    def json(self) -> String:
        """Return this identity as `json.dumps(..., sort_keys=True)`.

        Returns:
            The compact JSON object.
        """
        var flags = List[String]()
        for flag in materialize[C_FLAGS]():
            flags.append(flag)
        return (
            '{"command": '
            + _json_strings(self.command)
            + ', "files": '
            + _json_files(self.files, self.digests)
            + ', "flags": '
            + _json_strings(flags)
            + ', "machine": '
            + _json_string(self.machine)
            + ', "system": '
            + _json_string(self.system)
            + ', "version": '
            + _json_string(self.version)
            + "}"
        )


def _json_files(files: List[String], digests: List[String]) -> String:
    """Return a JSON object of path to digest, keys already sorted."""
    var out = "{"
    var index = 0
    while index < len(files):
        if index > 0:
            out += ", "
        out += _json_string(files[index]) + ": " + _json_string(digests[index])
        index += 1
    return out + "}"


def _split_command(text: String) -> List[String]:
    """Split a command as `shlex.split` does for quotes and spaces."""
    var words = List[String]()
    var current = String()
    var quote = UInt8(0)
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes):
        var byte = bytes[index]
        if quote == 0 and (byte == 32 or byte == 9 or byte == 10):
            if current.byte_length() > 0:
                words.append(current)
                current = String()
            index += 1
            continue
        if quote == 0 and (byte == 39 or byte == 34):
            quote = byte
            index += 1
            continue
        if quote != 0 and byte == quote:
            quote = 0
            index += 1
            continue
        if byte == 92 and quote != 39 and index + 1 < len(bytes):
            index += 1
            byte = bytes[index]
        var raw = List[UInt8]()
        raw.append(byte)
        current += String(from_utf8_lossy=raw)
        index += 1
    if current.byte_length() > 0:
        words.append(current)
    return words^


def _is_file(path: String) -> Bool:
    """Return whether `path` is a regular file."""
    return Path(path).is_file()


def _which(name: String) -> String:
    """Return the first executable `name` on `PATH`, or empty."""
    if name.find("/") >= 0:
        return name if _is_file(name) else String()
    var path = getenv("PATH", "/bin:/usr/bin")
    for directory in path.split(":"):
        var folder = String(directory)
        var candidate = (
            folder + "/" + name if folder.byte_length() > 0 else name
        )
        if _is_file(candidate):
            return candidate
    return String()


def _resolve(path: String) raises -> String:
    """Return the absolute path with symlinks removed.

    Args:
        path: A file or directory.

    Returns:
        The absolute path.

    Raises:
        Error: If the path cannot be resolved.
    """
    from std.os.path import realpath

    return realpath(path)


def _uname_field(index: Int) -> String:
    """Return one `uname` field. 0 is the system and 4 is the machine."""
    var buffer = List[UInt8](length=2048, fill=0)
    _ = external_call["uname", c_int](
        buffer.unsafe_ptr().unsafe_bitcast[NoneType]()
    )
    var width = 65
    comptime if CompilationTarget.is_macos():
        width = 256
    var text = List[UInt8]()
    var offset = index * width
    var cursor = 0
    while cursor < width:
        var byte = buffer[offset + cursor]
        if byte == 0:
            break
        text.append(byte)
        cursor += 1
    return String(from_utf8_lossy=text)


def compiler_identity(cc: String) raises -> CompilerIdentity:
    """Bind the compiler command, its version and its executable bytes.

    Args:
        cc: The compiler command, as the `CC` environment gives it.

    Returns:
        The identity. A replacement with the same `--version` text still
        differs when the executable bytes differ.

    Raises:
        Error: If the command is empty, the compiler is missing, or
            `--version` fails.
    """
    var command = _split_command(cc)
    if len(command) == 0:
        raise Error("native test compiler command is empty")
    var version_args = _copy(command)
    version_args.append("--version")
    var version = run_program(version_args, 30.0, merge_errors=False)
    if version.status != 0:
        raise Error("native test compiler --version failed: " + version.errors)
    var files = List[String]()
    var digests = List[String]()
    var index = 0
    while index < len(command):
        var argument = command[index]
        var candidate = argument
        if not _is_file(candidate):
            var found = _which(argument)
            if found.byte_length() == 0:
                if index == 0:
                    raise Error("native test compiler executable is missing")
                index += 1
                continue
            candidate = found
        var resolved = _resolve(candidate)
        var digest = sha256_hex(Path(resolved).read_bytes())
        files.append(resolved)
        digests.append(digest)
        index += 1
    var order = List[Int]()
    var place = 0
    while place < len(files):
        order.append(place)
        place += 1
    var cursor = 1
    while cursor < len(order):
        var item = order[cursor]
        var slot = cursor
        while slot > 0 and files[order[slot - 1]] > files[item]:
            order[slot] = order[slot - 1]
            slot -= 1
        order[slot] = item
        cursor += 1
    var sorted_files = List[String]()
    var sorted_digests = List[String]()
    for item in order:
        sorted_files.append(files[item])
        sorted_digests.append(digests[item])
    return CompilerIdentity(
        command^,
        version.output,
        sorted_files^,
        sorted_digests^,
        _uname_field(0),
        _uname_field(4),
    )


def _copy(words: List[String]) -> List[String]:
    """Return a copy of a command."""
    var out = List[String]()
    for word in words:
        out.append(word)
    return out^


def dependency_inputs(root: String, suite: String) raises -> List[String]:
    """Return the C fixtures a suite links, through its Mojo imports.

    Args:
        root: The repository root, or the instrumented tree.
        suite: The suite path. It may be absolute.

    Returns:
        The fixture paths relative to `root`.

    Raises:
        Error: If the suite is outside `root` or an import cannot be read.
    """
    var root_real = _resolve(root)
    var suite_real = _resolve(suite)
    var prefix = root_real + "/"
    if not suite_real.startswith(prefix):
        raise Error("suite is outside the root: " + suite)
    var relative = String(suite_real[byte = prefix.byte_length() :])
    var known = Set[String]()
    for path in mojo_files(root_real):
        known.add(path)
    var cache = SourceCache()
    var files = closure(root_real, relative, known, cache)
    return fixture_inputs(files)


def _inputs_json(
    source: String, digest: String, identity: CompilerIdentity
) -> String:
    """Return the object cache key's JSON, with sorted keys."""
    return (
        '{"compiler": '
        + identity.json()
        + ', "sha256": '
        + _json_string(digest)
        + ', "source": '
        + _json_string(source)
        + "}"
    )


def _mkdir(path: String) raises:
    """Create a directory and its parents."""
    var made = run_program(["mkdir", "-p", path], 10.0)
    if made.status != 0:
        raise Error("cannot create " + path + ": " + made.output)


def _rename(source: String, target: String) raises:
    """Replace `target` with `source`."""
    var from_path = c_bytes(source)
    var to_path = c_bytes(target)
    if (
        external_call["rename", c_int](
            from_path.unsafe_ptr().unsafe_bitcast[NoneType](),
            to_path.unsafe_ptr().unsafe_bitcast[NoneType](),
        )
        != 0
    ):
        raise Error("rename failed: " + strerror(errno()))


def build_object(
    root: String, fixture: String, cache: String, identity: CompilerIdentity
) raises -> String:
    """Compile one fixture, or return the cached object when its bytes match.

    Args:
        root: The tree that holds the fixture.
        fixture: The fixture path relative to `root`.
        cache: The object cache directory.
        identity: The compiler identity.

    Returns:
        The absolute object path.

    Raises:
        Error: If compilation fails or the fixture changes while it compiles.
    """
    var source = _resolve(root) + "/" + fixture
    var data = Path(source).read_bytes()
    var digest = sha256_hex(data)
    var key = sha256_hex(_inputs_json(source, digest, identity).as_bytes())
    _mkdir(cache)
    var cache_dir = _resolve(cache)
    var output = cache_dir + "/" + key + ".o"
    var metadata = cache_dir + "/" + key + ".json"
    if Path(output).is_file() and Path(metadata).is_file():
        var object_hash = sha256_hex(Path(output).read_bytes())
        var saved = Path(metadata).read_text()
        if (
            saved.find(digest) >= 0
            and saved.find(object_hash) >= 0
            and saved.find(_json_string(identity.version)) >= 0
        ):
            return output
    var temporary = cache_dir + "/" + key + ".tmp.o"
    var command = _copy(identity.command)
    for flag in materialize[C_FLAGS]():
        command.append(flag)
    command.append("-c")
    command.append(source)
    command.append("-o")
    command.append(temporary)
    var compiled = run_program(command, 120.0)
    if compiled.status != 0:
        raise Error("native test build failed: " + compiled.output)
    if sha256_hex(Path(source).read_bytes()) != digest:
        raise Error(
            "native test fixture changed during compilation: " + fixture
        )
    var object_hash = sha256_hex(Path(temporary).read_bytes())
    _rename(temporary, output)
    var record = (
        '{\n  "command": '
        + _json_strings(command)
        + ',\n  "inputs": '
        + _inputs_json(source, digest, identity)
        + ',\n  "object_sha256": '
        + _json_string(object_hash)
        + "\n}\n"
    )
    Path(metadata).write_text(record)
    return output


def _normalize(path: String) raises -> String:
    """Return an absolute path. A missing path is not resolved through links.

    Args:
        path: A path that may not exist yet, such as a build output.

    Returns:
        The absolute path.

    Raises:
        Error: If an existing path cannot be resolved.
    """
    if Path(path).exists():
        return _resolve(path)
    if path.startswith("/"):
        return path
    return _resolve(".") + "/" + path


def _source_index(command: List[String], suite: String) raises -> Int:
    """Return the one non-option argument that is the suite, or -1."""
    var resolved = _normalize(suite)
    var found = -1
    var count = 0
    var index = 2
    while index < len(command):
        var argument = command[index]
        if argument.byte_length() > 0 and argument.as_bytes()[0] != 45:
            if _normalize(argument) == resolved:
                found = index
                count += 1
        index += 1
    if count != 1:
        return -1
    return found


def prepare_command(
    root: String,
    suite: String,
    cache: String,
    cc: String,
    command: List[String],
) raises -> List[String]:
    """Insert fixture objects in front of the suite in a Mojo build command.

    Args:
        root: The tree that holds the suite and the fixtures.
        suite: The suite path.
        cache: The object cache.
        cc: The C compiler command.
        command: The Mojo command. A build command has `build` as argument 2.

    Returns:
        The command. It is unchanged when the suite links no fixture.

    Raises:
        Error: If a fixture suite is not a build command, or the suite path
            does not occur once.
    """
    var fixtures = dependency_inputs(root, suite)
    if len(fixtures) == 0:
        return _copy(command)
    if len(command) < 2 or command[1] != "build":
        raise Error(
            "native fixture object linking requires a Mojo build command"
        )
    var index = _source_index(command, suite)
    if index < 0:
        raise Error(
            "native fixture suite must occur exactly once in the Mojo command"
        )
    var identity = compiler_identity(cc)
    var objects = List[String]()
    for name in fixtures:
        objects.append(build_object(root, name, cache, identity))
    var prepared = List[String]()
    var cursor = 0
    while cursor < index:
        prepared.append(command[cursor])
        cursor += 1
    for path in objects:
        prepared.append("-Xlinker")
        prepared.append(path)
    while cursor < len(command):
        prepared.append(command[cursor])
        cursor += 1
    return prepared^


def _exec(command: List[String]) raises:
    """Replace this process with `command`.

    Args:
        command: The program and its arguments.

    Raises:
        Error: If no program starts.
    """
    if len(command) == 0:
        raise Error("a Mojo command is required after --")
    var plan = ExecPlan(command)
    var number = plan.run()
    raise Error("exec failed: " + strerror(number))


def _address(address: Int) -> OpaquePointer[MutAnyOrigin]:
    """Return `address` as a C pointer.

    Args:
        address: A live address.

    Returns:
        The pointer.
    """
    return OpaquePointer[MutAnyOrigin](unsafe_from_address=address)


def _spawn_same_group(command: List[String]) raises -> Int:
    """Run `command` in this process group and return its status.

    The child keeps the standard streams, so coverage probes stay on the
    capture pipe. A signal that stops the child has status 128 plus the
    signal number.

    Args:
        command: The program and its arguments.

    Returns:
        The exit status.

    Raises:
        Error: If the program cannot start or the wait fails.
    """
    if len(command) == 0:
        raise Error("a Mojo command is required after --")
    var plan = ExecPlan(command)
    var pipe = make_pipe()
    var report = List[Int32](length=1, fill=0)
    var pid = Int(external_call["fork", c_int]())
    if pid == 0:
        report[0] = Int32(plan.run())
        _ = external_call["write", Int](
            Int32(pipe[1]),
            _address(Int(report.unsafe_ptr())),
            4,
        )
        external_call["_exit", NoneType](c_int(127))
    var fork_error = errno()
    close_fd(pipe[1])
    if pid < 0:
        close_fd(pipe[0])
        raise Error("fork failed: " + strerror(fork_error))
    return _wait_child(pid, pipe[0], report, command[0])


def _wait_child(
    pid: Int, read_fd: Int, report: List[Int32], name: String
) raises -> Int:
    """Reap a spawned child and return its status.

    Args:
        pid: The child.
        read_fd: The pipe that reports an `exec` failure.
        report: The four-byte `errno` buffer.
        name: The program name for an `exec` error.

    Returns:
        The exit status. A signal N has status 128 + N.

    Raises:
        Error: If the program cannot start or the wait fails.
    """
    var got = 0
    while True:
        var count = external_call["read", Int](
            Int32(read_fd),
            _address(Int(report.unsafe_ptr()) + got),
            4 - got,
        )
        if count > 0:
            got += count
            if got == 4:
                break
            continue
        if count < 0 and errno() == EINTR:
            continue
        break
    close_fd(read_fd)
    if got == 4:
        _ = wait_blocking(pid)
        raise Error("cannot start " + name + ": " + strerror(Int(report[0])))
    var waited = wait_blocking(pid)
    if not waited.done:
        raise Error("wait failed: " + strerror(waited.error))
    if waited.status < 0:
        return 128 - waited.status
    return waited.status


def _spawn_file(file: String, command: List[String]) raises -> Int:
    """Run `file` with `command` as its arguments, in this process group.

    `command` begins with the name the program sees. That name can differ
    from `file`, as Python's `executable=` argument does.

    Args:
        file: The program file.
        command: The arguments, including the name in the first position.

    Returns:
        The exit status.

    Raises:
        Error: If the program cannot start or the wait fails.
    """
    if len(command) == 0:
        raise Error("a Mojo command is required after --")
    var path = c_bytes(file)
    var words = List[List[UInt8]]()
    for word in command:
        words.append(c_bytes(word))
    var pointers = List[Int]()
    for index in range(len(words)):
        pointers.append(Int(words[index].unsafe_ptr()))
    pointers.append(0)
    var pipe = make_pipe()
    var report = List[Int32](length=1, fill=0)
    var pid = Int(external_call["fork", c_int]())
    if pid == 0:
        _ = external_call["execv", c_int](
            _address(Int(path.unsafe_ptr())),
            _address(Int(pointers.unsafe_ptr())),
        )
        report[0] = Int32(errno())
        _ = external_call["write", Int](
            Int32(pipe[1]),
            _address(Int(report.unsafe_ptr())),
            4,
        )
        external_call["_exit", NoneType](c_int(127))
    var fork_error = errno()
    close_fd(pipe[1])
    if pid < 0:
        close_fd(pipe[0])
        raise Error("fork failed: " + strerror(fork_error))
    return _wait_child(pid, pipe[0], report, file)


def _clear_directory(directory: String) raises:
    """Remove a flat directory and the files in it.

    Args:
        directory: The directory. A missing directory is left alone.

    Raises:
        Error: If a file or the directory cannot be removed.
    """
    if not Path(directory).is_dir():
        return
    for name in listdir(directory):
        remove(Path(directory) / name)
    rmdir(directory)


struct _FixtureRun(Movable):
    """The build command and the program command for one fixture suite."""

    var build: List[String]
    """The Mojo build command, including the fixture objects."""
    var execute: List[String]
    """The program and the arguments that follow the suite."""

    def __init__(out self, var build: List[String], var execute: List[String]):
        """Make the pair.

        Args:
            build: The build command.
            execute: The program command.
        """
        self.build = build^
        self.execute = execute^


def _first_source(command: List[String], suite: String) raises -> Int:
    """Return the first non-option argument that is the suite.

    Args:
        command: A Mojo run command.
        suite: The suite path.

    Returns:
        The index of the suite.

    Raises:
        Error: If the command is not a run command, or the suite is absent.
    """
    if len(command) < 3 or command[1] != "run":
        raise Error("native fixture execution requires a Mojo run command")
    var resolved = _normalize(suite)
    var index = 2
    while index < len(command):
        var argument = command[index]
        if argument.byte_length() > 0 and argument.as_bytes()[0] != 45:
            if _normalize(argument) == resolved:
                return index
        index += 1
    raise Error("native fixture run is missing its Mojo source")


def prepare_run_commands(
    root: String,
    suite: String,
    cache: String,
    cc: String,
    command: List[String],
    executable: String,
) raises -> _FixtureRun:
    """Translate a fixture `mojo run` into a build and a program.

    Args:
        root: The tree that holds the suite and the fixtures.
        suite: The suite path.
        cache: The object cache.
        cc: The C compiler command.
        command: The Mojo run command and the program arguments.
        executable: The fresh program path for this run.

    Returns:
        The build command and the program command.

    Raises:
        Error: If the command is not a run command, the suite is absent,
            or a fixture object cannot be built.
    """
    var index = _first_source(command, suite)
    var build = List[String]()
    build.append(command[0])
    build.append("build")
    var cursor = 2
    while cursor < index:
        build.append(command[cursor])
        cursor += 1
    build.append("-o")
    build.append(executable)
    build.append(command[index])
    var prepared = prepare_command(root, suite, cache, cc, build)
    var execute = List[String]()
    execute.append(executable)
    cursor = index + 1
    while cursor < len(command):
        execute.append(command[cursor])
        cursor += 1
    return _FixtureRun(prepared^, execute^)


def run_fixture(
    root: String,
    suite: String,
    cache: String,
    cc: String,
    command: List[String],
    program_name: String = "",
) raises -> Int:
    """Build a fixture suite and run that program in this process group.

    Args:
        root: The tree that holds the suite and the fixtures.
        suite: The suite path.
        cache: The object cache.
        cc: The C compiler command.
        command: The Mojo run command and the program arguments.
        program_name: The name the program sees, when it differs from the
            built file. Empty keeps the built file's path.

    Returns:
        The build status, or the program status when the build exits 0.

    Raises:
        Error: If the command cannot be translated or a program cannot
            start. The fresh program directory is removed either way.
    """
    var folder = mkdtemp(prefix="threemojo-native-run-")
    try:
        var plan = prepare_run_commands(
            root, suite, cache, cc, command, folder + "/suite"
        )
        var status = _spawn_same_group(plan.build)
        if status == 0:
            if program_name.byte_length() == 0:
                status = _spawn_same_group(plan.execute)
            else:
                var argv = List[String]()
                argv.append(program_name)
                var index = 1
                while index < len(plan.execute):
                    argv.append(plan.execute[index])
                    index += 1
                status = _spawn_file(plan.execute[0], argv)
        return status
    finally:
        _clear_directory(folder)


def copy_fixtures(root: String, destination: String) raises:
    """Copy every fixture into an instrumented tree.

    Args:
        root: The source tree.
        destination: The instrumented tree.

    Raises:
        Error: If a fixture is missing or the copy changes its bytes.
    """
    var names = List[String]()
    for suite in materialize[FIXTURE_SUITES]():
        names.append(suite)
    var files = fixture_inputs(names)
    for name in files:
        var source = _resolve(root) + "/" + name
        _mkdir(destination)
        var target = _resolve(destination) + "/" + name
        var slash = target.rfind("/")
        if slash > 0:
            _mkdir(String(target[byte=:slash]))
        var data = Path(source).read_bytes()
        Path(target).write_bytes(data)
        if sha256_hex(Path(target).read_bytes()) != sha256_hex(data):
            raise Error("native fixture copy changed: " + name)


def fingerprint(cc: String) raises -> String:
    """Return the cache key of one compiler identity.

    Args:
        cc: The compiler command.

    Returns:
        The SHA-256 hex digest of the identity's sorted JSON.

    Raises:
        Error: If the compiler cannot be identified.
    """
    return sha256_hex(compiler_identity(cc).json().as_bytes())


def _value(arguments: List[String], name: String, index: Int) raises -> String:
    """Return the argument after `name`.

    Args:
        arguments: The command line.
        name: The option.
        index: The index of the option.

    Returns:
        The value.

    Raises:
        Error: If the value is missing.
    """
    if index + 1 >= len(arguments):
        raise Error(name + " needs a value")
    return arguments[index + 1]


def run_cli(arguments: List[String]) raises -> Int:
    """Run one subcommand.

    Args:
        arguments: The arguments, without the program name.

    Returns:
        The exit status.

    Raises:
        Error: If a subcommand fails before it replaces the process.
    """
    if len(arguments) == 0:
        raise Error("usage: native_test_support run|copy|fingerprint ...")
    var mode = arguments[0]
    var cc = getenv("CC", "cc")
    var root = String()
    var suite = String()
    var cache = String()
    var destination = String()
    var command = List[String]()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--":
            index += 1
            while index < len(arguments):
                command.append(arguments[index])
                index += 1
            break
        if word == "--root":
            root = _value(arguments, word, index)
            index += 1
        elif word == "--suite":
            suite = _value(arguments, word, index)
            index += 1
        elif word == "--cache":
            cache = _value(arguments, word, index)
            index += 1
        elif word == "--destination":
            destination = _value(arguments, word, index)
            index += 1
        elif word == "--cc":
            cc = _value(arguments, word, index)
            index += 1
        elif word.startswith("--"):
            raise Error("unknown argument " + word)
        else:
            command.append(word)
        index += 1
    if mode == "fingerprint":
        print(fingerprint(cc))
        return 0
    if mode == "copy":
        if root.byte_length() == 0 or destination.byte_length() == 0:
            raise Error("copy requires --root and --destination")
        copy_fixtures(root, destination)
        return 0
    if mode != "run":
        raise Error("unknown command " + mode)
    if (
        root.byte_length() == 0
        or suite.byte_length() == 0
        or cache.byte_length() == 0
    ):
        raise Error("run requires --root, --suite and --cache")
    if len(command) >= 2 and command[1] == "run":
        var needed = dependency_inputs(root, suite)
        if len(needed) > 0:
            return run_fixture(root, suite, cache, cc, command)
    var prepared = prepare_command(root, suite, cache, cc, command)
    _exec(prepared)
    return 1


def main() raises:
    """Link test-only C fixtures, copy them, or fingerprint the compiler."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        exit(run_cli(arguments))
    except error:
        print("native test support failed: " + String(error), file=stderr)
        exit(1)
