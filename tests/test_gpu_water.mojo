# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The GPU water shader agrees with the CPU frame and holds no resources.

The device fuses multiplies and adds where the host does not, and its math
functions round differently. A last-bit change can flip an anisotropic tap
count, a mip clamp or a noise band, so a few values differ a lot. Each
comparison uses the difference over max(|CPU value|, 0.01): relative for
bright values, absolute near black. On a TITAN RTX about 1.3 percent of
values differ by more than 1 percent, and under 0.1 percent by more than
10 percent. No value may differ by more than 2.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.water.frame import WaterScene, _radiance_image, camera_look
from extensions.water.gpu import GpuWater
from extensions.water.optics import hash12
from extensions.water.pebbles import PebbleBed
from extensions.water.resolution import SpectrumResolution
from extensions.water.view import CAUSTICS, FRAME
from geometries.sphere import sphere
from materials.material import BASIC, Material
from math.vector3 import Vector3
from max.gpu.host import DeviceContext
from objects.mesh import Mesh
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.math import isfinite
from std.memory import bitcast
from std.pathlib import Path
from std.ffi import external_call
from std.sys import (
    CompilationTarget,
    has_accelerator,
    has_apple_gpu_accelerator,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import DEGREE, METER, RADIAN, SECOND, Angle, Duration, Length


def _skipped(name: String) -> Bool:
    # An early return looks like a pass, so a skip says so.
    if has_accelerator():
        return False
    print("SKIP (no GPU):", name)
    return True


def _bed() raises -> PebbleBed:
    var pixels = List[Float32](length=32 * 32 * 3, fill=0.0)
    for i in range(len(pixels)):
        pixels[i] = Float32((i * 37) % 23) / 23.0
    return PebbleBed(32, 32, pixels^)


def _scene() raises -> WaterScene:
    # A 64-texel window lets the center tap raise real ripples.
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


def _agree(device: List[Float32], host: List[Float32]) raises:
    """Check that every value is finite and that the two images agree."""
    assert_equal(len(device), len(host))
    var near = 0
    var close = 0
    var worst = Float32(0)
    for i in range(len(host)):
        assert_true(isfinite(host[i]) and isfinite(device[i]))
        var d = abs(device[i] - host[i]) / max(abs(host[i]), 1e-2)
        worst = max(worst, d)
        if d <= 1e-2:
            near += 1
        if d <= 1e-1:
            close += 1
    assert_true(near * 100 >= len(host) * 98, String(near))
    assert_true(close * 1000 >= len(host) * 995, String(close))
    assert_true(worst <= 2.0, String(worst))


def _cpu(
    scene: WaterScene, bed: PebbleBed, pitch: Float32, w: Int, h: Int
) raises -> List[Float32]:
    var look = camera_look(scene.clock, True, Angle(pitch, RADIAN))
    var surface = scene._surface()
    var caustics = scene._caustics(surface)
    return _radiance_image(
        look,
        Float32(w) / Float32(h),
        surface,
        scene._ripples,
        caustics,
        bed,
        scene.clock,
        scene.sun,
        w,
        h,
        List[Bool](),
    )


def _gpu(
    mut gpu: GpuWater, scene: WaterScene, pitch: Float32, w: Int, h: Int
) raises -> List[Float32]:
    var look = camera_look(scene.clock, True, Angle(pitch, RADIAN))
    return gpu.radiance(scene, look, w, h)


def test_gpu_radiance_matches_the_cpu_frame() raises:
    if _skipped("gpu radiance matches the cpu frame"):
        return
    var scene = _scene()
    var bed = _bed()
    var gpu = GpuWater(bed)
    # A tile-aligned size and an odd size that leaves partial tiles.
    for size in [(96, 64), (97, 61)]:
        for pitch in [Float32(-0.72), Float32(-0.25)]:
            _agree(
                _gpu(gpu, scene, pitch, size[0], size[1]),
                _cpu(scene, bed, pitch, size[0], size[1]),
            )


def test_gpu_radiance_follows_reset_and_lighting() raises:
    if _skipped("gpu radiance follows reset and lighting"):
        return
    var scene = _scene()
    var bed = _bed()
    var gpu = GpuWater(bed)
    var before = _gpu(gpu, scene, -0.72, 48, 32)
    # A new sun changes the picture, and the device follows it.
    scene.set_sun(Vector3(-0.4, 0.5, 0.6))
    var lit = _gpu(gpu, scene, -0.72, 48, 32)
    _agree(lit, _cpu(scene, bed, -0.72, 48, 32))
    var changed = 0
    for i in range(len(lit)):
        if lit[i] != before[i]:
            changed += 1
    assert_true(changed * 2 > len(lit))
    # After a reset the calm window and the start clock are shaded.
    scene.reset()
    _agree(_gpu(gpu, scene, -0.72, 48, 32), _cpu(scene, bed, -0.72, 48, 32))


def test_gpu_draw_matches_the_cpu_draw() raises:
    if _skipped("gpu draw matches the cpu draw"):
        return
    var bed = _bed()
    var gpu = GpuWater(bed)
    var pitch = Angle(-0.72, RADIAN)
    for view in [FRAME, CAUSTICS]:
        var a = _scene()
        var b = _scene()
        var device = gpu.draw(a, 64, 48, view, True, pitch)
        var host = b.draw(64, 48, view, True, bed, pitch)
        var far = 0
        for y in range(48):
            for x in range(64):
                var p = device.get_pixel(x, y)
                var q = host.get_pixel(x, y)
                var d = max(
                    abs(Int(p.r) - Int(q.r)),
                    max(abs(Int(p.g) - Int(q.g)), abs(Int(p.b) - Int(q.b))),
                )
                if view == CAUSTICS:
                    # Caustics do not shade, so they match exactly.
                    assert_equal(d, 0)
                elif d > 2:
                    far += 1
        assert_true(far * 100 <= 64 * 48 * 2, String(far))
    with assert_raises(contains="dimensions must be positive"):
        var c = _scene()
        _ = gpu.draw(c, 0, 4, FRAME, True, pitch)


def _ball() raises -> Tuple[Scene, Assets, PerspectiveCamera]:
    var assets = Assets()
    var world = Scene()
    var node = world.add(Object3D())
    world.node(node).set_position(0, 0.6, -2.5)
    var paint = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    world.add_mesh(
        Mesh(
            assets.geometries.add(sphere(Length(0.35, METER), 12, 8)),
            paint,
            node,
        )
    )
    world.update()
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE),
        Float32(40) / Float32(30),
        Length(0.05, METER),
        Length(200.0, METER),
    )
    camera.place(Vector3(0, 1.2, 0), Vector3(0, 0.4, -3))
    return (world^, assets^, camera^)


