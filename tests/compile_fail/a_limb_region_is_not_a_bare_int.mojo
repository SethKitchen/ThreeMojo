# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A density region must be a LimbRegion, not a bare integer."""

from extensions.humanoid.skeleton.limb.regions import region_label


def main() raises:
    print(region_label(0))
