# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The frames that the native Streamline host reads, and the frame it writes.

ThreeMojo runs on Linux, macOS and WSL 2, and Streamline runs on Windows with
Direct3D. `extensions/streamline/native/host.cpp` is a small Windows program
that opens a Direct3D 12 device, loads `sl.interposer`, and runs one feature
on a sequence of frames. This module writes that sequence and reads the frame
that comes back. A program in WSL 2 can start the Windows program directly.

A `FrameBundle` holds the options of one feature and a list of frames. Each
frame has the `FrameConstants` of `frame_constants` and its buffers.
`add` checks a frame with the checks of `options`, `constants` and `tags`, so
the host gets nothing that Streamline would refuse. The host makes the output
color itself.

The file is little-endian. Every field is four bytes: an unsigned integer or
a 32-bit float. A matrix is the sixteen floats of `Matrix4.elements`, which
is the memory layout of `sl::float4x4`.

    header   "TMSL", version 1, feature, mode, preset,
             normal and roughness mode, flags, pre-exposure, exposure scale,
             render width and height, output width and height, passes,
             frame count, world to camera view, camera view to world
    frame    the four matrices of the constants, the jitter, the motion
             vector scale, the camera's position, up, right and forward
             axes, near, far, vertical field of view, aspect ratio,
             flags, buffer count
    buffer   Streamline buffer type, width, height, channels, then each
             texel's channels, row by row from the top

The result is "TMSR", version 1, width, height, then four floats a pixel,
row by row from the top.
"""

from extensions.streamline.constants import (
    FrameConstants,
    check_frame_constants,
)
from extensions.streamline.kinds import (
    BUFFER_OUTPUT_COLOR,
    BufferKind,
    Feature,
    RAY_RECONSTRUCTION,
    SUPER_RESOLUTION,
)
from extensions.streamline.options import (
    RayReconstructionOptions,
    SuperResolutionOptions,
    check_ray_reconstruction,
    check_super_resolution,
)
from extensions.streamline.sizing import FrameSize
from extensions.streamline.tags import (
    TaggedBuffer,
    check_ray_reconstruction_tags,
    check_super_resolution_tags,
)
from math.matrix4 import Matrix4
from render.framebuffer import FloatColor
from std.math import isfinite
from std.memory import bitcast
from units.si import METER, RADIAN

comptime BUNDLE_VERSION = 1
"""The version of the frame file that this module writes."""

comptime RESULT_VERSION = 1
"""The version of the result file that this module reads."""

comptime MOST_PASSES = 64
"""The most times that the host can play the frames."""

# The byte of the header where the frame count is.
comptime _COUNT_AT = 56
# The size of the header in bytes.
comptime _HEADER = 188
# The size of a result's header in bytes.
comptime _RESULT_HEADER = 16


def _put(mut bytes: List[UInt8], at: Int, word: UInt32):
    """Write a word, least significant byte first."""
    bytes[at] = UInt8(word & 0xFF)
    bytes[at + 1] = UInt8((word >> 8) & 0xFF)
    bytes[at + 2] = UInt8((word >> 16) & 0xFF)
    bytes[at + 3] = UInt8(word >> 24)


def _get(bytes: List[UInt8], at: Int) -> UInt32:
    """Read a word, least significant byte first."""
    return (
        UInt32(bytes[at])
        | (UInt32(bytes[at + 1]) << 8)
        | (UInt32(bytes[at + 2]) << 16)
        | (UInt32(bytes[at + 3]) << 24)
    )


def _grow(mut bytes: List[UInt8], words: Int) -> Int:
    """Add room for some words, and return where the room starts."""
    var start = len(bytes)
    bytes.resize(start + 4 * words, 0)
    return start


def _put_magic(mut bytes: List[UInt8], magic: String):
    """Write four ASCII letters."""
    var letters = magic.as_bytes()
    for index in range(4):
        bytes[index] = letters[index]


def _has_magic(bytes: List[UInt8], magic: String) -> Bool:
    """Return True if the bytes start with four ASCII letters."""
    var letters = magic.as_bytes()
    for index in range(4):
        if bytes[index] != letters[index]:
            return False
    return True


def _put_matrix(mut bytes: List[UInt8], at: Int, matrix: Matrix4):
    """Write the sixteen floats of a matrix in memory order."""
    for index in range(16):
        _put(
            bytes, at + 4 * index, bitcast[DType.uint32](matrix.elements[index])
        )


@fieldwise_init
struct BufferData(Copyable, Movable):
    """The texels of one buffer of a frame, as 32-bit floats."""

    var kind: BufferKind
    """What the buffer holds."""
    var width: Int
    """Its width in texels."""
    var height: Int
    """Its height in texels."""
    var channels: Int
    """How many channels a texel has: one to four."""
    var values: List[Float32]
    """Each texel's channels, row by row from the top. Linear, not sRGB."""

    def tag(self) -> TaggedBuffer:
        """Return the tag that this buffer gives a frame.

        Returns:
            Its kind, size and channel count, linear.
        """
        return TaggedBuffer(
            self.kind, self.width, self.height, self.channels, False
        )


