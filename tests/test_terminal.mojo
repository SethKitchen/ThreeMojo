# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `window.terminal`.

The window runs against a pseudo-terminal that each test opens: the
window has the terminal side, and the test has the other side, where it
reads what the window drew and types what a user would. Nothing needs a
real terminal, so the suite runs anywhere the C library has
`posix_openpt`.
"""

from controls.input import (
    ARROW_UP,
    KEY_DOWN,
    POINTER_DOWN,
    POINTER_MOVE,
    PRIMARY,
    Key,
)
from render.framebuffer import Color, Framebuffer
from std.ffi import c_char, c_int, external_call
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Duration, MILLISECOND, SECOND
from window.terminal import TerminalWindow, encode_frame

comptime O_RDWR = 2


struct PseudoTerminal(Movable):
    """A pseudo-terminal pair: the window's side and the user's side."""

    var user: c_int
    var terminal: c_int

    def __init__(out self) raises:
        """Open a pair.

        Raises:
            Error: If the C library cannot.
        """
        self.user = external_call["posix_openpt", c_int](c_int(O_RDWR))
        if self.user < 0:
            raise Error("posix_openpt failed")
        _ = external_call["grantpt", c_int](self.user)
        _ = external_call["unlockpt", c_int](self.user)
        var name = external_call["ptsname", Pointer[c_char, MutAnyOrigin]](
            self.user
        )
        var path = String(unsafe_from_utf8_ptr=name)
        self.terminal = external_call["open", c_int](
            path.as_c_string_span().ptr(), c_int(O_RDWR)
        )
        if self.terminal < 0:
            raise Error("Could not open ", path)

    def type_text(self, text: String):
        """Send bytes as if typed.

        Args:
            text: The bytes.
        """
        _ = external_call["write", Int](
            Int(self.user),
            text.unsafe_ptr().unsafe_bitcast[NoneType](),
            text.byte_length(),
        )

    def screen(self) -> String:
        """Read everything the window has written so far.

        Returns:
            The bytes, as text.
        """
        var text = String()
        while True:
            var chunk = _read_ready(self.user)
            if chunk == "":
                return text^
            text += chunk

    def close_user(self):
        """Hang up the user's side."""
        _ = external_call["close", c_int](self.user)

    def close_terminal(self):
        """Close the window's side."""
        _ = external_call["close", c_int](self.terminal)


def _read_ready(fd: c_int) -> String:
    """Read what a descriptor has ready, waiting briefly for it.

    Args:
        fd: The descriptor.

    Returns:
        The bytes, as text. Empty if nothing arrived.
    """
    var request = List[Int32](length=2, fill=0)
    request[0] = Int32(fd)
    request[1] = 1
    var ready = external_call["poll", c_int](
        request.unsafe_ptr(), c_int(1), c_int(20)
    )
    if ready <= 0:
        return String()
    var buffer = List[UInt8](length=4096, fill=0)
    var count = external_call["read", Int](
        Int(fd), buffer.unsafe_ptr().unsafe_bitcast[NoneType](), 4096
    )
    buffer.resize(max(count, 0), 0)
    return String(unsafe_from_utf8=buffer)


def _echoes(pty: PseudoTerminal) -> Bool:
    """Return whether the terminal side echoes what is typed: the flag that
    raw mode clears.

    A line is typed, so that a terminal not in raw mode has it ready too,
    and it is read back out of the terminal side so that nothing later
    sees it.

    Args:
        pty: The pair.

    Returns:
        True if typed bytes come back.
    """
    pty.type_text("z\n")
    var echoed = pty.screen()
    _ = _read_ready(pty.terminal)
    return echoed.startswith("z")


def test_a_frame_is_half_blocks_two_pixels_to_a_cell() raises:
    var frame = Framebuffer(2, 3, Color(10, 20, 30))
    frame.set_pixel(1, 0, Color(255, 0, 0))
    var text = encode_frame(frame)
    var expected = String(
        "\x1b[1;1H",
        "\x1b[38;2;10;20;30m\x1b[48;2;10;20;30m▀",
        "\x1b[38;2;255;0;0m▀",
        "\x1b[2;1H",
        # The third row has no row below it: that half is black.
        "\x1b[38;2;10;20;30m\x1b[48;2;0;0;0m▀▀",
        "\x1b[0m",
    )
    assert_equal(text, expected)


def test_a_window_needs_a_size_and_a_terminal() raises:
    with assert_raises(contains="must be positive"):
        _ = TerminalWindow(0, 4)
    with assert_raises(contains="must be positive"):
        _ = TerminalWindow(4, 0)
    # Standard input in a test run is not a terminal, and a closed
    # descriptor is not one either.
    with assert_raises(contains="not a terminal"):
        _ = TerminalWindow(4, 4, input_fd=-1)


