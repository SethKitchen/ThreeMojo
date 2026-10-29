# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.gamepad.mapping` and the built-in Linux mappings.

The expected mapping strings are the ones SDL 3.2.24 gives for the same
calls: `SDL_AddGamepadMapping` and then `SDL_GetGamepadMappingForGUID`,
in the same order, on SDL built from source for Linux. The one exception
is the labeled mapping, which this port corrects.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.gamepad.guid import JoystickGuid, string_to_guid
from extensions.gamepad.ids import (
    AXIS_LEFTX,
    AXIS_LEFT_TRIGGER,
    AXIS_RIGHTX,
    BUTTON_DPAD_DOWN,
    BUTTON_DPAD_UP,
    BUTTON_EAST,
    BUTTON_MISC1,
    BUTTON_NORTH,
    BUTTON_SOUTH,
    BUTTON_TOUCHPAD,
    JOYSTICK_AXIS_MAX,
    JOYSTICK_AXIS_MIN,
)
from extensions.gamepad.linux import default_mapping_database
from extensions.gamepad.linux_mappings import linux_default_mappings
from extensions.gamepad.mapping import (
    BIND_AXIS,
    BIND_BUTTON,
    BIND_HAT,
    BIND_NONE,
    HAT_DOWN,
    HAT_LEFT,
    HAT_RIGHT,
    HAT_UP,
    MAPPING_AXIS,
    MAPPING_BUTTON,
    MAPPING_HAT,
    MAPPING_NONE,
    PRIORITY_API,
    PRIORITY_DEFAULT,
    PRIORITY_USER,
    AutoMapping,
    BindType,
    GamepadBinding,
    InputMapping,
    MappingDatabase,
    MappingKind,
    MappingPriority,
    automatic_mapping_string,
    convert_mapping_to_positional,
    field_value,
    fixup_hidapi_mapping,
    is_hidapi_guid,
    mapping_crc,
    mapping_fields,
    mapping_for_guid_string,
    mapping_guid_field,
    mapping_name_field,
    parse_gamepad_element,
    parse_gamepad_mapping,
    uses_button_labels,
)


def _get(database: MappingDatabase, guid: String) raises -> String:
    try:
        return mapping_for_guid_string(database, string_to_guid(guid))
    except:
        return "(null)"


def test_kinds_check_their_range() raises:
    assert_true(BindType(3).is_valid())
    assert_false(BindType(4).is_valid())
    assert_false(BindType(-1).is_valid())
    assert_true(MappingPriority(2).is_valid())
    assert_false(MappingPriority(3).is_valid())
    assert_true(MappingKind(3).is_valid())
    assert_false(MappingKind(4).is_valid())
    assert_true(PRIORITY_DEFAULT < PRIORITY_API)
    assert_true(PRIORITY_API <= PRIORITY_API)
    assert_false(PRIORITY_USER < PRIORITY_API)
    assert_true(PRIORITY_USER == MappingPriority(2))


def test_the_built_in_database_matches_sdl() raises:
    assert_equal(len(linux_default_mappings()), 317)
    var database = default_mapping_database()
    # One GUID is in SDL's table twice, so SDL keeps 316 mappings.
    assert_equal(database.count(), 316)
    assert_equal(
        database.mapping_string(0),
        (
            "03000000c82d00000090000011010000,8BitDo FC30 Pro,a:b1,b:b0,"
            "back:b10,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,"
            "leftshoulder:b6,leftstick:b13,lefttrigger:a4,leftx:a0,lefty:a1,"
            "rightshoulder:b7,rightstick:b14,righttrigger:a5,rightx:a2,"
            "righty:a3,start:b11,x:b4,y:b3,"
            "hint:!SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,platform:Linux,"
        ),
    )
    assert_equal(
        database.mapping_string(database.count() - 1),
        (
            "030000009b2800000300000001010000,raphnet.net 4nes4snes v1.5,"
            "a:b0,b:b4,back:b2,leftshoulder:b6,leftx:a0,lefty:a1,"
            "rightshoulder:b7,start:b3,x:b1,y:b5,platform:Linux,"
        ),
    )
    with assert_raises():
        _ = database.mapping_string(database.count())
    with assert_raises():
        _ = database.mapping_string(-1)


