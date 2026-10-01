# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A head nerve must be a `HeadNerve`, not a bare integer."""

from extensions.humanoid.skeleton.head.nerves.dimensions import head_nerve_label


def main() raises:
    print(head_nerve_label(1))
