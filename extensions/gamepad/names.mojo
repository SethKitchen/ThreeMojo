# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of src/SDL_utils.c (SDL_CreateDeviceName)
# and the device lists and naming functions of src/joystick/SDL_joystick.c and
# src/joystick/SDL_gamepad.c, from SDL 3.2.24. It is a translation from C to
# Mojo. It is not the original software. The original notice follows.
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

"""The name SDL gives a device, and the devices it does not treat as one.

`create_joystick_name` cleans the name a driver reports. It drops
repeated spaces and repeated maker names, and shortens some makers: a
"HORI CO.,LTD. HORIPAD S" becomes "HORIPAD S". A controller in SDL's table
gets the table's name.

`should_ignore_joystick` refuses keyboards and mice that report joystick
buttons, motion sensors and Wii extensions that come as devices of their
own, and the Steam virtual gamepad. SDL's hints that add to or change
these lists are not ported.
"""
from extensions.gamepad.controller_type import (
    gamepad_type_from_vidpid,
    guess_controller_name,
)
from extensions.gamepad.guid import ProductId, VendorId
from extensions.gamepad.ids import (
    GAMEPAD_TYPE_NINTENDO_SWITCH_PRO,
    GAMEPAD_TYPE_PS3,
    GAMEPAD_TYPE_PS4,
    GAMEPAD_TYPE_PS5,
    GAMEPAD_TYPE_XBOX360,
    GAMEPAD_TYPE_XBOXONE,
)


def _lower(byte: UInt8) -> UInt8:
    """Return a byte in lowercase, if it is an uppercase ASCII letter.

    Args:
        byte: The byte.

    Returns:
        The lowercase byte, or the byte as it was.
    """
    if byte >= 65 and byte <= 90:
        return byte + 32
    return byte


def hex4(value: Int) -> String:
    """Return a 16-bit value as four lowercase hex digits.

    Args:
        value: A value from 0 to 65535.

    Returns:
        The digits, as C's `%.4x` writes them.
    """
    var digits = "0123456789abcdef".as_bytes()
    var text = List[UInt8](capacity=4)
    for shift in [12, 8, 4, 0]:  # pragma: no branch
        text.append(digits[(value >> shift) & 0xF])
    return String(unsafe_from_utf8=text)


def _starts_ignoring_case(name: List[UInt8], prefix: String) -> Bool:
    """Return True if bytes start with a prefix, ignoring ASCII case.

    Args:
        name: The bytes.
        prefix: The prefix.

    Returns:
        Whether the first bytes equal the prefix's, ignoring case.
    """
    var head = prefix.as_bytes()
    if len(head) > len(name):
        return False
    for index in range(len(head)):  # pragma: no branch
        if _lower(name[index]) != _lower(head[index]):
            return False
    return True


def _prefix_match(name: List[UInt8], start: Int) -> Int:
    """Return how many bytes from `start` match the start of the name.
    SDL: `PrefixMatch`.

    Args:
        name: The name's bytes.
        start: Where the second string starts.

    Returns:
        The length of the common prefix, ignoring case. "HORI " against
        "HORl " counts as 5, to fix the name of one HORI drum.
    """
    var hori = "HORI ".as_bytes()
    var horl = "HORl ".as_bytes()
    if len(name) - start >= 5:
        var both = True
        for index in range(5):
            if name[index] != hori[index] or name[start + index] != horl[index]:
                both = False
        if both:
            return 5
    var count = 0
    while start + count < len(name):
        if _lower(name[count]) != _lower(name[start + count]):
            break
        count += 1
    return count


def _strip_leading_spaces(text: String) -> String:
    """Return a string without its leading spaces.

    Args:
        text: The string.

    Returns:
        The string from its first byte that is not a space.
    """
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes) and bytes[index] == 32:
        index += 1
    return String(text[byte=index:])


