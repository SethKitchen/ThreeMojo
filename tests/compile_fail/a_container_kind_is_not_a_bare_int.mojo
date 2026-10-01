# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A CAM container must be named by a `ContainerKind`, not a bare
integer."""

from extensions.carla.v2x import LowFrequencyContainer, ROLE_DEFAULT


def main():
    var low = LowFrequencyContainer(1, ROLE_DEFAULT, 0, 0)
    print(low.present.is_valid())
