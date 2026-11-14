# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The GPU rasterizer draws a meadow's frame as the CPU rasterizer does.

Every test here needs a GPU. On a machine with none, each test says that
it is skipped. A skipped run does not show that the two agree.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.scene import Scene
from extensions.vegetation.gpu import MeadowDevice, device_size
from extensions.vegetation.meadow import Meadow
from math.vector3 import Vector3
from render.antialias import SUPERSAMPLE
from render.framebuffer import Framebuffer
from render.gpu import available
from renderers.renderer import Renderer
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from tests.test_vegetation_scene import _camera, _meadow_parameters
from units.si import SECOND, Duration


def _skipped(name: String) -> Bool:
    # An early return looks like a pass, so a skip says so.
    if available():
        return False
    print("SKIP (no accelerator):", name)
    return True


def _mismatches(
    left: Framebuffer, right: Framebuffer, tolerance: Int
) raises -> Int:
    # How many pixels differ by more than the tolerance in a channel.
    assert_equal(left.width, right.width)
    assert_equal(left.height, right.height)
    var count = 0
    for y in range(left.height):
        for x in range(left.width):
            var a = left.get_pixel(x, y)
            var b = right.get_pixel(x, y)
            if (
                abs(Int(a.r) - Int(b.r)) > tolerance
                or abs(Int(a.g) - Int(b.g)) > tolerance
                or abs(Int(a.b) - Int(b.b)) > tolerance
            ):
                count += 1
    return count


def _placed() raises -> PerspectiveCamera:
    # Over the field, looking across the trees toward the mountains.
    var camera = _camera()
    camera.place(Vector3(0, 6, 12), Vector3(0, 1, -6))
    return camera^


def test_the_device_takes_the_renderers_size() raises:
    # This part needs no device.
    var plain = Renderer(16, 9)
    assert_equal(device_size(plain)[0], 16)
    assert_equal(device_size(plain)[1], 9)
    plain.set_antialias(True)
    assert_equal(device_size(plain)[0], 16 * SUPERSAMPLE)
    assert_equal(device_size(plain)[1], 9 * SUPERSAMPLE)


def test_both_backends_draw_a_crowded_meadow_alike() raises:
    if _skipped("both backends draw a crowded meadow alike"):
        return
    var renderer = Renderer(32, 18)
    var assets = Assets()
    var scene = Scene()
    var meadow = Meadow(scene, assets, renderer, _meadow_parameters(True))
    var camera = _placed()
    _ = meadow.update(scene, assets, camera, Duration(1.0, SECOND))
    var device = MeadowDevice(renderer)
    # A frame before the textures are sent is refused.
    with assert_raises(contains="upload"):
        _ = device.draw(renderer, scene, assets, camera)
    device.upload(assets)
    var cpu = renderer.render(scene, assets, camera)
    var gpu = device.draw(renderer, scene, assets, camera)
    assert_equal(_mismatches(cpu, gpu, 1), 0)
    # The wind moves the grass, and the second frame agrees too.
    _ = meadow.update(scene, assets, camera, Duration(1.5, SECOND))
    cpu = renderer.render(scene, assets, camera)
    gpu = device.draw(renderer, scene, assets, camera)
    assert_equal(_mismatches(cpu, gpu, 1), 0)
    # A renderer of another size is refused.
    var other = Renderer(16, 9)
    with assert_raises(contains="one renderer size"):
        _ = device.draw(other, scene, assets, camera)


def test_an_antialiased_meadow_agrees_within_the_resolve() raises:
    if _skipped("an antialiased meadow agrees within the resolve"):
        return
    var renderer = Renderer(32, 18)
    renderer.set_antialias(True)
    var assets = Assets()
    var scene = Scene()
    var meadow = Meadow(scene, assets, renderer, _meadow_parameters(False))
    var camera = _placed()
    _ = meadow.update(scene, assets, camera, Duration(1.0, SECOND))
    var device = MeadowDevice(renderer)
    device.upload(assets)
    var cpu = renderer.render(scene, assets, camera)
    var gpu = device.draw(renderer, scene, assets, camera)
    assert_equal(gpu.width, 32)
    assert_equal(gpu.height, 18)
    # The device averages encoded bytes and the host averages linear
    # light, so an edge pixel can differ by a few levels. See
    # `render.antialias`.
    assert_true(_mismatches(cpu, gpu, 4) * 20 <= 32 * 18)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
