# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the renderer needs of a camera, and nothing more.

three.js has `Camera` extend `Object3D` and `PerspectiveCamera` extend that.
Mojo has no inheritance, so the shared part is a trait instead — which turns
out to describe the relationship better anyway. A renderer does not need a
camera to *be* anything; it needs four answers from it:

    view_matrix_in         where is the camera and which way is it facing?
    view_to_screen_matrix  how do camera-space points become pixels?
    near_distance          where does the visible range start...
    far_distance           ...and where does it end?

Everything else a camera knows — a field of view, a set of box edges — is its
own business and never reaches the renderer. That is why adding
`OrthographicCamera` needed no change to `renderers.renderer` beyond making
the argument generic: the perspective divide lives in the matrix, and a matrix
whose bottom row is (0, 0, 0, 1) simply does not divide.

The first answer takes the scene, because a camera can ride a scene node.
three.js's camera *is* an `Object3D`: it has a parent, it is carried by a
pivot like anything else, and its view matrix is the inverse of its world
position and rotation. Here a camera is not a node -- a `Mesh` is not one
either -- but it can name one with `attach`, and then its view comes from
that node's world matrix rather than from `place`. A camera that names no
node answers from where it was placed, and `view_matrix` is the same answer
without the scene for the many callers that only ever place a camera.

The two distances are methods rather than fields because a trait can require
behavior but not storage, and because the cameras hold them as `Length`
quantities while the clipper wants bare meters.
"""

from core.object3d import NodeId
from core.scene import Scene
from math.matrix4 import Matrix4


trait Camera(Copyable, Movable):
    """Something a `Renderer` can draw through."""

    def view_matrix(self) raises -> Matrix4:
        """Return the matrix taking world space to camera space, from where
        the camera was placed.

        Returns:
            The view matrix.

        Raises:
            Error: If the camera is attached to a node, whose transform only
                the scene knows; ask `view_matrix_in` instead.
        """
        ...

    def view_matrix_in(self, scene: Scene) raises -> Matrix4:
        """Return the matrix taking world space to camera space.

        Args:
            scene: The scene the camera may be riding a node of, updated.

        Returns:
            The view matrix: the inverse of the node's world matrix if the
            camera is attached, else the one `place` describes.

        Raises:
            Error: If the camera is attached to a node the scene does not
                have, or the scene is stale.
        """
        ...

    def view_to_screen_matrix(self, width: Int, height: Int) raises -> Matrix4:
        """Return the transform from camera space to pixels.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.
        """
        ...

    def near_distance(self) -> Float32:
        """Return the near clipping distance, in meters."""
        ...

    def far_distance(self) -> Float32:
        """Return the far clipping distance, in meters."""
        ...


def node_view_matrix(scene: Scene, node: NodeId) raises -> Matrix4:
    """Return the view matrix of a camera riding `node`.

    The inverse of the node's world *position and rotation*, which is what
    three.js keeps as `camera.matrixWorldInverse`: the transform that takes
    the world into the camera's own frame is the undoing of the one that put
    the camera in the world. Shared by both cameras so that "attached" means
    one thing.

    Scale is left out, as three.js leaves it out before inverting. A camera
    parented to a scaled group inherits the group's position and turn, but
    not its size: scale in a view matrix squashes camera space, which is what
    a field of view and an aspect ratio are for, and along z it changes what
    the near and far distances mean in meters. The first version inverted the
    whole world matrix and did all of that silently.

    Args:
        scene: The scene the node is in, updated.
        node: The node the camera rides.

    Returns:
        The view matrix.

    Raises:
        Error: If the node is not in the scene, or the scene is stale -- a
            camera on a node that has moved since the last `update` would
            otherwise look from where it used to be -- or the node's world
            transform reflects or flattens. A mirrored view reverses the
            screen winding the culler reads, and the culler corrects only for
            the mesh's own transform; a flattened one has no rotation left.
    """
    var world = scene.world_matrix(node)
    if world.determinant() < 0:
        raise Error(
            "A mirrored camera node would reverse the winding the culler reads"
        )
    var view = world.extract_rotation()
    view.elements[12] = world.elements[12]
    view.elements[13] = world.elements[13]
    view.elements[14] = world.elements[14]
    view.invert()
    return view^
