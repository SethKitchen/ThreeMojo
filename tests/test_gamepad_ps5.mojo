# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.gamepad.hid_ps5`, the DualSense driver.

Each scripted test runs the driver on a scripted HID device and compares
the whole transcript with the one SDL 3.2.24's own driver prints for the
same script. The SDL oracle is `hid.c`, linked with wrappers for the
`SDL_hid_*` calls, the clock and the rumble thread. Two changes to the
oracle make it print what this framework can print:

- SDL's PS3 drivers are turned off, with `SDL_HINT_JOYSTICK_HIDAPI_PS3`
  set to 0. The framework has no PS3 drivers, and the PS3 third-party
  driver asks a pad for the capability report before the DualShock 4
  and DualSense drivers do.
- The oracle prints one `removed` line for a gamepad and its joystick,
  as `run_script` does.

The DualShock 4 driver asks a third-party pad for the capability report
before this driver does. `_ps4_probe` puts that line in the expected
transcript only when the DualShock 4 driver can take part, so the tests
hold before and after that driver is ported.

SDL reads a Bluetooth report's CRC from the last 4 bytes with no check of
the length. A report shorter than 4 bytes makes SDL read before its
buffer, so no SDL transcript exists for it. The port drops such a report;
`test_short_bluetooth_report` checks that.
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true
from extensions.gamepad.gamepad import Gamepad
from extensions.gamepad.guid import ProductId, VendorId
from extensions.gamepad.hid import HID_BUS_BLUETOOTH, HID_BUS_USB, HidDeviceInfo
from extensions.gamepad.hid_device import HidapiDevice
from extensions.gamepad.hid_ps4 import Ps4Driver
from extensions.gamepad.hid_ps5 import Ps5Driver, crc32
from extensions.gamepad.ids import GAMEPAD_TYPE_STANDARD
from extensions.gamepad.joystick import Joystick
from tests._gamepad_hid_script import ScriptedHid, bytes_hex, run_script
from units.si import Duration64, SECOND

comptime SONY = (
    "strings Sony Interactive Entertainment|DualSense Wireless Controller|"
)


struct Transcript(Movable):
    """A script, and the transcript SDL prints for it."""

    var script: String
    var expected: String

    def __init__(out self):
        """Create an empty script."""
        self.script = String()
        self.expected = String()

    def step(mut self, line: String, output: String = ""):
        """Add a script line and what SDL prints for it.

        Args:
            line: The script line.
            output: The lines SDL prints after it echoes the line.
        """
        self.script += line + "\n"
        self.expected += "> " + line + "\n" + output

    def close(mut self):
        """Add the line SDL prints when it closes the device."""
        self.expected += "hid close\n"


def _ps4_probe(vendor: Int, product: Int) -> String:
    """Return the DualShock 4 driver's capability request, if it can make
    one.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        The transcript line, or nothing while that driver takes no
        third-party pads.
    """
    if Ps4Driver.is_supported(
        "",
        GAMEPAD_TYPE_STANDARD,
        VendorId(vendor),
        ProductId(product),
        0x100,
        0,
    ):
        return "feature-get 03 64\n"
    return ""


def touch(down: Bool, x: Int, y: Int, counter: Int = 0) -> List[UInt8]:
    """Return a touchpad finger's 4 bytes.

    Args:
        down: Whether the finger touches.
        x: Its position across, 0 to 1919.
        y: Its position down, 0 to 1069.
        counter: The touch counter.

    Returns:
        The counter byte, then 12 bits of X and 12 bits of Y.
    """
    return [
        UInt8((counter & 0x7F) | (0 if down else 0x80)),
        UInt8(x & 0xFF),
        UInt8(((x >> 8) & 0x0F) | ((y & 0x0F) << 4)),
        UInt8((y >> 4) & 0xFF),
    ]


def _put(mut bytes: List[UInt8], at: Int, value: Int, count: Int):
    """Write a little-endian number.

    Args:
        bytes: The buffer.
        at: Where the number starts.
        value: The number. A negative one is written in two's complement.
        count: How many bytes it takes.
    """
    for index in range(count):
        bytes[at + index] = UInt8((value >> (8 * index)) & 0xFF)


def _packet(
    lx: Int,
    ly: Int,
    rx: Int,
    ry: Int,
    lt: Int,
    rt: Int,
    b0: Int,
    b1: Int,
    b2: Int,
    seq: Int,
    gx: Int,
    gy: Int,
    gz: Int,
    ax: Int,
    ay: Int,
    az: Int,
    ts: Int,
    tp1: Optional[List[UInt8]],
    tp2: Optional[List[UInt8]],
    alt: Bool,
    size: Int,
) -> List[UInt8]:
    """Return a full state packet, after the report id.

    Args:
        lx: The left stick across.
        ly: The left stick down.
        rx: The right stick across.
        ry: The right stick down.
        lt: The left trigger.
        rt: The right trigger.
        b0: The face buttons and the d-pad.
        b1: The shoulder, menu and stick buttons.
        b2: The guide, touchpad, microphone, function and paddle buttons.
        seq: The packet sequence.
        gx: The gyroscope's pitch.
        gy: The gyroscope's yaw.
        gz: The gyroscope's roll.
        ax: The accelerometer's X.
        ay: The accelerometer's Y.
        az: The accelerometer's Z.
        ts: The sensor clock.
        tp1: The first finger, or None for none.
        tp2: The second finger, or None for none.
        alt: Whether it is the third-party layout, with a 16-bit clock.
        size: The packet's length.

    Returns:
        The packet.
    """
    var p = List[UInt8](length=size, fill=0)
    p[0] = UInt8(lx)
    p[1] = UInt8(ly)
    p[2] = UInt8(rx)
    p[3] = UInt8(ry)
    p[4] = UInt8(lt)
    p[5] = UInt8(rt)
    p[7] = UInt8(b0)
    p[8] = UInt8(b1)
    p[9] = UInt8(b2)
    _put(p, 11, seq, 4)
    var sensors = [gx, gy, gz, ax, ay, az]
    for index in range(6):
        _put(p, 15 + 2 * index, sensors[index], 2)
    var first = tp1.value().copy() if tp1 else touch(False, 0, 0)
    var second = tp2.value().copy() if tp2 else touch(False, 0, 0)
    var fingers = 31 if alt else 32
    _put(p, 27, ts, 2 if alt else 4)
    for index in range(4):
        p[fingers + index] = first[index]
        p[fingers + 4 + index] = second[index]
    return p^


