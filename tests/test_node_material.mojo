# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for node materials: a material that names a compiled node graph,
the rasterizer that runs it per fragment, and the renderer that moves its
vertices, writes its frame and refuses it where it cannot run.

`tests/test_nodes.mojo` checks each node's arithmetic. These check where
each output lands in the shading: what it replaces, and what reads it.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.fog import FogView, linear_fog
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.light import directional_light
from lights.lighting import Lighting
from materials.material import (
    BASIC,
    DEPTH,
    DISTANCE,
    LAMBERT,
    MATCAP,
    NORMALS,
    PHONG,
    PHYSICAL,
    SHADOW,
    STANDARD,
    TOON,
    BACK_SIDE,
    DOUBLE_SIDE,
    FRONT_SIDE,
    Material,
    Side,
    points_material,
    shader_material,
    sprite_material,
)
from materials.nodes import (
    AO_NODE,
    COLOR_NODE,
    DEPTH_NODE,
    EMISSIVE_NODE,
    MASK_NODE,
    NODE_FLOAT,
    NODE_VEC3,
    NODE_VEC4,
    NORMAL_NODE,
    NO_NODES,
    OPACITY_NODE,
    OUTPUT_NODE,
    POSITION_NODE,
    PROGRAM_TIME,
    SIZE_NODE,
    PROGRAM_VIEW,
    NodeGraph,
    NodeProgram,
    NodeProgramId,
    NodeProgramStore,
)
from math.vector3 import Vector3
from objects.line import Line
from objects.line_segments2 import LineSegments2, line_segments_geometry
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.framebuffer import Color, FloatColor, Framebuffer
from render.rasterizer import (
    DRAW_TRIANGLES,
    LayerFactors,
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
    Draw,
    RasterVertex,
    check_line_state,
    check_point_state,
    check_triangle_maps,
    check_triangle_state,
    rasterize_all,
    rasterize_frame,
    rasterize_line,
    rasterize_point,
)
from render.linerule import covers as line_covers, toward_at
from math.vector2 import Vector2
from render.srgb import LINEAR
from render.target import RenderTarget
from render.texture import BILINEAR, CLAMP, IGNORED, NEAREST, REPEAT, Texture
from render.cube_texture import CubeTexture
from render.cube_texture_store import CubeTextureId
from render.volume_texture import Data3DTexture, DataArrayTexture, VolumeImage
from render.volume_texture_store import Data3DTextureId, DataArrayTextureId
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from renderers.renderer import Renderer
from std.math import sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, Length, METER, SECOND

comptime SIZE = 16


def corner(
    x: Float32,
    y: Float32,
    nodes: NodeProgramId,
    kind: MaterialKind_ = LAMBERT,
) -> RasterVertex:
    """Return a corner of a flat triangle facing the camera, gray, with
    texture coordinates that follow the screen."""
    var vertex = RasterVertex(
        x,
        y,
        0.5,
        1,
        FloatColor(0.5, 0.5, 0.5, 1.0),
        x / Float32(SIZE),
        y / Float32(SIZE),
        kind=kind,
    )
    vertex.nodes = nodes
    return vertex


comptime MaterialKind_ = type_of(LAMBERT)


def big_triangle(
    nodes: NodeProgramId, kind: MaterialKind_ = LAMBERT
) -> List[RasterVertex]:
    """Return one triangle covering the top-left half of the target."""
    return [
        corner(0, 0, nodes, kind),
        corner(Float32(SIZE) * 2, 0, nodes, kind),
        corner(0, Float32(SIZE) * 2, nodes, kind),
    ]


def draw(
    corners: List[RasterVertex],
    programs: NodeProgramStore,
    mode: type_of(SHADE_LIT) = SHADE_LIT,
    textures: TextureStore = TextureStore(),
    lighting: Lighting = Lighting.uniform(),
    fog: FogView = FogView.none(),
    workers: Int = 1,
) raises -> RenderTarget:
    """Return a target with the triangles drawn into it."""
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    rasterize_all(
        corners,
        target,
        mode,
        textures,
        lighting,
        workers,
        fog,
        programs=programs,
    )
    return target^


def one_program(var graph: NodeGraph) raises -> NodeProgramStore:
    """Return a store holding the graph's program as id zero."""
    var store = NodeProgramStore()
    _ = store.add(graph.compile())
    return store^


def assert_color(
    got: FloatColor, r: Float32, g: Float32, b: Float32, a: Float32 = 1
) raises:
    """Assert a linear color, channel by channel."""
    assert_almost_equal(got.r, r, atol=1e-5)
    assert_almost_equal(got.g, g, atol=1e-5)
    assert_almost_equal(got.b, b, atol=1e-5)
    assert_almost_equal(got.a, a, atol=1e-5)


# --- the material -------------------------------------------------------------


def test_a_material_names_no_program_by_default() raises:
    var plain = Material(Color(255, 255, 255))
    assert_true(plain.nodes == NO_NODES)
    var noded = Material(Color(255, 255, 255), nodes=NodeProgramId(0))
    assert_equal(noded.nodes.value, 0)


def test_the_kinds_that_show_a_surfaces_color_take_nodes() raises:
    assert_true(BASIC.takes_nodes())
    assert_true(LAMBERT.takes_nodes())
    assert_true(PHONG.takes_nodes())
    assert_true(TOON.takes_nodes())
    assert_true(MATCAP.takes_nodes())
    assert_true(STANDARD.takes_nodes())
    assert_true(PHYSICAL.takes_nodes())
    assert_false(NORMALS.takes_nodes())
    assert_false(DEPTH.takes_nodes())
    assert_false(SHADOW.takes_nodes())
    assert_false(DISTANCE.takes_nodes())


def test_a_material_refuses_nodes_it_cannot_run() raises:
    with assert_raises(contains="node program id cannot be negative"):
        _ = Material(Color(255, 255, 255), nodes=NodeProgramId(-2))
    with assert_raises(contains="runs no node graph"):
        _ = Material(Color(255, 255, 255), kind=NORMALS, nodes=NodeProgramId(0))
    with assert_raises(contains="A wireframe material runs no node graph"):
        _ = Material(
            Color(255, 255, 255),
            kind=BASIC,
            wireframe=True,
            nodes=NodeProgramId(0),
        )


