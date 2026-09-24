# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A texture written as a KTX 2.0 file: three.js's `KTX2Exporter`, with
ktx-parse's `write`, and the other half of `render.ktx2`.

`export_ktx2` writes a 2D texture and `export_ktx2_volume` a
`Data3DTexture`. The file has one level, the texture's full size, with
no supercompression. `render.ktx2.read` reads it back to the same
texels.

**The format.** A texture here is RGBA. `channels` writes the first
four, two or one of each texel, three.js's `RGBAFormat`, `RGFormat` or
`RedFormat`. A byte texture is written as bytes: `R8G8B8A8_SRGB` and
the like when it is `SRGB`, `UNORM` when it is `LINEAR`. A float
texture is written as floats, `SFLOAT`, or as halves when `half` is
on, as three.js writes a `HalfFloatType` texture. A half is made with
three.js's `DataUtils.toHalfFloat`.

**The data format descriptor.** One basic block, of the RGBSDA color
model, with the BT.709 primaries, the sRGB or the linear transfer
function, and one sample for each channel. The rows are written in the
order they are held, as three.js writes a data texture's array.

**The key and value data.** One key, `KTXwriter`, whose value is
`writer`. three.js writes `three.js` and its revision.

**Where this port differs.** A texture here has no `NoColorSpace`, so
the primaries are always BT.709, three.js's for `LinearSRGBColorSpace`.
"""

from geometries.curve_modifier import to_half_float
from render.ktx2 import (
    VK_R8_SRGB,
    VK_R8_UNORM,
    VK_R8G8_SRGB,
    VK_R8G8_UNORM,
    VK_R8G8B8A8_SRGB,
    VK_R8G8B8A8_UNORM,
    VK_R16_SFLOAT,
    VK_R16G16_SFLOAT,
    VK_R16G16B16A16_SFLOAT,
    VK_R32_SFLOAT,
    VK_R32G32_SFLOAT,
    VK_R32G32B32A32_SFLOAT,
    VkFormat,
    identifier,
)
from render.srgb import LINEAR, SRGB, ColorSpace
from render.texture import FLOAT_TYPE, UNSIGNED_BYTE_TYPE, TexelType, Texture
from render.volume_texture import Data3DTexture
from std.memory import bitcast

# The data format descriptor's values that three.js writes.
comptime _MODEL_RGBSDA = 1
comptime _PRIMARIES_BT709 = 1
comptime _TRANSFER_LINEAR = 1
comptime _TRANSFER_SRGB = 2
comptime _CHANNEL_ALPHA = 15
comptime _SAMPLE_LINEAR = 16
comptime _SAMPLE_SIGNED = 64
comptime _SAMPLE_FLOAT = 128
# Minus one and one as floats: a float sample's lower and upper values.
comptime _FLOAT_LOWER = 0xBF800000
comptime _FLOAT_UPPER = 0x3F800000


def _push(mut out: List[UInt8], value: Int, size: Int):
    """Append a little-endian number of `size` bytes."""
    for k in range(size):
        out.append(UInt8((value >> (8 * k)) & 255))


def _format(channels: Int, size: Int, srgb: Bool) raises -> VkFormat:
    """Return three.js's `VK_FORMAT_MAP` entry."""
    if size == 1:
        if channels == 4:
            return VK_R8G8B8A8_SRGB if srgb else VK_R8G8B8A8_UNORM
        if channels == 2:
            return VK_R8G8_SRGB if srgb else VK_R8G8_UNORM
        return VK_R8_SRGB if srgb else VK_R8_UNORM
    if size == 2:
        if channels == 4:
            return VK_R16G16B16A16_SFLOAT
        if channels == 2:
            return VK_R16G16_SFLOAT
        return VK_R16_SFLOAT
    if channels == 4:
        return VK_R32G32B32A32_SFLOAT
    if channels == 2:
        return VK_R32G32_SFLOAT
    return VK_R32_SFLOAT


