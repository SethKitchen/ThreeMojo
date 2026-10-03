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
whole animal weighs what the published animal weighs. This is how a
biomechanist scales segment parameters to a weighed subject. An
individual keeps its own proportions and size relative to the
canonical one: a juvenile stays small and light.

A morph that is not the published kind, such as a grizzly when the
numbers are for a black bear, gets the length factor but no mass
correction, and `Calibration.matched` is False.
"""

from extensions.anatomy.inertia import InertiaTally
from extensions.animals.anatomy.body import species_body
from extensions.animals.anatomy.mass import BodyMass, sample_mass
from extensions.animals.build import Animal, create_animal
from extensions.animals.options import (
    ADULT,
    CROWD,
    MALE,
    Variant,
    animal_options,
)
from extensions.animals.registry import SpeciesId
from extensions.animals.warp import Warps, scale_warp
from units.si import KILOGRAM, METER, Length, Mass

# Canonical samples per reference length.
comptime CANON_CELLS = 40.0


@fieldwise_init
struct Calibration(ImplicitlyCopyable, Writable):
    """How a species' sculpt maps onto its published size."""

    # The length factor from sculpt meters to real meters.
    var scale: Float64
    # Published mass over predicted mass. One when not `matched`.
    var density_factor: Float64
    # The canonical sculpt's reference length, before scaling.
    var measured: Length
    # The published reference length.
    var published: Length
    # The scaled canonical sculpt's mass at the published densities.
    var predicted_mass: Mass
    # The published adult male mass.
    var published_mass: Mass
    # Whether the morph is the one the numbers describe.
    var matched: Bool


def calibrate(species: SpeciesId, variant: Variant) raises -> Calibration:
    """Measure a species' canonical individual against its published size.

    Args:
        species: The species.
        variant: The morph. A morph that is not the published one gets
            no mass correction.

    Returns:
        The length factor, the density factor and what they came from.

    Raises:
        Error: If the species is not named, the morph does not exist,
            or the canonical sculpt cannot be measured.
    """
    var body = species_body(species)
    var morph = variant.value
    var matched = body.variant < 0 or morph == body.variant
    if morph < 0:
        morph = max(body.variant, 0)
        matched = True
    var canon = create_animal(
        species,
        animal_options(
            1, quality=CROWD, sex=MALE, age=ADULT, variant=Variant(morph)
        ),
    )
    var published = Float64(body.reference_length.to(METER))
    # A first pass at the published size finds the length; the step only
    # needs to be a fortieth of it.
    var step = Length(Float32(published / CANON_CELLS), METER)
    var sample = sample_mass(canon, canon.bind_pose(), step)
    var measured = Float64(sample.reference(body.reference).to(METER))
    var scale = published / measured
    var predicted = Float64(sample.total().mass.value) * scale * scale * scale
    var target = Float64(body.male_mass.to(KILOGRAM))
    return Calibration(
        scale,
        target / predicted if matched else 1.0,
        Length(Float32(measured), METER),
        body.reference_length,
        Mass(Float32(predicted), KILOGRAM),
        body.male_mass,
        matched,
    )


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
        Error: If the scale is not positive and finite.
    """
    if not (cal.scale > 0.0 and cal.scale < 1e3):
        raise Error("A calibration scale must be positive and finite")
    var grow = Warps()
    grow.add(scale_warp(cal.scale))
    var traits = animal.traits.copy()
    traits.warps.add(scale_warp(cal.scale))
    traits.set("size", traits.get("size") * cal.scale)
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
            sculpt has no flesh.
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
