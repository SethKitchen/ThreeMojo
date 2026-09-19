# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bone tissue: mechanical properties and a PBR look.

The numbers come from Morgan, Unnikrishnan and Hussein, *Bone Mechanical
Properties in Healthy and Diseased States*, Annu. Rev. Biomed. Eng. 2018
(PMC6053074). Tissue density is 2.0 g/cm^3 for cortical and trabecular
bone. Cortical porosity is 5% to 15%; the template uses 10%. Table 1
gives the longitudinal elastic modulus of femoral cortical bone as
17.9 GPa in tension and 18.16 GPa in compression. Apparent density is
tissue density times one minus porosity. Mass of a bone is that density
times the mineral volume of the solid.

The look is a pair of procedural maps: an sRGB albedo and a linear
roughness map. MeshStandardMaterial is not ported, so `bone_phong` is the
surface the current renderer can draw. The roughness map is still built,
because a later standard material will read it.

    var tissue = cortical_tissue()
    var mass = tissue.apparent_density() * volume
    var weight = mass * STANDARD_GRAVITY
"""

from materials.material import Material, phong_material
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB
from render.texture import IGNORED, REPEAT, Texture
from render.texture_store import NO_TEXTURE, TextureId
from std.math import isfinite
from units.si import (
    Density,
    GRAM_PER_CUBIC_CENTIMETER,
    GIGAPASCAL,
    MEGAPASCAL,
    Pressure,
)


@fieldwise_init
struct BoneKind(Equatable, ImplicitlyCopyable, Writable):
    """Which tissue a `BoneTissue` describes, as a type rather than a bare int.

    The type stops a bare integer at compile time. A value that is not
    `CORTICAL` or `TRABECULAR` is still constructible, and the boundary
    that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `CORTICAL` or `TRABECULAR`."""
        return self == CORTICAL or self == TRABECULAR


# Compact bone of the diaphysis and the thin shell of the ends.
comptime CORTICAL = BoneKind(0)
# Cancellous bone that fills the head, neck and condyles.
comptime TRABECULAR = BoneKind(1)

# Albedo and roughness maps are square. Eight is the least that still
# shows grain. Two hundred fifty-six is enough for a close camera.
comptime MIN_LOOK = 8
comptime MAX_LOOK = 256


@fieldwise_init
struct BoneTissue(ImplicitlyCopyable):
    """Published density, porosity and elastic modulus of one bone tissue.

    `elastic_modulus` is the longitudinal tension value. Cortical bone
    also stores the compression value from the same table. Poisson's
    ratio is the Table 1 cortical figure; trabecular bone uses 0.3.

    The constructor does not refuse a bad kind. `validate` does that, the
    same way a `Material` can hold a kind that `is_valid` then rejects.
    """

    var kind: BoneKind
    var tissue_density: Density
    var porosity: Float32
    var elastic_modulus: Pressure
    var elastic_modulus_compression: Pressure
    var poisson_ratio: Float32

    def apparent_density(self) -> Density:
        """Return mass per total volume, including pore space.

        Returns:
            `tissue_density` scaled by one minus porosity.
        """
        return self.tissue_density.scaled(Float32(1) - self.porosity)

    def validate(self) raises:
        """Refuse a kind, density, porosity, modulus or Poisson ratio
        that this tissue cannot hold.

        Raises:
            Error: If `kind` is not `CORTICAL` or `TRABECULAR`, if a
                quantity is not finite or not positive, if porosity is
                outside 0 through 1, or if Poisson's ratio is outside
                0 through 1.
        """
        if not self.kind.is_valid():
            raise Error("Bone tissue must be cortical or trabecular")
        if not isfinite(self.tissue_density.value):
            raise Error("A bone tissue density must be finite")
        if self.tissue_density.value <= 0:
            raise Error("A bone tissue density must be positive")
        if not isfinite(self.porosity):
            raise Error("A bone porosity must be finite")
        if self.porosity < 0:
            raise Error("A bone porosity cannot be negative")
        if self.porosity > 1:
            raise Error("A bone porosity cannot exceed one")
        if not isfinite(self.elastic_modulus.value):
            raise Error("A bone elastic modulus must be finite")
        if self.elastic_modulus.value <= 0:
            raise Error("A bone elastic modulus must be positive")
        if not isfinite(self.elastic_modulus_compression.value):
            raise Error("A bone compression modulus must be finite")
        if self.elastic_modulus_compression.value <= 0:
            raise Error("A bone compression modulus must be positive")
        if not isfinite(self.poisson_ratio):
            raise Error("A bone Poisson ratio must be finite")
        if self.poisson_ratio < 0:
            raise Error("A bone Poisson ratio cannot be negative")
        if self.poisson_ratio > 1:
            raise Error("A bone Poisson ratio cannot exceed one")


def cortical_tissue() -> BoneTissue:
    """Return adult femoral cortical bone from Morgan et al. 2018.

    Tissue density is 2.0 g/cm^3. Porosity is 10%, the middle of the
    5% to 15% range. Longitudinal modulus is 17.9 GPa in tension and
    18.16 GPa in compression. Poisson's ratio is 0.62.

    Returns:
        The cortical template.
    """
    return BoneTissue(
        CORTICAL,
        Density(2.0, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.10),
        Pressure(17.9, GIGAPASCAL),
        Pressure(18.16, GIGAPASCAL),
        Float32(0.62),
    )


def trabecular_tissue() -> BoneTissue:
    """Return adult femoral trabecular bone from Morgan et al. 2018.

    Tissue density is 2.0 g/cm^3, the same as cortical bone. Porosity is
    80%, a typical metaphyseal fill inside the 40% to 95% range.
    Apparent modulus is 400 MPa, inside the 10 MPa to 3000 MPa range
    the paper reports. Poisson's ratio is 0.3.

    Returns:
        The trabecular template.
    """
    return BoneTissue(
        TRABECULAR,
        Density(2.0, GRAM_PER_CUBIC_CENTIMETER),
        Float32(0.80),
        Pressure(400.0, MEGAPASCAL),
        Pressure(400.0, MEGAPASCAL),
        Float32(0.30),
    )


def bone_albedo(size: Int = 64) raises -> Texture:
    """Return a square sRGB albedo of cortical bone.

    The map is ivory with grain, a darker posterior strip for the linea
    aspera, and slightly more yellow at the ends. Capsule `u` runs around
    the shaft. Capsule `v` runs from distal to proximal.

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
    linear coverage-ignored data, not sRGB color.

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
