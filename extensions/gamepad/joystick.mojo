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

A joystick can also have touchpads and motion sensors. `send_touchpad`
records a finger, as a position from 0 to 1 on each side and a pressure
from 0 to 1. `send_sensor` records a reading: an accelerometer in meters
per second squared, a gyroscope in radians per second. A sensor reports
only while it is enabled.

SDL drops events while the program has no keyboard focus, unless a hint
says not to. This port has no focus, so it keeps every event.
"""
from extensions.gamepad.guid import (
    DRIVER_HIDAPI,
    DRIVER_RAWINPUT,
    DRIVER_VIRTUAL,
    DRIVER_WGI,
    DRIVER_XINPUT,
    JoystickGuid,
    joystick_guid_info,
)
from extensions.gamepad.ids import (
    AXIS_COUNT,
    JOYSTICK_AXIS_MAX,
    JOYSTICK_AXIS_MIN,
)
from core.ordinal import ordinal_valid
from units.si import Duration64, Frequency

# The number of values a sensor keeps. SDL keeps 6; a SIMD vector needs a
# power of two, so the last two stay 0. The drivers send 3.
comptime SENSOR_VALUES = 8


@fieldwise_init
struct SensorType(Equatable, ImplicitlyCopyable, Writable):
    """What a motion sensor measures. SDL: `SDL_SensorType`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 7 types.

        Returns:
            Whether the value is 0 to 6. `SENSOR_INVALID` is not valid.
        """
        return ordinal_valid(self.value, 6)


comptime SENSOR_INVALID = SensorType(-1)
comptime SENSOR_UNKNOWN = SensorType(0)
# An accelerometer, in meters per second squared.
comptime SENSOR_ACCEL = SensorType(1)
# A gyroscope, in radians per second.
comptime SENSOR_GYRO = SensorType(2)
# The accelerometer of a left Joy-Con.
comptime SENSOR_ACCEL_L = SensorType(3)
comptime SENSOR_GYRO_L = SensorType(4)
comptime SENSOR_ACCEL_R = SensorType(5)
comptime SENSOR_GYRO_R = SensorType(6)


def is_accelerometer(type: SensorType) -> Bool:
    """Return True if a sensor type measures acceleration.

    Args:
        type: The sensor type.

    Returns:
        Whether it is one of the three accelerometers.
    """
    return (
        type == SENSOR_ACCEL
        or type == SENSOR_ACCEL_L
        or (type == SENSOR_ACCEL_R)
    )


@fieldwise_init
struct JoystickEventKind(Equatable, ImplicitlyCopyable, Writable):
    """What a joystick event is about. SDL: `SDL_EVENT_JOYSTICK_*`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 7 kinds.

        Returns:
            Whether the value is 0 to 6.
        """
        return ordinal_valid(self.value, 6)


# An axis moved. SDL: `SDL_EVENT_JOYSTICK_AXIS_MOTION`.
comptime JOYSTICK_AXIS_MOTION = JoystickEventKind(0)
# A button went down or up. SDL: `SDL_EVENT_JOYSTICK_BUTTON_DOWN` and `_UP`.
comptime JOYSTICK_BUTTON = JoystickEventKind(1)
# A hat moved. SDL: `SDL_EVENT_JOYSTICK_HAT_MOTION`.
comptime JOYSTICK_HAT_MOTION = JoystickEventKind(2)
# A finger touched a touchpad. SDL: `SDL_EVENT_GAMEPAD_TOUCHPAD_DOWN`.
comptime JOYSTICK_TOUCHPAD_DOWN = JoystickEventKind(3)
# A finger moved. SDL: `SDL_EVENT_GAMEPAD_TOUCHPAD_MOTION`.
comptime JOYSTICK_TOUCHPAD_MOTION = JoystickEventKind(4)
# A finger left a touchpad. SDL: `SDL_EVENT_GAMEPAD_TOUCHPAD_UP`.
comptime JOYSTICK_TOUCHPAD_UP = JoystickEventKind(5)
# A sensor reported. SDL: `SDL_EVENT_GAMEPAD_SENSOR_UPDATE`.
comptime JOYSTICK_SENSOR_UPDATE = JoystickEventKind(6)


struct JoystickEvent(ImplicitlyCopyable):
    """One change of a joystick's state."""

    var kind: JoystickEventKind
    # The axis, the button, the hat, the touchpad or the sensor type.
    var index: Int
    # The axis value, 1 or 0 for a button down or up, the hat bits, or the
    # finger.
    var value: Int
    # A finger's position and pressure, from 0 to 1.
    var x: Float32
    var y: Float32
    var pressure: Float32
    # A sensor's reading, in SI units.
    var data: SIMD[DType.float32, SENSOR_VALUES]
    # The sensor's own clock.
    var sensor_timestamp: Duration64

    def __init__(
        out self,
        kind: JoystickEventKind,
        index: Int,
        value: Int,
        x: Float32 = 0,
        y: Float32 = 0,
        pressure: Float32 = 0,
        data: SIMD[DType.float32, SENSOR_VALUES] = 0,
        sensor_timestamp: Duration64 = Duration64(0),
    ):
        """Create an event.

        Args:
            kind: What changed.
            index: The axis, button, hat, touchpad or sensor type.
            value: The new value, or the finger.
            x: A finger's position across the touchpad.
            y: A finger's position down the touchpad.
            pressure: A finger's pressure.
            data: A sensor's reading.
            sensor_timestamp: The sensor's clock.
        """
        self.kind = kind
        self.index = index
        self.value = value
        self.x = x
        self.y = y
        self.pressure = pressure
        self.data = data
        self.sensor_timestamp = sensor_timestamp


