# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of src/joystick/linux/SDL_sysjoystick.c and
# src/core/linux/SDL_evdev_capabilities.c, from SDL 3.2.24. It is a
# translation from C to Mojo. It is not the original software. The original
# notice follows.
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

"""The Linux evdev joystick logic, apart from the device calls.

A Linux input device reports what it has as bitmaps: the event types,
the key codes, the absolute axes. `EvdevCapabilities` holds them.
`guess_device_class` says from them whether the device is a joystick.
`EvdevLayout.configure` numbers its buttons, axes and hats as SDL does:
the joystick buttons from `BTN_JOYSTICK` up first, then the codes below
it. It also works out how to scale each axis to -32768 to 32767.

`EvdevState` applies the device's events to a `Joystick`, and
`automatic_mapping` writes the gamepad mapping of a device that follows
the kernel's gamepad layout. The kernel's drivers for Xbox and
PlayStation controllers do. So an Xbox or a DualSense controller works
with no database entry.

One result differs from SDL 3.2.24 and from SDL's main branch at
3da8c67d. When the d-pad is an analog hat, SDL binds up and down both to
the whole Y axis, and left and right both to the whole X axis. Then all
four directions read as pressed at rest, and left cannot be told from
right. This port binds each direction to its half of the axis.

A pad's motion sensors are a device of their own, which SDL pairs with
the pad by its unique id. `SensorLayout` and `SensorState` read that
device: an accelerometer in meters per second squared and a gyroscope in
radians per second. `encode_ff_effect` writes the force feedback effect
that makes a pad rumble.

The device calls are in `extensions.gamepad.linux`. The classic `js`
interface and trackballs are not ported.
"""
from extensions.gamepad.guid import VendorId
from extensions.gamepad.ids import (
    AXIS_LEFTX,
    AXIS_LEFTY,
    AXIS_LEFT_TRIGGER,
    AXIS_RIGHTX,
    AXIS_RIGHTY,
    AXIS_RIGHT_TRIGGER,
    BUTTON_BACK,
    BUTTON_DPAD_DOWN,
    BUTTON_DPAD_LEFT,
    BUTTON_DPAD_RIGHT,
    BUTTON_DPAD_UP,
    BUTTON_EAST,
    BUTTON_GUIDE,
    BUTTON_LEFT_PADDLE1,
    BUTTON_LEFT_PADDLE2,
    BUTTON_LEFT_SHOULDER,
    BUTTON_LEFT_STICK,
    BUTTON_MISC1,
    BUTTON_NORTH,
    BUTTON_RIGHT_PADDLE1,
    BUTTON_RIGHT_PADDLE2,
    BUTTON_RIGHT_SHOULDER,
    BUTTON_RIGHT_STICK,
    BUTTON_SOUTH,
    BUTTON_START,
    BUTTON_WEST,
    JOYSTICK_AXIS_MAX,
    JOYSTICK_AXIS_MIN,
    GamepadButton,
)
from extensions.gamepad.joystick import (
    SENSOR_ACCEL,
    SENSOR_GYRO,
    SENSOR_VALUES,
    Joystick,
)
from extensions.gamepad.mapping import (
    HAT_CENTERED,
    HAT_DOWN,
    HAT_LEFT,
    HAT_RIGHT,
    HAT_UP,
    MAPPING_AXIS,
    MAPPING_BUTTON,
    MAPPING_HAT,
    AutoMapping,
    InputMapping,
)
from std.math import floor
from units.si import Duration64, SECOND

# Event types.
comptime EV_SYN = 0x00
comptime EV_KEY = 0x01
comptime EV_REL = 0x02
comptime EV_ABS = 0x03
comptime EV_MSC = 0x04
comptime EV_FF = 0x15
# The sensor clock, in microseconds.
comptime MSC_TIMESTAMP = 0x05
# Force feedback effects.
comptime FF_RUMBLE = 0x50
comptime FF_PERIODIC = 0x51
comptime FF_SINE = 0x5A
comptime FF_BITMAP_BYTES = 16
# The size of `struct ff_effect` on a 64-bit system.
comptime FF_EFFECT_SIZE = 48
# Earth's gravity. SDL: `SDL_STANDARD_GRAVITY`.
comptime STANDARD_GRAVITY = Float32(9.80665)
# Synchronization codes.
comptime SYN_REPORT = 0
comptime SYN_DROPPED = 3
# The highest codes, and the sizes of the bitmaps that hold them.
comptime KEY_MAX = 0x2FF
comptime ABS_MAX = 0x3F
comptime KEY_BITMAP_BYTES = 96
comptime ABS_BITMAP_BYTES = 8
comptime REL_BITMAP_BYTES = 8
comptime EV_BITMAP_BYTES = 8
comptime PROP_BITMAP_BYTES = 8
# Absolute axes.
comptime ABS_X = 0x00
comptime ABS_Y = 0x01
comptime ABS_Z = 0x02
comptime ABS_RX = 0x03
comptime ABS_RY = 0x04
comptime ABS_RZ = 0x05
comptime ABS_THROTTLE = 0x06
comptime ABS_RUDDER = 0x07
comptime ABS_WHEEL = 0x08
comptime ABS_GAS = 0x09
comptime ABS_BRAKE = 0x0A
comptime ABS_HAT0X = 0x10
comptime ABS_HAT0Y = 0x11
comptime ABS_HAT1X = 0x12
comptime ABS_HAT1Y = 0x13
comptime ABS_HAT2X = 0x14
comptime ABS_HAT2Y = 0x15
comptime ABS_HAT3Y = 0x17
# Relative axes.
comptime REL_X = 0x00
comptime REL_Y = 0x01
# Keys and buttons.
comptime KEY_RECORD = 167
comptime BTN_MISC = 0x100
comptime BTN_1 = 0x101
comptime BTN_MOUSE = 0x110
comptime BTN_JOYSTICK = 0x120
comptime BTN_TRIGGER = 0x120
comptime BTN_GAMEPAD = 0x130
comptime BTN_A = 0x130
comptime BTN_B = 0x131
comptime BTN_NORTH = 0x133
comptime BTN_X = 0x133
comptime BTN_WEST = 0x134
comptime BTN_Y = 0x134
comptime BTN_TL = 0x136
comptime BTN_TR = 0x137
comptime BTN_TL2 = 0x138
comptime BTN_TR2 = 0x139
comptime BTN_SELECT = 0x13A
comptime BTN_START = 0x13B
comptime BTN_MODE = 0x13C
comptime BTN_THUMBL = 0x13D
comptime BTN_THUMBR = 0x13E
comptime BTN_TOOL_PEN = 0x140
comptime BTN_TOOL_FINGER = 0x145
comptime BTN_TOUCH = 0x14A
comptime BTN_STYLUS = 0x14B
comptime KEY_OK = 0x160
comptime BTN_DPAD_UP = 0x220
comptime BTN_DPAD_DOWN = 0x221
comptime BTN_DPAD_LEFT = 0x222
comptime BTN_DPAD_RIGHT = 0x223
comptime KEY_ALS_TOGGLE = 0x230
comptime BTN_TRIGGER_HAPPY = 0x2C0
# Device properties.
comptime INPUT_PROP_BUTTONPAD = 0x02
comptime INPUT_PROP_SEMI_MT = 0x03
comptime INPUT_PROP_TOPBUTTONPAD = 0x04
comptime INPUT_PROP_POINTING_STICK = 0x05
comptime INPUT_PROP_ACCELEROMETER = 0x06
# The size of one `struct input_event` on a 64-bit system: a 16-byte
# time, a 16-bit type, a 16-bit code and a 32-bit value.
comptime INPUT_EVENT_SIZE = 24
# The size of one `struct input_absinfo`: six 32-bit integers.
comptime ABSINFO_SIZE = 24
# The number of hats evdev has: `ABS_HAT0X` to `ABS_HAT3Y` in pairs.
comptime HAT_COUNT = 4
# The value a key or axis map holds for a code the device does not have.
# SDL fills its byte maps with 0xFF.
comptime NO_INDEX = 0xFF


