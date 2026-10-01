# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A torso nerve must be a `TorsoNerve`, not a bare integer."""

from extensions.humanoid.skeleton.torso.nerves.dimensions import (
    torso_nerve_label,
)


def main() raises:
    print(torso_nerve_label(2))
