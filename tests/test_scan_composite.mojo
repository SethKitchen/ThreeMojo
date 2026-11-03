# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.scan.composite`: a scan blended into a picture that
a mesh scene has drawn.

The site of `tests/_scan_site.mojo` is the scan. It stands in front of a
camera, and the picture has a gray ground and a depth. The scan must show
where nothing is nearer, hide where a surface is nearer, and turn with its
heading.
"""

from cameras.perspective_camera import PerspectiveCamera
from extensions.scan.composite import composite_splats, splat_layer
from extensions.scan.frame import (
    SCALE_DECLARED,
    SCAN_POSITIVE_Y,
    SCAN_POSITIVE_Z,
    ScanFrame,
)
from generators.utils import Vec3d
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.testing import TestSuite, assert_equal, assert_true
from tests._scan_site import site_scan
from units.si import Angle, Angle64, DEGREE, Length, Length64, METER, RADIAN

comptime SIZE = 48


def _frame() -> ScanFrame:
    """Return the frame of the site: scan axes are the building's."""
    return ScanFrame(
        SCAN_POSITIVE_Z,
        SCAN_POSITIVE_Y,
        Length64(1.0, METER),
        SCALE_DECLARED,
        Angle64(0.0, RADIAN),
        Vec3d(0, 0, 0),
    )


def _camera() raises -> PerspectiveCamera:
    """Return a camera that looks down at the middle of the site."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1.0, Length(0.5, METER), Length(300.0, METER)
    )
    camera.place(Vector3(0, 22, 42), Vector3(0, 3, 0))
    return camera^


def _gray() raises -> Framebuffer:
    """Return a gray picture with nothing in front of any pixel."""
    return Framebuffer(SIZE, SIZE, Color(80, 80, 80))


def _changed(image: Framebuffer, column_from: Int, column_to: Int) -> Int:
    """Count the pixels, in a range of columns, that are no longer gray."""
    var count = 0
    for row in range(SIZE):
        for column in range(column_from, column_to):
            var at = (row * SIZE + column) * 4
            if (
                image.pixels[at] != 80
                or image.pixels[at + 1] != 80
                or image.pixels[at + 2] != 80
            ):
                count += 1
    return count


def test_a_layer_knows_the_size_of_its_scan() raises:
    var layer = splat_layer(
        site_scan(SCAN_POSITIVE_Z, True), _frame(), 0.0, 0.0, 0.0, 0.0
    )
    # The ground is 30 m a side, the box of walls stands 5 m on it.
    assert_true(layer.width > 25.0 and layer.width < 40.0)
    assert_true(layer.depth > 25.0 and layer.depth < 40.0)
    assert_true(layer.height > 4.0 and layer.height < 12.0)


def test_a_scan_shows_where_nothing_is_nearer() raises:
    var layer = splat_layer(
        site_scan(SCAN_POSITIVE_Z, True), _frame(), 0.0, 0.0, 0.0, 0.0
    )
    var image = _gray()
    var drawn = composite_splats(image, layer, _camera(), 1)
    assert_true(drawn > 0)
    assert_true(_changed(image, 0, SIZE) > 300)


def test_a_surface_that_is_nearer_hides_the_scan() raises:
    var layer = splat_layer(
        site_scan(SCAN_POSITIVE_Z, True), _frame(), 0.0, 0.0, 0.0, 0.0
    )
    var image = _gray()
    # The left half has a surface just in front of the camera.
    for row in range(SIZE):
        for column in range(SIZE // 2):
            image.depth[row * SIZE + column] = -0.9999
    _ = composite_splats(image, layer, _camera(), 1)
    assert_equal(_changed(image, 0, SIZE // 2), 0)
    assert_true(_changed(image, SIZE // 2, SIZE) > 100)


def test_a_scan_is_set_down_where_it_is_told_and_turns() raises:
    var straight = _gray()
    var layer = splat_layer(
        site_scan(SCAN_POSITIVE_Z, True), _frame(), 0.0, 0.0, 0.0, 0.0
    )
    _ = composite_splats(straight, layer, _camera(), 1)
    # Turned about the vertical by half a radian, the walls are elsewhere.
    var turned = _gray()
    var other = splat_layer(
        site_scan(SCAN_POSITIVE_Z, True), _frame(), 0.0, 0.0, 0.0, 0.5
    )
    _ = composite_splats(turned, other, _camera(), 1)
    var different = 0
    for at in range(SIZE * SIZE * 4):
        if straight.pixels[at] != turned.pixels[at]:
            different += 1
    assert_true(different > 50)
    # Set down 200 m east, out of the camera's view, it draws nothing.
    var away = _gray()
    var far = splat_layer(
        site_scan(SCAN_POSITIVE_Z, True), _frame(), 200.0, 0.0, 0.0, 0.0
    )
    _ = composite_splats(away, far, _camera(), 1)
    assert_equal(_changed(away, 0, SIZE), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
