# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A groundwater kind must be a `AquiferKind`, not a bare integer."""

from extensions.groundwater.kinds import AquiferKind


def main():
    var kind: AquiferKind = 0
    _ = kind.is_valid()
