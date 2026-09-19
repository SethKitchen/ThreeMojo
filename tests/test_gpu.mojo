# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.gpu`.

The important property is not that the kernel runs but that it agrees with the
CPU rasterizer exactly, pixel for pixel. Two implementations of the same edge
test can easily drift at the boundary, and a triangle whose edge falls half a
pixel differently is a bug that no aggregate check would catch.

Tests needing hardware return early when none is present, so the suite passes
on a machine without a GPU rather than failing for the wrong reason. They say
so on the way out: a silent early return is indistinguishable from a pass, and
"the GPU tests are green" must not be able to mean "they never ran".

Parity alone is not enough either. Every comparison that expects a visible
triangle also asserts the CPU image is partly covered, because two renderers
agree trivially when both draw nothing. Two of these tests did exactly that:
their corners lay entirely outside the image they were drawn into.

Images are kept small deliberately. Comparing two renders means reading every
pixel of both, and `Framebuffer.get_pixel` is instrumented when the coverage
tool runs, so each pixel costs a record written to stderr. A 320x240
comparison produced 112 MB of them and dominated the entire coverage run.
"""

from materials.material import Blending, MaterialKind
from cameras.camera import Camera
from cameras.orthographic_camera import centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from materials.material import Material
from core.object3d import Object3D
from core.object3d import NodeId, Object3D
from core.scene import Scene
from lights.light import ambient_light, directional_light, point_light
from geometries.box import cube
from geometries.sphere import sphere
from math.matrix4 import translation
from math.vector2 import Vector2
from std.math import inf, pi
from math.vector3 import Vector3
from objects.instanced_mesh import InstancedMesh
from objects.line import LOOP, Line
from objects.mesh import Mesh
from renderers.renderer import Renderer
from units.si import Angle, DEGREE, Length, METER
from render.framebuffer import Color, FloatColor, Framebuffer
from materials.material import BLEND, NO_TEXTURE, OPAQUE
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from render.srgb import SRGB
from render.texture import (
    BILINEAR,
    COVERAGE,
    IGNORED,
    NEAREST,
    CLAMP,
    MIRROR,
    REPEAT,
    Texture,
    checkerboard,
)
from lights.light import (
    ambient_light,
    directional_light,
    hemisphere_light,
    point_light,
    spot_light,
)
from lights.lighting import PERSPECTIVE_VIEW, Lighting
from core.fog import Fog, FogView, exp2_fog, linear_fog, no_fog
from render.tonemap import (
    ACES_FILMIC_TONE_MAPPING,
    AGX_TONE_MAPPING,
    CINEON_TONE_MAPPING,
    LINEAR_TONE_MAPPING,
    NEUTRAL_TONE_MAPPING,
    NO_TONE_MAPPING,
    REINHARD_TONE_MAPPING,
    ToneMapping,
)
from render.rasterizer import (
    DRAW_SEGMENTS,
    Draw,
    rasterize_all,
    rasterize_lines_all,
)
from units.si import InverseLength, PER_METER
from core.layers import Layers
from renderers.renderer import camera_position, camera_up, toward_camera
from render.gpu import (
    FLOATS_PER_VERTEX,
    LANE_DASH,
    LANE_GAP,
    LANE_LINE_DISTANCE,
    FOG_FLOATS,
    LIGHTS_AMBIENT,
    LIGHTS_EYE,
    LIGHTS_FIRST,
    LIGHTS_TOWARD,
    LIGHTS_UP,
    STATE_PER_TRIANGLE,
    TABLE_COLUMNS,
    GpuRenderer,
    available,
    flatten,
    flatten_fog,
    flatten_lights,
    flatten_textures,
    pack,
    render,
    render_triangles,
    triangle_state,
)
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import Alpha
from geometries.plane import plane
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, POSITION
from math.matrix4 import Matrix4
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT, SkinnedMesh
from materials.material import (
    BASIC,
    DEPTH,
    DOUBLE_SIDE,
    LAMBERT,
    MATCAP,
    NORMALS,
    PHONG,
    TOON,
    depth_material,
    matcap_material,
    normal_material,
    phong_material,
    toon_material,
)
from render.target import RenderTarget
from render.rasterizer import (
    SHADE_LIT,
    SHADE_TEXTURE,
    SHADE_UV,
    RasterVertex,
    ShadeMode,
    Triangle,
    check_output_kinds,
    rasterize,
    rasterize_shaded,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)


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


comptime BACKGROUND = Color(20, 24, 32)
# The intensity that lights a facing white surface to full white: three.js
# divides a light's contribution by pi, as `lights.lighting` explains.
comptime FULL = Float32(pi)
comptime FOREGROUND = Color(255, 128, 32)


def _apart(a: UInt8, b: UInt8) -> Int:
    """Return how many levels apart two channel values are."""
    if a > b:
        return Int(a) - Int(b)
    return Int(b) - Int(a)


def count_mismatches(
    left: Framebuffer, right: Framebuffer, tolerance: Int = 0
) raises -> Int:
    """Return how many pixels differ between two same-sized framebuffers.

    **On tolerance.** Which pixels a triangle covers is decided in integer
    arithmetic by `render.fillrule`, so the two renderers agree there
    exactly, and every coverage test below demands it with the default of
    zero. What a covered pixel is *colored* is floating point, and there the
    two cannot be held to the last bit: a GPU contracts `a * b + c` into a
    fused multiply-add, which rounds once instead of twice, so an interpolated
    channel can land one ULP either side of the CPU's value. That is
    invisible until the exact result sits on a rounding midpoint, which is
    where it was first seen — a sphere's ambient green of 190 * 0.25 = 47.5,
    quantizing to 48 on one and 47 on the other.

    So tests that interpolate real shading allow one level, and say so. A
    tolerance wide enough to hide a genuine disagreement would defeat the
    point; one level cannot hide a wrong color, a wrong depth or a wrong
    pixel.

    Args:
        left: First image.
        right: Second image.
        tolerance: How many levels a channel may differ by and still count as
            a match. Zero, unless the test interpolates color.

    Returns:
        The number of differing pixels.

    Raises:
        Error: If a coordinate is out of bounds.
    """
    var differences = 0
    for y in range(left.height):
        for x in range(left.width):
            var a = left.get_pixel(x, y)
            var b = right.get_pixel(x, y)
            if (
                _apart(a.r, b.r) > tolerance
                or _apart(a.g, b.g) > tolerance
                or _apart(a.b, b.b) > tolerance
                or _apart(a.a, b.a) > tolerance
            ):
                differences += 1
    return differences


def count_foreground(image: Framebuffer) raises -> Int:
    """Return how many pixels hold the foreground color.

    Parity between two renderers says nothing if both drew nothing, so the
    comparison tests assert on this as well. Two of them used to fill zero
    pixels — their triangles lay entirely outside the image — and compared
    one blank image against another for months.

    Args:
        image: The framebuffer to inspect.

    Returns:
        The number of foreground pixels.

    Raises:
        Error: If a coordinate is out of bounds.
    """
    var filled = 0
    for y in range(image.height):
        for x in range(image.width):
            var pixel = image.get_pixel(x, y)
            if (
                pixel.r == FOREGROUND.r
                and pixel.g == FOREGROUND.g
                and pixel.b == FOREGROUND.b
            ):
                filled += 1
    return filled


def assert_partly_covered(image: Framebuffer) raises:
    """Assert the triangle is visible but does not fill the whole image.

    Args:
        image: The framebuffer to inspect.

    Raises:
        Error: If nothing was drawn, or everything was.
    """
    var filled = count_foreground(image)
    assert_true(filled > 0, "the triangle covered no pixels at all")
    assert_true(
        filled < image.width * image.height,
        "the triangle covered the entire image, so no edge was tested",
    )


def rendered[
    C: Camera
](
    renderer: Renderer,
    mut scene: Scene,
    assets: Assets,
    meshes: List[Mesh],
    camera: C,
) raises -> Framebuffer:
    """Render `meshes` in `scene`; see `prepared`.

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


def prepared[
    C: Camera
](
    renderer: Renderer,
    mut scene: Scene,
    assets: Assets,
    meshes: List[Mesh],
    camera: C,
) raises -> List[RasterVertex]:
    """`Renderer.prepare` with a mesh list, as `rendered` is for `render`.

    Args:
        renderer: The renderer to prepare with.
        scene: The scene to draw; its mesh list is replaced.
        assets: The geometry, materials and textures the meshes name.
        meshes: What to draw.
        camera: The camera to project through.

    Returns:
        Raster vertices, three per triangle.

    Raises:
        Error: If preparation fails.
    """
    scene.meshes = meshes.copy()
    return renderer.prepare(scene, assets, camera)


def skipped_for_lack_of_a_gpu(name: String) -> Bool:
    """Return True if there is no accelerator, saying so on the way out.

    A test that returns early looks identical to one that passed. Announcing
    the skip is what keeps "the GPU tests are green" from meaning "the GPU
    tests never ran".
    """
    if available():
        return False
    print("SKIP (no accelerator):", name)
    return True


def cpu_render(
    triangle: Triangle, width: Int, height: Int
) raises -> Framebuffer:
    """Return the CPU rasterizer's output for the same inputs.

    Args:
        triangle: Screen-space triangle to fill.
        width: Image width.
        height: Image height.

    Returns:
        The rendered framebuffer.

    Raises:
        Error: If the dimensions are invalid.
    """
    var target = Framebuffer(width, height, BACKGROUND)
    rasterize(triangle, target, FOREGROUND)
    return target^


def test_colors_pack_into_a_big_endian_word() raises:
    assert_equal(pack(Color(0xAA, 0xBB, 0xCC, 0xDD)), UInt32(0xAABBCCDD))
    assert_equal(pack(Color(0, 0, 0, 0)), UInt32(0))
    assert_equal(pack(Color(255, 255, 255, 255)), UInt32(0xFFFFFFFF))


def test_alpha_survives_packing() raises:
    assert_equal(pack(Color(1, 2, 3, 128)) & UInt32(0xFF), UInt32(128))


def test_availability_is_answerable() raises:
    # Whatever the answer, asking must not raise.
    var present = available()
    assert_true(present or not present)


def test_gpu_matches_the_cpu_rasterizer() raises:
    if skipped_for_lack_of_a_gpu("gpu matches the cpu rasterizer"):
        return
    # These corners used to be (50,180), (160,40), (275,190) in an 80x60
    # image, which is entirely off the bottom and right. Both renderers
    # returned a cleared buffer and the parity check passed on nothing.
    var triangle = Triangle(Vector2(10, 50), Vector2(40, 8), Vector2(72, 54))
    var gpu = render(triangle, 80, 60, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 80, 60)
    assert_partly_covered(cpu)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_gpu_matches_the_cpu_on_a_clockwise_triangle() raises:
    if skipped_for_lack_of_a_gpu("gpu matches the cpu on a clockwise triangle"):
        return
    # Opposite winding takes the other side of the kernel's area test.
    var triangle = Triangle(Vector2(8, 40), Vector2(58, 44), Vector2(32, 6))
    var gpu = render(triangle, 64, 48, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 64, 48)
    assert_partly_covered(cpu)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_gpu_matches_the_cpu_on_a_degenerate_triangle() raises:
    if skipped_for_lack_of_a_gpu(
        "gpu matches the cpu on a degenerate triangle"
    ):
        return
    # Three collinear points have zero area and must cover nothing.
    var triangle = Triangle(Vector2(0, 0), Vector2(10, 10), Vector2(20, 20))
    var gpu = render(triangle, 32, 32, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 32, 32)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_gpu_matches_the_cpu_when_the_triangle_is_offscreen() raises:
    if skipped_for_lack_of_a_gpu(
        "gpu matches the cpu when the triangle is offscreen"
    ):
        return
    var triangle = Triangle(
        Vector2(-99, -99), Vector2(-80, -99), Vector2(-99, -80)
    )
    var gpu = render(triangle, 32, 32, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 32, 32)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_a_renderer_can_be_created_after_another_was_destroyed() raises:
    if skipped_for_lack_of_a_gpu(
        "a renderer can be created after another was destroyed"
    ):
        return
    # `render` builds a GpuRenderer, uses it and lets it die. Under CUDA on
    # WSL 2 the second one hung in its constructor for as long as the first
    # released its context before its buffers -- see GpuRenderer.__deinit__.
    # The Makefile's budget turns that hang into a failure; this names it.
    var triangle = Triangle(Vector2(2, 14), Vector2(8, 2), Vector2(14, 14))
    var first = render(triangle, 16, 16, BACKGROUND, FOREGROUND)
    var second = render(triangle, 16, 16, BACKGROUND, FOREGROUND)
    assert_partly_covered(first)
    assert_equal(count_mismatches(first, second), 0)


def test_they_agree_on_pixels_lying_exactly_on_an_edge() raises:
    # Corners on whole pixels put sample points exactly on the edges, which is
    # where the fill rule decides and where a difference between the two
    # implementations would show. Before both used the same fixed-point rule,
    # these tests passed only because their triangles avoided such pixels.
    if skipped_for_lack_of_a_gpu(
        "they agree on pixels lying exactly on an edge"
    ):
        return
    var triangle = Triangle(Vector2(4, 4), Vector2(28, 4), Vector2(28, 20))
    var gpu = render(triangle, 32, 24, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 32, 24)
    assert_partly_covered(cpu)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_they_agree_on_both_halves_of_a_shared_diagonal() raises:
    # The two triangles of a quad, drawn into one image by each renderer.
    if skipped_for_lack_of_a_gpu(
        "they agree on both halves of a shared diagonal"
    ):
        return
    var upper = Triangle(Vector2(2, 2), Vector2(26, 2), Vector2(26, 18))
    var gpu = render(upper, 32, 24, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(upper, 32, 24)
    assert_partly_covered(cpu)
    assert_equal(count_mismatches(cpu, gpu), 0)
    var lower = Triangle(Vector2(2, 2), Vector2(26, 18), Vector2(2, 18))
    var gpu_lower = render(lower, 32, 24, BACKGROUND, FOREGROUND)
    var cpu_lower = cpu_render(lower, 32, 24)
    assert_partly_covered(cpu_lower)
    assert_equal(count_mismatches(cpu_lower, gpu_lower), 0)


def test_size_not_divisible_by_the_tile_is_handled() raises:
    if skipped_for_lack_of_a_gpu("size not divisible by the tile is handled"):
        return
    # 17x13 leaves a partial tile on both edges, which the kernel must clip.
    var triangle = Triangle(Vector2(2, 11), Vector2(8, 2), Vector2(15, 12))
    var gpu = render(triangle, 17, 13, BACKGROUND, FOREGROUND)
    var cpu = cpu_render(triangle, 17, 13)
    assert_equal(gpu.width, 17)
    assert_equal(gpu.height, 13)
    assert_partly_covered(cpu)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_zero_width_is_rejected() raises:
    with assert_raises():
        _ = render(
            Triangle(Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)),
            0,
            8,
            BACKGROUND,
            FOREGROUND,
        )


def test_negative_height_is_rejected() raises:
    with assert_raises():
        _ = render(
            Triangle(Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)),
            8,
            -1,
            BACKGROUND,
            FOREGROUND,
        )


# --- the multi-triangle path ------------------------------------------------


def corner(
    x: Float32,
    y: Float32,
    z: Float32,
    inv_w: Float32,
    color: Color,
    blend: Blending = OPAQUE,
) -> RasterVertex:
    """Return a raster vertex, for building test triangles.

    Whether the surface composites is stated rather than inferred from its
    alpha, because that is how the renderer states it.
    """
    return RasterVertex(
        x, y, z, inv_w, FloatColor(of=color), 0, 0, NO_TEXTURE, blend
    )


