# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.morph_blend_mesh`, `objects.morph_anim_mesh` and
`objects.md2_character`.

`assets/md2/characters.json` holds what three.js r180's `MorphBlendMesh`,
`MorphAnimMesh`, `MD2Character` and `MD2CharacterComplex` do with
`fixture.md2` and `many.md2`, run in Node by `three_characters.mjs` beside
it. Each test here takes the same steps.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import MeshIndex
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from loaders.json import JsonDocument, parse_json
from loaders.md2 import Md2Model, md2_clip, read_md2
from materials.material import Material
from objects.md2_character import (
    MD2Character,
    MD2CharacterComplex,
    Md2AnimationNames,
    Md2Controls,
)
from objects.mesh import Mesh
from objects.morph_anim_mesh import MorphAnimMesh
from objects.morph_blend_mesh import (
    DEFAULT_ANIMATION,
    MorphBlendMesh,
    js_remainder,
)
from render.framebuffer import Color
from render.texture import Texture
from render.texture_store import NO_TEXTURE, TextureId
from std.math import inf, isnan
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    Duration,
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Velocity,
)

comptime TOLERANCE = Float64(1e-5)


def _reference() raises -> JsonDocument:
    """Return what three.js did.

    Returns:
        The parsed file.

    Raises:
        Error: If the file cannot be read.
    """
    return parse_json(Path("assets/md2/characters.json").read_text())


def _entry(doc: JsonDocument, section: String) raises -> Int:
    """Return a top-level entry of the reference."""
    return doc.get(doc.root(), section)


def _assert_weights(
    scene: Scene, mesh: Int, doc: JsonDocument, want: Int
) raises:
    """Assert a mesh's morph weights match a list of the reference.

    Args:
        scene: The scene.
        mesh: Which of its meshes.
        doc: The reference.
        want: The list.

    Raises:
        Error: If a weight differs.
    """
    for at in range(doc.length(want)):
        assert_almost_equal(
            Float64(scene.meshes[mesh].morph_influence(at)),
            doc.number(doc.at(want, at)),
            atol=TOLERANCE,
        )


def _fixture() raises -> Md2Model:
    """Return `fixture.md2`."""
    return read_md2("assets/md2/fixture.md2")


def _one_mesh(model: Md2Model) raises -> Tuple[Scene, Assets]:
    """Return a scene of one mesh wearing a model's geometry, its morph
    targets named."""
    var scene = Scene()
    var assets = Assets()
    var shape = assets.geometries.add(model.geometry.clone())
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    var mesh = Mesh(shape, paint, scene.add(Object3D()))
    mesh.update_morph_targets(assets.geometries.get(shape))
    scene.add_mesh(mesh)
    scene.update()
    return (scene^, assets^)


# --- MorphBlendMesh ---------------------------------------------------------


def test_a_blend_mesh_finds_its_animations() raises:
    var made = _one_mesh(_fixture())
    ref scene = made[0]
    var blend = MorphBlendMesh(MeshIndex(0), scene)
    blend.auto_create_animations(scene, 6)
    var doc = _reference()
    var section = _entry(doc, "blend")
    assert_equal(blend.first_animation, doc.string(doc.get(section, "first")))
    var list = doc.get(section, "animations")
    assert_equal(len(blend.animations), doc.length(list))
    for at in range(len(blend.animations)):
        var want = doc.at(list, at)
        ref got = blend.animations[at]
        assert_equal(got.name, doc.string(doc.get(want, "name")))
        assert_equal(got.start, doc.integer(doc.get(want, "start")))
        assert_equal(got.end, doc.integer(doc.get(want, "end")))
        assert_almost_equal(got.fps, doc.number(doc.get(want, "fps")))
        assert_almost_equal(
            got.duration, doc.number(doc.get(want, "duration")), atol=TOLERANCE
        )
    assert_equal(blend.animations[0].name, DEFAULT_ANIMATION)


