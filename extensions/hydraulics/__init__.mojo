# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Steady hydraulics of pipe networks and of open channels.

A `PipeNetwork` holds junctions, reservoirs, pipes and pumps.
`solve_network` gives the head at each node and the flow in each link, by
the global gradient algorithm that EPANET uses. A `Channel` is a
trapezoid with a free surface. `water_surface_profile` gives its
gradually varied profile by the standard step method. See the wiki pages
Pipe networks and Open channels.
"""
