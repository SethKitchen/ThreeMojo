# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's frame, OpenDRIVE roads, sensor encodings, cameras and LiDAR."""

from core.assets import Assets
from core.buffer_geometry import NORMAL, POSITION
from core.object3d import Object3D
from core.scene import Scene
from extensions.carla.capture import depth_frame, nearest_hit, semantic_frame
from extensions.carla.geometry import (
    ARC,
    ARC_LENGTH,
    DirectedPoint,
    LINE,
    NORMALIZED,
    PARAM_POLY3,
    POLY3,
    ParamPoly3Range,
    RoadGeometry,
    RoadGeometryKind,
    SPIRAL,
    arc,
    line,
    param_poly3,
    poly3,
    spiral,
    with_arc,
    with_param_poly3,
    with_poly3,
    with_spiral,
)
from extensions.carla.lidar import LidarDescription, scan_lidar
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road_info import CURB, LaneId, LaneMarkingType
from extensions.carla.sensor import (
    BUILDING,
    CAR,
    CameraIntrinsics,
    ROAD,
    ROCK,
    SKY,
    SemanticTag,
    UNLABELED,
    cityscapes_color,
    decode_depth,
    encode_depth,
    logarithmic_gray,
    normalized_depth,
)
from extensions.carla.transform import (
    CarlaRotation,
    CarlaTransform,
    carla_to_three,
    three_to_carla,
)
from geometries.box import cube
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import cos, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    PER_METER,
    PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Frequency,
    InverseLength,
    Length,
    METER,
)


def _deg(value: Float32) -> Angle:
    return Angle(value, DEGREE)


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _rot(pitch: Float32, yaw: Float32, roll: Float32) -> CarlaRotation:
    return CarlaRotation(_deg(pitch), _deg(yaw), _deg(roll))


def _near(a: Vector3, b: Vector3, tol: Float64 = 1e-5) raises:
    assert_almost_equal(a.x, b.x, atol=tol)
    assert_almost_equal(a.y, b.y, atol=tol)
    assert_almost_equal(a.z, b.z, atol=tol)


# --- kinds ------------------------------------------------------------------


def test_kinds_are_checked() raises:
    assert_true(LINE.is_valid())
    assert_true(PARAM_POLY3.is_valid())
    assert_false(RoadGeometryKind(-1).is_valid())
    assert_false(RoadGeometryKind(5).is_valid())
    assert_true(ARC_LENGTH.is_valid())
    assert_true(NORMALIZED.is_valid())
    assert_false(ParamPoly3Range(2).is_valid())
    assert_true(LaneId(-1).is_valid())
    assert_true(LaneId(0).is_valid())
    assert_false(LaneId(1 << 40).is_valid())
    assert_true(CURB.is_valid())
    assert_false(LaneMarkingType(-1).is_valid())
    assert_false(LaneMarkingType(11).is_valid())
    assert_true(ROCK.is_valid())
    assert_false(SemanticTag(-1).is_valid())
    assert_false(SemanticTag(30).is_valid())


# --- frame ------------------------------------------------------------------


def test_rotation_matches_carla() raises:
    _near(_rot(0, 90, 0).forward_vector(), Vector3(0, 1, 0))
    _near(_rot(0, 90, 0).right_vector(), Vector3(-1, 0, 0))
    _near(_rot(0, 0, 0).up_vector(), Vector3(0, 0, 1))
    # CARLA's corrected pitch sign: the z row of the forward is -sin(p).
    _near(_rot(30, 0, 0).forward_vector(), Vector3(0.8660254, 0, -0.5))
    var r = _rot(12, -40, 33)
    var v = Vector3(0.3, -1.2, 2.5)
    _near(r.inverse_rotate_vector(r.rotate_vector(v)), v)
    assert_almost_equal(r.rotate_vector(v).length(), v.length(), atol=1e-5)


