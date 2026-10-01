# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A collision query's category must be a `CollisionCategory`, not a bare
integer."""

from extensions.carla.recorder_query import CATEGORY_ANY, query_collisions


def main() raises:
    _ = query_collisions(List[UInt8](), 97, CATEGORY_ANY)
