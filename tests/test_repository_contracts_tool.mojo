# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `tools.check_repository_contracts` and CI workflow CPU smoke."""

from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_true
from tests._tree import Tree
from tools.check_repository_contracts import (
    check_file_docstrings,
    check_repository,
)
from tools.domain_scope import select_domain

# Quote the CI workflow path so `ci_scope` runs this CPU smoke and contract
# suite whenever `.github/workflows/ci.yml` is edited on a pull request.
comptime WORKFLOW = ".github/workflows/ci.yml"


def test_current_repository_satisfies_all_contracts() raises:
    var problems = check_repository(".")
    assert_equal(len(problems), 0, "\n".join(problems))
    # Exercise core vector math so workflow-only PRs also compile and run
    # library code in `test-cpu`.
    var v = Vector3(3.0, 4.0, 0.0)
    assert_equal(v.length(), Float32(5.0))
    assert_true(String(WORKFLOW).endswith("ci.yml"))
    var warp_suites = select_domain(
        ".",
        "warp",
        ["tests/test_warp_solver.mojo", "tests/test_zip.mojo"],
    )
    assert_equal(len(warp_suites), 1)
    assert_equal(warp_suites[0], "tests/test_warp_solver.mojo")


def test_missing_docstrings_missing_compile_fail_and_bad_imports_fail() raises:
    var bad_doc = check_file_docstrings(
        "math/sample.mojo",
        "struct PublicBox:\n    var x: Int\n\ndef undocumented():\n    pass\n",
    )
    assert_equal(len(bad_doc), 2)

    var tree = Tree()
    tree.write(
        "math/bad.mojo",
        '"""Module."""\n\nfrom extensions.carla.world import World\n\n'
        + "struct NewKind:\n"
        + '    """A kind."""\n\n'
        + "    var value: Int\n\n"
        + "    def is_valid(self) -> Bool:\n"
        + '        """Check validity."""\n'
        + "        return self.value == 0\n",
    )
    tree.write(
        "extensions/visual/leak.mojo",
        '"""Leak."""\n\nfrom extensions.carla.world import World\n',
    )
    tree.write("tools/compile_fail_expectations.json", "{}\n")
    var problems = check_repository(tree.root)
    tree.close()
    var joined = "\n".join(problems)
    assert_true(joined.find("has no tests/compile_fail/ fixture") >= 0, joined)
    assert_true(
        joined.find("core module must not import extensions.carla") >= 0, joined
    )
    assert_true(
        joined.find("forbidden cross-extension import visual -> carla") >= 0,
        joined,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
