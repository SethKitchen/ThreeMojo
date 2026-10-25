# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of
# src/joystick/hidapi/SDL_hidapi_ps4.c, from SDL 3.2.24. It is a
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

"""The DualShock 4 driver. SDL: `SDL_hidapi_ps4.c`.

The driver reads Sony's DualShock 4 reports on USB and on Bluetooth, the
reports of the Sony wireless dongle, and those of the controllers other
companies make to the same protocol. It reads the sticks, the buttons,
the two-finger touchpad and the calibrated gyroscope and accelerometer,
and it sends rumble and the light bar color.

The driver runs with SDL's default hints: the enhanced reports are on
from the time the joystick opens, and a report comes every 4 ms. These
parts of SDL's driver are not here:

- `SendJoystickEffect`, which sends an effects report that the
  application makes.
- The hint callbacks, so the `SDL_JOYSTICK_ENHANCED_REPORTS` and
  `SDL_JOYSTICK_HIDAPI_PS4_REPORT_INTERVAL` hints keep their defaults.
  The enhanced-mode steps that only the `auto` hint reaches are gone.
- The battery level and the joystick type, which `HidapiDevice` and
  `Joystick` do not keep.
- The 2 ms wait between the tries to read the calibration report.

`UpdateDevice` returns whether the last read worked. SDL returns the
result of the serial number request instead when the dongle connects in
the same call. SDL ignores the value; the hub drops a device on False, so
the read decides here.
"""
from extensions.gamepad.gamepad import Gamepad
from extensions.gamepad.guid import ProductId, VendorId
from extensions.gamepad.hid import HidSource
from extensions.gamepad.hid_device import (
    CAP_RGB_LED,
    CAP_RUMBLE,
    HidapiDevice,
    USB_PACKET_LENGTH,
    USB_VENDOR_NACON_ALT,
    USB_VENDOR_PDP,
    USB_VENDOR_RAZER,
    load16,
    load32,
    supports_playstation_detection,
)
from extensions.gamepad.ids import (
    AXIS_COUNT,
    AXIS_LEFTX,
    AXIS_LEFTY,
    AXIS_LEFT_TRIGGER,
    AXIS_RIGHTX,
    AXIS_RIGHTY,
    AXIS_RIGHT_TRIGGER,
    BUTTON_BACK,
    BUTTON_EAST,
    BUTTON_GUIDE,
    BUTTON_LEFT_SHOULDER,
    BUTTON_LEFT_STICK,
    BUTTON_NORTH,
    BUTTON_RIGHT_SHOULDER,
    BUTTON_RIGHT_STICK,
    BUTTON_SOUTH,
    BUTTON_START,
    BUTTON_WEST,
    GAMEPAD_TYPE_PS4,
    GamepadType,
)
from extensions.gamepad.joystick import (
    SENSOR_ACCEL,
    SENSOR_GYRO,
    SENSOR_VALUES,
    Joystick,
)
from extensions.gamepad.mapping import HAT_DOWN, HAT_LEFT, HAT_RIGHT, HAT_UP
from render.checksum import crc32
from units.si import Duration64, Frequency, PER_SECOND, SECOND

comptime USB_VENDOR_SONY = 0x054C
comptime USB_PRODUCT_SONY_DS4_DONGLE = 0x0BA0
comptime USB_PRODUCT_SONY_DS4_STRIKEPAD = 0x05C5
comptime USB_PRODUCT_NACON_REVOLUTION_5_PRO_PS4_WIRELESS = 0x0D16
comptime USB_PRODUCT_VICTRIX_FS_PRO = 0x0203
comptime USB_PRODUCT_VICTRIX_FS_PRO_V2 = 0x0207

# How long a wireless pad may send nothing before the driver acts.
comptime BLUETOOTH_DISCONNECT_TIMEOUT = Duration64(0.5, SECOND)
# SDL's default report interval, in milliseconds.
comptime DEFAULT_REPORT_INTERVAL = 4

# The touchpad button. SDL: `SDL_GAMEPAD_BUTTON_PS4_TOUCHPAD`.
comptime BUTTON_PS4_TOUCHPAD = 11

# Input and output report ids. SDL: `EPS4ReportId`.
comptime REPORT_USB_STATE = 1
comptime REPORT_USB_EFFECTS = 5
comptime REPORT_BLUETOOTH_STATE1 = 17
comptime REPORT_BLUETOOTH_STATE9 = 25
comptime REPORT_BLUETOOTH_EFFECTS = 17

# Feature report ids. SDL: `EPS4FeatureReportID`.
comptime FEATURE_GYRO_CALIBRATION_USB = 0x02
comptime FEATURE_CAPABILITIES = 0x03
comptime FEATURE_GYRO_CALIBRATION_BT = 0x05
comptime FEATURE_SERIAL_NUMBER = 0x12

