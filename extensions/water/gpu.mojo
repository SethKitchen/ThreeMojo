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
surface, the ripple window and the caustics, then shades.

`draw` keeps the whole `FRAME` on the device. The bright part of the picture
is cut and blurred there for the bloom, and a few samples of it come back to
the CPU for the glare, which is one small FFT. The device then grades each
pixel and writes bytes, which are the only picture that comes back. `radiance`
and the other views read the linear radiance back and finish on the CPU.

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
    grade_pixel,
    lit_radiance,
    require_water_size,
)
from extensions.water.glare import (
    glare_cell_x,
    glare_cell_y,
    glare_sample_x,
    glare_sample_y,
)
from extensions.water.optics import clamp01
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
from extensions.water.post import RadianceView, blur_texel, highlight_texel
from extensions.water.surface import SurfaceField
from extensions.water.upload import convolve_glare, frame_values, glare_grid
from extensions.water.view import CAUSTICS, FRAME, WaterView, require_view
from math.vector3 import Vector3
from max.gpu import global_idx
from max.gpu.host import DeviceBuffer, DeviceContext
from max.gpu.memory import AddressSpace
from render.framebuffer import Color, FloatColor, Framebuffer
from std.math import ceildiv
from std.sys import has_accelerator
from units.si import SECOND, Angle, Duration, Length

comptime _GLOBAL = AddressSpace.GLOBAL
comptime _Untracked = UntrackedOrigin[mut=False]
comptime _Floats = MutPointer[Float32, MutAnyOrigin, address_space=_GLOBAL]
comptime _Table = MutPointer[Int64, MutAnyOrigin, address_space=_GLOBAL]
comptime _Bytes = MutPointer[UInt8, MutAnyOrigin, address_space=_GLOBAL]

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


def sparks_kernel(
    radiance: _Floats,
    samples: _Floats,
    width: Int32,
    height: Int32,
    sw: Int32,
    sh: Int32,
):
    """Cut the glints that the glare is made from, at the glare grid's points.

    One thread makes one point of the grid, as `apply_glare` samples the
    highlight image of the CPU frame.

    Args:
        radiance: The shaded frame, three floats a pixel.
        samples: The glare grid, three floats a point, row-major.
        width: Image width.
        height: Image height.
        sw: The glare grid's width.
        sh: The glare grid's height.
    """
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x >= Int(sw) or y >= Int(sh):
        return
    var image = RadianceView[_GLOBAL](_read(radiance), Int(width), Int(height))
    var rgb = highlight_texel(
        image,
        glare_sample_x(x, Int(sw), Int(width)),
        glare_sample_y(y, Int(sh), Int(height)),
        14.0,
        0.001,
    )
    var at = (y * Int(sw) + x) * 3
    samples[unsafe_offset=at] = rgb.x
    samples[unsafe_offset=at + 1] = rgb.y
    samples[unsafe_offset=at + 2] = rgb.z


def bright_kernel(
    radiance: _Floats, bright: _Floats, width: Int32, height: Int32
):
    """Cut the part of each pixel that blooms.

    Args:
        radiance: The shaded frame, three floats a pixel.
        bright: The bright part, three floats a pixel.
        width: Image width.
        height: Image height.
    """
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x >= Int(width) or y >= Int(height):
        return
    var image = RadianceView[_GLOBAL](_read(radiance), Int(width), Int(height))
    var rgb = highlight_texel(image, x, y, 2.5, 1.0)
    var at = (y * Int(width) + x) * 3
    bright[unsafe_offset=at] = rgb.x
    bright[unsafe_offset=at + 1] = rgb.y
    bright[unsafe_offset=at + 2] = rgb.z


def blur_kernel(
    source: _Floats,
    blurred: _Floats,
    width: Int32,
    height: Int32,
    horizontal: Int32,
):
    """Blur each pixel along one axis, as the CPU frame's bloom does.

    Args:
        source: The picture to blur, three floats a pixel.
        blurred: The result, three floats a pixel.
        width: Image width.
        height: Image height.
        horizontal: 1 blurs along a row, 0 along a column.
    """
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x >= Int(width) or y >= Int(height):
        return
    var image = RadianceView[_GLOBAL](_read(source), Int(width), Int(height))
    var rgb = blur_texel(image, x, y, horizontal == 1)
    var at = (y * Int(width) + x) * 3
    blurred[unsafe_offset=at] = rgb.x
    blurred[unsafe_offset=at + 1] = rgb.y
    blurred[unsafe_offset=at + 2] = rgb.z


