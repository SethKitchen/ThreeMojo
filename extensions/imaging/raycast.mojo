# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Draw a volume by casting a ray through each pixel, on the CPU.

The rays live in the volume frame: voxel `(i, j, k)` has its center at
`(i * spacing_x, j * spacing_y, k * spacing_z)` meters. The box of the
volume reaches half a voxel past the outer centers. A ray samples the
volume at even steps between the points where it enters and leaves the
box. Each sample is a trilinear blend of eight voxels.

`COMPOSITE` looks up each sample in a transfer function and blends from
front to back. The opacity of a point is for a step of one voxel and is
corrected for the real step. A sample is shaded by its gradient with a
light at the eye. The ray stops when it is 99 percent opaque.

`MAXIMUM_INTENSITY` keeps the largest sample and shows it through the
volume's window. `MONOCHROME1` volumes show it inverted.

`ISOSURFACE` stops at the first sample whose value reaches the iso value.
The crossing lies on the straight line between that sample and the one
before it. The surface there takes the transfer function's color at the
iso value, opaque, and is shaded by the gradient with a light at the eye.
A ray that enters the box at or above the iso value stops at its first
sample, so a crop shows the cut face.

The rows of the image are split among CPU tasks. Each pixel depends only
on its own ray, so the image does not depend on the number of tasks.
"""

from extensions.imaging.ids import (
    COMPOSITE,
    ISOSURFACE,
    MONOCHROME1,
    RenderMode,
    require_mode,
)
from extensions.imaging.image_volume import ImageVolume
from extensions.imaging.transfer import (
    Rgba,
    TransferFunction,
    WindowLevel,
    clamp_unit,
    corrected_opacity,
)
from extensions.sdf.vector import V3, cross, dot, length, normalize, v3
from render.framebuffer import Framebuffer
from render.tasks import TaskGroup
from std.math import cos, inf, isfinite, max, min, pi, sin, tan
from std.sys import num_logical_cores
from units.si import Angle64, METER, RADIAN

# The entries of the transfer table that a render looks colors up in.
comptime TABLE_SIZE = 1024
# A ray stops when its opacity reaches this.
comptime OPAQUE = Float32(0.99)
# The largest image side, in pixels.
comptime MAX_SIDE = 8192


struct VolumeCamera(ImplicitlyCopyable):
    """A pinhole camera in the volume frame."""

    var eye: V3
    """The camera's place, in meters."""
    var forward: V3
    """The unit direction the camera looks along."""
    var right: V3
    """The unit direction to the right of the image."""
    var up: V3
    """The unit direction to the top of the image."""
    var half_height: Float64
    """The tangent of half the vertical field of view."""
    var width: Int
    """The image width in pixels."""
    var height: Int
    """The image height in pixels."""

    def __init__(
        out self,
        eye: V3,
        target: V3,
        up: V3,
        field: Angle64,
        width: Int,
        height: Int,
    ) raises:
        """Create a camera that looks from `eye` at `target`.

        Args:
            eye: The camera's place, in meters.
            target: The point at the center of the image, in meters.
            up: A direction that points to the top of the image.
            field: The vertical field of view, above 0 and below pi.
            width: The image width in pixels, from 1 to 8192.
            height: The image height in pixels, from 1 to 8192.

        Raises:
            Error: If the image size is out of range, the field is out of
                range, the eye is at the target, or `up` is along the view.
        """
        if width < 1 or height < 1:
            raise Error("A volume camera needs at least one pixel")
        if width > MAX_SIDE or height > MAX_SIDE:
            raise Error("A volume camera image has at most 8192 pixels a side")
        var angle = field.to(RADIAN)
        if not (angle > 0) or not (angle < pi):
            raise Error("A field of view must be between 0 and pi")
        var view = target - eye
        if not (length(view) > 0):
            raise Error("A volume camera's eye cannot be at its target")
        var forward = normalize(view)
        var side = cross(forward, up)
        if not (length(side) > 1.0e-9 * length(up)):
            raise Error("A volume camera's up cannot lie along its view")
        self.eye = eye
        self.forward = forward
        self.right = normalize(side)
        self.up = cross(self.right, forward)
        self.half_height = tan(angle / 2.0)
        self.width = width
        self.height = height

    def ray(self, x: Int, y: Int) -> V3:
        """Return the unit direction through the center of a pixel.

        Args:
            x: The column, from the left.
            y: The row, from the top.

        Returns:
            The direction.
        """
        var aspect = Float64(self.width) / Float64(self.height)
        var u = (2.0 * (Float64(x) + 0.5) / Float64(self.width) - 1.0) * (
            aspect * self.half_height
        )
        var w = (1.0 - 2.0 * (Float64(y) + 0.5) / Float64(self.height)) * (
            self.half_height
        )
        return normalize(self.forward + self.right * u + self.up * w)


