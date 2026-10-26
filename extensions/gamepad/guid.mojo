# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of src/SDL_guid.c, src/stdlib/SDL_crc16.c
# and the GUID functions of src/joystick/SDL_joystick.c, from SDL 3.2.24. It
# is a translation from C to Mojo. It is not the original software. The
# original notice follows.
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

"""A joystick GUID: 16 bytes that name a kind of device.

SDL looks a gamepad up in its mapping database by this GUID. The standard
form, which every device with a USB vendor id gets, is eight
little-endian 16-bit words:

    bus, CRC-16 of the name, vendor, 0, product, 0, version, driver

The last word is two bytes: a driver signature, such as `h` for HIDAPI,
and data that belongs to the driver. A device with no vendor id keeps the
bus and the CRC, then up to 11 bytes of its name.

The text form is the 32 lowercase hex digits of the 16 bytes, in order.
`string_to_guid` reads it back.
"""
from extensions.gamepad.ids import equal_ignoring_case

# The number of bytes in a GUID.
comptime GUID_SIZE = 16


@fieldwise_init
struct HardwareBus(Equatable, ImplicitlyCopyable, Writable):
    """The bus a device is on: the Linux `input_id.bustype`. SDL:
    `SDL_HARDWARE_BUS_*`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the value fits the GUID's 16-bit bus word.

        Returns:
            Whether the value is 0 to 65535.
        """
        return self.value >= 0 and self.value <= 0xFFFF


comptime BUS_UNKNOWN = HardwareBus(0x00)
comptime BUS_USB = HardwareBus(0x03)
comptime BUS_BLUETOOTH = HardwareBus(0x05)
comptime BUS_VIRTUAL = HardwareBus(0xFF)


@fieldwise_init
struct VendorId(Equatable, ImplicitlyCopyable, Writable):
    """A USB vendor id, such as 0x054c for Sony."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the value is a 16-bit id.

        Returns:
            Whether the value is 0 to 65535.
        """
        return self.value >= 0 and self.value <= 0xFFFF


@fieldwise_init
struct ProductId(Equatable, ImplicitlyCopyable, Writable):
    """A USB product id, such as 0x0ce6 for the DualSense."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the value is a 16-bit id.

        Returns:
            Whether the value is 0 to 65535.
        """
        return self.value >= 0 and self.value <= 0xFFFF


@fieldwise_init
struct DriverSignature(Equatable, ImplicitlyCopyable, Writable):
    """The byte that names the driver that made a GUID, or 0 for none."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the value fits a byte.

        Returns:
            Whether the value is 0 to 255.
        """
        return self.value >= 0 and self.value <= 0xFF


comptime DRIVER_NONE = DriverSignature(0)
comptime DRIVER_HIDAPI = DriverSignature(ord("h"))
comptime DRIVER_XINPUT = DriverSignature(ord("x"))
comptime DRIVER_WGI = DriverSignature(ord("w"))
comptime DRIVER_MFI = DriverSignature(ord("m"))
comptime DRIVER_RAWINPUT = DriverSignature(ord("r"))
comptime DRIVER_VIRTUAL = DriverSignature(ord("v"))


def _crc16_for_byte(byte: UInt16) -> UInt16:
    """Return the CRC-16 table entry for one byte.

    Args:
        byte: The byte, from 0 to 255.

    Returns:
        SDL's `crc16_for_byte`.
    """
    var crc: UInt16 = 0
    var r = byte
    for _ in range(8):
        var mask: UInt16 = 0
        if ((crc ^ r) & 1) != 0:
            mask = 0xA001
        crc = mask ^ (crc >> 1)
        r >>= 1
    return crc


def crc16(crc: UInt16, data: Span[UInt8, _]) -> UInt16:
    """Continue a CRC-16 over some bytes. SDL: `SDL_crc16`.

    This is the reflected CRC-16 with the polynomial 0xA001, the one SDL
    uses for joystick names.

    Args:
        crc: The CRC so far, or 0 to start.
        data: The bytes.

    Returns:
        The CRC after the bytes.
    """
    var result = crc
    for byte in data:
        result = _crc16_for_byte((result ^ UInt16(byte)) & 0xFF) ^ (result >> 8)
    return result


struct JoystickGuidInfo(ImplicitlyCopyable):
    """What a GUID says about its device. SDL: `SDL_GetJoystickGUIDInfo`."""

    var vendor: VendorId
    var product: ProductId
    var version: Int
    var crc: UInt16

    def __init__(
        out self,
        vendor: VendorId,
        product: ProductId,
        version: Int,
        crc: UInt16,
    ):
        """Create the information.

        Args:
            vendor: The USB vendor id, or 0.
            product: The USB product id, or 0.
            version: The product version, or 0.
            crc: The CRC-16 of the name, or 0.
        """
        self.vendor = vendor
        self.product = product
        self.version = version
        self.crc = crc


