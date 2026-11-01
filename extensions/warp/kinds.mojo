# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The kinds of a warp drive analysis.

An `Axis` names one coordinate of the grid: time, x, y or z. A
`TensorIndex` says where the two indices of a tensor sit. An
`EnergyCondition` names one of the four pointwise energy conditions. A
`DifferenceOrder` picks the finite-difference stencil. A `Frame` says
whether tensor components are in the coordinate frame or in the frame of
the Eulerian observer.

WarpFactory passes these as strings, such as "covariant" and "Null". Here
each one is a type, so a bare integer or a misspelled name does not
compile.
"""


@fieldwise_init
struct Axis(Equatable, ImplicitlyCopyable, Writable):
    """One coordinate of the spacetime grid."""

    var value: Int
    """The number that names the kind."""

    def is_valid(self) -> Bool:
        """Return True if this names time, x, y or z.

        Returns:
            Whether the value is 0 to 3.
        """
        return self.value >= 0 and self.value < 4

    def name(self) -> String:
        """Return the coordinate's name.

        Returns:
            "t", "x", "y" or "z", or "?" if not valid.
        """
        var names: List[String] = ["t", "x", "y", "z"]
        if not self.is_valid():
            return "?"
        return names[self.value]


comptime T_AXIS = Axis(0)
"""The time coordinate. Its grid step is a duration."""
comptime X_AXIS = Axis(1)
"""The x coordinate, the direction a warp drive travels."""
comptime Y_AXIS = Axis(2)
"""The y coordinate."""
comptime Z_AXIS = Axis(3)
"""The z coordinate."""


@fieldwise_init
struct TensorIndex(Equatable, ImplicitlyCopyable, Writable):
    """Where the two indices of a rank-two tensor sit."""

    var value: Int
    """The number that names the kind."""

    def is_valid(self) -> Bool:
        """Return True if this is one of the four index positions.

        Returns:
            Whether the value is 0 to 3.
        """
        return self.value >= 0 and self.value < 4

    def name(self) -> String:
        """Return WarpFactory's name of the index position.

        Returns:
            "covariant", "contravariant", "mixedupdown" or "mixeddownup",
            or "?" if not valid.
        """
        var names: List[String] = [
            "covariant",
            "contravariant",
            "mixedupdown",
            "mixeddownup",
        ]
        if not self.is_valid():
            return "?"
        return names[self.value]


comptime COVARIANT = TensorIndex(0)
"""Both indices down: T_ab."""
comptime CONTRAVARIANT = TensorIndex(1)
"""Both indices up: T^ab."""
comptime MIXED_UP_DOWN = TensorIndex(2)
"""The first index up and the second down: T^a_b."""
comptime MIXED_DOWN_UP = TensorIndex(3)
"""The first index down and the second up: T_a^b."""


@fieldwise_init
struct EnergyCondition(Equatable, ImplicitlyCopyable, Writable):
    """One of the four pointwise energy conditions."""

    var value: Int
    """The number that names the kind."""

    def is_valid(self) -> Bool:
        """Return True if this is the null, weak, dominant or strong condition.

        Returns:
            Whether the value is 0 to 3.
        """
        return self.value >= 0 and self.value < 4

    def name(self) -> String:
        """Return WarpFactory's name of the condition.

        Returns:
            "Null", "Weak", "Dominant" or "Strong", or "?" if not valid.
        """
        var names: List[String] = ["Null", "Weak", "Dominant", "Strong"]
        if not self.is_valid():
            return "?"
        return names[self.value]

    def uses_null_directions(self) -> Bool:
        """Return True if the condition samples null directions only.

        The null and dominant conditions sample null directions. The weak
        and strong conditions sample timelike directions.

        Returns:
            Whether the condition is the null or the dominant condition.
        """
        return self.value == 0 or self.value == 2


comptime NULL_ENERGY = EnergyCondition(0)
"""T_ab k^a k^b >= 0 for every null k."""
comptime WEAK_ENERGY = EnergyCondition(1)
"""T_ab V^a V^b >= 0 for every timelike V."""
comptime DOMINANT_ENERGY = EnergyCondition(2)
"""-T^a_b k^b is not spacelike for every null k."""
comptime STRONG_ENERGY = EnergyCondition(3)
"""(T_ab - T g_ab / 2) V^a V^b >= 0 for every timelike V."""


@fieldwise_init
struct DifferenceOrder(Equatable, ImplicitlyCopyable, Writable):
    """The order of accuracy of the finite-difference stencils."""

    var value: Int
    """The number that names the kind."""

    def is_valid(self) -> Bool:
        """Return True if this is the second or the fourth order.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value == 0 or self.value == 1

    def reach(self) -> Int:
        """Return how many points the stencil reads on each side.

        Returns:
            1 for the second order and 2 for the fourth order.
        """
        return self.value + 1


comptime SECOND_ORDER = DifferenceOrder(0)
"""Central differences over three points. An axis needs 3 points or more."""
comptime FOURTH_ORDER = DifferenceOrder(1)
"""Central differences over five points. An axis needs 5 points or more."""


@fieldwise_init
struct Frame(Equatable, ImplicitlyCopyable, Writable):
    """The frame that a tensor's components are measured in."""

    var value: Int
    """The number that names the kind."""

    def is_valid(self) -> Bool:
        """Return True if this is the coordinate or the Eulerian frame.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value == 0 or self.value == 1


comptime COORDINATE_FRAME = Frame(0)
"""The components along the grid coordinates t, x, y and z."""
comptime EULERIAN_FRAME = Frame(1)
"""The components in the orthonormal frame of the observer at rest in the
slices of constant time. Its metric is the Minkowski metric."""
