# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `VXGIVolume`: the grid it fits, the sub-voxel bits
its conservative voxelization sets, the opacity chain, the light it
injects from each kind of light, and the bounce it caches. The expected
numbers are three.js's formulas worked by hand."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from lights.light import (
    ambient_light,
    directional_light,
    point_light,
    spot_light,
)
from lights.lighting import falloff
from lights.vxgi_cone_tracer import (
    UNBOUNDED,
    floats_of,
    half_rounded,
    unorm8,
)
from lights.vxgi_volume import (
    VXGIVolume,
    VXGI_DIRECTIONAL,
    VXGI_PI,
    VXGI_POINT,
    VXGI_SPOT,
    VoxelTriangle,
    VxgiLightType,
    light_record,
    resolve_voxel,
    voxel_bits,
    voxel_coordinates,
)
from materials.material import BACK_SIDE, BASIC, DOUBLE_SIDE, Material, Side
from math.bounds import Box3
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import cos, nan, sqrt
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


def quad(
    a: Vector3, b: Vector3, c: Vector3, d: Vector3
) raises -> BufferGeometry:
    """Return two triangles, `a b c` and `a c d`."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION,
        BufferAttribute(
            [a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, d.x, d.y, d.z], 3
        ),
    )
    geometry.set_index([0, 1, 2, 0, 2, 3])
    return geometry^


def triangle(a: Vector3, b: Vector3, c: Vector3) raises -> BufferGeometry:
    """Return one triangle."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION,
        BufferAttribute([a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z], 3),
    )
    return geometry^


def the_wall() raises -> BufferGeometry:
    """Return a wall at x = -0.5, a meter tall and two wide, facing +x."""
    return quad(
        Vector3(-0.5, 0, -1),
        Vector3(-0.5, 1, -1),
        Vector3(-0.5, 1, 1),
        Vector3(-0.5, 0, 1),
    )


def facing_up() raises -> BufferGeometry:
    """Return the floor as two triangles that both face up."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        POSITION,
        BufferAttribute([-1, 0, -1, 1, 0, -1, 1, 0, 1, -1, 0, 1], 3),
    )
    geometry.set_index([0, 2, 1, 0, 3, 2])
    return geometry^


def add_mesh(
    mut assets: Assets,
    mut scene: Scene,
    var geometry: BufferGeometry,
    material: Material,
) raises:
    """Add a mesh on a node of its own."""
    scene.add_mesh(
        Mesh(
            assets.geometries.add(geometry^),
            assets.materials.add(material),
            scene.add(Object3D()),
        )
    )


def at(mut scene: Scene, x: Float32, y: Float32, z: Float32) raises -> NodeId:
    """Return a new node at a point."""
    var node = Object3D()
    node.set_position(x, y, z)
    return scene.add(node^)


def a_floor(mut assets: Assets, mut scene: Scene, side: Side = Side(0)) raises:
    """Add the white floor."""
    add_mesh(assets, scene, facing_up(), Material(WHITE, side=side))


def a_sun(mut scene: Scene, y: Float32 = 5, intensity: Float32 = 1) raises:
    """Add a white sun straight above the origin, or below it."""
    scene.add_light(directional_light(WHITE, at(scene, 0, y, 0), intensity))


def lit(
    mut scene: Scene, mut assets: Assets, resolution: Int = 16, bounces: Int = 0
) raises -> VXGIVolume:
    """Return a volume of the scene, updated."""
    scene.update()
    var volume = VXGIVolume(resolution)
    volume.bounces = bounces
    volume.update(scene, assets)
    return volume^


def bits(volume: VXGIVolume, x: Int, y: Int, z: Int) -> Int32:
    """Return a voxel's sub-voxel bits."""
    return volume.occupancy[
        x + volume.grid.size_x * (y + volume.grid.size_y * z)
    ]


def test_a_light_type_is_one_of_three() raises:
    assert_true(VXGI_DIRECTIONAL.is_valid())
    assert_true(VXGI_POINT.is_valid())
    assert_true(VXGI_SPOT.is_valid())
    assert_false(VxgiLightType(3).is_valid())
    var scene = Scene()
    var light = directional_light(WHITE, at(scene, 0, 1, 0))
    with assert_raises(contains="directional, point or spot"):
        _ = light_record(
            VxgiLightType(3), Vector3(0, 0, 0), Vector3(0, 1, 0), light
        )


