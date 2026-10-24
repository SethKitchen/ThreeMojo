# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""HID devices: find them and send them reports.

SDL's HIDAPI drivers talk to a controller in its own reports, through the
hidapi library. `HidSource` is the calls they make: read an input report,
write an output report, and get or send a feature report. `HidrawFile`
makes them on a Linux `/dev/hidraw*` node. A test gives a recorded device
instead, and the macOS backend gives an IOKit device.

`enumerate_hidraw` lists the hidraw nodes with what hidapi's Linux
backend learns about each: the ids, the strings, the bus, the USB
interface and the first top-level usage of the report descriptor. hidapi
asks udev; this module reads the same files from sysfs, so it needs no
library.

A hidraw node is often readable only by root. A udev rule, such as the
one Steam installs for its controllers, gives the user at the seat
access.
"""
from extensions.gamepad.guid import ProductId, VendorId
from std.ffi import c_int, external_call
from std.os import listdir
from std.os.path import exists

# `poll` asks whether a read would not wait.
comptime POLLIN = 1


@fieldwise_init
struct HidBus(Equatable, ImplicitlyCopyable, Writable):
    """The bus a HID device is on. SDL: `SDL_hid_bus_type`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 5 buses.

        Returns:
            Whether the value is 0 to 4.
        """
        return self.value >= 0 and self.value <= 4


comptime HID_BUS_UNKNOWN = HidBus(0)
comptime HID_BUS_USB = HidBus(1)
comptime HID_BUS_BLUETOOTH = HidBus(2)
comptime HID_BUS_I2C = HidBus(3)
comptime HID_BUS_SPI = HidBus(4)


@fieldwise_init
struct HidDeviceInfo(Copyable, Movable, Writable):
    """What enumeration learns about a HID device. SDL:
    `SDL_hid_device_info`."""

    var path: String
    var vendor: VendorId
    var product: ProductId
    # The device's release number, such as USB's `bcdDevice`.
    var release: Int
    var serial: String
    var manufacturer: String
    var product_name: String
    var usage_page: Int
    var usage: Int
    # The USB interface, or -1 off USB.
    var interface_number: Int
    var bus: HidBus


trait HidSource(Deinitable, Movable):
    """The calls SDL's HIDAPI drivers make on a device.

    Each returns what hidapi returns: a byte count, or -1 when the call
    fails.
    """

    @staticmethod
    def open(path: String) raises -> Self:
        """Open a device. SDL: `SDL_hid_open_path`.

        Args:
            path: The device's path.

        Returns:
            The open device.

        Raises:
            Error: If the device cannot be opened.
        """
        ...

    def read(mut self, mut buffer: List[UInt8], milliseconds: Int) -> Int:
        """Read one input report. SDL: `SDL_hid_read_timeout`.

        Args:
            buffer: The buffer. Its length is the most to read.
            milliseconds: How long to wait. 0 does not wait.

        Returns:
            The report's length, 0 when none came, or -1 on an error.
        """
        ...

    def write(mut self, data: List[UInt8]) -> Int:
        """Write one output report. SDL: `SDL_hid_write`.

        Args:
            data: The report, its id first.

        Returns:
            The bytes written, or -1 on an error.
        """
        ...

    def get_feature_report(mut self, mut buffer: List[UInt8]) -> Int:
        """Read a feature report. SDL: `SDL_hid_get_feature_report`.

        Args:
            buffer: The report id in the first byte. The report replaces
                it. Its length is the most to read.

        Returns:
            The bytes read, the id included, or -1 on an error.
        """
        ...

    def send_feature_report(mut self, data: List[UInt8]) -> Int:
        """Send a feature report. SDL: `SDL_hid_send_feature_report`.

        Args:
            data: The report, its id first.

        Returns:
            The bytes sent, or -1 on an error.
        """
        ...


def _ioc_read_write(number: Int, size: Int) -> Int:
    """Return a hidraw ioctl request that writes and reads a buffer.

    Args:
        number: The request number.
        size: The buffer's size.

    Returns:
        `_IOC(_IOC_WRITE | _IOC_READ, 'H', number, size)`.
    """
    return (3 << 30) | (size << 16) | (ord("H") << 8) | number


def hidiocgfeature(size: Int) -> Int:
    """Return the request that reads a feature report.

    Args:
        size: The buffer's size.

    Returns:
        `HIDIOCGFEATURE(size)`.
    """
    return _ioc_read_write(0x07, size)


def hidiocsfeature(size: Int) -> Int:
    """Return the request that sends a feature report.

    Args:
        size: The report's size.

    Returns:
        `HIDIOCSFEATURE(size)`.
    """
    return _ioc_read_write(0x06, size)


struct HidrawFile(HidSource):
    """An open Linux hidraw node. hidapi: its `linux/hid.c` backend."""

    var fd: c_int

    def __init__(out self, path: String) raises:
        """Open a node for reading and writing.

        Args:
            path: The node, such as `/dev/hidraw0`.

        Raises:
            Error: If the node cannot be opened.
        """
        var text = path
        self.fd = external_call["open", c_int, num_fixed_args=2](
            text.as_c_string_span().ptr(), c_int(2)
        )
        if self.fd < 0:
            raise Error("Cannot open the HID device " + path)

    @staticmethod
    def open(path: String) raises -> Self:
        """Open a node for reading and writing.

        Args:
            path: The node's path.

        Returns:
            The open node.

        Raises:
            Error: If the node cannot be opened.
        """
        return HidrawFile(path)

    def __deinit__(deinit self):
        """Close the node."""
        _ = external_call["close", c_int](self.fd)

    def read(mut self, mut buffer: List[UInt8], milliseconds: Int) -> Int:
        """Read one input report. It waits with `poll`, then reads.

        Args:
            buffer: The buffer. Its length is the most to read.
            milliseconds: How long to wait. 0 does not wait.

        Returns:
            The report's length, 0 when none came, or -1 on an error.
        """
        # `struct pollfd`: the descriptor, then two shorts.
        var fds = List[Int32](length=2, fill=0)
        fds[0] = Int32(self.fd)
        fds[1] = Int32(POLLIN)
        var ready = external_call["poll", c_int](
            fds.unsafe_ptr(), UInt(1), c_int(milliseconds)
        )
        if ready <= 0:
            return Int(ready)
        var count = external_call["read", Int](
            Int32(self.fd), buffer.unsafe_ptr(), len(buffer)
        )
        # A node that went away reads as the end.
        return count if count > 0 else -1

    def write(mut self, data: List[UInt8]) -> Int:
        """Write one output report.

        Args:
            data: The report, its id first.

        Returns:
            The bytes written, or -1 on an error.
        """
        return external_call["write", Int](
            Int32(self.fd), data.unsafe_ptr(), len(data)
        )

    def get_feature_report(mut self, mut buffer: List[UInt8]) -> Int:
        """Read a feature report with `HIDIOCGFEATURE`.

        Args:
            buffer: The report id in the first byte. The report replaces
                it.

        Returns:
            The bytes read, the id included, or -1 on an error.
        """
        return Int(
            external_call["ioctl", c_int, num_fixed_args=2](
                self.fd,
                UInt(hidiocgfeature(len(buffer))),
                buffer.unsafe_ptr(),
            )
        )

    def send_feature_report(mut self, data: List[UInt8]) -> Int:
        """Send a feature report with `HIDIOCSFEATURE`.

        Args:
            data: The report, its id first.

        Returns:
            The bytes sent, or -1 on an error.
        """
        return Int(
            external_call["ioctl", c_int, num_fixed_args=2](
                self.fd,
                UInt(hidiocsfeature(len(data))),
                data.unsafe_ptr(),
            )
        )


def first_top_level_usage(descriptor: List[UInt8]) -> Tuple[Int, Int]:
    """Return the usage page and usage of a report descriptor's first
    top-level collection. hidapi: `get_next_hid_usage`, first call.

    Args:
        descriptor: The report descriptor.

    Returns:
        The usage page and the usage, or 0 and 0 when there is no
        top-level collection.
    """
    var page = 0
    var usage = 0
    var depth = 0
    var index = 0
    while index < len(descriptor):
        var key = Int(descriptor[index])
        if key == 0xFE:
            # A long item: its data size is the next byte.
            if index + 1 >= len(descriptor):
                break
            index += 3 + Int(descriptor[index + 1])
            continue
        var size = key & 3
        if size == 3:
            size = 4
        var value = 0
        for offset in range(size):
            if index + 1 + offset < len(descriptor):
                value |= Int(descriptor[index + 1 + offset]) << (8 * offset)
        var tag = key & 0xFC
        if tag == 0x04:
            page = value
        elif tag == 0x08:
            usage = value
        elif tag == 0xA0:
            if depth == 0:
                return (page, usage)
            depth += 1
        elif tag == 0xC0:
            depth -= 1
        index += 1 + size
    return (0, 0)


def _read_text(path: String) -> String:
    """Read a small sysfs file.

    Args:
        path: The file.

    Returns:
        Its text without the line end, or an empty string when it cannot
        be read.
    """
    try:
        with open(path, "r") as file:
            var text = file.read()
            if text.endswith("\n"):
                return String(text[byte = : text.byte_length() - 1])
            return text
    except:
        return ""


def _read_bytes(path: String) -> List[UInt8]:
    """Read a sysfs file's bytes.

    Args:
        path: The file.

    Returns:
        Its bytes, or none when it cannot be read.
    """
    try:
        with open(path, "r") as file:
            return file.read_bytes()
    except:
        return List[UInt8]()


def _hex_value(text: String) -> Int:
    """Read a hexadecimal number, as `strtol(text, NULL, 16)` does.

    Args:
        text: The text.

    Returns:
        The number, or 0 when the text starts with no hex digit.
    """
    var value = 0
    for byte in text.as_bytes():
        var digit: Int
        if byte >= 48 and byte <= 57:
            digit = Int(byte) - 48
        elif byte >= 97 and byte <= 102:
            digit = Int(byte) - 87
        elif byte >= 65 and byte <= 70:
            digit = Int(byte) - 55
        else:
            break
        value = value * 16 + digit
    return value


def _uevent_field(uevent: String, key: String) -> String:
    """Return one field of a uevent file.

    Args:
        uevent: The file's text.
        key: The field, such as `HID_NAME`.

    Returns:
        The value, or an empty string when the field is missing.
    """
    for line in uevent.split("\n"):
        if line.startswith(key + "="):
            return String(line[byte = key.byte_length() + 1 :])
    return ""


def read_hidraw_info(
    class_dir: String, name: String, dev_dir: String
) -> Optional[HidDeviceInfo]:
    """Learn about one hidraw node from sysfs. hidapi:
    `create_device_info_for_device`.

    Args:
        class_dir: The hidraw class folder, `/sys/class/hidraw`.
        name: The node's name, such as `hidraw0`.
        dev_dir: The device folder, `/dev`.

    Returns:
        What the node is, or None when its HID device gives no ids.
    """
    var device = class_dir + "/" + name + "/device"
    var uevent = _read_text(device + "/uevent")
    # HID_ID=0003:0000054C:00000CE6: the bus, the vendor and the product.
    var ids = _uevent_field(uevent, "HID_ID").split(":")
    if len(ids) != 3:
        return None
    var bus_number = _hex_value(String(ids[0]))
    var vendor = VendorId(_hex_value(String(ids[1])))
    var product = ProductId(_hex_value(String(ids[2])))
    var product_name = _uevent_field(uevent, "HID_NAME")
    var serial = _uevent_field(uevent, "HID_UNIQ")
    var usage = first_top_level_usage(
        _read_bytes(device + "/report_descriptor")
    )
    var manufacturer = ""
    var release = 0
    var interface_number = -1
    var bus = HID_BUS_UNKNOWN
    if bus_number == 0x03:
        bus = HID_BUS_USB
        # The USB interface holds the HID device; the USB device holds it.
        var interface = device + "/.."
        var usb = interface + "/.."
        if exists(usb + "/idVendor"):
            manufacturer = _read_text(usb + "/manufacturer")
            product_name = _read_text(usb + "/product")
            release = _hex_value(_read_text(usb + "/bcdDevice"))
            var number = _read_text(interface + "/bInterfaceNumber")
            if number.byte_length() > 0:
                interface_number = _hex_value(number)
    elif bus_number == 0x05:
        bus = HID_BUS_BLUETOOTH
    elif bus_number == 0x18:
        bus = HID_BUS_I2C
    elif bus_number == 0x1C:
        bus = HID_BUS_SPI
    return HidDeviceInfo(
        dev_dir + "/" + name,
        vendor,
        product,
        release,
        serial,
        manufacturer,
        product_name,
        usage[0],
        usage[1],
        interface_number,
        bus,
    )


def enumerate_hidraw(
    class_dir: String = "/sys/class/hidraw", dev_dir: String = "/dev"
) -> List[HidDeviceInfo]:
    """List the hidraw nodes. SDL: `SDL_hid_enumerate(0, 0)` on Linux.

    Args:
        class_dir: The hidraw class folder.
        dev_dir: The device folder.

    Returns:
        Each node with ids, in the order of their numbers.
    """
    var names = List[String]()
    try:
        for name in listdir(class_dir):
            if name.startswith("hidraw"):
                names.append(name)
    except:
        pass
    # hidraw2 before hidraw10.
    for index in range(1, len(names)):
        var at = index
        while at > 0 and (
            names[at - 1].byte_length() > names[at].byte_length()
            or (
                names[at - 1].byte_length() == names[at].byte_length()
                and names[at - 1] > names[at]
            )
        ):
            names.swap_elements(at - 1, at)
            at -= 1
    var found = List[HidDeviceInfo]()
    for name in names:
        var info = read_hidraw_info(class_dir, name, dev_dir)
        if info:
            found.append(info.value().copy())
    return found^
