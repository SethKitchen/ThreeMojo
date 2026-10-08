# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Independent refusal, conservation and atomic-update controls for hair."""

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
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def _fiber() -> HairGroom:
    """Return a straight unit-length fiber with three consistent fields."""
    var groom = HairGroom()
    groom.add(
        [Vector3(0, 0, 0), Vector3(0, 0.5, 0), Vector3(0, 1, 0)],
        [Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)],
        [Float32(0.25), 0.25, 0.25],
        1,
    )
    return groom^


def test_density_resolution_change_preserves_projected_area() raises:
    var groom = _fiber()
    var density = HairDensity(4, Length(0.001, METER))
    density.rebuild(groom)
    for resolution in [8, 4]:
        density.resolution = resolution
        density.rebuild(groom)
        assert_equal(len(density.coefficients), resolution**3)
        var total = Float32(0)
        for value in density.coefficients:
            total += value
        assert_almost_equal(
            total * density.cell**3, Float32(0.001), atol=1e-8
        )


def test_density_refuses_missing_and_decreasing_starts() raises:
    var density = HairDensity(4)
    var groom = _fiber()
    groom.starts = List[Int]()
    with assert_raises(contains="beginning at zero"):
        density.rebuild(groom)
    groom.starts = [0, 3, 2, 3]
    with assert_raises(contains="ordered"):
        density.rebuild(groom)
    assert_false(density.populated)


def test_density_checks_every_position_coordinate() raises:
    var density = HairDensity(4)
    for bad in [
        Vector3(nan[DType.float32](), 0, 0),
        Vector3(0, inf[DType.float32](), 0),
        Vector3(0, 0, -inf[DType.float32]()),
    ]:
        var groom = _fiber()
        groom.points[1] = bad
        with assert_raises(contains="finite positions"):
            density.rebuild(groom)
        assert_false(density.populated)


def test_density_refuses_unrepresentable_extent_and_volume() raises:
    var density = HairDensity(4)
    var groom = _fiber()
    groom.points[0].y = -3e38
    groom.points[2].y = 3e38
    with assert_raises(contains="grid scale"):
        density.rebuild(groom)
    groom.points[0].y = 0
    groom.points[2].y = 1e20
    with assert_raises(contains="grid scale"):
        density.rebuild(groom)
    assert_false(density.populated)


def test_single_point_strands_deposit_no_area() raises:
    var groom = HairGroom()
    groom.add([Vector3(0, 0, 0)], [Vector3(0, 0, 1)], [Float32(0)], 1)
    var density = HairDensity(4)
    density.rebuild(groom)
    assert_true(density.populated)
    for value in density.coefficients:
        assert_equal(value, 0)
    assert_equal(density.optical_depth(Vector3(0, 0, 0), Vector3(1, 0, 0)), 0)


def test_density_grid_boundaries_and_finite_ray_coordinates() raises:
    var density = HairDensity(4)
    # An unpopulated grid still validates the caller's ray coordinates.
    for bad in [
        Vector3(nan[DType.float32](), 0, 0),
        Vector3(0, inf[DType.float32](), 0),
        Vector3(0, 0, -inf[DType.float32]()),
    ]:
        with assert_raises(contains="finite point"):
            _ = density.optical_depth(bad, Vector3(1, 0, 0))
        with assert_raises(contains="finite light"):
            _ = density.optical_depth(Vector3(0, 0, 0), bad)
    # The grid's half-open bounds have an independent integer-cell oracle.
    assert_equal(density._slot(Vector3(0, 0, 0)), 0)
    assert_equal(density._slot(Vector3(3.5, 2.5, 1.5)), 27)
    for outside in [
        Vector3(-0.1, 0, 0),
        Vector3(0, -0.1, 0),
        Vector3(0, 0, -0.1),
        Vector3(4, 0, 0),
        Vector3(0, 4, 0),
        Vector3(0, 0, 4),
    ]:
        assert_equal(density._slot(outside), -1)
    var groom = _fiber()
    density.rebuild(groom)
    assert_equal(
        density.optical_depth(Vector3(0, 0, 0), Vector3(3e38, 3e38, 3e38)), 0
    )


