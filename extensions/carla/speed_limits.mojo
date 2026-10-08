# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Checked OpenDRIVE speed records and explicit simulation conversions.

ASAM OpenDRIVE 1.8.1 uses m/s when a road or lane speed omits its unit.
The other speed units are km/h and mph. A signal's numeric speed needs an
explicit unit. Raw record values remain in their source unit. The runtime
adapter returns Velocity64; narrowing to Float32 simulation is separate.
Road keywords, missing road limits and a numeric zero are distinct states.
"""

from std.math import isfinite
from units.si import Velocity, Velocity64


@fieldwise_init
struct SpeedLimitKind(Equatable, ImplicitlyCopyable, Writable):
    """Whether a road speed is numeric, unrestricted, undefined or absent."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this value names one of the four speed states.

        Returns:
            True for a numeric, unrestricted, undefined or absent speed state.
        """
        return self.value >= 0 and self.value <= 3


comptime NUMERIC_SPEED_LIMIT = SpeedLimitKind(0)
comptime NO_SPEED_LIMIT = SpeedLimitKind(1)
comptime UNDEFINED_SPEED_LIMIT = SpeedLimitKind(2)
comptime UNSPECIFIED_SPEED_LIMIT = SpeedLimitKind(3)


def opendrive_speed(
    value: Float64, unit: String, allow_default_si: Bool = False
) raises -> Velocity64:
    """Convert a raw OpenDRIVE speed to a checked runtime quantity.

    Args:
        value: The finite nonnegative number in the source unit.
        unit: Exactly m/s, km/h or mph; an empty unit is not guessed.
        allow_default_si: Whether an omitted road or lane unit means m/s.

    Returns:
        The speed in meters per second, with Float64 arithmetic.

    Raises:
        Error: If the number or unit is invalid, or conversion underflows.
    """
    if not isfinite(value) or value < 0:
        raise Error("OpenDRIVE speed must be finite and nonnegative")
    var speed: Float64
    if unit == "m/s":
        speed = value
    elif unit == "km/h":
        speed = value / Float64(3.6)
    elif unit == "mph":
        speed = value * Float64(0.44704)
    elif unit == "" and allow_default_si:
        speed = value
    else:
        raise Error("OpenDRIVE speed needs a supported unit: m/s, km/h or mph")
    if value != 0 and speed == 0:
        raise Error("OpenDRIVE speed conversion is outside Float64 range")
    return Velocity64(speed)


def simulation_speed(speed: Velocity64) raises -> Velocity:
    """Narrow a validated road speed explicitly for Float32 simulation.

    Args:
        speed: The finite nonnegative physical speed.

    Returns:
        The same speed in the simulation's existing Float32 representation.

    Raises:
        Error: If the speed is invalid, overflows, or underflows to zero.
    """
    if not isfinite(speed.value) or speed.value < 0:
        raise Error("Simulation speed must be finite and nonnegative")
    var value = Float32(speed.value)
    if not isfinite(value) or (speed.value != 0 and value == 0):
        raise Error("Simulation speed is outside Float32 range")
    return Velocity(value)


def _speed_decimal_syntax(number: String) -> Bool:
    """Check the complete finite XML decimal grammar, without conversion."""
    var mantissa_digits = 0
    var exponent_digits = 0
    var exponent = False
    var point = False
    var sign_allowed = True
    for byte in number.as_bytes():
        if byte >= 48 and byte <= 57:
            if exponent:
                exponent_digits += 1
            else:
                mantissa_digits += 1
            sign_allowed = False
        elif byte == 43 or byte == 45:
            if not sign_allowed:
                return False
            sign_allowed = False
        elif byte == 46:
            if exponent or point:
                return False
            point = True
            sign_allowed = False
        elif byte == 69 or byte == 101:
            if exponent or mantissa_digits == 0:
                return False
            exponent = True
            sign_allowed = True
        else:
            return False
    return mantissa_digits > 0 and (not exponent or exponent_digits > 0)


def read_speed_number(text: String) raises -> Float64:
    """Read one entire finite nonnegative OpenDRIVE speed number.

    Args:
        text: The numeric source text. Keywords are handled separately.

    Returns:
        The parsed Float64 number, retaining a numeric zero as zero.

    Raises:
        Error: If text is not a complete number, is negative or nonfinite,
            or a nonzero mantissa underflows to zero.
    """
    var number = String(text.strip())
    if number.byte_length() == 0:
        raise Error("OpenDRIVE speed needs a numeric max value")
    # Float64 also accepts non-XML syntax, including f/F and repeated points.
    if not _speed_decimal_syntax(number):
        raise Error("OpenDRIVE speed needs a numeric max value")
    var value: Float64
    try:
        value = Float64(number)
    except:
        raise Error("OpenDRIVE speed needs a numeric max value")
    if not isfinite(value) or value < 0:
        raise Error("OpenDRIVE speed must be finite and nonnegative")
    if value == 0:
        for byte in number.as_bytes():
            if byte == 101 or byte == 69:
                break
            # Validated mantissa nondigits (+, -, .) are all below byte 49.
            if byte >= 49:
                raise Error("OpenDRIVE speed number underflows Float64")
    return value
