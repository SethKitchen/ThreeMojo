# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The wet density of each solid of a sculpt.

A mammal's segments take Dempster's segment densities (Dempster 1955,
as tabulated by Winter, *Biomechanics and Motor Control of Human
Movement*, 4th ed., 2009, Table 4.1), applied to the homologous
segment: head and neck 1.11, thorax 0.92, abdomen and pelvis 1.01,
upper arm 1.07, forearm 1.13, hand 1.16, thigh 1.05, leg 1.09 and foot
1.10 g/cm^3. The thorax is light because the lungs hold air. Dempster
measured people. Applying his values to a quadruped is a `DESIGN`
choice. A tail takes the leg's value, also by design.

Other body plans take one whole-body density:

- a bird 1.044 g/cm^3 for a plucked chicken and 0.965 g/cm^3, the middle
  of the 0.880 to 1.050 range for plucked birds, for a flier
  (Hamershock, Seamans and Bernhardt 1993, report WL-TR-93-3049);
- a fish with a swim bladder 1.00 g/cm^3 (Lindsey et al. 2010, zebrafish);
- a frog 1.00 g/cm^3 (a specific gravity of about one);
- a shark 1.05 g/cm^3, between lean tissue at 1.076 and seawater at
  1.026, `UNVERIFIED`;
- a snake 1.057 g/cm^3: 1.13 with no air, with 6.5% of the body lung;
- a spider 1.05 g/cm^3, between hemolymph and cuticle, by design.

