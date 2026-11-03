# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.virtual`, splats made from pictures with depth.

The pictures are of a plane, made here with the depth that a renderer would
store: each pixel's ray meets the plane z = 0, and the point's NDC depth is
written. So the scan must lie in the plane, face the camera, have the
picture's colors, take no sample from the edge of a surface, and keep one
splat for each cell.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.gaussian_splat_utils import GaussianSplatGeometry
from extensions.scan.virtual import (
    SPLAT_ROW,
    VirtualScan,
    VirtualScanOptions,
    default_virtual_scan_options,
)
from loaders.splat import parse_splat
from math.matrix4 import Matrix4, translation
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import inf, nan, sqrt
from std.os import remove, rmdir
from std.pathlib import Path
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, Length64, METER

comptime WIDTH = 32
comptime HEIGHT = 24


def _camera(eye: Vector3) raises -> PerspectiveCamera:
    """Return a camera at a point that looks at the origin."""
    var camera = PerspectiveCamera(
        Angle(60, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100, METER),
    )
    camera.place(eye, Vector3(0, 0, 0))
    return camera^


def _picture(
    camera: PerspectiveCamera, eye: Vector3, step_at: Int
) raises -> Framebuffer:
    """Return what a renderer stores for the plane z = 0: a color that
    varies, and the NDC depth of the plane's point under each pixel. From
    column `step_at` on, the plane is 3 m lower."""
    var projection = camera.projection_matrix()
    var view = camera.view_matrix()
    var clip = projection * view
    var inverse = clip
    inverse.invert()
    var image = Framebuffer(WIDTH, HEIGHT, Color(0, 0, 0))
    for y in range(HEIGHT):
        for x in range(WIDTH):
            var ndc_x = (Float32(x) + 0.5) / Float32(WIDTH) * 2 - 1
            var ndc_y = 1 - (Float32(y) + 0.5) / Float32(HEIGHT) * 2
            var far = inverse.transform_point(Vector3(ndc_x, ndc_y, 0.5))
            var ray = far - eye
            var level = Float32(0)
            if x >= step_at:
                level = -3
            var t = (level - eye.z) / ray.z
            if t <= 0:
                continue
            var point = eye + ray * t
            image.depth[y * WIDTH + x] = clip.transform_point(point).z
            image.set_pixel(x, y, Color(UInt8(x * 7), UInt8(y * 9), 120))
    return image^


def _scan(voxel: Float64) raises -> VirtualScan:
    """Return an empty scan with a cell of the given edge."""
    var options = default_virtual_scan_options()
    options.voxel = Length64(voxel, METER)
    return VirtualScan(options)


def test_a_plane_gives_splats_that_lie_in_it() raises:
    """Every sample is a splat in the plane, facing the camera, with the
    pixel's color."""
    var eye = Vector3(0, 0, 5)
    var camera = _camera(eye)
    var scan = _scan(0.001)
    var taken = scan.add_view(
        _picture(camera, eye, WIDTH),
        camera.view_matrix(),
        camera.projection_matrix(),
    )
    assert_equal(taken, (WIDTH - 1) * (HEIGHT - 1))
    assert_equal(scan.count(), taken)
    assert_equal(scan.views, 1)
    assert_equal(scan.samples, taken)
    for place in range(scan.count()):
        assert_almost_equal(scan.centers[place * 3 + 2], 0, atol=2e-3)
        assert_almost_equal(scan.normals[place * 3 + 2], 1, atol=1e-3)
        assert_equal(scan.colors[place * 4 + 3], 240)
    assert_true(scan.colors[0] == 0 and scan.colors[1] == 0)


def test_a_cell_keeps_one_splat() raises:
    """A coarse cell takes the best sample of many, and a second view of the
    same plane adds samples but few splats."""
    var eye = Vector3(0, 0, 5)
    var camera = _camera(eye)
    var coarse = _scan(1.0)
    var first = coarse.add_view(
        _picture(camera, eye, WIDTH),
        camera.view_matrix(),
        camera.projection_matrix(),
    )
    assert_true(coarse.count() < first / 10)
    var near = Vector3(0.5, 0.5, 4)
    var other = _camera(near)
    var fine = _scan(0.2)
    var one = fine.add_view(
        _picture(camera, eye, WIDTH),
        camera.view_matrix(),
        camera.projection_matrix(),
    )
    var before = fine.count()
    var two = fine.add_view(
        _picture(other, near, WIDTH),
        other.view_matrix(),
        other.projection_matrix(),
    )
    assert_equal(fine.samples, one + two)
    assert_true(fine.count() < before + two)
    assert_true(fine.count() >= before)


