# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sampled value helpers stay checked."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.sampled_value_helpers import sampled_value_helpers


def _source() raises -> String:
    """Return the live lane-value module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path("extensions/carla/lane_value_bounds.mojo").read_text()


def _refuse(source: String, message: String) raises:
    """Require `source` to fail with `message`.

    Args:
        source: The module under test.
        message: The expected failure text.

    Raises:
        Error: The failure text differs.
    """
    with assert_raises(contains=message):
        sampled_value_helpers(source)


def test_the_live_helpers_stay() raises:
    """Seventeen helpers stay, and three reviewed bodies match."""
    var source = _source()
    sampled_value_helpers(source)
    sampled_value_helpers(
        source.replace(
            "def _uncertain_value(value: _Interval) -> _ValueJet:\n",
            (
                "def _uncertain_value(value: _Interval) -> _ValueJet:\n    #"
                " reviewed\n"
            ),
        )
    )


def test_a_changed_helper_is_refused() raises:
    """An extra statement, a missing helper, or a changed body is refused."""
    var source = _source()
    _refuse(
        source.replace(
            "from math.vector3 import Vector3\n",
            "from math.vector3 import Vector3\nvar unexpected = 1\n",
        ),
        "unexpected top-level execution",
    )
    _refuse(
        source.replace("def _sinc_value(", "def _sinc_other("),
        "missing or extra sampled helper",
    )
    _refuse(
        source.replace(
            "return _uncertain_expression[False](value)",
            "return _uncertain_expression[True](value)",
        ),
        "sampled helper diverged: _uncertain_value",
    )
    _refuse(
        source.replace(
            (
                "return _lane_value_bound_impl[False](road, section, lane, low,"
                " high)"
            ),
            (
                "return _lane_value_bound_impl[True](road, section, lane, low,"
                " high)"
            ),
        ),
        "sampled helper diverged: _sampled_lane_value_bound",
    )
    _refuse(
        source.replace(
            "road.info.geometries[at].geometry.kind == SPIRAL",
            "road.info.geometries[at].geometry.kind == LINE",
        ),
        "sampled helper diverged: _lane_value_bound",
    )
    _refuse(
        "def _uncertain_value():\n    return 0\n  return 1\n",
        "unsupported ideal source syntax",
    )


def main() raises:
    """Run the sampled helper tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
