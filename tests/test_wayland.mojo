# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `window.wayland`.

The window speaks the Wayland protocol over a socket. Most tests give it
one end of a socket pair and play the compositor on the other end: they
write the events a compositor sends before the window reads them, and
then read the requests the window sent. The object ids are the ones the
window gives its objects in order, so the tests know them. This needs no
compositor and no display.

One test opens a window on a real compositor, a headless `weston`, and
reads the frame back from a screenshot. It runs when `weston` and
`weston-screenshooter` are installed, and does nothing when they are not.
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
    NO_KEY,
    POINTER_CANCEL,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    PointerId,
    RESIZE,
    SECONDARY,
    TOUCH_POINTER,
    WHEEL,
)
from render.framebuffer import Color, Framebuffer
from render.png import decode
from std.ffi import OwnedDLHandle, c_int
from std.math import inf
from std.os import getenv, setenv
from std.pathlib import Path
from std.subprocess import run
from std.tempfile import mkdtemp
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from std.time import perf_counter_ns
from core.binary import (
    little_endian_i32,
    little_endian_u32,
    little_endian_uint,
    store_little_endian,
)
from test_scratch import TestScratch, temporary_path
from units.si import Duration, MILLISECOND, SECOND
from window.present import NATIVE_WINDOW_MAX
from window.wayland import (
    NO_INTERFACE,
    SILENT,
    WaylandInterface,
    WaylandSocket,
    WaylandWindow,
    WireMessage,
    button_of,
    connect_display,
    control_descriptors,
    descriptor_control,
    fixed_to_pixel,
    held_button,
    is_bsd,
    key_of_code,
    key_symbol,
    receive_message,
    require_buffer_size,
    require_io,
    runtime_folder,
    send_message,
    socket_address,
    socket_path,
    socket_ready,
)

# The ids the window gives its objects when the compositor has a seat and
# decorations: the registry, the first callback, then each object in the
# order the window makes it.
comptime REGISTRY = 2
comptime CALLBACK = 3
comptime COMPOSITOR = 4
comptime SHM = 5
comptime WM_BASE = 6
comptime SEAT = 7
comptime SURFACE = 8
comptime XDG_SURFACE = 9
comptime TOPLEVEL = 10
comptime MANAGER = 11
comptime DECORATION = 12
comptime POINTER = 13
comptime KEYBOARD = 14
comptime TOUCH = 15
comptime FIRST_POOL = 16
# Linux key codes.
comptime CODE_ESCAPE = 1
comptime CODE_Q = 16
comptime CODE_A = 30
comptime CODE_C = 46
comptime CODE_LEFT_SHIFT = 42
comptime CODE_UP = 103


def _fixed(pixel: Int) -> Int:
    """Return a pixel as a Wayland fixed-point number.

    Args:
        pixel: The pixel.

    Returns:
        The number, in 256ths.
    """
    return pixel * 256


def _message(object: Int, opcode: Int, *words: Int) -> List[UInt8]:
    """Return a message whose arguments are all words.

    Args:
        object: The object's id.
        opcode: The request's or the event's number.
        words: The arguments.

    Returns:
        The bytes.
    """
    var message = WireMessage(object, opcode)
    for word in words:
        message.word(word)
    return message.finish()


def _same(actual: List[UInt8], expected: List[UInt8]) raises:
    """Assert that two messages are the same bytes.

    Args:
        actual: The message read.
        expected: The message expected.

    Raises:
        Error: If they differ.
    """
    assert_equal(len(actual), len(expected))
    for index in range(len(expected)):
        assert_equal(actual[index], expected[index])


struct Compositor(Movable):
    """The compositor's end of a socket pair. A test writes the events a
    compositor sends, and reads the requests the window sent."""

    var lib: OwnedDLHandle
    # The compositor's end, and the end the window takes.
    var fd: Int
    var window_end: Int
    # The file descriptors the window sent, oldest first.
    var descriptors: List[Int]

    def __init__(out self) raises:
        """Make the socket pair.

        Raises:
            Error: If the system refuses.
        """
        self.lib = OwnedDLHandle()
        self.descriptors = List[Int]()
        var pair = List[Int32](length=2, fill=-1)
        var result = self.lib.call["socketpair", c_int](
            c_int(1), c_int(1), c_int(0), Int(pair.unsafe_ptr())
        )
        self.fd = Int(pair[0])
        self.window_end = Int(pair[1])
        if result != 0:
            raise Error("socketpair failed")

    def socket(self) -> WaylandSocket:
        """Return the end the window takes.

        Returns:
            The socket.
        """
        return WaylandSocket(self.window_end)

    def send(mut self, bytes: List[UInt8], descriptor: Int = -1) raises:
        """Write bytes to the window, with a file descriptor if given.

        Args:
            bytes: The bytes.
            descriptor: A descriptor to send with them, or -1.

        Raises:
            Error: If the socket does not take them.
        """
        var sent = send_message(
            self.lib, WaylandSocket(self.fd), bytes, descriptor, is_bsd()
        )
        if sent != len(bytes):
            raise Error("the test could not write to the window")

    def event(mut self, object: Int, opcode: Int, *words: Int) raises:
        """Send an event whose arguments are all words.

        Args:
            object: The object's id.
            opcode: The event's number.
            words: The arguments.

        Raises:
            Error: If the socket does not take it.
        """
        var message = WireMessage(object, opcode)
        for word in words:
            message.word(word)
        self.send(message.finish())

    def global_(mut self, name: Int, interface: String, version: Int) raises:
        """Send `wl_registry.global`.

        Args:
            name: The global's name.
            interface: Its interface.
            version: Its version.

        Raises:
            Error: If the socket does not take it.
        """
        var message = WireMessage(REGISTRY, 0)
        message.word(name)
        message.text(interface)
        message.word(version)
        self.send(message.finish())

    def requests(mut self) raises -> List[List[UInt8]]:
        """Read every request the window has sent, without waiting.

        Returns:
            The requests, each as its bytes, oldest first.

        Raises:
            Error: If a request is cut short.
        """
        var bytes = List[UInt8]()
        var socket = WaylandSocket(self.fd)
        while socket_ready(self.lib, socket, 0):
            var received = receive_message(self.lib, socket, is_bsd())
            if received.count <= 0:
                break
            for descriptor in received.descriptors:
                self.descriptors.append(descriptor)
            for byte in received.bytes:
                bytes.append(byte)
        var requests = List[List[UInt8]]()
        var start = 0
        while start < len(bytes):
            var size = little_endian_u32(bytes, start + 4) >> 16
            if size < 8 or start + size > len(bytes):
                raise Error("the window sent a request cut short")
            var request = List[UInt8](capacity=size)
            for index in range(size):
                request.append(bytes[start + index])
            requests.append(request^)
            start += size
        return requests^

    def hang_up(mut self):
        """Stop writing: the window then reads the end of the stream, and
        can still write."""
        _ = self.lib.call["shutdown", c_int](c_int(self.fd), c_int(1))

    def close(mut self):
        """Close the compositor's end and the descriptors it holds."""
        for descriptor in self.descriptors:
            _ = self.lib.call["close", c_int](c_int(descriptor))
        self.descriptors.clear()
        _ = self.lib.call["close", c_int](c_int(self.fd))

    def stored(self, descriptor: Int, offset: Int) raises -> List[UInt8]:
        """Read four bytes of a file the window sent.

        Args:
            descriptor: The file.
            offset: Where to read.

        Returns:
            The bytes.

        Raises:
            Error: If the file is shorter.
        """
        var bytes = List[UInt8](length=4, fill=0)
        var count = self.lib.call["pread", Int](
            c_int(descriptor), Int(bytes.unsafe_ptr()), 4, offset
        )
        if count != 4:
            raise Error("the file is too short")
        return bytes^


