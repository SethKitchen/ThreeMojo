# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Windows, transfer functions and the volume ray caster."""

from extensions.imaging.ids import (
    COMPOSITE,
    MAXIMUM_INTENSITY,
    MONOCHROME1,
    RenderMode,
)
from extensions.imaging.image_volume import ImageVolume, MILLIMETER64
from extensions.imaging.raycast import (
    VolumeCamera,
    orbit_camera,
    ray_box,
    render_volume,
    volume_center,
)
from extensions.imaging.transfer import (
    Rgba,
    TransferFunction,
    WindowLevel,
    clamp_unit,
    corrected_opacity,
)
from extensions.sdf.vector import V3, v3
from render.framebuffer import Framebuffer
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle64, DEGREE64, Length64


def test_window_level() raises:
    var window = WindowLevel(40, 400)
    assert_equal(window.apply(-160), 0)
    assert_equal(window.apply(-500), 0)
    assert_equal(window.apply(241), 1)
    assert_equal(window.apply(40), 0.5)
    assert_almost_equal(window.apply(140), 0.75)
    # A width below one suits values that are not whole numbers.
    var narrow = WindowLevel(0.25, 0.5)
    assert_almost_equal(narrow.apply(0.4), 0.8)
    with assert_raises(contains="center must be finite"):
        _ = WindowLevel(nan[DType.float64](), 1)
    with assert_raises(contains="width must be positive"):
        _ = WindowLevel(0, 0)
    with assert_raises(contains="width must be positive"):
        _ = WindowLevel(0, inf[DType.float64]())


def _same(a: Rgba, b: Rgba) raises:
    assert_almost_equal(a.r, b.r, atol=1e-6)
    assert_almost_equal(a.g, b.g, atol=1e-6)
    assert_almost_equal(a.b, b.b, atol=1e-6)
    assert_almost_equal(a.a, b.a, atol=1e-6)


def test_transfer_function_blends() raises:
    var transfer = TransferFunction()
    with assert_raises(contains="at least one point"):
        _ = transfer.sample(0)
    transfer.add_point(10, Rgba(1, 1, 1, 1))
    transfer.add_point(0, Rgba(0, 0, 0, 0))
    transfer.add_point(5, Rgba(1, 0, 0, 0.5))
    assert_equal(transfer.values[0], 0)
    assert_equal(transfer.values[2], 10)
    _same(transfer.sample(-3), Rgba(0, 0, 0, 0))
    _same(transfer.sample(12), Rgba(1, 1, 1, 1))
    _same(transfer.sample(2.5), Rgba(0.5, 0, 0, 0.25))
    _same(transfer.sample(7.5), Rgba(1, 0.5, 0.5, 0.75))
    var table = transfer.table(0, 10, 3)
    assert_equal(len(table), 3)
    _same(table[1], Rgba(1, 0, 0, 0.5))
    with assert_raises(contains="at least two entries"):
        _ = transfer.table(0, 10, 1)
    with assert_raises(contains="range that rises"):
        _ = transfer.table(10, 10, 4)


def test_transfer_function_refusals() raises:
    var transfer = TransferFunction()
    with assert_raises(contains="finite value"):
        transfer.add_point(inf[DType.float64](), Rgba(0, 0, 0, 0))
    with assert_raises(contains="red must be"):
        transfer.add_point(0, Rgba(-0.1, 0, 0, 0))
    with assert_raises(contains="red must be"):
        transfer.add_point(0, Rgba(1.1, 0, 0, 0))
    with assert_raises(contains="green must be"):
        transfer.add_point(0, Rgba(0, 2, 0, 0))
    with assert_raises(contains="blue must be"):
        transfer.add_point(0, Rgba(0, 0, 2, 0))
    with assert_raises(contains="opacity must be"):
        transfer.add_point(0, Rgba(0, 0, 0, 2))


