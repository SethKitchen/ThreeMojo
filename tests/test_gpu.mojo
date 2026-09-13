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

from cameras.perspective_camera import PerspectiveCamera
from core.geometry_store import GeometryStore
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.sphere import sphere
from math.vector2 import Vector2
from std.math import inf
from math.vector3 import Vector3
from objects.mesh import Mesh
from renderers.renderer import Renderer
from units.si import Angle, DEGREE, Length, METRE
from render.framebuffer import Color, FloatColor, Framebuffer
from render.gpu import (
    GpuRenderer,
    available,
    flatten,
    pack,
    render,
    render_triangles,
)
from render.rasterizer import (
    RasterVertex,
    Triangle,
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

comptime BACKGROUND = Color(20, 24, 32)
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
    zero. What a covered pixel is *coloured* is floating point, and there the
    two cannot be held to the last bit: a GPU contracts `a * b + c` into a
    fused multiply-add, which rounds once instead of twice, so an interpolated
    channel can land one ULP either side of the CPU's value. That is
    invisible until the exact result sits on a rounding midpoint, which is
    where it was first seen — a sphere's ambient green of 190 * 0.25 = 47.5,
    quantizing to 48 on one and 47 on the other.

    So tests that interpolate real shading allow one level, and say so. A
    tolerance wide enough to hide a genuine disagreement would defeat the
    point; one level cannot hide a wrong colour, a wrong depth or a wrong
    pixel.

    Args:
        left: First image.
        right: Second image.
        tolerance: How many levels a channel may differ by and still count as
            a match. Zero, unless the test interpolates colour.

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
    """Return how many pixels hold the foreground colour.

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
    x: Float32, y: Float32, z: Float32, inv_w: Float32, color: Color
) -> RasterVertex:
    """Return a raster vertex, for building test triangles."""
    return RasterVertex(x, y, z, inv_w, FloatColor(of=color))


def cpu_render_triangles(
    corners: List[RasterVertex], width: Int, height: Int
) raises -> Framebuffer:
    """Return the CPU rasterizer's output for the same prepared triangles.

    Args:
        corners: Raster vertices, three per triangle.
        width: Image width.
        height: Image height.

    Returns:
        The rendered framebuffer.

    Raises:
        Error: If the dimensions are invalid.
    """
    var target = Framebuffer(width, height, BACKGROUND)
    for index in range(len(corners) // 3):
        rasterize_shaded(
            corners[index * 3],
            corners[index * 3 + 1],
            corners[index * 3 + 2],
            target,
        )
    return target^


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
    # Both colours are visible, so the overlap really is partial.
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


def test_flattening_lays_out_eight_floats_per_vertex() raises:
    # The host side of the kernel's unpacking. If these disagree the image is
    # garbage, so the layout is asserted rather than assumed.
    var corners = List[RasterVertex]()
    corners.append(corner(1, 2, 3, 4, Color(255, 128, 0, 64)))
    var flat = flatten(corners)
    assert_equal(len(flat), 8)
    assert_equal(flat[0], Float32(1))
    assert_equal(flat[1], Float32(2))
    assert_equal(flat[2], Float32(3))
    assert_equal(flat[3], Float32(4))
    assert_equal(flat[4], Float32(1.0))
    assert_almost_equal(flat[5], Float32(128) / 255, atol=Float64(1e-6))
    assert_equal(flat[6], Float32(0))
    assert_almost_equal(flat[7], Float32(64) / 255, atol=Float64(1e-6))


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

    var geometries = GeometryStore()
    var box = geometries.add(cube(Length(1.0, METRE)))
    var ball = geometries.add(sphere(Length(0.7, METRE), 12, 8))

    var scene = Scene()
    var left = Object3D()
    left.set_position(-0.9, 0, 0)
    left.set_euler(Angle(25.0, DEGREE), Angle(35.0, DEGREE), Angle(0.0, DEGREE))
    var left_node = scene.add(left^)
    var right = Object3D()
    right.set_position(0.9, 0, 0.4)
    var right_node = scene.add(right^)
    scene.update()

    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE),
        Float32(48) / Float32(36),
        Length(0.1, METRE),
        Length(100.0, METRE),
    )
    camera.place(Vector3(0, 0.6, 3.0), Vector3(0, 0, 0))

    var meshes = List[Mesh]()
    meshes.append(Mesh(box, Color(255, 140, 40), left_node))
    meshes.append(Mesh(ball, Color(90, 190, 255), right_node))

    # Prepared once, filled twice.
    var corners = renderer.prepare(scene, geometries, meshes, camera)
    assert_true(len(corners) > 0, "the scene prepared no triangles")
    assert_equal(len(corners) % 3, 0)

    var cpu = renderer.render(scene, geometries, meshes, camera)
    var gpu = render_triangles(corners, 48, 36, BACKGROUND)

    # A real image: both meshes visible, and plenty of background left.
    var drawn = 48 * 36 - count_background(cpu, BACKGROUND)
    assert_true(drawn > 100, "the scene barely drew anything")
    assert_true(drawn < 48 * 36, "the scene filled the whole image")
    # One level of tolerance: this scene interpolates real shading, and the
    # two do not round identically. See `count_mismatches`.
    assert_equal(count_mismatches(cpu, gpu, tolerance=1), 0)


def count_background(image: Framebuffer, background: Color) raises -> Int:
    """Return how many pixels still hold the clear colour.

    Args:
        image: The rendered image.
        background: The colour it was cleared to.

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


def test_the_gpu_reads_back_depth_and_not_just_colour() raises:
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
                # applies as to colour; see `count_mismatches`.
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
