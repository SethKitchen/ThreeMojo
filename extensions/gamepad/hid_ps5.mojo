# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of src/joystick/hidapi/SDL_hidapi_ps5.c,
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

"""The DualSense driver. SDL: `SDL_hidapi_ps5.c`.

The driver runs Sony's DualSense and DualSense Edge, and the controllers
of other companies that answer Sony's capability report as a DualSense
does. It reads the simple report that a Bluetooth pad sends before it
gets an effects report, and the full report with the touchpad and the
motion sensors. It sends the light bar color, the player lights and the
rumble in effects reports. A Bluetooth report carries a CRC-32.

A gyroscope reading is in radians per second and an accelerometer
reading in meters per second squared, as SDL gives them. The sensor
clock counts in microseconds on a third-party pad and in thirds of a
microsecond on a DualSense.

The port keeps SDL's default hints: enhanced reports on and player
lights on. Because the enhanced reports hint is on, the driver enters
enhanced mode when the joystick opens. These parts of SDL are not
ported:

- The hint callbacks, and the hint's "auto" mode, in which a program's
  first effect or sensor call turns on enhanced mode.
- `SendJoystickEffect`, the raw effects call.
- The microphone light, which no SDL call asks for.
- The battery level, the firmware version and the joystick type of a
  third-party pad (guitar, drum kit, wheel), which the joystick here does
  not keep.
- The merge of an effects report with one that waits in SDL's rumble
  thread. Here a report is written at once.

SDL reads a Bluetooth report's CRC from the last 4 bytes without a check
of the length, so a report shorter than 4 bytes reads before the buffer.
This port drops such a report.
"""
from extensions.gamepad.gamepad import Gamepad
from extensions.gamepad.guid import ProductId, VendorId
from extensions.gamepad.hid import HidSource
from extensions.gamepad.hid_device import (
    CAP_PLAYER_LED,
    CAP_RGB_LED,
    CAP_RUMBLE,
    HidapiDevice,
    USB_PACKET_LENGTH,
    USB_VENDOR_NACON_ALT,
    USB_VENDOR_RAZER,
    load16,
    load32,
    supports_playstation_detection,
)
from extensions.gamepad.ids import (
    AXIS_COUNT,
    GAMEPAD_TYPE_PS5,
    GamepadType,
    JOYSTICK_AXIS_MAX,
)
from extensions.gamepad.joystick import (
    Joystick,
    SENSOR_ACCEL,
    SENSOR_GYRO,
    SENSOR_VALUES,
)
from extensions.gamepad.mapping import HAT_DOWN, HAT_LEFT, HAT_RIGHT, HAT_UP
from units.si import Duration64, Frequency, PER_SECOND, SECOND

comptime USB_VENDOR_SONY = 0x054C
comptime USB_PRODUCT_SONY_DS5_EDGE = 0x0DF2
comptime USB_PRODUCT_NACON_REVOLUTION_5_PRO_PS5_WIRELESS = 0x0D18
comptime USB_PRODUCT_NACON_REVOLUTION_5_PRO_PS5_WIRED = 0x0D19
comptime USB_PRODUCT_RAZER_KITSUNE = 0x1012
comptime USB_PRODUCT_RAZER_WOLVERINE_V2_PRO_PS5_WIRED = 0x100B
comptime USB_PRODUCT_RAZER_WOLVERINE_V2_PRO_PS5_WIRELESS = 0x100C

comptime GYRO_RES_PER_DEGREE = Float32(1024.0)
comptime ACCEL_RES_PER_G = Float32(8192.0)
# SDL: `SDL_PI_F` and `SDL_STANDARD_GRAVITY`.
comptime PI_F = Float32(3.141592653589793)
comptime STANDARD_GRAVITY = Float32(9.80665)
# How long a Bluetooth pad may be silent, in milliseconds.
comptime BLUETOOTH_DISCONNECT_TIMEOUT_MS = 500
# The touchpad is 1920 by 1070.
comptime TOUCHPAD_SCALEX = Float32(5.20833333e-4)
comptime TOUCHPAD_SCALEY = Float32(9.34579439e-4)
# The sensor clock when the Bluetooth light animation is over.
comptime CONNECTION_COMPLETE = 10200000

# The buttons after the 11 standard ones. SDL: `SDL_GAMEPAD_BUTTON_PS5_*`.
comptime BUTTON_PS5_TOUCHPAD = 11
comptime BUTTON_PS5_MICROPHONE = 12
comptime BUTTON_PS5_LEFT_FUNCTION = 13
comptime BUTTON_PS5_RIGHT_FUNCTION = 14
comptime BUTTON_PS5_LEFT_PADDLE = 15
comptime BUTTON_PS5_RIGHT_PADDLE = 16

# The joystick's buttons and axes. SDL: `SDL_GAMEPAD_BUTTON_*`.
comptime BUTTON_SOUTH = 0
comptime BUTTON_EAST = 1
comptime BUTTON_WEST = 2
comptime BUTTON_NORTH = 3
comptime BUTTON_BACK = 4
comptime BUTTON_GUIDE = 5
comptime BUTTON_START = 6
comptime BUTTON_LEFT_STICK = 7
comptime BUTTON_RIGHT_STICK = 8
comptime BUTTON_LEFT_SHOULDER = 9
comptime BUTTON_RIGHT_SHOULDER = 10
comptime AXIS_LEFTX = 0
comptime AXIS_LEFTY = 1
comptime AXIS_RIGHTX = 2
comptime AXIS_RIGHTY = 3
comptime AXIS_LEFT_TRIGGER = 4
comptime AXIS_RIGHT_TRIGGER = 5

# Report ids. SDL: `EPS5ReportId` and `EPS5FeatureReportId`.
comptime REPORT_STATE = 0x01
comptime REPORT_USB_EFFECTS = 0x02
comptime REPORT_BLUETOOTH_EFFECTS = 0x31
comptime REPORT_BLUETOOTH_STATE = 0x31
comptime FEATURE_CAPABILITIES = 0x03
comptime FEATURE_CALIBRATION = 0x05
comptime FEATURE_SERIAL_NUMBER = 0x09
comptime FEATURE_FIRMWARE_INFO = 0x20

