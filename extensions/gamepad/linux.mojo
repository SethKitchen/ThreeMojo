# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of the device functions of
# src/joystick/linux/SDL_sysjoystick.c, from SDL 3.2.24. It is a translation
# from C to Mojo. It is not the original software. The original notice
# follows.
#
#   Simple DirectMedia Layer
#   Copyright (C) 1997-2025 Sam Lantinga <slouken@libsdl.org>
#
#   This software is provided 'as-is', without any express or implied
#   warranty.  In no event will the authors be held liable for any damages
#   arising from the use of this software.
#
#   Permission is granted to anyone to use this software for any purpose,
#   including commercial applications, and to alter it and redistribute it
#   freely, subject to the following restrictions:
#
#   1. The origin of this software must not be misrepresented; you must not
#      claim that you wrote the original software. If you use this software
#      in a product, an acknowledgment in the product documentation would be
#      appreciated but is not required.
#   2. Altered source versions must be plainly marked as such, and must not be
#      misrepresented as being the original software.
#   3. This notice may not be removed or altered from any source distribution.

"""Linux gamepads through evdev: find them, open them, read them.

    var database = default_mapping_database()
    var pads = open_gamepads(database)
    while running:
        for ref pad in pads:
            for event in pad.update():
                ...

`list_event_nodes` lists `/dev/input/event*` in SDL's order.
`probe_joystick` asks a device who it is and whether it is a joystick.
`EvdevGamepad` opens one and reads it each frame. The user needs read
access to the device; most desktop systems give it to the user at the
seat.

SDL watches for devices with udev or inotify. This port does not. Call
`list_event_nodes` again to find a gamepad that was plugged in later. A
gamepad that is unplugged sets `gone`.

Every device call is a method of an `EvdevSource`. `EvdevFile` makes the
calls on a file descriptor. A test can give a recorded device instead.
"""
from extensions.gamepad.evdev import (
    ABSINFO_SIZE,
    ABS_BITMAP_BYTES,
    ABS_HAT0X,
    ABS_HAT3Y,
    ABS_MAX,
    EV_ABS,
    EV_BITMAP_BYTES,
    EV_KEY,
    EV_REL,
    INPUT_EVENT_SIZE,
    KEY_BITMAP_BYTES,
    PROP_BITMAP_BYTES,
    REL_BITMAP_BYTES,
    DEVICE_JOYSTICK,
    AbsInfo,
    EvdevCapabilities,
    EvdevLayout,
    EvdevState,
    InputId,
    automatic_mapping,
    decode_input_events,
    fixup_device_id,
    guess_device_class,
    test_bit,
)
from extensions.gamepad.gamepad import Gamepad, GamepadEvent
from extensions.gamepad.guid import (
    DRIVER_NONE,
    HardwareBus,
    JoystickGuid,
    ProductId,
    VendorId,
    create_joystick_guid,
)
from extensions.gamepad.joystick import Joystick
from extensions.gamepad.linux_mappings import linux_default_mappings
from extensions.gamepad.mapping import MappingDatabase, PRIORITY_DEFAULT
from extensions.gamepad.names import (
    create_joystick_name,
    should_ignore_joystick,
)
from std.ffi import c_int, external_call
from std.os import listdir

# The length of the name buffers SDL passes to the kernel.
comptime NAME_BYTES = 128
# How many events SDL reads at once.
comptime READ_EVENTS = 32
# `poll`'s "data to read" bit.
comptime POLLIN = 1


def _ioc_read(type: Int, number: Int, size: Int) -> Int:
    """Return a Linux ioctl request that reads. Linux: `_IOC(_IOC_READ, ...)`.

    Args:
        type: The driver's letter, `E` for evdev.
        number: The request number.
        size: The size of the buffer the kernel writes.

    Returns:
        The request.
    """
    return (2 << 30) | (size << 16) | (type << 8) | number


def eviocgbit(event_type: Int, size: Int) -> Int:
    """Return the request for a capability bitmap. Linux: `EVIOCGBIT`.

    Args:
        event_type: The event type, or 0 for the bitmap of event types.
        size: The bitmap's size in bytes.

    Returns:
        The request.
    """
    return _ioc_read(ord("E"), 0x20 + event_type, size)


