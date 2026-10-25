# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of the rumble and LED functions of
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

"""When to send rumble and light changes to a gamepad.

A program asks for rumble with two strengths from 0 to 65535 and a
duration. SDL sends a new strength to the driver at once, and the same
strength again only to extend the time. It stops the rumble when the
duration ends, and sends it again every 2 seconds while it runs, since
some pads stop on their own. The duration is at most 65535 milliseconds.

`RumbleState` holds that schedule. A backend asks `needs_send` before it
calls its driver, then reports with `commit`. Each frame it asks
`expired` and `resend_due`. `LedState` keeps a light from being sent
more than once in 5 seconds with the same color.
"""
from units.si import Duration64, SECOND

# The longest rumble. SDL: `SDL_MAX_RUMBLE_DURATION_MS`.
comptime MAX_RUMBLE_DURATION = Duration64(65.535, SECOND)
# How often a running rumble is sent again. SDL: `SDL_RUMBLE_RESEND_MS`.
comptime RUMBLE_RESEND = Duration64(2, SECOND)
# How long a light keeps one color before it is sent again. SDL:
# `SDL_LED_MIN_REPEAT_MS`.
comptime LED_MIN_REPEAT = Duration64(5, SECOND)


def require_strength(value: Int) raises:
    """Refuse a rumble strength that does not fit 16 bits.

    Nothing. The call returns when the strength is 0 to 65535.

    Args:
        value: The strength.

    Raises:
        Error: If it is negative or over 65535.
    """
    if value < 0 or value > 0xFFFF:
        raise Error("A rumble strength must be 0 to 65535")


struct RumbleState(ImplicitlyCopyable):
    """The rumble a pad is running. SDL: the rumble fields of
    `SDL_Joystick` and their handling in `SDL_RumbleJoystick` and
    `SDL_UpdateJoysticks`. The same state serves the trigger rumble."""

    # The strengths: low and high frequency, or left and right trigger.
    var first: Int
    var second: Int
    # When the rumble stops, or None when it runs until changed.
    var expiration: Optional[Duration64]
    # When it is sent again, or None.
    var resend: Optional[Duration64]

    def __init__(out self):
        """Create a pad that is not rumbling."""
        self.first = 0
        self.second = 0
        self.expiration = None
        self.resend = None

    def needs_send(self, first: Int, second: Int) -> Bool:
        """Return True if a request must reach the driver.

        Args:
            first: The first strength.
            second: The second strength.

        Returns:
            Whether either strength differs from the running one. The same
            strengths only extend the time.
        """
        return first != self.first or second != self.second

    def commit(
        mut self,
        sent: Bool,
        succeeded: Bool,
        first: Int,
        second: Int,
        duration: Duration64,
        now: Duration64,
    ) -> Bool:
        """Record a request. SDL: the rest of `SDL_RumbleJoystick`.

        Args:
            sent: Whether the driver was called.
            succeeded: Whether the driver accepted it. Ignored when it was
                not called.
            first: The first strength.
            second: The second strength.
            duration: How long to rumble. Zero rumbles until changed.
            now: The time now.

        Returns:
            Whether the request succeeded.
        """
        if sent:
            if succeeded:
                self.resend = now + RUMBLE_RESEND
            else:
                self.resend = None
                return False
        self.first = first
        self.second = second
        if (first != 0 or second != 0) and duration.value > 0:
            var length = duration
            if MAX_RUMBLE_DURATION < length:
                length = MAX_RUMBLE_DURATION
            self.expiration = now + length
        else:
            self.expiration = None
            self.resend = None
        return True

    def expired(self, now: Duration64) -> Bool:
        """Return True if the rumble's time is up.

        Args:
            now: The time now.

        Returns:
            Whether it has an end and the end has come.
        """
        return self.expiration and not (now < self.expiration.value())

    def resend_due(self, now: Duration64) -> Bool:
        """Return True if the rumble must be sent again.

        Args:
            now: The time now.

        Returns:
            Whether a resend is scheduled and its time has come.
        """
        return self.resend and not (now < self.resend.value())

    def resent(mut self, now: Duration64):
        """Schedule the next resend after one.

        Args:
            now: The time now.
        """
        self.resend = now + RUMBLE_RESEND


struct LedState(ImplicitlyCopyable):
    """The color a pad's light was last given. SDL: the LED fields of
    `SDL_Joystick` and `SDL_SetJoystickLED`."""

    var red: Int
    var green: Int
    var blue: Int
    # When the same color may be sent again.
    var expiration: Duration64

    def __init__(out self):
        """Create a light that was never set."""
        self.red = 0
        self.green = 0
        self.blue = 0
        self.expiration = Duration64(0)

    def needs_send(
        self, red: Int, green: Int, blue: Int, now: Duration64
    ) -> Bool:
        """Return True if a color must reach the driver.

        Args:
            red: The red level, 0 to 255.
            green: The green level.
            blue: The blue level.
            now: The time now.

        Returns:
            Whether the color is new, or the same color is due again.
        """
        var fresh = red != self.red or green != self.green or blue != self.blue
        return fresh or not (now < self.expiration)

    def commit(
        mut self, sent: Bool, red: Int, green: Int, blue: Int, now: Duration64
    ):
        """Record a color, whether or not it was sent.

        Args:
            sent: Whether the driver was called.
            red: The red level.
            green: The green level.
            blue: The blue level.
            now: The time now.
        """
        if sent:
            self.expiration = now + LED_MIN_REPEAT
        self.red = red
        self.green = green
        self.blue = blue


def require_color(red: Int, green: Int, blue: Int) raises:
    """Refuse a light level that does not fit a byte.

    Nothing. The call returns when each level is 0 to 255.

    Args:
        red: The red level.
        green: The green level.
        blue: The blue level.

    Raises:
        Error: If a level is negative or over 255.
    """
    for level in [red, green, blue]:  # pragma: no branch
        if level < 0 or level > 255:
            raise Error("A light level must be 0 to 255")
