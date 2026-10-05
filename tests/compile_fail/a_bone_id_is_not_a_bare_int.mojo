# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An animal bone must be a `BoneId`, not a bare integer."""

from extensions.animals.rig import Rig


def main() raises:
    var rig = Rig()
    rig.check(0)
