# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The measurable strand-hair requirements on the reference scenes (#298).

Each test states one requirement from Strand hair rendering and checks it
on the CPU rasterizer. `tests/test_gpu.mojo` draws the same scenes on the
device rasterizer and requires the same images.
"""

from core.assets import Assets
from core.scene import Scene
from extensions.humanoid.skeleton.head.hair.reference import (
    BACK_COLOR,
    FRONT_COLOR,
    HairReferenceRig,
    REFERENCE_BACKGROUND,
    add_crossing_strands,
    add_fine_silhouettes,
    block_coverage_error,
    count_color,
    coverage_samples,
    reference_camera,
    supersampled_coverage,
    total_coverage_error,
)
from extensions.humanoid.skeleton.head.hair.shading import HairLook
from math.vector3 import Vector3
from objects.line_segments2 import SOLID_LINE_COVERAGE, STRAND_LINE_COVERAGE
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.math import abs, inf, nan, sqrt
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime SIZE = 64
comptime FACTOR = 8
comptime FRONT_LIGHT = Vector3(0, 0.3, 1)
# Directly behind the curtain, inside the narrow TT lobe.
comptime BACK_LIGHT = Vector3(0, -0.035, -1)


def _look() -> HairLook:
    """Return a medium-brown fiber with Frostbitten's default lobes."""
    return HairLook(Vector3(0.3, 0.18, 0.1))


def _render(
    scene: Scene, assets: Assets, size: Int, workers: Int = 1
) raises -> Framebuffer:
    """Render a flat reference scene through the two-meter camera."""
    var renderer = Renderer(size, size, workers=workers)
    renderer.set_background(REFERENCE_BACKGROUND)
    return renderer.render(scene, assets, reference_camera(Length(2, METER)))


def _fine(
    size: Int,
    width_px: Float32,
    opacity: Float32,
    solid: Bool,
    reverse: Bool = False,
    workers: Int = 1,
) raises -> Framebuffer:
    """Render twelve fibers of one width, given in output pixels at SIZE."""
    var scene = Scene()
    var assets = Assets()
    add_fine_silhouettes(
        scene,
        assets,
        12,
        Length(width_px * 2 / Float32(SIZE), METER),
        opacity,
        SOLID_LINE_COVERAGE if solid else STRAND_LINE_COVERAGE,
        reverse,
    )
    scene.update()
    return _render(scene, assets, size, workers)


def _same(a: Framebuffer, b: Framebuffer) raises:
    """Require the same pixels, every silhouette hole included."""
    assert_equal(a.width, b.width)
    assert_equal(a.height, b.height)
    assert_true(a.pixels == b.pixels)


def _check_width(width_px: Float32, noise_limit: Float64) raises:
    """Check the coverage requirements of one width at three opacities.

    R1: the summed stochastic coverage is within three binomial standard
    deviations of the supersampled ground truth, so it is unbiased.
    R2: after a 16-pixel box filter, the normalized mean absolute error
    stays at or under `noise_limit`.
    """
    var truth_image = _fine(SIZE * FACTOR, width_px, 1, True)
    for opacity in [Float32(0.35), 0.65, 1]:
        var truth = supersampled_coverage(
            truth_image, FACTOR, REFERENCE_BACKGROUND, opacity
        )
        var measured = coverage_samples(
            _fine(SIZE, width_px, opacity, False), REFERENCE_BACKGROUND
        )
        var expected = Float64(0)
        for value in truth:
            expected += Float64(value)
        assert_true(total_coverage_error(measured, truth) <= 3 / sqrt(expected))
        assert_true(
            block_coverage_error(measured, truth, SIZE, 16) <= noise_limit
        )


def test_quarter_pixel_fibers_match_supersampled_coverage() raises:
    _check_width(0.25, 0.35)


def test_half_pixel_fibers_match_supersampled_coverage() raises:
    _check_width(0.5, 0.25)


def test_one_pixel_fibers_match_supersampled_coverage() raises:
    _check_width(1, 0.15)


