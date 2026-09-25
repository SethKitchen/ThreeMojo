# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `exporters.obj`, `exporters.stl`, `exporters.ply` and
`exporters.common.world_meshes`.

The key test is the round trip: a scene written in each format and
encoding reads back through this project's own loader to the same
geometry, in world space.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    COLOR,
    NORMAL,
    POSITION,
    UV,
    BufferGeometry,
    MaterialIndex,
)
from core.object3d import NodeId, Object3D
from core.scene import Scene
from exporters.common import WorldMesh, world_meshes
from exporters.obj import export_obj, write_obj
from exporters.ply import color_byte, export_ply, write_ply
from exporters.stl import (
    STL_ASCII,
    STL_BINARY,
    StlFormat,
    export_stl,
    write_stl,
)
from loaders.obj import parse_obj, read_obj
from loaders.ply import (
    PLY_ASCII,
    PLY_BINARY_BIG_ENDIAN,
    PLY_BINARY_LITTLE_ENDIAN,
    PlyFormat,
    parse_ply,
    read_ply,
)
from loaders.stl import parse_stl, read_stl
from materials.material import Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.srgb import srgb_to_linear
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE

comptime TOLERANCE = Float64(1e-5)


def geometry(
    indexed: Bool, normals: Bool, uvs: Bool, colors: Int
) raises -> BufferGeometry:
    """Return a square, two triangles, with the attributes asked for."""
    var shape = BufferGeometry()
    var corners: List[Float32] = [-1, -1, 0, 1, -1, 0, 1, 1, 0.5, -1, 1, 0]
    var turns: List[Float32] = [0, 0, 1, 0, 0, 1, 0, 0.6, 0.8, 1, 0, 0]
    var places: List[Float32] = [0, 0, 1, 0, 1, 1, 0, 1]
    var paints: List[Float32] = [
        1,
        0,
        0,
        0.5,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        1,
        0.2,
        0.4,
        0.6,
        0,
    ]
    var order: List[Int] = [0, 1, 2, 0, 2, 3]
    var positions = List[Float32]()
    var normal = List[Float32]()
    var uv = List[Float32]()
    var color = List[Float32]()
    var vertices: List[Int]
    if indexed:
        vertices = [0, 1, 2, 3]
    else:
        vertices = order.copy()
    for vertex in vertices:
        for lane in range(3):
            positions.append(corners[vertex * 3 + lane])
            normal.append(turns[vertex * 3 + lane])
        for lane in range(2):
            uv.append(places[vertex * 2 + lane])
        for lane in range(colors):
            color.append(paints[vertex * 4 + lane])
    shape.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    if normals:
        shape.set_attribute(String(NORMAL), BufferAttribute(normal^, 3))
    if uvs:
        shape.set_attribute(String(UV), BufferAttribute(uv^, 2))
    if colors > 0:
        shape.set_attribute(String(COLOR), BufferAttribute(color^, colors))
    if indexed:
        shape.set_index(order^)
    return shape^


struct Built(Movable):
    """Four meshes on three nodes, each with a different set of
    attributes, and the scene updated."""

    var scene: Scene
    var assets: Assets

    def __init__(out self) raises:
        self.scene = Scene()
        self.assets = Assets()
        var paint = self.assets.materials.add(Material(Color(200, 200, 200)))
        var first = Object3D()
        first.name = "first"
        first.set_position(1, 2, 3)
        first.set_euler(
            Angle(10.0, DEGREE), Angle(20.0, DEGREE), Angle(30.0, DEGREE)
        )
        first.set_scale(1, 2, 3)
        var one = self.scene.add(first^)
        var second = Object3D()
        second.name = "second part"
        second.set_position(0, 0, -4)
        var two = self.scene.attach(second^, one)
        var third = Object3D()
        third.set_scale(-1, 1, 1)
        var three = self.scene.add(third^)
        var shapes = [
            self.assets.geometries.add(geometry(True, True, True, 3)),
            self.assets.geometries.add(geometry(False, False, False, 0)),
            self.assets.geometries.add(geometry(False, False, True, 4)),
            self.assets.geometries.add(geometry(True, True, False, 0)),
        ]
        self.scene.add_mesh(Mesh(shapes[0], paint, one))
        self.scene.add_mesh(Mesh(shapes[1], paint, two))
        self.scene.add_mesh(Mesh(shapes[2], paint, three))
        self.scene.add_mesh(Mesh(shapes[3], paint, two))
        self.scene.update()


