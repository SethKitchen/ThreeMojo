# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An ITS station type must be a `StationType`, not a bare integer."""

from extensions.carla.v2x import vehicle_role_of


def main():
    print(vehicle_role_of(6).value)
