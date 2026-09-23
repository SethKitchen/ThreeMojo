# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for an STL format."""

from core.assets import Assets
from core.scene import Scene
from exporters.stl import export_stl


def main() raises:
    print(len(export_stl(Scene(), Assets(), 1)))