# The parts of an effects report. SDL: `EDS5Effect`.
comptime EFFECT_RUMBLE_START = 1 << 0
comptime EFFECT_RUMBLE = 1 << 1
comptime EFFECT_LED_RESET = 1 << 2
comptime EFFECT_LED = 1 << 3
comptime EFFECT_PAD_LIGHTS = 1 << 4

# Where the Bluetooth light reset is. SDL: `EDS5LEDResetState`.
comptime LED_RESET_NONE = 0
comptime LED_RESET_PENDING = 1
comptime LED_RESET_COMPLETE = 2

# The bytes of `DS5EffectsState_t`.
comptime EFFECTS_SIZE = 47
comptime EFFECT_ENABLE_BITS1 = 0
comptime EFFECT_ENABLE_BITS2 = 1
comptime EFFECT_RUMBLE_RIGHT = 2
comptime EFFECT_RUMBLE_LEFT = 3
comptime EFFECT_ENABLE_BITS3 = 38
comptime EFFECT_PAD_LIGHTS_BYTE = 43
comptime EFFECT_LED_RED = 44
comptime EFFECT_LED_GREEN = 45
comptime EFFECT_LED_BLUE = 46

# The bytes of the state packets after the report id. SDL:
# `PS5SimpleStatePacket_t`, `PS5StatePacketCommon_t`, `PS5StatePacket_t`
# and `PS5StatePacketAlt_t`, which share `last_state`.
comptime STATE_SIZE = 64
comptime SIMPLE_SIZE = 9
comptime SIMPLE_BUTTONS = 4
comptime SIMPLE_TRIGGER_LEFT = 7
comptime SIMPLE_TRIGGER_RIGHT = 8
comptime TRIGGER_LEFT = 4
comptime TRIGGER_RIGHT = 5
comptime BUTTONS = 7
comptime PACKET_SEQUENCE = 11
comptime GYRO = 15
comptime ACCEL = 21
comptime SENSOR_TIMESTAMP = 27
comptime TOUCHPAD1 = 32
comptime TOUCHPAD2 = 36
comptime ALT_SIZE = 39
comptime ALT_TOUCHPAD1 = 31
comptime ALT_TOUCHPAD2 = 35


def _wrap16(value: Int) -> Int:
    """Convert to a signed 16-bit number, as a C `Sint16` store does.

    Args:
        value: The number.

    Returns:
        The number modulo 65536, from -32768 to 32767.
    """
    var low = value & 0xFFFF
    return low - 0x10000 if low >= 0x8000 else low


