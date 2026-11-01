# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read and write NASA seven-coefficient data in the CHEMKIN thermo format.

Most published thermochemical databases use this format: GRI-Mech, the
Burcat tables and the files of combustion and plasma codes. Each species
takes four lines of 80 columns, with the line number 1 to 4 in column 80:

    columns  1-18   the name; the first word is used
    columns 25-44   up to four elements: a 2-column symbol, a 3-column count
    columns 74-78   a fifth element, in extended files
    column  45      the phase: G, L or S
    columns 46-55   the low temperature
    columns 56-65   the high temperature
    columns 66-73   the common temperature, where the two ranges meet
    lines 2-4       fifteen columns per number: a1 to a7 of the high range,
                    then a1 to a7 of the low range

    var species = read_chemkin_thermo(Path("thermo.dat").read_text())

Blank lines, lines that start with `!`, a `THERMO` line with the line of
default temperatures after it, and an `END` line are allowed between
records. An element with a count of zero is left out. A Fortran `D`
exponent reads as `E`.

`write_chemkin_thermo` writes species back in the same columns, with each
coefficient as Fortran's E15.8 writes it. A species fit must have one or
two segments in the seven-coefficient form. A one-segment fit is written
as two equal segments that meet at the middle of its range.

The species have no molar volume. Set one where the pressure term of a
condensed phase matters.
"""

from extensions.chemistry.elements import (
    ElementCount,
    Formula,
    element_from_symbol,
)
from std.math import floor, log10
from extensions.chemistry.kinds import GAS, LIQUID, Phase, SOLID
from extensions.chemistry.quantities import MolarVolume64
from extensions.chemistry.thermo import PER_SEGMENT, Species, nasa7
from loaders.js_number import js_to_fixed


def _number(field: String, line: Int) raises -> Float64:
    """Read a number from a fixed-width field."""
    var text = String(field.strip()).replace("D", "E").replace("d", "e")
    try:
        return atof(text)
    except:
        raise Error(String("Line ", line, ": '", field, "' is not a number"))


def _phase(letter: String, line: Int) raises -> Phase:
    """Return the phase that column 45 names."""
    var upper = letter.upper()
    if upper == "G":
        return GAS
    if upper == "L":
        return LIQUID
    if upper == "S":
        return SOLID
    raise Error(String("Line ", line, ": the phase must be G, L or S"))


def _record(lines: List[String], first: Int) raises -> Species:
    """Read the four lines of one species, from line index `first`."""
    if first + 3 >= len(lines):
        raise Error(String("Line ", first + 1, ": a species needs four lines"))
    for k in range(4):
        ref line = lines[first + k]
        var short = line.byte_length() < 80
        if short or String(line[byte=79:80]) != String(k + 1):
            raise Error(
                String("Line ", first + k + 1, ": column 80 must hold ", k + 1)
            )
    ref head = lines[first]
    var number = first + 1
    var words = String(head[byte=0:18]).split()
    if len(words) == 0:
        raise Error(String("Line ", number, ": a species needs a name"))
    var counts = List[ElementCount]()
    for at in [24, 29, 34, 39, 73]:
        var symbol = String(String(head[byte = at : at + 2]).strip())
        if symbol.byte_length() == 0:
            continue
        var amount = _number(String(head[byte = at + 2 : at + 5]), number)
        if amount == 0:
            continue
        if amount != Float64(Int(amount)) or amount < 0:
            raise Error(
                String("Line ", number, ": an element count must be whole")
            )
        counts.append(ElementCount(element_from_symbol(symbol), Int(amount)))
    var phase = _phase(String(head[byte=44:45]), number)
    var low = _number(String(head[byte=45:55]), number)
    var high = _number(String(head[byte=55:65]), number)
    var common = _number(String(head[byte=65:73]), number)
    var fields = List[Float64]()
    for k in range(1, 4):
        ref line = lines[first + k]
        for j in range(5):
            # The fourth line holds four numbers.
            if k * 5 + j < 19:
                var at = 15 * j
                fields.append(
                    _number(String(line[byte = at : at + 15]), first + k + 1)
                )
    # The low range comes first in `nasa7`; the file gives the high first.
    var coefficients = List[Float64]()
    for i in range(7, 14):
        coefficients.append(fields[i])
    for i in range(7):
        coefficients.append(fields[i])
    return Species(
        String(words[0]),
        Formula(counts^),
        phase,
        nasa7([low, common, high], coefficients^),
        MolarVolume64(0),
    )


def read_chemkin_thermo(text: String) raises -> List[Species]:
    """Read every species of a CHEMKIN thermo file.

    Args:
        text: The file's text.

    Returns:
        The species, in file order.

    Raises:
        Error: With the line number, if a record is short or misnumbered,
            a number cannot be read, an element is not in the table, a
            count is not whole, the phase is not G, L or S, or the
            temperatures do not ascend.
    """
    var lines = List[String]()
    for line in text.splitlines():
        lines.append(String(line))
    var out = List[Species]()
    var i = 0
    while i < len(lines):
        var word = String(lines[i].strip()).upper()
        if word.byte_length() == 0 or word.startswith("!"):
            i += 1
        elif word.startswith("THERMO"):
            # The THERMO line, then its line of default temperatures.
            i += 2
        elif word.startswith("END"):
            return out^
        else:
            out.append(_record(lines, i))
            i += 4
    return out^


def _e15(value: Float64) raises -> String:
    """Return a number in 15 columns, as Fortran's E15.8 writes it."""
    if value == 0:
        return " 0.00000000E+00"
    var sign = String(" ")
    if value < 0:
        sign = "-"
    var a = abs(value)
    var power = Int(floor(log10(a)))
    var text = js_to_fixed(a / Float64(10) ** power, 8)
    # A mantissa just below 10 rounds up to "10.": move a power over. One
    # just below 1 rounds up to "1.", so it needs no change.
    if text.startswith("10."):
        power += 1
        text = js_to_fixed(a / Float64(10) ** power, 8)
    if abs(power) >= 100:
        raise Error("A coefficient's exponent must have two digits")
    var exponent_sign = String("+")
    if power < 0:
        exponent_sign = "-"
    var digits = String(abs(power))
    if abs(power) < 10:
        digits = "0" + digits
    return sign + text + "E" + exponent_sign + digits


