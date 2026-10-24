# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of the mapping functions of
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

"""Gamepad mapping strings, their bindings, and the mapping database.

A mapping string tells SDL which joystick input is which gamepad control:

    030000004c050000e60c000011010000,PS5 Controller,a:b0,b:b1,leftx:a0,...

The first field is the joystick GUID and the second its name. Each other
field is `control:input`. An input is a button `b3`, an axis `a2`, or a
hat direction `h0.4`. An axis can be half, `+a2` or `-a2`, and inverted,
`a2~`. A control can be half too: `+leftx` is the right half of the left
stick. Fields such as `platform:Linux`, `crc:1a2b`, `type:ps4`,
`face:sony` and `hint:...` are not bindings.

`parse_gamepad_mapping` turns the fields into `GamepadBinding`s. A
`MappingDatabase` holds mappings by GUID and finds the best one for a
device. `generate_automatic_mapping` writes a mapping for a device the
database does not know, from what its driver says the buttons are.
"""
from extensions.gamepad.guid import (
    DRIVER_HIDAPI,
    JoystickGuid,
    guid_to_string,
    joystick_guid_info,
    joystick_guid_uses_version,
    string_to_guid,
)
from extensions.gamepad.ids import (
    AXIS_COUNT,
    AXIS_INVALID,
    BUTTON_COUNT,
    BUTTON_DPAD_DOWN,
    BUTTON_DPAD_LEFT,
    BUTTON_DPAD_RIGHT,
    BUTTON_DPAD_UP,
    BUTTON_INVALID,
    JOYSTICK_AXIS_MAX,
    JOYSTICK_AXIS_MIN,
    GamepadAxis,
    GamepadButton,
    equal_ignoring_case,
    gamepad_axis_from_string,
    gamepad_button_from_string,
    gamepad_string_for_axis,
    gamepad_string_for_button,
    is_trigger,
)
from extensions.gamepad.names import hex4
from core.ordinal import ordinal_valid

comptime CRC_FIELD = "crc:"
comptime TYPE_FIELD = "type:"
comptime FACE_FIELD = "face:"
comptime PLATFORM_FIELD = "platform:"
comptime HINT_FIELD = "hint:"
comptime BUTTON_LABELS_HINT = "SDL_GAMECONTROLLER_USE_BUTTON_LABELS"
# The longest control or input name a field can have. SDL keeps each in
# a 20-byte buffer.
comptime MAX_ELEMENT_NAME = 20

# The four hat directions, as bits. SDL: `SDL_HAT_UP` and the rest.
comptime HAT_CENTERED = 0x00
comptime HAT_UP = 0x01
comptime HAT_RIGHT = 0x02
comptime HAT_DOWN = 0x04
comptime HAT_LEFT = 0x08


@fieldwise_init
struct BindType(Equatable, ImplicitlyCopyable, Writable):
    """What a binding reads or writes. SDL: `SDL_GamepadBindingType`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 4 kinds.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 3)


comptime BIND_NONE = BindType(0)
comptime BIND_BUTTON = BindType(1)
comptime BIND_AXIS = BindType(2)
comptime BIND_HAT = BindType(3)


@fieldwise_init
struct MappingPriority(Comparable, ImplicitlyCopyable, Writable):
    """Who added a mapping. A mapping replaces one of the same or a lower
    priority only. SDL: `SDL_GamepadMappingPriority`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 3 priorities.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 2)

    def __lt__(self, other: Self) -> Bool:
        """Return True if this priority is lower.

        Args:
            other: The other priority.

        Returns:
            Whether this value is less.
        """
        return self.value < other.value

    def __eq__(self, other: Self) -> Bool:
        """Return True if the priorities are the same.

        Args:
            other: The other priority.

        Returns:
            Whether the values are equal.
        """
        return self.value == other.value


# A built-in mapping.
comptime PRIORITY_DEFAULT = MappingPriority(0)
# A mapping the program added.
comptime PRIORITY_API = MappingPriority(1)
# A mapping the user gave.
comptime PRIORITY_USER = MappingPriority(2)


