# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A shape kind must be a `ShapeKind`, not a bare integer."""

from extensions.carla.physics.shape import Shape


def main():
    var shape = Shape(1)
    print(shape.radius)
