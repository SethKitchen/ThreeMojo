# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Animated PNG encoding, for viewing several frames at once.

APNG is an ordinary PNG with three extra chunks, so everything `render.png`
already does is reused unchanged — the same signature, IHDR, stored-DEFLATE
streams and CRCs:

    acTL   once, before the first IDAT: how many frames, how many loops
    fcTL   once per frame: size, offset, delay, disposal
    fdAT   the second and later frames' pixels

The first frame's pixels stay in the IDAT chunk, which is what makes the file
degrade gracefully: a decoder that has never heard of APNG ignores the unknown
chunks and shows frame one as a still image.

GIF would be the obvious alternative and is a worse fit: it carries only 1-bit
transparency, so a pixel is either fully opaque or fully invisible, and caps
each frame at a 256-color palette that rendered output would have to be
quantized into.

Every frame here is full-size at offset (0, 0) with dispose NONE and blend
SOURCE, so each frame simply replaces the last. Sub-rectangle frames are the
format's compression trick, and nothing here compresses.
"""

from render.framebuffer import Framebuffer
from render.png import frame_data, push_be32, push_chunk, push_ihdr
from render.png import push_signature

# Leave the canvas alone after the frame; the next frame overwrites it.
comptime DISPOSE_NONE = UInt8(0)
# Write the frame's pixels straight over the canvas, alpha included.
comptime BLEND_SOURCE = UInt8(0)
# Delays are a fraction; expressing them in milliseconds keeps the numerator
# an exact integer.
comptime DELAY_DENOMINATOR = UInt16(1000)
comptime LOOP_FOREVER = 0
# The largest delay the two bytes of an fcTL numerator can hold, and the
# largest loop count the four bytes of acTL can.
comptime MAX_DELAY_MS = 65535
comptime MAX_PLAYS = 0xFFFFFFFF


def push_be16(mut out: List[UInt8], value: UInt16):
    """Append `value` as two big-endian bytes."""
    out.append(UInt8((value >> 8) & 0xFF))
    out.append(UInt8(value & 0xFF))


def push_actl(mut out: List[UInt8], frames: Int, plays: Int) raises:
    """Append the animation-control chunk.

    Args:
        out: Destination byte list.
        frames: Number of frames in the animation.
        plays: How many times to loop; 0 repeats forever.

    Raises:
        Error: If the loop count is negative or does not fit the chunk's
            thirty-two bits. Wrapping it instead turned minus one into four
            billion plays.
    """
    if plays < 0 or plays > MAX_PLAYS:
        raise Error("An APNG loop count is 0 to 4294967295")
    var data = List[UInt8]()
    push_be32(data, UInt32(frames))
    push_be32(data, UInt32(plays))
    push_chunk(out, String("acTL"), data)


def push_fctl(
    mut out: List[UInt8],
    sequence: Int,
    width: Int,
    height: Int,
    delay_ms: Int,
) raises:
    """Append a frame-control chunk describing one full-size frame.

    Args:
        out: Destination byte list.
        sequence: This chunk's number in the shared fcTL/fdAT counter.
        width: Frame width, always the full canvas here.
        height: Frame height, always the full canvas here.
        delay_ms: How long to show the frame, in milliseconds.

    Raises:
        Error: If the delay does not fit the chunk's sixteen bits: below
            zero, or above 65535 milliseconds. Truncating it instead showed
            a seventy-second frame for four and a half.
    """
    if delay_ms < 0 or delay_ms > MAX_DELAY_MS:
        raise Error("An APNG frame delay is 0 to 65535 milliseconds")
    var data = List[UInt8]()
    push_be32(data, UInt32(sequence))
    push_be32(data, UInt32(width))
    push_be32(data, UInt32(height))
    push_be32(data, UInt32(0))  # x offset
    push_be32(data, UInt32(0))  # y offset
    push_be16(data, UInt16(delay_ms))
    push_be16(data, DELAY_DENOMINATOR)
    data.append(DISPOSE_NONE)
    data.append(BLEND_SOURCE)
    push_chunk(out, String("fcTL"), data)


def push_fdat(mut out: List[UInt8], sequence: Int, pixels: List[UInt8]) raises:
    """Append a frame-data chunk: a sequence number, then IDAT-shaped bytes.

    Args:
        out: Destination byte list.
        sequence: This chunk's number in the shared fcTL/fdAT counter.
        pixels: The frame's zlib stream.

    Raises:
        Error: Never; present to match push_chunk.
    """
    var data = List[UInt8]()
    data.reserve(4 + len(pixels))
    push_be32(data, UInt32(sequence))
    data.extend(Span(pixels))
    push_chunk(out, String("fdAT"), data)


def encode(
    frames: List[Framebuffer], delay_ms: Int = 100, plays: Int = LOOP_FOREVER
) raises -> List[UInt8]:
    """Return `frames` encoded as one animated PNG.

    Args:
        frames: At least one frame; all must share the first frame's size.
        delay_ms: How long each frame is shown, in milliseconds.
        plays: How many times to loop; 0 repeats forever.

    Returns:
        The bytes of a valid APNG, which is also a valid PNG of frame one.

    Raises:
        Error: If `frames` is empty, the frames disagree on size, the delay
            is outside 0 to 65535 milliseconds, or the loop count is
            outside what four bytes hold.
    """
    if len(frames) == 0:
        raise Error("An animation needs at least one frame")

    var width = frames[0].width
    var height = frames[0].height
    # An empty list was rejected above, so this cannot run zero times.
    for index in range(len(frames)):  # pragma: no branch
        if frames[index].width != width or frames[index].height != height:
            raise Error("Every frame must match the first frame's size")

    var out = List[UInt8]()
    push_signature(out)
    push_ihdr(out, width, height)
    push_actl(out, len(frames), plays)

    # fcTL and fdAT share one counter, so it advances on every chunk of either
    # kind. The first frame is an exception: it is described by an fcTL but
    # carried by IDAT, which takes no sequence number of its own.
    var sequence = 0
    push_fctl(out, sequence, width, height, delay_ms)
    sequence += 1
    push_chunk(out, String("IDAT"), frame_data(frames[0]))

    for index in range(1, len(frames)):
        push_fctl(out, sequence, width, height, delay_ms)
        sequence += 1
        push_fdat(out, sequence, frame_data(frames[index]))
        sequence += 1

    push_chunk(out, String("IEND"), List[UInt8]())
    return out^
