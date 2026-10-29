# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the gamepad names, GUIDs, controller types and device names.

The expected GUIDs, CRCs and device names are the ones SDL 3.2.24 gives,
built from source and called with the same arguments. The PS5
controller's GUID `030000004c050000e60c000011010000` is the one in SDL's
own Linux mapping table.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.gamepad.controller_type import (
    CONTROLLER_NONE,
    CONTROLLER_PS3,
    CONTROLLER_PS4,
    CONTROLLER_PS5,
    CONTROLLER_STEAM_NEPTUNE,
    CONTROLLER_UNKNOWN_NON_STEAM,
    CONTROLLER_XBOX360,
    CONTROLLER_XBOXONE,
    CONTROLLER_XINPUT_PS4 as XINPUT_PS4,
    ControllerType,
    gamepad_type_from_guid,
    gamepad_type_from_vidpid,
    guess_controller_name,
    guess_controller_type,
    is_joystick_gamecube,
)
from extensions.gamepad.guid import (
    BUS_BLUETOOTH,
    BUS_USB,
    BUS_VIRTUAL,
    DRIVER_HIDAPI,
    DRIVER_MFI,
    DRIVER_NONE,
    DRIVER_XINPUT,
    DriverSignature,
    HardwareBus,
    JoystickGuid,
    ProductId,
    VendorId,
    crc16,
    create_joystick_guid,
    create_joystick_guid_for_name,
    guid_to_string,
    is_special_guid_name,
    joystick_guid_info,
    joystick_guid_uses_version,
    string_to_guid,
)
from extensions.gamepad.ids import (
    AXIS_INVALID,
    AXIS_LEFTX,
    AXIS_LEFT_TRIGGER,
    AXIS_RIGHT_TRIGGER,
    AXIS_RIGHTY,
    BUTTON_BACK,
    BUTTON_EAST,
    BUTTON_INVALID,
    BUTTON_MISC6,
    BUTTON_NORTH,
    BUTTON_SOUTH,
    BUTTON_WEST,
    FACE_STYLE_ABXY,
    FACE_STYLE_BAYX,
    FACE_STYLE_SONY,
    FACE_STYLE_UNKNOWN,
    GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT,
    GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR,
    GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT,
    GAMEPAD_TYPE_NINTENDO_SWITCH_PRO,
    GAMEPAD_TYPE_PS3,
    GAMEPAD_TYPE_PS4,
    GAMEPAD_TYPE_PS5,
    GAMEPAD_TYPE_STANDARD,
    GAMEPAD_TYPE_UNKNOWN,
    GAMEPAD_TYPE_XBOX360,
    GAMEPAD_TYPE_XBOXONE,
    FaceStyle,
    GamepadAxis,
    GamepadButton,
    GamepadButtonLabel,
    GamepadType,
    LABEL_A,
    LABEL_B,
    LABEL_CIRCLE,
    LABEL_CROSS,
    LABEL_SQUARE,
    LABEL_TRIANGLE,
    LABEL_UNKNOWN,
    LABEL_X,
    LABEL_Y,
    button_label_for_face_style,
    button_label_for_type,
    equal_ignoring_case,
    face_style_for_type,
    face_style_from_string,
    gamepad_axis_from_string,
    gamepad_button_from_string,
    gamepad_string_for_axis,
    gamepad_string_for_button,
    gamepad_string_for_type,
    gamepad_type_from_string,
    is_trigger,
    swap_face_button,
)
from extensions.gamepad.names import (
    create_device_name,
    create_joystick_name,
    hex4,
    should_ignore_gamepad,
    should_ignore_joystick,
)


