# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's pond: its basin, its ripples, its shore, and what its
water mirrors."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.fog import FogView, exp2_fog
from core.scene import Scene
from extensions.vegetation.field import FieldParameters, GrassField
from extensions.vegetation.blade import SEED_HEAD
from extensions.vegetation.ground import POND_DROP, Ground, Lot, Pond
from extensions.village.pond import MIRROR_MOST, PondLook, water_mask
from extensions.village.shore import ShoreParameters, stand_shore
from extensions.village.surfaces import house_looks
from extensions.village.village import pond_basin
from extensions.water.frame import WaterScene
from extensions.water.optics import (
    BASIN_MUD_DEPTH,
    Basin,
    basin_depth,
    basin_mud,
    floor_depth,
)
from extensions.water.resolution import SpectrumResolution
from extensions.water.ripple import (
    RippleDrop,
    RippleField,
    step_ripple,
    step_ripple_drops,
)
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    METER,
    PER_METER,
    SECOND,
    Angle,
    Duration,
    InverseLength,
    Length,
)


def _m(value: Float32) -> Length:
    return Length(value, METER)


def _pond_ground() raises -> Ground:
    """Return level ground with a pond 6 meters across at (0, 0)."""
    return Ground(
        seed=3,
        hill_height=_m(0),
        pond=Pond(_m(0), _m(0), _m(3), _m(1)),
    )


def test_a_basin_is_checked_and_none_keeps_the_shelving_bed() raises:
    var none = Basin()
    assert_equal(none.radius, 0)
    assert_equal(basin_depth(none, 1, -2), floor_depth(1, -2))
    assert_equal(basin_mud(none, 0), 0)
    with assert_raises(contains="kilometer across"):
        _ = Basin(_m(0), _m(0), _m(2000), _m(1), 0.3, _m(0.05))
    with assert_raises(contains="deep"):
        _ = Basin(_m(0), _m(0), _m(3), _m(60), 0.3, _m(0.05))
    with assert_raises(contains="level floor"):
        _ = Basin(_m(0), _m(0), _m(3), _m(1), 1, _m(0.05))
    with assert_raises(contains="rim"):
        _ = Basin(_m(0), _m(0), _m(3), _m(1), 0.3, _m(20))
    with assert_raises(contains="10 kilometers"):
        _ = Basin(_m(2.0e4), _m(0), _m(3), _m(1), 0.3, _m(0.05))


def test_a_basin_is_deep_in_the_middle_and_shallow_at_its_shore() raises:
    var basin = Basin(_m(2), _m(1), _m(4), _m(1.2), 0.3, _m(0.05))
    # Level in the middle, rising to the rim above the water.
    assert_almost_equal(basin_depth(basin, 2, 1), 1.2, atol=1e-6)
    assert_almost_equal(basin_depth(basin, 3, 1), 1.2, atol=1e-6)
    assert_almost_equal(basin_depth(basin, 6, 1), -0.05, atol=1e-6)
    assert_almost_equal(basin_depth(basin, 20, 1), -0.05, atol=1e-6)
    var mid = basin_depth(basin, 4.5, 1)
    assert_true(mid > 0 and mid < 1.2)
    # The bed turns to mud where the water is shallow.
    assert_equal(basin_mud(basin, BASIN_MUD_DEPTH), 0)
    assert_equal(basin_mud(basin, 2), 0)
    assert_almost_equal(basin_mud(basin, 0), 0.85, atol=1e-6)
    assert_almost_equal(basin_mud(basin, -1), 0.85, atol=1e-6)


def test_a_pond_gives_the_water_its_basin() raises:
    var basin = pond_basin(_pond_ground())
    assert_almost_equal(basin.radius, 3, atol=1e-6)
    assert_almost_equal(basin.depth, 1, atol=1e-6)
    # The water lies its drop below level ground, which is the rim.
    assert_almost_equal(basin.rim, POND_DROP, atol=1e-4)
    var dry = pond_basin(Ground(hill_height=_m(0)))
    assert_equal(dry.radius, 0)


def test_several_drops_step_as_one_drop_does() raises:
    var size = SpectrumResolution(16)
    var one = RippleField(size, _m(7))
    var many = RippleField(size, _m(7))
    step_ripple(one, 0, 0, 0.5, 0.5, 0.1, 0.07)
    step_ripple_drops(many, 0, 0, [RippleDrop(0.5, 0.5, 0.1, 0.07)])
    for k in range(len(one.height)):
        assert_equal(one.height[k], many.height[k])
    # Two drops pull the water down at both places.
    var two = RippleField(size, _m(7))
    step_ripple_drops(
        two,
        0,
        0,
        [RippleDrop(0.25, 0.25, 0.1, 0.07), RippleDrop(0.75, 0.75, 0.1, 0.07)],
    )
    assert_true(two.height[4 * 16 + 4] < 0)
    assert_true(two.height[12 * 16 + 12] < 0)