def test_opacity_correction() raises:
    assert_almost_equal(corrected_opacity(0.25, 1.0), 0.25)
    assert_almost_equal(corrected_opacity(0.25, 2.0), 1 - 0.75 * 0.75)
    assert_almost_equal(corrected_opacity(1.0, 0.5), 1.0)
    assert_equal(clamp_unit(-1), 0)
    assert_equal(clamp_unit(2), 1)
    assert_equal(clamp_unit(0.5), 0.5)


def test_ray_box() raises:
    var low = v3(0, 0, 0)
    var high = v3(1, 1, 1)
    var hit = ray_box(v3(-1, 0.5, 0.5), v3(1, 0, 0), low, high)
    assert_true(hit[0])
    assert_equal(hit[1], 1)
    assert_equal(hit[2], 2)
    # Parallel to a slab and below it, above it, or past the last slab.
    assert_false(ray_box(v3(0.5, -1, 0.5), v3(1, 0, 0), low, high)[0])
    assert_false(ray_box(v3(0.5, 2, 0.5), v3(1, 0, 0), low, high)[0])
    assert_false(ray_box(v3(0.5, 0.5, 2), v3(1, 0, 0), low, high)[0])
    assert_false(ray_box(v3(2, 0.5, 0.5), v3(0, 1, 0), low, high)[0])
    # A slanted ray that passes the box.
    assert_false(ray_box(v3(-1, 2, 0.5), v3(1, 1, 0), low, high)[0])
    # From inside, the near distance is zero.
    var inside = ray_box(v3(0.5, 0.5, 0.5), v3(0, 0, 1), low, high)
    assert_true(inside[0])
    assert_equal(inside[1], 0)
    assert_equal(inside[2], 0.5)


def test_camera_refusals() raises:
    var eye = v3(0, 0, -1)
    var target = v3(0, 0, 0)
    var up = v3(0, -1, 0)
    var field = Angle64(30, DEGREE64)
    with assert_raises(contains="at least one pixel"):
        _ = VolumeCamera(eye, target, up, field, 0, 4)
    with assert_raises(contains="at least one pixel"):
        _ = VolumeCamera(eye, target, up, field, 4, 0)
    with assert_raises(contains="8192"):
        _ = VolumeCamera(eye, target, up, field, 8193, 4)
    with assert_raises(contains="8192"):
        _ = VolumeCamera(eye, target, up, field, 4, 8193)
    with assert_raises(contains="field of view"):
        _ = VolumeCamera(eye, target, up, Angle64(0, DEGREE64), 4, 4)
    with assert_raises(contains="field of view"):
        _ = VolumeCamera(eye, target, up, Angle64(180, DEGREE64), 4, 4)
    with assert_raises(contains="eye cannot be at its target"):
        _ = VolumeCamera(eye, eye, up, field, 4, 4)
    with assert_raises(contains="up cannot lie along"):
        _ = VolumeCamera(eye, target, v3(0, 0, 2), field, 4, 4)
    var camera = VolumeCamera(eye, target, up, field, 5, 3)
    var center = camera.ray(2, 1)
    assert_almost_equal(center.z, 1)
    assert_true(camera.ray(0, 0).x < 0)
    assert_true(camera.ray(0, 0).y < 0)


def _uniform(value: Float32) raises -> ImageVolume:
    var spacing = Length64(1, MILLIMETER64)
    var volume = ImageVolume(4, 4, 4, spacing, spacing, spacing)
    for index in range(volume.count()):
        volume.values[index] = value
    return volume^


def _look_along_z(volume: ImageVolume, size: Int) raises -> VolumeCamera:
    var center = volume_center(volume)
    return VolumeCamera(
        center - v3(0, 0, 1),
        center,
        v3(0, -1, 0),
        Angle64(0.2, DEGREE64),
        size,
        size,
    )


def _gray(image: Framebuffer, x: Int, y: Int) raises -> Int:
    return Int(image.get_pixel(x, y).r)