Keratin is 1.30 g/cm^3 (McKittrick et al. 2012). Antler 1.8, tooth 2.1
and the eye 1.01 g/cm^3 are `UNVERIFIED`. Coat and foreign solids
weigh nothing: the sampler leaves them out.
"""

from extensions.animals.anatomy.body import (
    ANURAN,
    ARACHNID,
    BIRD,
    MAMMAL,
    SERPENT,
    SHARK_PLAN,
    BodyPlan,
    species_body,
)
from extensions.animals.anatomy.tissue import (
    ABDOMEN,
    ANTLER,
    COAT,
    EYE,
    FOOT,
    FOREARM,
    FOREIGN,
    HAND,
    HEAD,
    KERATIN,
    NECK,
    PELVIS,
    PLUMAGE,
    SHANK,
    TAIL,
    THIGH,
    THORAX,
    TOOTH,
    UPPER_ARM,
    BodyTissue,
    Segment,
    segment_of,
    tissue_of,
)
from extensions.animals.build import Animal
from extensions.animals.registry import CHICKEN, SpeciesId
from units.si import KILOGRAM_PER_CUBIC_METER, Density


def _density(kg_m3: Float64) -> Density:
    return Density(Float32(kg_m3), KILOGRAM_PER_CUBIC_METER)


def segment_density(plan: BodyPlan, segment: Segment) raises -> Density:
    """Return a mammal segment's density.

    Args:
        plan: The body plan. Only `MAMMAL` has segment densities.
        segment: The segment.

    Returns:
        Dempster's density for the homologous human segment.

    Raises:
        Error: If the plan is not `MAMMAL` or the segment has no
            mammal density.
    """
    if plan != MAMMAL:
        raise Error("Only a mammal has segment densities")
    if segment == HEAD or segment == NECK:
        return _density(1110)
    if segment == THORAX:
        return _density(920)
    if segment == ABDOMEN or segment == PELVIS:
        return _density(1010)
    if segment == UPPER_ARM:
        return _density(1070)
    if segment == FOREARM:
        return _density(1130)
    if segment == HAND:
        return _density(1160)
    if segment == THIGH:
        return _density(1050)
    if segment == SHANK or segment == TAIL:
        return _density(1090)
    if segment == FOOT:
        return _density(1100)
    raise Error("A mammal has no such segment")


def whole_body_density(species: SpeciesId) raises -> Density:
    """Return the one flesh density of a species that is not a mammal.

    Args:
        species: The species.

    Returns:
        Its whole-body density, coat left out.

    Raises:
        Error: If the species is a mammal or is not named.
    """
    var plan = species_body(species).plan
    if plan == MAMMAL:
        raise Error("A mammal's density is by segment")
    if plan == BIRD:
        return _density(1044.0 if species == CHICKEN else 965.0)
    if plan == SHARK_PLAN:
        return _density(1050)
    if plan == SERPENT:
        return _density(1057)
    if plan == ARACHNID:
        return _density(1050)
    # A teleost with its swim bladder, or a frog with its lungs.
    return _density(1000)


def tissue_density(tissue: BodyTissue) raises -> Density:
    """Return the density of a tissue that is not soft body.

    Args:
        tissue: The tissue.

    Returns:
        Its density. Zero for coat and foreign solids.

    Raises:
        Error: If the tissue is soft body or is not named.
    """
    if not tissue.is_valid():
        raise Error("A tissue must be named")
    if tissue == COAT or tissue == FOREIGN:
        return _density(0)
    if tissue == KERATIN:
        return _density(1300)
    if tissue == ANTLER:
        return _density(1800)
    if tissue == TOOTH:
        return _density(2100)
    if tissue == EYE:
        return _density(1010)
    raise Error("Soft body takes its segment's density")


def solid_densities(animal: Animal) raises -> List[Float64]:
    """Return the density of each solid of an animal's sculpt.

    Args:
        animal: The individual.

    Returns:
        One density per primitive, in kg/m^3, by primitive index. Zero
        for coat, foreign and carving solids, and for plumage bones.

    Raises:
        Error: If a primitive names a missing tag or bone.
    """
    var plan = species_body(animal.species).plan
    var flesh = 0.0
    if plan != MAMMAL:
        flesh = Float64(whole_body_density(animal.species).value)
    var out = List[Float64](capacity=len(animal.model.prims))
    for p in animal.model.prims:  # pragma: no branch
        animal.rig.check(p.bone)
        _ = animal.model.tag_name(p.tag)
        var bone = animal.rig.bones[p.bone.value].name
        var tissue = tissue_of(p.part, animal.model.tags[p.tag.value], bone)
        var segment = segment_of(plan, bone)
        if p.carve or segment == PLUMAGE:
            out.append(0.0)
        elif tissue.value != 0:
            out.append(Float64(tissue_density(tissue).value))
        elif plan == MAMMAL:
            out.append(Float64(segment_density(plan, segment).value))
        else:
            out.append(flesh)
    return out^


# Role bits of a solid, for the reference lengths.
comptime ON_WITHERS = 1
comptime IN_BODY = 2
comptime IS_COAT = 4


def solid_roles(animal: Animal) raises -> List[Int]:
    """Return which reference lengths each solid of a sculpt bounds.

    The withers are the chest and the shoulder blades. The body length
    runs over the head, the neck and the trunk, a snake's tail left out.
    The coat bounds only the total length.

    Args:
        animal: The individual.

    Returns:
        `ON_WITHERS`, `IN_BODY` and `IS_COAT` bits, by primitive index.

    Raises:
        Error: If a primitive names a missing tag or bone.
    """
    var plan = species_body(animal.species).plan
    var out = List[Int](capacity=len(animal.model.prims))
    for p in animal.model.prims:  # pragma: no branch
        animal.rig.check(p.bone)
        _ = animal.model.tag_name(p.tag)
        var bone = animal.rig.bones[p.bone.value].name
        var tag = animal.model.tags[p.tag.value]
        var segment = segment_of(plan, bone)
        var role = 0
        if tissue_of(p.part, tag, bone) == COAT:
            role = IS_COAT
        elif segment == THORAX and plan == MAMMAL:
            role = ON_WITHERS | IN_BODY
        elif segment == UPPER_ARM and bone.startswith("scapula"):
            role = ON_WITHERS
        elif segment.value <= PELVIS.value and not tag.startswith("tail"):
            role = IN_BODY
        out.append(role)
    return out^
