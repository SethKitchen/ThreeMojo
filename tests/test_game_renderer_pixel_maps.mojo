# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The game renderer's maps read at each pixel: their texels, their
levels, how they wrap, the fog over them and the shadows they cast."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, BufferGeometry
from core.fog import exp2_fog
from core.object3d import Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light
from materials.material import PHONG, Material, MaterialId
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from render.srgb import SRGB
from render.texture import CLAMP, MIRROR, NEAREST, REPEAT, Texture, Wrap
from renderers.game_renderer import GameRenderer, STILL_SHADOWS
from std.testing import TestSuite, assert_true
from units.si import DEGREE, METER, SECOND, Angle, Duration, Length, PER_METER
from units.si import InverseLength

comptime WIDTH = 64
comptime HEIGHT = 48
comptime NOW = Duration(1.0, SECOND)


def _quad(
    half: Float32, u: Float32, v: Float32, x: Float32 = 0
) raises -> BufferGeometry:
    """Return a square `half` from its middle on each side, in the xy
    plane at `x`, facing +z, its texture coordinates from 0 to `u` and
    `v`."""
    var geometry = BufferGeometry()
    var positions: List[Float32] = [
        x - half,
        -half,
        0,
        x + half,
        -half,
        0,
        x + half,
        half,
        0,
        x - half,
        half,
        0,
    ]
    var normals = List[Float32](length=12, fill=0)
    for k in range(4):
        normals[k * 3 + 2] = 1
    var uvs: List[Float32] = [0, 0, u, 0, u, v, 0, v]
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index([0, 1, 2, 0, 2, 3])
    return geometry^


def _texture(
    width: Int, height: Int, var bytes: List[UInt8], wrap: Wrap
) raises -> Texture:
    """Return an sRGB texture of nearest texels with no mipmaps."""
    return Texture(width, height, bytes^, wrap, NEAREST, SRGB, False)


def _checker() raises -> Texture:
    """Return a 2 by 2 checker: black and white, white and black."""
    var bytes = List[UInt8]()
    for k in range(4):
        var on = UInt8(255) if k == 1 or k == 2 else UInt8(0)
        bytes.extend([on, on, on, UInt8(255)])
    return _texture(2, 2, bytes^, REPEAT)


def _camera() raises -> PerspectiveCamera:
    """Return a camera on +z, 4 meters out, that looks at the origin."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def _scene(
    mut assets: Assets, var geometry: BufferGeometry, material: MaterialId
) raises -> Scene:
    """Return a scene of one mesh, under a white ambient light and a sun
    behind the camera."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(geometry^),
            material,
            node,
            cast_shadow=True,
            receive_shadow=True,
        )
    )
    scene.add_light(ambient_light(Color(255, 255, 255), 1))
    var lamp = Object3D()
    lamp.set_position(0.3, 0.5, 5)
    var lamp_node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 1))
    scene.update()
    return scene^


def _red(image: Framebuffer, x: Int, y: Int) -> Int:
    """Return a pixel's red byte."""
    return Int(image.pixels[(y * image.width + x) * 4])


def test_a_map_is_read_at_each_pixel_when_asked() raises:
    var assets = Assets()
    var map = assets.textures.add(_checker())
    var paint = assets.materials.add(Material(Color(255, 255, 255), map=map))
    var scene = _scene(assets, _quad(1.2, 1, 1), paint)
    var fast = GameRenderer(WIDTH, HEIGHT)
    var vertex = fast.render(scene, assets, _camera(), NOW)
    fast.pixel_maps = True
    var pixel = fast.render(scene, assets, _camera(), NOW)
    # At each pixel, each quarter of the square shows one texel. The
    # square spans pixels 16.6 to 47.4 across and 8.6 to 39.4 down, so
    # these pixels sit at the quarters' middles.
    var left = 24
    var right = 39
    var low = 31
    var high = 16
    var lower_left = _red(pixel, left, low)
    var lower_right = _red(pixel, right, low)
    var upper_right = _red(pixel, right, high)
    assert_true(abs(lower_right - lower_left) > 80)
    assert_true(abs(upper_right - lower_left) < 12)
    # At each vertex, the four corners' texels mix across the square.
    assert_true(
        abs(_red(vertex, left, low) - _red(vertex, right, low))
        < abs(lower_right - lower_left)
    )


