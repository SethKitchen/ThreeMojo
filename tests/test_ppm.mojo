# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.ppm`."""

from render.framebuffer import Color, Framebuffer
from render.ppm import encode, to_stdout
from std.testing import TestSuite, assert_equal, assert_true


def encoded(buffer: Framebuffer) raises -> String:
    """Return `buffer` encoded as PPM text.

    Args:
        buffer: The pixels to encode.

    Returns:
        The complete PPM document.

    Raises:
        Error: If encoding fails.
    """
    var out = String("")
    encode(buffer, out)
    return out^


def test_header_names_the_format_size_and_depth() raises:
    var lines = encoded(Framebuffer(2, 3, Color(0, 0, 0))).splitlines()
    assert_equal(String(lines[0]), String("P3"))
    assert_equal(String(lines[1]), String("2 3"))
    assert_equal(String(lines[2]), String("255"))


def test_body_holds_one_line_per_pixel() raises:
    var lines = encoded(Framebuffer(2, 3, Color(1, 2, 3))).splitlines()
    assert_equal(len(lines), 3 + 6)


def test_pixels_are_written_left_to_right_top_to_bottom() raises:
    var fb = Framebuffer(2, 2, Color(0, 0, 0))
    fb.set_pixel(0, 0, Color(10, 10, 10))
    fb.set_pixel(1, 0, Color(20, 20, 20))
    fb.set_pixel(0, 1, Color(30, 30, 30))
    fb.set_pixel(1, 1, Color(40, 40, 40))
    var lines = encoded(fb).splitlines()
    assert_equal(String(lines[3]), String("10 10 10"))
    assert_equal(String(lines[4]), String("20 20 20"))
    assert_equal(String(lines[5]), String("30 30 30"))
    assert_equal(String(lines[6]), String("40 40 40"))


def test_document_ends_with_a_newline() raises:
    var fb = Framebuffer(1, 1, Color(7, 8, 9))
    assert_equal(encoded(fb), String("P3\n1 1\n255\n7 8 9\n"))


def test_alpha_is_discarded() raises:
    # PPM has no alpha channel, so a translucent pixel writes its raw color.
    var fb = Framebuffer(1, 1, Color(7, 8, 9, 64))
    assert_equal(encoded(fb), String("P3\n1 1\n255\n7 8 9\n"))


def test_to_stdout_emits_the_same_document() raises:
    var fb = Framebuffer(2, 2, Color(5, 6, 7))
    assert_true(encoded(fb).startswith("P3\n2 2\n255\n"))
    to_stdout(fb)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
