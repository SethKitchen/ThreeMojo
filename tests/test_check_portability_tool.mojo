# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compiler-free controls for native portability result handling.

A shell script stands in for the compiler and for the probe, so no test
builds Mojo.
"""

from std.os import getenv, setenv, unsetenv
from std.os.path import realpath
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

from tests._tree import Tree
from tools._cli import absolute_path, normal_path
from tools._process import run_program
from tools.check_portability import (
    SECONDS,
    Background,
    Setting,
    check,
    check_child,
    child_command,
    parent_path,
    parse_portability,
    relative_path,
    which,
)
from tools._text import split_lines


def _environment(settings: List[Setting]) raises -> List[String]:
    """Return the sorted `NAME=value` lines of a child's environment."""
    var result = run_program(child_command(settings, ["env"]), 10)
    assert_equal(result.status, 0)
    var lines = List[String]()
    for line in split_lines(result.output):
        if line.startswith("THREEMOJO_") or line.startswith("PORTABILITY_KEEP"):
            lines.append(line)
    sort(lines)
    return lines^


def test_child_environment_does_not_inherit_roots_or_probe_actions() raises:
    var names: List[String] = [
        "THREEMOJO_ASSET_ROOT",
        "THREEMOJO_TEST_TMPDIR",
        "THREEMOJO_PORTABILITY_FAIL",
        "PORTABILITY_KEEP",
    ]
    var saved = List[String]()
    for name in names:
        saved.append(getenv(name, "\x00"))
    try:
        _ = setenv("THREEMOJO_ASSET_ROOT", "old")
        _ = setenv("THREEMOJO_TEST_TMPDIR", "old")
        _ = setenv("THREEMOJO_PORTABILITY_FAIL", "yes")
        _ = setenv("PORTABILITY_KEEP", "parent")
        var lines = _environment([("THREEMOJO_ASSET_ROOT", "new")])
        assert_equal(len(lines), 2)
        assert_equal(lines[0], "PORTABILITY_KEEP=parent")
        assert_equal(lines[1], "THREEMOJO_ASSET_ROOT=new")
        # A later value wins, and an empty value is set, not removed.
        lines = _environment(
            [
                ("THREEMOJO_PORTABILITY_FAIL", "it's"),
                ("THREEMOJO_PORTABILITY_FAIL", ""),
            ]
        )
        assert_equal(len(lines), 2)
        assert_equal(lines[1], "THREEMOJO_PORTABILITY_FAIL=")
    finally:
        for index in range(len(names)):
            if saved[index] == "\x00":
                _ = unsetenv(names[index])
            else:
                _ = setenv(names[index], saved[index])


def test_a_controlled_error_requires_both_nonzero_exit_and_diagnostic() raises:
    for item in [
        (1, "missing /root/file", True),
        (0, "missing /root/file", False),
        (1, "different failure", False),
        (128 + 6, "missing /root/file", False),
    ]:
        if item[2]:
            check_child(item[0], item[1], False, error=String("/root/file"))
        else:
            with assert_raises(contains="Expected controlled error"):
                check_child(item[0], item[1], False, error=String("/root/file"))
    with assert_raises(contains="timed out"):
        check_child(1, "missing /root/file", True, error=String("/root/file"))


def test_success_requires_a_marker_and_the_original_five_second_limit() raises:
    for item in [(0, ""), (1, "PORTABILITY PASS")]:
        with assert_raises(contains="Child failed"):
            check_child(item[0], item[1], False)
    check_child(0, "PORTABILITY PASS", False)
    assert_equal(SECONDS, 5)
    with assert_raises(contains="timed out after 5 seconds"):
        check_child(0, "PORTABILITY PASS", True)


def test_suite_output_cannot_hide_missing_or_slow_results() raises:
    var valid = String(
        "Running 1 tests for suite.mojo\nPASS [ 1.0 ] test_a\n"
        "Summary [ 1.0 ] 1 tests run: 1 passed , 0 failed , 0 skipped"
    )
    check_child(0, valid, False, suite=True)
    for output in [
        String(""),
        valid.replace("PASS [ 1.0 ]", "PASS [ 5001.0 ]"),
    ]:
        with assert_raises(contains="Invalid or slow suite"):
            check_child(0, output, False, suite=True)
    with assert_raises(contains="Child failed"):
        check_child(1, valid, False, suite=True)


