# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of src/joystick/controller_type.c,
# src/joystick/controller_list.h and the gamepad type functions of
# src/joystick/SDL_joystick.c, from SDL 3.2.24. It is a translation from C to
# Mojo. It is not the original software. The original notice follows.
#
#   Copyright (C) Valve Corporation (controller_list.h)
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

"""Which controller a USB vendor and product id name.

`guess_controller_type` looks a vendor and product up in SDL's table of
539 known controllers. `gamepad_type_from_vidpid` turns that into a
`GamepadType`, which sets the face button labels. A DualSense is
`GAMEPAD_TYPE_PS5`, so its south button is labeled Cross.

SDL's hint `SDL_HINT_GAMECONTROLLERTYPE`, which overrides the table, is
not ported. The table is SDL 3.2.24's.
"""
from extensions.gamepad.guid import (
    DRIVER_XINPUT,
    JoystickGuid,
    ProductId,
    VendorId,
    joystick_guid_info,
)
from extensions.gamepad.ids import (
    GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT,
    GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR,
    GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT,
    GAMEPAD_TYPE_NINTENDO_SWITCH_PRO,
    GAMEPAD_TYPE_PS3,
    GAMEPAD_TYPE_PS4,
    GAMEPAD_TYPE_PS5,
    GAMEPAD_TYPE_STANDARD,
    GAMEPAD_TYPE_XBOX360,
    GAMEPAD_TYPE_XBOXONE,
    GamepadType,
)

comptime USB_VENDOR_MICROSOFT = VendorId(0x045E)
comptime USB_VENDOR_NINTENDO = VendorId(0x057E)
comptime USB_VENDOR_SONY = VendorId(0x054C)
comptime USB_PRODUCT_NINTENDO_SWITCH_JOYCON_GRIP = ProductId(0x200E)
comptime USB_PRODUCT_NINTENDO_SWITCH_JOYCON_LEFT = ProductId(0x2006)
comptime USB_PRODUCT_NINTENDO_SWITCH_JOYCON_PAIR = ProductId(0x2008)
comptime USB_PRODUCT_NINTENDO_SWITCH_JOYCON_RIGHT = ProductId(0x2007)


@fieldwise_init
struct ControllerType(Equatable, ImplicitlyCopyable, Writable):
    """Valve's model of a controller. SDL: `EControllerType`.

    The values are stored in Steam's database, so they are not in order
    and have gaps, as in SDL.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the named models.

        Returns:
            Whether the value is -1 to 4, or 30 to 46.
        """
        return (self.value >= -1 and self.value <= 4) or (
            self.value >= 30 and self.value <= 46
        )


comptime CONTROLLER_NONE = ControllerType(-1)
comptime CONTROLLER_UNKNOWN = ControllerType(0)
comptime CONTROLLER_UNKNOWN_STEAM = ControllerType(1)
comptime CONTROLLER_STEAM = ControllerType(2)
comptime CONTROLLER_STEAM_V2 = ControllerType(3)
comptime CONTROLLER_STEAM_NEPTUNE = ControllerType(4)
comptime CONTROLLER_UNKNOWN_NON_STEAM = ControllerType(30)
comptime CONTROLLER_XBOX360 = ControllerType(31)
comptime CONTROLLER_XBOXONE = ControllerType(32)
comptime CONTROLLER_PS3 = ControllerType(33)
comptime CONTROLLER_PS4 = ControllerType(34)
comptime CONTROLLER_WII = ControllerType(35)
comptime CONTROLLER_APPLE = ControllerType(36)
comptime CONTROLLER_ANDROID = ControllerType(37)
comptime CONTROLLER_SWITCH_PRO = ControllerType(38)
comptime CONTROLLER_SWITCH_JOYCON_LEFT = ControllerType(39)
comptime CONTROLLER_SWITCH_JOYCON_RIGHT = ControllerType(40)
comptime CONTROLLER_SWITCH_JOYCON_PAIR = ControllerType(41)
comptime CONTROLLER_SWITCH_INPUT_ONLY = ControllerType(42)
comptime CONTROLLER_MOBILE_TOUCH = ControllerType(43)
comptime CONTROLLER_XINPUT_SWITCH = ControllerType(44)
comptime CONTROLLER_PS5 = ControllerType(45)
comptime CONTROLLER_XINPUT_PS4 = ControllerType(46)


