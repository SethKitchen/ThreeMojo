# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a sculpting tool."""

from core.assets import Assets
from core.scene import Scene
from geometries.sculptor import Sculptor


def main() raises:
    var scene = Scene()
    var assets = Assets()
    var sculptor = Sculptor(scene, assets, 0)
    sculptor.set_tool(1)
