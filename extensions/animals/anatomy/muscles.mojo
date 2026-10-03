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

**Mammal hind limb.** The masses are anchored on the greyhound's biceps
femoris, 485 g of a 31.8 kg dog, 1.53% of body mass (Williams et al.
2008, `FROM_TEXT`). The other five muscles keep the rat's ratios to the
biceps femoris: rectus femoris 0.354, vastus lateralis 0.483,
gastrocnemius (both heads) 0.704, soleus 0.051 and tibialis anterior
0.248 (Eng et al. 2008, Table 1, `CROSS_CHECKED`). Mass scales with body
mass, nearly isometrically (Pollock and Shadwick 1994, `FROM_ABSTRACT`).
The optimal fiber length is the rat's share of the segment it lies
along: 0.83, 0.28 and 0.48 of the femur for the thigh muscles; 0.34,
0.43 and 0.36 of the tibia for the shank muscles. The segment lengths
are the rig's.

**Mammal fore limb.** No per-muscle table was readable. The triceps is
19.8% of the fore-limb muscle (a cheetah figure of low confidence),
and the fore limbs together are 16.7% of a greyhound's body mass: 1.65%
a side, `UNVERIFIED`. The biceps brachii, the supraspinatus and the
superficial digital flexor are `DESIGN` values.

**Bird.** The pectoralis is 10% to 15% of body mass and the
supracoracoideus 1% to 2% (Hartman 1961, `FROM_TEXT`): 6.25% and 0.75%
a side.

**Frog.** The hind limbs hold 33% of body mass in *Litoria nasuta*
(James et al. 2007, `FROM_TEXT`); the plantaris is 19.4% of it. The
cruralis and the semimembranosus are `DESIGN` shares.

The attachment offsets are `DESIGN` choices that give each muscle its
known action: the biceps femoris extends the hip and flexes the knee,
the gastrocnemius extends the hock, and so on. The tendon slack length
makes the fibers optimal in the standing bind pose, as a scaled model
assumes.

