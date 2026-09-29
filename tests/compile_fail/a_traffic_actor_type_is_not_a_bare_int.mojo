# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A tracked actor's kind must be a `TrafficActorType`, not a bare
integer."""

from extensions.carla.traffic_manager_state import StaticAttributes
from units.si import Length


def main() raises:
    var attributes = StaticAttributes(0, Length(2.4), Length(1.0), Length(0.8))
    print(attributes.half_length.value)
