# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the C ABI build wrapper with a stand-in compiler.

`examples/capi/build.sh` must not treat an old or partial library as a
successful build, and it must drop the crash-reporter banner.
"""

from std.pathlib import Path
from std.sys import CompilationTarget
from std.testing import TestSuite, assert_equal, assert_true

from tests._tree import Tree
from tools._process import ProcessResult, run_program


def _library() -> String:
    """Return the native library the `core` app builds.

    Returns:
        `libthreemojo_core.so` on Linux, and the dylib name on macOS.
    """
    comptime if CompilationTarget.is_linux():
        return "out/capi/libthreemojo_core.so"
    else:
        return "out/capi/libthreemojo_core.dylib"


def _project() raises -> Tree:
    """Return a tree that holds a copy of the build script.

    Returns:
        The tree.

    Raises:
        Error: If the script cannot be copied.
    """
    var tree = Tree()
    tree.write(
        "examples/capi/build.sh",
        Path("examples/capi/build.sh").read_text(),
    )
    return tree^


def _build(tree: Tree, compiler: String) raises -> ProcessResult:
    """Run `build.sh native` with a stand-in compiler.

    Args:
        tree: The project.
        compiler: The shell body of the stand-in `mojo`.

    Returns:
        The script's status and combined output.

    Raises:
        Error: If the stand-in cannot be started.
    """
    var mojo = tree.root + "/mojo"
    Path(mojo).write_text("#!/bin/sh\n" + compiler)
    _ = run_program(["chmod", "755", mojo], 5)
    return run_program(
        [
            "env",
            "MOJO=" + mojo,
            "APPS=core",
            "sh",
            tree.root + "/examples/capi/build.sh",
            "native",
        ],
        10,
    )


def test_failed_compile_cannot_reuse_an_old_output() raises:
    var tree = _project()
    tree.write(_library(), "old library")
    var result = _build(tree, 'echo "compile failed" >&2\nexit 7\n')
    assert_true(result.status != 0)
    assert_true((result.output + result.errors).find("compile failed") >= 0)
    assert_equal((result.output + result.errors).find("built into"), -1)
    tree.close()


def test_failed_compile_cannot_accept_a_partial_output() raises:
    var tree = _project()
    var result = _build(tree, 'printf partial > "$7"\nexit 7\n')
    assert_true(result.status != 0)
    assert_equal((result.output + result.errors).find("built into"), -1)
    tree.close()


def test_success_keeps_output_and_filters_the_crashpad_banner() raises:
    var tree = _project()
    var result = _build(
        tree,
        'printf library > "$7"\n'
        + 'echo "Crashpad: reporter unavailable" >&2\n'
        + 'echo "compiler diagnostic" >&2\n',
    )
    assert_equal(result.status, 0, result.output + result.errors)
    assert_equal(tree.read(_library()), "library")
    var text = result.output + result.errors
    assert_equal(text.find("Crashpad"), -1)
    assert_true(text.find("compiler diagnostic") >= 0)
    tree.close()


def test_success_with_only_a_crashpad_banner_is_accepted() raises:
    var tree = _project()
    var result = _build(
        tree,
        'printf library > "$7"\n'
        + 'echo "Crashpad: reporter unavailable" >&2\n',
    )
    assert_equal(result.status, 0, result.output + result.errors)
    tree.close()


def test_success_without_an_output_is_refused() raises:
    var tree = _project()
    var result = _build(tree, "exit 0\n")
    assert_true(result.status != 0)
    assert_true((result.output + result.errors).find("mojo did not write") >= 0)
    tree.close()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