def test_a_white_map_under_fog_and_shadow_is_no_map() raises:
    var assets = Assets()
    var white = assets.textures.add(
        _texture(1, 1, List[UInt8](length=4, fill=255), REPEAT)
    )
    var mapped = assets.materials.add(Material(Color(200, 160, 120), map=white))
    var plain = assets.materials.add(Material(Color(200, 160, 120)))
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.pixel_maps = True
    fast.set_shadows(STILL_SHADOWS, 256)
    var images = List[Framebuffer]()
    for material in [mapped, plain]:
        var scene = _scene(assets, _quad(1.2, 1, 1), material)
        # A second square that takes no shadow, beside the first.
        var node = scene.add(Object3D())
        scene.add_mesh(
            Mesh(
                assets.geometries.add(_quad(0.5, 1, 1, 1.8)),
                material,
                node,
                receive_shadow=False,
            )
        )
        scene.fog = exp2_fog(
            Color(90, 110, 140), InverseLength(0.25, PER_METER)
        )
        scene.update()
        fast.refresh_shadows()
        images.append(fast.render(scene, assets, _camera(), NOW))
    var cx = WIDTH // 2
    var cy = HEIGHT // 2
    for x in [cx, cx + 20]:
        for k in range(3):
            var a = Int(images[0].pixels[(cy * WIDTH + x) * 4 + k])
            var b = Int(images[1].pixels[(cy * WIDTH + x) * 4 + k])
            assert_true(abs(a - b) <= 2)


