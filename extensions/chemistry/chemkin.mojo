# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read NASA seven-coefficient data in the CHEMKIN thermo format.

Most published thermochemical databases use this format: GRI-Mech, the
Burcat tables and the files of combustion and plasma codes. Each species
takes four lines of 80 columns, with the line number 1 to 4 in column 80:

    columns  1-18   the name; the first word is used
    columns 25-44   up to four elements: a 2-column symbol, a 3-column count
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
exponent reads as `E`. The fifth element pair of some extended files, in
columns 74 to 78, is not read.

The species have no molar volume. Set one where the pressure term of a
condensed phase matters.
"""

from extensions.chemistry.elements import (
    ElementCount,
    Formula,
    element_from_symbol,
)
from extensions.chemistry.kinds import GAS, LIQUID, Phase, SOLID
from extensions.chemistry.quantities import MolarVolume64
from extensions.chemistry.thermo import Nasa7, Species


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
    for k in range(4):
        var at = 24 + 5 * k
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
    # The low range comes first in `Nasa7`; the file gives the high first.
    var coefficients = List[Float64]()
    for i in range(7, 14):
        coefficients.append(fields[i])
    for i in range(7):
        coefficients.append(fields[i])
    return Species(
        String(words[0]),
        Formula(counts^),
        phase,
        Nasa7([low, common, high], coefficients^),
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
