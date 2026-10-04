# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Canonical lower-limb component catalog and bounded pair batches.

This tool uses physical fields, never display-radius helpers. Stable component
identities include the region, typed part family and its declared enum value.
Aliases do not add a second component. All fields share the knee origin.
"""

from extensions.humanoid.side import BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.limb.diagnostics import (
    diagnose_pair,
    _check_bounds,
)
from extensions.humanoid.skeleton.limb.sampling import (
    SampleGrid,
    MAX_SAMPLE_CELLS,
)
from extensions.humanoid.skeleton.occupancy import check_mass_step
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    foot_muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.knee.dimensions import (
    MEDIAL_MENISCUS,
    LATERAL_MENISCUS,
    MEDIAL_COLLATERAL,
    LATERAL_COLLATERAL,
)
from math.vector3 import Vector3
from loaders.json import quote_json
from std.math import max, min
from std.utils import Variant
from units.si import Length
from extensions.humanoid.skeleton.leg.femur.dimensions import FemurField
from extensions.humanoid.skeleton.leg.tibia.dimensions import TibiaField
from extensions.humanoid.skeleton.leg.fibula.dimensions import FibulaField
from extensions.humanoid.skeleton.leg.patella.dimensions import PatellaField
from extensions.humanoid.skeleton.leg.knee.dimensions import CartilageField
from extensions.humanoid.skeleton.leg.knee.dimensions import MeniscusField
from extensions.humanoid.skeleton.leg.knee.dimensions import CollateralField
from extensions.humanoid.skeleton.foot.bones.dimensions import FootBoneField
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    named_foot_bones,
    bone_part_label as _foot_bone_label,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import MuscleField
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    named_muscle_parts,
    muscle_part_label as _leg_muscle_label,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import FootMuscleField
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    named_foot_muscles,
    foot_muscle_part_label as _foot_muscle_label,
)
from extensions.humanoid.skeleton.foot.ligaments.dimensions import (
    FootLigamentField,
)
from extensions.humanoid.skeleton.foot.ligaments.dimensions import (
    named_foot_ligaments,
    ligament_part_label as _foot_ligament_label,
)
from extensions.humanoid.skeleton.leg.vessels.dimensions import VesselField
from extensions.humanoid.skeleton.leg.vessels.dimensions import (
    named_vessel_parts,
    vessel_part_label as _leg_vessel_label,
)
from extensions.humanoid.skeleton.foot.vessels.dimensions import FootVesselField
from extensions.humanoid.skeleton.foot.vessels.dimensions import (
    named_foot_vessels,
    vessel_part_label as _foot_vessel_label,
)
from extensions.humanoid.skeleton.leg.nerves.dimensions import NerveField
from extensions.humanoid.skeleton.leg.nerves.dimensions import (
    named_nerve_parts,
    nerve_part_label as _leg_nerve_label,
)
from extensions.humanoid.skeleton.foot.nerves.dimensions import FootNerveField
from extensions.humanoid.skeleton.foot.nerves.dimensions import (
    named_foot_nerves,
    nerve_part_label as _foot_nerve_label,
)
from extensions.humanoid.skeleton.leg.lymph.dimensions import LymphField
from extensions.humanoid.skeleton.leg.lymph.dimensions import (
    named_lymph_parts,
    lymph_part_label as _leg_lymph_label,
)
from extensions.humanoid.skeleton.foot.lymph.dimensions import FootLymphField
from extensions.humanoid.skeleton.foot.lymph.dimensions import (
    named_foot_lymph,
    lymph_part_label as _foot_lymph_label,
)

comptime _Solid = Variant[
    FemurField,
    TibiaField,
    FibulaField,
    PatellaField,
    CartilageField,
    MeniscusField,
    CollateralField,
    FootBoneField,
    MuscleField,
    FootMuscleField,
    FootLigamentField,
    VesselField,
    FootVesselField,
    NerveField,
    FootNerveField,
    LymphField,
    FootLymphField,
]


struct _Component(Copyable, DistanceField, Movable):
    """One canonical field with a translation into the common leg frame."""

    var solid: _Solid
    var origin: Vector3
    var low: Vector3
    var high: Vector3
    var identity: String
    var label: String
    var family: String

    def __init__[
        F: DistanceField
    ](
        out self,
        field: F,
        origin: Vector3,
        low: Vector3,
        high: Vector3,
        identity: String,
        label: String,
        family: String,
    ) raises:
        self.solid = _Solid(field.copy())
        self.origin = origin
        self.low = low + origin
        self.high = high + origin
        _check_bounds(self.low, self.high)
        self.identity = identity
        self.label = label
        self.family = family

    def distance(self, point: Vector3) -> Float32:
        var p = point - self.origin
        if self.solid.isa[FemurField]():
            return self.solid[FemurField].distance(p)
        if self.solid.isa[TibiaField]():
            return self.solid[TibiaField].distance(p)
        if self.solid.isa[FibulaField]():
            return self.solid[FibulaField].distance(p)
        if self.solid.isa[PatellaField]():
            return self.solid[PatellaField].distance(p)
        if self.solid.isa[CartilageField]():
            return self.solid[CartilageField].distance(p)
        if self.solid.isa[MeniscusField]():
            return self.solid[MeniscusField].distance(p)
        if self.solid.isa[CollateralField]():
            return self.solid[CollateralField].distance(p)
        if self.solid.isa[FootBoneField]():
            return self.solid[FootBoneField].distance(p)
        if self.solid.isa[MuscleField]():
            return self.solid[MuscleField].distance(p)
        if self.solid.isa[FootMuscleField]():
            return self.solid[FootMuscleField].distance(p)
        if self.solid.isa[FootLigamentField]():
            return self.solid[FootLigamentField].distance(p)
        if self.solid.isa[VesselField]():
            return self.solid[VesselField].distance(p)
        if self.solid.isa[FootVesselField]():
            return self.solid[FootVesselField].distance(p)
        if self.solid.isa[NerveField]():
            return self.solid[NerveField].distance(p)
        if self.solid.isa[FootNerveField]():
            return self.solid[FootNerveField].distance(p)
        if self.solid.isa[LymphField]():
            return self.solid[LymphField].distance(p)
        return self.solid[FootLymphField].distance(p)


def _components(spec: HumanoidSpec, side: BodySide) raises -> List[_Component]:
    var pose = assemble_leg(spec, side)
    var fm = foot_muscle_dimensions(spec, side)
    var foot = fm.foot
    var ankle = pose.ankle_center()
    var zero = Vector3(0, 0, 0)
    var parts = List[_Component]()
    var femur = FemurField(pose.femur)
    parts.append(
        _Component(
            femur,
            pose.femur_origin,
            femur.low,
            femur.high,
            "leg/bone/femur",
            "femur",
            "bone",
        )
    )
    var tibia = TibiaField(pose.tibia)
    parts.append(
        _Component(
            tibia,
            pose.tibia_origin,
            tibia.low,
            tibia.high,
            "leg/bone/tibia",
            "tibia",
            "bone",
        )
    )
    var fibula = FibulaField(pose.fibula)
    parts.append(
        _Component(
            fibula,
            pose.fibula_origin,
            fibula.low,
            fibula.high,
            "leg/bone/fibula",
            "fibula",
            "bone",
        )
    )
    var patella = PatellaField(pose.patella)
    parts.append(
        _Component(
            patella,
            pose.patella_origin,
            patella.low,
            patella.high,
            "leg/bone/patella",
            "patella",
            "bone",
        )
    )
    var cartilage = CartilageField(pose.knee)
    parts.append(
        _Component(
            cartilage,
            zero,
            cartilage.low,
            cartilage.high,
            "leg/knee/cartilage",
            "knee/cartilage",
            "knee",
        )
    )
    var medial = MeniscusField(pose.knee, MEDIAL_MENISCUS)
    parts.append(
        _Component(
            medial,
            zero,
            medial.low,
            medial.high,
            "leg/knee/medial",
            "knee/medial",
            "knee",
        )
    )
    var lateral = MeniscusField(pose.knee, LATERAL_MENISCUS)
    parts.append(
        _Component(
            lateral,
            zero,
            lateral.low,
            lateral.high,
            "leg/knee/lateral",
            "knee/lateral",
            "knee",
        )
    )
    var mcl = CollateralField(pose.knee, MEDIAL_COLLATERAL)
    parts.append(
        _Component(
            mcl, zero, mcl.low, mcl.high, "leg/knee/mcl", "knee/mcl", "knee"
        )
    )
    var lcl = CollateralField(pose.knee, LATERAL_COLLATERAL)
    parts.append(
        _Component(
            lcl, zero, lcl.low, lcl.high, "leg/knee/lcl", "knee/lcl", "knee"
        )
    )
    for part in named_foot_bones():
        var field = FootBoneField(foot, part)
        parts.append(
            _Component(
                field,
                ankle,
                field.low,
                field.high,
                "foot/bone/" + String(part.value),
                "foot/" + _foot_bone_label(part),
                "bone",
            )
        )
    for part in named_muscle_parts():
        var field = MuscleField(pose.muscles, part)
        parts.append(
            _Component(
                field,
                zero,
                field.low,
                field.high,
                "leg/muscle/" + String(part.value),
                "leg/muscle/" + _leg_muscle_label(part),
                "muscle",
            )
        )
    for part in named_foot_muscles():
        var field = FootMuscleField(fm, part)
        parts.append(
            _Component(
                field,
                ankle,
                field.low,
                field.high,
                "foot/muscle/" + String(part.value),
                "foot/muscle/" + _foot_muscle_label(part),
                "muscle",
            )
        )
    for part in named_foot_ligaments():
        var field = FootLigamentField(foot, part)
        parts.append(
            _Component(
                field,
                ankle,
                field.low,
                field.high,
                "foot/ligament/" + String(part.value),
                "foot/ligament/" + _foot_ligament_label(part),
                "ligament",
            )
        )
    for part in named_vessel_parts():
        var field = VesselField(pose.muscles, part)
        parts.append(
            _Component(
                field,
                zero,
                field.low,
                field.high,
                "leg/vascular/" + String(part.value),
                "leg/vascular/" + _leg_vessel_label(part),
                "vascular",
            )
        )
    for part in named_foot_vessels():
        var field = FootVesselField(foot, part)
        parts.append(
            _Component(
                field,
                ankle,
                field.low,
                field.high,
                "foot/vascular/" + String(part.value),
                "foot/vascular/" + _foot_vessel_label(part),
                "vascular",
            )
        )
    for part in named_nerve_parts():
        var field = NerveField(pose.muscles, part)
        parts.append(
            _Component(
                field,
                zero,
                field.low,
                field.high,
                "leg/nerve/" + String(part.value),
                "leg/nerve/" + _leg_nerve_label(part),
                "nerve",
            )
        )
    for part in named_foot_nerves():
        var field = FootNerveField(foot, part)
        parts.append(
            _Component(
                field,
                ankle,
                field.low,
                field.high,
                "foot/nerve/" + String(part.value),
                "foot/nerve/" + _foot_nerve_label(part),
                "nerve",
            )
        )
    for part in named_lymph_parts():
        var field = LymphField(pose.muscles, part)
        parts.append(
            _Component(
                field,
                zero,
                field.low,
                field.high,
                "leg/lymphatic/" + String(part.value),
                "leg/lymphatic/" + _leg_lymph_label(part),
                "lymphatic",
            )
        )
    for part in named_foot_lymph():
        var field = FootLymphField(foot, part)
        parts.append(
            _Component(
                field,
                ankle,
                field.low,
                field.high,
                "foot/lymphatic/" + String(part.value),
                "foot/lymphatic/" + _foot_lymph_label(part),
                "lymphatic",
            )
        )
    return parts^


def _vec(point: Vector3) -> String:
    return (
        "["
        + String(point.x)
        + ","
        + String(point.y)
        + ","
        + String(point.z)
        + "]"
    )


def _catalog(parts: List[_Component]):
    for i in range(len(parts)):
        print(
            '{"record":"component","index":'
            + String(i)
            + ',"component_id":'
            + quote_json(parts[i].identity)
            + ',"label":'
            + quote_json(parts[i].label)
            + ',"family":'
            + quote_json(parts[i].family)
            + ',"low_m":'
            + _vec(parts[i].low)
            + ',"high_m":'
            + _vec(parts[i].high)
            + ',"translation_m":'
            + _vec(parts[i].origin)
            + "}"
        )


def _work(first: _Component, second: _Component, step: Length) raises -> Int:
    # Preflight only. diagnose_pair remains the sole occupancy sampler.
    _check_bounds(first.low, first.high)
    _check_bounds(second.low, second.high)
    var low = Vector3(
        max(first.low.x, second.low.x),
        max(first.low.y, second.low.y),
        max(first.low.z, second.low.z),
    )
    var high = Vector3(
        min(first.high.x, second.high.x),
        min(first.high.y, second.high.y),
        min(first.high.z, second.high.z),
    )
    if low.x >= high.x or low.y >= high.y or low.z >= high.z:
        return 0
    var grid = SampleGrid(low, high, step)
    return grid.nx * grid.ny * grid.nz


def _batch(parts: List[_Component], request: String, step: Length) raises:
    # A batch is first-index:second-start:second-stop (exclusive).
    # Check the whole request and work before evaluating either field.
    check_mass_step(step, "canonical pair batch")
    var tokens = request.split(":")
    if len(tokens) != 3:
        raise Error("A pair batch needs first:second_start:second_stop")
    var first = Int(String(tokens[0]))
    var start = Int(String(tokens[1]))
    var stop = Int(String(tokens[2]))
    if (
        first < 0
        or first >= len(parts)
        or start <= first
        or stop <= start
        or stop > len(parts)
    ):
        raise Error("A pair batch must name ordered catalog indices")
    var work = 0
    for second in range(start, stop):
        work += _work(parts[first], parts[second], step)
        if work > MAX_SAMPLE_CELLS:
            raise Error("A pair batch exceeds the two-million-cell work limit")
    for second in range(start, stop):
        var a = parts[first].copy()
        var b = parts[second].copy()
        var d = diagnose_pair(a, a.low, a.high, b, b.low, b.high, step)
        print(
            '{"record":"pair","first_id":'
            + quote_json(a.identity)
            + ',"second_id":'
            + quote_json(b.identity)
            + ',"first":'
            + quote_json(a.label)
            + ',"second":'
            + quote_json(b.label)
            + ',"bounds_gap_m":'
            + String(d.bounds_gap.value)
            + ',"samples":'
            + String(d.samples)
            + ',"overlap_samples":'
            + String(d.overlap_samples)
            + ',"overlap_volume_m3":'
            + String(d.overlap_volume.value)
            + ',"signed_field_witness_m":'
            + String(d.field_witness.value)
            + "}"
        )


def _pair_probe(
    spec: HumanoidSpec, side: BodySide, request: String, step: Length
) raises:
    var parts = _components(spec, side)
    if request == "catalog":
        _catalog(parts)
    else:
        _batch(parts, request, step)
