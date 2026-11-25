# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Fiber sections and their moment-curvature response.

A `FiberSection` is a stack of fibers. Each fiber has an area, a height y
above a reference axis and a law of steel or of concrete. Plane sections
stay plane: at an axial strain ε₀ and a curvature κ the strain of a fiber
is ε₀ - κ y. So a positive curvature shortens the top. The axial force is
N = Σ σ A, with tension positive, and the moment is M = -Σ σ A y.

`ConcreteLaw` is the envelope of Kent and Park, "Flexural members with
confined concrete", 1971: a parabola up to the peak stress, a line down
to the crushing strength, and no tension. It is the monotonic envelope of
the OpenSees material Concrete01. It has no memory, so it is for loading
in one direction. The steel is the `SteelLaw` of
`extensions.structure.nonlinear`, with its plastic state.

`moment_curvature` raises the curvature in equal steps under a constant
axial force. At each step it finds the axial strain that gives the force,
by Newton iteration. OpenSees does this analysis with a fiber section in
a zero-length element under displacement control. The code is original
and shares no source with OpenSees.
"""

from std.math import isfinite
from core.ordinal import require_positive
from math.finite import (
    require_finite,
    require_positive_finite,
    require_positive_tolerance,
)
from extensions.structure.nonlinear import (
    BarState,
    SteelLaw,
    bar_response,
)
from units.si import (
    Area64,
    Force64,
    InverseLength64,
    Length64,
    METER,
    Moment64,
    NEWTON,
    PASCAL,
    PER_METER,
    Pressure64,
    SQUARE_METER,
)

# The largest number of fibers of one patch and of steps of one analysis.
comptime MAX_SECTION_STEPS = 1048576


struct ConcreteLaw(ImplicitlyCopyable):
    """The compressive envelope of Kent and Park, with no tension.

    The four values are sizes. They are positive for compression.
    """

    # The peak stress, in pascals.
    var strength: Float64
    # The strain at the peak stress.
    var peak_strain: Float64
    # The stress that stays after crushing, in pascals.
    var crushing_strength: Float64
    # The strain at which the stress reaches the crushing strength.
    var crushing_strain: Float64

    def __init__(
        out self,
        strength: Pressure64,
        peak_strain: Float64,
        crushing_strength: Pressure64,
        crushing_strain: Float64,
    ) raises:
        """Create a law.

        Args:
            strength: The size of the peak compressive stress. Positive.
            peak_strain: The size of the strain at the peak. Positive.
                About 0.002 for normal concrete.
            crushing_strength: The size of the stress after crushing.
                From zero to the strength.
            crushing_strain: The size of the strain at which the stress
                reaches the crushing strength. Above the peak strain.

        Raises:
            Error: If the strength or the peak strain is not positive and
                finite, the crushing strength is not from zero to the
                strength, or the crushing strain is not above the peak
                strain and finite.
        """
        var fc = strength.to(PASCAL)
        var fu = crushing_strength.to(PASCAL)
        require_positive_finite(
            fc, "A concrete strength must be positive and finite"
        )
        require_positive_finite(
            peak_strain, "A peak strain must be positive and finite"
        )
        if not (fu >= 0 and fu <= fc):
            raise Error("A crushing strength must be from zero to the strength")
        if not (crushing_strain > peak_strain and isfinite(crushing_strain)):
            raise Error(
                "A crushing strain must be above the peak strain and finite"
            )
        self.strength = fc
        self.peak_strain = peak_strain
        self.crushing_strength = fu
        self.crushing_strain = crushing_strain


@fieldwise_init
struct FiberStress(ImplicitlyCopyable):
    """The stress of a fiber at a strain, and its tangent."""

    # The stress, in pascals. Tension is positive.
    var stress: Float64
    # The derivative of the stress by the strain, in pascals.
    var tangent: Float64


def concrete_response(law: ConcreteLaw, strain: Float64) -> FiberStress:
    """Return the stress of concrete at a strain.

    Args:
        law: The law.
        strain: The strain. Tension is positive.

    Returns:
        The stress, which is zero or compressive, and its tangent. With
        x the compressive strain over the peak strain, the stress is the
        strength times 2 x - x² up to the peak. Then it falls on a line
        to the crushing strength and stays there.
    """
    if strain >= 0:
        return FiberStress(0, 0)
    var size = -strain
    if size <= law.peak_strain:
        var x = size / law.peak_strain
        return FiberStress(
            -law.strength * (2 * x - x * x),
            2 * law.strength * (1 - x) / law.peak_strain,
        )
    if size <= law.crushing_strain:
        var slope = (law.crushing_strength - law.strength) / (
            law.crushing_strain - law.peak_strain
        )
        return FiberStress(
            -(law.strength + slope * (size - law.peak_strain)), slope
        )
    return FiberStress(-law.crushing_strength, 0)


@fieldwise_init
struct ConcreteFiber(ImplicitlyCopyable):
    """A fiber of concrete."""

    # The height above the reference axis, in meters.
    var y: Float64
    # The area, in square meters.
    var area: Float64
    var law: ConcreteLaw


@fieldwise_init
struct SteelFiber(ImplicitlyCopyable):
    """A fiber of steel."""

    # The height above the reference axis, in meters.
    var y: Float64
    # The area, in square meters.
    var area: Float64
    var law: SteelLaw


struct FiberSection(Copyable, Movable):
    """Fibers of concrete and of steel about one reference axis."""

    var concrete: List[ConcreteFiber]
    var steel: List[SteelFiber]

    def __init__(out self):
        """Create a section with no fiber."""
        self.concrete = List[ConcreteFiber]()
        self.steel = List[SteelFiber]()

    def add_steel(mut self, y: Length64, area: Area64, law: SteelLaw) raises:
        """Add one fiber of steel, such as a layer of bars.

        The steel does not take concrete away. For a bar in concrete this
        counts the area of the bar twice, which is the usual small error.

        Args:
            y: The height of the fiber above the reference axis.
            area: The area. Positive.
            law: The law of the steel.

        Raises:
            Error: If the height is not finite or the area is not
                positive and finite.
        """
        var at = y.to(METER)
        var a = area.to(SQUARE_METER)
        require_finite(at, "A fiber height must be finite")
        require_positive_finite(a, "A fiber area must be positive and finite")
        self.steel.append(SteelFiber(at, a, law))

    def add_steel_patch(
        mut self,
        bottom: Length64,
        top: Length64,
        width: Length64,
        layers: Int,
        law: SteelLaw,
    ) raises:
        """Add a rectangle of steel, cut into equal layers.

        Args:
            bottom: The height of the lower edge above the reference axis.
            top: The height of the upper edge. Above the lower edge.
            width: The width of the rectangle. Positive.
            layers: How many fibers. From 1 to 1048576.
            law: The law of the steel.

        Raises:
            Error: If an edge is not finite, the top is not above the
                bottom, the width is not positive and finite, or the
                layer count is out of range.
        """
        var heights = _layers(bottom, top, width, layers)
        var area = heights[layers]
        for i in range(layers):  # pragma: no branch
            self.steel.append(SteelFiber(heights[i], area, law))

    def add_concrete_patch(
        mut self,
        bottom: Length64,
        top: Length64,
        width: Length64,
        layers: Int,
        law: ConcreteLaw,
    ) raises:
        """Add a rectangle of concrete, cut into equal layers.

        Args:
            bottom: The height of the lower edge above the reference axis.
            top: The height of the upper edge. Above the lower edge.
            width: The width of the rectangle. Positive.
            layers: How many fibers. From 1 to 1048576.
            law: The law of the concrete.

        Raises:
            Error: If an edge is not finite, the top is not above the
                bottom, the width is not positive and finite, or the
                layer count is out of range.
        """
        var heights = _layers(bottom, top, width, layers)
        var area = heights[layers]
        for i in range(layers):  # pragma: no branch
            self.concrete.append(ConcreteFiber(heights[i], area, law))


def _layers(
    bottom: Length64, top: Length64, width: Length64, layers: Int
) raises -> List[Float64]:
    """Return the mid height of each layer of a rectangle, then its area."""
    var low = bottom.to(METER)
    var high = top.to(METER)
    var b = width.to(METER)
    require_finite(low, "A patch edge must be finite")
    require_finite(high, "A patch edge must be finite")
    if not (high > low):
        raise Error("The top of a patch must be above its bottom")
    require_positive_finite(b, "A patch width must be positive and finite")
    require_positive(layers, "A patch needs one layer or more")
    if layers > MAX_SECTION_STEPS:
        raise Error("A patch has more layers than this port stores")
    var thickness = (high - low) / Float64(layers)
    var out = List[Float64](capacity=layers + 1)
    for i in range(layers):  # pragma: no branch
        out.append(low + (Float64(i) + 0.5) * thickness)
    out.append(b * thickness)
    return out^


struct SectionResponse(Movable):
    """The forces of a section at a strain and a curvature."""

    # The axial force, in newtons. Tension is positive.
    var axial: Float64
    # The moment, in newton meters. A positive moment shortens the top.
    var moment: Float64
    # The derivative of the axial force by the axial strain, in newtons.
    var axial_stiffness: Float64
    # The sum of the fiber forces in size, in newtons. A scale for a
    # tolerance.
    var size: Float64
    # The state of each steel fiber at the end.
    var steel: List[BarState]

    def __init__(
        out self,
        axial: Float64,
        moment: Float64,
        axial_stiffness: Float64,
        size: Float64,
        var steel: List[BarState],
    ):
        """Hold a response. `section_response` makes these.

        Args:
            axial: The axial force.
            moment: The moment.
            axial_stiffness: The axial tangent.
            size: The sum of the sizes of the fiber forces.
            steel: The new steel states.
        """
        self.axial = axial
        self.moment = moment
        self.axial_stiffness = axial_stiffness
        self.size = size
        self.steel = steel^


def section_response(
    section: FiberSection,
    steel: List[BarState],
    strain: Float64,
    curvature: Float64,
) raises -> SectionResponse:
    """Return the forces of a section at an axial strain and a curvature.

    Args:
        section: The section.
        steel: The state of each steel fiber at the start of the step.
        strain: The strain at the reference axis. Tension is positive.
        curvature: The curvature, per meter. A positive curvature
            shortens the top.

    Returns:
        The axial force, the moment, the axial tangent and the new steel
        states.

    Raises:
        Error: If the list does not have one state per steel fiber.
    """
    if len(steel) != len(section.steel):
        raise Error("Each steel fiber needs one state")
    var axial = Float64(0)
    var moment = Float64(0)
    var stiffness = Float64(0)
    var size = Float64(0)
    for i in range(len(section.concrete)):
        var fiber = section.concrete[i]
        var value = concrete_response(fiber.law, strain - curvature * fiber.y)
        var force = value.stress * fiber.area
        axial += force
        moment -= force * fiber.y
        stiffness += value.tangent * fiber.area
        size += abs(force)
    var states = List[BarState](capacity=len(steel))
    for i in range(len(section.steel)):
        var fiber = section.steel[i]
        var value = bar_response(
            fiber.law, steel[i], strain - curvature * fiber.y
        )
        var force = value.stress * fiber.area
        axial += force
        moment -= force * fiber.y
        stiffness += value.tangent * fiber.area
        size += abs(force)
        states.append(value.state)
    return SectionResponse(axial, moment, stiffness, size, states^)


@fieldwise_init
struct CurvaturePoint(ImplicitlyCopyable):
    """One point of a moment-curvature curve."""

    var curvature: InverseLength64
    var moment: Moment64
    # The strain at the reference axis. Tension is positive.
    var strain: Float64


def moment_curvature(
    section: FiberSection,
    axial: Force64,
    last_curvature: InverseLength64,
    steps: Int,
    tolerance: Float64,
) raises -> List[CurvaturePoint]:
    """Return the moment of a section at each of a row of curvatures.

    The axial force stays constant. The curvature rises from zero to the
    last curvature in equal steps, and the steel keeps its plastic state
    from each step to the next.

    Args:
        section: The section. It needs one fiber or more.
        axial: The axial force. Tension is positive, so the load of a
            column is negative.
        last_curvature: The curvature of the last point. Positive.
        steps: How many steps. From 1 to 1048576.
        tolerance: The unbalanced axial force, over the sum of the sizes
            of the fiber forces and the axial force, at which a step has
            converged. Positive.

    Returns:
        The point at zero curvature and one point per step.

    Raises:
        Error: If the section has no fiber, the axial force is not
            finite, the curvature is not positive and finite, the step
            count is out of range, the tolerance is not positive, or a
            step finds no axial strain that carries the axial force. The
            section then has no axial stiffness left, or the force is
            above its capacity.
    """
    if len(section.concrete) + len(section.steel) == 0:
        raise Error("A section needs one fiber or more")
    var force = axial.to(NEWTON)
    require_finite(force, "An axial force must be finite")
    var last = last_curvature.to(PER_METER)
    require_positive_finite(
        last, "A last curvature must be positive and finite"
    )
    require_positive(steps, "A step count must be positive")
    if steps > MAX_SECTION_STEPS:
        raise Error("A step count is larger than this port stores")
    require_positive_tolerance(tolerance)
    var states = List[BarState](length=len(section.steel), fill=BarState(0, 0))
    var strain = Float64(0)
    var out = List[CurvaturePoint](capacity=steps + 1)
    for step in range(steps + 1):  # pragma: no branch
        var curvature = last * Float64(step) / Float64(steps)
        var done = False
        for _ in range(_NEWTON_STEPS):  # pragma: no branch
            var response = section_response(section, states, strain, curvature)
            var unbalanced = force - response.axial
            if abs(unbalanced) <= tolerance * (response.size + abs(force)):
                states = response.steel.copy()
                out.append(
                    CurvaturePoint(
                        InverseLength64(curvature),
                        Moment64(response.moment),
                        strain,
                    )
                )
                done = True
                break
            if not (response.axial_stiffness > 0):
                break
            strain += unbalanced / response.axial_stiffness
        if not done:
            raise Error(
                (
                    "The section finds no axial strain that carries the axial"
                    " force at a curvature of "
                ),
                curvature,
                " per meter",
            )
    return out^


# The Newton iterations of one curvature step.
comptime _NEWTON_STEPS = 60
