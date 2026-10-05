# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Muscle bellies that bulge in a pose, and engineering mode's skin,
skeleton and muscle layers."""

from extensions.anatomy.mode import ENGINEERING_MODE, GAME_MODE, AnatomyMode
from extensions.animals.anatomy.body import MAMMAL
from extensions.animals.anatomy.flex import (
    fiber_ratio,
    flexed,
    flexed_animal,
)
from extensions.animals.anatomy.muscles import AnimalMuscle, animal_muscles
from extensions.animals.anatomy.mass import sample_mass
from extensions.animals.anatomy.render import (
    _skin_layer,
    BONE_LAYER,
    MUSCLE_LAYER,
    SKIN_LAYER,
    anatomy_layers,
    anatomy_materials,
    materials_in_mode,
    mesh_in_mode,
    muscle_model,
    skeleton_model,
)
from extensions.animals.build import Animal, create_animal, mesh_animal
from extensions.animals.gait import walk_pose
from extensions.animals.options import ADULT, CROWD, MALE, animal_options
from extensions.animals.registry import RAT, species_of
from extensions.sdf.ids import CONE, ELLIPSOID, LENS, BoneId, TagId
from extensions.sdf.field import SdfModel
from extensions.animals.parts import BODY, JAW
from core.buffer_geometry import NORMAL, POSITION
from extensions.sdf.vector import V3
from extensions.animals.warp import Warps
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import KILOGRAM, METER, Length, Mass


def _rat() raises -> Animal:
    return create_animal(
        RAT, animal_options(2, quality=CROWD, sex=MALE, age=ADULT)
    )


def test_bellies_keep_their_shape_standing_and_bulge_when_short() raises:
    var rat = _rat()
    var muscles = animal_muscles(rat.rig, MAMMAL, Mass(0.3, KILOGRAM))
    var bind = rat.bind_pose()
    var world = bind.world(rat.rig)
    for m in muscles:
        assert_almost_equal(fiber_ratio(m, world), 1.0, atol=1e-5)
    var still = flexed(rat, muscles, bind)
    for i in range(len(still.prims)):
        var a = still.prims[i].r
        var b = rat.model.prims[i].r
        assert_almost_equal(a.x, b.x, rtol=1e-5)
        assert_almost_equal(a.z, b.z, rtol=1e-5)
    # A deep crouch shortens the hamstrings and the calf to the limit.
    var crouch = rat.bind_pose()
    for side in ["L", "R"]:
        crouch.turn(rat.rig, "tibia" + side, V3(1, 0, 0), 2.4)
        crouch.turn(rat.rig, "femur" + side, V3(1, 0, 0), -1.2)
    var bent = crouch.world(rat.rig)
    var short = 2.0
    for m in muscles:
        short = min(short, fiber_ratio(m, bent))
    assert_almost_equal(short, 0.6)
    # A hip swung far back stretches the rectus femoris to the limit.
    var reach = rat.bind_pose()
    for side in ["L", "R"]:
        reach.turn(rat.rig, "femur" + side, V3(1, 0, 0), 1.6)
    var stretched = reach.world(rat.rig)
    var long = 0.0
    for m in muscles:
        long = max(long, fiber_ratio(m, stretched))
    assert_almost_equal(long, 1.4)
    var bulged = flexed(rat, muscles, crouch)
    var changed = 0
    for i in range(len(bulged.prims)):
        ref p = bulged.prims[i]
        var before = rat.model.prims[i].r
        if p.r.x != before.x or p.r.y != before.y or p.r.z != before.z:
            changed += 1
            assert_true(p.kind == ELLIPSOID or p.kind == CONE)
            if p.kind == ELLIPSOID:
                assert_almost_equal(
                    p.r.x * p.r.y * p.r.z,
                    before.x * before.y * before.z,
                    rtol=1e-12,
                )
            else:
                # The visual cone bulge changes radii, not its endpoints.
                assert_equal(p.c.y, rat.model.prims[i].c.y)
                assert_equal(p.b.y, rat.model.prims[i].b.y)
    assert_true(changed > 0)
    # Without muscles, nothing changes shape.
    var none = flexed(rat, List[AnimalMuscle](), crouch)
    assert_equal(len(none.prims), len(rat.model.prims))
    # A sculpt with no solids has nothing to check or shape.
    var bare = _rat()
    bare.model = SdfModel()
    assert_equal(len(flexed(bare, List[AnimalMuscle](), crouch).prims), 0)
    # A lens or a fin keeps its shape even where a belly shows.
    var odd = _rat()
    var lens = -1
    for i in range(len(odd.model.prims)):
        if odd.model.tags[odd.model.prims[i].tag.value] == "calf":
            odd.model.prims[i].kind = LENS
            lens = i
    assert_true(lens >= 0)
    var kept = flexed(odd, muscles, crouch)
    assert_equal(kept.prims[lens].r.x, odd.model.prims[lens].r.x)
    var walk = walk_pose(rat.rig, 0.4)
    var visual = flexed_animal(rat, muscles, walk)
    assert_equal(visual.traits.get("anatomy_visual_flex", 0.0), 1.0)
    assert_equal(rat.traits.get("anatomy_visual_flex", 0.0), 0.0)
    with assert_raises(contains="Visual flex"):
        _ = sample_mass(visual, walk, Length(0.02, METER))
    var mesh = mesh_animal(visual, walk)
    assert_true(mesh.vertex_count() > 100)


def test_skeleton_and_muscles_are_solids() raises:
    var rat = _rat()
    var bones = skeleton_model(rat)
    assert_true(len(bones.prims) > 20)
    for p in bones.prims:
        assert_equal(p.kind, CONE)
        assert_true(p.r.x > 0.0)
    # A bone of no length draws nothing.
    var flat = _rat()
    var tail = flat.rig.find_joint("tail1")
    flat.rig.joints[tail] = flat.rig.joints[flat.rig.find_joint("tail0")]
    assert_equal(len(skeleton_model(flat).prims), len(bones.prims) - 1)
    # A spider's legs are tubes of cuticle; flight feathers and fins
    # have no bone here.
    for name in ["spider", "crow", "fish"]:
        var other = create_animal(
            species_of(name), animal_options(2, quality=CROWD)
        )
        var skeleton = skeleton_model(other)
        assert_true(len(skeleton.prims) > 0)
        assert_true(len(skeleton.prims) <= len(other.rig.bones))
        if name != "spider":
            assert_true(len(skeleton.prims) < len(other.rig.bones))
    var muscles = animal_muscles(rat.rig, MAMMAL, Mass(0.3, KILOGRAM))
    assert_equal(
        len(muscle_model(rat, List[AnimalMuscle](), rat.bind_pose()).prims), 0
    )
    # A belly whose fibers fill its whole path has no tendon to draw.
    var long = muscles.copy()
    long[0].arch.fiber_length = Length(10.0, METER)
    var bare = muscle_model(rat, long, rat.bind_pose())
    assert_equal(
        len(bare.prims),
        len(muscle_model(rat, muscles, rat.bind_pose()).prims) - 1,
    )
    var flesh = muscle_model(rat, muscles, rat.bind_pose())
    var bellies = 0
    for p in flesh.prims:
        bellies += 1 if p.kind == ELLIPSOID else 0
    assert_equal(bellies, len(muscles))
    # A belly holds its muscle's volume.
    var first = flesh.prims[0]
    var volume = (
        4.0 / 3.0 * 3.141592653589793 * first.r.x * first.r.y * first.r.z
    )
    assert_almost_equal(volume, muscles[0].arch.volume_m3(), rtol=1e-6)


def test_flex_refuses_closed_belly_direction() raises:
    var rat = _rat()
    var muscles = animal_muscles(rat.rig, MAMMAL, Mass(0.3, KILOGRAM))
    # Every segment is nonzero, but the bind path returns to its origin.
    # Such a path has no direction along which the surface can bulge.
    muscles[0].points.append(muscles[0].points[0])
    muscles[0].bones.append(muscles[0].bones[0])
    with assert_raises(contains="distinct bind endpoints"):
        _ = flexed(rat, muscles, rat.bind_pose())


def test_direct_flex_provenance_survives_model_operations() raises:
    var animal = _rat()
    var muscles = animal_muscles(animal.rig, MAMMAL, Mass(0.3, KILOGRAM))
    var pose = animal.bind_pose()
    animal.model = flexed(animal, muscles, pose)
    assert_true(animal.model.visual_only)
    assert_equal(animal.traits.get("anatomy_visual_flex", 0.0), 0.0)
    with assert_raises(contains="Visual flex"):
        _ = sample_mass(animal, pose, Length(0.02, METER))
    var world = pose.world(animal.rig)
    var warps = Warps()
    var copies = List[SdfModel]()
    copies.append(animal.model.copy())
    copies.append(animal.model.moved(world))
    copies.append(warps.warp_model(animal.model))
    for _ in range(3):
        var copied = _rat()
        copied.model = copies.pop(0)
        assert_true(copied.model.visual_only)
        with assert_raises(contains="Visual flex"):
            _ = sample_mass(copied, copied.bind_pose(), Length(0.02, METER))


def test_flex_checks_mutated_bone_and_tag_ids() raises:
    for id in [-1, 10000]:
        var animal = _rat()
        animal.model.prims[0].bone = BoneId(id)
        with assert_raises(contains="names no bone"):
            _ = flexed(animal, List[AnimalMuscle](), animal.bind_pose())
        var tagged = _rat()
        tagged.model.prims[0].tag = TagId(id)
        with assert_raises(contains="names no tag"):
            _ = mesh_in_mode(
                tagged, List[AnimalMuscle](), tagged.bind_pose(), GAME_MODE
            )


def test_engineering_layers_mesh_and_light() raises:
    var rat = _rat()
    var muscles = animal_muscles(rat.rig, MAMMAL, Mass(0.3, KILOGRAM))
    var layers = mesh_in_mode(
        rat, muscles, walk_pose(rat.rig, 0.2), ENGINEERING_MODE, 2
    )
    assert_equal(len(layers), 3)
    for i in [SKIN_LAYER, BONE_LAYER, MUSCLE_LAYER]:
        assert_true(layers[i].vertex_count() > 50)
    with assert_raises(contains="muscles"):
        _ = anatomy_layers(rat, List[AnimalMuscle](), rat.bind_pose())
    var game = mesh_in_mode(rat, muscles, rat.bind_pose(), GAME_MODE, 2)
    assert_equal(len(game), 1)
    assert_equal(len(materials_in_mode(GAME_MODE)), 1)
    assert_equal(len(materials_in_mode(ENGINEERING_MODE)), 3)
    with assert_raises(contains="mode"):
        _ = mesh_in_mode(rat, muscles, rat.bind_pose(), AnatomyMode(7))
    with assert_raises(contains="mode"):
        _ = materials_in_mode(AnatomyMode(-2))
    var looks = anatomy_materials()
    assert_equal(len(looks), 3)
    assert_true(looks[SKIN_LAYER].transparent)
    assert_true(looks[SKIN_LAYER].opacity < 1.0)


def test_engineering_skin_preserves_game_surface_parts() raises:
    var animal = _rat()
    animal.cell = 0.1
    animal.eye_cell = 0.1
    animal.model = SdfModel()
    var bone = animal.rig.bone("pelvis")
    _ = animal.model.sphere("body", bone, V3(0, 0, 0), 0.4, k=0.0, part=BODY)
    # A carver in an otherwise empty JAW part must not cut BODY.
    _ = animal.model.sphere(
        "mouth", bone, V3(0, 0.3, 0), 0.3, k=0.0, carve=True, part=JAW
    )
    var bind = animal.bind_pose()
    var posed = animal.model.moved(bind.world(animal.rig))
    var skin = _skin_layer(animal, posed, 1)
    var game = mesh_animal(animal, bind)
    assert_equal(skin.vertex_count(), game.vertex_count())
    ref skin_positions = skin.attribute_view(String(POSITION))
    ref game_positions = game.attribute_view(String(POSITION))
    for i in range(skin.vertex_count()):
        for axis in range(3):
            assert_equal(
                skin_positions.component(i, axis),
                game_positions.component(i, axis),
            )
    # Separate additive parts stay separate too, with global indices and
    # normals preserved by the surface merge.
    _ = animal.model.sphere("jaw", bone, V3(0, -0.3, 0), 0.2, k=0.1, part=JAW)
    posed = animal.model.moved(bind.world(animal.rig))
    var layered = _skin_layer(animal, posed, 1)
    var painted = mesh_animal(animal, bind)
    assert_equal(layered.vertex_count(), painted.vertex_count())
    for i in layered.index:
        assert_true(i >= 0 and i < layered.vertex_count())
    assert_true(layered.has_attribute(String(NORMAL)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
