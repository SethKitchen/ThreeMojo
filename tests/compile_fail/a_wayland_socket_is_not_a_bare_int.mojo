# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a Wayland socket."""

from window.wayland import WaylandWindow


def main() raises:
    var window = WaylandWindow(4, 4, "title", 3)
    print(window.is_open)
