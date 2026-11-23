# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The head that a pipe loses to friction, by three formulas.

Each formula gives the loss h of a flow q in a pipe of length L and
diameter d, in SI units:

- Hazen-Williams: h = 10.67 L q^1.852 / (C^1.852 d^4.8704).
- Darcy-Weisbach: h = f (L / d) v² / (2 g), with the friction factor f.
- Chezy-Manning: h = n² L v² / R^(4/3), with the hydraulic radius
  R = d / 4 of a full pipe.

The friction factor follows EPANET. Below a Reynolds number of 2000 it is
64 / Re, the law of Hagen and Poiseuille. Above 4000 it is the formula of
Swamee and Jain, which is close to the Colebrook-White equation. Between
them it is a cubic that meets both, from Dunlop, 1991. See Rossman,
"EPANET 2 Users Manual", EPA/600/R-00/057, 2000, section 3.1.

A fitting adds a minor loss of K v² / (2 g).
"""

from std.math import isfinite, log, pi
from extensions.hydraulics.kinds import (
    CHEZY_MANNING,
    DARCY_WEISBACH,
    HAZEN_WILLIAMS,
    HeadLossFormula,
)
from units.si import Length64, METER

# The standard acceleration of gravity, in meters per second squared.
comptime GRAVITY = 9.80665
# The exponent of the flow in the Hazen-Williams formula.
comptime HAZEN_WILLIAMS_EXPONENT = 1.852
# Below this gradient of the loss, in seconds per square meter, a pipe has
# a linear loss instead. EPANET does the same, so that a pipe at rest
# does not make the equations singular.
comptime LOW_GRADIENT = 1e-7


struct Roughness(ImplicitlyCopyable):
    """A head loss formula and its roughness coefficient."""

    var formula: HeadLossFormula
    # The Hazen-Williams C, the roughness height in meters, or the Manning
    # n.
    var value: Float64

    def __init__(out self, formula: HeadLossFormula, value: Float64):
        """Hold a roughness. `hazen_williams`, `darcy_weisbach` and
        `chezy_manning` make these.

        Args:
            formula: The formula.
            value: Its coefficient.
        """
        self.formula = formula
        self.value = value

    def is_valid(self) -> Bool:
        """Return True if a pipe can use the roughness.

        Returns:
            Whether the formula is valid and the value is finite and
            positive. A Darcy-Weisbach roughness can be zero, for a
            smooth pipe.
        """
        if not self.formula.is_valid() or not isfinite(self.value):
            return False
        if self.formula == DARCY_WEISBACH:
            return self.value >= 0
        return self.value > 0


def hazen_williams(c: Float64) -> Roughness:
    """Return a Hazen-Williams roughness.

    Args:
        c: The coefficient C. New cast iron is about 130 and old cast
            iron about 100.

    Returns:
        The roughness. `PipeNetwork.add_pipe` refuses a value that is not
        positive.
    """
    return Roughness(HAZEN_WILLIAMS, c)


def darcy_weisbach(height: Length64) -> Roughness:
    """Return a Darcy-Weisbach roughness.

    Args:
        height: The roughness height ε of the pipe wall. Commercial
            steel is about 0.045 mm.

    Returns:
        The roughness. `PipeNetwork.add_pipe` refuses a negative height.
    """
    return Roughness(DARCY_WEISBACH, height.to(METER))


def chezy_manning(n: Float64) -> Roughness:
    """Return a Chezy-Manning roughness.

    Args:
        n: The Manning coefficient, in s / m^(1/3). Concrete is about
            0.012.

    Returns:
        The roughness. `PipeNetwork.add_pipe` refuses a value that is not
        positive.
    """
    return Roughness(CHEZY_MANNING, n)


def friction_factor(reynolds: Float64, relative_roughness: Float64) -> Float64:
    """Return the Darcy friction factor of a pipe.

    Args:
        reynolds: The Reynolds number v d / ν. Positive.
        relative_roughness: The roughness height over the diameter. Zero
            or more.

    Returns:
        The factor: 64 / Re below 2000, the formula of Swamee and Jain
        from 4000, and the cubic of Dunlop between them.
    """
    if reynolds < 2000:
        return 64 / reynolds
    var rough = relative_roughness / 3.7
    if reynolds >= 4000:
        # 0.86859 ln x is 2 log10 x.
        var y = 0.86859 * log(rough + 5.74 / reynolds**0.9)
        return 1 / (y * y)
    var y2 = rough + 5.74 / reynolds**0.9
    var y3 = -0.86859 * log(rough + 5.74 / 4000.0**0.9)
    var fa = 1 / (y3 * y3)
    var fb = fa * (2 - 0.00514215 / (y2 * y3))
    var r = reynolds / 2000
    var x1 = 7 * fa - fb
    var x2 = 0.128 - 17 * fa + 2.5 * fb
    var x3 = -0.128 + 13 * fa - 2 * fb
    var x4 = r * (0.032 - 3 * fa + 0.5 * fb)
    return x1 + r * (x2 + r * (x3 + x4))


@fieldwise_init
struct HeadLoss(ImplicitlyCopyable):
    """The head loss of a flow and its rate of change with the flow."""

    # The loss, in meters. Zero or more.
    var loss: Float64
    # The derivative of the loss by the flow, in seconds per square
    # meter. Positive.
    var gradient: Float64


def pipe_head_loss(
    flow: Float64,
    length: Float64,
    diameter: Float64,
    roughness: Roughness,
    minor: Float64,
    viscosity: Float64,
) -> HeadLoss:
    """Return the head loss of a flow in a pipe, and its gradient.

    The Darcy-Weisbach gradient takes the friction factor as constant, as
    EPANET does. A flow whose gradient is below 1e-7 s/m² has the linear
    loss of that gradient, except in laminar flow, which is linear
    already.

    Args:
        flow: The size of the flow, in cubic meters per second. Zero or
            more.
        length: The length, in meters. Positive.
        diameter: The inside diameter, in meters. Positive.
        roughness: The formula and its coefficient. Valid.
        minor: The minor loss coefficient K. Zero or more.
        viscosity: The kinematic viscosity, in square meters per second.
            Positive. Only the Darcy-Weisbach formula uses it.

    Returns:
        The loss and its gradient.
    """
    var d2 = diameter * diameter
    var minor_term = 8 * minor / (GRAVITY * pi * pi * d2 * d2)
    var loss: Float64
    var gradient: Float64
    if roughness.formula == HAZEN_WILLIAMS:
        var r = (
            10.67
            * length
            / (roughness.value**HAZEN_WILLIAMS_EXPONENT * diameter**4.8704)
        )
        loss = r * flow**HAZEN_WILLIAMS_EXPONENT
        gradient = (
            HAZEN_WILLIAMS_EXPONENT * r * flow ** (HAZEN_WILLIAMS_EXPONENT - 1)
        )
    elif roughness.formula == CHEZY_MANNING:
        # n² L v² / R^(4/3) with v = 4 q / (π d²) and R = d / 4.
        var r = (
            16
            * 4.0 ** (4.0 / 3.0)
            / (pi * pi)
            * roughness.value
            * roughness.value
            * length
            / diameter ** (16.0 / 3.0)
        )
        loss = r * flow * flow
        gradient = 2 * r * flow
    else:
        var reynolds = 4 * flow / (pi * diameter * viscosity)
        if reynolds < 2000:
            # Hagen and Poiseuille: the loss is linear in the flow.
            gradient = (
                128 * viscosity * length / (pi * GRAVITY * d2 * d2)
                + 2 * minor_term * flow
            )
            loss = (
                128 * viscosity * length / (pi * GRAVITY * d2 * d2) * flow
                + minor_term * flow * flow
            )
            return HeadLoss(loss, gradient)
        var f = friction_factor(reynolds, roughness.value / diameter)
        var r = 8 * f * length / (GRAVITY * pi * pi * d2 * d2 * diameter)
        loss = r * flow * flow
        gradient = 2 * r * flow
    loss += minor_term * flow * flow
    gradient += 2 * minor_term * flow
    if gradient < LOW_GRADIENT:
        return HeadLoss(LOW_GRADIENT * flow, LOW_GRADIENT)
    return HeadLoss(loss, gradient)
