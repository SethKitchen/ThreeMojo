# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Make cache keys stay distinct, and coverage staging copies the helpers.

    sh tools/tool.sh .venv/bin/mojo check_build_tools

`make test-coverage-tool` runs these checks. `make test-tools` ran their
Python version. Each one runs `make` itself: a cache key reads the whole tree, and a coverage
staging run binds every maintained input. One check takes longer than the
five seconds that a suite test must keep to.
"""

from std.collections import Set
from std.os.path import realpath
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tools._process import run_program


def _set(value: String) -> Set[String]:
    """Return the space-separated words in `value`."""
    var found = Set[String]()
    var parts = value.split(" ")
    for part in parts:
        var word = String(part)
        if word.byte_length() > 0:
            found.add(word)
    return found^


def _line_value(text: String, name: String) raises -> String:
    """Return the value after `name=` on its line."""
    var needle = "\n" + name + "="
    var at = text.find(needle)
    if at < 0 and text.startswith(name + "="):
        at = 0
        needle = name + "="
    elif at >= 0:
        at += 1
        needle = name + "="
    else:
        raise Error("missing " + name)
    var rest = String(text[byte = at + needle.byte_length() :])
    var stop = rest.find("\n")
    if stop < 0:
        return rest
    return String(rest[byte=:stop])


def _contains(group: Set[String], name: String) -> Bool:
    """Return whether `group` holds `name`."""
    return name in group


def _compiler(repo: String) -> String:
    """Return the stand-in compiler for one staging run."""
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
        "from pathlib import Path\n"
        "import shutil, sys\n"
        "if sys.argv[1:] == ['--version']:\n"
        "    print('staging fixture compiler')\n"
        "    raise SystemExit(0)\n"
        "index = sys.argv.index('coverage/build_cli.mojo')\n"
        "build = Path(sys.argv[index + 1])\n"
        "root = Path('"
        + repo
        + "')\n"
        "rows = []\n"
        "for name in sys.argv[index + 2:]:\n"
        "    target = build / name\n"
        "    target.parent.mkdir(parents=True, exist_ok=True)\n"
        "    shutil.copyfile(root / name, target)\n"
        "    rows.append('L ' + name.removesuffix('.mojo') + ' 1\\n')\n"
        "(build / 'manifest.txt').write_text(''.join(rows))\n"
        "model_generation(root, build, sys.argv[index + 2:])\n"
    )


def _make(repo: String, arguments: List[String], clean: Bool) raises -> String:
    """Run make and return its output."""
    var command = List[String]()
    command.append("env")
    if clean:
        command.append("-u")
        command.append("AFFECTED")
        command.append("-u")
        command.append("MAKEFLAGS")
        command.append("-u")
        command.append("MFLAGS")
        command.append("-u")
        command.append("MAKELEVEL")
    for word in arguments:
        command.append(word)
    var ran = run_program(command, 20.0, True, repo)
    if ran.status != 0:
        raise Error(ran.output)
    return ran.output


def test_explicit_partial_checks_have_distinct_keys() raises:
    """CPU_TESTS, COVERED, and MOJOFLAGS each change the cache key."""
    var repo = realpath(".")
    var scratch = mkdtemp(prefix="make-cache-key-")
    try:
        var extra = scratch + "/key.mk"
        Path(extra).write_text("cache-key-test:\n\t@echo $(HASH)\n")
        var base = List[String]()
        base.append("make")
        base.append("--no-print-directory")
        base.append("-s")
        base.append("-f")
        base.append("Makefile")
        base.append("-f")
        base.append(extra)
        base.append("cache-key-test")
        var full = _make(repo, base, True).strip()
        for override in ["CPU_TESTS=", "COVERED=", "MOJOFLAGS=-I . -O0"]:
            var command = List[String]()
            for word in base:
                command.append(word)
            command.append(override)
            var partial = _make(repo, command, True).strip()
            assert_true(full != partial, override)
    finally:
        _ = run_program(["rm", "-rf", scratch], 30.0)


def _classified(repo: String, flags: String) raises -> String:
    """Return the classification lines, with `flags` set when it is nonempty."""
    var scratch = mkdtemp(prefix="make-class-")
    try:
        var extra = scratch + "/classification.mk"
        Path(extra).write_text(
            "classification-test:\n"
            + "\t@echo HELPER_LIBS=$(HELPER_LIBS)\n"
            + "\t@echo DOC_SOURCES=$(DOC_SOURCES)\n"
            + "\t@echo ENTRY_POINTS=$(ENTRY_POINTS)\n"
            + "\t@echo COVERAGE_PASSTHROUGH=$(COVERAGE_PASSTHROUGH)\n"
            + "\t@echo COVERED=$(COVERED)\n"
        )
        var command = List[String]()
        if flags.byte_length() > 0:
            command.append("env")
            command.append("MAKEFLAGS=" + flags)
        command.append("make")
        command.append("--no-print-directory")
        command.append("-s")
        command.append("-f")
        command.append("Makefile")
        command.append("-f")
        command.append(extra)
        command.append("classification-test")
        command.append("AFFECTED=")
        var ran = run_program(command, 20.0, True, repo)
        if ran.status != 0:
            raise Error(ran.output)
        return ran.output
    finally:
        _ = run_program(["rm", "-rf", scratch], 30.0)


def test_import_only_helpers_stay_out_of_the_measured_set() raises:
    """Helper libraries are passthrough, including under an inherited MAKEFLAGS.
    """
    var repo = realpath(".")
    var helpers = [
        "tests/carla_fixed_s_fixture.mojo",
        "tests/exact_predicates_oracle.mojo",
    ]
    for flags in ["", "-- AFFECTED=HEAD"]:
        var text = _classified(repo, flags)
        var helper_libs = _set(_line_value(text, "HELPER_LIBS"))
        var docs = _set(_line_value(text, "DOC_SOURCES"))
        var entries = _set(_line_value(text, "ENTRY_POINTS"))
        var passthrough = _set(_line_value(text, "COVERAGE_PASSTHROUGH"))
        var covered = _set(_line_value(text, "COVERED"))
        for helper in helpers:
            assert_true(_contains(helper_libs, helper), helper)
            assert_true(_contains(docs, helper), helper)
            assert_true(_contains(passthrough, helper), helper)
            assert_false(_contains(entries, helper), helper)
            assert_false(_contains(covered, helper), helper)
        assert_true(_contains(covered, "math/vector3.mojo"))
        for name in covered:
            assert_false(_contains(passthrough, name), name)


def _stage(repo: String, destination: String, arguments: List[String]) raises:
    """Run coverage-instrument with the stand-in compiler."""
    var compiler = destination + ".compiler.py"
    Path(compiler).write_text(_compiler(repo))
    var command = List[String]()
    command.append("make")
    command.append("--no-print-directory")
    command.append("-s")
    command.append("coverage-instrument")
    command.append("MOJO=python3 " + compiler)
    command.append("COV_DIR=" + destination)
    for word in arguments:
        command.append(word)
    var ran = run_program(command, 20.0, True, repo)
    if ran.status != 0:
        raise Error(ran.output)


def test_import_only_helpers_are_copied_beside_their_suites() raises:
    """The default passthrough copies the helper libraries next to the suites.
    """
    var repo = realpath(".")
    var scratch = mkdtemp(prefix="coverage-stage-")
    var destination = scratch + "/instrumented"
    try:
        var arguments = List[String]()
        arguments.append("LIB_SOURCES=math/vector3.mojo")
        arguments.append("COVERED=math/vector3.mojo")
        arguments.append(
            "COVERAGE_TESTS=tests/test_carla_fixed_s_fraction.mojo"
            " tests/test_exact_predicates.mojo"
        )
        arguments.append(
            "TESTS=tests/test_carla_fixed_s_fraction.mojo"
            " tests/test_exact_predicates.mojo"
        )
        _stage(repo, destination, arguments)
        var names = List[String]()
        names.append("tests/carla_fixed_s_fixture.mojo")
        names.append("tests/exact_predicates_oracle.mojo")
        names.append("tests/test_carla_fixed_s_fraction.mojo")
        names.append("tests/test_exact_predicates.mojo")
        for name in names:
            assert_equal(
                Path(destination + "/" + name).read_bytes(),
                Path(repo + "/" + name).read_bytes(),
            )
    finally:
        _ = run_program(["rm", "-rf", scratch], 30.0)


def test_unselected_sibling_modules_are_staged() raises:
    """A suite that is not in this runner's group is still copied."""
    var repo = realpath(".")
    var scratch = mkdtemp(prefix="coverage-sibling-")
    var destination = scratch + "/instrumented"
    try:
        var selected = "tests/test_carla_render_scene.mojo"
        var sibling = "tests/test_carla_assets.mojo"
        var arguments = List[String]()
        arguments.append("COVERED=math/vector3.mojo")
        arguments.append("COVERAGE_PASSTHROUGH=")
        arguments.append("COVERAGE_TESTS=" + selected)
        arguments.append("TESTS=" + selected + " " + sibling)
        _stage(repo, destination, arguments)
        assert_true(Path(destination + "/" + selected).is_file())
        assert_true(Path(destination + "/" + sibling).is_file())
        assert_equal(
            Path(destination + "/" + sibling).read_bytes(),
            Path(repo + "/" + sibling).read_bytes(),
        )
    finally:
        _ = run_program(["rm", "-rf", scratch], 30.0)


def main() raises:
    """Run the build-tool checks."""
    TestSuite.discover_tests[__functions_in_module()]().run()
