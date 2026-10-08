# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent invariants for moving hair density, shading and storage."""

from core.assets import Assets
from core.buffer_geometry import COLOR, POSITION
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.skeleton.head.hair.density import HairDensity
from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from extensions.humanoid.skeleton.head.hair.shading import (
    HairLight,
    HairLook,
    shade_groom,
    shade_groom_into,
)
from extensions.humanoid.skeleton.head.hair.simulation import (
    HairSimulation,
    _motion_normal,
)
from extensions.humanoid.skeleton.head.hair.strands import add_strands
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def _add(mut groom: HairGroom, x: Float32, z: Float32 = 0):
    """Add a ten-centimeter vertical fiber with outward +z normals."""
    groom.add(
        [Vector3(x, -0.05, z), Vector3(x, 0, z), Vector3(x, 0.05, z)],
        [Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)],
        [Float32(0), 0, 0],
        1,
    )


def test_density_conserves_deposited_projected_area() raises:
    var groom = HairGroom()
    _add(groom, 0)
    _add(groom, 0.08)
    var density = HairDensity(24, Length(0.00008, METER))
    density.rebuild(groom)
    var sum = Float32(0)
    for index in range(len(density.coefficients)):
        sum += density.coefficients[index]
    var area = sum * density.cell * density.cell * density.cell
    assert_almost_equal(area, Float32(0.2 * 0.00008), atol=1e-9)
    var allocation = Int(density.coefficients.unsafe_ptr())
    density.rebuild(groom)
    assert_equal(Int(density.coefficients.unsafe_ptr()), allocation)
    var right = density.optical_depth(Vector3(0, 0, 0), Vector3(1, 0, 0))
    var left = density.optical_depth(Vector3(0, 0, 0), Vector3(-1, 0, 0))
    assert_true(right > 0)
    assert_equal(left, 0)
    assert_equal(
        density.optical_depth(Vector3(100, 0, 0), Vector3(-1, 0, 0)), 0
    )
    assert_equal(density.optical_depth(Vector3(0, 0, 0), Vector3(0, 0, 0)), 0)
    # Move the second fiber across the first. The shadow must follow it.
    for index in range(3, 6):
        groom.points[index].x = -0.08
    density.rebuild(groom)
    assert_equal(Int(density.coefficients.unsafe_ptr()), allocation)
    assert_true(density.optical_depth(Vector3(0, 0, 0), Vector3(-1, 0, 0)) > 0)
    assert_equal(density.optical_depth(Vector3(0, 0, 0), Vector3(1, 0, 0)), 0)


def test_density_rejects_invalid_boundaries() raises:
    for size in [3, 65]:
        with assert_raises(contains="cells"):
            _ = HairDensity(size)
    for width in [
        Float32(0),
        -0.1,
        nan[DType.float32](),
        inf[DType.float32](),
    ]:
        with assert_raises(contains="diameter"):
            _ = HairDensity(8, Length(width, METER))
    var groom = HairGroom()
    var density = HairDensity(8)
    density.rebuild(groom)
    assert_equal(density.optical_depth(Vector3(0, 0, 0), Vector3(1, 0, 0)), 0)
    _add(groom, 0)
    groom.starts[0] = 1
    with assert_raises(contains="beginning"):
        density.rebuild(groom)
    groom.starts[0] = 0
    groom.starts[1] = 2
    with assert_raises(contains="point count"):
        density.rebuild(groom)
    groom.starts[1] = 3
    groom.points[0].x = nan[DType.float32]()
    with assert_raises(contains="finite positions"):
        density.rebuild(groom)
    with assert_raises(contains="finite point"):
        _ = density.optical_depth(
            Vector3(nan[DType.float32](), 0, 0), Vector3(1, 0, 0)
        )
    with assert_raises(contains="finite light"):
        _ = density.optical_depth(
            Vector3(0, 0, 0), Vector3(inf[DType.float32](), 0, 0)
        )


