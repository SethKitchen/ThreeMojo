# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of the gamepad state and event functions of
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

"""A gamepad: a joystick read through a mapping.

`Gamepad` holds a joystick and the bindings of its mapping. Ask it for a
control by position, `get_button(BUTTON_SOUTH)` or
`get_axis(AXIS_LEFTX)`, whatever joystick input the device uses for it.
`update` turns the joystick's queued events into `GamepadEvent`s, so
that a press shows as one `GAMEPAD_BUTTON_DOWN` event.

A typical frame reads the backend, then the gamepad:

    device.update()
    for event in device.gamepad.update():
        if event.kind == GAMEPAD_BUTTON_DOWN and event.button == BUTTON_WEST:
            attack()
    var walk = device.gamepad.get_axis(AXIS_LEFTY)

SDL holds back a quick release of the guide button, which some Xbox 360
receivers send. This port sends it at once. Touchpads, sensors, rumble
and LEDs are not ported.
"""
from extensions.gamepad.controller_type import gamepad_type_from_guid
from extensions.gamepad.ids import (
    AXIS_COUNT,
    BUTTON_COUNT,
    BUTTON_INVALID,
    FACE_STYLE_BAYX,
    FACE_STYLE_UNKNOWN,
    GAMEPAD_TYPE_UNKNOWN,
    FaceStyle,
    GamepadAxis,
    GamepadButton,
    GamepadButtonLabel,
    GamepadType,
    LABEL_UNKNOWN,
    button_label_for_face_style,
    face_style_for_type,
    face_style_from_string,
    gamepad_type_from_string,
    is_trigger,
)
from extensions.gamepad.joystick import (
    JOYSTICK_AXIS_MOTION,
    JOYSTICK_BUTTON,
    Joystick,
)
from extensions.gamepad.mapping import (
    BIND_AXIS,
    BIND_BUTTON,
    BIND_HAT,
    BUTTON_LABELS_HINT,
    FACE_FIELD,
    TYPE_FIELD,
    GamepadBinding,
    GamepadMapping,
    field_value,
    fixup_hidapi_mapping,
    is_hidapi_guid,
    parse_gamepad_mapping,
    uses_button_labels,
)
from core.ordinal import ordinal_valid