def test_rotation_normalizes_and_compares() raises:
    var n = _rot(190, -190, 540).normalized()
    assert_almost_equal(n.pitch, -170.0, atol=1e-4)
    assert_almost_equal(n.yaw, 170.0, atol=1e-4)
    assert_almost_equal(n.roll, -180.0, atol=1e-4)
    assert_almost_equal(_rot(45, 0, 0).normalized().pitch, 45.0)
    var a = _rot(1, 2, 3)
    assert_true(a == _rot(1, 2, 3))
    assert_false(a == _rot(9, 2, 3))
    assert_false(a == _rot(1, 9, 3))
    assert_false(a == _rot(1, 2, 9))
    assert_true(a != _rot(1, 2, 9))
    assert_equal(
        String(_rot(0, 90, 0)), "Rotation(pitch=0.0, yaw=90.0, roll=0.0)"
    )


def test_transform_round_trips() raises:
    var t = CarlaTransform(_m(4), _m(-2), _m(1), _rot(10, 70, -5))
    var p = Vector3(1, 2, 3)
    _near(t.inverse_transform_point(t.transform_point(p)), p)
    var m = t.matrix()
    var moved = p
    moved.apply_matrix4(m)
    _near(moved, t.transform_point(p))
    var three = carla_to_three(p)
    _near(three, Vector3(1, 3, 2))
    _near(three_to_carla(three), p)
    var placed = carla_to_three(p)
    placed.apply_matrix4(t.three_matrix())
    _near(placed, carla_to_three(t.transform_point(p)), 1e-4)
    # A three.js camera looks down its minus z. That must be CARLA forward.
    var look = Vector3(0, 0, -1)
    look.transform_direction(t.camera_matrix())
    _near(look, carla_to_three(t.rotation.forward_vector()), 1e-5)
    var up = Vector3(0, 1, 0)
    up.transform_direction(t.camera_matrix())
    _near(up, carla_to_three(t.rotation.up_vector()), 1e-5)


# --- polynomial and geometry -------------------------------------------------


def test_cubic_polynomial_shifts() raises:
    var local = CubicPolynomial(1.5, -0.2, 0.03, 0.004, 0.0)
    var shifted = CubicPolynomial(1.5, -0.2, 0.03, 0.004, 7.0)
    assert_almost_equal(shifted.evaluate(10.0), local.evaluate(3.0), atol=1e-9)
    assert_almost_equal(shifted.tangent(10.0), local.tangent(3.0), atol=1e-9)
    assert_almost_equal(CubicPolynomial.constant(3.5).evaluate(99.0), 3.5)
    assert_almost_equal(shifted.s, 7.0)


def test_line_and_arc() raises:
    var l = line(_m(0), _m(1), _m(2), Angle(0.5, RADIAN), _m(10))
    assert_equal(l.kind, LINE)
    var p = l.pos_from_dist(_m(4))
    assert_almost_equal(p.x, 1.0 + 4.0 * cos(0.5), atol=1e-6)
    assert_almost_equal(p.y, 2.0 + 4.0 * sin(0.5), atol=1e-6)
    var clamped = l.pos_from_dist(_m(40))
    assert_almost_equal(clamped.x, 1.0 + 10.0 * cos(0.5), atol=1e-5)
    var before = l.pos_from_dist(_m(-3))
    assert_almost_equal(before.x, 1.0, atol=1e-6)
    assert_almost_equal(l.end_s(), 10.0)
    # A quarter circle of radius 10, turning left from east.
    var quarter = Float32(3.14159265358979 * 5.0)
    var a = arc(
        _m(0),
        _m(0),
        _m(0),
        Angle(0, RADIAN),
        _m(quarter),
        InverseLength(0.1, PER_METER),
    )
    var e = a.pos_from_dist(_m(quarter))
    assert_almost_equal(e.x, 10.0, atol=1e-4)
    assert_almost_equal(e.y, 10.0, atol=1e-4)
    assert_almost_equal(e.tangent, 1.5707963, atol=1e-5)
    with assert_raises():
        _ = arc(
            _m(0),
            _m(0),
            _m(0),
            Angle(0, RADIAN),
            _m(1),
            InverseLength(0.0, PER_METER),
        )


