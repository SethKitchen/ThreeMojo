# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A moated brick castle as data, as a scene and as engineering checks.

A `CastlePlan` holds towers, blocks, a moat and a bridge in meters. The
Wijnendale plan is one plan. A mesh view draws a plan into a scene. The
analysis modules check a plan the way a structural engineer would: wind
on a tower, a masonry arch in limit analysis, a retaining wall at the
moat edge and the water balance of the moat. See the wiki page Castle.
"""