def test_mappings_are_added_and_replaced_as_in_sdl() raises:
    var db = default_mapping_database()
    var ps5 = "030000004c050000e60c000011010000"
    assert_equal(
        _get(db, ps5),
        (
            ps5
            + ",PS5 Controller,a:b1,b:b2,back:b8,dpdown:h0.4,dpleft:h0.8,"
            "dpright:h0.2,dpup:h0.1,guide:b12,leftshoulder:b4,leftstick:b10,"
            "lefttrigger:a3,leftx:a0,lefty:a1,misc1:b13,rightshoulder:b5,"
            "rightstick:b11,righttrigger:a4,rightx:a2,righty:a5,start:b9,"
            "x:b0,y:b3,platform:Linux,"
        ),
    )
    assert_equal(db.add_mapping(ps5 + ",My PS5,a:b0,b:b1,"), 0)
    assert_equal(_get(db, ps5), ps5 + ",My PS5,a:b0,b:b1,platform:Linux,")
    assert_equal(db.add_mapping(ps5 + ",My PS5 again,a:b1,platform:Linux,"), 0)
    assert_equal(_get(db, ps5), ps5 + ",My PS5 again,a:b1,platform:Linux,")
    # A lower priority does not replace a higher one.
    assert_equal(db.add_mapping(ps5 + ",Low,a:b2,", PRIORITY_DEFAULT), 0)
    assert_equal(_get(db, ps5), ps5 + ",My PS5 again,a:b1,platform:Linux,")
    with assert_raises():
        _ = db.add_mapping(ps5 + ",Bad,a:b2,", MappingPriority(7))

    assert_equal(
        db.add_mapping("03000000aaaa0000bbbb000001000000,New Pad,a:b0,x:b2,"), 1
    )
    assert_equal(
        _get(db, "03000000aaaa0000bbbb000001000000"),
        "03000000aaaa0000bbbb000001000000,New Pad,a:b0,x:b2,platform:Linux,",
    )
    # Another version of the same pad uses the mapping too.
    assert_equal(
        _get(db, "03000000aaaa0000bbbb000002000000"),
        "03000000aaaa0000bbbb000002000000,New Pad,a:b0,x:b2,platform:Linux,",
    )


def test_crcs_are_matched_as_in_sdl() raises:
    var db = default_mapping_database()
    assert_equal(
        db.add_mapping(
            "0300cdab11110000222200000100000,Crc Pad,a:b0,crc:1234,b:b1,"
        ),
        1,
    )
    assert_equal(
        db.add_mapping(
            "0300cdab1111000022220000010000,Crc Pad,a:b0,crc:1234,b:b1,"
        ),
        0,
    )
    var expected = (
        "0300cdab111100002222000001000000,Crc"
        " Pad,a:b0,crc:abcd,b:b1,platform:Linux,"
    )
    assert_equal(_get(db, "0300cdab1111000022220000010000"), expected)
    assert_equal(_get(db, "0300cdab111100002222000001000000"), expected)
    assert_equal(_get(db, "03001111111100002222000001000000"), "(null)")
    assert_equal(_get(db, "03000000111100002222000001000000"), "(null)")

    assert_equal(
        db.add_mapping(
            "03000000333300004444000001000000,Field Crc,a:b0,crc:beef"
        ),
        1,
    )
    assert_equal(
        _get(db, "0300efbe333300004444000001000000"),
        (
            "0300efbe333300004444000001000000,Field"
            " Crc,a:b0,crc:beef,platform:Linux,"
        ),
    )
    assert_equal(_get(db, "03000000333300004444000001000000"), "(null)")
    assert_equal(_get(db, "0300aaaa333300004444000001000000"), "(null)")

    assert_equal(
        db.add_mapping("0300beef555500006666000001000000,Crc First,a:b0,"), 1
    )
    assert_equal(
        db.add_mapping("03000000555500006666000001000000,No Crc,a:b1,"), 1
    )
    assert_equal(
        _get(db, "0300beef555500006666000001000000"),
        (
            "0300beef555500006666000001000000,Crc"
            " First,a:b0,crc:efbe,platform:Linux,"
        ),
    )
    assert_equal(
        _get(db, "03000000555500006666000001000000"),
        "03000000555500006666000001000000,No Crc,a:b1,platform:Linux,",
    )
    # A CRC field with nothing after it, and a mapping with no fields.
    assert_equal(
        db.add_mapping("0300aaaa777700007777000001000000,Tail,crc:1"), 1
    )
    assert_equal(
        db.mapping_string(db.count() - 1),
        "03000000777700007777000001000000,Tail,crc:aaaa,platform:Linux,",
    )
    assert_equal(db.add_mapping("0300aaaa777700007777000002000000,Empty,"), 1)
    assert_equal(
        db.mapping_string(db.count() - 1),
        "03000000777700007777000002000000,Empty,crc:aaaa,platform:Linux,",
    )