def _water() raises -> WaterScene:
    var size = SpectrumResolution(16)
    return WaterScene(size, 8, 16, size, Duration(5.0, SECOND))


def test_a_splash_ripples_the_water_where_it_falls() raises:
    var water = _water()
    water.place_ripples(_m(10), _m(-4), _m(8))
    assert_equal(water._ripples.center_x, 10)
    assert_equal(water._ripples.center_z, -4)
    assert_equal(water._ripples.size, 8)
    # A splash out of the window is let go.
    water.splash(_m(100), _m(-4), _m(0.3), 0.05)
    water.splash(_m(10), _m(100), _m(0.3), 0.05)
    assert_equal(len(water._drops), 0)
    water.splash(_m(11), _m(-3), _m(0.6), 0.05)
    assert_equal(len(water._drops), 1)
    # At most 64 drops wait for a step.
    for _ in range(80):
        water.splash(_m(10), _m(-4), _m(0.3), 0.01)
    assert_equal(len(water._drops), 64)
    water.advance(Duration(0.1, SECOND), False)
    assert_equal(len(water._drops), 0)
    var lowest = Float32(0)
    for h in water._ripples.height:
        lowest = min(lowest, h)
    assert_true(lowest < 0)
    # A reset calms the window where it lies.
    water.splash(_m(10), _m(-4), _m(0.3), 0.01)
    water.reset()
    assert_equal(len(water._drops), 0)
    assert_equal(water._ripples.center_x, 10)
    assert_equal(water._ripples.size, 8)
    for h in water._ripples.height:
        assert_equal(h, 0)


def test_a_splash_and_a_window_are_checked() raises:
    var water = _water()
    with assert_raises(contains="200 meters"):
        water.place_ripples(_m(0), _m(0), _m(0.5))
    with assert_raises(contains="200 meters"):
        water.place_ripples(_m(0), _m(0), _m(300))
    with assert_raises(contains="finite"):
        water.place_ripples(_m(inf[DType.float32]()), _m(0), _m(5))
    with assert_raises(contains="finite"):
        water.place_ripples(_m(0), _m(inf[DType.float32]()), _m(5))
    with assert_raises(contains="finite"):
        water.splash(_m(inf[DType.float32]()), _m(0), _m(0.1), 0.1)
    with assert_raises(contains="finite"):
        water.splash(_m(0), _m(inf[DType.float32]()), _m(0.1), 0.1)
    with assert_raises(contains="10 meters"):
        water.splash(_m(0), _m(0), _m(11), 0.1)
    with assert_raises(contains="strength"):
        water.splash(_m(0), _m(0), _m(0.1), 2)


def test_a_drowned_point_lies_below_the_water() raises:
    var ground = _pond_ground()
    assert_true(ground.drowned(0, 0))
    assert_false(ground.drowned(10, 0))
    assert_false(Ground(hill_height=_m(0)).drowned(0, 0))
    # The mud is wet at the water's edge, and dry away from it.
    assert_equal(ground.damp(0, 0), 1)
    assert_equal(ground.damp(10, 0), 0)


def test_no_blade_roots_under_the_water_or_heads_on_its_shore() raises:
    var parameters = FieldParameters()
    parameters.span = _m(12)
    parameters.cluster_size = _m(4)
    parameters.density = 200
    parameters.seed_share = 0.5
    var ground = _pond_ground()
    var field = GrassField(parameters^, ground)
    var grown = 0
    for index in range(len(field.clusters)):
        for blade in range(field.clusters[index].tufts * 8):
            var made = field.grow(index, blade)
            if not made:
                continue
            grown += 1
            ref b = made.value()
            assert_false(ground.drowned(b.root.x, b.root.z))
            if ground.wet(b.root.x, b.root.z):
                assert_false(b.kind == SEED_HEAD)
    assert_true(grown > 0)


def test_the_shore_grows_reeds_lays_stones_and_floats_pads() raises:
    var assets = Assets()
    var looks = house_looks(assets, 8, 1)
    var scene = Scene()
    var shore = stand_shore(
        scene, assets, looks, ShoreParameters(), _pond_ground(), List[Lot]()
    )
    assert_true(shore.reeds > 0)
    assert_true(shore.stones > 0)
    assert_true(shore.pads > 0)
    assert_equal(shore.meshes, 1)
    assert_true(shore.triangles > 0)
    # Nothing stands on a lot over the whole pond.
    var clear = Scene()
    var kept = stand_shore(
        clear,
        assets,
        looks,
        ShoreParameters(),
        _pond_ground(),
        [Lot(0, 0, 8, 8, 0)],
    )
    assert_equal(kept.meshes, 0)
    assert_equal(kept.reeds + kept.stones + kept.pads, 0)
    # Ground with no pond has no shore.
    var dry = Scene()
    var none = stand_shore(
        dry, assets, looks, ShoreParameters(), Ground(), List[Lot]()
    )
    assert_equal(none.meshes, 0)
    var many = ShoreParameters()
    many.reeds = 501
    with assert_raises(contains="500"):
        many.check()


