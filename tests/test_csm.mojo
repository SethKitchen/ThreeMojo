# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `lights.csm` and the cascade arithmetic in `lights.shadow`:
the splits, the frustums, the lights a `CSM` adds and how a fragment's
depth picks its cascade."""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from lights.csm import (
    CSM,
    CUSTOM_SPLIT,
    LOGARITHMIC_SPLIT,
    PRACTICAL_LAMBDA,
    PRACTICAL_SPLIT,
    UNIFORM_SPLIT,
    CsmFrustum,
    CsmMode,
    logarithmic_split,
    practical_split,
    uniform_split,
)
from lights.light import DIRECTIONAL, directional_light, point_light
from lights.lighting import Lighting
from lights.shadow import ShadowCascade, cascade_reach, view_depth
from math.vector3 import Vector3
from render.framebuffer import Color
from renderers.renderer import camera_back, camera_position
from std.math import inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime WHITE = Color(255, 255, 255)
comptime UP = Vector3(0, 1, 0)


def eye() raises -> PerspectiveCamera:
    """Return a square ninety-degree camera from one meter to a hundred,
    at the origin looking down -z."""
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1, Length(1.0, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 0), Vector3(0, 0, -1))
    return camera^


def assert_close(a: Vector3, b: Vector3, atol: Float64 = 1e-3) raises:
    """Assert two vectors agree in every component."""
    assert_almost_equal(a.x, b.x, atol=atol)
    assert_almost_equal(a.y, b.y, atol=atol)
    assert_almost_equal(a.z, b.z, atol=atol)


# --- the split modes --------------------------------------------------------


def test_a_split_mode_is_one_of_three_js_four() raises:
    for mode in [UNIFORM_SPLIT, LOGARITHMIC_SPLIT, PRACTICAL_SPLIT]:
        assert_true(mode.is_valid())
    assert_true(CUSTOM_SPLIT.is_valid())
    assert_false(CsmMode(4).is_valid())
    assert_false(CsmMode(-1).is_valid())


def test_the_splits_follow_three_js_arithmetic() raises:
    var even = uniform_split(3, 1, 100)
    assert_equal(len(even), 3)
    assert_almost_equal(even[0], 0.34, atol=1e-6)
    assert_almost_equal(even[1], 0.67, atol=1e-6)
    assert_equal(even[2], 1)
    var ratio = logarithmic_split(3, 1, 100)
    assert_almost_equal(ratio[0], 0.0464159, atol=1e-6)
    assert_almost_equal(ratio[1], 0.2154435, atol=1e-6)
    assert_equal(ratio[2], 1)
    var both = practical_split(3, 1, 100, PRACTICAL_LAMBDA)
    assert_almost_equal(both[0], (0.34 + 0.0464159) / 2, atol=1e-6)
    assert_almost_equal(both[1], (0.67 + 0.2154435) / 2, atol=1e-6)
    assert_equal(both[2], 1)
    # One slice is the whole depth, in every mode.
    assert_equal(len(uniform_split(1, 1, 100)), 1)
    assert_equal(logarithmic_split(1, 1, 100)[0], 1)
    assert_equal(practical_split(1, 1, 100, 0.5)[0], 1)


# --- the frustum ------------------------------------------------------------


def test_a_frustum_is_the_camera_volume_cut_at_the_furthest_depth() raises:
    var camera = eye()
    var whole = CsmFrustum.from_projection(camera.projection_matrix(), 1000)
    assert_close(whole.near[0], Vector3(1, 1, -1))
    assert_close(whole.near[1], Vector3(1, -1, -1))
    assert_close(whole.near[2], Vector3(-1, -1, -1))
    assert_close(whole.near[3], Vector3(-1, 1, -1))
    assert_close(whole.far[0], Vector3(100, 100, -100), 0.05)
    # Cut at fifty meters, a perspective corner comes in along its ray.
    var cut = CsmFrustum.from_projection(camera.projection_matrix(), 50)
    assert_close(cut.far[2], Vector3(-50, -50, -50), 0.05)
    # An orthographic one comes in along its axis alone.
    var flat = OrthographicCamera(
        Length(-2.0, METER),
        Length(2.0, METER),
        Length(1.0, METER),
        Length(-1.0, METER),
        Length(1.0, METER),
        Length(10.0, METER),
    )
    var box = CsmFrustum.from_projection(flat.projection_matrix(), 5)
    assert_close(box.near[0], Vector3(2, 1, -1))
    assert_close(box.far[2], Vector3(-2, -1, -5))


def test_a_frustum_splits_at_its_breaks_and_moves_whole() raises:
    var camera = eye()
    var whole = CsmFrustum.from_projection(camera.projection_matrix(), 1000)
    var breaks: List[Float32] = [0.5, 1]
    var slices = whole.split(breaks)
    assert_equal(len(slices), 2)
    assert_close(slices[0].near[0], whole.near[0])
    var middle = whole.near[0]
    middle.lerp_vectors(whole.near[0], whole.far[0], 0.5)
    assert_close(slices[0].far[0], middle, 0.05)
    assert_close(slices[1].near[0], middle, 0.05)
    assert_close(slices[1].far[0], whole.far[0], 0.05)
    assert_equal(len(whole.split(List[Float32]())), 0)
    var moved = CsmFrustum.empty().to_space(camera.projection_matrix())
    assert_equal(len(moved.near), 4)


# --- the cascade a fragment falls in ----------------------------------------


def test_a_depth_is_measured_along_the_way_the_camera_looks() raises:
    var back = Vector3(0, 0, 1)
    assert_equal(view_depth(Vector3(3, 2, -5), Vector3(0, 0, 0), back), 5)
    assert_equal(view_depth(Vector3(0, 0, 1), Vector3(0, 0, 3), back), 2)


def test_without_fade_a_depth_takes_one_slice() raises:
    var inside = cascade_reach(0.3, 0.2, 0.4, False, False)
    assert_equal(inside[0], 1)
    assert_equal(inside[1], 1)
    var before = cascade_reach(0.1, 0.2, 0.4, False, False)
    assert_equal(before[0], 0)
    assert_equal(before[1], 0)
    var after = cascade_reach(0.5, 0.2, 0.4, False, False)
    assert_equal(after[0], 0)
    # Past the last slice the light still shines, with no shadow.
    var beyond = cascade_reach(1.5, 0.4, 1, True, False)
    assert_equal(beyond[0], 1)
    assert_equal(beyond[1], 0)
    var edge = cascade_reach(0.4, 0.2, 0.4, False, False)
    assert_equal(edge[0], 0)


def test_with_fade_a_slice_ramps_across_its_margin() raises:
    var middle = cascade_reach(0.3, 0.2, 0.4, False, True)
    assert_almost_equal(middle[0], 1, atol=1e-6)
    assert_equal(middle[1], 1)
    var far_rim = cascade_reach(0.41, 0.2, 0.4, False, True)
    assert_almost_equal(far_rim[0], 0.25, atol=1e-4)
    assert_equal(far_rim[1], 1)
    var near_rim = cascade_reach(0.2, 0.2, 0.4, False, True)
    assert_almost_equal(near_rim[0], 0.5, atol=1e-4)
    var outside = cascade_reach(0.19, 0.2, 0.4, False, True)
    assert_equal(outside[0], 0)
    assert_equal(outside[1], 0)
    var past = cascade_reach(0.43, 0.2, 0.4, False, True)
    assert_equal(past[0], 0)
    # The last slice fades its shadow, not its light, past its middle.
    var fading = cascade_reach(0.9, 0.4, 1, True, True)
    assert_equal(fading[0], 1)
    assert_almost_equal(fading[1], 0.9, atol=1e-4)
    var gone = cascade_reach(2, 0.4, 1, True, True)
    assert_equal(gone[0], 1)
    assert_equal(gone[1], 0)
    var early = cascade_reach(0.5, 0.4, 1, True, True)
    assert_equal(early[0], 1)
    assert_equal(early[1], 1)
    # A slice that starts at zero has no margin before its middle.
    var first = cascade_reach(0.1, 0, 0.3, False, True)
    assert_equal(first[0], 1)
    assert_equal(first[1], 1)


def test_a_cascade_refuses_a_slice_no_depth_fits() raises:
    ShadowCascade.none().validate()
    assert_false(ShadowCascade.none().is_cascade())
    var fine = ShadowCascade(0, 0.5, Length(10.0, METER), False, False)
    fine.validate()
    assert_true(fine.is_cascade())
    for wrong in [nan[DType.float32](), inf[DType.float32](), Float32(-1)]:
        var span = fine
        span.span = Length(wrong, METER)
        with assert_raises():
            span.validate()
    for wrong in [nan[DType.float32](), Float32(-0.5)]:
        var start = fine
        start.start = wrong
        with assert_raises():
            start.validate()
    var end = fine
    end.end = inf[DType.float32]()
    with assert_raises():
        end.validate()
    var crossed = fine
    crossed.end = -0.25
    crossed.start = 0
    with assert_raises():
        crossed.validate()
    # Only a directional light is a cascade.
    var scene = Scene()
    var bulb = point_light(WHITE, scene.add(Object3D()))
    bulb.cascade = fine
    with assert_raises():
        bulb.validate()
    var sun = directional_light(WHITE, NodeId(0))
    sun.cascade = fine
    sun.validate()
    sun.cascade.span = Length(-1.0, METER)
    with assert_raises():
        sun.validate()


def test_lighting_weighs_a_cascade_by_the_depth() raises:
    var scene = Scene()
    var high = Object3D()
    high.set_position(0, 1, 0)
    var node = scene.add(high^)
    var near = directional_light(WHITE, node)
    near.cascade = ShadowCascade(0, 0.5, Length(10.0, METER), False, False)
    var far = directional_light(WHITE, node)
    far.cascade = ShadowCascade(0.5, 1, Length(10.0, METER), True, False)
    scene.add_light(near)
    scene.add_light(far)
    scene.update()
    var lighting = Lighting(scene, back=Vector3(0, 0, 1))
    assert_equal(len(lighting.cascades), 2)
    # Two meters in front: the near slice alone.
    var at = Vector3(0, 0, -2)
    assert_equal(lighting.direction_through(0, at, UP, True), 1)
    assert_equal(lighting.direction_through(1, at, UP, True), 0)
    # Eight meters: the far slice alone; the sum is one light either way.
    var further = Vector3(0, 0, -8)
    assert_equal(lighting.direction_through(0, further, UP, True), 0)
    assert_equal(lighting.direction_through(1, further, UP, True), 1)
    var single = Scene()
    var lone = single.add(Object3D())
    single.node(lone).set_position(0, 1, 0)
    single.add_light(directional_light(WHITE, lone))
    single.update()
    var one = Lighting(single).intensity_at(UP, at)
    assert_equal(lighting.intensity_at(UP, at).r, one.r)
    assert_equal(lighting.intensity_at(UP, further).r, one.r)
    # Every sum weighs it alike.
    var ramp = List[Float32]()
    assert_equal(
        lighting.toon_at(UP, at, ramp).r,
        Lighting(single).toon_at(UP, at, ramp).r,
    )


# --- the lights a CSM adds --------------------------------------------------


def test_a_csm_adds_one_casting_light_per_cascade() raises:
    var scene = Scene()
    var camera = eye()
    var csm = CSM(scene, camera, shadow_map_size=16)
    assert_equal(csm.cascades, 3)
    assert_equal(len(scene.lights), 3)
    assert_equal(len(csm.breaks), 3)
    assert_equal(csm.mode, PRACTICAL_SPLIT)
    for index in range(3):
        ref light = scene.lights[csm.lights[index]]
        assert_equal(light.kind, DIRECTIONAL)
        assert_true(light.cast_shadow)
        assert_equal(light.intensity, 3)
        assert_equal(light.shadow.map_size, 16)
        assert_equal(light.shadow.near.to(METER), 1)
        assert_equal(light.shadow.far.to(METER), 2000)
        assert_almost_equal(light.shadow.bias, 0.000001, atol=1e-9)
        assert_equal(light.target, csm.targets[index])
        assert_true(light.cascade.is_cascade())
        assert_almost_equal(light.cascade.span.to(METER), 99, atol=1e-4)
        assert_equal(light.cascade.last, index == 2)
    ref first = scene.lights[csm.lights[0]].cascade
    assert_equal(first.start, 0)
    assert_equal(first.end, csm.breaks[0])
    assert_equal(scene.lights[csm.lights[1]].cascade.start, csm.breaks[0])
    assert_close(
        csm.light_direction, Vector3(1, -1, 1) * (1 / sqrt(Float32(3)))
    )


def test_a_csm_sizes_each_shadow_camera_to_its_slice() raises:
    var scene = Scene()
    var camera = eye()
    var csm = CSM(scene, camera, cascades=1, mode=UNIFORM_SPLIT)
    ref shadow = scene.lights[csm.lights[0]].shadow
    var width = Float32(200) * sqrt(Float32(2))
    assert_almost_equal(shadow.right.to(METER), width / 2, atol=0.1)
    assert_almost_equal(shadow.left.to(METER), -width / 2, atol=0.1)
    assert_almost_equal(shadow.top.to(METER), width / 2, atol=0.1)
    # Fade widens every slice by its margin.
    csm.fade = True
    csm.update_frustums(scene, camera)
    var wider = scene.lights[csm.lights[0]].shadow.right.to(METER)
    assert_true(wider > width / 2)
    assert_true(scene.lights[csm.lights[0]].cascade.fade)
    # A near slice whose far diagonal is shorter than its long one takes
    # the long one.
    var deep = PerspectiveCamera(
        Angle(10.0, DEGREE), 1, Length(1.0, METER), Length(100.0, METER)
    )
    var narrow = Scene()
    var thin = CSM(narrow, deep, cascades=2, mode=UNIFORM_SPLIT)
    assert_true(narrow.lights[thin.lights[0]].shadow.right.to(METER) > 20)


def test_each_mode_gives_its_breaks() raises:
    var camera = eye()
    var scene = Scene()
    var even = CSM(scene, camera, mode=UNIFORM_SPLIT)
    assert_almost_equal(even.breaks[0], 0.34, atol=1e-6)
    var log = CSM(scene, camera, mode=LOGARITHMIC_SPLIT)
    assert_almost_equal(log.breaks[0], 0.0464159, atol=1e-6)
    var custom = CSM(
        scene, camera, mode=CUSTOM_SPLIT, custom_breaks=[0.1, 0.3, 1]
    )
    assert_almost_equal(custom.breaks[1], 0.3, atol=1e-6)
    # The nearer of the camera's far plane and the furthest depth is cut.
    var short = CSM(
        scene, camera, mode=UNIFORM_SPLIT, max_far=Length(50.0, METER)
    )
    assert_almost_equal(short.breaks[0], (1 + 49 / 3.0) / 50, atol=1e-6)
    assert_almost_equal(
        scene.lights[short.lights[0]].cascade.span.to(METER), 49, atol=1e-4
    )
    # A mode changed to none of the four is refused when the breaks are
    # worked out again.
    even.mode = CsmMode(7)
    with assert_raises():
        even.update_frustums(scene, camera)


def test_a_csm_refuses_what_it_cannot_slice() raises:
    var camera = eye()
    var scene = Scene()
    with assert_raises():
        _ = CSM(scene, camera, cascades=0)
    with assert_raises():
        _ = CSM(scene, camera, mode=CsmMode(5))
    with assert_raises():
        _ = CSM(scene, camera, light_direction=Vector3(0, 0, 0))
    with assert_raises():
        _ = CSM(
            scene, camera, light_direction=Vector3(nan[DType.float32](), 0, 0)
        )
    with assert_raises():
        _ = CSM(scene, camera, max_far=Length(0.0, METER))
    with assert_raises():
        _ = CSM(scene, camera, max_far=Length(inf[DType.float32](), METER))
    with assert_raises():
        _ = CSM(scene, camera, light_margin=Length(inf[DType.float32](), METER))
    with assert_raises():
        _ = CSM(scene, camera, shadow_map_size=0)
    with assert_raises():
        _ = CSM(scene, camera, shadow_map_size=9000)
    with assert_raises():
        _ = CSM(scene, camera, light_intensity=-1)
    with assert_raises():
        _ = CSM(scene, camera, mode=CUSTOM_SPLIT)
    with assert_raises():
        _ = CSM(scene, camera, mode=CUSTOM_SPLIT, custom_breaks=[0.5, 0.2, 1])
    with assert_raises():
        _ = CSM(scene, camera, mode=CUSTOM_SPLIT, custom_breaks=[0.5, 0.6, 2])
    with assert_raises():
        _ = CSM(
            scene,
            camera,
            mode=CUSTOM_SPLIT,
            custom_breaks=[nan[DType.float32](), 0.6, 1],
        )
    # Breaks for another mode are not read.
    _ = CSM(scene, camera, custom_breaks=[5])


def test_update_stands_each_light_behind_its_slice() raises:
    var scene = Scene()
    var parent = scene.add(Object3D())
    var camera = eye()
    var csm = CSM(scene, camera, parent=parent, shadow_map_size=64)
    csm.update(scene, camera)
    assert_equal(scene.get(csm.nodes[0]).parent, parent)
    for index in range(3):
        var at = scene.world_position(csm.nodes[index])
        var aim = scene.world_position(csm.targets[index])
        assert_close(aim - at, csm.light_direction)
        # The light stands up the sun's ray from the slice.
        assert_true(at.y > 0)
    # A light direction straight down still finds a frame.
    var down = Scene()
    var straight = CSM(down, camera, light_direction=Vector3(0, -1, 0))
    straight.update(down, camera)
    var at = down.world_position(straight.nodes[0])
    var aim = down.world_position(straight.targets[0])
    assert_close(aim - at, Vector3(0, -1, 0))


def test_a_csm_refuses_a_scene_without_its_lights() raises:
    var scene = Scene()
    var camera = eye()
    var csm = CSM(scene, camera)
    var other = Scene()
    with assert_raises():
        csm.update(other, camera)
    with assert_raises():
        csm.update_frustums(other, camera)
    with assert_raises():
        csm.dispose(other)
    scene.lights[csm.lights[1]].node = csm.targets[1]
    with assert_raises():
        csm.update(scene, camera)


def test_remove_and_dispose_undo_what_a_csm_did() raises:
    var scene = Scene()
    var camera = eye()
    var csm = CSM(scene, camera)
    csm.dispose(scene)
    for index in range(3):
        assert_false(scene.lights[csm.lights[index]].cascade.is_cascade())
    csm.remove(scene)
    for index in range(3):
        assert_false(scene.light_shown(scene.lights[csm.lights[index]]))
    # The lights resolve to nothing once their nodes are gone.
    assert_equal(Lighting(scene).count(), 0)


def test_a_csm_lights_a_surface_once_at_every_depth() raises:
    var scene = Scene()
    var camera = eye()
    var csm = CSM(scene, camera, cascades=2, light_direction=Vector3(0, -1, -1))
    csm.update(scene, camera)
    var lighting = Lighting(
        scene,
        eye=camera_position(scene, camera),
        back=camera_back(scene, camera),
    )
    var single = Scene()
    var node = single.add(Object3D())
    single.node(node).set_position(0, 1, 1)
    single.add_light(directional_light(WHITE, node, 3))
    single.update()
    var one = Lighting(single)
    for depth in [Float32(2), Float32(20), Float32(90), Float32(500)]:
        var at = Vector3(0, -1, -depth)
        assert_almost_equal(
            lighting.intensity_at(UP, at).r,
            one.intensity_at(UP, at).r,
            atol=1e-5,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
