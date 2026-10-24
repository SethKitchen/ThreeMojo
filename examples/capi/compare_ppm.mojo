# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare two PPM frames, as `run.sh check` does for the GPU and the CPU.

    compare_ppm.mojo A.ppm B.ppm MEAN OUTLIER FRACTION

The frames pass when their mean difference is at most MEAN (of 255), and at
most FRACTION of the values differ by more than OUTLIER. Exit status 0 is a
pass. The printed mean and the outlier percent use Python's fixed-point
rounding: half to even, on the exact value of the double.
"""

from std.memory import bitcast
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._python_float import parse_float

comptime USAGE = (
    "Compare two PPM frames, as run.sh check does for the GPU and the CPU.\n"
    "\n"
    "    compare_ppm.mojo A.ppm B.ppm MEAN OUTLIER FRACTION\n"
    "\n"
    "The frames pass if their mean difference is at most MEAN (of 255), and"
    " at most\n"
    "FRACTION of the values differ by more than OUTLIER. Exit status 0 is a"
    " pass."
)
"""The text the tool prints when the command line is wrong."""


struct PpmFrame(Movable):
    """One binary P6 frame."""

    var width: Int
    """The width in pixels."""
    var height: Int
    """The height in pixels."""
    var pixels: List[UInt8]
    """The RGB bytes, three per pixel."""

    def __init__(out self, width: Int, height: Int, var pixels: List[UInt8]):
        """Store a frame.

        Args:
            width: The width in pixels.
            height: The height in pixels.
            pixels: The RGB bytes.
        """
        self.width = width
        self.height = height
        self.pixels = pixels^


def fixed_decimal(value: Float64, places: Int) raises -> String:
    """Return `value` in fixed point, as Python's `format` writes it.

    Args:
        value: A finite double.
        places: The number of digits after the decimal point.

    Returns:
        The text. A negative zero keeps its sign, as in `-0.0000`.

    Raises:
        Error: If `value` is not finite or `places` is negative.
    """
    if places < 0:
        raise Error("a fixed format needs a non-negative number of places")
    var negative = bitcast[DType.uint64](value) >> 63 == 1
    var magnitude = abs(Fraction.from_float(value))
    var scaled = magnitude * Fraction(BigInt(10) ** places)
    var parts = scaled.numerator.divmod(scaled.denominator)
    var whole = parts[0].copy()
    var twice = parts[1] * BigInt(2)
    if twice > scaled.denominator or (
        twice == scaled.denominator and whole.is_odd()
    ):
        whole = whole + BigInt(1)
    var digits = whole.to_string()
    while digits.byte_length() <= places:
        digits = "0" + digits
    var text = digits
    if places > 0:
        var split = digits.byte_length() - places
        text = String(digits[byte=:split]) + "." + String(digits[byte=split:])
    if negative:
        return "-" + text
    return text


def _integer(text: String) raises -> Int:
    """Return a base-10 integer, as Python's `int(text)` does for digits.

    Args:
        text: Optional sign and digits.

    Returns:
        The integer.

    Raises:
        Error: If `text` is not an integer.
    """
    var body = text
    var sign = 1
    if body.startswith("+"):
        var rest = String(body[byte=1:])
        body = rest
    elif body.startswith("-"):
        sign = -1
        var rest = String(body[byte=1:])
        body = rest
    if body.byte_length() == 0:
        raise Error("not an integer: " + text)
    var value = 0
    for byte in body.as_bytes():
        if byte < 48 or byte > 57:
            raise Error("not an integer: " + text)
        value = value * 10 + Int(byte) - 48
    return sign * value


def _piece(data: List[UInt8], start: Int, end: Int) -> String:
    """Return the UTF-8 text of a byte range.

    Args:
        data: The file bytes.
        start: The first byte.
        end: The byte after the last one.

    Returns:
        The text. Invalid UTF-8 becomes the replacement character.
    """
    var piece = List[UInt8]()
    for index in range(start, end):
        piece.append(data[index])
    return String(from_utf8_lossy=piece)


def read_ppm(path: String) raises -> PpmFrame:
    """Return a binary PPM whose maximum sample is 255.

    Args:
        path: The file.

    Returns:
        The width, the height and the RGB bytes.

    Raises:
        Error: If the file is missing or is not that kind of PPM.
    """
    var data: List[UInt8]
    try:
        data = Path(path).read_bytes()
    except error:
        raise Error(path + ": " + String(error))
    var breaks = List[Int]()
    for index in range(len(data)):
        if data[index] == 10:
            breaks.append(index)
            if len(breaks) == 3:
                break
    if len(breaks) < 3:
        raise Error(path + " is not a P6 PPM with 255 levels")
    var magic = _piece(data, 0, breaks[0])
    var size = _piece(data, breaks[0] + 1, breaks[1])
    var maximum = _piece(data, breaks[1] + 1, breaks[2])
    if magic != "P6" or maximum != "255":
        raise Error(path + " is not a P6 PPM with 255 levels")
    var parts = size.split()
    if len(parts) != 2:
        raise Error(path + " is not a P6 PPM with 255 levels")
    var width = _integer(String(parts[0]))
    var height = _integer(String(parts[1]))
    if width < 0 or height < 0:
        raise Error(path + " is not a P6 PPM with 255 levels")
    var expected = width * height * 3
    var pixels = List[UInt8]()
    for index in range(breaks[2] + 1, len(data)):
        pixels.append(data[index])
    if len(pixels) != expected:
        raise Error(
            path
            + " has "
            + String(len(pixels))
            + " bytes, not "
            + String(expected)
        )
    return PpmFrame(width, height, pixels^)


def compare_frames(
    first: PpmFrame,
    second: PpmFrame,
    mean_limit: Float64,
    outlier: Int,
    fraction: Float64,
) raises -> Tuple[Int, String]:
    """Compare two frames and return the status and the report line.

    Args:
        first: The first frame.
        second: The second frame.
        mean_limit: The largest allowed mean difference.
        outlier: A difference above this counts as an outlier.
        fraction: The largest allowed outlier fraction.

    Returns:
        Status 0 when the frames pass, otherwise 1, and the report line.

    Raises:
        Error: If the sizes differ or a frame has no samples.
    """
    if first.width != second.width or first.height != second.height:
        raise Error(
            "sizes differ: "
            + String(first.width)
            + "x"
            + String(first.height)
            + " and "
            + String(second.width)
            + "x"
            + String(second.height)
        )
    var count = len(first.pixels)
    if count == 0 or count != len(second.pixels):
        raise Error("a PPM must contain pixels")
    var total = 0
    var worst = 0
    var outliers = 0
    for index in range(count):
        var gap = Int(first.pixels[index]) - Int(second.pixels[index])
        if gap < 0:
            gap = -gap
        total += gap
        if gap > worst:
            worst = gap
        if gap > outlier:
            outliers += 1
    var mean = Float64(total) / Float64(count)
    var share = Float64(outliers) / Float64(count)
    var line = (
        String(first.width)
        + "x"
        + String(first.height)
        + ": mean "
        + fixed_decimal(mean, 4)
        + ", worst "
        + String(worst)
        + ", "
        + fixed_decimal(share * 100.0, 3)
        + "% over "
        + String(outlier)
    )
    var status = 0 if mean <= mean_limit and share <= fraction else 1
    return (status, line)


def compare_command(arguments: List[String]) raises -> Int:
    """Compare the frames named on the command line.

    Args:
        arguments: `A.ppm B.ppm MEAN OUTLIER FRACTION`, without the program.

    Returns:
        The exit status. A wrong command line or a bad frame is 1.

    Raises:
        Error: Never. A bad frame is an exit status, not an exception.
    """
    if len(arguments) != 5:
        print(USAGE, file=stderr)
        return 1
    try:
        var first = read_ppm(arguments[0])
        var second = read_ppm(arguments[1])
        var mean_limit = parse_float(arguments[2])
        var outlier = _integer(arguments[3])
        var fraction = parse_float(arguments[4])
        var result = compare_frames(
            first, second, mean_limit, outlier, fraction
        )
        print(result[1])
        return result[0]
    except error:
        print(error, file=stderr)
        return 1


def main() raises:
    """Compare two PPM files from the command line."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    exit(compare_command(arguments))
