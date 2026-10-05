# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Public anatomy boundaries, reference identity and finite-model controls."""

from extensions.anatomy.evidence import DESIGN, FROM_TEXT, Evidence
from extensions.animals.anatomy.body import (
    BODY_LENGTH,
    TOTAL_LENGTH,
    MAMMAL,
    TELEOST,
    species_body,
)
from extensions.animals.anatomy.axial import axial_muscles
from extensions.animals.anatomy.density import solid_densities, solid_roles
from extensions.animals.anatomy.engineering import (
    calibrate,
    _check_reference_support,
    calibrated_animal,
    calibrated_mass,
)
from extensions.animals.anatomy.mass import sample_mass
from extensions.animals.anatomy.muscles import (
    AnimalMuscle,
    animal_muscles,
    descends,
    plan_muscles,
    spans_of,
)
from extensions.animals.anatomy.physics import segment_bodies
from extensions.animals.anatomy.reference import reference_length
from extensions.animals.anatomy.stance import (
    _load,
    _distal_weight_moment,
    standing_loads,
)
from extensions.animals.anatomy.tissue import tissue_of
from extensions.animals.build import Animal, create_animal
from extensions.animals.options import (
    ADULT,
    CROWD,
    MALE,
    Variant,
    animal_options,
)
from extensions.animals.registry import DOG, RAT, SPIDER, HORSE
from extensions.sdf.field import SdfModel
from extensions.animals.parts import BODY, EYEBALL
from extensions.sdf.ids import BoneId, TagId, SurfacePart, PrimitiveKind
from extensions.sdf.vector import V3, Rigid, identity
from std.math import inf, nan, pi
from std.testing import (
    TestSuite,
    assert_raises,
    assert_almost_equal,
    assert_equal,
    assert_false,
)
from units.si import Mass, Length, Pressure


def _rat() raises -> Animal:
    return create_animal(
        RAT, animal_options(1, quality=CROWD, sex=MALE, age=ADULT)
    )


def test_calibration_refuses_unsupported_reference_without_explicit_opt_in() raises:
    with assert_raises(contains="allow_estimates"):
        _ = calibrate(DOG, Variant(-1))
    with assert_raises(contains="allow_estimates"):
        _ = calibrate(SPIDER, Variant(0))
    with assert_raises(contains="variant"):
        _ = calibrate(RAT, Variant(-2))
    var estimate = calibrate(DOG, Variant(-1), allow_estimates=True)
    assert_equal(estimate.model_evidence(), DESIGN)
    assert_equal(species_body(DOG).model_evidence(), DESIGN)
    var unmatched = calibrate(SPIDER, Variant(0), allow_estimates=True)
    assert_false(unmatched.matched)
    assert_equal(unmatched.density_factor, 1.0)


def test_calibration_binds_species_morph_and_canonical_mass_sampling() raises:
    var cal = calibrate(SPIDER, Variant(-1), allow_estimates=True)
    var base = create_animal(
        SPIDER,
        animal_options(
            1, quality=CROWD, sex=MALE, age=ADULT, variant=Variant(1)
        ),
    )
    var scaled = calibrated_animal(base, cal)
    var observed = (
        sample_mass(scaled, scaled.bind_pose(), cal.published.scaled(0.025))
        .total()
        .mass
    )
    assert_almost_equal(observed.value, cal.predicted_mass.value, rtol=1e-6)
    var normalized = calibrated_mass(base, cal).total().mass
    assert_almost_equal(normalized.value, cal.published_mass.value, rtol=1e-6)
    with assert_raises(contains="twice"):
        _ = calibrated_animal(scaled, cal)
    with assert_raises(contains="another species"):
        _ = calibrated_animal(_rat(), cal)
    var other = create_animal(
        SPIDER, animal_options(1, quality=CROWD, variant=Variant(0))
    )
    with assert_raises(contains="another morph"):
        _ = calibrated_mass(other, cal, 40)
    for value in [
        Float64(-1),
        Float64(0),
        nan[DType.float64](),
        inf[DType.float64](),
    ]:
        var bad = cal
        bad.density_factor = value
        with assert_raises(contains="density"):
            _ = calibrated_mass(base, bad, 40)
    var bad = cal
    bad.density_factor *= 2
    with assert_raises(contains="reference masses"):
        bad.check()
    bad = cal
    bad.scale *= 2
    with assert_raises(contains="reference lengths"):
        bad.check()
    for value in [
        Float32(0),
        Float32(-1),
        nan[DType.float32](),
        inf[DType.float32](),
    ]:
        bad = cal
        bad.published = Length(value)
        with assert_raises(contains="reference"):
            bad.check()
    bad = cal
    bad.variant = Variant(-1)
    bad.matched = False
    bad.density_factor = 1
    bad.allow_estimates = True
    with assert_raises(contains="resolved"):
        bad.check()
    bad = cal
    bad.matched = False
    with assert_raises(contains="match"):
        bad.check()


