# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the kind of object a VRML node became."""

from core.assets import Assets
from core.scene import Scene
from loaders.vrml import parse_vrml


def main() raises:
    var scene = Scene()
    var assets = Assets()
    var model = parse_vrml("#VRML V2.0Group { }", scene, assets)
    print(model.count(1))