def test_a_shader_material_is_an_unlit_node_material() raises:
    var shader = shader_material(NodeProgramId(2), transparent=True)
    assert_true(shader.kind == BASIC)
    assert_equal(shader.nodes.value, 2)
    assert_true(shader.transparent)
    assert_false(shader.fog)
    with assert_raises(contains="needs a node program to run"):
        _ = shader_material(NO_NODES)
    with assert_raises(contains="side"):
        _ = shader_material(NodeProgramId(0), side=Side(7))


# --- the rasterizer -----------------------------------------------------------


def test_a_color_node_replaces_the_diffuse_color_the_lights_multiply() raises:
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.vec3(1, 0.25, 0))
    var programs = one_program(graph^)
    var lit = draw(big_triangle(NodeProgramId(0)), programs)
    assert_color(lit.color_at(2, 2), 1, 0.25, 0)
    # Half the light, half the color: the lights multiply the node.
    var dim = draw(
        big_triangle(NodeProgramId(0)),
        programs,
        lighting=Lighting(ambient=FloatColor(0.5, 0.5, 0.5, 1.0)),
    )
    assert_color(dim.color_at(2, 2), 0.5, 0.125, 0)
    # A physical surface is lit by its own lobe, tinted by the node.
    var metal = draw(big_triangle(NodeProgramId(0), PHYSICAL), programs)
    assert_true(metal.color_at(2, 2).r > metal.color_at(2, 2).g)
    # A sheen over the node's color adds its own lobe on top.
    var cloth = big_triangle(NodeProgramId(0), PHYSICAL)
    var sheen = LayerFactors()
    sheen.sheen_color = Vector3(0, 0, 1)
    sheen.sheen_roughness = 0.5
    for index in range(3):
        cloth[index].layers = sheen
    var sky = Scene()
    var sun = Object3D()
    sun.set_position(0.3, 0.2, 1)
    var sun_node = sky.add(sun^)
    sky.add_light(directional_light(Color(255, 255, 255), sun_node, 2.0))
    sky.update()
    var lit_by_sun = Lighting(sky, eye=Vector3(0, 0, 3))
    var bare = draw(
        big_triangle(NodeProgramId(0), PHYSICAL), programs, lighting=lit_by_sun
    )
    var sheened = draw(cloth, programs, lighting=lit_by_sun)
    assert_true(sheened.color_at(2, 2).b > bare.color_at(2, 2).b)
    # With no program the corner's gray shows.
    var plain = draw(big_triangle(NO_NODES), programs)
    assert_color(plain.color_at(2, 2), 0.5, 0.5, 0.5)


def test_the_attributes_reach_the_graph_under_every_shading_mode() raises:
    # The uv view runs no graph; the other two read the interpolated
    # coordinates, even `SHADE_LIT`, which opens no texture.
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.swizzle(graph.uv(), "xyx"))
    var programs = one_program(graph^)
    var lit = draw(big_triangle(NodeProgramId(0), BASIC), programs)
    var here = lit.color_at(4, 2)
    assert_almost_equal(here.r, 4.5 / Float32(SIZE), atol=1e-5)
    assert_almost_equal(here.g, 2.5 / Float32(SIZE), atol=1e-5)
    var uv = draw(big_triangle(NodeProgramId(0), BASIC), programs, SHADE_UV)
    assert_almost_equal(uv.color_at(4, 2).b, 0, atol=1e-5)
    # The world position and the vertex color reach it too.
    var place = NodeGraph()
    place.set_output(
        COLOR_NODE, place.add(place.position_world(), place.vertex_color())
    )
    var placed = draw(big_triangle(NodeProgramId(0)), one_program(place^))
    assert_color(placed.color_at(2, 2), 0.5, 0.5, 0.5)


def test_opacity_and_emissive_nodes_replace_the_alpha_and_the_glow() raises:
    var graph = NodeGraph()
    graph.set_output(OPACITY_NODE, graph.float(0.25))
    graph.set_output(EMISSIVE_NODE, graph.vec3(0, 0, 0.5))
    var programs = one_program(graph^)
    var corners = big_triangle(NodeProgramId(0))
    # An alpha test above the node's opacity throws every fragment away.
    for index in range(3):
        corners[index].alpha_test = 0.5
    var cut = draw(corners, programs)
    assert_color(cut.color_at(2, 2), 0, 0, 0)
    # Below it, the opaque surface is drawn, glowing blue, in the dark.
    for index in range(3):
        corners[index].alpha_test = 0.1
    var dark = Lighting(ambient=FloatColor(0.0, 0.0, 0.0, 1.0))
    var kept = draw(corners, programs, lighting=dark)
    assert_color(kept.color_at(2, 2), 0, 0, 0.5)


def test_a_normal_node_bends_the_normal_the_other_outputs_read() raises:
    var graph = NodeGraph()
    graph.set_output(NORMAL_NODE, graph.vec3(1, 0, 0))
    graph.set_output(COLOR_NODE, graph.normal_world())
    var programs = one_program(graph^)
    var bent = draw(big_triangle(NodeProgramId(0), BASIC), programs)
    var half = sqrt(Float32(0.5))
    assert_color(bent.color_at(2, 2), half, 0, half)


def test_an_output_node_reads_the_lit_and_fogged_color() raises:
    var graph = NodeGraph()
    graph.set_output(
        OUTPUT_NODE, graph.mul(graph.lit(), graph.vec3(1, 0.5, 0.25))
    )
    var programs = one_program(graph^)
    var tinted = draw(big_triangle(NodeProgramId(0)), programs)
    assert_color(tinted.color_at(2, 2), 0.5, 0.25, 0.125)
    # A fog that hides everything turns the lit color the fog's before
    # the output node reads it.
    var fog = FogView(
        linear_fog(
            Color(255, 255, 255), Length(0.0, METER), Length(0.001, METER)
        )
    )
    var far = big_triangle(NodeProgramId(0))
    for index in range(3):
        far[index].view_depth = 1
    var foggy = draw(far, programs, fog=fog)
    assert_color(foggy.color_at(2, 2), 1, 0.5, 0.25)


def a_texture() raises -> Texture:
    """Return a two-by-one linear texture: red on the left, blue on the
    right, read nearest."""
    return Texture(
        2,
        1,
        [UInt8(255), 0, 0, 255, 0, 0, 255, 255],
        REPEAT,
        NEAREST,
        LINEAR,
        False,
    )


