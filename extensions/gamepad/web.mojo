# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of src/joystick/emscripten/SDL_sysjoystick.c,
# from SDL 3.2.24. It is a translation from C to Mojo. It is not the original
# software. The original notice follows.
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

"""Gamepads in a browser, through the Gamepad API.

A web page reads `navigator.getGamepads()` and gives each pad's state to
this module, which is SDL's Emscripten joystick driver without the
Emscripten calls:

    var hub = WebHub()
    hub.connect(state, rumble_available)    # gamepadconnected
    var events = hub.update(state)          # each frame
    hub.disconnect(index)                   # gamepaddisconnected

A browser already maps a known pad to its "standard" layout: 17 buttons
and 4 axes. SDL's `Standard Gamepad` mapping names them. A rumble asks the
page to call `vibrationActuator.playEffect("dual-rumble")`: the page takes
the request with `take_rumble`. A browser has no light, trigger rumble or
motion sensors for a page.

`window/capi_gamepad.mojo` puts this module behind the C ABI, for a page
or another host to feed.
"""
from extensions.gamepad.effects import RumbleState, require_strength
from extensions.gamepad.gamepad import Gamepad, GamepadEvent
from extensions.gamepad.guid import (
    JoystickGuid,
    ProductId,
    VendorId,
    create_joystick_guid_for_name,
)
from extensions.gamepad.joystick import Joystick
from extensions.gamepad.mapping import MappingDatabase, PRIORITY_DEFAULT
from extensions.gamepad.names import create_joystick_name
from units.si import Duration64

# The most axes and buttons SDL keeps for a browser pad.
comptime WEB_MAX_INPUTS = 64

# SDL's mapping for a pad in the browser's standard layout. SDL:
# `SDL_gamepad_db.h`, under `SDL_JOYSTICK_EMSCRIPTEN`.
comptime WEB_DEFAULT_MAPPING = (
    "default,Standard Gamepad,a:b0,b:b1,back:b8,dpdown:b13,dpleft:b14,"
    "dpright:b15,dpup:b12,guide:b16,leftshoulder:b4,leftstick:b10,"
    "lefttrigger:b6,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b11,"
    "righttrigger:b7,rightx:a2,righty:a3,start:b9,x:b2,y:b3,"
)


def web_mapping_database(
    mapping: String = WEB_DEFAULT_MAPPING,
) raises -> MappingDatabase:
    """Return a database with SDL's browser mapping as its default. SDL:
    `SDL_InitGamepadMappings` on Emscripten.

    Args:
        mapping: The default mapping.

    Returns:
        The database.

    Raises:
        Error: If the mapping is not well formed.
    """
    var database = MappingDatabase()
    _ = database.add_mapping(mapping, PRIORITY_DEFAULT)
    return database^


struct WebGamepadState(Copyable, Movable):
    """One pad as the browser shows it. SDL: `EmscriptenGamepadEvent`."""

    # The pad's place in `navigator.getGamepads()`.
    var index: Int
    # The browser's `Gamepad.id`.
    var id: String
    # The browser's `Gamepad.timestamp`, in milliseconds.
    var timestamp: Float64
    # Each axis, from -1 to 1.
    var axes: List[Float64]
    # Each button's value, from 0 to 1, and whether it is pressed.
    var analog_buttons: List[Float64]
    var digital_buttons: List[Bool]

    def __init__(
        out self,
        index: Int,
        id: String,
        axes: Int,
        buttons: Int,
        timestamp: Float64 = 0,
    ):
        """Create the state of a pad at rest.

        Args:
            index: The pad's place in `navigator.getGamepads()`.
            id: The browser's `Gamepad.id`.
            axes: How many axes it has. More than 64 are not kept.
            buttons: How many buttons it has. More than 64 are not kept.
            timestamp: The browser's `Gamepad.timestamp`.
        """
        self.index = index
        self.id = id
        self.timestamp = timestamp
        var axis_count = min(max(axes, 0), WEB_MAX_INPUTS)
        var button_count = min(max(buttons, 0), WEB_MAX_INPUTS)
        self.axes = List[Float64](length=axis_count, fill=0)
        self.analog_buttons = List[Float64](length=button_count, fill=0)
        self.digital_buttons = List[Bool](length=button_count, fill=False)


