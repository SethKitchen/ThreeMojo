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
| Light attack | The right shoulder | `F` |
| Heavy attack | The north button | `G` |
| Rising edge | Hold the left trigger, and the right shoulder | `Z` |
| Tempest | Hold the left trigger, and the north button | `X` |
| Dodge | The east button | `C` |
| Guard, and a ki pulse | The left shoulder | `V` |
| Lock on | The right stick | `T` |
| High, middle and low stance | Hold the left shoulder, and the north, the west or the south button | `6`, `7` and `8` |

While the left shoulder guards, the north, the west and the south buttons
choose a stance, and do not attack, use or jump: see `fight_input`.

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
    KEY_F,
    KEY_R,
    KEY_S,
    KEY_W,
    Key,
)
from extensions.gamepad.gamepad import Gamepad
from extensions.gamepad.ids import (
    AXIS_LEFTX,
    AXIS_LEFTY,
    AXIS_LEFT_TRIGGER,
    AXIS_RIGHTX,
    AXIS_RIGHTY,
    AXIS_RIGHT_TRIGGER,
    BUTTON_DPAD_DOWN,
    BUTTON_DPAD_LEFT,
    BUTTON_DPAD_RIGHT,
    BUTTON_DPAD_UP,
    BUTTON_EAST,
    BUTTON_LEFT_SHOULDER,
    BUTTON_LEFT_STICK,
    BUTTON_NORTH,
    BUTTON_RIGHT_SHOULDER,
    BUTTON_RIGHT_STICK,
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
comptime KEY_G = Key(103)
"""The `G` key: the heavy attack."""
comptime KEY_Z = Key(122)
"""The `Z` key: the rising edge."""
comptime KEY_X = Key(120)
"""The `X` key: the tempest."""
comptime KEY_C = Key(99)
"""The `C` key: the dodge."""
comptime KEY_V = Key(118)
"""The `V` key: the guard, and a ki pulse."""
comptime KEY_T = Key(116)
"""The `T` key: the lock on a foe."""
comptime KEY_SIX = Key(54)
"""The `6` key: the high stance. `7` and `8` follow it."""


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


def fight_input(
    var input: MoveInput,
    south: Bool,
    west: Bool,
    north: Bool,
    east: Bool,
    right_shoulder: Bool,
    left_shoulder: Bool,
    left_trigger: Bool,
    right_stick: Bool,
) -> MoveInput:
    """Return an input with a gamepad's buttons for the jump, the use and
    the fight.

    Args:
        input: The input with its sticks and its run set.
        south: Whether the south button is held.
        west: Whether the west button is held.
        north: Whether the north button is held.
        east: Whether the east button is held.
        right_shoulder: Whether the right shoulder is held.
        left_shoulder: Whether the left shoulder is held.
        left_trigger: Whether the left trigger is held past
            `TRIGGER_PRESS`.
        right_stick: Whether the right stick is pressed in.

    Returns:
        The input, with the buttons of the module's table. The left
        shoulder guards, and the north, the west and the south buttons
        then choose a stance. The left trigger turns the right shoulder
        and the north button into the artes.
    """
    var stance = left_shoulder and not left_trigger
    input.jump = south and not left_shoulder
    input.use = west and not left_shoulder
    input.light = right_shoulder and not left_trigger
    input.rising = right_shoulder and left_trigger
    input.heavy = north and not (left_trigger or left_shoulder)
    input.tempest = north and left_trigger
    input.dodge = east
    input.guard = left_shoulder
    input.lock = right_stick
    input.high = north and stance
    input.middle = west and stance
    input.low = south and stance
    return input


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
    var arte = Float32(pad.get_axis(AXIS_LEFT_TRIGGER)) / AXIS_HIGH
    return fight_input(
        MoveInput(
            clamp(forward, -1, 1),
            clamp(right, -1, 1),
            look[0],
            -look[1],
            run,
            False,
        ),
        pad.get_button(BUTTON_SOUTH),
        pad.get_button(BUTTON_WEST),
        pad.get_button(BUTTON_NORTH),
        pad.get_button(BUTTON_EAST),
        pad.get_button(BUTTON_RIGHT_SHOULDER),
        pad.get_button(BUTTON_LEFT_SHOULDER),
        arte > TRIGGER_PRESS,
        pad.get_button(BUTTON_RIGHT_STICK),
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
        light=keys.is_held(KEY_F),
        heavy=keys.is_held(KEY_G),
        rising=keys.is_held(KEY_Z),
        tempest=keys.is_held(KEY_X),
        dodge=keys.is_held(KEY_C),
        guard=keys.is_held(KEY_V),
        lock=keys.is_held(KEY_T),
        high=keys.is_held(KEY_SIX),
        middle=keys.is_held(Key(KEY_SIX.value + 1)),
        low=keys.is_held(Key(KEY_SIX.value + 2)),
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
        light=first.light or second.light,
        heavy=first.heavy or second.heavy,
        rising=first.rising or second.rising,
        tempest=first.tempest or second.tempest,
        dodge=first.dodge or second.dodge,
        guard=first.guard or second.guard,
        lock=first.lock or second.lock,
        high=first.high or second.high,
        middle=first.middle or second.middle,
        low=first.low or second.low,
    )
