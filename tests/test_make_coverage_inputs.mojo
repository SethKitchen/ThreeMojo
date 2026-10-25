# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The coverage-instrument recipe copies helpers and binds the Mojo seal."""

from std.collections import Set
from std.os.path import realpath
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tests._tree import tool_mojo
from tools._imports import imported_names, resolve
from tools._process import run_program
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


def _tools() -> List[String]:
    """Return the receipt's tool inputs, except the stub Makefile."""
    var names = List[String]()
    names.append("coverage/build_cli.mojo")
    names.append("coverage/instrument.mojo")
    names.append("coverage/scanner.mojo")
    names.append("coverage/runtime.mojo")
    names.append("coverage/report.mojo")
    names.append("coverage/report_cli.mojo")
    names.append("coverage/mcdc.mojo")
    names.append("tools/coverage_loop_proofs.py")
    names.append("tools/coverage_io.py")
    names.append("tools/cache_key.py")
    names.append("tools/native_test_support.py")
    names.append("tools/coverage_toolchain_identity.py")
    names.append("tools/coverage_process_group.py")
    names.append("tools/coverage_hit_aot.py")
    names.append("tools/coverage_hit_cache.c")
    names.append("tools/coverage_write_interposer.c")
    names.append("tools/test_environment.py")
    names.append("tools/run_suite.py")
    return names^


def _inputs() -> List[String]:
    """Return the fixture sources the recipe must see."""
    var names = List[String]()
    names.append("math/measured.mojo")
    names.append("math/unmeasured.mojo")
    names.append("bench/helper.mojo")
    names.append("bench/nested/driver.mojo")
    names.append("coverage/runtime.mojo")
    names.append("tests/test_driver.mojo")
    names.append("tests/_shared.mojo")
    names.append("tests/_nested.mojo")
    names.append("examples/unrelated.mojo")
    names.append("tools/doc_lint.mojo")
    names.append("tools/_anatomy_pairs.mojo")
    names.append("tools/anatomy_probe.mojo")
    names.append("tools/capture_carla_fixed_s_controls.mojo")
    names.append("tools/draco_export_check.mojo")
    names.append("tools/fixtures/carla_sum2_fp_state.c")
    return names^


def _slice(text: String, start: String, end: String) raises -> String:
    """Return the text from `start` up to `end`."""
    var at = text.find(start)
    if at < 0:
        raise Error("missing " + start)
    var rest = String(text[byte=at:])
    var stop = rest.find(end)
    if stop < 0:
        raise Error("missing " + end)
    return String(rest[byte=:stop])


def _line_from(text: String, start: String) raises -> String:
    """Return the line that starts with `start`."""
    var at = text.find(start)
    if at < 0:
        raise Error("missing " + start)
    var rest = String(text[byte=at:])
    var stop = rest.find("\n")
    if stop < 0:
        return rest
    return String(rest[byte=:stop])


