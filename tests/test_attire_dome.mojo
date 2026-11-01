# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for domed pauldrons: each shoulder closed in one smooth plate."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from extensions.attire.dome import (
    DOME_STAND,
    DOME_TRIM,
    dome_shoulders,
    shoulder_points,
)
from extensions.attire.mesh_ops import COVER, merge
from extensions.humanoid.rig.joints import (
    CHEST,
    LEFT_UPPER_ARM,
    RIGHT_UPPER_ARM,
    HumanoidRig,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_equal,
    assert_true,
)
from tests._attire_fixtures import standing_rig, tube


def _rig() raises -> HumanoidRig:
    """Return a standing rig with its chest at 1.3 m and its shoulders
    0.2 m to each side."""
    var rig = standing_rig()
    rig.joints[CHEST.value] = Vector3(0, 1.3, 0)
    rig.joints[RIGHT_UPPER_ARM.value] = Vector3(-0.2, 1.4, 0)
    rig.joints[LEFT_UPPER_ARM.value] = Vector3(0.2, 1.4, 0)
    return rig^


def _shoulders(both: Bool = True) raises -> BufferGeometry:
    """Return a short tube round each shoulder, or the right one alone, a
    cover value of one at each vertex."""
    var mesh = tube(-0.2, 0, 0.06, 1.45, 1.3, RIGHT_UPPER_ARM, 4, 12)
    if both:
        mesh = merge(mesh, tube(0.2, 0, 0.06, 1.45, 1.3, LEFT_UPPER_ARM, 4, 12))
    mesh.set_attribute(
        String(COVER),
        BufferAttribute(List[Float32](length=mesh.vertex_count(), fill=1), 1),
    )
    return mesh^


def test_a_shell_parts_at_the_chest() raises:
    var rig = _rig()
    var right = shoulder_points(_shoulders(), rig, True)
    var left = shoulder_points(_shoulders(), rig, False)
    assert_true(len(right) > 0 and len(left) > 0)
    for p in right:
        assert_true(p.x < 0)
    for p in left:
        assert_true(p.x > 0)


def test_each_shoulder_is_domed() raises:
    var rig = _rig()
    var domes = dome_shoulders(_shoulders(), rig, 0.002)
    assert_true(domes.triangle_count() > 100)
    ref placed = domes.attribute_view(String(POSITION))
    ref covers = domes.attribute_view(String(COVER))
    var right = 0
    var left = 0
    var highest = Float32(-1e9)
    var trimmed = 0
    for v in range(placed.count()):
        var p = placed.vector3(v)
        if p.x < 0:
            right += 1
        else:
            left += 1
        highest = max(highest, p.y)
        if covers.component(v, 0) == DOME_TRIM:
            trimmed += 1
    assert_true(right > 0 and left > 0)
    assert_true(trimmed > 0)
    # Each dome stands well off the shoulder's top.
    assert_true(highest > 1.45 + DOME_STAND * 0.8)
    # Neither dome reaches far over the middle of the chest.
    for v in range(placed.count()):
        assert_true(abs(placed.vector3(v).x) > 0.1)


def test_one_side_or_none_is_domed_as_it_can_be() raises:
    var rig = _rig()
    var one = dome_shoulders(_shoulders(False), rig, 0.002)
    ref placed = one.attribute_view(String(POSITION))
    for v in range(placed.count()):
        assert_true(placed.vector3(v).x < 0)
    var nothing = BufferGeometry()
    nothing.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    var bare = dome_shoulders(nothing, rig, 0.002)
    assert_equal(bare.vertex_count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
