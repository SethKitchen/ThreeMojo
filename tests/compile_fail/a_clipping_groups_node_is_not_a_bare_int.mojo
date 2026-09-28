# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the node a clipping group holds its
planes at: pass a `NodeId`."""

from objects.clipping_group import ClippingGroup


def main() raises:
    print(ClippingGroup(3).enabled)