def test_motion_half_turn_and_zero_normal_have_defined_results() raises:
    var opposite = _motion_normal(
        Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 1, 0)
    )
    assert_almost_equal(opposite.y, Float32(-1), atol=1e-6)
    assert_almost_equal(opposite.length(), Float32(1), atol=1e-6)
    var zero = _motion_normal(
        Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0)
    )
    assert_true(zero == Vector3(0, 0, 1))
    var empty = HairGroom()
    var motion = HairSimulation(empty)
    motion.write(empty)
    assert_equal(len(empty.points), 0)
    assert_equal(empty.starts, [0])


def test_motion_rejects_each_field_mismatch_before_writing() raises:
    for field in range(7):
        var groom = _fiber()
        var motion = HairSimulation(groom)
        motion.now[0].x = 2
        if field == 0:
            groom.starts.append(3)
        elif field == 1:
            _ = groom.normals.pop()
        elif field == 2:
            _ = groom.depths.pop()
        elif field == 3:
            _ = motion.initial_normals.pop()
        elif field == 4:
            _ = motion.initial_depths.pop()
        elif field == 5:
            _ = motion.initial_tangents.pop()
        else:
            groom.starts[1] = 2
        var points = groom.points.copy()
        var normals = groom.normals.copy()
        var depths = groom.depths.copy()
        with assert_raises():
            motion.write(groom)
        assert_true(groom.points == points)
        assert_true(groom.normals == normals)
        assert_equal(groom.depths, depths)


def test_motion_rejects_nonfinite_y_and_z_atomically() raises:
    for bad in [
        Vector3(0, nan[DType.float32](), 0),
        Vector3(0, 0, inf[DType.float32]()),
    ]:
        var groom = _fiber()
        var motion = HairSimulation(groom)
        motion.now[0].x = 2
        motion.now[2] = bad
        var points = groom.points.copy()
        var normals = groom.normals.copy()
        var depths = groom.depths.copy()
        with assert_raises(contains="finite positions"):
            motion.write(groom)
        assert_true(groom.points == points)
        assert_true(groom.normals == normals)
        assert_equal(groom.depths, depths)


def test_shading_refusals_preserve_the_output() raises:
    var lights: List[HairLight] = [
        HairLight(Vector3(0, 0, 1), Vector3(1, 1, 1))
    ]
    var look = HairLook(Vector3(0.3, 0.2, 0.1))
    for field in range(5):
        var groom = _fiber()
        var colors = List[Float32](length=9, fill=7)
        var optical = List[Float32](length=3, fill=0)
        if field == 0:
            _ = colors.pop()
        elif field == 1:
            _ = groom.normals.pop()
        elif field == 2:
            _ = groom.depths.pop()
        elif field == 3:
            _ = groom.shades.pop()
        else:
            optical[2] = nan[DType.float32]()
        var kept = colors.copy()
        with assert_raises():
            shade_groom_into(
                groom,
                look,
                lights,
                Vector3(0, 0, 1),
                Vector3(0, 0, 0),
                colors,
                optical,
            )
        assert_equal(colors, kept)


def test_hair_constructor_and_attachment_refuse_no_segments() raises:
    var empty = HairGroom()
    var look = HairLook(Vector3(0.3, 0.2, 0.1))
    with assert_raises(contains="at least one segment"):
        _ = HairStrands(empty^, GeometryId(0), look)
    var one = HairGroom()
    one.add([Vector3(0, 0, 0)], [Vector3(0, 0, 1)], [Float32(0)], 1)
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    with assert_raises(contains="at least one segment"):
        _ = add_strands(scene, assets, root, one^, look)
    assert_equal(scene.count(), 1)
    assert_equal(assets.geometries.count(), 0)
    assert_equal(assets.materials.count(), 0)


