# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A behavior type must be a `BehaviorType`, not a bare integer."""

from extensions.carla.agents_misc import behavior_parameters


def main() raises:
    var parameters = behavior_parameters(1)
    print(parameters.tailgate_counter)