def _channels(a: Color, b: Color) -> Int:
    return max(
        abs(Int(a.r) - Int(b.r)),
        max(abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b))),
    )


def test_gpu_compose_matches_the_cpu_compose() raises:
    if _skipped("gpu compose matches the cpu compose"):
        return
    var bed = _bed()
    var gpu = GpuWater(bed)
    var parts = _ball()
    var renderer = Renderer(40, 30)
    renderer.set_background(Color(0, 0, 0))
    var scene_only = renderer.render(parts[0], parts[1], parts[2])
    var device = renderer.render(parts[0], parts[1], parts[2])
    var host = renderer.render(parts[0], parts[1], parts[2])
    var water = _scene()
    var a = gpu.compose(water, device, parts[0], parts[2], Length(0.0, METER))
    var b = water.compose(host, parts[0], parts[2], Length(0.0, METER), bed)
    # The depth test runs on the CPU in both, so the same pixels show water.
    assert_equal(a, b)
    assert_true(a > 0)
    var far = 0
    var kept = 0
    for i in range(40 * 30):
        var x = i % 40
        var y = i // 40
        assert_equal(device.depth[i], host.depth[i])
        var p = device.get_pixel(x, y)
        if device.depth[i] == scene_only.depth[i]:
            # Not water: the ball and the sky keep their pixels exactly.
            assert_equal(_channels(p, scene_only.get_pixel(x, y)), 0)
            kept += 1
        elif _channels(p, host.get_pixel(x, y)) > 2:
            far += 1
    assert_true(kept > 0)
    # At most 2 percent of the water pixels, not of the whole image.
    assert_true(far * 100 <= a * 2, String(far))


