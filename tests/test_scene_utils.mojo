# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.scene_utils`.

The expected numbers are what three.js 0.180's `SceneUtils` gives under
node, for the same scene built the same way."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    MAX_MORPH_TARGETS,
    NORMAL,
    POSITION,
)
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from core.scene_utils import (
    compute_mesh_morphed_attributes,
    compute_skinned_morphed_attributes,
    create_meshes_from_instanced_mesh,
    create_multi_material_object,
    node_vertices,
    reduce_vertices,
    sort_instanced_mesh,
    visible_nodes,
)
from materials.material import Color, Material, MaterialId
from math.matrix4 import Matrix4, translation
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from objects.line import Line
from objects.mesh import Mesh
from objects.points import Points
from objects.skeleton import Bone, Skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from render.framebuffer import Color as PixelColor
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE


def near(actual: Float32, expected: Float64, tolerance: Float64 = 1e-5) raises:
    """Check a float against an expected double."""
    if abs(Float64(actual) - expected) > tolerance:
        raise Error(
            "expected " + String(expected) + " but got " + String(actual)
        )


def near_vector(actual: Vector3, expected: List[Float64]) raises:
    """Check a vector against three expected doubles."""
    near(actual.x, expected[0])
    near(actual.y, expected[1])
    near(actual.z, expected[2])


def matrix_of(elements: List[Float64]) -> Matrix4:
    """Return a matrix from its sixteen elements, column after column."""
    var m = Matrix4()
    for index in range(16):
        m.elements[index] = Float32(elements[index])
    return m