def assert_point(got: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point matches, within tolerance."""
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)
    assert_almost_equal(got.z, z, atol=TOLERANCE)


def corner(mesh: WorldMesh, slot: Int) -> Vector3:
    """Return a triangle corner of a world mesh, by its place in the
    triangle list."""
    var vertex = mesh.triangles[slot]
    return Vector3(
        mesh.positions[vertex * 3],
        mesh.positions[vertex * 3 + 1],
        mesh.positions[vertex * 3 + 2],
    )


def test_a_mesh_is_carried_into_world_space() raises:
    var built = Built()
    var meshes = world_meshes(built.scene, built.assets)
    assert_equal(len(meshes), 4)
    assert_equal(meshes[0].name, "first")
    assert_equal(meshes[1].name, "second part")
    # In `traverse` order: both meshes of the child before the third node.
    assert_equal(meshes[2].name, "second part")
    assert_equal(meshes[3].name, "")
    var matrix = built.scene.world_matrix(built.scene.meshes[0].node)
    var point = matrix.transform_point(Vector3(1, 1, 0.5))
    assert_point(corner(meshes[0], 2), point.x, point.y, point.z)
    # A normal is unit length after a scale that is not uniform.
    var normal = Vector3(
        meshes[0].normals[6], meshes[0].normals[7], meshes[0].normals[8]
    )
    assert_almost_equal(normal.length(), 1, atol=TOLERANCE)
    assert_true(meshes[0].with_normals and meshes[0].with_uvs)
    assert_equal(meshes[0].color_size, 3)
    assert_false(meshes[1].with_normals or meshes[1].with_uvs)
    assert_equal(meshes[3].color_size, 4)
    assert_equal(len(meshes[1].triangles), 6)
    assert_equal(meshes[1].triangles[5], 5)
    # Nothing to carry: no meshes, and a mesh of no vertices.
    assert_equal(len(world_meshes(Scene(), Assets())), 0)


def test_a_stale_scene_or_a_flat_node_is_refused() raises:
    var built = Built()
    built.scene.node(NodeId(0)).set_position(0, 0, 0)
    with assert_raises(contains="update"):
        _ = export_obj(built.scene, built.assets)
    built.scene.node(NodeId(0)).set_scale(0, 1, 1)
    built.scene.update()
    with assert_raises(contains="normal matrix"):
        _ = export_ply(built.scene, built.assets)


def test_an_obj_reads_back_to_the_same_world_geometry() raises:
    var built = Built()
    var text = export_obj(built.scene, built.assets)
    assert_true(text.startswith("o first\nv "))
    assert_true(text.find("f 1/1/1 2/2/2 3/3/3") >= 0)
    var model = parse_obj(text)
    var meshes = world_meshes(built.scene, built.assets)
    assert_equal(model.count(), 4)
    for index in range(4):
        ref mesh = meshes[index]
        ref got = model.objects[index].geometry
        assert_equal(model.objects[index].name, mesh.name)
        assert_equal(got.vertex_count(), len(mesh.triangles))
        assert_equal(got.has_attribute(String(NORMAL)), mesh.with_normals)
        assert_equal(got.has_attribute(String(UV)), mesh.with_uvs)
        ref positions = got.attribute_view(String(POSITION))
        for slot in range(len(mesh.triangles)):
            var expected = corner(mesh, slot)
            var read = positions.vector3(slot)
            assert_equal(read.x, expected.x)
            assert_equal(read.y, expected.y)
            assert_equal(read.z, expected.z)
            var vertex = mesh.triangles[slot]
            if mesh.with_normals:
                var normal = got.attribute_view(String(NORMAL)).vector3(slot)
                assert_equal(normal.x, mesh.normals[vertex * 3])
                assert_equal(normal.z, mesh.normals[vertex * 3 + 2])
            if mesh.with_uvs:
                ref uv = got.attribute_view(String(UV))
                assert_equal(uv.data[slot * 2], mesh.uvs[vertex * 2])
                assert_equal(uv.data[slot * 2 + 1], mesh.uvs[vertex * 2 + 1])
    write_obj("out/export.obj", built.scene, built.assets)
    assert_equal(read_obj("out/export.obj").count(), 4)


def test_an_obj_writes_a_material_list_as_runs_that_read_back() raises:
    var assets = Assets()
    var pair = BufferGeometry()
    pair.set_attribute(
        String(POSITION),
        BufferAttribute(
            [0, 0, 0, 1, 0, 0, 0, 1, 0, 2, 0, 0, 3, 0, 0, 2, 1, 0], 3
        ),
    )
    pair.set_index([0, 1, 2, 3, 4, 5])
    # Written in the groups' order, and a group with no material in the
    # list is left out, as it is not drawn.
    pair.add_group(3, 3, MaterialIndex(0))
    pair.add_group(0, 3, MaterialIndex(1))
    pair.add_group(0, 3, MaterialIndex(5))
    # A group of no whole triangle writes its `usemtl` and no face.
    pair.add_group(0, 2, MaterialIndex(0))
    var shape = assets.geometries.add(pair^)
    var red = assets.materials.add(Material(Color(255, 0, 0)))
    var blue = assets.materials.add(Material(Color(0, 0, 255)))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(Mesh(shape, [red, blue], node))
    var text = export_obj(scene, assets)
    assert_true(text.find("usemtl material0\nf 4 5 6\n") >= 0)
    assert_true(text.find("usemtl material1\nf 1 2 3\n") >= 0)
    var model = parse_obj(text)
    assert_equal(model.count(), 1)
    assert_equal(len(model.objects[0].materials), 2)
    assert_equal(model.objects[0].materials[1], String("material1"))
    assert_equal(len(model.objects[0].geometry.groups), 2)
    # A list whose groups name nothing writes no face.
    scene.meshes[0] = Mesh(shape, [MaterialId(9)], node)
    assets.geometries.geometries[0].clear_groups()
    assert_equal(export_obj(scene, assets).find("f "), -1)


def test_an_obj_name_that_would_not_read_back_is_refused() raises:
    for name in [String("a#b"), String("two  spaces"), String(" lead")]:
        var built = Built()
        built.scene.node(NodeId(0)).name = name
        built.scene.update()
        with assert_raises(contains="OBJ: a name"):
            _ = export_obj(built.scene, built.assets)


def check_stl(format: StlFormat) raises:
    """Write the built scene as STL and read it back."""
    var built = Built()
    var bytes = export_stl(built.scene, built.assets, format)
    var model = parse_stl(bytes)
    var meshes = world_meshes(built.scene, built.assets)
    ref got = model.geometry
    assert_equal(got.vertex_count(), 24)
    assert_false(model.has_colors())
    ref positions = got.attribute_view(String(POSITION))
    ref normals = got.attribute_view(String(NORMAL))
    var at = 0
    for mesh in meshes:
        for face in range(len(mesh.triangles) // 3):
            var a = corner(mesh, face * 3)
            var b = corner(mesh, face * 3 + 1)
            var c = corner(mesh, face * 3 + 2)
            var normal = c - b
            normal.cross(a - b)
            normal.normalize()
            for point in [a, b, c]:
                var read = positions.vector3(at)
                assert_equal(read.x, point.x)
                assert_equal(read.y, point.y)
                assert_equal(read.z, point.z)
                var turned = normals.vector3(at)
                assert_equal(turned.x, normal.x)
                assert_equal(turned.y, normal.y)
                assert_equal(turned.z, normal.z)
                at += 1


def test_an_ascii_stl_reads_back_to_the_same_facets() raises:
    check_stl(STL_ASCII)
    var built = Built()
    var text = String(
        unsafe_from_utf8=export_stl(built.scene, built.assets, STL_ASCII)
    )
    assert_true(text.startswith("solid exported\n\tfacet normal "))
    assert_true(text.endswith("\tendfacet\nendsolid exported\n"))


def test_a_binary_stl_reads_back_to_the_same_facets() raises:
    check_stl(STL_BINARY)
    var built = Built()
    var bytes = export_stl(built.scene, built.assets, STL_BINARY)
    assert_equal(len(bytes), 84 + 8 * 50)
    assert_equal(bytes[0], 0)
    assert_equal(bytes[80], 8)
    write_stl("out/export.stl", built.scene, built.assets, STL_BINARY)
    assert_equal(read_stl("out/export.stl").geometry.vertex_count(), 24)


def test_an_empty_scene_writes_an_stl_with_no_facets() raises:
    var ascii = export_stl(Scene(), Assets())
    assert_equal(
        String(unsafe_from_utf8=ascii), "solid exported\nendsolid exported\n"
    )
    var binary = export_stl(Scene(), Assets(), STL_BINARY)
    assert_equal(len(binary), 84)
    assert_equal(parse_stl(binary).geometry.vertex_count(), 0)


def check_ply(format: PlyFormat) raises:
    """Write the built scene as PLY and read it back."""
    var built = Built()
    var got = parse_ply(export_ply(built.scene, built.assets, format))
    var meshes = world_meshes(built.scene, built.assets)
    assert_equal(got.vertex_count(), 4 + 6 + 6 + 4)
    assert_true(got.has_attribute(String(NORMAL)))
    assert_true(got.has_attribute(String(UV)))
    ref color = got.attribute_view(String(COLOR))
    assert_equal(color.item_size, 3)
    ref positions = got.attribute_view(String(POSITION))
    ref normals = got.attribute_view(String(NORMAL))
    ref uvs = got.attribute_view(String(UV))
    var base = 0
    var slot = 0
    for mesh in meshes:
        for vertex in range(mesh.vertex_count()):
            var at = base + vertex
            for lane in range(3):
                assert_equal(
                    positions.data[at * 3 + lane],
                    mesh.positions[vertex * 3 + lane],
                )
                var normal = mesh.normals[
                    vertex * 3 + lane
                ] if mesh.with_normals else 0
                assert_equal(normals.data[at * 3 + lane], normal)
                var paint = (
                    mesh.colors[
                        vertex * mesh.color_size + lane
                    ] if mesh.color_size
                    > 0 else 1
                )
                var clamped = min(max(paint, Float32(0)), Float32(1))
                assert_almost_equal(
                    color.data[at * 3 + lane], clamped, atol=0.01
                )
            for lane in range(2):
                var place = mesh.uvs[vertex * 2 + lane] if mesh.with_uvs else 0
                assert_equal(uvs.data[at * 2 + lane], place)
        for entry in mesh.triangles:
            assert_equal(got.index[slot], base + entry)
            slot += 1
        base += mesh.vertex_count()


def test_an_ascii_ply_reads_back_to_the_same_vertices() raises:
    check_ply(PLY_ASCII)
    var built = Built()
    var text = String(unsafe_from_utf8=export_ply(built.scene, built.assets))
    assert_true(text.startswith("ply\nformat ascii 1.0\nelement vertex 20\n"))
    assert_true(text.find("element face 8\n") >= 0)
    assert_true(text.find("\n3 0 1 2\n") >= 0)


def test_a_binary_ply_reads_back_in_either_byte_order() raises:
    check_ply(PLY_BINARY_LITTLE_ENDIAN)
    check_ply(PLY_BINARY_BIG_ENDIAN)
    var built = Built()
    write_ply(
        "out/export.ply", built.scene, built.assets, PLY_BINARY_BIG_ENDIAN
    )
    assert_equal(read_ply("out/export.ply").vertex_count(), 20)


def test_a_ply_writes_only_the_properties_some_mesh_has() raises:
    var assets = Assets()
    var paint = assets.materials.add(Material(Color(1, 2, 3)))
    var bare = assets.geometries.add(geometry(True, False, False, 0))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(bare, paint, node))
    scene.update()
    var text = String(unsafe_from_utf8=export_ply(scene, assets))
    assert_equal(text.find("nx"), -1)
    assert_equal(text.find("property float s"), -1)
    assert_equal(text.find("red"), -1)
    var got = parse_ply(List[UInt8](text.as_bytes()))
    assert_false(got.has_attribute(String(NORMAL)))
    assert_equal(got.vertex_count(), 4)
    # An empty scene has an empty vertex element and an empty face element.
    var empty = parse_ply(export_ply(Scene(), Assets()))
    assert_equal(empty.vertex_count(), 0)


def test_a_color_is_rounded_down_as_three_js_does() raises:
    # three.js's `Math.floor( color * 255 )`, clamped here first. White
    # encodes a hair below one, so it is 254, as in three.js's files.
    assert_equal(color_byte(-1), 0)
    assert_equal(color_byte(2), color_byte(1))
    assert_equal(color_byte(1), 254)
    # A byte decoded as `read_ply` decodes it writes back as itself or one
    # below, as it does in three.js.
    for byte in range(256):
        var again = color_byte(srgb_to_linear(Float32(byte) / 255))
        assert_true(again == byte or again == byte - 1)


def test_a_mesh_of_no_vertices_writes_nothing_for_it() raises:
    var assets = Assets()
    var paint = assets.materials.add(Material(Color(1, 2, 3)))
    var hollow = BufferGeometry()
    hollow.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    hollow.set_attribute(String(NORMAL), BufferAttribute(List[Float32](), 3))
    hollow.set_attribute(String(UV), BufferAttribute(List[Float32](), 2))
    hollow.set_attribute(String(COLOR), BufferAttribute(List[Float32](), 3))
    var shape = assets.geometries.add(hollow^)
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(shape, paint, node))
    scene.update()
    assert_equal(export_obj(scene, assets), "o \n")
    assert_equal(export_obj(Scene(), Assets()), "")
    assert_equal(len(export_stl(scene, assets, STL_BINARY)), 84)
    assert_equal(parse_ply(export_ply(scene, assets)).vertex_count(), 0)


def test_a_format_that_is_none_of_the_named_is_refused() raises:
    assert_true(STL_BINARY.is_valid())
    with assert_raises(contains="STL: a format"):
        _ = export_stl(Scene(), Assets(), StlFormat(5))
    with assert_raises(contains="PLY: a format"):
        _ = export_ply(Scene(), Assets(), PlyFormat(9))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
