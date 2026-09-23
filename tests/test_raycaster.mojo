# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.raycaster`.

A unit cube at the origin, looked at down -z from five meters away, is the
scene most of these use: a ray a little off its middle enters the front
face at z = 0.5 and leaves the back at z = -0.5, so every distance and
normal can be written down before the code runs. A little off, because a
ray through the exact middle runs along the edge the two triangles of a
face share, and both report it -- as they do in three.js.
"""

from cameras.orthographic_camera import centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.raycaster import (
    BATCHED_HIT,
    INSTANCED_HIT,
    LOD_HIT,
    WIDE_LINE_HIT,
    MESH_HIT,
    HitKind,
    Raycaster,
)
from core.scene import Scene
from geometries.box import cube
from materials.material import BACK_SIDE, DOUBLE_SIDE, Material
from math.matrix4 import translation
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.instanced_mesh import BatchedMesh, InstancedMesh
from objects.lod import Lod
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-4)


def assert_point(got: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point matches the given components, within tolerance."""
    assert_almost_equal(got.x, x, atol=TOLERANCE)
    assert_almost_equal(got.y, y, atol=TOLERANCE)
    assert_almost_equal(got.z, z, atol=TOLERANCE)


def down_z(near: Length = Length(0.0, METER)) raises -> Raycaster:
    """Return a raycaster from five meters up z, pointing down it, a
    little off the axis so it crosses no shared edge.

    Args:
        near: How far from the origin its hits start to count.

    Returns:
        The raycaster.

    Raises:
        Error: If the range is invalid, which it is not.
    """
    return Raycaster(Vector3(0.1, 0.2, 5), Vector3(0, 0, -1), near)


def a_cube_scene(mut assets: Assets, material: Material) raises -> Scene:
    """Return a scene with one unit cube at the origin, drawn with
    `material`, and the assets it names added to `assets`.

    Args:
        assets: The stores to add the cube and the material to.
        material: What the cube is made of.

    Returns:
        The updated scene, with the cube as mesh zero on node zero.

    Raises:
        Error: If the scene is invalid, which it is not.
    """
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(
        Mesh(
            assets.geometries.add(cube(Length(1.0, METER))),
            assets.materials.add(material),
            node,
        )
    )
    return scene^