def volume_center(volume: ImageVolume) -> V3:
    """Return the center of a volume's voxel centers, in the volume frame.

    Args:
        volume: The volume.

    Returns:
        Half of `extent()`.
    """
    return volume.extent() * 0.5


def orbit_camera(
    volume: ImageVolume,
    azimuth: Angle64,
    elevation: Angle64,
    field: Angle64,
    width: Int,
    height: Int,
) raises -> VolumeCamera:
    """Return a camera that circles the volume and frames all of it.

    At zero azimuth and zero elevation the camera looks along +j with
    -k up, so an axial series shows its front. Azimuth turns the camera
    about k. Elevation raises it toward -k.

    Args:
        volume: The volume to frame.
        azimuth: The turn about k.
        elevation: The angle above the ring, below a quarter turn in size.
        field: The vertical field of view.
        width: The image width in pixels.
        height: The image height in pixels.

    Returns:
        The camera.

    Raises:
        Error: If the elevation is a quarter turn or more in size, or the
            camera refuses its view.
    """
    var a = azimuth.to(RADIAN)
    var e = elevation.to(RADIAN)
    if not (abs(e) < pi / 2.0):
        raise Error("An orbit elevation must be below a quarter turn")
    var center = volume_center(volume)
    var half = volume.extent() * 0.5
    var radius = length(half) + 0.5 * max(
        volume.spacing_x.to(METER),
        max(volume.spacing_y.to(METER), volume.spacing_z.to(METER)),
    )
    var angle = field.to(RADIAN)
    var reach = radius / sin(angle / 2.0) * 1.05
    var back = v3(-sin(a) * cos(e), -cos(a) * cos(e), -sin(e))
    return VolumeCamera(
        center + back * reach, center, v3(0, 0, -1), field, width, height
    )


def ray_box(
    origin: V3, direction: V3, low: V3, high: V3
) -> Tuple[Bool, Float64, Float64]:
    """Return where a ray enters and leaves a box, from the slab method.

    Args:
        origin: The start of the ray.
        direction: The direction of the ray. Not zero.
        low: The low corner of the box.
        high: The high corner of the box.

    Returns:
        Whether the ray meets the box ahead of its origin, and the two
        distances along it, in units of `direction`. The first distance
        is zero when the origin is inside.
    """
    var near = 0.0
    var far = inf[DType.float64]()
    var axes = _slab(origin.x, direction.x, low.x, high.x, near, far)
    axes = axes and _slab(origin.y, direction.y, low.y, high.y, near, far)
    axes = axes and _slab(origin.z, direction.z, low.z, high.z, near, far)
    if not axes:
        return (False, 0.0, 0.0)
    return (near < far, near, far)


def _slab(
    origin: Float64,
    direction: Float64,
    low: Float64,
    high: Float64,
    mut near: Float64,
    mut far: Float64,
) -> Bool:
    """Narrow a ray's range to one slab, and return False on a miss."""
    if direction == 0:
        return origin >= low and origin <= high
    var a = (low - origin) / direction
    var b = (high - origin) / direction
    near = max(near, min(a, b))
    far = min(far, max(a, b))
    return True


