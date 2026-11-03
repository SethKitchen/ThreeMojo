# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An analytic scene for the Streamline tests: a checkered floor under a sky.

Each sample is computed from the ray through it, so a frame costs almost
nothing, and the true image at the output size is known: the mean of 16
samples in each output pixel. The floor's 0.25 meter tiles shrink below a
render pixel in the distance, so one render cannot hold them. An upscaler
that uses the jitter and the history gets closer to the true image than one
that reads one render.

A sample at render pixel (x, y), moved by the offset that `JitteredCamera`
takes, is at x + 0.5 + offset.x across and y + 0.5 + offset.y down.
`frame_constants` tells Streamline the negative of that offset.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.scene import Scene
from extensions.streamline.bundle import BufferData
from extensions.streamline.constants import (
    CameraSnapshot,
    FrameConstants,
    frame_constants,
)
from extensions.streamline.kinds import (
    BUFFER_ALBEDO,
    BUFFER_DEPTH,
    BUFFER_INPUT_COLOR,
    BUFFER_MOTION_VECTORS,
    BUFFER_NORMAL_ROUGHNESS,
    BUFFER_SPECULAR_ALBEDO,
    BUFFER_SPECULAR_HIT_DISTANCE,
    MOTION_PIXELS,
)
from extensions.streamline.sizing import FrameSize
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from std.math import floor, sqrt, tan
from units.si import Angle, DEGREE, Length, METER, RADIAN

comptime NEAR = Float32(0.1)
comptime FAR = Float32(100.0)
comptime TILE = Float32(0.25)
comptime ROUGHNESS = Float32(0.8)
comptime SPECULAR = Float32(0.04)


@fieldwise_init
struct Sample(ImplicitlyCopyable):
    """What one ray sees."""

    var radiance: FloatColor
    var albedo: FloatColor
    var normal: Vector3
    var depth: Float32


def scene_camera() raises -> CameraSnapshot:
    """Return the camera: 40 degrees, 16 by 9, above the floor."""
    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        16.0 / 9.0,
        Length(Float32(NEAR), METER),
        Length(Float32(FAR), METER),
    )
    camera.place(Vector3(0, 1.0, 3.0), Vector3(0, 0.2, 0))
    return CameraSnapshot(camera, Scene())


def constants_for(
    snapshot: CameraSnapshot, render: FrameSize, offset: Vector2, first: Bool
) raises -> FrameConstants:
    """Return the constants of a frame of a camera that does not move."""
    return frame_constants(
        snapshot, snapshot, render, offset, MOTION_PIXELS, first
    )


def sample(
    constants: FrameConstants, size: FrameSize, x: Float32, y: Float32
) -> Sample:
    """Return what the ray through a point of a frame sees.

    Args:
        constants: The frame's constants, for the camera.
        size: The frame's size.
        x: Pixels across from the left edge.
        y: Pixels down from the top edge.

    Returns:
        The radiance, the albedo, the normal and the depth from 0 to 1.
    """
    var half = tan(constants.camera_fov.to(RADIAN) / 2)
    var across = (
        (2 * x / Float32(size.width) - 1) * half * constants.camera_aspect
    )
    var up = (1 - 2 * y / Float32(size.height)) * half
    var forward = constants.camera_forward
    var right = constants.camera_right
    var top = constants.camera_up
    var dx = forward.x + across * right.x + up * top.x
    var dy = forward.y + across * right.y + up * top.y
    var dz = forward.z + across * right.z + up * top.z
    var origin = constants.camera_position
    if dy < -1e-6:
        # The ray's forward part is one, so t is the view depth.
        var t = -origin.y / dy
        if t < FAR:
            var hx = origin.x + t * dx
            var hz = origin.z + t * dz
            var tile = Int(floor(hx / TILE)) + Int(floor(hz / TILE))
            var albedo = FloatColor(0.85, 0.84, 0.78, 1)
            if tile % 2 != 0:
                albedo = FloatColor(0.12, 0.22, 0.52, 1)
            # Ambient light and a sun at 0.8 of the zenith's cosine.
            var light = Float32(0.3 + 0.9 * 0.8)
            var depth = FAR / (FAR - NEAR) * (1 - NEAR / t)
            return Sample(
                FloatColor(
                    albedo.r * light, albedo.g * light, albedo.b * light, 1
                ),
                albedo,
                Vector3(0, 1, 0),
                depth,
            )
    var length = sqrt(dx * dx + dy * dy + dz * dz)
    var height = max(Float32(0), dy / length)
    var sky = FloatColor(0.45 - 0.2 * height, 0.6 - 0.1 * height, 0.85, 1)
    return Sample(
        sky, sky, Vector3(-dx / length, -dy / length, -dz / length), 1
    )


def truth(constants: FrameConstants, output: FrameSize) -> List[FloatColor]:
    """Return the true image at the output size: 16 samples a pixel."""
    var colors = List[FloatColor](capacity=output.width * output.height)
    for y in range(output.height):
        for x in range(output.width):
            var r = Float32(0)
            var g = Float32(0)
            var b = Float32(0)
            for j in range(4):
                for i in range(4):
                    var seen = sample(
                        constants,
                        output,
                        Float32(x) + (Float32(i) + 0.5) / 4,
                        Float32(y) + (Float32(j) + 0.5) / 4,
                    )
                    r += seen.radiance.r
                    g += seen.radiance.g
                    b += seen.radiance.b
            colors.append(FloatColor(r / 16, g / 16, b / 16, 1))
    return colors^