def eviocgabs(code: Int) -> Int:
    """Return the request for an axis's range. Linux: `EVIOCGABS`.

    Args:
        code: The axis code.

    Returns:
        The request.
    """
    return _ioc_read(ord("E"), 0x40 + code, ABSINFO_SIZE)


comptime EVIOCGID = (2 << 30) | (8 << 16) | (0x45 << 8) | 0x02


def eviocgname(size: Int) -> Int:
    """Return the request for a device's name. Linux: `EVIOCGNAME`.

    Args:
        size: The buffer's size.

    Returns:
        The request.
    """
    return _ioc_read(ord("E"), 0x06, size)


def eviocgprop(size: Int) -> Int:
    """Return the request for the property bitmap. Linux: `EVIOCGPROP`.

    Args:
        size: The bitmap's size in bytes.

    Returns:
        The request.
    """
    return _ioc_read(ord("E"), 0x09, size)


def eviocgkey(size: Int) -> Int:
    """Return the request for the keys that are down. Linux: `EVIOCGKEY`.

    Args:
        size: The bitmap's size in bytes.

    Returns:
        The request.
    """
    return _ioc_read(ord("E"), 0x18, size)


def jsiocgname(size: Int) -> Int:
    """Return the request for a classic joystick's name. Linux:
    `JSIOCGNAME`.

    Args:
        size: The buffer's size.

    Returns:
        The request.
    """
    return _ioc_read(ord("j"), 0x13, size)


trait EvdevSource(Deinitable, Movable):
    """The calls SDL makes on an input device.

    Each returns what `ioctl` or `read` returns: a negative value when the
    call fails.
    """

    @staticmethod
    def open(path: String) raises -> Self:
        """Open a device.

        Args:
            path: The device's path.

        Returns:
            The open device.

        Raises:
            Error: If the device cannot be opened.
        """
        ...

    def query(mut self, request: Int, mut buffer: List[UInt8]) -> Int:
        """Make an ioctl that fills a buffer.

        Args:
            request: The request.
            buffer: The buffer, at least as long as the request says.

        Returns:
            The ioctl's result.
        """
        ...

    def readable(mut self) -> Bool:
        """Return True if a read would not wait.

        Returns:
            Whether events, an error or the end are ready.
        """
        ...

    def read_into(mut self, mut buffer: List[UInt8]) -> Int:
        """Read events into a buffer.

        Args:
            buffer: The buffer. Its length is the most to read.

        Returns:
            The number of bytes read, 0 at the end, or -1 on an error.
        """
        ...


struct EvdevFile(EvdevSource):
    """An open input device: a file descriptor and the calls on it."""

    var fd: c_int

    def __init__(out self, path: String) raises:
        """Open a device for reading. SDL: `open(path, O_RDONLY)`.

        Args:
            path: The device, such as `/dev/input/event3`.

        Raises:
            Error: If the device cannot be opened.
        """
        var text = path
        self.fd = external_call["open", c_int, num_fixed_args=2](
            text.as_c_string_span().ptr(), c_int(0)
        )
        if self.fd < 0:
            raise Error("Cannot open the input device " + path)

    @staticmethod
    def open(path: String) raises -> Self:
        """Open a device for reading.

        Args:
            path: The device's path.

        Returns:
            The open device.

        Raises:
            Error: If the device cannot be opened.
        """
        return EvdevFile(path)

    def __deinit__(deinit self):
        """Close the device."""
        _ = external_call["close", c_int](self.fd)

    def query(mut self, request: Int, mut buffer: List[UInt8]) -> Int:
        """Make an ioctl that fills a buffer.

        Args:
            request: The request.
            buffer: The buffer, at least as long as the request says.

        Returns:
            The ioctl's result.
        """
        return Int(
            external_call["ioctl", c_int, num_fixed_args=2](
                self.fd, UInt(request), buffer.unsafe_ptr()
            )
        )

    def readable(mut self) -> Bool:
        """Return True if a read would not wait. It asks `poll` with no
        timeout.

        Returns:
            Whether events, an error or the end are ready.
        """
        # `struct pollfd`: the descriptor, then two shorts.
        var fds = List[Int32](length=2, fill=0)
        fds[0] = Int32(self.fd)
        fds[1] = Int32(POLLIN)
        return (
            external_call["poll", c_int](fds.unsafe_ptr(), UInt(1), c_int(0))
            > 0
        )

    def read_into(mut self, mut buffer: List[UInt8]) -> Int:
        """Read events into a buffer.

        Args:
            buffer: The buffer. Its length is the most to read.

        Returns:
            The number of bytes read, 0 at the end, or -1 on an error.
        """
        return external_call["read", Int](
            Int32(self.fd), buffer.unsafe_ptr(), len(buffer)
        )


