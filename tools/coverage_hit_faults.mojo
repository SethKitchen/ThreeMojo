# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check evidence sources without compiling; --compile-run is explicit opt-in.

    sh tools/tool.sh .venv/bin/mojo coverage_hit_faults [--compile-run]

The tool reads the probe transport `tools/coverage_hit_cache.c` and the
fault harness `tools/fixtures/coverage_hit_transport_faults.c`, checks
their text, and prints a JSON receipt. With `--compile-run`, it also builds
the harness with the C compiler and runs it for five seconds at most. The
receipt then holds the command, the outputs and the status, and the tool
exits with status 1 unless the harness passed. The tool works on the
repository in the current directory.
"""

from std.os import getenv, makedirs
from std.os.path import realpath
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._cli import absolute_path, normal_path, parse_command_line
from tools._json_tools import JsonWriter, quote_ascii
from tools._process import ProcessResult, run_program
from tools._sha256 import sha256_hex
from tools.compile_fail import shell_split

comptime COMPILE_SECONDS = 30.0
"""The time limit of the harness build, in seconds."""
comptime RUN_SECONDS = 5.0
"""The time limit of the harness run, in seconds."""
comptime PROGRAM = "coverage_hit_faults.mojo"
"""The program name in usage messages."""
comptime USAGE = (
    "usage: coverage_hit_faults.mojo [-h] [--source SOURCE] [--cc CC]\n"
    "                                [--compile-run] [--build-dir BUILD_DIR]\n"
    "                                [--receipt RECEIPT]\n"
)
"""The usage text, as `argparse` writes it."""
comptime HELP = (
    "\nCheck evidence sources without compiling; --compile-run is explicit"
    " opt-in.\n\noptions:\n  -h, --help            show this help message"
    " and exit\n  --source SOURCE\n  --cc CC\n  --compile-run\n  --build-dir"
    " BUILD_DIR\n  --receipt RECEIPT\n"
)
"""The help text after the usage."""
comptime HARNESS = "tools/fixtures/coverage_hit_transport_faults.c"
"""The fault harness, relative to the repository root."""
comptime SOURCE = "tools/coverage_hit_cache.c"
"""The default probe transport, relative to the repository root."""


trait Runner:
    """Something that runs a program, so that tests can stand in for it."""

    def run(
        mut self, arguments: List[String], timeout: Float64
    ) raises -> ProcessResult:
        """Run a program to its end.

        Args:
            arguments: The program and its arguments.
            timeout: The time limit in seconds.

        Returns:
            The status, negative for a signal as in Python, and the two
            output streams.

        Raises:
            Error: If the program does not finish in time.
        """
        ...


@fieldwise_init
struct ProcessRunner(Movable, Runner):
    """Run programs with `run_program`."""

    def run(
        mut self, arguments: List[String], timeout: Float64
    ) raises -> ProcessResult:
        """Run a program to its end.

        Args:
            arguments: The program and its arguments.
            timeout: The time limit in seconds.

        Returns:
            The status, negative for a signal as in Python, and the two
            output streams with universal newlines.

        Raises:
            Error: If the program does not finish in time.
        """
        var result = run_program(arguments, timeout, merge_errors=False)
        if result.timed_out:
            raise Error(
                "subprocess.TimeoutExpired: Command '"
                + _list_text(arguments)
                + "' timed out after "
                + String(Int(timeout))
                + " seconds"
            )
        var status = result.status
        if status > 128:
            status = 128 - status
        return ProcessResult(
            status, _newlines(result.output), _newlines(result.errors), False
        )


def _newlines(text: String) -> String:
    """Return text with CR LF and CR as LF, as Python's text mode reads it."""
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _list_text(words: List[String]) -> String:
    """Return a list of strings in Python's `repr` form, for messages."""
    var parts = List[String]()
    for word in words:
        parts.append("'" + word + "'")
    return "[" + ", ".join(parts) + "]"


def require(condition: Bool, message: String) raises:
    """Keep evidence checks active, as the Python tool's `require` did.

    Args:
        condition: The value that must be true.
        message: The failure text.

    Raises:
        Error: `RuntimeError` and the message, if `condition` is false.
    """
    if not condition:
        raise Error("RuntimeError: " + message)


