# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Linear-elastic structural analysis of frames and flat shells.

A `StructuralModel` holds nodes, supports, frame members, three-node
shells, loads and added masses. `StaticSolver` gives displacements,
reactions, member end forces and shell resultants. `solve_modes` gives
natural frequencies and mode shapes. `solve_load_history` and
`solve_ground_motion` follow a model in time. `solve_buckling` gives the
buckling factors of a load case and `solve_second_order` its P-Delta
response. `load_step` and `displacement_step` follow a truss whose bars
yield. See the wiki pages Frame analysis and Shell analysis.
"""
