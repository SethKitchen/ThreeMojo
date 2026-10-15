# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check native asset lookup and temporary-root ownership across processes.

    sh tools/tool.sh .venv/bin/mojo check_portability --mojo .venv/bin/mojo

Compilation is separate from each unchanged five-second execution limit.
The check never changes the assets and needs no GPU or Python bridge in Mojo.
The tool works on the repository in the current directory.

Each child process gets the environment of this process, without the asset
root, the test scratch root and the probe's own settings, and then the
values of its case. A POSIX shell sets them before it runs the child.
"""

from std.os import getenv, listdir, mkdir
from std.os.path import isfile, realpath
from std.pathlib import Path
from std.subprocess import run
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp
from std.time import perf_counter_ns, sleep

from tools._cli import (
    CommandLine,
    absolute_path,
    normal_path,
    parse_command_line,
)
from tools._process import ProcessResult, run_program, shell_quote
from tools.run_suite import result_errors, slow_tests

comptime SECONDS = 5
"""The time limit of one child process, in seconds."""
comptime BUILD_SECONDS = 300
"""The time limit of one compilation, in seconds."""
comptime PROGRAM = "check_portability.mojo"
"""The program name in usage messages."""
comptime USAGE = "usage: check_portability.mojo [-h] [--mojo MOJO]\n"
"""The usage text, as `argparse` writes it."""
comptime HELP = (
    "\nCheck native asset lookup and temporary-root ownership across"
    " processes.\n\noptions:\n  -h, --help   show this help message and"
    " exit\n  --mojo MOJO\n"
)
"""The help text after the usage."""
comptime PASS_MARKER = "PORTABILITY PASS"
"""The line that a successful probe prints."""
comptime SCRATCH_ERROR = "expected direct-process failure"
"""The error that the probe raises on request."""

comptime Setting = Tuple[String, String]
"""One environment variable and its value."""


def parse_portability(arguments: List[String]) -> CommandLine:
    """Parse the tool's command line.

    Args:
        arguments: The arguments, without the program name.

    Returns:
        The options. A nonzero status carries the text to print.
    """
    return parse_command_line(
        arguments, PROGRAM, USAGE, HELP, List[String](), ["--mojo"]
    )


def environment_script(settings: List[Setting]) -> String:
    """Return a shell script that sets a child's environment and runs it.

    The script removes the inherited asset root, the inherited scratch root
    and every `THREEMOJO_PORTABILITY_` variable. Then it sets `settings` in
    order, so a later value replaces an earlier one, and runs its arguments
    with `exec`.

    Args:
        settings: The child's variables and values.

    Returns:
        The script, for `sh -c SCRIPT sh PROGRAM ARGUMENT...`.
    """
    var script = String(
        "unset THREEMOJO_ASSET_ROOT THREEMOJO_TEST_TMPDIR\n"
        "for name in $(env | sed -n"
        " 's/^\\(THREEMOJO_PORTABILITY_[A-Za-z0-9_]*\\)=.*/\\1/p'); do\n"
        '    unset "$name"\n'
        "done\n"
    )
    for setting in settings:
        script += "export " + setting[0] + "=" + shell_quote(setting[1]) + "\n"
    script += 'exec "$@"\n'
    return script^


def child_command(
    settings: List[Setting], var program: List[String]
) -> List[String]:
    """Return the arguments that run a program in a child environment.

    Args:
        settings: The child's variables and values.
        program: The program and its arguments.

    Returns:
        The shell command.
    """
    var command: List[String] = [
        "sh",
        "-c",
        environment_script(settings),
        "sh",
    ]
    command.extend(program^)
    return command^


def check_child(
    status: Int,
    output: String,
    timed_out: Bool,
    error: Optional[String] = None,
    suite: Bool = False,
) raises:
    """Require a bounded successful child or a specific controlled failure.

    A status over 128 is a child that a signal stopped, as Python's negative
    return code is. It is never a controlled failure.

    Args:
        status: The child's exit status.
        output: The child's standard output and standard error.
        timed_out: True when the time limit stopped the child.
        error: The diagnostic of an expected controlled failure.
        suite: True for a `TestSuite` program, which prints no marker.

    Raises:
        Error: If the child did not end as the case requires.
    """
    if timed_out:
        raise Error(
            "Child timed out after " + String(SECONDS) + " seconds: " + output
        )
    if error:
        if status <= 0 or status > 128 or not error.value() in output:
            raise Error(
                "Expected controlled error '"
                + error.value()
                + "': status "
                + String(status)
                + ": "
                + output
            )
        return
    if status != 0 or (not suite and not PASS_MARKER in output):
        raise Error("Child failed: status " + String(status) + ": " + output)
    if suite and (
        len(result_errors(output)) > 0
        or len(slow_tests(output, Float64(SECONDS))) > 0
    ):
        raise Error("Invalid or slow suite: " + output)


def run_child(
    var program: List[String],
    settings: List[Setting],
    directory: String,
    error: Optional[String] = None,
    suite: Bool = False,
) raises -> ProcessResult:
    """Run a child with the time limit and check how it ended.

    Args:
        program: The program and its arguments.
        settings: The child's variables and values.
        directory: The child's working directory.
        error: The diagnostic of an expected controlled failure.
        suite: True for a `TestSuite` program.

    Returns:
        The child's result.

    Raises:
        Error: If the child did not end as the case requires.
    """
    var result = run_program(
        child_command(settings, program^),
        Float64(SECONDS),
        directory=directory,
    )
    check_child(result.status, result.output, result.timed_out, error, suite)
    return result^


def parent_path(path: String) -> String:
    """Return a path's parent, as `pathlib`'s `parent` does.

    Args:
        path: A path.

    Returns:
        The path without its last part.
    """
    var normal = normal_path(path)
    var slash = normal.rfind("/")
    if slash < 0:
        return "."
    if slash == 0:
        return "/"
    return String(normal[byte=:slash])


def _parts(path: String) -> List[String]:
    """Return the nonempty parts of a path."""
    var parts = List[String]()
    for part in path.split("/"):
        var text = String(part)
        if text.byte_length() > 0:
            parts.append(text)
    return parts^


def relative_path(path: String, start: String) -> String:
    """Return `os.path.relpath(path, start)` for two absolute paths.

    Args:
        path: The target, absolute.
        start: The directory to go from, absolute.

    Returns:
        The relative path, or `.` for the same path.
    """
    var to = _parts(normal_path(path))
    var origin = _parts(normal_path(start))
    var common = 0
    while (
        common < len(to)
        and common < len(origin)
        and to[common] == origin[common]
    ):
        common += 1
    var parts = List[String]()
    for _ in range(common, len(origin)):
        parts.append("..")
    for index in range(common, len(to)):
        parts.append(to[index])
    if len(parts) == 0:
        return "."
    return "/".join(parts)


def which(name: String) -> String:
    """Return the command a name runs, as `shutil.which(name) or name`.

    Args:
        name: A command name or a path.

    Returns:
        The first file of that name on `PATH` when the name has no slash,
        otherwise the name.
    """
    if "/" in name:
        return name
    for directory in getenv("PATH").split(":"):
        var folder = String(directory) if directory else String(".")
        var candidate = folder + "/" + name
        if isfile(candidate):
            return candidate
    return name


def _entries(directory: String) raises -> List[String]:
    """Return the names in a directory."""
    var names = List[String]()
    for name in listdir(directory):
        names.append(name)
    return names^


def _require_empty(directory: String) raises:
    """Raise an error unless a directory is empty."""
    var names = _entries(directory)
    if len(names) > 0:
        raise Error(directory + " is not empty: " + ", ".join(names))


def _require(condition: Bool, message: String) raises:
    """Raise an error with a message unless a condition holds."""
    if not condition:
        raise Error(message)


def _nonempty(path: String) raises -> Bool:
    """Return whether a file exists and has content."""
    return Path(path).exists() and len(Path(path).read_bytes()) > 0


def _remove_tree(path: String) raises:
    """Remove a directory and what it holds."""
    _ = run_program(["rm", "-rf", path], 60)


def _seconds_since(start: Int) -> Float64:
    """Return the seconds since a `perf_counter_ns` time."""
    return Float64(perf_counter_ns() - start) / 1e9


struct Background(Copyable, Movable):
    """A child process that runs while this process checks its files."""

    var scratch: String
    """A directory of this process for the child's output, status and
    process id."""

    def __init__(
        out self,
        program: String,
        settings: List[Setting],
        directory: String,
    ) raises:
        """Start a child in the background.

        Args:
            program: The program, which runs with no arguments.
            settings: The child's variables and values.
            directory: The child's working directory.

        Raises:
            Error: If the shell cannot start the child.
        """
        self.scratch = mkdtemp(prefix="threemojo-child-")
        var inner = (
            'echo "$$" >"$1/pid"\ncd -- "$2" || exit 1\nshift 2\n'
            + environment_script(settings)
        )
        var script = (
            "( sh -c "
            + shell_quote(inner)
            + " sh "
            + shell_quote(self.scratch)
            + " "
            + shell_quote(directory)
            + " "
            + shell_quote(program)
            + ' </dev/null >"$0/output" 2>&1; echo "$?" >"$0/status.new";'
            + ' mv "$0/status.new" "$0/status" ) </dev/null >/dev/null 2>&1 &'
        )
        _ = run(
            "sh -c " + shell_quote(script) + " " + shell_quote(self.scratch)
        )

    def poll(self) raises -> Optional[Int]:
        """Return the exit status once the child has ended.

        Returns:
            The status, or nothing while the child runs.

        Raises:
            Error: If the status file cannot be read.
        """
        var path = self.scratch + "/status"
        if not Path(path).exists():
            return None
        return Int(Path(path).read_text().strip())

    def kill(self) raises:
        """Stop the child with `SIGKILL`.

        Raises:
            Error: If the child has not started within the time limit.
        """
        var start = perf_counter_ns()
        while not _nonempty(self.scratch + "/pid"):
            if self.poll() or _seconds_since(start) > Float64(SECONDS):
                return
            sleep(0.005)
        var pid = String(Path(self.scratch + "/pid").read_text().strip())
        _ = run_program(["kill", "-KILL", pid], 10)

    def communicate(self, timeout: Float64) raises -> Tuple[Int, String]:
        """Wait for the child to end.

        Args:
            timeout: The time limit in seconds.

        Returns:
            The exit status and the output.

        Raises:
            Error: If the child does not end in time.
        """
        var start = perf_counter_ns()
        while True:
            var status = self.poll()
            if status:
                return (
                    status.value(),
                    String(
                        from_utf8_lossy=Path(
                            self.scratch + "/output"
                        ).read_bytes()
                    ),
                )
            if _seconds_since(start) > timeout:
                raise Error("Child timed out after " + String(timeout) + " s")
            sleep(0.005)

    def close(self) raises:
        """Stop the child if it runs, wait for it and remove the scratch
        files.

        Raises:
            Error: If the child does not end in time.
        """
        try:
            if not self.poll():
                self.kill()
            _ = self.communicate(Float64(SECONDS))
        finally:
            _remove_tree(self.scratch)


def check_assets(binary: String, folder: String, assets: String) raises:
    """Check the asset roots: absolute, relative, unset, empty, missing and
    an explicit file.

    Args:
        binary: The built probe.
        folder: The check's temporary directory.
        assets: The repository's asset directory, absolute.

    Raises:
        Error: If a case fails.
    """
    var root = realpath(".")
    var unrelated = folder + "/unrelated working directory"
    mkdir(unrelated)
    var missing = folder + "/nonexistent asset root"
    # Both high-level loaders work outside the repository with an absolute
    # root.
    for loader in [
        ("face", "face/ict_face.bin"),
        ("hair", "hair/layered.bin"),
    ]:
        var action = String(loader[0])
        var suffix = String(loader[1])
        _ = run_child(
            [binary],
            [
                ("THREEMOJO_ASSET_ROOT", assets),
                ("THREEMOJO_PORTABILITY_ACTION", action),
            ],
            unrelated,
        )
        # A relative root keeps its original call-time working-directory
        # meaning.
        _ = run_child(
            [binary],
            [
                ("THREEMOJO_ASSET_ROOT", relative_path(assets, unrelated)),
                ("THREEMOJO_PORTABILITY_ACTION", action),
            ],
            unrelated,
        )
        # Check unset and empty repository-root defaults without changing
        # fixtures.
        _ = run_child(
            [binary], [("THREEMOJO_PORTABILITY_ACTION", action)], root
        )
        _ = run_child(
            [binary],
            [
                ("THREEMOJO_PORTABILITY_ACTION", action),
                ("THREEMOJO_ASSET_ROOT", ""),
            ],
            root,
        )
        # No silent fallback, even when the working directory has valid
        # defaults.
        for directory in [root, unrelated]:
            _ = run_child(
                [binary],
                [
                    ("THREEMOJO_ASSET_ROOT", missing),
                    ("THREEMOJO_PORTABILITY_ACTION", action),
                ],
                directory,
                error=missing + "/" + suffix,
            )
    # Explicit file callers are independent of the high-level root setting.
    _ = run_child(
        [binary],
        [
            ("THREEMOJO_ASSET_ROOT", missing),
            ("THREEMOJO_PORTABILITY_ACTION", "explicit"),
            ("THREEMOJO_PORTABILITY_MODEL", assets + "/face/ict_face.bin"),
        ],
        unrelated,
    )
    print(
        "PASS asset roots: absolute, relative, unset, empty, missing,"
        " explicit file"
    )


def _with(settings: List[Setting], var more: List[Setting]) -> List[Setting]:
    """Return settings with more settings after them, which win."""
    var result = settings.copy()
    result.extend(more^)
    return result^


def _marked(marker: String) raises -> String:
    """Return the root that the probe wrote to a marker file."""
    return Path(marker).read_text()


def _owned_root(root: String, parent: String) raises:
    """Require a removed, absolute, process-owned root under `parent`."""
    _require(
        parent_path(root) == parent and root.startswith("/"),
        "Unexpected root: " + root,
    )
    _require(not Path(root).exists(), "Root was not removed: " + root)


def check_scratch(
    binary: String, suite: String, mojo: String, folder: String
) raises:
    """Check the temporary roots: direct runs, errors, nesting, borrowed
    roots, `TMPDIR`, concurrency and a cleanup error.

    Args:
        binary: The built probe.
        suite: The built scratch suite.
        mojo: The compiler, absolute.
        folder: The check's temporary directory.

    Raises:
        Error: If a case fails.
    """
    var root = realpath(".")
    var parent = folder + "/TMPDIR with spaces and an apostrophe's"
    mkdir(parent)
    var marker = folder + "/scratch-root.txt"
    var env: List[Setting] = [
        ("TMPDIR", parent),
        ("THREEMOJO_PORTABILITY_ACTION", "scratch"),
        ("THREEMOJO_PORTABILITY_MARKER", marker),
    ]
    for fail in ["", "yes"]:
        _ = run_child(
            [binary],
            _with(env, [("THREEMOJO_PORTABILITY_FAIL", fail)]),
            folder,
            error=Optional(String(SCRATCH_ERROR)) if fail else None,
        )
        _owned_root(_marked(marker), parent)
        _require_empty(parent)
    # A relative TMPDIR becomes an absolute, process-owned root.
    var tmpdir_name = String(parent[byte = parent.rfind("/") + 1 :])
    _ = run_child([binary], _with(env, [("TMPDIR", tmpdir_name)]), folder)
    _owned_root(_marked(marker), parent)
    # The stdlib can select relative TMP/TEMP when TMPDIR is empty. Cleanup
    # must retain the created absolute path even if the child changes cwd.
    var elsewhere = folder + "/different cleanup cwd"
    mkdir(elsewhere)
    _ = run_child(
        [binary],
        _with(
            env,
            [
                ("TMPDIR", ""),
                ("TMP", tmpdir_name),
                ("TEMP", tmpdir_name),
                ("THREEMOJO_PORTABILITY_CHDIR", elsewhere),
            ],
        ),
        folder,
    )
    _owned_root(_marked(marker), parent)
    _require_empty(elsewhere)
    _require_empty(parent)
    # Supplied roots remain caller-owned on both normal and exceptional exit.
    var borrowed = folder + "/runner-owned"
    mkdir(borrowed)
    var sentinel = borrowed + "/sentinel"
    Path(sentinel).write_text("keep")
    for fail in ["", "yes"]:
        _ = run_child(
            [binary],
            _with(
                env,
                [
                    ("THREEMOJO_TEST_TMPDIR", borrowed),
                    ("THREEMOJO_PORTABILITY_FAIL", fail),
                ],
            ),
            folder,
            error=Optional(String(SCRATCH_ERROR)) if fail else None,
        )
        _require(
            normal_path(_marked(marker)) == borrowed,
            "Borrowed root was not used: " + _marked(marker),
        )
        _require(Path(sentinel).read_text() == "keep", "Sentinel was changed")
        _require(
            Path(borrowed + "/same.bin").read_text() == "fixture",
            "Borrowed fixture was changed",
        )
        _require_empty(parent)
    _check_concurrent(binary, folder, parent, env)
    _check_cleanup_error(binary, folder, parent, env)
    # Built direct execution and literal mojo run need no wrapper or root
    # variable.
    var direct: List[Setting] = [("TMPDIR", parent)]
    _ = run_child([suite], direct, folder, suite=True)
    # mojo run includes compilation; TestSuite's own unchanged per-test
    # timings are checked below, while the compiler has a separate bounded
    # build budget.
    var result = run_program(
        child_command(
            direct,
            [
                mojo,
                "run",
                "--Werror",
                "-I",
                root,
                root + "/tests/test_scratch.mojo",
            ],
        ),
        Float64(BUILD_SECONDS),
        directory=folder,
    )
    _require(
        result.status == 0 and not result.timed_out,
        "mojo run failed: " + result.output,
    )
    _require(len(result_errors(result.output)) == 0, result.output)
    _require(
        len(slow_tests(result.output, Float64(SECONDS))) == 0, result.output
    )
    _require_empty(parent)
    print(
        "PASS temporary roots: direct run, errors, nested, borrowed, TMPDIR,"
        " concurrent"
    )


def _check_concurrent(
    binary: String, folder: String, parent: String, env: List[Setting]
) raises:
    """Two simultaneous direct processes write the same name under distinct
    roots."""
    var release = folder + "/release"
    var children = List[Background]()
    var start = perf_counter_ns()
    try:
        var markers: List[String] = [
            folder + "/concurrent-0.txt",
            folder + "/concurrent-1.txt",
        ]
        for index in range(len(markers)):
            children.append(
                Background(
                    binary,
                    _with(
                        env,
                        [
                            ("THREEMOJO_PORTABILITY_MARKER", markers[index]),
                            ("THREEMOJO_PORTABILITY_CONTENTS", String(index)),
                            ("THREEMOJO_PORTABILITY_RELEASE", release),
                        ],
                    ),
                    folder,
                )
            )
        while not (_nonempty(markers[0]) and _nonempty(markers[1])):
            var ended = False
            for ref child in children:
                if child.poll():
                    ended = True
            if _seconds_since(start) >= Float64(SECONDS) or ended:
                raise Error("Concurrent processes did not become ready")
            sleep(0.005)
        var roots: List[String] = [_marked(markers[0]), _marked(markers[1])]
        _require(roots[0] != roots[1], "Roots are equal: " + ", ".join(roots))
        for index in range(len(roots)):
            _require(
                parent_path(roots[index]) == parent
                and Path(roots[index] + "/same.bin").read_text()
                == String(index),
                "Unexpected root: " + roots[index],
            )
        Path(release).write_text("")
        for ref child in children:
            var remaining = Float64(SECONDS) - _seconds_since(start)
            var ended = child.communicate(max(0.001, remaining))
            _require(
                ended[0] == 0 and PASS_MARKER in ended[1],
                "Concurrent child failed: " + ended[1],
            )
        for path in roots:
            _require(not Path(path).exists(), "Root was not removed: " + path)
        _require_empty(parent)
    finally:
        for ref child in children:
            child.close()


def _check_cleanup_error(
    binary: String, folder: String, parent: String, env: List[Setting]
) raises:
    """The pinned stdlib refuses symlinks during cleanup. That error must not
    bypass environment restoration or touch the target. This process removes
    the deliberately retained test fixture afterward."""
    var external = folder + "/symlink-target"
    mkdir(external)
    Path(external + "/sentinel").write_text("keep")
    var bad_marker = folder + "/cleanup-root.txt"
    var bad_release = folder + "/cleanup-release"
    var child = Background(
        binary,
        _with(
            env,
            [
                ("THREEMOJO_PORTABILITY_MARKER", bad_marker),
                ("THREEMOJO_PORTABILITY_RELEASE", bad_release),
            ],
        ),
        folder,
    )
    var start = perf_counter_ns()
    try:
        while not _nonempty(bad_marker):
            if _seconds_since(start) >= Float64(SECONDS) or child.poll():
                raise Error("Cleanup-error process did not become ready")
            sleep(0.005)
        var root = _marked(bad_marker)
        var normal = normal_path(root)
        var name = String(normal[byte = normal.rfind("/") + 1 :])
        _require(
            parent_path(root) == parent and name.startswith("threemojo-test-"),
            "Unexpected root: " + root,
        )
        var linked = run_program(
            ["ln", "-s", external, root + "/external-link"], Float64(SECONDS)
        )
        _require(linked.status == 0, "Cannot make the link: " + linked.output)
        Path(bad_release).write_text("")
        var ended = child.communicate(
            max(0.001, Float64(SECONDS) - _seconds_since(start))
        )
        _require(
            ended[0] > 0
            and ended[0] <= 128
            and "can not be a symbolic link" in ended[1],
            "Unexpected cleanup result: " + ended[1],
        )
        _require(
            Path(external + "/sentinel").read_text() == "keep",
            "Link target was changed",
        )
        _remove_tree(root)
        _require_empty(parent)
    finally:
        child.close()


def build(mojo: String, root: String, source: String, output: String) raises:
    """Build a program with warnings as errors.

    Args:
        mojo: The compiler.
        root: The repository root, which is also the import root.
        source: The program's source.
        output: The program to write.

    Raises:
        Error: If the compiler fails or does not end in time.
    """
    var result = run_program(
        [mojo, "build", "--Werror", "-I", root, source, "-o", output],
        Float64(BUILD_SECONDS),
        directory=root,
    )
    print(result.output, end="")
    if result.status != 0 or result.timed_out:
        raise Error(
            "Command '"
            + mojo
            + " build "
            + source
            + "' returned non-zero exit status "
            + String(result.status)
            + "."
        )


def check(mojo_option: String) raises:
    """Build the probe and the scratch suite, then check both.

    Args:
        mojo_option: The `--mojo` value.

    Raises:
        Error: If a build or a case fails.
    """
    var root = realpath(".")
    # Absolute, because the last run uses the temporary folder as its cwd.
    var mojo = absolute_path(which(mojo_option))
    var assets = realpath(root + "/assets")
    var folder = realpath(mkdtemp(prefix="threemojo-portability-"))
    try:
        var binary = folder + "/probe"
        var suite = folder + "/scratch"
        build(mojo, root, root + "/tests/portability_probe.mojo", binary)
        build(mojo, root, root + "/tests/test_scratch.mojo", suite)
        check_assets(binary, folder, assets)
        check_scratch(binary, suite, mojo, folder)
    finally:
        _remove_tree(folder)


def main() raises:
    """Run the check, or print the help or a usage error.

    Raises:
        Error: If the command line cannot be read, or the check fails.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var command = parse_portability(arguments)
    if command.status == -1:
        print(command.message, end="")
        exit(0)
    if command.status != 0:
        print(command.message, end="", file=stderr)
        exit(command.status)
    check(command.value("--mojo", realpath(".") + "/.venv/bin/mojo"))
