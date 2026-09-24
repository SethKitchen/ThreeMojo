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
    COLOR,
    BufferGeometry,
    GeometryGroup,
    MaterialIndex,
    NORMAL,
    POSITION,
)
from core.deform import box_of, morph_offset, morphed_colors, sphere_of
from core.geometry_store import GeometryId
from core.morph import MorphInfluences
from core.object3d import NodeId, Object3D
from core.scene import Scene
from materials.material import Color, DOUBLE_SIDE, Material, MaterialId
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh, morph_target_index
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SkinnedMesh
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
    # Eight meters back, so a vertex carried two meters to the side is
    # still in a 45-degree view and not cut away by the side planes.
    camera.place(Vector3(0, 0, 8), Vector3(0, 0, 0))
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


def test_a_geometry_holds_more_than_eight_morph_targets() raises:
    # three.js on WebGL2 has no cap, and neither has this.
    var geometry = flat_triangle()
    for _ in range(20):
        geometry.add_morph_target(moved_target())
    assert_equal(geometry.morph_count(), 20)


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


def test_a_mesh_has_as_many_influences_as_it_is_given() raises:
    var assets = Assets()
    var mesh = a_mesh(assets, flat_triangle())
    with assert_raises(contains="negative"):
        mesh.set_morph_influence(-1, 1)
    with assert_raises(contains="negative"):
        _ = mesh.morph_influence(-1)
    # A weight never set reads as zero; setting one past the end grows
    # the list with zeros.
    assert_equal(mesh.morph_influence(40), 0)
    mesh.set_morph_influence(40, 0.5)
    assert_equal(len(mesh.morph_influences), 41)
    assert_equal(mesh.morph_influence(39), 0)
    assert_equal(mesh.morph_influence(40), 0.5)


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
    # A target carries it far off to one side, well outside the bound but
    # still inside the frustum: at depth 64 a 45-degree view is over 26
    # meters tall, and the triangle is moved 20 meters up.
    var assets = Assets()
    var geometry = flat_triangle()
    var far: List[Float32] = [0, 20, -60, 1, 20, -60, 0, 21, -60]
    geometry.add_morph_target(BufferAttribute(far^, 3))
    var mesh = a_mesh(assets, geometry^)

    # Unworn, the triangle is at the origin and is drawn.
    assert_equal(len(prepared(assets, mesh)), 3)

    # Worn, it has moved to where the bound does not describe it. The
    # renderer must still measure the vertices rather than the stale bound.
    mesh.set_morph_influence(0, 1)
    var moved = prepared(assets, mesh)
    assert_equal(len(moved), 3)
    assert_almost_equal(moved[0].world.y, Float32(20), atol=TOLERANCE)


def test_a_morph_offset_is_a_run_or_an_offset() raises:
    var base = Vector3(1, 0, 0)
    var target = Vector3(3, 0, 0)
    # An absolute target contributes the run from the base to itself.
    assert_almost_equal(
        morph_offset(base, target, 0.5, False).x, Float32(1), atol=TOLERANCE
    )
    # A relative one contributes itself.
    assert_almost_equal(
        morph_offset(base, target, 0.5, True).x, Float32(1.5), atol=TOLERANCE
    )


