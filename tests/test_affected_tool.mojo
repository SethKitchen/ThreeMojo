# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`tools/affected.mojo` reads the change from git and prints a selection.

Each test makes a git repository in a temporary directory. The reasons for
`ALL` go to standard error only with `--verbose`, so they never change
what the `Makefile` reads.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)

from tests._tree import Tree
from tools._imports import changed_paths, test_imports_removed
from tools.affected import parse_options, select

comptime FILES = [
    ("core/common.mojo", "def common():\n    pass\n"),
    ("core/used.mojo", "from core.common import common\n"),
    ("core/other.mojo", "def other():\n    pass\n"),
    (
        "tests/test_a.mojo",
        "from core.used import common\n\n\ndef main():\n    pass\n",
    ),
    ("tests/test_other.mojo", "from core.other import other\n"),
]


def _repository() raises -> Tree:
    """Return a committed repository with a few modules and suites."""
    var tree = Tree()
    for entry in materialize[FILES]():
        tree.write(entry[0], entry[1])
    tree.commit()
    return tree^


def _arguments(var extra: List[String]) -> List[String]:
    """Return a command line that compares with `HEAD` and names every
    file of the fixture."""
    var arguments: List[String] = ["--base", "HEAD"]
    arguments.extend(extra^)
    for entry in materialize[FILES]():
        arguments.append(entry[0])
    return arguments^


def _run(
    tree: Tree, var extra: List[String]
) raises -> Tuple[String, List[String]]:
    """Return what the tool prints, and its reasons, for the tree."""
    var result = select(tree.root, parse_options(_arguments(extra^)))
    return (result[0], result[1].copy())


def test_options() raises:
    var options = parse_options(
        ["--base=main", "--changed", "--list", "--verbose", "a.mojo"]
    )
    assert_equal(options.base, "main")
    assert_true(options.changed and options.list and options.verbose)
    assert_equal(len(options.files), 1)
    with assert_raises(contains="--base is required"):
        _ = parse_options(["a.mojo"])
    with assert_raises(contains="--base needs a ref"):
        _ = parse_options(["--base"])
    with assert_raises(contains="unknown option: --all"):
        _ = parse_options(["--base", "main", "--all"])


def test_a_library_change_selects_its_users_in_the_given_order() raises:
    var tree = _repository()
    tree.write("core/common.mojo", "def common():\n    return\n")
    var plain = _run(tree, [])
    assert_equal(plain[0], "core/common.mojo core/used.mojo tests/test_a.mojo")
    assert_equal(len(plain[1]), 0)
    assert_equal(_run(tree, ["--changed"])[0], "core/common.mojo")
    assert_equal(_run(tree, ["--list"])[0], "core/common.mojo")
    tree.close()


def test_a_leading_dot_is_removed_and_untracked_sources_count() raises:
    var tree = _repository()
    tree.write("core/new.mojo", "def new():\n    pass\n")
    tree.write("notes.txt", "not a build input\n")
    var options = parse_options(
        ["--base", "HEAD", "--changed", "./core/new.mojo"]
    )
    assert_equal(select(tree.root, options)[0], "core/new.mojo")
    assert_equal(_run(tree, ["--list"])[0], "core/new.mojo")
    tree.close()


def test_no_change_selects_nothing() raises:
    var tree = _repository()
    assert_equal(_run(tree, [])[0], "")
    assert_equal(_run(tree, ["--list"])[0], "")
    tree.close()


def test_every_reason_for_all_is_opt_in() raises:
    var tree = _repository()
    tree.write("Makefile", "all:\n")
    tree.commit()
    tree.write("Makefile", "all: check\n")
    var plain = _run(tree, [])
    var verbose = _run(tree, ["--verbose"])
    assert_equal(plain[0], verbose[0])
    assert_equal(len(plain[1]), 0)
    assert_equal(len(verbose[1]), 1)
    assert_equal(
        verbose[1][0], "a build input has no narrower dependency rule: Makefile"
    )
    assert_equal(_run(tree, ["--list"])[0], "ALL")
    assert_equal(len(plain[0].split(" ")), len(materialize[FILES]()))
    tree.close()


def test_a_removed_test_import_selects_everything() raises:
    var tree = _repository()
    tree.write("tests/test_a.mojo", "def main():\n    pass\n")
    var result = _run(tree, ["--verbose"])
    assert_equal(len(result[0].split(" ")), len(materialize[FILES]()))
    assert_equal(
        result[1][0], "a test or helper removed imports: tests/test_a.mojo"
    )
    assert_equal(_run(tree, ["--changed"])[0], _run(tree, [])[0])
    tree.close()


def test_a_deleted_test_and_an_unknown_base_select_everything() raises:
    var tree = _repository()
    tree.remove("tests/test_other.mojo")
    var deleted = _run(tree, ["--verbose"])
    assert_equal(
        deleted[1][0], "a test or helper was deleted: tests/test_other.mojo"
    )
    var options = parse_options(
        ["--base", "no-such-ref", "--verbose", "core/used.mojo"]
    )
    var unknown = select(tree.root, options)
    assert_equal(unknown[0], "core/used.mojo")
    assert_equal(unknown[1][0], "Git could not establish the changed inputs")
    tree.close()


def test_added_tests_have_no_former_imports() raises:
    var tree = _repository()
    tree.write("tests/test_new.mojo", "from core.other import other\n")
    var changed = changed_paths(tree.root, "HEAD")
    assert_true(Bool(changed))
    var reasons = List[String]()
    assert_true(
        not test_imports_removed(tree.root, changed.value(), "HEAD", reasons)
    )
    var missing = Dict[String, Bool]()
    missing["tests/test_new.mojo"] = False
    assert_true(
        test_imports_removed(tree.root, missing, "no-such-ref", reasons)
    )
    assert_equal(
        reasons[0], "the test import baseline could not be established"
    )
    tree.close()


def test_an_unreadable_changed_test_selects_everything() raises:
    var tree = _repository()
    tree.write("tests/test_a.mojo", "")
    _ = tree.git(["rm", "-q", "--cached", "tests/test_a.mojo"])
    tree.remove("tests/test_a.mojo")
    tree.write("tests/test_a.mojo/inner.txt", "a directory now\n")
    var changed = Dict[String, Bool]()
    changed["tests/test_a.mojo"] = False
    var reasons = List[String]()
    assert_true(test_imports_removed(tree.root, changed, "HEAD", reasons))
    assert_equal(
        reasons[0], "a changed test could not be read: tests/test_a.mojo"
    )
    tree.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