def test_two_pixel_fibers_match_supersampled_coverage() raises:
    _check_width(2, 0.10)


def test_fine_silhouettes_do_not_depend_on_order_or_workers() raises:
    var first = _fine(SIZE, 0.5, 0.65, False)
    _same(first, _fine(SIZE, 0.5, 0.65, False, reverse=True))
    _same(first, _fine(SIZE, 0.5, 0.65, False, workers=3))
    _same(first, _fine(SIZE, 0.5, 0.65, False))


def _crossing(
    count: Int,
    width: Float32,
    front: Float32,
    back: Float32,
    reverse: Bool = False,
) raises -> Framebuffer:
    """Render the two crossing layers."""
    var scene = Scene()
    var assets = Assets()
    add_crossing_strands(
        scene,
        assets,
        count,
        Length(width, METER),
        front,
        back,
        STRAND_LINE_COVERAGE,
        reverse,
    )
    scene.update()
    return _render(scene, assets, SIZE)


def test_crossing_layers_match_alpha_compositing_in_any_order() raises:
    # R3: where a front layer of opacity a covers a back layer of opacity
    # b, a of the samples show the front, (1 - a) b show the back, and
    # the rest show the background, as alpha compositing gives. The
    # 784-sample window allows three standard deviations, 0.05.
    for pair in [
        (Float32(0.65), Float32(0.65)),
        (Float32(0.35), Float32(1)),
        (Float32(1), Float32(0.5)),
    ]:
        var a = pair[0]
        var b = pair[1]
        var image = _crossing(1, 1, a, b)
        var window = Float64(28 * 28)
        var front = Float64(count_color(image, FRONT_COLOR, 18, 18, 46, 46))
        var back = Float64(count_color(image, BACK_COLOR, 18, 18, 46, 46))
        assert_true(abs(front / window - Float64(a)) <= 0.05)
        assert_true(abs(back / window - Float64((1 - a) * b)) <= 0.05)
        # R4: the submission order does not change one sample.
        _same(image, _crossing(1, 1, a, b, reverse=True))
    # Fine crossing fibers, eight in each layer.
    var weave = _crossing(8, 0.02, 0.65, 0.65)
    _same(weave, _crossing(8, 0.02, 0.65, 0.65, reverse=True))
    assert_true(count_color(weave, FRONT_COLOR, 0, 0, SIZE, SIZE) > 40)
    assert_true(count_color(weave, BACK_COLOR, 0, 0, SIZE, SIZE) > 40)


def test_self_shadow_darkens_rows_away_from_the_light() raises:
    # R5: under a front light, each row farther from the light is darker.
    # R6: a denser volume never brightens a row and darkens every row
    # behind the first. R7: no row falls below 1 - HairLook.shadows of
    # the first row, the documented darkness bound.
    var look = _look()
    var thin = HairReferenceRig(look, FRONT_LIGHT).row_luminance()
    var dense = HairReferenceRig(
        look, FRONT_LIGHT, clump=Length(0.003, METER)
    ).row_luminance()
    assert_equal(len(thin), 4)
    for row in range(1, 4):
        assert_true(thin[row] < thin[row - 1])
        assert_true(dense[row] < thin[row])
    assert_true(dense[0] <= thin[0])
    var floor = Float64(1 - look.shadows)
    assert_true(dense[3] >= floor * dense[0])
    assert_true(thin[3] >= floor * thin[0])


def test_backlight_transmits_and_its_optical_depth_grows_from_the_light() raises:
    var look = _look()
    var tt = look
    tt.weight_tt = 1
    var without = HairReferenceRig(look, BACK_LIGHT)
    var through = HairReferenceRig(tt, BACK_LIGHT)
    var dark = without.row_luminance()
    var lit = through.row_luminance()
    # R8: the TT lobe makes a backlit curtain at least 1.5 times brighter.
    for row in range(4):
        assert_true(lit[row] >= 1.5 * dark[row])
    # It is a forward lobe: a front light gains less than one percent.
    var front = HairReferenceRig(look, FRONT_LIGHT).row_luminance()
    var front_tt = HairReferenceRig(tt, FRONT_LIGHT).row_luminance()
    for row in range(4):
        assert_true(front_tt[row] <= 1.01 * front[row])
    # R9: the camera-side row has the most hair between it and the light.
    var depths = _row_optical_depth(through)
    for row in range(1, 4):
        assert_true(depths[row] <= depths[row - 1])
    assert_true(depths[0] > depths[3])


