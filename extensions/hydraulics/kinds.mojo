# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ids, the kinds and the units of a pipe network.

A `NodeId` and a `LinkId` index the lists of a `PipeNetwork`. A
`NodeKind` says if a node has a demand or a fixed head. A `LinkKind` says
if a link loses head or adds it. A `HeadLossFormula` names the law of a
pipe's friction.
"""
from core.ordinal import ordinal_valid
from units.quantity import Quantity, Unit

# Area per time: the kinematic viscosity of the fluid.
comptime KinematicViscosity64 = Quantity[2, 0, -1, 0, 0, DType.float64]
comptime KinematicViscosityUnit64 = Unit[2, 0, -1, 0, 0, DType.float64]
comptime SQUARE_METER_PER_SECOND = KinematicViscosityUnit64(1.0, "m^2/s")


@fieldwise_init
struct NodeId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a node in a `PipeNetwork`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a node.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct LinkId(Equatable, ImplicitlyCopyable, Writable):
    """The index of a link in a `PipeNetwork`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index can name a link.

        Returns:
            Whether the value is zero or more.
        """
        return self.value >= 0


@fieldwise_init
struct NodeKind(Equatable, ImplicitlyCopyable, Writable):
    """What a node of a network fixes."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two kinds.

        Returns:
            Whether the value is 0 or 1.
        """
        return ordinal_valid(self.value, 2 - 1)


# A node with a demand. Its head is a result.
comptime JUNCTION = NodeKind(0)
# A node with a fixed head, such as a lake or a tank at a known level.
comptime RESERVOIR = NodeKind(1)


@fieldwise_init
struct LinkKind(Equatable, ImplicitlyCopyable, Writable):
    """What a link of a network does to the head."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two kinds.

        Returns:
            Whether the value is 0 or 1.
        """
        return ordinal_valid(self.value, 2 - 1)


# A link that loses head to friction.
comptime PIPE = LinkKind(0)
# A link that adds head from its start to its end.
comptime PUMP = LinkKind(1)


@fieldwise_init
struct HeadLossFormula(Equatable, ImplicitlyCopyable, Writable):
    """The law of the friction of a pipe."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three formulas.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 3 - 1)


# The Hazen-Williams formula, for water in turbulent flow.
comptime HAZEN_WILLIAMS = HeadLossFormula(0)
# The Darcy-Weisbach formula, for any fluid and any flow.
comptime DARCY_WEISBACH = HeadLossFormula(1)
# The Chezy-Manning formula, for rough turbulent flow.
comptime CHEZY_MANNING = HeadLossFormula(2)
