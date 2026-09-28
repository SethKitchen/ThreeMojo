# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Voxel global illumination on the GPU: three.js's VXGI compute kernels,
as `lights.vxgi_volume` and `postprocessing.vxgi_node` run them on the
host.

**A thread a voxel.** three.js voxelizes with a thread a triangle, which
sets bits with `atomicOr` and races to write the voxel's last triangle.
Here a thread owns a voxel and asks every triangle in turn with
`VoxelTriangle.covers`, the same arithmetic the host's walk uses. The
last triangle that covers the voxel wins, as it does on the host. So the
two backends give the same bits and the same triangles.

**The rest.** The resolve, the opacity levels, the injection, the
radiance levels, the bounces and the pixels each run a thread a texel.
Each calls the host's own function for that texel. The volume stays on
the host between passes: each pass uploads what it reads and downloads
what it writes, so the parity tests compare the lists.

This module imports `max`, so it is in `GPU_LIB_SOURCES`, beside
`render/gpu.mojo`.
"""

from core.assets import Assets
from core.scene import Scene
from lights.vxgi_cone_tracer import (
    Untracked,
    VOXEL_FLOATS,
    VxgiGrid,
    floats_of,
)
from lights.vxgi_volume import (
    VXGIVolume,
    bounce_voxel,
    inject_voxel,
    opacity_mip_voxel,
    radiance_mip_voxel,
    resolve_voxel,
    voxel_bits,
    voxel_coordinates,
)
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from max.gpu import global_idx
from max.gpu.host import DeviceBuffer, DeviceContext
from postprocessing.screen_space import DepthView
from postprocessing.vxgi_node import VXGINode, VxgiFrame, vxgi_pixel
from render.gpu import available
from std.math import ceildiv
from std.memory import unsafe_memcpy


# Threads a block.
comptime BLOCK = 256


def _read(
    pointer: MutPointer[Float32, MutAnyOrigin]
) -> Pointer[Float32, Untracked]:
    """Return a device buffer's floats as the host's functions read them."""
    return pointer.unsafe_mut_cast[False]().unsafe_origin_cast[Untracked]()


def _put(
    target: MutPointer[Float32, MutAnyOrigin],
    index: Int,
    texel: SIMD[DType.float32, 4],
):
    """Write one voxel's four floats."""
    var at = index * VOXEL_FLOATS
    for lane in range(VOXEL_FLOATS):
        target[unsafe_offset=at + lane] = texel[lane]


def voxelize_kernel(
    occupancy: MutPointer[Int32, MutAnyOrigin],
    ids: MutPointer[Int32, MutAnyOrigin],
    triangles: MutPointer[Float32, MutAnyOrigin],
    header: MutPointer[Float32, MutAnyOrigin],
    triangle_count: Int32,
):
    """Find one voxel's bits and last triangle: `voxel_bits`.

    Args:
        occupancy: Each voxel's sub-voxel bits, written.
        ids: One more than each voxel's last triangle, written.
        triangles: The triangle records.
        header: The grid's floats.
        triangle_count: How many records there are.
    """
    var grid = VxgiGrid(header=_read(header))
    var index = Int(global_idx.x)
    if index >= grid.level_count(0):
        return
    var at = voxel_coordinates(index, grid.size_x, grid.size_y)
    var found = voxel_bits(
        _read(triangles), Int(triangle_count), grid, at[0], at[1], at[2]
    )
    occupancy[unsafe_offset=index] = Int32(found[0])
    ids[unsafe_offset=index] = Int32(found[1])


def resolve_kernel(
    opacity: MutPointer[Float32, MutAnyOrigin],
    occupancy: MutPointer[Int32, MutAnyOrigin],
    header: MutPointer[Float32, MutAnyOrigin],
):
    """Resolve one voxel's opacity from its bits: `resolve_voxel`.

    Args:
        opacity: The opacity chain, its level zero written.
        occupancy: Each voxel's sub-voxel bits.
        header: The grid's floats.
    """
    var grid = VxgiGrid(header=_read(header))
    var index = Int(global_idx.x)
    if index >= grid.level_count(0):
        return
    _put(opacity, index, resolve_voxel(Int(occupancy[unsafe_offset=index])))


