# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Range checks shared by the named part ids.

Each part keeps its own type, so a hand bone cannot be passed where an
arm bone is required. The range test is the same: zero through the last
named value.
"""


def ordinal_valid(value: Int, last: Int) -> Bool:
    """Return True when `value` names an entry from zero through `last`.

    Args:
        value: The stored ordinal.
        last: The value of the last named entry.

    Returns:
        True when `value` is from zero through `last`.
    """
    if value < 0:
        return False
    return value <= last