@fieldwise_init
struct _Scene(ImplicitlyCopyable):
    """What every ray of one render reads."""

    var camera: VolumeCamera
    var low: V3
    var high: V3
    var scale: V3
    var step: Float64
    var step_voxels: Float64
    var lowest: Float64
    var table_scale: Float64
    var mode: RenderMode
    var ambient: Float32
    var background: Rgba
    var window: WindowLevel
    var inverted: Bool
    var iso_value: Float64
    var iso_color: Rgba


def _gradient(
    volume: ImageVolume, x: Float64, y: Float64, z: Float64, scale: V3
) -> V3:
    """Return the value gradient at a point, per meter."""
    var gx = volume.trilinear(x + 1, y, z) - volume.trilinear(x - 1, y, z)
    var gy = volume.trilinear(x, y + 1, z) - volume.trilinear(x, y - 1, z)
    var gz = volume.trilinear(x, y, z + 1) - volume.trilinear(x, y, z - 1)
    return v3(
        Float64(gx) * scale.x * 0.5,
        Float64(gy) * scale.y * 0.5,
        Float64(gz) * scale.z * 0.5,
    )


def _composite(
    volume: ImageVolume,
    table: List[Rgba],
    scene: _Scene,
    direction: V3,
    near: Float64,
    far: Float64,
) -> Rgba:
    """Blend the samples of one ray from front to back."""
    var r = Float32(0)
    var g = Float32(0)
    var b = Float32(0)
    var a = Float32(0)
    var t = near + scene.step * 0.5
    var last = len(table) - 1
    while t < far and a < OPAQUE:
        var p = scene.camera.eye + direction * t
        var x = p.x * scene.scale.x
        var y = p.y * scene.scale.y
        var z = p.z * scene.scale.z
        var value = Float64(volume.trilinear(x, y, z))
        var slot = Int((value - scene.lowest) * scene.table_scale + 0.5)
        ref color = table[min(max(slot, 0), last)]
        if color.a > 0:
            var light = Float32(1)
            var normal = _gradient(volume, x, y, z, scene.scale)
            var size = length(normal)
            if size > 0:
                var facing = Float32(abs(dot(normal, direction)) / size)
                light = scene.ambient + (1 - scene.ambient) * facing
            var weight = (1 - a) * color.a
            r += weight * color.r * light
            g += weight * color.g * light
            b += weight * color.b * light
            a += weight
        t += scene.step
    return Rgba(r, g, b, a)


def _maximum(
    volume: ImageVolume,
    scene: _Scene,
    direction: V3,
    near: Float64,
    far: Float64,
) -> Rgba:
    """Return the windowed gray of the largest sample on one ray."""
    var middle = scene.camera.eye + direction * ((near + far) * 0.5)
    var best = Float64(
        volume.trilinear(
            middle.x * scene.scale.x,
            middle.y * scene.scale.y,
            middle.z * scene.scale.z,
        )
    )
    var t = near + scene.step * 0.5
    while t < far:
        var p = scene.camera.eye + direction * t
        var value = Float64(
            volume.trilinear(
                p.x * scene.scale.x, p.y * scene.scale.y, p.z * scene.scale.z
            )
        )
        best = max(best, value)
        t += scene.step
    var gray = Float32(scene.window.apply(best))
    if scene.inverted:
        gray = 1 - gray
    return Rgba(gray, gray, gray, 1)


def _crossing(
    before: Float64,
    before_value: Float64,
    at: Float64,
    value: Float64,
    iso: Float64,
) -> Float64:
    """Return where a straight line between two samples reaches `iso`.

    `before_value` is below `iso` and `value` is at or above it.
    """
    return before + (iso - before_value) / (value - before_value) * (
        at - before
    )


def _sample(
    volume: ImageVolume, scene: _Scene, direction: V3, t: Float64
) -> Float64:
    """Return the value at distance `t` along a ray."""
    var p = scene.camera.eye + direction * t
    return Float64(
        volume.trilinear(
            p.x * scene.scale.x, p.y * scene.scale.y, p.z * scene.scale.z
        )
    )


