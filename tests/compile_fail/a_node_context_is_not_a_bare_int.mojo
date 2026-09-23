# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for where a node reads the surface: use
one of the named contexts, such as `AT_RIGHT` or `CORNER_A`."""

from materials.nodes import NodeProgram, ProgramSource


def main() raises:
    var program = NodeProgram()
    var source = ProgramSource(Pointer(to=program))
    print(source.shares(2)[0])