def _globals(
    mut compositor: Compositor, *, seat: Int = 7, decoration: Bool = True
) raises:
    """Send the registry's globals, and finish the first callback.

    Args:
        compositor: The compositor.
        seat: The version of `wl_seat`, or zero for no seat.
        decoration: Whether the compositor has `xdg-decoration`.

    Raises:
        Error: If the socket does not take them.
    """
    compositor.global_(1, "wl_compositor", 5)
    compositor.global_(2, "wl_shm", 1)
    compositor.global_(3, "xdg_wm_base", 5)
    if seat > 0:
        compositor.global_(4, "wl_seat", seat)
    if decoration:
        compositor.global_(5, "zxdg_decoration_manager_v1", 1)
    # A global the window does not use.
    compositor.global_(6, "wl_output", 4)
    compositor.event(CALLBACK, 0, 0)


def _open(
    mut compositor: Compositor,
    width: Int = 8,
    height: Int = 6,
    capabilities: Int = 7,
) raises -> WaylandWindow:
    """Open a window on a compositor with a seat and decorations, and
    throw away the requests of the opening.

    Args:
        compositor: The compositor.
        width: The window's width.
        height: The window's height.
        capabilities: What the seat has.

    Returns:
        The window.

    Raises:
        Error: If the window is refused.
    """
    _globals(compositor)
    compositor.event(SEAT, 0, capabilities)
    compositor.event(TOPLEVEL, 0, 0, 0, 0)
    compositor.event(XDG_SURFACE, 0, 77)
    var window = WaylandWindow(
        width, height, "title", compositor.socket(), Duration(2.0, SECOND)
    )
    _ = compositor.requests()
    return window^


def _zero() -> Duration:
    """Return no time at all."""
    return Duration(0.0, SECOND)


# --- the pure parts ----------------------------------------------------------


def test_the_types_know_their_values() raises:
    assert_true(WaylandSocket(0).is_valid())
    assert_false(WaylandSocket(-1).is_valid())
    assert_true(NO_INTERFACE.is_valid())
    assert_true(SILENT.is_valid())
    assert_false(WaylandInterface(-1).is_valid())
    assert_false(WaylandInterface(13).is_valid())


def test_a_failed_call_is_refused() raises:
    require_io(True, "nothing")
    with assert_raises(contains="Wayland: the reason"):
        require_io(False, "the reason")


def test_the_socket_path_is_found_as_libwayland_finds_it() raises:
    assert_equal(socket_path("", "/run/user/7"), "/run/user/7/wayland-0")
    assert_equal(
        socket_path("wayland-3", "/run/user/7"), "/run/user/7/wayland-3"
    )
    assert_equal(socket_path("/tmp/elsewhere", ""), "/tmp/elsewhere")
    with assert_raises(contains="XDG_RUNTIME_DIR"):
        _ = socket_path("wayland-0", "")
    # A path of 103 bytes fits both layouts of a socket address.
    var long = String("/")
    for _ in range(102):
        long += "x"
    assert_equal(socket_path(long, ""), long)
    with assert_raises(contains="too long"):
        _ = socket_path(long + "x", "")
    assert_equal(runtime_folder(""), "/tmp")
    assert_equal(runtime_folder("/run/user/7"), "/run/user/7")


def test_a_socket_address_is_its_family_and_its_path() raises:
    # Linux: the family in 16 bits.
    var address = socket_address("/a/b", False)
    assert_equal(len(address), 106)
    assert_equal(address[0], 1)
    assert_equal(address[1], 0)
    assert_equal(address[2], 47)
    assert_equal(address[3], 97)
    assert_equal(address[5], 98)
    assert_equal(address[6], 0)
    # The BSD layout: the address's length, then the family, in a byte
    # each.
    var bsd = socket_address("/a/b", True)
    assert_equal(len(bsd), 106)
    assert_equal(bsd[0], 106)
    assert_equal(bsd[1], 1)
    assert_equal(bsd[2], 47)
    assert_equal(bsd[5], 98)
    assert_equal(bsd[6], 0)
    var empty = socket_address("", False)
    assert_equal(len(empty), 106)
    assert_equal(empty[2], 0)
    # A path of 103 bytes fills the address up to its last byte, which
    # ends the path. A longer one is refused in either layout.
    var long = String("/")
    for _ in range(102):
        long += "x"
    for bsd in [False, True]:
        var full = socket_address(long, bsd)
        assert_equal(len(full), 106)
        assert_equal(full[104], 120)
        assert_equal(full[105], 0)
        with assert_raises(contains="too long"):
            _ = socket_address(long + "x", bsd)


def test_a_descriptor_travels_in_control_data_of_either_layout() raises:
    # Linux: a 64-bit length of 20, level 1, type 1, the descriptor, and
    # padding to eight bytes.
    var linux: List[UInt8] = [
        20,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        7,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ]
    _same(descriptor_control(7, False), linux)
    # The BSD layout: a 32-bit length of 16, level 0xFFFF, type 1, and the
    # descriptor.
    var bsd: List[UInt8] = [
        16,
        0,
        0,
        0,
        0xFF,
        0xFF,
        0,
        0,
        1,
        0,
        0,
        0,
        7,
        0,
        0,
        0,
    ]
    _same(descriptor_control(7, True), bsd)
    # Read back: the header's control length is at 40, in 64 bits on Linux
    # and in 32 in the BSD layout, where the flags follow it.
    var header = List[UInt8](length=56, fill=0)
    header[40] = 24
    var found = control_descriptors(header, linux, False)
    assert_equal(len(found), 1)
    assert_equal(found[0], 7)
    header[40] = 16
    header[44] = 0x20
    found = control_descriptors(header, bsd, True)
    assert_equal(len(found), 1)
    assert_equal(found[0], 7)
    # No control data, and control data the buffer does not hold.
    header[44] = 0
    header[40] = 0
    assert_equal(len(control_descriptors(header, linux, False)), 0)
    header[40] = 200
    assert_equal(len(control_descriptors(header, linux, False)), 1)
    # Two pieces: one with two descriptors, and one with none.
    var two: List[UInt8] = [
        24,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        3,
        0,
        0,
        0,
        4,
        0,
        0,
        0,
        16,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
    ]
    header[40] = 40
    found = control_descriptors(header, two, False)
    assert_equal(len(found), 2)
    assert_equal(found[0], 3)
    assert_equal(found[1], 4)
    # A piece whose length is zero does not stop the reading.
    var zero = List[UInt8](length=32, fill=0)
    header[40] = 32
    assert_equal(len(control_descriptors(header, zero, True)), 0)
    assert_false(is_bsd() and not is_bsd())


