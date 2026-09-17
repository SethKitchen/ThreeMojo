# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.instanced_mesh`, `objects.lod`, and the renderer's
drawing of them.

The claim each render test makes is the same: a scene drawn with
instances, a batch or an LOD comes out pixel for pixel as the same scene
drawn with plain meshes on plain nodes. The opaque draws make that order
independent, since the depth test settles every pixel, so the comparison
is exact.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from geometries.sphere import sphere
from materials.material import BASIC, BLEND, MaterialId, Material
from math.matrix4 import Matrix4, scaling, translation
from math.vector3 import Vector3
from objects.instanced_mesh import BatchedMesh, InstancedMesh
from objects.lod import Lod
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime WIDTH = 24
comptime HEIGHT = 18
comptime TOLERANCE = Float64(1e-6)


def a_camera(z: Float32 = 6) raises -> PerspectiveCamera:
    """Return a camera on the z axis looking at the origin.

    Args:
        z: How far up z it sits.

    Returns:
        The camera.

    Raises:
        Error: If its parameters are invalid, which they are not.
    """
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, z), Vector3(0, 0, 0))
    return camera^


def a_scene() raises -> Scene:
    """Return an updated scene with one node at the origin and no lights."""
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    return scene^


def assert_same_image(got: Framebuffer, wanted: Framebuffer) raises:
    """Assert two images agree on every channel of every pixel.

    Args:
        got: The image to check.
        wanted: The image it must match.

    Raises:
        Error: If any pixel differs.
    """
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var one = got.get_pixel(x, y)
            var two = wanted.get_pixel(x, y)
            assert_equal(one.r, two.r)
            assert_equal(one.g, two.g)
            assert_equal(one.b, two.b)
            assert_equal(one.a, two.a)


def count_drawn(image: Framebuffer, background: Color) raises -> Int:
    """Return how many pixels are not the background."""
    var drawn = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if (
                pixel.r != background.r
                or pixel.g != background.g
                or pixel.b != background.b
            ):
                drawn += 1
    return drawn


def with_meshes(
    mut assets: Assets,
    geometries: List[GeometryId],
    material: MaterialId,
    offsets: List[Vector3],
) raises -> Scene:
    """Return a scene drawing each geometry as a plain mesh on its own
    node at the matching offset.

    Args:
        assets: The stores the ids name.
        geometries: One geometry per mesh.
        material: The material for all of them.
        offsets: Where each mesh's node sits.

    Returns:
        The updated scene.

    Raises:
        Error: If the scene is invalid, which it is not.
    """
    var scene = Scene()
    for index in range(len(geometries)):
        var node = Object3D()
        node.set_position(offsets[index].x, offsets[index].y, offsets[index].z)
        scene.add_mesh(Mesh(geometries[index], material, scene.add(node^)))
    scene.update()
    return scene^


# --- the objects -------------------------------------------------------------


def test_an_instanced_mesh_starts_every_instance_at_the_identity() raises:
    var group = InstancedMesh(GeometryId(0), MaterialId(0), NodeId(0), 3)
    assert_equal(group.count(), 3)
    assert_true(group.matrix_at(2).is_affine())
    assert_almost_equal(group.matrix_at(2).elements[12], Float32(0))
    group.set_matrix_at(1, translation(1, 2, 3))
    assert_almost_equal(group.matrix_at(1).elements[14], Float32(3))
    assert_almost_equal(group.matrix_at(0).elements[14], Float32(0))
    assert_true(group.frustum_culled)
    assert_equal(
        InstancedMesh(GeometryId(0), MaterialId(0), NodeId(0), 0).count(), 0
    )


def test_an_instanced_mesh_refuses_bad_ids_a_bad_count_and_a_bad_index() raises:
    with assert_raises():
        _ = InstancedMesh(GeometryId(-1), MaterialId(0), NodeId(0), 1)
    with assert_raises():
        _ = InstancedMesh(GeometryId(0), MaterialId(-1), NodeId(0), 1)
    with assert_raises():
        _ = InstancedMesh(GeometryId(0), MaterialId(0), NodeId(-1), 1)
    with assert_raises():
        _ = InstancedMesh(GeometryId(0), MaterialId(0), NodeId(0), -1)
    var group = InstancedMesh(GeometryId(0), MaterialId(0), NodeId(0), 2)
    with assert_raises():
        _ = group.matrix_at(2)
    with assert_raises():
        _ = group.matrix_at(-1)
    with assert_raises():
        group.set_matrix_at(2, Matrix4())


