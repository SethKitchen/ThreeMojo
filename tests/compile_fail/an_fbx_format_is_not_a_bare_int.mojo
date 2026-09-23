# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare integer must not stand in for the form an FBX file is written
in."""

from loaders.fbx_tree import FbxDocument


def main() raises:
    var document = FbxDocument(1)
    print(document.version)
