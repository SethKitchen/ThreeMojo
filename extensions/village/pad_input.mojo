# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A player's `MoveInput` from a gamepad or a keyboard.

The gamepad is read by position, as SDL names its buttons, so an Xbox and
a PlayStation controller play alike:

| Control | Gamepad | Keyboard |
|---|---|---|
| Move | Left stick, or the d-pad | `W`, `A`, `S`, `D` |
| Look | Right stick | The arrows |
| Run | Hold the right trigger, the east button or the left stick | Hold Shift, or `R` |
| Jump | The south button | Space |
| Use | The west button | `E` |

A stick reads nothing within `DEAD_ZONE` of its middle, and the rest of
its throw is stretched to the whole range, so a worn stick does not
creep. The two sources add, so a player can use either, or both.
"""

from controls.held_keys import HeldKeys
from controls.input import (
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    ARROW_UP,
    KEY_A,
    KEY_D,
    KEY_R,
    KEY_S,
    KEY_W,
    Key,
)
from extensions.gamepad.gamepad import Gamepad
from extensions.gamepad.ids import (
    AXIS_LEFTX,
    AXIS_LEFTY,
    AXIS_RIGHTX,
    AXIS_RIGHTY,
    AXIS_RIGHT_TRIGGER,
    BUTTON_DPAD_DOWN,
    BUTTON_DPAD_LEFT,
    BUTTON_DPAD_RIGHT,
    BUTTON_DPAD_UP,
    BUTTON_EAST,
    BUTTON_LEFT_STICK,
    BUTTON_SOUTH,
    BUTTON_WEST,
)
from extensions.village.character import MoveInput
from math.utils import clamp
from std.math import sqrt

comptime DEAD_ZONE = Float32(0.2)
"""The share of a stick's throw round its middle that reads nothing."""
comptime TRIGGER_PRESS = Float32(0.5)
"""The share of a trigger's throw past which it counts as held."""
comptime AXIS_HIGH = Float32(32767)
"""The value of an axis leaned all the way, as SDL reads it."""
comptime KEY_SPACE = Key(32)
"""The space bar."""
comptime KEY_E = Key(101)
"""The `E` key, which uses the thing nearby."""


def stick(
    x: Int, y: Int, dead_zone: Float32 = DEAD_ZONE
) -> Tuple[Float32, Float32]:
    """Return a stick's lean, with its dead zone taken out.

    Args:
        x: The stick's x axis, from -32768 to 32767, as SDL reads it.
        y: The stick's y axis. Down is positive, as SDL reads it.
        dead_zone: The share of the throw round the middle that reads
            nothing, from 0 to less than 1.

    Returns:
        The lean along x and along y, each from -1 to 1, as a pair. The
        lean's length is zero within the dead zone and grows from 0 to 1
        over the rest of the throw.
    """
    var lx = clamp(Float32(x) / AXIS_HIGH, -1, 1)
    var ly = clamp(Float32(y) / AXIS_HIGH, -1, 1)
    var length = sqrt(lx * lx + ly * ly)
    var zone = clamp(dead_zone, 0, 0.95)
    if length <= zone:
        return (Float32(0), Float32(0))
    var stretched = min(Float32(1), (length - zone) / (1 - zone))
    return (lx * stretched / length, ly * stretched / length)


def gamepad_input(pad: Gamepad, dead_zone: Float32 = DEAD_ZONE) -> MoveInput:
    """Return a player's input from a gamepad.

    Args:
        pad: The gamepad, updated for the frame.
        dead_zone: Each stick's dead zone: see `stick`.

    Returns:
        The input. The d-pad adds to the left stick.
    """
    var move = stick(
        pad.get_axis(AXIS_LEFTX), pad.get_axis(AXIS_LEFTY), dead_zone
    )
    var look = stick(
        pad.get_axis(AXIS_RIGHTX), pad.get_axis(AXIS_RIGHTY), dead_zone
    )
    var forward = -move[1]
    var right = move[0]
    if pad.get_button(BUTTON_DPAD_UP):
        forward += 1
    if pad.get_button(BUTTON_DPAD_DOWN):
        forward -= 1
    if pad.get_button(BUTTON_DPAD_RIGHT):
        right += 1
    if pad.get_button(BUTTON_DPAD_LEFT):
        right -= 1
    var trigger = Float32(pad.get_axis(AXIS_RIGHT_TRIGGER)) / AXIS_HIGH
    var run = (
        trigger > TRIGGER_PRESS
        or pad.get_button(BUTTON_EAST)
        or pad.get_button(BUTTON_LEFT_STICK)
    )
    return MoveInput(
        clamp(forward, -1, 1),
        clamp(right, -1, 1),
        look[0],
        -look[1],
        run,
        pad.get_button(BUTTON_SOUTH),
        pad.get_button(BUTTON_WEST),
    )


def keyboard_input(keys: HeldKeys, shift: Bool) -> MoveInput:
    """Return a player's input from the keys held.

    Args:
        keys: The keys held.
        shift: Whether Shift is held. A key event carries it.

    Returns:
        The input. Each stick leans all the way or not at all.
    """
    var forward = Float32(0)
    var right = Float32(0)
    var look_right = Float32(0)
    var look_up = Float32(0)
    if keys.is_held(KEY_W):
        forward += 1
    if keys.is_held(KEY_S):
        forward -= 1
    if keys.is_held(KEY_D):
        right += 1
    if keys.is_held(KEY_A):
        right -= 1
    if keys.is_held(ARROW_RIGHT):
        look_right += 1
    if keys.is_held(ARROW_LEFT):
        look_right -= 1
    if keys.is_held(ARROW_UP):
        look_up += 1
    if keys.is_held(ARROW_DOWN):
        look_up -= 1
    return MoveInput(
        forward,
        right,
        look_right,
        look_up,
        shift or keys.is_held(KEY_R),
        keys.is_held(KEY_SPACE),
        keys.is_held(KEY_E),
    )


def combined(first: MoveInput, second: MoveInput) -> MoveInput:
    """Return two inputs added, as a player who uses both.

    Args:
        first: One input.
        second: The other.

    Returns:
        The sticks added and kept from -1 to 1, and each button held if
        either holds it.
    """
    return MoveInput(
        clamp(first.forward + second.forward, -1, 1),
        clamp(first.right + second.right, -1, 1),
        clamp(first.look_right + second.look_right, -1, 1),
        clamp(first.look_up + second.look_up, -1, 1),
        first.run or second.run,
        first.jump or second.jump,
        first.use or second.use,
    )