def test_hints_decide_whether_a_mapping_is_added() raises:
    var db = MappingDatabase()
    assert_equal(
        db.add_mapping(
            "03000000777700008888000001000000,Hint Off,a:b0,hint:SDL_FOO:=0,"
        ),
        0,
    )
    assert_equal(
        db.add_mapping(
            "03000000777700008888000001000000,Hint Neg,a:b0,hint:!SDL_FOO:=0,"
        ),
        1,
    )
    assert_equal(
        _get(db, "03000000777700008888000001000000"),
        (
            "03000000777700008888000001000000,Hint"
            " Neg,a:b0,hint:!SDL_FOO:=0,platform:Linux,"
        ),
    )
    assert_equal(
        db.add_mapping(
            "03000000999900008888000001000000,Hint Bare,a:b0,hint:SDL_BAR,"
        ),
        0,
    )
    assert_equal(_get(db, "03000000999900008888000001000000"), "(null)")
    assert_equal(
        db.add_mapping(
            "03000000999900009999000001000000,Hint Set,a:b0,hint:SDL_BAR:=1,"
        ),
        1,
    )
    assert_equal(
        db.add_mapping(
            "03000000999900009999000002000000,Hint End,a:b0,hint:SDL_BAR:"
        ),
        0,
    )
    assert_equal(
        db.add_mapping("03000000999900009999000003000000,Hint Neg,hint:!"), 1
    )


def test_labeled_mappings_become_positional() raises:
    var db = MappingDatabase()
    var guid = "03000000aaaa0000cccc000001000000"
    assert_equal(
        db.add_mapping(
            guid
            + ",Labeled,a:b0,b:b1,back:b6,leftx:a0,lefty:a1,x:b2,y:b3,"
            "hint:SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,"
        ),
        1,
    )
    # SDL 3.2.24 gives "b:b0,a:b1,back:b6,lefty:a0,leftx:a1,x:b2,y:b3":
    # it swaps the left stick and not x and y. This port swaps x and y.
    assert_equal(
        _get(db, guid),
        guid
        + ",Labeled,b:b0,a:b1,back:b6,leftx:a0,lefty:a1,y:b2,x:b3,"
        "hint:!SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,platform:Linux,",
    )
    var positional = "03000000aaaa0000dddd000001000000"
    assert_equal(
        db.add_mapping(
            positional
            + ",Positional,a:b0,b:b1,x:b2,y:b3,"
            "hint:!SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,"
        ),
        1,
    )
    assert_equal(
        _get(db, positional),
        positional
        + ",Positional,a:b0,b:b1,x:b2,y:b3,"
        "hint:!SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,platform:Linux,",
    )
    assert_equal(convert_mapping_to_positional("g,n,back:b6,"), "g,n,back:b6,")
    assert_true(
        uses_button_labels("a:b0,hint:SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1")
    )
    assert_false(
        uses_button_labels("a:b0,hint:!SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1")
    )


def test_default_and_xinput_mappings_are_remembered() raises:
    var db = MappingDatabase()
    assert_equal(db.default_index, -1)
    assert_equal(db.add_mapping("default,Default Pad,a:b0,"), 1)
    assert_equal(
        db.mapping_string(0),
        "defa0000000000000000000000000000,Default Pad,a:b0,platform:Linux,",
    )
    assert_equal(db.add_mapping("XInput,XInput Pad,a:b0,"), 1)
    assert_equal(db.default_index, 0)
    assert_equal(db.xinput_index, 1)
    # "xinput" reads as the zero GUID, which no search matches.
    assert_equal(_get(db, "xinput"), "(null)")
    assert_equal(db.mapping_for_device("Pad", string_to_guid("0500"), None), 0)