def test_a_record_holds_what_three_js_writes() raises:
    var scene = Scene()
    var spot = spot_light(
        WHITE,
        at(scene, 0, 1, 0),
        intensity=2,
        distance=5,
        angle=Angle(30.0, DEGREE),
        penumbra=0.5,
        decay=1,
    )
    var record = light_record(
        VXGI_SPOT, Vector3(0, 1, 0), Vector3(0, -1, 0), spot
    )
    assert_equal(len(record), 16)
    assert_equal(record[1], 1)
    assert_equal(record[3], 2)
    assert_equal(record[5], -1)
    assert_equal(record[7], 5)
    assert_equal(record[8], 2)
    assert_equal(record[11], 1)
    assert_almost_equal(record[12], cos(Float32(0.5235987755982988)), atol=1e-6)
    assert_almost_equal(record[13], cos(Float32(0.2617993877991494)), atol=1e-6)
    # A directional light has no distance, and three.js's decay of two.
    var sun = directional_light(WHITE, at(scene, 0, 1, 0))
    record = light_record(
        VXGI_DIRECTIONAL, Vector3(0, 1, 0), Vector3(0, 1, 0), sun
    )
    assert_equal(record[3], 0)
    assert_equal(record[7], 0)
    assert_equal(record[11], 2)
    assert_equal(record[12], 0)


def test_a_volume_refuses_settings_it_cannot_use() raises:
    var volume = VXGIVolume(0)
    with assert_raises(contains="resolution must be positive"):
        volume.validate()
    volume = VXGIVolume()
    volume.bounces = -1
    with assert_raises(contains="bounces"):
        volume.validate()
    volume = VXGIVolume()
    volume.max_lights = -1
    with assert_raises(contains="light count"):
        volume.validate()
    volume = VXGIVolume()
    volume.min_opacity = nan[DType.float32]()
    with assert_raises(contains="minimum opacity"):
        volume.validate()
    volume = VXGIVolume()
    volume.step_scale = 0
    with assert_raises(contains="step scale"):
        volume.validate()
    volume.step_scale = nan[DType.float32]()
    with assert_raises(contains="step scale"):
        volume.validate()
    volume = VXGIVolume()
    volume.max_distance = Length(-1.0, METER)
    with assert_raises(contains="distance"):
        volume.validate()
    volume.max_distance = Length(nan[DType.float32](), METER)
    with assert_raises(contains="distance"):
        volume.validate()
    var apertures: List[Float32] = [0, 180, nan[DType.float32]()]
    for aperture in apertures:
        volume = VXGIVolume()
        volume.shadow_cone_angle = Angle(aperture, DEGREE)
        with assert_raises(contains="shadow cone"):
            volume.validate()
        volume = VXGIVolume()
        volume.bounce_cone_angle = Angle(aperture, DEGREE)
        with assert_raises(contains="bounce cone"):
            volume.validate()
    VXGIVolume().validate()


def test_the_grid_fits_the_floor_as_three_js_fits_it() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    var volume = lit(scene, assets)
    # Sixteen voxels across two meters; one more each side, rounded up to
    # the second level's step of two.
    assert_equal(volume.grid.voxel_size, 0.125)
    assert_equal(volume.grid.size_x, 18)
    assert_equal(volume.grid.size_y, 2)
    assert_equal(volume.grid.size_z, 18)
    assert_equal(volume.grid.levels, 2)
    assert_true(volume.grid.bounds_min == Vector3(-1.125, -0.125, -1.125))
    assert_true(volume.world_bounds.max == Vector3(1.125, 0.125, 1.125))
    assert_equal(len(volume.occupancy), 18 * 2 * 18)
    assert_equal(len(volume.opacity), (18 * 2 * 18 + 9 * 1 * 9) * 4)


def test_the_floor_s_voxels_hold_its_sub_voxel_bits() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    var volume = lit(scene, assets)
    # The floor fills the lower half of the voxels of row one, x and z
    # from sub-voxel 2 to 34: voxels 1 to 17, the last holding one column.
    assert_equal(bits(volume, 5, 1, 5), 0x33)
    assert_equal(bits(volume, 17, 1, 5), 0x11)
    assert_equal(bits(volume, 5, 1, 17), 0x03)
    assert_equal(bits(volume, 17, 1, 17), 0x01)
    assert_equal(bits(volume, 0, 1, 5), 0)
    assert_equal(bits(volume, 5, 0, 5), 0)
    assert_true(volume.triangle_ids[5 + 18 * (1 + 2 * 5)] > 0)


