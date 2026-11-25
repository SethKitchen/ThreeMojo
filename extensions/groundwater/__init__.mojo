# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Groundwater flow: a port of the GWF model of MODFLOW 6.

`Simulation` reads a MODFLOW 6 simulation folder and runs it one time
step at a time. The port includes the structured grid, the node property
flow, storage, constant heads, wells, drains, rivers, general heads,
recharge, evapotranspiration and the IMS solver.
"""