struct TouchpadFinger(ImplicitlyCopyable, Writable):
    """One finger on a touchpad. SDL: `SDL_JoystickTouchpadFingerInfo`."""

    var down: Bool
    # From 0 at the left to 1 at the right.
    var x: Float32
    # From 0 at the top to 1 at the bottom.
    var y: Float32
    # From 0 to 1.
    var pressure: Float32

    def __init__(
        out self,
        down: Bool = False,
        x: Float32 = 0,
        y: Float32 = 0,
        pressure: Float32 = 0,
    ):
        """Create a finger.

        Args:
            down: Whether it touches the pad.
            x: Its position across.
            y: Its position down.
            pressure: Its pressure.
        """
        self.down = down
        self.x = x
        self.y = y
        self.pressure = pressure


struct JoystickSensor(ImplicitlyCopyable):
    """One motion sensor. SDL: `SDL_JoystickSensorInfo`."""

    var type: SensorType
    var rate: Frequency
    var enabled: Bool
    # The last reading, in meters per second squared or radians per second.
    var data: SIMD[DType.float32, SENSOR_VALUES]

    def __init__(out self, type: SensorType, rate: Frequency):
        """Create a sensor that is off.

        Args:
            type: What it measures.
            rate: How often it reports, or 0 when it does not say.
        """
        self.type = type
        self.rate = rate
        self.enabled = False
        self.data = SIMD[DType.float32, SENSOR_VALUES](0)


