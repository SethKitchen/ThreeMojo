# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of include/SDL3/SDL_gamepad.h and
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

"""The kinds of a gamepad, its buttons and axes, as types.

SDL names a gamepad's controls by position, not by the letter printed on
them. `BUTTON_SOUTH` is the bottom face button: A on an Xbox controller,
Cross on a PlayStation controller, B on a Nintendo controller. A
`GamepadButtonLabel` is the letter or the shape, and `button_label_for_type`
gives it.

A `GamepadAxis` value is from -32768 to 32767. The two triggers are from 0
to 32767. These are SDL's `SDL_JOYSTICK_AXIS_MIN` and `SDL_JOYSTICK_AXIS_MAX`.

The names in the mapping strings are SDL's: `a`, `b`, `x`, `y`, `back`,
`leftx`, `righttrigger` and the rest. `a` is the south button, `b` the
east, `x` the west and `y` the north.
"""
from core.ordinal import ordinal_label, ordinal_valid

# The lowest value of a joystick axis. SDL: `SDL_JOYSTICK_AXIS_MIN`.
comptime JOYSTICK_AXIS_MIN = -32768
# The highest value of a joystick axis. SDL: `SDL_JOYSTICK_AXIS_MAX`.
comptime JOYSTICK_AXIS_MAX = 32767


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


def equal_ignoring_case(a: String, b: String) -> Bool:
    """Return True if two strings are equal when case is ignored.

    The comparison folds ASCII letters only, as SDL's `SDL_strcasecmp`
    does for these names.

    Args:
        a: The first string.
        b: The second string.

    Returns:
        Whether the two strings have the same bytes, ignoring ASCII case.
    """
    var left = a.as_bytes()
    var right = b.as_bytes()
    if len(left) != len(right):
        return False
    for index in range(len(left)):
        if _lower(left[index]) != _lower(right[index]):
            return False
    return True


def _drop_sign(text: String) -> String:
    """Return a name without one leading `+` or `-`.

    Args:
        text: The name.

    Returns:
        The name after its sign, or the name as it was.
    """
    if text.startswith("+") or text.startswith("-"):
        return String(text[byte=1:])
    return text


def _find_name(text: String, names: List[String]) -> Int:
    """Return the index of a name in a list, ignoring case.

    Args:
        text: The name to look for.
        names: The names, in order.

    Returns:
        The index of the first equal name, or -1 when there is none.
    """
    for index in range(len(names)):  # pragma: no branch
        if equal_ignoring_case(text, names[index]):
            return index
    return -1


@fieldwise_init
struct GamepadType(Equatable, ImplicitlyCopyable, Writable):
    """What kind of gamepad it is. SDL: `SDL_GamepadType`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 11 types.

        Returns:
            Whether the value is 0 to 10.
        """
        return ordinal_valid(self.value, 10)


# A gamepad SDL cannot place. SDL: `SDL_GAMEPAD_TYPE_UNKNOWN`.
comptime GAMEPAD_TYPE_UNKNOWN = GamepadType(0)
# A gamepad with the standard layout. SDL: `SDL_GAMEPAD_TYPE_STANDARD`.
comptime GAMEPAD_TYPE_STANDARD = GamepadType(1)
comptime GAMEPAD_TYPE_XBOX360 = GamepadType(2)
comptime GAMEPAD_TYPE_XBOXONE = GamepadType(3)
comptime GAMEPAD_TYPE_PS3 = GamepadType(4)
comptime GAMEPAD_TYPE_PS4 = GamepadType(5)
comptime GAMEPAD_TYPE_PS5 = GamepadType(6)
comptime GAMEPAD_TYPE_NINTENDO_SWITCH_PRO = GamepadType(7)
comptime GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_LEFT = GamepadType(8)
comptime GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_RIGHT = GamepadType(9)
comptime GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR = GamepadType(10)


def _type_names() -> List[String]:
    """Return the mapping names of the gamepad types, in order.

    Returns:
        SDL's `map_StringForGamepadType`.
    """
    return [
        "unknown",
        "standard",
        "xbox360",
        "xboxone",
        "ps3",
        "ps4",
        "ps5",
        "switchpro",
        "joyconleft",
        "joyconright",
        "joyconpair",
    ]


def gamepad_type_from_string(text: String) -> GamepadType:
    """Return the gamepad type a mapping names. SDL:
    `SDL_GetGamepadTypeFromString`.

    One leading `+` or `-` is skipped. Case is ignored.

    Args:
        text: The name, such as `ps4`.

    Returns:
        The type, or `GAMEPAD_TYPE_UNKNOWN` for a name that is not one.
    """
    var index = _find_name(_drop_sign(text), _type_names())
    if index < 0:
        return GAMEPAD_TYPE_UNKNOWN
    return GamepadType(index)