def square_camera() raises -> PerspectiveCamera:
    """Return a 90-degree square camera 5 m up z, looking at the origin.

    Returns:
        The camera.

    Raises:
        Error: If its parameters are invalid, which they are not.
    """
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(1.0, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


# --- the raycaster itself ----------------------------------------------------


def test_a_raycaster_counts_from_its_origin_without_end_by_default() raises:
    var caster = Raycaster(Vector3(1, 2, 3), Vector3(0, 0, -2))
    assert_point(caster.ray.origin, 1, 2, 3)
    assert_point(caster.ray.direction, 0, 0, -1)
    assert_equal(caster.near.value, Float32(0))
    assert_true(caster.far.value > 1e30)
    assert_true(caster.layers.is_enabled(0))
    caster.set(Vector3(0, 0, 0), Vector3(3, 0, 0))
    assert_point(caster.ray.origin, 0, 0, 0)
    assert_point(caster.ray.direction, 1, 0, 0)


def test_a_raycaster_refuses_a_bad_range_or_no_direction() raises:
    with assert_raises():
        _ = Raycaster(Vector3(0, 0, 0), Vector3(0, 0, 0))
    with assert_raises():
        _ = Raycaster(Vector3(0, 0, 0), Vector3(0, 0, -1), Length(-1.0, METER))
    with assert_raises():
        _ = Raycaster(
            Vector3(0, 0, 0),
            Vector3(0, 0, -1),
            Length(2.0, METER),
            Length(1.0, METER),
        )
    # A range that is not a number passed both tests above and then
    # filtered nothing, silently.
    with assert_raises():
        _ = Raycaster(
            Vector3(0, 0, 0),
            Vector3(0, 0, -1),
            Length(nan[DType.float32](), METER),
        )
    with assert_raises():
        _ = Raycaster(
            Vector3(0, 0, 0),
            Vector3(0, 0, -1),
            Length(0.0, METER),
            Length(nan[DType.float32](), METER),
        )
    var caster = down_z()
    with assert_raises():
        caster.set(Vector3(0, 0, 0), Vector3(0, 0, 0))


# --- from a camera -----------------------------------------------------------


def test_a_perspective_ray_leaves_the_eye_toward_the_point() raises:
    var scene = Scene()
    var caster = down_z()
    # The middle of the image: straight down the view.
    caster.set_from_camera(Vector2(0, 0), square_camera(), scene)
    assert_point(caster.ray.origin, 0, 0, 5)
    assert_point(caster.ray.direction, 0, 0, -1)
    # The right edge: at 90 degrees the edge is as far out as it is deep.
    caster.set_from_camera(Vector2(1, 0), square_camera(), scene)
    assert_point(caster.ray.origin, 0, 0, 5)
    assert_point(caster.ray.direction, 0.70710677, 0, -0.70710677)
    # The top edge, the same way up.
    caster.set_from_camera(Vector2(0, 1), square_camera(), scene)
    assert_point(caster.ray.direction, 0, 0.70710677, -0.70710677)


def test_an_orthographic_ray_starts_on_the_cameras_plane() raises:
    var scene = Scene()
    var flat = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    flat.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var caster = down_z()
    caster.set_from_camera(Vector2(0.5, 0), flat, scene)
    assert_point(caster.ray.origin, 0.5, 0, 5)
    assert_point(caster.ray.direction, 0, 0, -1)
    # Every ray is parallel: the bottom edge starts lower, and goes the
    # same way.
    caster.set_from_camera(Vector2(0, -1), flat, scene)
    assert_point(caster.ray.origin, 0, -1, 5)
    assert_point(caster.ray.direction, 0, 0, -1)


def test_a_pixel_ray_passes_through_what_the_camera_projected_there() raises:
    var scene = Scene()
    var camera = square_camera()
    var target = Vector3(1.5, -0.75, 2)
    var pixel = camera.project(target, 200, 100)
    var caster = down_z()
    caster.set_from_pixel(pixel.x, pixel.y, 200, 100, camera, scene)
    assert_almost_equal(
        caster.ray.distance_to_point(target), Float32(0), atol=TOLERANCE
    )
    # The center of the middle pixel is the middle of the image.
    caster.set_from_pixel(100, 50, 200, 100, camera, scene)
    assert_point(caster.ray.direction, 0, 0, -1)


def test_a_pixel_ray_refuses_an_image_with_no_size() raises:
    var scene = Scene()
    var caster = down_z()
    with assert_raises():
        caster.set_from_pixel(0, 0, 0, 100, square_camera(), scene)
    with assert_raises():
        caster.set_from_pixel(0, 0, 100, -1, square_camera(), scene)


def test_a_camera_on_a_stale_scene_cannot_aim_a_ray() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    var camera = square_camera()
    camera.attach(node)
    var caster = down_z()
    with assert_raises():
        caster.set_from_camera(Vector2(0, 0), camera, scene)
    scene.update()
    caster.set_from_camera(Vector2(0, 0), camera, scene)
    assert_point(caster.ray.origin, 0, 0, 0)


def test_a_ray_from_a_distant_camera_keeps_its_direction() raises:
    # Ten kilometers out with a near plane a millimeter deep: one inverse
    # of the projection times the view mixed the two and landed this ray
    # a meter and a half wide at ten meters. Built in camera space, the
    # direction is the same as from the origin, to a part in ten thousand.
    var scene = Scene()
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(0.001, METER), Length(1000.0, METER)
    )
    camera.place(Vector3(0, 0, 10000), Vector3(0, 0, 9000))
    var caster = down_z()
    caster.set_from_camera(Vector2(0.5, 0), camera, scene)
    assert_point(caster.ray.origin, 0, 0, 10000)
    assert_point(caster.ray.direction, 0.4472136, 0, -0.8944272)
    # Ten meters down the view, the ray is five meters across.
    assert_point(caster.ray.at(Float32(10) / 0.8944272), 5, 0, 9990)
    camera.place(Vector3(0, 0, 0), Vector3(0, 0, -1))
    caster.set_from_camera(Vector2(0.5, 0), camera, scene)
    assert_point(caster.ray.direction, 0.4472136, 0, -0.8944272)
    # The orthographic ray too: its origin is on the camera's plane, out
    # where the camera is.
    var flat = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    flat.place(Vector3(0, 0, 10000), Vector3(0, 0, 9000))
    caster.set_from_camera(Vector2(0.5, 0), flat, scene)
    assert_point(caster.ray.origin, 0.5, 0, 10000)
    assert_point(caster.ray.direction, 0, 0, -1)


