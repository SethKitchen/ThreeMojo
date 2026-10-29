# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the Xbox One and Xbox Series controller driver.

Each script test runs a scripted device and compares the whole
transcript with the one SDL 3.2.24 prints for the same script: its real
`SDL_hidapi_xboxone.c`, linked with wrappers for the `SDL_hid_*` calls,
the clock and the rumble thread. The oracle prints `removed` once when a
gamepad goes away, as `run_script` does; SDL sends a gamepad event and a
joystick event.

The other tests call the driver directly, for what a transcript cannot
show: a write that fails while reads work, the packet sequence number
and the serial number.
"""

from std.testing import TestSuite, assert_equal, assert_false, assert_true
from extensions.gamepad.gamepad import Gamepad
from extensions.gamepad.guid import ProductId, VendorId
from extensions.gamepad.hid import HID_BUS_USB, HidDeviceInfo, HidSource
from extensions.gamepad.hid_device import HidapiDevice
from extensions.gamepad.hid_xboxone import XboxOneDriver, serial_from_packet
from extensions.gamepad.ids import GAMEPAD_TYPE_PS4, GAMEPAD_TYPE_XBOXONE
from tests._gamepad_hid_script import ScriptedHid, hex_bytes, run_script
from units.si import Duration64, SECOND

comptime BT_SERIES = """
device 45e b13 509 bt -1 1 5
strings |Xbox Wireless Controller|
input 01000000000000000000000000000000000000
open
input 010000ffff0080341200000002030910
input 010000ffff0080341200000002030910
input 01ffff0000ffff000000020000000000000000
input 04
input 0100000000
update
input 01ffff0000ffff00000002000003091c0001
input 01ffff0000ffff000000020000040000000000
update
input 0201
input 01ffff0000ffff0000000200000400100001
update
input 0200
update
input 0100800080008000800000000000000000
update
"""

comptime BT_SERIES_EXPECTED = """\
> device 45e b13 509 bt -1 1 5
> strings |Xbox Wireless Controller|
> input 01000000000000000000000000000000000000
> open
hid open
name Xbox Series X Controller
guid 050018dc5e040000130b000009056800
type 3
mapping 050018dc5e040000130b000009056800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,misc1:b11,crc:dc18,platform:Linux,
counts 6 12 1
touchpads 0
sensors
caps 0 0 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 000000000000
hats 0
> input 010000ffff0080341200000002030910
> input 010000ffff0080341200000002030910
> input 01ffff0000ffff000000020000000000000000
> input 04
> input 0100000000
> update
axes 32767 -32768 32767 -32768 0 -32768
buttons 000000000000
hats 0
> input 01ffff0000ffff00000002000003091c0001
> input 01ffff0000ffff000000020000040000000000
> update
axes 32767 -32768 32767 -32768 0 -32768
buttons 000000000000
hats 6
> input 0201
> input 01ffff0000ffff0000000200000400100001
> update
axes 32767 -32768 32767 -32768 0 -32768
buttons 000001000000
hats 6
> input 0200
> update
axes 32767 -32768 32767 -32768 0 -32768
buttons 000000000000
hats 6
> input 0100800080008000800000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000
hats 0
hid close
"""


def test_bluetooth_series_x_reads_the_17_byte_report() raises:
    """A Bluetooth Xbox Series X pad: sticks, triggers, hat, buttons, share,
    and the guide button report that takes over the guide bit."""
    assert_equal(run_script(BT_SERIES), BT_SERIES_EXPECTED)


comptime BT_SERIES_RUMBLE = """
device 45e b13 509 bt -1 1 5
strings |Xbox Wireless Controller|
time 1000
open
rumble 65535 32768 0
triggers 1000 2000 0
update
time 1049
update
time 1050
update
time 1200
update
triggers 65535 0 100
time 1400
update
led 1 2 3
player 1
sensors 1
fail
rumble 100 100 0
update
update
"""

comptime BT_SERIES_RUMBLE_EXPECTED = """\
> device 45e b13 509 bt -1 1 5
> strings |Xbox Wireless Controller|
> time 1000
> open
hid open
name Xbox Series X Controller
guid 050018dc5e040000130b000009056800
type 3
mapping 050018dc5e040000130b000009056800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,misc1:b11,crc:dc18,platform:Linux,
counts 6 12 1
touchpads 0
sensors
caps 0 0 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 000000000000
hats 0
> rumble 65535 32768 0
write 030f00006432ff00eb
result 1
> triggers 1000 2000 0
result 1
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000
hats 0
> time 1049
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000
hats 0
> time 1050
> update
write 030f01036432ff00eb
axes 0 0 0 0 -32768 -32768
buttons 000000000000
hats 0
> time 1200
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000
hats 0
> triggers 65535 0 100
write 030f64006432ff00eb
result 1
> time 1400
> update
write 030f00006432ff00eb
axes 0 0 0 0 -32768 -32768
buttons 000000000000
hats 0
> led 1 2 3
result 0
> player 1
result 1
> sensors 1
> fail
> rumble 100 100 0
result 1
> update
removed
disconnected
> update
disconnected
hid close
"""


def test_bluetooth_rumble_waits_while_the_pad_is_busy() raises:
    """Bluetooth rumble and trigger rumble share one report, which waits
    50 ms after the last one. Then the pad goes away."""
    assert_equal(run_script(BT_SERIES_RUMBLE), BT_SERIES_RUMBLE_EXPECTED)


comptime BT_ONES = """
device 45e 2e0 408 bt -1 1 5
strings |Xbox Wireless Controller|
open
input 010000ffff00800080ff030001055501
input 010000ffff00800080ff030001055501
update
input 0100800080008000800000000008aa02
update
input 0100800080008000800000000002000001
update
input 0100800080008000800000000004000400
update
input 0100800080008000800000000006000000
update
input 010080008000800080ffff000007000000
update
input 0100800080008000800000000009000000
update
"""

comptime BT_ONES_EXPECTED = """\
> device 45e 2e0 408 bt -1 1 5
> strings |Xbox Wireless Controller|
> open
hid open
name Xbox One S Controller
guid 050018dc5e040000e002000008046800
type 3
mapping 050018dc5e040000e002000008046800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,crc:dc18,platform:Linux,
counts 6 11 1
touchpads 0
sensors
caps 0 0 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 010000ffff00800080ff030001055501
> input 010000ffff00800080ff030001055501
> update
axes -32768 32767 0 0 32767 -16384
buttons 10101001010
hats 4
> input 0100800080008000800000000008aa02
> update
axes 0 0 0 0 -32768 -32768
buttons 01010010101
hats 9
> input 0100800080008000800000000002000001
> update
axes 0 0 0 0 -32768 -32768
buttons 00001000000
hats 3
> input 0100800080008000800000000004000400
> update
axes 0 0 0 0 -32768 -32768
buttons 00001000000
hats 6
> input 0100800080008000800000000006000000
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 12
> input 010080008000800080ffff000007000000
> update
axes 0 0 0 0 32767 -32768
buttons 00000000000
hats 8
> input 0100800080008000800000000009000000
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
hid close
"""


def test_bluetooth_xbox_one_s_reads_both_report_lengths() raises:
    """A Bluetooth Xbox One S: the 16-byte report of its first firmware and
    the 17-byte report, where byte 16 is also the back button."""
    assert_equal(run_script(BT_ONES), BT_ONES_EXPECTED)


comptime BT_ELITE2 = """
device 45e b22 509 bt -1 1 5
strings |Xbox Elite Wireless Controller Series 2|
open
input 0100800080008000800000000000000000000005
update
input 0100800080008000800000000000000000000005
update
input 010080008000800080000000000000000001000f
update
input 01008000800080008000000000000000000a000000000000000000000000000000000000000000
update
input 01008000800080008000000000000000000a000200000000000000000000000000000000000000
update
input 01008000800080008000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000
update
input 01008000800080008000000000000000000000000000000000000000000000000003000100000000000000000000000000000000000000
update
input 01008000800080008000000000000010000f00
update
input 0100800080008000800000000000ff03
update
led 1 2 3
triggers 65535 65535 0
"""

comptime BT_ELITE2_EXPECTED = """\
> device 45e b22 509 bt -1 1 5
> strings |Xbox Elite Wireless Controller Series 2|
> open
hid open
name Xbox One Elite 2 Controller
guid 0500eac95e040000220b000009056800
type 3
mapping 0500eac95e040000220b000009056800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,paddle1:b11,paddle2:b13,paddle3:b12,paddle4:b14,crc:c9ea,platform:Linux,
counts 6 15 1
touchpads 0
sensors
caps 0 0 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 000000000000000
hats 0
> input 0100800080008000800000000000000000000005
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001010
hats 0
> input 0100800080008000800000000000000000000005
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001010
hats 0
> input 010080008000800080000000000000000001000f
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000000
hats 0
> input 01008000800080008000000000000000000a000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000101
hats 0
> input 01008000800080008000000000000000000a000200000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000000
hats 0
> input 01008000800080008000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001100
hats 0
> input 01008000800080008000000000000000000000000000000000000000000000000003000100000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000000
hats 0
> input 01008000800080008000000000000010000f00
> update
axes 0 0 0 0 -32768 -32768
buttons 000001000000000
hats 0
> input 0100800080008000800000000000ff03
> update
axes 0 0 0 0 -32768 -32768
buttons 111111111110000
hats 0
> led 1 2 3
result 0
> triggers 65535 65535 0
write 030f64640000ff00eb
result 1
hid close
"""


def test_bluetooth_elite_2_reads_the_paddles() raises:
    """A Bluetooth Elite Series 2: the paddles in the 20, 39 and 55 byte
    reports, dropped while a profile maps them."""
    assert_equal(run_script(BT_ELITE2), BT_ELITE2_EXPECTED)


comptime USB_ONES = """
device 45e 2ea 408 usb 0 1 5
strings Microsoft|Controller|
time 500
input 2000010e1000000000000000000000000000
input 07200102015b
input 0c0001110000000000000000000000000000000000
open
input 2000020e9459ff03000000000080ff7f3412
input 2000030e9459ff03000000000080ff7f3412
input 07200302015b
update
input 07300002015b
input 07300902005b
update
input 07210502015b
input 0520060100
input 2200070100
input 0320080100
input 0c00090a00000000000000000000
input 2000040e0002000000000000000000000000
update
rumble 65535 32768 0
triggers 655 1310 0
time 509
update
time 510
update
time 520
update
led 1 2 3
"""

comptime USB_ONES_EXPECTED = """\
> device 45e 2ea 408 usb 0 1 5
> strings Microsoft|Controller|
> time 500
> input 2000010e1000000000000000000000000000
> input 07200102015b
> input 0c0001110000000000000000000000000000000000
> open
hid open
name Xbox One S Controller
guid 0300aa4e5e040000ea02000008046800
type 3
mapping 0300aa4e5e040000ea02000008046800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,crc:4eaa,platform:Linux,
counts 6 11 1
touchpads 0
sensors
caps 0 0 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 2000020e9459ff03000000000080ff7f3412
> input 2000030e9459ff03000000000080ff7f3412
> input 07200302015b
> update
axes 0 32767 32767 -4661 32767 -32768
buttons 10010111010
hats 3
> input 07300002015b
> input 07300902005b
> update
write 01200109000720020000000000
write 01200909000720020000000000
axes 0 32767 32767 -4661 32767 -32768
buttons 10010011010
hats 3
> input 07210502015b
> input 0520060100
> input 2200070100
> input 0320080100
> input 0c00090a00000000000000000000
> input 2000040e0002000000000000000000000000
> update
axes 0 -1 0 -1 -32768 -32768
buttons 00000000000
hats 4
> rumble 65535 32768 0
write 09000009000f00006432ff00eb
result 1
> triggers 655 1310 0
result 1
> time 509
> update
axes 0 -1 0 -1 -32768 -32768
buttons 00000000000
hats 4
> time 510
> update
write 09000009000f01026432ff00eb
axes 0 -1 0 -1 -32768 -32768
buttons 00000000000
hats 4
> time 520
> update
axes 0 -1 0 -1 -32768 -32768
buttons 00000000000
hats 4
> led 1 2 3
result 0
hid close
"""


def test_usb_xbox_one_s_reads_gip_packets() raises:
    """A USB Xbox One S: the state and guide button packets, the
    acknowledgements, the packets that are skipped, and rumble, which
    waits 10 ms after the last report."""
    assert_equal(run_script(USB_ONES), USB_ONES_EXPECTED)


comptime USB_TRIGGERS = """
device 45e 2ea 408 usb 0 1 5
strings Microsoft|Controller|
open
input 2000011a000000000000000000000000000000000000c000000000000000
update
input 2000021a0000000000000000000000000000000000000000000000000000
update
input 2000031a0000000000000000000000000000000000008000000000000000
update
input 2000041a000000020001000000000000000000000000c000000000000000
update
input 2000050e0000000000000000000000000000
update
input 2000061a0000000000000000000000000000000000004000000000000000
update
input 2000070e0000ffffff030000000000000000
update
"""

comptime USB_TRIGGERS_EXPECTED = """\
> device 45e 2ea 408 usb 0 1 5
> strings Microsoft|Controller|
> open
hid open
name Xbox One S Controller
guid 0300aa4e5e040000ea02000008046800
type 3
mapping 0300aa4e5e040000ea02000008046800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,crc:4eaa,platform:Linux,
counts 6 11 1
touchpads 0
sensors
caps 0 0 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 2000011a000000000000000000000000000000000000c000000000000000
> update
axes 0 0 0 0 32767 32767
buttons 00000000000
hats 0
> input 2000021a0000000000000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 2000031a0000000000000000000000000000000000008000000000000000
> update
axes 0 0 0 0 32767 -32768
buttons 00000000000
hats 0
> input 2000041a000000020001000000000000000000000000c000000000000000
> update
axes 0 0 0 0 0 -16384
buttons 00000000000
hats 0
> input 2000050e0000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 2000061a0000000000000000000000000000000000004000000000000000
> update
axes 0 0 0 0 -32768 32767
buttons 00000000000
hats 0
> input 2000070e0000ffffff030000000000000000
> update
axes 0 0 0 0 32767 32767
buttons 00000000000
hats 0
hid close
"""


def test_usb_26_byte_report_can_say_a_trigger_is_full() raises:
    """The 26-byte USB report: byte 18 can say a trigger at rest is full."""
    assert_equal(run_script(USB_TRIGGERS), USB_TRIGGERS_EXPECTED)


comptime USB_INIT = """
device 45e 2ea 408 usb 0 1 5
strings Microsoft|Controller|
time 1000
open
input 0220011c00000000000000000000000000000000000000000000000000000000
update
time 1099
update
time 1100
update
time 1149
update
time 1150
update
input 0220021c00000000000000000000000000000000000000000000000000000000
input 0420030400000000
update
input 0320040100
update
input 0220051c00000000000000000000000000000000000000000000000000000000
update
input 2000060e1000000000000000000000000000
input 2000070e2000000000000000000000000000
update
"""

comptime USB_INIT_EXPECTED = """\
> device 45e 2ea 408 usb 0 1 5
> strings Microsoft|Controller|
> time 1000
> open
hid open
name Xbox One S Controller
guid 0300aa4e5e040000ea02000008046800
type 3
mapping 0300aa4e5e040000ea02000008046800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,crc:4eaa,platform:Linux,
counts 6 11 1
touchpads 0
sensors
caps 0 0 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 0220011c00000000000000000000000000000000000000000000000000000000
> update
write 04200100
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> time 1099
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> time 1100
> update
write 0520020100
write 0a200303000114
write 062004020100
write 09000509000f00000000ff00eb
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> time 1149
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> time 1150
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 0220021c00000000000000000000000000000000000000000000000000000000
> input 0420030400000000
> update
write 0520060100
write 0a200703000114
write 062008020100
write 09000909000f00000000ff00eb
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 0320040100
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 0220051c00000000000000000000000000000000000000000000000000000000
> update
write 04200a00
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 2000060e1000000000000000000000000000
> input 2000070e2000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 01000000000
hats 0
hid close
"""


def test_usb_startup_follows_the_announce() raises:
    """The GIP startup: the announce, the identification request and its
    timeout, the startup packets and the wait for input."""
    assert_equal(run_script(USB_INIT), USB_INIT_EXPECTED)


comptime USB_GONE = """
device 45e 2ea 408 usb 0 1 5
strings Microsoft|Controller|
time 1000
open
input 0220011c00000000000000000000000000000000000000000000000000000000
update
time 1100
fail
update
update
"""

comptime USB_GONE_EXPECTED = """\
> device 45e 2ea 408 usb 0 1 5
> strings Microsoft|Controller|
> time 1000
> open
hid open
name Xbox One S Controller
guid 0300aa4e5e040000ea02000008046800
type 3
mapping 0300aa4e5e040000ea02000008046800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,crc:4eaa,platform:Linux,
counts 6 11 1
touchpads 0
sensors
caps 0 0 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 0220011c00000000000000000000000000000000000000000000000000000000
> update
write 04200100
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> time 1100
> fail
> update
write 0520020100
removed
disconnected
> update
disconnected
hid close
"""


def test_usb_startup_stops_when_the_pad_goes_away() raises:
    """A pad that goes away during its startup: the first startup packet
    fails, and the rest are not sent."""
    assert_equal(run_script(USB_GONE), USB_GONE_EXPECTED)


comptime USB_PDP = """
device e6f 246 100 usb 0 1 5
strings PDP|Rock Candy|
time 10
open
time 59
update
time 60
update
triggers 100 100 0
rumble 6550 0 0
"""

comptime USB_PDP_EXPECTED = """\
> device e6f 246 100 usb 0 1 5
> strings PDP|Rock Candy|
> time 10
> open
hid open
write 0520010100
write 0a200203000114
write 062003020100
write 09000409000f00000000ff00eb
name PDP Xbox One Rock Candy
guid 0300cb3a6f0e00004602000000016800
type 3
mapping 0300cb3a6f0e00004602000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,crc:3acb,platform:Linux,
counts 6 11 1
touchpads 0
sensors
caps 0 0 0 1 0
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> time 59
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> time 60
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> triggers 100 100 0
result 0
> rumble 6550 0 0
write 09000009000f00000a00ff00eb
result 1
hid close
"""


def test_pdp_rock_candy_starts_at_once() raises:
    """The PDP Rock Candy sends no announce, so the driver starts it at once.
    It has no trigger motors."""
    assert_equal(run_script(USB_PDP), USB_PDP_EXPECTED)


comptime USB_POWERA = """
device 24c6 541a 100 usb 0 1 5
strings PowerA|Controller|
time 5
open
input 0220011c00000000000000000000000000000000000000000000000000000000
input 0420020400000000
update
"""

comptime USB_POWERA_EXPECTED = """\
> device 24c6 541a 100 usb 0 1 5
> strings PowerA|Controller|
> time 5
> open
hid open
name PowerA Controller
guid 0300eca9c62400001a54000000016800
type 3
mapping 0300eca9c62400001a54000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,crc:a9ec,platform:Linux,
counts 6 11 1
touchpads 0
sensors
caps 0 0 0 1 0
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 0220011c00000000000000000000000000000000000000000000000000000000
> input 0420020400000000
> update
write 0520010100
write 0a200203000114
write 062003020100
write 09000409000f00001d1dff0000
write 09000509000f00000000ff00eb
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
hid close
"""


def test_powera_startup_starts_the_motors() raises:
    """Some PowerA pads get an extra startup packet that starts the motors."""
    assert_equal(run_script(USB_POWERA), USB_POWERA_EXPECTED)


comptime USB_POWERA_SERIES = """
device 20d6 2005 100 usb 0 1 5
strings PowerA|Controller|
open
input 200001200000000000000000000000000000010000000000000000000000000000000000
update
triggers 65535 65535 0
rumble 65535 0 0
rumble 0 65535 0
time 1000
update
rumble 0 0 0
"""

comptime USB_POWERA_SERIES_EXPECTED = """\
> device 20d6 2005 100 usb 0 1 5
> strings PowerA|Controller|
> open
hid open
name PowerA Xbox Series X Controller
guid 0300eca9d62000000520000000016800
type 3
mapping 0300eca9d62000000520000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,misc1:b11,crc:a9ec,platform:Linux,
counts 6 12 1
touchpads 0
sensors
caps 0 0 0 1 0
axes 0 0 0 0 -32768 -32768
buttons 000000000000
hats 0
> input 200001200000000000000000000000000000010000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
> triggers 65535 65535 0
result 0
> rumble 65535 0 0
write 09000009000f00006400ff00eb
result 1
> rumble 0 65535 0
result 1
> time 1000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
> rumble 0 0 0
result 1
hid close
"""


def test_powera_series_pad_has_no_trigger_motors() raises:
    """A PowerA Xbox Series pad has a share button and no trigger motors.
    Rumble sent at time 0 records no send time, so later rumble waits."""
    assert_equal(run_script(USB_POWERA_SERIES), USB_POWERA_SERIES_EXPECTED)


comptime USB_ATROX = """
device 1532 a00 100 usb 0 1 5
strings Razer|Atrox|
open
input 2000010e0010000000000000000000000000
update
input 2000020e0020000000000000000000000000
update
"""

comptime USB_ATROX_EXPECTED = """\
> device 1532 a00 100 usb 0 1 5
> strings Razer|Atrox|
> open
hid open
name Razer Atrox
guid 03007ae632150000000a000000016800
type 3
mapping 03007ae632150000000a000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,crc:e67a,platform:Linux,
counts 6 11 1
touchpads 0
sensors
caps 0 0 0 1 0
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 2000010e0010000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000001
hats 0
> input 2000020e0020000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 00000000010
hats 0
hid close
"""


def test_razer_atrox_swaps_the_shoulder_buttons() raises:
    """The Razer Atrox has the shoulder button bits the other way round."""
    assert_equal(run_script(USB_ATROX), USB_ATROX_EXPECTED)


comptime USB_ELITE2 = """
device 45e b00 509 usb 0 1 5
strings Microsoft|Controller|
open
input 2000012e00000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000
update
input 2000022e00000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000
input 2000032e00000000000000000000000000000000000003010000000000000000000000000000000000000000000000000000
update
input 2000042200000000000000000000000000000400000000000000000000000000000000000000
update
input 2000052200000000000000000000000000000402000000000000000000000000000000000000
update
input 2000062f0000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000
update
input 2000072f0000000000000000000000000000080000000000010000000000000000000000000000000000000000000000000000
update
input 2000080e1000000000000000000000000000
input 0c0009111000000000000000000000000000020000
update
input 0c000a111000000000000000000000000000020000
input 0c000b1110000000000000000000000000000c0100
update
input 0c000c1120000000000000000000000000000c0100
update
input 0c000d1000000000000000000000000000000100
input 20000e2e00000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000
update
input 0c000f110000000000000000000000000000010000
input 2000102e00000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000
update
led 1 2 3
fail
led 3 2 1
update
"""

comptime USB_ELITE2_EXPECTED = """\
> device 45e b00 509 usb 0 1 5
> strings Microsoft|Controller|
> open
hid open
name Xbox One Elite 2 Controller
guid 0300aa4e5e040000000b000009056800
type 3
mapping 0300aa4e5e040000000b000009056800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,paddle1:b11,paddle2:b13,paddle3:b12,paddle4:b14,crc:4eaa,platform:Linux,
counts 6 15 1
touchpads 0
sensors
caps 0 1 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 000000000000000
hats 0
> input 2000012e00000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000
> update
write 4d0000020700
axes 0 0 0 0 -32768 -32768
buttons 000000000001000
hats 0
> input 2000022e00000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000
> input 2000032e00000000000000000000000000000000000003010000000000000000000000000000000000000000000000000000
> update
write 4d0000020700
write 4d0000020700
axes 0 0 0 0 -32768 -32768
buttons 000000000000000
hats 0
> input 2000042200000000000000000000000000000400000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000010
hats 0
> input 2000052200000000000000000000000000000402000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000000
hats 0
> input 2000062f0000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000001
hats 0
> input 2000072f0000000000000000000000000000080000000000010000000000000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000000
hats 0
> input 2000080e1000000000000000000000000000
> input 0c0009111000000000000000000000000000020000
> update
axes 0 0 0 0 -32768 -32768
buttons 100000000000100
hats 0
> input 0c000a111000000000000000000000000000020000
> input 0c000b1110000000000000000000000000000c0100
> update
axes 0 0 0 0 -32768 -32768
buttons 100000000000011
hats 0
> input 0c000c1120000000000000000000000000000c0100
> update
axes 0 0 0 0 -32768 -32768
buttons 100000000000000
hats 0
> input 0c000d1000000000000000000000000000000100
> input 20000e2e00000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000000000
hats 0
> input 0c000f110000000000000000000000000000010000
> input 2000102e00000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001000
hats 0
> led 1 2 3
write 0e0000050000010203
result 1
> fail
> led 3 2 1
write 0e0000050000030201
result 0
> update
removed
disconnected
hid close
"""


def test_usb_elite_2_reads_the_paddles_and_sets_the_light() raises:
    """A USB Elite Series 2: the paddles in the 34, 46 and 47 byte reports
    and in the unmapped state packet, and the color light."""
    assert_equal(run_script(USB_ELITE2), USB_ELITE2_EXPECTED)


comptime USB_ELITE1 = """
device 45e 2e3 100 usb 0 1 5
strings Microsoft|Controller|
open
input 2000011d100000000000000000000000000010000000000000000000000000000f
update
input 2000021d100000000000000000000000000020000000000000000000000000000f
update
input 2000031d1001000000000000000000000000100100000000000000000000000002
update
"""

comptime USB_ELITE1_EXPECTED = """\
> device 45e 2e3 100 usb 0 1 5
> strings Microsoft|Controller|
> open
hid open
name Xbox One Elite Controller
guid 0300aa4e5e040000e302000000016800
type 3
mapping 0300aa4e5e040000e302000000016800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,paddle1:b11,paddle2:b13,paddle3:b12,paddle4:b14,crc:4eaa,platform:Linux,
counts 6 15 1
touchpads 0
sensors
caps 0 0 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 000000000000000
hats 0
> input 2000011d100000000000000000000000000010000000000000000000000000000f
> update
axes 0 0 0 0 -32768 -32768
buttons 100000000001111
hats 0
> input 2000021d100000000000000000000000000020000000000000000000000000000f
> update
axes 0 0 0 0 -32768 -32768
buttons 100000000000000
hats 0
> input 2000031d1001000000000000000000000000100100000000000000000000000002
> update
axes 0 0 0 0 -32768 -32768
buttons 100000000001000
hats 1
hid close
"""


def test_usb_elite_1_finds_mapped_paddles() raises:
    """A USB Elite Series 1: the 29-byte report compares the mapped and the
    raw buttons to find mapped paddles."""
    assert_equal(run_script(USB_ELITE1), USB_ELITE1_EXPECTED)


comptime USB_SERIES = """
device 45e b12 509 usb 0 1 5
strings Microsoft|Controller|
open
input 200001200000000000000000000000000000010000000000000000000000000000000000
update
input 200002200000000000000000000000000000010000000000000000000000000000000000
update
input 2000032c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
update
input 2000042c0000000000000000000000000000000000000100000000000000000000000000000000000000000000000000
update
input 2000052e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
update
input 2000062e00000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000
update
input 2000073c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
update
input 2000083c000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000
update
input 200009320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
update
input 0c000a1100000000000000000000000000000f0000
update
"""

comptime USB_SERIES_EXPECTED = """\
> device 45e b12 509 usb 0 1 5
> strings Microsoft|Controller|
> open
hid open
name Xbox Series X Controller
guid 0300aa4e5e040000120b000009056800
type 3
mapping 0300aa4e5e040000120b000009056800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,misc1:b11,crc:4eaa,platform:Linux,
counts 6 12 1
touchpads 0
sensors
caps 0 0 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 000000000000
hats 0
> input 200001200000000000000000000000000000010000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
> input 200002200000000000000000000000000000010000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
> input 2000032c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
> input 2000042c0000000000000000000000000000000000000100000000000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
> input 2000052e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
> input 2000062e00000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
> input 2000073c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
> input 2000083c000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
> input 200009320000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
> input 0c000a1100000000000000000000000000000f0000
> update
axes 0 0 0 0 -32768 -32768
buttons 000000000001
hats 0
hid close
"""


def test_usb_series_x_finds_the_share_button() raises:
    """A USB Xbox Series X: where the share button is, by report length."""
    assert_equal(run_script(USB_SERIES), USB_SERIES_EXPECTED)


comptime USB_GIP = """
device 45e 2ea 408 usb 0 1 5
strings Microsoft|Controller|
open
input 20d0050a0e40000000000000400000
input 209005040a00000020
update
input 208005000e
update
input 2090060200010207200102015b
input 20c00702040102
input 20800704020102030407200102015b
update
input 07200802015b2000090e8000000000000000000000000000
update
input 07200a0500
update
input 2000
input 22000b808080800022000c80
input 22800d05
input 20000e0022000f0a10101010101010101010
update
input 1e30101004003039373132333332333534303336
update
"""

comptime USB_GIP_EXPECTED = """\
> device 45e 2ea 408 usb 0 1 5
> strings Microsoft|Controller|
> open
hid open
name Xbox One S Controller
guid 0300aa4e5e040000ea02000008046800
type 3
mapping 0300aa4e5e040000ea02000008046800,*,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,crc:4eaa,platform:Linux,
counts 6 11 1
touchpads 0
sensors
caps 0 0 0 1 1
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 20d0050a0e40000000000000400000
> input 209005040a00000020
> update
write 012005090020200a0000000400
write 012005090020200e0000000000
axes 0 0 0 0 -32768 -32768
buttons 00000000000
hats 0
> input 208005000e
> update
axes 16384 0 0 -8193 -32768 -32768
buttons 00100000000
hats 0
> input 2090060200010207200102015b
> input 20c00702040102
> input 20800704020102030407200102015b
> update
write 01200609002020020000000000
axes 16384 0 0 -8193 -32768 -32768
buttons 00100000000
hats 0
> input 07200802015b2000090e8000000000000000000000000000
> update
axes 0 0 0 -1 -32768 -32768
buttons 00010100000
hats 0
> input 07200a0500
> update
axes 0 0 0 -1 -32768 -32768
buttons 00010000000
hats 0
> input 2000
> input 22000b808080800022000c80
> input 22800d05
> input 20000e0022000f0a10101010101010101010
> update
axes 4112 -4113 4112 -4113 960 -31744
buttons 01000000000
hats 0
> input 1e30101004003039373132333332333534303336
> update
write 01201009001e20100000000000
axes 4112 -4113 4112 -4113 960 -31744
buttons 01000000000
hats 0
hid close
"""


def test_gip_framing() raises:
    """GIP framing: chunks, acknowledgements, several packets in one USB
    packet, short packets, long headers and the serial number."""
    assert_equal(run_script(USB_GIP), USB_GIP_EXPECTED)


struct WriteFailingHid(HidSource):
    """A HID device whose reads work and whose writes fail."""

    var queue: List[List[UInt8]]
    var writes: Int

    def __init__(out self):
        """Create a device with no reports."""
        self.queue = List[List[UInt8]]()
        self.writes = 0

    @staticmethod
    def open(path: String) raises -> Self:
        """Open a device.

        Args:
            path: Ignored.

        Returns:
            A device with no reports.
        """
        return WriteFailingHid()

    def read(mut self, mut buffer: List[UInt8], milliseconds: Int) -> Int:
        """Give the next queued report.

        Args:
            buffer: The buffer.
            milliseconds: Ignored.

        Returns:
            The report's length, or 0 when none is queued.
        """
        if len(self.queue) == 0:
            return 0
        var report = self.queue.pop(0)
        for index in range(len(report)):
            buffer[index] = report[index]
        return len(report)

    def write(mut self, data: List[UInt8]) -> Int:
        """Count a write and fail it.

        Args:
            data: The report.

        Returns:
            -1.
        """
        self.writes += 1
        return -1

    def get_feature_report(mut self, mut buffer: List[UInt8]) -> Int:
        """Fail.

        Args:
            buffer: Ignored.

        Returns:
            -1.
        """
        return -1

    def send_feature_report(mut self, data: List[UInt8]) -> Int:
        """Fail.

        Args:
            data: Ignored.

        Returns:
            -1.
        """
        return -1


def _usb_device(product: Int) raises -> HidapiDevice:
    """Describe a wired Microsoft pad.

    Args:
        product: The USB product id.

    Returns:
        The device.
    """
    return HidapiDevice(
        HidDeviceInfo(
            "/dev/hidraw0",
            VendorId(0x045E),
            ProductId(product),
            0x0408,
            "",
            "Microsoft",
            "Controller",
            1,
            5,
            0,
            HID_BUS_USB,
        )
    )


def test_a_failed_acknowledgement_drops_the_rest_of_the_packet() raises:
    """SDL stops reading a USB packet when it cannot acknowledge a GIP
    packet in it, so the announce after it does nothing."""
    var device = _usb_device(0x02EA)
    var source = WriteFailingHid()
    var driver = XboxOneDriver()
    var now = Duration64(1.0, SECOND)
    assert_true(driver.init_device(device, source, now))
    var pad = Optional[Gamepad](None)
    source.queue.append(hex_bytes("0730010201" + "5b" + "0220021c" + "00" * 28))
    assert_true(driver.update_device(device, source, pad, now))
    assert_equal(source.writes, 1)
    assert_equal(driver.init_state, 4)
    # The same announce on its own starts the identification, whose write
    # fails too.
    source.queue.append(hex_bytes("0220021c" + "00" * 28))
    assert_true(driver.update_device(device, source, pad, now))
    assert_equal(source.writes, 2)
    assert_equal(driver.init_state, 1)


def test_rumble_reports_a_failed_write() raises:
    """A rumble packet that cannot be written leaves the motors idle."""
    var device = _usb_device(0x02EA)
    var source = WriteFailingHid()
    var driver = XboxOneDriver()
    _ = driver.init_device(device, source, Duration64(1.0, SECOND))
    assert_false(driver.rumble(device, source, 65535, 0))
    assert_false(driver.rumble_triggers(device, source, 0, 65535))
    assert_equal(driver.rumble_state, 0)


def test_the_sequence_number_skips_zero() raises:
    """After 255 the packet sequence number goes to 1."""
    var device = _usb_device(0x02EA)
    var source = ScriptedHid()
    var driver = XboxOneDriver()
    var now = Duration64(1.0, SECOND)
    _ = driver.init_device(device, source, now)
    driver.sequence = 254
    var pad = Optional[Gamepad](None)
    # Two guide packets that ask for an acknowledgement with sequence 0.
    source.queue.append(hex_bytes("07300002015b07300002005b"))
    _ = driver.update_device(device, source, pad, now)
    assert_equal(len(source.log), 2)
    assert_equal(source.log[0], "write 0120ff09000720020000000000")
    assert_equal(source.log[1], "write 01200109000720020000000000")


def test_the_serial_number_packet_names_the_device() raises:
    """The serial number packet sets the device's serial number."""
    var device = _usb_device(0x02EA)
    var source = ScriptedHid()
    var driver = XboxOneDriver()
    var now = Duration64(1.0, SECOND)
    _ = driver.init_device(device, source, now)
    var pad = Optional[Gamepad](None)
    source.queue.append(
        hex_bytes("1e2001100400" + "3039373132333332333534303336")
    )
    _ = driver.update_device(device, source, pad, now)
    assert_equal(device.serial, "3039373132333332333534303336")


