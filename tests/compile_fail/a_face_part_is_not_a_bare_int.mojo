# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A part of the face model must be a `FacePart`, not a bare integer."""

from extensions.humanoid.skeleton.head.face_model import (
    FACE_MODEL_PATH,
    FaceModel,
)


def main() raises:
    var model = FaceModel(FACE_MODEL_PATH, 0, False)
    var points = model.shape(model.no_identity(), model.no_expression())
    print(model.part(points, 0).triangle_count())