def cpu_render_triangles(
    corners: List[RasterVertex],
    width: Int,
    height: Int,
    clear: Color = BACKGROUND,
) raises -> Framebuffer:
    """Return the CPU rasterizer's output for the same prepared triangles.

    Args:
        corners: Raster vertices, three per triangle.
        width: Image width.
        height: Image height.
        clear: The color to clear to.

    Returns:
        The rendered framebuffer.

    Raises:
        Error: If the dimensions are invalid.
    """
    var target = RenderTarget(width, height, clear)
    for index in range(len(corners) // 3):
        rasterize_shaded(
            corners[index * 3],
            corners[index * 3 + 1],
            corners[index * 3 + 2],
            target,
        )
    return target.resolve()


def overlapping_pair() -> List[RasterVertex]:
    """Return two overlapping triangles, the red one nearer than the green."""
    var corners = List[RasterVertex]()
    # Far, green, drawn first.
    corners.append(corner(2, 2, 0.8, 1, Color(0, 255, 0)))
    corners.append(corner(30, 2, 0.8, 1, Color(0, 255, 0)))
    corners.append(corner(2, 22, 0.8, 1, Color(0, 255, 0)))
    # Near, red, overlapping it.
    corners.append(corner(8, 6, 0.2, 1, Color(255, 0, 0)))
    corners.append(corner(34, 6, 0.2, 1, Color(255, 0, 0)))
    corners.append(corner(8, 26, 0.2, 1, Color(255, 0, 0)))
    return corners^


def test_the_gpu_resolves_depth_between_overlapping_triangles() raises:
    if skipped_for_lack_of_a_gpu("gpu resolves depth between triangles"):
        return
    var corners = overlapping_pair()
    var gpu = render_triangles(corners, 36, 30, BACKGROUND)
    var cpu = cpu_render_triangles(corners, 36, 30)
    # Both colors are visible, so the overlap really is partial.
    var reds = 0
    var greens = 0
    for y in range(30):
        for x in range(36):
            var pixel = cpu.get_pixel(x, y)
            if pixel.r > 200:
                reds += 1
            elif pixel.g > 200:
                greens += 1
    assert_true(reds > 0 and greens > 0, "the triangles did not overlap")
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_submitting_the_nearer_triangle_first_changes_nothing() raises:
    # Depth, not draw order, decides. On the GPU each thread owns its pixel
    # and keeps the nearest it finds, so order must not matter there either.
    if skipped_for_lack_of_a_gpu("submission order does not matter"):
        return
    var forwards = overlapping_pair()
    var backwards = List[RasterVertex]()
    for index in range(3):
        backwards.append(forwards[index + 3])
    for index in range(3):
        backwards.append(forwards[index])

    var first = render_triangles(forwards, 36, 30, BACKGROUND)
    var second = render_triangles(backwards, 36, 30, BACKGROUND)
    assert_equal(count_mismatches(first, second), 0)


def test_the_gpu_matches_the_cpu_on_a_perspective_gradient() raises:
    # Differing inv_w across the corners, so the perspective correction is
    # doing real work. Both implementations must apply it identically.
    if skipped_for_lack_of_a_gpu("gpu matches the cpu on a gradient"):
        return
    var corners = List[RasterVertex]()
    corners.append(corner(-5, -5, 0.5, 1.0, Color(255, 0, 0)))
    corners.append(corner(40, -5, 0.5, 0.25, Color(0, 0, 255)))
    corners.append(corner(-5, 40, 0.5, 0.6, Color(0, 255, 0)))
    var gpu = render_triangles(corners, 32, 24, BACKGROUND)
    var cpu = cpu_render_triangles(corners, 32, 24)
    # A gradient, not a flat fill: the corners must actually differ.
    assert_true(cpu.get_pixel(0, 0).r != cpu.get_pixel(31, 0).r)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_drawing_no_triangles_clears_to_the_background() raises:
    if skipped_for_lack_of_a_gpu("drawing nothing clears the target"):
        return
    var image = render_triangles(List[RasterVertex](), 16, 12, BACKGROUND)
    for y in range(12):
        for x in range(16):
            assert_equal(image.get_pixel(x, y).r, BACKGROUND.r)
            assert_equal(image.get_pixel(x, y).g, BACKGROUND.g)
            assert_equal(image.get_pixel(x, y).b, BACKGROUND.b)


def test_a_renderer_can_be_drawn_into_more_than_once() raises:
    # The reason `GpuRenderer` exists: an animation reuses one context and one
    # render target instead of allocating both per frame. A second draw must
    # completely replace the first, not blend with it.
    if skipped_for_lack_of_a_gpu("a renderer can be reused"):
        return
    var renderer = GpuRenderer(36, 30)
    var corners = overlapping_pair()
    renderer.draw(corners, BACKGROUND)
    var first = renderer.read_back()

    renderer.draw(List[RasterVertex](), BACKGROUND)
    var cleared = renderer.read_back()
    assert_equal(cleared.get_pixel(18, 15).r, BACKGROUND.r)

    # And drawing the original again reproduces it exactly.
    renderer.draw(corners, BACKGROUND)
    var again = renderer.read_back()
    assert_equal(count_mismatches(first, again), 0)


def test_a_renderer_grows_its_buffer_for_more_triangles() raises:
    # The vertex buffer starts at one triangle. Submitting more must grow it
    # rather than reading past the end or silently dropping the rest.
    if skipped_for_lack_of_a_gpu("a renderer grows its vertex buffer"):
        return
    var renderer = GpuRenderer(36, 30)
    renderer.draw(overlapping_pair(), BACKGROUND)
    var grown = renderer.read_back()
    var expected = cpu_render_triangles(overlapping_pair(), 36, 30)
    assert_equal(count_mismatches(expected, grown), 0)


def test_a_partial_triangle_is_rejected() raises:
    if skipped_for_lack_of_a_gpu("a partial triangle is rejected"):
        return
    var renderer = GpuRenderer(8, 8)
    var corners = List[RasterVertex]()
    corners.append(corner(0, 0, 0, 1, Color(255, 0, 0)))
    corners.append(corner(4, 0, 0, 1, Color(255, 0, 0)))
    with assert_raises():
        renderer.draw(corners, BACKGROUND)


def glowing(
    base: RasterVertex, glow: FloatColor, map: TextureId = NO_TEXTURE
) -> RasterVertex:
    """Return `base` giving off `glow`, through `map` if one is named."""
    return RasterVertex(
        base.x,
        base.y,
        base.z,
        base.inv_w,
        base.color,
        base.u,
        base.v,
        base.texture,
        base.blend,
        base.normal,
        base.world,
        base.kind,
        glow,
        map,
    )


def test_flattening_lays_out_a_lane_per_varying() raises:
    # The host side of the kernel's unpacking. If these disagree the image is
    # garbage, so the layout is asserted rather than assumed. The count is
    # spelled out because changing the stride and missing one of the kernel's
    # offsets is a mistake this project has made twice.
    var corners = List[RasterVertex]()
    corners.append(
        glowing(
            corner(1, 2, 3, 4, Color(255, 128, 0, 64)),
            FloatColor(0.25, 0.5, 0.75),
        )
    )
    var flat = flatten(corners)
    assert_equal(len(flat), 28)
    assert_equal(len(flat), FLOATS_PER_VERTEX)
    assert_equal(flat[0], Float32(1))
    assert_equal(flat[1], Float32(2))
    assert_equal(flat[2], Float32(3))
    assert_equal(flat[3], Float32(4))
    assert_equal(flat[4], Float32(1.0))
    assert_almost_equal(flat[5], Float32(128) / 255, atol=Float64(1e-6))
    assert_equal(flat[6], Float32(0))
    assert_almost_equal(flat[7], Float32(64) / 255, atol=Float64(1e-6))
    # The emissive rides after the world position, three lanes: it never
    # touches alpha. The camera-space depth rides last, for the fog.
    assert_equal(flat[16], Float32(0.25))
    assert_equal(flat[17], Float32(0.5))
    assert_equal(flat[18], Float32(0.75))
    assert_equal(flat[19], Float32(0))
    var deep = List[RasterVertex]()
    deep.append(RasterVertex(1, 2, 3, 4, FloatColor(1, 1, 1), view_depth=7.5))
    assert_equal(flatten(deep)[19], Float32(7.5))
    # The distance along a line and its dash and gap ride last, three
    # lanes, and a corner that says nothing about them carries zeros.
    assert_equal(flat[LANE_LINE_DISTANCE], Float32(0))
    assert_equal(flat[LANE_DASH], Float32(0))
    assert_equal(flat[LANE_GAP], Float32(0))
    var dashed = List[RasterVertex]()
    dashed.append(
        RasterVertex(
            1,
            2,
            3,
            4,
            FloatColor(1, 1, 1),
            line_distance=6.5,
            dash_size=3,
            gap_size=1,
        )
    )
    var lanes = flatten(dashed)
    assert_equal(lanes[LANE_LINE_DISTANCE], Float32(6.5))
    assert_equal(lanes[LANE_DASH], Float32(3))
    assert_equal(lanes[LANE_GAP], Float32(1))


def test_the_state_table_has_an_entry_per_map_and_policy() raises:
    # Texture, blend, material kind, emissive map, alpha map and gradient
    # map, all from the first corner.
    var corners = List[RasterVertex]()
    for _ in range(3):
        corners.append(
            RasterVertex(
                0,
                0,
                0.5,
                1,
                FloatColor(1, 1, 1),
                0,
                0,
                TextureId(2),
                BLEND,
                Vector3(0, 0, 1),
                Vector3(0, 0, 0),
                BASIC,
                FloatColor(0, 0, 0),
                TextureId(5),
            )
        )
    var state = triangle_state(corners)
    assert_equal(len(state), STATE_PER_TRIANGLE)
    assert_equal(state[0], Int32(2))
    assert_equal(state[1], Int32(BLEND.value))
    assert_equal(state[2], Int32(BASIC.value))
    assert_equal(state[3], Int32(5))
    assert_equal(state[4], Int32(NO_TEXTURE.value))
    assert_equal(state[5], Int32(NO_TEXTURE.value))
    assert_equal(state[6], Int32(NO_TEXTURE.value))
    # A matcap triangle's image rides the column after the ramp.
    assert_equal(triangle_state(matcap_pair(TextureId(8)))[6], Int32(8))
    assert_equal(triangle_state(matcap_pair())[6], Int32(NO_TEXTURE.value))
    # A toon triangle's ramp rides the last column.
    var stepped = toon_pair(TextureId(6))
    assert_equal(triangle_state(stepped)[5], Int32(6))
    assert_equal(triangle_state(toon_pair())[5], Int32(NO_TEXTURE.value))
    # And each of the other four kinds crosses as its own value.
    for kind in [LAMBERT, NORMALS, DEPTH, TOON, MATCAP]:
        var others = List[RasterVertex]()
        for _ in range(3):
            others.append(
                RasterVertex(0, 0, 0.5, 1, FloatColor(1, 1, 1), kind=kind)
            )
        assert_equal(triangle_state(others)[2], Int32(kind.value))


# --- one prepared scene, both backends --------------------------------------


def test_both_backends_agree_on_a_whole_prepared_scene() raises:
    # The architecture claim, checked rather than asserted in a comment: the
    # renderer prepares triangles once, and the CPU and GPU rasterizers fill
    # exactly the same list. Anything that drifted between the two — the fill
    # rule, the depth test, the perspective correction, the quantization —
    # shows up here as differing pixels.
    if skipped_for_lack_of_a_gpu("both backends agree on a prepared scene"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)

    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 12, 8))

    var scene = Scene()
    var left = Object3D()
    left.set_position(-0.9, 0, 0)
    left.set_euler(Angle(25.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE))
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.9, 0, 0.4)
    var right_node = scene.add(right^)
    light_the(scene)
    scene.update()

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.6, 3.0), Vector3(0, 0, 0))

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 140, 40))), left_node
        )
    )
    meshes.append(
        Mesh(
            ball,
            assets.materials.add(Material(Color(90, 190, 255))),
            right_node,
        )
    )

    # Prepared once, filled twice.
    var corners = prepared(renderer, scene, assets, meshes, camera)
    assert_true(len(corners) > 0, "the scene prepared no triangles")
    assert_equal(len(corners) % 3, 0)

    # "Prepared once, filled twice" has to be literally true or the test is
    # weaker than it reads: calling `render` here would prepare the scene a
    # second time and compare two pipelines rather than two rasterizers.
    # Lighting is per fragment now and is no longer baked into the corners,
    # so both sides get the same resolved lights as well as the same list.
    var lighting = Lighting(scene)
    var target = RenderTarget(48, 36, BACKGROUND)
    for triangle in range(len(corners) // 3):  # pragma: no branch
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            target,
            SHADE_LIT,
            assets.textures,
            lighting,
        )
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 48, 36, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )

    # A real image: both meshes visible, and plenty of background left.
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 100, "the scene barely drew anything")
    assert_true(drawn < 48 * 36, "the scene filled the whole image")
    # One level of tolerance: this scene interpolates real shading, and the
    # two do not round identically. See `count_mismatches`.
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_agree_on_vertex_colors() raises:
    # A cube colored by its own vertices, each corner's color taken from
    # where it sits, lit and turned so several faces show: the per-corner
    # color both rasterizers interpolate now varies within a mesh, and
    # they must still fill the same list to the same pixels.
    if skipped_for_lack_of_a_gpu("both backends agree on vertex colors"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)

    var assets = Assets()
    var box = cube(Length(1.2, METER))
    var tints = List[Float32]()
    ref positions = box.attribute_view(String(POSITION))
    for vertex in range(positions.count()):
        var at = positions.vector3(vertex)
        tints.append((at.x + 0.6) / 1.2)
        tints.append((at.y + 0.6) / 1.2)
        tints.append((at.z + 0.6) / 1.2)
    box.set_attribute(String(COLOR), BufferAttribute(tints^, 3))
    var tinted = assets.geometries.add(box^)

    var scene = Scene()
    var turned = Object3D()
    turned.set_euler(
        Angle(30.0, DEGREE), Angle(40.0, DEGREE), Angle(0.0, DEGREE)
    )
    var node = scene.add(turned^)
    light_the(scene)
    scene.update()

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.5, 3.0), Vector3(0, 0, 0))

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            tinted,
            assets.materials.add(
                Material(Color(255, 255, 255), vertex_colors=True)
            ),
            node,
        )
    )

    var corners = prepared(renderer, scene, assets, meshes, camera)
    assert_true(len(corners) > 0, "the cube prepared no triangles")
    var lighting = Lighting(scene)
    var target = RenderTarget(48, 36, BACKGROUND)
    for triangle in range(len(corners) // 3):  # pragma: no branch
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            target,
            SHADE_LIT,
            assets.textures,
            lighting,
        )
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 48, 36, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 100, "the cube barely drew anything")
    assert_true(drawn < 48 * 36, "the cube filled the whole image")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_agree_on_a_layered_scene() raises:
    # The whole-scene test with the ball and a second sun moved to layer
    # one, which the camera does not watch. Both backends get the one list
    # `prepare` made without the ball and the one `Lighting` resolved
    # without that sun, and fill it to the same pixels.
    if skipped_for_lack_of_a_gpu("both backends agree on a layered scene"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)

    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 12, 8))

    var scene = Scene()
    var left = Object3D()
    left.set_position(-0.9, 0, 0)
    left.set_euler(Angle(25.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE))
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.9, 0, 0.4)
    right.layers.set(1)
    var right_node = scene.add(right^)
    light_the(scene)
    var extra = Object3D()
    extra.set_position(-1.0, 0.2, 2.0)
    var extra_node = scene.add(extra^)
    var unseen = directional_light(Color(255, 255, 255), extra_node)
    unseen.layers.set(1)
    scene.add_light(unseen)
    scene.update()

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.6, 3.0), Vector3(0, 0, 0))

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 140, 40))), left_node
        )
    )
    meshes.append(
        Mesh(
            ball,
            assets.materials.add(Material(Color(90, 190, 255))),
            right_node,
        )
    )
    var box_alone = List[Mesh]()
    box_alone.append(meshes[0])

    # The camera's list is the box's list: the ball is not in it.
    var corners = prepared(renderer, scene, assets, meshes, camera)
    var expected = prepared(renderer, scene, assets, box_alone, camera)
    assert_equal(len(corners), len(expected))
    assert_true(len(corners) > 0, "the scene prepared no triangles")

    # And the camera's lights are the two on layer zero, not the three.
    var lighting = Lighting(scene, visible=camera.visible_layers())
    assert_equal(lighting.count(), 1)
    assert_equal(Lighting(scene).count(), 2)

    var target = RenderTarget(48, 36, BACKGROUND)
    for triangle in range(len(corners) // 3):  # pragma: no branch
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            target,
            SHADE_LIT,
            assets.textures,
            lighting,
        )
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 48, 36, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 100, "the scene barely drew anything")
    assert_true(drawn < 48 * 36, "the scene filled the whole image")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_agree_under_point_lights() raises:
    # The whole-scene test again with bulbs instead of a sun: the fragment's
    # world position now matters, and so does `falloff`, on both sides. One
    # bulb falls off freely and one is cut off, so both branches run.
    if skipped_for_lack_of_a_gpu("both backends agree under point lights"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)

    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 12, 8))

    var scene = Scene()
    var left = Object3D()
    left.set_position(-0.9, 0, 0)
    left.set_euler(Angle(25.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE))
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.9, 0, 0.4)
    var right_node = scene.add(right^)
    var warm = Object3D()
    warm.set_position(0.5, 1.0, 1.5)
    var warm_node = scene.add(warm^)
    scene.add_light(point_light(Color(255, 220, 180), warm_node, 0.8))
    var cool = Object3D()
    cool.set_position(-1.5, 0.5, 1.0)
    var cool_node = scene.add(cool^)
    scene.add_light(point_light(Color(120, 160, 255), cool_node, 1.5, 1.0, 2.5))
    scene.add_light(ambient_light(Color(255, 255, 255), 0.1))
    scene.update()

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.6, 3.0), Vector3(0, 0, 0))

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 140, 40))), left_node
        )
    )
    meshes.append(
        Mesh(
            ball,
            assets.materials.add(Material(Color(90, 190, 255))),
            right_node,
        )
    )

    var corners = prepared(renderer, scene, assets, meshes, camera)
    var lighting = Lighting(scene)
    assert_equal(lighting.point_count(), 2)
    var target = RenderTarget(48, 36, BACKGROUND)
    for triangle in range(len(corners) // 3):  # pragma: no branch
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            target,
            SHADE_LIT,
            assets.textures,
            lighting,
        )
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 48, 36, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 100, "the scene barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_flattening_lights_lays_out_the_sky_and_the_cone() raises:
    # The camera first, then the ambient term, then nine floats per
    # hemisphere light after the point lights and thirteen per spot light
    # after those, in the order the kernel unpacks them.
    var scene = Scene()
    var up = Object3D()
    up.set_position(0, 4, 0)
    var up_node = scene.add(up^)
    var bulb = Object3D()
    bulb.set_position(0, 2, 0)
    var bulb_node = scene.add(bulb^)
    scene.update()
    scene.add_light(ambient_light(Color(255, 255, 255), 0.5))
    scene.add_light(
        hemisphere_light(Color(255, 255, 255), Color(0, 0, 0), up_node, 0.25)
    )
    scene.add_light(
        spot_light(
            Color(255, 255, 255),
            bulb_node,
            2.0,
            7.0,
            Angle(60.0, DEGREE),
            0.5,
            1.0,
        )
    )
    var lighting = Lighting(scene)
    var flat = flatten_lights(lighting)
    assert_equal(len(flat), LIGHTS_FIRST + 9 + 13)
    assert_almost_equal(flat[LIGHTS_AMBIENT], Float32(0.5), atol=Float64(1e-6))
    # The sky is straight up, white at a quarter, over a black ground.
    var sky = LIGHTS_FIRST
    assert_almost_equal(flat[sky + 1], Float32(1), atol=Float64(1e-6))
    assert_almost_equal(flat[sky + 3], Float32(0.25), atol=Float64(1e-6))
    assert_almost_equal(flat[sky + 6], Float32(0), atol=Float64(1e-6))
    # The bulb two meters up, pointing down at the origin, so its axis from
    # the target toward it is +y; twice white; decay one and a cutoff of
    # seven; and the cosines of sixty and thirty degrees.
    var beam = sky + 9
    assert_almost_equal(flat[beam + 1], Float32(2), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 4], Float32(1), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 6], Float32(2), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 9], Float32(1), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 10], Float32(7), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 11], Float32(0.5), atol=Float64(1e-6))
    assert_almost_equal(flat[beam + 12], Float32(0.8660254), atol=Float64(1e-6))


def test_both_backends_agree_under_hemisphere_and_spot_lights() raises:
    # The point-light scene again under a sky and two cones: one soft-edged
    # and aimed at the origin, one hard-edged with a cutoff and aimed at a
    # node. Every branch of both new kinds runs on both sides -- inside,
    # on the rim, outside, behind -- and the images must agree.
    if skipped_for_lack_of_a_gpu(
        "both backends agree under hemisphere and spot lights"
    ):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)

    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 12, 8))
    var floor = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER), 2, 2)
    )

    var scene = Scene()
    var ground = Object3D()
    ground.set_position(0, -0.7, 0)
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var left = Object3D()
    left.set_position(-0.9, 0, 0)
    left.set_euler(Angle(25.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE))
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.9, 0, 0.4)
    var right_node = scene.add(right^)
    var sky = Object3D()
    sky.set_position(0.2, 3.0, 0.1)
    var sky_node = scene.add(sky^)
    scene.add_light(
        hemisphere_light(
            Color(120, 160, 255), Color(120, 80, 40), sky_node, 0.6 * FULL
        )
    )
    var soft = Object3D()
    soft.set_position(0.5, 2.5, 1.5)
    var soft_node = scene.add(soft^)
    scene.add_light(
        spot_light(
            Color(255, 220, 180),
            soft_node,
            3.0 * FULL,
            0.0,
            Angle(35.0, DEGREE),
            0.4,
        )
    )
    var hard = Object3D()
    hard.set_position(-1.8, 1.2, 1.2)
    var hard_node = scene.add(hard^)
    scene.add_light(
        spot_light(
            Color(255, 120, 120),
            hard_node,
            2.0 * FULL,
            4.0,
            Angle(25.0, DEGREE),
            0.0,
            2.0,
            left_node,
        )
    )
    scene.add_light(ambient_light(Color(255, 255, 255), 0.05 * FULL))
    scene.update()

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.8, 3.2), Vector3(0, 0, 0))

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            floor,
            assets.materials.add(Material(Color(200, 200, 200))),
            ground_node,
        )
    )
    meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 140, 40))), left_node
        )
    )
    meshes.append(
        Mesh(
            ball,
            assets.materials.add(Material(Color(90, 190, 255))),
            right_node,
        )
    )

    var corners = prepared(renderer, scene, assets, meshes, camera)
    var lighting = Lighting(scene)
    assert_equal(lighting.hemisphere_count(), 1)
    assert_equal(lighting.spot_count(), 2)
    var target = RenderTarget(48, 36, BACKGROUND)
    for triangle in range(len(corners) // 3):  # pragma: no branch
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            target,
            SHADE_LIT,
            assets.textures,
            lighting,
        )
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 48, 36, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 300, "the scene barely drew anything")
    # The cones really show: the floor is not lit evenly.
    var darkest = UInt8(255)
    var brightest = UInt8(0)
    for x in range(48):
        var shown = cpu.get_pixel(x, 30)
        if shown.r < darkest:
            darkest = shown.r
        if shown.r > brightest:
            brightest = shown.r
    assert_true(Int(brightest) - Int(darkest) > 40, "the cones left no pool")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_flattening_fog_lays_out_six_floats() raises:
    # The two edges, the density, then the color, linear.
    var view = FogView(
        linear_fog(Color(128, 0, 255), Length(2.0, METER), Length(9.0, METER))
    )
    var flat = flatten_fog(view)
    assert_equal(len(flat), 6)
    assert_equal(len(flat), FOG_FLOATS)
    assert_equal(flat[0], Float32(2))
    assert_equal(flat[1], Float32(9))
    assert_equal(flat[2], Float32(0))
    assert_almost_equal(flat[3], Float32(0.215861), atol=Float64(1e-5))
    assert_equal(flat[4], Float32(0))
    assert_equal(flat[5], Float32(1))


def compare_under_fog(fog: Fog, mode: ShadeMode) raises -> Framebuffer:
    """Render a floor, a box and a sphere lit by a sun and some fill on both
    backends under `fog`, assert they agree, and return the CPU image."""
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 12, 8))
    var floor = assets.geometries.add(
        plane(Length(30.0, METER), Length(30.0, METER), 3, 3)
    )
    var scene = Scene()
    var ground = Object3D()
    ground.set_position(0, -0.7, 0)
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var left = Object3D()
    left.set_position(-0.9, 0, 0)
    left.set_euler(Angle(25.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE))
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.9, 0, -3.0)
    var right_node = scene.add(right^)
    var sun = Object3D()
    sun.set_position(0.4, 0.8, 0.5)
    var sun_node = scene.add(sun^)
    scene.add_light(directional_light(Color(255, 255, 255), sun_node, 0.8))
    scene.add_light(ambient_light(Color(255, 255, 255), 0.15))
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            floor,
            assets.materials.add(Material(Color(200, 200, 200))),
            ground_node,
        )
    )
    meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 140, 40))), left_node
        )
    )
    meshes.append(
        Mesh(
            ball,
            assets.materials.add(Material(Color(90, 190, 255), kind=BASIC)),
            right_node,
        )
    )
    scene.fog = fog
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.8, 3.2), Vector3(0, 0, 0))
    var corners = prepared(renderer, scene, assets, meshes, camera)
    var lighting = Lighting(scene)
    var view = FogView(scene.fog)
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_all(corners, target, mode, assets.textures, lighting, 1, view)
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 48, 36, BACKGROUND, mode, assets.textures, lighting, view
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 300, "the scene barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    return cpu^


def test_both_backends_agree_under_linear_and_exponential_fog() raises:
    # A floor running to the horizon, a lit box and an unlit sphere further
    # back, under each kind of fog: the depth is taken from the interpolated
    # world position on both sides, and every material is veiled.
    if skipped_for_lack_of_a_gpu("both backends agree under fog"):
        return
    var fog_color = Color(160, 170, 190)
    var clear = compare_under_fog(no_fog(), SHADE_LIT)
    var linear = compare_under_fog(
        linear_fog(fog_color, Length(2.0, METER), Length(9.0, METER)), SHADE_LIT
    )
    var thick = compare_under_fog(
        exp2_fog(fog_color, InverseLength(0.25, PER_METER)), SHADE_LIT
    )
    # And the fog really changed the frame, differently for each kind.
    assert_true(
        count_mismatches(clear, linear) > 200, "the linear fog did nothing"
    )
    assert_true(
        count_mismatches(clear, thick) > 200, "the exponential fog did nothing"
    )
    assert_true(count_mismatches(linear, thick) > 50, "the two fogs agreed")


def test_both_backends_leave_the_uv_view_unfogged() raises:
    if skipped_for_lack_of_a_gpu("both backends leave the uv view unfogged"):
        return
    var clear = compare_under_fog(no_fog(), SHADE_UV)
    var veiled = compare_under_fog(
        exp2_fog(Color(255, 255, 255), InverseLength(5.0, PER_METER)), SHADE_UV
    )
    assert_equal(count_mismatches(clear, veiled), 0)


def compare_tone_mapped(
    mode: ToneMapping, exposure: Float32
) raises -> Framebuffer:
    """Render an overexposed box and sphere on both backends through
    `mode`, assert they agree, and return the CPU image."""
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 12, 8))
    var scene = Scene()
    var left = Object3D()
    left.set_position(-0.9, 0, 0)
    left.set_euler(Angle(25.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE))
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.9, 0, 0.4)
    var right_node = scene.add(right^)
    var sun = Object3D()
    sun.set_position(0.4, 0.8, 0.5)
    var sun_node = scene.add(sun^)
    scene.add_light(directional_light(Color(255, 240, 220), sun_node, 2.5))
    var bulb = Object3D()
    bulb.set_position(0.5, 1.0, 1.5)
    var bulb_node = scene.add(bulb^)
    scene.add_light(point_light(Color(255, 200, 160), bulb_node, 3.0))
    scene.add_light(ambient_light(Color(255, 255, 255), 0.3))
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 140, 40))), left_node
        )
    )
    meshes.append(
        Mesh(
            ball,
            assets.materials.add(Material(Color(90, 190, 255))),
            right_node,
        )
    )
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.6, 3.0), Vector3(0, 0, 0))
    var corners = prepared(renderer, scene, assets, meshes, camera)
    var lighting = Lighting(scene)
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_all(corners, target, SHADE_LIT, assets.textures, lighting)
    var cpu = target.resolve(1, mode, exposure)
    var gpu = render_triangles(
        corners,
        48,
        36,
        BACKGROUND,
        SHADE_LIT,
        TextureStore(),
        lighting,
        FogView.none(),
        mode,
        exposure,
    )
    var drawn = 0
    for y in range(36):
        for x in range(48):
            if cpu.depth_at(x, y) != inf[DType.float32]():
                drawn += 1
    assert_true(drawn > 200, "the scene barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    return cpu^


def test_both_backends_tone_map_identically() raises:
    # An overexposed scene through every curve: each is applied to the
    # finished pixel on both sides from the same function, and each
    # visibly changes the frame.
    if skipped_for_lack_of_a_gpu("both backends tone map identically"):
        return
    var plain = compare_tone_mapped(NO_TONE_MAPPING, 1.0)
    var blown = 0
    for y in range(36):
        for x in range(48):
            if plain.get_pixel(x, y).r == 255:
                blown += 1
    assert_true(
        blown > 20, "nothing was overexposed, so there is nothing to compress"
    )
    for mode in [
        LINEAR_TONE_MAPPING,
        REINHARD_TONE_MAPPING,
        CINEON_TONE_MAPPING,
        ACES_FILMIC_TONE_MAPPING,
        AGX_TONE_MAPPING,
        NEUTRAL_TONE_MAPPING,
    ]:
        var curved = compare_tone_mapped(mode, 0.7)
        assert_true(
            count_mismatches(plain, curved) > 100, "the curve changed nothing"
        )


def test_the_gpu_refuses_an_unknown_curve_or_a_negative_exposure() raises:
    if skipped_for_lack_of_a_gpu("the gpu refuses an unknown curve"):
        return
    var renderer = GpuRenderer(8, 8)
    with assert_raises():
        renderer.draw(
            overlapping_pair(),
            BACKGROUND,
            SHADE_LIT,
            Lighting.uniform(),
            FogView.none(),
            ToneMapping(9),
        )
    with assert_raises():
        renderer.draw(
            overlapping_pair(),
            BACKGROUND,
            SHADE_LIT,
            Lighting.uniform(),
            FogView.none(),
            REINHARD_TONE_MAPPING,
            -1.0,
        )


def test_the_gpu_never_tone_maps_the_uv_view() raises:
    if skipped_for_lack_of_a_gpu("the gpu never tone maps the uv view"):
        return
    var plain = render_triangles(mapped_quad(16), 16, 16, BACKGROUND, SHADE_UV)
    var curved = render_triangles(
        mapped_quad(16),
        16,
        16,
        BACKGROUND,
        SHADE_UV,
        TextureStore(),
        Lighting.uniform(),
        FogView.none(),
        REINHARD_TONE_MAPPING,
        0.5,
    )
    assert_equal(count_mismatches(plain, curved), 0)


def test_the_gpu_never_tone_maps_the_uv_views_background() raises:
    # The host turns the curve off for the whole uv frame, background and
    # lines included; the device once tone mapped every pixel no uv
    # triangle had written, so an empty uv frame came back darker than the
    # clear color.
    if skipped_for_lack_of_a_gpu("the gpu never tone maps the uv background"):
        return
    var gpu = render_triangles(
        List[RasterVertex](),
        8,
        8,
        BACKGROUND,
        SHADE_UV,
        TextureStore(),
        Lighting.uniform(),
        FogView.none(),
        REINHARD_TONE_MAPPING,
        1.0,
    )
    var cpu = RenderTarget(8, 8, BACKGROUND).resolve(1, NO_TONE_MAPPING, 1.0)
    assert_equal(gpu.get_pixel(3, 3).r, BACKGROUND.r)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_both_backends_resolve_an_untouched_transparent_clear_alike() raises:
    # The host holds its clear color premultiplied and unpremultiplies it
    # on the way out, so a clear with no coverage resolves to transparent
    # black whatever its color. The device wrote the clear color's own
    # bytes where nothing was drawn, which kept the blue.
    if skipped_for_lack_of_a_gpu("both backends resolve a transparent clear"):
        return
    var clear = Color(0, 0, 255, 0)
    var gpu = render_triangles(List[RasterVertex](), 4, 4, clear)
    var cpu = RenderTarget(4, 4, clear).resolve()
    assert_equal(cpu.get_pixel(1, 1).b, UInt8(0))
    assert_equal(gpu.get_pixel(1, 1).b, UInt8(0))
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_both_backends_let_blended_lines_cross() raises:
    # A blended segment tests the depth without claiming it. The host once
    # claimed it, so of two blended segments crossing, the second was
    # dropped at the crossing on the host and kept on the device.
    if skipped_for_lack_of_a_gpu("both backends let blended lines cross"):
        return
    var lines = a_line(2.0, 8.5, 14.0, 8.5, 0.2, Color(255, 0, 0, 128), BLEND)
    for here in a_line(8.5, 2.0, 8.5, 14.0, 0.6, Color(0, 0, 255, 128), BLEND):
        lines.append(here)
    var target = RenderTarget(16, 16, BACKGROUND)
    rasterize_lines_all(lines, target, 1, FogView.none())
    var cpu = target.resolve(1, NO_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        List[RasterVertex](),
        16,
        16,
        BACKGROUND,
        SHADE_LIT,
        TextureStore(),
        Lighting.uniform(),
        FogView.none(),
        NO_TONE_MAPPING,
        1.0,
        lines,
    )
    # Both colors reach the crossing, and neither side claimed its depth.
    assert_true(cpu.get_pixel(8, 8).b > 60, "the second segment was dropped")
    assert_equal(cpu.depth_at(8, 8), inf[DType.float32]())
    assert_equal(gpu.depth_at(8, 8), inf[DType.float32]())
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_refuse_a_blended_line_beside_data_under_a_curve() raises:
    # A blended segment over a data pixel decides that pixel's curve as a
    # blended triangle does, so it is refused the same way, on both sides.
    if skipped_for_lack_of_a_gpu("both backends refuse a blended line by data"):
        return
    var stroke = a_line(1.0, 8.5, 20.0, 8.5, 0.05, Color(0, 0, 0, 2), BLEND)
    var renderer = GpuRenderer(24, 18)
    with assert_raises():
        renderer.draw(
            data_pair(NORMALS),
            BACKGROUND,
            SHADE_TEXTURE,
            Lighting.uniform(),
            FogView(no_fog()),
            REINHARD_TONE_MAPPING,
            1.0,
            stroke,
        )
    with assert_raises():
        check_output_kinds(data_pair(NORMALS), True, stroke)
    # With no curve the same frame draws on the device.
    renderer.draw(
        data_pair(NORMALS),
        BACKGROUND,
        SHADE_TEXTURE,
        Lighting.uniform(),
        FogView(no_fog()),
        NO_TONE_MAPPING,
        1.0,
        stroke,
    )


def test_both_backends_draw_a_frame_in_its_one_order() raises:
    # An opaque line behind a translucent pane: drawn after every triangle
    # it landed on top, on both sides. The frame's draw order puts it
    # first, and both walk that order.
    if skipped_for_lack_of_a_gpu("both backends draw a frame in order"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var stroke = BufferGeometry()
    stroke.set_attribute(
        String(POSITION),
        BufferAttribute([-1.5, 0.0, 0.0, 1.5, 0.0, 0.0], 3),
    )
    var line_geometry = assets.geometries.add(stroke^)
    var glass = assets.materials.add(
        Material(
            Color(255, 0, 0),
            opacity=0.5,
            kind=BASIC,
            side=DOUBLE_SIDE,
            transparent=True,
        )
    )
    var blue = assets.materials.add(Material(Color(0, 0, 255), kind=BASIC))
    var scene = Scene()
    var near = Object3D()
    near.set_position(0, 0, 0.5)
    var near_node = scene.add(near^)
    var away = Object3D()
    away.set_position(0, 0, -0.5)
    var away_node = scene.add(away^)
    scene.update()
    scene.add_mesh(Mesh(sheet, glass, near_node))
    scene.add_line(Line(line_geometry, blue, away_node))
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.5, METER),
        Length(12.0, METER),
    )
    camera.place(Vector3(0, 0, 4.0), Vector3(0, 0, 0))
    var cpu = renderer.render(scene, assets, camera)
    var frame = renderer.prepare_frame(scene, assets, camera)
    assert_true(frame.draws[0].kind == DRAW_SEGMENTS)
    var device = GpuRenderer(48, 36)
    device.set_textures(assets.textures)
    device.draw(
        frame.corners,
        BACKGROUND,
        SHADE_TEXTURE,
        Lighting(scene),
        FogView(scene.fog),
        NO_TONE_MAPPING,
        1.0,
        frame.segments,
        frame.draws,
    )
    var gpu = device.read_back()
    var center = cpu.get_pixel(24, 18)
    assert_true(center.r > 100 and center.b > 100, "the pane did not blend")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # Without an order the device draws every triangle and then every
    # segment, which is what the two-pass host functions draw.
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_all(frame.corners, target, SHADE_TEXTURE, assets.textures)
    rasterize_lines_all(frame.segments, target)
    var two_passes = target.resolve()
    device.draw(
        frame.corners,
        BACKGROUND,
        SHADE_TEXTURE,
        Lighting(scene),
        FogView(scene.fog),
        NO_TONE_MAPPING,
        1.0,
        frame.segments,
    )
    assert_equal(
        count_mismatches(two_passes, device.read_back(), tolerance=1), 0
    )
    assert_true(two_passes.get_pixel(24, 18).r < 100, "the pane stayed on top")
    # And a draw the frame cannot hold is refused before the launch.
    with assert_raises():
        device.draw(
            frame.corners,
            BACKGROUND,
            SHADE_TEXTURE,
            Lighting(scene),
            FogView(scene.fog),
            NO_TONE_MAPPING,
            1.0,
            frame.segments,
            [Draw(DRAW_SEGMENTS, 0, 99)],
        )