def test_a_failed_frame_leaves_the_gpu_and_the_image_usable() raises:
    if _skipped("a failed frame leaves the gpu and the image usable"):
        return
    var bed = _bed()
    var gpu = GpuWater(bed)
    var scene = _scene()
    # A failure after the uploads are queued, then a good frame.
    gpu._fail_after_uploads = True
    with assert_raises(contains="failed after its uploads"):
        _ = _gpu(gpu, scene, -0.72, 48, 32)
    _agree(_gpu(gpu, scene, -0.72, 48, 32), _cpu(scene, bed, -0.72, 48, 32))
    # A composition that fails leaves its image and depths as they were.
    var parts = _ball()
    var renderer = Renderer(40, 30)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(parts[0], parts[1], parts[2])
    var before = renderer.render(parts[0], parts[1], parts[2])
    gpu._fail_after_uploads = True
    with assert_raises(contains="failed after its uploads"):
        _ = gpu.compose(scene, image, parts[0], parts[2], Length(0.0, METER))
    for i in range(40 * 30):
        assert_equal(image.depth[i], before.depth[i])
        assert_equal(
            _channels(
                image.get_pixel(i % 40, i // 40),
                before.get_pixel(i % 40, i // 40),
            ),
            0,
        )
    # A retry draws the image a first try draws: every pixel, every depth
    # and the drawn count. Both run on the device, so they match exactly.
    var fresh = renderer.render(parts[0], parts[1], parts[2])
    var drawn = gpu.compose(
        scene, image, parts[0], parts[2], Length(0.0, METER)
    )
    assert_equal(
        drawn,
        gpu.compose(scene, fresh, parts[0], parts[2], Length(0.0, METER)),
    )
    assert_true(drawn > 0)
    assert_true(image.depth == fresh.depth)
    assert_true(image.pixels == fresh.pixels)


def _resident_bytes() raises -> Int:
    comptime if CompilationTarget.is_macos():
        # macOS has no /proc. `getrusage` gives the peak resident size in
        # bytes, the fifth word. A peak that does not grow means the size
        # did not grow.
        var usage = Array[Int64, 18](fill=0)
        if external_call["getrusage", Int32](Int32(0), usage.unsafe_ptr()) != 0:
            raise Error("getrusage failed")
        return Int(usage[4])
    else:
        # Linux reports resident pages second in /proc/self/statm.
        var fields = Path("/proc/self/statm").read_text().split(" ")
        return Int(fields[1]) * 4096


def _released(probe: DeviceContext, empty: UInt) raises -> Bool:
    # Free device memory is back where it was, within 1 MiB. Not asked of a
    # GPU that shares the system's memory; see `_device_memory_is_its_own`.
    if not _device_memory_is_its_own():
        return True
    return probe.get_memory_info()[0] + (1 << 20) >= empty


def _device_memory_is_its_own() -> Bool:
    # An Apple GPU shares the system's memory, so the free memory a context
    # reports moves with every other process on the machine.
    return not has_apple_gpu_accelerator()


def test_gpu_resources_stay_bounded_and_are_released() raises:
    if _skipped("gpu resources stay bounded and are released"):
        return
    # A separate context reads free device memory for the whole device.
    var probe = DeviceContext()
    var empty = probe.get_memory_info()[0]
    var scene = _scene()
    var sizes = [(64, 48), (97, 61), (128, 72)]
    for round in range(2):
        var gpu = GpuWater(_bed())
        for size in sizes:
            _ = _gpu(gpu, scene, -0.72, size[0], size[1])
        var settled = probe.get_memory_info()[0]
        var host = _resident_bytes()
        var lowest = settled
        for frame in range(60):
            scene.advance(Duration(0.02, SECOND), frame % 7 == 0)
            if frame == 30:
                scene.reset()
            if frame == 40:
                # A refused frame leaves the object usable.
                with assert_raises(contains="dimensions must be positive"):
                    _ = _gpu(gpu, scene, -0.72, 0, 8)
            var size = sizes[frame % 3]
            _ = _gpu(gpu, scene, -0.72, size[0], size[1])
            lowest = min(lowest, probe.get_memory_info()[0])
        if _device_memory_is_its_own():
            # Sixty frames at three sizes leave free memory where warm-up
            # left it. Allocator caching settles in the warm-up frames.
            assert_true(
                probe.get_memory_info()[0] + (1 << 20) >= settled,
                String(round),
            )
            # Free memory read after each frame stays within 16 MiB of
            # where warm-up left it. This is a post-frame reading, not the
            # in-frame peak; see the storage bound in the GPU water report.
            assert_true(settled - lowest <= 16 << 20, String(settled - lowest))
        # Host memory does not grow with the frame count.
        assert_true(_resident_bytes() - host <= 32 << 20)
        # Dropping the object releases its context and its buffers.
        _ = gpu^
        if _device_memory_is_its_own():
            assert_true(
                probe.get_memory_info()[0] + (1 << 20) >= empty,
                String(round),
            )


def test_gpu_water_releases_after_construction_and_failure() raises:
    if _skipped("gpu water releases after construction and failure"):
        return
    var probe = DeviceContext()
    var empty = probe.get_memory_info()[0]
    var scene = _scene()
    for failing in [False, True]:
        var gpu = GpuWater(_bed())
        if failing:
            gpu._fail_after_uploads = True
            with assert_raises(contains="failed after its uploads"):
                _ = _gpu(gpu, scene, -0.72, 64, 48)
        # Dropped with no frame, or after a failed one.
        _ = gpu^
        assert_true(_released(probe, empty), String(failing))


def test_a_failed_construction_releases_and_the_next_one_works() raises:
    if _skipped("a failed construction releases and the next one works"):
        return
    var probe = DeviceContext()
    var empty = probe.get_memory_info()[0]
    var scene = _scene()
    var bed = _bed()
    for round in range(2):
        # The photograph's first copy is queued, then the construction
        # fails. Its buffer and its context are released.
        with assert_raises(contains="failed after its first copy"):
            _ = GpuWater(bed, _fail_after_first_upload=True)
        assert_true(_released(probe, empty), String(round))
        # The next construction works and shades as the CPU does.
        var gpu = GpuWater(bed)
        _agree(_gpu(gpu, scene, -0.72, 48, 32), _cpu(scene, bed, -0.72, 48, 32))
        _ = gpu^
        assert_true(_released(probe, empty), String(round))


struct _HashKernels:
    """Keep device-only entries out of the host test discovery list."""

    @staticmethod
    def hash_kernel(
        output: MutPointer[Float32, MutAnyOrigin],
        inputs: MutPointer[Float32, MutAnyOrigin],
        count: Int32,
    ):
        """Hash each pair of device inputs."""
        from max.gpu import global_idx

        var at = Int(global_idx.x)
        if at >= Int(count):
            return
        output[unsafe_offset=at] = hash12(
            inputs[unsafe_offset=2 * at], inputs[unsafe_offset=2 * at + 1]
        )


def test_both_backends_hash_water_to_the_same_bits() raises:
    # Apple GPUs have no Float64. The hash rounds each step in Float32, and
    # the low bits it reads must not depend on the backend.
    if _skipped("water hash"):
        return
    comptime count = 4096
    var inputs = List[Float32](capacity=2 * count)
    for at in range(count):
        var scale = Float32(10) ** Float32(at % 7 - 2)
        inputs.append((Float32(at) * 0.6180339 - 1250.0) * scale)
        inputs.append((Float32(at) * 0.4142135 + 3.25) * scale)
    var context = DeviceContext()
    var device_inputs = context.enqueue_create_buffer[DType.float32](
        len(inputs)
    )
    with device_inputs.map_to_host() as host:
        for at in range(len(inputs)):
            host[at] = inputs[at]
    var output = context.enqueue_create_buffer[DType.float32](count)
    context.enqueue_function[_HashKernels.hash_kernel](
        output.unsafe_ptr(),
        device_inputs.unsafe_ptr(),
        Int32(count),
        grid_dim=(count // 64,),
        block_dim=(64,),
    )
    context.synchronize()
    with output.map_to_host() as host:
        for at in range(count):
            assert_equal(
                bitcast[DType.uint32](host[at]),
                bitcast[DType.uint32](
                    hash12(inputs[2 * at], inputs[2 * at + 1])
                ),
            )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
