# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The limb and trunk muscles of each body plan, as Hill-type muscles.

Each muscle is a straight line from an origin on one bone to an
insertion on another. Its points sit at a joint, offset across the limb
by a share of the segment it lies along, in the bind pose. Each pose
moves them with their bones, so the muscle-tendon length and the moment
arm about every joint it crosses follow the pose.

A body plan gives every species of that plan the same muscles.
`species_specs` replaces selected inputs with reference rows. Some rows
come from another breed or species. Each resulting template remains
`DESIGN`. The wiki page `Animal-anatomy` lists each source by key.

**Mammal hind limb.** The template divides the greyhound biceps
femoris mean mass, 485 g, by the mean body mass, 31.8 kg, from six
cadavers: about 1.53% a side (Williams2008a, Table 1 and Methods,
`FROM_TEXT`). Other mass shares use the rat's ratios to biceps femoris
(Eng2008, Table 1, `FROM_TEXT`). These are ratios of means. No sample
variation is propagated.

Eng2008 gives fiber lengths normalized to a 2.4 micrometer sarcomere
length. It does not give the 41.0 and 46.2 mm bone lengths that this
template uses as denominators. Their source remains untraced. They are
not the current rat rig's authored 36 and 41 mm limb lengths. The
fiber-to-bone ratios remain DESIGN: 0.83, 0.28 and 0.48 for the thigh;
0.34, 0.43 and 0.35 for the shank. `fiber_source` names Eng2008 for the
numerator, graded DESIGN because the denominator is untraced.
The rig supplies each individual's segment length. The plan uses the
rat's nonzero pennation angles; applying them across species is DESIGN.
Reading a table and reproducing its arithmetic is not an independent
source check.

**Mammal fore limb.** The greyhound's (Williams et al. 2008b, Table 1,
p. 375, 31.4 kg dogs, `FROM_TEXT`): the long head of the triceps
brachii, the one head that crosses both the shoulder and the elbow, 341
g; the biceps brachii 54.1 g; the supraspinatus 150 g; and the
superficial digital flexor 18.3 g. Their fiber lengths are shares of
the dogs' 19.75 cm humerus and 22.75 cm radius (Table 3, p. 376,
`FROM_TEXT`).

**Species tables.** Every dog uses greyhound reference muscles
(Williams2008a and Williams2008b), including a German Shepherd body
template. This breed transfer is DESIGN. Its soleus mass and fiber
length come from Hudson2011a. The cheetah takes hind- and forelimb
inputs from Hudson2011a, Table 3, and Hudson2011b, Table 2. Its 33.1 kg
normalization mass is the mean of the five subjects with known mass;
the muscle tables include more subjects. These are reference choices,
not paired individual measurements. The cheetah uses greyhound
pennation proxies except for the soleus. Dog and cheetah soleus keep
the plan's rat angle, 3.9 degrees, explicitly graded DESIGN. The horse
takes its own hind limb (Payne et al. 2005, Table 4, p. 561; 510 kg, Table 3), and the rat
its own (Eng et al. 2008). A muscle of two or three heads sums their
masses and takes a mass-weighted harmonic mean of their fiber lengths.
This makes volume over fiber length additive before rounding. Pennation
uses a mass-weighted mean. These reductions and cube-root scaling of
fiber length with body mass remain DESIGN. They do not preserve each
head's force direction. Payne2005, Table 5, uses geometric similarity
for comparisons, not validation of the generated template.

**Bird.** The template uses medians of the 42 rows in Hartman1961,
Table 3, p. 89: pectoralis 14.875% and supracoracoideus 1.415% of body
mass for both sides. Each is halved for one side. These summaries are
DESIGN choices from FROM_TEXT inputs. Species rows use Table 1 inputs,
with the transfers described below. The White Leghorn's pectoral
muscles are 10.6% (20 birds, p. 45), split 8.78 : 3.50 as in the one bird weighed by muscle.
The American crow's are 14.2% (3 birds, p. 71), split as in
*Cyanocorax affinis* on the same page. Hartman has no golden eagle, so
the eagle takes the mean of five accipitrids on p. 43. These splits
and cross-species means are DESIGN choices. Hartman's totals include
both sides: Methods, p. 2, describes initial bilateral measurements
and later doubling of one-sided measurements.

**Frog.** The hind limbs hold 33% of body mass in *Litoria nasuta*
(James and Wilson 2008, abstract); the plantaris is 19.4% of it
(`FROM_TEXT`: no copy of the paper was readable). The cruralis and the
semimembranosus are `DESIGN` shares.

The attachment offsets are `DESIGN` choices that give each muscle its
known action: the biceps femoris extends the hip and flexes the knee,
the gastrocnemius extends the hock, and so on. The tendon slack length
makes the fibers optimal in the standing bind pose, as a scaled model
assumes.

