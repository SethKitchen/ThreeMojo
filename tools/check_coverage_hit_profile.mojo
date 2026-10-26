# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check phase, argv and complete-vector contracts of compiled coverage.

Every native test keeps its five-second limit. Raw protocol checks remain in
`tools/check_coverage_protocol.mojo`. On Linux, the private profile also checks
the transport with `tools/coverage_hit_faults.mojo`.

    check_coverage_hit_profile --mojo .venv/bin/mojo

Run it from the repository root. `make test-coverage-tool` does.
"""

from std.collections import Dict
from std.os import listdir, remove, rmdir
from std.pathlib import Path
from std.subprocess import run
from std.sys import CompilationTarget, argv, exit, stderr
from std.tempfile import mkdtemp

from tools._cli import absolute_path
from tools._process import ProcessResult, run_program, shell_quote
from tools.run_suite import result_errors, slow_tests

comptime _PROBE = """from std.testing import TestSuite
from coverage.runtime import hit, begin, leaf, finish
from std.testing import assert_equal


struct PhaseValue(ImplicitlyCopyable):
    var value: Int

    def __init__(out self, compile_phase: Bool):
        hit(
            StaticString(
                \"compile:constructor\"
            ) if compile_phase else StaticString(\"runtime:constructor\")
        )
        var values = List[Int]()
        _ = begin(values, 2)
        _ = leaf(
            True,
            values,
            StaticString(
                \"compile:decision.0\"
            ) if compile_phase else StaticString(\"runtime:decision.0\"),
            0,
        )
        _ = leaf(
            False,
            values,
            StaticString(
                \"compile:decision.1\"
            ) if compile_phase else StaticString(\"runtime:decision.1\"),
            1,
        )
        _ = finish(
            False,
            values,
            StaticString(\"compile:decision\") if compile_phase else StaticString(
                \"runtime:decision\"
            ),
        )
        self.value = 7


comptime VALUE = PhaseValue(True)


def test_phase() raises:
    assert_equal(VALUE.value, 7)
    var runtime = PhaseValue(False)
    assert_equal(runtime.value, 7)
    print(\"phase done\")

from coverage.runtime import hit, branch, _emit, begin, leaf, finish
from std.testing import assert_equal

def test_vectors() raises:
    for _ in range(3):
        hit(\"cached:1\")
        assert_equal(branch(\"cached:2\", True), True)
        assert_equal(branch(\"cached:2\", False), False)
        _emit(String(\"COVLINE:diagnostic:1\\n\"))
        var values = List[Int]()
        _ = begin(values, 2)
        _ = leaf(True, values, \"cached:3.0\", 0)
        _ = leaf(False, values, \"cached:3.1\", 1)
        _ = finish(False, values, \"cached:3\")
    print(\"done\")

def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
"""
"""The probe suite. It matches the former Python checker."""

comptime _IDENTITY = """from std.sys import argv
from std.pathlib import cwd

def main() raises:
    for item in argv():
        print(String(item))
    print(cwd())
"""
"""The program that prints argv and the working directory."""


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


def _vectors(text: String) -> List[String]:
    """Return the `COVEVAL2` lines, in order."""
    var lines = List[String]()
    for line in text.splitlines():
        var row = String(line)
        if row.startswith("COVEVAL2:"):
            lines.append(row)
    return lines^


def _same_lines(lines: List[String], expected: List[String]) -> Bool:
    """Return whether two lists hold the same lines in the same order."""
    if len(lines) != len(expected):
        return False
    var index = 0
    while index < len(lines):
        if lines[index] != expected[index]:
            return False
        index += 1
    return True


def _line_set(text: String) -> List[String]:
    """Return the distinct lines of `text`, in first-seen order."""
    var lines = List[String]()
    for line in text.splitlines():
        var row = String(line)
        var seen = False
        for item in lines:
            if item == row:
                seen = True
                break
        if not seen:
            lines.append(row)
    return lines^


def _same_set(left: String, right: String) -> Bool:
    """Return whether two texts have the same set of lines."""
    var a = _line_set(left)
    var b = _line_set(right)
    if len(a) != len(b):
        return False
    for line in a:
        var found = False
        for other in b:
            if line == other:
                found = True
                break
        if not found:
            return False
    return True


def _key(profile: String, source: String) -> String:
    """Return the map key for one profile and one source."""
    return profile + "\n" + source


def validate_capture(
    stdout: String, stderr_text: String, cache_phase: String
) raises:
    """Refuse a capture whose tests, diagnostics or vectors changed.

    Args:
        stdout: The suite's standard output.
        stderr_text: The suite's standard error.
        cache_phase: `cold` or `warm`.

    Raises:
        Error: If the evidence does not match the pinned contract.
    """
    var errors = result_errors(stdout)
    if len(errors) > 0:
        raise Error("\n".join(errors))
    if len(slow_tests(stdout, 5.0)) > 0:
        raise Error(stdout)
    if stdout.find("2 tests run: 2 passed , 0 failed , 0 skipped") < 0:
        raise Error("native test inventory or status changed")
    if _count(stderr_text, "COVLINE:diagnostic:1\n") != 3:
        raise Error("ordinary diagnostic multiplicity changed")
    if _count(stderr_text, "COVEVAL2:runtime:decision:") != 1:
        raise Error("runtime constructor vector missing or duplicated")
    if _count(stderr_text, "COVEVAL2:cached:3:") != 3:
        raise Error("complete repeated vector missing or duplicated")
    var compile_vectors = _count(stderr_text, "COVEVAL2:compile:decision:")
    var expect_compile = 1 if cache_phase == "cold" else 0
    if compile_vectors != expect_compile:
        raise Error("compile-time vector/cache-scope mismatch")
    var expected = List[String]()
    if cache_phase == "cold":
        expected.append("COVEVAL2:compile:decision:F:TF;")
    expected.append("COVEVAL2:runtime:decision:F:TF;")
    var repeat = 0
    while repeat < 3:
        expected.append("COVEVAL2:cached:3:F:TF;")
        repeat += 1
    if not _same_lines(_vectors(stderr_text), expected):
        raise Error("independent complete-vector content or order changed")


def validate_streams(
    streams: Dict[String, String],
    profiles: List[String],
    identities: Dict[String, String],
    sources: List[String],
) raises:
    """Refuse a profile whose vectors, hits or argv differ from raw.

    Args:
        streams: Standard error for each profile and cache phase.
        profiles: The profiles after `raw`.
        identities: The argv text for each profile and source.
        sources: The absolute and relative source paths.

    Raises:
        Error: If a profile does not match the raw capture.
    """
    for cache_phase in ["cold", "warm"]:
        var raw = streams[_key("raw", cache_phase)]
        var vectors = _vectors(raw)
        for profile in profiles:
            var actual = streams[_key(profile, cache_phase)]
            if not _same_lines(_vectors(actual), vectors):
                raise Error("complete vector sequence changed")
            if not _same_set(actual, raw):
                raise Error("hit/evaluation evidence changed")
            if profile != "aot-hits" and actual != raw:
                raise Error("uncached record multiplicity changed")
    for source in sources:
        var raw_identity = identities[_key("raw", source)]
        for profile in profiles:
            if identities[_key(profile, source)] != raw_identity:
                raise Error(
                    "source argv0, arguments or working directory changed"
                )


def profile_command(
    mojo: String,
    work: String,
    suite: String,
    source: String,
    profile: String,
    arguments: List[String],
    cache_name: String,
    root: String,
) -> List[String]:
    """Return the adapter command for one profile.

    The adapter runs in `work`, so the script, the compiler and the include
    path are absolute. A relative compiler path is resolved by the caller.

    Args:
        mojo: The Mojo compiler, as an absolute path.
        work: The temporary directory.
        suite: The suite path passed to the adapter.
        source: The source path passed to `mojo run`.
        profile: `raw`, `aot` or `aot-hits`.
        arguments: Program arguments after the source.
        cache_name: The compiler-cache directory name.
        root: The repository root.

    Returns:
        The command, starting with `env`.
    """
    var command = List[String]()
    command.append("env")
    command.append("-u")
    command.append("LD_PRELOAD")
    command.append("-u")
    command.append("DYLD_INSERT_LIBRARIES")
    command.append("-u")
    command.append("THREEMOJO_COVERAGE_PIPE_DEVICE")
    command.append("-u")
    command.append("THREEMOJO_COVERAGE_PIPE_INODE")
    command.append("MODULAR_CACHE_DIR=" + work + "/compiler-" + cache_name)
    command.append("XDG_CACHE_HOME=" + work + "/xdg-" + cache_name)
    command.append(mojo)
    command.append("run")
    command.append("-I")
    command.append(root)
    command.append(root + "/tools/coverage_hit_aot.mojo")
    command.append("--repository")
    command.append(root)
    command.append("--profile")
    command.append(profile)
    command.append("--root")
    command.append(work)
    command.append("--suite")
    command.append(suite)
    command.append("--cache")
    command.append(work + "/native objects")
    command.append("--")
    command.append(mojo)
    command.append("run")
    command.append("--Werror")
    command.append("--num-threads")
    command.append("1")
    command.append("-I")
    command.append(root)
    command.append(source)
    for argument in arguments:
        command.append(argument)
    return command^


def _remove_flat(directory: String) raises:
    """Remove a temporary directory that holds only files."""
    for name in listdir(directory):
        remove(Path(directory) / name)
    rmdir(directory)


def capture_program(
    arguments: List[String],
    timeout: Float64,
    directory: String = "",
) raises -> ProcessResult:
    """Run a program whose standard error is a pipe.

    The private hit profile reads that descriptor and refuses a file.
    Python's `subprocess` capture gives it a pipe. The time limit matches
    `run_program`.

    Args:
        arguments: The program and its arguments. The first is found on
            `PATH` when it has no slash.
        timeout: The time limit in seconds.
        directory: The working directory, or empty for the current one.

    Returns:
        The exit status, the standard output, and the standard error.

    Raises:
        Error: If `arguments` is empty, the time limit is not positive, or
            the shell cannot start or report a status.
    """
    if len(arguments) == 0:
        raise Error("capture_program needs a program")
    if not timeout > 0:
        raise Error("capture_program needs a positive time limit")
    var scratch = mkdtemp(prefix="threemojo-capture-")
    try:
        var output = scratch + "/output"
        var command = String("exec")
        for argument in arguments:
            command += " " + shell_quote(argument)
        if directory.byte_length() > 0:
            command = "cd -- " + shell_quote(directory) + " && " + command
        var script = (
            "out="
            + shell_quote(output)
            + '\nmkfifo "$out.pipe"\n'
            + 'cat "$out.pipe" > "$out.err" &\n'
            + "reader=$!\n"
            + "( "
            + command
            + ' ) </dev/null >"$out" 2>"$out.pipe" &\n'
            + "pid=$!\n"
            + "( trap 'kill \"$s\" 2>/dev/null; exit 0' TERM\n"
            + "  sleep "
            + String(timeout)
            + " & s=$!\n"
            + '  wait "$s"\n'
            + "  trap '' TERM\n"
            + '  kill -KILL "$pid" 2>/dev/null && : >"$out.timeout"\n'
            + ") </dev/null >/dev/null 2>&1 &\n"
            + "w=$!\n"
            + 'wait "$pid" 2>/dev/null; rc=$?\n'
            + 'kill "$w" 2>/dev/null; wait "$w" 2>/dev/null\n'
            + 'wait "$reader"\n'
            + "printf '%d' \"$rc\"\n"
        )
        var reported = run("sh -c " + shell_quote(script))
        var status = Int(reported)
        var bytes = Path(output).read_bytes()
        var error_text = String(
            from_utf8_lossy=Path(output + ".err").read_bytes()
        )
        var timed_out = Path(output + ".timeout").exists()
        return ProcessResult(
            status, String(from_utf8_lossy=bytes), error_text^, timed_out
        )
    finally:
        _remove_flat(scratch)


def _invoke(
    mojo: String,
    work: String,
    suite: String,
    source: String,
    profile: String,
    arguments: List[String],
    cache_name: String,
) raises -> Tuple[String, String]:
    """Run one coverage profile and return its output and its errors.

    Args:
        mojo: The Mojo compiler.
        work: The temporary directory.
        suite: The suite path passed to the adapter.
        source: The source path passed to `mojo run`.
        profile: `raw`, `aot` or `aot-hits`.
        arguments: Program arguments after the source.
        cache_name: The compiler-cache directory name.

    Returns:
        The standard output and the standard error.

    Raises:
        Error: If the profile fails or exceeds its time limit.
    """
    var root = absolute_path(".")
    var command = profile_command(
        absolute_path(mojo),
        work,
        suite,
        source,
        profile,
        arguments,
        cache_name,
        root,
    )
    var result = capture_program(command, 180.0, directory=work)
    if result.timed_out or result.status != 0:
        raise Error(profile + ": " + result.output + "\n" + result.errors)
    return (result.output, result.errors)


def check(mojo: String) raises:
    """Run the cold and warm profile checks.

    Args:
        mojo: The Mojo compiler.

    Raises:
        Error: If a profile, an argv or a Linux fault check fails.
    """
    var profiles = List[String]()
    profiles.append("raw")
    profiles.append("aot")
    if CompilationTarget.is_linux():
        profiles.append("aot-hits")
    var work = mkdtemp(prefix="threemojo coverage profile ")
    var suite = work + "/probe.mojo"
    Path(suite).write_text(_PROBE)
    var identity = work + "/identity.mojo"
    Path(identity).write_text(_IDENTITY)
    var streams = Dict[String, String]()
    var identities = Dict[String, String]()
    var compared = List[String]()
    for profile in profiles:
        if profile != "raw":
            compared.append(profile)
        for cache_phase in ["cold", "warm"]:
            var capture = _invoke(
                mojo, work, suite, suite, profile, List[String](), profile
            )
            validate_capture(capture[0], capture[1], cache_phase)
            streams[_key(profile, cache_phase)] = capture[1]
        for source in [identity, "identity.mojo"]:
            var arguments = List[String]()
            arguments.append("argument with spaces")
            arguments.append("--literal")
            arguments.append(source)
            var printed = _invoke(
                mojo, work, identity, source, profile, arguments, profile
            )
            if printed[1].byte_length() > 0:
                raise Error(printed[1])
            identities[_key(profile, source)] = printed[0]
    var sources = List[String]()
    sources.append(identity)
    sources.append("identity.mojo")
    validate_streams(streams, compared, identities, sources)
    if CompilationTarget.is_linux():
        var tool = List[String]()
        tool.append("sh")
        tool.append("tools/tool.sh")
        tool.append(mojo)
        tool.append("--build")
        tool.append("coverage_hit_faults")
        var built = run_program(tool, 120.0)
        if built.status != 0:
            raise Error(built.output + built.errors)
        var faults = List[String]()
        faults.append("sh")
        faults.append("tools/tool.sh")
        faults.append(mojo)
        faults.append("coverage_hit_faults")
        faults.append("--compile-run")
        var ran = run_program(faults, 60.0)
        if ran.status != 0:
            raise Error(ran.output + ran.errors)
    print(
        "PASS: cold/warm phase records, every complete vector, ordinary"
        " diagnostics, absolute/relative source argv0, spaced paths/arguments"
        " and compiled profiles"
    )


def main() raises:
    """Check compiled coverage profiles from the command line."""
    var mojo = ".venv/bin/mojo"
    var given = argv()
    var index = 1
    while index < len(given):
        var word = String(given[index])
        if word == "--mojo":
            if index + 1 >= len(given):
                print(
                    "check_coverage_hit_profile: --mojo needs a value",
                    file=stderr,
                )
                exit(2)
            mojo = String(given[index + 1])
            index += 2
            continue
        print(
            "check_coverage_hit_profile: unknown argument " + word, file=stderr
        )
        exit(2)
    try:
        check(mojo)
    except error:
        print("check_coverage_hit_profile: " + String(error), file=stderr)
        exit(1)
