# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A plain node must not stand in for a 32-bit word: a `vec2` of two
numbers is the halves of a `uint` only when `word`, a constant or a
packing makes it a `NodeWord`."""

from materials.nodes import NodeGraph
from materials.tsl_bits import word_to_uint


def main() raises:
    var graph = NodeGraph()
    var halves = graph.vec2(1, 2)
    print(word_to_uint(graph, halves).value)
