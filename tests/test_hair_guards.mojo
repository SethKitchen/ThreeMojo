# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Refusals and edge cases of moving hair density, shading and strands."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from core.geometry_store import GeometryId
from core.interleaved_buffer import InterleavedBuffer
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
from extensions.humanoid.skeleton.head.hair.strands import (
    HairStrands,
    add_strands,
)
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


def _add(mut groom: HairGroom, x: Float32, points: Int = 3):
    """Add a vertical fiber of one, two or three points at x."""
    var p = List[Vector3]()
    var n = List[Vector3]()
    var d = List[Float32]()
    for index in range(points):
        p.append(Vector3(x, Float32(index) * 0.05 - 0.05, 0))
        n.append(Vector3(0, 0, 1))
        d.append(0)
    groom.add(p, n, d, 1)


def _groom() -> HairGroom:
    var groom = HairGroom()
    _add(groom, 0)
    _add(groom, 0.08)
    return groom^


def _lights() -> List[HairLight]:
    return [HairLight(Vector3(0, 0, 1), Vector3(1, 1, 1))]


# --- density ------------------------------------------------------------------


def test_density_reallocates_after_a_resolution_change() raises:
    var density = HairDensity(24, Length(0.00008, METER))
    density.rebuild(_groom())
    density.resolution = 8
    density.rebuild(_groom())
    assert_equal(len(density.coefficients), 8 * 8 * 8)


def test_density_refuses_malformed_topology_and_positions() raises:
    var density = HairDensity(24, Length(0.00008, METER))
    var groom = _groom()
    groom.starts.clear()
    with assert_raises(contains="beginning at zero"):
        density.rebuild(groom)
    groom = _groom()
    groom.starts[1] = 7
    with assert_raises(contains="ordered"):
        density.rebuild(groom)
    for axis in range(3):
        groom = _groom()
        if axis == 0:
            groom.points[1].x = nan[DType.float32]()
        elif axis == 1:
            groom.points[1].y = nan[DType.float32]()
        else:
            groom.points[1].z = nan[DType.float32]()
        with assert_raises(contains="finite positions"):
            density.rebuild(groom)


def test_density_refuses_unrepresentable_grid_scales() raises:
    var density = HairDensity(64, Length(0.00008, METER))
    # The span overflows Float32, so the cell is infinite.
    var groom = HairGroom()
    _add(groom, -3.0e38)
    _add(groom, 3.0e38)
    with assert_raises(contains="grid scale"):
        density.rebuild(groom)
    # A finite cell whose cube overflows.
    groom = HairGroom()
    _add(groom, 0)
    _add(groom, 1.0e15)
    with assert_raises(contains="grid scale"):
        density.rebuild(groom)


def test_density_skips_a_one_point_strand() raises:
    var groom = HairGroom()
    _add(groom, 0, 1)
    _add(groom, 0.08)
    var density = HairDensity(24, Length(0.00008, METER))
    density.rebuild(groom)
    assert_true(density.populated)


def test_optical_depth_outside_the_grid_and_with_an_overflowing_direction() raises:
    var density = HairDensity(24, Length(0.00008, METER))
    density.rebuild(_groom())
    var up = Vector3(0, 0, 1)
    assert_equal(density.optical_depth(Vector3(0, -10, 0), up), 0)
    assert_equal(density.optical_depth(Vector3(0, 0, -10), up), 0)
    var huge = Vector3(3.0e38, 3.0e38, 0)
    assert_equal(density.optical_depth(Vector3(0, 0, 0), huge), 0)
    var bad = nan[DType.float32]()
    for axis in range(3):
        var point = Vector3(0, 0, 0)
        var direction = Vector3(0, 0, 1)
        if axis == 0:
            point.x = bad
            direction.x = bad
        elif axis == 1:
            point.y = bad
            direction.y = bad
        else:
            point.z = bad
            direction.z = bad
        with assert_raises(contains="finite point"):
            _ = density.optical_depth(point, up)
        with assert_raises(contains="finite light direction"):
            _ = density.optical_depth(Vector3(0, 0, 0), direction)


