# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an atomic function: pass an
`AtomicOp` such as `ATOMIC_ADD`."""

from materials.compute_nodes import ComputeKernel, StorageBufferStore
from materials.nodes import NODE_FLOAT


def main() raises:
    var store = StorageBufferStore()
    var cells = store.instanced_array(2, NODE_FLOAT)
    var kernel = ComputeKernel()
    var zero = kernel.graph.float(0)
    _ = kernel.atomic_func(2, cells, zero, zero)
