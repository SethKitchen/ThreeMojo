# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Photometric quantities: the light that falls on a surface, and the
light a surface sends toward the eye.

An `Illuminance` is light arriving per area, in lux. A `Luminance` is light
leaving a surface per area and per solid angle, in candela per square
meter (nits). Neither is a `Quantity`: both measure the eye's response to
light, and the luminous intensity is not one of `Quantity`'s dimensions.
Each adds, scales and compares with its own kind only.

A white diffuse surface under an illuminance E shines `E / pi` nits:
`diffuse_luminance` gives it.

    var noon = Illuminance(100, KILOLUX)
    print(noon.to(LUX))                    # 100000
    print(diffuse_luminance(noon).to(NIT)) # 31831
"""

from std.math import pi


@fieldwise_init
struct IlluminanceUnit(ImplicitlyCopyable):
    """A named illuminance unit: how many lux one of it is."""

    var lux: Float32
    var symbol: StaticString


@fieldwise_init
struct LuminanceUnit(ImplicitlyCopyable):
    """A named luminance unit: how many nits one of it is."""

    var nits: Float32
    var symbol: StaticString


comptime LUX = IlluminanceUnit(1.0, "lx")
comptime KILOLUX = IlluminanceUnit(1000.0, "klx")
comptime FOOT_CANDLE = IlluminanceUnit(10.763910417, "fc")
comptime NIT = LuminanceUnit(1.0, "cd/m^2")


struct Illuminance(ImplicitlyCopyable, Writable):
    """Light falling on a surface, stored in lux."""

    var lux: Float32

    def __init__(out self, value: Float32, unit: IlluminanceUnit):
        """Create an illuminance.

        Args:
            value: The amount.
            unit: Its unit, such as `LUX` or `KILOLUX`.
        """
        self.lux = value * unit.lux

    def to(self, unit: IlluminanceUnit) -> Float32:
        """Return the illuminance in a unit.

        Args:
            unit: The unit.

        Returns:
            The amount.
        """
        return self.lux / unit.lux

    def __add__(self, other: Self) -> Self:
        """Add two illuminances.

        Args:
            other: The other illuminance.

        Returns:
            The sum.
        """
        return Self(self.lux + other.lux, LUX)

    def __sub__(self, other: Self) -> Self:
        """Subtract an illuminance.

        Args:
            other: The illuminance to take away.

        Returns:
            The difference.
        """
        return Self(self.lux - other.lux, LUX)

    def __mul__(self, factor: Float32) -> Self:
        """Scale the illuminance.

        Args:
            factor: The factor.

        Returns:
            The scaled illuminance.
        """
        return Self(self.lux * factor, LUX)

    def __rmul__(self, factor: Float32) -> Self:
        """Scale the illuminance.

        Args:
            factor: The factor.

        Returns:
            The scaled illuminance.
        """
        return self * factor

    def __truediv__(self, other: Self) -> Float32:
        """Return the ratio of two illuminances.

        Args:
            other: The divisor.

        Returns:
            How many times `other` this is.
        """
        return self.lux / other.lux

    def __eq__(self, other: Self) -> Bool:
        """Compare two illuminances.

        Args:
            other: The other illuminance.

        Returns:
            Whether they are equal.
        """
        return self.lux == other.lux

    def __lt__(self, other: Self) -> Bool:
        """Compare two illuminances.

        Args:
            other: The other illuminance.

        Returns:
            Whether this one is less.
        """
        return self.lux < other.lux

    def write_to(self, mut writer: Some[Writer]):
        """Write the illuminance in lux.

        Args:
            writer: The destination.
        """
        writer.write(self.lux, " lx")


struct Luminance(ImplicitlyCopyable, Writable):
    """Light leaving a surface toward the eye, stored in nits."""

    var nits: Float32

    def __init__(out self, value: Float32, unit: LuminanceUnit):
        """Create a luminance.

        Args:
            value: The amount.
            unit: Its unit, `NIT`.
        """
        self.nits = value * unit.nits

    def to(self, unit: LuminanceUnit) -> Float32:
        """Return the luminance in a unit.

        Args:
            unit: The unit.

        Returns:
            The amount.
        """
        return self.nits / unit.nits

    def __add__(self, other: Self) -> Self:
        """Add two luminances.

        Args:
            other: The other luminance.

        Returns:
            The sum in nits.

        Raises:
            None.
        """
        return Self(self.nits + other.nits, NIT)

    def __sub__(self, other: Self) -> Self:
        """Subtract a luminance.

        Args:
            other: The luminance to take away.

        Returns:
            The difference in nits.

        Raises:
            None.
        """
        return Self(self.nits - other.nits, NIT)

    def __mul__(self, factor: Float32) -> Self:
        """Scale the luminance.

        Args:
            factor: The factor.

        Returns:
            The scaled luminance.
        """
        return Self(self.nits * factor, NIT)

    def __rmul__(self, factor: Float32) -> Self:
        """Scale the luminance with a factor on the left.

        Args:
            factor: The factor.

        Returns:
            The scaled luminance.

        Raises:
            None.
        """
        return self * factor

    def __truediv__(self, other: Self) -> Float32:
        """Return the ratio of two luminances.

        Args:
            other: The divisor.

        Returns:
            How many times `other` this is.
        """
        return self.nits / other.nits

    def __eq__(self, other: Self) -> Bool:
        """Compare two luminances.

        Args:
            other: The other luminance.

        Returns:
            Whether they are equal.
        """
        return self.nits == other.nits

    def __lt__(self, other: Self) -> Bool:
        """Compare two luminances.

        Args:
            other: The other luminance.

        Returns:
            Whether this one is less.
        """
        return self.nits < other.nits

    def write_to(self, mut writer: Some[Writer]):
        """Write the luminance in nits.

        Args:
            writer: The destination.
        """
        writer.write(self.nits, " cd/m^2")


def diffuse_luminance(illuminance: Illuminance) -> Luminance:
    """Return how bright a white diffuse surface shines under a light.

    Args:
        illuminance: The light falling on it.

    Returns:
        `E / pi`, since a Lambertian surface sends its light over the
        hemisphere's projected solid angle of pi.
    """
    return Luminance(illuminance.lux / Float32(pi), NIT)