def axis_value(axis: Float64) -> Int:
    """Convert a browser axis to a joystick axis. SDL:
    `(Sint16)(32767. * axis)`.

    Args:
        axis: The browser's value, from -1 to 1. A value outside is
            clamped, where SDL's cast would be undefined.

    Returns:
        The value, from -32767 to 32767, truncated toward zero.
    """
    return Int(32767.0 * min(max(axis, -1.0), 1.0))


struct WebGamepad(Movable):
    """One pad of the browser, opened as a gamepad. SDL: an
    `SDL_joylist_item` and the `SDL_Gamepad` opened on it."""

    var index: Int
    var name: String
    var guid: JoystickGuid
    # The state the pad had at the last update.
    var timestamp: Float64
    var axes: List[Float64]
    var analog_buttons: List[Float64]
    var digital_buttons: List[Bool]
    var gamepad: Gamepad
    # Whether the pad has a `vibrationActuator`.
    var rumble_available: Bool
    var rumble_state: RumbleState
    # The rumble the page must play: the low and high strengths.
    var pending_rumble: Optional[Tuple[Int, Int]]

    def __init__(
        out self,
        state: WebGamepadState,
        mut database: MappingDatabase,
        rumble_available: Bool = False,
    ) raises:
        """Open a pad that connected. SDL: `Emscripten_JoyStickConnected`,
        `EMSCRIPTEN_JoystickOpen` and `SDL_OpenGamepad`.

        Args:
            state: The pad's state when it connected.
            database: The mappings. Use `web_mapping_database`.
            rumble_available: Whether the pad has a `vibrationActuator`.

        Raises:
            Error: If no mapping fits the pad.
        """
        self.index = state.index
        self.name = create_joystick_name(
            VendorId(0), ProductId(0), "", state.id
        )
        self.guid = create_joystick_guid_for_name(self.name)
        self.timestamp = state.timestamp
        self.axes = state.axes.copy()
        self.analog_buttons = state.analog_buttons.copy()
        self.digital_buttons = state.digital_buttons.copy()
        self.rumble_available = rumble_available
        self.rumble_state = RumbleState()
        self.pending_rumble = None
        var mapping = database.mapping_for_device(self.name, self.guid, None)
        if mapping < 0:
            raise Error("No gamepad mapping fits " + self.name)
        var joystick = Joystick(
            self.name, self.guid, len(state.axes), len(state.digital_buttons), 0
        )
        self.gamepad = Gamepad(joystick^, database.mappings[mapping])

    def update(mut self, state: WebGamepadState) -> List[GamepadEvent]:
        """Take the pad's new state. SDL: `EMSCRIPTEN_JoystickUpdate`.

        Only what changed since the last state is sent. A state with the
        same nonzero timestamp as the last is old, and changes nothing.

        Args:
            state: The pad's state now.

        Returns:
            The gamepad events.
        """
        if state.timestamp == 0 or state.timestamp != self.timestamp:
            ref joystick = self.gamepad.joystick
            for index in range(len(self.digital_buttons)):
                var down = index < len(state.digital_buttons) and (
                    state.digital_buttons[index]
                )
                var value = (
                    state.analog_buttons[index] if index
                    < len(state.analog_buttons) else 0
                )
                if self.digital_buttons[index] != down:
                    joystick.send_button(index, down)
                self.analog_buttons[index] = value
                self.digital_buttons[index] = down
            for index in range(len(self.axes)):
                var value = state.axes[index] if index < len(state.axes) else 0
                if self.axes[index] != value:
                    joystick.send_axis(index, axis_value(value))
                self.axes[index] = value
            self.timestamp = state.timestamp
        return self.gamepad.update()

    def rumble_at(
        mut self, low: Int, high: Int, duration: Duration64, now: Duration64
    ) raises -> Bool:
        """Rumble the pad. SDL: `SDL_RumbleGamepad` and
        `EMSCRIPTEN_JoystickRumble`.

        The page plays the rumble: it takes it with `take_rumble` and
        plays SDL's effect for 3 seconds. SDL sends it again every 2
        seconds while it runs, through `tick`.

        Args:
            low: The low frequency strength, 0 to 65535.
            high: The high frequency strength, 0 to 65535.
            duration: How long. Zero rumbles until changed.
            now: The time now.

        Returns:
            Whether the pad rumbles. One without a `vibrationActuator`
            does not.

        Raises:
            Error: If a strength does not fit 16 bits.
        """
        require_strength(low)
        require_strength(high)
        return self._rumble(low, high, duration, now)

    def _rumble(
        mut self, low: Int, high: Int, duration: Duration64, now: Duration64
    ) -> Bool:
        """Rumble with strengths that fit 16 bits.

        Args:
            low: The low frequency strength.
            high: The high frequency strength.
            duration: How long.
            now: The time now.

        Returns:
            Whether the pad rumbles.
        """
        var sent = self.rumble_state.needs_send(low, high)
        var succeeded = sent and self._driver_rumble(low, high)
        return self.rumble_state.commit(
            sent, succeeded, low, high, duration, now
        )

    def _driver_rumble(mut self, low: Int, high: Int) -> Bool:
        """Ask the page to rumble. SDL: `EMSCRIPTEN_JoystickRumble`.

        Args:
            low: The low frequency strength.
            high: The high frequency strength.

        Returns:
            Whether the pad has a `vibrationActuator`.
        """
        if not self.rumble_available:
            return False
        self.pending_rumble = (low, high)
        return True

    def tick(mut self, now: Duration64):
        """Run the rumble timers. SDL: the rumble part of
        `SDL_UpdateJoysticks`.

        Args:
            now: The time now.
        """
        if self.rumble_state.expired(now):
            _ = self._rumble(0, 0, Duration64(0), now)
            self.rumble_state.resend = None
        if self.rumble_state.resend_due(now):
            _ = self._driver_rumble(
                self.rumble_state.first, self.rumble_state.second
            )
            self.rumble_state.resent(now)

    def take_rumble(mut self) -> Optional[Tuple[Int, Int]]:
        """Return the rumble the page must play, and forget it.

        Returns:
            The low and high strengths, or None when there is nothing to
            play. The page plays `dual-rumble` for 3 seconds with
            `weakMagnitude = low / 65535` and `strongMagnitude =
            high / 65535`, as SDL does.
        """
        var request = self.pending_rumble
        self.pending_rumble = None
        return request