struct FrameBundle(Movable):
    """The options of one feature and the frames to run it on."""

    var feature: Feature
    """Super Resolution or Ray Reconstruction."""
    var super_resolution: SuperResolutionOptions
    """The options when the feature is Super Resolution."""
    var ray_reconstruction: RayReconstructionOptions
    """The options when the feature is Ray Reconstruction."""
    var render: FrameSize
    """The size that each frame is rendered at."""
    var output: FrameSize
    """The size of the frame that the host returns."""
    var frames: Int
    """How many frames the bundle holds."""
    # The file so far, with a frame count of zero.
    var _bytes: List[UInt8]

    def __init__(
        out self,
        options: SuperResolutionOptions,
        render: FrameSize,
        passes: Int = 1,
    ) raises:
        """Start a bundle for Super Resolution.

        Args:
            options: The options, checked with `check_super_resolution`.
            render: The size that each frame is rendered at.
            passes: How many times the host plays the frames. The frame
                that comes back is the last frame of the last pass.

        Raises:
            Error: If the options are refused, a side of the render is
                below one pixel, or the passes are not 1 to `MOST_PASSES`.
        """
        check_super_resolution(options)
        self.feature = SUPER_RESOLUTION
        self.super_resolution = options.copy()
        self.ray_reconstruction = RayReconstructionOptions(
            options.mode, options.output_width, options.output_height
        )
        self.render = render
        self.output = FrameSize(options.output_width, options.output_height)
        self.frames = 0
        self._bytes = List[UInt8]()
        self._start(
            options.preset().value,
            0,
            options.colors_are_hdr,
            options.auto_exposure,
            options.alpha_upscaling,
            options.pre_exposure,
            options.exposure_scale,
            passes,
            Matrix4(),
            Matrix4(),
        )

    def __init__(
        out self,
        options: RayReconstructionOptions,
        render: FrameSize,
        passes: Int = 1,
    ) raises:
        """Start a bundle for Ray Reconstruction.

        Args:
            options: The options, checked with `check_ray_reconstruction`.
            render: The size that each frame is rendered at.
            passes: How many times the host plays the frames. The frame
                that comes back is the last frame of the last pass.

        Raises:
            Error: If the options are refused, a side of the render is
                below one pixel, or the passes are not 1 to `MOST_PASSES`.
        """
        check_ray_reconstruction(options)
        self.feature = RAY_RECONSTRUCTION
        self.super_resolution = SuperResolutionOptions(
            options.mode, options.output_width, options.output_height
        )
        self.ray_reconstruction = options.copy()
        self.render = render
        self.output = FrameSize(options.output_width, options.output_height)
        self.frames = 0
        self._bytes = List[UInt8]()
        self._start(
            options.preset().value,
            options.normal_roughness_mode.value,
            options.colors_are_hdr,
            False,
            options.alpha_upscaling,
            options.pre_exposure,
            options.exposure_scale,
            passes,
            options.world_to_camera_view,
            options.camera_view_to_world,
        )

    def _start(
        mut self,
        preset: Int,
        normal_roughness: Int,
        hdr: Bool,
        auto_exposure: Bool,
        alpha: Bool,
        pre_exposure: Float32,
        exposure_scale: Float32,
        passes: Int,
        world_to_view: Matrix4,
        view_to_world: Matrix4,
    ) raises:
        """Check the sizes and the passes, and write the header."""
        if self.render.width < 1 or self.render.height < 1:
            raise Error("A render must be at least one pixel each way")
        if passes < 1 or passes > MOST_PASSES:
            raise Error("The passes must be 1 to " + String(MOST_PASSES))
        _ = _grow(self._bytes, _HEADER // 4)
        _put_magic(self._bytes, "TMSL")
        _put(self._bytes, 4, UInt32(BUNDLE_VERSION))
        _put(self._bytes, 8, UInt32(self.feature.streamline_id()))
        _put(self._bytes, 12, UInt32(self.super_resolution.mode.value))
        _put(self._bytes, 16, UInt32(preset))
        _put(self._bytes, 20, UInt32(normal_roughness))
        var flags = UInt32(0)
        if hdr:
            flags |= 1
        if auto_exposure:
            flags |= 2
        if alpha:
            flags |= 4
        _put(self._bytes, 24, flags)
        _put(self._bytes, 28, bitcast[DType.uint32](pre_exposure))
        _put(self._bytes, 32, bitcast[DType.uint32](exposure_scale))
        _put(self._bytes, 36, UInt32(self.render.width))
        _put(self._bytes, 40, UInt32(self.render.height))
        _put(self._bytes, 44, UInt32(self.output.width))
        _put(self._bytes, 48, UInt32(self.output.height))
        _put(self._bytes, 52, UInt32(passes))
        _put_matrix(self._bytes, 60, world_to_view)
        _put_matrix(self._bytes, 124, view_to_world)

    def add(
        mut self, constants: FrameConstants, buffers: List[BufferData]
    ) raises:
        """Add a frame.

        Args:
            constants: The frame's constants, from `frame_constants`.
            buffers: Every buffer that the frame tags, except the output
                color, which the host makes.

        Raises:
            Error: If the constants are refused, a buffer is the output
                color, a buffer's values do not fill it or are not finite,
                or the tags are refused for the feature.
        """
        check_frame_constants(constants)
        var tags = List[TaggedBuffer]()
        for buffer in buffers:
            if buffer.kind == BUFFER_OUTPUT_COLOR:
                raise Error("The host makes the output color")
            if buffer.channels < 1 or buffer.channels > 4:
                raise Error("A buffer must have one to four channels")
            if (
                buffer.width < 1
                or buffer.height < 1
                or buffer.width > Int(UInt32.MAX)
                or buffer.height > Int(UInt32.MAX)
                or len(buffer.values)
                != buffer.width * buffer.height * buffer.channels
            ):
                raise Error(
                    "The values of the "
                    + buffer.kind.name()
                    + " buffer must fill it"
                )
            tags.append(buffer.tag())
        tags.append(
            TaggedBuffer(
                BUFFER_OUTPUT_COLOR,
                self.output.width,
                self.output.height,
                4,
                False,
            )
        )
        if self.feature == SUPER_RESOLUTION:
            check_super_resolution_tags(
                self.super_resolution, self.render, tags
            )
        else:
            check_ray_reconstruction_tags(
                self.ray_reconstruction, self.render, tags
            )
        for buffer in buffers:
            for value in buffer.values:
                if not isfinite(value):
                    raise Error(
                        "The values of the "
                        + buffer.kind.name()
                        + " buffer must be finite"
                    )
        self._put_constants(constants)
        _put(self._bytes, _grow(self._bytes, 1), UInt32(len(buffers)))
        for buffer in buffers:
            var at = _grow(self._bytes, 4 + len(buffer.values))
            _put(self._bytes, at, UInt32(buffer.kind.streamline_type()))
            _put(self._bytes, at + 4, UInt32(buffer.width))
            _put(self._bytes, at + 8, UInt32(buffer.height))
            _put(self._bytes, at + 12, UInt32(buffer.channels))
            at += 16
            for value in buffer.values:
                _put(self._bytes, at, bitcast[DType.uint32](value))
                at += 4
        self.frames += 1

    def _put_constants(mut self, constants: FrameConstants):
        """Write a frame's constants and their flags."""
        var at = _grow(self._bytes, 85)
        _put_matrix(self._bytes, at, constants.camera_view_to_clip)
        _put_matrix(self._bytes, at + 64, constants.clip_to_camera_view)
        _put_matrix(self._bytes, at + 128, constants.clip_to_prev_clip)
        _put_matrix(self._bytes, at + 192, constants.prev_clip_to_clip)
        var floats: List[Float32] = [
            constants.jitter_offset.x,
            constants.jitter_offset.y,
            constants.mvec_scale.x,
            constants.mvec_scale.y,
            constants.camera_position.x,
            constants.camera_position.y,
            constants.camera_position.z,
            constants.camera_up.x,
            constants.camera_up.y,
            constants.camera_up.z,
            constants.camera_right.x,
            constants.camera_right.y,
            constants.camera_right.z,
            constants.camera_forward.x,
            constants.camera_forward.y,
            constants.camera_forward.z,
            Float32(constants.camera_near.to(METER)),
            Float32(constants.camera_far.to(METER)),
            Float32(constants.camera_fov.to(RADIAN)),
            constants.camera_aspect,
        ]
        at += 256
        for value in floats:
            _put(self._bytes, at, bitcast[DType.uint32](value))
            at += 4
        var marks: List[Bool] = [
            constants.depth_inverted,
            constants.camera_motion_included,
            constants.motion_vectors_3d,
            constants.reset,
            constants.orthographic,
            constants.motion_vectors_dilated,
            constants.motion_vectors_jittered,
        ]
        var flags = UInt32(0)
        for bit in range(len(marks)):
            if marks[bit]:
                flags |= UInt32(1) << UInt32(bit)
        _put(self._bytes, at, flags)

    def encode(self) raises -> List[UInt8]:
        """Return the file that the host reads.

        Returns:
            The header and every frame.

        Raises:
            Error: If the bundle holds no frame.
        """
        if self.frames == 0:
            raise Error("A bundle needs a frame")
        var bytes = self._bytes.copy()
        _put(bytes, _COUNT_AT, UInt32(self.frames))
        return bytes^


def encode_result(
    colors: List[FloatColor], size: FrameSize
) raises -> List[UInt8]:
    """Return the file that the host writes for a frame.

    Args:
        colors: The frame, row by row from the top.
        size: Its size.

    Returns:
        The result file.

    Raises:
        Error: If a side is below one pixel or the colors do not fill the
            frame.
    """
    if size.width < 1 or size.height < 1:
        raise Error("A result must be at least one pixel each way")
    if size.width > Int.MAX // size.height or len(colors) != (
        size.width * size.height
    ):
        raise Error("The colors must fill the result")
    var bytes = List[UInt8]()
    _ = _grow(bytes, _RESULT_HEADER // 4 + 4 * len(colors))
    _put_magic(bytes, "TMSR")
    _put(bytes, 4, UInt32(RESULT_VERSION))
    _put(bytes, 8, UInt32(size.width))
    _put(bytes, 12, UInt32(size.height))
    var at = _RESULT_HEADER
    for color in colors:
        _put(bytes, at, bitcast[DType.uint32](color.r))
        _put(bytes, at + 4, bitcast[DType.uint32](color.g))
        _put(bytes, at + 8, bitcast[DType.uint32](color.b))
        _put(bytes, at + 12, bitcast[DType.uint32](color.a))
        at += 16
    return bytes^


def decode_result(
    bytes: List[UInt8], output: FrameSize
) raises -> List[FloatColor]:
    """Read the frame that the host wrote.

    Args:
        bytes: The result file.
        output: The size that the frame must have.

    Returns:
        The frame, row by row from the top.

    Raises:
        Error: If the file is not a result of this version, its size is not
            `output`, it is cut short or too long, or a value is not finite.
    """
    if len(bytes) < _RESULT_HEADER or not _has_magic(bytes, "TMSR"):
        raise Error("This is not a Streamline result")
    if Int(_get(bytes, 4)) != RESULT_VERSION:
        raise Error("The result's version is not " + String(RESULT_VERSION))
    var width = Int(_get(bytes, 8))
    var height = Int(_get(bytes, 12))
    if width != output.width or height != output.height:
        raise Error(
            "The result is "
            + String(width)
            + " by "
            + String(height)
            + ", not "
            + String(output.width)
            + " by "
            + String(output.height)
        )
    if len(bytes) != _RESULT_HEADER + 16 * width * height:
        raise Error("The result's length does not match its size")
    var colors = List[FloatColor](capacity=width * height)
    var at = _RESULT_HEADER
    for _ in range(width * height):
        var color = FloatColor(
            bitcast[DType.float32](_get(bytes, at)),
            bitcast[DType.float32](_get(bytes, at + 4)),
            bitcast[DType.float32](_get(bytes, at + 8)),
            bitcast[DType.float32](_get(bytes, at + 12)),
        )
        if not (
            isfinite(color.r)
            and isfinite(color.g)
            and isfinite(color.b)
            and isfinite(color.a)
        ):
            raise Error("A result's values must be finite")
        colors.append(color)
        at += 16
    return colors^
