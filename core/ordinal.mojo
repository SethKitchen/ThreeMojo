# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Whether an integer names an entry in a closed range.

A named id stores an integer. Zero is the first name. `last` is the
last name. A value outside that range is not a name. Each id keeps its
own type.
"""


def ordinal_valid(value: Int, last: Int) -> Bool:
    """Return True when `value` names an entry from zero through `last`.

    Args:
        value: The stored ordinal.
        last: The value of the last named entry. A count is one past this.

    Returns:
        True when `value` is from zero through `last`.
    """
    if value < 0:
        return False
    return value <= last
