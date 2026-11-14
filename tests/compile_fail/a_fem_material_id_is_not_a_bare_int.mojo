# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A finite element material id must be a `MaterialId`, not a bare integer.
"""

from extensions.fem.ids import NodeId
from extensions.fem.mesh import TetMesh


def main() raises:
    var mesh = TetMesh()
    _ = mesh.add_element(NodeId(0), NodeId(1), NodeId(2), NodeId(3), 0)