# --- one mesh ----------------------------------------------------------------


def test_a_front_side_cube_is_hit_once_on_its_near_face() raises:
    var assets = Assets()
    var scene = a_cube_scene(assets, Material(Color(255, 255, 255)))
    var hits = down_z().intersect_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_almost_equal(hits[0].distance, Float32(4.5), atol=TOLERANCE)
    assert_point(hits[0].point, 0.1, 0.2, 0.5)
    assert_point(hits[0].normal, 0, 0, 1)
    assert_equal(hits[0].index, 0)
    assert_equal(hits[0].mesh.node, NodeId(0))
    assert_true(hits[0].triangle >= 0 and hits[0].triangle < 12)


def test_a_double_sided_cube_is_hit_front_then_back() raises:
    var assets = Assets()
    var scene = a_cube_scene(
        assets, Material(Color(255, 255, 255), side=DOUBLE_SIDE)
    )
    var hits = down_z().intersect_mesh(scene, assets, 0)
    assert_equal(len(hits), 2)
    assert_almost_equal(hits[0].distance, Float32(4.5), atol=TOLERANCE)
    assert_point(hits[0].normal, 0, 0, 1)
    assert_almost_equal(hits[1].distance, Float32(5.5), atol=TOLERANCE)
    assert_point(hits[1].point, 0.1, 0.2, -0.5)
    # The face as wound, whichever side the ray came from.
    assert_point(hits[1].normal, 0, 0, -1)


def test_a_back_side_cube_is_hit_only_on_its_far_face() raises:
    var assets = Assets()
    var scene = a_cube_scene(
        assets, Material(Color(255, 255, 255), side=BACK_SIDE)
    )
    var hits = down_z().intersect_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_almost_equal(hits[0].distance, Float32(5.5), atol=TOLERANCE)
    assert_point(hits[0].normal, 0, 0, -1)


def test_the_range_drops_hits_too_near_or_too_far() raises:
    var assets = Assets()
    var scene = a_cube_scene(
        assets, Material(Color(255, 255, 255), side=DOUBLE_SIDE)
    )
    var from_five = down_z(Length(5.0, METER)).intersect_mesh(scene, assets, 0)
    assert_equal(len(from_five), 1)
    assert_almost_equal(from_five[0].distance, Float32(5.5), atol=TOLERANCE)
    var to_five = Raycaster(
        Vector3(0.1, 0.2, 5),
        Vector3(0, 0, -1),
        Length(0.0, METER),
        Length(5.0, METER),
    ).intersect_mesh(scene, assets, 0)
    assert_equal(len(to_five), 1)
    assert_almost_equal(to_five[0].distance, Float32(4.5), atol=TOLERANCE)


def test_a_mesh_the_ray_misses_costs_no_triangle_test() raises:
    var assets = Assets()
    var scene = a_cube_scene(assets, Material(Color(255, 255, 255)))
    # Pointing away: the bounding sphere is missed.
    var away = Raycaster(Vector3(0, 0, 5), Vector3(0, 0, 1))
    assert_equal(len(away.intersect_mesh(scene, assets, 0)), 0)
    # Inside the sphere but outside the box: the corner region.
    var grazing = Raycaster(Vector3(0.6, 0.6, 5), Vector3(0, 0, -1))
    assert_equal(len(grazing.intersect_mesh(scene, assets, 0)), 0)


