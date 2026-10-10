# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clearwater's per-pixel water shader on a GPU.

`GpuWater` runs `lit_radiance` with one thread for each pixel. It is the
same function the CPU frame calls, reading the same packed textures in
device memory, so the two differ only where the hardware rounds a math
function or fuses a multiply and an add differently.

The pebble photograph goes to the device once. Each frame copies the
surface, the ripple window and the caustics, then reads back the linear
radiance. Bloom, glare and grading stay on the CPU.

This module imports MAX, so it builds only where MAX is installed.
"""

from cameras.camera import Camera
from core.scene import Scene
from extensions.water.caustics import CausticField
from extensions.water.frame import (
    CameraLook,
    WaterScene,
    _compose_plan,
    camera_look,
    lit_radiance,
)
from extensions.water.packed import (
    CausticView,
    PebbleView,
    RippleView,
    SurfaceView,
    pack_caustics,
    pack_pebbles,
    pack_surface,
)
from extensions.water.pebbles import PebbleBed
from extensions.water.surface import SurfaceField
from extensions.water.view import CAUSTICS, WaterView, require_view
from math.vector3 import Vector3
from max.gpu import global_idx
from max.gpu.host import DeviceBuffer, DeviceContext
from max.gpu.memory import AddressSpace
from render.framebuffer import Framebuffer
from std.math import ceildiv
from std.sys import has_nvidia_gpu_accelerator
from units.si import SECOND, Angle, Duration, Length

comptime _GLOBAL = AddressSpace.GLOBAL
comptime _Untracked = UntrackedOrigin[mut=False]
comptime _Floats = MutPointer[Float32, MutAnyOrigin, address_space=_GLOBAL]
comptime _Table = MutPointer[Int64, MutAnyOrigin, address_space=_GLOBAL]

# 16 by 16 threads, as the rasterizer kernels use.
comptime _TILE = 16


def _read[
    T: AnyType
](pointer: MutPointer[T, MutAnyOrigin, address_space=_GLOBAL]) -> Pointer[
    T, _Untracked, address_space=_GLOBAL
]:
    return pointer.unsafe_mut_cast[False]().unsafe_origin_cast[_Untracked]()


def _device[
    dtype: DType
](buffer: DeviceBuffer[dtype]) -> MutPointer[
    Scalar[dtype], MutAnyOrigin, address_space=_GLOBAL
]:
    return (
        buffer.unsafe_ptr()
        .unsafe_mut_cast[True]()
        .unsafe_origin_cast[MutAnyOrigin]()
        .unsafe_address_space_cast[_GLOBAL]()
    )


def _upload[
    dtype: DType
](context: DeviceContext, values: List[Scalar[dtype]]) raises -> DeviceBuffer[
    dtype
]:
    var buffer = context.enqueue_create_buffer[dtype](len(values))
    context.enqueue_copy(buffer, values.unsafe_ptr())
    return buffer^


# The frame values the kernel reads from one small buffer: the camera's
# forward, right and up axes and its position, the sun direction, then the
# clock, the ocean patch, the ripple window and the caustic placement.
comptime _FRAME_FLOATS = 23


def water_kernel(
    surface: _Floats,
    surface_table: _Table,
    ripple: _Floats,
    caustic: _Floats,
    caustic_table: _Table,
    pebble: _Floats,
    pebble_table: _Table,
    frame: _Floats,
    radiance: _Floats,
    ripple_side: Int32,
    width: Int32,
    height: Int32,
):
    """Shade one pixel into linear RGB, as the CPU frame does.

    Args:
        surface: Packed surface texels.
        surface_table: The surface level table.
        ripple: The ripple normal texture.
        caustic: Packed caustic texels.
        caustic_table: The caustic level table.
        pebble: Packed photograph texels.
        pebble_table: The photograph level table.
        frame: The frame values, in the order `GpuWater.radiance` writes.
        radiance: Three floats a pixel, row-major from the top.
        ripple_side: Ripple texels on one side.
        width: Image width.
        height: Image height.
    """
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    # The grid is whole tiles, so its edges overhang the image.
    if x >= Int(width) or y >= Int(height):
        return
    var f = _read(frame)
    var look = CameraLook(
        f[unsafe_offset=0],
        f[unsafe_offset=1],
        f[unsafe_offset=2],
        f[unsafe_offset=3],
        f[unsafe_offset=4],
        f[unsafe_offset=5],
        f[unsafe_offset=6],
        f[unsafe_offset=7],
        f[unsafe_offset=8],
        f[unsafe_offset=9],
        f[unsafe_offset=10],
        f[unsafe_offset=11],
    )
    var sun = Vector3(
        f[unsafe_offset=12], f[unsafe_offset=13], f[unsafe_offset=14]
    )
    var w = Float32(width)
    var h = Float32(height)
    var ndc_x = ((Float32(x) + 0.5) / w) * 2.0 - 1.0
    var ndc_y = 1.0 - ((Float32(y) + 0.5) / h) * 2.0
    var rgb = lit_radiance(
        look,
        ndc_x,
        ndc_y,
        w / h,
        SurfaceView[_GLOBAL](
            _read(surface), _read(surface_table), f[unsafe_offset=16]
        ),
        RippleView[_GLOBAL](
            _read(ripple),
            Int(ripple_side),
            f[unsafe_offset=17],
            f[unsafe_offset=18],
            f[unsafe_offset=19],
        ),
        CausticView[_GLOBAL](
            _read(caustic),
            _read(caustic_table),
            f[unsafe_offset=20],
            f[unsafe_offset=21],
            f[unsafe_offset=22],
        ),
        PebbleView[_GLOBAL](_read(pebble), _read(pebble_table)),
        Duration(f[unsafe_offset=15], SECOND),
        2.0 / w,
        2.0 / h,
        sun,
    )
    var at = (y * Int(width) + x) * 3
    radiance[unsafe_offset=at] = rgb.x
    radiance[unsafe_offset=at + 1] = rgb.y
    radiance[unsafe_offset=at + 2] = rgb.z


struct GpuWater(Movable):
    """An NVIDIA GPU that shades water frames, holding the pebble photograph.

    CUDA is the only supported backend. The kernel was run on a TITAN RTX,
    and CI builds it for sm_80. No Metal check covers this kernel.
    """

    var _pebble: DeviceBuffer[DType.float32]
    var _pebble_table: DeviceBuffer[DType.int64]
    # A test raises once after a frame's uploads are queued, as a failed
    # launch or read back would, to check the cleanup on that path.
    var _fail_after_uploads: Bool
    # Declared last, and released last in `__deinit__`.
    var context: DeviceContext
    """The CUDA device the frames run on."""

    def __init__(out self, bed: PebbleBed) raises:
        """Open the CUDA GPU and copy the photograph to it once.

        Args:
            bed: The pebble photograph.

        Raises:
            Error: If there is no NVIDIA GPU, or a copy fails.
        """
        if not has_nvidia_gpu_accelerator():
            raise Error("GpuWater needs an NVIDIA CUDA GPU")
        var context = DeviceContext(api="cuda")
        var buffers = _upload_bed(context, pack_pebbles(bed))
        self._pebble = buffers[0]
        self._pebble_table = buffers[1]
        self._fail_after_uploads = False
        self.context = context^

    def __deinit__(deinit self):
        """Drain the queue, release the buffers, then release the context.

        `render/gpu.mojo` found that releasing a CUDA context with live
        buffers or a launch in flight can hang the next context on WSL 2.
        The order is spelled out so that a field reorder cannot change it.
        """
        # A destructor cannot raise. A context that cannot be waited on
        # has nothing left worth reporting.
        try:
            self.context.synchronize()
        except:
            pass
        _ = self._pebble^
        _ = self._pebble_table^
        _ = self.context^

    def radiance(
        mut self, scene: WaterScene, look: CameraLook, width: Int, height: Int
    ) raises -> List[Float32]:
        """Shade every pixel of one frame on the GPU.

        The result is the linear radiance that the CPU frame grades, three
        floats a pixel, row-major from the top. It uses the scene's clock,
        sun, surface, ripples and caustics.

        Args:
            scene: The water at its current clock.
            look: The camera basis and position.
            width: Image width in pixels. It must be positive.
            height: Image height in pixels. It must be positive.

        Returns:
            The linear radiance.

        Raises:
            Error: If a size is not positive, or a device step fails.
        """
        if width <= 0 or height <= 0:
            raise Error("Water image dimensions must be positive")
        var surface = scene._surface()
        var caustics = scene._caustics(surface)
        return self._shade(scene, surface, caustics, look, width, height)

    def draw(
        mut self,
        mut scene: WaterScene,
        width: Int,
        height: Int,
        view: WaterView,
        sway: Bool,
        pitch: Angle,
    ) raises -> Framebuffer:
        """Draw a whole frame as `WaterScene.draw` does, shading on the GPU.

        Bloom, glare and the tone curve run on the CPU over the GPU
        radiance. `CAUSTICS` has no shading and runs on the CPU.

        Args:
            scene: The water at its current clock. It keeps the glare
                kernels that a first `FRAME` or `GLARE` builds.
            width: Image width in pixels. It must be positive.
            height: Image height in pixels. It must be positive.
            view: Which picture. See `WaterView`.
            sway: True adds the idle camera bob.
            pitch: Camera pitch. The page starts at -0.72 radians.

        Returns:
            A framebuffer of display-ready pixels.

        Raises:
            Error: If a size or the view is not valid, or a device step
                fails.
        """
        if width <= 0 or height <= 0:
            raise Error("Water image dimensions must be positive")
        require_view(view)
        if view == CAUSTICS:
            return scene.draw(width, height, view, sway, _no_bed(), pitch)
        var look = camera_look(scene.clock, sway, pitch)
        var hdr = self.radiance(scene, look, width, height)
        return scene._finish(hdr, width, height, view)

    def compose[
        C: Camera
    ](
        mut self,
        scene: WaterScene,
        mut image: Framebuffer,
        world: Scene,
        camera: C,
        water_level: Length,
    ) raises -> Int:
        """Compose water into a rendered scene as `WaterScene.compose`
        does, shading on the GPU.

        It shades on the GPU before it changes `image`. The depth test and
        the write then run on the CPU, in pixel order. If shading fails,
        `image` and its depths are unchanged.

        Parameters:
            C: The camera type.

        Args:
            scene: The water at its current clock.
            image: The rendered scene, with its depth buffer. It is changed.
            world: The scene that was rendered, with current world matrices.
            camera: The centered perspective camera that rendered `image`.
                It must be above the water.
            water_level: The world height of the still water plane.

        Returns:
            How many pixels now show water.

        Raises:
            Error: If the camera view is invalid, or a device step fails.
        """
        var plan = _compose_plan(
            image,
            camera.projection_matrix(),
            camera.view_matrix_in(world),
            water_level,
        )
        var surface = scene._surface()
        var caustics = scene._caustics(surface)
        # Every pixel is shaded, so the shading does not need the depth
        # test. Shading first leaves the image whole if it fails.
        var hdr = self._shade(
            scene, surface, caustics, plan.look, image.width, image.height
        )
        var shown = scene._compose_depth(image, plan, surface)
        return scene._compose_write(image, hdr, shown)

    def _shade(
        mut self,
        scene: WaterScene,
        surface: SurfaceField,
        caustics: CausticField,
        look: CameraLook,
        width: Int,
        height: Int,
    ) raises -> List[Float32]:
        var packed_surface = pack_surface(surface)
        var packed_caustics = pack_caustics(caustics)
        var values: List[Float32] = [
            look.fx,
            look.fy,
            look.fz,
            look.rx,
            look.ry,
            look.rz,
            look.ux,
            look.uy,
            look.uz,
            look.px,
            look.py,
            look.pz,
            scene.sun.x,
            scene.sun.y,
            scene.sun.z,
            scene.clock.value,
            surface.surface_patch(),
            scene._ripples.size,
            scene._ripples.center_x,
            scene._ripples.center_z,
            caustics.patch,
            caustics.shift_x,
            caustics.shift_z,
        ]
        var radiance = List[Float32](length=width * height * 3, fill=0.0)
        # A copy reads its host list until it completes. On every exit, wait
        # for the queue before these lists can be freed.
        try:
            var surface_texels = _upload[DType.float32](
                self.context, packed_surface[0]
            )
            var surface_table = _upload[DType.int64](
                self.context, packed_surface[1]
            )
            var ripple = _upload[DType.float32](
                self.context, scene._ripples.normal
            )
            var caustic_texels = _upload[DType.float32](
                self.context, packed_caustics[0]
            )
            var caustic_table = _upload[DType.int64](
                self.context, packed_caustics[1]
            )
            var frame = _upload[DType.float32](self.context, values)
            if self._fail_after_uploads:
                self._fail_after_uploads = False
                raise Error("Water shading failed after its uploads")
            var output = self.context.enqueue_create_buffer[DType.float32](
                width * height * 3
            )
            self.context.enqueue_function[water_kernel](
                _device(surface_texels),
                _device(surface_table),
                _device(ripple),
                _device(caustic_texels),
                _device(caustic_table),
                _device(self._pebble),
                _device(self._pebble_table),
                _device(frame),
                _device(output),
                Int32(scene._ripples.n),
                Int32(width),
                Int32(height),
                grid_dim=(ceildiv(width, _TILE), ceildiv(height, _TILE)),
                block_dim=(_TILE, _TILE),
            )
            self.context.enqueue_copy(radiance.unsafe_ptr(), output)
            self.context.synchronize()
        except error:
            _drain(self.context)
            _keep(packed_surface, packed_caustics, values, radiance)
            raise error^
        # Every copy has completed. The host lists can go now.
        _keep(packed_surface, packed_caustics, values, radiance)
        return radiance^


def _upload_bed(
    context: DeviceContext, packed: Tuple[List[Float32], List[Int64]]
) raises -> Tuple[DeviceBuffer[DType.float32], DeviceBuffer[DType.int64]]:
    # A copy reads its host list until it completes. On every exit, wait for
    # the queue before the packed lists can be freed.
    try:
        var texels = _upload[DType.float32](context, packed[0])
        var table = _upload[DType.int64](context, packed[1])
        context.synchronize()
        return (texels^, table^)
    except error:
        _drain(context)
        raise error^


def _drain(context: DeviceContext):
    # Wait for queued copies after a failure. A queue that cannot be waited
    # on has failed already, and the original error is the one to report.
    try:
        context.synchronize()
    except:
        pass


def _keep(
    surface: Tuple[List[Float32], List[Int64]],
    caustics: Tuple[List[Float32], List[Int64]],
    values: List[Float32],
    radiance: List[Float32],
):
    # A use after the wait, so that no host list a copy reads is freed
    # before the copy completes.
    _ = len(surface[0]) + len(surface[1]) + len(caustics[0])
    _ = len(caustics[1]) + len(values) + len(radiance)


def _no_bed() raises -> PebbleBed:
    # `CAUSTICS` reads no photograph, and a bed needs one texel at least.
    return PebbleBed(1, 1, [Float32(0), 0, 0])
