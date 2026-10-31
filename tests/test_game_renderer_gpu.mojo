# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The game renderer's frame for a GPU: the triangles it packs, the shadow
maps, the maps and the sky it describes, and the numbers a host reads them
by."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import color_background
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import NORMAL, POSITION, UV, BufferGeometry
from core.fog import exp2_fog
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.srgb import SRGB
from render.texture import MIRROR, NEAREST, Texture
from renderers.game_gpu import (
    FLOAT_BIAS,
    FLOAT_COUNT,
    FLOAT_COVER_BRIGHT,
    FLOAT_COVER_FOG,
    FLOAT_COVER_GLOOM,
    FLOAT_COVER_GRAY,
    FLOAT_COVER_MIST,
    FLOAT_COVER_VEIL,
    FLOAT_EXPOSURE,
    FLOAT_FOG_BLUE,
    FLOAT_FOG_GREEN,
    FLOAT_FOG_RED,
    FLOAT_MOVING_PER_METER,
    FLOAT_NIGHT_ACROSS,
    FLOAT_NIGHT_D00,
    FLOAT_NIGHT_DAY,
    FLOAT_NIGHT_DOWN,
    FLOAT_NIGHT_DUSK,
    FLOAT_NIGHT_GLOW,
    FLOAT_NIGHT_SKY,
    FLOAT_NIGHT_STAR_GRID,
    FLOAT_NIGHT_STAR_RATE,
    FLOAT_NIGHT_STARS,
    FLOAT_STILL_PER_METER,
    FLOAT_WATER_CLIP,
    FLOAT_WATER_EYE,
    FLOAT_WATER_NIGHT,
    FLOAT_WATER_SHARE,
    GpuFrame,
    INT_COUNT,
    INT_COVER_COLUMNS,
    INT_COVER_ROWS,
    INT_COVER_STEP,
    INT_DEPTH,
    INT_FOG,
    INT_HEIGHT,
    INT_MAP_FLOATS,
    INT_MAP_LEVELS,
    INT_MAP_SLOTS,
    INT_MOVING_MADE,
    INT_MOVING_ON,
    INT_MOVING_SIZE,
    INT_MOVING_STRIDE,
    INT_NIGHT_ON,
    INT_PASSES,
    INT_SKY_COLUMNS,
    INT_SKY_ROWS,
    INT_SKY_STEP,
    INT_SMOOTH_ON,
    INT_STILL_MADE,
    INT_STILL_ON,
    INT_STILL_SIZE,
    INT_STILL_STRIDE,
    INT_TRIANGLES,
    INT_VERTICES,
    INT_WATER_BED_MADE,
    INT_WATER_CAUSTIC_FLOATS,
    INT_WATER_GRID_HEIGHT,
    INT_WATER_GRID_WIDTH,
    INT_WATER_ON,
    INT_WATER_PEBBLE_FLOATS,
    INT_WATER_RIPPLE_FLOATS,
    INT_WATER_RIPPLE_MADE,
    INT_WATER_STEP,
    INT_WATER_SURFACE_FLOATS,
    INT_WATER_SURFACE_MADE,
    INT_WATER_WORDS,
    INT_WIDTH,
    POINTER_CODES,
    POINTER_COLOR,
    POINTER_CORNERS,
    POINTER_COUNT,
    POINTER_COVER,
    POINTER_DEPTH,
    POINTER_MAP_COUNTS,
    POINTER_MAP_FIRSTS,
    POINTER_MAP_HEIGHTS,
    POINTER_MAP_STARTS,
    POINTER_MAP_TEXELS,
    POINTER_MAP_WIDTHS,
    POINTER_MAP_WRAPS_S,
    POINTER_MAP_WRAPS_T,
    POINTER_MOVING_CLIP,
    POINTER_MOVING_DEPTH,
    POINTER_SKY,
    POINTER_STILL_CLIP,
    POINTER_STILL_DEPTH,
    POINTER_VERTICES,
    POINTER_WATER_CAUSTIC,
    POINTER_WATER_PEBBLE,
    POINTER_WATER_RIPPLE,
    POINTER_WATER_SURFACE,
    POINTER_WATER_WORDS,
    VERTEX_FLOATS,
)
from renderers.game_renderer import (
    CACHED_SHADOWS,
    FULL_SHADOWS,
    GameRenderer,
    LEVEL_CODE,
    STILL_SHADOWS,
)
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true
from units.si import (
    DEGREE,
    METER,
    PER_METER,
    SECOND,
    Angle,
    Duration,
    InverseLength,
    Length,
)