def test_a_ray_through_a_geometrys_box_can_still_miss_its_triangles() raises:
    # One triangle in the corner of its own bounding box: a ray through the
    # box's other corner reaches the triangle tests and fails every one.
    var assets = Assets()
    var corner = BufferGeometry()
    var data: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    corner.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(
        Mesh(
            assets.geometries.add(corner^),
            assets.materials.add(Material(Color(255, 255, 255))),
            node,
        )
    )
    var missing = Raycaster(Vector3(0.75, 0.75, 5), Vector3(0, 0, -1))
    assert_equal(len(missing.intersect_mesh(scene, assets, 0)), 0)
    var hitting = Raycaster(Vector3(0.25, 0.25, 5), Vector3(0, 0, -1))
    var hits = hitting.intersect_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_point(hits[0].point, 0.25, 0.25, 0)
    assert_equal(hits[0].triangle, 0)


def test_a_mesh_on_another_layer_is_not_tested() raises:
    var assets = Assets()
    var scene = a_cube_scene(assets, Material(Color(255, 255, 255)))
    scene.node(NodeId(0)).layers.set(1)
    scene.update()
    var caster = down_z()
    assert_equal(len(caster.intersect_mesh(scene, assets, 0)), 0)
    caster.layers.enable(1)
    assert_equal(len(caster.intersect_mesh(scene, assets, 0)), 1)


def test_a_moved_and_turned_mesh_is_hit_where_it_is() raises:
    var assets = Assets()
    var scene = a_cube_scene(assets, Material(Color(255, 255, 255)))
    # Slid two meters right, and turned a quarter turn about y, so the face
    # that was on +x now faces the camera. Still a unit cube face-on.
    scene.node(NodeId(0)).set_position(2, 0, 0)
    scene.node(NodeId(0)).set_euler(
        Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE)
    )
    scene.update()
    var caster = Raycaster(Vector3(2.1, 0.2, 5), Vector3(0, 0, -1))
    var hits = caster.intersect_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_almost_equal(hits[0].distance, Float32(4.5), atol=TOLERANCE)
    assert_point(hits[0].point, 2.1, 0.2, 0.5)
    assert_point(hits[0].normal, 0, 0, 1)


def test_a_stretched_and_turned_mesh_reports_world_distances() raises:
    # A cube stretched to two meters along its own x, then turned a
    # quarter turn about z, so the stretch runs along world y. The ray
    # is carried into the cube's space, where its direction is made unit
    # again and its parameter is no longer meters; the distance comes
    # from the world point, and the range is measured against that.
    var assets = Assets()
    var scene = a_cube_scene(assets, Material(Color(255, 255, 255)))
    scene.node(NodeId(0)).set_scale(2, 1, 1)
    scene.node(NodeId(0)).set_euler(
        Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(90.0, DEGREE)
    )
    scene.update()
    var caster = Raycaster(Vector3(0.1, 0.8, 5), Vector3(0, 0, -1))
    var hits = caster.intersect_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_almost_equal(hits[0].distance, Float32(4.5), atol=TOLERANCE)
    assert_point(hits[0].point, 0.1, 0.8, 0.5)
    assert_point(hits[0].normal, 0, 0, 1)
    # The same point, past the stretched extent the other way: a miss.
    var beyond = Raycaster(Vector3(0.8, 0.1, 5), Vector3(0, 0, -1))
    assert_equal(len(beyond.intersect_mesh(scene, assets, 0)), 0)
    # The range is in world meters.
    var short = Raycaster(
        Vector3(0.1, 0.8, 5),
        Vector3(0, 0, -1),
        Length(0.0, METER),
        Length(4.4, METER),
    )
    assert_equal(len(short.intersect_mesh(scene, assets, 0)), 0)
    var enough = Raycaster(
        Vector3(0.1, 0.8, 5),
        Vector3(0, 0, -1),
        Length(0.0, METER),
        Length(4.6, METER),
    )
    assert_equal(len(enough.intersect_mesh(scene, assets, 0)), 1)


