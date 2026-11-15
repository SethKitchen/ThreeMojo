# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Strain-adaptive bone remodeling: the density of bone follows its load.

Bone adds mass where it carries more strain energy than it is used to,
and loses mass where it carries less. Huiskes and others (1987) model the
stimulus as the strain energy density over the density, `S = U / rho`,
with a reference stimulus k. Bone does not change while S stays in the
lazy zone from `(1 - s) k` to `(1 + s) k`. A stiff implant carries much of
the load, so the bone around it loses mass: stress shielding.

`remodel(problem, bone, law, rule, steps, tolerance, max_iterations)`
gives each element of the bone material its own density and modulus
`E = C (rho / rho0)^gamma`, with rho0 = 1 g/cm^3. At each step it solves
the problem and moves each density by the multiplicative update

    rho <- rho (S / k')^(w / (gamma + 1))

where k' is the nearer end of the lazy zone and w is the relaxation. The
densities stay between a least and a most. Under a fixed stress, S falls
as `rho^-(gamma + 1)`, so a relaxation of 1 reaches the end of the lazy
zone in one step, and a smaller one approaches it. The equilibria are
those of the rule of Huiskes and others, where S is in the lazy zone.

The strain energy density of an element is half its stress times its
strain. The elements are four-node tetrahedra, whose strain is the same
in all of each element.
"""

from extensions.fem.elasticity import IsotropicMaterial
from extensions.fem.ids import LINEAR, MaterialId, require_id
from extensions.fem.static import StaticProblem, solve_static
from extensions.numerics.iterative import CONVERGED
from extensions.clinical.distributions import precise_exp
from std.math import isfinite, log
from units.quantity import Quantity, Unit
from units.si import (
    Density64,
    GRAM_PER_CUBIC_CENTIMETER,
    KILOGRAM_PER_CUBIC_METER,
    PASCAL,
    Pressure64,
)

comptime SpecificEnergy64 = Quantity[2, 0, -2, 0, 0, DType.float64]
"""An energy for each mass, such as a remodeling stimulus."""
comptime JOULE_PER_KILOGRAM = Unit[2, 0, -2, 0, 0, DType.float64](1.0, "J/kg")
"""The joule for each kilogram."""
comptime MAX_REMODELING_STEPS = 1000
"""The most steps of one remodeling run."""
comptime _SOLVE_TOLERANCE = 1e-13


struct BoneLaw(Copyable, Movable):
    """The modulus of bone from its density: `E = C (rho / rho0)^gamma`,
    with rho0 = 1 g/cm^3."""

    var coefficient: Pressure64
    """The coefficient C: the modulus at a density of 1 g/cm^3."""
    var exponent: Float64
    """The exponent gamma, often 2 to 3."""
    var poisson: Float64
    """Poisson's ratio of the bone."""

    def __init__(
        out self, coefficient: Pressure64, exponent: Float64, poisson: Float64
    ) raises:
        """Create a law.

        Args:
            coefficient: The coefficient C, positive and finite.
            exponent: The exponent gamma, from 1 to 4.
            poisson: Poisson's ratio, above -1 and below 0.5.

        Raises:
            Error: If a value is out of range.
        """
        var c = coefficient.to(PASCAL)
        if not (c > 0) or not isfinite(c):
            raise Error("A bone law needs a positive, finite coefficient")
        if not (exponent >= 1 and exponent <= 4):
            raise Error("A bone law needs an exponent from 1 to 4")
        if not (poisson > -1.0) or not (poisson < 0.5):
            raise Error("Poisson's ratio must be above -1 and below 0.5")
        self.coefficient = coefficient
        self.exponent = exponent
        self.poisson = poisson

    def modulus(self, density: Density64) -> Pressure64:
        """Return the modulus of bone of a density.

        Args:
            density: The density, positive.

        Returns:
            `C (rho / rho0)^gamma`.
        """
        var ratio = density.to(GRAM_PER_CUBIC_CENTIMETER)
        return Pressure64(
            self.coefficient.to(PASCAL)
            * precise_exp(self.exponent * log(ratio)),
            PASCAL,
        )

    def material(self, density: Density64) raises -> IsotropicMaterial:
        """Return the material of bone of a density.

        Args:
            density: The density, positive and finite.

        Returns:
            The material with `modulus(density)` and the law's ratio.

        Raises:
            Error: If the modulus is not positive and finite.
        """
        return IsotropicMaterial(self.modulus(density), self.poisson)


struct RemodelingRule(Copyable, Movable):
    """How bone answers its stimulus."""

    var reference: SpecificEnergy64
    """The stimulus k at which bone does not change."""
    var lazy: Float64
    """The half width s of the lazy zone, as a share of k."""
    var least: Density64
    """The least density."""
    var most: Density64
    """The most density, such as that of cortical bone."""
    var relaxation: Float64
    """The relaxation w: the share of each step toward the lazy zone, in
    log density."""

    def __init__(
        out self,
        reference: SpecificEnergy64,
        lazy: Float64,
        least: Density64,
        most: Density64,
        relaxation: Float64,
    ) raises:
        """Create a rule.

        Args:
            reference: The stimulus k, positive and finite.
            lazy: The half width s, from 0 to below 1.
            least: The least density, positive.
            most: The most density, above the least and finite.
            relaxation: The relaxation w, above 0 and at most 1.

        Raises:
            Error: If a value is out of range.
        """
        var k = reference.to(JOULE_PER_KILOGRAM)
        if not (k > 0) or not isfinite(k):
            raise Error("A remodeling stimulus must be positive and finite")
        if not (lazy >= 0 and lazy < 1):
            raise Error("A lazy zone is from 0 to below 1 of the stimulus")
        var low = least.to(KILOGRAM_PER_CUBIC_METER)
        var high = most.to(KILOGRAM_PER_CUBIC_METER)
        if not (low > 0) or not (high > low) or not isfinite(high):
            raise Error("A remodeling rule needs 0 < least < most densities")
        if not (relaxation > 0 and relaxation <= 1):
            raise Error("A relaxation is above 0 and at most 1")
        self.reference = reference
        self.lazy = lazy
        self.least = least
        self.most = most
        self.relaxation = relaxation


struct RemodelingResult(Movable):
    """The densities that a remodeling run reached."""

    var densities: List[Density64]
    """The density of each element. Elements of other materials hold 0."""
    var stimuli: List[SpecificEnergy64]
    """The stimulus of each bone element at the last solve."""
    var steps: Int
    """The steps taken."""
    var change: Float64
    """The largest change of a log density at the last step."""
    var converged: Bool
    """Whether the last change was below the tolerance."""

    def __init__(out self, elements: Int):
        """Create a result of zeros.

        Args:
            elements: The element count.
        """
        self.densities = List[Density64](
            length=elements, fill=Density64(0, KILOGRAM_PER_CUBIC_METER)
        )
        self.stimuli = List[SpecificEnergy64](
            length=elements, fill=SpecificEnergy64(0, JOULE_PER_KILOGRAM)
        )
        self.steps = 0
        self.change = 0.0
        self.converged = False


def remodel(
    var problem: StaticProblem,
    bone: MaterialId,
    law: BoneLaw,
    rule: RemodelingRule,
    start: Density64,
    steps: Int,
    tolerance: Float64,
    max_iterations: Int,
) raises -> RemodelingResult:
    """Remodel the bone of a problem until its densities stop changing.

    Args:
        problem: The problem, with its supports and loads, on a mesh of
            four-node tetrahedra.
        bone: The material of the elements that remodel. Its own modulus
            is not used.
        law: The modulus of bone from its density.
        rule: The stimulus, the lazy zone, the bounds and the relaxation.
        start: The density of each bone element at the first step, from
            the least to the most of the rule.
        steps: The most steps, from 1 to 1000.
        tolerance: The largest change of a log density at which the run
            stops, above 0 and below 1. Each solve stops at a relative
            residual of 1e-13.
        max_iterations: The iteration budget of each solve.

    Returns:
        The densities and the stimuli of the last solve.

    Raises:
        Error: If the mesh is not of four-node tetrahedra, the material id
            names no material, the start, the steps or the tolerance is out
            of range, or a solve refuses the problem or runs out of its
            budget.
    """
    if problem.mesh.order != LINEAR:
        raise Error("Remodeling takes four-node tetrahedra")
    require_id(bone.is_valid(), bone.value, len(problem.materials), "material")
    var rho = start.to(KILOGRAM_PER_CUBIC_METER)
    var least = rule.least.to(KILOGRAM_PER_CUBIC_METER)
    var most = rule.most.to(KILOGRAM_PER_CUBIC_METER)
    if not (rho >= least and rho <= most):
        raise Error("A start density is from the least to the most")
    if steps < 1 or steps > MAX_REMODELING_STEPS:
        raise Error("A remodeling run takes from 1 to 1000 steps")
    if not (tolerance > 0 and tolerance < 1):
        raise Error("A remodeling tolerance is above 0 and below 1")
    var n = problem.mesh.element_count()
    var out = RemodelingResult(n)
    # Give each bone element a material of its own.
    var mine = List[Int](length=n, fill=-1)
    for e in range(n):  # pragma: no branch
        if problem.mesh.materials[e] != bone.value:
            continue
        mine[e] = len(problem.materials)
        problem.mesh.materials[e] = mine[e]
        problem.materials.append(law.material(start))
        out.densities[e] = start
    var k = rule.reference.to(JOULE_PER_KILOGRAM)
    var power = rule.relaxation / (law.exponent + 1.0)
    while out.steps < steps:
        var result = solve_static(problem, _SOLVE_TOLERANCE, max_iterations)
        if result.status != CONVERGED:
            raise Error("A remodeling solve ran out of its iteration budget")
        out.steps += 1
        out.change = 0.0
        for e in range(n):  # pragma: no branch
            if mine[e] < 0:
                continue
            var energy = 0.0
            for i in range(6):  # pragma: no branch
                energy += (
                    0.5 * result.stresses[6 * e + i] * result.strains[6 * e + i]
                )
            var density = out.densities[e].to(KILOGRAM_PER_CUBIC_METER)
            var stimulus = energy / density
            out.stimuli[e] = SpecificEnergy64(stimulus, JOULE_PER_KILOGRAM)
            var target: Float64
            if stimulus > (1.0 + rule.lazy) * k:
                target = (1.0 + rule.lazy) * k
            elif stimulus < (1.0 - rule.lazy) * k:
                target = (1.0 - rule.lazy) * k
            else:
                continue
            var next = density * precise_exp(power * log(stimulus / target))
            next = min(max(next, least), most)
            out.change = max(out.change, abs(log(next / density)))
            out.densities[e] = Density64(next, KILOGRAM_PER_CUBIC_METER)
            problem.materials[mine[e]] = law.material(out.densities[e])
        if out.change < tolerance:
            out.converged = True
            break
    return out^