def test_fixed_point_coordinates_round_down_to_pixels() raises:
    assert_equal(fixed_to_pixel(0), 0)
    assert_equal(fixed_to_pixel(255), 0)
    assert_equal(fixed_to_pixel(256), 1)
    assert_equal(fixed_to_pixel(256 * 7 + 128), 7)
    assert_equal(fixed_to_pixel(-1), -1)
    assert_equal(fixed_to_pixel(-256), -1)
    assert_equal(fixed_to_pixel(-257), -2)


def test_button_codes_and_held_buttons() raises:
    assert_true(button_of(0x110) == PRIMARY)
    assert_true(button_of(0x111) == SECONDARY)
    assert_true(button_of(0x112) == MIDDLE)
    assert_true(button_of(0x113) == NO_BUTTON)
    assert_true(held_button(0) == NO_BUTTON)
    assert_true(held_button(1) == PRIMARY)
    assert_true(held_button(2) == MIDDLE)
    assert_true(held_button(4) == SECONDARY)
    assert_true(held_button(7) == PRIMARY)
    assert_true(held_button(6) == MIDDLE)


def test_key_codes_are_read_as_a_us_keyboard_labels_them() raises:
    assert_true(key_of_code(CODE_Q, False) == Key(113))
    assert_true(key_of_code(CODE_A, False) == Key(97))
    assert_true(key_of_code(2, False) == Key(49))
    assert_true(key_of_code(11, False) == Key(48))
    assert_true(key_of_code(53, False) == Key(47))
    assert_true(key_of_code(43, False) == Key(92))
    assert_true(key_of_code(57, False) == Key(32))
    assert_true(key_of_code(CODE_ESCAPE, False) == Key(27))
    assert_true(key_of_code(14, False) == Key(8))
    assert_true(key_of_code(15, False) == Key(9))
    assert_true(key_of_code(28, False) == Key(13))
    assert_true(key_of_code(CODE_UP, False) == ARROW_UP)
    assert_true(key_of_code(108, False) == ARROW_DOWN)
    assert_true(key_of_code(105, False) == ARROW_LEFT)
    assert_true(key_of_code(106, False) == ARROW_RIGHT)
    # Ctrl with a letter is its control code, as a terminal sends it.
    assert_true(key_of_code(CODE_C, True) == Key(3))
    assert_true(key_of_code(2, True) == Key(49))
    # A modifier, and codes off the table, name no key.
    assert_true(key_of_code(CODE_LEFT_SHIFT, False) == NO_KEY)
    assert_true(key_of_code(29, False) == NO_KEY)
    assert_true(key_of_code(0, False) == NO_KEY)
    assert_true(key_of_code(-4, False) == NO_KEY)
    assert_true(key_of_code(54, False) == NO_KEY)
    assert_true(key_of_code(200, False) == NO_KEY)
    assert_equal(key_symbol(CODE_ESCAPE), 0xFF1B)
    assert_equal(key_symbol(CODE_LEFT_SHIFT), 0)


def test_a_message_is_words_least_significant_byte_first() raises:
    var bytes = _message(3, 5, 1, -2)
    var expected: List[UInt8] = [
        3,
        0,
        0,
        0,
        5,
        0,
        16,
        0,
        1,
        0,
        0,
        0,
        0xFE,
        0xFF,
        0xFF,
        0xFF,
    ]
    _same(bytes, expected)
    # A string is its length with its end, its bytes, and zeros up to a
    # whole word.
    var message = WireMessage(2, 0)
    message.text("abc")
    message.text("wl_shm")
    message.text("")
    var text: List[UInt8] = [
        2,
        0,
        0,
        0,
        0,
        0,
        36,
        0,
        4,
        0,
        0,
        0,
        97,
        98,
        99,
        0,
        7,
        0,
        0,
        0,
        119,
        108,
        95,
        115,
        104,
        109,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
    ]
    _same(message.finish(), text)


def test_a_frame_must_fit_a_wayland_buffer() raises:
    require_buffer_size(1, 1)
    require_buffer_size(23170, 23170)
    with assert_raises(contains="Wayland buffer"):
        require_buffer_size(23171, 23171)
    with assert_raises(contains="Wayland buffer"):
        require_buffer_size(NATIVE_WINDOW_MAX, 1)


# --- connecting ----------------------------------------------------------------


def _in_session(name: String) -> String:
    """Return a path in the session's folder, where a display has its
    socket.

    Args:
        name: The file's name.

    Returns:
        The path.
    """
    return getenv("XDG_RUNTIME_DIR", "") + "/" + name


def test_a_display_nobody_listens_on_is_refused() raises:
    with assert_raises(contains="Could not connect"):
        _ = connect_display(_in_session("threemojo-no-compositor"))
    # With no display named, the environment names it.
    _ = setenv("WAYLAND_DISPLAY", "threemojo-nobody-listens")
    with assert_raises(contains="threemojo-nobody-listens"):
        _ = connect_display()
    with assert_raises(contains="Could not connect"):
        _ = WaylandWindow(4, 4, "title", "threemojo-nobody-listens")
    with assert_raises(contains="must be positive"):
        _ = WaylandWindow(0, 4)
    with assert_raises(contains="Wayland buffer"):
        _ = WaylandWindow(30000, 30000)


def test_a_listening_socket_is_connected_to() raises:
    var lib = OwnedDLHandle()
    var path = _in_session("threemojo-wayland-listen")
    var listener = lib.call["socket", c_int](c_int(1), c_int(1), c_int(0))
    var address = socket_address(path, is_bsd())
    assert_equal(
        Int(
            lib.call["bind", c_int](
                listener, Int(address.unsafe_ptr()), UInt32(len(address))
            )
        ),
        0,
    )
    _ = address^
    assert_equal(Int(lib.call["listen", c_int](listener, c_int(1))), 0)
    var socket = connect_display(path)
    assert_true(socket.is_valid())
    _ = lib.call["close", c_int](c_int(socket.value))
    _ = lib.call["close", c_int](listener)
    _ = run("rm -f '" + path + "'")


