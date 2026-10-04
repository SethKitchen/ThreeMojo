# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Calibrate a species to its published size, for engineering mode.

A sculpt is drawn to look right. Engineering mode needs it to measure
right, so `calibrate` measures a canonical individual: an adult male of
the published morph. It finds the length factor that gives the sculpt
its published reference length, and the mass that the scaled sculpt
then has at the published densities. That mass is a prediction. The
published mass checks it.

`calibrated_mass` then scales the densities by `published / predicted`,
so every segment keeps the share of mass the geometry gives it and the
whole animal weighs what the published animal weighs. This prescribes the canonical mass; it does not independently validate
the sculpt or segment parameters. An individual keeps its own proportions and size relative to the
canonical one: a juvenile stays small and light.

A selected DESIGN template, unmatched morph or unverified reference
requires explicit `allow_estimates=True`, even if an excerpt is sourced. It gets its own length factor but no unrelated
mass correction. `matched` describes reference identity, not validated
anatomy. Source excerpts and derived DESIGN templates are distinct.
"""

from extensions.anatomy.evidence import DESIGN, Evidence
from extensions.anatomy.inertia import InertiaTally
from extensions.animals.anatomy.body import species_body
from extensions.animals.anatomy.mass import BodyMass, sample_mass
from extensions.animals.anatomy.reference import reference_length
from extensions.animals.build import Animal, create_animal
from extensions.animals.options import (
    ADULT,
    CROWD,
    MALE,
    Variant,
    animal_options,
)
from extensions.animals.registry import SpeciesId, species_variants
from std.math import isfinite
from extensions.animals.warp import Warps, scale_warp
from units.si import KILOGRAM, METER, Length, Mass

# Canonical samples per reference length.
comptime CANON_CELLS = 40.0


def _check_reference_support(
    matched: Bool,
    mass_excerpt: Evidence,
    length_excerpt: Evidence,
    parameters: Evidence,
    allow_estimates: Bool,
) raises:
    # Reading a source does not upgrade a selected or derived parameter.
    var supported = (
        matched
        and mass_excerpt.is_measured()
        and length_excerpt.is_measured()
        and parameters.is_measured()
    )
    if not supported and not allow_estimates:
        raise Error(
            "Unsupported reference: pass allow_estimates=True for a template"
            " estimate"
        )


@fieldwise_init
struct Calibration(ImplicitlyCopyable, Writable):
    """How a species' sculpt maps onto its published size."""

    # The length factor from sculpt meters to real meters.
    var scale: Float64
    # Published mass over predicted mass. One when not `matched`.
    var density_factor: Float64
    # The canonical sculpt's analytic envelope landmark, before scaling.
    var measured: Length
    # The published reference length.
    var published: Length
    # The scaled canonical sculpt's mass at the selected density templates.
    var predicted_mass: Mass
    # The published adult male mass.
    var published_mass: Mass
    # Whether the morph is the one the numbers describe.
    var matched: Bool
    # Identity of the reference. A morph of -1 permits coat-only variants.
    var species: SpeciesId
    var variant: Variant
    # Explicit permission to inspect unsupported reference estimates.
    var allow_estimates: Bool

    def model_evidence(self) -> Evidence:
        """Return DESIGN: calibration does not validate an animal model.

        Returns:
            The grade of the derived template, apart from source excerpts.
        """
        return DESIGN

    def check(self) raises:
        """Refuse invalid data and unsupported reference use.

        Raises:
            Error: If identity or numbers are invalid, or unsupported
                reference estimates were not explicitly requested.
        """
        var body = species_body(self.species)
        if not self.variant.is_valid():
            raise Error("A calibration variant must be named")
        if self.variant.value >= len(species_variants(self.species)):
            raise Error("A calibration variant must belong to its species")
        if self.variant.value < 0 and body.variant >= 0:
            raise Error("A calibration must bind a resolved reference morph")
        var matches = body.variant < 0 or self.variant.value == body.variant
        if self.matched != matches:
            raise Error(
                "A calibration match must agree with its reference morph"
            )
        _check_reference_support(
            matches,
            body.mass_source.evidence,
            body.length_source.evidence,
            body.model_evidence(),
            self.allow_estimates,
        )
        if not (isfinite(self.scale) and self.scale > 0.0 and self.scale < 1e3):
            raise Error("A calibration scale must be positive and finite")
        if not (isfinite(self.density_factor) and self.density_factor > 0.0):
            raise Error(
                "A calibration density factor must be positive and finite"
            )
        var values = [
            self.measured.value,
            self.published.value,
            self.predicted_mass.value,
            self.published_mass.value,
        ]
        for value in values:  # pragma: no branch
            if not (isfinite(value) and value > 0.0):
                raise Error(
                    "Calibration reference quantities must be positive and"
                    " finite"
                )
        if (
            self.published != body.reference_length
            or self.published_mass != body.male_mass
        ):
            raise Error("A calibration reference must match its species")
        var expected = (
            Float64(self.published_mass.value)
            / Float64(self.predicted_mass.value) if matches else 1.0
        )
        if abs(self.density_factor - expected) > 1e-5 * expected:
            raise Error(
                "A calibration density factor must match its reference masses"
            )
        if abs(
            self.scale * Float64(self.measured.value)
            - Float64(self.published.value)
        ) > 1e-5 * Float64(self.published.value):
            raise Error("A calibration scale must match its reference lengths")
        if not matches and self.density_factor != 1.0:
            raise Error(
                "An unmatched morph cannot use reference mass normalization"
            )

    def check_animal(self, animal: Animal) raises:
        """Refuse a calibration for another species or reference morph.

        Args:
            animal: The unscaled individual.

        Raises:
            Error: If the calibration is invalid or its identity differs.
        """
        self.check()
        if animal.species != self.species:
            raise Error("The calibration is for another species")
        var variant = animal.traits.variant
        if variant < 0 or variant >= len(species_variants(animal.species)):
            raise Error("The animal's resolved variant must be named")
        if self.variant.value >= 0 and variant != self.variant.value:
            raise Error("The calibration is for another morph")
        if animal.traits.get("anatomy_calibration_scale", 0.0) != 0.0:
            raise Error("An animal must not be calibrated twice")