def _type_name(vendor: VendorId, product: ProductId) -> String:
    """Return a name for a device with only a vendor and a product.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        A name from the kind of gamepad, or `0xVVVV/0xPPPP`.
    """
    var type = gamepad_type_from_vidpid(vendor, product, "", True)
    if type == GAMEPAD_TYPE_XBOX360:
        return "Xbox 360 Controller"
    if type == GAMEPAD_TYPE_XBOXONE:
        return "Xbox One Controller"
    if type == GAMEPAD_TYPE_PS3:
        return "PS3 Controller"
    if type == GAMEPAD_TYPE_PS4:
        return "PS4 Controller"
    if type == GAMEPAD_TYPE_PS5:
        return "DualSense Wireless Controller"
    if type == GAMEPAD_TYPE_NINTENDO_SWITCH_PRO:
        return "Nintendo Switch Pro Controller"
    return "0x" + hex4(vendor.value) + "/0x" + hex4(product.value)


def _replacements() -> List[String]:
    """Return SDL's maker prefixes and their replacements, in pairs.

    Returns:
        Each prefix, then its replacement.
    """
    return [
        "8BitDo Tech Ltd",
        "8BitDo",
        "ASTRO Gaming",
        "ASTRO",
        "Bensussen Deutsch & Associates,Inc.(BDA)",
        "BDA",
        "Guangzhou Chicken Run Network Technology Co., Ltd.",
        "GameSir",
        "HORI CO.,LTD.",
        "HORI",
        "HORI CO.,LTD",
        "HORI",
        "Mad Catz Inc.",
        "Mad Catz",
        "Nintendo Co., Ltd.",
        "Nintendo",
        "NVIDIA Corporation ",
        "",
        "Performance Designed Products",
        "PDP",
        "QANBA USA, LLC",
        "Qanba",
        "QANBA USA,LLC",
        "Qanba",
        "Unknown ",
        "",
    ]


def create_device_name(
    vendor: VendorId,
    product: ProductId,
    vendor_name: String,
    product_name: String,
    default_name: String,
) -> String:
    """Return a clean name for a device. SDL: `SDL_CreateDeviceName`.

    Args:
        vendor: The USB vendor id, or 0.
        product: The USB product id, or 0.
        vendor_name: The maker's name, or empty.
        product_name: The product's name, or empty.
        default_name: The name when nothing else is known.

    Returns:
        The name, with trailing and repeated spaces removed, a known
        maker shortened, and a maker's name said twice said once.
    """
    var maker = _strip_leading_spaces(vendor_name)
    var item = _strip_leading_spaces(product_name)
    var text: String
    if maker.byte_length() > 0 and item.byte_length() > 0:
        text = maker + " " + item
    elif item.byte_length() > 0:
        text = item
    elif vendor.value != 0 or product.value != 0:
        text = _type_name(vendor, product)
    else:
        text = default_name
    var name = List[UInt8](text.as_bytes())
    while len(name) > 0 and name[len(name) - 1] == 32:
        _ = name.pop()
    var index = 0
    while index + 1 < len(name):
        if name[index] == 32 and name[index + 1] == 32:
            _ = name.pop(index)
        else:
            index += 1
    var pairs = _replacements()
    for pair in range(0, len(pairs), 2):  # pragma: no branch
        if _starts_ignoring_case(name, pairs[pair]):
            var cut = pairs[pair].byte_length()
            var kept = List[UInt8](pairs[pair + 1].as_bytes())
            for byte in range(cut, len(name)):
                kept.append(name[byte])
            name = kept^
            break
    var at = 1
    while at + 1 < len(name):
        var length = _prefix_match(name, at)
        while length > 0:
            if name[length] == 32 or name[length] == 45:
                var kept = List[UInt8]()
                for byte in range(length + 1, len(name)):
                    kept.append(name[byte])
                name = kept^
                break
            length -= 1
        if length > 0:
            break
        at += 1
    return String(unsafe_from_utf8=name)


def create_joystick_name(
    vendor: VendorId,
    product: ProductId,
    vendor_name: String,
    product_name: String,
) -> String:
    """Return the name SDL gives a joystick. SDL: `SDL_CreateJoystickName`.

    Args:
        vendor: The USB vendor id, or 0.
        product: The USB product id, or 0.
        vendor_name: The maker's name, or empty.
        product_name: The product's name, or empty.

    Returns:
        The table's name for a known controller, or a clean name.
    """
    var known = guess_controller_name(vendor, product)
    if known.byte_length() > 0:
        return known
    return create_device_name(
        vendor, product, vendor_name, product_name, "Controller"
    )


