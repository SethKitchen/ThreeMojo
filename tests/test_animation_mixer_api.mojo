# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the playback half of the animation API three.js has beside
the basics: the mixer's time scale, root and cache, an action's
repetitions, `set_duration`, `sync_with` and `reset`, and the tracks on a
camera, a light's other numbers, a material's flags, a node's name and a
skinned mesh's morph targets.

The expected positions of repeating actions are three.js's, from r180 run
in node, but for the one frame a `PING_PONG` action finishes on; see
`AnimationAction._finish_repeating`.
"""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import (
    AnimationAction,
    AnimationMixer,
    FINISHED,
    LOOPED,
    ONCE,
    PING_PONG,
    REPEAT,
    Loop,
    check_target,
    read_target,
    resolve_targets,
    write_target,
)
from animation.animation_object_group import AnimationObjectGroup
from animation.keyframe_track import (
    CAMERA_FAR,
    CAMERA_FOV,
    CAMERA_NEAR,
    CAMERA_ZOOM,
    KeyframeTrack,
    LIGHT_ANGLE,
    LIGHT_DISTANCE,
    LIGHT_INTENSITY,
    LIGHT_PENUMBRA,
    LightIndex,
    MATERIAL_TRANSPARENT,
    MATERIAL_WIREFRAME,
    NODE_NAME,
    OrthographicCameraIndex,
    POSITION,
    PerspectiveCameraIndex,
    SMOOTH,
    SkinnedMeshIndex,
    TrackTarget,
    light_target,
    material_target,
    node_target,
    orthographic_camera_target,
    perspective_camera_target,
    skinned_morph_target,
)
from cameras.camera_list import CameraList
from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from lights.light import point_light, spot_light
from materials.material import Material, MaterialId
from math.matrix4 import Matrix4
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SkinnedMesh
from render.framebuffer import Color
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, METER, RADIAN, SECOND

comptime TOLERANCE = Float64(1e-4)


def seconds(values: List[Float32]) -> List[Duration]:
    """Return the given numbers as durations in seconds."""
    var out = List[Duration]()
    for index in range(len(values)):
        out.append(Duration(values[index], SECOND))
    return out^


def at(value: Float32) -> Duration:
    """Return a time in seconds."""
    return Duration(value, SECOND)


def slide(length: Float32 = 1) raises -> AnimationClip:
    """Return a clip that slides node zero from x = 0 to x = 10 over
    `length` seconds."""
    return AnimationClip(
        "slide",
        [
            KeyframeTrack(
                NodeId(0), POSITION, seconds([0, length]), [0, 0, 0, 10, 0, 0]
            )
        ],
    )


def one_node() raises -> Scene:
    """Return a scene of one node."""
    var scene = Scene()
    _ = scene.add(Object3D())
    return scene^


def run(
    loop: Loop,
    repetitions: Optional[Int],
    scale: Float32,
    steps: Int,
    step: Float32,
) raises -> List[Float32]:
    """Play the slide under a loop mode and repetitions, clamped, and
    return x after each update."""
    var scene = one_node()
    var mixer = AnimationMixer()
    var action = AnimationAction(slide(), clamp_when_finished=True)
    action.set_loop(loop, repetitions)
    action.time_scale = scale
    var which = mixer.add(action^)
    mixer.action(which).play()
    var out = List[Float32]()
    for _ in range(steps):
        mixer.update(scene, at(step))
        out.append(scene.get(NodeId(0)).position.x)
    return out^


def expect(got: List[Float32], wanted: List[Float32]) raises:
    """Assert two runs of positions agree."""
    assert_equal(len(got), len(wanted))
    for index in range(len(wanted)):
        assert_almost_equal(
            Float64(got[index]), Float64(wanted[index]), atol=TOLERANCE
        )


# --- the mixer --------------------------------------------------------------


def test_the_mixer_time_scale_scales_every_delta() raises:
    var scene = one_node()
    var mixer = AnimationMixer()
    var which = mixer.add(AnimationAction(slide(2)))
    mixer.action(which).play()
    mixer.time_scale = 0.5
    mixer.update(scene, at(1))
    # three.js: x = 2.5 and a mixer time of 0.5.
    assert_almost_equal(
        Float64(scene.get(NodeId(0)).position.x), 2.5, atol=TOLERANCE
    )
    assert_almost_equal(mixer.time().to(SECOND), 0.5, atol=TOLERANCE)
    mixer.time_scale = nan[DType.float32]()
    with assert_raises(contains="time scale must be a number"):
        mixer.update(scene, at(1))
    mixer.time_scale = 2
    with assert_raises(contains="not a number"):
        mixer.update(scene, at(inf[DType.float32]()))


def test_the_mixer_keeps_its_root_and_files_actions_under_one() raises:
    var mixer = AnimationMixer(NodeId(3))
    assert_equal(mixer.get_root(), NodeId(3))
    assert_false(Bool(mixer.existing_action("slide")))
    var plain = mixer.add(AnimationAction(slide()))
    var rooted = mixer.add(AnimationAction(slide()), NodeId(1))
    assert_equal(mixer.existing_action("slide").value(), plain)
    assert_equal(mixer.existing_action("slide", NodeId(1)).value(), rooted)
    assert_false(Bool(mixer.existing_action("walk")))
    assert_equal(AnimationMixer().get_root(), NO_PARENT)


def test_stop_all_action_stops_the_active_ones() raises:
    var scene = one_node()
    var mixer = AnimationMixer()
    mixer.stop_all_action()
    var playing = mixer.add(AnimationAction(slide()))
    var idle = mixer.add(AnimationAction(slide()))
    mixer.action(playing).play()
    mixer.update(scene, at(0.5))
    mixer.action(idle).phase = 0.25
    mixer.stop_all_action()
    assert_false(mixer.action(playing).is_active())
    assert_equal(mixer.action(playing).phase, 0)
    # three.js stops only the actions that are running.
    assert_equal(mixer.action(idle).phase, 0.25)


def test_sync_with_takes_the_other_actions_place_and_pace() raises:
    var mixer = AnimationMixer()
    var first = mixer.add(AnimationAction(slide()))
    var second = mixer.add(AnimationAction(slide(), time_scale=3))
    mixer.action(second).phase = 0.75
    mixer.action(first).warp(1, 2, at(1))
    mixer.sync_with(first, second)
    assert_equal(mixer.action(first).phase, 0.75)
    assert_equal(mixer.action(first).time_scale, 3)
    assert_false(mixer.action(first).warping)
    with assert_raises(contains="no action"):
        mixer.sync_with(first, 5)


def test_uncaching_an_action_keeps_every_index() raises:
    var scene = one_node()
    var mixer = AnimationMixer()
    var first = mixer.add(AnimationAction(slide()))
    var second = mixer.add(AnimationAction(slide()), NodeId(0))
    mixer.action(first).play()
    mixer.update(scene, at(0.5))
    assert_equal(mixer.binding_count(), 1)
    mixer.uncache_action(first)
    assert_equal(mixer.action_count(), 2)
    with assert_raises(contains="uncached"):
        _ = mixer.action(first)
    with assert_raises(contains="uncached"):
        mixer.uncache_action(first)
    # Still driven in the last update, so kept until the next one puts
    # the node back.
    assert_equal(mixer.binding_count(), 1)
    mixer.update(scene, at(0.5))
    assert_equal(scene.get(NodeId(0)).position.x, 0)
    mixer.uncache_action("slide", NodeId(0))
    assert_equal(mixer.binding_count(), 0)
    with assert_raises(contains="no action on a clip"):
        mixer.uncache_action("slide", NodeId(0))
    _ = second


def test_uncaching_a_clip_or_a_root_forgets_its_actions() raises:
    var mixer = AnimationMixer()
    mixer.uncache_clip("slide")
    mixer.uncache_root(NodeId(0))
    var first = mixer.add(AnimationAction(slide()))
    var other = mixer.add(
        AnimationAction(
            AnimationClip(
                "other",
                [
                    KeyframeTrack(
                        NodeId(0), POSITION, seconds([0, 1]), [0, 0, 0, 1, 0, 0]
                    )
                ],
            )
        ),
        NodeId(2),
    )
    var third = mixer.add(AnimationAction(slide()), NodeId(2))
    mixer.uncache_clip("slide")
    assert_false(Bool(mixer.existing_action("slide")))
    assert_equal(mixer.existing_action("other", NodeId(2)).value(), other)
    mixer.uncache_clip("slide")
    var kept = mixer.add(
        AnimationAction(
            AnimationClip(
                "kept",
                [
                    KeyframeTrack(
                        NodeId(0), POSITION, seconds([0, 1]), [0, 0, 0, 1, 0, 0]
                    )
                ],
            )
        )
    )
    mixer.uncache_root(NodeId(2))
    assert_false(Bool(mixer.existing_action("other", NodeId(2))))
    assert_equal(mixer.existing_action("kept").value(), kept)
    with assert_raises(contains="uncached"):
        _ = mixer.action(third)
    with assert_raises(contains="uncached"):
        mixer.cross_fade_from(first, other, at(1))
    mixer.uncache_root(NodeId(2))
    # An update steps over every uncached action.
    var scene = one_node()
    mixer.update(scene, at(1))
    mixer.stop_all_action()


# --- the action -------------------------------------------------------------


def test_repetitions_finish_a_repeating_action_as_three_js_does() raises:
    expect(run(REPEAT, 0, 1, 4, 0.4), [4, 8, 10, 10])
    expect(run(REPEAT, 1, 1, 4, 0.4), [4, 8, 10, 10])
    expect(run(REPEAT, 2, 1, 6, 0.4), [4, 8, 2, 6, 10, 10])
    # Backward, the first pass through zero is not a repetition.
    expect(run(REPEAT, 1, -1, 4, 0.4), [6, 2, 0, 0])
    expect(run(REPEAT, 2, -1, 6, 0.4), [6, 2, 8, 4, 0, 0])


def test_repetitions_count_each_ping_pong_leg() raises:
    # three.js reads the other end on the frame it finishes, and this
    # one from the next frame on; here it is read on both.
    expect(run(PING_PONG, 1, 1, 4, 0.4), [4, 8, 10, 10])
    expect(run(PING_PONG, 2, 1, 6, 0.4), [4, 8, 8, 4, 0, 0])
    expect(run(PING_PONG, 3, 1, 8, 0.4), [4, 8, 8, 4, 0, 4, 8, 10])
    expect(run(PING_PONG, 1, -1, 4, 0.4), [6, 2, 0, 0])
    expect(run(PING_PONG, 2, -1, 6, 0.3), [7, 4, 1, 2, 5, 8])
    expect(run(PING_PONG, 0, -1, 3, 0.4), [0, 0, 0])


def test_a_finished_repeat_is_an_event_and_not_a_loop() raises:
    var scene = one_node()
    var mixer = AnimationMixer()
    var action = AnimationAction(slide())
    action.set_loop(REPEAT, 1)
    var which = mixer.add(action^)
    mixer.action(which).play()
    mixer.update(scene, at(1.5))
    var events = mixer.drain_events()
    assert_equal(len(events), 1)
    assert_equal(events[0].kind, FINISHED)
    assert_false(mixer.action(which).is_active())
    # Many ends passed at once: it stops at the one its repetitions end
    # at, the end of the second leg, which is the start of the clip.
    var bounce = AnimationAction(slide())
    bounce.set_loop(PING_PONG, 2)
    bounce.clamp_when_finished = True
    var other = mixer.add(bounce^)
    mixer.action(other).play()
    mixer.update(scene, at(3.5))
    assert_equal(mixer.action(other).phase, 0)
    var backward = AnimationAction(slide(), time_scale=-1)
    backward.set_loop(PING_PONG, 1)
    backward.clamp_when_finished = True
    var third = mixer.add(backward^)
    mixer.action(third).play()
    mixer.update(scene, at(0.5))
    assert_equal(len(mixer.drain_events()), 1)
    mixer.update(scene, at(3))
    assert_equal(mixer.action(third).phase, 0)
    _ = LOOPED


def test_set_loop_refuses_what_is_not_a_loop() raises:
    var action = AnimationAction(slide())
    with assert_raises(contains="loop mode"):
        action.set_loop(Loop(7))
    with assert_raises(contains="fewer than zero"):
        action.set_loop(REPEAT, -1)
    action.set_loop(ONCE)
    assert_equal(action.loop, ONCE)
    assert_false(Bool(action.repetitions))


def test_set_duration_sets_the_time_scale() raises:
    var action = AnimationAction(slide(2))
    action.warp(1, 2, at(1))
    action.set_duration(at(4))
    assert_equal(action.time_scale, 0.5)
    assert_false(action.warping)
    action.set_duration(at(-1))
    assert_equal(action.time_scale, -2)
    with assert_raises(contains="other than zero"):
        action.set_duration(at(0))
    with assert_raises(contains="other than zero"):
        action.set_duration(at(nan[DType.float32]()))


def test_reset_rewinds_and_keeps_the_action_active() raises:
    var scene = one_node()
    var mixer = AnimationMixer()
    var which = mixer.add(AnimationAction(slide()))
    mixer.action(which).play()
    mixer.update(scene, at(1.5))
    mixer.action(which).pause()
    mixer.action(which).fade_in(at(1))
    mixer.action(which).reset()
    ref action = mixer.action(which)
    assert_true(action.is_active())
    assert_false(action.paused)
    assert_equal(action.phase, 0)
    assert_equal(action.loop_count, -1)
    assert_false(action.fading)


def test_a_repeating_smooth_track_ends_flat_before_its_last_run() raises:
    var scene = one_node()
    var mixer = AnimationMixer()
    var clip = AnimationClip(
        "s",
        [
            KeyframeTrack(
                NodeId(0),
                POSITION,
                seconds([0, 0.5, 1]),
                [0, 0, 0, 5, 0, 0, 0, 0, 0],
                SMOOTH,
            )
        ],
    )
    var action = AnimationAction(clip^)
    action.set_loop(REPEAT, 3)
    var which = mixer.add(action^)
    mixer.action(which).play()
    mixer.update(scene, at(1.25))
    # Two runs left: both ends wrap.
    assert_equal(mixer.action(which).ending_end.value, 2)
    mixer.update(scene, at(1))
    # The last run: the end is flat.
    assert_equal(mixer.action(which).ending_end.value, 1)
    assert_equal(mixer.action(which).ending_start.value, 2)


# --- the new targets --------------------------------------------------------


def cameras() raises -> CameraList:
    """Return a perspective camera and an orthographic one, both on node
    zero."""
    var list = CameraList()
    var eye = PerspectiveCamera(
        Angle(50, DEGREE), 1, Length(0.1, METER), Length(100, METER)
    )
    eye.attach(NodeId(0))
    list.perspective.append(eye)
    var lens = OrthographicCamera(
        Length(-1, METER),
        Length(1, METER),
        Length(1, METER),
        Length(-1, METER),
        Length(0.1, METER),
        Length(10, METER),
    )
    lens.attach(NodeId(0))
    list.orthographic.append(lens^)
    return list^


def play(
    mut mixer: AnimationMixer, target: TrackTarget, start: Float32, end: Float32
) raises -> Int:
    """Add and play a two-second track from `start` to `end`."""
    var which = mixer.add(
        AnimationAction(
            AnimationClip(
                "one",
                [KeyframeTrack(target, seconds([0, 2]), [start, end])],
            )
        )
    )
    mixer.action(which).play()
    return which


def test_a_mixer_drives_a_cameras_numbers() raises:
    var scene = one_node()
    var assets = Assets()
    var lenses = cameras()
    var mixer = AnimationMixer()
    var eye = PerspectiveCameraIndex(0)
    var lens = OrthographicCameraIndex(0)
    _ = play(mixer, perspective_camera_target(eye, CAMERA_FOV), 50, 70)
    _ = play(mixer, perspective_camera_target(eye, CAMERA_ZOOM), 1, 3)
    _ = play(mixer, perspective_camera_target(eye, CAMERA_NEAR), 0.1, 1.1)
    _ = play(mixer, perspective_camera_target(eye, CAMERA_FAR), 100, 50)
    _ = play(mixer, orthographic_camera_target(lens, CAMERA_ZOOM), 1, 2)
    _ = play(mixer, orthographic_camera_target(lens, CAMERA_NEAR), 0.1, 2.1)
    _ = play(mixer, orthographic_camera_target(lens, CAMERA_FAR), 10, 20)
    mixer.update(scene, assets, lenses, at(1))
    ref moved = lenses.perspective[0]
    assert_almost_equal(Float64(moved.fov.to(DEGREE)), 60, atol=TOLERANCE)
    assert_almost_equal(Float64(moved.zoom), 2, atol=TOLERANCE)
    assert_almost_equal(Float64(moved.near.to(METER)), 0.6, atol=TOLERANCE)
    assert_almost_equal(Float64(moved.far.to(METER)), 75, atol=TOLERANCE)
    ref plan = lenses.orthographic[0]
    assert_almost_equal(Float64(plan.zoom), 1.5, atol=TOLERANCE)
    assert_almost_equal(Float64(plan.near.to(METER)), 1.1, atol=TOLERANCE)
    assert_almost_equal(Float64(plan.far.to(METER)), 15, atol=TOLERANCE)
    # Stopped, each goes back to what it held.
    mixer.stop_all_action()
    mixer.update(scene, assets, lenses, at(1))
    assert_almost_equal(
        Float64(lenses.perspective[0].fov.to(DEGREE)), 50, atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(lenses.orthographic[0].far.to(METER)), 10, atol=TOLERANCE
    )


def test_a_camera_track_needs_the_cameras() raises:
    var scene = one_node()
    var assets = Assets()
    var mixer = AnimationMixer()
    _ = play(
        mixer,
        perspective_camera_target(PerspectiveCameraIndex(0), CAMERA_FOV),
        50,
        60,
    )
    with assert_raises(contains="needs the cameras"):
        mixer.update(scene, assets, at(1))
    var none = CameraList()
    with assert_raises(contains="camera that is there"):
        mixer.update(scene, assets, none, at(1))
    var lens = orthographic_camera_target(
        OrthographicCameraIndex(1), CAMERA_FAR
    )
    with assert_raises(contains="camera that is there"):
        check_target(scene, assets, True, lens, cameras(), True)


def refuse(
    mut scene: Scene,
    mut assets: Assets,
    mut lenses: CameraList,
    target: TrackTarget,
    value: Float32,
    text: String,
) raises:
    """Assert that writing `value` to a camera is refused with `text`."""
    var values: List[Float32] = [value, 0, 0, 0]
    with assert_raises(contains=text):
        write_target(scene, assets, lenses, target, values, 0)


def test_a_camera_number_it_cannot_hold_is_refused() raises:
    var scene = one_node()
    var assets = Assets()
    var lenses = cameras()
    var eye = PerspectiveCameraIndex(0)
    var lens = OrthographicCameraIndex(0)
    var eye_fov = perspective_camera_target(eye, CAMERA_FOV)
    refuse(scene, assets, lenses, eye_fov, 0, "field of view")
    refuse(scene, assets, lenses, eye_fov, 180, "field of view")
    var eye_zoom = perspective_camera_target(eye, CAMERA_ZOOM)
    refuse(scene, assets, lenses, eye_zoom, 0, "zoom")
    var eye_near = perspective_camera_target(eye, CAMERA_NEAR)
    refuse(scene, assets, lenses, eye_near, 0, "near plane")
    var eye_far = perspective_camera_target(eye, CAMERA_FAR)
    refuse(scene, assets, lenses, eye_far, 0.05, "near plane")
    var plan_near = orthographic_camera_target(lens, CAMERA_NEAR)
    refuse(scene, assets, lenses, plan_near, 10, "far plane")
    refuse(
        scene, assets, lenses, plan_near, inf[DType.float32](), "cannot hold"
    )
    var plan_zoom = orthographic_camera_target(lens, CAMERA_ZOOM)
    refuse(scene, assets, lenses, plan_zoom, 0, "zoom")
    # An orthographic near plane can be below zero, as three.js's can.
    var behind: List[Float32] = [-1, 0, 0, 0]
    write_target(
        scene,
        assets,
        lenses,
        orthographic_camera_target(lens, CAMERA_NEAR),
        behind,
        0,
    )
    assert_equal(lenses.orthographic[0].near.to(METER), -1)
    assert_equal(
        read_target(
            scene,
            assets,
            orthographic_camera_target(lens, CAMERA_NEAR),
            lenses,
        )[0],
        -1,
    )


def test_a_camera_on_a_removed_node_is_not_driven() raises:
    var scene = one_node()
    var assets = Assets()
    var lenses = cameras()
    scene.remove(NodeId(0))
    var values: List[Float32] = [70, 0, 0, 0]
    write_target(
        scene,
        assets,
        lenses,
        perspective_camera_target(PerspectiveCameraIndex(0), CAMERA_FOV),
        values,
        0,
    )
    assert_almost_equal(
        Float64(lenses.perspective[0].fov.to(DEGREE)), 50, atol=TOLERANCE
    )


def lamps() raises -> Scene:
    """Return a scene of one node carrying a spot light and a point
    light."""
    var scene = one_node()
    scene.add_light(spot_light(Color(255, 255, 255), NodeId(0), 1, 10))
    scene.add_light(point_light(Color(255, 255, 255), NodeId(0), 1))
    return scene^


def test_a_mixer_drives_a_lights_other_numbers() raises:
    var scene = lamps()
    var mixer = AnimationMixer()
    var spot = LightIndex(0)
    _ = play(mixer, light_target(spot, LIGHT_DISTANCE), 10, 20)
    _ = play(mixer, light_target(spot, LIGHT_ANGLE), 0.5, 0.7)
    _ = play(mixer, light_target(spot, LIGHT_PENUMBRA), 0, 0.5)
    _ = play(mixer, light_target(spot, LIGHT_INTENSITY), 1, 3)
    mixer.update(scene, at(1))
    ref light = scene.lights[0]
    assert_almost_equal(Float64(light.distance), 15, atol=TOLERANCE)
    assert_almost_equal(Float64(light.angle.to(RADIAN)), 0.6, atol=TOLERANCE)
    assert_almost_equal(Float64(light.penumbra), 0.25, atol=TOLERANCE)
    assert_almost_equal(Float64(light.intensity), 2, atol=TOLERANCE)
    var bad = AnimationMixer()
    _ = play(bad, light_target(spot, LIGHT_PENUMBRA), 0, 4)
    with assert_raises(contains="penumbra"):
        bad.update(scene, at(1.5))


def test_a_mixer_drives_a_materials_flags() raises:
    var scene = one_node()
    var assets = Assets()
    _ = assets.materials.add(Material(Color(0, 0, 0)))
    var mixer = AnimationMixer()
    var clip = AnimationClip(
        "flags",
        [
            KeyframeTrack(
                material_target(MaterialId(0), MATERIAL_TRANSPARENT),
                seconds([0, 1]),
                [0, 1],
            ),
            KeyframeTrack(
                material_target(MaterialId(0), MATERIAL_WIREFRAME),
                seconds([0, 1]),
                [1, 0],
            ),
        ],
    )
    var which = mixer.add(
        AnimationAction(clip^, loop=ONCE, clamp_when_finished=True)
    )
    mixer.action(which).play()
    mixer.update(scene, assets, at(0.5))
    assert_false(assets.materials.materials[0].transparent)
    assert_true(assets.materials.materials[0].wireframe)
    mixer.update(scene, assets, at(0.6))
    assert_true(assets.materials.materials[0].transparent)
    assert_false(assets.materials.materials[0].wireframe)
    # Stopped, both go back.
    mixer.stop_all_action()
    mixer.update(scene, assets, at(0.1))
    assert_false(assets.materials.materials[0].transparent)
    assert_false(assets.materials.materials[0].wireframe)


def test_a_mixer_drives_a_nodes_name() raises:
    var scene = one_node()
    var named = scene.get(NodeId(0))
    named.name = "start"
    scene.set(NodeId(0), named^)
    var mixer = AnimationMixer()
    var target = node_target(NodeId(0), NODE_NAME)
    var clip = AnimationClip(
        "rename",
        [KeyframeTrack(target, seconds([0, 1, 2]), ["a", "b", "a"])],
    )
    var which = mixer.add(AnimationAction(clip^))
    mixer.action(which).play()
    mixer.update(scene, at(0.5))
    assert_equal(scene.get(NodeId(0)).name, "a")
    # The same string again is found in the mixer's strings.
    mixer.update(scene, at(0.1))
    assert_equal(scene.get(NodeId(0)).name, "a")
    mixer.update(scene, at(1))
    assert_equal(scene.get(NodeId(0)).name, "b")
    mixer.action(which).stop()
    mixer.update(scene, at(0.1))
    assert_equal(scene.get(NodeId(0)).name, "start")
    var assets = Assets()
    with assert_raises(contains="mixer's strings"):
        _ = read_target(scene, assets, target)
    var lenses = CameraList()
    var values: List[Float32] = [3, 0, 0, 0]
    with assert_raises(contains="does not hold"):
        write_target(scene, assets, lenses, target, values, 0)
    values[0] = -1
    with assert_raises(contains="does not hold"):
        write_target(scene, assets, lenses, target, values, 0)


def rig() raises -> Scene:
    """Return a scene of a root node and a bone under it, with a skinned
    mesh at the root, and a plain node beside them."""
    var scene = Scene()
    var root = scene.add(Object3D())
    var bone = scene.attach(Object3D(), root)
    _ = scene.add(Object3D())
    scene.add_skinned_mesh(
        SkinnedMesh(
            GeometryId(0),
            MaterialId(0),
            root,
            Skeleton([Bone(bone, Matrix4())]),
        )
    )
    return scene^


def test_a_mixer_drives_a_skinned_meshs_morph_targets() raises:
    var scene = rig()
    var mixer = AnimationMixer()
    _ = play(mixer, skinned_morph_target(SkinnedMeshIndex(0), 2), 0, 1)
    mixer.update(scene, at(1))
    assert_almost_equal(
        Float64(scene.skinned_meshes[0].morph_influence(2)),
        0.5,
        atol=TOLERANCE,
    )
    mixer.stop_all_action()
    mixer.update(scene, at(1))
    assert_equal(scene.skinned_meshes[0].morph_influence(2), 0)
    var assets = Assets()
    with assert_raises(contains="that is there"):
        check_target(
            scene,
            assets,
            False,
            skinned_morph_target(SkinnedMeshIndex(1), 0),
        )


def test_a_group_reaches_skinned_meshes_and_cameras_at_its_members() raises:
    var scene = rig()
    var lenses = cameras()
    var group = AnimationObjectGroup()
    group.add(NodeId(0))
    group.add(NodeId(2))
    var skins = resolve_targets(
        scene, skinned_morph_target(SkinnedMeshIndex(9), 1), group
    )
    assert_equal(len(skins), 1)
    assert_equal(skins[0].index, 0)
    assert_equal(skins[0].slot, 1)
    var eyes = resolve_targets(
        scene,
        perspective_camera_target(PerspectiveCameraIndex(9), CAMERA_FOV),
        group,
        lenses,
    )
    assert_equal(len(eyes), 1)
    var plans = resolve_targets(
        scene,
        orthographic_camera_target(OrthographicCameraIndex(9), CAMERA_ZOOM),
        group,
        lenses,
    )
    assert_equal(len(plans), 1)
    assert_equal(plans[0].slot, 1)
    # A scene with no skinned meshes reaches none.
    var bare = AnimationObjectGroup()
    bare.add(NodeId(0))
    assert_equal(
        len(
            resolve_targets(
                one_node(), skinned_morph_target(SkinnedMeshIndex(0), 1), bare
            )
        ),
        0,
    )
    # No cameras at all: none are reached.
    assert_equal(
        len(
            resolve_targets(
                scene,
                perspective_camera_target(
                    PerspectiveCameraIndex(0), CAMERA_FOV
                ),
                group,
            )
        ),
        0,
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
