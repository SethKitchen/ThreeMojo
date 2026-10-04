# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compatibility imports for the shared bone-tissue definitions.

The original humanoid path exposes the same types and factories as
`extensions.anatomy.tissue`. No tissue state or implementation is copied.
"""

from extensions.anatomy.tissue import (
    BoneKind,
    BoneTissue,
    CORTICAL,
    TRABECULAR,
    cortical_tissue,
    trabecular_tissue,
)
