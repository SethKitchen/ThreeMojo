# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compatibility imports for `extensions.physics.shape`.

Existing CARLA imports keep the same types and functions. New simulations
can import the shared module directly.
"""

from extensions.physics.shape import (
    ShapeKind,
    SPHERE,
    BOX,
    CAPSULE,
    CONVEX,
    MESH,
    PhysicsMaterial,
    cross,
    unit_or,
    any_perpendicular,
    Polyhedron,
    MassProperties,
    Shape,
    component,
)
