# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Visual stand-ins for cartilage, meniscus, ligament, muscle and tendon.

The maps are visual approximations. MeshStandardMaterial is not ported,
so these surfaces are what the current renderer can draw.

    var map = muscle_albedo(64)
    var paint = muscle_phong(store.add(map))
"""

from materials.material import DOUBLE_SIDE, Material, phong_material
from render.framebuffer import Color
from render.srgb import SRGB
from render.texture import REPEAT, Texture
from render.texture_store import NO_TEXTURE, TextureId

comptime MIN_SOFT_LOOK = 8
comptime MAX_SOFT_LOOK = 256


def cartilage_phong() raises -> Material:
    """Return a Phong material for articular cartilage.

    The color is pearlescent glistening white/ivory, like wet hyaline cartilage.
    The surface is double-sided and opaque so it reads as tissue instead of colored glass.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(240, 242, 245),
        specular=Color(255, 255, 255),
        shininess=36.0,
        side=DOUBLE_SIDE,
    )


def meniscus_phong() raises -> Material:
    """Return a Phong material for a meniscus.

    The color is natural fibrocartilaginous off-white / light cream. Shininess is low.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(230, 226, 215),
        specular=Color(140, 135, 125),
        shininess=12.0,
    )


def ligament_phong() raises -> Material:
    """Return a Phong material for a collateral ligament.

    The color is pale fibrous silvery-tan connective tissue. Shininess is low.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(228, 222, 206),
        specular=Color(160, 155, 140),
        shininess=16.0,
    )


def muscle_albedo(size: Int = 64) raises -> Texture:
    """Return a red muscle texture with fine longitudinal fibers.

    Args:
        size: Width and height in texels. Eight through 256, 64 by default.

    Returns:
        An sRGB texture that tiles around a muscle belly.

    Raises:
        Error: If `size` is less than eight or more than 256.
    """
    if size < MIN_SOFT_LOOK:
        raise Error("A muscle map needs a size of at least eight")
    if size > MAX_SOFT_LOOK:
        raise Error("A muscle map's size cannot exceed 256")
    var pixels = List[UInt8]()
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var lane = x % 8
            var fiber = Float32(0.10)
            if lane < 2:
                fiber = Float32(1)
            elif lane > 5:
                fiber = Float32(0.45)
            var grain = Float32((x * 17 + y * 31 + (x * y) % 13) & 7) / Float32(
                7
            )
            pixels.append(UInt8(Int(Float32(150) + 24 * fiber + 7 * grain)))
            pixels.append(UInt8(Int(Float32(42) + 10 * fiber + 4 * grain)))
            pixels.append(UInt8(Int(Float32(36) + 7 * fiber + 3 * grain)))
            pixels.append(255)
    return Texture(size, size, pixels^, REPEAT, color_space=SRGB)


def muscle_phong(map: TextureId = NO_TEXTURE) raises -> Material:
    """Return a Phong material for skeletal muscle.

    The color is red muscle belly, like dissected skeletal muscle.

    Args:
        map: Id of a muscle albedo texture, or `NO_TEXTURE`.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    var color = Color(176, 54, 44)
    if map != NO_TEXTURE:
        color = Color(255, 255, 255)
    return phong_material(
        color, map=map, specular=Color(180, 110, 100), shininess=22.0
    )


def tendon_phong() raises -> Material:
    """Return a Phong material for tendon and fascia.

    The color is pale fibrous connective tissue.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(214, 200, 176),
        specular=Color(180, 172, 158),
        shininess=24.0,
    )
