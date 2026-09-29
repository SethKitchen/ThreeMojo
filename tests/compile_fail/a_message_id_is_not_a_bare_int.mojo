# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An ITS message id must be a `MessageId`, not a bare integer."""

from extensions.carla.v2x import ItsPduHeader


def main():
    var header = ItsPduHeader(2, 2, 7)
    print(header.message_id.is_valid())
