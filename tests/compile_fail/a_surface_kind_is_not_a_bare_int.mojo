# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A surface kind must be a `SurfaceKind`, not a bare integer."""

from extensions.carla.mesh_factory import surface_name


def main() raises:
    print(surface_name(0))
