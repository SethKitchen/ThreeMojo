# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The PR776 bound inputs keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.pr776_bound_inputs import pr776_bound_inputs


def _copy(root: String) raises:
    """Copy the reviewed PR776 bound inputs.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(
        [
            "mkdir",
            "-p",
            root + "/tools/carla_lane_oracle",
            root + "/tests/compile_fail",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("tools/carla_lane_oracle/test_main_rebase_successor.py")
    files.append("tests/compile_fail/a_gpu_info_is_not_a_bare_int.mojo")
    files.append("tests/compile_fail/a_gpu_part_is_not_a_bare_int.mojo")
    files.append("tests/compile_fail/a_splat_info_is_not_a_bare_int.mojo")
    files.append("tests/compile_fail/a_splat_part_is_not_a_bare_int.mojo")

    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_pr776_bound_inputs_hold() raises:
    """The 5 PR776 bound inputs keep their reviewed digests."""
    pr776_bound_inputs(".")
    pr776_bound_inputs("./")
    pr776_bound_inputs("tests/..")


def test_a_changed_rebase_successor_is_refused() raises:
    """A changed rebase successor is refused."""
    var root = "/tmp/pr776-bound-rebase"
    _copy(root)
    var path = root + "/tools/carla_lane_oracle/test_main_rebase_successor.py"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "PR776 bound input changed:"
            " tools/carla_lane_oracle/test_main_rebase_successor.py"
        )
    ):
        pr776_bound_inputs(root)


def test_a_changed_splat_part_is_refused() raises:
    """A changed splat part is refused."""
    var root = "/tmp/pr776-bound-splat-part"
    _copy(root)
    var path = root + "/tests/compile_fail/a_splat_part_is_not_a_bare_int.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "PR776 bound input changed: "
            + "tests/compile_fail/a_splat_part_is_not_a_bare_int.mojo"
        )
    ):
        pr776_bound_inputs(root)


def main() raises:
    """Run the PR776 bound-input tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