def swarm_matrices() -> List[Matrix4]:
    """Return the four instance matrices of the reference."""
    return [
        matrix_of(
            [
                1,
                0,
                0,
                0,
                0,
                0.8775825618903728,
                0.479425538604203,
                0,
                0,
                -0.479425538604203,
                0.8775825618903728,
                0,
                1,
                2,
                3,
                1,
            ]
        ),
        matrix_of(
            [
                1.0470112312690896,
                0.4948079185090459,
                -1.6306233793789202,
                0,
                -0.066836464833063,
                0.48445621085532237,
                0.10409162661963806,
                0,
                2.5244129544236893,
                0,
                1.6209069176044193,
                0,
                -1,
                0,
                2,
                1,
            ]
        ),
        matrix_of([-2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
        matrix_of([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 4, 5, 6, 1]),
    ]


def triangle() raises -> BufferGeometry:
    """Return the reference's triangle."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    return geometry^


def swarm(mut scene: Scene, mut assets: Assets) raises -> Int:
    """Add the reference's instanced mesh and return its place."""
    var geometry = triangle()
    geometry.set_attribute(
        "offset",
        BufferAttribute(
            [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3], 3, mesh_per_attribute=1
        ),
    )
    var wide = List[Float32]()
    for row in range(4):
        for column in range(5):
            wide.append(Float32(row * 10 + column))
    geometry.set_attribute(
        "wide", BufferAttribute(wide^, 5, mesh_per_attribute=1)
    )
    var id = assets.geometries.add(geometry^)
    var node = Object3D()
    node.set_position(1, 0, 0)
    node.name = "swarm"
    var at = scene.add(node^)
    var mesh = InstancedMesh(id, MaterialId(0), at, 4)
    var matrices = swarm_matrices()
    for index in range(4):
        mesh.set_matrix_at(index, matrices[index])
        mesh.set_color_at(
            index,
            PixelColor(UInt8(index * 64), 128, UInt8(255 - index * 64)),
        )
    scene.add_instanced_mesh(mesh^)
    return len(scene.instanced_meshes) - 1


struct Decomposed:
    """The three parts `Matrix4.decompose` fills."""

    var position: Vector3
    var quaternion: Quaternion
    var scale: Vector3

    def __init__(out self):
        """Start from nothing moved."""
        self.position = Vector3(0, 0, 0)
        self.quaternion = Quaternion.identity()
        self.scale = Vector3(1, 1, 1)


def test_decomposing_matches_three() raises:
    var matrices = swarm_matrices()
    var parts = Decomposed()
    matrices[1].decompose(parts.position, parts.quaternion, parts.scale)
    near_vector(parts.position, [-1, 0, 2])
    near_vector(
        parts.scale, [1.9999999839955864, 0.5000000005787846, 2.999999946288968]
    )
    near(parts.quaternion.x, 0.059772252361763166)
    near(parts.quaternion.y, 0.475684890731549)
    near(parts.quaternion.z, 0.10941237131055824)
    near(parts.quaternion.w, 0.870735375968894)
    var flipped = Decomposed()
    matrices[2].decompose(flipped.position, flipped.quaternion, flipped.scale)
    near_vector(flipped.scale, [-2, 1, 1])
    near(flipped.quaternion.w, 1)


def test_instances_become_meshes_as_in_three() raises:
    var scene = Scene()
    var assets = Assets()
    var index = swarm(scene, assets)
    var group = create_meshes_from_instanced_mesh(scene, index)
    var node = scene.get(group)
    assert_true(node.parent == NO_PARENT)
    assert_equal(node.name, "swarm")
    near_vector(node.position, [1, 0, 0])
    var children = scene.children(group)
    assert_equal(len(children), 4)
    assert_equal(len(scene.meshes), 4)
    var first = scene.get(children[0])
    near_vector(first.position, [1, 2, 3])
    near(first.quaternion.x, 0.2474039666402358)
    near(first.quaternion.w, 0.9689124198247626)
    near_vector(first.scale, [1, 0.9999999948352141, 0.9999999948352141])
    near_vector(scene.get(children[3]).position, [4, 5, 6])
    assert_true(scene.meshes[2].node == children[2])
    assert_true(scene.meshes[2].geometry == scene.instanced_meshes[0].geometry)
    with assert_raises():
        _ = create_meshes_from_instanced_mesh(scene, 1)
    with assert_raises():
        _ = create_meshes_from_instanced_mesh(scene, -1)


def test_sorting_instances_matches_three() raises:
    var scene = Scene()
    var assets = Assets()
    var index = swarm(scene, assets)
    sort_instanced_mesh(scene, assets, index, [3, 1, 3, 0])
    ref geometry = assets.geometries.get(GeometryId(0))
    var offsets = geometry.attribute_view("offset").packed()
    var expected: List[Float32] = [3, 3, 3, 1, 1, 1, 0, 0, 0, 2, 2, 2]
    for i in range(12):
        assert_equal(offsets[i], expected[i])
    var wide = geometry.attribute_view("wide").packed()
    var moved: List[Float32] = [
        30,
        31,
        32,
        33,
        4,
        10,
        11,
        12,
        13,
        14,
        0,
        1,
        2,
        3,
        24,
        20,
        21,
        22,
        23,
        34,
    ]
    for i in range(20):
        assert_equal(wide[i], moved[i])
    ref mesh = scene.instanced_meshes[index]
    var z: List[Float32] = [6, 2, 3, 0]
    for i in range(4):
        assert_equal(mesh.matrices[i].elements[14], z[i])
    assert_equal(mesh.colors[0].r, 192)
    assert_equal(mesh.colors[1].r, 64)
    assert_equal(mesh.colors[2].r, 0)
    assert_equal(mesh.colors[3].r, 128)


def test_sorting_needs_a_key_for_each_instance_and_its_geometry() raises:
    var scene = Scene()
    var assets = Assets()
    var index = swarm(scene, assets)
    with assert_raises():
        sort_instanced_mesh(scene, assets, index, [1, 2])
    with assert_raises():
        sort_instanced_mesh(scene, assets, 1, [1, 2, 3, 4])
    with assert_raises():
        sort_instanced_mesh(scene, assets, -1, [1, 2, 3, 4])
    var other = Scene()
    _ = other.add(Object3D())
    other.add_instanced_mesh(
        InstancedMesh(GeometryId(5), MaterialId(0), NodeId(0), 1)
    )
    with assert_raises():
        sort_instanced_mesh(other, assets, 0, [1])
    # Without colors, only the matrices move.
    var plain = Scene()
    _ = plain.add(Object3D())
    var bare = InstancedMesh(GeometryId(0), MaterialId(0), NodeId(0), 2)
    bare.set_matrix_at(0, translation(0, 0, 1))
    plain.add_instanced_mesh(bare^)
    sort_instanced_mesh(plain, assets, 0, [2, 1])
    assert_equal(plain.instanced_meshes[0].matrices[1].elements[14], 1)
    assert_equal(len(plain.instanced_meshes[0].colors), 0)


def test_a_multi_material_object_draws_one_geometry_in_each() raises:
    var scene = Scene()
    var group = create_multi_material_object(
        scene, GeometryId(3), [MaterialId(0), MaterialId(1)]
    )
    assert_equal(len(scene.children(group)), 2)
    assert_equal(len(scene.meshes), 2)
    assert_true(scene.meshes[1].material == MaterialId(1))
    assert_true(scene.meshes[0].geometry == scene.meshes[1].geometry)
    var none = create_multi_material_object(scene, GeometryId(3), [])
    assert_equal(len(scene.children(none)), 0)


def reduction_scene(mut scene: Scene, mut assets: Assets) raises -> NodeId:
    """Build the reference's scene for `reduceVertices` and return its
    root."""
    var morphing = triangle()
    morphing.add_morph_target(BufferAttribute([0, 0, 1, 1, 0, 1, 0, 1, 1], 3))
    var tri = assets.geometries.add(morphing^)
    var segment = BufferGeometry()
    segment.set_attribute(
        String(POSITION), BufferAttribute([2, 2, 2, 3, 3, 3], 3)
    )
    var line_geometry = assets.geometries.add(segment^)
    var dot = BufferGeometry()
    dot.set_attribute(String(POSITION), BufferAttribute([5, 0, 0], 3))
    var point_geometry = assets.geometries.add(dot^)
    var plain = assets.geometries.add(triangle())
    var root_node = Object3D()
    root_node.set_position(1, 2, 3)
    root_node.rotate_z(Angle(90, DEGREE))
    var root = scene.add(root_node^)
    var mesh_node = Object3D()
    mesh_node.set_position(0, 0, 1)
    var at = scene.attach(mesh_node^, root)
    var mesh = Mesh(tri, MaterialId(0), at)
    mesh.set_morph_influence(0, 0.5)
    scene.add_mesh(mesh)
    var hidden_node = Object3D()
    hidden_node.visible = False
    var hidden = scene.attach(hidden_node^, root)
    scene.add_mesh(Mesh(tri, MaterialId(0), hidden))
    var under = scene.attach(Object3D(), hidden)
    scene.add_mesh(Mesh(tri, MaterialId(0), under))
    var line = scene.attach(Object3D(), root)
    scene.add_line(Line(line_geometry, MaterialId(0), line))
    var points_node = Object3D()
    points_node.set_position(0, 1, 0)
    var points = scene.attach(points_node^, line)
    scene.add_points(Points(point_geometry, MaterialId(0), points))
    var inst_node = Object3D()
    inst_node.set_position(0, 0, -2)
    var inst = scene.attach(inst_node^, root)
    scene.add_instanced_mesh(InstancedMesh(plain, MaterialId(0), inst, 2))
    scene.update()
    return root


def collect(var so_far: List[Vector3], vertex: Vector3) -> List[Vector3]:
    """Return the vertices so far with one more."""
    so_far.append(vertex)
    return so_far^


def lowest(var so_far: Vector3, vertex: Vector3) -> Vector3:
    """Return the least of each coordinate."""
    return Vector3(
        min(so_far.x, vertex.x),
        min(so_far.y, vertex.y),
        min(so_far.z, vertex.z),
    )


def test_reducing_vertices_matches_three() raises:
    var scene = Scene()
    var assets = Assets()
    var root = reduction_scene(scene, assets)
    var vertices = reduce_vertices[collect](
        scene, assets, root, List[Vector3]()
    )
    var expected: List[List[Float64]] = [
        [1, 2, 4.5],
        [1, 3, 4.5],
        [0, 2, 4.5],
        [-1, 4, 5],
        [-2, 5, 6],
        [0, 7, 3],
        [1, 2, 1],
        [1, 3, 1],
        [0, 2, 1],
    ]
    assert_equal(len(vertices), len(expected))
    for index in range(len(expected)):
        near_vector(vertices[index], expected[index])
    var least = reduce_vertices[lowest](
        scene, assets, root, Vector3(1000, 1000, 1000)
    )
    near_vector(least, [-2, 2, 1])
    var hidden_root = Object3D()
    hidden_root.visible = False
    var lone = scene.add(hidden_root^)
    scene.update()
    assert_equal(len(visible_nodes(scene, lone)), 0)
    var none = reduce_vertices[collect](scene, assets, lone, List[Vector3]())
    assert_equal(len(none), 0)


def test_a_skinned_mesh_gives_its_carried_vertices() raises:
    var scene = Scene()
    var assets = Assets()
    var geometry = triangle()
    geometry.set_attribute(
        String(NORMAL), BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1], 3)
    )
    geometry.set_attribute(
        String(SKIN_INDEX), BufferAttribute(List[Float32](length=12, fill=0), 4)
    )
    geometry.set_attribute(
        String(SKIN_WEIGHT),
        BufferAttribute([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0], 4),
    )
    var id = assets.geometries.add(geometry^)
    var holder = scene.add(Object3D())
    var bone_node = Object3D()
    bone_node.set_position(2, 0, 0)
    var bone = scene.add(bone_node^)
    scene.add_skinned_mesh(
        SkinnedMesh(
            id, MaterialId(0), holder, Skeleton([Bone(bone, Matrix4())])
        )
    )
    scene.update()
    # The bone, bound at the origin, has moved two meters along x.
    var vertices = node_vertices(scene, assets, holder)
    assert_equal(len(vertices), 3)
    near_vector(vertices[1], [3, 0, 0])
    var worn = compute_skinned_morphed_attributes(scene, assets, 0)
    near(worn.morphed_position.component(2, 0), 2)
    near(worn.morphed_position.component(2, 1), 1)


