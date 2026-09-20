# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `cameras.cube_camera`: six face cameras that look along the
six axes from one point, with the ups `render.cube_texture` reads back."""

from cameras.cube_camera import CubeCamera
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from math.vector3 import Vector3
from render.cube_texture import (
    FACE_COUNT,
    POSITIVE_X,
    POSITIVE_Y,
    face_forward,
    face_up,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-5)


def a_cube_camera(size: Int = 8) raises -> CubeCamera:
    """Return a cube camera with ordinary planes."""
    return CubeCamera(Length(0.1, METER), Length(50.0, METER), size)


def test_a_cube_camera_starts_at_the_origin_on_layer_zero() raises:
    var camera = a_cube_camera(16)
    assert_equal(camera.size, 16)
    assert_equal(camera.position.length(), Float32(0))
    assert_equal(camera.node, NO_PARENT)
    assert_true(camera.layers.test(Layers()))
    assert_equal(camera.near.to(METER), Float32(0.1))
    assert_equal(camera.far.to(METER), Float32(50))


def test_a_cube_camera_refuses_bad_planes_and_sizes() raises:
    with assert_raises():
        _ = CubeCamera(Length(0.1, METER), Length(50.0, METER), 0)
    with assert_raises():
        _ = CubeCamera(Length(0.0, METER), Length(50.0, METER), 8)
    with assert_raises():
        _ = CubeCamera(Length(-1.0, METER), Length(50.0, METER), 8)
    with assert_raises():
        _ = CubeCamera(Length(2.0, METER), Length(2.0, METER), 8)


def test_each_face_camera_looks_along_its_axis_with_its_up() raises:
    # A face camera's view carries the point one ahead along its axis to
    # one in front of it, and the point one up along its up axis to one
    # above it: the same two tables the sampler reads with.
    var camera = a_cube_camera()
    camera.place(Vector3(1, 2, 3))
    var scene = Scene()
    for face in range(FACE_COUNT):
        var eye = camera.face_camera(face, scene)
        assert_almost_equal(Float64(eye.fov.to(DEGREE)), 90.0, atol=TOLERANCE)
        assert_equal(eye.aspect, Float32(1))
        var view = eye.view_matrix()
        var ahead = view.transform_point(Vector3(1, 2, 3) + face_forward(face))
        assert_almost_equal(Float64(ahead.x), 0.0, atol=TOLERANCE)
        assert_almost_equal(Float64(ahead.y), 0.0, atol=TOLERANCE)
        assert_almost_equal(Float64(ahead.z), -1.0, atol=TOLERANCE)
        var above = view.transform_point(Vector3(1, 2, 3) + face_up(face))
        assert_almost_equal(Float64(above.x), 0.0, atol=TOLERANCE)
        assert_almost_equal(Float64(above.y), 1.0, atol=TOLERANCE)
        assert_almost_equal(Float64(above.z), 0.0, atol=TOLERANCE)


def test_a_face_camera_carries_the_cube_cameras_layers_and_planes() raises:
    var camera = a_cube_camera()
    camera.layers = Layers()
    camera.layers.set(3)
    var scene = Scene()
    var eye = camera.face_camera(POSITIVE_Y, scene)
    assert_true(eye.visible_layers().test(camera.layers))
    var only_zero = Layers()
    assert_true(not eye.visible_layers().test(only_zero))
    assert_equal(eye.near.to(METER), Float32(0.1))
    assert_equal(eye.far.to(METER), Float32(50))


def test_a_face_must_be_one_of_six() raises:
    var camera = a_cube_camera()
    var scene = Scene()
    with assert_raises():
        _ = camera.face_camera(FACE_COUNT, scene)
    with assert_raises():
        _ = camera.face_camera(-1, scene)


def test_an_attached_cube_camera_stands_where_its_node_is() raises:
    var scene = Scene()
    var pivot = Object3D()
    pivot.set_position(0, 0, 4)
    var pivot_node = scene.add(pivot^)
    var rider = Object3D()
    rider.set_position(2, 0, 0)
    var rider_node = scene.attach(rider^, pivot_node)
    scene.update()
    var camera = a_cube_camera()
    camera.attach(rider_node)
    var stand = camera.eye(scene)
    assert_almost_equal(Float64(stand.x), 2.0, atol=TOLERANCE)
    assert_almost_equal(Float64(stand.z), 4.0, atol=TOLERANCE)
    # The face camera stands there too, and still looks along the world
    # axis: the node's own turn is not read.
    scene.node(pivot_node).rotate_y(Angle(90.0, DEGREE))
    scene.update()
    var eye = camera.face_camera(POSITIVE_X, scene)
    var stood = camera.eye(scene)
    var ahead = eye.view_matrix().transform_point(stood + Vector3(1, 0, 0))
    assert_almost_equal(Float64(ahead.z), -1.0, atol=TOLERANCE)
    # Placing lets go of the node.
    camera.place(Vector3(0, 9, 0))
    assert_equal(camera.node, NO_PARENT)
    assert_equal(camera.eye(scene).y, Float32(9))


def test_a_stale_or_missing_node_is_refused() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    var camera = a_cube_camera()
    camera.attach(node)
    with assert_raises():
        _ = camera.eye(scene)
    scene.update()
    _ = camera.face_camera(POSITIVE_X, scene)
    camera.attach(NodeId(7))
    with assert_raises():
        _ = camera.face_camera(POSITIVE_X, scene)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