struct GamepadBinding(Equatable, ImplicitlyCopyable, Writable):
    """One joystick input bound to one gamepad control. SDL:
    `SDL_GamepadBinding`.

    A field the input or output kind does not use holds zero, so that two
    bindings compare equal when they bind the same things, as SDL's
    `memcmp` does.
    """

    var input_type: BindType
    # The joystick button, for `BIND_BUTTON` input.
    var input_button: Int
    # The joystick axis and its range, for `BIND_AXIS` input. The range
    # runs from `input_axis_min` to `input_axis_max`, which can be in
    # either order: an inverted axis has them swapped.
    var input_axis: Int
    var input_axis_min: Int
    var input_axis_max: Int
    # The hat and its direction bits, for `BIND_HAT` input.
    var input_hat: Int
    var input_hat_mask: Int
    var output_type: BindType
    # The gamepad button, for `BIND_BUTTON` output.
    var output_button: GamepadButton
    # The gamepad axis and its range, for `BIND_AXIS` output.
    var output_axis: GamepadAxis
    var output_axis_min: Int
    var output_axis_max: Int

    def __init__(out self):
        """Create a binding of nothing to nothing."""
        self.input_type = BIND_NONE
        self.input_button = 0
        self.input_axis = 0
        self.input_axis_min = 0
        self.input_axis_max = 0
        self.input_hat = 0
        self.input_hat_mask = 0
        self.output_type = BIND_NONE
        self.output_button = GamepadButton(0)
        self.output_axis = GamepadAxis(0)
        self.output_axis_min = 0
        self.output_axis_max = 0

    def __eq__(self, other: Self) -> Bool:
        """Return True if two bindings bind the same input to the same
        output.

        Args:
            other: The other binding.

        Returns:
            Whether every field is equal.
        """
        return (
            self.input_type == other.input_type
            and self.input_button == other.input_button
            and self.input_axis == other.input_axis
            and self.input_axis_min == other.input_axis_min
            and self.input_axis_max == other.input_axis_max
            and self.input_hat == other.input_hat
            and self.input_hat_mask == other.input_hat_mask
            and self.output_type == other.output_type
            and self.output_button == other.output_button
            and self.output_axis == other.output_axis
            and self.output_axis_min == other.output_axis_min
            and self.output_axis_max == other.output_axis_max
        )

    def has_same_output(self, other: Self) -> Bool:
        """Return True if two bindings drive the same control. SDL:
        `HasSameOutput`.

        Args:
            other: The other binding.

        Returns:
            Whether both drive the same axis, or the same button.
        """
        if self.output_type != other.output_type:
            return False
        if self.output_type == BIND_AXIS:
            return self.output_axis == other.output_axis
        return self.output_button == other.output_button


def _is_digit(bytes: Span[UInt8, _], index: Int) -> Bool:
    """Return True if a byte is an ASCII digit.

    Args:
        bytes: The bytes.
        index: The place. A place past the end is not a digit.

    Returns:
        Whether the byte is 0 to 9.
    """
    return index < len(bytes) and bytes[index] >= 48 and bytes[index] <= 57


def _digits(bytes: Span[UInt8, _], start: Int) -> Int:
    """Read the decimal digits from a place, as C's `atoi` does after a
    digit.

    Args:
        bytes: The bytes.
        start: The first digit.

    Returns:
        The value of the digits up to the first byte that is not one.
    """
    var value = 0
    var index = start
    while _is_digit(bytes, index):
        value = value * 10 + Int(bytes[index] - 48)
        index += 1
    return value


def parse_gamepad_element(
    mut bindings: List[GamepadBinding],
    game_name: String,
    joystick_name: String,
    baxy: Bool,
) -> Bool:
    """Add the binding one mapping field names. SDL:
    `SDL_PrivateParseGamepadElement`.

    Args:
        bindings: The bindings so far. The new one is appended, unless an
            equal one is there.
        game_name: The control, such as `a`, `+leftx` or `lefttrigger`.
        joystick_name: The input, such as `b0`, `-a1`, `a2~` or `h0.4`.
        baxy: Whether the mapping names face buttons by Nintendo labels.

    Returns:
        False when the control or the input is not one, which skips the
        field. True otherwise.
    """
    var bind = GamepadBinding()
    var game = game_name
    var half_output = 0
    if game.startswith("+") or game.startswith("-"):
        half_output = Int(game.as_bytes()[0])
        var rest = String(game[byte=1:])
        game = rest
    var axis = gamepad_axis_from_string(game)
    var button = gamepad_button_from_string(game, baxy)
    if axis != AXIS_INVALID:
        bind.output_type = BIND_AXIS
        bind.output_axis = axis
        if is_trigger(axis) or half_output == ord("+"):
            bind.output_axis_min = 0
            bind.output_axis_max = JOYSTICK_AXIS_MAX
        elif half_output == ord("-"):
            bind.output_axis_min = 0
            bind.output_axis_max = JOYSTICK_AXIS_MIN
        else:
            bind.output_axis_min = JOYSTICK_AXIS_MIN
            bind.output_axis_max = JOYSTICK_AXIS_MAX
    elif button != BUTTON_INVALID:
        bind.output_type = BIND_BUTTON
        bind.output_button = button
    else:
        return False

    var input = joystick_name
    var half_input = 0
    if input.startswith("+") or input.startswith("-"):
        half_input = Int(input.as_bytes()[0])
        var rest = String(input[byte=1:])
        input = rest
    var invert = input.endswith("~")
    var bytes = input.as_bytes()
    if len(bytes) > 0 and bytes[0] == UInt8(ord("a")) and _is_digit(bytes, 1):
        bind.input_type = BIND_AXIS
        bind.input_axis = _digits(bytes, 1)
        if half_input == ord("+"):
            bind.input_axis_min = 0
            bind.input_axis_max = JOYSTICK_AXIS_MAX
        elif half_input == ord("-"):
            bind.input_axis_min = 0
            bind.input_axis_max = JOYSTICK_AXIS_MIN
        else:
            bind.input_axis_min = JOYSTICK_AXIS_MIN
            bind.input_axis_max = JOYSTICK_AXIS_MAX
        if invert:
            var low = bind.input_axis_min
            bind.input_axis_min = bind.input_axis_max
            bind.input_axis_max = low
    elif len(bytes) > 0 and bytes[0] == UInt8(ord("b")) and _is_digit(bytes, 1):
        bind.input_type = BIND_BUTTON
        bind.input_button = _digits(bytes, 1)
    elif (
        len(bytes) > 3
        and bytes[0] == UInt8(ord("h"))
        and _is_digit(bytes, 1)
        and bytes[2] == UInt8(ord("."))
        and _is_digit(bytes, 3)
    ):
        bind.input_type = BIND_HAT
        bind.input_hat = _digits(bytes, 1)
        bind.input_hat_mask = _digits(bytes, 3)
    else:
        return False

    for existing in bindings:
        if existing == bind:
            return True
    bindings.append(bind)
    return True


