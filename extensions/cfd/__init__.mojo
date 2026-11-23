# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite-volume analysis of incompressible flow in two dimensions.

A `Grid` is a block of equal rectangular cells. A `FlowCase` holds a
grid, a fluid and the boundary of each side. `FlowSolver` advances the
laminar Navier-Stokes equations in time with the PISO algorithm, as the
OpenFOAM solver icoFoam does. See the wiki page Finite-volume flow.
"""