def _query_bits[
    S: EvdevSource
](mut source: S, request: Int, size: Int) -> Optional[List[UInt8]]:
    """Read one bitmap.

    Args:
        source: The device.
        request: The request.
        size: The bitmap's size in bytes.

    Returns:
        The bitmap, or None when the call fails.
    """
    var bits = List[UInt8](length=size, fill=0)
    if source.query(request, bits) < 0:
        return None
    return bits^


def read_capabilities[
    S: EvdevSource
](mut source: S,) -> Optional[EvdevCapabilities]:
    """Read a device's bitmaps. SDL: the calls of `GuessDeviceClass`.

    Args:
        source: The device.

    Returns:
        The bitmaps, or None when the device does not give its event
        types, keys, relative axes or absolute axes. A device that does
        not give its properties has none.
    """
    var caps = EvdevCapabilities()
    var events = _query_bits(
        source, eviocgbit(0, EV_BITMAP_BYTES), EV_BITMAP_BYTES
    )
    var keys = _query_bits(
        source, eviocgbit(EV_KEY, KEY_BITMAP_BYTES), KEY_BITMAP_BYTES
    )
    var relatives = _query_bits(
        source, eviocgbit(EV_REL, REL_BITMAP_BYTES), REL_BITMAP_BYTES
    )
    var absolutes = _query_bits(
        source, eviocgbit(EV_ABS, ABS_BITMAP_BYTES), ABS_BITMAP_BYTES
    )
    if not events or not keys or not relatives or not absolutes:
        return None
    caps.events = events.take()
    caps.keys = keys.take()
    caps.relatives = relatives.take()
    caps.absolutes = absolutes.take()
    var properties = _query_bits(
        source, eviocgprop(PROP_BITMAP_BYTES), PROP_BITMAP_BYTES
    )
    if properties:
        caps.properties = properties.take()
    return caps^


def read_absinfo[
    S: EvdevSource
](mut source: S, absolutes: List[UInt8]) -> List[Optional[AbsInfo]]:
    """Read the range of each absolute axis a device has.

    Args:
        source: The device.
        absolutes: The device's absolute axis bitmap.

    Returns:
        Each axis's range by code, or None for an axis the device does not
        have or does not describe.
    """
    var result = List[Optional[AbsInfo]](length=ABS_MAX + 1, fill=None)
    for code in range(ABS_MAX + 1):  # pragma: no branch
        if not test_bit(absolutes, code):
            continue
        var bytes = List[UInt8](length=ABSINFO_SIZE, fill=0)
        if source.query(eviocgabs(code), bytes) >= 0:
            result[code] = AbsInfo.from_buffer(bytes)
    return result^


def _c_string(buffer: List[UInt8]) -> String:
    """Return the text of a buffer up to its first zero byte.

    Args:
        buffer: The buffer.

    Returns:
        The text.
    """
    var bytes = List[UInt8]()
    for byte in buffer:  # pragma: no branch
        if byte == 0:
            break
        bytes.append(byte)
    return String(unsafe_from_utf8=bytes)


