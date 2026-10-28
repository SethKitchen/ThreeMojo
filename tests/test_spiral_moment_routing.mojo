# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Stored spiral source routing keeps its reviewed projection."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

from tools._sha256 import sha256_hex
from tools._spiral_moment_routing import routing_json


def _digest(text: String, strip: Bool) raises -> String:
    """Return the SHA-256 of one routing projection.

    Args:
        text: The module source.
        strip: True when the try-only parameter is removed.

    Returns:
        The digest of the compact JSON projection.

    Raises:
        Error: The routing is refused.
    """
    return sha256_hex(routing_json(text, strip).as_bytes())


def test_trig_and_scalar_routing_match_their_pins() raises:
    """The trig module and the scalar module match their routing pins."""
    var trig = Path("extensions/carla/curve_trig.mojo").read_text()
    var lane = Path("extensions/carla/lane_geometry.mojo").read_text()
    assert_equal(
        _digest(trig, False),
        "9a7f80b4c4f66408d061d6977e8a667287a7f4ca773a1dd172b8e4b264469797",
    )
    assert_equal(
        _digest(lane, False),
        "2e43f74e47cf1f80323d2c75fd5b7439ec9e995032196d0abcd2babe95aab1ab",
    )
    var projected = routing_json(trig, False)
    assert_true(projected.find('["STORED_WORDS","_PHASE_LIMIT"]') >= 0)
    assert_true(projected.find('["STORED_WORDS","_SIN_COEFFICIENTS"]') >= 0)
    assert_true(projected.find("1048576.0") < 0)
    assert_true(projected.find("1.5707963267948966") >= 0)


def test_a_comment_keeps_scalar_routing() raises:
    """A comment keeps the scalar routing digest, and a statement changes it."""
    var lane = Path("extensions/carla/lane_geometry.mojo").read_text()
    var original = _digest(lane, False)
    var commented = lane.replace(
        "from std.math import ceil, isfinite",
        "from std.math import ceil, isfinite  # kept",
    )
    assert_equal(_digest(commented, False), original)
    var extended = lane + "\nvar unreviewed = 1\n"
    assert_true(_digest(extended, False) != original)


def test_live_caller_and_geometry_routing_differ() raises:
    """The live caller and geometry routing differ from their pins."""
    var bounds = Path("extensions/carla/curve_bounds.mojo").read_text()
    var geometry = Path("extensions/carla/geometry.mojo").read_text()
    var caller = _digest(bounds, True)
    assert_equal(
        caller,
        "35602c89866898721b2e138f1a3460046878844e505ba7c2657d64608e8447b7",
    )
    assert_true(
        caller
        != "51d9a0e9e9b0423cc038bdfd7aa747b7487fe9f471ccebe55526e02fa5d9dac6"
    )
    var stored = _digest(geometry, False)
    assert_equal(
        stored,
        "1b760bd22edd0bb379aa91ffe70dbaadead7ae81d692e2f76733e3c88ee299c1",
    )
    assert_true(
        stored
        != "c0d0f383bd23463c57c458b62dd511099ffb91addf07aa64edbb6e9fb18d2cf3"
    )
    var projected = routing_json(geometry, False)
    assert_true(projected.find('["STORED_WORDS","_GL_NODES"]') >= 0)
    assert_true(projected.find('["STORED_WORDS","_GL_WEIGHTS"]') >= 0)
    assert_true(projected.find("0.9061798459386640") < 0)


def test_a_missing_try_only_parameter_is_refused() raises:
    """A caller without the reviewed parameter is refused."""
    var source = (
        "def _lane_jet_model_proof(value: Float64):\n    return value\n"
    )
    with assert_raises(contains="try-only routing parameter"):
        _ = routing_json(source, True)
    with assert_raises(contains="missing try-only routing declaration"):
        _ = routing_json("def other():\n    return 1\n", True)


def main() raises:
    """Run the spiral routing tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
