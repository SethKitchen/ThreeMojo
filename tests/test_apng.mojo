# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.apng`.

The APNG rules that are easy to get wrong and impossible to see by eye are the
ones checked hardest here: acTL has to precede the first IDAT, and fcTL and
fdAT share a single sequence counter that must run 0, 1, 2, ... with no gaps.
A viewer given a file that breaks either one simply shows a still image.
"""

from render.apng import encode
from render.framebuffer import Color, Framebuffer
from std.testing import TestSuite, assert_equal, assert_raises, assert_true

comptime SIGNATURE_LENGTH = 8


def be32(bytes: List[UInt8], at: Int) -> Int:
    """Return the big-endian 32-bit integer starting at `at`."""
    return (
        Int(bytes[at]) << 24
        | Int(bytes[at + 1]) << 16
        | Int(bytes[at + 2]) << 8
        | Int(bytes[at + 3])
    )


def be16(bytes: List[UInt8], at: Int) -> Int:
    """Return the big-endian 16-bit integer starting at `at`."""
    return Int(bytes[at]) << 8 | Int(bytes[at + 1])


def chunk_kind(bytes: List[UInt8], at: Int) raises -> String:
    """Return the four-character chunk type starting at `at`."""
    var kind = String("")
    for offset in range(4):
        kind += chr(Int(bytes[at + offset]))
    return kind^


def chunk_kinds(png: List[UInt8]) raises -> List[String]:
    """Return every chunk type in the file, in order."""
    var kinds = List[String]()
    var position = SIGNATURE_LENGTH
    while position < len(png):
        kinds.append(chunk_kind(png, position + 4))
        position += 12 + be32(png, position)
    return kinds^


def data_offset_of(png: List[UInt8], wanted: String) raises -> Int:
    """Return the offset of `wanted`'s payload, or -1 if it is absent."""
    var position = SIGNATURE_LENGTH
    while position < len(png):
        if chunk_kind(png, position + 4) == wanted:
            return position + 8
        position += 12 + be32(png, position)
    return -1


def sequence_numbers(png: List[UInt8]) raises -> List[Int]:
    """Return the sequence numbers of every fcTL and fdAT, in file order."""
    var numbers = List[Int]()
    var position = SIGNATURE_LENGTH
    while position < len(png):
        var kind = chunk_kind(png, position + 4)
        if kind == "fcTL" or kind == "fdAT":
            numbers.append(be32(png, position + 8))
        position += 12 + be32(png, position)
    return numbers^


def frames_of(
    count: Int, width: Int = 2, height: Int = 2
) raises -> List[Framebuffer]:
    """Return `count` distinct frames of the given size.

    Args:
        count: How many frames to build.
        width: Frame width.
        height: Frame height.

    Returns:
        Frames whose top-left pixel differs so they can be told apart.

    Raises:
        Error: If a frame size is invalid.
    """
    var frames = List[Framebuffer]()
    for index in range(count):
        var frame = Framebuffer(width, height, Color(0, 0, 0))
        frame.set_pixel(0, 0, Color(UInt8(index + 1), 0, 0, 128))
        frames.append(frame^)
    return frames^


def test_single_frame_animation_is_shaped_like_a_still_png() raises:
    var kinds = chunk_kinds(encode(frames_of(1)))
    assert_equal(len(kinds), 5)
    assert_equal(kinds[0], String("IHDR"))
    assert_equal(kinds[1], String("acTL"))
    assert_equal(kinds[2], String("fcTL"))
    assert_equal(kinds[3], String("IDAT"))
    assert_equal(kinds[4], String("IEND"))


def test_first_frame_travels_in_idat_not_fdat() raises:
    # This is what lets a decoder that ignores APNG still show frame one.
    var kinds = chunk_kinds(encode(frames_of(3)))
    var idat_at = -1
    var first_fdat_at = -1
    for index in range(len(kinds)):
        if kinds[index] == "IDAT" and idat_at < 0:
            idat_at = index
        if kinds[index] == "fdAT" and first_fdat_at < 0:
            first_fdat_at = index
    assert_true(idat_at >= 0)
    assert_true(idat_at < first_fdat_at)


def test_actl_precedes_the_first_idat() raises:
    var kinds = chunk_kinds(encode(frames_of(2)))
    var actl_at = -1
    var idat_at = -1
    for index in range(len(kinds)):
        if kinds[index] == "acTL":
            actl_at = index
        if kinds[index] == "IDAT" and idat_at < 0:
            idat_at = index
    assert_true(actl_at >= 0)
    assert_true(actl_at < idat_at)


def test_one_fdat_for_every_frame_after_the_first() raises:
    var kinds = chunk_kinds(encode(frames_of(4)))
    var fdats = 0
    var fctls = 0
    for index in range(len(kinds)):
        if kinds[index] == "fdAT":
            fdats += 1
        if kinds[index] == "fcTL":
            fctls += 1
    assert_equal(fctls, 4)
    assert_equal(fdats, 3)


def test_sequence_numbers_run_without_gaps() raises:
    var numbers = sequence_numbers(encode(frames_of(4)))
    # One fcTL for frame 0, then fcTL + fdAT for each of the other three.
    assert_equal(len(numbers), 7)
    for index in range(len(numbers)):
        assert_equal(numbers[index], index)


def test_actl_records_the_frame_count_and_loop_count() raises:
    var png = encode(frames_of(3), delay_ms=40, plays=7)
    var at = data_offset_of(png, String("acTL"))
    assert_equal(be32(png, at), 3)
    assert_equal(be32(png, at + 4), 7)


def test_animations_loop_forever_by_default() raises:
    var png = encode(frames_of(2))
    assert_equal(be32(png, data_offset_of(png, String("acTL")) + 4), 0)


def test_fctl_describes_a_full_size_frame_at_the_origin() raises:
    var png = encode(frames_of(2, width=5, height=3), delay_ms=250)
    var at = data_offset_of(png, String("fcTL"))
    assert_equal(be32(png, at + 4), 5)  # width
    assert_equal(be32(png, at + 8), 3)  # height
    assert_equal(be32(png, at + 12), 0)  # x offset
    assert_equal(be32(png, at + 16), 0)  # y offset
    assert_equal(be16(png, at + 20), 250)  # delay numerator
    assert_equal(be16(png, at + 22), 1000)  # delay denominator
    assert_equal(Int(png[at + 24]), 0)  # dispose NONE
    assert_equal(Int(png[at + 25]), 0)  # blend SOURCE


def test_ihdr_matches_the_frame_size() raises:
    var png = encode(frames_of(2, width=7, height=4))
    var at = data_offset_of(png, String("IHDR"))
    assert_equal(be32(png, at), 7)
    assert_equal(be32(png, at + 4), 4)


def test_empty_animation_is_rejected() raises:
    with assert_raises():
        _ = encode(List[Framebuffer]())


def test_mismatched_frame_width_is_rejected() raises:
    var frames = List[Framebuffer]()
    frames.append(Framebuffer(2, 2, Color(0, 0, 0)))
    frames.append(Framebuffer(3, 2, Color(0, 0, 0)))
    with assert_raises():
        _ = encode(frames)


def test_mismatched_frame_height_is_rejected() raises:
    # Both halves of the size check need their own case; a width-only test
    # leaves the height comparison never once true.
    var frames = List[Framebuffer]()
    frames.append(Framebuffer(2, 2, Color(0, 0, 0)))
    frames.append(Framebuffer(2, 5, Color(0, 0, 0)))
    with assert_raises():
        _ = encode(frames)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
