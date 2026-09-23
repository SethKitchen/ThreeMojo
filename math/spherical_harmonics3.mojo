# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Nine colors that stand for light from every direction, from three.js
`src/math/SphericalHarmonics3.js`.

A light probe does not store an image of its surroundings. It stores the
first nine real spherical harmonics of it, bands zero to two: one average
color, three colors that say how the light leans along each axis, and five
that say how it bunches up. That is too little to show a reflection and
enough to light a diffuse surface, because the irradiance a matte surface
catches is a heavily blurred image of the light around it, and nine terms
hold that blur to within a few percent (Ramamoorthi and Hanrahan, "An
Efficient Representation for Irradiance Environment Maps", 2001).

The coefficients are held as one `SIMD` vector of 32 floats, nine colors of
three channels and five spare lanes, rather than nine `Vector3` values in a
list. A `Light` is copied implicitly, and a list is not; a vector also
crosses to the kernel as plain numbers.

`sh_basis` and `sh_irradiance_weight` are the two tables three.js writes out
term by term in `getBasisAt` and `getIrradianceAt`. They take the index of
one term so a loop can walk them, which is what the kernel does with the
coefficients it reads from the light buffer. Both rasterizers call them, so
the two sum the same products in the same order.
"""

from math.vector3 import Vector3
from std.math import isfinite

# How many coefficients bands zero to two hold: three.js's nine.
comptime SH_COUNT = 9


def sh_basis(index: Int, normal: Vector3) -> Float32:
    """Return one real spherical harmonic at a direction: one term of
    three.js's `SphericalHarmonics3.getBasisAt`.

    Args:
        index: Which term, zero to eight.
        normal: A unit direction.

    Returns:
        The basis function's value. Zero for an index past eight, which
        names no term.
    """
    var x = normal.x
    var y = normal.y
    var z = normal.z
    if index == 0:
        return 0.282095
    if index == 1:
        return 0.488603 * y
    if index == 2:
        return 0.488603 * z
    if index == 3:
        return 0.488603 * x
    if index == 4:
        return 1.092548 * x * y
    if index == 5:
        return 1.092548 * y * z
    if index == 6:
        return 0.315392 * (3 * z * z - 1)
    if index == 7:
        return 1.092548 * x * z
    if index == 8:
        return 0.546274 * (x * x - y * y)
    return 0


def sh_irradiance_weight(index: Int, normal: Vector3) -> Float32:
    """Return what one coefficient is multiplied by in the irradiance at a
    normal: one term of three.js's `getIrradianceAt` and of its shader's
    `shGetIrradianceAt`.

    Each basis function convolved with the clamped cosine, which is what a
    matte surface integrates the light around it against. Band zero is
    scaled by pi, band one by two thirds of pi and band two by a quarter of
    pi, as three.js's comments say.

    Args:
        index: Which term, zero to eight.
        normal: The surface's unit normal, in world space.

    Returns:
        The weight. Zero for an index past eight.
    """
    var x = normal.x
    var y = normal.y
    var z = normal.z
    if index == 0:
        return 0.886227
    if index == 1:
        return 2.0 * 0.511664 * y
    if index == 2:
        return 2.0 * 0.511664 * z
    if index == 3:
        return 2.0 * 0.511664 * x
    if index == 4:
        return 2.0 * 0.429043 * x * y
    if index == 5:
        return 2.0 * 0.429043 * y * z
    if index == 6:
        return 0.743125 * z * z - 0.247708
    if index == 7:
        return 2.0 * 0.429043 * x * z
    if index == 8:
        return 0.429043 * (x * x - y * y)
    return 0


struct SphericalHarmonics3(Equatable, ImplicitlyCopyable, Writable):
    """Nine RGB coefficients of the light around a point: three.js's
    `SphericalHarmonics3`."""

    # Coefficient `j`'s red, green and blue at lanes `3j`, `3j + 1` and
    # `3j + 2`. Lanes 27 to 31 are spare and always zero.
    var lanes: SIMD[DType.float32, 32]

    def __init__(out self):
        """Create the harmonics of darkness: every coefficient zero."""
        self.lanes = SIMD[DType.float32, 32](0)

    def coefficient(self, index: Int) raises -> Vector3:
        """Return one coefficient, three.js's `coefficients[index]`.

        Args:
            index: Zero to eight.

        Returns:
            Its red, green and blue as `x`, `y` and `z`.

        Raises:
            Error: If the index names no coefficient.
        """
        _check_index(index)
        return self._at(index)

    def _at(self, index: Int) -> Vector3:
        """Return one coefficient without checking the index."""
        return Vector3(
            self.lanes[index * 3],
            self.lanes[index * 3 + 1],
            self.lanes[index * 3 + 2],
        )

    def set_coefficient(mut self, index: Int, value: Vector3) raises:
        """Replace one coefficient.

        Args:
            index: Zero to eight.
            value: Its red, green and blue as `x`, `y` and `z`.

        Raises:
            Error: If the index names no coefficient.
        """
        _check_index(index)
        self.lanes[index * 3] = value.x
        self.lanes[index * 3 + 1] = value.y
        self.lanes[index * 3 + 2] = value.z

    def zero(mut self):
        """Set every coefficient to zero, three.js's `zero`."""
        self.lanes = SIMD[DType.float32, 32](0)

    def get_at(self, normal: Vector3) -> Vector3:
        """Return the radiance arriving from a direction, three.js's
        `getAt`.

        Args:
            normal: A unit direction.

        Returns:
            The color, as `x`, `y` and `z`.
        """
        return self._sum(normal, False)

    def get_irradiance_at(self, normal: Vector3) -> Vector3:
        """Return the irradiance a surface facing `normal` catches,
        three.js's `getIrradianceAt`.

        The light from every direction weighted by the clamped cosine. It
        includes the factor of pi a cosine integral has: divide by pi for
        what a white Lambert surface sends back, as three.js's
        `BRDF_Lambert` does.

        Args:
            normal: A unit direction.

        Returns:
            The irradiance, as `x`, `y` and `z`.
        """
        return self._sum(normal, True)

    def _sum(self, normal: Vector3, irradiance: Bool) -> Vector3:
        """Return the coefficients weighted by the basis or by the
        irradiance weights, summed in index order."""
        var total = Vector3(0, 0, 0)
        for index in range(SH_COUNT):  # pragma: no branch
            # One weight or the other, never both: this runs nine times per
            # shaded point.
            var weight = sh_irradiance_weight(
                index, normal
            ) if irradiance else sh_basis(index, normal)
            var term = self._at(index)
            total = Vector3(
                total.x + term.x * weight,
                total.y + term.y * weight,
                total.z + term.z * weight,
            )
        return total

    def add(mut self, other: Self):
        """Add another set's coefficients, three.js's `add`.

        Args:
            other: The harmonics to add.
        """
        self.lanes = self.lanes + other.lanes

    def add_scaled(mut self, other: Self, scale: Float32):
        """Add another set's coefficients times a number, three.js's
        `addScaledSH`.

        Args:
            other: The harmonics to add.
            scale: What each of its coefficients is multiplied by.
        """
        self.lanes = self.lanes + other.lanes * scale

    def scale(mut self, factor: Float32):
        """Multiply every coefficient, three.js's `scale`.

        Args:
            factor: The multiplier.
        """
        self.lanes = self.lanes * factor

    def lerp(mut self, other: Self, alpha: Float32):
        """Move every coefficient toward another set's, three.js's `lerp`.

        Args:
            other: Where alpha one arrives.
            alpha: How far, zero for no change.
        """
        self.lanes = self.lanes + (other.lanes - self.lanes) * alpha

    def is_finite(self) -> Bool:
        """Return True if every coefficient is a finite number."""
        for lane in range(SH_COUNT * 3):  # pragma: no branch
            if not isfinite(self.lanes[lane]):
                return False
        return True

    def to_array(self) -> List[Float32]:
        """Return the 27 numbers in coefficient order, three.js's
        `toArray`."""
        var out = List[Float32]()
        for lane in range(SH_COUNT * 3):  # pragma: no branch
            out.append(self.lanes[lane])
        return out^

    def __eq__(self, other: Self) -> Bool:
        """Return True if every coefficient matches, three.js's `equals`."""
        return self.lanes == other.lanes

    def write_to(self, mut writer: Some[Writer]):
        """Write the 27 numbers.

        Args:
            writer: Where to write them.
        """
        writer.write("SphericalHarmonics3(")
        for lane in range(SH_COUNT * 3):  # pragma: no branch
            if lane > 0:
                writer.write(", ")
            writer.write(self.lanes[lane])
        writer.write(")")


def sh_from_array(
    values: List[Float32], offset: Int = 0
) raises -> SphericalHarmonics3:
    """Return harmonics read from 27 numbers, three.js's `fromArray`.

    Args:
        values: The numbers, nine colors of three channels each.
        offset: Where in `values` the first one is.

    Returns:
        The harmonics.

    Raises:
        Error: If fewer than 27 numbers follow the offset, or the offset
            is negative.
    """
    if offset < 0 or len(values) - offset < SH_COUNT * 3:
        raise Error("Spherical harmonics are read from 27 numbers")
    var sh = SphericalHarmonics3()
    for lane in range(SH_COUNT * 3):  # pragma: no branch
        sh.lanes[lane] = values[offset + lane]
    return sh


def _check_index(index: Int) raises:
    """Refuse an index that names none of the nine coefficients."""
    if index < 0 or index >= SH_COUNT:
        raise Error("Spherical harmonics hold nine coefficients, zero to eight")