def test_a_serial_byte_below_16_ends_the_serial_number() raises:
    """SDL writes each byte with `SDL_uitoa`, so a byte below 0x10 gives
    one digit and ends the string."""
    var data = hex_bytes("0400" + "3a05" + "ff" * 12)
    assert_equal(serial_from_packet(data, 0), "3a5")
    data = hex_bytes("0000" + "00" * 14)
    assert_equal(serial_from_packet(data, 0), "0")


def test_the_driver_takes_xbox_one_pads_only() raises:
    """The driver runs the pads typed Xbox One, and asks them nothing."""
    assert_true(
        XboxOneDriver.is_supported(
            "", GAMEPAD_TYPE_XBOXONE, VendorId(0x045E), ProductId(0x02EA), 0, 0
        )
    )
    assert_false(
        XboxOneDriver.is_supported(
            "", GAMEPAD_TYPE_PS4, VendorId(0x054C), ProductId(0x09CC), 0, 0
        )
    )
    var device = _usb_device(0x02EA)
    var source = ScriptedHid()
    assert_true(XboxOneDriver.is_supported_device(source, device))


def test_the_pad_has_no_motion_sensors() raises:
    """The pad has no sensors to turn on."""
    var device = _usb_device(0x02EA)
    var source = ScriptedHid()
    var driver = XboxOneDriver()
    var now = Duration64(1.0, SECOND)
    _ = driver.init_device(device, source, now)
    var joystick = driver.open_joystick(device, source, now)
    assert_false(driver.set_sensors_enabled(device, source, joystick, True))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
