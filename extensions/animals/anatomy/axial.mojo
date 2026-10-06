# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The trunk muscles of swimmers and snakes, and a spider's leg flexors.

**Fish, shark and snake.** Each joint of the spine has a muscle on each
side, from the middle of one segment to the middle of the next, at a
lateral offset of the segment's radius of gyration. Contracting it bends
the body toward its side. Its mass is a share of the sampled mass of
the segment it inserts on: 60% for a teleost and 53% for a shark (white
muscle about 50% and red about 3% of body mass; Bernal et al. 2003 for
the red muscle, `FROM_TEXT`; the rest `UNVERIFIED`), and 30% for a snake
(`DESIGN`). The fibers fill 80% of the path, a `DESIGN` value for short
myomere fibers.

**Spider.** A spider has no extensor muscles at its femur-patella and
tibia-metatarsus joints. Hemolymph pressure extends them: about 5 to 8
kPa at rest and up to 65 kPa (Parry and Brown 1959; Anderson and
Prestwich 1975; both `FROM_TEXT`). Each of those joints has one flexor
here. Arthropod muscle develops 0.3 to 0.7 MPa (Medler 2002,
`FROM_TEXT`): the flexors use 0.5 MPa. Their mass, 0.4% of body mass
each, is a `DESIGN` value.
"""

from extensions.anatomy.evidence import (
    DESIGN,
    FROM_TEXT,
    UNVERIFIED,
    Cited,
)
from extensions.anatomy.muscle import MuscleArchitecture, muscle_density
from extensions.animals.anatomy.body import (
    ARACHNID,
    SERPENT,
    SHARK_PLAN,
    TELEOST,
    BodyPlan,
)
from extensions.animals.anatomy.mass import BodyMass
from extensions.animals.anatomy.muscles import AnimalMuscle
from extensions.animals.anatomy.tissue import ABDOMEN, TAIL, segment_of
from extensions.animals.rig import Rig
from extensions.sdf.vector import V3, cross, length, lerp, normalize
from std.math import isfinite, sqrt
from units.si import (
    DEGREE,
    KILOGRAM,
    MEGAPASCAL,
    METER,
    PASCAL,
    Angle,
    Length,
    Mass,
    Pressure,
)

# Fibers fill this share of a trunk muscle's path.
comptime FIBER_SHARE = 0.8
# A spider leg flexor's mass over body mass.
comptime FLEXOR_SHARE = 0.004


def hemolymph_pressure(peak: Bool) -> Pressure:
    """Return a spider's leg hemolymph pressure.

    Args:
        peak: True for the peak a sprint or a jump reaches, False for
            the pressure that holds a resting leg out.

    Returns:
        65 kPa at the peak, 6.5 kPa at rest.
    """
    return Pressure(Float32(65000.0 if peak else 6500.0), PASCAL)


def _trunk_share(plan: BodyPlan) -> Tuple[Float64, Cited]:
    if plan == TELEOST:
        return (0.60, Cited(UNVERIFIED, ""))
    if plan == SHARK_PLAN:
        return (0.53, Cited(UNVERIFIED, "Bernal2003"))
    return (0.30, Cited(DESIGN, ""))


def _muscle(
    name: String,
    side: String,
    rig: Rig,
    parent: Int,
    child: Int,
    origin: V3,
    insertion: V3,
    mass_kg: Float64,
    tension: Pressure,
    share_source: Cited,
    axis: V3,
) raises -> AnimalMuscle:
    var unit = length(insertion - origin)
    var arch = MuscleArchitecture(
        Mass(Float32(mass_kg), KILOGRAM),
        Length(Float32(FIBER_SHARE * unit), METER),
        Angle(0.0, DEGREE),
        Length(Float32((1.0 - FIBER_SHARE) * unit), METER),
        tension,
        muscle_density(),
    )
    arch.check()
    var joint = rig.find_joint(rig.bones[child].head)
    return AnimalMuscle(
        name,
        side,
        arch,
        [origin, insertion],
        [parent, child],
        [joint],
        [child],
        [1],
        axis,
        share_source.copy(),
        Cited(DESIGN, ""),
        List[String](),
    )


def _trunk(
    rig: Rig, plan: BodyPlan, mass: BodyMass
) raises -> List[AnimalMuscle]:
    var share = _trunk_share(plan)
    var out = List[AnimalMuscle]()
    for c in range(len(rig.bones)):  # pragma: no branch
        var p = rig.bones[c].parent.value
        if p < 0:
            continue
        var both = True
        for b in [p, c]:  # pragma: no branch
            var s = segment_of(plan, rig.bones[b].name)
            both = both and (s == ABDOMEN or s == TAIL)
        if not both:
            continue
        var m = mass.bones[c].mass
        var pa = rig.j(rig.bones[p].head)
        var pb = rig.j(rig.bones[p].tail)
        var ca = rig.j(rig.bones[c].head)
        var cb = rig.j(rig.bones[c].tail)
        var span = length(cb - ca)
        if m <= 0.0:
            # A segment with no flesh has no muscle.
            continue
        # The radius of a cylinder of the segment's mass and length.
        var radius = sqrt(m / (1000.0 * 3.141592653589793 * span))
        for side in ["L", "R"]:  # pragma: no branch
            var x = V3(radius, 0.0, 0.0) * (1.0 if side == "L" else -1.0)
            var mirror = 1.0 if side == "L" else -1.0
            out.append(
                _muscle(
                    "myomere " + rig.bones[c].name,
                    side,
                    rig,
                    p,
                    c,
                    lerp(pa, pb, 0.5) + x,
                    lerp(ca, cb, 0.5) + x,
                    0.5 * share[0] * m,
                    Pressure(0.3, MEGAPASCAL),
                    share[1].copy(),
                    # Positive bends the body toward the muscle's side.
                    V3(0.0, -mirror, 0.0),
                )
            )
    return out^


def _spider(rig: Rig, body_kg: Float64) raises -> List[AnimalMuscle]:
    var out = List[AnimalMuscle]()
    var up = V3(0.0, 1.0, 0.0)
    for side in ["L", "R"]:  # pragma: no branch
        for leg in range(1, 5):  # pragma: no branch
            var tag = String(leg) + side
            for pair in [
                ("femur", "patella"),
                ("tibia", "meta"),
            ]:  # pragma: no branch
                var p = rig.bone(pair[0] + tag).value
                var c = rig.bone(pair[1] + tag).value
                var pa = rig.j(rig.bones[p].head)
                var pb = rig.j(rig.bones[p].tail)
                var cb = rig.j(rig.bones[c].tail)
                var reach = length(pb - pa)
                var down = V3(0.0, -0.12 * reach, 0.0)
                # Positive turns the distal segment down: flexion.
                var axis = normalize(cross(up, pb - pa))
                out.append(
                    _muscle(
                        "flexor " + pair[1] + tag,
                        side,
                        rig,
                        p,
                        c,
                        lerp(pa, pb, 0.25) + down,
                        lerp(pb, cb, 0.15) + down,
                        FLEXOR_SHARE * body_kg,
                        Pressure(0.5, MEGAPASCAL),
                        Cited(DESIGN, ""),
                        axis,
                    )
                )
    return out^


def axial_muscles(
    rig: Rig, plan: BodyPlan, mass: BodyMass
) raises -> List[AnimalMuscle]:
    """Return a swimmer's or a snake's trunk muscles, or a spider's leg
    flexors.

    Args:
        rig: The individual's rig, in real meters.
        plan: Its body plan.
        mass: Its sampled mass, bone by bone, from the same rig.

    Returns:
        Both sides' muscles. Other plans have none here.

    Raises:
        Error: If the plan is not named, the mass is for another rig, or
            a spider's rig lacks a leg bone.
    """
    if not plan.is_valid():
        raise Error("A body plan must be named")
    if len(mass.bones) != len(rig.bones):
        raise Error("The mass was sampled from another rig")
    for i in range(len(rig.bones)):
        var parent = rig.bones[i].parent.value
        if parent < -1 or parent >= i:
            raise Error(
                "An axial bone parent must be a root or an earlier bone"
            )
    for tally in mass.bones:
        if not (isfinite(tally.mass) and tally.mass >= 0.0):
            raise Error("An axial muscle needs finite nonnegative segment mass")
    if plan == TELEOST or plan == SHARK_PLAN or plan == SERPENT:
        return _trunk(rig, plan, mass)
    if plan == ARACHNID:
        var body = 0.0
        for b in mass.bones:  # pragma: no branch
            body += b.mass
        return _spider(rig, body)
    return List[AnimalMuscle]()