struct JoystickInfo(Copyable, Movable):
    """What SDL learns about a joystick before it opens it. SDL:
    `SDL_joylist_item`."""

    var path: String
    var name: String
    var guid: JoystickGuid
    var id: InputId

    def __init__(
        out self, path: String, name: String, guid: JoystickGuid, id: InputId
    ):
        """Create the information.

        Args:
            path: The device's path.
            name: The name SDL gives it.
            guid: Its GUID.
            id: Its bus, vendor, product and version.
        """
        self.path = path
        self.name = name
        self.guid = guid
        self.id = id


def probe_joystick[
    S: EvdevSource
](mut source: S, path: String) raises -> Optional[JoystickInfo]:
    """Return who a device is, if it is a joystick. SDL: `IsJoystick`,
    without udev.

    Args:
        source: The open device.
        path: The device's path.

    Returns:
        The joystick's information, or None when it is not a joystick, does
        not say who it is, or is one SDL ignores.

    Raises:
        Error: If the device reports an id that does not fit 16 bits.
    """
    var name_buffer = List[UInt8](length=NAME_BYTES, fill=0)
    var id = InputId()
    if source.query(jsiocgname(NAME_BYTES), name_buffer) <= 0:
        var caps = read_capabilities(source)
        if not caps or not guess_device_class(caps.value()).has(
            DEVICE_JOYSTICK
        ):
            return None
        var id_bytes = List[UInt8](length=8, fill=0)
        if source.query(EVIOCGID, id_bytes) < 0:
            return None
        id = InputId.from_bytes(id_bytes)
        if source.query(eviocgname(NAME_BYTES), name_buffer) < 0:
            return None
    var product_name = _c_string(name_buffer)
    var name = create_joystick_name(
        VendorId(id.vendor), ProductId(id.product), "", product_name
    )
    var keys = _query_bits(
        source, eviocgbit(EV_KEY, KEY_BITMAP_BYTES), KEY_BITMAP_BYTES
    )
    if keys:
        id = fixup_device_id(id, keys.value())
    if should_ignore_joystick(
        VendorId(id.vendor), ProductId(id.product), id.version, name
    ):
        return None
    var guid = create_joystick_guid(
        HardwareBus(id.bustype),
        VendorId(id.vendor),
        ProductId(id.product),
        id.version,
        "",
        product_name,
        DRIVER_NONE,
        0,
    )
    return JoystickInfo(path, name, guid, id)


def is_event_node(path: String) -> Bool:
    """Return True if a path names an evdev node. SDL:
    `IsJoystickEventNode`.

    Args:
        path: The path or the file name.

    Returns:
        Whether the file name is `event` and then one or more digits.
    """
    var slash = path.rfind("/")
    var name = String(path[byte = slash + 1 :])
    if not name.startswith("event") or name.byte_length() == 5:
        return False
    for byte in name.as_bytes()[5:]:  # pragma: no branch
        if byte < 48 or byte > 57:
            return False
    return True


def _number_after(name: String, prefix: Int) -> Int:
    """Read the digits after a prefix, as `atoi` does.

    Args:
        name: The file name.
        prefix: The prefix's length.

    Returns:
        The number, or 0 when there are no digits.
    """
    var value = 0
    for byte in name.as_bytes()[prefix:]:
        if byte < 48 or byte > 57:
            break
        value = value * 10 + Int(byte - 48)
    return value


def event_joystick_index(sysfs: String, event: Int) -> Int:
    """Return the classic joystick number of an evdev node. SDL:
    `get_event_joystick_index`.

    Args:
        sysfs: The input class folder, `/sys/class/input`.
        event: The evdev node's number.

    Returns:
        The number of the device's `js` node, or -1 when it has none.
    """
    var names: List[String]
    try:
        names = listdir(sysfs + "/event" + String(event) + "/device")
    except:
        return -1
    sort(names)
    var index = -1
    for name in names:
        if name.startswith("js"):
            index = _number_after(name, 2)
    return index


def _before(a: String, b: String, sysfs: String) -> Bool:
    """Return True if one evdev node comes before another. SDL:
    `sort_entries`.

    Args:
        a: The first file name.
        b: The second file name.
        sysfs: The input class folder.

    Returns:
        Whether `a` sorts first: by `js` number when both have one, a node
        with one before a node without, and by `event` number otherwise.
    """
    var number_a = _number_after(a, 5)
    var number_b = _number_after(b, 5)
    var js_a = event_joystick_index(sysfs, number_a)
    var js_b = event_joystick_index(sysfs, number_b)
    if js_a >= 0 and js_b >= 0:
        return js_a < js_b
    if js_a >= 0 or js_b >= 0:
        return js_a >= 0
    return number_a < number_b


