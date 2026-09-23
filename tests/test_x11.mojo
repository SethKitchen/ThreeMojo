# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `window.x11`.

The event decoding is tested on hand-built `XEvent` bytes, which needs no
server. The window is tested on an Xvfb server each test starts on a
display of its own, so the suite needs Xvfb installed and nothing else:
no screen and no window manager.
"""

from controls.input import (
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    ARROW_UP,
    KEY_DOWN,
    Key,
    MIDDLE,
    NO_BUTTON,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    RESIZE,
    SECONDARY,
    WHEEL,
)
from render.framebuffer import Color, Framebuffer
from std.ffi import OwnedDLHandle, c_int, external_call
from std.subprocess import run
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Duration, MILLISECOND, SECOND
from std.os import setenv
from window.x11 import X11Window, event_of, is_true_color, key_of


def _put32(mut bytes: List[UInt8], offset: Int, value: Int):
    """Write a little-endian 32-bit integer."""
    for index in range(4):
        bytes[offset + index] = UInt8((value >> (8 * index)) & 255)


def _event(kind: Int, x: Int, y: Int, state: Int, detail: Int) -> List[UInt8]:
    """Return a key, button or motion `XEvent` as bytes."""
    var bytes = List[UInt8](length=192, fill=0)
    _put32(bytes, 0, kind)
    _put32(bytes, 64, x)
    _put32(bytes, 68, y)
    _put32(bytes, 80, state)
    _put32(bytes, 84, detail)
    return bytes^


def test_key_symbols_become_keys() raises:
    assert_true(key_of(0xFF51, False) == ARROW_LEFT)
    assert_true(key_of(0xFF53, False) == ARROW_RIGHT)
    assert_true(key_of(0xFF52, False) == ARROW_UP)
    assert_true(key_of(0xFF54, False) == ARROW_DOWN)
    assert_true(key_of(0xFF1B, False) == Key(27))
    assert_true(key_of(0xFF0D, False) == Key(13))
    assert_true(key_of(0xFF09, False) == Key(9))
    assert_true(key_of(0xFF08, False) == Key(8))
    assert_true(key_of(0x71, False) == Key(113))
    # Ctrl with a letter is its control code, as a terminal sends it.
    assert_true(key_of(0x63, True) == Key(3))
    assert_true(key_of(0x43, True) == Key(3))
    assert_true(key_of(0x31, True) == Key(0x31))
    assert_true(key_of(0x7B, True) == Key(0x7B))
    assert_true(key_of(0xFFE1, False) == Key(-1))
    assert_true(key_of(0x10, False) == Key(-1))


def test_x_events_become_input_events() raises:
    var press = event_of(_event(2, 0, 0, 1 | 4 | 8, 0), 0x71).value()
    assert_true(press.kind == KEY_DOWN)
    assert_true(press.shift and press.ctrl and press.alt)
    assert_false(Bool(event_of(_event(2, 0, 0, 0, 0), 0xFFE1)))
    var down = event_of(_event(4, 7, 9, 0, 1), 0).value()
    assert_true(down.kind == POINTER_DOWN)
    assert_true(down.button == PRIMARY)
    assert_equal(down.x, 7)
    assert_equal(down.y, 9)
    assert_true(event_of(_event(4, 0, 0, 0, 2), 0).value().button == MIDDLE)
    var up = event_of(_event(5, 0, 0, 0, 3), 0).value()
    assert_true(up.kind == POINTER_UP)
    assert_true(up.button == SECONDARY)
    assert_equal(event_of(_event(4, 0, 0, 0, 4), 0).value().wheel, -1)
    assert_equal(event_of(_event(4, 0, 0, 0, 5), 0).value().wheel, 1)
    assert_false(Bool(event_of(_event(5, 0, 0, 0, 4), 0)))
    assert_false(Bool(event_of(_event(4, 0, 0, 0, 8), 0)))
    assert_false(Bool(event_of(_event(4, 0, 0, 0, 0), 0)))
    var moves = [
        (1 << 8, PRIMARY),
        (1 << 9, MIDDLE),
        (1 << 10, SECONDARY),
        (0, NO_BUTTON),
    ]
    for index in range(len(moves)):
        var move = event_of(_event(6, 3, 4, moves[index][0], 0), 0).value()
        assert_true(move.kind == POINTER_MOVE)
        assert_true(move.button == moves[index][1])
    var resize = List[UInt8](length=192, fill=0)
    _put32(resize, 0, 22)
    _put32(resize, 56, 320)
    _put32(resize, 60, 200)
    var size = event_of(resize, 0).value()
    assert_true(size.kind == RESIZE)
    assert_equal(size.x, 320)
    assert_equal(size.y, 200)
    # A key release, and an expose, have no kind here.
    assert_false(Bool(event_of(_event(3, 0, 0, 0, 0), 0x71)))
    assert_false(Bool(event_of(_event(12, 0, 0, 0, 0), 0)))
    # A negative position survives the sign.
    assert_equal(event_of(_event(6, -2, 0, 0, 0), 0).value().x, -2)


struct Server(Movable):
    """An Xvfb server on a display of this process's own."""

    var display: String
    var pid: String

    def __init__(out self, depth: Int = 24) raises:
        """Start a server on a free display and wait for it to listen.

        Xvfb picks the display and writes its number once it listens, so a
        server left behind by another run cannot be mistaken for this one.

        Args:
            depth: The screen's color depth.

        Raises:
            Error: If Xvfb does not start.
        """
        var lines = run(
            "f=$(mktemp); Xvfb -displayfd 3 -screen 0 320x240x"
            + String(depth)
            + ' -nolisten tcp 3>"$f" >/dev/null 2>&1 & p=$!;'
            + ' for i in $(seq 50); do [ -s "$f" ] && break; sleep 0.1;'
            + ' done; echo $p; cat "$f"; rm -f "$f"'
        ).split("\n")
        if len(lines) < 2:
            raise Error("Xvfb did not start")
        self.pid = String(lines[0])
        self.display = ":" + String(lines[1].strip())

    def stop(deinit self) raises:
        """Stop the server. Called at the end of a test on purpose: Mojo
        ends a value at its last use, and a server ended while a window
        still talks to it makes Xlib exit the process.

        Raises:
            Error: If the shell cannot run.
        """
        _ = run("kill " + self.pid + "; sleep 0.2")


