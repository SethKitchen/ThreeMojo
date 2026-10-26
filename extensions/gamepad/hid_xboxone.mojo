# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of
# src/joystick/hidapi/SDL_hidapi_xboxone.c, from SDL 3.2.24. It is a
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

"""The Xbox One and Xbox Series controller driver. SDL:
`SDL_hidapi_xboxone.c`.

Over Bluetooth the pad is a HID device. Report 0x01 is the state, in
each format that SDL reads: the 16-byte report of the first Xbox One S
firmware, the 17-byte report of later firmware and of the Series pads,
and the Elite Series 2 reports of 20, 39 and 55 bytes with the paddles.
Report 0x02 is the guide button. Output report 0x03 rumbles the two
motors and the two trigger motors.

A wired pad speaks GIP, the Gaming Input Protocol, in USB packets. This
driver ports SDL's GIP state machine too: the announce, the
identification request, the startup packets, the acknowledgements, the
chunked packets, the serial number, the guide button packet, the state
packet with the Elite paddles and the Series share button, and the Elite
Series 2 unmapped state packet. On Linux and macOS, hidapi reaches a GIP
interface only through libusb, so the port reads these packets only
from a `HidSource` that gives them.

What is not ported, and why:

- The Bluetooth battery report (0x04). `Joystick` keeps no power state.
- The `SDL_JOYSTICK_HIDAPI_XBOX_ONE_HOME_LED` hint. The guide button
  light has SDL's default brightness, 20.
- The 10 ms wait after the PowerA rumble startup packet. The writes are
  synchronous.
- The Windows branches, where the Xbox driver does the GIP handshake,
  and the macOS check that leaves wired pads to GameController.
- SDL's size check on an outgoing GIP packet. The only one is the
  13-byte acknowledgement.

Differences from SDL:

- The driver interface gives `rumble` and `rumble_triggers` no time.
  They use the time of the last `update_device`, `open_joystick` or
  `init_device` call where SDL calls `SDL_GetTicks`.
- When a GIP header is longer than the bytes that are left, SDL gives the
  packet a length near 2**32 and can read past its 64-byte buffer. This
  port does the same, and the bytes past the buffer read as 0.
"""
from extensions.gamepad.gamepad import Gamepad
from extensions.gamepad.guid import ProductId, VendorId
from extensions.gamepad.hid import HidSource
from extensions.gamepad.hid_device import (
    CAP_RGB_LED,
    CAP_RUMBLE,
    CAP_TRIGGER_RUMBLE,
    HidapiDevice,
    USB_PACKET_LENGTH,
    USB_VENDOR_PDP,
    USB_VENDOR_POWERA,
    USB_VENDOR_POWERA_ALT,
    USB_VENDOR_RAZER,
    load16,
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
    GAMEPAD_TYPE_XBOXONE,
    GamepadType,
)
from extensions.gamepad.joystick import Joystick
from extensions.gamepad.mapping import (
    HAT_CENTERED,
    HAT_DOWN,
    HAT_LEFT,
    HAT_RIGHT,
    HAT_UP,
)
from units.si import Duration64, MILLISECOND

comptime _USB_VENDOR_MICROSOFT = 0x045E
comptime _USB_PRODUCT_RAZER_ATROX = 0x0A00
comptime _USB_PRODUCT_XBOX_ONE_ELITE_SERIES_2 = 0x0B00

comptime _CONTROLLER_IDENTIFY_TIMEOUT_MS = 100
comptime _CONTROLLER_PREPARE_INPUT_TIMEOUT_MS = 50

# The first button after the standard ones. SDL:
# `SDL_GAMEPAD_BUTTON_XBOX_SHARE_BUTTON`.
comptime _SHARE_BUTTON = 11

# SDL: `SDL_XboxOneInitState`.
comptime _INIT_ANNOUNCED = 0
comptime _INIT_IDENTIFYING = 1
comptime _INIT_STARTUP = 2
comptime _INIT_PREPARE_INPUT = 3
comptime _INIT_COMPLETE = 4

# SDL: `SDL_XboxOneRumbleState`.
comptime _RUMBLE_IDLE = 0
comptime _RUMBLE_QUEUED = 1
comptime _RUMBLE_BUSY = 2

# GIP. SDL adapted these from xone, by medusalix, under the Zlib license.
comptime _GIP_HEADER_MIN_LENGTH = 3
comptime _GIP_CMD_ACKNOWLEDGE = 0x01
comptime _GIP_CMD_ANNOUNCE = 0x02
comptime _GIP_CMD_STATUS = 0x03
comptime _GIP_CMD_IDENTIFY = 0x04
comptime _GIP_CMD_VIRTUAL_KEY = 0x07
comptime _GIP_CMD_SERIAL_NUMBER = 0x1E
comptime _GIP_CMD_UNMAPPED_STATE = 0x0C
comptime _GIP_CMD_INPUT = 0x20
comptime _GIP_OPT_ACKNOWLEDGE = 0x10
comptime _GIP_OPT_INTERNAL = 0x20
comptime _GIP_OPT_CHUNK_START = 0x40
comptime _GIP_OPT_CHUNK = 0x80

# The read buffer holds a USB packet and room for SDL's reads past a
# short packet, which see the rest of its stack buffer.
comptime _WORK_LENGTH = 2 * USB_PACKET_LENGTH


def _key(vendor: Int, product: Int) -> Int:
    """Join a vendor and a product id into one number.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        `vendor << 16 | product`.
    """
    return (vendor << 16) | product