def test_types_check_their_range() raises:
    assert_true(GamepadType(10).is_valid())
    assert_false(GamepadType(11).is_valid())
    assert_false(GamepadType(-1).is_valid())
    assert_true(GamepadButton(25).is_valid())
    assert_false(BUTTON_INVALID.is_valid())
    assert_false(GamepadButton(26).is_valid())
    assert_true(GamepadAxis(5).is_valid())
    assert_false(AXIS_INVALID.is_valid())
    assert_false(GamepadAxis(6).is_valid())
    assert_true(GamepadButtonLabel(8).is_valid())
    assert_false(GamepadButtonLabel(9).is_valid())
    assert_true(FaceStyle(3).is_valid())
    assert_false(FaceStyle(4).is_valid())
    assert_true(HardwareBus(0xFFFF).is_valid())
    assert_false(HardwareBus(0x10000).is_valid())
    assert_false(HardwareBus(-1).is_valid())
    assert_true(VendorId(0).is_valid())
    assert_false(VendorId(0x10000).is_valid())
    assert_false(VendorId(-1).is_valid())
    assert_true(ProductId(0xFFFF).is_valid())
    assert_false(ProductId(0x10000).is_valid())
    assert_false(ProductId(-1).is_valid())
    assert_true(DriverSignature(0xFF).is_valid())
    assert_false(DriverSignature(0x100).is_valid())
    assert_false(DriverSignature(-1).is_valid())
    assert_true(ControllerType(-1).is_valid())
    assert_true(ControllerType(4).is_valid())
    assert_false(ControllerType(5).is_valid())
    assert_false(ControllerType(29).is_valid())
    assert_true(ControllerType(30).is_valid())
    assert_true(ControllerType(46).is_valid())
    assert_false(ControllerType(47).is_valid())
    assert_false(ControllerType(-2).is_valid())
    assert_true(CONTROLLER_NONE.is_valid())


def test_names_ignore_case_only_for_ascii_letters() raises:
    assert_true(equal_ignoring_case("LeftX", "leftx"))
    assert_false(equal_ignoring_case("leftx", "left"))
    assert_false(equal_ignoring_case("a", "b"))
    assert_true(equal_ignoring_case("", ""))


def test_gamepad_types_round_trip_through_their_names() raises:
    assert_equal(gamepad_type_from_string("ps5"), GAMEPAD_TYPE_PS5)
    assert_equal(gamepad_type_from_string("+XboxOne"), GAMEPAD_TYPE_XBOXONE)
    assert_equal(gamepad_type_from_string("-ps4"), GAMEPAD_TYPE_PS4)
    assert_equal(gamepad_type_from_string("joyconpair"), GamepadType(10))
    assert_equal(gamepad_type_from_string("dreamcast"), GAMEPAD_TYPE_UNKNOWN)
    assert_equal(gamepad_type_from_string(""), GAMEPAD_TYPE_UNKNOWN)
    assert_equal(gamepad_string_for_type(GAMEPAD_TYPE_PS3), "ps3")
    assert_equal(gamepad_string_for_type(GAMEPAD_TYPE_STANDARD), "standard")
    assert_equal(gamepad_string_for_type(GAMEPAD_TYPE_UNKNOWN), "")
    assert_equal(gamepad_string_for_type(GamepadType(11)), "")


def test_buttons_round_trip_and_swap_for_labels() raises:
    assert_equal(gamepad_button_from_string("a"), BUTTON_SOUTH)
    assert_equal(gamepad_button_from_string("MISC6"), BUTTON_MISC6)
    assert_equal(gamepad_button_from_string("+a"), BUTTON_INVALID)
    assert_equal(gamepad_button_from_string(""), BUTTON_INVALID)
    assert_equal(gamepad_button_from_string("a", True), BUTTON_EAST)
    assert_equal(gamepad_button_from_string("b", True), BUTTON_SOUTH)
    assert_equal(gamepad_button_from_string("x", True), BUTTON_NORTH)
    assert_equal(gamepad_button_from_string("y", True), BUTTON_WEST)
    assert_equal(gamepad_button_from_string("back", True), BUTTON_BACK)
    assert_equal(swap_face_button(BUTTON_BACK), BUTTON_BACK)
    assert_equal(gamepad_string_for_button(BUTTON_WEST), "x")
    assert_equal(gamepad_string_for_button(GamepadButton(16)), "paddle1")
    assert_equal(gamepad_string_for_button(BUTTON_INVALID), "")


def test_axes_round_trip_and_name_the_triggers() raises:
    assert_equal(gamepad_axis_from_string("leftx"), AXIS_LEFTX)
    assert_equal(gamepad_axis_from_string("-righty"), AXIS_RIGHTY)
    assert_equal(gamepad_axis_from_string("+RightTrigger"), AXIS_RIGHT_TRIGGER)
    assert_equal(gamepad_axis_from_string("a"), AXIS_INVALID)
    assert_equal(gamepad_string_for_axis(AXIS_LEFT_TRIGGER), "lefttrigger")
    assert_equal(gamepad_string_for_axis(AXIS_INVALID), "")
    assert_true(is_trigger(AXIS_LEFT_TRIGGER))
    assert_true(is_trigger(AXIS_RIGHT_TRIGGER))
    assert_false(is_trigger(AXIS_LEFTX))