def test_spiral_matches_the_clothoid() raises:
    var s = spiral(
        _m(0),
        _m(1),
        _m(2),
        Angle(0.3, RADIAN),
        _m(40),
        InverseLength(0.0, PER_METER),
        InverseLength(0.1, PER_METER),
    )
    assert_equal(s.kind, SPIRAL)
    var p = s.pos_from_dist(_m(25))
    assert_almost_equal(p.x, 21.624606718461134, atol=1e-5)
    assert_almost_equal(p.y, 14.90333504831976, atol=1e-5)
    assert_almost_equal(p.tangent, 1.08125, atol=1e-6)
    var back = spiral(
        _m(0),
        _m(0),
        _m(0),
        Angle(0, RADIAN),
        _m(30),
        InverseLength(0.05, PER_METER),
        InverseLength(-0.05, PER_METER),
    )
    var q = back.pos_from_dist(_m(30))
    assert_almost_equal(q.x, 28.88500521862165, atol=1e-4)
    assert_almost_equal(q.y, 7.380147175693973, atol=1e-4)
    # Equal curvatures make an arc. CARLA's odrSpiral divides by zero here.
    var round = spiral(
        _m(0),
        _m(0),
        _m(0),
        Angle(0, RADIAN),
        _m(10),
        InverseLength(0.1, PER_METER),
        InverseLength(0.1, PER_METER),
    )
    var ref_arc = arc(
        _m(0),
        _m(0),
        _m(0),
        Angle(0, RADIAN),
        _m(10),
        InverseLength(0.1, PER_METER),
    )
    var r1 = round.pos_from_dist(_m(7))
    var r2 = ref_arc.pos_from_dist(_m(7))
    assert_almost_equal(r1.x, r2.x, atol=1e-6)
    assert_almost_equal(r1.y, r2.y, atol=1e-6)


def test_poly3_follows_carla_table() raises:
    var g = poly3(
        _m(0),
        _m(3),
        _m(4),
        Angle(0.5, RADIAN),
        _m(20),
        0.5,
        0.1,
        0.01,
        -0.0002,
    )
    assert_equal(g.kind, POLY3)
    var p = g.pos_from_dist(_m(12.3))
    assert_almost_equal(p.x, 12.243415865117623, atol=1e-4)
    assert_almost_equal(p.y, 12.25390497292341, atol=1e-4)
    assert_almost_equal(p.tangent, 0.7487153346283768, atol=1e-5)


def test_param_poly3_follows_carla_table() raises:
    var arc_length = param_poly3(
        _m(0),
        _m(0),
        _m(0),
        Angle(0, RADIAN),
        _m(10),
        CubicPolynomial(0, 1, 0, 0, 0),
        CubicPolynomial(0, 0, 0.02, 0, 0),
        ARC_LENGTH,
    )
    assert_equal(arc_length.kind, PARAM_POLY3)
    var p = arc_length.pos_from_dist(_m(6))
    assert_almost_equal(p.x, 5.944435683062763, atol=1e-4)
    assert_almost_equal(p.y, 0.7072202071044353, atol=1e-4)
    assert_almost_equal(p.tangent, 0.23344239850046075, atol=1e-5)
    var normalized = param_poly3(
        _m(0),
        _m(1),
        _m(1),
        Angle(1.0, RADIAN),
        _m(10),
        CubicPolynomial(0, 10, 0, 0, 0),
        CubicPolynomial(0, 0, 2, 0, 0),
        NORMALIZED,
    )
    var q = normalized.pos_from_dist(_m(5))
    assert_almost_equal(q.x, 3.2684223883505794, atol=1e-4)
    assert_almost_equal(q.y, 5.446846951963158, atol=1e-4)
    assert_almost_equal(q.tangent, 1.196146268857527, atol=1e-5)
    with assert_raises():
        _ = param_poly3(
            _m(0),
            _m(0),
            _m(0),
            Angle(0, RADIAN),
            _m(10),
            CubicPolynomial.constant(1),
            CubicPolynomial.constant(2),
            ARC_LENGTH,
        )
    with assert_raises():
        _ = param_poly3(
            _m(0),
            _m(0),
            _m(0),
            Angle(0, RADIAN),
            _m(10),
            CubicPolynomial(0, 1, 0, 0, 0),
            CubicPolynomial.constant(0),
            ParamPoly3Range(7),
        )