def _is_xbox_one_elite(vendor: Int, product: Int) -> Bool:
    """Return True for an Xbox Elite controller. SDL:
    `SDL_IsJoystickXboxOneElite`.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        Whether it is one.
    """
    var keys: List[Int] = [0x045E02E3, 0x045E0B00, 0x045E0B05, 0x045E0B22]
    return _key(vendor, product) in keys


def _is_xbox_series_x(vendor: Int, product: Int) -> Bool:
    """Return True for an Xbox Series controller. SDL:
    `SDL_IsJoystickXboxSeriesX`.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        Whether it is one.
    """
    var key = _key(vendor, product)
    var first = _key(USB_VENDOR_POWERA_ALT, 0x2001)
    if key >= first and key <= first + 0x19:
        return True
    var keys: List[Int] = [
        0x045E0B12, 0x045E0B13,
        0x0E6F02D6, 0x0E6F02D9, 0x0E6F02DA,
        0x20D64001, 0x20D6400B, 0x20D64014, 0x20D64016, 0x20D6890B,
        0x20D64002,
        0x0F0D01F7, 0x0F0D01F6, 0x0F0D02D6,
        0x0B051A38,
        0x2E240652,
        0x03F008B6, 0x03F007A0,
        0x044FD012,
        0x2DC82002, 0x2DC8200F,
        0x15320A29, 0x15320A2A, 0x15320A2B,
    ]  # fmt: skip
    return key in keys


def _ticks(now: Duration64) -> Int:
    """Return a time in whole milliseconds. SDL: `SDL_GetTicks`.

    Args:
        now: The time.

    Returns:
        The milliseconds, rounded.
    """
    return Int(round(now.to(MILLISECOND)))


def _int16(value: Int) -> Int:
    """Wrap a number into a signed 16-bit range, as a C `Sint16` store does.

    Args:
        value: The number.

    Returns:
        The number modulo 65536, from -32768 to 32767.
    """
    return ((value + 0x8000) & 0xFFFF) - 0x8000


def _trigger(data: List[UInt8], index: Int) -> Int:
    """Read a 10-bit trigger and scale it to an axis. SDL: the trigger
    lines of the state handlers.

    Args:
        data: The report.
        index: Where the trigger's 16 bits start.

    Returns:
        The axis value. A full trigger reads 32767.
    """
    var axis = _int16(load16(data, index) * 64 - 32768)
    if axis == 32704:
        return 32767
    return axis


def _bit(value: UInt8, mask: Int) -> Bool:
    """Return True if a byte has any bit of a mask.

    Args:
        value: The byte.
        mask: The bits.

    Returns:
        Whether `value & mask` is not 0.
    """
    return (Int(value) & mask) != 0


def _send_paddles(
    mut joystick: Joystick,
    first: Int,
    value: UInt8,
    bit1: Int,
    bit2: Int,
    bit3: Int,
    bit4: Int,
):
    """Send the four Elite paddles.

    Args:
        joystick: The joystick.
        first: The first paddle's button.
        value: The paddle byte.
        bit1: The bit of the first paddle button, P1.
        bit2: The bit of P2.
        bit3: The bit of P3.
        bit4: The bit of P4.
    """
    joystick.send_button(first, _bit(value, bit1))
    joystick.send_button(first + 1, _bit(value, bit2))
    joystick.send_button(first + 2, _bit(value, bit3))
    joystick.send_button(first + 3, _bit(value, bit4))


def serial_from_packet(data: List[UInt8], base: Int) -> String:
    """Make the serial number from a GIP serial number packet. SDL:
    `HIDAPI_DriverXboxOne_HandleSerialIDPacket`.

    SDL writes each of the 14 bytes with `SDL_uitoa` in base 16, two
    characters apart. A byte below 0x10 gives one digit and its NUL ends
    the string, so this port stops there too.

    Args:
        data: The bytes.
        base: Where the packet's data starts.

    Returns:
        The serial number.
    """
    comptime DIGITS = "0123456789abcdef"
    var serial = String()
    for index in range(14):
        var byte = Int(data[base + 2 + index])
        if byte >= 16:
            serial += DIGITS[byte=byte >> 4]
        serial += DIGITS[byte=byte & 15]
        if byte < 16:
            break
    return serial^


def _startup_packets(vendor: Int, product: Int) -> List[List[UInt8]]:
    """Return the startup packets a pad gets, in order. SDL:
    `xboxone_init_packets`, with the default guide button brightness.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        The packets, with sequence number 0.
    """
    var packets = List[List[UInt8]]()
    # Power on.
    packets.append([0x05, 0x20, 0x00, 0x01, 0x00])
    # Light the guide button at brightness 20.
    packets.append([0x0A, 0x20, 0x00, 0x03, 0x00, 0x01, 0x14])
    # The controller passed the security check.
    packets.append([0x06, 0x20, 0x00, 0x02, 0x01, 0x00])
    # Some PowerA controllers must start the rumble motors.
    var powera: List[Int] = [
        _key(USB_VENDOR_POWERA, 0x541A),
        _key(USB_VENDOR_POWERA, 0x542A),
        _key(USB_VENDOR_POWERA, 0x543A),
    ]
    if _key(vendor, product) in powera:
        packets.append([
            0x09, 0x00, 0x00, 0x09, 0x00, 0x0F, 0x00, 0x00,
            0x1D, 0x1D, 0xFF, 0x00, 0x00,
        ])  # fmt: skip
    # Set up rumble.
    packets.append([
        0x09, 0x00, 0x00, 0x09, 0x00, 0x0F, 0x00, 0x00,
        0x00, 0x00, 0xFF, 0x00, 0xEB,
    ])  # fmt: skip
    return packets^