def opacity_mip_kernel(
    opacity: MutPointer[Float32, MutAnyOrigin],
    header: MutPointer[Float32, MutAnyOrigin],
    level: Int32,
):
    """Fill one voxel of a coarser opacity level: `opacity_mip_voxel`.

    Args:
        opacity: The opacity chain, the level written.
        header: The grid's floats.
        level: The level, one or more.
    """
    var grid = VxgiGrid(header=_read(header))
    var tier = Int(level)
    var index = Int(global_idx.x)
    if index >= grid.level_count(tier):
        return
    var at = voxel_coordinates(index, grid.level_x(tier), grid.level_y(tier))
    var texel = opacity_mip_voxel(
        _read(opacity), grid, tier, at[0], at[1], at[2]
    )
    _put(opacity, grid.level_start(tier) + index, texel)


def radiance_mip_kernel(
    radiance: MutPointer[Float32, MutAnyOrigin],
    header: MutPointer[Float32, MutAnyOrigin],
    level: Int32,
):
    """Fill one voxel of a coarser radiance level: `radiance_mip_voxel`.

    Args:
        radiance: The radiance chain, the level written.
        header: The grid's floats.
        level: The level, one or more.
    """
    var grid = VxgiGrid(header=_read(header))
    var tier = Int(level)
    var index = Int(global_idx.x)
    if index >= grid.level_count(tier):
        return
    var at = voxel_coordinates(index, grid.level_x(tier), grid.level_y(tier))
    var texel = radiance_mip_voxel(
        _read(radiance), grid, tier, at[0], at[1], at[2]
    )
    _put(radiance, grid.level_start(tier) + index, texel)


def inject_kernel(
    direct: MutPointer[Float32, MutAnyOrigin],
    radiance: MutPointer[Float32, MutAnyOrigin],
    triangles: MutPointer[Float32, MutAnyOrigin],
    lights: MutPointer[Float32, MutAnyOrigin],
    opacity: MutPointer[Float32, MutAnyOrigin],
    occupancy: MutPointer[Int32, MutAnyOrigin],
    ids: MutPointer[Int32, MutAnyOrigin],
    header: MutPointer[Float32, MutAnyOrigin],
    light_count: Int32,
    shadow_tan: Float32,
):
    """Light one voxel: `inject_voxel`.

    Args:
        direct: The direct radiance, written.
        radiance: The radiance chain, its level zero written.
        triangles: The triangle records.
        lights: The light records.
        opacity: The opacity chain.
        occupancy: Each voxel's sub-voxel bits.
        ids: One more than each voxel's last triangle.
        header: The grid's floats.
        light_count: How many lights.
        shadow_tan: The tangent of half a shadow cone's aperture.
    """
    var grid = VxgiGrid(header=_read(header))
    var index = Int(global_idx.x)
    if index >= grid.level_count(0):
        return
    var at = voxel_coordinates(index, grid.size_x, grid.size_y)
    var texel = inject_voxel(
        grid,
        _read(triangles),
        _read(lights),
        Int(light_count),
        _read(opacity),
        Int(occupancy[unsafe_offset=index]),
        Int(ids[unsafe_offset=index]),
        at[0],
        at[1],
        at[2],
        shadow_tan,
    )
    _put(direct, index, texel)
    _put(radiance, index, texel)


def bounce_kernel(
    target: MutPointer[Float32, MutAnyOrigin],
    direct: MutPointer[Float32, MutAnyOrigin],
    source: MutPointer[Float32, MutAnyOrigin],
    triangles: MutPointer[Float32, MutAnyOrigin],
    opacity: MutPointer[Float32, MutAnyOrigin],
    occupancy: MutPointer[Int32, MutAnyOrigin],
    ids: MutPointer[Int32, MutAnyOrigin],
    header: MutPointer[Float32, MutAnyOrigin],
    tan_half: Float32,
    trace_distance: Float32,
):
    """Bounce the light once at one voxel: `bounce_voxel`.

    Args:
        target: The new radiance chain, its level zero written.
        direct: The direct radiance.
        source: The radiance chain of the pass before.
        triangles: The triangle records.
        opacity: The opacity chain.
        occupancy: Each voxel's sub-voxel bits.
        ids: One more than each voxel's last triangle.
        header: The grid's floats.
        tan_half: The tangent of half a cone's aperture.
        trace_distance: How far a cone may reach.
    """
    var grid = VxgiGrid(header=_read(header))
    var index = Int(global_idx.x)
    if index >= grid.level_count(0):
        return
    var at = voxel_coordinates(index, grid.size_x, grid.size_y)
    var texel = bounce_voxel(
        grid,
        _read(triangles),
        _read(direct),
        _read(source),
        _read(opacity),
        Int(occupancy[unsafe_offset=index]),
        Int(ids[unsafe_offset=index]),
        at[0],
        at[1],
        at[2],
        tan_half,
        trace_distance,
    )
    _put(target, index, texel)