def _right(text: String, width: Int) raises -> String:
    """Return text right-justified in a field."""
    if text.byte_length() > width:
        raise Error(String("'", text, "' does not fit in ", width, " columns"))
    return String(" ") * (width - text.byte_length()) + text


def _left(text: String, width: Int) -> String:
    """Return text left-justified in a field it fits."""
    return text + String(" ") * (width - text.byte_length())


def _pair(symbol: String, count: Int) raises -> String:
    """Return an element and its count in five columns."""
    return _left(symbol, 2) + _right(String(count), 3)


def chemkin_record(species: Species) raises -> String:
    """Return the four lines of one species in the CHEMKIN thermo format.

    Args:
        species: The species. Its fit has one or two segments in the
            seven-coefficient form.

    Returns:
        Four lines of 80 columns, each ending in a newline.

    Raises:
        Error: If the fit has more than two segments or is not in the
            seven-coefficient form, the name has a space or more than 18
            characters, the formula has more than five elements or a count
            above 999, a temperature does not fit its columns, or a
            coefficient's exponent needs three digits.
    """
    ref f = species.thermo
    var segments = len(f.bounds) - 1
    if segments > 2:
        raise Error("A CHEMKIN record holds at most two segments")
    for s in range(segments):  # pragma: no branch
        var k = PER_SEGMENT * s
        if f.coefficients[k] != 0 or f.coefficients[k + 1] != 0:
            raise Error("A CHEMKIN record holds the seven-coefficient form")
    var name = species.name
    if name.find(" ") >= 0 or name.byte_length() > 18:
        raise Error("A CHEMKIN name has no space and at most 18 characters")
    ref counts = species.formula.counts
    if len(counts) > 5:
        raise Error("A CHEMKIN record holds at most five elements")
    var low = f.bounds[0]
    var high = f.bounds[segments]
    var common = 0.5 * (low + high)
    var high_segment = 0
    if segments == 2:
        common = f.bounds[1]
        high_segment = 1
    var elements = String()
    var fifth = String("     ")
    for i in range(len(counts)):  # pragma: no branch
        var pair = _pair(counts[i].element.symbol(), counts[i].count)
        if i < 4:
            elements += pair
        else:
            fifth = pair
    var phase = String("S")
    if species.phase == GAS:
        phase = "G"
    elif species.phase == LIQUID:
        phase = "L"
    var line1 = (
        _left(name, 18)
        + String(" ") * 6
        + _left(elements, 20)
        + phase
        + _right(js_to_fixed(low, 3), 10)
        + _right(js_to_fixed(high, 3), 10)
        + _right(js_to_fixed(common, 2), 8)
        + fifth
        + " 1\n"
    )
    # The high segment first, then the low.
    var numbers = List[Float64]()
    for s in [high_segment, 0]:
        var k = PER_SEGMENT * s
        for i in range(2, 9):
            numbers.append(f.coefficients[k + i])
    var out = line1
    for row in range(3):
        var line = String()
        for j in range(5):
            var at = 5 * row + j
            if at < 14:
                line += _e15(numbers[at])
        out += _left(line, 79) + String(row + 2) + "\n"
    return out^


def write_chemkin_thermo(species: List[Species]) raises -> String:
    """Return a CHEMKIN thermo file of species.

    Args:
        species: The species, each in one or two seven-coefficient
            segments.

    Returns:
        A `THERMO` line, a line of default temperatures, the records and
        an `END` line.

    Raises:
        Error: If a species cannot be written. See `chemkin_record`.
    """
    var out = String("THERMO\n   300.000  1000.000  5000.000\n")
    for s in species:
        out += chemkin_record(s)
    return out + "END\n"