def _put(mut buffer: List[UInt8], at: Int, byte: UInt8):
    """Write a byte into a name buffer, as SDL writes `buffer[i]`.

    Args:
        buffer: The bytes so far.
        at: The place to write.
        byte: The byte.
    """
    if at < len(buffer):
        buffer[at] = byte
    else:
        buffer.append(byte)


def parse_gamepad_mapping(fields: String, baxy: Bool) -> List[GamepadBinding]:
    """Return the bindings of a mapping's fields. SDL:
    `SDL_PrivateParseGamepadConfigString`.

    Spaces are ignored anywhere. A field that is not a binding is
    skipped. A name longer than 20 bytes ends the parse, as in SDL, and
    the bindings before it are kept. A second colon in a field starts the
    input name again over the bytes already there, as in SDL.

    Args:
        fields: The mapping after its GUID and name.
        baxy: Whether the mapping names face buttons by Nintendo labels.

    Returns:
        The bindings, in the order of the fields.
    """
    var bindings = List[GamepadBinding]()
    var game = List[UInt8]()
    var joystick = List[UInt8]()
    var in_game = True
    var at = 0
    for byte in fields.as_bytes():
        if byte == UInt8(ord(":")):
            at = 0
            in_game = False
        elif byte == UInt8(ord(" ")):
            continue
        elif byte == UInt8(ord(",")):
            _ = parse_gamepad_element(
                bindings,
                String(unsafe_from_utf8=game),
                String(unsafe_from_utf8=joystick),
                baxy,
            )
            at = 0
            in_game = True
            game.clear()
            joystick.clear()
        elif at >= MAX_ELEMENT_NAME:
            return bindings^
        elif in_game:
            _put(game, at, byte)
            at += 1
        else:
            _put(joystick, at, byte)
            at += 1
    if len(game) > 0 or len(joystick) > 0:
        _ = parse_gamepad_element(
            bindings,
            String(unsafe_from_utf8=game),
            String(unsafe_from_utf8=joystick),
            baxy,
        )
    return bindings^


def fixup_hidapi_mapping(mut bindings: List[GamepadBinding]):
    """Move an old HIDAPI mapping's d-pad from buttons to hat 0. SDL:
    `SDL_FixupHIDAPIMapping`.

    An old HIDAPI mapping binds each button to the joystick button of the
    same number, with the d-pad as buttons 11 to 14. Newer HIDAPI drivers
    report the d-pad as a hat, so the buttons after it move down by 4.

    Args:
        bindings: The bindings, changed in place.
    """
    var needs_fixup = False
    for binding in bindings:
        if (
            binding.output_type == BIND_BUTTON
            and binding.output_button.value >= BUTTON_DPAD_UP.value
        ):
            needs_fixup = (
                binding.input_type == BIND_BUTTON
                and binding.input_button == binding.output_button.value
            )
            break
    if not needs_fixup:
        return
    var hats: List[Int] = [HAT_UP, HAT_DOWN, HAT_LEFT, HAT_RIGHT]
    for index in range(len(bindings)):  # pragma: no branch
        ref binding = bindings[index]
        if binding.input_type != BIND_BUTTON or (
            binding.output_type != BIND_BUTTON
        ):
            continue
        var button = binding.output_button.value
        if button >= BUTTON_DPAD_UP.value and button <= BUTTON_DPAD_RIGHT.value:
            binding.input_type = BIND_HAT
            binding.input_button = 0
            binding.input_hat = 0
            binding.input_hat_mask = hats[button - BUTTON_DPAD_UP.value]
        elif button > BUTTON_DPAD_RIGHT.value:
            binding.input_button -= 4


def _is_space(byte: UInt8) -> Bool:
    """Return True if a byte is white space, as C's `isspace` says.

    Args:
        byte: The byte.

    Returns:
        Whether it is a space, a tab, a line feed, a vertical tab, a form
        feed or a carriage return.
    """
    return byte == 32 or (byte >= 9 and byte <= 13)


