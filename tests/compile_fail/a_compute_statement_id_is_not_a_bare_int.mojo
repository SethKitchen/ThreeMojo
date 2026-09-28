# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a compute statement: pass a
`ComputeStatementId`."""

from materials.nodes import NODE_FLOAT, NodeGraph


def main() raises:
    var graph = NodeGraph()
    _ = graph.compute_result(0, NODE_FLOAT)