# --- shading ------------------------------------------------------------------


def test_shading_into_refuses_mismatched_storage_and_fields() raises:
    var look = HairLook(Vector3(0.3, 0.2, 0.1))
    var eye = Vector3(0, 0, 1)
    var ambient = Vector3(0, 0, 0)
    var groom = _groom()
    var colors = shade_groom(groom, look, _lights(), eye, ambient)
    # No optical depths keep the scalp-depth proxy.
    shade_groom_into(
        groom, look, _lights(), eye, ambient, colors, List[Float32]()
    )
    var depths: List[Float32] = [0, nan[DType.float32](), 0, 0, 0, 0]
    with assert_raises(contains="finite and nonnegative"):
        shade_groom_into(groom, look, _lights(), eye, ambient, colors, depths)
    var short = List[Float32](length=3, fill=0)
    with assert_raises(contains="three floats"):
        shade_groom_into(
            groom, look, _lights(), eye, ambient, short, List[Float32]()
        )
    for field in range(3):
        var broken = _groom()
        if field == 0:
            broken.normals.append(Vector3(0, 0, 1))
        elif field == 1:
            broken.depths.append(0)
        else:
            broken.shades.append(1)
        with assert_raises(contains="shading fields"):
            shade_groom_into(
                broken, look, _lights(), eye, ambient, colors, List[Float32]()
            )


# --- strands ------------------------------------------------------------------


def test_add_strands_refuses_bad_opacity_and_no_segments() raises:
    var look = HairLook(Vector3(0.3, 0.2, 0.1))
    for opacity in [nan[DType.float32](), Float32(-0.5), Float32(1.5)]:
        var scene = Scene()
        var assets = Assets()
        var root = scene.add(Object3D())
        with assert_raises(contains="opacity"):
            _ = add_strands(
                scene, assets, root, _groom(), look, opacity=opacity
            )
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var dots = HairGroom()
    _add(dots, 0, 1)
    with assert_raises(contains="at least one segment"):
        _ = add_strands(scene, assets, root, dots^, look)
    var single = HairGroom()
    _add(single, 0, 1)
    with assert_raises(contains="at least one segment"):
        _ = HairStrands(single^, GeometryId(0), look)
    with assert_raises(contains="at least one segment"):
        _ = HairStrands(HairGroom(), GeometryId(0), look)


def test_strands_with_a_one_point_fiber_upload_its_segments_only() raises:
    var groom = HairGroom()
    _add(groom, 0, 1)
    _add(groom, 0.08)
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var hair = add_strands(
        scene, assets, root, groom^, HairLook(Vector3(0.3, 0.2, 0.1))
    )
    hair.shade(assets, _lights(), Vector3(0, 0, 1), Vector3(0.1, 0.1, 0.1))
    var count = (
        assets.geometries.get(hair.geometry)
        .attribute_view(String(POSITION))
        .count()
    )
    assert_equal(count, 4)


def _installed(mut scene: Scene, mut assets: Assets) raises -> HairStrands:
    var root = scene.add(Object3D())
    var hair = add_strands(
        scene, assets, root, _groom(), HairLook(Vector3(0.3, 0.2, 0.1))
    )
    hair.shade(assets, _lights(), Vector3(0, 0, 1), Vector3(0.1, 0.1, 0.1))
    return hair^


def test_strand_updates_refuse_changed_topology() raises:
    var scene = Scene()
    var assets = Assets()
    var hair = _installed(scene, assets)
    hair.groom.starts.append(6)
    with assert_raises(contains="topology"):
        hair.shade(assets, _lights(), Vector3(0, 0, 1), Vector3(0, 0, 0))
    _ = hair.groom.starts.pop()
    hair.groom.starts[1] = 2
    with assert_raises(contains="topology"):
        hair.shade(assets, _lights(), Vector3(0, 0, 1), Vector3(0, 0, 0))