@fieldwise_init
struct _GipHeader(ImplicitlyCopyable):
    """A GIP packet header. SDL: `struct gip_header`."""

    var command: Int
    var options: Int
    var sequence: Int
    var packet_length: Int
    var chunk_offset: Int


def _decode_variable_int(
    data: List[UInt8], start: Int, length: Int
) -> Tuple[Int, Int]:
    """Read a GIP variable-length number. SDL: `DecodeVariableInt`.

    Args:
        data: The bytes.
        start: Where the number starts.
        length: How many bytes may be read.

    Returns:
        The number and the bytes it takes. SDL counts one byte more when
        every byte it may read has the continuation bit.
    """
    var value = 0
    var index = 0
    while index < 4 and index < length:
        var byte = Int(data[start + index])
        value |= (byte & 0x7F) << (index * 7)
        if (byte & 0x80) == 0:
            break
        index += 1
    return (value, index + 1)


def _decode_header(
    data: List[UInt8], start: Int, length: Int
) -> Tuple[_GipHeader, Int]:
    """Read a GIP header. SDL: `HIDAPI_GIP_DecodeHeader`.

    Args:
        data: The bytes.
        start: Where the header starts.
        length: How many bytes are left.

    Returns:
        The header and its length.
    """
    var header = _GipHeader(
        Int(data[start]), Int(data[start + 1]), Int(data[start + 2]), 0, 0
    )
    var used = 3
    var packet_length = _decode_variable_int(data, start + used, length - used)
    header.packet_length = packet_length[0]
    used += packet_length[1]
    if (header.options & _GIP_OPT_CHUNK) != 0:
        var chunk_offset = _decode_variable_int(
            data, start + used, length - used
        )
        header.chunk_offset = chunk_offset[0]
        used += chunk_offset[1]
    return (header, used)


