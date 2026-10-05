# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Linear-elastic structural analysis of frames and flat shells.

A `StructuralModel` holds nodes, supports, frame members, three-node
shells, loads and added masses. `StaticSolver` gives displacements,
reactions, member end forces and shell resultants. `solve_modes` gives
natural frequencies and mode shapes. See the wiki pages Frame analysis and
Shell analysis.
"""