def grade_kernel(
    radiance: _Floats,
    glare: _Floats,
    bloom: _Floats,
    pixels: _Bytes,
    width: Int32,
    height: Int32,
    sw: Int32,
    sh: Int32,
    clock: Float32,
):
    """Grade each pixel of a `FRAME` and write it as four bytes.

    Args:
        radiance: The shaded frame, three floats a pixel.
        glare: The glare grid after the convolution, three floats a point.
        bloom: The blurred bright part, three floats a pixel.
        pixels: Four bytes a pixel, row-major from the top, opaque.
        width: Image width.
        height: Image height.
        sw: The glare grid's width.
        sh: The glare grid's height.
        clock: The frame time, mixed into the grain.
    """
    var x = Int(global_idx.x)
    var y = Int(global_idx.y)
    if x >= Int(width) or y >= Int(height):
        return
    var p = (y * Int(width) + x) * 3
    var g = (
        glare_cell_y(y, Int(height), Int(sh)) * Int(sw)
        + glare_cell_x(x, Int(width), Int(sw))
    ) * 3
    var rgb = grade_pixel(
        radiance[unsafe_offset=p],
        radiance[unsafe_offset=p + 1],
        radiance[unsafe_offset=p + 2],
        glare[unsafe_offset=g],
        glare[unsafe_offset=g + 1],
        glare[unsafe_offset=g + 2],
        bloom[unsafe_offset=p],
        bloom[unsafe_offset=p + 1],
        bloom[unsafe_offset=p + 2],
        x,
        y,
        Int(width),
        Int(height),
        Duration(clock, SECOND),
        FRAME,
    )
    var color = FloatColor(
        clamp01(rgb.x), clamp01(rgb.y), clamp01(rgb.z), 1.0
    ).quantize()
    var at = (y * Int(width) + x) * 4
    pixels[unsafe_offset=at] = color.r
    pixels[unsafe_offset=at + 1] = color.g
    pixels[unsafe_offset=at + 2] = color.b
    pixels[unsafe_offset=at + 3] = color.a


