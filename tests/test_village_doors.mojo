# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's doors: each swings open while someone stands near it,
and shut after."""

from core.object3d import Object3D
from core.scene import Scene
from extensions.village.doors import (
    HEADROOM,
    OPEN_REACH,
    SWING_SPEED,
    WIDE,
    Doors,
)
from extensions.village.house_view import Hinge
from extensions.village.interior import Doorway
from math.vector3 import Vector3
from std.math import atan2
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import SECOND, Duration


def _door() -> Doorway:
    """Return a door a meter wide in a wall along x, its hinge at the
    origin, swinging toward -z, on a floor at 0.5 meters."""
    return Doorway(0, 0, 1, 0, 0, -1, 1, 2.1, 0.5, True)


def test_a_door_opens_for_someone_near_and_shuts_after() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    var doors = Doors()
    doors.add(Hinge(node, 0.25, -1, 0), _door())
    assert_equal(len(doors.angles), 1)
    assert_almost_equal(doors.ways[0].middle().x, 0.5, atol=1e-6)
    assert_almost_equal(doors.ways[0].middle().y, 0.5, atol=1e-6)
    var near: List[Vector3] = [Vector3(0.5, 0.5, 1)]
    var step = Duration(0.2, SECOND)
    doors.update(scene, near, step)
    assert_almost_equal(doors.angles[0], SWING_SPEED * 0.2, atol=1e-5)
    # It opens no further than wide.
    for _ in range(20):
        doors.update(scene, near, step)
    assert_almost_equal(doors.angles[0], WIDE, atol=1e-5)
    # The hinge turns from shut by the sense times the angle.
    var q = scene.node(node).quaternion
    var turned = 2 * atan2(q.y, q.w)
    assert_almost_equal(turned, Float32(0.25) - WIDE, atol=1e-4)
    # Someone far away, or on another storey, does not hold it open.
    var away: List[Vector3] = [
        Vector3(0.5, 0.5, OPEN_REACH + 1),
        Vector3(0.5, 0.5 + HEADROOM + 0.5, 0),
    ]
    doors.update(scene, away, step)
    assert_almost_equal(doors.angles[0], WIDE - SWING_SPEED * 0.2, atol=1e-5)
    for _ in range(20):
        doors.update(scene, List[Vector3](), step)
    assert_almost_equal(doors.angles[0], 0, atol=1e-6)


def test_a_negative_time_is_refused() raises:
    var scene = Scene()
    var doors = Doors()
    with assert_raises(contains="negative"):
        doors.update(scene, List[Vector3](), Duration(-1.0, SECOND))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