comptime WIDTH = 80
comptime HEIGHT = 50
comptime NOW = Duration(1.5, SECOND)


def _camera(eye: Vector3, target: Vector3) raises -> PerspectiveCamera:
    """Return a camera at `eye` that looks at `target`."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(eye, target)
    return camera^


def _above() raises -> PerspectiveCamera:
    """Return a camera above the floor, looking down at its middle."""
    return _camera(Vector3(0, 6, 4), Vector3(0, 0, 0))


def _scene(mut assets: Assets) raises -> Scene:
    """Return a floor 8 meters on a side with a block above its middle, both
    casting and receiving, under a sun and an ambient light."""
    var scene = Scene()
    var flat = Object3D()
    flat.set_euler(Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE))
    var ground = scene.add(flat^)
    var floor = assets.geometries.add(
        plane(Length(8.0, METER), Length(8.0, METER), 4, 4)
    )
    var paint = assets.materials.add(Material(Color(180, 160, 140)))
    scene.add_mesh(Mesh(floor, paint, ground, receive_shadow=True))
    var lift = Object3D()
    lift.set_position(0, 1.0, 0)
    var lift_node = scene.add(lift^)
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var red = assets.materials.add(Material(Color(200, 60, 60)))
    scene.add_mesh(
        Mesh(block, red, lift_node, cast_shadow=True, receive_shadow=True)
    )
    scene.add_light(ambient_light(Color(255, 255, 255), 0.3))
    var lamp = Object3D()
    lamp.set_position(-2, 5, 1)
    var lamp_node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 1.5))
    scene.background = color_background(Color(120, 170, 230))
    scene.update()
    return scene^


def _ints(address: Int64) -> Pointer[Int32, ImmutAnyOrigin]:
    """Return the integers at an address."""
    return Pointer[Int32, ImmutAnyOrigin](unsafe_from_address=Int(address))


def _floats(address: Int64) -> Pointer[Float32, ImmutAnyOrigin]:
    """Return the floats at an address."""
    return Pointer[Float32, ImmutAnyOrigin](unsafe_from_address=Int(address))


def _frame_of(
    mut fast: GameRenderer, scene: Scene, assets: Assets
) raises -> GpuFrame:
    """Prepare a frame as seen from above, and describe it."""
    fast.prepare_gpu(scene, assets, _above(), NOW)
    return fast.gpu_frame()


def test_a_prepared_frame_holds_the_triangles_the_cpu_draws() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var fast = GameRenderer(WIDTH, HEIGHT)
    var frame = _frame_of(fast, scene, assets)
    # The CPU's own frame draws the same triangles.
    var cpu = GameRenderer(WIDTH, HEIGHT)
    _ = cpu.render(scene, assets, _above(), NOW)
    assert_true(fast.triangles > 0)
    assert_equal(fast.triangles, cpu.triangles)
    assert_equal(fast.draw_count, cpu.draw_count)
    assert_equal(Int(frame.ints[INT_WIDTH]), WIDTH)
    assert_equal(Int(frame.ints[INT_HEIGHT]), HEIGHT)
    assert_equal(Int(frame.ints[INT_TRIANGLES]), fast.triangles)
    var vertices = Int(frame.ints[INT_VERTICES])
    assert_true(vertices >= fast.vertex_count)
    assert_equal(len(fast.timings), 8)
    # Every corner names a vertex, and every vertex is in front of the eye:
    # the setup cut what was behind it.
    var corners = _ints(frame.pointers[POINTER_CORNERS])
    var points = _floats(frame.pointers[POINTER_VERTICES])
    for k in range(fast.triangles * 3):
        var corner = Int(corners[unsafe_offset=k])
        assert_true(corner >= 0 and corner < vertices)
        assert_true(points[unsafe_offset=corner * VERTEX_FLOATS + 3] > 0)
    # With no map read at each pixel, no triangle has a map code.
    var codes = _floats(frame.pointers[POINTER_CODES])
    for k in range(fast.triangles):
        assert_equal(codes[unsafe_offset=k], Float32(-1))
    assert_equal(Int(frame.ints[INT_MAP_SLOTS]), 0)


def test_the_sky_and_the_fog_are_described() raises:
    var assets = Assets()
    var scene = _scene(assets)
    scene.fog = exp2_fog(Color(200, 210, 220), InverseLength(0.01, PER_METER))
    var fast = GameRenderer(WIDTH, HEIGHT, 1.25)
    fast.sky_step = 8
    var frame = _frame_of(fast, scene, assets)
    assert_equal(Int(frame.ints[INT_SKY_STEP]), 8)
    assert_equal(Int(frame.ints[INT_SKY_COLUMNS]), 11)
    assert_equal(Int(frame.ints[INT_SKY_ROWS]), 8)
    assert_equal(Int(frame.ints[INT_FOG]), 1)
    assert_equal(frame.floats[FLOAT_EXPOSURE], Float32(1.25))
    assert_equal(frame.floats[FLOAT_BIAS], fast.shadow_bias)
    # The fog's color is linear: a bluish gray has the most blue.
    assert_true(frame.floats[FLOAT_FOG_RED] > 0)
    assert_true(frame.floats[FLOAT_FOG_GREEN] > frame.floats[FLOAT_FOG_RED])
    assert_true(frame.floats[FLOAT_FOG_BLUE] > frame.floats[FLOAT_FOG_GREEN])
    # The sky's grid holds three floats a sample, and they are the
    # background's, linear.
    var sky = _floats(frame.pointers[POINTER_SKY])
    assert_true(sky[unsafe_offset=0] > 0)
    assert_true(sky[unsafe_offset=2] > sky[unsafe_offset=0])
    var bare = _scene(assets)
    var none = _frame_of(fast, bare, assets)
    assert_equal(Int(none.ints[INT_FOG]), 0)


def test_the_shadow_maps_are_described_and_counted() raises:
    var assets = Assets()
    var scene = _scene(assets)
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.shadow_reach = 8
    fast.moving_reach = 4
    fast.moving_size = 100
    # With no shadows, no map shades the frame.
    var plain = _frame_of(fast, scene, assets)
    assert_equal(Int(plain.ints[INT_STILL_ON]), 0)
    assert_equal(Int(plain.ints[INT_MOVING_ON]), 0)
    fast.set_shadows(STILL_SHADOWS, 256)
    var still = _frame_of(fast, scene, assets)
    assert_equal(Int(still.ints[INT_STILL_ON]), 1)
    assert_equal(Int(still.ints[INT_MOVING_ON]), 0)
    assert_equal(Int(still.ints[INT_STILL_SIZE]), 256)
    assert_true(Int(still.ints[INT_STILL_STRIDE]) >= 256)
    assert_equal(Int(still.ints[INT_STILL_MADE]), 1)
    assert_true(still.floats[FLOAT_STILL_PER_METER] > 0)
    assert_true(still.pointers[POINTER_STILL_DEPTH] != 0)
    assert_true(still.pointers[POINTER_STILL_CLIP] != 0)
    # The still map is kept: it is not drawn again.
    var again = _frame_of(fast, scene, assets)
    assert_equal(Int(again.ints[INT_STILL_MADE]), 1)
    # The moving map is drawn at each frame.
    fast.set_moving(scene, [scene.meshes[1].node])
    fast.set_shadows(CACHED_SHADOWS, 256)
    var cached = _frame_of(fast, scene, assets)
    assert_equal(Int(cached.ints[INT_MOVING_ON]), 1)
    assert_equal(Int(cached.ints[INT_MOVING_SIZE]), 100)
    assert_true(Int(cached.ints[INT_MOVING_STRIDE]) >= 100)
    assert_true(cached.floats[FLOAT_MOVING_PER_METER] > 0)
    assert_true(cached.pointers[POINTER_MOVING_DEPTH] != 0)
    assert_true(cached.pointers[POINTER_MOVING_CLIP] != 0)
    var made = Int(cached.ints[INT_MOVING_MADE])
    var next = _frame_of(fast, scene, assets)
    assert_equal(Int(next.ints[INT_MOVING_MADE]), made + 1)
    assert_equal(
        Int(next.ints[INT_STILL_MADE]), Int(cached.ints[INT_STILL_MADE])
    )
    # Full shadows draw both at each frame.
    fast.set_shadows(FULL_SHADOWS, 128)
    var full = _frame_of(fast, scene, assets)
    var after = _frame_of(fast, scene, assets)
    assert_equal(
        Int(after.ints[INT_STILL_MADE]), Int(full.ints[INT_STILL_MADE]) + 1
    )


def _quad(half: Float32) raises -> BufferGeometry:
    """Return a square `half` from its middle on each side, in the xy plane,
    facing +z, its texture coordinates from 0 to 1."""
    var geometry = BufferGeometry()
    var positions: List[Float32] = [
        -half,
        -half,
        0,
        half,
        -half,
        0,
        half,
        half,
        0,
        -half,
        half,
        0,
    ]
    var normals = List[Float32](length=12, fill=0)
    for k in range(4):
        normals[k * 3 + 2] = 1
    var uvs: List[Float32] = [0, 0, 1, 0, 1, 1, 0, 1]
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index([0, 1, 2, 0, 2, 3])
    return geometry^


def test_a_map_read_at_each_pixel_is_described_with_its_levels() raises:
    var assets = Assets()
    var bytes = List[UInt8]()
    for k in range(16):
        bytes.extend([UInt8(k * 16), UInt8(255 - k * 16), UInt8(128), 255])
    var map = assets.textures.add(
        Texture(4, 4, bytes^, MIRROR, NEAREST, SRGB, False)
    )
    var paint = assets.materials.add(Material(Color(255, 255, 255), map=map))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(assets.geometries.add(_quad(1.2)), paint, node))
    scene.add_light(ambient_light(Color(255, 255, 255), 1))
    scene.update()
    var fast = GameRenderer(WIDTH, HEIGHT)
    fast.pixel_maps = True
    var camera = _camera(Vector3(0, 0, 4), Vector3(0, 0, 0))
    fast.prepare_gpu(scene, assets, camera, NOW)
    var frame = fast.gpu_frame()
    assert_equal(Int(frame.ints[INT_MAP_SLOTS]), 1)
    # A 4 by 4 map halves to 2 by 2 and 1 by 1: three levels, and the
    # texels of all of them, three floats each.
    assert_equal(Int(frame.ints[INT_MAP_LEVELS]), 3)
    assert_equal(Int(frame.ints[INT_MAP_FLOATS]), (16 + 4 + 1) * 3)
    var firsts = _ints(frame.pointers[POINTER_MAP_FIRSTS])
    var counts = _ints(frame.pointers[POINTER_MAP_COUNTS])
    var widths = _ints(frame.pointers[POINTER_MAP_WIDTHS])
    var heights = _ints(frame.pointers[POINTER_MAP_HEIGHTS])
    var starts = _ints(frame.pointers[POINTER_MAP_STARTS])
    assert_equal(Int(firsts[unsafe_offset=0]), 0)
    assert_equal(Int(counts[unsafe_offset=0]), 3)
    assert_equal(Int(widths[unsafe_offset=0]), 4)
    assert_equal(Int(widths[unsafe_offset=2]), 1)
    assert_equal(Int(heights[unsafe_offset=1]), 2)
    assert_equal(Int(starts[unsafe_offset=1]), 16 * 3)
    assert_equal(
        Int(_ints(frame.pointers[POINTER_MAP_WRAPS_S])[unsafe_offset=0]), 2
    )
    assert_equal(
        Int(_ints(frame.pointers[POINTER_MAP_WRAPS_T])[unsafe_offset=0]), 2
    )
    assert_true(frame.pointers[POINTER_MAP_TEXELS] != 0)
    # Each triangle of the quad reads the map: its code is the slot times
    # `LEVEL_CODE`, plus a level that the map has.
    var codes = _floats(frame.pointers[POINTER_CODES])
    assert_true(fast.triangles >= 2)
    for k in range(fast.triangles):
        var code = codes[unsafe_offset=k]
        # Slot 0, level 0: a texel is far larger than a pixel here.
        assert_equal(code, Float32(0))


def test_a_frame_with_no_triangle_is_prepared() raises:
    var assets = Assets()
    # Seen from below, the floor's front faces away, and every triangle of it
    # is culled: there are draws and no triangle.
    var scene = _scene(assets)
    var fast = GameRenderer(WIDTH, HEIGHT)
    scene.meshes[1].cast_shadow = False
    var block = scene.meshes[1].node
    scene.node(block).visible = False
    scene.update()
    fast.prepare_gpu(
        scene, assets, _camera(Vector3(0, -6, 4), Vector3(0, 0, 0)), NOW
    )
    var frame = fast.gpu_frame()
    assert_equal(fast.triangles, 0)
    assert_equal(Int(frame.ints[INT_TRIANGLES]), 0)
    # No mesh at all.
    var bare = Scene()
    bare.add_light(ambient_light(Color(255, 255, 255), 0.5))
    bare.update()
    fast.prepare_gpu(bare, assets, _above(), NOW)
    assert_equal(fast.draw_count, 0)
    assert_equal(Int(fast.gpu_frame().ints[INT_TRIANGLES]), 0)


def test_a_frame_that_is_not_prepared_describes_nothing() raises:
    var empty = GpuFrame()
    assert_equal(len(empty.ints), INT_COUNT)
    assert_equal(len(empty.floats), FLOAT_COUNT)
    assert_equal(len(empty.pointers), POINTER_COUNT)
    for k in range(len(empty.ints)):
        assert_equal(Int(empty.ints[k]), 0)
    for k in range(len(empty.pointers)):
        assert_equal(Int(empty.pointers[k]), 0)


def _numbered(header: String, name: String, value: Int) -> Bool:
    """Return whether the header gives a name the number."""
    var at = header.find(name + " = ")
    if at < 0:
        return False
    var bytes = header.as_bytes()
    var place = at + name.byte_length() + 3
    var digits = 0
    var number = 0
    while place < len(bytes) and bytes[place] >= 48 and bytes[place] <= 57:
        number = number * 10 + Int(bytes[place]) - 48
        digits += 1
        place += 1
    return digits > 0 and number == value


def test_the_numbers_are_the_headers() raises:
    # window/threemojo.h lists these numbers for a host that is not in Mojo.
    var header = Path("window/threemojo.h").read_text()
    var ints: List[Tuple[String, Int]] = [
        ("WIDTH", INT_WIDTH),
        ("HEIGHT", INT_HEIGHT),
        ("VERTICES", INT_VERTICES),
        ("TRIANGLES", INT_TRIANGLES),
        ("SKY_COLUMNS", INT_SKY_COLUMNS),
        ("SKY_ROWS", INT_SKY_ROWS),
        ("SKY_STEP", INT_SKY_STEP),
        ("FOG", INT_FOG),
        ("STILL_ON", INT_STILL_ON),
        ("STILL_SIZE", INT_STILL_SIZE),
        ("STILL_STRIDE", INT_STILL_STRIDE),
        ("STILL_MADE", INT_STILL_MADE),
        ("MOVING_ON", INT_MOVING_ON),
        ("MOVING_SIZE", INT_MOVING_SIZE),
        ("MOVING_STRIDE", INT_MOVING_STRIDE),
        ("MOVING_MADE", INT_MOVING_MADE),
        ("MAP_SLOTS", INT_MAP_SLOTS),
        ("MAP_LEVELS", INT_MAP_LEVELS),
        ("MAP_FLOATS", INT_MAP_FLOATS),
        ("PASSES", INT_PASSES),
        ("DEPTH", INT_DEPTH),
        ("COVER_COLUMNS", INT_COVER_COLUMNS),
        ("COVER_ROWS", INT_COVER_ROWS),
        ("COVER_STEP", INT_COVER_STEP),
        ("NIGHT_ON", INT_NIGHT_ON),
        ("SMOOTH_ON", INT_SMOOTH_ON),
        ("WATER_ON", INT_WATER_ON),
        ("WATER_STEP", INT_WATER_STEP),
        ("WATER_GRID_WIDTH", INT_WATER_GRID_WIDTH),
        ("WATER_GRID_HEIGHT", INT_WATER_GRID_HEIGHT),
        ("WATER_SURFACE_MADE", INT_WATER_SURFACE_MADE),
        ("WATER_RIPPLE_MADE", INT_WATER_RIPPLE_MADE),
        ("WATER_BED_MADE", INT_WATER_BED_MADE),
        ("WATER_SURFACE_FLOATS", INT_WATER_SURFACE_FLOATS),
        ("WATER_RIPPLE_FLOATS", INT_WATER_RIPPLE_FLOATS),
        ("WATER_CAUSTIC_FLOATS", INT_WATER_CAUSTIC_FLOATS),
        ("WATER_PEBBLE_FLOATS", INT_WATER_PEBBLE_FLOATS),
        ("WATER_WORDS", INT_WATER_WORDS),
        ("COUNT", INT_COUNT),
    ]
    for entry in ints:
        assert_true(
            _numbered(header, "TM_VILLAGE_INT_" + entry[0], entry[1]),
            "TM_VILLAGE_INT_" + entry[0],
        )
    var floats: List[Tuple[String, Int]] = [
        ("EXPOSURE", FLOAT_EXPOSURE),
        ("BIAS", FLOAT_BIAS),
        ("FOG_RED", FLOAT_FOG_RED),
        ("FOG_GREEN", FLOAT_FOG_GREEN),
        ("FOG_BLUE", FLOAT_FOG_BLUE),
        ("STILL_PER_METER", FLOAT_STILL_PER_METER),
        ("MOVING_PER_METER", FLOAT_MOVING_PER_METER),
        ("WATER_EYE", FLOAT_WATER_EYE),
        ("WATER_CLIP", FLOAT_WATER_CLIP),
        ("WATER_SHARE", FLOAT_WATER_SHARE),
        ("WATER_NIGHT", FLOAT_WATER_NIGHT),
        ("COVER_GRAY", FLOAT_COVER_GRAY),
        ("COVER_FOG", FLOAT_COVER_FOG),
        ("COVER_VEIL", FLOAT_COVER_VEIL),
        ("COVER_MIST", FLOAT_COVER_MIST),
        ("COVER_BRIGHT", FLOAT_COVER_BRIGHT),
        ("COVER_GLOOM", FLOAT_COVER_GLOOM),
        ("NIGHT_DAY", FLOAT_NIGHT_DAY),
        ("NIGHT_DUSK", FLOAT_NIGHT_DUSK),
        ("NIGHT_STARS", FLOAT_NIGHT_STARS),
        ("NIGHT_D00", FLOAT_NIGHT_D00),
        ("NIGHT_ACROSS", FLOAT_NIGHT_ACROSS),
        ("NIGHT_DOWN", FLOAT_NIGHT_DOWN),
        ("NIGHT_GLOW", FLOAT_NIGHT_GLOW),
        ("NIGHT_SKY", FLOAT_NIGHT_SKY),
        ("NIGHT_STAR_GRID", FLOAT_NIGHT_STAR_GRID),
        ("NIGHT_STAR_RATE", FLOAT_NIGHT_STAR_RATE),
        ("COUNT", FLOAT_COUNT),
    ]
    for entry in floats:
        assert_true(
            _numbered(header, "TM_VILLAGE_FLOAT_" + entry[0], entry[1]),
            "TM_VILLAGE_FLOAT_" + entry[0],
        )
    var pointers: List[Tuple[String, Int]] = [
        ("VERTICES", POINTER_VERTICES),
        ("CORNERS", POINTER_CORNERS),
        ("CODES", POINTER_CODES),
        ("SKY", POINTER_SKY),
        ("STILL_DEPTH", POINTER_STILL_DEPTH),
        ("STILL_CLIP", POINTER_STILL_CLIP),
        ("MOVING_DEPTH", POINTER_MOVING_DEPTH),
        ("MOVING_CLIP", POINTER_MOVING_CLIP),
        ("MAP_TEXELS", POINTER_MAP_TEXELS),
        ("MAP_STARTS", POINTER_MAP_STARTS),
        ("MAP_WIDTHS", POINTER_MAP_WIDTHS),
        ("MAP_HEIGHTS", POINTER_MAP_HEIGHTS),
        ("MAP_FIRSTS", POINTER_MAP_FIRSTS),
        ("MAP_COUNTS", POINTER_MAP_COUNTS),
        ("MAP_WRAPS_S", POINTER_MAP_WRAPS_S),
        ("MAP_WRAPS_T", POINTER_MAP_WRAPS_T),
        ("COLOR", POINTER_COLOR),
        ("DEPTH", POINTER_DEPTH),
        ("COVER", POINTER_COVER),
        ("WATER_SURFACE", POINTER_WATER_SURFACE),
        ("WATER_RIPPLE", POINTER_WATER_RIPPLE),
        ("WATER_CAUSTIC", POINTER_WATER_CAUSTIC),
        ("WATER_PEBBLE", POINTER_WATER_PEBBLE),
        ("WATER_WORDS", POINTER_WATER_WORDS),
        ("COUNT", POINTER_COUNT),
    ]
    for entry in pointers:
        assert_true(
            _numbered(header, "TM_VILLAGE_POINTER_" + entry[0], entry[1]),
            "TM_VILLAGE_POINTER_" + entry[0],
        )
    assert_true(header.find("#define TM_VILLAGE_LEVEL_CODE 32") > 0)
    assert_equal(LEVEL_CODE, Float32(32))
    assert_equal(VERTEX_FLOATS, 16)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