def test_face_styles_follow_the_type() raises:
    assert_equal(face_style_from_string("abxy"), FACE_STYLE_ABXY)
    assert_equal(face_style_from_string("bayx"), FACE_STYLE_BAYX)
    assert_equal(face_style_from_string("sony"), FACE_STYLE_SONY)
    assert_equal(face_style_from_string("SONY"), FACE_STYLE_UNKNOWN)
    assert_equal(face_style_for_type(GAMEPAD_TYPE_PS3), FACE_STYLE_SONY)
    assert_equal(face_style_for_type(GAMEPAD_TYPE_PS5), FACE_STYLE_SONY)
    assert_equal(
        face_style_for_type(GAMEPAD_TYPE_NINTENDO_SWITCH_PRO), FACE_STYLE_BAYX
    )
    assert_equal(
        face_style_for_type(GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR),
        FACE_STYLE_BAYX,
    )
    assert_equal(face_style_for_type(GAMEPAD_TYPE_XBOXONE), FACE_STYLE_ABXY)
    assert_equal(face_style_for_type(GAMEPAD_TYPE_UNKNOWN), FACE_STYLE_ABXY)
    assert_equal(face_style_for_type(GamepadType(11)), FACE_STYLE_ABXY)


def test_labels_name_the_printed_face_buttons() raises:
    assert_equal(
        button_label_for_type(GAMEPAD_TYPE_XBOX360, BUTTON_SOUTH), LABEL_A
    )
    assert_equal(
        button_label_for_type(GAMEPAD_TYPE_XBOXONE, BUTTON_EAST), LABEL_B
    )
    assert_equal(
        button_label_for_type(GAMEPAD_TYPE_XBOXONE, BUTTON_WEST), LABEL_X
    )
    assert_equal(
        button_label_for_type(GAMEPAD_TYPE_XBOXONE, BUTTON_NORTH), LABEL_Y
    )
    assert_equal(
        button_label_for_type(GAMEPAD_TYPE_PS5, BUTTON_SOUTH), LABEL_CROSS
    )
    assert_equal(
        button_label_for_type(GAMEPAD_TYPE_PS4, BUTTON_EAST), LABEL_CIRCLE
    )
    assert_equal(
        button_label_for_type(GAMEPAD_TYPE_PS4, BUTTON_WEST), LABEL_SQUARE
    )
    assert_equal(
        button_label_for_type(GAMEPAD_TYPE_PS4, BUTTON_NORTH), LABEL_TRIANGLE
    )
    var switch = GAMEPAD_TYPE_NINTENDO_SWITCH_PRO
    assert_equal(button_label_for_type(switch, BUTTON_SOUTH), LABEL_B)
    assert_equal(button_label_for_type(switch, BUTTON_EAST), LABEL_A)
    assert_equal(button_label_for_type(switch, BUTTON_WEST), LABEL_Y)
    assert_equal(button_label_for_type(switch, BUTTON_NORTH), LABEL_X)
    assert_equal(button_label_for_type(switch, BUTTON_BACK), LABEL_UNKNOWN)
    assert_equal(button_label_for_type(switch, BUTTON_INVALID), LABEL_UNKNOWN)
    assert_equal(
        button_label_for_face_style(FACE_STYLE_UNKNOWN, BUTTON_SOUTH),
        LABEL_UNKNOWN,
    )
    assert_equal(
        button_label_for_face_style(FaceStyle(9), BUTTON_SOUTH), LABEL_UNKNOWN
    )


def test_crc16_matches_the_reference_check_value() raises:
    # CRC-16/ARC of "123456789" is 0xBB3D.
    assert_equal(crc16(0, "123456789".as_bytes()), 0xBB3D)
    assert_equal(crc16(0, "".as_bytes()), 0)


def test_guid_text_round_trips() raises:
    var guid = string_to_guid("030000004c050000e60c000011010000")
    assert_equal(guid_to_string(guid), "030000004c050000e60c000011010000")
    var info = joystick_guid_info(guid)
    assert_equal(info.vendor, VendorId(0x054C))
    assert_equal(info.product, ProductId(0x0CE6))
    assert_equal(info.version, 0x0111)
    assert_equal(info.crc, 0)
    assert_equal(guid.word(0), 3)
    # Uppercase digits read, a bad digit is zero, an odd tail is dropped.
    var short = string_to_guid("0A0bZz1")
    assert_equal(guid_to_string(short), "0a0b0000000000000000000000000000")
    # Digits past 32 are dropped.
    var long = string_to_guid("ff" * 20)
    assert_equal(guid_to_string(long), "ff" * 16)
    assert_true(JoystickGuid().is_zero())
    assert_false(guid.is_zero())