def gamepad_string_for_type(type: GamepadType) -> String:
    """Return the mapping name of a gamepad type. SDL:
    `SDL_GetGamepadStringForType`.

    Args:
        type: The type.

    Returns:
        The name, or an empty string for `GAMEPAD_TYPE_UNKNOWN` and a type
        that is not valid. SDL returns NULL there.
    """
    var known = type.is_valid() and type != GAMEPAD_TYPE_UNKNOWN
    return ordinal_label(known, type.value, _type_names(), "")


@fieldwise_init
struct GamepadButton(Equatable, ImplicitlyCopyable, Writable):
    """A button of a gamepad, by position. SDL: `SDL_GamepadButton`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 26 buttons.

        Returns:
            Whether the value is 0 to 25. `BUTTON_INVALID` is not valid.
        """
        return ordinal_valid(self.value, BUTTON_COUNT - 1)


# The number of gamepad buttons. SDL: `SDL_GAMEPAD_BUTTON_COUNT`.
comptime BUTTON_COUNT = 26
# No button. SDL: `SDL_GAMEPAD_BUTTON_INVALID`.
comptime BUTTON_INVALID = GamepadButton(-1)
# The bottom face button: Xbox A, PlayStation Cross.
comptime BUTTON_SOUTH = GamepadButton(0)
# The right face button: Xbox B, PlayStation Circle.
comptime BUTTON_EAST = GamepadButton(1)
# The left face button: Xbox X, PlayStation Square.
comptime BUTTON_WEST = GamepadButton(2)
# The top face button: Xbox Y, PlayStation Triangle.
comptime BUTTON_NORTH = GamepadButton(3)
comptime BUTTON_BACK = GamepadButton(4)
comptime BUTTON_GUIDE = GamepadButton(5)
comptime BUTTON_START = GamepadButton(6)
comptime BUTTON_LEFT_STICK = GamepadButton(7)
comptime BUTTON_RIGHT_STICK = GamepadButton(8)
comptime BUTTON_LEFT_SHOULDER = GamepadButton(9)
comptime BUTTON_RIGHT_SHOULDER = GamepadButton(10)
comptime BUTTON_DPAD_UP = GamepadButton(11)
comptime BUTTON_DPAD_DOWN = GamepadButton(12)
comptime BUTTON_DPAD_LEFT = GamepadButton(13)
comptime BUTTON_DPAD_RIGHT = GamepadButton(14)
# An extra button: the Xbox Series X share button, the PS5 microphone.
comptime BUTTON_MISC1 = GamepadButton(15)
# The upper paddle under the right hand: Xbox Elite P1.
comptime BUTTON_RIGHT_PADDLE1 = GamepadButton(16)
# The upper paddle under the left hand: Xbox Elite P3.
comptime BUTTON_LEFT_PADDLE1 = GamepadButton(17)
# The lower paddle under the right hand: Xbox Elite P2.
comptime BUTTON_RIGHT_PADDLE2 = GamepadButton(18)
# The lower paddle under the left hand: Xbox Elite P4.
comptime BUTTON_LEFT_PADDLE2 = GamepadButton(19)
# The PS4 and PS5 touchpad button.
comptime BUTTON_TOUCHPAD = GamepadButton(20)
comptime BUTTON_MISC2 = GamepadButton(21)
comptime BUTTON_MISC3 = GamepadButton(22)
comptime BUTTON_MISC4 = GamepadButton(23)
comptime BUTTON_MISC5 = GamepadButton(24)
comptime BUTTON_MISC6 = GamepadButton(25)


def _button_names() -> List[String]:
    """Return the mapping names of the buttons, in order.

    Returns:
        SDL's `map_StringForGamepadButton`.
    """
    return [
        "a",
        "b",
        "x",
        "y",
        "back",
        "guide",
        "start",
        "leftstick",
        "rightstick",
        "leftshoulder",
        "rightshoulder",
        "dpup",
        "dpdown",
        "dpleft",
        "dpright",
        "misc1",
        "paddle1",
        "paddle2",
        "paddle3",
        "paddle4",
        "touchpad",
        "misc2",
        "misc3",
        "misc4",
        "misc5",
        "misc6",
    ]


