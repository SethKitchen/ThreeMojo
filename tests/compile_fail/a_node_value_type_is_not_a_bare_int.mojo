# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a node value type: say which with
`NODE_FLOAT` or one of the vectors."""

from materials.nodes import ValueType


def main() raises:
    var type: ValueType = 3
    print(type.name())