def test_a_usb_guid_has_the_standard_form() raises:
    var guid = create_joystick_guid(
        BUS_USB,
        VendorId(0x045E),
        ProductId(0x0B12),
        0x0509,
        "",
        "Microsoft Xbox Series S|X Controller",
        DRIVER_NONE,
        0,
    )
    assert_equal(guid_to_string(guid), "0300f5a35e040000120b000009050000")
    var info = joystick_guid_info(guid)
    assert_equal(info.vendor, VendorId(0x045E))
    assert_equal(info.product, ProductId(0x0B12))
    assert_equal(info.version, 0x0509)
    var expected = crc16(0, "Microsoft Xbox Series S|X Controller".as_bytes())
    assert_equal(info.crc, expected)
    assert_true(joystick_guid_uses_version(guid))
    # The vendor and product names are joined by a space for the CRC.
    var named = create_joystick_guid(
        BUS_BLUETOOTH,
        VendorId(0x054C),
        ProductId(0x0CE6),
        0x8001,
        "Sony",
        "DualSense",
        DRIVER_HIDAPI,
        7,
    )
    assert_equal(
        joystick_guid_info(named).crc, crc16(0, "Sony DualSense".as_bytes())
    )
    assert_equal(guid_to_string(named), "050089284c050000e60c000001806807")
    assert_equal(named.driver(), DRIVER_HIDAPI)
    assert_equal(Int(named.data[15]), 7)
    # A vendor name alone does not count.
    var vendor_only = create_joystick_guid(
        BUS_USB, VendorId(1), ProductId(2), 0, "Sony", "", DRIVER_NONE, 0
    )
    assert_equal(joystick_guid_info(vendor_only).crc, 0)


def test_a_guid_without_a_vendor_keeps_the_name() raises:
    var guid = create_joystick_guid_for_name("A Very Long Joystick Name")
    assert_equal(guid_to_string(guid), "0000fa8e412056657279204c6f6e6700")
    var info = joystick_guid_info(guid)
    assert_equal(info.vendor, VendorId(0))
    assert_equal(info.crc, crc16(0, "A Very Long Joystick Name".as_bytes()))
    assert_false(joystick_guid_uses_version(guid))
    var driven = create_joystick_guid(
        BUS_VIRTUAL,
        VendorId(0),
        ProductId(0),
        0,
        "",
        "Pad",
        DriverSignature(118),
        4,
    )
    assert_equal(guid_to_string(driven), "ff00286a506164000000000000007604")
    assert_equal(Int(driven.data[14]), 118)
    assert_equal(Int(driven.data[15]), 4)
    # The virtual bus still has the standard form.
    assert_equal(joystick_guid_info(driven).crc, crc16(0, "Pad".as_bytes()))


def test_a_guid_with_another_bus_has_no_info() raises:
    var guid = JoystickGuid()
    guid.set_word(0, 0x1234)
    guid.set_crc(0x55)
    guid.set_vendor(VendorId(1))
    var info = joystick_guid_info(guid)
    assert_equal(info.crc, 0)
    assert_equal(info.vendor, VendorId(0))
    # An MFi GUID's version word is a button mask.
    var mfi = string_to_guid(
        "05000000" + "0100" + "0000" + "0200" + "0000" + "0300" + "6d00"
    )
    assert_equal(mfi.driver(), DRIVER_MFI)
    assert_false(joystick_guid_uses_version(mfi))
    var no_product = string_to_guid(
        "03000000" + "0100" + "0000" + "0000" + "0000"
    )
    assert_false(joystick_guid_uses_version(no_product))