def test_bounding_the_points_a_mesh_has_been_carried_to() raises:
    var points: List[Vector3] = [Vector3(0, 0, 0), Vector3(2, 0, 0)]
    var around = sphere_of(points)
    assert_almost_equal(around.center.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(around.radius, Float32(1), atol=TOLERANCE)
    var box = box_of(points)
    assert_almost_equal(box.min.x, Float32(0), atol=TOLERANCE)
    assert_almost_equal(box.max.x, Float32(2), atol=TOLERANCE)
    # No points is not a bound of nothing, it is nothing to bound. The box
    # comes back inside out, as `Box3.empty` is, and the sphere refuses.
    var nothing = box_of(List[Vector3]())
    assert_true(nothing.min.x > nothing.max.x)
    with assert_raises():
        _ = sphere_of(List[Vector3]())


# --- no cap, names and colors ------------------------------------------------


def test_influences_read_zero_past_the_end() raises:
    var worn = MorphInfluences()
    assert_equal(len(worn), 0)
    assert_false(worn.is_worn())
    assert_equal(worn[5], 0)
    assert_equal(worn[-1], 0)
    assert_equal(worn.get(5), 0)
    with assert_raises(contains="negative"):
        _ = worn.get(-1)
    with assert_raises(contains="must be a number"):
        worn.set(0, Float32(0) / Float32(0))
    worn.set(2, 0.25)
    assert_true(worn.is_worn())
    assert_equal(worn[2], 0.25)
    var sized = MorphInfluences(count=3)
    assert_equal(len(sized), 3)
    assert_false(sized.is_worn())
    with assert_raises(contains="negative number"):
        _ = MorphInfluences(count=-1)
    # A copy is its own list.
    var copied = worn
    copied.set(2, 1)
    assert_equal(worn[2], 0.25)


def test_a_mesh_wears_twenty_targets() raises:
    # Each target carries the first vertex a tenth of a meter along x.
    var assets = Assets()
    var geometry = flat_triangle()
    for _ in range(20):
        var points: List[Float32] = [0.1, 0, 0, 1, 0, 0, 0, 1, 0]
        geometry.morph_relative = False
        geometry.add_morph_target(BufferAttribute(points^, 3))
    var mesh = a_mesh(assets, geometry^)
    for target in range(20):
        mesh.set_morph_influence(target, 1)
    var corners = prepared(assets, mesh)
    assert_almost_equal(corners[0].world.x, Float32(2), atol=TOLERANCE)


def test_targets_have_names_and_a_dictionary() raises:
    var geometry = flat_triangle()
    geometry.add_morph_target(moved_target(), name="smile")
    geometry.add_morph_target(stretched_target())
    assert_equal(geometry.morph_target_name(0), "smile")
    assert_equal(geometry.morph_target_name(1), "1")
    # The names are none or one per target: a first name gives the
    # targets before it empty names.
    var unnamed = flat_triangle()
    unnamed.add_morph_target(moved_target())
    assert_equal(len(unnamed.morph_names), 0)
    assert_equal(unnamed.morph_target_name(0), "0")
    unnamed.add_morph_target(moved_target(), name="late")
    assert_equal(len(unnamed.morph_names), 2)
    assert_equal(unnamed.morph_names[0], "")
    assert_equal(unnamed.morph_target_name(1), "late")
    with assert_raises(contains="No morph target"):
        _ = geometry.morph_target_name(2)
    with assert_raises(contains="No morph target"):
        _ = geometry.morph_target_name(-1)
    var assets = Assets()
    var mesh = Mesh(
        assets.geometries.add(geometry.clone()),
        assets.materials.add(Material(Color(255, 255, 255))),
        NodeId(0),
    )
    mesh.set_morph_influence(5, 1)
    mesh.update_morph_targets(geometry)
    assert_equal(len(mesh.morph_influences), 2)
    assert_false(mesh.is_morphed())
    assert_equal(mesh.morph_target_dictionary["smile"], 0)
    assert_equal(mesh.morph_target_dictionary["1"], 1)
    mesh.set_morph_influence("smile", 0.5)
    assert_equal(mesh.morph_influence(0), 0.5)
    with assert_raises(contains="No morph target has the name frown"):
        mesh.set_morph_influence("frown", 0.5)
    assert_equal(morph_target_index(mesh.morph_target_dictionary, "1"), 1)
    # A geometry with no targets leaves the mesh as it is.
    mesh.update_morph_targets(flat_triangle())
    assert_equal(len(mesh.morph_influences), 2)
    # The copy a scene takes carries the dictionary.
    var copied = mesh
    assert_equal(copied.morph_target_dictionary["smile"], 0)


def test_a_skinned_mesh_has_a_dictionary_too() raises:
    var geometry = flat_triangle()
    geometry.add_morph_target(moved_target(), name="smile")
    var placed: List[Matrix4] = [Matrix4()]
    var nodes: List[NodeId] = [NodeId(0)]
    var mesh = SkinnedMesh(
        GeometryId(0), MaterialId(0), NodeId(0), bind_skeleton(nodes, placed)
    )
    mesh.update_morph_targets(geometry)
    mesh.set_morph_influence("smile", 0.75)
    assert_equal(mesh.morph_influence(0), 0.75)
    with assert_raises(contains="No morph target"):
        mesh.set_morph_influence("frown", 1)


def rgb(red: Float32, green: Float32, blue: Float32) raises -> BufferAttribute:
    """Return a color attribute of three vertices, all one color."""
    var data: List[Float32] = [
        red,
        green,
        blue,
        red,
        green,
        blue,
        red,
        green,
        blue,
    ]
    return BufferAttribute(data^, 3)


def test_color_targets_are_all_or_none() raises:
    var geometry = flat_triangle()
    var none = List[BufferAttribute]()
    none.append(rgb(1, 0, 0))
    with assert_raises(contains="Only a geometry with morph targets"):
        geometry.set_morph_colors(none^)
    geometry.add_morph_target(moved_target())
    with assert_raises(contains="a color, or none"):
        geometry.set_morph_colors(List[BufferAttribute]())
    var flat = List[BufferAttribute]()
    flat.append(BufferAttribute([0, 0, 0, 0, 0, 0], 2))
    with assert_raises(contains="three or four numbers"):
        geometry.set_morph_colors(flat^)
    var short = List[BufferAttribute]()
    short.append(BufferAttribute([0, 0, 0, 0, 0, 0], 3))
    with assert_raises(contains="cover every vertex"):
        geometry.set_morph_colors(short^)
    var red = List[BufferAttribute]()
    red.append(rgb(1, 0, 0))
    assert_false(geometry.has_morph_colors())
    geometry.set_morph_colors(red^)
    assert_true(geometry.has_morph_colors())
    assert_equal(geometry.morph_color(0, 1)[0], 1)
    # Three numbers a vertex read an alpha of one.
    assert_equal(geometry.morph_color(0, 1)[3], 1)
    with assert_raises(contains="No morph target has that color"):
        _ = geometry.morph_color(1, 0)
    with assert_raises(contains="No morph target has that color"):
        _ = geometry.morph_color(-1, 0)
    # A target added without a color after the colors is refused, with
    # normals or without.
    with assert_raises(contains="a color, or none"):
        geometry.add_morph_target(moved_target())
    var turned = flat_triangle()
    var facing: List[Float32] = [0, 0, 1, 0, 0, 1, 0, 0, 1]
    turned.add_morph_target(moved_target(), BufferAttribute(facing.copy(), 3))
    var blue = List[BufferAttribute]()
    blue.append(BufferAttribute([0, 0, 1, 0.5, 0, 0, 1, 0.5, 0, 0, 1, 0.5], 4))
    turned.set_morph_colors(blue^)
    assert_equal(turned.morph_color(0, 2)[3], 0.5)
    with assert_raises(contains="a color, or none"):
        turned.add_morph_target(moved_target(), BufferAttribute(facing^, 3))


def test_color_targets_are_carried_by_copies() raises:
    var geometry = flat_triangle()
    geometry.add_morph_target(moved_target(), name="red")
    var red = List[BufferAttribute]()
    red.append(rgb(1, 0, 0))
    geometry.set_morph_colors(red^)
    geometry.set_index([0, 1, 2])
    geometry.add_group(0, 3, MaterialIndex(0))
    var copied = geometry.clone()
    assert_true(copied.has_morph_colors())
    assert_equal(copied.morph_target_name(0), "red")
    var loose = geometry.to_non_indexed()
    assert_true(loose.has_morph_colors())
    assert_equal(loose.morph_target_name(0), "red")
    var part = geometry.group_part(GeometryGroup(0, 3, MaterialIndex(0)))
    assert_true(part.has_morph_colors())
    assert_equal(part.morph_color(0, 0)[0], 1)


def test_morphed_colors_match_three() raises:
    # three.js scales the base by one less the weights for absolute
    # targets and adds each target times its weight.
    var geometry = flat_triangle()
    geometry.add_morph_target(moved_target())
    geometry.add_morph_target(moved_target())
    var tints = List[BufferAttribute]()
    tints.append(rgb(1, 0, 0))
    tints.append(rgb(0, 0, 1))
    geometry.set_morph_colors(tints^)
    var base: List[SIMD[DType.float32, 4]] = [
        SIMD[DType.float32, 4](0.5, 0.5, 0.5, 1),
        SIMD[DType.float32, 4](0.5, 0.5, 0.5, 1),
        SIMD[DType.float32, 4](0.5, 0.5, 0.5, 1),
    ]
    var worn = MorphInfluences()
    worn.set(0, 0.5)
    worn.set(1, 0.25)
    var absolute = morphed_colors(geometry, base, worn)
    # 0.5 * (1 - 0.75) + 1 * 0.5 + 0 * 0.25
    assert_almost_equal(absolute[0][0], Float32(0.625), atol=TOLERANCE)
    assert_almost_equal(absolute[0][1], Float32(0.125), atol=TOLERANCE)
    assert_almost_equal(absolute[0][2], Float32(0.375), atol=TOLERANCE)
    assert_almost_equal(absolute[0][3], Float32(1), atol=TOLERANCE)
    geometry.morph_relative = True
    var relative = morphed_colors(geometry, base, worn)
    assert_almost_equal(relative[0][0], Float32(1), atol=TOLERANCE)
    assert_almost_equal(relative[0][2], Float32(0.75), atol=TOLERANCE)
    # No colors to morph, and no vertices: the base as it is.
    var plain = morphed_colors(flat_triangle(), base, worn)
    assert_equal(plain[1][0], 0.5)
    assert_equal(
        len(morphed_colors(geometry, List[SIMD[DType.float32, 4]](), worn)), 0
    )


def colored_mesh(
    mut assets: Assets, channels: Int, var geometry: BufferGeometry
) raises -> Mesh:
    """Return a mesh with gray vertex colors of `channels` numbers, whose
    one target turns them red."""
    var gray = List[Float32]()
    for _ in range(3):
        for channel in range(channels):
            gray.append(Float32(0.5) if channel < 3 else Float32(0.25))
    geometry.set_attribute(String(COLOR), BufferAttribute(gray^, channels))
    geometry.add_morph_target(moved_target())
    var red = List[BufferAttribute]()
    red.append(BufferAttribute([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1], 4))
    geometry.set_morph_colors(red^)
    return Mesh(
        assets.geometries.add(geometry^),
        assets.materials.add(
            Material(Color(255, 255, 255), side=DOUBLE_SIDE, vertex_colors=True)
        ),
        NodeId(0),
    )


def test_the_renderer_morphs_vertex_colors() raises:
    var assets = Assets()
    var mesh = colored_mesh(assets, 3, flat_triangle())
    var plain = prepared(assets, mesh)
    assert_almost_equal(plain[0].color.r, Float32(0.5), atol=TOLERANCE)
    mesh.set_morph_influence(0, 0.5)
    var half = prepared(assets, mesh)
    assert_almost_equal(half[0].color.r, Float32(0.75), atol=TOLERANCE)
    assert_almost_equal(half[0].color.g, Float32(0.25), atol=TOLERANCE)
    # Three numbers a vertex: the morphed alpha is not read.
    assert_almost_equal(half[0].color.a, Float32(1), atol=TOLERANCE)
    # Four numbers a vertex: it is, from a quarter toward one.
    var clear = colored_mesh(assets, 4, flat_triangle())
    clear.set_morph_influence(0, 0.5)
    var mixed = prepared(assets, clear)
    assert_almost_equal(mixed[0].color.a, Float32(0.625), atol=TOLERANCE)


def test_a_geometry_of_no_vertices_has_no_colors_to_morph() raises:
    var assets = Assets()
    var empty = BufferGeometry()
    var none = List[Float32]()
    empty.set_attribute(String(POSITION), BufferAttribute(none.copy(), 3))
    empty.set_attribute(String(COLOR), BufferAttribute(none.copy(), 3))
    var mesh = Mesh(
        assets.geometries.add(empty^),
        assets.materials.add(
            Material(Color(255, 255, 255), vertex_colors=True)
        ),
        NodeId(0),
    )
    mesh.frustum_culled = False
    assert_equal(len(prepared(assets, mesh)), 0)


def test_a_color_per_instance_is_not_morphed() raises:
    # three.js morphs the vertex color attribute only.
    var assets = Assets()
    var geometry = BufferGeometry(instanced=True)
    var points: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    geometry.set_attribute(String(POSITION), BufferAttribute(points^, 3))
    geometry.set_attribute(
        String(COLOR),
        BufferAttribute([1, 0, 0, 0, 1, 0], 3, mesh_per_attribute=1),
    )
    geometry.add_morph_target(moved_target())
    var blue = List[BufferAttribute]()
    blue.append(rgb(0, 0, 1))
    geometry.set_morph_colors(blue^)
    var mesh = Mesh(
        assets.geometries.add(geometry^),
        assets.materials.add(
            Material(Color(255, 255, 255), side=DOUBLE_SIDE, vertex_colors=True)
        ),
        NodeId(0),
    )
    mesh.set_morph_influence(0, 1)
    var corners = prepared(assets, mesh)
    assert_almost_equal(corners[0].color.r, Float32(1), atol=TOLERANCE)
    assert_almost_equal(corners[0].color.b, Float32(0), atol=TOLERANCE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
