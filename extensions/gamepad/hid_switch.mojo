# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of
# src/joystick/hidapi/SDL_hidapi_switch.c, from SDL 3.2.24. It is a
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

"""The Nintendo Switch Pro Controller driver. SDL: `SDL_hidapi_switch.c`.

The driver runs the Switch Pro Controller and the pads that SDL treats as
one, over USB and Bluetooth. It also runs the wired "input only" pads,
which send reports and take no commands.

On USB the driver first sends the 0x80 handshake commands. Then it asks
the pad what it is, reads the stick and motion calibration from the pad's
SPI flash, turns on rumble and puts the pad in the full report mode, 0x30.
That report carries the buttons, the 12-bit sticks and three samples of
the gyroscope and the accelerometer. The simple report, 0x3F, carries the
buttons and 16-bit sticks. The player number shows on the four player
lights. Rumble is Nintendo's HD rumble encoding.

The hints have their default values: enhanced reports are on, the player
lights are on, the home light is left as the pad set it, and Joy-Cons are
not in vertical mode.

These parts of SDL's driver are not ported:

- The Joy-Cons, the combined Joy-Con pair and the Nintendo Online
  classic controllers have their own SDL drivers. `is_supported` refuses
  them. A pad that says it is a Joy-Con is refused when it starts.
- The hint callbacks, so a hint cannot change while a pad runs. The home
  light hint has no default, so SDL sends no home light command, and
  neither does this driver.
- `SendJoystickEffect`, the battery level and the power state.
- The macOS wait of 250 ms before the handshake.

SDL waits up to 100 ms for each reply, by the clock. This driver reads
with a 1 ms timeout and stops after 100 reads that return nothing. The
clock of the methods that get no time is the last time that
`init_device`, `open_joystick` or `update_device` got.
"""
from extensions.gamepad.controller_type import (
    CONTROLLER_SWITCH_INPUT_ONLY,
    USB_VENDOR_NINTENDO,
    guess_controller_type,
    is_joystick_gamecube,
)
from extensions.gamepad.gamepad import Gamepad
from extensions.gamepad.guid import ProductId, VendorId
from extensions.gamepad.hid import HidSource
from extensions.gamepad.hid_device import (
    CAP_PLAYER_LED,
    CAP_RUMBLE,
    HidapiDevice,
    load16,
    load32,
    remap_val,
)
from extensions.gamepad.ids import (
    GAMEPAD_TYPE_NINTENDO_SWITCH_PRO,
    GAMEPAD_TYPE_STANDARD,
    GamepadType,
)
from extensions.gamepad.joystick import (
    Joystick,
    SENSOR_ACCEL,
    SENSOR_GYRO,
    SENSOR_VALUES,
    SensorType,
)
from units.si import Duration64, Frequency, PER_SECOND, SECOND

# How often rumble can be written, and how often a long rumble must be
# written again to keep the motors running.
comptime RUMBLE_WRITE_FREQUENCY_MS = 30
comptime RUMBLE_REFRESH_FREQUENCY_MS = 50
# How long a reply can take, and how long a pad can be silent.
comptime REPLY_TIMEOUT_MS = 100
comptime USB_INPUT_TIMEOUT_MS = 100
comptime BLUETOOTH_INPUT_TIMEOUT_MS = 3000
comptime IMU_RESET_DELAY_MS = 3000
comptime IMU_UPDATE_RATE_SAMPLE_FREQUENCY = 1000
comptime NANOSECONDS_PER_MILLISECOND = 1_000_000

comptime SWITCH_GYRO_SCALE: Float32 = 14.2842
comptime SWITCH_ACCEL_SCALE: Float32 = 4096.0
comptime SWITCH_GYRO_SCALE_MULT: Float32 = 936.0
comptime SWITCH_ACCEL_SCALE_MULT: Float32 = 4.0
comptime STANDARD_GRAVITY: Float32 = 9.80665
comptime PI: Float32 = 3.141592653589793

# The input reports. SDL: `ESwitchInputReportIDs`.
comptime INPUT_SUBCOMMAND_REPLY = 0x21
comptime INPUT_FULL_STATE = 0x30
comptime INPUT_FULL_AND_MCU_STATE = 0x31
comptime INPUT_SIMPLE_STATE = 0x3F
comptime INPUT_COMMAND_ACK = 0x81

# The output reports. SDL: `ESwitchOutputReportIDs`.
comptime OUTPUT_RUMBLE_AND_SUBCOMMAND = 0x01
comptime OUTPUT_RUMBLE = 0x10
comptime OUTPUT_PROPRIETARY = 0x80

# The subcommands. SDL: `ESwitchSubcommandIDs`.
comptime SUBCOMMAND_REQUEST_DEVICE_INFO = 0x02
comptime SUBCOMMAND_SET_INPUT_REPORT_MODE = 0x03
comptime SUBCOMMAND_SPI_FLASH_READ = 0x10
comptime SUBCOMMAND_SET_PLAYER_LIGHTS = 0x30
comptime SUBCOMMAND_ENABLE_IMU = 0x40
comptime SUBCOMMAND_ENABLE_VIBRATION = 0x48

# The USB commands. SDL: `ESwitchProprietaryCommandIDs`.
comptime PROPRIETARY_STATUS = 0x01
comptime PROPRIETARY_HANDSHAKE = 0x02
comptime PROPRIETARY_HIGH_SPEED = 0x03
comptime PROPRIETARY_FORCE_USB = 0x04

# The packet sizes.
comptime OUTPUT_PACKET_DATA_LENGTH = 49
comptime MAX_OUTPUT_PACKET_LENGTH = 64
comptime BLUETOOTH_PACKET_LENGTH = OUTPUT_PACKET_DATA_LENGTH
comptime USB_PACKET_LENGTH = MAX_OUTPUT_PACKET_LENGTH
comptime RUMBLE_PACKET_LENGTH = 10

# Where the calibration is in the SPI flash.
comptime SPI_STICK_FACTORY_CALIBRATION = 0x603D
comptime SPI_STICK_FACTORY_CALIBRATION_LENGTH = 0x12
comptime SPI_STICK_USER_CALIBRATION = 0x8010
comptime SPI_STICK_USER_CALIBRATION_LENGTH = 0x16
comptime SPI_IMU_SCALE = 0x6020
comptime SPI_IMU_SCALE_LENGTH = 0x18
comptime SPI_IMU_USER_SCALE = 0x8026
comptime SPI_IMU_USER_SCALE_LENGTH = 0x14

# Where a subcommand reply's data starts in the read buffer: the report
# id, the 12-byte controller state, the acknowledgment and the id.
comptime REPLY_DATA = 15
# Where the read data of an SPI flash reply starts: after the address and
# the length.
comptime SPI_READ_DATA = REPLY_DATA + 5

# What the pad says it is. SDL: `ESwitchDeviceInfoControllerType`.
comptime SWITCH_UNKNOWN = 0
comptime SWITCH_JOYCON_LEFT = 1
comptime SWITCH_JOYCON_RIGHT = 2
comptime SWITCH_PRO_CONTROLLER = 3
comptime SWITCH_LIC_PRO_CONTROLLER = 6
comptime SWITCH_HVC_LEFT = 7
comptime SWITCH_HVC_RIGHT = 8
comptime SWITCH_NES_LEFT = 9
comptime SWITCH_NES_RIGHT = 10
comptime SWITCH_SNES = 11
comptime SWITCH_N64 = 12
comptime SWITCH_SEGA_GENESIS = 13

comptime USB_PRODUCT_NINTENDO_SWITCH_PRO = 0x2009
comptime USB_PRODUCT_NINTENDO_SNES_CONTROLLER = 0x2017
comptime USB_PRODUCT_NINTENDO_N64_CONTROLLER = 0x2019
comptime USB_PRODUCT_NINTENDO_SEGA_GENESIS_CONTROLLER = 0x201E

