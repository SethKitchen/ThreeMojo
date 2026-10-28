# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The `make` stamp key changes with every build input and nothing else."""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_not_equal,
    assert_raises,
)

from tests._tree import Tree
from std.pathlib import Path

from tools._process import run_program
from tools._sha256 import sha256_hex
from tools.cache_key import (
    cache_key,
    input_paths,
    installed_packages,
    memo_digests,
    run,
)


def _tree() raises -> Tree:
    """Return a tree with inputs, and files that are not inputs."""
    var tree = Tree()
    for path in [
        "Makefile",
        "core/a.mojo",
        "tools/b.py",
        "c.json",
        "d.toml",
        "e.yaml",
        "f.yml",
        "g.mjs",
        "h.c",
        "h.h",
        "assets/i.bin",
        "assets/deep/j",
        "docs/k.mojo",
        ".github/workflows/l.yml",
        "deep/Makefile",
        # Not inputs: the kinds, the skipped names at any depth, and the
        # coverage copy.
        "README.md",
        "notes.txt",
        ".mojo",
        ".git/m.mojo",
        ".venv/n.py",
        ".cache/o.mojo",
        "out/p.mojo",
        "core/out/q.mojo",
        "node_modules/r.mjs",
        "tools/__pycache__/s.py",
        ".agents/t.json",
        ".claude/u.json",
        "coverage/build/v.mojo",
    ]:
        tree.write(path, path)
    tree.write("coverage/w.mojo", "")
    return tree^


def test_input_paths_are_the_build_inputs_sorted() raises:
    var tree = _tree()
    _ = run_program(
        ["ln", "-s", tree.root + "/core", tree.root + "/linked"], 10
    )
    assert_equal(
        " ".join(input_paths(tree.root)),
        (
            ".github/workflows/l.yml Makefile assets/deep/j assets/i.bin c.json"
            " core/a.mojo coverage/w.mojo d.toml deep/Makefile docs/k.mojo"
            " e.yaml f.yml g.mjs h.c h.h tools/b.py"
        ),
    )
    tree.close()


def test_the_key_changes_with_inputs_names_and_settings_only() raises:
    var tree = _tree()
    var before = cache_key(tree.root, ["s"])
    assert_equal(before.byte_length(), 20)
    assert_equal(before, cache_key(tree.root, ["s"]))
    tree.write("README.md", "changed")
    tree.write("out/p.mojo", "changed")
    tree.write(".cache/generated.mojo", "ignored")
    tree.write("coverage/build/generated.mojo", "ignored")
    tree.write("node_modules/generated.mojo", "ignored")
    tree.write(".venv/generated.mojo", "ignored")
    assert_equal(before, cache_key(tree.root, ["s"]))
    tree.write("coverage/instrument.mojo", "top-level-only parser")
    var instrument = cache_key(tree.root, ["covered:module.mojo"])
    tree.write("coverage/instrument.mojo", "grouped leaf parser")
    var grouped = cache_key(tree.root, ["covered:module.mojo"])
    assert_not_equal(instrument, grouped)
    tree.write("coverage/scanner.mojo", "quote-aware scanner")
    assert_not_equal(grouped, cache_key(tree.root, ["covered:module.mojo"]))
    assert_not_equal(before, cache_key(tree.root, ["t"]))
    # A moved boundary between two settings changes the key.
    assert_not_equal(
        cache_key(tree.root, ["ab", "c"]), cache_key(tree.root, ["a", "bc"])
    )
    for path in ["core/a.mojo", "assets/deep/j", "Makefile", "h.h"]:
        tree.write(path, "changed")
        var after = cache_key(tree.root, ["s"])
        assert_not_equal(before, after, path)
        before = after
    tree.write("core/new.mojo", "")
    var added = cache_key(tree.root, ["s"])
    assert_not_equal(before, added)
    _ = run_program(
        ["mv", tree.root + "/assets/i.bin", tree.root + "/assets/renamed.bin"],
        10,
    )
    assert_not_equal(added, cache_key(tree.root, ["s"]))
    tree.close()


def test_memo_digests_follow_each_file() raises:
    """A memo digest is the file's SHA-256 before and after a change."""
    var tree = Tree()
    tree.write(".cache/keep", "")
    tree.write("one.bin", "first")
    tree.write("two.bin", "second")
    var paths: List[String] = [tree.root + "/one.bin", tree.root + "/two.bin"]
    var memo = ".cache/test-files"
    var first = memo_digests(tree.root, memo, paths)
    assert_equal(first[0], sha256_hex("first".as_bytes()))
    assert_equal(first[1], sha256_hex("second".as_bytes()))
    assert_equal(len(first), 2)
    var again = memo_digests(tree.root, memo, paths)
    assert_equal(again[0], first[0])
    assert_equal(again[1], first[1])
    tree.write("one.bin", "a longer first")
    var changed = memo_digests(tree.root, memo, paths)
    assert_equal(changed[0], sha256_hex("a longer first".as_bytes()))
    assert_equal(changed[1], first[1])
    assert_equal(
        Path(tree.root + "/" + memo).exists(),
        True,
    )
    tree.close()


def test_installed_packages_name_each_version() raises:
    var tree = Tree()
    assert_equal(installed_packages(tree.root), "")
    tree.write(
        ".venv/lib/python3.12/site-packages/mojo-1.1.0.dist-info/METADATA", ""
    )
    tree.write(
        ".venv/lib/python3.12/site-packages/max-26.6.0.dist-info/METADATA", ""
    )
    tree.write(".venv/lib/python3.12/site-packages/max/__init__.py", "")
    tree.write(".venv/lib/notes.txt", "")
    assert_equal(
        installed_packages(tree.root),
        "python3.12/max-26.6.0.dist-info\npython3.12/mojo-1.1.0.dist-info",
    )
    var before = run([String("--root"), tree.root])
    tree.write(
        ".venv/lib/python3.12/site-packages/max-26.7.0.dist-info/METADATA", ""
    )
    assert_not_equal(before, run(["--root=" + tree.root]))
    tree.close()


def test_command_line() raises:
    var tree = _tree()
    assert_equal(
        run(["--root", tree.root, "--setting=a", "--setting", "b"]),
        cache_key(tree.root, ["a", "b", ""]),
    )
    with assert_raises(contains="--setting needs a value"):
        _ = run(["--setting"])
    with assert_raises(contains="unknown argument: x"):
        _ = run(["x"])
    tree.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
