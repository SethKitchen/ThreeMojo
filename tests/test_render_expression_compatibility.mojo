# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact historical floating expressions, including exceptional inputs."""

from render.color_spaces import (
    Row3,
    _dot,
    srgb_to_linear_three,
    linear_to_srgb_three,
)
from render.cube_texture import reflected, refracted
from math.vector3 import Vector3
from std.benchmark import black_box
from std.math import pow, sqrt
from std.memory import bitcast
from std.testing import TestSuite, assert_equal


def _original__dot(row: Row3, r: Float64, g: Float64, b: Float64) -> Float64:
    """Return a row times a column, summed in three.js's order.

    Args:
        row: The row.
        r: The first component.
        g: The second.
        b: The third.

    Returns:
        `row[0] * r + row[1] * g + row[2] * b`.
    """
    return black_box(row[0] * r) + black_box(row[1] * g) + black_box(row[2] * b)


def _original_srgb_to_linear_three(c: Float64) -> Float64:
    """Return three.js's `SRGBToLinear`, with its constants.

    Args:
        c: An sRGB-encoded channel.

    Returns:
        The linear channel.
    """
    if c < 0.04045:
        return c * 0.0773993808
    return pow(black_box(c * 0.9478672986) + 0.0521327014, 2.4)


def _original_linear_to_srgb_three(c: Float64) -> Float64:
    """Return three.js's `LinearToSRGB`, with its constants.

    Args:
        c: A linear channel.

    Returns:
        The sRGB-encoded channel.
    """
    if c < 0.0031308:
        return c * 12.92
    return black_box(1.055 * pow(c, 0.41666)) - 0.055


def _original_reflected(toward_eye: Vector3, normal: Vector3) -> Vector3:
    """Return the direction a mirror surface sends the camera's view.

    GLSL's `reflect(-toward_eye, normal)`, which three.js's
    `envmap_fragment` evaluates on the vector from the camera to the
    fragment: the view direction turned back through the surface,

        reflected = 2 * dot(normal, toward_eye) * normal - toward_eye

    so a surface square-on to the camera reflects the camera and one seen
    at a grazing angle reflects what is beyond it. Shared by both
    rasterizers, as `matcap_uv` is.

    Args:
        toward_eye: Unit direction from the surface toward the camera.
        normal: The surface's unit normal.

    Returns:
        The reflected direction, unit length for unit inputs.
    """
    var along = normal.dot(toward_eye)
    return Vector3(
        2 * along * normal.x - toward_eye.x,
        2 * along * normal.y - toward_eye.y,
        2 * along * normal.z - toward_eye.z,
    )


def _original_refracted(
    toward_eye: Vector3, normal: Vector3, ratio: Float32
) -> Vector3:
    """Return the direction a clear surface bends the camera's view:
    GLSL's `refract(-toward_eye, normal, ratio)`, which three.js's
    `envmap_fragment` evaluates under a refraction mapping.

        k = 1 - ratio^2 * (1 - dot(normal, view)^2)
        refracted = ratio * view - (ratio * dot(normal, view) + sqrt(k)) * normal

    with `view = -toward_eye`. When `k` is below zero the light is
    reflected inside the surface instead, and GLSL answers the zero
    vector; so does this, and the environment is read in the direction
    `face_of` and `equirect_uv` give the zero vector. Shared by both
    rasterizers.

    Args:
        toward_eye: Unit direction from the surface toward the camera.
        normal: The surface's unit normal.
        ratio: The ratio of the two indices of refraction, three.js's
            `refractionRatio`.

    Returns:
        The refracted direction, or the zero vector.
    """
    var along = -normal.dot(toward_eye)
    var k = 1 - ratio * ratio * (1 - along * along)
    if k < 0:
        return Vector3(0, 0, 0)
    var bend = ratio * along + sqrt(k)
    return Vector3(
        -ratio * toward_eye.x - bend * normal.x,
        -ratio * toward_eye.y - bend * normal.y,
        -ratio * toward_eye.z - bend * normal.z,
    )


def test_color_products_keep_historical_bits() raises:
    var words: List[UInt64] = [
        0,
        0x8000000000000000,
        0x7FF0000000000000,
        0xFFF0000000000000,
        0x7FF8000000000001,
        0xFFF8000000000001,
        0x7FF4000000000001,
        0xFFF4000000000001,
        1,
        0x8000000000000001,
        0x3FE0000000000000,
        0x3FEFFFFFFFFFFFFF,
        0x3FF0000000000000,
        0x3FF0000000000001,
        0xBFF0000000000000,
    ]
    for one in words:
        var a = black_box(bitcast[DType.float64](one))
        assert_equal(
            bitcast[DType.uint64](srgb_to_linear_three(a)),
            bitcast[DType.uint64](_original_srgb_to_linear_three(a)),
        )
        assert_equal(
            bitcast[DType.uint64](linear_to_srgb_three(a)),
            bitcast[DType.uint64](_original_linear_to_srgb_three(a)),
        )
        for two in words:
            for three in words:
                var b = black_box(bitcast[DType.float64](two))
                var c = black_box(bitcast[DType.float64](three))
                # Includes 0*Inf plus a payload-carrying NaN and finite controls.
                var row = Row3(a, b, c, 0)
                assert_equal(
                    bitcast[DType.uint64](_dot(row, b, c, a)),
                    bitcast[DType.uint64](_original__dot(row, b, c, a)),
                )


def test_cube_directions_keep_historical_expressions() raises:
    var words: List[UInt32] = [
        0,
        0x80000000,
        0x7F800000,
        0xFF800000,
        0x7FC00001,
        0xFFC00001,
        0x7FA00001,
        0xFFA00001,
        1,
        0x80000001,
        0x3F000000,
        0x3F7FFFFF,
        0x3F800000,
        0x3F800001,
        0xBF800000,
    ]
    for one in words:
        for two in words:
            var a = black_box(bitcast[DType.float32](one))
            var b = black_box(bitcast[DType.float32](two))
            var eye = Vector3(a, 0.25, -0.5)
            var normal = Vector3(b, -0.25, 0.5)
            var actual = reflected(eye, normal)
            var original = _original_reflected(eye, normal)
            assert_equal(
                bitcast[DType.uint32](actual.x),
                bitcast[DType.uint32](original.x),
            )
            assert_equal(
                bitcast[DType.uint32](actual.y),
                bitcast[DType.uint32](original.y),
            )
            assert_equal(
                bitcast[DType.uint32](actual.z),
                bitcast[DType.uint32](original.z),
            )
            for ratio in [Float32(0), Float32(0.66), Float32(1), a]:
                actual = refracted(eye, normal, ratio)
                original = _original_refracted(eye, normal, ratio)
                assert_equal(
                    bitcast[DType.uint32](actual.x),
                    bitcast[DType.uint32](original.x),
                )
                assert_equal(
                    bitcast[DType.uint32](actual.y),
                    bitcast[DType.uint32](original.y),
                )
                assert_equal(
                    bitcast[DType.uint32](actual.z),
                    bitcast[DType.uint32](original.z),
                )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
