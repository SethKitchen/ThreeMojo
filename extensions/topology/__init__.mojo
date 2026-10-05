# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cell complex for buildings: cells that share faces.

Rooms are cells. A wall between two rooms is one face with a room on each
side, and a floor is one face with a room above and a room below. The
modules build that complex from storey plans and answer adjacency
questions about it.
"""