def test_geometry_refuses_bad_records() raises:
    with assert_raises():
        _ = RoadGeometry(
            RoadGeometryKind(9), _m(0), _m(0), _m(0), Angle(0, RADIAN), _m(1)
        )
    with assert_raises():
        _ = line(_m(-1), _m(0), _m(0), Angle(0, RADIAN), _m(1))
    with assert_raises():
        _ = line(_m(0), _m(0), _m(0), Angle(0, RADIAN), _m(0))


def test_geometry_in_double() raises:
    # The builder's form keeps s, the heading and the length in double.
    var g = RoadGeometry(LINE, 0.1, 2.0, 3.0, 0.25, 7.5)
    assert_equal(g.s, 0.1)
    assert_equal(g.length, 7.5)
    var p = g.pos_at(2.0)
    assert_almost_equal(p.x, 2.0 + 2.0 * cos(0.25), atol=1e-12)
    assert_almost_equal(p.y, 3.0 + 2.0 * sin(0.25), atol=1e-12)
    var a = with_arc(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0), 0.5)
    assert_equal(a.kind, ARC)
    assert_equal(a.curvature_end, 0.5)
    with assert_raises():
        _ = with_arc(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0), 0.0)
    var sp = with_spiral(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0), 0.0, 0.1)
    assert_equal(sp.kind, SPIRAL)
    var p3 = with_poly3(RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0), 0, 0, 0, 0)
    assert_equal(p3.kind, POLY3)
    var pp = with_param_poly3(
        RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, 1.0),
        CubicPolynomial(0, 1, 0, 0, 0),
        CubicPolynomial.constant(0),
        NORMALIZED,
    )
    assert_equal(pp.kind, PARAM_POLY3)
    with assert_raises():
        _ = RoadGeometry(RoadGeometryKind(7), 0.0, 0.0, 0.0, 0.0, 1.0)
    with assert_raises():
        _ = RoadGeometry(LINE, -0.5, 0.0, 0.0, 0.0, 1.0)
    with assert_raises():
        _ = RoadGeometry(LINE, 0.0, 0.0, 0.0, 0.0, -1.0)


def test_geometry_distance_to() raises:
    # CARLA's `Geometry::DistanceTo`, record by record.
    var l = line(_m(0), _m(0), _m(0), Angle(0, RADIAN), _m(10))
    var d = l.distance_to(Vector3(4, 3, 0))
    assert_almost_equal(d[0], 4.0, atol=1e-6)
    assert_almost_equal(d[1], 3.0, atol=1e-6)
    d = l.distance_to(Vector3(-2, 1, 0))
    assert_almost_equal(d[0], 0.0, atol=1e-6)
    assert_almost_equal(d[1], 2.2360680, atol=1e-6)
    # A quarter circle of radius 10: the values come from a Python copy
    # of `Math::DistanceArcToPoint`.
    var quarter = Float32(3.14159265358979 * 5.0)
    var a = arc(
        _m(0),
        _m(0),
        _m(0),
        Angle(0, RADIAN),
        _m(quarter),
        InverseLength(0.1, PER_METER),
    )
    d = a.distance_to(Vector3(3, 2, 0))
    assert_almost_equal(d[0], 3.587706702705722, atol=1e-4)
    assert_almost_equal(d[1], 1.4559962546824692, atol=1e-4)
    var s = spiral(
        _m(0),
        _m(1),
        _m(2),
        Angle(0, RADIAN),
        _m(10),
        InverseLength(0, PER_METER),
        InverseLength(0.1, PER_METER),
    )
    d = s.distance_to(Vector3(4, 7, 0))
    assert_almost_equal(d[0], 3.0, atol=1e-6)
    assert_almost_equal(d[1], 5.0, atol=1e-6)
    var p = poly3(_m(0), _m(3), _m(4), Angle(0, RADIAN), _m(10), 0, 0, 0.01, 0)
    d = p.distance_to(Vector3(40, 70, 0))
    assert_almost_equal(d[0], 3.0, atol=1e-6)
    assert_almost_equal(d[1], 4.0, atol=1e-6)