def _index(text: String, part: String) raises -> Int:
    """Return where a string first starts, as `str.index` does."""
    var at = text.find(part)
    if at < 0:
        raise Error("ValueError: substring not found")
    return at


def preflight(text: String, harness: String) raises:
    """Check the transport and harness sources without compiling them.

    These are source preflight assertions, not execution of C semantics.

    Args:
        text: The transport source.
        harness: The harness source.

    Raises:
        Error: `RuntimeError` with the failed check, or `ValueError` when an
            ordered statement is missing.
    """
    require(
        text.find("if ((device || inode) && !enabled)\n        abort();") >= 0,
        (
            "qualification check failed: 'if ((device || inode) &&"
            " !enabled)\\n        abort();' in text"
        ),
    )
    require(
        _index(text, "write_record(probe_sink, bytes, size);")
        < _index(text, "memcpy(slot->bytes, bytes, size);"),
        (
            "qualification check failed: text.index('write_record(probe_sink,"
            " bytes, size);') < text.index('memcpy(slot->bytes, bytes, size);')"
        ),
    )
    require(
        text.find(
            "pthread_atfork(before_fork, after_parent_fork, child_after_fork)"
        )
        >= 0,
        (
            "qualification check failed: all fork transition hooks must be"
            " registered"
        ),
    )
    require(
        text.find("O_WRONLY | O_NONBLOCK | O_CLOEXEC") >= 0,
        (
            "qualification check failed: 'O_WRONLY | O_NONBLOCK | O_CLOEXEC' in"
            " text"
        ),
    )
    var copies = 0
    var at = text.find("memcpy(slot->bytes, bytes, size);")
    while at >= 0:
        copies += 1
        at = text.find("memcpy(slot->bytes, bytes, size);", at + 1)
    require(
        copies == 1,
        (
            "qualification check failed: text.count('memcpy(slot->bytes, bytes,"
            " size);') == 1"
        ),
    )
    require(
        harness.find("#include TRANSPORT_SOURCE") >= 0,
        (
            "qualification check failed: '#include TRANSPORT_SOURCE' in"
            " harness_bytes.decode()"
        ),
    )


struct Options(Movable):
    """What the command line asks for."""

    var source: String
    """The transport source, with an absolute path."""
    var harness: String
    """The fault harness, with an absolute path."""
    var cc: String
    """The C compiler command, split as a shell splits it."""
    var compile_run: Bool
    """True to build and run the harness."""
    var build_dir: Optional[String]
    """The folder for the build's temporary directory, or nothing."""

    def __init__(
        out self,
        source: String,
        harness: String,
        cc: String,
        compile_run: Bool,
        build_dir: Optional[String],
    ):
        """Make the options.

        Args:
            source: The transport source, with an absolute path.
            harness: The fault harness, with an absolute path.
            cc: The C compiler command.
            compile_run: True to build and run the harness.
            build_dir: The folder for the build's temporary directory.
        """
        self.source = source
        self.harness = harness
        self.cc = cc
        self.compile_run = compile_run
        self.build_dir = build_dir


struct Receipt(Movable):
    """The JSON receipt and whether the native harness passed."""

    var text: String
    """The receipt, as `json.dumps(result, indent=2)` and a newline."""
    var native_harness: String
    """`passed`, `failed`, `compile failed`, or `not compiled or run`."""

    def __init__(out self, var text: String, var native_harness: String):
        """Make a receipt.

        Args:
            text: The receipt text.
            native_harness: The harness outcome.
        """
        self.text = text^
        self.native_harness = native_harness^


def _strings(mut writer: JsonWriter, words: List[String]):
    """Write a list of strings."""
    writer.begin_array()
    for word in words:
        writer.string(word)
    writer.end()


