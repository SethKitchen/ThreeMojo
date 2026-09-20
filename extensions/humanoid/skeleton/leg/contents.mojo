# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which solids `add_leg` attaches: bones, muscles, or both.

    _ = add_leg(..., contents=MUSCLES)
    _ = add_leg(..., contents=BONES)
    _ = add_leg(..., contents=BOTH)
"""


@fieldwise_init
struct LegContents(Equatable, ImplicitlyCopyable, Writable):
    """Which tissue layers a connected leg draws.

    The type stops a bare integer at compile time. A value that is not
    `BONES`, `MUSCLES` or `BOTH` is still constructible, and the
    boundary that reads it refuses it.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is bones, muscles or both."""
        if self == BONES:
            return True
        if self == MUSCLES:
            return True
        return self == BOTH

    def includes_bones(self) raises -> Bool:
        """Return True if this layer set draws the bones and knee tissues.

        Returns:
            True for `BONES` and `BOTH`.

        Raises:
            Error: If this value is not a named layer set.
        """
        if not self.is_valid():
            raise Error("Leg contents must be bones, muscles or both")
        if self == BONES:
            return True
        return self == BOTH

    def includes_muscles(self) raises -> Bool:
        """Return True if this layer set draws the skeletal muscles.

        Returns:
            True for `MUSCLES` and `BOTH`.

        Raises:
            Error: If this value is not a named layer set.
        """
        if not self.is_valid():
            raise Error("Leg contents must be bones, muscles or both")
        if self == MUSCLES:
            return True
        return self == BOTH


# Cortical bones and the five knee tissues.
comptime BONES = LegContents(0)
# Named skeletal muscles and three connective-tissue solids.
comptime MUSCLES = LegContents(1)
# Bones, knee tissues and muscles together.
comptime BOTH = LegContents(2)
