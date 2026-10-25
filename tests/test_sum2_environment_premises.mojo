# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reviewed Sum2 environment guards stay in the live source modules."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tools._sha256 import sha256_hex


def _cases(
    mut modules: List[String],
    mut premises: List[String],
    mut edits: List[String],
):
    """Fill the reviewed Sum2 environment premises.

    Args:
        modules: The module names, without the `.mojo` suffix.
        premises: The premise text in each module.
        edits: The reviewed replacement for each premise.
    """
    modules.append("curve_sum2")
    premises.append("one_slot.unsafe_load[volatile=True]()")
    edits.append("one_slot.unsafe_load[volatile=False]()")
    modules.append("curve_sum2")
    premises.append("half_slot.unsafe_load[volatile=True]()")
    edits.append("half_slot.unsafe_load[volatile=False]()")
    modules.append("curve_sum2")
    premises.append("tiny_slot.unsafe_load[volatile=True]()")
    edits.append("tiny_slot.unsafe_load[volatile=False]()")
    modules.append("curve_sum2")
    premises.append("one_slot[unsafe_offset=0]")
    edits.append("one_slot[unsafe_offset=1]")
    modules.append("curve_sum2")
    premises.append("    var one_slot")
    edits.append("    return True\n    var one_slot")
    modules.append("curve_sum2")
    premises.append("    var one_slot")
    edits.append("    return False\n    var one_slot")
    modules.append("curve_sum2")
    premises.append("0x3CA0000000000000")
    edits.append("0x3C90000000000000")
    modules.append("curve_sum2")
    premises.append("0x3FF0000000000000")
    edits.append("0x3FF0000000000001")
    modules.append("curve_sum2")
    premises.append("tiny_slot[unsafe_offset=0] = UInt64(1)")
    edits.append("tiny_slot[unsafe_offset=0] = UInt64(0)")
    modules.append("curve_sum2")
    premises.append("one_word + UInt64(1)")
    edits.append("one_word + UInt64(2)")
    modules.append("curve_sum2")
    premises.append("UInt64(0x3FF0000000000002)")
    edits.append("UInt64(0x3FF0000000000001)")
    modules.append("curve_sum2")
    premises.append("or bitcast[\n        DType.uint64\n    ](odd[0])")
    edits.append("and bitcast[\n        DType.uint64\n    ](odd[0])")
    modules.append("curve_sum2")
    premises.append("first[0], first[1], -one")
    edits.append("first[0], 0.0, -one")
    modules.append("curve_sum2")
    premises.append("last[0] + last[1]")
    edits.append("last[0]")
    modules.append("curve_sum2")
    premises.append("bitcast[DType.uint64](last[0] + last[1]) == UInt64(1)")
    edits.append("(last[0] + last[1]) == tiny")
    modules.append("curve_sum2")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("curve_sum2")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if _sum2_supported_environment():")
    modules.append("curve_sum2")
    premises.append("return inf[DType.float64]()")
    edits.append("return 0.0")
    modules.append("curve_sum2")
    premises.append("(magnitude, inherited, count)")
    edits.append("(inherited, magnitude, count)")
    modules.append("curve_sum2")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("curve_sum2")
    premises.append("raise Error(")
    edits.append("return Error(")
    modules.append("lane_geometry")
    premises.append("    _require_sum2_environment()\n")
    edits.append("")
    modules.append("curve_bounds")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("curve_bounds")
    premises.append("            inf[DType.float64](),")
    edits.append("            0.0,")
    modules.append("curve_bounds")
    premises.append("_sum2_error_checked(\n        x_magnitude.high")
    edits.append("_sum2_error(\n        x_magnitude.high")
    modules.append("curve_bounds")
    premises.append("if proof and not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("curve_bounds")
    premises.append("if proof and not _sum2_supported_environment():")
    edits.append("if proof and _sum2_supported_environment():")
    modules.append("curve_bounds")
    premises.append("return _unknown_point()")
    edits.append(
        "return (_Jet.constant(0.0), _Jet.constant(0.0), _Jet.constant(0.0))"
    )
    modules.append("spiral_domain_proof")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("spiral_domain_proof")
    premises.append("x.error = proof.first_x_error")
    edits.append("x.error = 0.0")
    modules.append("spiral_moment_proof")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("spiral_moment_proof")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("spiral_moment_table")
    premises.append("if not _sum2_supported_environment():")
    edits.append("if False:")
    modules.append("lane_refinement")
    premises.append("    _require_sum2_environment()\n")
    edits.append("")
    modules.append("lane_refinement")
    premises.append("    _require_sum2_environment()\n")
    edits.append("")
    modules.append("lane_refinement")
    premises.append("if not axis and _RoundedBox.bounds(low, high).known:")
    edits.append("if not axis:")
    modules.append("lane_refinement")
    premises.append("if not axis and _RoundedBox.bounds(low, high).known:")
    edits.append("if not axis and not _RoundedBox.bounds(low, high).known:")
    modules.append("lane_refinement")
    premises.append("if not axis and _RoundedBox.bounds(low, high).known:")
    edits.append("if not axis or _RoundedBox.bounds(low, high).known:")
    modules.append("lane_refinement")
    premises.append("_RoundedBox.bounds(low, high).known")
    edits.append("_RoundedBox.bounds(low, low).known")
    modules.append("lane_refinement")
    premises.append("_RoundedBox.bounds(low, high).known")
    edits.append("_RoundedBox.bounds(low, high).high")
    modules.append("lane_refinement")
    premises.append("    _require_sum2_environment()\n")
    edits.append("")
    modules.append("map")
    premises.append("        _require_sum2_environment()\n")
    edits.append("")
    modules.append("map")
    premises.append("        _require_sum2_environment()\n")
    edits.append("")
    modules.append("map_builder")
    premises.append("        _require_sum2_environment()\n")
    edits.append("")


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


def test_environment_premises_stay_in_the_live_modules() raises:
    """Every reviewed environment premise still occurs, and its edit changes the digest.
    """
    var modules = List[String]()
    var premises = List[String]()
    var edits = List[String]()
    _cases(modules, premises, edits)
    assert_equal(len(modules), 44)
    for index in range(len(modules)):
        var path = "extensions/carla/" + modules[index] + ".mojo"
        var text = Path(path).read_text()
        assert_true(text.find(premises[index]) >= 0)
        var changed = _replace_first(text, premises[index], edits[index])
        assert_true(
            sha256_hex(changed.as_bytes()) != sha256_hex(text.as_bytes())
        )


def test_guard_aliases_and_a_method_decorator_change_the_digest() raises:
    """A removed barrier, an alias, a redirected import, or a method decorator changes the digest.
    """
    var curve = Path("extensions/carla/curve_sum2.mojo").read_text()
    var bare = _replace_first(
        curve,
        "@no_inline\ndef _sum2_supported_environment",
        "def _sum2_supported_environment",
    )
    assert_true(sha256_hex(bare.as_bytes()) != sha256_hex(curve.as_bytes()))
    var aliased = curve + "\n_sum2_supported_environment = cached_true\n"
    assert_true(sha256_hex(aliased.as_bytes()) != sha256_hex(curve.as_bytes()))
    var lane = Path("extensions/carla/lane_refinement.mojo").read_text()
    var redirected = _replace_first(
        lane,
        "from extensions.carla.curve_rounded_arc import (",
        "from unexpected.curve_rounded_arc import (",
    )
    assert_true(
        sha256_hex(redirected.as_bytes()) != sha256_hex(lane.as_bytes())
    )
    var builder = Path("extensions/carla/map_builder.mojo").read_text()
    var decorated = _replace_first(
        builder, "    def build(\n", "    @no_inline\n    def build(\n"
    )
    assert_true(
        sha256_hex(decorated.as_bytes()) != sha256_hex(builder.as_bytes())
    )


def main() raises:
    """Run the Sum2 environment premise tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