def test_a_mirrored_mesh_is_hit_on_the_face_the_renderer_draws() raises:
    var assets = Assets()
    var scene = a_cube_scene(assets, Material(Color(255, 255, 255)))
    scene.node(NodeId(0)).set_scale(-1, 1, 1)
    scene.update()
    var hits = down_z().intersect_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_point(hits[0].point, 0.1, 0.2, 0.5)
    # The reflection reversed the winding; the normal is turned back, as
    # the renderer turns its geometric normal.
    assert_point(hits[0].normal, 0, 0, 1)


def test_a_mesh_with_no_vertices_is_hit_nowhere() raises:
    var assets = Assets()
    var nothing = BufferGeometry()
    nothing.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(
        Mesh(
            assets.geometries.add(nothing^),
            assets.materials.add(Material(Color(255, 255, 255))),
            node,
        )
    )
    assert_equal(len(down_z().intersect_mesh(scene, assets, 0)), 0)


def test_a_geometry_with_no_whole_triangle_is_hit_nowhere() raises:
    # One vertex: a bound the ray reaches, and no triangle to test.
    var assets = Assets()
    var dot = BufferGeometry()
    var data: List[Float32] = [0, 0, 0]
    dot.set_attribute(String(POSITION), BufferAttribute(data^, 3))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(
        Mesh(
            assets.geometries.add(dot^),
            assets.materials.add(Material(Color(255, 255, 255))),
            node,
        )
    )
    var through = Raycaster(Vector3(0, 0, 5), Vector3(0, 0, -1))
    assert_equal(len(through.intersect_mesh(scene, assets, 0)), 0)


def test_a_flattened_mesh_is_refused() raises:
    # A scale of zero has no inverse to carry the ray through.
    var assets = Assets()
    var scene = a_cube_scene(assets, Material(Color(255, 255, 255)))
    scene.node(NodeId(0)).set_scale(1, 0, 1)
    scene.update()
    with assert_raises():
        _ = down_z().intersect_mesh(scene, assets, 0)


def test_a_wrong_mesh_or_a_stale_scene_is_refused() raises:
    var assets = Assets()
    var scene = a_cube_scene(assets, Material(Color(255, 255, 255)))
    with assert_raises():
        _ = down_z().intersect_mesh(scene, assets, 1)
    with assert_raises():
        _ = down_z().intersect_mesh(scene, assets, -1)
    scene.add_mesh(Mesh(GeometryId(7), scene.meshes[0].material, NodeId(0)))
    with assert_raises():
        _ = down_z().intersect_mesh(scene, assets, 1)
    scene.node(NodeId(0)).set_position(0, 0, 1)
    with assert_raises():
        _ = down_z().intersect_mesh(scene, assets, 0)


# --- the whole scene ---------------------------------------------------------


def test_the_scene_answers_nearest_first_across_meshes() raises:
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(
        Material(Color(255, 255, 255), side=DOUBLE_SIDE)
    )
    var scene = Scene()
    # The further cube is added first, so the order has to come from the
    # distances and not from the mesh list.
    var far = Object3D()
    far.set_position(0, 0, -3)
    scene.add_mesh(Mesh(box, paint, scene.add(far^)))
    scene.add_mesh(Mesh(box, paint, scene.add(Object3D())))
    # And one off to the side that the ray never reaches.
    var aside = Object3D()
    aside.set_position(4, 0, 0)
    scene.add_mesh(Mesh(box, paint, scene.add(aside^)))
    scene.update()
    var hits = down_z().intersect_scene(scene, assets)
    assert_equal(len(hits), 4)
    assert_equal(hits[0].index, 1)
    assert_almost_equal(hits[0].distance, Float32(4.5), atol=TOLERANCE)
    assert_equal(hits[1].index, 1)
    assert_almost_equal(hits[1].distance, Float32(5.5), atol=TOLERANCE)
    assert_equal(hits[2].index, 0)
    assert_almost_equal(hits[2].distance, Float32(7.5), atol=TOLERANCE)
    assert_equal(hits[3].index, 0)
    assert_almost_equal(hits[3].distance, Float32(8.5), atol=TOLERANCE)


