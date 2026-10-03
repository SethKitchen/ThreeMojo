# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Selected reference sizes of each species, with excerpt provenance.

Each species has a body plan, an adult mass for each sex, and one
reference length that a field biologist measures: shoulder height for a
quadruped mammal, total length for a bird or a fish, snout-vent or
head-body length for a frog, a rat or a rabbit, and body length for a
spider. Engineering mode scales the sculpt so that its reference length
is the published one. The mass is then a prediction from the sculpt's
volume, and the published mass checks it.

The sources are in the wiki page `Animal-anatomy`, by key. Each value
carries its `Evidence` grade. Three were read in the source itself: the
White Leghorn's masses, measured by Hartman 1961 (Table 1, p. 45), and
the German Shepherd Dog's masses and height, from its breed standard
(FCI-Standard No. 166, p. 8). The others come from search-result text
that quotes the source, `FROM_TEXT` at best. Where a source gives a
range, the model value is a `DESIGN` choice inside it. The reference
length is the adult male's, because the calibration measures a male;
the wiki notes where a source gives only the female's.

The coat depth is how far the sculpt's surface stands off the skin: fur,
wool under the explicit fleece, and contour plumage. It is a `DESIGN`
estimate. No source we read gives it.
"""

from extensions.anatomy.evidence import (
    DESIGN,
    FROM_TEXT,
    UNVERIFIED,
    Cited,
    Evidence,
)
from extensions.animals.registry import SPECIES_COUNT, SpeciesId
from units.si import KILOGRAM, METER, Length, Mass


@fieldwise_init
struct BodyPlan(Equatable, ImplicitlyCopyable, Writable):
    """Which bauplan a species' anatomy follows."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is a named body plan.

        Returns:
            True for the seven plans.
        """
        return self.value >= 0 and self.value <= 6


# A four-legged mammal: the quadruped rig and limb muscles.
comptime MAMMAL = BodyPlan(0)
# A bird: pneumatized bones, air sacs, flight and leg muscles.
comptime BIRD = BodyPlan(1)
# A frog: a short trunk, lungs and long jumping hind legs.
comptime ANURAN = BodyPlan(2)
# A bony fish with a swim bladder and myotomal muscle.
comptime TELEOST = BodyPlan(3)
# A shark: no swim bladder, an oily liver, myotomal muscle.
comptime SHARK_PLAN = BodyPlan(4)
# A limbless squamate: a long trunk of epaxial units.
comptime SERPENT = BodyPlan(5)
# A spider: a prosoma, an abdomen, and legs extended by hemolymph.
comptime ARACHNID = BodyPlan(6)


@fieldwise_init
struct ReferenceKind(Equatable, ImplicitlyCopyable, Writable):
    """Which length the reference length measures."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is a named reference length.

        Returns:
            True for the three kinds.
        """
        return self.value >= 0 and self.value <= 2


# Ground to the top of the withers.
comptime SHOULDER_HEIGHT = ReferenceKind(0)
# Snout to vent, or head and body: the trunk and the head, nose to rump.
comptime BODY_LENGTH = ReferenceKind(1)
# Snout or bill to the tip of the tail or the tail fin, coat included.
comptime TOTAL_LENGTH = ReferenceKind(2)


@fieldwise_init
struct SpeciesBody(Copyable, Movable):
    """A species' published size."""

    var plan: BodyPlan
    # The kind of animal the numbers are for, such as a breed.
    var kind: String
    # The morph the numbers describe, or -1 when every morph is one
    # kind of animal and differs only in its coat.
    var variant: Int
    var male_mass: Mass
    var female_mass: Mass
    # Evidence for the reference excerpt, not for individual anatomy.
    var mass_source: Cited
    var reference: ReferenceKind
    var reference_length: Length
    # Evidence for the reference excerpt, not for individual anatomy.
    var length_source: Cited
    var coat_depth: Length

    def model_evidence(self) -> Evidence:
        """Return the evidence grade of the selected reference template.

        Returns:
            DESIGN. Excerpt evidence stays in mass_source and length_source;
            representative values are not measurements of this individual.
        """
        return DESIGN


def _body(
    plan: BodyPlan,
    kind: String,
    variant: Int,
    male_kg: Float32,
    female_kg: Float32,
    mass_grade: Evidence,
    mass_source: String,
    reference: ReferenceKind,
    length_m: Float32,
    length_grade: Evidence,
    length_source: String,
    coat_m: Float32,
) -> SpeciesBody:
    return SpeciesBody(
        plan,
        kind,
        variant,
        Mass(male_kg, KILOGRAM),
        Mass(female_kg, KILOGRAM),
        Cited(mass_grade, mass_source),
        reference,
        Length(length_m, METER),
        Cited(length_grade, length_source),
        Length(coat_m, METER),
    )