def _write(
    width: Int,
    height: Int,
    depth: Int,
    texel_type: TexelType,
    color_space: ColorSpace,
    pixels: List[UInt8],
    data: List[Float32],
    channels: Int,
    half: Bool,
    writer: String,
) raises -> List[UInt8]:
    """Write the file of one level: three.js's `parse`, then ktx-parse's
    `write`."""
    if channels != 1 and channels != 2 and channels != 4:
        raise Error(
            "KTX2 export: a texel is written with 1, 2 or 4 channels, not "
            + String(channels)
        )
    if texel_type != UNSIGNED_BYTE_TYPE and texel_type != FLOAT_TYPE:
        raise Error("KTX2 export: a texel type must be bytes or floats")
    if color_space != SRGB and color_space != LINEAR:
        raise Error("KTX2 export: a color space must be SRGB or LINEAR")
    var floats = texel_type == FLOAT_TYPE
    if half and not floats:
        raise Error("KTX2 export: only a float texture is written as halves")
    if floats and color_space == SRGB:
        raise Error(
            "KTX2 export: a float texture must be LINEAR; the sRGB"
            " transfer is for bytes"
        )
    var size = 1 if not floats else (2 if half else 4)
    var srgb = color_space == SRGB
    var texels = width * height * max(depth, 1)
    # The level: the first `channels` of each texel.
    var level = List[UInt8](capacity=texels * channels * size)
    # A texture has one texel or more, and a texel one channel or more.
    # The loops always run.
    for t in range(texels):  # pragma: no branch
        for c in range(channels):  # pragma: no branch
            if not floats:
                level.append(pixels[t * 4 + c])
            elif half:
                _push(level, Int(to_half_float(Float64(data[t * 4 + c]))), 2)
            else:
                _push(level, Int(bitcast[DType.uint32](data[t * 4 + c])), 4)
    # The data format descriptor: a basic block and a sample a channel.
    var transfer = _TRANSFER_SRGB if srgb else _TRANSFER_LINEAR
    var descriptor = List[UInt8]()
    _push(descriptor, 28 + 16 * channels, 4)
    _push(descriptor, 0, 2)
    _push(descriptor, 0, 2)
    _push(descriptor, 2, 2)
    _push(descriptor, 24 + 16 * channels, 2)
    descriptor.append(_MODEL_RGBSDA)
    descriptor.append(_PRIMARIES_BT709)
    descriptor.append(UInt8(transfer))
    descriptor.append(0)
    _push(descriptor, 0, 4)
    descriptor.append(UInt8(size * channels))
    _push(descriptor, 0, 7)
    # One channel or more. The loop always runs.
    for i in range(channels):  # pragma: no branch
        var channel = _CHANNEL_ALPHA if i == 3 else i
        if channel == _CHANNEL_ALPHA and transfer != _TRANSFER_LINEAR:
            channel |= _SAMPLE_LINEAR
        if floats:
            channel |= _SAMPLE_FLOAT | _SAMPLE_SIGNED
        _push(descriptor, i * size * 8, 2)
        descriptor.append(UInt8(size * 8 - 1))
        descriptor.append(UInt8(channel))
        _push(descriptor, 0, 4)
        _push(descriptor, _FLOAT_LOWER if floats else 0, 4)
        _push(descriptor, _FLOAT_UPPER if floats else 255, 4)
    # The key and value data: `KTXwriter`, its value and a zero byte each.
    var key_values = List[UInt8]()
    var entry = "KTXwriter".byte_length() + 1 + writer.byte_length() + 1
    _push(key_values, entry, 4)
    key_values.extend("KTXwriter".as_bytes())
    key_values.append(0)
    key_values.extend(writer.as_bytes())
    key_values.append(0)
    _push(key_values, 0, (4 - entry % 4) % 4)
    # Where each part goes: the identifier, the header, one level entry.
    var descriptor_at = 12 + 68 + 24
    var key_values_at = descriptor_at + len(descriptor)
    var at = key_values_at + len(key_values)
    # A level starts at a multiple of its texel size and of four: the
    # least common multiple, as ktx-parse finds it.
    var block = size * channels
    # A texel is 1, 2, 4, 8 or 16 bytes, so the larger of it and four is a
    # multiple of the smaller, and is the least common multiple.
    var align = max(block, 4)
    var padding = (align - at % align) % align
    var out = identifier()
    _push(out, Int(_format(channels, size, srgb).value), 4)
    _push(out, size, 4)
    _push(out, width, 4)
    _push(out, height, 4)
    _push(out, depth, 4)
    _push(out, 0, 4)
    _push(out, 1, 4)
    _push(out, 1, 4)
    _push(out, 0, 4)
    _push(out, descriptor_at, 4)
    _push(out, len(descriptor), 4)
    _push(out, key_values_at, 4)
    _push(out, len(key_values), 4)
    _push(out, 0, 8)
    _push(out, 0, 8)
    _push(out, at + padding, 8)
    _push(out, len(level), 8)
    _push(out, len(level), 8)
    out.extend(descriptor^)
    out.extend(key_values^)
    _push(out, 0, padding)
    out.extend(level^)
    return out^


def export_ktx2(
    texture: Texture,
    channels: Int = 4,
    half: Bool = False,
    writer: String = "ThreeMojo",
) raises -> List[UInt8]:
    """Return a texture as a KTX 2.0 file, as three.js's `KTX2Exporter`
    writes a `DataTexture`.

    Args:
        texture: The texture. Its full size is written; its chain is not.
        channels: 4, 2 or 1: the first channels of each texel, three.js's
            `RGBAFormat`, `RGFormat` or `RedFormat`.
        half: Write a float texture as halves, three.js's
            `HalfFloatType`.
        writer: The value of the `KTXwriter` key.

    Returns:
        The file.

    Raises:
        Error: If the texture is blank, `channels` is not 1, 2 or 4, the
            texel type or the color space is none of its named values, a
            byte texture is asked for halves, or a float texture is
            `SRGB`.
    """
    if texture.width == 0:
        raise Error("KTX2 export: a blank texture has no texels to write")
    return _write(
        texture.width,
        texture.height,
        0,
        texture.texel_type,
        texture.color_space,
        texture.pixels,
        texture.data,
        channels,
        half,
        writer,
    )


def export_ktx2_volume(
    texture: Data3DTexture,
    channels: Int = 4,
    half: Bool = False,
    writer: String = "ThreeMojo",
) raises -> List[UInt8]:
    """Return a 3D texture as a KTX 2.0 file, as three.js's
    `KTX2Exporter` writes a `Data3DTexture`.

    Args:
        texture: The texture.
        channels: 4, 2 or 1: the first channels of each texel.
        half: Write a float texture as halves.
        writer: The value of the `KTXwriter` key.

    Returns:
        The file, with the texture's depth.

    Raises:
        Error: If `channels` is not 1, 2 or 4, the texel type or the
            color space is none of its named values, a byte texture is
            asked for halves, or a float texture is `SRGB`.
    """
    ref image = texture.image
    return _write(
        image.width,
        image.height,
        image.depth,
        image.texel_type,
        texture.color_space,
        image.pixels,
        image.data,
        channels,
        half,
        writer,
    )
