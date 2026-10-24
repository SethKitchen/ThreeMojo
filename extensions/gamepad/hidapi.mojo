# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# This file is an altered version of src/joystick/hidapi/SDL_hidapijoystick.c
# and of SDL_CreateMappingForHIDAPIGamepad in src/joystick/SDL_gamepad.c,
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

"""Gamepads that SDL's HIDAPI drivers run: DualSense, DualShock 4, Switch
Pro and Xbox One controllers, with their lights, rumble, touchpads and
motion sensors.

    var database = default_mapping_database()
    var hub = HidHub[HidrawFile]()
    while running:
        for change in hub.detect(database):
            ...
        for ref pad in hub.pads:
            for event in pad.update():
                ...

A driver speaks the controller's own reports, so it reaches what the
kernel's evdev driver does not: the light bar, the player lights, the
trigger motors and the calibrated sensors. `HidGamepad` runs one device
with its driver, as SDL's HIDAPI joystick driver does. `HidHub` finds the
devices on Linux with `enumerate_hidraw`, and drops them when they go
away.

A device that the evdev backend also sees is the same pad. Give the
hub's `claimed` ids to `EvdevHub` so that it skips them, as SDL's Linux
driver skips the devices HIDAPI runs.
"""
from extensions.gamepad.controller_type import (
    CONTROLLER_STEAM,
    CONTROLLER_STEAM_V2,
    CONTROLLER_SWITCH_INPUT_ONLY,
    CONTROLLER_SWITCH_PRO,
    USB_PRODUCT_NINTENDO_SWITCH_JOYCON_PAIR,
    USB_VENDOR_MICROSOFT,
    USB_VENDOR_NINTENDO,
    USB_VENDOR_SONY,
    gamepad_type_from_vidpid,
    guess_controller_type,
)
from extensions.gamepad.effects import (
    LedState,
    RumbleState,
    require_color,
    require_strength,
)
from extensions.gamepad.gamepad import Gamepad, GamepadEvent
from extensions.gamepad.guid import (
    JoystickGuid,
    ProductId,
    VendorId,
    joystick_guid_info,
)
from extensions.gamepad.hid import (
    HID_BUS_BLUETOOTH,
    HID_BUS_USB,
    HidDeviceInfo,
    HidSource,
    enumerate_hidraw,
)
from extensions.gamepad.hid_device import (
    HidapiDevice,
    USB_VENDOR_DRAGONRISE,
    USB_VENDOR_HORI,
    USB_VENDOR_PDP,
    USB_VENDOR_POWERA_ALT,
)
from extensions.gamepad.hid_ps4 import Ps4Driver
from extensions.gamepad.hid_ps5 import Ps5Driver
from extensions.gamepad.hid_switch import SwitchDriver
from extensions.gamepad.hid_xboxone import XboxOneDriver
from extensions.gamepad.ids import (
    GAMEPAD_TYPE_PS4,
    GAMEPAD_TYPE_STANDARD,
    GAMEPAD_TYPE_PS5,
    GAMEPAD_TYPE_XBOXONE,
    GamepadType,
)
from extensions.gamepad.joystick import Joystick, SensorType
from extensions.gamepad.linux import (
    DETECT_INTERVAL,
    DeviceChange,
    GAMEPAD_ADDED,
    GAMEPAD_REMOVED,
    folder_change_time,
)
from extensions.gamepad.mapping import MappingDatabase, PRIORITY_DEFAULT
from extensions.gamepad.names import should_ignore_joystick
from std.time import perf_counter_ns
from units.si import Duration64, SECOND

# HID usages that a gamepad's top-level collection has.
comptime USAGE_PAGE_GENERIC_DESKTOP = 0x0001
comptime USAGE_JOYSTICK = 0x0004
comptime USAGE_GAMEPAD = 0x0005
comptime USAGE_MULTIAXISCONTROLLER = 0x0008
comptime USB_VENDOR_VALVE = 0x28DE

# The Nintendo controller kinds a HIDAPI GUID keeps in its last byte.
# SDL: `ESwitchDeviceInfoControllerType` and `EWiiExtensionControllerType`.
comptime SWITCH_JOYCON_LEFT = 1
comptime SWITCH_JOYCON_RIGHT = 2
comptime SWITCH_HVC_LEFT = 7
comptime SWITCH_HVC_RIGHT = 8
comptime SWITCH_NES_LEFT = 9
comptime SWITCH_NES_RIGHT = 10
comptime SWITCH_SNES = 11
comptime SWITCH_N64 = 12
comptime SWITCH_SEGA_GENESIS = 13
comptime WII_EXTENSION_NONE = 128
comptime WII_EXTENSION_NUNCHUK = 129


@fieldwise_init
struct HidDriverKind(Equatable, ImplicitlyCopyable, Writable):
    """Which HIDAPI driver runs a device."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the 4 drivers, or none.

        Returns:
            Whether the value is -1 to 3.
        """
        return self.value >= -1 and self.value <= 3


