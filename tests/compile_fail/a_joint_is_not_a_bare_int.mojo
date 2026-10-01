# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A joint must be a `Joint`, not a bare integer."""

from extensions.humanoid.rig.joints import joint_parent


def main() raises:
    _ = joint_parent(1)
