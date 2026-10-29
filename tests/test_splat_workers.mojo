# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the workers and the row spans of `render.splat_raster`.

More workers must sort, project and draw as one does, to the bit, and a
splat that visits only the rows and columns of its disc must draw what its
whole box draws. The cloud is 9,000 splats of every band, enough for the
projection and the fill to share the splats out in runs. A line of 40,000
splats is enough for the sort.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    create_gaussian_splat_geometry,
    packed_band,
    write_covariance,
)
from core.object3d import Object3D
from core.scene import Scene
from math.vector3 import Vector3
from objects.gaussian_splat import SORT_RUN, GaussianSplat
from render.framebuffer import Color
from render.raster_state import DepthMode
from render.splat_raster import (
    SPLAT_RUN,
    blend_splat_pixel,
    _splat_band,
    draw_gaussian_splat,
    prepare_gaussian_splat,
    raise_splat_band_errors,
    rasterize_splats,
    splat_disc_rows,
    splat_row_span,
    splat_rows,
)
from render.splatrule import (
    ProjectedSplat,
    splat_alpha,
    splat_depth_passes,
    splat_reach,
)
from render.target import RenderTarget
from render.tasks import TaskGroup
from std.math import ceil, floor, inf, nan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Angle, DEGREE, Length, METER

comptime COUNT = 9000
comptime WIDTH = 96
comptime HEIGHT = 64


struct _Random:
    """A linear congruential generator, so the cloud is the same each run."""

    var state: UInt64

    def __init__(out self):
        self.state = 20261020

    def next(mut self) -> Float64:
        """Return a number from 0 up to 1."""
        self.state = self.state * 6364136223846793005 + 1442695040888963407
        return Float64(self.state >> 11) / Float64(1 << 53)

    def between(mut self, low: Float64, high: Float64) -> Float64:
        """Return a number from `low` up to `high`."""
        return low + (high - low) * self.next()


def _cloud() raises -> GaussianSplatGeometry:
    """Return `COUNT` splats of every band in a box before the camera."""
    var random = _Random()
    var centers = List[Float32]()
    var covariances = List[Float32](length=COUNT * 6, fill=0)
    var colors = List[UInt8]()
    for index in range(COUNT):
        for _ in range(3):
            centers.append(Float32(random.between(-2, 2)))
        write_covariance(
            covariances,
            index * 6,
            random.between(0.005, 0.2),
            random.between(0.005, 0.05),
            random.between(0.005, 0.1),
            random.between(-1, 1),
            random.between(-1, 1),
            random.between(-1, 1),
            random.between(0.2, 1),
        )
        for _ in range(4):
            colors.append(UInt8(Int(random.between(0, 256))))
    var bands = List[List[UInt8]]()
    for degree in range(1, 4):
        var band = packed_band(COUNT, degree)
        for at in range(len(band)):
            band[at] = UInt8(Int(random.between(0, 256)))
        bands.append(band^)
    return create_gaussian_splat_geometry(
        centers^,
        covariances^,
        colors^,
        bands[0].copy(),
        bands[1].copy(),
        bands[2].copy(),
    )


def _camera() raises -> PerspectiveCamera:
    """Return a camera that sees the whole cloud."""
    var camera = PerspectiveCamera(
        Angle(60, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100, METER),
    )
    camera.place(Vector3(1, 2, 7), Vector3(0, 0, 0))
    return camera^


def _same_pictures(found: RenderTarget, expected: RenderTarget) raises:
    """Assert two targets hold the same colors to the bit."""
    assert_equal(len(found.colors), len(expected.colors))
    for at in range(len(found.colors)):
        var a = found.colors[at]
        var b = expected.colors[at]
        if a.r != b.r or a.g != b.g or a.b != b.b or a.a != b.a:
            raise Error("the pictures differ at pixel " + String(at))


def _box_blend(mut target: RenderTarget, splat: ProjectedSplat) raises:
    """Blend one splat over its whole box, with the fill's own rule for a
    pixel: what the fill did before spans."""
    var reach = splat_reach(splat)
    var left = max(Int(floor(splat.x - reach[0])) - 1, 0)
    var right = min(Int(ceil(splat.x + reach[0])) + 1, target.width - 1)
    var top = max(Int(floor(splat.y - reach[1])) - 1, 0)
    var bottom = min(Int(ceil(splat.y + reach[1])) + 1, target.height - 1)
    for y in range(top, bottom + 1):
        for x in range(left, right + 1):
            var stored = target.depth[y * target.width + x]
            if not splat_depth_passes(target.depth_mode, splat.depth, stored):
                continue
            var alpha = splat_alpha(splat, x, y)
            if alpha > 0:
                blend_splat_pixel(target, y * target.width + x, splat, alpha)


