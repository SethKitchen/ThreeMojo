# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A native window on X11: frames at full resolution, keys, the pointer
and resizes.

three.js draws into a canvas in a browser window. On Linux, and on
Windows under WSL 2 with WSLg, the window system is X11 or answers X11,
and Xlib is its C library. This module loads `libX11.so.6` when a window
opens, through `std.ffi.OwnedDLHandle`, so the library still builds and
runs with nothing but the standard library: a machine without X11 fails
only when it asks for a window. `TerminalWindow` stays the default.

The Xlib structures are read at their offsets on a 64-bit Linux ABI,
the only one X11 runs on here: `XEvent` is 192 bytes, and a key, button
or motion event holds its position at 64 and 68, its modifier state at
80 and its key code or button at 84. A frame is sent as a 24-bit
`ZPixmap` of 32 bits a pixel, blue first, which is what every TrueColor
visual on a little-endian machine takes; any other visual is refused.
"""

from controls.input import (
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    ARROW_UP,
    InputEvent,
    KEY_DOWN,
    KEY_UP,
    Key,
    MIDDLE,
    NO_BUTTON,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerButton,
    RESIZE,
    SECONDARY,
    WHEEL,
)
from render.framebuffer import Framebuffer
from std.ffi import OwnedDLHandle, c_int, external_call
from units.si import Duration, MILLISECOND

comptime LIBRARY = "libX11.so.6"
comptime EVENT_BYTES = 192
# The events asked for: key press and release, button press and release,
# pointer motion, exposure and structure changes.
comptime EVENT_MASK = 1 | 2 | 4 | 8 | (1 << 6) | (1 << 15) | (1 << 17)
# Event types.
comptime KEY_PRESS = 2
comptime KEY_RELEASE = 3
comptime BUTTON_PRESS = 4
comptime BUTTON_RELEASE = 5
comptime MOTION_NOTIFY = 6
comptime CONFIGURE_NOTIFY = 22
comptime CLIENT_MESSAGE = 33
# Modifier and button bits of an event's state.
comptime SHIFT_MASK = 1
comptime CONTROL_MASK = 4
comptime ALT_MASK = 8
comptime BUTTON1_MASK = 1 << 8
comptime BUTTON2_MASK = 1 << 9
comptime BUTTON3_MASK = 1 << 10
# Key symbols that are not their ASCII codes.
comptime XK_BACKSPACE = 0xFF08
comptime XK_TAB = 0xFF09
comptime XK_RETURN = 0xFF0D
comptime XK_ESCAPE = 0xFF1B
comptime XK_LEFT = 0xFF51
comptime XK_UP = 0xFF52
comptime XK_RIGHT = 0xFF53
comptime XK_DOWN = 0xFF54
comptime ZPIXMAP = 2
comptime POLLIN = 1


def _int32(bytes: List[UInt8], offset: Int) -> Int:
    """Return the little-endian signed 32-bit integer at an offset."""
    var value = (
        Int(bytes[offset])
        | (Int(bytes[offset + 1]) << 8)
        | (Int(bytes[offset + 2]) << 16)
        | (Int(bytes[offset + 3]) << 24)
    )
    if value >= 1 << 31:
        value -= 1 << 32
    return value


def _uint64(bytes: List[UInt8], offset: Int) -> Int:
    """Return the little-endian 64-bit integer at an offset."""
    var value = 0
    for index in range(8):  # pragma: no branch
        value |= Int(bytes[offset + index]) << (8 * index)
    return value


def key_of(symbol: Int, control: Bool) -> Key:
    """Return the key an X key symbol names, as the terminal decoder names
    it.

    A symbol that types an ASCII character is that character. With Ctrl
    held, a letter is its control code, one to twenty-six, as a terminal
    sends it: Ctrl+C is `Key(3)` either way.

    Args:
        symbol: The key symbol, from `XLookupKeysym`.
        control: Whether Ctrl is held.

    Returns:
        The key, or `NO_KEY` for a symbol this port does not name.
    """
    if symbol == XK_LEFT:
        return ARROW_LEFT
    if symbol == XK_RIGHT:
        return ARROW_RIGHT
    if symbol == XK_UP:
        return ARROW_UP
    if symbol == XK_DOWN:
        return ARROW_DOWN
    if symbol == XK_ESCAPE:
        return Key(27)
    if symbol == XK_RETURN:
        return Key(13)
    if symbol == XK_TAB:
        return Key(9)
    if symbol == XK_BACKSPACE:
        return Key(8)
    if symbol < 0x20 or symbol > 0x7E:
        return Key(-1)
    var lower = symbol | 0x20
    if control and lower >= 0x61 and lower <= 0x7A:
        return Key(lower - 0x60)
    return Key(symbol)


def event_of(bytes: List[UInt8], symbol: Int) -> Optional[InputEvent]:
    """Return the input event an X event describes, or None.

    Args:
        bytes: The `XEvent`, as 192 bytes.
        symbol: The key symbol of a key event, or anything for another.

    Returns:
        A key, pointer, wheel or resize event, or None for an event this
        port has no kind for: a button beyond the wheel, and every other
        type.
    """
    var kind = _int32(bytes, 0)
    if kind == CONFIGURE_NOTIFY:
        return InputEvent(RESIZE, x=_int32(bytes, 56), y=_int32(bytes, 60))
    var pointer = (
        kind == KEY_PRESS
        or kind == KEY_RELEASE
        or kind == BUTTON_PRESS
        or kind == BUTTON_RELEASE
        or kind == MOTION_NOTIFY
    )
    if not pointer:
        return None
    var x = _int32(bytes, 64)
    var y = _int32(bytes, 68)
    var state = _int32(bytes, 80)
    var detail = _int32(bytes, 84)
    var shift = (state & SHIFT_MASK) != 0
    var control = (state & CONTROL_MASK) != 0
    var alt = (state & ALT_MASK) != 0
    if kind == KEY_PRESS or kind == KEY_RELEASE:
        var key = key_of(symbol, control)
        if key == Key(-1):
            return None
        var what = KEY_DOWN if kind == KEY_PRESS else KEY_UP
        return InputEvent(what, key=key, shift=shift, alt=alt, ctrl=control)
    if kind == MOTION_NOTIFY:
        return InputEvent(
            POINTER_MOVE,
            button=_held(state),
            x=x,
            y=y,
            shift=shift,
            alt=alt,
            ctrl=control,
        )
    # Buttons four and five are the wheel, a notch away and toward the
    # user. Their releases say nothing more.
    if detail == 4 or detail == 5:
        if kind == BUTTON_RELEASE:
            return None
        return InputEvent(
            WHEEL, x=x, y=y, wheel=1 if detail == 5 else -1, shift=shift
        )
    if detail < 1 or detail > 3:
        return None
    var button = PRIMARY
    if detail == 2:
        button = MIDDLE
    elif detail == 3:
        button = SECONDARY
    var what = POINTER_DOWN if kind == BUTTON_PRESS else POINTER_UP
    return InputEvent(
        what, button=button, x=x, y=y, shift=shift, alt=alt, ctrl=control
    )


def _held(state: Int) -> PointerButton:
    """Return the first button a motion event's state holds, or none."""
    if (state & BUTTON1_MASK) != 0:
        return PRIMARY
    if (state & BUTTON2_MASK) != 0:
        return MIDDLE
    if (state & BUTTON3_MASK) != 0:
        return SECONDARY
    return NO_BUTTON


