# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Looks for the named hydrated tissues of the limb.

Each tissue has a Phong look and a physically based one. The physical
looks take a roughness, an index of refraction and, where the tissue
has one, a sheen or a clear coat. They need an environment or a lamp
and read best tone mapped. The maps are visual approximations.

    var map = muscle_albedo(64)
    var paint = muscle_physical(store.add(map))
"""

from materials.material import (
    DOUBLE_SIDE,
    Material,
    phong_material,
    physical_material,
)
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


def artery_phong() raises -> Material:
    """Return a Phong material for an artery.

    The color is saturated arterial red.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(168, 28, 42),
        specular=Color(190, 90, 90),
        shininess=28.0,
    )


def vein_phong() raises -> Material:
    """Return a Phong material for a vein.

    The color is deep venous blue.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(52, 74, 142),
        specular=Color(110, 130, 180),
        shininess=26.0,
    )


def lymph_phong() raises -> Material:
    """Return a Phong material for lymph nodes and trunks.

    The color is pale yellow-green lymph.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(196, 208, 154),
        specular=Color(170, 180, 140),
        shininess=16.0,
    )


def nerve_phong() raises -> Material:
    """Return a Phong material for a peripheral nerve.

    The color is pale dissected nerve.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(236, 220, 158),
        specular=Color(200, 190, 150),
        shininess=20.0,
    )


def skin_albedo(size: Int = 64) raises -> Texture:
    """Return a skin texture with pores and a faint hair grain.

    Args:
        size: Width and height in texels. Eight through 256, 64 by default.

    Returns:
        An sRGB texture that tiles around a limb.

    Raises:
        Error: If `size` is less than eight or more than 256.
    """
    if size < MIN_SOFT_LOOK:
        raise Error("A skin map needs a size of at least eight")
    if size > MAX_SOFT_LOOK:
        raise Error("A skin map's size cannot exceed 256")
    var pixels = List[UInt8]()
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var pore = Float32((x * 13 + y * 29) % 9) / Float32(8)
            var grain = Float32((x * 19 + y * 7 + (x * y) % 11) & 7) / Float32(
                7
            )
            pixels.append(UInt8(Int(Float32(210) + 18 * pore + 8 * grain)))
            pixels.append(UInt8(Int(Float32(158) + 14 * pore + 6 * grain)))
            pixels.append(UInt8(Int(Float32(128) + 10 * pore + 5 * grain)))
            pixels.append(255)
    return Texture(size, size, pixels^, REPEAT, color_space=SRGB)


def skin_phong(map: TextureId = NO_TEXTURE) raises -> Material:
    """Return a Phong material for dermis.

    The color is light adult skin. With a map the color is white so the
    albedo arrives unshifted.

    Args:
        map: Id of a skin albedo texture, or `NO_TEXTURE`.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    var color = Color(222, 174, 146)
    if map != NO_TEXTURE:
        color = Color(255, 255, 255)
    return phong_material(
        color,
        map=map,
        specular=Color(90, 70, 60),
        shininess=12.0,
        side=DOUBLE_SIDE,
    )


def hair_phong() raises -> Material:
    """Return a Phong material for a keratin hair shaft.

    The color is medium brown terminal hair.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If the Phong constructor refuses the values.
    """
    return phong_material(
        Color(128, 80, 50),
        specular=Color(150, 112, 82),
        shininess=24.0,
    )


def muscle_physical(map: TextureId = NO_TEXTURE) raises -> Material:
    """Return a physically based material for skeletal muscle.

    Muscle is wet. Its epimysium is a thin glossy film over a rough
    fibrous body, so a soft lobe carries a sharper clear coat.

    Args:
        map: Id of a muscle albedo texture, or `NO_TEXTURE`.

    Returns:
        A `PHYSICAL` material.

    Raises:
        Error: If the physical constructor refuses the values.
    """
    var color = Color(176, 54, 44)
    if map != NO_TEXTURE:
        color = Color(255, 255, 255)
    return physical_material(
        color,
        map=map,
        roughness=0.55,
        ior=1.37,
        clearcoat=0.35,
        clearcoat_roughness=0.3,
    )


def tendon_physical() raises -> Material:
    """Return a physically based material for tendon and fascia.

    Tendon's collagen runs in parallel bundles, which gives it a silvery
    sheen along its length.

    Returns:
        A `PHYSICAL` material.

    Raises:
        Error: If the physical constructor refuses the values.
    """
    return physical_material(
        Color(214, 200, 176),
        roughness=0.45,
        ior=1.40,
        sheen=0.5,
        sheen_color=Color(235, 230, 220),
        sheen_roughness=0.4,
    )


def ligament_physical() raises -> Material:
    """Return a physically based material for ligament.

    Returns:
        A `PHYSICAL` material with the look of `tendon_physical`, a shade
        darker.

    Raises:
        Error: If the physical constructor refuses the values.
    """
    return physical_material(
        Color(198, 184, 160),
        roughness=0.5,
        ior=1.40,
        sheen=0.4,
        sheen_color=Color(225, 220, 208),
        sheen_roughness=0.45,
    )


def cartilage_physical() raises -> Material:
    """Return a physically based material for articular cartilage.

    Hyaline cartilage is smooth and wet: a low roughness and a clear
    coat over a pale blue-white body.

    Returns:
        A `PHYSICAL` material.

    Raises:
        Error: If the physical constructor refuses the values.
    """
    return physical_material(
        Color(206, 214, 222),
        roughness=0.3,
        ior=1.38,
        clearcoat=0.6,
        clearcoat_roughness=0.15,
    )


def skin_physical(map: TextureId = NO_TEXTURE) raises -> Material:
    """Return a physically based material for dermis.

    Skin reflects about three percent at normal incidence, an index of
    refraction near 1.4. Light that enters it scatters and leaves warm
    and soft at grazing angles. The renderer has no subsurface
    scattering, so a warm sheen stands in for that rim.

    Args:
        map: Id of a skin albedo texture, or `NO_TEXTURE`.

    Returns:
        A `PHYSICAL` material.

    Raises:
        Error: If the physical constructor refuses the values.
    """
    var color = Color(222, 174, 146)
    if map != NO_TEXTURE:
        color = Color(255, 255, 255)
    return physical_material(
        color,
        map=map,
        roughness=0.55,
        ior=1.40,
        specular_intensity=0.6,
        sheen=0.35,
        sheen_color=Color(230, 140, 120),
        sheen_roughness=0.6,
        side=DOUBLE_SIDE,
    )
