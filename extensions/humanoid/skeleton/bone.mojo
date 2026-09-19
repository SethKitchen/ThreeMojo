# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Visual look of bone: procedural albedo, roughness and a Phong stand-in.

Tissue density, porosity and moduli live in `tissue.mojo`. This module
does not consume those numbers. The maps are visual approximations.

The look is a pair of procedural maps: an sRGB albedo and a linear
roughness map. MeshStandardMaterial is not ported, so `bone_phong` is the
surface the current renderer can draw. The roughness map is still built,
because a later standard material will read it.

    var map = bone_albedo(64)
    var paint = bone_phong(store.add(map))
"""

from materials.material import Material, phong_material
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB
from render.texture import IGNORED, REPEAT, Texture
from render.texture_store import NO_TEXTURE, TextureId

# Albedo and roughness maps are square. Eight is the least that still
# shows grain. Two hundred fifty-six is enough for a close camera.
comptime MIN_LOOK = 8
comptime MAX_LOOK = 256


def bone_albedo(size: Int = 64) raises -> Texture:
    """Return a square sRGB albedo of cortical bone.

    The map is ivory with grain, a darker posterior strip for the linea
    aspera, and slightly more yellow at the ends. `u` runs around the
    shaft. `v` runs from distal to proximal.

    Args:
        size: Width and height in texels. Eight through 256, 64 by default.

    Returns:
        An sRGB texture that tiles around the shaft.

    Raises:
        Error: If `size` is less than eight or more than 256.
    """
    _check_look_size(size)
    var pixels = List[UInt8]()
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var u = (Float32(x) + Float32(0.5)) / Float32(size)
            var v = (Float32(y) + Float32(0.5)) / Float32(size)
            var grain = _hash(x, y) * Float32(0.55) + _hash(
                x // 4, y // 3
            ) * Float32(0.45)
            var end = v - Float32(0.5)
            if end < 0:
                end = -end
            end = end * Float32(2)
            var du = u - Float32(0.5)
            if du < 0:
                du = -du
            var aspera = Float32(0)
            if du < Float32(0.10):
                aspera = (Float32(0.10) - du) / Float32(0.10)
            var r = (
                Float32(214)
                + Float32(22) * (Float32(1) - grain)
                - Float32(16) * end
                - Float32(24) * aspera
            )
            var g = (
                Float32(196)
                + Float32(18) * (Float32(1) - grain)
                - Float32(14) * end
                - Float32(20) * aspera
            )
            var b = (
                Float32(162)
                + Float32(16) * (Float32(1) - grain)
                - Float32(12) * end
                - Float32(16) * aspera
            )
            pixels.append(_byte(r))
            pixels.append(_byte(g))
            pixels.append(_byte(b))
            pixels.append(255)
    return Texture(size, size, pixels^, REPEAT, color_space=SRGB)


def bone_roughness(size: Int = 64) raises -> Texture:
    """Return a square linear roughness map of cortical bone.

    The shaft is smoother. The articular ends are rougher. Bytes are
    linear coverage-ignored data, not sRGB color. The current Phong
    path does not sample this map.

    Args:
        size: Width and height in texels. Eight through 256, 64 by default.

    Returns:
        A linear texture. Metalness is zero: bone is a dielectric.

    Raises:
        Error: If `size` is less than eight or more than 256.
    """
    _check_look_size(size)
    var pixels = List[UInt8]()
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var v = (Float32(y) + Float32(0.5)) / Float32(size)
            var grain = _hash(x + 17, y + 9)
            var end = v - Float32(0.5)
            if end < 0:
                end = -end
            end = end * Float32(2)
            var rough = (
                Float32(0.38) + Float32(0.34) * end + Float32(0.10) * grain
            )
            var tone = _byte(rough * Float32(255))
            pixels.append(tone)
            pixels.append(tone)
            pixels.append(tone)
            pixels.append(255)
    return Texture(
        size,
        size,
        pixels^,
        REPEAT,
        color_space=LINEAR,
        alpha=IGNORED,
    )


def bone_phong(map: TextureId = NO_TEXTURE) raises -> Material:
    """Return a Phong material that stands in for bone until standard
    PBR is ported.

    With no map the color is dry cortical ivory. With a map the color is
    white so the albedo arrives unshifted. Shininess is low: bone is not
    a glossy dielectric.

    Args:
        map: Id of an albedo texture, or `NO_TEXTURE`.

    Returns:
        A `PHONG` material.

    Raises:
        Error: If `map` is a negative other than `NO_TEXTURE`.
    """
    var color = Color(232, 214, 180)
    if map != NO_TEXTURE:
        color = Color(255, 255, 255)
    return phong_material(
        color,
        map=map,
        specular=Color(82, 74, 62),
        shininess=14.0,
    )


def _check_look_size(size: Int) raises:
    """Refuse a map that is too small or too large.

    Args:
        size: Requested width and height.

    Raises:
        Error: If `size` is less than eight or more than 256.
    """
    if size < MIN_LOOK:
        raise Error("A bone map needs a size of at least eight")
    if size > MAX_LOOK:
        raise Error("A bone map's size cannot exceed 256")


def _hash(x: Int, y: Int) -> Float32:
    """Return a stable 0 through 1 grain for texel `(x, y)`."""
    var n = x * 374761393 + y * 668265263
    n = (n ^ (n >> 13)) * 1274126177
    var bits = n & 65535
    return Float32(bits) / Float32(65535)


def _byte(value: Float32) -> UInt8:
    """Return `value` rounded into an 8-bit channel."""
    if value < 0:
        return 0
    if value > 255:
        return 255
    return UInt8(Int(value + Float32(0.5)))
