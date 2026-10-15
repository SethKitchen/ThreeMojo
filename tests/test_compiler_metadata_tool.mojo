# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Metadata-only and fake-command checks for `tools/compiler_metadata`.

No compiler work runs: the commands are small shell programs. Two tests run
the built tool through `tools/tool.sh`, as the CI workflow does.
"""

from std.os import setenv, unsetenv
from std.pathlib import Path
from std.sys import CompilationTarget
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_true,
)

from tests._tree import tool_mojo
from tools._owned_process import monotonic_seconds, nap
from tools._process import run_program, shell_quote
from tools._python_json import PyJson, dumps_canonical
from tools._sha256 import sha256_hex
from tools.compiler_metadata import (
    BUILD_ARGS,
    Budget,
    CommandResult,
    DEADLINE,
    MAX_OUTPUT,
    MetadataSource,
    collect,
    file_identity,
    find_driver,
    parse_options,
    read_command,
    record_text,
)

comptime TARGET = (
    "Effective target configuration:\n"
    "  --target-triple x86_64-unknown-linux-gnu\n"
    "  --target-cpu x86-64-v3\n"
    "  --target-features +avx,+avx2,+fma\n"
)


struct FakeSource(MetadataSource, Movable):
    """Commands with fixed output, and a fixed or failing driver."""

    var version: String
    """The output of `--version`."""
    var target: String
    """The output of the target command."""
    var status: String
    """The status of each command."""
    var driver_path: String
    """The driver, or empty to fail with `driver_error`."""
    var driver_error: String
    """The error that finding the driver raises."""
    var run_error: String
    """An error that every command raises, or empty."""
    var commands: List[List[String]]
    """Each command run."""
    var limits: Budget
    """The budget."""
    var real_driver: Bool
    """True to find the driver as the tool does."""

    def __init__(out self):
        """Make a source that prints a version and a target."""
        self.version = "Mojo 1.1.0 (8189361e)\n"
        self.target = TARGET
        self.status = "ok"
        self.driver_path = String()
        self.driver_error = "RuntimeError: no driver"
        self.run_error = String()
        self.commands = List[List[String]]()
        self.limits = Budget()
        self.real_driver = False

    def run(mut self, command: List[String]) raises -> CommandResult:
        """Return the fixed output."""
        self.commands.append(command.copy())
        if self.run_error.byte_length() > 0:
            raise Error(self.run_error)
        if "--version" in command:
            return CommandResult(self.version, self.status)
        return CommandResult(self.target, self.status)

    def driver(mut self, compiler: String) raises -> String:
        """Return the fixed driver, or fail."""
        if self.real_driver:
            return find_driver(compiler)
        if self.driver_path.byte_length() == 0:
            raise Error(self.driver_error)
        return self.driver_path

    def budget(self) -> Budget:
        """Return the budget."""
        return self.limits.copy()


def _text(doc: PyJson, node: Int, key: String) -> String:
    """Return a member's text."""
    return doc.text(doc.get(node, key))


