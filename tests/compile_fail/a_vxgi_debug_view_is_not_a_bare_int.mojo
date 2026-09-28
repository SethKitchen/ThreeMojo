# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a VXGI pass's debug view."""

from postprocessing.vxgi_node import VXGINode


def main() raises:
    var node = VXGINode()
    node.debug = 1
    node.validate()
