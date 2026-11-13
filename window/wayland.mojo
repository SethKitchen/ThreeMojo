# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A native window on Wayland: frames at full resolution, keys, the
pointer, touch and resizes.

three.js draws into a canvas in a browser window. On a Linux desktop the
window system is Wayland, or X11 through it. A Wayland client and its
compositor talk over a Unix socket, in messages of 32-bit words. This
module speaks that protocol itself, with the C library's socket calls. So
the library still builds and runs with nothing but the standard library,
and a machine without Wayland fails only when it asks for a window.
`TerminalWindow` stays the default.

The window binds four globals of the compositor: `wl_compositor`, `wl_shm`
and `xdg_wm_base`, which it needs, and `wl_seat` for input. It asks
`zxdg_decoration_manager_v1`, when the compositor has it, for a title bar
that the compositor draws. A frame is a `wl_shm` buffer of 32 bits a
pixel, blue first: `XRGB8888`, which every compositor takes. The buffer is
a file the compositor maps. The window writes each frame into the file and
keeps a buffer until the compositor releases it, so two or three buffers
take turns.

A key arrives as the code of its place on the keyboard. The window names
it as a US keyboard labels that place, and does not read the keymap that
the compositor sends. A compositor sends a key once, so the window repeats
a held key itself, at the rate the compositor gives.

The structures of `sendmsg` and `recvmsg` are written at their offsets on
a 64-bit system: Linux's, which is where Wayland runs, or the BSD layout
that macOS has. The window ignores the `SIGPIPE` signal for the program,
as programs that write to sockets do. A compositor that left is then an
error, and not the end of the program.
"""

from core.binary import (
    append_little_endian,
    little_endian_i32,
    little_endian_u32,
    little_endian_uint,
    store_little_endian,
)
from controls.input import (
    InputEvent,
    InputKind,
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
    PointerButton,
    PointerId,
    RESIZE,
    SECONDARY,
    WHEEL,
    touch_event,
)
from core.ordinal import ordinal_valid
from render.framebuffer import Framebuffer
from std.ffi import OwnedDLHandle, c_int
from std.os import getenv
from std.sys import CompilationTarget
from std.time import perf_counter_ns
from units.si import Duration, SECOND
from window.poll_timeout import poll_milliseconds
from window.present import (
    require_native_window_size,
    require_open,
    require_presented_frame,
)
from window.x11 import key_of

# The socket's family and type: `AF_UNIX` and `SOCK_STREAM`.
comptime AF_UNIX = 1
comptime SOCK_STREAM = 1
comptime POLLIN = 1
# `SIGPIPE`, and `SIG_IGN`.
comptime BROKEN_PIPE_SIGNAL = 13
comptime IGNORE_SIGNAL = 1
# The longest socket path both layouts of `sockaddr_un` hold: macOS has
# 104 bytes for the path and its end, and Linux has 108.
comptime SOCKET_PATH_MAX = 103
# `struct msghdr`: the buffers at 16, their count at 24, the control data
# at 32 and its length at 40. Linux's is 56 bytes. The BSD one is 48, with
# a count and a length of 32 bits at the same places.
comptime MESSAGE_HEADER_BYTES = 56
# `SCM_RIGHTS`: control data that carries descriptors. Its level,
# `SOL_SOCKET`, is 1 on Linux and 0xFFFF in the BSD layout.
comptime SCM_RIGHTS = 1
comptime CONTROL_BYTES = 256
comptime READ_BYTES = 4096
# A message is an object, then its size in the high half of a word and its
# opcode in the low half.
comptime HEADER_BYTES = 8
# `wl_shm`'s `XRGB8888`.
comptime FORMAT_XRGB8888 = 1
# `wl_seat`'s capabilities.
comptime CAPABILITY_POINTER = 1
comptime CAPABILITY_KEYBOARD = 2
comptime CAPABILITY_TOUCH = 4
# The version of `wl_seat` the window speaks: the last one before a pointer
# sends its events in frames, and the first whose keyboard gives its repeat
# rate.
comptime SEAT_VERSION = 4
# Linux's codes of the three buttons: `BTN_LEFT`, `BTN_RIGHT`, `BTN_MIDDLE`.
comptime BUTTON_LEFT = 0x110
comptime BUTTON_RIGHT = 0x111
comptime BUTTON_MIDDLE = 0x112
# The modifier bits every XKB keymap gives Shift, Control and Alt.
comptime SHIFT_MASK = 1
comptime CONTROL_MASK = 4
comptime ALT_MASK = 8
# `zxdg_toplevel_decoration_v1`'s mode for a title bar the compositor draws.
comptime SERVER_SIDE = 2
# The repeat of a held key until the compositor says: a key repeats 25
# times a second after 600 milliseconds, as libwayland's clients assume.
comptime DEFAULT_REPEAT_RATE = 25
comptime DEFAULT_REPEAT_DELAY = 600
# The largest buffer `wl_shm` can describe: its sizes are signed 32-bit.
comptime BUFFER_MAX = 2147483647
# What a US keyboard types at Linux's key codes 1 to 53, unshifted. A
# space is a key with no character here: a modifier.
comptime KEY_ROWS = (
    "\x1b1234567890-=\x08\tqwertyuiop[]\r asdfghjkl;'` \\zxcvbnm,./"
)
comptime KEY_SPACE = 57
comptime KEY_UP_ARROW = 103
comptime KEY_LEFT_ARROW = 105
comptime KEY_RIGHT_ARROW = 106
comptime KEY_DOWN_ARROW = 108


@fieldwise_init
struct WaylandSocket(Equatable, ImplicitlyCopyable, Writable):
    """A connected socket to a compositor, as a type rather than a bare
    int. Its value is the socket's file descriptor."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this can be a file descriptor.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct WaylandInterface(Equatable, ImplicitlyCopyable, Writable):
    """Which interface an object of the connection has, as a type rather
    than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the interfaces the window speaks,
        or none.

        Returns:
            Whether the value names an interface.
        """
        return ordinal_valid(self.value, 12)


# An object the window does not listen to.
comptime NO_INTERFACE = WaylandInterface(0)
comptime WL_DISPLAY = WaylandInterface(1)
comptime WL_REGISTRY = WaylandInterface(2)
comptime WL_CALLBACK = WaylandInterface(3)
comptime WL_SEAT = WaylandInterface(4)
comptime WL_POINTER = WaylandInterface(5)
comptime WL_KEYBOARD = WaylandInterface(6)
comptime WL_TOUCH = WaylandInterface(7)
comptime WL_BUFFER = WaylandInterface(8)
comptime XDG_WM_BASE = WaylandInterface(9)
comptime XDG_SURFACE = WaylandInterface(10)
comptime XDG_TOPLEVEL = WaylandInterface(11)
# `wl_compositor`, `wl_shm`, a pool, a surface and the decoration objects:
# the window sends to them and hears nothing it needs.
comptime SILENT = WaylandInterface(12)


