# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scanned buildings as canonical building models.

`levels` finds the floors and the ceilings in a scan's occupancy grid.
`fit` makes a `Building` from them with a construction kit, so the
structural, bearing, thermal and render views and the IFC writer read a
scan as they read a procedural tower. `catalog` reads the manifest of the
scanned buildings that `tools/building_scans.mojo` downloads.
"""