def calibrate(
    species: SpeciesId, variant: Variant, allow_estimates: Bool = False
) raises -> Calibration:
    """Measure a species' canonical individual against its published size.

    Args:
        species: The species.
        variant: The morph. A morph that is not the published one gets
            no mass correction.
        allow_estimates: Explicitly permit a template when reference inputs
            are selected DESIGN values, unverified or unmatched. A sourced
            excerpt does not upgrade the selected template. This is not validation.

    Returns:
        The length factor, the density factor and what they came from.

    Raises:
        Error: If the species is not named, the morph does not exist,
            unsupported estimates lack opt-in, or the sculpt cannot be measured.
    """
    var body = species_body(species)
    if not variant.is_valid():
        raise Error("A calibration variant must be named")
    var morph = variant.value
    var matched = body.variant < 0 or morph == body.variant
    if morph < 0:
        morph = max(body.variant, 0)
        matched = True
    _check_reference_support(
        matched,
        body.mass_source.evidence,
        body.length_source.evidence,
        body.model_evidence(),
        allow_estimates,
    )
    var canon = create_animal(
        species,
        animal_options(
            1, quality=CROWD, sex=MALE, age=ADULT, variant=Variant(morph)
        ),
    )
    var published = Float64(body.reference_length.to(METER))
    # The reference landmark is analytic and independent of occupancy.
    # The fixed canonical grid only estimates mass.
    var step = Length(Float32(published / CANON_CELLS), METER)
    var measured = Float64(reference_length(canon).to(METER))
    var scale = published / measured
    var target = Float64(body.male_mass.to(KILOGRAM))
    var cal = Calibration(
        scale,
        1.0,
        Length(Float32(measured), METER),
        body.reference_length,
        body.male_mass,
        body.male_mass,
        matched,
        species,
        Variant(-1 if body.variant < 0 else morph),
        allow_estimates,
    )
    # Coat depth is a physical length, not a scaled sculpt proportion.
    # Re-sample the scaled canonical geometry before normalizing mass.
    # Multiplying the original mass by scale^3 changes the relative coat
    # thickness and does not predict the sampled scaled anatomy.
    var scaled = calibrated_animal(canon, cal)
    var actual = sample_mass(scaled, scaled.bind_pose(), step).total().mass
    cal.predicted_mass = actual
    cal.density_factor = target / Float64(actual.value) if matched else 1.0
    cal.check()
    return cal


def calibrated_animal(animal: Animal, cal: Calibration) raises -> Animal:
    """Return an individual scaled to its species' published size.

    The sculpt, the rig and the cells scale together. The scale joins
    the individual's warps, so the coat still paints.

    Args:
        animal: The individual.
        cal: Its species' calibration.

    Returns:
        The same individual, `cal.scale` times larger.

    Raises:
        Error: If the calibration is invalid or belongs to another species
            or morph.
    """
    cal.check_animal(animal)
    var grow = Warps()
    grow.add(scale_warp(cal.scale))
    var traits = animal.traits.copy()
    traits.warps.add(scale_warp(cal.scale))
    traits.set("size", traits.get("size") * cal.scale)
    traits.set("anatomy_calibration_scale", cal.scale)
    return Animal(
        animal.species,
        animal.options,
        traits^,
        grow.warp_rig(animal.rig),
        grow.warp_model(animal.model),
        animal.palette.copy(),
        animal.eye,
        animal.look,
        animal.cell * cal.scale,
        animal.eye_cell * cal.scale,
    )


def calibrated_mass(
    animal: Animal, cal: Calibration, cells: Float64 = 60.0
) raises -> BodyMass:
    """Return an individual's mass properties at its published size.

    Args:
        animal: The individual, as `create_animal` made it.
        cal: Its species' calibration.
        cells: Samples per published reference length.

    Returns:
        Per-bone mass, center and inertia, in SI units, with the
        densities scaled so the canonical adult male weighs the
        published mass.

    Raises:
        Error: If the scale or the sample count is not positive, or the
            sculpt has no flesh, or the calibration identity differs.
    """
    if not (cells >= 4.0 and cells <= 400.0):
        raise Error("A mass sample needs 4 to 400 cells a length")
    var scaled = calibrated_animal(animal, cal)
    var step = Length(cal.published.value / Float32(cells), METER)
    var mass = sample_mass(scaled, scaled.bind_pose(), step)
    var k = cal.density_factor
    var bones = List[InertiaTally](capacity=len(mass.bones))
    for b in mass.bones:  # pragma: no branch
        var t = b.copy()
        t.mass *= k
        t.first *= k
        t.second *= k
        bones.append(t^)
    mass.bones = bones^
    return mass^
