# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A vehicle's body shape must be a `BodyStyle`, not a bare integer."""

from extensions.carla.render_actors import body_profile


def main() raises:
    print(body_profile(2).clearance)
