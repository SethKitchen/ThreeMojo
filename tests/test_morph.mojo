# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for morph targets: the geometry that carries them, the mesh that
wears them, and the renderer that applies them.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    MAX_MORPH_TARGETS,
    NORMAL,
    POSITION,
)
from core.object3d import NodeId, Object3D
from core.scene import Scene
from materials.material import Color, DOUBLE_SIDE, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.rasterizer import RasterVertex
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-5)
comptime WIDTH = 32
comptime HEIGHT = 32


def flat_triangle() raises -> BufferGeometry:
    """Return one triangle in the z equals zero plane, facing the camera."""
    var geometry = BufferGeometry()
    var points: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    geometry.set_attribute(String(POSITION), BufferAttribute(points^, 3))
    var facing: List[Float32] = [0, 0, 1, 0, 0, 1, 0, 0, 1]
    geometry.set_attribute(String(NORMAL), BufferAttribute(facing^, 3))
    return geometry^


def moved_target() raises -> BufferAttribute:
    """Return a target that carries the first vertex two meters along x and
    leaves the other two where they are."""
    var points: List[Float32] = [2, 0, 0, 1, 0, 0, 0, 1, 0]
    return BufferAttribute(points^, 3)


def stretched_target() raises -> BufferAttribute:
    """Return a target that carries the *second* vertex further along x.

    It keeps the triangle wound the way it started, which the normal tests
    need: a face seen from behind has its normal turned around, and that
    would be measuring the winding rather than the morph.
    """
    var points: List[Float32] = [0, 0, 0, 3, 0, 0, 0, 1, 0]
    return BufferAttribute(points^, 3)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera looking at the origin from along positive z."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


# --- the geometry -----------------------------------------------------------


def test_a_geometry_starts_with_no_morph_targets() raises:
    var geometry = flat_triangle()
    assert_equal(geometry.morph_count(), 0)
    assert_false(geometry.has_morph_normals())
    assert_false(geometry.morph_relative)


def test_a_geometry_carries_morph_positions() raises:
    var geometry = flat_triangle()
    geometry.add_morph_target(moved_target())
    assert_equal(geometry.morph_count(), 1)
    assert_false(geometry.has_morph_normals())
    var moved = geometry.morph_position(0, 0)
    assert_almost_equal(moved.x, Float32(2), atol=TOLERANCE)


def test_a_geometry_carries_morph_normals_beside_them() raises:
    var geometry = flat_triangle()
    var turned: List[Float32] = [1, 0, 0, 1, 0, 0, 1, 0, 0]
    geometry.add_morph_target(moved_target(), BufferAttribute(turned^, 3))
    assert_equal(geometry.morph_count(), 1)
    assert_true(geometry.has_morph_normals())
    assert_almost_equal(
        geometry.morph_normal(0, 2).x, Float32(1), atol=TOLERANCE
    )


def test_a_morph_target_must_fit_the_geometry() raises:
    # A geometry with no positions has no vertices to move.
    var empty = BufferGeometry()
    with assert_raises():
        empty.add_morph_target(moved_target())
    # Two numbers a vertex is not a position.
    var geometry = flat_triangle()
    var flat: List[Float32] = [0, 0, 1, 0, 0, 1]
    with assert_raises():
        geometry.add_morph_target(BufferAttribute(flat^, 2))
    # The right shape, the wrong number of vertices.
    var short: List[Float32] = [0, 0, 0, 1, 0, 0]
    with assert_raises():
        geometry.add_morph_target(BufferAttribute(short^, 3))


def test_a_geometry_holds_eight_morph_targets_at_most() raises:
    var geometry = flat_triangle()
    for _ in range(MAX_MORPH_TARGETS):
        geometry.add_morph_target(moved_target())
    assert_equal(geometry.morph_count(), MAX_MORPH_TARGETS)
    with assert_raises():
        geometry.add_morph_target(moved_target())


def test_every_morph_target_carries_normals_or_none_does() raises:
    var turned: List[Float32] = [1, 0, 0, 1, 0, 0, 1, 0, 0]
    var without = flat_triangle()
    without.add_morph_target(moved_target())
    with assert_raises():
        without.add_morph_target(moved_target(), BufferAttribute(turned^, 3))

    var second: List[Float32] = [1, 0, 0, 1, 0, 0, 1, 0, 0]
    var with_normals = flat_triangle()
    with_normals.add_morph_target(moved_target(), BufferAttribute(second^, 3))
    with assert_raises():
        with_normals.add_morph_target(moved_target())


