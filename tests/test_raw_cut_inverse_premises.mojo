# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The raw-cut inverse premises stay fixed."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools.raw_cut_inverse_premises import raw_cut_inverse_premises


def _copy(root: String) raises:
    """Copy the raw-cut premise inputs.

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
            root + "/tests",
        ],
        10.0,
    )
    if made.status != 0:
        raise Error(made.output)
    var files = List[String]()
    files.append("tools/carla_lane_oracle/raw-cut-inverse-migration.json")
    files.append(
        "tools/carla_lane_oracle/curve-support-dispatch-migration.json"
    )
    files.append("extensions/carla/curve_sample_dispatch.mojo")
    files.append("extensions/carla/curve_sum2.mojo")
    files.append("tests/test_carla_raw_cut_successor.mojo")
    files.append("tests/test_carla_support_dispatch_successor.mojo")
    var index = 0
    while index < len(files):
        var copied = run_program(
            ["cp", files[index], root + "/" + files[index]], 10.0
        )
        if copied.status != 0:
            raise Error(copied.output)
        index += 1


def test_the_raw_cut_inverse_premises_hold() raises:
    """The live premises match the raw-cut record."""
    raw_cut_inverse_premises(".")
    raw_cut_inverse_premises("./")


def test_a_changed_raw_cut_body_is_refused() raises:
    """A changed dispatch body is refused."""
    var root = "/tmp/raw-cut-inverse-premises-body"
    _copy(root)
    var dispatch = root + "/extensions/carla/curve_sample_dispatch.mojo"
    Path(dispatch).write_text(
        Path(dispatch)
        .read_text()
        .replace(
            "if _sample_dispatch_predicate(origin, length, local, start):",
            "if _sample_dispatch_predicate(origin, length, local, origin):",
        )
    )
    with assert_raises(
        contains="raw cut inverse contract: raw inverse operation graph changed"
    ):
        raw_cut_inverse_premises(root)


def test_a_bare_road_info_import_is_refused() raises:
    """A bare road-info import is refused."""
    var root = "/tmp/raw-cut-inverse-premises-alias"
    _copy(root)
    var dispatch = root + "/extensions/carla/curve_sample_dispatch.mojo"
    Path(dispatch).write_text(
        Path(dispatch)
        .read_text()
        .replace(
            (
                "from extensions.carla.road_info import _info_index_si as"
                " info_index\n"
            ),
            "from extensions.carla.road_info import info_index\n",
        )
    )
    with assert_raises(
        contains="raw cut inverse contract: raw inverse operation graph changed"
    ):
        raw_cut_inverse_premises(root)


def main() raises:
    """Run the raw-cut inverse premise tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