def is_true_color(depth: Int, red_mask: Int) -> Bool:
    """Return whether a visual is the 24-bit TrueColor that frames need.

    A frame is sent as blue, green, red and a pad byte, so red must be the
    high byte.

    Args:
        depth: The visual's depth in bits.
        red_mask: The visual's red mask.

    Returns:
        True for a depth of 24 with red in the high byte.
    """
    return depth == 24 and red_mask == 0xFF0000


struct X11Window(Movable):
    """A window from the X server, showing frames of its size."""

    var width: Int
    var height: Int
    var is_open: Bool
    # True once the window manager asked the window to close.
    var close_requested: Bool
    var _lib: OwnedDLHandle
    var _display: Int
    var _window: Int
    var _gc: Int
    var _visual: Int
    var _depth: c_int
    var _delete: Int
    var _pixels: List[UInt8]
    var _event: List[UInt8]

    def __init__(
        out self,
        width: Int,
        height: Int,
        title: String = "ThreeMojo",
        display: String = "",
    ) raises:
        """Open a window on the X server and show it.

        Args:
            width: The frame's width, in pixels.
            height: The frame's height, in pixels.
            title: The window's title.
            display: The X display, as `DISPLAY` names one. Empty takes
                `DISPLAY` from the environment.

        Raises:
            Error: If the size is not positive, `libX11.so.6` cannot be
                loaded, the display cannot be opened, or its visual is not
                24-bit TrueColor.
        """
        if width <= 0 or height <= 0:
            raise Error(
                "A window's size must be positive, got ", width, "x", height
            )
        self.width = width
        self.height = height
        self.is_open = False
        self.close_requested = False
        self._lib = OwnedDLHandle(LIBRARY)
        var name = display
        var display_name = Int(name.as_c_string_span().ptr())
        if display == "":
            display_name = 0
        self._display = self._lib.call["XOpenDisplay", Int](display_name)
        # An address does not keep its bytes alive: each buffer passed by
        # address is dropped only after the call that reads it.
        _ = name^
        if self._display == 0:
            raise Error("Could not open the X display '", display, "'")
        var screen = self._lib.call["XDefaultScreen", c_int](self._display)
        self._visual = self._lib.call["XDefaultVisual", Int](
            self._display, screen
        )
        self._depth = self._lib.call["XDefaultDepth", c_int](
            self._display, screen
        )
        self._gc = self._lib.call["XDefaultGC", Int](self._display, screen)
        # A Visual's red mask sits after its extension data, its id and its
        # class: at 24 on a 64-bit ABI.
        var red_mask = Pointer[UInt64, MutAnyOrigin](
            unsafe_from_address=self._visual + 24
        )[]
        if not is_true_color(Int(self._depth), Int(red_mask)):
            _ = self._lib.call["XCloseDisplay", c_int](self._display)
            raise Error("The X display's visual is not 24-bit TrueColor")
        var root = self._lib.call["XRootWindow", Int](self._display, screen)
        self._window = self._lib.call["XCreateSimpleWindow", Int](
            self._display,
            root,
            c_int(0),
            c_int(0),
            c_int(width),
            c_int(height),
            c_int(0),
            Int(0),
            Int(0),
        )
        _ = self._lib.call["XSelectInput", c_int](
            self._display, self._window, Int(EVENT_MASK)
        )
        var title_text = title
        _ = self._lib.call["XStoreName", c_int](
            self._display,
            self._window,
            Int(title_text.as_c_string_span().ptr()),
        )
        _ = title_text^
        var atom_name = String("WM_DELETE_WINDOW")
        self._delete = self._lib.call["XInternAtom", Int](
            self._display, Int(atom_name.as_c_string_span().ptr()), c_int(0)
        )
        _ = atom_name^
        var protocols = List[Int](length=1, fill=self._delete)
        _ = self._lib.call["XSetWMProtocols", c_int](
            self._display, self._window, Int(protocols.unsafe_ptr()), c_int(1)
        )
        _ = protocols^
        _ = self._lib.call["XMapWindow", c_int](self._display, self._window)
        _ = self._lib.call["XFlush", c_int](self._display)
        self._pixels = List[UInt8](length=width * height * 4, fill=0)
        self._event = List[UInt8](length=EVENT_BYTES, fill=0)
        self.is_open = True

    def __deinit__(deinit self):
        """Close the window if it is still open."""
        if self.is_open:
            self._shut()

    def _shut(mut self):
        """Destroy the window and close the display."""
        _ = self._lib.call["XDestroyWindow", c_int](self._display, self._window)
        _ = self._lib.call["XCloseDisplay", c_int](self._display)
        self.is_open = False

    def close(mut self):
        """Destroy the window. Closing a closed window does nothing."""
        if self.is_open:
            self._shut()

    def present(mut self, frame: Framebuffer) raises:
        """Draw a frame at the window's top left.

        Args:
            frame: The frame, of the window's size.

        Raises:
            Error: If the window is closed or the frame is another size.
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
        # RGBA to the visual's order: blue, green, red, then a byte the
        # server ignores.
        for pixel in range(self.width * self.height):  # pragma: no branch
            var at = pixel * 4
            self._pixels[at] = frame.pixels[at + 2]
            self._pixels[at + 1] = frame.pixels[at + 1]
            self._pixels[at + 2] = frame.pixels[at]
            self._pixels[at + 3] = 255
        var image = self._lib.call["XCreateImage", Int](
            self._display,
            self._visual,
            UInt32(24),
            c_int(ZPIXMAP),
            c_int(0),
            Int(self._pixels.unsafe_ptr()),
            UInt32(self.width),
            UInt32(self.height),
            c_int(32),
            c_int(0),
        )
        _ = self._lib.call["XPutImage", c_int](
            self._display,
            self._window,
            self._gc,
            image,
            c_int(0),
            c_int(0),
            c_int(0),
            c_int(0),
            UInt32(self.width),
            UInt32(self.height),
        )
        # The pixels are ours: take them back before the image is freed.
        # An XImage's data pointer sits after four ints, at 16.
        Pointer[Int, MutAnyOrigin](unsafe_from_address=image + 16)[] = 0
        _ = self._lib.call["XFree", c_int](image)
        _ = self._lib.call["XFlush", c_int](self._display)

    def resize(mut self, width: Int, height: Int) raises:
        """Take frames of a new size. A `RESIZE` event says when the user
        resized the window; this does not resize it.

        Args:
            width: The new width, in pixels.
            height: The new height, in pixels.

        Raises:
            Error: If the window is closed or the size is not positive.
        """
        if not self.is_open:
            raise Error("The window is closed")
        if width <= 0 or height <= 0:
            raise Error(
                "A window's size must be positive, got ", width, "x", height
            )
        self.width = width
        self.height = height
        self._pixels = List[UInt8](length=width * height * 4, fill=0)

    def poll(mut self, timeout: Duration) raises -> List[InputEvent]:
        """Wait for input, and return what arrived.

        A resize to the size the window already has is not reported. A
        request from the window manager to close sets `close_requested`.

        Args:
            timeout: How long to wait for the first event. Zero returns at
                once.

        Returns:
            The events, oldest first, with positions in pixels.

        Raises:
            Error: If the window is closed or the timeout is negative.
        """
        if not self.is_open:
            raise Error("The window is closed")
        var milliseconds = Int(timeout.to(MILLISECOND))
        if milliseconds < 0:
            raise Error("A timeout must not be negative")
        var events = List[InputEvent]()
        if self._lib.call["XPending", c_int](self._display) == 0:
            var request = List[Int32](length=2, fill=0)
            request[0] = self._lib.call["XConnectionNumber", c_int](
                self._display
            )
            request[1] = Int32(POLLIN)
            _ = external_call["poll", c_int](
                request.unsafe_ptr(), c_int(1), c_int(milliseconds)
            )
        while self._lib.call["XPending", c_int](self._display) > 0:
            _ = self._lib.call["XNextEvent", c_int](
                self._display, Int(self._event.unsafe_ptr())
            )
            var kind = _int32(self._event, 0)
            if kind == CLIENT_MESSAGE:
                if _uint64(self._event, 56) == self._delete:
                    self.close_requested = True
                continue
            var symbol = 0
            if kind == KEY_PRESS or kind == KEY_RELEASE:
                symbol = self._lib.call["XLookupKeysym", Int](
                    Int(self._event.unsafe_ptr()), c_int(0)
                )
            var found = event_of(self._event, symbol)
            if not Bool(found):
                continue
            var event = found.value()
            var same = event.x == self.width and event.y == self.height
            if event.kind == RESIZE and same:
                continue
            events.append(event)
        return events^