def _half(value: Int) -> Int:
    """Halve a number toward zero, as C's `/ 2` does.

    Args:
        value: The number.

    Returns:
        The half, without its fraction.
    """
    return -((-value) // 2) if value < 0 else value // 2


def _milliseconds(time: Duration64) -> Int:
    """Return a time in whole milliseconds. SDL: `SDL_GetTicks`.

    Args:
        time: The time.

    Returns:
        The milliseconds, rounded down after rounding to a microsecond.
    """
    return Int(time.to(SECOND) * 1e6 + 0.5) // 1000


def crc32(crc: UInt32, data: List[UInt8], count: Int) -> UInt32:
    """Continue a CRC-32 over some bytes. SDL: `SDL_crc32`.

    Args:
        crc: The CRC so far, or 0.
        data: The bytes.
        count: How many of the first bytes to add.

    Returns:
        The CRC with the bytes added.
    """
    var value = crc
    for index in range(count):
        var r = UInt32(UInt8(value & 0xFF) ^ data[index])
        for _ in range(8):
            r = (UInt32(0) if r & 1 else UInt32(0xEDB88320)) ^ (r >> 1)
        value = (r ^ UInt32(0xFF000000)) ^ (value >> 8)
    return value


def _read_feature_report[
    S: HidSource
](mut source: S, report_id: Int, mut report: List[UInt8], length: Int) -> Int:
    """Read a feature report into a cleared buffer. SDL:
    `ReadFeatureReport`.

    Parameters:
        S: The kind of HID device.

    Args:
        source: The open device.
        report_id: The report id.
        report: The buffer, which this call sizes.
        length: The most to read.

    Returns:
        The bytes read, or -1 on an error.
    """
    report = List[UInt8](length=length, fill=0)
    report[0] = UInt8(report_id)
    return source.get_feature_report(report)


def _hat(data: Int) -> Int:
    """Return the hat bits for the d-pad's direction code.

    Args:
        data: The low 4 bits of the buttons byte.

    Returns:
        The hat bits. Codes past 7 are centered.
    """
    if data == 0:
        return HAT_UP
    if data == 1:
        return HAT_RIGHT | HAT_UP
    if data == 2:
        return HAT_RIGHT
    if data == 3:
        return HAT_RIGHT | HAT_DOWN
    if data == 4:
        return HAT_DOWN
    if data == 5:
        return HAT_LEFT | HAT_DOWN
    if data == 6:
        return HAT_LEFT
    if data == 7:
        return HAT_LEFT | HAT_UP
    return 0


def _stick(value: UInt8) -> Int:
    """Scale a stick or trigger byte to an axis value.

    Args:
        value: The byte.

    Returns:
        The axis value, from -32768 to 32767.
    """
    return Int(value) * 257 - 32768


def _set_leds_for_player_index(mut effects: List[UInt8], player_index: Int):
    """Set the light bar to a player's color. SDL:
    `SetLedsForPlayerIndex`.

    Args:
        effects: The effects state.
        player_index: The player, or -1 for the first color.
    """
    # The same colors as the Linux hid-sony driver: blue, red, green,
    # pink, orange, teal and white.
    var colors: List[Int] = [
        0x000040,
        0x400000,
        0x004000,
        0x200020,
        0x201000,
        0x001010,
        0x101010,
    ]
    var index = player_index % 7 if player_index >= 0 else 0
    effects[EFFECT_LED_RED] = UInt8((colors[index] >> 16) & 0xFF)
    effects[EFFECT_LED_GREEN] = UInt8((colors[index] >> 8) & 0xFF)
    effects[EFFECT_LED_BLUE] = UInt8(colors[index] & 0xFF)


def _set_lights_for_player_index(mut effects: List[UInt8], player_index: Int):
    """Set the player lights under the touchpad. SDL:
    `SetLightsForPlayerIndex`.

    Args:
        effects: The effects state.
        player_index: The player, or -1 for none.
    """
    var lights: List[Int] = [0x04, 0x0A, 0x15, 0x1B, 0x1F]
    if player_index >= 0:
        # 0x20 changes the lights at once instead of fading.
        effects[EFFECT_PAD_LIGHTS_BYTE] = UInt8(lights[player_index % 5] | 0x20)
    else:
        effects[EFFECT_PAD_LIGHTS_BYTE] = 0


struct Ps5Driver(Movable):
    """The DualSense driver's state. SDL: `SDL_DriverPS5_Context`."""

    # Whether the joystick is open. SDL: `joystick != NULL`.
    var joystick_open: Bool
    var is_nacon_dongle: Bool
    var use_alternate_report: Bool
    var sensors_supported: Bool
    var lightbar_supported: Bool
    var vibration_supported: Bool
    var playerled_supported: Bool
    var touchpad_supported: Bool
    var effects_supported: Bool
    var enhanced_reports: Bool
    # Whether the pad is in enhanced mode. With the enhanced reports hint
    # on, this is SDL's `enhanced_mode` and `enhanced_mode_available`.
    var enhanced_mode: Bool
    var report_sensors: Bool
    var report_touchpad: Bool
    var hardware_calibration: Bool
    # The gyroscope's pitch, yaw and roll, then the accelerometer's X, Y
    # and Z.
    var calibration_bias: List[Int]
    var calibration_sensitivity: List[Float32]
    var firmware_version: Int
    var last_packet: Duration64
    var player_index: Int
    # The player number the joystick has, which the open joystick takes.
    var assigned_player_index: Int
    var enhanced_rumble: Bool
    var rumble_left: Int
    var rumble_right: Int
    var color_set: Bool
    var led_red: Int
    var led_green: Int
    var led_blue: Int
    var led_reset_state: Int
    # The sensor clock, in its own ticks, and its last raw value.
    var sensor_ticks: Int
    var last_tick: Int
    var last_state: List[UInt8]

    def __init__(out self):
        """Create the state of a device the driver has not seen."""
        self.joystick_open = False
        self.is_nacon_dongle = False
        self.use_alternate_report = False
        self.sensors_supported = False
        self.lightbar_supported = False
        self.vibration_supported = False
        self.playerled_supported = False
        self.touchpad_supported = False
        self.effects_supported = False
        self.enhanced_reports = False
        self.enhanced_mode = False
        self.report_sensors = False
        self.report_touchpad = False
        self.hardware_calibration = False
        self.calibration_bias = List[Int](length=6, fill=0)
        self.calibration_sensitivity = List[Float32](length=6, fill=0)
        self.firmware_version = 0
        self.last_packet = Duration64(0)
        self.player_index = 0
        self.assigned_player_index = -1
        self.enhanced_rumble = False
        self.rumble_left = 0
        self.rumble_right = 0
        self.color_set = False
        self.led_red = 0
        self.led_green = 0
        self.led_blue = 0
        self.led_reset_state = LED_RESET_NONE
        self.sensor_ticks = 0
        self.last_tick = 0
        self.last_state = List[UInt8](length=STATE_SIZE, fill=0)

    @staticmethod
    def is_supported(
        name: String,
        type: GamepadType,
        vendor: VendorId,
        product: ProductId,
        version: Int,
        interface_number: Int,
    ) -> Bool:
        """Return True if the driver may run a device. SDL:
        `IsSupportedDevice` with no open device.

        Args:
            name: The device's name.
            type: The device's gamepad type.
            vendor: The USB vendor id.
            product: The USB product id.
            version: The release number.
            interface_number: The USB interface, or -1.

        Returns:
            Whether the device is a DualSense, or may be one made by
            another company.
        """
        if type == GAMEPAD_TYPE_PS5:
            return True
        return supports_playstation_detection(vendor, product)

    @staticmethod
    def is_supported_device[
        S: HidSource
    ](mut source: S, device: HidapiDevice) -> Bool:
        """Return True if the driver runs an open device. SDL:
        `IsSupportedDevice` with the device open.

        A device that only may be a DualSense must answer the capability
        report as one.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            device: What is known about it.

        Returns:
            Whether the driver runs it.
        """
        if device.type == GAMEPAD_TYPE_PS5:
            return True
        if supports_playstation_detection(device.vendor, device.product):
            var data = List[UInt8]()
            var size = _read_feature_report(
                source, FEATURE_CAPABILITIES, data, USB_PACKET_LENGTH
            )
            return size == 48 and data[2] == 0x28
        return False

    def init_device[
        S: HidSource
    ](
        mut self, mut device: HidapiDevice, mut source: S, now: Duration64
    ) -> Bool:
        """Start the driver on a device. SDL: `InitDevice`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            now: The time now.

        Returns:
            Whether the driver runs the device.
        """
        var serial = String()
        if device.serial.byte_length() == 12:
            # "aabbccddeeff" becomes "aa-bb-cc-dd-ee-ff".
            for index in range(0, 12, 2):  # pragma: no branch
                if index > 0:
                    serial += "-"
                serial += String(device.serial[byte = index : index + 2])
        # Read a report to see what mode the pad is in.
        var data = List[UInt8](length=USB_PACKET_LENGTH * 2, fill=0)
        var size = source.read(data, 16)
        if size == 64:
            # USB.
            self.enhanced_reports = True
        elif size > 0 and data[0] == REPORT_BLUETOOTH_EFFECTS:
            # Bluetooth, with enhanced reports.
            self.enhanced_reports = True
        var vendor = device.vendor.value
        var product = device.product.value
        if vendor == USB_VENDOR_SONY and self.enhanced_reports:
            # The serial number is the Bluetooth address, last byte first.
            # Both reads also turn on enhanced reports over Bluetooth.
            if (
                _read_feature_report(
                    source, FEATURE_SERIAL_NUMBER, data, USB_PACKET_LENGTH * 2
                )
                >= 7
            ):
                comptime DIGITS = "0123456789abcdef"
                serial = String()
                for index in range(6, 0, -1):  # pragma: no branch
                    if index < 6:
                        serial += "-"
                    serial += DIGITS[byte=Int(data[index] >> 4)]
                    serial += DIGITS[byte=Int(data[index] & 15)]
            if (
                _read_feature_report(
                    source, FEATURE_FIRMWARE_INFO, data, USB_PACKET_LENGTH
                )
                >= 46
            ):
                self.firmware_version = Int(data[44]) | (Int(data[45]) << 8)
        if vendor == USB_VENDOR_SONY:
            # Firmware 0 is a Bluetooth pad, which is assumed up to date.
            if (
                product == USB_PRODUCT_SONY_DS5_EDGE
                or self.firmware_version == 0
                or self.firmware_version >= 0x0224
            ):
                self.enhanced_rumble = True
            self.sensors_supported = True
            self.lightbar_supported = True
            self.vibration_supported = True
            self.playerled_supported = True
            self.touchpad_supported = True
        else:
            # Ask a third-party pad what it has.
            size = _read_feature_report(
                source, FEATURE_CAPABILITIES, data, USB_PACKET_LENGTH * 2
            )
            if size == 48 and data[2] == 0x28:
                var capabilities = Int(data[4])
                var capabilities2 = Int(data[20])
                self.sensors_supported = capabilities & 0x02 != 0
                self.lightbar_supported = capabilities & 0x04 != 0
                self.vibration_supported = capabilities & 0x08 != 0
                self.touchpad_supported = capabilities & 0x40 != 0
                self.playerled_supported = capabilities2 & 0x80 != 0
                self.use_alternate_report = True
                if vendor == USB_VENDOR_NACON_ALT and (
                    product == USB_PRODUCT_NACON_REVOLUTION_5_PRO_PS5_WIRED
                    or product
                    == USB_PRODUCT_NACON_REVOLUTION_5_PRO_PS5_WIRELESS
                ):
                    # It rumbles, though it does not say so.
                    self.vibration_supported = True
            elif vendor == USB_VENDOR_RAZER and (
                product == USB_PRODUCT_RAZER_WOLVERINE_V2_PRO_PS5_WIRED
                or product == USB_PRODUCT_RAZER_WOLVERINE_V2_PRO_PS5_WIRELESS
            ):
                # It does not answer, but has a touchpad and sensors.
                self.sensors_supported = True
                self.touchpad_supported = True
                self.use_alternate_report = True
            elif (
                vendor == USB_VENDOR_RAZER
                and product == USB_PRODUCT_RAZER_KITSUNE
            ):
                # It does not answer, but has a touchpad.
                self.touchpad_supported = True
                self.use_alternate_report = True
        self.effects_supported = (
            self.lightbar_supported
            or self.vibration_supported
            or self.playerled_supported
        )
        if (
            vendor == USB_VENDOR_NACON_ALT
            and product == USB_PRODUCT_NACON_REVOLUTION_5_PRO_PS5_WIRELESS
        ):
            self.is_nacon_dongle = True
        device.type = GAMEPAD_TYPE_PS5
        if vendor == USB_VENDOR_SONY:
            if product == USB_PRODUCT_SONY_DS5_EDGE:
                device.set_name("DualSense Edge Wireless Controller")
            else:
                device.set_name("DualSense Wireless Controller")
        device.set_serial(serial)
        if self.is_nacon_dongle:
            # The pad may not be on yet: wait for its reports.
            return True
        # A pad on USB wins over the same pad on Bluetooth.
        if device.is_bluetooth:
            if device.has_connected_usb_device(device.serial):
                return True
        else:
            var own = device.serial
            device.disconnect_bluetooth_device(own)
        return device.joystick_connected()

    def set_player_index[
        S: HidSource
    ](mut self, mut device: HidapiDevice, mut source: S, player_index: Int):
        """Show a player number. SDL: `SetDevicePlayerIndex`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            player_index: The player, from 0, or -1 for none.
        """
        self.assigned_player_index = player_index
        if not self.joystick_open:
            return
        self.player_index = player_index
        _ = self._update_effects(device, source, EFFECT_LED | EFFECT_PAD_LIGHTS)

    def _load_calibration_data[S: HidSource](mut self, mut source: S):
        """Read the motion sensors' calibration. SDL:
        `LoadCalibrationData`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
        """
        var data = List[UInt8]()
        var size = _read_feature_report(
            source, FEATURE_CALIBRATION, data, USB_PACKET_LENGTH
        )
        if size < 35:
            return
        var numerator = Float32(load16(data, 19) + load16(data, 21)) * (
            GYRO_RES_PER_DEGREE
        )
        for axis in range(3):  # pragma: no branch
            self.calibration_bias[axis] = load16(data, 1 + 2 * axis)
            var plus = load16(data, 7 + 4 * axis)
            var minus = load16(data, 9 + 4 * axis)
            self.calibration_sensitivity[axis] = numerator / Float32(
                plus - minus
            )
        for axis in range(3):  # pragma: no branch
            var plus = load16(data, 23 + 4 * axis)
            var minus = load16(data, 25 + 4 * axis)
            var range_2g = _wrap16(plus - minus)
            self.calibration_bias[3 + axis] = _wrap16(plus - _half(range_2g))
            self.calibration_sensitivity[3 + axis] = (
                Float32(2.0) * ACCEL_RES_PER_G / Float32(range_2g)
            )
        self.hardware_calibration = True
        for index in range(6):  # pragma: no branch
            var divisor = Float32(64.0) if index < 3 else Float32(1.0)
            # Some pads have a bad calibration.
            var bias = self.calibration_bias[index]
            if (bias if bias >= 0 else -bias) > 1024 or abs(
                Float32(1.0) - self.calibration_sensitivity[index] / divisor
            ) > Float32(0.5):
                self.hardware_calibration = False

    def _apply_calibration(self, index: Int, value: Int) -> Float32:
        """Convert a raw sensor value. SDL: `ApplyCalibrationData`.

        Args:
            index: The axis: 0 to 2 for the gyroscope, 3 to 5 for the
                accelerometer.
            value: The raw value.

        Returns:
            Radians per second for the gyroscope, meters per second
            squared for the accelerometer.
        """
        var result: Float32
        if self.hardware_calibration:
            result = (
                Float32(value - self.calibration_bias[index])
                * self.calibration_sensitivity[index]
            )
        elif index < 3:
            result = Float32(value) * Float32(64.0)
        else:
            result = Float32(value)
        if index < 3:
            return (result / GYRO_RES_PER_DEGREE) * PI_F / Float32(180.0)
        return (result / ACCEL_RES_PER_G) * STANDARD_GRAVITY

    def _update_effects[
        S: HidSource
    ](mut self, device: HidapiDevice, mut source: S, effect_mask: Int,) -> Bool:
        """Send the effects state. SDL: `UpdateEffects`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            effect_mask: The `EFFECT_*` parts to change.

        Returns:
            Whether the report went out, or waits for the Bluetooth light
            reset.
        """
        # Let the Bluetooth connection finish before a light changes.
        if (
            device.is_bluetooth
            and self.enhanced_reports
            and effect_mask & (EFFECT_LED | EFFECT_PAD_LIGHTS) != 0
        ):
            if self.led_reset_state != LED_RESET_COMPLETE:
                self.led_reset_state = LED_RESET_PENDING
                return True
        var effects = List[UInt8](length=EFFECTS_SIZE, fill=0)
        if self.vibration_supported:
            if self.rumble_left != 0 or self.rumble_right != 0:
                if self.enhanced_rumble:
                    # Firmware 2.24 and later emulate rumble better.
                    effects[EFFECT_ENABLE_BITS3] |= 0x04
                    effects[EFFECT_RUMBLE_LEFT] = UInt8(self.rumble_left)
                    effects[EFFECT_RUMBLE_RIGHT] = UInt8(self.rumble_right)
                else:
                    effects[EFFECT_ENABLE_BITS1] |= 0x01
                    # Half strength, to match Xbox controllers.
                    effects[EFFECT_RUMBLE_LEFT] = UInt8(self.rumble_left >> 1)
                    effects[EFFECT_RUMBLE_RIGHT] = UInt8(self.rumble_right >> 1)
                # Turn off the audio haptics.
                effects[EFFECT_ENABLE_BITS1] |= 0x02
            if effect_mask & EFFECT_RUMBLE_START != 0:
                effects[EFFECT_ENABLE_BITS1] |= 0x02
        if self.lightbar_supported:
            if effect_mask & EFFECT_LED_RESET != 0:
                effects[EFFECT_ENABLE_BITS2] |= 0x08
            if effect_mask & EFFECT_LED != 0:
                effects[EFFECT_ENABLE_BITS2] |= 0x04
                if self.color_set:
                    effects[EFFECT_LED_RED] = UInt8(self.led_red)
                    effects[EFFECT_LED_GREEN] = UInt8(self.led_green)
                    effects[EFFECT_LED_BLUE] = UInt8(self.led_blue)
                else:
                    _set_leds_for_player_index(effects, self.player_index)
        if self.playerled_supported:
            if effect_mask & EFFECT_PAD_LIGHTS != 0:
                effects[EFFECT_ENABLE_BITS2] |= 0x10
                _set_lights_for_player_index(effects, self.player_index)
        return self._send_effect(device, source, effects)

    def _send_effect[
        S: HidSource
    ](
        mut self,
        device: HidapiDevice,
        mut source: S,
        effect: List[UInt8],
    ) -> Bool:
        """Write an effects report. SDL: `InternalSendJoystickEffect`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            effect: The effects state.

        Returns:
            Whether the whole report was written.
        """
        if not self.effects_supported:
            return False
        if not self.enhanced_mode:
            return False
        var data = List[UInt8](length=78, fill=0)
        var report_size: Int
        var offset: Int
        if device.is_bluetooth:
            data[0] = REPORT_BLUETOOTH_EFFECTS
            data[1] = 0x02
            report_size = 78
            offset = 2
        else:
            data[0] = REPORT_USB_EFFECTS
            report_size = 48
            offset = 1
        for index in range(min(78 - offset, len(effect))):  # pragma: no branch
            data[offset + index] = effect[index]
        if device.is_bluetooth:
            # The CRC covers the hidp header too.
            var crc = crc32(0, [UInt8(0xA2)], 1)
            crc = crc32(crc, data, report_size - 4)
            for index in range(4):  # pragma: no branch
                data[report_size - 4 + index] = UInt8(
                    (crc >> UInt32(8 * index)) & 0xFF
                )
        data.resize(report_size, 0)
        return source.write(data) == report_size

    def _check_pending_led_reset[
        S: HidSource
    ](mut self, device: HidapiDevice, mut source: S):
        """Reset the light once the Bluetooth connection is done. SDL:
        `CheckPendingLEDReset`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
        """
        var complete = True
        # SDL also asks for `enhanced_reports`, which a pending reset
        # always has.
        if self.sensors_supported and not self.use_alternate_report:
            # The light animation ends at a time of the sensor clock.
            complete = (
                load32(self.last_state, SENSOR_TIMESTAMP) >= CONNECTION_COMPLETE
            )
        if complete:
            _ = self._update_effects(device, source, EFFECT_LED_RESET)
            self.led_reset_state = LED_RESET_COMPLETE
            _ = self._update_effects(
                device, source, EFFECT_LED | EFFECT_PAD_LIGHTS
            )

    def _tickle_bluetooth[
        S: HidSource
    ](mut self, mut device: HidapiDevice, mut source: S):
        """Make a silent Bluetooth link show whether it is gone. SDL:
        `TickleBluetooth`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
        """
        if self.enhanced_reports:
            # A report with no CRC, which the pad ignores.
            var data = List[UInt8](length=78, fill=0)
            data[0] = REPORT_BLUETOOTH_EFFECTS
            data[1] = 0x02
            _ = source.write(data)
        elif device.joysticks > 0:
            # Any effects report would turn on enhanced mode.
            device.joystick_disconnected()

    def _handle_simple_state(
        mut self, mut joystick: Joystick, data: List[UInt8], at: Int
    ):
        """Read a simple report. SDL: `HandleSimpleStatePacket`.

        Args:
            joystick: The joystick.
            data: The report.
            at: Where the packet starts, after the report id.
        """
        var buttons0 = data[at + SIMPLE_BUTTONS]
        var buttons1 = data[at + SIMPLE_BUTTONS + 1]
        var buttons2 = data[at + SIMPLE_BUTTONS + 2]
        if self.last_state[SIMPLE_BUTTONS] != buttons0:
            self._face_buttons(joystick, buttons0)
        if self.last_state[SIMPLE_BUTTONS + 1] != buttons1:
            self._shoulder_buttons(joystick, buttons1)
        if self.last_state[SIMPLE_BUTTONS + 2] != buttons2:
            joystick.send_button(BUTTON_GUIDE, buttons2 & 0x01 != 0)
            joystick.send_button(BUTTON_PS5_TOUCHPAD, buttons2 & 0x02 != 0)
        self._axes(
            joystick,
            data,
            at,
            data[at + SIMPLE_TRIGGER_LEFT],
            data[at + SIMPLE_TRIGGER_RIGHT],
            buttons1,
        )
        for index in range(SIMPLE_SIZE):  # pragma: no branch
            self.last_state[index] = data[at + index]

    def _face_buttons(self, mut joystick: Joystick, data: UInt8):
        """Send the face buttons and the d-pad.

        Args:
            joystick: The joystick.
            data: The first buttons byte.
        """
        var face = data >> 4
        joystick.send_button(BUTTON_WEST, face & 0x01 != 0)
        joystick.send_button(BUTTON_SOUTH, face & 0x02 != 0)
        joystick.send_button(BUTTON_EAST, face & 0x04 != 0)
        joystick.send_button(BUTTON_NORTH, face & 0x08 != 0)
        joystick.send_hat(0, _hat(Int(data & 0x0F)))

    def _shoulder_buttons(self, mut joystick: Joystick, data: UInt8):
        """Send the shoulder, menu and stick buttons.

        Args:
            joystick: The joystick.
            data: The second buttons byte.
        """
        joystick.send_button(BUTTON_LEFT_SHOULDER, data & 0x01 != 0)
        joystick.send_button(BUTTON_RIGHT_SHOULDER, data & 0x02 != 0)
        joystick.send_button(BUTTON_BACK, data & 0x10 != 0)
        joystick.send_button(BUTTON_START, data & 0x20 != 0)
        joystick.send_button(BUTTON_LEFT_STICK, data & 0x40 != 0)
        joystick.send_button(BUTTON_RIGHT_STICK, data & 0x80 != 0)

    def _axes(
        self,
        mut joystick: Joystick,
        data: List[UInt8],
        at: Int,
        trigger_left: UInt8,
        trigger_right: UInt8,
        buttons1: UInt8,
    ):
        """Send the triggers and the sticks.

        A trigger at 0 with its button down is fully pressed.

        Args:
            joystick: The joystick.
            data: The report.
            at: Where the packet starts, with the sticks.
            trigger_left: The left trigger byte.
            trigger_right: The right trigger byte.
            buttons1: The second buttons byte.
        """
        var axis = _stick(trigger_left)
        if trigger_left == 0 and buttons1 & 0x04 != 0:
            axis = JOYSTICK_AXIS_MAX
        joystick.send_axis(AXIS_LEFT_TRIGGER, axis)
        axis = _stick(trigger_right)
        if trigger_right == 0 and buttons1 & 0x08 != 0:
            axis = JOYSTICK_AXIS_MAX
        joystick.send_axis(AXIS_RIGHT_TRIGGER, axis)
        joystick.send_axis(AXIS_LEFTX, _stick(data[at]))
        joystick.send_axis(AXIS_LEFTY, _stick(data[at + 1]))
        joystick.send_axis(AXIS_RIGHTX, _stick(data[at + 2]))
        joystick.send_axis(AXIS_RIGHTY, _stick(data[at + 3]))

    def _handle_state_common(
        mut self, mut joystick: Joystick, data: List[UInt8], at: Int
    ):
        """Read the part the full reports share. SDL:
        `HandleStatePacketCommon`.

        Args:
            joystick: The joystick.
            data: The report.
            at: Where the packet starts, after the report id.
        """
        var buttons0 = data[at + BUTTONS]
        var buttons1 = data[at + BUTTONS + 1]
        var buttons2 = data[at + BUTTONS + 2]
        if self.last_state[BUTTONS] != buttons0:
            self._face_buttons(joystick, buttons0)
        if self.last_state[BUTTONS + 1] != buttons1:
            self._shoulder_buttons(joystick, buttons1)
        if self.last_state[BUTTONS + 2] != buttons2:
            joystick.send_button(BUTTON_GUIDE, buttons2 & 0x01 != 0)
            joystick.send_button(BUTTON_PS5_TOUCHPAD, buttons2 & 0x02 != 0)
            joystick.send_button(BUTTON_PS5_MICROPHONE, buttons2 & 0x04 != 0)
            joystick.send_button(BUTTON_PS5_LEFT_FUNCTION, buttons2 & 0x10 != 0)
            joystick.send_button(
                BUTTON_PS5_RIGHT_FUNCTION, buttons2 & 0x20 != 0
            )
            joystick.send_button(BUTTON_PS5_LEFT_PADDLE, buttons2 & 0x40 != 0)
            joystick.send_button(BUTTON_PS5_RIGHT_PADDLE, buttons2 & 0x80 != 0)
        self._axes(
            joystick,
            data,
            at,
            data[at + TRIGGER_LEFT],
            data[at + TRIGGER_RIGHT],
            buttons1,
        )
        if not self.report_sensors:
            return
        var nanoseconds: Int
        if self.use_alternate_report:
            # A 16-bit clock in microseconds.
            var tick = Int(data[at + SENSOR_TIMESTAMP]) | (
                Int(data[at + SENSOR_TIMESTAMP + 1]) << 8
            )
            var delta: Int
            if self.last_tick < tick:
                delta = tick - self.last_tick
            else:
                delta = (0xFFFF - self.last_tick + tick + 1) & 0xFFFFFFFF
            self.last_tick = tick
            self.sensor_ticks += delta
            nanoseconds = self.sensor_ticks * 1000
        else:
            # A 32-bit clock in thirds of a microsecond.
            var tick = load32(data, at + SENSOR_TIMESTAMP)
            var delta: Int
            if self.last_tick < tick:
                delta = tick - self.last_tick
            else:
                delta = (0xFFFFFFFF - self.last_tick + tick + 1) & 0xFFFFFFFF
            self.last_tick = tick
            self.sensor_ticks += delta
            nanoseconds = self.sensor_ticks * 1000 // 3
        var timestamp = Duration64(Float64(nanoseconds) * 1e-9, SECOND)
        var values = SIMD[DType.float32, SENSOR_VALUES](0)
        for axis in range(3):  # pragma: no branch
            values[axis] = self._apply_calibration(
                axis, load16(data, at + GYRO + 2 * axis)
            )
        joystick.send_sensor(SENSOR_GYRO, timestamp, values)
        for axis in range(3):  # pragma: no branch
            values[axis] = self._apply_calibration(
                3 + axis, load16(data, at + ACCEL + 2 * axis)
            )
        joystick.send_sensor(SENSOR_ACCEL, timestamp, values)

    def _touchpad(
        self, mut joystick: Joystick, data: List[UInt8], at: Int, finger: Int
    ):
        """Send one finger on the touchpad.

        Args:
            joystick: The joystick.
            data: The report.
            at: Where the finger's counter byte is.
            finger: The finger, 0 or 1.
        """
        var down = data[at] & 0x80 == 0
        var x = Int(data[at + 1]) | ((Int(data[at + 2]) & 0x0F) << 8)
        var y = (Int(data[at + 2]) >> 4) | (Int(data[at + 3]) << 4)
        joystick.send_touchpad(
            0,
            finger,
            down,
            Float32(x) * TOUCHPAD_SCALEX,
            Float32(y) * TOUCHPAD_SCALEY,
            Float32(1.0) if down else Float32(0.0),
        )

    def _handle_state(
        mut self, mut joystick: Joystick, data: List[UInt8], at: Int
    ):
        """Read a full report. SDL: `HandleStatePacket` and
        `HandleStatePacketAlt`.

        Args:
            joystick: The joystick.
            data: The report.
            at: Where the packet starts, after the report id.
        """
        if self.report_touchpad:
            var first = ALT_TOUCHPAD1 if self.use_alternate_report else (
                TOUCHPAD1
            )
            var second = ALT_TOUCHPAD2 if self.use_alternate_report else (
                TOUCHPAD2
            )
            self._touchpad(joystick, data, at + first, 0)
            self._touchpad(joystick, data, at + second, 1)
        self._handle_state_common(joystick, data, at)
        for index in range(STATE_SIZE):  # pragma: no branch
            self.last_state[index] = data[at + index]

    def _is_packet_valid(mut self, data: List[UInt8], size: Int) -> Bool:
        """Return True if a report is one to read. SDL: `IsPacketValid`.

        Args:
            data: The report.
            size: Its length.

        Returns:
            Whether it is a state report, with a good CRC on Bluetooth.
            A Nacon dongle's report counts only when its sequence moves.
        """
        if data[0] == REPORT_STATE:
            if self.is_nacon_dongle and size >= 1 + ALT_SIZE:
                # The sequence stands still while no pad is on the dongle.
                var same = True
                for index in range(4):  # pragma: no branch
                    if (
                        data[1 + PACKET_SEQUENCE + index]
                        != self.last_state[PACKET_SEQUENCE + index]
                    ):
                        same = False
                if same:
                    return False
                var empty = True
                for index in range(6):  # pragma: no branch
                    if self.last_state[ACCEL + index] != 0:
                        empty = False
                if empty:
                    # Nothing to compare with yet: keep this one.
                    for index in range(ALT_SIZE):  # pragma: no branch
                        self.last_state[index] = data[1 + index]
                    return False
            return True
        if data[0] == REPORT_BLUETOOTH_STATE:
            if size < 4:
                return False
            var crc = crc32(0, [UInt8(0xA1)], 1)
            crc = crc32(crc, data, size - 4)
            return Int(crc) == load32(data, size - 4)
        return False

    def update_device[
        S: HidSource
    ](
        mut self,
        mut device: HidapiDevice,
        mut source: S,
        mut pad: Optional[Gamepad],
        now: Duration64,
    ) -> Bool:
        """Read the device's reports. SDL: `UpdateDevice`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            pad: The open gamepad, or None.
            now: The time now.

        Returns:
            False when the device went away.
        """
        var data = List[UInt8](length=USB_PACKET_LENGTH * 2, fill=0)
        var packet_count = 0
        var size: Int
        while True:
            size = source.read(data, 0)
            if size <= 0:
                break
            if not self._is_packet_valid(data, size):
                continue
            packet_count += 1
            self.last_packet = now
            if not pad:
                continue
            ref joystick = pad.value().joystick
            if data[0] == REPORT_STATE:
                if size == 10 or size == 78:
                    self._handle_simple_state(joystick, data, 1)
                else:
                    self._handle_state(joystick, data, 1)
            else:
                # The full report over Bluetooth.
                self.enhanced_reports = True
                self._handle_state(joystick, data, 2)
                if self.led_reset_state == LED_RESET_PENDING:
                    self._check_pending_led_reset(device, source)
        var timed_out = (
            _milliseconds(now)
            >= _milliseconds(self.last_packet) + BLUETOOTH_DISCONNECT_TIMEOUT_MS
        )
        if device.is_bluetooth:
            if packet_count == 0:
                if timed_out:
                    # See whether the link is still there.
                    self._tickle_bluetooth(device, source)
                    self.last_packet = now
            elif device.joysticks == 0 and not (
                device.has_connected_usb_device(device.serial)
            ):
                # The USB cable is gone: the Bluetooth link takes over.
                _ = device.joystick_connected()
        if self.is_nacon_dongle:
            if packet_count == 0:
                if device.joysticks > 0 and timed_out:
                    device.joystick_disconnected()
            elif device.joysticks == 0:
                _ = device.joystick_connected()
        if packet_count == 0 and size < 0 and device.joysticks > 0:
            # A read error: the device is gone.
            device.joystick_disconnected()
        return size >= 0

    def open_joystick[
        S: HidSource
    ](
        mut self, mut device: HidapiDevice, mut source: S, now: Duration64
    ) raises -> Joystick:
        """Make the device's joystick. SDL: `OpenJoystick`, with the hint
        callbacks it calls at once.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            now: The time now.

        Returns:
            The joystick, with its touchpad and sensors.

        Raises:
            Error: If the joystick cannot be made.
        """
        self.joystick_open = True
        self.last_packet = now
        self.report_sensors = False
        self.report_touchpad = False
        self.rumble_left = 0
        self.rumble_right = 0
        self.color_set = False
        self.led_reset_state = LED_RESET_NONE
        self.last_state = List[UInt8](length=STATE_SIZE, fill=0)
        self.player_index = self.assigned_player_index
        var edge = (
            device.vendor.value == USB_VENDOR_SONY
            and device.product.value == USB_PRODUCT_SONY_DS5_EDGE
        )
        var buttons = 11
        if edge:
            # The paddles, the touchpad and the microphone.
            buttons = 17
        elif self.touchpad_supported:
            # The touchpad and the microphone.
            buttons = 13
        var joystick = Joystick(
            device.name, device.guid, AXIS_COUNT, buttons, 1
        )
        # The enhanced reports hint is on: enter enhanced mode.
        if self.touchpad_supported:
            joystick.add_touchpad(2)
            self.report_touchpad = True
        if self.sensors_supported:
            # 250 Hz over USB; 1000 Hz over Bluetooth and on the Edge.
            var rate = Float32(250.0)
            if device.is_bluetooth or edge:
                rate = Float32(1000.0)
            joystick.add_sensor(SENSOR_GYRO, Frequency(rate, PER_SECOND))
            joystick.add_sensor(SENSOR_ACCEL, Frequency(rate, PER_SECOND))
        self.enhanced_mode = True
        # Switch the pad to enhanced reports, then set its lights.
        _ = self._update_effects(device, source, 0)
        _ = self._update_effects(device, source, EFFECT_LED | EFFECT_PAD_LIGHTS)
        return joystick^

    def rumble[
        S: HidSource
    ](
        mut self, mut device: HidapiDevice, mut source: S, low: Int, high: Int
    ) -> Bool:
        """Rumble. SDL: `RumbleJoystick`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            low: The low frequency strength, 0 to 65535.
            high: The high frequency strength, 0 to 65535.

        Returns:
            Whether the pad took it.
        """
        if not self.vibration_supported:
            return False
        if self.rumble_left == 0 and self.rumble_right == 0:
            _ = self._update_effects(device, source, EFFECT_RUMBLE_START)
        self.rumble_left = low >> 8
        self.rumble_right = high >> 8
        return self._update_effects(device, source, EFFECT_RUMBLE)

    def rumble_triggers[
        S: HidSource
    ](
        mut self,
        mut device: HidapiDevice,
        mut source: S,
        left: Int,
        right: Int,
    ) -> Bool:
        """Rumble the triggers. SDL: `RumbleJoystickTriggers`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            left: The left trigger's strength, 0 to 65535.
            right: The right trigger's strength, 0 to 65535.

        Returns:
            False: the driver has no trigger rumble.
        """
        return False

    def capabilities(self, device: HidapiDevice) -> Int:
        """Return what the pad can do. SDL: `GetJoystickCapabilities`.

        Args:
            device: The device.

        Returns:
            The `CAP_*` bits, or 0 before enhanced mode.
        """
        var result = 0
        if self.enhanced_mode:
            if self.lightbar_supported:
                result |= CAP_RGB_LED
            if self.playerled_supported:
                result |= CAP_PLAYER_LED
            if self.vibration_supported:
                result |= CAP_RUMBLE
        return result

    def set_led[
        S: HidSource
    ](
        mut self,
        mut device: HidapiDevice,
        mut source: S,
        red: Int,
        green: Int,
        blue: Int,
    ) -> Bool:
        """Set the light bar. SDL: `SetJoystickLED`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            red: The red level, 0 to 255.
            green: The green level.
            blue: The blue level.

        Returns:
            Whether the pad took it.
        """
        if not self.lightbar_supported:
            return False
        self.color_set = True
        self.led_red = red
        self.led_green = green
        self.led_blue = blue
        return self._update_effects(device, source, EFFECT_LED)

    def set_sensors_enabled[
        S: HidSource
    ](
        mut self,
        mut device: HidapiDevice,
        mut source: S,
        mut joystick: Joystick,
        enabled: Bool,
    ) -> Bool:
        """Turn the motion sensors on or off. SDL:
        `SetJoystickSensorsEnabled`.

        Turning them on reads the calibration again.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            joystick: The joystick.
            enabled: Whether they report.

        Returns:
            Whether the change took effect.
        """
        if not self.sensors_supported or (enabled and not self.enhanced_mode):
            return False
        if enabled:
            self._load_calibration_data(source)
        self.report_sensors = enabled
        return True

    def close_joystick[
        S: HidSource
    ](mut self, mut device: HidapiDevice, mut source: S):
        """Close the joystick. SDL: `CloseJoystick`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
        """
        self.joystick_open = False
        self.report_sensors = False
        self.enhanced_mode = False
