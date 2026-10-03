# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Emit bounded canonical evidence as JSON Lines; no validation claim."""

from extensions.humanoid.athleticism import TONED, UNTONED
from extensions.humanoid.sex import MALE, FEMALE
from extensions.humanoid.side import RIGHT, LEFT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.field import DistanceField
from extensions.humanoid.skeleton.occupancy import check_mass_step
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.leg.femur.dimensions import FemurField
from extensions.humanoid.skeleton.leg.tibia.dimensions import TibiaField
from extensions.humanoid.skeleton.leg.fibula.dimensions import FibulaField
from extensions.humanoid.skeleton.leg.patella.dimensions import PatellaField
from extensions.humanoid.skeleton.leg.knee.dimensions import (
    CartilageField,
    MeniscusField,
    CollateralField,
    MEDIAL_MENISCUS,
    LATERAL_MENISCUS,
    MEDIAL_COLLATERAL,
    LATERAL_COLLATERAL,
)
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    FootBoneField,
    foot_dimensions,
    named_foot_bones,
    bone_part_label,
)
from extensions.humanoid.skeleton.limb.inertia import (
    segment_estimate,
    THIGH,
    SHANK,
    FOOT_SEGMENT,
)
from extensions.humanoid.skeleton.limb.regions import LimbRegion, region_label
from extensions.humanoid.skeleton.limb.diagnostics import diagnose_pair
from extensions.humanoid.skeleton.head.frame import head_dimensions
from extensions.humanoid.skeleton.head.bones.dimensions import (
    HeadBone,
    head_bone_field,
)
from extensions.humanoid.skeleton.head.ligaments.dimensions import (
    CERVICAL_DISCS,
    head_ligament_field,
)
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    TorsoBone,
    torso_bone_field,
)
from extensions.humanoid.skeleton.torso.ligaments.dimensions import (
    INTERVERTEBRAL_DISCS,
    torso_ligament_field,
)
from extensions.humanoid.skeleton.torso.sweep import Sweep
from loaders.json import quote_json
from math.vector3 import Vector3
from std.math import min, max
from std.sys import argv
from units.si import Length, MILLIMETER
from tests.test_anatomy_accounting import (
    test_named_regions_and_marrow_override_overlapping_soft_tissue,
    test_grid_rejects_non_finite_and_unbounded_work_before_counts,
    test_cuboid_and_arbitrary_cut_composition_are_exact_at_three_steps,
    test_independent_point_masses_rigid_transform_and_parallel_axis,
)
from tests.test_anatomy_dimension_guards import (
    test_spine_sizes_reject_nan_and_both_infinities,
    test_all_editable_frame_values_have_finite_guards,
    test_morph_guards_do_not_impose_an_unmeasured_biological_range,
)
from tests.test_anatomy_diagnostics import (
    test_pair_exact_boxes_and_no_hit_limit,
    test_bad_diagnostic_requests_and_field_values_fail,
)


@fieldwise_init
struct _PlacedFemur(DistanceField, ImplicitlyCopyable):
    var field: FemurField
    var origin: Vector3

    def distance(self, p: Vector3) -> Float32:
        return self.field.distance(p - self.origin)


@fieldwise_init
struct _PlacedTibia(DistanceField, ImplicitlyCopyable):
    var field: TibiaField
    var origin: Vector3

    def distance(self, p: Vector3) -> Float32:
        return self.field.distance(p - self.origin)


@fieldwise_init
struct _PlacedFibula(DistanceField, ImplicitlyCopyable):
    var field: FibulaField
    var origin: Vector3

    def distance(self, p: Vector3) -> Float32:
        return self.field.distance(p - self.origin)


@fieldwise_init
struct _PlacedPatella(DistanceField, ImplicitlyCopyable):
    var field: PatellaField
    var origin: Vector3

    def distance(self, p: Vector3) -> Float32:
        return self.field.distance(p - self.origin)


@fieldwise_init
struct _PlacedFootBone(DistanceField, ImplicitlyCopyable):
    var field: FootBoneField
    var origin: Vector3

    def distance(self, p: Vector3) -> Float32:
        return self.field.distance(p - self.origin)


@fieldwise_init
struct _Disc(Copyable, DistanceField, Movable):
    var sweep: Sweep

    def distance(self, p: Vector3) -> Float32:
        return self.sweep.distance(p, 0)


def _vec(p: Vector3) -> String:
    return "[" + String(p.x) + "," + String(p.y) + "," + String(p.z) + "]"


