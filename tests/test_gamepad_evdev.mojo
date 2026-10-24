# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.gamepad.evdev` and `extensions.gamepad.linux`.

`RecordedDevice` answers the evdev ioctls from recorded tables, as a
kernel device would. The expected names, GUIDs, mappings, axes, hats and
buttons are the ones SDL 3.2.24's own Linux driver gives for the same
devices and the same events. The SDL run linked the driver with wrappers
for `open`, `ioctl`, `read` and `fstat` that answer from the same tables.
The one difference is the analog d-pad, which this port binds by halves.
"""

from std.os import makedirs
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.gamepad.evdev import (
    ABS_BRAKE,
    ABS_GAS,
    ABS_HAT0X,
    ABS_HAT0Y,
    ABS_HAT1X,
    ABS_HAT1Y,
    ABS_HAT2X,
    ABS_HAT2Y,
    ABS_RX,
    ABS_RY,
    ABS_RZ,
    ABS_X,
    ABS_Y,
    ABS_Z,
    BTN_A,
    BTN_B,
    BTN_DPAD_DOWN,
    BTN_DPAD_LEFT,
    BTN_DPAD_RIGHT,
    BTN_DPAD_UP,
    BTN_GAMEPAD,
    BTN_MODE,
    BTN_MOUSE,
    BTN_NORTH,
    BTN_SELECT,
    BTN_START,
    BTN_STYLUS,
    BTN_THUMBL,
    BTN_THUMBR,
    BTN_TL,
    BTN_TL2,
    BTN_TOOL_FINGER,
    BTN_TOOL_PEN,
    BTN_TOUCH,
    BTN_TR,
    BTN_TR2,
    BTN_TRIGGER,
    BTN_WEST,
    BTN_X,
    BTN_Y,
    DEVICE_ACCELEROMETER,
    DEVICE_HAS_KEYS,
    DEVICE_JOYSTICK,
    DEVICE_KEYBOARD,
    DEVICE_MOUSE,
    DEVICE_TOUCHPAD,
    DEVICE_TOUCHSCREEN,
    DEVICE_UNKNOWN,
    EV_ABS,
    EV_KEY,
    EV_REL,
    EV_SYN,
    INPUT_PROP_ACCELEROMETER,
    INPUT_PROP_BUTTONPAD,
    INPUT_PROP_POINTING_STICK,
    INPUT_PROP_SEMI_MT,
    INPUT_PROP_TOPBUTTONPAD,
    KEY_RECORD,
    REL_X,
    REL_Y,
    SYN_DROPPED,
    SYN_REPORT,
    AbsInfo,
    DeviceClass,
    EvdevCapabilities,
    EvdevEvent,
    EV_MSC,
    MSC_TIMESTAMP,
    SensorLayout,
    SensorState,
    EvdevLayout,
    EvdevState,
    InputId,
    automatic_mapping,
    c_divide,
    decode_input_events,
    encode_input_event,
    fixup_device_id,
    guess_device_class,
    is_digital_hat,
    set_bit,
    test_bit,
)
from extensions.gamepad.gamepad import (
    GAMEPAD_BUTTON_DOWN,
    GAMEPAD_SENSOR_UPDATE,
)
from extensions.gamepad.joystick import SENSOR_ACCEL, SENSOR_GYRO, SensorType
from units.si import Duration64, Frequency, SECOND
from extensions.gamepad.guid import JoystickGuid, VendorId, guid_to_string
from extensions.gamepad.ids import (
    AXIS_COUNT,
    BUTTON_COUNT,
    BUTTON_WEST,
    GamepadAxis,
    GamepadButton,
)
from extensions.gamepad.joystick import Joystick
from extensions.gamepad.linux import (
    _before,
    EVIOCGID,
    EvdevFile,
    EvdevGamepad,
    EvdevSource,
    default_mapping_database,
    event_joystick_index,
    eviocgabs,
    eviocgbit,
    eviocgkey,
    eviocgname,
    eviocgprop,
    is_event_node,
    jsiocgname,
    list_event_nodes,
    DeviceChangeKind,
    EVIOCSFF,
    EvdevHub,
    GAMEPAD_ADDED,
    GAMEPAD_REMOVED,
    folder_change_time,
    open_gamepads,
    open_gamepads_with,
    probe_joystick,
    probe_sensor,
    read_absinfo,
    read_capabilities,
)
from extensions.gamepad.mapping import (
    MAPPING_AXIS,
    MAPPING_BUTTON,
    MAPPING_HAT,
    MappingDatabase,
)
from test_scratch import TestScratch, temporary_path


struct RecordedDevice(EvdevSource):
    """A device that answers from tables, as the SDL oracle's wrappers do."""

    var name: String
    var id: InputId
    var events: List[UInt8]
    var keys: List[UInt8]
    var absolutes: List[UInt8]
    var relatives: List[UInt8]
    var properties: List[UInt8]
    var keys_down: List[UInt8]
    var info: List[AbsInfo]
    var queue: List[UInt8]
    var consumed: Int
    # The request numbers that fail, and whether the end has come.
    var failing: List[Int]
    var ended: Bool
    # A classic joystick node answers JSIOCGNAME with its name.
    var classic: Bool
    # The unique id, or empty for none, and the force feedback bitmap.
    var uniq: String
    var ff: List[UInt8]
    # What was written, the effects uploaded, and the next effect id.
    var log: List[String]
    var next_effect: Int
    # Whether the device was unplugged, and whether writes fail.
    var unplugged: Bool
    var write_fails: Bool
    # Whether the kernel forgets the uploaded effect once.
    var lose_effect: Bool

    def __init__(
        out self,
        name: String,
        bus: Int,
        vendor: Int,
        product: Int,
        version: Int,
    ):
        self.name = name
        self.id = InputId(bus, vendor, product, version)
        self.events = List[UInt8](length=8, fill=0)
        self.keys = List[UInt8](length=96, fill=0)
        self.absolutes = List[UInt8](length=8, fill=0)
        self.relatives = List[UInt8](length=8, fill=0)
        self.properties = List[UInt8](length=8, fill=0)
        self.keys_down = List[UInt8](length=96, fill=0)
        self.info = List[AbsInfo](length=64, fill=AbsInfo())
        self.queue = List[UInt8]()
        self.consumed = 0
        self.failing = List[Int]()
        self.ended = False
        self.classic = False
        self.uniq = ""
        self.ff = List[UInt8](length=16, fill=0)
        self.log = List[String]()
        self.next_effect = 0
        self.unplugged = False
        self.write_fails = False
        self.lose_effect = False
        set_bit(self.events, EV_SYN)

    def key(mut self, code: Int):
        set_bit(self.events, EV_KEY)
        set_bit(self.keys, code)

    def axis(
        mut self,
        code: Int,
        value: Int,
        minimum: Int,
        maximum: Int,
        fuzz: Int = 0,
        flat: Int = 0,
    ):
        set_bit(self.events, EV_ABS)
        set_bit(self.absolutes, code)
        self.info[code] = AbsInfo(value, minimum, maximum, fuzz, flat, 0)

    @staticmethod
    def open(path: String) raises -> Self:
        var name = String(path[byte = path.rfind("/") + 1 :])
        if name == "sony":
            return _sony()
        if name == "keyboard" or name == "event1":
            return _keyboard()
        if name == "stick":
            return _flight_stick()
        if name == "event3":
            return _paired_sony()
        if name == "event4":
            return _motion_sensors()
        if name == "event10":
            return _sine_pad()
        if name == "event20":
            return _late_pad()
        if name == "deaf":
            # A sensor device that does not give its axes.
            var device = _motion_sensors()
            device.fail(eviocgbit(EV_ABS, 8))
            return device^
        raise Error("No recorded device at " + path)

    def write_from(mut self, buffer: List[UInt8]) -> Int:
        var event = decode_input_events(buffer)[0]
        self.log.append(
            "write type "
            + hex(event.type)
            + " code "
            + String(event.code)
            + " value "
            + String(event.value)
        )
        return -1 if self.write_fails else len(buffer)

    def unplug(mut self):
        self.unplugged = True

    def fail(mut self, request: Int):
        self.failing.append(request)

    def push_bytes(mut self, count: Int):
        for _ in range(count):
            self.queue.append(0)

    def set_value(mut self, code: Int, value: Int):
        self.info[code].value = value

    def hold_only(mut self, code: Int):
        self.keys_down = List[UInt8](length=96, fill=0)
        set_bit(self.keys_down, code)

    def sensor(mut self, code: Int, value: Int, resolution: Int):
        set_bit(self.events, EV_ABS)
        set_bit(self.absolutes, code)
        self.info[code] = AbsInfo(value, -32768, 32767, 0, 0, resolution)

    def push(mut self, type: Int, code: Int, value: Int):
        self.queue += encode_input_event(type, code, value)

    def query(mut self, request: Int, mut buffer: List[UInt8]) -> Int:
        if request in self.failing:
            return -1
        var type = (request >> 8) & 0xFF
        var number = request & 0xFF
        var size = (request >> 16) & 0x3FFF
        if type == ord("j") and number == 0x13 and self.classic:
            var bytes = self.name.as_bytes()
            for index in range(len(bytes)):
                buffer[index] = bytes[index]
            return len(bytes) + 1
        if type != ord("E"):
            return -1
        if number == 0x08:
            if self.uniq.byte_length() == 0:
                return -1
            var bytes = self.uniq.as_bytes()
            for index in range(len(bytes)):
                buffer[index] = bytes[index]
            return len(bytes) + 1
        if number == 0x80:
            var id = Int(buffer[2]) | (Int(buffer[3]) << 8)
            if self.lose_effect and id != 0xFFFF:
                self.lose_effect = False
                return -1
            if id == 0xFFFF:
                id = self.next_effect
                self.next_effect += 1
                buffer[2] = UInt8(id)
                buffer[3] = 0
            var kind = Int(buffer[0]) | (Int(buffer[1]) << 8)
            var text = "EVIOCSFF type " + hex(kind) + " id " + String(id)
            text += " length " + String(
                Int(buffer[10]) | (Int(buffer[11]) << 8)
            )
            text += " strong " + String(
                Int(buffer[16]) | (Int(buffer[17]) << 8)
            )
            text += " weak " + String(Int(buffer[18]) | (Int(buffer[19]) << 8))
            text += " magnitude " + String(
                Int(buffer[20]) | (Int(buffer[21]) << 8)
            )
            self.log.append(text)
            return 0
        if number == 0x02:
            var words: List[Int] = [
                self.id.bustype,
                self.id.vendor,
                self.id.product,
                self.id.version,
            ]
            for index in range(4):
                buffer[2 * index] = UInt8(words[index] & 0xFF)
                buffer[2 * index + 1] = UInt8(words[index] >> 8)
            return 0
        if number == 0x06:
            var bytes = self.name.as_bytes()
            var length = min(len(bytes) + 1, size)
            for index in range(length):
                buffer[index] = bytes[index] if index < len(bytes) else 0
            return length
        if number >= 0x40 and number < 0x80:
            var info = self.info[number - 0x40]
            var values: List[Int] = [
                info.value,
                info.minimum,
                info.maximum,
                info.fuzz,
                info.flat,
                info.resolution,
            ]
            for field in range(6):
                for byte in range(4):
                    buffer[4 * field + byte] = UInt8(
                        (values[field] >> (8 * byte)) & 0xFF
                    )
            return 0
        var source: List[UInt8]
        if number == 0x09:
            source = self.properties.copy()
        elif number == 0x18:
            source = self.keys_down.copy()
        elif number == 0x20:
            source = self.events.copy()
        elif number == 0x20 + EV_KEY:
            source = self.keys.copy()
        elif number == 0x20 + EV_ABS:
            source = self.absolutes.copy()
        elif number == 0x20 + EV_REL:
            source = self.relatives.copy()
        elif number == 0x20 + 0x15:
            source = self.ff.copy()
        else:
            return -1
        var length = min(len(source), size)
        for index in range(len(buffer)):
            buffer[index] = source[index] if index < length else 0
        return length

    def readable(mut self) -> Bool:
        return self.ended or self.unplugged or self.consumed < len(self.queue)

    def read_into(mut self, mut buffer: List[UInt8]) -> Int:
        if self.unplugged:
            return -1
        var left = len(self.queue) - self.consumed
        if left <= 0:
            return 0
        var take = min(left, len(buffer) // 24 * 24)
        for index in range(take):
            buffer[index] = self.queue[self.consumed + index]
        self.consumed += take
        return take


def _sony() -> RecordedDevice:
    var device = RecordedDevice("Sony Pad Clone", 3, 0x054C, 0x9999, 0x0100)
    for code in [
        0x130,
        0x131,
        0x133,
        0x134,
        0x136,
        0x137,
        0x138,
        0x139,
        0x13A,
        0x13B,
        0x13C,
        0x13D,
        0x13E,
    ]:
        device.key(code)
    device.axis(ABS_X, 128, 0, 255)
    device.axis(ABS_Y, 128, 0, 255)
    device.axis(ABS_RX, 128, 0, 255)
    device.axis(ABS_RY, 128, 0, 255)
    device.axis(ABS_Z, 0, 0, 255)
    device.axis(ABS_RZ, 0, 0, 255)
    device.axis(ABS_HAT0X, 0, -1, 1)
    device.axis(ABS_HAT0Y, 0, -1, 1)
    set_bit(device.keys_down, 0x131)
    return device^


def _elite() -> RecordedDevice:
    var device = RecordedDevice("Elite Clone", 3, 0x045E, 0x9999, 0x0001)
    for code in [
        BTN_A,
        BTN_B,
        BTN_X,
        BTN_Y,
        BTN_SELECT,
        BTN_START,
        BTN_MODE,
        BTN_THUMBL,
        BTN_THUMBR,
        KEY_RECORD,
        0x2C4,
        0x2C5,
        0x2C6,
        0x2C7,
        BTN_DPAD_UP,
        BTN_DPAD_DOWN,
    ]:
        device.key(code)
    device.axis(ABS_X, 0, -32768, 32767, 16, 128)
    device.axis(ABS_Y, 0, -32768, 32767, 16, 128)
    device.axis(ABS_RX, 0, -32768, 32767, 16, 128)
    device.axis(ABS_RY, 0, -32768, 32767, 16, 128)
    device.axis(ABS_GAS, 0, 0, 1023)
    device.axis(ABS_BRAKE, 0, 0, 1023)
    device.axis(ABS_HAT0X, 0, -100, 100, 4, 2)
    device.axis(ABS_HAT0Y, 0, -100, 100, 4, 2)
    device.axis(ABS_HAT1X, 0, -1, 1)
    device.axis(ABS_HAT1Y, 0, -1, 1)
    return device^


def _paired_sony() -> RecordedDevice:
    var device = RecordedDevice("Sony Pad Clone", 3, 0x054C, 0x9999, 0x0100)
    device.uniq = "aa:bb:cc"
    for code in [0x130, 0x131, 0x133, 0x134]:
        device.key(code)
    device.axis(ABS_X, 128, 0, 255)
    device.axis(ABS_Y, 128, 0, 255)
    set_bit(device.events, 0x15)
    set_bit(device.ff, 0x50)
    return device^


def _motion_sensors() -> RecordedDevice:
    var device = RecordedDevice(
        "Sony Pad Clone Motion Sensors", 3, 0x054C, 0x9999, 0x0100
    )
    device.uniq = "aa:bb:cc"
    set_bit(device.properties, INPUT_PROP_ACCELEROMETER)
    device.sensor(ABS_X, 100, 8192)
    device.sensor(ABS_Y, -50, 8192)
    device.sensor(ABS_Z, 8192, 8192)
    device.sensor(ABS_RX, 1024, 1024)
    device.sensor(ABS_RY, 0, 1024)
    device.sensor(ABS_RZ, -2048, 1024)
    return device^


def _sine_pad() -> RecordedDevice:
    var device = RecordedDevice("Sine Pad", 3, 0x1234, 0x0001, 1)
    device.key(BTN_A)
    device.key(BTN_B)
    device.axis(ABS_X, 0, -32768, 32767)
    device.axis(ABS_Y, 0, -32768, 32767)
    set_bit(device.events, 0x15)
    set_bit(device.ff, 0x5A)
    return device^


def _late_pad() -> RecordedDevice:
    var device = RecordedDevice("Late Pad", 3, 0x1234, 0x0002, 1)
    device.key(BTN_A)
    device.axis(ABS_X, 0, -32768, 32767)
    device.axis(ABS_Y, 0, -32768, 32767)
    return device^


def _keyboard() -> RecordedDevice:
    var device = RecordedDevice("Keyboard", 3, 0x1111, 0x3333, 1)
    for code in range(1, 40):
        device.key(code)
    return device^


def _flight_stick() -> RecordedDevice:
    var device = RecordedDevice("Flight Stick", 3, 0x1111, 0x2222, 1)
    device.key(BTN_TRIGGER)
    device.axis(ABS_X, 0, -512, 511)
    device.axis(ABS_Y, 0, -512, 511)
    return device^


def _open(
    var device: RecordedDevice,
    mut database: MappingDatabase,
    use_deadzones: Bool = False,
) raises -> EvdevGamepad[RecordedDevice]:
    var info = probe_joystick(device, "/dev/input/event3")
    return EvdevGamepad(device^, info.value(), database, use_deadzones)


def _show(mut pad: EvdevGamepad[RecordedDevice]) -> String:
    _ = pad.update()
    ref joystick = pad.gamepad.joystick
    var text = String("raw")
    for index in range(joystick.axis_count()):
        text += " " + String(joystick.get_axis(index))
    text += " hats"
    for index in range(joystick.hat_count()):
        text += " " + String(joystick.get_hat(index))
    text += " buttons"
    for index in range(joystick.button_count()):
        if joystick.get_button(index):
            text += " " + String(index)
    text += " pad"
    for index in range(AXIS_COUNT):
        text += " " + String(pad.gamepad.get_axis(GamepadAxis(index)))
    text += " buttons"
    for index in range(BUTTON_COUNT):
        if pad.gamepad.get_button(GamepadButton(index)):
            text += " " + String(index)
    return text


def test_devices_are_probed_as_in_sdl() raises:
    var sony = _sony()
    var info = probe_joystick(sony, "/dev/input/event3")
    assert_equal(info.value().name, "Sony Pad Clone")
    assert_equal(
        guid_to_string(info.value().guid), "0300b7144c0500009999000000010000"
    )
    var elite = _elite()
    assert_equal(
        guid_to_string(probe_joystick(elite, "e").value().guid),
        "0300f5a65e0400009999000001000000",
    )
    var stick = _flight_stick()
    assert_equal(
        guid_to_string(probe_joystick(stick, "e").value().guid),
        "030087d3111100002222000001000000",
    )
    var keyboard = _keyboard()
    assert_false(probe_joystick(keyboard, "e"))


def test_probing_stops_where_the_device_does_not_answer() raises:
    var no_bits = _sony()
    no_bits.failing.append(eviocgbit(EV_ABS, 8))
    assert_false(probe_joystick(no_bits, "e"))
    var no_id = _sony()
    no_id.failing.append(EVIOCGID)
    assert_false(probe_joystick(no_id, "e"))
    var no_name = _sony()
    no_name.failing.append(eviocgname(128))
    assert_false(probe_joystick(no_name, "e"))
    # A device without its key bitmap the second time keeps its id.
    var no_keys = _sony()
    var keys = no_keys.keys.copy()
    _ = keys
    var ignored = RecordedDevice("Sony Motion Sensors", 3, 0x054C, 0x9999, 1)
    ignored.key(BTN_A)
    ignored.axis(ABS_X, 0, 0, 1)
    ignored.axis(ABS_Y, 0, 0, 1)
    assert_false(probe_joystick(ignored, "e"))


def test_the_automatic_mappings_match_sdl() raises:
    var database = default_mapping_database()
    var sony = _open(_sony(), database)
    # SDL_GetGamepadMapping writes the joystick's GUID, with its CRC.
    assert_equal(
        database.mapping_string(database.count() - 1, sony.info.guid),
        (
            "0300b7144c0500009999000000010000,Sony Pad Clone,a:b0,b:b1,x:b3,"
            "y:b2,back:b8,guide:b10,start:b9,leftstick:b11,rightstick:b12,"
            "leftshoulder:b4,rightshoulder:b5,dpup:h0.1,dpdown:h0.4,"
            "dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a3,righty:a4,"
            "lefttrigger:a2,righttrigger:a5,platform:Linux,"
        ),
    )
    var elite = _open(_elite(), database)
    # SDL writes dpup:a7,dpdown:a7,dpleft:a6,dpright:a6.
    assert_equal(
        database.mapping_string(database.count() - 1, elite.info.guid),
        (
            "0300f5a65e0400009999000001000000,Elite Clone,a:b0,b:b1,x:b2,y:b3,"
            "back:b4,guide:b6,start:b5,leftstick:b7,rightstick:b8,"
            "leftshoulder:h0.4,rightshoulder:h0.2,dpup:-a7,dpdown:+a7,"
            "dpleft:-a6,dpright:+a6,misc1:b15,paddle1:b11,paddle2:b13,"
            "paddle3:b12,paddle4:b14,leftx:a0,lefty:a1,rightx:a2,righty:a3,"
            "lefttrigger:a5,righttrigger:a4,platform:Linux,"
        ),
    )
    _ = sony^
    _ = elite^
    # A joystick that is not a gamepad, with no mapping, is refused.
    with assert_raises():
        _ = _open(_flight_stick(), database)


def test_a_sony_pad_reads_as_in_sdl() raises:
    var database = default_mapping_database()
    var pad = _open(_sony(), database)
    assert_equal(
        _show(pad),
        (
            "raw 128 128 -32768 128 128 -32768 hats 0 buttons 1 pad 128 128 128"
            " 128 0 0 buttons 1"
        ),
    )
    pad.source.push(EV_ABS, ABS_X, 255)
    pad.source.push(EV_ABS, ABS_Y, 0)
    pad.source.push(EV_SYN, SYN_REPORT, 0)
    pad.source.push(EV_KEY, BTN_WEST, 1)
    pad.source.push(EV_ABS, ABS_Z, 255)
    pad.source.push(EV_ABS, ABS_HAT0X, -1)
    pad.source.push(EV_ABS, ABS_HAT0Y, 1)
    pad.source.push(EV_SYN, SYN_REPORT, 0)
    var events = pad.update()
    assert_true(len(events) > 0)
    assert_equal(
        _show(pad),
        (
            "raw 32767 -32768 32767 128 128 -32768 hats 12 buttons 1 3 pad"
            " 32767 -32768 128 128 32767 0 buttons 1 2 12 13"
        ),
    )
    pad.source.push(EV_ABS, ABS_RX, 200)
    pad.source.push(EV_ABS, ABS_RX, 10)
    pad.source.push(EV_ABS, ABS_RY, 100)
    pad.source.push(EV_KEY, BTN_TR2, 1)
    assert_equal(
        _show(pad),
        (
            "raw 32767 -32768 32767 -30198 -7068 -32768 hats 12 buttons 1 3 7"
            " pad 32767 -32768 -30198 -7068 32767 0 buttons 1 2 12 13"
        ),
    )
    pad.source.set_value(ABS_X, 64)
    pad.source.set_value(ABS_HAT0X, 1)
    pad.source.hold_only(BTN_NORTH)
    pad.source.push(EV_SYN, SYN_DROPPED, 0)
    pad.source.push(EV_ABS, ABS_X, 0)
    pad.source.push(EV_KEY, 0x130, 1)
    pad.source.push(EV_SYN, SYN_REPORT, 0)
    pad.source.push(EV_KEY, 0x2FF, 1)
    pad.source.push(EV_ABS, 0x3F, 5)
    pad.source.push(EV_REL, REL_X, 3)
    pad.source.push(EV_SYN, 9, 0)
    pad.source.push(4, 4, 0)
    # SDL reads past its arrays for key 0x2FF and axis 0x3F, and writes to
    # a missing trackball for REL_X, so its run left those three out.
    assert_equal(
        _show(pad),
        (
            "raw -16320 128 -32768 128 128 -32768 hats 2 buttons 2 pad -16320"
            " 128 128 128 0 0 buttons 3 14"
        ),
    )
    assert_false(pad.gone)
    pad.source.ended = True
    _ = pad.update()
    assert_true(pad.gone)
    _ = pad.update()


def test_an_elite_pad_reads_as_in_sdl() raises:
    var database = default_mapping_database()
    var pad = _open(_elite(), database)
    # SDL presses all four d-pad buttons at rest: "buttons 11 12 13 14".
    assert_equal(
        _show(pad),
        (
            "raw 0 0 0 0 -32768 -32768 -1 -1 hats 0 buttons pad 0 0 0 0 0 0"
            " buttons"
        ),
    )
    for event in _elite_moves():
        pad.source.push(event.type, event.code, event.value)
    # SDL: "buttons 9 10 13 14 15 16".
    assert_equal(
        _show(pad),
        (
            "raw -32768 0 32767 0 32767 -13550 19660 -32768 hats 6 buttons 11"
            " 15 pad -32768 0 32767 0 9608 32767 buttons 9 10 11 14 15 16"
        ),
    )
    for event in _elite_hats():
        pad.source.push(event.type, event.code, event.value)
    # SDL: "buttons 9 11 12 15 16".
    assert_equal(
        _show(pad),
        (
            "raw 300 -32000 32767 0 32767 -13550 -328 9830 hats 4 buttons 11 15"
            " pad 300 -32000 32767 0 9608 32767 buttons 9 15 16"
        ),
    )


def test_dead_zones_scale_as_in_sdl() raises:
    var database = default_mapping_database()
    var pad = _open(_elite(), database, True)
    assert_equal(
        _show(pad),
        "raw 0 0 0 0 -32768 -32768 0 0 hats 0 buttons pad 0 0 0 0 0 0 buttons",
    )
    for event in _elite_moves():
        pad.source.push(event.type, event.code, event.value)
    assert_equal(
        _show(pad),
        (
            "raw -32768 0 32767 0 32767 -13550 19797 -32768 hats 6 buttons 11"
            " 15 pad -32768 0 32767 0 9608 32767 buttons 9 10 11 14 15 16"
        ),
    )
    for event in _elite_hats():
        pad.source.push(event.type, event.code, event.value)
    assert_equal(
        _show(pad),
        (
            "raw 173 -32121 32767 0 32767 -13550 0 9557 hats 4 buttons 11 15"
            " pad 173 -32121 32767 0 9608 32767 buttons 9 15 16"
        ),
    )


def _elite_moves() -> List[EvdevEvent]:
    return [
        EvdevEvent(EV_ABS, ABS_HAT0X, 60),
        EvdevEvent(EV_ABS, ABS_HAT0Y, -100),
        EvdevEvent(EV_ABS, ABS_HAT1X, 1),
        EvdevEvent(EV_ABS, ABS_HAT1Y, 1),
        EvdevEvent(EV_ABS, ABS_GAS, 1023),
        EvdevEvent(EV_ABS, ABS_BRAKE, 300),
        EvdevEvent(EV_KEY, 0x2C4, 1),
        EvdevEvent(EV_KEY, KEY_RECORD, 1),
        EvdevEvent(EV_ABS, ABS_X, -32768),
        EvdevEvent(EV_ABS, ABS_Y, 100),
        EvdevEvent(EV_ABS, ABS_RX, 32767),
        EvdevEvent(EV_ABS, ABS_RY, -200),
    ]


def _elite_hats() -> List[EvdevEvent]:
    return [
        EvdevEvent(EV_ABS, ABS_HAT0X, 1),
        EvdevEvent(EV_ABS, ABS_HAT0X, -1),
        EvdevEvent(EV_ABS, ABS_HAT0Y, -120),
        EvdevEvent(EV_ABS, ABS_HAT0Y, 30),
        EvdevEvent(EV_ABS, ABS_HAT1X, 0),
        EvdevEvent(EV_ABS, ABS_X, 64),
        EvdevEvent(EV_ABS, ABS_X, 300),
        EvdevEvent(EV_ABS, ABS_Y, -32000),
    ]


def test_gamepad_events_say_when_to_attack() raises:
    var database = default_mapping_database()
    var pad = _open(_sony(), database)
    _ = pad.update()
    pad.source.push(EV_KEY, BTN_WEST, 1)
    var attacks = 0
    for event in pad.update():
        if event.kind == GAMEPAD_BUTTON_DOWN and event.button == BUTTON_WEST:
            attacks += 1
    assert_equal(attacks, 1)


def test_bits_and_classes() raises:
    var bits = List[UInt8](length=2, fill=0)
    set_bit(bits, 9)
    assert_true(test_bit(bits, 9))
    assert_false(test_bit(bits, 8))
    assert_false(test_bit(bits, 16))
    assert_false(test_bit(bits, -1))
    assert_true(DeviceClass(0x1FF).is_valid())
    assert_false(DeviceClass(0x200).is_valid())
    assert_false(DeviceClass(-1).is_valid())
    assert_true(DeviceClass(5).has(DEVICE_JOYSTICK))
    assert_false(DEVICE_UNKNOWN.has(DEVICE_MOUSE))
    assert_equal(c_divide(-7, 2), -3)
    assert_equal(c_divide(7, 2), 3)
    assert_equal(c_divide(-8, 2), -4)


def _caps() -> EvdevCapabilities:
    return EvdevCapabilities()


def test_device_classes_follow_sdl() raises:
    var caps = _caps()
    set_bit(caps.properties, INPUT_PROP_ACCELEROMETER)
    assert_equal(guess_device_class(caps), DEVICE_ACCELEROMETER)
    caps = _caps()
    set_bit(caps.properties, INPUT_PROP_POINTING_STICK)
    assert_equal(guess_device_class(caps), DEVICE_MOUSE)
    for prop in [
        INPUT_PROP_TOPBUTTONPAD,
        INPUT_PROP_BUTTONPAD,
        INPUT_PROP_SEMI_MT,
    ]:
        caps = _caps()
        set_bit(caps.properties, prop)
        assert_equal(guess_device_class(caps), DEVICE_TOUCHPAD)
    # X, Y and Z, or RX, RY and RZ, without keys: an accelerometer.
    caps = _caps()
    set_bit(caps.events, EV_ABS)
    for code in [ABS_X, ABS_Y, ABS_Z]:
        set_bit(caps.absolutes, code)
    assert_equal(guess_device_class(caps), DEVICE_ACCELEROMETER)
    caps = _caps()
    set_bit(caps.events, EV_ABS)
    for code in [ABS_RX, ABS_RY, ABS_RZ]:
        set_bit(caps.absolutes, code)
    assert_equal(guess_device_class(caps), DEVICE_ACCELEROMETER)
    # A pen, a touchpad, a mouse and a touchscreen.
    var tools: List[Int] = [
        BTN_STYLUS,
        BTN_TOOL_PEN,
        BTN_TOOL_FINGER,
        BTN_MOUSE,
        BTN_TOUCH,
    ]
    var classes: List[DeviceClass] = [
        DEVICE_UNKNOWN,
        DEVICE_UNKNOWN,
        DEVICE_TOUCHPAD,
        DEVICE_MOUSE,
        DEVICE_TOUCHSCREEN,
    ]
    for index in range(len(tools)):
        caps = _caps()
        set_bit(caps.events, EV_ABS)
        set_bit(caps.events, EV_KEY)
        set_bit(caps.absolutes, ABS_X)
        set_bit(caps.absolutes, ABS_Y)
        set_bit(caps.keys, tools[index])
        assert_equal(guess_device_class(caps), classes[index])
    # Each sign of a joystick.
    for code in [ABS_RX, ABS_RY, ABS_RZ, 6, 7, 8, ABS_GAS, ABS_BRAKE]:
        caps = _caps()
        set_bit(caps.events, EV_ABS)
        set_bit(caps.absolutes, ABS_X)
        set_bit(caps.absolutes, ABS_Y)
        set_bit(caps.absolutes, code)
        set_bit(caps.events, EV_KEY)
        assert_equal(guess_device_class(caps), DEVICE_JOYSTICK)
    for key in [BTN_TRIGGER, BTN_A, 0x101]:
        caps = _caps()
        set_bit(caps.events, EV_ABS)
        set_bit(caps.absolutes, ABS_X)
        set_bit(caps.absolutes, ABS_Y)
        set_bit(caps.keys, key)
        assert_true(guess_device_class(caps).has(DEVICE_JOYSTICK))
    # X without Y, and Y without X, are not pointers.
    caps = _caps()
    set_bit(caps.events, EV_ABS)
    set_bit(caps.absolutes, ABS_X)
    set_bit(caps.keys, BTN_A)
    assert_equal(guess_device_class(caps), DEVICE_UNKNOWN)
    caps = _caps()
    set_bit(caps.absolutes, ABS_X)
    set_bit(caps.absolutes, ABS_Y)
    set_bit(caps.keys, BTN_A)
    assert_equal(guess_device_class(caps), DEVICE_UNKNOWN)
    # A relative mouse.
    caps = _caps()
    set_bit(caps.events, EV_REL)
    set_bit(caps.relatives, REL_X)
    set_bit(caps.relatives, REL_Y)
    set_bit(caps.keys, BTN_MOUSE)
    assert_equal(guess_device_class(caps), DEVICE_MOUSE)
    for missing in range(3):
        caps = _caps()
        if missing != 0:
            set_bit(caps.events, EV_REL)
        if missing != 1:
            set_bit(caps.relatives, REL_X)
        if missing != 2:
            set_bit(caps.relatives, REL_Y)
        set_bit(caps.keys, BTN_MOUSE)
        assert_equal(guess_device_class(caps), DEVICE_UNKNOWN)
    caps = _caps()
    set_bit(caps.events, EV_REL)
    set_bit(caps.relatives, REL_X)
    set_bit(caps.relatives, REL_Y)
    assert_equal(guess_device_class(caps), DEVICE_UNKNOWN)
    # Keys in the high blocks.
    for code in [0x160, 0x230]:
        caps = _caps()
        set_bit(caps.events, EV_KEY)
        set_bit(caps.keys, code)
        assert_equal(guess_device_class(caps), DEVICE_HAS_KEYS)
    caps = _caps()
    set_bit(caps.events, EV_KEY)
    set_bit(caps.keys, 0x2C0)
    assert_equal(guess_device_class(caps), DEVICE_UNKNOWN)
    # A full keyboard.
    caps = _caps()
    set_bit(caps.events, EV_KEY)
    for code in range(1, 32):
        set_bit(caps.keys, code)
    assert_equal(guess_device_class(caps), DeviceClass(0x02 | 0x80))
    caps = _caps()
    for code in range(1, 31):
        set_bit(caps.keys, code)
    assert_equal(guess_device_class(caps), DEVICE_UNKNOWN)
    assert_equal(DEVICE_KEYBOARD.value, 2)


def test_digital_hats_are_guessed_as_in_sdl() raises:
    var none = Optional[AbsInfo]()
    var unit = Optional(AbsInfo(0, -1, 1, 0, 0, 0))
    var analog = Optional(AbsInfo(0, -100, 100, 4, 2, 0))
    var bare = Optional(AbsInfo(0, -100, 100, 0, 0, 0))
    var fuzzy = Optional(AbsInfo(0, -100, 100, 1, 0, 0))
    var flat = Optional(AbsInfo(0, -100, 100, 0, 1, 0))
    var resolved = Optional(AbsInfo(0, -100, 100, 0, 0, 1))
    var low = Optional(AbsInfo(0, -1, 5, 1, 0, 0))
    assert_false(is_digital_hat(none, none))
    assert_true(is_digital_hat(analog, analog, True))
    assert_true(is_digital_hat(unit, none))
    assert_true(is_digital_hat(none, unit))
    assert_true(is_digital_hat(unit, unit))
    assert_false(is_digital_hat(unit, low))
    assert_false(is_digital_hat(low, unit))
    assert_true(is_digital_hat(bare, none))
    assert_true(is_digital_hat(none, bare))
    assert_true(is_digital_hat(bare, bare))
    assert_false(is_digital_hat(analog, bare))
    assert_false(is_digital_hat(bare, fuzzy))
    assert_false(is_digital_hat(flat, bare))
    assert_false(is_digital_hat(bare, resolved))


def test_layouts_number_inputs_as_in_sdl() raises:
    var caps = _caps()
    set_bit(caps.keys, 1)
    set_bit(caps.keys, BTN_A)
    set_bit(caps.keys, 0x2FE)
    set_bit(caps.absolutes, ABS_X)
    set_bit(caps.absolutes, ABS_HAT2X)
    set_bit(caps.absolutes, ABS_HAT2Y)
    set_bit(caps.absolutes, ABS_Y)
    var info = List[Optional[AbsInfo]](length=64, fill=None)
    info[ABS_X] = AbsInfo(0, 5, 5, 0, 0, 0)
    info[ABS_HAT2X] = AbsInfo(0, 0, 255, 0, 0, 0)
    info[ABS_HAT2Y] = AbsInfo(0, 0, 255, 3, 0, 0)
    var layout = EvdevLayout()
    layout.configure(caps, info)
    # Joystick buttons first, then the low codes.
    assert_equal(layout.key_map[BTN_A], 0)
    assert_equal(layout.key_map[0x2FE], 1)
    assert_equal(layout.key_map[1], 2)
    assert_equal(layout.buttons, 3)
    # An axis whose range is a point passes values through, clamped.
    assert_equal(layout.axis_correct(ABS_X, 40000), 32767)
    assert_equal(layout.axis_correct(ABS_X, -40000), -32768)
    assert_equal(layout.axis_correct(ABS_X, 7), 7)
    # Hat 2 is analog, and ABS_Y did not say its range.
    assert_false(layout.has_hat[2])
    assert_true(layout.has_abs[ABS_HAT2Y])
    assert_false(layout.has_abs[ABS_Y])
    assert_equal(layout.axes, 3)
    # Dead zones: the flat zone reads 0, a zero range keeps the slope 0.
    var dead = EvdevLayout()
    var zone = List[Optional[AbsInfo]](length=64, fill=None)
    zone[ABS_X] = AbsInfo(0, -100, 100, 0, 10, 0)
    zone[ABS_HAT2X] = AbsInfo(0, -10, 10, 0, 5, 0)
    zone[ABS_HAT2Y] = AbsInfo(0, -10, 10, 3, 0, 0)
    set_bit(caps.absolutes, ABS_HAT2X)
    dead.configure(caps, zone, True)
    assert_equal(dead.axis_correct(ABS_X, 5), 0)
    assert_equal(dead.axis_correct(ABS_X, 100), 32767)
    assert_equal(dead.axis_correct(ABS_X, -100), -32768)
    assert_equal(dead.abs_correct[ABS_HAT2X].coef2, 0)
    assert_equal(dead.axis_correct(ABS_HAT2X, 10), 0)


def test_hats_follow_sdl() raises:
    var caps = _caps()
    set_bit(caps.absolutes, ABS_HAT0X)
    set_bit(caps.absolutes, ABS_HAT0Y)
    var info = List[Optional[AbsInfo]](length=64, fill=None)
    info[ABS_HAT0X] = AbsInfo(0, -30, 30, 0, 0, 0)
    var layout = EvdevLayout()
    layout.configure(caps, info, use_hat_deadzones=False)
    assert_true(layout.has_hat[0])
    # The Y axis did not say its range, so it is -1 to 1.
    assert_equal(Int(layout.hat_correct[0].minimum[1]), -1)
    var state = EvdevState(layout^)
    var joystick = Joystick("Pad", JoystickGuid(), 0, 0, 1)
    # Without dead zones any motion counts.
    state.handle_hat(joystick, 0, 0, 5)
    assert_equal(joystick.get_hat(0), 2)
    state.handle_hat(joystick, 0, 0, -5)
    assert_equal(joystick.get_hat(0), 8)
    state.handle_hat(joystick, 0, 0, 0)
    assert_equal(joystick.get_hat(0), 0)
    # A value past the end widens the range.
    state.handle_hat(joystick, 0, 1, 7)
    assert_equal(Int(state.layout.hat_correct[0].maximum[1]), 7)
    assert_equal(joystick.get_hat(0), 4)
    state.handle_hat(joystick, 0, 1, -9)
    assert_equal(Int(state.layout.hat_correct[0].minimum[1]), -9)
    assert_equal(joystick.get_hat(0), 1)


def test_events_round_trip_through_bytes() raises:
    var bytes = encode_input_event(EV_ABS, ABS_RY, -200)
    bytes += encode_input_event(EV_KEY, 0x2C4, 1)
    bytes.append(7)
    var events = decode_input_events(bytes)
    assert_equal(len(events), 2)
    assert_equal(events[0].type, EV_ABS)
    assert_equal(events[0].code, ABS_RY)
    assert_equal(events[0].value, -200)
    assert_equal(events[1].code, 0x2C4)
    with assert_raises():
        _ = AbsInfo.from_bytes(List[UInt8](length=23, fill=0))
    var info_bytes = List[UInt8](length=24, fill=0)
    info_bytes[8] = 255
    assert_equal(AbsInfo.from_bytes(info_bytes).maximum, 255)
    with assert_raises():
        _ = InputId.from_bytes(List[UInt8](length=7, fill=0))
    assert_equal(
        InputId.from_bytes(List[UInt8](length=8, fill=1)).vendor, 0x0101
    )


def test_device_ids_are_fixed_up_as_in_sdl() raises:
    var keys = List[UInt8](length=96, fill=0)
    var elite = InputId(3, 0x045E, 0x0B05, 0x0903)
    assert_equal(fixup_device_id(elite, keys).version, 0x0903)
    set_bit(keys, 0x2C0)
    assert_equal(fixup_device_id(elite, keys).version, 0x0902)
    assert_equal(
        fixup_device_id(InputId(3, 0x045E, 0x0B05, 0x0904), keys).version,
        0x0904,
    )
    assert_equal(
        fixup_device_id(InputId(3, 0x045E, 0x0B06, 0x0903), keys).version,
        0x0903,
    )
    assert_equal(
        fixup_device_id(InputId(3, 0x045F, 0x0B05, 0x0903), keys).version,
        0x0903,
    )
    assert_equal(
        fixup_device_id(InputId(3, 0x3250, 0x1001, 5), keys).version, 0
    )
    assert_equal(
        fixup_device_id(InputId(3, 0x3250, 0x1002, 5), keys).version, 0
    )
    assert_equal(
        fixup_device_id(InputId(3, 0x3250, 0x1003, 5), keys).version, 5
    )


def _layout(keys: List[Int], axes: List[Int], hats: List[Int]) -> EvdevLayout:
    var caps = _caps()
    for code in keys:
        set_bit(caps.keys, code)
    var info = List[Optional[AbsInfo]](length=64, fill=None)
    for code in axes:
        set_bit(caps.absolutes, code)
        info[code] = AbsInfo(0, -100, 100, 4, 2, 0)
    for code in hats:
        set_bit(caps.absolutes, code)
        info[code] = AbsInfo(0, -1, 1, 0, 0, 0)
    var layout = EvdevLayout()
    layout.configure(caps, info)
    return layout^


def test_automatic_mappings_cover_each_convention() raises:
    assert_false(automatic_mapping(_layout([BTN_TRIGGER], [], []), VendorId(1)))
    # Shoulders on axes, triggers on the Linux spec's hat 2 axes, d-pad
    # buttons, sticks on Z and RZ.
    var linux = _layout(
        [
            BTN_GAMEPAD,
            BTN_DPAD_UP,
            BTN_DPAD_DOWN,
            BTN_DPAD_LEFT,
            BTN_DPAD_RIGHT,
        ],
        [
            ABS_HAT1X,
            ABS_HAT1Y,
            ABS_HAT2X,
            ABS_HAT2Y,
            ABS_X,
            ABS_Y,
            ABS_Z,
            ABS_RZ,
        ],
        [],
    )
    var raw = automatic_mapping(linux, VendorId(1)).value().copy()
    assert_equal(raw.buttons[9].kind, MAPPING_AXIS)
    assert_equal(raw.buttons[10].kind, MAPPING_AXIS)
    assert_equal(raw.axes[4].target, linux.abs_map[ABS_HAT2Y])
    assert_equal(raw.axes[5].target, linux.abs_map[ABS_HAT2X])
    assert_equal(raw.buttons[11].kind, MAPPING_BUTTON)
    assert_equal(raw.axes[2].target, linux.abs_map[ABS_Z])
    assert_equal(raw.axes[3].target, linux.abs_map[ABS_RZ])
    # Triggers on hat 2, then on buttons.
    var hat_triggers = _layout(
        [BTN_GAMEPAD, BTN_TL, BTN_TR],
        [],
        [ABS_HAT2X, ABS_HAT2Y, ABS_HAT0X, ABS_HAT0Y],
    )
    var hats = automatic_mapping(hat_triggers, VendorId(1)).value().copy()
    assert_equal(hats.axes[4].kind, MAPPING_HAT)
    assert_equal(hats.axes[4].target, (1 << 4) | 4)
    assert_equal(hats.buttons[9].kind, MAPPING_BUTTON)
    var button_triggers = _layout(
        [BTN_GAMEPAD, BTN_TL2, BTN_TR2], [ABS_HAT0X], []
    )
    var buttons = automatic_mapping(button_triggers, VendorId(1)).value().copy()
    assert_equal(buttons.axes[4].kind, MAPPING_BUTTON)
    assert_equal(buttons.axes[5].kind, MAPPING_BUTTON)
    # One analog d-pad axis alone is not a d-pad.
    assert_equal(buttons.buttons[11].kind.value, 0)
    # Android's brake and gas, and a left trigger only.
    var android = _layout([BTN_GAMEPAD, BTN_TR2], [ABS_BRAKE], [])
    var pedals = automatic_mapping(android, VendorId(1)).value().copy()
    assert_equal(pedals.axes[4].target, android.abs_map[ABS_BRAKE])
    assert_equal(pedals.axes[5].kind, MAPPING_BUTTON)
    var right_only = _layout([BTN_GAMEPAD, BTN_TL2], [ABS_RZ], [])
    var right = automatic_mapping(right_only, VendorId(1)).value().copy()
    assert_equal(right.axes[4].kind, MAPPING_BUTTON)
    assert_equal(right.axes[5].target, right_only.abs_map[ABS_RZ])
    # Shoulders from hat 1 when only one shoulder button exists.
    var one_shoulder = _layout(
        [BTN_GAMEPAD, BTN_TL], [], [ABS_HAT1X, ABS_HAT1Y]
    )
    var shoulder = automatic_mapping(one_shoulder, VendorId(1)).value().copy()
    assert_equal(shoulder.buttons[9].kind, MAPPING_HAT)
    # Shoulder axes when one is a button.
    var mixed = _layout([BTN_GAMEPAD, BTN_TR], [ABS_HAT1Y, ABS_HAT1X], [])
    var mixed_raw = automatic_mapping(mixed, VendorId(1)).value().copy()
    assert_equal(mixed_raw.buttons[9].kind, MAPPING_AXIS)
    assert_equal(mixed_raw.buttons[10].kind, MAPPING_BUTTON)
    var left_button = _layout([BTN_GAMEPAD, BTN_TL], [ABS_HAT1Y, ABS_HAT1X], [])
    var left_raw = automatic_mapping(left_button, VendorId(1)).value().copy()
    assert_equal(left_raw.buttons[9].kind, MAPPING_BUTTON)
    assert_equal(left_raw.buttons[10].kind, MAPPING_AXIS)
    # Microsoft pads without all four paddles, and RX without RY.
    var three = _layout([BTN_GAMEPAD, 0x2C4, 0x2C5, 0x2C6], [ABS_X, ABS_RX], [])
    var three_raw = automatic_mapping(three, VendorId(0x045E)).value().copy()
    assert_equal(three_raw.buttons[16].kind.value, 0)
    assert_equal(three_raw.buttons[15].kind.value, 0)
    assert_equal(three_raw.axes[0].kind.value, 0)
    assert_equal(three_raw.axes[2].kind.value, 0)
    for missing in range(4):
        var codes: List[Int] = [BTN_GAMEPAD]
        for paddle in range(4):
            if paddle != missing:
                codes.append(0x2C4 + paddle)
        var partial = (
            automatic_mapping(
                _layout(codes, [ABS_Y, ABS_RY, ABS_Z], []), VendorId(0x045E)
            )
            .value()
            .copy()
        )
        assert_equal(partial.buttons[16].kind.value, 0)
    # Each button of the face and the middle.
    var face = _layout(
        [
            BTN_GAMEPAD,
            BTN_TL,
            BTN_B,
            BTN_X,
            BTN_Y,
            BTN_SELECT,
            BTN_START,
            BTN_THUMBL,
            BTN_THUMBR,
            BTN_MODE,
            BTN_TR,
        ],
        [],
        [],
    )
    var face_raw = automatic_mapping(face, VendorId(1)).value().copy()
    for button in range(11):
        assert_equal(face_raw.buttons[button].kind, MAPPING_BUTTON)
    var sony = (
        automatic_mapping(_layout([BTN_GAMEPAD], [], []), VendorId(0x054C))
        .value()
        .copy()
    )
    assert_equal(sony.buttons[2].kind.value, 0)


def test_requests_have_the_kernel_numbers() raises:
    assert_equal(eviocgbit(EV_KEY, 96), 0x80604521)
    assert_equal(eviocgabs(ABS_HAT0X), 0x80184550)
    assert_equal(EVIOCGID, 0x80084502)
    assert_equal(eviocgname(128), 0x80804506)
    assert_equal(eviocgprop(8), 0x80084509)
    assert_equal(eviocgkey(96), 0x80604518)
    assert_equal(jsiocgname(128), 0x80806A13)


def test_capabilities_need_four_bitmaps() raises:
    for request in [
        eviocgbit(0, 8),
        eviocgbit(EV_KEY, 96),
        eviocgbit(EV_REL, 8),
        eviocgbit(EV_ABS, 8),
    ]:
        var device = _sony()
        device.failing.append(request)
        assert_false(read_capabilities(device))
    var no_props = _sony()
    no_props.failing.append(eviocgprop(8))
    assert_true(read_capabilities(no_props))
    var no_abs = _sony()
    no_abs.failing.append(eviocgabs(ABS_X))
    var info = read_absinfo(no_abs, no_abs.absolutes.copy())
    assert_false(info[ABS_X])
    assert_true(info[ABS_Y])


def test_opening_needs_the_keys_and_axes() raises:
    for request in [
        eviocgbit(EV_KEY, 96),
        eviocgbit(EV_REL, 8),
        eviocgbit(EV_ABS, 8),
    ]:
        var database = default_mapping_database()
        var device = _sony()
        var info = probe_joystick(device, "e")
        device.failing.append(request)
        with assert_raises():
            _ = EvdevGamepad(device^, info.value(), database)
    # A device that stops giving its state is read from events alone.
    var database = default_mapping_database()
    var quiet = _sony()
    var info = probe_joystick(quiet, "e")
    quiet.failing.append(eviocgkey(96))
    quiet.failing.append(eviocgabs(ABS_X))
    quiet.failing.append(eviocgabs(ABS_HAT0X))
    var pad = EvdevGamepad(quiet^, info.value(), database)
    _ = pad.update()
    assert_false(pad.gamepad.joystick.get_button(1))


def test_event_nodes_are_found_in_sdl_order() raises:
    with TestScratch():
        var root = temporary_path("input")
        var sysfs = temporary_path("sys")
        makedirs(root)
        makedirs(sysfs + "/event5/device/js1")
        makedirs(sysfs + "/event7/device/js0")
        makedirs(sysfs + "/event9/device")
        for name in [
            "event10",
            "event2",
            "event5",
            "event7",
            "event9",
            "mice",
            "eventx",
            "event",
            "js0",
        ]:
            with open(root + "/" + name, "w") as file:
                file.write("")
        var nodes = list_event_nodes(root, sysfs)
        var names = List[String]()
        for node in nodes:
            names.append(String(node[byte = root.byte_length() + 1 :]))
        assert_equal(names[0], "event7")
        assert_equal(names[1], "event5")
        assert_equal(names[2], "event2")
        assert_equal(names[3], "event9")
        assert_equal(names[4], "event10")
        assert_equal(len(names), 5)
        assert_equal(event_joystick_index(sysfs, 7), 0)
        # Each order of a node with a js number and one without, whatever
        # order the folder lists them in.
        assert_true(_before("event5", "event9", sysfs))
        assert_false(_before("event9", "event5", sysfs))
        assert_equal(event_joystick_index(sysfs, 9), -1)
        assert_equal(event_joystick_index(sysfs, 3), -1)
        assert_equal(len(list_event_nodes(root + "/missing", sysfs)), 0)
        assert_true(is_event_node("/dev/input/event12"))
        assert_true(is_event_node("event0"))
        assert_false(is_event_node("event"))
        assert_false(is_event_node("event1a"))
        assert_false(is_event_node("mouse0"))
        # Regular files are not input devices.
        var database = default_mapping_database()
        assert_equal(len(open_gamepads(database, root, sysfs)), 0)
        var file = EvdevFile(root + "/event2")
        var buffer = List[UInt8](length=8, fill=0)
        assert_true(file.query(eviocgbit(0, 8), buffer) < 0)
        assert_true(file.readable())
        assert_equal(file.read_into(buffer), 0)
        assert_equal(file.write_from(buffer), 8)
        with assert_raises():
            _ = EvdevFile(root + "/missing")


def test_more_device_classes() raises:
    var caps = _caps()
    set_bit(caps.events, EV_ABS)
    set_bit(caps.absolutes, ABS_Y)
    set_bit(caps.keys, BTN_A)
    assert_equal(guess_device_class(caps), DEVICE_UNKNOWN)
    assert_equal(len(decode_input_events(List[UInt8]())), 0)


def test_hat_dead_zones() raises:
    var caps = _caps()
    set_bit(caps.absolutes, ABS_HAT0X)
    var info = List[Optional[AbsInfo]](length=64, fill=None)
    info[ABS_HAT0X] = AbsInfo(0, -30, 30, 0, 0, 0)
    var layout = EvdevLayout()
    layout.configure(caps, info)
    assert_true(layout.hat_correct[0].use_deadzones)
    var state = EvdevState(layout^)
    var joystick = Joystick("Pad", JoystickGuid(), 0, 0, 1)
    # Inside a third of the range is the center.
    state.handle_hat(joystick, 0, 0, 5)
    assert_equal(joystick.get_hat(0), 0)
    state.handle_hat(joystick, 0, 0, -5)
    assert_equal(joystick.get_hat(0), 0)
    state.handle_hat(joystick, 0, 0, 20)
    assert_equal(joystick.get_hat(0), 2)
    state.handle_hat(joystick, 0, 0, -20)
    assert_equal(joystick.get_hat(0), 8)
    # Other sync codes do not end a dropped report.
    state.recovering_from_dropped = True
    assert_false(state.handle_event(joystick, EvdevEvent(EV_SYN, 9, 0)))
    assert_true(state.recovering_from_dropped)
    assert_true(state.handle_event(joystick, EvdevEvent(EV_SYN, SYN_REPORT, 0)))


def test_state_reads_skip_what_the_device_does_not_say() raises:
    var database = default_mapping_database()
    var pad = _open(_sony(), database)
    pad.source.fail(eviocgabs(ABS_X))
    pad.source.set_value(ABS_X, 0)
    pad.source.set_value(ABS_Y, 0)
    # A dropped report reads the whole state again; ABS_X does not answer.
    pad.source.push(EV_SYN, SYN_DROPPED, 0)
    pad.source.push(EV_SYN, SYN_REPORT, 0)
    _ = pad.update()
    assert_equal(pad.gamepad.joystick.get_axis(0), 128)
    assert_equal(pad.gamepad.joystick.get_axis(1), -32768)
    # A short read decodes to nothing.
    pad.source.push_bytes(3)
    assert_equal(len(pad.update()), 0)


def test_a_classic_joystick_node_gives_its_name() raises:
    var device = _sony()
    device.classic = True
    var info = probe_joystick(device, "/dev/input/js0")
    assert_equal(info.value().name, "Sony Pad Clone")
    assert_equal(info.value().id.vendor, 0)
    device.fail(eviocgbit(EV_KEY, 96))
    assert_true(probe_joystick(device, "/dev/input/js0"))


def test_recorded_devices_open_as_gamepads() raises:
    var database = default_mapping_database()
    var pads = open_gamepads_with[RecordedDevice](
        database, ["keyboard", "missing", "stick", "sony"]
    )
    assert_equal(len(pads), 1)
    assert_equal(pads[0].info.name, "Sony Pad Clone")


def test_node_names_and_sysfs_corners() raises:
    assert_false(is_event_node("event1."))
    with TestScratch():
        var root = temporary_path("empty")
        var sysfs = temporary_path("sysfs")
        makedirs(root)
        for name in ["js", "jsx", "js-", "input5"]:
            makedirs(sysfs + "/event4/device/" + name)
        assert_equal(len(list_event_nodes(root, sysfs)), 0)
        var database = default_mapping_database()
        assert_equal(len(open_gamepads(database, root, sysfs)), 0)
        # "js-" sorts last, and has no digits.
        assert_equal(event_joystick_index(sysfs, 4), 0)


def _near(a: Float32, b: Float32) raises:
    assert_true(abs(a - b) < 1e-5, String(a) + " is not " + String(b))


def _paired(
    mut database: MappingDatabase,
) raises -> EvdevGamepad[RecordedDevice]:
    var pads = open_gamepads_with[RecordedDevice](
        database, ["/x/event3", "/x/event4"]
    )
    assert_equal(len(pads), 1)
    return pads.pop(0)


def test_motion_sensors_read_as_in_sdl() raises:
    var database = default_mapping_database()
    var pad = _paired(database)
    assert_true(pad.gamepad.has_sensor(SENSOR_GYRO))
    assert_true(pad.gamepad.has_sensor(SENSOR_ACCEL))
    assert_equal(pad.gamepad.sensor_data_rate(SENSOR_GYRO).value, 0)
    assert_true(pad.set_sensor_enabled(SENSOR_ACCEL, True))
    assert_true(pad.set_sensor_enabled(SENSOR_GYRO, True))
    assert_true(pad.gamepad.sensor_enabled(SENSOR_GYRO))
    _ = pad.update_at(Duration64(0))
    # SDL: "open gyro 0 0 0 accel 0 0 0".
    assert_equal(pad.gamepad.sensor_data(SENSOR_ACCEL)[0], 0)
    pad.sensor_sources[0].push(EV_ABS, ABS_X, 4096)
    pad.sensor_sources[0].push(EV_ABS, ABS_RY, -512)
    pad.sensor_sources[0].push(4, 5, 1000)
    pad.sensor_sources[0].push(EV_SYN, SYN_REPORT, 0)
    var events = pad.update_at(Duration64(0))
    assert_equal(len(events), 2)
    assert_equal(events[0].kind, GAMEPAD_SENSOR_UPDATE)
    assert_equal(events[0].sensor, SENSOR_GYRO)
    _near(Float32(events[1].sensor_timestamp.value * 1e6), 1000)
    # SDL: "report gyro 0 -0.008727 0 accel 4.903325 0 0".
    _near(pad.gamepad.sensor_data(SENSOR_GYRO)[1], -0.008727)
    _near(pad.gamepad.sensor_data(SENSOR_ACCEL)[0], 4.903325)
    _near(Float32(pad.gamepad.acceleration(SENSOR_ACCEL, 0).value), 4.903325)
    _near(
        Float32(pad.gamepad.angular_velocity(SENSOR_GYRO, 1).value), -0.008727
    )
    pad.sensor_sources[0].push(EV_SYN, SYN_DROPPED, 0)
    pad.sensor_sources[0].push(EV_ABS, ABS_X, 1)
    pad.sensor_sources[0].push(EV_SYN, SYN_REPORT, 0)
    _ = pad.update_at(Duration64(0))
    # SDL: "dropped gyro 0.017453 0 -0.034907 accel 0.119710 -0.059855
    # 9.806650".
    var gyro = pad.gamepad.sensor_data(SENSOR_GYRO)
    _near(gyro[0], 0.017453)
    _near(gyro[2], -0.034907)
    var accel = pad.gamepad.sensor_data(SENSOR_ACCEL)
    _near(accel[0], 0.119710)
    _near(accel[1], -0.059855)
    _near(accel[2], 9.806650)
    assert_true(pad.set_sensor_enabled(SENSOR_GYRO, False))
    assert_true(pad.set_sensor_enabled(SENSOR_ACCEL, False))
    assert_false(pad.report_sensor)
    with assert_raises():
        _ = pad.set_sensor_enabled(SensorType(5), True)
    with assert_raises():
        _ = pad.gamepad.acceleration(SENSOR_GYRO, 0)
    with assert_raises():
        _ = pad.gamepad.angular_velocity(SENSOR_ACCEL, 0)


def test_rumble_and_lights_follow_sdl() raises:
    var database = default_mapping_database()
    var pad = _paired(database)
    var now = Duration64(0)
    var ms = Duration64(0.001, SECOND)
    assert_true(pad.rumble_at(0x1000, 0x2000, ms.scaled(100.0), now))
    assert_true(pad.rumble_at(0x1000, 0x2000, ms.scaled(100.0), now))
    assert_true(pad.rumble_at(0x3000, 0, Duration64(0), now))
    assert_equal(len(pad.source.log), 4)
    assert_equal(
        pad.source.log[0],
        (
            "EVIOCSFF type 0x50 id 0 length 65535 strong 4096 weak 8192"
            " magnitude 0"
        ),
    )
    assert_equal(pad.source.log[1], "write type 0x15 code 0 value 1")
    assert_equal(
        pad.source.log[2],
        "EVIOCSFF type 0x50 id 0 length 65535 strong 12288 weak 0 magnitude 0",
    )
    assert_false(pad.rumble_triggers_at(1, 2, ms.scaled(100.0), now))
    assert_true(pad.rumble_triggers_at(0, 0, ms.scaled(100.0), now))
    assert_false(pad.set_led_at(1, 2, 3, now))
    assert_true(pad.set_led_at(1, 2, 3, now))
    assert_false(pad.set_led_at(0, 0, 0, now))
    with assert_raises():
        _ = pad.rumble_at(-1, 0, now, now)
    with assert_raises():
        _ = pad.set_led_at(0, 256, 0, now)
    # A sine pad gets the average strength.
    var sine = open_gamepads_with[RecordedDevice](database, ["/x/event10"])
    assert_true(sine[0].rumble_at(0x1000, 0x2001, ms.scaled(100.0), now))
    assert_equal(
        sine[0].source.log[0],
        "EVIOCSFF type 0x51 id 0 length 65535 strong 90 weak 0 magnitude 3072",
    )
    # After 100 ms the rumble stops; SDL sends a zero sine.
    _ = sine[0].update_at(ms.scaled(150.0))
    assert_equal(
        sine[0].source.log[2],
        "EVIOCSFF type 0x51 id 0 length 65535 strong 90 weak 0 magnitude 0",
    )


def test_rumble_resends_and_recovers() raises:
    var database = default_mapping_database()
    var pad = _paired(database)
    var second = Duration64(1, SECOND)
    # A rumble with no end is not sent again.
    assert_true(pad.rumble_at(100, 200, Duration64(0), Duration64(0)))
    _ = pad.update_at(second.scaled(5.0))
    assert_equal(len(pad.source.log), 2)
    # Every 2 seconds a timed rumble is sent again.
    assert_true(pad.rumble_at(100, 300, second.scaled(10.0), Duration64(0)))
    _ = pad.update_at(second)
    assert_equal(len(pad.source.log), 4)
    _ = pad.update_at(second.scaled(2.5))
    assert_equal(len(pad.source.log), 6)
    # A lost effect is uploaded again as a new one.
    pad.source.fail(EVIOCSFF)
    assert_false(pad.rumble_at(5, 6, Duration64(0), second.scaled(3.0)))
    var plain = open_gamepads_with[RecordedDevice](database, ["/x/event20"])
    assert_false(plain[0].rumble_at(1, 1, Duration64(0), Duration64(0)))
    var mute = _paired(database)
    mute.source.write_fails = True
    assert_false(mute.rumble_at(1, 1, Duration64(0), Duration64(0)))


def test_sensor_and_rumble_corners() raises:
    var database = default_mapping_database()
    # A lost effect that uploads again as a new one.
    var pad = _paired(database)
    assert_true(pad.rumble(100, 200, Duration64(0)))
    pad.source.lose_effect = True
    assert_true(pad.rumble_at(300, 400, Duration64(0), Duration64(0)))
    assert_equal(pad.effect_id, 1)
    # A sensor device that goes away cannot be turned on again.
    assert_true(pad.set_sensor_enabled(SENSOR_GYRO, True))
    pad.sensor_sources[0].unplug()
    _ = pad.update_at(Duration64(0))
    assert_true(pad.sensor_gone)
    _ = pad.update_at(Duration64(0))
    assert_true(pad.set_sensor_enabled(SENSOR_GYRO, False))
    assert_false(pad.set_sensor_enabled(SENSOR_GYRO, True))
    # Nor can one that no longer opens.
    var moved = _paired(database)
    moved.sensor_path = "/x/missing"
    assert_false(moved.set_sensor_enabled(SENSOR_GYRO, True))
    # A sensor device that does not open, or does not give its axes,
    # gives no sensors.
    for path in ["/x/missing", "/x/deaf"]:
        var source = RecordedDevice.open("/x/event3")
        var info = probe_joystick(source, "/x/event3")
        var lone = EvdevGamepad(
            source^, info.value(), database, sensor_path=path
        )
        assert_false(lone.gamepad.has_sensor(SENSOR_GYRO))
    # A device that does not say who it is is no sensor device.
    var anonymous = RecordedDevice.open("/x/event4")
    anonymous.fail(EVIOCGID)
    assert_false(probe_sensor(anonymous))


def test_sensor_layout_and_state_corners() raises:
    # No sensor axes: no sensors, and nothing to send.
    var none = SensorLayout()
    var info = List[Optional[AbsInfo]](length=64, fill=None)
    none.configure(List[UInt8](length=8, fill=0), info)
    assert_false(none.has_accelerometer)
    assert_false(none.has_gyro)
    var joystick = Joystick("Pad", JoystickGuid(), 0, 0, 0)
    var quiet = SensorState(none)
    quiet.apply_state(joystick, info)
    # Two of the three axes of each sensor are no sensor.
    for missing in [ABS_Y, ABS_Z]:
        var two = List[UInt8](length=8, fill=0)
        for code in [ABS_X, ABS_Y, ABS_Z]:
            if code != missing:
                set_bit(two, code)
                set_bit(two, code + 3)
        var layout = SensorLayout()
        layout.configure(two, info)
        assert_false(layout.has_accelerometer)
        assert_false(layout.has_gyro)
    # All six axes, but one of each without its range: no sensors.
    var bits = List[UInt8](length=8, fill=0)
    for code in [ABS_X, ABS_Y, ABS_Z, ABS_RX, ABS_RY, ABS_RZ]:
        set_bit(bits, code)
    info[ABS_X] = AbsInfo(0, -32768, 32767, 0, 0, 8192)
    info[ABS_RX] = AbsInfo(0, -32768, 32767, 0, 0, 1024)
    var partial = SensorLayout()
    partial.configure(bits, info)
    assert_false(partial.has_accelerometer)
    assert_false(partial.has_gyro)
    # A full layout reads a state with an axis missing as 0 there.
    for code in [ABS_Y, ABS_Z]:
        info[code] = AbsInfo(1, -32768, 32767, 0, 0, 8192)
    for code in [ABS_RY, ABS_RZ]:
        info[code] = AbsInfo(1, -32768, 32767, 0, 0, 1024)
    var full = SensorLayout()
    full.configure(bits, info)
    assert_true(full.has_gyro)
    var state = SensorState(full)
    joystick.add_sensor(SENSOR_GYRO, Frequency(0))
    joystick.add_sensor(SENSOR_ACCEL, Frequency(0))
    joystick.set_sensor_enabled(SENSOR_GYRO, True)
    joystick.set_sensor_enabled(SENSOR_ACCEL, True)
    info[ABS_X] = None
    info[ABS_RX] = None
    state.apply_state(joystick, info)
    assert_equal(joystick.sensors[0].data[0], 0)
    # Events the sensor loop does not use change nothing.
    for event in [
        EvdevEvent(EV_ABS, ABS_HAT0X, 5),
        EvdevEvent(EV_MSC, 0, 5),
        EvdevEvent(EV_KEY, BTN_A, 1),
        EvdevEvent(EV_SYN, 1, 0),
    ]:
        assert_false(state.handle_event(joystick, event))
    # The sensor clock wraps at 2^31.
    _ = state.handle_event(joystick, EvdevEvent(EV_MSC, MSC_TIMESTAMP, 100))
    _ = state.handle_event(joystick, EvdevEvent(EV_MSC, MSC_TIMESTAMP, 50))
    assert_equal(state.sensor_tick, 100 + 0x7FFFFFFF - 100 + 50 + 1)
    # While recovering, only a report counts.
    _ = state.handle_event(joystick, EvdevEvent(EV_SYN, SYN_DROPPED, 0))
    assert_false(state.handle_event(joystick, EvdevEvent(EV_SYN, 1, 0)))
    assert_true(state.handle_event(joystick, EvdevEvent(EV_SYN, SYN_REPORT, 0)))


def test_the_hub_follows_devices_as_sdl_does() raises:
    with TestScratch():
        var root = temporary_path("hub")
        var sysfs = temporary_path("hubsys")
        makedirs(root)
        for name in ["event1", "event3", "event4", "event10"]:
            with open(root + "/" + name, "w") as file:
                file.write("")
        var database = default_mapping_database()
        var hub = EvdevHub[RecordedDevice](root, sysfs)
        var changes = hub.detect_at(database, Duration64(0))
        # SDL: "added Sony Pad Clone", "added Sine Pad".
        assert_equal(len(changes), 2)
        assert_equal(changes[0].kind, GAMEPAD_ADDED)
        assert_equal(changes[0].name, "Sony Pad Clone")
        assert_equal(changes[1].name, "Sine Pad")
        assert_true(hub.pads[0].gamepad.has_sensor(SENSOR_ACCEL))
        assert_false(hub.pads[1].gamepad.has_sensor(SENSOR_ACCEL))
        with open(root + "/event20", "w") as file:
            file.write("")
        # Not three seconds yet.
        assert_equal(len(hub.detect_at(database, Duration64(1, SECOND))), 0)
        changes = hub.detect_at(database, Duration64(3, SECOND))
        assert_equal(len(changes), 1)
        assert_equal(changes[0].name, "Late Pad")
        # An unplugged pad is dropped.
        hub.pads[0].source.unplug()
        _ = hub.pads[0].update_at(Duration64(3, SECOND))
        assert_true(hub.pads[0].gone)
        changes = hub.detect_at(database, Duration64(4, SECOND))
        assert_equal(len(changes), 1)
        assert_equal(changes[0].kind, GAMEPAD_REMOVED)
        assert_equal(changes[0].path, root + "/event3")
        assert_equal(len(hub.pads), 2)
        # An unchanged folder is not scanned again.
        assert_equal(len(hub.detect_at(database, Duration64(10, SECOND))), 0)
        assert_true(DeviceChangeKind(1).is_valid())
        assert_false(DeviceChangeKind(2).is_valid())
        var missing = EvdevHub[RecordedDevice](root + "/none", sysfs)
        assert_equal(len(missing.detect(database)), 0)
        # A pad that a HIDAPI driver runs is skipped.
        var shared = EvdevHub[RecordedDevice](root, sysfs)
        changes = shared.detect_at(
            database, Duration64(0), [(0x054C << 16) | 0x9999]
        )
        assert_equal(len(changes), 2)
        assert_equal(changes[0].name, "Sine Pad")
        assert_equal(changes[1].name, "Late Pad")
        assert_false(folder_change_time(root + "/none"))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
