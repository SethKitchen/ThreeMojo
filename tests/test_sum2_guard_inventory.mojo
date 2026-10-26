# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Sum2 protected-helper inventory stays checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._sum2_guard_inventory import sum2_guard_inventory


def _copy(root: String) raises:
    """Copy the pin and the protected modules.

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
    files.append("extensions/carla/curve_bounds.mojo")
    files.append("extensions/carla/curve_frozen_arc.mojo")
    files.append("extensions/carla/curve_minimizer_support.mojo")
    files.append("extensions/carla/curve_objective_model.mojo")
    files.append("extensions/carla/curve_sample_dispatch.mojo")
    files.append("extensions/carla/curve_sum2.mojo")
    files.append("extensions/carla/junction_bounds.mojo")
    files.append("extensions/carla/lane_box_cover.mojo")
    files.append("extensions/carla/lane_geometry.mojo")
    files.append("extensions/carla/lane_refinement.mojo")
    files.append("extensions/carla/lane_value_bounds.mojo")
    files.append("extensions/carla/map.mojo")
    files.append("extensions/carla/map_builder.mojo")
    files.append("extensions/carla/spiral_domain_proof.mojo")
    files.append("extensions/carla/spiral_grouped_lane.mojo")
    files.append("extensions/carla/spiral_grouped_roundoff_proof.mojo")
    files.append("extensions/carla/spiral_moment_proof.mojo")
    files.append("extensions/carla/spiral_moment_table.mojo")
    files.append("extensions/carla/spiral_roundoff_proof.mojo")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_sum2_protected_inventory_holds() raises:
    """The protected file set and the live digests stay fixed."""
    sum2_guard_inventory(".")


def test_a_changed_sum2_protected_inventory_is_refused() raises:
    """A changed live digest or a new protected use is refused."""
    var changed = "/tmp/sum2-guard-inventory-digest"
    _copy(changed)
    var helper = changed + "/extensions/carla/curve_sum2.mojo"
    Path(helper).write_text(
        Path(helper)
        .read_text()
        .replace(
            "from extensions.carla.curve_interval import _Interval",
            (
                "var marker = 1\nfrom extensions.carla.curve_interval import"
                " _Interval"
            ),
        )
    )
    with assert_raises(
        contains="global protected-helper use/import inventory changed"
    ):
        sum2_guard_inventory(changed)
    var added = "/tmp/sum2-guard-inventory-added"
    _copy(added)
    Path(added + "/extensions/carla/extra_guard.mojo").write_text(
        "def use():\n    var total = _sum2_update\n"
    )
    with assert_raises(
        contains="global protected-helper use/import inventory changed"
    ):
        sum2_guard_inventory(added)


def main() raises:
    """Run the Sum2 protected-inventory tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
