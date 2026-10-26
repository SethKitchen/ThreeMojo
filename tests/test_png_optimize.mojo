# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.png_optimize`.

The fixtures hold stored (level 0) zlib streams split over several data
chunks, so recompression must make them smaller. `semantics` decodes every
data run and keeps every other chunk, so a test can show that the decoded
samples and all controls survive while the bytes change.
"""

from render.deflate import zlib_deflate
from render.inflate import zlib_inflate
from render.png import push_be32
from render.png_optimize import (
    FCTL,
    FDAT,
    IDAT,
    IEND,
    IHDR,
    PngChunks,
    optimize,
    read_chunks,
    recompress,
    write_chunks,
)
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

# Chunk types the fixtures use that the module does not name.
comptime TEXT = UInt32(0x74455874)
comptime ACTL = UInt32(0x6163544C)


def _bytes(text: String) -> List[UInt8]:
    """Return the bytes of an ASCII string."""
    var out = List[UInt8]()
    out.extend(text.as_bytes())
    return out^


def _be32_bytes(values: List[Int]) -> List[UInt8]:
    """Return each value as four big-endian bytes."""
    var out = List[UInt8]()
    for value in values:
        push_be32(out, UInt32(value))
    return out^


def _slice(data: List[UInt8], start: Int, end: Int) -> List[UInt8]:
    """Return a copy of `data[start:end]`."""
    var out = List[UInt8]()
    out.extend(Span(data)[start:end])
    return out^


def _frame_control(
    sequence: Int, delay: Int, dispose: Int, blend: Int
) -> List[UInt8]:
    """Return a 26-byte fcTL body for a 64-by-1 frame."""
    var out = _be32_bytes([sequence, 64, 1, 0, 0])
    out.append(UInt8(delay >> 8))
    out.append(UInt8(delay & 0xFF))
    out.append(0)
    out.append(60)
    out.append(UInt8(dispose))
    out.append(UInt8(blend))
    return out^


def _stream() raises -> List[UInt8]:
    """Return a stored zlib stream of one filtered 64-pixel RGB row."""
    var raw = List[UInt8]()
    raw.append(0)
    for _ in range(64):
        raw.append(0x10)
        raw.append(0x20)
        raw.append(0x30)
    return zlib_deflate(Span(raw), 0)


def _fixture_chunks(animated: Bool) raises -> PngChunks:
    """Return the chunks of a still or an animated fixture."""
    var stream = _stream()
    var chunks = PngChunks()
    var header = _be32_bytes([64, 1])
    header.extend(Span([UInt8(8), 2, 0, 0, 0]))
    chunks.append(IHDR, header^)
    chunks.append(TEXT, _bytes("Attribution\x00Example credit"))
    if animated:
        chunks.append(ACTL, _be32_bytes([2, 3]))
        chunks.append(FCTL, _frame_control(0, 7, 1, 0))
    chunks.append(IDAT, _slice(stream, 0, 15))
    chunks.append(IDAT, _slice(stream, 15, len(stream)))
    if animated:
        chunks.append(FCTL, _frame_control(1, 9, 2, 1))
        var first = _be32_bytes([2])
        first.extend(Span(stream)[:14])
        chunks.append(FDAT, first^)
        var second = _be32_bytes([3])
        second.extend(Span(stream)[14:])
        chunks.append(FDAT, second^)
    chunks.append(IEND, List[UInt8]())
    return chunks^


def _fixture(animated: Bool = False) raises -> List[UInt8]:
    """Return a still or an animated fixture file."""
    return write_chunks(_fixture_chunks(animated))


def _with_chunk_before_end(
    chunk_type: UInt32, var body: List[UInt8]
) raises -> List[UInt8]:
    """Return the still fixture with one more chunk before `IEND`."""
    var chunks = _fixture_chunks(False)
    var fixed = PngChunks()
    for i in range(len(chunks) - 1):
        fixed.append(chunks.types[i], chunks.bodies[i].copy())
    fixed.append(chunk_type, body^)
    fixed.append(IEND, List[UInt8]())
    return write_chunks(fixed)


def _semantics(data: List[UInt8]) raises -> List[List[UInt8]]:
    """Return each decoded data run and every other chunk, in order.

    Each entry is the chunk type, then the decoded samples for a data run,
    or the body for another chunk. fcTL and fdAT sequence numbers are left
    out, because recompression can empty chunks but not renumber them.
    """
    var chunks = read_chunks(data)
    var result = List[List[UInt8]]()
    var pending = List[UInt8]()
    var previous = UInt32(0)
    for i in range(len(chunks)):
        var chunk_type = chunks.types[i]
        var is_data = chunk_type == IDAT or chunk_type == FDAT
        if (not is_data or chunk_type != previous) and len(pending) > 0:
            var entry = List[UInt8]()
            push_be32(entry, previous)
            entry.extend(Span(zlib_inflate(pending)))
            result.append(entry^)
            pending = List[UInt8]()
        if is_data:
            var skip = 4 if chunk_type == FDAT else 0
            pending.extend(Span(chunks.bodies[i])[skip:])
        else:
            var entry = List[UInt8]()
            push_be32(entry, chunk_type)
            var skip = 4 if chunk_type == FCTL else 0
            entry.extend(Span(chunks.bodies[i])[skip:])
            result.append(entry^)
        previous = chunk_type
    return result^


def _assert_same_lists(a: List[List[UInt8]], b: List[List[UInt8]]) raises:
    """Assert two lists of byte lists are equal."""
    assert_equal(len(a), len(b))
    for i in range(len(a)):
        assert_equal(a[i], b[i])


def test_still_and_animation_keep_all_samples_and_controls() raises:
    for animated in [False, True]:
        var before = _fixture(animated)
        var after = optimize(before)
        assert_true(len(after) < len(before))
        _assert_same_lists(_semantics(after), _semantics(before))
        # A second pass finds nothing smaller and returns the same bytes.
        assert_equal(optimize(after), after)


def test_sequence_numbers_and_chunk_positions_do_not_move() raises:
    var before = read_chunks(_fixture(True))
    var after = read_chunks(optimize(_fixture(True)))
    assert_equal(len(after), len(before))
    var expected = 0
    for i in range(len(after)):
        assert_equal(after.types[i], before.types[i])
        if after.types[i] == FCTL or after.types[i] == FDAT:
            var body = after.bodies[i].copy()
            var sequence = (
                Int(body[0]) << 24
                | Int(body[1]) << 16
                | Int(body[2]) << 8
                | Int(body[3])
            )
            assert_equal(sequence, expected)
            expected += 1
    assert_equal(expected, 4)


def test_the_first_chunk_of_a_run_holds_the_new_stream() raises:
    var after = read_chunks(optimize(_fixture(False)))
    # IHDR, tEXt, IDAT, IDAT, IEND: the second IDAT is now empty.
    assert_true(len(after.bodies[2]) > 0)
    assert_equal(len(after.bodies[3]), 0)


def test_a_file_that_does_not_shrink_is_returned_unchanged() raises:
    var chunks = PngChunks()
    chunks.append(IHDR, _be32_bytes([1, 1]))
    chunks.append(IEND, List[UInt8]())
    var data = write_chunks(chunks)
    assert_equal(optimize(data), data)


def test_rejects_corrupt_truncated_and_trailing_files() raises:
    var valid = _fixture()
    var corrupt = valid.copy()
    corrupt[29] ^= 1
    var trailing = valid.copy()
    trailing.append(120)
    var bad = List[List[UInt8]]()
    bad.append(_bytes("x"))
    bad.append(_slice(valid, 0, len(valid) - 1))
    bad.append(trailing^)
    bad.append(corrupt^)
    for data in bad:
        with assert_raises():
            _ = optimize(data)


def test_rejects_a_wrong_signature_and_a_chunk_past_the_end() raises:
    var wrong = _fixture()
    wrong[1] = 81
    with assert_raises(contains="not a PNG file"):
        _ = read_chunks(wrong)
    # A length that runs past the end of the file.
    var long = _fixture()
    long[8 + 2] = 200
    with assert_raises(contains="truncated PNG chunk data"):
        _ = read_chunks(long)


def test_rejects_end_data_and_a_missing_header_or_end() raises:
    var chunks = PngChunks()
    chunks.append(IHDR, _be32_bytes([1, 1]))
    chunks.append(IEND, _bytes("x"))
    with assert_raises(contains="invalid PNG end"):
        _ = read_chunks(write_chunks(chunks))
    # The signature alone has no chunks at all.
    var empty = write_chunks(PngChunks())
    with assert_raises(contains="missing PNG header"):
        _ = read_chunks(empty)
    var headless = PngChunks()
    headless.append(TEXT, _bytes("x"))
    headless.append(IEND, List[UInt8]())
    with assert_raises(contains="missing PNG header"):
        _ = read_chunks(write_chunks(headless))
    var endless = PngChunks()
    endless.append(IHDR, _be32_bytes([1, 1]))
    with assert_raises(contains="missing PNG header"):
        _ = read_chunks(write_chunks(endless))


def test_rejects_short_frame_data_and_controls() raises:
    with assert_raises(contains="short APNG frame data"):
        _ = optimize(_with_chunk_before_end(FDAT, _bytes("x")))
    with assert_raises(contains="invalid APNG frame control"):
        _ = optimize(_with_chunk_before_end(FCTL, _bytes("x")))


def test_frame_data_right_after_image_data_is_a_new_stream() raises:
    # fdAT that follows IDAT without an fcTL still starts its own stream.
    var stream = _stream()
    var body = _be32_bytes([0])
    body.extend(Span(stream))
    var data = _with_chunk_before_end(FDAT, body^)
    var after = optimize(data)
    assert_true(len(after) < len(data))
    _assert_same_lists(_semantics(after), _semantics(data))


def test_a_stream_past_its_image_is_refused() raises:
    # One gray pixel is two scanline bytes. Three bytes of output are past
    # that, and still far under the default image of a 64-pixel frame.
    var raw = List[UInt8]()
    raw.append(0)
    raw.append(1)
    raw.append(2)
    var stream = zlib_deflate(Span(raw), 0)
    var still = PngChunks()
    var gray = _be32_bytes([1, 1])
    gray.extend(Span([UInt8(8), 0, 0, 0, 0]))
    still.append(IHDR, gray^)
    still.append(IDAT, stream.copy())
    still.append(IEND, List[UInt8]())
    with assert_raises(contains="more than was expected"):
        _ = optimize(write_chunks(still))
    # A 1 by 1 RGB frame is four scanline bytes. The default image is a
    # 64-pixel row, so this only fails when the frame size is the limit.
    var wide = List[UInt8]()
    wide.append(0)
    for _ in range(4):
        wide.append(1)
    var wide_stream = zlib_deflate(Span(wide), 0)
    var frame = PngChunks()
    var header = _be32_bytes([64, 1])
    header.extend(Span([UInt8(8), 2, 0, 0, 0]))
    frame.append(IHDR, header^)
    var control = _be32_bytes([0, 1, 1, 0, 0])
    control.append(0)
    control.append(1)
    control.append(0)
    control.append(1)
    control.append(0)
    control.append(0)
    frame.append(FCTL, control^)
    var body = _be32_bytes([1])
    body.extend(Span(wide_stream))
    frame.append(FDAT, body^)
    frame.append(IEND, List[UInt8]())
    with assert_raises(contains="more than was expected"):
        _ = optimize(write_chunks(frame))


def test_an_image_whose_scanline_bytes_do_not_fit_is_refused() raises:
    var chunks = PngChunks()
    var header = _be32_bytes([4294967295, 4294967295])
    header.extend(Span([UInt8(16), 6, 0, 0, 0]))
    chunks.append(IHDR, header^)
    chunks.append(IDAT, _bytes("x"))
    chunks.append(IEND, List[UInt8]())
    with assert_raises(contains="larger than this decoder will build"):
        _ = optimize(write_chunks(chunks))
    var short = PngChunks()
    short.append(IHDR, _be32_bytes([1, 1]))
    short.append(IDAT, _bytes("x"))
    short.append(IEND, List[UInt8]())
    with assert_raises(contains="wrong size"):
        _ = optimize(write_chunks(short))


def test_rejects_bad_zlib_and_extra_streams() raises:
    var single = zlib_deflate(Span(_bytes("a")), 9)
    var short = _slice(single, 0, len(single) - 1)
    var double = single.copy()
    double.extend(Span(zlib_deflate(Span(_bytes("b")), 9)))
    var bad = List[List[UInt8]]()
    bad.append(_bytes("bad"))
    bad.append(short^)
    bad.append(double^)
    for stream in bad:
        with assert_raises():
            _ = recompress(stream)


def test_rejects_bytes_after_the_checksum() raises:
    var stream = zlib_deflate(Span(_bytes("a")), 9)
    stream.append(0)
    with assert_raises(contains="trailing bytes"):
        _ = recompress(stream)


def test_a_stream_that_does_not_shrink_keeps_its_bytes() raises:
    var stream = zlib_deflate(Span(_bytes("a")), 9)
    assert_equal(recompress(stream), stream)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
