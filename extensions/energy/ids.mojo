# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ids and kinds of a zone model, each a type rather than a bare integer.

A `ZoneId`, a `SurfaceId` and a `WindowId` index the lists of a
`ZoneModel`. Each id is valid when it is zero or more. Methods that read
an id also check that it is in range. A `BoundaryKind` says what is on
the outside face of a surface.
"""


@fieldwise_init
struct ZoneId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a thermal zone in a `ZoneModel`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a zone.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct SurfaceId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a heat transfer surface in a `ZoneModel`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a surface.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct WindowId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a window in a `ZoneModel`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a window.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct BoundaryKind(Equatable, ImplicitlyCopyable, Writable):
    """What is on the outside face of a surface."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the 3 kinds.

        Returns:
            Whether the value is 0 to 2.
        """
        return self.value >= 0 and self.value < 3

    def name(self) -> String:
        """Return the kind's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        if not self.is_valid():
            return "unknown"
        var names: List[String] = ["exterior", "interzone", "ground"]
        return names[self.value]


# The outdoor air, the sun and the sky.
comptime EXTERIOR = BoundaryKind(0)
# Another zone, or the same zone, on the outside face.
comptime INTERZONE = BoundaryKind(1)
# The ground, at a fixed temperature.
comptime GROUND = BoundaryKind(2)
