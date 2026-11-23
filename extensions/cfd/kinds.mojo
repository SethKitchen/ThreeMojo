# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The kinds of a finite-volume flow case.

A `Side` names one of the four sides of a grid. A `BoundaryKind` says
which variable a side fixes. A `ConvectionScheme` says how a face takes
its velocity from the two cells beside it.
"""
from core.ordinal import ordinal_valid


@fieldwise_init
struct Side(Equatable, ImplicitlyCopyable, Writable):
    """One of the four sides of a grid."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the four sides.

        Returns:
            Whether the value is 0 to 3.
        """
        return ordinal_valid(self.value, 4 - 1)


# The side at the lowest x.
comptime WEST = Side(0)
# The side at the highest x.
comptime EAST = Side(1)
# The side at the lowest y.
comptime SOUTH = Side(2)
# The side at the highest y.
comptime NORTH = Side(3)


@fieldwise_init
struct BoundaryKind(Equatable, ImplicitlyCopyable, Writable):
    """Which variable a side of the grid fixes."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two kinds.

        Returns:
            Whether the value is 0 or 1.
        """
        return ordinal_valid(self.value, 2 - 1)


# The velocity is fixed and the pressure has no gradient along the normal.
# A wall, a moving wall and an inlet are of this kind.
comptime FIXED_VELOCITY = BoundaryKind(0)
# The pressure is fixed and the velocity has no gradient along the normal.
# An outlet and a pressure inlet are of this kind.
comptime FIXED_PRESSURE = BoundaryKind(1)


@fieldwise_init
struct ConvectionScheme(Equatable, ImplicitlyCopyable, Writable):
    """How a face takes its velocity from the two cells beside it."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two schemes.

        Returns:
            Whether the value is 0 or 1.
        """
        return ordinal_valid(self.value, 2 - 1)


# The value of the cell that the flow comes from. First order and bounded.
comptime UPWIND = ConvectionScheme(0)
# The mean of the two cells. Second order. OpenFOAM names it `linear`.
comptime CENTRAL = ConvectionScheme(1)
