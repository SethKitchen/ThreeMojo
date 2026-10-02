# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compatibility imports for `extensions.physics.collide`.

Existing CARLA imports keep the same types and functions. New simulations
can import the shared module directly.
"""

from extensions.physics.collide import (
    ContactPoint,
    WorldShape,
    flipped,
    collide,
    round_round,
    SignedDistance,
    signed_distance,
    round_polyhedron,
    polyhedron_polyhedron,
    clip_polygon,
    face_contact,
    mesh_contacts,
)
