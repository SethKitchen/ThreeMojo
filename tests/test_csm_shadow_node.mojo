# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `lights.csm_shadow_node`, the `NODE_BLEND` cascades of
`lights.shadow`, and the functions `lights.csm` shares with the node.

`three_js_shadow` is three.js's `_setupStandard` and `_setupFade` written
out as the shader runs them: one loop over the cascades and one shadow
value. The shares of `csm_node_reach` are checked against it."""

from cameras.perspective_camera import PerspectiveCamera
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from lights.csm import (
    CSM,
    CUSTOM_SPLIT,
    PRACTICAL_SPLIT,
    UNIFORM_SPLIT,
    CsmFrustum,
    CsmMode,
    csm_breaks,
    practical_split,
    require_cascade_lights,
    require_custom_breaks,
)
from lights.csm_shadow_node import CSMShadowNode
from lights.light import DIRECTIONAL, Light, directional_light, point_light
from lights.lighting import Lighting
from lights.shadow import (
    CSM_BLEND,
    NODE_BLEND,
    SUN_BLEND,
    CascadeBlend,
    ShadowCascade,
    csm_node_reach,
)
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import inf, max, min, nan, sqrt
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


def sun(mut scene: Scene, at: Vector3) raises -> Light:
    """Return a casting directional light on a new node at `at`, shining
    toward the origin, with a map of sixteen texels."""
    var node = scene.add(Object3D())
    scene.node(node).set_position(at.x, at.y, at.z)
    var light = directional_light(WHITE, node, 2)
    light.cast_shadow = True
    light.shadow.map_size = 16
    light.shadow.bias = 0.001
    return light


def assert_close(a: Vector3, b: Vector3, atol: Float64 = 1e-3) raises:
    """Assert two vectors agree in every component."""
    assert_almost_equal(a.x, b.x, atol=atol)
    assert_almost_equal(a.y, b.y, atol=atol)
    assert_almost_equal(a.z, b.z, atol=atol)


def three_js_shadow(
    depth: Float32,
    breaks: List[Float32],
    shadows: List[Float32],
    fade: Bool,
) -> Float32:
    """Return three.js's `shadowValue` for a linear depth: what the one
    light is multiplied by."""
    var value = Float32(1)
    var last = len(breaks) - 1
    for index in range(len(breaks)):
        var x = Float32(0)
        if index > 0:
            x = breaks[index - 1]
        var y = breaks[index]
        if not fade:
            if depth >= x and depth <= y:
                value = shadows[index]
            continue
        var center = (x + y) / 2
        var closest = x if depth < center else y
        var margin = Float32(0.25) * closest * closest
        var csm_x = x - margin / 2
        var csm_y = y
        if index != last:
            csm_y = y + margin / 2
        if depth >= csm_x and depth <= csm_y:
            var distance = min(depth - csm_x, csm_y - depth)
            var ratio = Float32(1)
            if margin > 0:
                ratio = max(Float32(0), min(Float32(1), distance / margin))
            if index == 0 and not (depth > center):
                ratio = 1
            value -= (1 - shadows[index]) * ratio
    return value


def shared_shadow(
    depth: Float32,
    breaks: List[Float32],
    shadows: List[Float32],
    fade: Bool,
) -> Float32:
    """Return what the cascade lights of the port add up to at a linear
    depth: each light's share, with its share of its shadow."""
    var total = Float32(0)
    var last = len(breaks) - 1
    for index in range(len(breaks)):
        var start = Float32(0)
        if index > 0:
            start = breaks[index - 1]
        var reach = csm_node_reach(
            depth, start, breaks[index], index == last, fade
        )
        total += reach[0] * (1 - reach[1] * (1 - shadows[index]))
    return total


# --- the blend --------------------------------------------------------------


def test_a_cascade_blend_is_one_of_three() raises:
    assert_true(CSM_BLEND.is_valid())
    assert_true(SUN_BLEND.is_valid())
    assert_true(NODE_BLEND.is_valid())
    assert_false(CascadeBlend(3).is_valid())
    assert_false(CascadeBlend(-1).is_valid())


