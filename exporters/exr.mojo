# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""RGBA floats written as an OpenEXR file: three.js's `EXRExporter`, and
the other half of `render.exr`.

`export_exr` takes the texels of a `FloatType` data texture, and
`export_exr_half` takes those of a `HalfFloatType` one. Each has four
values a texel, red, green, blue and alpha, from the bottom row up, as a
three.js `DataTexture` holds them. `export_exr_image` takes a
`FloatImage`, whose rows go from the top down, so that `render.exr`
reads the file back to the same image.

The file is a scanline file with one part. The header has the
attributes three.js writes, in its order. The channels are `A`, `B`,
`G` and `R`, each of `HALF_SAMPLES` or `FLOAT_SAMPLES`. A half is made
with three.js's `DataUtils.toHalfFloat`, which cuts off the extra bits
and clamps to 65,504. The blocks are stored as they are
(`NO_COMPRESSION`), or compressed with zlib one line at a time
(`ZIPS_COMPRESSION`) or sixteen lines at a time (`ZIP_COMPRESSION`, the
default). zlib is fflate's, from `render.deflate`, so the bytes are
three.js's bytes.

**Where this port differs.** three.js writes two kinds of block that
its own `EXRLoader` reads wrong values from. This port writes them as
OpenEXR says:

- three.js compresses the last block of a `ZIP_COMPRESSION` file at
  the size of a full block of sixteen lines, with the bytes of the
  block before it after the real lines. This port compresses only the
  real lines.
- A reader takes a block that is not smaller than its raw lines as raw
  lines. three.js writes the zlib stream of such a block all the same,
  for example for a small image. This port writes the raw lines.

Every other block, and the header, are three.js's bytes. An image with
no texels, or data of the wrong length, is refused. three.js writes a
file with a data window of minus one.
"""

from geometries.curve_modifier import to_half_float
from render.deflate import zlib_deflate
from render.exr import (
    FLOAT_SAMPLES,
    HALF_SAMPLES,
    NO_COMPRESSION,
    ZIPS_COMPRESSION,
    ZIP_COMPRESSION,
    ExrCompression,
    ExrPixelType,
    half_to_float,
)
from render.float_image import FloatImage
from std.math import isnan
from std.memory import bitcast


def _push_u32(mut out: List[UInt8], value: Int):
    """Append four little-endian bytes."""
    # Four bytes. The loop always runs.
    for k in range(4):  # pragma: no branch
        out.append(UInt8((value >> (8 * k)) & 255))


def _push_string(mut out: List[UInt8], text: String):
    """Append a string and its zero byte."""
    # Each name has letters. The loop always runs.
    for b in text.as_bytes():  # pragma: no branch
        out.append(b)
    out.append(0)


def _attribute(mut out: List[UInt8], name: String, kind: String, size: Int):
    """Append an attribute's name, type and size."""
    _push_string(out, name)
    _push_string(out, kind)
    _push_u32(out, size)


def _check(
    width: Int,
    height: Int,
    count: Int,
    compression: ExrCompression,
    type: ExrPixelType,
) raises:
    """Refuse a size, a compression or a sample type that three.js does
    not write."""
    if width < 1 or height < 1:
        raise Error("EXR export: an image needs a width and a height")
    if count != width * height * 4:
        raise Error(
            "EXR export: the data must hold four values for each of the "
            + String(width * height)
            + " texels, not "
            + String(count)
            + " values"
        )
    if not (
        compression == NO_COMPRESSION
        or compression == ZIPS_COMPRESSION
        or compression == ZIP_COMPRESSION
    ):
        raise Error("EXR export: the compression must be none, ZIPS or ZIP")
    if not (type == HALF_SAMPLES or type == FLOAT_SAMPLES):
        raise Error("EXR export: the sample type must be HALF or FLOAT")