@fieldwise_init
struct GamepadEventKind(Equatable, ImplicitlyCopyable, Writable):
    """What a gamepad event is about. SDL: `SDL_EVENT_GAMEPAD_*`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 3 kinds.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 2)


# An axis moved. SDL: `SDL_EVENT_GAMEPAD_AXIS_MOTION`.
comptime GAMEPAD_AXIS_MOTION = GamepadEventKind(0)
# A button went down. SDL: `SDL_EVENT_GAMEPAD_BUTTON_DOWN`.
comptime GAMEPAD_BUTTON_DOWN = GamepadEventKind(1)
# A button went up. SDL: `SDL_EVENT_GAMEPAD_BUTTON_UP`.
comptime GAMEPAD_BUTTON_UP = GamepadEventKind(2)


struct GamepadEvent(ImplicitlyCopyable):
    """One change of a gamepad control."""

    var kind: GamepadEventKind
    # The button, for a button event, or `BUTTON_INVALID`.
    var button: GamepadButton
    # The axis, for an axis event.
    var axis: GamepadAxis
    # The axis value, from -32768 to 32767.
    var value: Int

    def __init__(
        out self,
        kind: GamepadEventKind,
        button: GamepadButton,
        axis: GamepadAxis,
        value: Int,
    ):
        """Create an event.

        Args:
            kind: What happened.
            button: The button, or `BUTTON_INVALID`.
            axis: The axis, for an axis event.
            value: The axis value, for an axis event.
        """
        self.kind = kind
        self.button = button
        self.axis = axis
        self.value = value


def _in_range(value: Int, a: Int, b: Int) -> Bool:
    """Return True if a value is between two ends, in either order.

    Args:
        value: The value.
        a: One end.
        b: The other end.

    Returns:
        Whether the value is from the lower end to the higher, inclusive.
    """
    if a < b:
        return value >= a and value <= b
    return value >= b and value <= a


def _scaled(binding: GamepadBinding, value: Int) -> Int:
    """Map an input axis value into a binding's output range.

    Args:
        binding: An axis-to-axis binding.
        value: The input value, in the input range.

    Returns:
        The output value. SDL's float arithmetic is kept, so that the
        results are the same.
    """
    if (
        binding.input_axis_min == binding.output_axis_min
        and binding.input_axis_max == binding.output_axis_max
    ):
        return value
    var normalized = Float32(value - binding.input_axis_min) / Float32(
        binding.input_axis_max - binding.input_axis_min
    )
    return binding.output_axis_min + Int(
        normalized * Float32(binding.output_axis_max - binding.output_axis_min)
    )


def _to_sint16(value: Int) -> Int:
    """Return an integer as C's cast to `Sint16` keeps it.

    Args:
        value: The integer.

    Returns:
        Its low 16 bits as a signed value.
    """
    var low = value & 0xFFFF
    return low - 0x10000 if low >= 0x8000 else low


struct Gamepad(Movable):
    """A joystick with a gamepad mapping. SDL: `SDL_Gamepad`."""

    var joystick: Joystick
    var name: String
    var type: GamepadType
    var face_style: FaceStyle
    var bindings: List[GamepadBinding]
    # The binding each joystick axis last drove, or -1.
    var last_match_axis: List[Int]
    # The bits each hat last had.
    var last_hat_mask: List[Int]

    def __init__(out self, var joystick: Joystick, mapping: GamepadMapping):
        """Open a joystick as a gamepad. SDL: `SDL_OpenGamepad` with
        `SDL_PrivateLoadButtonMapping`.

        Args:
            joystick: The joystick.
            mapping: Its mapping, from a `MappingDatabase`.
        """
        self.joystick = joystick^
        self.name = ""
        self.type = GAMEPAD_TYPE_UNKNOWN
        self.face_style = FACE_STYLE_UNKNOWN
        self.bindings = List[GamepadBinding]()
        self.last_match_axis = List[Int](
            length=self.joystick.axis_count(), fill=-1
        )
        self.last_hat_mask = List[Int](length=self.joystick.hat_count(), fill=0)
        self.load_mapping(mapping)

    def load_mapping(mut self, mapping: GamepadMapping):
        """Use a mapping. SDL: `SDL_PrivateLoadButtonMapping`.

        It sets the name, the type, the face style and the bindings. A
        trigger's joystick axis is set to rest at the low end of its
        range, so that an untouched trigger reads 0.

        Args:
            mapping: The mapping.
        """
        self.name = mapping.name
        for index in range(len(self.last_match_axis)):
            self.last_match_axis[index] = -1
        self.type = gamepad_type_from_string(
            field_value(mapping.mapping, TYPE_FIELD)
        )
        if self.type == GAMEPAD_TYPE_UNKNOWN:
            self.type = gamepad_type_from_guid(
                self.joystick.guid, self.joystick.name
            )
        self.face_style = face_style_from_string(
            field_value(mapping.mapping, FACE_FIELD)
        )
        if (
            self.face_style == FACE_STYLE_UNKNOWN
            and mapping.mapping.find(BUTTON_LABELS_HINT) >= 0
        ):
            self.face_style = FACE_STYLE_BAYX
        if self.face_style == FACE_STYLE_UNKNOWN:
            self.face_style = face_style_for_type(self.type)
        self.bindings = parse_gamepad_mapping(
            mapping.mapping, uses_button_labels(mapping.mapping)
        )
        if is_hidapi_guid(mapping.guid):
            fixup_hidapi_mapping(self.bindings)
        for binding in self.bindings:
            if (
                binding.input_type == BIND_AXIS
                and binding.output_type == BIND_AXIS
                and is_trigger(binding.output_axis)
                and binding.input_axis < self.joystick.axis_count()
            ):
                ref axis = self.joystick.axes[binding.input_axis]
                axis.value = _to_sint16(binding.input_axis_min)
                axis.zero = axis.value

    def has_axis(self, axis: GamepadAxis) -> Bool:
        """Return True if the mapping binds an axis. SDL:
        `SDL_GamepadHasAxis`.

        Args:
            axis: The axis.

        Returns:
            Whether some binding drives it.
        """
        for binding in self.bindings:
            if binding.output_type == BIND_AXIS and binding.output_axis == axis:
                return True
        return False

    def has_button(self, button: GamepadButton) -> Bool:
        """Return True if the mapping binds a button. SDL:
        `SDL_GamepadHasButton`.

        Args:
            button: The button.

        Returns:
            Whether some binding drives it.
        """
        for binding in self.bindings:
            if (
                binding.output_type == BIND_BUTTON
                and binding.output_button == button
            ):
                return True
        return False

    def get_axis(self, axis: GamepadAxis) -> Int:
        """Return an axis's value. SDL: `SDL_GetGamepadAxis`.

        The first binding that gives a value other than zero wins.

        Args:
            axis: The axis.

        Returns:
            The value from -32768 to 32767. A trigger is from 0 to 32767.
            An axis the mapping does not bind is 0.
        """
        for binding in self.bindings:
            if binding.output_type != BIND_AXIS or binding.output_axis != axis:
                continue
            var value = 0
            if binding.input_type == BIND_AXIS:
                value = self.joystick.get_axis(binding.input_axis)
                if _in_range(
                    value, binding.input_axis_min, binding.input_axis_max
                ):
                    value = _scaled(binding, value)
                else:
                    value = 0
            elif binding.input_type == BIND_BUTTON:
                if self.joystick.get_button(binding.input_button):
                    value = binding.output_axis_max
            else:
                var mask = self.joystick.get_hat(binding.input_hat)
                if (mask & binding.input_hat_mask) != 0:
                    value = binding.output_axis_max
            # SDL also checks that the value is in the output range. Every
            # value above is, so the check is left out.
            if value != 0:
                return _to_sint16(value)
        return 0

    def get_button(self, button: GamepadButton) -> Bool:
        """Return whether a button is down. SDL: `SDL_GetGamepadButton`.

        An axis bound to a button presses it past the middle of its
        range.

        Args:
            button: The button.

        Returns:
            Whether any binding holds it down.
        """
        var result = False
        for binding in self.bindings:
            if (
                binding.output_type != BIND_BUTTON
                or binding.output_button != button
            ):
                continue
            if binding.input_type == BIND_AXIS:
                var value = self.joystick.get_axis(binding.input_axis)
                var low = binding.input_axis_min
                var high = binding.input_axis_max
                var threshold = low + (high - low) // 2
                if _in_range(value, low, high):
                    if low < high:
                        result = result or value >= threshold
                    else:
                        result = result or value <= threshold
            elif binding.input_type == BIND_BUTTON:
                result = result or self.joystick.get_button(
                    binding.input_button
                )
            else:
                var mask = self.joystick.get_hat(binding.input_hat)
                result = result or (mask & binding.input_hat_mask) != 0
        return result

    def button_label(self, button: GamepadButton) -> GamepadButtonLabel:
        """Return the label on a face button. SDL:
        `SDL_GetGamepadButtonLabel`.

        Args:
            button: The button.

        Returns:
            The label for this gamepad's face style, or `LABEL_UNKNOWN`.
        """
        return button_label_for_face_style(self.face_style, button)

    def _send_axis(
        self, mut events: List[GamepadEvent], axis: GamepadAxis, value: Int
    ):
        """Queue an axis event. SDL: `SDL_SendGamepadAxis`.

        Args:
            events: The queue.
            axis: The axis.
            value: The value.
        """
        events.append(
            GamepadEvent(
                GAMEPAD_AXIS_MOTION, BUTTON_INVALID, axis, _to_sint16(value)
            )
        )

    def _send_button(
        self, mut events: List[GamepadEvent], button: GamepadButton, down: Bool
    ):
        """Queue a button event. SDL: `SDL_SendGamepadButton`, without the
        guide button delay.

        Args:
            events: The queue.
            button: The button. `BUTTON_INVALID` is dropped.
            down: Whether it went down.
        """
        if button == BUTTON_INVALID:
            return
        var kind = GAMEPAD_BUTTON_DOWN if down else GAMEPAD_BUTTON_UP
        events.append(GamepadEvent(kind, button, GamepadAxis(0), 0))

    def _reset_output(self, mut events: List[GamepadEvent], index: Int):
        """Queue the event that returns a binding's control to rest. SDL:
        `ResetOutput`.

        Args:
            events: The queue.
            index: The binding.
        """
        ref binding = self.bindings[index]
        if binding.output_type == BIND_AXIS:
            self._send_axis(events, binding.output_axis, 0)
        else:
            self._send_button(events, binding.output_button, False)

    def _handle_axis(
        mut self, mut events: List[GamepadEvent], axis: Int, value: Int
    ):
        """Turn a joystick axis motion into gamepad events. SDL:
        `HandleJoystickAxis`.

        Args:
            events: The queue.
            axis: The joystick axis.
            value: Its new value.
        """
        var last = self.last_match_axis[axis]
        var found = -1
        for index in range(len(self.bindings)):
            ref binding = self.bindings[index]
            if binding.input_type == BIND_AXIS and binding.input_axis == axis:
                if _in_range(
                    value, binding.input_axis_min, binding.input_axis_max
                ):
                    found = index
                    break
        if last >= 0 and (
            found < 0
            or not self.bindings[last].has_same_output(self.bindings[found])
        ):
            self._reset_output(events, last)
        if found >= 0:
            ref binding = self.bindings[found]
            if binding.output_type == BIND_AXIS:
                self._send_axis(
                    events, binding.output_axis, _scaled(binding, value)
                )
            else:
                var low = binding.input_axis_min
                var high = binding.input_axis_max
                var threshold = low + (high - low) // 2
                var down = (
                    value <= threshold if high < low else (value >= threshold)
                )
                self._send_button(events, binding.output_button, down)
        self.last_match_axis[axis] = found

    def _handle_button(
        self, mut events: List[GamepadEvent], button: Int, down: Bool
    ):
        """Turn a joystick button into gamepad events. SDL:
        `HandleJoystickButton`.

        Args:
            events: The queue.
            button: The joystick button.
            down: Whether it went down.
        """
        for binding in self.bindings:
            if (
                binding.input_type == BIND_BUTTON
                and binding.input_button == button
            ):
                if binding.output_type == BIND_AXIS:
                    var value = binding.output_axis_max if down else (
                        binding.output_axis_min
                    )
                    self._send_axis(events, binding.output_axis, value)
                else:
                    self._send_button(events, binding.output_button, down)
                return

    def _handle_hat(
        mut self, mut events: List[GamepadEvent], hat: Int, value: Int
    ):
        """Turn a joystick hat motion into gamepad events. SDL:
        `HandleJoystickHat`.

        Args:
            events: The queue.
            hat: The joystick hat.
            value: Its new direction bits.
        """
        var changed = self.last_hat_mask[hat] ^ value
        for index in range(len(self.bindings)):
            ref binding = self.bindings[index]
            if binding.input_type != BIND_HAT or binding.input_hat != hat:
                continue
            if (changed & binding.input_hat_mask) == 0:
                continue
            if (value & binding.input_hat_mask) != 0:
                if binding.output_type == BIND_AXIS:
                    self._send_axis(
                        events, binding.output_axis, binding.output_axis_max
                    )
                else:
                    self._send_button(events, binding.output_button, True)
            else:
                self._reset_output(events, index)
        self.last_hat_mask[hat] = value

    def update(mut self) -> List[GamepadEvent]:
        """Turn the joystick's queued events into gamepad events. SDL:
        `SDL_GamepadEventWatcher`.

        Returns:
            The gamepad events, in order. A joystick event that changes no
            control gives none.
        """
        var events = List[GamepadEvent]()
        for event in self.joystick.take_events():
            if event.kind == JOYSTICK_AXIS_MOTION:
                self._handle_axis(events, event.index, event.value)
            elif event.kind == JOYSTICK_BUTTON:
                self._handle_button(events, event.index, event.value != 0)
            else:
                self._handle_hat(events, event.index, event.value)
        return events^

    def recenter(self) -> List[GamepadEvent]:
        """Return the events that put every control at rest. SDL:
        `RecenterGamepad`, which runs when a gamepad goes away.

        Returns:
            An up event for each button that is down and a zero motion for
            each axis that is not at zero.
        """
        var events = List[GamepadEvent]()
        for index in range(BUTTON_COUNT):  # pragma: no branch
            if self.get_button(GamepadButton(index)):
                self._send_button(events, GamepadButton(index), False)
        for index in range(AXIS_COUNT):  # pragma: no branch
            if self.get_axis(GamepadAxis(index)) != 0:
                self._send_axis(events, GamepadAxis(index), 0)
        return events^