def test_the_edge_of_a_surface_gives_no_sample() raises:
    """Across a step of 3 m the neighbors are too far apart, and the pixels
    that straddle it are left out."""
    var eye = Vector3(0, 0, 5)
    var camera = _camera(eye)
    var scan = _scan(0.001)
    var taken = scan.add_view(
        _picture(camera, eye, 16),
        camera.view_matrix(),
        camera.projection_matrix(),
    )
    assert_true(taken <= (WIDTH - 1) * (HEIGHT - 1) - (HEIGHT - 1))
    assert_true(taken > (WIDTH - 1) * (HEIGHT - 1) - 2 * (HEIGHT - 1))


def test_a_grazing_surface_gives_fewer_samples() raises:
    """Seen almost edge on, the plane gives fewer samples with a higher
    grazing limit."""
    var eye = Vector3(0, -4, 1.5)
    var camera = _camera(eye)
    var low = default_virtual_scan_options()
    # The picture is 32 pixels wide, so its neighbors are far apart.
    low.edge = 1
    low.grazing = 0
    low.voxel = Length64(0.001, METER)
    var all = VirtualScan(low)
    var many = all.add_view(
        _picture(camera, eye, WIDTH),
        camera.view_matrix(),
        camera.projection_matrix(),
    )
    var high = low
    high.grazing = 0.6
    var strict = VirtualScan(high)
    var few = strict.add_view(
        _picture(camera, eye, WIDTH),
        camera.view_matrix(),
        camera.projection_matrix(),
    )
    assert_true(many > 0)
    assert_true(few < many)


def test_a_picture_with_no_surface_gives_nothing() raises:
    """A picture of the sky is no scan."""
    var camera = _camera(Vector3(0, 0, 5))
    var scan = _scan(0.1)
    var sky = Framebuffer(WIDTH, HEIGHT, Color(0, 0, 0))
    assert_equal(
        scan.add_view(sky, camera.view_matrix(), camera.projection_matrix()), 0
    )
    assert_equal(scan.count(), 0)
    with assert_raises(contains="the views gave no splat"):
        _ = scan.geometry()
    with assert_raises(contains="the views gave no splat"):
        _ = scan.splat_bytes()


def test_the_scan_is_splats_and_a_splat_file() raises:
    """The geometry has one splat for each sample, flat in the plane, and the
    `.splat` bytes read back as the same splats."""
    var eye = Vector3(0, 0, 5)
    var camera = _camera(eye)
    var scan = _scan(0.001)
    _ = scan.add_view(
        _picture(camera, eye, WIDTH),
        camera.view_matrix(),
        camera.projection_matrix(),
    )
    var geometry = scan.geometry()
    assert_equal(geometry.count(), scan.count())
    var bytes = scan.splat_bytes()
    assert_equal(len(bytes), scan.count() * SPLAT_ROW)
    var read = parse_splat(bytes)
    assert_equal(read.count(), scan.count())
    for place in range(scan.count()):
        for lane in range(3):
            assert_equal(
                read.centers[place * 3 + lane],
                geometry.centers[place * 3 + lane],
            )
        for lane in range(4):
            assert_equal(
                read.colors[place * 4 + lane], geometry.colors[place * 4 + lane]
            )
        # Flat: little spread across the plane, a great deal in it.
        var across = geometry.covariances[place * 6 + 5]
        var along = (
            geometry.covariances[place * 6]
            + geometry.covariances[place * 6 + 3]
        )
        assert_true(across < along / 4)
        var rotated = read.covariances[place * 6 + 5]
        assert_true(rotated < along / 3)


def _five_by_five() raises -> Framebuffer:
    """Return a picture of five pixels a side, every depth 0.3, for the
    identity camera: the point of a pixel is its place in NDC."""
    var image = Framebuffer(5, 5, Color(90, 90, 90))
    for at in range(25):
        image.depth[at] = 0.3
    return image^


