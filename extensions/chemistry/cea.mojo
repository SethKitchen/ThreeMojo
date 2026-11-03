# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read NASA nine-coefficient data in the NASA CEA `thermo.inp` format.

NASA's Glenn database (McBride, Zehe and Gordon, NASA TP-2002-211556) and
the CEA program use this format. A species takes two lines, then three
lines for each temperature interval:

    line 1          columns 1-24 the name
    line 2          columns 1-2 the interval count; columns 11-50 five
                    elements, each a 2-column symbol and an 6-column count;
                    columns 51-52 zero for a gas
    interval 1      columns 1-22 the low and high temperatures, 11 each;
                    columns 24-63 the eight exponents of T, which must be
                    -2, -1, 0, 1, 2, 3, 4 and 0
    interval 2      five coefficients, 16 columns each
    interval 3      two coefficients in columns 1-32, and the integration
                    constants b1 and b2 in columns 49-80

A condensed species with "(L)" in its name is a liquid, and any other is a
solid. A record with no interval holds only an assigned enthalpy, and a
record with the electron E is an ion. The reader leaves both out, as it
does a formula with a count that is not whole. Lines that start with `!`,
the `thermo` line and the line of default temperatures after it, and the
`END PRODUCTS` line are allowed between records. `END REACTANTS` ends the
data. A Fortran `D` exponent reads as `E`.
"""

from extensions.chemistry.elements import (
    ElementCount,
    Formula,
    element_from_symbol,
)
from extensions.chemistry.kinds import GAS, LIQUID, Phase, SOLID
from extensions.chemistry.quantities import MolarVolume64
from extensions.chemistry.thermo import Species, nasa9


def _number(field: String, line: Int) raises -> Float64:
    """Read a number from a fixed-width field."""
    var text = String(field.strip()).replace("D", "E").replace("d", "e")
    try:
        return atof(text)
    except:
        raise Error(String("Line ", line, ": '", field, "' is not a number"))


def _field(line: String, start: Int, end: Int) -> String:
    """Return columns start to end of a line, blank past its end."""
    var n = line.byte_length()
    if start >= n:
        return String()
    return String(line[byte = start : min(end, n)])


def _record(
    lines: List[String], first: Int, mut out: List[Species]
) raises -> Int:
    """Read one record from line index `first`; return the next index."""
    if first + 1 >= len(lines):
        raise Error(String("Line ", first + 1, ": a record needs two lines"))
    var name = String(_field(lines[first], 0, 24).strip())
    ref head = lines[first + 1]
    var number = first + 2
    var intervals = Int(_number(_field(head, 0, 2), number))
    var end = first + 2 + 3 * intervals
    if intervals < 0 or end > len(lines):
        raise Error(
            String("Line ", number, ": the intervals run past the file")
        )
    var counts = List[ElementCount]()
    var whole = True
    var ion = False
    for k in range(5):
        var at = 10 + 8 * k
        var symbol = String(_field(head, at, at + 2).strip())
        if symbol.byte_length() == 0:
            continue
        var amount = _number(_field(head, at + 2, at + 8), number)
        if amount == 0:
            continue
        if symbol.upper() == "E":
            ion = True
            continue
        if amount != Float64(Int(amount)) or amount < 0:
            whole = False
            continue
        counts.append(ElementCount(element_from_symbol(symbol), Int(amount)))
    if intervals == 0 or ion or not whole:
        return end
    var phase = GAS
    if Int(_number(_field(head, 50, 52), number)) != 0:
        phase = SOLID
        if name.find("(L)") >= 0:
            phase = LIQUID
    var bounds = List[Float64]()
    var coefficients = List[Float64]()
    var exponents: List[Float64] = [-2, -1, 0, 1, 2, 3, 4, 0]
    # A record with no interval has returned above.
    for i in range(intervals):  # pragma: no branch
        var at = first + 2 + 3 * i
        ref range_line = lines[at]
        var low = _number(_field(range_line, 0, 11), at + 1)
        var high = _number(_field(range_line, 11, 22), at + 1)
        for e in range(8):
            var start = 23 + 5 * e
            var value = _number(_field(range_line, start, start + 5), at + 1)
            if value != exponents[e]:
                raise Error(
                    String("Line ", at + 1, ": the exponents of T must be")
                    + " -2 to 4, then 0"
                )
        if i == 0:
            bounds.append(low)
        bounds.append(high)
        for j in range(5):
            coefficients.append(
                _number(_field(lines[at + 1], 16 * j, 16 * j + 16), at + 2)
            )
        ref last = lines[at + 2]
        coefficients.append(_number(_field(last, 0, 16), at + 3))
        coefficients.append(_number(_field(last, 16, 32), at + 3))
        coefficients.append(_number(_field(last, 48, 64), at + 3))
        coefficients.append(_number(_field(last, 64, 80), at + 3))
    out.append(
        Species(
            name,
            Formula(counts^),
            phase,
            nasa9(bounds^, coefficients^),
            MolarVolume64(0),
        )
    )
    return end


def read_cea_thermo(text: String) raises -> List[Species]:
    """Read every species of a NASA CEA thermo file.

    Args:
        text: The file's text.

    Returns:
        The species with fits, in file order.

    Raises:
        Error: With the line number, if a record is short, a number cannot
            be read, an element is not in the table, the exponents of T
            are not the standard ones, or the temperatures do not ascend.
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
            i += 2
        elif word.startswith("END REACTANTS"):
            return out^
        elif word.startswith("END"):
            i += 1
        else:
            i = _record(lines, i, out)
    return out^