def test_more_workers_draw_the_same_picture() raises:
    """Four workers project and fill as one does, to the bit."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var camera = _camera()
    var one = GaussianSplat(_cloud(), node)
    var four = GaussianSplat(_cloud(), node)
    assert_true(COUNT // SPLAT_RUN >= 2)
    var alone = prepare_gaussian_splat(
        scene, one, camera, WIDTH, HEIGHT, DepthMode(0)
    )
    var shared = prepare_gaussian_splat(
        scene, four, camera, WIDTH, HEIGHT, DepthMode(0), None, 4
    )
    assert_equal(len(alone), len(shared))
    assert_true(len(alone) > COUNT // 2)
    for index in range(len(alone)):
        var a = alone[index]
        var b = shared[index]
        assert_true(a.x == b.x and a.y == b.y and a.depth == b.depth)
        assert_true(a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a)
        assert_true(a.scale1 == b.scale1 and a.axis_x == b.axis_x)
    var serial = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0, 255))
    var banded = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0, 255))
    draw_gaussian_splat(serial, scene, one, camera)
    draw_gaussian_splat(banded, scene, four, camera, None, 4)
    _same_pictures(banded, serial)


def test_a_row_span_draws_what_the_whole_box_draws() raises:
    """Spans skip only the pixels that would add nothing."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var camera = _camera()
    var splat = GaussianSplat(_cloud(), node)
    var splats = prepare_gaussian_splat(
        scene, splat, camera, WIDTH, HEIGHT, DepthMode(0)
    )
    # A long splat at a slant, one that crosses the frame, and a round one.
    splats.append(ProjectedSplat(40, 30, 0, 0.6, 0.8, 30, 0.7, 1, 0, 0, 0.9))
    splats.append(ProjectedSplat(48, 32, 0, 0.8, -0.6, 80, 9, 0, 1, 0, 0.5))
    splats.append(ProjectedSplat(10, 10, 0, 1, 0, 3, 3, 0, 0, 1, 0.8))
    var spans = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0, 255))
    var boxes = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0, 255))
    rasterize_splats(spans, splats)
    for index in range(len(splats)):
        _box_blend(boxes, splats[index])
    _same_pictures(spans, boxes)


def test_a_span_holds_the_disc_and_no_more() raises:
    """A row through a splat spans its disc; a row past it spans nothing."""
    var round = ProjectedSplat(20, 20, 0, 1, 0, 2, 2, 1, 1, 1, 1)
    var middle = splat_row_span(round, 19, 0, 40)
    # The disc reaches four pixels each way, a little less on a row half a
    # pixel off its middle: the pixel centers from 16.5 to 23.5.
    assert_equal(middle[0], 16)
    assert_equal(middle[1], 23)
    var past = splat_row_span(round, 30, 0, 40)
    assert_true(past[0] > past[1])
    var clipped = splat_row_span(round, 19, 18, 21)
    assert_equal(clipped[0], 18)
    assert_equal(clipped[1], 21)
    var rows = splat_rows(round)
    assert_equal(rows[0], 15)
    assert_equal(rows[1], 25)


def test_a_splat_that_is_not_an_ellipse_gets_its_box() raises:
    """A zero, an infinite or a missing axis or scale spans the whole box."""
    var flat = ProjectedSplat(20, 20, 0, 1, 0, 0, 2, 1, 1, 1, 1)
    var wide = ProjectedSplat(
        20, 20, 0, 1, 0, inf[DType.float32](), 2, 1, 1, 1, 1
    )
    var lost = ProjectedSplat(
        20, 20, 0, 1, 0, nan[DType.float32](), 2, 1, 1, 1, 1
    )
    var still = ProjectedSplat(20, 20, 0, 0, 0, 2, 2, 1, 1, 1, 1)
    for splat in [flat, wide, lost, still]:
        var span = splat_row_span(splat, 19, 3, 37)
        assert_equal(span[0], 3)
        assert_equal(span[1], 37)


def test_a_short_target_or_one_worker_fills_on_one_thread() raises:
    """One row has one band, and one worker has one, whatever is asked."""
    var splats: List[ProjectedSplat] = [
        ProjectedSplat(4, 0, 0, 1, 0, 1, 1, 1, 0, 0, 1)
    ]
    var row = RenderTarget(8, 1, Color(0, 0, 0, 255))
    var alone = RenderTarget(8, 1, Color(0, 0, 0, 255))
    rasterize_splats(row, splats, 4)
    rasterize_splats(alone, splats, 1)
    _same_pictures(row, alone)
    assert_true(row.colors[4].r > 0)
    # No splats on many bands draw nothing.
    var empty = RenderTarget(8, 8, Color(0, 0, 0, 255))
    rasterize_splats(empty, List[ProjectedSplat](), 4)
    assert_equal(empty.colors[0].r, 0)


def _run_band(
    mut target: RenderTarget,
    splats: List[ProjectedSplat],
    members: List[Int],
    mut errors: List[String],
):
    """Run the second band of two, alone, as `rasterize_splats` runs it."""
    var spans = members.copy()
    var group = TaskGroup()
    group.create_task(
        _splat_band(
            Pointer(to=target).unsafe_origin_cast[MutAnyOrigin](),
            splats.unsafe_ptr().unsafe_origin_cast[ImmutAnyOrigin](),
            spans.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
            len(spans),
            errors.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
            1,
            0,
            target.height - 1,
        )
    )
    group.wait()
    _ = len(spans)
    _ = len(splats)