def test_a_geometry_refuses_a_morph_target_it_does_not_have() raises:
    var geometry = flat_triangle()
    geometry.add_morph_target(moved_target())
    with assert_raises():
        _ = geometry.morph_position(-1, 0)
    with assert_raises():
        _ = geometry.morph_position(1, 0)
    # The targets carry no normals at all, so every index is refused.
    with assert_raises():
        _ = geometry.morph_normal(0, 0)
    with assert_raises():
        _ = geometry.morph_normal(-1, 0)


# --- the mesh ---------------------------------------------------------------


def a_mesh(mut assets: Assets, var geometry: BufferGeometry) raises -> Mesh:
    """Return a mesh drawing `geometry` at node zero, drawn on both sides.

    Both sides because a morph target can carry a vertex past its
    neighbors and turn the face inside out, and these tests are about where
    the vertices land rather than which way the triangle ends up facing.
    """
    return Mesh(
        assets.geometries.add(geometry^),
        assets.materials.add(Material(Color(255, 255, 255), side=DOUBLE_SIDE)),
        NodeId(0),
    )


def test_a_mesh_wears_nothing_to_begin_with() raises:
    var assets = Assets()
    var mesh = a_mesh(assets, flat_triangle())
    assert_false(mesh.is_morphed())
    assert_almost_equal(mesh.morph_influence(0), Float32(0), atol=TOLERANCE)


def test_a_mesh_wears_a_morph_target() raises:
    var assets = Assets()
    var mesh = a_mesh(assets, flat_triangle())
    mesh.set_morph_influence(2, 0.75)
    assert_true(mesh.is_morphed())
    assert_almost_equal(mesh.morph_influence(2), Float32(0.75), atol=TOLERANCE)


def test_a_mesh_has_eight_influences_and_no_more() raises:
    var assets = Assets()
    var mesh = a_mesh(assets, flat_triangle())
    with assert_raises():
        mesh.set_morph_influence(-1, 1)
    with assert_raises():
        mesh.set_morph_influence(MAX_MORPH_TARGETS, 1)
    with assert_raises():
        _ = mesh.morph_influence(-1)
    with assert_raises():
        _ = mesh.morph_influence(MAX_MORPH_TARGETS)


def test_a_morph_influence_must_be_a_number() raises:
    var assets = Assets()
    var mesh = a_mesh(assets, flat_triangle())
    var nowhere = Float32(0) / Float32(0)
    with assert_raises():
        mesh.set_morph_influence(0, nowhere)


# --- the renderer -----------------------------------------------------------


def prepared(assets: Assets, mesh: Mesh) raises -> List[RasterVertex]:
    """Return the corners the renderer prepares for one mesh at the origin.

    A scene is not copyable, so each call builds its own rather than taking
    one; the mesh is what the tests vary.
    """
    var renderer = Renderer(WIDTH, HEIGHT)
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.add_mesh(mesh)
    scene.update()
    return renderer.prepare(scene, assets, a_camera())