def test_a_texture_node_reads_where_the_graph_says() raises:
    var textures = TextureStore()
    var map = textures.add(a_texture())
    var graph = NodeGraph()
    # Read at the coordinate turned around: the left half reads blue.
    var turned = graph.sub(graph.vec2(1, 1), graph.uv())
    graph.set_output(
        COLOR_NODE, graph.swizzle(graph.texture(map, turned), "rgb")
    )
    var programs = one_program(graph^)
    var read = draw(
        big_triangle(NodeProgramId(0), BASIC), programs, SHADE_TEXTURE, textures
    )
    assert_color(read.color_at(2, 2), 0, 0, 1)
    # A mode that opens no texture reads white.
    var white = draw(big_triangle(NodeProgramId(0), BASIC), programs, SHADE_LIT)
    assert_color(white.color_at(2, 2), 1, 1, 1)


def test_a_texture_node_reads_at_the_level_the_graph_says() raises:
    # Blue and red crossed: the full-size image reads blue at the bottom
    # left, and the one-texel level below it is their mean.
    var textures = TextureStore()
    var map = textures.add(
        Texture(
            2,
            2,
            [
                UInt8(255),
                0,
                0,
                255,
                0,
                0,
                255,
                255,
                0,
                0,
                255,
                255,
                255,
                0,
                0,
                255,
            ],
            REPEAT,
            BILINEAR,
            LINEAR,
        )
    )
    var reds: List[Float32] = [0, 0.5]
    var blues: List[Float32] = [1, 0.5]
    for level in range(2):
        var graph = NodeGraph()
        var read = graph.texture_level(
            map, graph.vec2(0.25, 0.25), graph.float(Float32(level))
        )
        graph.set_output(COLOR_NODE, graph.swizzle(read, "rgb"))
        var shown = draw(
            big_triangle(NodeProgramId(0), BASIC),
            one_program(graph^),
            SHADE_TEXTURE,
            textures,
        ).color_at(2, 2)
        assert_almost_equal(shown.r, reds[level], atol=0.01)
        assert_almost_equal(shown.b, blues[level], atol=0.01)


def test_a_texel_is_read_by_its_column_and_row() raises:
    # The crossed texture again: row zero, counted as v counts, is the
    # bottom row, blue then red.
    var textures = TextureStore()
    var map = textures.add(
        Texture(
            2,
            2,
            [
                UInt8(255),
                0,
                0,
                255,
                0,
                0,
                255,
                255,
                0,
                0,
                255,
                255,
                255,
                0,
                0,
                255,
            ],
            REPEAT,
            BILINEAR,
            LINEAR,
        )
    )
    var graph = NodeGraph()
    var named = graph.texture_uniform("map", map)
    var left = graph.texture_load(named, graph.vec2(0, 0), graph.float(0))
    var right = graph.texture_load(named, graph.vec2(1, 0), graph.float(0))
    var size = graph.texture_size(named, graph.float(1))
    graph.set_output(
        COLOR_NODE,
        graph.join(
            [
                graph.swizzle(right, "r"),
                graph.swizzle(size, "x"),
                graph.swizzle(left, "b"),
            ]
        ),
    )
    var shown = draw(
        big_triangle(NodeProgramId(0), BASIC),
        one_program(graph^),
        SHADE_TEXTURE,
        textures,
    ).color_at(2, 2)
    assert_color(shown, 1, 1, 1)
    var blank = Texture()
    assert_equal(blank.fetch(0, 0, 0).g, 1)
    assert_equal(blank.fetch_size(0)[0], 0)


def test_bands_run_the_graph_as_one_thread_does() raises:
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.swizzle(graph.uv(), "yxy"))
    var programs = one_program(graph^)
    var one = draw(big_triangle(NodeProgramId(0), BASIC), programs)
    var four = draw(big_triangle(NodeProgramId(0), BASIC), programs, workers=4)
    for y in range(SIZE):
        for x in range(SIZE):
            assert_true(one.color_at(x, y).r == four.color_at(x, y).r)


def test_the_rasterizer_refuses_a_program_it_cannot_run() raises:
    var graph = NodeGraph()
    graph.set_output(
        COLOR_NODE,
        graph.swizzle(graph.texture(TextureId(3), graph.uv()), "rgb"),
    )
    var programs = one_program(graph^)
    with assert_raises(contains="No node program has that id"):
        _ = draw(big_triangle(NodeProgramId(1)), programs)
    with assert_raises(contains="No texture has that id"):
        _ = draw(big_triangle(NodeProgramId(0)), programs, SHADE_TEXTURE)
    # The uv view runs no program, so it asks nothing of one.
    _ = draw(big_triangle(NodeProgramId(5)), programs, SHADE_UV)
    # Nor does `SHADE_LIT` open the textures it reads.
    _ = draw(big_triangle(NodeProgramId(0)), programs, SHADE_LIT)
    var frame = big_triangle(NodeProgramId(1))
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    with assert_raises(contains="No node program has that id"):
        rasterize_frame(
            frame,
            List[RasterVertex](),
            [Draw(DRAW_TRIANGLES, 0, 1)],
            target,
            programs=programs,
        )
    with assert_raises(contains="No node program has that id"):
        check_triangle_maps(
            frame[0], SHADE_LIT, TextureStore(), programs=programs
        )


def test_a_triangles_corners_must_agree_on_a_program_it_can_run() raises:
    var corners = big_triangle(NodeProgramId(0))
    corners[1].nodes = NO_NODES
    with assert_raises(contains="disagree about their node program"):
        check_triangle_state(corners[0], corners[1], corners[2])
    corners[1].nodes = NodeProgramId(0)
    corners[2].nodes = NodeProgramId(1)
    with assert_raises(contains="disagree about their node program"):
        check_triangle_state(corners[0], corners[1], corners[2])
    var negative = big_triangle(NodeProgramId(-3))
    with assert_raises(contains="node program id that nothing can hold"):
        check_triangle_state(negative[0], negative[1], negative[2])
    var data = big_triangle(NodeProgramId(0), NORMALS)
    with assert_raises(contains="runs no node graph"):
        check_triangle_state(data[0], data[1], data[2])