def test_the_resolve_turns_bits_into_opacity() raises:
    var q = unorm8(0.5)
    var full = resolve_voxel(0x33)
    assert_equal(full[0], q)
    assert_equal(full[1], 1)
    assert_equal(full[2], q)
    assert_equal(full[3], q)
    var one = resolve_voxel(0x01)
    assert_equal(one[0], unorm8(0.25))
    assert_equal(one[1], unorm8(0.25))
    assert_equal(one[2], unorm8(0.25))
    assert_equal(one[3], unorm8(0.125))
    var all = resolve_voxel(0xFF)
    assert_equal(all[0], 1)
    assert_equal(all[3], 1)


def test_an_opacity_level_combines_along_and_averages_across() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    var volume = lit(scene, assets)
    var q = unorm8(0.5)
    assert_true(volume.opacity_at(0, 5, 1, 5)[0] == q)
    var coarse = volume.opacity_at(1, 2, 0, 2)
    # Along x, two floor voxels one behind the other in the upper row and
    # nothing in the lower: `1 - (1 - q)^2` twice of four.
    var along = unorm8((1 - (1 - q) * (1 - q)) * 2 * 0.25)
    assert_equal(coarse[0], along)
    # Along y each column holds the floor: one.
    assert_equal(coarse[1], 1)
    assert_equal(coarse[2], along)
    assert_equal(coarse[3], unorm8(q * 4 * 0.125))


def test_the_host_walk_and_the_voxel_query_agree() raises:
    # What a kernel asks of each voxel is what the host's walk sets: the
    # floor, a wall, a tilted triangle and a triangle of no area.
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    add_mesh(
        assets,
        scene,
        the_wall(),
        Material(WHITE),
    )
    add_mesh(
        assets,
        scene,
        triangle(
            Vector3(0.1, 0.2, 0.3),
            Vector3(0.9, 0.35, -0.6),
            Vector3(0.2, 0.8, 0.5),
        ),
        Material(WHITE),
    )
    add_mesh(
        assets,
        scene,
        triangle(
            Vector3(0, 0.5, 0),
            Vector3(0.5, 0.5, 0),
            Vector3(0.25, 0.5, 0),
        ),
        Material(WHITE),
    )
    add_mesh(
        assets,
        scene,
        triangle(
            Vector3(0.2, 0.1, 0.4),
            Vector3(0.7, 0.3, 0.45),
            Vector3(0.3, 0.8, 0.5),
        ),
        Material(WHITE),
    )
    var volume = lit(scene, assets, resolution=8)
    var grid = volume.grid
    var records = floats_of(volume.triangles)
    var covered = 0
    for index in range(grid.level_count(0)):
        var place = voxel_coordinates(index, grid.size_x, grid.size_y)
        var found = voxel_bits(
            records, volume.triangle_count(), grid, place[0], place[1], place[2]
        )
        assert_equal(Int32(found[0]), volume.occupancy[index])
        assert_equal(Int32(found[1]), volume.triangle_ids[index])
        if found[0] != 0:
            covered += 1
    assert_true(covered > 50)
    # No triangles set nothing.
    var none = voxel_bits(records, 0, grid, 1, 1, 1)
    assert_equal(none[0], 0)
    assert_equal(none[1], 0)
    _ = volume^


def test_a_triangle_touching_the_far_faces_fills_nothing() raises:
    # Each triangle meets the volume only on a far face: its columns, or
    # its sub-voxels along the dominant axis, lie past the last.
    var assets = Assets()
    var scene = Scene()
    add_mesh(
        assets,
        scene,
        triangle(
            Vector3(1.25, 0, 0),
            Vector3(1.25, 0.5, 0),
            Vector3(1.25, 0, 0.5),
        ),
        Material(WHITE),
    )
    add_mesh(
        assets,
        scene,
        triangle(
            Vector3(1.25, 0, 0),
            Vector3(2, 0, 0),
            Vector3(1.25, 0.5, 0),
        ),
        Material(WHITE),
    )
    add_mesh(
        assets,
        scene,
        triangle(
            Vector3(0, 1.25, 0),
            Vector3(0.5, 1.25, 0),
            Vector3(0, 2, 0),
        ),
        Material(WHITE),
    )
    scene.update()
    var volume = VXGIVolume(8)
    volume.bounds = Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))
    volume.update(scene, assets)
    assert_true(volume.world_bounds.max == Vector3(1.25, 1.25, 1.25))
    assert_true(volume.triangle_count() >= 3)
    var any = 0
    for index in range(len(volume.occupancy)):
        any += Int(volume.occupancy[index])
    assert_equal(any, 0)
    # And the per-voxel query agrees at the far corner.
    var grid = volume.grid
    var found = voxel_bits(
        floats_of(volume.triangles),
        volume.triangle_count(),
        grid,
        grid.size_x - 1,
        grid.size_y - 1,
        0,
    )
    assert_equal(found[0], 0)
    _ = volume^


