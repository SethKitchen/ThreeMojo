# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for meshes that wear a material list, three.js's
`Mesh.material` as an array.

Each group of the geometry draws with the material its index names, in
the renderer, the raycaster and `createMeshesFromMultiMaterialMesh`. The
built-in geometries write three.js's groups."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    GeometryGroup,
    MaterialIndex,
    POSITION,
)
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.raycaster import Raycaster
from core.scene import Scene
from core.scene_utils import create_meshes_from_multi_material_mesh
from geometries.box import cube
from geometries.cylinder import cone, cylinder
from geometries.edges import triangle_edges
from geometries.extrude import extrude
from materials.material import (
    BACK_SIDE,
    BASIC,
    DOUBLE_SIDE,
    Material,
    MaterialId,
)
from math.path import Path, Shape
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


def two_triangles() raises -> BufferGeometry:
    """Return two triangles side by side facing +z, indexed, with no
    groups: the left one around x = -1 and the right one around x = 1."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute(
            [
                -1.5,
                -0.5,
                0,
                -0.5,
                -0.5,
                0,
                -1.0,
                0.5,
                0,
                0.5,
                -0.5,
                0,
                1.5,
                -0.5,
                0,
                1.0,
                0.5,
                0,
            ],
            3,
        ),
    )
    geometry.set_index([0, 1, 2, 3, 4, 5])
    return geometry^


def basic(red: UInt8, green: UInt8, blue: UInt8) raises -> Material:
    """Return an unlit, two-sided material of one color."""
    return Material(Color(red, green, blue), kind=BASIC, side=DOUBLE_SIDE)


def looking_down_z() raises -> PerspectiveCamera:
    """Return a camera at z = 5 looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, Length(0.5, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


def one_node(mut scene: Scene) raises -> NodeId:
    """Add one node at the origin and update the scene."""
    var node = scene.add(Object3D())
    scene.update()
    return node


# --- The mesh ---------------------------------------------------------


def test_a_mesh_with_one_material_has_no_list() raises:
    var mesh = Mesh(GeometryId(0), MaterialId(2), NodeId(0))
    assert_false(mesh.is_multi_material())
    assert_equal(len(mesh.materials), 0)
    with assert_raises(contains="one material"):
        _ = mesh.group_material(MaterialIndex(0))


def test_a_mesh_with_a_list_reads_it_by_group() raises:
    var mesh = Mesh(GeometryId(0), [MaterialId(3), MaterialId(5)], NodeId(0))
    assert_true(mesh.is_multi_material())
    # The first entry is the one material code that reads one sees.
    assert_true(mesh.material == MaterialId(3))
    assert_true(mesh.group_material(MaterialIndex(1)).value() == MaterialId(5))
    # Past the end: three.js reads `undefined` and draws nothing.
    assert_false(Bool(mesh.group_material(MaterialIndex(2))))
    with assert_raises(contains="negative"):
        _ = mesh.group_material(MaterialIndex(-1))


def test_a_material_list_must_hold_real_materials() raises:
    with assert_raises(contains="needs one material"):
        _ = Mesh(GeometryId(0), List[MaterialId](), NodeId(0))
    with assert_raises(contains="name a material"):
        _ = Mesh(GeometryId(0), [MaterialId(0), MaterialId(-1)], NodeId(0))
    with assert_raises(contains="scene node"):
        _ = Mesh(GeometryId(0), [MaterialId(0)], NodeId(-1))


def test_a_copied_mesh_keeps_its_own_list() raises:
    var mesh = Mesh(
        GeometryId(1),
        [MaterialId(0), MaterialId(1)],
        NodeId(0),
        frustum_culled=False,
        cast_shadow=True,
        receive_shadow=True,
    )
    mesh.set_morph_influence(0, 0.5)
    var copied = mesh
    mesh.materials[1] = MaterialId(7)
    assert_true(copied.materials[1] == MaterialId(1))
    assert_true(copied.geometry == GeometryId(1))
    assert_false(copied.frustum_culled)
    assert_true(copied.cast_shadow and copied.receive_shadow)
    assert_equal(copied.morph_influence(0), 0.5)


# --- A run of the triangle stream ---------------------------------------


def test_a_run_is_clamped_to_whole_triangles_in_the_stream() raises:
    var geometry = two_triangles()
    var whole = geometry.triangle_run(0, -1)
    assert_equal(whole[0], 0)
    assert_equal(whole[1], 2)
    var second = geometry.triangle_run(3, 3)
    assert_equal(second[0], 3)
    assert_equal(second[1], 1)
    # Past the end stops at it, and a part of a triangle is not drawn.
    var over = geometry.triangle_run(2, 99)
    assert_equal(over[0], 2)
    assert_equal(over[1], 1)
    var beyond = geometry.triangle_run(10, 3)
    assert_equal(beyond[0], 6)
    assert_equal(beyond[1], 0)
    with assert_raises(contains="before the stream"):
        _ = geometry.triangle_run(-1, 3)


def test_a_group_part_reads_every_attribute_and_target() raises:
    var geometry = two_triangles()
    var moved = geometry.clone_attribute(String(POSITION))
    geometry.add_morph_target(moved.copy(), moved.copy())
    geometry.morph_relative = True
    var part = geometry.group_part(GeometryGroup(3, 3, MaterialIndex(1)))
    assert_false(part.is_indexed())
    assert_equal(part.vertex_count(), 3)
    assert_equal(len(part.groups), 0)
    assert_equal(part.morph_count(), 1)
    assert_true(part.has_morph_normals())
    assert_true(part.morph_relative)
    assert_equal(part.attribute_view(String(POSITION)).component(0, 0), 0.5)
    with assert_raises():
        _ = geometry.group_part(GeometryGroup(3, 9, MaterialIndex(0)))
    # A group of nothing, of a geometry of nothing, is a geometry of
    # nothing.
    var empty = BufferGeometry().group_part(
        GeometryGroup(0, 0, MaterialIndex(0))
    )
    assert_equal(len(empty.names), 0)


def test_a_wireframe_run_has_only_its_own_edges() raises:
    var geometry = two_triangles()
    assert_equal(len(triangle_edges(geometry)[0]), 6)
    var right = triangle_edges(geometry, 3, 3)
    assert_equal(len(right[0]), 3)
    assert_equal(right[0][0], 3)
    assert_equal(len(triangle_edges(geometry, 6, 3)[0]), 0)


# --- The renderer -------------------------------------------------------


def test_each_face_of_a_box_draws_in_its_own_material() raises:
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var list = List[MaterialId]()
    for face in range(6):
        list.append(assets.materials.add(basic(UInt8(40 * face), 0, 0)))
    var scene = Scene()
    var node = one_node(scene)
    scene.add_mesh(Mesh(box, list, node))
    var renderer = Renderer(24, 24)
    var image = renderer.render(scene, assets, looking_down_z())
    # The camera sees the +z face, which three.js dresses in material 4.
    assert_equal(Int(image.get_pixel(12, 12).r), 160)
    # With one material the groups are not read.
    scene.meshes[0] = Mesh(box, list[2], node)
    image = renderer.render(scene, assets, looking_down_z())
    assert_equal(Int(image.get_pixel(12, 12).r), 80)


def test_a_group_past_the_list_or_no_group_draws_nothing() raises:
    var assets = Assets()
    var geometry = two_triangles()
    geometry.add_group(0, 3, MaterialIndex(0))
    geometry.add_group(3, 3, MaterialIndex(4))
    # No whole triangle: nothing to draw.
    geometry.add_group(0, 2, MaterialIndex(0))
    var grouped = assets.geometries.add(geometry^)
    var plain = assets.geometries.add(two_triangles())
    var red = assets.materials.add(basic(255, 0, 0))
    var scene = Scene()
    var node = one_node(scene)
    scene.add_mesh(Mesh(grouped, [red], node))
    var renderer = Renderer(24, 24)
    var corners = renderer.prepare(scene, assets, looking_down_z())
    assert_equal(len(corners), 3)
    # A list and no groups: three.js finds no group to draw.
    scene.meshes[0] = Mesh(plain, [red], node)
    assert_equal(len(renderer.prepare(scene, assets, looking_down_z())), 0)
    # One material and the same geometry draws both triangles.
    scene.meshes[0] = Mesh(plain, red, node)
    assert_equal(len(renderer.prepare(scene, assets, looking_down_z())), 6)


def test_groups_sort_into_the_opaque_and_the_blended_lists() raises:
    var assets = Assets()
    var geometry = two_triangles()
    geometry.add_group(0, 3, MaterialIndex(0))
    geometry.add_group(3, 3, MaterialIndex(1))
    var pair = assets.geometries.add(geometry^)
    var glass = assets.materials.add(
        Material(
            Color(0, 0, 255),
            kind=BASIC,
            side=DOUBLE_SIDE,
            opacity=0.5,
            transparent=True,
        )
    )
    var solid = assets.materials.add(basic(255, 0, 0))
    var far_green = assets.materials.add(basic(0, 255, 0))
    var scene = Scene()
    var near = scene.add(Object3D())
    var away = Object3D()
    away.set_position(0, 0, -3)
    var far = scene.add(away^)
    scene.update()
    # The near mesh wears glass on its left and red on its right; the
    # far one is green all over.
    scene.add_mesh(Mesh(pair, [glass, solid], near))
    scene.add_mesh(Mesh(pair, far_green, far))
    var corners = Renderer(24, 24).prepare(scene, assets, looking_down_z())
    assert_equal(len(corners), 12)
    # Opaque nearest first: the red group, then the green mesh's two
    # triangles, and the blended group after every opaque one.
    assert_true(corners[0].color.r > 0.9)
    assert_true(corners[3].color.g > 0.9)
    assert_true(corners[6].color.g > 0.9)
    assert_true(corners[9].color.b > 0.9)


def test_a_wireframe_group_draws_its_own_edges_as_lines() raises:
    var assets = Assets()
    var geometry = two_triangles()
    geometry.add_group(0, 3, MaterialIndex(0))
    geometry.add_group(3, 3, MaterialIndex(1))
    var pair = assets.geometries.add(geometry^)
    var wire = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, wireframe=True)
    )
    var solid = assets.materials.add(basic(255, 0, 0))
    var scene = Scene()
    var node = one_node(scene)
    scene.add_mesh(Mesh(pair, [wire, solid], node))
    var renderer = Renderer(24, 24)
    assert_equal(len(renderer.prepare(scene, assets, looking_down_z())), 3)
    assert_equal(
        len(renderer.prepare_lines(scene, assets, looking_down_z())), 6
    )