def test_both_backends_agree_on_the_whole_pipeline_at_once() raises:
    # Every light kind, a mipmapped floor, a lit box, an unlit sphere and a
    # translucent pane, through a linear fog and the ACES curve: the whole
    # pipeline under the chosen conventions, in color and alpha to one
    # level and in depth to rounding.
    if skipped_for_lack_of_a_gpu("both backends agree on the whole pipeline"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)

    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ball = assets.geometries.add(sphere(Length(0.6, METER), 12, 8))
    var floor = assets.geometries.add(
        plane(Length(20.0, METER), Length(20.0, METER), 4, 4)
    )
    var pane = assets.geometries.add(
        plane(Length(1.6, METER), Length(1.2, METER), 1, 1)
    )
    var board = assets.textures.add(
        checkerboard(
            64,
            8,
            Color(240, 240, 240),
            Color(40, 60, 120),
            REPEAT,
            BILINEAR,
            mipmapped=True,
        )
    )
    var tiled = assets.materials.add(
        Material(Color(255, 255, 255), board, DOUBLE_SIDE)
    )
    var orange = assets.materials.add(Material(Color(255, 140, 40)))
    var plain = assets.materials.add(Material(Color(90, 190, 255), kind=BASIC))
    var glass = assets.materials.add(
        Material(
            Color(120, 255, 160),
            NO_TEXTURE,
            DOUBLE_SIDE,
            0.45,
            transparent=True,
        )
    )

    var scene = Scene()
    var ground = Object3D()
    ground.set_position(0, -0.6, 0)
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var left = Object3D()
    left.set_position(-0.9, 0, 0)
    left.set_euler(Angle(25.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE))
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.9, 0, -0.4)
    var right_node = scene.add(right^)
    var sheet = Object3D()
    sheet.set_position(0.1, 0.2, 1.2)
    sheet.set_euler(Angle(0.0, DEGREE), Angle(15.0, DEGREE), Angle(0.0, DEGREE))
    var sheet_node = scene.add(sheet^)
    var sun = Object3D()
    sun.set_position(0.4, 0.8, 0.5)
    var sun_node = scene.add(sun^)
    scene.add_light(directional_light(Color(255, 255, 255), sun_node, 0.5))
    var bulb = Object3D()
    bulb.set_position(0.5, 1.0, 1.5)
    var bulb_node = scene.add(bulb^)
    scene.add_light(point_light(Color(255, 220, 180), bulb_node, 0.8))
    var sky = Object3D()
    sky.set_position(0.0, 3.0, 0.2)
    var sky_node = scene.add(sky^)
    scene.add_light(
        hemisphere_light(
            Color(120, 160, 255), Color(120, 80, 40), sky_node, 0.4
        )
    )
    var beam = Object3D()
    beam.set_position(-0.5, 2.5, 1.5)
    var beam_node = scene.add(beam^)
    scene.add_light(
        spot_light(
            Color(255, 240, 200), beam_node, 2.0, 0.0, Angle(35.0, DEGREE), 0.4
        )
    )
    scene.add_light(ambient_light(Color(255, 255, 255), 0.1))
    scene.fog = linear_fog(
        Color(160, 170, 190), Length(2.0, METER), Length(9.0, METER)
    )
    scene.update()

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.8, 3.4), Vector3(0, 0, 0))

    var meshes = List[Mesh]()
    meshes.append(Mesh(floor, tiled, ground_node))
    meshes.append(Mesh(box, orange, left_node))
    meshes.append(Mesh(ball, plain, right_node))
    meshes.append(Mesh(pane, glass, sheet_node))
    var corners = prepared(renderer, scene, assets, meshes, camera)
    var lighting = Lighting(scene)
    assert_equal(lighting.hemisphere_count(), 1)
    assert_equal(lighting.spot_count(), 1)
    var view = FogView(scene.fog)
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_all(
        corners, target, SHADE_TEXTURE, assets.textures, lighting, 1, view
    )
    var cpu = target.resolve(1, ACES_FILMIC_TONE_MAPPING, 0.9)
    var gpu = render_triangles(
        corners,
        48,
        36,
        BACKGROUND,
        SHADE_TEXTURE,
        assets.textures,
        lighting,
        view,
        ACES_FILMIC_TONE_MAPPING,
        0.9,
    )
    var drawn = 0
    for y in range(36):
        for x in range(48):
            if cpu.depth_at(x, y) != inf[DType.float32]():
                drawn += 1
    assert_true(drawn > 300, "the scene barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    for y in range(36):
        for x in range(48):
            var theirs = cpu.depth_at(x, y)
            var ours = gpu.depth_at(x, y)
            if theirs == inf[DType.float32]():
                assert_equal(ours, theirs)
            else:
                assert_almost_equal(ours, theirs, atol=Float64(1e-5))


def test_the_gpu_leaves_an_unlit_triangle_its_own_color() raises:
    # A BASIC material's triangles carry `kind=BASIC`, and the kernel must
    # skip the lights for them exactly as the host does.
    if skipped_for_lack_of_a_gpu("the gpu leaves an unlit triangle alone"):
        return
    var corners = List[RasterVertex]()
    for index in range(len(overlapping_pair())):
        var base = overlapping_pair()[index]
        corners.append(
            RasterVertex(
                base.x,
                base.y,
                base.z,
                base.inv_w,
                base.color,
                base.u,
                base.v,
                base.texture,
                base.blend,
                base.normal,
                base.world,
                BASIC,
            )
        )
    # Lighting that would halve everything if it were applied.
    var half = Lighting(ambient=FloatColor(0.5, 0.5, 0.5, 1.0))
    var target = RenderTarget(24, 18, BACKGROUND)
    for index in range(len(corners) // 3):  # pragma: no branch
        rasterize_shaded(
            corners[index * 3],
            corners[index * 3 + 1],
            corners[index * 3 + 2],
            target,
            SHADE_LIT,
            TextureStore(),
            half,
        )
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 24, 18, BACKGROUND, SHADE_LIT, TextureStore(), half
    )
    assert_equal(count_mismatches(cpu, gpu), 0)
    # And the lit version really is different, or this proves nothing.
    var lit = render_triangles(
        overlapping_pair(), 24, 18, BACKGROUND, SHADE_LIT, TextureStore(), half
    )
    assert_true(count_mismatches(gpu, lit) > 0, "the lights changed nothing")


def glowing_pair() -> List[RasterVertex]:
    """Return `overlapping_pair` with every corner giving off a little light."""
    var corners = List[RasterVertex]()
    for base in overlapping_pair():
        corners.append(glowing(base, FloatColor(0.2, 0.1, 0.05)))
    return corners^


def test_both_backends_add_the_emissive_the_same_way() raises:
    # The glow is added after the lights on both sides, in the same order
    # of operations, so the two agree to the usual one ULP.
    if skipped_for_lack_of_a_gpu("both backends add the emissive"):
        return
    var half = Lighting(ambient=FloatColor(0.5, 0.5, 0.5, 1.0))
    var corners = glowing_pair()
    var target = RenderTarget(24, 18, BACKGROUND)
    for index in range(len(corners) // 3):  # pragma: no branch
        rasterize_shaded(
            corners[index * 3],
            corners[index * 3 + 1],
            corners[index * 3 + 2],
            target,
            SHADE_LIT,
            TextureStore(),
            half,
        )
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 24, 18, BACKGROUND, SHADE_LIT, TextureStore(), half
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # And the glow really shows, or this proves nothing.
    var plain = render_triangles(
        overlapping_pair(), 24, 18, BACKGROUND, SHADE_LIT, TextureStore(), half
    )
    assert_true(count_mismatches(gpu, plain) > 0, "the glow changed nothing")


def dark() -> Lighting:
    """Return lighting under which only an emissive term shows."""
    return Lighting(ambient=FloatColor(0.0, 0.0, 0.0, 1.0))


def test_both_backends_sample_an_emissive_map_identically() raises:
    # With no light at all the glow is the whole image, so this is the
    # texture parity test again, through the emissive path.
    if skipped_for_lack_of_a_gpu("both backends sample an emissive map"):
        return
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(
            16, 4, Color(240, 60, 20), Color(20, 40, 200), alpha=IGNORED
        )
    )
    var corners = List[RasterVertex]()
    for base in mapped_quad(24):
        corners.append(glowing(base, FloatColor(1, 1, 1), board))
    var cpu = cpu_textured_lit(corners, 24, textures, dark())
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures, dark()
    )
    var light = 0
    var deep = 0
    for y in range(24):
        for x in range(24):
            if cpu.get_pixel(x, y).r > 200:
                light += 1
            if cpu.get_pixel(x, y).b > 150:
                deep += 1
    assert_true(light > 0 and deep > 0, "the emissive board did not appear")
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_both_backends_agree_on_a_mipmapped_emissive_map() raises:
    # The receding surface again, with the board as the emissive map: the
    # level choice runs through the shared sampler on both sides.
    if skipped_for_lack_of_a_gpu("both backends agree on a mipmapped glow"):
        return
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(
            32,
            8,
            Color(255, 255, 255),
            Color(0, 0, 0),
            REPEAT,
            BILINEAR,
            mipmapped=True,
            alpha=IGNORED,
        )
    )
    var flat = List[RasterVertex]()
    flat.append(lit_corner(2, 22, 1.0, 0, 0))
    flat.append(lit_corner(16, 4, 0.1, 0.3, 3))
    flat.append(lit_corner(22, 22, 1.0, 3, 0))
    flat.append(lit_corner(2, 22, 1.0, 0, 0))
    flat.append(lit_corner(8, 4, 0.1, 0.0, 3))
    flat.append(lit_corner(16, 4, 0.1, 0.3, 3))
    var corners = List[RasterVertex]()
    for base in flat:
        corners.append(glowing(base, FloatColor(1, 1, 1), board))
    var cpu = cpu_textured_lit(corners, 24, textures, dark())
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures, dark()
    )
    var drawn = 0
    for y in range(24):
        for x in range(24):
            var shown = cpu.get_pixel(x, y)
            if shown.r != BACKGROUND.r or shown.b != BACKGROUND.b:
                drawn += 1
    assert_true(drawn > 100, "the surface did not appear")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_refuse_an_emissive_map_that_is_not_there() raises:
    if skipped_for_lack_of_a_gpu("both backends refuse a missing glow map"):
        return
    var corners = List[RasterVertex]()
    for base in mapped_quad(24):
        corners.append(glowing(base, FloatColor(1, 1, 1), TextureId(3)))
    var renderer = GpuRenderer(24, 24)
    with assert_raises():
        renderer.draw(corners, BACKGROUND, SHADE_TEXTURE)
    with assert_raises():
        _ = cpu_textured(corners, 24, TextureStore())
    # And corners that disagree about it are refused before any sampling.
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(
            8, 2, Color(240, 60, 20), Color(20, 40, 200), alpha=IGNORED
        )
    )
    var mixed = List[RasterVertex]()
    for base in mapped_quad(24):
        mixed.append(glowing(base, FloatColor(1, 1, 1), board))
    mixed[1] = glowing(mixed[1], FloatColor(1, 1, 1), NO_TEXTURE)
    renderer.set_textures(textures)
    with assert_raises():
        renderer.draw(mixed, BACKGROUND, SHADE_TEXTURE)
    with assert_raises():
        _ = cpu_textured(mixed, 24, textures)


def test_the_table_carries_the_alpha_mode() raises:
    # Host side: eight columns per texture, the last the alpha mode, and the
    # blank texture crosses as coverage like any opaque image.
    var textures = TextureStore()
    _ = textures.add(checkerboard(2, 2, Color(255, 255, 255), Color(0, 0, 0)))
    _ = textures.add(
        checkerboard(2, 2, Color(255, 255, 255), Color(0, 0, 0), alpha=IGNORED)
    )
    _ = textures.add(Texture())
    var flattened = flatten_textures(textures)
    ref table = flattened[1]
    assert_equal(len(table), 3 * TABLE_COLUMNS)
    assert_equal(table[7], Int32(COVERAGE.value))
    assert_equal(table[TABLE_COLUMNS + 7], Int32(IGNORED.value))
    assert_equal(table[2 * TABLE_COLUMNS + 7], Int32(COVERAGE.value))


def test_both_backends_ignore_an_emissive_maps_alpha_alike() raises:
    # Opaque red beside transparent green as the emissive map, bilinear and
    # ignoring alpha: both backends filter the color straight, so the middle
    # of the quad is yellow rather than the red that coverage filtering
    # gives.
    if skipped_for_lack_of_a_gpu("both backends ignore a glow map's alpha"):
        return
    var textures = TextureStore()
    var pixels = List[UInt8]()
    for value in [UInt8(255), UInt8(0), UInt8(0), UInt8(255)]:
        pixels.append(value)
    for value in [UInt8(0), UInt8(255), UInt8(0), UInt8(0)]:
        pixels.append(value)
    var strip = textures.add(
        Texture(2, 1, pixels^, CLAMP, BILINEAR, LINEAR, False, IGNORED)
    )
    var corners = List[RasterVertex]()
    for base in mapped_quad(24):
        corners.append(glowing(base, FloatColor(1, 1, 1), strip))
    var cpu = cpu_textured_lit(corners, 24, textures, dark())
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures, dark()
    )
    var middle = cpu.get_pixel(12, 12)
    assert_true(middle.r > 100 and middle.g > 100, "the hidden green was lost")
    assert_equal(middle.b, UInt8(0))
    assert_equal(middle.a, UInt8(255))
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_base_and_emissive_maps_of_different_sizes_agree() raises:
    # Each map picks its mip level from its own size, on a receding surface
    # under real lights, and the two backends still agree.
    if skipped_for_lack_of_a_gpu("maps of different sizes on one surface"):
        return
    var textures = TextureStore()
    var base = textures.add(
        checkerboard(
            16,
            4,
            Color(240, 60, 20),
            Color(20, 40, 200),
            REPEAT,
            BILINEAR,
            mipmapped=True,
        )
    )
    var glow = textures.add(
        checkerboard(
            32,
            8,
            Color(255, 255, 255),
            Color(0, 0, 0),
            REPEAT,
            BILINEAR,
            mipmapped=True,
            alpha=IGNORED,
        )
    )
    var flat = List[RasterVertex]()
    flat.append(lit_corner(2, 22, 1.0, 0, 0, base))
    flat.append(lit_corner(16, 4, 0.1, 0.3, 3, base))
    flat.append(lit_corner(22, 22, 1.0, 3, 0, base))
    flat.append(lit_corner(2, 22, 1.0, 0, 0, base))
    flat.append(lit_corner(8, 4, 0.1, 0.0, 3, base))
    flat.append(lit_corner(16, 4, 0.1, 0.3, 3, base))
    var corners = List[RasterVertex]()
    for corner in flat:
        corners.append(glowing(corner, FloatColor(0.4, 0.4, 0.4), glow))
    var lighting = gpu_lit_along_z()
    var cpu = cpu_textured_lit(corners, 24, textures, lighting)
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures, lighting
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # Color, alpha and depth: the maps change what a fragment is colored,
    # never where it lands.
    for y in range(24):
        for x in range(24):
            var near = cpu.depth_at(x, y)
            if near < Float32(1e30):
                assert_almost_equal(
                    near, gpu.depth_at(x, y), atol=Float64(1e-5)
                )


def test_both_backends_refuse_an_emissive_map_that_reads_alpha_as_coverage() raises:
    if skipped_for_lack_of_a_gpu("both backends refuse a coverage glow map"):
        return
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(8, 2, Color(240, 60, 20), Color(20, 40, 200))
    )
    var corners = List[RasterVertex]()
    for base in mapped_quad(24):
        corners.append(glowing(base, FloatColor(1, 1, 1), board))
    var renderer = GpuRenderer(24, 24)
    renderer.set_textures(textures)
    with assert_raises():
        renderer.draw(corners, BACKGROUND, SHADE_TEXTURE)
    with assert_raises():
        _ = cpu_textured(corners, 24, textures)
    # SHADE_LIT never opens the map, so neither refuses it there.
    renderer.draw(corners, BACKGROUND, SHADE_LIT)
    _ = cpu_render_triangles(corners, 24, 24)


def count_background(image: Framebuffer, background: Color) raises -> Int:
    """Return how many pixels still hold the clear color.

    Args:
        image: The rendered image.
        background: The color it was cleared to.

    Returns:
        The number of untouched pixels.

    Raises:
        Error: If a coordinate is out of bounds.
    """
    var untouched = 0
    for y in range(image.height):
        for x in range(image.width):
            var pixel = image.get_pixel(x, y)
            if (
                pixel.r == background.r
                and pixel.g == background.g
                and pixel.b == background.b
            ):
                untouched += 1
    return untouched


# --- the readback contract --------------------------------------------------


def test_the_gpu_reads_back_depth_and_not_just_color() raises:
    # `read_back` returns a Framebuffer, and a Framebuffer promises depth. It
    # used to hand back one whose depth was infinity everywhere, so drawing a
    # further depth-tested triangle into it would paint straight over a nearer
    # surface the GPU had already drawn.
    if skipped_for_lack_of_a_gpu("gpu reads back depth"):
        return
    var corners = overlapping_pair()
    var gpu = render_triangles(corners, 36, 30, BACKGROUND)
    var cpu = cpu_render_triangles(corners, 36, 30)

    var covered = 0
    for y in range(30):
        for x in range(36):
            var theirs = cpu.depth_at(x, y)
            var ours = gpu.depth_at(x, y)
            if theirs == inf[DType.float32]():
                # Nothing drawn here: the GPU must agree there is nothing.
                assert_equal(ours, inf[DType.float32]())
            else:
                covered += 1
                # Interpolated in floating point, so the same one-ULP caveat
                # applies as to color; see `count_mismatches`.
                assert_almost_equal(ours, theirs, atol=Float64(1e-5))
    assert_true(covered > 0, "nothing was drawn, so nothing was compared")


def test_depth_is_infinite_where_nothing_was_drawn() raises:
    if skipped_for_lack_of_a_gpu("depth is infinite where nothing was drawn"):
        return
    var image = render_triangles(List[RasterVertex](), 16, 12, BACKGROUND)
    for y in range(12):
        for x in range(16):
            assert_equal(image.depth_at(x, y), inf[DType.float32]())


def test_reading_back_before_drawing_is_rejected() raises:
    # The device target is allocated but not cleared, so this would otherwise
    # hand back whatever the allocation happened to contain.
    if skipped_for_lack_of_a_gpu("reading back before drawing is rejected"):
        return
    var renderer = GpuRenderer(8, 8)
    with assert_raises():
        _ = renderer.read_back()
    renderer.draw(List[RasterVertex](), BACKGROUND)
    # Drawing nothing still counts as drawing; the target is now defined.
    var image = renderer.read_back()
    assert_equal(image.get_pixel(0, 0).r, BACKGROUND.r)


# --- texture coordinates ----------------------------------------------------


