# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of the device functions of
# src/joystick/hidapi/SDL_hidapijoystick.c, from SDL 3.2.24. It is a
# translation from C to Mojo. It is not the original software. The original
# notice follows.
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

"""What SDL's HIDAPI drivers know about a device, and the helpers they share.

`HidapiDevice` is SDL's `SDL_HIDAPI_Device` without the driver: the name,
the ids, the GUID, the bus and whether a joystick is connected. A driver
changes it through the same calls SDL's drivers make, such as
`set_name` and `joystick_connected`.
"""
from extensions.gamepad.controller_type import gamepad_type_from_vidpid
from extensions.gamepad.guid import (
    BUS_BLUETOOTH,
    BUS_USB,
    DRIVER_HIDAPI,
    HardwareBus,
    JoystickGuid,
    ProductId,
    VendorId,
    create_joystick_guid,
    crc16,
)
from extensions.gamepad.hid import HID_BUS_BLUETOOTH, HidDeviceInfo
from extensions.gamepad.ids import (
    GAMEPAD_TYPE_STANDARD,
    GAMEPAD_TYPE_XBOX360,
    GAMEPAD_TYPE_XBOXONE,
    GamepadType,
)
from extensions.gamepad.names import create_joystick_name

# The largest HID report on USB. SDL: `USB_PACKET_LENGTH`.
comptime USB_PACKET_LENGTH = 64

# What a joystick can do. SDL: `SDL_JOYSTICK_CAP_*`.
comptime CAP_MONO_LED = 0x01
comptime CAP_RGB_LED = 0x02
comptime CAP_PLAYER_LED = 0x04
comptime CAP_RUMBLE = 0x10
comptime CAP_TRIGGER_RUMBLE = 0x20

# USB vendor ids. SDL: `usb_ids.h`.
comptime USB_VENDOR_DRAGONRISE = 0x0079
comptime USB_VENDOR_HORI = 0x0F0D
comptime USB_VENDOR_LOGITECH = 0x046D
comptime USB_VENDOR_MADCATZ = 0x0738
comptime USB_VENDOR_MAYFLASH = 0x33DF
comptime USB_VENDOR_NACON = 0x146B
comptime USB_VENDOR_NACON_ALT = 0x3285
comptime USB_VENDOR_PDP = 0x0E6F
comptime USB_VENDOR_POWERA = 0x24C6
comptime USB_VENDOR_POWERA_ALT = 0x20D6
comptime USB_VENDOR_QANBA = 0x2C22
comptime USB_VENDOR_RAZER = 0x1532
comptime USB_VENDOR_SHANWAN = 0x2563
comptime USB_VENDOR_SHANWAN_ALT = 0x20BC
comptime USB_VENDOR_THRUSTMASTER = 0x044F
comptime USB_VENDOR_ZEROPLUS = 0x0C12
comptime USB_PRODUCT_MADCATZ_SAITEK_SIDE_PANEL_CONTROL_DECK = 0x2218


def supports_playstation_detection(
    vendor: VendorId, product: ProductId
) -> Bool:
    """Return True if a device may be a PlayStation controller made by
    another company. SDL: `HIDAPI_SupportsPlaystationDetection`.

    The drivers then ask the device for Sony's capability report.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        Whether the vendor makes such controllers and the device is not
        known to be something else.
    """
    if gamepad_type_from_vidpid(vendor, product, "", False) != (
        GAMEPAD_TYPE_STANDARD
    ):
        return False
    var id = vendor.value
    if id == USB_VENDOR_MADCATZ:
        return (
            product.value != USB_PRODUCT_MADCATZ_SAITEK_SIDE_PANEL_CONTROL_DECK
        )
    return (
        id == USB_VENDOR_DRAGONRISE
        or id == USB_VENDOR_HORI
        or id == USB_VENDOR_MAYFLASH
        or id == USB_VENDOR_NACON
        or id == USB_VENDOR_NACON_ALT
        or id == USB_VENDOR_PDP
        or id == USB_VENDOR_POWERA
        or id == USB_VENDOR_POWERA_ALT
        or id == USB_VENDOR_QANBA
        or id == USB_VENDOR_SHANWAN
        or id == USB_VENDOR_SHANWAN_ALT
        or id == USB_VENDOR_ZEROPLUS
        or id == 0x7545
    )


