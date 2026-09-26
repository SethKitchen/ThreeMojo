# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A WebP decoder with no image library: libwebp 1.6.0's `WebPDecodeRGBA`.

The half of three.js's `TextureLoader` that a browser does for it, as
`render.png` and `render.jpeg` are for PNG and JPEG. glTF's
`EXT_texture_webp` names WebP images.

**The container.** A RIFF file of type `WEBP`. It holds a `VP8L` chunk,
a lossless image, or a `VP8 ` chunk, a lossy one. A `VP8X` chunk before
it says what else there is: an `ALPH` chunk holds a lossy image's alpha.
Other chunks, such as metadata, are skipped.

**Lossless images** are `render.webp_lossless`. **Lossy images** are
`render.webp_lossy`: the VP8 key frame, in YUV 4:2:0, which libwebp turns
into RGB with its fancy upsampling. **Alpha** is stored raw or as a
lossless image's green channel. A filter can code each value as its
difference from the value to the left, above, or a gradient guess.

**Bit for bit.** libwebp decodes with integer arithmetic only, and this
decoder does the same arithmetic. `tests/test_webp.mojo` compares each
pixel with what libwebp 1.6.0's `dwebp` writes.

**What is refused.** An animation, which libwebp's still-image decoder
refuses too. A file that is not RIFF: libwebp also reads a bare VP8 or
VP8L stream, but a WebP file always has its container. And anything that
libwebp refuses: a chunk that runs past the file, a canvas that is not
the image's size, a malformed stream, or alpha that does not decode.

