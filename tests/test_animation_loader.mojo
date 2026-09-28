# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.animation_loader` and `helpers.animation_path`.

`assets/animation/clips.json` is what three.js r186's
`AnimationClip.toJSON` writes for three clips. The expected path is what
three.js r186's `AnimationPathHelper` samples from the same track.
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import (
    KeyframeTrack,
    LIGHT_INTENSITY,
    MATERIAL_MAP_OFFSET,
    MATERIAL_OPACITY,
    MORPH_INFLUENCE,
    POSITION,
    POSITION_ELEMENT,
    QUATERNION,
    TrackTarget,
)
from core.assets import Assets
from core.buffer_geometry import POSITION as POSITION_ATTRIBUTE
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from helpers.animation_path import (
    DEFAULT_MARKER_SIZE,
    add_animation_path_helper,
    animation_path,
    animation_path_markers,
    position_track,
)
from lights.light import point_light
from loaders.animation_loader import (
    parse_animations,
    read_animations,
    track_target,
)
from materials.material import Material
from objects.mesh import Mesh
from render.framebuffer import Color
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Duration, Length, METER, SECOND


def named(name: String, parent: NodeId = NO_PARENT) -> Object3D:
    """Return a node with a name, under a parent."""
    var node = Object3D()
    node.name = name
    node.parent = parent
    return node^


struct Rig(Movable):
    """A small scene: a root, a mesh below it, a hand below that, and a
    lamp."""

    var scene: Scene
    var assets: Assets
    var root: NodeId
    var hips: NodeId
    var hand: NodeId
    var lamp: NodeId

    def __init__(out self) raises:
        """Build the rig."""
        self.scene = Scene()
        self.assets = Assets()
        self.root = self.scene.add(named("Robot"))
        self.hips = self.scene.add(named("Hips", self.root))
        self.hand = self.scene.add(named("Hand", self.hips))
        self.lamp = self.scene.add(named("Lamp", self.root))
        var box = self.assets.geometries.add(cube(Length(1.0, METER)))
        var paint = self.assets.materials.add(Material(Color(255, 0, 0)))
        var mesh = Mesh(box, paint, self.hips)
        mesh.morph_target_dictionary["smile"] = 0
        self.scene.add_mesh(mesh)
        self.scene.add_light(point_light(Color(255, 255, 255), self.lamp))


def target(rig: Rig, name: String) raises -> Optional[TrackTarget]:
    """Return what a track name drives below the rig's root."""
    return track_target(rig.scene, rig.root, name)


def test_a_node_name_finds_the_root_or_a_node_below_it() raises:
    var rig = Rig()
    var root = TrackTarget(POSITION, rig.root.value, 0)
    assert_true(target(rig, ".position").value() == root)
    assert_true(target(rig, "Robot.position").value() == root)
    assert_true(
        target(rig, "Hips.position").value()
        == TrackTarget(POSITION, rig.hips.value, 0)
    )
    assert_true(
        target(rig, "Hand.position[y]").value()
        == TrackTarget(POSITION_ELEMENT, rig.hand.value, 1)
    )
    assert_false(Bool(target(rig, "Nobody.position")))
    # A lone node has nothing below it.
    var lone = Scene()
    var only = lone.add(named("Only"))
    assert_false(Bool(track_target(lone, only, "Other.position")))
    assert_true(Bool(track_target(lone, only, "..position")))


def test_an_empty_node_name_is_the_root() raises:
    var rig = Rig()
    var plain = track_target(rig.scene, rig.root, ".quaternion")
    assert_true(plain.value() == TrackTarget(QUATERNION, rig.root.value, 0))


def test_a_bone_is_a_node_below_by_its_name() raises:
    var rig = Rig()
    assert_true(
        target(rig, ".bones[Hand].quaternion").value()
        == TrackTarget(QUATERNION, rig.hand.value, 0)
    )
    assert_false(Bool(target(rig, ".bones[Tail].position")))


def test_a_morph_track_finds_the_mesh_at_its_node() raises:
    var rig = Rig()
    assert_true(
        target(rig, "Hips.morphTargetInfluences[1]").value()
        == TrackTarget(MORPH_INFLUENCE, 0, 1)
    )
    assert_true(
        target(rig, "Hips.morphTargetInfluences[smile]").value()
        == TrackTarget(MORPH_INFLUENCE, 0, 0)
    )
    assert_equal(target(rig, "Hips.morphTargetInfluences").value().slot, -1)
    assert_false(Bool(target(rig, "Hips.morphTargetInfluences[frown]")))
    assert_false(Bool(target(rig, "Hand.morphTargetInfluences[0]")))


def test_a_light_track_finds_the_light_at_its_node() raises:
    var rig = Rig()
    assert_true(
        target(rig, "Lamp.intensity").value()
        == TrackTarget(LIGHT_INTENSITY, 0, 0)
    )
    assert_false(Bool(target(rig, "Hand.intensity")))


def test_a_material_track_finds_the_mesh_material() raises:
    var rig = Rig()
    var paint = rig.scene.meshes[0].material.value
    assert_true(
        target(rig, "Hips.material.opacity").value()
        == TrackTarget(MATERIAL_OPACITY, paint, 0)
    )
    assert_true(
        target(rig, "Hips.map.offset").value()
        == TrackTarget(MATERIAL_MAP_OFFSET, paint, 0)
    )
    assert_false(Bool(target(rig, "Hand.material.opacity")))
    assert_false(Bool(target(rig, "Hips.materials.opacity")))
    assert_false(Bool(target(rig, "Hips.material[0].opacity")))
    # A camera's property: nothing to bind.
    assert_false(Bool(target(rig, "Hips.fov")))