def test_directed_point() raises:
    var p = DirectedPoint(1, 2, 3, 1.5707963267948966)
    assert_equal(p.pitch, 0.0)
    assert_equal(DirectedPoint(0, 0, 0, 0, 0.25).pitch, 0.25)
    p.apply_lateral_offset(_m(2))
    assert_almost_equal(p.x, 3.0, atol=1e-6)
    assert_almost_equal(p.y, 2.0, atol=1e-6)
    assert_almost_equal(p.heading().to(DEGREE), 90.0, atol=1e-4)
    var t = p.to_carla()
    _near(t.location, Vector3(3, -2, 3))
    assert_almost_equal(t.rotation.yaw, -90.0, atol=1e-4)


# --- sensors ----------------------------------------------------------------


def test_palette() raises:
    var road = cityscapes_color(ROAD)
    assert_equal(Int(road.r), 128)
    assert_equal(Int(road.g), 64)
    assert_equal(Int(road.b), 128)
    var rock = cityscapes_color(ROCK)
    assert_equal(Int(rock.r), 180)
    assert_equal(Int(rock.b), 70)
    assert_equal(Int(cityscapes_color(UNLABELED).g), 0)
    with assert_raises():
        _ = cityscapes_color(SemanticTag(30))


def test_depth_encoding() raises:
    var c = encode_depth(_m(12.345))
    assert_almost_equal(decode_depth(c).value, 12.345, atol=1e-3)
    var far = encode_depth(_m(5000))
    assert_equal(Int(far.r), 255)
    assert_equal(Int(far.b), 255)
    assert_almost_equal(normalized_depth(far), 1.0)
    var near = encode_depth(_m(-1))
    assert_equal(Int(near.g), 0)
    assert_almost_equal(
        decode_depth(Color(1, 0, 0)).value, 1000.0 / 16777215.0, atol=1e-9
    )
    assert_almost_equal(logarithmic_gray(1.0), 1.0)
    assert_almost_equal(logarithmic_gray(0.0), 0.005)
    assert_almost_equal(logarithmic_gray(1e-6), 0.005)
    assert_almost_equal(logarithmic_gray(0.1), 0.59630, atol=1e-4)
    assert_almost_equal(logarithmic_gray(2.0), 1.0)


def test_intrinsics() raises:
    var k = CameraIntrinsics(800, 600, _deg(90))
    assert_almost_equal(k.focal, 400.0, atol=1e-3)
    assert_almost_equal(k.cx, 400.0)
    assert_almost_equal(k.cy, 300.0)
    var cam = CarlaTransform(_m(0), _m(0), _m(2), _rot(0, 0, 0))
    var ahead = k.project(cam, Vector3(10, 1, 3))
    assert_almost_equal(ahead.x, 440.0, atol=1e-3)
    assert_almost_equal(ahead.y, 260.0, atol=1e-3)
    assert_almost_equal(ahead.z, 10.0, atol=1e-5)
    assert_true(k.project(cam, Vector3(-5, 0, 2)).z < 0.0)
    var ray = k.ray(cam, 440.0, 260.0)
    _near(ray * 10.0, Vector3(10, 1, 1), 1e-4)
    with assert_raises():
        _ = CameraIntrinsics(0, 600, _deg(90))
    with assert_raises():
        _ = CameraIntrinsics(800, -1, _deg(90))
    with assert_raises():
        _ = CameraIntrinsics(800, 600, _deg(0))
    with assert_raises():
        _ = CameraIntrinsics(800, 600, _deg(180))


