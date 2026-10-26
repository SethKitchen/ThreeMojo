# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The seed-count premises keep their score-era token digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.seed_count_premises import seed_count_premises


def _copy(root: String) raises:
    """Copy the premise modules and the count record.

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
            root + "/tools/carla_lane_oracle",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("extensions/carla/curve_bounds.mojo")
    files.append("extensions/carla/curve_interval.mojo")
    files.append("extensions/carla/curve_minimizer_support.mojo")
    files.append("extensions/carla/curve_sum2.mojo")
    files.append("extensions/carla/curve_trig.mojo")
    files.append("extensions/carla/map.mojo")
    files.append("extensions/carla/map_search.mojo")
    files.append("extensions/carla/road_info.mojo")
    files.append("tools/carla_lane_oracle/seed-count-successor.json")
    # Copied in this process: one `cp` for each file took most of the
    # five seconds a test may run.
    for path in files:
        Path(root + "/" + path).write_bytes(Path(path).read_bytes())


def test_the_live_seed_count_premises_hold() raises:
    """The forty-five declarations keep their score-era digests."""
    seed_count_premises(".")
    seed_count_premises("./")
    seed_count_premises("extensions/..")


def test_a_changed_premise_is_refused() raises:
    """A changed Map premise is refused."""
    var root = "/tmp/seed-count-premises-map"
    _copy(root)
    var path = root + "/extensions/carla/map.mojo"
    Path(path).write_text(
        Path(path)
        .read_text()
        .replace("value.is_point(0.0)", "value.is_point(1.0)")
    )
    with assert_raises(
        contains=(
            "live theorem premise changed: extensions/carla/map.mojo:"
            + "_seed_exact_interval"
        )
    ):
        seed_count_premises(root)


def test_a_changed_record_is_refused() raises:
    """A changed count record is refused."""
    var root = "/tmp/seed-count-premises-record"
    _copy(root)
    var path = root + "/tools/carla_lane_oracle/seed-count-successor.json"
    Path(path).write_text(Path(path).read_text() + "\n")
    with assert_raises(contains="immutable successor record changed"):
        seed_count_premises(root)


def main() raises:
    """Run the seed-count premise tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