# --- opening -------------------------------------------------------------------


def test_opening_binds_the_globals_and_makes_the_window() raises:
    var compositor = Compositor()
    _globals(compositor)
    compositor.event(SEAT, 0, 7)
    compositor.event(TOPLEVEL, 0, 0, 0, 0)
    compositor.event(XDG_SURFACE, 0, 77)
    var window = WaylandWindow(
        8, 6, "A title", compositor.socket(), Duration(2.0, SECOND)
    )
    assert_true(window.is_open)
    assert_false(window.close_requested)
    assert_equal(window.width, 8)
    assert_equal(window.height, 6)
    var requests = compositor.requests()
    assert_equal(len(requests), 19)
    _same(requests[0], _message(1, 1, REGISTRY))
    _same(requests[1], _message(1, 0, CALLBACK))
    var bind = WireMessage(REGISTRY, 0)
    bind.word(1)
    bind.text("wl_compositor")
    bind.word(1)
    bind.word(COMPOSITOR)
    _same(requests[2], bind.finish())
    bind = WireMessage(REGISTRY, 0)
    bind.word(2)
    bind.text("wl_shm")
    bind.word(1)
    bind.word(SHM)
    _same(requests[3], bind.finish())
    bind = WireMessage(REGISTRY, 0)
    bind.word(3)
    bind.text("xdg_wm_base")
    bind.word(1)
    bind.word(WM_BASE)
    _same(requests[4], bind.finish())
    # The seat is version 7. The window speaks version 4.
    bind = WireMessage(REGISTRY, 0)
    bind.word(4)
    bind.text("wl_seat")
    bind.word(4)
    bind.word(SEAT)
    _same(requests[5], bind.finish())
    _same(requests[6], _message(COMPOSITOR, 0, SURFACE))
    _same(requests[7], _message(WM_BASE, 2, XDG_SURFACE, SURFACE))
    _same(requests[8], _message(XDG_SURFACE, 1, TOPLEVEL))
    var title = WireMessage(TOPLEVEL, 2)
    title.text("A title")
    _same(requests[9], title.finish())
    bind = WireMessage(REGISTRY, 0)
    bind.word(5)
    bind.text("zxdg_decoration_manager_v1")
    bind.word(1)
    bind.word(MANAGER)
    _same(requests[10], bind.finish())
    _same(requests[11], _message(MANAGER, 1, DECORATION, TOPLEVEL))
    # A title bar that the compositor draws.
    _same(requests[12], _message(DECORATION, 1, 2))
    _same(requests[13], _message(SURFACE, 6))
    # The seat's devices, then the answer to the first size.
    _same(requests[14], _message(SEAT, 0, POINTER))
    _same(requests[15], _message(SEAT, 1, KEYBOARD))
    _same(requests[16], _message(SEAT, 2, TOUCH))
    _same(requests[17], _message(XDG_SURFACE, 4, 77))
    _same(requests[18], _message(SURFACE, 6))
    window.close()
    assert_false(window.is_open)
    window.close()
    compositor.close()


def test_a_compositor_with_no_seat_and_no_decorations_still_opens() raises:
    var compositor = Compositor()
    _globals(compositor, seat=0, decoration=False)
    # The surface is object 7, its role 8 and the window 9.
    compositor.event(9, 0, 0, 0, 0)
    compositor.event(8, 0, 5)
    var window = WaylandWindow(
        8, 6, "title", compositor.socket(), Duration(2.0, SECOND)
    )
    var requests = compositor.requests()
    assert_equal(len(requests), 12)
    _same(requests[5], _message(COMPOSITOR, 0, 7))
    _same(requests[10], _message(8, 4, 5))
    window.close()
    compositor.close()
    # An old seat is bound at its own version.
    var old = Compositor()
    _globals(old, seat=2, decoration=False)
    old.event(SEAT, 0, 0)
    old.event(TOPLEVEL, 0, 0, 0, 0)
    old.event(XDG_SURFACE, 0, 5)
    var second = WaylandWindow(
        8, 6, "title", old.socket(), Duration(2.0, SECOND)
    )
    var bind = WireMessage(REGISTRY, 0)
    bind.word(4)
    bind.text("wl_seat")
    bind.word(2)
    bind.word(SEAT)
    _same(old.requests()[5], bind.finish())
    second.close()
    old.close()


def test_a_compositor_that_lacks_a_global_is_refused() raises:
    var names: List[String] = ["wl_compositor", "wl_shm", "xdg_wm_base"]
    for missing in range(3):
        var compositor = Compositor()
        for index in range(3):
            if index != missing:
                compositor.global_(index + 1, names[index], 1)
        compositor.event(CALLBACK, 0, 0)
        with assert_raises(contains="lacks"):
            _ = WaylandWindow(
                8, 6, "title", compositor.socket(), Duration(2.0, SECOND)
            )
        compositor.close()


def test_a_compositor_that_does_not_answer_is_refused() raises:
    var silent = Compositor()
    var start = perf_counter_ns()
    with assert_raises(contains="did not answer in time"):
        _ = WaylandWindow(
            8, 6, "title", silent.socket(), Duration(30.0, MILLISECOND)
        )
    assert_true(perf_counter_ns() - start < 2000000000)
    silent.close()
    # No time at all to answer.
    var hurried = Compositor()
    with assert_raises(contains="did not answer in time"):
        _ = WaylandWindow(8, 6, "title", hurried.socket(), _zero())
    hurried.close()
    # It answers the first step, and never gives the window a size.
    var half = Compositor()
    _globals(half)
    with assert_raises(contains="did not answer in time"):
        _ = WaylandWindow(
            8, 6, "title", half.socket(), Duration(30.0, MILLISECOND)
        )
    half.close()


def test_a_compositor_that_leaves_or_errs_is_refused() raises:
    var gone = Compositor()
    gone.hang_up()
    with assert_raises(contains="closed the connection"):
        _ = WaylandWindow(8, 6, "title", gone.socket(), Duration(2.0, SECOND))
    gone.close()
    # Its end is closed: the first request cannot be written.
    var closed = Compositor()
    closed.close()
    with assert_raises(contains="cannot be written"):
        _ = WaylandWindow(8, 6, "title", closed.socket(), Duration(2.0, SECOND))
    # `wl_display.error`: an object, a code and a message.
    var erring = Compositor()
    var error = WireMessage(1, 0)
    error.word(1)
    error.word(3)
    error.text("no memory")
    erring.send(error.finish())
    with assert_raises(contains="reports an error: no memory"):
        _ = WaylandWindow(8, 6, "title", erring.socket(), Duration(2.0, SECOND))
    erring.close()


