# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the property tracks, the bindings, the object groups and the
additive blend mode in `animation`, and for `animation.animation_utils`.
"""

from animation.animation_clip import (
    ADDITIVE_BLEND_MODE,
    AnimationBlendMode,
    AnimationClip,
    NORMAL_BLEND_MODE,
)
from animation.animation_mixer import (
    AnimationAction,
    AnimationMixer,
    Binding,
    add_onto_pile,
    additive_identity,
    check_target,
    checked_value,
    find_target,
    material_number,
    mix_additive_into_pile,
    mix_into_pile,
    read_target,
    rest_into_pile,
    write_target,
)
from animation.animation_object_group import AnimationObjectGroup
from animation.animation_utils import checked_fps, make_clip_additive, subclip
from animation.keyframe_track import (
    Interpolation,
    KeyframeTrack,
    LIGHT_COLOR,
    LIGHT_INTENSITY,
    LINEAR,
    LightIndex,
    MATERIAL_ALPHA_TEST,
    MATERIAL_CLEARCOAT,
    MATERIAL_CLEARCOAT_ROUGHNESS,
    MATERIAL_COLOR,
    MATERIAL_EMISSIVE,
    MATERIAL_EMISSIVE_INTENSITY,
    MATERIAL_ENV_MAP_INTENSITY,
    MATERIAL_IOR,
    MATERIAL_METALNESS,
    MATERIAL_OPACITY,
    MATERIAL_REFLECTIVITY,
    MATERIAL_ROUGHNESS,
    MATERIAL_SHININESS,
    MATERIAL_SPECULAR,
    MATERIAL_SPECULAR_INTENSITY,
    MORPH_INFLUENCE,
    MeshIndex,
    POSITION,
    QUATERNION,
    SCALE,
    STEP,
    TrackKind,
    TrackTarget,
    VISIBLE,
    light_target,
    material_target,
    morph_target,
    node_target,
)
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from materials.material import MAX_IOR, MIN_IOR, Material, MaterialId
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import inf, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, Duration, RADIAN, SECOND

comptime TOLERANCE = Float64(1e-5)


def seconds(values: List[Float32]) -> List[Duration]:
    """Return the given numbers as durations in seconds."""
    var out = List[Duration]()
    for index in range(len(values)):
        out.append(Duration(values[index], SECOND))
    return out^


def at(value: Float32) -> Duration:
    """Return a time in seconds."""
    return Duration(value, SECOND)


def world() raises -> Scene:
    """Return a scene of three nodes: node zero carries mesh zero with
    material zero and a directional light, node one carries mesh one with
    material one, and node two carries nothing. An ambient light, on no
    node, comes first."""
    var scene = Scene()
    _ = scene.add(Object3D())
    _ = scene.add(Object3D())
    _ = scene.add(Object3D())
    scene.add_light(ambient_light(Color(255, 255, 255), 0.5))
    scene.add_light(directional_light(Color(255, 255, 255), NodeId(0), 2))
    scene.add_mesh(Mesh(GeometryId(0), MaterialId(0), NodeId(0)))
    scene.add_mesh(Mesh(GeometryId(0), MaterialId(1), NodeId(1)))
    return scene^


def stuff() raises -> Assets:
    """Return assets holding two plain materials, black and white."""
    var assets = Assets()
    _ = assets.materials.add(Material(Color(0, 0, 0)))
    _ = assets.materials.add(Material(Color(255, 255, 255)))
    return assets^


def number_track(
    target: TrackTarget, start: Float32, end: Float32
) raises -> KeyframeTrack:
    """Return a two-second track running one number from `start` to
    `end`."""
    return KeyframeTrack(target, seconds([0, 2]), [start, end])


def play(
    mut mixer: AnimationMixer, var track: KeyframeTrack, weight: Float32 = 1
) raises -> Int:
    """Add and play an action on a clip of one track."""
    var which = mixer.add(
        AnimationAction(AnimationClip("one", [track^]), weight=weight)
    )
    mixer.action(which).play()
    return which


def play_additive(
    mut mixer: AnimationMixer, var track: KeyframeTrack, weight: Float32 = 1
) raises -> Int:
    """Add and play an additive action on a clip of one track."""
    var which = mixer.add(
        AnimationAction(
            AnimationClip("one", [track^], ADDITIVE_BLEND_MODE), weight=weight
        )
    )
    mixer.action(which).play()
    return which


# --- the kinds and the targets ---------------------------------------------


def test_every_kind_says_what_it_drives() raises:
    assert_true(VISIBLE.is_valid())
    assert_true(LIGHT_INTENSITY.is_valid())
    assert_false(TrackKind(40).is_valid())
    assert_false(TrackKind(-1).is_valid())
    assert_true(VISIBLE.is_node())
    assert_false(MORPH_INFLUENCE.is_node())
    assert_true(MORPH_INFLUENCE.is_morph())
    assert_true(MATERIAL_COLOR.is_material())
    assert_true(MATERIAL_IOR.is_material())
    assert_false(LIGHT_COLOR.is_material())
    assert_true(LIGHT_COLOR.is_light())
    assert_true(LIGHT_INTENSITY.is_light())
    assert_true(MATERIAL_SPECULAR.is_color())
    assert_false(MATERIAL_OPACITY.is_color())
    assert_true(VISIBLE.is_boolean())
    assert_equal(MATERIAL_COLOR.component_count(), 3)
    assert_equal(LIGHT_COLOR.component_count(), 3)
    assert_equal(MATERIAL_OPACITY.component_count(), 1)
    assert_equal(VISIBLE.component_count(), 1)
    assert_equal(TrackKind(40).component_count(), 0)


def test_mesh_and_light_indices_are_checked() raises:
    assert_true(MeshIndex(0).is_valid())
    assert_false(MeshIndex(-1).is_valid())
    assert_true(LightIndex(3).is_valid())
    assert_false(LightIndex(-1).is_valid())


def test_a_target_fits_its_slot() raises:
    assert_true(TrackTarget(POSITION, 0, 0).is_valid())
    assert_false(TrackTarget(POSITION, 0, 1).is_valid())
    assert_false(TrackTarget(TrackKind(9), 0, 0).is_valid())
    assert_true(TrackTarget(MORPH_INFLUENCE, 0, 7).is_valid())
    assert_false(TrackTarget(MORPH_INFLUENCE, 0, 8).is_valid())
    assert_false(TrackTarget(MORPH_INFLUENCE, 0, -1).is_valid())


def test_each_target_takes_the_kinds_of_its_own_thing() raises:
    assert_true(node_target(NodeId(2), VISIBLE) == TrackTarget(VISIBLE, 2, 0))
    assert_true(
        morph_target(MeshIndex(1), 3) == TrackTarget(MORPH_INFLUENCE, 1, 3)
    )
    assert_true(
        material_target(MaterialId(4), MATERIAL_OPACITY)
        == TrackTarget(MATERIAL_OPACITY, 4, 0)
    )
    assert_true(
        light_target(LightIndex(1), LIGHT_INTENSITY)
        == TrackTarget(LIGHT_INTENSITY, 1, 0)
    )
    with assert_raises():
        _ = node_target(NodeId(0), MATERIAL_OPACITY)
    with assert_raises():
        _ = morph_target(MeshIndex(0), -1)
    with assert_raises():
        _ = morph_target(MeshIndex(0), 8)
    with assert_raises():
        _ = material_target(MaterialId(0), POSITION)
    with assert_raises():
        _ = light_target(LightIndex(0), MATERIAL_COLOR)


# --- the tracks -------------------------------------------------------------


def test_a_flag_track_holds_each_key() raises:
    var shown = KeyframeTrack(NodeId(0), VISIBLE, seconds([0, 1]), [1, 0])
    assert_true(shown.interpolation == STEP)
    assert_true(shown.kind() == VISIBLE)
    assert_almost_equal(shown.sample(at(0.9))[0], Float32(1), atol=TOLERANCE)
    assert_almost_equal(shown.sample(at(1))[0], Float32(0), atol=TOLERANCE)
    var told = KeyframeTrack(
        NodeId(0), VISIBLE, seconds([0]), [1], interpolation=STEP
    )
    assert_true(told.interpolation == STEP)
    with assert_raises():
        _ = KeyframeTrack(
            NodeId(0), VISIBLE, seconds([0]), [1], interpolation=LINEAR
        )
    with assert_raises():
        _ = KeyframeTrack(NodeId(0), VISIBLE, seconds([0, 1]), [1, 0.5])


def test_a_track_refuses_a_target_that_does_not_fit() raises:
    with assert_raises():
        _ = KeyframeTrack(TrackTarget(MORPH_INFLUENCE, 0, 9), seconds([0]), [1])
    with assert_raises():
        _ = KeyframeTrack(
            TrackTarget(MATERIAL_OPACITY, 0, 0),
            seconds([0]),
            [1],
            interpolation=Interpolation(5),
        )


def test_a_color_track_runs_each_channel() raises:
    var track = KeyframeTrack(
        material_target(MaterialId(0), MATERIAL_COLOR),
        seconds([0, 2]),
        [0, 0, 0, 1, 0.5, 0.25],
    )
    var middle = track.sample(at(1))
    assert_equal(len(middle), 3)
    assert_almost_equal(middle[0], Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(middle[1], Float32(0.25), atol=TOLERANCE)
    assert_almost_equal(middle[2], Float32(0.125), atol=TOLERANCE)


def test_a_clip_refuses_a_blend_mode_that_is_not_named() raises:
    assert_true(NORMAL_BLEND_MODE.is_valid())
    assert_true(ADDITIVE_BLEND_MODE.is_valid())
    assert_false(AnimationBlendMode(7).is_valid())
    var track = KeyframeTrack(NodeId(0), VISIBLE, seconds([0, 1]), [1, 0])
    with assert_raises():
        _ = AnimationClip("odd", [track^], AnimationBlendMode(7))
    var plain = AnimationClip(
        "plain", [KeyframeTrack(NodeId(0), VISIBLE, seconds([0, 1]), [1, 0])]
    )
    assert_true(plain.blend_mode == NORMAL_BLEND_MODE)
    var twin = AnimationClip(copy=plain)
    assert_true(twin.blend_mode == NORMAL_BLEND_MODE)


# --- the piles --------------------------------------------------------------


def test_a_flag_pile_takes_the_value_with_half_the_weight() raises:
    var piles: List[Float32] = [1, 0, 0, 0]
    var hidden: List[Float32] = [0]
    # A third of the weight is not enough to take the pile.
    mix_into_pile(piles, 0, 2, 1, hidden, VISIBLE)
    assert_equal(piles[0], Float32(1))
    # Half is.
    mix_into_pile(piles, 0, 1, 1, hidden, VISIBLE)
    assert_equal(piles[0], Float32(0))


def test_a_flag_pile_rests_to_the_original_below_half_the_weight() raises:
    var piles: List[Float32] = [0, 0, 0, 0]
    var original: List[Float32] = [1, 0, 0, 0]
    rest_into_pile(piles, 0, 0.75, original, VISIBLE)
    assert_equal(piles[0], Float32(0))
    rest_into_pile(piles, 0, 0.5, original, VISIBLE)
    assert_equal(piles[0], Float32(1))


def test_find_target_matches_the_whole_target() raises:
    var targets: List[TrackTarget] = [
        TrackTarget(MORPH_INFLUENCE, 0, 1),
        TrackTarget(MORPH_INFLUENCE, 0, 2),
    ]
    assert_equal(find_target(targets, TrackTarget(MORPH_INFLUENCE, 0, 2)), 1)
    assert_equal(find_target(targets, TrackTarget(MORPH_INFLUENCE, 1, 2)), -1)


def test_an_additive_pile_starts_at_what_adds_nothing() raises:
    var piles: List[Float32] = [5, 5, 5, 5]
    var original: List[Float32] = [1, 0, 0, 0]
    additive_identity(piles, 0, original, QUATERNION)
    assert_equal(piles[0], Float32(0))
    assert_equal(piles[3], Float32(1))
    additive_identity(piles, 0, original, VISIBLE)
    assert_equal(piles[0], Float32(1))
    assert_equal(piles[3], Float32(0))
    additive_identity(piles, 0, original, POSITION)
    assert_equal(piles[0], Float32(0))


def test_an_additive_pile_adds_by_weight() raises:
    var piles: List[Float32] = [1, 2, 3, 0]
    var value: List[Float32] = [2, 2, 2]
    mix_additive_into_pile(piles, 0, 0.5, value, POSITION)
    assert_almost_equal(piles[0], Float32(2), atol=TOLERANCE)
    assert_almost_equal(piles[2], Float32(4), atol=TOLERANCE)

    var flags: List[Float32] = [1, 0, 0, 0]
    var hidden: List[Float32] = [0]
    mix_additive_into_pile(flags, 0, 0.25, hidden, VISIBLE)
    assert_equal(flags[0], Float32(1))
    mix_additive_into_pile(flags, 0, 0.5, hidden, VISIBLE)
    assert_equal(flags[0], Float32(0))

    # Half of a quarter turn on top of no turn is an eighth of a turn.
    var quarter = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(Float32(pi) / 2, RADIAN)
    )
    var turns: List[Float32] = [0, 0, 0, 1]
    var turn: List[Float32] = [quarter.x, quarter.y, quarter.z, quarter.w]
    mix_additive_into_pile(turns, 0, 0.5, turn, QUATERNION)
    var eighth = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(Float32(pi) / 4, RADIAN)
    )
    var mixed = Quaternion(turns[0], turns[1], turns[2], turns[3])
    assert_almost_equal(abs(mixed.dot(eighth)), Float32(1), atol=TOLERANCE)


def test_an_additive_pile_goes_on_top() raises:
    var piles: List[Float32] = [1, 1, 1, 0]
    var additive: List[Float32] = [1, 2, 3, 0]
    add_onto_pile(piles, 0, additive, SCALE)
    assert_almost_equal(piles[2], Float32(4), atol=TOLERANCE)

    var flags: List[Float32] = [1, 0, 0, 0]
    var hidden: List[Float32] = [0, 0, 0, 0]
    add_onto_pile(flags, 0, hidden, VISIBLE)
    assert_equal(flags[0], Float32(0))

    # A quarter turn on top of a quarter turn about one axis is a half turn.
    var quarter = Quaternion.from_axis_angle(
        Vector3(0, 0, 1), Angle(Float32(pi) / 2, RADIAN)
    )
    var turns: List[Float32] = [quarter.x, quarter.y, quarter.z, quarter.w]
    var more: List[Float32] = [quarter.x, quarter.y, quarter.z, quarter.w]
    add_onto_pile(turns, 0, more, QUATERNION)
    assert_almost_equal(turns[2], Float32(1), atol=TOLERANCE)
    assert_almost_equal(turns[3], Float32(0), atol=TOLERANCE)


def test_a_written_value_must_fit_its_property() raises:
    var nowhere = Float32(0) / Float32(0)
    assert_equal(checked_value(0.5, 0, 1, "x"), Float32(0.5))
    with assert_raises():
        _ = checked_value(nowhere, 0, 1, "x")
    with assert_raises():
        _ = checked_value(-0.5, 0, 1, "x")
    with assert_raises():
        _ = checked_value(1.5, 0, 1, "x")


def test_each_material_number_has_the_range_material_accepts() raises:
    assert_equal(material_number(MATERIAL_IOR, False), MIN_IOR)
    assert_equal(material_number(MATERIAL_IOR, True), MAX_IOR)
    assert_equal(material_number(MATERIAL_OPACITY, False), Float32(0))
    assert_equal(material_number(MATERIAL_OPACITY, True), Float32(1))
    assert_equal(
        material_number(MATERIAL_EMISSIVE_INTENSITY, True), inf[DType.float32]()
    )
    assert_equal(
        material_number(MATERIAL_SHININESS, True), inf[DType.float32]()
    )
    assert_equal(
        material_number(MATERIAL_ENV_MAP_INTENSITY, True), inf[DType.float32]()
    )


# --- reading and writing every property -------------------------------------


def test_every_property_reads_back_what_it_was_written() raises:
    var scene = world()
    var assets = stuff()
    var kinds: List[TrackKind] = [
        MATERIAL_OPACITY,
        MATERIAL_EMISSIVE_INTENSITY,
        MATERIAL_ROUGHNESS,
        MATERIAL_METALNESS,
        MATERIAL_SHININESS,
        MATERIAL_ALPHA_TEST,
        MATERIAL_REFLECTIVITY,
        MATERIAL_ENV_MAP_INTENSITY,
        MATERIAL_CLEARCOAT,
        MATERIAL_CLEARCOAT_ROUGHNESS,
        MATERIAL_SPECULAR_INTENSITY,
        MATERIAL_IOR,
    ]
    # Each a value inside its field's range and away from its default.
    var wanted: List[Float32] = [
        0.25,
        1.25,
        0.25,
        0.25,
        1.25,
        0.25,
        0.25,
        1.25,
        0.25,
        0.25,
        0.25,
        1.25,
    ]
    for index in range(len(kinds)):
        var target = TrackTarget(kinds[index], 0, 0)
        write_target(scene, assets, target, [wanted[index], 0, 0, 0], 0)
        var back = read_target(scene, assets, target)
        assert_equal(back[0], wanted[index])
    var material = assets.materials.get(MaterialId(0))
    assert_almost_equal(material.opacity, Float32(0.25), atol=TOLERANCE)
    assert_almost_equal(material.ior, Float32(1.25), atol=TOLERANCE)
    assert_almost_equal(
        material.clearcoat_roughness, Float32(0.25), atol=TOLERANCE
    )
    with assert_raises():
        write_target(
            scene, assets, TrackTarget(MATERIAL_OPACITY, 0, 0), [2, 0, 0, 0], 0
        )

    var colors: List[TrackKind] = [
        MATERIAL_COLOR,
        MATERIAL_EMISSIVE,
        MATERIAL_SPECULAR,
        LIGHT_COLOR,
    ]
    for index in range(len(colors)):
        var target = TrackTarget(colors[index], 1, 0)
        write_target(scene, assets, target, [1, 0.5, 0, 0], 0)
        var back = read_target(scene, assets, target)
        assert_almost_equal(back[0], Float32(1), atol=TOLERANCE)
        assert_almost_equal(back[1], Float32(0.5), atol=1e-2)
        assert_almost_equal(back[2], Float32(0), atol=TOLERANCE)
    assert_equal(assets.materials.get(MaterialId(1)).specular.r, UInt8(255))
    assert_equal(scene.lights[1].color.g, UInt8(188))
    with assert_raises():
        write_target(
            scene, assets, TrackTarget(LIGHT_COLOR, 1, 0), [1, 1.5, 0, 0], 0
        )

    var bright = TrackTarget(LIGHT_INTENSITY, 1, 0)
    write_target(scene, assets, bright, [3, 0, 0, 0], 0)
    assert_almost_equal(
        read_target(scene, assets, bright)[0], Float32(3), atol=TOLERANCE
    )
    with assert_raises():
        write_target(scene, assets, bright, [-1, 0, 0, 0], 0)

    var morph = TrackTarget(MORPH_INFLUENCE, 1, 2)
    write_target(scene, assets, morph, [0.75, 0, 0, 0], 0)
    assert_almost_equal(
        read_target(scene, assets, morph)[0], Float32(0.75), atol=TOLERANCE
    )

    var shown = TrackTarget(VISIBLE, 2, 0)
    write_target(scene, assets, shown, [0, 0, 0, 0], 0)
    assert_equal(read_target(scene, assets, shown)[0], Float32(0))
    write_target(scene, assets, shown, [1, 0, 0, 0], 0)
    assert_equal(read_target(scene, assets, shown)[0], Float32(1))

    var place = TrackTarget(POSITION, 2, 0)
    write_target(scene, assets, place, [1, 2, 3, 0], 0)
    assert_almost_equal(
        read_target(scene, assets, place)[2], Float32(3), atol=TOLERANCE
    )
    var size = TrackTarget(SCALE, 2, 0)
    write_target(scene, assets, size, [2, 2, 2, 0], 0)
    assert_almost_equal(
        read_target(scene, assets, size)[1], Float32(2), atol=TOLERANCE
    )
    var turn = TrackTarget(QUATERNION, 2, 0)
    write_target(scene, assets, turn, [0, 1, 0, 0], 0)
    assert_almost_equal(
        read_target(scene, assets, turn)[1], Float32(1), atol=TOLERANCE
    )


def test_a_color_read_and_written_back_is_the_same_color() raises:
    # A property released goes back to its original through a decode and
    # an encode, so the two must meet at every byte.
    var scene = world()
    var assets = Assets()
    for level in range(256):
        _ = assets.materials.add(
            Material(Color(UInt8(level), UInt8(255 - level), UInt8(level)))
        )
    for level in range(256):
        var target = TrackTarget(MATERIAL_COLOR, level, 0)
        var original = read_target(scene, assets, target)
        write_target(scene, assets, target, original, 0)
        var color = assets.materials.get(MaterialId(level)).color
        assert_equal(color.r, UInt8(level))
        assert_equal(color.g, UInt8(255 - level))


def test_a_target_must_name_something_that_is_there() raises:
    var scene = world()
    var assets = stuff()
    check_target(scene, assets, True, TrackTarget(POSITION, 2, 0))
    check_target(scene, assets, True, TrackTarget(MORPH_INFLUENCE, 1, 0))
    check_target(scene, assets, True, TrackTarget(LIGHT_COLOR, 1, 0))
    check_target(scene, assets, True, TrackTarget(MATERIAL_COLOR, 1, 0))
    with assert_raises():
        check_target(scene, assets, True, TrackTarget(TrackKind(9), 0, 0))
    with assert_raises():
        check_target(scene, assets, True, TrackTarget(POSITION, 3, 0))
    with assert_raises():
        check_target(scene, assets, True, TrackTarget(POSITION, -1, 0))
    with assert_raises():
        check_target(scene, assets, True, TrackTarget(MORPH_INFLUENCE, 2, 0))
    with assert_raises():
        check_target(scene, assets, True, TrackTarget(LIGHT_INTENSITY, 2, 0))
    with assert_raises():
        check_target(scene, assets, True, TrackTarget(MATERIAL_OPACITY, 2, 0))
    with assert_raises():
        check_target(scene, assets, False, TrackTarget(MATERIAL_OPACITY, 0, 0))


def test_a_binding_names_its_target() raises:
    var held = Binding(1, MORPH_INFLUENCE.value, [0, 0, 0, 0], 3)
    assert_true(held.target() == TrackTarget(MORPH_INFLUENCE, 1, 3))
    var twin = Binding(copy=held)
    assert_equal(twin.slot, 3)


# --- the mixer on every property --------------------------------------------


def test_a_mixer_fades_a_material_and_a_light() raises:
    var scene = world()
    var assets = stuff()
    var mixer = AnimationMixer()
    _ = play(
        mixer,
        number_track(material_target(MaterialId(0), MATERIAL_OPACITY), 1, 0),
    )
    _ = play(
        mixer,
        number_track(light_target(LightIndex(1), LIGHT_INTENSITY), 2, 4),
    )
    _ = play(
        mixer,
        KeyframeTrack(
            material_target(MaterialId(1), MATERIAL_EMISSIVE),
            seconds([0, 2]),
            [0, 0, 0, 1, 0, 0],
        ),
    )
    mixer.update(scene, assets, at(1))
    assert_almost_equal(
        assets.materials.get(MaterialId(0)).opacity,
        Float32(0.5),
        atol=TOLERANCE,
    )
    assert_almost_equal(scene.lights[1].intensity, Float32(3), atol=TOLERANCE)
    # Half of full red in linear light is 188 of 255 in sRGB.
    assert_equal(assets.materials.get(MaterialId(1)).emissive.r, UInt8(188))
    assert_equal(mixer.binding_count(), 3)


def test_a_material_track_needs_the_assets() raises:
    var scene = world()
    var mixer = AnimationMixer()
    _ = play(
        mixer,
        number_track(material_target(MaterialId(0), MATERIAL_OPACITY), 1, 0),
    )
    with assert_raises():
        mixer.update(scene, at(1))


def test_a_mixer_drives_a_morph_target_and_a_flag() raises:
    var scene = world()
    var mixer = AnimationMixer()
    _ = play(mixer, number_track(morph_target(MeshIndex(0), 5), 0, 1))
    var blink = play(
        mixer,
        KeyframeTrack(NodeId(1), VISIBLE, seconds([0, 1, 2]), [1, 0, 1]),
    )
    mixer.update(scene, at(1.5))
    assert_almost_equal(
        scene.meshes[0].morph_influence(5), Float32(0.75), atol=TOLERANCE
    )
    assert_false(scene.get(NodeId(1)).visible)
    # A flag at a weight below one half gives the node back its own.
    mixer.action(blink).set_weight(0.25)
    mixer.update(scene, at(0))
    assert_true(scene.get(NodeId(1)).visible)
    # Stopping it puts the flag back, as it does a position.
    mixer.action(blink).set_weight(1)
    mixer.update(scene, at(0))
    assert_false(scene.get(NodeId(1)).visible)
    mixer.action(blink).stop()
    mixer.update(scene, at(0))
    assert_true(scene.get(NodeId(1)).visible)


def test_two_actions_on_one_flag_take_the_heavier() raises:
    var scene = world()
    var mixer = AnimationMixer()
    _ = play(
        mixer, KeyframeTrack(NodeId(2), VISIBLE, seconds([0, 1]), [0, 0]), 0.4
    )
    var heavy = play(
        mixer, KeyframeTrack(NodeId(2), VISIBLE, seconds([0, 1]), [1, 1]), 0.6
    )
    # The first hides it and the second, heavier, shows it.
    mixer.update(scene, at(0.5))
    assert_true(scene.get(NodeId(2)).visible)
    mixer.action(heavy).set_weight(0.3)
    mixer.update(scene, at(0.1))
    # Now the hiding action is the heavier, and the whole weight is below
    # one: the original, shown, comes in at three tenths, which is not
    # half, so the node stays hidden.
    assert_false(scene.get(NodeId(2)).visible)


def test_a_mixer_refuses_a_value_its_property_cannot_hold() raises:
    var scene = world()
    var assets = stuff()
    var mixer = AnimationMixer()
    _ = play(
        mixer,
        number_track(material_target(MaterialId(0), MATERIAL_ROUGHNESS), 0, 4),
    )
    with assert_raises():
        mixer.update(scene, assets, at(1))


def test_a_mixer_refuses_a_blend_mode_that_is_not_named() raises:
    var scene = world()
    var mixer = AnimationMixer()
    var which = play(mixer, number_track(morph_target(MeshIndex(0), 0), 0, 1))
    mixer.action(which).blend_mode = AnimationBlendMode(4)
    with assert_raises():
        mixer.update(scene, at(1))


# --- additive actions -------------------------------------------------------


def test_an_additive_action_adds_on_top_of_the_pose() raises:
    var scene = world()
    var mixer = AnimationMixer()
    _ = play(
        mixer,
        KeyframeTrack(NodeId(0), POSITION, seconds([0, 2]), [2, 0, 0, 2, 0, 0]),
    )
    var bump = play_additive(
        mixer,
        KeyframeTrack(NodeId(0), POSITION, seconds([0, 2]), [0, 0, 0, 0, 4, 0]),
        0.5,
    )
    _ = play_additive(
        mixer,
        KeyframeTrack(NodeId(0), POSITION, seconds([0, 2]), [1, 0, 0, 1, 0, 0]),
        0.5,
    )
    mixer.update(scene, at(1))
    var placed = scene.get(NodeId(0)).position
    assert_almost_equal(placed.x, Float32(2.5), atol=TOLERANCE)
    assert_almost_equal(placed.y, Float32(1), atol=TOLERANCE)
    assert_true(mixer.action(bump).blend_mode == ADDITIVE_BLEND_MODE)


def test_an_additive_action_alone_adds_onto_the_original() raises:
    var scene = world()
    scene.node(NodeId(1)).set_position(1, 1, 1)
    var assets = stuff()
    var mixer = AnimationMixer()
    _ = play_additive(
        mixer,
        KeyframeTrack(NodeId(1), POSITION, seconds([0, 2]), [0, 0, 0, 2, 0, 0]),
    )
    # Additive opacity on a material at a half: 1 - 0.25 = 0.75.
    _ = play_additive(
        mixer,
        number_track(material_target(MaterialId(1), MATERIAL_OPACITY), 0, -0.5),
    )
    mixer.update(scene, assets, at(1))
    assert_almost_equal(
        scene.get(NodeId(1)).position.x, Float32(2), atol=TOLERANCE
    )
    assert_almost_equal(
        assets.materials.get(MaterialId(1)).opacity,
        Float32(0.75),
        atol=TOLERANCE,
    )


def test_an_additive_rotation_turns_after_the_pose() raises:
    var scene = world()
    var quarter = Quaternion.from_axis_angle(
        Vector3(0, 0, 1), Angle(Float32(pi) / 2, RADIAN)
    )
    var q: List[Float32] = [quarter.x, quarter.y, quarter.z, quarter.w]
    var mixer = AnimationMixer()
    _ = play(
        mixer,
        KeyframeTrack(
            NodeId(0),
            QUATERNION,
            seconds([0, 2]),
            [q[0], q[1], q[2], q[3], q[0], q[1], q[2], q[3]],
        ),
    )
    _ = play_additive(
        mixer,
        KeyframeTrack(
            NodeId(0),
            QUATERNION,
            seconds([0, 2]),
            [q[0], q[1], q[2], q[3], q[0], q[1], q[2], q[3]],
        ),
    )
    mixer.update(scene, at(1))
    var turned = scene.get(NodeId(0)).quaternion
    assert_almost_equal(abs(turned.z), Float32(1), atol=TOLERANCE)


def test_an_additive_flag_replaces_the_normal_one() raises:
    # three.js's `PropertyMixer.apply` puts the additive flag in place of
    # the normal one, starting from the original.
    var scene = world()
    var mixer = AnimationMixer()
    _ = play(mixer, KeyframeTrack(NodeId(2), VISIBLE, seconds([0, 1]), [0, 0]))
    _ = play_additive(
        mixer, KeyframeTrack(NodeId(2), VISIBLE, seconds([0, 1]), [0, 0]), 0.25
    )
    mixer.update(scene, at(0.5))
    assert_true(scene.get(NodeId(2)).visible)


# --- groups -----------------------------------------------------------------


def test_a_group_holds_each_node_once() raises:
    var group = AnimationObjectGroup()
    assert_equal(group.count(), 0)
    assert_false(group.contains(NodeId(0)))
    group.remove(NodeId(0))
    group.add(NodeId(1))
    group.add(NodeId(2))
    group.add(NodeId(1))
    assert_equal(group.count(), 2)
    assert_true(group.contains(NodeId(2)))
    group.remove(NodeId(1))
    assert_equal(group.count(), 1)
    assert_false(group.contains(NodeId(1)))
    with assert_raises():
        group.add(NodeId(-1))
    var twin = AnimationObjectGroup(copy=group)
    assert_equal(twin.count(), 1)


def test_a_group_action_plays_on_every_member() raises:
    var scene = world()
    var assets = stuff()
    var group = AnimationObjectGroup()
    group.add(NodeId(0))
    group.add(NodeId(1))
    group.add(NodeId(2))
    var action = AnimationAction(
        AnimationClip(
            "crowd",
            [
                KeyframeTrack(
                    NodeId(9), POSITION, seconds([0, 2]), [0, 0, 0, 4, 0, 0]
                ),
                number_track(
                    material_target(MaterialId(9), MATERIAL_OPACITY), 1, 0
                ),
                number_track(morph_target(MeshIndex(9), 1), 0, 1),
                number_track(
                    light_target(LightIndex(9), LIGHT_INTENSITY), 0, 8
                ),
            ],
        )
    )
    action.use_group(group^)
    var twin = AnimationAction(copy=action)
    assert_true(twin.grouped)
    assert_equal(twin.group.count(), 3)
    var mixer = AnimationMixer()
    var which = mixer.add(action^)
    mixer.action(which).play()
    mixer.update(scene, assets, at(1))
    for node in range(3):
        assert_almost_equal(
            scene.get(NodeId(node)).position.x, Float32(2), atol=TOLERANCE
        )
    assert_almost_equal(
        assets.materials.get(MaterialId(0)).opacity,
        Float32(0.5),
        atol=TOLERANCE,
    )
    assert_almost_equal(
        assets.materials.get(MaterialId(1)).opacity,
        Float32(0.5),
        atol=TOLERANCE,
    )
    assert_almost_equal(
        scene.meshes[1].morph_influence(1), Float32(0.5), atol=TOLERANCE
    )
    assert_almost_equal(scene.lights[1].intensity, Float32(4), atol=TOLERANCE)
    # The ambient light is on no node, so no member reaches it.
    assert_almost_equal(scene.lights[0].intensity, Float32(0.5), atol=TOLERANCE)


def test_members_sharing_a_material_drive_it_once() raises:
    var scene = world()
    scene.add_mesh(Mesh(GeometryId(0), MaterialId(0), NodeId(2)))
    var assets = stuff()
    var group = AnimationObjectGroup()
    group.add(NodeId(0))
    group.add(NodeId(2))
    var action = AnimationAction(
        AnimationClip(
            "shared",
            [
                number_track(
                    material_target(MaterialId(0), MATERIAL_OPACITY), 1, 0
                )
            ],
        )
    )
    action.use_group(group^)
    var mixer = AnimationMixer()
    var which = mixer.add(action^)
    mixer.action(which).play()
    mixer.update(scene, assets, at(1))
    assert_equal(mixer.binding_count(), 1)


def test_an_empty_group_drives_nothing() raises:
    var scene = world()
    var action = AnimationAction(
        AnimationClip(
            "none",
            [
                KeyframeTrack(
                    NodeId(0), POSITION, seconds([0, 2]), [0, 0, 0, 4, 0, 0]
                )
            ],
        )
    )
    action.use_group(AnimationObjectGroup())
    var mixer = AnimationMixer()
    var which = mixer.add(action^)
    mixer.action(which).play()
    mixer.update(scene, at(1))
    assert_equal(mixer.binding_count(), 0)


def test_a_member_with_no_mesh_and_no_light_takes_no_such_track() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    var group = AnimationObjectGroup()
    group.add(NodeId(0))
    var action = AnimationAction(
        AnimationClip(
            "bare",
            [
                number_track(morph_target(MeshIndex(0), 0), 0, 1),
                number_track(
                    light_target(LightIndex(0), LIGHT_INTENSITY), 0, 1
                ),
            ],
        )
    )
    action.use_group(group^)
    var mixer = AnimationMixer()
    var which = mixer.add(action^)
    mixer.action(which).play()
    mixer.update(scene, at(1))
    assert_equal(mixer.binding_count(), 0)


def test_a_group_member_must_be_in_the_scene() raises:
    var scene = world()
    var track = KeyframeTrack(
        NodeId(0), POSITION, seconds([0, 2]), [0, 0, 0, 4, 0, 0]
    )
    var group = AnimationObjectGroup()
    group.add(NodeId(3))
    var action = AnimationAction(AnimationClip("far", [track.copy()]))
    action.use_group(group^)
    var mixer = AnimationMixer()
    var which = mixer.add(action^)
    mixer.action(which).play()
    with assert_raises():
        mixer.update(scene, at(1))
    # One below zero cannot be added, but the list is open.
    var below = AnimationObjectGroup()
    below.members.append(NodeId(-1))
    var other = AnimationAction(AnimationClip("below", [track^]))
    other.use_group(below^)
    var second = AnimationMixer()
    var index = second.add(other^)
    second.action(index).play()
    with assert_raises():
        second.update(scene, at(1))


# --- subclip ----------------------------------------------------------------


def long_clip() raises -> AnimationClip:
    """Return a clip of two tracks keyed at frames 0, 10, 20 and 30 of a
    ten-frame-a-second clock, the second starting at frame 10."""
    return AnimationClip(
        "all",
        [
            KeyframeTrack(
                NodeId(0),
                POSITION,
                seconds([0, 1, 2, 3]),
                [0, 0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0],
            ),
            KeyframeTrack(
                material_target(MaterialId(0), MATERIAL_OPACITY),
                seconds([1, 2, 3]),
                [1, 0.5, 0],
            ),
            KeyframeTrack(NodeId(1), VISIBLE, seconds([0, 3]), [1, 0]),
        ],
        ADDITIVE_BLEND_MODE,
    )


def test_a_subclip_keeps_the_keys_in_its_range() raises:
    var cut = subclip(long_clip(), "middle", 10, 30, 10)
    assert_equal(String(cut.name), String("middle"))
    # The flag track keeps no key: frame 0 is before, frame 30 is the end.
    assert_equal(cut.track_count(), 2)
    assert_true(cut.blend_mode == ADDITIVE_BLEND_MODE)
    assert_almost_equal(cut.duration().to(SECOND), Float32(1), atol=TOLERANCE)
    assert_equal(cut.tracks[0].key_count(), 2)
    assert_almost_equal(cut.tracks[0].values[0], Float32(1), atol=TOLERANCE)
    assert_almost_equal(cut.tracks[1].times[0], Float32(0), atol=TOLERANCE)


def test_a_subclip_starts_at_its_earliest_key() raises:
    # The second track keeps a key earlier than the first track's first.
    var clip = AnimationClip(
        "two",
        [
            KeyframeTrack(
                NodeId(0), POSITION, seconds([2, 3]), [0, 0, 0, 1, 0, 0]
            ),
            KeyframeTrack(
                NodeId(1), POSITION, seconds([1, 3]), [0, 0, 0, 1, 0, 0]
            ),
            KeyframeTrack(
                NodeId(2), POSITION, seconds([1.5, 3]), [0, 0, 0, 1, 0, 0]
            ),
        ],
    )
    var cut = subclip(clip, "tail", 0, 40, 10)
    assert_almost_equal(cut.tracks[0].times[0], Float32(1), atol=TOLERANCE)
    assert_almost_equal(cut.tracks[1].times[0], Float32(0), atol=TOLERANCE)
    assert_almost_equal(cut.tracks[2].times[0], Float32(0.5), atol=TOLERANCE)


def test_a_subclip_refuses_a_range_it_cannot_cut() raises:
    var nowhere = Float32(0) / Float32(0)
    with assert_raises():
        _ = subclip(long_clip(), "x", 0, 10, 0)
    with assert_raises():
        _ = subclip(long_clip(), "x", 0, 10, nowhere)
    with assert_raises():
        _ = subclip(long_clip(), "x", -1, 10, 10)
    with assert_raises():
        _ = subclip(long_clip(), "x", 10, 10, 10)
    # No key at all in the range.
    with assert_raises():
        _ = subclip(long_clip(), "x", 31, 40, 10)
    # One key of each track only: a clip of no length.
    with assert_raises():
        _ = subclip(long_clip(), "x", 30, 40, 10)


def test_a_frame_rate_must_be_above_zero() raises:
    assert_equal(checked_fps(30), Float32(30))
    with assert_raises():
        _ = checked_fps(-1)


# --- make_clip_additive -----------------------------------------------------


def test_an_additive_clip_holds_changes_from_its_first_frame() raises:
    var clip = AnimationClip(
        "walk",
        [
            KeyframeTrack(
                NodeId(0), POSITION, seconds([0, 1]), [1, 2, 3, 2, 2, 3]
            ),
            KeyframeTrack(NodeId(0), VISIBLE, seconds([0, 1]), [1, 0]),
        ],
    )
    var made = make_clip_additive(clip)
    assert_true(made.blend_mode == ADDITIVE_BLEND_MODE)
    assert_true(clip.blend_mode == NORMAL_BLEND_MODE)
    assert_almost_equal(made.tracks[0].values[0], Float32(0), atol=TOLERANCE)
    assert_almost_equal(made.tracks[0].values[3], Float32(1), atol=TOLERANCE)
    assert_almost_equal(made.tracks[0].values[5], Float32(0), atol=TOLERANCE)
    # The flag is left as it is.
    assert_almost_equal(made.tracks[1].values[0], Float32(1), atol=TOLERANCE)
    # At the last frame of a ten-frame-a-second clock.
    var late = make_clip_additive(clip, 10, 10)
    assert_almost_equal(late.tracks[0].values[0], Float32(-1), atol=TOLERANCE)


def test_an_additive_rotation_is_relative_to_the_reference() raises:
    var quarter = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(Float32(pi) / 2, RADIAN)
    )
    var half = Quaternion.from_axis_angle(
        Vector3(0, 1, 0), Angle(Float32(pi), RADIAN)
    )
    var clip = AnimationClip(
        "turn",
        [
            KeyframeTrack(
                NodeId(0),
                QUATERNION,
                seconds([0, 1]),
                [
                    quarter.x,
                    quarter.y,
                    quarter.z,
                    quarter.w,
                    half.x,
                    half.y,
                    half.z,
                    half.w,
                ],
            )
        ],
    )
    var made = make_clip_additive(clip)
    # The first key is no turn from itself, and the second is a quarter
    # turn from the first.
    assert_almost_equal(made.tracks[0].values[3], Float32(1), atol=TOLERANCE)
    var second = Quaternion(
        made.tracks[0].values[4],
        made.tracks[0].values[5],
        made.tracks[0].values[6],
        made.tracks[0].values[7],
    )
    assert_almost_equal(abs(second.dot(quarter)), Float32(1), atol=TOLERANCE)


def test_an_additive_clip_takes_its_reference_from_another_clip() raises:
    var target = AnimationClip(
        "target",
        [
            KeyframeTrack(
                NodeId(0), POSITION, seconds([0, 1]), [5, 0, 0, 6, 0, 0]
            ),
            KeyframeTrack(
                NodeId(1), SCALE, seconds([0, 1]), [1, 1, 1, 2, 2, 2]
            ),
        ],
    )
    var reference = AnimationClip(
        "rest",
        [
            KeyframeTrack(
                NodeId(2), POSITION, seconds([0, 1]), [9, 9, 9, 9, 9, 9]
            ),
            KeyframeTrack(
                NodeId(0), POSITION, seconds([0, 2]), [2, 0, 0, 4, 0, 0]
            ),
        ],
    )
    # Frame 15 at thirty a second is half a second in: 2.5 to take off.
    var made = make_clip_additive(target, 15, reference)
    assert_almost_equal(made.tracks[0].values[0], Float32(2.5), atol=TOLERANCE)
    # No reference drives the scale, so it is kept as it is.
    assert_almost_equal(made.tracks[1].values[0], Float32(1), atol=TOLERANCE)
    with assert_raises():
        _ = make_clip_additive(target, -1, reference)
    with assert_raises():
        _ = make_clip_additive(target, 0, reference, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
