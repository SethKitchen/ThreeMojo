# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The construction-boundary inputs keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.construction_boundary_inputs import construction_boundary_inputs


def _copy(root: String) raises:
    """Copy the reviewed construction-boundary inputs.

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
            root + "/extensions/carla",
            root + "/loaders",
            root + "/math",
            root + "/units",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("extensions/__init__.mojo")
    files.append("extensions/carla/__init__.mojo")
    files.append("extensions/carla/curve_frozen_arc.mojo")
    files.append("extensions/carla/curve_interval.mojo")
    files.append("extensions/carla/curve_minimizer_support.mojo")
    files.append("extensions/carla/curve_sum2.mojo")
    files.append("extensions/carla/curve_trig.mojo")
    files.append("extensions/carla/lane_distance.mojo")
    files.append("extensions/carla/map_search.mojo")
    files.append("extensions/carla/map_validation.mojo")
    files.append("extensions/carla/rtree.mojo")
    files.append("extensions/carla/spiral_grouped_roundoff_proof.mojo")
    files.append("extensions/carla/spiral_moment_proof.mojo")
    files.append("extensions/carla/spiral_moment_table.mojo")
    files.append("extensions/carla/spiral_moment_table_data.mojo")
    files.append("extensions/carla/spiral_roundoff_proof.mojo")
    files.append("extensions/carla/transform.mojo")
    files.append("loaders/__init__.mojo")
    files.append("math/__init__.mojo")
    files.append("math/matrix_determinant.mojo")
    files.append("math/random.mojo")
    files.append("math/remainder.mojo")
    files.append("units/__init__.mojo")
    files.append("units/quantity.mojo")

    for path in files:
        var copied = run_program(["cp", path, root + "/" + path], 10.0)
        if copied.status != 0:
            raise Error(copied.output)


def test_the_live_construction_inputs_hold() raises:
    """The 24 construction-boundary inputs keep their reviewed digests."""
    construction_boundary_inputs(".")
    construction_boundary_inputs("./")
    construction_boundary_inputs("extensions/..")


def test_a_changed_extensions_package_is_refused() raises:
    """A changed extensions package is refused."""
    var root = "/tmp/construction-boundary-extensions"
    _copy(root)
    var path = root + "/extensions/__init__.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains="construction boundary input changed: extensions/__init__.mojo"
    ):
        construction_boundary_inputs(root)


def test_a_changed_quantity_unit_is_refused() raises:
    """A changed quantity unit is refused."""
    var root = "/tmp/construction-boundary-quantity"
    _copy(root)
    var path = root + "/units/quantity.mojo"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(
        contains=(
            "construction boundary input changed: " + "units/quantity.mojo"
        )
    ):
        construction_boundary_inputs(root)


def main() raises:
    """Run the construction-boundary input tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