# --- The raycaster ------------------------------------------------------


def test_a_pick_names_the_material_of_the_group_struck() raises:
    var assets = Assets()
    var geometry = two_triangles()
    geometry.add_group(0, 3, MaterialIndex(0))
    geometry.add_group(3, 3, MaterialIndex(1))
    var pair = assets.geometries.add(geometry^)
    var red = assets.materials.add(basic(255, 0, 0))
    var blue = assets.materials.add(basic(0, 0, 255))
    var scene = Scene()
    var node = one_node(scene)
    scene.add_mesh(Mesh(pair, [red, blue], node))
    var right = Raycaster(Vector3(1.0, 0, 5), Vector3(0, 0, -1))
    var hits = right.intersect_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_true(hits[0].mesh.material == blue)
    assert_equal(hits[0].triangle, 1)
    # three.js's `face.materialIndex`: the group's index.
    assert_equal(hits[0].face.value().material_index.value, 1)
    assert_equal(hits[0].face.value().a, 3)
    # The mesh's own list is kept on the hit.
    assert_equal(len(hits[0].mesh.materials), 2)
    var left = Raycaster(Vector3(-1.0, 0, 5), Vector3(0, 0, -1))
    hits = left.intersect_mesh(scene, assets, 0)
    assert_true(hits[0].mesh.material == red)