def test_malformed_mappings_are_refused() raises:
    var db = MappingDatabase()
    with assert_raises():
        _ = db.add_mapping("nocomma")
    with assert_raises():
        _ = db.add_mapping("03000000aaaa0000eeee000001000000,noname")
    assert_equal(
        db.add_mapping(
            "  03000000aaaa0000ffff000001000000 , Spaced ,  a:b0,  b:b1  \n"
        ),
        1,
    )
    assert_equal(_get(db, "03000000aaaa0000ffff000001000000"), "(null)")
    assert_equal(db.mappings[0].mapping, "a:b0,  b:b1")
    assert_equal(db.mappings[0].name, " Spaced ")
    assert_equal(
        db.add_mapping(
            "03000000abab0000cdcd000001000000,Two"
            " Platforms,platform:Linux,a:b0,platform:Linux,"
        ),
        1,
    )
    assert_equal(
        _get(db, "03000000abab0000cdcd000001000000"),
        "03000000abab0000cdcd000001000000,Two Platforms,platform:Linux,a:b0,",
    )
    assert_equal(_get(db, "05000000000000000000000000000000"), "(null)")


def test_mapping_fields_are_split_out() raises:
    assert_equal(mapping_guid_field("abc,Name,a:b0"), "abc")
    assert_equal(mapping_name_field("abc,Name,a:b0"), "Name")
    assert_equal(mapping_fields("abc,Name,\t a:b0 \r\n"), "a:b0")
    assert_equal(mapping_fields("abc,Name,   "), "")
    with assert_raises():
        _ = mapping_guid_field("abc")
    with assert_raises():
        _ = mapping_name_field("abc")
    with assert_raises():
        _ = mapping_name_field("abc,Name")
    with assert_raises():
        _ = mapping_fields("abc")
    with assert_raises():
        _ = mapping_fields("abc,Name")
    assert_equal(field_value("a:b0,type:ps4,x:b1", "type:"), "ps4")
    assert_equal(field_value("a:b0,type:ps4", "type:"), "ps4")
    assert_equal(field_value("a:b0", "type:"), "")
    assert_equal(mapping_crc("a:b0,crc:  -0X1f,"), UInt16(0xFFE1))
    assert_equal(mapping_crc("a:b0,crc:+ab"), UInt16(0xAB))
    assert_equal(mapping_crc("a:b0,crc:0x"), UInt16(0))
    assert_equal(mapping_crc("a:b0,crc:0xg"), UInt16(0))
    assert_equal(mapping_crc("a:b0,crc:1FFFF"), UInt16(0xFFFF))
    assert_equal(mapping_crc("a:b0"), UInt16(0))


def test_platform_lines_are_read_from_a_file() raises:
    var db = MappingDatabase()
    var text = String(
        "# Game Controller DB\n"
        "03000000aaaa0000bbbb000001000000,Pad,a:b0,platform:Linux,\n"
        "03000000aaaa0000bbbb000002000000,Pad,a:b0,platform:Windows,\n"
        "03000000aaaa0000bbbb000003000000,Pad,a:b0,platform:linux\n"
        "03000000aaaa0000bbbb000004000000,Pad,a:b0,platform:LINUX,\n"
        "03000000aaaa0000bbbb000001000000,Again,a:b1,platform:Linux,\n"
        "03000000aaaa0000bbbb000005000000,Pad,a:b0,platform:"
        + "x" * 70
        + ",\n"
    )
    assert_equal(db.add_mappings_from_text(text), 2)
    assert_equal(db.count(), 2)
    assert_equal(db.mappings[0].name, "Again")
    assert_equal(db.add_mappings_from_text(text, "Windows"), 1)


def _binding(text: String) -> GamepadBinding:
    var bindings = parse_gamepad_mapping(text, False)
    return bindings[0]