def _shade(
    volume: ImageVolume, scene: _Scene, direction: V3, t: Float64
) -> Rgba:
    """Return the iso color at distance `t`, lit by the gradient there."""
    var p = scene.camera.eye + direction * t
    var normal = _gradient(
        volume,
        p.x * scene.scale.x,
        p.y * scene.scale.y,
        p.z * scene.scale.z,
        scene.scale,
    )
    var light = Float32(1)
    var size = length(normal)
    if size > 0:
        var facing = Float32(abs(dot(normal, direction)) / size)
        light = scene.ambient + (1 - scene.ambient) * facing
    ref color = scene.iso_color
    return Rgba(color.r * light, color.g * light, color.b * light, 1)


def _first_hit(
    volume: ImageVolume,
    scene: _Scene,
    direction: V3,
    near: Float64,
    far: Float64,
) -> Rgba:
    """Return the shaded surface where a ray first reaches the iso value."""
    var iso = scene.iso_value
    var before = near + scene.step * 0.5
    var before_value = _sample(volume, scene, direction, before)
    if before_value >= iso:
        return _shade(volume, scene, direction, before)
    var t = before + scene.step
    while t < far:
        var value = _sample(volume, scene, direction, t)
        if value >= iso:
            var hit = _crossing(before, before_value, t, value, iso)
            return _shade(volume, scene, direction, hit)
        before = t
        before_value = value
        t += scene.step
    return Rgba(0, 0, 0, 0)


def _byte(value: Float32) -> UInt8:
    """Return a channel from zero to one as a byte."""
    return UInt8(Int(clamp_unit(value) * 255 + 0.5))


__async def _render_rows(
    volume: Pointer[ImageVolume, ImmutAnyOrigin],
    table: Pointer[List[Rgba], ImmutAnyOrigin],
    scene: _Scene,
    pixels: MutPointer[UInt8, MutAnyOrigin],
    first: Int,
    past: Int,
):
    """Cast the rays of rows `first` to `past`."""
    var width = scene.camera.width
    for y in range(first, past):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var direction = scene.camera.ray(x, y)
            var hit = ray_box(
                scene.camera.eye, direction, scene.low, scene.high
            )
            var color = Rgba(0, 0, 0, 0)
            if hit[0]:
                if scene.mode == COMPOSITE:
                    color = _composite(
                        volume[], table[], scene, direction, hit[1], hit[2]
                    )
                elif scene.mode == ISOSURFACE:
                    color = _first_hit(
                        volume[], scene, direction, hit[1], hit[2]
                    )
                else:
                    color = _maximum(volume[], scene, direction, hit[1], hit[2])
            var clear = 1 - color.a
            var at = (y * width + x) * 4
            pixels[unsafe_offset=at] = _byte(
                color.r + clear * scene.background.r
            )
            pixels[unsafe_offset=at + 1] = _byte(
                color.g + clear * scene.background.g
            )
            pixels[unsafe_offset=at + 2] = _byte(
                color.b + clear * scene.background.b
            )
            pixels[unsafe_offset=at + 3] = 255


def _cast(
    volume: ImageVolume, table: List[Rgba], scene: _Scene, tasks: Int
) -> List[UInt8]:
    """Return the RGBA bytes of every ray, cast by `tasks` tasks."""
    var width = scene.camera.width
    var height = scene.camera.height
    var pixels = List[UInt8](length=width * height * 4, fill=0)
    var group = TaskGroup()
    for task in range(tasks):  # pragma: no branch
        group.create_task(
            _render_rows(
                Pointer(to=volume).unsafe_origin_cast[ImmutAnyOrigin](),
                Pointer(to=table).unsafe_origin_cast[ImmutAnyOrigin](),
                scene,
                pixels.unsafe_ptr().unsafe_origin_cast[MutAnyOrigin](),
                task * height // tasks,
                (task + 1) * height // tasks,
            )
        )
    group.wait()
    return pixels^


def _require_crop(low: Float64, high: Float64) raises:
    """Refuse a crop range that is outside zero to one or empty."""
    if not (low >= 0) or not (high <= 1) or not (low < high):
        raise Error("A crop must run from 0 to 1 and rise on each axis")