def test_a_batched_mesh_names_a_geometry_per_instance() raises:
    var batch = BatchedMesh(MaterialId(0), NodeId(0))
    assert_equal(batch.count(), 0)
    assert_equal(batch.add_instance(GeometryId(3)), 0)
    assert_equal(batch.add_instance(GeometryId(4), translation(1, 0, 0)), 1)
    assert_equal(batch.count(), 2)
    assert_equal(batch.geometry_at(1), GeometryId(4))
    assert_almost_equal(batch.matrix_at(1).elements[12], Float32(1))
    assert_almost_equal(batch.matrix_at(0).elements[12], Float32(0))
    batch.set_geometry_at(0, GeometryId(5))
    batch.set_matrix_at(0, translation(0, 2, 0))
    assert_equal(batch.geometry_at(0), GeometryId(5))
    assert_almost_equal(batch.matrix_at(0).elements[13], Float32(2))


def test_a_batched_mesh_refuses_bad_ids_and_a_bad_index() raises:
    with assert_raises():
        _ = BatchedMesh(MaterialId(-1), NodeId(0))
    with assert_raises():
        _ = BatchedMesh(MaterialId(0), NodeId(-1))
    var batch = BatchedMesh(MaterialId(0), NodeId(0))
    with assert_raises():
        _ = batch.add_instance(GeometryId(-1))
    _ = batch.add_instance(GeometryId(0))
    with assert_raises():
        batch.set_geometry_at(0, GeometryId(-1))
    with assert_raises():
        batch.set_geometry_at(1, GeometryId(0))
    with assert_raises():
        _ = batch.geometry_at(-1)
    with assert_raises():
        _ = batch.matrix_at(1)
    with assert_raises():
        batch.set_matrix_at(1, Matrix4())


def test_an_lod_keeps_its_levels_in_order_of_distance() raises:
    var lod = Lod(NodeId(0))
    assert_equal(lod.count(), 0)
    assert_equal(lod.level_for(Length(3.0, METER)), -1)
    lod.add_level(GeometryId(2), MaterialId(0), Length(10.0, METER))
    lod.add_level(GeometryId(0), MaterialId(0))
    lod.add_level(GeometryId(1), MaterialId(0), Length(5.0, METER))
    # A level at a distance another has goes after it.
    lod.add_level(GeometryId(3), MaterialId(0), Length(5.0, METER))
    assert_equal(lod.count(), 4)
    assert_equal(lod.level_at(0).geometry, GeometryId(0))
    assert_equal(lod.level_at(1).geometry, GeometryId(1))
    assert_equal(lod.level_at(2).geometry, GeometryId(3))
    assert_equal(lod.level_at(3).geometry, GeometryId(2))
    assert_almost_equal(lod.level_at(3).distance.value, Float32(10))
    # The last level whose distance has been reached shows, and the first
    # below the second's distance.
    assert_equal(lod.level_for(Length(0.0, METER)), 0)
    assert_equal(lod.level_for(Length(4.9, METER)), 0)
    assert_equal(lod.level_for(Length(5.0, METER)), 2)
    assert_equal(lod.level_for(Length(7.0, METER)), 2)
    assert_equal(lod.level_for(Length(50.0, METER)), 3)


def test_an_lod_refuses_bad_ids_a_negative_distance_and_a_bad_level() raises:
    with assert_raises():
        _ = Lod(NodeId(-1))
    var lod = Lod(NodeId(0))
    with assert_raises():
        lod.add_level(GeometryId(-1), MaterialId(0))
    with assert_raises():
        lod.add_level(GeometryId(0), MaterialId(-1))
    with assert_raises():
        lod.add_level(GeometryId(0), MaterialId(0), Length(-1.0, METER))
    with assert_raises():
        _ = lod.level_at(0)
    lod.add_level(GeometryId(0), MaterialId(0))
    with assert_raises():
        _ = lod.level_at(1)
    with assert_raises():
        _ = lod.level_at(-1)


def test_the_scene_takes_each_once_its_node_exists() raises:
    var scene = Scene()
    with assert_raises():
        scene.add_instanced_mesh(
            InstancedMesh(GeometryId(0), MaterialId(0), NodeId(0), 1)
        )
    with assert_raises():
        scene.add_batched_mesh(BatchedMesh(MaterialId(0), NodeId(0)))
    with assert_raises():
        scene.add_lod(Lod(NodeId(0)))
    _ = scene.add(Object3D())
    scene.add_instanced_mesh(
        InstancedMesh(GeometryId(0), MaterialId(0), NodeId(0), 1)
    )
    scene.add_batched_mesh(BatchedMesh(MaterialId(0), NodeId(0)))
    scene.add_lod(Lod(NodeId(0)))
    assert_equal(len(scene.instanced_meshes), 1)
    assert_equal(len(scene.batched_meshes), 1)
    assert_equal(len(scene.lods), 1)


