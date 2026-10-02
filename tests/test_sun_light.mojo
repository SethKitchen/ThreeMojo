# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `lights.sun_light`, three.js r186's `SunLight` and
`SunLightShadow`, and the `SUN_BLEND` cascades of `lights.shadow`, its
`SunShadowNode`.

The expected numbers are `SunLightShadow.updateMatrices` worked by hand
for a camera at the origin looking down -z, ninety degrees wide, from one
meter to three, and a sun at (0, 0, 1), whose light travels down -z so
its frame is the world's:

- The split is `(2 + sqrt(3)) / 2`, 1.8660254: halfway between the even
  split, two, and the logarithmic one, `sqrt(3)`.
- The first cascade fades from 1.7794229, a tenth of its depth before it
  ends. The second begins there, fades from 2.8866025 and ends at three.
- The map is 1024 texels less an inset of two on each side: 1020. The
  radii, padded by `1 / (1 - 1 / 1020)`, are 2.6768722 and 4.2905162.
- The caster ceiling is the highest corner, -1, plus the depth, three:
  two. Each camera stands half a meter above it, at z = 2.5. Their far
  planes are 4.8660254 and six.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import DIRECTIONAL, ambient_light, directional_light
from lights.lighting import Lighting
from lights.shadow import (
    CSM_BLEND,
    CascadeBlend,
    SUN_BLEND,
    ShadowCascade,
    sun_reach,
)
from lights.sun_light import (
    SUN_CASCADES,
    SUN_MAP_SIZE,
    SunLight,
    fit_sun,
    sun_light_shadow,
    sun_splits,
)
from materials.material import Material
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.math import inf, nan, sqrt
from std.memory import bitcast
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime SPLIT = Float32(1.8660254)
comptime FIRST_FADE = Float32(1.7794229)
comptime SECOND_FADE = Float32(2.8866025)


def assert_at(point: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point's three coordinates, to within a ten-thousandth."""
    assert_almost_equal(point.x, x, atol=1e-4)
    assert_almost_equal(point.y, y, atol=1e-4)
    assert_almost_equal(point.z, z, atol=1e-4)


def a_short_camera() raises -> PerspectiveCamera:
    """Return a camera at the origin looking down -z, ninety degrees
    wide, from one meter to three."""
    return PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(1.0, METER), Length(3.0, METER)
    )


# --- the blend --------------------------------------------------------------


def test_a_cascade_blend_is_one_of_two() raises:
    assert_true(CSM_BLEND.is_valid())
    assert_true(SUN_BLEND.is_valid())
    assert_false(CascadeBlend(2).is_valid())
    assert_equal(ShadowCascade.none().blend, CSM_BLEND)


def test_a_suns_cascades_share_the_light_as_three_js_mixes_it() raises:
    # Before the first fade, the first cascade has all of the light and
    # its shadow; the second none.
    var first = sun_reach(1.0, 0, 0, FIRST_FADE, SPLIT, False)
    assert_equal(first[0], 1)
    assert_equal(first[1], 1)
    var second = sun_reach(1.0, FIRST_FADE, SPLIT, SECOND_FADE, 3, True)
    assert_equal(second[0], 0)
    assert_equal(second[1], 0)
    # In the fade, the light is split and every share still casts:
    # three.js's `mix( first, second, t )`.
    var t = smoothstep(FIRST_FADE, SPLIT, 1.82)
    first = sun_reach(1.82, 0, 0, FIRST_FADE, SPLIT, False)
    second = sun_reach(1.82, FIRST_FADE, SPLIT, SECOND_FADE, 3, True)
    assert_almost_equal(first[0], 1 - t, atol=1e-6)
    assert_almost_equal(second[0], t, atol=1e-6)
    assert_almost_equal(first[0] + second[0], 1, atol=1e-6)
    assert_equal(second[1], 1)
    # Past the first cascade it lights nothing.
    first = sun_reach(2.5, 0, 0, FIRST_FADE, SPLIT, False)
    assert_equal(first[0], 0)
    # The last cascade fades its shadow, not its light, and past its end
    # lights with no shadow.
    var u = smoothstep(SECOND_FADE, 3, 2.95)
    second = sun_reach(2.95, FIRST_FADE, SPLIT, SECOND_FADE, 3, True)
    assert_equal(second[0], 1)
    assert_almost_equal(second[1], 1 - u, atol=1e-6)
    second = sun_reach(4, FIRST_FADE, SPLIT, SECOND_FADE, 3, True)
    assert_equal(second[0], 1)
    assert_equal(second[1], 0)