def _compiler() -> String:
    """Return the stand-in compiler the recipe runs."""
    return (
        "def model_generation(root, build, names=('module.mojo',)):\n"
        "    manifest = (build / 'manifest.txt').read_bytes()\n"
        "    for name in names:\n"
        "        module = name.removesuffix('.mojo').encode()\n"
        "        fragment = b''.join(row for row in"
        " manifest.splitlines(keepends=True)\n"
        "            if len(row.split()) >= 2 and row.split()[1] =="
        " module)\n"
        "        parts = [name.encode(), (root / name).read_bytes(),\n"
        "                 (build / name).read_bytes(), fragment]\n"
        "        record = b'COVORIGIN1 ' + b' '.join(str(len(part)).encode()"
        " for part in parts) + b'\\n' + b''.join(parts)\n"
        "        (build / (name + '.cov-origin')).write_bytes(record)\n"
        "    checkpoint = (build / 'generation-inputs.json').read_bytes()\n"
        "    index = (b'COVORIGIN_INDEX2 ' + str(len(names)).encode() + b'"
        " ' + str(len(manifest)).encode()\n"
        "             + b' ' + str(len(checkpoint)).encode() + b'\\n' +"
        " manifest + checkpoint)\n"
        "    for name in names:\n"
        "        raw = name.encode()\n"
        "        index += str(len(raw)).encode() + b'\\n' + raw\n"
        "    (build / 'origins.ready').write_bytes(index)\n"
        "import os, sys\n"
        "from pathlib import Path\n"
        "assert sys.argv[1:3] == ['run', 'coverage/build_cli.mojo']\n"
        "if os.environ.get('FAIL_INSTRUMENTER'):\n"
        "    raise SystemExit(7)\n"
        "root = Path(sys.argv[3])\n"
        "for name in sys.argv[4:]:\n"
        "    path = root / name\n"
        "    path.parent.mkdir(parents=True, exist_ok=True)\n"
        "    path.write_text('instrumented ' + name + '\\n')\n"
        "(root / 'manifest.txt').write_text(''.join('L ' +"
        " name.removesuffix('.mojo') + ' 1\\n' for name in sys.argv[4:]))\n"
        "model_generation(Path.cwd(), root, sys.argv[4:])\n"
    )


def _write(path: String, text: String) raises:
    """Write `text`, creating parent directories."""
    var slash = path.rfind("/")
    if slash > 0:
        var parent = String(path[byte=:slash])
        var made = run_program(["mkdir", "-p", parent], 10.0)
        if made.status != 0:
            raise Error(made.output)
    Path(path).write_text(text)


def _copy(source: String, dest: String) raises:
    """Copy one file, creating parent directories."""
    var slash = dest.rfind("/")
    if slash > 0:
        var parent = String(dest[byte=:slash])
        var made = run_program(["mkdir", "-p", parent], 10.0)
        if made.status != 0:
            raise Error(made.output)
    Path(dest).write_bytes(Path(source).read_bytes())


def _stamp() raises -> String:
    """Return the tool-cache directory name for this compiler."""
    var ran = run_program(
        [
            "sh",
            "-c",
            tool_mojo() + " --version 2>/dev/null | cksum | cut -d ' ' -f 1",
        ],
        20.0,
        merge_errors=False,
    )
    if ran.status != 0:
        raise Error(ran.errors)
    var text = ran.output
    if text.endswith("\n"):
        var end = text.byte_length() - 1
        var trimmed = String(text[byte=:end])
        return trimmed
    return text


def _prepare() raises -> String:
    """Create one fixture tree and return its root."""
    var root = mkdtemp(prefix="coverage-inputs-")
    for name in _inputs():
        _write(root + "/" + name, "original " + name + "\n")
    for name in _tools():
        var dest = root + "/" + name
        if not Path(dest).exists():
            _copy(name, dest)
    _copy(
        "tools/coverage_reviewed_loops.json",
        root + "/tools/coverage_reviewed_loops.json",
    )
    _write(root + "/compiler.py", _compiler())
    var makefile = Path("Makefile").read_text()
    var quote = _line_from(makefile, "quote =")
    var run = _slice(makefile, "define run\n", "\nendef") + "\nendef"
    var passthrough = _slice(makefile, "COVERAGE_PASSTHROUGH :=", "\n\n")
    var recipe = _slice(
        makefile, "coverage-instrument:\n", "\ncoverage-capture:"
    )
    var stamp = _stamp()
    var wrapper = root + "/toolwrap.sh"
    # Keep the fixture as the working directory. The binary path is absolute.
    _write(
        wrapper,
        "#!/bin/sh\nname=$1\nshift\nexec "
        + realpath(".")
        + "/.cache/tools/"
        + stamp
        + '/"$name" "$@"\n',
    )
    var mode = run_program(["chmod", "755", wrapper], 10.0)
    if mode.status != 0:
        raise Error(mode.output)
    _write(
        root + "/Makefile",
        "MOJO := python3 compiler.py\nMOJOFLAGS :=\nCOV_DIR := build\nTOOL := '"
        + wrapper
        + "'\n"
        + quote
        + "\n"
        + "LIB_SOURCES := math/measured.mojo math/unmeasured.mojo\n"
        + "HELPER_LIBS := tests/_shared.mojo tests/_nested.mojo"
        + " tools/_anatomy_pairs.mojo\n"
        + "ENTRY_POINTS := bench/helper.mojo bench/nested/driver.mojo "
        + "tests/test_driver.mojo examples/unrelated.mojo "
        + "tools/doc_lint.mojo tools/anatomy_probe.mojo "
        + "tools/capture_carla_fixed_s_controls.mojo"
        + " tools/draco_export_check.mojo\n"
        + "TESTS := tests/test_driver.mojo\n"
        + "COVERED := math/measured.mojo\n"
        + run
        + "\n"
        + passthrough
        + "\n"
        + recipe,
    )
    return root