def test_guid_creation_refuses_values_out_of_range() raises:
    with assert_raises():
        _ = create_joystick_guid(
            HardwareBus(-1),
            VendorId(0),
            ProductId(0),
            0,
            "",
            "",
            DRIVER_NONE,
            0,
        )
    with assert_raises():
        _ = create_joystick_guid(
            BUS_USB, VendorId(0x10000), ProductId(0), 0, "", "", DRIVER_NONE, 0
        )
    with assert_raises():
        _ = create_joystick_guid(
            BUS_USB, VendorId(0), ProductId(-1), 0, "", "", DRIVER_NONE, 0
        )
    with assert_raises():
        _ = create_joystick_guid(
            BUS_USB,
            VendorId(0),
            ProductId(0),
            0,
            "",
            "",
            DriverSignature(256),
            0,
        )
    with assert_raises():
        _ = create_joystick_guid(
            BUS_USB, VendorId(0), ProductId(0), -1, "", "", DRIVER_NONE, 0
        )
    with assert_raises():
        _ = create_joystick_guid(
            BUS_USB, VendorId(0), ProductId(0), 0x10000, "", "", DRIVER_NONE, 0
        )
    with assert_raises():
        _ = create_joystick_guid(
            BUS_USB, VendorId(0), ProductId(0), 0, "", "", DRIVER_NONE, -1
        )
    with assert_raises():
        _ = create_joystick_guid(
            BUS_USB, VendorId(0), ProductId(0), 0, "", "", DRIVER_NONE, 256
        )


def test_special_guid_names() raises:
    assert_true(is_special_guid_name("default"))
    assert_true(is_special_guid_name("XInput"))
    assert_false(is_special_guid_name("03000000"))


def test_the_table_knows_xbox_and_playstation_controllers() raises:
    assert_equal(
        guess_controller_type(VendorId(0x045E), ProductId(0x028E)),
        CONTROLLER_XBOX360,
    )
    assert_equal(
        guess_controller_type(VendorId(0x045E), ProductId(0x0B12)),
        CONTROLLER_XBOXONE,
    )
    assert_equal(
        guess_controller_type(VendorId(0x054C), ProductId(0x0268)),
        CONTROLLER_PS3,
    )
    assert_equal(
        guess_controller_type(VendorId(0x054C), ProductId(0x09CC)),
        CONTROLLER_PS4,
    )
    assert_equal(
        guess_controller_type(VendorId(0x054C), ProductId(0x0CE6)),
        CONTROLLER_PS5,
    )
    assert_equal(
        guess_controller_type(VendorId(0x28DE), ProductId(0x1205)),
        CONTROLLER_STEAM_NEPTUNE,
    )
    assert_equal(
        guess_controller_type(VendorId(1), ProductId(2)),
        CONTROLLER_UNKNOWN_NON_STEAM,
    )
    assert_equal(
        guess_controller_name(VendorId(0x045E), ProductId(0x028E)),
        "Xbox 360 Controller",
    )
    assert_equal(guess_controller_name(VendorId(0x054C), ProductId(0x0268)), "")
    assert_equal(guess_controller_name(VendorId(1), ProductId(2)), "")


def test_gamecube_controllers_are_known() raises:
    assert_true(is_joystick_gamecube(VendorId(0x0E6F), ProductId(0x0185)))
    assert_true(is_joystick_gamecube(VendorId(0x20D6), ProductId(0xA711)))
    assert_false(is_joystick_gamecube(VendorId(0x0E6F), ProductId(0xA711)))
    assert_false(is_joystick_gamecube(VendorId(0x20D6), ProductId(0x0185)))


def _type(vendor: Int, product: Int, name: String, for_ui: Bool) -> GamepadType:
    return gamepad_type_from_vidpid(
        VendorId(vendor), ProductId(product), name, for_ui
    )


