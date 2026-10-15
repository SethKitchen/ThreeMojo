# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compiler-free controls for the inherited-default coverage source check.

The expectations are the Python tool's values. A shell script stands in for
the compiler, so no test builds Mojo.
"""

from std.os import listdir
from std.os.path import exists, isdir, realpath
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._tree import Tree
from tools._cli import parse_command_line
from tools._process import run_program
from tools.check_coverage_sources import (
    DEFAULTS,
    HELP,
    PROGRAM,
    USAGE,
    check,
    check_stress,
    colliding_loop,
    command_text,
    copy_tree,
    count_of,
    default_records,
    line_of,
    manifest,
    read_text,
    require,
    run_checked,
    stress_source,
    universal_newlines,
)


def test_manifest_rows_follow_python_order() raises:
    assert_equal(
        manifest("m", [1, 2], [(3, 2), (4, 0)]),
        "L m 1\nL m 2\nB m 3\nC m 3 0\nM m 3 0\nC m 3 1\nM m 3 1\nB m 4\n",
    )


def test_default_records_are_the_full_raw_stream() raises:
    assert_equal(
        default_records(),
        (
            "COVLINE:defaults:21\nCOVLINE:defaults:22\nCOVLINE:defaults:23\n"
            "COVLINE:defaults:10\nCOVLINE:defaults:18\nCOVLINE:defaults:10.0:T\n"
            "COVLINE:defaults:10.1:T\nCOVLINE:defaults:10:T\n"
            "COVEVAL2:defaults:10:T:TT;\nCOVLINE:defaults:11\n"
            "COVLINE:defaults:10\nCOVLINE:defaults:18\nCOVLINE:defaults:10.0:T\n"
            "COVLINE:defaults:10.1:F\nCOVLINE:defaults:10:F\n"
            "COVEVAL2:defaults:10:F:TF;\nCOVLINE:defaults:12\n"
            "COVLINE:defaults:10\nCOVLINE:defaults:18\nCOVLINE:defaults:10.0:F\n"
            "COVLINE:defaults:10:F\nCOVEVAL2:defaults:10:F:F-;\n"
            "COVLINE:defaults:12\n"
        ),
    )


def test_stress_fixture_names_its_colliding_loop_line() raises:
    assert_equal(colliding_loop(), 49)
    var source = stress_source()
    assert_equal(source.find("LOOP"), -1)
    assert_true(source.find("var _cov_loop_49 = 40") >= 0)
    assert_true(source.find("var _cov_loop__49 = 50") >= 0)
    assert_true(source.find("# COLLIDING_49") >= 0)
    assert_equal(line_of(source, "if self.leaf("), 11)
    assert_equal(line_of(source, "range(0)"), 52)
    with assert_raises(contains="StopIteration"):
        _ = line_of(source, "no such marker")
    assert_true(String(DEFAULTS).startswith('"""Inherited bodies'))


def _stress_raw() -> List[String]:
    """Return a raw stream that satisfies every stress expectation."""
    var rows: List[String] = [
        "COVEVAL2:stress:11:F:F-;",
        "COVEVAL2:stress:11:F:TF;",
        "COVEVAL2:stress:11:T:TT;",
        "COVEVAL2:stress:11:F:TF;",
        "COVEVAL2:stress:17:F:F-;",
        "COVEVAL2:stress:17:F:TF;",
        "COVEVAL2:stress:17:F:TF;",
        "COVEVAL2:stress:17:F:TF;",
        "COVEVAL2:stress:26:F:TF;",
        "COVEVAL2:stress:26:T:TT;",
        "COVEVAL2:stress:29:T:TTTT;",
        "COVLINE:stress:49:T",
        "COVLINE:stress:52:F",
        "COVLINE:stress:11.0:T",
        "COVLINE:stress:11.0:T",
        "COVLINE:stress:11.0:T",
        "COVLINE:stress:11.0:T",
        "COVLINE:stress:11.1:T",
        "COVLINE:stress:11.1:F",
        "COVLINE:stress:11.1:F",
    ]
    return rows^


comptime STRESS_TEXT = (
    "from coverage.runtime import hit as _cov_hit__, branch as _cov_branch__,"
    " buffer as _cov_eval__buffer\n    var _cov_loop___49 = 0\n"
)