def test_a_sun_overhead_lights_the_floor() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    a_sun(scene)
    var volume = lit(scene, assets)
    assert_equal(volume.light_count(), 1)
    var texel = volume.radiance_at(0, 5, 1, 5)
    # The albedo times the irradiance over pi, times the occupancy of a
    # half, as a half float.
    assert_equal(texel[0], half_rounded(Float32(1) / VXGI_PI * 0.5))
    assert_equal(texel[3], 0.5)
    var direct = volume.direct[(5 + 18 * (1 + 2 * 5)) * 4]
    assert_equal(direct, texel[0])
    assert_equal(volume.radiance_at(0, 5, 0, 5)[3], 0)
    # The coarser level is the mean of eight children.
    var coarse = volume.radiance_at(1, 2, 0, 2)
    assert_equal(coarse[3], half_rounded(0.5 * 4 * 0.125))


def test_a_bulb_falls_off_with_distance() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    scene.add_light(point_light(WHITE, at(scene, 0, 1, 0)))
    var volume = lit(scene, assets)
    # The voxel at (9, 1, 9) is centered at (0.0625, 0.0625, 0.0625).
    var toward = Vector3(-0.0625, 0.9375, -0.0625)
    var distance = toward.length()
    var ndl = Float32(0.9375) / distance
    var want = falloff(distance, 2, 0) * ndl / VXGI_PI * 0.5
    assert_almost_equal(volume.radiance_at(0, 9, 1, 9)[0], want, atol=1e-3)
    # Past its cutoff a bulb gives nothing.
    var far = Scene()
    var more = Assets()
    a_floor(more, far)
    far.add_light(point_light(WHITE, at(far, 0, 1, 0), distance=0.5))
    var dark = lit(far, more)
    assert_equal(dark.radiance_at(0, 9, 1, 9)[0], 0)


def test_a_spot_lights_only_inside_its_cone() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    scene.add_light(
        spot_light(
            WHITE,
            at(scene, 0, 1, 0),
            angle=Angle(10.0, DEGREE),
            target=at(scene, 0, 0, 0),
        )
    )
    var volume = lit(scene, assets)
    assert_true(volume.radiance_at(0, 9, 1, 9)[0] > 0.1)
    assert_equal(volume.radiance_at(0, 2, 1, 2)[0], 0)


def test_a_floor_lit_from_its_back_or_from_either_side() raises:
    # A back side faces down: a sun above does not reach it, and one below
    # does.
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene, BACK_SIDE)
    a_sun(scene)
    assert_equal(lit(scene, assets).radiance_at(0, 5, 1, 5)[0], 0)
    var below = Scene()
    var more = Assets()
    a_floor(more, below, BACK_SIDE)
    a_sun(below, -5)
    assert_true(lit(below, more).radiance_at(0, 5, 1, 5)[0] > 0.1)
    # Both sides take the light whichever way the normal points.
    var both = Scene()
    var again = Assets()
    a_floor(again, both, DOUBLE_SIDE)
    a_sun(both)
    assert_true(lit(both, again).radiance_at(0, 5, 1, 5)[0] > 0.1)


def test_an_occluder_shades_the_floor_below_it() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    add_mesh(
        assets,
        scene,
        quad(
            Vector3(-0.4, 0.5, -0.4),
            Vector3(0.4, 0.5, -0.4),
            Vector3(0.4, 0.5, 0.4),
            Vector3(-0.4, 0.5, 0.4),
        ),
        Material(WHITE, side=DOUBLE_SIDE),
    )
    a_sun(scene)
    var volume = lit(scene, assets)
    var shaded = volume.radiance_at(0, 9, 1, 9)[0]
    var open = volume.radiance_at(0, 2, 1, 2)[0]
    assert_true(open > 0.1)
    assert_true(shaded < open * 0.5)


def test_ambient_hidden_and_extra_lights_are_skipped() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    scene.add_light(ambient_light(WHITE))
    var hidden = at(scene, 0, 5, 0)
    scene.add_light(directional_light(WHITE, hidden))
    var node = scene.get(hidden)
    node.visible = False
    scene.set(hidden, node^)
    a_sun(scene)
    a_sun(scene)
    scene.update()
    var volume = VXGIVolume(16)
    volume.max_lights = 1
    volume.update(scene, assets)
    assert_equal(volume.light_count(), 1)


