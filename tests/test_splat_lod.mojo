# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.splat_lod`, levels of detail for Gaussian splats.

Two splats merge into the Gaussian of their moments, and splats that
overlap widen it. A tree over a grid of splats holds each splat once and
a merged splat for each node of more than one. A view selects every splat at 0 pixels, the root's merged splat
from far away, and nothing behind it or past a side. More workers select,
project and draw as one does, to the bit.
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
from objects.gaussian_splat import GaussianSplat
from render.framebuffer import Color
from render.raster_state import DepthMode
from render.rect import Rect
from render.splat_lod import (
    LOD_LEAF,
    LOD_RUN,
    SplatLod,
    build_splat_lod,
    draw_splat_lod,
    morton_order,
    prepare_splat_lod,
    select_splats,
)
from render.splat_raster import draw_gaussian_splat
from render.target import RenderTarget
from std.math import nan, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime WIDTH = 64
comptime HEIGHT = 48


def _splats(
    var centers: List[Float32], deviation: Float64, opacity: UInt8, degree: Int
) raises -> GaussianSplatGeometry:
    """Return round splats at centers, gray, with harmonics bytes that count
    up."""
    var count = len(centers) // 3
    var covariances = List[Float32](length=count * 6, fill=0)
    var colors = List[UInt8]()
    for index in range(count):
        write_covariance(
            covariances,
            index * 6,
            deviation,
            deviation,
            deviation,
            0,
            0,
            0,
            1,
        )
        colors.append(UInt8(100 + index % 50))
        colors.append(UInt8(120))
        colors.append(UInt8(140))
        colors.append(opacity)
    var bands = List[List[UInt8]]()
    for band in range(1, 4):
        var bytes = List[UInt8]()
        if band <= degree:
            bytes = packed_band(count, band)
            for at in range(len(bytes)):
                bytes[at] = UInt8(100 + at % 60)
        bands.append(bytes^)
    return create_gaussian_splat_geometry(
        centers^,
        covariances^,
        colors^,
        bands[0].copy(),
        bands[1].copy(),
        bands[2].copy(),
    )


def _grid(
    side: Int, spacing: Float32, degree: Int
) raises -> GaussianSplatGeometry:
    """Return `side^3` splats on a grid about the origin."""
    var centers = List[Float32]()
    var half = Float32(side - 1) * spacing / 2
    for k in range(side):
        for j in range(side):
            for i in range(side):
                centers.append(Float32(i) * spacing - half)
                centers.append(Float32(j) * spacing - half)
                centers.append(Float32(k) * spacing - half)
    return _splats(centers^, Float64(spacing) * 0.3, 200, degree)


