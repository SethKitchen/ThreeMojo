# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.gpu_splat_lod` on a device: a scan kept on the device
must give the picture of the host's `draw_splat_lod`.

A grid of splats, with spherical harmonics of each degree, is drawn from near
and from far, whole and in merged splats, at sizes that are not a whole
number of tiles. A channel may differ by a few levels of 255, where the
device fuses a product that the host does not. Nearly every channel must be
equal. A camera that looks away from the scan draws the background, and a
scene draws frame after frame as the camera moves.
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
from render.framebuffer import Color
from render.gpu_splat_lod import GpuSplatScene
from render.splat_lod import build_splat_lod, draw_splat_lod
from render.working_space import resolve_srgb_working, srgb_working_target
from std.sys import has_accelerator
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Angle, DEGREE, Length, METER

comptime BACKGROUND = Color(7, 8, 15)


def _splats(
    var centers: List[Float32], deviation: Float64, opacity: UInt8, degree: Int
) raises -> GaussianSplatGeometry:
    """Return round splats at centers, in colors that vary, with harmonics
    bytes that count up."""
    var count = len(centers) // 3
    var covariances = List[Float32](length=count * 6, fill=0)
    var colors = List[UInt8]()
    for index in range(count):
        write_covariance(
            covariances,
            index * 6,
            deviation,
            deviation * 0.6,
            deviation * 1.4,
            0.3 * Float64(index % 7),
            0.2,
            0.1 * Float64(index % 5),
            1,
        )
        colors.append(UInt8(60 + (index * 7) % 150))
        colors.append(UInt8(80 + (index * 3) % 120))
        colors.append(UInt8(140))
        colors.append(opacity)
    var bands = List[List[UInt8]]()
    for band in range(1, 4):
        var bytes = List[UInt8]()
        if band <= degree:
            bytes = packed_band(count, band)
            for at in range(len(bytes)):
                bytes[at] = UInt8(100 + (at * 5) % 60)
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


def _camera(
    width: Int, height: Int, z: Float32, looking: Float32
) raises -> PerspectiveCamera:
    """Return a camera on the z axis that looks along it, from `z` toward
    `looking`."""
    var camera = PerspectiveCamera(
        Angle(60, DEGREE),
        Float32(width) / Float32(height),
        Length(0.1, METER),
        Length(1000, METER),
    )
    camera.place(Vector3(0, 0, z), Vector3(0, 0, looking))
    return camera^


def _compare(
    degree: Int, pixels: Float32, z: Float32, width: Int, height: Int
) raises -> Tuple[Int, Int]:
    """Draw a grid on the host and on the device. Return how many channels
    differ, and the largest difference."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var lod = build_splat_lod(_grid(9, 0.5, degree), node)
    var camera = _camera(width, height, z, 0)
    var host = srgb_working_target(width, height, BACKGROUND)
    draw_splat_lod(host, scene, lod, camera, None, 1, pixels)
    var want = resolve_srgb_working(host)
    var device = GpuSplatScene(lod)
    var got = device.draw(
        scene, lod, camera, width, height, BACKGROUND, 4, pixels
    )
    var differing = 0
    var worst = 0
    for at in range(width * height * 4):
        var step = abs(Int(want.pixels[at]) - Int(got.pixels[at]))
        if step > 0:
            differing += 1
        worst = max(worst, step)
    return (differing, worst)


def test_the_device_draws_the_picture_of_the_host() raises:
    """Every splat, with no harmonics: nearly all channels are exact."""
    if not has_accelerator():
        return
    var found = _compare(0, 0, 4, 64, 48)
    assert_true(found[1] <= 3)
    assert_true(found[0] * 100 < 64 * 48 * 4)


def test_the_harmonics_of_each_degree_shade_alike() raises:
    """Degrees 1, 2 and 3 give the host's colors from the device."""
    if not has_accelerator():
        return
    for degree in range(1, 4):
        var found = _compare(degree, 0, 4, 64, 48)
        assert_true(found[1] <= 3)
        assert_true(found[0] * 100 < 64 * 48 * 4)


def test_merged_splats_draw_from_far_and_from_near() raises:
    """At 2.5 pixels the tree draws merged splats from far away and its own
    from near; the device selects what the host selects."""
    if not has_accelerator():
        return
    var far = _compare(1, 2.5, 40, 100, 75)
    assert_true(far[1] <= 3)
    assert_true(far[0] * 100 < 100 * 75 * 4)
    var near = _compare(1, 2.5, 3, 100, 75)
    assert_true(near[1] <= 3)
    assert_true(near[0] * 100 < 100 * 75 * 4)


def test_a_camera_that_looks_away_draws_the_background() raises:
    """With every splat behind the camera, the picture is the clear color."""
    if not has_accelerator():
        return
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var lod = build_splat_lod(_grid(4, 0.5, 0), node)
    var camera = _camera(64, 48, 10, 20)
    var device = GpuSplatScene(lod)
    var got = device.draw(scene, lod, camera, 64, 48, BACKGROUND)
    for at in range(64 * 48):
        assert_equal(got.pixels[at * 4], 7)
        assert_equal(got.pixels[at * 4 + 1], 8)
        assert_equal(got.pixels[at * 4 + 2], 15)
        assert_equal(got.pixels[at * 4 + 3], 255)


def test_a_scene_draws_frame_after_frame_at_two_sizes() raises:
    """One scene draws from three places and then at a larger size, and
    each picture is the host's."""
    if not has_accelerator():
        return
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var lod = build_splat_lod(_grid(9, 0.5, 1), node)
    var device = GpuSplatScene(lod)
    for z in [6.0, 4.0, 2.5]:
        var camera = _camera(64, 48, Float32(z), 0)
        var host = srgb_working_target(64, 48, BACKGROUND)
        draw_splat_lod(host, scene, lod, camera, None, 1)
        var want = resolve_srgb_working(host)
        var got = device.draw(scene, lod, camera, 64, 48, BACKGROUND)
        var worst = 0
        for at in range(64 * 48 * 4):
            worst = max(worst, abs(Int(want.pixels[at]) - Int(got.pixels[at])))
        assert_true(worst <= 3)
    var big = device.draw(
        scene, lod, _camera(160, 90, 4, 0), 160, 90, BACKGROUND
    )
    assert_equal(big.width, 160)


def test_a_scene_refuses_what_it_cannot_draw() raises:
    """A background with alpha, a picture with no pixel, and another scan's
    tree are errors."""
    if not has_accelerator():
        return
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var lod = build_splat_lod(_grid(3, 0.5, 0), node)
    var other = build_splat_lod(_grid(4, 0.5, 0), node)
    var camera = _camera(64, 48, 4, 0)
    var device = GpuSplatScene(lod)
    with assert_raises(contains="needs an opaque background"):
        _ = device.draw(scene, lod, camera, 64, 48, Color(7, 8, 15, 200))
    with assert_raises(contains="at least one pixel each way"):
        _ = device.draw(scene, lod, camera, 0, 48, BACKGROUND)
    with assert_raises(contains="not the scan that the scene holds"):
        _ = device.draw(scene, other, camera, 64, 48, BACKGROUND)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