def test_motion_rotates_normals_and_refreshes_depth() raises:
    var groom = HairGroom()
    _add(groom, 0)
    for index in range(3):
        groom.depths[index] = 0.005
    var motion = HairSimulation(groom)
    for index in range(3):
        motion.now[index] = motion.initial[index] + Vector3(0, 0, 0.01)
    motion.write(groom)
    for index in range(3):
        assert_equal(groom.depths[index], 0)
        assert_almost_equal(groom.normals[index].z, Float32(1), atol=1e-6)
    # Rotate +y tangents into +z: +z normals must rotate into -y.
    for index in range(3):
        motion.now[index] = Vector3(0, 0, motion.initial[index].y)
    motion.write(groom)
    assert_almost_equal(groom.normals[1].y, Float32(-1), atol=1e-6)
    assert_almost_equal(groom.normals[1].length(), Float32(1), atol=1e-6)
    var kept = groom.points[0]
    motion.now[1].x = nan[DType.float32]()
    with assert_raises(contains="finite"):
        motion.write(groom)
    assert_true(groom.points[0] == kept)
    var opposite = _motion_normal(
        Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)
    )
    assert_almost_equal(opposite.z, Float32(1), atol=1e-6)
    var parallel = _motion_normal(
        Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(1, 0, 0)
    )
    assert_almost_equal(parallel.x, Float32(-1), atol=1e-6)


def test_dynamic_shading_uses_optical_depth_and_reuses_output() raises:
    var groom = HairGroom()
    _add(groom, 0)
    var lights: List[HairLight] = [
        HairLight(Vector3(0, 0, 1), Vector3(1, 1, 1))
    ]
    var look = HairLook(Vector3(0.3, 0.2, 0.1))
    look.shadows = 1
    var eye = Vector3(0, 0, 1)
    var ambient = Vector3(0, 0, 0)
    var colors = shade_groom(groom, look, lights, eye, ambient)
    var clear = colors.copy()
    var allocation = Int(colors.unsafe_ptr())
    shade_groom_into(
        groom, look, lights, eye, ambient, colors, [Float32(0), 0, 0]
    )
    assert_equal(colors, clear)
    shade_groom_into(
        groom, look, lights, eye, ambient, colors, [Float32(3), 3, 3]
    )
    assert_equal(Int(colors.unsafe_ptr()), allocation)
    assert_true(colors[0] < clear[0] * 0.1)
    with assert_raises(contains="one value"):
        shade_groom_into(
            groom, look, lights, eye, ambient, colors, [Float32(1)]
        )
    with assert_raises(contains="nonnegative"):
        shade_groom_into(
            groom, look, lights, eye, ambient, colors, [Float32(-1), 0, 0]
        )


def test_hair_updates_reuse_geometry_and_shared_storage() raises:
    var groom = HairGroom()
    _add(groom, 0)
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var hair = add_strands(
        scene, assets, root, groom^, HairLook(Vector3(0.3, 0.2, 0.1))
    )
    var shape = hair.geometry
    var buffer = (
        assets.geometries.get(shape)
        .attribute_view(String(POSITION))
        .interleaved_buffer()
    )
    var density = Int(hair.density.coefficients.unsafe_ptr())
    var lights: List[HairLight] = [
        HairLight(Vector3(0, 0, 1), Vector3(1, 1, 1))
    ]
    hair.shade(assets, lights, Vector3(0, 0, 1), Vector3(0.1, 0.1, 0.1))
    var colors = Int(hair._point_colors.unsafe_ptr())
    var optical = Int(hair._optical_depths.unsafe_ptr())
    for frame in range(4):
        hair.groom.points[2].x = Float32(frame + 1) * 0.01
        hair.shade(assets, lights, Vector3(0, 0, 1), Vector3(0.1, 0.1, 0.1))
        assert_equal(hair.geometry, shape)
        assert_equal(assets.geometries.count(), 1)
        assert_equal(assets.materials.count(), 1)
        assert_equal(len(scene.wide_lines), 1)
        assert_equal(Int(hair.density.coefficients.unsafe_ptr()), density)
        assert_equal(Int(hair._point_colors.unsafe_ptr()), colors)
        assert_equal(Int(hair._optical_depths.unsafe_ptr()), optical)
        assert_true(
            assets.geometries.get(shape)
            .attribute_view(String(COLOR))
            .interleaved_buffer()
            .shares_with(buffer)
        )
    assert_almost_equal(buffer.value(18), Float32(0.04), atol=1e-6)


def test_invalid_groom_attachment_leaves_no_store_or_scene_entries() raises:
    for field in range(3):
        var groom = HairGroom()
        _add(groom, 0)
        if field == 0:
            _ = groom.normals.pop()
        elif field == 1:
            _ = groom.depths.pop()
        else:
            _ = groom.shades.pop()
        var scene = Scene()
        var assets = Assets()
        var root = scene.add(Object3D())
        with assert_raises(contains="shading fields"):
            _ = add_strands(
                scene, assets, root, groom^, HairLook(Vector3(0.3, 0.2, 0.1))
            )
        assert_equal(scene.count(), 1)
        assert_equal(len(scene.wide_lines), 0)
        assert_equal(assets.geometries.count(), 0)
        assert_equal(assets.materials.count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