def test_bit(bits: List[UInt8], number: Int) -> Bool:
    """Return whether a bit of a kernel bitmap is set. SDL: `test_bit`.

    The bitmaps are arrays of `unsigned long`. On a little-endian system,
    which every supported platform is, bit `n` is bit `n % 8` of byte
    `n / 8`.

    Args:
        bits: The bitmap's bytes.
        number: The bit.

    Returns:
        Whether it is set. A bit past the end is not.
    """
    var byte = number >> 3
    if number < 0 or byte >= len(bits):
        return False
    return ((bits[byte] >> UInt8(number & 7)) & 1) != 0


def set_bit(mut bits: List[UInt8], number: Int):
    """Set a bit of a kernel bitmap.

    Args:
        bits: The bitmap's bytes. It must be long enough.
        number: The bit.
    """
    bits[number >> 3] |= UInt8(1) << UInt8(number & 7)


def _read_int32(bytes: List[UInt8], offset: Int) -> Int:
    """Read a little-endian signed 32-bit integer.

    Args:
        bytes: The bytes.
        offset: Where the integer starts.

    Returns:
        The integer.
    """
    var value = 0
    for index in range(4):
        value |= Int(bytes[offset + index]) << (8 * index)
    return value - (1 << 32) if value >= (1 << 31) else value


def _read_uint16(bytes: List[UInt8], offset: Int) -> Int:
    """Read a little-endian unsigned 16-bit integer.

    Args:
        bytes: The bytes.
        offset: Where the integer starts.

    Returns:
        The integer.
    """
    return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)


def c_divide(a: Int, b: Int) -> Int:
    """Divide integers as C does, rounding toward zero.

    Args:
        a: The dividend.
        b: The divisor, which is not zero.

    Returns:
        The quotient, rounded toward zero.
    """
    var quotient = a // b
    if quotient < 0 and quotient * b != a:
        quotient += 1
    return quotient


@fieldwise_init
struct DeviceClass(Equatable, ImplicitlyCopyable, Writable):
    """What kinds of device an input device is, as bits. SDL:
    `SDL_UDEV_deviceclass`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if only known bits are set.

        Returns:
            Whether the value is a set of the nine classes.
        """
        return self.value >= 0 and (self.value & ~0x1FF) == 0

    def has(self, other: DeviceClass) -> Bool:
        """Return True if this set has all the bits of another.

        Args:
            other: The classes to look for.

        Returns:
            Whether every bit of `other` is set here.
        """
        return (self.value & other.value) == other.value


comptime DEVICE_UNKNOWN = DeviceClass(0x0000)
comptime DEVICE_MOUSE = DeviceClass(0x0001)
comptime DEVICE_KEYBOARD = DeviceClass(0x0002)
comptime DEVICE_JOYSTICK = DeviceClass(0x0004)
comptime DEVICE_TOUCHSCREEN = DeviceClass(0x0010)
comptime DEVICE_ACCELEROMETER = DeviceClass(0x0020)
comptime DEVICE_TOUCHPAD = DeviceClass(0x0040)
comptime DEVICE_HAS_KEYS = DeviceClass(0x0080)


struct AbsInfo(Equatable, ImplicitlyCopyable, Writable):
    """The range of an absolute axis. Linux: `struct input_absinfo`."""

    var value: Int
    var minimum: Int
    var maximum: Int
    var fuzz: Int
    var flat: Int
    var resolution: Int

    def __init__(
        out self,
        value: Int = 0,
        minimum: Int = 0,
        maximum: Int = 0,
        fuzz: Int = 0,
        flat: Int = 0,
        resolution: Int = 0,
    ):
        """Create an axis range.

        Args:
            value: The axis's current value.
            minimum: The lowest value.
            maximum: The highest value.
            fuzz: The noise the kernel filters out.
            flat: The dead zone at the center.
            resolution: Units per millimeter or per radian.
        """
        self.value = value
        self.minimum = minimum
        self.maximum = maximum
        self.fuzz = fuzz
        self.flat = flat
        self.resolution = resolution

    @staticmethod
    def from_bytes(bytes: List[UInt8]) raises -> AbsInfo:
        """Read the structure the kernel writes.

        Args:
            bytes: Its 24 bytes.

        Returns:
            The axis range.

        Raises:
            Error: If there are fewer than 24 bytes.
        """
        if len(bytes) < ABSINFO_SIZE:
            raise Error("An input_absinfo is 24 bytes")
        return AbsInfo.from_buffer(bytes)

    @staticmethod
    def from_buffer(bytes: List[UInt8]) -> AbsInfo:
        """Read the structure from a buffer known to hold 24 bytes.

        Args:
            bytes: At least 24 bytes.

        Returns:
            The axis range.
        """
        return AbsInfo(
            _read_int32(bytes, 0),
            _read_int32(bytes, 4),
            _read_int32(bytes, 8),
            _read_int32(bytes, 12),
            _read_int32(bytes, 16),
            _read_int32(bytes, 20),
        )


