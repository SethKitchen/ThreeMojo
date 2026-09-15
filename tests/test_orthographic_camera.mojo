# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.projection.orthographic` and `cameras.orthographic_camera`.

The defining property is negative: distance does *not* shrink anything. Most
of these assert that directly, by comparing two identical objects at different
depths, because "the matrix has the right numbers in it" is a weaker claim
than "the picture has no perspective in it".
"""

from cameras.camera import Camera
from render.framebuffer import Framebuffer
from core.object3d import NodeId
from cameras.orthographic_camera import OrthographicCamera, centered
from core.assets import Assets
from materials.material import Material
from core.object3d import Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from geometries.box import cube
from math.projection import look_at, orthographic
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length, METER


def rendered[
    C: Camera
](
    renderer: Renderer,
    mut scene: Scene,
    assets: Assets,
    meshes: List[Mesh],
    camera: C,
) raises -> Framebuffer:
    """Render `meshes` in `scene`, the way this suite was written to.

    Meshes live in the scene now, as lights do, and the renderer takes only
    the scene. These tests were written passing a list alongside it, and
    several render one scene with two different lists to compare them, which
    is exactly what assigning `scene.meshes` here preserves.

    Args:
        renderer: The renderer to draw with.
        scene: The scene to draw; its mesh list is replaced.
        assets: The geometry, materials and textures the meshes name.
        meshes: What to draw.
        camera: The camera to project through.

    Returns:
        The rendered image.

    Raises:
        Error: If the render fails.
    """
    scene.meshes = meshes.copy()
    return renderer.render(scene, assets, camera)


def rendered_new[
    C: Camera
](
    renderer: Renderer,
    var scene: Scene,
    assets: Assets,
    meshes: List[Mesh],
    camera: C,
) raises -> Framebuffer:
    """`rendered`, for a scene built in the call itself.

    Args:
        renderer: The renderer to draw with.
        scene: The scene to draw, consumed.
        assets: The geometry, materials and textures the meshes name.
        meshes: What to draw.
        camera: The camera to project through.

    Returns:
        The rendered image.

    Raises:
        Error: If the render fails.
    """
    scene.meshes = meshes.copy()
    return renderer.render(scene, assets, camera)


def light_the(mut scene: Scene) raises:
    """Add the lighting these tests were written against.

    White ambient at a quarter plus a white directional at three quarters,
    from up and to the right. That is exactly the fixed light `Renderer` used
    to carry -- its `0.25 + 0.75 * lambert` is what an additive quarter and
    three quarters come to for a white lamp -- so every expected color in
    this file is unchanged by lights becoming scene objects. A color that
    moves here is a bug, not the redesign.

    Adds the lamp's node last, so the node ids meshes already name still
    point at the same nodes.
    """
    var lamp = Object3D()
    lamp.set_position(0.4, 0.8, 0.5)
    var node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.25))
    scene.add_light(directional_light(Color(255, 255, 255), node, 0.75))


comptime TOLERANCE = Float64(1e-5)
comptime WIDTH = 32
comptime HEIGHT = 24


def a_camera() raises -> OrthographicCamera:
    """Return a symmetric camera four meters back, six meters tall."""
    var camera = centered(
        Length(6.0, METER),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


# --- the projection matrix --------------------------------------------------


def test_the_near_plane_maps_to_minus_one_and_the_far_plane_to_plus_one() raises:
    var m = orthographic(-2, 2, 1.5, -1.5, 1, 10)
    assert_almost_equal(
        m.transform_point(Vector3(0, 0, -1)).z, Float32(-1), atol=TOLERANCE
    )
    assert_almost_equal(
        m.transform_point(Vector3(0, 0, -10)).z, Float32(1), atol=TOLERANCE
    )


def test_the_volume_edges_map_to_the_edges_of_the_cube() raises:
    var m = orthographic(-2, 2, 1.5, -1.5, 1, 10)
    var corner = m.transform_point(Vector3(2, 1.5, -5))
    assert_almost_equal(corner.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(corner.y, Float32(1), atol=TOLERANCE)


def test_w_stays_one_so_nothing_is_divided() raises:
    # The entire difference from `perspective`, and the reason the
    # perspective-correct interpolation quietly becomes a no-op.
    var m = orthographic(-2, 2, 1.5, -1.5, 1, 10)
    assert_equal(m.transform_w(Vector3(0, 0, -1)), Float32(1))
    assert_equal(m.transform_w(Vector3(9, -4, -97)), Float32(1))


def test_depth_does_not_change_size() raises:
    # The property the whole projection exists for. The same offset from the
    # axis lands in the same place whether it is near or far away.
    var m = orthographic(-2, 2, 1.5, -1.5, 1, 10)
    var near = m.transform_point(Vector3(1, 0, -2))
    var far = m.transform_point(Vector3(1, 0, -9))
    assert_almost_equal(near.x, far.x, atol=TOLERANCE)


def test_an_off_center_volume_shifts_the_view() raises:
    # Not every orthographic camera is symmetric; a shadow map's rarely is.
    var m = orthographic(0, 4, 1.5, -1.5, 1, 10)
    assert_almost_equal(
        m.transform_point(Vector3(2, 0, -5)).x, Float32(0), atol=TOLERANCE
    )


def test_a_degenerate_or_misordered_volume_is_rejected() raises:
    # Equal edges have no volume; reversed ones mirror the projection, which
    # would reverse screen winding and quietly invert backface culling.
    with assert_raises():
        _ = orthographic(1, 1, 1, -1, 1, 10)
    with assert_raises():
        _ = orthographic(-1, 1, 1, 1, 1, 10)
    with assert_raises():
        _ = orthographic(1, -1, 1, -1, 1, 10)
    with assert_raises():
        _ = orthographic(-1, 1, -1, 1, 1, 10)
    with assert_raises():
        _ = orthographic(-1, 1, 1, -1, -1, 10)
    with assert_raises():
        _ = orthographic(-1, 1, 1, -1, 5, 5)


def test_a_near_plane_of_zero_is_allowed() raises:
    # Nothing divides by depth in an orthographic projection, so the
    # perspective camera's reason for forbidding it does not apply. three.js
    # allows it too.
    var m = orthographic(-2, 2, 1.5, -1.5, 0, 10)
    assert_almost_equal(
        m.transform_point(Vector3(0, 0, 0)).z, Float32(-1), atol=TOLERANCE
    )
    assert_almost_equal(
        m.transform_point(Vector3(0, 0, -10)).z, Float32(1), atol=TOLERANCE
    )


# --- the camera -------------------------------------------------------------


def test_a_centered_camera_has_the_height_it_was_asked_for() raises:
    var camera = centered(
        Length(6.0, METER), 2.0, Length(0.1, METER), Length(100.0, METER)
    )
    assert_equal(camera.top.value, Float32(3))
    assert_equal(camera.bottom.value, Float32(-3))
    # Twice as wide as tall.
    assert_equal(camera.right.value, Float32(6))
    assert_equal(camera.left.value, Float32(-6))


def test_a_camera_reports_its_clipping_distances() raises:
    var camera = a_camera()
    assert_equal(camera.near_distance(), Float32(0.1))
    assert_equal(camera.far_distance(), Float32(100))


def test_an_orthographic_camera_can_ride_a_node() raises:
    var scene = Scene()
    var eye = Object3D()
    eye.set_position(0, 0, 5)
    var node = scene.add(eye^)
    scene.update()
    var camera = a_camera()
    camera.attach(node)
    with assert_raises():
        _ = camera.view_matrix()
    var view = camera.view_matrix_in(scene)
    var expected = look_at(Vector3(0, 0, 5), Vector3(0, 0, 0), Vector3(0, 1, 0))
    for index in range(16):
        assert_almost_equal(
            view.elements[index], expected.elements[index], atol=TOLERANCE
        )
    # Placed again, it answers from the placement and needs no scene.
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var placed = camera.view_matrix_in(Scene())
    for index in range(16):
        assert_almost_equal(
            placed.elements[index], expected.elements[index], atol=TOLERANCE
        )


def test_an_orthographic_camera_on_a_scaled_node_keeps_its_lens() raises:
    var scene = Scene()
    var eye = Object3D()
    eye.set_position(0, 0, 5)
    eye.set_scale(2, 2, 0.5)
    var node = scene.add(eye^)
    scene.update()
    var camera = a_camera()
    camera.attach(node)
    var view = camera.view_matrix_in(scene)
    var expected = look_at(Vector3(0, 0, 5), Vector3(0, 0, 0), Vector3(0, 1, 0))
    for index in range(16):
        assert_almost_equal(
            view.elements[index], expected.elements[index], atol=TOLERANCE
        )


def test_an_unusable_camera_is_rejected() raises:
    with assert_raises():
        _ = centered(
            Length(0.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
        )
    with assert_raises():
        _ = centered(
            Length(6.0, METER), 0.0, Length(0.1, METER), Length(10.0, METER)
        )
    with assert_raises():
        _ = OrthographicCamera(
            Length(-1.0, METER),
            Length(-1.0, METER),
            Length(1.0, METER),
            Length(-1.0, METER),
            Length(0.1, METER),
            Length(10.0, METER),
        )
    with assert_raises():
        _ = OrthographicCamera(
            Length(-1.0, METER),
            Length(1.0, METER),
            Length(1.0, METER),
            Length(1.0, METER),
            Length(0.1, METER),
            Length(10.0, METER),
        )
    with assert_raises():
        _ = OrthographicCamera(
            Length(-1.0, METER),
            Length(1.0, METER),
            Length(1.0, METER),
            Length(-1.0, METER),
            Length(-1.0, METER),
            Length(10.0, METER),
        )
    with assert_raises():
        _ = OrthographicCamera(
            Length(-1.0, METER),
            Length(1.0, METER),
            Length(1.0, METER),
            Length(-1.0, METER),
            Length(1.0, METER),
            Length(1.0, METER),
        )


# --- rendering through it ---------------------------------------------------


def drawn_pixels(
    renderer: Renderer, mut scene: Scene, assets: Assets, meshes: List[Mesh]
) raises -> Int:
    """Return how many pixels a scene covers through an orthographic camera.

    Args:
        renderer: The renderer to draw with.
        scene: The transform hierarchy.
        assets: The geometry, materials and textures the meshes name.
        meshes: What to draw.

    Returns:
        The number of non-background pixels.

    Raises:
        Error: If the render fails.
    """
    var image = rendered(renderer, scene, assets, meshes, a_camera())
    var drawn = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if (
                pixel.r != renderer.background.r
                or pixel.g != renderer.background.g
                or pixel.b != renderer.background.b
            ):
                drawn += 1
    return drawn


def test_a_camera_with_a_zero_near_plane_renders() raises:
    # The whole chain has to agree that zero is acceptable: the camera, the
    # projection matrix and the shared clipper.
    var renderer = Renderer(WIDTH, HEIGHT)
    var camera = centered(
        Length(6.0, METER),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.0, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var assets = Assets()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            assets.geometries.add(cube(Length(2.0, METER))),
            assets.materials.add(Material(Color(9, 9, 9))),
            NodeId(0),
        )
    )
    var image = rendered_new(renderer, a_scene_at(0), assets, meshes, camera)
    var drawn = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if image.get_pixel(x, y).r != renderer.background.r:
                drawn += 1
    assert_true(drawn > 0, "nothing drew through a zero near plane")


def test_the_renderer_accepts_an_orthographic_camera() raises:
    # The trait doing its job: `Renderer` never mentions either camera type.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(2.0, METER)))
    var scene = Scene()
    var node = Object3D()
    _ = scene.add(node^)
    light_the(scene)
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 140, 40))), NodeId(0)
        )
    )
    assert_true(drawn_pixels(renderer, scene, assets, meshes) > 0)


def a_scene_at(z: Float32) raises -> Scene:
    """Return a scene holding one node at the given depth."""
    var scene = Scene()
    var node = Object3D()
    node.set_position(0, 0, z)
    _ = scene.add(node^)
    light_the(scene)
    scene.update()
    return scene^


def test_distance_does_not_change_which_pixels_a_cube_covers() raises:
    # Perspective's absence, measured on the image rather than the matrix.
    # Comparing *counts* would be too weak: two different silhouettes can
    # cover the same number of pixels. These must be the same pixels.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(2.0, METER)))

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 140, 40))), NodeId(0)
        )
    )
    var near = rendered_new(renderer, a_scene_at(0), assets, meshes, a_camera())
    var far = rendered_new(renderer, a_scene_at(-8), assets, meshes, a_camera())

    var covered = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var here = near.get_pixel(x, y)
            var there = far.get_pixel(x, y)
            var drawn_here = here.r != renderer.background.r or (
                here.g != renderer.background.g
            )
            var drawn_there = there.r != renderer.background.r or (
                there.g != renderer.background.g
            )
            assert_equal(drawn_here, drawn_there)
            if drawn_here:
                covered += 1
    assert_true(covered > 0, "the cube drew nothing at either depth")


def test_moving_away_still_changes_the_depth_buffer() raises:
    # The other half of the same claim. Size must not change with distance;
    # *depth* must, or the projection would be flattening z as well and the
    # test above would pass for the wrong reason.
    var renderer = Renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(2.0, METER)))
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 140, 40))), NodeId(0)
        )
    )

    var near = rendered_new(renderer, a_scene_at(0), assets, meshes, a_camera())
    var far = rendered_new(renderer, a_scene_at(-8), assets, meshes, a_camera())

    var compared = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if near.get_pixel(x, y).r != renderer.background.r:
                assert_true(far.depth_at(x, y) > near.depth_at(x, y))
                compared += 1
    assert_true(compared > 0, "no covered pixel to compare depth at")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