def test_a_malformed_message_is_refused() raises:
    # A size below the header's.
    var short = Compositor()
    var bytes: List[UInt8] = [2, 0, 0, 0, 0, 0, 4, 0]
    short.send(bytes)
    with assert_raises(contains="malformed"):
        _ = WaylandWindow(8, 6, "title", short.socket(), Duration(2.0, SECOND))
    short.close()
    # A size that is no whole number of words.
    var odd = Compositor()
    var uneven: List[UInt8] = [2, 0, 0, 0, 0, 0, 10, 0, 0, 0]
    odd.send(uneven)
    with assert_raises(contains="malformed"):
        _ = WaylandWindow(8, 6, "title", odd.socket(), Duration(2.0, SECOND))
    odd.close()


def test_a_window_is_refused_what_it_cannot_do() raises:
    var compositor = Compositor()
    with assert_raises(contains="must be positive"):
        _ = WaylandWindow(0, 4, "title", compositor.socket())
    with assert_raises(contains="must be positive"):
        _ = WaylandWindow(4, 0, "title", compositor.socket())
    with assert_raises(contains="native integer"):
        _ = WaylandWindow(
            NATIVE_WINDOW_MAX + 1, 1, "title", compositor.socket()
        )
    with assert_raises(contains="Wayland buffer"):
        _ = WaylandWindow(30000, 30000, "title", compositor.socket())
    with assert_raises(contains="not a file descriptor"):
        _ = WaylandWindow(4, 4, "title", WaylandSocket(-1))
    with assert_raises(contains="negative"):
        _ = WaylandWindow(
            4, 4, "title", compositor.socket(), Duration(-1.0, SECOND)
        )
    with assert_raises(contains="finite"):
        _ = WaylandWindow(
            4,
            4,
            "title",
            compositor.socket(),
            Duration(inf[DType.float32](), SECOND),
        )
    _ = compositor.lib.call["close", c_int](c_int(compositor.window_end))
    compositor.close()


# --- frames --------------------------------------------------------------------


def test_a_window_shows_a_frame() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    var frame = Framebuffer(8, 6, Color(200, 40, 10))
    frame.set_pixel(3, 2, Color(0, 0, 255))
    window.present(frame)
    var requests = compositor.requests()
    assert_equal(len(requests), 5)
    # A pool over a file of 8 by 6 pixels, four bytes each, then a buffer
    # in it: no offset, the size, 32 bytes a row, and `XRGB8888`.
    _same(requests[0], _message(SHM, 0, FIRST_POOL, 192))
    _same(requests[1], _message(FIRST_POOL, 0, FIRST_POOL + 1, 0, 8, 6, 32, 1))
    _same(requests[2], _message(SURFACE, 1, FIRST_POOL + 1, 0, 0))
    _same(requests[3], _message(SURFACE, 2, 0, 0, 8, 6))
    _same(requests[4], _message(SURFACE, 6))
    # The file came with the pool. A pixel is blue, green, red and a byte
    # the compositor ignores.
    assert_equal(len(compositor.descriptors), 1)
    var first: List[UInt8] = [10, 40, 200, 255]
    _same(compositor.stored(compositor.descriptors[0], 0), first)
    var blue: List[UInt8] = [255, 0, 0, 255]
    _same(compositor.stored(compositor.descriptors[0], (2 * 8 + 3) * 4), blue)
    # The compositor still shows the first buffer, so the next frame gets
    # a second one.
    frame.set_pixel(0, 0, Color(1, 2, 3))
    window.present(frame)
    requests = compositor.requests()
    assert_equal(len(requests), 5)
    _same(requests[0], _message(SHM, 0, FIRST_POOL + 2, 192))
    _same(requests[2], _message(SURFACE, 1, FIRST_POOL + 3, 0, 0))
    assert_equal(len(compositor.descriptors), 2)
    # It lets the first buffer go, and the third frame goes into it.
    compositor.event(FIRST_POOL + 1, 0)
    frame.set_pixel(0, 0, Color(7, 8, 9))
    window.present(frame)
    requests = compositor.requests()
    assert_equal(len(requests), 3)
    _same(requests[0], _message(SURFACE, 1, FIRST_POOL + 1, 0, 0))
    var third: List[UInt8] = [9, 8, 7, 255]
    _same(compositor.stored(compositor.descriptors[0], 0), third)
    with assert_raises(contains="does not fit"):
        window.present(Framebuffer(9, 6, Color(0, 0, 0)))
    with assert_raises(contains="does not fit"):
        window.present(Framebuffer(8, 7, Color(0, 0, 0)))
    window.close()
    with assert_raises(contains="closed"):
        window.present(frame)
    with assert_raises(contains="closed"):
        _ = window.poll(_zero())
    with assert_raises(contains="closed"):
        window.resize(4, 4)
    compositor.close()


def test_a_resize_makes_new_buffers() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    # Nothing to free before the first frame.
    window.resize(8, 6)
    assert_equal(len(compositor.requests()), 0)
    window.present(Framebuffer(8, 6, Color(1, 2, 3)))
    window.present(Framebuffer(8, 6, Color(1, 2, 3)))
    _ = compositor.requests()
    window.resize(4, 2)
    assert_equal(window.width, 4)
    assert_equal(window.height, 2)
    var requests = compositor.requests()
    assert_equal(len(requests), 4)
    # Each buffer is destroyed, then its pool.
    _same(requests[0], _message(FIRST_POOL + 1, 0))
    _same(requests[1], _message(FIRST_POOL, 1))
    _same(requests[2], _message(FIRST_POOL + 3, 0))
    _same(requests[3], _message(FIRST_POOL + 2, 1))
    # A buffer that is gone can still be let go.
    compositor.event(FIRST_POOL + 3, 0)
    window.present(Framebuffer(4, 2, Color(1, 2, 3)))
    requests = compositor.requests()
    _same(requests[0], _message(SHM, 0, FIRST_POOL + 4, 32))
    _same(
        requests[1], _message(FIRST_POOL + 4, 0, FIRST_POOL + 5, 0, 4, 2, 16, 1)
    )
    with assert_raises(contains="must be positive"):
        window.resize(0, 4)
    with assert_raises(contains="must be positive"):
        window.resize(4, 0)
    with assert_raises(contains="Wayland buffer"):
        window.resize(30000, 30000)
    window.close()
    compositor.close()


def test_a_frame_needs_a_folder_for_its_file() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    var folder = getenv("XDG_RUNTIME_DIR", "")
    _ = setenv("XDG_RUNTIME_DIR", temporary_path("threemojo-no-such-folder"))
    with assert_raises(contains="cannot make a file"):
        window.present(Framebuffer(8, 6, Color(1, 2, 3)))
    # With no folder named, the file is made in `/tmp`.
    _ = setenv("XDG_RUNTIME_DIR", "")
    window.present(Framebuffer(8, 6, Color(1, 2, 3)))
    _ = setenv("XDG_RUNTIME_DIR", folder)
    window.close()
    compositor.close()