def test_a_suns_cascade_is_refused_when_it_cannot_blend() raises:
    var band = ShadowCascade(
        1, 3, Length(1.0, METER), True, False, SUN_BLEND, 2.5, 1.5
    )
    band.validate()
    band.blend = CascadeBlend(7)
    with assert_raises(contains="none of the two"):
        band.validate()
    band.blend = SUN_BLEND
    band.fade_start = 4
    with assert_raises(contains="fade before it ends"):
        band.validate()
    band.fade_start = nan[DType.float32]()
    with assert_raises(contains="fade before it ends"):
        band.validate()
    band.fade_start = 2.5
    band.ramp_end = 0.5
    with assert_raises(contains="fade before it ends"):
        band.validate()
    band.ramp_end = inf[DType.float32]()
    with assert_raises(contains="fade before it ends"):
        band.validate()
    # A CSM cascade does not read the sun's two numbers.
    band.blend = CSM_BLEND
    band.validate()


# --- the fit ----------------------------------------------------------------


def test_the_split_is_three_js_practical_split() raises:
    var splits = sun_splits(1, 3)
    assert_equal(len(splits), SUN_CASCADES + 1)
    assert_equal(splits[0], 1)
    assert_almost_equal(splits[1], SPLIT, atol=1e-5)
    assert_equal(splits[2], 3)
    # A near plane at zero has no logarithm: the split is even.
    assert_almost_equal(sun_splits(0, 4)[1], 2, atol=1e-6)


def test_the_shadow_has_three_js_defaults() raises:
    var shadow = sun_light_shadow()
    assert_equal(shadow.map_size, SUN_MAP_SIZE)
    assert_equal(shadow.near.to(METER), 0.5)
    assert_equal(shadow.far.to(METER), 500)
    assert_equal(shadow.radius, 1)


def test_the_cascades_are_fit_as_three_js_fits_them() raises:
    var scene = Scene()
    var fit = fit_sun(
        scene, a_short_camera(), Vector3(0, 0, 1), sun_light_shadow()
    )
    assert_at(fit.direction, 0, 0, -1)
    assert_equal(fit.resolution, 1020)
    assert_equal(len(fit.cascades), 2)
    ref near = fit.cascades[0]
    assert_equal(near.start, 0)
    assert_almost_equal(near.end, SPLIT, atol=1e-5)
    assert_almost_equal(near.fade_start, FIRST_FADE, atol=1e-5)
    assert_equal(near.ramp_end, 0)
    assert_almost_equal(near.radius, 2.6768722, atol=1e-4)
    assert_at(near.position, 0, 0, 2.5)
    assert_equal(near.near, 0.5)
    assert_almost_equal(near.far, 4.8660254, atol=1e-4)
    ref far = fit.cascades[1]
    assert_almost_equal(far.start, FIRST_FADE, atol=1e-5)
    assert_almost_equal(far.end, 3, atol=1e-5)
    assert_almost_equal(far.fade_start, SECOND_FADE, atol=1e-5)
    assert_almost_equal(far.ramp_end, SPLIT, atol=1e-5)
    assert_almost_equal(far.radius, 4.2905162, atol=1e-4)
    assert_at(far.position, 0, 0, 2.5)
    assert_almost_equal(far.far, 6, atol=1e-4)
    assert_true(not near.band(False).last)
    assert_true(far.band(True).last)
    assert_equal(far.band(True).blend, SUN_BLEND)


def test_the_shadow_far_plane_cuts_the_view() raises:
    # A shadow that reaches two meters cuts the depth there.
    var scene = Scene()
    var shadow = sun_light_shadow()
    shadow.far = Length(2.0, METER)
    var fit = fit_sun(scene, a_short_camera(), Vector3(0, 0, 1), shadow)
    assert_almost_equal(fit.cascades[1].end, 2, atol=1e-5)


def test_a_sun_overhead_turns_its_frame_up_to_z() raises:
    # Within eight degrees of vertical, the light's frame takes +z as up.
    # The caster ceiling is the highest corner, y = 3, plus the depth.
    var scene = Scene()
    var fit = fit_sun(
        scene, a_short_camera(), Vector3(0, 1, 0), sun_light_shadow()
    )
    assert_at(fit.direction, 0, -1, 0)
    for index in range(SUN_CASCADES):
        assert_almost_equal(fit.cascades[index].position.y, 6.5, atol=1e-4)
    assert_almost_equal(fit.cascades[0].far, 8.8660254, atol=1e-4)