WebP carries no color space here, so the samples are sRGB, as a browser
takes them.
"""

from render.png import DecodedImage
from render.srgb import SRGB
from render.webp_lossless import decode_lossless, decode_lossless_stream
from render.webp_lossy import decode_lossy


def is_webp(bytes: List[UInt8]) -> Bool:
    """Return True if bytes begin as a WebP file.

    Args:
        bytes: A file's bytes.

    Returns:
        Whether they begin `RIFF`, four bytes of size, and `WEBP`.
    """
    return (
        len(bytes) >= 12
        and _tag(bytes, 0) == "RIFF"
        and _tag(bytes, 8) == "WEBP"
    )


def _tag(bytes: List[UInt8], at: Int) -> String:
    """Return four bytes as text."""
    var out = String()
    for i in range(4):  # pragma: no branch
        out += chr(Int(bytes[at + i]))
    return out


def _le(bytes: List[UInt8], at: Int, count: Int) -> Int:
    """Return a little-endian number of `count` bytes."""
    var value = 0
    for i in range(count):  # pragma: no branch
        value |= Int(bytes[at + i]) << (8 * i)
    return value


def _slice(bytes: List[UInt8], start: Int, end: Int) -> List[UInt8]:
    """Return a copy of bytes `start` to `end`."""
    var out = List[UInt8](capacity=end - start)
    for i in range(start, end):
        out.append(bytes[i])
    return out^


def unfilter_alpha(
    mut alpha: List[UInt8], width: Int, height: Int, filter: Int
):
    """Undo an alpha filter in place: libwebp's `WebPUnfilters`.

    Horizontal adds the value to the left, vertical the one above, and
    gradient the left plus the one above less the one above left,
    clamped. The first row of each is horizontal, and the first value of
    a row after it takes the one above.

    Args:
        alpha: The values, row by row.
        width: The image's width.
        height: The image's height.
        filter: 0 for none, 1 horizontal, 2 vertical, 3 gradient.
    """
    if filter == 0:
        return
    for y in range(height):  # pragma: no branch
        var at = y * width
        if y == 0 or filter == 1:
            var prediction = UInt8(0) if y == 0 else alpha[at - width]
            for x in range(width):  # pragma: no branch
                alpha[at + x] = alpha[at + x] + prediction
                prediction = alpha[at + x]
        elif filter == 2:
            for x in range(width):  # pragma: no branch
                alpha[at + x] = alpha[at + x] + alpha[at + x - width]
        else:
            var top_left = Int(alpha[at - width])
            var left = top_left
            for x in range(width):  # pragma: no branch
                var top = Int(alpha[at + x - width])
                var guess = min(max(left + top - top_left, 0), 255)
                left = (Int(alpha[at + x]) + guess) & 0xFF
                top_left = top
                alpha[at + x] = UInt8(left)


def decode_alpha(
    chunk: List[UInt8], width: Int, height: Int
) raises -> List[UInt8]:
    """Decode an `ALPH` chunk: libwebp's `ALPHDecode`.

    Args:
        chunk: The chunk's payload.
        width: The image's width.
        height: The image's height.

    Returns:
        One alpha value a pixel, row by row.

    Raises:
        If the header names a method, a preprocessing or reserved bits
        that are not allowed, or the data is short or malformed.
    """
    if len(chunk) <= 1:
        raise Error("WebP: the alpha chunk is empty")
    var header = Int(chunk[0])
    var method = header & 3
    var filter = (header >> 2) & 3
    if method > 1 or (header >> 4) & 3 > 1 or header >> 6 != 0:
        raise Error("WebP: an alpha header that is not allowed")
    var alpha: List[UInt8]
    if method == 0:
        if len(chunk) - 1 < width * height:
            raise Error("WebP: the raw alpha is too short")
        alpha = _slice(chunk, 1, 1 + width * height)
    else:
        var argb = decode_lossless_stream(
            _slice(chunk, 1, len(chunk)), width, height
        )
        alpha = List[UInt8](capacity=len(argb))
        for pixel in argb:  # pragma: no branch
            alpha.append(UInt8((pixel >> 8) & 0xFF))
    unfilter_alpha(alpha, width, height, filter)
    return alpha^


def decode(bytes: List[UInt8]) raises -> DecodedImage:
    """Decode a WebP file to RGBA.

    Args:
        bytes: The file.

    Returns:
        The image, eight-bit RGBA from the top, as sRGB.

    Raises:
        If the file is not a still WebP image that libwebp decodes.
    """
    if not is_webp(bytes):
        raise Error("WebP: not a RIFF WEBP file")
    # libwebp's `ParseRIFF`, `ParseVP8X`, `ParseOptionalChunks` and
    # `ParseVP8Header`, with all of the file at hand.
    var riff = _le(bytes, 4, 4)
    if riff < 12 or riff > len(bytes) - 8:
        raise Error("WebP: the RIFF size does not fit the file")
    var at = 12
    var canvas_width = -1
    var canvas_height = -1
    var alpha = List[UInt8]()
    var has_alpha_chunk = False
    # The RIFF size is at least 12 and fits the file, so a chunk header
    # follows `WEBP`.
    if _tag(bytes, at) == "VP8X":
        if _le(bytes, at + 4, 4) != 10:
            raise Error("WebP: a VP8X chunk that is not ten bytes")
        if len(bytes) - at < 18:
            raise Error("WebP: the VP8X chunk runs past the file")
        if Int(bytes[at + 8]) & 0x02 != 0:
            raise Error("WebP: an animation is not decoded")
        canvas_width = _le(bytes, at + 12, 3) + 1
        canvas_height = _le(bytes, at + 15, 3) + 1
        at += 18
        # Chunks up to the image; the last alpha chunk counts.
        var total = 4 + 18
        while True:
            if len(bytes) - at < 8:
                raise Error("WebP: the file has no image chunk")
            var size = _le(bytes, at + 4, 4)
            var disk = (8 + size + 1) & ~1
            total += disk
            if total > riff:
                raise Error("WebP: a chunk runs past the RIFF size")
            var tag = _tag(bytes, at)
            if tag == "VP8 " or tag == "VP8L":
                break
            # Within the RIFF size, so within the file.
            if tag == "ALPH":
                alpha = _slice(bytes, at + 8, at + 8 + size)
                has_alpha_chunk = True
            at += disk
    var tag = _tag(bytes, at)
    if tag != "VP8 " and tag != "VP8L":
        raise Error("WebP: the image chunk is not VP8 or VP8L")
    var size = _le(bytes, at + 4, 4)
    # Within the RIFF size, which fits the file, is within the file.
    if size > riff - 12:
        raise Error("WebP: the image chunk runs past the file")
    var payload = _slice(bytes, at + 8, at + 8 + size)
    var width: Int
    var height: Int
    var rgba: List[UInt8]
    if tag == "VP8L":
        var image = decode_lossless(payload^)
        width = image.width
        height = image.height
        rgba = List[UInt8](capacity=width * height * 4)
        for pixel in image.pixels:  # pragma: no branch
            rgba.append(UInt8((pixel >> 16) & 0xFF))
            rgba.append(UInt8((pixel >> 8) & 0xFF))
            rgba.append(UInt8(pixel & 0xFF))
            rgba.append(UInt8(pixel >> 24))
    else:
        var image = decode_lossy(payload^)
        width = image.width
        height = image.height
        rgba = image.rgba.copy()
    if canvas_width >= 0 and (canvas_width != width or canvas_height != height):
        raise Error("WebP: the canvas is not the image's size")
    if tag == "VP8 " and has_alpha_chunk:
        var values = decode_alpha(alpha, width, height)
        for i in range(width * height):  # pragma: no branch
            rgba[i * 4 + 3] = values[i]
    return DecodedImage(width, height, rgba^, SRGB)