# The joystick's buttons and axes. SDL: `SDL_GamepadButton` and
# `SDL_GamepadAxis`, with the share button and the paddles after them.
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
comptime BUTTON_SHARE = 11
comptime BUTTON_COUNT = 16
comptime AXIS_LEFTX = 0
comptime AXIS_LEFTY = 1
comptime AXIS_RIGHTX = 2
comptime AXIS_RIGHTY = 3
comptime AXIS_LEFT_TRIGGER = 4
comptime AXIS_RIGHT_TRIGGER = 5
comptime AXIS_COUNT = 6

comptime HAT_CENTERED = 0x00
comptime HAT_UP = 0x01
comptime HAT_RIGHT = 0x02
comptime HAT_DOWN = 0x04
comptime HAT_LEFT = 0x08


def _sint16(value: Int) -> Int:
    """Wrap a number to 16 bits with a sign, as a C `Sint16` does.

    Args:
        value: The number.

    Returns:
        The number from -32768 to 32767 with the same low 16 bits.
    """
    return ((value + 0x8000) & 0xFFFF) - 0x8000


def _ticks_ns(now: Duration64) -> Int:
    """Return a time in whole nanoseconds. SDL: `SDL_GetTicksNS`.

    Args:
        now: The time.

    Returns:
        The nanoseconds.
    """
    return Int(round(now.value * 1e9))


def _amplitude_index(amplitude: Int) -> Int:
    """Return the row of the rumble amplitude table for a strength. SDL:
    the search in `EncodeRumbleHighAmplitude` and
    `EncodeRumbleLowAmplitude`, whose tables share their first column.

    Args:
        amplitude: The strength, 0 to 65535.

    Returns:
        The first row whose strength is at least the given one, 0 to 100.
    """
    var limits: List[Int] = [
        0, 514, 775, 921, 1096, 1303, 1550, 1843, 2192, 2606, 3100, 3686,
        4383, 5213, 6199, 7372, 7698, 8039, 8395, 8767, 9155, 9560, 9984,
        10426, 10887, 11369, 11873, 12398, 12947, 13520, 14119, 14744,
        15067, 15397, 15734, 16079, 16431, 16790, 17158, 17534, 17918,
        18310, 18711, 19121, 19540, 19967, 20405, 20851, 21308, 21775,
        22251, 22739, 23236, 23745, 24265, 24797, 25340, 25894, 26462,
        27041, 27633, 28238, 28856, 29488, 30134, 30794, 31468, 32157,
        32861, 33581, 34316, 35068, 35836, 36620, 37422, 38242, 39079,
        39935, 40809, 41703, 42616, 43549, 44503, 45477, 46473, 47491,
        48531, 49593, 50679, 51789, 52923, 54082, 55266, 56476, 57713,
        58977, 60268, 61588, 62936, 64315, 65535,
    ]  # fmt: skip
    var index = 0
    # The last row is 65535, so the search ends in the table.
    while amplitude > limits[index]:
        index += 1
    return index


def encode_rumble_high_amplitude(amplitude: Int) -> Int:
    """Return the high band amplitude code of a strength. SDL:
    `EncodeRumbleHighAmplitude`.

    Args:
        amplitude: The strength, 0 to 65535.

    Returns:
        The code, 0x00 to 0xC8. It goes up by 2 for each table row.
    """
    return 2 * _amplitude_index(amplitude)


