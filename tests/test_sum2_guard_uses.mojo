# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Sum2 helper use sites stay inside the reviewed callers."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_guard_uses import sum2_guard_uses


def _copy(root: String) raises:
    """Copy the caller modules.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var cleared = run_program(["rm", "-rf", root], 10.0)
    if cleared.status != 0:
        raise Error(cleared.output)
    var made = run_program(["mkdir", "-p", root + "/extensions/carla"], 10.0)
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("extensions/carla/lane_geometry.mojo")
    files.append("extensions/carla/curve_bounds.mojo")
    files.append("extensions/carla/lane_refinement.mojo")
    files.append("extensions/carla/map.mojo")
    files.append("extensions/carla/map_builder.mojo")
    files.append("extensions/carla/spiral_domain_proof.mojo")
    files.append("extensions/carla/spiral_moment_proof.mojo")
    files.append("extensions/carla/spiral_moment_table.mojo")
    files.append("extensions/carla/spiral_roundoff_proof.mojo")
    files.append("extensions/carla/curve_objective_model.mojo")
    files.append("extensions/carla/curve_minimizer_support.mojo")
    files.append("extensions/carla/curve_sample_dispatch.mojo")
    files.append("extensions/carla/spiral_grouped_lane.mojo")
    files.append("extensions/carla/spiral_grouped_roundoff_proof.mojo")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_sum2_helper_uses_stay_reviewed() raises:
    """Each protected helper use stays inside a reviewed caller."""
    sum2_guard_uses(".")


def test_an_unreviewed_sum2_helper_use_is_refused() raises:
    """A protected helper use outside a reviewed caller is refused."""
    var root = "/tmp/sum2-guard-uses"
    _copy(root)
    var lane = root + "/extensions/carla/lane_geometry.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "def _lane_geometry_pos_at(",
            "var marker = _sum2_update\ndef _lane_geometry_pos_at(",
        )
    )
    with assert_raises(
        contains=(
            "unreviewed Sum2 helper binding/use: lane_geometry:_sum2_update"
        )
    ):
        sum2_guard_uses(root)


def main() raises:
    """Run the Sum2 helper use tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