def _replacement(which: Int, own: InterleavedBuffer) raises -> BufferGeometry:
    var geometry = BufferGeometry()
    var other = InterleavedBuffer(List[Float32](length=24, fill=0), 6)
    var plain: List[Float32] = [0, 0, 0, 1, 1, 1]
    if which == 0:
        return geometry^
    if which == 1:
        geometry.set_attribute(String(POSITION), BufferAttribute(own, 3, 0))
        return geometry^
    if which == 2:
        geometry.set_attribute(
            String(POSITION), BufferAttribute(plain.copy(), 3)
        )
        geometry.set_attribute(String(COLOR), BufferAttribute(own, 3, 3))
        return geometry^
    if which == 3:
        geometry.set_attribute(String(POSITION), BufferAttribute(own, 3, 0))
        geometry.set_attribute(String(COLOR), BufferAttribute(plain.copy(), 3))
        return geometry^
    if which == 4:
        geometry.set_attribute(String(POSITION), BufferAttribute(other, 3, 0))
        geometry.set_attribute(String(COLOR), BufferAttribute(own, 3, 3))
        return geometry^
    geometry.set_attribute(String(POSITION), BufferAttribute(own, 3, 0))
    geometry.set_attribute(String(COLOR), BufferAttribute(other, 3, 3))
    return geometry^


def test_strand_updates_refuse_a_replaced_or_foreign_geometry() raises:
    var messages: List[String] = [
        "was replaced",
        "was replaced",
        "was replaced",
        "was replaced",
        "another owner",
        "another owner",
    ]
    for which in range(6):
        var scene = Scene()
        var assets = Assets()
        var hair = _installed(scene, assets)
        var own = (
            assets.geometries.get(hair.geometry)
            .attribute_view(String(POSITION))
            .interleaved_buffer()
        )
        assets.geometries.replace(hair.geometry, _replacement(which, own))
        with assert_raises(contains=messages[which]):
            hair.shade(assets, _lights(), Vector3(0, 0, 1), Vector3(0, 0, 0))


# --- simulation ---------------------------------------------------------------


def test_motion_normal_half_turn_corners() raises:
    # The rest normal lies along the tangent, which is not near the x axis.
    var along = _motion_normal(
        Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 1, 0)
    )
    assert_almost_equal(along.length(), Float32(1), atol=1e-6)
    # A zero rest normal has no turned direction; +z is the fallback.
    var none = _motion_normal(
        Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 0)
    )
    assert_true(none == Vector3(0, 0, 1))


def test_an_empty_simulation_writes_an_empty_groom() raises:
    var motion = HairSimulation(HairGroom())
    var groom = HairGroom()
    motion.write(groom)
    assert_equal(len(groom.points), 0)
    groom.starts.clear()
    motion.starts.clear()
    motion.write(groom)


def test_simulation_write_refuses_mismatches_and_nonfinite_motion() raises:
    var motion = HairSimulation(_groom())
    var groom = _groom()
    groom.starts.append(6)
    with assert_raises(contains="not the one"):
        motion.write(groom)
    groom = _groom()
    groom.starts[1] = 2
    with assert_raises(contains="not the one"):
        motion.write(groom)
    for field in range(2):
        groom = _groom()
        if field == 0:
            groom.normals.append(Vector3(0, 0, 1))
        else:
            groom.depths.append(0)
        with assert_raises(contains="shading fields"):
            motion.write(groom)
    for field in range(3):
        var rest = HairSimulation(_groom())
        if field == 0:
            rest.initial_normals.append(Vector3(0, 0, 1))
        elif field == 1:
            rest.initial_depths.append(0)
        else:
            rest.initial_tangents.append(Vector3(0, 1, 0))
        groom = _groom()
        with assert_raises(contains="rest shading fields"):
            rest.write(groom)
    for axis in range(3):
        var moved = HairSimulation(_groom())
        if axis == 0:
            moved.now[1].x = nan[DType.float32]()
        elif axis == 1:
            moved.now[1].y = nan[DType.float32]()
        else:
            moved.now[1].z = inf[DType.float32]()
        groom = _groom()
        with assert_raises(contains="finite positions"):
            moved.write(groom)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