def _row_index(vendor: VendorId, product: ProductId) -> Int:
    """Return the first table row for a vendor and product.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        The row, or -1 when the table has none.
    """
    var key = (vendor.value << 16) | product.value
    var rows = _controller_rows()
    for index in range(len(rows)):  # pragma: no branch
        if rows[index] >> 8 == key:
            return index
    return -1


def guess_controller_type(
    vendor: VendorId, product: ProductId
) -> ControllerType:
    """Return the model of a controller. SDL: `GuessControllerType`.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        The model, or `CONTROLLER_UNKNOWN_NON_STEAM` when the table does
        not have it.
    """
    var index = _row_index(vendor, product)
    if index < 0:
        return CONTROLLER_UNKNOWN_NON_STEAM
    return ControllerType(_controller_rows()[index] & 0xFF)


def guess_controller_name(vendor: VendorId, product: ProductId) -> String:
    """Return the name SDL gives a controller. SDL: `GuessControllerName`.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        The name, or an empty string when the table has no name for it.
    """
    var index = _row_index(vendor, product)
    if index < 0:
        return ""
    return _controller_names()[index]


def is_joystick_gamecube(vendor: VendorId, product: ProductId) -> Bool:
    """Return True if a controller is shaped like a GameCube controller.
    SDL: `SDL_IsJoystickGameCube`, without its hints.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        Whether it is the PDP Wired Fight Pad Pro or the PowerA GameCube
        Style controller.
    """
    return (vendor.value == 0x0E6F and product.value == 0x0185) or (
        vendor.value == 0x20D6 and product.value == 0xA711
    )


def _name_is(name: String, a: String, b: String, c: String) -> Bool:
    """Return True if a name is one of three.

    Args:
        name: The name.
        a: The first choice.
        b: The second choice.
        c: The third choice.

    Returns:
        Whether the name equals one of them.
    """
    return name == a or name == b or name == c


def gamepad_type_from_vidpid(
    vendor: VendorId, product: ProductId, name: String, for_ui: Bool
) -> GamepadType:
    """Return the kind of gamepad a vendor and product id name. SDL:
    `SDL_GetGamepadTypeFromVIDPID`.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.
        name: The device's name, or empty. Some clones are known by name.
        for_ui: Whether the type is for showing labels. Then a
            controller in XInput mode keeps the look of its maker.

    Returns:
        The type, `GAMEPAD_TYPE_STANDARD` when nothing more is known.
    """
    if vendor.value == 0 and product.value == 0:
        if _name_is(
            name,
            "Lic Pro Controller",
            "Nintendo Wireless Gamepad",
            "Wireless Gamepad",
        ):
            return GAMEPAD_TYPE_NINTENDO_SWITCH_PRO
        return GAMEPAD_TYPE_STANDARD
    if vendor.value == 1 and product.value == 1:
        return GAMEPAD_TYPE_STANDARD
    if vendor == USB_VENDOR_NINTENDO:
        if product == USB_PRODUCT_NINTENDO_SWITCH_JOYCON_LEFT:
            return GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT
        if product == USB_PRODUCT_NINTENDO_SWITCH_JOYCON_RIGHT:
            if name.find("NES Controller") >= 0:
                return GAMEPAD_TYPE_STANDARD
            return GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT
        if product == USB_PRODUCT_NINTENDO_SWITCH_JOYCON_GRIP:
            if name.find("(L)") >= 0:
                return GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT
            return GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT
        if product == USB_PRODUCT_NINTENDO_SWITCH_JOYCON_PAIR:
            return GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR
    if for_ui and is_joystick_gamecube(vendor, product):
        return GAMEPAD_TYPE_STANDARD
    var model = guess_controller_type(vendor, product)
    if model == CONTROLLER_XBOX360:
        return GAMEPAD_TYPE_XBOX360
    if model == CONTROLLER_XBOXONE:
        return GAMEPAD_TYPE_XBOXONE
    if model == CONTROLLER_PS3:
        return GAMEPAD_TYPE_PS3
    if model == CONTROLLER_PS4:
        return GAMEPAD_TYPE_PS4
    if model == CONTROLLER_PS5:
        return GAMEPAD_TYPE_PS5
    if model == CONTROLLER_XINPUT_PS4 and for_ui:
        return GAMEPAD_TYPE_PS4
    if model == CONTROLLER_SWITCH_PRO or model == CONTROLLER_SWITCH_INPUT_ONLY:
        return GAMEPAD_TYPE_NINTENDO_SWITCH_PRO
    if model == CONTROLLER_XINPUT_SWITCH and for_ui:
        return GAMEPAD_TYPE_NINTENDO_SWITCH_PRO
    return GAMEPAD_TYPE_STANDARD


