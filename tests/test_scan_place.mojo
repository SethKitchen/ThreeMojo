# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.place`: a scan's frame as a scene node's
transform.

A scan point must stand in the scene where the frame puts it in the
building, with the scene's x east, y up and z south. That is checked for
every pair of up and north axes, with a scale, an origin and a heading, and
through a node of a scene.
"""

from core.object3d import Object3D
from core.scene import Scene
from extensions.scan.frame import (
    SCALE_ASSUMED,
    ScanAxis,
    ScanFrame,
    supersplat_frame,
)
from extensions.scan.place import scan_placement
from generators.utils import Vec3d
from math.vector3 import Vector3
from std.testing import TestSuite, assert_almost_equal, assert_raises
from units.si import Angle64, DEGREE64, Length64, METER


def _points() -> List[Vec3d]:
    """Return scan points in all directions."""
    return [
        Vec3d(0, 0, 0),
        Vec3d(1, 0, 0),
        Vec3d(0, 2, 0),
        Vec3d(0, 0, 3),
        Vec3d(-4, 5, -6),
        Vec3d(7.5, -2.25, 0.5),
    ]


def _close(found: Vector3, want: Vec3d) raises:
    """Assert a scene point is the building point in the scene's axes."""
    assert_almost_equal(Float64(found.x), want.x, atol=2e-4)
    assert_almost_equal(Float64(found.y), want.z, atol=2e-4)
    assert_almost_equal(Float64(found.z), -want.y, atol=2e-4)


def test_every_frame_places_a_scan_where_the_building_has_it() raises:
    """For all thirty frames the scan point is at the frame's building point,
    turned to the scene's axes."""
    for up in range(6):
        for north in range(6):
            if up // 2 == north // 2:
                continue
            var frame = ScanFrame(
                ScanAxis(up),
                ScanAxis(north),
                Length64(2.5, METER),
                SCALE_ASSUMED,
                Angle64(30, DEGREE64),
                Vec3d(1, -2, 3),
            )
            var placement = scan_placement(frame)
            for point in _points():
                _close(placement.to_scene(point), frame.to_building(point))


def test_a_node_stands_the_scan_in_the_scene() raises:
    """The node's world matrix puts a scan point where `to_scene` does."""
    var frame = supersplat_frame()
    frame.unit = Length64(0.5, METER)
    frame.origin = Vec3d(2, 3, 4)
    frame.heading = Angle64(-20, DEGREE64)
    var placement = scan_placement(frame)
    var scene = Scene()
    var node = scene.add(Object3D())
    placement.apply(scene.node(node))
    scene.update()
    for point in _points():
        var scan = Vector3(Float32(point.x), Float32(point.y), Float32(point.z))
        var placed = scene.world_matrix(node).transform_point(scan)
        _close(placed, frame.to_building(point))
        var asked = placement.to_scene(point)
        assert_almost_equal(placed.x, asked.x, atol=2e-4)
        assert_almost_equal(placed.y, asked.y, atol=2e-4)
        assert_almost_equal(placed.z, asked.z, atol=2e-4)


def test_a_frame_that_is_refused_has_no_placement() raises:
    """The frame's own check runs first."""
    var frame = supersplat_frame()
    frame.unit = Length64(0, METER)
    with assert_raises(contains="the unit must be positive"):
        _ = scan_placement(frame)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