def test_gamepad_types_from_vendor_and_product() raises:
    assert_equal(
        _type(0, 0, "Lic Pro Controller", True),
        GAMEPAD_TYPE_NINTENDO_SWITCH_PRO,
    )
    assert_equal(
        _type(0, 0, "Nintendo Wireless Gamepad", True),
        GAMEPAD_TYPE_NINTENDO_SWITCH_PRO,
    )
    assert_equal(
        _type(0, 0, "Wireless Gamepad", False), GAMEPAD_TYPE_NINTENDO_SWITCH_PRO
    )
    assert_equal(_type(0, 0, "Gamepad", True), GAMEPAD_TYPE_STANDARD)
    assert_equal(_type(0, 5, "", True), GAMEPAD_TYPE_STANDARD)
    assert_equal(_type(1, 1, "", True), GAMEPAD_TYPE_STANDARD)
    assert_equal(_type(1, 2, "", True), GAMEPAD_TYPE_STANDARD)
    assert_equal(
        _type(0x057E, 0x2006, "", True),
        GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT,
    )
    assert_equal(
        _type(0x057E, 0x2007, "", True),
        GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT,
    )
    assert_equal(
        _type(0x057E, 0x2007, "NES Controller (R)", True), GAMEPAD_TYPE_STANDARD
    )
    assert_equal(
        _type(0x057E, 0x200E, "Joy-Con (L)", True),
        GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT,
    )
    assert_equal(
        _type(0x057E, 0x200E, "Joy-Con (R)", True),
        GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT,
    )
    assert_equal(
        _type(0x057E, 0x2008, "", True),
        GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR,
    )
    assert_equal(
        _type(0x057E, 0x2009, "", True), GAMEPAD_TYPE_NINTENDO_SWITCH_PRO
    )
    assert_equal(_type(0x0E6F, 0x0185, "", True), GAMEPAD_TYPE_STANDARD)
    assert_equal(
        _type(0x0E6F, 0x0185, "", False), GAMEPAD_TYPE_NINTENDO_SWITCH_PRO
    )
    assert_equal(_type(0x045E, 0x028E, "", True), GAMEPAD_TYPE_XBOX360)
    assert_equal(_type(0x045E, 0x0B12, "", True), GAMEPAD_TYPE_XBOXONE)
    assert_equal(_type(0x054C, 0x0268, "", True), GAMEPAD_TYPE_PS3)
    assert_equal(_type(0x054C, 0x09CC, "", True), GAMEPAD_TYPE_PS4)
    assert_equal(_type(0x054C, 0x0CE6, "", True), GAMEPAD_TYPE_PS5)
    # An XInput DualShock 4 look-alike looks like a PS4 controller in a UI.
    assert_equal(_type(0x0F0D, 0x00ED, "", True), GAMEPAD_TYPE_PS4)
    assert_equal(_type(0x0F0D, 0x00ED, "", False), GAMEPAD_TYPE_STANDARD)
    # A Switch controller that is input only, and one in XInput mode.
    assert_equal(
        _type(0x0F0D, 0x00C1, "", True), GAMEPAD_TYPE_NINTENDO_SWITCH_PRO
    )
    assert_equal(
        _type(0x0F0D, 0x00DC, "", True), GAMEPAD_TYPE_NINTENDO_SWITCH_PRO
    )
    assert_equal(_type(0x0F0D, 0x00DC, "", False), GAMEPAD_TYPE_STANDARD)
    assert_equal(
        guess_controller_type(VendorId(0x0F0D), ProductId(0x00ED)), XINPUT_PS4
    )


def test_gamepad_types_from_guids() raises:
    var ps5 = string_to_guid("030000004c050000e60c000011010000")
    assert_equal(gamepad_type_from_guid(ps5, ""), GAMEPAD_TYPE_PS5)
    var xinput = string_to_guid(
        "03000000" + "0100" + "0000" + "0200" + "0000" + "0000" + "7800"
    )
    assert_equal(xinput.driver(), DRIVER_XINPUT)
    assert_equal(gamepad_type_from_guid(xinput, ""), GAMEPAD_TYPE_XBOXONE)
    var plain = string_to_guid("03000000" + "0100" + "0000" + "0200" + "0000")
    assert_equal(gamepad_type_from_guid(plain, ""), GAMEPAD_TYPE_STANDARD)
    var xinput_ps4 = string_to_guid(
        "03000000" + "0d0f" + "0000" + "ed00" + "0000" + "0000" + "7800"
    )
    assert_equal(gamepad_type_from_guid(xinput_ps4, ""), GAMEPAD_TYPE_PS4)


def test_hex4_writes_four_lowercase_digits() raises:
    assert_equal(hex4(0x0A1F), "0a1f")
    assert_equal(hex4(0), "0000")


def _name(vendor: Int, product: Int, maker: String, item: String) -> String:
    return create_device_name(
        VendorId(vendor), ProductId(product), maker, item, "Controller"
    )


