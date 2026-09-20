# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Several cameras drawing into regions of one image, from three.js
`src/cameras/ArrayCamera.js`.

three.js's `ArrayCamera` is a `PerspectiveCamera` holding a list of
`PerspectiveCamera`s, each with a `viewport`, and its renderer draws the
scene once per sub camera into that camera's rectangle. A split screen,
a stereo pair side by side, a wall of monitors: every one is this.

Here it is the list and nothing else. The renderer already has a
viewport and a scissor, which is all a sub camera needs, so
`Renderer.render_array` sets both to each camera's rectangle in turn,
clears that rectangle to the background, draws through the camera, and
resolves the target once at the end. Nothing of one region reaches
another. See `examples/split.mojo` for the same thing done by hand, and
`cameras.stereo_camera` for the pair this was written for.

A sub camera is a `PerspectiveCamera`, as three.js's is. Each keeps its
own aspect, and a camera whose aspect does not match its rectangle draws
a squeezed image, as three.js's does: the projection is mapped onto the
rectangle whatever its shape.
"""

from cameras.perspective_camera import PerspectiveCamera
from render.rect import Rect


struct ArrayCamera(Movable):
    """A list of perspective cameras, each with the rectangle of the image
    it draws into."""

    var cameras: List[PerspectiveCamera]
    # One rectangle per camera, in pixels, the corner counting up from the
    # bottom left as three.js's viewport does; see `render.rect`.
    var viewports: List[Rect]

    def __init__(out self):
        """Create an array holding no camera."""
        self.cameras = List[PerspectiveCamera]()
        self.viewports = List[Rect]()

    def add(mut self, camera: PerspectiveCamera, viewport: Rect) raises:
        """Add a camera and the rectangle it draws into.

        Args:
            camera: The camera. Copied: a change to it afterward does not
                reach the array.
            viewport: Where its image lands, in pixels. It must hold at
                least one pixel. Whether it fits the target is known only
                when a target is drawn into, and `Renderer.render_array`
                refuses one that does not.

        Raises:
            Error: If the rectangle holds no pixel.
        """
        if not viewport.is_valid():
            raise Error("A sub camera's viewport needs a positive size")
        self.cameras.append(camera)
        self.viewports.append(viewport)

    def count(self) raises -> Int:
        """Return how many cameras the array holds.

        Returns:
            The count, which is the length of both lists.

        Raises:
            Error: If the two lists do not have the same length. `add`
                keeps them in step; the lists are open, and one edited on
                its own would send a camera to a rectangle that is not
                there.
        """
        if len(self.cameras) != len(self.viewports):
            raise Error(
                "An array camera needs one viewport per camera: the two"
                " lists have different lengths"
            )
        return len(self.cameras)
