# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skin envelope derived from the modeled anatomy of the pelvis.

Transverse sections run from just below the pubic arch to a little
above the iliac crest. Each one slices both hip bones, the sacrum and
the coccyx, the pelvic muscles of both sides, and the top of each leg:
the femur and the muscles that cross the hip. It closes the outline as
a convex hull and adds the subcutaneous fat and the dermis. See
`extensions.humanoid.skeleton.loft`. A separate shell represents the
dermis for occupancy and mass.

Below the pubic arch the two thighs part. Each leg's own skin covers
its thigh there. `LowerBodySkinField` joins the three surfaces.

The solid lives in the pelvis frame. The origin is the midpoint of the
two hip joint centers. Plus y is proximal. Plus x is body-right. Plus z
is anterior.

    var dims = pelvis_muscle_dimensions(person)
    var d = pelvis_skin_distance(dims, Vector3(0, 0.05, 0.12))
"""

from extensions.humanoid.sex import MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import (
    DistanceField,
    field_gradient,
    flip_x,
    mix_point,
    smax,
)
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    FemurField,
    femur_dimensions,
)
from extensions.humanoid.skeleton.leg.knee.dimensions import (
    femur_origin,
    knee_dimensions_from_bones,
)
from extensions.humanoid.skeleton.leg.fibula.dimensions import (
    fibula_dimensions,
)
from extensions.humanoid.skeleton.leg.lymph.dimensions import (
    INGUINAL_NODES,
    LymphField,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    GLUTEUS_MAXIMUS,
    ADDUCTOR_LONGUS,
    ADDUCTOR_MAGNUS,
    BICEPS_FEMORIS,
    GLUTEUS_MEDIUS,
    GRACILIS,
    ILIOTIBIAL_TRACT,
    PECTINEUS,
    RECTUS_FEMORIS,
    SARTORIUS,
    SEMIMEMBRANOSUS,
    SEMITENDINOSUS,
    TENSOR_FASCIAE_LATAE,
    VASTUS_INTERMEDIUS,
    VASTUS_LATERALIS,
    VASTUS_MEDIALIS,
    MuscleField,
    MusclePart,
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.patella.dimensions import (
    patella_dimensions,
)
from extensions.humanoid.skeleton.leg.tibia.dimensions import tibia_dimensions
from extensions.humanoid.skeleton.loft import (
    AXIS_Y,
    Loft,
    LoftSample,
    fit_loft,
    loft_distance,
)
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    COCCYX,
    RIGHT_HIP_BONE,
    HipBoneShape,
    PelvisBoneField,
    SacrumShape,
)
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    PelvisChain,
    PelvisMuscleDimensions,
    PelvisMuscleField,
    named_pelvis_muscles,
)
from math.vector3 import Vector3
from std.math import max

# Sections from below the pubic arch to above the crest: about seven
# millimeters apart on a six-foot pelvis.
comptime PELVIS_SKIN_SECTIONS = 44
# Subcutaneous fat over the hips, buttocks and lower abdomen, in
# meters. Authored adult template values.
comptime MALE_PELVIC_FAT = Float32(0.0110)
comptime FEMALE_PELVIC_FAT = Float32(0.0200)
comptime DERMIS = Float32(0.0018)
# The natal cleft behind the coccyx: its half-width, and its rounding.
# Ratios of stature.
comptime CLEFT_HALF = Float32(0.0022)
comptime CLEFT_ROUND = Float32(0.0050)


struct PelvisSkinField(Copyable, DistanceField, Movable):
    """The outer skin surface around the modeled pelvic anatomy."""

    var subcutaneous: Float32
    var dermis: Float32
    var loft: Loft
    # The cleft runs below the sacral apex and behind the coccyx.
    var cleft_top: Float32
    var cleft_front: Float32
    var cleft_half: Float32
    var cleft_round: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: PelvisMuscleDimensions) raises:
        """Build skin around the actual modeled structures.

        Args:
            dimensions: Pelvic landmarks and the spec for the other parts.

        Raises:
            Error: If any underlying anatomical field refuses its inputs.
        """
        dimensions.validate()
        var p = dimensions.pelvis
        var S = p.stature.value
        var spec = HumanoidSpec(p.stature, p.sex, dimensions.athleticism)
        self.subcutaneous = pelvic_fat(p.sex)
        self.dermis = DERMIS
        self.cleft_top = p.sacral_apex.y
        self.cleft_front = p.coccyx_tip.z - 0.006 * S
        self.cleft_half = CLEFT_HALF * S
        self.cleft_round = CLEFT_ROUND * S
        self.epsilon = dimensions.epsilon
        var points = List[LoftSample]()
        var bones = PelvisBoneField(p, RIGHT_HIP_BONE)
        _append_hip_bone(points, bones.hip_bone, False)
        _append_hip_bone(points, bones.hip_bone, True)
        _append_sacrum(points, bones.sacrum)
        var coccyx = PelvisBoneField(p, COCCYX)
        _append_sphere(points, coccyx.coccyx0, coccyx.coccyx_ml)
        _append_sphere(points, coccyx.coccyx2, coccyx.coccyx_ml)
        var muscles = named_pelvis_muscles()
        for index in range(len(muscles)):
            var right = PelvisMuscleField(dimensions, muscles[index], RIGHT)
            _append_chains(points, right, False)
            _append_chains(points, right, True)
        _append_leg(points, spec, RIGHT, dimensions.leg_origin_at(RIGHT))
        _append_leg(points, spec, LEFT, dimensions.leg_origin_at(LEFT))
        var bottom = p.symphysis_bottom.y - 0.034 * S
        var top = p.crest_top.y + 0.025 * S
        var covers = List[Float32]()
        for _ in range(PELVIS_SKIN_SECTIONS):
            covers.append(self.subcutaneous + self.dermis)
        # Three passes fill a groove between one muscle's belly and the
        # next, as the fat over them does.
        self.loft = fit_loft(
            points, AXIS_Y, bottom, top, PELVIS_SKIN_SECTIONS, covers, 3
        )
        self.low = self.loft.low
        self.high = self.loft.high

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the anatomy-derived outer surface.

        Negative is inside. Zero is the surface.
        """
        var d = loft_distance(self.loft, point)
        # A convex section cannot hold the natal cleft, so a narrow
        # rounded slot cuts it between the buttocks.
        var slot = max(
            abs(point.x) - self.cleft_half,
            max(point.y - self.cleft_top, point.z - self.cleft_front),
        )
        return smax(d, -slot, self.cleft_round)

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


