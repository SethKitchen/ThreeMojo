# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Preserve the original light clamp trees, including exceptional floats."""

from lights.physical_layers import (
    clearcoat_of,
    sheen_roughness_of,
    SHEEN_ROUGHNESS_FLOOR,
)
from lights.projector_light import (
    projector_attenuation,
    sd_box,
    PROJECTOR_PENUMBRA_CAP,
)
from math.vector3 import Vector3
from std.math import acos, min, max
from std.memory import bitcast
from std.testing import TestSuite, assert_equal


def _values() -> List[Float32]:
    var bits: List[UInt32] = [
        0,
        0x80000000,
        1,
        0x80000001,
        0x3F000000,
        0x3F800000,
        0xBF800000,
        0x40000000,
        0xC0000000,
        0x7F7FFFFF,
        0xFF7FFFFF,
        0x7F800000,
        0xFF800000,
        0x7FC00001,
        0xFFC12345,
    ]
    var values = List[Float32]()
    for b in bits:
        values.append(bitcast[DType.float32](b))
    return values^


def test_sheen_original_lower_first_bits() raises:
    var values = _values()
    for authored in values:
        for texel in values:
            var original = (
                min(max(authored, SHEEN_ROUGHNESS_FLOOR), Float32(1)) * texel
            )
            assert_equal(
                bitcast[DType.uint32](sheen_roughness_of(authored, texel)),
                bitcast[DType.uint32](original),
            )


def _original_projector(
    frame: SIMD[DType.float32, 16], position: Vector3, penumbra_cos: Float32
) -> Float32:
    """Return how much of a projector's light reaches a world position,
    three.js's `ProjectorLightNode.getSpotAttenuation`.

    Both backends call it.

    Args:
        frame: World space to the light's clip space, column major, as
            `lights.shadow.ShadowMap.frame`.
        position: The world position, with no normal bias, as three.js
            reads `positionWorld`.
        penumbra_cos: `cos( angle * ( 1 - penumbra ) )`. Capped here at
            `PROJECTOR_PENUMBRA_CAP`.

    Returns:
        From zero outside the rectangle, or behind the light, to one
        well inside it.
    """
    var x = (
        frame[0] * position.x
        + frame[4] * position.y
        + frame[8] * position.z
        + frame[12]
    )
    var y = (
        frame[1] * position.x
        + frame[5] * position.y
        + frame[9] * position.z
        + frame[13]
    )
    var w = (
        frame[3] * position.x
        + frame[7] * position.y
        + frame[11] * position.z
        + frame[15]
    )
    if w <= 0:
        return 0
    # The shadow matrix's half and half: a map coordinate from zero to
    # one, less its middle, is half the normalized device coordinate.
    var u = x / w * 0.5
    var v = y / w * 0.5
    var box = sd_box(u, v, 0.5)
    var capped = min(penumbra_cos, PROJECTOR_PENUMBRA_CAP)
    var angle_factor = Float32(-1.0) / ((Float32(1.0) - acos(capped)) - 1.0)
    return min(max(box * -2.0 * angle_factor, Float32(0)), Float32(1))


def test_projector_original_tree_boundary_grid() raises:
    var values = _values()
    var position = Vector3(0, 0, 0)
    for x in values:
        for y in values:
            for w in values:
                var frame = SIMD[DType.float32, 16](0)
                frame[12] = x
                frame[13] = y
                frame[15] = w
                for penumbra in values:
                    assert_equal(
                        bitcast[DType.uint32](
                            projector_attenuation(frame, position, penumbra)
                        ),
                        bitcast[DType.uint32](
                            _original_projector(frame, position, penumbra)
                        ),
                    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


def _original_saturated(value: Float32) -> Float32:
    """Return `value` clamped to zero through one: GLSL's `saturate`."""
    return max(Float32(0), min(Float32(1), value))


def _original_clearcoat_of(authored: Float32, texel: Float32) -> Float32:
    return _original_saturated(authored * texel)


def test_clearcoat_original_saturate_bits() raises:
    var values = _values()
    for authored in values:
        for texel in values:
            assert_equal(
                bitcast[DType.uint32](clearcoat_of(authored, texel)),
                bitcast[DType.uint32](_original_clearcoat_of(authored, texel)),
            )