struct InputId(Equatable, ImplicitlyCopyable, Writable):
    """Who made a device. Linux: `struct input_id`."""

    var bustype: Int
    var vendor: Int
    var product: Int
    var version: Int

    def __init__(
        out self,
        bustype: Int = 0,
        vendor: Int = 0,
        product: Int = 0,
        version: Int = 0,
    ):
        """Create a device identity.

        Args:
            bustype: The bus, such as 3 for USB.
            vendor: The USB vendor id.
            product: The USB product id.
            version: The product version.
        """
        self.bustype = bustype
        self.vendor = vendor
        self.product = product
        self.version = version

    @staticmethod
    def from_bytes(bytes: List[UInt8]) raises -> InputId:
        """Read the structure the kernel writes.

        Args:
            bytes: Its 8 bytes: four 16-bit words.

        Returns:
            The identity.

        Raises:
            Error: If there are fewer than 8 bytes.
        """
        if len(bytes) < 8:
            raise Error("An input_id is 8 bytes")
        return InputId.from_buffer(bytes)

    @staticmethod
    def from_buffer(bytes: List[UInt8]) -> InputId:
        """Read the structure from a buffer known to hold 8 bytes.

        Args:
            bytes: At least 8 bytes.

        Returns:
            The identity.
        """
        return InputId(
            _read_uint16(bytes, 0),
            _read_uint16(bytes, 2),
            _read_uint16(bytes, 4),
            _read_uint16(bytes, 6),
        )


struct EvdevCapabilities(Copyable, Movable):
    """What an input device says it has."""

    var properties: List[UInt8]
    var events: List[UInt8]
    var keys: List[UInt8]
    var absolutes: List[UInt8]
    var relatives: List[UInt8]

    def __init__(out self):
        """Create capabilities with no bit set."""
        self.properties = List[UInt8](length=PROP_BITMAP_BYTES, fill=0)
        self.events = List[UInt8](length=EV_BITMAP_BYTES, fill=0)
        self.keys = List[UInt8](length=KEY_BITMAP_BYTES, fill=0)
        self.absolutes = List[UInt8](length=ABS_BITMAP_BYTES, fill=0)
        self.relatives = List[UInt8](length=REL_BITMAP_BYTES, fill=0)


def _any_key(keys: List[UInt8], start: Int, end: Int) -> Bool:
    """Return True if any key from `start` up to `end` is set.

    Args:
        keys: The key bitmap.
        start: The first code.
        end: The code after the last.

    Returns:
        Whether one of the bits is set.
    """
    for code in range(start, end):  # pragma: no branch
        if test_bit(keys, code):
            return True
    return False


def guess_device_class(caps: EvdevCapabilities) -> DeviceClass:
    """Return what kinds of device an input device is. SDL:
    `SDL_EVDEV_GuessDeviceClass`.

    Args:
        caps: The device's bitmaps.

    Returns:
        The classes. A device with absolute X and Y and a joystick button,
        or a second stick, a throttle, a rudder, a wheel, a gas or a brake
        pedal, is a joystick.
    """
    ref props = caps.properties
    ref ev = caps.events
    ref abs = caps.absolutes
    ref key = caps.keys
    if test_bit(props, INPUT_PROP_ACCELEROMETER):
        return DEVICE_ACCELEROMETER
    if test_bit(props, INPUT_PROP_POINTING_STICK):
        return DEVICE_MOUSE
    if (
        test_bit(props, INPUT_PROP_TOPBUTTONPAD)
        or test_bit(props, INPUT_PROP_BUTTONPAD)
        or test_bit(props, INPUT_PROP_SEMI_MT)
    ):
        return DEVICE_TOUCHPAD
    var has_abs = test_bit(ev, EV_ABS)
    var has_keys = test_bit(ev, EV_KEY)
    if (
        has_abs
        and test_bit(abs, ABS_X)
        and test_bit(abs, ABS_Y)
        and test_bit(abs, ABS_Z)
        and not has_keys
    ):
        return DEVICE_ACCELEROMETER
    if (
        has_abs
        and test_bit(abs, ABS_RX)
        and test_bit(abs, ABS_RY)
        and test_bit(abs, ABS_RZ)
        and not has_keys
    ):
        return DEVICE_ACCELEROMETER
    var classes = 0
    if has_abs and test_bit(abs, ABS_X) and test_bit(abs, ABS_Y):
        if test_bit(key, BTN_STYLUS) or test_bit(key, BTN_TOOL_PEN):
            pass
        elif test_bit(key, BTN_TOOL_FINGER):
            classes |= DEVICE_TOUCHPAD.value
        elif test_bit(key, BTN_MOUSE):
            classes |= DEVICE_MOUSE.value
        elif test_bit(key, BTN_TOUCH):
            classes |= DEVICE_TOUCHSCREEN.value
        var joystick_codes: List[Int] = [
            ABS_RX,
            ABS_RY,
            ABS_RZ,
            ABS_THROTTLE,
            ABS_RUDDER,
            ABS_WHEEL,
            ABS_GAS,
            ABS_BRAKE,
        ]
        var joystick = (
            test_bit(key, BTN_TRIGGER)
            or test_bit(key, BTN_A)
            or test_bit(key, BTN_1)
        )
        for code in joystick_codes:  # pragma: no branch
            joystick = joystick or test_bit(abs, code)
        if joystick:
            classes |= DEVICE_JOYSTICK.value
    if (
        test_bit(ev, EV_REL)
        and test_bit(caps.relatives, REL_X)
        and test_bit(caps.relatives, REL_Y)
        and test_bit(key, BTN_MOUSE)
    ):
        classes |= DEVICE_MOUSE.value
    if has_keys:
        var found = _any_key(key, 0, BTN_MISC)
        if not found:
            found = _any_key(key, KEY_OK, BTN_DPAD_UP) or _any_key(
                key, KEY_ALS_TOGGLE, BTN_TRIGGER_HAPPY
            )
        if found:
            classes |= DEVICE_HAS_KEYS.value
    # Keys 1 to 31 are Escape, the digits and Q to D: a full keyboard.
    var keyboard = True
    for code in range(1, 32):
        keyboard = keyboard and test_bit(key, code)
    if keyboard:
        classes |= DEVICE_KEYBOARD.value
    return DeviceClass(classes)


def is_digital_hat(
    x: Optional[AbsInfo], y: Optional[AbsInfo], digital_hats: Bool = False
) -> Bool:
    """Return True if a pair of hat axes is a digital hat. SDL:
    `GuessIfAxesAreDigitalHat`.

    Linux does not say whether a hat axis is digital, so SDL guesses.

    Args:
        x: The X axis's range, or None when the device does not have it.
        y: The Y axis's range, or None.
        digital_hats: SDL's hint `SDL_JOYSTICK_LINUX_DIGITAL_HATS`, which
            says every hat is digital.

    Returns:
        Whether the axes are a hat: at least one is there, and each that
        is there is from -1 to 1, or has no fuzz, flat or resolution.
    """
    if not x and not y:
        return False
    if digital_hats:
        return True
    var x_unit = not x or (x.value().minimum == -1 and x.value().maximum == 1)
    var y_unit = not y or (y.value().minimum == -1 and y.value().maximum == 1)
    if x_unit and y_unit:
        return True
    var x_bare = not x or (
        x.value().fuzz == 0
        and x.value().flat == 0
        and x.value().resolution == 0
    )
    var y_bare = not y or (
        y.value().fuzz == 0
        and y.value().flat == 0
        and y.value().resolution == 0
    )
    return x_bare and y_bare