# --- captures and LiDAR ---------------------------------------------------------


def _wall_scene(mut assets: Assets) raises -> Scene:
    # A 2 m cube centered 10 m ahead in CARLA's frame, 1 m up.
    var geometry = assets.geometries.add(cube(_m(2)))
    var material = assets.materials.add(Material(Color(200, 200, 200)))
    var scene = Scene()
    var node = Object3D()
    var at = carla_to_three(Vector3(10, 0, 1))
    node.set_position(at.x, at.y, at.z)
    var id = scene.add(node^)
    scene.add_mesh(Mesh(geometry, material, id))
    scene.update()
    return scene^


def test_captures() raises:
    var assets = Assets()
    var scene = _wall_scene(assets)
    var cam = CarlaTransform(_m(0), _m(0), _m(1), _rot(0, 0, 0))
    var k = CameraIntrinsics(5, 3, _deg(90))
    var depth = depth_frame(scene, assets, cam, k)
    assert_almost_equal(
        decode_depth(depth.get_pixel(2, 1)).value, 9.0, atol=1e-2
    )
    assert_almost_equal(
        decode_depth(depth.get_pixel(0, 0)).value, 1000.0, atol=1e-2
    )
    var tags = List[SemanticTag]()
    tags.append(CAR)
    var semantic = semantic_frame(scene, assets, tags, SKY, cam, k)
    assert_equal(Int(semantic.get_pixel(2, 1).b), 142)
    assert_equal(Int(semantic.get_pixel(0, 0).b), 180)
    with assert_raises():
        _ = semantic_frame(scene, assets, List[SemanticTag](), SKY, cam, k)
    var miss = nearest_hit(
        scene, assets, Vector3(0, 0, 1), Vector3(-1, 0, 0), _m(100)
    )
    assert_equal(miss.mesh, -1)
    var scaled = nearest_hit(
        scene, assets, Vector3(0, 0, 1), Vector3(2, 0, 0), _m(100)
    )
    assert_almost_equal(scaled.distance, 4.5, atol=1e-4)
    # A second cube behind the first: the nearer one still wins.
    var far_node = Object3D()
    var behind = carla_to_three(Vector3(20, 0, 1))
    far_node.set_position(behind.x, behind.y, behind.z)
    var far_id = scene.add(far_node^)
    scene.add_mesh(
        Mesh(scene.meshes[0].geometry, scene.meshes[0].material, far_id)
    )
    scene.update()
    var nearer = nearest_hit(
        scene, assets, Vector3(0, 0, 1), Vector3(1, 0, 0), _m(100)
    )
    assert_equal(nearer.mesh, 0)
    assert_almost_equal(nearer.distance, 9.0, atol=1e-4)
    tags.append(BUILDING)
    var both = semantic_frame(scene, assets, tags, SKY, cam, k)
    assert_equal(Int(both.get_pixel(2, 1).b), 142)
    var empty = Scene()
    empty.update()
    var nothing = nearest_hit(
        empty, assets, Vector3(0, 0, 0), Vector3(1, 0, 0), _m(10)
    )
    assert_equal(nothing.mesh, -1)


def test_lidar_description() raises:
    var d = LidarDescription()
    d.validate()
    var angles = d.laser_angles()
    assert_equal(len(angles), 32)
    assert_almost_equal(angles[0].to(DEGREE), 10.0, atol=1e-4)
    assert_almost_equal(angles[31].to(DEGREE), -30.0, atol=1e-4)
    d.channels = 1
    assert_almost_equal(d.laser_angles()[0].to(DEGREE), 10.0, atol=1e-4)
    d.channels = 0
    assert_equal(len(d.laser_angles()), 0)
    d.channels = 32
    assert_equal(d.points_per_laser(Duration(0.05, SECOND)), 88)
    assert_almost_equal(d.intensity(_m(100)), 0.67032, atol=1e-4)
    var bad = LidarDescription()
    bad.channels = 0
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.range = _m(0)
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.points_per_second = 0
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.rotation_frequency = Frequency(0.0, PER_SECOND)
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.upper_fov = _deg(-40)
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.horizontal_fov = _deg(0)
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.horizontal_fov = _deg(400)
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.atmosphere_attenuation = InverseLength(-1.0, PER_METER)
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.dropoff_general_rate = -0.1
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.dropoff_general_rate = 1.1
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.dropoff_zero_intensity = -0.1
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.dropoff_zero_intensity = 1.1
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.dropoff_intensity_limit = 0.0
    with assert_raises():
        bad.validate()
    bad = LidarDescription()
    bad.noise_stddev = _m(-1)
    with assert_raises():
        bad.validate()


