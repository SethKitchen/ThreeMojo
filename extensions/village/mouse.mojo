# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The mouse in the village: drag to look, click to strike.

`MouseLook` reads a window's pointer events. While a button is held, the
pointer's travel turns the camera: `MOUSE_TURN` of a full turn of the
look stick for each pixel it moves in a frame. A click of the primary
button that does not drag is a light attack, and of the secondary a heavy
one. `apply` adds a frame's look and strikes to the input of the gamepad
and the keyboard.
"""

from controls.input import (
    InputEvent,
    POINTER_DOWN,
    POINTER_MOVE,
    POINTER_UP,
    PRIMARY,
    SECONDARY,
)
from extensions.village.character import MoveInput

comptime MOUSE_TURN = Float32(0.04)
"""How far one pixel of the pointer's travel leans the look, as a share of
the look stick's full lean."""
comptime DRAG = 4
"""How many pixels a held button must travel before its press is a drag
and not a click."""


struct MouseLook(Copyable, Movable):
    """What the mouse did since the last frame."""

    var held: Bool
    """Whether a button is held."""
    var x: Int
    """Where the pointer was last, in pixels."""
    var y: Int
    var travel_x: Int
    """How far the pointer has moved across while held, this frame, in
    pixels."""
    var travel_y: Int
    var dragged: Bool
    """Whether the held button has dragged past `DRAG` pixels."""
    var light: Bool
    """Whether a primary click ended this frame."""
    var heavy: Bool
    """Whether a secondary click ended this frame."""

    def __init__(out self):
        """Make a mouse that did nothing."""
        self.held = False
        self.x = 0
        self.y = 0
        self.travel_x = 0
        self.travel_y = 0
        self.dragged = False
        self.light = False
        self.heavy = False

    def event(mut self, event: InputEvent):
        """Take one of a window's events. Events of keys and the wheel are
        let go.

        Args:
            event: The event.
        """
        if event.kind == POINTER_DOWN:
            self.held = True
            self.dragged = False
            self.x = event.x
            self.y = event.y
        elif event.kind == POINTER_MOVE and self.held:
            var dx = event.x - self.x
            var dy = event.y - self.y
            self.travel_x += dx
            self.travel_y += dy
            if abs(dx) + abs(dy) > DRAG:
                self.dragged = True
            self.x = event.x
            self.y = event.y
        elif event.kind == POINTER_UP and self.held:
            self.held = False
            if not self.dragged:
                if event.button == PRIMARY:
                    self.light = True
                elif event.button == SECONDARY:
                    self.heavy = True

    def apply(mut self, mut input: MoveInput):
        """Add this frame's look and strikes to an input, and begin the
        next frame.

        Args:
            input: The input of the gamepad and the keyboard. Its look
                leans further, up to the stick's full lean, and its light
                and heavy attacks are pressed with a click.
        """
        var right = input.look_right + Float32(self.travel_x) * MOUSE_TURN
        var up = input.look_up - Float32(self.travel_y) * MOUSE_TURN
        input.look_right = max(Float32(-1), min(Float32(1), right))
        input.look_up = max(Float32(-1), min(Float32(1), up))
        input.light = input.light or self.light
        input.heavy = input.heavy or self.heavy
        self.travel_x = 0
        self.travel_y = 0
        self.light = False
        self.heavy = False
