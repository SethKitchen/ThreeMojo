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

from extensions.water.frame import CameraLook, WaterScene, lit_radiance
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
from math.vector3 import Vector3
from max.gpu import global_idx
from max.gpu.host import DeviceBuffer, DeviceContext
from max.gpu.memory import AddressSpace
from std.math import ceildiv
from units.si import SECOND, Duration

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
    """A GPU that shades water frames, holding the pebble photograph."""

    var context: DeviceContext
    """The device the frames run on."""
    var _pebble: DeviceBuffer[DType.float32]
    var _pebble_table: DeviceBuffer[DType.int64]

    def __init__(out self, bed: PebbleBed) raises:
        """Open the default GPU and copy the photograph to it once.

        Args:
            bed: The pebble photograph.

        Raises:
            Error: If there is no GPU or a copy fails.
        """
        self.context = DeviceContext()
        var packed = pack_pebbles(bed)
        self._pebble = _upload[DType.float32](self.context, packed[0])
        self._pebble_table = _upload[DType.int64](self.context, packed[1])

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
        var packed_surface = pack_surface(surface)
        var packed_caustics = pack_caustics(caustics)
        var surface_texels = _upload[DType.float32](
            self.context, packed_surface[0]
        )
        var surface_table = _upload[DType.int64](
            self.context, packed_surface[1]
        )
        var ripple = _upload[DType.float32](self.context, scene._ripples.normal)
        var caustic_texels = _upload[DType.float32](
            self.context, packed_caustics[0]
        )
        var caustic_table = _upload[DType.int64](
            self.context, packed_caustics[1]
        )
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
        var frame = _upload[DType.float32](self.context, values)
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
        var radiance = List[Float32](length=width * height * 3, fill=0.0)
        self.context.enqueue_copy(radiance.unsafe_ptr(), output)
        self.context.synchronize()
        return radiance^