def test_a_shadow_nodes_cascade_needs_a_near_plane() raises:
    var band = ShadowCascade(
        0, 0.5, Length(99.0, METER), False, False, NODE_BLEND, near=0.01
    )
    band.validate()
    assert_equal(band.near, Float32(0.01))
    band.near = 0
    band.validate()
    band.near = -0.01
    with assert_raises(contains="near plane at zero"):
        band.validate()
    band.near = nan[DType.float32]()
    with assert_raises(contains="near plane at zero"):
        band.validate()
    # The other two blends do not read it.
    band.blend = CSM_BLEND
    band.validate()
    assert_equal(ShadowCascade.none().near, 0)
    band.blend = CascadeBlend(3)
    with assert_raises(contains="none of the three"):
        band.validate()


def test_without_fade_a_depth_takes_the_last_slice_that_holds_it() raises:
    # A slice owns its start and not its end.
    var inside = csm_node_reach(0.3, 0.2, 0.4, False, False)
    assert_equal(inside[0], 1)
    assert_equal(inside[1], 1)
    var start = csm_node_reach(0.2, 0.2, 0.4, False, False)
    assert_equal(start[0], 1)
    var before = csm_node_reach(0.1, 0.2, 0.4, False, False)
    assert_equal(before[0], 0)
    assert_equal(before[1], 0)
    var end = csm_node_reach(0.4, 0.2, 0.4, False, False)
    assert_equal(end[0], 0)
    # The last slice owns its end too.
    var rim = csm_node_reach(1, 0.4, 1, True, False)
    assert_equal(rim[0], 1)
    assert_equal(rim[1], 1)
    var held = csm_node_reach(0.5, 0.4, 1, True, False)
    assert_equal(held[0], 1)
    assert_equal(held[1], 1)
    # Past the last slice, and nearer than the near plane, no slice holds
    # the depth: three.js leaves the light unshadowed, and the last
    # cascade carries it.
    var beyond = csm_node_reach(1.5, 0.4, 1, True, False)
    assert_equal(beyond[0], 1)
    assert_equal(beyond[1], 0)
    var behind = csm_node_reach(-0.1, 0.4, 1, True, False)
    assert_equal(behind[0], 1)
    assert_equal(behind[1], 0)
    # A nearer slice holds the depths before the last one.
    var nearer = csm_node_reach(0.3, 0.4, 1, True, False)
    assert_equal(nearer[0], 0)
    assert_equal(nearer[1], 0)


def test_with_fade_a_slice_ramps_across_its_margin() raises:
    # A middle slice from 0.2 to 0.4. Its near margin is 0.01 and its
    # far margin 0.04.
    var middle = csm_node_reach(0.3, 0.2, 0.4, False, True)
    assert_almost_equal(middle[0], 1, atol=1e-6)
    assert_equal(middle[1], 1)
    var near_rim = csm_node_reach(0.2, 0.2, 0.4, False, True)
    assert_almost_equal(near_rim[0], 0.5, atol=1e-4)
    assert_equal(near_rim[1], 1)
    var far_rim = csm_node_reach(0.41, 0.2, 0.4, False, True)
    assert_almost_equal(far_rim[0], 0.25, atol=1e-4)
    # Outside its margins it takes no light, so its shadow's share is
    # not read.
    var outside = csm_node_reach(0.19, 0.2, 0.4, False, True)
    assert_equal(outside[0], 0)
    var past = csm_node_reach(0.43, 0.2, 0.4, False, True)
    assert_equal(past[0], 0)
    # The first slice starts at zero and does not fade at its near edge.
    var first = csm_node_reach(0.1, 0, 0.3, False, True)
    assert_equal(first[0], 1)
    assert_equal(first[1], 1)
    var origin = csm_node_reach(0, 0, 0.3, False, True)
    assert_equal(origin[0], 1)
    # It still fades at its far edge.
    var leaving = csm_node_reach(0.3, 0, 0.3, False, True)
    assert_almost_equal(leaving[0], 0.5, atol=1e-4)
    # At its middle three.js sets the ratio to one. A slice this deep
    # would ramp there by its far margin alone: 12 over 16.
    var deep = csm_node_reach(4, 0, 8, False, True)
    assert_equal(deep[0], 1)
    var past_middle = csm_node_reach(4.5, 0, 8, False, True)
    assert_almost_equal(past_middle[0], 11.5 / 16, atol=1e-5)
    # A slice that starts later ramps at its middle as anywhere else.
    var later = csm_node_reach(0.5, 0.5, 1, False, True)
    assert_almost_equal(later[0], 0.5, atol=1e-4)


