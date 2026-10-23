# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.splat_harmonics`, the weights of a splat's spherical
harmonics.

The weights are held to the colors that `GaussianSplat` sums on the host: a
splat with known harmonics bytes is shaded for several directions both ways.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
    packed_band,
    write_covariance,
)
from core.object3d import Object3D
from core.scene import Scene
from math.vector3 import Vector3
from objects.gaussian_splat import GaussianSplat
from render.splat_harmonics import sh_weights
from std.testing import TestSuite, assert_almost_equal, assert_equal


def _one_splat(degree: Int) raises -> GaussianSplatGeometry:
    """Return one splat with harmonics bytes that count up."""
    var covariances = List[Float32](length=6, fill=0)
    write_covariance(covariances, 0, 0.1, 0.1, 0.1, 0, 0, 0, 1)
    var colors: List[UInt8] = [120, 130, 140, 255]
    var bands = List[List[UInt8]]()
    for band in range(1, 4):
        var bytes = List[UInt8]()
        if band <= degree:
            bytes = packed_band(1, band)
            for at in range(len(bytes)):
                bytes[at] = UInt8(90 + (at * 7) % 80)
        bands.append(bytes^)
    return create_gaussian_splat_geometry(
        [0.0, 0.0, 0.0],
        covariances^,
        colors^,
        bands[0].copy(),
        bands[1].copy(),
        bands[2].copy(),
    )


def _sum(
    geometry: GaussianSplatGeometry, direction: Vector3, degree: Int
) -> Vector3:
    """Return the harmonics' color from the weights, as a kernel sums them."""
    var sum = Vector3(0, 0, 0)
    for band in range(1, degree + 1):
        var weights = sh_weights(band, direction)
        var bytes = geometry.sh1.copy()
        if band == 2:
            bytes = geometry.sh2.copy()
        elif band == 3:
            bytes = geometry.sh3.copy()
        for k in range(band * 2 + 1):
            var at = k * 3
            sum.x += (Float32(bytes[at]) - 128) / 128 * weights[k]
            sum.y += (Float32(bytes[at + 1]) - 128) / 128 * weights[k]
            sum.z += (Float32(bytes[at + 2]) - 128) / 128 * weights[k]
    return sum


def test_the_weights_give_the_color_that_the_object_sums() raises:
    """For each degree and several directions, the weights and the object
    agree to rounding."""
    var directions = List[Vector3]()
    directions.append(Vector3(0.6, 0.0, 0.8))
    directions.append(Vector3(0.0, 1.0, 0.0))
    directions.append(Vector3(-0.48, 0.64, -0.6))
    directions.append(Vector3(0.36, -0.8, 0.48))
    for degree in range(1, 4):
        var geometry = _one_splat(degree)
        var scene = Scene()
        var node = scene.add(Object3D())
        scene.update()
        var splat = GaussianSplat(geometry.copy(), node)
        for direction in directions:
            # The splat is at the origin, so the camera is at minus the
            # direction, and the object's direction is the unit vector.
            var camera = direction * Float32(-3)
            var shaded = splat.spherical_harmonics_color(0, camera, degree)
            var found = _sum(geometry, direction, degree)
            assert_almost_equal(shaded.x, found.x, atol=1e-5)
            assert_almost_equal(shaded.y, found.y, atol=1e-5)
            assert_almost_equal(shaded.z, found.z, atol=1e-5)


def test_the_weights_beyond_the_band_are_zero() raises:
    """Band 1 has three weights, band 2 five and band 3 seven; the other
    lanes are zero."""
    var d = Vector3(0.6, 0.0, 0.8)
    var one = sh_weights(1, d)
    var two = sh_weights(2, d)
    var three = sh_weights(3, d)
    for lane in range(3, 8):
        assert_equal(one[lane], 0)
    for lane in range(5, 8):
        assert_equal(two[lane], 0)
    assert_equal(three[7], 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