def test_both_backends_agree_on_texture_coordinates() raises:
    # uv is unpacked from the flat buffer at ten-float strides on the device
    # and packed at the same strides on the host. Nothing but this would
    # notice the two drifting apart.
    if skipped_for_lack_of_a_gpu("both backends agree on texture coordinates"):
        return
    var corners = List[RasterVertex]()
    corners.append(
        RasterVertex(-4, -4, 0.5, 1.0, FloatColor(0, 0, 0), 0.0, 0.0)
    )
    corners.append(
        RasterVertex(40, -4, 0.5, 0.25, FloatColor(0, 0, 0), 1.0, 0.0)
    )
    corners.append(
        RasterVertex(-4, 40, 0.5, 0.6, FloatColor(0, 0, 0), 0.0, 1.0)
    )
    var gpu = render_triangles(corners, 32, 24, BACKGROUND, SHADE_UV)

    var drawn = RenderTarget(32, 24, BACKGROUND)
    rasterize_shaded(corners[0], corners[1], corners[2], drawn, SHADE_UV)
    var cpu = drawn.resolve()

    # A real gradient in both channels, not a flat fill.
    assert_true(cpu.get_pixel(0, 0).r != cpu.get_pixel(31, 0).r)
    assert_true(cpu.get_pixel(0, 0).g != cpu.get_pixel(0, 23).g)
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_the_gpu_ignores_texture_coordinates_when_shading_lit() raises:
    if skipped_for_lack_of_a_gpu("gpu ignores uv when shading lit"):
        return
    var corners = List[RasterVertex]()
    corners.append(
        RasterVertex(-4, -4, 0.5, 1.0, FloatColor(srgb=FOREGROUND), 1.0, 1.0)
    )
    corners.append(
        RasterVertex(40, -4, 0.5, 1.0, FloatColor(srgb=FOREGROUND), 1.0, 1.0)
    )
    corners.append(
        RasterVertex(-4, 40, 0.5, 1.0, FloatColor(srgb=FOREGROUND), 1.0, 1.0)
    )
    var image = render_triangles(corners, 16, 12, BACKGROUND)
    assert_equal(image.get_pixel(2, 2).r, FOREGROUND.r)
    assert_equal(image.get_pixel(2, 2).g, FOREGROUND.g)
    assert_equal(image.get_pixel(2, 2).b, FOREGROUND.b)


def test_both_backends_agree_on_a_prepared_orthographic_uv_scene() raises:
    # The widest path this project has: an orthographic camera, a scene graph,
    # clipping, texture coordinates, the ten-float GPU layout, interpolation
    # and depth readback, all at once. The other GPU uv test starts from
    # hand-built RasterVertex values and so covers only the last stage.
    if skipped_for_lack_of_a_gpu("both backends agree on an ortho uv scene"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    renderer.set_shading(SHADE_UV)

    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.4, METER)))
    var ball = assets.geometries.add(sphere(Length(0.8, METER), 10, 6))

    var scene = Scene()
    var left = Object3D()
    left.set_position(-0.9, 0, 0)
    left.set_euler(Angle(20.0, DEGREE), Angle(30.0, DEGREE), Angle(0.0, DEGREE))
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.9, 0.2, -0.5)
    var right_node = scene.add(right^)
    light_the(scene)
    scene.update()

    var camera = centered(
        Length(4.0, METER),
        Float32(48) / Float32(36),
        Length(0.0, METER),
        Length(50.0, METER),
    )
    camera.place(Vector3(0, 0.5, 4), Vector3(0, 0, 0))

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            box, assets.materials.add(Material(Color(255, 255, 255))), left_node
        )
    )
    meshes.append(
        Mesh(
            ball,
            assets.materials.add(Material(Color(255, 255, 255))),
            right_node,
        )
    )

    var corners = prepared(renderer, scene, assets, meshes, camera)
    assert_true(len(corners) > 0, "the scene prepared no triangles")

    var cpu = rendered(renderer, scene, assets, meshes, camera)
    var gpu = render_triangles(corners, 48, 36, BACKGROUND, SHADE_UV)

    # An orthographic camera leaves every inv_w at one, so the interpolation
    # is exactly affine and the two must agree to the last bit.
    assert_equal(count_mismatches(cpu, gpu), 0)

    # And it is a real image with real texture coordinates in it.
    var reds = 0
    var greens = 0
    for y in range(36):
        for x in range(48):
            var pixel = cpu.get_pixel(x, y)
            if pixel.r > 0 and pixel.b == 0:
                reds += 1
            if pixel.g > 0 and pixel.b == 0:
                greens += 1
    assert_true(reds > 0, "no u reached the image")
    assert_true(greens > 0, "no v reached the image")


# --- textures ---------------------------------------------------------------


def lit_corner(
    x: Float32,
    y: Float32,
    inv_w: Float32,
    u: Float32,
    v: Float32,
    texture: TextureId = NO_TEXTURE,
) -> RasterVertex:
    """Return a white raster vertex carrying texture coordinates."""
    return RasterVertex(x, y, 0.5, inv_w, FloatColor(1, 1, 1), u, v, texture)


def mapped_quad(
    size: Float32, texture: TextureId = NO_TEXTURE
) -> List[RasterVertex]:
    """Return two triangles covering a square image, mapped once across it."""
    var corners = List[RasterVertex]()
    corners.append(lit_corner(0, 0, 1, 0, 1, texture))
    corners.append(lit_corner(size, 0, 1, 1, 1, texture))
    corners.append(lit_corner(size, size, 1, 1, 0, texture))
    corners.append(lit_corner(0, 0, 1, 0, 1, texture))
    corners.append(lit_corner(size, size, 1, 1, 0, texture))
    corners.append(lit_corner(0, size, 1, 0, 0, texture))
    return corners^


def cpu_textured(
    corners: List[RasterVertex],
    size: Int,
    textures: TextureStore,
    clear: Color = BACKGROUND,
) raises -> Framebuffer:
    """Return the CPU rasterizer's textured output.

    Args:
        corners: Raster vertices, three per triangle.
        size: Image width and height.
        textures: The images to sample.
        clear: The color to start from, alpha included.

    Returns:
        The rendered framebuffer.

    Raises:
        Error: If the dimensions are invalid.
    """
    var target = RenderTarget(size, size, clear)
    for triangle in range(len(corners) // 3):
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            target,
            SHADE_TEXTURE,
            textures,
        )
    return target.resolve()


def test_both_backends_sample_a_texture_identically() raises:
    # Nearest-neighbor sampling is integer arithmetic once the coordinate is
    # floored, so unlike interpolated shading this has to agree exactly.
    if skipped_for_lack_of_a_gpu("both backends sample a texture"):
        return
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(16, 4, Color(240, 60, 20), Color(20, 40, 200))
    )
    var corners = mapped_quad(24, board)
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures
    )
    var cpu = cpu_textured(corners, 24, textures)

    # A real pattern: both colors present, so the mapping did something.
    var light = 0
    var dark = 0
    for y in range(24):
        for x in range(24):
            if cpu.get_pixel(x, y).r > 200:
                light += 1
            if cpu.get_pixel(x, y).b > 150:
                dark += 1
    assert_true(light > 0 and dark > 0, "the checkerboard did not appear")
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_both_backends_choose_and_blend_mip_levels_identically() raises:
    # A 64-texel board tiled four times across 24 pixels: about ten texels to
    # a pixel, which is three or four levels down. The chain is the only
    # reason this is not a field of noise, and the level is chosen from an
    # analytic derivative that both backends have to compute the same way --
    # one level out on either would be plainly visible here.
    if skipped_for_lack_of_a_gpu("both backends agree on mip levels"):
        return
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(
            64,
            8,
            Color(240, 60, 20),
            Color(20, 40, 200),
            REPEAT,
            BILINEAR,
            mipmapped=True,
        )
    )
    var corners = List[RasterVertex]()
    corners.append(lit_corner(0, 0, 1, 0, 4, board))
    corners.append(lit_corner(24, 0, 1, 4, 4, board))
    corners.append(lit_corner(24, 24, 1, 4, 0, board))
    corners.append(lit_corner(0, 0, 1, 0, 4, board))
    corners.append(lit_corner(24, 24, 1, 4, 0, board))
    corners.append(lit_corner(0, 24, 1, 0, 0, board))

    var cpu = cpu_textured(corners, 24, textures)
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures
    )

    # The surface really is minified: level zero would be sampling one texel
    # in ten and the two colors would still be at full strength.
    var extreme = 0
    for y in range(24):
        for x in range(24):
            var shown = cpu.get_pixel(x, y)
            if shown.r > 220 or shown.b > 180:
                extreme += 1
    assert_equal(extreme, 0)
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_agree_when_a_mipmapped_surface_recedes() raises:
    # Perspective: `inv_w` differs across the quad, so the footprint grows
    # towards the far edge and the level changes from pixel to pixel. That
    # exercises the part neither a flat quad nor a uniform level can -- the
    # neighboring coordinates are perspective-corrected before the
    # derivative is taken.
    if skipped_for_lack_of_a_gpu("both backends agree on a receding surface"):
        return
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(
            32,
            8,
            Color(255, 255, 255),
            Color(0, 0, 0),
            REPEAT,
            BILINEAR,
            mipmapped=True,
        )
    )
    var corners = List[RasterVertex]()
    # Far edge at a tenth the near edge's inv_w: ten times the compression.
    corners.append(lit_corner(2, 22, 1.0, 0, 0, board))
    corners.append(lit_corner(16, 4, 0.1, 0.3, 3, board))
    corners.append(lit_corner(22, 22, 1.0, 3, 0, board))
    corners.append(lit_corner(2, 22, 1.0, 0, 0, board))
    corners.append(lit_corner(8, 4, 0.1, 0.0, 3, board))
    corners.append(lit_corner(16, 4, 0.1, 0.3, 3, board))

    var cpu = cpu_textured(corners, 24, textures)
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures
    )
    # Anything that is not the clear color: a textured surface holds no one
    # foreground color, so `count_foreground` has nothing to count.
    var drawn = 0
    for y in range(24):
        for x in range(24):
            var shown = cpu.get_pixel(x, y)
            if shown.r != BACKGROUND.r or shown.b != BACKGROUND.b:
                drawn += 1
    assert_true(drawn > 100, "the surface did not appear")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_a_mipmapped_and_a_plain_texture_can_be_drawn_together() raises:
    # The level count is per texture and travels in the table, so one image
    # with a chain and one without must not be read with each other's.
    if skipped_for_lack_of_a_gpu("a mipmapped and a plain texture together"):
        return
    var textures = TextureStore()
    var plain = textures.add(
        checkerboard(16, 4, Color(240, 60, 20), Color(20, 40, 200))
    )
    var chained = textures.add(
        checkerboard(
            16,
            4,
            Color(20, 240, 60),
            Color(200, 20, 40),
            REPEAT,
            BILINEAR,
            mipmapped=True,
        )
    )
    var corners = List[RasterVertex]()
    corners.append(lit_corner(0, 0, 1, 0, 1, plain))
    corners.append(lit_corner(24, 0, 1, 2, 1, plain))
    corners.append(lit_corner(24, 12, 1, 2, 0, plain))
    corners.append(lit_corner(0, 12, 1, 0, 1, chained))
    corners.append(lit_corner(24, 12, 1, 2, 1, chained))
    corners.append(lit_corner(24, 24, 1, 2, 0, chained))

    var cpu = cpu_textured(corners, 24, textures)
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_reject_corners_that_disagree() raises:
    if skipped_for_lack_of_a_gpu("both backends reject disagreeing corners"):
        return
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(8, 2, Color(240, 60, 20), Color(20, 40, 200))
    )
    var corners = mapped_quad(24, board)
    # One corner of the first triangle names no texture at all.
    corners[1] = RasterVertex(
        corners[1].x,
        corners[1].y,
        corners[1].z,
        corners[1].inv_w,
        corners[1].color,
        corners[1].u,
        corners[1].v,
        NO_TEXTURE,
        corners[1].blend,
    )
    var renderer = GpuRenderer(24, 24)
    renderer.set_textures(textures)
    with assert_raises():
        renderer.draw(corners, BACKGROUND, SHADE_TEXTURE)
    with assert_raises():
        _ = cpu_textured(corners, 24, textures)


def test_both_backends_agree_on_mipmapped_transparency() raises:
    # Everything at once: a texture with varying alpha, a mipmapped chain, a
    # BLEND surface composited over a transparent clear color, and depth.
    # Each of those has its own test; this is the one that puts them in the
    # same fragment, where a premultiply applied once too often or a level
    # chosen from the wrong footprint would show.
    if skipped_for_lack_of_a_gpu("both backends agree on mipmapped alpha"):
        return
    var textures = TextureStore()
    # A checkerboard whose dark squares are half transparent.
    var pixels = List[UInt8]()
    for y in range(32):  # pragma: no branch
        for x in range(32):  # pragma: no branch
            if (x // 4 + y // 4) % 2 == 0:
                for value in [UInt8(240), UInt8(200), UInt8(60), UInt8(255)]:
                    pixels.append(value)
            else:
                for value in [UInt8(30), UInt8(60), UInt8(220), UInt8(128)]:
                    pixels.append(value)
    var board = textures.add(
        Texture(32, 32, pixels^, REPEAT, BILINEAR, SRGB, mipmapped=True)
    )

    # Minified two and a half times over, and translucent on top of that.
    var corners = List[RasterVertex]()
    var quad = mapped_quad(24, board)
    for corner in quad:
        corners.append(
            RasterVertex(
                corner.x,
                corner.y,
                corner.z,
                corner.inv_w,
                FloatColor(1, 1, 1, 0.6),
                corner.u * 2.5,
                corner.v * 2.5,
                corner.texture,
                BLEND,
            )
        )

    var clear = Color(0, 0, 0, 0)
    var cpu = cpu_textured(corners, 24, textures, clear)
    var gpu = render_triangles(corners, 24, 24, clear, SHADE_TEXTURE, textures)

    # It really is translucent over nothing, and really is filtered.
    var seen = cpu.get_pixel(12, 12)
    assert_true(seen.a > 0 and seen.a < 255, "the surface resolved opaque")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    for y in range(24):
        for x in range(24):
            assert_equal(cpu.depth_at(x, y), gpu.depth_at(x, y))


def gpu_lit_along_z() raises -> Lighting:
    """Return one white directional light along +z, plus a little ambient."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    _ = scene.add(lamp^)
    scene.update()
    scene.add_light(ambient_light(Color(40, 60, 90), 1.0))
    scene.add_light(directional_light(Color(255, 240, 200), NodeId(0)))
    return Lighting(scene)


def bent(x: Float32, y: Float32, normal: Vector3) -> RasterVertex:
    """Return a white corner carrying a normal of its own."""
    return RasterVertex(
        x, y, 0.5, 1, FloatColor(1, 1, 1), 0, 0, NO_TEXTURE, OPAQUE, normal
    )


def test_both_backends_shade_each_fragment_by_its_own_normal() raises:
    # Lighting is no longer baked into the corners, so both backends now
    # interpolate a normal, renormalize it and evaluate every light per
    # fragment. Two implementations of that -- one in Mojo, one in a kernel --
    # have to agree, and a colored ambient plus a colored lamp means a
    # channel swapped anywhere shows up.
    if skipped_for_lack_of_a_gpu("both backends shade per fragment"):
        return
    var lean = Float32(0.70710678)
    var corners = List[RasterVertex]()
    corners.append(bent(0, 0, Vector3(-lean, 0, lean)))
    corners.append(bent(31, 0, Vector3(lean, 0, lean)))
    corners.append(bent(16, 23, Vector3(0, lean, lean)))

    var lighting = gpu_lit_along_z()
    var target = RenderTarget(32, 24, BACKGROUND)
    rasterize_shaded(
        corners[0],
        corners[1],
        corners[2],
        target,
        SHADE_LIT,
        TextureStore(),
        lighting,
    )
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 32, 24, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )

    # The shading really does vary across the face, so this is not two flat
    # fills agreeing.
    var lowest = UInt8(255)
    var highest = UInt8(0)
    for y in range(24):
        for x in range(32):
            var shown = cpu.get_pixel(x, y)
            if shown.r != BACKGROUND.r:
                if shown.r < lowest:
                    lowest = shown.r
                if shown.r > highest:
                    highest = shown.r
    assert_true(Int(highest) - Int(lowest) > 20, "the face shaded almost flat")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_agree_when_a_surface_faces_away() raises:
    # Every light behind the surface: both must land on the ambient term
    # alone, and on the same ambient.
    if skipped_for_lack_of_a_gpu("both backends agree on an unlit face"):
        return
    var away = Vector3(0, 0, -1)
    var corners = List[RasterVertex]()
    corners.append(bent(0, 0, away))
    corners.append(bent(23, 0, away))
    corners.append(bent(0, 23, away))
    var lighting = gpu_lit_along_z()
    var target = RenderTarget(24, 24, BACKGROUND)
    rasterize_shaded(
        corners[0],
        corners[1],
        corners[2],
        target,
        SHADE_LIT,
        TextureStore(),
        lighting,
    )
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    # The ambient is blue-ish, so an unlit face is not black.
    assert_true(cpu.get_pixel(4, 4).b > cpu.get_pixel(4, 4).r)
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_light_a_texture_the_same_way() raises:
    if skipped_for_lack_of_a_gpu("both backends light a texture"):
        return
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(8, 2, Color(240, 60, 20), Color(20, 40, 200))
    )
    var lean = Float32(0.70710678)
    var quad = mapped_quad(24, board)
    var corners = List[RasterVertex]()
    var slants = [
        Vector3(-lean, 0, lean),
        Vector3(lean, 0, lean),
        Vector3(0, lean, lean),
    ]
    for index in range(len(quad)):
        var corner = quad[index]
        corners.append(
            RasterVertex(
                corner.x,
                corner.y,
                corner.z,
                corner.inv_w,
                corner.color,
                corner.u,
                corner.v,
                corner.texture,
                corner.blend,
                slants[index % 3],
            )
        )
    var lighting = gpu_lit_along_z()
    var cpu = cpu_textured_lit(corners, 24, textures, lighting)
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures, lighting
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def cpu_textured_lit(
    corners: List[RasterVertex],
    size: Int,
    textures: TextureStore,
    lighting: Lighting,
) raises -> Framebuffer:
    """Return the CPU rasterizer's textured output under given lights."""
    var target = RenderTarget(size, size, BACKGROUND)
    for triangle in range(len(corners) // 3):  # pragma: no branch
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            target,
            SHADE_TEXTURE,
            textures,
            lighting,
        )
    return target.resolve()


def test_both_backends_match_a_hand_computed_shaded_pixel() raises:
    # An answer worked out on paper rather than taken from either backend,
    # which is what makes this different from the parity tests around it:
    # they prove the two agree, and this proves what they agree *on*.
    #
    # Three corners with inv_w of 1, 0.5 and 0.25, so the perspective
    # correction actually bites. At pixel (1, 1) the sample is (1.5, 1.5) and
    # the screen-space weights are (0.5, 0.25, 0.25); weighting each by its
    # own inv_w and renormalizing gives (8/11, 2/11, 1/11).
    #
    # The normals are the three axes, so the interpolated normal is
    # (2, 1, 8) / 11, whose length is sqrt(69) / 11. Against a white light
    # of intensity pi along +z, which the 1/pi of three.js's Lambert BRDF
    # brings back to one, the Lambert term is 8 / sqrt(69) = 0.963087, and
    # 0.963087 of the light displays as 251.
    #
    # Interpolating lighting computed at the corners instead would give
    # (8/11) * 1 + (2/11) * 0 + (1/11) * 0 = 0.727, which displays as 224.
    if skipped_for_lack_of_a_gpu("a hand-computed shaded pixel"):
        return
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    _ = scene.add(lamp^)
    scene.update()
    scene.add_light(directional_light(Color(255, 255, 255), NodeId(0), FULL))
    var lighting = Lighting(scene)

    var corners = List[RasterVertex]()
    corners.append(
        RasterVertex(
            0.5,
            0.5,
            0.5,
            1.0,
            FloatColor(1, 1, 1),
            0,
            0,
            NO_TEXTURE,
            OPAQUE,
            Vector3(0, 0, 1),
        )
    )
    corners.append(
        RasterVertex(
            4.5,
            0.5,
            0.5,
            0.5,
            FloatColor(1, 1, 1),
            0,
            0,
            NO_TEXTURE,
            OPAQUE,
            Vector3(1, 0, 0),
        )
    )
    corners.append(
        RasterVertex(
            0.5,
            4.5,
            0.5,
            0.25,
            FloatColor(1, 1, 1),
            0,
            0,
            NO_TEXTURE,
            OPAQUE,
            Vector3(0, 1, 0),
        )
    )

    var target = RenderTarget(6, 6, BACKGROUND)
    rasterize_shaded(
        corners[0],
        corners[1],
        corners[2],
        target,
        SHADE_LIT,
        TextureStore(),
        lighting,
    )
    assert_equal(target.shown(1, 1).r, UInt8(251))

    var gpu = render_triangles(
        corners, 6, 6, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    assert_equal(gpu.get_pixel(1, 1).r, UInt8(251))


def test_both_backends_agree_on_every_wrap_mode() raises:
    # Coordinates outside the unit square, so the wrap arithmetic is what is
    # being compared rather than the sampling.
    if skipped_for_lack_of_a_gpu("both backends agree on wrapping"):
        return
    for mode in [REPEAT, CLAMP, MIRROR]:
        var textures = TextureStore()
        var board = textures.add(
            checkerboard(8, 2, Color(240, 60, 20), Color(20, 40, 200), mode)
        )
        var corners = List[RasterVertex]()
        # Three tiles across and up, and starting below zero.
        corners.append(lit_corner(0, 0, 1, -1.0, 2.0, board))
        corners.append(lit_corner(24, 0, 1, 2.0, 2.0, board))
        corners.append(lit_corner(24, 24, 1, 2.0, -1.0, board))
        corners.append(lit_corner(0, 0, 1, -1.0, 2.0, board))
        corners.append(lit_corner(24, 24, 1, 2.0, -1.0, board))
        corners.append(lit_corner(0, 24, 1, -1.0, -1.0, board))
        var gpu = render_triangles(
            corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures
        )
        var cpu = cpu_textured(corners, 24, textures)
        assert_equal(count_mismatches(cpu, gpu), 0)


def test_the_gpu_treats_no_texture_as_white() raises:
    # A width of zero is what the kernel reads to mean "blank", and blank has
    # to leave the lighting exactly alone.
    if skipped_for_lack_of_a_gpu("the gpu treats no texture as white"):
        return
    var corners = mapped_quad(16)
    var lit = render_triangles(corners, 16, 16, BACKGROUND)
    var textured = render_triangles(corners, 16, 16, BACKGROUND, SHADE_TEXTURE)
    assert_equal(count_mismatches(lit, textured), 0)


def test_a_texture_survives_being_drawn_twice() raises:
    # Uploaded once by set_texture rather than per draw, so the second frame
    # has to still find it there.
    if skipped_for_lack_of_a_gpu("a texture survives a second draw"):
        return
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(16, 4, Color(240, 60, 20), Color(20, 40, 200))
    )
    var renderer = GpuRenderer(24, 24)
    renderer.set_textures(textures)
    var corners = mapped_quad(24, board)

    renderer.draw(corners, BACKGROUND, SHADE_TEXTURE)
    var first = renderer.read_back()
    renderer.draw(corners, BACKGROUND, SHADE_TEXTURE)
    var second = renderer.read_back()
    assert_equal(count_mismatches(first, second), 0)
    assert_equal(
        count_mismatches(cpu_textured(corners, 24, textures), first), 0
    )


def test_both_backends_filter_a_texture_identically() raises:
    # Bilinear is floating-point arithmetic, unlike nearest, so this is where
    # a fused multiply-add might have rounded differently. It does not: the
    # two agree exactly, and the assertion below says so rather than allowing
    # a level it does not need. That is measured, not guaranteed -- the blend
    # is a chain of multiply-adds and a device that contracts them differently
    # could land either side of a quantization midpoint. If this ever fails by
    # one level on some other hardware, that is what happened, and
    # `count_mismatches` takes a tolerance for exactly this reason.
    if skipped_for_lack_of_a_gpu("both backends filter a texture"):
        return
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(
            8, 2, Color(240, 60, 20), Color(20, 40, 200), REPEAT, BILINEAR
        )
    )
    var corners = mapped_quad(24, board)
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures
    )
    var cpu = cpu_textured(corners, 24, textures)

    # Blended, not stepped: there are colors between the two.
    var between = 0
    for y in range(24):
        for x in range(24):
            var pixel = cpu.get_pixel(x, y)
            if pixel.r > 60 and pixel.b > 60:
                between += 1
    assert_true(between > 0, "nothing was blended, so nothing was compared")
    assert_equal(count_mismatches(cpu, gpu), 0)


# --- the texture table ------------------------------------------------------


