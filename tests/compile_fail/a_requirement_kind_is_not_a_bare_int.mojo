# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A requirement kind must be a `RequirementKind`, not a bare integer."""

from extensions.chemistry.kinds import RequirementKind


def main():
    var kind: RequirementKind = 0
    _ = kind.is_valid()
