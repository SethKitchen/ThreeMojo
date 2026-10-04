# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The animals extension's core: the rig and poses, proportion warps,
options, traits, noise and the eye and head helpers."""

from extensions.sdf.ids import (
    BoneId,
    CONE,
    ELLIPSOID,
    FIN,
    LENS,
    PrimitiveKind,
    SurfacePart,
    TagId,
    require_kind,
    require_part,
)
from extensions.animals.parts import (
    BODY,
    JAW,
)
from extensions.sdf.sculpt import (
    ell_y,
    tube,
)
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    head_local,
    sculpt_eye_socket,
)
from extensions.sdf.mesher import (
    Lattice,
    SurfaceMesh,
    UNSAMPLED,
    _Grid,
    _faces,
    check_cell,
    merge,
    mesh_part,
)
from extensions.animals.noise import cells3, fbm3, ihash, vnoise3
from extensions.animals.options import (
    ADULT,
    ANY_AGE,
    ANY_SEX,
    ANY_VARIANT,
    CROWD,
    FEMALE,
    HERO,
    HIGH,
    JUVENILE,
    LOW,
    MALE,
    MEDIUM,
    Age,
    AnimalOptions,
    Quality,
    Sex,
    Variant,
    animal_options,
    body_random,
    check_options,
    coat_random,
)
from extensions.animals.rig import (
    NO_BONE,
    Bone,
    Pose,
    Rig,
    add_sided,
    quadruped_bones,
    tail_chain,
)
from extensions.sdf.field import (
    FAR,
    SdfModel,
    outline_distance,
    smin,
)
from extensions.animals.traits import (
    Traits,
    pick_age,
    pick_sex,
    pick_variant,
)
from extensions.sdf.vector import (
    Rigid,
    V3,
    clamp,
    cross,
    distance,
    dot,
    frame_zy,
    identity,
    length,
    lerp,
    mirror,
    mix,
    normalize,
    rotate_about,
    rotation_about,
    smoothstep,
    v3,
)
from extensions.animals.warp import (
    GIRTH,
    LEGS,
    SCALE_ABOUT,
    SHIFT,
    Warp,
    WarpKind,
    Warps,
    apply_warp,
    check_warp,
    girth_warp,
    legs_warp,
    length_warp,
    scale_about_warp,
    scale_warp,
    shift_warp,
)
from std.math import pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import METER, Length


def _near(a: V3, b: V3, tolerance: Float64 = 1e-9) raises:
    assert_almost_equal(a.x, b.x, atol=tolerance)
    assert_almost_equal(a.y, b.y, atol=tolerance)
    assert_almost_equal(a.z, b.z, atol=tolerance)


def _ball() raises -> SdfModel:
    var m = SdfModel()
    _ = m.sphere("ball", BoneId(0), V3(0, 0, 0), 1.0, k=0.0)
    return m^


def _square() -> List[Float64]:
    return [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, 1.0]


def _leg_rig() raises -> Rig:
    var rig = Rig()
    rig.set("hipL", V3(0.1, 1, 0))
    rig.set("kneeL", V3(0.1, 0.5, 0.1))
    rig.set("footL", V3(0.1, 0, 0))
    rig.mirror_joints()
    _ = rig.add_bone("thighL", "hipL", "kneeL", "")
    _ = rig.add_bone("shinL", "kneeL", "footL", "thighL")
    return rig^


def test_rig_joints_and_bones() raises:
    var rig = _leg_rig()
    _near(rig.j("kneeR"), V3(-0.1, 0.5, 0.1))
    assert_equal(rig.find_joint("nowhere"), -1)
    rig.set("kneeL", V3(0.1, 0.5, 0.2))
    _near(rig.j("kneeL"), V3(0.1, 0.5, 0.2))
    # Mirroring again keeps a right joint that is already placed.
    rig.mirror_joints()
    _near(rig.j("kneeR"), V3(-0.1, 0.5, 0.1))
    assert_equal(rig.bone("shinL").value, 1)
    assert_true(rig.bones[0].parent == NO_BONE)
    _near(rig.head_of(BoneId(1)), V3(0.1, 0.5, 0.2))
    _near(rig.tail_of(BoneId(1)), V3(0.1, 0, 0))
    with assert_raises(contains="no joint"):
        _ = rig.j("nowhere")
    with assert_raises(contains="no bone"):
        _ = rig.bone("wing")
    with assert_raises(contains="already has a bone"):
        _ = rig.add_bone("thighL", "hipL", "kneeL", "")
    with assert_raises(contains="no bone"):
        _ = rig.add_bone("toe", "hipL", "kneeL", "foot")
    with assert_raises(contains="names no bone"):
        rig.check(BoneId(2))
    with assert_raises(contains="names no bone"):
        rig.check(BoneId(-1))
    var copy = rig.copy()
    copy.set("hipL", V3(0, 0, 0))
    _near(rig.j("hipL"), V3(0.1, 1, 0))
    add_sided(rig, "foot{S}", "knee{S}", "foot{S}", "")
    assert_equal(rig.bones[3].name, "footR")


def test_tail_chain() raises:
    var rig = Rig()
    rig.set("tailBase", V3(0, 1, 0))
    tail_chain(rig, "tailBase", [0.0, 90.0], [0.5, 0.25])
    _near(rig.j("tail1"), V3(0, 1, -0.5), 1e-12)
    _near(rig.j("tail2"), V3(0, 1.25, -0.5), 1e-12)
    with assert_raises(contains="one length per angle"):
        tail_chain(rig, "tailBase", [0.0], [0.5, 0.25])


def test_quadruped_skeleton() raises:
    var rig = Rig()
    for name in [
        String("lumbosacral"),
        "tailBase",
        "lumbarMid",
        "thoraxRear",
        "chestMid",
        "neckBase",
        "neckMid",
        "occiput",
        "nose",
        "jawHinge",
        "jawTip",
        "earBaseL",
        "earTipL",
        "scapTopL",
        "shoulderL",
        "elbowL",
        "wristL",
        "mcpL",
        "ftoeL",
        "hipL",
        "kneeL",
        "hockL",
        "mtpL",
        "htoeL",
    ]:
        rig.set(name, V3(0.1, 0.5, 0.0))
    tail_chain(rig, "tailBase", [0.0], [0.1])
    rig.mirror_joints()
    quadruped_bones(rig, 1)
    assert_equal(len(rig.bones), 9 + 2 + 18 + 1)
    var bare = rig.copy()
    bare.bones = List[Bone]()
    quadruped_bones(bare, 0, ears=False, jaw=False)
    assert_equal(len(bare.bones), 8 + 18)


def test_pose_turns_children() raises:
    var rig = _leg_rig()
    var pose = Pose(len(rig.bones))
    pose.turn(rig, "thighL", V3(1, 0, 0), pi / 2.0)
    var world = pose.world(rig)
    # The thigh turns about the hip, and the shin rides it.
    _near(world[0].apply(V3(0.1, 0, 0)), V3(0.1, 1, -1), 1e-12)
    _near(world[1].apply(V3(0.1, 0, 0)), V3(0.1, 1, -1), 1e-12)
    pose.turn(rig, "shinL", V3(1, 0, 0), pi / 2.0)
    world = pose.world(rig)
    _near(world[1].apply(V3(0.1, 0, 0)), world[1].apply(V3(0.1, 0, 0)))
    var wrong = Pose(1)
    with assert_raises(contains="another rig"):
        wrong.turn(rig, "thighL", V3(1, 0, 0), 0.1)
    with assert_raises(contains="another rig"):
        _ = wrong.world(rig)


def test_mutated_bone_ids_are_refused_before_indexing() raises:
    var rig = _leg_rig()
    var pose = Pose(len(rig.bones))
    for invalid in [-2, 1, 2]:
        rig.bones[1].parent = BoneId(invalid)
        with assert_raises(contains="earlier bone"):
            _ = pose.world(rig)
    var model = _ball()
    model.prims[0].bone = BoneId(-1)
    with assert_raises(contains="has no transform"):
        _ = model.moved([identity()])
    for invalid in [-1, 1]:
        var tagged = _ball()
        tagged.prims[0].tag = TagId(invalid)
        with assert_raises(contains="names no tag"):
            _ = tagged.moved([identity()])
    var wrong_kind = _ball()
    wrong_kind.prims[0].kind = PrimitiveKind(-1)
    with assert_raises(contains="kind"):
        _ = wrong_kind.moved([identity()])
    var wrong_part = _ball()
    wrong_part.prims[0].part = SurfacePart(-1)
    with assert_raises(contains="part"):
        _ = wrong_part.moved([identity()])


def test_warps_move_points() raises:
    _near(apply_warp(scale_warp(2.0), V3(1, 2, 3)), V3(2, 4, 6))
    # Legs: below the belly line, height stretches.
    var legs = legs_warp(1.1, 0.5)
    _near(apply_warp(legs, V3(0, 0.2, 0)), V3(0, 0.22, 0), 1e-12)
    _near(apply_warp(legs, V3(0, -0.1, 0)), V3(0, -0.1, 0), 1e-12)
    var above = apply_warp(legs, V3(0, 1.0, 0))
    assert_almost_equal(above.y - 1.0, 0.05, atol=1e-9)
    var inside = apply_warp(legs, V3(0, 0.5, 0))
    assert_true(inside.y > 0.5)
    # Length: the span stretches about its middle and the ends move.
    var span = length_warp(1.2, -0.5, 0.5)
    _near(apply_warp(span, V3(0, 0, 0)), V3(0, 0, 0), 1e-12)
    assert_true(apply_warp(span, V3(0, 0, 1)).z > 1.0)
    assert_true(apply_warp(span, V3(0, 0, -1)).z < -1.0)
    # Scale about: whole at the center, none far away.
    var head = scale_about_warp(V3(0, 1, 0), 1.5, 0.1, 0.2)
    _near(apply_warp(head, V3(0, 1.05, 0)), V3(0, 1.075, 0), 1e-12)
    _near(apply_warp(head, V3(0, 2, 0)), V3(0, 2, 0), 1e-12)
    # Girth: wider inside the planes, above the belly.
    var girth = girth_warp(1.2, 0.5, -0.3, 0.3)
    var g = apply_warp(girth, V3(0.1, 0.5, 0))
    assert_almost_equal(g.x, 0.12, atol=1e-9)
    _near(apply_warp(girth, V3(0.1, 0.5, 2)), V3(0.1, 0.5, 2), 1e-12)
    # Shift: whole past the segment, none before it.
    var shift = shift_warp(V3(0, 0, 0), V3(0, 0, 1), V3(0, 0.1, 0))
    _near(apply_warp(shift, V3(0, 0, 2)), V3(0, 0.1, 2), 1e-12)
    _near(apply_warp(shift, V3(0, 0, -1)), V3(0, 0, -1), 1e-12)


def test_warp_checks() raises:
    assert_true(WarpKind(5).is_valid())
    assert_false(WarpKind(6).is_valid())
    assert_false(WarpKind(-1).is_valid())
    var zero = V3(0, 0, 0)
    with assert_raises(contains="Warp kind"):
        check_warp(Warp(WarpKind(9), 1, 0, 0, zero, zero, zero))
    with assert_raises(contains="positive width"):
        check_warp(scale_about_warp(zero, 1.1, 0.2, 0.1))
    with assert_raises(contains="planes must be in order"):
        check_warp(length_warp(1.1, 0.5, -0.5))
    with assert_raises(contains="planes must be in order"):
        check_warp(girth_warp(1.1, 0.5, 0.5, -0.5))
    with assert_raises(contains="above the ground"):
        check_warp(legs_warp(1.1, 0.0))
    with assert_raises(contains="must not be empty"):
        check_warp(shift_warp(zero, zero, V3(1, 0, 0)))
    check_warp(scale_warp(1.0))
    var warps = Warps()
    with assert_raises(contains="above the ground"):
        warps.add(legs_warp(1.1, -1.0))
    assert_equal(len(warps.list), 0)


def test_warps_reshape_a_sculpt() raises:
    var m = SdfModel()
    _ = m.ell("egg", BoneId(0), V3(0, 1, 0), V3(0.1, 0.2, 0.3))
    _ = m.cone("leg", BoneId(0), V3(0, 1, 0), V3(0, 0, 0), 0.1, 0.05)
    _ = m.lens(
        "eye",
        BoneId(0),
        V3(0, 1, 0.3),
        V3(1, 0, 0),
        V3(0, 1, 0),
        V3(0, 0, 1),
        0.02,
        0.01,
        -0.01,
        0.01,
        carve=True,
    )
    _ = m.fin(
        "fin",
        BoneId(0),
        V3(0, 1, -0.3),
        V3(1, 0, 0),
        V3(0, 1, 0),
        _square(),
        0.01,
    )
    var warps = Warps()
    warps.add(scale_warp(2.0))
    var w = warps.warp_model(m)
    _near(w.prims[0].c, V3(0, 2, 0), 1e-9)
    _near(w.prims[0].r, V3(0.2, 0.4, 0.6), 1e-6)
    # Blends grow with the body.
    assert_almost_equal(w.prims[0].k, 2.0 * m.prims[0].k, atol=1e-6)
    _near(w.prims[1].b, V3(0, 0, 0), 1e-9)
    assert_almost_equal(w.prims[1].r.x, 0.2, atol=1e-6)
    assert_almost_equal(w.prims[2].r.x, 0.04, atol=1e-6)
    assert_almost_equal(w.prims[2].hi, 0.02, atol=1e-6)
    assert_almost_equal(w.prims[3].r.x, 0.01, atol=1e-6)
    assert_almost_equal(w.outline[0], -2.0, atol=1e-6)
    assert_almost_equal(warps.scale_at(V3(1, 1, 1)), 2.0, atol=1e-6)
    var rig = _leg_rig()
    var big = warps.warp_rig(rig)
    _near(big.j("hipL"), V3(0.2, 2, 0), 1e-12)


def test_options_and_quality() raises:
    assert_equal(HERO.resolution(), 1.0)
    assert_equal(HIGH.resolution(), 1.3)
    assert_equal(MEDIUM.resolution(), 2.0)
    assert_equal(LOW.resolution(), 3.0)
    assert_equal(CROWD.resolution(), 4.2)
    assert_equal(Quality(9).resolution(), 4.2)
    assert_false(Quality(-1).is_valid())
    var o = animal_options(seed=-1)
    assert_equal(o.seed, 0xFFFFFFFF)
    check_options(o)
    with assert_raises(contains="quality"):
        check_options(
            AnimalOptions(1, Quality(5), ANY_SEX, ANY_AGE, ANY_VARIANT)
        )
    with assert_raises(contains="sex"):
        check_options(AnimalOptions(1, HIGH, Sex(2), ANY_AGE, ANY_VARIANT))
    with assert_raises(contains="sex"):
        check_options(AnimalOptions(1, HIGH, Sex(-2), ANY_AGE, ANY_VARIANT))
    with assert_raises(contains="age"):
        check_options(AnimalOptions(1, HIGH, ANY_SEX, Age(2), ANY_VARIANT))
    with assert_raises(contains="age"):
        check_options(AnimalOptions(1, HIGH, ANY_SEX, Age(-2), ANY_VARIANT))
    with assert_raises(contains="variant"):
        check_options(AnimalOptions(1, HIGH, ANY_SEX, ANY_AGE, Variant(-2)))


def test_random_streams_match_the_original() raises:
    # procedural-animals' rng(seed * 2654435761 + 12345) for seed 3 and
    # rng(3 * 7919 + 17), drawn in JavaScript.
    var r = body_random(3)
    assert_almost_equal(r.next(), 0.6132382601499557, atol=1e-15)
    var c = coat_random(3)
    assert_almost_equal(c.next(), 0.7951061737257987, atol=1e-15)
    var one = body_random(1)
    var g = one.g()
    assert_true(g > -1.0 and g < 1.0)


def test_traits() raises:
    var t = Traits(MALE, JUVENILE, 2)
    assert_equal(t.get("ear"), 1.0)
    assert_equal(t.get("ear", 0.5), 0.5)
    t.set("ear", 1.2)
    t.set("ear", 1.3)
    t.set("tail", 0.9)
    assert_equal(t.get("ear"), 1.3)
    assert_equal(len(t.names), 2)
    assert_true(t.male())
    assert_equal(t.juvenile(), 1.0)
    var f = Traits(FEMALE, ADULT, 0)
    assert_false(f.male())
    assert_equal(f.juvenile(), 0.0)


def test_picks() raises:
    var r = body_random(1)
    assert_true(pick_sex(MALE, r) == MALE)
    assert_true(pick_sex(FEMALE, r) == FEMALE)
    var drawn = pick_sex(ANY_SEX, r)
    assert_true(drawn == MALE or drawn == FEMALE)
    var low = body_random(5)
    var picks = 0
    for _ in range(20):
        picks += Int(pick_sex(ANY_SEX, low) == MALE)
    assert_true(picks > 0 and picks < 20)
    assert_true(pick_age(JUVENILE) == JUVENILE)
    assert_true(pick_age(ANY_AGE) == ADULT)
    var weights: List[Float64] = [0.5, 0.3, 0.2]
    assert_equal(pick_variant(-1, weights, 0.1), 0)
    assert_equal(pick_variant(-1, weights, 0.6), 1)
    assert_equal(pick_variant(-1, weights, 0.95), 2)
    assert_equal(pick_variant(-1, weights, 1.5), 0)
    assert_equal(pick_variant(2, weights, 0.1), 2)
    with assert_raises(contains="no such color variant"):
        _ = pick_variant(3, weights, 0.1)


def test_noise() raises:
    # procedural-animals' ihash, computed in JavaScript.
    assert_almost_equal(ihash(1, 2, 3), 0.37165542552247643, atol=1e-15)
    assert_almost_equal(ihash(-7, 0, 9), 0.6756379308644682, atol=1e-15)
    var a = vnoise3(V3(0.3, 1.7, -2.2))
    assert_true(a >= 0.0 and a < 1.0)
    # On a lattice point, value noise is the hash there.
    assert_almost_equal(vnoise3(V3(1, 2, 3)), ihash(1, 2, 3), atol=1e-15)
    var f = fbm3(V3(0.1, 0.2, 0.3))
    assert_true(f > 0.0 and f < 1.0)
    assert_equal(fbm3(V3(0, 0, 0), 0), 0.5)
    var c = cells3(V3(0.5, 0.5, 0.5), 3)
    assert_true(c.nearest <= c.second)
    assert_true(c.id >= 0.0 and c.id < 1.0)
    assert_true(cells3(V3(4.1, -2.3, 7.7), 1).nearest < 1.0)


def test_kit_helpers() raises:
    var m = SdfModel()
    _ = ell_y(m, "ear", BoneId(0), V3(0, 0, 0), V3(0, 2, 0), V3(0.1, 0.3, 0.05))
    # The long radius runs along `ydir`.
    assert_almost_equal(m.distance(0, V3(0, 0.3, 0)), 0.0, atol=1e-9)
    var points: List[V3] = [V3(0, 0, 0), V3(0, 0, 1), V3(0, 1, 1)]
    var radii: List[Float64] = [0.1, 0.08, 0.06]
    tube(m, "lip", BoneId(0), points, radii, V3(0, 2, 1), 3, 0.01)
    assert_equal(len(m.prims), 1 + 1 + 3)
    assert_equal(m.prims[1].k, 0.01)
    assert_equal(m.prims[2].k, 0.0)
    with assert_raises(contains="two or more points"):
        tube(m, "lip", BoneId(0), [V3(0, 0, 0)], [0.1], V3(0, 0, 1), 3, 0.0)
    with assert_raises(contains="two or more points"):
        tube(m, "lip", BoneId(0), points, [0.1], V3(0, 0, 1), 3, 0.0)
    var eye = EyeSpec(
        V3(0.03, 0.02, 0.04),
        0.01,
        0.002,
        0.2,
        0.05,
        0.001,
        0.012,
        0.008,
        0.0,
        0.1,
        0.006,
        0.008,
    )
    var left = eye_frame_of(eye, V3(0, 1, 0), 1.0)
    var right = eye_frame_of(eye, V3(0, 1, 0), -1.0)
    assert_almost_equal(left.c.x, -right.c.x, atol=1e-12)
    assert_true(left.z.x > 0.0)
    _near(left.at(0, 0, 0), left.c)
    var count = len(m.prims)
    _ = sculpt_eye_socket(m, eye, V3(0, 1, 0), 1.0, BoneId(0))
    assert_equal(len(m.prims), count + 2)
    _ = sculpt_eye_socket(
        m,
        eye,
        V3(0, 1, 0),
        -1.0,
        BoneId(0),
        orbit_r=V3(0.01, 0.01, 0.01),
        orbit_k=0.003,
        z_max=0.02,
    )
    assert_equal(len(m.prims), count + 5)
    assert_equal(m.prims[count + 2].k, 0.003)
    _near(
        head_local(V3(0, 1, 0), 2.0, 0.05, 1.5, 1.2, V3(0.1, 0.1, 0.15)),
        V3(0.24, 1.2, 0.4),
        1e-12,
    )
    _near(
        head_local(V3(0, 1, 0), 2.0, 0.05, 1.5, 1.0, V3(0, 0, -0.1)),
        V3(0, 1, -0.2),
        1e-12,
    )


def test_empty_inputs() raises:
    var rig = Rig()
    rig.mirror_joints()
    assert_equal(len(rig.joints), 0)
    with assert_raises(contains="no bone"):
        _ = rig.bone("head")
    rig.set("base", V3(0, 0, 0))
    tail_chain(rig, "base", List[Float64](), List[Float64]())
    assert_equal(len(rig.joints), 2)
    assert_equal(len(Pose(0).world(Rig())), 0)
    # An outline of no points reads as the distance to its first point.
    assert_almost_equal(outline_distance(_square(), 0, 0, 3.0, 1.0), sqrt(20.0))
    var none = Warps()
    _near(none.apply(V3(1, 2, 3)), V3(1, 2, 3))
    assert_equal(len(none.warp_rig(Rig()).joints), 0)
    assert_equal(len(none.warp_model(SdfModel()).prims), 0)
    var empty = List[Float64]()
    assert_equal(pick_variant(-1, empty, 0.3), 0)


def test_valid_warps_pass_their_checks() raises:
    var warps = Warps()
    warps.add(girth_warp(1.1, 0.5, -0.3, 0.3))
    warps.add(shift_warp(V3(0, 0, 0), V3(0, 0, 1), V3(0, 0.1, 0)))
    warps.add(length_warp(1.1, -0.3, 0.3))
    warps.add(scale_about_warp(V3(0, 0, 0), 1.1, 0.1, 0.2))
    warps.add(legs_warp(1.1, 0.4))
    assert_equal(len(warps.list), 5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
