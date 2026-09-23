# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a node of a graph: use the
`NodeRef` the graph handed back."""

from materials.nodes import NodeGraph


def main() raises:
    var graph = NodeGraph()
    _ = graph.float(1)
    var wave = graph.sin(0)
    print(wave.value)