def test_one_draw_can_use_several_different_textures() raises:
    # The machinery this commit introduced: every image crosses as one buffer
    # with a table saying where each starts. Different sizes, filters and wrap
    # modes in a single draw is what exercises the offsets and the selection;
    # one texture at a time never leaves the first descriptor.
    if skipped_for_lack_of_a_gpu("one draw, several textures"):
        return
    var textures = TextureStore()
    var small = textures.add(
        checkerboard(4, 2, Color(255, 0, 0), Color(60, 0, 0), CLAMP, NEAREST)
    )
    var large = textures.add(
        checkerboard(32, 8, Color(0, 0, 255), Color(0, 0, 60), MIRROR, BILINEAR)
    )
    var plain = textures.add(Texture())

    # Three strips side by side, each naming a different descriptor, plus a
    # fourth naming none at all.
    var corners = List[RasterVertex]()
    var ids = [small, large, plain, NO_TEXTURE]
    for slot in range(4):
        var left = Float32(slot) * 8
        var right = left + 8
        corners.append(lit_corner(left, 0, 1, 0, 1, ids[slot]))
        corners.append(lit_corner(right, 0, 1, 1, 1, ids[slot]))
        corners.append(lit_corner(right, 32, 1, 1, 0, ids[slot]))
        corners.append(lit_corner(left, 0, 1, 0, 1, ids[slot]))
        corners.append(lit_corner(right, 32, 1, 1, 0, ids[slot]))
        corners.append(lit_corner(left, 32, 1, 0, 0, ids[slot]))

    var gpu = render_triangles(
        corners, 32, 32, BACKGROUND, SHADE_TEXTURE, textures
    )
    var cpu = cpu_textured(corners, 32, textures)
    assert_equal(count_mismatches(cpu, gpu), 0)

    # And the strips really are different: red, blue, and two whites.
    assert_true(cpu.get_pixel(2, 16).r > cpu.get_pixel(2, 16).b)
    assert_true(cpu.get_pixel(10, 16).b > cpu.get_pixel(10, 16).r)
    assert_equal(cpu.get_pixel(18, 16).r, UInt8(255))
    assert_equal(cpu.get_pixel(26, 16).r, UInt8(255))


def test_a_stored_blank_texture_reads_as_white_on_both_backends() raises:
    # A blank texture is a legitimate thing to store and gets a real id. Left
    # as a zero-width descriptor the kernel reached a modulo by zero and
    # returned black where the CPU returned white.
    if skipped_for_lack_of_a_gpu("a stored blank texture reads as white"):
        return
    var textures = TextureStore()
    var nothing = textures.add(Texture())
    var corners = mapped_quad(16, nothing)
    var gpu = render_triangles(
        corners, 16, 16, BACKGROUND, SHADE_TEXTURE, textures
    )
    var cpu = cpu_textured(corners, 16, textures)
    assert_equal(cpu.get_pixel(4, 4).r, UInt8(255))
    assert_equal(count_mismatches(cpu, gpu), 0)

    # And it matches drawing with no texture at all, which is the contract.
    var untextured = render_triangles(
        mapped_quad(16), 16, 16, BACKGROUND, SHADE_TEXTURE, textures
    )
    assert_equal(count_mismatches(untextured, gpu), 0)


def test_drawing_a_texture_that_was_never_uploaded_is_rejected() raises:
    # The kernel indexes the table with a number that arrived on a vertex, so
    # an id past the end is an unchecked read of device memory. Nothing on the
    # device can tell; the host has to.
    if skipped_for_lack_of_a_gpu("an unuploaded texture is rejected"):
        return
    var renderer = GpuRenderer(16, 16)
    with assert_raises():
        renderer.draw(mapped_quad(16, TextureId(0)), BACKGROUND, SHADE_TEXTURE)

    var textures = TextureStore()
    _ = textures.add(checkerboard(4, 2, Color(255, 0, 0), Color(0, 0, 255)))
    renderer.set_textures(textures)
    # One texture uploaded, so id 0 is fine and id 1 is not.
    renderer.draw(mapped_quad(16, TextureId(0)), BACKGROUND, SHADE_TEXTURE)
    with assert_raises():
        renderer.draw(mapped_quad(16, TextureId(1)), BACKGROUND, SHADE_TEXTURE)


# --- blending ---------------------------------------------------------------


def translucent_pair() -> List[RasterVertex]:
    """Return an opaque pane with a translucent one in front of it."""
    var corners = List[RasterVertex]()
    # Opaque green, far. Opaque first is the order the renderer guarantees.
    corners.append(corner(0, 0, 0.8, 1, Color(0, 255, 0)))
    corners.append(corner(40, 0, 0.8, 1, Color(0, 255, 0)))
    corners.append(corner(0, 40, 0.8, 1, Color(0, 255, 0)))
    # Translucent red, nearer.
    corners.append(corner(0, 0, 0.3, 1, Color(255, 0, 0, 128), BLEND))
    corners.append(corner(40, 0, 0.3, 1, Color(255, 0, 0, 128), BLEND))
    corners.append(corner(0, 40, 0.3, 1, Color(255, 0, 0, 128), BLEND))
    return corners^


def test_both_backends_blend_identically() raises:
    if skipped_for_lack_of_a_gpu("both backends blend identically"):
        return
    var corners = translucent_pair()
    var gpu = render_triangles(corners, 16, 16, BACKGROUND)
    var cpu = cpu_render_triangles(corners, 16, 16)
    # Both colors present at once, which is what blending means.
    assert_true(cpu.get_pixel(2, 2).r > 0)
    assert_true(cpu.get_pixel(2, 2).g > 0)
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_agree_that_a_blend_claims_no_depth() raises:
    # A translucent surface is hidden by what is in front without hiding what
    # is behind, so the depth that comes back is the nearest *solid* one.
    if skipped_for_lack_of_a_gpu("a blend claims no depth"):
        return
    var corners = translucent_pair()
    var gpu = render_triangles(corners, 16, 16, BACKGROUND)
    var cpu = cpu_render_triangles(corners, 16, 16)
    # The opaque pane is at 0.8; the translucent one at 0.3 claims nothing.
    assert_almost_equal(cpu.depth_at(2, 2), Float32(0.8), atol=Float64(1e-5))
    assert_almost_equal(gpu.depth_at(2, 2), Float32(0.8), atol=Float64(1e-5))


def test_both_backends_blend_a_translucent_surface_over_nothing() raises:
    # Over the background rather than over black, which is what the kernel
    # has to decode the clear color for.
    if skipped_for_lack_of_a_gpu("a blend over the background"):
        return
    var corners = List[RasterVertex]()
    corners.append(corner(0, 0, 0.5, 1, Color(255, 255, 255, 128), BLEND))
    corners.append(corner(40, 0, 0.5, 1, Color(255, 255, 255, 128), BLEND))
    corners.append(corner(0, 40, 0.5, 1, Color(255, 255, 255, 128), BLEND))
    var gpu = render_triangles(corners, 16, 16, BACKGROUND)
    var cpu = cpu_render_triangles(corners, 16, 16)
    assert_true(cpu.get_pixel(2, 2).r > BACKGROUND.r)
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_agree_on_depth_in_uv_mode() raises:
    # A debug view of texture coordinates is opaque on both sides: it shows
    # the nearest surface's coordinates, and averaging several surfaces'
    # would mean nothing. The CPU used to read the policy and skip the depth
    # write; the GPU always wrote it, so the two disagreed by an infinity.
    if skipped_for_lack_of_a_gpu("uv mode agrees on depth"):
        return
    var corners = List[RasterVertex]()
    for index in range(3):
        var at = mapped_quad(16)[index]
        corners.append(
            RasterVertex(
                at.x,
                at.y,
                0.5,
                1,
                FloatColor(1, 1, 1, 0.5),
                at.u,
                at.v,
                NO_TEXTURE,
                BLEND,
            )
        )
    var gpu = render_triangles(corners, 16, 16, BACKGROUND, SHADE_UV)
    var drawn = RenderTarget(16, 16, BACKGROUND)
    rasterize_shaded(corners[0], corners[1], corners[2], drawn, SHADE_UV)
    var cpu = drawn.resolve()

    assert_almost_equal(cpu.depth_at(2, 2), Float32(0.5), atol=Float64(1e-6))
    assert_almost_equal(gpu.depth_at(2, 2), Float32(0.5), atol=Float64(1e-6))
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_both_backends_force_a_texture_alpha_to_one_on_an_opaque_surface() raises:
    # An opaque material sampling a partly transparent texture: the surface
    # replaces what is behind it, and its alpha is written as one, as
    # three.js's `opaque_fragment` chunk writes it. A blended surface keeps
    # the sampled alpha and mixes by it. Both backends, both ways.
    if skipped_for_lack_of_a_gpu("texture alpha on an opaque surface"):
        return
    var textures = TextureStore()
    var faded = List[UInt8]()
    for value in [UInt8(255), UInt8(255), UInt8(255), UInt8(128)]:
        faded.append(value)
    var half = textures.add(Texture(1, 1, faded^, REPEAT, NEAREST, LINEAR))

    var corners = mapped_quad(16, half)
    var gpu = render_triangles(
        corners, 16, 16, BACKGROUND, SHADE_TEXTURE, textures
    )
    var cpu = cpu_textured(corners, 16, textures)
    assert_equal(cpu.get_pixel(4, 4).a, UInt8(255))
    assert_equal(cpu.get_pixel(4, 4).r, UInt8(255))
    assert_equal(count_mismatches(cpu, gpu), 0)

    var blended = List[RasterVertex]()
    for base in corners:
        blended.append(blending_as(base, BLEND))
    gpu = render_triangles(blended, 16, 16, BACKGROUND, SHADE_TEXTURE, textures)
    cpu = cpu_textured(blended, 16, textures)
    assert_true(
        cpu.get_pixel(4, 4).r < UInt8(255), "the half alpha did not mix"
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_composite_over_a_transparent_clear_color() raises:
    # Nothing behind means nothing contributes, on both sides.
    if skipped_for_lack_of_a_gpu("compositing over a transparent clear"):
        return
    var clear = Color(0, 0, 255, 0)
    var corners = List[RasterVertex]()
    corners.append(corner(0, 0, 0.5, 1, Color(255, 0, 0, 128), BLEND))
    corners.append(corner(40, 0, 0.5, 1, Color(255, 0, 0, 128), BLEND))
    corners.append(corner(0, 40, 0.5, 1, Color(255, 0, 0, 128), BLEND))
    var gpu = render_triangles(corners, 16, 16, clear)
    var cpu = cpu_render_triangles(corners, 16, 16, clear)
    # The hidden blue contributes nothing, and coverage stays at a half.
    assert_equal(cpu.get_pixel(2, 2).b, UInt8(0))
    assert_equal(cpu.get_pixel(2, 2).a, UInt8(128))
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


# --- the review's regressions ------------------------------------------------


def test_the_gpu_refuses_an_unknown_mode_or_blend_policy() raises:
    # `ShadeMode(99)` and `Blending(7)` construct, and each was once read
    # one way by the host and the other way by the kernel. Both backends now
    # refuse them before drawing.
    if skipped_for_lack_of_a_gpu("the gpu refuses unknown metadata"):
        return
    var corners = overlapping_pair()
    with assert_raises():
        _ = render_triangles(corners, 24, 18, BACKGROUND, ShadeMode(99))
    var odd = List[RasterVertex]()
    for index in range(3):
        var base = corners[index]
        odd.append(
            RasterVertex(
                base.x,
                base.y,
                base.z,
                base.inv_w,
                base.color,
                0,
                0,
                NO_TEXTURE,
                Blending(7),
            )
        )
    with assert_raises():
        _ = render_triangles(odd, 24, 18, BACKGROUND)
    with assert_raises():
        _ = cpu_render_triangles(odd, 24, 18)


def test_flattening_refuses_a_texture_edited_into_nonsense() raises:
    # Host side, so it runs without a GPU: the upload checks every texture
    # again, because the kernel cannot raise on what it finds in the table.
    var textures = TextureStore()
    var board = checkerboard(
        4, 2, Color(255, 255, 255), Color(0, 0, 0), REPEAT, NEAREST
    )
    board.color_space = ColorSpace(99)
    _ = textures.add(board^)
    with assert_raises():
        _ = flatten_textures(textures)


def test_a_failed_texture_upload_leaves_the_old_set_in_place() raises:
    # The failure injected here is the one the host can inject -- a texture
    # that fails validation -- and it lands before any device work. What the
    # test pins is the invariant every failure point now shares: nothing on
    # the device has changed, so the previous upload is whole and the same
    # draw gives the same image. A device allocation failing between the two
    # buffers is not reproducible on demand; `set_textures` builds both as
    # locals and commits them together so that it lands on the same
    # invariant.
    if skipped_for_lack_of_a_gpu("a failed texture upload leaves the old set"):
        return
    var textures = TextureStore()
    var board = textures.add(
        checkerboard(
            8, 4, Color(255, 255, 255), Color(0, 0, 0), REPEAT, NEAREST
        )
    )
    var corners = mapped_quad(24, board)
    var renderer = GpuRenderer(24, 24)
    renderer.set_textures(textures)
    renderer.draw(corners, BACKGROUND, SHADE_TEXTURE)
    var before = renderer.read_back()

    var broken = TextureStore()
    _ = broken.add(
        checkerboard(8, 4, Color(255, 0, 0), Color(0, 0, 255), REPEAT, NEAREST)
    )
    var bad = checkerboard(
        4, 2, Color(255, 255, 255), Color(0, 0, 0), REPEAT, NEAREST
    )
    bad.color_space = ColorSpace(99)
    _ = broken.add(bad^)
    with assert_raises():
        renderer.set_textures(broken)

    renderer.draw(corners, BACKGROUND, SHADE_TEXTURE)
    var after = renderer.read_back()
    assert_equal(count_mismatches(before, after), 0)
    # And the old count still bounds what a vertex may name.
    with assert_raises():
        renderer.draw(mapped_quad(24, TextureId(1)), BACKGROUND, SHADE_TEXTURE)


def test_both_backends_agree_on_every_new_feature_at_once() raises:
    # A camera riding a node under a turned pivot, aimed by `Scene.look_at`;
    # a mipmapped checkerboard floor that runs behind the camera and is
    # clipped; an unlit sphere and a lit cube; a bulb, a sun and some fill.
    # Color to one level, depth to rounding.
    if skipped_for_lack_of_a_gpu("both backends agree on every new feature"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)

    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var ball = assets.geometries.add(sphere(Length(0.6, METER), 12, 8))
    var floor = assets.geometries.add(
        plane(Length(20.0, METER), Length(20.0, METER), 4, 4)
    )
    var board = assets.textures.add(
        checkerboard(
            64,
            8,
            Color(240, 240, 240),
            Color(40, 60, 120),
            REPEAT,
            BILINEAR,
            mipmapped=True,
        )
    )
    var tiled = assets.materials.add(
        Material(Color(255, 255, 255), board, DOUBLE_SIDE)
    )
    var orange = assets.materials.add(Material(Color(255, 140, 40)))
    var plain = assets.materials.add(Material(Color(90, 190, 255), kind=BASIC))

    var scene = Scene()
    var ground = Object3D()
    ground.set_position(0, -0.6, 0)
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var left = Object3D()
    left.set_position(-0.9, 0, 0)
    left.set_euler(Angle(25.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE))
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.9, 0, 0.4)
    var right_node = scene.add(right^)
    var bulb = Object3D()
    bulb.set_position(0.5, 1.0, 1.5)
    var bulb_node = scene.add(bulb^)
    scene.add_light(point_light(Color(255, 220, 180), bulb_node, 0.8))
    var sun = Object3D()
    sun.set_position(0.4, 0.8, 0.5)
    var sun_node = scene.add(sun^)
    scene.add_light(directional_light(Color(255, 255, 255), sun_node, 0.5))
    scene.add_light(ambient_light(Color(255, 255, 255), 0.1))
    var pivot = Object3D()
    pivot.set_euler(Angle(0.0, DEGREE), Angle(30.0, DEGREE), Angle(0.0, DEGREE))
    var rig = scene.add(pivot^)
    var eye = Object3D()
    eye.set_position(0, 0.6, 3.0)
    var eye_node = scene.attach(eye^, rig)
    scene.update()
    scene.look_at(eye_node, Vector3(0, 0, 0), camera=True)
    scene.update()

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.attach(eye_node)

    var meshes = List[Mesh]()
    meshes.append(Mesh(floor, tiled, ground_node))
    meshes.append(Mesh(box, orange, left_node))
    meshes.append(Mesh(ball, plain, right_node))
    var corners = prepared(renderer, scene, assets, meshes, camera)
    var lighting = Lighting(scene)
    var target = RenderTarget(48, 36, BACKGROUND)
    for triangle in range(len(corners) // 3):  # pragma: no branch
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            target,
            SHADE_TEXTURE,
            assets.textures,
            lighting,
        )
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 48, 36, BACKGROUND, SHADE_TEXTURE, assets.textures, lighting
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 300, "the scene barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    for y in range(36):
        for x in range(48):
            var theirs = cpu.depth_at(x, y)
            var ours = gpu.depth_at(x, y)
            if theirs == inf[DType.float32]():
                assert_equal(ours, theirs)
            else:
                assert_almost_equal(ours, theirs, atol=Float64(1e-5))