struct PelvisSkinLayerField(Copyable, DistanceField, Movable):
    """The dermal shell immediately inside a `PelvisSkinField`."""

    var outer: PelvisSkinField
    var thickness: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: PelvisMuscleDimensions) raises:
        """Build the dermal shell around the modeled anatomy.

        Args:
            dimensions: Pelvic landmarks and the spec for the other parts.

        Raises:
            Error: If the outer field refuses an anatomical input.
        """
        self.outer = PelvisSkinField(dimensions)
        self.thickness = self.outer.dermis
        self.low = self.outer.low
        self.high = self.outer.high

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the dermal shell, in meters.

        Negative is inside the dermis. Deep anatomy and exterior space
        are both outside this shell.
        """
        var d = self.outer.distance(point)
        return max(d, -d - self.thickness)


def pelvic_fat(sex: Sex) -> Float32:
    """Return the subcutaneous fat over the pelvis for `sex`, in meters.

    Args:
        sex: `MALE` or `FEMALE`. Any other value gets the female cover.

    Returns:
        The authored template thickness.
    """
    if sex == MALE:
        return MALE_PELVIC_FAT
    return FEMALE_PELVIC_FAT


def pelvis_skin_distance(
    dimensions: PelvisMuscleDimensions, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside the pelvic skin, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `pelvis_muscle_dimensions`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return PelvisSkinField(dimensions).distance(point)


def _placed(point: Vector3, mirror: Bool) -> Vector3:
    """Return `point`, mirrored on x when `mirror` is set."""
    if mirror:
        return flip_x(point)
    return point


def _append_segment(
    mut points: List[LoftSample],
    a: Vector3,
    ra: Float32,
    b: Vector3,
    rb: Float32,
):
    """Append one round tapered segment: its ends and its middle."""
    points.append(LoftSample(a, ra, ra, 0, False))
    points.append(
        LoftSample(
            mix_point(a, b, 0.5), 0.5 * (ra + rb), 0.5 * (ra + rb), 0, True
        )
    )
    points.append(LoftSample(b, rb, rb, 0, True))


def _append_sphere(mut points: List[LoftSample], center: Vector3, r: Float32):
    """Append one round lone station."""
    points.append(LoftSample(center, r, r, r, False))


def _append_hip_bone(
    mut points: List[LoftSample], shape: HipBoneShape, mirror: Bool
):
    """Append a hip bone's capsules, its wing plates' edges and its cup."""
    for index in range(len(shape.capsules)):
        var capsule = shape.capsules[index]
        _append_segment(
            points,
            _placed(capsule.a, mirror),
            capsule.ra,
            _placed(capsule.b, mirror),
            capsule.rb,
        )
    # The fan's blades share their edges, and the hub lies inside the
    # bone, so the rim edges carry the wing's outline.
    for index in range(len(shape.plates)):
        var plate = shape.plates[index]
        _append_segment(
            points,
            _placed(plate.b, mirror),
            shape.thin,
            _placed(plate.c, mirror),
            shape.thin,
        )
    _append_sphere(points, _placed(shape.hub, mirror), shape.thick)
    _append_sphere(points, _placed(shape.hip, mirror), shape.cup)
    var t = shape.tuberosity_r
    points.append(
        LoftSample(_placed(shape.tuberosity, mirror), t.x, t.z, t.y, False)
    )


def _append_sacrum(mut points: List[LoftSample], shape: SacrumShape):
    """Append the sacrum's five elliptical stations as one chain."""
    points.append(LoftSample(shape.c0, shape.ml0, shape.ap0, 0, False))
    points.append(LoftSample(shape.c1, shape.ml1, shape.ap1, 0, True))
    points.append(LoftSample(shape.c2, shape.ml2, shape.ap2, 0, True))
    points.append(LoftSample(shape.c3, shape.ml3, shape.ap3, 0, True))
    points.append(LoftSample(shape.c4, shape.ml4, shape.ap4, 0, True))


