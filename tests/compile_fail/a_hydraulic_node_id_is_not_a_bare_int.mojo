# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A pipe network node must be a `NodeId`, not a bare integer."""

from extensions.hydraulics.kinds import NodeId


def main():
    var node: NodeId = 0
    _ = node.is_valid()
