# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The animals' anatomy: published sizes and their grades, tissues and
segments, densities, sampled mass properties and calibration."""

from extensions.anatomy.evidence import (
    CROSS_CHECKED,
    DESIGN,
    FROM_ABSTRACT,
    FROM_TEXT,
    UNVERIFIED,
    Evidence,
    evidence_label,
)
from extensions.animals.anatomy.body import (
    ANURAN,
    ARACHNID,
    BIRD,
    BODY_LENGTH,
    MAMMAL,
    SERPENT,
    SHARK_PLAN,
    SHOULDER_HEIGHT,
    TELEOST,
    TOTAL_LENGTH,
    BodyPlan,
    ReferenceKind,
    species_body,
)
from extensions.animals.anatomy.density import (
    IN_BODY,
    IS_COAT,
    ON_WITHERS,
    segment_density,
    solid_densities,
    solid_roles,
    tissue_density,
    whole_body_density,
)
from extensions.animals.anatomy.engineering import (
    Calibration,
    calibrate,
    calibrated_animal,
    calibrated_mass,
)
from extensions.animals.anatomy.mass import sample_mass
from extensions.animals.anatomy.tissue import (
    ABDOMEN,
    ANTLER,
    COAT,
    EYE,
    FIN,
    FOOT,
    FOREARM,
    FOREIGN,
    HAND,
    HEAD,
    KERATIN,
    LEG,
    NECK,
    PELVIS,
    PLUMAGE,
    SEGMENT_COUNT,
    SHANK,
    SOFT_BODY,
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
from extensions.animals.build import create_animal
from extensions.animals.options import (
    ADULT,
    CROWD,
    FEMALE,
    JUVENILE,
    MALE,
    Variant,
    animal_options,
)
from extensions.animals.parts import BODY, EYEBALL, HORN, JAW, TEETH
from extensions.animals.registry import (
    BEAR,
    FISH,
    FROG,
    RAT,
    SPECIES_COUNT,
    SPIDER,
    SpeciesId,
    species_of,
    species_variants,
)
from extensions.sdf.ids import ELLIPSOID
from extensions.sdf.vector import V3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import KILOGRAM, METER, Length


def test_evidence_grades_are_named() raises:
    for g in [FROM_ABSTRACT, FROM_TEXT, CROSS_CHECKED, UNVERIFIED, DESIGN]:
        assert_true(g.is_valid())
        assert_true(evidence_label(g).byte_length() > 0)
    assert_true(FROM_TEXT.is_measured())
    assert_false(UNVERIFIED.is_measured())
    assert_false(Evidence(-1).is_measured())
    assert_false(Evidence(5).is_valid())
    assert_false(Evidence(-1).is_valid())
    with assert_raises(contains="grade"):
        _ = evidence_label(Evidence(9))


def test_every_species_has_a_graded_published_size() raises:
    for i in range(SPECIES_COUNT):
        var b = species_body(SpeciesId(i))
        assert_true(b.plan.is_valid())
        assert_true(b.reference.is_valid())
        assert_true(b.male_mass.value > 0 and b.female_mass.value > 0)
        assert_true(b.reference_length.value > 0)
        assert_true(b.coat_depth.value >= 0)
        assert_true(b.mass_source.evidence.is_valid())
        assert_true(b.length_source.evidence.is_valid())
        # A measured value names its source.
        if b.mass_source.evidence.is_measured():
            assert_true(b.mass_source.source.byte_length() > 0)
        assert_true(b.variant < len(species_variants(SpeciesId(i))))
    with assert_raises(contains="species"):
        _ = species_body(SpeciesId(SPECIES_COUNT))
    for kind in [BodyPlan(-1), BodyPlan(7)]:
        assert_false(kind.is_valid())
    assert_false(ReferenceKind(3).is_valid())
    assert_false(ReferenceKind(-1).is_valid())


def test_tissues_follow_part_and_tag() raises:
    assert_equal(tissue_of(EYEBALL, "eyeball", "head"), EYE)
    assert_equal(tissue_of(TEETH, "tusk", "head"), TOOTH)
    assert_equal(tissue_of(HORN, "horn", "head"), KERATIN)
    assert_equal(tissue_of(HORN, "tine", "head"), ANTLER)
    assert_equal(tissue_of(BODY, "eartag", "earL"), FOREIGN)
    assert_equal(tissue_of(BODY, "mane", "neck1"), COAT)
    assert_equal(tissue_of(BODY, "primary@6391,479/12800", "pri1L"), COAT)
    assert_equal(tissue_of(BODY, "rectrix#6151,-199/13000", "tail"), COAT)
    assert_equal(tissue_of(BODY, "hoof", "fhoofL"), KERATIN)
    assert_equal(tissue_of(BODY, "sole", "hhoofR"), KERATIN)
    assert_equal(tissue_of(BODY, "sole", "hpawL"), SOFT_BODY)
    assert_equal(tissue_of(JAW, "mandible", "jaw"), SOFT_BODY)
    assert_equal(tissue_of(BODY, "", "head"), SOFT_BODY)
    for t in range(7):
        assert_true(BodyTissue(t).is_valid())
    assert_false(BodyTissue(7).is_valid())
    assert_false(BodyTissue(-1).is_valid())


def test_segments_follow_bone_and_plan() raises:
    var mammal: List[Tuple[String, Segment]] = [
        ("head", HEAD),
        ("jaw", HEAD),
        ("neck1", NECK),
        ("chest", THORAX),
        ("spine3", THORAX),
        ("spine1", ABDOMEN),
        ("pelvis", PELVIS),
        ("scapulaL", UPPER_ARM),
        ("radiusR", FOREARM),
        ("fhoofL", HAND),
        ("femurL", THIGH),
        ("tibiaR", SHANK),
        ("hpawL", FOOT),
        ("tail3", TAIL),
        ("udder", ABDOMEN),
        ("", HEAD),
        ("L", HEAD),
    ]
    for pair in mammal:
        assert_equal(segment_of(MAMMAL, pair[0]), pair[1])
    assert_equal(segment_of(BIRD, "spine3"), ABDOMEN)
    assert_equal(segment_of(BIRD, "pri4L"), PLUMAGE)
    assert_equal(segment_of(BIRD, "toe2bR"), FOOT)
    assert_equal(segment_of(BIRD, "ulnaL"), FOREARM)
    assert_equal(segment_of(TELEOST, "pectoralL"), FIN)
    assert_equal(segment_of(TELEOST, "caudal1"), TAIL)
    assert_equal(segment_of(ANURAN, "spine3"), THORAX)
    for name in ["prosoma", "pedicel"]:
        assert_equal(segment_of(ARACHNID, name), THORAX)
    for name in ["abdomen", "spinnerets"]:
        assert_equal(segment_of(ARACHNID, name), ABDOMEN)
    for name in ["head", "cheliceraL", "fangR"]:
        assert_equal(segment_of(ARACHNID, name), HEAD)
    assert_equal(segment_of(ARACHNID, "femur3L"), LEG)
    with assert_raises(contains="plan"):
        _ = segment_of(BodyPlan(9), "head")
    for s in range(SEGMENT_COUNT):
        assert_true(Segment(s).is_valid())
    assert_false(Segment(SEGMENT_COUNT).is_valid())


def test_densities_are_dempster_and_whole_body() raises:
    var expect: List[Tuple[Segment, Float64]] = [
        (HEAD, 1110.0),
        (NECK, 1110.0),
        (THORAX, 920.0),
        (ABDOMEN, 1010.0),
        (PELVIS, 1010.0),
        (UPPER_ARM, 1070.0),
        (FOREARM, 1130.0),
        (HAND, 1160.0),
        (THIGH, 1050.0),
        (SHANK, 1090.0),
        (TAIL, 1090.0),
        (FOOT, 1100.0),
    ]
    for pair in expect:
        assert_almost_equal(
            Float64(segment_density(MAMMAL, pair[0]).value), pair[1]
        )
    with assert_raises(contains="mammal has no"):
        _ = segment_density(MAMMAL, FIN)
    with assert_raises(contains="Only a mammal"):
        _ = segment_density(BIRD, HEAD)
    var whole: List[Tuple[String, Float64]] = [
        ("chicken", 1044.0),
        ("crow", 968.0),
        ("shark", 1050.0),
        ("snake", 1057.0),
        ("spider", 1050.0),
        ("fish", 1000.0),
        ("frog", 1000.0),
    ]
    for pair in whole:
        var d = whole_body_density(species_of(pair[0]))
        assert_almost_equal(Float64(d.value), pair[1])
    with assert_raises(contains="by segment"):
        _ = whole_body_density(BEAR)
    var tissue: List[Tuple[BodyTissue, Float64]] = [
        (COAT, 0.0),
        (FOREIGN, 0.0),
        (KERATIN, 1300.0),
        (ANTLER, 1800.0),
        (TOOTH, 2100.0),
        (EYE, 1010.0),
    ]
    for pair in tissue:
        assert_almost_equal(Float64(tissue_density(pair[0]).value), pair[1])
    with assert_raises(contains="segment"):
        _ = tissue_density(SOFT_BODY)
    with assert_raises(contains="named"):
        _ = tissue_density(BodyTissue(12))


def test_solids_get_density_and_roles() raises:
    var rat = create_animal(RAT, animal_options(3, quality=CROWD, age=ADULT))
    var d = solid_densities(rat)
    var roles = solid_roles(rat)
    assert_equal(len(d), len(rat.model.prims))
    var withers = 0
    var coat = 0
    for i in range(len(d)):
        ref p = rat.model.prims[i]
        assert_true(d[i] >= 0.0)
        if p.carve:
            assert_equal(d[i], 0.0)
        withers += 1 if roles[i] & ON_WITHERS != 0 else 0
        coat += 1 if roles[i] & IS_COAT != 0 else 0
    assert_true(withers > 0)
    assert_true(coat > 0)
    var frog = create_animal(FROG, animal_options(3, quality=CROWD))
    for v in solid_densities(frog):
        assert_true(v == 0.0 or v >= 1000.0)
    var body = 0
    for r in solid_roles(frog):
        body += 1 if r & IN_BODY != 0 else 0
    assert_true(body > 0)
    # A crow's flight feathers ride bones of their own and weigh nothing.
    var crow = create_animal(
        species_of("crow"), animal_options(3, quality=CROWD)
    )
    var plumage = 0
    var feathers = solid_densities(crow)
    for i in range(len(feathers)):
        var bone = crow.rig.bones[crow.model.prims[i].bone.value].name
        if bone.startswith("pri"):
            plumage += 1
            assert_equal(feathers[i], 0.0)
    assert_true(plumage > 0)
    # A snake's tail is not in its snout-vent length.
    var snake = create_animal(
        species_of("snake"), animal_options(3, quality=CROWD)
    )
    var roles_s = solid_roles(snake)
    for i in range(len(roles_s)):
        var tag = snake.model.tags[snake.model.prims[i].tag.value]
        if tag.startswith("tail"):
            assert_equal(roles_s[i] & IN_BODY, 0)


def test_sampled_mass_is_the_sum_of_bones_and_converges() raises:
    var rat = create_animal(
        RAT, animal_options(2, quality=CROWD, sex=MALE, age=ADULT)
    )
    var coarse = sample_mass(rat, rat.bind_pose(), Length(0.008, METER), 1)
    var fine = sample_mass(rat, rat.bind_pose(), Length(0.004, METER), 3)
    var a = coarse.total()
    var b = fine.total()
    assert_almost_equal(Float64(a.mass.value), Float64(b.mass.value), rtol=0.06)
    var sum = 0.0
    for i in range(len(fine.bones)):
        if fine.bones[i].mass > 0.0:
            var seg = fine.bone(i, 0.01)
            sum += Float64(seg.mass.value)
            assert_true(seg.xx.value >= 0 and seg.yy.value >= 0)
    assert_almost_equal(sum, Float64(b.mass.value), rtol=1e-4)
    # Flesh of about a tissue's density.
    var rho = Float64(b.mass.value) / Float64(fine.volume.value)
    assert_true(rho > 900.0 and rho < 1200.0)
    assert_true(fine.reference(BODY_LENGTH).value > 0.1)
    assert_true(fine.reference(TOTAL_LENGTH) > fine.reference(BODY_LENGTH))
    assert_true(fine.reference(SHOULDER_HEIGHT).value > 0.0)
    with assert_raises(contains="named"):
        _ = fine.reference(ReferenceKind(5))
    with assert_raises(contains="no such bone"):
        _ = fine.bone(len(fine.bones), 0.1)
    with assert_raises(contains="no such bone"):
        _ = fine.bone(-1, 0.1)
    with assert_raises(contains="step"):
        _ = sample_mass(rat, rat.bind_pose(), Length(0, METER))
    with assert_raises(contains="400"):
        _ = sample_mass(rat, rat.bind_pose(), Length(0.0005, METER))
    with assert_raises(contains="step"):
        _ = sample_mass(rat, rat.bind_pose(), Length(2000, METER))
    # A sculpt of coat alone has no flesh.
    var bald = create_animal(RAT, animal_options(2, quality=CROWD))
    var mane = bald.model.tag("mane")
    for i in range(len(bald.model.prims)):
        bald.model.prims[i].tag = mane
        bald.model.prims[i].part = BODY
    with assert_raises(contains="no flesh"):
        _ = sample_mass(bald, bald.bind_pose(), Length(0.01, METER))
    # Solids far thinner than a cell leave no flesh in any cell.
    var thin = create_animal(RAT, animal_options(2, quality=CROWD))
    for i in range(1, len(thin.model.prims)):
        thin.model.prims[i].carve = True
    thin.model.prims[0].kind = ELLIPSOID
    thin.model.prims[0].part = BODY
    var flesh = thin.model.tag("ribcage")
    thin.model.prims[0].tag = flesh
    thin.model.prims[0].r = V3(1e-6, 1e-6, 1e-6)
    thin.model.prims[0].k = 1e-7
    with assert_raises(contains="no flesh"):
        _ = sample_mass(thin, thin.bind_pose(), Length(0.01, METER))
    var fish = create_animal(FISH, animal_options(2, quality=CROWD))
    var swim = sample_mass(fish, fish.bind_pose(), Length(0.02, METER))
    with assert_raises(contains="withers"):
        _ = swim.reference(SHOULDER_HEIGHT)


def test_calibration_scales_to_the_published_size() raises:
    var cal = calibrate(SPIDER, Variant(-1), allow_estimates=True)
    assert_true(cal.matched)
    assert_almost_equal(Float64(cal.published.value), 0.055, rtol=1e-6)
    assert_almost_equal(
        cal.scale * Float64(cal.measured.value), 0.055, rtol=1e-5
    )
    assert_almost_equal(
        cal.density_factor,
        Float64(cal.published_mass.value / cal.predicted_mass.value),
        rtol=1e-5,
    )
    var canon = create_animal(
        SPIDER,
        animal_options(
            1, quality=CROWD, sex=MALE, age=ADULT, variant=Variant(1)
        ),
    )
    var m = calibrated_mass(canon, cal)
    # The canonical male weighs the published mass.
    assert_almost_equal(
        Float64(m.total().mass.value),
        Float64(cal.published_mass.to(KILOGRAM)),
        rtol=0.03,
    )
    var young = create_animal(
        SPIDER,
        animal_options(4, quality=CROWD, age=JUVENILE, variant=Variant(1)),
    )
    var small = calibrated_mass(young, cal, 40.0)
    assert_true(small.total().mass < m.total().mass)
    # Another morph keeps the length but not the mass correction.
    var wolf_spider = calibrate(SPIDER, Variant(0), allow_estimates=True)
    assert_false(wolf_spider.matched)
    assert_equal(wolf_spider.density_factor, 1.0)
    var bad = cal
    for scale in [0.0, 1e4]:
        bad.scale = scale
        with assert_raises(contains="scale"):
            _ = calibrated_animal(canon, bad)
    for cells in [2.0, 500.0]:
        with assert_raises(contains="cells"):
            _ = calibrated_mass(canon, cal, cells)
    var big = calibrated_animal(canon, cal)
    assert_almost_equal(big.cell, canon.cell * cal.scale, rtol=1e-12)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