def _write(
    width: Int,
    height: Int,
    values: List[Float64],
    compression: ExrCompression,
    type: ExrPixelType,
) raises -> List[UInt8]:
    """Write the file from the values, four a texel from the bottom row
    up: three.js's `reorganizeDataBuffer`, `compressData` and
    `fillData`."""
    var size = 2 * type.value
    var lines = 16 if compression == ZIP_COMPRESSION else 1
    var blocks = (height + lines - 1) // lines
    # The lines from the top down, each with its A, B, G and R runs.
    var raw = List[UInt8](length=width * height * 4 * size, fill=0)
    # The height is one or more. The loop always runs.
    for y in range(height):  # pragma: no branch
        var line = (height - y - 1) * width * 4 * size
        # The width is one or more. The loop always runs.
        for x in range(width):  # pragma: no branch
            var i = (y * width + x) * 4
            # A, B, G and R, as three.js writes them.
            # Four channels. The loop always runs.
            for c in range(4):  # pragma: no branch
                var at = line + c * width * size + x * size
                var value = values[i + 3 - c]
                var bits: Int
                if type == HALF_SAMPLES:
                    # three.js's clamp gives the processor's NaN, whose
                    # sign is set on x86-64.
                    bits = 0xFE00 if isnan(value) else Int(to_half_float(value))
                elif isnan(value):
                    # JavaScript holds one NaN, with no payload.
                    bits = 0x7FC00000
                else:
                    bits = Int(bitcast[DType.uint32](Float32(value)))
                # Two or four bytes. The loop always runs.
                for k in range(size):  # pragma: no branch
                    raw[at + k] = UInt8((bits >> (8 * k)) & 255)
    var chunks = List[List[UInt8]]()
    var block_size = width * 4 * lines * size
    # There is one block or more. The loop always runs.
    for b in range(blocks):  # pragma: no branch
        var start = block_size * b
        var end = min(start + block_size, len(raw))
        if compression == NO_COMPRESSION:
            chunks.append(List[UInt8](raw[start:end]))
            continue
        # Even bytes, then odd bytes, then each byte less the one before.
        var n = end - start
        var tmp = List[UInt8](length=n, fill=0)
        var t1 = 0
        var t2 = (n + 1) // 2
        # A block has one line or more. The loop always runs.
        for s in range(n):  # pragma: no branch
            if s % 2 == 0:
                tmp[t1] = raw[start + s]
                t1 += 1
            else:
                tmp[t2] = raw[start + s]
                t2 += 1
        var p = Int(tmp[0])
        # A line has eight bytes or more. The loop always runs.
        for t in range(1, n):  # pragma: no branch
            var d = Int(tmp[t]) - p + 128 + 256
            p = Int(tmp[t])
            tmp[t] = UInt8(d & 255)
        var packed = zlib_deflate(tmp)
        # A block that zlib does not make smaller is read as raw lines.
        if len(packed) >= n:
            chunks.append(List[UInt8](raw[start:end]))
        else:
            chunks.append(packed^)
    var out = List[UInt8]()
    _push_u32(out, 20000630)
    _push_u32(out, 2)
    _attribute(out, "compression", "compression", 1)
    out.append(UInt8(compression.value))
    _attribute(out, "screenWindowCenter", "v2f", 8)
    _push_u32(out, 0)
    _push_u32(out, 0)
    _attribute(out, "screenWindowWidth", "float", 4)
    _push_u32(out, Int(bitcast[DType.uint32](Float32(1))))
    _attribute(out, "pixelAspectRatio", "float", 4)
    _push_u32(out, Int(bitcast[DType.uint32](Float32(1))))
    _attribute(out, "lineOrder", "lineOrder", 1)
    out.append(0)
    # Two windows. The loop always runs.
    for name in ["dataWindow", "displayWindow"]:  # pragma: no branch
        _attribute(out, name, "box2i", 16)
        _push_u32(out, 0)
        _push_u32(out, 0)
        _push_u32(out, width - 1)
        _push_u32(out, height - 1)
    _attribute(out, "channels", "chlist", 4 * 18 + 1)
    # Four channels. The loop always runs.
    for name in ["A", "B", "G", "R"]:  # pragma: no branch
        _push_string(out, name)
        _push_u32(out, type.value)
        _push_u32(out, 0)
        _push_u32(out, 1)
        _push_u32(out, 1)
    out.append(0)
    out.append(0)
    var offset = len(out) + blocks * 8
    # There is one block or more. The loop always runs.
    for chunk in chunks:  # pragma: no branch
        # Eight bytes. The loop always runs.
        for k in range(8):  # pragma: no branch
            out.append(UInt8((offset >> (8 * k)) & 255))
        offset += len(chunk) + 8
    # There is one block or more. The loop always runs.
    for b in range(blocks):  # pragma: no branch
        _push_u32(out, b * lines)
        _push_u32(out, len(chunks[b]))
        out.extend(chunks[b].copy())
    return out^


