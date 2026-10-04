# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ids of a structural model, each a type rather than a bare integer.

Each id indexes one list of a `StructuralModel`. An id is valid when it is
zero or more. The `StructuralModel` methods that read an id also check that
it is in range.
"""


@fieldwise_init
struct NodeId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a node in a `StructuralModel`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a node.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct MemberId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a frame member in a `StructuralModel`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a frame member.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct ShellId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a shell in a `StructuralModel`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a shell.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct LoadCaseId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a load case in a `StructuralModel`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a load case.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0