def test_selected_identity_target_and_no_compilation_command() raises:
    var root = mkdtemp(prefix="metadata ")
    Path(root + "/launcher").write_text("python launcher")
    Path(root + "/driver").write_text("native driver")
    var source = FakeSource()
    source.driver_path = root + "/driver"
    var doc = collect(root + "/launcher", source)
    var driver = doc.get(doc.root, "driver")
    var launcher = doc.get(doc.root, "launcher")
    assert_equal(
        _text(doc, driver, "sha256"), sha256_hex("native driver".as_bytes())
    )
    assert_true(_text(doc, driver, "sha256") != _text(doc, launcher, "sha256"))
    assert_equal(_text(doc, doc.root, "version"), "Mojo 1.1.0 (8189361e)")
    var target = doc.get(doc.root, "effective_target")
    assert_equal(_text(doc, target, "target-features"), "+avx,+avx2,+fma")
    var expected: List[String] = [
        root + "/launcher",
        "build",
        "--print-effective-target",
    ]
    for word in materialize[BUILD_ARGS]():
        expected.append(word)
    assert_equal(source.commands[1], expected)
    var flags: List[String] = [
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
    var actual = List[String]()
    for word in materialize[BUILD_ARGS]():
        actual.append(word)
    assert_equal(actual, flags)
    _ = run_program(["rm", "-rf", root], 10)


def test_unrecognized_output_and_environment_values_are_not_logged() raises:
    var token = "DO_NOT_LOG_PRIVATE_ENV_VALUE"
    _ = setenv("PRIVATE_TEST_VALUE", token, True)
    var source = FakeSource()
    source.version = token
    source.target = token
    source.driver_error = token
    var doc = collect("absent", source)
    _ = unsetenv("PRIVATE_TEST_VALUE")
    var output = dumps_canonical(doc, doc.root)
    assert_false(token in output)
    assert_equal(_text(doc, doc.root, "version_status"), "unrecognized-output")
    assert_equal(_text(doc, doc.root, "target_status"), "unrecognized-output")
    assert_equal(
        _text(doc, doc.get(doc.root, "driver"), "status"), "unavailable"
    )


def test_metadata_failure_does_not_replace_the_following_failure_gate() raises:
    var source = FakeSource()
    source.run_error = "private diagnostic"
    var line = record_text("absent", source)
    assert_equal(line, '{"compiler_metadata":1,"status":"unavailable"}')
    # The metadata-only command does not wrap or mask a later CPU command.
    var script = (
        "sh tools/tool.sh "
        + shell_quote(tool_mojo())
        + " compiler_metadata --compiler missing; exit 7"
    )
    var result = run_program(["sh", "-ec", script], 30)
    assert_equal(result.status, 7)


def test_whole_collector_deadline_covers_hashing_and_driver_resolution() raises:
    var root = mkdtemp(prefix="metadata ")
    Path(root + "/launcher").write_text(String("x") * 100000)
    var expired = Budget(0)
    var raised = String()
    try:
        _ = file_identity(root + "/launcher", expired)
    except error:
        raised = String(error)
    assert_equal(raised, DEADLINE)
    var source = FakeSource()
    source.limits = Budget(0.03)
    source.driver_error = DEADLINE
    var started = monotonic_seconds()
    var line = record_text(root + "/missing", source)
    assert_true(monotonic_seconds() - started < 2)
    assert_equal(line, '{"compiler_metadata":1,"status":"unavailable"}')
    _ = run_program(["rm", "-rf", root], 10)


def test_other_launcher_cannot_be_labeled_with_a_driver() raises:
    var root = mkdtemp(prefix="metadata ")
    Path(root + "/mojo").write_text("launcher")
    var raised = False
    try:
        _ = find_driver(root + "/mojo")
    except:
        raised = True
    assert_true(raised)
    var source = FakeSource()
    source.real_driver = True
    source.status = "unavailable"
    var doc = collect(root + "/mojo", source)
    assert_equal(
        _text(doc, doc.get(doc.root, "driver"), "status"), "unavailable"
    )
    _ = run_program(["rm", "-rf", root], 10)


def test_a_wheel_launcher_names_its_own_driver() raises:
    var root = mkdtemp(prefix="metadata ")
    var site = root + "/lib/python3.12/site-packages"
    _ = run_program(
        ["mkdir", "-p", root + "/bin", site + "/mojo", site + "/modular/bin"],
        10,
    )
    Path(root + "/bin/mojo").write_text("launcher")
    Path(root + "/bin/python").write_text("interpreter")
    Path(site + "/mojo/run.py").write_text("")
    Path(site + "/modular/bin/mojo").write_text("driver")
    assert_equal(find_driver(root + "/bin/mojo"), site + "/modular/bin/mojo")
    _ = setenv("MODULAR_MOJO_MAX_DRIVER_PATH", "/chosen/driver", True)
    var chosen = find_driver(root + "/bin/mojo")
    _ = unsetenv("MODULAR_MOJO_MAX_DRIVER_PATH")
    assert_equal(chosen, "/chosen/driver")
    var raised = False
    try:
        _ = find_driver(root + "/bin/python")
    except:
        raised = True
    assert_true(raised)
    _ = run_program(["rm", "-rf", root], 10)


def test_missing_metadata_command_is_unavailable() raises:
    var result = read_command(
        ["/nonexistent/compiler-metadata-command"], Budget()
    )
    assert_false(result.text)
    assert_equal(result.status, "unavailable")


def test_stderr_is_never_captured_or_emitted() raises:
    var result = read_command(
        ["sh", "-c", "echo safe; echo secret 1>&2"], Budget()
    )
    assert_equal(result.text.value(), "safe\n")
    assert_equal(result.status, "ok")
    var failed = read_command(["sh", "-c", "echo out; exit 3"], Budget())
    assert_false(failed.text)
    assert_equal(failed.status, "failed")


def test_output_and_elapsed_time_have_small_bounds() raises:
    var result = read_command(
        ["sh", "-c", "head -c 50000 /dev/zero"], Budget(), limit=64
    )
    assert_false(result.text)
    assert_equal(result.status, "output-limit")
    var started = monotonic_seconds()
    result = read_command(["sh", "-c", "sleep 5"], Budget(), timeout=0.05)
    assert_false(result.text)
    assert_equal(result.status, "timeout")
    assert_true(monotonic_seconds() - started < 2)


def _running(pid: String, start: String) -> Bool:
    """Return whether a process with this start time runs and is no zombie."""
    try:
        var text = Path("/proc/" + pid + "/stat").read_text()
        var fields = String(text[byte = text.rfind(")") + 1 :]).split()
        return String(fields[19]) == start and String(fields[0]) != "Z"
    except:
        return False


def test_timeout_cleans_owned_descendant_that_holds_the_output_pipe() raises:
    comptime if not CompilationTarget.is_linux():
        return
    var root = mkdtemp(prefix="metadata ")
    var receipt = root + "/child"
    # The leader exits at once; its child keeps the pipe open and sleeps.
    var worker = (
        'sh -c \'echo $$ > "$1.tmp"; mv "$1.tmp" "$1"; exec sleep 5\''
        + " _ "
        + shell_quote(receipt)
        + " &\nwhile [ ! -f "
        + shell_quote(receipt)
        + " ]; do sleep 0.01; done\nexit 0\n"
    )
    var started = monotonic_seconds()
    var result = read_command(["sh", "-c", worker], Budget(), timeout=0.5)
    assert_equal(result.status, "timeout")
    assert_true(monotonic_seconds() - started < 2)
    var pid = String(Path(receipt).read_text().strip())
    var start = String()
    try:
        var text = Path("/proc/" + pid + "/stat").read_text()
        start = String(String(text[byte = text.rfind(")") + 1 :]).split()[19])
    except:
        pass
    var deadline = monotonic_seconds() + 1
    while _running(pid, start) and monotonic_seconds() < deadline:
        nap(0.01)
    assert_false(_running(pid, start))
    _ = run_program(["rm", "-rf", root], 10)


def test_binary_and_record_sizes_are_bounded() raises:
    var root = mkdtemp(prefix="metadata ")
    Path(root + "/twenty").write_text(String("x") * 20)
    assert_equal(
        file_identity(root + "/twenty", Budget(), max_binary=10).status,
        "unavailable",
    )
    var exact = file_identity(root + "/twenty", Budget())
    assert_equal(exact.status, "ok")
    assert_equal(exact.bytes, 20)
    _ = run_program(["rm", "-rf", root], 10)
    var source = FakeSource()
    var line = record_text("/" + String("c") * MAX_OUTPUT, source)
    assert_equal(line, '{"compiler_metadata":1,"status":"record-limit"}')


def test_targets_with_paths_duplicates_or_extra_text_are_not_logged() raises:
    for extra in [
        "  --target-cpu secret\n",
        "environment SECRET=private\n",
        "  --target-features /private/path\n",
    ]:
        var source = FakeSource()
        source.target = TARGET + extra
        var doc = collect("absent", source)
        assert_false(doc.find(doc.root, "effective_target") >= 0)
        assert_equal(
            _text(doc, doc.root, "target_status"), "unrecognized-output"
        )
    var blank = FakeSource()
    blank.target = TARGET + "  \t\n  --target-abi lp64\n"
    var doc = collect("absent", blank)
    var target = doc.get(doc.root, "effective_target")
    assert_equal(_text(doc, target, "target-abi"), "lp64")


def test_cancellation_stops_the_command_group_and_prints_nothing() raises:
    var root = mkdtemp(prefix="metadata ")
    var compiler = root + "/bin/mojo"
    _ = run_program(["mkdir", "-p", root + "/bin"], 10)
    Path(compiler).write_text(
        '#!/bin/sh\necho $$ > "$(dirname "$0")/started"\nexec sleep 5\n'
    )
    _ = run_program(["chmod", "+x", compiler], 10)
    var q = shell_quote(root)
    var script = (
        "sh tools/tool.sh "
        + shell_quote(tool_mojo())
        + " compiler_metadata --compiler "
        + shell_quote(compiler)
        + " > "
        + q
        + "/out & t=$!\n"
        + "n=0; while [ ! -f "
        + q
        + "/bin/started ] && [ $n -lt 500 ]; do sleep 0.01; n=$((n+1)); done\n"
        + "kill -TERM $t; wait $t; echo $?\n"
    )
    # The shell may report the stopped job on its standard error, as the
    # shell of macOS does, so only the standard output is compared.
    var result = run_program(["sh", "-c", script], 30, merge_errors=False)
    assert_equal(result.output, "143\n")
    assert_equal(Path(root + "/out").read_text(), "")
    comptime if CompilationTarget.is_linux():
        var pid = String(Path(root + "/bin/started").read_text().strip())
        var gone = True
        try:
            var text = Path("/proc/" + pid + "/stat").read_text()
            gone = (
                String(String(text[byte = text.rfind(")") + 1 :]).split()[0])
                == "Z"
            )
        except:
            pass
        assert_true(gone)
    _ = run_program(["rm", "-rf", root], 10)


def test_options_follow_argparse() raises:
    var options = parse_options([])
    assert_equal(options.compiler, ".venv/bin/mojo")
    options = parse_options(["--c=x", "--compiler", "-1"])
    assert_equal(options.compiler, "-1")
    options = parse_options(["--compiler", "x", "y", "--z"])
    assert_equal(
        options.message,
        (
            "usage: compiler_metadata.mojo [-h] [--compiler COMPILER]\n"
            "compiler_metadata.mojo: error: unrecognized arguments: y --z\n"
        ),
    )
    options = parse_options(["x", "--compiler"])
    assert_true("argument --compiler: expected one argument" in options.message)
    options = parse_options(["--", "--compiler", "x"])
    assert_true("unrecognized arguments: -- --compiler x\n" in options.message)
    options = parse_options(["-h", "x"])
    assert_equal(options.status, 0)
    assert_true(options.message.endswith("  --compiler COMPILER\n"))


def main() raises:
    # Build the tool once before the tests, so that no test pays for it.
    var built = run_program(
        ["sh", "tools/tool.sh", tool_mojo(), "--build", "compiler_metadata"],
        300,
    )
    if built.status != 0:
        raise Error("cannot build compiler_metadata: " + built.output)
    TestSuite.discover_tests[__functions_in_module()]().run()