def test_tissue_and_sampling_refuse_malformed_model_before_indexing() raises:
    with assert_raises(contains="part"):
        _ = tissue_of(SurfacePart(-1), "body", "head")
    for index in [-1, 100000]:
        var a = _rat()
        a.model.prims[0].bone = BoneId(index)
        with assert_raises(contains="Bone"):
            _ = solid_densities(a)
        with assert_raises(contains="Bone"):
            _ = solid_roles(a)
        with assert_raises(contains="Bone"):
            _ = sample_mass(a, a.bind_pose(), Length(0.01))
        a = _rat()
        a.model.prims[0].tag = TagId(index)
        with assert_raises(contains="Tag"):
            _ = solid_densities(a)
        with assert_raises(contains="Tag"):
            _ = solid_roles(a)
    var a = _rat()
    for value in [nan[DType.float64](), inf[DType.float64]()]:
        a.model.prims[0].c = V3(value, 0, 0)
        with assert_raises(contains="finite"):
            _ = sample_mass(a, a.bind_pose(), Length(0.01))
    a = _rat()
    a.model.prims[0].kind = PrimitiveKind(9)
    with assert_raises(contains="kind"):
        _ = sample_mass(a, a.bind_pose(), Length(0.01))
    with assert_raises(contains="named"):
        _ = reference_length(a)
    a = _rat()
    with assert_raises(contains="400"):
        _ = sample_mass(a, a.bind_pose(), Length(1e-30))


def test_paths_refuse_malformed_arrays_indexes_and_degenerate_segments() raises:
    var a = _rat()
    var world = a.bind_pose().world(a.rig)
    var muscles = animal_muscles(a.rig, MAMMAL, Mass(0.3))
    assert_equal(muscles[0].model_evidence(), DESIGN)
    for value in [Float32(-1), nan[DType.float32](), inf[DType.float32]()]:
        with assert_raises(contains="mass"):
            _ = animal_muscles(a.rig, MAMMAL, Mass(value))
    var m = muscles[0].copy()
    m.bones.clear()
    with assert_raises(contains="paired"):
        _ = m.path(world)
    for index in [-1, len(world)]:
        m = muscles[0].copy()
        m.bones[0] = index
        with assert_raises(contains="transform"):
            _ = m.path(world)
    m = muscles[0].copy()
    m.points[1] = m.points[0]
    with assert_raises(contains="positive length"):
        _ = m.path(world)
    for value in [nan[DType.float64](), inf[DType.float64]()]:
        m = muscles[0].copy()
        m.points[0] = V3(0, value, 0)
        with assert_raises(contains="finite"):
            _ = m.unit_length(world)
    m = muscles[0].copy()
    m.spans.clear()
    with assert_raises(contains="paired"):
        _ = m.moment_arms(a.rig, world)
    for index in [-1, len(a.rig.joints)]:
        m = muscles[0].copy()
        m.joints[0] = index
        with assert_raises(contains="joint"):
            _ = m.moment_arms(a.rig, world)
    m = muscles[0].copy()
    m.joints[0] = a.rig.find_joint("kneeL")
    with assert_raises(contains="head"):
        _ = m.moment_arms(a.rig, world)
    m = muscles[0].copy()
    m.spans[0] = 0
    with assert_raises(contains="span"):
        _ = m.moment_arms(a.rig, world)
    m = muscles[0].copy()
    m.axis = V3(0, 0, 0)
    with assert_raises(contains="axis"):
        _ = m.moment_arms(a.rig, world)
    with assert_raises(contains="two bones"):
        _ = spans_of(a.rig, [], [])
    for index in [-1, len(a.rig.bones)]:
        with assert_raises(contains="descendant"):
            _ = descends(a.rig, index, 0)
        with assert_raises(contains="ancestor"):
            _ = descends(a.rig, 0, index)
    var leg = a.rig.bone("tibiaL").value
    a.rig.bones[leg].parent = BoneId(leg)
    with assert_raises(contains="earlier"):
        _ = descends(a.rig, leg, 0)