def test_a_group_is_picked_with_its_own_materials_side() raises:
    var assets = Assets()
    var geometry = two_triangles()
    geometry.add_group(0, 3, MaterialIndex(0))
    geometry.add_group(3, 3, MaterialIndex(3))
    var pair = assets.geometries.add(geometry^)
    var back = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, side=BACK_SIDE)
    )
    var scene = Scene()
    var node = one_node(scene)
    scene.add_mesh(Mesh(pair, [back], node))
    # The left triangle faces the ray, and its material shows only its
    # back; the right one names a material the list does not have.
    var left = Raycaster(Vector3(-1.0, 0, 5), Vector3(0, 0, -1))
    assert_equal(len(left.intersect_mesh(scene, assets, 0)), 0)
    var right = Raycaster(Vector3(1.0, 0, 5), Vector3(0, 0, -1))
    assert_equal(len(right.intersect_mesh(scene, assets, 0)), 0)
    var behind = Raycaster(Vector3(-1.0, 0, -5), Vector3(0, 0, 1))
    assert_equal(len(behind.intersect_mesh(scene, assets, 0)), 1)
    # A list and no groups is not picked at all.
    scene.meshes[0] = Mesh(assets.geometries.add(two_triangles()), [back], node)
    assert_equal(len(behind.intersect_mesh(scene, assets, 0)), 0)


