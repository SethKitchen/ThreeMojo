# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.skeleton`, `objects.skinned_mesh` and the skinning
the renderer does in `prepare`.
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
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from materials.material import Color, DOUBLE_SIDE, Material, MaterialId
from math.matrix4 import Matrix4, scaling, translation
from math.vector3 import Vector3
from objects.skeleton import Bone, Skeleton, bind_skeleton, blend_bones
from objects.skinned_mesh import (
    BONES_PER_VERTEX,
    SKIN_INDEX,
    SKIN_WEIGHT,
    SkinnedMesh,
)
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


def skinned_triangle(
    first: List[Float32], second: List[Float32]
) raises -> BufferGeometry:
    """Return one triangle whose three vertices are carried by the bones
    named in `first` at the weights in `second`.

    Args:
        first: Twelve numbers, four bone indices a vertex.
        second: Twelve numbers, four weights a vertex.

    Returns:
        The geometry.

    Raises:
        Error: If an attribute does not divide evenly.
    """
    var geometry = BufferGeometry()
    var points: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    geometry.set_attribute(String(POSITION), BufferAttribute(points^, 3))
    var facing: List[Float32] = [0, 0, 1, 0, 0, 1, 0, 0, 1]
    geometry.set_attribute(String(NORMAL), BufferAttribute(facing^, 3))
    geometry.set_attribute(String(SKIN_INDEX), BufferAttribute(first.copy(), 4))
    geometry.set_attribute(
        String(SKIN_WEIGHT), BufferAttribute(second.copy(), 4)
    )
    return geometry^


def on_one_bone() raises -> BufferGeometry:
    """Return a triangle carried entirely by bone zero."""
    var first: List[Float32] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var second: List[Float32] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
    return skinned_triangle(first, second)


def between_two_bones() raises -> BufferGeometry:
    """Return a triangle carried half by bone zero and half by bone one."""
    var first: List[Float32] = [0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0]
    var second: List[Float32] = [
        0.5,
        0.5,
        0,
        0,
        0.5,
        0.5,
        0,
        0,
        0.5,
        0.5,
        0,
        0,
    ]
    return skinned_triangle(first, second)


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


# --- Skeleton ---------------------------------------------------------------


def test_a_skeleton_needs_a_bone() raises:
    with assert_raises():
        _ = Skeleton(List[Bone]())


def test_a_skeleton_refuses_a_bind_it_cannot_use() raises:
    var broken = Matrix4()
    broken.elements[0] = Float32(0) / Float32(0)
    with assert_raises():
        _ = Skeleton([Bone(NodeId(0), broken)])
    # Affine means the bottom row is zero, zero, zero, one.
    var sheared = Matrix4()
    sheared.elements[3] = 0.5
    with assert_raises():
        _ = Skeleton([Bone(NodeId(0), sheared)])


def test_a_skeleton_names_its_bones() raises:
    var skeleton = Skeleton(
        [Bone(NodeId(2), Matrix4()), Bone(NodeId(5), Matrix4())]
    )
    assert_equal(skeleton.bone_count(), 2)
    assert_equal(skeleton.node(0), NodeId(2))
    assert_equal(skeleton.node(1), NodeId(5))
    with assert_raises():
        _ = skeleton.node(-1)
    with assert_raises():
        _ = skeleton.node(2)


def test_a_skeleton_copies() raises:
    var skeleton = Skeleton([Bone(NodeId(1), Matrix4())])
    var twin = Skeleton(copy=skeleton)
    assert_equal(twin.bone_count(), 1)
    assert_equal(twin.node(0), NodeId(1))