def test_paths_follow_pathlib() raises:
    assert_equal(normal_path("/a//b/./c/"), "/a/b/c")
    assert_equal(normal_path(""), ".")
    assert_equal(parent_path("/tmp/x/root/"), "/tmp/x")
    assert_equal(parent_path("/x"), "/")
    assert_equal(parent_path("x"), ".")
    assert_equal(relative_path("/a/b/c", "/a/d/e"), "../../b/c")
    assert_equal(relative_path("/a/b", "/a/b"), ".")
    assert_equal(relative_path("/a/b/c", "/a/b"), "c")
    assert_equal(which("/abs/mojo"), "/abs/mojo")
    assert_equal(which("sh").endswith("/sh"), True)
    assert_equal(
        which("threemojo-no-such-command"), "threemojo-no-such-command"
    )
    assert_equal(absolute_path("/nonexistent//a/./b"), "/nonexistent/a/b")
    assert_equal(absolute_path("/nonexistent/../x/./mojo"), "/x/mojo")
    assert_equal(absolute_path("/.."), "/")
    assert_equal(
        absolute_path("threemojo-missing"), realpath(".") + "/threemojo-missing"
    )


def test_the_command_line_matches_argparse() raises:
    var help = parse_portability(["--help"])
    assert_equal(help.status, -1)
    assert_true(
        help.message.startswith(
            "usage: check_portability.mojo [-h] [--mojo MOJO]\n\nCheck native"
        )
    )
    var given = parse_portability(["--mojo", "/x/mojo"])
    assert_equal(given.status, 0)
    assert_equal(given.value("--mojo", ""), "/x/mojo")
    var bad = parse_portability(["extra"])
    assert_equal(bad.status, 2)
    assert_equal(
        bad.message,
        (
            "usage: check_portability.mojo [-h] [--mojo MOJO]\n"
            "check_portability.mojo: error: unrecognized arguments: extra\n"
        ),
    )


def _script(tree: Tree, name: String, body: String) raises -> String:
    """Write an executable shell script and return its path."""
    tree.write(name, "#!/bin/sh\n" + body)
    _ = run_program(["chmod", "+x", tree.root + "/" + name], 10)
    return tree.root + "/" + name


def test_a_background_child_reports_its_status_and_output() raises:
    var tree = Tree()
    var program = _script(
        tree,
        "child",
        (
            'pwd -P\necho "[$THREEMOJO_PORTABILITY_CONTENTS]"\n'
            'while [ ! -e "$THREEMOJO_PORTABILITY_RELEASE" ]; do sleep 0.01;'
            " done\nexit 3\n"
        ),
    )
    var child = Background(
        program,
        [
            ("THREEMOJO_PORTABILITY_CONTENTS", "a b"),
            ("THREEMOJO_PORTABILITY_RELEASE", tree.root + "/release"),
        ],
        "/",
    )
    assert_false(child.poll())
    tree.write("release", "")
    var ended = child.communicate(Float64(SECONDS))
    assert_equal(ended[0], 3)
    assert_equal(ended[1], "/\n[a b]\n")
    child.close()
    # A child that does not end is stopped.
    var stuck = Background(
        _script(tree, "stuck", "exec sleep 30\n"), List[Setting](), "/"
    )
    with assert_raises(contains="timed out"):
        _ = stuck.communicate(0.2)
    stuck.kill()
    assert_equal(stuck.communicate(Float64(SECONDS))[0], 128 + 9)
    stuck.close()
    tree.close()


def test_a_probe_that_never_fails_is_caught() raises:
    # The stand-in compiler builds a probe that always passes, so the first
    # missing-root case, which expects a controlled error, must fail.
    var tree = Tree()
    var mojo = _script(
        tree,
        "fake-mojo",
        (
            'while [ "$#" -gt 0 ]; do\n  if [ "$1" = -o ]; then out=$2; fi\n'
            "  shift\ndone\nprintf '#!/bin/sh\\necho PORTABILITY PASS\\n'"
            ' >"$out"\nchmod +x "$out"\n'
        ),
    )
    with assert_raises(contains="Expected controlled error"):
        check(mojo)
    tree.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
