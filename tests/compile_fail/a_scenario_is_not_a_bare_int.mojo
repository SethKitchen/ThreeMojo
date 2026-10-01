# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A V2X scenario must be a `Scenario`, not a bare integer."""

from extensions.carla.v2x import PropagationParams


def main():
    var params = PropagationParams()
    params.scenario = 2
    print(params.scenario.is_valid())
