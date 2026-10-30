# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for bands: a belt drawn taut round the body."""

from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from extensions.attire.band import BAND_HEIGHT, BAND_ROWS, belt_band
from extensions.attire.mesh_ops import merge
from extensions.attire.skirt import SKIRT_SIDES, skirt_scale
from extensions.humanoid.rig.joints import HIPS, RIGHT_FOREARM
from std.math import sqrt
from std.testing import TestSuite, assert_equal, assert_true
from tests._attire_fixtures import empty_mesh, standing_rig, tube


def _shell() raises -> BufferGeometry:
    """Return a trunk 15 cm round from y = 0.5 down to -0.3, and an arm
    hanging beside it."""
    var trunk = tube(0, 0, 0.15, 0.5, -0.3, HIPS, 16, 24)
    var arm = tube(0.3, 0, 0.04, 0.4, -0.2, RIGHT_FOREARM, 8, 12)
    return merge(trunk, arm)


def test_a_band_is_level_and_taut_round_the_trunk() raises:
    var rig = standing_rig()
    var piece = tube(0, 0, 0.15, 0.15, 0.05, HIPS, 2, 24)
    var band = belt_band(_shell(), piece, rig, 0.002)
    # Each row round, inside and out, and the top and the bottom edges.
    assert_equal(
        band.triangle_count(),
        2 * 2 * (BAND_ROWS - 1) * SKIRT_SIDES + 2 * 2 * SKIRT_SIDES,
    )
    assert_true(band.has_attribute(String(NORMAL)))
    var half = BAND_HEIGHT * skirt_scale(rig) / 2
    ref placed = band.attribute_view(String(POSITION))
    var widest = Float32(0)
    for v in range(placed.count()):
        var p = placed.vector3(v)
        # Level at its top and its bottom, about the piece's middle.
        assert_true(abs(p.y - 0.1) <= half + 1e-5)
        widest = max(widest, sqrt(p.x * p.x + p.z * p.z))
    # Round the trunk alone: the arm beside it is left out.
    assert_true(widest <= 0.1501 and widest > 0.14)


def test_a_band_that_cannot_be_drawn_is_left_as_it_is() raises:
    var rig = standing_rig()
    # Nothing covered.
    assert_equal(
        belt_band(_shell(), empty_mesh(), rig, 0.002).triangle_count(), 0
    )
    # A band above the shell crosses nothing: the piece as it is.
    var high = tube(0, 0, 0.15, 2.1, 2.0, HIPS, 2, 24)
    assert_equal(
        belt_band(_shell(), high, rig, 0.002).triangle_count(),
        high.triangle_count(),
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