comptime HID_DRIVER_NONE = HidDriverKind(-1)
comptime HID_DRIVER_PS4 = HidDriverKind(0)
comptime HID_DRIVER_PS5 = HidDriverKind(1)
comptime HID_DRIVER_SWITCH = HidDriverKind(2)
comptime HID_DRIVER_XBOXONE = HidDriverKind(3)


def driver_for(
    name: String,
    type: GamepadType,
    vendor: VendorId,
    product: ProductId,
    version: Int,
    interface_number: Int,
) -> HidDriverKind:
    """Return the first driver that may run a device, in SDL's order.

    Args:
        name: The device's name.
        type: Its gamepad type.
        vendor: The USB vendor id.
        product: The USB product id.
        version: The release number.
        interface_number: The USB interface, or -1.

    Returns:
        The driver, or `HID_DRIVER_NONE`.
    """
    if Ps4Driver.is_supported(
        name, type, vendor, product, version, interface_number
    ):
        return HID_DRIVER_PS4
    if Ps5Driver.is_supported(
        name, type, vendor, product, version, interface_number
    ):
        return HID_DRIVER_PS5
    if SwitchDriver.is_supported(
        name, type, vendor, product, version, interface_number
    ):
        return HID_DRIVER_SWITCH
    if XboxOneDriver.is_supported(
        name, type, vendor, product, version, interface_number
    ):
        return HID_DRIVER_XBOXONE
    return HID_DRIVER_NONE


def device_driver(device: HidapiDevice) -> HidDriverKind:
    """Return the driver that may run a device. SDL:
    `HIDAPI_GetDeviceDriver`, before the device is open.

    Args:
        device: The device.

    Returns:
        The driver, or `HID_DRIVER_NONE` for a device that is ignored,
        is not a game controller, or that no driver knows.
    """
    if should_ignore_joystick(
        device.vendor, device.product, device.version, device.name
    ):
        return HID_DRIVER_NONE
    if device.vendor.value != USB_VENDOR_VALVE:
        if (
            device.usage_page != 0
            and device.usage_page != USAGE_PAGE_GENERIC_DESKTOP
        ):
            return HID_DRIVER_NONE
        if (
            device.usage != 0
            and device.usage != USAGE_JOYSTICK
            and device.usage != USAGE_GAMEPAD
            and device.usage != USAGE_MULTIAXISCONTROLLER
        ):
            return HID_DRIVER_NONE
    return driver_for(
        device.name,
        device.type,
        device.vendor,
        device.product,
        device.version,
        device.interface_number,
    )


def _driver_with_device[
    S: HidSource
](device: HidapiDevice, mut source: S) -> HidDriverKind:
    """Return the driver that runs an open device. SDL:
    `HIDAPI_GetDeviceDriver`, with the device open.

    Parameters:
        S: The kind of HID device.

    Args:
        device: The device.
        source: The open device, which a driver may ask who it is.

    Returns:
        The first driver in SDL's order that takes the device, or
        `HID_DRIVER_NONE`.
    """
    var first = device_driver(device)
    if first == HID_DRIVER_PS4 and Ps4Driver.is_supported_device(
        source, device
    ):
        return HID_DRIVER_PS4
    # The PS4 driver takes every pad that the PS5 driver may probe, so a
    # pad it turns down is the PS5 driver's to ask next.
    if first == HID_DRIVER_PS4 or first == HID_DRIVER_PS5:
        if Ps5Driver.is_supported_device(source, device):
            return HID_DRIVER_PS5
        return HID_DRIVER_NONE
    return first


def is_device_supported(
    vendor: VendorId, product: ProductId, version: Int, name: String
) -> Bool:
    """Return True if a HIDAPI driver may run a device. SDL:
    `HIDAPI_IsDeviceSupported`.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.
        version: The release number.
        name: The device's name.

    Returns:
        Whether some driver may run it.
    """
    var type = game_controller_type(name, vendor, product)
    return driver_for(name, type, vendor, product, version, -1) != (
        HID_DRIVER_NONE
    )


def game_controller_type(
    name: String, vendor: VendorId, product: ProductId
) -> GamepadType:
    """Return the type of a device with no USB interface.

    Args:
        name: The device's name.
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        The type.
    """
    from extensions.gamepad.hid_device import game_controller_protocol

    return game_controller_protocol(name, vendor, product, -1, 0, 0, 0)


def _is_xbox_one_elite(vendor: Int, product: Int) -> Bool:
    """Return True for an Xbox Elite controller. SDL:
    `SDL_IsJoystickXboxOneElite`.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        Whether it is one.
    """
    return vendor == USB_VENDOR_MICROSOFT.value and (
        product == 0x02E3
        or product == 0x0B00
        or product == 0x0B05
        or product == 0x0B22
    )