def usb(
    lx: Int = 0x80,
    ly: Int = 0x80,
    rx: Int = 0x80,
    ry: Int = 0x80,
    lt: Int = 0,
    rt: Int = 0,
    b0: Int = 0x08,
    b1: Int = 0,
    b2: Int = 0,
    seq: Int = 0,
    gx: Int = 0,
    gy: Int = 0,
    gz: Int = 0,
    ax: Int = 0,
    ay: Int = 0,
    az: Int = 0,
    ts: Int = 0,
    tp1: Optional[List[UInt8]] = None,
    tp2: Optional[List[UInt8]] = None,
    alt: Bool = False,
) -> String:
    """Return a script line for a 64-byte USB state report.

    Args:
        lx: The left stick across.
        ly: The left stick down.
        rx: The right stick across.
        ry: The right stick down.
        lt: The left trigger.
        rt: The right trigger.
        b0: The face buttons and the d-pad. 8 is centered.
        b1: The shoulder, menu and stick buttons.
        b2: The guide, touchpad, microphone, function and paddle buttons.
        seq: The packet sequence.
        gx: The gyroscope's pitch.
        gy: The gyroscope's yaw.
        gz: The gyroscope's roll.
        ax: The accelerometer's X.
        ay: The accelerometer's Y.
        az: The accelerometer's Z.
        ts: The sensor clock.
        tp1: The first finger, or None for none.
        tp2: The second finger, or None for none.
        alt: Whether it is the third-party layout.

    Returns:
        The `input` line.
    """
    var report: List[UInt8] = [0x01]
    report += _packet(
        lx, ly, rx, ry, lt, rt, b0, b1, b2, seq, gx, gy, gz, ax, ay, az, ts,
        tp1, tp2, alt, 63,
    )  # fmt: skip
    return "input " + bytes_hex(report)


def bt(
    lx: Int = 0x80,
    ly: Int = 0x80,
    rx: Int = 0x80,
    ry: Int = 0x80,
    lt: Int = 0,
    rt: Int = 0,
    b0: Int = 0x08,
    b1: Int = 0,
    b2: Int = 0,
    seq: Int = 0,
    gx: Int = 0,
    gy: Int = 0,
    gz: Int = 0,
    ax: Int = 0,
    ay: Int = 0,
    az: Int = 0,
    ts: Int = 0,
    tp1: Optional[List[UInt8]] = None,
    tp2: Optional[List[UInt8]] = None,
    alt: Bool = False,
    crc: Bool = True,
) -> String:
    """Return a script line for a 78-byte Bluetooth state report.

    Args:
        lx: The left stick across.
        ly: The left stick down.
        rx: The right stick across.
        ry: The right stick down.
        lt: The left trigger.
        rt: The right trigger.
        b0: The face buttons and the d-pad. 8 is centered.
        b1: The shoulder, menu and stick buttons.
        b2: The guide, touchpad, microphone, function and paddle buttons.
        seq: The packet sequence.
        gx: The gyroscope's pitch.
        gy: The gyroscope's yaw.
        gz: The gyroscope's roll.
        ax: The accelerometer's X.
        ay: The accelerometer's Y.
        az: The accelerometer's Z.
        ts: The sensor clock.
        tp1: The first finger, or None for none.
        tp2: The second finger, or None for none.
        alt: Whether it is the third-party layout.
        crc: Whether the CRC is good. A bad one is 0.

    Returns:
        The `input` line.
    """
    var report: List[UInt8] = [0x31, 0x00]
    report += _packet(
        lx, ly, rx, ry, lt, rt, b0, b1, b2, seq, gx, gy, gz, ax, ay, az, ts,
        tp1, tp2, alt, 72,
    )  # fmt: skip
    var value = 0
    if crc:
        value = Int(crc32(crc32(0, [UInt8(0xA1)], 1), report, len(report)))
    report += [UInt8(0), UInt8(0), UInt8(0), UInt8(0)]
    _put(report, 74, value, 4)
    return "input " + bytes_hex(report)


def simple(
    lx: Int = 0x80,
    ly: Int = 0x80,
    rx: Int = 0x80,
    ry: Int = 0x80,
    b0: Int = 0x08,
    b1: Int = 0,
    b2: Int = 0,
    lt: Int = 0,
    rt: Int = 0,
    size: Int = 10,
) -> String:
    """Return a script line for a simple state report.

    Args:
        lx: The left stick across.
        ly: The left stick down.
        rx: The right stick across.
        ry: The right stick down.
        b0: The face buttons and the d-pad. 8 is centered.
        b1: The shoulder, menu and stick buttons.
        b2: The guide and touchpad buttons.
        lt: The left trigger.
        rt: The right trigger.
        size: The report's length: 10, or 78 with zeros.

    Returns:
        The `input` line.
    """
    var report = List[UInt8](length=size, fill=0)
    var values = [0x01, lx, ly, rx, ry, b0, b1, b2, lt, rt]
    for index in range(len(values)):
        report[index] = UInt8(values[index])
    return "input " + bytes_hex(report)


def serial_feature() -> String:
    """Return the serial number report for the address 11:22:33:44:55:66.

    Returns:
        The `feature` line, with the address last byte first.
    """
    var report = List[UInt8](length=20, fill=0)
    var values = [0x09, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11]
    for index in range(len(values)):
        report[index] = UInt8(values[index])
    return "feature " + bytes_hex(report)


def firmware_feature(version: Int) -> String:
    """Return the firmware report.

    Args:
        version: The firmware version, such as 0x0224 for 2.24.

    Returns:
        The `feature` line.
    """
    var report = List[UInt8](length=64, fill=0)
    report[0] = 0x20
    _put(report, 44, version, 2)
    return "feature " + bytes_hex(report)


def calibration_feature(
    bias0: Int = 1,
    gyro_plus0: Int = 8000,
    gyro_minus0: Int = -8000,
    acc_plus0: Int = 8200,
    acc_minus0: Int = -8180,
    length: Int = 41,
) -> String:
    """Return the calibration report.

    Args:
        bias0: The gyroscope's pitch bias.
        gyro_plus0: The pitch at the plus reference speed.
        gyro_minus0: The pitch at the minus reference speed.
        acc_plus0: The accelerometer's X at plus 1 g.
        acc_minus0: The accelerometer's X at minus 1 g.
        length: The report's length. Under 35 is too short.

    Returns:
        The `feature` line.
    """
    var values = [
        bias0, -2, 3,
        gyro_plus0, gyro_minus0, 8100, -8100, 8200, -8200,
        540, 540,
        acc_plus0, acc_minus0, 8250, -8150, 8300, -8100,
    ]  # fmt: skip
    var report = List[UInt8](length=41, fill=0)
    report[0] = 0x05
    for index in range(len(values)):
        _put(report, 1 + 2 * index, values[index], 2)
    report.resize(length, 0)
    return "feature " + bytes_hex(report)


def caps_feature(
    caps: Int = 0x4E, caps2: Int = 0x80, kind: Int = 0, marker: Int = 0x28
) -> String:
    """Return a third-party pad's capability report.

    Args:
        caps: Sensors 0x02, light bar 0x04, rumble 0x08, touchpad 0x40.
        caps2: Player lights 0x80.
        kind: The device type, such as 6 for a wheel.
        marker: 0x28 for a DualSense, 0x27 for a DualShock 4.

    Returns:
        The `feature` line.
    """
    var report = List[UInt8](length=48, fill=0)
    report[0] = 0x03
    report[2] = UInt8(marker)
    report[4] = UInt8(caps)
    report[5] = UInt8(kind)
    report[20] = UInt8(caps2)
    return "feature " + bytes_hex(report)