def _clamp_unit(value: Float32) -> Float32:
    """Clamp a value to 0 to 1.

    Args:
        value: The value.

    Returns:
        The value, at least 0 and at most 1.
    """
    if value < 0:
        return 0
    if value > 1:
        return 1
    return value


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
    var touchpads: List[List[TouchpadFinger]]
    var sensors: List[JoystickSensor]
    # How many sensors are enabled. The driver reports while any is.
    var sensors_enabled: Int
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
        self.touchpads = List[List[TouchpadFinger]]()
        self.sensors = List[JoystickSensor]()
        self.sensors_enabled = 0
        self.events = List[JoystickEvent]()
        # SDL_OpenJoystick: a two-axis pad, or one SDL knows, is centered
        # at zero, so its first values are motion.
        var info = joystick_guid_info(guid)
        var key = (info.vendor.value << 16) | info.product.value
        if axes == 2 or key == 0x05A03232 or key == 0x0E8F3013:
            for index in range(axes):
                self.axes[index].has_initial_value = True
        # The drivers that know their triggers rest at -32768.
        var driver = guid.driver()
        if (
            driver == DRIVER_HIDAPI
            or driver == DRIVER_XINPUT
            or driver == DRIVER_RAWINPUT
            or driver == DRIVER_WGI
        ) and axes >= AXIS_COUNT:
            var left = 2 if driver == DRIVER_XINPUT else 4
            var right = 5
            for index in range(AXIS_COUNT):  # pragma: no branch
                var rest = JOYSTICK_AXIS_MIN if (
                    index == left or index == right
                ) else 0
                self.axes[index].value = rest
                self.axes[index].zero = rest
                self.axes[index].initial_value = rest
                self.axes[index].has_initial_value = True

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

    def add_touchpad(mut self, fingers: Int) raises:
        """Add a touchpad. SDL: `SDL_PrivateJoystickAddTouchpad`.

        Args:
            fingers: How many fingers it tracks at once.

        Raises:
            Error: If the count is negative.
        """
        if fingers < 0:
            raise Error("A touchpad cannot track a negative number of fingers")
        self.touchpads.append(
            List[TouchpadFinger](length=fingers, fill=TouchpadFinger())
        )

    def add_sensor(mut self, type: SensorType, rate: Frequency) raises:
        """Add a motion sensor, off. SDL: `SDL_PrivateJoystickAddSensor`.

        Args:
            type: What it measures.
            rate: How often it reports, or 0.

        Raises:
            Error: If the type is not valid.
        """
        if not type.is_valid():
            raise Error("A joystick sensor type is not valid")
        self.sensors.append(JoystickSensor(type, rate))

    def sensor_index(self, type: SensorType) -> Int:
        """Return the place of the first sensor of a type.

        Args:
            type: The sensor type.

        Returns:
            The index in `sensors`, or -1 when there is none.
        """
        for index in range(len(self.sensors)):
            if self.sensors[index].type == type:
                return index
        return -1

    def sensor_switch(self, type: SensorType, enabled: Bool) raises -> Int:
        """Say what the driver must do to turn a sensor on or off. SDL: the
        first half of `SDL_SetGamepadSensorEnabled`.

        Args:
            type: The sensor type.
            enabled: Whether it is to be on.

        Returns:
            1 when the driver must start reporting, -1 when it must stop,
            and 0 when nothing changes for the driver.

        Raises:
            Error: If the joystick has no sensor of the type.
        """
        var index = self.sensor_index(type)
        if index < 0:
            raise Error("The joystick has no sensor of this type")
        if self.sensors[index].enabled == enabled:
            return 0
        if enabled and self.sensors_enabled == 0:
            return 1
        if not enabled and self.sensors_enabled == 1:
            return -1
        return 0

    def set_sensor_enabled(mut self, type: SensorType, enabled: Bool) raises:
        """Turn a sensor on or off, after the driver agreed. SDL: the second
        half of `SDL_SetGamepadSensorEnabled`.

        Args:
            type: The sensor type.
            enabled: Whether it is on.

        Raises:
            Error: If the joystick has no sensor of the type.
        """
        var index = self.sensor_index(type)
        if index < 0:
            raise Error("The joystick has no sensor of this type")
        if self.sensors[index].enabled == enabled:
            return
        self.sensors_enabled += 1 if enabled else -1
        self.sensors[index].enabled = enabled

    def send_sensor(
        mut self,
        type: SensorType,
        sensor_timestamp: Duration64,
        data: SIMD[DType.float32, SENSOR_VALUES],
    ):
        """Record a sensor reading. SDL: `SDL_SendJoystickSensor`.

        A reading of a sensor that is off, or that the joystick does not
        have, is dropped.

        Args:
            type: The sensor type.
            sensor_timestamp: The sensor's clock.
            data: The reading, in SI units. Unused values are 0.
        """
        var index = self.sensor_index(type)
        if index < 0 or not self.sensors[index].enabled:
            return
        self.sensors[index].data = data
        self.events.append(
            JoystickEvent(
                JOYSTICK_SENSOR_UPDATE,
                type.value,
                0,
                data=data,
                sensor_timestamp=sensor_timestamp,
            )
        )

    def send_touchpad(
        mut self,
        touchpad: Int,
        finger: Int,
        down: Bool,
        x: Float32,
        y: Float32,
        pressure: Float32,
    ):
        """Record a finger on a touchpad. SDL: `SDL_SendJoystickTouchpad`.

        A lifted finger at 0, 0 keeps its last position. Positions and the
        pressure are clamped to 0 to 1. A lifted finger has no pressure.

        Args:
            touchpad: The touchpad. One the joystick does not have is
                ignored.
            finger: The finger. One the touchpad does not track is ignored.
            down: Whether it touches.
            x: Its position across.
            y: Its position down.
            pressure: Its pressure.
        """
        if touchpad < 0 or touchpad >= len(self.touchpads):
            return
        if finger < 0 or finger >= len(self.touchpads[touchpad]):
            return
        var info = self.touchpads[touchpad][finger]
        var at_x = x
        var at_y = y
        var force = pressure
        if not down:
            if at_x == 0 and at_y == 0:
                at_x = info.x
                at_y = info.y
            force = 0
        at_x = _clamp_unit(at_x)
        at_y = _clamp_unit(at_y)
        force = _clamp_unit(force)
        if down == info.down and (
            not down
            or (at_x == info.x and at_y == info.y and force == info.pressure)
        ):
            return
        var kind: JoystickEventKind
        if down == info.down:
            kind = JOYSTICK_TOUCHPAD_MOTION
        elif down:
            kind = JOYSTICK_TOUCHPAD_DOWN
        else:
            kind = JOYSTICK_TOUCHPAD_UP
        self.touchpads[touchpad][finger] = TouchpadFinger(
            down, at_x, at_y, force
        )
        self.events.append(
            JoystickEvent(kind, touchpad, finger, at_x, at_y, force)
        )

    def take_events(mut self) -> List[JoystickEvent]:
        """Return the queued events and empty the queue.

        Returns:
            The changes since the last call, in order.
        """
        var taken = self.events^
        self.events = List[JoystickEvent]()
        return taken^
