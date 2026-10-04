# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A zone heat-balance simulation of a building.

The modules read weather, place the sun, conduct heat through layered
constructions and balance the heat of each thermal zone step by step.
They give the air temperature of each zone and the ideal heating and
cooling power that holds its setpoints. See the wiki page Building energy.
"""