def test_hair_attachment_refuses_each_invalid_opacity_atomically() raises:
    for opacity in [nan[DType.float32](), Float32(-0.1), Float32(1.1)]:
        var scene = Scene()
        var assets = Assets()
        var root = scene.add(Object3D())
        var groom = _fiber()
        with assert_raises(contains="opacity"):
            _ = add_strands(
                scene,
                assets,
                root,
                groom^,
                HairLook(Vector3(0.3, 0.2, 0.1)),
                opacity=opacity,
            )
        assert_equal(scene.count(), 1)
        assert_equal(assets.geometries.count(), 0)
        assert_equal(assets.materials.count(), 0)


def test_hair_update_rejects_topology_changes_before_shared_writes() raises:
    for change in range(2):
        var scene = Scene()
        var assets = Assets()
        var root = scene.add(Object3D())
        var hair = add_strands(
            scene, assets, root, _fiber(), HairLook(Vector3(0.3, 0.2, 0.1))
        )
        var before = hair._buffer.value(0)
        hair.groom.points[0].x = 2
        if change == 0:
            hair.groom.starts.append(3)
        else:
            hair.groom.starts[1] = 2
        with assert_raises(contains="topology"):
            hair.shade(
                assets, List[HairLight](), Vector3(0, 0, 1), Vector3(0, 0, 0)
            )
        assert_equal(hair._buffer.value(0), before)


def test_hair_checks_both_attributes_and_both_buffer_owners() raises:
    for change in range(6):
        var scene = Scene()
        var assets = Assets()
        var root = scene.add(Object3D())
        var hair = add_strands(
            scene, assets, root, _fiber(), HairLook(Vector3(0.3, 0.2, 0.1))
        )
        var foreign = InterleavedBuffer(List[Float32](length=24, fill=11), 6)
        var shape = BufferGeometry()
        if change != 0:
            if change == 2:
                shape.set_attribute(
                    String(POSITION),
                    BufferAttribute(List[Float32](length=12, fill=11), 3),
                )
            elif change == 4:
                shape.set_attribute(
                    String(POSITION), BufferAttribute(foreign, 3, 0)
                )
            else:
                shape.set_attribute(
                    String(POSITION), BufferAttribute(hair._buffer, 3, 0)
                )
        if change != 1:
            if change == 3:
                shape.set_attribute(
                    String(COLOR),
                    BufferAttribute(List[Float32](length=12, fill=11), 3),
                )
            elif change == 5:
                shape.set_attribute(
                    String(COLOR), BufferAttribute(foreign, 3, 3)
                )
            else:
                shape.set_attribute(
                    String(COLOR), BufferAttribute(hair._buffer, 3, 3)
                )
        assets.geometries.replace(hair.geometry, shape^)
        var before = hair._buffer.value(0)
        hair.groom.points[0].x = 2
        with assert_raises(contains="hair geometry"):
            hair.shade(
                assets, List[HairLight](), Vector3(0, 0, 1), Vector3(0, 0, 0)
            )
        assert_equal(hair._buffer.value(0), before)
        assert_equal(foreign.value(0), 11)


def test_singleton_strand_does_not_change_neighbor_segment_upload() raises:
    var groom = HairGroom()
    groom.add([Vector3(1, 0, 0)], [Vector3(0, 0, 1)], [Float32(0)], 1)
    groom.add(
        [Vector3(0, 0, 0), Vector3(0, 1, 0)],
        [Vector3(0, 0, 1), Vector3(0, 0, 1)],
        [Float32(0), 0],
        1,
    )
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var hair = add_strands(
        scene, assets, root, groom^, HairLook(Vector3(0.3, 0.2, 0.1))
    )
    ref positions = assets.geometries.get(hair.geometry).attribute_view(
        String(POSITION)
    )
    assert_equal(positions.count(), 2)
    assert_true(positions.vector3(0) == Vector3(0, 0, 0))
    assert_true(positions.vector3(1) == Vector3(0, 1, 0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