def test_an_empty_scene_is_hit_nowhere() raises:
    var assets = Assets()
    var scene = Scene()
    assert_equal(len(down_z().intersect_scene(scene, assets)), 0)


def test_a_click_lands_on_the_cube_under_it() raises:
    # The whole path: a pixel of an image the camera would render, back
    # through the camera, onto the mesh drawn there.
    var assets = Assets()
    var scene = a_cube_scene(assets, Material(Color(255, 255, 255)))
    var camera = square_camera()
    # A little right of and above the middle: at 90 degrees, a tenth of the
    # way to the edge is a tenth of the depth, so 0.45 across at z = 0.5.
    var caster = down_z()
    caster.set_from_pixel(110, 47.5, 200, 100, camera, scene)
    var hits = caster.intersect_scene(scene, assets)
    assert_equal(len(hits), 1)
    assert_point(hits[0].point, 0.45, 0.225, 0.5)
    # A pixel at the edge of the image looks past the cube.
    caster.set_from_pixel(0.5, 50, 200, 100, camera, scene)
    assert_equal(len(caster.intersect_scene(scene, assets)), 0)


# --- groups and levels -------------------------------------------------------


def test_a_hit_kind_is_one_of_nine() raises:
    assert_true(MESH_HIT.is_valid())
    assert_true(INSTANCED_HIT.is_valid())
    assert_true(BATCHED_HIT.is_valid())
    assert_true(LOD_HIT.is_valid())
    assert_true(HitKind(7).is_valid())
    assert_true(WIDE_LINE_HIT.is_valid())
    assert_false(HitKind(9).is_valid())
    assert_false(HitKind(-1).is_valid())


def test_a_plain_mesh_hit_names_its_list_and_no_instance() raises:
    var assets = Assets()
    var scene = a_cube_scene(assets, Material(Color(255, 255, 255)))
    var hits = down_z().intersect_mesh(scene, assets, 0)
    assert_equal(hits[0].kind, MESH_HIT)
    assert_equal(hits[0].instance, -1)


def test_an_instanced_mesh_is_hit_per_instance_at_its_own_place() raises:
    # Two unit cubes on one node: one at the origin, one two meters up z
    # and slid off the ray on x. The ray strikes the first alone, and the
    # hit says which, three.js's `instanceId`.
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var group = InstancedMesh(
        assets.geometries.add(cube(Length(1.0, METER))),
        assets.materials.add(Material(Color(255, 255, 255))),
        node,
        2,
    )
    group.set_matrix_at(1, translation(3, 0, 2))
    scene.add_instanced_mesh(group^)
    var hits = down_z().intersect_instanced_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_equal(hits[0].kind, INSTANCED_HIT)
    assert_equal(hits[0].index, 0)
    assert_equal(hits[0].instance, 0)
    assert_equal(hits[0].mesh.node, node)
    assert_almost_equal(hits[0].distance, Float32(4.5), atol=TOLERANCE)
    # Slide the second under the ray, in front of the first: it is struck
    # first, at the node's transform times its own.
    scene.instanced_meshes[0].set_matrix_at(1, translation(0, 0, 2))
    hits = down_z().intersect_instanced_mesh(scene, assets, 0)
    assert_equal(len(hits), 2)
    assert_equal(hits[0].instance, 1)
    assert_almost_equal(hits[0].distance, Float32(2.5), atol=TOLERANCE)
    assert_equal(hits[1].instance, 0)
    with assert_raises():
        _ = down_z().intersect_instanced_mesh(scene, assets, 1)
    with assert_raises():
        _ = down_z().intersect_instanced_mesh(scene, assets, -1)