def remap_val(
    value: Float32,
    value_min: Float32,
    value_max: Float32,
    output_min: Float32,
    output_max: Float32,
) -> Float32:
    """Map a value from one range to another. SDL: `HIDAPI_RemapVal`.

    Args:
        value: The value.
        value_min: The input range's start.
        value_max: The input range's end.
        output_min: The output range's start.
        output_max: The output range's end.

    Returns:
        The value in the output range.
    """
    return output_min + (output_max - output_min) * (value - value_min) / (
        value_max - value_min
    )


def load16(data: List[UInt8], index: Int) -> Int:
    """Read a signed 16-bit little-endian number. SDL: `LOAD16`.

    Args:
        data: The bytes.
        index: Where the number starts.

    Returns:
        The number, from -32768 to 32767.
    """
    var value = Int(data[index]) | (Int(data[index + 1]) << 8)
    return value - 0x10000 if value >= 0x8000 else value


def load32(data: List[UInt8], index: Int) -> Int:
    """Read an unsigned 32-bit little-endian number. SDL: `LOAD32`.

    Args:
        data: The bytes.
        index: Where the number starts.

    Returns:
        The number, from 0 to 4294967295.
    """
    return (
        Int(data[index])
        | (Int(data[index + 1]) << 8)
        | (Int(data[index + 2]) << 16)
        | (Int(data[index + 3]) << 24)
    )


def _in_vendors(vendor: Int, vendors: List[Int]) -> Bool:
    """Return True if a vendor is in a list.

    Args:
        vendor: The vendor id.
        vendors: The list.

    Returns:
        Whether it is there.
    """
    for entry in vendors:
        if entry == vendor:
            return True
    return False


def game_controller_protocol(
    name: String,
    vendor: VendorId,
    product: ProductId,
    interface_number: Int,
    interface_class: Int,
    interface_subclass: Int,
    interface_protocol: Int,
) -> GamepadType:
    """Return the kind of gamepad a HID device is. SDL:
    `SDL_GetJoystickGameControllerProtocol`.

    An Xbox controller's USB interface names its protocol. hidapi on
    Linux and macOS gives no interface class, so there the ids decide.

    Args:
        name: The device's name.
        vendor: The USB vendor id.
        product: The USB product id.
        interface_number: The USB interface, or -1.
        interface_class: The interface class, or 0.
        interface_subclass: The interface subclass, or 0.
        interface_protocol: The interface protocol, or 0.

    Returns:
        The gamepad type.
    """
    comptime VENDOR_SPECIFIC = 0xFF
    var type = GAMEPAD_TYPE_STANDARD
    if (
        interface_class == VENDOR_SPECIFIC
        and interface_subclass == 93
        and (interface_protocol == 1 or interface_protocol == 129)
    ):
        var vendors: List[Int] = [
            0x0079, 0x044F, 0x045E, 0x046D, 0x056E, 0x06A3, 0x0738,
            0x07FF, 0x0E6F, 0x0F0D, 0x1038, 0x11C9, 0x12AB, 0x1430,
            0x146B, 0x1532, 0x15E4, 0x162E, 0x1689, 0x1949, 0x1BAD,
            0x20D6, 0x24C6, 0x2C22, 0x2DC8, 0x9886,
        ]  # fmt: skip
        if _in_vendors(vendor.value, vendors):
            type = GAMEPAD_TYPE_XBOX360
    if (
        interface_number == 0
        and interface_class == VENDOR_SPECIFIC
        and interface_subclass == 71
        and interface_protocol == 208
    ):
        var vendors: List[Int] = [
            0x03F0, 0x044F, 0x045E, 0x0738, 0x0B05, 0x0E6F, 0x0F0D,
            0x10F5, 0x1532, 0x20D6, 0x24C6, 0x2DC8, 0x2E24, 0x3537,
        ]  # fmt: skip
        if _in_vendors(vendor.value, vendors):
            type = GAMEPAD_TYPE_XBOXONE
    if type == GAMEPAD_TYPE_STANDARD:
        type = gamepad_type_from_vidpid(vendor, product, name, False)
    return type


