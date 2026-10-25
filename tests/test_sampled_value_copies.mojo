# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sampled value copies stay checked against their jet sources."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools.sampled_value_copies import (
    sampled_constant_heading,
    sampled_value_copies,
)


def _text(path: String) raises -> String:
    """Return one module.

    Args:
        path: The repository path.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return Path(path).read_text()


def _bounds() raises -> String:
    """Return the live curve-bounds module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return _text("extensions/carla/curve_bounds.mojo")


def _trig() raises -> String:
    """Return the live curve-trig module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return _text("extensions/carla/curve_trig.mojo")


def _value() raises -> String:
    """Return the live lane-value module.

    Returns:
        The module text.

    Raises:
        Error: The file is unreadable.
    """
    return _text("extensions/carla/lane_value_bounds.mojo")


def test_the_live_copies_match() raises:
    """Ten value helpers match their renamed jet sources."""
    var value = _value()
    sampled_value_copies(_bounds(), _trig(), value)
    sampled_value_copies(
        _bounds(),
        _trig(),
        value.replace(
            "def _atan_value(value: _ValueJet) -> _ValueJet:\n",
            "def _atan_value(value: _ValueJet) -> _ValueJet:\n    # reviewed\n",
        ),
    )


def test_a_changed_copy_is_refused() raises:
    """A missing helper, a changed copy, or a blend edit is refused."""
    var bounds = _bounds()
    var trig = _trig()
    var value = _value()
    with assert_raises(contains="missing or ambiguous function: _atan_value"):
        sampled_value_copies(
            bounds,
            trig,
            value.replace("def _atan_value(", "def _atan_other("),
        )
    with assert_raises(contains="sampled helper diverged: _atan_value"):
        sampled_value_copies(
            bounds,
            trig,
            value.replace("domain.low < 0.0", "domain.low < 1.0"),
        )
    with assert_raises(contains="derivative intersection shape changed"):
        sampled_value_copies(
            bounds.replace(
                (
                    "    result.first = _intersect_ideal_bounds(result.first,"
                    " ideal.first)\n"
                ),
                "",
            ),
            trig,
            value,
        )
    with assert_raises(contains="sampled helper diverged: _sample_blend_value"):
        sampled_value_copies(
            bounds,
            trig,
            value.replace(
                (
                    "result.value = _intersect_ideal_bounds(result.value,"
                    " ideal.value)"
                ),
                (
                    "result.value = _intersect_ideal_bounds(result.value,"
                    " ideal.error)"
                ),
            ),
        )
    with assert_raises(contains="unsupported ideal source syntax"):
        sampled_value_copies(
            "def _polynomial_jet():\n    return 0\n  return 1\n",
            trig,
            value,
        )


def test_the_constant_heading_projection_holds() raises:
    """The value heading helper replaces zero derivatives with unknown."""
    var trig = _trig()
    var value = _value()
    sampled_constant_heading(trig, value)
    sampled_constant_heading(
        trig.replace(
            (
                "def _constant_sincos_jet(heading: Float64) -> Tuple[_Jet,"
                " _Jet]:\n"
            ),
            (
                "def _constant_sincos_jet(heading: Float64) -> Tuple[_Jet,"
                " _Jet]:\n    # reviewed\n"
            ),
        ),
        value,
    )


def test_a_changed_constant_heading_is_refused() raises:
    """A changed layout, constructor, projection, or value helper is refused."""
    var trig = _trig()
    var value = _value()
    with assert_raises(contains="constant heading layout changed"):
        sampled_constant_heading(
            trig.replace("_PHASE_LIMIT", "_HALF_PI"),
            value,
        )
    with assert_raises(
        contains="constant heading derivative constructor changed"
    ):
        sampled_constant_heading(
            trig.replace(
                "var zero = _Interval.point(0.0)",
                "var zero = _Interval.point(1.0)",
            ),
            value,
        )
    with assert_raises(contains="constant heading field projection changed"):
        sampled_constant_heading(
            trig.replace(
                "_Jet(result[0].rounded_value(), zero, zero, 0.0)",
                "_Jet(result[0].rounded_value(), zero, result[0], 0.0)",
            ),
            value,
        )
    with assert_raises(
        contains="sampled helper diverged: _constant_sincos_value"
    ):
        sampled_constant_heading(
            trig,
            value.replace(
                "var unknown = _Interval.whole()",
                "var unknown = _Interval.point(0.0)",
            ),
        )


def main() raises:
    """Run the sampled copy tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