def export_exr(
    width: Int,
    height: Int,
    data: List[Float32],
    compression: ExrCompression = ZIP_COMPRESSION,
    type: ExrPixelType = HALF_SAMPLES,
) raises -> List[UInt8]:
    """Return an EXR file of RGBA floats, as three.js's `EXRExporter`
    writes a `FloatType` `DataTexture`.

    Args:
        width: The width in texels.
        height: The height in texels.
        data: Four values a texel, from the bottom row up.
        compression: `NO_COMPRESSION`, `ZIPS_COMPRESSION` or
            `ZIP_COMPRESSION`, three.js's default.
        type: `HALF_SAMPLES`, three.js's default, or `FLOAT_SAMPLES`.

    Returns:
        The file.

    Raises:
        Error: If the image has no texels, the data is not four values a
            texel, or the compression or the type is not one of these.
    """
    _check(width, height, len(data), compression, type)
    var values = List[Float64](capacity=len(data))
    # The data holds four values or more. The loop always runs.
    for v in data:  # pragma: no branch
        values.append(Float64(v))
    return _write(width, height, values, compression, type)


def export_exr_half(
    width: Int,
    height: Int,
    data: List[UInt16],
    compression: ExrCompression = ZIP_COMPRESSION,
    type: ExrPixelType = HALF_SAMPLES,
) raises -> List[UInt8]:
    """Return an EXR file of RGBA halves, as three.js's `EXRExporter`
    writes a `HalfFloatType` `DataTexture`.

    Each half is read as a number and written again, so a NaN loses
    its payload, as in three.js.

    Args:
        width: The width in texels.
        height: The height in texels.
        data: The bits of four halves a texel, from the bottom row up.
        compression: `NO_COMPRESSION`, `ZIPS_COMPRESSION` or
            `ZIP_COMPRESSION`, three.js's default.
        type: `HALF_SAMPLES`, three.js's default, or `FLOAT_SAMPLES`.

    Returns:
        The file.

    Raises:
        Error: If the image has no texels, the data is not four values a
            texel, or the compression or the type is not one of these.
    """
    _check(width, height, len(data), compression, type)
    var values = List[Float64](capacity=len(data))
    # The data holds four values or more. The loop always runs.
    for v in data:  # pragma: no branch
        values.append(Float64(half_to_float(v)))
    return _write(width, height, values, compression, type)


def export_exr_image(
    image: FloatImage,
    compression: ExrCompression = ZIP_COMPRESSION,
    type: ExrPixelType = HALF_SAMPLES,
) raises -> List[UInt8]:
    """Return an EXR file of an image, which `render.exr.decode` reads
    back with its top row at the top.

    Args:
        image: The image, from the top row down.
        compression: `NO_COMPRESSION`, `ZIPS_COMPRESSION` or
            `ZIP_COMPRESSION`, three.js's default.
        type: `HALF_SAMPLES`, three.js's default, or `FLOAT_SAMPLES`.

    Returns:
        The file.

    Raises:
        Error: If the image has no texels, its pixels are not four values
            a texel, or the compression or the type is not one of these.
    """
    _check(
        image.width,
        image.height,
        len(image.pixels),
        compression,
        type,
    )
    var row = image.width * 4
    var data = List[Float32](capacity=len(image.pixels))
    var y = image.height - 1
    while y >= 0:
        # A row has four values or more. The loop always runs.
        for i in range(row):  # pragma: no branch
            data.append(image.pixels[y * row + i])
        y -= 1
    return export_exr(image.width, image.height, data, compression, type)