def mapping_guid_field(mapping: String) raises -> String:
    """Return the GUID field of a mapping string. SDL:
    `SDL_PrivateGetGamepadGUIDFromMappingString`, as on Linux.

    Args:
        mapping: The whole mapping string.

    Returns:
        The text before the first comma.

    Raises:
        Error: If the mapping has no comma.
    """
    var comma = mapping.find(",")
    if comma < 0:
        raise Error("A gamepad mapping has no GUID field: " + mapping)
    return String(mapping[byte=:comma])


def mapping_name_field(mapping: String) raises -> String:
    """Return the name field of a mapping string. SDL:
    `SDL_PrivateGetGamepadNameFromMappingString`.

    Args:
        mapping: The whole mapping string.

    Returns:
        The text between the first and the second comma.

    Raises:
        Error: If the mapping has fewer than two commas.
    """
    var first = mapping.find(",")
    var second = mapping.find(",", first + 1) if first >= 0 else -1
    if second < 0:
        raise Error("A gamepad mapping has no name field: " + mapping)
    return String(mapping[byte = first + 1 : second])


def mapping_fields(mapping: String) raises -> String:
    """Return the fields of a mapping string after its GUID and name.
    SDL: `SDL_PrivateGetGamepadMappingFromMappingString`.

    Args:
        mapping: The whole mapping string.

    Returns:
        The text after the second comma, with white space trimmed from
        both ends.

    Raises:
        Error: If the mapping has fewer than two commas.
    """
    var first = mapping.find(",")
    var second = mapping.find(",", first + 1) if first >= 0 else -1
    if second < 0:
        raise Error("A gamepad mapping has no fields: " + mapping)
    var bytes = mapping.as_bytes()
    var start = second + 1
    while start < len(bytes) and _is_space(bytes[start]):
        start += 1
    var end = len(bytes)
    while end > start and _is_space(bytes[end - 1]):
        end -= 1
    return String(mapping[byte=start:end])


def field_value(fields: String, field: String) -> String:
    """Return the value of a named field, such as `type:`.

    Args:
        fields: The mapping, or its fields.
        field: The field name with its colon.

    Returns:
        The text from after the name to the next comma or the end, or an
        empty string when the field is not there.
    """
    var at = fields.find(field)
    if at < 0:
        return ""
    var start = at + field.byte_length()
    var comma = fields.find(",", start)
    if comma < 0:
        return String(fields[byte=start:])
    return String(fields[byte=start:comma])


def _hex_value(text: String) -> Int:
    """Read a hex number as C's `strtol(text, NULL, 16)` does.

    Args:
        text: The text: optional white space, an optional sign, an
            optional `0x`, then hex digits.

    Returns:
        The value of the digits, or 0 when there are none.
    """
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes) and _is_space(bytes[index]):
        index += 1
    var negative = False
    if index < len(bytes) and (
        bytes[index] == UInt8(ord("+")) or bytes[index] == UInt8(ord("-"))
    ):
        negative = bytes[index] == UInt8(ord("-"))
        index += 1
    if (
        index + 2 < len(bytes)
        and bytes[index] == UInt8(ord("0"))
        and _lower_byte(bytes[index + 1]) == UInt8(ord("x"))
        and _hex_digit(bytes[index + 2]) >= 0
    ):
        index += 2
    var value = 0
    while index < len(bytes) and _hex_digit(bytes[index]) >= 0:
        value = value * 16 + _hex_digit(bytes[index])
        index += 1
    return -value if negative else value


def _lower_byte(byte: UInt8) -> UInt8:
    """Return a byte in lowercase, if it is an uppercase ASCII letter.

    Args:
        byte: The byte.

    Returns:
        The lowercase byte, or the byte as it was.
    """
    if byte >= 65 and byte <= 90:
        return byte + 32
    return byte


def _hex_digit(byte: UInt8) -> Int:
    """Return the value of a hex digit.

    Args:
        byte: The byte.

    Returns:
        The value from 0 to 15, or -1 when the byte is not a hex digit.
    """
    var lower = _lower_byte(byte)
    if lower >= 48 and lower <= 57:
        return Int(lower) - 48
    if lower >= 97 and lower <= 102:
        return Int(lower) - 97 + 10
    return -1


def mapping_crc(fields: String) -> UInt16:
    """Return the CRC a mapping's `crc:` field gives.

    Args:
        fields: The mapping, or its fields.

    Returns:
        The CRC, or 0 when there is no `crc:` field. Only the low 16 bits
        of the value are kept, as SDL's cast does.
    """
    var at = fields.find(CRC_FIELD)
    if at < 0:
        return 0
    return UInt16(
        _hex_value(String(fields[byte = at + CRC_FIELD.byte_length() :]))
        & 0xFFFF
    )


