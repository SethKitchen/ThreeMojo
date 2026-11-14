# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A joint kind must be a `JointKind`, not a bare integer."""

from extensions.physics.joint import JointKind


def _name(kind: JointKind) -> String:
    return "joint"


def main() raises:
    print(_name(1))