def _row_optical_depth(rig: HairReferenceRig) raises -> List[Float64]:
    """Return each row's mean optical depth toward the rig's light."""
    var sums = List[Float64](length=4, fill=0)
    var counts = List[Int](length=4, fill=0)
    ref groom = rig.hair.groom
    for strand in range(len(groom)):
        var row = rig.rows[strand]
        for index in range(groom.starts[strand], groom.starts[strand + 1]):
            sums[row] += Float64(
                rig.hair.density.optical_depth(
                    groom.points[index], rig.lights[0].direction
                )
            )
            counts[row] += 1
    for row in range(4):
        sums[row] /= Float64(counts[row])
    return sums^


def _frames(steps: Int) raises -> List[Framebuffer]:
    """Render the rest pose and `steps` frames of moving hair."""
    var rig = HairReferenceRig(_look(), FRONT_LIGHT)
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(REFERENCE_BACKGROUND)
    var frames = List[Framebuffer]()
    frames.append(renderer.render(rig.scene, rig.assets, rig.camera))
    for _ in range(steps):
        rig.advance(2)
        frames.append(renderer.render(rig.scene, rig.assets, rig.camera))
    return frames^


def _covered(image: Framebuffer) raises -> Float64:
    """Return how many samples differ from the background."""
    var total = Float64(0)
    for value in coverage_samples(image, REFERENCE_BACKGROUND):
        total += Float64(value)
    return total


def test_moving_long_hair_is_repeatable_and_its_coverage_is_stable() raises:
    var frames = _frames(5)
    var replay = _frames(5)
    var rest = _covered(frames[0])
    for index in range(len(frames)):
        # R10: the same steps give the same image.
        _same(frames[index], replay[index])
        # R11: with no temporal accumulation, each frame keeps its
        # covered samples within five percent of the rest pose.
        assert_true(abs(_covered(frames[index]) - rest) <= 0.05 * rest)
        if index > 0:
            # The motion is visible.
            assert_true(frames[index].pixels != frames[index - 1].pixels)


def test_moving_hair_rebuilds_its_self_shadow() raises:
    # R12: after motion the density volume and the colors follow the
    # strands.
    var rig = HairReferenceRig(_look(), FRONT_LIGHT)
    var before = rig.colors()
    var depth = rig.hair.density.coefficients.copy()
    rig.advance(0)
    assert_true(rig.colors() == before)
    rig.advance(6)
    assert_true(rig.hair.density.coefficients != depth)
    assert_true(rig.colors() != before)


def _strip_luminance(image: Framebuffer) raises -> Float64:
    """Sum the receiver's luminance in the strip under the strand tips."""
    var total = Float64(0)
    for y in range(55, 63):
        for x in range(19, 45):
            var p = image.get_pixel(x, y)
            total += (
                0.2126 * Float64(p.r)
                + 0.7152 * Float64(p.g)
                + 0.0722 * Float64(p.b)
            )
    return total


def _cast(opacity: Float32, cast: Bool) raises -> Float64:
    """Render the curtain over its receiver and measure the strip."""
    var rig = HairReferenceRig(
        _look(), FRONT_LIGHT, opacity=opacity, receiver=True
    )
    rig.scene.wide_lines[0].cast_shadow = cast
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(REFERENCE_BACKGROUND)
    return _strip_luminance(renderer.render(rig.scene, rig.assets, rig.camera))