def test_with_fade_the_last_slice_fades_its_shadow_not_its_light() raises:
    # The last slice from 0.4 to 1: its far margin is 0.25.
    var entering = csm_node_reach(0.4, 0.4, 1, True, True)
    assert_almost_equal(entering[0], 0.5, atol=1e-4)
    assert_almost_equal(entering[1], 1, atol=1e-4)
    var early = csm_node_reach(0.6, 0.4, 1, True, True)
    assert_equal(early[0], 1)
    assert_equal(early[1], 1)
    var fading = csm_node_reach(0.9, 0.4, 1, True, True)
    assert_equal(fading[0], 1)
    assert_almost_equal(fading[1], 0.4, atol=1e-4)
    # It does not reach past its end, where three.js's `CSMShader` does.
    var rim = csm_node_reach(1, 0.4, 1, True, True)
    assert_equal(rim[0], 1)
    assert_equal(rim[1], 0)
    var gone = csm_node_reach(2, 0.4, 1, True, True)
    assert_equal(gone[0], 1)
    assert_equal(gone[1], 0)
    # Before its near margin a nearer slice has the light.
    var nearer = csm_node_reach(0.2, 0.4, 1, True, True)
    assert_equal(nearer[0], 0)
    assert_equal(nearer[1], 0)
    # Nearer than the near plane no slice has it, and the last one lights.
    var close = csm_node_reach(-0.1, 0.4, 1, True, True)
    assert_equal(close[0], 1)
    assert_equal(close[1], 0)
    # A narrow last slice from 0.75 to 1 fades its shadow before its
    # light is whole. three.js takes 0.896 of the shadow at 0.874, so
    # the light is whole there and the shadow's share is 0.896.
    var narrow = csm_node_reach(0.874, 0.75, 1, True, True)
    assert_equal(narrow[0], 1)
    assert_almost_equal(narrow[1], 0.126 / 0.140625, atol=1e-4)
    # Where the slice before it still ramps out, the two shares multiply
    # to three.js's ratio.
    var ramping = csm_node_reach(0.7, 0.75, 1, True, True)
    assert_almost_equal(ramping[0], (0.7 - 0.6796875) / 0.140625, atol=1e-4)
    assert_almost_equal(ramping[1], 1, atol=1e-4)
    # One slice alone is the first and the last: nearer than the near
    # plane it lights with no shadow.
    var behind = csm_node_reach(-0.05, 0, 1, True, True)
    assert_equal(behind[0], 1)
    assert_equal(behind[1], 0)
    var alone = csm_node_reach(0.5, 0, 1, True, True)
    assert_equal(alone[0], 1)
    assert_equal(alone[1], 1)


def test_the_shares_add_up_to_the_shadow_three_js_reads() raises:
    # three.js's practical split of one meter to a hundred.
    var breaks = practical_split(3, 1, 100, 0.5)
    var shadows: List[Float32] = [0.2, 0.5, 0.8]
    for fade in [False, True]:
        for step in range(-100, 1300):
            var depth = Float32(step) / 1000
            assert_almost_equal(
                shared_shadow(depth, breaks, shadows, fade),
                three_js_shadow(depth, breaks, shadows, fade),
                atol=1e-5,
            )
    # At a break, and at the two ends.
    for depth in [Float32(0), breaks[0], breaks[1], Float32(1)]:
        for fade in [False, True]:
            assert_almost_equal(
                shared_shadow(depth, breaks, shadows, fade),
                three_js_shadow(depth, breaks, shadows, fade),
                atol=1e-5,
            )
    # One cascade and four even ones.
    var whole: List[Float32] = [1]
    var one: List[Float32] = [0.3]
    var even: List[Float32] = [0.25, 0.5, 0.75, 1]
    var four: List[Float32] = [0.1, 0.4, 0.6, 0.9]
    for fade in [False, True]:
        for step in range(-50, 1100):
            var depth = Float32(step) / 1000
            assert_almost_equal(
                shared_shadow(depth, whole, one, fade),
                three_js_shadow(depth, whole, one, fade),
                atol=1e-5,
            )
            assert_almost_equal(
                shared_shadow(depth, even, four, fade),
                three_js_shadow(depth, even, four, fade),
                atol=1e-5,
            )