def test_a_bounce_carries_the_floor_s_light_to_a_wall() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    add_mesh(
        assets,
        scene,
        the_wall(),
        Material(WHITE),
    )
    a_sun(scene)
    # Eight voxels across: a voxel is a quarter meter, the wall stands in
    # column 3 and the floor lies in row 1.
    var flat = lit(scene, assets, resolution=8, bounces=0)
    assert_equal(flat.radiance_at(0, 3, 2, 5)[3], 0.5)
    assert_equal(flat.radiance_at(0, 3, 2, 5)[0], 0)
    var bounced = lit(scene, assets, resolution=8, bounces=1)
    assert_true(bounced.radiance_at(0, 3, 2, 5)[0] > 0.01)
    # The floor keeps its direct light and gains a little from the wall.
    assert_true(
        bounced.radiance_at(0, 5, 1, 5)[0] >= flat.radiance_at(0, 5, 1, 5)[0]
    )


def test_an_emissive_floor_glows_with_no_light() raises:
    var assets = Assets()
    var scene = Scene()
    add_mesh(assets, scene, facing_up(), Material(WHITE, kind=BASIC))
    var volume = lit(scene, assets)
    assert_equal(volume.light_count(), 0)
    assert_equal(volume.radiance_at(0, 5, 1, 5)[0], 0.5)


def test_a_changed_light_or_setting_injects_again() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    a_sun(scene)
    var volume = lit(scene, assets)
    assert_false(volume.lighting_needs_update)
    assert_false(volume.collect_lights(scene))
    scene.lights[0].intensity = 2
    assert_true(volume.collect_lights(scene))
    assert_false(volume.collect_lights(scene))
    volume.bounces = 2
    assert_true(volume.collect_lights(scene))
    volume.lighting_needs_update = True
    assert_true(volume.collect_lights(scene))
    volume.update(scene, assets)
    assert_false(volume.lighting_needs_update)
    assert_almost_equal(
        volume.radiance_at(0, 5, 1, 5)[0],
        half_rounded(Float32(2) / VXGI_PI * 0.5),
        atol=1e-3,
    )


def test_the_scene_is_voxelized_again_only_when_asked() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    var volume = lit(scene, assets)
    assert_false(volume.needs_voxels())
    assert_false(volume.needs_update)
    volume.resolution = 8
    volume.update(scene, assets)
    assert_equal(volume.grid.size_x, 18)
    volume.needs_update = True
    assert_true(volume.needs_voxels())
    volume.update(scene, assets)
    assert_equal(volume.grid.size_x, 10)


def test_requested_bounds_are_used_and_a_point_is_refused() raises:
    var assets = Assets()
    var scene = Scene()
    a_floor(assets, scene)
    scene.update()
    var volume = VXGIVolume(16)
    volume.bounds = Box3(Vector3(-2, -2, -2), Vector3(2, 2, 2))
    volume.update(scene, assets)
    assert_true(volume.world_bounds.min == Vector3(-2.25, -2.25, -2.25))
    var point = VXGIVolume(16)
    point.bounds = Box3(Vector3(1, 1, 1), Vector3(1, 1, 1))
    with assert_raises(contains="must have a size"):
        point.update(scene, assets)


def test_an_empty_scene_voxelizes_a_default_box() raises:
    var assets = Assets()
    var scene = Scene()
    var volume = lit(scene, assets, resolution=4)
    # At least eight voxels across the box from -1 to 1, and one level.
    assert_equal(volume.grid.voxel_size, 0.25)
    assert_equal(volume.grid.size_x, 10)
    assert_equal(volume.grid.levels, 1)
    assert_equal(volume.triangle_count(), 0)


def test_a_cone_reaches_its_distance_or_without_end() raises:
    var volume = VXGIVolume()
    assert_equal(volume.trace_distance(), UNBOUNDED)
    volume.max_distance = Length(3.0, METER)
    assert_equal(volume.trace_distance(), 3)
    assert_almost_equal(volume.shadow_tan(), Float32(0.08748866), atol=1e-6)
    assert_almost_equal(volume.bounce_tan(), Float32(0.57735027), atol=1e-6)


def test_a_voxel_s_place_splits_into_its_coordinates() raises:
    var place = voxel_coordinates(1 + 4 * (2 + 3 * 1), 4, 3)
    assert_equal(place[0], 1)
    assert_equal(place[1], 2)
    assert_equal(place[2], 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
