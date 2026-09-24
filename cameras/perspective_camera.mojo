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

## Film, zoom and tiles

The rest is three.js's, setting for setting. `zoom` divides the frustum's
height and width about its center. `film_gauge` is the height of the film,
or its width when the image is portrait, and `film_offset` moves the film
across: `set_focal_length` and `get_focal_length` convert between a lens and
the field of view through it. `focus` is carried for a scene's JSON; nothing
here draws differently for it. `set_view_offset` draws one tile of a larger
image. `projection_matrix` builds from all of them in the order three.js's
`updateProjectionMatrix` does.

three.js keeps the film in millimeters by convention and never says so.
Here the gauge and the offset are `Length`s, and only their ratio reaches
the projection.
"""

from cameras.camera import Camera, ViewOffset, node_view_matrix, view_offset
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from math.matrix4 import Matrix4
from math.projection import look_at, perspective, viewport
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import atan, isfinite, max, min, tan
from units.si import Angle, Length, METER, MILLIMETER, RADIAN

# A frustum that looks straight ahead: what a camera has unless asked.
comptime NO_SHIFT = Length(0.0, METER)
# three.js's `filmGauge`: 35 millimeters, the film a 35 mm camera takes.
comptime DEFAULT_FILM_GAUGE = Length(35.0, MILLIMETER)
# three.js's `focus`: ten meters.
comptime DEFAULT_FOCUS_DISTANCE = Length(10.0, METER)


@fieldwise_init
struct ViewBounds(ImplicitlyCopyable):
    """The rectangle a perspective camera sees at one distance, three.js's
    `getViewBounds`: its lower-left and its upper-right corner, in meters
    across and up in the camera's own frame."""

    var min_corner: Vector2
    var max_corner: Vector2