def _table() -> List[SpeciesBody]:
    var t = List[SpeciesBody](capacity=SPECIES_COUNT)
    var m = SHOULDER_HEIGHT
    # fmt: off
    t.append(_body(MAMMAL, "American black bear", 3, 100, 60, FROM_TEXT, "BSG", m, 0.90, FROM_TEXT, "BSG", 0.05))
    t.append(_body(MAMMAL, "central European wild boar", 0, 85, 70, FROM_TEXT, "WildlifeOnline", m, 0.75, FROM_TEXT, "WildlifeOnline", 0.02))
    t.append(_body(MAMMAL, "domestic cat", -1, 4.5, 3.5, FROM_TEXT, "ADW", m, 0.25, FROM_TEXT, "ADW", 0.012))
    t.append(_body(MAMMAL, "cheetah", -1, 50, 30, FROM_TEXT, "ADW", m, 0.80, FROM_TEXT, "ADW", 0.008))
    t.append(_body(BIRD, "White Leghorn", 1, 2.43, 1.705, FROM_TEXT, "Hartman1961", TOTAL_LENGTH, 0.45, UNVERIFIED, "", 0.02))
    t.append(_body(MAMMAL, "Holstein-Friesian", 0, 900, 680, UNVERIFIED, "Holstein", m, 1.47, FROM_TEXT, "Holstein", 0.008))
    t.append(_body(BIRD, "American crow", 0, 0.47, 0.43, FROM_TEXT, "BOW", TOTAL_LENGTH, 0.45, FROM_TEXT, "BOW", 0.012))
    t.append(_body(MAMMAL, "white-tailed deer", -1, 70, 50, FROM_TEXT, "FAO", m, 0.90, FROM_TEXT, "FAO", 0.015))
    t.append(_body(MAMMAL, "German Shepherd Dog", 0, 35, 27, FROM_TEXT, "FCI166", m, 0.625, FROM_TEXT, "FCI166", 0.03))
    t.append(_body(BIRD, "golden eagle", 1, 3.7, 5.2, FROM_TEXT, "SDZWA", TOTAL_LENGTH, 0.85, FROM_TEXT, "SDZWA", 0.025))
    t.append(_body(TELEOST, "rainbow trout", 0, 1.0, 1.0, FROM_TEXT, "TroutLW", TOTAL_LENGTH, 0.45, FROM_TEXT, "TroutLW", 0.0))
    t.append(_body(MAMMAL, "red fox", -1, 6.5, 5.0, FROM_TEXT, "ADW", m, 0.40, FROM_TEXT, "ADW", 0.03))
    t.append(_body(ANURAN, "American bullfrog", 0, 0.30, 0.30, UNVERIFIED, "", BODY_LENGTH, 0.155, FROM_TEXT, "USANPN", 0.0))
    t.append(_body(MAMMAL, "Saanen dairy goat", 0, 85, 65, UNVERIFIED, "NSWDPI", m, 0.94, FROM_TEXT, "NSWDPI", 0.01))
    t.append(_body(MAMMAL, "Thoroughbred", -1, 500, 450, FROM_TEXT, "TBMorph", m, 1.62, FROM_TEXT, "TBMorph", 0.006))
    t.append(_body(MAMMAL, "African lion", -1, 190, 126, FROM_TEXT, "SDZWA", m, 1.15, FROM_TEXT, "SDZWA", 0.015))
    t.append(_body(MAMMAL, "Large White pig", 0, 300, 250, FROM_TEXT, "TNAU", m, 0.90, UNVERIFIED, "", 0.003))
    t.append(_body(MAMMAL, "European rabbit", 0, 1.8, 1.8, FROM_TEXT, "WildlifeOnline", BODY_LENGTH, 0.38, FROM_TEXT, "WildlifeOnline", 0.015))
    t.append(_body(MAMMAL, "Norway rat", -1, 0.30, 0.25, FROM_TEXT, "ADW", BODY_LENGTH, 0.21, FROM_TEXT, "ADW", 0.005))
    t.append(_body(SHARK_PLAN, "white shark", 0, 850, 1400, FROM_TEXT, "FloridaMuseum", TOTAL_LENGTH, 3.7, FROM_TEXT, "FloridaMuseum", 0.0))
    t.append(_body(MAMMAL, "Suffolk", 1, 130, 80, FROM_TEXT, "Suffolk", m, 0.70, FROM_TEXT, "Suffolk", 0.01))
    t.append(_body(SERPENT, "corn snake", 0, 0.5, 0.5, FROM_TEXT, "VHS", BODY_LENGTH, 0.87, FROM_TEXT, "VHS", 0.0))
    t.append(_body(ARACHNID, "Mexican redknee tarantula", 1, 0.012, 0.020, FROM_TEXT, "Mendoza", BODY_LENGTH, 0.055, FROM_TEXT, "Mendoza", 0.0005))
    t.append(_body(MAMMAL, "gray wolf", -1, 55, 45, FROM_TEXT, "ADW", m, 0.80, FROM_TEXT, "ADW", 0.04))
    # fmt: on
    return t^


def species_body(id: SpeciesId) raises -> SpeciesBody:
    """Return a species' published size.

    Args:
        id: The species.

    Returns:
        Its body plan, mass by sex, reference length and coat depth.

    Raises:
        Error: If the species is not named.
    """
    if not id.is_valid():
        raise Error("No such species")
    return _table()[id.value].copy()
