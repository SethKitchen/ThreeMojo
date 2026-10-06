# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ids of a cell complex, each a type rather than a bare integer.

A `VertexId`, an `EdgeId`, a `FaceId` and a `CellId` index the lists of
a `CellComplex`. A `RegionId` names one input polygon of an arrangement:
the caller chooses it, for example the index of a room. Each id is valid
when it is zero or more. Methods that read an id also check that it is in
range.
"""


@fieldwise_init
struct VertexId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a vertex of a cell complex."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a vertex.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct EdgeId(Equatable, ImplicitlyCopyable, Writable):
    """The index of an edge of a cell complex."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name an edge.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct FaceId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a face of a cell complex."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a face.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct CellId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a cell of a cell complex."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a cell.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct RegionId(Equatable, ImplicitlyCopyable, Writable):
    """A caller's name for one input polygon of an arrangement."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names a region.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


# The label of a part of the plane that no region covers.
comptime NO_REGION = RegionId(-1)
