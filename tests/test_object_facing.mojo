# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Object and camera facing share one scale-independent look-at basis."""

from core.object3d import Object3D, facing
from math.quaternion import Quaternion
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_raises,
    assert_true,
)


def unit_frame(turn: Quaternion) raises:
    """Check that the returned quaternion is a unit rotation."""
    assert_almost_equal(turn.length(), Float32(1), atol=Float64(1e-5))
    var x = turn.rotate(Vector3(1, 0, 0))
    var y = turn.rotate(Vector3(0, 1, 0))
    var z = turn.rotate(Vector3(0, 0, 1))
    assert_almost_equal(x.length(), Float32(1), atol=Float64(1e-5))
    assert_almost_equal(y.length(), Float32(1), atol=Float64(1e-5))
    assert_almost_equal(z.length(), Float32(1), atol=Float64(1e-5))
    assert_almost_equal(x.dot(y), Float32(0), atol=Float64(1e-5))
    assert_almost_equal(x.dot(z), Float32(0), atol=Float64(1e-5))
    assert_almost_equal(y.dot(z), Float32(0), atol=Float64(1e-5))


def test_parallel_up_is_a_rotation_at_every_finite_scale() raises:
    for camera in [False, True]:
        for scale in [Float32(2), Float32(1e-40), Float32(1e30)]:
            var turn = facing(
                Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, scale), camera
            )
            unit_frame(turn)
            var local = Vector3(0, 0, -1) if camera else Vector3(0, 0, 1)
            assert_almost_equal(
                turn.rotate(local).z, Float32(1), atol=Float64(1e-4)
            )


def test_facing_preserves_object_and_camera_forward_axes() raises:
    for camera in [False, True]:
        var node = Object3D()
        node.up = Vector3(0, 1e30, 0)
        node.look_at(Vector3(1, 0, 0), camera=camera)
        unit_frame(node.quaternion)
        var local = Vector3(0, 0, -1) if camera else Vector3(0, 0, 1)
        assert_almost_equal(
            node.quaternion.rotate(local).x, Float32(1), atol=Float64(1e-5)
        )


def test_facing_handles_extreme_finite_position_separation() raises:
    for camera in [False, True]:
        var turn = facing(
            Vector3(3e38, 0, 0), Vector3(-3e38, 0, 0), Vector3(0, 1, 0), camera
        )
        unit_frame(turn)
        var local = Vector3(0, 0, -1) if camera else Vector3(0, 0, 1)
        assert_almost_equal(
            turn.rotate(local).x, Float32(-1), atol=Float64(1e-5)
        )


def test_coincident_positions_keep_the_shared_plus_z_fallback() raises:
    for camera in [False, True]:
        var turn = facing(
            Vector3(2, 3, 4), Vector3(2, 3, 4), Vector3(0, 2, 0), camera
        )
        unit_frame(turn)
        assert_almost_equal(
            turn.rotate(Vector3(0, 0, 1)).z, Float32(1), atol=Float64(1e-5)
        )


def test_invalid_facing_positions_do_not_change_the_node() raises:
    var node = Object3D()
    var original = node.quaternion
    for bad in [inf[DType.float32](), nan[DType.float32]()]:
        with assert_raises():
            node.look_at(Vector3(bad, 0, 0))
        assert_true(node.quaternion == original)
        node.position = Vector3(bad, 0, 0)
        with assert_raises():
            node.look_at(Vector3(0, 0, 0))
        assert_true(node.quaternion == original)
        node.position = Vector3(0, 0, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
