# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Numbers in the fixed-width fields of thermochemical data files.

The NASA CEA and Chemkin thermo files are Fortran records. A number fills
a field of fixed width, with spaces around it, and its exponent can be a
`D` where other languages write `E`. `fortran_number(field, line)` reads
one, and names the line when the field is not a number.
"""


def fortran_number(field: String, line: Int) raises -> Float64:
    """Read a number from a fixed-width field.

    Args:
        field: The field, with any spaces around the number.
        line: The line of the record, from one, for the message.

    Returns:
        The number. A `D` or `d` exponent reads as `E`.

    Raises:
        Error: If the field is not a number.
    """
    var text = String(field.strip()).replace("D", "E").replace("d", "e")
    try:
        return atof(text)
    except:
        raise Error(String("Line ", line, ": '", field, "' is not a number"))