def _camera() raises -> PerspectiveCamera:
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 1, 6), Vector3(0, 0.5, 0))
    return camera^


def _frame(
    camera: PerspectiveCamera, side: Int = 24
) raises -> Tuple[Framebuffer, List[Float32]]:
    """Return a frame of a red wall at z = -2, standing on water at y = 0,
    and the depths before the water was composed: the wall's above the
    water, and the wall's below it, which the water then covered."""
    var w = side
    var h = side
    var image = Framebuffer(w, h, Color(0, 0, 0, 255))
    var clip = camera.projection_matrix()
    clip.multiply(camera.view_matrix())
    var inverse = clip
    inverse.invert()
    var before = List[Float32](length=w * h, fill=inf[DType.float32]())
    for y in range(h):
        var ny = 1 - (Float32(y) + 0.5) / Float32(h) * 2
        for x in range(w):
            var nx = (Float32(x) + 0.5) / Float32(w) * 2 - 1
            var a = inverse.transform_point(Vector3(nx, ny, -1))
            var b = inverse.transform_point(Vector3(nx, ny, 1))
            var d = b - a
            var k = y * w + x
            # Where the ray meets the wall, and the water.
            var t = (-2 - a.z) / d.z
            var at = a + d * t
            var wall = clip.transform_point(at).z
            if at.y >= 0:
                image.set_pixel(x, y, Color(200, 30, 30, 255))
                before[k] = wall
                image.depth[k] = wall
            else:
                var s = (0 - a.y) / d.y
                var flat = clip.transform_point(a + d * s).z
                image.set_pixel(x, y, Color(60, 90, 120, 255))
                before[k] = wall
                image.depth[k] = flat
    return (image^, before^)


def _clone(image: Framebuffer) raises -> Framebuffer:
    return Framebuffer(
        image.width, image.height, image.pixels.copy(), image.depth.copy()
    )


def test_the_water_mirrors_the_scene_above_it() raises:
    var camera = _camera()
    var made = _frame(camera)
    var image = _clone(made[0])
    var before = made[1].copy()
    var mask = water_mask(image, before)
    var waters = 0
    for m in mask:
        if m:
            waters += 1
    assert_true(waters > 0)
    var look = PondLook()
    var shown = look.apply(image, before, camera, _m(0), FogView.none(), 0)
    assert_true(shown > 0)
    # Some water pixel turned red with the wall's mirror image.
    var reddest = 0
    for k in range(len(mask)):
        if mask[k]:
            reddest = max(reddest, Int(image.pixels[k * 4]))
    assert_true(reddest > 60)
    # No mirror: the water keeps its color.
    var plain = _clone(made[0])
    var still = PondLook()
    still.mirror = 0
    assert_equal(
        still.apply(plain, before, camera, _m(0), FogView.none(), 0), 0
    )
    for k in range(len(mask)):
        if mask[k]:
            assert_equal(plain.pixels[k * 4], 60)
    _ = MIRROR_MOST


def test_the_water_fades_into_fog_and_mirrors_the_stars() raises:
    var camera = _camera()
    var made = _frame(camera)
    var foggy = _clone(made[0])
    var before = made[1].copy()
    var look = PondLook()
    look.mirror = 0
    var fog = FogView(
        exp2_fog(Color(255, 255, 255, 255), InverseLength(0.5, PER_METER))
    )
    _ = look.apply(foggy, before, camera, _m(0), fog, 0)
    var mask = water_mask(foggy, before)
    for k in range(len(mask)):
        if mask[k]:
            assert_true(foggy.pixels[k * 4] > 60)
    # At night, a star or more shows in the water.
    var big = _frame(camera, 200)
    var night = _clone(big[0])
    var dark = big[1].copy()
    _ = look.apply(night, dark, camera, _m(0), FogView.none(), 1)
    var lit = water_mask(night, dark)
    var stars = 0
    for k in range(len(lit)):
        if lit[k] and night.pixels[k * 4] > 60:
            stars += 1
    assert_true(stars > 0)


def test_a_pond_look_is_checked() raises:
    var camera = _camera()
    var made = _frame(camera)
    var image = _clone(made[0])
    var before = made[1].copy()
    var look = PondLook()
    look.mirror = 2
    with assert_raises(contains="mirror"):
        _ = look.apply(image, before, camera, _m(0), FogView.none(), 0)
    look.mirror = 1
    with assert_raises(contains="stars"):
        _ = look.apply(image, before, camera, _m(0), FogView.none(), 2)
    with assert_raises(contains="depth"):
        _ = look.apply(image, List[Float32](), camera, _m(0), FogView.none(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
