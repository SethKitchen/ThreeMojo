# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A level of detail's distance given as a bare number must not compile:
fifty what? three.js's `LOD.addLevel(object, distance)` takes a unitless
number and divides it by the camera's zoom."""

from core.object3d import NodeId
from objects.lod import Lod


def main() raises:
    var lod = Lod(NodeId(0))
    lod.add_level(NodeId(1), 50.0)
    print(lod.count())