def _is_xbox_series_x(vendor: Int, product: Int) -> Bool:
    """Return True for an Xbox Series controller. SDL:
    `SDL_IsJoystickXboxSeriesX`.

    Args:
        vendor: The USB vendor id.
        product: The USB product id.

    Returns:
        Whether it is one.
    """
    if vendor == USB_VENDOR_MICROSOFT.value:
        return product == 0x0B12 or product == 0x0B13
    if vendor == USB_VENDOR_PDP:
        return product == 0x02D6 or product == 0x02D9 or product == 0x02DA
    if vendor == USB_VENDOR_POWERA_ALT:
        return (
            (product >= 0x2001 and product <= 0x201A)
            or product == 0x4001
            or product == 0x400B
            or product == 0x4014
            or product == 0x4016
            or product == 0x890B
            or product == 0x4002
        )
    if vendor == USB_VENDOR_HORI:
        return product == 0x01F7 or product == 0x01F6 or product == 0x02D6
    if vendor == 0x0B05:  # ASUS
        return product == 0x1A38
    if vendor == 0x2E24:  # Hyperkin
        return product == 0x0652
    if vendor == 0x03F0:  # HP
        return product == 0x08B6 or product == 0x07A0
    if vendor == 0x044F:  # Thrustmaster
        return product == 0xD012
    if vendor == 0x2DC8:  # 8BitDo
        return product == 0x2002 or product == 0x200F
    if vendor == 0x1532:  # Razer
        return product == 0x0A29 or product == 0x0A2A or product == 0x0A2B
    return False


def create_mapping_for_hidapi_gamepad(
    guid: JoystickGuid, type: GamepadType
) -> String:
    """Return the mapping SDL makes for a HIDAPI device that has none.
    SDL: `SDL_CreateMappingForHIDAPIGamepad`, with Joy-Cons in their
    default, mini gamepad mode.

    Args:
        guid: The device's GUID.
        type: The device's gamepad type, from its driver.

    Returns:
        The whole mapping, with `none` for the GUID and `*` for the name.
    """
    var info = joystick_guid_info(guid)
    var vendor = info.vendor.value
    var product = info.product.value
    var kind = Int(guid.data[15])
    var mapping = String("none,*,")
    if (vendor == USB_VENDOR_NINTENDO.value and product == 0x0337) or (
        vendor == USB_VENDOR_DRAGONRISE
        and (product == 0x1843 or product == 0x1846)
    ):
        return (
            mapping
            + "a:b0,b:b1,dpdown:b6,dpleft:b4,dpright:b5,dpup:b7,"
            "lefttrigger:a4,leftx:a0,lefty:a1~,rightshoulder:b9,"
            "righttrigger:a5,rightx:a2,righty:a3~,start:b8,x:b2,y:b3,"
        )
    var hat = "dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,"
    if vendor == USB_VENDOR_NINTENDO.value:
        if (
            kind == SWITCH_HVC_LEFT
            or kind == SWITCH_NES_LEFT
            or (kind == SWITCH_NES_RIGHT)
        ):
            return mapping + (
                "a:b0,b:b1,back:b4,"
                + hat
                + "leftshoulder:b9,rightshoulder:b10,start:b6,"
            )
        if kind == SWITCH_HVC_RIGHT:
            return mapping + (
                "a:b0,b:b1," + hat + "leftshoulder:b9,rightshoulder:b10,"
            )
        if kind == SWITCH_SNES:
            return mapping + (
                "a:b0,b:b1,back:b4,"
                + hat
                + "leftshoulder:b9,lefttrigger:a4,rightshoulder:b10,"
                "righttrigger:a5,start:b6,x:b2,y:b3,"
                "hint:!SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,"
            )
        if kind == SWITCH_N64:
            return mapping + (
                "a:b0,b:b1,back:b4,"
                + hat
                + "guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,"
                "leftx:a0,lefty:a1,rightshoulder:b10,righttrigger:a5,"
                "start:b6,x:b2,y:b3,misc1:b11,"
            )
        if kind == SWITCH_SEGA_GENESIS:
            return mapping + (
                "a:b0,b:b1,"
                + hat
                + "guide:b5,leftshoulder:b9,rightshoulder:b10,"
                "righttrigger:a5,start:b6,x:b2,y:b3,misc1:b11,"
            )
        if kind == WII_EXTENSION_NONE:
            return mapping + (
                "a:b0,b:b1,back:b4," + hat + "guide:b5,start:b6,x:b2,y:b3,"
            )
        if kind == WII_EXTENSION_NUNCHUK:
            return (
                mapping
                + "a:b0,b:b1,back:b4,dpdown:b12,dpleft:b13,dpright:b14,"
                "dpup:b11,guide:b5,leftshoulder:b9,lefttrigger:a4,"
                "leftx:a0,lefty:a1,start:b6,x:b2,y:b3,"
            )
        var joycon = (
            "a:b0,b:b1,guide:b5,leftshoulder:b9,leftstick:b7,leftx:a0,"
            "lefty:a1,rightshoulder:b10,start:b6,x:b2,y:b3,"
        )
        if kind == SWITCH_JOYCON_LEFT:
            return mapping + joycon + "paddle2:b13,paddle4:b15,"
        if kind == SWITCH_JOYCON_RIGHT:
            return mapping + joycon + "paddle1:b12,paddle3:b14,"
    mapping += (
        "a:b0,b:b1,back:b4,"
        + hat
        + "guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,"
        "lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,"
        "rightx:a2,righty:a3,start:b6,x:b2,y:b3,"
    )
    var model = guess_controller_type(info.vendor, info.product)
    if model == CONTROLLER_STEAM or model == CONTROLLER_STEAM_V2:
        return mapping + "paddle1:b12,paddle2:b11,"
    if model == CONTROLLER_SWITCH_PRO or model == CONTROLLER_SWITCH_INPUT_ONLY:
        return mapping + "misc1:b11,"
    if (
        vendor == USB_VENDOR_NINTENDO.value
        and product == USB_PRODUCT_NINTENDO_SWITCH_JOYCON_PAIR.value
    ):
        return (
            mapping
            + "misc1:b11,paddle1:b12,paddle2:b13,paddle3:b14,paddle4:b15,"
        )
    if (vendor == 0x1949 and product == 0x0419) or (
        vendor == 0x0171 and product == 0x0419
    ):
        # Amazon Luna: a microphone button under the guide button.
        return mapping + "misc1:b11,"
    if vendor == 0x18D1 and product == 0x9400:
        # Google Stadia: a share button and an Assistant button.
        return mapping + "misc1:b11,misc2:b12"
    if vendor == 0x0955 and (product == 0x7210 or product == 0x7214):
        # NVIDIA SHIELD: a share button; the first model a touchpad and
        # two more buttons.
        mapping += "misc1:b11,"
        if product == 0x7210:
            mapping += "touchpad:b12,misc2:b13,misc3:b14"
        return mapping
    if vendor == USB_VENDOR_HORI and (product == 0x01AB or product == 0x0196):
        return (
            mapping
            + "paddle1:b13,paddle2:b12,paddle3:b15,paddle4:b14,misc2:b11,"
            "misc3:b16,misc4:b17"
        )
    if type == GAMEPAD_TYPE_PS4:
        return mapping + "touchpad:b11,"
    if type == GAMEPAD_TYPE_PS5:
        mapping += "touchpad:b11,misc1:b12,"
        if vendor == USB_VENDOR_SONY.value and product == 0x0DF2:
            mapping += "paddle1:b16,paddle2:b15,paddle3:b14,paddle4:b13,"
        return mapping
    if type == GAMEPAD_TYPE_XBOXONE:
        if _is_xbox_one_elite(vendor, product):
            return mapping + "paddle1:b11,paddle2:b13,paddle3:b12,paddle4:b14,"
        if _is_xbox_series_x(vendor, product):
            return mapping + "misc1:b11,"
        return mapping
    if vendor == 0 and product == 0:
        # A Bluetooth Switch Pro controller.
        return mapping + "misc1:b11,"
    return mapping