# The size of `PS4StatePacket_t`, and where its fields start.
comptime STATE_SIZE = 42
comptime STATE_BUTTONS = 4
comptime STATE_TRIGGER_LEFT = 7
comptime STATE_TRIGGER_RIGHT = 8
comptime STATE_TIMESTAMP = 9
comptime STATE_GYRO = 12
comptime STATE_ACCEL = 18
comptime STATE_TOUCHPAD = 34

# The size of `DS4EffectsState_t`.
comptime EFFECTS_SIZE = 19
# The largest effects report.
comptime EFFECTS_REPORT_SIZE = 78

# The touchpad's scale: 1 / 1920 across and 1 / 920 down.
comptime TOUCHPAD_SCALE_X: Float32 = 5.20833333e-4
comptime TOUCHPAD_SCALE_Y: Float32 = 1.08695652e-3

comptime PI = 3.141592653589793
# SDL's `SDL_STANDARD_GRAVITY` is a float.
comptime STANDARD_GRAVITY: Float32 = 9.80665


def _sint16(value: Int) -> Int:
    """Wrap a number to a signed 16-bit value, as a C cast does.

    Args:
        value: The number.

    Returns:
        The number from -32768 to 32767 with the same low 16 bits.
    """
    var low = value & 0xFFFF
    return low - 0x10000 if low >= 0x8000 else low


def _uint16(data: List[UInt8], index: Int) -> Int:
    """Read an unsigned 16-bit little-endian number.

    Args:
        data: The bytes.
        index: Where the number starts.

    Returns:
        The number, from 0 to 65535.
    """
    return Int(data[index]) | (Int(data[index + 1]) << 8)


def _hex2(value: UInt8) -> String:
    """Write a byte as two lowercase hexadecimal digits, as `%.2x` does.

    Args:
        value: The byte.

    Returns:
        The two digits.
    """
    comptime DIGITS = "0123456789abcdef"
    return String(DIGITS[byte=Int(value >> 4)]) + String(
        DIGITS[byte=Int(value & 15)]
    )


def _read_feature[
    S: HidSource
](mut source: S, report_id: Int, mut report: List[UInt8]) -> Int:
    """Clear a buffer and read a feature report into it. SDL:
    `ReadFeatureReport`.

    Parameters:
        S: The kind of HID device.

    Args:
        source: The open device.
        report_id: The report id.
        report: The buffer. Its length is the most to read.

    Returns:
        The bytes read, or -1 on an error.
    """
    report = List[UInt8](length=len(report), fill=0)
    report[0] = UInt8(report_id)
    return source.get_feature_report(report)


def _serial_from_report(data: List[UInt8], size: Int) -> String:
    """Return the serial number in a serial number feature report.

    Args:
        data: The report.
        size: The bytes read.

    Returns:
        The serial number as `xx-xx-xx-xx-xx-xx`, or an empty string when
        the report is short or all zeros.
    """
    if size < 7:
        return ""
    var any = False
    for index in range(1, 7):
        if data[index] != 0:
            any = True
    if not any:
        return ""
    var serial = _hex2(data[6])
    for index in range(1, 6):
        serial += "-" + _hex2(data[6 - index])
    return serial^


def _dashed_serial(text: String) -> String:
    """Put dashes in a 12-digit serial number, as `InitDevice` does.

    Args:
        text: The serial number the device reports.

    Returns:
        The serial number as `xx-xx-xx-xx-xx-xx`, or an empty string when
        it is not 12 bytes long.
    """
    if text.byte_length() != 12:
        return ""
    var serial = String(text[byte=0:2])
    for pair in range(1, 6):
        serial += "-" + String(text[byte = 2 * pair : 2 * pair + 2])
    return serial^


@fieldwise_init
struct ImuCalibration(Copyable, Movable):
    """One sensor axis's calibration. SDL: `IMUCalibrationData`."""

    # The raw value at rest, as a signed 16-bit number.
    var bias: Int
    # The factor from a raw value less the bias to SI units.
    var scale: Float32