def test_usb() raises:
    """A DualSense on USB: the buttons, the d-pad, the sticks, the
    triggers, the lights, rumble with old firmware, calibrated sensors,
    the touchpad, and the unplug."""
    var run = Transcript()
    run.step("device 54c ce6 100 usb 3 1 5")
    run.step(SONY + "0123456789ab")
    run.step(usb())
    run.step(serial_feature())
    run.step(firmware_feature(0x0210))
    run.step(calibration_feature())
    run.step(
        "open",
        (
            "hid open\nfeature-get 09 128\nfeature-get 20 64\nwrite"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
            " 020014000000000000000000000000000000000000000000000000000000000000000000000000000000000024000040\nname"
            " DualSense Wireless Controller\nguid"
            " 030057564c050000e60c000000016800\ntype 6\nmapping"
            " 030057564c050000e60c000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:5657,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step(
        usb(
            lx=0x00,
            ly=0xFF,
            rx=0x40,
            ry=0xC0,
            lt=0x80,
            b0=0x1F,
            b1=0xFB,
            b2=0x07,
            seq=1,
        )
    )
    run.step(
        "update",
        (
            "axes -32768 32767 -16320 16576 128 32767\n"
            "buttons 0010111111111\n"
            "hats 0\n"
        ),
    )
    run.step(usb(b0=0x22, b1=0x08, seq=2))
    run.step(usb(b0=0x83, seq=3))
    run.step(
        "update",
        "axes 128 128 128 128 -32768 -32768\nbuttons 0001000000000\nhats 6\n",
    )
    run.step(usb(b0=0x45, seq=4))
    run.step(
        "update",
        "axes 128 128 128 128 -32768 -32768\nbuttons 0100000000000\nhats 12\n",
    )
    run.step(usb(b0=0x06, seq=5))
    run.step(
        "update",
        "axes 128 128 128 128 -32768 -32768\nbuttons 0000000000000\nhats 8\n",
    )
    run.step(usb(b0=0x07, seq=6))
    run.step(
        "update",
        "axes 128 128 128 128 -32768 -32768\nbuttons 0000000000000\nhats 9\n",
    )
    run.step(usb(b0=0x0F, seq=7))
    run.step(
        "update",
        "axes 128 128 128 128 -32768 -32768\nbuttons 0000000000000\nhats 0\n",
    )
    run.step(usb(b0=0x00, seq=8))
    run.step(
        "update",
        "axes 128 128 128 128 -32768 -32768\nbuttons 0000000000000\nhats 1\n",
    )
    run.step(usb(b0=0x01, seq=9))
    run.step(
        "update",
        "axes 128 128 128 128 -32768 -32768\nbuttons 0000000000000\nhats 3\n",
    )
    run.step(usb(b0=0x04, b1=0x04, seq=10))
    run.step(
        "update",
        "axes 128 128 128 128 32767 -32768\nbuttons 0000000000000\nhats 4\n",
    )
    run.step(
        "player 2",
        (
            "write"
            " 020014000000000000000000000000000000000000000000000000000000000000000000000000000000000035004000\n"
            "result 1\n"
        ),
    )
    run.step(
        "player 6",
        (
            "write"
            " 02001400000000000000000000000000000000000000000000000000000000000000000000000000000000002a101010\n"
            "result 1\n"
        ),
    )
    run.step(
        "player -1",
        (
            "write"
            " 020014000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040\n"
            "result 1\n"
        ),
    )
    run.step(
        "led 10 20 30",
        (
            "write"
            " 0200040000000000000000000000000000000000000000000000000000000000000000000000000000000000000a141e\n"
            "result 1\n"
        ),
    )
    run.step(
        "rumble 1000 60000 0",
        (
            "write"
            " 020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "write"
            " 020300750100000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "result 1\n"
        ),
    )
    run.step(
        "rumble 0 0 0",
        (
            "write"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "result 1\n"
        ),
    )
    run.step("triggers 100 100 0", "result 0\n")
    run.step("time 100")
    run.step("sensors 1", "feature-get 05 64\nresult 1\nresult 1\n")
    run.step(
        usb(gx=100, gy=-200, gz=300, ax=500, ay=-8192, az=1000, ts=3000, seq=11)
    )
    run.step(usb(gx=-100, gz=64, ay=8192, az=-1, ts=6000, seq=12))
    run.step(
        "update",
        (
            "sensor 2 0.1166 -0.2304 0.3414 1000000\n"
            "sensor 1 0.5867 -9.8569 1.0763 1000000\n"
            "sensor 2 -0.1190 0.0023 0.0701 2000000\n"
            "sensor 1 -0.0120 9.7373 -0.1208 2000000\n"
            "axes 128 128 128 128 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.step(usb(gx=1, gy=1, gz=1, ax=1, ay=1, az=1, ts=5, seq=13))
    run.step(
        "update",
        (
            "sensor 2 0.0000 0.0035 -0.0023 1431655767000\n"
            "sensor 1 -0.0108 -0.0586 -0.1184 1431655767000\n"
            "axes 128 128 128 128 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.step("sensors 0", "result 1\nresult 1\n")
    run.step(usb(gx=1, gy=1, gz=1, ax=1, ay=1, az=1, ts=50, seq=14))
    run.step(
        "update",
        "axes 128 128 128 128 -32768 -32768\nbuttons 0000000000000\nhats 0\n",
    )
    run.step(usb(tp1=touch(True, 960, 535, 1), seq=15))
    run.step(
        "update",
        (
            "touch down 0 0 0.5000 0.5000 1.0000\n"
            "axes 128 128 128 128 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.step(
        usb(
            tp1=touch(True, 1000, 600, 1), tp2=touch(True, 100, 1000, 2), seq=16
        )
    )
    run.step(
        "update",
        (
            "touch motion 0 0 0.5208 0.5607 1.0000\n"
            "touch down 0 1 0.0521 0.9346 1.0000\n"
            "axes 128 128 128 128 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.step(
        usb(
            tp1=touch(False, 1000, 600, 1),
            tp2=touch(True, 100, 1000, 2),
            seq=17,
        )
    )
    run.step(
        "update",
        (
            "touch up 0 0 0.5208 0.5607 0.0000\n"
            "axes 128 128 128 128 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.step(
        usb(
            tp1=touch(False, 1000, 600, 1),
            tp2=touch(False, 100, 1000, 2),
            seq=18,
        )
    )
    run.step(
        "update",
        (
            "touch up 0 1 0.0521 0.9346 0.0000\n"
            "axes 128 128 128 128 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.step("input 0201")
    run.step(
        "update",
        "axes 128 128 128 128 -32768 -32768\nbuttons 0000000000000\nhats 0\n",
    )
    run.step("fail")
    run.step(
        "rumble 100 100 0",
        (
            "write"
            " 020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "write"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "result 0\n"
        ),
    )
    run.step("update", "removed\ndisconnected\n")
    run.step("update", "disconnected\n")
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_usb_old_firmware() raises:
    """Firmware before 2.24 halves the rumble strengths and turns on the
    rumble emulation."""
    var run = Transcript()
    run.step("device 54c ce6 100 usb 3 1 5")
    run.step(SONY)
    run.step(usb())
    run.step(serial_feature())
    run.step(firmware_feature(0x0100))
    run.step(
        "open",
        (
            "hid open\nfeature-get 09 128\nfeature-get 20 64\nwrite"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
            " 020014000000000000000000000000000000000000000000000000000000000000000000000000000000000024000040\nname"
            " DualSense Wireless Controller\nguid"
            " 030057564c050000e60c000000016800\ntype 6\nmapping"
            " 030057564c050000e60c000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:5657,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step(
        "rumble 1000 60000 0",
        (
            "write"
            " 020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "write"
            " 020300750100000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "result 1\n"
        ),
    )
    run.step(
        "rumble 2000 0 0",
        (
            "write"
            " 020300000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "result 1\n"
        ),
    )
    run.step(
        "rumble 0 4000 0",
        (
            "write"
            " 020300070000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "result 1\n"
        ),
    )
    run.step(
        "rumble 0 0 0",
        (
            "write"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "result 1\n"
        ),
    )
    run.step(
        "led 1 2 3",
        (
            "write"
            " 020004000000000000000000000000000000000000000000000000000000000000000000000000000000000000010203\n"
            "result 1\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_usb_no_features() raises:
    """A pad that answers no feature report: the enhanced rumble, and the
    sensors without calibration."""
    var run = Transcript()
    run.step("device 54c ce6 100 usb 3 1 5")
    run.step(SONY)
    run.step(usb())
    run.step(firmware_feature(0x0224))
    run.step(
        "open",
        (
            "hid open\nfeature-get 09 128\nfeature-get 20 64\nwrite"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
            " 020014000000000000000000000000000000000000000000000000000000000000000000000000000000000024000040\nname"
            " DualSense Wireless Controller\nguid"
            " 030057564c050000e60c000000016800\ntype 6\nmapping"
            " 030057564c050000e60c000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:5657,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step(
        "rumble 1000 60000 0",
        (
            "write"
            " 020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "write"
            " 020200ea0300000000000000000000000000000000000000000000000000000000000000000000040000000000000000\n"
            "result 1\n"
        ),
    )
    run.step("sensors 1", "feature-get 05 64\nresult 1\nresult 1\n")
    run.step(
        usb(gx=100, gy=-200, gz=300, ax=500, ay=-8192, az=1000, ts=3000, seq=1)
    )
    run.step(
        "update",
        (
            "sensor 2 0.1091 -0.2182 0.3272 1000000\n"
            "sensor 1 0.5986 -9.8067 1.1971 1000000\n"
            "axes 0 0 0 0 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_edge() raises:
    """A DualSense Edge on USB: 17 buttons, with the function buttons and
    the paddles, sensors at 1000 Hz, and the enhanced rumble on old
    firmware."""
    var run = Transcript()
    run.step("device 54c df2 100 usb 3 1 5")
    run.step(
        "strings Sony Interactive Entertainment|DualSense Edge Wireless"
        " Controller|"
    )
    run.step(usb())
    run.step(firmware_feature(0x0100))
    run.step(
        "open",
        (
            "hid open\nfeature-get 09 128\nfeature-get 20 64\nwrite"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
            " 020014000000000000000000000000000000000000000000000000000000000000000000000000000000000024000040\nname"
            " DualSense Edge Wireless Controller\nguid"
            " 0300e0274c050000f20d000000016800\ntype 6\nmapping"
            " 0300e0274c050000f20d000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,paddle1:b16,paddle2:b15,paddle3:b14,paddle4:b13,crc:27e0,platform:Linux,\ncounts"
            " 6 17 1\ntouchpads 1 2\nsensors 1:1000.0 2:1000.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons"
            " 00000000000000000\nhats 0\n"
        ),
    )
    run.step(usb(b2=0xF7, seq=1))
    run.step(
        "update",
        "axes 0 0 0 0 -32768 -32768\nbuttons 00000100000111111\nhats 0\n",
    )
    run.step(usb(seq=2))
    run.step(
        "update",
        "axes 0 0 0 0 -32768 -32768\nbuttons 00000000000000000\nhats 0\n",
    )
    run.step(
        "rumble 300 300 0",
        (
            "write"
            " 020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "write"
            " 020200010100000000000000000000000000000000000000000000000000000000000000000000040000000000000000\n"
            "result 1\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_bluetooth_simple() raises:
    """A DualSense on Bluetooth that sends simple reports: no feature
    reports, effects with a CRC, the 78-byte simple report, an unknown
    report, and the disconnect after 500 ms of silence, then the
    reconnect."""
    var run = Transcript()
    run.step("device 54c ce6 100 bt -1 1 5")
    run.step(SONY + "a0b1c2d3e4f5")
    run.step(simple())
    run.step(serial_feature())
    run.step(
        "open",
        (
            "hid open\nwrite"
            " 310200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026a1e7f7\nwrite"
            " 3102001400000000000000000000000000000000000000000000000000000000000000000000000000000000002400004000000000000000000000000000000000000000000000000000b71f41a2\nname"
            " DualSense Wireless Controller\nguid"
            " 050057564c050000e60c000000016800\ntype 6\nmapping"
            " 050057564c050000e60c000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:5657,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:1000.0 2:1000.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step(simple(lx=0, ly=255, b0=0x15, b1=0x3F, b2=0x03))
    run.step(
        "update",
        "axes -32768 32767 0 0 32767 32767\nbuttons 0010111001110\nhats 12\n",
    )
    run.step(simple(b1=0x04, rt=200, size=78))
    run.step(
        "update",
        "axes 128 128 0 0 32767 18632\nbuttons 0000000000000\nhats 0\n",
    )
    run.step(simple(b1=0x04, rt=100))
    run.step(
        "update",
        "axes 128 128 0 0 32767 -7068\nbuttons 0000000000000\nhats 0\n",
    )
    run.step("input 0501")
    run.step(
        "update",
        "axes 128 128 0 0 32767 -7068\nbuttons 0000000000000\nhats 0\n",
    )
    run.step("time 400")
    run.step(
        "update",
        "axes 128 128 0 0 32767 -7068\nbuttons 0000000000000\nhats 0\n",
    )
    run.step("time 600")
    run.step("update", "removed\ndisconnected\n")
    run.step("time 1000")
    run.step("update", "disconnected\n")
    run.step("time 1200")
    run.step("update", "disconnected\n")
    run.step(simple())
    run.step("update", "disconnected\n")
    run.step(
        "open",
        (
            "write"
            " 310200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026a1e7f7\nwrite"
            " 3102001400000000000000000000000000000000000000000000000000000000000000000000000000000000002400004000000000000000000000000000000000000000000000000000b71f41a2\nname"
            " DualSense Wireless Controller\nguid"
            " 050057564c050000e60c000000016800\ntype 6\nmapping"
            " 050057564c050000e60c000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:5657,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:1000.0 2:1000.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step(simple(b0=0x02))
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 2\n"
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_bluetooth_enhanced() raises:
    """A DualSense on Bluetooth that sends full reports: the serial number,
    the light reset after the connection animation, a bad CRC, rumble,
    sensors, the touchpad, and the tickle after 500 ms of silence."""
    var run = Transcript()
    run.step("device 54c ce6 100 bt -1 1 5")
    run.step(SONY + "a0b1c2d3e4f5")
    run.step(bt())
    run.step(serial_feature())
    run.step("time 50")
    run.step(
        "open",
        (
            "hid open\nfeature-get 09 128\nfeature-get 20 64\nwrite"
            " 310200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026a1e7f7\nname"
            " DualSense Wireless Controller\nguid"
            " 050057564c050000e60c000000016800\ntype 6\nmapping"
            " 050057564c050000e60c000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:5657,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:1000.0 2:1000.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step(bt(ts=100, seq=1))
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
    )
    run.step(bt(ts=200, seq=2, b0=0x00, crc=False))
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
    )
    run.step("led 7 8 9", "result 1\n")
    run.step("player 3", "result 1\n")
    run.step(bt(ts=10200000, seq=3, b1=0x01))
    run.step(
        "update",
        (
            "write"
            " 310200080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000023499c90\nwrite"
            " 3102001400000000000000000000000000000000000000000000000000000000000000000000000000000000003b070809000000000000000000000000000000000000000000000000007c9756c8\naxes"
            " 0 0 0 0 -32768 -32768\nbuttons 0000000001000\nhats 0\n"
        ),
    )
    run.step(
        "player 4",
        (
            "write"
            " 3102001400000000000000000000000000000000000000000000000000000000000000000000000000000000003f07080900000000000000000000000000000000000000000000000000adf5389f\n"
            "result 1\n"
        ),
    )
    run.step(
        "rumble 65535 256 0",
        (
            "write"
            " 31020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004f008070\n"
            "write"
            " 3102020001ff000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000009ddd762\n"
            "result 1\n"
        ),
    )
    run.step("sensors 1", "feature-get 05 64\nresult 1\nresult 1\n")
    run.step(bt(ts=10203000, seq=4, gx=10, gy=20, gz=30, ax=40, ay=50, az=60))
    run.step(
        "update",
        (
            "sensor 2 0.0109 0.0218 0.0327 3401000000\n"
            "sensor 1 0.0479 0.0599 0.0718 3401000000\n"
            "axes 0 0 0 0 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.step(bt(ts=10206000, seq=5, tp1=touch(True, 1919, 1069, 3)))
    run.step(
        "update",
        (
            "touch down 0 0 0.9995 0.9991 1.0000\n"
            "sensor 2 0.0000 0.0000 0.0000 3402000000\n"
            "sensor 1 0.0000 0.0000 0.0000 3402000000\n"
            "axes 0 0 0 0 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.step("time 2000")
    run.step(
        "update",
        (
            "write"
            " 310200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\naxes"
            " 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step("time 2400")
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
    )
    run.step("time 2600")
    run.step(
        "update",
        (
            "write"
            " 310200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\naxes"
            " 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_bluetooth_edge() raises:
    """A DualSense Edge on Bluetooth."""
    var run = Transcript()
    run.step("device 54c df2 100 bt -1 1 5")
    run.step(
        "strings Sony Interactive Entertainment|DualSense Edge Wireless"
        " Controller|"
    )
    run.step(bt())
    run.step(
        "open",
        (
            "hid open\nfeature-get 09 128\nfeature-get 20 64\nwrite"
            " 310200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026a1e7f7\nname"
            " DualSense Edge Wireless Controller\nguid"
            " 0500e0274c050000f20d000000016800\ntype 6\nmapping"
            " 0500e0274c050000f20d000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,paddle1:b16,paddle2:b15,paddle3:b14,paddle4:b13,crc:27e0,platform:Linux,\ncounts"
            " 6 17 1\ntouchpads 1 2\nsensors 1:1000.0 2:1000.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons"
            " 00000000000000000\nhats 0\n"
        ),
    )
    run.step(bt(ts=20000000, seq=1))
    run.step(
        "update",
        (
            "write"
            " 310200080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000023499c90\nwrite"
            " 3102001400000000000000000000000000000000000000000000000000000000000000000000000000000000002400004000000000000000000000000000000000000000000000000000b71f41a2\naxes"
            " 0 0 0 0 -32768 -32768\nbuttons 00000000000000000\nhats 0\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_third_party() raises:
    """A third-party pad that answers the capability report: the alternate
    report, a 16-bit sensor clock that wraps, a bad calibration, and the
    touchpad."""
    var run = Transcript()
    run.step("device f0d 7771 100 usb 0 1 5")
    run.step("strings HORI CO.,LTD.|Fighting Commander|")
    run.step(caps_feature())
    run.step(calibration_feature(bias0=2000))
    run.step(usb(alt=True))
    run.step(
        "open",
        "hid open\n"
        + _ps4_probe(0xF0D, 0x7771)
        + "feature-get 03 64\nfeature-get 03 128\nwrite"
        " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
        " 020014000000000000000000000000000000000000000000000000000000000000000000000000000000000024000040\nname"
        " HORI Fighting Commander\nguid"
        " 030032400d0f00007177000000016800\ntype 6\nmapping"
        " 030032400d0f00007177000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:4032,platform:Linux,\ncounts"
        " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 1 1 1"
        " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n",
    )
    run.step(usb(alt=True, seq=1, b0=0x28, b2=0x05))
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 1000010000001\nhats 0\n"
    )
    run.step("sensors 1", "feature-get 05 64\nresult 1\nresult 1\n")
    run.step(
        usb(
            alt=True,
            seq=2,
            gx=64,
            gy=128,
            gz=-64,
            ax=8192,
            az=-8192,
            ts=65000,
            tp1=touch(True, 10, 20),
            tp2=touch(True, 30, 40),
        )
    )
    run.step(
        "update",
        (
            "touch down 0 0 0.0052 0.0187 1.0000\n"
            "touch down 0 1 0.0156 0.0374 1.0000\n"
            "sensor 2 0.0698 0.1396 -0.0698 65000000\n"
            "sensor 1 9.8067 0.0000 -9.8067 65000000\n"
            "axes 0 0 0 0 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.step(
        usb(alt=True, seq=3, gx=64, gy=128, gz=-64, ax=8192, az=-8192, ts=100)
    )
    run.step(
        "update",
        (
            "touch up 0 0 0.0052 0.0187 0.0000\n"
            "touch up 0 1 0.0156 0.0374 0.0000\n"
            "sensor 2 0.0698 0.1396 -0.0698 65636000\n"
            "sensor 1 9.8067 0.0000 -9.8067 65636000\n"
            "axes 0 0 0 0 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.step(usb(alt=True, seq=4, ax=1, ay=2, az=3, ts=100))
    run.step(
        "update",
        (
            "sensor 2 0.0000 0.0000 0.0000 131172000\n"
            "sensor 1 0.0012 0.0024 0.0036 131172000\n"
            "axes 0 0 0 0 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.step(
        "rumble 512 512 0",
        (
            "write"
            " 020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "write"
            " 020300010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "result 1\n"
        ),
    )
    run.step(
        "led 1 1 1",
        (
            "write"
            " 020304010100000000000000000000000000000000000000000000000000000000000000000000000000000000010101\n"
            "result 1\n"
        ),
    )
    run.step(
        "player 1",
        (
            "write"
            " 02031401010000000000000000000000000000000000000000000000000000000000000000000000000000002a010101\n"
            "result 1\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_third_party_light_bar_only() raises:
    """A third-party wheel with only a light bar: no touchpad, no rumble
    and no player lights."""
    var run = Transcript()
    run.step("device f0d 7772 100 usb 0 1 5")
    run.step("strings HORI CO.,LTD.|Pad|")
    run.step(caps_feature(caps=0x04, caps2=0x00, kind=6))
    run.step(usb(alt=True))
    run.step(
        "open",
        "hid open\n"
        + _ps4_probe(0xF0D, 0x7772)
        + "feature-get 03 64\nfeature-get 03 128\nwrite"
        " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
        " 020004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040\nname"
        " HORI Pad\nguid 03003e3e0d0f00007277000000016800\ntype 6\nmapping"
        " 03003e3e0d0f00007277000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:3e3e,platform:Linux,\ncounts"
        " 6 11 1\ntouchpads 0\nsensors\ncaps 0 1 0 0 0\naxes 0 0 0 0 -32768"
        " -32768\nbuttons 00000000000\nhats 0\n",
    )
    run.step("rumble 512 512 0", "result 0\n")
    run.step(
        "led 9 9 9",
        (
            "write"
            " 020004000000000000000000000000000000000000000000000000000000000000000000000000000000000000090909\n"
            "result 1\n"
        ),
    )
    run.step(
        "player 1",
        (
            "write"
            " 020004000000000000000000000000000000000000000000000000000000000000000000000000000000000000090909\n"
            "result 1\n"
        ),
    )
    run.step(usb(alt=True, seq=1, b0=0x00, tp1=touch(True, 5, 5)))
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 00000000000\nhats 0\n"
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_third_party_bluetooth() raises:
    """A third-party pad on Bluetooth with full reports: the light reset
    does not wait for the sensor clock."""
    var run = Transcript()
    run.step("device f0d 7774 100 bt -1 1 5")
    run.step("strings HORI CO.,LTD.|Pad|")
    run.step(caps_feature())
    run.step(bt(alt=True))
    run.step(
        "open",
        "hid open\n"
        + _ps4_probe(0xF0D, 0x7774)
        + "feature-get 03 64\nfeature-get 03 128\nwrite"
        " 310200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026a1e7f7\nname"
        " HORI Pad\nguid 05003e3e0d0f00007477000000016800\ntype 6\nmapping"
        " 05003e3e0d0f00007477000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:3e3e,platform:Linux,\ncounts"
        " 6 13 1\ntouchpads 1 2\nsensors 1:1000.0 2:1000.0\ncaps 0 1 1 1"
        " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n",
    )
    run.step(bt(alt=True, seq=1))
    run.step(
        "update",
        (
            "write"
            " 310200080000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000023499c90\nwrite"
            " 3102001400000000000000000000000000000000000000000000000000000000000000000000000000000000002400004000000000000000000000000000000000000000000000000000b71f41a2\naxes"
            " 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step(
        "led 1 2 3",
        (
            "write"
            " 310200040000000000000000000000000000000000000000000000000000000000000000000000000000000000000102030000000000000000000000000000000000000000000000000063f01807\n"
            "result 1\n"
        ),
    )
    run.step(bt(alt=True, seq=2))
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_nacon_dongle() raises:
    """The Nacon Revolution 5 Pro dongle: the pad connects when the report
    sequence moves, and disconnects after 500 ms of silence."""
    var run = Transcript()
    run.step("device 3285 d18 100 usb 0 1 5")
    run.step("strings Nacon|Revolution 5 Pro|")
    run.step(caps_feature())
    run.step("open", "hid open\nfeature-get 03 128\nno joystick\n")
    run.step("update", "disconnected\n")
    run.step("time 600")
    run.step("update", "disconnected\n")
    run.step("time 0")
    run.step(usb(alt=True, seq=0))
    run.step(usb(alt=True, seq=1))
    run.step(usb(alt=True, seq=2, ax=1))
    run.step(usb(alt=True, seq=3, ax=1))
    run.step("update", "disconnected\n")
    run.step(
        "open",
        (
            "write"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
            " 020014000000000000000000000000000000000000000000000000000000000000000000000000000000000024000040\nname"
            " Nacon Revolution 5 Pro\nguid"
            " 03004ebf85320000180d000000016800\ntype 6\nmapping"
            " 03004ebf85320000180d000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:bf4e,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step(usb(alt=True, seq=4, ax=1, b0=0x18))
    run.step(usb(alt=True, seq=5, ax=1, b0=0x18))
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
    )
    run.step(usb(alt=True, seq=5, ax=1))
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
    )
    run.step(simple(b0=0x02))
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 2\n"
    )
    run.step(
        "rumble 1000 1000 0",
        (
            "write"
            " 020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "write"
            " 020300010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "result 1\n"
        ),
    )
    run.step("time 499")
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 2\n"
    )
    run.step("time 500")
    run.step("update", "removed\ndisconnected\n")
    run.step(usb(alt=True, seq=6, ax=1))
    run.step("update", "disconnected\n")
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_nacon_wired() raises:
    """The wired Nacon Revolution 5 Pro rumbles, though its capability
    report does not say so."""
    var run = Transcript()
    run.step("device 3285 d19 100 usb 0 1 5")
    run.step("strings Nacon|Revolution 5 Pro|")
    run.step(caps_feature(caps=0x46, caps2=0x00, kind=8))
    run.step(usb(alt=True))
    run.step(
        "open",
        (
            "hid open\nfeature-get 03 128\nwrite"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
            " 020004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040\nname"
            " Nacon Revolution 5 Pro\nguid"
            " 03004ebf85320000190d000000016800\ntype 6\nmapping"
            " 03004ebf85320000190d000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:bf4e,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 1 0 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step(
        "rumble 1000 1000 0",
        (
            "write"
            " 020200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "write"
            " 020300010100000000000000000000000000000000000000000000000000000000000000000000000000000000000000\n"
            "result 1\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_nacon_other() raises:
    """Another Nacon pad that answers the capability report has only what
    it reports."""
    var run = Transcript()
    run.step("device 3285 7777 100 usb 0 1 5")
    run.step("strings Nacon|Pad|")
    run.step(caps_feature(caps=0x46, caps2=0x00))
    run.step(usb(alt=True))
    run.step(
        "open",
        "hid open\n"
        + _ps4_probe(0x3285, 0x7777)
        + "feature-get 03 64\nfeature-get 03 128\nwrite"
        " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
        " 020004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040\nname"
        " Nacon Pad\nguid 03002a7d853200007777000000016800\ntype 6\nmapping"
        " 03002a7d853200007777000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:7d2a,platform:Linux,\ncounts"
        " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 1 0 0"
        " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n",
    )
    run.step("rumble 1000 1000 0", "result 0\n")
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_hori_bluetooth() raises:
    """A Hori DualSense pad on Bluetooth that does not answer the
    capability report: no effects, and the light reset does not wait for
    a sensor clock."""
    var run = Transcript()
    run.step("device f0d 163 100 bt -1 1 5")
    run.step("strings HORI CO.,LTD.|Pad|")
    run.step(bt())
    run.step(
        "open",
        (
            "hid open\nfeature-get 03 128\nname HORI Pad\nguid"
            " 05003e3e0d0f00006301000000016800\ntype 6\nmapping"
            " 05003e3e0d0f00006301000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:3e3e,platform:Linux,\ncounts"
            " 6 11 1\ntouchpads 0\nsensors\ncaps 0 0 0 0 0\naxes 0 0 0 0 -32768"
            " -32768\nbuttons 00000000000\nhats 0\n"
        ),
    )
    run.step(bt(seq=1, b0=0x00))
    run.step(
        "update", "axes 0 0 0 0 -32768 -32768\nbuttons 00000000000\nhats 0\n"
    )
    run.step("led 1 2 3", "result 0\n")
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_nacon_wired_silent() raises:
    """A wired Nacon Revolution 5 Pro with no capability report has no
    effects."""
    var run = Transcript()
    run.step("device 3285 d19 100 usb 0 1 5")
    run.step("strings Nacon|Revolution 5 Pro|")
    run.step(
        "open",
        (
            "hid open\nfeature-get 03 128\nname Nacon Revolution 5 Pro\nguid"
            " 03004ebf85320000190d000000016800\ntype 6\nmapping"
            " 03004ebf85320000190d000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:bf4e,platform:Linux,\ncounts"
            " 6 11 1\ntouchpads 0\nsensors\ncaps 0 0 0 0 0\naxes 0 0 0 0 -32768"
            " -32768\nbuttons 00000000000\nhats 0\n"
        ),
    )
    run.step("rumble 1000 1000 0", "result 0\n")
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_wolverine() raises:
    """The Razer Wolverine V2 Pro: a touchpad and sensors, and no effects."""
    var run = Transcript()
    run.step("device 1532 100b 100 usb 0 1 5")
    run.step("strings Razer|Wolverine V2 Pro|")
    run.step(
        "open",
        (
            "hid open\nfeature-get 03 128\nname Razer Wolverine V2 Pro\nguid"
            " 030080ae321500000b10000000016800\ntype 6\nmapping"
            " 030080ae321500000b10000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:ae80,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 0 0 0"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step("rumble 1000 1000 0", "result 0\n")
    run.step("led 1 2 3", "result 0\n")
    run.step("player 2", "result 1\n")
    run.step("sensors 1", "feature-get 05 64\nresult 1\nresult 1\n")
    run.step(usb(alt=True, seq=1, gx=64, ts=10))
    run.step(
        "update",
        (
            "sensor 2 0.0698 0.0000 0.0000 10000\n"
            "sensor 1 0.0000 0.0000 0.0000 10000\n"
            "axes 0 0 0 0 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_wolverine_wireless() raises:
    """The wireless Razer Wolverine V2 Pro, with a capability report that
    is not a DualSense one."""
    var run = Transcript()
    run.step("device 1532 100c 100 usb 0 1 5")
    run.step("strings Razer|Wolverine V2 Pro|")
    run.step(caps_feature(marker=0x27))
    run.step(
        "open",
        (
            "hid open\nfeature-get 03 128\nname Razer Wolverine V2 Pro\nguid"
            " 030080ae321500000c10000000016800\ntype 6\nmapping"
            " 030080ae321500000c10000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:ae80,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 0 0 0"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_kitsune() raises:
    """The Razer Kitsune: a touchpad, and no sensors."""
    var run = Transcript()
    run.step("device 1532 1012 100 usb 0 1 5")
    run.step("strings Razer|Kitsune|")
    run.step(
        "open",
        (
            "hid open\nfeature-get 03 128\nname Razer Kitsune\nguid"
            " 0300f97f321500001210000000016800\ntype 6\nmapping"
            " 0300f97f321500001210000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:7ff9,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors\ncaps 0 0 0 0 0\naxes 0 0 0 0"
            " -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step(usb(alt=True, seq=1, b2=0x07, tp1=touch(True, 5, 5)))
    run.step(
        "update",
        (
            "touch down 0 0 0.0026 0.0047 1.0000\n"
            "axes 0 0 0 0 -32768 -32768\n"
            "buttons 0000010000011\n"
            "hats 0\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_short_calibration() raises:
    """A short calibration report is ignored; the 32-bit sensor clock
    wraps."""
    var run = Transcript()
    run.step("device 54c ce6 100 usb 3 1 5")
    run.step(SONY)
    run.step(usb())
    run.step(calibration_feature(length=34))
    run.step(
        "open",
        (
            "hid open\nfeature-get 09 128\nfeature-get 20 64\nwrite"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
            " 020014000000000000000000000000000000000000000000000000000000000000000000000000000000000024000040\nname"
            " DualSense Wireless Controller\nguid"
            " 030057564c050000e60c000000016800\ntype 6\nmapping"
            " 030057564c050000e60c000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:5657,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step("sensors 1", "feature-get 05 64\nresult 1\nresult 1\n")
    run.step(usb(seq=1, gx=1, gy=2, gz=3, ax=4, ay=5, az=6, ts=0xFFFFFF00))
    run.step(usb(seq=2, gx=1, gy=2, gz=3, ax=4, ay=5, az=6, ts=0x10))
    run.step(
        "update",
        (
            "sensor 2 0.0011 0.0022 0.0033 1431655680000\n"
            "sensor 1 0.0048 0.0060 0.0072 1431655680000\n"
            "sensor 2 0.0011 0.0022 0.0033 1431655770666\n"
            "sensor 1 0.0048 0.0060 0.0072 1431655770666\n"
            "axes 0 0 0 0 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_bad_accelerometer_calibration() raises:
    """An accelerometer range that overflows 16 bits makes the calibration
    bad."""
    var run = Transcript()
    run.step("device 54c ce6 100 usb 3 1 5")
    run.step(SONY)
    run.step(usb())
    run.step(calibration_feature(acc_plus0=30000, acc_minus0=-30000))
    run.step(
        "open",
        (
            "hid open\nfeature-get 09 128\nfeature-get 20 64\nwrite"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
            " 020014000000000000000000000000000000000000000000000000000000000000000000000000000000000024000040\nname"
            " DualSense Wireless Controller\nguid"
            " 030057564c050000e60c000000016800\ntype 6\nmapping"
            " 030057564c050000e60c000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:5657,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step("sensors 1", "feature-get 05 64\nresult 1\nresult 1\n")
    run.step(usb(seq=1, gx=1, gy=2, gz=3, ax=4, ay=5, az=6, ts=7))
    run.step(
        "update",
        (
            "sensor 2 0.0011 0.0022 0.0033 2333\n"
            "sensor 1 0.0048 0.0060 0.0072 2333\n"
            "axes 0 0 0 0 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def test_bad_gyroscope_calibration() raises:
    """A gyroscope sensitivity far from 64 makes the calibration bad."""
    var run = Transcript()
    run.step("device 54c ce6 100 usb 3 1 5")
    run.step(SONY)
    run.step(usb())
    run.step(calibration_feature(gyro_plus0=100, gyro_minus0=-100))
    run.step(
        "open",
        (
            "hid open\nfeature-get 09 128\nfeature-get 20 64\nwrite"
            " 020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000\nwrite"
            " 020014000000000000000000000000000000000000000000000000000000000000000000000000000000000024000040\nname"
            " DualSense Wireless Controller\nguid"
            " 030057564c050000e60c000000016800\ntype 6\nmapping"
            " 030057564c050000e60c000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,touchpad:b11,misc1:b12,crc:5657,platform:Linux,\ncounts"
            " 6 13 1\ntouchpads 1 2\nsensors 1:250.0 2:250.0\ncaps 0 1 1 1"
            " 0\naxes 0 0 0 0 -32768 -32768\nbuttons 0000000000000\nhats 0\n"
        ),
    )
    run.step("sensors 1", "feature-get 05 64\nresult 1\nresult 1\n")
    run.step(usb(seq=1, gx=1, gy=2, gz=3, ax=4, ay=5, az=6, ts=7))
    run.step(
        "update",
        (
            "sensor 2 0.0011 0.0022 0.0033 2333\n"
            "sensor 1 0.0048 0.0060 0.0072 2333\n"
            "axes 0 0 0 0 -32768 -32768\n"
            "buttons 0000000000000\n"
            "hats 0\n"
        ),
    )
    run.close()
    assert_equal(run_script(run.script), run.expected)


def _device(
    vendor: Int, product: Int, bluetooth: Bool, serial: String = ""
) raises -> HidapiDevice:
    """Describe a device as enumeration finds it.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.
        bluetooth: Whether it is on Bluetooth.
        serial: The serial number.

    Returns:
        The device.

    Raises:
        Error: If the GUID cannot be made.
    """
    return HidapiDevice(
        HidDeviceInfo(
            "/dev/hidraw0",
            VendorId(vendor),
            ProductId(product),
            0x100,
            serial,
            "Maker",
            "Pad",
            1,
            5,
            -1 if bluetooth else 3,
            HID_BUS_BLUETOOTH if bluetooth else HID_BUS_USB,
        )
    )


def _report(line: String) -> List[UInt8]:
    """Return the bytes of a script's `input` or `feature` line.

    Args:
        line: The line.

    Returns:
        The bytes after the command word.
    """
    from tests._gamepad_hid_script import hex_bytes

    var start = line.find(" ") + 1
    return hex_bytes(String(line[byte=start:]))


def test_crc32() raises:
    """The CRC is the standard CRC-32, and it continues over parts."""
    var digits = List[UInt8]()
    for byte in "123456789".as_bytes():
        digits.append(byte)
    assert_equal(crc32(0, digits, 9), 0xCBF43926)
    var tail: List[UInt8] = [digits[4], digits[5], digits[6], digits[7]]
    tail.append(digits[8])
    assert_equal(crc32(crc32(0, digits, 4), tail, 5), 0xCBF43926)
    assert_equal(crc32(5, digits, 0), 5)


def test_detection() raises:
    """A pad that only may be a DualSense must answer the capability report
    as one."""
    var source = ScriptedHid()
    var sony = _device(0x054C, 0x0CE6, False)
    assert_true(Ps5Driver.is_supported_device(source, sony))
    var hori = _device(0x0F0D, 0x7773, False)
    assert_true(
        Ps5Driver.is_supported(
            hori.name, hori.type, hori.vendor, hori.product, 0x100, 3
        )
    )
    # No answer, a DualShock 4 answer, and a short answer.
    assert_false(Ps5Driver.is_supported_device(source, hori))
    var answer = _report(caps_feature())
    answer[2] = 0x27
    source.features[3] = answer.copy()
    assert_false(Ps5Driver.is_supported_device(source, hori))
    answer[2] = 0x28
    answer.resize(40, 0)
    source.features[3] = answer^
    assert_false(Ps5Driver.is_supported_device(source, hori))
    source.features[3] = _report(caps_feature())
    assert_true(Ps5Driver.is_supported_device(source, hori))
    assert_equal(len(source.log), 4)
    assert_equal(source.log[0], "feature-get 03 64")
    # An Xbox controller is neither.
    var xbox = _device(0x045E, 0x0B12, False)
    assert_false(
        Ps5Driver.is_supported(
            xbox.name, xbox.type, xbox.vendor, xbox.product, 0x100, 3
        )
    )
    assert_false(Ps5Driver.is_supported_device(source, xbox))
    assert_equal(len(source.log), 4)


def test_bluetooth_waits_for_usb() raises:
    """A Bluetooth pad connects only while no USB pad has its serial
    number, and a USB pad disconnects its own Bluetooth link."""
    var device = _device(0x054C, 0x0CE6, True, "a0b1c2d3e4f5")
    device.usb_serials = ["a0-b1-c2-d3-e4-f5"]
    var source = ScriptedHid()
    source.queue.append(_report(simple()))
    var driver = Ps5Driver()
    assert_true(driver.init_device(device, source, Duration64(0)))
    assert_equal(device.serial, "a0-b1-c2-d3-e4-f5")
    assert_equal(device.joysticks, 0)
    var pad = Optional[Gamepad](None)
    source.queue.append(_report(simple()))
    assert_true(driver.update_device(device, source, pad, Duration64(0)))
    assert_equal(device.joysticks, 0)
    device.usb_serials = List[String]()
    source.queue.append(_report(simple()))
    assert_true(driver.update_device(device, source, pad, Duration64(0)))
    assert_equal(device.joysticks, 1)
    var usb = _device(0x054C, 0x0CE6, False, "a0b1c2d3e4f5")
    var cable = ScriptedHid()
    var wired = Ps5Driver()
    assert_true(wired.init_device(usb, cable, Duration64(0)))
    assert_equal(usb.disconnect_bluetooth, "a0-b1-c2-d3-e4-f5")
    assert_equal(len(cable.log), 0)


def test_other_razer() raises:
    """A Razer pad the driver does not know has no touchpad, sensors or
    effects. Only its ids would bring it to the driver."""
    var device = _device(0x1532, 0x7777, False)
    var source = ScriptedHid()
    var driver = Ps5Driver()
    assert_true(driver.init_device(device, source, Duration64(0)))
    assert_false(driver.touchpad_supported)
    assert_false(driver.sensors_supported)
    assert_false(driver.effects_supported)
    assert_false(driver.use_alternate_report)
    assert_equal(device.joysticks, 1)


def test_closed_driver() raises:
    """Before enhanced mode, the driver reports no capabilities, sends no
    effects and turns on no sensors."""
    var device = _device(0x054C, 0x0CE6, False)
    var source = ScriptedHid()
    var driver = Ps5Driver()
    assert_equal(driver.capabilities(device), 0)
    driver.effects_supported = True
    driver.lightbar_supported = True
    assert_false(driver.set_led(device, source, 1, 2, 3))
    var joystick = Joystick(device.name, device.guid, 6, 13, 1)
    assert_false(driver.set_sensors_enabled(device, source, joystick, True))
    driver.sensors_supported = True
    assert_false(driver.set_sensors_enabled(device, source, joystick, True))
    assert_true(driver.set_sensors_enabled(device, source, joystick, False))
    assert_equal(len(source.log), 0)


def test_short_bluetooth_report() raises:
    """A Bluetooth report shorter than its CRC is dropped. SDL reads such a
    report's CRC from before its buffer."""
    var device = _device(0x054C, 0x0CE6, True)
    var source = ScriptedHid()
    var driver = Ps5Driver()
    _ = driver.init_device(device, source, Duration64(0))
    var pad = Optional[Gamepad](None)
    source.queue.append([UInt8(0x31), UInt8(0x00)])
    var now = Duration64(0.1, SECOND)
    assert_true(driver.update_device(device, source, pad, now))
    assert_equal(driver.last_packet.to(SECOND), 0)
    source.queue.append(_report(simple()))
    assert_true(driver.update_device(device, source, pad, now))
    assert_equal(driver.last_packet.to(SECOND), 0.1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