def _pair[
    F: DistanceField, G: DistanceField
](
    a: F,
    alo: Vector3,
    ahi: Vector3,
    aname: String,
    b: G,
    blo: Vector3,
    bhi: Vector3,
    bname: String,
    step: Length,
) raises:
    var d = diagnose_pair(a, alo, ahi, b, blo, bhi, step)
    print(
        '{"record":"pair","first":'
        + quote_json(aname)
        + ',"second":'
        + quote_json(bname)
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


def _foot_pairs[
    F: DistanceField
](
    a: F,
    lo: Vector3,
    hi: Vector3,
    name: String,
    bones: List[FootBoneField],
    names: List[String],
    ankle: Vector3,
    step: Length,
) raises:
    for i in range(len(bones)):
        var b = _PlacedFootBone(bones[i], ankle)
        _pair(
            a,
            lo,
            hi,
            name,
            b,
            bones[i].low + ankle,
            bones[i].high + ankle,
            names[i],
            step,
        )


def main() raises:
    var args = argv()
    if len(args) != 8:
        raise Error(
            "Use anatomy_probe mode part step_mm stature_m male|female"
            " right|left untoned|toned"
        )
    var sex = MALE
    if args[5] == "female":
        sex = FEMALE
    elif args[5] != "male":
        raise Error("A probe sex must be male or female")
    var side = RIGHT
    if args[6] == "left":
        side = LEFT
    elif args[6] != "right":
        raise Error("A probe side must be right or left")
    var tone = UNTONED
    if args[7] == "toned":
        tone = TONED
    elif args[7] != "untoned":
        raise Error("A probe athleticism must be untoned or toned")
    var spec = HumanoidSpec(
        Length(Float32(Float64(String(args[4])))), sex, tone
    )
    var step = Length(Float32(Float64(String(args[3]))), MILLIMETER)
    check_mass_step(step, "validity probe")
    if args[1] == "controls":
        test_named_regions_and_marrow_override_overlapping_soft_tissue()
        test_grid_rejects_non_finite_and_unbounded_work_before_counts()
        test_cuboid_and_arbitrary_cut_composition_are_exact_at_three_steps()
        test_independent_point_masses_rigid_transform_and_parallel_axis()
        test_spine_sizes_reject_nan_and_both_infinities()
        test_all_editable_frame_values_have_finite_guards()
        test_morph_guards_do_not_impose_an_unmeasured_biological_range()
        test_pair_exact_boxes_and_no_hit_limit()
        test_bad_diagnostic_requests_and_field_values_fail()
        print(
            '{"record":"controls","passed":true,"checks":["three-step analytic'
            ' cuboid","unaligned-cut composition","two-point-mass full'
            ' tensor","rigid rotation and translation","full parallel-axis'
            ' identity","marrow assignment","finite editable'
            ' dimensions","bounded sampling work","analytic overlap'
            ' boxes"],"absolute_tolerances":{"cuboid_mass_kg":2e-8,"cuboid_center_m":2e-8,"cuboid_tensor_kg_m2":1e-10,"point_mass_tensor_kg_m2":1e-8,"rigid_center_m":2e-8,"overlap_volume_m3":1e-11}}'
        )
        return
    if args[1] == "segment":
        var part = THIGH
        if args[2] == "shank":
            part = SHANK
        elif args[2] == "foot":
            part = FOOT_SEGMENT
        elif args[2] != "thigh":
            raise Error("A probe segment must be thigh, shank or foot")
        var e = segment_estimate(spec, part, side, step)
        var v = e.inertia
        var regions = String("{")
        for i in range(7):
            if i > 0:
                regions += ","
            regions += (
                quote_json(region_label(LimbRegion(i)))
                + ':{"volume_m3":'
                + String(e.region_volumes[i])
                + ',"mass_kg":'
                + String(e.region_masses[i])
                + "}"
            )
        regions += "}"
        print(
            '{"record":"segment","segment":'
            + quote_json(String(args[2]))
            + ',"step_m":'
            + String(step.value)
            + ',"mass_kg":'
            + String(v.mass.value)
            + ',"center_m":'
            + _vec(v.center)
            + ',"inertia_kg_m2":['
            + String(v.xx.value)
            + ","
            + String(v.yy.value)
            + ","
            + String(v.zz.value)
            + ","
            + String(v.xy.value)
            + ","
            + String(v.xz.value)
            + ","
            + String(v.yz.value)
            + "]"
            + ',"length_m":'
            + String(v.length.value)
            + ',"low_m":'
            + _vec(e.low)
            + ',"high_m":'
            + _vec(e.high)
            + ',"regions":'
            + regions
            + "}"
        )
        return
    if args[1] == "spine":
        _spine(spec, step)
        return
    var pose = assemble_leg(spec, side)
    var f = FemurField(pose.femur)
    var pf = _PlacedFemur(f, pose.femur_origin)
    var flo = f.low + pose.femur_origin
    var fhi = f.high + pose.femur_origin
    var t = TibiaField(pose.tibia)
    var pt = _PlacedTibia(t, pose.tibia_origin)
    var tlo = t.low + pose.tibia_origin
    var thi = t.high + pose.tibia_origin
    var b = FibulaField(pose.fibula)
    var pb = _PlacedFibula(b, pose.fibula_origin)
    var blo = b.low + pose.fibula_origin
    var bhi = b.high + pose.fibula_origin
    var p = PatellaField(pose.patella)
    var pp = _PlacedPatella(p, pose.patella_origin)
    var plo = p.low + pose.patella_origin
    var phi = p.high + pose.patella_origin
    if args[1] == "bones":
        _pair(pf, flo, fhi, "femur", pt, tlo, thi, "tibia", step)
        _pair(pf, flo, fhi, "femur", pb, blo, bhi, "fibula", step)
        _pair(pf, flo, fhi, "femur", pp, plo, phi, "patella", step)
        _pair(pt, tlo, thi, "tibia", pb, blo, bhi, "fibula", step)
        _pair(pt, tlo, thi, "tibia", pp, plo, phi, "patella", step)
        _pair(pb, blo, bhi, "fibula", pp, plo, phi, "patella", step)
        var foot = foot_dimensions(spec.stature, spec.sex, side)
        var bones = List[FootBoneField]()
        var names = List[String]()
        for part in named_foot_bones():
            bones.append(FootBoneField(foot, part))
            names.append("foot/" + bone_part_label(part))
        var ankle = pose.ankle_center()
        _foot_pairs(pf, flo, fhi, "femur", bones, names, ankle, step)
        _foot_pairs(pt, tlo, thi, "tibia", bones, names, ankle, step)
        _foot_pairs(pb, blo, bhi, "fibula", bones, names, ankle, step)
        _foot_pairs(pp, plo, phi, "patella", bones, names, ankle, step)
        for i in range(len(bones)):
            for j in range(i + 1, len(bones)):
                var a = _PlacedFootBone(bones[i], ankle)
                var b = _PlacedFootBone(bones[j], ankle)
                _pair(
                    a,
                    bones[i].low + ankle,
                    bones[i].high + ankle,
                    names[i],
                    b,
                    bones[j].low + ankle,
                    bones[j].high + ankle,
                    names[j],
                    step,
                )
        return
    if args[1] == "knee":
        var cartilage = CartilageField(pose.knee)
        var medial = MeniscusField(pose.knee, MEDIAL_MENISCUS)
        var lateral = MeniscusField(pose.knee, LATERAL_MENISCUS)
        var mcl = CollateralField(pose.knee, MEDIAL_COLLATERAL)
        var lcl = CollateralField(pose.knee, LATERAL_COLLATERAL)
        _pair(
            pf,
            flo,
            fhi,
            "femur",
            cartilage,
            cartilage.low,
            cartilage.high,
            "knee/cartilage",
            step,
        )
        _pair(
            pf,
            flo,
            fhi,
            "femur",
            medial,
            medial.low,
            medial.high,
            "knee/medial",
            step,
        )
        _pair(
            pf,
            flo,
            fhi,
            "femur",
            lateral,
            lateral.low,
            lateral.high,
            "knee/lateral",
            step,
        )
        _pair(pf, flo, fhi, "femur", mcl, mcl.low, mcl.high, "knee/mcl", step)
        _pair(pf, flo, fhi, "femur", lcl, lcl.low, lcl.high, "knee/lcl", step)
        _pair(
            pt,
            tlo,
            thi,
            "tibia",
            cartilage,
            cartilage.low,
            cartilage.high,
            "knee/cartilage",
            step,
        )
        _pair(
            pt,
            tlo,
            thi,
            "tibia",
            medial,
            medial.low,
            medial.high,
            "knee/medial",
            step,
        )
        _pair(
            pt,
            tlo,
            thi,
            "tibia",
            lateral,
            lateral.low,
            lateral.high,
            "knee/lateral",
            step,
        )
        _pair(pt, tlo, thi, "tibia", mcl, mcl.low, mcl.high, "knee/mcl", step)
        _pair(pt, tlo, thi, "tibia", lcl, lcl.low, lcl.high, "knee/lcl", step)
        _pair(
            pb,
            blo,
            bhi,
            "fibula",
            cartilage,
            cartilage.low,
            cartilage.high,
            "knee/cartilage",
            step,
        )
        _pair(
            pb,
            blo,
            bhi,
            "fibula",
            medial,
            medial.low,
            medial.high,
            "knee/medial",
            step,
        )
        _pair(
            pb,
            blo,
            bhi,
            "fibula",
            lateral,
            lateral.low,
            lateral.high,
            "knee/lateral",
            step,
        )
        _pair(pb, blo, bhi, "fibula", mcl, mcl.low, mcl.high, "knee/mcl", step)
        _pair(pb, blo, bhi, "fibula", lcl, lcl.low, lcl.high, "knee/lcl", step)
        _pair(
            pp,
            plo,
            phi,
            "patella",
            cartilage,
            cartilage.low,
            cartilage.high,
            "knee/cartilage",
            step,
        )
        _pair(
            pp,
            plo,
            phi,
            "patella",
            medial,
            medial.low,
            medial.high,
            "knee/medial",
            step,
        )
        _pair(
            pp,
            plo,
            phi,
            "patella",
            lateral,
            lateral.low,
            lateral.high,
            "knee/lateral",
            step,
        )
        _pair(pp, plo, phi, "patella", mcl, mcl.low, mcl.high, "knee/mcl", step)
        _pair(pp, plo, phi, "patella", lcl, lcl.low, lcl.high, "knee/lcl", step)
        _pair(
            cartilage,
            cartilage.low,
            cartilage.high,
            "knee/cartilage",
            medial,
            medial.low,
            medial.high,
            "knee/medial",
            step,
        )
        _pair(
            cartilage,
            cartilage.low,
            cartilage.high,
            "knee/cartilage",
            lateral,
            lateral.low,
            lateral.high,
            "knee/lateral",
            step,
        )
        _pair(
            cartilage,
            cartilage.low,
            cartilage.high,
            "knee/cartilage",
            mcl,
            mcl.low,
            mcl.high,
            "knee/mcl",
            step,
        )
        _pair(
            cartilage,
            cartilage.low,
            cartilage.high,
            "knee/cartilage",
            lcl,
            lcl.low,
            lcl.high,
            "knee/lcl",
            step,
        )
        _pair(
            medial,
            medial.low,
            medial.high,
            "knee/medial",
            lateral,
            lateral.low,
            lateral.high,
            "knee/lateral",
            step,
        )
        _pair(
            medial,
            medial.low,
            medial.high,
            "knee/medial",
            mcl,
            mcl.low,
            mcl.high,
            "knee/mcl",
            step,
        )
        _pair(
            medial,
            medial.low,
            medial.high,
            "knee/medial",
            lcl,
            lcl.low,
            lcl.high,
            "knee/lcl",
            step,
        )
        _pair(
            lateral,
            lateral.low,
            lateral.high,
            "knee/lateral",
            mcl,
            mcl.low,
            mcl.high,
            "knee/mcl",
            step,
        )
        _pair(
            lateral,
            lateral.low,
            lateral.high,
            "knee/lateral",
            lcl,
            lcl.low,
            lcl.high,
            "knee/lcl",
            step,
        )
        _pair(
            mcl,
            mcl.low,
            mcl.high,
            "knee/mcl",
            lcl,
            lcl.low,
            lcl.high,
            "knee/lcl",
            step,
        )
        return
    raise Error("A probe mode must be controls, segment, bones, knee or spine")


def _disc_bounds(s: Sweep) -> Tuple[Vector3, Vector3]:
    var a = s.stations[0]
    var b = s.stations[1]
    return (
        Vector3(
            min(a.p.x - a.ml, b.p.x - b.ml),
            min(a.p.y, b.p.y),
            min(a.p.z - a.ap, b.p.z - b.ap),
        ),
        Vector3(
            max(a.p.x + a.ml, b.p.x + b.ml),
            max(a.p.y, b.p.y),
            max(a.p.z + a.ap, b.p.z + b.ap),
        ),
    )


def _endplane(
    name: String,
    body: Sweep,
    disc: Sweep,
    next_top: Float32,
    next_outside: Float32,
):
    var top = disc.stations[0].p
    var below = disc.stations[1].p
    var body_bottom = min(body.stations[0].p.y, body.stations[1].p.y)
    print(
        '{"record":"endplane","body":'
        + quote_json(name)
        + ',"disc_gap_m":'
        + String(top.y - below.y)
        + ',"body_disc_endplane_error_m":'
        + String(abs(top.y - body_bottom))
        + ',"next_body_disc_endplane_error_m":'
        + String(abs(below.y - next_top))
        + ',"body_outside_field_m":'
        + String(body.distance(top - Vector3(0, 0.0001, 0), 0))
        + ',"next_body_outside_field_m":'
        + String(next_outside)
        + ',"disc_outside_upper_field_m":'
        + String(disc.distance(top + Vector3(0, 0.0001, 0), 0))
        + ',"disc_outside_lower_field_m":'
        + String(disc.distance(below - Vector3(0, 0.0001, 0), 0))
        + "}"
    )


def _spine(spec: HumanoidSpec, step: Length) raises:
    var h = head_dimensions(spec.stature, spec.sex)
    var t = h.torso.copy()
    var discs = torso_ligament_field(t, INTERVERTEBRAL_DISCS, RIGHT)
    for i in range(17):
        var body = torso_bone_field(t, TorsoBone(i), RIGHT)
        var disc = discs.sweeps[i].copy()
        var d = _Disc(disc.copy())
        var lo, hi = _disc_bounds(disc)
        var name = "thoracolumbar/" + String(i)
        _pair(body, body.low, body.high, name, d, lo, hi, name + "/disc", step)
        var below = disc.stations[1].p
        if i < 16:
            var next = torso_bone_field(t, TorsoBone(i + 1), RIGHT)
            _pair(
                body,
                body.low,
                body.high,
                name,
                next,
                next.low,
                next.high,
                "thoracolumbar/" + String(i + 1),
                step,
            )
            _pair(
                next,
                next.low,
                next.high,
                "thoracolumbar/" + String(i + 1),
                d,
                lo,
                hi,
                name + "/disc",
                step,
            )
            _endplane(
                name,
                body.sweeps[0],
                disc,
                t.centers[i + 1].y + t.heights[i + 1] * 0.5,
                next.sweeps[0].distance(below + Vector3(0, 0.0001, 0), 0),
            )
        else:
            # The authored sacral support plane is not a flat body solid.
            _endplane(name, body.sweeps[0], disc, t.frame.at(0, 7.6, -2.4).y, 0)
    var cervical = head_ligament_field(h, CERVICAL_DISCS, RIGHT)
    for i in range(1, 7):
        var body = head_bone_field(h, HeadBone(i))
        var disc = cervical.sweeps[i - 1].copy()
        var d = _Disc(disc.copy())
        var lo, hi = _disc_bounds(disc)
        var name = "cervical/" + String(i + 1)
        _pair(body, body.low, body.high, name, d, lo, hi, name + "/disc", step)
        var below = disc.stations[1].p
        if i < 6:
            var next = head_bone_field(h, HeadBone(i + 1))
            _pair(
                body,
                body.low,
                body.high,
                name,
                next,
                next.low,
                next.high,
                "cervical/" + String(i + 2),
                step,
            )
            _pair(
                next,
                next.low,
                next.high,
                "cervical/" + String(i + 2),
                d,
                lo,
                hi,
                name + "/disc",
                step,
            )
            _endplane(
                name,
                body.sweeps[0],
                disc,
                h.centers[i + 1].y + h.heights[i + 1] * 0.5,
                next.sweeps[0].distance(below + Vector3(0, 0.0001, 0), 0),
            )
        else:
            var next = torso_bone_field(t, TorsoBone(0), RIGHT)
            _pair(
                body,
                body.low,
                body.high,
                name,
                next,
                next.low,
                next.high,
                "thoracolumbar/0",
                step,
            )
            _pair(
                next,
                next.low,
                next.high,
                "thoracolumbar/0",
                d,
                lo,
                hi,
                name + "/disc",
                step,
            )
            _endplane(
                name,
                body.sweeps[0],
                disc,
                t.centers[0].y + t.heights[0] * 0.5,
                next.sweeps[0].distance(below + Vector3(0, 0.0001, 0), 0),
            )