def test_lighting_takes_the_near_plane_from_a_shadow_nodes_depth() raises:
    var scene = Scene()
    var high = Object3D()
    high.set_position(0, 1, 0)
    var node = scene.add(high^)
    # A camera from one meter to eleven: a span of ten.
    var near = directional_light(WHITE, node)
    near.cascade = ShadowCascade(
        0, 0.5, Length(10.0, METER), False, False, NODE_BLEND, near=0.1
    )
    var far = directional_light(WHITE, node)
    far.cascade = ShadowCascade(
        0.5, 1, Length(10.0, METER), True, False, NODE_BLEND, near=0.1
    )
    scene.add_light(near)
    scene.add_light(far)
    scene.update()
    var lighting = Lighting(scene, back=Vector3(0, 0, 1))
    # Five and a half meters in front is 0.45 past the near plane: the
    # near slice. `CSM_BLEND` would read 0.55 and give the far one.
    var at = Vector3(0, 0, -5.5)
    assert_equal(lighting.direction_through(0, at, UP, True).x, 1)
    assert_equal(lighting.direction_through(1, at, UP, True).x, 0)
    var further = Vector3(0, 0, -6.5)
    assert_equal(lighting.direction_through(0, further, UP, True).x, 0)
    assert_equal(lighting.direction_through(1, further, UP, True).x, 1)
    # Nearer than the near plane the last cascade still lights.
    var close = Vector3(0, 0, -0.5)
    assert_equal(lighting.direction_through(0, close, UP, True).x, 0)
    assert_equal(lighting.direction_through(1, close, UP, True).x, 1)
    # The sum is one light at every depth.
    var single = Scene()
    var lone = single.add(Object3D())
    single.node(lone).set_position(0, 1, 0)
    single.add_light(directional_light(WHITE, lone))
    single.update()
    var one = Lighting(single).intensity_at(UP, at)
    assert_equal(lighting.intensity_at(UP, at).r, one.r)
    assert_equal(lighting.intensity_at(UP, further).r, one.r)
    assert_equal(lighting.intensity_at(UP, close).r, one.r)


# --- the functions the node shares with a CSM -------------------------------


def test_custom_breaks_are_one_per_slice_and_rise() raises:
    require_custom_breaks(List[Float32](), 0)
    var fine: List[Float32] = [0.25, 1]
    require_custom_breaks(fine, 2)
    with assert_raises(contains="one break per cascade"):
        require_custom_breaks(fine, 3)
    var falling: List[Float32] = [0.5, 0.25]
    with assert_raises(contains="rise from zero to one"):
        require_custom_breaks(falling, 2)
    var past: List[Float32] = [0.5, 1.5]
    with assert_raises(contains="rise from zero to one"):
        require_custom_breaks(past, 2)
    var holes: List[Float32] = [nan[DType.float32](), 1]
    with assert_raises(contains="rise from zero to one"):
        require_custom_breaks(holes, 2)
    assert_equal(csm_breaks(CUSTOM_SPLIT, 2, 1, 100, fine)[0], 0.25)
    assert_equal(len(csm_breaks(UNIFORM_SPLIT, 4, 1, 100, fine)), 4)
    with assert_raises(contains="none of the four"):
        _ = csm_breaks(CsmMode(9), 2, 1, 100, fine)


def test_a_cascade_mapping_must_be_whole() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    var target = scene.add(Object3D())
    scene.add_light(directional_light(WHITE, node, 1, target))
    var lights: List[Int] = [0]
    var nodes: List[NodeId] = [node]
    var targets: List[NodeId] = [target]
    require_cascade_lights(scene, 1, lights, nodes, targets)
    with assert_raises(contains="one complete mapping"):
        require_cascade_lights(scene, 0, lights, nodes, targets)
    with assert_raises(contains="one complete mapping"):
        require_cascade_lights(scene, 2, lights, nodes, targets)
    var missing: List[Int] = [3]
    with assert_raises(contains="not in this scene"):
        require_cascade_lights(scene, 1, missing, nodes, targets)
    var swapped: List[NodeId] = [target]
    with assert_raises(contains="not in this scene"):
        require_cascade_lights(scene, 1, lights, swapped, targets)


# --- the lights a shadow node adds ------------------------------------------