def fault_receipt[R: Runner](options: Options, mut runner: R) raises -> Receipt:
    """Check the sources, build and run the harness when asked, and write
    the receipt.

    Parameters:
        R: The type of the runner.

    Args:
        options: What to check.
        runner: What runs the compiler and the harness.

    Returns:
        The receipt.

    Raises:
        Error: If a source cannot be read or fails its preflight, the
            compiler command is empty, a program is too slow, or the source
            changed while the tool ran.
    """
    var source_bytes = Path(options.source).read_bytes()
    var harness_bytes = Path(options.harness).read_bytes()
    var text = String(from_utf8=Span(source_bytes))
    preflight(text, String(from_utf8=Span(harness_bytes)))
    var native_harness = String("not compiled or run")
    var compiled = False
    var command = List[String]()
    var build = ProcessResult(0, String(), String(), False)
    var ran = False
    var result = ProcessResult(0, String(), String(), False)
    if options.compile_run:
        var compiler = shell_split(options.cc)
        if len(compiler) == 0:
            raise Error("ValueError: empty compiler command")
        var parent = Optional[String]()
        if options.build_dir:
            makedirs(options.build_dir.value(), exist_ok=True)
            var folder = options.build_dir.value()
            if not folder.startswith("/"):
                folder = realpath(".") + "/" + folder
            parent = normal_path(folder)
        var directory = mkdtemp(prefix="transport-review-", dir=parent)
        try:
            var executable = directory + "/transport-fault-harness"
            command = compiler.copy()
            command.extend(
                [
                    "-std=c11",
                    "-O2",
                    "-Wall",
                    "-Wextra",
                    "-Werror",
                    "-pthread",
                    "-DTRANSPORT_SOURCE=" + quote_ascii(options.source),
                    options.harness,
                    "-o",
                    executable,
                ]
            )
            build = runner.run(command, COMPILE_SECONDS)
            compiled = True
            if build.status == 0:
                result = runner.run([executable], RUN_SECONDS)
                ran = True
                native_harness = "passed" if result.status == 0 else "failed"
            else:
                native_harness = "compile failed"
        finally:
            _ = run_program(["rm", "-rf", directory], 60)
    var unchanged = Path(options.source).read_bytes() == source_bytes
    var writer = JsonWriter()
    writer.begin_object()
    writer.key("source")
    writer.string(options.source)
    writer.key("source_sha256")
    writer.string(sha256_hex(source_bytes))
    writer.key("harness_sha256")
    writer.string(sha256_hex(harness_bytes))
    writer.key("source_preflight")
    writer.string("passed")
    writer.key("native_harness")
    writer.string(native_harness)
    if compiled:
        writer.key("compile_command")
        _strings(writer, command)
        writer.key("compile_returncode")
        writer.integer(build.status)
        writer.key("compile_stdout")
        writer.string(build.output)
        writer.key("compile_stderr")
        writer.string(build.errors)
    if ran:
        writer.key("run_returncode")
        writer.integer(result.status)
        writer.key("run_stdout")
        writer.string(result.output)
        writer.key("run_stderr")
        writer.string(result.errors)
    writer.key("source_unchanged")
    writer.boolean(unchanged)
    writer.end()
    require(unchanged, "qualification check failed: result['source_unchanged']")
    return Receipt(writer.text() + "\n", native_harness)


def main() raises:
    """Run the check, or print the help or a usage error.

    Raises:
        Error: If the check fails.
    """
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    var command = parse_command_line(
        arguments,
        PROGRAM,
        USAGE,
        HELP,
        ["--compile-run"],
        ["--source", "--cc", "--build-dir", "--receipt"],
    )
    if command.status == -1:
        print(command.message, end="")
        exit(0)
    if command.status != 0:
        print(command.message, end="", file=stderr)
        exit(command.status)
    var root = realpath(".")
    var options = Options(
        absolute_path(command.value("--source", root + "/" + SOURCE)),
        root + "/" + HARNESS,
        command.value("--cc", getenv("CC", "cc")),
        "--compile-run" in command.flags,
        command.values.get("--build-dir"),
    )
    var runner = ProcessRunner()
    var receipt = fault_receipt(options, runner)
    if "--receipt" in command.values:
        Path(command.values["--receipt"]).write_bytes(receipt.text.as_bytes())
    print(receipt.text, end="")
    if options.compile_run and receipt.native_harness != "passed":
        exit(1)
