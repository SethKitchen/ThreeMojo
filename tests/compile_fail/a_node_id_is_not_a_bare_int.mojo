# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Passing a plain integer where a node is expected must not compile.

The wrapper has to be more than documentation: an `Int` that happens to hold
the right number is still the wrong type, because the next one might not.
"""

from core.object3d import Object3D
from core.scene import Scene


def main() raises:
    var scene = Scene()
    _ = scene.add(Object3D())
    var bad = scene.world_position(0)
    print(bad.x)
