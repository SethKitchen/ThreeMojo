# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `window.capi_core`, the C ABI's WebAssembly-capable core.

The functions are the ones a C host calls, called here from Mojo with the
same scalars and the same opaque handle. The frame hashes at the end are
the numbers that `examples/capi/web/check.mjs` expects of the WebAssembly
build, so one pair of hashes ties the native and the WebAssembly builds
together.
"""

from controls.input import (
    KEY_DOWN as INPUT_KEY_DOWN,
    POINTER_DOWN as INPUT_POINTER_DOWN,
    KEY_UP as INPUT_KEY_UP,
    POINTER_MOVE as INPUT_POINTER_MOVE,
    WHEEL as INPUT_WHEEL,
)
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from window.capi_abi import (
    ABI_VERSION,
    KEY_DOWN,
    KEY_UP,
    KEY_SPACE,
    MAX_SIDE,
    POINTER_DOWN,
    POINTER_MOVE,
    WHEEL,
)
from window.capi_core import (
    TICK_MICROSECONDS,
    tm_abi_version,
    tm_create,
    tm_destroy,
    tm_event,
    tm_frame,
    tm_height,
    tm_init,
    tm_step,
    tm_width,
)

comptime Handle = OpaquePointer[MutUntrackedOrigin]
comptime WIDTH = 96
comptime HEIGHT = 64
comptime KEY_A = 97
comptime UNKNOWN_KIND = 99
comptime FRAME_BYTES = WIDTH * HEIGHT * 4


def _make(width: Int, height: Int) raises -> Handle:
    """Make an app, which the test needs to succeed."""
    var created = tm_create(Int32(width), Int32(height))
    assert_true(Bool(created))
    return Handle(unsafe_from_address=Int(created.value()))


def _frame(app: Handle) -> List[UInt8]:
    """Draw the app, and copy the frame out."""
    var bytes = tm_frame(app)
    var copy = List[UInt8](capacity=FRAME_BYTES)
    for index in range(FRAME_BYTES):
        copy.append(bytes.unsafe_offset(index).unsafe_load())
    return copy^


def _at(frame: List[UInt8], x: Int, y: Int, channel: Int) -> Int:
    """Return one channel of one pixel."""
    return Int(frame[(y * WIDTH + x) * 4 + channel])


def _is_white(frame: List[UInt8], x: Int, y: Int) -> Bool:
    """Return whether a pixel is opaque white."""
    return (
        _at(frame, x, y, 0) == 255
        and _at(frame, x, y, 1) == 255
        and _at(frame, x, y, 2) == 255
        and _at(frame, x, y, 3) == 255
    )


def _hash(frame: List[UInt8]) -> UInt64:
    """Return the 64-bit FNV-1a hash of a frame."""
    var hash = UInt64(14695981039346656037)
    for byte in frame:
        hash = (hash ^ UInt64(byte)) * UInt64(1099511628211)
    return hash


def _step(app: Handle, ticks: Int):
    """Step an app by whole animation ticks."""
    for _ in range(ticks):
        tm_step(app, Int32(TICK_MICROSECONDS))


def test_the_abi_version_is_one() raises:
    assert_equal(tm_abi_version(), Int32(1))
    assert_equal(ABI_VERSION, 1)


def test_event_kinds_are_the_input_kinds() raises:
    assert_equal(KEY_DOWN, INPUT_KEY_DOWN.value)
    assert_equal(POINTER_DOWN, INPUT_POINTER_DOWN.value)
    assert_equal(POINTER_MOVE, INPUT_POINTER_MOVE.value)
    assert_equal(WHEEL, INPUT_WHEEL.value)
    assert_equal(KEY_UP, INPUT_KEY_UP.value)


def test_init_changes_nothing() raises:
    tm_init()
    tm_init()
    var app = _make(WIDTH, HEIGHT)
    assert_equal(tm_width(app), Int32(WIDTH))
    tm_destroy(app)


def test_a_size_out_of_range_makes_no_app() raises:
    assert_false(Bool(tm_create(Int32(0), Int32(10))))
    assert_false(Bool(tm_create(Int32(10), Int32(0))))
    assert_false(Bool(tm_create(Int32(-1), Int32(10))))
    assert_false(Bool(tm_create(Int32(10), Int32(-1))))
    assert_false(Bool(tm_create(Int32(MAX_SIDE + 1), Int32(10))))
    assert_false(Bool(tm_create(Int32(10), Int32(MAX_SIDE + 1))))


def test_the_edge_sizes_make_apps() raises:
    var thin = _make(1, 1)
    assert_equal(tm_width(thin), Int32(1))
    assert_equal(tm_height(thin), Int32(1))
    var wide = _make(MAX_SIDE, 1)
    assert_equal(tm_width(wide), Int32(MAX_SIDE))
    var tall = _make(1, MAX_SIDE)
    assert_equal(tm_height(tall), Int32(MAX_SIDE))
    tm_destroy(thin)
    tm_destroy(wide)
    tm_destroy(tall)


def test_the_first_frame_is_a_gradient_with_a_triangle() raises:
    var app = _make(WIDTH, HEIGHT)
    assert_equal(tm_width(app), Int32(WIDTH))
    assert_equal(tm_height(app), Int32(HEIGHT))
    var frame = _frame(app)
    # The top left is the gradient's first shade, and every pixel is opaque.
    assert_equal(_at(frame, 0, 0, 0), 12)
    assert_equal(_at(frame, 0, 0, 1), 12)
    assert_equal(_at(frame, 0, 0, 2), 24)
    assert_equal(_at(frame, 5, 5, 2), 27)
    for pixel in range(WIDTH * HEIGHT):
        assert_equal(frame[pixel * 4 + 3], 255)
    # Inside the triangle the three corner weights add to a whole: red,
    # green and blue come to 255, less the rounding of three divisions.
    var inside = _at(frame, 70, 40, 0) + _at(frame, 70, 40, 1)
    inside += _at(frame, 70, 40, 2)
    assert_true(inside >= 253 and inside <= 255)
    tm_destroy(app)


def test_the_triangle_slides_and_comes_back() raises:
    var app = _make(WIDTH, HEIGHT)
    var first = _frame(app)
    _step(app, 60)
    var half = _frame(app)
    assert_true(_hash(first) != _hash(half))
    # The wave is 120 ticks long.
    _step(app, 60)
    var whole = _frame(app)
    assert_equal(_hash(first), _hash(whole))
    tm_destroy(app)


def test_negative_time_is_ignored() raises:
    var app = _make(WIDTH, HEIGHT)
    var first = _frame(app)
    tm_step(app, Int32(-1))
    assert_equal(_hash(first), _hash(_frame(app)))
    tm_destroy(app)


def test_the_space_bar_pauses_and_resumes() raises:
    var app = _make(WIDTH, HEIGHT)
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    var paused = _frame(app)
    _step(app, 30)
    assert_equal(_hash(paused), _hash(_frame(app)))
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_SPACE))
    _step(app, 30)
    assert_true(_hash(paused) != _hash(_frame(app)))
    tm_destroy(app)


def test_other_events_do_not_pause() raises:
    var app = _make(WIDTH, HEIGHT)
    var first = _frame(app)
    # The space bar going up, another key going down and an unknown kind.
    tm_event(app, Int32(KEY_UP), Int32(0), Int32(0), Int32(KEY_SPACE))
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(KEY_A))
    tm_event(app, Int32(UNKNOWN_KIND), Int32(0), Int32(0), Int32(KEY_SPACE))
    _step(app, 60)
    assert_true(_hash(first) != _hash(_frame(app)))
    tm_destroy(app)


def test_the_pointer_moves_the_top_corner_and_is_marked() raises:
    var app = _make(WIDTH, HEIGHT)
    var before = _frame(app)
    tm_event(app, Int32(POINTER_MOVE), Int32(30), Int32(20), Int32(-1))
    var frame = _frame(app)
    assert_true(_hash(before) != _hash(frame))
    for y in range(18, 23):
        for x in range(28, 33):
            assert_true(_is_white(frame, x, y))
    assert_false(_is_white(frame, 27, 20))
    assert_false(_is_white(frame, 33, 20))
    tm_destroy(app)


def test_a_button_press_places_the_pointer_too() raises:
    var app = _make(WIDTH, HEIGHT)
    tm_event(app, Int32(POINTER_DOWN), Int32(60), Int32(10), Int32(0))
    assert_true(_is_white(_frame(app), 60, 10))
    tm_destroy(app)


def test_the_pointer_stays_inside_the_frame() raises:
    var app = _make(WIDTH, HEIGHT)
    tm_event(app, Int32(POINTER_MOVE), Int32(-5), Int32(200), Int32(-1))
    assert_true(_is_white(_frame(app), 0, HEIGHT - 1))
    tm_event(app, Int32(POINTER_MOVE), Int32(500), Int32(-9), Int32(-1))
    assert_true(_is_white(_frame(app), WIDTH - 1, 0))
    tm_destroy(app)


def test_a_marker_at_a_corner_is_cut_by_the_frame() raises:
    var app = _make(3, 3)
    tm_event(app, Int32(POINTER_MOVE), Int32(0), Int32(0), Int32(-1))
    var bytes = tm_frame(app)
    # The five by five square covers all nine pixels of a three by three
    # frame, and nothing is written outside it.
    for index in range(9):
        assert_equal(bytes.unsafe_offset(index * 4).unsafe_load(), UInt8(255))
    tm_destroy(app)


def test_a_triangle_wound_the_other_way_draws_nothing() raises:
    var app = _make(WIDTH, HEIGHT)
    # With the top corner below the base, the corners wind the other way.
    tm_event(app, Int32(POINTER_MOVE), Int32(48), Int32(60), Int32(-1))
    var frame = _frame(app)
    # Where the triangle was, there is now only the gradient.
    assert_equal(_at(frame, 70, 40, 0), 24)
    assert_equal(_at(frame, 70, 40, 1), 24)
    assert_equal(_at(frame, 70, 40, 2), 49)
    tm_destroy(app)


def test_a_frame_of_one_pixel_is_drawn() raises:
    var app = _make(1, 1)
    var bytes = tm_frame(app)
    assert_equal(bytes.unsafe_offset(3).unsafe_load(), UInt8(255))
    tm_destroy(app)


def test_the_frame_hashes_that_the_wasm_build_must_match() raises:
    var app = _make(WIDTH, HEIGHT)
    var first = _hash(_frame(app))
    _step(app, 60)
    var second = _hash(_frame(app))
    tm_event(app, Int32(POINTER_MOVE), Int32(30), Int32(20), Int32(-1))
    var third = _hash(_frame(app))
    assert_equal(first, UInt64(1275981141803364349))
    assert_equal(second, UInt64(658073559776311977))
    assert_equal(third, UInt64(17593184181753337403))
    tm_destroy(app)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
