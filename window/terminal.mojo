# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A window in the terminal: it shows frames and reads keys and the mouse.

three.js draws into a canvas that the browser shows, and the browser
reports the input. Mojo's standard library has no window system, but a
terminal is a window it can already reach: the C library's terminal calls
are in every process, and `std.ffi.external_call` calls them. So this
window is the terminal the program runs in, with no dependency.

A terminal cell is taller than it is wide, about twice. Each cell shows
two pixels, one above the other: the upper half block `▀` in the top
pixel's color, on the bottom pixel's color. A frame `width` pixels wide
and `height` high takes `width` columns and `height / 2` rows, rounded up.
Colors are sent as 24-bit, which every current terminal draws. Alpha is
not shown.

Opening the window puts the terminal in raw mode, so that each key
arrives when it is pressed, and switches to the alternate screen, so that
closing it leaves the shell as it was. It asks for xterm's SGR mouse
reports of presses, drags and the wheel. `close`, or the window going out
of scope, undoes all of it.

The calls are POSIX, and the layout of their one structure, `termios`,
differs by platform. The window never reads it: it asks the C library to
fill it and to make it raw, in a buffer larger than any platform's.
"""

from controls.input import InputDecoder, InputEvent
from render.framebuffer import Framebuffer
from std.ffi import c_int, external_call
from units.si import Duration, MILLISECOND

comptime STANDARD_INPUT = 0
comptime STANDARD_OUTPUT = 1
# Larger than `struct termios` on Linux (60 bytes) and macOS (72).
comptime TERMIOS_BYTES = 256
# `tcsetattr` applies the change at once.
comptime TCSANOW = 0
# `poll` reports data to read.
comptime POLLIN = 1
# At most this many bytes are read a call. A mouse drag sends about ten a
# move, so this is a hundred moves.
comptime READ_BYTES = 1024

# The alternate screen, the cursor hidden, drags reported, reports in SGR
# form, and the screen cleared.
comptime ENTER = "\x1b[?1049h\x1b[?25l\x1b[?1002h\x1b[?1006h\x1b[2J"
# The same, undone in reverse order, with the colors reset.
comptime LEAVE = "\x1b[0m\x1b[?1006l\x1b[?1002l\x1b[?25h\x1b[?1049l"
# Asks the terminal for its text area in cells: xterm's window operation
# 18, answered with `ESC [ 8 ; rows ; columns t`.
comptime SIZE_QUERY = "\x1b[18t"
# Clears the screen, for a frame of a new size.
comptime CLEAR = "\x1b[0m\x1b[2J"
comptime UPPER_HALF = "▀"
comptime RESET = "\x1b[0m"


def _rgb(frame: Framebuffer, x: Int, y: Int) -> Int:
    """Return a pixel's red, green and blue as one number, or black below
    the frame's last row.

    Args:
        frame: The frame.
        x: The column, within the frame.
        y: The row, within the frame or one past it.

    Returns:
        `0xRRGGBB`.
    """
    if y >= frame.height:
        return 0
    var i = (y * frame.width + x) * 4
    return (
        (Int(frame.pixels[i]) << 16)
        | (Int(frame.pixels[i + 1]) << 8)
        | Int(frame.pixels[i + 2])
    )


def _color(mut text: String, layer: Int, rgb: Int):
    """Append the sequence that sets a color.

    Args:
        text: Where to append it.
        layer: 38 for the foreground, 48 for the background.
        rgb: The color, `0xRRGGBB`.
    """
    text += "\x1b["
    text += String(layer)
    text += ";2;"
    text += String((rgb >> 16) & 255)
    text += ";"
    text += String((rgb >> 8) & 255)
    text += ";"
    text += String(rgb & 255)
    text += "m"


def encode_frame(frame: Framebuffer) -> String:
    """Return the bytes that draw a frame at the top left of the terminal.

    Each row of cells starts with a cursor move, so a line that wraps
    cannot shift the rows below it. A color is sent only where it changes
    along a row.

    Args:
        frame: The frame.

    Returns:
        The escape sequences and the half blocks, ending with the colors
        reset.
    """
    var text = String()
    # A framebuffer's width and height are positive, so neither loop can
    # run zero times.
    for top in range(0, frame.height, 2):  # pragma: no branch
        text += "\x1b["
        text += String(top // 2 + 1)
        text += ";1H"
        var foreground = -1
        var background = -1
        for x in range(frame.width):  # pragma: no branch
            var upper = _rgb(frame, x, top)
            var lower = _rgb(frame, x, top + 1)
            if upper != foreground:
                _color(text, 38, upper)
                foreground = upper
            if lower != background:
                _color(text, 48, lower)
                background = lower
            text += UPPER_HALF
    text += RESET
    return text^


def _write_all(fd: Int, text: String) raises:
    """Write all of `text` to a file descriptor.

    Args:
        fd: The descriptor.
        text: The bytes.

    Raises:
        Error: If a write fails.
    """
    var total = text.byte_length()
    var done = 0
    var base = text.unsafe_ptr()
    # Every text this module writes ends in an escape sequence, so the loop
    # runs at least once.
    while done < total:  # pragma: no branch
        var written = external_call["write", Int](
            fd,
            base.unsafe_offset(done).unsafe_bitcast[NoneType](),
            total - done,
        )
        if written <= 0:
            raise Error("Could not write to the terminal")
        done += written


def _expect_zero(result: c_int, what: String) raises:
    """Refuse a C call's failure.

    Args:
        result: What the call returned.
        what: What it was doing, for the message.

    Raises:
        Error: If the result is not zero.
    """
    if result != 0:
        raise Error("Could not ", what)


struct TerminalWindow(Movable):
    """The terminal, showing frames of a fixed size and reading input."""

    # The frame's size, in pixels.
    var width: Int
    var height: Int
    var input_fd: Int
    var output_fd: Int
    # The terminal's settings before the window opened, to put back.
    var saved: List[UInt8]
    var decoder: InputDecoder
    var is_open: Bool

    def __init__(
        out self,
        width: Int,
        height: Int,
        *,
        input_fd: Int = STANDARD_INPUT,
        output_fd: Int = STANDARD_OUTPUT,
    ) raises:
        """Open the window: raw mode, the alternate screen, the mouse.

        Args:
            width: The frame's width, in pixels. One column each.
            height: The frame's height, in pixels. Two to a row.
            input_fd: The terminal to read, and to set raw.
            output_fd: The terminal to draw on.

        Raises:
            Error: If the size is not positive, the input is not a
                terminal, or the terminal cannot be set or written.
        """
        if width <= 0 or height <= 0:
            raise Error(
                "A window's size must be positive, got ", width, "x", height
            )
        self.width = width
        self.height = height
        self.input_fd = input_fd
        self.output_fd = output_fd
        self.saved = List[UInt8](length=TERMIOS_BYTES, fill=0)
        self.decoder = InputDecoder()
        self.is_open = False
        _expect_zero(
            external_call["tcgetattr", c_int](
                c_int(input_fd), self.saved.unsafe_ptr()
            ),
            "read the terminal's settings: the input is not a terminal",
        )
        var raw = self.saved.copy()
        external_call["cfmakeraw", NoneType](raw.unsafe_ptr())
        _expect_zero(
            external_call["tcsetattr", c_int](
                c_int(input_fd), c_int(TCSANOW), raw.unsafe_ptr()
            ),
            "set the terminal to raw mode",
        )
        self.is_open = True
        try:
            _write_all(output_fd, ENTER)
        except error:
            self._restore()
            raise error^

    def __deinit__(deinit self):
        """Close the window if it is still open, ignoring a failure: the
        terminal is left as well as it can be."""
        if self.is_open:
            try:
                _write_all(self.output_fd, LEAVE)
            except:
                pass
            self._restore()

    def _restore(mut self):
        """Put the terminal's settings back as they were, and mark the
        window closed."""
        _ = external_call["tcsetattr", c_int](
            c_int(self.input_fd), c_int(TCSANOW), self.saved.unsafe_ptr()
        )
        self.is_open = False

    def close(mut self) raises:
        """Leave the alternate screen, show the cursor, stop the mouse
        reports and put the terminal's settings back. Closing a closed
        window does nothing.

        Raises:
            Error: If the terminal cannot be written. Its settings are put
                back first.
        """
        if not self.is_open:
            return
        self._restore()
        _write_all(self.output_fd, LEAVE)

    def present(self, frame: Framebuffer) raises:
        """Draw a frame. three.js's canvas shows what was rendered into it;
        here the frame is drawn on the terminal.

        Args:
            frame: The frame, of the window's size.

        Raises:
            Error: If the window is closed, the frame is another size, or
                the terminal cannot be written.
        """
        if not self.is_open:
            raise Error("The window is closed")
        if frame.width != self.width or frame.height != self.height:
            raise Error(
                "A frame of ",
                frame.width,
                "x",
                frame.height,
                " does not fit a window of ",
                self.width,
                "x",
                self.height,
            )
        _write_all(self.output_fd, encode_frame(frame))

    def request_size(self) raises:
        """Ask the terminal for its size. three.js reads its canvas's size
        from the page; a terminal is asked.

        The answer arrives as a `RESIZE` event from a later `poll`, in the
        pixels of the largest frame that fits: one per column, two per
        row. Ask again from time to time to follow a terminal the user
        resizes. A terminal that does not answer sends nothing.

        Raises:
            Error: If the window is closed, or the terminal cannot be
                written.
        """
        if not self.is_open:
            raise Error("The window is closed")
        _write_all(self.output_fd, SIZE_QUERY)

    def resize(mut self, width: Int, height: Int) raises:
        """Change the size of the frames the window takes, and clear the
        screen. three.js: `WebGLRenderer.setSize`.

        Args:
            width: The new width, in pixels.
            height: The new height, in pixels.

        Raises:
            Error: If the window is closed, the size is not positive, or
                the terminal cannot be written.
        """
        if not self.is_open:
            raise Error("The window is closed")
        if width <= 0 or height <= 0:
            raise Error(
                "A window's size must be positive, got ", width, "x", height
            )
        self.width = width
        self.height = height
        _write_all(self.output_fd, CLEAR)

    def poll(mut self, timeout: Duration) raises -> List[InputEvent]:
        """Wait for input, and return what arrived.

        A pointer's position comes back in the frame's pixels: its column,
        and twice its row. A poll a signal interrupts returns no events.

        Args:
            timeout: How long to wait for the first byte. Zero returns at
                once.

        Returns:
            The events, oldest first. Empty if nothing arrived in time.

        Raises:
            Error: If the window is closed, the timeout is negative, or the
                terminal cannot be read.
        """
        if not self.is_open:
            raise Error("The window is closed")
        var milliseconds = Int(timeout.to(MILLISECOND))
        if milliseconds < 0:
            raise Error("A timeout must not be negative")
        # `struct pollfd` is an int and two shorts: the descriptor, then
        # the events asked for in the low half of the next int, and the
        # events that happened in the high half.
        var request = List[Int32](length=2, fill=0)
        request[0] = Int32(self.input_fd)
        request[1] = Int32(POLLIN)
        var ready = external_call["poll", c_int](
            request.unsafe_ptr(), c_int(1), c_int(milliseconds)
        )
        if ready <= 0:
            return List[InputEvent]()
        var buffer = List[UInt8](length=READ_BYTES, fill=0)
        var count = external_call["read", Int](
            self.input_fd,
            buffer.unsafe_ptr().unsafe_bitcast[NoneType](),
            READ_BYTES,
        )
        if count <= 0:
            raise Error("Could not read the terminal: it closed")
        buffer.resize(count, 0)
        var events = self.decoder.feed(buffer)
        for index in range(len(events)):
            events[index].y *= 2
        return events^