def swap_face_button(button: GamepadButton) -> GamepadButton:
    """Return the face button a labeled mapping means by a position.

    A mapping with the hint `SDL_GAMECONTROLLER_USE_BUTTON_LABELS` names
    the face buttons by their Nintendo labels. Its `a` is the east button,
    its `b` the south, its `x` the north and its `y` the west.

    Args:
        button: The button the name gives by position.

    Returns:
        The button with south and east swapped and west and north
        swapped. Any other button is returned as it was.
    """
    if button == BUTTON_SOUTH:
        return BUTTON_EAST
    if button == BUTTON_EAST:
        return BUTTON_SOUTH
    if button == BUTTON_WEST:
        return BUTTON_NORTH
    if button == BUTTON_NORTH:
        return BUTTON_WEST
    return button


def gamepad_button_from_string(
    text: String, baxy: Bool = False
) -> GamepadButton:
    """Return the button a mapping names. SDL:
    `SDL_PrivateGetGamepadButtonFromString`.

    Case is ignored. A sign is not skipped: `+a` names no button.

    Args:
        text: The name, such as `leftshoulder`.
        baxy: Whether the mapping uses Nintendo labels, so that the face
            buttons are swapped.

    Returns:
        The button, or `BUTTON_INVALID` for a name that is not one.
    """
    var index = _find_name(text, _button_names())
    if index < 0:
        return BUTTON_INVALID
    if baxy:
        return swap_face_button(GamepadButton(index))
    return GamepadButton(index)


def gamepad_string_for_button(button: GamepadButton) -> String:
    """Return the mapping name of a button. SDL:
    `SDL_GetGamepadStringForButton`.

    Args:
        button: The button.

    Returns:
        The name, or an empty string for a button that is not valid.
    """
    return ordinal_label(button.is_valid(), button.value, _button_names(), "")


@fieldwise_init
struct GamepadAxis(Equatable, ImplicitlyCopyable, Writable):
    """An axis of a gamepad. SDL: `SDL_GamepadAxis`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 6 axes.

        Returns:
            Whether the value is 0 to 5. `AXIS_INVALID` is not valid.
        """
        return ordinal_valid(self.value, AXIS_COUNT - 1)


# The number of gamepad axes. SDL: `SDL_GAMEPAD_AXIS_COUNT`.
comptime AXIS_COUNT = 6
# No axis. SDL: `SDL_GAMEPAD_AXIS_INVALID`.
comptime AXIS_INVALID = GamepadAxis(-1)
# The left stick, left to right.
comptime AXIS_LEFTX = GamepadAxis(0)
# The left stick, top to bottom: pushed up is negative.
comptime AXIS_LEFTY = GamepadAxis(1)
comptime AXIS_RIGHTX = GamepadAxis(2)
comptime AXIS_RIGHTY = GamepadAxis(3)
# The left trigger, from 0 at rest to 32767 pulled.
comptime AXIS_LEFT_TRIGGER = GamepadAxis(4)
comptime AXIS_RIGHT_TRIGGER = GamepadAxis(5)


def _axis_names() -> List[String]:
    """Return the mapping names of the axes, in order.

    Returns:
        SDL's `map_StringForGamepadAxis`.
    """
    return [
        "leftx",
        "lefty",
        "rightx",
        "righty",
        "lefttrigger",
        "righttrigger",
    ]


def gamepad_axis_from_string(text: String) -> GamepadAxis:
    """Return the axis a mapping names. SDL: `SDL_GetGamepadAxisFromString`.

    One leading `+` or `-` is skipped. Case is ignored.

    Args:
        text: The name, such as `lefttrigger`.

    Returns:
        The axis, or `AXIS_INVALID` for a name that is not one.
    """
    var index = _find_name(_drop_sign(text), _axis_names())
    if index < 0:
        return AXIS_INVALID
    return GamepadAxis(index)


def gamepad_string_for_axis(axis: GamepadAxis) -> String:
    """Return the mapping name of an axis. SDL:
    `SDL_GetGamepadStringForAxis`.

    Args:
        axis: The axis.

    Returns:
        The name, or an empty string for an axis that is not valid.
    """
    return ordinal_label(axis.is_valid(), axis.value, _axis_names(), "")


def is_trigger(axis: GamepadAxis) -> Bool:
    """Return True if an axis is one of the two triggers.

    Args:
        axis: The axis.

    Returns:
        Whether the axis is `AXIS_LEFT_TRIGGER` or `AXIS_RIGHT_TRIGGER`.
    """
    return axis == AXIS_LEFT_TRIGGER or axis == AXIS_RIGHT_TRIGGER