struct WebHub(Movable):
    """The browser's pads. SDL: the Emscripten driver's joystick list."""

    var pads: List[WebGamepad]
    var database: MappingDatabase

    def __init__(out self, mapping: String = WEB_DEFAULT_MAPPING) raises:
        """Create a hub with no pads and a default mapping.

        Args:
            mapping: The default mapping, SDL's browser mapping unless a
                program gives another.

        Raises:
            Error: If the mapping is not well formed.
        """
        self.pads = List[WebGamepad]()
        self.database = web_mapping_database(mapping)

    def find(self, index: Int) -> Int:
        """Return where a browser pad is in `pads`. SDL: `JoystickByIndex`.

        Args:
            index: The pad's place in `navigator.getGamepads()`.

        Returns:
            Its place in `pads`, or -1.
        """
        if index < 0:
            return -1
        for at in range(len(self.pads)):
            if self.pads[at].index == index:
                return at
        return -1

    def connect(
        mut self, state: WebGamepadState, rumble_available: Bool = False
    ) -> Bool:
        """Add a pad that connected. SDL: `Emscripten_JoyStickConnected`.

        Args:
            state: Its state.
            rumble_available: Whether it has a `vibrationActuator`.

        Returns:
            True if it was added; False if it is known already or no
            mapping fits it.
        """
        if self.find(state.index) >= 0:
            return False
        try:
            self.pads.append(WebGamepad(state, self.database, rumble_available))
            return True
        except:
            return False

    def disconnect(mut self, index: Int) -> Bool:
        """Drop a pad that went away. SDL:
        `Emscripten_JoyStickDisconnected`.

        Args:
            index: The pad's place in `navigator.getGamepads()`.

        Returns:
            True if the pad was known.
        """
        var at = self.find(index)
        if at < 0:
            return False
        _ = self.pads.pop(at)
        return True

    def update(mut self, state: WebGamepadState) -> List[GamepadEvent]:
        """Give a pad its new state.

        Args:
            state: The state. A pad the hub does not know is ignored.

        Returns:
            The pad's gamepad events.
        """
        var at = self.find(state.index)
        if at < 0:
            return List[GamepadEvent]()
        return self.pads[at].update(state)
