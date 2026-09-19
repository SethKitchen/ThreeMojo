# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `objects.points`, `objects.sprite`, `Scene.add_points`,
`Scene.add_sprite`, `Renderer.prepare_points` and the sprite pass of
`Renderer.prepare`."""

from cameras.orthographic_camera import OrthographicCamera, centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from core.geometry_store import GeometryId
from core.layers import Layers
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from materials.material import (
    BASIC,
    BLEND,
    LAMBERT,
    Material,
    MaterialId,
    OPAQUE,
    PointSize,
    points_material,
    sprite_material,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import SPRITE_RADIUS, Sprite
from render.framebuffer import Color, Framebuffer
from render.rasterizer import (
    DRAW_POINTS,
    DRAW_SEGMENTS,
    DRAW_TRIANGLES,
    RasterVertex,
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
)
from render.srgb import LINEAR, SRGB
from render.texture import (
    COVERAGE,
    IGNORED,
    NEAREST,
    REPEAT,
    Texture,
    checkerboard,
)
from render.texture_store import NO_TEXTURE, TextureId
from renderers.renderer import Renderer
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
# Small for the reason `tests/test_line_objects.mojo` gives.
comptime WIDTH = 16
comptime HEIGHT = 16


def a_camera() raises -> OrthographicCamera:
    """Return a camera looking down -z at a two-meter square of world:
    eight pixels a meter, the origin at the image's center.

    Returns:
        The camera.

    Raises:
        Error: If its parameters are invalid.
    """
    var camera = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def a_perspective_camera() raises -> PerspectiveCamera:
    """Return a camera two meters from the origin with a right-angle view:
    four meters across at the origin, four pixels a meter there.

    Returns:
        The camera.

    Raises:
        Error: If its parameters are invalid.
    """
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(0.5, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 2), Vector3(0, 0, 0))
    return camera^


def dots(var numbers: List[Float32]) raises -> BufferGeometry:
    """Return a geometry holding `numbers` as positions and nothing else.

    Args:
        numbers: Three per point.

    Returns:
        The geometry.

    Raises:
        Error: If the numbers do not divide into points.
    """
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    return geometry^


def a_scene_with_one_node() raises -> Scene:
    """Return a scene holding one node at the origin, updated.

    Returns:
        The scene.

    Raises:
        Error: If the scene is invalid.
    """
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    return scene^


def a_mask(green: UInt8, linear: Bool = True) raises -> Texture:
    """Return a one-texel alpha map whose green channel is `green`."""
    var pixels: List[UInt8] = [0, green, 255, 255]
    var space = SRGB
    if linear:
        space = LINEAR
    return Texture(1, 1, pixels^, REPEAT, NEAREST, space, False, IGNORED)


def painted(image: Framebuffer, channel: Int) raises -> Int:
    """Return how many pixels have one channel above half."""
    var count = 0
    for y in range(image.height):
        for x in range(image.width):
            var pixel = image.get_pixel(x, y)
            var value = pixel.r
            if channel == 1:
                value = pixel.g
            if channel == 2:
                value = pixel.b
            if value > 128:
                count += 1
    return count


# --- the objects ------------------------------------------------------------


def test_points_name_three_ids() raises:
    var cloud = Points(GeometryId(3), MaterialId(2), NodeId(1))
    assert_equal(cloud.geometry.value, 3)
    assert_equal(cloud.material.value, 2)
    assert_equal(cloud.node.value, 1)
    assert_true(cloud.frustum_culled)
    var kept = Points(
        GeometryId(0), MaterialId(0), NodeId(0), frustum_culled=False
    )
    assert_false(kept.frustum_culled)


def test_points_refuse_what_cannot_be_an_id() raises:
    with assert_raises(contains="scene node"):
        _ = Points(GeometryId(0), MaterialId(0), NodeId(-1))
    with assert_raises(contains="geometry"):
        _ = Points(GeometryId(-1), MaterialId(0), NodeId(0))
    with assert_raises(contains="material"):
        _ = Points(GeometryId(0), MaterialId(-1), NodeId(0))


def test_a_sprite_names_a_material_a_node_and_a_center() raises:
    var badge = Sprite(MaterialId(2), NodeId(1))
    assert_equal(badge.material.value, 2)
    assert_equal(badge.node.value, 1)
    assert_almost_equal(Float64(badge.center.x), 0.5, atol=TOLERANCE)
    assert_almost_equal(Float64(badge.center.y), 0.5, atol=TOLERANCE)
    assert_true(badge.frustum_culled)
    var cornered = Sprite(
        MaterialId(0), NodeId(0), center=Vector2(0, 1), frustum_culled=False
    )
    assert_almost_equal(Float64(cornered.center.y), 1.0, atol=TOLERANCE)
    assert_false(cornered.frustum_culled)
    assert_almost_equal(
        Float64(SPRITE_RADIUS), 0.7071067811865476, atol=TOLERANCE
    )


def test_a_sprite_refuses_what_cannot_be_an_id_or_a_center() raises:
    with assert_raises(contains="scene node"):
        _ = Sprite(MaterialId(0), NodeId(-1))
    with assert_raises(contains="material"):
        _ = Sprite(MaterialId(-1), NodeId(0))
    with assert_raises(contains="center must be finite"):
        _ = Sprite(
            MaterialId(0), NodeId(0), center=Vector2(nan[DType.float32](), 0)
        )
    with assert_raises(contains="center must be finite"):
        _ = Sprite(
            MaterialId(0), NodeId(0), center=Vector2(0, nan[DType.float32]())
        )


def test_a_scene_takes_points_and_sprites_beside_its_meshes() raises:
    var scene = a_scene_with_one_node()
    scene.add_points(Points(GeometryId(0), MaterialId(0), NodeId(0)))
    scene.add_sprite(Sprite(MaterialId(0), NodeId(0)))
    assert_equal(len(scene.points), 1)
    assert_equal(len(scene.sprites), 1)
    with assert_raises(contains="node that is in the scene"):
        scene.add_points(Points(GeometryId(0), MaterialId(0), NodeId(4)))
    with assert_raises(contains="node that is in the scene"):
        scene.add_sprite(Sprite(MaterialId(0), NodeId(4)))


# --- preparing points -------------------------------------------------------


def test_preparing_points_gives_one_corner_each() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(
        dots([-0.5, 0.0, 0.0, 0.0, 0.5, 0.0, 0.5, 0.0, 0.0])
    )
    var material = assets.materials.add(
        points_material(Color(255, 0, 0), size=PointSize(3.0))
    )
    var scene = a_scene_with_one_node()
    scene.add_points(Points(geometry, material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    var prepared = renderer.prepare_points(scene, assets, a_camera())
    assert_equal(len(prepared), 3)
    for index in range(len(prepared)):
        assert_true(prepared[index].kind == BASIC)
        assert_true(prepared[index].texture == NO_TEXTURE)
        assert_true(prepared[index].blend == OPAQUE)
        # A parallel projection leaves the size as the material said.
        assert_almost_equal(
            Float64(prepared[index].point_size), 3.0, atol=TOLERANCE
        )
    # Eight pixels a meter from the center: the first point four to the
    # left, the second four up.
    assert_almost_equal(Float64(prepared[0].x), 4.0, atol=TOLERANCE)
    assert_almost_equal(Float64(prepared[0].y), 8.0, atol=TOLERANCE)
    assert_almost_equal(Float64(prepared[1].x), 8.0, atol=TOLERANCE)
    assert_almost_equal(Float64(prepared[1].y), 4.0, atol=TOLERANCE)
    # And each carries its own color when the material asks.
    var tinted = BufferGeometry()
    tinted.set_attribute(
        String(POSITION), BufferAttribute([0.0, 0.0, 0.0, 0.5, 0.0, 0.0], 3)
    )
    tinted.set_attribute(
        String(COLOR), BufferAttribute([1.0, 0.0, 0.0, 0.0, 1.0, 0.0], 3)
    )
    var colored = assets.geometries.add(tinted^)
    var paint = assets.materials.add(
        points_material(Color(255, 255, 255), vertex_colors=True)
    )
    scene.points = List[Points]()
    scene.add_points(Points(colored, paint, NodeId(0)))
    var shaded = renderer.prepare_points(scene, assets, a_camera())
    assert_almost_equal(Float64(shaded[0].color.r), 1.0, atol=TOLERANCE)
    assert_almost_equal(Float64(shaded[0].color.g), 0.0, atol=TOLERANCE)
    assert_almost_equal(Float64(shaded[1].color.g), 1.0, atol=TOLERANCE)


def test_a_point_shrinks_with_distance_under_perspective() raises:
    # Half the image height is eight; the camera is two meters from the
    # origin, so a point there is size * 8 / 2, and one a meter further
    # is size * 8 / 3. Attenuation off, both are the material's size.
    var assets = Assets()
    var geometry = assets.geometries.add(dots([0.0, 0.0, 0.0, 0.0, 0.0, -1.0]))
    var shrinking = assets.materials.add(
        points_material(Color(255, 0, 0), size=PointSize(2.0))
    )
    var fixed = assets.materials.add(
        points_material(
            Color(255, 0, 0), size=PointSize(2.0), size_attenuation=False
        )
    )
    var scene = a_scene_with_one_node()
    scene.add_points(Points(geometry, shrinking, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    var camera = a_perspective_camera()
    var prepared = renderer.prepare_points(scene, assets, camera)
    assert_almost_equal(Float64(prepared[0].point_size), 8.0, atol=TOLERANCE)
    assert_almost_equal(
        Float64(prepared[1].point_size), 16.0 / 3.0, atol=TOLERANCE
    )
    scene.points = List[Points]()
    scene.add_points(Points(geometry, fixed, NodeId(0)))
    var held = renderer.prepare_points(scene, assets, camera)
    assert_almost_equal(Float64(held[0].point_size), 2.0, atol=TOLERANCE)
    assert_almost_equal(Float64(held[1].point_size), 2.0, atol=TOLERANCE)


def test_a_point_outside_the_view_volume_is_left_out_whole() raises:
    var assets = Assets()
    # One in view, one behind the camera, one past the far plane, one off
    # the left side.
    var geometry = assets.geometries.add(
        dots([0.0, 0.0, 0.0, 0.0, 0.0, 5.0, 0.0, 0.0, -20.0, -30.0, 0.0, 0.0])
    )
    var material = assets.materials.add(points_material(Color(255, 0, 0)))
    var scene = a_scene_with_one_node()
    scene.add_points(
        Points(geometry, material, NodeId(0), frustum_culled=False)
    )
    var renderer = Renderer(WIDTH, HEIGHT)
    var prepared = renderer.prepare_points(scene, assets, a_camera())
    assert_equal(len(prepared), 1)
    assert_almost_equal(Float64(prepared[0].x), 8.0, atol=TOLERANCE)


def test_points_out_of_view_are_left_out_unless_they_say_otherwise() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(dots([50.0, 0.0, 0.0, 51.0, 0.0, 0.0]))
    var material = assets.materials.add(points_material(Color(255, 0, 0)))
    var scene = a_scene_with_one_node()
    scene.add_points(Points(geometry, material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    assert_equal(len(renderer.prepare_points(scene, assets, a_camera())), 0)
    # Opting out of the cull leaves the clipper to throw each point away
    # on its own, which comes to the same list here.
    scene.points = List[Points]()
    scene.add_points(
        Points(geometry, material, NodeId(0), frustum_culled=False)
    )
    assert_equal(len(renderer.prepare_points(scene, assets, a_camera())), 0)
    # And a node on a layer the camera does not see contributes nothing.
    var near = assets.geometries.add(dots([0.0, 0.0, 0.0]))
    scene.points = List[Points]()
    scene.add_points(Points(near, material, NodeId(0)))
    assert_equal(len(renderer.prepare_points(scene, assets, a_camera())), 1)
    var hidden = Layers()
    hidden.set(3)
    scene.node(NodeId(0)).layers = hidden
    scene.update()
    assert_equal(len(renderer.prepare_points(scene, assets, a_camera())), 0)


def test_points_refuse_a_material_or_a_geometry_that_does_not_suit() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(dots([0.0, 0.0, 0.0]))
    var scene = a_scene_with_one_node()
    var renderer = Renderer(WIDTH, HEIGHT)
    var lit = assets.materials.add(Material(Color(255, 0, 0), kind=LAMBERT))
    scene.add_points(Points(geometry, lit, NodeId(0)))
    with assert_raises(contains="must be BASIC"):
        _ = renderer.prepare_points(scene, assets, a_camera())
    var wire = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, wireframe=True)
    )
    scene.points = List[Points]()
    scene.add_points(Points(geometry, wire, NodeId(0)))
    with assert_raises(contains="cannot be a wireframe"):
        _ = renderer.prepare_points(scene, assets, a_camera())
    var missing = assets.materials.add(
        points_material(Color(255, 0, 0), map=TextureId(9))
    )
    scene.points = List[Points]()
    scene.add_points(Points(geometry, missing, NodeId(0)))
    with assert_raises(contains="texture that is not there"):
        _ = renderer.prepare_points(scene, assets, a_camera())
    var no_mask = assets.materials.add(
        points_material(Color(255, 0, 0), alpha_map=TextureId(9))
    )
    scene.points = List[Points]()
    scene.add_points(Points(geometry, no_mask, NodeId(0)))
    with assert_raises(contains="alpha map that is not there"):
        _ = renderer.prepare_points(scene, assets, a_camera())
    var wrong_mask = assets.textures.add(a_mask(128, linear=False))
    var bad_mask = assets.materials.add(
        points_material(Color(255, 0, 0), alpha_map=wrong_mask)
    )
    scene.points = List[Points]()
    scene.add_points(Points(geometry, bad_mask, NodeId(0)))
    with assert_raises():
        _ = renderer.prepare_points(scene, assets, a_camera())
    # A map moved, tiled or turned is refused: the point samples it as
    # stored.
    var moved = checkerboard(4, 2, Color(255, 255, 255), Color(0, 0, 0))
    moved.offset = Vector2(0.5, 0)
    var shifted = assets.textures.add(moved^)
    var transformed = assets.materials.add(
        points_material(Color(255, 0, 0), map=shifted)
    )
    scene.points = List[Points]()
    scene.add_points(Points(geometry, transformed, NodeId(0)))
    with assert_raises(contains="transform is not the identity"):
        _ = renderer.prepare_points(scene, assets, a_camera())
    # An indexed geometry is a triangle list, not a point list.
    var indexed = dots([0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.5, 0.0])
    indexed.set_index([0, 1, 2])
    var mesh_shape = assets.geometries.add(indexed^)
    var plain = assets.materials.add(points_material(Color(255, 0, 0)))
    scene.points = List[Points]()
    scene.add_points(Points(mesh_shape, plain, NodeId(0)))
    with assert_raises(contains="cannot be indexed"):
        _ = renderer.prepare_points(scene, assets, a_camera())


def test_a_points_map_is_carried_only_when_it_will_be_sampled() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(dots([0.0, 0.0, 0.0]))
    var board = assets.textures.add(
        checkerboard(4, 2, Color(255, 255, 255), Color(0, 0, 0))
    )
    var mask = assets.textures.add(a_mask(128))
    var material = assets.materials.add(
        points_material(Color(255, 0, 0), map=board, alpha_map=mask)
    )
    var scene = a_scene_with_one_node()
    scene.add_points(Points(geometry, material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    # Following the material is the default, and carries both maps.
    var mapped = renderer.prepare_points(scene, assets, a_camera())
    assert_true(mapped[0].texture == board)
    assert_true(mapped[0].alpha_map == mask)
    renderer.set_shading(SHADE_LIT)
    var plain = renderer.prepare_points(scene, assets, a_camera())
    assert_true(plain[0].texture == NO_TEXTURE)
    assert_true(plain[0].alpha_map == NO_TEXTURE)


def test_opaque_points_are_prepared_before_blended_ones() raises:
    var assets = Assets()
    var near = assets.geometries.add(dots([0.0, 0.0, 0.5]))
    var far = assets.geometries.add(dots([0.0, 0.0, -0.5]))
    var solid = assets.materials.add(points_material(Color(255, 0, 0)))
    var glass = assets.materials.add(
        points_material(Color(0, 0, 255), opacity=0.5, transparent=True)
    )
    var scene = a_scene_with_one_node()
    var back = Object3D()
    back.set_position(0, 0, -0.5)
    var back_node = scene.add(back^)
    var front = Object3D()
    front.set_position(0, 0, 0.5)
    var front_node = scene.add(front^)
    scene.update()
    # Added blended first, far before near; prepared opaque first with
    # the nearest opaque first, then blended furthest first.
    scene.add_points(Points(far, glass, back_node))
    scene.add_points(Points(near, glass, front_node))
    scene.add_points(Points(far, solid, back_node))
    scene.add_points(Points(near, solid, front_node))
    var renderer = Renderer(WIDTH, HEIGHT)
    var prepared = renderer.prepare_points(scene, assets, a_camera())
    assert_equal(len(prepared), 4)
    assert_true(prepared[0].blend == OPAQUE)
    assert_true(prepared[1].blend == OPAQUE)
    assert_true(prepared[0].z < prepared[1].z)
    assert_true(prepared[2].blend == BLEND)
    assert_true(prepared[3].blend == BLEND)
    assert_true(prepared[2].z > prepared[3].z)


def test_rendered_points_land_where_the_camera_puts_them() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(dots([-0.5, 0.0, 0.0, 0.5, 0.5, 0.0]))
    var material = assets.materials.add(
        points_material(Color(255, 0, 0), size=PointSize(2.0))
    )
    var scene = a_scene_with_one_node()
    scene.add_points(Points(geometry, material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, a_camera())
    # Two points, four pixels each: at (4, 8) and (12, 4), each a two by
    # two square around a pixel corner.
    assert_equal(painted(image, 0), 8)
    assert_true(image.get_pixel(3, 7).r > 128)
    assert_true(image.get_pixel(4, 8).r > 128)
    assert_true(image.get_pixel(11, 3).r > 128)
    assert_true(image.get_pixel(12, 4).r > 128)
    assert_true(image.get_pixel(8, 8).r < 128)


def test_points_are_drawn_among_the_surfaces_by_depth() raises:
    # An opaque point behind a surface is hidden by it, a blended point
    # in front of a blended pane is drawn after it, and both are sorted
    # into the frame's one order.
    var assets = Assets()
    var floor = assets.geometries.add(plane(Length(4, METER), Length(4, METER)))
    var ahead = assets.geometries.add(dots([-0.5, 0.0, 0.5]))
    var nearer = assets.geometries.add(dots([-0.5, 0.0, 0.6]))
    var behind = assets.geometries.add(dots([0.5, 0.0, -0.5]))
    var surface = assets.materials.add(Material(Color(0, 0, 255), kind=BASIC))
    var ink = assets.materials.add(
        points_material(Color(255, 0, 0), size=PointSize(2.0))
    )
    var glass = assets.materials.add(
        points_material(
            Color(0, 255, 0), size=PointSize(2.0), opacity=0.5, transparent=True
        )
    )
    var scene = a_scene_with_one_node()
    scene.add_mesh(Mesh(floor, surface, NodeId(0)))
    scene.add_points(Points(ahead, ink, NodeId(0)))
    scene.add_points(Points(behind, ink, NodeId(0)))
    scene.add_points(Points(nearer, glass, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var frame = renderer.prepare_frame(scene, assets, a_camera())
    assert_equal(len(frame.points), 3)
    assert_equal(len(frame.draws), 4)
    assert_true(frame.draws[0].kind == DRAW_TRIANGLES)
    assert_true(frame.draws[1].kind == DRAW_POINTS)
    assert_true(frame.draws[2].kind == DRAW_POINTS)
    assert_true(frame.draws[3].kind == DRAW_POINTS)
    var image = renderer.render(scene, assets, a_camera())
    # The point in front shows red mixed with green; the one behind is
    # hidden under blue.
    assert_true(image.get_pixel(4, 8).r > 60)
    assert_true(image.get_pixel(4, 8).g > 60)
    assert_true(image.get_pixel(12, 8).b > 128)
    assert_true(image.get_pixel(12, 8).r < 60)


def test_points_with_no_vertices_prepare_nothing() raises:
    var assets = Assets()
    var geometry = assets.geometries.add(dots(List[Float32]()))
    var material = assets.materials.add(points_material(Color(255, 0, 0)))
    var scene = a_scene_with_one_node()
    scene.add_points(
        Points(geometry, material, NodeId(0), frustum_culled=False)
    )
    var renderer = Renderer(WIDTH, HEIGHT)
    assert_equal(len(renderer.prepare_points(scene, assets, a_camera())), 0)


# --- preparing sprites ------------------------------------------------------


def test_a_sprite_prepares_two_triangles_facing_the_camera() raises:
    var assets = Assets()
    var material = assets.materials.add(sprite_material(Color(255, 0, 0)))
    var scene = Scene()
    var node = Object3D()
    # Turned every which way, and scaled: the turn does nothing to a
    # sprite and the scale sets its size.
    node.set_euler(
        Angle(70.0, DEGREE), Angle(30.0, DEGREE), Angle(10.0, DEGREE)
    )
    node.set_scale(1.0, 0.5, 1.0)
    var placed = scene.add(node^)
    scene.update()
    scene.add_sprite(Sprite(material, placed))
    var renderer = Renderer(WIDTH, HEIGHT)
    var corners = renderer.prepare(scene, assets, a_camera())
    assert_equal(len(corners), 6)
    # A meter wide and half a meter tall at eight pixels a meter: four
    # pixels either side of the center along x, two along y.
    var left = Float32(100)
    var right = Float32(-100)
    var top = Float32(100)
    var bottom = Float32(-100)
    for index in range(6):
        assert_true(corners[index].kind == BASIC)
        assert_true(corners[index].blend == BLEND)
        left = min(left, corners[index].x)
        right = max(right, corners[index].x)
        top = min(top, corners[index].y)
        bottom = max(bottom, corners[index].y)
    assert_almost_equal(Float64(left), 4.0, atol=TOLERANCE)
    assert_almost_equal(Float64(right), 12.0, atol=TOLERANCE)
    assert_almost_equal(Float64(top), 6.0, atol=TOLERANCE)
    assert_almost_equal(Float64(bottom), 10.0, atol=TOLERANCE)
    # The bottom left corner carries the coordinate (0, 0) and the top
    # right (1, 1): the image is upright.
    for index in range(6):
        if corners[index].x < 5 and corners[index].y > 9:
            assert_almost_equal(Float64(corners[index].u), 0.0, atol=TOLERANCE)
            assert_almost_equal(Float64(corners[index].v), 0.0, atol=TOLERANCE)
        if corners[index].x > 11 and corners[index].y < 7:
            assert_almost_equal(Float64(corners[index].u), 1.0, atol=TOLERANCE)
            assert_almost_equal(Float64(corners[index].v), 1.0, atol=TOLERANCE)


def test_a_sprite_is_turned_and_anchored_by_its_material_and_center() raises:
    var assets = Assets()
    var turned = assets.materials.add(
        sprite_material(Color(255, 0, 0), rotation=Angle(90.0, DEGREE))
    )
    var scene = Scene()
    var node = Object3D()
    node.set_scale(1.0, 0.5, 1.0)
    var placed = scene.add(node^)
    scene.update()
    scene.add_sprite(Sprite(turned, placed))
    var renderer = Renderer(WIDTH, HEIGHT)
    var corners = renderer.prepare(scene, assets, a_camera())
    # A quarter turn swaps the extents: two pixels either side along x,
    # four along y.
    var left = Float32(100)
    var right = Float32(-100)
    var top = Float32(100)
    var bottom = Float32(-100)
    for index in range(6):
        left = min(left, corners[index].x)
        right = max(right, corners[index].x)
        top = min(top, corners[index].y)
        bottom = max(bottom, corners[index].y)
    assert_almost_equal(Float64(left), 6.0, atol=TOLERANCE)
    assert_almost_equal(Float64(right), 10.0, atol=TOLERANCE)
    assert_almost_equal(Float64(top), 4.0, atol=TOLERANCE)
    assert_almost_equal(Float64(bottom), 12.0, atol=TOLERANCE)
    # A center at the bottom left puts the node at the sprite's bottom
    # left corner: the square lies up and to the right of the origin.
    var plain = assets.materials.add(sprite_material(Color(255, 0, 0)))
    scene.sprites = List[Sprite]()
    scene.add_sprite(Sprite(plain, placed, center=Vector2(0, 0)))
    var anchored = renderer.prepare(scene, assets, a_camera())
    left = Float32(100)
    bottom = Float32(-100)
    for index in range(6):
        left = min(left, anchored[index].x)
        bottom = max(bottom, anchored[index].y)
    assert_almost_equal(Float64(left), 8.0, atol=TOLERANCE)
    assert_almost_equal(Float64(bottom), 8.0, atol=TOLERANCE)


def test_a_sprite_keeps_its_size_on_the_image_with_attenuation_off() raises:
    # Under perspective a unit sprite two meters away is four pixels
    # across, and one three meters away is smaller -- unless the
    # attenuation is off, when the scale is multiplied by the depth and
    # the divide undoes it: both are four pixels, as one at a depth of
    # one would be with it on.
    var assets = Assets()
    var shrinking = assets.materials.add(sprite_material(Color(255, 0, 0)))
    var fixed = assets.materials.add(
        sprite_material(Color(255, 0, 0), size_attenuation=False)
    )
    var scene = Scene()
    var near = scene.add(Object3D())
    var back = Object3D()
    back.set_position(0, 0, -1)
    var far = scene.add(back^)
    scene.update()
    scene.add_sprite(Sprite(shrinking, near))
    scene.add_sprite(Sprite(shrinking, far))
    var renderer = Renderer(WIDTH, HEIGHT)
    var camera = a_perspective_camera()
    var corners = renderer.prepare(scene, assets, camera)
    assert_equal(len(corners), 12)
    # Blended, so the further sprite is prepared first.
    assert_almost_equal(
        Float64(width_of(corners, 0)), 8.0 / 3.0, atol=TOLERANCE
    )
    assert_almost_equal(Float64(width_of(corners, 6)), 4.0, atol=TOLERANCE)
    scene.sprites = List[Sprite]()
    scene.add_sprite(Sprite(fixed, near))
    scene.add_sprite(Sprite(fixed, far))
    var held = renderer.prepare(scene, assets, camera)
    assert_almost_equal(Float64(width_of(held, 0)), 8.0, atol=TOLERANCE)
    assert_almost_equal(Float64(width_of(held, 6)), 8.0, atol=TOLERANCE)
    # Under a parallel projection the flag changes nothing.
    var flat = renderer.prepare(scene, assets, a_camera())
    assert_almost_equal(Float64(width_of(flat, 0)), 8.0, atol=TOLERANCE)
    assert_almost_equal(Float64(width_of(flat, 6)), 8.0, atol=TOLERANCE)


def width_of(corners: List[RasterVertex], first: Int) raises -> Float32:
    """Return how many pixels wide the six corners from `first` span."""
    var left = Float32(1000)
    var right = Float32(-1000)
    for index in range(first, first + 6):
        left = min(left, corners[index].x)
        right = max(right, corners[index].x)
    return right - left


def test_a_sprite_out_of_view_is_left_out_unless_it_says_otherwise() raises:
    var assets = Assets()
    var material = assets.materials.add(sprite_material(Color(255, 0, 0)))
    var scene = Scene()
    var away = Object3D()
    away.set_position(50, 0, 0)
    var node = scene.add(away^)
    scene.update()
    scene.add_sprite(Sprite(material, node))
    var renderer = Renderer(WIDTH, HEIGHT)
    assert_equal(len(renderer.prepare(scene, assets, a_camera())), 0)
    # Opting out sends it to the clipper, which throws the whole of it
    # away too.
    scene.sprites = List[Sprite]()
    scene.add_sprite(Sprite(material, node, frustum_culled=False))
    assert_equal(len(renderer.prepare(scene, assets, a_camera())), 0)
    # A sprite half off the side is cut there rather than thrown away.
    var edge = Object3D()
    edge.set_position(1.0, 0, 0)
    var edge_node = scene.add(edge^)
    scene.update()
    scene.sprites = List[Sprite]()
    scene.add_sprite(Sprite(material, edge_node))
    var cut = renderer.prepare(scene, assets, a_camera())
    assert_true(len(cut) >= 6)
    for index in range(len(cut)):
        assert_true(cut[index].x <= Float32(WIDTH) + 0.001)
    # And a node on a layer the camera does not see contributes nothing.
    var hidden = Layers()
    hidden.set(3)
    scene.node(edge_node).layers = hidden
    scene.update()
    assert_equal(len(renderer.prepare(scene, assets, a_camera())), 0)


def test_a_sprite_refuses_a_material_that_does_not_suit_it() raises:
    var assets = Assets()
    var scene = a_scene_with_one_node()
    var renderer = Renderer(WIDTH, HEIGHT)
    var lit = assets.materials.add(Material(Color(255, 0, 0), kind=LAMBERT))
    scene.add_sprite(Sprite(lit, NodeId(0)))
    with assert_raises(contains="must be BASIC"):
        _ = renderer.prepare(scene, assets, a_camera())
    var wire = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, wireframe=True)
    )
    scene.sprites = List[Sprite]()
    scene.add_sprite(Sprite(wire, NodeId(0)))
    with assert_raises(contains="cannot be a wireframe"):
        _ = renderer.prepare(scene, assets, a_camera())
    var missing = assets.materials.add(
        sprite_material(Color(255, 0, 0), map=TextureId(9))
    )
    scene.sprites = List[Sprite]()
    scene.add_sprite(Sprite(missing, NodeId(0)))
    with assert_raises(contains="texture that is not there"):
        _ = renderer.prepare(scene, assets, a_camera())


def test_a_sprite_is_never_a_wireframe_and_never_a_line() raises:
    # A scene with a wireframe mesh runs the wireframe pass, which reads
    # every draw and must skip the sprites.
    var assets = Assets()
    var box = assets.geometries.add(plane(Length(1, METER), Length(1, METER)))
    var wire = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, wireframe=True)
    )
    var badge = assets.materials.add(sprite_material(Color(0, 255, 0)))
    var scene = a_scene_with_one_node()
    scene.add_mesh(Mesh(box, wire, NodeId(0)))
    scene.add_sprite(Sprite(badge, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    var segments = renderer.prepare_lines(scene, assets, a_camera())
    # Five edges of the two triangles, two ends each, and nothing of the
    # sprite.
    assert_equal(len(segments), 10)
    var corners = renderer.prepare(scene, assets, a_camera())
    assert_equal(len(corners), 6)


def test_a_rendered_sprite_is_a_square_of_its_image() raises:
    var assets = Assets()
    var board = assets.textures.add(
        checkerboard(
            4, 2, Color(255, 255, 255), Color(0, 0, 0), REPEAT, NEAREST
        )
    )
    var material = assets.materials.add(
        sprite_material(Color(255, 255, 255), map=board, transparent=False)
    )
    var scene = a_scene_with_one_node()
    scene.add_sprite(Sprite(material, NodeId(0)))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(40, 40, 40))
    renderer.set_shading(SHADE_TEXTURE)
    var image = renderer.render(scene, assets, a_camera())
    # A meter square at eight pixels a meter: sixty-four pixels, half
    # white and half black, from (4, 4) to (11, 11).
    var white = 0
    var black = 0
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var pixel = image.get_pixel(x, y)
            if pixel.r == 255:
                white += 1
            if pixel.r == 0:
                black += 1
            if x < 4 or x > 11 or y < 4 or y > 11:
                assert_equal(pixel.r, UInt8(40))
    assert_equal(white, 32)
    assert_equal(black, 32)
    # The uv view shows the square's coordinates.
    renderer.set_shading(SHADE_UV)
    var view = renderer.render(scene, assets, a_camera())
    assert_true(view.get_pixel(11, 4).r > 200)
    assert_true(view.get_pixel(4, 11).r < 60)


def test_a_blended_sprite_is_sorted_among_the_blended_surfaces() raises:
    var assets = Assets()
    var floor = assets.geometries.add(plane(Length(4, METER), Length(4, METER)))
    var glass = assets.materials.add(
        Material(Color(0, 0, 255), kind=BASIC, opacity=0.5, transparent=True)
    )
    var badge = assets.materials.add(
        sprite_material(Color(255, 0, 0), opacity=0.5)
    )
    var scene = Scene()
    var pane_node = scene.add(Object3D())
    var front = Object3D()
    front.set_position(0, 0, 1)
    var front_node = scene.add(front^)
    scene.update()
    # The sprite is added first and sits nearer: it is drawn last.
    scene.add_sprite(Sprite(badge, front_node))
    scene.add_mesh(Mesh(floor, glass, pane_node))
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    var frame = renderer.prepare_frame(scene, assets, a_camera())
    # The pane's four triangles first, then the sprite's two.
    assert_equal(len(frame.draws), 2)
    assert_equal(frame.draws[0].count, 4)
    assert_equal(frame.draws[1].count, 2)
    assert_true(frame.corners[0].z > frame.corners[12].z)
    var image = renderer.render(scene, assets, a_camera())
    # Half red over half blue over black at the center: both show.
    var middle = image.get_pixel(8, 8)
    assert_true(middle.r > 128)
    assert_true(middle.b > 60)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