def _pixel(window: X11Window, x: Int, y: Int) raises -> Int:
    """Return a window pixel as `0xRRGGBB`, read back from the server.

    Args:
        window: The window.
        x: The column.
        y: The row.

    Returns:
        The color.

    Raises:
        Error: If the server returns no image.
    """
    var lib = OwnedDLHandle("libX11.so.6")
    var image = lib.call["XGetImage", Int](
        window._display,
        window._window,
        c_int(x),
        c_int(y),
        UInt32(1),
        UInt32(1),
        Int(-1),
        c_int(2),
    )
    if image == 0:
        raise Error("XGetImage returned nothing")
    var value = lib.call["XGetPixel", Int](image, c_int(0), c_int(0))
    _ = lib.call["XDestroyImage", c_int](image)
    return value & 0xFFFFFF


def _send(window: X11Window, bytes: List[UInt8]) raises:
    """Send the window a synthetic event.

    Args:
        window: The window.
        bytes: The event.

    Raises:
        Error: Never.
    """
    var lib = OwnedDLHandle("libX11.so.6")
    var event = bytes.copy()
    # The window at 32, as every event names it.
    for index in range(8):
        event[32 + index] = UInt8((window._window >> (8 * index)) & 255)
    _ = lib.call["XSendEvent", c_int](
        window._display,
        window._window,
        c_int(0),
        Int(0),
        Int(event.unsafe_ptr()),
    )
    # The address alone does not keep the bytes alive through the call.
    _ = event^
    _ = lib.call["XFlush", c_int](window._display)


def test_a_window_shows_a_frame() raises:
    var server = Server()
    var window = X11Window(8, 6, display=server.display)
    assert_true(window.is_open)
    var frame = Framebuffer(8, 6, Color(200, 40, 10))
    frame.set_pixel(3, 2, Color(0, 0, 255))
    window.present(frame)
    _ = window.poll(Duration(100.0, MILLISECOND))
    window.present(frame)
    assert_equal(_pixel(window, 0, 0), 0xC8280A)
    assert_equal(_pixel(window, 3, 2), 0x0000FF)
    with assert_raises(contains="does not fit"):
        window.present(Framebuffer(9, 6, Color(0, 0, 0)))
    with assert_raises(contains="does not fit"):
        window.present(Framebuffer(8, 7, Color(0, 0, 0)))
    window.close()
    assert_false(window.is_open)
    window.close()
    with assert_raises(contains="closed"):
        window.present(frame)
    with assert_raises(contains="closed"):
        _ = window.poll(Duration(0.0, SECOND))
    with assert_raises(contains="closed"):
        window.resize(4, 4)
    server^.stop()