def test_a_shadow_node_adds_one_casting_light_per_cascade() raises:
    var scene = Scene()
    var camera = eye()
    var light = sun(scene, Vector3(-10, 20, -10))
    light.color = Color(255, 128, 0)
    var csm = CSMShadowNode(scene, camera, light)
    assert_equal(csm.cascades, 3)
    assert_equal(csm.mode, PRACTICAL_SPLIT)
    assert_false(csm.fade)
    # The scene holds the cascades and not the light itself.
    assert_equal(len(scene.lights), 3)
    assert_equal(len(csm.breaks), 3)
    for index in range(3):
        ref lamp = scene.lights[csm.lights[index]]
        assert_equal(lamp.kind, DIRECTIONAL)
        assert_true(lamp.cast_shadow)
        assert_equal(lamp.intensity, 2)
        assert_equal(lamp.color.g, 128)
        assert_equal(lamp.node, csm.nodes[index])
        assert_equal(lamp.target, csm.targets[index])
        assert_equal(lamp.shadow.map_size, 16)
        # three.js multiplies the bias by the cascade's number.
        assert_almost_equal(
            lamp.shadow.bias, Float32(0.001) * Float32(index + 1), atol=1e-9
        )
        assert_equal(lamp.cascade.blend, NODE_BLEND)
        assert_false(lamp.cascade.fade)
        assert_equal(lamp.cascade.last, index == 2)
        # three.js's `shadowFar - cameraNear`, and the near plane over it.
        assert_almost_equal(lamp.cascade.span.to(METER), 99, atol=1e-4)
        assert_almost_equal(lamp.cascade.near, Float32(1) / 99, atol=1e-7)
        assert_equal(lamp.cascade.end, csm.breaks[index])
        lamp.validate()
        # The cascade lights hang beside the light's node: on the scene.
        assert_equal(scene.get(lamp.node).parent, NO_PARENT)
    assert_equal(scene.lights[csm.lights[0]].cascade.start, 0)
    assert_equal(scene.lights[csm.lights[1]].cascade.start, csm.breaks[0])
    assert_equal(scene.lights[csm.lights[2]].cascade.start, csm.breaks[1])
    # The breaks are three.js's practical split.
    var expected = practical_split(3, 1, 100, 0.5)
    assert_equal(csm.breaks[0], expected[0])
    assert_equal(csm.breaks[1], expected[1])
    # The light the node keeps is the caller's, unchanged.
    assert_almost_equal(csm.light.shadow.bias, 0.001, atol=1e-9)
    assert_false(csm.light.cascade.is_cascade())


def test_the_cascade_lights_hang_from_the_lights_parent() raises:
    var scene = Scene()
    var camera = eye()
    var rig = scene.add(Object3D())
    var light = sun(scene, Vector3(0, 30, 10))
    scene.add(light.node, parent=rig)
    var csm = CSMShadowNode(scene, camera, light, cascades=2)
    for index in range(2):
        assert_equal(scene.get(csm.nodes[index]).parent, rig)
        assert_equal(scene.get(csm.targets[index]).parent, rig)


def test_a_shadow_node_places_its_lights_as_a_csm_places_them() raises:
    # The same sun as a `CSM` of the same direction: three.js's two
    # classes share the arithmetic that places a cascade.
    var scene = Scene()
    var camera = eye()
    var at = Vector3(-30, 60, -30)
    var light = sun(scene, at)
    var csm = CSMShadowNode(
        scene,
        camera,
        light,
        max_far=Length(50.0, METER),
        mode=UNIFORM_SPLIT,
        light_margin=Length(20.0, METER),
    )
    csm.update(scene, camera)
    var other = Scene()
    var twin = CSM(
        other,
        camera,
        max_far=Length(50.0, METER),
        mode=UNIFORM_SPLIT,
        shadow_map_size=16,
        light_direction=Vector3(0, 0, 0) - at,
        light_margin=Length(20.0, METER),
    )
    twin.update(other, camera)
    var way = csm.direction(scene)
    assert_close(way, twin.light_direction, 1e-6)
    for index in range(3):
        ref lamp = scene.lights[csm.lights[index]]
        ref mate = other.lights[twin.lights[index]]
        assert_almost_equal(
            lamp.shadow.right.to(METER), mate.shadow.right.to(METER), atol=1e-4
        )
        assert_almost_equal(
            lamp.shadow.bottom.to(METER),
            mate.shadow.bottom.to(METER),
            atol=1e-4,
        )
        var stood = scene.get(csm.nodes[index]).position
        assert_close(stood, other.get(twin.nodes[index]).position, 1e-3)
        # Each target is one step along the direction from its light.
        assert_close(scene.get(csm.targets[index]).position, stood + way, 1e-4)
    # The first slice ends at a third of the fifty meters.
    assert_almost_equal(csm.breaks[0], (1 + Float32(49) / 3) / 50, atol=1e-6)
    assert_almost_equal(
        scene.lights[csm.lights[0]].cascade.span.to(METER), 49, atol=1e-4
    )


