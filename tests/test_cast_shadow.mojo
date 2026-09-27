# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a material that colors the shadow it casts, three.js's
`castShadowNode` under `shadowMap.transmitted`: the shadow pass's colors,
the transmitted shadow, and a floor under a red pane."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry
from geometries.plane import plane
from lights.light import directional_light
from lights.shadow import (
    CUBE_FACES,
    PCF_SHADOW_MAP,
    ShadowMap,
    transmitted_shadow,
)
from materials.material import (
    DOUBLE_SIDE,
    Material,
    PointSize,
    points_material,
)
from materials.nodes import (
    CAST_SHADOW_NODE,
    MASK_NODE,
    NodeGraph,
)
from math.vector3 import Vector3
from objects.line import Line
from objects.mesh import Mesh
from objects.points import Points
from render.framebuffer import Color
from render.rasterizer import SHADE_SHADOW
from render.srgb import LINEAR
from render.texture import IGNORED, NEAREST, REPEAT, Texture
from renderers.renderer import Renderer
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from test_received_shadow import a_camera, a_shadowed_scene
from test_shadow import ORIGIN, flat_frame
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 16
# Where the middle texel's four floats start.
comptime MIDDLE = ((SIZE // 2) * SIZE + SIZE // 2) * 4


def test_a_transmitted_shadow_follows_three_js() raises:
    # Lit by the depths: all the light, whatever was seen there.
    var lit = transmitted_shadow(1, SIMD[DType.float32, 4](1, 0, 0, 1), 1)
    assert_equal(lit.x, 1)
    assert_equal(lit.y, 1)
    # Shadowed behind opaque black: none; behind opaque red: red.
    var black = transmitted_shadow(0, SIMD[DType.float32, 4](0, 0, 0, 1), 1)
    assert_equal(black.x, 0)
    var red = transmitted_shadow(0, SIMD[DType.float32, 4](1, 0, 0, 1), 1)
    assert_equal(red.x, 1)
    assert_equal(red.y, 0)
    assert_equal(red.z, 0)
    # Nothing drawn, alpha zero, takes nothing away; half an alpha at half
    # an intensity takes a quarter.
    var clear = transmitted_shadow(0, SIMD[DType.float32, 4](0, 0, 0, 0), 1)
    assert_equal(clear.z, 1)
    var thin = transmitted_shadow(0, SIMD[DType.float32, 4](0, 0, 0, 0.5), 0.5)
    assert_equal(thin.x, 0.75)


def colored_map(
    red: Float32, green: Float32, blue: Float32
) raises -> ShadowMap:
    """Return a four-texel map over the unit square whose left half holds
    an opaque caster of this color at z = 0.5, and whose right half holds
    nothing."""
    var depths = List[Float32]()
    var colors = List[Float32]()
    for _ in range(4):
        for column in range(4):
            if column < 2:
                depths.append(-0.5)
                colors.append(red)
                colors.append(green)
                colors.append(blue)
                colors.append(1)
            else:
                depths.append(inf[DType.float32]())
                for _ in range(4):
                    colors.append(0)
    return ShadowMap(
        0, 4, flat_frame(), depths^, 0, 0, 0, PCF_SHADOW_MAP, 1, colors^
    )


def test_a_map_with_colors_lets_their_light_through() raises:
    var up = Vector3(0, 0, 1)
    var shadowed = Vector3(-0.5, 0, 0)
    var beside = Vector3(0.5, 0, 0)
    # An opaque black caster casts the shadow the depths alone cast.
    var black = colored_map(0, 0, 0)
    for place in [shadowed, beside, Vector3(-0.9, 0.9, 0), Vector3(5, 0, 0)]:
        assert_equal(black.through(place, up).x, black.lit(place, up))
        assert_equal(black.through(place, up).z, black.lit(place, up))
    # A red one lets its red through, and nothing else.
    var red = colored_map(1, 0, 0)
    var tinted = red.through(shadowed, up)
    assert_equal(tinted.x, 1)
    assert_equal(tinted.y, 0)
    assert_equal(red.through(beside, up).y, 1)
    # Off the map, all of it.
    assert_equal(red.through(Vector3(5, 0, 0), up).y, 1)
    # Colors must fill the square.
    with assert_raises(contains="colors must fill its square"):
        _ = ShadowMap(
            0,
            4,
            flat_frame(),
            black.depths.copy(),
            0,
            0,
            0,
            PCF_SHADOW_MAP,
            1,
            [Float32(1), 0, 0],
        )


def test_a_cube_with_colors_lets_their_light_through() raises:
    # A caster two meters out along +x, red, and nothing on the other
    # five faces.
    var depths = List[Float32]()
    var colors = List[Float32]()
    for face in range(CUBE_FACES):
        for _ in range(16):
            var filled = Float32(1) if face == 0 else Float32(0)
            depths.append(Float32(0.2) if face == 0 else Float32(1))
            colors.append(filled)
            colors.append(0)
            colors.append(0)
            colors.append(filled)
    var cube = ShadowMap(
        cube_of=0,
        size=4,
        origin=ORIGIN,
        near=0,
        far=10,
        depths=depths.copy(),
        bias=0,
        normal_bias=0,
        radius=0,
        colors=colors^,
    )
    var toward = Vector3(-1, 0, 0)
    var beyond = cube.through(Vector3(5, 0, 0), toward)
    assert_equal(beyond.x, 1)
    assert_equal(beyond.y, 0)
    assert_equal(cube.through(Vector3(0, 0, 5), toward).y, 1)
    assert_equal(cube.through(Vector3(15, 0, 0), toward).y, 1)
    with assert_raises(contains="colors must fill six faces"):
        _ = ShadowMap(
            cube_of=0,
            size=4,
            origin=ORIGIN,
            near=0,
            far=10,
            depths=depths^,
            bias=0,
            normal_bias=0,
            radius=0,
            colors=[Float32(1)],
        )


def test_a_cast_shadow_node_is_a_vec4() raises:
    var graph = NodeGraph()
    with assert_raises():
        graph.set_output(CAST_SHADOW_NODE, graph.vec3(1, 0, 0))
    graph.set_output(
        CAST_SHADOW_NODE, graph.join([graph.vec3(1, 0, 0), graph.float(1)])
    )
    assert_true(graph.compile().has(CAST_SHADOW_NODE))


def test_only_the_shadow_pass_shades_its_colors() raises:
    var renderer = Renderer(4, 4)
    with assert_raises(contains="which the renderer draws for itself"):
        renderer.set_shading(SHADE_SHADOW)


def one_texel(
    red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8
) raises -> Texture:
    """Return a one-texel texture that holds data."""
    return Texture(
        1,
        1,
        [red, green, blue, alpha],
        REPEAT,
        NEAREST,
        LINEAR,
        False,
        IGNORED,
    )


def a_sun(mut scene: Scene) raises:
    """Add a sun above the origin that casts on a map `SIZE` texels a
    side."""
    var lamp = Object3D()
    lamp.set_position(0, 5, 1)
    var sun = directional_light(Color(255, 255, 255), scene.add(lamp^), 1.0)
    sun.cast_shadow = True
    sun.shadow.map_size = SIZE
    scene.add_light(sun)


def seen_through(
    mut assets: Assets, var scene: Scene, transmitted: Bool = True
) raises -> SIMD[DType.float32, 4]:
    """Return what the sun sees through the middle of its map, or -1 in
    every lane for a map with no colors."""
    a_sun(scene)
    scene.update()
    var renderer = Renderer(8, 8)
    renderer.shadow_map_transmitted = transmitted
    var maps = renderer.shadow_maps(scene, assets)
    ref colors = maps[0].colors
    if len(colors) == 0:
        return SIMD[DType.float32, 4](-1)
    return SIMD[DType.float32, 4](
        colors[MIDDLE],
        colors[MIDDLE + 1],
        colors[MIDDLE + 2],
        colors[MIDDLE + 3],
    )


def panes(
    mut assets: Assets, paints: List[Material], heights: List[Float32]
) raises -> Scene:
    """Return a level pane four meters a side at each height, in order,
    each painted and casting."""
    var scene = Scene()
    var square = assets.geometries.add(
        plane(Length(4.0, METER), Length(4.0, METER))
    )
    for index in range(len(paints)):
        var node = Object3D()
        node.set_position(0, heights[index], 0)
        node.set_euler(
            Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
        )
        var paint = paints[index].copy()
        paint.side = DOUBLE_SIDE
        scene.add_mesh(
            Mesh(
                square,
                assets.materials.add(paint),
                scene.add(node^),
                cast_shadow=True,
            )
        )
    return scene^


def casting(mut assets: Assets, red: Float32, blue: Float32) raises -> Material:
    """Return a material whose cast shadow node is opaque red and blue."""
    var graph = NodeGraph()
    graph.set_output(
        CAST_SHADOW_NODE,
        graph.join([graph.vec3(red, 0, blue), graph.float(1)]),
    )
    var paint = Material(Color(200, 200, 200))
    paint.nodes = assets.programs.add(graph.compile())
    return paint^


def seen_through_one(
    mut assets: Assets, paint: Material
) raises -> SIMD[DType.float32, 4]:
    """Return what the sun sees through one pane of `paint`."""
    var scene = panes(assets, [paint.copy()], [Float32(2)])
    return seen_through(assets, scene^)


def test_the_shadow_pass_keeps_what_the_light_sees() raises:
    var assets = Assets()
    # Opaque black by default, and nothing kept unless asked.
    var plain = Material(Color(200, 200, 200))
    var seen = seen_through_one(assets, plain)
    assert_equal(seen[0], 0)
    assert_equal(seen[3], 1)
    var scene = panes(assets, [plain.copy()], [Float32(2)])
    assert_equal(seen_through(assets, scene^, transmitted=False)[0], -1)
    # The cast shadow node's color.
    seen = seen_through_one(assets, casting(assets, 1, 0))
    assert_equal(seen[0], 1)
    assert_equal(seen[2], 0)
    # The map's alpha and the alpha map's green thin it.
    var mapped = Material(Color(200, 200, 200))
    mapped.map = assets.textures.add(one_texel(255, 255, 255, 128))
    mapped.alpha_map = assets.textures.add(one_texel(0, 128, 0, 255))
    seen = seen_through_one(assets, mapped)
    assert_almost_equal(seen[3], (128.0 / 255) * (128.0 / 255), atol=1e-3)


def test_a_caster_thrown_away_leaves_its_texel_clear() raises:
    var assets = Assets()
    # Masked away.
    var graph = NodeGraph()
    graph.set_output(MASK_NODE, graph.float(0))
    var masked = Material(Color(200, 200, 200))
    masked.nodes = assets.programs.add(graph.compile())
    assert_equal(seen_through_one(assets, masked)[3], 0)
    # Below its alpha test.
    var tested = Material(Color(200, 200, 200))
    tested.map = assets.textures.add(one_texel(255, 255, 255, 64))
    tested.alpha_test = 0.5
    assert_equal(seen_through_one(assets, tested)[3], 0)
    # Hashed away at no alpha.
    var hashed = Material(Color(200, 200, 200))
    hashed.alpha_map = assets.textures.add(one_texel(0, 0, 0, 255))
    hashed.alpha_hash = True
    assert_equal(seen_through_one(assets, hashed)[3], 0)


def test_the_nearest_caster_is_the_one_the_light_sees() raises:
    # Red above blue, drawn in either order: the light sees red.
    for flipped in [False, True]:
        var assets = Assets()
        var paints: List[Material] = [
            casting(assets, 1, 0),
            casting(assets, 0, 1),
        ]
        var heights: List[Float32] = [2, 1]
        if flipped:
            paints = [casting(assets, 0, 1), casting(assets, 1, 0)]
            heights = [1, 2]
        var seen = seen_through(assets, panes(assets, paints, heights))
        assert_equal(seen[0], 1)
        assert_equal(seen[2], 0)
    # A caster that writes no depth is painted over by one behind it.
    var assets = Assets()
    var above = casting(assets, 1, 0)
    above.depth_write = False
    var seen = seen_through(
        assets,
        panes(
            assets,
            [above^, casting(assets, 0, 1)],
            [Float32(2), Float32(1)],
        ),
    )
    assert_equal(seen[2], 1)


def test_a_red_pane_casts_a_red_shadow() raises:
    # The block of the shaped scene casts red: where its shadow falls on
    # the floor, red comes through and green and blue are held back.
    var assets = Assets()
    var floor = Material(Color(200, 200, 200))
    var scene = a_shadowed_scene(assets, floor, casting(assets, 1, 0))
    var renderer = Renderer(48, 36)
    var gray = renderer.render(scene, assets, a_camera())
    renderer.shadow_map_transmitted = True
    var red = renderer.render(scene, assets, a_camera())
    var redder = 0
    for y in range(36):
        for x in range(48):
            var was = gray.get_pixel(x, y)
            var now = red.get_pixel(x, y)
            if Int(now.r) > Int(was.r) + 10 and Int(now.g) <= Int(was.g) + 1:
                redder += 1
    assert_true(redder > 20, "no shadow turned red")


def dots(
    mut assets: Assets, paints: List[Material], heights: List[Float32]
) raises -> Scene:
    """Return one point forty pixels wide at each height, in order, each
    painted and casting."""
    var scene = Scene()
    var one = BufferGeometry()
    one.set_attribute("position", BufferAttribute([Float32(0), 0, 0], 3))
    one.set_attribute("uv", BufferAttribute([Float32(0.5), 0.5], 2))
    var shape = assets.geometries.add(one^)
    for index in range(len(paints)):
        var node = Object3D()
        node.set_position(0, heights[index], 0)
        scene.add_points(
            Points(
                shape,
                assets.materials.add(paints[index].copy()),
                scene.add(node^),
                cast_shadow=True,
            )
        )
    return scene^


def a_dot(mut assets: Assets) raises -> Material:
    """Return a points material forty pixels wide."""
    return points_material(
        Color(200, 200, 200), size=PointSize(40.0), size_attenuation=False
    )


def test_a_point_casts_what_the_light_sees_through_it() raises:
    var assets = Assets()
    var plain = a_dot(assets)
    var seen = seen_through(assets, dots(assets, [plain.copy()], [Float32(2)]))
    assert_equal(seen[0], 0)
    assert_equal(seen[3], 1)
    # Its map and its alpha map thin it, and its alpha test throws it away.
    var thin = a_dot(assets)
    thin.map = assets.textures.add(one_texel(255, 255, 255, 128))
    thin.alpha_map = assets.textures.add(one_texel(0, 128, 0, 255))
    seen = seen_through(assets, dots(assets, [thin.copy()], [Float32(2)]))
    assert_almost_equal(seen[3], (128.0 / 255) * (128.0 / 255), atol=1e-3)
    thin.alpha_test = 0.5
    seen = seen_through(assets, dots(assets, [thin^], [Float32(2)]))
    assert_equal(seen[3], 0)
    # Its mask throws it away.
    var graph = NodeGraph()
    graph.set_output(MASK_NODE, graph.float(0))
    var masked = a_dot(assets)
    masked.nodes = assets.programs.add(graph.compile())
    seen = seen_through(assets, dots(assets, [masked^], [Float32(2)]))
    assert_equal(seen[3], 0)
    # The nearer of two is the one seen, in either order.
    var red_graph = NodeGraph()
    red_graph.set_output(
        CAST_SHADOW_NODE,
        red_graph.join([red_graph.vec3(1, 0, 0), red_graph.float(1)]),
    )
    var red = a_dot(assets)
    red.nodes = assets.programs.add(red_graph.compile())
    for flipped in [False, True]:
        var heights: List[Float32] = [2, 1]
        var paints: List[Material] = [red.copy(), a_dot(assets)]
        if flipped:
            heights = [1, 2]
            paints = [a_dot(assets), red.copy()]
        seen = seen_through(assets, dots(assets, paints, heights))
        assert_equal(seen[0], 1)
    # One that writes no depth is painted over by one behind it.
    var above = red.copy()
    above.depth_write = False
    seen = seen_through(
        assets,
        dots(assets, [above^, a_dot(assets)], [Float32(2), Float32(1)]),
    )
    assert_equal(seen[0], 0)


def sticks(
    mut assets: Assets, paints: List[Material], heights: List[Float32]
) raises -> Scene:
    """Return one segment across the middle at each height, in order,
    each painted and casting."""
    var scene = Scene()
    var two = BufferGeometry()
    two.set_attribute(
        "position", BufferAttribute([Float32(-3), 0, 0, 3, 0, 0], 3)
    )
    var shape = assets.geometries.add(two^)
    for index in range(len(paints)):
        # Moved back as it moves down, so every stick lies on the one
        # ray from the sun and lands on the same texels.
        var node = Object3D()
        node.set_position(0, heights[index], (heights[index] - 2) * 0.2)
        scene.add_line(
            Line(
                shape,
                assets.materials.add(paints[index].copy()),
                scene.add(node^),
                cast_shadow=True,
            )
        )
    return scene^


def reddest(
    mut assets: Assets, var scene: Scene
) raises -> SIMD[DType.float32, 4]:
    """Return the texel the sun sees most red through, or one with
    nothing in it."""
    a_sun(scene)
    scene.update()
    var renderer = Renderer(8, 8)
    renderer.shadow_map_transmitted = True
    var maps = renderer.shadow_maps(scene, assets)
    ref colors = maps[0].colors
    var best = SIMD[DType.float32, 4](0)
    var drawn = 0
    for texel in range(len(colors) // 4):
        if colors[texel * 4 + 3] > 0:
            drawn += 1
            if colors[texel * 4] >= best[0]:
                best = SIMD[DType.float32, 4](
                    colors[texel * 4],
                    colors[texel * 4 + 1],
                    colors[texel * 4 + 2],
                    colors[texel * 4 + 3],
                )
    assert_true(drawn > 0, "the sun saw no line")
    return best


def test_a_line_casts_what_the_light_sees_through_it() raises:
    var assets = Assets()
    var red_graph = NodeGraph()
    red_graph.set_output(
        CAST_SHADOW_NODE,
        red_graph.join([red_graph.vec3(1, 0, 0), red_graph.float(1)]),
    )
    var red = Material(Color(200, 200, 200))
    red.nodes = assets.programs.add(red_graph.compile())
    var black = Material(Color(200, 200, 200))
    # Alone, black; red where its node says red.
    var seen = reddest(assets, sticks(assets, [black.copy()], [Float32(2)]))
    assert_equal(seen[0], 0)
    assert_equal(seen[3], 1)
    # The nearer of two is the one seen, in either order.
    for flipped in [False, True]:
        var heights: List[Float32] = [2, 1]
        var paints: List[Material] = [red.copy(), black.copy()]
        if flipped:
            heights = [1, 2]
            paints = [black.copy(), red.copy()]
        seen = reddest(assets, sticks(assets, paints, heights))
        assert_equal(seen[0], 1)
    # One that writes no depth is painted over by one behind it.
    var above = red.copy()
    above.depth_write = False
    seen = reddest(
        assets,
        sticks(assets, [above^, black.copy()], [Float32(2), Float32(1)]),
    )
    assert_equal(seen[0], 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