def test_a_blend_mesh_plays_forward_back_and_back_and_forth() raises:
    var made = _one_mesh(_fixture())
    ref scene = made[0]
    var blend = MorphBlendMesh(MeshIndex(0), scene)
    blend.auto_create_animations(scene, 6)
    var doc = _reference()
    var steps = doc.get(_entry(doc, "blend"), "steps")
    assert_true(blend.play_animation("run"))
    blend.set_animation_weight("run", 0.8)
    var deltas: List[Float64] = [0.1, 0.15, 0.2, 0.1, 0.25, 0.2, 0.3, 0.3]
    for at in range(len(deltas)):
        if at == 3:
            blend.set_animation_direction_backward("run")
        if at == 5:
            blend.set_animation_direction_forward("run")
            blend.animations[2].mirrored_loop = True
        blend.update(scene, deltas[at])
        _assert_weights(scene, 0, doc, doc.at(steps, at))


def test_a_blend_mesh_passes_over_a_name_it_has_not() raises:
    var made = _one_mesh(_fixture())
    ref scene = made[0]
    var blend = MorphBlendMesh(MeshIndex(0), scene)
    assert_false(blend.play_animation("fly"))
    blend.stop_animation("fly")
    blend.set_animation_direction_forward("fly")
    blend.set_animation_direction_backward("fly")
    blend.set_animation_fps("fly", 3)
    blend.set_animation_duration("fly", 3)
    blend.set_animation_weight("fly", 3)
    blend.set_animation_time("fly", 3)
    assert_equal(blend.get_animation_time("fly"), 0)
    assert_equal(blend.get_animation_duration("fly"), -1)
    # The default plays every target once a second.
    blend.set_animation_fps(DEFAULT_ANIMATION, 14)
    assert_almost_equal(blend.get_animation_duration(DEFAULT_ANIMATION), 0.5)
    blend.set_animation_duration(DEFAULT_ANIMATION, 1.75)
    assert_almost_equal(blend.animations[0].fps, 4)
    blend.set_animation_time(DEFAULT_ANIMATION, 0.5)
    assert_almost_equal(blend.get_animation_time(DEFAULT_ANIMATION), 0.5)
    assert_true(blend.play_animation(DEFAULT_ANIMATION))
    blend.stop_animation(DEFAULT_ANIMATION)
    assert_false(blend.animations[0].active)
    with assert_raises(contains="not a number"):
        blend.update(scene, inf[DType.float64]())
    var none = MorphBlendMesh(MeshIndex(0), scene)
    none.mesh = MeshIndex(4)
    with assert_raises(contains="scene's meshes"):
        none.update(scene, 0.1)
    with assert_raises(contains="scene's meshes"):
        _ = MorphBlendMesh(MeshIndex(-1), scene)


def test_a_blend_mesh_of_no_targets_sets_none() raises:
    var scene = Scene()
    var assets = Assets()
    var shape = assets.geometries.add(_fixture().geometry.clone())
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    # No `update_morph_targets`: the mesh names no target.
    scene.add_mesh(Mesh(shape, paint, scene.add(Object3D())))
    var blend = MorphBlendMesh(MeshIndex(0), scene)
    assert_true(blend.play_animation(DEFAULT_ANIMATION))
    blend.update(scene, 0.1)
    assert_equal(len(scene.meshes[0].morph_influences), 0)


def test_js_remainder_takes_the_sign_of_the_dividend() raises:
    assert_almost_equal(js_remainder(-0.25, 1), -0.25)
    assert_almost_equal(js_remainder(1.25, 1), 0.25)
    assert_almost_equal(js_remainder(-1.25, -1), -0.25)
    assert_equal(js_remainder(0, 1), 0)
    assert_true(isnan(js_remainder(1, 0)))


# --- MorphAnimMesh ----------------------------------------------------------


