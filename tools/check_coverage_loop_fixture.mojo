# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Qualify coverage loop fixtures with the Mojo coverage tools.

    check_coverage_loop_fixture [--mojo PATH]

The program checks the constant loops, a shadowed `range`, physical line
endings, the production capture, and generated-stage mutations. The
profiled owner controls stay in `tools/check_coverage_loop_proofs.py`.
"""

from std.os import setenv, stat
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._process import run_program
from tools._python_json import PyJson
from tools._sha256 import sha256_hex
from tools.coverage_io import Reducer, _expected_command, _now


comptime _SOURCE = """from std.testing import assert_equal
from std.sys import argv

def fixed(leave: Int) raises -> Int:
    var total = 0
    for index in range(3):
        if leave == 1:
            break
        if leave == 2:
            return total
        if leave == 3:
            raise Error(\"expected body\")
        if index == 0:
            continue
        total += index
    else:
        total += 10
    return total

def empty() -> Int:
    for index in range(0):
        return index
    else:
        return 7

def mark(value: Int, mut order: String) -> Int:
    order += String(value)
    return value

def literal() raises -> Int:
    var total = 0
    var order = String(\"\")
    for value in [mark(1, order), mark(2, order), mark(3, order)]:
        assert_equal(order, \"123\")
        total += value
    return total

def dynamic(n: Int) -> Int:
    var total = 0
    for index in range(n):
        total += index
    return total

def main() raises:
    var mode = Int(String(argv()[1]))
    assert_equal(fixed(0), 13)
    assert_equal(fixed(1), 0)
    assert_equal(fixed(2), 0)
    var caught = False
    try:
        _ = fixed(3)
    except error:
        caught = String(error) == \"expected body\"
    assert_equal(caught, True)
    assert_equal(empty(), 7)
    assert_equal(literal(), 6)
    assert_equal(dynamic(2), 1)
    if mode == 0:
        assert_equal(dynamic(0), 0)
    print(\"RESULT constant loops\")
"""


def diagnostic_manifest(
    masked: String, module: String, lines: List[Int]
) raises -> String:
    """Keep the manifest rows for one module's loop lines.

    Args:
        masked: The masked manifest, one record per line.
        module: The fixture module name.
        lines: The loop lines that must appear.

    Returns:
        The selected rows, ending with a newline.

    Raises:
        Error: A requested loop line is missing.
    """
    var rows = String("")
    var seen = List[Int]()
    var start = 0
    var raw = masked
    var count = raw.byte_length()
    var bytes = raw.as_bytes()
    while start < count:
        var end = start
        while end < count and bytes[end] != 10:
            end += 1
        var row = String(raw[byte=start:end])
        if row.byte_length() > 0:
            var fields = row.split(" ")
            if len(fields) > 0 and String(fields[0]) == "P":
                rows += row + "\n"
            elif (
                len(fields) >= 3
                and (String(fields[0]) == "B" or String(fields[0]) == "R")
                and String(fields[1]) == module
                and _listed(lines, Int(String(fields[2])))
            ):
                rows += row + "\n"
                seen.append(Int(String(fields[2])))
        start = end + 1
    for line in lines:
        if not _listed(seen, line):
            raise Error("Diagnostic loop identity is missing")
    return rows


def _listed(lines: List[Int], line: Int) -> Bool:
    """Return whether `lines` contains `line`."""
    for item in lines:
        if item == line:
            return True
    return False


def _fail(message: String) raises:
    """Raise a fixture qualification error.

    Args:
        message: The failure text.

    Raises:
        Error: The qualification failed.
    """
    raise Error(message)


def _run(
    arguments: List[String], timeout: Float64, directory: String
) raises -> String:
    """Run a command and return its output.

    Args:
        arguments: The program and its arguments.
        timeout: The time limit in seconds.
        directory: The working directory, or empty.

    Returns:
        The standard output and standard error.

    Raises:
        Error: The command fails or exceeds `timeout`.
    """
    var result = run_program(arguments, timeout, True, directory)
    if result.status != 0:
        _fail(result.output)
    return result.output


def _run_both(
    arguments: List[String], timeout: Float64, directory: String
) raises -> Tuple[Int, String, String]:
    """Run a command and keep its output and errors apart.

    Args:
        arguments: The program and its arguments.
        timeout: The time limit in seconds.
        directory: The working directory, or empty.

    Returns:
        The status, the standard output, and the standard error.

    Raises:
        Error: The command exceeds `timeout`.
    """
    var result = run_program(arguments, timeout, False, directory)
    return (result.status, result.output, result.errors)


def _line(source: String, fragment: String) raises -> Int:
    """Return the one line that contains `fragment`.

    Args:
        source: The fixture source.
        fragment: The text that identifies the loop.

    Returns:
        The line number, starting at 1.

    Raises:
        Error: The fragment is missing or repeated.
    """
    var number = 0
    var found = 0
    var start = 0
    var count = source.byte_length()
    var bytes = source.as_bytes()
    while start <= count:
        var end = start
        while end < count and bytes[end] != 10:
            end += 1
        number += 1
        var row = String(source[byte=start:end])
        if row.find(fragment) >= 0:
            if found != 0:
                _fail("Fixture identity is not unique: " + fragment)
            found = number
        if end >= count:
            break
        start = end + 1
    if found == 0:
        _fail("Fixture identity is not unique: " + fragment)
    return found


def _copy(source: String, destination: String) raises:
    """Copy one file, creating its parent directory."""
    var slash = destination.rfind("/")
    if slash > 0:
        _ = _run(["mkdir", "-p", String(destination[byte=:slash])], 10.0, "")
    _ = _run(["cp", "-a", source, destination], 30.0, "")


def _tool(mojo: String, name: String) -> List[String]:
    """Return the `tool.sh` command for `name`."""
    var command = List[String]()
    command.append("sh")
    command.append("tools/tool.sh")
    command.append(mojo)
    command.append(name)
    return command^


def qualify_constant_loops(mojo: String) raises:
    """Instrument the constant-loop fixture and reject a false entry probe.

    Args:
        mojo: The Mojo compiler used to build and run the fixture.

    Raises:
        Error: A loop outcome, report, or mutation check fails.
    """
    var version = _run([mojo, "--version"], 30.0, "")
    var compiler = String(version.strip())
    var flags = "-Werror -I ."
    var work = mkdtemp(prefix="loop fixture ")
    var native = work + "/native"
    var rewritten = work + "/rewritten"
    _ = _run(["mkdir", "-p", native, rewritten], 10.0, "")
    var inputs = List[String]()
    inputs.append("coverage/build_cli.mojo")
    inputs.append("coverage/instrument.mojo")
    inputs.append("coverage/scanner.mojo")
    inputs.append("coverage/runtime.mojo")
    inputs.append("coverage/report.mojo")
    inputs.append("coverage/report_cli.mojo")
    inputs.append("coverage/mcdc.mojo")
    inputs.append("tools/coverage_loop_proofs.py")
    inputs.append("tools/coverage_io.py")
    inputs.append("tools/cache_key.py")
    inputs.append("tools/native_test_support.py")
    inputs.append("tools/coverage_toolchain_identity.py")
    inputs.append("tools/coverage_hit_aot.mojo")
    inputs.append("tools/coverage_hit_cache.c")
    inputs.append("tools/coverage_write_interposer.c")
    inputs.append("tools/run_suite.mojo")
    inputs.append("Makefile")
    for name in inputs:
        _copy(name, native + "/" + name)
    _ = _run(["cp", "-a", "coverage/.", native + "/coverage/"], 30.0, "")
    _ = _run(["rm", "-rf", native + "/coverage/build"], 10.0, "")
    _ = _run(["mkdir", "-p", rewritten + "/coverage"], 10.0, "")
    _ = _run(["cp", "-a", "coverage/.", rewritten + "/coverage/"], 30.0, "")
    _ = _run(["rm", "-rf", rewritten + "/coverage/build"], 10.0, "")
    _ = _run(["cp", "-a", "tools/.", native + "/tools/"], 60.0, "")
    _ = _run(["rm", "-rf", native + "/tools/__pycache__"], 10.0, "")
    for name in ["core/__init__.mojo", "core/search.mojo", "core/binary.mojo"]:
        _copy(name, native + "/" + name)
    Path(native + "/fixture.mojo").write_text(_SOURCE)
    var reporter = work + "/report"
    var build_report = List[String]()
    build_report.append(mojo)
    build_report.append("build")
    build_report.append("-Werror")
    build_report.append("-I")
    build_report.append(".")
    build_report.append("coverage/report_cli.mojo")
    build_report.append("-o")
    build_report.append(reporter)
    _ = _run(build_report, 180.0, native)
    var begin = _tool(mojo, "coverage_loop_begin")
    begin.append("--root")
    begin.append(native)
    begin.append("--build")
    begin.append(rewritten)
    begin.append("--compiler")
    begin.append(compiler)
    begin.append("--flags")
    begin.append(flags)
    begin.append("--mojo")
    begin.append(mojo)
    begin.append("--sources")
    begin.append("fixture.mojo")
    _ = _run(begin, 180.0, "")
    var generate = List[String]()
    generate.append(mojo)
    generate.append("run")
    generate.append("-Werror")
    generate.append("-I")
    generate.append(".")
    generate.append("coverage/build_cli.mojo")
    generate.append(rewritten)
    generate.append("fixture.mojo")
    _ = _run(generate, 180.0, native)
    var fixed = _line(_SOURCE, "for index in range(3)")
    var empty = _line(_SOURCE, "for index in range(0)")
    var literal = _line(_SOURCE, "for value in [mark(1, order)")
    var dynamic = _line(_SOURCE, "for index in range(n)")
    var manifest = Path(rewritten + "/manifest.txt").read_text()
    var decision_lines = List[Int]()
    decision_lines.append(fixed)
    decision_lines.append(empty)
    decision_lines.append(literal)
    decision_lines.append(dynamic)
    for line in decision_lines:
        if manifest.find("B fixture " + String(line) + "\n") < 0:
            _fail("Missing original fixture decision")
    var seal = _tool(mojo, "coverage_loop_seal")
    seal.append("--root")
    seal.append(native)
    seal.append("--build")
    seal.append(rewritten)
    seal.append("--compiler")
    seal.append(compiler)
    seal.append("--flags")
    seal.append(flags)
    seal.append("--mojo")
    seal.append(mojo)
    _ = _run(seal, 180.0, "")
    var receipt = PyJson.parse(
        Path(rewritten + "/loop-proofs.json").read_text()
    )
    var proofs = receipt.at(receipt.at(receipt.root, "receipt"), "proofs")
    if receipt.length(proofs) != 3:
        _fail("Expected exactly three constant loops")
    var denominator = receipt.at(
        receipt.at(receipt.root, "receipt"), "denominator"
    )
    var potential = Int(
        receipt.text(receipt.at(denominator, "potential_total"))
    )
    var required = Int(receipt.text(receipt.at(denominator, "required_total")))
    if potential - required != 3:
        _fail("Reachable outcome removed")
    var masked_path = rewritten + "/mojo-masked-manifest.txt"
    var mask = _tool(mojo, "coverage_loop_seal")
    mask.append("mask")
    mask.append("--build")
    mask.append(rewritten)
    mask.append("--output")
    mask.append(masked_path)
    _ = _run(mask, 60.0, "")
    var lines = List[Int]()
    lines.append(fixed)
    lines.append(empty)
    lines.append(literal)
    lines.append(dynamic)
    var derived = diagnostic_manifest(
        Path(masked_path).read_text(), "fixture", lines
    )
    var derived_path = work + "/derived-manifest.txt"
    Path(derived_path).write_text(derived)
    var plain_bin = native + "/fixture"
    var inst_bin = rewritten + "/fixture"
    var plain_build = List[String]()
    plain_build.append(mojo)
    plain_build.append("build")
    plain_build.append("-Werror")
    plain_build.append("-I")
    plain_build.append(native)
    plain_build.append(native + "/fixture.mojo")
    plain_build.append("-o")
    plain_build.append(plain_bin)
    _ = _run(plain_build, 180.0, "")
    var inst_build = List[String]()
    inst_build.append(mojo)
    inst_build.append("build")
    inst_build.append("-Werror")
    inst_build.append("-I")
    inst_build.append(rewritten)
    inst_build.append(rewritten + "/fixture.mojo")
    inst_build.append("-o")
    inst_build.append(inst_bin)
    _ = _run(inst_build, 180.0, "")
    for mode in [0, 1]:
        var plain = _run_both([plain_bin, String(mode)], 5.0, "")
        var instrumented = _run_both([inst_bin, String(mode)], 5.0, "")
        if plain[0] != 0 or instrumented[0] != 0:
            _fail("Native program failed")
        if (
            plain[1] != "RESULT constant loops\n"
            or instrumented[1] != "RESULT constant loops\n"
        ):
            _fail("Native output changed")
        if plain[2].byte_length() != 0:
            _fail("Native program unexpectedly emitted probe records")
        var outcomes = _outcomes(instrumented[2])
        if _joined(outcomes, fixed) != "TTTTTTT":
            _fail("Loop protocol changed: fixed")
        if _joined(outcomes, empty) != "F":
            _fail("Loop protocol changed: empty")
        if _joined(outcomes, literal) != "TTTT":
            _fail("Loop protocol changed: literal")
        var dynamic_text = "TTT"
        if mode == 0:
            dynamic_text = "TTTF"
        if _joined(outcomes, dynamic) != dynamic_text:
            _fail("Loop protocol changed: dynamic")
        var case_dir = work + "/case-" + String(mode)
        _ = _run(["mkdir", "-p", case_dir], 10.0, "")
        var raw_path = case_dir + "/result.raw.txt"
        Path(raw_path).write_text(instrumented[2])
        var reduced = _reduce(instrumented[2])
        var reduced_text = case_dir + "/result.txt"
        Path(reduced_text).write_text(reduced)
        _ = _run(["gzip", "-n", "-f", reduced_text], 10.0, "")
        var report = _run_both([reporter, derived_path, raw_path], 5.0, "")
        var passed = report[0] == 0
        if passed != (mode == 0):
            _fail("Missing dynamic-empty obligation was lost")
        if mode == 0:
            if report[1].find("TOTAL") < 0 or report[1].find("5/5") < 0:
                _fail("Positive report is incomplete")
            if (
                report[1].find(
                    "DENOMINATOR potential 8, required 5, proven impossible 3"
                )
                < 0
            ):
                _fail("Denominator lineage missing")
        elif (
            report[1].find("never evaluated False") < 0
            and report[2].find("never evaluated False") < 0
        ):
            _fail("Dynamic-empty failure not explained")
        var replay = _tool(mojo, "coverage_io")
        replay.append("report")
        replay.append("--capture-dir")
        replay.append(case_dir)
        replay.append("--")
        replay.append(reporter)
        replay.append(derived_path)
        var replayed = _run_both(replay, 30.0, "")
        if (replayed[0] == 0) != (mode == 0):
            _fail(
                "Diagnostic raw/reduced reporting changed the result: "
                + replayed[1]
                + replayed[2]
            )
    var source_path = rewritten + "/fixture.mojo"
    var original = Path(source_path).read_text()
    var needle = '_cov_branch("fixture:' + String(fixed) + '", True)'
    if original.find(needle) < 0:
        _fail("Mutation target absent")
    var mutated = original.replace(needle, needle.replace("True", "False"))
    Path(source_path).write_text(mutated)
    var rejected = _tool(mojo, "coverage_loop_seal")
    rejected.append("--root")
    rejected.append(native)
    rejected.append("--build")
    rejected.append(rewritten)
    rejected.append("--compiler")
    rejected.append(compiler)
    rejected.append("--flags")
    rejected.append(flags)
    rejected.append("--mojo")
    rejected.append(mojo)
    var refusal = _run_both(rejected, 180.0, "")
    var refusal_text = refusal[1] + refusal[2]
    if refusal[0] == 0 or refusal_text.find("generation origin") < 0:
        _fail("Unexpected mutation rejection: " + refusal_text)
    var mutant = rewritten + "/mutant"
    var mutant_build = List[String]()
    mutant_build.append(mojo)
    mutant_build.append("build")
    mutant_build.append("-Werror")
    mutant_build.append("-I")
    mutant_build.append(rewritten)
    mutant_build.append(source_path)
    mutant_build.append("-o")
    mutant_build.append(mutant)
    _ = _run(mutant_build, 180.0, "")
    var mutant_run = _run_both([mutant, "0"], 5.0, "")
    if mutant_run[0] != 0:
        _fail("Mutant fixture failed")
    var mutant_raw = work + "/mutant.raw.txt"
    Path(mutant_raw).write_text(mutant_run[2])
    var contradicted = _run_both([reporter, derived_path, mutant_raw], 5.0, "")
    var contradicted_text = contradicted[1] + contradicted[2]
    if (
        contradicted[0] == 0
        or contradicted_text.find("Constant-loop proof contradicted") < 0
    ):
        _fail("Contradictory native probe was accepted: " + contradicted_text)
    Path(source_path).write_text(original)
    var verify = _tool(mojo, "coverage_loop_seal")
    verify.append("verify")
    verify.append("--root")
    verify.append(native)
    verify.append("--build")
    verify.append(rewritten)
    verify.append("--compiler")
    verify.append(compiler)
    verify.append("--flags")
    verify.append(flags)
    verify.append("--mojo")
    verify.append(mojo)
    _ = _run(verify, 180.0, "")
    _ = _run(["rm", "-rf", work], 30.0, "")
    print(
        "PASS: unchanged native loop streams; constant reachable outcomes;"
        " dynamic-empty negative; raw/reduced report parity; actual native"
        " entry-probe mutation rejected"
    )


def _outcomes(stderr_text: String) raises -> Dict[Int, String]:
    """Return the joined COVLINE outcomes for each fixture line."""
    var outcomes = Dict[Int, String]()
    var start = 0
    var count = stderr_text.byte_length()
    var bytes = stderr_text.as_bytes()
    while start < count:
        var end = start
        while end < count and bytes[end] != 10:
            end += 1
        var row = String(stderr_text[byte=start:end])
        if row.startswith("COVLINE:fixture:"):
            var fields = row.split(":")
            if len(fields) == 4:
                var line = Int(String(fields[2]))
                var text = String("")
                if line in outcomes:
                    text = outcomes[line]
                text += String(fields[3])
                outcomes[line] = text
        start = end + 1
    return outcomes^


def _joined(outcomes: Dict[Int, String], line: Int) raises -> String:
    """Return the outcomes stored for `line`."""
    if not line in outcomes:
        return ""
    return outcomes[line]


def _reduce(stderr_text: String) raises -> String:
    """Return the reduced probe records for one run.

    Args:
        stderr_text: The instrumented program's standard error.

    Returns:
        The reduced records.

    Raises:
        Error: A probe record is malformed.
    """
    var reducer = Reducer()
    var start = 0
    var count = stderr_text.byte_length()
    var bytes = stderr_text.as_bytes()
    while start < count:
        var end = start
        while end < count and bytes[end] != 10:
            end += 1
        var line = String(stderr_text[byte=start:end]) + "\n"
        reducer.feed(line)
        if end >= count:
            break
        start = end + 1
    return reducer.output


comptime _FACTORY = (
    "def custom_range(n: Int) -> List[Int]:\n    return List[Int]()\n"
)

comptime _SHADOW = """from std.testing import assert_equal
from shadow_factory import custom_range as range

def main() raises:
    var visits = 0
    for item in range(3):
        visits += item + 1
    assert_equal(visits, 0)
    print(\"RESULT shadowed range\")
"""


def qualify_shadowed_range(mojo: String) raises:
    """Keep both outcomes when `range` names an empty function.

    Args:
        mojo: The Mojo compiler used to build and run the fixture.

    Raises:
        Error: The shadowed loop is proved, drops an outcome, or accepts
            an aliased source.
    """
    var version = _run([mojo, "--version"], 30.0, "")
    var compiler = String(version.strip())
    var flags = "-Werror -I ."
    var work = mkdtemp(prefix="loop shadow ")
    var native = work + "/native"
    var stage = work + "/shadow-stage"
    _ = _run(["mkdir", "-p", native, stage], 10.0, "")
    _ = _run(["cp", "-a", "coverage/.", native + "/coverage/"], 30.0, "")
    _ = _run(["rm", "-rf", native + "/coverage/build"], 10.0, "")
    _ = _run(["mkdir", "-p", stage + "/coverage"], 10.0, "")
    _ = _run(["cp", "-a", "coverage/.", stage + "/coverage/"], 30.0, "")
    _ = _run(["rm", "-rf", stage + "/coverage/build"], 10.0, "")
    _ = _run(["cp", "-a", "tools/.", native + "/tools/"], 60.0, "")
    _ = _run(["rm", "-rf", native + "/tools/__pycache__"], 10.0, "")
    for name in ["core/__init__.mojo", "core/search.mojo", "core/binary.mojo"]:
        _copy(name, native + "/" + name)
    var inputs = List[String]()
    inputs.append("coverage/build_cli.mojo")
    inputs.append("coverage/instrument.mojo")
    inputs.append("coverage/scanner.mojo")
    inputs.append("coverage/runtime.mojo")
    inputs.append("coverage/report.mojo")
    inputs.append("coverage/report_cli.mojo")
    inputs.append("coverage/mcdc.mojo")
    inputs.append("tools/coverage_loop_proofs.py")
    inputs.append("tools/coverage_io.py")
    inputs.append("tools/cache_key.py")
    inputs.append("tools/native_test_support.py")
    inputs.append("tools/coverage_toolchain_identity.py")
    inputs.append("tools/coverage_hit_aot.mojo")
    inputs.append("tools/coverage_hit_cache.c")
    inputs.append("tools/coverage_write_interposer.c")
    inputs.append("tools/run_suite.mojo")
    inputs.append("Makefile")
    for name in inputs:
        _copy(name, native + "/" + name)
    Path(native + "/shadow.mojo").write_text(_SHADOW)
    Path(native + "/shadow_factory.mojo").write_text(_FACTORY)
    Path(stage + "/shadow_factory.mojo").write_text(_FACTORY)
    var reporter = work + "/report"
    var build_report = List[String]()
    build_report.append(mojo)
    build_report.append("build")
    build_report.append("-Werror")
    build_report.append("-I")
    build_report.append(".")
    build_report.append("coverage/report_cli.mojo")
    build_report.append("-o")
    build_report.append(reporter)
    _ = _run(build_report, 180.0, native)
    var begin = _tool(mojo, "coverage_loop_begin")
    begin.append("--root")
    begin.append(native)
    begin.append("--build")
    begin.append(stage)
    begin.append("--compiler")
    begin.append(compiler)
    begin.append("--flags")
    begin.append(flags)
    begin.append("--mojo")
    begin.append(mojo)
    begin.append("--sources")
    begin.append("shadow.mojo")
    _ = _run(begin, 180.0, "")
    var generate = List[String]()
    generate.append(mojo)
    generate.append("run")
    generate.append("-Werror")
    generate.append("-I")
    generate.append(".")
    generate.append("coverage/build_cli.mojo")
    generate.append(stage)
    generate.append("shadow.mojo")
    _ = _run(generate, 180.0, native)
    var line = _line(_SHADOW, "for item in range(3)")
    var manifest = Path(stage + "/manifest.txt").read_text()
    if manifest.find("B shadow " + String(line) + "\n") < 0:
        _fail("Shadow fixture original loop missing")
    var seal = _tool(mojo, "coverage_loop_seal")
    seal.append("--root")
    seal.append(native)
    seal.append("--build")
    seal.append(stage)
    seal.append("--compiler")
    seal.append(compiler)
    seal.append("--flags")
    seal.append(flags)
    seal.append("--mojo")
    seal.append(mojo)
    _ = _run(seal, 180.0, "")
    var receipt = PyJson.parse(Path(stage + "/loop-proofs.json").read_text())
    var proofs = receipt.at(receipt.at(receipt.root, "receipt"), "proofs")
    if receipt.length(proofs) != 0:
        _fail("Shadowed range incorrectly proved builtin")
    var lines = List[Int]()
    lines.append(line)
    var masked_path = stage + "/mojo-masked-manifest.txt"
    var mask = _tool(mojo, "coverage_loop_seal")
    mask.append("mask")
    mask.append("--build")
    mask.append(stage)
    mask.append("--output")
    mask.append(masked_path)
    _ = _run(mask, 60.0, "")
    var derived = diagnostic_manifest(
        Path(masked_path).read_text(), "shadow", lines
    )
    var derived_path = work + "/shadow-manifest.txt"
    Path(derived_path).write_text(derived)
    var plain_bin = native + "/shadow"
    var inst_bin = stage + "/shadow"
    var plain_build = List[String]()
    plain_build.append(mojo)
    plain_build.append("build")
    plain_build.append("-Werror")
    plain_build.append("-I")
    plain_build.append(native)
    plain_build.append(native + "/shadow.mojo")
    plain_build.append("-o")
    plain_build.append(plain_bin)
    _ = _run(plain_build, 180.0, "")
    var inst_build = List[String]()
    inst_build.append(mojo)
    inst_build.append("build")
    inst_build.append("-Werror")
    inst_build.append("-I")
    inst_build.append(stage)
    inst_build.append(stage + "/shadow.mojo")
    inst_build.append("-o")
    inst_build.append(inst_bin)
    _ = _run(inst_build, 180.0, "")
    var plain = _run_both([plain_bin], 5.0, "")
    var instrumented = _run_both([inst_bin], 5.0, "")
    if plain[0] != 0 or instrumented[0] != 0:
        _fail("Shadowed range program failed")
    if (
        plain[1] != "RESULT shadowed range\n"
        or instrumented[1] != "RESULT shadowed range\n"
    ):
        _fail("Shadowed range native semantics changed")
    if plain[2].byte_length() != 0:
        _fail("Unexpected native shadow probe")
    var needle = "COVLINE:shadow:" + String(line) + ":"
    var records = String("")
    var start = 0
    var count = instrumented[2].byte_length()
    var bytes = instrumented[2].as_bytes()
    while start < count:
        var end = start
        while end < count and bytes[end] != 10:
            end += 1
        var row = String(instrumented[2][byte=start:end])
        if row.startswith(needle):
            if records.byte_length() != 0:
                records += "\n"
            records += row
        start = end + 1
    if records != needle + "F":
        _fail("Shadowed range must emit only F")
    var raw_path = work + "/shadow.raw.txt"
    Path(raw_path).write_text(instrumented[2])
    var report = _run_both([reporter, derived_path, raw_path], 5.0, "")
    if report[0] == 0 or report[1].find("branches 1/2") < 0:
        _fail("Shadowed loop lost a reachable/unknown obligation")
    var drifted = String(_SHADOW).replace(
        "from shadow_factory import custom_range as range",
        "# same-line builtin alias drift",
    )
    Path(native + "/shadow.mojo").write_text(drifted)
    var rejected = _tool(mojo, "coverage_loop_seal")
    rejected.append("--root")
    rejected.append(native)
    rejected.append("--build")
    rejected.append(stage)
    rejected.append("--compiler")
    rejected.append(compiler)
    rejected.append("--flags")
    rejected.append(flags)
    rejected.append("--mojo")
    rejected.append(mojo)
    var refusal = _run_both(rejected, 180.0, "")
    var refusal_text = refusal[1] + refusal[2]
    if refusal[0] == 0 or refusal_text.find("generation origin") < 0:
        _fail("Unexpected alias-drift rejection: " + refusal_text)
    Path(native + "/shadow.mojo").write_text(_SHADOW)
    Path(native + "/missing.mojo").write_text("def main():\n    pass\n")
    var again = _tool(mojo, "coverage_loop_begin")
    again.append("--root")
    again.append(native)
    again.append("--build")
    again.append(stage)
    again.append("--compiler")
    again.append(compiler)
    again.append("--flags")
    again.append(flags)
    again.append("--mojo")
    again.append(mojo)
    again.append("--sources")
    again.append("shadow.mojo")
    again.append("missing.mojo")
    _ = _run(again, 180.0, "")
    _ = _run(["rm", "-f", native + "/missing.mojo"], 10.0, "")
    var regenerate = List[String]()
    regenerate.append(mojo)
    regenerate.append("run")
    regenerate.append("-Werror")
    regenerate.append("-I")
    regenerate.append(".")
    regenerate.append("coverage/build_cli.mojo")
    regenerate.append(stage)
    regenerate.append("shadow.mojo")
    regenerate.append("missing.mojo")
    var failed = _run_both(regenerate, 180.0, native)
    if failed[0] == 0:
        _fail("Missing source regeneration unexpectedly succeeded")
    if len(Path(stage + "/origins.ready").read_bytes()) != 0:
        _fail("Failed generation left a usable prior index")
    _ = _run(["rm", "-rf", work], 30.0, "")
    print(
        "PASS: shadowed range stays unknown; both obligations retained;"
        " alias drift rejected"
    )


comptime _PHYSICAL = """from std.testing import assert_equal

def main() raises:
    var text = String(\"é\tλ\")
    var total = 0
    for index in range(2):
        total += index
    assert_equal(total, 1)
    assert_equal(text, \"é\tλ\")
    print(\"RESULT physical\")
"""


def _ending(index: Int) -> String:
    """Return one of the three physical line endings."""
    if index == 0:
        return "\n"
    if index == 1:
        return "\r\n"
    return "\r"


def _utf8(text: String) -> List[UInt8]:
    """Copy `text` into a byte list."""
    var raw = List[UInt8]()
    for item in text.as_bytes():
        raw.append(item)
    return raw^


def qualify_physical_endings(mojo: String) raises:
    """Keep LF, CRLF, and CR source bytes in the generation receipt.

    Args:
        mojo: The Mojo compiler used to build and run the fixture.

    Raises:
        Error: A physical source digest or native result changes.
    """
    var version = _run([mojo, "--version"], 30.0, "")
    var compiler = String(version.strip())
    var flags = "-Werror -I ."
    var work = mkdtemp(prefix="loop physical ")
    var native = work + "/native"
    _ = _run(["mkdir", "-p", native], 10.0, "")
    _ = _run(["cp", "-a", "coverage/.", native + "/coverage/"], 30.0, "")
    _ = _run(["rm", "-rf", native + "/coverage/build"], 10.0, "")
    _ = _run(["cp", "-a", "tools/.", native + "/tools/"], 60.0, "")
    _ = _run(["rm", "-rf", native + "/tools/__pycache__"], 10.0, "")
    for name in ["core/__init__.mojo", "core/search.mojo", "core/binary.mojo"]:
        _copy(name, native + "/" + name)
    var inputs = List[String]()
    inputs.append("coverage/build_cli.mojo")
    inputs.append("coverage/instrument.mojo")
    inputs.append("coverage/scanner.mojo")
    inputs.append("coverage/runtime.mojo")
    inputs.append("coverage/report.mojo")
    inputs.append("coverage/report_cli.mojo")
    inputs.append("coverage/mcdc.mojo")
    inputs.append("tools/coverage_loop_proofs.py")
    inputs.append("tools/coverage_io.py")
    inputs.append("tools/cache_key.py")
    inputs.append("tools/native_test_support.py")
    inputs.append("tools/coverage_toolchain_identity.py")
    inputs.append("tools/coverage_hit_aot.mojo")
    inputs.append("tools/coverage_hit_cache.c")
    inputs.append("tools/coverage_write_interposer.c")
    inputs.append("tools/run_suite.mojo")
    inputs.append("Makefile")
    for name in inputs:
        _copy(name, native + "/" + name)
    var index = 0
    while index < 3:
        var ending = _ending(index)
        var source_name = "physical_" + String(index) + ".mojo"
        var original = _utf8(String(_PHYSICAL).replace("\n", ending))
        var source_path = native + "/" + source_name
        Path(source_path).write_bytes(original)
        var stage = work + "/physical-" + String(index)
        _ = _run(["mkdir", "-p", stage + "/coverage"], 10.0, "")
        _ = _run(["cp", "-a", "coverage/.", stage + "/coverage/"], 30.0, "")
        _ = _run(["rm", "-rf", stage + "/coverage/build"], 10.0, "")
        var begin = _tool(mojo, "coverage_loop_begin")
        begin.append("--root")
        begin.append(native)
        begin.append("--build")
        begin.append(stage)
        begin.append("--compiler")
        begin.append(compiler)
        begin.append("--flags")
        begin.append(flags)
        begin.append("--mojo")
        begin.append(mojo)
        begin.append("--sources")
        begin.append(source_name)
        _ = _run(begin, 180.0, "")
        var generate = List[String]()
        generate.append(mojo)
        generate.append("run")
        generate.append("-Werror")
        generate.append("-I")
        generate.append(".")
        generate.append("coverage/build_cli.mojo")
        generate.append(stage)
        generate.append(source_name)
        _ = _run(generate, 180.0, native)
        var seal = _tool(mojo, "coverage_loop_seal")
        seal.append("--root")
        seal.append(native)
        seal.append("--build")
        seal.append(stage)
        seal.append("--compiler")
        seal.append(compiler)
        seal.append("--flags")
        seal.append(flags)
        seal.append("--mojo")
        seal.append(mojo)
        _ = _run(seal, 180.0, "")
        var receipt = PyJson.parse(
            Path(stage + "/loop-proofs.json").read_text()
        )
        var generation = receipt.at(
            receipt.at(receipt.root, "receipt"), "generation"
        )
        var modules = receipt.at(generation, "modules")
        var item = receipt.at(modules, source_name)
        var recorded = receipt.text(receipt.at(item, "source"))
        if recorded != sha256_hex(Span(original)):
            _fail("Physical source bytes changed")
        var plain_bin = native + "/physical-" + String(index)
        var inst_bin = stage + "/physical-" + String(index)
        var plain_build = List[String]()
        plain_build.append(mojo)
        plain_build.append("build")
        plain_build.append("-Werror")
        plain_build.append("-I")
        plain_build.append(native)
        plain_build.append(source_path)
        plain_build.append("-o")
        plain_build.append(plain_bin)
        _ = _run(plain_build, 180.0, "")
        var inst_build = List[String]()
        inst_build.append(mojo)
        inst_build.append("build")
        inst_build.append("-Werror")
        inst_build.append("-I")
        inst_build.append(stage)
        inst_build.append(stage + "/" + source_name)
        inst_build.append("-o")
        inst_build.append(inst_bin)
        _ = _run(inst_build, 180.0, "")
        var plain = _run_both([plain_bin], 5.0, "")
        var instrumented = _run_both([inst_bin], 5.0, "")
        if plain[0] != 0 or instrumented[0] != 0:
            _fail("Physical program failed")
        if (
            plain[1] != "RESULT physical\n"
            or instrumented[1] != "RESULT physical\n"
        ):
            _fail("Physical-byte native parity failed")
        index += 1
    _ = _run(["rm", "-rf", work], 30.0, "")
    print("PASS: native LF, CRLF, CR and UTF-8 pairs verified")


comptime _TOTAL = """def total(n: Int) -> Int:
    var value = 0
    for index in range(2):
        value += index
    for index in range(n):
        value += index
    return value
"""

comptime _PRODUCTION = """from production import total
from std.testing import assert_equal
from std.ffi import external_call

def main() raises:
    assert_equal(external_call[\"alarm\", UInt32](UInt32(5)), UInt32(0))
    assert_equal(total(0), 1)
    assert_equal(total(2), 2)
    print(\"RESULT production capture\")
"""

comptime _HANG = """from production import total
from std.testing import assert_equal
from std.ffi import external_call

def main() raises:
    assert_equal(external_call[\"alarm\", UInt32](UInt32(5)), UInt32(0))
    assert_equal(total(0), 1)
    while True:
        _ = external_call[\"pause\", Int32]()
"""

comptime _BROKEN = """from production import total

def main() raises:
    var broken =
"""


def _expand(value: String, root: String, build: String) -> String:
    """Replace `@ROOT@` and `@BUILD@` in one capture word."""
    if value == "@ROOT@":
        return root
    if value == "@BUILD@":
        return build
    if value.startswith("@ROOT@/"):
        return root + String(value[byte=6:])
    if value.startswith("@BUILD@/"):
        return build + String(value[byte=7:])
    return value


def _gunzip(path: String) raises -> String:
    """Return the decoded text of a gzip file."""
    return _run(["gzip", "-dc", path], 30.0, "")


def _capture(
    mojo: String,
    output: String,
    archive: String,
    proof: String,
    root: String,
    command: List[String],
    deadline: Float64,
) raises -> Tuple[Int, String, String]:
    """Run one sealed capture under `deadline`."""
    _ = setenv("THREEMOJO_COVERAGE_DEADLINE", String(deadline), True)
    var launch = _tool(mojo, "coverage_io")
    launch.append("capture")
    launch.append("--out")
    launch.append(output)
    launch.append("--err")
    launch.append(archive)
    launch.append("--loop-proof")
    launch.append(proof)
    launch.append("--loop-proof-root")
    launch.append(root)
    launch.append("--")
    for word in command:
        launch.append(word)
    return _run_both(launch, 180.0, "")


def qualify_production_capture(mojo: String) raises:
    """Capture the production suite and reject a hang, a bad compile, and an expired deadline.

    Args:
        mojo: The Mojo compiler used to build and run the fixture.

    Raises:
        Error: The runtime, the reduced capture, or a negative result changes.
    """
    var version = _run([mojo, "--version"], 30.0, "")
    var compiler = String(version.strip())
    var flags = "-Werror -I ."
    var work = mkdtemp(prefix="loop production ")
    var native = work + "/native"
    var stage = work + "/production-stage"
    _ = _run(["mkdir", "-p", native + "/tests", stage + "/tests"], 10.0, "")
    _ = _run(["cp", "-a", "coverage/.", native + "/coverage/"], 30.0, "")
    _ = _run(["rm", "-rf", native + "/coverage/build"], 10.0, "")
    _ = _run(["cp", "-a", "coverage/.", stage + "/coverage/"], 30.0, "")
    _ = _run(["rm", "-rf", stage + "/coverage/build"], 10.0, "")
    _ = _run(["cp", "-a", "tools/.", native + "/tools/"], 60.0, "")
    _ = _run(["rm", "-rf", native + "/tools/__pycache__"], 10.0, "")
    for name in ["core/__init__.mojo", "core/search.mojo", "core/binary.mojo"]:
        _copy(name, native + "/" + name)
    var inputs = List[String]()
    inputs.append("coverage/build_cli.mojo")
    inputs.append("coverage/instrument.mojo")
    inputs.append("coverage/scanner.mojo")
    inputs.append("coverage/runtime.mojo")
    inputs.append("coverage/report.mojo")
    inputs.append("coverage/report_cli.mojo")
    inputs.append("coverage/mcdc.mojo")
    inputs.append("tools/coverage_loop_proofs.py")
    inputs.append("tools/coverage_io.py")
    inputs.append("tools/cache_key.py")
    inputs.append("tools/native_test_support.py")
    inputs.append("tools/coverage_toolchain_identity.py")
    inputs.append("tools/coverage_hit_aot.mojo")
    inputs.append("tools/coverage_hit_cache.c")
    inputs.append("tools/coverage_write_interposer.c")
    inputs.append("tools/run_suite.mojo")
    inputs.append("Makefile")
    for name in inputs:
        _copy(name, native + "/" + name)
    Path(native + "/production.mojo").write_text(_TOTAL)
    var suite = "tests/test_production.mojo"
    var hang = "tests/test_production_hang.mojo"
    var broken = "tests/test_production_compile_error.mojo"
    Path(native + "/" + suite).write_text(_PRODUCTION)
    Path(stage + "/" + suite).write_text(_PRODUCTION)
    Path(native + "/" + hang).write_text(_HANG)
    Path(stage + "/" + hang).write_text(_HANG)
    Path(native + "/" + broken).write_text(_BROKEN)
    Path(stage + "/" + broken).write_text(_BROKEN)
    var reporter = work + "/report"
    var build_report = List[String]()
    build_report.append(mojo)
    build_report.append("build")
    build_report.append("-Werror")
    build_report.append("-I")
    build_report.append(".")
    build_report.append("coverage/report_cli.mojo")
    build_report.append("-o")
    build_report.append(reporter)
    _ = _run(build_report, 180.0, native)
    var begin = _tool(mojo, "coverage_loop_begin")
    begin.append("--root")
    begin.append(native)
    begin.append("--build")
    begin.append(stage)
    begin.append("--compiler")
    begin.append(compiler)
    begin.append("--flags")
    begin.append(flags)
    begin.append("--mojo")
    begin.append(mojo)
    begin.append("--sources")
    begin.append("production.mojo")
    _ = _run(begin, 180.0, "")
    var generate = List[String]()
    generate.append(mojo)
    generate.append("run")
    generate.append("-Werror")
    generate.append("-I")
    generate.append(".")
    generate.append("coverage/build_cli.mojo")
    generate.append(stage)
    generate.append("production.mojo")
    _ = _run(generate, 180.0, native)
    var seal = _tool(mojo, "coverage_loop_seal")
    seal.append("--root")
    seal.append(native)
    seal.append("--build")
    seal.append(stage)
    seal.append("--compiler")
    seal.append(compiler)
    seal.append("--flags")
    seal.append(flags)
    seal.append("--mojo")
    seal.append(mojo)
    seal.append("--suites")
    seal.append(suite)
    seal.append(hang)
    seal.append(broken)
    _ = _run(seal, 180.0, "")
    var plain_bin = work + "/production-runtime-0"
    var inst_bin = work + "/production-runtime-1"
    var plain_build = List[String]()
    plain_build.append(mojo)
    plain_build.append("build")
    plain_build.append("-Werror")
    plain_build.append("-I")
    plain_build.append(native)
    plain_build.append(native + "/" + suite)
    plain_build.append("-o")
    plain_build.append(plain_bin)
    _ = _run(plain_build, 180.0, "")
    var inst_build = List[String]()
    inst_build.append(mojo)
    inst_build.append("build")
    inst_build.append("-Werror")
    inst_build.append("-I")
    inst_build.append(stage)
    inst_build.append(stage + "/" + suite)
    inst_build.append("-o")
    inst_build.append(inst_bin)
    _ = _run(inst_build, 180.0, "")
    var plain = _run_both([plain_bin], 5.0, "")
    var instrumented = _run_both([inst_bin], 5.0, "")
    if plain[0] != 0 or instrumented[0] != 0:
        _fail("Production program failed")
    if (
        plain[1] != "RESULT production capture\n"
        or instrumented[1] != "RESULT production capture\n"
    ):
        _fail("Prebuilt production runtime output changed")
    if plain[2].byte_length() != 0:
        _fail("Uninstrumented production emitted probes")
    var reduced = _reduce(instrumented[2])
    var hits = stage + "/hits"
    _ = _run(["mkdir", "-p", hits], 10.0, "")
    var receipt = PyJson.parse(Path(stage + "/loop-proofs.json").read_text())
    var execution = receipt.at(receipt.at(receipt.root, "receipt"), "execution")
    var symbolic = _expected_command(receipt, execution, suite, "raw")
    var command = List[String]()
    for word in symbolic:
        command.append(_expand(word, native, stage))
    var proof = stage + "/loop-proofs.json"
    var capture = hits + "/test_production.txt.gz"
    var output = hits + "/test_production.out"
    var captured = _capture(
        mojo, output, capture, proof, native, command, _now() + 180.0
    )
    if captured[0] != 0:
        _fail("Production capture failed: " + captured[1] + captured[2])
    if Path(output).read_text() != "RESULT production capture\n":
        _fail("Production capture output changed")
    if _gunzip(capture) != reduced:
        _fail("Real raw-profile and prebuilt runtime probe evidence differ")
    var report = _tool(mojo, "coverage_io")
    report.append("report")
    report.append("--capture-dir")
    report.append(hits)
    report.append("--loop-proof-root")
    report.append(native)
    report.append("--loop-proof-build")
    report.append(stage)
    report.append("--compiler=" + compiler)
    report.append("--flags=" + flags)
    report.append("--mojo")
    report.append(mojo)
    report.append("--suites")
    report.append(suite)
    report.append(hang)
    report.append(broken)
    report.append("--")
    report.append(reporter)
    report.append(stage + "/manifest.txt")
    var reported = _run_both(report, 30.0, "")
    if (
        reported[0] != 0
        or reported[1].find("100%") < 0
        or reported[1].find("proven impossible 1") < 0
    ):
        _fail(
            "Full original manifest failed the proof-aware production report: "
            + reported[1]
            + reported[2]
        )
    var hang_capture = hits + "/test_production_hang.txt.gz"
    var hang_output = hits + "/test_production_hang.out"
    var hang_receipt = hang_capture + ".proof.json"
    Path(hang_receipt).write_text("stale success must be removed")
    var hang_symbolic = _expected_command(receipt, execution, hang, "raw")
    var hang_command = List[String]()
    for word in hang_symbolic:
        hang_command.append(_expand(word, native, stage))
    var hung = _capture(
        mojo,
        hang_output,
        hang_capture,
        proof,
        native,
        hang_command,
        _now() + 180.0,
    )
    if hung[0] == 0 or hung[0] == 124 or hung[0] != 142:
        _fail("Raw runtime did not terminate with SIGALRM")
    if _gunzip(hang_capture).find("COVLINE:production:") < 0:
        _fail("Forced hang never entered the actual production workload")
    if Path(hang_receipt).exists():
        _fail("Failed raw capture left a success receipt")
    var bad_capture = hits + "/test_production_compile_error.txt.gz"
    var bad_output = hits + "/test_production_compile_error.out"
    var bad_receipt = bad_capture + ".proof.json"
    Path(bad_receipt).write_text("stale success must be removed")
    var bad_symbolic = _expected_command(receipt, execution, broken, "raw")
    var bad_command = List[String]()
    for word in bad_symbolic:
        bad_command.append(_expand(word, native, stage))
    var refused = _capture(
        mojo,
        bad_output,
        bad_capture,
        proof,
        native,
        bad_command,
        _now() + 180.0,
    )
    if refused[0] == 0 or refused[0] == 124:
        _fail("Runtime alarm or compiler refusal was not observed")
    var errors = _gunzip(bad_capture)
    if (
        errors.find("error:") < 0
        or errors.find("test_production_compile_error.mojo") < 0
    ):
        _fail("Failure was not the actual fixture compiler refusal")
    if Path(bad_receipt).exists():
        _fail("Failed raw capture left a success receipt")
    var expired_dir = work + "/expired"
    _ = _run(["mkdir", "-p", expired_dir], 10.0, "")
    var expired_capture = expired_dir + "/test_production.txt.gz"
    var expired_output = expired_dir + "/test_production.out"
    var expired_receipt = expired_capture + ".proof.json"
    Path(expired_receipt).write_text("stale success must be removed")
    var exhausted = _capture(
        mojo,
        expired_output,
        expired_capture,
        proof,
        native,
        command,
        _now() - 1.0,
    )
    if exhausted[0] != 124:
        _fail("Expired integration deadline was extended")
    if Path(expired_receipt).exists():
        _fail("Expired capture retained a success receipt")
    _ = _run(["rm", "-rf", work], 30.0, "")
    print(
        "PASS: production capture matches the prebuilt runtime; hang,"
        " compile refusal, and expired deadline stay failures"
    )


def _refuse_verify(
    mojo: String,
    root: String,
    stage: String,
    compiler: String,
    flags: String,
    suite: String,
) raises -> String:
    """Return the refusal text from one seal verify."""
    var command = _tool(mojo, "coverage_loop_seal")
    command.append("verify")
    command.append("--root")
    command.append(root)
    command.append("--build")
    command.append(stage)
    command.append("--compiler")
    command.append(compiler)
    command.append("--flags")
    command.append(flags)
    command.append("--mojo")
    command.append(mojo)
    command.append("--suites")
    command.append(suite)
    var refusal = _run_both(command, 180.0, "")
    return String(refusal[0]) + "\n" + refusal[1] + refusal[2]


def qualify_generated_mutations(mojo: String, stage: String) raises:
    """Reject a changed passthrough file and a new provider in a generated stage.

    Args:
        mojo: The Mojo compiler that sealed `stage`.
        stage: The generated include-root directory.

    Raises:
        Error: A mutation is accepted or the manifest changes.
    """
    var version = _run([mojo, "--version"], 30.0, "")
    var compiler = String(version.strip())
    var flags = "-Werror -I ."
    var suite = "tests/test_carla_lane_geometry_guard_controls.mojo"
    var changed = stage + "/extensions/animals/anatomy/render.mojo"
    var source = "extensions/animals/anatomy/render.mojo"
    var link = _run_both(["test", "-L", changed], 10.0, "")
    if link[0] == 0:
        _fail("Mutation target is not a regular contained generated file")
    var regular = _run_both(["test", "-f", changed], 10.0, "")
    if regular[0] != 0:
        _fail("Mutation target is not a regular contained generated file")
    var changed_real = String(_run(["realpath", changed], 10.0, "").strip())
    var stage_real = String(_run(["realpath", stage], 10.0, "").strip())
    if not changed_real.startswith(stage_real + "/"):
        _fail("Mutation target is not a regular contained generated file")
    var changed_info = stat(changed)
    var source_info = stat(source)
    if (
        changed_info.st_dev == source_info.st_dev
        and changed_info.st_ino == source_info.st_ino
    ):
        _fail("Generated mutation target aliases the sealed source")
    var original = Path(changed).read_bytes()
    var manifest = sha256_hex(Span(Path(stage + "/manifest.txt").read_bytes()))
    var suffixes = List[String]()
    suffixes.append("\n# unsealed same-path change\n")
    suffixes.append("\ndef main():\n    pass\n")
    for suffix in suffixes:
        var mutated = List[UInt8]()
        for byte in original:
            mutated.append(byte)
        for byte in String(suffix).as_bytes():
            mutated.append(byte)
        _ = _run(["rm", "-f", changed], 10.0, "")
        Path(changed).write_bytes(mutated)
        var refusal = _refuse_verify(mojo, ".", stage, compiler, flags, suite)
        _ = _run(["rm", "-f", changed], 10.0, "")
        Path(changed).write_bytes(original.copy())
        if not (
            refusal.startswith("1\n")
            or refusal.startswith("2\n")
            or (not refusal.startswith("0\n"))
        ):
            _fail("Unexpected same-path rejection: " + refusal)
        if refusal.find("Staged input differs") < 0:
            _fail("Unexpected same-path rejection: " + refusal)
    var shadow = stage + "/tests/render.mojo"
    var shadow_exists = _run_both(["test", "-e", shadow], 10.0, "")
    if shadow_exists[0] == 0:
        _fail("Lookup-shadow fixture collides with maintained source")
    Path(shadow).write_text("def main():\n    pass\n")
    var provider = _refuse_verify(mojo, ".", stage, compiler, flags, suite)
    _ = _run(["rm", "-f", shadow], 10.0, "")
    if (
        provider.startswith("0\n")
        or provider.find("Unmaintained executable input") < 0
    ):
        _fail("Unexpected new-provider rejection: " + provider)
    if sha256_hex(Span(Path(stage + "/manifest.txt").read_bytes())) != manifest:
        _fail("Original denominator changed")
    print(
        "PASS: changed passthrough bytes and a new provider are rejected;"
        " the manifest stays"
    )


def main() raises:
    """Qualify the constant-loop, shadow, and physical fixtures."""
    var mojo = ".venv/bin/mojo"
    var mutations = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--mojo" or word == "--mutations":
            if index + 1 >= len(arguments):
                print(
                    (
                        "usage: check_coverage_loop_fixture [--mojo PATH]"
                        " [--mutations STAGE]"
                    ),
                    file=stderr,
                )
                exit(2)
            if word == "--mojo":
                mojo = arguments[index + 1]
            else:
                mutations = arguments[index + 1]
            index += 2
            continue
        print(
            (
                "usage: check_coverage_loop_fixture [--mojo PATH] [--mutations"
                " STAGE]"
            ),
            file=stderr,
        )
        exit(2)
    try:
        if mutations.byte_length() > 0:
            qualify_generated_mutations(mojo, mutations)
        else:
            qualify_constant_loops(mojo)
            qualify_shadowed_range(mojo)
            qualify_physical_endings(mojo)
            qualify_production_capture(mojo)
    except error:
        print("check_coverage_loop_fixture: " + String(error), file=stderr)
        exit(1)
