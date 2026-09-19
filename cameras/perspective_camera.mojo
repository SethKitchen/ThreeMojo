# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A perspective camera, ported from three.js `src/cameras/PerspectiveCamera.js`.

three.js takes the field of view as a bare number and documents it as degrees.
Here it is an `Angle`, so the unit is carried by the value and
`PerspectiveCamera(50.0, ...)` does not compile — you have to say which.

`near` and `far` are `Length`, which is where this project's world units get
pinned down: **world space is meters**. three.js leaves world units to the
application, and that works until someone builds a scene in feet and wonders
why the camera clips. Saying it once, in the type, settles it.

The camera is placed by `position` and `target`, or it rides a scene node.
three.js's camera is an `Object3D` and is always the second; `place` is the
shortcut every example wanted, and `attach` is the general case -- a camera
on a pivot orbits with it, and a camera that is a child of a car looks out
of the windscreen. See `cameras.camera`.
"""

from cameras.camera import Camera, node_view_matrix
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from math.matrix4 import Matrix4
from math.projection import look_at, perspective, viewport
from math.vector3 import Vector3
from std.math import isfinite, tan
from units.si import Angle, Length, METER

# A frustum that looks straight ahead: what a camera has unless asked.
comptime NO_SHIFT = Length(0.0, METER)


struct PerspectiveCamera(Camera, ImplicitlyCopyable):
    """A camera that renders with perspective, in meters and radians."""

    var fov: Angle
    var aspect: Float32
    var near: Length
    var far: Length
    # How far the frustum's two side edges are moved along x at the near
    # plane, keeping their distance apart: an off-center projection that
    # looks a little to one side without turning. Zero looks straight
    # ahead. What three.js's `StereoCamera` does to each eye's projection,
    # and the one thing a stereo pair needs of a camera that the field of
    # view cannot say. See `cameras.stereo_camera`.
    var view_shift: Length
    var position: Vector3
    var target: Vector3
    var up: Vector3
    # The scene node this camera rides, or `NO_PARENT` for a camera that is
    # placed. While attached, `position`, `target` and `up` are not read.
    var node: NodeId
    # Which layers this camera draws, three.js's `camera.layers`: layer
    # zero alone until told otherwise. See `core.layers`.
    var layers: Layers

    def __init__(
        out self,
        fov: Angle,
        aspect: Float32,
        near: Length,
        far: Length,
        view_shift: Length = NO_SHIFT,
    ) raises:
        """Create a camera at the origin looking down -z, drawing layer zero.

        Args:
            fov: Vertical field of view.
            aspect: Width divided by height; dimensionless.
            near: Distance to the near clipping plane.
            far: Distance to the far clipping plane.
            view_shift: How far the frustum is moved along x at the near
                plane, positive to the right. Zero, the default, looks
                straight ahead.

        Raises:
            Error: If the aspect ratio or the clipping planes are unusable,
                or the shift is not finite.
        """
        if aspect <= 0:
            raise Error("The aspect ratio must be positive")
        if fov.value <= 0:
            raise Error("The field of view must be positive")
        if near.value <= 0:
            raise Error("The near plane must be in front of the camera")
        if far.value <= near.value:
            raise Error("The far plane must be beyond the near plane")
        if not isfinite(view_shift.value):
            raise Error("A view shift must be finite")

        self.view_shift = view_shift
        self.fov = fov
        self.aspect = aspect
        self.near = near
        self.far = far
        self.position = Vector3(0, 0, 0)
        self.target = Vector3(0, 0, -1)
        self.up = Vector3(0, 1, 0)
        self.node = NO_PARENT
        self.layers = Layers()

    def visible_layers(self) -> Layers:
        """Return which layers this camera draws; see `core.layers`."""
        return self.layers

    def place(mut self, position: Vector3, target: Vector3):
        """Move the camera to `position` and aim it at `target`.

        Also lets go of any node it was riding: placing is the other way of
        saying where a camera is.
        """
        self.position = position
        self.target = target
        self.node = NO_PARENT

    def attach(mut self, node: NodeId):
        """Ride `node`, looking down its -z with its +y up.

        From then on the view comes from the node's world matrix, so parent
        the node to a pivot and the camera orbits, or `Scene.look_at` it at
        something with `camera=True`. What `place` set is kept but not read
        until `place` is called again.

        Args:
            node: The scene node to ride.
        """
        self.node = node

    def projection_matrix(self) raises -> Matrix4:
        """Return the matrix taking camera space to normalized device space.

        The top edge is found from half the field of view and the rest
        follows from it and the aspect ratio. The two side edges are then
        moved by `view_shift`, which keeps the frustum's width and skews
        it: the symmetric frustum is the shift of zero.

        Returns:
            The projection matrix.

        Raises:
            Error: If the frustum works out degenerate.
        """
        var top = self.near.value * tan(self.fov.value / 2)
        var right = top * self.aspect
        var shift = self.view_shift.value
        return perspective(
            -right + shift,
            right + shift,
            top,
            -top,
            self.near.value,
            self.far.value,
        )

    def view_matrix(self) raises -> Matrix4:
        """Return the matrix taking world space to camera space.

        Returns:
            The view matrix, from where the camera was placed.

        Raises:
            Error: If the camera sits at its own target, or up is parallel to
                the view direction, or the camera rides a node -- the scene
                has that answer, so ask `view_matrix_in`.
        """
        if self.node != NO_PARENT:
            raise Error(
                "An attached camera's view comes from its node; call"
                " view_matrix_in(scene)"
            )
        return look_at(self.position, self.target, self.up)

    def view_matrix_in(self, scene: Scene) raises -> Matrix4:
        """Return the matrix taking world space to camera space.

        Args:
            scene: The scene, updated, for a camera riding one of its nodes.

        Returns:
            The inverse of the node's world matrix if attached, else what
            `view_matrix` gives.

        Raises:
            Error: If the placement is degenerate, the node is not in the
                scene, or the scene is stale.
        """
        if self.node == NO_PARENT:
            return self.view_matrix()
        return node_view_matrix(scene, self.node)

    def view_projection_matrix(self) raises -> Matrix4:
        """Return projection * view: world space straight to NDC.

        Returns:
            The combined matrix.

        Raises:
            Error: If either half cannot be built.
        """
        var combined = self.projection_matrix()
        combined.multiply(self.view_matrix())
        return combined^

    def screen_matrix(self, width: Int, height: Int) raises -> Matrix4:
        """Return the full world-space-to-pixels transform.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.

        Returns:
            The product viewport * projection * view, ready to transform
            world points straight into pixels.

        Raises:
            Error: If the viewport or either camera matrix is invalid.
        """
        var combined = viewport(width, height)
        combined.multiply(self.view_projection_matrix())
        return combined^

    def view_to_screen_matrix(self, width: Int, height: Int) raises -> Matrix4:
        """Return the transform from camera space to pixels.

        This is `screen_matrix` without the view half, for callers that have
        already moved into camera space — anything clipping against the near
        plane has to, since the plane is only a plane there.

        Args:
            width: Image width in pixels.
            height: Image height in pixels.

        Returns:
            The product viewport * projection.

        Raises:
            Error: If the viewport or the projection is invalid.
        """
        var combined = viewport(width, height)
        combined.multiply(self.projection_matrix())
        return combined^

    def near_distance(self) -> Float32:
        """Return the near clipping distance, in meters."""
        return self.near.value

    def far_distance(self) -> Float32:
        """Return the far clipping distance, in meters."""
        return self.far.value

    def project(
        self, point: Vector3, width: Int, height: Int
    ) raises -> Vector3:
        """Return where a world-space point lands on the image.

        The x and y components come back in pixels, with y measured down from
        the top. The z component is NDC depth, -1 at the near plane and +1 at
        the far plane, which is what a depth buffer would compare.

        Args:
            point: A position in world space, in meters.
            width: Image width in pixels.
            height: Image height in pixels.

        Returns:
            The projected point, x and y in pixels and z as NDC depth.

        Raises:
            Error: If the camera or viewport is invalid.
        """
        return self.screen_matrix(width, height).transform_point(point)