def pixel_kernel(
    out_pixels: MutPointer[Float32, MutAnyOrigin],
    opacity: MutPointer[Float32, MutAnyOrigin],
    radiance: MutPointer[Float32, MutAnyOrigin],
    params: MutPointer[Float32, MutAnyOrigin],
    depth: MutPointer[Float32, MutAnyOrigin],
    normals: MutPointer[Float32, MutAnyOrigin],
    header: MutPointer[Float32, MutAnyOrigin],
    width: Int32,
    height: Int32,
):
    """Gather one pixel: `vxgi_pixel`.

    Args:
        out_pixels: Four floats a pixel, written.
        opacity: The opacity chain.
        radiance: The radiance chain.
        params: The pass's numbers, `VXGINode.params`.
        depth: One window depth a pixel.
        normals: Three floats a pixel, the view-space normal.
        header: The grid's floats.
        width: The frame's width.
        height: The frame's height.
    """
    var grid = VxgiGrid(header=_read(header))
    var slot = Int(global_idx.x)
    var w = Int(width)
    if slot >= w * Int(height):
        return
    var normal = Vector3(
        normals[unsafe_offset=slot * 3],
        normals[unsafe_offset=slot * 3 + 1],
        normals[unsafe_offset=slot * 3 + 2],
    )
    var pixel = vxgi_pixel(
        grid,
        _read(opacity),
        _read(radiance),
        _read(params),
        depth[unsafe_offset=slot],
        normal,
        slot % w,
        slot // w,
    )
    _put(out_pixels, slot, pixel)


