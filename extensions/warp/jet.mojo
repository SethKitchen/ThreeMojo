# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact first and second derivatives, by forward automatic differentiation.

A `Jet` carries a value with its gradient and its Hessian in the four
coordinates x⁰ = c t, x, y and z. Arithmetic on jets applies the chain
rule, so a formula written with jets gives its derivatives with no
finite differences: no step, no truncation error and no edge of the
grid.

A function of one variable φ maps a jet f to

    value   φ(f)
    ∂ₐ      φ'(f) ∂ₐf
    ∂ₐ∂ᵦ    φ'(f) ∂ₐ∂ᵦf + φ''(f) ∂ₐf ∂ᵦf

and a product of jets uses the product rule to second order. See
Griewank and Walther, "Evaluating Derivatives", 2nd edition, 2008,
chapter 13.
"""

from std.math import cosh, exp, log, sqrt, tanh

comptime Gradient = SIMD[DType.float64, 4]
"""The derivatives along x⁰, x, y and z."""
comptime Hessian = SIMD[DType.float64, 16]
"""The second derivatives: ∂ₐ∂ᵦ is at 4 a + b."""


def _outer(a: Gradient, b: Gradient) -> Hessian:
    """Return the symmetric product a ⊗ b + b ⊗ a."""
    var out = Hessian(0)
    for i in range(4):
        for j in range(4):
            out[4 * i + j] = a[i] * b[j] + b[i] * a[j]
    return out


def _square(a: Gradient) -> Hessian:
    """Return a ⊗ a."""
    var out = Hessian(0)
    for i in range(4):
        for j in range(4):
            out[4 * i + j] = a[i] * a[j]
    return out


@fieldwise_init
struct Jet(ImplicitlyCopyable, Movable):
    """A value with its exact gradient and Hessian in four coordinates."""

    var value: Float64
    """The value."""
    var gradient: Gradient
    """The first derivatives."""
    var hessian: Hessian
    """The second derivatives."""

    @staticmethod
    def constant(value: Float64) -> Jet:
        """Return a jet that does not depend on the coordinates.

        Args:
            value: The value.

        Returns:
            The jet, with zero derivatives.
        """
        return Jet(value, Gradient(0), Hessian(0))

    @staticmethod
    def variable(value: Float64, axis: Int) -> Jet:
        """Return the jet of one coordinate.

        Args:
            value: The value of the coordinate.
            axis: The coordinate, 0 to 3.

        Returns:
            The jet, with a derivative of 1 along its own axis.
        """
        var gradient = Gradient(0)
        gradient[axis] = 1.0
        return Jet(value, gradient, Hessian(0))

    def apply(self, f: Float64, df: Float64, ddf: Float64) -> Jet:
        """Return a function of this jet, by the chain rule.

        Args:
            f: The function φ at the jet's value.
            df: φ' at the jet's value.
            ddf: φ'' at the jet's value.

        Returns:
            The jet of φ of this jet.
        """
        return Jet(
            f,
            df * self.gradient,
            df * self.hessian + ddf * _square(self.gradient),
        )

    def __add__(self, other: Jet) -> Jet:
        """Return the sum.

        Args:
            other: The other jet.

        Returns:
            The sum self + other.
        """
        return Jet(
            self.value + other.value,
            self.gradient + other.gradient,
            self.hessian + other.hessian,
        )

    def __sub__(self, other: Jet) -> Jet:
        """Return the difference.

        Args:
            other: The other jet.

        Returns:
            The difference self - other.
        """
        return Jet(
            self.value - other.value,
            self.gradient - other.gradient,
            self.hessian - other.hessian,
        )

    def __neg__(self) -> Jet:
        """Return the negation.

        Returns:
            The negation -self.
        """
        return Jet(-self.value, -self.gradient, -self.hessian)

    def __mul__(self, other: Jet) -> Jet:
        """Return the product, by the product rule.

        Args:
            other: The other jet.

        Returns:
            The product self times other.
        """
        return Jet(
            self.value * other.value,
            self.value * other.gradient + other.value * self.gradient,
            self.value * other.hessian
            + other.value * self.hessian
            + _outer(self.gradient, other.gradient),
        )

    def __truediv__(self, other: Jet) -> Jet:
        """Return the quotient.

        Args:
            other: The divisor. Its value must not be zero.

        Returns:
            The quotient self divided by other. The value is the plain quotient, so it
            rounds as a division of floats does.
        """
        var q = self.value / other.value
        var dq = (self.gradient - q * other.gradient) / other.value
        return Jet(
            q,
            dq,
            (self.hessian - q * other.hessian - _outer(dq, other.gradient))
            / other.value,
        )

    def scaled(self, factor: Float64) -> Jet:
        """Return the jet times a constant.

        Args:
            factor: The constant.

        Returns:
            The product factor times self.
        """
        return Jet(
            self.value * factor, self.gradient * factor, self.hessian * factor
        )

    def shifted(self, offset: Float64) -> Jet:
        """Return the jet plus a constant.

        Args:
            offset: The constant.

        Returns:
            The sum self + offset.
        """
        return Jet(self.value + offset, self.gradient, self.hessian)

    def reciprocal(self) -> Jet:
        """Return 1 over the jet.

        Returns:
            The reciprocal 1 / self. The value must not be zero.
        """
        var r = 1.0 / self.value
        return self.apply(r, -r * r, 2.0 * r * r * r)

    def squared(self) -> Jet:
        """Return the square.

        Returns:
            The square self times self.
        """
        return self * self

    def sqrt(self) -> Jet:
        """Return the square root.

        Returns:
            The root √self. The value must be positive.
        """
        var s = sqrt(self.value)
        return self.apply(s, 0.5 / s, -0.25 / (s * self.value))

    def tanh(self) -> Jet:
        """Return the hyperbolic tangent.

        Returns:
            The value tanh(self).
        """
        var t = tanh(self.value)
        var sech2 = 1.0 / cosh(self.value) ** 2
        return self.apply(t, sech2, -2.0 * t * sech2)

    def exp(self) -> Jet:
        """Return the exponential.

        Returns:
            The value e to the power of self.
        """
        var e = exp(self.value)
        return self.apply(e, e, e)

    def log(self) -> Jet:
        """Return the natural logarithm.

        Returns:
            The value ln(self). The value must be positive.
        """
        var r = 1.0 / self.value
        return self.apply(log(self.value), r, -r * r)

    def second(self, a: Int, b: Int) -> Float64:
        """Return one second derivative.

        Args:
            a: The first coordinate, 0 to 3.
            b: The second coordinate, 0 to 3.

        Returns:
            ∂ₐ∂ᵦ of the jet.
        """
        return self.hessian[4 * a + b]


def jet_place(x0: Float64, x: Float64, y: Float64, z: Float64) -> List[Jet]:
    """Return the jets of the four coordinates at a place.

    Args:
        x0: The time coordinate c t, in meters.
        x: The x coordinate, in meters.
        y: The y coordinate, in meters.
        z: The z coordinate, in meters.

    Returns:
        The four coordinate jets, x⁰ first.
    """
    return [
        Jet.variable(x0, 0),
        Jet.variable(x, 1),
        Jet.variable(y, 2),
        Jet.variable(z, 3),
    ]