def test_a_window_reads_keys_buttons_resizes_and_a_close() raises:
    var server = Server()
    var window = X11Window(40, 30, display=server.display)
    _ = window.poll(Duration(200.0, MILLISECOND))
    var lib = OwnedDLHandle("libX11.so.6")
    var code = lib.call["XKeysymToKeycode", Int](window._display, Int(0x71))
    _send(window, _event(2, 0, 0, 0, code))
    _send(window, _event(4, 5, 6, 0, 1))
    _send(window, _event(6, 7, 8, 1 << 8, 0))
    _send(window, _event(5, 7, 8, 0, 1))
    var events = window.poll(Duration(500.0, MILLISECOND))
    assert_equal(len(events), 4)
    assert_true(events[0].key == Key(113))
    assert_true(events[1].kind == POINTER_DOWN)
    assert_true(events[2].kind == POINTER_MOVE)
    assert_true(events[3].kind == POINTER_UP)
    # A resize by the server reaches the window as a RESIZE.
    _ = lib.call["XResizeWindow", c_int](
        window._display, window._window, UInt32(64), UInt32(48)
    )
    _ = lib.call["XFlush", c_int](window._display)
    var sized = window.poll(Duration(500.0, MILLISECOND))
    assert_true(len(sized) >= 1)
    assert_true(sized[len(sized) - 1].kind == RESIZE)
    assert_equal(sized[len(sized) - 1].x, 64)
    window.resize(64, 48)
    window.present(Framebuffer(64, 48, Color(1, 2, 3)))
    # The same size again says nothing.
    var same = List[UInt8](length=192, fill=0)
    _put32(same, 0, 22)
    _put32(same, 56, 64)
    _put32(same, 60, 48)
    _send(window, same)
    assert_equal(len(window.poll(Duration(300.0, MILLISECOND))), 0)
    # The window manager asks the window to close; another message does not.
    var message = List[UInt8](length=192, fill=0)
    _put32(message, 0, 33)
    _put32(message, 48, 32)
    _send(window, message)
    _ = window.poll(Duration(300.0, MILLISECOND))
    assert_false(window.close_requested)
    for index in range(8):
        message[56 + index] = UInt8((window._delete >> (8 * index)) & 255)
    _send(window, message)
    _ = window.poll(Duration(300.0, MILLISECOND))
    assert_true(window.close_requested)
    # Nothing waiting: the poll times out empty.
    assert_equal(len(window.poll(Duration(0.0, SECOND))), 0)
    with assert_raises(contains="negative"):
        _ = window.poll(Duration(-1.0, SECOND))
    with assert_raises(contains="must be positive"):
        window.resize(0, 4)
    with assert_raises(contains="must be positive"):
        window.resize(4, 0)
    window.close()
    server^.stop()


def test_a_window_is_refused_what_it_cannot_do() raises:
    with assert_raises(contains="must be positive"):
        _ = X11Window(0, 4)
    with assert_raises(contains="must be positive"):
        _ = X11Window(4, 0)
    with assert_raises(contains="Could not open"):
        _ = X11Window(4, 4, display=":999")
    var shallow = Server(depth=16)
    with assert_raises(contains="TrueColor"):
        _ = X11Window(4, 4, display=shallow.display)
    shallow^.stop()


def test_only_24_bit_red_high_visuals_are_true_color() raises:
    assert_true(is_true_color(24, 0xFF0000))
    assert_false(is_true_color(16, 0xFF0000))
    # A server that sends red in the low byte would swap every color.
    assert_false(is_true_color(24, 0x0000FF))


def test_a_window_with_no_display_named_uses_the_environment() raises:
    var server = Server()
    _ = setenv("DISPLAY", server.display)
    var window = X11Window(4, 4)
    assert_true(window.is_open)
    window.close()
    server^.stop()


def test_a_window_dropped_open_closes_itself() raises:
    var server = Server()
    var window = X11Window(4, 4, display=server.display)
    _ = window^
    var other = X11Window(4, 4, display=server.display)
    other.close()
    _ = other^
    server^.stop()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