def test_a_light_shines_toward_its_target() raises:
    var scene = Scene()
    var camera = eye()
    var light = sun(scene, Vector3(4, 10, 0))
    var aim = scene.add(Object3D())
    scene.node(aim).set_position(4, 0, 10)
    light.target = aim
    var csm = CSMShadowNode(scene, camera, light, cascades=1)
    var way = csm.direction(scene)
    assert_close(way, Vector3(0, -1, 1) * (1 / sqrt(Float32(2))), 1e-6)
    csm.update(scene, camera)
    var stood = scene.get(csm.nodes[0]).position
    assert_close(scene.get(csm.targets[0]).position, stood + way, 1e-4)
    # A light that stands on its target shines no way at all.
    scene.node(aim).set_position(4, 10, 0)
    with assert_raises(contains="stand off its target"):
        _ = csm.direction(scene)
    with assert_raises(contains="stand off its target"):
        csm.update(scene, camera)
    scene.node(aim).set_position(inf[DType.float32](), 0, 0)
    with assert_raises(contains="stand off its target"):
        _ = csm.direction(scene)


def test_update_carries_the_lights_color_intensity_and_layers() raises:
    var scene = Scene()
    var camera = eye()
    var light = sun(scene, Vector3(10, 20, 10))
    var csm = CSMShadowNode(scene, camera, light, cascades=2)
    csm.light.intensity = 5
    csm.light.color = Color(10, 20, 30)
    var layers = Layers()
    layers.set(3)
    csm.light.layers = layers
    csm.update(scene, camera)
    for index in range(2):
        ref lamp = scene.lights[csm.lights[index]]
        assert_equal(lamp.intensity, 5)
        assert_equal(lamp.color.b, 30)
        assert_true(lamp.layers.test(layers))
        assert_false(lamp.layers.test(Layers()))
    # Moving the light turns the cascades with it at the next update.
    var before = scene.get(csm.nodes[0]).position
    scene.node(csm.light.node).set_position(-10, 20, 10)
    csm.update(scene, camera)
    assert_true(scene.get(csm.nodes[0]).position.x != before.x)


def test_fade_and_the_split_take_effect_at_update_frustums() raises:
    var scene = Scene()
    var camera = eye()
    var light = sun(scene, Vector3(10, 20, 10))
    var csm = CSMShadowNode(
        scene, camera, light, cascades=1, mode=UNIFORM_SPLIT
    )
    ref shadow = scene.lights[csm.lights[0]].shadow
    var width = Float32(200) * sqrt(Float32(2))
    assert_almost_equal(shadow.right.to(METER), width / 2, atol=0.1)
    assert_almost_equal(shadow.left.to(METER), -width / 2, atol=0.1)
    assert_almost_equal(shadow.top.to(METER), width / 2, atol=0.1)
    # Fade widens the slice by its margin and marks the cascade.
    csm.fade = True
    csm.update_frustums(scene, camera)
    assert_true(scene.lights[csm.lights[0]].shadow.right.to(METER) > width / 2)
    assert_true(scene.lights[csm.lights[0]].cascade.fade)
    # A custom split is the caller's breaks.
    var two = Scene()
    var again = sun(two, Vector3(10, 20, 10))
    var custom: List[Float32] = [0.1, 1]
    var cut = CSMShadowNode(
        two,
        camera,
        again,
        cascades=2,
        mode=CUSTOM_SPLIT,
        custom_breaks=custom.copy(),
    )
    assert_equal(cut.breaks[0], Float32(0.1))
    assert_equal(two.lights[cut.lights[1]].cascade.start, Float32(0.1))
    cut.custom_breaks[0] = 2
    with assert_raises(contains="rise from zero to one"):
        cut.update_frustums(two, camera)
    cut.mode = CsmMode(9)
    with assert_raises(contains="none of the four"):
        cut.update_frustums(two, camera)


