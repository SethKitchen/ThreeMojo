# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A modal combination rule must be a `CombinationRule`, not a bare integer."""

from extensions.structure.spectrum import CombinationRule


def main():
    var rule: CombinationRule = 0
    _ = rule.is_valid()