def test_the_pixels_that_are_no_surface_make_no_quad() raises:
    """A depth behind the near plane, or none, leaves a pixel out, and a quad
    needs its pixel and the two beside it."""
    var image = _five_by_five()
    # In front of the near plane at (2, 0), nothing at (4, 0) and (0, 4).
    image.depth[2] = -1.5
    image.depth[4] = inf[DType.float32]()
    image.depth[4 * 5] = inf[DType.float32]()
    var options = default_virtual_scan_options()
    options.edge = 100
    var scan = VirtualScan(options)
    var taken = scan.add_view(image, Matrix4(), Matrix4())
    # Of 16 quads, (1, 0) and (2, 0) use (2, 0), (3, 0) uses (4, 0) and
    # (0, 3) uses (0, 4).
    assert_equal(taken, 12)
    assert_equal(scan.views, 1)


def test_a_surface_at_the_eye_has_no_direction() raises:
    """A point at the eye gives no sample, and the quads that lean on it are
    seen edge on."""
    var image = _five_by_five()
    image.depth[2 * 5 + 2] = 0
    var options = default_virtual_scan_options()
    options.edge = 100
    var scan = VirtualScan(options)
    # The quads (2, 2), (1, 2) and (2, 1) are lost.
    assert_equal(scan.add_view(image, Matrix4(), Matrix4()), 13)


def test_a_jump_below_a_pixel_is_the_edge_of_a_surface() raises:
    """A neighbor much farther away than the pixel gives no sample."""
    var image = _five_by_five()
    image.depth[4 * 5 + 1] = 0.99
    var options = default_virtual_scan_options()
    options.edge = 1
    var scan = VirtualScan(options)
    assert_equal(scan.add_view(image, Matrix4(), Matrix4()), 15)


def test_points_too_far_out_to_tell_apart_have_no_quad() raises:
    """Float32 cannot tell a point of a billion meters from its neighbor, so
    the pixels give no area and no sample."""
    var image = _five_by_five()
    var scan = VirtualScan(default_virtual_scan_options())
    var far = translation(-1.0e9, -1.0e9, 0)
    assert_equal(scan.add_view(image, far, Matrix4()), 0)
    assert_equal(scan.count(), 0)


def test_a_scan_is_written_as_a_splat_file() raises:
    """The file holds what `splat_bytes` gives."""
    var eye = Vector3(0, 0, 5)
    var camera = _camera(eye)
    var scan = _scan(0.05)
    _ = scan.add_view(
        _picture(camera, eye, WIDTH),
        camera.view_matrix(),
        camera.projection_matrix(),
    )
    var directory = mkdtemp(prefix="virtual scan ")
    var path = directory + "/plane.splat"
    scan.write(path)
    var written = Path(path).read_bytes()
    var expected = scan.splat_bytes()
    assert_equal(len(written), len(expected))
    for at in range(len(expected)):
        assert_equal(written[at], expected[at])
    remove(path)
    rmdir(directory)


def test_the_options_must_make_a_scan() raises:
    """Each number is checked."""
    var good = default_virtual_scan_options()
    good.check()
    var bad = good
    bad.voxel = Length64(0, METER)
    with assert_raises(contains="the voxel must be positive"):
        bad.check()
    bad = good
    bad.edge = 0
    with assert_raises(contains="the edge must be positive"):
        bad.check()
    bad = good
    bad.spread = -1
    with assert_raises(contains="the spread must be positive"):
        bad.check()
    bad = good
    bad.thin = 0
    with assert_raises(contains="the thickness must be positive"):
        bad.check()
    bad = good
    bad.grazing = nan[DType.float64]()
    with assert_raises(contains="the grazing cosine must be finite"):
        bad.check()
    bad = good
    bad.grazing = 1
    with assert_raises(contains="the grazing cosine is 0 up to 1"):
        bad.check()
    bad = good
    bad.grazing = -0.1
    with assert_raises(contains="the grazing cosine is 0 up to 1"):
        bad.check()
    bad = good
    bad.voxel = Length64(0, METER)
    with assert_raises(contains="the voxel must be positive"):
        _ = VirtualScan(bad)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
