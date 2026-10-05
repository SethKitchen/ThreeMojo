# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The animals extension's build: the coat kit, the walk, the species
registry and the pipeline from a seed to a painted mesh."""

from core.buffer_geometry import COLOR, NORMAL, POSITION
from extensions.animals.build import (
    Animal,
    _geometry,
    _inflate_thin,
    animal_materials,
    bake_occlusion,
    create_animal,
    mesh_animal,
    part_box,
    primitive_box,
)
from extensions.animals.coat import (
    EYE,
    CoatSample,
    FUR,
    KERATIN,
    NOSE,
    SURFACE_CLASS_COUNT,
    EyeLook,
    Palette,
    SurfaceClass,
    band,
    grizzle,
    mix3,
    paint_eye,
    palette_of,
    shade,
    srgb,
)
from extensions.animals.gait import (
    DUTY,
    _reach_along,
    WALK_FL,
    WALK_FR,
    WALK_HL,
    WALK_HR,
    foot_offset,
    is_quadruped,
    solve_two_bone,
    spine_count,
    undulate_pose,
    walk_pose,
    walk_pose_at,
    walk_stride,
)
from extensions.sdf.ids import (
    BoneId,
    FIN,
)
from extensions.animals.parts import (
    BODY,
    EYEBALL,
    HORN,
    JAW,
    TONGUE,
)
from extensions.animals.kit import EyeSpec
from extensions.sdf.mesher import SurfaceMesh
from extensions.animals.options import (
    ANY_AGE,
    ANY_SEX,
    CROWD,
    HIGH,
    JUVENILE,
    MALE,
    AnimalOptions,
    Quality,
    Variant,
    animal_options,
    body_random,
)
from extensions.animals.registry import (
    SPECIES_COUNT,
    WOLF,
    SpeciesId,
    require_species,
    species_cell,
    species_eye,
    species_head_origin,
    species_look,
    species_name,
    species_names,
    species_of,
    species_paint,
    species_palette,
    species_rig,
    species_sculpt,
    species_traits,
    species_variants,
)
from extensions.animals.rig import Pose, Rig
from extensions.sdf.field import SdfModel
from extensions.animals.traits import Traits
from extensions.anatomy.locomotion import (
    WALK_FROUDE,
    stride_frequency,
    stride_length,
)
from units.si import METER, SECOND, Duration, Length
from extensions.sdf.vector import (
    V3,
    length,
    rotation_about,
)
from std.math import floor, isfinite, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def test_colors() raises:
    var white = srgb(0xFFFFFF)
    assert_almost_equal(white.x, 1.0, atol=1e-12)
    var mid = srgb(0x808080)
    assert_almost_equal(mid.y, 0.21586, atol=1e-4)
    assert_almost_equal(srgb(0x010000).x, 1.0 / 255.0 / 12.92, atol=1e-12)
    var half = mix3(V3(0, 0, 0), V3(1, 1, 1), 0.5)
    assert_equal(half.x, 0.5)
    assert_equal(shade(V3(2, 0.5, -1), 1.0).x, 0.95)
    assert_equal(shade(V3(2, 0.5, -1), 1.0).y, 0.5)
    assert_equal(shade(V3(2, 0.5, -1), 1.0).z, 0.0)
    var g = grizzle(V3(0.5, 0.5, 0.5), V3(0.1, 0.2, 0.3), 100.0, 0.2)
    assert_true(g.x > 0.4 and g.x < 0.6)
    assert_equal(band(0.5, 0.0, 0.2, 0.8, 1.0), 1.0)
    assert_equal(band(0.95, 0.0, 0.2, 0.8, 0.9), 0.0)


def test_surface_classes_and_palettes() raises:
    assert_true(SurfaceClass(SURFACE_CLASS_COUNT - 1).is_valid())
    assert_false(SurfaceClass(SURFACE_CLASS_COUNT).is_valid())
    assert_false(SurfaceClass(-1).is_valid())
    var p = Palette()
    p.set("fur", V3(0.1, 0.2, 0.3))
    p.set("fur", V3(0.3, 0.2, 0.1))
    assert_equal(p.get("fur").x, 0.3)
    assert_equal(len(p.names), 1)
    assert_almost_equal(p.get("missing").x, 0.18)
    var names: List[String] = [String("a"), "b"]
    var hexes: List[Int] = [0xFF0000, 0x00FF00]
    var q = palette_of(names, hexes)
    assert_almost_equal(q.get("b").y, 1.0, atol=1e-12)
    with assert_raises(contains="one color per name"):
        _ = palette_of(names, [0xFF0000])
    assert_equal(len(palette_of(List[String](), List[Int]()).names), 0)
    assert_almost_equal(Palette().get("any").y, 0.18)


def test_eye_paint() raises:
    var look = EyeLook(
        V3(0.3, 0.2, 0.1),
        V3(0.5, 0.3, 0.1),
        V3(0.1, 0.05, 0.02),
        V3(0.8, 0.8, 0.75),
        0.4,
        0.0,
    )
    var center = paint_eye(look, V3(0, 0, 0.01), 0.01, 0.008)
    assert_true(center.surface == EYE)
    # The pupil is near black, the iris colored, the back of the ball
    # the sclera.
    assert_true(center.color.x < 0.01)
    var iris = paint_eye(look, V3(0.005, 0, 0.008), 0.01, 0.008)
    assert_true(iris.color.x > 0.05)
    var back = paint_eye(look, V3(0, 0, -0.01), 0.01, 0.008)
    assert_almost_equal(back.color.x, 0.8, atol=1e-9)
    # A vertical slit narrows the pupil across, a bar narrows it down.
    var cat = EyeLook(look.inner, look.mid, look.outer, look.sclera, 0.4, 3.0)
    var goat = EyeLook(look.inner, look.mid, look.outer, look.sclera, 0.4, -3.0)
    var side = V3(0.0025, 0, 0.01)
    var up = V3(0, 0.0025, 0.01)
    assert_true(
        paint_eye(cat, side, 0.01, 0.008).color.x
        > paint_eye(look, side, 0.01, 0.008).color.x
    )
    assert_true(
        paint_eye(goat, up, 0.01, 0.008).color.x
        > paint_eye(look, up, 0.01, 0.008).color.x
    )


def test_registry() raises:
    var names = species_names()
    assert_equal(len(names), SPECIES_COUNT)
    assert_equal(species_name(WOLF), "wolf")
    assert_true(species_of("wolf") == WOLF)
    with assert_raises(contains="No species is named"):
        _ = species_of("unicorn")
    with assert_raises(contains="names no species"):
        require_species(SpeciesId(SPECIES_COUNT))
    with assert_raises(contains="names no species"):
        _ = species_name(SpeciesId(-1))
    assert_false(SpeciesId(-1).is_valid())
    # Every species supplies everything the build reads.
    for i in range(SPECIES_COUNT):
        var id = SpeciesId(i)
        assert_true(len(species_variants(id)) > 0)
        var r = body_random(1)
        var t = species_traits(id, r, animal_options(1))
        var rig = species_rig(id, t)
        _ = rig.bone("head")
        var m = SdfModel()
        species_sculpt(id, m, rig, t)
        assert_true(len(m.prims) > 10)
        assert_true(species_eye(id, t).r > 0.0)
        assert_true(species_look(id, t).pupil > 0.0)
        assert_true(len(species_palette(id, t).names) > 0)
        assert_true(species_cell(id) > 0.0)
        assert_true(species_head_origin(id).y > -1.0)
        # Every painter colors every solid of its own sculpt.
        var pal = species_palette(id, t)
        for p in m.prims:
            var sample = CoatSample(
                p.c, V3(0, 1, 0), V3(0, 0, 0), p.tag.value, p.bone.value, p.part
            )
            var paint = species_paint(
                id,
                pal,
                t,
                m.tags[p.tag.value],
                rig.bones[p.bone.value].name,
                sample,
            )
            assert_true(paint.surface.is_valid())


def test_create_animal() raises:
    var wolf = create_animal(WOLF, animal_options(3, quality=CROWD))
    assert_true(len(wolf.model.prims) > 200)
    # The individual is warped: its head stands where its rig says.
    assert_true(wolf.cell > 0.009 and wolf.cell < 0.012)
    assert_true(wolf.eye_cell <= wolf.cell)
    var pup = create_animal(
        WOLF, animal_options(3, age=JUVENILE, sex=MALE, variant=Variant(1))
    )
    assert_true(pup.traits.get("size") < 0.6)
    assert_equal(pup.traits.variant, 1)
    var bind = pup.bind_pose()
    assert_equal(len(bind.local), len(pup.rig.bones))
    with assert_raises(contains="names no species"):
        _ = create_animal(SpeciesId(99), animal_options(1))
    with assert_raises(contains="quality"):
        _ = create_animal(
            WOLF, AnimalOptions(1, Quality(7), ANY_SEX, ANY_AGE, Variant(-1))
        )
    with assert_raises(contains="no such color variant"):
        _ = create_animal(WOLF, animal_options(1, variant=Variant(4)))


def test_thin_parts_inflate_at_coarse_tiers() raises:
    var fine = create_animal(WOLF, animal_options(3, quality=HIGH))
    var coarse = create_animal(WOLF, animal_options(3, quality=CROWD))
    var grew = 0
    for i in range(len(fine.model.prims)):
        grew += Int(coarse.model.prims[i].r.z > fine.model.prims[i].r.z + 1e-9)
    assert_true(grew > 0)


def test_primitive_boxes() raises:
    var m = SdfModel()
    _ = m.sphere("a", BoneId(0), V3(0, 0, 0), 1.0)
    _ = m.cone("b", BoneId(0), V3(0, 0, 0), V3(0, 0, 2), 0.5, 0.25)
    var square: List[Float64] = [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, 1.0]
    _ = m.fin(
        "c", BoneId(0), V3(0, 0, 0), V3(1, 0, 0), V3(0, 1, 0), square, 0.1
    )
    _ = m.lens(
        "d",
        BoneId(0),
        V3(0, 0, 0),
        V3(1, 0, 0),
        V3(0, 1, 0),
        V3(0, 0, 1),
        0.1,
        0.05,
        -0.2,
        0.3,
        carve=True,
    )
    var a = primitive_box(m.prims[0], m.outline)
    assert_equal(a[1].x, 1.0)
    var b = primitive_box(m.prims[1], m.outline)
    assert_equal(b[1].z, 2.5)
    var c = primitive_box(m.prims[2], m.outline)
    assert_almost_equal(c[1].x, 1.6, atol=1e-12)
    var d = primitive_box(m.prims[3], m.outline)
    assert_almost_equal(d[1].x, 0.5, atol=1e-12)
    # A part's box skips carvers and pads by the largest blend.
    var box = part_box(m, [0, 3])
    assert_almost_equal(box[1].x, 1.02, atol=1e-12)


def _tiny() raises -> Animal:
    # A small sculpt on the wolf's painter: a head, a nose on another bone,
    # a jaw, a fur ball on a third bone and the two eyeballs.
    var options = animal_options(1, quality=HIGH)
    var r = body_random(1)
    var t = species_traits(WOLF, r, options)
    var rig = Rig()
    rig.set("occiput", V3(0, 0, 0))
    rig.set("nose", V3(0, 0, 0.2))
    rig.set("neck", V3(0, 0, -0.2))
    rig.set("jawHinge", V3(0, -0.05, 0))
    rig.set("jawTip", V3(0, -0.05, 0.2))
    _ = rig.add_bone("head", "occiput", "nose", "")
    _ = rig.add_bone("jaw", "jawHinge", "jawTip", "head")
    _ = rig.add_bone("neck1", "neck", "occiput", "")
    _ = rig.add_bone("nosebone", "occiput", "nose", "head")
    var m = SdfModel()
    _ = m.sphere("cranium", BoneId(0), V3(0, 0, 0), 0.12, k=0.05)
    _ = m.sphere("nose", BoneId(3), V3(0, 0, 0.15), 0.05, k=0.03)
    _ = m.sphere("ruff", BoneId(2), V3(0, 0, -0.13), 0.1, k=0.05)
    _ = m.sphere("chin", BoneId(1), V3(0, -0.12, 0.05), 0.05, k=0.0, part=JAW)
    # A tongue carved away entirely makes no surface, and a part of
    # carvers alone is not meshed.
    _ = m.sphere("tongue", BoneId(1), V3(0, -0.3, 0), 0.02, k=0.0, part=TONGUE)
    _ = m.sphere(
        "cut", BoneId(1), V3(0, -0.3, 0), 0.05, k=0.0, carve=True, part=TONGUE
    )
    _ = m.sphere("cut", BoneId(1), V3(0, -0.5, 0), 0.05, carve=True, part=HORN)
    _ = m.ell(
        "eyeball",
        BoneId(0),
        V3(0.06, 0.05, 0.07),
        V3(0.03, 0.03, 0.03),
        axis=V3(0.4, 0, 1),
        k=0.0,
        part=EYEBALL,
    )
    var eye = EyeSpec(
        V3(0.06, 0.05, 0.07),
        0.03,
        0.0,
        0.3,
        0.0,
        0.002,
        0.03,
        0.02,
        0.0,
        0.0,
        0.02,
        0.024,
    )
    var look = EyeLook(
        V3(0.3, 0.2, 0.1),
        V3(0.5, 0.3, 0.1),
        V3(0.1, 0.05, 0.02),
        V3(0.8, 0.8, 0.75),
        0.4,
        0.0,
    )
    var pal = species_palette(WOLF, t)
    return Animal(WOLF, options, t^, rig^, m^, pal^, eye, look, 0.03, 0.01)


def test_mesh_a_tiny_animal() raises:
    var animal = _tiny()
    var g = mesh_animal(animal, animal.bind_pose())
    var count = g.vertex_count()
    assert_true(count > 100)
    assert_true(g.has_attribute(String(POSITION)))
    assert_true(g.has_attribute(String(NORMAL)))
    assert_true(g.has_attribute(String(COLOR)))
    # The fur, the nose and the eyes each wear their own material.
    var classes = List[Int]()
    for group in g.groups:
        classes.append(group.material_index.value)
    assert_true(FUR.value in classes)
    assert_true(NOSE.value in classes)
    assert_true(EYE.value in classes)
    # A turned jaw moves its surface, and threads change nothing.
    var pose = animal.bind_pose()
    pose.turn(animal.rig, "jaw", V3(1, 0, 0), 0.4)
    var open = mesh_animal(animal, pose, workers=0)
    assert_true(open.vertex_count() > 100)
    var wrong = Pose(1)
    with assert_raises(contains="another rig"):
        _ = mesh_animal(animal, wrong)


def test_occlusion_bake() raises:
    var animal = _tiny()
    var empty = SurfaceMesh()
    with assert_raises(contains="nothing to occlude"):
        _ = bake_occlusion(animal.model, empty, 0.01, 1)


def test_an_empty_sculpt_makes_no_animal() raises:
    var animal = _tiny()
    animal.model = SdfModel()
    with assert_raises(contains="made no surface"):
        _ = mesh_animal(animal, animal.bind_pose())


def test_inflate_thin() raises:
    var m = SdfModel()
    _inflate_thin(m, 3.0, 0.01)
    var square: List[Float64] = [-1.0, -1.0, 1.0, -1.0, 1.0, 1.0, -1.0, 1.0]
    _ = m.fin(
        "fin",
        BoneId(0),
        V3(0, 0, 0),
        V3(1, 0, 0),
        V3(0, 1, 0),
        square,
        0.002,
        thin=True,
    )
    _ = m.sphere("ear", BoneId(0), V3(0, 0, 0), 0.001, thin=True)
    _ = m.sphere("hole", BoneId(0), V3(0, 0, 0), 0.001, carve=True, thin=True)
    _ = m.sphere("body", BoneId(0), V3(0, 0, 0), 0.001)
    _inflate_thin(m, 1.3, 0.01)
    assert_equal(m.prims[1].r.x, 0.001)
    _inflate_thin(m, 3.0, 0.01)
    assert_almost_equal(m.prims[0].r.x, 0.03, atol=1e-12)
    assert_almost_equal(m.prims[1].r.x, 0.03, atol=1e-12)
    assert_equal(m.prims[2].r.x, 0.001)
    assert_equal(m.prims[3].r.x, 0.001)


def test_empty_boxes_and_geometries() raises:
    var m = SdfModel()
    var box = part_box(m, List[Int]())
    assert_true(box[0].x > box[1].x)
    var surface = SurfaceMesh()
    surface.positions = [Float32(0), 0, 0]
    surface.normals = [Float32(0), 1, 0]
    surface.vertex_block = [0]
    var g = _geometry(surface, [Float32(1), 1, 1], [0])
    assert_equal(len(g.groups), 0)
    var shade = bake_occlusion(m, surface, 0.01, 1)
    assert_equal(shade[0], 1.0)


def test_an_animal_without_bones() raises:
    var animal = _tiny()
    animal.model = SdfModel()
    animal.rig = Rig()
    with assert_raises(contains="made no surface"):
        _ = mesh_animal(animal, Pose(0))


def test_materials() raises:
    var m = animal_materials()
    assert_equal(len(m), SURFACE_CLASS_COUNT)
    for material in m:
        assert_true(material.vertex_colors)


def test_walk_cycle() raises:
    assert_equal(foot_offset(0.0, 0.4, 0.1).z, 0.2)
    assert_equal(foot_offset(0.0, 0.4, 0.1).y, 0.0)
    var mid_swing = foot_offset(DUTY + (1.0 - DUTY) / 2.0, 0.4, 0.1)
    assert_almost_equal(mid_swing.y, 0.1, atol=1e-12)
    assert_almost_equal(mid_swing.z, 0.0, atol=1e-12)
    # The chain reaches a target in reach exactly.
    var turns = solve_two_bone(
        V3(0, 1, 0), V3(0, 0.5, 0.1), V3(0, 0, 0), V3(0, 0.1, 0.1)
    )
    var upper = turns[0]
    var lower = turns[1]
    assert_true(abs(upper) > 0.0 or abs(lower) > 0.0)
    # One out of reach straightens the chain.
    var far = solve_two_bone(
        V3(0, 1, 0), V3(0, 0.5, -0.1), V3(0, 0, 0), V3(0, -5, 0)
    )
    assert_true(abs(far[1]) > 0.0)
    var wolf = create_animal(WOLF, animal_options(3))
    assert_true(is_quadruped(wolf.rig))
    var pose = walk_pose(wolf.rig, 0.3)
    var world = pose.world(wolf.rig)
    assert_equal(len(world), len(wolf.rig.bones))
    var back = walk_pose(wolf.rig, -0.7)
    assert_almost_equal(back.root.t.y, pose.root.t.y, atol=1e-12)
    var rig = Rig()
    rig.set("a", V3(0, 0, 0))
    rig.set("b", V3(0, 1, 0))
    _ = rig.add_bone("head", "a", "b", "")
    assert_false(is_quadruped(rig))
    assert_equal(len(walk_pose(rig, 0.5).local), 1)


def test_two_bone_reaches_the_projected_target() raises:
    var root = V3(0, 1, 0)
    var mid = V3(0, 0.5, 0.1)
    var end = V3(0, 0, 0)
    for target in [V3(0, 0.1, 0.1), V3(0, -5, 0), root]:
        var turns = solve_two_bone(root, mid, end, target)
        var upper = rotation_about(root, V3(1, 0, 0), turns[0])
        var lower = rotation_about(mid, V3(1, 0, 0), turns[1]).then(upper)
        var actual = lower.apply(end)
        var offset = target - root
        var distance = length(offset)
        var reach = min(distance, length(mid - root) + length(end - mid))
        var expected = root if distance == 0.0 else root + offset * (
            reach / distance
        )
        assert_almost_equal(actual.y, expected.y, atol=1e-9)
        assert_almost_equal(actual.z, expected.z, atol=1e-9)
    # Unequal links cannot reach inside their inner radius either.
    var bent = V3(0, 0.7, 0)
    var target = V3(0, 0.9, 0)
    var turns = solve_two_bone(root, bent, end, target)
    var upper = rotation_about(root, V3(1, 0, 0), turns[0])
    var lower = rotation_about(bent, V3(1, 0, 0), turns[1]).then(upper)
    assert_almost_equal(lower.apply(end).y, 0.6, atol=1e-9)
    with assert_raises(contains="planar length"):
        _ = solve_two_bone(root, root, end, target)
    with assert_raises(contains="planar length"):
        _ = solve_two_bone(root, mid, mid, target)
    with assert_raises(contains="planar length"):
        _ = solve_two_bone(
            V3(0, 1e308, 0), V3(0, 0, 0), V3(0, -1e308, 0), target
        )
    var inf = 1e300 * 1e300
    for bad in [V3(inf, 0, 0), V3(0, inf, 0), V3(0, 0, inf)]:
        with assert_raises(contains="finite"):
            _ = solve_two_bone(root, mid, end, bad)


def test_two_bone_scales_without_squared_overflow() raises:
    # Angles are scale invariant. Raw squared lengths overflow at this
    # scale even though every input and the requested solution is finite.
    var a = V3(0, 1, 0)
    var b = V3(0, 0.5, 0.1)
    var c = V3(0, 0, 0)
    var target = V3(0, 0.1, 0.1)
    var ordinary = solve_two_bone(a, b, c, target)
    var large = solve_two_bone(a * 1e160, b * 1e160, c, target * 1e160)
    assert_almost_equal(large[0], ordinary[0], atol=1e-12)
    assert_almost_equal(large[1], ordinary[1], atol=1e-12)
    var tiny = solve_two_bone(a * 1e-160, b * 1e-160, c, target * 1e-160)
    assert_almost_equal(tiny[0], ordinary[0], atol=1e-12)
    assert_almost_equal(tiny[1], ordinary[1], atol=1e-12)
    assert_almost_equal(_reach_along(5e160, 3e160) / 1e160, 4.0, atol=1e-12)
    assert_almost_equal(_reach_along(5e-160, 3e-160) / 1e-160, 4.0, atol=1e-12)
    # Finite endpoints can still have an unrepresentable displacement.
    with assert_raises(contains="target displacement"):
        _ = solve_two_bone(
            V3(0, 1e308, 0), V3(0, 9e307, 0), V3(0, 8e307, 0), V3(0, -1e308, 0)
        )


def test_two_bone_refuses_unrepresentable_ratios_and_solutions() raises:
    # The upper link is too small beside the lower for their ratio.
    with assert_raises(contains="numeric range"):
        _ = solve_two_bone(
            V3(0, 0, 0), V3(0, 1e-150, 0), V3(0, 1e200, 0), V3(0, 0, 0)
        )
    # The solved middle joint lands past the largest Float64, in y and
    # then in z alone.
    for axis in [V3(0, 1, 0), V3(0, 0, 1)]:
        with assert_raises(contains="finite coordinates"):
            _ = solve_two_bone(
                axis * 1.5e308, axis * 6e307, axis * -2e307, axis * 1.79e308
            )


def test_equal_links_walk_without_an_inner_radius() raises:
    var wolf = create_animal(WOLF, animal_options(3, quality=CROWD))
    var x = wolf.rig.j("shoulderL").x
    wolf.rig.set("shoulderL", V3(x, 0.75, 0.5))
    wolf.rig.set("elbowL", V3(x, 0.5, 0.625))
    wolf.rig.set("wristL", V3(x, 0.25, 0.5))
    var stride = Float64(walk_stride(wolf.rig).to(METER))
    assert_true(stride >= 0.0 and isfinite(stride))


def test_walk_stance_feet_hold_height_for_each_quadruped() raises:
    # Check actual forward kinematics, not just nonzero joint angles.
    # All species are built, but this test does not mesh their surfaces.
    for species in range(SPECIES_COUNT):
        var animal = create_animal(
            SpeciesId(species), animal_options(3, quality=CROWD)
        )
        if not is_quadruped(animal.rig):
            continue
        var stride = Float64(walk_stride(animal.rig).to(METER))
        var hip = Length(Float32(animal.rig.j("hipL").y), METER)
        assert_true(stride >= 0.0)
        assert_true(
            stride <= Float64(stride_length(WALK_FROUDE, hip).to(METER)) + 1e-6
        )
        for frame in range(32):
            var phase = Float64(frame) / 32.0
            var pose = walk_pose(animal.rig, phase)
            var world = pose.world(animal.rig)
            for foot in range(4):
                var front = foot < 2
                var side = String("L") if foot % 2 == 0 else String("R")
                var phases: List[Float64] = [WALK_FL, WALK_FR, WALK_HL, WALK_HR]
                var local = phase + phases[foot]
                local -= floor(local)
                if local >= DUTY:
                    continue
                var bone = animal.rig.bone(
                    (String("metacarpus") if front else String("metatarsus"))
                    + side
                )
                var point = animal.rig.j(
                    (String("mcp") if front else String("mtp")) + side
                )
                var actual = world[bone.value].apply(point)
                assert_almost_equal(actual.y, point.y, atol=1e-7)
                var offset = foot_offset(local, stride * DUTY, 0.0)
                assert_almost_equal(actual.z, point.z + offset.z, atol=1e-7)


def test_walk_respects_the_inner_reach_of_folded_legs() raises:
    var animal = create_animal(WOLF, animal_options(3, quality=CROWD))
    var rig = animal.rig.copy()
    for front in [True, False]:
        for side in [String("L"), String("R")]:
            var x = 0.1 if side == "L" else -0.1
            rig.set(
                (String("shoulder") if front else String("hip")) + side,
                V3(x, 1.0, 0.0),
            )
            rig.set(
                (String("elbow") if front else String("knee")) + side,
                V3(x, 0.2, 0.1),
            )
            rig.set(
                (String("wrist") if front else String("hock")) + side,
                V3(x, 0.9, 0.1),
            )
    var sweep = DUTY * Float64(walk_stride(rig).value)
    assert_true(sweep > 0.0 and sweep < 0.2)
    for frame in range(32):
        var phase = Float64(frame) / 32.0
        var world = walk_pose(rig, phase).world(rig)
        for foot in range(4):
            var front = foot < 2
            var side = String("L") if foot % 2 == 0 else String("R")
            var phases: List[Float64] = [WALK_FL, WALK_FR, WALK_HL, WALK_HR]
            var local = phase + phases[foot]
            local -= floor(local)
            if local >= DUTY:
                continue
            var bone = rig.bone(
                (String("metacarpus") if front else String("metatarsus")) + side
            )
            var p = rig.j((String("mcp") if front else String("mtp")) + side)
            var moved = world[bone.value].apply(p)
            assert_almost_equal(moved.y, p.y, atol=1e-7)
            assert_almost_equal(
                moved.z, p.z + foot_offset(local, sweep, 0.0).z, atol=1e-7
            )


def test_walk_time_uses_each_animals_frequency_and_wraps() raises:
    var frequencies = List[Float64]()
    for name in [String("horse"), String("dog")]:
        var animal = create_animal(
            species_of(name), animal_options(3, quality=CROWD)
        )
        var hip = Length(Float32(animal.rig.j("hipL").y), METER)
        var f = Float64(stride_frequency(WALK_FROUDE, hip).value)
        frequencies.append(f)
        var timed = walk_pose_at(animal.rig, Duration(0.25, SECOND))
        var expected = walk_pose(animal.rig, 0.25 * f)
        var a = timed.world(animal.rig)
        var b = expected.world(animal.rig)
        for i in range(len(a)):
            assert_almost_equal(a[i].t.y, b[i].t.y, atol=1e-12)
            assert_almost_equal(a[i].t.z, b[i].t.z, atol=1e-12)
        # The foot paths and world transforms meet at the cycle seam.
        var before = walk_pose(animal.rig, -1e-8)
        var after = walk_pose(animal.rig, 1e-8)
        var left = before.world(animal.rig)
        var right = after.world(animal.rig)
        for i in range(len(left)):
            assert_almost_equal(left[i].t.y, right[i].t.y, atol=1e-6)
            assert_almost_equal(left[i].t.z, right[i].t.z, atol=1e-6)
    assert_true(frequencies[1] > frequencies[0])
    var bare = Rig()
    assert_equal(walk_stride(bare).value, Float32(0.0))
    assert_equal(len(walk_pose_at(bare, Duration(0.25, SECOND)).local), 0)
    var inf = 1e300 * 1e300
    with assert_raises(contains="time must be finite"):
        _ = walk_pose_at(bare, Duration(Float32(inf), SECOND))
    var wolf = create_animal(WOLF, animal_options(3, quality=CROWD))
    with assert_raises(contains="phase must be finite"):
        _ = walk_pose(wolf.rig, inf)


def test_undulation() raises:
    var rig = Rig()
    for i in range(7):
        rig.set("v" + String(i), V3(0, 0.1, -0.1 * Float64(i)))
    for i in range(6):
        _ = rig.add_bone(
            "spine" + String(i),
            "v" + String(i),
            "v" + String(i + 1),
            "" if i == 0 else "spine" + String(i - 1),
        )
    _ = rig.add_bone("head", "v0", "v1", "spine0")
    assert_equal(spine_count(rig), 6)
    var pose = undulate_pose(rig, 0.25)
    var world = pose.world(rig)
    # The tail swings off the line; the root stays put.
    var tail = world[5].apply(V3(0, 0.1, -0.6))
    assert_true(abs(tail.x) > 0.01)
    assert_equal(world[0].apply(V3(0, 0.1, 0)).x, 0.0)
    # A rig without a spine chain stays in its bind pose.
    var bare = Rig()
    bare.set("a", V3(0, 0, 0))
    bare.set("b", V3(0, 1, 0))
    _ = bare.add_bone("head", "a", "b", "")
    assert_equal(spine_count(bare), 0)
    assert_equal(len(undulate_pose(bare, 0.5).local), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