def test_elements_parse_into_bindings() raises:
    var button = _binding("a:b3")
    assert_equal(button.input_type, BIND_BUTTON)
    assert_equal(button.input_button, 3)
    assert_equal(button.output_type, BIND_BUTTON)
    assert_equal(button.output_button, BUTTON_SOUTH)
    var axis = _binding("leftx:a12")
    assert_equal(axis.input_type, BIND_AXIS)
    assert_equal(axis.input_axis, 12)
    assert_equal(axis.input_axis_min, JOYSTICK_AXIS_MIN)
    assert_equal(axis.input_axis_max, JOYSTICK_AXIS_MAX)
    assert_equal(axis.output_axis, AXIS_LEFTX)
    assert_equal(axis.output_axis_min, JOYSTICK_AXIS_MIN)
    var trigger = _binding("lefttrigger:+a2~")
    assert_equal(trigger.output_axis, AXIS_LEFT_TRIGGER)
    assert_equal(trigger.output_axis_min, 0)
    assert_equal(trigger.output_axis_max, JOYSTICK_AXIS_MAX)
    assert_equal(trigger.input_axis_min, JOYSTICK_AXIS_MAX)
    assert_equal(trigger.input_axis_max, 0)
    var half = _binding("-leftx:-a1")
    assert_equal(half.output_axis_min, 0)
    assert_equal(half.output_axis_max, JOYSTICK_AXIS_MIN)
    assert_equal(half.input_axis_min, 0)
    assert_equal(half.input_axis_max, JOYSTICK_AXIS_MIN)
    var plus = _binding("+rightx:a1~")
    assert_equal(plus.output_axis, AXIS_RIGHTX)
    assert_equal(plus.output_axis_min, 0)
    assert_equal(plus.output_axis_max, JOYSTICK_AXIS_MAX)
    assert_equal(plus.input_axis_min, JOYSTICK_AXIS_MAX)
    assert_equal(plus.input_axis_max, JOYSTICK_AXIS_MIN)
    var hat = _binding("dpdown:h1.4")
    assert_equal(hat.input_type, BIND_HAT)
    assert_equal(hat.input_hat, 1)
    assert_equal(hat.input_hat_mask, 4)
    assert_equal(hat.output_button, BUTTON_DPAD_DOWN)
    var button_axis = _binding("dpleft:-a0")
    assert_equal(button_axis.output_type, BIND_BUTTON)
    assert_equal(button_axis.input_axis_max, JOYSTICK_AXIS_MIN)
    var signed_button = _binding("x:+b4")
    assert_equal(signed_button.input_type, BIND_BUTTON)
    assert_equal(signed_button.input_button, 4)


def test_bad_elements_are_skipped() raises:
    var bindings = List[GamepadBinding]()
    assert_false(parse_gamepad_element(bindings, "platform", "Linux", False))
    assert_false(parse_gamepad_element(bindings, "a", "", False))
    assert_false(parse_gamepad_element(bindings, "a", "q1", False))
    assert_false(parse_gamepad_element(bindings, "a", "a", False))
    assert_false(parse_gamepad_element(bindings, "a", "b", False))
    assert_false(parse_gamepad_element(bindings, "a", "h0", False))
    assert_false(parse_gamepad_element(bindings, "a", "hx.1", False))
    assert_false(parse_gamepad_element(bindings, "a", "h0x1", False))
    assert_false(parse_gamepad_element(bindings, "a", "h0.x", False))
    assert_false(parse_gamepad_element(bindings, "a", "-", False))
    assert_equal(len(bindings), 0)
    assert_true(parse_gamepad_element(bindings, "a", "b0", True))
    assert_equal(bindings[0].output_button, BUTTON_EAST)
    # The same binding twice is kept once.
    assert_true(parse_gamepad_element(bindings, "a", "b0", True))
    assert_equal(len(bindings), 1)


def test_mapping_strings_parse_as_in_sdl() raises:
    var bindings = parse_gamepad_mapping(
        "a:b0, b : b1,platform:Linux,,x:b2,y:b3,crc:12ab", False
    )
    assert_equal(len(bindings), 4)
    assert_equal(bindings[1].output_button, BUTTON_EAST)
    assert_equal(bindings[3].output_button, BUTTON_NORTH)
    # A trailing field without a comma still counts.
    assert_equal(len(parse_gamepad_mapping("a:b0,b:b1", False)), 2)
    # A name over 20 bytes ends the parse, keeping what came before.
    var long = parse_gamepad_mapping(
        "a:b0,hint:SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,b:b1", False
    )
    assert_equal(len(long), 1)
    var long_name = parse_gamepad_mapping("a:b0," + "q" * 21 + ":b1", False)
    assert_equal(len(long_name), 1)
    # A second colon writes over the input name.
    var twice = parse_gamepad_mapping("a:b12:h", False)
    assert_equal(len(twice), 0)
    var over = parse_gamepad_mapping("a:a2:b", False)
    assert_equal(over[0].input_type, BIND_BUTTON)
    assert_equal(over[0].input_button, 2)
    assert_equal(len(parse_gamepad_mapping("", False)), 0)


