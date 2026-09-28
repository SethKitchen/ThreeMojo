# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Torso contents must be `TorsoContents`, not a bare integer."""

from extensions.humanoid.skeleton.torso.contents import BONES


def main() raises:
    print(BONES.plus(2).value)
