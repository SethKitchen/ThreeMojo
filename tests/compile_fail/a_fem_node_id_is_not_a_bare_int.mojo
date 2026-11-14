# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A finite element node id must be a `NodeId`, not a bare integer."""

from extensions.fem.mesh import TetMesh


def main() raises:
    TetMesh().require_node(0)
