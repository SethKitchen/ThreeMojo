# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The type check the TSL function modules share."""

from materials.nodes import NodeGraph, NodeRef, ValueType


def _expect(g: NodeGraph, node: NodeRef, type: ValueType, what: String) raises:
    """Refuse a node that is not of the type a function reads.

    Args:
        g: The graph that owns the node.
        node: The node to read.
        type: The type the function requires.
        what: The function's name, for the message.

    Raises:
        Error: If the node is not of this graph or not of `type`.
    """
    var got = g.type_of(node)
    if got != type:
        raise Error(what + " reads a " + type.name() + ", not a " + got.name())
