# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of the joystick state functions of
# src/joystick/SDL_joystick.c, from SDL 3.2.24. It is a translation from C to
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

"""A joystick's state: its axes, buttons and hats, and the events that
change them.

A backend reports what the device sends with `send_axis`, `send_button`
and `send_hat`. Each records the new state and queues a `JoystickEvent`
when the state changes. A `Gamepad` reads the queue and turns it into
gamepad events.

An axis value is from -32768 to 32767. SDL holds back an axis's first
motion until it moves by more than 1/80 of the range, so that a device
that reports noise at rest does not send motion. A hat value is a set of
`HAT_UP`, `HAT_RIGHT`, `HAT_DOWN` and `HAT_LEFT` bits.

SDL drops events while the program has no keyboard focus, unless a hint
says not to. This port has no focus, so it keeps every event.
"""
from extensions.gamepad.guid import DRIVER_VIRTUAL, JoystickGuid
from extensions.gamepad.ids import JOYSTICK_AXIS_MAX
from core.ordinal import ordinal_valid


@fieldwise_init
struct JoystickEventKind(Equatable, ImplicitlyCopyable, Writable):
    """What a joystick event is about. SDL: `SDL_EVENT_JOYSTICK_*`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 3 kinds.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 2)


# An axis moved. SDL: `SDL_EVENT_JOYSTICK_AXIS_MOTION`.
comptime JOYSTICK_AXIS_MOTION = JoystickEventKind(0)
# A button went down or up. SDL: `SDL_EVENT_JOYSTICK_BUTTON_DOWN` and `_UP`.
comptime JOYSTICK_BUTTON = JoystickEventKind(1)
# A hat moved. SDL: `SDL_EVENT_JOYSTICK_HAT_MOTION`.
comptime JOYSTICK_HAT_MOTION = JoystickEventKind(2)


@fieldwise_init
struct JoystickEvent(ImplicitlyCopyable):
    """One change of a joystick's state."""

    var kind: JoystickEventKind
    # The axis, the button or the hat.
    var index: Int
    # The axis value, 1 or 0 for a button down or up, or the hat bits.
    var value: Int


struct JoystickAxisInfo(ImplicitlyCopyable):
    """What SDL keeps about one axis. SDL: `SDL_JoystickAxisInfo`."""

    var initial_value: Int
    var value: Int
    # The value at rest. The gamepad layer sets it for triggers.
    var zero: Int
    var has_initial_value: Bool
    var has_second_value: Bool
    var sent_initial_value: Bool
    var sending_initial_value: Bool

    def __init__(out self):
        """Create an axis that has reported nothing."""
        self.initial_value = 0
        self.value = 0
        self.zero = 0
        self.has_initial_value = False
        self.has_second_value = False
        self.sent_initial_value = False
        self.sending_initial_value = False


def _abs(value: Int) -> Int:
    """Return the absolute value of an integer.

    Args:
        value: The integer.

    Returns:
        The integer without its sign.
    """
    return -value if value < 0 else value