# --- drawing -----------------------------------------------------------------


def test_an_instanced_mesh_draws_as_its_meshes_would() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(220, 120, 40)))
    var offsets: List[Vector3] = [
        Vector3(-1.5, 0, 0),
        Vector3(0, 0.3, -1),
        Vector3(1.5, -0.2, 0.5),
    ]
    var group = InstancedMesh(box, paint, NodeId(0), 3)
    for index in range(3):
        group.set_matrix_at(
            index,
            translation(offsets[index].x, offsets[index].y, offsets[index].z),
        )
    var scene = a_scene()
    scene.add_instanced_mesh(group^)
    var instanced = renderer.render(scene, assets, a_camera())
    var plain = with_meshes(assets, [box, box, box], paint, offsets)
    var separate = renderer.render(plain, assets, a_camera())
    assert_true(
        count_drawn(instanced, renderer.background) > 30, "nothing drawn"
    )
    assert_same_image(instanced, separate)


def test_moving_the_node_moves_every_instance() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(220, 120, 40)))
    var group = InstancedMesh(box, paint, NodeId(0), 2)
    group.set_matrix_at(0, translation(-1, 0, 0))
    group.set_matrix_at(1, translation(1, 0, 0))
    var scene = a_scene()
    scene.node(NodeId(0)).set_position(0, 1, 0)
    scene.update()
    scene.add_instanced_mesh(group^)
    var instanced = renderer.render(scene, assets, a_camera())
    var plain = with_meshes(
        assets, [box, box], paint, [Vector3(-1, 1, 0), Vector3(1, 1, 0)]
    )
    assert_same_image(instanced, renderer.render(plain, assets, a_camera()))


def test_a_batched_mesh_draws_each_instances_own_geometry() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ball = assets.geometries.add(sphere(Length(0.6, METER), 12, 8))
    var paint = assets.materials.add(Material(Color(90, 190, 255)))
    var batch = BatchedMesh(paint, NodeId(0))
    _ = batch.add_instance(box, translation(-1.5, 0, 0))
    _ = batch.add_instance(ball, translation(1.5, 0, 0))
    var scene = a_scene()
    scene.add_batched_mesh(batch^)
    var batched = renderer.render(scene, assets, a_camera())
    var plain = with_meshes(
        assets,
        [box, ball],
        paint,
        [Vector3(-1.5, 0, 0), Vector3(1.5, 0, 0)],
    )
    assert_true(count_drawn(batched, renderer.background) > 30, "nothing drawn")
    assert_same_image(batched, renderer.render(plain, assets, a_camera()))


def test_an_instance_out_of_view_is_culled_on_its_own() raises:
    # One instance in front of the camera and one behind it: the group
    # prepares as many triangles as the one cube alone, and with culling
    # off the same, since the clipper removes the other.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(220, 120, 40)))
    var scene = a_scene()
    scene.add_mesh(Mesh(box, paint, NodeId(0)))
    var alone = len(renderer.prepare(scene, assets, a_camera()))
    assert_true(alone > 0, "the cube prepared nothing")
    for culled in [True, False]:
        var group = InstancedMesh(
            box, paint, NodeId(0), 2, frustum_culled=culled
        )
        group.set_matrix_at(1, translation(0, 0, 20))
        var pair = a_scene()
        pair.add_instanced_mesh(group^)
        assert_equal(len(renderer.prepare(pair, assets, a_camera())), alone)
    # A group with every instance behind the camera draws nothing at all.
    var hidden = InstancedMesh(box, paint, NodeId(0), 2)
    hidden.set_matrix_at(0, translation(0, 0, 20))
    hidden.set_matrix_at(1, translation(3, 0, 20))
    var none = a_scene()
    none.add_instanced_mesh(hidden^)
    assert_equal(len(renderer.prepare(none, assets, a_camera())), 0)


def test_a_group_on_another_layer_is_not_drawn() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(220, 120, 40)))
    var scene = a_scene()
    scene.node(NodeId(0)).layers.set(1)
    scene.update()
    scene.add_instanced_mesh(InstancedMesh(box, paint, NodeId(0), 1))
    var batch = BatchedMesh(paint, NodeId(0))
    _ = batch.add_instance(box)
    scene.add_batched_mesh(batch^)
    var lod = Lod(NodeId(0))
    lod.add_level(box, paint)
    scene.add_lod(lod^)
    var image = renderer.render(scene, assets, a_camera())
    assert_equal(count_drawn(image, renderer.background), 0)


