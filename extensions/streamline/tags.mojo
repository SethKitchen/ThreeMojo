# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The buffers a frame tags for DLSS, and whether they are enough.

Streamline reads a frame through resource tags: a buffer, and what it holds.
A feature that misses a buffer, or gets one of the wrong size or format,
fails inside the driver with little to say. `check_super_resolution_tags` and
`check_ray_reconstruction_tags` ask the same questions at the boundary, and
name the buffer.

**What each feature needs**, from Streamline 2.14.16's programming guides for
DLSS and for Ray Reconstruction:

- Super Resolution: the depth, the motion vectors and the input color at the
  render size, and the output color at the output's size. The exposure is
  optional. Without it, or with `auto_exposure`, DLSS finds the exposure.
- Ray Reconstruction: the noisy input color, the motion vectors, the diffuse
  and the specular albedo, one of the depth and the linear depth, and the
  output color. The normals and the roughness are two buffers in the unpacked
  mode, and one buffer, `BUFFER_NORMAL_ROUGHNESS`, in the packed mode. The
  specular motion vectors or the specular hit distance are the last need.

A buffer of a kind that the feature does not read is accepted. Streamline
integrations tag one set of buffers for every feature.

**What is checked of each buffer.** Its size: the render size, except the
output color at the output's size and the exposure at one texel. Its number
of channels, and that an albedo is not sRGB, which DLSS does not support.
The guides do not state the format of every buffer, so only what they state
is checked.
"""

from extensions.streamline.kinds import (
    BUFFER_ALBEDO,
    BUFFER_DEPTH,
    BUFFER_EXPOSURE,
    BUFFER_INPUT_COLOR,
    BUFFER_LINEAR_DEPTH,
    BUFFER_MOTION_VECTORS,
    BUFFER_NORMALS,
    BUFFER_NORMAL_ROUGHNESS,
    BUFFER_OUTPUT_COLOR,
    BUFFER_ROUGHNESS,
    BUFFER_SPECULAR_ALBEDO,
    BUFFER_SPECULAR_HIT_DISTANCE,
    BUFFER_SPECULAR_MOTION_VECTORS,
    BufferKind,
    ROUGHNESS_PACKED,
)
from extensions.streamline.options import (
    RayReconstructionOptions,
    SuperResolutionOptions,
    check_ray_reconstruction,
    check_super_resolution,
)
from extensions.streamline.sizing import FrameSize


@fieldwise_init
struct TaggedBuffer(Copyable, Movable):
    """A buffer that a frame tags: what it holds, its size and its format."""

    # What the buffer holds.
    var kind: BufferKind
    # Its size, in texels.
    var width: Int
    var height: Int
    # How many channels a texel has.
    var channels: Int
    # Whether the texels are sRGB encoded.
    var srgb: Bool


# The fewest and the most channels of each kind, in the order of
# `BufferKind`: the depths, the motion vectors, the colors, the exposure, the
# albedos, the normals, the roughness, the transparency and the guides.
def _fewest_channels() -> List[Int]:
    """Return the fewest channels of each kind of buffer."""
    return [1, 1, 2, 2, 1, 3, 3, 1, 3, 3, 3, 4, 1, 3, 1, 3, 1, 1]


def _most_channels() -> List[Int]:
    """Return the most channels of each kind of buffer."""
    return [1, 1, 2, 2, 1, 4, 4, 1, 4, 4, 4, 4, 1, 4, 1, 4, 1, 1]


def _expected_size(
    kind: BufferKind, render: FrameSize, output: FrameSize
) -> FrameSize:
    """Return the size a kind of buffer has."""
    if kind == BUFFER_OUTPUT_COLOR:
        return output
    if kind == BUFFER_EXPOSURE:
        return FrameSize(1, 1)
    return render


def _check_buffer(
    buffer: TaggedBuffer, render: FrameSize, output: FrameSize
) raises:
    """Refuse a buffer of the wrong kind, size or format."""
    if not buffer.kind.is_valid():
        raise Error("A tagged buffer's kind must be one of the eighteen")
    var name = buffer.kind.name()
    var size = _expected_size(buffer.kind, render, output)
    if buffer.width != size.width or buffer.height != size.height:
        raise Error(
            "The "
            + name
            + " buffer must be "
            + String(size.width)
            + " by "
            + String(size.height)
            + " texels"
        )
    if (
        buffer.channels < _fewest_channels()[buffer.kind.value]
        or buffer.channels > _most_channels()[buffer.kind.value]
    ):
        raise Error("The " + name + " buffer has the wrong number of channels")
    if buffer.srgb and (
        buffer.kind == BUFFER_ALBEDO or buffer.kind == BUFFER_SPECULAR_ALBEDO
    ):
        raise Error("The " + name + " buffer must be linear, not sRGB")


def _check_buffers(
    tags: List[TaggedBuffer], render: FrameSize, output: FrameSize
) raises:
    """Refuse a buffer that is wrong, or a kind that is tagged twice."""
    var seen = List[Bool](length=18, fill=False)
    for buffer in tags:
        _check_buffer(buffer, render, output)
        if seen[buffer.kind.value]:
            raise Error("The " + buffer.kind.name() + " buffer is tagged twice")
        seen[buffer.kind.value] = True


def _has(tags: List[TaggedBuffer], kind: BufferKind) -> Bool:
    """Return True if a frame tags a kind of buffer."""
    for buffer in tags:
        if buffer.kind == kind:
            return True
    return False


def _need(tags: List[TaggedBuffer], kind: BufferKind) raises:
    """Refuse a frame that does not tag a kind of buffer."""
    if not _has(tags, kind):
        raise Error("The " + kind.name() + " buffer is not tagged")


def check_super_resolution_tags(
    options: SuperResolutionOptions,
    render: FrameSize,
    tags: List[TaggedBuffer],
) raises:
    """Refuse a frame that Super Resolution could not run.

    Args:
        options: The options of the frame. `check_super_resolution` runs
            first.
        render: The size the scene is rendered at.
        tags: The buffers the frame tags.

    Raises:
        Error: If the options are refused, a buffer is of an invalid kind, of
            the wrong size or number of channels, or tagged twice, or the
            depth, the motion vectors, the input color or the output color is
            not tagged.
    """
    check_super_resolution(options)
    var output = FrameSize(options.output_width, options.output_height)
    _check_buffers(tags, render, output)
    _need(tags, BUFFER_DEPTH)
    _need(tags, BUFFER_MOTION_VECTORS)
    _need(tags, BUFFER_INPUT_COLOR)
    _need(tags, BUFFER_OUTPUT_COLOR)


def check_ray_reconstruction_tags(
    options: RayReconstructionOptions,
    render: FrameSize,
    tags: List[TaggedBuffer],
) raises:
    """Refuse a frame that Ray Reconstruction could not run.

    Args:
        options: The options of the frame. `check_ray_reconstruction` runs
            first.
        render: The size the scene is rendered at.
        tags: The buffers the frame tags.

    Raises:
        Error: If the options are refused, a buffer is of an invalid kind, of
            the wrong size or number of channels, or tagged twice, a buffer
            that the feature needs is not tagged, the normals and the
            roughness do not match the mode, or the frame tags neither the
            specular motion vectors nor the specular hit distance.
    """
    check_ray_reconstruction(options)
    var output = FrameSize(options.output_width, options.output_height)
    _check_buffers(tags, render, output)
    _need(tags, BUFFER_INPUT_COLOR)
    _need(tags, BUFFER_OUTPUT_COLOR)
    _need(tags, BUFFER_MOTION_VECTORS)
    _need(tags, BUFFER_ALBEDO)
    _need(tags, BUFFER_SPECULAR_ALBEDO)
    if not (_has(tags, BUFFER_DEPTH) or _has(tags, BUFFER_LINEAR_DEPTH)):
        raise Error("The depth or the linear depth buffer is not tagged")
    if options.normal_roughness_mode == ROUGHNESS_PACKED:
        _need(tags, BUFFER_NORMAL_ROUGHNESS)
    else:
        if _has(tags, BUFFER_NORMAL_ROUGHNESS):
            raise Error("The normal and roughness buffer needs the packed mode")
        _need(tags, BUFFER_NORMALS)
        _need(tags, BUFFER_ROUGHNESS)
    if not (
        _has(tags, BUFFER_SPECULAR_MOTION_VECTORS)
        or _has(tags, BUFFER_SPECULAR_HIT_DISTANCE)
    ):
        raise Error(
            "The specular motion vectors or the specular hit distance"
            " buffer is not tagged"
        )