struct GpuWater(Movable):
    """A GPU that shades water frames, holding the pebble photograph.

    It runs on CUDA and on Apple Metal. The kernel was run on a TITAN RTX
    and on an Apple M4 Max. CI builds it for sm_80, and `make check-gpu-air`
    checks its Metal calls.
    """

    var _pebble: DeviceBuffer[DType.float32]
    var _pebble_table: DeviceBuffer[DType.int64]
    # The frame's working buffers, kept from one frame to the next and made
    # again when the size changes: the shaded frame, the bloom before and after
    # its blur, and the bytes that come back. A frame waits for the queue before
    # it returns, so no launch is using them when they are replaced.
    var _radiance: DeviceBuffer[DType.float32]
    var _bloom: DeviceBuffer[DType.float32]
    var _blurred: DeviceBuffer[DType.float32]
    var _bytes: DeviceBuffer[DType.uint8]
    var _width: Int
    var _height: Int
    # A test raises once after a frame's uploads are queued, as a failed
    # launch or read back would, to check the cleanup on that path.
    var _fail_after_uploads: Bool
    # Declared last, and released last in `__deinit__`.
    var context: DeviceContext
    """The device the frames run on."""

    def __init__(
        out self, bed: PebbleBed, _fail_after_first_upload: Bool = False
    ) raises:
        """Open the GPU and copy the photograph to it once.

        Args:
            bed: The pebble photograph.
            _fail_after_first_upload: For tests only. True raises after the
                photograph's first copy is queued, as a failed second copy
                would, to check the cleanup of a partial construction.

        Raises:
            Error: If there is no GPU, or a copy fails.
        """
        if not has_accelerator():
            raise Error("GpuWater needs a GPU")
        var context = DeviceContext()
        var buffers = _upload_bed(
            context, pack_pebbles(bed), _fail_after_first_upload
        )
        self._pebble = buffers[0]
        self._pebble_table = buffers[1]
        self._radiance = context.enqueue_create_buffer[DType.float32](1)
        self._bloom = context.enqueue_create_buffer[DType.float32](1)
        self._blurred = context.enqueue_create_buffer[DType.float32](1)
        self._bytes = context.enqueue_create_buffer[DType.uint8](1)
        self._width = 0
        self._height = 0
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
        _ = self._radiance^
        _ = self._bloom^
        _ = self._blurred^
        _ = self._bytes^
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
        require_water_size(width, height)
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

        A `FRAME` stays on the device after the shading: the bloom, the
        grading and the bytes are made there, and only the glare's small FFT
        runs on the CPU. The other views read the radiance back, and the CPU
        finishes them, as `CAUSTICS`, which has no shading, runs on the CPU.

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
        require_water_size(width, height)
        require_view(view)
        if view == CAUSTICS:
            return scene.draw(width, height, view, sway, _no_bed(), pitch)
        if view == FRAME:
            return self._frame(scene, width, height, sway, pitch)
        var look = camera_look(scene.clock, sway, pitch)
        var hdr = self.radiance(scene, look, width, height)
        return scene._finish(hdr, width, height, view)

    def _ensure(mut self, width: Int, height: Int) raises:
        # Make the working buffers for a size. A frame has waited for the queue,
        # so nothing is using the old ones.
        if self._width == width and self._height == height:
            return
        var floats = width * height * 3
        self._radiance = self.context.enqueue_create_buffer[DType.float32](
            floats
        )
        self._bloom = self.context.enqueue_create_buffer[DType.float32](floats)
        self._blurred = self.context.enqueue_create_buffer[DType.float32](
            floats
        )
        self._bytes = self.context.enqueue_create_buffer[DType.uint8](
            width * height * 4
        )
        self._width = width
        self._height = height

    def _frame(
        mut self,
        mut scene: WaterScene,
        width: Int,
        height: Int,
        sway: Bool,
        pitch: Angle,
    ) raises -> Framebuffer:
        var look = camera_look(scene.clock, sway, pitch)
        var surface = scene._surface()
        var caustics = scene._caustics(surface)
        self._ensure(width, height)
        var size = glare_grid(scene, width, height)
        var sw = size[0]
        var sh = size[1]
        var samples = List[Float32](length=sw * sh * 3, fill=0.0)
        # The bytes come back into a list that the frame adopts. A cleared
        # frame would write every pixel twice, and costs milliseconds at 720p.
        var pixels = List[UInt8](length=width * height * 4, fill=0)
        var flight = self._enqueue_shade(
            scene,
            surface,
            caustics,
            look,
            width,
            height,
            _device(self._radiance),
        )
        # A copy reads or writes its host list until it completes. On every
        # exit, wait for the queue before these lists can be freed.
        var grid = List[Float32]()
        try:
            var tiles = (ceildiv(width, _TILE), ceildiv(height, _TILE))
            var sample_buffer = self.context.enqueue_create_buffer[
                DType.float32
            ](sw * sh * 3)
            self.context.enqueue_function[sparks_kernel](
                _device(self._radiance),
                _device(sample_buffer),
                Int32(width),
                Int32(height),
                Int32(sw),
                Int32(sh),
                grid_dim=(ceildiv(sw, _TILE), ceildiv(sh, _TILE)),
                block_dim=(_TILE, _TILE),
            )
            self.context.enqueue_copy(samples.unsafe_ptr(), sample_buffer)
            self.context.synchronize()
            # The device blurs the bloom while the CPU convolves the glare.
            self.context.enqueue_function[bright_kernel](
                _device(self._radiance),
                _device(self._bloom),
                Int32(width),
                Int32(height),
                grid_dim=tiles,
                block_dim=(_TILE, _TILE),
            )
            self.context.enqueue_function[blur_kernel](
                _device(self._bloom),
                _device(self._blurred),
                Int32(width),
                Int32(height),
                Int32(1),
                grid_dim=tiles,
                block_dim=(_TILE, _TILE),
            )
            self.context.enqueue_function[blur_kernel](
                _device(self._blurred),
                _device(self._bloom),
                Int32(width),
                Int32(height),
                Int32(0),
                grid_dim=tiles,
                block_dim=(_TILE, _TILE),
            )
            grid = convolve_glare(scene, samples, sw, sh)
            var glare_buffer = _upload[DType.float32](self.context, grid)
            self.context.enqueue_function[grade_kernel](
                _device(self._radiance),
                _device(glare_buffer),
                _device(self._bloom),
                _device(self._bytes),
                Int32(width),
                Int32(height),
                Int32(sw),
                Int32(sh),
                scene.clock.value,
                grid_dim=tiles,
                block_dim=(_TILE, _TILE),
            )
            self.context.enqueue_copy(pixels.unsafe_ptr(), self._bytes)
            self.context.synchronize()
            _ = len(sample_buffer) + len(glare_buffer)
        except error:
            _drain(self.context)
            flight.keep()
            _ = len(samples) + len(grid) + len(pixels)
            raise error^
        flight.keep()
        _ = len(samples) + len(grid)
        return Framebuffer(width, height, pixels^)

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

    def _enqueue_shade(
        mut self,
        scene: WaterScene,
        surface: SurfaceField,
        caustics: CausticField,
        look: CameraLook,
        width: Int,
        height: Int,
        output: _Floats,
    ) raises -> _Flight:
        # Queue the uploads and the shading of one frame into `output`, and
        # return what the queue reads. The caller keeps it until it has waited
        # for the queue. If this raises, the queue has been waited for.
        var packed_surface = pack_surface(surface)
        var packed_caustics = pack_caustics(caustics)
        var values = frame_values(scene, look, surface, caustics)
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
            self.context.enqueue_function[water_kernel](
                _device(surface_texels),
                _device(surface_table),
                _device(ripple),
                _device(caustic_texels),
                _device(caustic_table),
                _device(self._pebble),
                _device(self._pebble_table),
                _device(frame),
                output,
                Int32(scene._ripples.n),
                Int32(width),
                Int32(height),
                grid_dim=(ceildiv(width, _TILE), ceildiv(height, _TILE)),
                block_dim=(_TILE, _TILE),
            )
            return _Flight(
                packed_surface^,
                packed_caustics^,
                values^,
                surface_texels^,
                surface_table^,
                ripple^,
                caustic_texels^,
                caustic_table^,
                frame^,
            )
        except error:
            _drain(self.context)
            _keep(packed_surface, packed_caustics, values, List[Float32]())
            raise error^

    def _shade(
        mut self,
        scene: WaterScene,
        surface: SurfaceField,
        caustics: CausticField,
        look: CameraLook,
        width: Int,
        height: Int,
    ) raises -> List[Float32]:
        var radiance = List[Float32](length=width * height * 3, fill=0.0)
        var output = self.context.enqueue_create_buffer[DType.float32](
            width * height * 3
        )
        var flight = self._enqueue_shade(
            scene, surface, caustics, look, width, height, _device(output)
        )
        # A copy writes its host list until it completes. On every exit, wait
        # for the queue before the list can be freed.
        try:
            self.context.enqueue_copy(radiance.unsafe_ptr(), output)
            self.context.synchronize()
        except error:
            _drain(self.context)
            flight.keep()
            _ = len(radiance)
            raise error^
        # Every copy has completed. The host lists can go now.
        flight.keep()
        return radiance^