def gamepad_type_from_guid(guid: JoystickGuid, name: String) -> GamepadType:
    """Return the kind of gamepad a GUID names. SDL:
    `SDL_GetGamepadTypeFromGUID`, without the HIDAPI driver.

    Args:
        guid: The joystick's GUID.
        name: The joystick's name.

    Returns:
        The type for showing labels. A standard XInput device is
        `GAMEPAD_TYPE_XBOXONE`.
    """
    var info = joystick_guid_info(guid)
    var type = gamepad_type_from_vidpid(info.vendor, info.product, name, True)
    if type == GAMEPAD_TYPE_STANDARD and guid.driver() == DRIVER_XINPUT:
        return GAMEPAD_TYPE_XBOXONE
    return type


def _controller_rows() -> List[Int]:
    """Return each known controller as `vendor << 24 | product << 8 | type`.

    Returns:
        SDL's `arrControllers`, in its order.
    """
    return [
        0x0079181A21,
        0x044FB31521,
        0x044FD00721,
        0x046DCAD121,
        0x054C026821,
        0x056E200F21,
        0x056E201321,
        0x05B8100421,
        0x05B8100621,
        0x06A3F62221,
        0x0738318021,
        0x0738325021,
        0x0738348121,
        0x0738818021,
        0x0738883821,
        0x0810000121,
        0x0810000321,
        0x0925000521,
        0x0925886621,
        0x0925888821,
        0x0E6F010921,
        0x0E6F011E21,
        0x0E6F012821,
        0x0E6F021421,
        0x0E6F131421,
        0x0E6F630221,
        0x0E8F000821,
        0x0E8F307521,
        0x0E8F310D21,
        0x0F0D000921,
        0x0F0D004D21,
        0x0F0D005F21,
        0x0F0D006A21,
        0x0F0D006E21,
        0x0F0D008521,
        0x0F0D008621,
        0x0F0D008821,
        0x0F30110021,
        0x11FF333121,
        0x1345100021,
        0x1345600521,
        0x146B550021,
        0x1A34083621,
        0x20BC550021,
        0x20D6576D21,
        0x20D6CA6D21,
        0x2563052321,
        0x2563057521,
        0x25F083C321,
        0x25F0C12121,
        0x2C22200321,
        0x2C22230221,
        0x2C22250221,
        0x8380000321,
        0x8888030821,
        0x0079181B22,
        0x044FD00E22,
        0x054C05C422,
        0x054C05C522,
        0x054C09CC22,
        0x054C0BA022,
        0x0738825022,
        0x0738838422,
        0x0738848022,
        0x0738848122,
        0x0C120E1022,
        0x0C120E1322,
        0x0C120E1522,
        0x0C120E2022,
        0x0C120EF622,
        0x0C121CF622,
        0x0C121E1022,
        0x0C122E1822,
        0x0E6F020322,
        0x0E6F020722,
        0x0E6F020A22,
        0x0F0D005522,
        0x0F0D005E22,
        0x0F0D006622,
        0x0F0D008422,
        0x0F0D008722,
        0x0F0D008A22,
        0x0F0D009C22,
        0x0F0D00A022,
        0x0F0D00ED2E,
        0x0F0D00EE22,
        0x0F0D011C22,
        0x0F0D012322,
        0x0F0D016222,
        0x0F0D01642E,
        0x11C0400122,
        0x146B06032E,
        0x146B06042E,
        0x146B06052E,
        0x146B06062E,
        0x146B06092E,
        0x146B0D0122,
        0x146B0D0222,
        0x146B0D0622,
        0x146B0D0822,
        0x146B0D0922,
        0x146B0D1022,
        0x146B0D1022,
        0x146B0D1322,
        0x146B110322,
        0x1532100022,
        0x1532100422,
        0x1532100722,
        0x1532100822,
        0x1532100922,
        0x1532100A22,
        0x1532110022,
        0x20D6792A22,
        0x2C22200022,
        0x2C22230022,
        0x2C2223032E,
        0x2C22250022,
        0x2C2225032E,
        0x32850D1622,
        0x32850D1722,
        0x7545010422,
        0x9886002522,
        0x054C0CE62D,
        0x054C0DF22D,
        0x054C0E5F2D,
        0x0E6F02092D,
        0x0F0D01632D,
        0x0F0D01842D,
        0x1532100B2D,
        0x1532100C2D,
        0x153210122D,
        0x32850D182D,
        0x32850D192D,
        0x358A01042D,
        0x007900061E,
        0x007918D41F,
        0x03EBFF021F,
        0x044FB3261F,
        0x045E028E1F,
        0x045E028F1F,
        0x045E02911F,
        0x045E02A01F,
        0x045E02A11F,
        0x045E02A91F,
        0x045E07191F,
        0x046DC21D1F,
        0x046DC21E1F,
        0x046DC21F1F,
        0x046DC2421F,
        0x056E20041F,
        0x073847161F,
        0x073847181F,
        0x073847261F,
        0x073847281F,
        0x073847361F,
        0x073847381F,
        0x073847401F,
        0x0738B7261F,
        0x0738BEEF1F,
        0x0738CB021F,
        0x0738CB031F,
        0x0738F7381F,
        0x095572101F,
        0x0955B4001F,
        0x0B051B4C1F,
        0x0E6F01051F,
        0x0E6F01131F,
        0x0E6F011F1F,
        0x0E6F01251F,
        0x0E6F01271F,
        0x0E6F01311F,
        0x0E6F01331F,
        0x0E6F01431F,
        0x0E6F01471F,
        0x0E6F02011F,
        0x0E6F02131F,
        0x0E6F021F1F,
        0x0E6F03011F,
        0x0E6F03131F,
        0x0E6F03141F,
        0x0E6F04011F,
        0x0E6F04131F,
        0x0E6F05011F,
        0x0E6FF9001F,
        0x0F0D000A1F,
        0x0F0D000C1F,
        0x0F0D000D1F,
        0x0F0D00161F,
        0x0F0D001B1F,
        0x0F0D008C1F,
        0x0F0D00DB1F,
        0x0F0D011E1F,
        0x103814301F,
        0x103814311F,
        0x1038B3601F,
        0x11C955F01F,
        0x12AB00041F,
        0x12AB03011F,
        0x12AB03031F,
        0x143002A01F,
        0x143047481F,
        0x1430F8011F,
        0x146B06011F,
        0x15E43F001F,
        0x15E43F0A1F,
        0x15E43F101F,
        0x162EBEEF1F,
        0x1689FD001F,
        0x1689FD011F,
        0x1689FE001F,
        0x1949041A1F,
        0x1BAD00021F,
        0x1BAD00031F,
        0x1BADF0161F,
        0x1BADF0181F,
        0x1BADF0191F,
        0x1BADF0211F,
        0x1BADF0231F,
        0x1BADF0251F,
        0x1BADF0271F,
        0x1BADF0281F,
        0x1BADF02E1F,
        0x1BADF0361F,
        0x1BADF0381F,
        0x1BADF0391F,
        0x1BADF03A1F,
        0x1BADF03D1F,
        0x1BADF03E1F,
        0x1BADF03F1F,
        0x1BADF0421F,
        0x1BADF0801F,
        0x1BADF5011F,
        0x1BADF5021F,
        0x1BADF5031F,
        0x1BADF5041F,
        0x1BADF5051F,
        0x1BADF5061F,
        0x1BADF9001F,
        0x1BADF9011F,
        0x1BADF9021F,
        0x1BADF9031F,
        0x1BADF9041F,
        0x1BADF9061F,
        0x1BADFA011F,
        0x1BADFD001F,
        0x1BADFD011F,
        0x24C650001F,
        0x24C653001F,
        0x24C653031F,
        0x24C6530A1F,
        0x24C6531A1F,
        0x24C653971F,
        0x24C655001F,
        0x24C655011F,
        0x24C655021F,
        0x24C655031F,
        0x24C655061F,
        0x24C6550D1F,
        0x24C6550E1F,
        0x24C655081F,
        0x24C655101F,
        0x24C65B001F,
        0x24C65B021F,
        0x24C65B031F,
        0x24C65D041F,
        0x24C6FAFA1F,
        0x24C6FAFB1F,
        0x24C6FAFC1F,
        0x24C6FAFD1F,
        0x24C6FAFE1F,
        0x03F0049520,
        0x044FD01220,
        0x045E02D120,
        0x045E02DD20,
        0x045E02E020,
        0x045E02E320,
        0x045E02EA20,
        0x045E02FD20,
        0x045E02FF20,
        0x045E0B0020,
        0x045E0B0520,
        0x045E0B0A20,
        0x045E0B0C20,
        0x045E0B1220,
        0x045E0B1320,
        0x045E0B2020,
        0x045E0B2120,
        0x045E0B2220,
        0x07384A0120,
        0x0E6F013920,
        0x0E6F013B20,
        0x0E6F013A20,
        0x0E6F014520,
        0x0E6F014620,
        0x0E6F015B20,
        0x0E6F015C20,
        0x0E6F015D20,
        0x0E6F015F20,
        0x0E6F016020,
        0x0E6F016120,
        0x0E6F016220,
        0x0E6F016320,
        0x0E6F016420,
        0x0E6F016520,
        0x0E6F016620,
        0x0E6F016720,
        0x0E6F020520,
        0x0E6F020620,
        0x0E6F024620,
        0x0E6F026120,
        0x0E6F026220,
        0x0E6F02A020,
        0x0E6F02A120,
        0x0E6F02A220,
        0x0E6F02A320,
        0x0E6F02A420,
        0x0E6F02A520,
        0x0E6F02A620,
        0x0E6F02A720,
        0x0E6F02A820,
        0x0E6F02A920,
        0x0E6F02AA20,
        0x0E6F02AB20,
        0x0E6F02AC20,
        0x0E6F02AD20,
        0x0E6F02AE20,
        0x0E6F02AF20,
        0x0E6F02B020,
        0x0E6F02B120,
        0x0E6F02B320,
        0x0E6F02B520,
        0x0E6F02B620,
        0x0E6F02BD20,
        0x0E6F02BE20,
        0x0E6F02BF20,
        0x0E6F02C020,
        0x0E6F02C120,
        0x0E6F02C220,
        0x0E6F02C320,
        0x0E6F02C420,
        0x0E6F02C520,
        0x0E6F02C620,
        0x0E6F02C720,
        0x0E6F02C820,
        0x0E6F02C920,
        0x0E6F02CA20,
        0x0E6F02CB20,
        0x0E6F02CD20,
        0x0E6F02CE20,
        0x0E6F02CF20,
        0x0E6F02D520,
        0x0E6F034620,
        0x0E6F044620,
        0x0E6F02DA20,
        0x0E6F02D620,
        0x0E6F02D920,
        0x0F0D006320,
        0x0F0D006720,
        0x0F0D007820,
        0x0F0D00C520,
        0x0F0D015020,
        0x10F5700920,
        0x10F5701320,
        0x15320A0020,
        0x15320A0320,
        0x15320A1420,
        0x15320A1520,
        0x20D6200120,
        0x20D6200220,
        0x20D6200320,
        0x20D6200420,
        0x20D6200520,
        0x20D6200620,
        0x20D6200920,
        0x20D6200A20,
        0x20D6200B20,
        0x20D6200C20,
        0x20D6200D20,
        0x20D6200E20,
        0x20D6200F20,
        0x20D6201120,
        0x20D6201220,
        0x20D6201520,
        0x20D6201620,
        0x20D6201720,
        0x20D6201820,
        0x20D6201920,
        0x20D6201A20,
        0x20D6400120,
        0x20D6400220,
        0x20D6890B20,
        0x24C6541A20,
        0x24C6542A20,
        0x24C6543A20,
        0x24C6551A20,
        0x24C6561A20,
        0x24C6581A20,
        0x24C6591A20,
        0x24C6592A20,
        0x24C6791A20,
        0x2DC8200220,
        0x2DC8310620,
        0x2E24065220,
        0x2E24161820,
        0x2E24168820,
        0x146B061120,
        0x000000001F,
        0x045E02A21F,
        0x0E6F14141F,
        0x0E6F01591F,
        0x24C6FAFF1F,
        0x0F0D006D1F,
        0x0F0D00A41F,
        0x007918321F,
        0x0079187F1F,
        0x007918831F,
        0x03EBFF011F,
        0x0C120EF81F,
        0x046D10001F,
        0x11FF05111F,
        0x134560061F,
        0x056E20121F,
        0x146B06021F,
        0x0F0D00AE1F,
        0x046D04011F,
        0x046D03011F,
        0x046DCAA31F,
        0x046DC2611F,
        0x046D02911F,
        0x007918D31F,
        0x0F0D00B11F,
        0x000100011F,
        0x0079188E1F,
        0x0079187C1F,
        0x0079189C1F,
        0x007918741F,
        0x2F24005020,
        0x2F24002E20,
        0x2F24009120,
        0x1430071920,
        0x0F0D00ED20,
        0x0F0D00C020,
        0x0E6F015220,
        0x0E6F02A720,
        0x046D100720,
        0x0E6F02B820,
        0x0E6F02A820,
        0x007918A120,
        0x0000668620,
        0x12AB030420,
        0x1430029120,
        0x143002A920,
        0x1430070B20,
        0x1BAD028E20,
        0x1BAD02A020,
        0x1BAD550020,
        0x20AB55EF20,
        0x24C6550920,
        0x2516006920,
        0x25B1036020,
        0x2C22220320,
        0x2F24001120,
        0x2F24005320,
        0x2F2400B720,
        0x046D000020,
        0x046D100420,
        0x046D100820,
        0x046DF30120,
        0x073802A020,
        0x0738726320,
        0x0738B73820,
        0x0738CB2920,
        0x0738F40120,
        0x007918C220,
        0x007918C820,
        0x007918CF20,
        0x0C120E1720,
        0x0C120E1C20,
        0x0C120E2220,
        0x0C120E3020,
        0xD2D2D2D220,
        0x0D629A1A20,
        0x0D629A1B20,
        0x0E000E0020,
        0x0E6F012A20,
        0x0E6F02A120,
        0x0E6F02A220,
        0x0E6F02A520,
        0x0E6F02B220,
        0x0E6F02BD20,
        0x0E6F02BF20,
        0x0E6F02C020,
        0x0E6F02C620,
        0x0F0D009720,
        0x0F0D00BA20,
        0x0F0D00D820,
        0x0FFF02A120,
        0x045E086720,
        0x16D00F3F20,
        0x2F24008F20,
        0x0E6FF50120,
        0x05AC000124,
        0x05AC000224,
        0x057E200627,
        0x057E200728,
        0x057E200829,
        0x057E200926,
        0x0F0D00C12A,
        0x0F0D00922A,
        0x0F0D00F626,
        0x0F0D00DC2C,
        0x0E6F01802A,
        0x0E6F01812A,
        0x0E6F01842A,
        0x0E6F01852A,
        0x0E6F018626,
        0x0E6F01872A,
        0x0E6F01882A,
        0x0F0D00AA2A,
        0x20D6A7112A,
        0x20D6A7122A,
        0x20D6A7132A,
        0x20D6A7142A,
        0x20D6A7152A,
        0x20D6A7162A,
        0x20D6A7182A,
        0x33DD00012A,
        0x33DD00022A,
        0x33DD00032A,
        0x000011FB2B,
        0x28DE110102,
        0x28DE110202,
        0x28DE110502,
        0x28DE110602,
        0x28DE11FF1E,
        0x28DE114202,
        0x28DE120103,
        0x28DE120203,
        0x28DE120504,
    ]