struct HidGamepad[S: HidSource](Movable):
    """A HID device run by a HIDAPI driver. SDL: an `SDL_HIDAPI_Device`
    with its driver, and the `SDL_Gamepad` opened on its joystick."""

    var device: HidapiDevice
    var source: Self.S
    var driver: HidDriverKind
    var ps4: Ps4Driver
    var ps5: Ps5Driver
    var switch_pro: SwitchDriver
    var xbox_one: XboxOneDriver
    # The open gamepad, once the driver connects a joystick.
    var pad: Optional[Gamepad]
    var player_index: Int
    var rumble_state: RumbleState
    var trigger_rumble_state: RumbleState
    var led: LedState
    # Whether the device stopped answering.
    var gone: Bool
    var epoch: Int

    def __init__(
        out self,
        info: HidDeviceInfo,
        var source: Self.S,
        now: Duration64,
        player_index: Int = 0,
    ) raises:
        """Start a driver on an open device. SDL: `HIDAPI_AddDevice` and
        `HIDAPI_SetupDeviceDriver`.

        Args:
            info: What enumeration learned about the device.
            source: The open device.
            now: The time now.
            player_index: The player number the pad shows, from 0.

        Raises:
            Error: If no driver runs the device, or the driver cannot
                start.
        """
        self.device = HidapiDevice(info)
        self.source = source^
        self.ps4 = Ps4Driver()
        self.ps5 = Ps5Driver()
        self.switch_pro = SwitchDriver()
        self.xbox_one = XboxOneDriver()
        self.pad = None
        self.player_index = player_index
        self.rumble_state = RumbleState()
        self.trigger_rumble_state = RumbleState()
        self.led = LedState()
        self.gone = False
        self.epoch = Int(perf_counter_ns())
        self.driver = _driver_with_device(self.device, self.source)
        if self.driver == HID_DRIVER_NONE:
            raise Error("No HIDAPI driver runs " + self.device.name)
        var connected = self.device.joysticks
        var started: Bool
        if self.driver == HID_DRIVER_PS4:
            started = self.ps4.init_device(self.device, self.source, now)
        elif self.driver == HID_DRIVER_PS5:
            started = self.ps5.init_device(self.device, self.source, now)
        elif self.driver == HID_DRIVER_SWITCH:
            started = self.switch_pro.init_device(self.device, self.source, now)
        else:
            started = self.xbox_one.init_device(self.device, self.source, now)
        if not started:
            raise Error("The HIDAPI driver cannot start " + self.device.name)
        self._joined(connected)

    def now(self) -> Duration64:
        """Return the time since the device opened.

        Returns:
            The time, by the monotonic clock.
        """
        return Duration64(
            Float64(Int(perf_counter_ns()) - self.epoch) * 1e-9, SECOND
        )

    def _joined(mut self, before: Int):
        """Give a newly connected joystick its player number. SDL:
        `SDL_PrivateJoystickAdded`, which calls `SetDevicePlayerIndex`.

        Args:
            before: How many joysticks were connected before the driver
                call.
        """
        if before == 0 and self.device.joysticks > 0:
            self.set_player_index(self.player_index)

    def set_player_index(mut self, player_index: Int):
        """Show a player number on the pad's lights. SDL:
        `SetDevicePlayerIndex`.

        Args:
            player_index: The player, from 0, or -1 for none.
        """
        self.player_index = player_index
        if self.driver == HID_DRIVER_PS4:
            self.ps4.set_player_index(self.device, self.source, player_index)
        elif self.driver == HID_DRIVER_PS5:
            self.ps5.set_player_index(self.device, self.source, player_index)
        elif self.driver == HID_DRIVER_SWITCH:
            self.switch_pro.set_player_index(
                self.device, self.source, player_index
            )
        else:
            self.xbox_one.set_player_index(
                self.device, self.source, player_index
            )

    def _update_device(mut self, now: Duration64) -> Bool:
        """Let the driver read the device. SDL: `UpdateDevice`.

        Args:
            now: The time now.

        Returns:
            False when the device went away.
        """
        var before = self.device.joysticks
        var alive: Bool
        if self.driver == HID_DRIVER_PS4:
            alive = self.ps4.update_device(
                self.device, self.source, self.pad, now
            )
        elif self.driver == HID_DRIVER_PS5:
            alive = self.ps5.update_device(
                self.device, self.source, self.pad, now
            )
        elif self.driver == HID_DRIVER_SWITCH:
            alive = self.switch_pro.update_device(
                self.device, self.source, self.pad, now
            )
        else:
            alive = self.xbox_one.update_device(
                self.device, self.source, self.pad, now
            )
        self._joined(before)
        if self.device.joysticks == 0 and self.pad:
            self._close()
        return alive

    def close(mut self):
        """Close the gamepad, if it is open. SDL: `SDL_CloseGamepad`."""
        if self.pad:
            self._close()

    def gamepad_type(self) -> GamepadType:
        """Return the kind of gamepad, for its labels. SDL:
        `SDL_GetGamepadTypeFromGUID`.

        Returns:
            The type the ids name, else the type the driver found.
        """
        var type = gamepad_type_from_vidpid(
            self.device.vendor, self.device.product, self.device.name, True
        )
        if type == GAMEPAD_TYPE_STANDARD:
            return self.device.type
        return type

    def _close(mut self):
        """Close the gamepad. SDL: `HIDAPI_JoystickClose`."""
        if self.driver == HID_DRIVER_PS4:
            self.ps4.close_joystick(self.device, self.source)
        elif self.driver == HID_DRIVER_PS5:
            self.ps5.close_joystick(self.device, self.source)
        elif self.driver == HID_DRIVER_SWITCH:
            self.switch_pro.close_joystick(self.device, self.source)
        else:
            self.xbox_one.close_joystick(self.device, self.source)
        self.pad = None

    def connected(self) -> Bool:
        """Return True if the driver connected a joystick.

        Returns:
            Whether a gamepad can be opened, or is open.
        """
        return self.device.joysticks > 0

    def open_at(
        mut self, mut database: MappingDatabase, now: Duration64
    ) raises:
        """Open the gamepad. SDL: `HIDAPI_JoystickOpen` and
        `SDL_OpenGamepad`.

        Args:
            database: The mappings. One is made for a device that has
                none.
            now: The time now.

        Raises:
            Error: If the device went away, or the driver cannot open it.
        """
        # SDL ignores the result: the driver disconnects a pad that went
        # away.
        _ = self._update_device(now)
        if self.device.joysticks == 0:
            raise Error("The HIDAPI device disconnected while opening")
        var joystick: Joystick
        if self.driver == HID_DRIVER_PS4:
            joystick = self.ps4.open_joystick(self.device, self.source, now)
        elif self.driver == HID_DRIVER_PS5:
            joystick = self.ps5.open_joystick(self.device, self.source, now)
        elif self.driver == HID_DRIVER_SWITCH:
            joystick = self.switch_pro.open_joystick(
                self.device, self.source, now
            )
        else:
            joystick = self.xbox_one.open_joystick(
                self.device, self.source, now
            )
        var index = database.mapping_for_name_and_guid(
            self.device.name, self.device.guid
        )
        if index < 0:
            index = database.add_generated_mapping(
                self.device.guid,
                create_mapping_for_hidapi_gamepad(
                    self.device.guid, self.device.type
                ),
            )
        self.pad = Gamepad(joystick^, database.mappings[index])

    def open(mut self, mut database: MappingDatabase) raises:
        """Open the gamepad now.

        Args:
            database: The mappings.

        Raises:
            Error: If the device went away, or the driver cannot open it.
        """
        self.open_at(database, self.now())

    def capabilities(self) -> Int:
        """Return what the pad can do. SDL: `GetJoystickCapabilities`.

        Returns:
            The `CAP_*` bits.
        """
        if self.driver == HID_DRIVER_PS4:
            return self.ps4.capabilities(self.device)
        if self.driver == HID_DRIVER_PS5:
            return self.ps5.capabilities(self.device)
        if self.driver == HID_DRIVER_SWITCH:
            return self.switch_pro.capabilities(self.device)
        return self.xbox_one.capabilities(self.device)

    def _driver_rumble(mut self, low: Int, high: Int) -> Bool:
        """Send rumble to the driver. SDL: `RumbleJoystick`.

        Args:
            low: The low frequency strength.
            high: The high frequency strength.

        Returns:
            Whether the pad took it.
        """
        if self.driver == HID_DRIVER_PS4:
            return self.ps4.rumble(self.device, self.source, low, high)
        if self.driver == HID_DRIVER_PS5:
            return self.ps5.rumble(self.device, self.source, low, high)
        if self.driver == HID_DRIVER_SWITCH:
            return self.switch_pro.rumble(self.device, self.source, low, high)
        return self.xbox_one.rumble(self.device, self.source, low, high)

    def _driver_rumble_triggers(mut self, left: Int, right: Int) -> Bool:
        """Send trigger rumble to the driver. SDL: `RumbleJoystickTriggers`.

        Args:
            left: The left trigger's strength.
            right: The right trigger's strength.

        Returns:
            Whether the pad took it.
        """
        if self.driver == HID_DRIVER_PS4:
            return self.ps4.rumble_triggers(
                self.device, self.source, left, right
            )
        if self.driver == HID_DRIVER_PS5:
            return self.ps5.rumble_triggers(
                self.device, self.source, left, right
            )
        if self.driver == HID_DRIVER_SWITCH:
            return self.switch_pro.rumble_triggers(
                self.device, self.source, left, right
            )
        return self.xbox_one.rumble_triggers(
            self.device, self.source, left, right
        )

    def rumble_at(
        mut self, low: Int, high: Int, duration: Duration64, now: Duration64
    ) raises -> Bool:
        """Rumble the pad. SDL: `SDL_RumbleGamepad`.

        Args:
            low: The low frequency strength, 0 to 65535.
            high: The high frequency strength, 0 to 65535.
            duration: How long. Zero rumbles until changed.
            now: The time now.

        Returns:
            Whether the pad rumbles.

        Raises:
            Error: If a strength does not fit 16 bits.
        """
        require_strength(low)
        require_strength(high)
        return self._rumble(low, high, duration, now)

    def _rumble(
        mut self, low: Int, high: Int, duration: Duration64, now: Duration64
    ) -> Bool:
        """Rumble with strengths that fit 16 bits.

        Args:
            low: The low frequency strength.
            high: The high frequency strength.
            duration: How long.
            now: The time now.

        Returns:
            Whether the pad rumbles.
        """
        var sent = self.rumble_state.needs_send(low, high)
        var succeeded = sent and self._driver_rumble(low, high)
        return self.rumble_state.commit(
            sent, succeeded, low, high, duration, now
        )

    def rumble(
        mut self, low: Int, high: Int, duration: Duration64
    ) raises -> Bool:
        """Rumble the pad now. SDL: `SDL_RumbleGamepad`.

        Args:
            low: The low frequency strength, 0 to 65535.
            high: The high frequency strength, 0 to 65535.
            duration: How long. Zero rumbles until changed.

        Returns:
            Whether the pad rumbles.

        Raises:
            Error: If a strength does not fit 16 bits.
        """
        return self.rumble_at(low, high, duration, self.now())

    def rumble_triggers_at(
        mut self, left: Int, right: Int, duration: Duration64, now: Duration64
    ) raises -> Bool:
        """Rumble the triggers. SDL: `SDL_RumbleGamepadTriggers`.

        Args:
            left: The left trigger's strength, 0 to 65535.
            right: The right trigger's strength, 0 to 65535.
            duration: How long. Zero rumbles until changed.
            now: The time now.

        Returns:
            Whether the triggers rumble.

        Raises:
            Error: If a strength does not fit 16 bits.
        """
        require_strength(left)
        require_strength(right)
        return self._rumble_triggers(left, right, duration, now)

    def _rumble_triggers(
        mut self, left: Int, right: Int, duration: Duration64, now: Duration64
    ) -> Bool:
        """Rumble the triggers with strengths that fit 16 bits.

        Args:
            left: The left trigger's strength.
            right: The right trigger's strength.
            duration: How long.
            now: The time now.

        Returns:
            Whether the triggers rumble.
        """
        var sent = self.trigger_rumble_state.needs_send(left, right)
        var succeeded = sent and self._driver_rumble_triggers(left, right)
        return self.trigger_rumble_state.commit(
            sent, succeeded, left, right, duration, now
        )

    def set_led_at(
        mut self, red: Int, green: Int, blue: Int, now: Duration64
    ) raises -> Bool:
        """Set the pad's light. SDL: `SDL_SetGamepadLED`.

        Args:
            red: The red level, 0 to 255.
            green: The green level.
            blue: The blue level.
            now: The time now.

        Returns:
            Whether the pad took the color. One that need not be sent
            again counts as taken.

        Raises:
            Error: If a level does not fit a byte.
        """
        require_color(red, green, blue)
        var sent = self.led.needs_send(red, green, blue, now)
        var result = True
        if sent:
            if self.driver == HID_DRIVER_PS4:
                result = self.ps4.set_led(
                    self.device, self.source, red, green, blue
                )
            elif self.driver == HID_DRIVER_PS5:
                result = self.ps5.set_led(
                    self.device, self.source, red, green, blue
                )
            elif self.driver == HID_DRIVER_SWITCH:
                result = self.switch_pro.set_led(
                    self.device, self.source, red, green, blue
                )
            else:
                result = self.xbox_one.set_led(
                    self.device, self.source, red, green, blue
                )
        self.led.commit(sent, red, green, blue, now)
        return result

    def set_sensor_enabled(
        mut self, type: SensorType, enabled: Bool
    ) raises -> Bool:
        """Turn a motion sensor on or off. SDL:
        `SDL_SetGamepadSensorEnabled`.

        Args:
            type: The sensor type.
            enabled: Whether it reports.

        Returns:
            Whether the change took effect.

        Raises:
            Error: If the gamepad is not open or has no sensor of the
                type.
        """
        if not self.pad:
            raise Error("The gamepad is not open")
        var change = self.pad.value().joystick.sensor_switch(type, enabled)
        if change != 0:
            var on = change > 0
            var done: Bool
            if self.driver == HID_DRIVER_PS4:
                done = self.ps4.set_sensors_enabled(
                    self.device, self.source, self.pad.value().joystick, on
                )
            elif self.driver == HID_DRIVER_PS5:
                done = self.ps5.set_sensors_enabled(
                    self.device, self.source, self.pad.value().joystick, on
                )
            elif self.driver == HID_DRIVER_SWITCH:
                done = self.switch_pro.set_sensors_enabled(
                    self.device, self.source, self.pad.value().joystick, on
                )
            else:
                done = self.xbox_one.set_sensors_enabled(
                    self.device, self.source, self.pad.value().joystick, on
                )
            if not done:
                return False
        self.pad.value().joystick.set_sensor_enabled(type, enabled)
        return True

    def update_at(mut self, now: Duration64) -> List[GamepadEvent]:
        """Read the device and return the gamepad's events. SDL:
        `HIDAPI_UpdateDevices`, the rumble timers of
        `SDL_UpdateJoysticks` and the gamepad event watcher.

        Args:
            now: The time now.

        Returns:
            The gamepad events since the last call, or none while no
            gamepad is open.
        """
        if not self._update_device(now):
            self.gone = True
        if not self.pad:
            return List[GamepadEvent]()
        if self.rumble_state.expired(now):
            _ = self._rumble(0, 0, Duration64(0), now)
            self.rumble_state.resend = None
        if self.rumble_state.resend_due(now):
            _ = self._driver_rumble(
                self.rumble_state.first, self.rumble_state.second
            )
            self.rumble_state.resent(now)
        if self.trigger_rumble_state.expired(now):
            _ = self._rumble_triggers(0, 0, Duration64(0), now)
            self.trigger_rumble_state.resend = None
        if self.trigger_rumble_state.resend_due(now):
            _ = self._driver_rumble_triggers(
                self.trigger_rumble_state.first,
                self.trigger_rumble_state.second,
            )
            self.trigger_rumble_state.resent(now)
        return self.pad.value().update()

    def update(mut self) -> List[GamepadEvent]:
        """Read the device and return the gamepad's events, now.

        Returns:
            The gamepad events since the last call.
        """
        return self.update_at(self.now())