def test_a_line_runs_a_graph_at_each_pixel() raises:
    var end = RasterVertex(0, 0, 0, 1, FloatColor(1.0, 1.0, 1.0), kind=BASIC)
    var noded = end
    noded.nodes = NodeProgramId(0)
    check_line_state(end, end)
    check_line_state(noded, noded)
    with assert_raises(contains="ends must agree about the node program"):
        check_line_state(noded, end)
    # Left to right, the line's coordinate is red and its step across a
    # pixel green, the right half is thrown away, and the output halves
    # what is left.
    var graph = NodeGraph()
    var u = graph.swizzle(graph.uv(), "x")
    graph.set_output(
        COLOR_NODE, graph.join([u, graph.dfdx(u), graph.float(1)])
    )
    graph.set_output(MASK_NODE, graph.less_than(u, graph.float(0.5)))
    graph.set_output(OUTPUT_NODE, graph.mul(graph.lit(), graph.float(0.5)))
    var programs = one_program(graph^)
    var a = noded
    a.x = 1.5
    a.y = 4.5
    var b = a
    b.x = 13.5
    b.u = 1
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    rasterize_line(a, b, target, programs=programs)
    var first = Vector2(a.x, a.y)
    var second = Vector2(b.x, b.y)
    var kept = 0
    for x in range(SIZE):
        var toward = toward_at(first, second, 1, 1, x, 4)
        var step = toward_at(first, second, 1, 1, x + 1, 4) - toward
        var got = target.color_at(x, 4)
        if line_covers(first, second, x, 4) and toward < 0.5:
            assert_color(got, toward * 0.5, step * 0.5, 0.5)
            kept += 1
        else:
            assert_color(got, 0, 0, 0)
    assert_true(kept > 4)
    # The uv view runs no program, and a program not there is refused.
    rasterize_line(a, b, target, mode=SHADE_UV, programs=programs)
    a.nodes = NodeProgramId(2)
    b.nodes = NodeProgramId(2)
    with assert_raises(contains="No node program has that id"):
        rasterize_line(a, b, target, programs=programs)


def test_a_point_runs_a_graph_at_each_pixel() raises:
    # A point four pixels across at (4, 4): gl_PointCoord's x is red and
    # its y green, its step across one pixel is blue, and the right half
    # is thrown away.
    var graph = NodeGraph()
    var place = graph.point_coord()
    var across = graph.swizzle(place, "x")
    graph.set_output(
        COLOR_NODE,
        graph.join(
            [
                across,
                graph.swizzle(place, "y"),
                graph.mul(graph.dfdx(across), graph.float(4)),
            ]
        ),
    )
    graph.set_output(MASK_NODE, graph.less_than(across, graph.float(0.5)))
    graph.set_output(OPACITY_NODE, graph.float(0.5))
    var programs = one_program(graph^)
    var point = RasterVertex(4, 4, 0, 1, FloatColor(1.0, 1.0, 1.0), kind=BASIC)
    point.point_size = 4
    check_point_state(point)
    point.nodes = NodeProgramId(0)
    check_point_state(point)
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    rasterize_point(point, target, SHADE_LIT, TextureStore(), programs=programs)
    assert_color(target.color_at(2, 2), 0.125, 0.125, 1)
    assert_color(target.color_at(3, 5), 0.375, 0.875, 1)
    # Thrown away where the mask is zero, and the opacity is not a blend
    # the point asked for.
    assert_color(target.color_at(4, 3), 0, 0, 0)
    # The output node reads the finished color, fog and all.
    var tinted = NodeGraph()
    tinted.set_output(
        OUTPUT_NODE, tinted.mul(tinted.lit(), tinted.vec3(1, 0.5, 0.25))
    )
    tinted.set_output(
        COLOR_NODE, tinted.swizzle(tinted.frag_coord(), "xyz")
    )
    var tints = one_program(tinted^)
    var tinted_target = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    rasterize_point(point, tinted_target, SHADE_LIT, TextureStore(), programs=tints)
    assert_color(
        tinted_target.color_at(2, 2),
        2.5,
        (Float32(SIZE) - 2.5) * 0.5,
        (point.z * 0.5 + 0.5) * 0.25,
    )
    # A program that is not there is refused, and the uv view runs none.
    point.nodes = NodeProgramId(3)
    with assert_raises(contains="No node program has that id"):
        rasterize_point(point, target, SHADE_LIT, TextureStore(), programs=programs)
    rasterize_point(point, target, SHADE_UV, TextureStore(), programs=programs)


# --- the mask, the ambient occlusion and the depth ----------------------------


def test_a_mask_and_a_discard_throw_fragments_away() raises:
    # Kept right of a quarter of the way across, and not below half way.
    var graph = NodeGraph()
    var u = graph.swizzle(graph.uv(), "x")
    graph.set_output(MASK_NODE, graph.greater_than(u, graph.float(0.25)))
    graph.set_output(COLOR_NODE, graph.vec3(1, 1, 1))
    graph.If(
        graph.greater_than(graph.swizzle(graph.uv(), "y"), graph.float(0.5))
    )
    graph.Discard()
    graph.End()
    var programs = one_program(graph^)
    var cut = draw(big_triangle(NodeProgramId(0), BASIC), programs)
    assert_color(cut.color_at(2, 2), 0, 0, 0)
    assert_color(cut.color_at(6, 2), 1, 1, 1)
    assert_color(cut.color_at(6, 10), 0, 0, 0)
    # A thrown-away fragment claims no depth: what is behind shows through.
    var behind = big_triangle(NO_NODES, BASIC)
    for index in range(3):
        behind[index].z = 0.9
        behind[index].color = FloatColor(0.0, 1.0, 0.0, 1.0)
    var both = big_triangle(NodeProgramId(0), BASIC)
    both.extend(behind^)
    var layered = draw(both, programs)
    assert_color(layered.color_at(2, 2), 0, 1, 0)
    assert_color(layered.color_at(6, 2), 1, 1, 1)