def test_composite_matches_the_analytic_opacity() raises:
    var volume = _uniform(1)
    var transfer = TransferFunction()
    transfer.add_point(1, Rgba(1, 1, 1, 0.25))
    var camera = _look_along_z(volume, 5)
    var image = render_volume(
        volume, camera, transfer, COMPOSITE, 0.5, 1, Rgba(0, 0, 0, 1)
    )
    # Four voxels of 0.25 opacity each pass 0.75^4 of the background.
    var expected = (1 - 0.75**4) * 255
    assert_true(abs(Float64(_gray(image, 2, 2)) - expected) <= 0.6)
    var white = render_volume(
        volume, camera, transfer, COMPOSITE, 1, 1, Rgba(1, 1, 1, 1)
    )
    assert_equal(_gray(white, 2, 2), 255)


def test_composite_stops_when_opaque_and_skips_clear_samples() raises:
    var volume = _uniform(0)
    for j in range(4):
        for i in range(4):
            volume.set(i, j, 1, 10)
    var transfer = TransferFunction()
    transfer.add_point(0, Rgba(0, 0, 0, 0))
    transfer.add_point(1, Rgba(0, 1, 0, 1))
    var camera = _look_along_z(volume, 3)
    var image = render_volume(
        volume, camera, transfer, COMPOSITE, 0.5, 0.2, Rgba(1, 0, 0, 1)
    )
    var pixel = image.get_pixel(1, 1)
    # The second layer is opaque green, so the ray stops inside the box.
    # The clear front lets it show.
    assert_equal(Int(pixel.g), 255)
    assert_equal(Int(pixel.r), 0)


def test_shading_follows_the_gradient() raises:
    var spacing = Length64(1, MILLIMETER64)
    var volume = ImageVolume(4, 4, 4, spacing, spacing, spacing)
    for k in range(4):
        for j in range(4):
            for i in range(4):
                volume.set(i, j, k, Float32(k))
    var transfer = TransferFunction()
    transfer.add_point(0, Rgba(1, 1, 1, 0.3))
    var center = volume_center(volume)
    var along = VolumeCamera(
        center - v3(0, 0, 1),
        center,
        v3(0, -1, 0),
        Angle64(0.2, DEGREE64),
        3,
        3,
    )
    var across = VolumeCamera(
        center - v3(1, 0, 0),
        center,
        v3(0, -1, 0),
        Angle64(0.2, DEGREE64),
        3,
        3,
    )
    var lit = render_volume(
        volume, along, transfer, COMPOSITE, 0.5, 0.1, Rgba(0, 0, 0, 1)
    )
    var dim = render_volume(
        volume, across, transfer, COMPOSITE, 0.5, 0.1, Rgba(0, 0, 0, 1)
    )
    # A ray along the gradient faces it. A ray across it gets the ambient.
    assert_true(_gray(lit, 1, 1) > 3 * _gray(dim, 1, 1))


def test_maximum_intensity() raises:
    var volume = _uniform(0)
    volume.set(1, 2, 2, 10)
    volume.window_center = 5
    volume.window_width = 10
    var transfer = TransferFunction()
    transfer.add_point(0, Rgba(0, 0, 0, 0))
    var spacing = volume.spacing_x
    var center = v3(
        1 * spacing.to(MILLIMETER64) / 1000,
        2 * spacing.to(MILLIMETER64) / 1000,
        0.0015,
    )
    var camera = VolumeCamera(
        center - v3(0, 0, 1),
        center,
        v3(0, -1, 0),
        Angle64(0.01, DEGREE64),
        1,
        1,
    )
    var image = render_volume(
        volume, camera, transfer, MAXIMUM_INTENSITY, 1, 1, Rgba(0, 0, 1, 1)
    )
    assert_equal(_gray(image, 0, 0), 255)
    volume.photometric = MONOCHROME1
    image = render_volume(
        volume, camera, transfer, MAXIMUM_INTENSITY, 1, 1, Rgba(0, 0, 1, 1)
    )
    assert_equal(_gray(image, 0, 0), 0)
    assert_equal(Int(image.get_pixel(0, 0).b), 0)


