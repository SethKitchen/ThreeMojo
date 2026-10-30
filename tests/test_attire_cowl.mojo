# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for cowls: a hood closed round the head in one loose shape."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, BufferGeometry
from extensions.attire.cover import face_opening, face_oval
from extensions.attire.cowl import (
    COWL_OVERLAP,
    COWL_RINGS,
    COWL_SECTORS,
    cowl_bottom,
    cowl_mesh,
    hang_cowl,
    head_cowl,
)
from extensions.attire.last import FootLast
from extensions.attire.skirt import skirt_scale
from extensions.attire.mesh_ops import COVER, merge
from extensions.humanoid.rig.joints import (
    HEAD,
    NECK,
    RIGHT_FOREARM,
    HumanoidRig,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from tests._attire_fixtures import empty_mesh, standing_rig, tube


def _rig() raises -> HumanoidRig:
    """Return a standing rig with its skull at 1.6 m and its neck's base at
    1.45 m."""
    var rig = standing_rig()
    rig.joints[NECK.value] = Vector3(0, 1.45, 0)
    rig.joints[HEAD.value] = Vector3(0, 1.6, 0)
    return rig^


def _hood() raises -> BufferGeometry:
    """Return a head and neck as an open tube, an arm hanging beside it, a
    cover value of one at each vertex."""
    var head = tube(0, 0, 0.09, 1.85, 1.4, HEAD, 9, 16)
    var arm = tube(0.3, 0, 0.04, 1.5, 1.0, RIGHT_FOREARM)
    var mesh = merge(head, arm)
    mesh.set_attribute(
        String(COVER),
        BufferAttribute(List[Float32](length=mesh.vertex_count(), fill=1), 1),
    )
    return mesh^


def test_the_face_s_oval_is_open() raises:
    var rig = _rig()
    # Its middle, 7 cm over the skull's joint, in front.
    var middle = Vector3(0, 1.67, 0.1)
    assert_almost_equal(face_oval(rig, middle), -1)
    assert_equal(face_opening(rig, middle), 0)
    # On its edge, and beyond it.
    assert_almost_equal(face_oval(rig, Vector3(0.068, 1.67, 0.1)), 0)
    assert_true(face_oval(rig, Vector3(0.2, 1.67, 0.1)) > 0)
    assert_equal(face_opening(rig, Vector3(0.2, 1.67, 0.1)), 1)
    # Behind the head there is no opening.
    assert_equal(face_oval(rig, Vector3(0, 1.67, -0.1)), 1)


def test_a_cowl_reaches_the_base_of_the_neck() raises:
    var rig = _rig()
    assert_almost_equal(cowl_bottom(rig), 1.45)
    var hulls = head_cowl(_hood(), rig)
    assert_equal(len(hulls), 1)
    # Only the head and neck above the bottom: the arm is left out.
    assert_true(hulls[0].center.x < 0.01 and hulls[0].center.x > -0.01)
    assert_almost_equal(hulls[0].top, 1.85, atol=1e-5)
    # The hull takes where the shell crosses the bottom, so it reaches
    # down to it.
    var reach = hulls[0].top - 2 * hulls[0].reach.y
    assert_almost_equal(reach, cowl_bottom(rig), atol=1e-4)
    # A hood that does not reach above the bottom has no cowl.
    var low = tube(0, 0, 0.09, 1.4, 1.2, HEAD)
    assert_equal(len(head_cowl(low, rig)), 0)


def test_a_cowl_is_open_at_the_face_and_lined() raises:
    var rig = _rig()
    var hood = _hood()
    var hull = head_cowl(hood, rig)[0].copy()
    var closed = cowl_mesh(hull, hood, rig, False, 0.0012)
    var opened = cowl_mesh(hull, hood, rig, True, 0.0012)
    assert_true(closed.triangle_count() > 2 * COWL_SECTORS * COWL_RINGS)
    assert_true(opened.triangle_count() < closed.triangle_count())
    assert_true(opened.has_attribute(String(NORMAL)))
    # Nothing of the open cowl lies inside the face's oval, but for the
    # chords the cut lays across its curve, and nothing below its bottom.
    ref placed = opened.attribute_view(String(POSITION))
    for v in range(placed.count()):
        var p = placed.vector3(v)
        assert_true(face_oval(rig, p) > -0.05)
        assert_true(p.y > 1.45)
    # A cowl stands off its hull; its lining a thickness inside it.
    ref round = closed.attribute_view(String(POSITION))
    var outer = Float32(0)
    for v in range(round.count()):
        outer = max(outer, round.vector3(v).x)
    assert_true(outer > 0.09)
    # A shell with no vertex gives the cowl no weights to take.
    var bare = cowl_mesh(hull, empty_mesh(), rig, True, 0.0012)
    assert_true(bare.triangle_count() > 0)


def test_a_hood_hangs_its_cowl() raises:
    var rig = _rig()
    var hood = _hood()
    var hulls = head_cowl(hood, rig)
    var hung = hang_cowl(hood, hulls, rig, True, 0.0012)
    var cowl = cowl_mesh(hulls[0], hood, rig, True, 0.0012)
    # The shell keeps what lies below the cut, under the cowl's bottom.
    assert_true(hung.triangle_count() > cowl.triangle_count())
    ref placed = hung.attribute_view(String(POSITION))
    var lowest = Float32(10)
    for v in range(placed.count()):
        lowest = min(lowest, placed.vector3(v).y)
    assert_almost_equal(lowest, 1.0, atol=1e-5)
    # The shell reaches up into the cowl, past its bottom, so no gap
    # opens round the neck.
    var edge = cowl_bottom(rig) + COWL_OVERLAP * skirt_scale(rig)
    var at_edge = 0
    for v in range(placed.count()):
        if abs(placed.vector3(v).y - edge) < 1e-4:
            at_edge += 1
    assert_true(at_edge > 0)
    # An empty shell hangs the cowl alone.
    var alone = hang_cowl(empty_mesh(), hulls, rig, True, 0.0012)
    assert_true(alone.triangle_count() > 0)
    # No hull: the hood as it was.
    var same = hang_cowl(hood, List[FootLast](), rig, True, 0.0012)
    assert_equal(same.triangle_count(), hood.triangle_count())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
