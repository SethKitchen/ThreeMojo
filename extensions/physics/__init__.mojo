# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared rigid-body mechanics for simulation extensions.

The core has no CARLA actor, map, sensor or vehicle dependency. Scalars
use SI units; vectors and tensors use the units documented on each field.
Choose one world frame and express all bodies, forces and gravity in it.
"""
