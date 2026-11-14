# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Static linear elasticity on meshes of four-node tetrahedra.

A box or the voxels of a label map become a tetrahedral mesh. Supports
and nodal forces load it, and a preconditioned conjugate gradient solve
gives displacements, stresses and reactions. The deformed surface draws
colored by von Mises stress. See the wiki page Tetrahedral FEM.
"""