struct GpuVxgi(Movable):
    """Runs a `VXGIVolume`'s passes and a `VXGINode`'s pixels on the
    device."""

    var context: DeviceContext

    def __init__(out self) raises:
        """Open the device.

        Raises:
            Error: If no GPU is present.
        """
        if not available():
            raise Error("No GPU available")
        self.context = DeviceContext()

    def _floats(
        self, values: List[Float32]
    ) raises -> DeviceBuffer[DType.float32]:
        """Return a device buffer holding a list's floats."""
        var buffer = self.context.enqueue_create_buffer[DType.float32](
            max(len(values), VOXEL_FLOATS)
        )
        with buffer.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=values.unsafe_ptr(),
                count=len(values),
            )
        return buffer^

    def _ints(self, values: List[Int32]) raises -> DeviceBuffer[DType.int32]:
        """Return a device buffer holding a list's integers."""
        var buffer = self.context.enqueue_create_buffer[DType.int32](
            max(len(values), VOXEL_FLOATS)
        )
        with buffer.map_to_host() as host:
            unsafe_memcpy(
                dest=host.unsafe_ptr(),
                src=values.unsafe_ptr(),
                count=len(values),
            )
        return buffer^

    def _read_floats(
        self, buffer: DeviceBuffer[DType.float32], mut values: List[Float32]
    ) raises:
        """Copy a device buffer back over a list of its length."""
        self.context.synchronize()
        with buffer.map_to_host() as host:
            unsafe_memcpy(
                dest=values.unsafe_ptr(),
                src=host.unsafe_ptr(),
                count=len(values),
            )

    def _read_ints(
        self, buffer: DeviceBuffer[DType.int32], mut values: List[Int32]
    ) raises:
        """Copy a device buffer back over a list of its length."""
        self.context.synchronize()
        with buffer.map_to_host() as host:
            unsafe_memcpy(
                dest=values.unsafe_ptr(),
                src=host.unsafe_ptr(),
                count=len(values),
            )

    def voxelize(mut self, mut volume: VXGIVolume) raises:
        """Voxelize the collected triangles and build the opacity chain on
        the device, as `VXGIVolume.voxelize` does on the host.
        `prepare_voxels` must run first.

        Args:
            volume: The volume. Its occupancy, triangles and opacity are
                written.

        Raises:
            Error: If the device fails.
        """
        var grid = volume.grid
        var count = grid.level_count(0)
        var header = self._floats(grid.header())
        var triangles = self._floats(volume.triangles)
        var occupancy = self._ints(volume.occupancy)
        var ids = self._ints(volume.triangle_ids)
        var opacity = self._floats(volume.opacity)
        self.context.enqueue_function[voxelize_kernel](
            occupancy.unsafe_ptr(),
            ids.unsafe_ptr(),
            triangles.unsafe_ptr(),
            header.unsafe_ptr(),
            Int32(volume.triangle_count()),
            grid_dim=ceildiv(count, BLOCK),
            block_dim=BLOCK,
        )
        self.context.enqueue_function[resolve_kernel](
            opacity.unsafe_ptr(),
            occupancy.unsafe_ptr(),
            header.unsafe_ptr(),
            grid_dim=ceildiv(count, BLOCK),
            block_dim=BLOCK,
        )
        for level in range(1, grid.levels):
            self.context.synchronize()
            self.context.enqueue_function[opacity_mip_kernel](
                opacity.unsafe_ptr(),
                header.unsafe_ptr(),
                Int32(level),
                grid_dim=ceildiv(grid.level_count(level), BLOCK),
                block_dim=BLOCK,
            )
        self._read_ints(occupancy, volume.occupancy)
        self._read_ints(ids, volume.triangle_ids)
        self._read_floats(opacity, volume.opacity)

    def _radiance_levels(
        mut self,
        radiance: DeviceBuffer[DType.float32],
        header: DeviceBuffer[DType.float32],
        grid: VxgiGrid,
    ) raises:
        """Fill every coarser radiance level on the device."""
        for level in range(1, grid.levels):
            self.context.synchronize()
            self.context.enqueue_function[radiance_mip_kernel](
                radiance.unsafe_ptr(),
                header.unsafe_ptr(),
                Int32(level),
                grid_dim=ceildiv(grid.level_count(level), BLOCK),
                block_dim=BLOCK,
            )

    def light(mut self, mut volume: VXGIVolume) raises:
        """Inject the light and cache the bounces on the device, as
        `VXGIVolume.update_lighting` does on the host. The volume must be
        voxelized and its lights collected.

        Args:
            volume: The volume. Its direct light and radiance are written.

        Raises:
            Error: If the device fails.
        """
        var grid = volume.grid
        var count = grid.level_count(0)
        var total = grid.total() * VOXEL_FLOATS
        volume.direct = List[Float32](length=count * VOXEL_FLOATS, fill=0)
        volume.radiance = List[Float32](length=total, fill=0)
        var header = self._floats(grid.header())
        var triangles = self._floats(volume.triangles)
        var lights = self._floats(volume.lights)
        var opacity = self._floats(volume.opacity)
        var occupancy = self._ints(volume.occupancy)
        var ids = self._ints(volume.triangle_ids)
        var direct = self._floats(volume.direct)
        var radiance = self._floats(volume.radiance)
        self.context.enqueue_function[inject_kernel](
            direct.unsafe_ptr(),
            radiance.unsafe_ptr(),
            triangles.unsafe_ptr(),
            lights.unsafe_ptr(),
            opacity.unsafe_ptr(),
            occupancy.unsafe_ptr(),
            ids.unsafe_ptr(),
            header.unsafe_ptr(),
            Int32(volume.light_count()),
            volume.shadow_tan(),
            grid_dim=ceildiv(count, BLOCK),
            block_dim=BLOCK,
        )
        self._radiance_levels(radiance, header, grid)
        for _ in range(volume.bounces):
            self.context.synchronize()
            var next = self._floats(List[Float32](length=total, fill=0))
            self.context.enqueue_function[bounce_kernel](
                next.unsafe_ptr(),
                direct.unsafe_ptr(),
                radiance.unsafe_ptr(),
                triangles.unsafe_ptr(),
                opacity.unsafe_ptr(),
                occupancy.unsafe_ptr(),
                ids.unsafe_ptr(),
                header.unsafe_ptr(),
                volume.bounce_tan(),
                volume.trace_distance(),
                grid_dim=ceildiv(count, BLOCK),
                block_dim=BLOCK,
            )
            self._radiance_levels(next, header, grid)
            self.context.synchronize()
            radiance = next^
        self._read_floats(direct, volume.direct)
        self._read_floats(radiance, volume.radiance)

    def update(
        mut self, mut volume: VXGIVolume, scene: Scene, assets: Assets
    ) raises:
        """Voxelize and light a volume on the device where it needs it, as
        `VXGIVolume.update` does on the host.

        Args:
            volume: The volume.
            scene: The scene. It must be current.
            assets: Where its meshes' geometries, materials and textures
                are.

        Raises:
            Error: Anything `VXGIVolume.prepare_voxels` or
                `VXGIVolume.collect_lights` raises, or the device fails.
        """
        if volume.needs_voxels():
            volume.prepare_voxels(scene, assets)
            self.voxelize(volume)
            volume.voxels_done()
        if volume.collect_lights(scene):
            self.light(volume)
            volume.lighting_done()

    def gather(
        mut self,
        node: VXGINode,
        view: DepthView,
        normals: List[Vector3],
        camera_world: Matrix4,
        frame_id: Int,
    ) raises -> VxgiFrame:
        """Gather every pixel on the device, as `VXGINode.gather` does on
        the host.

        Args:
            node: The pass, with its volume up to date.
            view: The frame's depth, and the camera's projection.
            normals: One view-space normal a pixel.
            camera_world: The camera's world matrix.
            frame_id: The frame's number.

        Returns:
            The two images.

        Raises:
            Error: If the pass's settings are refused, there is not one
                normal a pixel, or the device fails.
        """
        node.validate()
        var count = view.width * view.height
        if len(normals) != count:
            raise Error("A VXGI pass needs one normal a pixel")
        var flat = List[Float32](capacity=count * 3)
        for normal in normals:
            flat.extend([normal.x, normal.y, normal.z])
        var header = self._floats(node.volume.grid.header())
        var opacity = self._floats(node.volume.opacity)
        var radiance = self._floats(node.volume.radiance)
        var params = self._floats(node.params(view, camera_world, frame_id))
        var depth = self._floats(view.depth)
        var turned = self._floats(flat)
        var pixels = self._floats(
            List[Float32](length=count * VOXEL_FLOATS, fill=0)
        )
        self.context.enqueue_function[pixel_kernel](
            pixels.unsafe_ptr(),
            opacity.unsafe_ptr(),
            radiance.unsafe_ptr(),
            params.unsafe_ptr(),
            depth.unsafe_ptr(),
            turned.unsafe_ptr(),
            header.unsafe_ptr(),
            Int32(view.width),
            Int32(view.height),
            grid_dim=ceildiv(count, BLOCK),
            block_dim=BLOCK,
        )
        var out = List[Float32](length=count * VOXEL_FLOATS, fill=0)
        self._read_floats(pixels, out)
        var frame = VxgiFrame(view.width, view.height)
        for slot in range(count):
            var at = slot * VOXEL_FLOATS
            frame.add(
                SIMD[DType.float32, 4](
                    out[at], out[at + 1], out[at + 2], out[at + 3]
                )
            )
        return frame^

    def render(
        mut self,
        mut node: VXGINode,
        view: DepthView,
        camera_world: Matrix4,
        scene: Scene,
        assets: Assets,
        frame_id: Int = 0,
    ) raises -> VxgiFrame:
        """Update the pass's volume and gather every pixel on the device,
        as `VXGINode.render` does on the host.

        Args:
            node: The pass.
            view: The frame's depth, and the camera's projection.
            camera_world: The camera's world matrix.
            scene: The scene the frame shows. It must be current.
            assets: Where its meshes' geometries, materials and textures
                are.
            frame_id: The frame's number.

        Returns:
            The two images.

        Raises:
            Error: Anything `update` or `gather` raises.
        """
        node.validate()
        self.update(node.volume, scene, assets)
        return self.gather(node, view, view.normals(), camera_world, frame_id)