def test_both_backends_agree_on_a_transformed_texture() raises:
    # A texture's offset, repeat, rotation and center are applied to the
    # coordinates in prepare, so both rasterizers are handed the same
    # turned and tiled coordinates and sample the same texels. Nearest
    # sampling, so exactly.
    if skipped_for_lack_of_a_gpu(
        "both backends agree on a transformed texture"
    ):
        return
    var renderer = Renderer(32, 32)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var board = checkerboard(8, 4, Color(240, 60, 20), Color(20, 40, 200))
    board.repeat = Vector2(2, 1.5)
    board.rotation = Angle(30.0, DEGREE)
    board.center = Vector2(0.5, 0.5)
    board.offset = Vector2(0.1, -0.2)
    var skin = assets.materials.add(
        Material(Color(255, 255, 255), assets.textures.add(board^), kind=BASIC)
    )
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    var camera = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 3), Vector3(0, 0, 0))
    var meshes = List[Mesh]()
    meshes.append(Mesh(sheet, skin, NodeId(0)))
    var corners = prepared(renderer, scene, assets, meshes, camera)
    assert_equal(len(corners), 6)
    var cpu = cpu_textured(corners, 32, assets.textures)
    var gpu = render_triangles(
        corners, 32, 32, BACKGROUND, SHADE_TEXTURE, assets.textures
    )
    # A real pattern: both colors present, so the mapping did something.
    var light = 0
    var dark = 0
    for y in range(32):
        for x in range(32):
            if cpu.get_pixel(x, y).r > 200:
                light += 1
            if cpu.get_pixel(x, y).b > 150:
                dark += 1
    assert_true(light > 0 and dark > 0, "the checkerboard did not appear")
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_both_backends_agree_on_an_instanced_scene() raises:
    # Instances are folded into world matrices in prepare, so both
    # rasterizers are handed one list of triangles for the whole forest
    # and fill it the same way.
    if skipped_for_lack_of_a_gpu("both backends agree on an instanced scene"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(0.8, METER)))
    var paint = assets.materials.add(Material(Color(255, 140, 40)))
    var scene = Scene()
    var root = scene.add(Object3D())
    light_the(scene)
    scene.update()
    var group = InstancedMesh(box, paint, root, 4)
    group.set_matrix_at(0, translation(-1.2, 0, 0))
    group.set_matrix_at(1, translation(1.2, 0.3, -0.5))
    group.set_matrix_at(2, translation(0, -0.6, 0.4))
    group.set_matrix_at(3, translation(0, 0, 30))
    scene.add_instanced_mesh(group^)
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.6, 4.0), Vector3(0, 0, 0))
    var corners = renderer.prepare(scene, assets, camera)
    assert_true(len(corners) > 0, "the instances prepared no triangles")
    var lighting = Lighting(scene)
    var target = RenderTarget(48, 36, BACKGROUND)
    for triangle in range(len(corners) // 3):  # pragma: no branch
        rasterize_shaded(
            corners[triangle * 3],
            corners[triangle * 3 + 1],
            corners[triangle * 3 + 2],
            target,
            SHADE_LIT,
            assets.textures,
            lighting,
        )
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 48, 36, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 100, "the forest barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


# --- normal and depth materials, both backends ------------------------------


def of_kind(
    base: RasterVertex,
    kind: MaterialKind,
    normal: Vector3 = Vector3(0, 0, 1),
    depth: Float32 = 0,
) -> RasterVertex:
    """Return `base` as a surface of `kind`, facing `normal`."""
    return RasterVertex(
        base.x,
        base.y,
        base.z,
        base.inv_w,
        base.color,
        base.u,
        base.v,
        base.texture,
        base.blend,
        normal,
        base.world,
        kind,
        base.emissive,
        base.emissive_map,
        depth,
    )


def data_pair(kind: MaterialKind, depth: Float32 = 0) -> List[RasterVertex]:
    """Return `overlapping_pair` as surfaces of `kind`, each corner facing a
    different way so the normal is really interpolated."""
    var normals: List[Vector3] = [
        Vector3(0, 0, 1),
        Vector3(1, 0, 0.5),
        Vector3(0, -1, 0.25),
        Vector3(-0.5, 0.5, 1),
        Vector3(0, 0.5, 0),
        Vector3(0.25, 0, -1),
    ]
    var corners = List[RasterVertex]()
    var base = overlapping_pair()
    for index in range(len(base)):
        corners.append(of_kind(base[index], kind, normals[index], depth))
    return corners^


def test_both_backends_agree_on_a_normal_material() raises:
    # The kernel packs the interpolated normal with the host's own
    # functions, from the state table's kind, and neither lights it.
    if skipped_for_lack_of_a_gpu("both backends agree on a normal material"):
        return
    var corners = data_pair(NORMALS)
    # Lighting that would halve everything if it reached these fragments.
    var half = Lighting(ambient=FloatColor(0.5, 0.5, 0.5, 1.0))
    var target = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(corners, target, SHADE_TEXTURE, TextureStore(), half)
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 24, 18, BACKGROUND, SHADE_TEXTURE, TextureStore(), half
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # And it really shows the normal rather than the corner colors: the
    # same triangles as a basic material differ.
    var plain = render_triangles(
        corners_of(BASIC),
        24,
        18,
        BACKGROUND,
        SHADE_TEXTURE,
        TextureStore(),
        half,
    )
    assert_true(count_mismatches(gpu, plain) > 50, "the normal changed nothing")


def corners_of(kind: MaterialKind) -> List[RasterVertex]:
    """Return `data_pair` of another kind, for comparing one against
    another."""
    return data_pair(kind)


def test_both_backends_agree_on_a_depth_material() raises:
    # The depth comes from the same interpolated z on both sides, packed by
    # the same function, and the normal is not read at all.
    if skipped_for_lack_of_a_gpu("both backends agree on a depth material"):
        return
    var corners = data_pair(DEPTH)
    var half = Lighting(ambient=FloatColor(0.5, 0.5, 0.5, 1.0))
    var target = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(corners, target, SHADE_TEXTURE, TextureStore(), half)
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 24, 18, BACKGROUND, SHADE_TEXTURE, TextureStore(), half
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # The near triangle is the paler gray on both, as one minus the depth.
    assert_true(
        cpu.get_pixel(12, 12).r > cpu.get_pixel(3, 3).r,
        "the nearer surface was not the paler gray",
    )
    var normals = render_triangles(
        corners_of(NORMALS),
        24,
        18,
        BACKGROUND,
        SHADE_TEXTURE,
        TextureStore(),
        half,
    )
    assert_true(
        count_mismatches(gpu, normals) > 50, "the depth and the normal agreed"
    )


def test_both_backends_keep_data_out_of_the_fog_and_the_curve() raises:
    # A fog veils light and a curve compresses it, and a normal is neither.
    # Both backends must leave the same pixels alone.
    if skipped_for_lack_of_a_gpu("both backends keep data out of the fog"):
        return
    var fog = FogView(
        linear_fog(Color(255, 0, 0), Length(1.0, METER), Length(4.0, METER))
    )
    for kind in [NORMALS, DEPTH]:
        var corners = data_pair(kind, 3.0)
        var target = RenderTarget(24, 18, BACKGROUND)
        rasterize_all(
            corners,
            target,
            SHADE_TEXTURE,
            TextureStore(),
            Lighting.uniform(),
            1,
            fog,
        )
        var cpu = target.resolve(1, REINHARD_TONE_MAPPING, 0.8)
        var gpu = render_triangles(
            corners,
            24,
            18,
            BACKGROUND,
            SHADE_TEXTURE,
            TextureStore(),
            Lighting.uniform(),
            fog,
            REINHARD_TONE_MAPPING,
            0.8,
        )
        assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
        # And the data itself came through untouched by either: the same
        # triangles with no fog and no curve give the same covered pixels.
        var clear = render_triangles(
            data_pair(kind, 3.0),
            24,
            18,
            BACKGROUND,
            SHADE_TEXTURE,
            TextureStore(),
            Lighting.uniform(),
        )
        assert_equal(clear.get_pixel(12, 12).r, gpu.get_pixel(12, 12).r)
        assert_equal(clear.get_pixel(12, 12).g, gpu.get_pixel(12, 12).g)
        assert_equal(clear.get_pixel(12, 12).b, gpu.get_pixel(12, 12).b)


def test_the_gpu_refuses_a_material_kind_it_has_no_path_for() raises:
    if skipped_for_lack_of_a_gpu("the gpu refuses an unknown material kind"):
        return
    var renderer = GpuRenderer(8, 8)
    with assert_raises():
        renderer.draw(data_pair(MaterialKind(9)), BACKGROUND)
    # And corners that disagree, which is the check it shares with the CPU.
    var mixed = data_pair(NORMALS)
    mixed[1] = of_kind(mixed[1], DEPTH)
    with assert_raises():
        renderer.draw(mixed, BACKGROUND)


def test_both_backends_agree_on_a_scene_that_mixes_light_and_data() raises:
    # One frame holding a lit floor, a sphere showing its normals and a box
    # showing its depth, under a fog and a curve: the light is veiled and
    # compressed, the data is not, and the two backends decide that per
    # pixel in the same way.
    if skipped_for_lack_of_a_gpu("both backends agree on light and data"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var floor = assets.geometries.add(
        plane(Length(12.0, METER), Length(12.0, METER), 4, 4)
    )
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 12, 8))
    var box = assets.geometries.add(cube(Length(1.0, METER)))

    var scene = Scene()
    var ground = Object3D()
    ground.set_position(0, -1.0, 0)
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var left = Object3D()
    left.set_position(-1.0, 0, 0)
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(1.0, 0, -0.5)
    right.set_euler(
        Angle(20.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE)
    )
    var right_node = scene.add(right^)
    light_the(scene)
    scene.fog = linear_fog(
        Color(160, 170, 190), Length(2.0, METER), Length(9.0, METER)
    )
    scene.update()

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            floor,
            assets.materials.add(Material(Color(200, 200, 200))),
            ground_node,
        )
    )
    meshes.append(
        Mesh(ball, assets.materials.add(normal_material()), left_node)
    )
    meshes.append(Mesh(box, assets.materials.add(depth_material()), right_node))

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.5, METER),
        Length(8.0, METER),
    )
    camera.place(Vector3(0, 0.8, 3.2), Vector3(0, 0, 0))

    var corners = prepared(renderer, scene, assets, meshes, camera)
    assert_true(len(corners) > 0, "the scene prepared no triangles")
    var lighting = Lighting(scene)
    var view = FogView(scene.fog)
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_all(
        corners, target, SHADE_TEXTURE, assets.textures, lighting, 1, view
    )
    var cpu = target.resolve(1, ACES_FILMIC_TONE_MAPPING, 1.1)
    var gpu = render_triangles(
        corners,
        48,
        36,
        BACKGROUND,
        SHADE_TEXTURE,
        assets.textures,
        lighting,
        view,
        ACES_FILMIC_TONE_MAPPING,
        1.1,
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 300, "the scene barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # Some pixel held data and some held light, or this proves nothing.
    var holds_data = 0
    for y in range(36):
        for x in range(48):
            if target.is_data(x, y):
                holds_data += 1
    assert_true(holds_data > 50, "no pixel held data")
    assert_true(holds_data < drawn, "every drawn pixel held data")


# --- alpha maps and the alpha test, both backends ---------------------------


def a_gpu_mask(
    green: UInt8,
    space: ColorSpace = LINEAR,
    alpha: Alpha = IGNORED,
) raises -> Texture:
    """Return a one-texel alpha map whose green channel is `green`."""
    var pixels = List[UInt8]()
    pixels.append(0)
    pixels.append(green)
    pixels.append(255)
    pixels.append(255)
    return Texture(1, 1, pixels^, REPEAT, NEAREST, space, False, alpha)


def thinned(
    base: RasterVertex, alpha_map: TextureId, alpha_test: Float32
) -> RasterVertex:
    """Return `base` thinned by `alpha_map` and cut by `alpha_test`."""
    return RasterVertex(
        base.x,
        base.y,
        base.z,
        base.inv_w,
        base.color,
        base.u,
        base.v,
        base.texture,
        base.blend,
        base.normal,
        base.world,
        base.kind,
        base.emissive,
        base.emissive_map,
        base.view_depth,
        alpha_map,
        alpha_test,
    )


def blending_as(base: RasterVertex, blend: Blending) -> RasterVertex:
    """Return `base` with its blending changed to `blend`."""
    return RasterVertex(
        base.x,
        base.y,
        base.z,
        base.inv_w,
        base.color,
        base.u,
        base.v,
        base.texture,
        blend,
        base.normal,
        base.world,
        base.kind,
        base.emissive,
        base.emissive_map,
        base.view_depth,
        base.alpha_map,
        base.alpha_test,
    )


def thinned_pair(
    alpha_map: TextureId, alpha_test: Float32, blend: Blending = BLEND
) -> List[RasterVertex]:
    """Return `mapped_quad` thinned and cut, so the uv really varies.

    The quad is blended unless asked otherwise: an opaque surface writes
    alpha one whatever its map says, as three.js's `opaque_fragment` does,
    so only a blended one shows the thinning without an alpha test.
    """
    var corners = List[RasterVertex]()
    for base in mapped_quad(24):
        corners.append(blending_as(thinned(base, alpha_map, alpha_test), blend))
    return corners^


def test_flattening_carries_the_alpha_test_in_its_own_lane() raises:
    # It is the only float among the per-triangle state, so it rides a lane
    # of its own rather than the integer state table.
    var corners = List[RasterVertex]()
    corners.append(
        RasterVertex(1, 2, 3, 4, FloatColor(1, 1, 1), alpha_test=0.375)
    )
    var flat = flatten(corners)
    assert_equal(len(flat), 28)
    assert_equal(len(flat), FLOATS_PER_VERTEX)
    assert_equal(flat[20], Float32(0.375))
    # And a corner that says nothing about it carries zero, no test.
    var plain = List[RasterVertex]()
    plain.append(RasterVertex(0, 0, 0.5, 1, FloatColor(1, 1, 1)))
    assert_equal(flatten(plain)[20], Float32(0))


def test_the_state_table_carries_the_alpha_map() raises:
    var corners = List[RasterVertex]()
    for _ in range(3):
        corners.append(
            RasterVertex(
                0,
                0,
                0.5,
                1,
                FloatColor(1, 1, 1),
                alpha_map=TextureId(7),
            )
        )
    var state = triangle_state(corners)
    assert_equal(len(state), STATE_PER_TRIANGLE)
    assert_equal(len(state), 7)
    assert_equal(state[4], Int32(7))
    var plain = List[RasterVertex]()
    for _ in range(3):
        plain.append(RasterVertex(0, 0, 0.5, 1, FloatColor(1, 1, 1)))
    assert_equal(triangle_state(plain)[4], Int32(NO_TEXTURE.value))


def test_both_backends_thin_a_surface_by_the_same_green() raises:
    # The kernel reads the map's green channel and multiplies the alpha by
    # it, exactly as the host does, from the same sampler.
    if skipped_for_lack_of_a_gpu("both backends thin by the same green"):
        return
    var textures = TextureStore()
    var mask = textures.add(a_gpu_mask(128))
    var corners = thinned_pair(mask, 0.0)
    var target = RenderTarget(24, 24, BACKGROUND)
    rasterize_all(corners, target, SHADE_TEXTURE, textures)
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 24, 24, BACKGROUND, SHADE_TEXTURE, textures
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # And the map really thinned it: the same draw with no map differs.
    var whole = render_triangles(
        thinned_pair(NO_TEXTURE, 0.0),
        24,
        24,
        BACKGROUND,
        SHADE_TEXTURE,
        textures,
    )
    assert_true(count_mismatches(gpu, whole) > 50, "the map thinned nothing")


def test_both_backends_cut_the_same_fragments_out() raises:
    # The alpha test discards on both sides, and a discarded fragment
    # claims no depth on either: the kernel leaves `nearest` alone where
    # the host defers its `claim_depth`.
    if skipped_for_lack_of_a_gpu("both backends cut the same fragments"):
        return
    var textures = TextureStore()
    var mask = textures.add(a_gpu_mask(128))
    # A test just above the map's green, so every fragment goes. Opaque,
    # so a survivor claims depth.
    var corners = thinned_pair(mask, 0.6, OPAQUE)
    var target = RenderTarget(24, 24, BACKGROUND)
    rasterize_all(corners, target, SHADE_TEXTURE, textures)
    var cpu = target.resolve()
    var renderer = GpuRenderer(24, 24)
    renderer.set_textures(textures)
    renderer.draw(corners, BACKGROUND, SHADE_TEXTURE)
    var gpu = renderer.read_back()
    assert_equal(count_mismatches(cpu, gpu), 0)
    # Nothing survived, so neither backend claimed a depth anywhere.
    for y in range(24):
        for x in range(24):
            assert_true(cpu.depth_at(x, y) > 1.0e30, "the host claimed a depth")
            assert_true(
                gpu.depth_at(x, y) > 1.0e30, "the kernel claimed a depth"
            )
    # A test just below it keeps every fragment, and both then claim depth.
    var kept = thinned_pair(mask, 0.4, OPAQUE)
    var second = RenderTarget(24, 24, BACKGROUND)
    rasterize_all(kept, second, SHADE_TEXTURE, textures)
    var solid = second.resolve()
    renderer.draw(kept, BACKGROUND, SHADE_TEXTURE)
    var device = renderer.read_back()
    assert_equal(count_mismatches(solid, device, tolerance=1), 0)
    assert_true(
        solid.depth_at(12, 12) < 1.0e30, "nothing survived the looser test"
    )
    assert_almost_equal(
        device.depth_at(12, 12), solid.depth_at(12, 12), atol=Float64(1e-6)
    )


def test_both_backends_show_what_is_behind_a_hole() raises:
    # The near surface is cut away entirely and the far one, submitted
    # after it and further away, is drawn in its place on both backends.
    if skipped_for_lack_of_a_gpu("both backends show what is behind a hole"):
        return
    var textures = TextureStore()
    var mask = textures.add(a_gpu_mask(0))
    var corners = List[RasterVertex]()
    for base in overlapping_pair():
        corners.append(thinned(base, mask, 0.5))
    for base in overlapping_pair():
        corners.append(thinned(base, NO_TEXTURE, 0.0))
    var target = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(corners, target, SHADE_TEXTURE, textures)
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 24, 18, BACKGROUND, SHADE_TEXTURE, textures
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # The surviving surface really is there, or the hole showed nothing.
    var drawn = 24 * 18 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 100, "nothing was drawn through the hole")


def test_the_gpu_refuses_an_alpha_map_it_cannot_sample() raises:
    if skipped_for_lack_of_a_gpu("the gpu refuses a bad alpha map"):
        return
    var renderer = GpuRenderer(16, 16)
    # Never uploaded: the kernel would index the descriptor table past its
    # end, which is an unchecked read of device memory.
    with assert_raises():
        renderer.draw(
            thinned_pair(TextureId(0), 0.0), BACKGROUND, SHADE_TEXTURE
        )
    # Uploaded but not stored as data, each way round.
    var encoded = TextureStore()
    var wrong = encoded.add(a_gpu_mask(128, SRGB, IGNORED))
    renderer.set_textures(encoded)
    with assert_raises():
        renderer.draw(thinned_pair(wrong, 0.0), BACKGROUND, SHADE_TEXTURE)
    var covered = TextureStore()
    var alpha = covered.add(a_gpu_mask(128, LINEAR, COVERAGE))
    renderer.set_textures(covered)
    with assert_raises():
        renderer.draw(thinned_pair(alpha, 0.0), BACKGROUND, SHADE_TEXTURE)
    # `SHADE_LIT` never opens it, so it is not refused there.
    renderer.draw(thinned_pair(alpha, 0.0), BACKGROUND, SHADE_LIT)


def test_both_backends_refuse_an_alpha_test_they_cannot_reach() raises:
    if skipped_for_lack_of_a_gpu("both backends refuse a bad alpha test"):
        return
    var renderer = GpuRenderer(8, 8)
    var target = RenderTarget(8, 8, BACKGROUND)
    for bad in [Float32(-0.25), Float32(2.0)]:
        var corners = thinned_pair(NO_TEXTURE, bad)
        with assert_raises():
            renderer.draw(corners, BACKGROUND, SHADE_TEXTURE)
        with assert_raises():
            rasterize_all(corners, target, SHADE_TEXTURE)


# --- the phong highlight, both backends -------------------------------------


def test_flattening_carries_the_specular_and_the_shininess() raises:
    # Four more lanes: the specular as three, like the emissive, and the
    # shininess as one per-triangle float, like the alpha test.
    var corners = List[RasterVertex]()
    corners.append(
        RasterVertex(
            1,
            2,
            3,
            4,
            FloatColor(1, 1, 1),
            specular=FloatColor(0.25, 0.5, 0.75),
            shininess=30.0,
        )
    )
    var flat = flatten(corners)
    assert_equal(len(flat), 28)
    assert_equal(len(flat), FLOATS_PER_VERTEX)
    assert_equal(flat[21], Float32(0.25))
    assert_equal(flat[22], Float32(0.5))
    assert_equal(flat[23], Float32(0.75))
    assert_equal(flat[24], Float32(30.0))


def test_the_light_buffer_begins_with_the_camera_and_its_direction() raises:
    # A highlight is measured from there, and putting the camera at the
    # head leaves every light's offset one named constant away. The
    # direction beside it is what a parallel projection puts there.
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 1.0))
    scene.add_light(directional_light(Color(255, 255, 255), node, 1.0))
    scene.update()
    var flat = flatten_lights(Lighting(scene, Layers.all(), Vector3(7, 8, 9)))
    assert_equal(len(flat), LIGHTS_FIRST + 6)
    assert_equal(flat[LIGHTS_EYE], Float32(7))
    assert_equal(flat[LIGHTS_EYE + 1], Float32(8))
    assert_equal(flat[LIGHTS_EYE + 2], Float32(9))
    # Nothing said which way the camera lies, so the lanes hold the zero
    # vector that means a converging view; see `toward_eye_at`.
    assert_equal(flat[LIGHTS_TOWARD], Float32(0))
    assert_equal(flat[LIGHTS_TOWARD + 1], Float32(0))
    assert_equal(flat[LIGHTS_TOWARD + 2], Float32(0))
    assert_equal(flat[LIGHTS_AMBIENT], Float32(1))
    # The one directional light follows, its unit direction then its light.
    assert_equal(flat[LIGHTS_FIRST + 2], Float32(1))
    assert_equal(flat[LIGHTS_FIRST + 3], Float32(1))
    # A parallel projection puts its one direction there, normalized on the
    # way in so no fragment has to.
    var flat_view = flatten_lights(
        Lighting(scene, Layers.all(), Vector3(7, 8, 9), Vector3(0, 0, 4))
    )
    assert_equal(flat_view[LIGHTS_TOWARD], Float32(0))
    assert_equal(flat_view[LIGHTS_TOWARD + 1], Float32(0))
    assert_equal(flat_view[LIGHTS_TOWARD + 2], Float32(1))
    # The camera's own up axis follows, normalized on the way in. World
    # up is what an upright camera has and what a caller that says
    # nothing gets.
    assert_equal(flat[LIGHTS_UP], Float32(0))
    assert_equal(flat[LIGHTS_UP + 1], Float32(1))
    assert_equal(flat[LIGHTS_UP + 2], Float32(0))
    var rolled = flatten_lights(
        Lighting(
            scene,
            Layers.all(),
            Vector3(7, 8, 9),
            PERSPECTIVE_VIEW,
            Vector3(0, 0, 5),
        )
    )
    assert_equal(rolled[LIGHTS_UP + 2], Float32(1))
    assert_equal(rolled[LIGHTS_UP + 1], Float32(0))


def phong_pair(specular: FloatColor, shininess: Float32) -> List[RasterVertex]:
    """Return `overlapping_pair` as phong surfaces, each corner facing a
    different way so the highlight really varies across the triangles."""
    var normals: List[Vector3] = [
        Vector3(0, 0, 1),
        Vector3(0.3, 0, 1),
        Vector3(0, 0.4, 1),
        Vector3(-0.2, 0.1, 1),
        Vector3(0.1, -0.3, 1),
        Vector3(0, 0, 1),
    ]
    var corners = List[RasterVertex]()
    var base = overlapping_pair()
    for index in range(len(base)):
        var here = base[index]
        corners.append(
            RasterVertex(
                here.x,
                here.y,
                here.z,
                here.inv_w,
                here.color,
                here.u,
                here.v,
                here.texture,
                here.blend,
                normals[index],
                Vector3(Float32(index) * 0.2 - 0.5, Float32(index) * 0.1, 0.0),
                PHONG,
                here.emissive,
                here.emissive_map,
                here.view_depth,
                NO_TEXTURE,
                0,
                specular,
                shininess,
            )
        )
    return corners^


def phong_lighting() raises -> Lighting:
    """Return a sun, a bulb and a cone, with the camera up the z axis."""
    var scene = Scene()
    var sun = Object3D()
    sun.set_position(0.4, 0.8, 0.6)
    var sun_node = scene.add(sun^)
    scene.add_light(directional_light(Color(255, 250, 240), sun_node, 0.9))
    var bulb = Object3D()
    bulb.set_position(-0.8, 0.5, 1.2)
    var bulb_node = scene.add(bulb^)
    scene.add_light(point_light(Color(255, 210, 170), bulb_node, 2.0))
    var beam = Object3D()
    beam.set_position(0.6, 1.0, 1.4)
    var beam_node = scene.add(beam^)
    scene.add_light(
        spot_light(
            Color(200, 220, 255), beam_node, 3.0, angle=Angle(50.0, DEGREE)
        )
    )
    scene.add_light(ambient_light(Color(255, 255, 255), 0.2))
    scene.update()
    return Lighting(scene, Layers.all(), Vector3(0, 0, 3))


