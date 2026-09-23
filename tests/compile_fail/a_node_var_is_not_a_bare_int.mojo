# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a variable of a graph: use the
`NodeVar` that `Var` handed back."""

from materials.nodes import NodeGraph


def main() raises:
    var graph = NodeGraph()
    _ = graph.Var(graph.float(1))
    var held = graph.get(0)
    print(held.value)