def _append_chain(mut points: List[LoftSample], c: PelvisChain, mirror: Bool):
    """Append one muscle chain's five stations and their midpoints."""
    var first = len(points)
    _append_station(points, c.p0, c.ml0, c.ap0, c.p1, c.ml1, c.ap1, mirror)
    _append_station(points, c.p1, c.ml1, c.ap1, c.p2, c.ml2, c.ap2, mirror)
    _append_station(points, c.p2, c.ml2, c.ap2, c.p3, c.ml3, c.ap3, mirror)
    _append_station(points, c.p3, c.ml3, c.ap3, c.p4, c.ml4, c.ap4, mirror)
    points.append(LoftSample(_placed(c.p4, mirror), c.ml4, c.ap4, 0, True))
    points[first].joins = False


def _append_station(
    mut points: List[LoftSample],
    a: Vector3,
    aml: Float32,
    aap: Float32,
    b: Vector3,
    bml: Float32,
    bap: Float32,
    mirror: Bool,
):
    """Append one station and the midpoint to the next."""
    points.append(LoftSample(_placed(a, mirror), aml, aap, 0, True))
    points.append(
        LoftSample(
            _placed(mix_point(a, b, 0.5), mirror),
            0.5 * (aml + bml),
            0.5 * (aap + bap),
            0,
            True,
        )
    )


