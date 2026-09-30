# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Skin envelope derived from the modeled anatomy of the torso.

Transverse sections run from below the waist to the top of the chest.
Each one slices the vertebrae, the ribs, the sternum, the costal
cartilages and the torso's muscles on both sides, closes the outline as
a convex hull, and adds the subcutaneous fat and the dermis. See
`extensions.humanoid.skeleton.loft`. The fat is thicker over the
abdomen than over the chest. A female template carries breast tissue
over the pectoralis major. A separate shell represents the dermis for
occupancy and mass.

The sections slice the shoulder girdle too, so the skin covers the
clavicles, the scapulae and the acromia. It leaves out where the
pectoralis major and the latissimus dorsi reach the humerus: the arm's
own skin covers the armpit's folds there. The neck is not modeled, so
the skin ends in a cut at the base of the neck.

    var dims = torso_muscle_dimensions(person)
    var d = torso_skin_distance(dims, Vector3(0, 0.3, 0.15))
"""

from extensions.humanoid.sex import MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.skeleton.field import (
    DistanceField,
    field_gradient,
    flip_x,
    mix_point,
    smin,
)
from extensions.humanoid.skeleton.loft import (
    AXIS_Y,
    Loft,
    LoftSample,
    fit_loft,
    loft_distance,
)
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    is_paired_bone,
    named_torso_bones,
    shoulder_girdle,
    torso_bone_field,
)
from extensions.humanoid.skeleton.torso.ligaments.dimensions import (
    COSTAL_CARTILAGES,
    torso_ligament_field,
)
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    TorsoMuscleDimensions,
    is_paired_muscle,
    named_torso_muscles,
    torso_muscle_field,
)
from extensions.humanoid.skeleton.sculpt import Sculpt
from extensions.humanoid.skeleton.torso.sweep import SweepField
from math.vector3 import Vector3
from std.math import max, min

# Sections from below the waist to the top of the chest: about nine
# millimeters apart on a six-foot torso.
comptime TORSO_SKIN_SECTIONS = 50
# Subcutaneous fat over the abdomen and over the chest, in meters.
# Authored adult template values.
comptime MALE_BELLY_FAT = Float32(0.0140)
comptime MALE_CHEST_FAT = Float32(0.0080)
comptime FEMALE_BELLY_FAT = Float32(0.0240)
comptime FEMALE_CHEST_FAT = Float32(0.0150)
comptime TORSO_DERMIS = Float32(0.0018)
# A female template's breast, in template centimeters: its center, its
# semi-axes across, up and forward, how far it turns out and down, and
# the fold where it meets the chest.
comptime BREAST_X = Float32(10.0)
comptime BREAST_Y = Float32(37.5)
comptime BREAST_Z = Float32(10.8)
comptime BREAST_ACROSS = Float32(6.4)
comptime BREAST_TALL = Float32(6.0)
comptime BREAST_DEEP = Float32(5.6)
comptime BREAST_TURN = Float32(0.25)
comptime BREAST_DROOP = Float32(0.15)
comptime BREAST_FOLD = Float32(2.5)


struct TorsoSkinField(Copyable, DistanceField, Movable):
    """The outer skin surface around the modeled torso anatomy."""

    var belly: Float32
    var chest: Float32
    var dermis: Float32
    var loft: Loft
    # A female template's breasts, each its own form over the
    # pectoralis major, and the fold where they meet the chest. A
    # male template's is empty.
    var breasts: Sculpt
    var breast_fold: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: TorsoMuscleDimensions) raises:
        """Build skin around the actual modeled structures.

        Args:
            dimensions: Torso landmarks and the muscles' radius scale.

        Raises:
            Error: If any underlying anatomical field refuses its inputs.
        """
        dimensions.validate()
        var t = dimensions.torso.copy()
        var f = t.frame
        self.belly = torso_fat(t.sex, True)
        self.chest = torso_fat(t.sex, False)
        self.dermis = TORSO_DERMIS
        self.epsilon = f.cm(0.15)
        var points = List[LoftSample]()
        # A station lateral of and below this corner belongs to the
        # arm's skin: where the chest's muscles reach the humerus.
        var g = shoulder_girdle(t)
        var arm = Vector3(g.shoulder.x - f.cm(2.3), g.shoulder.y - f.cm(1.0), 0)
        var bones = named_torso_bones()
        for index in range(len(bones)):  # pragma: no branch
            _append_field(points, torso_bone_field(t, bones[index], RIGHT))
            if is_paired_bone(bones[index]):
                _append_field(points, torso_bone_field(t, bones[index], LEFT))
        _append_field(points, torso_ligament_field(t, COSTAL_CARTILAGES, RIGHT))
        _append_field(points, torso_ligament_field(t, COSTAL_CARTILAGES, LEFT))
        var muscles = named_torso_muscles()
        for index in range(len(muscles)):  # pragma: no branch
            var part = muscles[index]
            _append_field(
                points, torso_muscle_field(dimensions, part, RIGHT), arm
            )
            if is_paired_muscle(part):
                _append_field(
                    points, torso_muscle_field(dimensions, part, LEFT), arm
                )
        # A section's outline is one closed curve around its center, so
        # it cannot dip between two breasts: they are forms of their
        # own, each turned a little out and down, as they sit.
        self.breasts = Sculpt(f.cm(1.0), f.cm(0.5))
        self.breast_fold = f.cm(BREAST_FOLD)
        if t.sex != MALE:
            var center = f.at(BREAST_X, BREAST_Y, BREAST_Z)
            var radii = Vector3(
                f.cm(BREAST_ACROSS) * f.wide,
                f.cm(BREAST_TALL),
                f.cm(BREAST_DEEP),
            )
            var facing = Vector3(BREAST_TURN, -BREAST_DROOP, 1)
            facing.normalize()
            self.breasts.ellipsoid(center, radii, facing)
            self.breasts.ellipsoid(flip_x(center), radii, flip_x(facing))
        var bottom = f.at(0, 10.0, 0).y
        var top = f.at(0, 53.5, 0).y
        var waist = f.at(0, 30.0, 0).y
        var ribs = f.at(0, 36.0, 0).y
        var covers = List[Float32]()
        var spacing = (top - bottom) / Float32(TORSO_SKIN_SECTIONS - 1)
        for section in range(TORSO_SKIN_SECTIONS):  # pragma: no branch
            var y = bottom + spacing * Float32(section)
            var t_up = min(max((y - waist) / (ribs - waist), 0), 1)
            covers.append(
                self.belly + (self.chest - self.belly) * t_up + self.dermis
            )
        # Ten passes bridge the dips between the ribs, which skin and
        # fat span, so the chest reads smooth. Then eight passes round
        # off each section that stands proud, so the skin shows no
        # bands where it turns.
        self.loft = fit_loft(
            points, AXIS_Y, bottom, top, TORSO_SKIN_SECTIONS, covers, 10, 8
        )
        self.low = self.loft.low
        self.high = self.loft.high
        if len(self.breasts.pieces) > 0:
            self.high.z = max(self.high.z, self.breasts.high.z)

    def distance(self, point: Vector3) -> Float32:
        """Return distance to the anatomy-derived outer surface.

        Negative is inside. Zero is the surface.
        """
        return smin(
            loft_distance(self.loft, point),
            self.breasts.distance(point),
            self.breast_fold,
        )

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)


struct TorsoSkinLayerField(Copyable, DistanceField, Movable):
    """The dermal shell immediately inside a `TorsoSkinField`."""

    var outer: TorsoSkinField
    var thickness: Float32
    var low: Vector3
    var high: Vector3

    def __init__(out self, dimensions: TorsoMuscleDimensions) raises:
        """Build the dermal shell around the modeled anatomy.

        Args:
            dimensions: Torso landmarks and the muscles' radius scale.

        Raises:
            Error: If the outer field refuses an anatomical input.
        """
        self.outer = TorsoSkinField(dimensions)
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


def torso_fat(sex: Sex, belly: Bool) -> Float32:
    """Return the subcutaneous fat over the torso, in meters.

    Args:
        sex: `MALE` or `FEMALE`. Any other value gets the female cover.
        belly: True for the abdomen, False for the chest.

    Returns:
        The authored template thickness.
    """
    if sex == MALE:
        if belly:
            return MALE_BELLY_FAT
        return MALE_CHEST_FAT
    if belly:
        return FEMALE_BELLY_FAT
    return FEMALE_CHEST_FAT


def torso_skin_distance(
    dimensions: TorsoMuscleDimensions, point: Vector3
) raises -> Float32:
    """Return how far `point` lies outside the torso's skin, in meters.

    Negative is inside.

    Args:
        dimensions: Landmarks from `torso_muscle_dimensions`.
        point: A point in the pelvis frame, in meters.

    Returns:
        The signed distance, in meters.

    Raises:
        Error: If `dimensions.validate` refuses the copy.
    """
    return TorsoSkinField(dimensions).distance(point)


def _append_field(
    mut points: List[LoftSample],
    field: SweepField,
    arm: Vector3 = Vector3(1.0e9, -1.0e9, 0),
):
    """Append every station of a field's sweeps, placed on its side.

    A sheet that lies thin across the body wall is sliced as a round
    section of its thickness; its breadth comes from the run of its
    stations. A station farther from the midline than `arm.x` and lower
    than `arm.y` is left out: it lies under the arm's skin.
    """
    for s in range(len(field.sweeps)):  # pragma: no branch
        var sweep = field.sweeps[s].copy()
        var flat = sweep.hint.z > 0.5
        # The first station kept starts a run; each later one joins it.
        var started = False
        for index in range(len(sweep.stations)):  # pragma: no branch
            var station = sweep.stations[index]
            var p = station.p
            if p.x > arm.x and p.y < arm.y:
                continue
            if field.mirror:
                p = flip_x(p)
            var ml = station.ml
            var ap = station.ap
            if flat:
                ap = station.ml
            points.append(LoftSample(p, ml, ap, 0, started))
            started = True
            if index + 1 < len(sweep.stations):
                var next = sweep.stations[index + 1]
                var q = next.p
                if q.x > arm.x and q.y < arm.y:
                    continue
                if field.mirror:
                    q = flip_x(q)
                var next_ap = next.ap
                if flat:
                    next_ap = next.ml
                points.append(
                    LoftSample(
                        mix_point(p, q, 0.5),
                        0.5 * (ml + next.ml),
                        0.5 * (ap + next_ap),
                        0,
                        True,
                    )
                )