def test_both_backends_agree_on_a_phong_highlight() raises:
    # Blinn's half vector, three.js's Fresnel, geometric term and lobe,
    # summed over the lights that have a direction: the kernel calls the
    # same function as the host and must reach the same pixels.
    if skipped_for_lack_of_a_gpu("both backends agree on a phong highlight"):
        return
    var lighting = phong_lighting()
    var corners = phong_pair(FloatColor(0.3, 0.3, 0.3), 30.0)
    var target = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(corners, target, SHADE_LIT, TextureStore(), lighting)
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 24, 18, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # And the highlight really is there: the same surfaces as lambert ones
    # differ.
    var plain = List[RasterVertex]()
    for here in phong_pair(FloatColor(0.3, 0.3, 0.3), 30.0):
        plain.append(of_kind(here, LAMBERT, here.normal))
    var flat = render_triangles(
        plain, 24, 18, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    assert_true(
        count_mismatches(gpu, flat) > 50, "the highlight changed nothing"
    )


def test_both_backends_agree_on_every_shininess() raises:
    # The lobe is a power, spelled as exp2 of log2 on both sides so the
    # two round alike, and a wide lobe and a tight one take that path
    # differently.
    if skipped_for_lack_of_a_gpu("both backends agree on every shininess"):
        return
    var lighting = phong_lighting()
    for shininess in [
        Float32(0.0),
        Float32(1.0),
        Float32(30.0),
        Float32(200.0),
    ]:
        var corners = phong_pair(FloatColor(0.6, 0.5, 0.4), shininess)
        var target = RenderTarget(24, 18, BACKGROUND)
        rasterize_all(corners, target, SHADE_LIT, TextureStore(), lighting)
        var cpu = target.resolve()
        var gpu = render_triangles(
            corners, 24, 18, BACKGROUND, SHADE_LIT, TextureStore(), lighting
        )
        assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_agree_on_a_prepared_phong_scene() raises:
    # A whole frame: a lit floor, a phong sphere and a phong box, through a
    # fog and a curve, prepared once and filled twice.
    if skipped_for_lack_of_a_gpu("both backends agree on a phong scene"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var floor = assets.geometries.add(
        plane(Length(12.0, METER), Length(12.0, METER), 4, 4)
    )
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 16, 12))
    var box = assets.geometries.add(cube(Length(1.0, METER)))

    var scene = Scene()
    var ground = Object3D()
    ground.set_position(0, -1.0, 0)
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var left = Object3D()
    left.set_position(-1.0, 0, 0)
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(1.0, 0, -0.4)
    right.set_euler(
        Angle(20.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE)
    )
    var right_node = scene.add(right^)
    light_the(scene)
    var bulb = Object3D()
    bulb.set_position(0.5, 1.2, 1.5)
    var bulb_node = scene.add(bulb^)
    scene.add_light(point_light(Color(255, 220, 180), bulb_node, 2.0))
    scene.fog = linear_fog(
        Color(160, 170, 190), Length(3.0, METER), Length(12.0, METER)
    )
    scene.update()

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            floor,
            assets.materials.add(Material(Color(200, 200, 200))),
            ground_node,
        )
    )
    meshes.append(
        Mesh(
            ball,
            assets.materials.add(
                phong_material(
                    Color(200, 60, 60), NO_TEXTURE, Color(255, 255, 255), 60.0
                )
            ),
            left_node,
        )
    )
    meshes.append(
        Mesh(
            box,
            assets.materials.add(
                phong_material(
                    Color(60, 120, 200), NO_TEXTURE, Color(80, 80, 80), 8.0
                )
            ),
            right_node,
        )
    )

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.5, METER),
        Length(12.0, METER),
    )
    camera.place(Vector3(0, 0.8, 3.2), Vector3(0, 0, 0))

    var corners = prepared(renderer, scene, assets, meshes, camera)
    assert_true(len(corners) > 0, "the scene prepared no triangles")
    var lighting = Lighting(
        scene, camera.visible_layers(), camera_position(scene, camera)
    )
    var view = FogView(scene.fog)
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_all(
        corners, target, SHADE_TEXTURE, assets.textures, lighting, 1, view
    )
    var cpu = target.resolve(1, ACES_FILMIC_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        corners,
        48,
        36,
        BACKGROUND,
        SHADE_TEXTURE,
        assets.textures,
        lighting,
        view,
        ACES_FILMIC_TONE_MAPPING,
        1.0,
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 300, "the scene barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_refuse_a_shininess_they_cannot_reach() raises:
    if skipped_for_lack_of_a_gpu("both backends refuse a bad shininess"):
        return
    var renderer = GpuRenderer(8, 8)
    var target = RenderTarget(8, 8, BACKGROUND)
    var corners = phong_pair(FloatColor(1, 1, 1), -1.0)
    with assert_raises():
        renderer.draw(corners, BACKGROUND)
    with assert_raises():
        rasterize_all(corners, target)


# --- a blend that covers nothing, on both backends --------------------------


def sheet_over(z: Float32, alpha: Float32) -> List[RasterVertex]:
    """Return two blended triangles covering everything, at `alpha`.

    White, so a backend that lets an empty source-over contribute shows it
    at once.

    Args:
        z: Depth to put them at, in front of what they cover.
        alpha: Coverage, zero for a fragment that must change nothing.

    Returns:
        Six raster vertices, three per triangle.
    """
    var places: List[Tuple[Float32, Float32]] = [
        (Float32(0), Float32(0)),
        (Float32(40), Float32(0)),
        (Float32(0), Float32(40)),
        (Float32(40), Float32(0)),
        (Float32(40), Float32(40)),
        (Float32(0), Float32(40)),
    ]
    var corners = List[RasterVertex]()
    for place in places:
        corners.append(
            RasterVertex(
                place[0],
                place[1],
                z,
                1,
                FloatColor(1, 1, 1, alpha),
                blend=BLEND,
            )
        )
    return corners^


def test_both_backends_ignore_a_blend_that_covers_nothing() raises:
    # Source-over at alpha zero hides nothing and adds nothing, so it must
    # add no color and no depth. The kernel recorded both before it looked
    # at the alpha.
    #
    # The surfaces underneath are `BASIC` rather than `NORMALS`: a blended
    # fragment may not share a tone-mapped frame with a data material at
    # all now, and that refusal is what puts the flag half of this rule out
    # of reach here. `RenderTarget.blend` is still held to it directly, in
    # `tests/test_target.mojo`.
    if skipped_for_lack_of_a_gpu("both backends ignore an empty blend"):
        return
    var covered = data_pair(BASIC)
    for here in sheet_over(0.05, 0.0):
        covered.append(here)
    var alone = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(
        data_pair(BASIC),
        alone,
        SHADE_TEXTURE,
        TextureStore(),
        Lighting.uniform(),
    )
    var under = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(
        covered, under, SHADE_TEXTURE, TextureStore(), Lighting.uniform()
    )
    var plain = alone.resolve(1, REINHARD_TONE_MAPPING, 1.0)
    var veiled = under.resolve(1, REINHARD_TONE_MAPPING, 1.0)
    assert_equal(count_mismatches(plain, veiled), 0)
    var gpu = render_triangles(
        covered,
        24,
        18,
        BACKGROUND,
        SHADE_TEXTURE,
        TextureStore(),
        Lighting.uniform(),
        FogView(no_fog()),
        REINHARD_TONE_MAPPING,
        1.0,
    )
    assert_equal(count_mismatches(plain, gpu, tolerance=1), 0)
    for y in range(18):
        for x in range(24):
            assert_almost_equal(
                gpu.depth_at(x, y), plain.depth_at(x, y), atol=Float64(1e-5)
            )
    # A sheet that does cover something changes both, so the rule is about
    # the alpha and not about the sheet.
    var faint = data_pair(BASIC)
    for here in sheet_over(0.05, 0.5):
        faint.append(here)
    var mixed = render_triangles(
        faint,
        24,
        18,
        BACKGROUND,
        SHADE_TEXTURE,
        TextureStore(),
        Lighting.uniform(),
        FogView(no_fog()),
        REINHARD_TONE_MAPPING,
        1.0,
    )
    assert_true(count_mismatches(plain, mixed) > 50, "a real blend did nothing")
    # And over nothing at all it leaves the background, rather than writing
    # a transparent black where it found no contribution.
    var empty = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(sheet_over(0.05, 0.0), empty, SHADE_TEXTURE)
    var clear = empty.resolve()
    var device = render_triangles(
        sheet_over(0.05, 0.0), 24, 18, BACKGROUND, SHADE_TEXTURE
    )
    assert_equal(count_mismatches(clear, device), 0)
    assert_equal(device.get_pixel(12, 12).r, BACKGROUND.r)
    assert_equal(device.get_pixel(12, 12).a, UInt8(255))
    assert_equal(device.depth_at(12, 12), inf[DType.float32]())


# --- a highlight under a parallel projection, on both backends --------------


def test_both_backends_agree_on_a_parallel_view_highlight() raises:
    # A parallel projection sees every point of a flat sheet from one
    # direction, so the sheet reflects evenly. The kernel reads that
    # direction from the light buffer rather than working it out from the
    # camera's position, and must reach the same even highlight.
    if skipped_for_lack_of_a_gpu("both backends agree on a parallel highlight"):
        return
    var renderer = Renderer(32, 24)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER), 4, 4)
    )
    var shiny = assets.materials.add(
        phong_material(Color(0, 0, 0), NO_TEXTURE, Color(255, 255, 255), 30.0)
    )
    var scene = Scene()
    _ = scene.add(Object3D())
    var lamp = Object3D()
    lamp.set_position(0, 0, 5)
    var node = scene.add(lamp^)
    scene.add_light(directional_light(Color(255, 255, 255), node, 1.0))
    scene.update()
    var camera = centered(
        Length(6.0, METER),
        Float32(32) / Float32(24),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var meshes = List[Mesh]()
    meshes.append(Mesh(sheet, shiny, NodeId(0)))
    var corners = prepared(renderer, scene, assets, meshes, camera)
    assert_true(len(corners) > 0, "the sheet prepared no triangles")
    var lighting = Lighting(
        scene,
        camera.visible_layers(),
        camera_position(scene, camera),
        toward_camera(scene, camera),
    )
    var target = RenderTarget(32, 24, BACKGROUND)
    rasterize_all(corners, target, SHADE_TEXTURE, assets.textures, lighting)
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 32, 24, BACKGROUND, SHADE_TEXTURE, assets.textures, lighting
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # Even across the sheet on the device too, which is what says the
    # kernel read the direction rather than the camera's position.
    var middle = gpu.get_pixel(16, 12)
    assert_true(middle.r > 200, "the sheet caught no highlight")
    for y in range(4, 20):
        for x in range(6, 26):
            assert_true(
                _apart(gpu.get_pixel(x, y).r, middle.r) <= 1,
                "the device highlight is not even across a parallel view",
            )


# --- the whole phong path at once, through either kind of camera ------------


def a_masked_phong_frame[
    C: Camera
](camera: C, alpha_test: Float32) raises -> Int:
    """Draw an alpha-tested phong sheet through `camera` on both backends.

    A turned and tiled mask cuts the holes, a fog veils what survives and a
    curve compresses it. Asserts the two agree in color and in depth, and
    returns how many pixels a fragment claimed the depth of, so a caller
    can say the mask really cut something out.

    Args:
        camera: The camera to project through.
        alpha_test: The cutoff, or zero to keep every fragment.

    Returns:
        How many pixels the host claimed a depth for.

    Raises:
        Error: If the two backends disagree, or the sheet barely drew.
    """
    var renderer = Renderer(32, 24)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(4.0, METER), Length(4.0, METER), 6, 6)
    )
    var mask = checkerboard(
        16,
        4,
        Color(0, 255, 0),
        Color(0, 0, 0),
        REPEAT,
        NEAREST,
        LINEAR,
        False,
        IGNORED,
    )
    mask.repeat = Vector2(2, 1.5)
    mask.rotation = Angle(25.0, DEGREE)
    mask.center = Vector2(0.5, 0.5)
    mask.offset = Vector2(0.1, -0.2)
    var cut = assets.materials.add(
        Material(
            Color(200, 90, 60),
            kind=PHONG,
            alpha_map=assets.textures.add(mask^),
            alpha_test=alpha_test,
            specular=Color(255, 255, 255),
            shininess=40.0,
        )
    )
    var scene = Scene()
    var tilted = Object3D()
    tilted.set_euler(
        Angle(-25.0, DEGREE), Angle(15.0, DEGREE), Angle(0.0, DEGREE)
    )
    var node = scene.add(tilted^)
    light_the(scene)
    var bulb = Object3D()
    bulb.set_position(0.5, 1.0, 2.0)
    var bulb_node = scene.add(bulb^)
    scene.add_light(point_light(Color(255, 220, 180), bulb_node, 2.0))
    scene.fog = linear_fog(
        Color(160, 170, 190), Length(2.0, METER), Length(9.0, METER)
    )
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(Mesh(sheet, cut, node))
    var corners = prepared(renderer, scene, assets, meshes, camera)
    assert_true(len(corners) > 0, "the sheet prepared no triangles")
    var lighting = Lighting(
        scene,
        camera.visible_layers(),
        camera_position(scene, camera),
        toward_camera(scene, camera),
    )
    var view = FogView(scene.fog)
    var target = RenderTarget(32, 24, BACKGROUND)
    rasterize_all(
        corners, target, SHADE_TEXTURE, assets.textures, lighting, 1, view
    )
    var cpu = target.resolve(1, AGX_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        corners,
        32,
        24,
        BACKGROUND,
        SHADE_TEXTURE,
        assets.textures,
        lighting,
        view,
        AGX_TONE_MAPPING,
        1.0,
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # The depth agrees everywhere too, which is what says the late write
    # for a cut fragment happened on both.
    var claimed = 0
    for y in range(24):
        for x in range(32):
            var theirs = cpu.depth_at(x, y)
            if theirs > 1.0e30:
                assert_true(
                    gpu.depth_at(x, y) > 1.0e30,
                    "the kernel claimed a depth the host cut away",
                )
            else:
                claimed += 1
                assert_almost_equal(
                    gpu.depth_at(x, y), theirs, atol=Float64(1e-5)
                )
    return claimed


def test_both_backends_agree_on_a_masked_phong_frame() raises:
    # Every part of this change at once -- the highlight, the alpha map,
    # the cutoff and the late depth write -- through a fog and a curve, and
    # through both kinds of camera, because the highlight asks the
    # projection which direction the camera lies in.
    if skipped_for_lack_of_a_gpu("both backends agree on a masked phong frame"):
        return
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(32) / Float32(24),
        Length(0.5, METER),
        Length(12.0, METER),
    )
    camera.place(Vector3(0.6, 0.8, 3.4), Vector3(0, 0, 0))
    var cut = a_masked_phong_frame(camera, 0.5)
    var whole = a_masked_phong_frame(camera, 0.0)
    assert_true(cut > 50, "the masked sheet barely drew anything")
    assert_true(cut < whole, "the mask cut nothing out of the near view")
    # The same frame through a parallel projection.
    var flat = centered(
        Length(4.0, METER),
        Float32(32) / Float32(24),
        Length(0.1, METER),
        Length(12.0, METER),
    )
    flat.place(Vector3(0.6, 0.8, 3.4), Vector3(0, 0, 0))
    var parallel = a_masked_phong_frame(flat, 0.5)
    var full = a_masked_phong_frame(flat, 0.0)
    assert_true(parallel > 50, "the parallel sheet barely drew anything")
    assert_true(parallel < full, "the mask cut nothing out of the flat view")


# --- a toon material, both backends -----------------------------------------


def a_gpu_ramp(
    tones: List[UInt8],
    space: ColorSpace = LINEAR,
    alpha: Alpha = IGNORED,
) raises -> Texture:
    """Return a one-row gradient map whose red channel holds `tones`."""
    var pixels = List[UInt8]()
    for tone in tones:
        pixels.append(tone)
        pixels.append(255)
        pixels.append(0)
        pixels.append(255)
    return Texture(len(tones), 1, pixels^, REPEAT, NEAREST, space, False, alpha)


def toon_pair(gradient_map: TextureId = NO_TEXTURE) -> List[RasterVertex]:
    """Return `overlapping_pair` as toon surfaces, each corner facing a
    different way so the ramp is really swept across the triangles."""
    var normals: List[Vector3] = [
        Vector3(0, 0, 1),
        Vector3(0.9, 0, 0.4),
        Vector3(0, 0.9, -0.4),
        Vector3(-0.8, 0.2, 0.5),
        Vector3(0.3, -0.9, 0.1),
        Vector3(0, 0, -1),
    ]
    var corners = List[RasterVertex]()
    var base = overlapping_pair()
    for index in range(len(base)):
        var here = base[index]
        corners.append(
            RasterVertex(
                here.x,
                here.y,
                here.z,
                here.inv_w,
                here.color,
                here.u,
                here.v,
                here.texture,
                here.blend,
                normals[index],
                Vector3(Float32(index) * 0.2 - 0.5, Float32(index) * 0.1, 0.0),
                TOON,
                here.emissive,
                here.emissive_map,
                here.view_depth,
                NO_TEXTURE,
                0,
                FloatColor(0, 0, 0),
                0,
                gradient_map,
            )
        )
    return corners^


def test_both_backends_agree_on_the_fallback_toon_ramp() raises:
    # No gradient map, so both step through three.js's two tones from the
    # same shared function. The kernel must reach the same pixels.
    if skipped_for_lack_of_a_gpu("both backends agree on the toon fallback"):
        return
    var lighting = phong_lighting()
    var corners = toon_pair()
    var target = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(corners, target, SHADE_LIT, TextureStore(), lighting)
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 24, 18, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # And the ramp really stepped: the same surfaces as lambert ones differ.
    var plain = List[RasterVertex]()
    for here in toon_pair():
        plain.append(of_kind(here, LAMBERT, here.normal))
    var faded = render_triangles(
        plain, 24, 18, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    assert_true(count_mismatches(gpu, faded) > 50, "the ramp changed nothing")


def test_both_backends_read_the_same_tone_off_a_gradient_map() raises:
    # The host reads texel (x, 0) of the map and the kernel reads the same
    # byte of the same row, so a ramp of three tones cannot step at one
    # coordinate on one side and another on the other.
    if skipped_for_lack_of_a_gpu("both backends read the same toon ramp"):
        return
    var textures = TextureStore()
    var tones: List[UInt8] = [0, 96, 176, 255]
    var ramp = textures.add(a_gpu_ramp(tones))
    var lighting = phong_lighting()
    var corners = toon_pair(ramp)
    var target = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(corners, target, SHADE_LIT, textures, lighting)
    var cpu = target.resolve()
    var renderer = GpuRenderer(24, 18)
    renderer.set_textures(textures)
    renderer.draw(corners, BACKGROUND, SHADE_LIT, lighting)
    var gpu = renderer.read_back()
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # And the map really replaced the fallback: the same surfaces without
    # it differ, and reach no black.
    var fallback = render_triangles(
        toon_pair(), 24, 18, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    assert_true(
        count_mismatches(gpu, fallback) > 50, "the gradient map did nothing"
    )


def test_the_gpu_refuses_a_gradient_map_it_cannot_sample() raises:
    # The same three refusals the host makes before its first fragment,
    # made here before the launch, plus the one only the device can make.
    if skipped_for_lack_of_a_gpu("the gpu refuses a bad gradient map"):
        return
    var tones: List[UInt8] = [0, 255]
    var textures = TextureStore()
    var good = textures.add(a_gpu_ramp(tones))
    var colored = textures.add(a_gpu_ramp(tones, SRGB, IGNORED))
    var weighted = textures.add(a_gpu_ramp(tones, LINEAR, COVERAGE))
    var empty = textures.add(Texture())
    var renderer = GpuRenderer(16, 12)
    renderer.set_textures(textures)
    var target = RenderTarget(16, 12, BACKGROUND)
    for slot in [colored, weighted, empty]:
        with assert_raises():
            renderer.draw(toon_pair(slot), BACKGROUND, SHADE_LIT)
        with assert_raises():
            rasterize_all(toon_pair(slot), target, SHADE_LIT, textures)
    # A ramp stored as data draws on both, which is what makes the three
    # above about the storage.
    renderer.draw(toon_pair(good), BACKGROUND, SHADE_LIT)
    rasterize_all(toon_pair(good), target, SHADE_LIT, textures)
    # A ramp that was never uploaded is refused rather than read off the
    # end of the descriptor table.
    with assert_raises():
        renderer.draw(toon_pair(TextureId(9)), BACKGROUND, SHADE_LIT)


def test_both_backends_agree_on_a_prepared_toon_scene() raises:
    # A whole frame: a lit floor, a toon sphere on the fallback and a toon
    # box on a ramp of its own, through a fog and a curve.
    if skipped_for_lack_of_a_gpu("both backends agree on a toon scene"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var floor = assets.geometries.add(
        plane(Length(12.0, METER), Length(12.0, METER), 4, 4)
    )
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 16, 12))
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var tones: List[UInt8] = [0, 80, 160, 255]
    var ramp = assets.textures.add(a_gpu_ramp(tones))

    var scene = Scene()
    var ground = Object3D()
    ground.set_position(0, -1.0, 0)
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var left = Object3D()
    left.set_position(-1.0, 0, 0)
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(1.0, 0, -0.4)
    right.set_euler(
        Angle(20.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE)
    )
    var right_node = scene.add(right^)
    light_the(scene)
    var bulb = Object3D()
    bulb.set_position(0.5, 1.2, 1.5)
    var bulb_node = scene.add(bulb^)
    scene.add_light(point_light(Color(255, 220, 180), bulb_node, 2.0))
    scene.fog = linear_fog(
        Color(160, 170, 190), Length(3.0, METER), Length(12.0, METER)
    )
    scene.update()

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            floor,
            assets.materials.add(Material(Color(200, 200, 200))),
            ground_node,
        )
    )
    meshes.append(
        Mesh(
            ball,
            assets.materials.add(toon_material(Color(200, 60, 60))),
            left_node,
        )
    )
    meshes.append(
        Mesh(
            box,
            assets.materials.add(
                toon_material(Color(60, 120, 200), NO_TEXTURE, ramp)
            ),
            right_node,
        )
    )

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.5, METER),
        Length(12.0, METER),
    )
    camera.place(Vector3(0, 0.8, 3.2), Vector3(0, 0, 0))

    var corners = prepared(renderer, scene, assets, meshes, camera)
    assert_true(len(corners) > 0, "the scene prepared no triangles")
    var lighting = Lighting(
        scene, camera.visible_layers(), camera_position(scene, camera)
    )
    var view = FogView(scene.fog)
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_all(
        corners, target, SHADE_TEXTURE, assets.textures, lighting, 1, view
    )
    var cpu = target.resolve(1, ACES_FILMIC_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        corners,
        48,
        36,
        BACKGROUND,
        SHADE_TEXTURE,
        assets.textures,
        lighting,
        view,
        ACES_FILMIC_TONE_MAPPING,
        1.0,
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 300, "the scene barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


# --- morph targets, both backends -------------------------------------------


def test_both_backends_agree_on_a_morphed_mesh() raises:
    # A morph target moves vertices in `Renderer.prepare`, which is the one
    # place both backends read from, so the two are drawing the same
    # triangles by construction. This is what says so: the same scene worn
    # at a weight that is neither nothing nor everything, through both.
    if skipped_for_lack_of_a_gpu("both backends agree on a morphed mesh"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()

    var shape = cube(Length(1.0, METER))
    ref positions = shape.attribute_view(String(POSITION))
    var stretched = List[Float32]()
    for vertex in range(positions.count()):
        var point = positions.vector3(vertex)
        # A target that pulls the box out along x and up along y, so the
        # silhouette and the shading both change rather than just the size.
        stretched.append(point.x * 1.8)
        stretched.append(point.y + 0.4)
        stretched.append(point.z)
    shape.add_morph_target(BufferAttribute(stretched^, 3))
    var box = assets.geometries.add(shape^)

    var scene = Scene()
    var node = Object3D()
    node.set_euler(Angle(20.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE))
    var placed = scene.add(node^)
    var lamp = Object3D()
    lamp.set_position(2, 3, 4)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(60, 60, 60)))
    scene.add_light(directional_light(Color(220, 220, 220), lamp_node))
    scene.update()

    var meshes = List[Mesh]()
    var worn = Mesh(
        box, assets.materials.add(Material(Color(200, 120, 60))), placed
    )
    worn.set_morph_influence(0, 0.65)
    meshes.append(worn)

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.5, METER),
        Length(12.0, METER),
    )
    camera.place(Vector3(0, 0.6, 3.4), Vector3(0, 0, 0))

    var corners = prepared(renderer, scene, assets, meshes, camera)
    assert_true(len(corners) > 0, "the morphed scene prepared no triangles")
    var lighting = Lighting(
        scene, camera.visible_layers(), camera_position(scene, camera)
    )
    var view = FogView(scene.fog)
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_all(
        corners, target, SHADE_LIT, assets.textures, lighting, 1, view
    )
    var cpu = target.resolve(1, NO_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        corners,
        48,
        36,
        BACKGROUND,
        SHADE_LIT,
        assets.textures,
        lighting,
        view,
        NO_TONE_MAPPING,
        1.0,
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 200, "the morphed box barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


# --- skinning, both backends ------------------------------------------------


def test_both_backends_agree_on_a_posed_rig() raises:
    # Skinning happens in `prepare`, which both backends read from, so
    # neither rasterizer knows a bone exists. This says so: a two-bone rig
    # with the far bone turned, drawn through both.
    if skipped_for_lack_of_a_gpu("both backends agree on a posed rig"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()

    # A tall box, split top and bottom between two bones so the turn bends
    # it rather than carrying it whole.
    var shape = cube(Length(1.2, METER))
    ref points = shape.attribute_view(String(POSITION))
    var named = List[Float32]()
    var shares = List[Float32]()
    for vertex in range(points.count()):
        var point = points.vector3(vertex)
        named.append(0)
        named.append(1)
        named.append(0)
        named.append(0)
        # Everything above the middle leans on the second bone.
        var upper = Float32(0.5) + point.y / Float32(1.2)
        if upper < 0:
            upper = 0
        if upper > 1:
            upper = 1
        shares.append(1 - upper)
        shares.append(upper)
        shares.append(0)
        shares.append(0)
    shape.set_attribute(String(SKIN_INDEX), BufferAttribute(named^, 4))
    shape.set_attribute(String(SKIN_WEIGHT), BufferAttribute(shares^, 4))
    var box = assets.geometries.add(shape^)

    var scene = Scene()
    var body = Object3D()
    var body_node = scene.add(body^)
    var root = Object3D()
    root.set_position(0, -0.5, 0)
    var root_node = scene.add(root^)
    var tip = Object3D()
    tip.set_position(0, 0.5, 0)
    var tip_node = scene.add(tip^)
    var lamp = Object3D()
    lamp.set_position(2, 3, 4)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(60, 60, 60)))
    scene.add_light(directional_light(Color(220, 220, 220), lamp_node))
    scene.update()

    var bones: List[NodeId] = [root_node, tip_node]
    var placed = List[Matrix4]()
    for index in range(len(bones)):
        placed.append(scene.world_matrix(bones[index]))
    var skeleton = bind_skeleton(bones, placed)
    scene.add_skinned_mesh(
        SkinnedMesh(
            box,
            assets.materials.add(Material(Color(200, 120, 60))),
            body_node,
            skeleton^,
        )
    )
    # Bend the top bone over, which is what the upper vertices follow.
    scene.node(tip_node).set_euler(
        Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(40.0, DEGREE)
    )
    scene.update()

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.5, METER),
        Length(12.0, METER),
    )
    # Off the axis, so several faces of the box show and the bend is
    # visible rather than edge on.
    camera.place(Vector3(1.8, 1.1, 2.4), Vector3(0, 0, 0))

    var corners = renderer.prepare(scene, assets, camera)
    assert_true(len(corners) > 0, "the rig prepared no triangles")
    var lighting = Lighting(
        scene, camera.visible_layers(), camera_position(scene, camera)
    )
    var view = FogView(scene.fog)
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_all(
        corners, target, SHADE_LIT, assets.textures, lighting, 1, view
    )
    var cpu = target.resolve(1, NO_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        corners,
        48,
        36,
        BACKGROUND,
        SHADE_LIT,
        assets.textures,
        lighting,
        view,
        NO_TONE_MAPPING,
        1.0,
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 300, "the rig barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


# --- lines, both backends ---------------------------------------------------


def a_line(
    ax: Float32,
    ay: Float32,
    bx: Float32,
    by: Float32,
    z: Float32,
    color: Color,
    blend: Blending = OPAQUE,
) raises -> List[RasterVertex]:
    """Return one segment's two ends, unlit as a line must be."""
    return [
        RasterVertex(
            ax,
            ay,
            z,
            1,
            FloatColor(srgb=color),
            0,
            0,
            NO_TEXTURE,
            blend,
            kind=BASIC,
        ),
        RasterVertex(
            bx,
            by,
            z,
            1,
            FloatColor(srgb=color),
            0,
            0,
            NO_TEXTURE,
            blend,
            kind=BASIC,
        ),
    ]


def test_both_backends_draw_the_same_staircase() raises:
    # The rule lives in `render.linerule` and the two loops are shaped
    # differently: the host walks the line, the kernel asks each pixel
    # whether the line lights it. This is what says they agree.
    if skipped_for_lack_of_a_gpu("both backends draw the same staircase"):
        return
    var lines = List[RasterVertex]()
    # Flat, upright, diagonal, shallow, steep, and two drawn backwards, on
    # ends that are not on pixel centers.
    for segment in [
        a_line(2.0, 2.0, 44.0, 2.0, 0.5, Color(255, 255, 255)),
        a_line(2.0, 4.0, 2.0, 33.0, 0.5, Color(255, 0, 0)),
        a_line(3.3, 6.7, 40.1, 30.2, 0.5, Color(0, 255, 0)),
        a_line(44.0, 8.0, 4.0, 12.0, 0.5, Color(0, 0, 255)),
        a_line(30.0, 34.0, 36.0, 3.0, 0.5, Color(255, 255, 0)),
        a_line(10.5, 30.5, 10.5, 30.5, 0.5, Color(0, 255, 255)),
    ]:
        for corner in segment:
            lines.append(corner)

    var empty = List[RasterVertex]()
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_lines_all(lines, target, 1, FogView.none())
    var cpu = target.resolve(1, NO_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        empty,
        48,
        36,
        BACKGROUND,
        SHADE_LIT,
        TextureStore(),
        Lighting.uniform(),
        FogView.none(),
        NO_TONE_MAPPING,
        1.0,
        lines,
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 100, "the lines barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def test_both_backends_put_lines_over_the_same_surface() raises:
    # A line has to test its depth against the triangles, and a blended one
    # has to mix with what they left. Both passes run in one kernel for
    # that reason, in the order the host draws them.
    if skipped_for_lack_of_a_gpu("both backends put lines over a surface"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var floor = assets.geometries.add(
        plane(Length(4.0, METER), Length(4.0, METER), 2, 2)
    )
    var scene = Scene()
    var node = Object3D()
    node.set_euler(Angle(-60.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE))
    var placed = scene.add(node^)
    scene.add_light(ambient_light(Color(200, 200, 200)))
    scene.update()
    var meshes = List[Mesh]()
    meshes.append(
        Mesh(floor, assets.materials.add(Material(Color(90, 90, 120))), placed)
    )
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.5, METER),
        Length(12.0, METER),
    )
    camera.place(Vector3(0, 0.5, 4.0), Vector3(0, 0, 0))
    var corners = prepared(renderer, scene, assets, meshes, camera)

    var lines = List[RasterVertex]()
    # One in front of the floor, one behind it, and one blended over it.
    for segment in [
        a_line(4.0, 6.0, 44.0, 30.0, 0.2, Color(255, 240, 120)),
        a_line(4.0, 30.0, 44.0, 6.0, 0.95, Color(255, 0, 0)),
        a_line(6.0, 18.0, 42.0, 18.0, 0.25, Color(0, 255, 255), BLEND),
    ]:
        for corner in segment:
            lines.append(corner)

    var lighting = Lighting(
        scene, camera.visible_layers(), camera_position(scene, camera)
    )
    var view = FogView(scene.fog)
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_all(
        corners, target, SHADE_LIT, assets.textures, lighting, 1, view
    )
    rasterize_lines_all(lines, target, 1, view)
    var cpu = target.resolve(1, NO_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        corners,
        48,
        36,
        BACKGROUND,
        SHADE_LIT,
        assets.textures,
        lighting,
        view,
        NO_TONE_MAPPING,
        1.0,
        lines,
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


# --- a matcap material, both backends ---------------------------------------


def a_gpu_matcap(
    left: Color, right: Color, alpha: Alpha = IGNORED
) raises -> Texture:
    """Return a two-texel matcap: `left` on the left, `right` on the
    right."""
    var pixels = List[UInt8]()
    for tint in [left, right]:
        pixels.append(tint.r)
        pixels.append(tint.g)
        pixels.append(tint.b)
        pixels.append(255)
    return Texture(2, 1, pixels^, CLAMP, NEAREST, SRGB, False, alpha)


def matcap_pair(matcap: TextureId = NO_TEXTURE) -> List[RasterVertex]:
    """Return `overlapping_pair` as matcap surfaces, each corner facing a
    different way so the lookup really sweeps the image."""
    var normals: List[Vector3] = [
        Vector3(0, 0, 1),
        Vector3(0.9, 0, 0.4),
        Vector3(0, 0.9, -0.4),
        Vector3(-0.8, 0.2, 0.5),
        Vector3(0.3, -0.9, 0.1),
        Vector3(0, -0.6, 0.8),
    ]
    var corners = List[RasterVertex]()
    var base = overlapping_pair()
    for index in range(len(base)):
        var here = base[index]
        corners.append(
            RasterVertex(
                here.x,
                here.y,
                here.z,
                here.inv_w,
                # White, because a matcap multiplies the surface color:
                # a green corner under a red image would show neither.
                FloatColor(1, 1, 1),
                here.u,
                here.v,
                here.texture,
                here.blend,
                normals[index],
                Vector3(Float32(index) * 0.2 - 0.5, Float32(index) * 0.1, 0.0),
                MATCAP,
                here.emissive,
                here.emissive_map,
                here.view_depth,
                NO_TEXTURE,
                0,
                FloatColor(0, 0, 0),
                0,
                NO_TEXTURE,
                matcap,
            )
        )
    return corners^


def watching() raises -> Lighting:
    """Return lighting with a camera off to one side and no lights, so
    nothing but the matcap decides a pixel."""
    return Lighting(Scene(), Layers.all(), Vector3(0.4, 0.3, 3.0))


def test_both_backends_look_a_matcap_up_in_the_same_place() raises:
    # The frame comes from the same shared function on both sides, and the
    # image is read at the same level, so the two must reach the same
    # texels.
    if skipped_for_lack_of_a_gpu("both backends look a matcap up alike"):
        return
    var textures = TextureStore()
    var ball = textures.add(
        a_gpu_matcap(Color(255, 40, 40), Color(40, 40, 255))
    )
    var lighting = watching()
    var corners = matcap_pair(ball)
    var target = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(corners, target, SHADE_LIT, textures, lighting)
    var cpu = target.resolve()
    var renderer = GpuRenderer(24, 18)
    renderer.set_textures(textures)
    renderer.draw(corners, BACKGROUND, SHADE_LIT, lighting)
    var gpu = renderer.read_back()
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # Both halves of the image really arrived, so the lookup swept it.
    var reds = 0
    var blues = 0
    for y in range(18):
        for x in range(24):
            var here = gpu.get_pixel(x, y)
            if here.r > 200:
                reds += 1
            elif here.b > 200:
                blues += 1
    assert_true(reds > 20 and blues > 20, "the lookup did not sweep the image")


def test_both_backends_agree_on_the_fallback_matcap() raises:
    # No image, so both take three.js's gray gradient from the same shared
    # function.
    if skipped_for_lack_of_a_gpu("both backends agree on the matcap gradient"):
        return
    var lighting = watching()
    var corners = matcap_pair()
    var target = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(corners, target, SHADE_LIT, TextureStore(), lighting)
    var cpu = target.resolve()
    var gpu = render_triangles(
        corners, 24, 18, BACKGROUND, SHADE_LIT, TextureStore(), lighting
    )
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # And it is a gradient, not one flat gray: the corners face different
    # ways, so the lookup reaches different heights.
    var low = UInt8(255)
    var high = UInt8(0)
    for y in range(18):
        for x in range(24):
            var here = gpu.get_pixel(x, y)
            if here.r == BACKGROUND.r and here.g == BACKGROUND.g:
                continue
            if here.r < low:
                low = here.r
            if here.r > high:
                high = here.r
    assert_true(high > low + 8, "the fallback matcap was flat")


def test_the_gpu_refuses_a_matcap_it_cannot_sample() raises:
    if skipped_for_lack_of_a_gpu("the gpu refuses a bad matcap"):
        return
    var textures = TextureStore()
    var good = textures.add(a_gpu_matcap(Color(255, 0, 0), Color(0, 0, 255)))
    var weighted = textures.add(
        a_gpu_matcap(Color(255, 0, 0), Color(0, 0, 255), COVERAGE)
    )
    var renderer = GpuRenderer(16, 12)
    renderer.set_textures(textures)
    var target = RenderTarget(16, 12, BACKGROUND)
    with assert_raises():
        renderer.draw(matcap_pair(weighted), BACKGROUND, SHADE_LIT)
    with assert_raises():
        rasterize_all(matcap_pair(weighted), target, SHADE_LIT, textures)
    # One that ignores its alpha draws on both.
    renderer.draw(matcap_pair(good), BACKGROUND, SHADE_LIT)
    rasterize_all(matcap_pair(good), target, SHADE_LIT, textures)
    # And one that was never uploaded is refused rather than read off the
    # end of the descriptor table.
    with assert_raises():
        renderer.draw(matcap_pair(TextureId(9)), BACKGROUND, SHADE_LIT)


def test_both_backends_agree_on_a_prepared_matcap_scene() raises:
    # A whole frame: a lit floor, a matcap sphere on an image and a matcap
    # box on the gradient, through a fog and a curve.
    if skipped_for_lack_of_a_gpu("both backends agree on a matcap scene"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var floor = assets.geometries.add(
        plane(Length(12.0, METER), Length(12.0, METER), 4, 4)
    )
    var ball = assets.geometries.add(sphere(Length(0.7, METER), 16, 12))
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var image = assets.textures.add(
        a_gpu_matcap(Color(255, 190, 120), Color(40, 60, 110))
    )

    var scene = Scene()
    var ground = Object3D()
    ground.set_position(0, -1.0, 0)
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var left = Object3D()
    left.set_position(-1.0, 0, 0)
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(1.0, 0, -0.4)
    right.set_euler(
        Angle(20.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE)
    )
    var right_node = scene.add(right^)
    light_the(scene)
    scene.fog = linear_fog(
        Color(160, 170, 190), Length(3.0, METER), Length(12.0, METER)
    )
    scene.update()

    var meshes = List[Mesh]()
    meshes.append(
        Mesh(
            floor,
            assets.materials.add(Material(Color(200, 200, 200))),
            ground_node,
        )
    )
    meshes.append(
        Mesh(ball, assets.materials.add(matcap_material(image)), left_node)
    )
    meshes.append(
        Mesh(box, assets.materials.add(matcap_material()), right_node)
    )

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.5, METER),
        Length(12.0, METER),
    )
    camera.place(Vector3(0, 0.8, 3.2), Vector3(0, 0, 0))

    var corners = prepared(renderer, scene, assets, meshes, camera)
    assert_true(len(corners) > 0, "the scene prepared no triangles")
    var lighting = Lighting(
        scene,
        camera.visible_layers(),
        camera_position(scene, camera),
        toward_camera(scene, camera),
        camera_up(scene, camera),
    )
    var view = FogView(scene.fog)
    var target = RenderTarget(48, 36, BACKGROUND)
    rasterize_all(
        corners, target, SHADE_TEXTURE, assets.textures, lighting, 1, view
    )
    var cpu = target.resolve(1, ACES_FILMIC_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        corners,
        48,
        36,
        BACKGROUND,
        SHADE_TEXTURE,
        assets.textures,
        lighting,
        view,
        ACES_FILMIC_TONE_MAPPING,
        1.0,
    )
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 300, "the scene barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


# --- the same two contracts, on the device ----------------------------------


def a_tall_gpu_ramp(tones: List[UInt8]) raises -> Texture:
    """Return a two-row gradient map, which both backends refuse."""
    var pixels = List[UInt8]()
    for tone in tones:
        pixels.append(tone)
        pixels.append(255)
        pixels.append(0)
        pixels.append(255)
    for _ in tones:
        pixels.append(17)
        pixels.append(17)
        pixels.append(17)
        pixels.append(255)
    return Texture(
        len(tones), 2, pixels^, REPEAT, NEAREST, LINEAR, False, IGNORED
    )


def test_both_backends_refuse_a_ramp_taller_than_one_row() raises:
    # A `v` of zero is the bottom row here and the first stored row in
    # three.js, so a taller ramp has two defensible readings. Both backends
    # refuse it rather than each picking one.
    if skipped_for_lack_of_a_gpu("both backends refuse a tall ramp"):
        return
    var tones: List[UInt8] = [0, 255]
    var textures = TextureStore()
    var flat = textures.add(a_gpu_ramp(tones))
    var tall = textures.add(a_tall_gpu_ramp(tones))
    var renderer = GpuRenderer(16, 12)
    renderer.set_textures(textures)
    var target = RenderTarget(16, 12, BACKGROUND)
    with assert_raises():
        renderer.draw(toon_pair(tall), BACKGROUND, SHADE_LIT)
    with assert_raises():
        rasterize_all(toon_pair(tall), target, SHADE_LIT, textures)
    # One row draws on both, which is what makes the refusal about height.
    renderer.draw(toon_pair(flat), BACKGROUND, SHADE_LIT)
    rasterize_all(toon_pair(flat), target, SHADE_LIT, textures)


def test_both_backends_refuse_data_beside_a_blend_under_a_curve() raises:
    # The host asks this before it draws and the device before it launches,
    # from the same function, because a kernel cannot raise part way
    # through a frame. See `check_output_kinds`.
    if skipped_for_lack_of_a_gpu("both backends refuse a mixed curve frame"):
        return
    var mixed = data_pair(NORMALS)
    for here in sheet_over(0.05, 0.5):
        mixed.append(here)
    var renderer = GpuRenderer(24, 18)
    var target = RenderTarget(24, 18, BACKGROUND)
    with assert_raises():
        renderer.draw(
            mixed,
            BACKGROUND,
            SHADE_TEXTURE,
            Lighting.uniform(),
            FogView(no_fog()),
            REINHARD_TONE_MAPPING,
            1.0,
        )
    with assert_raises():
        check_output_kinds(mixed, True)
    # With no curve the same frame draws on the device, as it always did.
    renderer.draw(mixed, BACKGROUND, SHADE_TEXTURE)
    # And the uv view is data throughout, so it is never refused.
    renderer.draw(
        mixed,
        BACKGROUND,
        SHADE_UV,
        Lighting.uniform(),
        FogView(no_fog()),
        REINHARD_TONE_MAPPING,
        1.0,
    )
    _ = target


def a_four_corner_matcap() raises -> Texture:
    """Return a two-by-two matcap, a different color in every quadrant."""
    var pixels = List[UInt8]()
    var corners: List[Color] = [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 0),
    ]
    for tint in corners:
        pixels.append(tint.r)
        pixels.append(tint.g)
        pixels.append(tint.b)
        pixels.append(255)
    return Texture(2, 2, pixels^, CLAMP, NEAREST, SRGB, False, IGNORED)