def test_a_morph_anim_mesh_plays_one_clip() raises:
    var model = _fixture()
    var made = _one_mesh(model)
    ref scene = made[0]
    var clips = List[AnimationClip]()
    for at in range(len(model.animations)):
        if len(model.animations[at].frames) >= 3:
            clips.append(md2_clip(model, at, MeshIndex(0), 10))
    var anim = MorphAnimMesh(MeshIndex(0), clips^)
    var doc = _reference()
    var steps = doc.get(_entry(doc, "anim"), "steps")
    anim.play_animation("run", 6)
    anim.update_animation(scene, Duration(0.05, SECOND))
    _assert_weights(scene, 0, doc, doc.at(steps, 0))
    anim.update_animation(scene, Duration(0.1, SECOND))
    _assert_weights(scene, 0, doc, doc.at(steps, 1))
    anim.set_direction_backward()
    anim.update_animation(scene, Duration(0.07, SECOND))
    _assert_weights(scene, 0, doc, doc.at(steps, 2))
    anim.set_direction_forward()
    anim.play_animation("stand", 4)
    anim.update_animation(scene, Duration(0.1, SECOND))
    _assert_weights(scene, 0, doc, doc.at(steps, 3))
    # Played again, a clip keeps its one action.
    anim.play_animation("run", 6)
    assert_equal(anim.mixer.action_count(), 2)
    with assert_raises(contains="is not a clip"):
        anim.play_animation("fly", 6)
    assert_equal(anim.active, -1)


# --- MD2Character -----------------------------------------------------------


def _skins(mut assets: Assets, count: Int) -> List[TextureId]:
    """Return blank textures, one a skin."""
    var out = List[TextureId]()
    for _ in range(count):
        out.append(assets.textures.add(Texture()))
    return out^


def test_a_character_plays_its_body_and_its_weapon_in_step() raises:
    var scene = Scene()
    var assets = Assets()
    var weapons = List[Md2Model]()
    weapons.append(_fixture())
    weapons.append(read_md2("assets/md2/many.md2"))
    var names: List[String] = ["fixture.md2", "many.md2"]
    var character = MD2Character(
        scene,
        assets,
        _fixture(),
        weapons,
        names,
        _skins(assets, 2),
        _skins(assets, 2),
        scale=2,
    )
    scene.update()
    var doc = _reference()
    var section = _entry(doc, "character")
    var root = doc.get(section, "root")
    assert_almost_equal(
        Float64(scene.get(character.root).position.y),
        doc.number(doc.at(root, 1)),
        atol=TOLERANCE,
    )
    assert_equal(
        character.active_animation_clip_name,
        doc.string(doc.get(section, "first")),
    )
    assert_equal(scene.get(character.weapons[1].node).name, "many.md2")
    assert_equal(character.weapon, 1)
    var steps = doc.get(section, "steps")
    var deltas: List[Float32] = [0.3, 0.2, 0.1, 0.15]
    for at in range(4):
        if at == 0:
            character.set_animation("stand")
        elif at == 1:
            character.set_weapon(scene, 0)
        elif at == 2:
            character.set_playback_rate(2)
        else:
            character.set_animation("run")
        character.update(scene, Duration(deltas[at], SECOND))
        var step = doc.at(steps, at)
        _assert_weights(scene, character.body.mesh, doc, doc.get(step, "body"))
        var held = doc.get(step, "weapons")
        for which in range(2):
            _assert_weights(
                scene,
                character.weapons[which].mesh,
                doc,
                doc.at(held, which),
            )
    assert_true(scene.get(character.weapons[0].node).visible)
    assert_false(scene.get(character.weapons[1].node).visible)


