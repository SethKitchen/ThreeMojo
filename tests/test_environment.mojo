# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for environments end to end: a material that reflects a cube
texture, a scene's background and environment, and a cube camera whose
six faces become the cube texture a mirror reflects.

Every cube here has six faces of six different flat colors, so a pixel
says which face a reflection or a sky read, and a rendered pixel is
checked against the face it must have read.
"""

from cameras.cube_camera import CubeCamera
from cameras.orthographic_camera import OrthographicCamera, centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import POSITION, BufferGeometry
from core.background import (
    Background,
    BackgroundKind,
    color_background,
    cube_background,
    no_background,
    texture_background,
)
from core.fog import linear_fog
from core.layers import Layers
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from geometries.sphere import sphere
from lights.light import ambient_light, directional_light
from materials.material import (
    ADD_OPERATION,
    BASIC,
    DOUBLE_SIDE,
    LAMBERT,
    MIX_OPERATION,
    Material,
    MaterialId,
    combine_light,
    line_dashed_material,
    points_material,
    sprite_material,
)
from math.vector3 import Vector3
from objects.line import LOOP, Line
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.cube_texture import (
    FACE_COUNT,
    NEGATIVE_X,
    NEGATIVE_Z,
    POSITIVE_X,
    POSITIVE_Z,
    CubeTexture,
    face_forward,
)
from render.cube_texture_store import (
    NO_CUBE_TEXTURE,
    SCENE_ENVIRONMENT,
    CubeTextureId,
)
from render.framebuffer import Color, FloatColor, Framebuffer
from render.rasterizer import SHADE_LIT, SHADE_TEXTURE, SHADE_UV
from render.rect import Rect
from render.srgb import SRGB
from render.target import RenderTarget
from render.texture import CLAMP, NEAREST, Texture
from render.texture_store import TextureId
from renderers.renderer import Renderer
from std.math import pi
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime WIDTH = 32
comptime HEIGHT = 24
comptime CLEAR = Color(9, 9, 9)

# One color per face, in face order.
comptime RED = Color(255, 0, 0)
comptime GREEN = Color(0, 255, 0)
comptime BLUE = Color(0, 0, 255)
comptime YELLOW = Color(255, 255, 0)
comptime CYAN = Color(0, 255, 255)
comptime MAGENTA = Color(255, 0, 255)


def face_colors() -> List[Color]:
    """Return the six face colors, in face order."""
    return [RED, GREEN, BLUE, YELLOW, CYAN, MAGENTA]


def solid(size: Int, color: Color) raises -> Texture:
    """Return a square texture of one color, clamped and nearest."""
    var pixels = List[UInt8]()
    for _ in range(size * size):
        pixels.append(color.r)
        pixels.append(color.g)
        pixels.append(color.b)
        pixels.append(color.a)
    return Texture(size, size, pixels^, CLAMP, NEAREST, SRGB, False)


def a_cube() raises -> CubeTexture:
    """Return a cube of six flat faces, one color each."""
    var faces = List[Texture]()
    for color in face_colors():
        faces.append(solid(2, color))
    return CubeTexture(faces^)


def assert_color(got: Color, want: Color) raises:
    """Assert two colors match in red, green and blue."""
    assert_equal(got.r, want.r)
    assert_equal(got.g, want.g)
    assert_equal(got.b, want.b)


def a_renderer() raises -> Renderer:
    """Return a small renderer cleared to `CLEAR`."""
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(CLEAR)
    return renderer^


def camera_at(x: Float32, y: Float32, z: Float32) raises -> PerspectiveCamera:
    """Return a camera at a point, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(x, y, z), Vector3(0, 0, 0))
    return camera^


def a_ball(mut scene: Scene, mut assets: Assets, paint: MaterialId) raises:
    """Put one sphere at the origin, drawn with `paint`.

    Coarse, on purpose: under the coverage instrumenter every triangle of
    every render is a run of probe records, and this suite renders a
    sphere many times over.
    """
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sphere(Length(0.9, METER), 12, 8)),
            paint,
            node,
        )
    )
    scene.update()


def lit(mut scene: Scene) raises:
    """Light the scene from the camera's side, straight on."""
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, Float32(pi)))


