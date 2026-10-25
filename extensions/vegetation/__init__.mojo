# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Dense vegetation for the software renderer: grass, flowers and trees.

The grass is real geometry, one curved and tapered strip a blade. Blades
are grouped in square clusters. Each frame, a cluster is culled against
the view and given a level of detail by its distance, and only the
clusters that stay are bent by the wind and rebuilt. This is the work a
GPU-driven renderer does in a compute pass, done here before the draw.
"""