def test_an_orthographic_view_keeps_its_far_corners_square() raises:
    # From half a meter to four, the split is (2.25 + sqrt(2)) / 2,
    # 1.8321068. The first slice is 4 by 2 by 1.3321068, and its sphere
    # the half diagonal, 2.3331618, padded to 2.3354478.
    var scene = Scene()
    var camera = OrthographicCamera(
        Length(-2.0, METER),
        Length(2.0, METER),
        Length(1.0, METER),
        Length(-1.0, METER),
        Length(0.5, METER),
        Length(4.0, METER),
    )
    var fit = fit_sun(scene, camera, Vector3(0, 0, 1), sun_light_shadow())
    assert_almost_equal(fit.cascades[0].end, 1.8321068, atol=1e-5)
    assert_almost_equal(fit.cascades[0].radius, 2.3354478, atol=1e-4)


def test_a_tiny_map_is_not_padded_or_snapped() raises:
    # One texel a side: three.js's inset leaves half a texel, so the
    # radius is not padded and the middle not snapped. The map keeps one
    # texel.
    var scene = Scene()
    var shadow = sun_light_shadow()
    shadow.map_size = 1
    var fit = fit_sun(scene, a_short_camera(), Vector3(0.3, 0.2, 1), shadow)
    assert_equal(fit.resolution, 1)
    assert_almost_equal(fit.cascades[0].radius, 2.6742479, atol=1e-4)


def test_a_sun_at_the_origin_has_no_direction() raises:
    var scene = Scene()
    with assert_raises(contains="no direction"):
        _ = fit_sun(
            scene, a_short_camera(), Vector3(0, 0, 0), sun_light_shadow()
        )
    # A sun at no finite place has no direction either.
    with assert_raises(contains="no direction"):
        _ = fit_sun(
            scene,
            a_short_camera(),
            Vector3(0, 0, nan[DType.float32]()),
            sun_light_shadow(),
        )


# --- the light --------------------------------------------------------------


def test_a_sun_is_two_directional_cascades_over_one_node() raises:
    var scene = Scene()
    var sun = SunLight(scene, Color(255, 240, 220), 2.0)
    assert_equal(len(scene.lights), SUN_CASCADES)
    assert_false(sun.cast_shadow)
    assert_equal(sun.shadow.map_size, SUN_MAP_SIZE)
    # three.js's `Object3D.DEFAULT_UP`: the sun is straight up.
    assert_at(scene.world_position(sun.node), 0, 1, 0)
    for index in range(SUN_CASCADES):
        ref light = scene.lights[sun.lights[index]]
        assert_equal(light.kind, DIRECTIONAL)
        assert_equal(light.intensity, 2)
        assert_equal(light.cascade.blend, SUN_BLEND)
    # Before the first fit the pair lights once, with no shadow.
    var lighting = Lighting(scene, eye=Vector3(0, 0, 5))
    var up = lighting.intensity_at(Vector3(0, 1, 0), Vector3(0, 0, 0))
    var single = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 1, 0)
    single.add_light(
        directional_light(Color(255, 240, 220), single.add(lamp^), 2.0)
    )
    single.update()
    var one = Lighting(single).intensity_at(Vector3(0, 1, 0), Vector3(0, 0, 0))
    assert_almost_equal(up.r, one.r, atol=1e-6)
    with assert_raises():
        _ = SunLight(scene, intensity=-1)


def test_update_places_each_cascade() raises:
    var scene = Scene()
    var sun = SunLight(scene)
    sun.cast_shadow = True
    sun.shadow.bias = -0.001
    scene.node(sun.node).set_position(0, 0, 1)
    scene.update()
    sun.update(scene, a_short_camera())
    for index in range(SUN_CASCADES):
        ref light = scene.lights[sun.lights[index]]
        assert_true(light.cast_shadow)
        assert_equal(light.shadow.bias, -0.001)
        assert_equal(light.shadow.map_size, 1020)
        assert_equal(light.shadow.near.to(METER), 0.5)
        assert_at(scene.world_position(sun.nodes[index]), 0, 0, 2.5)
        assert_at(scene.world_position(sun.targets[index]), 0, 0, 1.5)
    ref near = scene.lights[sun.lights[0]]
    assert_almost_equal(near.shadow.right.to(METER), 2.6768722, atol=1e-4)
    assert_almost_equal(near.shadow.far.to(METER), 4.8660254, atol=1e-4)
    assert_false(near.cascade.last)
    assert_true(scene.lights[sun.lights[1]].cascade.last)