def center(image: Framebuffer) raises -> Color:
    """Return the pixel at the middle of the image."""
    return image.get_pixel(WIDTH // 2, HEIGHT // 2)


# --- a material that reflects -------------------------------------------------


def test_a_white_mirror_shows_the_face_behind_the_camera() raises:
    # The middle of a sphere faces the camera, so it reflects the camera:
    # the view turned back is the +z axis, and the +z face is cyan.
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var chrome = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, env_map=sky)
    )
    var scene = Scene()
    a_ball(scene, assets, chrome)
    var shown = renderer.render(scene, assets, camera_at(0, 0, 4))
    assert_color(center(shown), CYAN)
    # From the other side the +z face is behind the sphere, and the
    # camera sees the -z face reflected.
    var behind = renderer.render(scene, assets, camera_at(0, 0, -4))
    assert_color(center(behind), MAGENTA)


def test_a_multiply_tints_the_reflection_by_the_surface() raises:
    # three.js's default: the surface's light times the reflection. A
    # red basic surface times a cyan face is black.
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var red = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, env_map=sky)
    )
    var scene = Scene()
    a_ball(scene, assets, red)
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, 0, 4))),
        Color(0, 0, 0),
    )
    # And a yellow one times cyan keeps the green they share.
    var yellow = assets.materials.add(
        Material(Color(255, 255, 0), kind=BASIC, env_map=sky)
    )
    var again = Scene()
    a_ball(again, assets, yellow)
    assert_color(
        center(renderer.render(again, assets, camera_at(0, 0, 4))),
        Color(0, 255, 0),
    )


def test_a_mix_fades_toward_the_reflection_and_an_add_adds_it() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    # Red mixed halfway to cyan, in linear light: half of each channel.
    var mixed = assets.materials.add(
        Material(
            Color(255, 0, 0),
            kind=BASIC,
            env_map=sky,
            reflectivity=0.5,
            combine=MIX_OPERATION,
        )
    )
    var scene = Scene()
    a_ball(scene, assets, mixed)
    var half = center(renderer.render(scene, assets, camera_at(0, 0, 4)))
    # Half of linear one encodes to 188.
    assert_equal(half.r, UInt8(188))
    assert_equal(half.g, UInt8(188))
    assert_equal(half.b, UInt8(188))
    # Red plus cyan is white.
    var added = assets.materials.add(
        Material(
            Color(255, 0, 0), kind=BASIC, env_map=sky, combine=ADD_OPERATION
        )
    )
    var again = Scene()
    a_ball(again, assets, added)
    assert_color(
        center(renderer.render(again, assets, camera_at(0, 0, 4))),
        Color(255, 255, 255),
    )
    # A reflectivity of zero reflects nothing.
    var dull = assets.materials.add(
        Material(Color(255, 0, 0), kind=BASIC, env_map=sky, reflectivity=0.0)
    )
    var third = Scene()
    a_ball(third, assets, dull)
    assert_color(
        center(renderer.render(third, assets, camera_at(0, 0, 4))), RED
    )


def test_a_lit_surface_reflects_after_it_is_lit() raises:
    # A white lambert sphere lit straight on is white in the middle, and
    # times the cyan face is cyan; unlit it is black, and black times
    # anything is black. The reflection joins the lit light, as three.js
    # joins it after `reflectedLight`.
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var paint = assets.materials.add(
        Material(Color(255, 255, 255), kind=LAMBERT, env_map=sky)
    )
    var scene = Scene()
    lit(scene)
    a_ball(scene, assets, paint)
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, 0, 4))), CYAN
    )
    var dark = Scene()
    a_ball(dark, assets, paint)
    assert_color(
        center(renderer.render(dark, assets, camera_at(0, 0, 4))),
        Color(0, 0, 0),
    )


def test_a_reflection_is_a_texture_and_two_modes_ignore_it() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var red = assets.materials.add(
        Material(
            Color(255, 0, 0), kind=BASIC, env_map=sky, combine=ADD_OPERATION
        )
    )
    var scene = Scene()
    a_ball(scene, assets, red)
    renderer.set_shading(SHADE_LIT)
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, 0, 4))), RED
    )
    renderer.set_shading(SHADE_UV)
    var shown = center(renderer.render(scene, assets, camera_at(0, 0, 4)))
    assert_equal(shown.b, UInt8(0))