def test_a_batched_mesh_is_hit_with_each_instances_own_geometry() raises:
    # A big cube slid off the ray and a small one under it, in one batch.
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var big = assets.geometries.add(cube(Length(4.0, METER)))
    var small = assets.geometries.add(cube(Length(1.0, METER)))
    var batch = BatchedMesh(
        assets.materials.add(Material(Color(255, 255, 255))), node
    )
    _ = batch.add_instance(big, translation(6, 0, 0))
    _ = batch.add_instance(small, translation(0, 0, 1))
    scene.add_batched_mesh(batch^)
    var hits = down_z().intersect_batched_mesh(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_equal(hits[0].kind, BATCHED_HIT)
    assert_equal(hits[0].instance, 1)
    assert_equal(hits[0].mesh.geometry, small)
    assert_almost_equal(hits[0].distance, Float32(3.5), atol=TOLERANCE)
    with assert_raises():
        _ = down_z().intersect_batched_mesh(scene, assets, 1)
    with assert_raises():
        _ = down_z().intersect_batched_mesh(scene, assets, -1)


def test_an_empty_group_is_hit_nowhere() raises:
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    scene.add_instanced_mesh(InstancedMesh(box, paint, node, 0))
    scene.add_batched_mesh(BatchedMesh(paint, node))
    assert_equal(len(down_z().intersect_scene(scene, assets)), 0)


def test_an_lod_is_hit_on_the_level_the_rays_origin_picks() raises:
    # A unit cube up close and a two-meter cube from three meters on. The
    # ray leaves five meters out, so the far level is the one struck.
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var small = assets.geometries.add(cube(Length(1.0, METER)))
    var large = assets.geometries.add(cube(Length(2.0, METER)))
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    var lod = Lod(node)
    lod.add_level(small, paint)
    lod.add_level(large, paint, Length(3.0, METER), 0.5)
    scene.add_lod(lod^)
    var hits = down_z().intersect_lod(scene, assets, 0)
    assert_equal(len(hits), 1)
    assert_equal(hits[0].kind, LOD_HIT)
    assert_equal(hits[0].instance, 1)
    assert_equal(hits[0].mesh.geometry, large)
    assert_almost_equal(hits[0].distance, Float32(4.0), atol=TOLERANCE)
    # From two meters out, the near level, whatever the LOD remembers:
    # three.js's `LOD.raycast` goes by `getObjectForDistance`.
    scene.update_lods(Vector3(0, 0, 5))
    var near = Raycaster(Vector3(0.1, 0.2, 2), Vector3(0, 0, -1))
    hits = near.intersect_lod(scene, assets, 0)
    assert_equal(hits[0].instance, 0)
    assert_almost_equal(hits[0].distance, Float32(1.5), atol=TOLERANCE)
    # No levels, no hits; no such LOD, an error.
    var bare = Scene()
    _ = bare.add(Object3D())
    bare.update()
    bare.add_lod(Lod(NodeId(0)))
    assert_equal(len(down_z().intersect_lod(bare, assets, 0)), 0)
    with assert_raises():
        _ = down_z().intersect_lod(scene, assets, 1)
    with assert_raises():
        _ = down_z().intersect_lod(scene, assets, -1)


def test_the_scene_answers_across_every_kind_of_object() raises:
    # A plain cube at the origin, an instance a meter up, a batch member
    # two up and an LOD level three up: four hits, nearest first, each
    # from its own list.
    var assets = Assets()
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(255, 255, 255)))
    scene.add_mesh(Mesh(box, paint, node))
    var group = InstancedMesh(box, paint, node, 1)
    group.set_matrix_at(0, translation(0, 0, 1))
    scene.add_instanced_mesh(group^)
    var batch = BatchedMesh(paint, node)
    _ = batch.add_instance(box, translation(0, 0, 2))
    scene.add_batched_mesh(batch^)
    var raised = scene.add(Object3D())
    scene.node(raised).set_position(0, 0, 3)
    scene.update()
    var lod = Lod(raised)
    lod.add_level(box, paint)
    scene.add_lod(lod^)
    var hits = down_z().intersect_scene(scene, assets)
    assert_equal(len(hits), 4)
    assert_equal(hits[0].kind, LOD_HIT)
    assert_equal(hits[1].kind, BATCHED_HIT)
    assert_equal(hits[2].kind, INSTANCED_HIT)
    assert_equal(hits[3].kind, MESH_HIT)
    assert_almost_equal(hits[0].distance, Float32(1.5), atol=TOLERANCE)
    assert_almost_equal(hits[3].distance, Float32(4.5), atol=TOLERANCE)
    # A layer the raycaster does not test hides a group as it hides a mesh.
    scene.node(node).layers.set(1)
    scene.update()
    hits = down_z().intersect_scene(scene, assets)
    assert_equal(len(hits), 1)
    assert_equal(hits[0].kind, LOD_HIT)


