# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Response spectrum analysis of a structural model.

A response spectrum gives the peak pseudo-acceleration S_a of a damped
oscillator of each period under one ground motion. A structure responds
in each of its modes as such an oscillator. For a ground motion along
one axis, with r the rigid motion along it and φ a mode with φᵀ M φ = 1:

- The participation factor is Γ = φᵀ M r.
- The effective mass is Γ², and the peak base shear of the mode is
  Γ² S_a.
- The peak displacement of the mode is Γ φ S_a / ω².

The peaks of the modes do not occur at one time, so a rule combines
them. `SRSS` is the square root of the sum of the squares. `CQC` adds the
cross terms of modes with close frequencies, with the correlation of Der
Kiureghian, "A response spectrum method for random vibration analysis of
MDF systems", 1981. See Chopra, "Dynamics of Structures", 4th edition,
sections 13.7 and 13.8.
"""

from std.math import isfinite, pi, sqrt
from core.ordinal import ordinal_valid, require_valid
from math.finite import require_finite, require_non_negative_finite
from extensions.structure.ids import NodeId
from extensions.structure.kinds import Dof
from extensions.structure.modal import assemble_mass, solve_modes
from extensions.structure.model import StructuralModel
from units.si import (
    Acceleration64,
    Duration64,
    Force64,
    Frequency64,
    Length64,
    METER_PER_SECOND_SQUARED,
    Mass64,
    PER_SECOND,
    SECOND,
)


@fieldwise_init
struct CombinationRule(Equatable, ImplicitlyCopyable, Writable):
    """How the peaks of the modes are combined."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two rules.

        Returns:
            Whether the value is 0 or 1.
        """
        return ordinal_valid(self.value, 2 - 1)


# The square root of the sum of the squares. For well separated modes.
comptime SRSS = CombinationRule(0)
# The complete quadratic combination. For modes with close frequencies.
comptime CQC = CombinationRule(1)


struct ResponseSpectrum(Copyable, Movable):
    """Pseudo-accelerations at periods, linear between them.

    Below the first period and above the last one, the spectrum keeps its
    end value.
    """

    # The periods, ascending, in seconds.
    var periods: List[Float64]
    # The pseudo-acceleration at each period, in meters per second
    # squared.
    var accelerations: List[Float64]

    def __init__(
        out self,
        var periods: List[Float64],
        values: List[Float64],
        scale: Acceleration64,
    ) raises:
        """Create a spectrum.

        Args:
            periods: The periods, in seconds. Zero or more, and each
                above the one before it. At least one.
            values: The value at each period. Zero or more.
            scale: The pseudo-acceleration of a value of one. For values
                in units of g it is 9.80665 meters per second squared.

        Raises:
            Error: If there is no period, the two lists differ in length,
                the periods are not ascending from zero or more, a value
                is negative or not finite, or the scale is not positive
                and finite.
        """
        if len(periods) == 0 or len(periods) != len(values):
            raise Error(
                "A spectrum needs one value for each of one period or more"
            )
        var g = scale.to(METER_PER_SECOND_SQUARED)
        if not (g > 0 and isfinite(g)):
            raise Error("A spectrum scale must be positive and finite")
        var accelerations = List[Float64](capacity=len(values))
        for i in range(len(periods)):  # pragma: no branch
            if not (periods[i] >= 0 and isfinite(periods[i])):
                raise Error(
                    "The periods of a spectrum must ascend from zero or more"
                )
            if i > 0 and periods[i] <= periods[i - 1]:
                raise Error(
                    "The periods of a spectrum must ascend from zero or more"
                )
            require_non_negative_finite(
                values[i], "A spectrum value must be zero or more and finite"
            )
            accelerations.append(values[i] * g)
        self.periods = periods^
        self.accelerations = accelerations^

    def at(self, period: Duration64) -> Acceleration64:
        """Return the pseudo-acceleration at a period.

        Args:
            period: The period.

        Returns:
            The value between the two periods beside it, or the end value
            outside the periods of the spectrum.
        """
        var t = period.to(SECOND)
        var last = len(self.periods) - 1
        if not (t > self.periods[0]):
            return Acceleration64(self.accelerations[0])
        if t >= self.periods[last]:
            return Acceleration64(self.accelerations[last])
        var i = 0
        while self.periods[i + 1] < t:
            i += 1
        var share = (t - self.periods[i]) / (
            self.periods[i + 1] - self.periods[i]
        )
        return Acceleration64(
            self.accelerations[i]
            + share * (self.accelerations[i + 1] - self.accelerations[i])
        )


def modal_correlation(
    first: Float64, second: Float64, damping: Float64
) -> Float64:
    """Return the CQC correlation of two modes with one damping ratio.

    With β the ratio of the two frequencies, the correlation is
    8 ζ² (1 + β) β^1.5 / ((1 - β²)² + 4 ζ² β (1 + β)²).

    Args:
        first: The frequency of the first mode. Positive.
        second: The frequency of the second mode, in the same unit.
            Positive.
        damping: The damping ratio ζ of both modes. Zero or more.

    Returns:
        The correlation, from zero to one. Two equal frequencies give
        one.
    """
    if first == second:
        return 1
    var beta = second / first
    var z2 = damping * damping
    var gap = 1 - beta * beta
    return (
        8
        * z2
        * (1 + beta)
        * beta**1.5
        / (gap * gap + 4 * z2 * beta * (1 + beta) * (1 + beta))
    )


def combine_modes(
    peaks: List[Float64],
    frequencies: List[Float64],
    rule: CombinationRule,
    damping: Float64,
) raises -> Float64:
    """Return the combined peak of the peaks of the modes.

    Args:
        peaks: The peak of one response in each mode, with its sign.
        frequencies: The frequency of each mode. Positive.
        rule: `SRSS` or `CQC`.
        damping: The damping ratio of every mode, for `CQC`. Zero or
            more.

    Returns:
        The combined peak. Zero or more.

    Raises:
        Error: If the rule is not valid, the lists differ in length, or
            the damping is negative or not finite.
    """
    require_valid(rule.is_valid(), "A combination rule must be SRSS or CQC")
    if len(peaks) != len(frequencies):
        raise Error("Each mode needs one peak and one frequency")
    require_non_negative_finite(
        damping, "A damping ratio must be zero or more and finite"
    )
    var total = Float64(0)
    for i in range(len(peaks)):
        total += peaks[i] * peaks[i]
        if rule == SRSS:
            continue
        for j in range(len(peaks)):  # pragma: no branch
            if j != i:
                total += (
                    modal_correlation(frequencies[i], frequencies[j], damping)
                    * peaks[i]
                    * peaks[j]
                )
    # Round-off can leave a sum of canceling cross terms just below zero.
    return sqrt(max(total, 0))


struct SpectrumResult(Movable):
    """The peak response of a model to a response spectrum."""

    # The frequency of each mode, in hertz, ascending.
    var frequencies: List[Frequency64]
    # The participation factor φᵀ M r of each mode, in root kilograms.
    var participation: List[Float64]
    # The effective mass of each mode, in kilograms.
    var effective_masses: List[Float64]
    # The peak base shear of each mode, in newtons.
    var modal_shears: List[Float64]
    # The combined peak of each degree of freedom, six per node, in
    # meters and radians, relative to the ground. Zero or more.
    var displacements: List[Float64]
    # The combined peak base shear, in newtons.
    var shear: Float64

    def __init__(
        out self,
        var frequencies: List[Frequency64],
        var participation: List[Float64],
        var effective_masses: List[Float64],
        var modal_shears: List[Float64],
        var displacements: List[Float64],
        shear: Float64,
    ):
        """Hold a result. `solve_response_spectrum` makes these.

        Args:
            frequencies: One per mode.
            participation: One per mode.
            effective_masses: One per mode.
            modal_shears: One per mode.
            displacements: Six per node.
            shear: The combined base shear.
        """
        self.frequencies = frequencies^
        self.participation = participation^
        self.effective_masses = effective_masses^
        self.modal_shears = modal_shears^
        self.displacements = displacements^
        self.shear = shear

    def translation(self, node: NodeId, dof: Dof) raises -> Length64:
        """Return the combined peak displacement along a global axis.

        Args:
            node: The node.
            dof: `UX`, `UY` or `UZ`.

        Returns:
            The peak size of the displacement. It has no sign.

        Raises:
            Error: If the node id is out of range or the degree of freedom
                is not a translation.
        """
        if not dof.is_translation():
            raise Error("A translation needs UX, UY or UZ")
        if not node.is_valid() or 6 * node.value >= len(self.displacements):
            raise Error("A node id is out of range")
        return Length64(self.displacements[6 * node.value + dof.value])

    def base_shear(self) -> Force64:
        """Return the combined peak base shear.

        Returns:
            The peak of the sum of the inertia forces along the ground
            motion.
        """
        return Force64(self.shear)

    def effective_mass(self, mode: Int) raises -> Mass64:
        """Return the effective mass of a mode.

        The effective masses of all the modes add to the mass that the
        ground motion moves.

        Args:
            mode: The mode, from zero.

        Returns:
            The mass.

        Raises:
            Error: If the mode is out of range.
        """
        if mode < 0 or mode >= len(self.effective_masses):
            raise Error("A mode is out of range")
        return Mass64(self.effective_masses[mode])


def solve_response_spectrum(
    model: StructuralModel,
    spectrum: ResponseSpectrum,
    direction: Dof,
    modes: Int,
    rule: CombinationRule,
    damping: Float64,
) raises -> SpectrumResult:
    """Return the peak response of a model to a response spectrum.

    Args:
        model: The model. Every free degree of freedom needs mass.
        spectrum: The spectrum, for the damping of the structure.
        direction: The axis of the ground motion: `UX`, `UY` or `UZ`.
        modes: How many of the lowest modes to combine. Use enough for
            the effective masses to add to most of the mass.
        rule: `SRSS` or `CQC`.
        damping: The damping ratio of every mode, for `CQC`. Zero or
            more.

    Returns:
        The frequencies, the participation factors, the effective masses
        and the combined peaks.

    Raises:
        Error: If the direction is not a translation, the rule is not
            valid, the damping is negative or not finite, the mode count
            is out of range, or the structure is a mechanism.
    """
    if not direction.is_translation():
        raise Error("A ground motion must act along a translation")
    require_valid(rule.is_valid(), "A combination rule must be SRSS or CQC")
    require_non_negative_finite(
        damping, "A damping ratio must be zero or more and finite"
    )
    var found = solve_modes(model, modes)
    var rigid = List[Float64](length=model.dof_count(), fill=0)
    for n in range(len(model.nodes)):  # pragma: no branch
        rigid[6 * n + direction.value] = 1
    var inertia = assemble_mass(model).multiply(rigid)
    var participation = List[Float64](capacity=modes)
    var masses = List[Float64](capacity=modes)
    var shears = List[Float64](capacity=modes)
    var omegas = List[Float64](capacity=modes)
    var scales = List[Float64](capacity=modes)
    for m in range(modes):  # pragma: no branch
        var gamma = Float64(0)
        for i in range(len(inertia)):  # pragma: no branch
            gamma += found.shapes[m][i] * inertia[i]
        var hertz = found.frequencies[m].to(PER_SECOND)
        var omega = 2 * pi * hertz
        var sa = spectrum.at(Duration64(1 / hertz)).to(METER_PER_SECOND_SQUARED)
        participation.append(gamma)
        masses.append(gamma * gamma)
        shears.append(gamma * gamma * sa)
        omegas.append(omega)
        # The peak displacement of the mode is this times its shape.
        scales.append(gamma * sa / (omega * omega))
    var displacements = List[Float64](length=model.dof_count(), fill=0)
    var peaks = List[Float64](length=modes, fill=0)
    for i in range(model.dof_count()):  # pragma: no branch
        for m in range(modes):  # pragma: no branch
            peaks[m] = scales[m] * found.shapes[m][i]
        displacements[i] = combine_modes(peaks, omegas, rule, damping)
    var shear = combine_modes(shears, omegas, rule, damping)
    return SpectrumResult(
        found.frequencies.copy(),
        participation^,
        masses^,
        shears^,
        displacements^,
        shear,
    )