def test_a_material_can_reflect_the_scenes_environment() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var chrome = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, env_map=SCENE_ENVIRONMENT)
    )
    var scene = Scene()
    a_ball(scene, assets, chrome)
    # No environment: nothing to reflect, so the surface is its own color.
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, 0, 4))),
        Color(255, 255, 255),
    )
    scene.environment = sky
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, 0, 4))), CYAN
    )
    # A material with a cube of its own keeps it whatever the scene says.
    var own = assets.cube_textures.add(a_cube())
    var fixed = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, env_map=own)
    )
    scene.meshes = List[Mesh]()
    a_ball(scene, assets, fixed)
    scene.environment = NO_CUBE_TEXTURE
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, 0, 4))), CYAN
    )


def test_an_env_map_must_be_in_the_store() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var missing = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, env_map=CubeTextureId(3))
    )
    var scene = Scene()
    a_ball(scene, assets, missing)
    with assert_raises():
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))
    # Whatever the mode: a wrong asset, not a wrong frame.
    renderer.set_shading(SHADE_LIT)
    with assert_raises():
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))
    # And the scene's environment is checked the same way.
    renderer.set_shading(SHADE_TEXTURE)
    var shared = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, env_map=SCENE_ENVIRONMENT)
    )
    scene.meshes = List[Mesh]()
    a_ball(scene, assets, shared)
    scene.environment = CubeTextureId(4)
    with assert_raises():
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))


def test_lines_points_and_sprites_cannot_reflect() raises:
    # None has a surface to reflect from, so each pass refuses the
    # material rather than carrying an env map it would never read.
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    # Three points, unindexed, as a line or a point cloud wants them.
    var bare = BufferGeometry()
    bare.set_attribute(
        String(POSITION),
        BufferAttribute([-0.5, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.5, 0.0], 3),
    )
    var shape = assets.geometries.add(bare^)
    var dashed = line_dashed_material(Color(255, 255, 255))
    dashed.env_map = sky
    scene.add_line(Line(shape, assets.materials.add(dashed), node, mode=LOOP))
    with assert_raises():
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))
    scene.lines = List[Line]()
    var dots = points_material(Color(255, 255, 255))
    dots.env_map = sky
    scene.add_points(Points(shape, assets.materials.add(dots), node))
    with assert_raises():
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))
    scene.points = List[Points]()
    var badge = sprite_material()
    badge.env_map = sky
    scene.add_sprite(Sprite(assets.materials.add(badge), node))
    with assert_raises():
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))


# --- the scene's background ----------------------------------------------------


def test_a_color_background_replaces_the_clear_color() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, 0, 4))), CLEAR
    )
    scene.background = color_background(Color(30, 60, 90))
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, 0, 4))),
        Color(30, 60, 90),
    )
    assert_color(renderer.clear_color(scene), Color(30, 60, 90))
    scene.background = no_background()
    assert_color(renderer.clear_color(scene), CLEAR)
    # No image for either, so nothing to paint.
    assert_false(Bool(renderer.backdrop(scene, assets, camera_at(0, 0, 4))))


