# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A snapshot ray distance is a Length, not a bare float."""

from extensions.physics.query_snapshot import SnapshotRaycastHit


def _wrong(mut hit: SnapshotRaycastHit):
    hit.distance = Float32(1)


def main():
    pass