struct JoystickGuid(Equatable, ImplicitlyCopyable, Writable):
    """The 16 bytes that name a kind of joystick. SDL: `SDL_GUID`."""

    var data: SIMD[DType.uint8, GUID_SIZE]

    def __init__(out self):
        """Create the zero GUID."""
        self.data = SIMD[DType.uint8, GUID_SIZE](0)

    def word(self, index: Int) -> Int:
        """Return one of the eight little-endian 16-bit words.

        Args:
            index: The word, from 0 to 7.

        Returns:
            The word.
        """
        return Int(self.data[2 * index]) | (Int(self.data[2 * index + 1]) << 8)

    def set_word(mut self, index: Int, value: Int):
        """Set one of the eight little-endian 16-bit words.

        Args:
            index: The word, from 0 to 7.
            value: The word. Only its low 16 bits are kept.
        """
        self.data[2 * index] = UInt8(value & 0xFF)
        self.data[2 * index + 1] = UInt8((value >> 8) & 0xFF)

    def is_zero(self) -> Bool:
        """Return True if every byte is zero.

        Returns:
            Whether this is the zero GUID.
        """
        return self.data == SIMD[DType.uint8, GUID_SIZE](0)

    def set_vendor(mut self, vendor: VendorId):
        """Set the vendor word. SDL: `SDL_SetJoystickGUIDVendor`.

        Args:
            vendor: The USB vendor id.
        """
        self.set_word(2, vendor.value)

    def set_product(mut self, product: ProductId):
        """Set the product word. SDL: `SDL_SetJoystickGUIDProduct`.

        Args:
            product: The USB product id.
        """
        self.set_word(4, product.value)

    def set_version(mut self, version: Int):
        """Set the version word. SDL: `SDL_SetJoystickGUIDVersion`.

        Args:
            version: The product version.
        """
        self.set_word(6, version)

    def set_crc(mut self, crc: UInt16):
        """Set the CRC word. SDL: `SDL_SetJoystickGUIDCRC`.

        Args:
            crc: The CRC-16 of the name.
        """
        self.set_word(1, Int(crc))

    def driver(self) -> DriverSignature:
        """Return the driver signature, byte 14.

        Returns:
            The signature. `DRIVER_HIDAPI` means SDL's HIDAPI driver made
            the GUID.
        """
        return DriverSignature(Int(self.data[14]))


def guid_to_string(guid: JoystickGuid) -> String:
    """Return the 32 lowercase hex digits of a GUID. SDL: `SDL_GUIDToString`.

    Args:
        guid: The GUID.

    Returns:
        The text form.
    """
    var digits = "0123456789abcdef".as_bytes()
    var text = List[UInt8](capacity=2 * GUID_SIZE)
    for index in range(GUID_SIZE):  # pragma: no branch
        var byte = Int(guid.data[index])
        text.append(digits[byte >> 4])
        text.append(digits[byte & 0x0F])
    return String(unsafe_from_utf8=text)


def _nibble(byte: UInt8) -> UInt8:
    """Return the value of a hex digit. SDL: `nibble`.

    Args:
        byte: The ASCII digit.

    Returns:
        The value from 0 to 15, or 0 for a byte that is not a hex digit,
        as in SDL.
    """
    if byte >= 48 and byte <= 57:
        return byte - 48
    if byte >= 65 and byte <= 70:
        return byte - 65 + 10
    if byte >= 97 and byte <= 102:
        return byte - 97 + 10
    return 0


def string_to_guid(text: String) -> JoystickGuid:
    """Read a GUID from its hex digits. SDL: `SDL_StringToGUID`.

    An odd last digit is ignored. Digits past the 32nd are ignored. A
    shorter text leaves the rest zero. A byte that is not a hex digit
    counts as 0.

    Args:
        text: The text form.

    Returns:
        The GUID.
    """
    var bytes = text.as_bytes()
    var length = len(bytes) & ~1
    var guid = JoystickGuid()
    var index = 0
    while index < length and index // 2 < GUID_SIZE:
        guid.data[index // 2] = (_nibble(bytes[index]) << 4) | _nibble(
            bytes[index + 1]
        )
        index += 2
    return guid