struct Ps4Driver(Movable):
    """The DualShock 4 driver's state. SDL: `SDL_DriverPS4_Context`."""

    # Whether the joystick is open. SDL: `joystick` is not NULL.
    var joystick_open: Bool
    var is_dongle: Bool
    var is_nacon_dongle: Bool
    var official_controller: Bool
    var sensors_supported: Bool
    var lightbar_supported: Bool
    var vibration_supported: Bool
    var touchpad_supported: Bool
    var effects_supported: Bool
    var enhanced_reports: Bool
    var enhanced_mode: Bool
    var enhanced_mode_available: Bool
    var report_interval: Int
    var report_sensors: Bool
    var report_touchpad: Bool
    var hardware_calibration: Bool
    var calibration: List[ImuCalibration]
    var last_packet: Duration64
    var player_index: Int
    # The player number SDL gives the joystick, which `OpenJoystick`
    # reads. SDL: `SDL_GetJoystickPlayerIndex`.
    var joystick_player_index: Int
    var rumble_left: Int
    var rumble_right: Int
    var color_set: Bool
    var led_red: Int
    var led_green: Int
    var led_blue: Int
    var gyro_numerator: Int
    var gyro_denominator: Int
    var accel_numerator: Int
    var accel_denominator: Int
    var sensor_ticks: Int
    var last_tick: Int
    # A counter that wraps at 65536.
    var valid_crc_packets: Int
    # The last state packet. SDL: `PS4StatePacket_t last_state`.
    var last_state: List[UInt8]
    # `UpdateDevice`'s report buffer. SDL keeps it on the stack, so the
    # bytes past a short report are what an earlier report left.
    var buffer: List[UInt8]

    def __init__(out self):
        """Create the state of a device the driver has not seen."""
        self.joystick_open = False
        self.is_dongle = False
        self.is_nacon_dongle = False
        self.official_controller = False
        self.sensors_supported = False
        self.lightbar_supported = False
        self.vibration_supported = False
        self.touchpad_supported = False
        self.effects_supported = False
        self.enhanced_reports = False
        self.enhanced_mode = False
        self.enhanced_mode_available = False
        self.report_interval = 0
        self.report_sensors = False
        self.report_touchpad = False
        self.hardware_calibration = False
        self.calibration = List[ImuCalibration](
            length=6, fill=ImuCalibration(0, 0)
        )
        self.last_packet = Duration64(0, SECOND)
        self.player_index = 0
        self.joystick_player_index = -1
        self.rumble_left = 0
        self.rumble_right = 0
        self.color_set = False
        self.led_red = 0
        self.led_green = 0
        self.led_blue = 0
        self.gyro_numerator = 1
        self.gyro_denominator = 16
        self.accel_numerator = 1
        self.accel_denominator = 8192
        self.sensor_ticks = 0
        self.last_tick = 0
        self.valid_crc_packets = 0
        self.last_state = List[UInt8](length=STATE_SIZE, fill=0)
        self.buffer = List[UInt8](length=USB_PACKET_LENGTH * 2, fill=0)

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
            Whether the driver may run it: a PS4 controller, or one from
            a company that makes PlayStation controllers, which the open
            device then confirms.
        """
        if type == GAMEPAD_TYPE_PS4:
            return True
        return supports_playstation_detection(vendor, product)

    @staticmethod
    def is_supported_device[
        S: HidSource
    ](mut source: S, device: HidapiDevice) -> Bool:
        """Return True if the driver runs an open device. SDL:
        `IsSupportedDevice` with the device open.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            device: What is known about it.

        Returns:
            Whether the driver runs it. A device that is not a PS4
            controller must answer Sony's capability report.
        """
        if device.type == GAMEPAD_TYPE_PS4:
            return True
        if supports_playstation_detection(device.vendor, device.product):
            var data = List[UInt8](length=USB_PACKET_LENGTH, fill=0)
            var size = _read_feature(source, FEATURE_CAPABILITIES, data)
            return size == 48 and data[2] == 0x27
        return False

    @staticmethod
    def _read_wired_serial[
        S: HidSource
    ](mut source: S, serial: String) -> String:
        """Read the serial number of a wired pad. SDL: `ReadWiredSerial`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            serial: The serial number so far.

        Returns:
            The serial number the pad reports, or `serial` when it reports
            none.
        """
        var data = List[UInt8](length=USB_PACKET_LENGTH, fill=0)
        var size = _read_feature(source, FEATURE_SERIAL_NUMBER, data)
        var read = _serial_from_report(data, size)
        if read.byte_length() > 0:
            return read^
        return serial

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
            Whether the driver runs the device. A dongle with no pad runs
            with no joystick.
        """
        var vendor = device.vendor.value
        var product = device.product.value
        var serial = _dashed_serial(device.serial)
        self.is_dongle = (
            vendor == USB_VENDOR_SONY and product == USB_PRODUCT_SONY_DS4_DONGLE
        )
        if self.is_dongle:
            serial = Self._read_wired_serial(source, serial)
            self.enhanced_reports = True
        elif (
            vendor == USB_VENDOR_SONY
            and product == USB_PRODUCT_SONY_DS4_STRIKEPAD
        ):
            self.enhanced_reports = True
        elif vendor == USB_VENDOR_SONY:
            if device.is_bluetooth:
                # A first report from 17 to 25 means enhanced mode.
                var data = List[UInt8](length=USB_PACKET_LENGTH, fill=0)
                var size = source.read(data, 16)
                if (
                    size > 0
                    and Int(data[0]) >= REPORT_BLUETOOTH_STATE1
                    and Int(data[0]) <= REPORT_BLUETOOTH_STATE9
                ):
                    self.enhanced_reports = True
            else:
                serial = Self._read_wired_serial(source, serial)
                self.enhanced_reports = True
        else:
            # Third-party controllers all appear to be wired.
            self.enhanced_reports = True

        if vendor == USB_VENDOR_SONY:
            self.official_controller = True
            self.sensors_supported = True
            self.lightbar_supported = True
            self.vibration_supported = True
            self.touchpad_supported = True
        else:
            var data = List[UInt8](length=USB_PACKET_LENGTH, fill=0)
            var size = _read_feature(source, FEATURE_CAPABILITIES, data)
            if size == 48 and data[2] == 0x27:
                var capabilities = Int(data[4])
                var gyro_numerator = _uint16(data, 10)
                var gyro_denominator = _uint16(data, 12)
                var accel_numerator = _uint16(data, 14)
                var accel_denominator = _uint16(data, 16)
                self.sensors_supported = capabilities & 0x02 != 0
                self.lightbar_supported = capabilities & 0x04 != 0
                self.vibration_supported = capabilities & 0x08 != 0
                self.touchpad_supported = capabilities & 0x40 != 0
                if gyro_numerator != 0 and gyro_denominator != 0:
                    self.gyro_numerator = gyro_numerator
                    self.gyro_denominator = gyro_denominator
                if accel_numerator != 0 and accel_denominator != 0:
                    self.accel_numerator = accel_numerator
                    self.accel_denominator = accel_denominator
            elif vendor == USB_VENDOR_RAZER:
                # The Razer Raiju does not answer, but has a touchpad and
                # rumble.
                self.vibration_supported = True
                self.touchpad_supported = True
        self.effects_supported = (
            self.lightbar_supported or self.vibration_supported
        )
        self.is_nacon_dongle = (
            vendor == USB_VENDOR_NACON_ALT
            and product == USB_PRODUCT_NACON_REVOLUTION_5_PRO_PS4_WIRELESS
        )
        if vendor == USB_VENDOR_PDP and (
            product == USB_PRODUCT_VICTRIX_FS_PRO
            or product == USB_PRODUCT_VICTRIX_FS_PRO_V2
        ):
            # The Victrix FS Pro V2 says it has a light bar, but it does
            # not answer the effects report and hangs on reboot after one.
            self.effects_supported = False

        device.type = GAMEPAD_TYPE_PS4
        if self.official_controller:
            device.set_name("PS4 Controller")
        device.set_serial(serial)

        # Prefer the USB device to the Bluetooth device.
        if device.is_bluetooth:
            if device.has_connected_usb_device(device.serial):
                return True
        else:
            var own = device.serial
            device.disconnect_bluetooth_device(own)
        if (self.is_dongle or self.is_nacon_dongle) and (
            serial.byte_length() == 0
        ):
            # No pad is connected yet.
            return True
        return device.joystick_connected()

    def _load_official_calibration[
        S: HidSource
    ](mut self, device: HidapiDevice, mut source: S) -> Bool:
        """Read the sensor calibration of a Sony pad. SDL:
        `LoadOfficialCalibrationData`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.

        Returns:
            Whether the pad's own calibration is in use.
        """
        if not self.official_controller:
            return False
        var data = List[UInt8](length=USB_PACKET_LENGTH, fill=0)
        var have_data = False
        for _ in range(5):  # pragma: no branch
            # On Bluetooth, this report turns on the enhanced reports.
            var size = _read_feature(source, FEATURE_GYRO_CALIBRATION_USB, data)
            if size < 35:
                return False
            if device.is_bluetooth:
                size = _read_feature(source, FEATURE_GYRO_CALIBRATION_BT, data)
                if size < 35:
                    return False
            # The report is sometimes all zeros, such as just after the
            # dongle connects.
            for index in range(size):  # pragma: no branch
                if data[index] != 0:
                    have_data = True
                    break
            if have_data:
                break
        if not have_data:
            return self.hardware_calibration

        var pitch_bias = load16(data, 1)
        var yaw_bias = load16(data, 3)
        var roll_bias = load16(data, 5)
        var pitch_plus: Int
        var pitch_minus: Int
        var yaw_plus: Int
        var yaw_minus: Int
        var roll_plus: Int
        var roll_minus: Int
        if device.is_bluetooth or self.is_dongle:
            pitch_plus = load16(data, 7)
            yaw_plus = load16(data, 9)
            roll_plus = load16(data, 11)
            pitch_minus = load16(data, 13)
            yaw_minus = load16(data, 15)
            roll_minus = load16(data, 17)
        else:
            pitch_plus = load16(data, 7)
            pitch_minus = load16(data, 9)
            yaw_plus = load16(data, 11)
            yaw_minus = load16(data, 13)
            roll_plus = load16(data, 15)
            roll_minus = load16(data, 17)
        var speed_plus = load16(data, 19)
        var speed_minus = load16(data, 21)

        var numerator = (
            Float32(speed_plus + speed_minus)
            * Float32(self.gyro_denominator)
            / Float32(self.gyro_numerator)
        )
        var biases = [pitch_bias, yaw_bias, roll_bias]
        var plus = [pitch_plus, yaw_plus, roll_plus]
        var minus = [pitch_minus, yaw_minus, roll_minus]
        for axis in range(3):  # pragma: no branch
            var denominator = Float32(
                abs(plus[axis] - biases[axis]) + abs(minus[axis] - biases[axis])
            )
            if denominator != 0:
                self.calibration[axis].bias = biases[axis]
                self.calibration[axis].scale = numerator / denominator
        for axis in range(3):  # pragma: no branch
            var accel_plus = load16(data, 23 + 4 * axis)
            var accel_minus = load16(data, 25 + 4 * axis)
            var range_2g = _sint16(accel_plus - accel_minus)
            # C's division truncates toward zero.
            var half = range_2g // 2 if range_2g >= 0 else -((-range_2g) // 2)
            self.calibration[3 + axis].bias = _sint16(accel_plus - half)
            self.calibration[3 + axis].scale = (
                Float32(2.0)
                * Float32(self.accel_denominator)
                / Float32(self.accel_numerator)
            ) / Float32(range_2g)

        self.hardware_calibration = True
        for index in range(6):  # pragma: no branch
            # Some controllers have a bad calibration.
            if (
                abs(self.calibration[index].bias) > 1024
                or abs(Float32(1.0) - self.calibration[index].scale) > 0.5
            ):
                self.hardware_calibration = False
        return self.hardware_calibration

    def _load_calibration[
        S: HidSource
    ](mut self, device: HidapiDevice, mut source: S):
        """Read the sensor calibration and scale it to SI units. SDL:
        `LoadCalibrationData`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
        """
        if not self._load_official_calibration(device, source):
            for index in range(6):  # pragma: no branch
                self.calibration[index].bias = 0
                self.calibration[index].scale = 1.0
        var strikepad = (
            device.vendor.value == USB_VENDOR_SONY
            and device.product.value == USB_PRODUCT_SONY_DS4_STRIKEPAD
        )
        for index in range(6):  # pragma: no branch
            var scale = Float64(self.calibration[index].scale)
            if index < 3:
                scale *= (
                    (
                        Float64(self.gyro_numerator)
                        / Float64(self.gyro_denominator)
                    )
                    * PI
                    / 180.0
                )
                if strikepad:
                    # The Armor-X Pro gives half the rotation it should.
                    scale *= 2.0
            else:
                scale *= (
                    Float64(self.accel_numerator)
                    / Float64(self.accel_denominator)
                ) * Float64(STANDARD_GRAVITY)
                if strikepad:
                    # The Armor-X Pro gives half the acceleration it
                    # should, the wrong way on every axis.
                    scale *= -2.0
            self.calibration[index].scale = Float32(scale)

    def _calibrated(self, index: Int, value: Int) -> Float32:
        """Apply one axis's calibration. SDL: `ApplyCalibrationData`.

        Args:
            index: The axis: 0 to 2 for the gyroscope, 3 to 5 for the
                accelerometer.
            value: The raw value.

        Returns:
            The value in rad/s or m/s².
        """
        return (
            Float32(value) - Float32(self.calibration[index].bias)
        ) * self.calibration[index].scale

    def _update_effects[
        S: HidSource
    ](mut self, device: HidapiDevice, mut source: S) -> Bool:
        """Send the rumble and the light bar color. SDL: `UpdateEffects`
        and `InternalSendJoystickEffect`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.

        Returns:
            Whether the pad took the report.
        """
        if not self.effects_supported:
            # Do not send reports to this controller.
            return False
        if not self.enhanced_mode:
            # Effects are not allowed outside the enhanced mode.
            return False
        var effects = List[UInt8](length=EFFECTS_SIZE, fill=0)
        if self.vibration_supported:
            effects[0] = UInt8(self.rumble_right)
            effects[1] = UInt8(self.rumble_left)
        if self.lightbar_supported:
            if self.color_set:
                effects[2] = UInt8(self.led_red)
                effects[3] = UInt8(self.led_green)
                effects[4] = UInt8(self.led_blue)
            else:
                # The colors of hid-sony.c in the Linux kernel. The first
                # 4 are those a PS4 gives.
                var colors: List[UInt8] = [
                    0x00, 0x00, 0x40,  # Blue
                    0x40, 0x00, 0x00,  # Red
                    0x00, 0x40, 0x00,  # Green
                    0x20, 0x00, 0x20,  # Pink
                    0x02, 0x01, 0x00,  # Orange
                    0x00, 0x01, 0x01,  # Teal
                    0x01, 0x01, 0x01,  # White
                ]  # fmt: skip
                var player = (
                    self.player_index % 7 if (self.player_index >= 0) else 0
                )
                for channel in range(3):  # pragma: no branch
                    effects[2 + channel] = colors[3 * player + channel]

        var data = List[UInt8](length=EFFECTS_REPORT_SIZE, fill=0)
        var report_size: Int
        var offset: Int
        if device.is_bluetooth and self.official_controller:
            data[0] = UInt8(REPORT_BLUETOOTH_EFFECTS)
            # HID and CRC, and the report interval.
            data[1] = UInt8(0xC0 | self.report_interval)
            # Rumble and light bar.
            data[3] = 0x03
            report_size = 78
            offset = 6
        else:
            data[0] = UInt8(REPORT_USB_EFFECTS)
            data[1] = 0x07
            report_size = 32
            offset = 4
        for index in range(EFFECTS_SIZE):  # pragma: no branch
            data[offset + index] = effects[index]
        if device.is_bluetooth:
            # A Bluetooth report ends with a CRC of the HIDP header and
            # the report.
            var covered: List[UInt8] = [0xA2]
            for index in range(report_size - 4):  # pragma: no branch
                covered.append(data[index])
            var crc = crc32(covered)
            for index in range(4):  # pragma: no branch
                data[report_size - 4 + index] = UInt8(
                    (crc >> UInt32(8 * index)) & 0xFF
                )
        data.resize(report_size, 0)
        return source.write(data) == report_size

    def _tickle_bluetooth[S: HidSource](mut self, mut source: S):
        """Send a report that does nothing, so that the Bluetooth stack
        notices a pad that went away. SDL: `TickleBluetooth`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
        """
        if self.enhanced_reports:
            # The CRC is not set, so the pad drops the report.
            var data = List[UInt8](length=EFFECTS_REPORT_SIZE, fill=0)
            data[0] = UInt8(REPORT_BLUETOOTH_EFFECTS)
            data[1] = 0xC0
            _ = source.write(data)

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
        self.joystick_player_index = player_index
        if not self.joystick_open:
            return
        self.player_index = player_index
        # SDL makes this call itself, so it does not turn on the enhanced
        # mode.
        _ = self._update_effects(device, source)

    def _verify_crc(self) -> Bool:
        """Check the CRC at the end of a Bluetooth state report. SDL:
        `VerifyCRC`.

        Returns:
            Whether the CRC of the HIDP header and the first 74 bytes is
            the one in the last 4.
        """
        var covered: List[UInt8] = [0xA1]
        for index in range(74):  # pragma: no branch
            covered.append(self.buffer[index])
        return Int(crc32(covered)) == load32(self.buffer, 74)

    def _is_packet_valid(mut self, size: Int) -> Bool:
        """Return True if the report in the buffer is a state report to
        read. SDL: `IsPacketValid`.

        Args:
            size: The report's length.

        Returns:
            Whether to read it.
        """
        var id = Int(self.buffer[0])
        if id == REPORT_USB_STATE:
            if size == 10:
                # A report outside the enhanced mode.
                return True
            if self.is_nacon_dongle and size >= 1 + STATE_SIZE:
                # The timestamp stays the same while no pad is connected.
                if (
                    self.buffer[1 + STATE_TIMESTAMP]
                    == self.last_state[STATE_TIMESTAMP]
                    and self.buffer[2 + STATE_TIMESTAMP]
                    == self.last_state[STATE_TIMESTAMP + 1]
                ):
                    return False
                var empty = True
                for index in range(6):  # pragma: no branch
                    if self.last_state[STATE_ACCEL + index] != 0:
                        empty = False
                if empty:
                    # Nothing to compare with yet: keep this state.
                    for index in range(STATE_SIZE):  # pragma: no branch
                        self.last_state[index] = self.buffer[1 + index]
                    return False
            # Bit 2 of byte 31 is 0 while a pad is connected to the
            # dongle, and always 0 on a pad.
            return size >= 64 and self.buffer[31] & 0x04 == 0
        if id >= REPORT_BLUETOOTH_STATE1 and id <= REPORT_BLUETOOTH_STATE9:
            # The first of two more bytes says whether HID data is there.
            if size >= 78 and self.buffer[1] & 0x80 != 0:
                if self._verify_crc():
                    self.valid_crc_packets = (
                        self.valid_crc_packets + 1
                    ) & 0xFFFF
                else:
                    if self.valid_crc_packets > 0:
                        self.valid_crc_packets -= 1
                    if self.valid_crc_packets >= 3:
                        # The CRCs are usually right, but this one is not.
                        return False
                return True
        return False

    def _handle_state_packet(
        mut self, mut joystick: Joystick, offset: Int, size: Int
    ):
        """Read a state report into the joystick. SDL: `HandleStatePacket`.

        Args:
            joystick: The joystick.
            offset: Where the state starts in the buffer.
            size: The state's length.
        """
        ref data = self.buffer
        if size > 9 and self.report_touchpad and self.enhanced_reports:
            for finger in range(2):  # pragma: no branch
                var at = offset + STATE_TOUCHPAD + 4 * finger
                var down = data[at] & 0x80 == 0
                var x = Int(data[at + 1]) | ((Int(data[at + 2]) & 0x0F) << 8)
                var y = (Int(data[at + 2]) >> 4) | (Int(data[at + 3]) << 4)
                joystick.send_touchpad(
                    0,
                    finger,
                    down,
                    Float32(x) * TOUCHPAD_SCALE_X,
                    Float32(y) * TOUCHPAD_SCALE_Y,
                    Float32(1.0) if down else Float32(0.0),
                )

        var buttons = offset + STATE_BUTTONS
        if self.last_state[STATE_BUTTONS] != data[buttons]:
            var face = Int(data[buttons]) >> 4
            joystick.send_button(BUTTON_WEST.value, face & 0x01 != 0)
            joystick.send_button(BUTTON_SOUTH.value, face & 0x02 != 0)
            joystick.send_button(BUTTON_EAST.value, face & 0x04 != 0)
            joystick.send_button(BUTTON_NORTH.value, face & 0x08 != 0)
            var direction = Int(data[buttons]) & 0x0F
            var hats: List[Int] = [
                HAT_UP,
                HAT_RIGHT | HAT_UP,
                HAT_RIGHT,
                HAT_RIGHT | HAT_DOWN,
                HAT_DOWN,
                HAT_LEFT | HAT_DOWN,
                HAT_LEFT,
                HAT_LEFT | HAT_UP,
            ]
            joystick.send_hat(0, hats[direction] if direction < 8 else 0)

        var middle = Int(data[buttons + 1])
        if Int(self.last_state[STATE_BUTTONS + 1]) != middle:
            joystick.send_button(BUTTON_LEFT_SHOULDER.value, middle & 0x01 != 0)
            joystick.send_button(
                BUTTON_RIGHT_SHOULDER.value, middle & 0x02 != 0
            )
            joystick.send_button(BUTTON_BACK.value, middle & 0x10 != 0)
            joystick.send_button(BUTTON_START.value, middle & 0x20 != 0)
            joystick.send_button(BUTTON_LEFT_STICK.value, middle & 0x40 != 0)
            joystick.send_button(BUTTON_RIGHT_STICK.value, middle & 0x80 != 0)

        # Some fight sticks, such as the Victrix FS Pro, set only these
        # digital trigger bits and not the analog values.
        if middle & 0x04 != 0 and data[offset + STATE_TRIGGER_LEFT] == 0:
            data[offset + STATE_TRIGGER_LEFT] = 255
        if middle & 0x08 != 0 and data[offset + STATE_TRIGGER_RIGHT] == 0:
            data[offset + STATE_TRIGGER_RIGHT] = 255

        if self.last_state[STATE_BUTTONS + 2] != data[buttons + 2]:
            var system = Int(data[buttons + 2]) & 0x03
            joystick.send_button(BUTTON_GUIDE.value, system & 0x01 != 0)
            joystick.send_button(BUTTON_PS4_TOUCHPAD, system & 0x02 != 0)

        var axes: List[Int] = [
            AXIS_LEFT_TRIGGER.value,
            STATE_TRIGGER_LEFT,
            AXIS_RIGHT_TRIGGER.value,
            STATE_TRIGGER_RIGHT,
            AXIS_LEFTX.value,
            0,
            AXIS_LEFTY.value,
            1,
            AXIS_RIGHTX.value,
            2,
            AXIS_RIGHTY.value,
            3,
        ]
        for index in range(0, len(axes), 2):  # pragma: no branch
            joystick.send_axis(
                axes[index], Int(data[offset + axes[index + 1]]) * 257 - 32768
            )

        if size > 9 and self.report_sensors:
            var tick = _uint16(data, offset + STATE_TIMESTAMP)
            var delta: Int
            if self.last_tick < tick:
                delta = tick - self.last_tick
            else:
                delta = (0xFFFF - self.last_tick + tick + 1) & 0xFFFF
            self.sensor_ticks += delta
            self.last_tick = tick
            # The sensor clock counts in 16/3 microseconds.
            var nanoseconds = self.sensor_ticks * 1000 * 16 // 3
            var timestamp = Duration64(Float64(nanoseconds) * 1e-9, SECOND)
            var gyro = SIMD[DType.float32, SENSOR_VALUES](0)
            var accel = SIMD[DType.float32, SENSOR_VALUES](0)
            for axis in range(3):  # pragma: no branch
                gyro[axis] = self._calibrated(
                    axis, load16(data, offset + STATE_GYRO + 2 * axis)
                )
                accel[axis] = self._calibrated(
                    3 + axis, load16(data, offset + STATE_ACCEL + 2 * axis)
                )
            joystick.send_sensor(SENSOR_GYRO, timestamp, gyro)
            joystick.send_sensor(SENSOR_ACCEL, timestamp, accel)

        for index in range(STATE_SIZE):  # pragma: no branch
            self.last_state[index] = data[offset + index]

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
        var has_joystick = device.joysticks > 0 and Bool(pad)
        var packet_count = 0
        var size = source.read(self.buffer, 0)
        while size > 0:
            if self._is_packet_valid(size):
                packet_count += 1
                self.last_packet = now
                if has_joystick:
                    if Int(self.buffer[0]) == REPORT_USB_STATE:
                        self._handle_state_packet(
                            pad.value().joystick, 1, size - 1
                        )
                    else:
                        # An enhanced Bluetooth report. With the default
                        # hint, the enhanced mode is already on.
                        self.enhanced_reports = True
                        self._handle_state_packet(
                            pad.value().joystick, 3, size - 3
                        )
            size = source.read(self.buffer, 0)

        if device.is_bluetooth:
            if packet_count == 0:
                # The pad may have gone away.
                if not (now < self.last_packet + BLUETOOTH_DISCONNECT_TIMEOUT):
                    self._tickle_bluetooth(source)
                    self.last_packet = now
            elif device.joysticks == 0 and not device.has_connected_usb_device(
                device.serial
            ):
                # Connect the Bluetooth pad again once the USB pad is gone.
                _ = device.joystick_connected()

        if self.is_dongle or self.is_nacon_dongle:
            if packet_count == 0:
                if device.joysticks > 0 and not (
                    now < self.last_packet + BLUETOOTH_DISCONNECT_TIMEOUT
                ):
                    device.joystick_disconnected()
            elif device.joysticks == 0:
                var read = _read_feature(
                    source, FEATURE_SERIAL_NUMBER, self.buffer
                )
                device.set_serial(_serial_from_report(self.buffer, read))
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
        """Make the device's joystick. SDL: `OpenJoystick`, with the two
        hint callbacks it runs at once.

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
        for index in range(STATE_SIZE):  # pragma: no branch
            self.last_state[index] = 0
        self.player_index = self.joystick_player_index
        var buttons = 12 if self.touchpad_supported else 11
        var joystick = Joystick(
            device.name, device.guid, AXIS_COUNT, buttons, 1
        )

        # SDL_PS4ReportIntervalHintChanged, with no hint set.
        if self.report_interval != DEFAULT_REPORT_INTERVAL:
            self.report_interval = DEFAULT_REPORT_INTERVAL
            # Not in the enhanced mode yet, so nothing is sent.
            _ = self._update_effects(device, source)

        # SDL_PS4EnhancedReportsChanged, with no hint set: the enhanced
        # mode is on. SDL: `SetEnhancedMode`.
        self.enhanced_mode_available = True
        if self.touchpad_supported:
            joystick.add_touchpad(2)
            self.report_touchpad = True
        if self.sensors_supported:
            var rate = Frequency(
                Float32(1000 // self.report_interval), PER_SECOND
            )
            joystick.add_sensor(SENSOR_GYRO, rate)
            joystick.add_sensor(SENSOR_ACCEL, rate)
        self.enhanced_mode = True
        # Switch to the enhanced reports.
        _ = self._update_effects(device, source)
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
        self.rumble_left = low >> 8
        self.rumble_right = high >> 8
        return self._update_effects(device, source)

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
            False: a DualShock 4 has no trigger motors.
        """
        return False

    def capabilities(self, device: HidapiDevice) -> Int:
        """Return what the pad can do. SDL: `GetJoystickCapabilities`.

        Args:
            device: The device.

        Returns:
            The `CAP_*` bits.
        """
        var result = 0
        if self.enhanced_mode_available:
            if self.lightbar_supported:
                result |= CAP_RGB_LED
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
        return self._update_effects(device, source)

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

        A joystick has sensors only when the pad supports them, and they
        come with the enhanced mode, so SDL's check for both always
        passes here.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            joystick: The joystick.
            enabled: Whether they report.

        Returns:
            True.
        """
        if enabled:
            self._load_calibration(device, source)
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
        self.enhanced_mode_available = False