def test_far_texels_mix_into_their_level() raises:
    var assets = Assets()
    var map = assets.textures.add(_checker())
    var paint = assets.materials.add(Material(Color(255, 255, 255), map=map))
    # The checker repeats 64 times across the square: each pixel covers
    # many texels, so the pixel reads a smaller level, a mean gray.
    var scene = _scene(assets, _quad(1.2, 64, 64), paint)
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.pixel_maps = True
    var image = fast.render(scene, assets, _camera(), NOW)
    var lowest = 255
    var highest = 0
    for dy in range(-5, 6):
        for dx in range(-5, 6):
            var r = _red(image, WIDTH // 2 + dx, HEIGHT // 2 + dy)
            lowest = min(lowest, r)
            highest = max(highest, r)
    assert_true(highest - lowest < 40)


def test_a_clamped_map_holds_its_edge_and_a_repeated_one_goes_round() raises:
    var assets = Assets()
    var black_white: List[UInt8] = [0, 0, 0, 255, 255, 255, 255, 255]
    var clamped = assets.textures.add(_texture(2, 1, black_white.copy(), CLAMP))
    var repeated = assets.textures.add(_texture(2, 1, black_white^, REPEAT))
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.pixel_maps = True
    var reds = List[Int]()
    for map in [clamped, repeated]:
        var paint = assets.materials.add(
            Material(Color(255, 255, 255), map=map)
        )
        # The coordinates run from 0 to 2 across: past 1 a clamped map
        # holds its white edge, and a repeated one starts again in black.
        var scene = _scene(assets, _quad(1.2, 2, 1), paint)
        var image = fast.render(scene, assets, _camera(), NOW)
        # Five eighths of the way across: u is 1.25.
        var span = Float32(WIDTH) * 0.34
        var x = Int(Float32(WIDTH) / 2 + span * 0.25)
        reds.append(_red(image, x, HEIGHT // 2))
    assert_true(reds[0] > reds[1] + 80)


def test_each_side_wraps_its_own_way_and_a_mirror_folds_back() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.pixel_maps = True
    # Black then white across, read from u 0 to 2: at u 1.75 a mirrored
    # map has folded back to black, where a clamped one holds white.
    var reds = List[Int]()
    for wrap in [MIRROR, CLAMP]:
        var black_white: List[UInt8] = [0, 0, 0, 255, 255, 255, 255, 255]
        var map = assets.textures.add(_texture(2, 1, black_white^, wrap))
        var paint = assets.materials.add(
            Material(Color(255, 255, 255), map=map)
        )
        var scene = _scene(assets, _quad(1.2, 2, 1), paint)
        var image = fast.render(scene, assets, _camera(), NOW)
        reds.append(_red(image, 43, HEIGHT // 2))
    assert_true(reds[1] > reds[0] + 80)
    # Black then white up, read from v 0 to 2, repeated along u and
    # clamped along v: at v 1.25 it reads as a map clamped both ways, and
    # not as one repeated both ways.
    var ups = List[Int]()
    for wraps in [(REPEAT, CLAMP), (CLAMP, CLAMP), (REPEAT, REPEAT)]:
        var black_white: List[UInt8] = [0, 0, 0, 255, 255, 255, 255, 255]
        var texture = _texture(1, 2, black_white^, wraps[0])
        texture.wrap_t = wraps[1]
        var map = assets.textures.add(texture^)
        var paint = assets.materials.add(
            Material(Color(255, 255, 255), map=map)
        )
        var scene = _scene(assets, _quad(1.2, 1, 2), paint)
        var image = fast.render(scene, assets, _camera(), NOW)
        ups.append(_red(image, WIDTH // 2, 20))
    assert_true(abs(ups[0] - ups[1]) < 8)
    assert_true(abs(ups[0] - ups[2]) > 80)


def test_a_shining_or_glowing_material_reads_its_map_at_each_vertex() raises:
    """A map read at each pixel would scale a highlight and a glow too, so
    such a material draws as it does with its map read at each vertex."""
    var assets = Assets()
    var gray = List[UInt8]()
    for _ in range(4):
        gray.extend([UInt8(60), UInt8(60), UInt8(60), UInt8(255)])
    var map = assets.textures.add(_texture(2, 2, gray^, REPEAT))
    var shiny = Material(
        Color(255, 255, 255),
        map=map,
        kind=PHONG,
        specular=Color(255, 255, 255),
        shininess=30,
    )
    var glowing = Material(
        Color(255, 255, 255), map=map, emissive=Color(200, 40, 10)
    )
    for material in [shiny^, glowing^]:
        var paint = assets.materials.add(material.copy())
        var scene = _scene(assets, _quad(1.2, 1, 1), paint)
        var fast = GameRenderer(WIDTH, HEIGHT)
        var vertex = fast.render(scene, assets, _camera(), NOW)
        fast.pixel_maps = True
        var pixel = fast.render(scene, assets, _camera(), NOW)
        assert_true(vertex.pixels == pixel.pixels)


def test_a_forgotten_map_is_read_again() raises:
    var assets = Assets()
    var black = List[UInt8](length=16, fill=0)
    for k in range(4):
        black[k * 4 + 3] = 255
    var map = assets.textures.add(_texture(2, 2, black^, REPEAT))
    var paint = assets.materials.add(Material(Color(255, 255, 255), map=map))
    var scene = _scene(assets, _quad(1.2, 1, 1), paint)
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.pixel_maps = True
    var before = fast.render(scene, assets, _camera(), NOW)
    # The texture turns white. The renderer keeps the map it read until it
    # forgets it.
    assets.textures.textures[map.value] = _texture(
        2, 2, List[UInt8](length=16, fill=255), REPEAT
    )
    var kept = fast.render(scene, assets, _camera(), NOW)
    assert_true(kept.pixels == before.pixels)
    fast.forget_maps()
    var after = fast.render(scene, assets, _camera(), NOW)
    var middle = (HEIGHT // 2) * WIDTH + WIDTH // 2
    assert_true(
        Int(after.pixels[middle * 4]) > Int(before.pixels[middle * 4]) + 100
    )


def test_tall_narrow_and_long_maps_keep_their_levels() raises:
    var assets = Assets()
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.pixel_maps = True
    # Two texels wide and four tall: its levels halve to one texel wide
    # before they are one tall.
    var tall = List[UInt8]()
    for _ in range(8):
        tall.extend([UInt8(255), UInt8(0), UInt8(0), UInt8(255)])
    # 65,536 texels long: more levels than are kept.
    var long = List[UInt8](length=65536 * 4, fill=0)
    for k in range(65536):
        long[k * 4 + 1] = 255
        long[k * 4 + 3] = 255
    var maps = [
        assets.textures.add(_texture(2, 4, tall^, REPEAT)),
        assets.textures.add(_texture(65536, 1, long^, REPEAT)),
    ]
    for k in range(2):
        var paint = assets.materials.add(
            Material(Color(255, 255, 255), map=maps[k])
        )
        var scene = _scene(assets, _quad(1.2, 3, 3), paint)
        # The same map twice: it is read once.
        var node = scene.add(Object3D())
        scene.add_mesh(
            Mesh(assets.geometries.add(_quad(0.3, 1, 1, 1.6)), paint, node)
        )
        scene.update()
        var image = fast.render(scene, assets, _camera(), NOW)
        var at = (HEIGHT // 2 * WIDTH + WIDTH // 2) * 4
        # The red map shows red, and the green one green.
        assert_true(
            Int(image.pixels[at + k]) > Int(image.pixels[at + 1 - k]) + 60
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
