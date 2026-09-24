# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Draco Edgebreaker traversal."""

from loaders.draco_buffer import DracoBuffer
from loaders.draco_mesh import decode_edgebreaker


def main() raises:
    var buffer = DracoBuffer(List[UInt8]())
    var mesh = decode_edgebreaker(buffer, 0)
    print(mesh.points)
