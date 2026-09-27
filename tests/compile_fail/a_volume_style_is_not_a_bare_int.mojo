# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A bare int must not stand in for a volume render style: say which with
`VOLUME_MIP` or `VOLUME_ISO`."""

from materials.volume_shader import volume_render_shader


def main() raises:
    var program = volume_render_shader(1)
    print(len(program.code))