def _in_list(vendor: VendorId, product: ProductId, ids: List[Int]) -> Bool:
    """Return True if a vendor and product pair is in a list.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.
        ids: Each pair as `vendor << 16 | product`.

    Returns:
        Whether the pair is in the list.
    """
    var key = (vendor.value << 16) | product.value
    for id in ids:  # pragma: no branch
        if id == key:
            return True
    return False


def _blocked_devices() -> List[Int]:
    """Return the keyboards, mice and tablets SDL never treats as
    joysticks.

    Returns:
        SDL's `initial_blacklist_devices`, each as `vendor << 16 | product`.
    """
    return [
        0x045E009D,
        0x045E00B0,
        0x045E00B4,
        0x045E0730,
        0x045E0745,
        0x045E0748,
        0x045E0750,
        0x045E0768,
        0x045E0773,
        0x045E07A5,
        0x045E07B2,
        0x045E0800,
        0x046DC30A,
        0x04D9A0DF,
        0x056A0010,
        0x056A0011,
        0x056A0012,
        0x056A0013,
        0x056A0014,
        0x056A0015,
        0x056A0016,
        0x056A0017,
        0x056A0018,
        0x056A0019,
        0x056A00D1,
        0x056A030E,
        0x09DA054F,
        0x09DA1410,
        0x09DA3043,
        0x09DA31B5,
        0x09DA3997,
        0x09DA3F8B,
        0x09DA51F4,
        0x09DA5589,
        0x09DA7B22,
        0x09DA7F2D,
        0x09DA8090,
        0x09DA9033,
        0x09DA9066,
        0x09DA9090,
        0x09DA90C0,
        0x09DAF012,
        0x09DAF32A,
        0x09DAF613,
        0x09DAF624,
        0x1B1C1B3C,
        0x1D57AD03,
        0x1E7D2E4A,
        0x20A0422D,
        0x2516001F,
        0x25160028,
        0x04D98008,
        0x04D98009,
        0x04D9A292,
        0x04D9A293,
        0x15320266,
        0x15320282,
        0x26CE01A2,
        0x20D60002,
        0x34340211,
        0x04F2A13C,
    ]


def _rog_mice() -> List[Int]:
    """Return the ASUS ROG mice that report gamepad buttons.

    Returns:
        SDL's `initial_rog_gamepad_mice`, each as `vendor << 16 | product`.
    """
    return [
        0x0B0518E3,
        0x0B0518E5,
        0x0B051906,
        0x0B051958,
        0x0B051A18,
        0x0B051A1A,
        0x0B051A1C,
    ]


def should_ignore_gamepad(
    vendor: VendorId, product: ProductId, version: Int, name: String
) -> Bool:
    """Return True if SDL does not treat a device as a gamepad. SDL:
    `SDL_ShouldIgnoreGamepad`, as on Linux, without its hints.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.
        version: The product version.
        name: The device's name.

    Returns:
        Whether it is a motion sensor, a Wii extension, a fingerprint
        sensor or the Steam virtual gamepad.
    """
    _ = version
    if name.endswith(" Motion Sensors"):
        return True
    if name.startswith("Nintendo ") and name.find(" IMU") >= 0:
        return True
    if (
        name.endswith(" Accelerometer")
        or name.endswith(" IR")
        or name.endswith(" Motion Plus")
        or name.endswith(" Nunchuk")
    ):
        return True
    if name.startswith("uinput-"):
        return True
    # The Steam virtual gamepad: Valve 0x11ff, unless a hint allows it.
    return vendor.value == 0x28DE and product.value == 0x11FF


def should_ignore_joystick(
    vendor: VendorId, product: ProductId, version: Int, name: String
) -> Bool:
    """Return True if SDL does not treat a device as a joystick. SDL:
    `SDL_ShouldIgnoreJoystick`, without its hints.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.
        version: The product version.
        name: The device's name.

    Returns:
        Whether the device is on SDL's block list, is a ROG mouse, or is
        a device SDL does not treat as a gamepad.
    """
    if _in_list(vendor, product, _blocked_devices()):
        return True
    if _in_list(vendor, product, _rog_mice()):
        return True
    return should_ignore_gamepad(vendor, product, version, name)