def test_device_names_are_cleaned() raises:
    assert_equal(_name(0, 0, "  Sony", " Pad  "), "Sony Pad")
    assert_equal(_name(0, 0, "", "A  B   C"), "A B C")
    assert_equal(_name(0, 0, "Sony", ""), "Controller")
    assert_equal(_name(0, 0, "", ""), "Controller")
    assert_equal(_name(0x045E, 0x028E, "", ""), "Xbox 360 Controller")
    assert_equal(_name(0x045E, 0x0B12, "", ""), "Xbox One Controller")
    assert_equal(_name(0x054C, 0x0268, "", ""), "PS3 Controller")
    assert_equal(_name(0x054C, 0x09CC, "", ""), "PS4 Controller")
    assert_equal(_name(0x054C, 0x0CE6, "", ""), "DualSense Wireless Controller")
    assert_equal(
        _name(0x057E, 0x2009, "", ""), "Nintendo Switch Pro Controller"
    )
    assert_equal(_name(0x1234, 0xABCD, "", ""), "0x1234/0xabcd")
    assert_equal(_name(0, 0, "HORI CO.,LTD.", "HORIPAD S"), "HORIPAD S")
    assert_equal(_name(0, 0, "", "Unknown Gamepad"), "Gamepad")
    assert_equal(_name(0, 0, "", "8BitDo Tech Ltd Pro 2"), "8BitDo Pro 2")
    assert_equal(_name(0, 0, "Razer", "Razer Raiju"), "Razer Raiju")
    assert_equal(_name(0, 0, "", "Mad-Mad Pad"), "Mad Pad")
    assert_equal(_name(0, 0, "", "HORI HORl Taiko Drum"), "HORl Taiko Drum")
    assert_equal(_name(0, 0, "", "Pad"), "Pad")
    assert_equal(_name(0, 0, "", "AB"), "AB")


def test_joystick_names_prefer_the_table() raises:
    assert_equal(
        create_joystick_name(VendorId(0x045E), ProductId(0x028E), "", "X"),
        "Xbox 360 Controller",
    )
    assert_equal(
        create_joystick_name(
            VendorId(0x054C),
            ProductId(0x0CE6),
            "",
            "Sony Interactive Entertainment DualSense Wireless Controller",
        ),
        "Sony Interactive Entertainment DualSense Wireless Controller",
    )


def _ignored(vendor: Int, product: Int, name: String) -> Bool:
    return should_ignore_joystick(VendorId(vendor), ProductId(product), 0, name)


def test_sensors_keyboards_and_mice_are_not_gamepads() raises:
    assert_true(_ignored(0, 0, "Sony DualSense Motion Sensors"))
    assert_true(_ignored(0, 0, "Nintendo Switch Pro Controller IMU"))
    assert_false(_ignored(0, 0, "Nintendo Switch Pro Controller"))
    assert_false(_ignored(0, 0, "Pad IMU"))
    assert_true(_ignored(0, 0, "Wii Accelerometer"))
    assert_true(_ignored(0, 0, "Wii IR"))
    assert_true(_ignored(0, 0, "Wii Motion Plus"))
    assert_true(_ignored(0, 0, "Wii Nunchuk"))
    assert_true(_ignored(0, 0, "uinput-fpc"))
    assert_true(_ignored(0x28DE, 0x11FF, "Steam Virtual Gamepad"))
    assert_false(_ignored(0x28DE, 0x1205, "Steam Deck"))
    assert_false(_ignored(0x1234, 0x11FF, "Pad"))
    assert_true(_ignored(0x045E, 0x009D, "Microsoft Keyboard"))
    assert_true(_ignored(0x0B05, 0x1906, "ROG Pugio II"))
    assert_false(_ignored(0x054C, 0x0CE6, "DualSense Wireless Controller"))
    assert_false(
        should_ignore_gamepad(VendorId(0x054C), ProductId(0x0CE6), 0, "Pad")
    )


def test_guid_corners() raises:
    # A name GUID with no name keeps only the bus.
    var empty = create_joystick_guid_for_name("")
    assert_equal(guid_to_string(empty), "0" * 32)
    # Word 5 not zero: the name form, so only the CRC is read.
    var guid = string_to_guid(
        "0300abcd" + "0100" + "0000" + "0200" + "ff00" + "0000" + "0000"
    )
    var info = joystick_guid_info(guid)
    assert_equal(info.vendor, VendorId(0))
    assert_equal(info.crc, 0xCDAB)


def test_device_name_corners() raises:
    assert_equal(_name(0, 5, "", ""), "0x0000/0x0005")
    assert_equal(create_device_name(VendorId(0), ProductId(0), "", "", ""), "")
    assert_equal(_name(0, 0, "", "HORI CO.,LTD."), "HORI")
    assert_equal(_name(0, 0, "", "Pad Pad"), "Pad")
    assert_equal(_name(0, 0, "", "---"), "")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
