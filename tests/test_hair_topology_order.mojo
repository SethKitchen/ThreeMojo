# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Validation-order controls for retained hair topology comparisons."""

from core.assets import Assets
from core.geometry_store import GeometryId
from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from extensions.humanoid.skeleton.head.hair.shading import HairLight, HairLook
from extensions.humanoid.skeleton.head.hair.simulation import HairSimulation
from extensions.humanoid.skeleton.head.hair.strands import HairStrands
from math.vector3 import Vector3
from std.math import nan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _groom() -> HairGroom:
    """Return one segment with all shading fields present."""
    var groom = HairGroom()
    groom.add(
        [Vector3(0, 0, 0), Vector3(0, 1, 0)],
        [Vector3(0, 0, 1), Vector3(0, 0, 1)],
        [Float32(0.25), 0.25],
        1,
    )
    return groom^


def test_simulation_preserves_validation_precedence_and_atomicity() raises:
    for failure in range(4):
        var groom = _groom()
        var motion = HairSimulation(groom)
        motion.now[0].x = 2
        var expected = String("not the one")
        if failure == 0:
            groom.starts.append(2)
            _ = groom.normals.pop()
        elif failure == 1:
            groom.starts[1] = 1
            _ = groom.normals.pop()
            expected = "groom's shading fields"
        elif failure == 2:
            groom.starts[1] = 1
            _ = motion.initial_depths.pop()
            expected = "rest shading fields"
        else:
            groom.starts[1] = 1
            motion.now[1].x = nan[DType.float32]()
        var points = groom.points.copy()
        var normals = groom.normals.copy()
        var depths = groom.depths.copy()
        with assert_raises(contains=expected):
            motion.write(groom)
        assert_true(groom.points == points)
        assert_true(groom.normals == normals)
        assert_equal(groom.depths, depths)


def test_strands_refuse_topology_before_reading_geometry() raises:
    for change in range(2):
        var assets = Assets()
        var hair = HairStrands(
            _groom(), GeometryId(99), HairLook(Vector3(0.3, 0.2, 0.1))
        )
        if change == 0:
            hair.groom.starts.append(2)
        else:
            hair.groom.starts[1] = 1
        with assert_raises(contains="topology cannot change"):
            hair.shade(
                assets, List[HairLight](), Vector3(0, 0, 1), Vector3(0, 0, 0)
            )
        assert_equal(assets.geometries.count(), 0)
        assert_equal(hair._buffer.value(0), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