def _still(count: Int) -> List[Rigid]:
    var out = List[Rigid](capacity=count)
    for _ in range(count):
        out.append(identity())
    return out^


def test_paths_refuse_each_coordinate_and_unrepresentable_lengths() raises:
    var a = _rat()
    var muscles = animal_muscles(a.rig, MAMMAL, Mass(0.3))
    assert_equal(plan_muscles(MAMMAL)[0].model_evidence(), DESIGN)
    var still = _still(len(a.rig.bones))
    var m = muscles[0].copy()
    m.points = [m.points[0]]
    m.bones = [m.bones[0]]
    with assert_raises(contains="paired"):
        _ = m.path(still)
    # One coordinate alone overflows: a pure translation keeps the others.
    for axis in [V3(0, 1, 0), V3(0, 0, 1)]:
        m = muscles[0].copy()
        var moved = still.copy()
        moved[m.bones[0]].t = axis * 1e308
        m.points[0] = axis * 1e308
        with assert_raises(contains="finite points"):
            _ = m.path(moved)
    # Finite points can still be an unrepresentable distance apart.
    m = muscles[0].copy()
    m.points[0] = V3(0, 1e308, 0)
    m.points[1] = V3(0, -1e308, 0)
    with assert_raises(contains="positive length"):
        _ = m.path(still)
    # A path too long or too short for a Float32 SI length.
    for scale in [Float64(1e45), Float64(1e-50)]:
        m = muscles[0].copy()
        for k in range(len(m.points)):
            m.points[k] = m.points[k] * scale
        with assert_raises(contains="positive finite SI length"):
            _ = m.unit_length(still)
    m = muscles[0].copy()
    for k in range(len(m.points)):
        m.points[k] = m.points[k] * 1e45
    with assert_raises(contains="moment arm"):
        _ = m.moment_arms(a.rig, still)


def test_moment_arms_refuse_each_mismatched_mapping() raises:
    var a = _rat()
    var muscles = animal_muscles(a.rig, MAMMAL, Mass(0.3))
    var world = a.bind_pose().world(a.rig)
    var m = muscles[0].copy()
    var short = world.copy()
    _ = short.pop()
    with assert_raises(contains="transforms must match"):
        _ = m.moment_arms(a.rig, short)
    m.joint_bones.append(0)
    with assert_raises(contains="paired"):
        _ = m.moment_arms(a.rig, world)
    m = muscles[0].copy()
    m.axis = V3(nan[DType.float64](), 0, 0)
    with assert_raises(contains="axis"):
        _ = m.moment_arms(a.rig, world)
    # A muscle that crosses no joint has no moment arms.
    m = muscles[0].copy()
    m.joints.clear()
    m.joint_bones.clear()
    m.spans.clear()
    assert_equal(len(m.moment_arms(a.rig, world)), 0)
    # The joint table is shorter than the joint list.
    m = muscles[0].copy()
    var joint = m.joints[0]
    var rig = a.rig.copy()
    while len(rig.joint_names) > joint:
        _ = rig.joint_names.pop()
    with assert_raises(contains="head"):
        _ = m.moment_arms(rig, world)
    # The name lookup points at another joint.
    rig = a.rig.copy()
    rig.joint_at[rig.joint_names[joint]] = joint + 1
    with assert_raises(contains="head"):
        _ = m.moment_arms(rig, world)
    var leg = a.rig.bone("tibiaL").value
    with assert_raises(contains="cross back"):
        _ = spans_of(a.rig, [0, leg, 0], [leg])
    rig = a.rig.copy()
    rig.bones[leg].parent = BoneId(-2)
    with assert_raises(contains="earlier"):
        _ = descends(rig, leg, 0)


def test_standing_support_needs_ordered_finite_feet() raises:
    var a = _rat()
    var mass = sample_mass(a, a.bind_pose(), Length(0.01))
    var muscles = animal_muscles(a.rig, MAMMAL, Mass(0.3))
    for joint in [String("mcpL"), String("mtpL")]:
        var b = _rat()
        var p = b.rig.j(joint)
        b.rig.set(joint, V3(p.x, p.y, nan[DType.float64]()))
        with assert_raises(contains="ordered finite feet"):
            _ = standing_loads(b, mass, muscles)
    # The fore feet behind the hind feet.
    var b = _rat()
    for joint in [String("mcpL"), String("ftoeL")]:
        var p = b.rig.j(joint)
        b.rig.set(joint, V3(p.x, p.y, -10))
    with assert_raises(contains="ordered finite feet"):
        _ = standing_loads(b, mass, muscles)


