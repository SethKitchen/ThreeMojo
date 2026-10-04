# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ids of a building model, each a type rather than a bare integer.

Each id indexes one list of a `Building`. An id is valid when it is zero or
more. The `Building` methods that read an id also check that it is in
range.
"""


@fieldwise_init
struct StoreyId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a storey in a `Building`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a storey.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct SpaceId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a space in a `Building`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a space.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct ElementId(Equatable, ImplicitlyCopyable, Writable):
    """The index of an element in a `Building`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name an element.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct OpeningId(Equatable, ImplicitlyCopyable, Writable):
    """The index of an opening in a `Building`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name an opening.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct MaterialId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a material in a `Building`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a material.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct ConstructionId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a construction in a `Building`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a construction.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct FurnishingId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a furnishing in a `Building`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a furnishing.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0