def morphed_scene() raises -> Scene:
    """Return a scene holding one flat triangle at the origin, whose single
    morph target carries every vertex ten meters along x."""
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    return scene^


def morphed_mesh(mut assets: Assets, weight: Float32) raises -> Mesh:
    """Return a mesh over that triangle, wearing its target at `weight`."""
    var geometry = BufferGeometry()
    var points: List[Float32] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    geometry.set_attribute(String(POSITION), BufferAttribute(points^, 3))
    var offsets: List[Float32] = [10, 0, 0, 10, 0, 0, 10, 0, 0]
    geometry.add_morph_target(BufferAttribute(offsets^, 3))
    geometry.morph_relative = True
    var mesh = Mesh(
        assets.geometries.add(geometry^),
        assets.materials.add(Material(Color(255, 255, 255), side=DOUBLE_SIDE)),
        NodeId(0),
    )
    mesh.set_morph_influence(0, weight)
    return mesh^


def test_a_ray_meets_a_morphed_mesh_where_it_is_drawn() raises:
    # Rendering wears the targets and picking did not, so the drawn shape
    # could not be hit and the modelled one could be hit where nothing was.
    var assets = Assets()
    var scene = morphed_scene()
    scene.add_mesh(morphed_mesh(assets, 1))
    scene.update()

    # Straight down onto where the triangle has gone.
    var onto = Raycaster(Vector3(10.25, 0.25, 1), Vector3(0, 0, -1))
    var met = onto.intersect_mesh(scene, assets, 0)
    assert_equal(len(met), 1)
    assert_almost_equal(met[0].point.x, Float32(10.25), atol=TOLERANCE)
    assert_almost_equal(met[0].point.z, Float32(0), atol=TOLERANCE)


def test_a_ray_misses_a_morphed_mesh_where_it_used_to_be() raises:
    var assets = Assets()
    var scene = morphed_scene()
    scene.add_mesh(morphed_mesh(assets, 1))
    scene.update()

    # Straight down onto where the geometry was modelled and is not now.
    var behind = Raycaster(Vector3(0.25, 0.25, 1), Vector3(0, 0, -1))
    assert_equal(len(behind.intersect_mesh(scene, assets, 0)), 0)


def test_a_half_worn_target_is_met_half_way() raises:
    var assets = Assets()
    var scene = morphed_scene()
    scene.add_mesh(morphed_mesh(assets, 0.5))
    scene.update()
    var onto = Raycaster(Vector3(5.25, 0.25, 1), Vector3(0, 0, -1))
    assert_equal(len(onto.intersect_mesh(scene, assets, 0)), 1)
    var elsewhere = Raycaster(Vector3(10.25, 0.25, 1), Vector3(0, 0, -1))
    assert_equal(len(elsewhere.intersect_mesh(scene, assets, 0)), 0)


def test_picking_a_scene_sees_the_worn_mesh_too() raises:
    # `intersect_scene` walks the same path, so the whole-scene query has
    # to agree with the single-mesh one.
    var assets = Assets()
    var scene = morphed_scene()
    scene.add_mesh(morphed_mesh(assets, 1))
    scene.update()
    var onto = Raycaster(Vector3(10.25, 0.25, 1), Vector3(0, 0, -1))
    assert_equal(len(onto.intersect_scene(scene, assets)), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