def test_a_compositor_that_leaves_ends_a_frame() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    compositor.hang_up()
    with assert_raises(contains="closed the connection"):
        window.present(Framebuffer(8, 6, Color(1, 2, 3)))
    with assert_raises(contains="closed the connection"):
        _ = window.poll(_zero())
    window.close()
    compositor.close()


# --- input ---------------------------------------------------------------------


def test_the_pointer_becomes_input_events() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    # It enters at (3, 4): nothing to report yet.
    compositor.event(POINTER, 0, 1, SURFACE, _fixed(3), _fixed(4))
    assert_equal(len(window.poll(_zero())), 0)
    compositor.event(POINTER, 2, 100, _fixed(5) + 128, _fixed(6))
    compositor.event(POINTER, 3, 2, 100, 0x110, 1)
    compositor.event(POINTER, 2, 100, _fixed(7), _fixed(6))
    compositor.event(POINTER, 3, 3, 100, 0x110, 0)
    compositor.event(POINTER, 3, 4, 100, 0x111, 1)
    compositor.event(POINTER, 3, 5, 100, 0x112, 1)
    compositor.event(POINTER, 2, 100, _fixed(-2), _fixed(1))
    compositor.event(POINTER, 3, 6, 100, 0x112, 0)
    compositor.event(POINTER, 2, 100, _fixed(1), _fixed(1))
    # A button this port has no name for, and the pointer leaving.
    compositor.event(POINTER, 3, 7, 100, 0x113, 1)
    compositor.event(POINTER, 1, 8, SURFACE)
    var events = window.poll(_zero())
    assert_equal(len(events), 9)
    assert_true(events[0].kind == POINTER_MOVE)
    assert_true(events[0].button == NO_BUTTON)
    assert_equal(events[0].x, 5)
    assert_equal(events[0].y, 6)
    assert_true(events[1].kind == POINTER_DOWN)
    assert_true(events[1].button == PRIMARY)
    assert_equal(events[1].x, 5)
    assert_true(events[2].kind == POINTER_MOVE)
    assert_true(events[2].button == PRIMARY)
    assert_equal(events[2].x, 7)
    assert_true(events[3].kind == POINTER_UP)
    assert_true(events[3].button == PRIMARY)
    assert_true(events[4].kind == POINTER_DOWN)
    assert_true(events[4].button == SECONDARY)
    assert_true(events[5].button == MIDDLE)
    # The first button held is the one a move names, and a place left of
    # the window is negative.
    assert_true(events[6].kind == POINTER_MOVE)
    assert_true(events[6].button == MIDDLE)
    assert_equal(events[6].x, -2)
    assert_true(events[7].kind == POINTER_UP)
    assert_true(events[8].button == SECONDARY)
    window.close()
    compositor.close()


def test_the_wheel_becomes_notches() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    compositor.event(POINTER, 0, 1, SURFACE, _fixed(3), _fixed(4))
    # Axis zero is the wheel: down is toward the user.
    compositor.event(POINTER, 4, 100, 0, _fixed(10))
    compositor.event(POINTER, 4, 100, 0, _fixed(-10))
    # No movement, and the sideways axis, are not notches.
    compositor.event(POINTER, 4, 100, 0, 0)
    compositor.event(POINTER, 4, 100, 1, _fixed(10))
    var events = window.poll(_zero())
    assert_equal(len(events), 2)
    assert_true(events[0].kind == WHEEL)
    assert_equal(events[0].wheel, 1)
    assert_equal(events[0].x, 3)
    assert_equal(events[0].y, 4)
    assert_equal(events[1].wheel, -1)
    window.close()
    compositor.close()


def test_the_keyboard_becomes_key_events() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    # The keymap comes as a file, which the window closes unread.
    var lib = OwnedDLHandle()
    var name = temporary_path("threemojo-wayland-keymap")
    _ = run("printf keymap > '" + name + "'")
    var path = name
    var keymap = lib.call["open", c_int](
        Int(path.as_c_string_span().ptr()), c_int(0)
    )
    _ = path^
    assert_true(keymap >= 0)
    compositor.send(_message(KEYBOARD, 0, 1, 6), Int(keymap))
    _ = lib.call["close", c_int](keymap)
    _ = run("rm -f '" + name + "'")
    # It enters, with no keys held: an empty array.
    compositor.event(KEYBOARD, 1, 1, SURFACE, 0)
    # A key repeats only after a long time here.
    compositor.event(KEYBOARD, 5, 25, 60000)
    compositor.event(KEYBOARD, 3, 2, 100, CODE_Q, 1)
    compositor.event(KEYBOARD, 3, 3, 100, CODE_Q, 0)
    # Shift and Ctrl held, then Ctrl+C.
    compositor.event(KEYBOARD, 4, 4, 1 | 4, 0, 0, 0)
    compositor.event(KEYBOARD, 3, 5, 100, CODE_C, 1)
    compositor.event(KEYBOARD, 4, 6, 8, 0, 0, 0)
    compositor.event(KEYBOARD, 3, 7, 100, CODE_UP, 1)
    # A modifier is no key.
    compositor.event(KEYBOARD, 3, 8, 100, CODE_LEFT_SHIFT, 1)
    var events = window.poll(_zero())
    assert_equal(len(events), 4)
    assert_true(events[0].kind == KEY_DOWN)
    assert_true(events[0].key == Key(113))
    assert_false(events[0].shift)
    assert_true(events[1].kind == KEY_UP)
    assert_true(events[1].key == Key(113))
    assert_true(events[2].key == Key(3))
    assert_true(events[2].shift and events[2].ctrl)
    assert_false(events[2].alt)
    assert_true(events[3].key == ARROW_UP)
    assert_true(events[3].alt)
    assert_false(events[3].ctrl)
    # The modifiers reach the pointer and a finger too.
    compositor.event(POINTER, 2, 100, _fixed(1), _fixed(1))
    compositor.event(TOUCH, 0, 9, 100, SURFACE, 0, _fixed(2), _fixed(2))
    events = window.poll(_zero())
    assert_true(events[0].alt)
    assert_true(events[1].alt)
    window.close()
    compositor.close()


