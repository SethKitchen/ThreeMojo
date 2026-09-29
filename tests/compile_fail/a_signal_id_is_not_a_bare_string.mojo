# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A signal id must be a `SignalId`, not a bare string."""

from extensions.carla.map_builder import MapBuilder


def main() raises:
    var builder = MapBuilder()
    builder.add_dependency_to_signal(String("1001"), "1002", "light")
