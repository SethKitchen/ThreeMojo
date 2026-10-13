# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A dentition must be a Dentition, not a bare integer."""

from extensions.humanoid.correspondence import dentition_label


def main() raises:
    print(dentition_label(0))