struct HidHub[S: HidSource](Movable):
    """The HID gamepads, as they come and go. SDL: the device list of
    SDL's HIDAPI joystick driver."""

    var pads: List[HidGamepad[Self.S]]
    var class_dir: String
    var dev_dir: String
    var last_check: Optional[Duration64]
    var last_change: Optional[Int]
    var epoch: Int

    def __init__(
        out self,
        class_dir: String = "/sys/class/hidraw",
        dev_dir: String = "/dev",
    ):
        """Create a hub with no devices. The first `detect` scans.

        Args:
            class_dir: The hidraw class folder.
            dev_dir: The device folder.
        """
        self.pads = List[HidGamepad[Self.S]]()
        self.class_dir = class_dir
        self.dev_dir = dev_dir
        self.last_check = None
        self.last_change = None
        self.epoch = Int(perf_counter_ns())

    def now(self) -> Duration64:
        """Return the time since the hub was created.

        Returns:
            The time, by the monotonic clock.
        """
        return Duration64(
            Float64(Int(perf_counter_ns()) - self.epoch) * 1e-9, SECOND
        )

    def claimed(self) -> List[Int]:
        """Return the devices the hub runs, as `vendor << 16 | product`.

        Returns:
            One entry for each device with a driver. SDL's Linux driver
            skips these: `HIDAPI_IsDevicePresent`.
        """
        var ids = List[Int]()
        for index in range(len(self.pads)):
            var device = self.pads[index].device.copy()
            ids.append((device.vendor.value << 16) | device.product.value)
        return ids^

    def _free_player_index(self) -> Int:
        """Return the smallest player number no pad shows. SDL:
        `SDL_FindFreePlayerIndex`.

        Returns:
            The player number.
        """
        var index = 0
        while True:
            var used = False
            for at in range(len(self.pads)):
                if self.pads[at].player_index == index:
                    used = True
            if not used:
                return index
            index += 1

    def _settle(
        mut self,
        mut database: MappingDatabase,
        now: Duration64,
        mut changes: List[DeviceChange],
    ):
        """Drop the devices that went away, and open the gamepads that
        connected.

        Args:
            database: The mappings.
            now: The time now.
            changes: The list the changes go on.
        """
        # A pad on USB disconnects its own Bluetooth link.
        for at in range(len(self.pads)):
            var serial = self.pads[at].device.disconnect_bluetooth
            if serial.byte_length() == 0:
                continue
            self.pads[at].device.disconnect_bluetooth = ""
            for other in range(len(self.pads)):  # pragma: no branch
                if (
                    self.pads[other].device.is_bluetooth
                    and self.pads[other].device.serial == serial
                    and self.pads[other].connected()
                ):
                    self.pads[other].device.joystick_disconnected()
                    self.pads[other].gone = True
        var index = 0
        while index < len(self.pads):
            if not self.pads[index].gone:
                index += 1
                continue
            var pad = self.pads.pop(index)
            if pad.pad:
                changes.append(
                    DeviceChange(
                        GAMEPAD_REMOVED, pad.device.path, pad.device.name
                    )
                )
        var serials = List[String]()
        for at in range(len(self.pads)):
            if not self.pads[at].device.is_bluetooth:
                serials.append(self.pads[at].device.serial)
        for at in range(len(self.pads)):
            self.pads[at].device.usb_serials = serials.copy()
            if self.pads[at].connected() and not self.pads[at].pad:
                try:
                    self.pads[at].open_at(database, now)
                    changes.append(
                        DeviceChange(
                            GAMEPAD_ADDED,
                            self.pads[at].device.path,
                            self.pads[at].device.name,
                        )
                    )
                except:
                    pass

    def detect_with(
        mut self,
        mut database: MappingDatabase,
        found: List[HidDeviceInfo],
        now: Duration64,
    ) -> List[DeviceChange]:
        """Add new devices, drop missing ones, and open the gamepads that
        connected. SDL: `HIDAPI_UpdateDeviceList` and the joystick added
        and removed events.

        Args:
            database: The mappings.
            found: The devices enumeration found.
            now: The time now.

        Returns:
            The gamepads added and those removed.
        """
        var changes = List[DeviceChange]()
        for at in range(len(self.pads)):
            var seen = False
            for info in found:
                if info.path == self.pads[at].device.path:
                    seen = True
            if not seen:
                self.pads[at].gone = True
        for info in found:
            var known = False
            for at in range(len(self.pads)):
                if self.pads[at].device.path == info.path:
                    known = True
            if known:
                continue
            try:
                if device_driver(HidapiDevice(info)) == HID_DRIVER_NONE:
                    continue
                var source = Self.S.open(info.path)
                self.pads.append(
                    HidGamepad[Self.S](
                        info, source^, now, self._free_player_index()
                    )
                )
            except:
                continue
        self._settle(database, now, changes)
        return changes^

    def detect_at(
        mut self, mut database: MappingDatabase, now: Duration64
    ) -> List[DeviceChange]:
        """Scan the hidraw nodes when the device folder changed, at most
        every 3 seconds, and open the gamepads that connected.

        Args:
            database: The mappings.
            now: The time now.

        Returns:
            The gamepads added and those removed.
        """
        var rescan = False
        for at in range(len(self.pads)):
            if self.pads[at].device.rescan:
                self.pads[at].device.rescan = False
                rescan = True
        if (
            rescan
            or not self.last_check
            or not (now < self.last_check.value() + DETECT_INTERVAL)
        ):
            self.last_check = now
            var change = folder_change_time(self.dev_dir)
            if (
                rescan
                or not change
                or not self.last_change
                or change.value() != self.last_change.value()
            ):
                self.last_change = change
                return self.detect_with(
                    database,
                    enumerate_hidraw(self.class_dir, self.dev_dir),
                    now,
                )
        var changes = List[DeviceChange]()
        self._settle(database, now, changes)
        return changes^

    def detect(mut self, mut database: MappingDatabase) -> List[DeviceChange]:
        """Scan for gamepads now.

        Args:
            database: The mappings.

        Returns:
            The gamepads added and those removed.
        """
        return self.detect_at(database, self.now())
