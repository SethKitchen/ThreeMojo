# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A reference length must be a `ReferenceKind`, not a bare integer."""

from extensions.animals.anatomy.body import ReferenceKind


def main() raises:
    var kind: ReferenceKind = 1
    print(kind.value)
