# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared parts of the exact CARLA control generators.

Each generator writes one test fixture from exact Fraction arithmetic. This
module holds the float bits, the directed rounding, the command line and the
read-only check that the generators share. The rules are those of the Python
generators that the tools replace.
"""

from std.math import inf
from std.memory import bitcast
from std.pathlib import Path

from tools._fraction import Fraction


comptime USAGE_TAIL = " [-h] [--json JSON] [--check]"
"""The options part of the usage line."""


def float_bits(value: Float64) -> UInt64:
    """Return the bits of a double, as `struct.pack('>d')` gives them.

    Args:
        value: The double.

    Returns:
        The 64 bits.
    """
    return bitcast[DType.uint64](value)


def from_bits(raw: UInt64) -> Float64:
    """Return the double that 64 bits encode.

    Args:
        raw: The bits.

    Returns:
        The double.
    """
    return bitcast[DType.float64](raw)


def exact(raw: UInt64) raises -> Fraction:
    """Return the exact value of finite double bits.

    Args:
        raw: The bits of a finite double.

    Returns:
        The exact value.

    Raises:
        Error: If the bits encode an infinity or a NaN.
    """
    return Fraction.from_float(from_bits(raw))


def hex_word(raw: UInt64) -> String:
    """Return 16 uppercase hexadecimal digits, as `f'{raw:016X}'` does.

    Args:
        raw: The word.

    Returns:
        The digits, without a prefix.
    """
    comptime digits = "0123456789ABCDEF"
    var out = String()
    for shift in range(60, -4, -4):
        out += chr(Int(digits.as_bytes()[Int((raw >> UInt64(shift)) & 15)]))
    return out^


def python_bool(value: Bool) -> String:
    """Return `True` or `False`, as Python's `str(bool)` does.

    Args:
        value: The value.

    Returns:
        The text.
    """
    return "True" if value else "False"


def is_finite(value: Float64) -> Bool:
    """Return whether a double is neither infinite nor a NaN.

    Args:
        value: The double.

    Returns:
        True for a finite double.
    """
    return value == value and value - value == 0


def next_up(value: Float64) -> Float64:
    """Return the next double toward positive infinity.

    This is `math.nextafter(value, math.inf)`.

    Args:
        value: The double.

    Returns:
        The next double. Positive infinity and a NaN return themselves.
    """
    if value != value or value == inf[DType.float64]():
        return value
    if value == 0:
        return from_bits(1)
    var raw = float_bits(value)
    return from_bits(raw + 1) if value > 0 else from_bits(raw - 1)


def next_down(value: Float64) -> Float64:
    """Return the next double toward negative infinity.

    This is `math.nextafter(value, -math.inf)`.

    Args:
        value: The double.

    Returns:
        The next double. Negative infinity and a NaN return themselves.
    """
    return -next_up(-value)


def toward_zero(value: Float64) -> Float64:
    """Return the next double toward zero.

    This is `math.nextafter(value, 0.0)`.

    Args:
        value: A nonzero double.

    Returns:
        The next double toward zero.
    """
    return next_down(value) if value > 0 else next_up(value)


def bracket(number: Fraction) raises -> Tuple[Float64, Float64]:
    """Return the tightest double interval that holds a rational.

    An exact double gives a point. A value past the finite range gives the
    interval from the largest finite double to the infinity.

    Args:
        number: The rational.

    Returns:
        The low and high doubles.

    Raises:
        Error: If the arithmetic fails, which it must not.
    """
    var rounded: Float64
    try:
        rounded = number.to_float()
    except:
        var infinity = inf[DType.float64]()
        rounded = infinity if number > Fraction(0) else -infinity
    if not is_finite(rounded):
        if rounded > 0:
            return (toward_zero(rounded), rounded)
        return (rounded, toward_zero(rounded))
    var represented = Fraction.from_float(rounded)
    var low = next_down(rounded) if represented > number else rounded
    var high = next_up(rounded) if represented < number else rounded
    return (low, high)


def power_of_two(exponent: Int) -> Float64:
    """Return a normal power of two exactly.

    Args:
        exponent: An exponent from -1022 to 1023.

    Returns:
        2**exponent.
    """
    return from_bits(UInt64(exponent + 1023) << 52)


def ldexp(value: Float64, exponent: Int) -> Float64:
    """Return value * 2**exponent when the result is normal.

    The tools call it only where `math.ldexp` is exact: a normal result.

    Args:
        value: The double.
        exponent: An exponent from -1022 to 1023.

    Returns:
        The scaled double.
    """
    return value * power_of_two(exponent)


struct Options(Movable):
    """The parsed command line of a control generator."""

    var status: Int
    """0 to run, 2 for an argument error, or -1 after `--help`."""
    var message: String
    """The usage error or help text."""
    var check: Bool
    """True for a read-only check."""
    var json: String
    """The JSON report path, or empty for none."""
    var has_json: Bool
    """True when `--json` was given."""
    var positional: String
    """The positional argument, or empty when the tool takes none."""

    def __init__(out self):
        """Start with no options."""
        self.status = 0
        self.message = String()
        self.check = False
        self.json = String()
        self.has_json = False
        self.positional = String()


def parse_options(
    program: String,
    description: String,
    arguments: List[String],
    positional: String = "",
) -> Options:
    """Parse `[--json PATH] [--check]` as `argparse` does without
    abbreviations.

    Args:
        program: The program name for the usage line.
        description: The help description.
        arguments: The arguments, without the program name.
        positional: The name of one required positional argument, or empty
            for none.

    Returns:
        The options. A nonzero status carries the text to print.
    """
    var options = Options()
    var takes = positional.byte_length() > 0
    var usage = "usage: " + program + USAGE_TAIL
    if takes:
        usage += " " + positional
    usage += "\n"
    var unknown = List[String]()
    var i = 0
    var problem = String()
    var found = False
    var only_positional = False
    while i < len(arguments):
        var word = arguments[i]
        var dashed = (
            not only_positional
            and word.startswith("-")
            and word.byte_length() > 1
        )
        if not dashed:
            if takes and not found:
                options.positional = word
                found = True
            else:
                unknown.append(word)
        elif word == "--" and takes:
            only_positional = True
        elif word == "-h" or word == "--help":
            options.status = -1
            var arguments_help = String()
            if takes:
                arguments_help = (
                    "\npositional arguments:\n  " + positional + "\n"
                )
            options.message = (
                usage
                + "\n"
                + description
                + "\n"
                + arguments_help
                + "\noptions:\n  -h, --help   show this help message and"
                " exit\n  --json JSON\n  --check      verify without writing\n"
            )
            return options^
        elif word == "--check":
            options.check = True
        elif word == "--json":
            if i + 1 >= len(arguments) or (
                arguments[i + 1].startswith("-")
                and arguments[i + 1].byte_length() > 1
            ):
                problem = "argument --json: expected one argument"
                break
            options.json = arguments[i + 1]
            options.has_json = True
            i += 1
        elif word.startswith("--json="):
            options.json = String(word[byte=7:])
            options.has_json = True
        else:
            unknown.append(word)
        i += 1
    if not problem and takes and not found:
        problem = "the following arguments are required: " + positional
    if not problem and len(unknown) > 0:
        problem = "unrecognized arguments: " + " ".join(unknown)
    if not problem and options.check and options.has_json:
        problem = "--check is read-only; do not combine it with --json"
    if problem:
        options.status = 2
        options.message = usage + program + ": error: " + problem + "\n"
    return options^


def deliver(
    root: String, relative: String, text: String, check: Bool
) -> Tuple[Int, String]:
    """Write a fixture, or compare it byte for byte without writing.

    Args:
        root: The repository root.
        relative: The fixture path below the root.
        text: The fixture text.
        check: True to compare without writing.

    Returns:
        0 and no text on success, or 1 and the reason.
    """
    var target = root + "/" + relative
    if check:
        var path = Path(target)
        var saved: List[UInt8]
        try:
            if path.is_dir():
                raise Error("[Errno 21] Is a directory: '" + target + "'")
            saved = path.read_bytes()
        except error:
            return (1, "Cannot check " + target + ": " + String(error) + "\n")
        var wanted = text.as_bytes()
        var same = len(saved) == len(wanted)
        if same:
            for index in range(len(saved)):
                if saved[index] != wanted[index]:
                    same = False
                    break
        if not same:
            return (
                1,
                target + " is stale; regenerate without --check\n",
            )
        return (0, String())
    try:
        Path(target).write_text(text)
    except error:
        return (1, "Cannot write " + target + ": " + String(error) + "\n")
    return (0, String())


def write_report(path: String, text: String) -> Tuple[Int, String]:
    """Write a JSON report.

    Args:
        path: The report path.
        text: The JSON text, with its final newline.

    Returns:
        0 and no text on success, or 1 and the reason.
    """
    try:
        Path(path).write_text(text)
    except error:
        return (1, "Cannot write " + path + ": " + String(error) + "\n")
    return (0, String())