def list_event_nodes(
    directory: String = "/dev/input", sysfs: String = "/sys/class/input"
) -> List[String]:
    """Return the evdev nodes in SDL's order. SDL:
    `LINUX_ScanInputDevices`.

    Args:
        directory: The input device folder.
        sysfs: The input class folder.

    Returns:
        The full path of each node, or no paths when the folder cannot be
        read.
    """
    var names = List[String]()
    try:
        for name in listdir(directory):
            if is_event_node(name):
                names.append(name)
    except:
        return List[String]()
    # An insertion sort: there are a few dozen nodes at most.
    for index in range(1, len(names)):
        var at = index
        while at > 0 and _before(names[at], names[at - 1], sysfs):
            names.swap_elements(at, at - 1)
            at -= 1
    var paths = List[String]()
    for name in names:
        paths.append(directory + "/" + name)
    return paths^


def _is_hat_axis(layout: EvdevLayout, code: Int) -> Bool:
    """Return True if an axis code is one of a digital hat's axes.

    Args:
        layout: The layout.
        code: The axis code.

    Returns:
        Whether the code is `ABS_HAT0X` to `ABS_HAT3Y` and its hat is
        digital.
    """
    if code < ABS_HAT0X or code > ABS_HAT3Y:
        return False
    return layout.has_hat[(code - ABS_HAT0X) // 2]


def default_mapping_database() raises -> MappingDatabase:
    """Return a database with SDL's built-in Linux mappings. SDL:
    `SDL_InitGamepadMappings`, without its files and hints.

    Returns:
        The database.

    Raises:
        Error: Never, since the built-in mappings are well formed.
    """
    var database = MappingDatabase()
    for mapping in linux_default_mappings():  # pragma: no branch
        _ = database.add_mapping(mapping, PRIORITY_DEFAULT)
    return database^


struct EvdevGamepad[S: EvdevSource](Movable):
    """An open evdev device read as a gamepad. SDL: an `SDL_Gamepad` on the
    Linux joystick driver."""

    var source: Self.S
    var info: JoystickInfo
    var state: EvdevState
    var gamepad: Gamepad
    # Whether the device went away.
    var gone: Bool

    def __init__(
        out self,
        var source: Self.S,
        info: JoystickInfo,
        mut database: MappingDatabase,
        use_deadzones: Bool = False,
        use_hat_deadzones: Bool = True,
        digital_hats: Bool = False,
    ) raises:
        """Open a joystick as a gamepad. SDL: `LINUX_JoystickOpen`,
        `LINUX_JoystickGetGamepadMapping` and `SDL_OpenGamepad`.

        Args:
            source: The open device.
            info: What `probe_joystick` learned about it.
            database: The mappings. An automatic mapping is added to it.
            use_deadzones: SDL's hint `SDL_JOYSTICK_LINUX_DEADZONES`.
            use_hat_deadzones: SDL's hint
                `SDL_JOYSTICK_LINUX_HAT_DEADZONES`.
            digital_hats: SDL's hint `SDL_JOYSTICK_LINUX_DIGITAL_HATS`.

        Raises:
            Error: If the device does not give its keys and axes, or no
                mapping fits it.
        """
        var keys = _query_bits(
            source, eviocgbit(EV_KEY, KEY_BITMAP_BYTES), KEY_BITMAP_BYTES
        )
        var absolutes = _query_bits(
            source, eviocgbit(EV_ABS, ABS_BITMAP_BYTES), ABS_BITMAP_BYTES
        )
        var relatives = _query_bits(
            source, eviocgbit(EV_REL, REL_BITMAP_BYTES), REL_BITMAP_BYTES
        )
        if not keys or not absolutes or not relatives:
            raise Error(
                "The input device does not give its keys and axes: " + info.path
            )
        var caps = EvdevCapabilities()
        caps.keys = keys.take()
        caps.absolutes = absolutes.take()
        caps.relatives = relatives.take()
        var layout = EvdevLayout()
        layout.configure(
            caps,
            read_absinfo(source, caps.absolutes),
            use_deadzones,
            use_hat_deadzones,
            digital_hats,
        )
        var raw = automatic_mapping(layout, VendorId(info.id.vendor))
        var index = database.mapping_for_device(info.name, info.guid, raw)
        if index < 0:
            raise Error("No gamepad mapping fits " + info.name)
        var joystick = Joystick(
            info.name, info.guid, layout.axes, layout.buttons, layout.hats
        )
        self.gamepad = Gamepad(joystick^, database.mappings[index])
        self.source = source^
        self.info = info.copy()
        self.state = EvdevState(layout^)
        self.gone = False

    def _read_state(mut self):
        """Read the device's whole state. SDL: `PollAllValues`."""
        var absinfo = List[Optional[AbsInfo]](length=ABS_MAX + 1, fill=None)
        for code in range(ABS_MAX):  # pragma: no branch
            if not self.state.layout.has_abs[code] and not _is_hat_axis(
                self.state.layout, code
            ):
                continue
            var bytes = List[UInt8](length=ABSINFO_SIZE, fill=0)
            if self.source.query(eviocgabs(code), bytes) >= 0:
                absinfo[code] = AbsInfo.from_buffer(bytes)
        var keys = _query_bits(
            self.source, eviocgkey(KEY_BITMAP_BYTES), KEY_BITMAP_BYTES
        )
        self.state.apply_state(self.gamepad.joystick, absinfo, keys)

    def update(mut self) -> List[GamepadEvent]:
        """Read what the device sent and return the gamepad's events. SDL:
        `HandleInputEvents` and the gamepad event watcher.

        The first call reads the device's whole state, so that a button
        held at open shows as down.

        Returns:
            The gamepad events since the last call.
        """
        if self.state.fresh:
            self._read_state()
            self.state.fresh = False
        var buffer = List[UInt8](length=READ_EVENTS * INPUT_EVENT_SIZE, fill=0)
        while not self.gone and self.source.readable():
            var count = self.source.read_into(buffer)
            if count <= 0:
                self.gone = True
                break
            var bytes = List[UInt8](capacity=count)
            for index in range(count):  # pragma: no branch
                bytes.append(buffer[index])
            for event in decode_input_events(bytes):
                if self.state.handle_event(self.gamepad.joystick, event):
                    self._read_state()
        return self.gamepad.update()


def open_gamepads_with[
    S: EvdevSource
](mut database: MappingDatabase, paths: List[String]) -> List[EvdevGamepad[S]]:
    """Open each path that is a gamepad. SDL: `MaybeAddDevice` and
    `SDL_OpenGamepad` for each device.

    A device that cannot be opened, or is not a gamepad, is skipped.

    Parameters:
        S: The kind of device, which `S.open` opens.

    Args:
        database: The mappings.
        paths: The device paths, in order.

    Returns:
        The open gamepads, in the order of the paths.
    """
    var pads = List[EvdevGamepad[S]]()
    for path in paths:
        try:
            var source = S.open(path)
            var info = probe_joystick(source, path)
            if info:
                pads.append(EvdevGamepad(source^, info.value(), database))
        except:
            continue
    return pads^


def open_gamepads(
    mut database: MappingDatabase,
    directory: String = "/dev/input",
    sysfs: String = "/sys/class/input",
) -> List[EvdevGamepad[EvdevFile]]:
    """Open every gamepad. SDL: `LINUX_JoystickDetect` and
    `SDL_OpenGamepad` for each gamepad.

    A device that cannot be opened, or is not a gamepad, is skipped.

    Args:
        database: The mappings.
        directory: The input device folder.
        sysfs: The input class folder.

    Returns:
        The open gamepads, in SDL's order.
    """
    return open_gamepads_with[EvdevFile](
        database, list_event_nodes(directory, sysfs)
    )
