# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Steady hydraulics of a network of pipes.

A `PipeNetwork` holds junctions, reservoirs, pipes and pumps.
`solve_network` gives the head at each node and the flow in each link, by
the global gradient algorithm that EPANET uses. See the wiki page Pipe
networks.
"""
