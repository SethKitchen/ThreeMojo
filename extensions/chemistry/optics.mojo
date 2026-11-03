# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Thin-film optics: the reflectance and color of an oxide on a metal.

An anodized metal and a tempered steel take their color from light that
reflects from both faces of a thin oxide and interferes. `film_reflectance`
sums the reflections of one transparent film on an absorbing substrate at
normal incidence (Born and Wolf, "Principles of Optics", 1.6):

    r = (r01 + r12 e^(2 i b)) / (1 + r01 r12 e^(2 i b))
    r01 = (1 - n1) / (1 + n1),  r12 = (n1 - N2) / (n1 + N2)
    b = 2 pi n1 t / wavelength

where n1 is the film's index, t its thickness and N2 = n + i k the
substrate's complex index. The reflectance is |r|^2.

`film_color` weights the reflectance by the CIE 1931 color matching
functions, in the analytic fit of Wyman, Sloan and Shirley (2013), from
380 nm to 780 nm under an equal-energy light. It returns X, Y and Z, with
Y = 1 for a perfect mirror. `linear_srgb` turns X, Y and Z into linear
sRGB with a D65 white. `anodic_thickness` is the thickness of an anodic
film that grows a fixed amount per volt. That growth depends on the metal
and the electrolyte, so measure it.
"""

from std.math import cos, exp, isfinite, pi, sin
from units.si import Length64, NANOMETER

# The color integral: 380 nm to 780 nm in steps of 5 nm.
comptime _FIRST = 380.0
comptime _STEP = 5.0
comptime _COUNT = 81


@fieldwise_init
struct _Complex(ImplicitlyCopyable):
    """A complex number, for the reflection sum."""

    var re: Float64
    var im: Float64

    def __add__(self, other: Self) -> Self:
        """Add."""
        return Self(self.re + other.re, self.im + other.im)

    def __mul__(self, other: Self) -> Self:
        """Multiply."""
        return Self(
            self.re * other.re - self.im * other.im,
            self.re * other.im + self.im * other.re,
        )

    def __truediv__(self, other: Self) -> Self:
        """Divide by a nonzero number."""
        var d = other.re * other.re + other.im * other.im
        return Self(
            (self.re * other.re + self.im * other.im) / d,
            (self.im * other.re - self.re * other.im) / d,
        )

    def norm(self) -> Float64:
        """Return the squared magnitude."""
        return self.re * self.re + self.im * self.im


@fieldwise_init
struct ComplexIndex(ImplicitlyCopyable):
    """A complex refractive index N = n + i k."""

    var n: Float64
    var k: Float64


@fieldwise_init
struct Tristimulus(ImplicitlyCopyable):
    """CIE 1931 X, Y and Z."""

    var x: Float64
    var y: Float64
    var z: Float64


def film_reflectance(
    thickness: Length64,
    film: Float64,
    substrate: ComplexIndex,
    wavelength: Length64,
) raises -> Float64:
    """Return the normal-incidence reflectance of a film on a substrate.

    Args:
        thickness: The film's thickness, zero or more.
        film: The film's real refractive index, at least 1.
        substrate: The substrate's complex index.
        wavelength: The wavelength in vacuum.

    Returns:
        The share of light reflected, from zero to one.

    Raises:
        Error: If the thickness is negative, the film's index is below
            one, the substrate's index is negative, or the wavelength is
            not positive.
    """
    if not (isfinite(thickness.value) and thickness.value >= 0):
        raise Error("A film thickness must be finite and not negative")
    if not (isfinite(film) and film >= 1):
        raise Error("A film index must be finite and at least 1")
    if not (substrate.n >= 0 and substrate.k >= 0):
        raise Error("A substrate index must not be negative")
    if not (isfinite(wavelength.value) and wavelength.value > 0):
        raise Error("A wavelength must be finite and positive")
    var one = _Complex(1, 0)
    var n1 = _Complex(film, 0)
    var n2 = _Complex(substrate.n, substrate.k)
    var r01 = _Complex(1 - film, 0) / _Complex(1 + film, 0)
    var r12 = (n1 + _Complex(-n2.re, -n2.im)) / (n1 + n2)
    var b = 2 * pi * film * thickness.value / wavelength.value
    var phase = _Complex(cos(2 * b), sin(2 * b))
    var r = (r01 + r12 * phase) / (one + r01 * r12 * phase)
    return r.norm()


def _lobe(
    wavelength: Float64, mean: Float64, left: Float64, right: Float64
) -> Float64:
    """Return a Gaussian with a different width on each side of its peak."""
    var width = left
    if wavelength >= mean:
        width = right
    var u = (wavelength - mean) / width
    return exp(-0.5 * u * u)


def color_matching(wavelength_nm: Float64) -> Tristimulus:
    """Return the CIE 1931 color matching functions at a wavelength.

    Args:
        wavelength_nm: The wavelength in nanometers.

    Returns:
        The values x-bar, y-bar and z-bar, by the multi-lobe fit of Wyman, Sloan and
        Shirley (2013).
    """
    var w = wavelength_nm
    var x = (
        1.056 * _lobe(w, 599.8, 37.9, 31.0)
        + 0.362 * _lobe(w, 442.0, 16.0, 26.7)
        - 0.065 * _lobe(w, 501.1, 20.4, 26.2)
    )
    var y = 0.821 * _lobe(w, 568.8, 46.9, 40.5) + 0.286 * _lobe(
        w, 530.9, 16.3, 31.1
    )
    var z = 1.217 * _lobe(w, 437.0, 11.8, 36.0) + 0.681 * _lobe(
        w, 459.0, 26.0, 13.8
    )
    return Tristimulus(x, y, z)


def film_color(
    thickness: Length64, film: Float64, substrate: ComplexIndex
) raises -> Tristimulus:
    """Return the color a film on a substrate reflects.

    Args:
        thickness: The film's thickness.
        film: The film's refractive index.
        substrate: The substrate's complex index.

    Returns:
        X, Y and Z under an equal-energy light, with Y = 1 for a perfect
        mirror.

    Raises:
        Error: If an argument is not valid. See `film_reflectance`.
    """
    var sx = Float64(0)
    var sy = Float64(0)
    var sz = Float64(0)
    var white = Float64(0)
    for i in range(_COUNT):  # pragma: no branch
        var w = _FIRST + _STEP * Float64(i)
        var r = film_reflectance(
            thickness, film, substrate, Length64(w, NANOMETER)
        )
        var c = color_matching(w)
        sx += r * c.x
        sy += r * c.y
        sz += r * c.z
        white += c.y
    return Tristimulus(sx / white, sy / white, sz / white)


def linear_srgb(color: Tristimulus) -> Tuple[Float64, Float64, Float64]:
    """Return X, Y and Z as linear sRGB, with a D65 white.

    Args:
        color: The tristimulus values.

    Returns:
        Red, green and blue, before any clipping or gamma.
    """
    var x = color.x
    var y = color.y
    var z = color.z
    return (
        3.2406 * x - 1.5372 * y - 0.4986 * z,
        -0.9689 * x + 1.8758 * y + 0.0415 * z,
        0.0557 * x - 0.2040 * y + 1.0570 * z,
    )


def anodic_thickness(volts: Float64, growth: Length64) raises -> Length64:
    """Return the thickness of an anodic film grown to a voltage.

    Args:
        volts: The anodizing voltage, zero or more.
        growth: The thickness the film grows per volt.

    Returns:
        The thickness, growth times voltage.

    Raises:
        Error: If the voltage is negative or the growth is not positive.
    """
    if not (isfinite(volts) and volts >= 0):
        raise Error("A voltage must be finite and not negative")
    if not (isfinite(growth.value) and growth.value > 0):
        raise Error("A growth per volt must be finite and positive")
    return Length64(growth.value * volts)
