# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a drag event kind."""

from controls.drag_controls import DragEvent
from core.object3d import NodeId


def main():
    var event = DragEvent(3, NodeId(0))
    print(event.node)