def convert_mapping_to_positional(mapping: String) -> String:
    """Swap a labeled mapping's face buttons into positions. SDL:
    `SDL_ConvertMappingToPositional`, corrected.

    A mapping with the hint `SDL_GAMECONTROLLER_USE_BUTTON_LABELS` names
    the face buttons by their Nintendo labels. This writes `a` as `b`, `b`
    as `a`, `x` as `y` and `y` as `x`, and turns the hint into
    `!SDL_GAMECONTROLLER_USE_BUTTON_LABELS`, which says positions.

    SDL 3.2.24 finds the first `x:` anywhere in the string, which is the
    end of `leftx:` in a mapping sorted by name. Then it swaps `leftx` and
    `lefty` and leaves `x` and `y` as they were. This port finds each of
    the four names only at the start of a field, as SDL's main branch
    does from commit 3da8c67d (`SDL_ConvertMappingToPositionalBAXY`).

    Args:
        mapping: The whole mapping string.

    Returns:
        The positional mapping.
    """
    var bytes = List[UInt8](mapping.as_bytes())
    var swaps: List[String] = ["a:", "b:", "x:", "y:"]
    var into: List[UInt8] = [
        UInt8(ord("b")),
        UInt8(ord("a")),
        UInt8(ord("y")),
        UInt8(ord("x")),
    ]
    for index in range(len(swaps)):  # pragma: no branch
        var at = mapping.find("," + swaps[index])
        if at >= 0:
            bytes[at + 1] = into[index]
    var text = String(unsafe_from_utf8=bytes)
    var hint = text.find(HINT_FIELD + BUTTON_LABELS_HINT)
    if hint >= 0:
        var cut = hint + HINT_FIELD.byte_length()
        text = String(text[byte=:cut]) + "!" + String(text[byte=cut:])
    return text


struct GamepadMapping(Copyable, Movable):
    """One mapping in the database. SDL: `GamepadMapping_t`."""

    var guid: JoystickGuid
    var name: String
    # The fields after the GUID and the name.
    var mapping: String
    var priority: MappingPriority

    def __init__(
        out self,
        guid: JoystickGuid,
        name: String,
        mapping: String,
        priority: MappingPriority,
    ):
        """Create a mapping.

        Args:
            guid: The GUID it is for, without its CRC.
            name: The gamepad's name.
            mapping: The fields after the GUID and the name.
            priority: Who added it.
        """
        self.guid = guid
        self.name = name
        self.mapping = mapping
        self.priority = priority


