# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A torso lymph part must be a `TorsoLymph`, not a bare integer."""

from extensions.humanoid.skeleton.torso.lymph.dimensions import (
    torso_lymph_label,
)


def main() raises:
    print(torso_lymph_label(2))