def test_dispose_takes_the_cascades_off_the_scene() raises:
    var scene = Scene()
    var camera = eye()
    var light = sun(scene, Vector3(10, 20, 10))
    var csm = CSMShadowNode(scene, camera, light, cascades=2)
    assert_true(scene.in_scene(csm.nodes[1]))
    csm.dispose(scene)
    for index in range(2):
        assert_false(scene.in_scene(csm.nodes[index]))
        assert_false(scene.in_scene(csm.targets[index]))
    # The light's own node stays, for the caller to add the light to.
    assert_true(scene.in_scene(csm.light.node))


# --- what a shadow node refuses ---------------------------------------------


def test_a_shadow_node_refuses_a_light_it_cannot_shadow() raises:
    var camera = eye()
    var scene = Scene()
    var light = sun(scene, Vector3(10, 20, 10))
    with assert_raises(contains="at least one cascade"):
        _ = CSMShadowNode(scene, camera, light, cascades=0)
    with assert_raises(contains="larger than this port slices"):
        _ = CSMShadowNode(scene, camera, light, cascades=16777217)
    with assert_raises(contains="none of the four"):
        _ = CSMShadowNode(scene, camera, light, mode=CsmMode(7))
    var bulb = point_light(WHITE, light.node)
    with assert_raises(contains="shadows a directional light"):
        _ = CSMShadowNode(scene, camera, bulb)
    var plain = light
    plain.cast_shadow = False
    with assert_raises(contains="must cast a shadow"):
        _ = CSMShadowNode(scene, camera, plain)
    var sliced = light
    sliced.cascade = ShadowCascade(0, 1, Length(10.0, METER), True, False)
    with assert_raises(contains="a cascade already"):
        _ = CSMShadowNode(scene, camera, sliced)
    var dark = light
    dark.intensity = -1
    with assert_raises():
        _ = CSMShadowNode(scene, camera, dark)
    var lost = light
    lost.node = NodeId(99)
    with assert_raises():
        _ = CSMShadowNode(scene, camera, lost)
    var aimless = light
    aimless.target = NodeId(99)
    with assert_raises():
        _ = CSMShadowNode(scene, camera, aimless)
    for wrong in [Float32(0), nan[DType.float32](), Float32(-5)]:
        with assert_raises(contains="positive length"):
            _ = CSMShadowNode(
                scene, camera, light, max_far=Length(wrong, METER)
            )
    with assert_raises(contains="margin must be finite"):
        _ = CSMShadowNode(
            scene,
            camera,
            light,
            light_margin=Length(inf[DType.float32](), METER),
        )
    var short: List[Float32] = [1]
    with assert_raises(contains="one break per cascade"):
        _ = CSMShadowNode(
            scene, camera, light, mode=CUSTOM_SPLIT, custom_breaks=short.copy()
        )
    # A refused node adds nothing to the scene.
    assert_equal(len(scene.lights), 0)


def test_update_refuses_a_node_that_is_no_longer_whole() raises:
    var camera = eye()
    var scene = Scene()
    var light = sun(scene, Vector3(10, 20, 10))
    var csm = CSMShadowNode(scene, camera, light, cascades=2)
    scene.lights[csm.lights[1]].shadow.map_size = 0
    with assert_raises(contains="map size must be positive"):
        csm.update(scene, camera)
    scene.lights[csm.lights[1]].shadow.map_size = 16
    var kept = csm.frustums[1].near.pop()
    with assert_raises(contains="four corners per plane"):
        csm.update(scene, camera)
    csm.frustums[1].near.append(kept)
    var far = csm.frustums[0].far.pop()
    with assert_raises(contains="four corners per plane"):
        csm.update(scene, camera)
    csm.frustums[0].far.append(far)
    csm.update(scene, camera)
    var gone = csm.frustums.pop()
    with assert_raises(contains="one frustum per cascade"):
        csm.update(scene, camera)
    csm.frustums.append(gone^)
    # The lights the node added must still be the scene's.
    scene.lights[csm.lights[0]].target = NO_PARENT
    with assert_raises(contains="not in this scene"):
        csm.update(scene, camera)
    with assert_raises(contains="not in this scene"):
        csm.update_frustums(scene, camera)
    with assert_raises(contains="not in this scene"):
        csm.dispose(scene)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