@fieldwise_init
struct MappingKind(Equatable, ImplicitlyCopyable, Writable):
    """What an automatic mapping binds a control to. SDL: `EMappingKind`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 4 kinds.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 3)


comptime MAPPING_NONE = MappingKind(0)
comptime MAPPING_BUTTON = MappingKind(1)
comptime MAPPING_AXIS = MappingKind(2)
comptime MAPPING_HAT = MappingKind(3)


struct InputMapping(Equatable, ImplicitlyCopyable, Writable):
    """The joystick input a driver says a control is. SDL:
    `SDL_InputMapping`."""

    var kind: MappingKind
    # A button or an axis number, or for a hat `hat << 4 | direction bits`.
    var target: Int
    var axis_reversed: Bool
    var half_axis_positive: Bool
    var half_axis_negative: Bool

    def __init__(out self, kind: MappingKind = MAPPING_NONE, target: Int = 0):
        """Create an input mapping.

        Args:
            kind: What the control is bound to.
            target: The button, the axis, or the hat and its direction.
        """
        self.kind = kind
        self.target = target
        self.axis_reversed = False
        self.half_axis_positive = False
        self.half_axis_negative = False


struct AutoMapping(Copyable, Movable):
    """The inputs a driver gives each control of a gamepad. SDL:
    `SDL_GamepadMapping`.

    `buttons` is indexed by `GamepadButton` and `axes` by `GamepadAxis`.
    """

    var buttons: List[InputMapping]
    var axes: List[InputMapping]

    def __init__(out self):
        """Create a mapping that binds nothing."""
        self.buttons = List[InputMapping](
            length=BUTTON_COUNT, fill=InputMapping()
        )
        self.axes = List[InputMapping](length=AXIS_COUNT, fill=InputMapping())


def _input_text(input: InputMapping) -> String:
    """Return the mapping text of an input. SDL: the inside of
    `SDL_PrivateAppendToMappingString`.

    Args:
        input: The input, which is not `MAPPING_NONE`.

    Returns:
        `b3`, `+a2~` or `h0.4`.
    """
    if input.kind == MAPPING_BUTTON:
        return "b" + String(input.target)
    if input.kind == MAPPING_AXIS:
        var sign = "+" if input.half_axis_positive else (
            "-" if input.half_axis_negative else ""
        )
        return (
            sign
            + "a"
            + String(input.target)
            + ("~" if input.axis_reversed else "")
        )
    return "h" + String(input.target >> 4) + "." + String(input.target & 0x0F)


def automatic_mapping_string(name: String, raw: AutoMapping) -> String:
    """Write the mapping string of an automatic mapping. SDL: the text that
    `SDL_PrivateGenerateAutomaticGamepadMapping` builds.

    The GUID field is `none`. Commas in the name become spaces, and the
    name is cut to 127 bytes, as SDL's buffer does.

    Args:
        name: The device's name.
        raw: The inputs.

    Returns:
        The mapping string.
    """
    var bytes = List[UInt8]()
    for byte in name.as_bytes():
        if len(bytes) == 127:
            break
        bytes.append(UInt8(ord(" ")) if byte == UInt8(ord(",")) else byte)
    var text = "none," + String(unsafe_from_utf8=bytes) + ","
    # SDL's order: the buttons through the d-pad, misc1 to misc6, the
    # paddles, the axes, then the touchpad.
    var order: List[Int] = [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        21,
        22,
        23,
        24,
        25,
        16,
        17,
        18,
        19,
    ]
    for button in order:  # pragma: no branch
        if raw.buttons[button].kind != MAPPING_NONE:
            text += gamepad_string_for_button(GamepadButton(button)) + ":"
            text += _input_text(raw.buttons[button]) + ","
    for axis in range(AXIS_COUNT):  # pragma: no branch
        if raw.axes[axis].kind != MAPPING_NONE:
            text += gamepad_string_for_axis(GamepadAxis(axis)) + ":"
            text += _input_text(raw.axes[axis]) + ","
    if raw.buttons[20].kind != MAPPING_NONE:
        text += "touchpad:" + _input_text(raw.buttons[20]) + ","
    return text


struct MappingDatabase(Movable):
    """The mappings SDL knows, by GUID. SDL: the list `s_pSupportedGamepads`
    and the functions that search it.

    A program fills one with `add_mapping`, usually from
    `linux_default_mappings` and then from a `gamecontrollerdb.txt`.
    """

    var mappings: List[GamepadMapping]
    # The mapping with the GUID `default`, or -1.
    var default_index: Int
    # The mapping with the GUID `xinput`, or -1.
    var xinput_index: Int

    def __init__(out self):
        """Create an empty database."""
        self.mappings = List[GamepadMapping]()
        self.default_index = -1
        self.xinput_index = -1

    def count(self) -> Int:
        """Return the number of mappings.

        Returns:
            How many there are.
        """
        return len(self.mappings)

    def match_mapping(
        self, guid: JoystickGuid, match_version: Bool, exact_match_crc: Bool
    ) -> Int:
        """Find the mapping for a GUID. SDL:
        `SDL_PrivateMatchGamepadMappingForGUID`.

        Args:
            guid: The joystick's GUID, with its CRC.
            match_version: Whether the version must match too.
            exact_match_crc: Whether a GUID with a CRC needs a mapping with
                the same CRC.

        Returns:
            The index of a mapping with the same CRC, or else of the first
            mapping without a CRC, or -1.
        """
        var crc = joystick_guid_info(guid).crc
        var key = guid
        key.set_crc(0)
        if not match_version:
            key.set_version(0)
        var best = -1
        for index in range(len(self.mappings)):
            ref mapping = self.mappings[index]
            if mapping.guid.is_zero():
                continue
            var candidate = mapping.guid
            if not match_version:
                candidate.set_version(0)
            if candidate != key:
                continue
            if mapping.mapping.find(CRC_FIELD) >= 0:
                if mapping_crc(mapping.mapping) != crc:
                    continue
                return index
            elif crc != 0 and exact_match_crc:
                continue
            if best < 0:
                best = index
        return best

    def mapping_for_guid(self, guid: JoystickGuid, adding: Bool) -> Int:
        """Find the best mapping for a GUID. SDL:
        `SDL_PrivateGetGamepadMappingForGUID`, without the drivers that
        are not ported.

        Args:
            guid: The joystick's GUID.
            adding: Whether a mapping is being added, so that only an
                exact match counts.

        Returns:
            The index of the mapping, or -1.
        """
        var index = self.match_mapping(guid, True, adding)
        if index >= 0 or adding:
            return index
        if joystick_guid_uses_version(guid):
            return self.match_mapping(guid, False, False)
        return -1

    def _add_mapping_for_guid(
        mut self,
        guid: JoystickGuid,
        mapping: String,
        priority: MappingPriority,
    ) raises -> Tuple[Int, Bool]:
        """Add or replace the mapping for a GUID. SDL:
        `SDL_PrivateAddMappingForGUID`.

        Args:
            guid: The GUID the mapping is for.
            mapping: The whole mapping string.
            priority: Who adds it.

        Returns:
            The index of the mapping, and whether it was there before.

        Raises:
            Error: If the mapping has no name or no fields.
        """
        var key = guid
        var name = mapping_name_field(mapping)
        var fields = mapping_fields(mapping)
        var crc = joystick_guid_info(key).crc
        if crc != 0:
            var crc_at = fields.find(CRC_FIELD)
            var tail = ""
            if crc_at >= 0:
                var comma = fields.find(",", crc_at)
                if comma >= 0:
                    tail = String(fields[byte = comma + 1 :])
                var head = String(fields[byte=:crc_at])
                fields = head
            var comma = (
                "" if fields.byte_length() == 0 or fields.endswith(",") else ","
            )
            fields = fields + comma + CRC_FIELD + hex4(Int(crc)) + "," + tail
        else:
            # SDL keeps the field's CRC in the same variable, so the GUID it
            # stores below is cleared of it too.
            crc = mapping_crc(fields)
            if crc != 0:
                key.set_crc(crc)
        var index = self.mapping_for_guid(key, True)
        if index >= 0:
            if self.mappings[index].priority <= priority:
                self.mappings[index].name = name
                self.mappings[index].mapping = fields
                self.mappings[index].priority = priority
            return (index, True)
        if crc != 0:
            key.set_crc(0)
        self.mappings.append(GamepadMapping(key, name, fields, priority))
        return (len(self.mappings) - 1, False)

    def add_mapping(
        mut self, mapping: String, priority: MappingPriority = PRIORITY_API
    ) raises -> Int:
        """Add a mapping string. SDL: `SDL_PrivateAddGamepadMapping`.

        A `hint:` field other than the button labels hint is read at its
        default value, since SDL's hints are not ported: `hint:NAME:=1`
        adds the mapping and `hint:NAME` skips it. `!` before the name
        negates it.

        Args:
            mapping: The whole mapping string.
            priority: Who adds it. A mapping replaces one of the same or a
                lower priority only.

        Returns:
            1 when the mapping is new, and 0 when it replaced one, kept a
            higher one, or was skipped by its hint.

        Raises:
            Error: If the priority is not valid, or the mapping has no
                GUID, name or fields.
        """
        if not priority.is_valid():
            raise Error("A gamepad mapping priority is not valid")
        var text = mapping
        var hint_at = text.find(HINT_FIELD)
        if hint_at >= 0:
            var bytes = text.as_bytes()
            var at = hint_at + HINT_FIELD.byte_length()
            var negate = at < len(bytes) and bytes[at] == UInt8(ord("!"))
            if negate:
                at += 1
            var start = at
            while (
                at < len(bytes)
                and bytes[at] != UInt8(ord(","))
                and bytes[at] != UInt8(ord(":"))
                and at - start < 127
            ):
                at += 1
            var hint = String(text[byte=start:at])
            var default_value = False
            if (
                at + 1 < len(bytes)
                and bytes[at] == UInt8(ord(":"))
                and bytes[at + 1] == UInt8(ord("="))
            ):
                default_value = (
                    _decimal_value(String(text[byte = at + 2 :])) != 0
                )
            if hint == BUTTON_LABELS_HINT:
                if not negate:
                    text = convert_mapping_to_positional(text)
            elif default_value == negate:
                return 0
        var guid_text = mapping_guid_field(text)
        var guid = string_to_guid(guid_text)
        var added = self._add_mapping_for_guid(guid, text, priority)
        if added[1]:
            return 0
        if equal_ignoring_case(guid_text, "default"):
            self.default_index = added[0]
        elif equal_ignoring_case(guid_text, "xinput"):
            self.xinput_index = added[0]
        return 1

    def add_mappings_from_text(
        mut self, text: String, platform: String = "Linux"
    ) raises -> Int:
        """Add the lines of a mapping file for one platform. SDL:
        `SDL_AddGamepadMappingsFromIO`.

        Each line is a mapping string. A line is added when its
        `platform:` field names the platform, ignoring case. Other lines,
        such as comments, are skipped. This reads the community file
        `gamecontrollerdb.txt`.

        Args:
            text: The file's text.
            platform: The platform, as SDL's `SDL_GetPlatform` names it.

        Returns:
            How many new mappings were added.

        Raises:
            Error: If a line for the platform has no GUID, name or fields.
        """
        var added = 0
        for piece in text.split("\n"):  # pragma: no branch
            var line = String(piece)
            var at = line.find(PLATFORM_FIELD)
            if at < 0:
                continue
            var start = at + PLATFORM_FIELD.byte_length()
            var comma = line.find(",", start)
            # SDL copies the name into a 64-byte buffer with its comma.
            if comma < 0 or comma - start + 2 >= 64:
                continue
            if equal_ignoring_case(String(line[byte=start:comma]), platform):
                added += self.add_mapping(line, PRIORITY_API)
        return added

    def mapping_for_name_and_guid(
        mut self, name: String, guid: JoystickGuid
    ) raises -> Int:
        """Find the mapping for a device. SDL:
        `SDL_PrivateGetGamepadMappingForNameAndGUID`, as on Linux.

        The Linux driver for the Xbox 360 wireless receiver reports the
        d-pad as buttons, so a receiver with no mapping gets one for that.

        Args:
            name: The device's name.
            guid: The device's GUID.

        Returns:
            The index of the mapping, or -1.

        Raises:
            Error: Never, since the receiver's mapping is well formed.
        """
        var index = self.mapping_for_guid(guid, False)
        if index < 0 and name.find("Xbox 360 Wireless Receiver") >= 0:
            index = self._add_mapping_for_guid(
                guid,
                (
                    "none,X360 Wireless Controller,a:b0,b:b1,back:b6,"
                    "dpdown:b14,dpleft:b11,dpright:b12,dpup:b13,guide:b8,"
                    "leftshoulder:b4,leftstick:b9,lefttrigger:a2,leftx:a0,"
                    "lefty:a1,rightshoulder:b5,rightstick:b10,"
                    "righttrigger:a5,rightx:a3,righty:a4,start:b7,x:b2,y:b3,"
                ),
                PRIORITY_DEFAULT,
            )[0]
        return index

    def generate_automatic_mapping(
        mut self, name: String, guid: JoystickGuid, raw: AutoMapping
    ) raises -> Int:
        """Add the mapping a driver's inputs give. SDL:
        `SDL_PrivateGenerateAutomaticGamepadMapping`.

        Args:
            name: The device's name.
            guid: The device's GUID. Its CRC is not used, so that a mapping
                added later without a CRC replaces this one.
            raw: The inputs of each control.

        Returns:
            The index of the mapping.

        Raises:
            Error: Never, since the mapping string is well formed.
        """
        var key = guid
        key.set_crc(0)
        return self._add_mapping_for_guid(
            key, automatic_mapping_string(name, raw), PRIORITY_DEFAULT
        )[0]

    def mapping_for_device(
        mut self, name: String, guid: JoystickGuid, raw: Optional[AutoMapping]
    ) raises -> Int:
        """Find or make the mapping for a device. SDL:
        `SDL_PrivateGetGamepadMapping`.

        Args:
            name: The device's name.
            guid: The device's GUID.
            raw: The driver's inputs, or None when the driver cannot say.

        Returns:
            The index of the mapping, of the `default` mapping, or -1 when
            the device is not a gamepad.

        Raises:
            Error: Never, since generated mappings are well formed.
        """
        var index = self.mapping_for_name_and_guid(name, guid)
        if index < 0 and raw:
            index = self.generate_automatic_mapping(name, guid, raw.value())
        if index < 0:
            return self.default_index
        return index

    def mapping_string(
        self,
        index: Int,
        guid: Optional[JoystickGuid] = None,
        platform: String = "Linux",
    ) raises -> String:
        """Return a whole mapping string. SDL: `CreateMappingString`.

        Args:
            index: The mapping.
            guid: The GUID to write, or None for the mapping's own. SDL
                writes the GUID it was asked about.
            platform: The platform to add when the mapping has no
                `platform:` field.

        Returns:
            The GUID, the name and the fields, with one `platform:` field.

        Raises:
            Error: If the index is out of range.
        """
        if index < 0 or index >= len(self.mappings):
            raise Error("A gamepad mapping index is out of range")
        ref mapping = self.mappings[index]
        var written = guid.value() if guid else mapping.guid
        var text = guid_to_string(written) + "," + mapping.name + ","
        text += mapping.mapping
        if mapping.mapping.find(PLATFORM_FIELD) < 0:
            if not mapping.mapping.endswith(","):
                text += ","
            text += PLATFORM_FIELD + platform + ","
        var first = text.find(PLATFORM_FIELD)
        var second = text.find(PLATFORM_FIELD, first + 1)
        if second >= 0:
            var head = String(text[byte=:second])
            text = head
        return text


def mapping_for_guid_string(
    database: MappingDatabase, guid: JoystickGuid
) raises -> String:
    """Return the mapping string for a GUID. SDL:
    `SDL_GetGamepadMappingForGUID`.

    Args:
        database: The mappings.
        guid: The GUID.

    Returns:
        The best mapping, written with this GUID.

    Raises:
        Error: If no mapping fits the GUID.
    """
    var index = database.mapping_for_guid(guid, False)
    if index < 0:
        raise Error("No gamepad mapping fits " + guid_to_string(guid))
    return database.mapping_string(index, guid)


def _decimal_value(text: String) -> Int:
    """Read a decimal number as C's `atoi` does.

    Args:
        text: The text: optional white space, an optional sign, then
            digits.

    Returns:
        The value, or 0 when there are no digits.
    """
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes) and _is_space(bytes[index]):
        index += 1
    var negative = False
    if index < len(bytes) and (
        bytes[index] == UInt8(ord("+")) or bytes[index] == UInt8(ord("-"))
    ):
        negative = bytes[index] == UInt8(ord("-"))
        index += 1
    var value = _digits(bytes, index)
    return -value if negative else value


def uses_button_labels(fields: String) -> Bool:
    """Return True if a mapping names its face buttons by Nintendo labels.

    Args:
        fields: The mapping's fields.

    Returns:
        Whether it has `hint:SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1`.
    """
    return fields.find(",hint:" + BUTTON_LABELS_HINT + ":=1") >= 0


def is_hidapi_guid(guid: JoystickGuid) -> Bool:
    """Return True if SDL's HIDAPI driver made a GUID. SDL:
    `SDL_IsJoystickHIDAPI`.

    Args:
        guid: The GUID.

    Returns:
        Whether its driver byte is `h`.
    """
    return guid.driver() == DRIVER_HIDAPI
