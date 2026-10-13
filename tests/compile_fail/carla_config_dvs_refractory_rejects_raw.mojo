# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reject a raw mismatch at the dvs_refractory configuration boundary."""

from extensions.carla.cameras import DVSConfig


def main() raises:
    var config = DVSConfig()
    config.set_refractory_period(Float64(0))
