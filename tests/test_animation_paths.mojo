# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the track paths three.js binds past a whole property: one
number of a vector, a map's layout, one material of several, and a morph
target by name. Also the mixer's `set_time` and a clip's user data.

`assets/animation/three.json` holds what three.js r180 does with each, run
in Node by `three_paths.mjs` beside it.
"""

from animation.animation_clip import AnimationClip
from animation.animation_json import (
    parse_track_name,
    property_kind,
    property_path,
    read_clip,
    write_clip,
)
from animation.animation_object_group import AnimationObjectGroup
from animation.animation_mixer import (
    AnimationAction,
    AnimationMixer,
    ONCE,
    PING_PONG,
    REPEAT,
)
from animation.keyframe_track import (
    KeyframeTrack,
    MATERIAL_MAP_CENTER,
    MATERIAL_MAP_OFFSET,
    MATERIAL_MAP_REPEAT,
    MATERIAL_MAP_ROTATION,
    MATERIAL_OPACITY,
    MORPH_INFLUENCE,
    POSITION,
    POSITION_ELEMENT,
    ROTATION_ELEMENT,
    SCALE_ELEMENT,
    TrackKind,
    TrackTarget,
    VISIBLE,
    material_target,
    node_element_target,
    node_target,
)
from cameras.camera_list import CameraList
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from exporters.json_writer import JsonWriter
from loaders.json import JsonDocument, parse_json
from loaders.object_loader import read_object_json
from materials.material import Material, MaterialId
from math.euler import Euler
from math.quaternion import Quaternion
from math.vector3 import Vector3
from render.framebuffer import Color
from render.texture import Texture
from render.texture_store import TextureId
from std.pathlib import Path
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


def _reference() raises -> JsonDocument:
    """Return what three.js did.

    Returns:
        The parsed file.

    Raises:
        Error: If the file cannot be read.
    """
    return parse_json(Path("assets/animation/three.json").read_text())


def _expect(
    doc: JsonDocument, section: String, key: String, got: List[Float32]
) raises:
    """Assert a list of numbers matches one list of the reference.

    Args:
        doc: The reference.
        section: The top-level entry.
        key: The list in it.
        got: The numbers.

    Raises:
        Error: If they differ.
    """
    var want = doc.get(doc.get(doc.root(), section), key)
    assert_equal(len(got), doc.length(want))
    for at in range(len(got)):
        assert_almost_equal(
            Float64(got[at]), doc.number(doc.at(want, at)), atol=TOLERANCE
        )


def _seconds(values: List[Float32]) -> List[Duration]:
    """Return numbers as durations in seconds."""
    var out = List[Duration]()
    for index in range(len(values)):
        out.append(Duration(values[index], SECOND))
    return out^


# --- one number of a vector -------------------------------------------------


def test_one_number_of_a_vector_mixes_with_the_rest() raises:
    var scene = Scene()
    var node = Object3D()
    node.set_position(1, 2, 3)
    node.set_euler(Angle(0.1, RADIAN), Angle(0.2, RADIAN), Angle(0.3, RADIAN))
    var id = scene.add(node^)
    var times = _seconds([0, 1])
    var tracks: List[KeyframeTrack] = [
        KeyframeTrack(
            node_element_target(id, POSITION_ELEMENT, 0), times, [0, 4]
        ),
        KeyframeTrack(node_element_target(id, SCALE_ELEMENT, 2), times, [1, 3]),
        KeyframeTrack(
            node_element_target(id, ROTATION_ELEMENT, 1), times, [0, 1.5]
        ),
    ]
    var mixer = AnimationMixer()
    var action = AnimationAction(AnimationClip("e", tracks^))
    action.weight = 0.5
    var which = mixer.add(action^)
    mixer.action(which).play()
    mixer.update(scene, Duration(0.5, SECOND))
    ref held = scene.get(id)
    var doc = _reference()
    _expect(
        doc,
        "element",
        "position",
        [held.position.x, held.position.y, held.position.z],
    )
    _expect(doc, "element", "scale", [held.scale.x, held.scale.y, held.scale.z])
    _expect(
        doc,
        "element",
        "quaternion",
        [
            held.quaternion.x,
            held.quaternion.y,
            held.quaternion.z,
            held.quaternion.w,
        ],
    )


def test_each_rotation_axis_turns_about_its_own() raises:
    # Driven alone, a rotation element turns the node about its axis by the
    # key's angle, and reads the angle back.
    for axis in range(3):
        var scene = Scene()
        var id = scene.add(Object3D())
        var tracks: List[KeyframeTrack] = [
            KeyframeTrack(
                node_element_target(id, ROTATION_ELEMENT, axis),
                _seconds([0, 1]),
                [0.2, 0.2],
            )
        ]
        var mixer = AnimationMixer()
        var which = mixer.add(AnimationAction(AnimationClip("r", tracks^)))
        mixer.action(which).play()
        mixer.update(scene, Duration(0.5, SECOND))
        var angles = Euler.from_quaternion(scene.get(id).quaternion)
        var got: List[Float32] = [
            angles.x.to(RADIAN),
            angles.y.to(RADIAN),
            angles.z.to(RADIAN),
        ]
        for other in range(3):
            assert_almost_equal(
                got[other], 0.2 if other == axis else Float32(0), atol=1e-6
            )
        # Stopped, the node turns back to where it was.
        mixer.action(which).stop()
        mixer.update(scene, Duration(0.5, SECOND))
        assert_almost_equal(scene.get(id).quaternion.w, 1, atol=1e-6)


def test_an_element_target_names_an_axis() raises:
    var target = node_element_target(NodeId(0), ROTATION_ELEMENT, 2)
    assert_equal(target.slot, 2)
    assert_true(target.is_valid())
    assert_true(ROTATION_ELEMENT.is_node())
    assert_true(ROTATION_ELEMENT.is_element())
    assert_equal(ROTATION_ELEMENT.component_count(), 1)
    assert_equal(ROTATION_ELEMENT.value_type_name(), "number")
    assert_false(TrackTarget(POSITION_ELEMENT, 0, 3).is_valid())
    assert_false(TrackTarget(POSITION_ELEMENT, 0, -1).is_valid())
    with assert_raises(contains="axis must be 0, 1 or 2"):
        _ = node_element_target(NodeId(0), SCALE_ELEMENT, 3)
    with assert_raises(contains="axis must be 0, 1 or 2"):
        _ = node_element_target(NodeId(0), SCALE_ELEMENT, -1)
    with assert_raises(contains="needs an element kind"):
        _ = node_element_target(NodeId(0), POSITION, 0)
    with assert_raises(contains="drives a whole property"):
        _ = node_target(NodeId(0), POSITION_ELEMENT)


def test_an_element_path_reads_and_writes() raises:
    assert_equal(
        property_kind(parse_track_name(".position[x]")), POSITION_ELEMENT
    )
    assert_equal(property_kind(parse_track_name(".scale[y]")), SCALE_ELEMENT)
    assert_equal(
        property_kind(parse_track_name("Box.rotation[z]")), ROTATION_ELEMENT
    )
    assert_equal(
        property_path(node_element_target(NodeId(0), POSITION_ELEMENT, 0)),
        ".position[x]",
    )
    assert_equal(
        property_path(node_element_target(NodeId(0), SCALE_ELEMENT, 1)),
        ".scale[y]",
    )
    assert_equal(
        property_path(node_element_target(NodeId(0), ROTATION_ELEMENT, 2)),
        ".rotation[z]",
    )
    with assert_raises(contains="by x, y or z"):
        _ = property_kind(parse_track_name(".scale[w]"))
    with assert_raises(contains="by x, y or z"):
        _ = property_kind(parse_track_name(".rotation[1]"))
    # A whole rotation is three.js's `Euler`, which a track here does not
    # drive: `quaternion` is the whole turn.
    with assert_raises(contains="property named rotation"):
        _ = property_kind(parse_track_name(".rotation"))


def test_an_element_track_on_a_group_keeps_its_axis() raises:
    var scene = Scene()
    var first = scene.add(Object3D())
    var second = scene.add(Object3D())
    var group = AnimationObjectGroup()
    group.add(first)
    group.add(second)
    var tracks: List[KeyframeTrack] = [
        KeyframeTrack(
            node_element_target(NodeId(0), POSITION_ELEMENT, 1),
            _seconds([0, 1]),
            [0, 2],
        )
    ]
    var action = AnimationAction(AnimationClip("g", tracks^))
    action.use_group(group^)
    var mixer = AnimationMixer()
    var which = mixer.add(action^)
    mixer.action(which).play()
    mixer.update(scene, Duration(0.5, SECOND))
    assert_almost_equal(scene.get(second).position.y, 1, atol=1e-6)
    assert_equal(scene.get(second).position.x, 0)


# --- a map's layout ---------------------------------------------------------


def test_a_map_is_laid_as_three_js_lays_it() raises:
    var scene = Scene()
    var assets = Assets()
    var map = assets.textures.add(Texture())
    var paint = Material(Color(255, 255, 255))
    paint.map = map
    var worn = assets.materials.add(paint^)
    var times = _seconds([0, 1])
    var tracks: List[KeyframeTrack] = [
        KeyframeTrack(
            material_target(worn, MATERIAL_MAP_OFFSET), times, [0, 0, 1, 0.5]
        ),
        KeyframeTrack(
            material_target(worn, MATERIAL_MAP_REPEAT), times, [1, 1, 3, 5]
        ),
        KeyframeTrack(
            material_target(worn, MATERIAL_MAP_CENTER),
            times,
            [0, 0, 0.5, 0.5],
        ),
        KeyframeTrack(
            material_target(worn, MATERIAL_MAP_ROTATION), times, [0, 2]
        ),
    ]
    var mixer = AnimationMixer()
    var which = mixer.add(AnimationAction(AnimationClip("m", tracks^)))
    mixer.action(which).play()
    mixer.update(scene, assets, Duration(0.25, SECOND))
    ref laid = assets.textures.textures[map.value]
    var doc = _reference()
    _expect(doc, "map", "offset", [laid.offset.x, laid.offset.y])
    _expect(doc, "map", "repeat", [laid.repeat.x, laid.repeat.y])
    _expect(doc, "map", "center", [laid.center.x, laid.center.y])
    assert_almost_equal(
        Float64(laid.rotation.to(RADIAN)),
        doc.number(doc.get(doc.get(doc.root(), "map"), "rotation")),
        atol=TOLERANCE,
    )
    # Stopped, the mixer puts the layout back.
    mixer.action(which).stop()
    mixer.update(scene, assets, Duration(0.25, SECOND))
    assert_equal(assets.textures.textures[map.value].offset.x, 0)
    assert_equal(assets.textures.textures[map.value].repeat.y, 1)


def test_a_map_path_reads_and_writes() raises:
    assert_true(MATERIAL_MAP_OFFSET.is_material())
    assert_true(MATERIAL_MAP_OFFSET.is_map())
    assert_equal(MATERIAL_MAP_OFFSET.component_count(), 2)
    assert_equal(MATERIAL_MAP_OFFSET.value_type_name(), "vector")
    assert_equal(MATERIAL_MAP_ROTATION.component_count(), 1)
    assert_equal(MATERIAL_MAP_ROTATION.value_type_name(), "number")
    assert_equal(
        property_kind(parse_track_name(".map.offset")), MATERIAL_MAP_OFFSET
    )
    assert_equal(
        property_kind(parse_track_name("Box.map.rotation")),
        MATERIAL_MAP_ROTATION,
    )
    assert_equal(
        property_path(material_target(MaterialId(0), MATERIAL_MAP_REPEAT)),
        ".map.repeat",
    )
    assert_equal(
        property_path(material_target(MaterialId(0), MATERIAL_MAP_CENTER)),
        ".map.center",
    )
    with assert_raises(contains="property named"):
        _ = property_kind(parse_track_name(".map.opacity"))
    with assert_raises(contains="one part of"):
        _ = property_kind(parse_track_name(".map.offset[x]"))


def test_a_map_track_needs_a_map() raises:
    var scene = Scene()
    var assets = Assets()
    var bare = assets.materials.add(Material(Color(255, 255, 255)))
    var lost = Material(Color(255, 255, 255))
    lost.map = TextureId(4)
    var missing = assets.materials.add(lost^)
    var below = Material(Color(255, 255, 255))
    below.map = TextureId(-3)
    var negative = assets.materials.add(below^)
    for material in [bare, missing, negative]:
        var tracks: List[KeyframeTrack] = [
            KeyframeTrack(
                material_target(material, MATERIAL_MAP_ROTATION),
                _seconds([0, 1]),
                [0, 1],
            )
        ]
        var mixer = AnimationMixer()
        var which = mixer.add(AnimationAction(AnimationClip("m", tracks^)))
        mixer.action(which).play()
        with assert_raises(contains="map track"):
            mixer.update(scene, assets, Duration(0.25, SECOND))


# --- a scene's clip in JSON -------------------------------------------------


def test_a_clip_binds_as_three_js_binds_it() raises:
    var doc = _reference()
    var text = doc.string(doc.get(doc.root(), "document"))
    var scene = Scene()
    var assets = Assets()
    var model = read_object_json(text, scene, assets)
    assert_equal(len(model.animations), 1)
    ref clip = model.animations[0]
    # `materials[0]` binds nothing, as in three.js.
    assert_equal(clip.track_count(), 3)
    assert_equal(clip.tracks[1].target.kind, MORPH_INFLUENCE)
    assert_equal(clip.tracks[1].target.slot, 1)
    assert_equal(clip.tracks[2].target.kind, POSITION_ELEMENT)
    assert_equal(clip.tracks[2].target.slot, 1)
    assert_equal(clip.user_data.number("take"), 3)
    var mixer = AnimationMixer()
    var which = mixer.add(AnimationAction(clip.copy()))
    mixer.action(which).play()
    mixer.update(scene, assets, Duration(0.25, SECOND))
    ref multi = scene.meshes[0]
    _expect(
        doc,
        "loaded",
        "opacity",
        [
            assets.materials.materials[multi.materials[0].value].opacity,
            assets.materials.materials[multi.materials[1].value].opacity,
        ],
    )
    ref face = scene.meshes[1]
    _expect(
        doc,
        "loaded",
        "influences",
        [face.morph_influence(0), face.morph_influence(1)],
    )
    ref placed = scene.get(multi.node).position
    _expect(doc, "loaded", "position", [placed.x, placed.y, placed.z])


def test_a_path_the_loader_cannot_bind_is_left_out() raises:
    var doc = _reference()
    var text = doc.string(doc.get(doc.root(), "document"))
    var names: List[String] = [
        "Multi.material[2].opacity",
        "Multi.material[one].opacity",
        "Face.material[0].opacity",
        "Face.morphTargetInfluences[grin]",
        "Multi.morphTargetInfluences[grin]",
        "Face.map.rotation",
    ]
    for at in range(len(names)):
        var renamed = text.replace("Multi.material[1].opacity", names[at])
        var scene = Scene()
        var assets = Assets()
        var model = read_object_json(renamed, scene, assets)
        var bound = 0
        if len(model.animations) > 0:
            bound = model.animations[0].track_count()
        if at < 5:
            # The one renamed track is left out.
            assert_equal(bound, 2)
        else:
            # A map binds to the material; the mixer checks the map.
            assert_equal(bound, 3)
            assert_equal(
                model.animations[0].tracks[0].target.kind,
                MATERIAL_MAP_ROTATION,
            )


# --- set_time and user data -------------------------------------------------


def test_set_time_plays_from_the_start() raises:
    var doc = _reference()
    var loops = [REPEAT, PING_PONG, ONCE]
    var names: List[String] = ["repeat", "ping_pong", "once"]
    for at in range(3):
        var scene = Scene()
        var id = scene.add(Object3D())
        var tracks: List[KeyframeTrack] = [
            KeyframeTrack(
                id, POSITION, _seconds([0, 1, 2]), [0, 0, 0, 1, 2, 3, 4, 0, 0]
            )
        ]
        var action = AnimationAction(
            AnimationClip("s", tracks^), clamp_when_finished=True
        )
        action.set_loop(loops[at])
        var mixer = AnimationMixer()
        var which = mixer.add(action^)
        mixer.action(which).play()
        mixer.update(scene, Duration(0.7, SECOND))
        mixer.set_time(scene, Duration(2.5, SECOND))
        ref placed = scene.get(id).position
        _expect(doc, "set_time", names[at], [placed.x, placed.y, placed.z])
        assert_almost_equal(mixer.time().to(SECOND), 2.5, atol=1e-6)


def test_set_time_with_no_action_moves_the_clock() raises:
    var scene = Scene()
    var mixer = AnimationMixer()
    mixer.set_time(scene, Duration(1.5, SECOND))
    assert_almost_equal(mixer.time().to(SECOND), 1.5, atol=1e-6)


def test_set_time_with_the_assets_and_the_cameras() raises:
    var scene = Scene()
    var assets = Assets()
    var cameras = CameraList()
    var id = scene.add(Object3D())
    var tracks: List[KeyframeTrack] = [
        KeyframeTrack(id, POSITION, _seconds([0, 1]), [0, 0, 0, 1, 0, 0])
    ]
    var mixer = AnimationMixer()
    var which = mixer.add(AnimationAction(AnimationClip("a", tracks^)))
    mixer.action(which).play()
    mixer.set_time(scene, assets, Duration(0.25, SECOND))
    assert_almost_equal(scene.get(id).position.x, 0.25, atol=1e-6)
    mixer.set_time(scene, assets, cameras, Duration(0.5, SECOND))
    assert_almost_equal(scene.get(id).position.x, 0.5, atol=1e-6)


def test_a_clips_user_data_is_kept() raises:
    var tracks: List[KeyframeTrack] = [
        KeyframeTrack(
            node_target(NodeId(0), VISIBLE), _seconds([0]), [Float32(1)]
        )
    ]
    var clip = AnimationClip("u", tracks^, duration=Duration(1, SECOND))
    clip.user_data.set_number("take", 3)
    clip.user_data.set_string("tag", "a")
    var copied = clip.copy()
    assert_equal(copied.user_data.string("tag"), "a")
    var writer = JsonWriter()
    write_clip(writer, clip, [".visible"], "u")
    var written = parse_json(writer.finish())
    var doc = _reference()
    assert_equal(
        written.string(written.get(written.root(), "userData")),
        doc.string(doc.get(doc.root(), "user_data")),
    )
    var shown: List[Optional[TrackTarget]] = [node_target(NodeId(0), VISIBLE)]
    var read = read_clip(written, written.root(), shown)
    assert_equal(read.value().user_data.number("take"), 3)
    assert_equal(read.value().user_data.string("tag"), "a")
    # An empty text is no user data, as three.js's `|| '{}'` reads it.
    var bare = parse_json(
        '{"name":"b","tracks":[{"name":".visible","type":"bool",'
        + '"times":[0,1],"values":[true,false]}],"userData":""}'
    )
    var none = read_clip(bare, bare.root(), shown)
    assert_equal(none.value().user_data.count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