def test_an_ao_node_dims_the_indirect_light() raises:
    var graph = NodeGraph()
    graph.set_output(AO_NODE, graph.float(0.5))
    var programs = one_program(graph^)
    # All the light here is indirect, so half of it is left.
    var dim = draw(big_triangle(NodeProgramId(0)), programs)
    assert_color(dim.color_at(2, 2), 0.25, 0.25, 0.25)
    var basic = draw(big_triangle(NodeProgramId(0), BASIC), programs)
    assert_color(basic.color_at(2, 2), 0.25, 0.25, 0.25)
    # A physical surface takes it with its indirect light too.
    var plain = draw(big_triangle(NO_NODES, PHYSICAL), programs)
    var metal = draw(big_triangle(NodeProgramId(0), PHYSICAL), programs)
    assert_true(metal.color_at(2, 2).r < plain.color_at(2, 2).r)
    # The node replaces an ao map where both are.
    var textures = TextureStore()
    var map = textures.add(
        Texture(
            2,
            1,
            [UInt8(255), 0, 0, 255, 0, 0, 255, 255],
            REPEAT,
            NEAREST,
            LINEAR,
            False,
            IGNORED,
        )
    )
    var mapped = big_triangle(NodeProgramId(0))
    for index in range(3):
        mapped[index].ao_map = map
    var replaced = draw(mapped, programs, SHADE_TEXTURE, textures)
    assert_color(replaced.color_at(2, 2), 0.25, 0.25, 0.25)


def test_a_depth_node_replaces_the_depth_the_tests_read() raises:
    # A gray triangle at a depth of 0.2, then the node's triangle in front,
    # at 0.5, which the node puts at a window depth of 0.9: behind.
    var graph = NodeGraph()
    graph.set_output(DEPTH_NODE, graph.float(0.9))
    graph.set_output(COLOR_NODE, graph.vec3(1, 0, 0))
    var programs = one_program(graph^)
    var near = big_triangle(NO_NODES, BASIC)
    for index in range(3):
        near[index].z = 0.2
    var corners = near.copy()
    corners.extend(big_triangle(NodeProgramId(0), BASIC))
    var hidden = draw(corners, programs)
    assert_color(hidden.color_at(2, 2), 0.5, 0.5, 0.5)
    # At a window depth of 0.1 it is in front.
    var front = NodeGraph()
    front.set_output(DEPTH_NODE, front.float(0.1))
    front.set_output(COLOR_NODE, front.vec3(1, 0, 0))
    var shown = draw(corners, one_program(front^))
    assert_color(shown.color_at(2, 2), 1, 0, 0)


def test_derivatives_and_varyings_read_the_triangles_plane() raises:
    # The coordinates grow a sixteenth a pixel right and down: dFdy looks
    # up, so it reads minus a sixteenth.
    var graph = NodeGraph()
    var slope = graph.join(
        [
            graph.mul(
                graph.swizzle(graph.dfdx(graph.uv()), "x"), graph.float(16)
            ),
            graph.mul(
                graph.swizzle(graph.dfdy(graph.uv()), "y"), graph.float(-16)
            ),
            graph.float(0),
        ]
    )
    graph.set_output(COLOR_NODE, slope)
    var steep = draw(big_triangle(NodeProgramId(0), BASIC), one_program(graph^))
    assert_color(steep.color_at(3, 5), 1, 1, 0)
    # A varying of u squared is the corners' squares mixed: 0, 4 and 0,
    # weighed by the second corner's share, (x + 0.5) / 32.
    var curve = NodeGraph()
    var u = curve.swizzle(curve.uv(), "x")
    var mixed = curve.varying(curve.mul(u, u))
    curve.set_output(
        COLOR_NODE, curve.join([mixed, curve.mul(u, u), curve.float(0)])
    )
    var bent = draw(big_triangle(NodeProgramId(0), BASIC), one_program(curve^))
    var here = bent.color_at(2, 2)
    assert_almost_equal(here.r, 4 * 2.5 / 32, atol=1e-5)
    assert_almost_equal(here.g, (2.5 / 16) * (2.5 / 16), atol=1e-5)


def test_a_texture_uniform_must_name_a_texture_to_draw() raises:
    var graph = NodeGraph()
    var map = graph.texture_uniform("map")
    graph.set_output(
        COLOR_NODE, graph.swizzle(graph.texture(map, graph.uv()), "rgb")
    )
    var programs = one_program(graph^)
    with assert_raises(contains="names no texture; call set_texture() first"):
        _ = draw(big_triangle(NodeProgramId(0), BASIC), programs, SHADE_TEXTURE)
    # A mode that opens no texture needs none.
    _ = draw(big_triangle(NodeProgramId(0), BASIC), programs, SHADE_LIT)
    var textures = TextureStore()
    var red = textures.add(a_texture())
    programs.get(NodeProgramId(0)).set_texture("map", red)
    var read = draw(
        big_triangle(NodeProgramId(0), BASIC), programs, SHADE_TEXTURE, textures
    )
    assert_color(read.color_at(2, 2), 1, 0, 0)


# --- the renderer -------------------------------------------------------------


