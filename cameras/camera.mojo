# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the renderer needs of a camera, and nothing more.

three.js has `Camera` extend `Object3D` and `PerspectiveCamera` extend that.
Mojo has no inheritance, so the shared part is a trait instead — which turns
out to describe the relationship better anyway. A renderer does not need a
camera to *be* anything; it needs four answers from it:

    view_matrix            where is the camera and which way is it facing?
    view_to_screen_matrix  how do camera-space points become pixels?
    near_distance          where does the visible range start...
    far_distance           ...and where does it end?

Everything else a camera knows — a field of view, a set of box edges — is its
own business and never reaches the renderer. That is why adding
`OrthographicCamera` needed no change to `renderers.renderer` beyond making
the argument generic: the perspective divide lives in the matrix, and a matrix
whose bottom row is (0, 0, 0, 1) simply does not divide.

The two distances are methods rather than fields because a trait can require
behaviour but not storage, and because the cameras hold them as `Length`
quantities while the clipper wants bare metres.
"""

from math.matrix4 import Matrix4


trait Camera(Copyable, Movable):
    """Something a `Renderer` can draw through."""

    def view_matrix(self) raises -> Matrix4:
        """Return the matrix taking world space to camera space."""
        ...

    def view_to_screen_matrix(self, width: Int, height: Int) raises -> Matrix4:
        """Return the transform from camera space to pixels.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.
        """
        ...

    def near_distance(self) -> Float32:
        """Return the near clipping distance, in metres."""
        ...

    def far_distance(self) -> Float32:
        """Return the far clipping distance, in metres."""
        ...