def test_both_backends_orient_a_matcap_the_same_way() raises:
    # A two-texel image only pins left against right. Four quadrants pin the
    # other axis, so a flipped `v` on one backend alone would show here.
    if skipped_for_lack_of_a_gpu("both backends orient a matcap alike"):
        return
    var textures = TextureStore()
    var ball = textures.add(a_four_corner_matcap())
    var lighting = watching()
    var corners = matcap_pair(ball)
    var target = RenderTarget(24, 18, BACKGROUND)
    rasterize_all(corners, target, SHADE_LIT, textures, lighting)
    var cpu = target.resolve()
    var renderer = GpuRenderer(24, 18)
    renderer.set_textures(textures)
    renderer.draw(corners, BACKGROUND, SHADE_LIT, lighting)
    var gpu = renderer.read_back()
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)
    # Three of the four quadrants at least reached the image, or the
    # normals never swept it and the comparison proves nothing.
    var seen = 0
    for want in [
        Color(255, 0, 0),
        Color(0, 255, 0),
        Color(0, 0, 255),
        Color(255, 255, 0),
    ]:
        var found = False
        for y in range(18):
            for x in range(24):
                var here = gpu.get_pixel(x, y)
                if (
                    _apart(here.r, want.r) < 40
                    and _apart(here.g, want.g) < 40
                    and _apart(here.b, want.b) < 40
                ):
                    found = True
        if found:
            seen += 1
    assert_true(seen >= 3, "the lookup did not sweep the image")


def test_both_backends_agree_on_a_scene_with_lines_in_it() raises:
    # The whole path, not hand-built corners: one scene, one camera, and
    # both halves of the renderer reading what `prepare` and
    # `prepare_lines` produce. A line drawn over a lit box is where the
    # two passes have to meet, because the segment tests the depth the
    # triangles wrote.
    if skipped_for_lack_of_a_gpu("both backends agree on a scene with lines"):
        return
    var renderer = Renderer(48, 36)
    renderer.set_background(BACKGROUND)
    var assets = Assets()
    var box = assets.geometries.add(cube(Length(1.2, METER)))
    var paint = assets.materials.add(Material(Color(60, 120, 220)))
    var outline = BufferGeometry()
    outline.set_attribute(
        String(POSITION),
        BufferAttribute(
            [
                Float32(-0.9),
                -0.7,
                0.9,
                0.9,
                -0.7,
                0.9,
                0.8,
                0.75,
                0.9,
                -0.85,
                0.6,
                0.9,
            ],
            3,
        ),
    )
    var ring = assets.geometries.add(outline^)
    var ink = assets.materials.add(Material(Color(255, 210, 0), kind=BASIC))
    var scene = Scene()
    var root = scene.add(Object3D())
    light_the(scene)
    scene.update()
    scene.add_mesh(Mesh(box, paint, root))
    scene.add_line(Line(ring, ink, root, mode=LOOP))
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.4, 3.2), Vector3(0, 0, 0))
    var corners = renderer.prepare(scene, assets, camera)
    var segments = renderer.prepare_lines(scene, assets, camera)
    assert_equal(len(segments), 8)
    var cpu = renderer.render(scene, assets, camera)
    var gpu = render_triangles(
        corners,
        48,
        36,
        BACKGROUND,
        SHADE_LIT,
        assets.textures,
        Lighting(scene),
        FogView(scene.fog),
        NO_TONE_MAPPING,
        1.0,
        segments,
    )
    # The line is really on top of the box, not beside it.
    var ink_pixels = 0
    for y in range(36):
        for x in range(48):
            var pixel = cpu.get_pixel(x, y)
            if pixel.r > 200 and pixel.g > 150 and pixel.b < 100:
                ink_pixels += 1
    assert_true(ink_pixels > 20, "the outline barely drew anything")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def a_varying_line(
    ax: Float32,
    bx: Float32,
    near: FloatColor,
    far: FloatColor,
    near_inv_w: Float32 = 1,
    far_inv_w: Float32 = 1,
    depth: Float32 = 0,
    blend: Blending = OPAQUE,
) raises -> List[RasterVertex]:
    """Return one flat segment whose two ends differ in color and in w.

    `a_line` gives both ends one color, which is exactly the case that
    cannot tell one interpolation convention from another.
    """
    return [
        RasterVertex(
            ax,
            8.5,
            0.5,
            near_inv_w,
            near,
            0,
            0,
            NO_TEXTURE,
            blend,
            kind=BASIC,
            view_depth=depth,
        ),
        RasterVertex(
            bx,
            8.5,
            0.5,
            far_inv_w,
            far,
            0,
            0,
            NO_TEXTURE,
            blend,
            kind=BASIC,
            view_depth=depth,
        ),
    ]


def test_both_backends_veil_a_line_with_the_same_fog() raises:
    # The kernel used to read the fog buffer by literal slot, which took
    # the color out of the near, far and density lanes: a white line in
    # black fog came back yellow. Its own test because a parity test on a
    # scene with no fog cannot see it, and one with gray fog barely can.
    if skipped_for_lack_of_a_gpu("both backends veil a line with one fog"):
        return
    var lines = a_varying_line(
        2.5,
        13.5,
        FloatColor(1, 1, 1),
        FloatColor(1, 1, 1),
        depth=2.0,
    )
    var view = FogView(
        linear_fog(Color(0, 0, 0), Length(1.0, METER), Length(3.0, METER))
    )
    var target = RenderTarget(16, 16, BACKGROUND)
    rasterize_lines_all(lines, target, 1, view)
    var cpu = target.resolve(1, NO_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        List[RasterVertex](),
        16,
        16,
        BACKGROUND,
        SHADE_LIT,
        TextureStore(),
        Lighting.uniform(),
        view,
        NO_TONE_MAPPING,
        1.0,
        lines,
    )
    # Halfway through a one-to-three fog, so half the white survives over
    # black. The number is here so that a change of convention has to be
    # deliberate rather than merely agreed on by both backends.
    var painted = cpu.get_pixel(8, 8)
    assert_equal(Int(painted.r), 188)
    assert_equal(Int(painted.g), 188)
    assert_equal(Int(painted.b), 188)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_both_backends_interpolate_a_line_color_the_same_way() raises:
    # Ends that differ in color and in alpha, with unequal w, which is the
    # only case that tells a straight interpolation from a premultiplied
    # one. The host used to premultiply and the kernel never did.
    if skipped_for_lack_of_a_gpu("both backends interpolate a line alike"):
        return
    var lines = a_varying_line(
        2.5,
        13.5,
        FloatColor(1, 0, 0, 0),
        FloatColor(0, 0, 1, 1),
        near_inv_w=1,
        far_inv_w=3,
        blend=BLEND,
    )
    var target = RenderTarget(16, 16, BACKGROUND)
    rasterize_lines_all(lines, target, 1, FogView.none())
    var cpu = target.resolve(1, NO_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        List[RasterVertex](),
        16,
        16,
        BACKGROUND,
        SHADE_LIT,
        TextureStore(),
        Lighting.uniform(),
        FogView.none(),
        NO_TONE_MAPPING,
        1.0,
        lines,
    )
    # The transparent red still lends its red, which is what a varying
    # does and what premultiplying would have thrown away.
    var reds = 0
    for x in range(16):
        if cpu.get_pixel(x, 8).r > 40:
            reds += 1
    assert_true(reds > 0, "the transparent end lent no color")
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def a_dashed_line(
    dash: Float32,
    gap: Float32,
    near_inv_w: Float32 = 1,
    far_inv_w: Float32 = 1,
    z: Float32 = 0.5,
) raises -> List[RasterVertex]:
    """Return one flat segment across the image, sixteen units long along
    itself, dashed."""
    return [
        RasterVertex(
            0,
            8.5,
            z,
            near_inv_w,
            FloatColor(1, 1, 1),
            0,
            0,
            NO_TEXTURE,
            OPAQUE,
            kind=BASIC,
            line_distance=0,
            dash_size=dash,
            gap_size=gap,
        ),
        RasterVertex(
            16,
            8.5,
            z,
            far_inv_w,
            FloatColor(1, 1, 1),
            0,
            0,
            NO_TEXTURE,
            OPAQUE,
            kind=BASIC,
            line_distance=16,
            dash_size=dash,
            gap_size=gap,
        ),
    ]


def test_both_backends_dash_a_line_the_same_way() raises:
    # A dash of four and a gap of four across sixteen columns, with the
    # near end three times as close, so the fold is asked of a
    # perspective-corrected distance on both sides. Then a solid line
    # behind it, which shows through the gaps on both sides: a gap
    # claims no depth on either.
    if skipped_for_lack_of_a_gpu("both backends dash a line alike"):
        return
    var lines = a_dashed_line(4, 4, near_inv_w=3, far_inv_w=1, z=0.2)
    var behind = a_varying_line(
        0, 16, FloatColor(0, 0, 1, 1), FloatColor(0, 0, 1, 1), depth=0
    )
    lines.append(
        RasterVertex(
            behind[0].x,
            behind[0].y,
            0.6,
            1,
            behind[0].color,
            0,
            0,
            NO_TEXTURE,
            OPAQUE,
            kind=BASIC,
        )
    )
    lines.append(
        RasterVertex(
            behind[1].x,
            behind[1].y,
            0.6,
            1,
            behind[1].color,
            0,
            0,
            NO_TEXTURE,
            OPAQUE,
            kind=BASIC,
        )
    )
    var target = RenderTarget(16, 16, BACKGROUND)
    rasterize_lines_all(lines, target, 1, FogView.none())
    var cpu = target.resolve(1, NO_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        List[RasterVertex](),
        16,
        16,
        BACKGROUND,
        SHADE_LIT,
        TextureStore(),
        Lighting.uniform(),
        FogView.none(),
        NO_TONE_MAPPING,
        1.0,
        lines,
    )
    # Some of the row is white dash and some is the blue line behind, and
    # nothing in it is the background.
    var white = 0
    var blue = 0
    for x in range(16):
        var pixel = cpu.get_pixel(x, 8)
        if pixel.r > 200:
            white += 1
        elif pixel.b > 200:
            blue += 1
    assert_true(white > 0, "no dash was drawn")
    assert_true(blue > 0, "no gap let the line behind show")
    assert_equal(white + blue, 16)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_both_backends_show_a_line_the_same_way_in_the_uv_view() raises:
    # A line carries light, not coordinates, and the uv view has to encode
    # it like any other light. The kernel used to quantize the whole frame
    # instead, which showed the line's linear value as a byte.
    if skipped_for_lack_of_a_gpu("both backends show a line in the uv view"):
        return
    var gray = Color(128, 128, 128)
    var lines = a_varying_line(
        2.5, 13.5, FloatColor(srgb=gray), FloatColor(srgb=gray)
    )
    var target = RenderTarget(16, 16, BACKGROUND)
    rasterize_lines_all(lines, target, 1, FogView.none())
    var cpu = target.resolve(1, NO_TONE_MAPPING, 1.0)
    var gpu = render_triangles(
        List[RasterVertex](),
        16,
        16,
        BACKGROUND,
        SHADE_UV,
        TextureStore(),
        Lighting.uniform(),
        FogView.none(),
        NO_TONE_MAPPING,
        1.0,
        lines,
    )
    assert_equal(Int(cpu.get_pixel(8, 8).r), 128)
    assert_equal(count_mismatches(cpu, gpu), 0)


def test_a_second_upload_describes_its_own_textures() raises:
    # `set_textures` replaces the store, so every list that describes it is
    # replaced. The heights were appended to instead, so a second upload
    # validated its gradient maps against the first upload's rows.
    if skipped_for_lack_of_a_gpu("a second upload describes its own textures"):
        return
    var renderer = GpuRenderer(36, 30)
    var tones: List[UInt8] = [0, 255]
    var tall = TextureStore()
    _ = tall.add(a_tall_gpu_ramp(tones))
    renderer.set_textures(tall)
    # The same id, now a one-row ramp, which is the only shape a gradient
    # map is allowed. It has to be judged on its own rows.
    var flat = TextureStore()
    _ = flat.add(a_gpu_ramp(tones))
    renderer.set_textures(flat)
    renderer.draw(
        toon_pair(TextureId(0)), BACKGROUND, SHADE_LIT, Lighting.uniform()
    )
    assert_equal(renderer.read_back().width, 36)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