def _positive(value: Float32) -> Bool:
    """Return True if a number is finite and above zero."""
    return value > 0 and isfinite(value)


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
    # How far the view is magnified, three.js's `zoom`: the frustum's
    # height and width are divided by it. One by default.
    var zoom: Float32
    # How far in front of the camera things are in focus, three.js's
    # `focus`. Carried, and written to JSON; nothing here reads it.
    var focus: Length
    # The film's size along its larger axis, three.js's `filmGauge`.
    var film_gauge: Length
    # How far the film is moved across, three.js's `filmOffset`: an
    # off-center projection, as `view_shift` is, measured on the film.
    var film_offset: Length
    # The tile of a larger image this camera draws, three.js's `view`:
    # none until `set_view_offset`. See `cameras.camera.ViewOffset`.
    var view: Optional[ViewOffset]

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
        self.zoom = 1
        self.focus = DEFAULT_FOCUS_DISTANCE
        self.film_gauge = DEFAULT_FILM_GAUGE
        self.film_offset = NO_SHIFT
        self.view = None

    def validate(self) raises:
        """Refuse a zoom, a film, a focus or a tile that is not one.

        The fields are open, so a value can be written that three.js would
        take and turn into a projection of infinities. `projection_matrix`
        asks this first.

        Raises:
            Error: If the zoom, the film gauge or the focus is not
                positive and finite, the film offset is not finite, or an
                enabled view is refused by `ViewOffset.validate`.
        """
        if not _positive(self.zoom):
            raise Error("A camera's zoom must be positive, got ", self.zoom)
        if not _positive(self.film_gauge.value):
            raise Error("A film gauge must be positive")
        if not isfinite(self.film_offset.value):
            raise Error("A film offset must be finite")
        if not _positive(self.focus.value):
            raise Error("A focus distance must be positive")
        if self._tiled():
            self.view.value().validate()

    def _tiled(self) -> Bool:
        """Return True if a view offset is set and enabled."""
        return Bool(self.view) and self.view.value().enabled

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

        The aspect ratio becomes the full image's, as in three.js. Three
        monitors side by side, each 1920 by 1080, are drawn by three
        cameras set to `(5760, 1080, 0, 0, 1920, 1080)`,
        `(5760, 1080, 1920, 0, 1920, 1080)` and
        `(5760, 1080, 3840, 0, 1920, 1080)`.

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
        var view = view_offset(full_width, full_height, x, y, width, height)
        self.aspect = full_width / full_height
        self.view = view

    def clear_view_offset(mut self):
        """Draw the whole image again, three.js's `clearViewOffset`.

        The tile is kept, disabled, as three.js keeps it.
        """
        if Bool(self.view):
            self.view.value().enabled = False

    def get_film_width(self) -> Length:
        """Return how wide the film's image is, three.js's `getFilmWidth`.

        Returns:
            The gauge, or less for a portrait image, which does not cover
            the film across.
        """
        return self.film_gauge.scaled(min(self.aspect, Float32(1)))

    def get_film_height(self) -> Length:
        """Return how tall the film's image is, three.js's `getFilmHeight`.

        Returns:
            The gauge, or less for a landscape image, which does not cover
            the film up and down.
        """
        return Length(
            self.film_gauge.value / max(self.aspect, Float32(1)), METER
        )

    def get_focal_length(self) -> Length:
        """Return the focal length of the lens that sees `fov` on this
        film, three.js's `getFocalLength`.

        Returns:
            The focal length, in the film's own units: about 50 mm for 40
            degrees on the default 35 mm gauge, square.
        """
        var slope = tan(self.fov.to(RADIAN) / 2)
        return Length(0.5 * self.get_film_height().value / slope, METER)

    def set_focal_length(mut self, focal_length: Length) raises:
        """Set the field of view to what a lens of `focal_length` sees on
        this film, three.js's `setFocalLength`.

        Args:
            focal_length: The lens's focal length.

        Raises:
            Error: If the focal length or the film gauge is not positive
                and finite.
        """
        if not _positive(focal_length.value):
            raise Error("A focal length must be positive")
        if not _positive(self.film_gauge.value):
            raise Error("A film gauge must be positive")
        var slope = 0.5 * self.get_film_height().value / focal_length.value
        self.fov = Angle(2 * atan(slope), RADIAN)

    def get_effective_fov(self) -> Angle:
        """Return the vertical field of view once `zoom` is applied,
        three.js's `getEffectiveFOV`.

        Returns:
            The narrower angle a zoom above one leaves.
        """
        var slope = tan(self.fov.to(RADIAN) / 2) / self.zoom
        return Angle(2 * atan(slope), RADIAN)

    def get_view_bounds(self, distance: Length) raises -> ViewBounds:
        """Return the rectangle this camera sees at `distance` in front of
        it, three.js's `getViewBounds`.

        The projection's corners are carried back through its inverse, so
        zoom, film offset, view shift and tile all move the rectangle.

        Args:
            distance: How far in front of the camera.

        Returns:
            Its lower-left and upper-right corners, across and up.

        Raises:
            Error: If the projection cannot be built.
        """
        var inverse = self.projection_matrix()
        inverse.invert()
        var low = inverse.transform_point(Vector3(-1, -1, 0.5))
        var high = inverse.transform_point(Vector3(1, 1, 0.5))
        var reach = distance.value
        return ViewBounds(
            Vector2(low.x, low.y) * (-reach / low.z),
            Vector2(high.x, high.y) * (-reach / high.z),
        )

    def get_view_size(self, distance: Length) raises -> Vector2:
        """Return how wide and how tall the view is at `distance`,
        three.js's `getViewSize`.

        Args:
            distance: How far in front of the camera.

        Returns:
            The width and the height, in meters.

        Raises:
            Error: If the projection cannot be built.
        """
        var bounds = self.get_view_bounds(distance)
        return bounds.max_corner - bounds.min_corner

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
        """Return the matrix taking camera space to normalized device space,
        three.js's `updateProjectionMatrix`.

        The top edge is found from half the field of view, divided by the
        zoom, and the width follows from it and the aspect ratio. An
        enabled view offset then cuts its tile out of that, and the film
        offset moves both side edges, as in three.js. Last the side edges
        are moved by `view_shift`, which keeps the frustum's width and
        skews it: the symmetric frustum is the shift of zero.

        Returns:
            The projection matrix.

        Raises:
            Error: If `validate` refuses the settings, or the frustum works
                out degenerate.
        """
        self.validate()
        var near = self.near.value
        var top = near * tan(self.fov.value / 2) / self.zoom
        var height = 2 * top
        var width = self.aspect * height
        var left = -0.5 * width
        if self._tiled():
            var view = self.view.value()
            left += view.offset_x * width / view.full_width
            top -= view.offset_y * height / view.full_height
            width *= view.width / view.full_width
            height *= view.height / view.full_height
        var skew = self.film_offset.value
        if skew != 0:
            left += near * skew / self.get_film_width().value
        left += self.view_shift.value
        return perspective(
            left,
            left + width,
            top,
            top - height,
            near,
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
