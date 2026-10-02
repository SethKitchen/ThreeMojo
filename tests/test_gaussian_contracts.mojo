# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Interleaved attributes and conservative Gaussian broad-phase bounds."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from core.gaussian_splat_utils import (
    COVARIANCE,
    create_gaussian_splat_geometry,
    gaussian_splat_geometry_of,
)
from core.interleaved_buffer import InterleavedBuffer
from core.object3d import NodeId
from core.raycaster import Raycaster
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.gaussian_splat import GaussianSplat
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
)


def splat(covariance: List[Float32]) raises -> GaussianSplat:
    """Return an opaque splat at the origin."""
    return GaussianSplat(
        create_gaussian_splat_geometry(
            [0, 0, 0], covariance.copy(), [255, 255, 255, 255]
        ),
        NodeId(0),
    )


def test_interleaved_colors_are_read_through_the_attribute() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute([0, 0, 0, 1, 0, 0], 3))
    geometry.set_attribute(
        COVARIANCE, BufferAttribute([1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1], 6)
    )
    var colors = InterleavedBuffer([99, 1, 0, 0, 1, 99, 0.5, 0.25, 1, 0.5], 5)
    geometry.set_attribute(COLOR, BufferAttribute(colors, 4, 1))
    var made = gaussian_splat_geometry_of(geometry)
    assert_equal(made.count(), 2)
    var expected: List[UInt8] = [255, 0, 0, 255, 128, 64, 255, 128]
    for lane in range(len(expected)):
        assert_equal(made.colors[lane], expected[lane])


def test_rotated_long_axes_survive_sphere_rejection() raises:
    for sign in [Float32(1), Float32(-1)]:
        var shape = splat([2.5, 1.5 * sign, 0, 2.5, 0, 1])
        for side in [Float32(1), Float32(-1)]:
            var ray = Raycaster(
                Vector3(2.6 * side, 2.6 * side * sign, 5), Vector3(0, 0, -1)
            )
            assert_equal(len(shape.raycast(Matrix4(), ray)), 1)
        shape.compute_bounding_sphere()
        assert_almost_equal(
            shape.bounding_sphere.value().radius, Float32(4), atol=Float64(1e-5)
        )


def test_the_exact_ellipsoid_still_rejects_points_outside_it() raises:
    var shape = splat([2.5, 1.5, 0, 2.5, 0, 1])
    # Inside the broad sphere but outside the short principal axis.
    var ray = Raycaster(Vector3(2, -2, 5), Vector3(0, 0, -1))
    assert_equal(len(shape.raycast(Matrix4(), ray)), 0)


def test_diagonal_covariance_keeps_its_exact_radius() raises:
    var shape = splat([4, 0, 0, 1, 0, 0.25])
    shape.compute_bounding_sphere()
    assert_equal(shape.bounding_sphere.value().radius, 4)


def test_a_positive_determinant_alone_does_not_make_a_covariance_positive() raises:
    var shape = splat([-1, 0, 0, -1, 0, 1])
    var ray = Raycaster(Vector3(0, 0, 5), Vector3(0, 0, -1))
    assert_equal(len(shape.raycast(Matrix4(), ray)), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
