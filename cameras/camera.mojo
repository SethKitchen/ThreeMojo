# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the renderer needs of a camera, and nothing more.

three.js has `Camera` extend `Object3D` and `PerspectiveCamera` extend that.
Mojo has no inheritance, so the shared part is a trait instead — which turns
out to describe the relationship better anyway. A renderer does not need a
camera to *be* anything; it needs five answers from it:

    view_matrix_in         where is the camera and which way is it facing?
    projection_matrix      what volume can it see?
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

from core.layers import Layers
from core.object3d import NodeId
from core.scene import Scene
from math.matrix4 import Matrix4
from math.vector3 import Vector3


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

    def projection_matrix(self) raises -> Matrix4:
        """Return the transform from camera space to normalized device
        space, three.js's `projectionMatrix`.

        What `view_to_screen_matrix` is before the viewport, and what the
        renderer reads its `Frustum` from: times the view matrix, it says
        in world space what the camera can see, and a mesh whose bounds
        lie outside it is not prepared at all.

        Returns:
            The projection matrix.

        Raises:
            Error: If the camera's volume is degenerate.
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

    def visible_layers(self) -> Layers:
        """Return which layers this camera draws, three.js's `camera.layers`.

        `Renderer.prepare` skips a mesh whose node shares none of them.
        """
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
            transform reflects, flattens or shears. A mirrored view reverses
            the screen winding the culler reads, and the culler corrects only
            for the mesh's own transform; a flattened one has no rotation
            left; a sheared one, a nonuniform scale above a turn, has axes
            that are not at right angles, which no rotation matches.
    """
    var world = scene.world_matrix(node)
    if world.determinant() < 0:
        raise Error(
            "A mirrored camera node would reverse the winding the culler reads"
        )
    var view = world.extract_rotation()
    # Unit axes are not always a rotation. A group scaled (2, 1, 1) above a
    # node turned about z leaves the node's world x and y axes off right
    # angles, and normalizing them keeps that angle: inverted as a view it
    # would skew the whole image. A scale along the node's own world axes
    # drops out cleanly; this is the case that does not.
    if not view.is_rotation():
        raise Error(
            "A sheared camera node has no rotation to look from: a nonuniform"
            " scale above a turn takes its axes off right angles"
        )
    # The inverse of a rotation and a translation, taken exactly: the
    # rotation transposed, and the translation turned back through it and
    # negated. The general inverse gives the same numbers to within
    # rounding, but rounding is the point: it leaves a bottom row of
    # (1e-8, 0, 0, 0.9999999) where a rigid inverse has (0, 0, 0, 1), and
    # the frustum the renderer builds from a view asks for that row exactly
    # before it trusts the view's z row as a depth. This is the row it
    # promises.
    var inverse = Matrix4()
    for row in range(3):  # pragma: no branch
        for column in range(3):  # pragma: no branch
            inverse.elements[column * 4 + row] = view.elements[row * 4 + column]
    var back = inverse.transform_direction(
        Vector3(world.elements[12], world.elements[13], world.elements[14])
    )
    inverse.elements[12] = -back.x
    inverse.elements[13] = -back.y
    inverse.elements[14] = -back.z
    return inverse^


def project_point[
    C: Camera
](point: Vector3, camera: C, scene: Scene) raises -> Vector3:
    """Return where a world-space point lands in a camera's normalized
    device space, three.js's `Vector3.project(camera)`.

    Args:
        point: The point, in world space.
        camera: The camera.
        scene: The scene, updated, whose node the camera can ride.

    Returns:
        The point in normalized device space: x and y from -1 to 1 across
        the view, z from -1 at the near plane to 1 at the far one.

    Raises:
        Error: If the camera's volume is degenerate, or it rides a node
            the scene does not have, or the scene is stale.
    """
    var out = point
    out.project(camera.view_matrix_in(scene), camera.projection_matrix())
    return out


def unproject_point[
    C: Camera
](point: Vector3, camera: C, scene: Scene) raises -> Vector3:
    """Return the world-space point at a place in a camera's normalized
    device space, three.js's `Vector3.unproject(camera)`.

    Args:
        point: The point in normalized device space.
        camera: The camera.
        scene: The scene, updated, whose node the camera can ride.

    Returns:
        The point, in world space.

    Raises:
        Error: If the camera's volume is degenerate, or it rides a node
            the scene does not have, or the scene is stale.
    """
    var out = point
    out.unproject(camera.view_matrix_in(scene), camera.projection_matrix())
    return out