def _append_chains(
    mut points: List[LoftSample], field: PelvisMuscleField, mirror: Bool
):
    """Append every chain of one right-side muscle field."""
    var set = field.chains
    _append_chain(points, set.c0, mirror)
    if set.count >= 2:
        _append_chain(points, set.c1, mirror)
    if set.count >= 3:
        _append_chain(points, set.c2, mirror)


def _append_leg(
    mut points: List[LoftSample],
    spec: HumanoidSpec,
    side: BodySide,
    origin: Vector3,
) raises:
    """Append the top of one leg: its femur and the muscles over the hip.

    `origin` places the leg frame in the pelvis frame.
    """
    var legs = muscle_dimensions(spec, side)
    var femur_dims = femur_dimensions(spec.stature, spec.sex, side)
    var knee = knee_dimensions_from_bones(
        femur_dims,
        tibia_dimensions(spec.stature, spec.sex, side),
        fibula_dimensions(spec.stature, spec.sex, side),
        patella_dimensions(spec.stature, spec.sex, side),
    )
    var femur = FemurField(femur_dims)
    var at = origin + femur_origin(femur_dims, knee.femoral_thickness)
    _append_sphere(points, femur.head_center + at, femur.head_r)
    var gt = femur.gt_r
    points.append(LoftSample(femur.gt + at, gt.x, gt.z, gt.y, False))
    points.append(LoftSample(femur.s4 + at, femur.ml4, femur.ap4, 0, False))
    points.append(LoftSample(femur.s3 + at, femur.ml3, femur.ap3, 0, True))
    points.append(LoftSample(femur.s2 + at, femur.ml2, femur.ap2, 0, True))
    var parts = List[MusclePart]()
    parts.append(GLUTEUS_MAXIMUS)
    parts.append(GLUTEUS_MEDIUS)
    parts.append(TENSOR_FASCIAE_LATAE)
    parts.append(ILIOTIBIAL_TRACT)
    parts.append(SARTORIUS)
    parts.append(RECTUS_FEMORIS)
    parts.append(VASTUS_LATERALIS)
    parts.append(VASTUS_MEDIALIS)
    parts.append(VASTUS_INTERMEDIUS)
    parts.append(PECTINEUS)
    parts.append(ADDUCTOR_LONGUS)
    parts.append(ADDUCTOR_MAGNUS)
    parts.append(GRACILIS)
    parts.append(BICEPS_FEMORIS)
    parts.append(SEMITENDINOSUS)
    parts.append(SEMIMEMBRANOSUS)
    for index in range(len(parts)):
        var m = MuscleField(legs, parts[index])
        var first = len(points)
        _append_leg_station(
            points, m.p0 + origin, m.r0, m.a0, m.p1 + origin, m.r1, m.a1
        )
        _append_leg_station(
            points, m.p1 + origin, m.r1, m.a1, m.p2 + origin, m.r2, m.a2
        )
        _append_leg_station(
            points, m.p2 + origin, m.r2, m.a2, m.p3 + origin, m.r3, m.a3
        )
        _append_leg_station(
            points, m.p3 + origin, m.r3, m.a3, m.p4 + origin, m.r4, m.a4
        )
        points.append(LoftSample(m.p4 + origin, m.r4, m.a4, 0, True))
        points[first].joins = False
    var nodes = LymphField(legs, INGUINAL_NODES)
    _append_sphere(points, nodes.c0 + origin, nodes.n0)
    _append_sphere(points, nodes.c1 + origin, nodes.n1)
    _append_sphere(points, nodes.c2 + origin, nodes.n2)
    _append_sphere(points, nodes.c3 + origin, nodes.n3)
    _append_sphere(points, nodes.c4 + origin, nodes.n4)


def _append_leg_station(
    mut points: List[LoftSample],
    a: Vector3,
    aml: Float32,
    aap: Float32,
    b: Vector3,
    bml: Float32,
    bap: Float32,
):
    """Append one leg muscle station and the midpoint to the next."""
    _append_station(points, a, aml, aap, b, bml, bap, False)