def test_a_band_carries_its_error_back() raises:
    """A band that is refused writes its slot, and the slot is raised."""
    var target = RenderTarget(8, 8, Color(0, 0, 0, 255))
    target.depth_mode = DepthMode(9)
    var splats: List[ProjectedSplat] = [
        ProjectedSplat(4, 4, 0, 1, 0, 1, 1, 1, 0, 0, 1)
    ]
    var members: List[Int] = [0]
    var errors = List[String](length=2, fill=String())
    _run_band(target, splats, members, errors)
    assert_equal(errors[0], "")
    assert_true("valid depth mode" in errors[1])
    with assert_raises(contains="valid depth mode"):
        raise_splat_band_errors(errors)
    raise_splat_band_errors(List[String](length=3, fill=String()))
    raise_splat_band_errors(List[String]())


def _line(count: Int) raises -> GaussianSplatGeometry:
    """Return `count` small splats along a line away from the camera, many
    to a bin of the sort."""
    var random = _Random()
    var centers = List[Float32]()
    var covariances = List[Float32](length=count * 6, fill=0)
    var colors = List[UInt8](length=count * 4, fill=128)
    for index in range(count):
        centers.append(Float32(random.between(-1, 1)))
        centers.append(Float32(random.between(-1, 1)))
        centers.append(Float32(random.between(-4, 4)))
        write_covariance(covariances, index * 6, 0.01, 0.01, 0.01, 0, 0, 0, 1)
    return create_gaussian_splat_geometry(centers^, covariances^, colors^)


def test_more_workers_sort_in_the_same_order() raises:
    """A sort shared out in runs gives one worker's order: by bin, and by
    index in a bin."""
    var count = 40000
    assert_true(count // SORT_RUN >= 2)
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var camera = _camera()
    var world = scene.world_matrix(node)
    var view = camera.view_matrix_in(scene)
    var one = GaussianSplat(_line(count), node)
    var four = GaussianSplat(_line(count), node)
    assert_true(one.update_sort(world, view, Length(0.1, METER)))
    assert_true(four.update_sort(world, view, Length(0.1, METER), 4))
    for at in range(count):
        assert_equal(one.order[at], four.order[at])
    for at in range(1, count):
        var before = one.sort_bin(one.order[at - 1])
        var after = one.sort_bin(one.order[at])
        assert_true(
            before < after
            or (before == after and one.order[at - 1] < one.order[at])
        )


def test_a_splat_takes_the_rows_of_its_disc() raises:
    """A round splat takes the rows its disc reaches, and a tiny one takes
    one row where its box takes five."""
    var round = ProjectedSplat(20, 20, 0, 1, 0, 2, 2, 1, 1, 1, 1)
    var rows = splat_disc_rows(round)
    assert_equal(rows[0], 16)
    assert_equal(rows[1], 23)
    var tiny = ProjectedSplat(20.3, 20.3, 0, 1, 0, 0.3, 0.3, 1, 1, 1, 1)
    var box = splat_rows(tiny)
    assert_equal(box[1] - box[0] + 1, 5)
    var disc = splat_disc_rows(tiny)
    assert_equal(disc[0], 20)
    assert_equal(disc[1], 20)


def test_a_splat_that_is_not_an_ellipse_takes_its_box_rows() raises:
    """A zero, an infinite or a missing scale, or no axis, takes the box's
    rows, as its spans take the box's columns."""
    var flat = ProjectedSplat(20, 20, 0, 1, 0, 0, 2, 1, 1, 1, 1)
    var thin = ProjectedSplat(20, 20, 0, 1, 0, 2, 0, 1, 1, 1, 1)
    var still = ProjectedSplat(20, 20, 0, 0, 0, 2, 2, 1, 1, 1, 1)
    var wide = ProjectedSplat(
        20, 20, 0, 0.6, 0.8, inf[DType.float32](), 2, 1, 1, 1, 1
    )
    var lost = ProjectedSplat(
        20, 20, 0, 1, 0, nan[DType.float32](), 2, 1, 1, 1, 1
    )
    for splat in [flat, thin, still, wide, lost]:
        var rows = splat_disc_rows(splat)
        var box = splat_rows(splat)
        assert_equal(rows[0], box[0])
        assert_equal(rows[1], box[1])


def test_splats_past_the_frame_reach_no_band() raises:
    """Splats above, below and in the frame, shared out in runs, draw what
    one worker draws."""
    var splats = List[ProjectedSplat]()
    for index in range(2 * SPLAT_RUN + 100):
        var x = Float32(index % 90) + 3
        var y = Float32((index // 90) % 104) - 20
        splats.append(
            ProjectedSplat(x, y, 0, 0.6, 0.8, 0.7, 0.4, 0.5, 0.2, 0.1, 0.3)
        )
    var serial = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0, 255))
    var banded = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0, 255))
    rasterize_splats(serial, splats, 1)
    rasterize_splats(banded, splats, 4)
    _same_pictures(banded, serial)
    assert_true(serial.colors[30 * WIDTH + 40].r > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