def test_stress_records_accept_the_exact_stream() raises:
    check_stress("\n".join(_stress_raw()) + "\n", STRESS_TEXT)


def test_stress_records_reject_each_change() raises:
    var rows = _stress_raw()
    for index in range(len(rows)):
        var changed = rows.copy()
        _ = changed.pop(index)
        with assert_raises(contains="AssertionError"):
            check_stress("\n".join(changed) + "\n", STRESS_TEXT)
    # A throwing operand must not add a complete vector.
    var extra = rows.copy()
    extra.append("COVLINE:stress:11.1:T")
    with assert_raises(contains="AssertionError"):
        check_stress("\n".join(extra) + "\n", STRESS_TEXT)
    for name in [
        "_cov_loop___49 = 0",
        "hit as _cov_hit__, branch as _cov_branch__",
        "buffer as _cov_eval__buffer",
    ]:
        with assert_raises(contains="AssertionError"):
            check_stress(
                "\n".join(rows) + "\n", String(STRESS_TEXT).replace(name, "")
            )


def test_python_text_meanings() raises:
    assert_equal(count_of("aaaa", "aa"), 2)
    assert_equal(count_of("abc", "x"), 0)
    assert_equal(universal_newlines("a\r\nb\rc\n"), "a\nb\nc\n")
    assert_equal(command_text(["mojo", "it's"]), "['mojo', \"it's\"]")
    with assert_raises(contains="AssertionError: why"):
        require(False, "why")
    with assert_raises(contains="AssertionError"):
        require(False)
    require(True, "never")


def test_failed_programs_report_the_command_and_both_streams() raises:
    with assert_raises(
        contains=(
            "RuntimeError: ['sh', '-c', 'echo out; echo err >&2; exit 3']:"
            "\nout\n\nerr\n"
        )
    ):
        _ = run_checked(["sh", "-c", "echo out; echo err >&2; exit 3"], 5)
    with assert_raises(contains="timed out after 0.3 seconds"):
        _ = run_checked(["sleep", "5"], 0.3)
    var result = run_checked(["sh", "-c", "printf 'a\\r\\nb'; printf x >&2"], 5)
    assert_equal(result.output, "a\nb")
    assert_equal(result.errors, "x")
    assert_equal(result.status, 0)


def test_copy_tree_leaves_out_build_folders_and_reads_universal_text() raises:
    var tree = Tree()
    tree.write("source/a.mojo", "a\r\nb\r")
    tree.write("source/build/x", "x")
    tree.write("source/inner/build", "y")
    tree.write("source/inner/c.mojo", "c")
    copy_tree(tree.root + "/source", tree.root + "/copy")
    assert_true(isdir(tree.root + "/copy/inner"))
    assert_false(exists(tree.root + "/copy/build"))
    assert_false(exists(tree.root + "/copy/inner/build"))
    assert_equal(tree.read("copy/inner/c.mojo"), "c")
    assert_equal(read_text(tree.root + "/copy/a.mojo"), "a\nb\n")
    tree.close()


def test_a_failing_compiler_stops_the_check() raises:
    var tree = Tree()
    tree.write("mojo", "#!/bin/sh\necho broken compiler >&2\nexit 9\n")
    _ = run_program(["chmod", "+x", tree.root + "/mojo"], 10)
    with assert_raises(contains="broken compiler"):
        check(tree.root + "/mojo", None)
    tree.close()


def test_help_and_usage_errors_match_argparse() raises:
    var help = parse_command_line(
        ["--help"], PROGRAM, USAGE, HELP, List[String](), ["--mojo", "--output"]
    )
    assert_equal(help.status, -1)
    assert_true(help.message.startswith(USAGE + "\nCheck inherited defaults"))
    var bad = parse_command_line(
        ["--bogus"],
        PROGRAM,
        USAGE,
        HELP,
        List[String](),
        ["--mojo", "--output"],
    )
    assert_equal(bad.status, 2)
    assert_true(
        bad.message.endswith(
            "check_coverage_sources.mojo: error: unrecognized arguments:"
            " --bogus\n"
        )
    )
    var given = parse_command_line(
        ["--out", "x", "--mojo=m"],
        PROGRAM,
        USAGE,
        HELP,
        List[String](),
        ["--mojo", "--output"],
    )
    assert_equal(given.value("--output", ""), "x")
    assert_equal(given.value("--mojo", ""), "m")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
