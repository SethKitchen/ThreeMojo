# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A fabric kind must be a `FabricKind`, not a bare integer."""

from extensions.attire.kinds import require_fabric_kind


def main() raises:
    require_fabric_kind(1)