The fish, shark, snake and spider muscles are in
`extensions/animals/anatomy/axial.mojo`.
"""

from extensions.anatomy.evidence import (
    CROSS_CHECKED,
    DESIGN,
    FROM_TEXT,
    UNVERIFIED,
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
from extensions.animals.rig import Pose, Rig
from extensions.sdf.vector import V3, Rigid, cross, dot, length, lerp
from std.math import cos
from units.si import DEGREE, KILOGRAM, METER, Angle, Length, Mass

# The greyhound's biceps femoris share of body mass, a side.
comptime BICEPS_FEMORIS_SHARE = 485.0 / 31800.0


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
    # Its optimal fiber length over the length of `fiber_bone`.
    var fiber_ratio: Float64
    var fiber_bone: String
    var fiber_source: Cited
    var pennation_degrees: Float64
    # The joints it crosses, `{S}` for the side.
    var crosses: List[String]
    # The sculpt's tags that show its belly.
    var bellies: List[String]
    # The axis its joints turn about, in the bind pose: `+x` for a limb
    # that swings fore and aft, `+z` for a wing that beats up and down.
    var axis: V3
    # Where the path turns over a pulley on the origin's bone, if
    # `has_via`: the line of action at the insertion points there.
    var via: Attachment
    var has_via: Bool


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
    var crosses: List[String],
    var bellies: List[String],
    axis: V3 = V3(1.0, 0.0, 0.0),
    via: Optional[Attachment] = None,
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
        pennation,
        crosses^,
        bellies^,
        axis,
        via.value().copy() if via else origin.copy(),
        Bool(via),
    )


def _mammal() -> List[MuscleSpec]:
    var bf = BICEPS_FEMORIS_SHARE
    var out = List[MuscleSpec]()
    # fmt: off
    out.append(_spec("biceps femoris",
        _at("pelvis", "hip{S}", "hip{S}", 0.0, V3(0.0, 0.05, -0.45)),
        _at("tibia{S}", "knee{S}", "hock{S}", 0.25, V3(0.0, 0.0, -0.12)),
        bf, FROM_TEXT, "Williams2008", 34.0 / 41.0, "femur{S}", CROSS_CHECKED, "Eng2008",
        0.0, ["hip{S}", "knee{S}"], ["hamstring", "breeches"]))
    out.append(_spec("rectus femoris",
        _at("pelvis", "hip{S}", "hip{S}", 0.0, V3(0.0, 0.05, 0.15)),
        _at("tibia{S}", "knee{S}", "knee{S}", 0.0, V3(0.0, -0.05, 0.15)),
        bf * 0.945 / 2.671, CROSS_CHECKED, "Eng2008", 11.6 / 41.0, "femur{S}", CROSS_CHECKED, "Eng2008",
        0.0, ["hip{S}", "knee{S}"], ["thighfront"]))
    out.append(_spec("vastus lateralis",
        _at("femur{S}", "hip{S}", "knee{S}", 0.15, V3(0.0, 0.0, 0.10)),
        _at("tibia{S}", "knee{S}", "knee{S}", 0.0, V3(0.0, -0.05, 0.15)),
        bf * 1.289 / 2.671, CROSS_CHECKED, "Eng2008", 19.6 / 41.0, "femur{S}", CROSS_CHECKED, "Eng2008",
        0.0, ["knee{S}"], ["thigh", "thighmuscle"]))
    out.append(_spec("gastrocnemius",
        _at("femur{S}", "knee{S}", "knee{S}", 0.0, V3(0.0, 0.05, -0.10)),
        _at("metatarsus{S}", "hock{S}", "hock{S}", 0.0, V3(0.0, 0.0, -0.25)),
        bf * 1.880 / 2.671, CROSS_CHECKED, "Eng2008", 15.85 / 46.2, "tibia{S}", CROSS_CHECKED, "Eng2008",
        0.0, ["knee{S}", "hock{S}"], ["calf", "gaskin"]))
    out.append(_spec("soleus",
        _at("tibia{S}", "knee{S}", "hock{S}", 0.15, V3(0.0, 0.0, -0.08)),
        _at("metatarsus{S}", "hock{S}", "hock{S}", 0.0, V3(0.0, 0.0, -0.25)),
        bf * 0.135 / 2.671, CROSS_CHECKED, "Eng2008", 19.7 / 46.2, "tibia{S}", CROSS_CHECKED, "Eng2008",
        0.0, ["hock{S}"], []))
    out.append(_spec("tibialis anterior",
        _at("tibia{S}", "knee{S}", "hock{S}", 0.15, V3(0.0, 0.0, 0.08)),
        _at("metatarsus{S}", "hock{S}", "mtp{S}", 0.2, V3(0.0, 0.0, 0.06)),
        bf * 0.662 / 2.671, CROSS_CHECKED, "Eng2008", 16.4 / 46.2, "tibia{S}", CROSS_CHECKED, "Eng2008",
        0.0, ["hock{S}"], ["shin"]))
    out.append(_spec("triceps brachii",
        _at("scapula{S}", "scapTop{S}", "shoulder{S}", 0.7, V3(0.0, 0.0, -0.15)),
        _at("radius{S}", "elbow{S}", "elbow{S}", 0.0, V3(0.0, 0.02, -0.20)),
        0.0165, UNVERIFIED, "Hudson2011", 0.45, "humerus{S}", DESIGN, "",
        0.0, ["shoulder{S}", "elbow{S}"], ["triceps"]))
    out.append(_spec("biceps brachii",
        _at("scapula{S}", "shoulder{S}", "shoulder{S}", 0.0, V3(0.0, 0.10, 0.10)),
        _at("radius{S}", "elbow{S}", "wrist{S}", 0.12, V3(0.0, 0.0, 0.08)),
        0.003, DESIGN, "", 0.30, "humerus{S}", DESIGN, "",
        0.0, ["shoulder{S}", "elbow{S}"], ["upperarm"]))
    out.append(_spec("supraspinatus",
        _at("scapula{S}", "scapTop{S}", "shoulder{S}", 0.4, V3(0.0, 0.0, 0.10)),
        _at("humerus{S}", "shoulder{S}", "shoulder{S}", 0.0, V3(0.0, 0.05, 0.12)),
        0.006, DESIGN, "", 0.40, "humerus{S}", DESIGN, "",
        0.0, ["shoulder{S}"], ["scapmuscle"]))
    out.append(_spec("superficial digital flexor",
        _at("humerus{S}", "elbow{S}", "elbow{S}", 0.0, V3(0.0, 0.0, -0.10)),
        _at("fpaw{S}", "mcp{S}", "ftoe{S}", 0.5, V3(0.0, -0.03, -0.05)),
        0.004, DESIGN, "", 0.15, "radius{S}", DESIGN, "",
        0.0, ["elbow{S}", "wrist{S}", "mcp{S}"], ["forearmmuscle"]))
    # fmt: on
    return out^


def _bird() -> List[MuscleSpec]:
    var out = List[MuscleSpec]()
    # fmt: off
    out.append(_spec("pectoralis",
        _at("chest", "shoulder{S}", "shoulder{S}", 0.0, V3(-0.9, -0.9, 0.3)),
        _at("humerus{S}", "shoulder{S}", "elbow{S}", 0.25, V3(0.0, -0.12, 0.0)),
        0.0625, FROM_TEXT, "Hartman1961", 0.8, "humerus{S}", DESIGN, "",
        0.0, ["shoulder{S}"], ["breast"], V3(0.0, 0.0, 1.0)))
    out.append(_spec("supracoracoideus",
        _at("chest", "shoulder{S}", "shoulder{S}", 0.0, V3(-0.8, -0.6, 0.2)),
        _at("humerus{S}", "shoulder{S}", "elbow{S}", 0.05, V3(0.0, 0.10, 0.0)),
        0.0075, FROM_TEXT, "Hartman1961", 0.5, "humerus{S}", DESIGN, "",
        0.0, ["shoulder{S}"], [], V3(0.0, 0.0, 1.0),
        # Its tendon turns over the triosseal canal, above the shoulder,
        # and lifts the wing from there.
        _at("chest", "shoulder{S}", "shoulder{S}", 0.0, V3(-0.15, 0.25, 0.05))))
    # fmt: on
    return out^


def _frog() -> List[MuscleSpec]:
    var leg = 0.33 / 2.0
    var out = List[MuscleSpec]()
    # fmt: off
    out.append(_spec("plantaris",
        _at("femur{S}", "knee{S}", "knee{S}", 0.0, V3(0.0, 0.05, -0.10)),
        _at("metatarsus{S}", "hock{S}", "hock{S}", 0.0, V3(0.0, 0.0, -0.15)),
        leg * 0.194, FROM_TEXT, "James2007", 0.35, "tibia{S}", DESIGN, "",
        0.0, ["knee{S}", "hock{S}"], ["calf"]))
    out.append(_spec("cruralis",
        _at("femur{S}", "hip{S}", "knee{S}", 0.2, V3(0.0, 0.0, 0.10)),
        _at("tibia{S}", "knee{S}", "knee{S}", 0.0, V3(0.0, -0.05, 0.12)),
        leg * 0.15, DESIGN, "", 0.4, "femur{S}", DESIGN, "",
        0.0, ["knee{S}"], ["thighmuscle"]))
    out.append(_spec("semimembranosus",
        _at("pelvis", "hip{S}", "hip{S}", 0.0, V3(0.0, 0.0, -0.35)),
        _at("tibia{S}", "knee{S}", "hock{S}", 0.15, V3(0.0, 0.0, -0.10)),
        leg * 0.12, DESIGN, "", 0.6, "femur{S}", DESIGN, "",
        0.0, ["hip{S}", "knee{S}"], ["thigh"]))
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


def _sided(name: String, side: String) -> String:
    return name.replace("{S}", side)


@fieldwise_init
struct AnimalMuscle(Copyable, Movable):
    """One muscle of one individual, on one side."""

    var name: String
    var side: String
    var arch: MuscleArchitecture
    var origin_bone: Int
    var insertion_bone: Int
    # The attachment points in the bind pose, in meters. `via` rides
    # the origin's bone; without a pulley it is the origin.
    var origin: V3
    var via: V3
    var insertion: V3
    # The joints it crosses, by joint index.
    var joints: List[Int]
    # The bone that each joint is the head of: the one it turns.
    var joint_bones: List[Int]
    # The joints' axis in the bind pose, mirrored for the side.
    var axis: V3
    var share_source: Cited
    var fiber_source: Cited
    var bellies: List[String]

    def path(self, world: List[Rigid]) -> Tuple[V3, V3, V3]:
        """Return the origin, the pulley and the insertion in a pose.

        Args:
            world: The pose's world transform of each bone.

        Returns:
            The three points, in meters. The pulley is the origin when
            the muscle runs straight.
        """
        ref o = world[self.origin_bone]
        var i = world[self.insertion_bone].apply(self.insertion)
        return (o.apply(self.origin), o.apply(self.via), i)

    def moment_arms(self, rig: Rig, world: List[Rigid]) -> List[Length]:
        """Return the moment arm about each joint the muscle crosses.

        A positive arm turns the distal bone about the joint's axis by
        the right-hand rule: a limb extensor at the hip, a knee flexor.

        Args:
            rig: The individual's rig.
            world: The pose's world transform of each bone.

        Returns:
            One moment arm per crossed joint, in meters.
        """
        var p = self.path(world)
        var out = List[Length](capacity=len(self.joints))
        for n in range(len(self.joints)):  # pragma: no branch
            ref turn = world[self.joint_bones[n]]
            var center = turn.apply(rig.joints[self.joints[n]])
            var axis = turn.turn(self.axis)
            var lever = p[2] - center
            var line = p[1] - p[2]
            var pull = line * (1.0 / length(line))
            var arm = dot(cross(lever, pull), axis)
            out.append(Length(Float32(arm), METER))
        return out^

    def unit_length(self, world: List[Rigid]) -> Length:
        """Return the muscle-tendon length in a pose.

        Args:
            world: The pose's world transform of each bone.

        Returns:
            Origin to insertion, in meters.
        """
        var p = self.path(world)
        var unit = length(p[1] - p[0]) + length(p[2] - p[1])
        return Length(Float32(unit), METER)


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


def animal_muscles(
    rig: Rig, plan: BodyPlan, body_mass: Mass
) raises -> List[AnimalMuscle]:
    """Return an individual's limb muscles, both sides.

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
    var m = Float64(body_mass.to(KILOGRAM))
    if not (m > 0.0):
        raise Error("A body mass must be positive")
    var specs = plan_muscles(plan)
    var out = List[AnimalMuscle]()
    for side in ["L", "R"]:  # pragma: no branch
        for spec in specs:
            var fiber_bone = rig.bone(_sided(spec.fiber_bone, side))
            var reach = length(
                rig.tail_of(fiber_bone) - rig.head_of(fiber_bone)
            )
            var origin = _point(rig, spec.origin, side, reach)
            var insertion = _point(rig, spec.insertion, side, reach)
            var via = _point(rig, spec.via, side, reach)
            var fiber = spec.fiber_ratio * reach
            var unit = length(via - origin) + length(insertion - via)
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
            out.append(
                AnimalMuscle(
                    spec.name,
                    String(side),
                    arch,
                    rig.bone(_sided(spec.origin.bone, side)).value,
                    rig.bone(_sided(spec.insertion.bone, side)).value,
                    origin,
                    via,
                    insertion,
                    joints^,
                    joint_bones^,
                    axis,
                    spec.share_source.copy(),
                    spec.fiber_source.copy(),
                    spec.bellies.copy(),
                )
            )
    return out^
