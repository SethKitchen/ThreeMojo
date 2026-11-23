# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Steady groundwater flow in one aquifer layer.

An `Aquifer` is a grid of cells with a hydraulic conductivity, fixed
heads, wells and recharge. `solve_heads` gives the head of each cell by
the block-centered finite differences of MODFLOW. See the wiki page
Groundwater flow.
"""
