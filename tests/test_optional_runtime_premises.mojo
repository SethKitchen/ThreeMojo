# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reviewed optional-runtime premises stay in the live source modules."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tools._sha256 import sha256_hex


def _cases(
    mut modules: List[String],
    mut premises: List[String],
    mut edits: List[String],
):
    """Fill the reviewed optional-runtime premises.

    Args:
        modules: The module names, without the `.mojo` suffix.
        premises: The premise text in each module.
        edits: The reviewed replacement for each premise.
    """
    modules.append("curve_objective_model")
    premises.append("low < model.low")
    edits.append("low < model.low - 1.0")
    modules.append("curve_objective_model")
    premises.append("high > model.high")
    edits.append("high > model.high + 1.0")
    modules.append("curve_objective_model")
    premises.append("bitcast[DType.uint64](scale) != model.scale_word")
    edits.append("False")
    modules.append("curve_objective_model")
    premises.append("model.domain.second, model.domain.error")
    edits.append("model.domain.second, model.center.error")
    modules.append("curve_objective_model")
    premises.append("model.domain.second, model.domain.error")
    edits.append("model.center.second, model.domain.error")
    modules.append("curve_objective_model")
    premises.append("or not _model_interval(domain.second)")
    edits.append("or False")
    modules.append("curve_objective_model")
    premises.append("or domain.error < 0.0")
    edits.append("or domain.error > 0.0")
    modules.append("curve_objective_model")
    premises.append("or center_s > high")
    edits.append("or center_s > high + 1.0")
    modules.append("curve_objective_model")
    premises.append("_Interval.point(0.5)")
    edits.append("_Interval.point(0.25)")
    modules.append("curve_minimizer_support")
    premises.append("_Interval.point(2.0) * _Interval.point(domain.error)")
    edits.append("_Interval.point(2.0) * _Interval.point(center.error)")
    modules.append("curve_minimizer_support")
    premises.append("or best < low")
    edits.append("or best < low - 1.0")
    modules.append("curve_sample_dispatch")
    premises.append(") > local")
    edits.append(") >= local")
    modules.append("curve_sample_dispatch")
    premises.append("station - origin")
    edits.append("station + origin")
    modules.append("curve_sample_dispatch")
    premises.append("word += UInt64(1)")
    edits.append("word += UInt64(2)")
    modules.append("curve_sample_dispatch")
    premises.append("min(max(before - record.s, 0.0), geometry.length)")
    edits.append("min(max(station - record.s, 0.0), geometry.length)")
    modules.append("curve_sample_dispatch")
    premises.append("or after_index != threshold_at")
    edits.append("or False")
    modules.append("curve_sample_dispatch")
    premises.append("nodes > max_nodes - node_reserve")
    edits.append("nodes > max_nodes - 1")
    modules.append("curve_sample_dispatch")
    premises.append("term_reserve > max_terms - terms")
    edits.append("extra > max_terms - terms")
    modules.append("curve_sample_dispatch")
    premises.append("var extra = 8 * count")
    edits.append("var extra = 6 * count")
    modules.append("curve_sample_dispatch")
    premises.append("count > 2")
    edits.append("count > 3")
    modules.append("spiral_grouped_roundoff_proof")
    premises.append(
        "_sum2_error_checked(magnitude.high, inherited.high, count)"
    )
    edits.append("_sum2_error(magnitude.high, inherited.high, count)")
    modules.append("spiral_grouped_roundoff_proof")
    premises.append("x_inherited, 5 * pieces, geometry.x")
    edits.append("x_inherited, pieces, geometry.x")
    modules.append("spiral_grouped_roundoff_proof")
    premises.append("d.value, _Interval.whole(), _Interval.whole(), d.error")
    edits.append("d.value, _Interval.whole(), _Interval.whole(), 0.0")
    modules.append("spiral_grouped_roundoff_proof")
    premises.append("1 if weight == 2 else 2")
    edits.append("1 if weight == 2 else 1")
    modules.append("spiral_grouped_roundoff_proof")
    premises.append("3 * min(4, pieces)")
    edits.append("2 * min(4, pieces)")
    modules.append("spiral_grouped_lane")
    premises.append("max_terms - terms < 24")
    edits.append("max_terms - terms < 12")
    modules.append("spiral_grouped_lane")
    premises.append("extra += _spiral_grouped_roundoff_work(counts[1])")
    edits.append("extra += 0")
    modules.append("spiral_grouped_lane")
    premises.append("counts[1] - counts[0] > 1")
    edits.append("counts[1] - counts[0] > 2")
    modules.append("spiral_grouped_lane")
    premises.append("terms += extra")
    edits.append("terms += 0")
    modules.append("spiral_grouped_lane")
    premises.append("require_reuse=True")
    edits.append("require_reuse=False")
    modules.append("spiral_grouped_roundoff_proof")
    premises.append("work + fallback_work > max_terms - terms")
    edits.append("work > max_terms - terms")
    modules.append("lane_refinement")
    premises.append("var best = certificate.s")
    edits.append("var best = low")
    modules.append("lane_refinement")
    premises.append("var best_point = certificate.point.copy()")
    edits.append("var best_point = query_point.copy()")
    modules.append("curve_objective_model")
    premises.append("(remaining - center_work) // 8")
    edits.append("remaining // 8")
    modules.append("lane_refinement")
    premises.append("bitcast[DType.uint64](split_at) - UInt64(1)")
    edits.append("bitcast[DType.uint64](split_at) - UInt64(2)")
    modules.append("map")
    premises.append("fixed += 16")
    edits.append("fixed += 15")
    modules.append("curve_objective_model")
    premises.append("nodes < 0")
    edits.append("nodes < -1")
    modules.append("curve_objective_model")
    premises.append("nodes > max_nodes")
    edits.append("nodes > max_nodes + 1")
    modules.append("curve_objective_model")
    premises.append("terms < 0")
    edits.append("terms < -1")
    modules.append("curve_objective_model")
    premises.append("terms > max_terms")
    edits.append("terms > max_terms + 1")
    modules.append("curve_objective_model")
    premises.append("reference_work < 0")
    edits.append("reference_work < -1")
    modules.append("curve_objective_model")
    premises.append("center_work < 0")
    edits.append("center_work < -1")
    modules.append("curve_objective_model")
    premises.append("max_nodes - nodes >= 4")
    edits.append("max_nodes - nodes >= 3")
    modules.append("curve_objective_model")
    premises.append("// 8")
    edits.append("// 7")
    modules.append("curve_objective_model")
    premises.append("center_work <= remaining")
    edits.append("True")
    modules.append("curve_objective_model")
    premises.append("reference_work <= (remaining - center_work) // 8")
    edits.append("8 * reference_work + center_work <= remaining")
    modules.append("lane_refinement")
    premises.append("var grouped: Optional[Tuple[_Jet, _Jet, _Jet]] = None")
    edits.append(
        "var grouped: Optional[Tuple[_Jet, _Jet, _Jet]] = previous_grouped"
    )
    modules.append("curve_sample_dispatch")
    premises.append("3 * count + 2")
    edits.append("3 * count + 1")
    modules.append("curve_sample_dispatch")
    premises.append("16 * count")
    edits.append("16 * count - 1")
    modules.append("curve_objective_model")
    premises.append("nodes < max_nodes")
    edits.append("nodes <= max_nodes")
    modules.append("curve_objective_model")
    premises.append("nodes >= 0")
    edits.append("nodes >= -1")
    modules.append("lane_refinement")
    premises.append("var sampled_checked = False")
    edits.append("var cached_model = None\n    var sampled_checked = False")
    modules.append("lane_refinement")
    premises.append("var best = certificate.s")
    edits.append(
        "var hidden = _restrict_objective_model(previous, low, high, 1.0)\n   "
        " var best = certificate.s"
    )
    modules.append("lane_refinement")
    premises.append("var point_domain: Tuple[_Jet, _Jet, _Jet]")
    edits.append(
        "if previous_lower > best_upper:\n                continue\n           "
        " var point_domain: Tuple[_Jet, _Jet, _Jet]"
    )
    modules.append("lane_refinement")
    premises.append("var work = _reference_work(road, lo, hi)")
    edits.append("var work = _reference_work(road, low, high)")
    modules.append("map")
    premises.append("fixed += 14")
    edits.append("fixed += 0")
    modules.append("curve_objective_model")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("curve_sample_dispatch")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("spiral_grouped_lane")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("spiral_grouped_roundoff_proof")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("lane_refinement")
    premises.append("if max_nodes - nodes >= 2:")
    edits.append("if max_nodes - nodes >= 1:")
    modules.append("lane_refinement")
    premises.append(
        "var delta = _Interval(cell.low, cell.high) - _Interval.point(center_s)"
    )
    edits.append(
        "var hidden = _try_objective_model(cell.low, cell.high, center_s,"
        " policy.scale, domain, center)\n        var delta ="
        " _Interval(cell.low, cell.high) - _Interval.point(center_s)"
    )
    modules.append("lane_refinement")
    premises.append("terms += whole_work")
    edits.append("terms += 0")
    modules.append("lane_refinement")
    premises.append("if max_nodes - nodes >= 2:")
    edits.append("if True:")


def _replace_first(text: String, before: String, after: String) -> String:
    """Replace the first `before`.

    Args:
        text: The source.
        before: The premise.
        after: The replacement.

    Returns:
        The source with that premise replaced.
    """
    var at = text.find(before)
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + before.byte_length() :])
    return head + after + tail


def test_optional_runtime_premises_stay_in_the_live_modules() raises:
    """Every live optional-runtime premise still occurs, and its edit changes the digest.
    """
    var modules = List[String]()
    var premises = List[String]()
    var edits = List[String]()
    _cases(modules, premises, edits)
    assert_equal(len(modules), 64)
    for index in range(len(modules)):
        var path = "extensions/carla/" + modules[index] + ".mojo"
        var text = Path(path).read_text()
        assert_true(text.find(premises[index]) >= 0)
        var changed = _replace_first(text, premises[index], edits[index])
        assert_true(
            sha256_hex(changed.as_bytes()) != sha256_hex(text.as_bytes())
        )


def main() raises:
    """Run the optional-runtime premise tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
