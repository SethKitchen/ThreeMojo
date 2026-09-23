# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a node output: say which part of
the shading with `COLOR_NODE` and its siblings."""

from materials.nodes import NodeGraph


def main() raises:
    var graph = NodeGraph()
    graph.set_output(0, graph.vec3(1, 0, 0))
    print(graph.count())