def test_update_refuses_a_scene_without_the_sun() raises:
    var scene = Scene()
    var sun = SunLight(scene)
    var camera = a_short_camera()
    var other = Scene()
    with assert_raises(contains="not in this scene"):
        sun.update(other, camera)
    var swapped = Scene()
    swapped.add_light(ambient_light(Color(255, 255, 255)))
    swapped.add_light(ambient_light(Color(255, 255, 255)))
    with assert_raises(contains="not in this scene"):
        sun.update(swapped, camera)
    sun.shadow.map_size = 0
    with assert_raises():
        sun.update(scene, camera)


def test_the_sun_casts_a_shadow_where_the_camera_looks() raises:
    # A box on a floor, seen from above, shadows the floor on the side
    # away from the sun; the floor on the sun's side is lit.
    var assets = Assets()
    var scene = Scene()
    var ground = Object3D()
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var floor = assets.geometries.add(
        plane(Length(8.0, METER), Length(8.0, METER), 2, 2)
    )
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    scene.add_mesh(Mesh(floor, paint, scene.add(ground^), receive_shadow=True))
    var lift = Object3D()
    lift.set_position(0, 0.5, 0)
    scene.add_mesh(Mesh(block, paint, scene.add(lift^), cast_shadow=True))
    var sun = SunLight(scene, intensity=3.0)
    sun.cast_shadow = True
    sun.shadow.map_size = 256
    sun.shadow.bias = -0.0005
    scene.node(sun.node).set_position(-1, 1, 0)
    scene.update()
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.0, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 6, 0.001), Vector3(0, 0, 0))
    sun.update(scene, camera)
    var image = Renderer(32, 32).render(scene, assets, camera)
    # The light travels toward +x, so the shadow falls on the +x side.
    var shaded = image.get_pixel(21, 16).r
    var lit = image.get_pixel(9, 16).r
    assert_true(lit > shaded + 30, "the sun cast no shadow")


def test_nonfinite_constructor_intensity_keeps_the_scene_empty() raises:
    var bad: List[Float32] = [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]
    for intensity in bad:
        var scene = Scene()
        with assert_raises(contains="intensity must be finite"):
            _ = SunLight(scene, intensity=intensity)
        assert_equal(scene.count(), 0)
        assert_equal(len(scene.lights), 0)


def test_overflowing_cascade_positions_do_not_change_the_scene() raises:
    var scene = Scene()
    var sun = SunLight(scene)
    var camera = a_short_camera()
    sun.update(scene, camera)
    var first = scene.lights[sun.lights[0]]
    var second = scene.lights[sun.lights[1]]
    var before = scene.world_position(sun.nodes[0])
    # This finite view placement overflows the Float32 sum of eight
    # corners while fitting. Non-shadow-casting lights still need finite
    # positions, and a failed fit must not partially update the scene.
    camera.place(Vector3(1e38, 0, 5), Vector3(1e38, 0, 0))
    with assert_raises(contains="cascade position must be finite"):
        sun.update(scene, camera)
    assert_equal(
        scene.lights[sun.lights[0]].shadow.right.value, first.shadow.right.value
    )
    assert_equal(
        scene.lights[sun.lights[1]].shadow.right.value,
        second.shadow.right.value,
    )
    assert_at(scene.world_position(sun.nodes[0]), before.x, before.y, before.z)


def test_a_sun_refuses_changed_node_and_target_mappings() raises:
    var scene = Scene()
    var sun = SunLight(scene)
    var camera = a_short_camera()
    var original_node = scene.lights[sun.lights[0]].node
    scene.lights[sun.lights[0]].node = sun.targets[0]
    with assert_raises(contains="not in this scene"):
        sun.update(scene, camera)
    scene.lights[sun.lights[0]].node = original_node
    scene.lights[sun.lights[0]].target = sun.nodes[0]
    with assert_raises(contains="not in this scene"):
        sun.update(scene, camera)


def test_a_unit_direction_cannot_overflow_a_finite_cascade_position() raises:
    from lights.sun_light import _finite_point

    var largest = bitcast[DType.float32](UInt32(0x7F7FFFFF))
    var edge = Vector3(largest, -largest, largest)
    var direction = Vector3(1, -1, 1)
    direction.normalize()
    assert_true(_finite_point(edge + direction))
    assert_at(edge + direction, edge.x, edge.y, edge.z)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