def test_lidar_scan() raises:
    var assets = Assets()
    var scene = _wall_scene(assets)
    var sensor = CarlaTransform(_m(0), _m(0), _m(1), _rot(0, 0, 0))
    var d = LidarDescription()
    d.channels = 3
    d.upper_fov = _deg(2)
    d.lower_fov = _deg(-2)
    d.range = _m(50)
    d.horizontal_fov = _deg(10)
    d.points_per_second = 300
    d.dropoff_general_rate = 0.0
    d.dropoff_intensity_limit = 1.0
    d.dropoff_zero_intensity = 0.0
    var tick = Duration(0.1, SECOND)
    # Ten turns a second: one tick of 0.1 s sweeps the fov once.
    var scan = scan_lidar(scene, assets, sensor, d, tick, _deg(0), 7)
    assert_equal(len(scan.points), 30)
    assert_almost_equal(scan.next_angle.to(DEGREE), 0.0, atol=1e-3)
    var first = scan.points[0]
    assert_almost_equal(first.point.x, 9.0, atol=1e-3)
    assert_equal(first.channel, 0)
    assert_almost_equal(first.intensity, d.intensity(_m(9.0)), atol=1e-3)
    # The drop-off keeps only rays above the limit, or those the draw keeps.
    d.dropoff_intensity_limit = 0.5
    d.dropoff_zero_intensity = 1.0
    d.atmosphere_attenuation = InverseLength(0.2, PER_METER)
    var thinned = scan_lidar(scene, assets, sensor, d, tick, _deg(5), 7)
    assert_true(len(thinned.points) < 30)
    assert_almost_equal(thinned.next_angle.to(DEGREE), 5.0, atol=1e-3)
    d.dropoff_general_rate = 1.0
    var none = scan_lidar(scene, assets, sensor, d, tick, _deg(0), 7)
    assert_equal(len(none.points), 0)
    d.dropoff_general_rate = 0.0
    d.dropoff_intensity_limit = 1.0
    d.dropoff_zero_intensity = 0.0
    d.noise_stddev = _m(0.05)
    var noisy = scan_lidar(scene, assets, sensor, d, tick, _deg(0), 3)
    assert_equal(len(noisy.points), 30)
    assert_true(noisy.points[0].point.x != 9.0)
    # Look away: every ray misses.
    var away = CarlaTransform(_m(0), _m(0), _m(1), _rot(0, 180, 0))
    assert_equal(
        len(scan_lidar(scene, assets, away, d, tick, _deg(0), 1).points), 0
    )
    # This seed sends the generator's first state to zero, which a
    # xorshift never leaves. The generator moves it off zero.
    var odd = scan_lidar(
        scene, assets, sensor, d, tick, _deg(0), -7379792620528906219
    )
    assert_equal(len(odd.points), 30)
    d.points_per_second = 1
    var idle = scan_lidar(scene, assets, sensor, d, tick, _deg(3), 1)
    assert_equal(len(idle.points), 0)
    assert_almost_equal(idle.next_angle.to(DEGREE), 3.0, atol=1e-4)
    with assert_raises():
        _ = scan_lidar(
            scene, assets, sensor, d, Duration(0, SECOND), _deg(0), 1
        )
    d.channels = 0
    with assert_raises():
        _ = scan_lidar(scene, assets, sensor, d, tick, _deg(0), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
