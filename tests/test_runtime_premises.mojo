# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reviewed runtime premises stay in the live source modules."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._winner_pin_predecessor import restored_winner_pins
from tools._sha256 import sha256_hex


comptime _LANE = "extensions/carla/lane_value_bounds.mojo"
"""The lane-value module whose blend guard is the winner pin."""
comptime _GUARD = "coupled_error >= 0.0"
"""The blend guard kept by that winner pin."""


def _cases(mut files: List[String], mut premises: List[String]):
    """Fill the reviewed runtime premises.

    Args:
        files: The module file names.
        premises: The premise text in each module.
    """
    files.append("curve_interval.mojo")
    premises.append("constant(0.5)")
    files.append("curve_interval.mojo")
    premises.append("result = value *")
    files.append("curve_interval.mojo")
    premises.append("_Interval.point(value.error)")
    files.append("curve_interval.mojo")
    premises.append("UInt64(623)")
    files.append("curve_interval.mojo")
    premises.append("UInt64(1423)")
    files.append("curve_interval.mojo")
    premises.append("not value.value.is_finite()")
    files.append("curve_interval.mojo")
    premises.append("value.value.low > value.value.high")
    files.append("curve_interval.mojo")
    premises.append("value.error < 0.0")
    files.append("curve_interval.mojo")
    premises.append("result = one - two")
    files.append("curve_interval.mojo")
    premises.append("left.low >= right.high * 0.5")
    files.append("curve_interval.mojo")
    premises.append("right.low * 2.0")
    files.append("curve_interval.mojo")
    premises.append("one.error + two.error")
    files.append("curve_interval.mojo")
    premises.append("one.error == 0.0 and two.error == 0.0")
    files.append("curve_interval.mojo")
    premises.append("return result")
    files.append("curve_interval.mojo")
    premises.append("_Interval.point(one), -_Interval.point(two)")
    files.append("curve_interval.mojo")
    premises.append("_Interval.point(abs(two))")
    files.append("curve_interval.mojo")
    premises.append("_Interval.point(rate.error)")
    files.append("curve_interval.mojo")
    premises.append(
        "+ _Interval.point(abs(two)) * _Interval.point(complement_error)"
    )
    files.append("curve_interval.mojo")
    premises.append(
        "+ _Interval.point(first_error)\n        +"
        " _Interval.point(second_error)\n        + _Interval.point(final_error)"
    )
    files.append("curve_interval.mojo")
    premises.append(
        "+ _Interval.point(second_error)\n        +"
        " _Interval.point(final_error)"
    )
    files.append("curve_interval.mojo")
    premises.append("+ _Interval.point(final_error)")
    files.append("curve_interval.mojo")
    premises.append("UInt64(623)")
    files.append("curve_interval.mojo")
    premises.append("rate.error < 0.0")
    files.append("curve_interval.mojo")
    premises.append("not isfinite(rate.error)")
    files.append("curve_interval.mojo")
    premises.append("value.error")
    files.append("curve_interval.mojo")
    premises.append("value.value,")
    files.append("curve_interval.mojo")
    premises.append("comptime if not Self.derivatives:")
    files.append("lane_value_bounds.mojo")
    premises.append("magnitude * _expression_polynomial")
    files.append("lane_value_bounds.mojo")
    premises.append("domain.low < 0.0")
    files.append("lane_value_bounds.mojo")
    premises.append("dx.low > 0.0")
    files.append("lane_value_bounds.mojo")
    premises.append("- _ValueJet.constant(shift)")
    files.append("lane_value_bounds.mojo")
    premises.append("_Interval.whole()")
    files.append("lane_value_bounds.mojo")
    premises.append("domain.low >= geometry.length")
    files.append("lane_value_bounds.mojo")
    premises.append("constant(one)")
    files.append("lane_value_bounds.mojo")
    premises.append("geometry.samples[index + 1]")
    files.append("lane_value_bounds.mojo")
    premises.append("_stored_blend_error(rate, one, two)")
    files.append("lane_value_bounds.mojo")
    premises.append("coupled_error >= 0.0")
    files.append("lane_value_bounds.mojo")
    premises.append("domain.high <= _QUARTER_PI")
    files.append("lane_value_bounds.mojo")
    premises.append("_SIN_COEFFICIENTS")
    files.append("lane_value_bounds.mojo")
    premises.append("if not isfinite(radius):")
    files.append("lane_value_bounds.mojo")
    premises.append("- _ValueJet.constant(Float64(translation.x))")
    files.append("lane_value_bounds.mojo")
    premises.append("chord * trig[1]")
    files.append("lane_value_bounds.mojo")
    premises.append("turn * _ValueJet.constant(0.5)")
    files.append("lane_value_bounds.mojo")
    premises.append("abs(heading) > _PHASE_LIMIT")
    files.append("lane_value_bounds.mojo")
    premises.append("unknown, unknown, 0.0")
    files.append("lane_value_bounds.mojo")
    premises.append("_lane_value_bound_impl[False]")
    files.append("lane_value_bounds.mojo")
    premises.append("_lane_value_bound_impl[True]")
    files.append("lane_value_bounds.mojo")
    premises.append("_lane_jet(road, section, lane, low, high)")
    files.append("lane_value_bounds.mojo")
    premises.append("at >= 0")
    files.append("lane_value_bounds.mojo")
    premises.append("comptime if all_geometry:")
    files.append("lane_value_bounds.mojo")
    premises.append("all_geometry: Bool")
    files.append("lane_value_bounds.mojo")
    premises.append("def _sinc_value(")
    files.append("lane_value_bounds.mojo")
    premises.append("    _stored_half,")
    files.append("lane_value_bounds.mojo")
    premises.append("def _uncertain_value(")
    files.append("lane_value_bounds.mojo")
    premises.append("var domain = value.rounded_value().absolute()")
    files.append("spiral_moment_table.mojo")
    premises.append("pieces > 64")
    files.append("spiral_roundoff_proof.mojo")
    premises.append("pieces > 64")
    files.append("spiral_roundoff_proof.mojo")
    premises.append("count > 320")
    files.append("spiral_domain_proof.mojo")
    premises.append("high > root_high")
    files.append("spiral_domain_proof.mojo")
    premises.append("domain.low <= 0.0")
    files.append("spiral_domain_proof.mojo")
    premises.append("counts[1] - counts[0] > 1")
    files.append("spiral_moment_proof.mojo")
    premises.append("floor(selection.low) == 0.0 and")
    files.append("spiral_domain_proof.mojo")
    premises.append("- _Jet.constant(Float64(translation.x))")
    files.append("spiral_domain_proof.mojo")
    premises.append("+ _Jet.constant(Float64(translation.y))")
    files.append("spiral_domain_proof.mojo")
    premises.append("x.error = inf[DType.float64]()")
    files.append("spiral_domain_proof.mojo")
    premises.append("y.error = inf[DType.float64]()")
    files.append("spiral_domain_proof.mojo")
    premises.append("translation.x != 0.0 or translation.y != 0.0")
    files.append("curve_bounds.mojo")
    premises.append("result.error = inf[DType.float64]()")
    files.append("curve_bounds.mojo")
    premises.append("point, Vector3(0, 0, 0), scale")
    files.append("curve_bounds.mojo")
    premises.append("counts[0] != counts[1]")
    files.append("curve_bounds.mojo")
    premises.append("_finite_spiral_ideal_branch(")
    files.append("curve_bounds.mojo")
    premises.append("if reused:")
    files.append("lane_refinement.mojo")
    premises.append("taylor.low - domain.error")
    files.append("spiral_moment_table.mojo")
    premises.append("var work = 22")
    files.append("curve_bounds.mojo")
    premises.append("1024 * branches")
    files.append("lane_refinement.mojo")
    premises.append("terms += work")
    files.append("lane_refinement.mojo")
    premises.append("terms > max_terms - work")
    files.append("spiral_domain_proof.mojo")
    premises.append("_stored_half(rate) * d")
    files.append("spiral_domain_proof.mojo")
    premises.append("_Jet.constant(0.5) * rate * d * d")
    files.append("spiral_moment_proof.mojo")
    premises.append("_stored_half(rate) * d")
    files.append("spiral_moment_proof.mojo")
    premises.append("_Jet.constant(0.5) * rate * d * d")
    files.append("spiral_moment_table.mojo")
    premises.append("_stored_half(rate) * d")
    files.append("spiral_moment_table.mojo")
    premises.append("_Jet.constant(0.5) * rate * d * d")
    files.append("spiral_moment_proof.mojo")
    premises.append("_Jet.constant(0.5) * rate * t")
    files.append("spiral_domain_proof.mojo")
    premises.append("geometry.curvature_end - geometry.curvature_start")
    files.append("spiral_moment_proof.mojo")
    premises.append("geometry.curvature_end - geometry.curvature_start")
    files.append("spiral_moment_table.mojo")
    premises.append("geometry.curvature_end - geometry.curvature_start")