def test_a_character_wears_a_skin_or_a_wireframe() raises:
    var scene = Scene()
    var assets = Assets()
    var weapons = List[Md2Model]()
    weapons.append(_fixture())
    var names: List[String] = ["w"]
    var skins = _skins(assets, 2)
    var character = MD2Character(
        scene,
        assets,
        _fixture(),
        weapons,
        names,
        skins.copy(),
        _skins(assets, 1),
        parent=scene.add(Object3D()),
    )
    ref body = character.body
    assert_equal(scene.meshes[body.mesh].material, body.textured)
    assert_equal(assets.materials.get(body.textured).map, skins[0])
    character.set_skin(scene, assets, 1)
    assert_equal(assets.materials.get(body.textured).map, skins[1])
    character.set_skin(scene, assets, 5)
    assert_equal(assets.materials.get(body.textured).map, NO_TEXTURE)
    character.set_wireframe(scene, True)
    assert_equal(scene.meshes[body.mesh].material, body.wireframe)
    assert_equal(
        scene.meshes[character.weapons[0].mesh].material,
        character.weapons[0].wireframe,
    )
    assert_true(assets.materials.get(body.wireframe).wireframe)
    # A wireframe keeps its skin.
    character.set_skin(scene, assets, 0)
    assert_equal(assets.materials.get(body.textured).map, NO_TEXTURE)
    character.set_wireframe(scene, False)
    assert_equal(scene.meshes[body.mesh].material, body.textured)
    # A weapon past the end hides them all.
    character.set_weapon(scene, 3)
    assert_false(scene.get(character.weapons[0].node).visible)
    character.set_playback_rate(0)
    assert_equal(character.mixer.time_scale, 0)
    # A clip no part has plays nothing.
    character.set_animation("fly")
    assert_equal(character.body_action, -1)
    with assert_raises(contains="one name a weapon"):
        _ = MD2Character(
            scene,
            assets,
            _fixture(),
            weapons,
            List[String](),
            List[TextureId](),
            List[TextureId](),
        )


def test_a_character_without_a_weapon_plays_its_body() raises:
    var scene = Scene()
    var assets = Assets()
    var character = MD2Character(
        scene,
        assets,
        _fixture(),
        List[Md2Model](),
        List[String](),
        List[TextureId](),
        List[TextureId](),
    )
    assert_equal(character.weapon, -1)
    assert_equal(
        assets.materials.get(character.body.textured).map, NO_TEXTURE
    )
    character.set_animation("run")
    character.set_wireframe(scene, True)
    character.update(scene, Duration(0.1, SECOND))
    assert_true(character.body_action >= 0)


# --- MD2CharacterComplex ----------------------------------------------------


def _names() -> Md2AnimationNames:
    """Return the animations three.js's reference asks for."""
    return Md2AnimationNames(
        "run", "stand", "run", "stand", "run", "stand", "run"
    )


def test_a_complex_character_moves_and_blends() raises:
    var scene = Scene()
    var assets = Assets()
    var weapons = List[Md2Model]()
    weapons.append(_fixture())
    var names: List[String] = ["fixture.md2"]
    var character = MD2CharacterComplex(
        scene,
        assets,
        _fixture(),
        weapons,
        names,
        _skins(assets, 1),
        _skins(assets, 1),
        animations=_names(),
        walk_speed=Velocity(300.0, METER_PER_SECOND),
        crouch_speed=Velocity(150.0, METER_PER_SECOND),
        scale=2,
    )
    character.controls = Md2Controls()
    var doc = _reference()
    var steps = doc.get(_entry(doc, "complex"), "steps")
    var deltas: List[Float32] = [0.1, 0.1, 0.1, 0.05, 0.1, 0.2, 0.1, 0.3]
    for at in range(len(deltas)):
        var asked = Md2Controls()
        asked.move_forward = at < 3
        asked.move_left = at == 2
        asked.move_backward = at == 3
        asked.crouch = at == 6
        asked.move_right = at == 6
        character.controls = asked^
        character.update(scene, Duration(deltas[at], SECOND))
        var step = doc.at(steps, at)
        ref placed = scene.get(character.root).position
        var position = doc.get(step, "position")
        assert_almost_equal(
            Float64(placed.x), doc.number(doc.at(position, 0)), atol=1e-3
        )
        assert_almost_equal(
            Float64(placed.z), doc.number(doc.at(position, 2)), atol=1e-3
        )
        assert_almost_equal(
            Float64(character.body_orientation.to(RADIAN)),
            doc.number(doc.get(step, "turn")),
            atol=TOLERANCE,
        )
        assert_almost_equal(
            Float64(character.speed.to(METER_PER_SECOND)),
            doc.number(doc.get(step, "speed")),
            atol=1e-3,
        )
        assert_equal(
            character.active_animation, doc.string(doc.get(step, "active"))
        )
        _assert_weights(scene, character.body.mesh, doc, doc.get(step, "body"))