def _make(root: String, extra: List[String], fail: Bool) raises -> String:
    """Run coverage-instrument and return its combined output."""
    var command = List[String]()
    command.append("env")
    command.append("-u")
    command.append("MAKEFLAGS")
    command.append("-u")
    command.append("MFLAGS")
    command.append("-u")
    command.append("MAKEOVERRIDES")
    command.append("-u")
    command.append("MAKELEVEL")
    command.append("-u")
    command.append("MAKEFILES")
    command.append("-u")
    command.append("GNUMAKEFLAGS")
    if fail:
        command.append("FAIL_INSTRUMENTER=1")
    command.append("make")
    command.append("-s")
    for word in extra:
        command.append(word)
    command.append("coverage-instrument")
    var ran = run_program(command, 20.0, True, root)
    return String(ran.status) + "\n" + ran.output


def _status(text: String) -> Int:
    """Return the status line written by `_make`."""
    var line = text
    var stop = text.find("\n")
    if stop >= 0:
        line = String(text[byte=:stop])
    var value = 0
    var index = 0
    var bytes = line.as_bytes()
    while index < len(bytes):
        value = value * 10 + Int(bytes[index]) - 48
        index += 1
    return value


def _body(text: String) -> String:
    """Return `_make` output after the status line."""
    var stop = text.find("\n")
    if stop < 0:
        return ""
    return String(text[byte = stop + 1 :])


def _ok(text: String) raises:
    """Require a zero make status."""
    if _status(text) != 0:
        raise Error(_body(text))