def test_strand_cast_shadow_darkens_the_receiver_by_opacity() raises:
    # R13: the strands' stochastic cast shadow darkens the receiver, and
    # more opaque strands darken it more.
    var open = _cast(1, False)
    var solid = _cast(1, True)
    var light = _cast(0.35, True)
    assert_true(solid < 0.9 * open)
    assert_true(solid < light)
    assert_true(light < _cast(0.35, False))


def test_metrics_refuse_inconsistent_inputs() raises:
    var scene = Scene()
    var assets = Assets()
    with assert_raises(contains="at least one fiber"):
        add_fine_silhouettes(
            scene, assets, 0, Length(0.01, METER), 1, STRAND_LINE_COVERAGE
        )
    with assert_raises(contains="at least one fiber"):
        add_crossing_strands(
            scene,
            assets,
            0,
            Length(0.01, METER),
            1,
            1,
            STRAND_LINE_COVERAGE,
        )
    var image = Framebuffer(16, 8, REFERENCE_BACKGROUND)
    for factor in [0, 3, 16]:
        with assert_raises(contains="divide the image"):
            _ = supersampled_coverage(image, factor, REFERENCE_BACKGROUND, 1)
    assert_equal(
        len(supersampled_coverage(image, 8, REFERENCE_BACKGROUND, 1)), 2
    )
    var one: List[Float32] = [1]
    var none = List[Float32]()
    with assert_raises(contains="same length"):
        _ = total_coverage_error(one, none)
    with assert_raises(contains="must be positive"):
        _ = total_coverage_error(none, none)
    with assert_raises(contains="same length"):
        _ = block_coverage_error(one, none, 1, 1)
    var twelve = List[Float32](length=12, fill=1)
    var eight = List[Float32](length=8, fill=1)
    with assert_raises(contains="block size"):
        _ = block_coverage_error(eight, eight, 4, 0)
    with assert_raises(contains="block size"):
        _ = block_coverage_error(eight, eight, 0, 1)
    with assert_raises(contains="block size"):
        _ = block_coverage_error(twelve, twelve, 6, 4)
    with assert_raises(contains="block size"):
        _ = block_coverage_error(twelve, twelve, 4, 2)
    with assert_raises(contains="must be positive"):
        _ = block_coverage_error(none, none, 4, 2)
    assert_equal(block_coverage_error(eight, eight, 4, 2), 0)
    # An empty rectangle counts nothing, in either direction.
    assert_equal(count_color(image, REFERENCE_BACKGROUND, 0, 3, 16, 3), 0)
    assert_equal(count_color(image, REFERENCE_BACKGROUND, 5, 0, 5, 8), 0)
    assert_equal(count_color(image, REFERENCE_BACKGROUND, 0, 0, 16, 8), 128)
    image.set_pixel(1, 1, Color(0, 1, 0))
    assert_equal(coverage_samples(image, REFERENCE_BACKGROUND)[17], 1)


def test_rig_refuses_bad_counts_and_lights() raises:
    var look = _look()
    with assert_raises(contains="rows, guides and points"):
        _ = HairReferenceRig(look, FRONT_LIGHT, rows=0)
    with assert_raises(contains="rows, guides and points"):
        _ = HairReferenceRig(look, FRONT_LIGHT, guides=0)
    with assert_raises(contains="rows, guides and points"):
        _ = HairReferenceRig(look, FRONT_LIGHT, followers=-1)
    with assert_raises(contains="rows, guides and points"):
        _ = HairReferenceRig(look, FRONT_LIGHT, points=1)
    for light in [
        Vector3(0, 0, 0),
        Vector3(inf[DType.float32](), 0, 0),
        Vector3(nan[DType.float32](), 0, 0),
    ]:
        with assert_raises(contains="finite direction"):
            _ = HairReferenceRig(look, light)
    # A curtain without followers is still a valid scene.
    var bare = HairReferenceRig(look, FRONT_LIGHT, rows=1, followers=0)
    assert_equal(len(bare.rows), 12)
    assert_equal(len(bare.row_luminance()), 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