struct _Flight(Movable):
    """What the queue of one frame reads: host lists and device buffers.

    A queued copy reads its host list when the device runs it, and a launch
    reads its buffers then, so all of them must live until the queue has been
    waited for. Mojo ends a value at its last use, which `keep` is.
    """

    var surface: Tuple[List[Float32], List[Int64]]
    var caustics: Tuple[List[Float32], List[Int64]]
    var values: List[Float32]
    var surface_texels: DeviceBuffer[DType.float32]
    var surface_table: DeviceBuffer[DType.int64]
    var ripple: DeviceBuffer[DType.float32]
    var caustic_texels: DeviceBuffer[DType.float32]
    var caustic_table: DeviceBuffer[DType.int64]
    var frame: DeviceBuffer[DType.float32]

    def __init__(
        out self,
        var surface: Tuple[List[Float32], List[Int64]],
        var caustics: Tuple[List[Float32], List[Int64]],
        var values: List[Float32],
        var surface_texels: DeviceBuffer[DType.float32],
        var surface_table: DeviceBuffer[DType.int64],
        var ripple: DeviceBuffer[DType.float32],
        var caustic_texels: DeviceBuffer[DType.float32],
        var caustic_table: DeviceBuffer[DType.int64],
        var frame: DeviceBuffer[DType.float32],
    ):
        self.surface = surface^
        self.caustics = caustics^
        self.values = values^
        self.surface_texels = surface_texels^
        self.surface_table = surface_table^
        self.ripple = ripple^
        self.caustic_texels = caustic_texels^
        self.caustic_table = caustic_table^
        self.frame = frame^

    def keep(self):
        _keep(self.surface, self.caustics, self.values, List[Float32]())
        _ = len(self.surface_texels) + len(self.surface_table)
        _ = len(self.ripple) + len(self.caustic_texels)
        _ = len(self.caustic_table) + len(self.frame)


def _upload_bed(
    context: DeviceContext,
    packed: Tuple[List[Float32], List[Int64]],
    fail_after_first: Bool,
) raises -> Tuple[DeviceBuffer[DType.float32], DeviceBuffer[DType.int64]]:
    # A copy reads its host list until it completes. On every exit, wait for
    # the queue before the packed lists can be freed.
    try:
        var texels = _upload[DType.float32](context, packed[0])
        if fail_after_first:
            raise Error("The photograph upload failed after its first copy")
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