def test_generation_order_does_not_change_the_receipt() raises:
    """Two source orders produce one sorted checkpoint and one receipt."""
    var root = _prepare()
    try:
        var names = List[String]()
        names.append("math/measured.mojo")
        names.append("math/unmeasured.mojo")
        var first = Path(root + "/math/measured.mojo").read_bytes()
        var second = Path(root + "/math/unmeasured.mojo").read_bytes()
        var receipts = List[String]()
        var orders = List[String]()
        orders.append("math/measured.mojo math/unmeasured.mojo")
        orders.append("math/unmeasured.mojo math/measured.mojo")
        for order in orders:
            _ = run_program(
                [
                    "rm",
                    "-f",
                    root + "/math/measured.mojo",
                    root + "/math/unmeasured.mojo",
                ],
                10.0,
            )
            var forward = order == String(orders[0])
            if forward:
                Path(root + "/math/measured.mojo").write_bytes(first)
                Path(root + "/math/unmeasured.mojo").write_bytes(second)
            else:
                Path(root + "/math/unmeasured.mojo").write_bytes(second)
                Path(root + "/math/measured.mojo").write_bytes(first)
            var covered = List[String]()
            covered.append("COVERED=" + order)
            var text = _make(root, covered, False)
            _ok(text)
            var doc = PyJson.parse(
                Path(root + "/build/generation-inputs.json").read_text()
            )
            var sources = doc.at(doc.root, "sources")
            assert_equal(doc.length(sources), 2)
            assert_equal(doc.text(doc.item(sources, 0)), "math/measured.mojo")
            assert_equal(doc.text(doc.item(sources, 1)), "math/unmeasured.mojo")
            assert_equal(
                Path(root + "/build/manifest.txt").read_text(),
                "L math/measured 1\nL math/unmeasured 1\n",
            )
            receipts.append(Path(root + "/build/loop-proofs.json").read_text())
        assert_equal(receipts[0], receipts[1])
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def test_duplicate_sources_are_refused() raises:
    """A repeated measured source does not leave a receipt."""
    var root = _prepare()
    try:
        var extra = List[String]()
        extra.append("COVERED=math/measured.mojo math/measured.mojo")
        var text = _make(root, extra, False)
        assert_true(_status(text) != 0)
        assert_true(_body(text).find("distinct source identities") >= 0)
        assert_false(Path(root + "/build/loop-proofs.json").exists())
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def test_helpers_copy_through_and_one_module_is_measured() raises:
    """Only the measured module is instrumented. The other inputs are copied."""
    var root = _prepare()
    try:
        var text = _make(root, List[String](), False)
        _ok(text)
        assert_equal(
            Path(root + "/build/manifest.txt").read_text(),
            "L math/measured 1\n",
        )
        for name in _inputs():
            var staged = root + "/build/" + name
            if name == "examples/unrelated.mojo":
                assert_false(Path(staged).exists())
            elif name == "math/measured.mojo":
                assert_equal(
                    Path(staged).read_text(), "instrumented " + name + "\n"
                )
            else:
                assert_equal(
                    Path(staged).read_bytes(),
                    Path(root + "/" + name).read_bytes(),
                )
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def test_a_measured_helper_stays_instrumented() raises:
    """A helper named in COVERED is instrumented, and its sibling is copied."""
    var root = _prepare()
    try:
        var extra = List[String]()
        extra.append("COVERED=math/measured.mojo bench/helper.mojo")
        var text = _make(root, extra, False)
        _ok(text)
        assert_equal(
            Path(root + "/build/bench/helper.mojo").read_text(),
            "instrumented bench/helper.mojo\n",
        )
        assert_equal(
            Path(root + "/build/bench/nested/driver.mojo").read_bytes(),
            Path(root + "/bench/nested/driver.mojo").read_bytes(),
        )
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def test_nested_helpers_keep_their_bytes() raises:
    """Nested test helpers are copied and add no manifest row."""
    var root = _prepare()
    try:
        Path(root + "/tests/_nested.mojo").write_text(
            "from math.measured import value\r\n"
        )
        Path(root + "/tests/_shared.mojo").write_text(
            "from tests._nested import value\n"
        )
        var text = _make(root, List[String](), False)
        _ok(text)
        assert_equal(
            Path(root + "/build/tests/_nested.mojo").read_text(),
            "from math.measured import value\r\n",
        )
        assert_equal(
            Path(root + "/build/tests/_shared.mojo").read_text(),
            "from tests._nested import value\n",
        )
        assert_equal(
            Path(root + "/build/manifest.txt").read_text(),
            "L math/measured 1\n",
        )
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def _known() -> Set[String]:
    """Return the fixture's source paths."""
    var known = Set[String]()
    for name in _inputs():
        known.add(name)
    return known^


def _joined(paths: List[String]) -> String:
    """Return paths joined by newlines."""
    var text = ""
    var index = 0
    while index < len(paths):
        if index > 0:
            text += "\n"
        text += paths[index]
        index += 1
    return text


