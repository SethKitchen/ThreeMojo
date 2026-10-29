# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.gamepad.hidapi`, SDL's HIDAPI joystick layer.

The drivers' own tests compare whole transcripts with SDL. These tests
cover the layer around them: which driver takes a device, the mapping
SDL makes for a HIDAPI pad (`SDL_CreateMappingForHIDAPIGamepad`), and the
hub that adds and drops devices. An Xbox Series pad on Bluetooth is the
subject, since its driver connects it as soon as it starts.
"""

from std.os import makedirs
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.gamepad.guid import (
    BUS_USB,
    DRIVER_HIDAPI,
    JoystickGuid,
    ProductId,
    VendorId,
    create_joystick_guid,
)
from extensions.gamepad.hid import (
    HID_BUS_BLUETOOTH,
    HID_BUS_USB,
    HidBus,
    HidDeviceInfo,
)
from extensions.gamepad.hid_device import HidapiDevice
from extensions.gamepad.hidapi import (
    HID_DRIVER_NONE,
    HID_DRIVER_PS4,
    HID_DRIVER_PS5,
    HID_DRIVER_XBOXONE,
    HidDriverKind,
    HidGamepad,
    HidHub,
    _driver_with_device,
    create_mapping_for_hidapi_gamepad,
    device_driver,
    game_controller_type,
    is_device_supported,
)
from extensions.gamepad.ids import (
    GAMEPAD_TYPE_PS4,
    GAMEPAD_TYPE_PS5,
    GAMEPAD_TYPE_STANDARD,
    GAMEPAD_TYPE_XBOXONE,
    GamepadType,
)
from extensions.gamepad.joystick import SENSOR_GYRO
from extensions.gamepad.linux import (
    GAMEPAD_ADDED,
    GAMEPAD_REMOVED,
    default_mapping_database,
)
from units.si import Duration64, Frequency, SECOND
from _gamepad_hid_script import ScriptedHid, hex_bytes
from test_scratch import TestScratch, temporary_path

comptime STANDARD = (
    "none,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,"
    "dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,"
    "leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,"
    "rightx:a2,righty:a3,start:b6,x:b2,y:b3,"
)


def _seconds(value: Float64) -> Duration64:
    return Duration64(value, SECOND)


def _info(
    path: String,
    vendor: Int,
    product: Int,
    name: String,
    bus: HidBus = HID_BUS_BLUETOOTH,
    usage_page: Int = 1,
    usage: Int = 5,
    serial: String = "",
) -> HidDeviceInfo:
    return HidDeviceInfo(
        path,
        VendorId(vendor),
        ProductId(product),
        0x509,
        serial,
        "",
        name,
        usage_page,
        usage,
        -1,
        bus,
    )


def _xbox(path: String = "/dev/hidraw0") -> HidDeviceInfo:
    return _info(path, 0x045E, 0x0B13, "Xbox Wireless Controller")


def _dualsense(
    path: String = "/dev/hidraw9", serial: String = ""
) -> HidDeviceInfo:
    return _info(
        path,
        0x054C,
        0x0CE6,
        "DualSense Wireless Controller",
        HID_BUS_USB,
        serial=serial,
    )


def _guid(vendor: Int, product: Int, kind: Int = 0) raises -> JoystickGuid:
    var guid = create_joystick_guid(
        BUS_USB,
        VendorId(vendor),
        ProductId(product),
        0,
        "",
        "",
        DRIVER_HIDAPI,
        0,
    )
    guid.data[15] = UInt8(kind)
    return guid


def _mapping(
    vendor: Int,
    product: Int,
    kind: Int = 0,
    type: GamepadType = GAMEPAD_TYPE_STANDARD,
) raises -> String:
    return create_mapping_for_hidapi_gamepad(_guid(vendor, product, kind), type)


def test_driver_kind() raises:
    assert_true(HID_DRIVER_NONE.is_valid())
    assert_true(HID_DRIVER_XBOXONE.is_valid())
    assert_false(HidDriverKind(4).is_valid())
    assert_false(HidDriverKind(-2).is_valid())


def test_device_driver() raises:
    assert_true(device_driver(HidapiDevice(_xbox())) == HID_DRIVER_XBOXONE)
    var sony = _info("p", 0x054C, 0x09CC, "Wireless Controller")
    assert_true(device_driver(HidapiDevice(sony)) == HID_DRIVER_PS4)
    var five = _info("p", 0x054C, 0x0CE6, "DualSense Wireless Controller")
    assert_true(device_driver(HidapiDevice(five)) == HID_DRIVER_PS5)
    # A collection that is not a game controller.
    var keyboard = _info("p", 0x045E, 0x0B13, "Pad", usage_page=0x0C)
    assert_true(device_driver(HidapiDevice(keyboard)) == HID_DRIVER_NONE)
    var mouse = _info("p", 0x045E, 0x0B13, "Pad", usage=2)
    assert_true(device_driver(HidapiDevice(mouse)) == HID_DRIVER_NONE)
    # No usage at all is allowed, and a joystick usage too.
    var bare = _info("p", 0x045E, 0x0B13, "Pad", usage_page=0, usage=0)
    assert_true(device_driver(HidapiDevice(bare)) == HID_DRIVER_XBOXONE)
    var stick = _info("p", 0x045E, 0x0B13, "Pad", usage=4)
    assert_true(device_driver(HidapiDevice(stick)) == HID_DRIVER_XBOXONE)
    var multi = _info("p", 0x045E, 0x0B13, "Pad", usage=8)
    assert_true(device_driver(HidapiDevice(multi)) == HID_DRIVER_XBOXONE)
    # Valve's devices skip the usage check; no driver here takes them.
    var valve = _info("p", 0x28DE, 0x1102, "Steam", usage_page=0xFF00)
    assert_true(device_driver(HidapiDevice(valve)) == HID_DRIVER_NONE)
    # A device SDL ignores, and one no driver knows.
    var ignored = _info("p", 0x045E, 0x009D, "Pad", bus=HID_BUS_USB)
    assert_true(device_driver(HidapiDevice(ignored)) == HID_DRIVER_NONE)
    var unknown = _info("p", 0x1234, 0x5678, "Pad")
    assert_true(device_driver(HidapiDevice(unknown)) == HID_DRIVER_NONE)
    assert_true(
        is_device_supported(VendorId(0x054C), ProductId(0x0CE6), 0, "Pad")
    )
    assert_false(is_device_supported(VendorId(0x1234), ProductId(1), 0, "Pad"))
    assert_true(
        game_controller_type("", VendorId(0x054C), ProductId(0x09CC))
        == GAMEPAD_TYPE_PS4
    )


def test_driver_with_device() raises:
    var source = ScriptedHid()
    # A known Xbox pad needs no question.
    assert_true(
        _driver_with_device(HidapiDevice(_xbox()), source) == HID_DRIVER_XBOXONE
    )
    # A third-party pad that answers neither PlayStation question.
    var hori = HidapiDevice(_info("p", 0x0F0D, 0x1234, "Pad", bus=HID_BUS_USB))
    assert_true(_driver_with_device(hori, source) == HID_DRIVER_NONE)
    # A DualSense needs no question either.
    var five = HidapiDevice(_info("p", 0x054C, 0x0CE6, "DualSense"))
    assert_true(_driver_with_device(five, source) == HID_DRIVER_PS5)


def test_standard_mappings() raises:
    assert_equal(_mapping(0x1234, 0x0001), STANDARD)
    assert_equal(_mapping(0x0000, 0x0000), STANDARD + "misc1:b11,")
    assert_equal(
        _mapping(0x054C, 0x09CC, type=GAMEPAD_TYPE_PS4),
        STANDARD + "touchpad:b11,",
    )
    assert_equal(
        _mapping(0x054C, 0x0CE6, type=GAMEPAD_TYPE_PS5),
        STANDARD + "touchpad:b11,misc1:b12,",
    )
    assert_equal(
        _mapping(0x054C, 0x0DF2, type=GAMEPAD_TYPE_PS5),
        STANDARD
        + "touchpad:b11,misc1:b12,paddle1:b16,paddle2:b15,paddle3:b14,"
        "paddle4:b13,",
    )
    assert_equal(
        _mapping(0x1234, 0x0DF2, type=GAMEPAD_TYPE_PS5),
        STANDARD + "touchpad:b11,misc1:b12,",
    )
    var elite = STANDARD + "paddle1:b11,paddle2:b13,paddle3:b12,paddle4:b14,"
    for product in [0x02E3, 0x0B00, 0x0B05, 0x0B22]:
        assert_equal(
            _mapping(0x045E, product, type=GAMEPAD_TYPE_XBOXONE), elite
        )
    var series = STANDARD + "misc1:b11,"
    for pair in [
        (0x045E, 0x0B12),
        (0x045E, 0x0B13),
        (0x0E6F, 0x02D6),
        (0x0E6F, 0x02D9),
        (0x0E6F, 0x02DA),
        (0x20D6, 0x2001),
        (0x20D6, 0x201A),
        (0x20D6, 0x4001),
        (0x20D6, 0x400B),
        (0x20D6, 0x4014),
        (0x20D6, 0x4016),
        (0x20D6, 0x890B),
        (0x20D6, 0x4002),
        (0x0F0D, 0x01F7),
        (0x0F0D, 0x01F6),
        (0x0F0D, 0x02D6),
        (0x0B05, 0x1A38),
        (0x2E24, 0x0652),
        (0x03F0, 0x08B6),
        (0x03F0, 0x07A0),
        (0x044F, 0xD012),
        (0x2DC8, 0x2002),
        (0x2DC8, 0x200F),
        (0x1532, 0x0A29),
        (0x1532, 0x0A2A),
        (0x1532, 0x0A2B),
    ]:
        assert_equal(
            _mapping(pair[0], pair[1], type=GAMEPAD_TYPE_XBOXONE), series
        )
    for pair in [
        (0x045E, 0x02EA),
        (0x0E6F, 0x0001),
        (0x20D6, 0x2000),
        (0x20D6, 0x201B),
        (0x0F0D, 0x0001),
        (0x0B05, 0x0001),
        (0x2E24, 0x0001),
        (0x03F0, 0x0001),
        (0x044F, 0x0001),
        (0x2DC8, 0x0001),
        (0x1532, 0x0001),
        (0x1111, 0x0001),
    ]:
        assert_equal(
            _mapping(pair[0], pair[1], type=GAMEPAD_TYPE_XBOXONE), STANDARD
        )


def test_other_mappings() raises:
    assert_equal(
        _mapping(0x057E, 0x0337),
        (
            "none,*,a:b0,b:b1,dpdown:b6,dpleft:b4,dpright:b5,dpup:b7,"
            "lefttrigger:a4,leftx:a0,lefty:a1~,rightshoulder:b9,"
            "righttrigger:a5,rightx:a2,righty:a3~,start:b8,x:b2,y:b3,"
        ),
    )
    assert_equal(_mapping(0x0079, 0x1843), _mapping(0x057E, 0x0337))
    assert_equal(_mapping(0x0079, 0x1846), _mapping(0x057E, 0x0337))
    assert_equal(_mapping(0x0079, 0x1847), STANDARD)
    assert_equal(
        _mapping(0x28DE, 0x1102), STANDARD + "paddle1:b12,paddle2:b11,"
    )
    assert_equal(
        _mapping(0x28DE, 0x1201), STANDARD + "paddle1:b12,paddle2:b11,"
    )
    assert_equal(_mapping(0x0F0D, 0x00C1), STANDARD + "misc1:b11,")
    # A GUID with a product but no vendor.
    var odd = JoystickGuid()
    odd.set_word(0, 3)
    odd.set_word(4, 5)
    assert_equal(
        create_mapping_for_hidapi_gamepad(odd, GAMEPAD_TYPE_STANDARD), STANDARD
    )
    assert_equal(_mapping(0x057E, 0x2009), STANDARD + "misc1:b11,")
    assert_equal(
        _mapping(0x057E, 0x2008),
        STANDARD + "misc1:b11,paddle1:b12,paddle2:b13,paddle3:b14,paddle4:b15,",
    )
    assert_equal(_mapping(0x057E, 0x2017), STANDARD)
    assert_equal(_mapping(0x1949, 0x0419), STANDARD + "misc1:b11,")
    assert_equal(_mapping(0x0171, 0x0419), STANDARD + "misc1:b11,")
    assert_equal(_mapping(0x1949, 0x0001), STANDARD)
    assert_equal(_mapping(0x0171, 0x0001), STANDARD)
    assert_equal(_mapping(0x18D1, 0x9400), STANDARD + "misc1:b11,misc2:b12")
    assert_equal(_mapping(0x18D1, 0x0001), STANDARD)
    assert_equal(
        _mapping(0x0955, 0x7210),
        STANDARD + "misc1:b11,touchpad:b12,misc2:b13,misc3:b14",
    )
    assert_equal(_mapping(0x0955, 0x7214), STANDARD + "misc1:b11,")
    assert_equal(_mapping(0x0955, 0x0001), STANDARD)
    var hori = (
        STANDARD
        + "paddle1:b13,paddle2:b12,paddle3:b15,paddle4:b14,misc2:b11,"
        "misc3:b16,misc4:b17"
    )
    assert_equal(_mapping(0x0F0D, 0x01AB), hori)
    assert_equal(_mapping(0x0F0D, 0x0196), hori)
    assert_equal(_mapping(0x0F0D, 0x0001), STANDARD)


def test_nintendo_mappings() raises:
    var hat = "dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,"
    var nes = (
        "none,*,a:b0,b:b1,back:b4,"
        + hat
        + "leftshoulder:b9,rightshoulder:b10,start:b6,"
    )
    for kind in [7, 9, 10]:
        assert_equal(_mapping(0x057E, 0x2017, kind), nes)
    assert_equal(
        _mapping(0x057E, 0x2017, 8),
        "none,*,a:b0,b:b1," + hat + "leftshoulder:b9,rightshoulder:b10,",
    )
    assert_true(
        _mapping(0x057E, 0x2017, 11).endswith(
            "hint:!SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,"
        )
    )
    assert_true(_mapping(0x057E, 0x2017, 12).endswith("x:b2,y:b3,misc1:b11,"))
    assert_true(_mapping(0x057E, 0x2017, 13).find("righttrigger:a5") > 0)
    assert_equal(
        _mapping(0x057E, 0x0330, 128),
        "none,*,a:b0,b:b1,back:b4," + hat + "guide:b5,start:b6,x:b2,y:b3,",
    )
    assert_true(_mapping(0x057E, 0x0330, 129).find("dpup:b11") > 0)
    var joycon = (
        "none,*,a:b0,b:b1,guide:b5,leftshoulder:b9,leftstick:b7,leftx:a0,"
        "lefty:a1,rightshoulder:b10,start:b6,x:b2,y:b3,"
    )
    assert_equal(
        _mapping(0x057E, 0x2006, 1), joycon + "paddle2:b13,paddle4:b15,"
    )
    assert_equal(
        _mapping(0x057E, 0x2007, 2), joycon + "paddle1:b12,paddle3:b14,"
    )
    # Another kind is a standard pad.
    assert_equal(_mapping(0x057E, 0x2009, 3), STANDARD + "misc1:b11,")


def test_gamepad() raises:
    var database = default_mapping_database()
    with assert_raises():
        _ = HidGamepad[ScriptedHid](
            _info("p", 0x1234, 0x5678, "Pad"), ScriptedHid(), _seconds(0)
        )
    # A Switch pad that says it is a Joy-Con: the driver does not start.
    var joycon = ScriptedHid()
    joycon.queue.append(hex_bytes("81010001665544332211"))
    with assert_raises():
        _ = HidGamepad[ScriptedHid](
            _info("p", 0x0E6F, 0x0186, "Pad", bus=HID_BUS_USB),
            joycon^,
            _seconds(0),
        )
    var pad = HidGamepad[ScriptedHid](_xbox(), ScriptedHid(), _seconds(0))
    assert_true(pad.driver == HID_DRIVER_XBOXONE)
    assert_true(pad.connected())
    assert_true(pad.gamepad_type() == GAMEPAD_TYPE_XBOXONE)
    # Not open yet: no events, and no sensors to switch.
    assert_equal(len(pad.update_at(_seconds(0))), 0)
    with assert_raises():
        _ = pad.set_sensor_enabled(SENSOR_GYRO, True)
    pad.open(database)
    assert_true(pad.pad)
    assert_true(pad.now() >= _seconds(0))
    _ = pad.update()
    with assert_raises():
        _ = pad.rumble_triggers_at(70000, 0, _seconds(1), _seconds(1))
    with assert_raises():
        _ = pad.set_sensor_enabled(SENSOR_GYRO, True)
    # Trigger rumble runs out, and is sent again while it lasts.
    assert_true(pad.rumble_triggers_at(100, 200, _seconds(5), _seconds(1)))
    _ = pad.update_at(_seconds(3.5))
    _ = pad.update_at(_seconds(7))
    assert_equal(pad.trigger_rumble_state.first, 0)
    assert_true(pad.rumble(0, 0, Duration64(0)))
    # The Xbox driver has no sensors, so turning one on fails.
    pad.pad.value().joystick.add_sensor(SENSOR_GYRO, Frequency(0))
    assert_false(pad.set_sensor_enabled(SENSOR_GYRO, True))
    pad.close()
    assert_false(pad.pad)
    pad.close()
    # A pad whose device fails while opening.
    var broken = HidGamepad[ScriptedHid](_xbox(), ScriptedHid(), _seconds(0))
    broken.source.failing = True
    with assert_raises():
        broken.open_at(database, _seconds(0))
    # A DualSense: its light, sent once in five seconds for one color, and
    # its rumble, which ends and is sent again while it lasts.
    var five = HidGamepad[ScriptedHid](_dualsense(), ScriptedHid(), _seconds(0))
    five.open_at(database, _seconds(0))
    assert_true(five.set_led_at(1, 2, 3, _seconds(0)))
    var writes = len(five.source.log)
    assert_true(five.set_led_at(1, 2, 3, _seconds(1)))
    assert_equal(len(five.source.log), writes)
    assert_true(five.rumble_at(100, 200, _seconds(5), _seconds(1)))
    assert_true(five.set_sensor_enabled(SENSOR_GYRO, True))
    _ = five.update_at(_seconds(3.5))
    _ = five.update_at(_seconds(7))
    assert_equal(five.rumble_state.first, 0)


def test_hub() raises:
    var database = default_mapping_database()
    var hub = HidHub[ScriptedHid]()
    assert_equal(len(hub.claimed()), 0)
    var found: List[HidDeviceInfo] = [
        _xbox("/dev/hidraw0"),
        _info("/dev/hidraw1", 0x1234, 0x5678, "Pad"),
        _info("/dev/missing", 0x045E, 0x0B13, "Xbox Wireless Controller"),
        _info("/dev/hidraw2", 0x0F0D, 0x1234, "Pad", bus=HID_BUS_USB),
    ]
    var changes = hub.detect_with(database, found, _seconds(0))
    assert_equal(len(changes), 1)
    assert_true(changes[0].kind == GAMEPAD_ADDED)
    assert_equal(changes[0].path, "/dev/hidraw0")
    assert_equal(len(hub.pads), 1)
    assert_equal(hub.pads[0].player_index, 0)
    assert_equal(hub.claimed()[0], (0x045E << 16) | 0x0B13)
    # A second pad takes the next player number.
    found.append(_xbox("/dev/hidraw3"))
    changes = hub.detect_with(database, found, _seconds(0))
    assert_equal(len(changes), 1)
    assert_equal(hub.pads[1].player_index, 1)
    # The first pad's device goes away: it is removed.
    _ = found.pop(0)
    changes = hub.detect_with(database, found, _seconds(1))
    assert_equal(len(changes), 1)
    assert_true(changes[0].kind == GAMEPAD_REMOVED)
    assert_equal(len(hub.pads), 1)
    # Its player number is free again.
    found.append(_xbox("/dev/hidraw4"))
    _ = hub.detect_with(database, found, _seconds(1))
    assert_equal(hub.pads[1].player_index, 0)
    # A USB pad drops the Bluetooth link with its serial number.
    hub.pads[0].device.serial = "s1"
    hub.pads[1].device.disconnect_bluetooth = "s1"
    var settled = List[HidDeviceInfo]()
    for index in range(len(hub.pads)):
        settled.append(_xbox(hub.pads[index].device.path))
    changes = hub.detect_with(database, settled, _seconds(2))
    assert_equal(len(changes), 1)
    assert_true(changes[0].kind == GAMEPAD_REMOVED)
    assert_equal(len(hub.pads), 1)
    # A serial that no Bluetooth pad has changes nothing.
    hub.pads[0].device.disconnect_bluetooth = "s9"
    var left: List[HidDeviceInfo] = [_xbox(hub.pads[0].device.path)]
    assert_equal(len(hub.detect_with(database, left, _seconds(2))), 0)
    assert_true(hub.now() >= _seconds(0))


def test_hub_links() raises:
    # A pad on USB disconnects only the connected Bluetooth pads with its
    # serial number. A pad that never opened goes without an event.
    var database = default_mapping_database()
    var hub = HidHub[ScriptedHid]()
    var found: List[HidDeviceInfo] = [
        _dualsense("/dev/hidraw0"),
        _xbox("/dev/hidraw1"),
        _xbox("/dev/hidraw2"),
        _xbox("/dev/hidraw3"),
    ]
    assert_equal(len(hub.detect_with(database, found, _seconds(0))), 4)
    hub.pads[1].device.serial = "s1"
    hub.pads[2].device.serial = "s1"
    hub.pads[2].device.joysticks = 0
    hub.pads[3].device.serial = "s2"
    hub.pads[0].device.serial = "s1"
    hub.pads[0].device.disconnect_bluetooth = "s1"
    # Another pad's link to itself is not a Bluetooth pad: the USB pad stays.
    hub.pads[3].device.disconnect_bluetooth = "s1"
    hub.pads[3].pad = None
    var changes = hub.detect_with(database, found, _seconds(1))
    assert_equal(len(changes), 2)
    assert_true(changes[0].kind == GAMEPAD_REMOVED)
    assert_equal(changes[0].path, "/dev/hidraw1")
    assert_true(changes[1].kind == GAMEPAD_ADDED)
    assert_equal(changes[1].path, "/dev/hidraw3")
    # The pad that was closed reopens.
    assert_true(hub.pads[2].pad)
    # A pad that fails as it opens stays closed.
    hub.pads[1].device.joysticks = 1
    hub.pads[1].pad = None
    hub.pads[1].source.failing = True
    var current: List[HidDeviceInfo] = [
        found[0].copy(),
        found[2].copy(),
        found[3].copy(),
    ]
    assert_equal(len(hub.detect_with(database, current, _seconds(1.5))), 0)
    assert_false(hub.pads[1].pad)
    hub.pads[2].gone = True
    hub.pads[2].pad = None
    var left: List[HidDeviceInfo] = [found[0].copy(), found[2].copy()]
    assert_equal(len(hub.detect_with(database, left, _seconds(2))), 0)
    assert_equal(len(hub.pads), 2)


def test_hub_scans() raises:
    with TestScratch():
        var root = temporary_path("class")
        makedirs(root)
        var database = default_mapping_database()
        var hub = HidHub[ScriptedHid](root, root)
        # The first call scans, the next waits 3 seconds.
        assert_equal(len(hub.detect_at(database, _seconds(0))), 0)
        assert_equal(len(hub.detect_at(database, _seconds(1))), 0)
        _ = hub.detect_with(database, [_xbox()], _seconds(1))
        assert_equal(len(hub.pads), 1)
        # A pad that disconnects asks for a scan at once; the scan finds
        # no hidraw node, so the pad goes.
        hub.pads[0].device.rescan = True
        var changes = hub.detect_at(database, _seconds(1.5))
        assert_equal(len(changes), 1)
        assert_equal(len(hub.pads), 0)
        # The folder has not changed: no scan after 3 seconds.
        _ = hub.detect_with(database, [_xbox()], _seconds(2))
        assert_equal(len(hub.detect_at(database, _seconds(10))), 0)
        assert_equal(len(hub.pads), 1)
        # A changed folder is scanned: the pad has no node there.
        with open(root + "/new", "w") as file:
            file.write("")
        assert_equal(len(hub.detect_at(database, _seconds(14))), 1)
        # A folder that cannot be read always scans.
        var lost = HidHub[ScriptedHid](root + "/none", root + "/none")
        assert_equal(len(lost.detect(database)), 0)
        assert_equal(len(lost.detect_at(database, _seconds(5))), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
