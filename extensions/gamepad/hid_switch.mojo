# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Nintendo Switch Pro driver. SDL: `SDL_hidapi_switch.c`. Not ported yet."""
from extensions.gamepad.gamepad import Gamepad
from extensions.gamepad.guid import ProductId, VendorId
from extensions.gamepad.hid import HidSource
from extensions.gamepad.hid_device import HidapiDevice
from extensions.gamepad.ids import GamepadType
from extensions.gamepad.joystick import Joystick
from units.si import Duration64


struct SwitchDriver(Movable):
    """The Nintendo Switch Pro driver's state. SDL: `SDL_DriverSwitch_Context`.
    """

    def __init__(out self):
        """Create the state of a device the driver has not seen."""
        pass

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
        return False

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
            Whether the driver runs it.
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
            Whether the driver runs the device.
        """
        return False

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
        pass

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
        return False

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
        raise Error("The Nintendo Switch Pro driver is not ported")

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
        return False

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
            Whether the pad took it.
        """
        return False

    def capabilities(self, device: HidapiDevice) -> Int:
        """Return what the pad can do. SDL: `GetJoystickCapabilities`.

        Args:
            device: The device.

        Returns:
            The `CAP_*` bits.
        """
        return 0

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
            Whether the pad took it.
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
        return False

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
        pass