struct HidapiDevice(Copyable, Movable):
    """A HID device that a HIDAPI driver may run. SDL: `SDL_HIDAPI_Device`."""

    var name: String
    var manufacturer: String
    var product_name: String
    var path: String
    var vendor: VendorId
    var product: ProductId
    var version: Int
    # The serial number, or empty for none.
    var serial: String
    var guid: JoystickGuid
    var interface_number: Int
    var usage_page: Int
    var usage: Int
    var is_bluetooth: Bool
    var type: GamepadType
    # How many joysticks the driver connected: 0 or 1.
    var joysticks: Int
    # Set when a joystick goes away, so that the device list is read
    # again. SDL: `SDL_HIDAPI_change_count = 0`.
    var rescan: Bool
    # The serial numbers of the USB devices with a driver, which a
    # Bluetooth pad compares with its own. The hub fills it.
    var usb_serials: List[String]
    # A serial number whose Bluetooth devices the hub must disconnect.
    var disconnect_bluetooth: String

    def __init__(out self, info: HidDeviceInfo) raises:
        """Describe a device that enumeration found. SDL:
        `HIDAPI_AddDevice`, before the driver is chosen.

        Args:
            info: What enumeration learned.

        Raises:
            Error: If the GUID cannot be made, which a valid version
                never causes.
        """
        self.path = info.path
        self.vendor = info.vendor
        self.product = info.product
        self.version = info.release
        self.interface_number = info.interface_number
        self.usage_page = info.usage_page
        self.usage = info.usage
        self.is_bluetooth = info.bus == HID_BUS_BLUETOOTH
        self.manufacturer = info.manufacturer
        self.product_name = info.product_name
        self.name = create_joystick_name(
            info.vendor, info.product, info.manufacturer, info.product_name
        )
        self.serial = info.serial
        var bus = BUS_BLUETOOTH if self.is_bluetooth else BUS_USB
        self.guid = create_joystick_guid(
            bus,
            info.vendor,
            info.product,
            info.release,
            info.manufacturer,
            info.product_name,
            DRIVER_HIDAPI,
            0,
        )
        self.type = game_controller_protocol(
            self.name, info.vendor, info.product, info.interface_number, 0, 0, 0
        )
        self.joysticks = 0
        self.rescan = False
        self.usb_serials = List[String]()
        self.disconnect_bluetooth = ""

    def set_name(mut self, name: String):
        """Rename the device and update the GUID's CRC. SDL:
        `HIDAPI_SetDeviceName`.

        Args:
            name: The new name. An empty or equal one changes nothing.
        """
        if name.byte_length() > 0 and name != self.name:
            self.name = name
            self.guid.set_crc(crc16(0, name.as_bytes()))

    def set_product(mut self, vendor: VendorId, product: ProductId) raises:
        """Give the GUID other ids, such as those of the pad behind a
        dongle. SDL: `HIDAPI_SetDeviceProduct`.

        The device keeps its own ids, so that it is not found again as a
        new device.

        Args:
            vendor: The vendor id.
            product: The product id.

        Raises:
            Error: If the GUID cannot be made, which a valid version
                never causes.
        """
        self.guid = create_joystick_guid(
            HardwareBus(Int(self.guid.data[0])),
            vendor,
            product,
            self.version,
            self.manufacturer,
            self.product_name,
            DRIVER_HIDAPI,
            0,
        )

    def set_serial(mut self, serial: String):
        """Set the serial number. SDL: `HIDAPI_SetDeviceSerial`.

        Args:
            serial: The serial number. An empty or equal one changes
                nothing.
        """
        if serial.byte_length() > 0 and serial != self.serial:
            self.serial = serial

    def serial_is_empty(self) -> Bool:
        """Return True if the serial number is missing or all zeros. SDL:
        `HIDAPI_SerialIsEmpty`.

        Returns:
            Whether no digit is other than 0.
        """
        for byte in self.serial.as_bytes():
            if byte != UInt8(ord("0")):
                return False
        return True

    def has_connected_usb_device(self, serial: String) -> Bool:
        """Return True if a USB device with a driver has a serial number.
        SDL: `HIDAPI_HasConnectedUSBDevice`.

        Args:
            serial: The serial number, or empty.

        Returns:
            Whether a USB device has it.
        """
        if serial.byte_length() == 0:
            return False
        return serial in self.usb_serials

    def disconnect_bluetooth_device(mut self, serial: String):
        """Ask the hub to disconnect the Bluetooth devices with a serial
        number. SDL: `HIDAPI_DisconnectBluetoothDevice`.

        Args:
            serial: The serial number, or empty.
        """
        self.disconnect_bluetooth = serial

    def joystick_connected(mut self) -> Bool:
        """Connect the device's joystick. SDL: `HIDAPI_JoystickConnected`.

        Returns:
            True.
        """
        self.joysticks = 1
        return True

    def joystick_disconnected(mut self):
        """Disconnect the device's joystick. SDL:
        `HIDAPI_JoystickDisconnected`.
        """
        self.joysticks = 0
        self.rescan = True
