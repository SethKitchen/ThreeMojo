# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.object_bounds`, `cameras.frustum_array` and the camera
helpers `project_point` and `unproject_point`.

The camera numbers come from three.js 0.180, run in node with the same
camera.
"""

from cameras.array_camera import ArrayCamera
from cameras.camera import project_point, unproject_point
from cameras.frustum_array import FrustumArray
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.object_bounds import (
    box_from_object,
    expand_by_object,
    intersects_object,
    intersects_sprite,
)
from core.scene import Scene
from materials.material import MaterialId
from math.bounds import Box3, Sphere
from math.frustum import Frustum
from math.matrix4 import Matrix4, translation
from math.projection import orthographic
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.instanced_mesh import BatchedMesh, InstancedMesh
from objects.line import Line
from objects.line_segments2 import LineSegments2
from objects.lod import Lod
from objects.mesh import Mesh
from objects.points import Points
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from objects.sprite import Sprite
from render.rect import Rect
from std.math import sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(2e-5)
comptime HALF_ROOT_TWO = 0.7071067811865476


def assert_vector(got: Vector3, x: Float64, y: Float64, z: Float64) raises:
    """Assert a vector matches three components, within tolerance.

    Args:
        got: The vector to check.
        x: Expected x.
        y: Expected y.
        z: Expected z.

    Raises:
        Error: If a component differs.
    """
    assert_almost_equal(Float64(got.x), x, atol=TOLERANCE)
    assert_almost_equal(Float64(got.y), y, atol=TOLERANCE)
    assert_almost_equal(Float64(got.z), z, atol=TOLERANCE)


def fan() raises -> BufferGeometry:
    """Return three points: (1, 0, 0), (0, 1, 0) and (-1, 0, 0)."""
    var geometry = BufferGeometry()
    var points: List[Float32] = [1, 0, 0, 0, 1, 0, -1, 0, 0]
    geometry.set_attribute(String(POSITION), BufferAttribute(points^, 3))
    return geometry^


def turned_scene(mut assets: Assets) raises -> Scene:
    """Return a scene with a root and, under it, a node moved ten meters
    along x and turned 45 degrees about z.

    Args:
        assets: Receives the fan as geometry zero.

    Returns:
        The scene, not yet updated.
    """
    _ = assets.geometries.add(fan())
    var scene = Scene()
    var root = scene.add(Object3D())
    var child = Object3D()
    child.parent = root
    child.set_position(10, 0, 0)
    child.rotate_z(Angle(45.0, DEGREE))
    _ = scene.add(child^)
    return scene^


def test_box_of_a_turned_mesh() raises:
    var assets = Assets()
    var scene = turned_scene(assets)
    scene.add_mesh(Mesh(GeometryId(0), MaterialId(0), NodeId(1)))
    scene.update()
    # The fan's box is x -1 to 1, y 0 to 1. Its turned corners reach
    # root two either way.
    var loose = box_from_object(scene, assets, NodeId(0))
    assert_vector(loose.min, 10 - 2 * HALF_ROOT_TWO, -HALF_ROOT_TWO, 0)
    assert_vector(loose.max, 10 + HALF_ROOT_TWO, 2 * HALF_ROOT_TWO, 0)
    # Each vertex on its own reaches only half root two.
    var tight = box_from_object(scene, assets, NodeId(0), precise=True)
    assert_vector(tight.min, 10 - HALF_ROOT_TWO, -HALF_ROOT_TWO, 0)
    assert_vector(tight.max, 10 + HALF_ROOT_TWO, HALF_ROOT_TWO, 0)


def test_morph_targets_move_a_precise_mesh() raises:
    var assets = Assets()
    var geometry = fan()
    var moved: List[Float32] = [1, 0, 2, 0, 1, 2, -1, 0, 2]
    geometry.add_morph_target(BufferAttribute(moved^, 3))
    _ = assets.geometries.add(geometry^)
    var scene = Scene()
    _ = scene.add(Object3D())
    var mesh = Mesh(GeometryId(0), MaterialId(0), NodeId(0))
    mesh.morph_influences[0] = 0.5
    scene.add_mesh(mesh)
    scene.update()
    var tight = box_from_object(scene, assets, NodeId(0), precise=True)
    assert_vector(tight.max, 1, 1, 1)
    # The loose box is the geometry's, which leaves the targets out.
    assert_vector(box_from_object(scene, assets, NodeId(0)).max, 1, 1, 0)


def test_a_subtree_leaves_out_what_is_beside_it() raises:
    var assets = Assets()
    var scene = turned_scene(assets)
    var aside = scene.add(Object3D())
    scene.node(aside).set_position(-50, 0, 0)
    scene.add_mesh(Mesh(GeometryId(0), MaterialId(0), aside))
    scene.add_line(Line(GeometryId(0), MaterialId(0), aside))
    scene.add_points(Points(GeometryId(0), MaterialId(0), aside))
    scene.add_wide_line(LineSegments2(GeometryId(0), MaterialId(0), aside))
    var lod = Lod(aside)
    lod.add_level(GeometryId(0), MaterialId(0))
    scene.add_lod(lod^)
    var instanced = InstancedMesh(GeometryId(0), MaterialId(0), aside, 1)
    scene.add_instanced_mesh(instanced^)
    var batched = BatchedMesh(MaterialId(0), aside)
    _ = batched.add_instance(GeometryId(0))
    scene.add_batched_mesh(batched^)
    scene.add_sprite(Sprite(MaterialId(0), aside))
    scene.update()
    assert_true(box_from_object(scene, assets, NodeId(1)).is_empty())
    var beside = box_from_object(scene, assets, aside)
    assert_almost_equal(Float64(beside.min.x), -51, atol=TOLERANCE)


def test_every_kind_of_content_adds_its_box() raises:
    var assets = Assets()
    _ = assets.geometries.add(fan())
    var scene = Scene()
    var root = scene.add(Object3D())
    scene.update()
    scene.add_line(Line(GeometryId(0), MaterialId(0), root))
    assert_vector(box_from_object(scene, assets, root).max, 1, 1, 0)
    scene.lines.clear()
    scene.add_points(Points(GeometryId(0), MaterialId(0), root))
    assert_vector(
        box_from_object(scene, assets, root, precise=True).min, -1, 0, 0
    )
    scene.points.clear()
    scene.add_wide_line(LineSegments2(GeometryId(0), MaterialId(0), root))
    assert_vector(box_from_object(scene, assets, root).min, -1, 0, 0)
    scene.wide_lines.clear()
    var lod = Lod(root)
    lod.add_level(GeometryId(0), MaterialId(0))
    scene.add_lod(lod^)
    scene.add_lod(Lod(root))
    assert_vector(box_from_object(scene, assets, root).max, 1, 1, 0)
    scene.lods.clear()
    var group = InstancedMesh(GeometryId(0), MaterialId(0), root, 2)
    group.set_matrix_at(1, translation(0, 0, 5))
    scene.add_instanced_mesh(group^)
    scene.add_instanced_mesh(
        InstancedMesh(GeometryId(0), MaterialId(0), root, 0)
    )
    assert_vector(box_from_object(scene, assets, root).max, 1, 1, 5)
    scene.instanced_meshes.clear()
    var batch = BatchedMesh(MaterialId(0), root)
    _ = batch.add_instance(GeometryId(0), translation(0, -3, 0))
    scene.add_batched_mesh(batch^)
    scene.add_batched_mesh(BatchedMesh(MaterialId(0), root))
    assert_vector(box_from_object(scene, assets, root).min, -1, -3, 0)
    scene.batched_meshes.clear()
    scene.add_sprite(Sprite(MaterialId(0), root))
    var square = box_from_object(scene, assets, root)
    assert_vector(square.min, -0.5, -0.5, 0)
    assert_vector(square.max, 0.5, 0.5, 0)


def test_expand_by_object_keeps_what_the_box_held() raises:
    var assets = Assets()
    var scene = turned_scene(assets)
    scene.add_mesh(Mesh(GeometryId(0), MaterialId(0), NodeId(1)))
    scene.update()
    var box = Box3(Vector3(-5, -5, -5), Vector3(-4, -4, -4))
    expand_by_object(box, scene, assets, NodeId(1))
    assert_vector(box.min, -5, -5, -5)
    assert_almost_equal(Float64(box.max.x), 10 + HALF_ROOT_TWO, atol=TOLERANCE)


def test_a_stale_scene_is_refused() raises:
    var assets = Assets()
    var scene = turned_scene(assets)
    scene.add_mesh(Mesh(GeometryId(0), MaterialId(0), NodeId(1)))
    with assert_raises():
        _ = box_from_object(scene, assets, NodeId(0))
    scene.update()
    with assert_raises():
        _ = box_from_object(scene, assets, NodeId(9))


def rigged(mut assets: Assets) raises -> Scene:
    """Return a scene holding the fan on one bone moved five meters along
    x.

    Args:
        assets: Receives the fan, with skin attributes.

    Returns:
        The scene, updated.
    """
    var geometry = fan()
    var bones: List[Float32] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    var weights: List[Float32] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
    geometry.set_attribute(String(SKIN_INDEX), BufferAttribute(bones^, 4))
    geometry.set_attribute(String(SKIN_WEIGHT), BufferAttribute(weights^, 4))
    var shape = assets.geometries.add(geometry^)
    var scene = Scene()
    var body = scene.add(Object3D())
    var bone = scene.add(Object3D())
    scene.update()
    var skeleton = bind_skeleton([bone], [Matrix4()])
    scene.add_skinned_mesh(SkinnedMesh(shape, MaterialId(0), body, skeleton^))
    scene.node(bone).set_position(5, 0, 0)
    scene.update()
    return scene^


def test_a_skinned_mesh_is_bounded_where_its_bones_put_it() raises:
    var assets = Assets()
    var scene = rigged(assets)
    var loose = box_from_object(scene, assets, NodeId(0))
    assert_vector(loose.min, 4, 0, 0)
    assert_vector(loose.max, 6, 1, 0)
    var tight = box_from_object(scene, assets, NodeId(0), precise=True)
    assert_vector(tight.min, 4, 0, 0)
    # The bone is not under the body, so the body's subtree still holds the
    # mesh while the bone's does not.
    assert_true(box_from_object(scene, assets, NodeId(1)).is_empty())


def test_content_with_no_vertices_adds_nothing() raises:
    var assets = Assets()
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute(List[Float32](), 3)
    )
    geometry.set_attribute(
        String(SKIN_INDEX), BufferAttribute(List[Float32](), 4)
    )
    geometry.set_attribute(
        String(SKIN_WEIGHT), BufferAttribute(List[Float32](), 4)
    )
    var shape = assets.geometries.add(geometry^)
    var scene = Scene()
    var body = scene.add(Object3D())
    var bone = scene.add(Object3D())
    scene.update()
    var skeleton = bind_skeleton([bone], [Matrix4()])
    scene.add_skinned_mesh(SkinnedMesh(shape, MaterialId(0), body, skeleton^))
    scene.add_points(Points(shape, MaterialId(0), body))
    assert_true(box_from_object(scene, assets, body).is_empty())
    assert_true(box_from_object(scene, assets, body, precise=True).is_empty())


def a_frustum() raises -> Frustum:
    """Return an orthographic view of x and y from -2 to 2, looking down
    -z from the origin."""
    return Frustum.from_projection_matrix(orthographic(-2, 2, 2, -2, 0.1, 100))


def test_intersects_object() raises:
    var assets = Assets()
    _ = assets.geometries.add(fan())
    var scene = Scene()
    var seen = scene.add(Object3D())
    scene.node(seen).set_position(0, 0, -5)
    var hidden = scene.add(Object3D())
    scene.node(hidden).set_position(10, 0, -5)
    scene.update()
    var frustum = a_frustum()
    assert_true(
        intersects_object(
            frustum, scene, assets, Mesh(GeometryId(0), MaterialId(0), seen)
        )
    )
    assert_false(
        intersects_object(
            frustum, scene, assets, Mesh(GeometryId(0), MaterialId(0), hidden)
        )
    )
    assert_true(
        intersects_object(
            frustum, scene, assets, Line(GeometryId(0), MaterialId(0), seen)
        )
    )
    assert_false(
        intersects_object(
            frustum, scene, assets, Points(GeometryId(0), MaterialId(0), hidden)
        )
    )
    var group = InstancedMesh(GeometryId(0), MaterialId(0), hidden, 2)
    group.set_matrix_at(1, translation(-10, 0, 0))
    assert_true(intersects_object(frustum, scene, assets, group))
    var none = InstancedMesh(GeometryId(0), MaterialId(0), seen, 0)
    assert_false(intersects_object(frustum, scene, assets, none))


def test_intersects_sprite() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.node(node).set_position(2.8, 0, -5)
    scene.update()
    var frustum = a_frustum()
    # Centered, the sphere reaches root two over two: short of the edge.
    assert_false(intersects_sprite(frustum, scene, Sprite(MaterialId(0), node)))
    # A center at a corner grows the sphere by as much again.
    var cornered = Sprite(MaterialId(0), node, center=Vector2(0, 0))
    assert_true(intersects_sprite(frustum, scene, cornered))


def a_camera() raises -> PerspectiveCamera:
    """Return the camera the node run used: 50 degrees, aspect 1.5, at
    (1, 2, 5) looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.5, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(1, 2, 5), Vector3(0, 0, 0))
    return camera^