struct AxisCorrect(ImplicitlyCopyable):
    """How to scale one axis. SDL: `struct axis_correct`."""

    var use_deadzones: Bool
    var coef0: Int
    var coef1: Int
    var coef2: Int
    var minimum: Int
    var maximum: Int
    var scale: Float32

    def __init__(out self):
        """Create a correction that passes values through."""
        self.use_deadzones = False
        self.coef0 = 0
        self.coef1 = 0
        self.coef2 = 0
        self.minimum = 0
        self.maximum = 0
        self.scale = 0


struct HatCorrect(ImplicitlyCopyable):
    """The range of one hat's two axes. SDL: `struct hat_axis_correct`."""

    var use_deadzones: Bool
    var minimum: SIMD[DType.int64, 2]
    var maximum: SIMD[DType.int64, 2]

    def __init__(out self):
        """Create a hat range of zero."""
        self.use_deadzones = False
        self.minimum = SIMD[DType.int64, 2](0)
        self.maximum = SIMD[DType.int64, 2](0)


struct EvdevLayout(Copyable, Movable):
    """How a device's codes become joystick buttons, axes and hats. SDL:
    the layout part of `struct joystick_hwdata`, which `ConfigJoystick`
    fills."""

    var key_map: List[Int]
    var has_key: List[Bool]
    var abs_map: List[Int]
    var has_abs: List[Bool]
    var abs_correct: List[AxisCorrect]
    var has_hat: List[Bool]
    var hat_index: List[Int]
    var hat_correct: List[HatCorrect]
    var buttons: Int
    var axes: Int
    var hats: Int

    def __init__(out self):
        """Create a layout with no inputs."""
        self.key_map = List[Int](length=KEY_MAX, fill=NO_INDEX)
        self.has_key = List[Bool](length=KEY_MAX, fill=False)
        self.abs_map = List[Int](length=ABS_MAX, fill=NO_INDEX)
        self.has_abs = List[Bool](length=ABS_MAX, fill=False)
        self.abs_correct = List[AxisCorrect](length=ABS_MAX, fill=AxisCorrect())
        self.has_hat = List[Bool](length=HAT_COUNT, fill=False)
        self.hat_index = List[Int](length=HAT_COUNT, fill=0)
        self.hat_correct = List[HatCorrect](length=HAT_COUNT, fill=HatCorrect())
        self.buttons = 0
        self.axes = 0
        self.hats = 0

    def _add_key(mut self, code: Int):
        """Give a key code the next button number.

        Args:
            code: The key code.
        """
        self.key_map[code] = self.buttons & 0xFF
        self.has_key[code] = True
        self.buttons += 1

    def configure(
        mut self,
        caps: EvdevCapabilities,
        absinfo: List[Optional[AbsInfo]],
        use_deadzones: Bool = False,
        use_hat_deadzones: Bool = True,
        digital_hats: Bool = False,
    ):
        """Number the buttons, axes and hats. SDL: `ConfigJoystick`, for
        the evdev interface.

        Args:
            caps: The device's bitmaps.
            absinfo: The range of each absolute axis, by code, or None
                where the device could not say.
            use_deadzones: SDL's hint `SDL_JOYSTICK_LINUX_DEADZONES`: honor
                each axis's flat zone.
            use_hat_deadzones: SDL's hint
                `SDL_JOYSTICK_LINUX_HAT_DEADZONES`.
            digital_hats: SDL's hint `SDL_JOYSTICK_LINUX_DIGITAL_HATS`.
        """
        for code in range(BTN_JOYSTICK, KEY_MAX):  # pragma: no branch
            if test_bit(caps.keys, code):
                self._add_key(code)
        for code in range(BTN_JOYSTICK):  # pragma: no branch
            if test_bit(caps.keys, code):
                self._add_key(code)
        for code in range(ABS_HAT0X, ABS_HAT3Y + 1, 2):  # pragma: no branch
            var x = Optional[AbsInfo]()
            var y = Optional[AbsInfo]()
            if test_bit(caps.absolutes, code):
                x = absinfo[code]
            if test_bit(caps.absolutes, code + 1):
                y = absinfo[code + 1]
            if not is_digital_hat(x, y, digital_hats):
                continue
            var hat = (code - ABS_HAT0X) // 2
            self.hat_index[hat] = self.hats
            self.has_hat[hat] = True
            ref correct = self.hat_correct[hat]
            correct.use_deadzones = use_hat_deadzones
            correct.minimum[0] = Int64(x.value().minimum if x else -1)
            correct.maximum[0] = Int64(x.value().maximum if x else 1)
            correct.minimum[1] = Int64(y.value().minimum if y else -1)
            correct.maximum[1] = Int64(y.value().maximum if y else 1)
            self.hats += 1
        for code in range(ABS_MAX):  # pragma: no branch
            if (
                code >= ABS_HAT0X
                and code <= ABS_HAT3Y
                and self.has_hat[(code - ABS_HAT0X) // 2]
            ):
                continue
            if not test_bit(caps.absolutes, code) or not absinfo[code]:
                continue
            var info = absinfo[code].value()
            self.abs_map[code] = self.axes & 0xFF
            self.has_abs[code] = True
            ref correct = self.abs_correct[code]
            correct.minimum = info.minimum
            correct.maximum = info.maximum
            if correct.minimum != correct.maximum:
                if use_deadzones:
                    correct.use_deadzones = True
                    correct.coef0 = (
                        info.maximum + info.minimum
                    ) - 2 * info.flat
                    correct.coef1 = (
                        info.maximum + info.minimum
                    ) + 2 * info.flat
                    var t = (info.maximum - info.minimum) - 4 * info.flat
                    correct.coef2 = c_divide(1 << 28, t) if t != 0 else 0
                else:
                    var value_range = Float32(correct.maximum - correct.minimum)
                    var output_range = Float32(
                        JOYSTICK_AXIS_MAX - JOYSTICK_AXIS_MIN
                    )
                    correct.scale = output_range / value_range
            self.axes += 1

    def axis_correct(self, code: Int, value: Int) -> Int:
        """Scale a raw axis value to -32768 to 32767. SDL: `AxisCorrect`.

        Args:
            code: The axis code.
            value: The raw value.

        Returns:
            The scaled value, clamped.
        """
        ref correct = self.abs_correct[code]
        var result = value
        if correct.minimum != correct.maximum:
            if correct.use_deadzones:
                result *= 2
                if result > correct.coef0:
                    if result < correct.coef1:
                        return 0
                    result -= correct.coef1
                else:
                    result -= correct.coef0
                result = Int(Int32(result * correct.coef2)) >> 13
            else:
                result = Int(
                    floor(
                        Float32(value - correct.minimum) * correct.scale
                        + Float32(JOYSTICK_AXIS_MIN)
                        + 0.5
                    )
                )
        if result < JOYSTICK_AXIS_MIN:
            return JOYSTICK_AXIS_MIN
        if result > JOYSTICK_AXIS_MAX:
            return JOYSTICK_AXIS_MAX
        return result


@fieldwise_init
struct EvdevEvent(ImplicitlyCopyable):
    """One event from a device. Linux: `struct input_event`, without the
    time."""

    var type: Int
    var code: Int
    var value: Int


def decode_input_events(bytes: List[UInt8]) -> List[EvdevEvent]:
    """Read the events a device sent.

    Args:
        bytes: Whole 24-byte `input_event` structures, as `read` gives
            them. A short tail is ignored.

    Returns:
        The events, in order.
    """
    var events = List[EvdevEvent]()
    var count = len(bytes) // INPUT_EVENT_SIZE
    for index in range(count):
        var at = index * INPUT_EVENT_SIZE
        events.append(
            EvdevEvent(
                _read_uint16(bytes, at + 16),
                _read_uint16(bytes, at + 18),
                _read_int32(bytes, at + 20),
            )
        )
    return events^


def encode_input_event(type: Int, code: Int, value: Int) -> List[UInt8]:
    """Write one `input_event` with a zero time, as a device sends it.

    Args:
        type: The event type.
        code: The code.
        value: The value.

    Returns:
        The 24 bytes.
    """
    var bytes = List[UInt8](length=INPUT_EVENT_SIZE, fill=0)
    bytes[16] = UInt8(type & 0xFF)
    bytes[17] = UInt8((type >> 8) & 0xFF)
    bytes[18] = UInt8(code & 0xFF)
    bytes[19] = UInt8((code >> 8) & 0xFF)
    for index in range(4):
        bytes[20 + index] = UInt8((value >> (8 * index)) & 0xFF)
    return bytes^


def _hat_position(x: Int, y: Int) -> Int:
    """Return the hat bits of a pair of axis states. SDL: `position_map`.

    Args:
        x: 0 left, 1 center or 2 right.
        y: 0 up, 1 center or 2 down.

    Returns:
        The direction bits.
    """
    var horizontal: List[Int] = [HAT_LEFT, HAT_CENTERED, HAT_RIGHT]
    var vertical: List[Int] = [HAT_UP, HAT_CENTERED, HAT_DOWN]
    return horizontal[x] | vertical[y]


struct EvdevState(Copyable, Movable):
    """A device's layout and what SDL tracks while reading it."""

    var layout: EvdevLayout
    # Each hat's two axes, as 0, 1 or 2. SDL: `struct hwdata_hat`.
    var hat_axes: List[SIMD[DType.int64, 2]]
    # Whether the device has not been read yet, so that its whole state
    # must be read first.
    var fresh: Bool
    # Whether the kernel dropped events, so that the rest of this report
    # must be ignored.
    var recovering_from_dropped: Bool

    def __init__(out self, var layout: EvdevLayout):
        """Create the state of a device that has not been read.

        Args:
            layout: The device's layout.
        """
        self.layout = layout^
        self.hat_axes = List[SIMD[DType.int64, 2]](
            length=HAT_COUNT, fill=SIMD[DType.int64, 2](1)
        )
        self.fresh = True
        self.recovering_from_dropped = False

    def handle_hat(
        mut self, mut joystick: Joystick, hat: Int, axis: Int, value: Int
    ):
        """Apply one hat axis value. SDL: `HandleHat`.

        A value at or past the axis's end widens the range and counts. A
        value inside the range counts past a third of it when dead zones
        are on.

        Args:
            joystick: The joystick to update.
            hat: The evdev hat, from 0 to 3.
            axis: 0 for X, 1 for Y.
            value: The raw value.
        """
        var number = self.layout.hat_index[hat]
        ref correct = self.layout.hat_correct[hat]
        var state: Int
        if value < 0:
            if value <= Int(correct.minimum[axis]):
                correct.minimum[axis] = Int64(value)
                state = 0
            elif not correct.use_deadzones or value < c_divide(
                Int(correct.minimum[axis]), 3
            ):
                state = 0
            else:
                state = 1
        elif value > 0:
            if value >= Int(correct.maximum[axis]):
                correct.maximum[axis] = Int64(value)
                state = 2
            elif not correct.use_deadzones or value > c_divide(
                Int(correct.maximum[axis]), 3
            ):
                state = 2
            else:
                state = 1
        else:
            state = 1
        if Int(self.hat_axes[number][axis]) != state:
            self.hat_axes[number][axis] = Int64(state)
            joystick.send_hat(
                number,
                _hat_position(
                    Int(self.hat_axes[number][0]),
                    Int(self.hat_axes[number][1]),
                ),
            )

    def handle_event(
        mut self, mut joystick: Joystick, event: EvdevEvent
    ) -> Bool:
        """Apply one event. SDL: the loop body of `HandleInputEvents`.

        Args:
            joystick: The joystick to update.
            event: The event.

        Returns:
            True when the device's whole state must be read again, after a
            report that followed dropped events.
        """
        var code = event.code
        if self.recovering_from_dropped and (
            event.type != EV_SYN or code != SYN_REPORT
        ):
            return False
        if event.type == EV_KEY:
            if code < KEY_MAX:
                joystick.send_button(
                    self.layout.key_map[code], event.value != 0
                )
        elif event.type == EV_ABS:
            if (
                code >= ABS_HAT0X
                and code <= ABS_HAT3Y
                and self.layout.has_hat[(code - ABS_HAT0X) // 2]
            ):
                self.handle_hat(
                    joystick, (code - ABS_HAT0X) // 2, code % 2, event.value
                )
            elif code < ABS_MAX:
                joystick.send_axis(
                    self.layout.abs_map[code],
                    self.layout.axis_correct(code, event.value),
                )
        elif event.type == EV_SYN:
            if code == SYN_DROPPED:
                self.recovering_from_dropped = True
            elif code == SYN_REPORT and self.recovering_from_dropped:
                self.recovering_from_dropped = False
                return True
        return False

    def apply_state(
        mut self,
        mut joystick: Joystick,
        absinfo: List[Optional[AbsInfo]],
        keys: Optional[List[UInt8]],
    ):
        """Apply the whole state read from the device. SDL:
        `PollAllValues`.

        Args:
            joystick: The joystick to update.
            absinfo: Each absolute axis's range and value, by code, or None
                where the device could not say.
            keys: The bitmap of keys that are down, or None when the device
                could not say.
        """
        for code in range(ABS_MAX):  # pragma: no branch
            if self.layout.has_abs[code] and absinfo[code]:
                joystick.send_axis(
                    self.layout.abs_map[code],
                    self.layout.axis_correct(code, absinfo[code].value().value),
                )
        for code in range(ABS_HAT0X, ABS_HAT3Y + 1):  # pragma: no branch
            var hat = (code - ABS_HAT0X) // 2
            if self.layout.has_hat[hat] and absinfo[code]:
                self.handle_hat(
                    joystick,
                    hat,
                    (code - ABS_HAT0X) % 2,
                    absinfo[code].value().value,
                )
        if keys:
            for code in range(KEY_MAX):  # pragma: no branch
                if self.layout.has_key[code]:
                    joystick.send_button(
                        self.layout.key_map[code], test_bit(keys.value(), code)
                    )


def fixup_device_id(id: InputId, keys: List[UInt8]) -> InputId:
    """Adjust a device's identity so that the right mapping is found. SDL:
    `FixupDeviceInfoForMapping`.

    Args:
        id: The identity the device reports.
        keys: The device's key bitmap.

    Returns:
        The identity. The first Xbox Elite Series 2 firmware, which reports
        each input twice, gets version 0x0902. Atari VCS controllers get
        version 0, since their mapping does not change with firmware.
    """
    var result = id
    if (
        id.vendor == 0x045E
        and id.product == 0x0B05
        and id.version == 0x0903
        and test_bit(keys, 0x2C0)
    ):
        result.version = 0x0902
    if id.vendor == 0x3250 and (id.product == 0x1001 or id.product == 0x1002):
        result.version = 0
    return result


def _button(layout: EvdevLayout, code: Int) -> InputMapping:
    """Return the input mapping of a key code.

    Args:
        layout: The layout.
        code: The key code, which the device has.

    Returns:
        A button mapping to the code's button number.
    """
    return InputMapping(MAPPING_BUTTON, layout.key_map[code])


def _axis(layout: EvdevLayout, code: Int) -> InputMapping:
    """Return the input mapping of an absolute axis.

    Args:
        layout: The layout.
        code: The axis code, which the device has.

    Returns:
        An axis mapping to the code's axis number.
    """
    return InputMapping(MAPPING_AXIS, layout.abs_map[code])


def _half_axis(layout: EvdevLayout, code: Int, positive: Bool) -> InputMapping:
    """Return the input mapping of one half of an absolute axis.

    Args:
        layout: The layout.
        code: The axis code, which the device has.
        positive: Whether it is the positive half.

    Returns:
        An axis mapping to the code's axis number and the half.
    """
    var mapping = InputMapping(MAPPING_AXIS, layout.abs_map[code])
    mapping.half_axis_positive = positive
    mapping.half_axis_negative = not positive
    return mapping


def _hat(layout: EvdevLayout, hat: Int, direction: Int) -> InputMapping:
    """Return the input mapping of a hat direction.

    Args:
        layout: The layout.
        hat: The evdev hat, which the device has.
        direction: The direction bit.

    Returns:
        A hat mapping to the hat's number and the direction.
    """
    return InputMapping(MAPPING_HAT, (layout.hat_index[hat] << 4) | direction)


def automatic_mapping(
    layout: EvdevLayout, vendor: VendorId
) -> Optional[AutoMapping]:
    """Write the gamepad mapping of a device in the kernel's gamepad
    layout. SDL: `LINUX_JoystickGetGamepadMapping`.

    Args:
        layout: The device's layout.
        vendor: The device's USB vendor id. Sony controllers name their
            west and north buttons by position; Microsoft controllers have
            paddles and a share button.

    Returns:
        The inputs of each control, or None when the device does not have
        `BTN_GAMEPAD` and so is not a gamepad by the kernel's rules.
    """
    if not layout.has_key[BTN_GAMEPAD]:
        return None
    var raw = AutoMapping()
    var direct: List[Int] = [BTN_A, BTN_B]
    var controls: List[GamepadButton] = [BUTTON_SOUTH, BUTTON_EAST]
    if vendor.value == 0x054C:
        direct += [BTN_WEST, BTN_NORTH]
    else:
        direct += [BTN_X, BTN_Y]
    controls += [BUTTON_WEST, BUTTON_NORTH]
    direct += [BTN_SELECT, BTN_START, BTN_THUMBL, BTN_THUMBR, BTN_MODE]
    controls += [
        BUTTON_BACK,
        BUTTON_START,
        BUTTON_LEFT_STICK,
        BUTTON_RIGHT_STICK,
        BUTTON_GUIDE,
    ]
    for index in range(len(direct)):  # pragma: no branch
        if layout.has_key[direct[index]]:
            raw.buttons[controls[index].value] = _button(layout, direct[index])

    # Prefer digital shoulder buttons, but settle for a hat or axes.
    var mapped = 0
    if layout.has_key[BTN_TL]:
        raw.buttons[BUTTON_LEFT_SHOULDER.value] = _button(layout, BTN_TL)
        mapped |= 1
    if layout.has_key[BTN_TR]:
        raw.buttons[BUTTON_RIGHT_SHOULDER.value] = _button(layout, BTN_TR)
        mapped |= 2
    if mapped != 3 and layout.has_hat[1]:
        raw.buttons[BUTTON_LEFT_SHOULDER.value] = _hat(layout, 1, HAT_DOWN)
        raw.buttons[BUTTON_RIGHT_SHOULDER.value] = _hat(layout, 1, HAT_RIGHT)
        mapped = 3
    if (mapped & 1) == 0 and layout.has_abs[ABS_HAT1Y]:
        raw.buttons[BUTTON_LEFT_SHOULDER.value] = _axis(layout, ABS_HAT1Y)
        mapped |= 1
    if (mapped & 2) == 0 and layout.has_abs[ABS_HAT1X]:
        raw.buttons[BUTTON_RIGHT_SHOULDER.value] = _axis(layout, ABS_HAT1X)
        mapped |= 2

    # Prefer analog triggers, but settle for a hat or buttons. The
    # kernel's gamepad layout, Android and older Xbox and PlayStation
    # drivers each put the triggers on different axes.
    mapped = 0
    for code in [ABS_HAT2Y, ABS_BRAKE, ABS_Z]:  # pragma: no branch
        if layout.has_abs[code]:
            raw.axes[AXIS_LEFT_TRIGGER.value] = _axis(layout, code)
            mapped |= 1
            break
    for code in [ABS_HAT2X, ABS_GAS, ABS_RZ]:  # pragma: no branch
        if layout.has_abs[code]:
            raw.axes[AXIS_RIGHT_TRIGGER.value] = _axis(layout, code)
            mapped |= 2
            break
    if mapped != 3 and layout.has_hat[2]:
        raw.axes[AXIS_LEFT_TRIGGER.value] = _hat(layout, 2, HAT_DOWN)
        raw.axes[AXIS_RIGHT_TRIGGER.value] = _hat(layout, 2, HAT_RIGHT)
        mapped = 3
    if (mapped & 1) == 0 and layout.has_key[BTN_TL2]:
        raw.axes[AXIS_LEFT_TRIGGER.value] = _button(layout, BTN_TL2)
        mapped |= 1
    if (mapped & 2) == 0 and layout.has_key[BTN_TR2]:
        raw.axes[AXIS_RIGHT_TRIGGER.value] = _button(layout, BTN_TR2)
        mapped |= 2

    # Prefer digital d-pad buttons, but settle for a hat or axes.
    mapped = 0
    var pad: List[GamepadButton] = [
        BUTTON_DPAD_UP,
        BUTTON_DPAD_DOWN,
        BUTTON_DPAD_LEFT,
        BUTTON_DPAD_RIGHT,
    ]
    for index in range(4):
        if layout.has_key[BTN_DPAD_UP + index]:
            raw.buttons[pad[index].value] = _button(layout, BTN_DPAD_UP + index)
            mapped |= 1 << index
    if mapped != 0xF:
        if layout.has_hat[0]:
            var bits: List[Int] = [HAT_UP, HAT_DOWN, HAT_LEFT, HAT_RIGHT]
            for index in range(4):
                raw.buttons[pad[index].value] = _hat(layout, 0, bits[index])
        elif layout.has_abs[ABS_HAT0X] and layout.has_abs[ABS_HAT0Y]:
            # SDL binds each direction to the whole axis, so all four read
            # as pressed at rest. This port binds each to its half.
            raw.buttons[BUTTON_DPAD_UP.value] = _half_axis(
                layout, ABS_HAT0Y, False
            )
            raw.buttons[BUTTON_DPAD_DOWN.value] = _half_axis(
                layout, ABS_HAT0Y, True
            )
            raw.buttons[BUTTON_DPAD_LEFT.value] = _half_axis(
                layout, ABS_HAT0X, False
            )
            raw.buttons[BUTTON_DPAD_RIGHT.value] = _half_axis(
                layout, ABS_HAT0X, True
            )

    if layout.has_abs[ABS_X] and layout.has_abs[ABS_Y]:
        raw.axes[AXIS_LEFTX.value] = _axis(layout, ABS_X)
        raw.axes[AXIS_LEFTY.value] = _axis(layout, ABS_Y)
    # The kernel's layout puts the right stick on RX and RY. Android's
    # puts it on Z and RZ.
    if layout.has_abs[ABS_RX] and layout.has_abs[ABS_RY]:
        raw.axes[AXIS_RIGHTX.value] = _axis(layout, ABS_RX)
        raw.axes[AXIS_RIGHTY.value] = _axis(layout, ABS_RY)
    elif layout.has_abs[ABS_Z] and layout.has_abs[ABS_RZ]:
        raw.axes[AXIS_RIGHTX.value] = _axis(layout, ABS_Z)
        raw.axes[AXIS_RIGHTY.value] = _axis(layout, ABS_RZ)

    if vendor.value == 0x045E:
        # The Xbox Elite paddles are BTN_TRIGGER_HAPPY5 to 8.
        var happy = BTN_TRIGGER_HAPPY
        if (
            layout.has_key[happy + 4]
            and layout.has_key[happy + 5]
            and layout.has_key[happy + 6]
            and layout.has_key[happy + 7]
        ):
            raw.buttons[BUTTON_RIGHT_PADDLE1.value] = _button(layout, happy + 4)
            raw.buttons[BUTTON_LEFT_PADDLE1.value] = _button(layout, happy + 6)
            raw.buttons[BUTTON_RIGHT_PADDLE2.value] = _button(layout, happy + 5)
            raw.buttons[BUTTON_LEFT_PADDLE2.value] = _button(layout, happy + 7)
        # The Xbox Series X share button is KEY_RECORD.
        if layout.has_key[KEY_RECORD]:
            raw.buttons[BUTTON_MISC1.value] = _button(layout, KEY_RECORD)
    return raw^


struct SensorLayout(ImplicitlyCopyable):
    """Which motion sensors a sensor device has, and their scales. SDL: the
    sensor part of `ConfigJoystick`."""

    var has_accelerometer: Bool
    var has_gyro: Bool
    # Counts per unit, from each axis's resolution.
    var accelerometer_scale: SIMD[DType.float32, 4]
    var gyro_scale: SIMD[DType.float32, 4]

    def __init__(out self):
        """Create a layout with no sensors."""
        self.has_accelerometer = False
        self.has_gyro = False
        self.accelerometer_scale = SIMD[DType.float32, 4](0)
        self.gyro_scale = SIMD[DType.float32, 4](0)

    def configure(
        mut self, absolutes: List[UInt8], absinfo: List[Optional[AbsInfo]]
    ):
        """Find the sensors of a sensor device. SDL: the sensor part of
        `ConfigJoystick`.

        A sensor needs all three axes, and the range of each.

        Args:
            absolutes: The sensor device's absolute axis bitmap.
            absinfo: The range of each axis, by code, or None.
        """
        if (
            test_bit(absolutes, ABS_X)
            and test_bit(absolutes, ABS_Y)
            and test_bit(absolutes, ABS_Z)
        ):
            self.has_accelerometer = True
            for axis in range(3):  # pragma: no branch
                if not absinfo[ABS_X + axis]:
                    self.has_accelerometer = False
                    break
                self.accelerometer_scale[axis] = Float32(
                    absinfo[ABS_X + axis].value().resolution
                )
        if (
            test_bit(absolutes, ABS_RX)
            and test_bit(absolutes, ABS_RY)
            and test_bit(absolutes, ABS_RZ)
        ):
            self.has_gyro = True
            for axis in range(3):  # pragma: no branch
                if not absinfo[ABS_RX + axis]:
                    self.has_gyro = False
                    break
                self.gyro_scale[axis] = Float32(
                    absinfo[ABS_RX + axis].value().resolution
                )

    def accelerometer(self, axis: Int, value: Int) -> Float32:
        """Scale a raw accelerometer value. SDL:
        `value * SDL_STANDARD_GRAVITY / accelerometer_scale`.

        Args:
            axis: 0 for X, 1 for Y, 2 for Z.
            value: The raw value.

        Returns:
            The acceleration, in meters per second squared.
        """
        return (
            Float32(value) * STANDARD_GRAVITY / self.accelerometer_scale[axis]
        )

    def gyro(self, axis: Int, value: Int) -> Float32:
        """Scale a raw gyroscope value. SDL:
        `value * (SDL_PI_F / 180) / gyro_scale`.

        Args:
            axis: 0 for X, 1 for Y, 2 for Z.
            value: The raw value, in counts per degree per second.

        Returns:
            The turn rate, in radians per second.
        """
        return (
            Float32(value)
            * (Float32(3.14159265358979323846264338327950288) / 180)
            / self.gyro_scale[axis]
        )


struct SensorState(ImplicitlyCopyable):
    """What SDL tracks while it reads a sensor device. SDL: the sensor
    fields of `struct joystick_hwdata`."""

    var layout: SensorLayout
    var accel_data: SIMD[DType.float32, SENSOR_VALUES]
    var gyro_data: SIMD[DType.float32, SENSOR_VALUES]
    # The sensor clock, in microseconds, and its last raw value.
    var sensor_tick: Int
    var last_tick: Int
    var recovering_from_dropped: Bool

    def __init__(out self, layout: SensorLayout):
        """Create the state of a sensor device that has not been read.

        Args:
            layout: The device's sensors.
        """
        self.layout = layout
        self.accel_data = SIMD[DType.float32, SENSOR_VALUES](0)
        self.gyro_data = SIMD[DType.float32, SENSOR_VALUES](0)
        self.sensor_tick = 0
        self.last_tick = 0
        self.recovering_from_dropped = False

    def timestamp(self) -> Duration64:
        """Return the sensor clock.

        Returns:
            The time the sensor reported, by its own clock.
        """
        return Duration64(Float64(self.sensor_tick) * 1e-6, SECOND)

    def handle_event(
        mut self, mut joystick: Joystick, event: EvdevEvent
    ) -> Bool:
        """Apply one event of the sensor device. SDL: the sensor loop of
        `HandleInputEvents`.

        A report sends the gyroscope, then the accelerometer.

        Args:
            joystick: The joystick to update.
            event: The event.

        Returns:
            True when the sensors must be read again, after a report that
            followed dropped events.
        """
        var code = event.code
        if self.recovering_from_dropped and (
            event.type != EV_SYN or code != SYN_REPORT
        ):
            return False
        if event.type == EV_ABS:
            # ABS_X is 0, so a code is never below it.
            if code <= ABS_Z:
                self.accel_data[code - ABS_X] = self.layout.accelerometer(
                    code - ABS_X, event.value
                )
            # ABS_RX follows ABS_Z, so no code falls between them.
            elif code <= ABS_RZ:
                self.gyro_data[code - ABS_RX] = self.layout.gyro(
                    code - ABS_RX, event.value
                )
        elif event.type == EV_MSC:
            if code == MSC_TIMESTAMP:
                var tick = event.value
                var delta: Int
                if self.last_tick < tick:
                    delta = tick - self.last_tick
                else:
                    delta = 0x7FFFFFFF - self.last_tick + tick + 1
                self.sensor_tick += delta
                self.last_tick = tick
        elif event.type == EV_SYN:
            if code == SYN_DROPPED:
                self.recovering_from_dropped = True
            elif code == SYN_REPORT:
                if self.recovering_from_dropped:
                    self.recovering_from_dropped = False
                    return True
                joystick.send_sensor(
                    SENSOR_GYRO, self.timestamp(), self.gyro_data
                )
                joystick.send_sensor(
                    SENSOR_ACCEL, self.timestamp(), self.accel_data
                )
        return False

    def apply_state(
        mut self, mut joystick: Joystick, absinfo: List[Optional[AbsInfo]]
    ):
        """Send the whole sensor state read from the device. SDL:
        `PollAllSensors`.

        An axis the device does not describe reads 0.

        Args:
            joystick: The joystick to update.
            absinfo: Each axis's range and value, by code, or None.
        """
        if self.layout.has_gyro:
            var data = SIMD[DType.float32, SENSOR_VALUES](0)
            for axis in range(3):  # pragma: no branch
                if absinfo[ABS_RX + axis]:
                    data[axis] = self.layout.gyro(
                        axis, absinfo[ABS_RX + axis].value().value
                    )
            joystick.send_sensor(SENSOR_GYRO, self.timestamp(), data)
        if self.layout.has_accelerometer:
            var data = SIMD[DType.float32, SENSOR_VALUES](0)
            for axis in range(3):  # pragma: no branch
                if absinfo[ABS_X + axis]:
                    data[axis] = self.layout.accelerometer(
                        axis, absinfo[ABS_X + axis].value().value
                    )
            joystick.send_sensor(SENSOR_ACCEL, self.timestamp(), data)


def _put16(mut bytes: List[UInt8], offset: Int, value: Int):
    """Write a little-endian 16-bit integer.

    Args:
        bytes: The bytes.
        offset: Where it starts.
        value: The value. Only its low 16 bits are kept.
    """
    bytes[offset] = UInt8(value & 0xFF)
    bytes[offset + 1] = UInt8((value >> 8) & 0xFF)


def encode_ff_effect(
    rumble: Bool, id: Int, low: Int, high: Int, length_ms: Int
) -> List[UInt8]:
    """Write the force feedback effect SDL uploads. SDL: the effect of
    `LINUX_JoystickRumble`. Linux: `struct ff_effect`.

    A pad with `FF_RUMBLE` gets the two strengths. A pad with only
    `FF_SINE` gets a sine wave with their average.

    Args:
        rumble: Whether the pad has `FF_RUMBLE`. False uses `FF_SINE`.
        id: The effect id the kernel gave, or -1 for a new effect.
        low: The low frequency strength, 0 to 65535.
        high: The high frequency strength, 0 to 65535.
        length_ms: How long the effect plays, in milliseconds.

    Returns:
        The 48 bytes of the effect.
    """
    var bytes = List[UInt8](length=FF_EFFECT_SIZE, fill=0)
    _put16(bytes, 2, id)
    # The replay length is at offset 10, after the trigger.
    _put16(bytes, 10, length_ms)
    if rumble:
        _put16(bytes, 0, FF_RUMBLE)
        _put16(bytes, 16, low)
        _put16(bytes, 18, high)
    else:
        _put16(bytes, 0, FF_PERIODIC)
        _put16(bytes, 16, FF_SINE)
        # SDL: `(Sint16)(((low / 2) + (high / 2)) / 2)`.
        _put16(bytes, 20, ((low // 2) + (high // 2)) // 2)
    return bytes^


def ff_effect_id(bytes: List[UInt8]) -> Int:
    """Read the id the kernel wrote into an uploaded effect.

    Args:
        bytes: The effect's bytes.

    Returns:
        The id, as a signed 16-bit value.
    """
    var value = _read_uint16(bytes, 2)
    return value - 0x10000 if value >= 0x8000 else value