def test_a_bone_that_has_not_moved_poses_as_the_identity() raises:
    # The property the whole thing rests on: bound where it stands, a bone
    # carries nothing anywhere.
    var skeleton = bind_skeleton([NodeId(0)], [translation(3, 4, 5)])
    var posed = skeleton.pose([translation(3, 4, 5)])
    assert_equal(len(posed), 1)
    var carried = posed[0].transform_point(Vector3(1, 2, 3))
    assert_almost_equal(carried.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(carried.y, Float32(2), atol=TOLERANCE)
    assert_almost_equal(carried.z, Float32(3), atol=TOLERANCE)


def test_a_moved_bone_poses_as_how_far_it_moved() raises:
    var skeleton = bind_skeleton([NodeId(0)], [Matrix4()])
    var posed = skeleton.pose([translation(1, 0, 0)])
    var carried = posed[0].transform_point(Vector3(0, 0, 0))
    assert_almost_equal(carried.x, Float32(1), atol=TOLERANCE)


def test_a_pose_needs_one_matrix_per_bone() raises:
    var skeleton = Skeleton([Bone(NodeId(0), Matrix4())])
    with assert_raises():
        _ = skeleton.pose(List[Matrix4]())


def test_binding_needs_one_matrix_per_node() raises:
    with assert_raises():
        _ = bind_skeleton([NodeId(0), NodeId(1)], [Matrix4()])


def test_a_bone_cannot_be_bound_where_it_has_no_size() raises:
    with assert_raises():
        _ = bind_skeleton([NodeId(0)], [scaling(1, 0, 1)])


# --- blend_bones ------------------------------------------------------------


def test_blending_one_bone_gives_that_bone() raises:
    var palette: List[Matrix4] = [translation(1, 0, 0), translation(0, 5, 0)]
    var bones: List[Int] = [0, 1, 0, 0]
    var weights: List[Float32] = [1, 0, 0, 0]
    var blended = blend_bones(palette, bones, weights)
    var carried = blended.transform_point(Vector3(0, 0, 0))
    assert_almost_equal(carried.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(carried.y, Float32(0), atol=TOLERANCE)


def test_blending_two_bones_lands_between_them() raises:
    var palette: List[Matrix4] = [translation(2, 0, 0), Matrix4()]
    var bones: List[Int] = [0, 1, 0, 0]
    var weights: List[Float32] = [0.5, 0.5, 0, 0]
    var blended = blend_bones(palette, bones, weights)
    var carried = blended.transform_point(Vector3(0, 0, 0))
    assert_almost_equal(carried.x, Float32(1), atol=TOLERANCE)


def test_blending_refuses_what_it_cannot_read() raises:
    var palette: List[Matrix4] = [Matrix4()]
    var bones: List[Int] = [0, 0]
    with assert_raises():
        _ = blend_bones(palette, bones, [Float32(1)])
    # A bone the skeleton does not have, named with weight behind it:
    # past the end, and before the start.
    var stray: List[Int] = [7, 0]
    with assert_raises():
        _ = blend_bones(palette, stray, [Float32(1), Float32(0)])
    var below: List[Int] = [-1, 0]
    with assert_raises():
        _ = blend_bones(palette, below, [Float32(1), Float32(0)])
    # No bones at all, which sums to nothing rather than to one.
    with assert_raises():
        _ = blend_bones(palette, List[Int](), List[Float32]())
    # Weights that do not sum to one, either way.
    with assert_raises():
        _ = blend_bones(palette, bones, [Float32(0.5), Float32(0)])
    with assert_raises():
        _ = blend_bones(palette, bones, [Float32(1), Float32(1)])


# --- SkinnedMesh ------------------------------------------------------------


def a_skeleton() raises -> Skeleton:
    """Return a one-bone skeleton bound at the origin."""
    return Skeleton([Bone(NodeId(1), Matrix4())])


def test_a_skinned_mesh_holds_its_rig() raises:
    var mesh = SkinnedMesh(
        GeometryId(0), MaterialId(0), NodeId(0), a_skeleton()
    )
    assert_equal(mesh.bone_count(), 1)
    # Off by default, unlike a plain mesh: a posed skeleton carries the
    # vertices out of the bound the geometry describes.
    assert_false(mesh.frustum_culled)
    var twin = SkinnedMesh(copy=mesh)
    assert_equal(twin.bone_count(), 1)


def test_a_skinned_mesh_must_name_what_it_draws() raises:
    with assert_raises():
        _ = SkinnedMesh(GeometryId(-1), MaterialId(0), NodeId(0), a_skeleton())
    with assert_raises():
        _ = SkinnedMesh(GeometryId(0), MaterialId(-1), NodeId(0), a_skeleton())
    with assert_raises():
        _ = SkinnedMesh(GeometryId(0), MaterialId(0), NodeId(-1), a_skeleton())


def test_a_bind_matrix_must_be_usable() raises:
    var broken = Matrix4()
    broken.elements[0] = Float32(0) / Float32(0)
    with assert_raises():
        _ = SkinnedMesh(
            GeometryId(0), MaterialId(0), NodeId(0), a_skeleton(), broken
        )
    var sheared = Matrix4()
    sheared.elements[3] = 0.5
    with assert_raises():
        _ = SkinnedMesh(
            GeometryId(0), MaterialId(0), NodeId(0), a_skeleton(), sheared
        )
    with assert_raises():
        _ = SkinnedMesh(
            GeometryId(0),
            MaterialId(0),
            NodeId(0),
            a_skeleton(),
            scaling(1, 0, 1),
        )


# --- the scene --------------------------------------------------------------


def test_a_scene_refuses_a_rig_it_does_not_hold() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    with assert_raises():
        scene.add_skinned_mesh(
            SkinnedMesh(
                GeometryId(0),
                MaterialId(0),
                NodeId(9),
                Skeleton([Bone(NodeId(0), Matrix4())]),
            )
        )
    with assert_raises():
        scene.add_skinned_mesh(
            SkinnedMesh(
                GeometryId(0),
                MaterialId(0),
                NodeId(0),
                Skeleton([Bone(NodeId(9), Matrix4())]),
            )
        )
    # And a bone naming no node at all, which is the other end of the
    # same check.
    with assert_raises():
        scene.add_skinned_mesh(
            SkinnedMesh(
                GeometryId(0),
                MaterialId(0),
                NodeId(0),
                Skeleton([Bone(NodeId(-1), Matrix4())]),
            )
        )


# --- the renderer -----------------------------------------------------------


def rigged(
    mut assets: Assets, var geometry: BufferGeometry, bone_at: Vector3
) raises -> List[RasterVertex]:
    """Return the corners prepared for a skinned triangle whose first bone
    has been carried to `bone_at` since it was bound at the origin.

    Node zero holds the mesh, node one is the first bone and node two is a
    second bone that never moves.
    """
    var scene = Scene()
    _ = scene.add(Object3D())
    _ = scene.add(Object3D())
    _ = scene.add(Object3D())
    scene.update()

    var skeleton = bind_skeleton(
        [NodeId(1), NodeId(2)],
        [scene.world_matrix(NodeId(1)), scene.world_matrix(NodeId(2))],
    )
    var mesh = SkinnedMesh(
        assets.geometries.add(geometry^),
        assets.materials.add(Material(Color(255, 255, 255), side=DOUBLE_SIDE)),
        NodeId(0),
        skeleton^,
    )
    scene.add_skinned_mesh(mesh^)
    scene.node(NodeId(1)).set_position(bone_at.x, bone_at.y, bone_at.z)
    scene.update()

    var renderer = Renderer(WIDTH, HEIGHT)
    return renderer.prepare(scene, assets, a_camera())


def test_a_rig_in_its_bind_pose_moves_nothing() raises:
    var assets = Assets()
    var corners = rigged(assets, on_one_bone(), Vector3(0, 0, 0))
    assert_equal(len(corners), 3)
    assert_almost_equal(corners[0].world.x, Float32(0), atol=TOLERANCE)
    assert_almost_equal(corners[1].world.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(corners[2].world.y, Float32(1), atol=TOLERANCE)


def test_a_moved_bone_carries_the_vertices_it_holds() raises:
    var assets = Assets()
    var corners = rigged(assets, on_one_bone(), Vector3(1, 0, 0))
    assert_almost_equal(corners[0].world.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(corners[1].world.x, Float32(2), atol=TOLERANCE)


def test_a_vertex_between_two_bones_follows_both() raises:
    # Half on a bone that moved a meter and half on one that did not.
    var assets = Assets()
    var corners = rigged(assets, between_two_bones(), Vector3(1, 0, 0))
    assert_almost_equal(corners[0].world.x, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(corners[1].world.x, Float32(1.5), atol=TOLERANCE)


def test_a_turned_bone_turns_the_normals_it_holds() raises:
    var assets = Assets()
    var scene = Scene()
    _ = scene.add(Object3D())
    _ = scene.add(Object3D())
    scene.update()
    var skeleton = bind_skeleton([NodeId(1)], [scene.world_matrix(NodeId(1))])
    var first: List[Float32] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var second: List[Float32] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
    var mesh = SkinnedMesh(
        assets.geometries.add(skinned_triangle(first, second)),
        assets.materials.add(Material(Color(255, 255, 255), side=DOUBLE_SIDE)),
        NodeId(0),
        skeleton^,
    )
    scene.add_skinned_mesh(mesh^)
    # A quarter turn about x carries the +z normal onto -y or +y.
    scene.node(NodeId(1)).set_euler(
        Angle(90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    scene.update()
    var renderer = Renderer(WIDTH, HEIGHT)
    var corners = renderer.prepare(scene, assets, a_camera())
    assert_equal(len(corners), 3)
    assert_almost_equal(corners[0].normal.z, Float32(0), atol=TOLERANCE)
    assert_almost_equal(abs(corners[0].normal.y), Float32(1), atol=TOLERANCE)


def test_a_skinned_geometry_must_carry_its_skin() raises:
    var assets = Assets()
    var bare = BufferGeometry()
    var points: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    bare.set_attribute(String(POSITION), BufferAttribute(points^, 3))
    with assert_raises():
        _ = rigged(assets, bare^, Vector3(0, 0, 0))


def test_a_skin_attribute_is_four_numbers_a_vertex() raises:
    var assets = Assets()
    var geometry = on_one_bone()
    var narrow: List[Float32] = [0, 0, 0, 0, 0, 0]
    geometry.set_attribute(String(SKIN_INDEX), BufferAttribute(narrow^, 2))
    with assert_raises():
        _ = rigged(assets, geometry^, Vector3(0, 0, 0))


def test_a_skin_attribute_must_cover_every_vertex() raises:
    var assets = Assets()
    var geometry = on_one_bone()
    var short: List[Float32] = [0, 0, 0, 0, 0, 0, 0, 0]
    geometry.set_attribute(String(SKIN_INDEX), BufferAttribute(short^, 4))
    with assert_raises():
        _ = rigged(assets, geometry^, Vector3(0, 0, 0))


def test_each_skin_attribute_is_checked_on_its_own() raises:
    # Every one of these checks reads two attributes, and a test that only
    # ever breaks the first leaves the second half of each never taken.
    var assets = Assets()
    var missing_weight = BufferGeometry()
    var points: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    missing_weight.set_attribute(String(POSITION), BufferAttribute(points^, 3))
    var named: List[Float32] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    missing_weight.set_attribute(String(SKIN_INDEX), BufferAttribute(named^, 4))
    with assert_raises():
        _ = rigged(assets, missing_weight^, Vector3(0, 0, 0))

    var narrow_weight = on_one_bone()
    var narrow: List[Float32] = [0, 0, 0, 0, 0, 0]
    narrow_weight.set_attribute(
        String(SKIN_WEIGHT), BufferAttribute(narrow^, 2)
    )
    with assert_raises():
        _ = rigged(assets, narrow_weight^, Vector3(0, 0, 0))

    var short_weight = on_one_bone()
    var short: List[Float32] = [1, 0, 0, 0, 1, 0, 0, 0]
    short_weight.set_attribute(String(SKIN_WEIGHT), BufferAttribute(short^, 4))
    with assert_raises():
        _ = rigged(assets, short_weight^, Vector3(0, 0, 0))


def test_a_skinned_mesh_wears_morph_targets_too() raises:
    # A face is morphed for its expression and skinned for its jaw. The
    # morph moves the vertex first and the bones carry it from there,
    # which is the order three.js's vertex shader uses.
    var assets = Assets()
    var geometry = on_one_bone()
    var moved: List[Float32] = [0, 2, 0, 1, 0, 0, 0, 1, 0]
    geometry.add_morph_target(BufferAttribute(moved^, 3))

    var scene = Scene()
    _ = scene.add(Object3D())
    _ = scene.add(Object3D())
    _ = scene.add(Object3D())
    scene.update()
    var skeleton = bind_skeleton(
        [NodeId(1), NodeId(2)],
        [scene.world_matrix(NodeId(1)), scene.world_matrix(NodeId(2))],
    )
    var mesh = SkinnedMesh(
        assets.geometries.add(geometry^),
        assets.materials.add(Material(Color(255, 255, 255), side=DOUBLE_SIDE)),
        NodeId(0),
        skeleton^,
    )
    # Half the target carries the first vertex a meter up.
    mesh.set_morph_influence(0, 0.5)
    assert_almost_equal(mesh.morph_influence(0), Float32(0.5), atol=TOLERANCE)
    var nowhere = Float32(0) / Float32(0)
    with assert_raises():
        mesh.set_morph_influence(-1, 1)
    with assert_raises():
        mesh.set_morph_influence(MAX_MORPH_TARGETS, 1)
    with assert_raises():
        mesh.set_morph_influence(0, nowhere)
    with assert_raises():
        _ = mesh.morph_influence(-1)
    with assert_raises():
        _ = mesh.morph_influence(MAX_MORPH_TARGETS)
    scene.add_skinned_mesh(mesh^)
    # And the bone carries everything a meter along x from there.
    scene.node(NodeId(1)).set_position(1, 0, 0)
    scene.update()

    var renderer = Renderer(WIDTH, HEIGHT)
    var corners = renderer.prepare(scene, assets, a_camera())
    assert_equal(len(corners), 3)
    assert_almost_equal(corners[0].world.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(corners[0].world.y, Float32(1), atol=TOLERANCE)


def test_a_mesh_bound_somewhere_else_still_comes_back() raises:
    # The bind matrix is where the mesh stood when it was attached. A mesh
    # whose node is turned needs it, because the bones work in world space
    # and the geometry does not. Bound and posed unmoved, every vertex must
    # land exactly where the geometry put it.
    var assets = Assets()
    var scene = Scene()
    var body = Object3D()
    body.set_euler(Angle(0.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE))
    _ = scene.add(body^)
    _ = scene.add(Object3D())
    _ = scene.add(Object3D())
    scene.update()

    var skeleton = bind_skeleton(
        [NodeId(1), NodeId(2)],
        [scene.world_matrix(NodeId(1)), scene.world_matrix(NodeId(2))],
    )
    var mesh = SkinnedMesh(
        assets.geometries.add(on_one_bone()),
        assets.materials.add(Material(Color(255, 255, 255), side=DOUBLE_SIDE)),
        NodeId(0),
        skeleton^,
        scene.world_matrix(NodeId(0)),
    )
    scene.add_skinned_mesh(mesh^)
    scene.update()

    var renderer = Renderer(WIDTH, HEIGHT)
    var corners = renderer.prepare(scene, assets, a_camera())
    assert_equal(len(corners), 3)
    # The node turns the triangle, and the rig leaves it exactly there.
    var turned = scene.world_matrix(NodeId(0)).transform_point(Vector3(1, 0, 0))
    assert_almost_equal(corners[1].world.x, turned.x, atol=TOLERANCE)
    assert_almost_equal(corners[1].world.z, turned.z, atol=TOLERANCE)


def test_four_bones_a_vertex_is_the_shape_of_a_skin() raises:
    assert_equal(BONES_PER_VERTEX, 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
