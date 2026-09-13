# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Rotating by a bare number must not compile: is it degrees or radians?"""

from math.matrix4 import rotation_z


def main() raises:
    var m = rotation_z(90.0)
    print(m.elements[0])