struct Joystick(Movable):
    """The state of one joystick. SDL: the state part of `SDL_Joystick`."""

    var name: String
    var guid: JoystickGuid
    var axes: List[JoystickAxisInfo]
    var buttons: List[Bool]
    var hats: List[Int]
    # The changes since the last `take_events`.
    var events: List[JoystickEvent]

    def __init__(
        out self,
        name: String,
        guid: JoystickGuid,
        axes: Int,
        buttons: Int,
        hats: Int,
    ) raises:
        """Create a joystick at rest.

        Args:
            name: The device's name.
            guid: The device's GUID.
            axes: How many axes it has.
            buttons: How many buttons it has.
            hats: How many hats it has.

        Raises:
            Error: If a count is negative.
        """
        if axes < 0 or buttons < 0 or hats < 0:
            raise Error("A joystick cannot have a negative number of inputs")
        self.name = name
        self.guid = guid
        self.axes = List[JoystickAxisInfo](length=axes, fill=JoystickAxisInfo())
        self.buttons = List[Bool](length=buttons, fill=False)
        self.hats = List[Int](length=hats, fill=0)
        self.events = List[JoystickEvent]()

    def axis_count(self) -> Int:
        """Return the number of axes. SDL: `SDL_GetNumJoystickAxes`.

        Returns:
            How many axes there are.
        """
        return len(self.axes)

    def button_count(self) -> Int:
        """Return the number of buttons. SDL: `SDL_GetNumJoystickButtons`.

        Returns:
            How many buttons there are.
        """
        return len(self.buttons)

    def hat_count(self) -> Int:
        """Return the number of hats. SDL: `SDL_GetNumJoystickHats`.

        Returns:
            How many hats there are.
        """
        return len(self.hats)

    def get_axis(self, axis: Int) -> Int:
        """Return an axis's value. SDL: `SDL_GetJoystickAxis`.

        Args:
            axis: The axis.

        Returns:
            The value from -32768 to 32767, or 0 for an axis the
            joystick does not have.
        """
        if axis < 0 or axis >= len(self.axes):
            return 0
        return self.axes[axis].value

    def get_button(self, button: Int) -> Bool:
        """Return whether a button is down. SDL: `SDL_GetJoystickButton`.

        Args:
            button: The button.

        Returns:
            Whether it is down. False for a button the joystick does not
            have.
        """
        if button < 0 or button >= len(self.buttons):
            return False
        return self.buttons[button]

    def get_hat(self, hat: Int) -> Int:
        """Return a hat's direction bits. SDL: `SDL_GetJoystickHat`.

        Args:
            hat: The hat.

        Returns:
            The bits, or 0 for a hat the joystick does not have.
        """
        if hat < 0 or hat >= len(self.hats):
            return 0
        return self.hats[hat]

    def send_axis(mut self, axis: Int, value: Int):
        """Record an axis value the device sent. SDL: `SDL_SendJoystickAxis`.

        Args:
            axis: The axis. An axis the joystick does not have is ignored.
            value: The value from -32768 to 32767.
        """
        if axis < 0 or axis >= len(self.axes):
            return
        ref info = self.axes[axis]
        if not info.has_initial_value or (
            not info.has_second_value
            and (info.initial_value <= -32767 or info.initial_value == 32767)
            and _abs(value) < JOYSTICK_AXIS_MAX // 4
        ):
            info.initial_value = value
            info.value = value
            info.zero = value
            info.has_initial_value = True
        elif value == info.value and not info.sending_initial_value:
            return
        else:
            info.has_second_value = True
        if not info.sent_initial_value:
            # Do not send motion until the axis really moves.
            if (
                _abs(value - info.value) <= JOYSTICK_AXIS_MAX // 80
                and self.guid.driver() != DRIVER_VIRTUAL
            ):
                return
            info.sent_initial_value = True
            info.sending_initial_value = True
            var initial = info.initial_value
            self.send_axis(axis, initial)
            self.axes[axis].sending_initial_value = False
        self.axes[axis].value = value
        self.events.append(JoystickEvent(JOYSTICK_AXIS_MOTION, axis, value))

    def send_button(mut self, button: Int, down: Bool):
        """Record a button the device sent. SDL: `SDL_SendJoystickButton`.

        Args:
            button: The button. A button the joystick does not have is
                ignored.
            down: Whether it is down.
        """
        if button < 0 or button >= len(self.buttons):
            return
        if self.buttons[button] == down:
            return
        self.buttons[button] = down
        self.events.append(
            JoystickEvent(JOYSTICK_BUTTON, button, 1 if down else 0)
        )

    def send_hat(mut self, hat: Int, value: Int):
        """Record a hat the device sent. SDL: `SDL_SendJoystickHat`.

        Args:
            hat: The hat. A hat the joystick does not have is ignored.
            value: The direction bits.
        """
        if hat < 0 or hat >= len(self.hats):
            return
        if self.hats[hat] == value:
            return
        self.hats[hat] = value
        self.events.append(JoystickEvent(JOYSTICK_HAT_MOTION, hat, value))

    def take_events(mut self) -> List[JoystickEvent]:
        """Return the queued events and empty the queue.

        Returns:
            The changes since the last call, in order.
        """
        var taken = self.events^
        self.events = List[JoystickEvent]()
        return taken^
