# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Osteological sex of a humanoid, as a type rather than a bare integer.

The two values are the adult templates that published long-bone formulae
distinguish. They are skeletal sex, not gender: the measurements they carry
are from osteometry. A later bone that needs another template adds a value
here, and every boundary that reads a `Sex` already refuses one that is not
valid.
"""


@fieldwise_init
struct Sex(Equatable, ImplicitlyCopyable, Writable):
    """Which adult osteological template a humanoid uses."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `MALE` or `FEMALE`."""
        return self == MALE or self == FEMALE


# Adult male osteological template. The inverted Trotter and Gleser male
# line, and the authored male ratios for head, shaft and condyles, use this.
comptime MALE = Sex(0)
# Adult female osteological template. The inverted female line and the
# authored female ratios use this.
comptime FEMALE = Sex(1)
