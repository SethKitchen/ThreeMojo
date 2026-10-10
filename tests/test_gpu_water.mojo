# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The GPU water shader agrees with the CPU frame."""

from extensions.water.frame import WaterScene, _radiance_image, camera_look
from extensions.water.gpu import GpuWater
from extensions.water.pebbles import PebbleBed
from extensions.water.resolution import SpectrumResolution
from std.sys import has_accelerator
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import RADIAN, SECOND, Angle, Duration


def _skipped(name: String) -> Bool:
    # An early return looks like a pass, so a skip says so.
    if has_accelerator():
        return False
    print("SKIP (no accelerator):", name)
    return True


def _bed() raises -> PebbleBed:
    var pixels = List[Float32](length=32 * 32 * 3, fill=0.0)
    for i in range(len(pixels)):
        pixels[i] = Float32((i * 37) % 23) / 23.0
    return PebbleBed(32, 32, pixels^)


def _scene() raises -> WaterScene:
    var scene = WaterScene(
        SpectrumResolution(64),
        16,
        64,
        SpectrumResolution(4),
        Duration(5.0, SECOND),
    )
    for step in range(6):
        scene.advance(Duration(0.02, SECOND), step % 2 == 0)
    return scene^


def test_gpu_radiance_matches_the_cpu_frame() raises:
    # The device fuses multiplies and adds where the host does not, and its
    # math functions round differently. A last-bit change can flip an
    # anisotropic tap count, a mip clamp or a noise band, so a few values
    # differ a lot. Measured on a TITAN RTX: about 1.3 percent of values
    # differ by more than 1 percent, and 16 of 18432 by more than 10.
    if _skipped("gpu radiance matches the cpu frame"):
        return
    var scene = _scene()
    var bed = _bed()
    var gpu = GpuWater(bed)
    var width = 96
    var height = 64
    for pitch in [Float32(-0.72), Float32(-0.25)]:
        var look = camera_look(scene.clock, True, Angle(pitch, RADIAN))
        var device = gpu.radiance(scene, look, width, height)
        var surface = scene._surface()
        var caustics = scene._caustics(surface)
        var host = _radiance_image(
            look,
            Float32(width) / Float32(height),
            surface,
            scene._ripples,
            caustics,
            bed,
            scene.clock,
            scene.sun,
            width,
            height,
            List[Bool](),
        )
        assert_equal(len(device), len(host))
        var near = 0
        var close = 0
        for i in range(len(host)):
            var d = abs(device[i] - host[i]) / max(abs(host[i]), 1e-2)
            if d <= 1e-2:
                near += 1
            if d <= 1e-1:
                close += 1
        assert_true(near * 100 >= len(host) * 98, String(near))
        assert_true(close * 1000 >= len(host) * 995, String(close))


def test_gpu_radiance_refuses_an_empty_image() raises:
    if _skipped("gpu radiance refuses an empty image"):
        return
    var scene = _scene()
    var gpu = GpuWater(_bed())
    var look = camera_look(scene.clock, False, Angle(-0.72, RADIAN))
    for size in [(0, 4), (4, 0)]:
        with assert_raises(contains="dimensions must be positive"):
            _ = gpu.radiance(scene, look, size[0], size[1])


def test_gpu_frames_keep_device_memory_bounded() raises:
    if _skipped("gpu frames keep device memory bounded"):
        return
    var scene = _scene()
    var gpu = GpuWater(_bed())
    var look = camera_look(scene.clock, False, Angle(-0.72, RADIAN))
    # Two warm-up frames let the device allocator settle.
    for _ in range(2):
        scene.advance(Duration(0.02, SECOND), False)
        _ = gpu.radiance(scene, look, 64, 48)
    var settled = gpu.context.get_memory_info()[0]
    var lowest = settled
    for step in range(40):
        scene.advance(Duration(0.02, SECOND), step % 7 == 0)
        _ = gpu.radiance(scene, look, 64, 48)
        lowest = min(lowest, gpu.context.get_memory_info()[0])
    # Each frame frees its buffers, so free memory does not drift down.
    var after = gpu.context.get_memory_info()[0]
    print("free bytes settled", settled, "lowest", lowest, "after", after)
    assert_true(after + (1 << 20) >= settled)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