def _controller_names() -> List[String]:
    """Return the name of each known controller, in the order of the rows.

    Returns:
        The names. An empty name is SDL's NULL.
    """
    return [
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "Retro-bit Controller",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "Xbox 360 Controller",
        "Xbox 360 Controller",
        "Xbox 360 Wireless Controller",
        "",
        "Xbox 360 Wireless Controller",
        "Xbox 360 Wireless Controller",
        "Xbox 360 Wireless Controller",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "PDP Xbox 360 Afterglow",
        "PDP Xbox 360 Rock Candy",
        "PDP INJUSTICE FightStick",
        "PDP INJUSTICE FightPad",
        "PDP EA Soccer Controller",
        "PDP Battlefield 4 Controller",
        "PDP MK X Fight Stick",
        "PDP Xbox 360 Marvel Controller",
        "PDP Xbox 360 Controller",
        "PDP Xbox 360 Afterglow",
        "PDP Xbox 360 Rock Candy",
        "PDP Xbox 360 Controller",
        "PDP Xbox 360 Afterglow",
        "PDP Xbox 360 Afterglow",
        "PDP Xbox 360 Controller",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "HORI Slime Controller",
        "",
        "SteelSeries Stratus Duo",
        "SteelSeries Stratus Duo",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "Amazon Luna Controller",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "Xbox One Controller",
        "Xbox One Controller",
        "Xbox One S Controller",
        "Xbox One Elite Controller",
        "Xbox One S Controller",
        "Xbox One S Controller",
        "Xbox One Controller",
        "Xbox One Elite 2 Controller",
        "Xbox One Elite 2 Controller",
        "Xbox Adaptive Controller",
        "Xbox Adaptive Controller",
        "Xbox Series X Controller",
        "Xbox Series X Controller",
        "Xbox One S Controller",
        "Xbox Adaptive Controller",
        "Xbox One Elite 2 Controller",
        "",
        "PDP Xbox One Afterglow",
        "PDP Xbox One Face-Off Controller",
        "",
        "PDP MK X Fight Pad",
        "PDP Xbox One Rock Candy",
        "PDP Fallout 4 Vault Boy Controller",
        "PDP Xbox One @Play Controller",
        "PDP Mirror's Edge Controller",
        "PDP Metallic Controller",
        "PDP NFL Face-Off Controller",
        "PDP Xbox One Camo",
        "PDP Xbox One Controller",
        "PDP Deliverer of Truth",
        "PDP Battlefield 1 Controller",
        "PDP Titanfall 2 Controller",
        "PDP Mass Effect: Andromeda Controller",
        "PDP Halo Wars 2 Face-Off Controller",
        "PDP Victrix Pro Fight Stick",
        "PDP Mortal Kombat Controller",
        "PDP Xbox One Rock Candy",
        "PDP Xbox One Camo",
        "PDP Xbox One Controller",
        "PDP Xbox One Midnight Blue",
        "PDP Xbox One Verdant Green",
        "PDP Xbox One Crimson Red",
        "PDP Xbox One Arctic White",
        "PDP Xbox One Phantom Black",
        "PDP Xbox One Ghost White",
        "PDP Xbox One Revenant Blue",
        "PDP Xbox One Raven Black",
        "PDP Xbox One Arctic White",
        "PDP Xbox One Midnight Blue",
        "PDP Xbox One Verdant Green",
        "PDP Xbox One Crimson Red",
        "PDP Xbox One Ember Orange",
        "PDP Xbox One Phantom Black",
        "PDP Xbox One Ghost White",
        "PDP Xbox One Revenant Blue",
        "PDP Xbox One Raven Black",
        "PDP Xbox One Arctic White",
        "PDP Xbox One Afterglow",
        "PDP Xbox One GAMEware Controller",
        "",
        "PDP Xbox One Royal Purple",
        "PDP Xbox One Raven Black",
        "PDP Xbox One Midnight Blue",
        "PDP Xbox One Phantom Black",
        "PDP Xbox One Ghost White",
        "PDP Xbox One Revenant Blue",
        "PDP Xbox One Verdant Green",
        "PDP Xbox One Ember Orange",
        "PDP Xbox One Royal Purple",
        "PDP Xbox One Crimson Red",
        "PDP Xbox One Arctic White",
        "PDP Kingdom Hearts Controller",
        "PDP Xbox One Phantasm Red",
        "PDP Xbox One Specter Violet",
        "PDP Xbox One Specter Violet",
        "PDP Xbox One Blu-merang",
        "PDP Xbox One Cranblast",
        "PDP Xbox One Aqualime",
        "PDP Xbox One Red Camo",
        "PDP Xbox One RC Gamepad",
        "PDP Xbox One RC Gamepad",
        "PDP Xbox Series X Afterglow",
        "Victrix Gambit Tournament Controller",
        "PDP Xbox Series X Midnight Blue",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Xbox Series X Controller",
        "PowerA Fusion Pro 2 Controller",
        "PowerA Spectra Infinity Controller",
        "",
        "",
        "",
        "PowerA Xbox One Controller",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
    ]