def test_a_texture_background_is_stretched_over_the_viewport() raises:
    # A 2x2 image of four colors fills the image: the top left quarter
    # of the frame is the top left texel, whatever the aspect.
    var renderer = a_renderer()
    var assets = Assets()
    var pixels = List[UInt8]()
    for tint in [RED, GREEN, BLUE, YELLOW]:
        pixels.append(tint.r)
        pixels.append(tint.g)
        pixels.append(tint.b)
        pixels.append(255)
    var quad = assets.textures.add(
        Texture(2, 2, pixels^, CLAMP, NEAREST, SRGB, False)
    )
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.background = texture_background(quad)
    var shown = renderer.render(scene, assets, camera_at(0, 0, 4))
    assert_color(shown.get_pixel(2, 2), RED)
    assert_color(shown.get_pixel(WIDTH - 3, 2), GREEN)
    assert_color(shown.get_pixel(2, HEIGHT - 3), BLUE)
    assert_color(shown.get_pixel(WIDTH - 3, HEIGHT - 3), YELLOW)
    # Behind everything: a sphere in front covers it.
    var paint = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    a_ball(scene, assets, paint)
    var covered = renderer.render(scene, assets, camera_at(0, 0, 4))
    assert_color(center(covered), Color(255, 255, 255))
    assert_color(covered.get_pixel(2, 2), RED)
    # Stretched over the viewport and not the target: with the viewport
    # on the left half, the whole image is in that half and the right
    # half keeps the clear color.
    scene.meshes = List[Mesh]()
    renderer.set_viewport(Rect(0, 0, WIDTH // 2, HEIGHT))
    var half = renderer.render(scene, assets, camera_at(0, 0, 4))
    assert_color(half.get_pixel(1, 1), RED)
    assert_color(half.get_pixel(WIDTH // 2 - 2, 1), GREEN)
    assert_color(half.get_pixel(WIDTH - 2, 1), CLEAR)
    # And the scissor keeps it out of the rows it excludes.
    renderer.set_viewport(Rect.whole(WIDTH, HEIGHT))
    renderer.set_scissor(Rect(0, 0, WIDTH, HEIGHT // 2))
    renderer.set_scissor_test(True)
    var cut = renderer.render(scene, assets, camera_at(0, 0, 4))
    assert_color(cut.get_pixel(1, HEIGHT - 2), BLUE)
    assert_color(cut.get_pixel(1, 1), CLEAR)


def test_a_cube_background_is_the_face_the_camera_looks_at() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.background = cube_background(sky)
    # Looking down -z from +z sees the -z face; from -x, the +x face.
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, 0, 4))), MAGENTA
    )
    assert_color(
        center(renderer.render(scene, assets, camera_at(-4, 0, 0))), RED
    )
    # The sky turns with the camera: a camera looking at the +y face's
    # top edge from below sees that face, not the horizon's.
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, -4, 0))), BLUE
    )
    # A parallel camera sees one direction everywhere.
    var flat = centered(
        Length(3.0, METER),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    flat.place(Vector3(4, 0, 0), Vector3(0, 0, 0))
    var parallel = renderer.render(scene, assets, flat)
    assert_color(parallel.get_pixel(0, 0), GREEN)
    assert_color(parallel.get_pixel(WIDTH - 1, HEIGHT - 1), GREEN)


def test_an_image_background_stays_inside_the_viewport_and_scissor() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.background = cube_background(sky)
    # The viewport is the left half; the right half keeps the clear color.
    renderer.set_viewport(Rect(0, 0, WIDTH // 2, HEIGHT))
    var shown = renderer.render(scene, assets, camera_at(0, 0, 4))
    assert_color(shown.get_pixel(2, HEIGHT // 2), MAGENTA)
    assert_color(shown.get_pixel(WIDTH - 2, HEIGHT // 2), CLEAR)
    # With the scissor on the bottom half, the top left keeps it too.
    renderer.set_viewport(Rect.whole(WIDTH, HEIGHT))
    renderer.set_scissor(Rect(0, 0, WIDTH, HEIGHT // 2))
    renderer.set_scissor_test(True)
    var cut = renderer.render(scene, assets, camera_at(0, 0, 4))
    assert_color(cut.get_pixel(2, HEIGHT - 2), MAGENTA)
    assert_color(cut.get_pixel(2, 1), CLEAR)
    # The backdrop says the same: transparent where nothing was painted.
    var painted = renderer.backdrop(scene, assets, camera_at(0, 0, 4))
    ref image = painted.value()
    assert_equal(image.get_pixel(2, 1).a, UInt8(0))
    assert_equal(image.get_pixel(2, HEIGHT - 2).a, UInt8(255))


def test_the_fog_does_not_reach_the_background() raises:
    # three.js does not fog its background, and nor does this: a sky is
    # not a surface at any depth.
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.background = cube_background(sky)
    scene.fog = linear_fog(
        Color(128, 128, 128), Length(0.0, METER), Length(0.5, METER)
    )
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, 0, 4))), MAGENTA
    )


def test_two_modes_clear_an_image_background_to_the_color() raises:
    # An image background is a texture, and the two modes that ignore
    # every texture ignore it.
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.background = cube_background(sky)
    renderer.set_shading(SHADE_LIT)
    assert_color(
        center(renderer.render(scene, assets, camera_at(0, 0, 4))), CLEAR
    )
    assert_false(Bool(renderer.backdrop(scene, assets, camera_at(0, 0, 4))))


def test_a_background_must_name_what_the_assets_hold() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.background = texture_background(TextureId(2))
    with assert_raises():
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))
    scene.background = cube_background(CubeTextureId(2))
    with assert_raises():
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))
    # And a background of no known kind is refused before anything is
    # cleared.
    scene.background = Background(BackgroundKind(9))
    with assert_raises():
        _ = renderer.render(scene, assets, camera_at(0, 0, 4))
    with assert_raises():
        _ = renderer.clear_color(scene)
    with assert_raises():
        _ = renderer.backdrop(scene, assets, camera_at(0, 0, 4))


# --- a cube camera ---------------------------------------------------------------


def a_room(mut scene: Scene, mut assets: Assets) raises -> List[Mesh]:
    """Return six walls around the origin, each one face's color, drawn
    from the inside."""
    var meshes = List[Mesh]()
    var colors = face_colors()
    var wall = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER))
    )
    for face in range(FACE_COUNT):
        var node = Object3D()
        var out = face_forward(face) * 3
        node.set_position(out.x, out.y, out.z)
        var id = scene.add(node^)
        # A plane faces +z; turn it to face the origin, as a camera would.
        scene.update()
        scene.look_at(id, Vector3(0, 0, 0))
        var paint = assets.materials.add(
            Material(colors[face], kind=BASIC, side=DOUBLE_SIDE)
        )
        var seen = Mesh(wall, paint, id)
        scene.add_mesh(seen)
        meshes.append(seen)
    scene.update()
    return meshes^