def test_each_group_is_picked_where_it_is_worn() raises:
    var assets = Assets()
    var geometry = two_triangles()
    geometry.add_group(0, 3, MaterialIndex(0))
    geometry.add_group(3, 3, MaterialIndex(1))
    geometry.add_morph_target(
        BufferAttribute(
            [
                -1.5,
                -0.5,
                1,
                -0.5,
                -0.5,
                1,
                -1.0,
                0.5,
                1,
                0.5,
                -0.5,
                1,
                1.5,
                -0.5,
                1,
                1.0,
                0.5,
                1,
            ],
            3,
        )
    )
    var pair = assets.geometries.add(geometry^)
    var red = assets.materials.add(basic(255, 0, 0))
    var scene = Scene()
    var node = one_node(scene)
    var mesh = Mesh(pair, [red, red], node)
    mesh.set_morph_influence(0, 1.0)
    scene.add_mesh(mesh)
    var right = Raycaster(Vector3(1.0, 0, 5), Vector3(0, 0, -1))
    var hits = right.intersect_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_true(abs(hits[0].distance - 4.0) < 1e-5)
    # Missed wholly: the worn bound is tested group by group.
    var aside = Raycaster(Vector3(9.0, 0, 5), Vector3(0, 0, -1))
    assert_equal(len(aside.intersect_mesh(scene, assets, 0)), 0)


# --- SceneUtils ---------------------------------------------------------


def test_a_multi_material_mesh_splits_into_a_mesh_per_material() raises:
    var assets = Assets()
    var geometry = two_triangles()
    geometry.add_group(3, 3, MaterialIndex(1))
    geometry.add_group(0, 3, MaterialIndex(0))
    # A group of nothing makes a mesh of nothing, as in three.js.
    geometry.add_group(6, 0, MaterialIndex(2))
    var pair = assets.geometries.add(geometry^)
    var red = assets.materials.add(basic(255, 0, 0))
    var blue = assets.materials.add(basic(0, 0, 255))
    var scene = Scene()
    var placed = Object3D()
    placed.set_position(2, 0, 0)
    var node = scene.add(placed^)
    scene.add_mesh(Mesh(pair, [red, blue, red], node))
    var group = create_meshes_from_multi_material_mesh(scene, assets, 0)
    assert_true(scene.get(group).parent == NO_PARENT)
    assert_equal(scene.get(group).position.x, 2)
    assert_equal(len(scene.children(group)), 3)
    assert_equal(len(scene.meshes), 4)
    assert_equal(
        assets.geometries.get(scene.meshes[3].geometry).vertex_count(), 0
    )
    # Sorted by material, as `mergeGroups` sorts them.
    assert_true(scene.meshes[1].material == red)
    assert_false(scene.meshes[1].is_multi_material())
    ref left = assets.geometries.get(scene.meshes[1].geometry)
    assert_false(left.is_indexed())
    assert_equal(left.vertex_count(), 3)
    assert_equal(left.attribute_view(String(POSITION)).component(0, 0), -1.5)
    assert_true(scene.meshes[2].material == blue)
    ref right = assets.geometries.get(scene.meshes[2].geometry)
    assert_equal(right.attribute_view(String(POSITION)).component(0, 0), 0.5)


