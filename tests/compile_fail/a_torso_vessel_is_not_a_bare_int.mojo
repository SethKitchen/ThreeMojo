# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A torso vessel must be a `TorsoVessel`, not a bare integer."""

from extensions.humanoid.skeleton.torso.vessels.dimensions import (
    torso_vessel_label,
)


def main() raises:
    print(torso_vessel_label(2))