def test_staged_tools_resolve_like_the_source_tree() raises:
    """A staged tool import reaches the same files, and a later edit is refused.
    """
    var root = _prepare()
    try:
        Path(root + "/tests/test_driver.mojo").write_text(
            "from tools.doc_lint import check_links\n"
        )
        Path(root + "/tools/doc_lint.mojo").write_text(
            "from tools.anatomy_probe import helper\n"
            + "def main():\n    pass\n"
        )
        var text = _make(root, List[String](), False)
        _ok(text)
        var known = _known()
        var entries = List[String]()
        entries.append("tests")
        var names = imported_names(
            Path(root + "/tests/test_driver.mojo").read_text()
        )
        var reached = List[String]()
        for name in names:
            for path in resolve(name, known, entries):
                reached.append(path)
        var flat = _joined(reached)
        assert_true(flat.find("tools/doc_lint.mojo") >= 0, flat)
        var tool_names = imported_names(
            Path(root + "/tools/doc_lint.mojo").read_text()
        )
        var tool_entries = List[String]()
        tool_entries.append("tools")
        var tools = List[String]()
        for name in tool_names:
            for path in resolve(name, known, tool_entries):
                tools.append(path)
        var tool_flat = _joined(tools)
        assert_true(tool_flat.find("tools/anatomy_probe.mojo") >= 0, tool_flat)
        var doc = PyJson.parse(
            Path(root + "/build/loop-proofs.json").read_text()
        )
        var receipt = doc.at(doc.root, "receipt")
        var inputs = doc.at(receipt, "inputs")
        var probe = root + "/tools/anatomy_probe.mojo"
        var digest = sha256_hex(Path(probe).read_bytes())
        var bound = doc.at(inputs, "tools/anatomy_probe.mojo")
        assert_equal(doc.text(doc.at(bound, "source")), digest)
        assert_equal(doc.text(doc.at(bound, "instrumented")), digest)
        var staged = root + "/build/tools/anatomy_probe.mojo"
        var original = Path(staged).read_text()
        Path(staged).write_text(original + "# changed after sealing\n")
        var verify = run_program(
            [
                root + "/toolwrap.sh",
                "coverage_loop_seal",
                "verify",
                "--root",
                root,
                "--build",
                root + "/build",
                "--compiler=",
                "--flags=",
                "--mojo=python3 compiler.py",
                "--capture-cache=/native-coverage",
                "--suites",
            ],
            20.0,
            True,
            root,
        )
        assert_true(verify.status != 0, verify.output)
        Path(staged).write_text(original)
        var again = run_program(
            [
                root + "/toolwrap.sh",
                "coverage_loop_seal",
                "verify",
                "--root",
                root,
                "--build",
                root + "/build",
                "--compiler=",
                "--flags=",
                "--mojo=python3 compiler.py",
                "--capture-cache=/native-coverage",
                "--suites",
            ],
            20.0,
            True,
            root,
        )
        if again.status != 0:
            raise Error(again.output)
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def test_an_empty_measurement_does_not_create_a_build() raises:
    """COVERED empty prints the unmeasured line and leaves no build directory.
    """
    var root = _prepare()
    try:
        var extra = List[String]()
        extra.append("COVERED=")
        var text = _make(root, extra, False)
        _ok(text)
        assert_true(_body(text).find("coverage not measured") >= 0)
        assert_false(Path(root + "/build").exists())
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def test_an_instrumenter_failure_copies_nothing() raises:
    """A failing compiler stops before the passthrough copy."""
    var root = _prepare()
    try:
        var text = _make(root, List[String](), True)
        assert_true(_status(text) != 0)
        assert_false(Path(root + "/build/bench/helper.mojo").exists())
        assert_false(Path(root + "/build/manifest.txt").exists())
    finally:
        _ = run_program(["rm", "-rf", root], 30.0)


def main() raises:
    """Build the recipe tools, then run the tests."""
    var mojo = tool_mojo()
    for name in [
        "coverage_loop_begin",
        "coverage_loop_seal",
        "native_test_support",
    ]:
        var built = run_program(
            ["sh", "tools/tool.sh", mojo, "--build", name], 120.0
        )
        if built.status != 0:
            raise Error(built.output + built.errors)
    TestSuite.discover_tests[__functions_in_module()]().run()