def is_bsd() -> Bool:
    """Return whether the program is built for a system with the BSD
    socket structures, which is every system here but Linux.

    Returns:
        False on Linux, True on macOS.
    """
    return not CompilationTarget.is_linux()


def require_io(ok: Bool, what: String) raises:
    """Refuse the result of a C library call that failed.

    Nothing. The call returns when `ok` is true.

    Args:
        ok: Whether the call did what it was asked.
        what: What failed, the words after `Wayland: `.

    Raises:
        Error: If `ok` is false.
    """
    if not ok:
        raise Error("Wayland: " + what)


def socket_path(display: String, runtime: String) raises -> String:
    """Return the path of a compositor's socket, as libwayland finds it.

    Args:
        display: The display's name, as `WAYLAND_DISPLAY` names one. A name
            that starts with `/` is the path itself. Empty is `wayland-0`.
        runtime: The folder of the session's sockets, `XDG_RUNTIME_DIR`.

    Returns:
        The path.

    Raises:
        Error: If the name is relative and there is no runtime folder, or
            the path is longer than a socket address holds.
    """
    var name = display if display != "" else String("wayland-0")
    var path = name
    if not name.startswith("/"):
        if runtime == "":
            raise Error("XDG_RUNTIME_DIR is not set, so Wayland has no socket")
        path = runtime + "/" + name
    require_socket_path(path)
    return path


def require_socket_path(path: String) raises:
    """Refuse a socket path that a socket address cannot hold.

    Nothing. The call returns when the path fits.

    Args:
        path: The socket's path.

    Raises:
        Error: If the path is longer than 103 bytes.
    """
    if path.byte_length() > SOCKET_PATH_MAX:
        raise Error("The Wayland socket's path is too long: ", path)


def socket_address(path: String, bsd: Bool) raises -> List[UInt8]:
    """Return the `sockaddr_un` of a path.

    Linux's is the family in 16 bits, then the path and its end. The BSD
    one is the address's length in a byte, the family in a byte, then the
    path and its end.

    Args:
        path: The socket's path, of at most 103 bytes.
        bsd: Whether to use the BSD layout.

    Returns:
        The address, 106 bytes.

    Raises:
        Error: If the path is longer than 103 bytes.
    """
    require_socket_path(path)
    var address = List[UInt8](length=2 + SOCKET_PATH_MAX + 1, fill=0)
    address[0] = AF_UNIX
    if bsd:
        address[0] = UInt8(len(address))
        address[1] = AF_UNIX
    var at = 2
    for byte in path.as_bytes():
        address[at] = byte
        at += 1
    return address^


def descriptor_control(descriptor: Int, bsd: Bool) -> List[UInt8]:
    """Return the control data that sends one file descriptor: a
    `cmsghdr` of `SCM_RIGHTS` and the descriptor.

    Linux's header is a 64-bit length, a level and a type, and the data
    is padded to eight bytes. The BSD header is a 32-bit length, a level
    and a type.

    Args:
        descriptor: The file descriptor.
        bsd: Whether to use the BSD layout.

    Returns:
        The control data: 24 bytes on Linux, 16 in the BSD layout.
    """
    var control = List[UInt8]()
    if bsd:
        append_little_endian(control, 16, 4)
        append_little_endian(control, 0xFFFF, 4)
        append_little_endian(control, SCM_RIGHTS, 4)
        append_little_endian(control, descriptor, 4)
        return control^
    append_little_endian(control, 20, 8)
    append_little_endian(control, 1, 4)
    append_little_endian(control, SCM_RIGHTS, 4)
    append_little_endian(control, descriptor, 8)
    return control^