def test_a_cube_camera_renders_the_room_around_it() raises:
    # Six walls, each a face's color, seen from the middle: each face of
    # the cube camera's texture is the wall it looks at.
    var renderer = a_renderer()
    var assets = Assets()
    var scene = Scene()
    _ = a_room(scene, assets)
    var camera = CubeCamera(Length(0.1, METER), Length(20.0, METER), 8)
    var seen = renderer.render_cube(scene, assets, camera)
    assert_equal(seen.size, 8)
    var colors = face_colors()
    for face in range(FACE_COUNT):
        assert_color(seen.sample(face_forward(face)).encode(), colors[face])


def test_a_cube_camera_hides_a_mirror_with_layers() raises:
    # A mirror ball on layer one and a cube camera on layer zero: the
    # faces hold the room and not the ball, and the ball then reflects
    # the room the main camera sees around it.
    var renderer = a_renderer()
    var assets = Assets()
    var scene = Scene()
    _ = a_room(scene, assets)
    var camera = CubeCamera(Length(0.1, METER), Length(20.0, METER), 8)
    var seen = assets.cube_textures.add(
        renderer.render_cube(scene, assets, camera)
    )
    var chrome = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, env_map=seen)
    )
    var ball = Object3D()
    ball.layers.set(1)
    var ball_node = scene.add(ball^)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sphere(Length(0.9, METER), 12, 8)),
            chrome,
            ball_node,
        )
    )
    scene.update()
    # The cube camera on layer zero does not see the ball.
    var again = renderer.render_cube(scene, assets, camera)
    assert_color(again.sample(Vector3(0, 0, 1)).encode(), CYAN)
    # A cube camera on the ball's layer sees only the ball.
    var close = camera
    close.layers.set(1)
    var inside = renderer.render_cube(scene, assets, close)
    assert_color(inside.sample(Vector3(0, 0, 1)).encode(), CLEAR)
    # The main camera on both layers sees the ball reflecting the room:
    # the +z wall behind the camera, cyan, in the middle.
    var eye = camera_at(0, 0, 2.5)
    eye.layers.enable(1)
    var shown = renderer.render(scene, assets, eye)
    assert_color(center(shown), CYAN)


def test_a_cube_camera_rides_a_node_and_keeps_the_scene_background() raises:
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var scene = Scene()
    var stand = Object3D()
    stand.set_position(0, 0, 1)
    var node = scene.add(stand^)
    scene.update()
    scene.background = cube_background(sky)
    var camera = CubeCamera(Length(0.1, METER), Length(20.0, METER), 4)
    camera.attach(node)
    # Nothing but the sky: each face shows the sky's face.
    var seen = renderer.render_cube(scene, assets, camera)
    assert_color(seen.sample(Vector3(1, 0, 0)).encode(), RED)
    assert_color(seen.sample(Vector3(0, 0, -1)).encode(), MAGENTA)
    # A refused face refuses the cube: a stale scene has no node position.
    scene.node(node).set_position(0, 0, 2)
    with assert_raises():
        _ = renderer.render_cube(scene, assets, camera)


# --- the four the previous review asked for ---------------------------------


def an_ortho_camera(
    x: Float32, y: Float32, z: Float32
) raises -> OrthographicCamera:
    """Return a parallel camera at a point, looking at the origin."""
    var camera = centered(
        Length(3.0, METER),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(x, y, z), Vector3(0, 0, 0))
    return camera^