def test_old_hidapi_mappings_move_the_dpad_to_a_hat() raises:
    var bindings = parse_gamepad_mapping(
        (
            "a:b0,dpup:b11,dpdown:b12,dpleft:b13,dpright:b14,misc1:b15,"
            "leftx:a0,lefttrigger:b20"
        ),
        False,
    )
    fixup_hidapi_mapping(bindings)
    assert_equal(bindings[0].input_button, 0)
    var bits: List[Int] = [HAT_UP, HAT_DOWN, HAT_LEFT, HAT_RIGHT]
    for index in range(4):
        assert_equal(bindings[1 + index].input_type, BIND_HAT)
        assert_equal(bindings[1 + index].input_hat_mask, bits[index])
    assert_equal(bindings[5].input_button, 11)
    assert_equal(bindings[7].input_button, 20)
    # A new-style mapping is left alone.
    var current = parse_gamepad_mapping("dpup:h0.1,misc1:b11", False)
    fixup_hidapi_mapping(current)
    assert_equal(current[1].input_button, 11)
    var shifted = parse_gamepad_mapping("misc1:b11", False)
    fixup_hidapi_mapping(shifted)
    assert_equal(shifted[0].input_button, 11)
    var axis_first = parse_gamepad_mapping("dpup:a1,misc1:b15", False)
    fixup_hidapi_mapping(axis_first)
    assert_equal(axis_first[1].input_button, 15)
    var none = parse_gamepad_mapping("a:b0", False)
    fixup_hidapi_mapping(none)
    assert_equal(none[0].input_button, 0)
    assert_true(is_hidapi_guid(string_to_guid("0300" + "00" * 12 + "6800")))
    assert_false(is_hidapi_guid(JoystickGuid()))


def test_bindings_compare_their_outputs() raises:
    var a = _binding("leftx:a0")
    var b = _binding("leftx:a1")
    var c = _binding("rightx:a0")
    var d = _binding("a:b0")
    var e = _binding("a:b1")
    var f = _binding("b:b0")
    assert_true(a.has_same_output(b))
    assert_false(a.has_same_output(c))
    assert_false(a.has_same_output(d))
    assert_true(d.has_same_output(e))
    assert_false(d.has_same_output(f))
    assert_true(a != b)
    assert_true(GamepadBinding() == GamepadBinding())
    assert_equal(GamepadBinding().input_type, BIND_NONE)


def test_automatic_mappings_are_written_in_sdl_order() raises:
    var raw = AutoMapping()
    raw.buttons[BUTTON_SOUTH.value] = InputMapping(MAPPING_BUTTON, 0)
    raw.buttons[BUTTON_TOUCHPAD.value] = InputMapping(MAPPING_BUTTON, 9)
    raw.buttons[BUTTON_MISC1.value] = InputMapping(MAPPING_BUTTON, 5)
    raw.buttons[21] = InputMapping(MAPPING_BUTTON, 6)
    raw.buttons[16] = InputMapping(MAPPING_BUTTON, 7)
    raw.buttons[BUTTON_DPAD_UP.value] = InputMapping(MAPPING_HAT, 0x11)
    var axis = InputMapping(MAPPING_AXIS, 2)
    axis.half_axis_positive = True
    axis.axis_reversed = True
    raw.axes[AXIS_LEFT_TRIGGER.value] = axis
    var negative = InputMapping(MAPPING_AXIS, 3)
    negative.half_axis_negative = True
    raw.axes[AXIS_LEFTX.value] = negative
    raw.axes[AXIS_RIGHTX.value] = InputMapping(MAPPING_AXIS, 4)
    assert_equal(
        automatic_mapping_string("My, Pad", raw),
        (
            "none,My  Pad,a:b0,dpup:h1.1,misc1:b5,misc2:b6,paddle1:b7,"
            "leftx:-a3,rightx:a4,lefttrigger:+a2~,touchpad:b9,"
        ),
    )
    assert_equal(
        automatic_mapping_string("n" * 200, AutoMapping()),
        "none," + "n" * 127 + ",",
    )
    assert_equal(InputMapping().kind, MAPPING_NONE)


