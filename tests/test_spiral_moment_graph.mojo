# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stored spiral operation blocks keep their reviewed digests."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._sha256 import sha256_hex
from tools.spiral_moment_graph import selected_block


def _replace_once(text: String, before: String, after: String) raises -> String:
    """Replace the first `before` in `text`.

    Args:
        text: The source text.
        before: The text to find.
        after: The replacement.

    Returns:
        The text with one replacement.

    Raises:
        Error: `before` is absent.
    """
    var at = text.find(before)
    if at < 0:
        raise Error("missing text")
    var head = text[byte=0:at]
    var tail = text[byte = at + before.byte_length() :]
    return String(head) + after + String(tail)


def _digest(text: String, begin: String, end: String) raises -> String:
    """Return the SHA-256 of one normalized block.

    Args:
        text: The module source.
        begin: The start marker.
        end: The end marker.

    Returns:
        The digest of the normalized block.

    Raises:
        Error: The block is refused.
    """
    return sha256_hex(selected_block(text, begin, end).as_bytes())


def test_nine_live_blocks_match_their_pins() raises:
    """Nine live operation blocks match their recorded digests."""
    var lane = Path("extensions/carla/lane_geometry.mojo").read_text()
    var trig = Path("extensions/carla/curve_trig.mojo").read_text()
    var bounds = Path("extensions/carla/curve_bounds.mojo").read_text()
    assert_equal(
        _digest(
            lane,
            "from extensions.carla.curve_trig import (",
            "from std.math import ceil",
        ),
        "80d38ed115e33fe36579962308f4552a785becd13faa4af7285ac731cf289ce6",
    )
    assert_equal(
        _digest(trig, "def _scalar_polynomial[", "def _jet_polynomial["),
        "bf0c064e296966ce80c0f40ae1579aec0cada28bfe06ad89a1e330fe0f13cf61",
    )
    assert_equal(
        _digest(
            trig,
            "@no_inline\ndef _curve_sincos(value: Float64)",
            "def _curve_sin(value: Float64)",
        ),
        "84d4bc9455d01b1e1741ecdf8b310c1a85df5226e1e91fec73b46b21e1b32402",
    )
    assert_equal(
        _digest(
            trig,
            "def _curve_sin(value: Float64)",
            "@no_inline\ndef _curve_atan(",
        ),
        "28620259ae57e84d366848fa2e1d1e33b52ba5f2a820114a8828cebfb098987c",
    )
    assert_equal(
        _digest(trig, "def _sincos_expression[", "def _constant_sincos_jet("),
        "660c00106a75d0b4c17ad87aebc4b7b71d1ab017945b3dc0874b895cc266fdc2",
    )
    assert_equal(
        _digest(
            trig,
            "def _expression_polynomial[",
            "@no_inline\ndef _curve_sincos(",
        ),
        "aacc0792f0e340f1859a6ed4e1d64aa4b35961a53f807f3e4f276857c111c22f",
    )
    assert_equal(
        _digest(
            trig, "def _sincos_branch_expression[", "def _uncertain(value:"
        ),
        "b8a1c365598f4f40a29af377f5189359f200baf1386ec08e8b73650344dd709e",
    )
    assert_equal(
        _digest(bounds, "def _spiral_expression[", "def _sample_index("),
        "e5f42ae7ff2a7aa243e6dbe0ab9c591f600f14479fd5bc4a2955bbaed5c03eaa",
    )
    assert_equal(
        _digest(trig, "def _uncertain_expression[", "def _sincos_jet("),
        "5f6a923bf1eb1903449cb5352e271a2a7fa1a829c322f94df9c99d6a100e3b35",
    )


def test_the_live_scalar_spiral_differs_from_its_pin() raises:
    """Restoring the scalar spiral call matches the recorded digest."""
    var lane = Path("extensions/carla/lane_geometry.mojo").read_text()
    var begin = "def _lane_spiral(geometry: RoadGeometry, d: Float64)"
    var end = "def _lane_geometry_derivative_at("
    var live = _digest(lane, begin, end)
    assert_equal(
        live, "9cd5b0ade7510b903f1a034f041df234d3643470cc16d351ef2bb4cede5901eb"
    )
    assert_true(
        live
        != "ca86527db95b4164d07db2eacb8af98ddad73d56c864666621d3bf3c75f3b1c0"
    )
    var restored = _replace_once(
        lane,
        (
            "return DirectedPoint._from_si(\n        geometry.x + (x +"
            " x_correction),"
        ),
        "return DirectedPoint(\n        geometry.x + (x + x_correction),",
    )
    assert_equal(
        _digest(restored, begin, end),
        "ca86527db95b4164d07db2eacb8af98ddad73d56c864666621d3bf3c75f3b1c0",
    )


def test_a_comment_keeps_the_block_and_an_edit_changes_it() raises:
    """A comment keeps the Horner digest, and an operation edit changes it."""
    var trig = Path("extensions/carla/curve_trig.mojo").read_text()
    var begin = "def _scalar_polynomial["
    var end = "def _jet_polynomial["
    var original = _digest(trig, begin, end)
    var commented = _replace_once(
        trig,
        "result = result * x + coefficients[i]",
        "result = result * x + coefficients[i]  # kept",
    )
    assert_equal(_digest(commented, begin, end), original)
    var edited = _replace_once(
        trig,
        "result = result * x + coefficients[i]",
        "result = result * y + coefficients[i]",
    )
    assert_true(_digest(edited, begin, end) != original)


def test_a_bad_boundary_is_refused() raises:
    """A repeated marker, a missing marker, and a bare decorator are refused."""
    var trig = Path("extensions/carla/curve_trig.mojo").read_text()
    var begin = "def _scalar_polynomial["
    with assert_raises(contains="ambiguous source-block start"):
        _ = selected_block(
            trig + "\n" + begin + "\n", begin, "def _jet_polynomial["
        )
    with assert_raises(contains="ambiguous source-block end"):
        _ = selected_block(trig, begin, "def _absent(")
    with assert_raises(contains="unbound decorator"):
        _ = selected_block(
            trig,
            "def _curve_sincos(value: Float64)",
            "def _curve_sin(value: Float64)",
        )


def main() raises:
    """Run the spiral operation-block tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