@fieldwise_init
struct GamepadButtonLabel(Equatable, ImplicitlyCopyable, Writable):
    """The letter or shape printed on a face button. SDL:
    `SDL_GamepadButtonLabel`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 9 labels.

        Returns:
            Whether the value is 0 to 8.
        """
        return ordinal_valid(self.value, 8)


comptime LABEL_UNKNOWN = GamepadButtonLabel(0)
comptime LABEL_A = GamepadButtonLabel(1)
comptime LABEL_B = GamepadButtonLabel(2)
comptime LABEL_X = GamepadButtonLabel(3)
comptime LABEL_Y = GamepadButtonLabel(4)
comptime LABEL_CROSS = GamepadButtonLabel(5)
comptime LABEL_CIRCLE = GamepadButtonLabel(6)
comptime LABEL_SQUARE = GamepadButtonLabel(7)
comptime LABEL_TRIANGLE = GamepadButtonLabel(8)


@fieldwise_init
struct FaceStyle(Equatable, ImplicitlyCopyable, Writable):
    """How the face buttons are labeled. SDL: `SDL_GamepadFaceStyle`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 4 styles.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 3)


comptime FACE_STYLE_UNKNOWN = FaceStyle(0)
# A at the bottom, B at the right: Xbox.
comptime FACE_STYLE_ABXY = FaceStyle(1)
# B at the bottom, A at the right: Nintendo.
comptime FACE_STYLE_BAYX = FaceStyle(2)
# Cross, Circle, Square and Triangle: PlayStation.
comptime FACE_STYLE_SONY = FaceStyle(3)


def face_style_from_string(text: String) -> FaceStyle:
    """Return the face style a mapping's `face:` field names. SDL:
    `SDL_GetGamepadFaceStyleFromString`.

    Case is not ignored, as in SDL.

    Args:
        text: The name: `abxy`, `bayx` or `sony`.

    Returns:
        The style, or `FACE_STYLE_UNKNOWN` for any other name.
    """
    if text == "abxy":
        return FACE_STYLE_ABXY
    if text == "bayx":
        return FACE_STYLE_BAYX
    if text == "sony":
        return FACE_STYLE_SONY
    return FACE_STYLE_UNKNOWN


def face_style_for_type(type: GamepadType) -> FaceStyle:
    """Return the face style of a kind of gamepad. SDL:
    `SDL_GetGamepadFaceStyleForGamepadType`.

    Args:
        type: The gamepad type.

    Returns:
        `FACE_STYLE_SONY` for PlayStation, `FACE_STYLE_BAYX` for Nintendo
        Switch, and `FACE_STYLE_ABXY` for any other type.
    """
    if type.value >= GAMEPAD_TYPE_PS3.value and type.value <= (
        GAMEPAD_TYPE_PS5.value
    ):
        return FACE_STYLE_SONY
    if type.value >= GAMEPAD_TYPE_NINTENDO_SWITCH_PRO.value and type.value <= (
        GAMEPAD_TYPE_NINTENDO_SWITCH_JOYCON_PAIR.value
    ):
        return FACE_STYLE_BAYX
    return FACE_STYLE_ABXY


def button_label_for_face_style(
    style: FaceStyle, button: GamepadButton
) -> GamepadButtonLabel:
    """Return the label on a face button. SDL:
    `SDL_GetGamepadButtonLabelForFaceStyle`.

    Args:
        style: How the face buttons are labeled.
        button: The button.

    Returns:
        The label, or `LABEL_UNKNOWN` for a button that is not a face
        button or a style that is not known.
    """
    if not style.is_valid() or style == FACE_STYLE_UNKNOWN:
        return LABEL_UNKNOWN
    if button.value < BUTTON_SOUTH.value or button.value > BUTTON_NORTH.value:
        return LABEL_UNKNOWN
    var labels: List[GamepadButtonLabel]
    if style == FACE_STYLE_ABXY:
        labels = [LABEL_A, LABEL_B, LABEL_X, LABEL_Y]
    elif style == FACE_STYLE_BAYX:
        labels = [LABEL_B, LABEL_A, LABEL_Y, LABEL_X]
    else:
        labels = [LABEL_CROSS, LABEL_CIRCLE, LABEL_SQUARE, LABEL_TRIANGLE]
    return labels[button.value]


def button_label_for_type(
    type: GamepadType, button: GamepadButton
) -> GamepadButtonLabel:
    """Return the label on a face button of a kind of gamepad. SDL:
    `SDL_GetGamepadButtonLabelForType`.

    Args:
        type: The gamepad type.
        button: The button.

    Returns:
        The label, or `LABEL_UNKNOWN` for a button that is not a face
        button.
    """
    return button_label_for_face_style(face_style_for_type(type), button)