def test_a_complex_character_crouches_jumps_and_attacks() raises:
    var scene = Scene()
    var assets = Assets()
    var weapons = List[Md2Model]()
    weapons.append(_fixture())
    var names: List[String] = ["w"]
    var picks = Md2AnimationNames(
        "move", "idle", "jump", "attack", "crouch_move", "crouch_idle", "ca"
    )
    var character = MD2CharacterComplex(
        scene,
        assets,
        _fixture(),
        weapons,
        names,
        _skins(assets, 2),
        _skins(assets, 1),
        animations=picks,
    )
    var cases: List[Tuple[Bool, Bool, Bool, Bool, String]] = [
        (False, False, False, False, "idle"),
        (True, False, False, True, "crouch_move"),
        (False, True, False, True, "jump"),
        (False, False, True, True, "attack"),
        (True, False, True, True, "ca"),
        (True, False, False, False, "crouch_idle"),
    ]
    for at in range(len(cases)):
        var asked = Md2Controls()
        asked.crouch = cases[at][0]
        asked.jump = cases[at][1]
        asked.attack = cases[at][2]
        asked.move_forward = cases[at][3]
        character.controls = asked^
        character.speed = Velocity(0.0, METER_PER_SECOND)
        character.update_behaviors()
        assert_equal(character.active_animation, cases[at][4])
    # Asked again, the active animation is kept, and an empty one ignored.
    character.set_animation("crouch_idle")
    character.set_animation("")
    assert_equal(character.active_animation, "crouch_idle")
    # The weapon takes the body's animation and its time.
    character.set_weapon(scene, 0)
    assert_true(scene.get(character.weapons[0].node).visible)
    character.set_weapon(scene, 4)
    assert_false(scene.get(character.weapons[0].node).visible)
    character.enable_shadows(scene, True)
    assert_true(scene.meshes[character.body.mesh].cast_shadow)
    character.set_visible(scene, False)
    assert_false(scene.get(character.body.node).visible)
    character.set_skin(scene, assets, 1)
    assert_equal(character.current_skin, 1)
    character.set_wireframe(scene, True)
    character.set_skin(scene, assets, 0)
    assert_equal(character.current_skin, 1)
    character.set_wireframe(scene, False)
    # With no controls it stands; with no animations it plays none.
    character.controls = None
    character.update_behaviors()
    character.update_movement_model(scene, Duration(0.1, SECOND))
    var still = MD2CharacterComplex(
        scene,
        assets,
        _fixture(),
        List[Md2Model](),
        List[String](),
        List[TextureId](),
        List[TextureId](),
    )
    still.controls = Md2Controls()
    still.update(scene, Duration(0.1, SECOND))
    still.set_animation("run")
    still.set_weapon(scene, 0)
    still.update_animations(scene, Duration(0.1, SECOND))
    assert_equal(still.weapon, -1)
    with assert_raises(contains="one name a weapon"):
        _ = MD2CharacterComplex(
            scene,
            assets,
            _fixture(),
            weapons,
            List[String](),
            List[TextureId](),
            List[TextureId](),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