def test_opening_sets_raw_mode_and_closing_puts_it_back() raises:
    var pty = PseudoTerminal()
    assert_true(_echoes(pty))
    var window = TerminalWindow(
        4, 4, input_fd=Int(pty.terminal), output_fd=Int(pty.terminal)
    )
    assert_true(window.is_open)
    var opened = pty.screen()
    assert_true(opened.startswith("\x1b[?1049h"))
    assert_true("\x1b[?1006h" in opened)
    assert_false(_echoes(pty))
    window.close()
    assert_false(window.is_open)
    assert_true(pty.screen().endswith("\x1b[?1049l"))
    assert_true(_echoes(pty))
    # A second close does nothing.
    window.close()
    assert_equal(pty.screen(), "")
    pty.close_terminal()
    pty.close_user()


def test_a_window_that_cannot_draw_puts_the_terminal_back() raises:
    var pty = PseudoTerminal()
    with assert_raises(contains="Could not write"):
        _ = TerminalWindow(4, 4, input_fd=Int(pty.terminal), output_fd=-1)
    assert_true(_echoes(pty))
    pty.close_terminal()
    pty.close_user()


def test_present_draws_a_frame_of_the_window_size() raises:
    var pty = PseudoTerminal()
    var window = TerminalWindow(
        3, 2, input_fd=Int(pty.terminal), output_fd=Int(pty.terminal)
    )
    _ = pty.screen()
    var frame = Framebuffer(3, 2, Color(1, 2, 3))
    window.present(frame)
    assert_equal(pty.screen(), encode_frame(frame))
    with assert_raises(contains="does not fit"):
        window.present(Framebuffer(4, 2, Color(1, 2, 3)))
    with assert_raises(contains="does not fit"):
        window.present(Framebuffer(3, 4, Color(1, 2, 3)))
    window.close()
    with assert_raises(contains="closed"):
        window.present(frame)
    pty.close_terminal()
    pty.close_user()


def test_poll_reads_keys_and_the_mouse_in_pixels() raises:
    var pty = PseudoTerminal()
    var window = TerminalWindow(
        8, 8, input_fd=Int(pty.terminal), output_fd=Int(pty.terminal)
    )
    # Nothing typed: the poll times out with no events.
    assert_equal(len(window.poll(Duration(0.0, SECOND))), 0)
    pty.type_text("q\x1b[A\x1b[<0;3;2M\x1b[<32;4;")
    var events = window.poll(Duration(100.0, MILLISECOND))
    assert_equal(len(events), 3)
    assert_true(events[0].kind == KEY_DOWN)
    assert_true(events[0].key == Key(113))
    assert_true(events[1].key == ARROW_UP)
    assert_true(events[2].kind == POINTER_DOWN)
    assert_true(events[2].button == PRIMARY)
    # Column 3 and row 2, from one, are pixel 2 and pixel 2.
    assert_equal(events[2].x, 2)
    assert_equal(events[2].y, 2)
    # The rest of a drag arrives in the next read.
    pty.type_text("3M")
    events = window.poll(Duration(100.0, MILLISECOND))
    assert_equal(len(events), 1)
    assert_true(events[0].kind == POINTER_MOVE)
    assert_equal(events[0].x, 3)
    assert_equal(events[0].y, 4)
    # Bytes that make no event yet make no event.
    pty.type_text("\x1b[<0;")
    assert_equal(len(window.poll(Duration(100.0, MILLISECOND))), 0)
    with assert_raises(contains="negative"):
        _ = window.poll(Duration(-1.0, SECOND))
    window.close()
    with assert_raises(contains="closed"):
        _ = window.poll(Duration(0.0, SECOND))
    pty.close_terminal()
    pty.close_user()


def test_a_hung_up_terminal_cannot_be_read() raises:
    var pty = PseudoTerminal()
    var window = TerminalWindow(
        2, 2, input_fd=Int(pty.terminal), output_fd=Int(pty.terminal)
    )
    _ = pty.screen()
    pty.close_user()
    with assert_raises(contains="it closed"):
        _ = window.poll(Duration(100.0, MILLISECOND))
    # Closing now cannot write the way out, but it still puts the
    # settings back and marks the window closed.
    with assert_raises(contains="Could not write"):
        window.close()
    assert_false(window.is_open)
    pty.close_terminal()


def test_a_window_dropped_open_closes_itself() raises:
    var pty = PseudoTerminal()
    var window = TerminalWindow(
        2, 2, input_fd=Int(pty.terminal), output_fd=Int(pty.terminal)
    )
    _ = pty.screen()
    _ = window^
    assert_true(pty.screen().endswith("\x1b[?1049l"))
    assert_true(_echoes(pty))
    # A window dropped when it cannot write still puts the settings back.
    var mute = TerminalWindow(
        2, 2, input_fd=Int(pty.terminal), output_fd=Int(pty.terminal)
    )
    _ = pty.screen()
    mute.output_fd = -1
    _ = mute^
    assert_true(_echoes(pty))
    # A window closed and then dropped writes nothing more.
    var closed = TerminalWindow(
        2, 2, input_fd=Int(pty.terminal), output_fd=Int(pty.terminal)
    )
    closed.close()
    _ = pty.screen()
    _ = closed^
    assert_equal(pty.screen(), "")
    pty.close_terminal()
    pty.close_user()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
