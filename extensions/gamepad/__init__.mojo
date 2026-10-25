# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Gamepads, ported from SDL 3.2.24's gamepad subsystem.

The modules read Xbox, PlayStation, Nintendo and other controllers on
Linux through evdev, and name their controls by position. They hold
SDL's mapping database and its controller tables. See the wiki page
Gamepads.
"""