def test_project_and_unproject_with_a_camera() raises:
    var scene = Scene()
    var ndc = project_point(Vector3(1, -2, 3), a_camera(), scene)
    assert_almost_equal(Float64(ndc.x), 0.17063481147304393, atol=1e-4)
    assert_almost_equal(Float64(ndc.y), -1.962671242127977, atol=1e-4)
    assert_almost_equal(Float64(ndc.z), 0.9410830210760575, atol=1e-4)
    var world = unproject_point(Vector3(0.2, -0.3, 0.5), a_camera(), scene)
    assert_almost_equal(Float64(world.x), 0.9858900870251195, atol=1e-4)
    assert_almost_equal(Float64(world.y), 1.8024402739283774, atol=1e-4)
    assert_almost_equal(Float64(world.z), 4.644978429350512, atol=1e-4)


def test_frustum_array() raises:
    var assets = Assets()
    _ = assets.geometries.add(fan())
    var scene = Scene()
    var front = scene.add(Object3D())
    var behind = scene.add(Object3D())
    scene.node(behind).set_position(0, 0, 30)
    scene.update()
    var cameras = ArrayCamera()
    var views = FrustumArray()
    var mesh = Mesh(GeometryId(0), MaterialId(0), front)
    # No cameras see nothing.
    assert_false(views.intersects_object(cameras, scene, assets, mesh))
    assert_false(views.contains_point(cameras, scene, Vector3(0, 0, 0)))
    assert_false(
        views.intersects_object(
            cameras, scene, assets, Line(GeometryId(0), MaterialId(0), front)
        )
    )
    assert_false(
        views.intersects_object(
            cameras, scene, assets, Points(GeometryId(0), MaterialId(0), front)
        )
    )
    assert_false(
        views.intersects_object(
            cameras,
            scene,
            assets,
            InstancedMesh(GeometryId(0), MaterialId(0), front, 1),
        )
    )
    assert_false(
        views.intersects_sprite(cameras, scene, Sprite(MaterialId(0), front))
    )
    assert_false(
        views.intersects_sphere(cameras, scene, Sphere(Vector3(0, 0, 0), 1))
    )
    assert_false(
        views.intersects_box(
            cameras, scene, Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))
        )
    )
    var away = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    away.place(Vector3(0, 0, 10), Vector3(0, 0, 20))
    cameras.add(away, Rect(0, 0, 8, 8))
    cameras.add(a_camera(), Rect(8, 0, 8, 8))
    assert_true(views.intersects_object(cameras, scene, assets, mesh))
    var far_mesh = Mesh(GeometryId(0), MaterialId(0), behind)
    assert_true(views.intersects_object(cameras, scene, assets, far_mesh))
    assert_true(
        views.intersects_object(
            cameras, scene, assets, Line(GeometryId(0), MaterialId(0), front)
        )
    )
    assert_true(
        views.intersects_object(
            cameras, scene, assets, Points(GeometryId(0), MaterialId(0), front)
        )
    )
    assert_true(
        views.intersects_object(
            cameras,
            scene,
            assets,
            InstancedMesh(GeometryId(0), MaterialId(0), front, 1),
        )
    )
    assert_true(
        views.intersects_sprite(cameras, scene, Sprite(MaterialId(0), front))
    )
    assert_true(
        views.intersects_sphere(cameras, scene, Sphere(Vector3(0, 0, 0), 1))
    )
    assert_true(
        views.intersects_box(
            cameras, scene, Box3(Vector3(-1, -1, -1), Vector3(1, 1, 1))
        )
    )
    assert_true(views.contains_point(cameras, scene, Vector3(0, 0, 0)))
    # Beside both views.
    var aside = Vector3(500, 0, 0)
    assert_false(views.contains_point(cameras, scene, aside))
    assert_false(views.intersects_sphere(cameras, scene, Sphere(aside, 1)))
    assert_false(
        views.intersects_box(
            cameras, scene, Box3(aside, aside + Vector3(1, 1, 1))
        )
    )
    var out = scene.add(Object3D())
    scene.node(out).set_position(500, 0, 0)
    scene.update()
    assert_false(
        views.intersects_object(
            cameras, scene, assets, Mesh(GeometryId(0), MaterialId(0), out)
        )
    )
    assert_false(
        views.intersects_object(
            cameras, scene, assets, Line(GeometryId(0), MaterialId(0), out)
        )
    )
    assert_false(
        views.intersects_object(
            cameras, scene, assets, Points(GeometryId(0), MaterialId(0), out)
        )
    )
    assert_false(
        views.intersects_object(
            cameras,
            scene,
            assets,
            InstancedMesh(GeometryId(0), MaterialId(0), out, 1),
        )
    )
    assert_false(
        views.intersects_sprite(cameras, scene, Sprite(MaterialId(0), out))
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