def test_splitting_asks_for_a_mesh_with_a_list_of_the_right_length() raises:
    var assets = Assets()
    var geometry = two_triangles()
    geometry.add_group(0, 6, MaterialIndex(2))
    var grouped = assets.geometries.add(geometry^)
    var red = assets.materials.add(basic(255, 0, 0))
    var scene = Scene()
    var node = one_node(scene)
    scene.add_mesh(Mesh(grouped, red, node))
    # One material: nothing to split, and the mesh's own node comes back.
    assert_true(
        create_meshes_from_multi_material_mesh(scene, assets, 0) == node
    )
    assert_equal(len(scene.meshes), 1)
    scene.meshes[0] = Mesh(grouped, [red], node)
    with assert_raises(contains="does not have"):
        _ = create_meshes_from_multi_material_mesh(scene, assets, 0)
    with assert_raises(contains="No mesh"):
        _ = create_meshes_from_multi_material_mesh(scene, assets, 1)
    with assert_raises(contains="No mesh"):
        _ = create_meshes_from_multi_material_mesh(scene, assets, -1)
    var bare = BufferGeometry()
    bare.set_index([0, 1, 2])
    scene.meshes[0] = Mesh(assets.geometries.add(bare^), [red], node)
    with assert_raises():
        _ = create_meshes_from_multi_material_mesh(scene, assets, 0)


def test_a_mesh_with_a_list_and_no_groups_splits_into_nothing() raises:
    var assets = Assets()
    var plain = assets.geometries.add(two_triangles())
    var red = assets.materials.add(basic(255, 0, 0))
    var scene = Scene()
    var node = one_node(scene)
    scene.add_mesh(Mesh(plain, [red], node))
    var group = create_meshes_from_multi_material_mesh(scene, assets, 0)
    assert_equal(len(scene.children(group)), 0)
    assert_equal(len(scene.meshes), 1)


# --- The built-in geometries' groups -------------------------------------


def test_a_box_has_three_js_s_six_groups() raises:
    var box = cube(Length(1.0, METER))
    assert_equal(len(box.groups), 6)
    var dressed: List[Int] = [4, 5, 1, 0, 2, 3]
    for face in range(6):
        assert_equal(box.groups[face].start, face * 6)
        assert_equal(box.groups[face].count, 6)
        assert_equal(box.groups[face].material_index.value, dressed[face])


def test_a_cylinder_has_a_side_and_two_caps() raises:
    var tube = cylinder(
        Length(1.0, METER), Length(1.0, METER), Length(2.0, METER), 8
    )
    assert_equal(len(tube.groups), 3)
    # The side: eight cells of two triangles; each cap: eight triangles.
    assert_equal(tube.groups[0].count, 48)
    assert_equal(tube.groups[1].start, 48)
    assert_equal(tube.groups[1].count, 24)
    assert_equal(tube.groups[1].material_index.value, 1)
    assert_equal(tube.groups[2].start, 72)
    assert_equal(tube.groups[2].material_index.value, 2)
    # A cone has no top cap, and an open one no cap at all.
    var point = cone(Length(1.0, METER), Length(2.0, METER), 8)
    assert_equal(len(point.groups), 2)
    assert_equal(point.groups[0].count, 24)
    assert_equal(point.groups[1].material_index.value, 2)
    var pipe = cylinder(
        Length(1.0, METER),
        Length(1.0, METER),
        Length(2.0, METER),
        8,
        open_ended=True,
    )
    assert_equal(len(pipe.groups), 1)
    assert_equal(pipe.groups[0].count, 48)
    var funnel = cylinder(
        Length(1.0, METER), Length(0.0, METER), Length(2.0, METER), 8
    )
    assert_equal(len(funnel.groups), 2)
    assert_equal(funnel.groups[1].material_index.value, 1)


def test_an_extrusion_has_caps_and_walls() raises:
    var outline = Path(Vector2(0, 0))
    outline.line_to(Vector2(1, 0))
    outline.line_to(Vector2(1, 1))
    outline.line_to(Vector2(0, 1))
    outline.line_to(Vector2(0, 0))
    var solid = extrude(Shape(outline^), Length(1.0, METER))
    assert_equal(len(solid.groups), 2)
    # Two caps of two triangles, then four walls of two.
    assert_equal(solid.groups[0].start, 0)
    assert_equal(solid.groups[0].count, 12)
    assert_equal(solid.groups[0].material_index.value, 0)
    assert_equal(solid.groups[1].start, 12)
    assert_equal(solid.groups[1].count, 24)
    assert_equal(solid.groups[1].material_index.value, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
