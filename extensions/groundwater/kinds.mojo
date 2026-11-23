# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The kinds of a groundwater model.

A `CellKind` says what a cell of the grid does. An `AquiferKind` says if
the layer is full of water or has a water table.
"""
from core.ordinal import ordinal_valid


@fieldwise_init
struct CellKind(Equatable, ImplicitlyCopyable, Writable):
    """What a cell of an aquifer grid does."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three kinds.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 3 - 1)


# A cell whose head is a result.
comptime ACTIVE = CellKind(0)
# A cell whose head is fixed, such as a river or a lake that cuts the
# layer.
comptime FIXED_HEAD = CellKind(1)
# A cell that holds no water and passes none, such as rock.
comptime INACTIVE = CellKind(2)


@fieldwise_init
struct AquiferKind(Equatable, ImplicitlyCopyable, Writable):
    """How the thickness of the flow follows from the head."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two kinds.

        Returns:
            Whether the value is 0 or 1.
        """
        return ordinal_valid(self.value, 2 - 1)


# The layer is full between its bottom and its top. The transmissivity is
# the conductivity times that thickness.
comptime CONFINED = AquiferKind(0)
# The layer has a water table. The transmissivity is the conductivity
# times the head above the bottom.
comptime UNCONFINED = AquiferKind(1)
