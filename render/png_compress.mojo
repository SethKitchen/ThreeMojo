# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""PNG encoding with compression: filtered rows that `render.deflate`
compresses.

`render.png.encode` writes DEFLATE's stored blocks, so its file is as
large as its pixels. `encode_compressed` writes the same pixels as a
file that any PNG reader reads, and that is far smaller. The exporters
write their textures with it.

**Filters.** A filter writes each byte of a row as its difference from a
guess: the byte of the pixel to the left, the byte above, their average,
or the Paeth guess of the two and the corner. A good guess leaves bytes
near zero, which DEFLATE packs well. Each row gets the filter whose bytes,
read as signed, have the smallest sum: the test that the PNG
specification suggests and that libpng uses.

**Levels.** The level is DEFLATE's, from 0 to 9. Level 0 stores the
filtered rows. Level 1 is the fastest that compresses and level 9 gives
the smallest file. `TEXTURE_LEVEL` is 6, which is zlib's own default.

**Sizes.** A texture of 1024 by 1024 texels is 4.2 MB from
`render.png.encode`. At level 6 a photograph is about 2.3 MB and a
drawing is far less, for about half a second of work on one core.
"""

from render.deflate import zlib_deflate
from render.framebuffer import Framebuffer
from render.png import _paeth, push_chunk, push_ihdr, push_signature

# The level the exporters write a texture at: zlib's own default.
comptime TEXTURE_LEVEL = 6
# The row filters of PNG, in the order of their type bytes.
comptime FILTER_NONE = 0
comptime FILTER_SUB = 1
comptime FILTER_UP = 2
comptime FILTER_AVERAGE = 3
comptime FILTER_PAETH = 4


def _signed_size(byte: Int) -> Int:
    """Return how far a filtered byte is from zero, as a signed byte."""
    return byte if byte < 128 else 256 - byte


def filtered_scanlines(buffer: Framebuffer) -> List[UInt8]:
    """Return the buffer's rows, each behind the filter that suits it.

    Each row gets the filter whose bytes, read as signed, have the
    smallest sum. The first filter with that sum wins, so a row that no
    filter helps is written as it is.

    Args:
        buffer: The RGBA pixels.

    Returns:
        For each row, the filter's type byte and then the filtered row.
    """
    comptime step = Framebuffer.CHANNELS
    var stride = buffer.width * step
    var out = List[UInt8](capacity=buffer.height * (stride + 1))
    ref pixels = buffer.pixels
    # A Framebuffer always has positive dimensions, so each loop runs.
    for y in range(buffer.height):  # pragma: no branch
        var row = y * stride
        var none = 0
        var sub = 0
        var up = 0
        var average = 0
        var paeth = 0
        for x in range(stride):  # pragma: no branch
            var value = Int(pixels[row + x])
            var left = Int(pixels[row + x - step]) if x >= step else 0
            var above = Int(pixels[row + x - stride]) if y > 0 else 0
            var corner = 0
            if x >= step and y > 0:
                corner = Int(pixels[row + x - stride - step])
            none += _signed_size(value)
            sub += _signed_size((value - left) & 255)
            up += _signed_size((value - above) & 255)
            average += _signed_size((value - (left + above) // 2) & 255)
            paeth += _signed_size((value - _paeth(left, above, corner)) & 255)
        var filter = FILTER_NONE
        var least = none
        if sub < least:
            filter = FILTER_SUB
            least = sub
        if up < least:
            filter = FILTER_UP
            least = up
        if average < least:
            filter = FILTER_AVERAGE
            least = average
        if paeth < least:
            filter = FILTER_PAETH
        out.append(UInt8(filter))
        for x in range(stride):  # pragma: no branch
            var value = Int(pixels[row + x])
            var left = Int(pixels[row + x - step]) if x >= step else 0
            var above = Int(pixels[row + x - stride]) if y > 0 else 0
            if filter == FILTER_SUB:
                value -= left
            elif filter == FILTER_UP:
                value -= above
            elif filter == FILTER_AVERAGE:
                value -= (left + above) // 2
            elif filter == FILTER_PAETH:
                # There is a row above. On the first row Paeth's guess is
                # the pixel to the left, and the tie goes to that filter.
                var corner = 0
                if x >= step:
                    corner = Int(pixels[row + x - stride - step])
                value -= _paeth(left, above, corner)
            out.append(UInt8(value & 255))
    return out^


def compressed_frame_data(
    buffer: Framebuffer, level: Int = TEXTURE_LEVEL
) raises -> List[UInt8]:
    """Return one frame's pixels as a zlib stream of filtered rows.

    Args:
        buffer: The RGBA pixels.
        level: DEFLATE's level, from 0, which stores the rows, to 9, the
            smallest.

    Returns:
        The stream, which an `IDAT` chunk holds.

    Raises:
        Error: If the level is not from 0 to 9.
    """
    return zlib_deflate(Span(filtered_scanlines(buffer)), level)


def encode_compressed(
    buffer: Framebuffer, level: Int = TEXTURE_LEVEL
) raises -> List[UInt8]:
    """Return `buffer` encoded as a complete, compressed PNG file.

    Args:
        buffer: The RGBA pixels to encode.
        level: DEFLATE's level, from 0 to 9; see `compressed_frame_data`.

    Returns:
        The bytes of a valid PNG, alpha preserved. `render.png.decode`
        reads it back to the same pixels.

    Raises:
        Error: If the level is not from 0 to 9.
    """
    var out = List[UInt8]()
    push_signature(out)
    push_ihdr(out, buffer.width, buffer.height)
    push_chunk(out, String("IDAT"), compressed_frame_data(buffer, level))
    push_chunk(out, String("IEND"), List[UInt8]())
    return out^