def test_a_worn_target_moves_the_vertex_it_names() raises:
    var assets = Assets()
    var geometry = flat_triangle()
    geometry.add_morph_target(moved_target())
    var mesh = a_mesh(assets, geometry^)

    # Nothing worn: the vertex is where the geometry put it.
    var plain = prepared(assets, mesh)
    assert_almost_equal(plain[0].world.x, Float32(0), atol=TOLERANCE)

    # Half of a target that carries the vertex to two meters.
    mesh.set_morph_influence(0, 0.5)
    var half = prepared(assets, mesh)
    assert_almost_equal(half[0].world.x, Float32(1), atol=TOLERANCE)

    # All of it.
    mesh.set_morph_influence(0, 1)
    var whole = prepared(assets, mesh)
    assert_almost_equal(whole[0].world.x, Float32(2), atol=TOLERANCE)

    # The vertices the target leaves alone do not move.
    assert_almost_equal(whole[1].world.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(whole[2].world.y, Float32(1), atol=TOLERANCE)


def test_a_relative_target_adds_its_own_offsets() raises:
    var assets = Assets()
    var geometry = flat_triangle()
    # The same move written as an offset rather than a destination.
    var offsets: List[Float32] = [2, 0, 0, 0, 0, 0, 0, 0, 0]
    geometry.add_morph_target(BufferAttribute(offsets^, 3))
    geometry.morph_relative = True
    var mesh = a_mesh(assets, geometry^)
    mesh.set_morph_influence(0, 0.5)
    var corners = prepared(assets, mesh)
    assert_almost_equal(corners[0].world.x, Float32(1), atol=TOLERANCE)


def test_two_targets_add_rather_than_compound() raises:
    # Each target carries the first vertex two meters along its own axis.
    # Worn together at half each, the vertex lands one meter along both --
    # which it would not if the second were measured from the first.
    var assets = Assets()
    var geometry = flat_triangle()
    geometry.add_morph_target(moved_target())
    var up: List[Float32] = [0, 2, 0, 1, 0, 0, 0, 1, 0]
    geometry.add_morph_target(BufferAttribute(up^, 3))
    var mesh = a_mesh(assets, geometry^)
    mesh.set_morph_influence(0, 0.5)
    mesh.set_morph_influence(1, 0.5)
    var corners = prepared(assets, mesh)
    assert_almost_equal(corners[0].world.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(corners[0].world.y, Float32(1), atol=TOLERANCE)


def test_morph_normals_turn_the_surface_with_it() raises:
    var assets = Assets()
    var geometry = flat_triangle()
    # A target that turns every normal from +z to +x.
    var turned: List[Float32] = [1, 0, 0, 1, 0, 0, 1, 0, 0]
    geometry.add_morph_target(stretched_target(), BufferAttribute(turned^, 3))
    var mesh = a_mesh(assets, geometry^)
    mesh.set_morph_influence(0, 1)
    var corners = prepared(assets, mesh)
    assert_almost_equal(corners[0].normal.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(corners[0].normal.z, Float32(0), atol=TOLERANCE)


def test_targets_without_normals_keep_the_base_normal() raises:
    # three.js's shader does the same without `morphAttributes.normal`.
    var assets = Assets()
    var geometry = flat_triangle()
    geometry.add_morph_target(stretched_target())
    var mesh = a_mesh(assets, geometry^)
    mesh.set_morph_influence(0, 1)
    var corners = prepared(assets, mesh)
    assert_almost_equal(corners[0].normal.z, Float32(1), atol=TOLERANCE)


def test_one_geometry_wears_two_expressions_at_once() raises:
    # The whole reason the targets are on the geometry and the weights are
    # on the mesh.
    var assets = Assets()
    var geometry = flat_triangle()
    geometry.add_morph_target(moved_target())
    var shape = assets.geometries.add(geometry^)
    var paint = assets.materials.add(
        Material(Color(255, 255, 255), side=DOUBLE_SIDE)
    )
    var renderer = Renderer(WIDTH, HEIGHT)

    var scene = Scene()
    _ = scene.add(Object3D())
    var second = Object3D()
    second.set_position(0, 0, 0)
    _ = scene.add(second^)
    var plain = Mesh(shape, paint, NodeId(0))
    var pulled = Mesh(shape, paint, NodeId(1))
    pulled.set_morph_influence(0, 1)
    scene.add_mesh(plain)
    scene.add_mesh(pulled)
    scene.update()

    var corners = renderer.prepare(scene, assets, a_camera())
    assert_equal(len(corners), 6)
    assert_almost_equal(corners[0].world.x, Float32(0), atol=TOLERANCE)
    assert_almost_equal(corners[3].world.x, Float32(2), atol=TOLERANCE)


def test_a_morphed_mesh_is_not_culled_by_a_bound_it_has_left() raises:
    # The geometry sits at the origin and its bound is around the origin.
    # A target carries it far off to one side, out of the camera's view of
    # the origin but still within the frustum where it has gone.
    var assets = Assets()
    var geometry = flat_triangle()
    var far: List[Float32] = [40, 0, -60, 41, 0, -60, 40, 1, -60]
    geometry.add_morph_target(BufferAttribute(far^, 3))
    var mesh = a_mesh(assets, geometry^)

    # Unworn, the triangle is at the origin and is drawn.
    assert_equal(len(prepared(assets, mesh)), 3)

    # Worn, it has moved to where the bound does not describe it. The
    # renderer must still measure the vertices rather than the stale bound.
    mesh.set_morph_influence(0, 1)
    var moved = prepared(assets, mesh)
    assert_equal(len(moved), 3)
    assert_almost_equal(moved[0].world.x, Float32(40), atol=TOLERANCE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
