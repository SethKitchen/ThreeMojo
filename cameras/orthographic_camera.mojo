# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A camera without perspective, from three.js `src/cameras/OrthographicCamera.js`.

Parallel projection: two objects of the same size come out the same size on
screen however far away they are. That is wrong for a photograph and right for
a floor plan, an isometric game, a CAD drawing, or a shadow map — anywhere
measurements have to survive the trip to the image.

The view volume is a box rather than a pyramid, so it is given by its edges in
world units rather than by an angle. three.js takes those four edges directly
and so does this; `centered` is here for the common case of a symmetric box,
which is the shape `PerspectiveCamera` always has.

`near` may be zero. A perspective camera cannot allow that because projection
divides by depth; nothing here does, so the restriction would be borrowed from
a problem this camera does not have. Edges must be properly ordered — right
beyond left, top above bottom — because a reversed pair mirrors the projection,
and backface culling reads exactly that winding.

Everything after the projection matrix is shared with the perspective path,
including the clipper and the perspective-correct interpolation. The latter
costs nothing here and is not special-cased: an orthographic matrix leaves the
transformed w at one, so every `inv_w` is one and the correction divides by
one. A backend that special-cased it would be two code paths where the math
already gives one.

`zoom` and `set_view_offset` are three.js's. The zoom divides the box's
width and height about its center, and a view offset cuts one tile of a
larger image out of the zoomed box, as `updateProjectionMatrix` cuts it.
"""

from std.math import isfinite
from cameras.camera import Camera, ViewOffset, node_view_matrix, view_offset
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from math.matrix4 import Matrix4
from math.projection import look_at, orthographic, viewport
from math.vector3 import Vector3
from units.si import Length, METER


struct OrthographicCamera(Camera):
    """A camera that renders without perspective, in meters."""

    var left: Length
    var right: Length
    var top: Length
    var bottom: Length
    var near: Length
    var far: Length
    var position: Vector3
    var target: Vector3
    var up: Vector3
    # The scene node this camera rides, or `NO_PARENT` for a camera that is
    # placed. See `PerspectiveCamera.attach`.
    var node: NodeId
    # Which layers this camera draws; see `PerspectiveCamera.layers`.
    var layers: Layers
    # How far the view is magnified, three.js's `zoom`: the volume's
    # width and height are divided by it about their center. One by
    # default. OrbitControls zooms an orthographic camera by changing it.
    var zoom: Float32
    # The tile of a larger image this camera draws, three.js's `view`:
    # none until `set_view_offset`. See `cameras.camera.ViewOffset`.
    var view: Optional[ViewOffset]

    def __init__(
        out self,
        left: Length,
        right: Length,
        top: Length,
        bottom: Length,
        near: Length,
        far: Length,
    ) raises:
        """Create a camera at the origin looking down -z.

        Args:
            left: Left edge of the view volume.
            right: Right edge.
            top: Top edge.
            bottom: Bottom edge.
            near: Distance to the near clipping plane.
            far: Distance to the far clipping plane.

        Raises:
            Error: If the volume has no width or height or its edges are
                reversed, or the clipping planes are unusable. `near` may be
                zero, as in three.js — nothing divides by depth here — but
                not negative.
        """
        if right.value <= left.value:
            raise Error("The view volume needs right beyond left")
        if top.value <= bottom.value:
            raise Error("The view volume needs top above bottom")
        if far.value <= near.value:
            raise Error("The far plane must be beyond the near plane")

        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
        self.near = near
        self.far = far
        self.position = Vector3(0, 0, 0)
        self.target = Vector3(0, 0, -1)
        self.up = Vector3(0, 1, 0)
        self.node = NO_PARENT
        self.layers = Layers()
        self.zoom = 1
        self.view = None

    def set_view_offset(
        mut self,
        full_width: Float32,
        full_height: Float32,
        x: Float32,
        y: Float32,
        width: Float32,
        height: Float32,
    ) raises:
        """Draw one tile of a larger image, three.js's `setViewOffset`.

        Unlike the perspective camera's, this leaves the volume's edges as
        they are, as three.js leaves them: the tile is a share of the box
        the edges and the zoom describe.

        Args:
            full_width: The full image's width, in pixels.
            full_height: The full image's height, in pixels.
            x: How far across the full image the tile starts.
            y: How far down the full image the tile starts.
            width: The tile's width.
            height: The tile's height.

        Raises:
            Error: If a number is not finite, or a width or a height is
                not positive. The camera is left as it was.
        """
        self.view = view_offset(full_width, full_height, x, y, width, height)

    def clear_view_offset(mut self):
        """Draw the whole image again, three.js's `clearViewOffset`.

        The tile is kept, disabled, as three.js keeps it.
        """
        if Bool(self.view):
            self.view.value().enabled = False

    def visible_layers(self) -> Layers:
        """Return which layers this camera draws; see `core.layers`."""
        return self.layers

    def place(mut self, position: Vector3, target: Vector3):
        """Move the camera to `position` and aim it at `target`.

        Also lets go of any node it was riding, as `PerspectiveCamera.place`
        does.
        """
        self.position = position
        self.target = target
        self.node = NO_PARENT

    def attach(mut self, node: NodeId):
        """Ride `node`, looking down its -z with its +y up.

        Args:
            node: The scene node to ride. See `PerspectiveCamera.attach`.
        """
        self.node = node

    def projection_matrix(self) raises -> Matrix4:
        """Return the matrix taking camera space to normalized device space.

        Returns:
            The projection matrix.

        Raises:
            Error: If the view volume works out degenerate, the zoom is
                not positive and finite, or an enabled view offset is
                refused by `ViewOffset.validate`.
        """
        if not (self.zoom > 0 and isfinite(self.zoom)):
            raise Error(
                "An orthographic zoom must be positive, got ", self.zoom
            )
        # The edges as given at a zoom of one, not rebuilt from a center
        # and a half width, which can round a last bit away.
        var left = self.left.value
        var right = self.right.value
        var top = self.top.value
        var bottom = self.bottom.value
        if self.zoom != 1:
            # three.js's `updateProjectionMatrix`: the half extents divided
            # by the zoom, about the volume's center.
            var half_x = (self.right.value - self.left.value) / (2 * self.zoom)
            var half_y = (self.top.value - self.bottom.value) / (2 * self.zoom)
            var mid_x = (self.right.value + self.left.value) / 2
            var mid_y = (self.top.value + self.bottom.value) / 2
            left = mid_x - half_x
            right = mid_x + half_x
            top = mid_y + half_y
            bottom = mid_y - half_y
        if Bool(self.view) and self.view.value().enabled:
            var view = self.view.value()
            view.validate()
            # One pixel of the full image, in meters of the zoomed box.
            var scale_w = (
                (self.right.value - self.left.value) / view.full_width
            ) / self.zoom
            var scale_h = (
                (self.top.value - self.bottom.value) / view.full_height
            ) / self.zoom
            left += scale_w * view.offset_x
            right = left + scale_w * view.width
            top -= scale_h * view.offset_y
            bottom = top - scale_h * view.height
        return orthographic(
            left, right, top, bottom, self.near.value, self.far.value
        )

    def view_matrix(self) raises -> Matrix4:
        """Return the matrix taking world space to camera space.

        Returns:
            The view matrix, from where the camera was placed.

        Raises:
            Error: If the camera sits at its own target, or up is parallel to
                the view direction, or the camera rides a node -- ask
                `view_matrix_in`.
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

    def view_to_screen_matrix(self, width: Int, height: Int) raises -> Matrix4:
        """Return the transform from camera space to pixels.

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


def centered(
    height: Length, aspect: Float32, near: Length, far: Length
) raises -> OrthographicCamera:
    """Return a symmetric orthographic camera of a given visible height.

    The shape a `PerspectiveCamera` always has, specified the same way: how
    much you can see, and how wide that is relative to how tall.

    Args:
        height: How much of the world fits vertically in the image.
        aspect: Width divided by height; dimensionless.
        near: Distance to the near clipping plane.
        far: Distance to the far clipping plane.

    Returns:
        The camera.

    Raises:
        Error: If the height or aspect is not positive, or the clipping
            planes are unusable.
    """
    if height.value <= 0:
        raise Error("The visible height must be positive")
    if aspect <= 0:
        raise Error("The aspect ratio must be positive")
    var half = height.value / 2
    var wide = half * aspect
    return OrthographicCamera(
        Length(-wide, METER),
        Length(wide, METER),
        Length(half, METER),
        Length(-half, METER),
        near,
        far,
    )
