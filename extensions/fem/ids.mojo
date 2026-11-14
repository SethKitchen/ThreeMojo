# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The ids and kinds of a tetrahedral finite element model.

Each is a type, so a bare integer cannot stand in for one. An id is an
index into one list of a mesh or a problem. `is_valid` checks the sign
only. The mesh or the problem checks the upper bound where it reads the
id.
"""

from core.ordinal import ordinal_valid, require_valid


@fieldwise_init
struct NodeId(Equatable, ImplicitlyCopyable, Writable):
    """A node: its index in `TetMesh.nodes`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative.

        Returns:
            Whether the value can index a node.
        """
        return self.value >= 0


@fieldwise_init
struct ElementId(Equatable, ImplicitlyCopyable, Writable):
    """A tetrahedron: its index in the elements of a `TetMesh`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative.

        Returns:
            Whether the value can index an element.
        """
        return self.value >= 0


@fieldwise_init
struct MaterialId(Equatable, ImplicitlyCopyable, Writable):
    """A material: its index in `StaticProblem.materials`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if the index is not negative.

        Returns:
            Whether the value can index a material.
        """
        return self.value >= 0


def require_id(valid: Bool, index: Int, count: Int, name: String) raises:
    """Refuse an id that does not name an entry.

    Args:
        valid: Whether the id's `is_valid` holds.
        index: The id's index.
        count: How many entries the list holds.
        name: The kind of entry, for the error text.

    Raises:
        Error: If the id is negative or past the last entry.
    """
    if not valid or index >= count:
        raise Error("The " + name + " id names no " + name + " of this model")


@fieldwise_init
struct DofAxis(Equatable, ImplicitlyCopyable, Writable):
    """The axis of one degree of freedom of a node: x, y or z."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the three axes.

        Returns:
            Whether the value is from zero to two.
        """
        return ordinal_valid(self.value, 2)


comptime DOF_X = DofAxis(0)
comptime DOF_Y = DofAxis(1)
comptime DOF_Z = DofAxis(2)


def require_dof_axis(axis: DofAxis) raises:
    """Refuse a degree of freedom axis that is not x, y or z.

    Args:
        axis: The axis to check.

    Raises:
        Error: If `axis` is not valid.
    """
    require_valid(axis.is_valid(), "A degree of freedom axis must be 0 to 2")


@fieldwise_init
struct ElementOrder(Equatable, ImplicitlyCopyable, Writable):
    """The order of the shape functions of a mesh's tetrahedra.

    `LINEAR` elements have four nodes, one at each corner. `QUADRATIC`
    elements have ten: the corners, and one node at the middle of each
    edge.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two orders.

        Returns:
            Whether the value is zero or one.
        """
        return ordinal_valid(self.value, 1)

    def nodes(self) -> Int:
        """Return how many nodes an element of this order has.

        Returns:
            4 for `LINEAR` and 10 for `QUADRATIC`.
        """
        if self.value == 1:
            return 10
        return 4


comptime LINEAR = ElementOrder(0)
comptime QUADRATIC = ElementOrder(1)


def require_order(order: ElementOrder) raises:
    """Refuse an element order that is not one of the two.

    Args:
        order: The order to check.

    Raises:
        Error: If `order` is not valid.
    """
    require_valid(order.is_valid(), "An element order must be 0 or 1")