def test_empty_meshes_and_geometries_pass_through() raises:
    var scene = Scene()
    var assets = Assets()
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    empty.set_attribute(String(NORMAL), BufferAttribute(List[Float32](), 3))
    empty.set_attribute(String(SKIN_INDEX), BufferAttribute(List[Float32](), 4))
    empty.set_attribute(
        String(SKIN_WEIGHT), BufferAttribute(List[Float32](), 4)
    )
    var hollow = assets.geometries.add(empty^)
    var nothing = BufferGeometry()
    nothing.set_attribute(
        "offset", BufferAttribute(List[Float32](), 3, mesh_per_attribute=1)
    )
    var bare = assets.geometries.add(nothing^)
    var holder = scene.add(Object3D())
    var bone = scene.add(Object3D())
    scene.add_instanced_mesh(InstancedMesh(bare, MaterialId(0), holder, 0))
    var group = create_meshes_from_instanced_mesh(scene, 0)
    assert_equal(len(scene.children(group)), 0)
    sort_instanced_mesh(scene, assets, 0, [])
    var blank = assets.geometries.add(BufferGeometry())
    scene.add_instanced_mesh(InstancedMesh(blank, MaterialId(0), holder, 1))
    sort_instanced_mesh(scene, assets, 1, [0])
    scene.add_line(Line(hollow, MaterialId(0), holder))
    scene.add_skinned_mesh(
        SkinnedMesh(
            hollow, MaterialId(0), holder, Skeleton([Bone(bone, Matrix4())])
        )
    )
    scene.instanced_meshes.clear()
    scene.update()
    assert_equal(len(node_vertices(scene, assets, holder)), 0)
    assert_equal(len(node_vertices(scene, assets, bone)), 0)


def test_a_mesh_s_morphed_attributes_use_its_weights() raises:
    var assets = Assets()
    var geometry = triangle()
    geometry.set_attribute(
        String(NORMAL), BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1], 3)
    )
    geometry.add_morph_target(BufferAttribute([0, 0, 2, 1, 0, 2, 0, 1, 2], 3))
    var id = assets.geometries.add(geometry^)
    var mesh = Mesh(id, MaterialId(0), NodeId(0))
    mesh.set_morph_influence(0, 0.25)
    var worn = compute_mesh_morphed_attributes(assets, mesh)
    near(worn.morphed_position.component(1, 2), 0.5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