def a_camera() raises -> PerspectiveCamera:
    """Return a camera four meters up +z looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def a_scene(
    mut assets: Assets, material: Material, normals: Bool = True
) raises -> Scene:
    """Return a scene of one two-meter plane facing the camera."""
    var geometry = plane(Length(2.0, METER), Length(2.0, METER), 2, 2)
    if not normals:
        var bare = BufferGeometry()
        bare.set_attribute(
            String(POSITION),
            geometry.attribute_view(String(POSITION)).clone(),
        )
        bare.set_attribute(
            String(UV), geometry.attribute_view(String(UV)).clone()
        )
        bare.set_index(geometry.index.copy())
        geometry = bare^
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(geometry^),
            assets.materials.add(material),
            node,
        )
    )
    scene.update()
    return scene^


def middle(image: Framebuffer) raises -> Color:
    """Return the middle pixel."""
    return image.get_pixel(SIZE // 2, SIZE // 2)


def test_a_uniform_changed_between_frames_changes_the_next() raises:
    var assets = Assets()
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.uniform("tint", Color(255, 0, 0)))
    var id = assets.programs.add(graph.compile())
    var scene = a_scene(assets, shader_material(id))
    var renderer = Renderer(SIZE, SIZE)
    var red = middle(renderer.render(scene, assets, a_camera()))
    assert_equal(red.r, 255)
    assert_equal(red.b, 0)
    assets.programs.get(id).set_uniform("tint", Color(0, 0, 255))
    var blue = middle(renderer.render(scene, assets, a_camera()))
    assert_equal(blue.r, 0)
    assert_equal(blue.b, 255)


def test_a_fragment_knows_its_pixel_and_its_neighbors() raises:
    var assets = Assets()
    var graph = NodeGraph()
    var place = graph.frag_coord()
    var across = graph.dfdx(graph.swizzle(place, "x"))
    var up = graph.dfdy(graph.swizzle(place, "y"))
    graph.set_output(COLOR_NODE, graph.join([across, up, graph.float(0)]))
    var id = assets.programs.add(graph.compile())
    var scene = a_scene(assets, shader_material(id))
    var image = Renderer(SIZE, SIZE).render(scene, assets, a_camera())
    # One pixel right is one more across, and one pixel up one more up.
    var seen = middle(image)
    assert_equal(seen.r, 255)
    assert_equal(seen.g, 255)
    assert_equal(seen.b, 0)


def test_a_fragment_knows_which_way_its_triangle_faces() raises:
    # TSL's frontFacing and faceDirection, and GLSL's gl_FrontFacing, which
    # three.js's WebGL renderer turns round under BACK_SIDE.
    var graph = NodeGraph()
    var direction = graph.add(
        graph.mul(graph.face_direction(), graph.float(0.5)), graph.float(0.5)
    )
    graph.set_output(
        COLOR_NODE,
        graph.join([graph.front_facing(), graph.gl_front_facing(), direction]),
    )
    var sides = [FRONT_SIDE, DOUBLE_SIDE, DOUBLE_SIDE, BACK_SIDE]
    var heights = [Float32(4), Float32(4), Float32(-4), Float32(-4)]
    var greens = [255, 255, 0, 255]
    for index in range(4):
        var assets = Assets()
        var id = assets.programs.add(graph.compile())
        var scene = a_scene(assets, shader_material(id, side=sides[index]))
        var camera = a_camera()
        camera.place(Vector3(0, 0, heights[index]), Vector3(0, 0, 0))
        var seen = middle(Renderer(SIZE, SIZE).render(scene, assets, camera))
        var front = 255 if heights[index] > 0 else 0
        assert_equal(Int(seen.r), front)
        assert_equal(Int(seen.g), greens[index])
        assert_equal(Int(seen.b), front)


def test_a_custom_attribute_of_the_geometry_colors_the_mesh() raises:
    # The same tint at every vertex; a pair read as a vec3 takes zero for
    # its missing float, and an attribute the geometry lacks all zeros and
    # one, as WebGL fills them.
    var graph = NodeGraph()
    var tint = graph.attribute("tint", NODE_FLOAT)
    var pair = graph.attribute("pair", NODE_VEC3)
    var missing = graph.attribute("missing", NODE_VEC4)
    graph.set_output(
        COLOR_NODE,
        graph.join(
            [
                tint,
                graph.add(graph.swizzle(pair, "y"), graph.swizzle(pair, "z")),
                graph.add(
                    graph.swizzle(missing, "w"), graph.swizzle(missing, "x")
                ),
            ]
        ),
    )
    var assets = Assets()
    var id = assets.programs.add(graph.compile())
    var geometry = plane(Length(2.0, METER), Length(2.0, METER), 2, 2)
    var count = geometry.attribute_view(String(POSITION)).count()
    var tints = List[Float32]()
    var pairs = List[Float32]()
    for _ in range(count):
        tints.append(0.25)
        pairs.append(0.1)
        pairs.append(0.5)
    geometry.set_attribute("tint", BufferAttribute(tints^, 1))
    geometry.set_attribute("pair", BufferAttribute(pairs^, 2))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(
        Mesh(
            assets.geometries.add(geometry^),
            assets.materials.add(shader_material(id)),
            node,
        )
    )
    scene.update()
    var seen = middle(Renderer(SIZE, SIZE).render(scene, assets, a_camera()))
    assert_equal(Int(seen.r), 137)
    assert_equal(Int(seen.g), 188)
    assert_equal(Int(seen.b), 255)


def a_cube() raises -> CubeTexture:
    """Return a cube of six flat faces, linear: red +x, green -x, blue
    +y, yellow -y, cyan +z, magenta -z."""
    var faces = List[Texture]()
    for color in [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 0),
        Color(0, 255, 255),
        Color(255, 0, 255),
    ]:
        var pixels = List[UInt8]()
        for _ in range(4):
            pixels.append(color.r)
            pixels.append(color.g)
            pixels.append(color.b)
            pixels.append(255)
        faces.append(Texture(2, 2, pixels^, CLAMP, NEAREST, LINEAR, False))
    return CubeTexture(faces^)


def test_a_node_program_reads_a_cube_in_a_direction() raises:
    # The cube uniform looks along +z, the cyan face.
    var assets = Assets()
    var sky = assets.cube_textures.add(a_cube())
    var graph = NodeGraph()
    var read = graph.texture_cube(
        graph.cube_uniform("sky"), graph.vec3(0, 0, 1)
    )
    graph.set_output(COLOR_NODE, graph.swizzle(read, "rgb"))
    var id = assets.programs.add(graph.compile())
    var scene = a_scene(assets, shader_material(id))
    var renderer = Renderer(SIZE, SIZE)
    renderer.shading = SHADE_TEXTURE
    # Unset, the cube is refused before a pixel is drawn.
    with assert_raises(contains="reads a cube uniform that names no cube"):
        _ = renderer.render(scene, assets, a_camera())
    assets.programs.get(id).set_cube("sky", sky)
    var seen = middle(renderer.render(scene, assets, a_camera()))
    assert_equal(Int(seen.r), 0)
    assert_equal(Int(seen.g), 255)
    assert_equal(Int(seen.b), 255)
    # A cube that is not in the store is refused.
    assets.programs.get(id).set_cube("sky", CubeTextureId(7))
    with assert_raises(
        contains="A node program reads a cube that is not there"
    ):
        _ = renderer.render(scene, assets, a_camera())


def a_stack(first: Color, second: Color) raises -> VolumeImage:
    """Return two texels a side and two deep: `first` in the front layer
    and `second` in the back one."""
    var pixels = List[UInt8]()
    for color in [first, second]:
        for _ in range(4):
            pixels.append(color.r)
            pixels.append(color.g)
            pixels.append(color.b)
            pixels.append(255)
    return VolumeImage.of_bytes(2, 2, 2, pixels)


def test_a_node_program_reads_a_3d_and_an_array_texture() raises:
    # The 3D texture's back layer is green and the array's front layer
    # blue, so the sum is cyan.
    var assets = Assets()
    var cloud = assets.data_3d_textures.add(
        Data3DTexture(a_stack(Color(255, 0, 0), Color(0, 255, 0)))
    )
    var layers = assets.data_array_textures.add(
        DataArrayTexture(a_stack(Color(0, 0, 255), Color(255, 255, 0)))
    )
    var graph = NodeGraph()
    var deep = graph.texture_3d(
        graph.volume_uniform("cloud"), graph.vec3(0.5, 0.5, 0.75)
    )
    var layered = graph.texture_array(
        graph.array_uniform("layers"), graph.vec3(0.5, 0.5, 0)
    )
    graph.set_output(COLOR_NODE, graph.swizzle(graph.add(deep, layered), "rgb"))
    var id = assets.programs.add(graph.compile())
    var scene = a_scene(assets, shader_material(id))
    var renderer = Renderer(SIZE, SIZE)
    renderer.shading = SHADE_TEXTURE
    # Unset, each is refused before a pixel is drawn.
    with assert_raises(contains="names no texture; call set_volume() first"):
        _ = renderer.render(scene, assets, a_camera())
    assets.programs.get(id).set_volume("cloud", cloud)
    with assert_raises(contains="names no texture; call set_array() first"):
        _ = renderer.render(scene, assets, a_camera())
    assets.programs.get(id).set_array("layers", layers)
    var seen = middle(renderer.render(scene, assets, a_camera()))
    assert_equal(Int(seen.r), 0)
    assert_equal(Int(seen.g), 255)
    assert_equal(Int(seen.b), 255)
    # One that is not in the store is refused.
    assets.programs.get(id).set_volume("cloud", Data3DTextureId(7))
    with assert_raises(contains="reads a 3D texture that is not there"):
        _ = renderer.render(scene, assets, a_camera())
    assets.programs.get(id).set_volume("cloud", cloud)
    assets.programs.get(id).set_array("layers", DataArrayTextureId(7))
    with assert_raises(contains="reads an array texture that is not there"):
        _ = renderer.render(scene, assets, a_camera())


def test_the_frame_carries_the_renderers_time_and_the_cameras_view() raises:
    var assets = Assets()
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.swizzle(graph.sin(graph.time()), "xxx"))
    var id = assets.programs.add(graph.compile())
    var scene = a_scene(assets, shader_material(id))
    var renderer = Renderer(SIZE, SIZE)
    renderer.time = Duration(0.5, SECOND)
    var frame = renderer.prepare_frame(scene, assets, a_camera())
    ref program = frame.programs.get(id)
    assert_equal(program.code[PROGRAM_TIME], 0.5)
    # The camera stands four meters up +z, so the view moves z by -4.
    assert_equal(program.code[PROGRAM_VIEW + 14], -4)
    # The store the assets hold is left at time zero.
    assert_equal(assets.programs.get(id).code[PROGRAM_TIME], 0)
    var image = renderer.render(scene, assets, a_camera())
    assert_true(middle(image).r > 100)
    # Anti-aliased, the supersampled frame keeps the time.
    renderer.set_antialias(True)
    var smooth = renderer.render(scene, assets, a_camera())
    assert_equal(middle(smooth).r, middle(image).r)


def lifted(normals: Bool) raises -> NodeGraph:
    """Return a graph that lifts each vertex a meter along its normal, and
    a meter up y, and shows white."""
    var graph = NodeGraph()
    graph.set_output(
        POSITION_NODE,
        graph.add(graph.normal_local(), graph.vec3(0, 1, 0)),
    )
    graph.set_output(COLOR_NODE, graph.vec3(1, 1, 1))
    return graph^


def test_a_position_node_moves_the_surface_before_it_is_drawn() raises:
    # Lifted a meter along +z toward the camera and a meter up, the plane
    # covers the middle no longer and the top edge instead.
    var assets = Assets()
    var id = assets.programs.add(lifted(True).compile())
    var scene = a_scene(assets, shader_material(id))
    var renderer = Renderer(SIZE, SIZE)
    var image = renderer.render(scene, assets, a_camera())
    assert_equal(middle(image).r, renderer.background.r)
    assert_equal(image.get_pixel(SIZE // 2, 1).r, 255)
    # A geometry with no normals reads zero, so it moves only up.
    var bare = Assets()
    var bare_id = bare.programs.add(lifted(False).compile())
    var flat = a_scene(bare, shader_material(bare_id), normals=False)
    var up = renderer.render(flat, bare, a_camera())
    assert_equal(up.get_pixel(SIZE // 2, 3).r, 255)


def test_a_moved_mesh_is_drawn_where_its_bound_would_cull_it() raises:
    # Moved ten meters, the plane leaves its bound: the graph moves it back
    # into view from ten meters away, and it is still drawn.
    var assets = Assets()
    var graph = NodeGraph()
    graph.set_output(POSITION_NODE, graph.vec3(-10, 0, 0))
    graph.set_output(COLOR_NODE, graph.vec3(1, 1, 1))
    var id = assets.programs.add(graph.compile())
    var scene = a_scene(assets, shader_material(id))
    scene.node(NodeId(0)).set_position(10, 0, 0)
    scene.update()
    var image = Renderer(SIZE, SIZE).render(scene, assets, a_camera())
    assert_equal(middle(image).r, 255)
    # A program id that names nothing is culled first, and never read.
    var lost = Assets()
    var nowhere = a_scene(lost, shader_material(NodeProgramId(4)))
    nowhere.node(NodeId(0)).set_position(10, 0, 0)
    nowhere.update()
    _ = Renderer(SIZE, SIZE).render(nowhere, lost, a_camera())


def test_the_renderer_refuses_a_program_that_is_not_there() raises:
    var assets = Assets()
    var scene = a_scene(assets, shader_material(NodeProgramId(0)))
    with assert_raises(contains="names a node program that is not there"):
        _ = Renderer(SIZE, SIZE).render(scene, assets, a_camera())
    var graph = NodeGraph()
    graph.set_output(
        COLOR_NODE,
        graph.swizzle(graph.texture(TextureId(0), graph.uv()), "rgb"),
    )
    _ = assets.programs.add(graph.compile())
    with assert_raises(contains="reads a texture that is not there"):
        _ = Renderer(SIZE, SIZE).render(scene, assets, a_camera())
    _ = assets.textures.add(a_texture())
    _ = Renderer(SIZE, SIZE).render(scene, assets, a_camera())


def test_a_sprite_runs_its_node_material() raises:
    # The square's coordinates, as a mesh's reach its graph. The sprite is
    # 4.8 pixels wide, and the middle pixel's center is half a pixel right
    # of the sprite's and half a pixel below it: (0.6, 0.4).
    var assets = Assets()
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.join([graph.uv(), graph.float(1)]))
    var id = assets.programs.add(graph.compile())
    var scene = Scene()
    var at = scene.add(Object3D())
    scene.add_sprite(Sprite(assets.materials.add(shader_material(id)), at))
    scene.update()
    var seen = middle(Renderer(SIZE, SIZE).render(scene, assets, a_camera()))
    assert_equal(Int(seen.r), 204)
    assert_equal(Int(seen.g), 169)
    assert_equal(Int(seen.b), 255)
    # A position node moves a mesh's vertices, which a sprite has none of.
    var lifted_graph = lifted(True)
    var moved = assets.programs.add(lifted_graph.compile())
    var moving = Scene()
    at = moving.add(Object3D())
    moving.add_sprite(Sprite(assets.materials.add(shader_material(moved)), at))
    moving.update()
    with assert_raises(
        contains="A sprite's node material has no position node"
    ):
        _ = Renderer(SIZE, SIZE).render(moving, assets, a_camera())


def test_wide_lines_refuse_a_node_material() raises:
    var assets = Assets()
    var graph = NodeGraph()
    graph.set_output(COLOR_NODE, graph.vec3(1, 1, 1))
    var id = assets.programs.add(graph.compile())
    var noded = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, nodes=id)
    )
    var bare = BufferGeometry()
    bare.set_attribute(
        String(POSITION), BufferAttribute([Float32(-1), 0, 0, 1, 0, 0], 3)
    )
    var shape = assets.geometries.add(bare^)
    var camera = a_camera()
    var renderer = Renderer(SIZE, SIZE)
    var wide = Scene()
    var at = wide.add(Object3D())
    var sticks = assets.geometries.add(
        line_segments_geometry([Vector3(-1, 0, 0), Vector3(1, 0, 0)])
    )
    wide.add_wide_line(LineSegments2(sticks, noded, at))
    wide.update()
    with assert_raises(contains="A wide line runs no node graph"):
        _ = renderer.render(wide, assets, camera)


def test_lines_run_a_node_material() raises:
    # A line across the middle, colored by its coordinate and a custom
    # attribute. A position node that moves it nowhere keeps it from being
    # culled by its bound.
    var assets = Assets()
    var graph = NodeGraph()
    graph.set_output(
        COLOR_NODE,
        graph.join(
            [
                graph.swizzle(graph.uv(), "x"),
                graph.attribute("green", NODE_FLOAT),
                graph.float(1),
            ]
        ),
    )
    graph.set_output(POSITION_NODE, graph.vec3(0, 0, 0))
    var id = assets.programs.add(graph.compile())
    var noded = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, nodes=id)
    )
    var bare = BufferGeometry()
    bare.set_attribute(
        String(POSITION), BufferAttribute([Float32(-1), 0, 0, 1, 0, 0], 3)
    )
    bare.set_attribute(String(UV), BufferAttribute([Float32(1), 0, 1, 0], 2))
    bare.set_attribute("green", BufferAttribute([Float32(0), 0], 1))
    var shape = assets.geometries.add(bare^)
    var scene = Scene()
    var at = scene.add(Object3D())
    scene.add_line(Line(shape, noded, at))
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var seen = middle(renderer.render(scene, assets, a_camera()))
    assert_equal(Int(seen.r), 255)
    assert_equal(Int(seen.g), 0)
    assert_equal(Int(seen.b), 255)


def test_points_run_a_node_material() raises:
    # One point at the origin, six pixels across from its own `size`
    # attribute, colored from its coordinate. A position node that moves
    # it nowhere keeps it from being culled by its bound.
    var assets = Assets()
    var graph = NodeGraph()
    var uv = graph.uv()
    graph.set_output(
        COLOR_NODE,
        graph.join(
            [graph.swizzle(uv, "x"), graph.swizzle(uv, "y"), graph.float(1)]
        ),
    )
    graph.set_output(SIZE_NODE, graph.attribute("size", NODE_FLOAT))
    graph.set_output(POSITION_NODE, graph.vec3(0, 0, 0))
    var id = assets.programs.add(graph.compile())
    var noded = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, nodes=id)
    )
    var one = BufferGeometry()
    one.set_attribute(String(POSITION), BufferAttribute([Float32(0), 0, 0], 3))
    one.set_attribute(String(UV), BufferAttribute([Float32(1), 0], 2))
    one.set_attribute("size", BufferAttribute([Float32(6)], 1))
    var shape = assets.geometries.add(one^)
    var scene = Scene()
    var at = scene.add(Object3D())
    scene.add_points(Points(shape, noded, at))
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(scene, assets, a_camera())
    var seen = middle(image)
    assert_equal(Int(seen.r), 255)
    assert_equal(Int(seen.g), 0)
    assert_equal(Int(seen.b), 255)
    # Six pixels across: columns five to ten.
    assert_equal(Int(image.get_pixel(5, SIZE // 2).b), 255)
    assert_equal(Int(image.get_pixel(4, SIZE // 2).b), 0)
    # A size that is not above zero is refused.
    var flat = NodeGraph()
    flat.set_output(SIZE_NODE, flat.float(0))
    var nothing = assets.programs.add(flat.compile())
    var unsized = assets.materials.add(
        Material(Color(255, 255, 255), kind=BASIC, nodes=nothing)
    )
    var bad = Scene()
    at = bad.add(Object3D())
    bad.add_points(Points(shape, unsized, at))
    bad.update()
    with assert_raises(contains="size node gave a size that is not above"):
        _ = renderer.render(bad, assets, a_camera())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