def _noise(x: Int, y: Int, frame: Int) -> Float32:
    """Return a hashed number from 0 to 2 whose mean is one."""
    var h = (
        UInt32(x) * 0x8DA6B343
        ^ UInt32(y) * 0xD8163841
        ^ UInt32(frame + 1) * 0xCB1AB31F
    )
    h ^= h >> 15
    h *= 0x2C1B3C6D
    h ^= h >> 12
    h *= 0x297A2D39
    h ^= h >> 15
    return Float32(h >> 8) / Float32(1 << 24) * 2


def render_colors(
    constants: FrameConstants,
    render: FrameSize,
    offset: Vector2,
    noisy_frame: Int = -1,
) -> List[FloatColor]:
    """Return a render, one sample a pixel, moved by a jitter offset.

    Args:
        constants: The frame's constants.
        render: The render's size.
        offset: The offset that `JitteredCamera` would take.
        noisy_frame: Below zero for a clean render. Otherwise the floor's
            light is scaled by noise from 0 to 2 that this number seeds,
            the way one path a pixel scatters it.

    Returns:
        The render, row by row from the top.
    """
    var colors = List[FloatColor](capacity=render.width * render.height)
    for y in range(render.height):
        for x in range(render.width):
            var seen = sample(
                constants,
                render,
                Float32(x) + 0.5 + offset.x,
                Float32(y) + 0.5 + offset.y,
            )
            var color = seen.radiance
            if noisy_frame >= 0 and seen.depth < 1:
                var scale = _noise(x, y, noisy_frame)
                color = FloatColor(
                    color.r * scale, color.g * scale, color.b * scale, 1
                )
            colors.append(color)
    return colors^


def _flat(colors: List[FloatColor]) -> List[Float32]:
    """Return colors as four floats each."""
    var values = List[Float32](capacity=4 * len(colors))
    for color in colors:
        values.append(color.r)
        values.append(color.g)
        values.append(color.b)
        values.append(color.a)
    return values^


def super_resolution_buffers(
    constants: FrameConstants, render: FrameSize, offset: Vector2
) -> List[BufferData]:
    """Return the color, the depth and the motion vectors of a frame."""
    var depth = List[Float32](capacity=render.width * render.height)
    for y in range(render.height):
        for x in range(render.width):
            depth.append(
                sample(
                    constants,
                    render,
                    Float32(x) + 0.5 + offset.x,
                    Float32(y) + 0.5 + offset.y,
                ).depth
            )
    var buffers = List[BufferData]()
    buffers.append(
        BufferData(
            BUFFER_INPUT_COLOR,
            render.width,
            render.height,
            4,
            _flat(render_colors(constants, render, offset)),
        )
    )
    buffers.append(
        BufferData(BUFFER_DEPTH, render.width, render.height, 1, depth^)
    )
    buffers.append(
        BufferData(
            BUFFER_MOTION_VECTORS,
            render.width,
            render.height,
            2,
            List[Float32](length=2 * render.width * render.height, fill=0),
        )
    )
    return buffers^


def ray_reconstruction_buffers(
    constants: FrameConstants, render: FrameSize, offset: Vector2, frame: Int
) -> List[BufferData]:
    """Return a noisy frame and the guides that Ray Reconstruction reads."""
    var count = render.width * render.height
    var depth = List[Float32](capacity=count)
    var albedo = List[Float32](capacity=4 * count)
    var specular = List[Float32](capacity=4 * count)
    var normals = List[Float32](capacity=4 * count)
    for y in range(render.height):
        for x in range(render.width):
            var seen = sample(
                constants,
                render,
                Float32(x) + 0.5 + offset.x,
                Float32(y) + 0.5 + offset.y,
            )
            depth.append(seen.depth)
            albedo.append(seen.albedo.r)
            albedo.append(seen.albedo.g)
            albedo.append(seen.albedo.b)
            albedo.append(1)
            for _ in range(3):
                specular.append(SPECULAR)
            specular.append(1)
            normals.append(seen.normal.x)
            normals.append(seen.normal.y)
            normals.append(seen.normal.z)
            normals.append(ROUGHNESS)
    var buffers = List[BufferData]()
    buffers.append(
        BufferData(
            BUFFER_INPUT_COLOR,
            render.width,
            render.height,
            4,
            _flat(render_colors(constants, render, offset, frame)),
        )
    )
    buffers.append(
        BufferData(BUFFER_DEPTH, render.width, render.height, 1, depth^)
    )
    buffers.append(
        BufferData(
            BUFFER_MOTION_VECTORS,
            render.width,
            render.height,
            2,
            List[Float32](length=2 * count, fill=0),
        )
    )
    buffers.append(
        BufferData(BUFFER_ALBEDO, render.width, render.height, 4, albedo^)
    )
    buffers.append(
        BufferData(
            BUFFER_SPECULAR_ALBEDO, render.width, render.height, 4, specular^
        )
    )
    buffers.append(
        BufferData(
            BUFFER_NORMAL_ROUGHNESS, render.width, render.height, 4, normals^
        )
    )
    buffers.append(
        BufferData(
            BUFFER_SPECULAR_HIT_DISTANCE,
            render.width,
            render.height,
            1,
            List[Float32](length=count, fill=0),
        )
    )
    return buffers^


def mean_squared_error(
    a: List[FloatColor], b: List[FloatColor], size: FrameSize
) -> Float64:
    """Return the mean squared error of the colors, without an 8-pixel
    border."""
    var sum = Float64(0)
    var n = 0
    for y in range(8, size.height - 8):
        for x in range(8, size.width - 8):
            var p = a[y * size.width + x]
            var q = b[y * size.width + x]
            sum += Float64(
                (p.r - q.r) ** 2 + (p.g - q.g) ** 2 + (p.b - q.b) ** 2
            )
            n += 3
    return sum / Float64(n)