def test_devices_get_a_mapping_or_the_default() raises:
    var db = MappingDatabase()
    var guid = string_to_guid("0300abcd5e0400008e02000014010000")
    assert_equal(db.mapping_for_device("Pad", guid, None), -1)
    var raw = AutoMapping()
    raw.buttons[0] = InputMapping(MAPPING_BUTTON, 0)
    var index = db.mapping_for_device("Pad", guid, raw^)
    assert_equal(index, 0)
    # The automatic mapping drops the GUID's CRC.
    assert_equal(
        db.mapping_string(index),
        "030000005e0400008e02000014010000,Pad,a:b0,platform:Linux,",
    )
    # Found again without a new mapping.
    assert_equal(db.mapping_for_device("Pad", guid, None), 0)
    # The Xbox 360 wireless receiver gets SDL's Linux mapping.
    var receiver = string_to_guid("030000005e040000a102000007010000")
    var at = db.mapping_for_device(
        "Xbox 360 Wireless Receiver (XBOX)", receiver, None
    )
    assert_equal(db.mappings[at].name, "X360 Wireless Controller")
    assert_true(db.mappings[at].mapping.find("dpleft:b11") >= 0)
    assert_equal(
        db.mapping_for_device("Xbox 360 Wireless Receiver", receiver, None), at
    )


def test_mapping_corners() raises:
    var db = MappingDatabase()
    # A GUID with a CRC does not replace a mapping without one.
    assert_equal(
        db.add_mapping("03000000555500006666000001000000,No Crc,a:b1,"), 1
    )
    assert_equal(
        db.add_mapping("0300beef555500006666000001000000,Crc,a:b0,"), 1
    )
    assert_equal(db.count(), 2)
    # Two versions of a pad: another version finds the first.
    assert_equal(db.add_mapping("03000000aaaa0000bbbb000001000000,V1,a:b0,"), 1)
    assert_equal(db.add_mapping("03000000aaaa0000bbbb000002000000,V2,a:b0,"), 1)
    assert_equal(
        db.mappings[
            db.mapping_for_guid(
                string_to_guid("03000000aaaa0000bbbb000003000000"), False
            )
        ].name,
        "V1",
    )
    # Hint values with space and a sign, an empty value, and long names.
    assert_equal(
        db.add_mapping(
            "03000000aaaa0000cccc000001000000,H,a:b0,hint:SDL_X:= -1"
        ),
        1,
    )
    assert_equal(
        db.add_mapping(
            "03000000aaaa0000cccc000002000000,H,a:b0,hint:SDL_X:= +0"
        ),
        0,
    )
    assert_equal(
        db.add_mapping("03000000aaaa0000cccc000003000000,H,a:b0,hint:SDL_X:="),
        0,
    )
    assert_equal(
        db.add_mapping(
            "03000000aaaa0000cccc000004000000,H,a:b0,hint:SDL_X,b:b1"
        ),
        0,
    )
    assert_equal(
        db.add_mapping("03000000aaaa0000cccc000005000000,H,a:b0,hint:SDL_X:b"),
        0,
    )
    assert_equal(
        db.add_mapping(
            "03000000aaaa0000cccc000006000000,H,a:b0,hint:" + "Y" * 130 + ":=1"
        ),
        0,
    )
    # Only white space after the CRC field's name reads as zero.
    assert_equal(mapping_crc("a:b0,crc:   "), UInt16(0))
    assert_equal(mapping_crc("a:b0,crc:"), UInt16(0))
    assert_equal(mapping_crc("a:b0,crc: -"), UInt16(0))


def test_parser_corners() raises:
    var bindings = List[GamepadBinding]()
    assert_false(parse_gamepad_element(bindings, "a", "q123", False))
    # A last field with no control name.
    assert_equal(len(parse_gamepad_mapping("a:b0,:b1", False)), 1)
    # The fix-up with no bindings, and with an axis first.
    var none = List[GamepadBinding]()
    fixup_hidapi_mapping(none)
    var axis_first = parse_gamepad_mapping("leftx:a0,dpup:b11,misc1:b15", False)
    fixup_hidapi_mapping(axis_first)
    assert_equal(axis_first[1].input_type, BIND_HAT)
    assert_equal(axis_first[2].input_button, 11)
    assert_equal(automatic_mapping_string("", AutoMapping()), "none,,")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
