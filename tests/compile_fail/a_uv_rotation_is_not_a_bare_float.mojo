# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Turning a 2D transform by a bare number must not compile: is it degrees
or radians? three.js's `Matrix3.rotate` takes radians and says so only in
its documentation."""

from math.matrix3 import Matrix3


def main() raises:
    var m = Matrix3.rotation(90.0)
    print(m.elements[0])
