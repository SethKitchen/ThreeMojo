# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Binary solutions: activities and phase boundaries.

A `PhaseModel` is one phase of a binary system of components 1 and 2,
such as the liquid or a solid solution of an alloy. Its molar Gibbs
energy at the mole fraction x of component 2 is

    G = (1 - x) G1 + x G2 + R T ((1 - x) ln(1 - x) + x ln x) + Gex
    Gex = x (1 - x) sum_k L_k (1 - 2 x)^k

G1 and G2 are the pure components' energies in this phase, and the L_k
are the Redlich-Kister parameters. Each is a `Linear` function of
temperature, a + b T. With no L_k the solution is ideal, and with L0 only
it is regular. `activity` gives a component's activity, which a reaction
can take as a condensed term's fraction.

`phase_boundaries` finds the two-phase regions at a temperature. It takes
the lower convex hull of every phase's Gibbs curve. A stretch of the hull
that spans no sampled point is a tie line between two phases, or between
two compositions of one phase across a miscibility gap. The ends of each
tie line are the phase boundaries, to the sampling step.

The parameters of a real alloy come from an assessment such as a CALPHAD
database. Most such databases are licensed, so this module takes the
parameters as inputs.
"""

from std.math import exp, isfinite, log
from extensions.chemistry.quantities import (
    GAS_CONSTANT,
    MolarEnergy64,
    MolarEntropy64,
)
from units.temperature import Temperature64

# The most samples of each phase's Gibbs curve.
comptime MAX_SAMPLES = 100_000


@fieldwise_init
struct Linear(ImplicitlyCopyable):
    """A molar energy that varies linearly with temperature: a + b T."""

    var a: MolarEnergy64
    var b: MolarEntropy64

    def at(self, temperature: Temperature64) -> Float64:
        """Return the value at a temperature, in J/mol.

        Args:
            temperature: The temperature.

        Returns:
            The value a + b T.
        """
        return self.a.value + self.b.value * temperature.kelvin


struct PhaseModel(Copyable, Movable):
    """One phase of a binary system, with a Redlich-Kister excess energy."""

    var name: String
    var g1: Linear
    var g2: Linear
    # L0, L1, ... of the excess energy.
    var interaction: List[Linear]

    def __init__(
        out self,
        name: String,
        g1: Linear,
        g2: Linear,
        var interaction: List[Linear],
    ) raises:
        """Make a phase model.

        Args:
            name: The phase's name, such as "liquid" or "fcc".
            g1: Pure component 1's Gibbs energy in this phase.
            g2: Pure component 2's Gibbs energy in this phase.
            interaction: The Redlich-Kister parameters, L0 first. Empty
                for an ideal solution.

        Raises:
            Error: If a parameter is not finite.
        """
        var all: List[Linear] = [g1, g2]
        for p in interaction:
            all.append(p)
        for p in all:  # pragma: no branch
            if not (isfinite(p.a.value) and isfinite(p.b.value)):
                raise Error("A phase parameter must be finite")
        self.name = name
        self.g1 = g1
        self.g2 = g2
        self.interaction = interaction^

    def excess(self, x: Float64, temperature: Temperature64) raises -> Float64:
        """Return the excess Gibbs energy at a composition, in J/mol.

        Args:
            x: The mole fraction of component 2, from 0 to 1.
            temperature: The temperature.

        Returns:
            The energy x (1 - x) sum_k L_k (1 - 2 x)^k.

        Raises:
            Error: If the mole fraction is not from 0 to 1.
        """
        _require_fraction(x)
        var d = 1 - 2 * x
        var total = Float64(0)
        var power = Float64(1)
        for p in self.interaction:
            total += p.at(temperature) * power
            power *= d
        return x * (1 - x) * total

    def gibbs(self, x: Float64, temperature: Temperature64) raises -> Float64:
        """Return the molar Gibbs energy at a composition, in J/mol.

        Args:
            x: The mole fraction of component 2, from 0 to 1.
            temperature: The temperature, above absolute zero.

        Returns:
            The pure parts, the ideal mixing term and the excess.

        Raises:
            Error: If the mole fraction is not from 0 to 1 or the
                temperature is not positive.
        """
        _require_temperature(temperature)
        var rt = GAS_CONSTANT.value * temperature.kelvin
        var g = (1 - x) * self.g1.at(temperature) + x * self.g2.at(temperature)
        return (
            g
            + rt * (_x_log_x(x) + _x_log_x(1 - x))
            + self.excess(x, temperature)
        )

    def log_gamma(
        self, component: Int, x: Float64, temperature: Temperature64
    ) raises -> Float64:
        """Return the natural log of a component's activity coefficient.

        Args:
            component: 1 or 2.
            x: The mole fraction of component 2, from 0 to 1.
            temperature: The temperature, above absolute zero.

        Returns:
            The value ln gamma, from the Redlich-Kister series term by
            term.

        Raises:
            Error: If the component is not 1 or 2, or another argument is
                out of range.
        """
        _require_fraction(x)
        _require_temperature(temperature)
        if not (component == 1 or component == 2):
            raise Error("A binary solution has components 1 and 2")
        var x1 = 1 - x
        var x2 = x
        var d = x1 - x2
        var total = Float64(0)
        var power = Float64(1)
        # For L_k: RT ln g1 = x2^2 L_k d^(k-1) ((2k+1) x1 - x2), and
        # RT ln g2 = x1^2 L_k d^(k-1) (x1 - (2k+1) x2). For k = 0 both
        # reduce to x2^2 L0 and x1^2 L0.
        for k in range(len(self.interaction)):
            var l = self.interaction[k].at(temperature)
            if k == 0:
                if component == 1:
                    total += x2 * x2 * l
                else:
                    total += x1 * x1 * l
            else:
                var f = Float64(2 * k + 1)
                if component == 1:
                    total += x2 * x2 * l * power * (f * x1 - x2)
                else:
                    total += x1 * x1 * l * power * (x1 - f * x2)
                power *= d
        return total / (GAS_CONSTANT.value * temperature.kelvin)

    def activity(
        self, component: Int, x: Float64, temperature: Temperature64
    ) raises -> Float64:
        """Return a component's activity, relative to it pure in this phase.

        Args:
            component: 1 or 2.
            x: The mole fraction of component 2, from 0 to 1.
            temperature: The temperature, above absolute zero.

        Returns:
            The mole fraction times the activity coefficient.

        Raises:
            Error: If an argument is out of range.
        """
        var g = self.log_gamma(component, x, temperature)
        var fraction = x
        if component == 1:
            fraction = 1 - x
        return fraction * exp(g)


def _x_log_x(x: Float64) -> Float64:
    """Return x ln x, zero at x = 0."""
    if x <= 0:
        return 0
    return x * log(x)


def _require_fraction(x: Float64) raises:
    """Refuse a mole fraction outside [0, 1]."""
    if not (x >= 0 and x <= 1):
        raise Error("A mole fraction must lie from 0 to 1")


def _require_temperature(temperature: Temperature64) raises:
    """Refuse a temperature that is not finite and positive."""
    if not (temperature.is_valid() and temperature.kelvin > 0):
        raise Error("A temperature must be finite and positive")


@fieldwise_init
struct TieLine(ImplicitlyCopyable):
    """A two-phase region at one temperature, between two compositions."""

    # The phases at each end, by index in the list given.
    var left_phase: Int
    var right_phase: Int
    # The mole fractions of component 2 at each end.
    var left: Float64
    var right: Float64


def _cross(
    ax: Float64, ay: Float64, bx: Float64, by: Float64, cx: Float64, cy: Float64
) -> Float64:
    """Return the z of (b - a) x (c - a)."""
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)


def phase_boundaries(
    phases: List[PhaseModel], temperature: Temperature64, samples: Int = 2000
) raises -> List[TieLine]:
    """Return the two-phase regions of a binary system at a temperature.

    Args:
        phases: The phases that can form.
        temperature: The temperature.
        samples: The steps each Gibbs curve is sampled in, from 10 to
            100000. The boundaries are accurate to one step.

    Returns:
        The tie lines, from component 1 toward component 2. A system with
        no tie line is one phase at every composition.

    Raises:
        Error: If there is no phase, the sample count is out of range, or
            the temperature is not positive.
    """
    if len(phases) == 0:
        raise Error("A phase diagram needs a phase")
    if not (samples >= 10 and samples <= MAX_SAMPLES):
        raise Error("A curve takes 10 to 100000 samples")
    _require_temperature(temperature)
    # The lowest phase at each composition first: the hull of all curves
    # is the hull of their lower envelope.
    var xs = List[Float64]()
    var gs = List[Float64]()
    var which = List[Int]()
    for i in range(samples + 1):  # pragma: no branch
        var x = Float64(i) / Float64(samples)
        var best = 0
        var best_g = phases[0].gibbs(x, temperature)
        for j in range(1, len(phases)):
            var g = phases[j].gibbs(x, temperature)
            if g < best_g:
                best = j
                best_g = g
        xs.append(x)
        gs.append(best_g)
        which.append(best)
    # The lower hull, by Andrew's monotone chain.
    var hull = List[Int]()
    for i in range(len(xs)):  # pragma: no branch
        while len(hull) >= 2:
            var a = hull[len(hull) - 2]
            var b = hull[len(hull) - 1]
            if _cross(xs[a], gs[a], xs[b], gs[b], xs[i], gs[i]) <= 0:
                _ = hull.pop()
            else:
                break
        hull.append(i)
    var out = List[TieLine]()
    for k in range(1, len(hull)):  # pragma: no branch
        var a = hull[k - 1]
        var b = hull[k]
        if b - a > 1:
            out.append(TieLine(which[a], which[b], xs[a], xs[b]))
    return out^
