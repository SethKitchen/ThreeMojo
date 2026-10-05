# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compatibility import for the issue 288 benchmark.

The sole primitive-index implementation lives in extensions.physics.
This alias retains the benchmark and its independent oracle tests.
"""

from extensions.physics.primitive_index import _Node, _PrimitiveIndex

comptime _SnapshotBVH = _PrimitiveIndex


def main():
    """Name the benchmark entry point."""
    print("Owned primitive index; use physics_static_bench.mojo")
