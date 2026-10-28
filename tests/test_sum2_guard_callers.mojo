# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live Sum2 guard callers stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_guard_callers import sum2_guard_callers


def _copy(root: String) raises:
    """Copy the pin and the caller modules.

    Args:
        root: The temporary repository.

    Raises:
        Error: A file cannot be copied.
    """
    var made = run_program(
        [
            "mkdir",
            "-p",
            root + "/tools/carla_lane_oracle",
            root + "/extensions/carla",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("tools/carla_lane_oracle/sum2-guard-pins.json")
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


def test_the_live_sum2_guard_callers_hold() raises:
    """The pinned caller functions and live routing stay in place."""
    sum2_guard_callers(".")


def test_a_changed_sum2_guard_caller_is_refused() raises:
    """A changed caller function or a changed routing is refused."""
    var body = "/tmp/sum2-guard-callers-body"
    _copy(body)
    var support = body + "/extensions/carla/curve_minimizer_support.mojo"
    Path(support).write_text(
        Path(support)
        .read_text()
        .replace(
            "var twice_error = _Interval.point(2.0)",
            "var twice_error = _Interval.point(3.0)",
        )
    )
    with assert_raises(
        contains=(
            "Sum2 complete guarded caller changed: "
            "curve_minimizer_support:_minimizer_support"
        )
    ):
        sum2_guard_callers(body)
    var routing = "/tmp/sum2-guard-callers-routing"
    _copy(routing)
    var lane = routing + "/extensions/carla/lane_geometry.mojo"
    Path(lane).write_text(
        Path(lane)
        .read_text()
        .replace(
            "from extensions.carla.geometry import (",
            "var marker = 1\nfrom extensions.carla.geometry import (",
        )
    )
    with assert_raises(
        contains="Sum2 guard import/declaration routing changed: lane_geometry"
    ):
        sum2_guard_callers(routing)


def main() raises:
    """Run the Sum2 guard caller tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
