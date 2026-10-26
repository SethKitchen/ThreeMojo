# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Run a HIDAPI driver on a scripted device and print what it does.

The SDL oracle for these tests is SDL 3.2.24 linked with wrappers for the
`SDL_hid_*` calls, the clock and the rumble thread. It reads the same
script and prints the same lines, so a test compares the two transcripts
whole. A script line is one of:

    device VID PID VERSION usb|bt IFACE USAGE_PAGE USAGE
    strings MANUFACTURER|PRODUCT|SERIAL
    feature HEX            the reply to a feature report request
    input HEX              one input report
    fail                   every later call fails: the device went away
    time MS
    open                   start the driver and open the gamepad
    update
    rumble LOW HIGH MS
    triggers LEFT RIGHT MS
    led R G B
    player N
    sensors 0|1            turn every sensor on or off
"""

from extensions.gamepad.gamepad import (
    GAMEPAD_SENSOR_UPDATE,
    GAMEPAD_TOUCHPAD_DOWN,
    GAMEPAD_TOUCHPAD_UP,
    GamepadEvent,
)
from extensions.gamepad.guid import ProductId, VendorId, guid_to_string
from extensions.gamepad.hid import (
    HID_BUS_BLUETOOTH,
    HID_BUS_USB,
    HidDeviceInfo,
    HidSource,
)
from extensions.gamepad.hid_device import (
    CAP_MONO_LED,
    CAP_PLAYER_LED,
    CAP_RGB_LED,
    CAP_RUMBLE,
    CAP_TRIGGER_RUMBLE,
)
from extensions.gamepad.hid_device import HidapiDevice
from extensions.gamepad.hidapi import HID_DRIVER_NONE, HidGamepad, device_driver
from extensions.gamepad.joystick import SENSOR_ACCEL, SENSOR_GYRO_R, SensorType
from extensions.gamepad.linux import default_mapping_database
from extensions.gamepad.mapping import MappingDatabase
from units.si import Duration64, PER_SECOND, SECOND


def hex_bytes(text: String) -> List[UInt8]:
    """Read bytes written as hexadecimal pairs.

    Args:
        text: The pairs, with nothing between them.

    Returns:
        The bytes.
    """
    var bytes = List[UInt8]()
    var digits = text.as_bytes()
    var index = 0
    while index + 1 < len(digits):
        var value = 0
        for offset in range(2):
            var byte = Int(digits[index + offset])
            value = value * 16 + (
                byte - 48 if byte
                <= 57 else (byte - 87 if byte >= 97 else byte - 55)
            )
        bytes.append(UInt8(value))
        index += 2
    return bytes^


def bytes_hex(bytes: List[UInt8]) -> String:
    """Write bytes as lowercase hexadecimal pairs.

    Args:
        bytes: The bytes.

    Returns:
        The pairs.
    """
    comptime DIGITS = "0123456789abcdef"
    var text = String()
    for byte in bytes:
        text += DIGITS[byte=Int(byte >> 4)]
        text += DIGITS[byte=Int(byte & 15)]
    return text^


def fixed4(value: Float32) -> String:
    """Write a number with four decimals, as `printf("%.4f")` does.

    Args:
        value: The number.

    Returns:
        The text.
    """
    var scaled = Int(round(Float64(value) * 10000))
    var sign = "-" if scaled < 0 else ""
    if scaled < 0:
        scaled = -scaled
    var fraction = String(scaled % 10000)
    while fraction.byte_length() < 4:
        fraction = "0" + fraction
    return sign + String(scaled // 10000) + "." + fraction


def fixed1(value: Float32) -> String:
    """Write a number with one decimal, as `printf("%.1f")` does.

    Args:
        value: The number.

    Returns:
        The text.
    """
    var scaled = Int(round(Float64(value) * 10))
    return String(scaled // 10) + "." + String(scaled % 10)


struct ScriptedHid(HidSource):
    """A HID device that answers from a script and logs every call."""

    var queue: List[List[UInt8]]
    var features: List[List[UInt8]]
    var failing: Bool
    var log: List[String]

    def __init__(out self):
        """Create a device with no reports."""
        self.queue = List[List[UInt8]]()
        self.features = List[List[UInt8]](length=256, fill=List[UInt8]())
        self.failing = False
        self.log = List[String]()

    @staticmethod
    def open(path: String) raises -> Self:
        """Open a device. A path with `missing` in it fails.

        Args:
            path: The path.

        Returns:
            A device with no reports.

        Raises:
            Error: For a missing device.
        """
        if path.find("missing") >= 0:
            raise Error("missing")
        return ScriptedHid()

    def read(mut self, mut buffer: List[UInt8], milliseconds: Int) -> Int:
        """Give the next queued report.

        Args:
            buffer: The buffer.
            milliseconds: Ignored.

        Returns:
            The report's length, 0 when none is queued, or -1 when failing.
        """
        if self.failing:
            return -1
        if len(self.queue) == 0:
            return 0
        var report = self.queue.pop(0)
        var count = min(len(report), len(buffer))
        for index in range(count):
            buffer[index] = report[index]
        return count

    def write(mut self, data: List[UInt8]) -> Int:
        """Log a written report.

        Args:
            data: The report.

        Returns:
            Its length, or -1 when failing.
        """
        self.log.append("write " + bytes_hex(data))
        return -1 if self.failing else len(data)

    def get_feature_report(mut self, mut buffer: List[UInt8]) -> Int:
        """Give the scripted reply to a feature report request.

        Args:
            buffer: The report id first.

        Returns:
            The reply's length, or -1 when there is none or when failing.
        """
        var id = Int(buffer[0])
        self.log.append(
            "feature-get " + bytes_hex([buffer[0]]) + " " + String(len(buffer))
        )
        if self.failing or len(self.features[id]) == 0:
            return -1
        var count = min(len(self.features[id]), len(buffer))
        for index in range(count):
            buffer[index] = self.features[id][index]
        return count

    def send_feature_report(mut self, data: List[UInt8]) -> Int:
        """Log a sent feature report.

        Args:
            data: The report.

        Returns:
            Its length, or -1 when failing.
        """
        self.log.append("feature-send " + bytes_hex(data))
        return -1 if self.failing else len(data)


def _fields(line: String) -> List[String]:
    """Split a script line at its spaces.

    Args:
        line: The line.

    Returns:
        Its words.
    """
    var words = List[String]()
    for word in line.split(" "):
        if word.byte_length() > 0:
            words.append(String(word))
    return words^


def _flush(mut out: String, mut source: ScriptedHid):
    """Move the device's log to the transcript.

    Args:
        out: The transcript.
        source: The device.
    """
    for line in source.log:
        out += line + "\n"
    source.log.clear()


def _events(mut out: String, events: List[GamepadEvent]):
    """Print the sensor and touchpad events, as the oracle does.

    Args:
        out: The transcript.
        events: The gamepad's events.
    """
    for event in events:
        if event.kind == GAMEPAD_SENSOR_UPDATE:
            var nanoseconds = Int(
                round(event.sensor_timestamp.to(SECOND) * 1e9)
            )
            out += "sensor " + String(event.sensor.value)
            for axis in range(3):
                out += " " + fixed4(event.data[axis])
            out += " " + String(nanoseconds) + "\n"
        elif event.kind.value >= GAMEPAD_TOUCHPAD_DOWN.value and (
            event.kind.value <= GAMEPAD_TOUCHPAD_UP.value
        ):
            var name = "down" if event.kind == GAMEPAD_TOUCHPAD_DOWN else (
                "up" if event.kind == GAMEPAD_TOUCHPAD_UP else "motion"
            )
            out += (
                "touch "
                + name
                + " "
                + String(event.touchpad)
                + " "
                + String(event.finger)
                + " "
                + fixed4(event.x)
                + " "
                + fixed4(event.y)
                + " "
                + fixed4(event.pressure)
                + "\n"
            )


def _state(mut out: String, pad: HidGamepad[ScriptedHid]):
    """Print the joystick's axes, buttons and hats.

    Args:
        out: The transcript.
        pad: The device.
    """
    if not pad.pad:
        out += "disconnected\n"
        return
    ref joystick = pad.pad.value().joystick
    out += "axes"
    for index in range(joystick.axis_count()):
        out += " " + String(joystick.get_axis(index))
    out += "\nbuttons "
    for index in range(joystick.button_count()):
        out += "1" if joystick.get_button(index) else "0"
    out += "\nhats"
    for index in range(joystick.hat_count()):
        out += " " + String(joystick.get_hat(index))
    out += "\n"


def _describe(
    mut out: String, pad: HidGamepad[ScriptedHid], database: MappingDatabase
) raises:
    """Print what the oracle prints when a gamepad opens.

    Args:
        out: The transcript.
        pad: The device.
        database: The mappings.

    Raises:
        Error: If the gamepad's mapping is gone.
    """
    ref gamepad = pad.pad.value()
    ref joystick = gamepad.joystick
    out += "name " + pad.device.name + "\n"
    out += "guid " + guid_to_string(pad.device.guid) + "\n"
    out += "type " + String(pad.gamepad_type().value) + "\n"
    var index = database.mapping_for_guid(pad.device.guid, False)
    out += "mapping " + database.mapping_string(index, pad.device.guid) + "\n"
    out += (
        "counts "
        + String(joystick.axis_count())
        + " "
        + String(joystick.button_count())
        + " "
        + String(joystick.hat_count())
        + "\n"
    )
    out += "touchpads " + String(gamepad.touchpad_count())
    for touchpad in range(gamepad.touchpad_count()):
        out += " " + String(gamepad.touchpad_finger_count(touchpad))
    out += "\nsensors"
    for type in range(SENSOR_ACCEL.value, SENSOR_GYRO_R.value + 1):
        if gamepad.has_sensor(SensorType(type)):
            out += (
                " "
                + String(type)
                + ":"
                + fixed1(
                    gamepad.sensor_data_rate(SensorType(type)).to(PER_SECOND)
                )
            )
    var caps = pad.capabilities()
    out += "\ncaps"
    for bit in [
        CAP_MONO_LED,
        CAP_RGB_LED,
        CAP_PLAYER_LED,
        CAP_RUMBLE,
        CAP_TRIGGER_RUMBLE,
    ]:
        out += " 1" if caps & bit else " 0"
    out += "\n"


def run_script(script: String) raises -> String:
    """Run a script and return the transcript.

    Args:
        script: The script, one command a line.

    Returns:
        What the oracle prints for the same script.

    Raises:
        Error: If a line is not a command.
    """
    var database = default_mapping_database()
    var out = String()
    var info = HidDeviceInfo(
        "/dev/hidraw0",
        VendorId(0),
        ProductId(0),
        0,
        "",
        "",
        "",
        0,
        0,
        -1,
        HID_BUS_USB,
    )
    var pending = ScriptedHid()
    var pad = Optional[HidGamepad[ScriptedHid]](None)
    var now = Duration64(0)
    for raw in script.split("\n"):
        var line = String(raw.strip())
        if line.byte_length() == 0 or line.startswith("#"):
            continue
        out += "> " + line + "\n"
        var words = _fields(line)
        var command = words[0]
        if command == "device":
            info.vendor = VendorId(atol(words[1], 16))
            info.product = ProductId(atol(words[2], 16))
            info.release = atol(words[3], 16)
            info.bus = HID_BUS_BLUETOOTH if words[4] == "bt" else HID_BUS_USB
            info.interface_number = atol(words[5])
            info.usage_page = atol(words[6], 16)
            info.usage = atol(words[7], 16)
        elif command == "strings":
            var parts = String(line[byte=8:]).split("|")
            info.manufacturer = String(parts[0])
            info.product_name = String(parts[1]) if len(parts) > 1 else ""
            info.serial = String(parts[2]) if len(parts) > 2 else ""
        elif command == "feature":
            var bytes = hex_bytes(words[1])
            if pad:
                pad.value().source.features[Int(bytes[0])] = bytes^
            else:
                pending.features[Int(bytes[0])] = bytes^
        elif command == "input":
            if pad:
                pad.value().source.queue.append(hex_bytes(words[1]))
            else:
                pending.queue.append(hex_bytes(words[1]))
        elif command == "fail":
            if pad:
                pad.value().source.failing = True
            else:
                pending.failing = True
        elif command == "time":
            now = Duration64(Float64(atol(words[1])) * 1e-3, SECOND)
        elif command == "open":
            if not pad:
                if device_driver(HidapiDevice(info)) != HID_DRIVER_NONE:
                    out += "hid open\n"
                var source = pending^
                pending = ScriptedHid()
                try:
                    pad = HidGamepad[ScriptedHid](info, source^, now)
                except:
                    out += "no joystick\n"
                    continue
            if not pad.value().connected():
                _flush(out, pad.value().source)
                out += "no joystick\n"
                continue
            try:
                pad.value().open_at(database, now)
            except:
                _flush(out, pad.value().source)
                out += "open failed\n"
                continue
            _flush(out, pad.value().source)
            _describe(out, pad.value(), database)
            _events(out, pad.value().pad.value().update())
            _state(out, pad.value())
        elif not pad or not pad.value().pad:
            # No gamepad is open, so the oracle's calls get NULL.
            if command == "update":
                if pad:
                    _ = pad.value().update_at(now)
                    _flush(out, pad.value().source)
                out += "disconnected\n"
            elif command == "sensors":
                pass
            else:
                out += "result 0\n"
        elif command == "update":
            var was_open = Bool(pad.value().pad)
            var events = pad.value().update_at(now)
            _flush(out, pad.value().source)
            _events(out, events)
            if was_open and not pad.value().pad:
                out += "removed\n"
            _state(out, pad.value())
        elif command == "rumble":
            var result = pad.value().rumble_at(
                atol(words[1]),
                atol(words[2]),
                Duration64(Float64(atol(words[3])) * 1e-3, SECOND),
                now,
            )
            _flush(out, pad.value().source)
            out += "result " + String(Int(result)) + "\n"
        elif command == "triggers":
            var result = pad.value().rumble_triggers_at(
                atol(words[1]),
                atol(words[2]),
                Duration64(Float64(atol(words[3])) * 1e-3, SECOND),
                now,
            )
            _flush(out, pad.value().source)
            out += "result " + String(Int(result)) + "\n"
        elif command == "led":
            var result = pad.value().set_led_at(
                atol(words[1]), atol(words[2]), atol(words[3]), now
            )
            _flush(out, pad.value().source)
            out += "result " + String(Int(result)) + "\n"
        elif command == "player":
            pad.value().set_player_index(atol(words[1]))
            _flush(out, pad.value().source)
            out += "result 1\n"
        elif command == "sensors":
            var on = words[1] == "1"
            for type in range(SENSOR_ACCEL.value, SENSOR_GYRO_R.value + 1):
                if pad.value().pad.value().has_sensor(SensorType(type)):
                    var result = pad.value().set_sensor_enabled(
                        SensorType(type), on
                    )
                    _flush(out, pad.value().source)
                    out += "result " + String(Int(result)) + "\n"
        else:
            raise Error("Not a script command: " + line)
    if pad:
        pad.value().close()
        _flush(out, pad.value().source)
        out += "hid close\n"
    return out^