def control_descriptors(
    header: List[UInt8], control: List[UInt8], bsd: Bool
) -> List[Int]:
    """Return the file descriptors that came with a `recvmsg`.

    The socket asks for no other control data, so each piece of it holds
    descriptors.

    Args:
        header: The `msghdr` after the call. Its control length is 64
            bits on Linux and 32 in the BSD layout.
        control: The control data the call filled.
        bsd: Whether to use the BSD layout.

    Returns:
        The descriptors, in the order they were sent.
    """
    var width = 8
    var start = 16
    if bsd:
        width = 4
        start = 12
    var used = min(little_endian_uint(header, 40, width), len(control))
    var descriptors = List[Int]()
    var at = 0
    while at + start <= used:
        var length = little_endian_uint(control, at, width)
        var end = min(at + length, used)
        for offset in range(at + start, end - 3, 4):
            descriptors.append(little_endian_i32(control, offset))
        # A piece is padded to a whole word of the layout.
        at += max((length + width - 1) // width * width, start)
    return descriptors^


@fieldwise_init
struct Received(Movable):
    """What one `recvmsg` gave: how many bytes, the bytes, and the file
    descriptors that came with them."""

    var count: Int
    var bytes: List[UInt8]
    var descriptors: List[Int]


def send_message(
    libc: OwnedDLHandle,
    socket: WaylandSocket,
    bytes: List[UInt8],
    descriptor: Int,
    bsd: Bool,
) -> Int:
    """Write bytes to a socket with `sendmsg`, with a file descriptor if
    one is given.

    Args:
        libc: The C library.
        socket: The socket.
        bytes: The bytes.
        descriptor: A file descriptor to send with them, or -1.
        bsd: Whether to use the BSD layout.

    Returns:
        How many bytes the socket took, or -1.
    """
    var data = bytes.copy()
    var vector = List[UInt8](length=16, fill=0)
    store_little_endian(vector, 0, Int(data.unsafe_ptr()), 8)
    store_little_endian(vector, 8, len(data), 8)
    var header = List[UInt8](length=MESSAGE_HEADER_BYTES, fill=0)
    store_little_endian(header, 16, Int(vector.unsafe_ptr()), 8)
    store_little_endian(header, 24, 1, 8)
    var control = descriptor_control(descriptor, bsd)
    if descriptor >= 0:
        store_little_endian(header, 32, Int(control.unsafe_ptr()), 8)
        store_little_endian(header, 40, len(control), 8)
    var sent = libc.call["sendmsg", Int](
        c_int(socket.value), Int(header.unsafe_ptr()), c_int(0)
    )
    # An address does not keep its bytes alive: each buffer is dropped
    # only after the call that reads it.
    _ = data^
    _ = vector^
    _ = header^
    _ = control^
    return sent


def receive_message(
    libc: OwnedDLHandle, socket: WaylandSocket, bsd: Bool
) -> Received:
    """Read bytes from a socket with `recvmsg`, and the file descriptors
    that come with them. The call waits until the socket has bytes or its
    other end closed.

    Args:
        libc: The C library.
        socket: The socket.
        bsd: Whether to use the BSD layout.

    Returns:
        The bytes read, with a count of zero when the other end closed
        and a negative count for an error.
    """
    var data = List[UInt8](length=READ_BYTES, fill=0)
    var vector = List[UInt8](length=16, fill=0)
    store_little_endian(vector, 0, Int(data.unsafe_ptr()), 8)
    store_little_endian(vector, 8, len(data), 8)
    var control = List[UInt8](length=CONTROL_BYTES, fill=0)
    var header = List[UInt8](length=MESSAGE_HEADER_BYTES, fill=0)
    store_little_endian(header, 16, Int(vector.unsafe_ptr()), 8)
    store_little_endian(header, 24, 1, 8)
    store_little_endian(header, 32, Int(control.unsafe_ptr()), 8)
    store_little_endian(header, 40, len(control), 8)
    var count = libc.call["recvmsg", Int](
        c_int(socket.value), Int(header.unsafe_ptr()), c_int(0)
    )
    _ = vector^
    var descriptors = control_descriptors(header, control, bsd)
    var bytes = List[UInt8]()
    for index in range(count):
        bytes.append(data[index])
    return Received(count, bytes^, descriptors^)


def socket_ready(libc: OwnedDLHandle, socket: WaylandSocket, wait: Int) -> Bool:
    """Wait until a socket has something to read.

    Args:
        libc: The C library.
        socket: The socket.
        wait: How long to wait, in milliseconds.

    Returns:
        True if the socket has bytes or its other end closed, False if
        the wait ran out.
    """
    var request = List[Int32](length=2, fill=0)
    request[0] = Int32(socket.value)
    request[1] = Int32(POLLIN)
    var ready = libc.call["poll", c_int](
        Int(request.unsafe_ptr()), UInt(1), c_int(wait)
    )
    _ = request^
    return ready > 0


def connect_display(display: String = "") raises -> WaylandSocket:
    """Connect to a compositor.

    Args:
        display: The display's name, as `WAYLAND_DISPLAY` names one. Empty
            takes `WAYLAND_DISPLAY` from the environment, and `wayland-0`
            when that is not set.

    Returns:
        The connected socket.

    Raises:
        Error: If the socket has no path, or no compositor listens there.
    """
    var name = display if display != "" else getenv("WAYLAND_DISPLAY", "")
    var path = socket_path(name, getenv("XDG_RUNTIME_DIR", ""))
    # The address comes first: a path it refuses then leaves no socket open.
    var address = socket_address(path, is_bsd())
    var libc = OwnedDLHandle()
    var fd = libc.call["socket", c_int](
        c_int(AF_UNIX), c_int(SOCK_STREAM), c_int(0)
    )
    require_io(fd >= 0, "cannot make a socket")
    var result = libc.call["connect", c_int](
        fd, Int(address.unsafe_ptr()), UInt32(len(address))
    )
    # An address does not keep its bytes alive: the buffer is dropped only
    # after the call that reads it.
    _ = address^
    if result != 0:
        _ = libc.call["close", c_int](fd)
        raise Error("Could not connect to the Wayland display '", path, "'")
    return WaylandSocket(Int(fd))


def runtime_folder(value: String) -> String:
    """Return the folder a frame's file is made in.

    Args:
        value: `XDG_RUNTIME_DIR`, or empty when it is not set.

    Returns:
        That folder, or `/tmp` for an empty value.
    """
    if value == "":
        return String("/tmp")
    return value


def fixed_to_pixel(raw: Int) -> Int:
    """Return the pixel a Wayland fixed-point coordinate is in.

    Args:
        raw: The coordinate, in 256ths of a pixel, as the wire holds it.

    Returns:
        The pixel, rounded down.
    """
    return raw >> 8


def button_of(code: Int) -> PointerButton:
    """Return the pointer button a Linux button code names.

    Args:
        code: The code, from `wl_pointer`'s `button` event.

    Returns:
        The button, or `NO_BUTTON` for a code this port has no button for.
    """
    if code == BUTTON_LEFT:
        return PRIMARY
    if code == BUTTON_MIDDLE:
        return MIDDLE
    if code == BUTTON_RIGHT:
        return SECONDARY
    return NO_BUTTON


def held_button(buttons: Int) -> PointerButton:
    """Return the first button that a set of held buttons holds.

    Args:
        buttons: One bit for each button held, at the button's number:
            bit zero for the primary button.

    Returns:
        The primary button, else the middle, else the secondary, or
        `NO_BUTTON` for an empty set.
    """
    if (buttons & 1) != 0:
        return PRIMARY
    if (buttons & 2) != 0:
        return MIDDLE
    if (buttons & 4) != 0:
        return SECONDARY
    return NO_BUTTON


def key_symbol(code: Int) -> Int:
    """Return the X key symbol of a Linux key code on a US keyboard.

    Args:
        code: The key code, from `wl_keyboard`'s `key` event.

    Returns:
        The symbol `window.x11.key_of` reads: an ASCII character, an
        arrow, Escape, Return, Tab or Backspace. Zero for a key this port
        does not name.
    """
    if code == KEY_UP_ARROW:
        return 0xFF52
    if code == KEY_DOWN_ARROW:
        return 0xFF54
    if code == KEY_LEFT_ARROW:
        return 0xFF51
    if code == KEY_RIGHT_ARROW:
        return 0xFF53
    if code == KEY_SPACE:
        return 0x20
    if code < 1 or code > KEY_ROWS.byte_length():
        return 0
    var character = Int(KEY_ROWS.as_bytes()[code - 1])
    if character == 0x20:
        return 0
    # Escape, Backspace, Tab and Return have symbols of their own.
    if character < 0x20:
        return 0xFF00 | character
    return character


def key_of_code(code: Int, control: Bool) -> Key:
    """Return the key a Linux key code names, as the terminal decoder
    names it. The key is read by its place, as a US keyboard labels it.

    Args:
        code: The key code, from `wl_keyboard`'s `key` event.
        control: Whether Ctrl is held. With Ctrl, a letter is its control
            code, as a terminal sends it.

    Returns:
        The key, or `NO_KEY` for a key this port does not name.
    """
    return key_of(key_symbol(code), control)


struct WireMessage(Movable):
    """One message of the Wayland protocol, as it is built.

    A message is its object, a word with its size and its opcode, and its
    arguments in 32-bit words, least significant byte first.
    """

    var bytes: List[UInt8]

    def __init__(out self, object: Int, opcode: Int):
        """Start a message to an object.

        Args:
            object: The object's id.
            opcode: The request's number in the object's interface.
        """
        self.bytes = List[UInt8]()
        append_little_endian(self.bytes, object, 4)
        append_little_endian(self.bytes, opcode, 4)

    def word(mut self, value: Int):
        """Add an integer, an object or a new id.

        Args:
            value: The value. A negative integer is stored in two's
                complement.
        """
        append_little_endian(self.bytes, value & 0xFFFFFFFF, 4)

    def text(mut self, value: String):
        """Add a string: its length with its end, its bytes, and zeros up
        to a whole word.

        Args:
            value: The string.
        """
        var length = value.byte_length() + 1
        append_little_endian(self.bytes, length, 4)
        for byte in value.as_bytes():
            self.bytes.append(byte)
        # At least the string's end is added.
        var zeros = (length + 3) // 4 * 4 - (length - 1)
        for _ in range(zeros):  # pragma: no branch
            self.bytes.append(0)

    def finish(mut self) -> List[UInt8]:
        """Return the message with its size written in.

        Returns:
            The bytes to send.
        """
        var opcode = little_endian_u32(self.bytes, 4)
        store_little_endian(self.bytes, 4, (len(self.bytes) << 16) | opcode, 4)
        return self.bytes.copy()


@fieldwise_init
struct _Buffer(ImplicitlyCopyable):
    """A frame the compositor can map: its `wl_buffer`, its pool, the file
    behind them, and whether the compositor still shows it."""

    var id: Int
    var pool: Int
    var fd: Int
    var busy: Bool


@fieldwise_init
struct _Touch(ImplicitlyCopyable):
    """A finger that is down, and the pixel it is on."""

    var id: Int
    var x: Int
    var y: Int


struct WaylandWindow(Movable):
    """A window from a Wayland compositor, showing frames of its size."""

    var width: Int
    var height: Int
    var is_open: Bool
    # True once the compositor asked the window to close.
    var close_requested: Bool
    var _libc: OwnedDLHandle
    var _fd: Int
    # The interface of each object, by its id, and the next free id.
    var _kinds: List[WaylandInterface]
    # The bytes read and not yet a whole message, and the events waiting
    # for `poll`.
    var _incoming: List[UInt8]
    var _events: List[InputEvent]
    # The registry's names and versions of the globals, -1 for none.
    var _compositor_name: Int
    var _shm_name: Int
    var _wm_base_name: Int
    var _seat_name: Int
    var _seat_version: Int
    var _decoration_name: Int
    # The objects the window made, zero for none.
    var _shm: Int
    var _wm_base: Int
    var _seat: Int
    var _surface: Int
    var _xdg_surface: Int
    var _pointer: Int
    var _keyboard: Int
    var _touch: Int
    # The last callback the compositor finished, and whether it gave the
    # window its first size.
    var _synced: Int
    var _configured: Bool
    var _buffers: List[_Buffer]
    var _pixels: List[UInt8]
    # Where the pointer is, the buttons held, and the modifiers held.
    var _pointer_x: Int
    var _pointer_y: Int
    var _buttons: Int
    var _shift: Bool
    var _ctrl: Bool
    var _alt: Bool
    # The key held, its code, and when it next repeats, in milliseconds.
    var _held: Key
    var _held_code: Int
    var _repeat_at: Int
    var _repeat_rate: Int
    var _repeat_delay: Int
    var _fingers: List[_Touch]

    def __init__(
        out self,
        width: Int,
        height: Int,
        title: String = "ThreeMojo",
        display: String = "",
    ) raises:
        """Open a window on a compositor.

        Args:
            width: The frame's width, in pixels.
            height: The frame's height, in pixels.
            title: The window's title.
            display: The Wayland display, as `WAYLAND_DISPLAY` names one.
                Empty takes `WAYLAND_DISPLAY` from the environment.

        Raises:
            Error: If the size is refused, no compositor listens on the
                display, or the compositor refuses the window. See the
                other constructor.
        """
        require_native_window_size(width, height)
        require_buffer_size(width, height)
        self = Self(width, height, title, connect_display(display))

    def __init__(
        out self,
        width: Int,
        height: Int,
        title: String,
        socket: WaylandSocket,
        timeout: Duration = Duration(5.0, SECOND),
    ) raises:
        """Open a window on a compositor that a socket is connected to.
        The window owns the socket once it accepts the size, the socket
        and the timeout, and closes it.

        Args:
            width: The frame's width, in pixels.
            height: The frame's height, in pixels.
            title: The window's title.
            socket: The connected socket.
            timeout: How long the compositor has to answer.

        Raises:
            Error: If the size is not positive, a side does not fit in a
                native integer, a frame does not fit in a Wayland buffer,
                the socket or the timeout is invalid, the compositor does
                not answer in time or reports an error, or it lacks
                `wl_compositor`, `wl_shm` or `xdg_wm_base`.
        """
        require_native_window_size(width, height)
        require_buffer_size(width, height)
        require_io(socket.is_valid(), "the socket is not a file descriptor")
        var wait = Int(poll_milliseconds(timeout))
        self.width = width
        self.height = height
        self.is_open = False
        self.close_requested = False
        self._libc = OwnedDLHandle()
        # A write to a compositor that left then fails, with no signal.
        _ = self._libc.call["signal", Int](
            c_int(BROKEN_PIPE_SIGNAL), Int(IGNORE_SIGNAL)
        )
        self._fd = socket.value
        self._kinds = [NO_INTERFACE, WL_DISPLAY]
        self._incoming = List[UInt8]()
        self._events = List[InputEvent]()
        self._compositor_name = -1
        self._shm_name = -1
        self._wm_base_name = -1
        self._seat_name = -1
        self._seat_version = 1
        self._decoration_name = -1
        self._shm = 0
        self._wm_base = 0
        self._seat = 0
        self._surface = 0
        self._xdg_surface = 0
        self._pointer = 0
        self._keyboard = 0
        self._touch = 0
        self._synced = 0
        self._configured = False
        self._buffers = List[_Buffer]()
        self._pixels = List[UInt8](length=width * height * 4, fill=0)
        self._pointer_x = 0
        self._pointer_y = 0
        self._buttons = 0
        self._shift = False
        self._ctrl = False
        self._alt = False
        self._held = NO_KEY
        self._held_code = 0
        self._repeat_at = 0
        self._repeat_rate = DEFAULT_REPEAT_RATE
        self._repeat_delay = DEFAULT_REPEAT_DELAY
        self._fingers = List[_Touch]()
        try:
            self._shake_hands(title, wait)
        except error:
            self._shut()
            raise error^
        self.is_open = True

    def __deinit__(deinit self):
        """Close the window if it is still open."""
        if self.is_open:
            self._shut()

    def _shut(mut self):
        """Close the socket and the files of the buffers. The compositor
        then frees everything the window made."""
        for buffer in self._buffers:
            _ = self._libc.call["close", c_int](c_int(buffer.fd))
        self._buffers.clear()
        _ = self._libc.call["close", c_int](c_int(self._fd))
        self.is_open = False

    def close(mut self):
        """Close the window. Closing a closed window does nothing."""
        if self.is_open:
            self._shut()

    # --- the connection ------------------------------------------------------

    def _new(mut self, kind: WaylandInterface) -> Int:
        """Take the next object id for an object the window makes.

        Args:
            kind: The object's interface.

        Returns:
            The id.
        """
        self._kinds.append(kind)
        return len(self._kinds) - 1

    def _send(mut self, mut message: WireMessage, descriptor: Int = -1) raises:
        """Send one message, with a file descriptor if it has one.

        Args:
            message: The message.
            descriptor: The descriptor a `fd` argument sends, or -1.

        Raises:
            Error: If the socket does not take the whole message.
        """
        var bytes = message.finish()
        var sent = send_message(
            self._libc, WaylandSocket(self._fd), bytes, descriptor, is_bsd()
        )
        require_io(
            sent == len(bytes), "the compositor's socket cannot be written"
        )

    def _fill(mut self, wait: Int) raises -> Bool:
        """Read what the compositor sent, after waiting for it.

        A file descriptor that comes with the bytes is closed: the only
        one a compositor sends is a keymap, which the window does not
        read.

        Args:
            wait: How long to wait for the first byte, in milliseconds.

        Returns:
            True if bytes arrived, False if the wait ran out.

        Raises:
            Error: If the compositor closed the connection.
        """
        var socket = WaylandSocket(self._fd)
        if not socket_ready(self._libc, socket, wait):
            return False
        var received = receive_message(self._libc, socket, is_bsd())
        for descriptor in received.descriptors:
            _ = self._libc.call["close", c_int](c_int(descriptor))
        require_io(received.count > 0, "the compositor closed the connection")
        # The count is positive here.
        for byte in received.bytes:  # pragma: no branch
            self._incoming.append(byte)
        return True

    def _next(mut self) raises -> Bool:
        """Take one whole message off the bytes read, and act on it.

        Returns:
            True if there was a whole message.

        Raises:
            Error: If the message is malformed, or it is an error the
                compositor reports.
        """
        if len(self._incoming) < HEADER_BYTES:
            return False
        var size = little_endian_u32(self._incoming, 4) >> 16
        require_io(
            size >= HEADER_BYTES and size % 4 == 0,
            "the compositor sent a malformed message",
        )
        if len(self._incoming) < size:
            return False
        # A message is at least its header.
        var message = List[UInt8](capacity=size)
        for index in range(size):  # pragma: no branch
            message.append(self._incoming[index])
        var rest = List[UInt8](capacity=len(self._incoming) - size)
        for index in range(size, len(self._incoming)):
            rest.append(self._incoming[index])
        self._incoming = rest^
        self._dispatch(message)
        return True

    def _drain(mut self) raises:
        """Act on every message that has arrived, without waiting.

        Raises:
            Error: If the compositor closed the connection, sent a
                malformed message or reports an error.
        """
        while True:
            while self._next():
                pass
            if not self._fill(0):
                return

    def _await(mut self, callback: Int, wait: Int) raises:
        """Act on messages until the compositor finishes a callback, or,
        for callback zero, until it gives the window its first size.

        A message after the awaited one stays unread, for later.

        Args:
            callback: The `wl_callback` of a `sync`, or zero.
            wait: How long the compositor has, in milliseconds.

        Raises:
            Error: If the time runs out, or a message is refused.
        """
        var start = _milliseconds()
        while not self._arrived(callback):
            if self._next():
                continue
            var left = wait - (_milliseconds() - start)
            require_io(
                left > 0 and self._fill(left),
                "the compositor did not answer in time",
            )

    def _arrived(self, callback: Int) -> Bool:
        """Return whether what `_await` waits for has come.

        Args:
            callback: The callback, or zero for the first size.

        Returns:
            Whether it has come.
        """
        if callback == 0:
            return self._configured
        return self._synced == callback

    def _shake_hands(mut self, title: String, wait: Int) raises:
        """Find the compositor's globals, and make the window.

        Args:
            title: The window's title.
            wait: How long the compositor has to answer each step, in
                milliseconds.

        Raises:
            Error: If the compositor does not answer in time, reports an
                error, or lacks a global the window needs.
        """
        var registry = self._new(WL_REGISTRY)
        var get_registry = WireMessage(1, 1)
        get_registry.word(registry)
        self._send(get_registry)
        var first = self._new(WL_CALLBACK)
        var sync = WireMessage(1, 0)
        sync.word(first)
        self._send(sync)
        self._await(first, wait)
        if (
            self._compositor_name < 0
            or self._shm_name < 0
            or self._wm_base_name < 0
        ):
            raise Error(
                "The Wayland compositor lacks wl_compositor, wl_shm or"
                + " xdg_wm_base"
            )
        var compositor = self._bind(
            registry, self._compositor_name, "wl_compositor", 1, SILENT
        )
        self._shm = self._bind(registry, self._shm_name, "wl_shm", 1, SILENT)
        self._wm_base = self._bind(
            registry, self._wm_base_name, "xdg_wm_base", 1, XDG_WM_BASE
        )
        if self._seat_name >= 0:
            self._seat = self._bind(
                registry,
                self._seat_name,
                "wl_seat",
                min(self._seat_version, SEAT_VERSION),
                WL_SEAT,
            )
        self._surface = self._new(SILENT)
        var create_surface = WireMessage(compositor, 0)
        create_surface.word(self._surface)
        self._send(create_surface)
        self._xdg_surface = self._new(XDG_SURFACE)
        var get_xdg_surface = WireMessage(self._wm_base, 2)
        get_xdg_surface.word(self._xdg_surface)
        get_xdg_surface.word(self._surface)
        self._send(get_xdg_surface)
        var toplevel = self._new(XDG_TOPLEVEL)
        var get_toplevel = WireMessage(self._xdg_surface, 1)
        get_toplevel.word(toplevel)
        self._send(get_toplevel)
        var set_title = WireMessage(toplevel, 2)
        set_title.text(title)
        self._send(set_title)
        if self._decoration_name >= 0:
            var manager = self._bind(
                registry,
                self._decoration_name,
                "zxdg_decoration_manager_v1",
                1,
                SILENT,
            )
            var decoration = self._new(SILENT)
            var get_decoration = WireMessage(manager, 1)
            get_decoration.word(decoration)
            get_decoration.word(toplevel)
            self._send(get_decoration)
            var set_mode = WireMessage(decoration, 1)
            set_mode.word(SERVER_SIDE)
            self._send(set_mode)
        # A first commit with no buffer asks the compositor for a size.
        self._commit()
        self._await(0, wait)

    def _bind(
        mut self,
        registry: Int,
        name: Int,
        interface: String,
        version: Int,
        kind: WaylandInterface,
    ) raises -> Int:
        """Bind a global of the compositor.

        Args:
            registry: The registry.
            name: The global's name in the registry.
            interface: The global's interface.
            version: The version the window speaks.
            kind: What the window listens to on the object.

        Returns:
            The new object's id.

        Raises:
            Error: If the socket cannot be written.
        """
        var id = self._new(kind)
        var bind = WireMessage(registry, 0)
        bind.word(name)
        bind.text(interface)
        bind.word(version)
        bind.word(id)
        self._send(bind)
        return id

    def _commit(mut self) raises:
        """Send `wl_surface.commit`.

        Raises:
            Error: If the socket cannot be written.
        """
        var commit = WireMessage(self._surface, 6)
        self._send(commit)

    # --- what the compositor says --------------------------------------------

    def _dispatch(mut self, message: List[UInt8]) raises:
        """Act on one message from the compositor.

        Args:
            message: The whole message.

        Raises:
            Error: If it is an error the compositor reports, or an answer
                cannot be sent.
        """
        var object = little_endian_u32(message, 0)
        var opcode = little_endian_u32(message, 4) & 0xFFFF
        var kind = NO_INTERFACE
        if object < len(self._kinds):
            kind = self._kinds[object]
        if kind == WL_DISPLAY:
            if opcode == 0:
                raise Error(
                    "The Wayland compositor reports an error: ",
                    _text(message, 2),
                )
        elif kind == WL_REGISTRY:
            if opcode == 0:
                self._global(message)
        elif kind == WL_CALLBACK:
            self._synced = object
        elif kind == XDG_WM_BASE:
            var pong = WireMessage(object, 3)
            pong.word(_word(message, 0))
            self._send(pong)
        elif kind == XDG_SURFACE:
            var ack = WireMessage(object, 4)
            ack.word(_word(message, 0))
            self._send(ack)
            self._commit()
            self._configured = True
        elif kind == XDG_TOPLEVEL:
            self._toplevel(opcode, message)
        elif kind == WL_SEAT:
            if opcode == 0:
                self._capabilities(_word(message, 0))
        elif kind == WL_POINTER:
            self._pointer_event(opcode, message)
        elif kind == WL_KEYBOARD:
            self._keyboard_event(opcode, message)
        elif kind == WL_TOUCH:
            self._touch_event(opcode, message)
        elif kind == WL_BUFFER:
            for index in range(len(self._buffers)):
                if self._buffers[index].id == object:
                    self._buffers[index].busy = False

    def _global(mut self, message: List[UInt8]):
        """Note a global the window uses. `wl_registry`'s `global`.

        Args:
            message: The event: a name, an interface and a version.
        """
        var name = _word(message, 0)
        var interface = _text(message, 1)
        # The version follows the string: its length, and its bytes up to
        # a whole word.
        var words = 2 + (_word(message, 1) + 3) // 4
        if interface == "wl_compositor":
            self._compositor_name = name
        elif interface == "wl_shm":
            self._shm_name = name
        elif interface == "xdg_wm_base":
            self._wm_base_name = name
        elif interface == "wl_seat":
            self._seat_name = name
            self._seat_version = _word(message, words)
        elif interface == "zxdg_decoration_manager_v1":
            self._decoration_name = name

    def _toplevel(mut self, opcode: Int, message: List[UInt8]):
        """Act on an event of the window itself. `xdg_toplevel`'s
        `configure` and `close`.

        A size of zero leaves the size to the window. A size the window
        already has is not reported.

        Args:
            opcode: The event's number.
            message: The event.
        """
        if opcode == 1:
            self.close_requested = True
            return
        if opcode != 0:
            return
        var width = _signed(message, 0)
        var height = _signed(message, 1)
        var same = width == self.width and height == self.height
        if width > 0 and height > 0 and not same:
            self._events.append(InputEvent(RESIZE, x=width, y=height))

    def _capabilities(mut self, capabilities: Int) raises:
        """Ask the seat for each device it has and the window has not.
        `wl_seat`'s `capabilities`.

        Args:
            capabilities: One bit for a pointer, a keyboard and a touch
                screen.

        Raises:
            Error: If the socket cannot be written.
        """
        if (capabilities & CAPABILITY_POINTER) != 0 and self._pointer == 0:
            self._pointer = self._device(0, WL_POINTER)
        if (capabilities & CAPABILITY_KEYBOARD) != 0 and self._keyboard == 0:
            self._keyboard = self._device(1, WL_KEYBOARD)
        if (capabilities & CAPABILITY_TOUCH) != 0 and self._touch == 0:
            self._touch = self._device(2, WL_TOUCH)

    def _device(mut self, opcode: Int, kind: WaylandInterface) raises -> Int:
        """Ask the seat for a pointer, a keyboard or a touch screen.

        Args:
            opcode: The seat's request for the device.
            kind: The device's interface.

        Returns:
            The new object's id.

        Raises:
            Error: If the socket cannot be written.
        """
        var id = self._new(kind)
        var get = WireMessage(self._seat, opcode)
        get.word(id)
        self._send(get)
        return id

    def _pointer_event(mut self, opcode: Int, message: List[UInt8]):
        """Turn an event of the pointer into input. `wl_pointer`'s
        `enter`, `motion`, `button` and `axis`.

        Args:
            opcode: The event's number.
            message: The event.
        """
        if opcode == 0:
            self._pointer_x = fixed_to_pixel(_signed(message, 2))
            self._pointer_y = fixed_to_pixel(_signed(message, 3))
        elif opcode == 2:
            self._pointer_x = fixed_to_pixel(_signed(message, 1))
            self._pointer_y = fixed_to_pixel(_signed(message, 2))
            self._events.append(
                self._at(POINTER_MOVE, held_button(self._buttons))
            )
        elif opcode == 3:
            var button = button_of(_word(message, 2))
            if button == NO_BUTTON:
                return
            if _word(message, 3) != 0:
                self._buttons |= 1 << button.value
                self._events.append(self._at(POINTER_DOWN, button))
            else:
                self._buttons &= ~(1 << button.value)
                self._events.append(self._at(POINTER_UP, button))
        elif opcode == 4:
            # Axis zero is the wheel. A positive value scrolls down, which
            # is a notch toward the user.
            var value = _signed(message, 2)
            if _word(message, 1) == 0 and value != 0:
                var wheel = self._at(WHEEL, NO_BUTTON)
                wheel.wheel = 1 if value > 0 else -1
                self._events.append(wheel)

    def _at(self, kind: InputKind, button: PointerButton) -> InputEvent:
        """Return an event where the pointer is, with the modifiers held.

        Args:
            kind: What happened.
            button: The button the event is about.

        Returns:
            The event.
        """
        return InputEvent(
            kind,
            button=button,
            x=self._pointer_x,
            y=self._pointer_y,
            shift=self._shift,
            alt=self._alt,
            ctrl=self._ctrl,
        )

    def _keyboard_event(mut self, opcode: Int, message: List[UInt8]):
        """Turn an event of the keyboard into input. `wl_keyboard`'s
        `leave`, `key`, `modifiers` and `repeat_info`.

        Args:
            opcode: The event's number.
            message: The event.
        """
        if opcode == 2:
            # The window lost the keyboard: nothing repeats.
            self._held = NO_KEY
        elif opcode == 3:
            var code = _word(message, 2)
            var key = key_of_code(code, self._ctrl)
            if key == NO_KEY:
                return
            if _word(message, 3) != 0:
                self._events.append(self._key(KEY_DOWN, key))
                self._held = key
                self._held_code = code
                self._repeat_at = _milliseconds() + self._repeat_delay
            else:
                self._events.append(self._key(KEY_UP, key))
                if code == self._held_code:
                    self._held = NO_KEY
        elif opcode == 4:
            var held = _word(message, 1)
            self._shift = (held & SHIFT_MASK) != 0
            self._ctrl = (held & CONTROL_MASK) != 0
            self._alt = (held & ALT_MASK) != 0
        elif opcode == 5:
            self._repeat_rate = _signed(message, 0)
            self._repeat_delay = _signed(message, 1)

    def _key(self, kind: InputKind, key: Key) -> InputEvent:
        """Return a key event with the modifiers held.

        Args:
            kind: `KEY_DOWN` or `KEY_UP`.
            key: The key.

        Returns:
            The event.
        """
        return InputEvent(
            kind, key=key, shift=self._shift, alt=self._alt, ctrl=self._ctrl
        )

    def _touch_event(mut self, opcode: Int, message: List[UInt8]):
        """Turn an event of the touch screen into input. `wl_touch`'s
        `down`, `up`, `motion` and `cancel`.

        Args:
            opcode: The event's number.
            message: The event.
        """
        if opcode == 0:
            self._finger(
                POINTER_DOWN,
                _signed(message, 3),
                fixed_to_pixel(_signed(message, 4)),
                fixed_to_pixel(_signed(message, 5)),
            )
        elif opcode == 1:
            var id = _signed(message, 2)
            for index in range(len(self._fingers)):
                if self._fingers[index].id == id:
                    var finger = self._fingers.pop(index)
                    self._events.append(
                        self._touched(POINTER_UP, id, finger.x, finger.y)
                    )
                    break
        elif opcode == 2:
            self._finger(
                POINTER_MOVE,
                _signed(message, 1),
                fixed_to_pixel(_signed(message, 2)),
                fixed_to_pixel(_signed(message, 3)),
            )
        elif opcode == 4:
            for finger in self._fingers:
                self._events.append(
                    self._touched(POINTER_CANCEL, finger.id, finger.x, finger.y)
                )
            self._fingers.clear()

    def _finger(mut self, kind: InputKind, id: Int, x: Int, y: Int):
        """Record where a finger is, and report it.

        Args:
            kind: `POINTER_DOWN` or `POINTER_MOVE`.
            id: The finger's id. A negative id names no finger.
            x: The pixel's column.
            y: The pixel's row.
        """
        if id < 0:
            return
        var known = False
        for index in range(len(self._fingers)):
            if self._fingers[index].id == id:
                self._fingers[index] = _Touch(id, x, y)
                known = True
        if not known:
            self._fingers.append(_Touch(id, x, y))
        self._events.append(self._touched(kind, id, x, y))

    def _touched(self, kind: InputKind, id: Int, x: Int, y: Int) -> InputEvent:
        """Return a finger's event, with the modifiers held.

        Args:
            kind: What the finger did.
            id: The finger's id.
            x: The pixel's column.
            y: The pixel's row.

        Returns:
            The event.
        """
        return touch_event(
            kind,
            PointerId(id),
            x,
            y,
            shift=self._shift,
            alt=self._alt,
            ctrl=self._ctrl,
        )

    # --- frames --------------------------------------------------------------

    def _new_buffer(mut self) raises -> Int:
        """Make a buffer that holds the converted frame.

        A buffer is a file with no name in the session's folder. The
        frame is in the file before the compositor maps it.

        Returns:
            The buffer's index in the window's buffers.

        Raises:
            Error: If the file cannot be made, or the socket cannot be
                written.
        """
        var template = (
            runtime_folder(getenv("XDG_RUNTIME_DIR", "")) + "/threemojo-XXXXXX"
        )
        # The template is never empty.
        var path = List[UInt8]()
        for byte in template.as_bytes():  # pragma: no branch
            path.append(byte)
        path.append(0)
        var fd = Int(self._libc.call["mkstemp", c_int](Int(path.unsafe_ptr())))
        require_io(fd >= 0, "cannot make a file for a frame")
        _ = self._libc.call["unlink", c_int](Int(path.unsafe_ptr()))
        _ = path^
        self._store(fd)
        var size = len(self._pixels)
        var pool = self._new(SILENT)
        var create_pool = WireMessage(self._shm, 0)
        create_pool.word(pool)
        create_pool.word(size)
        self._send(create_pool, fd)
        var id = self._new(WL_BUFFER)
        var create_buffer = WireMessage(pool, 0)
        create_buffer.word(id)
        create_buffer.word(0)
        create_buffer.word(self.width)
        create_buffer.word(self.height)
        create_buffer.word(self.width * 4)
        create_buffer.word(FORMAT_XRGB8888)
        self._send(create_buffer)
        self._buffers.append(_Buffer(id, pool, fd, False))
        return len(self._buffers) - 1

    def _store(mut self, fd: Int) raises:
        """Write the converted frame into a buffer's file.

        Args:
            fd: The file.

        Raises:
            Error: If the file does not take the whole frame.
        """
        var size = len(self._pixels)
        var written = self._libc.call["pwrite", Int](
            c_int(fd), Int(self._pixels.unsafe_ptr()), size, Int(0)
        )
        require_io(written == size, "cannot store a frame")

    def present(mut self, frame: Framebuffer) raises:
        """Draw a frame in the window.

        Args:
            frame: The frame, of the window's size.

        Raises:
            Error: If the window is closed, the frame is another size, the
                compositor closed the connection or reports an error, or
                the frame cannot be stored.
        """
        require_presented_frame(self.is_open, frame, self.width, self.height)
        # Hear which buffers the compositor has let go. Input that comes
        # with that waits for `poll`.
        self._drain()
        # RGBA to the buffer's order: blue, green, red, then a byte the
        # compositor ignores.
        for pixel in range(self.width * self.height):  # pragma: no branch
            var at = pixel * 4
            self._pixels[at] = frame.pixels[at + 2]
            self._pixels[at + 1] = frame.pixels[at + 1]
            self._pixels[at + 2] = frame.pixels[at]
            self._pixels[at + 3] = 255
        var free = len(self._buffers)
        for index in range(len(self._buffers)):
            if not self._buffers[index].busy:
                free = index
        if free < len(self._buffers):
            self._store(self._buffers[free].fd)
        else:
            free = self._new_buffer()
        self._buffers[free].busy = True
        var attach = WireMessage(self._surface, 1)
        attach.word(self._buffers[free].id)
        attach.word(0)
        attach.word(0)
        self._send(attach)
        var damage = WireMessage(self._surface, 2)
        damage.word(0)
        damage.word(0)
        damage.word(self.width)
        damage.word(self.height)
        self._send(damage)
        self._commit()

    def resize(mut self, width: Int, height: Int) raises:
        """Take frames of a new size. A `RESIZE` event says when the
        compositor gave the window a new size; this does not resize it.

        Args:
            width: The new width, in pixels.
            height: The new height, in pixels.

        Raises:
            Error: If the window is closed, the size is not positive, a
                side does not fit in a native integer, a frame does not
                fit in a Wayland buffer, or the socket cannot be written.
        """
        require_open(self.is_open)
        require_native_window_size(width, height)
        require_buffer_size(width, height)
        for buffer in self._buffers:
            var destroy_buffer = WireMessage(buffer.id, 0)
            self._send(destroy_buffer)
            var destroy_pool = WireMessage(buffer.pool, 1)
            self._send(destroy_pool)
            _ = self._libc.call["close", c_int](c_int(buffer.fd))
        self._buffers.clear()
        self.width = width
        self.height = height
        self._pixels = List[UInt8](length=width * height * 4, fill=0)

    # --- input ---------------------------------------------------------------

    def poll(mut self, timeout: Duration) raises -> List[InputEvent]:
        """Wait for input, and return what arrived.

        A held key repeats here, at the compositor's rate. A size the
        window already has is not reported. A request from the compositor
        to close sets `close_requested`.

        Args:
            timeout: How long to wait for the first event. Zero returns at
                once.

        Returns:
            The events, oldest first, with positions in pixels.

        Raises:
            Error: If the window is closed, the timeout is negative,
                nonfinite, or too large for native poll milliseconds, or
                the compositor closed the connection or reports an error.
        """
        require_open(self.is_open)
        var wait = Int(poll_milliseconds(timeout))
        # Events that a `present` heard are ready: do not wait for more.
        if len(self._events) == 0:
            if self._repeats():
                wait = min(wait, max(self._repeat_at - _milliseconds(), 0))
            _ = self._fill(wait)
        self._drain()
        var now = _milliseconds()
        if self._repeats() and now >= self._repeat_at:
            self._events.append(self._key(KEY_DOWN, self._held))
            self._repeat_at = now + max(1000 // self._repeat_rate, 1)
        var events = self._events.copy()
        self._events.clear()
        return events^

    def _repeats(self) -> Bool:
        """Return whether a key is held and the compositor lets keys
        repeat.

        Returns:
            Whether the held key repeats.
        """
        return self._held != NO_KEY and self._repeat_rate > 0


def require_buffer_size(width: Int, height: Int) raises:
    """Refuse a frame that a Wayland buffer cannot hold.

    Nothing. The call returns when four bytes a pixel fit in a signed
    32-bit size.

    Args:
        width: The width, in pixels. It must be positive.
        height: The height, in pixels. It must be positive.

    Raises:
        Error: If the frame is larger than that.
    """
    if width > (BUFFER_MAX // 4) // height:
        raise Error("A window is larger than a Wayland buffer holds")


def _milliseconds() -> Int:
    """Return the monotonic clock, in milliseconds."""
    return Int(perf_counter_ns()) // 1000000


def _word(message: List[UInt8], index: Int) -> Int:
    """Return an unsigned argument of a message, or zero past its end.

    Args:
        message: The message.
        index: Which 32-bit word after the header.

    Returns:
        The word.
    """
    var at = HEADER_BYTES + index * 4
    if at + 4 > len(message):
        return 0
    return little_endian_u32(message, at)


def _signed(message: List[UInt8], index: Int) -> Int:
    """Return a signed argument of a message, or zero past its end.

    Args:
        message: The message.
        index: Which 32-bit word after the header.

    Returns:
        The integer, or the fixed-point number in 256ths.
    """
    var value = _word(message, index)
    return value - 0x100000000 if value >= 0x80000000 else value


def _text(message: List[UInt8], index: Int) -> String:
    """Return a string argument of a message.

    Args:
        message: The message.
        index: The word its length is in.

    Returns:
        The string, without its end. Empty when the message is too short
        to hold it.
    """
    var length = _word(message, index)
    var at = HEADER_BYTES + (index + 1) * 4
    if length < 1 or at + length > len(message):
        return String("")
    var bytes = List[UInt8](capacity=length)
    for offset in range(length - 1):
        bytes.append(message[at + offset])
    return String(unsafe_from_utf8=bytes)
