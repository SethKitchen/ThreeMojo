# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.gamepad.hid` and `extensions.gamepad.hid_device`.

The sysfs tree is made in a scratch folder, with the links the kernel
makes: `class/hidraw/hidrawN/device` links to the HID device, whose
parents are the USB interface and the USB device. The names, GUIDs and
types are the ones SDL 3.2.24's `HIDAPI_AddDevice` gives for the same
ids and strings.
"""

from std.ffi import c_int, external_call
from std.os import makedirs
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.gamepad.guid import (
    ProductId,
    VendorId,
    guid_to_string,
    joystick_guid_info,
)
from extensions.gamepad.hid import (
    HID_BUS_BLUETOOTH,
    HID_BUS_I2C,
    HID_BUS_SPI,
    HID_BUS_UNKNOWN,
    HID_BUS_USB,
    HidBus,
    HidDeviceInfo,
    HidrawFile,
    _hex_value,
    enumerate_hidraw,
    first_top_level_usage,
    hidiocgfeature,
    hidiocsfeature,
    read_hidraw_info,
)
from extensions.gamepad.hid_device import (
    HidapiDevice,
    game_controller_protocol,
    load16,
    load32,
    remap_val,
    supports_playstation_detection,
)
from extensions.gamepad.ids import (
    GAMEPAD_TYPE_PS4,
    GAMEPAD_TYPE_PS5,
    GAMEPAD_TYPE_STANDARD,
    GAMEPAD_TYPE_XBOX360,
    GAMEPAD_TYPE_XBOXONE,
)
from test_scratch import TestScratch, temporary_path


def _write(path: String, text: String) raises:
    with open(path, "w") as file:
        file.write(text)


def _link(target: String, name: String):
    var a = target
    var b = name
    _ = external_call["symlink", c_int](
        a.as_c_string_span().ptr(), b.as_c_string_span().ptr()
    )


def _unlink(path: String):
    var name = path
    _ = external_call["unlink", c_int](name.as_c_string_span().ptr())


def _info(
    vendor: Int,
    product: Int,
    manufacturer: String,
    product_name: String,
    bus: HidBus = HID_BUS_USB,
    serial: String = "",
) -> HidDeviceInfo:
    return HidDeviceInfo(
        "/dev/hidraw0",
        VendorId(vendor),
        ProductId(product),
        0x100,
        serial,
        manufacturer,
        product_name,
        1,
        5,
        3,
        bus,
    )


def test_bus_and_requests() raises:
    assert_true(HID_BUS_SPI.is_valid())
    assert_false(HidBus(5).is_valid())
    assert_false(HidBus(-1).is_valid())
    assert_equal(hidiocgfeature(64), 0xC0404807)
    assert_equal(hidiocsfeature(78), 0xC04E4806)


def test_report_descriptor_usage() raises:
    # Usage page 1, usage 5, an application collection.
    var gamepad: List[UInt8] = [0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0xC0]
    var usage = first_top_level_usage(gamepad)
    assert_equal(usage[0], 1)
    assert_equal(usage[1], 5)
    # A long item is skipped; a 4-byte usage page counts.
    var long: List[UInt8] = [
        0xFE, 0x02, 0x00, 0xAA, 0xBB,
        0x07, 0x0C, 0x00, 0x00, 0x00,
        0x0A, 0x01, 0x00,
        0xA1, 0x01,
        0xA1, 0x00, 0xC0,
        0xC0,
    ]  # fmt: skip
    usage = first_top_level_usage(long)
    assert_equal(usage[0], 0x0C)
    assert_equal(usage[1], 1)
    # No collection, a truncated long item, and a truncated value.
    assert_equal(first_top_level_usage([0x05, 0x01])[0], 0)
    assert_equal(first_top_level_usage([0xFE])[1], 0)
    assert_equal(first_top_level_usage([0x05, 0x01, 0xA1])[0], 1)
    # Another item before the collection is skipped.
    usage = first_top_level_usage([0x05, 0x01, 0x15, 0x00, 0x09, 0x04, 0xA1, 1])
    assert_equal(usage[1], 4)
    # An end before a start leaves the depth below zero: still no usage.
    assert_equal(first_top_level_usage([0xC0, 0xA1, 0x01])[0], 0)


def test_enumerate_hidraw() raises:
    with TestScratch():
        var root = temporary_path("sys")
        var dev = temporary_path("dev")
        var usb = root + "/devices/usb1/1-1"
        var hid = usb + "/1-1:1.3/0003:054C:0CE6.0001"
        makedirs(hid)
        makedirs(dev)
        _write(usb + "/idVendor", "054c\n")
        _write(usb + "/manufacturer", "Sony Interactive Entertainment\n")
        _write(usb + "/product", "DualSense Wireless Controller\n")
        _write(usb + "/bcdDevice", "01a0")
        _write(usb + "/1-1:1.3/bInterfaceNumber", "03\n")
        _write(
            hid + "/uevent",
            (
                "DRIVER=playstation\nHID_ID=0003:0000054C:00000CE6\n"
                "HID_NAME=Sony Interactive Entertainment DualSense\n"
                "HID_UNIQ=\n"
            ),
        )
        with open(hid + "/report_descriptor", "w") as file:
            file.write_bytes([0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0xC0])
        # A Bluetooth pad: no USB parents.
        var bt = root + "/devices/bt/0005:054C:09CC.0002"
        makedirs(bt)
        _write(
            bt + "/uevent",
            (
                "HID_ID=0005:0000054C:000009CC\nHID_NAME=Wireless Controller\n"
                "HID_UNIQ=a0:b1:c2:d3:e4:f5\n"
            ),
        )
        # A virtual USB device has no USB device above it.
        var virtual = root + "/devices/virtual/x/0003:1234:5678.0003"
        makedirs(virtual)
        _write(
            virtual + "/uevent",
            "HID_ID=0003:00001234:00005678\nHID_NAME=Virtual Pad\n",
        )
        # A USB interface without its number.
        var bare = root + "/devices/usb2/2-1"
        makedirs(bare + "/2-1:1.0/0003:0001:0002.0004")
        _write(bare + "/idVendor", "0001\n")
        _write(
            bare + "/2-1:1.0/0003:0001:0002.0004/uevent",
            "HID_ID=0003:00000001:00000002\n",
        )
        # I2C, SPI, an unknown bus, and a device with no ids.
        for entry in [
            ("i2c", "0018:00000001:00000003"),
            ("spi", "001C:00000001:00000004"),
            ("other", "0006:00000001:00000005"),
            ("noid", ""),
        ]:
            makedirs(root + "/devices/" + entry[0])
            _write(
                root + "/devices/" + entry[0] + "/uevent",
                "HID_ID=" + entry[1] + "\n" if entry[1].byte_length()
                > 0 else "X=1\n",
            )
        var classes = root + "/class/hidraw"
        makedirs(classes)
        for entry in [
            ("hidraw2", hid),
            ("hidraw10", bt),
            ("hidraw1", virtual),
            ("hidraw3", bare + "/2-1:1.0/0003:0001:0002.0004"),
            ("hidraw4", root + "/devices/i2c"),
            ("hidraw5", root + "/devices/spi"),
            ("hidraw6", root + "/devices/other"),
            ("hidraw7", root + "/devices/noid"),
        ]:
            makedirs(classes + "/" + entry[0])
            _link(entry[1], classes + "/" + entry[0] + "/device")
        makedirs(classes + "/other")
        var found = enumerate_hidraw(classes, dev)
        assert_equal(len(found), 7)
        assert_equal(found[0].path, dev + "/hidraw1")
        assert_equal(found[0].manufacturer, "")
        assert_equal(found[0].product_name, "Virtual Pad")
        assert_equal(found[0].interface_number, -1)
        ref sony = found[1]
        assert_equal(sony.path, dev + "/hidraw2")
        assert_equal(sony.vendor.value, 0x054C)
        assert_equal(sony.product.value, 0x0CE6)
        assert_equal(sony.release, 0x1A0)
        assert_equal(sony.manufacturer, "Sony Interactive Entertainment")
        assert_equal(sony.product_name, "DualSense Wireless Controller")
        assert_equal(sony.interface_number, 3)
        assert_equal(sony.usage_page, 1)
        assert_equal(sony.usage, 5)
        assert_true(sony.bus == HID_BUS_USB)
        assert_equal(found[2].interface_number, -1)
        assert_true(found[3].bus == HID_BUS_I2C)
        assert_true(found[4].bus == HID_BUS_SPI)
        assert_true(found[5].bus == HID_BUS_UNKNOWN)
        ref pad = found[6]
        assert_equal(pad.path, dev + "/hidraw10")
        assert_true(pad.bus == HID_BUS_BLUETOOTH)
        assert_equal(pad.serial, "a0:b1:c2:d3:e4:f5")
        assert_equal(pad.product_name, "Wireless Controller")
        assert_equal(pad.usage_page, 0)
        assert_false(read_hidraw_info(classes, "hidraw7", dev))
        assert_equal(len(enumerate_hidraw(root + "/missing", dev)), 0)
        assert_equal(len(enumerate_hidraw(dev, dev)), 0)
        # The scratch folder removes files and folders, not links.
        for name in ["1", "2", "3", "4", "5", "6", "7", "10"]:
            _unlink(classes + "/hidraw" + name + "/device")


def test_hidraw_file() raises:
    with TestScratch():
        var path = temporary_path("hidraw")
        _write(path, "")
        var file = HidrawFile.open(path)
        var buffer = List[UInt8](length=4, fill=0)
        # A regular file is always ready, and at its end.
        assert_equal(file.read(buffer, 0), -1)
        assert_equal(file.write([1, 2, 3]), 3)
        buffer[0] = 5
        assert_equal(file.get_feature_report(buffer), -1)
        assert_equal(file.send_feature_report([5, 1]), -1)
        with assert_raises():
            _ = HidrawFile(path + ".missing")
        # A FIFO with no writer's data: nothing is ready.
        var fifo = temporary_path("fifo")
        var name = fifo
        _ = external_call["mkfifo", c_int](
            name.as_c_string_span().ptr(), UInt32(0o600)
        )
        var pipe = HidrawFile(fifo)
        assert_equal(pipe.read(buffer, 0), 0)
        _unlink(fifo)


def test_hex_value() raises:
    assert_equal(_hex_value("1aF"), 0x1AF)
    assert_equal(_hex_value("12-3"), 0x12)
    assert_equal(_hex_value(""), 0)
    assert_equal(_hex_value("9g"), 9)
    assert_equal(_hex_value("9Z"), 9)


def test_helpers() raises:
    assert_equal(load16([0xFF, 0x7F], 0), 32767)
    assert_equal(load16([0x00, 0x80], 0), -32768)
    assert_equal(load32([1, 2, 3, 0xF4], 0), 0xF4030201)
    assert_almost_equal(remap_val(5, 0, 10, -1, 1), 0)
    assert_true(supports_playstation_detection(VendorId(0x0F0D), ProductId(1)))
    assert_true(supports_playstation_detection(VendorId(0x7545), ProductId(1)))
    assert_true(supports_playstation_detection(VendorId(0x0738), ProductId(1)))
    assert_false(
        supports_playstation_detection(VendorId(0x0738), ProductId(0x2218))
    )
    assert_false(supports_playstation_detection(VendorId(0x046D), ProductId(1)))
    # A device known to be something else is not probed.
    assert_false(
        supports_playstation_detection(VendorId(0x0F0D), ProductId(0x00C1))
    )


def test_protocol() raises:
    var vendor = VendorId(0x045E)
    var product = ProductId(0x1234)
    assert_true(
        game_controller_protocol("", vendor, product, 0, 0xFF, 93, 1)
        == GAMEPAD_TYPE_XBOX360
    )
    assert_true(
        game_controller_protocol("", vendor, product, 0, 0xFF, 93, 129)
        == GAMEPAD_TYPE_XBOX360
    )
    assert_true(
        game_controller_protocol("", VendorId(0x1111), product, 0, 0xFF, 93, 1)
        == GAMEPAD_TYPE_STANDARD
    )
    assert_true(
        game_controller_protocol("", vendor, product, 0, 0xFF, 93, 2)
        == GAMEPAD_TYPE_STANDARD
    )
    assert_true(
        game_controller_protocol("", vendor, product, 0, 0xFF, 71, 208)
        == GAMEPAD_TYPE_XBOXONE
    )
    assert_true(
        game_controller_protocol(
            "", VendorId(0x1111), product, 0, 0xFF, 71, 208
        )
        == GAMEPAD_TYPE_STANDARD
    )
    assert_true(
        game_controller_protocol("", vendor, product, 1, 0xFF, 71, 208)
        == GAMEPAD_TYPE_STANDARD
    )
    for entry in [(0, 0xFE, 71, 208), (0, 0xFF, 70, 208), (0, 0xFF, 71, 1)]:
        assert_true(
            game_controller_protocol(
                "", vendor, product, entry[0], entry[1], entry[2], entry[3]
            )
            == GAMEPAD_TYPE_STANDARD
        )
    assert_true(
        game_controller_protocol(
            "", VendorId(0x054C), ProductId(0x0CE6), -1, 0, 0, 0
        )
        == GAMEPAD_TYPE_PS5
    )


def test_device() raises:
    var device = HidapiDevice(
        _info(
            0x054C,
            0x09CC,
            "Sony Interactive Entertainment",
            "Wireless Controller",
        )
    )
    # The driver renames it later; this is the name from the strings.
    assert_equal(
        device.name, "Sony Interactive Entertainment Wireless Controller"
    )
    assert_true(device.type == GAMEPAD_TYPE_PS4)
    assert_false(device.is_bluetooth)
    # The bus, the ids, the version and HIDAPI's signature; the CRC is of
    # the strings until the driver renames the pad.
    var text = guid_to_string(device.guid)
    assert_equal(String(text[byte=:4]), "0300")
    assert_equal(String(text[byte=8:]), "4c050000cc09000000016800")
    assert_equal(device.interface_number, 3)
    assert_equal(device.usage_page, 1)
    assert_equal(device.usage, 5)
    assert_true(device.serial_is_empty())
    # A new name sets the GUID's CRC.
    var crc = joystick_guid_info(device.guid).crc
    device.set_name("Sony Interactive Entertainment Wireless Controller")
    assert_equal(joystick_guid_info(device.guid).crc, crc)
    device.set_name("")
    device.set_name("Pad")
    assert_equal(device.name, "Pad")
    assert_true(joystick_guid_info(device.guid).crc != crc)
    # A dongle's pad gives the GUID its own ids; the device keeps its own.
    device.set_product(VendorId(0x054C), ProductId(0x05C4))
    assert_equal(joystick_guid_info(device.guid).product.value, 0x05C4)
    assert_equal(device.product.value, 0x09CC)
    device.set_serial("")
    device.set_serial("000000")
    assert_true(device.serial_is_empty())
    device.set_serial("a1")
    assert_false(device.serial_is_empty())
    device.set_serial("a1")
    assert_equal(device.serial, "a1")
    device.usb_serials = ["a1"]
    assert_true(device.has_connected_usb_device("a1"))
    assert_false(device.has_connected_usb_device("b2"))
    assert_false(device.has_connected_usb_device(""))
    device.disconnect_bluetooth_device("a1")
    assert_equal(device.disconnect_bluetooth, "a1")
    assert_true(device.joystick_connected())
    assert_equal(device.joysticks, 1)
    device.joystick_disconnected()
    assert_equal(device.joysticks, 0)
    assert_true(device.rescan)
    var wireless = HidapiDevice(
        _info(0x045E, 0x0B13, "", "Xbox Wireless Controller", HID_BUS_BLUETOOTH)
    )
    assert_true(wireless.is_bluetooth)
    assert_equal(Int(wireless.guid.data[0]), 0x05)
    assert_true(wireless.type == GAMEPAD_TYPE_XBOXONE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