def _camera(z: Float32) raises -> PerspectiveCamera:
    """Return a camera on the z axis that looks at the origin."""
    var camera = PerspectiveCamera(
        Angle(60, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(1000, METER),
    )
    camera.place(Vector3(0, 0, z), Vector3(0, 0, 0))
    return camera^


def test_morton_order_sorts_the_centers_along_the_curve() raises:
    """The far corner sorts last, splats of one code keep their order, and
    a center that is not a number is in the first cell."""
    var centers: List[Float32] = [
        1,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        nan[DType.float32](),
        0,
        0,
    ]
    var sorted = morton_order(_splats(centers^, 0.1, 255, 0))
    ref codes = sorted[0]
    ref order = sorted[1]
    assert_equal(order[3], 0)
    assert_equal(codes[3], 0x7FFFFFFFFFFFFFFF)
    assert_equal(codes[0], 0)
    # The two at the origin keep their order; the lost center is with them.
    assert_equal(order[0], 1)
    assert_equal(order[1], 2)
    assert_equal(order[2], 3)


def test_two_splats_merge_into_the_gaussian_of_their_moments() raises:
    """Two equal splats a unit apart: the mean between them, the variance
    widened by the offsets, the mean color, and an opacity of their summed
    area over the merged area."""
    var centers: List[Float32] = [-0.5, 0, 0, 0.5, 0, 0]
    var scene = Scene()
    var node = scene.add(Object3D())
    var lod = build_splat_lod(_splats(centers^, 0.1, 255, 3), node)
    assert_equal(len(lod.nodes), 1)
    assert_equal(lod.scan_count(), 2)
    assert_equal(lod.splat.count(), 3)
    var root = lod.nodes[0]
    assert_equal(root.children, 0)
    assert_equal(root.merged, 2)
    ref g = lod.splat.splat_geometry
    assert_almost_equal(g.centers[6], 0, atol=1e-7)
    # Each splat's variance is 0.01, and each is 0.5 from the mean.
    assert_almost_equal(g.covariances[12], 0.26, atol=1e-6)
    assert_almost_equal(g.covariances[15], 0.01, atol=1e-7)
    assert_almost_equal(g.covariances[13], 0, atol=1e-7)
    # Colors 100 and 101: the mean rounds half to even.
    assert_equal(g.colors[8], 100)
    assert_equal(g.colors[9], 120)
    # The area of a splat is sqrt(3) 0.01; of the merged, sqrt(0.0053).
    var expected = min(
        2 * sqrt(3.0) * 0.01 / sqrt(0.26 * 0.01 * 2 + 0.0001), 1.0
    )
    assert_almost_equal(Float64(g.colors[11]) / 255, expected, atol=0.003)
    # The harmonics bytes are means: 100 and 112, and 120 and 144.
    assert_equal(g.sh1[2 * 12], 106)
    assert_equal(g.sh3[2 * 24 + 20], 132)
    # The sphere holds both splats out to twice their deviation, 0.1.
    assert_almost_equal(Float64(root.radius), 0.7, atol=1e-6)


def test_clear_splats_merge_evenly_into_a_clear_one() raises:
    """Splats of no opacity weigh the same, and the merged splat is clear."""
    var centers: List[Float32] = [0, 0, 0, 1, 0, 0, 2, 0, 0]
    var scene = Scene()
    var node = scene.add(Object3D())
    var lod = build_splat_lod(_splats(centers^, 0.1, 0, 0), node)
    ref g = lod.splat.splat_geometry
    assert_almost_equal(g.centers[9], 1, atol=1e-6)
    assert_equal(g.colors[15], 0)
    assert_equal(len(g.sh1), 0)


def _patch(side: Int, deviation: Float64, opacity: UInt8) raises -> SplatLod:
    """Return the tree of a square patch of splats 0.1 apart, flat in z."""
    var centers = List[Float32]()
    var covariances = List[Float32]()
    var colors = List[UInt8]()
    for j in range(side):
        for i in range(side):
            centers.extend([Float32(i) * 0.1, Float32(j) * 0.1, 0])
            var v = Float32(deviation * deviation)
            covariances.extend([v, 0, 0, v, 0, 1e-6])
            colors.extend([UInt8(90), UInt8(90), UInt8(90), opacity])
    var scene = Scene()
    var node = scene.add(Object3D())
    return build_splat_lod(
        create_gaussian_splat_geometry(centers^, covariances^, colors^), node
    )


def test_overlapping_splats_widen_the_merged_splat() raises:
    """Splats that cover more than the merged splat's area widen it, until
    its opacity times its area holds their weight, or its deviation reaches
    the node's sphere."""
    # Sixteen half-clear splats of deviation 0.05: their weight fills the
    # merged splat when it is widened by a third.
    var lod = _patch(4, 0.05, 128)
    var root = lod.nodes[0]
    ref g = lod.splat.splat_geometry
    var xx = 0.0025 + 0.0125
    var area = sqrt(xx * xx + 2 * xx * 1e-6)
    var total = 16 * 128.0 / 255 * sqrt(0.0025 * 0.0025 + 2 * 0.0025 * 1e-6)
    var widen = total / area
    assert_true(widen > 1.3 and widen < 1.4)
    assert_almost_equal(
        Float64(g.covariances[root.merged * 6]), xx * widen, atol=1e-6
    )
    assert_equal(g.colors[root.merged * 4 + 3], 255)
    # Four opaque splats of deviation 0.1 would need more: the merged
    # splat's deviation stops at the sphere's radius.
    var wide = _patch(2, 0.1, 255)
    var top = wide.nodes[0]
    ref h = wide.splat.splat_geometry
    var trace = Float64(
        h.covariances[top.merged * 6]
        + h.covariances[top.merged * 6 + 3]
        + h.covariances[top.merged * 6 + 5]
    )
    assert_almost_equal(trace, Float64(top.radius) ** 2, atol=1e-6)
    assert_equal(h.colors[top.merged * 4 + 3], 255)


def test_a_grid_makes_a_tree_of_every_splat_once() raises:
    """Each leaf holds `LOD_LEAF` splats or fewer, each splat is in one
    leaf, and each node of more than one splat has a merged splat."""
    var scene = Scene()
    var node = scene.add(Object3D())
    var lod = build_splat_lod(_grid(6, 0.5, 1), node)
    assert_equal(lod.scan_count(), 216)
    var held = List[Int](length=216, fill=0)
    var merged = 0
    for at in range(len(lod.nodes)):
        var here = lod.nodes[at]
        if here.high - here.low > 1:
            merged += 1
            assert_true(here.merged >= 216)
        if here.children == 0:
            assert_true(here.high - here.low <= LOD_LEAF)
            for index in range(here.low, here.high):
                held[index] += 1
        else:
            assert_equal(lod.nodes[here.first_child].low, here.low)
            var last = here.first_child + here.children - 1
            assert_equal(lod.nodes[last].high, here.high)
    for index in range(216):
        assert_equal(held[index], 1)
    assert_equal(lod.splat.count(), 216 + merged)
    var seen = List[Bool](length=216, fill=False)
    for index in lod.source:
        seen[index] = True
    for index in range(216):
        assert_true(seen[index])


def test_splats_at_one_point_make_one_large_leaf() raises:
    """More than `LOD_LEAF` splats of one Morton code are one leaf."""
    var centers = List[Float32]()
    for _ in range(LOD_LEAF + 4):
        centers.append(1)
        centers.append(2)
        centers.append(3)
    var scene = Scene()
    var node = scene.add(Object3D())
    var lod = build_splat_lod(_splats(centers^, 0.1, 255, 0), node)
    assert_equal(len(lod.nodes), 1)
    assert_equal(lod.nodes[0].high, LOD_LEAF + 4)
    assert_equal(lod.nodes[0].children, 0)


def test_no_splats_make_no_tree_and_draw_nothing() raises:
    """An empty geometry has no nodes; a view selects and draws nothing."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var lod = build_splat_lod(GaussianSplatGeometry(), node)
    assert_equal(len(lod.nodes), 0)
    var camera = _camera(10)
    var view = camera.view_matrix_in(scene) * scene.world_matrix(node)
    assert_equal(
        len(select_splats(lod, view, camera.projection_matrix(), HEIGHT, 0)), 0
    )
    var target = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0, 255))
    draw_splat_lod(target, scene, lod, camera)
    assert_equal(target.colors[0].r, 0)


def _selected(
    lod: SplatLod, camera: PerspectiveCamera, scene: Scene, pixels: Float32
) raises -> List[Int]:
    """Return what a camera selects of a tree at the scene's first node."""
    var view = camera.view_matrix_in(scene) * scene.world_matrix(lod.splat.node)
    return select_splats(lod, view, camera.projection_matrix(), HEIGHT, pixels)


def test_a_view_selects_by_size_and_skips_what_it_cannot_see() raises:
    """At 0 pixels every splat in tree order; far away the root's merged
    splat; behind, beside or above the camera nothing; and from inside the
    root's sphere the children decide."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var lod = build_splat_lod(_grid(6, 0.5, 0), node)
    var every = _selected(lod, _camera(20), scene, 0)
    assert_equal(len(every), 216)
    for at in range(216):
        assert_equal(every[at], at)
    var far = _selected(lod, _camera(5000), scene, 2)
    assert_equal(len(far), 1)
    assert_equal(far[0], lod.nodes[0].merged)
    var behind = _camera(-20)
    behind.place(Vector3(0, 0, 20), Vector3(0, 0, 40))
    assert_equal(len(_selected(lod, behind, scene, 2)), 0)
    var beside = _camera(20)
    beside.place(Vector3(40, 0, 20), Vector3(40, 0, 0))
    assert_equal(len(_selected(lod, beside, scene, 2)), 0)
    var above = _camera(20)
    above.place(Vector3(0, 40, 20), Vector3(0, 40, 0))
    assert_equal(len(_selected(lod, above, scene, 2)), 0)
    # Inside the root's sphere the root cannot be drawn whole, however
    # coarse the selection.
    var inside = _selected(lod, _camera(0.5), scene, 1000)
    assert_true(len(inside) > 1)
    # Splats with no harmonics are drawn with their colors alone.
    var target = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0, 255))
    draw_splat_lod(target, scene, lod, _camera(20))
    assert_true(target.colors[(HEIGHT // 2) * WIDTH + WIDTH // 2].r > 0)


def test_more_workers_select_the_same_splats() raises:
    """A selection shared out in subtrees joins in tree order."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var lod = build_splat_lod(_grid(12, 0.25, 0), node)
    var camera = _camera(6)
    var view = camera.view_matrix_in(scene) * scene.world_matrix(node)
    var one = select_splats(lod, view, camera.projection_matrix(), HEIGHT, 1)
    var four = select_splats(
        lod, view, camera.projection_matrix(), HEIGHT, 1, 4
    )
    assert_true(len(one) > 1)
    assert_equal(len(one), len(four))
    for at in range(len(one)):
        assert_equal(one[at], four[at])
    # Far away the root is drawn whole, and no subtree is opened.
    var far = _camera(5000)
    var coarse = select_splats(
        lod,
        far.view_matrix_in(scene) * scene.world_matrix(node),
        far.projection_matrix(),
        HEIGHT,
        2,
        4,
    )
    assert_equal(len(coarse), 1)


def test_more_workers_project_and_draw_the_same_picture() raises:
    """A cloud larger than the view, of every band, drawn on four workers
    and on one, every splat of it: the same splats and the same picture,
    close to the object's own draw."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var lod = build_splat_lod(_grid(22, 0.2, 3), node)
    var camera = _camera(3)
    var depth = DepthMode(0)
    var one = prepare_splat_lod(
        scene, lod, camera, WIDTH, HEIGHT, depth, None, 1, 0
    )
    var four = prepare_splat_lod(
        scene, lod, camera, WIDTH, HEIGHT, depth, None, 4, 0
    )
    assert_true(len(one) >= 2 * LOD_RUN)
    # Some splats of the selected nodes are past the sides of the view.
    assert_true(len(one) < lod.scan_count())
    assert_equal(len(one), len(four))
    for at in range(len(one)):
        assert_true(one[at].x == four[at].x and one[at].y == four[at].y)
        assert_true(one[at].r == four[at].r and one[at].a == four[at].a)
    var alone = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0, 255))
    var shared = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0, 255))
    draw_splat_lod(alone, scene, lod, camera, None, 1, 0)
    draw_splat_lod(shared, scene, lod, camera, None, 4, 0)
    var drawn = 0
    for at in range(len(alone.colors)):
        assert_true(alone.colors[at] == shared.colors[at])
        if alone.colors[at].r > 0:
            drawn += 1
    assert_true(drawn > WIDTH * HEIGHT // 2)
    # The splats of one depth bin keep the tree's order, not the scan's,
    # so the object's own draw differs by little.
    var whole = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0, 255))
    var object = GaussianSplat(_grid(22, 0.2, 3), node)
    draw_gaussian_splat(whole, scene, object, camera)
    var worst = Float32(0)
    for at in range(len(whole.colors)):
        worst = max(worst, abs(whole.colors[at].r - alone.colors[at].r))
    assert_true(worst < 0.05)


def test_a_hidden_node_or_a_bad_target_is_refused_or_drawn_empty() raises:
    """A hidden node draws nothing; a depth mode or a viewport that is not
    valid is refused."""
    var scene = Scene()
    var hidden = Object3D()
    hidden.visible = False
    var node = scene.add(hidden^)
    scene.update()
    var lod = build_splat_lod(_grid(3, 0.5, 0), node)
    var camera = _camera(10)
    assert_equal(
        len(prepare_splat_lod(scene, lod, camera, WIDTH, HEIGHT, DepthMode(0))),
        0,
    )
    with assert_raises(contains="depth mode"):
        _ = prepare_splat_lod(scene, lod, camera, WIDTH, HEIGHT, DepthMode(9))
    with assert_raises(contains="valid viewport"):
        _ = prepare_splat_lod(
            scene,
            lod,
            camera,
            WIDTH,
            HEIGHT,
            DepthMode(0),
            Rect(0, 0, 0, HEIGHT),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
