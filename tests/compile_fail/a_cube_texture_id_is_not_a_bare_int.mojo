# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for a cube texture id."""

from materials.material import Material
from render.framebuffer import Color


def main() raises:
    var chrome = Material(Color(255, 255, 255), env_map=0)
    print(chrome.reflectivity)