def test_a_held_key_repeats_at_the_compositors_rate() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    # Fifty times a second, after 30 milliseconds.
    compositor.event(KEYBOARD, 5, 50, 30)
    compositor.event(KEYBOARD, 3, 1, 100, CODE_A, 1)
    var events = window.poll(_zero())
    assert_equal(len(events), 1)
    assert_true(events[0].key == Key(97))
    # The wait ends when the key repeats, not after the whole second.
    var start = perf_counter_ns()
    events = window.poll(Duration(1.0, SECOND))
    assert_true(perf_counter_ns() - start < 900000000)
    assert_equal(len(events), 1)
    assert_true(events[0].kind == KEY_DOWN)
    assert_true(events[0].key == Key(97))
    # Not again at once: the next repeat is 20 milliseconds away.
    assert_equal(len(window.poll(_zero())), 0)
    # Another key takes over, and the release of the first one does not
    # stop it.
    compositor.event(KEYBOARD, 5, 50, 0)
    compositor.event(KEYBOARD, 3, 2, 100, CODE_Q, 1)
    compositor.event(KEYBOARD, 3, 3, 100, CODE_A, 0)
    events = window.poll(_zero())
    assert_equal(len(events), 3)
    assert_true(events[0].key == Key(113))
    assert_true(events[1].kind == KEY_UP)
    assert_true(events[2].kind == KEY_DOWN)
    assert_true(events[2].key == Key(113))
    # A rate of zero turns the repeat off.
    compositor.event(KEYBOARD, 5, 0, 0)
    assert_equal(len(window.poll(Duration(40.0, MILLISECOND))), 0)
    # The window loses the keyboard: nothing repeats after.
    compositor.event(KEYBOARD, 5, 50, 0)
    compositor.event(KEYBOARD, 2, 4, SURFACE)
    assert_equal(len(window.poll(Duration(40.0, MILLISECOND))), 0)
    # The release of the held key stops it too.
    compositor.event(KEYBOARD, 3, 5, 100, CODE_A, 1)
    compositor.event(KEYBOARD, 3, 6, 100, CODE_A, 0)
    events = window.poll(_zero())
    assert_equal(len(events), 2)
    assert_equal(len(window.poll(Duration(40.0, MILLISECOND))), 0)
    window.close()
    compositor.close()


def test_fingers_become_touch_events() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    compositor.event(TOUCH, 0, 1, 100, SURFACE, 0, _fixed(2), _fixed(3))
    compositor.event(TOUCH, 0, 2, 100, SURFACE, 5, _fixed(6), _fixed(7))
    compositor.event(TOUCH, 2, 100, 5, _fixed(8), _fixed(9))
    compositor.event(TOUCH, 3)
    compositor.event(TOUCH, 1, 3, 100, 5)
    # A finger that is not down lifts, and a finger with no id goes down.
    compositor.event(TOUCH, 1, 4, 100, 9)
    compositor.event(TOUCH, 0, 5, 100, SURFACE, -1, _fixed(1), _fixed(1))
    var events = window.poll(_zero())
    assert_equal(len(events), 4)
    assert_true(events[0].kind == POINTER_DOWN)
    assert_true(events[0].pointer_type == TOUCH_POINTER)
    assert_true(events[0].pointer_id == PointerId(0))
    assert_true(events[0].button == PRIMARY)
    assert_equal(events[0].x, 2)
    assert_equal(events[0].y, 3)
    assert_true(events[1].pointer_id == PointerId(5))
    assert_true(events[2].kind == POINTER_MOVE)
    assert_equal(events[2].x, 8)
    assert_equal(events[2].y, 9)
    # A finger lifts where it last was.
    assert_true(events[3].kind == POINTER_UP)
    assert_true(events[3].pointer_id == PointerId(5))
    assert_equal(events[3].x, 8)
    assert_equal(events[3].y, 9)
    # The compositor takes the fingers away.
    compositor.event(TOUCH, 0, 6, 100, SURFACE, 3, _fixed(4), _fixed(4))
    compositor.event(TOUCH, 4)
    events = window.poll(_zero())
    assert_equal(len(events), 3)
    assert_true(events[1].kind == POINTER_CANCEL)
    assert_true(events[1].pointer_id == PointerId(0))
    assert_equal(events[1].x, 2)
    assert_true(events[2].kind == POINTER_CANCEL)
    assert_true(events[2].pointer_id == PointerId(3))
    # With no finger down, a cancel and a lift say nothing.
    compositor.event(TOUCH, 4)
    compositor.event(TOUCH, 1, 7, 100, 0)
    assert_equal(len(window.poll(_zero())), 0)
    window.close()
    compositor.close()


def test_the_window_hears_its_size_and_a_request_to_close() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    # The size it has, no size, and half a size say nothing.
    compositor.event(TOPLEVEL, 0, 8, 6, 0)
    compositor.event(TOPLEVEL, 0, 0, 0, 0)
    compositor.event(TOPLEVEL, 0, 9, 0, 0)
    compositor.event(TOPLEVEL, 0, 0, 9, 0)
    assert_equal(len(window.poll(_zero())), 0)
    compositor.event(TOPLEVEL, 0, 20, 6, 0)
    compositor.event(TOPLEVEL, 0, 8, 10, 0)
    # The compositor's bounds are no size.
    compositor.event(TOPLEVEL, 2, 640, 480)
    compositor.event(XDG_SURFACE, 0, 91)
    var events = window.poll(_zero())
    assert_equal(len(events), 2)
    assert_true(events[0].kind == RESIZE)
    assert_equal(events[0].x, 20)
    assert_equal(events[0].y, 6)
    assert_equal(events[1].x, 8)
    assert_equal(events[1].y, 10)
    # The window acknowledges the size and commits.
    var requests = compositor.requests()
    assert_equal(len(requests), 2)
    _same(requests[0], _message(XDG_SURFACE, 4, 91))
    _same(requests[1], _message(SURFACE, 6))
    assert_false(window.close_requested)
    compositor.event(TOPLEVEL, 1)
    _ = window.poll(_zero())
    assert_true(window.close_requested)
    window.close()
    compositor.close()


def test_the_window_answers_a_ping_and_ignores_what_it_does_not_use() raises:
    var compositor = Compositor()
    var window = _open(compositor, capabilities=0)
    compositor.event(WM_BASE, 0, 4242)
    # A deleted id, a removed global, a pixel format, the seat's name, and
    # an object the window never made.
    compositor.event(1, 1, CALLBACK)
    compositor.event(REGISTRY, 1, 6)
    compositor.event(SHM, 0, 1)
    var seat_name = WireMessage(SEAT, 1)
    seat_name.text("seat0")
    compositor.send(seat_name.finish())
    compositor.event(4000, 0, 1)
    assert_equal(len(window.poll(_zero())), 0)
    var requests = compositor.requests()
    assert_equal(len(requests), 1)
    _same(requests[0], _message(WM_BASE, 3, 4242))
    # The seat had nothing. A pointer comes, then a keyboard, and the
    # pointer is not asked for twice.
    compositor.event(SEAT, 0, 1)
    compositor.event(SEAT, 0, 3)
    compositor.event(SEAT, 0, 7)
    compositor.event(SEAT, 0, 7)
    _ = window.poll(_zero())
    requests = compositor.requests()
    assert_equal(len(requests), 3)
    _same(requests[0], _message(SEAT, 0, POINTER))
    _same(requests[1], _message(SEAT, 1, KEYBOARD))
    _same(requests[2], _message(SEAT, 2, TOUCH))
    window.close()
    compositor.close()


