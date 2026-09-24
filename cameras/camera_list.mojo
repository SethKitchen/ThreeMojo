# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The cameras that go with a scene, held beside it.

A camera is not a scene node here. It rides a node, by `attach`, and is
held in a list of its own type. `CameraList` holds the two lists, so a
loader can hand back the cameras of a file and a mixer can drive their
`fov`, `zoom`, `near` and `far`, as three.js's mixer drives a camera that
is in the scene graph.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera


struct CameraList(Copyable, Movable):
    """The perspective cameras and the orthographic cameras of a scene."""

    var perspective: List[PerspectiveCamera]
    var orthographic: List[OrthographicCamera]

    def __init__(out self):
        """Start with no cameras."""
        self.perspective = List[PerspectiveCamera]()
        self.orthographic = List[OrthographicCamera]()