def test_a_mirrored_instance_still_faces_the_camera() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(220, 120, 40)))
    var group = InstancedMesh(box, paint, NodeId(0), 1)
    group.set_matrix_at(0, scaling(-1, 1, 1))
    var scene = a_scene()
    scene.add_instanced_mesh(group^)
    var instanced = renderer.render(scene, assets, a_camera(3))
    var plain = a_scene()
    plain.node(NodeId(0)).set_scale(-1, 1, 1)
    plain.update()
    plain.add_mesh(Mesh(box, paint, NodeId(0)))
    assert_true(count_drawn(instanced, renderer.background) > 10, "culled away")
    assert_same_image(instanced, renderer.render(plain, assets, a_camera(3)))


def test_a_translucent_group_is_drawn_after_the_opaque_ones() raises:
    # A see-through pane in front of a solid cube: the pane's pixels show
    # the cube through it, so they are neither the pane's color nor the
    # cube's alone.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var sheet = assets.geometries.add(
        plane(Length(3.0, METER), Length(3.0, METER))
    )
    # Unlit, so the colors are as authored: the scene has no lights.
    var solid = assets.materials.add(Material(Color(220, 120, 40), kind=BASIC))
    var glass = assets.materials.add(
        Material(Color(40, 120, 220), opacity=0.5, blending=BLEND, kind=BASIC)
    )
    var scene = a_scene()
    var pane = InstancedMesh(sheet, glass, NodeId(0), 1)
    pane.set_matrix_at(0, translation(0, 0, 1.5))
    scene.add_instanced_mesh(pane^)
    scene.add_mesh(Mesh(box, solid, NodeId(0)))
    var image = renderer.render(scene, assets, a_camera())
    var middle = image.get_pixel(WIDTH // 2, HEIGHT // 2)
    var opaque = a_scene()
    opaque.add_mesh(Mesh(box, solid, NodeId(0)))
    var bare = renderer.render(opaque, assets, a_camera()).get_pixel(
        WIDTH // 2, HEIGHT // 2
    )
    assert_true(middle.r < bare.r, "the pane did not tint the cube")
    assert_true(middle.r > 40, "the cube did not show through the pane")


def test_an_lod_shows_the_level_its_distance_picks() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 12, 8))
    var paint = assets.materials.add(Material(Color(220, 120, 40)))
    var lod = Lod(NodeId(0))
    lod.add_level(box, paint)
    lod.add_level(ball, paint, Length(5.0, METER))
    var scene = a_scene()
    scene.add_lod(lod^)
    var near_box = a_scene()
    near_box.add_mesh(Mesh(box, paint, NodeId(0)))
    var far_ball = a_scene()
    far_ball.add_mesh(Mesh(ball, paint, NodeId(0)))
    # Three meters out, the cube; eight meters out, the sphere.
    assert_same_image(
        renderer.render(scene, assets, a_camera(3)),
        renderer.render(near_box, assets, a_camera(3)),
    )
    assert_same_image(
        renderer.render(scene, assets, a_camera(8)),
        renderer.render(far_ball, assets, a_camera(8)),
    )
    assert_true(
        count_drawn(
            renderer.render(scene, assets, a_camera(8)), renderer.background
        )
        > 0,
        "the far level drew nothing",
    )


def test_an_lod_with_no_levels_draws_nothing() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var scene = a_scene()
    scene.add_lod(Lod(NodeId(0)))
    assert_equal(len(renderer.prepare(scene, assets, a_camera())), 0)


def test_a_group_naming_an_asset_that_is_not_there_is_refused() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(220, 120, 40)))
    var missing_shape = a_scene()
    missing_shape.add_instanced_mesh(
        InstancedMesh(GeometryId(7), paint, NodeId(0), 1)
    )
    with assert_raises():
        _ = renderer.render(missing_shape, assets, a_camera())
    var missing_paint = a_scene()
    var batch = BatchedMesh(MaterialId(7), NodeId(0))
    _ = batch.add_instance(box)
    missing_paint.add_batched_mesh(batch^)
    with assert_raises():
        _ = renderer.render(missing_paint, assets, a_camera())
    var missing_level = a_scene()
    var lod = Lod(NodeId(0))
    lod.add_level(box, MaterialId(7))
    missing_level.add_lod(lod^)
    with assert_raises():
        _ = renderer.render(missing_level, assets, a_camera())


def test_a_group_with_no_instances_draws_nothing() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(220, 120, 40)))
    var scene = a_scene()
    scene.add_instanced_mesh(InstancedMesh(box, paint, NodeId(0), 0))
    scene.add_batched_mesh(BatchedMesh(paint, NodeId(0)))
    assert_equal(len(renderer.prepare(scene, assets, a_camera())), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