def create_joystick_guid(
    bus: HardwareBus,
    vendor: VendorId,
    product: ProductId,
    version: Int,
    vendor_name: String,
    product_name: String,
    driver: DriverSignature,
    driver_data: Int,
) raises -> JoystickGuid:
    """Make the GUID of a device. SDL: `SDL_CreateJoystickGUID`.

    The CRC is over the vendor name, a space and the product name when
    both are given, or over the product name alone. An empty name is
    SDL's NULL.

    Args:
        bus: The bus.
        vendor: The USB vendor id, or 0 when there is none.
        product: The USB product id.
        version: The product version, from 0 to 65535.
        vendor_name: The vendor's name, or empty.
        product_name: The product's name, or empty.
        driver: The driver signature, or `DRIVER_NONE`.
        driver_data: A byte that belongs to the driver.

    Returns:
        The GUID.

    Raises:
        Error: If an id is not valid, or the version or the driver data
            does not fit.
    """
    if not bus.is_valid() or not vendor.is_valid() or not product.is_valid():
        raise Error("A joystick GUID needs a 16-bit bus, vendor and product")
    if not driver.is_valid() or version < 0 or version > 0xFFFF:
        raise Error("A joystick GUID needs a byte driver and 16-bit version")
    if driver_data < 0 or driver_data > 0xFF:
        raise Error("A joystick GUID's driver data must fit a byte")
    var crc: UInt16 = 0
    if vendor_name.byte_length() > 0 and product_name.byte_length() > 0:
        crc = crc16(crc, vendor_name.as_bytes())
        crc = crc16(crc, " ".as_bytes())
        crc = crc16(crc, product_name.as_bytes())
    else:
        crc = crc16(crc, product_name.as_bytes())
    var guid = JoystickGuid()
    guid.set_word(0, bus.value)
    guid.set_crc(crc)
    if vendor.value != 0:
        guid.set_vendor(vendor)
        guid.set_product(product)
        guid.set_version(version)
        guid.data[14] = UInt8(driver.value)
        guid.data[15] = UInt8(driver_data)
        return guid
    var available = GUID_SIZE - 4
    if driver.value != 0:
        available -= 2
        guid.data[14] = UInt8(driver.value)
        guid.data[15] = UInt8(driver_data)
    # strlcpy: at most `available - 1` bytes, then a zero byte.
    var name = product_name.as_bytes()
    var count = min(len(name), available - 1)
    for index in range(count):
        guid.data[4 + index] = name[index]
    return guid


def create_joystick_guid_for_name(name: String) raises -> JoystickGuid:
    """Make the GUID of a device known only by its name. SDL:
    `SDL_CreateJoystickGUIDForName`.

    Args:
        name: The device's name.

    Returns:
        The GUID: an unknown bus, the name's CRC and its first bytes.

    Raises:
        Error: Never, since every argument is in range.
    """
    return create_joystick_guid(
        BUS_UNKNOWN,
        VendorId(0),
        ProductId(0),
        0,
        "",
        name,
        DRIVER_NONE,
        0,
    )


def joystick_guid_info(guid: JoystickGuid) -> JoystickGuidInfo:
    """Return the vendor, product, version and CRC a GUID holds. SDL:
    `SDL_GetJoystickGUIDInfo`.

    Args:
        guid: The GUID.

    Returns:
        All four for the standard form. Only the CRC for the name form.
        Zeros for a GUID in neither form.
    """
    var bus = guid.word(0)
    var standard_bus = bus < 32 or bus == BUS_VIRTUAL.value
    if standard_bus and guid.word(3) == 0 and guid.word(5) == 0:
        return JoystickGuidInfo(
            VendorId(guid.word(2)),
            ProductId(guid.word(4)),
            guid.word(6),
            UInt16(guid.word(1)),
        )
    if standard_bus:
        return JoystickGuidInfo(
            VendorId(0), ProductId(0), 0, UInt16(guid.word(1))
        )
    return JoystickGuidInfo(VendorId(0), ProductId(0), 0, 0)


def joystick_guid_uses_version(guid: JoystickGuid) -> Bool:
    """Return True if a GUID's version word is a version. SDL:
    `SDL_JoystickGUIDUsesVersion`.

    Args:
        guid: The GUID.

    Returns:
        Whether the GUID has a vendor and a product and is not from the
        MFi driver, which keeps a button mask there.
    """
    if guid.driver() == DRIVER_MFI:
        return False
    var info = joystick_guid_info(guid)
    return info.vendor.value != 0 and info.product.value != 0


def is_special_guid_name(text: String) -> Bool:
    """Return True if a mapping's GUID field is a name rather than digits.

    Args:
        text: The GUID field of a mapping.

    Returns:
        Whether it is `default` or `xinput`, ignoring case.
    """
    return equal_ignoring_case(text, "default") or equal_ignoring_case(
        text, "xinput"
    )
