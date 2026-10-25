# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `window.capi_gamepad`, the C ABI that a host feeds gamepads.

The functions are the ones a host calls, called here from Mojo with the same
scalars and the same opaque handle.
"""

from std.memory import Layout
from std.testing import TestSuite, assert_equal, assert_false, assert_true
from window.capi_abi import ABI_VERSION, KEY_DOWN, MAX_SIDE
from window.capi_gamepad import (
    MAX_ID,
    create_app,
    RUMBLE_HIGH,
    RUMBLE_LOW,
    tm_abi_version,
    tm_alloc,
    tm_create,
    tm_destroy,
    tm_event,
    tm_frame,
    tm_free,
    tm_gamepad_axis,
    tm_gamepad_button,
    tm_gamepad_connect,
    tm_gamepad_count,
    tm_gamepad_disconnect,
    tm_gamepad_index,
    tm_gamepad_rumble,
    tm_gamepad_rumble_strength,
    tm_gamepad_sample,
    tm_gamepad_set_axis,
    tm_gamepad_set_button,
    tm_gamepad_take_rumble,
    tm_height,
    tm_init,
    tm_step,
    tm_width,
)

comptime Handle = OpaquePointer[MutUntrackedOrigin]
comptime Bytes = Pointer[UInt8, MutUntrackedOrigin]
comptime WIDTH = 104
comptime HEIGHT = 60


def _make() raises -> Handle:
    var created = tm_create(Int32(WIDTH), Int32(HEIGHT))
    assert_true(Bool(created))
    return Handle(unsafe_from_address=Int(created.value()))


def _connect(app: Handle, index: Int, id: String, rumble: Int) -> Int32:
    """Connect a pad with the standard layout, its id in `tm_alloc` room."""
    var bytes = id.as_bytes()
    var room = tm_alloc(Int32(max(len(bytes), 1)))
    var pointer = room.value()
    for at in range(len(bytes)):
        pointer.unsafe_offset(at).unsafe_write(bytes[at])
    var added = tm_gamepad_connect(
        app,
        Int32(index),
        pointer,
        Int32(len(bytes)),
        Int32(4),
        Int32(17),
        Int32(rumble),
    )
    tm_free(pointer)
    return added


def _pixel(app: Handle, x: Int, y: Int) -> Int:
    """Return the red channel of one pixel of a fresh frame."""
    var frame = tm_frame(app)
    return Int(frame.unsafe_offset((y * WIDTH + x) * 4).unsafe_load())


def test_app() raises:
    assert_equal(Int(tm_abi_version()), ABI_VERSION)
    tm_init()
    assert_false(Bool(tm_create(Int32(0), Int32(10))))
    assert_false(Bool(tm_create(Int32(10), Int32(MAX_SIDE + 1))))
    assert_false(Bool(tm_create(Int32(10), Int32(0))))
    assert_false(Bool(tm_create(Int32(MAX_SIDE + 1), Int32(10))))
    # A default mapping that is not well formed makes no app.
    assert_false(Bool(create_app(10, 10, "not a mapping")))
    var app = _make()
    assert_equal(Int(tm_width(app)), WIDTH)
    assert_equal(Int(tm_height(app)), HEIGHT)
    # Keys and pointers do nothing; negative time is ignored.
    tm_event(app, Int32(KEY_DOWN), Int32(0), Int32(0), Int32(32))
    tm_step(app, Int32(-5))
    tm_step(app, Int32(1000))
    # Staging for a pad that is not connected does nothing.
    tm_gamepad_set_axis(app, Int32(0), Int32(0), 1.0)
    # With no pad the frame is the background.
    assert_equal(_pixel(app, 0, 0), 24)
    assert_equal(Int(tm_gamepad_count(app)), 0)
    tm_destroy(app)


def test_tiny_frame() raises:
    # A frame smaller than the drawing clips it.
    var created = tm_create(Int32(1), Int32(1))
    var app = Handle(unsafe_from_address=Int(created.value()))
    assert_equal(Int(_connect(app, 0, "Pad", 0)), 1)
    tm_gamepad_set_axis(app, Int32(0), Int32(0), -1.0)
    _ = tm_gamepad_sample(app, Int32(0), 0.0)
    _ = tm_frame(app)
    tm_destroy(app)


def test_alloc() raises:
    assert_false(Bool(tm_alloc(Int32(0))))
    assert_false(Bool(tm_alloc(Int32(MAX_ID + 1))))
    var room = tm_alloc(Int32(8))
    assert_true(Bool(room))
    tm_free(room.value())


def test_pads() raises:
    var app = _make()
    assert_equal(Int(_connect(app, 2, "Xbox Wireless Controller", 1)), 1)
    assert_equal(Int(_connect(app, 2, "Xbox Wireless Controller", 1)), 0)
    assert_equal(Int(_connect(app, 5, "", 0)), 1)
    assert_equal(Int(tm_gamepad_count(app)), 2)
    assert_equal(Int(tm_gamepad_index(app, Int32(0))), 2)
    assert_equal(Int(tm_gamepad_index(app, Int32(1))), 5)
    assert_equal(Int(tm_gamepad_index(app, Int32(2))), -1)
    assert_equal(Int(tm_gamepad_index(app, Int32(-1))), -1)
    # An id longer than the limit is refused.
    var empty = tm_alloc(Int32(1)).value()
    assert_equal(
        Int(
            tm_gamepad_connect(
                app,
                Int32(9),
                empty,
                Int32(MAX_ID + 1),
                Int32(4),
                Int32(17),
                Int32(0),
            )
        ),
        0,
    )
    assert_equal(
        Int(
            tm_gamepad_connect(
                app, Int32(9), empty, Int32(-1), Int32(4), Int32(17), Int32(0)
            )
        ),
        0,
    )
    tm_free(empty)
    # Stage a state: the south button, the left trigger and the left stick.
    tm_gamepad_set_button(app, Int32(2), Int32(0), Int32(1), 1.0)
    tm_gamepad_set_button(app, Int32(2), Int32(6), Int32(1), 0.5)
    tm_gamepad_set_axis(app, Int32(2), Int32(0), 1.0)
    tm_gamepad_set_axis(app, Int32(2), Int32(1), -1.0)
    # Out of range: ignored.
    tm_gamepad_set_button(app, Int32(2), Int32(17), Int32(1), 1.0)
    tm_gamepad_set_button(app, Int32(2), Int32(-1), Int32(1), 1.0)
    tm_gamepad_set_button(app, Int32(8), Int32(0), Int32(1), 1.0)
    tm_gamepad_set_axis(app, Int32(2), Int32(4), 1.0)
    tm_gamepad_set_axis(app, Int32(2), Int32(-1), 1.0)
    tm_gamepad_set_axis(app, Int32(8), Int32(0), 1.0)
    # Nothing changes before the sample.
    assert_equal(Int(tm_gamepad_button(app, Int32(2), Int32(0))), 0)
    assert_true(tm_gamepad_sample(app, Int32(2), 0.0) > 0)
    assert_equal(Int(tm_gamepad_sample(app, Int32(8), 0.0)), -1)
    assert_equal(Int(tm_gamepad_button(app, Int32(2), Int32(0))), 1)
    assert_equal(Int(tm_gamepad_axis(app, Int32(2), Int32(0))), 32767)
    assert_equal(Int(tm_gamepad_axis(app, Int32(2), Int32(1))), -32767)
    assert_equal(Int(tm_gamepad_axis(app, Int32(2), Int32(4))), 32767)
    assert_equal(Int(tm_gamepad_axis(app, Int32(2), Int32(6))), 0)
    assert_equal(Int(tm_gamepad_axis(app, Int32(2), Int32(-1))), 0)
    assert_equal(Int(tm_gamepad_axis(app, Int32(8), Int32(0))), 0)
    assert_equal(Int(tm_gamepad_button(app, Int32(2), Int32(26))), 0)
    assert_equal(Int(tm_gamepad_button(app, Int32(2), Int32(-1))), 0)
    assert_equal(Int(tm_gamepad_button(app, Int32(8), Int32(0))), 0)
    # The frame shows the first pad: its south button is lit.
    var cell = WIDTH // 26
    assert_equal(_pixel(app, 0, HEIGHT - cell - 1), 230)
    assert_equal(_pixel(app, cell, HEIGHT - cell - 1), 70)
    assert_equal(Int(tm_gamepad_disconnect(app, Int32(2))), 1)
    assert_equal(Int(tm_gamepad_disconnect(app, Int32(2))), 0)
    assert_equal(Int(tm_gamepad_count(app)), 1)
    tm_destroy(app)


def test_rumble() raises:
    var app = _make()
    assert_equal(Int(_connect(app, 0, "Pad", 1)), 1)
    assert_equal(Int(_connect(app, 1, "Silent Pad", 0)), 1)
    assert_equal(
        Int(tm_gamepad_rumble(app, Int32(1), Int32(5), Int32(6), Int32(100))),
        0,
    )
    assert_equal(
        Int(tm_gamepad_rumble(app, Int32(4), Int32(5), Int32(6), Int32(100))),
        0,
    )
    assert_equal(
        Int(
            tm_gamepad_rumble(app, Int32(0), Int32(70000), Int32(6), Int32(100))
        ),
        0,
    )
    assert_equal(Int(tm_gamepad_take_rumble(app, Int32(0))), 0)
    assert_equal(Int(tm_gamepad_take_rumble(app, Int32(4))), 0)
    assert_equal(
        Int(
            tm_gamepad_rumble(
                app, Int32(0), Int32(65535), Int32(32768), Int32(500)
            )
        ),
        1,
    )
    assert_equal(Int(tm_gamepad_take_rumble(app, Int32(0))), 1)
    assert_equal(Int(tm_gamepad_rumble_strength(app, Int32(RUMBLE_LOW))), 65535)
    assert_equal(
        Int(tm_gamepad_rumble_strength(app, Int32(RUMBLE_HIGH))), 32768
    )
    assert_equal(Int(tm_gamepad_rumble_strength(app, Int32(2))), 0)
    assert_equal(Int(tm_gamepad_take_rumble(app, Int32(0))), 0)
    # The step runs the timers: after 500 ms the rumble stops.
    tm_step(app, Int32(600000))
    assert_equal(Int(tm_gamepad_take_rumble(app, Int32(0))), 1)
    assert_equal(Int(tm_gamepad_rumble_strength(app, Int32(RUMBLE_LOW))), 0)
    tm_destroy(app)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
