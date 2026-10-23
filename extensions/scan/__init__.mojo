# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scanned scenes: SOG splat files, the frame of a scan, occupancy grids
and colliders.

A scan is a Gaussian splat capture of a real place. This package reads
the SOG files that SuperSplat publishes, puts a scan in meters with z up,
and turns the splats into a voxel grid and static boxes for the physics
world. `extensions.building.scan` turns the same grid into a canonical
building model.
"""
