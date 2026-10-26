# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Qualify coverage loop fixtures with the Mojo coverage tools.

    check_coverage_loop_fixture [--mojo PATH]

The program checks the three constant loops and a shadowed `range`. The
profiled owner controls stay in `tools/check_coverage_loop_proofs.py`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._process import run_program
from tools._python_json import PyJson
from tools.coverage_io import Reducer


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


def main() raises:
    """Qualify the constant-loop fixture and the shadowed range."""
    var mojo = ".venv/bin/mojo"
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--mojo":
            if index + 1 >= len(arguments):
                print(
                    "usage: check_coverage_loop_fixture [--mojo PATH]",
                    file=stderr,
                )
                exit(2)
            mojo = arguments[index + 1]
            index += 2
            continue
        print("usage: check_coverage_loop_fixture [--mojo PATH]", file=stderr)
        exit(2)
    try:
        qualify_constant_loops(mojo)
        qualify_shadowed_range(mojo)
    except error:
        print("check_coverage_loop_fixture: " + String(error), file=stderr)
        exit(1)
