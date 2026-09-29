# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA physics: shapes, bodies, contacts and ray casts.

Every expected value is a hand calculation from the physics: the inertia
formulas of solids, the closest points of simple shapes, and the lengths
along a ray.
"""

from extensions.carla.physics.body import (
    BodyId,
    BodyKind,
    DYNAMIC,
    KINEMATIC,
    RigidBody,
    STATIC,
)
from extensions.carla.physics.collide import (
    ContactPoint,
    WorldShape,
    clip_polygon,
    collide,
    face_contact,
    flipped,
    mesh_contacts,
    polyhedron_polyhedron,
    round_polyhedron,
    round_round,
    signed_distance,
)
from extensions.carla.physics.quantities import (
    JOULE,
    KILOMETER_PER_HOUR,
    MILE_PER_HOUR,
    NEWTON_METER,
    NEWTON_PER_CENTIMETER,
    NEWTON_PER_DEGREE,
    NEWTON_PER_METER,
    NEWTON_SECOND,
    NEWTON_SECOND_PER_METER,
    REVOLUTION_PER_MINUTE,
    CorneringStiffness,
    DampingRate,
    Energy,
    Momentum,
    Stiffness,
    Torque,
)
from extensions.carla.physics.shape import (
    BOX,
    CAPSULE,
    CONVEX,
    MESH,
    PhysicsMaterial,
    Polyhedron,
    SPHERE,
    Shape,
    ShapeKind,
    any_perpendicular,
    component,
    cross,
    unit_or,
)
from extensions.carla.physics.world import PhysicsWorld
from math.matrix3 import Matrix3
from math.quaternion import Quaternion
from math.triangle import Triangle
from math.vector3 import Vector3
from std.math import cos, inf, isnan, nan, pi, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Angle,
    AngularVelocity,
    DEGREE,
    Duration,
    KILOGRAM,
    Length,
    METER,
    Mass,
    RADIAN,
    SECOND,
    Velocity,
)


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _kg(value: Float32) -> Mass:
    return Mass(value, KILOGRAM)


def _near(a: Vector3, b: Vector3, tol: Float64) raises:
    assert_almost_equal(a.x, b.x, atol=tol)
    assert_almost_equal(a.y, b.y, atol=tol)
    assert_almost_equal(a.z, b.z, atol=tol)


def _cube(half: Float32) raises -> Shape:
    return Shape.box(_m(half), _m(half), _m(half))


def _body(
    kind: BodyKind, var shape: Shape, mass: Float32, at: Vector3
) raises -> RigidBody:
    return RigidBody(kind, shape^, _kg(mass), at, Quaternion.identity())


def _solid(half: Vector3, at: Vector3, turn: Quaternion) -> WorldShape:
    var m = Matrix3.from_matrix4(turn.to_matrix())
    return WorldShape.solid(Polyhedron.box(half).transformed(at, m))


def _turn(axis: Vector3, degrees: Float32) -> Quaternion:
    return Quaternion.from_axis_angle(axis, Angle(degrees, DEGREE))


# --- units ------------------------------------------------------------------


def test_units() raises:
    # One rpm is 2 pi / 60 rad/s; 36 km/h is 10 m/s; 1 mph is 0.44704 m/s.
    assert_almost_equal(
        AngularVelocity(60, REVOLUTION_PER_MINUTE).value,
        Float32(2 * pi),
        atol=1e-5,
    )
    assert_almost_equal(Velocity(36, KILOMETER_PER_HOUR).value, 10, atol=1e-5)
    assert_almost_equal(Velocity(1, MILE_PER_HOUR).value, 0.44704, atol=1e-7)
    # 250 N/cm is 25 000 N/m.
    assert_almost_equal(
        Stiffness(250, NEWTON_PER_CENTIMETER).to(NEWTON_PER_METER),
        25000,
        atol=1e-2,
    )
    # 1 N/deg is 180 / pi N/rad.
    assert_almost_equal(
        CorneringStiffness(1, NEWTON_PER_DEGREE).value,
        Float32(180 / pi),
        atol=1e-4,
    )
    assert_equal(Torque(3, NEWTON_METER).to(JOULE), 3)
    assert_equal(Momentum(2, NEWTON_SECOND).value, 2)
    assert_equal(DampingRate(4, NEWTON_SECOND_PER_METER).value, 4)
    assert_equal(Energy(5, JOULE).value, 5)


# --- shapes -----------------------------------------------------------------


def test_shape_kinds_and_materials() raises:
    assert_true(SPHERE.is_valid())
    assert_true(MESH.is_valid())
    assert_false(ShapeKind(-1).is_valid())
    assert_false(ShapeKind(5).is_valid())
    var d = PhysicsMaterial.default()
    assert_almost_equal(d.friction, 0.6, atol=1e-6)
    assert_equal(d.restitution, 0)
    d.check()
    # Box2D's mixing: sqrt(0.2 x 0.8) = 0.4, and the larger restitution.
    var c = PhysicsMaterial(0.2, 1.0).combine(PhysicsMaterial(0.8, 0.0))
    assert_almost_equal(c.friction, 0.4, atol=1e-6)
    assert_equal(c.restitution, 1)
    c = PhysicsMaterial(0.5, 0.25).combine(PhysicsMaterial(0, 0.5))
    assert_equal(c.friction, 0)
    assert_equal(c.restitution, 0.5)
    with assert_raises():
        PhysicsMaterial(-0.1, 0.5).check()
    with assert_raises():
        PhysicsMaterial(inf[DType.float32](), 0.5).check()
    with assert_raises():
        PhysicsMaterial(0.5, -0.1).check()
    with assert_raises():
        PhysicsMaterial(0.5, 1.1).check()


def test_vector_helpers() raises:
    _near(cross(Vector3(1, 0, 0), Vector3(0, 1, 0)), Vector3(0, 0, 1), 0)
    _near(
        unit_or(Vector3(0, 3, 4), Vector3(1, 0, 0)), Vector3(0, 0.6, 0.8), 1e-6
    )
    _near(unit_or(Vector3(0, 0, 0), Vector3(1, 0, 0)), Vector3(1, 0, 0), 0)
    # Both branches: a normal near x and one far from it.
    var u = any_perpendicular(Vector3(0, 0, 1))
    assert_almost_equal(u.dot(Vector3(0, 0, 1)), 0, atol=1e-6)
    assert_almost_equal(u.length(), 1, atol=1e-6)
    var w = any_perpendicular(Vector3(1, 0, 0))
    assert_almost_equal(w.dot(Vector3(1, 0, 0)), 0, atol=1e-6)
    assert_almost_equal(w.length(), 1, atol=1e-6)
    var v = Vector3(1, 2, 3)
    assert_equal(component(v, 0), 1)
    assert_equal(component(v, 1), 2)
    assert_equal(component(v, 2), 3)


def test_shape_refusals() raises:
    with assert_raises():
        _ = Shape.sphere(_m(0))
    with assert_raises():
        _ = Shape.sphere(_m(inf[DType.float32]()))
    with assert_raises():
        _ = Shape.box(_m(1), _m(-1), _m(1))
    with assert_raises():
        _ = Shape.capsule(_m(0), _m(1))
    with assert_raises():
        _ = Shape.capsule(_m(1), _m(-1))
    with assert_raises():
        _ = Shape.capsule(_m(1), _m(inf[DType.float32]()))
    with assert_raises():
        _ = Shape.convex([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
    with assert_raises():
        _ = Shape.mesh(List[Triangle]())
    var mesh = Shape.mesh(
        [Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))]
    )
    assert_true(mesh.kind == MESH)
    with assert_raises():
        _ = mesh.mass_properties(1)


def test_polyhedron_box() raises:
    var box = Polyhedron.box(Vector3(1, 2, 3))
    assert_equal(len(box.vertices), 8)
    assert_equal(box.face_count(), 6)
    assert_equal(len(box.edge_a), 12)
    # Every face normal points away from the middle, one unit long.
    for f in range(6):
        assert_almost_equal(box.normals[f].length(), 1, atol=1e-6)
        assert_true(box.offsets[f] > 0)
    assert_equal(box.support(Vector3(0, 0, 1)), 3)
    assert_equal(box.support(Vector3(-1, 0, 0)), 1)
    _near(box.center(), Vector3(0, 0, 0), 0)
    var tri = Polyhedron.triangle(
        Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))
    )
    assert_equal(tri.face_count(), 1)
    assert_equal(len(tri.edge_a), 3)
    _near(tri.normals[0], Vector3(0, 0, 1), 0)


def test_hull_merges_coplanar_faces() raises:
    var points = List[Vector3]()
    for i in range(8):
        points.append(
            Vector3(
                Float32(1) if (i & 1) != 0 else Float32(-1),
                Float32(1) if (i & 2) != 0 else Float32(-1),
                Float32(1) if (i & 4) != 0 else Float32(-1),
            )
        )
    # A point inside is not a corner.
    points.append(Vector3(0, 0, 0))
    var hull = Shape.convex(points)
    assert_true(hull.kind == CONVEX)
    # The twelve triangles of a cube merge into six squares.
    assert_equal(hull.polyhedron.face_count(), 6)
    assert_equal(len(hull.polyhedron.vertices), 8)
    assert_equal(len(hull.polyhedron.edge_a), 12)
    for f in range(6):
        assert_equal(
            hull.polyhedron.face_start[f + 1] - hull.polyhedron.face_start[f],
            4,
        )
        assert_almost_equal(hull.polyhedron.offsets[f], 1, atol=1e-5)


def test_mass_properties() raises:
    # A solid sphere: I = 2/5 m r^2 = 0.4 * 2 * 0.25.
    var sphere = Shape.sphere(_m(0.5)).mass_properties(2)
    assert_almost_equal(sphere.inertia.elements[0], 0.2, atol=1e-6)
    assert_almost_equal(sphere.inertia.elements[8], 0.2, atol=1e-6)
    # A box: I_xx = m (b^2 + c^2) / 3 with half sizes: 4 (4 + 9).
    var box = Shape.box(_m(1), _m(2), _m(3)).mass_properties(12)
    assert_almost_equal(box.inertia.elements[0], 52, atol=1e-3)
    assert_almost_equal(box.inertia.elements[4], 40, atol=1e-3)
    assert_almost_equal(box.inertia.elements[8], 20, atol=1e-3)
    assert_almost_equal(box.inertia.elements[1], 0, atol=1e-4)
    _near(box.center, Vector3(0, 0, 0), 1e-5)
    # A capsule of radius 1 and a 2 m segment: the cylinder is 2 pi, the
    # ball 4 pi / 3, so 6 kg of 10 are cylinder and 4 are ball.
    # Axial: 6 / 2 + 4 * 0.4 = 4.6. Across: 6 (1/4 + 4/12)
    # + 4 (0.4 + 1 + 0.75) = 12.1.
    var capsule = Shape.capsule(_m(1), _m(1)).mass_properties(10)
    assert_almost_equal(capsule.inertia.elements[8], 4.6, atol=1e-4)
    assert_almost_equal(capsule.inertia.elements[0], 12.1, atol=1e-4)
    assert_almost_equal(capsule.inertia.elements[4], 12.1, atol=1e-4)
    # The unit right tetrahedron: volume 1/6, center (1/4, 1/4, 1/4).
    # About the origin, the integral of x^2 is 1/60 and of x y 1/120, so
    # with density 6 and moved to the center: I_xx = 0.075 and
    # I_xy = 0.0125.
    var tet = Shape.convex(
        [
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(0, 0, 1),
        ]
    ).mass_properties(1)
    _near(tet.center, Vector3(0.25, 0.25, 0.25), 1e-5)
    assert_almost_equal(tet.inertia.elements[0], 0.075, atol=1e-5)
    assert_almost_equal(tet.inertia.elements[4], 0.075, atol=1e-5)
    assert_almost_equal(tet.inertia.elements[1], 0.0125, atol=1e-5)
    assert_almost_equal(tet.inertia.elements[5], 0.0125, atol=1e-5)


# --- bodies -----------------------------------------------------------------


def test_body_kinds_and_refusals() raises:
    assert_true(STATIC.is_valid())
    assert_true(KINEMATIC.is_valid())
    assert_false(BodyKind(3).is_valid())
    assert_false(BodyKind(-1).is_valid())
    assert_true(BodyId(0).is_valid())
    assert_false(BodyId(-1).is_valid())
    with assert_raises():
        _ = _body(BodyKind(7), _cube(1), 1, Vector3(0, 0, 0))
    var tris: List[Triangle] = [
        Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))
    ]
    with assert_raises():
        _ = _body(DYNAMIC, Shape.mesh(tris^), 1, Vector3(0, 0, 0))
    with assert_raises():
        _ = _body(DYNAMIC, _cube(1), 0, Vector3(0, 0, 0))
    with assert_raises():
        _ = _body(DYNAMIC, _cube(1), nan[DType.float32](), Vector3(0, 0, 0))
    var still = _body(STATIC, _cube(1), 5, Vector3(0, 0, 0))
    assert_equal(still.mass, 0)
    assert_false(still.is_dynamic())
    with assert_raises():
        still.set_mass(_kg(1))
    # A static body's shape can move; its mass stays none.
    still.set_shape_pose(Vector3(0, 0, 1), Quaternion.identity())
    assert_equal(still.mass, 0)


def test_body_motion() raises:
    # A 2 kg ball of radius 0.5: I = 0.2.
    var ball = _body(DYNAMIC, Shape.sphere(_m(0.5)), 2, Vector3(1, 0, 0))
    assert_true(ball.is_dynamic())
    # An impulse (0, 1, 0) at the right edge: dv = 0.5, dw = r x J / I
    # = (0, 0, 0.5) / 0.2 = 2.5.
    ball.apply_impulse(Vector3(0, 1, 0), Vector3(1.5, 0, 0))
    _near(ball.linear_velocity, Vector3(0, 0.5, 0), 1e-6)
    _near(ball.angular_velocity, Vector3(0, 0, 2.5), 1e-5)
    _near(ball.momentum(), Vector3(0, 1, 0), 1e-6)
    _near(ball.angular_momentum(), Vector3(0, 0, 0.5), 1e-5)
    # m v^2 / 2 + I w^2 / 2 = 0.25 + 0.625.
    assert_almost_equal(ball.kinetic_energy(), 0.875, atol=1e-5)
    # The point opposite the push moves with v - w x r.
    _near(ball.velocity_at(Vector3(0.5, 0, 0)), Vector3(0, -0.75, 0), 1e-5)
    ball.add_force(Vector3(0, 0, 3), Vector3(1, 1, 0))
    _near(ball.force, Vector3(0, 0, 3), 0)
    _near(ball.torque, Vector3(3, 0, 0), 1e-6)


def test_body_shape_pose() raises:
    # A box moved up 1 m in its body: the center of mass follows.
    var body = _body(DYNAMIC, _cube(0.5), 3, Vector3(0, 0, 0))
    body.set_shape_pose(Vector3(0, 0, 1), _turn(Vector3(0, 0, 1), 90))
    _near(body.center_of_mass, Vector3(0, 0, 1), 1e-6)
    body.rotation = _turn(Vector3(1, 0, 0), 90)
    # Turned a quarter about x, local plus z points along world minus y.
    _near(body.world_center_of_mass(), Vector3(0, -1, 0), 1e-6)
    _near(body.shape_world_position(), Vector3(0, -1, 0), 1e-6)
    body.set_center_of_mass(Vector3(0, 0, 0))
    _near(body.world_center_of_mass(), Vector3(0, 0, 0), 0)
    # A cube's inertia is the same about every axis: m (2 a^2) / 3 = 0.5.
    var inertia = body.world_inverse_inertia()
    assert_almost_equal(inertia.elements[0], 2, atol=1e-4)
    assert_almost_equal(inertia.elements[4], 2, atol=1e-4)


# --- contacts ---------------------------------------------------------------


def test_round_round() raises:
    var a = WorldShape.round(Vector3(0, 0, 0), Vector3(0, 0, 0), 1)
    var b = WorldShape.round(Vector3(1.5, 0, 0), Vector3(1.5, 0, 0), 1)
    assert_true(a.is_round())
    var c = collide(a, b, 0.02)
    assert_equal(len(c), 1)
    assert_almost_equal(c[0].depth, 0.5, atol=1e-6)
    _near(c[0].normal, Vector3(1, 0, 0), 1e-6)
    # Halfway between the surfaces at x = 1 and x = 0.5.
    _near(c[0].point, Vector3(0.75, 0, 0), 1e-6)
    # Apart by more than the margin: nothing.
    var far = WorldShape.round(Vector3(2.1, 0, 0), Vector3(2.1, 0, 0), 1)
    assert_equal(len(round_round(a, far, 0.02)), 0)
    # Apart by less than the margin: a contact with a gap.
    var near = WorldShape.round(Vector3(2.01, 0, 0), Vector3(2.01, 0, 0), 1)
    var gap = round_round(a, near, 0.02)
    assert_almost_equal(gap[0].depth, -0.01, atol=1e-5)
    # The same center has no direction: plus z is used.
    var same = round_round(a, a, 0.02)
    _near(same[0].normal, Vector3(0, 0, 1), 0)
    # Two crossed capsules touch at their segments' nearest points.
    var p = WorldShape.round(Vector3(-1, 0, 0), Vector3(1, 0, 0), 0.3)
    var q = WorldShape.round(Vector3(0, -1, 0.5), Vector3(0, 1, 0.5), 0.3)
    var pq = collide(p, q, 0.02)
    assert_almost_equal(pq[0].depth, 0.1, atol=1e-6)
    _near(pq[0].normal, Vector3(0, 0, 1), 1e-6)
    _near(pq[0].point, Vector3(0, 0, 0.25), 1e-6)


def test_signed_distance() raises:
    var box = Polyhedron.box(Vector3(1, 1, 1))
    var inside = signed_distance(box, Vector3(0, 0, 0.5))
    assert_almost_equal(inside.distance, -0.5, atol=1e-6)
    _near(inside.normal, Vector3(0, 0, 1), 0)
    _near(inside.surface, Vector3(0, 0, 1), 1e-6)
    # Off a corner: the distance to the corner.
    var corner = signed_distance(box, Vector3(2, 2, 2))
    assert_almost_equal(corner.distance, Float32(sqrt(3.0)), atol=1e-5)
    _near(corner.surface, Vector3(1, 1, 1), 1e-5)
    # Off an edge.
    var edge = signed_distance(box, Vector3(2, 0.5, 2))
    assert_almost_equal(edge.distance, Float32(sqrt(2.0)), atol=1e-5)


def test_round_polyhedron() raises:
    var box = _solid(Vector3(1, 1, 1), Vector3(0, 0, 0), Quaternion.identity())
    # A ball on the top face: 0.2 deep, the normal from the box up.
    var ball = WorldShape.round(Vector3(0, 0, 1.3), Vector3(0, 0, 1.3), 0.5)
    var c = collide(box, ball, 0.02)
    assert_equal(len(c), 1)
    assert_almost_equal(c[0].depth, 0.2, atol=1e-6)
    _near(c[0].normal, Vector3(0, 0, 1), 1e-6)
    _near(c[0].point, Vector3(0, 0, 0.9), 1e-6)
    # The other order turns the normal around.
    var d = collide(ball, box, 0.02)
    _near(d[0].normal, Vector3(0, 0, -1), 1e-6)
    # Near a corner: the depth is the radius less the corner distance.
    var off = WorldShape.round(
        Vector3(1.3, 1.3, 1.3), Vector3(1.3, 1.3, 1.3), 0.6
    )
    var e = collide(box, off, 0.02)
    assert_almost_equal(e[0].depth, Float32(0.6 - sqrt(0.27)), atol=1e-5)
    var k = Float32(1 / sqrt(3.0))
    _near(e[0].normal, Vector3(k, k, k), 1e-5)
    # Too far: nothing.
    var away = WorldShape.round(Vector3(0, 0, 3), Vector3(0, 0, 3), 0.5)
    assert_equal(len(collide(box, away, 0.02)), 0)
    # A capsule lying on the top face rests on its two ends. Every point
    # of it is as deep, so where the search ends is a matter of rounding:
    # it may add a third point, as deep as the ends.
    var lying = WorldShape.round(
        Vector3(-0.5, 0, 1.2), Vector3(0.5, 0, 1.2), 0.3
    )
    var f = round_polyhedron(lying, box.polyhedron, 0.02)
    assert_true(len(f) >= 2)
    for p in f:
        assert_almost_equal(p.depth, 0.1, atol=1e-5)
    # A capsule across an edge: only its middle touches.
    var across = WorldShape.round(
        Vector3(1.2, -2, 1.2), Vector3(1.2, 2, 1.2), 0.3
    )
    var g = round_polyhedron(across, box.polyhedron, 0.02)
    assert_equal(len(g), 1)
    assert_almost_equal(g[0].depth, Float32(0.3 - sqrt(0.08)), atol=1e-4)
    var h = Float32(1 / sqrt(2.0))
    _near(g[0].normal, Vector3(h, 0, h), 1e-3)
    # Standing up on the face: the nearest point is an end.
    var up = WorldShape.round(Vector3(0, 0, 1.2), Vector3(0, 0, 3), 0.3)
    assert_equal(len(round_polyhedron(up, box.polyhedron, 0.02)), 1)
    var down = WorldShape.round(Vector3(0, 0, 3), Vector3(0, 0, 1.2), 0.3)
    assert_equal(len(round_polyhedron(down, box.polyhedron, 0.02)), 1)


def test_box_box_face() raises:
    var a = _solid(Vector3(1, 1, 1), Vector3(0, 0, 0), Quaternion.identity())
    var b = _solid(
        Vector3(0.5, 0.5, 0.5), Vector3(0, 0, 1.4), Quaternion.identity()
    )
    # The small box's bottom face, clipped to the big box's top: 4 corners,
    # each 0.1 deep, halfway at z = 0.95.
    var c = collide(a, b, 0.02)
    assert_equal(len(c), 4)
    for p in c:
        assert_almost_equal(p.depth, 0.1, atol=1e-5)
        _near(p.normal, Vector3(0, 0, 1), 1e-6)
        assert_almost_equal(p.point.z, 0.95, atol=1e-5)
        assert_almost_equal(abs(p.point.x), 0.5, atol=1e-5)
    # Apart along a face of the first, of the second, or along an edge.
    var above = _solid(
        Vector3(0.5, 0.5, 0.5), Vector3(0, 0, 3), Quaternion.identity()
    )
    assert_equal(
        len(polyhedron_polyhedron(a.polyhedron, above.polyhedron, 0.02)), 0
    )
    var tilted = _solid(
        Vector3(1, 1, 1), Vector3(0, 0, 0), _turn(Vector3(1, 0, 0), 45)
    )
    var flat = _solid(
        Vector3(0.5, 0.5, 0.5), Vector3(0, 0, 3), Quaternion.identity()
    )
    assert_equal(len(collide(tilted, flat, 0.02)), 0)


def test_box_box_reference_second() raises:
    # A box on its edge, a flat box resting on that edge. The flat box's
    # bottom is the best face: it is the reference, and the normal is
    # turned around to point from the first box to the second.
    var top = Float32(sqrt(2.0))
    var a = _solid(
        Vector3(1, 1, 1), Vector3(0, 0, 0), _turn(Vector3(1, 0, 0), 45)
    )
    var b = _solid(
        Vector3(0.5, 0.5, 0.5),
        Vector3(0, 0, top + 0.45),
        Quaternion.identity(),
    )
    var c = collide(a, b, 0.02)
    assert_equal(len(c), 2)
    for p in c:
        assert_almost_equal(p.depth, 0.05, atol=1e-4)
        _near(p.normal, Vector3(0, 0, 1), 1e-5)
        assert_almost_equal(abs(p.point.x), 0.5, atol=1e-4)


def test_box_box_edge() raises:
    # Two boxes on crossed edges, 0.1 into each other: one contact where
    # the edges cross.
    var top = Float32(sqrt(2.0))
    var a = _solid(
        Vector3(1, 1, 1), Vector3(0, 0, 0), _turn(Vector3(1, 0, 0), 45)
    )
    var b = _solid(
        Vector3(1, 1, 1),
        Vector3(0, 0, 2 * top - 0.1),
        _turn(Vector3(0, 1, 0), 45),
    )
    var c = collide(a, b, 0.02)
    assert_equal(len(c), 1)
    assert_almost_equal(c[0].depth, 0.1, atol=1e-4)
    _near(c[0].normal, Vector3(0, 0, 1), 1e-4)
    _near(c[0].point, Vector3(0, 0, top - 0.05), 1e-4)


def test_mesh_contacts() raises:
    var tri = Triangle(Vector3(-5, -5, 0), Vector3(5, -5, 0), Vector3(0, 5, 0))
    # A box 0.05 into the triangle: four points, normals up.
    var box = _solid(
        Vector3(0.5, 0.5, 0.5), Vector3(0, 0, 0.45), Quaternion.identity()
    )
    var c = mesh_contacts(tri, box, 0.02)
    assert_equal(len(c), 4)
    for p in c:
        assert_almost_equal(p.depth, 0.05, atol=1e-5)
        _near(p.normal, Vector3(0, 0, 1), 1e-6)
    # A box with its middle behind the triangle does not touch it.
    var under = _solid(
        Vector3(0.5, 0.5, 0.5), Vector3(0, 0, -0.1), Quaternion.identity()
    )
    assert_equal(len(mesh_contacts(tri, under, 0.02)), 0)
    # A ball 0.1 in, and one 0.01 above: a gap within the margin.
    var ball = WorldShape.round(Vector3(0, 0, 0.4), Vector3(0, 0, 0.4), 0.5)
    var b = mesh_contacts(tri, ball, 0.02)
    assert_almost_equal(b[0].depth, 0.1, atol=1e-5)
    var hover = WorldShape.round(Vector3(0, 0, 0.51), Vector3(0, 0, 0.51), 0.5)
    assert_almost_equal(
        mesh_contacts(tri, hover, 0.02)[0].depth, -0.01, atol=1e-5
    )
    var high = WorldShape.round(Vector3(0, 0, 2), Vector3(0, 0, 2), 0.5)
    assert_equal(len(mesh_contacts(tri, high, 0.02)), 0)
    # A standing capsule 0.05 in.
    var cap = WorldShape.round(Vector3(0, 0, 0.25), Vector3(0, 0, 1.25), 0.3)
    var d = mesh_contacts(tri, cap, 0.02)
    assert_equal(len(d), 1)
    assert_almost_equal(d[0].depth, 0.05, atol=1e-5)
    var far = WorldShape.round(Vector3(0, 0, 2), Vector3(0, 0, 3), 0.3)
    assert_equal(len(mesh_contacts(tri, far, 0.02)), 0)


def test_flipped() raises:
    var points: List[ContactPoint] = [
        ContactPoint(Vector3(1, 2, 3), Vector3(0, 0, 1), 0.5)
    ]
    var f = flipped(points)
    _near(f[0].normal, Vector3(0, 0, -1), 0)
    _near(f[0].point, Vector3(1, 2, 3), 0)
    assert_equal(f[0].depth, 0.5)


def test_empty_and_tiny_polyhedra() raises:
    # With no corner, a move moves nothing and the middle is undefined.
    var none = Polyhedron().transformed(Vector3(1, 2, 3), Matrix3())
    assert_equal(len(none.vertices), 0)
    assert_true(isnan(Polyhedron().center().x))
    # One corner reaches as far as itself.
    var one = Polyhedron()
    one.vertices.append(Vector3(1, 2, 3))
    assert_equal(one.support(Vector3(0, 0, 1)), 3)


def test_clip_polygon() raises:
    var square: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(2, 0, 0),
        Vector3(2, 2, 0),
        Vector3(0, 2, 0),
    ]
    # Cut at x = 1: two corners kept, two made where the edges cross.
    var half = clip_polygon(square, Vector3(1, 0, 0), 1)
    assert_equal(len(half), 4)
    for p in half:
        assert_true(p.x <= 1 + 1e-6)
    # All on the far side: nothing, and nothing clips to nothing.
    var gone = clip_polygon(square, Vector3(-1, 0, 0), -5)
    assert_equal(len(gone), 0)
    assert_equal(len(clip_polygon(gone, Vector3(1, 0, 0), 0)), 0)


def test_face_contact_clipped_away() raises:
    # The top face of one box against a box far to the side: its facing
    # face lies outside the top face's sides, so nothing is left.
    var a = Polyhedron.box(Vector3(1, 1, 1))
    var m = Matrix3()
    var b = Polyhedron.box(Vector3(0.5, 0.5, 0.5)).transformed(
        Vector3(5, 0, 1.4), m
    )
    # Face 5 of a box is its top, plus z.
    _near(a.normals[5], Vector3(0, 0, 1), 0)
    assert_equal(len(face_contact(a, 5, b, 0.02)), 0)
    assert_equal(len(face_contact(a, 5, a, 0.02)), 4)


def test_face_contact_keeps_eight() raises:
    # Two octagonal slabs, the upper turned 22.5 degrees: the clipped
    # face has sixteen corners, and eight are kept.
    var lower = List[Vector3]()
    var upper = List[Vector3]()
    for i in range(8):
        var a = Float32(i) * Float32(pi / 4)
        var b = a + Float32(pi / 8)
        for z in [Float32(-0.5), Float32(0.5)]:
            lower.append(Vector3(cos(a), sin(a), z))
            upper.append(Vector3(cos(b), sin(b), z + 0.95))
    var p = Shape.convex(lower).polyhedron.copy()
    var q = Shape.convex(upper).polyhedron.copy()
    var c = polyhedron_polyhedron(p, q, 0.02)
    assert_equal(len(c), 8)
    for point in c:
        assert_almost_equal(point.depth, 0.05, atol=1e-4)


def test_box_box_gap_along_the_second() raises:
    # A box on its edge and a flat box 0.1 above it: only the flat box's
    # face shows the gap.
    var top = Float32(sqrt(2.0))
    var a = _solid(
        Vector3(1, 1, 1), Vector3(0, 0, 0), _turn(Vector3(1, 0, 0), 45)
    )
    var b = _solid(
        Vector3(0.5, 0.5, 0.5),
        Vector3(0, 0, top + 0.6),
        Quaternion.identity(),
    )
    assert_equal(len(collide(a, b, 0.02)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