def test_a_parallel_camera_reflects_along_its_own_axis() raises:
    # `envmap_fragment` special-cases a parallel projection where the
    # matcap does not: under `isOrthographic` it takes the view's third
    # column, and only otherwise the way to `cameraPosition`.
    #
    # The consequence is what this pins. A parallel camera's rays do not
    # converge, so sliding it along its own axis cannot change which way
    # any surface is seen, and cannot change what that surface reflects.
    # Measuring from the camera's *position* made the reflection swim as
    # the camera moved.
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var chrome = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, env_map=sky)
    )
    var scene = Scene()
    a_ball(scene, assets, chrome)
    var near = renderer.render(scene, assets, an_ortho_camera(0, 0, 4))
    var far = renderer.render(scene, assets, an_ortho_camera(0, 0, 40))
    # The middle faces the camera, so it reflects the +z face, cyan.
    assert_color(center(near), CYAN)
    assert_color(center(far), CYAN)
    # And not only in the middle: no pixel may move when the camera does.
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_color(near.get_pixel(x, y), far.get_pixel(x, y))


def test_a_sky_ray_does_not_depend_on_where_the_camera_stands() raises:
    # A cube background is read in the direction a pixel's ray leaves the
    # camera. A direction has no origin, so translating the camera cannot
    # change one. Unprojecting the near and the far point into *world*
    # space put the camera's position into both, and a scene far from the
    # origin spent its Float32 significand on that offset.
    var renderer = a_renderer()
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var scene = Scene()
    scene.background = cube_background(sky)
    scene.update()
    var here = renderer.render(scene, assets, camera_at(0, 0, 4))
    # The same camera orientation, a long way out. `camera_at` looks at
    # the origin, so build this one by hand to keep the direction fixed.
    var moved = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    moved.place(Vector3(0, 0, 100004), Vector3(0, 0, 100000))
    var there = renderer.render(scene, assets, moved)
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_color(here.get_pixel(x, y), there.get_pixel(x, y))


def test_a_dim_surface_keeps_its_light_beside_a_bright_reflection() raises:
    # `mix` written as `a + (b - a) * t` loses the small side when the two
    # are decades apart in Float32: the difference carries the larger
    # exponent, and adding the smaller back rounds it away. A reflection
    # is where that happens -- a bright sky over a dim surface -- and the
    # weighted sum keeps it.
    var dim = FloatColor(1.0e-7, 1.0e-7, 1.0e-7, 1.0)
    var bright = FloatColor(1.0e7, 1.0e7, 1.0e7, 1.0)
    # Almost all surface: the reflection contributes a millionth, and the
    # surface's own light must still be in the answer.
    var joined = combine_light(dim, bright, 1.0e-9, MIX_OPERATION)
    assert_true(
        joined.r > 0.0,
        "the surface's own light was rounded away by the reflection",
    )
    # And the arithmetic is still `mix`: a reflectivity of zero is the
    # surface, and of one is the reflection.
    assert_equal(combine_light(dim, bright, 0.0, MIX_OPERATION).r, dim.r)
    assert_equal(combine_light(dim, bright, 1.0, MIX_OPERATION).r, bright.r)


def test_a_refused_background_does_not_erase_the_target_first() raises:
    # A target is a buffer a caller keeps and draws several views into.
    # The background is the last thing that can refuse a frame, and it
    # used to be asked *after* the clear, so a refused background wiped a
    # view that was already drawn and then raised. Everything that can be
    # refused is now asked before anything is written.
    var renderer = a_renderer()
    var assets = Assets()
    var paint = assets.materials.add(Material(RED, kind=BASIC))
    var scene = Scene()
    a_ball(scene, assets, paint)
    var target = RenderTarget(WIDTH, HEIGHT, CLEAR)
    renderer.render_into(target, scene, assets, camera_at(0, 0, 4))
    var drawn = target.shown(WIDTH // 2, HEIGHT // 2)
    assert_color(drawn, RED)
    # Now name a cube texture that is not there and draw again.
    scene.background = cube_background(CubeTextureId(7))
    with assert_raises(contains="not there"):
        renderer.render_into(target, scene, assets, camera_at(0, 0, 4))
    # The view that was already there is untouched.
    assert_color(target.shown(WIDTH // 2, HEIGHT // 2), drawn)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