def test_a_scene_with_nothing_to_bind_binds_nothing() raises:
    var bare = Scene()
    var root = bare.add(named("Root"))
    assert_false(Bool(track_target(bare, root, ".morphTargetInfluences[0]")))
    assert_false(Bool(track_target(bare, root, ".intensity")))
    assert_false(Bool(track_target(bare, root, ".material.opacity")))
    with assert_raises():
        _ = track_target(bare, NodeId(7), ".position")


def test_the_loader_reads_threes_clips() raises:
    var rig = Rig()
    var clips = read_animations(
        "assets/animation/clips.json", rig.scene, rig.root
    )
    # three.js keeps all three; `lost` finds no node, so it is left out.
    assert_equal(len(clips), 2)
    assert_equal(clips[0].name, "walk")
    assert_almost_equal(clips[0].length, 2)
    assert_equal(clips[0].track_count(), 3)
    assert_true(
        clips[0].tracks[2].target == TrackTarget(MATERIAL_OPACITY, 0, 0)
    )
    assert_equal(clips[1].name, "wave")
    assert_almost_equal(clips[1].length, 0.5)
    # `Nobody.position[x]` is left out.
    assert_equal(clips[1].track_count(), 1)
    var raised = clips[1].tracks[0].sample(Duration(0.25, SECOND))
    assert_almost_equal(raised[0], 1)


def test_the_loader_refuses_what_is_not_an_array_of_clips() raises:
    var rig = Rig()
    with assert_raises(contains="array"):
        _ = parse_animations('{"name": "walk"}', rig.scene, rig.root)
    with assert_raises():
        _ = parse_animations("[1]", rig.scene, rig.root)
    with assert_raises():
        _ = read_animations("assets/animation/none.json", rig.scene, rig.root)
    assert_equal(len(parse_animations("[]", rig.scene, rig.root)), 0)


def moving_clip(node: NodeId, other: NodeId) raises -> AnimationClip:
    """Return a clip that turns `node`, moves `other`, then moves `node`
    through three keys: three.js's reference track."""
    var times: List[Duration] = [
        Duration(0, SECOND),
        Duration(1, SECOND),
        Duration(3, SECOND),
    ]
    var turn = KeyframeTrack(
        node,
        QUATERNION,
        [Duration(0, SECOND), Duration(1, SECOND)],
        [Float32(0), 0, 0, 1, 0, 0, 0, 1],
    )
    var aside = KeyframeTrack(
        other, POSITION, times, [Float32(5), 5, 5, 5, 5, 5, 5, 5, 5]
    )
    var move = KeyframeTrack(
        node, POSITION, times, [Float32(0), 0, 0, 2, 0, 0, 2, 4, 0]
    )
    return AnimationClip("move", [turn^, aside^, move^])


def test_the_helper_finds_the_nodes_position_track() raises:
    var clip = moving_clip(NodeId(1), NodeId(2))
    assert_equal(position_track(clip, NodeId(1)), 2)
    assert_equal(position_track(clip, NodeId(2)), 1)
    assert_equal(position_track(clip, NodeId(3)), -1)


def test_the_path_is_threes_samples() raises:
    var clip = moving_clip(NodeId(1), NodeId(2))
    var path = animation_path(clip, NodeId(1), 4)
    ref points = path.attribute_view(POSITION_ATTRIBUTE)
    var expected: List[Float32] = [
        0,
        0,
        0,
        1.5,
        0,
        0,
        2,
        1,
        0,
        2,
        2.5,
        0,
        2,
        4,
        0,
    ]
    assert_equal(len(points.data), len(expected))
    for index in range(len(expected)):
        assert_almost_equal(points.data[index], expected[index], atol=1e-5)
    var markers = animation_path_markers(clip, NodeId(1))
    ref keys = markers.attribute_view(POSITION_ATTRIBUTE)
    assert_equal(keys.count(), 3)
    assert_almost_equal(keys.data[7], 4)
    with assert_raises(contains="division"):
        _ = animation_path(clip, NodeId(1), 0)
    with assert_raises(contains="no position track"):
        _ = animation_path(clip, NodeId(3))
    with assert_raises(contains="no position track"):
        _ = animation_path_markers(clip, NodeId(3))


def test_the_helper_rides_the_nodes_parent() raises:
    var scene = Scene()
    var assets = Assets()
    var parent = scene.add(Object3D())
    var node = scene.attach(Object3D(), parent)
    var clip = moving_clip(node, parent)
    var helper = add_animation_path_helper(scene, assets, clip, node)
    assert_equal(scene.get(helper.node).parent, parent)
    assert_equal(len(scene.lines), 1)
    assert_equal(len(scene.points), 1)
    ref path = assets.geometries.get(helper.line.geometry)
    assert_equal(path.attribute_view(POSITION_ATTRIBUTE).count(), 101)
    var markers = assets.materials.get(helper.points.value().material)
    assert_false(markers.tone_mapped)
    assert_false(markers.size_attenuation)
    assert_true(markers.point_size == DEFAULT_MARKER_SIZE)
    assert_false(assets.materials.get(helper.line.material).tone_mapped)
    var bare = add_animation_path_helper(
        scene, assets, clip, node, divisions=8, show_markers=False
    )
    assert_false(Bool(bare.points))
    assert_equal(len(scene.points), 1)
    with assert_raises():
        _ = add_animation_path_helper(scene, assets, clip, NodeId(40))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