def test_an_event_cut_short_reads_as_zeros() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    # A pointer motion with no arguments, a global with no name, and a
    # global whose interface is the empty string.
    compositor.event(POINTER, 2)
    compositor.event(REGISTRY, 0, 9)
    compositor.global_(9, "", 1)
    var cut = WireMessage(REGISTRY, 0)
    cut.word(9)
    cut.word(40)
    compositor.send(cut.finish())
    var events = window.poll(_zero())
    assert_equal(len(events), 1)
    assert_equal(events[0].x, 0)
    assert_equal(events[0].y, 0)
    window.close()
    compositor.close()


def test_a_message_can_come_in_two_parts() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    var whole = _message(POINTER, 2, 100, _fixed(5), _fixed(6))
    var head = List[UInt8]()
    var tail = List[UInt8]()
    for index in range(len(whole)):
        if index < 6:
            head.append(whole[index])
        else:
            tail.append(whole[index])
    compositor.send(head)
    assert_equal(len(window.poll(_zero())), 0)
    # The size is known, and the arguments are still to come.
    var middle = List[UInt8]()
    middle.append(tail[0])
    middle.append(tail[1])
    middle.append(tail[2])
    compositor.send(middle)
    assert_equal(len(window.poll(_zero())), 0)
    var rest = List[UInt8]()
    for index in range(3, len(tail)):
        rest.append(tail[index])
    compositor.send(rest)
    var events = window.poll(_zero())
    assert_equal(len(events), 1)
    assert_equal(events[0].x, 5)
    window.close()
    compositor.close()


def test_events_heard_while_drawing_wait_for_the_next_poll() raises:
    var compositor = Compositor()
    var window = _open(compositor)
    compositor.event(POINTER, 2, 100, _fixed(5), _fixed(6))
    window.present(Framebuffer(8, 6, Color(1, 2, 3)))
    # The event is ready, so the poll does not wait.
    var start = perf_counter_ns()
    var events = window.poll(Duration(3.0, SECOND))
    assert_true(perf_counter_ns() - start < 2000000000)
    assert_equal(len(events), 1)
    # Nothing waiting: the poll times out empty.
    assert_equal(len(window.poll(Duration(5.0, MILLISECOND))), 0)
    with assert_raises(contains="negative"):
        _ = window.poll(Duration(-1.0, SECOND))
    with assert_raises(contains="finite"):
        _ = window.poll(Duration(inf[DType.float32](), SECOND))
    window.close()
    compositor.close()


def _drop_open(mut compositor: Compositor) raises:
    """Open a window and let it go out of scope open.

    Args:
        compositor: The compositor.

    Raises:
        Error: If the window is refused.
    """
    var window = _open(compositor)
    assert_true(window.is_open)


def test_a_window_dropped_open_closes_itself() raises:
    var compositor = Compositor()
    _drop_open(compositor)
    # The compositor reads the end of the stream.
    var byte = List[UInt8](length=1, fill=0)
    var count = compositor.lib.call["read", Int](
        c_int(compositor.fd), Int(byte.unsafe_ptr()), 1
    )
    assert_equal(count, 0)
    compositor.close()


# --- a real compositor ---------------------------------------------------------


def _installed(program: String) raises -> Bool:
    """Return whether a program is on the path.

    Args:
        program: Its name.

    Returns:
        Whether the shell finds it.

    Raises:
        Error: If the shell cannot run.
    """
    return (
        run("command -v " + program + " >/dev/null 2>&1 && echo yes") == "yes"
    )


def test_a_window_shows_a_frame_on_a_real_compositor() raises:
    if not (_installed("weston") and _installed("weston-screenshooter")):
        print("    weston is not installed: the real compositor is skipped")
        return
    var folder = _in_session("threemojo-weston")
    var saved = getenv("XDG_RUNTIME_DIR", "")
    var pid = run(
        "mkdir -m 700 -p '"
        + folder
        + "' && cd '"
        + folder
        + "' && XDG_RUNTIME_DIR='"
        + folder
        + "' weston --backend=headless --renderer=pixman"
        + " --socket=threemojo --width=64 --height=48 --shell=kiosk"
        + " --debug --idle-time=0 >weston.log 2>&1 & p=$!;"
        + " for i in $(seq 80); do [ -S '"
        + folder
        + "/threemojo' ] && break; sleep 0.05; done; echo $p"
    )
    _ = setenv("XDG_RUNTIME_DIR", folder)
    var window = WaylandWindow(64, 48, "ThreeMojo", "threemojo")
    var frame = Framebuffer(64, 48, Color(200, 100, 50))
    frame.set_pixel(3, 2, Color(255, 255, 255))
    frame.set_pixel(10, 5, Color(0, 0, 255))
    # The compositor lets a buffer go when it shows the next one, so two
    # buffers take turns however many frames there are.
    for _ in range(6):
        window.present(frame)
        _ = window.poll(Duration(50.0, MILLISECOND))
    assert_true(len(window._buffers) <= 3)
    var png = run(
        "cd '"
        + folder
        + "' && WAYLAND_DISPLAY=threemojo weston-screenshooter"
        + " >/dev/null 2>&1; ls wayland-screenshot-*.png"
    )
    var shot = decode(Path(folder + "/" + png).read_bytes())
    assert_equal(shot.width, 64)
    assert_equal(shot.height, 48)
    var back = shot.get_pixel(0, 0)
    assert_true(back.r == 200 and back.g == 100 and back.b == 50)
    var white = shot.get_pixel(3, 2)
    assert_true(white.r == 255 and white.g == 255 and white.b == 255)
    var blue = shot.get_pixel(10, 5)
    assert_true(blue.r == 0 and blue.g == 0 and blue.b == 255)
    window.close()
    _ = setenv("XDG_RUNTIME_DIR", saved)
    _ = run("kill " + pid + "; rm -rf '" + folder + "'")


def main() raises:
    with TestScratch():
        # The session's folder, where a display has its socket and a
        # frame has its file. A socket's path holds at most 103 bytes, and
        # a test root in macOS's TMPDIR is too long for one. So the folder
        # is a short one in /tmp, as a real session's is in /run/user. A
        # socket path is a protocol path, not a test fixture.
        var runtime = mkdtemp(prefix="threemojo-wl-", dir=String("/tmp"))
        _ = setenv("XDG_RUNTIME_DIR", runtime)
        try:
            TestSuite.discover_tests[__functions_in_module()]().run()
        finally:
            _ = run("rm -rf '" + runtime + "'")