def _scaled(size: V3, fraction: V3) -> V3:
    """Return each component of `size` times that of `fraction`."""
    return v3(size.x * fraction.x, size.y * fraction.y, size.z * fraction.z)


def render_volume(
    volume: ImageVolume,
    camera: VolumeCamera,
    transfer: TransferFunction,
    mode: RenderMode,
    step_voxels: Float64,
    ambient: Float32,
    background: Rgba,
    crop_low: V3 = V3(0, 0, 0),
    crop_high: V3 = V3(1, 1, 1),
    iso_value: Float64 = 0.0,
    threads: Int = 0,
) raises -> Framebuffer:
    """Return the image of a volume seen by a camera.

    Args:
        volume: The volume to draw.
        camera: The camera, in the volume frame.
        transfer: The colors and opacities for `COMPOSITE`, and the color
            of the surface for `ISOSURFACE`. It needs at least one point in
            every mode.
        mode: `COMPOSITE`, `MAXIMUM_INTENSITY` or `ISOSURFACE`.
        step_voxels: The distance between samples, in units of the
            smallest spacing. From 0.05 to 4.
        ambient: The light a sample gets when it faces away from the eye,
            from zero to one. One turns the shading off.
        background: The color behind the volume. Its opacity is ignored.
        crop_low: The low corner of the part of the box to draw, as a
            fraction of the box on each axis.
        crop_high: The high corner of the part to draw, as a fraction.
            Each fraction is from zero to one and above `crop_low`'s.
        iso_value: The value of the surface for `ISOSURFACE`. Finite.
        threads: The tasks to use. Zero means one for each logical core.

    Returns:
        The image, with every pixel opaque.

    Raises:
        Error: If the mode is not valid, the step or the ambient light is
            out of range, the crop is out of range or empty, the iso value
            is not finite, `threads` is negative, the transfer function has
            no points, or the volume's window is not finite with a positive
            width.
    """
    require_mode(mode)
    if not (step_voxels >= 0.05) or not (step_voxels <= 4.0):
        raise Error("A ray step must be from 0.05 to 4 voxels")
    if not (ambient >= 0) or not (ambient <= 1):
        raise Error("The ambient light must be from 0 to 1")
    _require_crop(crop_low.x, crop_high.x)
    _require_crop(crop_low.y, crop_high.y)
    _require_crop(crop_low.z, crop_high.z)
    if not isfinite(iso_value):
        raise Error("An iso value must be finite")
    if threads < 0:
        raise Error("A thread count must not be negative")
    var span = volume.value_range()
    var lowest = Float64(span[0])
    var highest = max(Float64(span[1]), lowest + 1.0e-6)
    var raw = transfer.table(lowest, highest, TABLE_SIZE)
    var table = List[Rgba]()
    for entry in raw:  # pragma: no branch
        table.append(
            Rgba(
                entry.r,
                entry.g,
                entry.b,
                corrected_opacity(entry.a, step_voxels),
            )
        )
    var sx = volume.spacing_x.to(METER)
    var sy = volume.spacing_y.to(METER)
    var sz = volume.spacing_z.to(METER)
    var smallest = min(sx, min(sy, sz))
    var low = v3(-sx / 2, -sy / 2, -sz / 2)
    var size = volume.extent() + v3(sx, sy, sz)
    var scene = _Scene(
        camera,
        low + _scaled(size, crop_low),
        low + _scaled(size, crop_high),
        v3(1.0 / sx, 1.0 / sy, 1.0 / sz),
        step_voxels * smallest,
        step_voxels,
        lowest,
        Float64(TABLE_SIZE - 1) / (highest - lowest),
        mode,
        ambient,
        background,
        WindowLevel(volume.window_center, volume.window_width),
        volume.photometric == MONOCHROME1,
        iso_value,
        transfer.sample(iso_value),
    )
    var tasks = threads
    if tasks == 0:
        tasks = num_logical_cores()
    tasks = max(1, min(tasks, camera.height))
    var pixels = _cast(volume, table, scene, tasks)
    return Framebuffer(camera.width, camera.height, pixels^)