def encode_rumble_low_amplitude(amplitude: Int) -> Int:
    """Return the low band amplitude code of a strength. SDL:
    `EncodeRumbleLowAmplitude`.

    Args:
        amplitude: The strength, 0 to 65535.

    Returns:
        The 16-bit code, 0x0040 to 0x0072. Each pair of table rows has one
        low byte; the second row of the pair also sets bit 15.
    """
    var index = _amplitude_index(amplitude)
    return ((index & 1) << 15) | (0x40 + index // 2)


def _hex2(value: UInt8) -> String:
    """Write a byte as two lowercase hexadecimal digits, as `%.2x` does.

    Args:
        value: The byte.

    Returns:
        The digits.
    """
    comptime DIGITS = "0123456789abcdef"
    return String(DIGITS[byte=Int(value >> 4)]) + String(
        DIGITS[byte=Int(value & 15)]
    )


def _is_other_nintendo_driver(product: Int) -> Bool:
    """Return True for a Nintendo product that another SDL driver runs.
    SDL: `HIDAPI_DriverNintendoClassic_IsSupportedDevice` and
    `HIDAPI_DriverJoyCons_IsSupportedDevice`, without an open device.

    Args:
        product: The USB product id.

    Returns:
        Whether it is a Joy-Con, the charging grip or a Nintendo Online
        classic controller.
    """
    var products: List[Int] = [
        0x2006, 0x2007, 0x200E, USB_PRODUCT_NINTENDO_SNES_CONTROLLER,
        USB_PRODUCT_NINTENDO_N64_CONTROLLER,
        USB_PRODUCT_NINTENDO_SEGA_GENESIS_CONTROLLER,
    ]  # fmt: skip
    return product in products


def _is_nintendo_pro(vendor: VendorId, product: ProductId) -> Bool:
    """Return True for the ids of Nintendo's Switch Pro Controller.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        Whether they are 057E:2009.
    """
    return (vendor.value << 16) | product.value == (
        USB_VENDOR_NINTENDO.value << 16
    ) | USB_PRODUCT_NINTENDO_SWITCH_PRO


def _is_classic(controller_type: Int) -> Bool:
    """Return True for a Nintendo Online classic controller. SDL: the
    controller types that `OpenJoystick` reads no motion calibration for.

    Args:
        controller_type: What the pad says it is.

    Returns:
        Whether it is a classic controller, which has no motion sensors.
    """
    return (
        controller_type >= SWITCH_HVC_LEFT
        and controller_type <= SWITCH_SEGA_GENESIS
    )


def _always_uses_labels(
    vendor: VendorId, product: ProductId, controller_type: Int
) -> Bool:
    """Return True for a pad whose face buttons are not a diamond. SDL:
    `AlwaysUsesLabels`.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.
        controller_type: What the pad says it is.

    Returns:
        Whether the buttons go by their labels.
    """
    if is_joystick_gamecube(vendor, product):
        return True
    return _is_classic(controller_type) and controller_type != SWITCH_SNES


struct SwitchDriver(Movable):
    """The Nintendo Switch Pro driver's state. SDL: `SDL_DriverSwitch_Context`.
    """

    # Whether the driver connected a joystick to the device. SDL:
    # `ctx->joystick`.
    var has_joystick: Bool
    var bluetooth: Bool
    var vendor: VendorId
    var product: ProductId
    var input_only: Bool
    var use_button_labels: Bool
    var player_lights: Bool
    var player_index: Int
    # The joystick's player number, which the pad shows once it is open.
    # SDL: `SDL_GetJoystickPlayerIndex`.
    var joystick_player_index: Int
    var max_write_attempts: Int
    var controller_type: Int
    var initial_input_mode: Int
    var current_input_mode: Int
    var mac_address: List[UInt8]
    var command_number: Int
    var enhanced_mode: Bool
    var enhanced_mode_available: Bool
    # The last rumble report: its id, its number and the rumble data of
    # both motors. Subcommands repeat the rumble data.
    var rumble_packet: List[UInt8]
    var read_buffer: List[UInt8]
    var rumble_active: Bool
    # SDL's integer clock: the milliseconds of `SDL_GetTicks`, and the
    # nanoseconds of `SDL_GetTicksNS`.
    var rumble_sent_ms: Int
    var rumble_pending: Bool
    var rumble_zero_pending: Bool
    var rumble_pending_value: Int
    var sensors_supported: Bool
    var report_sensors: Bool
    var has_sensor_data: Bool
    var last_input_ms: Int
    var last_imu_reset_ms: Int
    var imu_sample_timestamp_ns: Int
    var imu_samples: Int
    var imu_update_interval_ns: Int
    var timestamp_ns: Int
    # The time the driver last got.
    var now_ns: Int
    # The buttons, hat and sticks of the last input only report.
    var last_input_only_state: List[UInt8]
    # The buttons and hat of the last simple report.
    var last_simple_state: List[UInt8]
    # The buttons of the last full report.
    var last_full_state: List[UInt8]
    # The calibration of each stick and axis: the center, the distance
    # below it and the distance above it. Index `(stick * 2 + axis) * 3`.
    var stick_calibration: List[Int]
    # The range seen on each stick and axis: the lowest and the highest.
    # Index `(stick * 2 + axis) * 2`.
    var stick_extents: List[Int]
    var simple_stick_extents: List[Int]
    # The accelerometer scales x, y and z, then the gyroscope scales.
    var imu_scale: List[Float32]

    def __init__(out self):
        """Create the state of a device the driver has not seen."""
        self.has_joystick = False
        self.bluetooth = False
        self.vendor = VendorId(0)
        self.product = ProductId(0)
        self.input_only = False
        self.use_button_labels = False
        self.player_lights = False
        self.player_index = 0
        self.joystick_player_index = -1
        self.max_write_attempts = 5
        self.controller_type = SWITCH_UNKNOWN
        self.initial_input_mode = 0
        self.current_input_mode = 0
        self.mac_address = List[UInt8](length=6, fill=0)
        self.command_number = 0
        self.enhanced_mode = False
        self.enhanced_mode_available = False
        self.rumble_packet = List[UInt8](length=RUMBLE_PACKET_LENGTH, fill=0)
        self.read_buffer = List[UInt8](length=MAX_OUTPUT_PACKET_LENGTH, fill=0)
        self.rumble_active = False
        self.rumble_sent_ms = 0
        self.rumble_pending = False
        self.rumble_zero_pending = False
        self.rumble_pending_value = 0
        self.sensors_supported = False
        self.report_sensors = False
        self.has_sensor_data = False
        self.last_input_ms = 0
        self.last_imu_reset_ms = 0
        self.imu_sample_timestamp_ns = 0
        self.imu_samples = 0
        self.imu_update_interval_ns = 0
        self.timestamp_ns = 0
        self.now_ns = 0
        self.last_input_only_state = List[UInt8](length=7, fill=0)
        self.last_simple_state = List[UInt8](length=3, fill=0)
        self.last_full_state = List[UInt8](length=3, fill=0)
        self.stick_calibration = List[Int](length=12, fill=0)
        self.stick_extents = List[Int](length=8, fill=0)
        self.simple_stick_extents = List[Int](length=8, fill=0)
        self.imu_scale = List[Float32](length=6, fill=0)

    def _now_ms(self) -> Int:
        """Return the driver's clock in milliseconds. SDL: `SDL_GetTicks`.

        Returns:
            The milliseconds.
        """
        return self.now_ns // NANOSECONDS_PER_MILLISECOND

    # ----- Reports -----

    def _read_input[S: HidSource](mut self, mut source: S, wait: Int) -> Int:
        """Read one report, and learn the pad's input mode from the first.
        SDL: `ReadInput`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            wait: How many milliseconds to wait for a report.

        Returns:
            The report's length, 0 when none came, or -1 on an error.
        """
        var result = source.read(self.read_buffer, wait)
        if result > 0 and not self.input_only and self.initial_input_mode == 0:
            var id = Int(self.read_buffer[0])
            if (
                id == INPUT_FULL_STATE
                or id == INPUT_FULL_AND_MCU_STATE
                or id == INPUT_SIMPLE_STATE
            ):
                self.initial_input_mode = id
        return result

    def _read_subcommand_reply[
        S: HidSource
    ](mut self, mut source: S, expected: Int) -> Bool:
        """Wait for the reply to a subcommand. SDL: `ReadSubcommandReply`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            expected: The subcommand.

        Returns:
            Whether the reply came. The read buffer holds it.
        """
        # SDL waits 1 ms after each read that finds nothing.
        var waited = 0
        while waited < REPLY_TIMEOUT_MS:
            var count = self._read_input(source, 1)
            if count < 0:
                return False
            if count == 0:
                waited += 1
            elif Int(self.read_buffer[0]) == INPUT_SUBCOMMAND_REPLY:
                if (
                    Int(self.read_buffer[14]) == expected
                    and self.read_buffer[13] & 0x80 != 0
                ):
                    return True
        return False

    def _read_proprietary_reply[
        S: HidSource
    ](mut self, mut source: S, expected: Int) -> Bool:
        """Wait for the reply to a USB command. SDL: `ReadProprietaryReply`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            expected: The command.

        Returns:
            Whether the reply came. The read buffer holds it.
        """
        # SDL waits 1 ms after each read that finds nothing.
        var waited = 0
        while waited < REPLY_TIMEOUT_MS:
            var count = self._read_input(source, 1)
            if count < 0:
                return False
            if count == 0:
                waited += 1
            elif (
                Int(self.read_buffer[0]) == INPUT_COMMAND_ACK
                and Int(self.read_buffer[1]) == expected
            ):
                return True
        return False

    def _write_packet[
        S: HidSource
    ](self, mut source: S, packet: List[UInt8]) -> Bool:
        """Write a packet, padded to the bus's report size. SDL:
        `WritePacket`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            packet: The packet, at most 49 bytes.

        Returns:
            Whether the write worked.
        """
        var size = (
            BLUETOOTH_PACKET_LENGTH if self.bluetooth else USB_PACKET_LENGTH
        )
        var data = packet.copy()
        while len(data) < size:
            data.append(0)
        return source.write(data) >= 0

    def _write_subcommand[
        S: HidSource
    ](mut self, mut source: S, command: Int, payload: List[UInt8]) -> Bool:
        """Send a subcommand until it is answered. SDL: `WriteSubcommand`
        and `ConstructSubcommand`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            command: The subcommand.
            payload: Its data.

        Returns:
            Whether the pad answered. The read buffer holds the reply.
        """
        var reply = False
        var tries = 1
        while not reply and tries <= self.max_write_attempts:
            var packet = List[UInt8](length=OUTPUT_PACKET_DATA_LENGTH, fill=0)
            packet[0] = OUTPUT_RUMBLE_AND_SUBCOMMAND
            packet[1] = UInt8(self.command_number)
            for index in range(8):  # pragma: no branch
                packet[2 + index] = self.rumble_packet[2 + index]
            packet[10] = UInt8(command)
            for index in range(len(payload)):
                packet[11 + index] = payload[index]
            self.command_number = (self.command_number + 1) & 0xF
            if self._write_packet(source, packet):
                reply = self._read_subcommand_reply(source, command)
            tries += 1
        return reply

    def _write_proprietary[
        S: HidSource
    ](mut self, mut source: S, command: Int, wait_for_reply: Bool) -> Bool:
        """Send a USB command until it is answered. SDL: `WriteProprietary`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            command: The command.
            wait_for_reply: Whether the pad answers it.

        Returns:
            Whether the write worked and, if one was awaited, the reply
            came.
        """
        for _ in range(self.max_write_attempts):  # pragma: no branch
            var packet = List[UInt8](length=OUTPUT_PACKET_DATA_LENGTH, fill=0)
            packet[0] = OUTPUT_PROPRIETARY
            packet[1] = UInt8(command)
            if not self._write_packet(source, packet):
                continue
            if not wait_for_reply or self._read_proprietary_reply(
                source, command
            ):
                return True
        return False

    def _set_neutral_rumble(mut self):
        """Set both motors to rest. SDL: `SetNeutralRumble`, twice."""
        for motor in range(2):  # pragma: no branch
            self.rumble_packet[2 + 4 * motor] = 0x00
            self.rumble_packet[3 + 4 * motor] = 0x01
            self.rumble_packet[4 + 4 * motor] = 0x40
            self.rumble_packet[5 + 4 * motor] = 0x40

    def _write_rumble[S: HidSource](mut self, mut source: S) -> Bool:
        """Send the rumble report. SDL: `WriteRumble`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.

        Returns:
            Whether the write worked.
        """
        self.rumble_packet[0] = OUTPUT_RUMBLE
        self.rumble_packet[1] = UInt8(self.command_number)
        self.command_number = (self.command_number + 1) & 0xF
        self.rumble_sent_ms = self._now_ms()
        return self._write_packet(source, self.rumble_packet)

    # ----- Device information -----

    @staticmethod
    def _read_joycon_controller_type[
        S: HidSource
    ](mut source: S, device: HidapiDevice) -> Int:
        """Ask a pad what it is, with a context of its own. SDL:
        `ReadJoyConControllerType`, which tries once.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            device: What is known about it.

        Returns:
            What the pad says it is, or `SWITCH_UNKNOWN` when it does not
            answer.
        """
        var probe = SwitchDriver()
        probe.bluetooth = device.is_bluetooth
        if device.is_bluetooth:
            if probe._write_subcommand(
                source, SUBCOMMAND_REQUEST_DEVICE_INFO, List[UInt8]()
            ):
                return Int(probe.read_buffer[REPLY_DATA + 2])
        elif probe._write_proprietary(source, PROPRIETARY_STATUS, True):
            return Int(probe.read_buffer[3])
        return SWITCH_UNKNOWN

    def _read_device_info[S: HidSource](mut self, mut source: S):
        """Learn what the pad is and its MAC address. SDL:
        `BReadDeviceInfo`.

        A Pro Controller id never belongs to the N64 controller or to the
        charging grip, so SDL's `CalculateControllerType` keeps the type.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
        """
        if self.bluetooth:
            if self._write_subcommand(
                source, SUBCOMMAND_REQUEST_DEVICE_INFO, List[UInt8]()
            ):
                self.controller_type = Int(self.read_buffer[REPLY_DATA + 2])
                for index in range(6):  # pragma: no branch
                    self.mac_address[index] = self.read_buffer[
                        REPLY_DATA + 4 + index
                    ]
        elif self._write_proprietary(source, PROPRIETARY_STATUS, True):
            self.controller_type = Int(self.read_buffer[3])
            for index in range(6):  # pragma: no branch
                self.mac_address[index] = self.read_buffer[9 - index]

    def _update_device_identity(mut self, mut device: HidapiDevice) raises:
        """Name the device for what it is. SDL: `UpdateDeviceIdentity`.

        Args:
            device: The device.

        Raises:
            Error: If the GUID cannot be made, which a valid version never
                causes.
        """
        if self.input_only:
            if is_joystick_gamecube(self.vendor, self.product):
                device.type = GAMEPAD_TYPE_STANDARD
            return
        var nintendo = USB_VENDOR_NINTENDO
        var type = self.controller_type
        if type == SWITCH_PRO_CONTROLLER or type == SWITCH_LIC_PRO_CONTROLLER:
            device.set_name("Nintendo Switch Pro Controller")
            device.set_product(
                nintendo, ProductId(USB_PRODUCT_NINTENDO_SWITCH_PRO)
            )
            device.type = GAMEPAD_TYPE_NINTENDO_SWITCH_PRO
        elif type == SWITCH_UNKNOWN:
            # The pad did not answer, so it may not follow the protocol.
            if _is_nintendo_pro(self.vendor, self.product):
                self.controller_type = SWITCH_PRO_CONTROLLER
                device.set_name("Nintendo Switch Pro Controller")
                device.type = GAMEPAD_TYPE_NINTENDO_SWITCH_PRO
            return
        else:
            device.type = GAMEPAD_TYPE_STANDARD
            if type == SWITCH_HVC_LEFT:
                device.set_name("Nintendo HVC Controller (1)")
            elif type == SWITCH_HVC_RIGHT:
                device.set_name("Nintendo HVC Controller (2)")
            elif type == SWITCH_NES_LEFT:
                device.set_name("Nintendo NES Controller (L)")
            elif type == SWITCH_NES_RIGHT:
                device.set_name("Nintendo NES Controller (R)")
            elif type == SWITCH_SNES:
                device.set_name("Nintendo SNES Controller")
                device.set_product(
                    nintendo, ProductId(USB_PRODUCT_NINTENDO_SNES_CONTROLLER)
                )
            elif type == SWITCH_N64:
                device.set_name("Nintendo N64 Controller")
                device.set_product(
                    nintendo, ProductId(USB_PRODUCT_NINTENDO_N64_CONTROLLER)
                )
            elif type == SWITCH_SEGA_GENESIS:
                device.set_name("Nintendo SEGA Genesis Controller")
                device.set_product(
                    nintendo,
                    ProductId(USB_PRODUCT_NINTENDO_SEGA_GENESIS_CONTROLLER),
                )
        device.guid.data[15] = UInt8(self.controller_type)
        var serial = _hex2(self.mac_address[0])
        for index in range(1, 6):  # pragma: no branch
            serial += "-" + _hex2(self.mac_address[index])
        device.set_serial(serial)

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
            Whether the driver may run it.
        """
        # The HORI Wireless Switch Pad has the ids of its Bluetooth self
        # on USB, where it does not answer. Its USB name tells them apart.
        if name == "HORI Wireless Switch Pad":
            return False
        if vendor == USB_VENDOR_NINTENDO and _is_other_nintendo_driver(
            product.value
        ):
            return False
        return type == GAMEPAD_TYPE_NINTENDO_SWITCH_PRO

    @staticmethod
    def is_supported_device[
        S: HidSource
    ](mut source: S, device: HidapiDevice) -> Bool:
        """Return True if the driver runs an open device. SDL:
        `IsSupportedDevice` with the device open.

        A Kinvoca Joy-Con has the ids of a Pro Controller. SDL asks a pad
        with those ids what it is twice: once for the Joy-Con driver,
        which comes first, and once for this driver.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            device: What is known about it.

        Returns:
            Whether the driver runs it: False for a Joy-Con.
        """
        if _is_nintendo_pro(device.vendor, device.product):
            for _ in range(2):  # pragma: no branch
                var type = SwitchDriver._read_joycon_controller_type(
                    source, device
                )
                if type == SWITCH_JOYCON_LEFT or type == SWITCH_JOYCON_RIGHT:
                    return False
        return True

    def init_device[
        S: HidSource
    ](
        mut self, mut device: HidapiDevice, mut source: S, now: Duration64
    ) -> Bool:
        """Start the driver on a device. SDL: `InitDevice`.

        SDL asks an open device whether the driver runs it before it
        starts the driver, so this does that first. SDL then reads the
        device's waiting reports, so this does that last.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            now: The time now.

        Returns:
            Whether the driver runs the device.
        """
        self.now_ns = _ticks_ns(now)
        self.bluetooth = device.is_bluetooth
        self.vendor = device.vendor
        self.product = device.product
        if not Self.is_supported_device(source, device):
            return False
        self.input_only = (
            guess_controller_type(device.vendor, device.product)
            == CONTROLLER_SWITCH_INPUT_ONLY
        )
        if not self.input_only:
            # The MOBAPAD M073 needs rest rumble data to answer.
            self._set_neutral_rumble()
            self._read_device_info(source)
        if (
            self.controller_type == SWITCH_JOYCON_LEFT
            or self.controller_type == SWITCH_JOYCON_RIGHT
        ):
            # SDL's Joy-Con handling is not ported.
            return False
        try:
            self._update_device_identity(device)
        except:
            return False
        # Prefer the USB device over the Bluetooth device.
        if not device.is_bluetooth:
            var serial = device.serial
            device.disconnect_bluetooth_device(serial)
            _ = device.joystick_connected()
        elif not device.has_connected_usb_device(device.serial):
            _ = device.joystick_connected()
        var no_pad = Optional[Gamepad](None)
        _ = self.update_device(device, source, no_pad, now)
        return True

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
        if not self.has_joystick:
            return
        self.player_index = player_index
        self._update_slot_led(source)

    def _update_slot_led[S: HidSource](mut self, mut source: S):
        """Light the player light of the player number. SDL:
        `UpdateSlotLED`, with the player lights on.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
        """
        if self.input_only:
            return
        var led: UInt8 = 0
        if self.player_index >= 0:
            led = UInt8(1 << (self.player_index % 4))
        _ = self._write_subcommand(source, SUBCOMMAND_SET_PLAYER_LIGHTS, [led])

    # ----- Opening -----

    def _try_setup_usb[S: HidSource](mut self, mut source: S) -> Bool:
        """Send the USB handshake. SDL: `BTrySetupUSB`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.

        Returns:
            Whether the pad answered the first handshake. The writes
            after it cannot fail when it worked.
        """
        if not self._write_proprietary(source, PROPRIETARY_HANDSHAKE, True):
            return False
        # The 8BitDo M30 and SF30 Pro do not answer this.
        _ = self._write_proprietary(source, PROPRIETARY_HIGH_SPEED, True)
        # The right Joy-Con in the charging grip does not answer this.
        _ = self._write_proprietary(source, PROPRIETARY_HANDSHAKE, True)
        return self._write_proprietary(source, PROPRIETARY_FORCE_USB, False)

    def _spi_read[
        S: HidSource
    ](mut self, mut source: S, address: Int, length: Int) -> Bool:
        """Read the pad's SPI flash. SDL: `WriteSubcommand` with
        `k_eSwitchSubcommandIDs_SPIFlashRead`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            address: Where to read.
            length: How many bytes to read.

        Returns:
            Whether the pad answered. The data is at `SPI_READ_DATA` in the
            read buffer.
        """
        var payload: List[UInt8] = [
            UInt8(address & 0xFF),
            UInt8((address >> 8) & 0xFF),
            UInt8((address >> 16) & 0xFF),
            UInt8((address >> 24) & 0xFF),
            UInt8(length),
        ]
        return self._write_subcommand(
            source, SUBCOMMAND_SPI_FLASH_READ, payload
        )

    def _has_user_magic(self, offset: Int) -> Bool:
        """Return True if the user calibration of a stick is set. SDL: the
        magic byte test in `LoadStickCalibration`.

        Args:
            offset: Where the stick's magic bytes are in the read buffer.

        Returns:
            Whether they are 0xB2 0xA1.
        """
        if self.read_buffer[offset] != 0xB2:
            return False
        return self.read_buffer[offset + 1] == 0xA1

    def _load_stick_calibration[S: HidSource](mut self, mut source: S) -> Bool:
        """Read the stick calibration: the user's, else the factory's. SDL:
        `LoadStickCalibration`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.

        Returns:
            Whether a calibration was read.
        """
        # The user calibration is not readable on all pads.
        var user = self._spi_read(
            source,
            SPI_STICK_USER_CALIBRATION,
            SPI_STICK_USER_CALIBRATION_LENGTH,
        )
        var found = 0
        if user:
            if self._has_user_magic(SPI_READ_DATA):
                found += 1
            if self._has_user_magic(SPI_READ_DATA + 11):
                found += 1
        var left = SPI_READ_DATA + 2
        var right = SPI_READ_DATA + 13
        if found < 2:
            var attempt = 0
            while True:
                if not self._spi_read(
                    source,
                    SPI_STICK_FACTORY_CALIBRATION,
                    SPI_STICK_FACTORY_CALIBRATION_LENGTH,
                ):
                    return False
                if (
                    load32(self.read_buffer, REPLY_DATA)
                    == SPI_STICK_FACTORY_CALIBRATION
                ):
                    left = SPI_READ_DATA
                    right = SPI_READ_DATA + 9
                    break
                if attempt == 3:
                    return False
                attempt += 1
        # Each value is 12 bits. The left stick has the maxima, the
        # centers and the minima; the right stick the centers, the minima
        # and the maxima.
        var order: List[Int] = [2, 0, 1, 0, 1, 2]
        for stick in range(2):  # pragma: no branch
            var at = left if stick == 0 else right
            for group in range(3):  # pragma: no branch
                var b0 = Int(self.read_buffer[at + 3 * group])
                var b1 = Int(self.read_buffer[at + 3 * group + 1])
                var b2 = Int(self.read_buffer[at + 3 * group + 2])
                var field = order[stick * 3 + group]
                self.stick_calibration[stick * 6 + field] = (
                    (b1 << 8) & 0xF00
                ) | b0
                self.stick_calibration[stick * 6 + 3 + field] = (b2 << 4) | (
                    b1 >> 4
                )
        # Values the flash never had are 0xFFF.
        for index in range(4):  # pragma: no branch
            var at = index * 3
            if self.stick_calibration[at] == 0xFFF:
                self.stick_calibration[at] = 2048
            var guess = Int(Float32(self.stick_calibration[at]) * Float32(0.7))
            for field in range(1, 3):  # pragma: no branch
                if self.stick_calibration[at + field] == 0xFFF:
                    self.stick_calibration[at + field] = guess
        for index in range(4):  # pragma: no branch
            self.stick_extents[index * 2] = -Int(
                Float32(self.stick_calibration[index * 3 + 1]) * Float32(0.7)
            )
            self.stick_extents[index * 2 + 1] = Int(
                Float32(self.stick_calibration[index * 3 + 2]) * Float32(0.7)
            )
            self.simple_stick_extents[index * 2] = Int(
                Float32(-32768) * Float32(0.5)
            )
            self.simple_stick_extents[index * 2 + 1] = Int(
                Float32(32767) * Float32(0.5)
            )
        return True

    def _scale_word(self, offset: Int) -> Float32:
        """Read a 16-bit calibration word, as a C `Sint16` would.

        Args:
            offset: Where it is in the read buffer.

        Returns:
            The word with its sign.
        """
        return Float32(load16(self.read_buffer, offset))

    def _load_imu_calibration[S: HidSource](mut self, mut source: S):
        """Read the motion calibration: the factory's, with the user's
        offsets when they are set. SDL: `LoadIMUCalibration`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
        """
        if not self._spi_read(source, SPI_IMU_SCALE, SPI_IMU_SCALE_LENGTH):
            var accel = STANDARD_GRAVITY / SWITCH_ACCEL_SCALE
            var gyro = PI / Float32(180.0) / SWITCH_GYRO_SCALE
            for axis in range(3):  # pragma: no branch
                self.imu_scale[axis] = accel
                self.imu_scale[3 + axis] = gyro
            return
        var data = SPI_READ_DATA
        var accel_raw = List[Float32](length=3, fill=0)
        var accel_coefficient = List[Float32](length=3, fill=0)
        var gyro_raw = List[Float32](length=3, fill=0)
        var gyro_coefficient = List[Float32](length=3, fill=0)
        for axis in range(3):  # pragma: no branch
            accel_raw[axis] = self._scale_word(data + 2 * axis)
            accel_coefficient[axis] = self._scale_word(data + 6 + 2 * axis)
            gyro_raw[axis] = self._scale_word(data + 12 + 2 * axis)
            gyro_coefficient[axis] = self._scale_word(data + 18 + 2 * axis)
        # The user calibration overrides the factory offsets when it is set.
        if self._spi_read(
            source, SPI_IMU_USER_SCALE, SPI_IMU_USER_SCALE_LENGTH
        ):
            if load16(self.read_buffer, data) & 0xFFFF == 0xA1B2:
                for axis in range(3):  # pragma: no branch
                    accel_raw[axis] = self._scale_word(data + 2 + 2 * axis)
                    gyro_raw[axis] = self._scale_word(data + 14 + 2 * axis)
        for axis in range(3):  # pragma: no branch
            self.imu_scale[axis] = (
                SWITCH_ACCEL_SCALE_MULT
                / (accel_coefficient[axis] - accel_raw[axis])
                * STANDARD_GRAVITY
            )
            self.imu_scale[3 + axis] = (
                SWITCH_GYRO_SCALE_MULT
                / (gyro_coefficient[axis] - gyro_raw[axis])
                * PI
                / Float32(180.0)
            )

    def _input_mode(self) -> Int:
        """Return the report mode the pad must be in. SDL:
        `GetDefaultInputMode` with enhanced reports on, which gives the
        same mode as `GetSensorInputMode`.

        Returns:
            The full report, unless the pad started in another full mode.
        """
        if (
            self.initial_input_mode == 0
            or self.initial_input_mode == INPUT_SIMPLE_STATE
        ):
            return INPUT_FULL_STATE
        return self.initial_input_mode

    def _set_input_mode[
        S: HidSource
    ](mut self, mut source: S, input_mode: Int) -> Bool:
        """Put the pad in a report mode. SDL: `SetInputMode`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            input_mode: The report.

        Returns:
            Whether the pad is in the mode.
        """
        if input_mode == self.current_input_mode:
            return True
        self.current_input_mode = input_mode
        return self._write_subcommand(
            source, SUBCOMMAND_SET_INPUT_REPORT_MODE, [UInt8(input_mode)]
        )

    def open_joystick[
        S: HidSource
    ](
        mut self, mut device: HidapiDevice, mut source: S, now: Duration64
    ) raises -> Joystick:
        """Make the device's joystick. SDL: `OpenJoystick`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            now: The time now.

        Returns:
            The joystick, with its touchpads and sensors.

        Raises:
            Error: If the joystick cannot be opened.
        """
        self.now_ns = _ticks_ns(now)
        self.has_joystick = True
        var joystick = Joystick(
            device.name, device.guid, AXIS_COUNT, BUTTON_COUNT, 1
        )
        if not self.input_only:
            if self.initial_input_mode == 0:
                # This learns the report mode, when a report waits.
                _ = self._read_input(source, 0)
            self.current_input_mode = self.initial_input_mode
            self._set_neutral_rumble()
            if not self.bluetooth:
                if not self._try_setup_usb(source):
                    device.joystick_disconnected()
                    raise Error("Couldn't setup USB mode")
            if not self._load_stick_calibration(source):
                device.joystick_disconnected()
                raise Error("Couldn't load stick calibration")
            if not _is_classic(self.controller_type):
                # SDL's LoadIMUCalibration always succeeds.
                self._load_imu_calibration(source)
                self.sensors_supported = True
            _ = self._write_subcommand(
                source, SUBCOMMAND_ENABLE_VIBRATION, [UInt8(1)]
            )
            # SDL_EnhancedReportsChanged, with enhanced reports on.
            self.enhanced_mode_available = True
            if self.sensors_supported:
                joystick.add_sensor(SENSOR_GYRO, Frequency(200.0, PER_SECOND))
                joystick.add_sensor(SENSOR_ACCEL, Frequency(200.0, PER_SECOND))
            self.enhanced_mode = True
            _ = self._set_input_mode(source, self._input_mode())
            if not self.bluetooth:
                # This has no reply. Writes work here, as the handshake's did.
                _ = self._write_proprietary(
                    source, PROPRIETARY_FORCE_USB, False
                )
        if _always_uses_labels(self.vendor, self.product, self.controller_type):
            self.use_button_labels = True
        self.player_index = self.joystick_player_index
        self.player_lights = True
        self._update_slot_led(source)
        self.last_input_ms = self._now_ms()
        self.last_imu_reset_ms = self.last_input_ms
        self.imu_update_interval_ns = 5 * NANOSECONDS_PER_MILLISECOND
        return joystick^

    # ----- Rumble, lights and sensors -----

    def _actually_rumble[
        S: HidSource
    ](mut self, mut source: S, low: Int, high: Int) -> Bool:
        """Encode and send rumble. SDL:
        `HIDAPI_DriverSwitch_ActuallyRumbleJoystick`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            low: The low frequency strength, 0 to 65535.
            high: The high frequency strength, 0 to 65535.

        Returns:
            Whether the write worked.
        """
        if low != 0 or high != 0:
            # SDL's EncodeRumble. The low band amplitude code is never 0,
            # so the motors always get the encoded values.
            var high_amplitude = encode_rumble_high_amplitude(high)
            var low_amplitude = encode_rumble_low_amplitude(low)
            for motor in range(2):  # pragma: no branch
                self.rumble_packet[2 + 4 * motor] = 0x74
                self.rumble_packet[3 + 4 * motor] = UInt8(high_amplitude)
                self.rumble_packet[4 + 4 * motor] = UInt8(
                    0x3D | ((low_amplitude >> 8) & 0x80)
                )
                self.rumble_packet[5 + 4 * motor] = UInt8(low_amplitude & 0xFF)
            self.rumble_active = True
        else:
            self._set_neutral_rumble()
            self.rumble_active = False
        return self._write_rumble(source)

    def _send_pending_rumble[S: HidSource](mut self, mut source: S) -> Bool:
        """Send the rumble that waited for the write interval. SDL:
        `HIDAPI_DriverSwitch_SendPendingRumble`.

        It runs only when rumble or a stop waits.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.

        Returns:
            Whether the write worked, or True when it is too soon.
        """
        if self._now_ms() < self.rumble_sent_ms + RUMBLE_WRITE_FREQUENCY_MS:
            return True
        if self.rumble_pending:
            var low = self.rumble_pending_value >> 16
            var high = self.rumble_pending_value & 0xFFFF
            self.rumble_pending = False
            self.rumble_pending_value = 0
            return self._actually_rumble(source, low, high)
        self.rumble_zero_pending = False
        return self._actually_rumble(source, 0, 0)

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
        if self.input_only:
            return False
        if self.rumble_pending:
            if not self._send_pending_rumble(source):
                return False
        if self._now_ms() < self.rumble_sent_ms + RUMBLE_WRITE_FREQUENCY_MS:
            if low != 0 or high != 0:
                # Keep the strongest rumble of the interval.
                var pending = (low << 16) | high
                if pending > self.rumble_pending_value:
                    self.rumble_pending_value = pending
                self.rumble_pending = True
                self.rumble_zero_pending = False
            else:
                # Stop when the interval ends.
                self.rumble_zero_pending = True
            return True
        return self._actually_rumble(source, low, high)

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
            False: the pad has no trigger motors.
        """
        return False

    def capabilities(self, device: HidapiDevice) -> Int:
        """Return what the pad can do. SDL: `GetJoystickCapabilities`.

        Args:
            device: The device.

        Returns:
            The `CAP_*` bits. An input only pad never says what it is, so
            only a pad that takes commands can be a Pro Controller.
        """
        var result = 0
        if self.player_lights and not self.input_only:
            result |= CAP_PLAYER_LED
        if self.controller_type == SWITCH_PRO_CONTROLLER:
            # It has no RGB light.
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
        """Set the light. SDL: `SetJoystickLED`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            red: The red level, 0 to 255.
            green: The green level.
            blue: The blue level.

        Returns:
            False: the pad has no color light.
        """
        return False

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
        if not self.sensors_supported:
            return False
        if enabled and not self.enhanced_mode:
            return False
        self.report_sensors = enabled
        self.imu_samples = 0
        self.imu_sample_timestamp_ns = self.now_ns
        _ = self._set_input_mode(source, self._input_mode())
        _ = self._write_subcommand(
            source, SUBCOMMAND_ENABLE_IMU, [UInt8(1 if enabled else 0)]
        )
        return True

    # ----- Input -----

    def _remap_button(self, button: Int) -> Int:
        """Swap the face buttons of a pad that goes by its labels. SDL:
        `RemapButton`.

        Args:
            button: A face button by position.

        Returns:
            The button by label, or by position.
        """
        if self.use_button_labels:
            return button ^ 1
        return button

    def _hat_from_direction(self, direction: Int) -> Int:
        """Return the hat bits of a direction 0 to 7, from up clockwise.

        Args:
            direction: The direction, or another number for none.

        Returns:
            The hat bits.
        """
        var hats: List[Int] = [
            HAT_UP, HAT_UP | HAT_RIGHT, HAT_RIGHT, HAT_RIGHT | HAT_DOWN,
            HAT_DOWN, HAT_LEFT | HAT_DOWN, HAT_LEFT, HAT_LEFT | HAT_UP,
        ]  # fmt: skip
        if direction < 8:
            return hats[direction]
        return HAT_CENTERED

    def _handle_input_only_state(mut self, mut joystick: Joystick):
        """Read an input only pad's report. SDL:
        `HandleInputOnlyControllerState`.

        Args:
            joystick: The joystick.
        """
        ref data = self.read_buffer
        ref last = self.last_input_only_state
        if data[0] != last[0]:
            var bits = data[0]
            joystick.send_button(
                self._remap_button(BUTTON_SOUTH), bits & 0x02 != 0
            )
            joystick.send_button(
                self._remap_button(BUTTON_EAST), bits & 0x04 != 0
            )
            joystick.send_button(
                self._remap_button(BUTTON_WEST), bits & 0x01 != 0
            )
            joystick.send_button(
                self._remap_button(BUTTON_NORTH), bits & 0x08 != 0
            )
            joystick.send_button(BUTTON_LEFT_SHOULDER, bits & 0x10 != 0)
            joystick.send_button(BUTTON_RIGHT_SHOULDER, bits & 0x20 != 0)
        if data[1] != last[1]:
            var bits = data[1]
            joystick.send_button(BUTTON_BACK, bits & 0x01 != 0)
            joystick.send_button(BUTTON_START, bits & 0x02 != 0)
            joystick.send_button(BUTTON_LEFT_STICK, bits & 0x04 != 0)
            joystick.send_button(BUTTON_RIGHT_STICK, bits & 0x08 != 0)
            joystick.send_button(BUTTON_GUIDE, bits & 0x10 != 0)
            joystick.send_button(BUTTON_SHARE, bits & 0x20 != 0)
        if data[2] != last[2]:
            joystick.send_hat(0, self._hat_from_direction(Int(data[2])))
        joystick.send_axis(
            AXIS_LEFT_TRIGGER, 32767 if data[0] & 0x40 != 0 else -32768
        )
        joystick.send_axis(
            AXIS_RIGHT_TRIGGER, 32767 if data[0] & 0x80 != 0 else -32768
        )
        for axis in range(4):  # pragma: no branch
            if data[3 + axis] != last[3 + axis]:
                var value = remap_val(
                    Float32(Int(data[3 + axis])),
                    0,
                    255,
                    -32768,
                    32767,
                )
                joystick.send_axis(axis, Int(value))
        for index in range(7):  # pragma: no branch
            self.last_input_only_state[index] = self.read_buffer[index]

    def _simple_stick(mut self, stick: Int, axis: Int, raw: Int) -> Int:
        """Scale a simple report's stick value. SDL:
        `ApplySimpleStickCalibration`.

        Args:
            stick: 0 for the left stick, 1 for the right.
            axis: 0 for across, 1 for up and down.
            raw: The value, 0x8000 at the center.

        Returns:
            The axis value.
        """
        var value = _sint16(raw - 0x8000)
        var at = (stick * 2 + axis) * 2
        if value >= 0:
            if value > self.simple_stick_extents[at + 1]:
                self.simple_stick_extents[at + 1] = value
            return Int(
                remap_val(
                    Float32(value),
                    0,
                    Float32(self.simple_stick_extents[at + 1]),
                    0,
                    32767,
                )
            )
        if value < self.simple_stick_extents[at]:
            self.simple_stick_extents[at] = value
        return Int(
            remap_val(
                Float32(value),
                Float32(self.simple_stick_extents[at]),
                0,
                -32768,
                0,
            )
        )

    def _handle_simple_state(mut self, mut joystick: Joystick):
        """Read a simple report, 0x3F. SDL: `HandleSimpleControllerState`.

        Args:
            joystick: The joystick.
        """
        ref data = self.read_buffer
        ref last = self.last_simple_state
        if data[1] != last[0]:
            var bits = data[1]
            joystick.send_button(
                self._remap_button(BUTTON_SOUTH), bits & 0x01 != 0
            )
            joystick.send_button(
                self._remap_button(BUTTON_EAST), bits & 0x02 != 0
            )
            joystick.send_button(
                self._remap_button(BUTTON_WEST), bits & 0x04 != 0
            )
            joystick.send_button(
                self._remap_button(BUTTON_NORTH), bits & 0x08 != 0
            )
            joystick.send_button(BUTTON_LEFT_SHOULDER, bits & 0x10 != 0)
            joystick.send_button(BUTTON_RIGHT_SHOULDER, bits & 0x20 != 0)
        if data[2] != last[1]:
            var bits = data[2]
            joystick.send_button(BUTTON_BACK, bits & 0x01 != 0)
            joystick.send_button(BUTTON_START, bits & 0x02 != 0)
            joystick.send_button(BUTTON_LEFT_STICK, bits & 0x04 != 0)
            joystick.send_button(BUTTON_RIGHT_STICK, bits & 0x08 != 0)
            joystick.send_button(BUTTON_GUIDE, bits & 0x10 != 0)
            joystick.send_button(BUTTON_SHARE, bits & 0x20 != 0)
        if data[3] != last[2]:
            joystick.send_hat(0, self._hat_from_direction(Int(data[3])))
        joystick.send_axis(
            AXIS_LEFT_TRIGGER, 32767 if data[1] & 0x40 != 0 else -32768
        )
        var right = (data[1] | data[2]) & 0x80 != 0
        joystick.send_axis(AXIS_RIGHT_TRIGGER, 32767 if right else -32768)
        for axis in range(4):  # pragma: no branch
            var raw = load16(self.read_buffer, 4 + 2 * axis)
            joystick.send_axis(
                axis, self._simple_stick(axis // 2, axis % 2, raw)
            )
        for index in range(3):  # pragma: no branch
            self.last_simple_state[index] = self.read_buffer[1 + index]

    def _full_stick(mut self, stick: Int, axis: Int, raw: Int) -> Int:
        """Calibrate a full report's stick value. SDL:
        `ApplyStickCalibration`.

        Args:
            stick: 0 for the left stick, 1 for the right.
            axis: 0 for across, 1 for up and down.
            raw: The 12-bit value.

        Returns:
            The axis value.
        """
        var value = _sint16(
            raw - self.stick_calibration[(stick * 2 + axis) * 3]
        )
        var at = (stick * 2 + axis) * 2
        if value >= 0:
            if value > self.stick_extents[at + 1]:
                self.stick_extents[at + 1] = value
            return Int(
                remap_val(
                    Float32(value),
                    0,
                    Float32(self.stick_extents[at + 1]),
                    0,
                    32767,
                )
            )
        if value < self.stick_extents[at]:
            self.stick_extents[at] = value
        return Int(
            remap_val(
                Float32(value), Float32(self.stick_extents[at]), 0, -32768, 0
            )
        )

    def _send_sensor(
        self,
        mut joystick: Joystick,
        type: SensorType,
        timestamp_ns: Int,
        offset: Int,
    ):
        """Send one gyroscope or accelerometer sample. SDL:
        `SendSensorUpdate`, for a Pro Controller.

        The axes are in the order of a PlayStation controller.

        Args:
            joystick: The joystick.
            type: `SENSOR_GYRO` or `SENSOR_ACCEL`.
            timestamp_ns: The sample's time.
            offset: Where the sample's x, y and z are in the read buffer.
        """
        var scale = 3 if type == SENSOR_GYRO else 0
        var x = Float32(load16(self.read_buffer, offset))
        var y = Float32(load16(self.read_buffer, offset + 2))
        var z = Float32(load16(self.read_buffer, offset + 4))
        var data = SIMD[DType.float32, SENSOR_VALUES](0)
        data[0] = -(self.imu_scale[scale + 1] * y)
        data[1] = self.imu_scale[scale + 2] * z
        data[2] = -(self.imu_scale[scale] * x)
        joystick.send_sensor(
            type, Duration64(Float64(timestamp_ns) * 1e-9, SECOND), data
        )

    def _handle_full_state[
        S: HidSource
    ](mut self, mut source: S, mut joystick: Joystick):
        """Read a full report, 0x30 or 0x31. SDL:
        `HandleFullControllerState`, for a Pro Controller.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            joystick: The joystick.
        """
        ref data = self.read_buffer
        ref last = self.last_full_state
        if data[3] != last[0]:
            var bits = data[3]
            joystick.send_button(
                self._remap_button(BUTTON_SOUTH), bits & 0x04 != 0
            )
            joystick.send_button(
                self._remap_button(BUTTON_EAST), bits & 0x08 != 0
            )
            joystick.send_button(
                self._remap_button(BUTTON_WEST), bits & 0x01 != 0
            )
            joystick.send_button(
                self._remap_button(BUTTON_NORTH), bits & 0x02 != 0
            )
            joystick.send_button(BUTTON_RIGHT_SHOULDER, bits & 0x40 != 0)
        if data[4] != last[1]:
            var bits = data[4]
            joystick.send_button(BUTTON_BACK, bits & 0x01 != 0)
            joystick.send_button(BUTTON_START, bits & 0x02 != 0)
            joystick.send_button(BUTTON_RIGHT_STICK, bits & 0x04 != 0)
            joystick.send_button(BUTTON_LEFT_STICK, bits & 0x08 != 0)
            joystick.send_button(BUTTON_GUIDE, bits & 0x10 != 0)
            joystick.send_button(BUTTON_SHARE, bits & 0x20 != 0)
        if data[5] != last[2]:
            var bits = data[5]
            var hat = HAT_CENTERED
            if bits & 0x01 != 0:
                hat |= HAT_DOWN
            if bits & 0x02 != 0:
                hat |= HAT_UP
            if bits & 0x04 != 0:
                hat |= HAT_RIGHT
            if bits & 0x08 != 0:
                hat |= HAT_LEFT
            joystick.send_hat(0, hat)
            joystick.send_button(BUTTON_LEFT_SHOULDER, bits & 0x40 != 0)
        joystick.send_axis(
            AXIS_RIGHT_TRIGGER, 32767 if data[3] & 0x80 != 0 else -32768
        )
        joystick.send_axis(
            AXIS_LEFT_TRIGGER, 32767 if data[5] & 0x80 != 0 else -32768
        )
        for stick in range(2):  # pragma: no branch
            var at = 6 + 3 * stick
            var across = Int(data[at]) | ((Int(data[at + 1]) & 0xF) << 8)
            var down = ((Int(data[at + 1]) & 0xF0) >> 4) | (
                Int(data[at + 2]) << 4
            )
            joystick.send_axis(2 * stick, self._full_stick(stick, 0, across))
            # The pad's y axis points up.
            joystick.send_axis(2 * stick + 1, ~self._full_stick(stick, 1, down))
        for index in range(3):  # pragma: no branch
            self.last_full_state[index] = self.read_buffer[3 + index]
        if self.report_sensors:
            self._handle_imu(source, joystick)

    def _handle_imu[
        S: HidSource
    ](mut self, mut source: S, mut joystick: Joystick):
        """Send the three motion samples of a full report, or turn the
        motion sensors on again when they went quiet. SDL: the sensor part
        of `HandleFullControllerState`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            joystick: The joystick.
        """
        # The first sample's accelerometer is never all zero while the
        # sensors run.
        var has_data = (
            load16(self.read_buffer, 17) != 0
            or load16(self.read_buffer, 15) != 0
            or load16(self.read_buffer, 13) != 0
        )
        if has_data:
            self.has_sensor_data = True
            # Measure the sample interval over 1000 samples.
            self.imu_samples += 3
            if self.imu_samples >= IMU_UPDATE_RATE_SAMPLE_FREQUENCY:
                var elapsed = self.now_ns - self.imu_sample_timestamp_ns
                if elapsed > 0:
                    self.imu_update_interval_ns = elapsed // self.imu_samples
                self.imu_samples = 0
                self.imu_sample_timestamp_ns = self.now_ns
            # The last sample in the report is the oldest.
            for sample in range(3):  # pragma: no branch
                self.timestamp_ns += self.imu_update_interval_ns
                var at = 13 + 12 * (2 - sample)
                self._send_sensor(
                    joystick, SENSOR_GYRO, self.timestamp_ns, at + 6
                )
                self._send_sensor(joystick, SENSOR_ACCEL, self.timestamp_ns, at)
        elif self.has_sensor_data:
            # The sensors went quiet: turn them on again, at most every 3 s.
            var now = self._now_ms()
            if now >= self.last_imu_reset_ms + IMU_RESET_DELAY_MS:
                _ = self._write_subcommand(
                    source, SUBCOMMAND_ENABLE_IMU, [UInt8(1)]
                )
                self.last_imu_reset_ms = now

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
        self.now_ns = _ticks_ns(now)
        var now_ms = self._now_ms()
        var packet_count = 0
        var size = self._read_input(source, 0)
        while size > 0:
            packet_count += 1
            self.last_input_ms = now_ms
            if pad:
                ref joystick = pad.value().joystick
                if self.input_only:
                    self._handle_input_only_state(joystick)
                elif Int(self.read_buffer[0]) != INPUT_SUBCOMMAND_REPLY:
                    var id = Int(self.read_buffer[0])
                    self.current_input_mode = id
                    if id == INPUT_SIMPLE_STATE:
                        self._handle_simple_state(joystick)
                    elif (
                        id == INPUT_FULL_STATE or id == INPUT_FULL_AND_MCU_STATE
                    ):
                        self._handle_full_state(source, joystick)
            size = self._read_input(source, 0)
        if pad:
            if packet_count == 0:
                if not self.input_only and not self.bluetooth:
                    if now_ms >= self.last_input_ms + USB_INPUT_TIMEOUT_MS:
                        # Steam may have stopped the pad's reports.
                        _ = self._write_proprietary(
                            source, PROPRIETARY_FORCE_USB, False
                        )
                elif (
                    self.bluetooth
                    and self.current_input_mode != INPUT_SIMPLE_STATE
                ):
                    if (
                        now_ms
                        >= self.last_input_ms + BLUETOOTH_INPUT_TIMEOUT_MS
                    ):
                        # The Bluetooth link may be gone.
                        size = -1
            if self.rumble_pending or self.rumble_zero_pending:
                _ = self._send_pending_rumble(source)
            elif self.rumble_active:
                if now_ms >= self.rumble_sent_ms + RUMBLE_REFRESH_FREQUENCY_MS:
                    _ = self._write_rumble(source)
        # Connect the Bluetooth device again once the USB device is gone.
        if device.joysticks == 0 and self.bluetooth and packet_count > 0:
            if not device.has_connected_usb_device(device.serial):
                _ = device.joystick_connected()
        if size < 0 and device.joysticks > 0:
            device.joystick_disconnected()
        return size >= 0

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
        if not self.input_only:
            # Give other programs back the simple report.
            if (
                self.initial_input_mode == 0
                or self.initial_input_mode == INPUT_SIMPLE_STATE
            ):
                _ = self._set_input_mode(source, INPUT_SIMPLE_STATE)
        self.has_joystick = False
        self.report_sensors = False
        self.enhanced_mode = False
        self.enhanced_mode_available = False