def _lane_winner() raises -> String:
    """Return the lane-value winner pin.

    Returns:
        The restored lane-value module.

    Raises:
        Error: The winner pin changed.
    """
    var paths = List[String]()
    var texts = List[String]()
    restored_winner_pins(paths, texts)
    for index in range(len(paths)):
        if paths[index] == _LANE:
            return texts[index]
    raise Error(
        "winner/sign source contract: unreviewed canonical dependency: " + _LANE
    )


def test_runtime_premises_stay_in_their_sources() raises:
    """Every reviewed runtime premise still occurs, and an edit changes its digest.
    """
    var files = List[String]()
    var premises = List[String]()
    _cases(files, premises)
    assert_equal(len(files), 87)
    var lane = _lane_winner()
    assert_true(lane.find(_GUARD) >= 0)
    for index in range(len(files)):
        var path = "extensions/carla/" + files[index]
        var text = Path(path).read_text()
        if (
            files[index] == "lane_value_bounds.mojo"
            and premises[index] == _GUARD
        ):
            text = lane
        var at = text.find(premises[index])
        assert_true(at >= 0)
        var head = String(text[byte=:at])
        var tail = String(text[byte = at + premises[index].byte_length() :])
        var changed = head + "False" + tail
        assert_true(
            sha256_hex(changed.as_bytes()) != sha256_hex(text.as_bytes())
        )


def main() raises:
    """Run the runtime premise tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