The fish, shark, snake and spider muscles are in
`extensions/animals/anatomy/axial.mojo`.
"""

from extensions.anatomy.evidence import (
    DESIGN,
    FROM_TEXT,
    Cited,
    Evidence,
)
from extensions.anatomy.muscle import (
    MuscleArchitecture,
    default_tension,
    muscle_density,
)
from extensions.animals.anatomy.body import (
    ANURAN,
    BIRD,
    MAMMAL,
    BodyPlan,
    species_body,
)
from extensions.animals.registry import (
    CHEETAH,
    CHICKEN,
    CROW,
    DOG,
    EAGLE,
    HORSE,
    RAT,
    SpeciesId,
)
from extensions.animals.rig import Pose, Rig
from extensions.sdf.vector import V3, Rigid, cross, dot, length, lerp
from std.math import cos, isfinite, pow
from units.si import DEGREE, KILOGRAM, METER, Angle, Length, Mass

# The greyhound's biceps femoris share of body mass, a side.
comptime BICEPS_FEMORIS_SHARE = 485.0 / 31800.0
# The greyhounds' humerus and radius (Williams et al. 2008b, Table 3).
comptime GREYHOUND_HUMERUS = 0.1975
comptime GREYHOUND_RADIUS = 0.2275


@fieldwise_init
struct Attachment(Copyable, Movable):
    """Where a muscle meets a bone, in the bind pose.

    The point is `lerp(joint a, joint b, t)` plus `offset` times the
    length of the muscle's fiber bone. `offset` is in the animal's frame: `+y` dorsal,
    `+z` cranial and `+x` lateral, mirrored for the right side.
    """

    # The bone the point rides, `{S}` for the side.
    var bone: String
    var a: String
    var b: String
    var t: Float64
    var offset: V3


@fieldwise_init
struct MuscleSpec(Copyable, Movable):
    """One muscle of a body plan, before it meets an individual."""

    var name: String
    var origin: Attachment
    var insertion: Attachment
    # Its mass over body mass, one side.
    var share: Float64
    var share_source: Cited
    # Its optimal fiber length over the length of `fiber_bone`, unless
    # `source_kg` is positive.
    var fiber_ratio: Float64
    var fiber_bone: String
    # Citation for the fiber input; model_evidence grades the ratio.
    var fiber_source: Cited
    # When positive, the optimal fiber length is `fiber_m` meters in an
    # animal of `source_kg`, and scales with the cube root of mass.
    var fiber_m: Float64
    var source_kg: Float64
    var pennation_degrees: Float64
    var pennation_source: Cited
    # The joints it crosses, `{S}` for the side.
    var crosses: List[String]
    # The sculpt's tags that show its belly.
    var bellies: List[String]
    # The axis its joints turn about, in the bind pose: `+x` for a limb
    # that swings fore and aft, `+z` for a wing that beats up and down.
    var axis: V3
    # Where the path turns over a pulley or wraps behind a joint, in
    # order from the origin. Each rides its own bone.
    var vias: List[Attachment]

    def model_evidence(self) -> Evidence:
        """Return DESIGN for the architecture template derived from references.

        Returns:
            DESIGN. share_source and fiber_source describe source inputs;
            applying them to another species is not a measured architecture.
        """
        return DESIGN

    def fiber_length(self, reach: Float64, body_kg: Float64) raises -> Float64:
        """Return the optimal fiber length in one individual.

        Args:
            reach: The length of its fiber bone, in meters.
            body_kg: Its body mass, in kilograms.

        Returns:
            A finite positive fiber length, in meters.

        Raises:
            Error: If reach or body mass is not finite and positive, the
                source mass is invalid, the active fiber parameter is
                invalid, or the result is not finite and positive.
        """
        if not (isfinite(reach) and reach > 0.0):
            raise Error("Fiber reach must be finite and positive")
        if not (isfinite(body_kg) and body_kg > 0.0):
            raise Error("Fiber body mass must be finite and positive")
        if not (isfinite(self.source_kg) and self.source_kg >= 0.0):
            raise Error("Fiber source mass must be finite and nonnegative")
        var fiber: Float64
        if self.source_kg > 0.0:
            if not (isfinite(self.fiber_m) and self.fiber_m > 0.0):
                raise Error(
                    "Reference fiber length must be finite and positive"
                )
            fiber = self.fiber_m * pow(body_kg / self.source_kg, 1.0 / 3.0)
        else:
            if not (isfinite(self.fiber_ratio) and self.fiber_ratio > 0.0):
                raise Error("Fiber ratio must be finite and positive")
            fiber = self.fiber_ratio * reach
        if not (isfinite(fiber) and fiber > 0.0):
            raise Error("Fiber result must be finite and positive")
        return fiber


@fieldwise_init
struct MuscleRow(Copyable, Movable):
    """Reference inputs selected for one species template."""

    # The plan's muscle it replaces.
    var name: String
    # The mean belly mass, one side, and the selected normalization mass.
    var mass_kg: Float64
    var source_kg: Float64
    # The mean optimal fiber length, or zero to keep the plan's.
    var fiber_m: Float64
    # The mean pennation angle, or a negative value to keep the plan's.
    var pennation_degrees: Float64
    var source: Cited
    var pennation_source: Cited


def _at(bone: String, a: String, b: String, t: Float64, o: V3) -> Attachment:
    return Attachment(bone, a, b, t, o)


def _spec(
    name: String,
    origin: Attachment,
    insertion: Attachment,
    share: Float64,
    share_grade: Evidence,
    share_source: String,
    fiber_ratio: Float64,
    fiber_bone: String,
    fiber_grade: Evidence,
    fiber_source: String,
    pennation: Float64,
    pennation_grade: Evidence,
    pennation_source: String,
    var crosses: List[String],
    var bellies: List[String],
    axis: V3 = V3(1.0, 0.0, 0.0),
    var vias: List[Attachment] = [],
) -> MuscleSpec:
    return MuscleSpec(
        name,
        origin.copy(),
        insertion.copy(),
        share,
        Cited(share_grade, share_source),
        fiber_ratio,
        fiber_bone,
        Cited(fiber_grade, fiber_source),
        0.0,
        0.0,
        pennation,
        Cited(pennation_grade, pennation_source),
        crosses^,
        bellies^,
        axis,
        vias^,
    )


def _mammal() -> List[MuscleSpec]:
    var bf = BICEPS_FEMORIS_SHARE
    var dog = 31400.0
    var hum = GREYHOUND_HUMERUS
    var out = List[MuscleSpec]()
    # Hind limb: Eng et al. 2008, Table 1, p. 2339, in mg, cm and degrees.
    # The gastrocnemius sums the medial (849.17 mg, 1.61 cm, 14.0) and
    # lateral (1031.17 mg, 1.56 cm, 14.2) heads.
    # fmt: off
    out.append(_spec("biceps femoris",
        _at("pelvis", "hip{S}", "hip{S}", 0.0, V3(0.0, 0.05, -0.45)),
        _at("tibia{S}", "knee{S}", "hock{S}", 0.25, V3(0.0, 0.0, -0.12)),
        bf, FROM_TEXT, "Williams2008a", 34.0 / 41.0, "femur{S}", DESIGN, "Eng2008",
        3.6, FROM_TEXT, "Eng2008", ["hip{S}", "knee{S}"], ["hamstring", "breeches"]))
    out.append(_spec("rectus femoris",
        _at("pelvis", "hip{S}", "hip{S}", 0.0, V3(0.0, 0.05, 0.15)),
        _at("tibia{S}", "knee{S}", "knee{S}", 0.0, V3(0.0, -0.05, 0.15)),
        bf * 945.33 / 2670.83, FROM_TEXT, "Eng2008", 11.6 / 41.0, "femur{S}", DESIGN, "Eng2008",
        25.4, FROM_TEXT, "Eng2008", ["hip{S}", "knee{S}"], ["thighfront"]))
    out.append(_spec("vastus lateralis",
        _at("femur{S}", "hip{S}", "knee{S}", 0.15, V3(0.0, 0.0, 0.10)),
        _at("tibia{S}", "knee{S}", "knee{S}", 0.0, V3(0.0, -0.05, 0.15)),
        bf * 1288.83 / 2670.83, FROM_TEXT, "Eng2008", 19.6 / 41.0, "femur{S}", DESIGN, "Eng2008",
        10.0, FROM_TEXT, "Eng2008", ["knee{S}"], ["thigh", "thighmuscle"]))
    out.append(_spec("gastrocnemius",
        _at("femur{S}", "knee{S}", "knee{S}", 0.0, V3(0.0, 0.05, -0.10)),
        _at("metatarsus{S}", "hock{S}", "hock{S}", 0.0, V3(0.0, 0.0, -0.25)),
        bf * 1880.34 / 2670.83, FROM_TEXT, "Eng2008", 15.82 / 46.2, "tibia{S}", DESIGN, "Eng2008",
        14.1, FROM_TEXT, "Eng2008", ["knee{S}", "hock{S}"], ["calf", "gaskin"]))
    out.append(_spec("soleus",
        _at("tibia{S}", "knee{S}", "hock{S}", 0.15, V3(0.0, 0.0, -0.08)),
        _at("metatarsus{S}", "hock{S}", "hock{S}", 0.0, V3(0.0, 0.0, -0.25)),
        bf * 134.67 / 2670.83, FROM_TEXT, "Eng2008", 19.7 / 46.2, "tibia{S}", DESIGN, "Eng2008",
        3.9, FROM_TEXT, "Eng2008", ["hock{S}"], []))
    out.append(_spec("tibialis anterior",
        _at("tibia{S}", "knee{S}", "hock{S}", 0.15, V3(0.0, 0.0, 0.08)),
        _at("metatarsus{S}", "hock{S}", "mtp{S}", 0.2, V3(0.0, 0.0, 0.06)),
        bf * 662.17 / 2670.83, FROM_TEXT, "Eng2008", 16.4 / 46.2, "tibia{S}", DESIGN, "Eng2008",
        12.8, FROM_TEXT, "Eng2008", ["hock{S}"], ["shin"]))
    # Fore limb: Williams et al. 2008b, Table 1, p. 375, in g, cm and
    # degrees; the bones are Table 3's.
    out.append(_spec("triceps brachii",
        _at("scapula{S}", "scapTop{S}", "shoulder{S}", 0.7, V3(0.0, 0.0, -0.15)),
        _at("radius{S}", "elbow{S}", "elbow{S}", 0.0, V3(0.0, 0.02, -0.20)),
        341.0 / dog, FROM_TEXT, "Williams2008b", 0.065 / hum, "humerus{S}", FROM_TEXT, "Williams2008b",
        31.0, FROM_TEXT, "Williams2008b", ["shoulder{S}", "elbow{S}"], ["triceps"]))
    out.append(_spec("biceps brachii",
        _at("scapula{S}", "shoulder{S}", "shoulder{S}", 0.0, V3(0.0, 0.10, 0.10)),
        _at("radius{S}", "elbow{S}", "wrist{S}", 0.12, V3(0.0, 0.0, 0.08)),
        54.1 / dog, FROM_TEXT, "Williams2008b", 0.018 / hum, "humerus{S}", FROM_TEXT, "Williams2008b",
        41.0, FROM_TEXT, "Williams2008b", ["shoulder{S}", "elbow{S}"], ["upperarm"]))
    out.append(_spec("supraspinatus",
        _at("scapula{S}", "scapTop{S}", "shoulder{S}", 0.4, V3(0.0, 0.0, 0.10)),
        _at("humerus{S}", "shoulder{S}", "shoulder{S}", 0.0, V3(0.0, 0.05, 0.12)),
        150.0 / dog, FROM_TEXT, "Williams2008b", 0.059 / hum, "humerus{S}", FROM_TEXT, "Williams2008b",
        18.0, FROM_TEXT, "Williams2008b", ["shoulder{S}"], ["scapmuscle"]))
    out.append(_spec("superficial digital flexor",
        _at("humerus{S}", "elbow{S}", "elbow{S}", 0.0, V3(0.0, 0.0, -0.10)),
        _at("fpaw{S}", "mcp{S}", "ftoe{S}", 0.3, V3(0.0, -0.03, -0.02)),
        18.3 / dog, FROM_TEXT, "Williams2008b", 0.012 / GREYHOUND_RADIUS, "radius{S}", FROM_TEXT, "Williams2008b",
        41.0, FROM_TEXT, "Williams2008b", ["elbow{S}", "wrist{S}", "mcp{S}"], ["forearmmuscle"],
        V3(1.0, 0.0, 0.0),
        # Its tendon runs behind the carpus and over the sesamoids.
        [
            _at("radius{S}", "wrist{S}", "wrist{S}", 0.0, V3(0.0, 0.0, -0.06)),
            _at("metacarpus{S}", "mcp{S}", "mcp{S}", 0.0, V3(0.0, 0.02, -0.08)),
        ]))
    # fmt: on
    return out^


def _bird() -> List[MuscleSpec]:
    var out = List[MuscleSpec]()
    # fmt: off
    out.append(_spec("pectoralis",
        _at("chest", "shoulder{S}", "shoulder{S}", 0.0, V3(-0.9, -0.9, 0.3)),
        _at("humerus{S}", "shoulder{S}", "elbow{S}", 0.25, V3(0.0, -0.12, 0.0)),
        0.14875 / 2.0, FROM_TEXT, "Hartman1961", 0.8, "humerus{S}", DESIGN, "",
        0.0, DESIGN, "", ["shoulder{S}"], ["breast"], V3(0.0, 0.0, 1.0)))
    out.append(_spec("supracoracoideus",
        _at("chest", "shoulder{S}", "shoulder{S}", 0.0, V3(-0.8, -0.6, 0.2)),
        _at("humerus{S}", "shoulder{S}", "elbow{S}", 0.05, V3(0.0, 0.10, 0.0)),
        0.01415 / 2.0, FROM_TEXT, "Hartman1961", 0.5, "humerus{S}", DESIGN, "",
        0.0, DESIGN, "", ["shoulder{S}"], [], V3(0.0, 0.0, 1.0),
        # Its tendon turns over the triosseal canal, above the shoulder,
        # and lifts the wing from there.
        [_at("chest", "shoulder{S}", "shoulder{S}", 0.0, V3(-0.15, 0.25, 0.05))]))
    # fmt: on
    return out^


def _frog() -> List[MuscleSpec]:
    var leg = 0.33 / 2.0
    var out = List[MuscleSpec]()
    # fmt: off
    out.append(_spec("plantaris",
        _at("femur{S}", "knee{S}", "knee{S}", 0.0, V3(0.0, 0.05, -0.10)),
        _at("metatarsus{S}", "hock{S}", "hock{S}", 0.0, V3(0.0, 0.0, -0.15)),
        leg * 0.194, FROM_TEXT, "James2008", 0.35, "tibia{S}", DESIGN, "",
        0.0, DESIGN, "", ["knee{S}", "hock{S}"], ["calf"]))
    out.append(_spec("cruralis",
        _at("femur{S}", "hip{S}", "knee{S}", 0.2, V3(0.0, 0.0, 0.10)),
        _at("tibia{S}", "knee{S}", "knee{S}", 0.0, V3(0.0, -0.05, 0.12)),
        leg * 0.15, DESIGN, "", 0.4, "femur{S}", DESIGN, "",
        0.0, DESIGN, "", ["knee{S}"], ["thighmuscle"]))
    out.append(_spec("semimembranosus",
        _at("pelvis", "hip{S}", "hip{S}", 0.0, V3(0.0, 0.0, -0.35)),
        _at("tibia{S}", "knee{S}", "hock{S}", 0.15, V3(0.0, 0.0, -0.10)),
        leg * 0.12, DESIGN, "", 0.6, "femur{S}", DESIGN, "",
        0.0, DESIGN, "", ["hip{S}", "knee{S}"], ["thigh"]))
    # fmt: on
    return out^


def plan_muscles(plan: BodyPlan) raises -> List[MuscleSpec]:
    """Return the limb muscles of a body plan, one side.

    Args:
        plan: The body plan.

    Returns:
        Its limb muscles. A plan without limb muscles here has none.

    Raises:
        Error: If the plan is not named.
    """
    if not plan.is_valid():
        raise Error("A body plan must be named")
    if plan == MAMMAL:
        return _mammal()
    if plan == BIRD:
        return _bird()
    if plan == ANURAN:
        return _frog()
    return List[MuscleSpec]()


def _row(
    name: String,
    grams: Float64,
    source_kg: Float64,
    fiber_cm: Float64,
    pennation: Float64,
    grade: Evidence,
    source: String,
    pennation_grade: Evidence,
    pennation_source: String,
) -> MuscleRow:
    return MuscleRow(
        name,
        grams / 1000.0,
        source_kg,
        fiber_cm / 100.0,
        pennation,
        Cited(grade, source),
        Cited(pennation_grade, pennation_source),
    )


def _share(name: String, percent: Float64) -> MuscleRow:
    # A bird's muscle as a percentage of body mass, both sides.
    return _row(
        name,
        percent * 10.0 / 2.0,
        1.0,
        0.0,
        -1.0,
        FROM_TEXT,
        "Hartman1961",
        DESIGN,
        "",
    )


def species_table(species: SpeciesId) raises -> List[MuscleRow]:
    """Return reference rows selected for a species template.

    Args:
        species: The species.

    Returns:
        Its rows, one side, empty when the plan's muscles serve.

    Raises:
        Error: If the species is not named.
    """
    if not species.is_valid():
        raise Error("No such species")
    var t = List[MuscleRow]()
    var f = FROM_TEXT
    var d = DESIGN
    # fmt: off
    if species == DOG:
        # Williams et al. 2008a, Table 1, p. 364: 31.8 kg greyhounds. The
        # gastrocnemius sums its lateral (40.9 g, 1.7 cm, 25) and medial
        # (45.1 g, 2.1 cm, 36) heads. Their soleus is in Hudson et al.
        # 2011a, Table 3, p. 367: three greyhounds of 27.3 kg (Table 1).
        var w = String("Williams2008a")
        t.append(_row("biceps femoris", 485.0, 31.8, 14.3, 0.0, f, w, f, w))
        t.append(_row("rectus femoris", 267.0, 31.8, 9.6, 20.0, f, w, f, w))
        t.append(_row("vastus lateralis", 137.0, 31.8, 12.8, 12.0, f, w, f, w))
        t.append(_row("gastrocnemius", 86.0, 31.8, 1.889, 30.8, f, w, f, w))
        t.append(_row("soleus", 9.5, 27.33, 1.8, -1.0, f, "Hudson2011a", d, "Eng2008"))
        t.append(_row("tibialis anterior", 25.2, 31.8, 6.0, 20.0, f, w, f, w))
    elif species == CHEETAH:
        # Hudson et al. 2011a, Table 3, p. 367, and 2011b, Table 2,
        # p. 378: the mean of the five weighed cheetahs is 33.1 kg
        # (Table 1). The tables give no pennation: the greyhound's.
        # The gastrocnemius sums its lateral (31.1 g, 2.5 cm) and medial
        # (47.1 g, 2.8 cm) heads.
        var h = String("Hudson2011a")
        var g = String("Hudson2011b")
        var wh = String("Williams2008a")
        var wf = String("Williams2008b")
        t.append(_row("biceps femoris", 295.0, 33.1, 14.6, 0.0, f, h, d, wh))
        t.append(_row("rectus femoris", 160.0, 33.1, 5.4, 20.0, f, h, d, wh))
        t.append(_row("vastus lateralis", 214.0, 33.1, 7.6, 12.0, f, h, d, wh))
        t.append(_row("gastrocnemius", 78.2, 33.1, 2.672, 30.8, f, h, d, wh))
        t.append(_row("soleus", 16.0, 33.1, 2.4, -1.0, f, h, d, "Eng2008"))
        t.append(_row("tibialis anterior", 39.3, 33.1, 8.8, 20.0, f, h, d, wh))
        t.append(_row("triceps brachii", 255.4, 33.1, 6.0, 31.0, f, g, d, wf))
        t.append(_row("biceps brachii", 88.8, 33.1, 3.6, 41.0, f, g, d, wf))
        t.append(_row("supraspinatus", 206.4, 33.1, 7.9, 18.0, f, g, d, wf))
        t.append(_row("superficial digital flexor", 23.4, 33.1, 1.0, 41.0, f, g, d, wf))
    elif species == HORSE:
        # Payne et al. 2005, Table 4, p. 561: one pelvic limb each of seven
        # horses, five of them Thoroughbreds; 510 kg is their mean (Table
        # 3). The biceps femoris sums its intermediate (870 g,
        # 235 mm, 27), vertebral (6112 g, 258 mm, 37) and caudal (946 g,
        # 245 mm, 39) heads; the gastrocnemius its medial (817 g, 48 mm,
        # 36) and lateral (808 g, 56 mm, 34) heads.
        var p = String("Payne2005")
        t.append(_row("biceps femoris", 7928.0, 510.0, 25.37, 36.1, f, p, f, p))
        t.append(_row("rectus femoris", 2291.0, 510.0, 9.8, 40.0, f, p, f, p))
        t.append(_row("vastus lateralis", 1734.0, 510.0, 15.5, 36.0, f, p, f, p))
        t.append(_row("gastrocnemius", 1625.0, 510.0, 5.167, 35.0, f, p, f, p))
        t.append(_row("soleus", 6.0, 510.0, 12.1, 22.0, f, p, f, p))
        t.append(_row("tibialis anterior", 309.0, 510.0, 4.0, 41.0, f, p, f, p))
    elif species == RAT:
        # Eng et al. 2008, Table 1, p. 2339: rats of 323 g (p. 2337).
        var e = String("Eng2008")
        t.append(_row("biceps femoris", 2.67083, 0.323, 3.40, 3.6, f, e, f, e))
        t.append(_row("rectus femoris", 0.94533, 0.323, 1.16, 25.4, f, e, f, e))
        t.append(_row("vastus lateralis", 1.28883, 0.323, 1.96, 10.0, f, e, f, e))
        t.append(_row("gastrocnemius", 1.88034, 0.323, 1.582, 14.1, f, e, f, e))
        t.append(_row("soleus", 0.13467, 0.323, 1.97, 3.9, f, e, f, e))
        t.append(_row("tibialis anterior", 0.66217, 0.323, 1.64, 12.8, f, e, f, e))
    elif species == CHICKEN:
        # Hartman 1961, Table 1, p. 45: White Leghorns.
        t.append(_share("pectoralis", 10.6 * 8.78 / 12.28))
        t.append(_share("supracoracoideus", 10.6 * 3.50 / 12.28))
    elif species == CROW:
        # Hartman 1961, Table 1, p. 71: Corvus brachyrhynchos pascuus,
        # split as Cyanocorax affinis (12.36 : 1.01).
        t.append(_share("pectoralis", 14.2 * 12.36 / 13.37))
        t.append(_share("supracoracoideus", 14.2 * 1.01 / 13.37))
    elif species == EAGLE:
        # Hartman 1961, Table 1, p. 43: the mean of Buteo platypterus,
        # B. magnirostris, Buteogallus anthracinus, Spizastur
        # melanoleucus and Heterospizias meridionalis.
        t.append(_share("pectoralis", 13.432))
        t.append(_share("supracoracoideus", 0.487))
    # fmt: on
    return t^


def species_specs(species: SpeciesId) raises -> List[MuscleSpec]:
    """Return a species template's muscles with selected reference rows.

    Args:
        species: The species.

    Returns:
        The plan's muscles, one side, replaced by selected reference
        rows where available. The resulting template remains DESIGN.

    Raises:
        Error: If the species is not named.
    """
    var specs = plan_muscles(species_body(species).plan)
    var rows = species_table(species)
    for k in range(len(specs)):
        for row in rows:
            if row.name != specs[k].name:
                continue
            ref s = specs[k]
            s.share = row.mass_kg / row.source_kg
            s.share_source = row.source.copy()
            if row.fiber_m > 0.0:
                s.fiber_m = row.fiber_m
                s.source_kg = row.source_kg
                s.fiber_source = row.source.copy()
            if row.pennation_degrees >= 0.0:
                s.pennation_degrees = row.pennation_degrees
                s.pennation_source = row.pennation_source.copy()
            elif row.pennation_source.source != "":
                # A missing angle can retain a named DESIGN proxy.
                s.pennation_source = row.pennation_source.copy()
    return specs^


def _sided(name: String, side: String) -> String:
    return name.replace("{S}", side)


@fieldwise_init
struct AnimalMuscle(Copyable, Movable):
    """One muscle of one individual, on one side."""

    var name: String
    var side: String
    var arch: MuscleArchitecture
    # The path in the bind pose, in meters: the origin, any pulleys,
    # and the insertion. Each point rides the bone at the same index.
    var points: List[V3]
    var bones: List[Int]
    # The joints it crosses, by joint index.
    var joints: List[Int]
    # The bone that each joint is the head of: the one it turns.
    var joint_bones: List[Int]
    # For each joint, the path segment that spans it: from point
    # `k - 1` to point `k`.
    var spans: List[Int]
    # The joints' axis in the bind pose, mirrored for the side.
    var axis: V3
    var share_source: Cited
    var fiber_source: Cited
    var bellies: List[String]

    def model_evidence(self) -> Evidence:
        """Return DESIGN for this individual's generated muscle architecture.

        Returns:
            DESIGN, distinct from the retained source reference grades.
        """
        return DESIGN

    def path(self, world: List[Rigid]) raises -> List[V3]:
        """Return the path in a pose.

        Args:
            world: The pose's world transform of each bone.

        Returns:
            The points, origin first, in meters.

        Raises:
            Error: If the architecture, indexes, points or segments are invalid.
        """
        self.arch.check()
        if len(self.points) < 2 or len(self.points) != len(self.bones):
            raise Error("A muscle path needs paired points and bones")
        var out = List[V3](capacity=len(self.points))
        for k in range(len(self.points)):  # pragma: no branch
            var bone = self.bones[k]
            if bone < 0 or bone >= len(world):
                raise Error("A muscle path names a missing bone transform")
            var p = world[bone].apply(self.points[k])
            if not (isfinite(p.x) and isfinite(p.y) and isfinite(p.z)):
                raise Error("A muscle path must have finite points")
            if k > 0:
                var span = length(p - out[k - 1])
                if not (isfinite(span) and span > 0.0):
                    raise Error(
                        "A muscle path segment must have positive length"
                    )
            out.append(p)
        return out^

    def moment_arms(self, rig: Rig, world: List[Rigid]) raises -> List[Length]:
        """Return the moment arm about each joint the muscle crosses.

        A positive arm turns the distal bone about the joint's axis by
        the right-hand rule: a limb extensor at the hip, a knee flexor.
        Each uses the stretch of the path that spans the joint.

        Args:
            rig: The individual's rig.
            world: The pose's world transform of each bone.

        Returns:
            One moment arm per crossed joint, in meters.

        Raises:
            Error: If the path, joint mapping, axis or SI result is invalid.
        """
        if len(world) != len(rig.bones):
            raise Error("Muscle transforms must match the rig")
        if len(self.joints) != len(self.joint_bones) or len(self.joints) != len(
            self.spans
        ):
            raise Error("Muscle joints need paired bones and spans")
        var axis_length = length(self.axis)
        if not (isfinite(axis_length) and axis_length > 0.0):
            raise Error("A muscle axis must be finite and nonzero")
        var expected_spans = spans_of(rig, self.bones, self.joint_bones)
        for n in range(len(self.spans)):
            if self.spans[n] != expected_spans[n]:
                raise Error(
                    "A muscle joint span does not match the bone hierarchy"
                )
        var p = self.path(world)
        var out = List[Length](capacity=len(self.joints))
        for n in range(len(self.joints)):  # pragma: no branch
            var joint = self.joints[n]
            var bone = self.joint_bones[n]
            var span = self.spans[n]
            if joint < 0 or joint >= len(rig.joints):
                raise Error("A muscle names a missing joint")
            # `spans_of` above refused a joint bone the rig lacks, and the
            # world matches the rig.
            debug_assert(bone >= 0 and bone < len(world), "A joint bone exists")
            var head = rig.bones[bone].head
            if (
                joint >= len(rig.joint_names)
                or rig.joint_names[joint] != head
                or rig.find_joint(head) != joint
            ):
                raise Error(
                    "A muscle joint must be the head of its turning bone"
                )
            # Each span matched `spans_of`, which keeps it inside the path.
            debug_assert(span > 0 and span < len(p), "A span is in its path")
            ref turn = world[bone]
            var center = turn.apply(rig.joints[self.joints[n]])
            var axis = turn.turn(self.axis * (1.0 / axis_length))
            var k = self.spans[n]
            var lever = p[k] - center
            var line = p[k - 1] - p[k]
            var pull = line * (1.0 / length(line))
            var arm = dot(cross(lever, pull), axis)
            if not isfinite(Float32(arm)):
                raise Error("A muscle moment arm must fit a finite SI length")
            out.append(Length(Float32(arm), METER))
        return out^

    def unit_length(self, world: List[Rigid]) raises -> Length:
        """Return the muscle-tendon length in a pose.

        Args:
            world: The pose's world transform of each bone.

        Returns:
            The path's length, in meters.

        Raises:
            Error: If the path or its SI length is invalid.
        """
        var p = self.path(world)
        var unit = 0.0
        for k in range(1, len(p)):  # pragma: no branch
            unit += length(p[k] - p[k - 1])
        if not (isfinite(Float32(unit)) and Float32(unit) > 0.0):
            raise Error(
                "A muscle path length must fit a positive finite SI length"
            )
        return Length(Float32(unit), METER)


def descends(rig: Rig, bone: Int, ancestor: Int) raises -> Bool:
    """Return whether a bone is another or rides it.

    Args:
        rig: The rig.
        bone: The bone, by index.
        ancestor: The bone it may ride, by index.

    Returns:
        True if `bone` is `ancestor` or a child of a child of it.

    Raises:
        Error: If an index or the parent chain is invalid.
    """
    if bone < 0 or bone >= len(rig.bones):
        raise Error("A descendant must name a bone")
    if ancestor < 0 or ancestor >= len(rig.bones):
        raise Error("An ancestor must name a bone")
    var b = bone
    while b >= 0:
        if b == ancestor:
            return True
        var parent = rig.bones[b].parent.value
        if parent < -1 or parent >= b:
            raise Error("A bone parent must be a root or an earlier bone")
        b = parent
    return False


def spans_of(
    rig: Rig, bones: List[Int], joint_bones: List[Int]
) raises -> List[Int]:
    """Return, for each joint, the path segment that crosses it.

    Args:
        rig: The rig.
        bones: The bone each path point rides, origin first.
        joint_bones: The bone each joint turns.

    Returns:
        For each joint, the index of the first point that the joint
        moves: the segment ends there.

    Raises:
        Error: If the origin already rides the joint's bone, or no point
            does.
    """
    if len(bones) < 2:
        raise Error("A muscle path needs at least two bones")
    var out = List[Int]()
    for jb in joint_bones:  # pragma: no branch
        if descends(rig, bones[0], jb):
            raise Error("A muscle's origin must be above the joints it crosses")
        var k = 1
        while k < len(bones) and not descends(rig, bones[k], jb):
            k += 1
        if k == len(bones):
            raise Error("A muscle must insert beyond the joints it crosses")
        # `k` is below `len(bones)`: the check above refused the rest.
        for after in range(k, len(bones)):  # pragma: no branch
            if not descends(rig, bones[after], jb):
                raise Error("A muscle path cannot cross back over a joint")
        out.append(k)
    return out^


def _point(rig: Rig, at: Attachment, side: String, scale: Float64) raises -> V3:
    var a = rig.j(_sided(at.a, side))
    var b = rig.j(_sided(at.b, side))
    var mirror = 1.0 if side == "L" else -1.0
    var o = at.offset
    # The rig's +x is the animal's left, so lateral is +x on the left.
    var lateral = V3(o.x * mirror, o.y, o.z)
    return lerp(a, b, at.t) + lateral * scale


def _head_bone(rig: Rig, joint: String) raises -> Int:
    # The bone a joint turns: the first whose head it is.
    for i in range(len(rig.bones)):  # pragma: no branch
        if rig.bones[i].head == joint:
            return i
    raise Error("No bone turns at " + joint)


def _build(
    rig: Rig, specs: List[MuscleSpec], body_mass: Mass
) raises -> List[AnimalMuscle]:
    var m = Float64(body_mass.to(KILOGRAM))
    if not (isfinite(m) and m > 0.0):
        raise Error("A body mass must be positive")
    var out = List[AnimalMuscle]()
    for side in ["L", "R"]:  # pragma: no branch
        for spec in specs:
            var fiber_bone = rig.bone(_sided(spec.fiber_bone, side))
            var reach = length(
                rig.tail_of(fiber_bone) - rig.head_of(fiber_bone)
            )
            var points: List[V3] = [_point(rig, spec.origin, side, reach)]
            var bones: List[Int] = [
                rig.bone(_sided(spec.origin.bone, side)).value
            ]
            for via in spec.vias:
                points.append(_point(rig, via, side, reach))
                bones.append(rig.bone(_sided(via.bone, side)).value)
            points.append(_point(rig, spec.insertion, side, reach))
            bones.append(rig.bone(_sided(spec.insertion.bone, side)).value)
            var fiber = spec.fiber_length(reach, m)
            var unit = 0.0
            for k in range(1, len(points)):  # pragma: no branch
                unit += length(points[k] - points[k - 1])
            var pennation = spec.pennation_degrees * 0.017453292519943295
            var slack = unit - fiber * cos(pennation)
            if slack <= 0.0:
                raise Error(
                    "The muscle " + spec.name + " is shorter than its fibers"
                )
            var arch = MuscleArchitecture(
                Mass(Float32(spec.share * m), KILOGRAM),
                Length(Float32(fiber), METER),
                Angle(Float32(spec.pennation_degrees), DEGREE),
                Length(Float32(slack), METER),
                default_tension(),
                muscle_density(),
            )
            arch.check()
            var joints = List[Int]()
            var joint_bones = List[Int]()
            for j in spec.crosses:  # pragma: no branch
                var name = _sided(j, side)
                joints.append(rig.find_joint(name))
                joint_bones.append(_head_bone(rig, name))
            var mirror = 1.0 if side == "L" else -1.0
            # A mirrored axis keeps the right-hand rule's sense per side.
            var axis = V3(
                spec.axis.x, spec.axis.y * mirror, spec.axis.z * mirror
            )
            var spans = spans_of(rig, bones, joint_bones)
            out.append(
                AnimalMuscle(
                    spec.name,
                    String(side),
                    arch,
                    points^,
                    bones^,
                    joints^,
                    joint_bones^,
                    spans^,
                    axis,
                    spec.share_source.copy(),
                    spec.fiber_source.copy(),
                    spec.bellies.copy(),
                )
            )
    return out^


def animal_muscles(
    rig: Rig, plan: BodyPlan, body_mass: Mass
) raises -> List[AnimalMuscle]:
    """Return an individual's limb muscles from its plan, both sides.

    Args:
        rig: The individual's rig, in real meters.
        plan: Its body plan.
        body_mass: Its body mass.

    Returns:
        Every muscle of the plan, left side then right side, with its
        architecture in SI units.

    Raises:
        Error: If the plan is not named, the mass is not positive, or
            the rig lacks a bone or a joint a muscle needs.
    """
    return _build(rig, plan_muscles(plan), body_mass)


def species_muscles(
    rig: Rig, species: SpeciesId, body_mass: Mass
) raises -> List[AnimalMuscle]:
    """Return an individual's limb muscles from its species, both sides.

    Selected reference rows replace the plan's muscle inputs where
    available. These may be breed or species proxies. See `species_specs`.

    Args:
        rig: The individual's rig, in real meters.
        species: Its species.
        body_mass: Its body mass.

    Returns:
        Every muscle, left side then right side, with its architecture
        in SI units.

    Raises:
        Error: If the species is not named, the mass is not positive, or
            the rig lacks a bone or a joint a muscle needs.
    """
    return _build(rig, species_specs(species), body_mass)
