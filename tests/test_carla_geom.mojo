# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's engine-independent geometry, image and point cloud code.

Expected numbers come from hand calculation or from Python ports of the
C++ in `LibCarla/source/carla/geom`, `image`, `pointcloud` and
`third-party/simplify`, run apart from this suite. The Python works in
doubles and rounds to `float` where the C++ does.
"""

from core.buffer_geometry import NORMAL, POSITION, UV
from extensions.carla.bounding_box import BoundingBox
from extensions.carla.geo import (
    Ellipsoid,
    GeoLocation,
    GeoProjection,
    LAMBERT_CONFORMAL_CONIC,
    LambertConformalConicParams,
    OffsetTransform,
    ProjectionType,
    TRANSVERSE_MERCATOR,
    TransverseMercatorParams,
    UNIVERSAL_TRANSVERSE_MERCATOR,
    UniversalTransverseMercatorParams,
    UtmZone,
    WEB_MERCATOR,
    WebMercatorParams,
    create_ellipsoid,
    create_offset_transform,
    geo_location_to_transform_lambert_conformal_conic,
    geo_location_to_transform_transverse_mercator,
    geo_location_to_transform_universal_transverse_mercator,
    geo_location_to_transform_web_mercator,
    named_ellipsoid,
    parse_geo_projection_and_reference,
    parse_geo_reference,
    parse_projection_parameters,
    stod,
    stoll,
    transform_to_geo_location_lambert_conformal_conic,
    transform_to_geo_location_transverse_mercator,
    transform_to_geo_location_universal_transverse_mercator,
    transform_to_geo_location_web_mercator,
    xml_as_double,
)
from extensions.carla.image_convert import (
    CITY_SCAPES_PALETTE,
    ColorConverter,
    DEPTH,
    InstanceId,
    LOGARITHMIC_DEPTH,
    RAW,
    convert_in_place,
    convert_pixel,
    decode_instance_id,
    decode_instance_tag,
    decode_normal,
    encode_flow_image,
    encode_flow_pixel,
    encode_instance,
    gray_byte,
)
from extensions.carla.lidar import LidarPoint
from extensions.carla.math import (
    AccelerationVector,
    AngularVelocityVector,
    Vector3DInt,
    VelocityVector,
    distance_2d,
    distance_arc_to_point,
    distance_segment_to_point,
    distance_squared_2d,
    dot_2d,
    from_right_handed,
    generate_range,
    inverse_matrix,
    length_2d,
    make_unit_vector,
    make_unit_vector_2d,
    quaternion_forward_vector,
    quaternion_from_rotation,
    quaternion_inverse,
    quaternion_inverse_rotate,
    quaternion_right_vector,
    quaternion_up_vector,
    rotate_point_on_origin_2d,
    rotation_difference,
    rotation_from_quaternion,
    rotation_sum,
    rotations_equal,
    squared_length_2d,
    to_right_handed,
    transform_vector,
    transforms_equal,
    vector_abs,
    vector_angle,
)
from extensions.carla.mesh import CarlaMesh, MeshMaterial, format_fixed
from extensions.carla.pointcloud import (
    LidarDetection,
    SemanticLidarDetection,
    dump,
    save_to_disk,
    validate_file_path,
)
from extensions.carla.rtree import (
    PointCloudRtree,
    PointElement,
    PointFilter,
    SegmentCloudRtree,
    SegmentElement,
    SegmentFilter,
    segment_intersects_box,
)
from extensions.carla.sensor import ROAD, SemanticTag
from extensions.carla.simplification import Simplification
from extensions.carla.transform import CarlaRotation, CarlaTransform
from loaders.ply import parse_ply
from loaders.xml import XmlDocument, parse_xml
from math.bounds import Box3
from math.quaternion import Quaternion
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.collections import Dict
from std.math import inf, isinf, isnan, nan, sqrt
from std.os import rmdir
from std.os.path import exists
from std.pathlib import Path
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
    DEGREE_PER_SECOND,
    METER,
    METER_PER_SECOND,
    METER_PER_SECOND_SQUARED,
    PER_METER,
    RADIAN,
    Angle,
    InverseLength,
    Length,
)


def _rot(pitch: Float32, yaw: Float32, roll: Float32) -> CarlaRotation:
    var r = CarlaRotation(Angle(0, DEGREE), Angle(0, DEGREE), Angle(0, DEGREE))
    r.pitch = pitch
    r.yaw = yaw
    r.roll = roll
    return r


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _near(a: Vector3, b: Vector3, tol: Float64 = 1e-5) raises:
    assert_almost_equal(a.x, b.x, atol=tol)
    assert_almost_equal(a.y, b.y, atol=tol)
    assert_almost_equal(a.z, b.z, atol=tol)


def _same_color(a: Color, b: Color) raises:
    assert_equal(Int(a.r), Int(b.r))
    assert_equal(Int(a.g), Int(b.g))
    assert_equal(Int(a.b), Int(b.b))
    assert_equal(Int(a.a), Int(b.a))


# --- kinds -----------------------------------------------------------------


def test_kinds_are_checked() raises:
    assert_true(TRANSVERSE_MERCATOR.is_valid())
    assert_true(LAMBERT_CONFORMAL_CONIC.is_valid())
    assert_false(ProjectionType(-1).is_valid())
    assert_false(ProjectionType(4).is_valid())
    assert_true(UtmZone(1).is_valid())
    assert_true(UtmZone(60).is_valid())
    assert_false(UtmZone(0).is_valid())
    assert_false(UtmZone(61).is_valid())
    assert_true(RAW.is_valid())
    assert_true(CITY_SCAPES_PALETTE.is_valid())
    assert_false(ColorConverter(-1).is_valid())
    assert_false(ColorConverter(4).is_valid())
    assert_true(InstanceId(0).is_valid())
    assert_true(InstanceId(65535).is_valid())
    assert_false(InstanceId(-1).is_valid())
    assert_false(InstanceId(65536).is_valid())


# --- math ------------------------------------------------------------------


def test_two_dimensional_helpers() raises:
    var a = Vector3(1, 2, 30)
    var b = Vector3(4, 6, -7)
    assert_equal(dot_2d(a, b), 16.0)
    assert_equal(distance_squared_2d(a, b), 25.0)
    assert_equal(distance_2d(a, b).value, 5.0)
    assert_equal(squared_length_2d(b), 52.0)
    assert_almost_equal(length_2d(Vector3(3, 4, 9)), 5.0)
    _near(vector_abs(Vector3(-1, 2, -3)), Vector3(1, 2, 3))


def test_vector_angle_keeps_carla_nan() raises:
    assert_almost_equal(
        vector_angle(Vector3(1, 0, 0), Vector3(0, 2, 0)).to(DEGREE), 90.0
    )
    assert_almost_equal(
        vector_angle(Vector3(1, 1, 0), Vector3(1, 0, 0)).to(DEGREE),
        45.0,
        atol=1e-4,
    )
    assert_true(isnan(vector_angle(Vector3(0, 0, 0), Vector3(1, 0, 0)).value))
    # A cosine rounded past one gives NaN too, where `angle_to` clamps:
    # |(1, 1, 0)| squared is 1.9999999 in `float`, and 2 / 1.9999999 > 1.
    assert_true(isnan(vector_angle(Vector3(1, 1, 0), Vector3(1, 1, 0)).value))


def test_distance_segment_to_point() raises:
    # Python port of `Math::DistanceSegmentToPoint`.
    var r = distance_segment_to_point(
        Vector3(1, 2, 0), Vector3(0, 0, 0), Vector3(4, 0, 0)
    )
    assert_almost_equal(r[0].value, 1.0)
    assert_almost_equal(r[1].value, 2.0)
    r = distance_segment_to_point(
        Vector3(5, 1, 0), Vector3(0, 0, 0), Vector3(4, 0, 0)
    )
    assert_almost_equal(r[0].value, 4.0)
    assert_almost_equal(r[1].value, 1.4142135, atol=1e-6)
    r = distance_segment_to_point(
        Vector3(-2, 1, 0), Vector3(0, 0, 0), Vector3(4, 0, 0)
    )
    assert_almost_equal(r[0].value, 0.0)
    assert_almost_equal(r[1].value, 2.2360680, atol=1e-6)
    # A segment of no length in x-y: the distance to its start.
    r = distance_segment_to_point(
        Vector3(3, 4, 9), Vector3(0, 0, 1), Vector3(0, 0, 5)
    )
    assert_equal(r[0].value, 0.0)
    assert_almost_equal(r[1].value, 5.0)


def _arc(
    p: Vector3, length: Float32, curvature: Float32, heading: Float32 = 0
) -> Tuple[Length, Length]:
    return distance_arc_to_point(
        p,
        Vector3(0, 0, 0),
        _m(length),
        Angle(heading, RADIAN),
        InverseLength(curvature, PER_METER),
    )


def test_distance_arc_to_point() raises:
    # Python port of `Math::DistanceArcToPoint`.
    # The point at the center of the circle: as far from every point of
    # the arc.
    var center = _arc(Vector3(0, 10, 0), 20, 0.1)
    assert_equal(center[0].value, 0.0)
    assert_equal(center[1].value, 10.0)
    center = _arc(Vector3(0, -10, 0), 20, -0.1)
    assert_equal(center[0].value, 0.0)
    assert_equal(center[1].value, 10.0)
    # Across the circle from the start.
    var r = _arc(Vector3(0, -10, 0), 20, 0.1)
    assert_equal(r[0].value, 0.0)
    assert_almost_equal(r[1].value, 10.0, atol=1e-5)
    r = _arc(Vector3(0, 10, 0), 20, -0.1)
    assert_equal(r[0].value, 0.0)
    assert_almost_equal(r[1].value, 10.0, atol=1e-5)
    # On the arc's span.
    r = _arc(Vector3(5, -1, 0), 10, 0.1)
    assert_almost_equal(r[0].value, 4.266274931268761, atol=1e-4)
    assert_almost_equal(r[1].value, 2.0830459735945723, atol=1e-4)
    r = _arc(Vector3(5, 1, 0), 10, -0.1)
    assert_almost_equal(r[0].value, 4.266274931268761, atol=1e-4)
    assert_almost_equal(r[1].value, 2.0830459735945723, atol=1e-4)
    # Behind the start: the start is nearer.
    r = _arc(Vector3(-3, 0.5, 0), 10, 0.1)
    assert_equal(r[0].value, 0.0)
    assert_almost_equal(r[1].value, 3.0413812651491097, atol=1e-4)
    # Past the end: the end is nearer.
    r = _arc(Vector3(12, -8, 0), 5, 0.1)
    assert_equal(r[0].value, 5.0)
    assert_almost_equal(r[1].value, 11.705047990267152, atol=1e-4)
    # A heading and a start away from the origin.
    var moved = distance_arc_to_point(
        Vector3(2, 3, 0),
        Vector3(1, 1, 0),
        _m(4),
        Angle(0.5, RADIAN),
        InverseLength(0.2, PER_METER),
    )
    assert_almost_equal(moved[0].value, 2.290562835632075, atol=1e-4)
    assert_almost_equal(moved[1].value, 0.8475785199194228, atol=1e-4)


def test_rotate_point_and_range() raises:
    _near(
        rotate_point_on_origin_2d(Vector3(1, 0, 5), Angle(90, DEGREE)),
        Vector3(0, 1, 0),
    )
    var up = generate_range(2, 5)
    assert_equal(len(up), 4)
    assert_equal(up[0], 2)
    assert_equal(up[3], 5)
    var down = generate_range(3, 1)
    assert_equal(len(down), 3)
    assert_equal(down[0], 3)
    assert_equal(down[2], 1)
    assert_equal(len(generate_range(4, 4)), 1)


def test_make_unit_vector() raises:
    _near(make_unit_vector(Vector3(3, 0, 4)), Vector3(0.6, 0, 0.8))
    # At or below epsilon the vector comes back as it is.
    var tiny = Vector3(1e-8, 0, 0)
    assert_equal(make_unit_vector(tiny).x, Float32(1e-8))
    assert_equal(make_unit_vector(Vector3(0.5, 0, 0), 0.5).x, 0.5)
    # A negative epsilon counts as zero.
    assert_equal(make_unit_vector(Vector3(0.5, 0, 0), -1).x, 1.0)
    var v2 = make_unit_vector_2d(Vector2(0, -2))
    assert_equal(v2.y, -1.0)
    assert_equal(make_unit_vector_2d(Vector2(0, 0)).x, 0.0)


def test_vector3d_int() raises:
    var a = Vector3DInt(3, -4, 12)
    assert_equal(a.squared_length(), 169)
    assert_equal(a.length(), 13.0)
    # CARLA's 32-bit square would overflow; this one does not.
    assert_equal(Vector3DInt(65536, 0, 0).squared_length(), 4294967296)
    var s = a + Vector3DInt(1, 1, 1)
    assert_true(s == Vector3DInt(4, -3, 13))
    assert_true(a - Vector3DInt(3, -4, 12) == Vector3DInt(0, 0, 0))
    assert_true(a * 2 == Vector3DInt(6, -8, 24))
    # C++ division rounds toward zero.
    assert_true(Vector3DInt(7, -7, -8) / 2 == Vector3DInt(3, -3, -4))
    with assert_raises(contains="divided by zero"):
        _ = a / 0
    assert_false(a == Vector3DInt(9, -4, 12))
    assert_false(a == Vector3DInt(3, 9, 12))
    assert_false(a == Vector3DInt(3, -4, 9))
    assert_true(a != Vector3DInt(0, 0, 0))
    _near(a.to_location(), Vector3(3, -4, 12))
    assert_equal(String(a), "Vector3DInt(x=3, y=-4, z=12)")


def test_right_handed_and_unit_vectors() raises:
    _near(to_right_handed(Vector3(1, 2, 3)), Vector3(1, -2, 3))
    _near(from_right_handed(Vector3(1, 2, 3)), Vector3(1, -2, 3))
    var v = VelocityVector.from_centimeters_per_second(Vector3(100, -250, 0))
    assert_almost_equal(v.x.to(METER_PER_SECOND), 1.0)
    assert_almost_equal(v.y.to(METER_PER_SECOND), -2.5)
    _near(v.to_centimeters_per_second(), Vector3(100, -250, 0), 1e-4)
    _near(v.vector(), Vector3(1, -2.5, 0))
    assert_almost_equal(v.length().to(METER_PER_SECOND), 2.6925824, atol=1e-6)
    var a = AccelerationVector.from_centimeters_per_second_squared(
        Vector3(981, 0, -50)
    )
    assert_almost_equal(a.x.to(METER_PER_SECOND_SQUARED), 9.81, atol=1e-5)
    _near(a.to_centimeters_per_second_squared(), Vector3(981, 0, -50), 1e-3)
    _near(a.vector(), Vector3(9.81, 0, -0.5))
    var w = AngularVelocityVector.from_degrees_per_second(Vector3(90, 0, -45))
    # 90 degrees a second is pi / 2 radians a second.
    assert_almost_equal(w.x.value, 1.5707963, atol=1e-6)
    _near(w.to_degrees_per_second(), Vector3(90, 0, -45), 1e-4)


def test_quaternion_matches_carla() raises:
    # Yaw 90: the quaternion turns about z by -90 degrees in the
    # right-handed frame.
    var q = quaternion_from_rotation(_rot(0, 90, 0))
    assert_almost_equal(q.z, -0.70710678, atol=1e-6)
    assert_almost_equal(q.w, 0.70710678, atol=1e-6)
    _near(quaternion_forward_vector(q), Vector3(0, 1, 0))
    _near(quaternion_right_vector(q), Vector3(-1, 0, 0))
    _near(quaternion_up_vector(q), Vector3(0, 0, 1))
    # The basis agrees with the matrix of `CarlaRotation`.
    var r = _rot(20, -35, 50)
    var qr = quaternion_from_rotation(r)
    _near(quaternion_forward_vector(qr), r.forward_vector())
    _near(quaternion_right_vector(qr), r.right_vector())
    _near(quaternion_up_vector(qr), r.up_vector())
    var back = rotation_from_quaternion(qr)
    assert_almost_equal(back.pitch, 20.0, atol=1e-4)
    assert_almost_equal(back.yaw, -35.0, atol=1e-4)
    assert_almost_equal(back.roll, 50.0, atol=1e-4)
    # The sine of the pitch is clamped at both ends.
    var up = rotation_from_quaternion(Quaternion(0, 0.8, 0, 0.8))
    assert_almost_equal(up.pitch, 90.0, atol=1e-4)
    var down = rotation_from_quaternion(Quaternion(0, -0.8, 0, 0.8))
    assert_almost_equal(down.pitch, -90.0, atol=1e-4)
    # CARLA's inverse divides by the squared length.
    var inv = quaternion_inverse(Quaternion(0, 0, 0, 2))
    assert_equal(inv.w, 0.5)
    var id = quaternion_inverse(Quaternion(0, 0, 0, 0))
    assert_equal(id.w, 1.0)
    var v = Vector3(1, 2, 3)
    _near(quaternion_inverse_rotate(qr, qr.rotate(v)), v)


def test_rotation_arithmetic_and_equality() raises:
    var s = rotation_sum(_rot(1, 2, 3), _rot(10, 20, 30))
    assert_equal(s.pitch, 11.0)
    assert_equal(s.yaw, 22.0)
    assert_equal(s.roll, 33.0)
    var d = rotation_difference(_rot(1, 2, 3), _rot(10, 20, 30))
    assert_equal(d.pitch, -9.0)
    assert_equal(d.yaw, -18.0)
    assert_equal(d.roll, -27.0)
    assert_true(rotations_equal(_rot(1, 2, 3), _rot(1, 2, 3)))
    assert_false(rotations_equal(_rot(9, 2, 3), _rot(1, 2, 3)))
    assert_false(rotations_equal(_rot(1, 9, 3), _rot(1, 2, 3)))
    assert_false(rotations_equal(_rot(1, 2, 9), _rot(1, 2, 3)))
    # Each angle wraps to [-180, 180): 370 is 10, -190 is 170, and 180
    # is -180.
    assert_true(rotations_equal(_rot(370, -190, 180), _rot(10, 170, -180)))
    assert_true(rotations_equal(_rot(-360, 720, -540), _rot(0, 0, 180)))
    assert_false(rotations_equal(_rot(371, -190, 180), _rot(10, 170, -180)))
    assert_false(rotations_equal(_rot(370, -191, 180), _rot(10, 170, -180)))
    assert_false(rotations_equal(_rot(370, -190, 179), _rot(10, 170, -180)))
    # Magnitudes that sum to 180 are not the same angle.
    assert_false(rotations_equal(_rot(90, -100, 180), _rot(-90, 80, 0)))
    var t = CarlaTransform(_m(1), _m(2), _m(3), _rot(370, -190, 180))
    var u = CarlaTransform(_m(1), _m(2), _m(3), _rot(10, 170, -180))
    assert_true(transforms_equal(t, u))
    var w = CarlaTransform(_m(1), _m(2), _m(4), _rot(-90, 80, 0))
    assert_false(transforms_equal(t, w))
    assert_false(
        transforms_equal(t, CarlaTransform(_m(1), _m(2), _m(3), _rot(0, 0, 0)))
    )


def test_transform_vector_and_inverse_matrix() raises:
    var t = CarlaTransform(_m(4), _m(-2), _m(1), _rot(10, 70, -5))
    var v = Vector3(1, 2, 3)
    _near(transform_vector(t, v), t.rotation.rotate_vector(v))
    var m = inverse_matrix(t)
    var p = Vector3(0.5, -1, 7)
    var moved = t.transform_point(p)
    moved.apply_matrix4(m)
    _near(moved, p, 1e-4)
    # The product with the forward matrix is the identity.
    var identity = t.matrix() * m
    for i in range(16):
        var expected: Float32 = 1.0 if i % 5 == 0 else 0.0
        assert_almost_equal(identity.elements[i], expected, atol=1e-5)


# --- bounding box ------------------------------------------------------------


def test_bounding_box_contains_as_carla() raises:
    var box = BoundingBox(Vector3(1, 0, 0), Vector3(2, 1, 0.5))
    var at = CarlaTransform(_m(10), _m(0), _m(0), _rot(0, 90, 0))
    # The box's frame turned 90 degrees: local (x, y) is world (-y, x).
    assert_true(box.contains(Vector3(10, 2.5, 0), at))
    assert_true(box.contains(Vector3(9.5, 2, 0.4), at))
    assert_false(box.contains(Vector3(10, 3.5, 0), at))
    assert_false(box.contains(Vector3(8.9, 1, 0), at))
    assert_false(box.contains(Vector3(10, 1, 0.6), at))
    # The faces count as inside.
    var still = CarlaTransform(_m(0), _m(0), _m(0), _rot(0, 0, 0))
    assert_true(box.contains(Vector3(3, 1, 0.5), still))
    assert_true(box.contains(Vector3(-1, -1, -0.5), still))
    # The box's own rotation is not applied, as in CARLA.
    var turned = BoundingBox(
        Vector3(0, 0, 0), Vector3(2, 0.5, 0.5), _rot(0, 90, 0)
    )
    var origin = CarlaTransform(_m(0), _m(0), _m(0), _rot(0, 0, 0))
    assert_true(turned.contains(Vector3(1.5, 0, 0), origin))
    assert_false(turned.contains(Vector3(0, 1.5, 0), origin))


def test_bounding_box_vertices() raises:
    var box = BoundingBox(Vector3(1, 2, 3), Vector3(1, 2, 3), _rot(0, 90, 0))
    var local = box.local_vertices()
    assert_equal(len(local), 8)
    # (-1, -2, -3) turned by yaw 90 is (2, -1, -3).
    _near(local[0], Vector3(3, 1, 0))
    # (1, 2, 3) turned is (-2, 1, 3).
    _near(local[7], Vector3(-1, 3, 6))
    var plain = box.local_vertices_no_rotation()
    _near(plain[0], Vector3(0, 0, 0))
    _near(plain[1], Vector3(0, 0, 6))
    _near(plain[2], Vector3(0, 4, 0))
    _near(plain[4], Vector3(2, 0, 0))
    var world = box.world_vertices(
        CarlaTransform(_m(10), _m(0), _m(0), _rot(0, 0, 0))
    )
    _near(world[0], Vector3(13, 1, 0))
    var origin = BoundingBox(Vector3(1, 1, 1))
    _near(origin.local_vertices()[0], Vector3(-1, -1, -1))


def test_bounding_box_obb_equality_and_checks() raises:
    var box = BoundingBox(Vector3(1, 2, 3), Vector3(1, 2, 3), _rot(0, 90, 0))
    var obb = box.to_obb()
    _near(obb.axis(0), Vector3(0, 1, 0))
    _near(obb.axis(1), Vector3(-1, 0, 0))
    assert_true(obb.contains_point(Vector3(1, 2, 3)))
    var same = BoundingBox(Vector3(1, 2, 3), Vector3(1, 2, 3), _rot(0, 90, 0))
    assert_true(box == same)
    assert_false(
        box == BoundingBox(Vector3(0, 2, 3), Vector3(1, 2, 3), _rot(0, 90, 0))
    )
    assert_false(
        box == BoundingBox(Vector3(1, 2, 3), Vector3(1, 1, 3), _rot(0, 90, 0))
    )
    assert_false(
        box == BoundingBox(Vector3(1, 2, 3), Vector3(1, 2, 3), _rot(0, 0, 0))
    )
    assert_true(box != BoundingBox(Vector3(1, 1, 1)))
    with assert_raises(contains="half size"):
        _ = BoundingBox(Vector3(0, 0, -1))
    assert_equal(
        String(BoundingBox(Vector3(1, 2, 3), Vector3(4, 5, 6))),
        (
            "BoundingBox(location=(1.0, 2.0, 3.0), extent=(4.0, 5.0, 6.0),"
            " Rotation(pitch=0.0, yaw=0.0, roll=0.0))"
        ),
    )


# --- geo ------------------------------------------------------------------------


def _wgs84() -> Ellipsoid:
    return Ellipsoid(6378137.0, 298.257223563)


def _close_geo(
    g: GeoLocation,
    lat: Float64,
    lon: Float64,
    alt: Float64,
    tol: Float64 = 1e-9,
) raises:
    assert_almost_equal(g.latitude_degrees, lat, atol=tol)
    assert_almost_equal(g.longitude_degrees, lon, atol=tol)
    assert_almost_equal(g.altitude_meters, alt, atol=1e-6)


def test_ellipsoids() raises:
    var sphere = Ellipsoid()
    assert_equal(sphere.a_meters, 6378137.0)
    assert_true(isinf(sphere.f_inv))
    assert_equal(sphere.f(), 0.0)
    assert_equal(sphere.e2(), 0.0)
    var wgs = _wgs84()
    assert_almost_equal(wgs.b_meters(), 6356752.314245179, atol=1e-6)
    assert_almost_equal(wgs.e2(), 0.0066943799901413165, atol=1e-15)
    assert_almost_equal(wgs.ep2(), 0.006739496742276435, atol=1e-15)
    var e = Ellipsoid(6378137.0, 300.0)
    e.from_b(6356752.314245179)
    assert_almost_equal(e.f_inv, 298.257223563, atol=1e-6)
    e.from_f(0.5)
    assert_equal(e.f_inv, 2.0)
    for name in [
        "wgs84",
        "GRS80",
        "intl",
        "bessel",
        "clrk66",
        "airy",
        "wgs72",
        "wgs66",
        "Sphere",
    ]:
        assert_true(Bool(named_ellipsoid(name)))
    assert_equal(named_ellipsoid("WGS84").value().f_inv, 298.257223563)
    assert_equal(named_ellipsoid("grs80").value().f_inv, 298.257222101)
    assert_equal(named_ellipsoid("intl").value().a_meters, 6378388.0)
    assert_equal(named_ellipsoid("bessel").value().a_meters, 6377397.155)
    assert_equal(named_ellipsoid("clrk66").value().f_inv, 294.9786982138)
    assert_equal(named_ellipsoid("airy").value().a_meters, 6377563.396)
    assert_equal(named_ellipsoid("wgs72").value().f_inv, 298.26)
    assert_equal(named_ellipsoid("wgs66").value().a_meters, 6378145.0)
    assert_true(isinf(named_ellipsoid("sphere").value().f_inv))
    assert_false(Bool(named_ellipsoid("mars")))
    assert_true(wgs == _wgs84())
    assert_false(wgs == Ellipsoid(1.0, 298.257223563))
    assert_false(wgs == Ellipsoid(6378137.0, 1.0))


def test_geo_location_basics() raises:
    var g = GeoLocation()
    assert_equal(g.latitude_degrees, 0.0)
    var h = GeoLocation(49.5, 8.25, 100.0)
    assert_almost_equal(h.latitude_angle().to(DEGREE), 49.5, atol=1e-4)
    assert_almost_equal(h.longitude_angle().to(DEGREE), 8.25, atol=1e-4)
    assert_true(h == GeoLocation(49.5, 8.25, 100.0))
    assert_false(h == GeoLocation(0, 8.25, 100.0))
    assert_false(h == GeoLocation(49.5, 0, 100.0))
    assert_false(h == GeoLocation(49.5, 8.25, 0))
    assert_true(h != g)
    assert_equal(
        String(h), "GeoLocation(latitude=49.5, longitude=8.25, altitude=100.0)"
    )


def test_offset_transform() raises:
    var off = OffsetTransform(-691000.0, 5334000.0, -500.0, 0.3)
    var p = Vector3(100, -200, 3)
    # Python port of `ApplyTransformation`.
    var q = off.apply(p)
    var tx = 100.0 - 691000.0
    var ty = 200.0 + 5334000.0
    var c = 0.9553364891256060  # cos(-0.3)
    var s = -0.2955202066613396  # sin(-0.3)
    assert_almost_equal(Float64(q.x), tx * c - ty * s, atol=0.1)
    assert_almost_equal(Float64(q.y), tx * s + ty * c, atol=0.5)
    assert_equal(q.z, -497.0)
    _near(off.apply_inverse(off.apply(p)), p, 0.5)
    var zero = OffsetTransform(1.0, 2.0, 3.0, 0.0)
    _near(zero.apply(Vector3(1, 1, 1)), Vector3(2, 1, 4))
    _near(zero.apply_inverse(Vector3(2, 1, 4)), Vector3(1, 1, 1))
    assert_true(zero == OffsetTransform(1.0, 2.0, 3.0, 0.0))
    assert_false(zero == OffsetTransform(0.0, 2.0, 3.0, 0.0))
    assert_false(zero == OffsetTransform(1.0, 0.0, 3.0, 0.0))
    assert_false(zero == OffsetTransform(1.0, 2.0, 0.0, 0.0))
    var turned = OffsetTransform(1.0, 2.0, 3.0, 0.0)
    turned.offset_cos_h = 0.5
    assert_false(zero == turned)
    turned = OffsetTransform(1.0, 2.0, 3.0, 0.0)
    turned.offset_sin_h = 0.5
    assert_false(zero == turned)


def test_transverse_mercator() raises:
    # Python port of `GeoProjection.cpp`.
    var p = TransverseMercatorParams(49.0, 8.0, 1.0, 0.0, 0.0, _wgs84())
    var loc = geo_location_to_transform_transverse_mercator(
        GeoLocation(49.0005, 8.0012, 110.0), p
    )
    assert_equal(loc.x, Float32(87.8052749633789))
    assert_equal(loc.y, Float32(55.60556411743164))
    assert_equal(loc.z, 110.0)
    _close_geo(
        transform_to_geo_location_transverse_mercator(
            Vector3(87.5, 55.25, 3), p
        ),
        49.00049680509446,
        8.001195827876666,
        3.0,
    )
    var k = TransverseMercatorParams(
        40.0, -3.0, 0.9996, 500000.0, 100.0, Ellipsoid()
    )
    var loc2 = geo_location_to_transform_transverse_mercator(
        GeoLocation(40.4, -3.7, 0.0), k
    )
    assert_equal(loc2.x, Float32(440681.65625))
    assert_equal(loc2.y, Float32(44844.83984375))
    _close_geo(
        transform_to_geo_location_transverse_mercator(
            Vector3(500123.0, 44000.0, 1.0), k
        ),
        40.39451820794246,
        -2.9985486219892903,
        1.0,
    )
    var d = TransverseMercatorParams()
    var loc3 = geo_location_to_transform_transverse_mercator(
        GeoLocation(0.001, 0.002, 0.0), d
    )
    assert_equal(loc3.x, Float32(222.63897705078125))
    assert_equal(loc3.y, Float32(111.31948852539062))


def test_universal_transverse_mercator() raises:
    var p = UniversalTransverseMercatorParams(UtmZone(32), True, _wgs84(), None)
    var loc = geo_location_to_transform_universal_transverse_mercator(
        GeoLocation(48.137, 11.575, 519.0), p
    )
    assert_equal(loc.x, Float32(691567.3125))
    assert_equal(loc.y, Float32(5334734.5))
    _close_geo(
        transform_to_geo_location_universal_transverse_mercator(
            Vector3(691607.0, 5334760.0, 519.0), p
        ),
        48.1372187690073,
        11.575544272481187,
        519.0,
    )
    var south = UniversalTransverseMercatorParams(
        UtmZone(56), False, _wgs84(), None
    )
    var loc2 = geo_location_to_transform_universal_transverse_mercator(
        GeoLocation(-33.8688, 151.2093, 5.0), south
    )
    assert_equal(loc2.x, Float32(334368.625))
    assert_equal(loc2.y, Float32(6250948.5))
    _close_geo(
        transform_to_geo_location_universal_transverse_mercator(
            Vector3(334369.0, 6250948.0, 5.0), south
        ),
        -33.8688031703491,
        151.20930389397503,
        5.0,
    )
    var off = UniversalTransverseMercatorParams(
        UtmZone(32),
        True,
        _wgs84(),
        OffsetTransform(-691000.0, 5334000.0, -500.0, 0.3),
    )
    var loc3 = geo_location_to_transform_universal_transverse_mercator(
        GeoLocation(48.137, 11.575, 519.0), off
    )
    assert_equal(loc3.x, Float32(-224842.359375))
    assert_equal(loc3.y, Float32(33161.35546875))
    assert_equal(loc3.z, 1019.0)
    _close_geo(
        transform_to_geo_location_universal_transverse_mercator(
            Vector3(100, -200, 3), off
        ),
        47.72004390590829,
        14.551917431670812,
        -497.0,
    )
    var bad = UniversalTransverseMercatorParams(
        UtmZone(0), True, _wgs84(), None
    )
    with assert_raises(contains="UTM zone"):
        _ = geo_location_to_transform_universal_transverse_mercator(
            GeoLocation(), bad
        )
    with assert_raises(contains="UTM zone"):
        _ = transform_to_geo_location_universal_transverse_mercator(
            Vector3(0, 0, 0), bad
        )


def test_web_mercator() raises:
    var p = WebMercatorParams(_wgs84())
    var loc = geo_location_to_transform_web_mercator(
        GeoLocation(41.3874, 2.1686, 12.0), p
    )
    assert_equal(loc.x, Float32(241407.453125))
    assert_equal(loc.y, Float32(5069652.0))
    _close_geo(
        transform_to_geo_location_web_mercator(
            Vector3(241404.0, 5069621.0, 12.0), p
        ),
        41.38719038164845,
        2.16856902847589,
        12.0,
    )


def test_lambert_conformal_conic() raises:
    var p = LambertConformalConicParams(
        46.5,
        44.0,
        49.0,
        3.0,
        700000.0,
        6600000.0,
        Ellipsoid(6378137.0, 298.257222101),
    )
    var loc = geo_location_to_transform_lambert_conformal_conic(
        GeoLocation(47.3, 3.2, 0.0), p
    )
    assert_equal(loc.x, Float32(715112.875))
    assert_equal(loc.y, Float32(6688872.5))
    _close_geo(
        transform_to_geo_location_lambert_conformal_conic(
            Vector3(715000.0, 6640000.0, 7.0), p
        ),
        46.85999818430525,
        3.196893441068682,
        7.0,
    )
    # On a sphere the first step already converges.
    var sphere = LambertConformalConicParams(
        30.0, 20.0, 60.0, 0.0, 0.0, 0.0, Ellipsoid()
    )
    var s = geo_location_to_transform_lambert_conformal_conic(
        GeoLocation(31.0, 1.0, 0.0), sphere
    )
    assert_equal(s.x, Float32(90935.6953125))
    assert_equal(s.y, Float32(106770.34375))
    _close_geo(
        transform_to_geo_location_lambert_conformal_conic(
            Vector3(111000.0, 111000.0, 0.0), sphere
        ),
        31.037459113050357,
        1.2212677787816075,
        0.0,
    )
    # A cone that opens south has a negative constant.
    var south = LambertConformalConicParams(
        -40.0, -30.0, -50.0, 145.0, 0.0, 0.0, _wgs84()
    )
    var t = geo_location_to_transform_lambert_conformal_conic(
        GeoLocation(-40.0, 150.0, 0.0), south
    )
    assert_equal(t.x, Float32(420273.53125))
    assert_equal(t.y, Float32(-11852.34765625))
    _close_geo(
        transform_to_geo_location_lambert_conformal_conic(
            Vector3(400000.0, 20000.0, 0.0), south
        ),
        -39.719327929028836,
        149.7390445636331,
        0.0,
    )
    # A very flat ellipsoid does not converge in ten steps; CARLA stops.
    var flat = LambertConformalConicParams(
        30.0, 20.0, 60.0, 10.0, 0.0, 0.0, Ellipsoid(6378137.0, 2.0)
    )
    _close_geo(
        transform_to_geo_location_lambert_conformal_conic(
            Vector3(400000.0, 300000.0, 0.0), flat
        ),
        36.72753853193094,
        13.927287122570126,
        0.0,
        1e-7,
    )


def test_geo_projection_dispatches() raises:
    var geo = GeoLocation(48.137, 11.575, 519.0)
    var tm = GeoProjection()
    assert_true(tm.projection_type == TRANSVERSE_MERCATOR)
    _near(
        tm.geo_location_to_transform(geo),
        geo_location_to_transform_transverse_mercator(
            geo, TransverseMercatorParams()
        ),
    )
    var utm_params = UniversalTransverseMercatorParams(
        UtmZone(32), True, _wgs84(), None
    )
    var utm = GeoProjection.make(utm_params)
    assert_true(utm.projection_type == UNIVERSAL_TRANSVERSE_MERCATOR)
    var at = utm.geo_location_to_transform(geo)
    assert_equal(at.x, Float32(691567.3125))
    _close_geo(
        utm.transform_to_geo_location(Vector3(691607.0, 5334760.0, 519.0)),
        48.1372187690073,
        11.575544272481187,
        519.0,
    )
    var web = GeoProjection.make(WebMercatorParams(_wgs84()))
    assert_true(web.projection_type == WEB_MERCATOR)
    assert_equal(
        web.geo_location_to_transform(GeoLocation(41.3874, 2.1686, 12.0)).x,
        Float32(241407.453125),
    )
    _close_geo(
        web.transform_to_geo_location(Vector3(241404.0, 5069621.0, 12.0)),
        41.38719038164845,
        2.16856902847589,
        12.0,
    )
    var lcc = GeoProjection.make(
        LambertConformalConicParams(
            46.5,
            44.0,
            49.0,
            3.0,
            700000.0,
            6600000.0,
            Ellipsoid(6378137.0, 298.257222101),
        )
    )
    assert_true(lcc.projection_type == LAMBERT_CONFORMAL_CONIC)
    assert_equal(
        lcc.geo_location_to_transform(GeoLocation(47.3, 3.2, 0.0)).y,
        Float32(6688872.5),
    )
    _close_geo(
        lcc.transform_to_geo_location(Vector3(715000.0, 6640000.0, 7.0)),
        46.85999818430525,
        3.196893441068682,
        7.0,
    )
    var tmp = GeoProjection.make(
        TransverseMercatorParams(49.0, 8.0, 1.0, 0.0, 0.0, _wgs84())
    )
    _close_geo(
        tmp.transform_to_geo_location(Vector3(87.5, 55.25, 3)),
        49.00049680509446,
        8.001195827876666,
        3.0,
    )
    var broken = GeoProjection()
    broken.projection_type = ProjectionType(7)
    with assert_raises(contains="projection type"):
        _ = broken.geo_location_to_transform(geo)
    with assert_raises(contains="projection type"):
        _ = broken.transform_to_geo_location(Vector3(0, 0, 0))


def test_projection_params_compare() raises:
    var tm = TransverseMercatorParams(1, 2, 3, 4, 5, _wgs84())
    assert_true(tm == TransverseMercatorParams(1, 2, 3, 4, 5, _wgs84()))
    assert_false(tm == TransverseMercatorParams(0, 2, 3, 4, 5, _wgs84()))
    assert_false(tm == TransverseMercatorParams(1, 0, 3, 4, 5, _wgs84()))
    assert_false(tm == TransverseMercatorParams(1, 2, 0, 4, 5, _wgs84()))
    assert_false(tm == TransverseMercatorParams(1, 2, 3, 0, 5, _wgs84()))
    assert_false(tm == TransverseMercatorParams(1, 2, 3, 4, 0, _wgs84()))
    assert_false(tm == TransverseMercatorParams(1, 2, 3, 4, 5, Ellipsoid()))
    assert_true(tm != TransverseMercatorParams())
    var off = OffsetTransform(1, 2, 3, 0.5)
    var u = UniversalTransverseMercatorParams(UtmZone(3), True, _wgs84(), off)
    assert_true(
        u == UniversalTransverseMercatorParams(UtmZone(3), True, _wgs84(), off)
    )
    assert_false(
        u == UniversalTransverseMercatorParams(UtmZone(4), True, _wgs84(), off)
    )
    assert_false(
        u == UniversalTransverseMercatorParams(UtmZone(3), False, _wgs84(), off)
    )
    assert_false(
        u
        == UniversalTransverseMercatorParams(UtmZone(3), True, Ellipsoid(), off)
    )
    assert_false(
        u == UniversalTransverseMercatorParams(UtmZone(3), True, _wgs84(), None)
    )
    assert_false(
        u
        == UniversalTransverseMercatorParams(
            UtmZone(3), True, _wgs84(), OffsetTransform(9, 2, 3, 0.5)
        )
    )
    assert_true(
        UniversalTransverseMercatorParams()
        == UniversalTransverseMercatorParams()
    )
    assert_true(WebMercatorParams() == WebMercatorParams(Ellipsoid()))
    assert_false(WebMercatorParams() == WebMercatorParams(_wgs84()))
    var l = LambertConformalConicParams(1, 2, 3, 4, 5, 6, _wgs84())
    assert_true(l == LambertConformalConicParams(1, 2, 3, 4, 5, 6, _wgs84()))
    assert_false(l == LambertConformalConicParams(0, 2, 3, 4, 5, 6, _wgs84()))
    assert_false(l == LambertConformalConicParams(1, 0, 3, 4, 5, 6, _wgs84()))
    assert_false(l == LambertConformalConicParams(1, 2, 0, 4, 5, 6, _wgs84()))
    assert_false(l == LambertConformalConicParams(1, 2, 3, 0, 5, 6, _wgs84()))
    assert_false(l == LambertConformalConicParams(1, 2, 3, 4, 0, 6, _wgs84()))
    assert_false(l == LambertConformalConicParams(1, 2, 3, 4, 5, 0, _wgs84()))
    assert_false(
        l == LambertConformalConicParams(1, 2, 3, 4, 5, 6, Ellipsoid())
    )
    var d = LambertConformalConicParams()
    assert_equal(d.lat_1_degrees, -5.0)
    assert_equal(d.lat_2_degrees, 5.0)


# --- geoReference parsing ----------------------------------------------------


def test_number_readers() raises:
    assert_equal(stod(" 12.5abc"), 12.5)
    assert_equal(stod("-.5"), -0.5)
    assert_equal(stod("5."), 5.0)
    assert_equal(stod("+1e+2x"), 100.0)
    assert_equal(stod("1e"), 1.0)
    assert_equal(stod("2E-1"), 0.2)
    assert_equal(stod("2ex"), 2.0)
    with assert_raises(contains="no number"):
        _ = stod("   ")
    assert_equal(stod("0x10"), 0.0)
    assert_equal(stod("0.000"), 0.0)
    assert_true(isinf(stod("-Infinity")))
    assert_true(stod("-inf") < 0)
    assert_true(isnan(stod("NaN")))
    with assert_raises(contains="no number"):
        _ = stod("abc")
    with assert_raises(contains="no number"):
        _ = stod("+.e1")
    with assert_raises(contains="no number"):
        _ = stod("")
    with assert_raises(contains="out of range"):
        _ = stod("1e999")
    with assert_raises(contains="out of range"):
        _ = stod("1e-400")
    with assert_raises(contains="out of range"):
        _ = stod("4e-320")
    assert_equal(xml_as_double("abc"), 0.0)
    assert_equal(xml_as_double("2.5m"), 2.5)
    assert_equal(stoll(" -42x"), -42)
    assert_equal(stoll("+7"), 7)
    assert_equal(stoll("9223372036854775807"), 9223372036854775807)
    assert_equal(stoll("-9223372036854775808"), -9223372036854775807 - 1)
    with assert_raises(contains="out of range"):
        _ = stoll("9223372036854775808")
    with assert_raises(contains="out of range"):
        _ = stoll("-9223372036854775809")
    with assert_raises(contains="no number"):
        _ = stoll("x1")
    with assert_raises(contains="no number"):
        _ = stoll("-")
    with assert_raises(contains="no number"):
        _ = stoll("")


def test_parse_projection_parameters_as_the_regex() raises:
    var p = parse_projection_parameters(
        "+proj=tmerc +a='x y' +b=\"q\" +c +d=+5 +e= +9 ++k=1 +g=\"abc +h='x"
        " +i=1\t+j=2+last"
    )
    assert_equal(p["proj"], "tmerc")
    assert_equal(p["a"], "'x y'")
    assert_equal(p["b"], '"q"')
    assert_equal(p["c"], "")
    assert_equal(p["d"], "")
    assert_equal(p["5"], "")
    assert_equal(p["e"], "")
    assert_equal(p["9"], "")
    assert_equal(p["k"], "1")
    assert_equal(p["g"], '"abc')
    assert_equal(p["h"], "'x")
    assert_equal(p["i"], "1")
    assert_equal(p["j"], "2")
    assert_equal(p["last"], "")
    # A later key replaces an earlier one; a bare plus is skipped.
    var q = parse_projection_parameters("+x=1 +x=2 + +")
    assert_equal(q["x"], "2")
    assert_equal(len(q), 1)
    # A value cut off by the end of the text.
    var end = parse_projection_parameters('+a="')
    assert_equal(end["a"], '"')
    var bare = parse_projection_parameters("+b=")
    assert_equal(bare["b"], "")


def _params(text: String) -> Dict[String, String]:
    return parse_projection_parameters(text)


def test_create_ellipsoid() raises:
    assert_true(create_ellipsoid(_params("")) == _wgs84())
    assert_true(
        create_ellipsoid(_params("+ellps=intl")) == Ellipsoid(6378388.0, 297.0)
    )
    assert_true(
        create_ellipsoid(_params("+datum=WGS84 +ellps=bessel"))
        == Ellipsoid(6377397.155, 299.1528128)
    )
    # An unknown `ellps` hides the `datum`, and nothing else is set.
    assert_true(
        create_ellipsoid(_params("+ellps=mars +datum=intl")) == _wgs84()
    )
    assert_true(
        create_ellipsoid(_params("+datum=airy"))
        == Ellipsoid(6377563.396, 299.3249646)
    )
    var a = create_ellipsoid(_params("+a=6000000"))
    assert_equal(a.a_meters, 6000000.0)
    assert_true(isinf(a.f_inv))
    var b = create_ellipsoid(_params("+a=100 +b=99"))
    assert_almost_equal(b.f_inv, 100.0, atol=1e-9)
    var f = create_ellipsoid(_params("+f=0.25 +rf=300"))
    assert_equal(f.f_inv, 300.0)
    var only_f = create_ellipsoid(_params("+f=0.25"))
    assert_equal(only_f.f_inv, 4.0)
    with assert_raises(contains="no number"):
        _ = create_ellipsoid(_params("+a=big"))


def test_create_offset_transform() raises:
    assert_false(Bool(create_offset_transform(Dict[String, Float64]())))
    var d = Dict[String, Float64]()
    d["x"] = 1.0
    d["hdg"] = 0.0
    d["other"] = 9.0
    var off = create_offset_transform(d)
    assert_true(off.value() == OffsetTransform(1.0, 0.0, 0.0, 0.0))


def test_parse_geo_projection_and_reference() raises:
    var none = Dict[String, Float64]()
    var tm = parse_geo_projection_and_reference(
        (
            "+proj=tmerc +lat_0=49 +lon_0=8 +k=0.9996 +x_0=500000 +y_0=10"
            " +datum=WGS84 +units=m"
        ),
        none,
    )
    assert_true(tm[0].projection_type == TRANSVERSE_MERCATOR)
    assert_true(
        tm[0].transverse_mercator
        == TransverseMercatorParams(49.0, 8.0, 0.9996, 500000.0, 10.0, _wgs84())
    )
    assert_true(tm[1] == GeoLocation(49.0, 8.0, 0.0))
    assert_true(tm[0].proj_string.startswith("+proj=tmerc"))
    var offsets = Dict[String, Float64]()
    offsets["x"] = 10.0
    offsets["hdg"] = 0.5
    var utm = parse_geo_projection_and_reference(
        "+proj=utm +zone=56 +south +ellps=GRS80", offsets
    )
    assert_true(utm[0].projection_type == UNIVERSAL_TRANSVERSE_MERCATOR)
    ref u = utm[0].universal_transverse_mercator
    assert_true(u.zone == UtmZone(56))
    assert_false(u.north)
    assert_true(u.ellps == Ellipsoid(6378137.0, 298.257222101))
    assert_true(u.offset.value() == OffsetTransform(10.0, 0.0, 0.0, 0.5))
    assert_true(utm[1] == GeoLocation(0.0, 153.0, 0.0))
    var fractional = parse_geo_projection_and_reference(
        "+proj=utm +zone=31.5", none
    )
    assert_true(fractional[0].universal_transverse_mercator.zone == UtmZone(31))
    assert_true(fractional[0].universal_transverse_mercator.north)
    assert_false(Bool(fractional[0].universal_transverse_mercator.offset))
    assert_equal(fractional[1].longitude_degrees, 3.0)
    var no_zone = parse_geo_projection_and_reference("+proj=utm", none)
    assert_true(no_zone[0].universal_transverse_mercator.zone == UtmZone(31))
    assert_equal(no_zone[1].longitude_degrees, 0.0)
    with assert_raises(contains="UTM zone"):
        _ = parse_geo_projection_and_reference("+proj=utm +zone=61", none)
    with assert_raises(contains="no number"):
        _ = parse_geo_projection_and_reference("+proj=utm +zone=north", none)
    var merc = parse_geo_projection_and_reference(
        "+proj=merc +a=6378137 +b=6378137", none
    )
    assert_true(merc[0].projection_type == WEB_MERCATOR)
    assert_true(merc[0].web_mercator.ellps == Ellipsoid())
    assert_equal(merc[0].proj_string, "+proj=merc +a=6378137 +b=6378137")
    assert_true(merc[1] == GeoLocation())
    var lcc = parse_geo_projection_and_reference(
        (
            "+proj=lcc +lat_1=44 +lat_2=49 +lat_0=46.5 +lon_0=3 +x_0=700000"
            " +y_0=6600000 +ellps=GRS80"
        ),
        none,
    )
    assert_true(lcc[0].projection_type == LAMBERT_CONFORMAL_CONIC)
    assert_true(
        lcc[0].lambert_conformal_conic
        == LambertConformalConicParams(
            46.5,
            44.0,
            49.0,
            3.0,
            700000.0,
            6600000.0,
            Ellipsoid(6378137.0, 298.257222101),
        )
    )
    assert_true(lcc[1] == GeoLocation(46.5, 3.0, 0.0))
    var lcc_default = parse_geo_projection_and_reference("+proj=lcc", none)
    assert_equal(lcc_default[0].lambert_conformal_conic.lat_1_degrees, -5.0)
    assert_equal(lcc_default[0].lambert_conformal_conic.lat_2_degrees, 5.0)
    var missing = parse_geo_projection_and_reference("+ellps=intl", none)
    assert_true(missing[0].projection_type == TRANSVERSE_MERCATOR)
    assert_true(
        missing[0].transverse_mercator.ellps == Ellipsoid(6378388.0, 297.0)
    )
    assert_equal(missing[0].proj_string, "")
    assert_true(missing[1] == GeoLocation())
    var other = parse_geo_projection_and_reference("+proj=ortho", none)
    assert_true(other[0].projection_type == TRANSVERSE_MERCATOR)
    assert_true(other[0].transverse_mercator.ellps == _wgs84())
    assert_equal(other[0].proj_string, "")


def test_parse_geo_reference_from_opendrive() raises:
    var document = parse_xml(
        "<OpenDRIVE><header><geoReference><![CDATA[+proj=utm +zone=32"
        ' +datum=WGS84]]></geoReference><offset x="-691000"'
        ' y="5334000" z="-500" hdg="0.3" note="n/a"/></header>'
        "</OpenDRIVE>"
    )
    var read = parse_geo_reference(document)
    ref u = read[0].universal_transverse_mercator
    assert_true(u.zone == UtmZone(32))
    assert_true(
        u.offset.value() == OffsetTransform(-691000.0, 5334000.0, -500.0, 0.3)
    )
    assert_equal(read[1].longitude_degrees, 9.0)
    # The GNSS reading of a CARLA location, as the sensor computes it.
    _close_geo(
        read[0].transform_to_geo_location(Vector3(100, -200, 3)),
        47.72004390590829,
        14.551917431670812,
        -497.0,
    )
    var no_offset = parse_geo_reference(
        parse_xml(
            "<OpenDRIVE><header><geoReference>+proj=utm +zone=5</geoReference>"
            "<offset/></header></OpenDRIVE>"
        )
    )
    assert_false(Bool(no_offset[0].universal_transverse_mercator.offset))
    var bare = parse_geo_reference(
        parse_xml("<OpenDRIVE><header/></OpenDRIVE>")
    )
    assert_true(bare[0].projection_type == TRANSVERSE_MERCATOR)
    assert_true(bare[0].transverse_mercator.ellps == _wgs84())
    var no_header = parse_geo_reference(parse_xml("<OpenDRIVE/>"))
    assert_true(no_header[1] == GeoLocation())
    var other_root = parse_geo_reference(
        parse_xml(
            "<Other><header><geoReference>+proj=merc</geoReference></header></Other>"
        )
    )
    assert_true(other_root[0].projection_type == TRANSVERSE_MERCATOR)
    var empty = parse_geo_reference(XmlDocument())
    assert_true(empty[0].projection_type == TRANSVERSE_MERCATOR)
    var only_reference = parse_geo_reference(
        parse_xml(
            "<OpenDRIVE><header><geoReference>+proj=merc</geoReference>"
            "</header></OpenDRIVE>"
        )
    )
    assert_true(only_reference[0].projection_type == WEB_MERCATOR)


# --- R-tree ---------------------------------------------------------------------


struct _Lcg(Movable):
    var state: UInt64

    def __init__(out self, seed: UInt64):
        self.state = seed

    def next(mut self) -> Float32:
        self.state = self.state * 6364136223846793005 + 1442695040888963407
        return Float32(Int((self.state >> 40) & 0xFFFF)) / 65536.0


def _brute_points(
    points: List[Vector3], p: Vector3, count: Int, even_only: Bool
) -> List[Int]:
    """A plain scan: sort by distance, then by insertion."""
    var keys = List[Float64]()
    var order = List[Int]()
    for i in range(len(points)):
        if even_only and i % 2 != 0:
            continue
        var dx = Float64(points[i].x) - Float64(p.x)
        var dy = Float64(points[i].y) - Float64(p.y)
        var dz = Float64(points[i].z) - Float64(p.z)
        keys.append(dx * dx + dy * dy + dz * dz)
        order.append(i)
    # Selection sort on (key, index).
    var out = List[Int]()
    var used = List[Bool](length=len(order), fill=False)
    for _ in range(min(count, len(order))):
        var best = -1
        for j in range(len(order)):
            if used[j]:
                continue
            if best < 0 or keys[j] < keys[best]:
                best = j
        used[best] = True
        out.append(order[best])
    return out^


@fieldwise_init
struct _EvenPoints(ImplicitlyCopyable, PointFilter):
    def accepts(self, element: PointElement) -> Bool:
        return element.value % 2 == 0


@fieldwise_init
struct _EvenSegments(ImplicitlyCopyable, SegmentFilter):
    def accepts(self, element: SegmentElement) -> Bool:
        return element.start_value % 2 == 0


def test_point_rtree_matches_a_scan() raises:
    var tree = PointCloudRtree()
    assert_equal(tree.get_tree_size(), 0)
    assert_equal(len(tree.get_nearest_neighbours(Vector3(0, 0, 0), 3)), 0)
    var rng = _Lcg(7)
    var points = List[Vector3]()
    for i in range(400):
        var p = Vector3(rng.next() * 100, rng.next() * 100, rng.next() * 5)
        points.append(p)
        if i % 3 == 0:
            tree.insert_element(PointElement(p, i))
        elif i % 3 == 1:
            tree.insert_element(p, i)
        else:
            var batch = List[PointElement]()
            batch.append(PointElement(p, i))
            tree.insert_elements(batch)
    assert_equal(tree.get_tree_size(), 400)
    for _ in range(12):
        var p = Vector3(
            rng.next() * 110 - 5, rng.next() * 110 - 5, rng.next() * 6
        )
        var got = tree.get_nearest_neighbours(p, 7)
        var want = _brute_points(points, p, 7, False)
        assert_equal(len(got), 7)
        for k in range(7):
            assert_equal(got[k].value, want[k])
        var filtered = tree.get_nearest_neighbours_with_filter(
            p, _EvenPoints(), 5
        )
        var want_even = _brute_points(points, p, 5, True)
        for k in range(5):
            assert_equal(filtered[k].value, want_even[k])
    assert_equal(len(tree.get_nearest_neighbours(Vector3(0, 0, 0), 0)), 0)
    assert_equal(len(tree.get_nearest_neighbours(Vector3(0, 0, 0), 1000)), 400)
    with assert_raises(contains="count"):
        _ = tree.get_nearest_neighbours(Vector3(0, 0, 0), -1)


def test_point_rtree_holds_duplicates() raises:
    # Forty copies of one point fill several leaves whose boxes all hold
    # the query, so leaves and points tie at distance zero.
    var tree = PointCloudRtree()
    tree.insert_elements(List[PointElement]())
    for i in range(40):
        tree.insert_element(Vector3(5, 5, 5), i)
    tree.insert_element(Vector3(6, 5, 5), 40)
    var got = tree.get_nearest_neighbours(Vector3(5, 5, 5), 41)
    assert_equal(len(got), 41)
    for k in range(41):
        assert_equal(got[k].value, k)


def test_point_rtree_splits_a_lopsided_node() raises:
    # Sixteen points in a small cube and one far away: the far one seeds a
    # group that must then take the last entries to reach the minimum.
    var tree = PointCloudRtree()
    var rng = _Lcg(3)
    var points = List[Vector3]()
    for i in range(17):
        var p = Vector3(rng.next(), rng.next(), rng.next())
        if i == 16:
            p = Vector3(100, 100, 100)
        points.append(p)
        tree.insert_element(p, i)
    for i in range(17, 60):
        var p = Vector3(rng.next() * 3, rng.next() * 3, rng.next() * 3)
        points.append(p)
        tree.insert_element(p, i)
    var query = Vector3(1, 1, 1)
    var got = tree.get_nearest_neighbours(query, 10)
    var want = _brute_points(points, query, 10, False)
    for k in range(10):
        assert_equal(got[k].value, want[k])
    var far = tree.get_nearest_neighbours(Vector3(99, 99, 99), 1)
    assert_equal(far[0].value, 16)


def test_point_rtree_breaks_ties_by_insertion() raises:
    var tree = PointCloudRtree()
    tree.insert_element(Vector3(1, 0, 0), 10)
    tree.insert_element(Vector3(-1, 0, 0), 11)
    tree.insert_element(Vector3(0, 1, 0), 12)
    tree.insert_element(Vector3(0, 0, 3), 13)
    var got = tree.get_nearest_neighbours(Vector3(0, 0, 0), 4)
    assert_equal(got[0].value, 10)
    assert_equal(got[1].value, 11)
    assert_equal(got[2].value, 12)
    assert_equal(got[3].value, 13)
    _near(got[3].point, Vector3(0, 0, 3))


def _segment_distance2(a: Vector3, b: Vector3, p: Vector3) -> Float64:
    # The squared distance to the nearest point of the segment, by the
    # clamped projection.
    var ab = (
        Float64(b.x) - Float64(a.x),
        Float64(b.y) - Float64(a.y),
        Float64(b.z) - Float64(a.z),
    )
    var ap = (
        Float64(p.x) - Float64(a.x),
        Float64(p.y) - Float64(a.y),
        Float64(p.z) - Float64(a.z),
    )
    var len2 = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2]
    var t = (ap[0] * ab[0] + ap[1] * ab[1] + ap[2] * ab[2]) / len2
    t = min(max(t, 0.0), 1.0)
    var x = ap[0] - ab[0] * t
    var y = ap[1] - ab[1] * t
    var z = ap[2] - ab[2] * t
    return x * x + y * y + z * z


def test_segment_rtree_matches_a_scan() raises:
    var tree = SegmentCloudRtree()
    tree.insert_elements(List[SegmentElement]())
    var rng = _Lcg(11)
    var starts = List[Vector3]()
    var ends = List[Vector3]()
    for i in range(300):
        var a = Vector3(rng.next() * 200, rng.next() * 200, 0)
        var b = a + Vector3(rng.next() * 6 - 3, rng.next() * 6 - 3, rng.next())
        starts.append(a)
        ends.append(b)
        if i % 3 == 0:
            tree.insert_element(a, b, i, i + 1000)
        elif i % 3 == 1:
            tree.insert_element(SegmentElement(a, b, i, i + 1000))
        else:
            var batch = List[SegmentElement]()
            batch.append(SegmentElement(a, b, i, i + 1000))
            tree.insert_elements(batch)
    assert_equal(tree.get_tree_size(), 300)
    for _ in range(8):
        var p = Vector3(rng.next() * 200, rng.next() * 200, rng.next())
        var got = tree.get_nearest_neighbours(p, 4)
        assert_equal(len(got), 4)
        # Each is at least as near as the next, and none left out is nearer.
        var worst = 0.0
        for k in range(4):
            var d = _segment_distance2(got[k].start, got[k].end, p)
            assert_true(d >= worst - 1e-6)
            worst = d
            assert_equal(got[k].end_value, got[k].start_value + 1000)
        var taken = List[Int]()
        for k in range(4):
            taken.append(got[k].start_value)
        for i in range(300):
            if i in taken:
                continue
            assert_true(
                _segment_distance2(starts[i], ends[i], p) >= worst - 1e-6
            )
        var even = tree.get_nearest_neighbours_with_filter(
            p, _EvenSegments(), 3
        )
        assert_equal(len(even), 3)
        for k in range(3):
            assert_equal(even[k].start_value % 2, 0)
    var box = Box3(Vector3(50, 50, -1), Vector3(90, 80, 2))
    var hits = tree.get_intersections(box)
    var expected = List[Int]()
    for i in range(300):
        if segment_intersects_box(starts[i], ends[i], box):
            expected.append(i)
    assert_true(len(expected) > 5)
    assert_equal(len(hits), len(expected))
    for k in range(len(hits)):
        assert_equal(hits[k].start_value, expected[k])
    assert_equal(len(tree.get_intersections(Box3.empty())), 0)


def test_segment_box_intersection() raises:
    var box = Box3(Vector3(0, 0, 0), Vector3(1, 1, 1))
    # Through the box.
    assert_true(
        segment_intersects_box(Vector3(-1, 0.5, 0.5), Vector3(2, 0.5, 0.5), box)
    )
    # Inside.
    assert_true(
        segment_intersects_box(
            Vector3(0.2, 0.2, 0.2), Vector3(0.4, 0.4, 0.4), box
        )
    )
    # Touching a face counts.
    assert_true(
        segment_intersects_box(Vector3(1, 0.5, 0.5), Vector3(2, 0.5, 0.5), box)
    )
    # Stopping short.
    assert_false(
        segment_intersects_box(
            Vector3(-2, 0.5, 0.5), Vector3(-1, 0.5, 0.5), box
        )
    )
    # Reversed direction.
    assert_true(
        segment_intersects_box(Vector3(2, 0.5, 0.5), Vector3(-1, 0.5, 0.5), box)
    )
    # Parallel to an axis and outside its slab.
    assert_false(
        segment_intersects_box(Vector3(-1, 2, 0.5), Vector3(2, 2, 0.5), box)
    )
    assert_false(
        segment_intersects_box(Vector3(-1, -2, 0.5), Vector3(2, -2, 0.5), box)
    )
    # Passing by a corner.
    assert_false(
        segment_intersects_box(
            Vector3(-1, 0.5, 0.5), Vector3(0.5, 2.5, 0.5), box
        )
    )
    assert_false(
        segment_intersects_box(
            Vector3(0.5, 0.5, 0.5), Vector3(0.6, 0.5, 0.5), Box3.empty()
        )
    )


# --- mesh --------------------------------------------------------------------------


def _quad() -> List[Vector3]:
    var v = List[Vector3]()
    v.append(Vector3(0, 0, 0))
    v.append(Vector3(0, 1, 0))
    v.append(Vector3(1, 0, 0))
    v.append(Vector3(1, 1, 0))
    return v^


def _ints(values: List[Int], expected: List[Int]) raises:
    assert_equal(len(values), len(expected))
    for i in range(len(values)):
        assert_equal(values[i], expected[i])


def test_format_fixed_as_printf() raises:
    # Python's `'%.*f'`, which rounds the exact value half to even.
    assert_equal(format_fixed(1.5, 6), "1.500000")
    assert_equal(format_fixed(0.1, 6), "0.100000")
    assert_equal(format_fixed(0.0078125, 6), "0.007812")
    assert_equal(format_fixed(0.0234375, 6), "0.023438")
    assert_equal(format_fixed(-0.0, 6), "-0.000000")
    assert_equal(
        format_fixed(1e30, 6), "1000000015047466219876688855040.000000"
    )
    assert_equal(format_fixed(1e-40, 6), "0.000000")
    assert_equal(format_fixed(2.5, 0), "2")
    assert_equal(format_fixed(3.5, 0), "4")
    assert_equal(format_fixed(-1e-9, 4), "-0.0000")
    assert_equal(format_fixed(123.456, 4), "123.4560")
    assert_equal(format_fixed(-7.25, 2), "-7.25")
    assert_equal(format_fixed(0.03125, 4), "0.0312")
    assert_equal(format_fixed(1e-7, 6), "0.000000")
    assert_equal(format_fixed(inf[DType.float32](), 6), "inf")
    assert_equal(format_fixed(-inf[DType.float32](), 6), "-inf")
    assert_equal(format_fixed(nan[DType.float32](), 6), "nan")
    with assert_raises(contains="digits"):
        _ = format_fixed(1, 19)
    with assert_raises(contains="digits"):
        _ = format_fixed(1, -1)


def test_triangle_strip_and_fan() raises:
    var mesh = CarlaMesh()
    mesh.add_triangle_strip(List[Vector3]())
    assert_equal(mesh.vertices_num(), 0)
    mesh.add_triangle_strip(_quad())
    # (1, 2, 3), then (4, 3, 2), by hand from `Mesh::AddTriangleStrip`.
    _ints(mesh.indexes, [1, 2, 3, 4, 3, 2])
    mesh.add_triangle_strip(_quad())
    _ints(mesh.indexes, [1, 2, 3, 4, 3, 2, 5, 6, 7, 8, 7, 6])
    var fan = CarlaMesh()
    fan.add_triangle_fan(_quad())
    _ints(fan.indexes, [1, 2, 3, 1, 3, 4])
    assert_equal(fan.indexes_num(), 6)
    assert_equal(fan.last_vertex_index(), 4)


def test_materials_open_and_close() raises:
    var mesh = CarlaMesh()
    mesh.end_material()  # none open: nothing
    mesh.add_material("road")
    mesh.end_material()  # no index yet: nothing
    assert_equal(mesh.materials[0].index_end, 0)
    assert_false(mesh.is_valid())
    mesh.add_triangle_strip(_quad())
    assert_false(mesh.is_valid())  # "road" is still open
    mesh.add_material("sidewalk")  # closes "road" at 6
    assert_equal(mesh.materials[0].index_end, 6)
    mesh.add_index(1)
    mesh.end_material()  # 7 is not a multiple of three: nothing
    assert_equal(mesh.materials[1].index_end, 0)
    mesh.add_index(2)
    mesh.add_index(3)
    mesh.end_material()
    assert_equal(mesh.materials[1].index_start, 6)
    assert_equal(mesh.materials[1].index_end, 9)
    mesh.end_material()  # already closed: nothing
    assert_equal(mesh.materials[1].index_end, 9)
    mesh.add_index(4)
    mesh.add_material("grass")  # 10 is not a multiple of three: no start
    assert_equal(len(mesh.materials), 2)
    var closing = CarlaMesh()
    closing.add_material("a")
    closing.add_index(1)
    closing.add_material("b")  # closes nothing (1 index), starts nothing
    assert_equal(len(closing.materials), 1)
    assert_equal(closing.materials[0].index_end, 0)


def test_is_valid() raises:
    assert_false(CarlaMesh().is_valid())
    var odd = CarlaMesh()
    odd.add_vertex(Vector3(0, 0, 0))
    assert_true(odd.is_valid())
    odd.add_index(1)
    assert_false(odd.is_valid())
    assert_equal(odd.generate_obj(), "")
    assert_equal(odd.generate_obj_for_recast(), "")
    assert_equal(odd.generate_ply(), "Invalid Mesh")
    with assert_raises(contains="not valid"):
        _ = odd.to_buffer_geometry()


def _textured() -> CarlaMesh:
    var mesh = CarlaMesh()
    mesh.add_material("road")
    mesh.add_triangle_strip(_quad())
    mesh.end_material()
    var uvs = List[Vector2]()
    uvs.append(Vector2(0, 0))
    uvs.append(Vector2(0, 1))
    uvs.append(Vector2(1, 0))
    uvs.append(Vector2(1, 1))
    mesh.add_uvs(uvs)
    for _ in range(4):
        mesh.add_normal(Vector3(0, 0, 1))
    return mesh^


def test_generate_obj_as_carla() raises:
    var mesh = _textured()
    mesh.vertices[3] = Vector3(1, 1, 0.125)
    mesh.add_material("line")
    mesh.add_index(1)
    mesh.add_index(4)
    mesh.add_index(2)
    mesh.end_material()
    var expected = String(
        "# List of geometric vertices, with (x, y, z) coordinates.\n"
        "v 0.000000 0.000000 0.000000\n"
        "v 0.000000 1.000000 0.000000\n"
        "v 1.000000 0.000000 0.000000\n"
        "v 1.000000 1.000000 0.125000\n"
        "\n# List of texture coordinates, in (u, v) coordinates, these will"
        " vary between 0 and 1.\n"
        "vt 0.000000 0.000000\n"
        "vt 0.000000 1.000000\n"
        "vt 1.000000 0.000000\n"
        "vt 1.000000 1.000000\n"
        "\n# List of vertex normals in (x, y, z) form; normals might not be"
        " unit vectors.\n"
        "vn 0.000000 0.000000 1.000000\n"
        "vn 0.000000 0.000000 1.000000\n"
        "vn 0.000000 0.000000 1.000000\n"
        "vn 0.000000 0.000000 1.000000\n"
        "\n# Polygonal face element.\n"
        "\nusemtl road\n"
        "f 1 2 3\n"
        "f 4 3 2\n"
        "\nusemtl line\n"
        "f 1 4 2\n"
    )
    assert_equal(mesh.generate_obj(), expected)
    var recast = String(
        "# List of geometric vertices, with (x, y, z) coordinates.\n"
        "v 0.000000 0.000000 0.000000\n"
        "v 0.000000 0.000000 1.000000\n"
        "v 1.000000 0.000000 0.000000\n"
        "v 1.000000 0.125000 1.000000\n"
        "\n# Polygonal face element.\n"
        "\nusemtl road\n"
        "f 1 3 2\n"
        "f 4 2 3\n"
        "\nusemtl line\n"
        "f 1 2 4\n"
    )
    assert_equal(mesh.generate_obj_for_recast(), recast)
    # Faces after the last material, and a mesh of vertices alone.
    var tail = CarlaMesh()
    tail.add_material("a")
    tail.add_triangle_strip(_quad())
    tail.end_material()
    tail.add_triangle_fan(_quad())
    var text = tail.generate_obj()
    assert_true(
        text.endswith("\nusemtl a\nf 1 2 3\nf 4 3 2\nf 5 6 7\nf 5 7 8\n")
    )
    var points = CarlaMesh()
    points.add_vertex(Vector3(1, 2, 3))
    assert_equal(
        points.generate_obj(),
        (
            "# List of geometric vertices, with (x, y, z) coordinates.\n"
            "v 1.000000 2.000000 3.000000\n"
        ),
    )
    assert_equal(
        points.generate_obj_for_recast(),
        (
            "# List of geometric vertices, with (x, y, z) coordinates.\n"
            "v 1.000000 3.000000 2.000000\n"
        ),
    )


def test_to_buffer_geometry() raises:
    var mesh = _textured()
    var three = mesh.to_buffer_geometry()
    assert_true(three.is_indexed())
    _ints(three.index, [0, 1, 2, 3, 2, 1])
    ref positions = three.attribute_view(String(POSITION))
    # CARLA (0, 1, 0) is three.js (0, 0, 1).
    _near(positions.vector3(1), Vector3(0, 0, 1))
    _near(three.attribute_view(String(NORMAL)).vector3(0), Vector3(0, 1, 0))
    assert_true(three.has_attribute(String(UV)))
    assert_equal(len(three.groups), 1)
    assert_equal(three.groups[0].start, 0)
    assert_equal(three.groups[0].count, 6)
    var carla = mesh.to_buffer_geometry(False)
    _near(carla.attribute_view(String(POSITION)).vector3(1), Vector3(0, 1, 0))
    _near(carla.attribute_view(String(NORMAL)).vector3(0), Vector3(0, 0, 1))
    # A strip in CARLA's frame faces up in three.js's.
    var a = positions.vector3(0)
    var b = positions.vector3(1)
    var c = positions.vector3(2)
    var n = b - a
    n.cross(c - a)
    assert_true(n.y > 0)
    var bare = CarlaMesh()
    bare.add_triangle_strip(_quad())
    bare.add_normal(Vector3(0, 0, 1))
    var plain = bare.to_buffer_geometry()
    assert_false(plain.has_attribute(String(NORMAL)))
    assert_false(plain.has_attribute(String(UV)))
    var cloud = CarlaMesh()
    cloud.add_vertex(Vector3(1, 2, 3))
    var dots = cloud.to_buffer_geometry()
    assert_equal(len(dots.index), 0)
    var wrong = CarlaMesh()
    wrong.add_vertex(Vector3(0, 0, 0))
    wrong.indexes = [1, 1, 2]
    with assert_raises(contains="name a vertex"):
        _ = wrong.to_buffer_geometry()
    wrong.indexes = [0, 1, 1]
    with assert_raises(contains="name a vertex"):
        _ = wrong.to_buffer_geometry()


def test_generate_ply_reads_back() raises:
    var mesh = _textured()
    var text = mesh.generate_ply()
    assert_true(text.startswith("ply\nformat ascii 1.0\n"))
    var geometry = parse_ply(List[UInt8](text.as_bytes()))
    assert_equal(geometry.vertex_count(), 4)
    assert_equal(geometry.triangle_count(), 2)
    _near(
        geometry.attribute_view(String(POSITION)).vector3(1), Vector3(0, 1, 0)
    )


def test_concat_and_join() raises:
    var left = CarlaMesh()
    left.add_triangle_strip(_quad())
    var right = CarlaMesh()
    right.add_material("r")
    right.add_triangle_strip(_quad())
    right.end_material()
    var joined = left.copy()
    joined.concat_mesh(right, 2)
    # By hand from `Mesh::ConcatMesh`: the seam of two, then the rest.
    _ints(
        joined.indexes,
        [1, 2, 3, 4, 3, 2, 3, 4, 5, 4, 6, 5, 5, 6, 7, 8, 7, 6],
    )
    assert_equal(joined.vertices_num(), 8)
    # CARLA moves the materials by the index count before the seam.
    assert_equal(joined.materials[0].index_start, 6)
    assert_equal(joined.materials[0].index_end, 12)
    with assert_raises(contains="link count"):
        joined.concat_mesh(right, 5)
    with assert_raises(contains="link count"):
        joined.concat_mesh(right, -1)
    var empty = CarlaMesh()
    with assert_raises(contains="link count"):
        empty.concat_mesh(right, 1)
    # One vertex a side makes no seam; a mesh of vertices alone adds no
    # index and no material.
    var single = left.copy()
    single.concat_mesh(right, 1)
    _ints(single.indexes, [1, 2, 3, 4, 3, 2, 5, 6, 7, 8, 7, 6])
    var cloud = CarlaMesh()
    cloud.add_vertex(Vector3(9, 9, 9))
    var dotted = left.copy()
    dotted.concat_mesh(cloud, 0)
    assert_equal(dotted.vertices_num(), 5)
    assert_equal(dotted.indexes_num(), 6)
    # A mesh that is not valid is appended as `+=` appends it.
    var invalid = CarlaMesh()
    var appended = left.copy()
    appended.concat_mesh(invalid, 2)
    assert_equal(appended.vertices_num(), 4)
    var sum = left + right
    _ints(sum.indexes, [1, 2, 3, 4, 3, 2, 5, 6, 7, 8, 7, 6])
    assert_equal(sum.materials[0].index_start, 6)
    var grow = left.copy()
    grow += _textured()
    assert_equal(len(grow.uvs), 4)
    assert_equal(len(grow.normals), 4)
    assert_equal(grow.materials[0].index_end, 12)


def test_mesh_constructor_takes_lists() raises:
    var mesh = CarlaMesh(_quad(), List[Vector3](), [1, 2, 3], List[Vector2]())
    assert_true(mesh.is_valid())
    assert_equal(mesh.indexes_num(), 3)
    mesh.add_uv(Vector2(0.5, 0.5))
    assert_equal(len(mesh.uvs), 1)
    var material = MeshMaterial("x", 0, 3)
    mesh.materials.append(material^)
    assert_true(mesh.is_valid())


# --- simplification ----------------------------------------------------------------


def _grid(
    n: Int,
    bumpy: Bool,
    a: Int = 7,
    b: Int = 3,
    m: Int = 4,
    scale: Float32 = 0.25,
) -> CarlaMesh:
    # The same grid as the Python reference: z = scale ((a i + b j) mod m).
    var mesh = CarlaMesh()
    for j in range(n + 1):
        for i in range(n + 1):
            var z: Float32 = 0.0
            if bumpy:
                z = scale * Float32((i * a + j * b) % m)
            mesh.add_vertex(Vector3(Float32(i), Float32(j), z))
    for j in range(n):
        for i in range(n):
            var a = j * (n + 1) + i + 1
            var b = a + 1
            var c = a + (n + 1)
            var d = c + 1
            mesh.indexes.extend([a, b, d, a, d, c])
    return mesh^


def _vertices(mesh: CarlaMesh, expected: List[Float64]) raises:
    assert_equal(len(mesh.vertices) * 3, len(expected))
    for i in range(len(mesh.vertices)):
        assert_almost_equal(
            Float64(mesh.vertices[i].x), expected[i * 3], atol=1e-6
        )
        assert_almost_equal(
            Float64(mesh.vertices[i].y), expected[i * 3 + 1], atol=1e-6
        )
        assert_almost_equal(
            Float64(mesh.vertices[i].z), expected[i * 3 + 2], atol=1e-6
        )


def test_simplify_a_flat_grid() raises:
    # Python port of `Simplify::simplify_mesh`.
    var mesh = _grid(4, False)
    mesh.add_normal(Vector3(0, 0, 1))
    # A vertex no triangle uses is dropped.
    mesh.add_vertex(Vector3(99, 99, 99))
    Simplification(0.5).simplificate(mesh)
    _vertices(
        mesh,
        [
            0, 0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0, 4, 0, 0, 0, 1, 0, 4, 1, 0,
            0, 2, 0, 2.0625, 2, 0, 4, 2, 0, 0, 3, 0, 4, 3, 0, 0, 4, 0, 1, 4, 0,
            2, 4, 0, 3, 4, 0, 4, 4, 0,
        ],
    )  # fmt: skip
    _ints(
        mesh.indexes,
        [
            1, 2, 9, 1, 9, 6, 2, 3, 9, 3, 4, 9, 4, 5, 7, 4, 7, 9, 6, 9, 8,
            9, 7, 10, 8, 9, 11, 9, 10, 12, 11, 9, 14, 11, 14, 13, 9, 15, 14,
            9, 16, 15, 9, 12, 17, 9, 17, 16,
        ],
    )  # fmt: skip
    # The normals are kept, as CARLA keeps them.
    assert_equal(len(mesh.normals), 1)


def test_simplify_a_bumpy_grid() raises:
    var mesh = _grid(4, True)
    Simplification(0.3).simplificate(mesh)
    _vertices(
        mesh,
        [
            0, 0, 0, 1, 0, 0.75, 2, 0, 0.5, 3, 0, 0.25, 4, 0, 0, 0, 1, 0.75,
            4, 1, 0.75, 0, 2, 0.5, 2.0219781398773193, 2.0219781398773193,
            0.2967033088207245, 4, 2, 0.5, 0, 3, 0.25, 4, 3, 0.25, 0, 4, 0,
            1, 4, 0.75, 2, 4, 0.5, 3, 4, 0.25, 4, 4, 0,
        ],
    )  # fmt: skip
    assert_equal(mesh.indexes_num(), 48)


def test_simplify_refuses_a_flip() raises:
    # This grid has collapses that would turn a neighbor over; they are
    # skipped.
    var mesh = _grid(3, True, 1, 4, 5, 0.5)
    Simplification(0.2).simplificate(mesh)
    _vertices(
        mesh,
        [
            0, 0, 0, 1, 0, 0.5, 2, 0, 1, 3, 0, 1.5, 0, 1, 2, 1.5, 1.5, 0, 3, 1,
            1, 0, 2, 1.5, 1, 2, 2, 3, 2, 0.5, 0, 3, 1, 1, 3, 1.5, 2, 3, 2, 3, 3,
            0,
        ],
    )  # fmt: skip
    _ints(
        mesh.indexes,
        [
            1, 2, 6, 1, 6, 5, 2, 3, 6, 3, 4, 7, 3, 7, 6, 5, 6, 9, 5, 9, 8, 6,
            7, 10, 8, 9, 12, 8, 12, 11, 9, 6, 13, 9, 13, 12, 6, 10, 14, 6, 14,
            13,
        ],
    )  # fmt: skip


def test_simplify_a_closed_cube() raises:
    var mesh = CarlaMesh()
    var corners: List[Float64] = [
        0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 2, 0, 1, 2, 0, 2, 0, 0, 2, 1,
        0, 2, 2, 2, 0, 0, 2, 1, 0, 2, 0, 1, 2, 1, 1, 2, 2, 0, 2, 2, 1, 2, 0, 2,
        2, 1, 2, 2, 2, 2, 1, 0, 0, 1, 0, 1, 1, 0, 2, 1, 2, 0, 1, 2, 1, 1, 2, 2,
        1, 1, 0, 1, 1, 2,
    ]  # fmt: skip
    for i in range(26):
        mesh.add_vertex(
            Vector3(
                Float32(corners[i * 3]),
                Float32(corners[i * 3 + 1]),
                Float32(corners[i * 3 + 2]),
            )
        )
    mesh.indexes = [
        1, 2, 4, 1, 4, 3, 2, 5, 6, 2, 6, 4, 3, 4, 8, 3, 8, 7, 4, 6, 9, 4, 9, 8,
        10, 11, 13, 10, 13, 12, 11, 14, 15, 11, 15, 13, 12, 13, 17, 12, 17, 16,
        13, 15, 18, 13, 18, 17, 1, 19, 20, 1, 20, 2, 19, 10, 12, 19, 12, 20,
        2, 20, 21, 2, 21, 5, 20, 12, 16, 20, 16, 21, 7, 8, 23, 7, 23, 22, 8, 9,
        24, 8, 24, 23, 22, 23, 15, 22, 15, 14, 23, 24, 18, 23, 18, 15, 1, 3,
        25, 1, 25, 19, 3, 7, 22, 3, 22, 25, 19, 25, 11, 19, 11, 10, 25, 22, 14,
        25, 14, 11, 5, 21, 26, 5, 26, 6, 21, 16, 17, 21, 17, 26, 6, 26, 24, 6,
        24, 9, 26, 17, 18, 26, 18, 24,
    ]  # fmt: skip
    Simplification(0.5).simplificate(mesh)
    _vertices(
        mesh,
        [
            0, 0, 0, 0, 0, 2, 0, 2, 0, 0, 2, 2, 2, 0, 0, 2, 0, 1, 2, 2, 0, 2, 1,
            2, 2, 2, 2, 1, 0, 0, 2, 0, 2, 1, 2, 0, 1, 2, 2, 1, 1, 0,
        ],
    )  # fmt: skip
    _ints(
        mesh.indexes,
        [
            1, 2, 3, 3, 2, 4, 5, 7, 6, 6, 8, 11, 6, 7, 9, 6, 9, 8, 1, 10, 11,
            10, 5, 6, 10, 6, 11, 1, 11, 2, 3, 4, 13, 3, 13, 12, 12, 13, 9, 12,
            9, 7, 1, 3, 14, 1, 14, 10, 3, 12, 14, 10, 14, 5, 14, 12, 7, 14, 7,
            5, 2, 11, 8, 2, 13, 4, 2, 8, 9, 2, 9, 13,
        ],
    )  # fmt: skip


def test_simplify_a_degenerate_triangle() raises:
    var mesh = _grid(3, False)
    mesh.indexes.extend([1, 1, 2])
    Simplification(0.4).simplificate(mesh)
    _vertices(
        mesh,
        [
            0, 0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0, 0, 1, 0, 1.5, 1.5, 0, 3, 1, 0,
            0, 2, 0, 3, 2, 0, 0, 3, 0, 1, 3, 0, 2, 3, 0, 3, 3, 0,
        ],
    )  # fmt: skip
    _ints(
        mesh.indexes,
        [
            1, 2, 6, 1, 6, 5, 2, 3, 6, 3, 4, 7, 3, 7, 6, 5, 6, 8, 6, 7, 9, 8,
            6, 11, 8, 11, 10, 6, 12, 11, 6, 9, 13, 6, 13, 12, 1, 1, 2,
        ],
    )  # fmt: skip


def test_simplify_edges() raises:
    # Two indices make no triangle, and the unused vertices go.
    var two = CarlaMesh(_quad(), List[Vector3](), [1, 2], List[Vector2]())
    Simplification(0.5).simplificate(two)
    assert_equal(two.vertices_num(), 0)
    assert_equal(two.indexes_num(), 0)
    # A rate of one keeps every triangle.
    var keep = _grid(2, False)
    Simplification(1.0).simplificate(keep)
    assert_equal(keep.indexes_num(), 24)
    with assert_raises(contains="needs indices"):
        var one = CarlaMesh(_quad(), List[Vector3](), [1], List[Vector2]())
        Simplification(0.5).simplificate(one)
    with assert_raises(contains="name a vertex"):
        var bad = CarlaMesh(
            _quad(), List[Vector3](), [1, 2, 9], List[Vector2]()
        )
        Simplification(0.5).simplificate(bad)
    with assert_raises(contains="name a vertex"):
        var zero = CarlaMesh(
            _quad(), List[Vector3](), [0, 2, 3], List[Vector2]()
        )
        Simplification(0.5).simplificate(zero)
    # No vertex and no triangle: nothing to do.
    var nothing = CarlaMesh(
        List[Vector3](), List[Vector3](), [1, 2], List[Vector2]()
    )
    Simplification(0.5).simplificate(nothing)
    assert_equal(nothing.indexes_num(), 0)
    with assert_raises(contains="finite"):
        var square = _grid(1, False)
        Simplification(nan[DType.float32]()).simplificate(square)
    with assert_raises(contains="not negative"):
        var square = _grid(1, False)
        Simplification(-0.5).simplificate(square)


# --- point cloud -------------------------------------------------------------------


def test_dump_lidar_as_carla() raises:
    var points = List[LidarDetection]()
    points.append(LidarDetection(Vector3(1.5, -2.25, 0.03125), 0.9))
    points.append(
        LidarDetection.from_lidar_point(LidarPoint(Vector3(10, 0, -1), 0.5, 3))
    )
    assert_equal(
        dump(points),
        (
            "ply\nformat ascii 1.0\nelement vertex 2\n"
            "property float32 x\nproperty float32 y\nproperty float32 z\n"
            "property float32 I\nend_header\n"
            "1.5000 -2.2500 0.0312 0.9000\n"
            "10.0000 0.0000 -1.0000 0.5000\n"
        ),
    )
    var semantic = List[SemanticLidarDetection]()
    semantic.append(SemanticLidarDetection(Vector3(1, 2, 3), 0.5, 7, 14))
    assert_equal(
        dump(semantic),
        (
            "ply\nformat ascii 1.0\nelement vertex 1\n"
            "property float32 x\nproperty float32 y\nproperty float32 z\n"
            "property float32 CosAngle\nproperty uint32 ObjIdx\n"
            "property uint32 ObjTag\nend_header\n"
            "1.0000 2.0000 3.0000 0.5000 7 14\n"
        ),
    )
    assert_equal(
        dump(List[LidarDetection]()),
        (
            "ply\nformat ascii 1.0\nelement vertex 0\n"
            "property float32 x\nproperty float32 y\nproperty float32 z\n"
            "property float32 I\nend_header\n"
        ),
    )


def test_validate_file_path() raises:
    if exists("out/carla_geom/fresh"):
        rmdir("out/carla_geom/fresh")
    assert_equal(
        validate_file_path("out/carla_geom/fresh/a", ".ply"),
        "out/carla_geom/fresh/a.ply",
    )
    assert_true(exists("out/carla_geom/fresh"))
    assert_equal(
        validate_file_path("out/carla_geom/a.txt", ".ply"),
        "out/carla_geom/a.ply",
    )
    assert_true(exists("out/carla_geom"))
    assert_equal(
        validate_file_path("out/carla_geom/scan", ".ply"),
        "out/carla_geom/scan.ply",
    )
    assert_equal(
        validate_file_path("out/carla_geom/b.ply", ".ply"),
        "out/carla_geom/b.ply",
    )
    assert_equal(
        validate_file_path("out/carla_geom/.hidden", ".ply"),
        "out/carla_geom/.hidden.ply",
    )
    assert_equal(
        validate_file_path("out/carla_geom/..", ".ply"), "out/carla_geom/...ply"
    )
    assert_equal(
        validate_file_path("out/carla_geom/x.y/name", ".ply"),
        "out/carla_geom/x.y/name.ply",
    )
    assert_equal(validate_file_path("plain.txt", ""), "plain.txt")
    assert_equal(validate_file_path("plain", ".ply"), "plain.ply")


def test_save_to_disk() raises:
    var points = List[LidarDetection]()
    points.append(LidarDetection(Vector3(1, 2, 3), 1))
    var path = save_to_disk("out/carla_geom/cloud/scan.bin", points)
    assert_equal(path, "out/carla_geom/cloud/scan.ply")
    assert_equal(Path(path).read_text(), dump(points))


# --- image conversion -----------------------------------------------------------------


def test_convert_pixels() raises:
    # Half of full scale: code 0x7FFFFF, gray 0.49999997, byte 127.
    var depth = Color(255, 255, 127)
    _same_color(convert_pixel(depth, DEPTH), Color(127, 127, 127, 255))
    # Full scale is one: byte 255. Log of one is one.
    _same_color(
        convert_pixel(Color(255, 255, 255), DEPTH), Color(255, 255, 255)
    )
    _same_color(
        convert_pixel(Color(255, 255, 255), LOGARITHMIC_DEPTH),
        Color(255, 255, 255),
    )
    # Zero depth: the log gray floor 0.005, byte 1 (0.005 255 + 0.5 = 1.775).
    _same_color(
        convert_pixel(Color(0, 0, 0), LOGARITHMIC_DEPTH), Color(1, 1, 1)
    )
    # One percent of full scale: 1 + ln(0.01) / 5.70378 = 0.192608, byte 49.
    var one_percent = Color(0x5C, 0x8F, 0x02)  # 167772 = 0x028F5C
    _same_color(
        convert_pixel(one_percent, LOGARITHMIC_DEPTH), Color(49, 49, 49)
    )
    _same_color(
        convert_pixel(Color(1, 9, 9, 7), CITY_SCAPES_PALETTE),
        Color(128, 64, 128),
    )
    _same_color(convert_pixel(Color(1, 2, 3, 4), RAW), Color(1, 2, 3, 4))
    with assert_raises(contains="not valid"):
        _ = convert_pixel(Color(30, 0, 0), CITY_SCAPES_PALETTE)
    with assert_raises(contains="four conversions"):
        _ = convert_pixel(Color(0, 0, 0), ColorConverter(9))
    assert_equal(Int(gray_byte(0.5)), 128)
    assert_equal(Int(gray_byte(0.0)), 0)


def test_convert_in_place() raises:
    var image = Framebuffer(2, 1, Color(0, 0, 0))
    image.set_pixel(0, 0, Color(1, 0, 0))
    image.set_pixel(1, 0, Color(14, 0, 0))
    convert_in_place(image, CITY_SCAPES_PALETTE)
    _same_color(image.get_pixel(0, 0), Color(128, 64, 128))
    _same_color(image.get_pixel(1, 0), Color(0, 0, 142))


def test_instance_segmentation() raises:
    var c = encode_instance(ROAD, InstanceId(0x1234))
    _same_color(c, Color(1, 0x34, 0x12))
    assert_equal(decode_instance_tag(c).value, 1)
    assert_equal(decode_instance_id(c).value, 0x1234)
    with assert_raises(contains="16 bits"):
        _ = encode_instance(ROAD, InstanceId(70000))
    with assert_raises(contains="not valid"):
        _ = encode_instance(SemanticTag(40), InstanceId(1))


def test_decode_normal() raises:
    _near(decode_normal(Color(255, 0, 255)), Vector3(1, -1, 1))
    _near(
        decode_normal(Color(128, 128, 128)),
        Vector3(0.0039216, 0.0039216, 0.0039216),
    )


def test_optical_flow_colors() raises:
    # Python port of `EncodeFlowPixelToBgra`, in `float`.
    _same_color(encode_flow_pixel(0.1, 0.0), Color(0, 254, 255, 0))
    _same_color(encode_flow_pixel(0.0, 0.05), Color(64, 0, 129, 0))
    _same_color(encode_flow_pixel(-0.02, -0.03), Color(93, 87, 0, 0))
    _same_color(encode_flow_pixel(0.5, -0.5), Color(0, 255, 63, 0))
    _same_color(encode_flow_pixel(0.0, 0.0), Color(0, 0, 0, 0))
    _same_color(encode_flow_pixel(-0.004, 0.001), Color(8, 0, 1, 0))
    _same_color(encode_flow_pixel(0.03, 0.01), Color(0, 56, 81, 0))
    _same_color(encode_flow_pixel(0.01, -0.03), Color(15, 81, 0, 0))
    # Off the seam at 180 degrees: exactly on it, the platform's atan2
    # decides between sector 0 and the white default.
    _same_color(encode_flow_pixel(-0.05, -0.01), Color(131, 24, 0, 0))
    # A hue that rounds to six falls to CARLA's white default.
    _same_color(encode_flow_pixel(-1.0, 3.9e-7), Color(255, 255, 255, 0))
    with assert_raises(contains="finite"):
        _ = encode_flow_pixel(nan[DType.float32](), 0)
    with assert_raises(contains="finite"):
        _ = encode_flow_pixel(0, inf[DType.float32]())
    var image = encode_flow_image(2, 1, [0.1, 0.0, 0.0, 0.05])
    _same_color(image.get_pixel(0, 0), Color(0, 254, 255, 0))
    _same_color(image.get_pixel(1, 0), Color(64, 0, 129, 0))
    with assert_raises(contains="positive size"):
        _ = encode_flow_image(0, 1, List[Float32]())
    with assert_raises(contains="positive size"):
        _ = encode_flow_image(1, 0, List[Float32]())
    with assert_raises(contains="two numbers"):
        _ = encode_flow_image(1, 1, [0.1])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