def test_misses_show_the_background_and_threads_agree() raises:
    var volume = _uniform(1)
    var transfer = TransferFunction()
    transfer.add_point(1, Rgba(1, 1, 1, 0.5))
    var camera = orbit_camera(
        volume,
        Angle64(30, DEGREE64),
        Angle64(20, DEGREE64),
        Angle64(40, DEGREE64),
        16,
        12,
    )
    var one = render_volume(
        volume,
        camera,
        transfer,
        COMPOSITE,
        1,
        0.5,
        Rgba(0, 0, 1, 1),
        threads=1,
    )
    var three = render_volume(
        volume,
        camera,
        transfer,
        COMPOSITE,
        1,
        0.5,
        Rgba(0, 0, 1, 1),
        threads=3,
    )
    var every = render_volume(
        volume, camera, transfer, COMPOSITE, 1, 0.5, Rgba(0, 0, 1, 1)
    )
    for index in range(len(one.pixels)):
        assert_equal(one.pixels[index], three.pixels[index])
        assert_equal(one.pixels[index], every.pixels[index])
    # The corner sees the background; the center sees the volume.
    assert_equal(Int(one.get_pixel(0, 0).b), 255)
    assert_true(Int(one.get_pixel(8, 6).r) > 0)
    with assert_raises(contains="quarter turn"):
        _ = orbit_camera(
            volume,
            Angle64(0, DEGREE64),
            Angle64(90, DEGREE64),
            Angle64(40, DEGREE64),
            4,
            4,
        )


def test_crop_removes_part_of_the_box() raises:
    var volume = _uniform(1)
    var transfer = TransferFunction()
    transfer.add_point(1, Rgba(1, 1, 1, 0.25))
    var camera = _look_along_z(volume, 5)
    var half = render_volume(
        volume,
        camera,
        transfer,
        COMPOSITE,
        0.5,
        1,
        Rgba(0, 0, 0, 1),
        v3(0, 0, 0.5),
        v3(1, 1, 1),
    )
    # Two voxels of the four are left.
    var expected = (1 - 0.75**2) * 255
    assert_true(abs(Float64(_gray(half, 2, 2)) - expected) <= 0.6)


def test_render_refusals() raises:
    var volume = _uniform(1)
    var transfer = TransferFunction()
    transfer.add_point(1, Rgba(1, 1, 1, 1))
    var camera = _look_along_z(volume, 2)
    var black = Rgba(0, 0, 0, 1)
    with assert_raises(contains="render mode"):
        _ = render_volume(volume, camera, transfer, RenderMode(5), 1, 1, black)
    with assert_raises(contains="ray step"):
        _ = render_volume(volume, camera, transfer, COMPOSITE, 0.01, 1, black)
    with assert_raises(contains="ray step"):
        _ = render_volume(volume, camera, transfer, COMPOSITE, 5, 1, black)
    with assert_raises(contains="ambient"):
        _ = render_volume(volume, camera, transfer, COMPOSITE, 1, -1, black)
    with assert_raises(contains="ambient"):
        _ = render_volume(volume, camera, transfer, COMPOSITE, 1, 2, black)
    with assert_raises(contains="crop"):
        _ = render_volume(
            volume,
            camera,
            transfer,
            COMPOSITE,
            1,
            1,
            black,
            v3(-0.1, 0, 0),
            v3(1, 1, 1),
        )
    with assert_raises(contains="crop"):
        _ = render_volume(
            volume,
            camera,
            transfer,
            COMPOSITE,
            1,
            1,
            black,
            v3(0, 0, 0),
            v3(1, 1.5, 1),
        )
    with assert_raises(contains="crop"):
        _ = render_volume(
            volume,
            camera,
            transfer,
            COMPOSITE,
            1,
            1,
            black,
            v3(0, 0, 0.5),
            v3(1, 1, 0.5),
        )
    with assert_raises(contains="thread count"):
        _ = render_volume(
            volume, camera, transfer, COMPOSITE, 1, 1, black, threads=-1
        )
    with assert_raises(contains="at least one point"):
        _ = render_volume(
            volume, camera, TransferFunction(), COMPOSITE, 1, 1, black
        )
    volume.window_width = 0
    with assert_raises(contains="width must be positive"):
        _ = render_volume(volume, camera, transfer, COMPOSITE, 1, 1, black)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