def test_standing_advantage_refuses_a_foot_level_with_its_joint() raises:
    # A joint at z = 0 lets the foot sit a subnormal distance from it.
    var a = _rat()
    var knee = a.rig.j("kneeL")
    a.rig.set("kneeL", V3(knee.x, knee.y, 0))
    var muscles = animal_muscles(a.rig, MAMMAL, Mass(0.3))
    var foot = V3(knee.x, knee.y - 0.1, 1e-320)
    with assert_raises(contains="ratios must be finite"):
        _ = _load(a, muscles, "kneeL", foot, 10, -10)


def test_stance_capacity_is_independent_of_muscle_order() raises:
    var a = _rat()
    var muscles = animal_muscles(a.rig, MAMMAL, Mass(0.3))
    var strong = muscles[0].copy()
    var weak = muscles[0].copy()
    weak.arch.specific_tension = Pressure(150000)
    var foot = a.rig.j("kneeL") + V3(0, -0.1, 0.1)
    var first = _load(a, [strong.copy(), weak.copy()], "kneeL", foot, 10)
    var second = _load(a, [weak.copy(), strong.copy()], "kneeL", foot, 10)
    assert_almost_equal(first.activation, second.activation, atol=1e-10)
    assert_almost_equal(
        first.activation, Float64(first.stress.value) / 150000.0, rtol=1e-6
    )


def test_stance_includes_distal_weight_and_refuses_si_overflow() raises:
    var a = _rat()
    var muscles = animal_muscles(a.rig, MAMMAL, Mass(0.3))
    var foot = a.rig.j("kneeL") + V3(0, -0.1, 0.1)
    var unloaded = _load(a, List[AnimalMuscle](), "kneeL", foot, 0)
    assert_equal(unloaded.held, True)
    assert_equal(unloaded.activation, 0.0)
    var no_weight = _load(a, muscles, "kneeL", foot, 10)
    var with_weight = _load(a, muscles, "kneeL", foot, 10, 0.25)
    assert_almost_equal(
        no_weight.moment.value - with_weight.moment.value, 0.25, atol=1e-6
    )
    with assert_raises(contains="finite"):
        _ = _load(a, muscles, "kneeL", foot, 1e100)
    var mass = sample_mass(a, a.bind_pose(), Length(0.01))
    # Independent single distal point mass: 2 kg at 0.1 m forward of knee.
    for i in range(len(mass.bones)):
        mass.bones[i].mass = 0
        mass.bones[i].first = SIMD[DType.float64, 4](0)
        mass.bones[i].second = SIMD[DType.float64, 8](0)
    var distal = a.rig.bone("tibiaL").value
    var z = a.rig.j("kneeL").z + 0.1
    mass.bones[distal].mass = 2
    mass.bones[distal].first[2] = 2 * z
    mass.bones[distal].second[2] = 2 * z * z
    assert_almost_equal(
        _distal_weight_moment(a, mass, "kneeL"), 2 * 0.1 * 9.80665, atol=1e-6
    )


def test_sampling_rejects_visual_geometry_and_nonrigid_primitive_frame() raises:
    var a = _rat()
    a.traits.set("anatomy_visual_flex", 1.0)
    with assert_raises(contains="Visual flex"):
        _ = sample_mass(a, a.bind_pose(), Length(0.01))
    with assert_raises(contains="Visual flex"):
        _ = reference_length(a)
    a = _rat()
    a.model.visual_only = True
    with assert_raises(contains="Visual flex"):
        _ = sample_mass(a, a.bind_pose(), Length(0.01))
    with assert_raises(contains="Visual flex"):
        _ = reference_length(a)
    a = _rat()
    a.model.prims[0].ax = V3(0, 0, 0)
    with assert_raises(contains="orthonormal"):
        _ = sample_mass(a, a.bind_pose(), Length(0.01))
    a = _rat()
    a.model.prims[0].ay = a.model.prims[0].ax
    with assert_raises(contains="orthonormal"):
        _ = sample_mass(a, a.bind_pose(), Length(0.01))