struct XboxOneDriver(Movable):
    """The Xbox One driver's state. SDL: `SDL_DriverXboxOne_Context`."""

    var vendor_id: Int
    var product_id: Int
    var init_state: Int
    var start_time: Int
    var sequence: Int
    var send_time: Int
    var has_guide_packet: Bool
    var has_color_led: Bool
    var has_paddles: Bool
    var has_unmapped_state: Bool
    var has_trigger_rumble: Bool
    var has_share_button: Bool
    var last_paddle_state: UInt8
    var low_frequency_rumble: Int
    var high_frequency_rumble: Int
    var left_trigger_rumble: Int
    var right_trigger_rumble: Int
    var rumble_state: Int
    # When the last rumble packet went out, or 0.
    var rumble_time: Int
    var rumble_pending: Bool
    var last_state: List[UInt8]
    var has_chunk_buffer: Bool
    var chunk_buffer: List[UInt8]
    var chunk_length: Int
    # The time of the last call that gave one, in milliseconds. SDL:
    # `SDL_GetTicks`.
    var ticks: Int

    def __init__(out self):
        """Create the state of a device the driver has not seen."""
        self.vendor_id = 0
        self.product_id = 0
        self.init_state = _INIT_ANNOUNCED
        self.start_time = 0
        self.sequence = 0
        self.send_time = 0
        self.has_guide_packet = False
        self.has_color_led = False
        self.has_paddles = False
        self.has_unmapped_state = False
        self.has_trigger_rumble = False
        self.has_share_button = False
        self.last_paddle_state = 0
        self.low_frequency_rumble = 0
        self.high_frequency_rumble = 0
        self.left_trigger_rumble = 0
        self.right_trigger_rumble = 0
        self.rumble_state = _RUMBLE_IDLE
        self.rumble_time = 0
        self.rumble_pending = False
        self.last_state = List[UInt8](length=USB_PACKET_LENGTH, fill=0)
        self.has_chunk_buffer = False
        self.chunk_buffer = List[UInt8]()
        self.chunk_length = 0
        self.ticks = 0

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
            Whether the device is an Xbox One controller.
        """
        return type == GAMEPAD_TYPE_XBOXONE

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
            True. The driver asks the device nothing.
        """
        return True

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
            True. The joystick connects at once.
        """
        self.ticks = _ticks(now)
        self.vendor_id = device.vendor.value
        self.product_id = device.product.value
        self.start_time = self.ticks
        self.sequence = 0
        var key = _key(self.vendor_id, self.product_id)
        self.has_color_led = key == _key(
            _USB_VENDOR_MICROSOFT, _USB_PRODUCT_XBOX_ONE_ELITE_SERIES_2
        )
        self.has_paddles = _is_xbox_one_elite(self.vendor_id, self.product_id)
        # Only Microsoft's own pads have real trigger motors.
        self.has_trigger_rumble = self.vendor_id == _USB_VENDOR_MICROSOFT
        self.has_share_button = _is_xbox_series_x(
            self.vendor_id, self.product_id
        )
        # The PDP Rock Candy sends no announce packet on Linux, so its
        # startup begins at once. Other pads are assumed to be ready.
        if key == _key(USB_VENDOR_PDP, 0x0246):
            self.init_state = _INIT_STARTUP
        else:
            self.init_state = _INIT_COMPLETE
        device.type = GAMEPAD_TYPE_XBOXONE
        return device.joystick_connected()

    def set_player_index[
        S: HidSource
    ](mut self, mut device: HidapiDevice, mut source: S, player_index: Int):
        """Show a player number. SDL: `SetDevicePlayerIndex`, which does
        nothing for this pad.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            player_index: The player, from 0, or -1 for none.
        """
        pass

    def _next_sequence(mut self) -> UInt8:
        """Return the next packet sequence number, which skips 0. SDL:
        `GetNextPacketSequence`.

        Returns:
            The number, from 1 to 255.
        """
        self.sequence = (self.sequence + 1) & 0xFF
        if self.sequence == 0:
            self.sequence = 1
        return UInt8(self.sequence)

    def _send_protocol_packet[
        S: HidSource
    ](mut self, mut source: S, data: List[UInt8]) -> Bool:
        """Send a GIP packet. SDL: `SendProtocolPacket`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            data: The packet.

        Returns:
            Whether all of it was written.
        """
        self.send_time = self.ticks
        return source.write(data) == len(data)

    def _send_controller_startup[S: HidSource](mut self, mut source: S):
        """Send the startup packets. SDL: `SendControllerStartup`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
        """
        # The list always has at least 4 packets.
        for packet in _startup_packets(  # pragma: no branch
            self.vendor_id, self.product_id
        ):
            var data = packet.copy()
            data[2] = self._next_sequence()
            if not self._send_protocol_packet(source, data):
                return

    def _update_init_state[S: HidSource](mut self, mut source: S):
        """Move through the startup sequence. SDL:
        `HIDAPI_DriverXboxOne_UpdateInitState`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
        """
        while True:
            var previous = self.init_state
            if self.init_state == _INIT_ANNOUNCED:
                # Ask who the pad is. The reply is optional.
                var packet: List[UInt8] = [0x04, 0x20, 0x00, 0x00]
                packet[2] = self._next_sequence()
                _ = self._send_protocol_packet(source, packet)
                self.init_state = _INIT_IDENTIFYING
            elif self.init_state == _INIT_IDENTIFYING:
                if self.ticks >= (
                    self.send_time + _CONTROLLER_IDENTIFY_TIMEOUT_MS
                ):
                    self.init_state = _INIT_STARTUP
            elif self.init_state == _INIT_STARTUP:
                self._send_controller_startup(source)
                self.init_state = _INIT_PREPARE_INPUT
            elif self.init_state == _INIT_PREPARE_INPUT:
                if self.ticks >= (
                    self.send_time + _CONTROLLER_PREPARE_INPUT_TIMEOUT_MS
                ):
                    self.init_state = _INIT_COMPLETE
            if self.init_state == previous:
                return

    def _update_rumble[
        S: HidSource
    ](mut self, device: HidapiDevice, mut source: S) -> Bool:
        """Send pending rumble once the pad is ready for it. SDL:
        `HIDAPI_DriverXboxOne_UpdateRumble`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.

        Returns:
            False if a rumble packet could not be written.
        """
        if self.rumble_state == _RUMBLE_QUEUED:
            if self.rumble_time != 0:
                self.rumble_state = _RUMBLE_BUSY
        if self.rumble_state == _RUMBLE_BUSY:
            var busy = 10
            if device.is_bluetooth:
                busy = 50
            if self.ticks >= self.rumble_time + busy:
                self.rumble_time = 0
                self.rumble_state = _RUMBLE_IDLE
        if not self.rumble_pending:
            return True
        if self.rumble_state != _RUMBLE_IDLE:
            return True
        # No longer pending, even if the write fails.
        self.rumble_pending = False
        var packet: List[UInt8]
        if device.is_bluetooth:
            packet = [0x03, 0x0F, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xEB]
            packet[2] = UInt8(self.left_trigger_rumble)
            packet[3] = UInt8(self.right_trigger_rumble)
            packet[4] = UInt8(self.low_frequency_rumble)
            packet[5] = UInt8(self.high_frequency_rumble)
        else:
            packet = [
                0x09, 0x00, 0x00, 0x09, 0x00, 0x0F, 0x00, 0x00,
                0x00, 0x00, 0xFF, 0x00, 0xEB,
            ]  # fmt: skip
            packet[6] = UInt8(self.left_trigger_rumble)
            packet[7] = UInt8(self.right_trigger_rumble)
            packet[8] = UInt8(self.low_frequency_rumble)
            packet[9] = UInt8(self.high_frequency_rumble)
        var written = source.write(packet)
        # SDL: `HIDAPI_DriverXboxOne_RumbleSent`, which the rumble thread
        # calls after the write, whatever its result.
        self.rumble_time = self.ticks
        if written != len(packet):
            return False
        self.rumble_state = _RUMBLE_QUEUED
        return True

    def _handle_unmapped_state_packet(
        mut self,
        mut joystick: Joystick,
        mut data: List[UInt8],
        base: Int,
        size: Int,
    ):
        """Read the Elite Series 2 unmapped state, which has the paddles.
        SDL: `HIDAPI_DriverXboxOne_HandleUnmappedStatePacket`.

        Args:
            joystick: The joystick.
            data: The bytes.
            base: Where the packet's data starts.
            size: The packet's length.
        """
        if size != 17:
            return
        var paddle_index = base + 14
        var paddles_mapped = True
        if data[base + 15] == 0:
            paddles_mapped = False
        elif data[base : base + 14] == self.last_state[0:14]:
            # A profile is on, but it maps nothing to the paddles.
            paddles_mapped = False
        if paddles_mapped:
            # The paddles work as other controls; do not pass them on.
            data[paddle_index] = 0
        if self.last_paddle_state != data[paddle_index]:
            _send_paddles(
                joystick,
                _SHARE_BUTTON + Int(self.has_share_button),
                data[paddle_index],
                0x01,
                0x02,
                0x04,
                0x08,
            )
            self.last_paddle_state = data[paddle_index]
        self.has_unmapped_state = True

    def _handle_state_packet[
        S: HidSource
    ](
        mut self,
        mut source: S,
        mut joystick: Joystick,
        mut data: List[UInt8],
        base: Int,
        size: Int,
    ):
        """Read a GIP state packet. SDL:
        `HIDAPI_DriverXboxOne_HandleStatePacket`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            joystick: The joystick.
            data: The bytes.
            base: Where the packet's data starts.
            size: The packet's length.
        """
        # The Elite paddles: the byte, the bit of each of P1 to P4, and
        # the test of whether a profile maps them to other controls.
        #   Elite Series 1, 29 bytes: paddles in byte 28.
        #   Elite Series 2, 4.x firmware, 34 bytes: paddles in 14, mode 15.
        #   Elite Series 2, 5.x firmware, 46 bytes: paddles in 18, mode 19.
        #   Elite Series 2, 5.17+ firmware, 47 bytes: paddles in 14, mode 20.
        var paddle_index = -1
        var bits: List[Int] = [0x01, 0x02, 0x04, 0x08]
        var paddles_mapped = False
        if self.has_paddles and not self.has_unmapped_state:
            if size == 46:
                # Turn the paddles on over USB.
                _ = source.write([0x4D, 0x00, 0x00, 0x02, 0x07, 0x00])
                paddle_index = 18
                paddles_mapped = data[base + 19] != 0
            elif size == 29:
                paddle_index = 28
                bits = [0x02, 0x08, 0x01, 0x04]
                # The mapped state is at byte 0 and the raw state at 14.
                paddles_mapped = load16(data, base) != load16(data, base + 14)
            elif size == 34:
                paddle_index = 14
                paddles_mapped = data[base + 15] != 0
            elif size == 47:
                paddle_index = 14
                paddles_mapped = data[base + 20] != 0

        if self.last_state[0] != data[base]:
            var byte = data[base]
            joystick.send_button(BUTTON_START.value, _bit(byte, 0x04))
            joystick.send_button(BUTTON_BACK.value, _bit(byte, 0x08))
            joystick.send_button(BUTTON_SOUTH.value, _bit(byte, 0x10))
            joystick.send_button(BUTTON_EAST.value, _bit(byte, 0x20))
            joystick.send_button(BUTTON_WEST.value, _bit(byte, 0x40))
            joystick.send_button(BUTTON_NORTH.value, _bit(byte, 0x80))

        if self.last_state[1] != data[base + 1]:
            var byte = Int(data[base + 1])
            var hat = (
                (byte & 0x01) * HAT_UP
                | ((byte >> 1) & 1) * HAT_DOWN
                | ((byte >> 2) & 1) * HAT_LEFT
                | ((byte >> 3) & 1) * HAT_RIGHT
            )
            joystick.send_hat(0, hat)
            # The Razer Atrox has the shoulder bits the other way round.
            var left = 0x10
            var right = 0x20
            if _key(self.vendor_id, self.product_id) == _key(
                USB_VENDOR_RAZER, _USB_PRODUCT_RAZER_ATROX
            ):
                left = 0x20
                right = 0x10
            joystick.send_button(BUTTON_LEFT_SHOULDER.value, (byte & left) != 0)
            joystick.send_button(
                BUTTON_RIGHT_SHOULDER.value, (byte & right) != 0
            )
            joystick.send_button(BUTTON_LEFT_STICK.value, (byte & 0x40) != 0)
            joystick.send_button(BUTTON_RIGHT_STICK.value, (byte & 0x80) != 0)

        if self.has_share_button:
            # The share button's byte by report length:
            #   Series X 5.0 firmware, 32 bytes, and 5.1, 40 bytes: 14.
            #   Series X 5.5 firmware, 44 bytes: 18.
            #   Victrix Gambit Tournament Controller, 46 bytes: 28.
            #   Thrustmaster eSwap PRO Controller Xbox, 60 bytes: 42.
            var share = -1
            if size < 44:
                share = 14
            elif size == 44:
                share = 18
            elif size == 46:
                share = 28
            elif size == 60:
                share = 42
            if share >= 0:
                if self.last_state[share] != data[base + share]:
                    joystick.send_button(
                        _SHARE_BUTTON, _bit(data[base + share], 0x01)
                    )

        if paddle_index >= 0:
            if paddles_mapped:
                # The paddles work as other controls; do not pass them on.
                data[base + paddle_index] = 0
            var paddles = data[base + paddle_index]
            if self.last_paddle_state != paddles:
                _send_paddles(
                    joystick,
                    _SHARE_BUTTON + Int(self.has_share_button),
                    paddles,
                    bits[0],
                    bits[1],
                    bits[2],
                    bits[3],
                )
                self.last_paddle_state = paddles

        var axis = _trigger(data, base + 2)
        if axis == -32768 and size == 26 and _bit(data[base + 18], 0x80):
            axis = 32767
        joystick.send_axis(AXIS_LEFT_TRIGGER.value, axis)
        axis = _trigger(data, base + 4)
        if axis == -32768 and size == 26 and _bit(data[base + 18], 0x40):
            axis = 32767
        joystick.send_axis(AXIS_RIGHT_TRIGGER.value, axis)
        joystick.send_axis(AXIS_LEFTX.value, load16(data, base + 6))
        joystick.send_axis(AXIS_LEFTY.value, ~load16(data, base + 8))
        joystick.send_axis(AXIS_RIGHTX.value, load16(data, base + 10))
        joystick.send_axis(AXIS_RIGHTY.value, ~load16(data, base + 12))

        for index in range(min(size, USB_PACKET_LENGTH)):
            self.last_state[index] = data[base + index]
        # This packet came without the unmapped state.
        self.has_unmapped_state = False

    def _handle_bluetooth_buttons16(
        mut self, mut joystick: Joystick, data: List[UInt8]
    ):
        """Read the buttons of the first Xbox One S firmware's 16-byte
        report. SDL: `HIDAPI_DriverXboxOneBluetooth_HandleButtons16`.

        Args:
            joystick: The joystick.
            data: The report.
        """
        if self.last_state[14] != data[14]:
            var byte = data[14]
            joystick.send_button(BUTTON_SOUTH.value, _bit(byte, 0x01))
            joystick.send_button(BUTTON_EAST.value, _bit(byte, 0x02))
            joystick.send_button(BUTTON_WEST.value, _bit(byte, 0x04))
            joystick.send_button(BUTTON_NORTH.value, _bit(byte, 0x08))
            joystick.send_button(BUTTON_LEFT_SHOULDER.value, _bit(byte, 0x10))
            joystick.send_button(BUTTON_RIGHT_SHOULDER.value, _bit(byte, 0x20))
            joystick.send_button(BUTTON_BACK.value, _bit(byte, 0x40))
            joystick.send_button(BUTTON_START.value, _bit(byte, 0x80))
        if self.last_state[15] != data[15]:
            joystick.send_button(BUTTON_LEFT_STICK.value, _bit(data[15], 0x01))
            joystick.send_button(BUTTON_RIGHT_STICK.value, _bit(data[15], 0x02))

    def _handle_bluetooth_buttons(
        mut self, mut joystick: Joystick, mut data: List[UInt8], size: Int
    ):
        """Read the buttons of the later Bluetooth reports. SDL:
        `HIDAPI_DriverXboxOneBluetooth_HandleButtons`.

        The reports: Xbox One S 4.8 and 5.x firmware and Xbox Series X,
        17 bytes; Elite Series 2 4.7 firmware, 55 bytes; 4.8 firmware,
        39 bytes; 5.11 firmware, 19 bytes; 5.13 and later, 20 bytes.

        Args:
            joystick: The joystick.
            data: The report.
            size: The report's length.
        """
        if self.last_state[14] != data[14]:
            var byte = data[14]
            joystick.send_button(BUTTON_SOUTH.value, _bit(byte, 0x01))
            joystick.send_button(BUTTON_EAST.value, _bit(byte, 0x02))
            joystick.send_button(BUTTON_WEST.value, _bit(byte, 0x08))
            joystick.send_button(BUTTON_NORTH.value, _bit(byte, 0x10))
            joystick.send_button(BUTTON_LEFT_SHOULDER.value, _bit(byte, 0x40))
            joystick.send_button(BUTTON_RIGHT_SHOULDER.value, _bit(byte, 0x80))
        if self.last_state[15] != data[15]:
            var byte = data[15]
            if not self.has_guide_packet:
                joystick.send_button(BUTTON_GUIDE.value, _bit(byte, 0x10))
            joystick.send_button(BUTTON_START.value, _bit(byte, 0x08))
            joystick.send_button(BUTTON_LEFT_STICK.value, _bit(byte, 0x20))
            joystick.send_button(BUTTON_RIGHT_STICK.value, _bit(byte, 0x40))
        if self.has_share_button:
            joystick.send_button(BUTTON_BACK.value, _bit(data[15], 0x04))
            joystick.send_button(_SHARE_BUTTON, _bit(data[16], 0x01))
        else:
            joystick.send_button(
                BUTTON_BACK.value,
                ((Int(data[15]) & 0x04) | (Int(data[16]) & 0x01)) != 0,
            )
        if self.has_paddles:
            # The paddle byte and the byte that says a profile maps them.
            var paddle_index = -1
            var mapped_index = 0
            if size == 55:
                # The first Elite Series 2 firmware.
                paddle_index = 33
                mapped_index = 35
            elif size == 39:
                paddle_index = 17
                mapped_index = 19
            elif size == 20:
                # 5.13 and later firmware.
                paddle_index = 19
                mapped_index = 17
            if paddle_index >= 0:
                if data[mapped_index] != 0:
                    # The paddles work as other controls; do not pass them
                    # on.
                    data[paddle_index] = 0
                if self.last_paddle_state != data[paddle_index]:
                    _send_paddles(
                        joystick,
                        _SHARE_BUTTON,
                        data[paddle_index],
                        0x01,
                        0x02,
                        0x04,
                        0x08,
                    )
                    self.last_paddle_state = data[paddle_index]

    def _handle_bluetooth_state_packet(
        mut self, mut joystick: Joystick, mut data: List[UInt8], size: Int
    ):
        """Read a Bluetooth state report, 16 bytes or longer. SDL:
        `HIDAPI_DriverXboxOneBluetooth_HandleStatePacket`.

        Args:
            joystick: The joystick.
            data: The report.
            size: The report's length.
        """
        if size == 16:
            # The first Xbox One S firmware: the guide button has its own
            # report.
            self._handle_bluetooth_buttons16(joystick, data)
        else:
            self._handle_bluetooth_buttons(joystick, data, size)

        if self.last_state[13] != data[13]:
            var hats: List[Int] = [
                HAT_CENTERED,
                HAT_UP,
                HAT_RIGHT | HAT_UP,
                HAT_RIGHT,
                HAT_RIGHT | HAT_DOWN,
                HAT_DOWN,
                HAT_LEFT | HAT_DOWN,
                HAT_LEFT,
                HAT_LEFT | HAT_UP,
            ]
            var hat = HAT_CENTERED
            if Int(data[13]) < len(hats):
                hat = hats[Int(data[13])]
            joystick.send_hat(0, hat)

        joystick.send_axis(AXIS_LEFT_TRIGGER.value, _trigger(data, 9))
        joystick.send_axis(AXIS_RIGHT_TRIGGER.value, _trigger(data, 11))
        joystick.send_axis(
            AXIS_LEFTX.value, (load16(data, 1) & 0xFFFF) - 0x8000
        )
        joystick.send_axis(
            AXIS_LEFTY.value, (load16(data, 3) & 0xFFFF) - 0x8000
        )
        joystick.send_axis(
            AXIS_RIGHTX.value, (load16(data, 5) & 0xFFFF) - 0x8000
        )
        joystick.send_axis(
            AXIS_RIGHTY.value, (load16(data, 7) & 0xFFFF) - 0x8000
        )

        # The caller passes only reports of 16 bytes or more.
        for index in range(min(size, USB_PACKET_LENGTH)):  # pragma: no branch
            self.last_state[index] = data[index]

    def _acknowledge_packet[
        S: HidSource
    ](mut self, mut source: S, ack: _GipHeader) -> Bool:
        """Acknowledge a GIP packet. SDL: `HIDAPI_GIP_AcknowledgePacket`.

        Parameters:
            S: The kind of HID device.

        Args:
            source: The open device.
            ack: The header of the packet that asks for it.

        Returns:
            Whether the acknowledgement was written.
        """
        var length = (ack.chunk_offset + ack.packet_length) & 0xFFFF
        var remaining = 0
        if (ack.options & _GIP_OPT_CHUNK) != 0 and self.has_chunk_buffer:
            remaining = (self.chunk_length - length) & 0xFFFF
        var sequence = UInt8(ack.sequence)
        if sequence == 0:
            sequence = self._next_sequence()
        # The header, then `struct gip_pkt_acknowledge`.
        var packet: List[UInt8] = [
            _GIP_CMD_ACKNOWLEDGE,
            _GIP_OPT_INTERNAL,
            sequence,
            9,
            0,
            UInt8(ack.command),
            _GIP_OPT_INTERNAL,
            UInt8(length & 0xFF),
            UInt8(length >> 8),
            0,
            0,
            UInt8(remaining & 0xFF),
            UInt8(remaining >> 8),
        ]
        return self._send_protocol_packet(source, packet)

    def _dispatch_packet[
        S: HidSource
    ](
        mut self,
        mut device: HidapiDevice,
        mut source: S,
        mut pad: Optional[Gamepad],
        header: _GipHeader,
        mut data: List[UInt8],
        base: Int,
        size: Int,
    ):
        """Act on one GIP packet. SDL: `HIDAPI_GIP_DispatchPacket`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device, for the Elite paddle packet.
            pad: The open gamepad, or None.
            header: The packet's header.
            data: The bytes.
            base: Where the packet's data starts.
            size: The packet's length.
        """
        if (header.options & 0x0F) != 0:
            # The packet is for a device plugged into the controller.
            return
        if (header.options & _GIP_OPT_INTERNAL) != 0:
            if header.command == _GIP_CMD_ANNOUNCE:
                # The controller waits to be started.
                self.init_state = _INIT_ANNOUNCED
            elif header.command == _GIP_CMD_STATUS:
                if self.init_state < _INIT_COMPLETE:
                    self.init_state = _INIT_COMPLETE
            elif header.command == _GIP_CMD_IDENTIFY:
                self.init_state = _INIT_STARTUP
            elif header.command == _GIP_CMD_VIRTUAL_KEY:
                if pad:
                    pad.value().joystick.send_button(
                        BUTTON_GUIDE.value, _bit(data[base], 0x01)
                    )
            elif header.command == _GIP_CMD_SERIAL_NUMBER:
                device.set_serial(serial_from_packet(data, base))
        elif header.command == _GIP_CMD_INPUT:
            if self.init_state < _INIT_COMPLETE:
                # The first input may be spurious, so it is skipped.
                self.init_state = _INIT_COMPLETE
            elif pad:
                self._handle_state_packet(
                    source, pad.value().joystick, data, base, size
                )
        elif header.command == _GIP_CMD_UNMAPPED_STATE:
            if pad:
                self._handle_unmapped_state_packet(
                    pad.value().joystick, data, base, size
                )

    def _process_packet[
        S: HidSource
    ](
        mut self,
        mut device: HidapiDevice,
        mut source: S,
        mut pad: Optional[Gamepad],
        var header: _GipHeader,
        mut data: List[UInt8],
        base: Int,
    ) -> Bool:
        """Acknowledge, collect and act on one GIP packet. SDL:
        `HIDAPI_GIP_ProcessPacket` and `HIDAPI_GIP_ProcessPacketChunked`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            pad: The open gamepad, or None.
            header: The packet's header.
            data: The bytes.
            base: Where the packet's data starts.

        Returns:
            False if the acknowledgement failed or a chunk does not fit.
        """
        if (header.options & _GIP_OPT_CHUNK_START) != 0:
            # The first chunk's offset is the whole length.
            self.chunk_buffer = List[UInt8](
                length=header.chunk_offset + _WORK_LENGTH, fill=0
            )
            self.has_chunk_buffer = True
            self.chunk_length = header.chunk_offset
            header.chunk_offset = 0
        if (header.options & _GIP_OPT_ACKNOWLEDGE) != 0:
            if not self._acknowledge_packet(source, header):
                return False
        if (header.options & _GIP_OPT_CHUNK) == 0:
            self._dispatch_packet(
                device, source, pad, header, data, base, header.packet_length
            )
            return True
        if not self.has_chunk_buffer:
            return False
        if header.chunk_offset + header.packet_length > self.chunk_length:
            return False
        if header.packet_length > 0:
            # The length is above 0 here.
            for index in range(header.packet_length):  # pragma: no branch
                self.chunk_buffer[header.chunk_offset + index] = data[
                    base + index
                ]
            return True
        var whole = self.chunk_buffer^
        self.chunk_buffer = List[UInt8]()
        self.has_chunk_buffer = False
        var length = self.chunk_length
        self.chunk_length = 0
        self._dispatch_packet(device, source, pad, header, whole, 0, length)
        return True

    def _process_data[
        S: HidSource
    ](
        mut self,
        mut device: HidapiDevice,
        mut source: S,
        mut pad: Optional[Gamepad],
        mut data: List[UInt8],
        size: Int,
    ):
        """Act on each GIP packet in a USB packet. SDL:
        `HIDAPI_GIP_ProcessData`.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            pad: The open gamepad, or None.
            data: The USB packet.
            size: Its length.
        """
        var base = 0
        var left = size
        while left > _GIP_HEADER_MIN_LENGTH:
            var decoded = _decode_header(data, base, left)
            var header = decoded[0]
            var header_length = decoded[1]
            if header_length + header.packet_length > left:
                # macOS gives a shortened report. A header longer than
                # the bytes left gives a length near 2**32, as in SDL.
                header.packet_length = (left - header_length) & 0xFFFFFFFF
            if not self._process_packet(
                device, source, pad, header, data, base + header_length
            ):
                return
            base += header_length + header.packet_length
            left -= header_length + header.packet_length

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
        self.ticks = _ticks(now)
        if device.joysticks == 0:
            return False
        var buffer = List[UInt8](length=USB_PACKET_LENGTH, fill=0)
        var data = List[UInt8](length=_WORK_LENGTH, fill=0)
        var size: Int
        while True:
            size = source.read(buffer, 0)
            if size <= 0:
                break
            # A read of 0 bytes or fewer ended the loop.
            for index in range(size):  # pragma: no branch
                data[index] = buffer[index]
            if not device.is_bluetooth:
                self._process_data(device, source, pad, data, size)
            elif pad:
                var id = Int(data[0])
                if id == 0x01:
                    if size >= 16:
                        self._handle_bluetooth_state_packet(
                            pad.value().joystick, data, size
                        )
                elif id == 0x02:
                    # The guide button. SDL:
                    # `HIDAPI_DriverXboxOneBluetooth_HandleGuidePacket`.
                    self.has_guide_packet = True
                    pad.value().joystick.send_button(
                        BUTTON_GUIDE.value, _bit(data[1], 0x01)
                    )
        self._update_init_state(source)
        _ = self._update_rumble(device, source)
        if size < 0:
            # A read error: the device went away.
            device.joystick_disconnected()
            return False
        return True

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
            The joystick: 6 axes, 1 hat, and 11 buttons, with the share
            button and the 4 paddles of the pads that have them.

        Raises:
            Error: If the joystick cannot be made, which valid counts
                never cause.
        """
        self.ticks = _ticks(now)
        self.low_frequency_rumble = 0
        self.high_frequency_rumble = 0
        self.left_trigger_rumble = 0
        self.right_trigger_rumble = 0
        self.rumble_state = _RUMBLE_IDLE
        self.rumble_time = 0
        self.rumble_pending = False
        self.last_state = List[UInt8](length=USB_PACKET_LENGTH, fill=0)
        var buttons = (
            11 + Int(self.has_share_button) + 4 * Int(self.has_paddles)
        )
        return Joystick(device.name, device.guid, AXIS_COUNT, buttons, 1)

    def rumble[
        S: HidSource
    ](
        mut self, mut device: HidapiDevice, mut source: S, low: Int, high: Int
    ) -> Bool:
        """Rumble. SDL: `RumbleJoystick`.

        The pad takes strengths from 0 to 100. The packet waits while the
        pad is busy with the last one, and `update_device` sends it.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            low: The low frequency strength, 0 to 65535.
            high: The high frequency strength, 0 to 65535.

        Returns:
            False if the packet could not be written.
        """
        self.low_frequency_rumble = low // 655
        self.high_frequency_rumble = high // 655
        self.rumble_pending = True
        return self._update_rumble(device, source)

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
            False for a pad with no trigger motors, or if the packet could
            not be written.
        """
        if not self.has_trigger_rumble:
            return False
        self.left_trigger_rumble = left // 655
        self.right_trigger_rumble = right // 655
        self.rumble_pending = True
        return self._update_rumble(device, source)

    def capabilities(self, device: HidapiDevice) -> Int:
        """Return what the pad can do. SDL: `GetJoystickCapabilities`.

        Args:
            device: The device.

        Returns:
            The `CAP_*` bits.
        """
        return (
            CAP_RUMBLE
            | Int(self.has_trigger_rumble) * CAP_TRIGGER_RUMBLE
            | Int(self.has_color_led) * CAP_RGB_LED
        )

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
        """Set the light. SDL: `SetJoystickLED`. Only the Elite Series 2
        has a color light.

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
        if not self.has_color_led:
            return False
        # Byte 5 is a white level that adds to the color.
        var packet: List[UInt8] = [
            0x0E,
            0x00,
            0x00,
            0x05,
            0x00,
            0x00,
            UInt8(red),
            UInt8(green),
            UInt8(blue),
        ]
        return source.write(packet) == len(packet)

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
        `SetJoystickSensorsEnabled`. The pad has none.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
            joystick: The joystick.
            enabled: Whether they report.

        Returns:
            False.
        """
        return False

    def close_joystick[
        S: HidSource
    ](mut self, mut device: HidapiDevice, mut source: S):
        """Close the joystick. SDL: `CloseJoystick`, which only drops the
        guide light hint.

        Parameters:
            S: The kind of HID device.

        Args:
            device: The device.
            source: The open device.
        """
        pass