def test_sampling_chooses_union_after_part_specific_coat_erosion() raises:
    var a = _rat()
    var model = SdfModel()
    var head = a.rig.bone("head")
    _ = model.sphere("head", head, V3(0, 0, 0), 0.1, k=0.0, part=BODY)
    _ = model.sphere("eye", head, V3(0, 0, 0), 0.098, k=0.0, part=EYEBALL)
    a.model = model^
    var mass = sample_mass(a, a.bind_pose(), Length(0.005), 1)
    # Rat coat depth is 5 mm. The body shrinks to radius .095 m; the bare
    # eye remains .098 m. A union taken before erosion misses its shell.
    var expected = 4.0 * pi / 3.0 * 0.098 * 0.098 * 0.098 * 1010.0
    assert_almost_equal(Float64(mass.total().mass.value), expected, rtol=0.015)


def test_axial_muscles_validate_masses_and_parent_indexes_without_pose() raises:
    var a = _rat()
    var mass = sample_mass(a, a.bind_pose(), Length(0.01))
    for bad in [Float64(-1), inf[DType.float64](), nan[DType.float64]()]:
        var keep = mass.bones[0].mass
        mass.bones[0].mass = bad
        with assert_raises(contains="mass"):
            _ = axial_muscles(a.rig, TELEOST, mass)
        mass.bones[0].mass = keep
    for bad in [-2, len(a.rig.bones)]:
        a.rig.bones[0].parent = BoneId(bad)
        with assert_raises(contains="parent"):
            _ = axial_muscles(a.rig, TELEOST, mass)


def test_missing_sampled_reference_is_explicitly_under_resolved() raises:
    var a = _rat()
    var mass = sample_mass(a, a.bind_pose(), Length(0.01))
    mass.body_length = Length(0)
    with assert_raises(contains="under-resolved"):
        _ = mass.reference(BODY_LENGTH)
    mass.total_length = Length(nan[DType.float32]())
    with assert_raises(contains="under-resolved"):
        _ = mass.reference(TOTAL_LENGTH)


def test_physics_export_rejects_negative_or_nonfinite_mass() raises:
    var a = _rat()
    var mass = sample_mass(a, a.bind_pose(), Length(0.01))
    for value in [Float64(-1), nan[DType.float64](), inf[DType.float64]()]:
        mass.bones[0].mass = value
        with assert_raises(contains="mass"):
            _ = segment_bodies(a, mass)


def test_matched_sourced_excerpts_cannot_bypass_template_estimate_gate() raises:
    for species in [SPIDER, RAT, HORSE]:
        var body = species_body(species)
        assert_equal(body.mass_source.evidence, FROM_TEXT)
        assert_equal(body.length_source.evidence, FROM_TEXT)
        assert_equal(body.model_evidence(), DESIGN)
        with assert_raises(contains="allow_estimates"):
            _ = calibrate(species, Variant(-1))
        var estimate = calibrate(species, Variant(-1), allow_estimates=True)
        assert_equal(estimate.allow_estimates, True)
        assert_equal(estimate.matched, True)
        assert_equal(estimate.model_evidence(), DESIGN)
        assert_equal(estimate.species, species)
        estimate.check()
        estimate.allow_estimates = False
        with assert_raises(contains="allow_estimates"):
            estimate.check()
    assert_equal(species_body(SPIDER).mass_source.source, "Mendoza")
    assert_equal(species_body(RAT).mass_source.source, "ADW")
    assert_equal(species_body(HORSE).mass_source.source, "TBMorph")


def test_reference_support_policy_checks_all_evidence_grades() raises:
    # This is only a policy truth table. It does not create a measured
    # SpeciesBody or claim that the built-in DESIGN rows are supported.
    for matched in [False, True]:
        for mass in range(-1, 6):
            for length in range(-1, 6):
                for parameters in range(-1, 6):
                    var expected = (
                        matched
                        and mass >= 0
                        and mass <= 2
                        and length >= 0
                        and length <= 2
                        and parameters >= 0
                        and parameters <= 2
                    )
                    if expected:
                        _check_reference_support(
                            matched,
                            Evidence(mass),
                            Evidence(length),
                            Evidence(parameters),
                            False,
                        )
                    else:
                        with assert_raises(contains="allow_estimates"):
                            _check_reference_support(
                                matched,
                                Evidence(mass),
                                Evidence(length),
                                Evidence(parameters),
                                False,
                            )
                    # Explicit estimate permission does not upgrade the grades.
                    _check_reference_support(
                        matched,
                        Evidence(mass),
                        Evidence(length),
                        Evidence(parameters),
                        True,
                    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
