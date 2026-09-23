# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A placed camera's position and its three axes, for the controls that
move a camera along its own axes and turn it about them.

three.js keeps a camera's orientation in a quaternion, and its controls
call `translateX`, `translateZ` and `quaternion.multiply` on it. A camera
here is placed by `position`, `target` and `up`, and `look_at` makes its
axes from them. `CameraFrame` holds those axes, so that a control can move
and turn the camera as three.js does, and then place it again: the target
straight ahead at the same distance, and `up` the camera's own y.
"""

from cameras.orthographic_camera import OrthographicCamera
from cameras.perspective_camera import PerspectiveCamera
from math.matrix4 import Matrix4
from math.projection import look_at
from math.quaternion import Quaternion
from math.vector3 import Vector3


struct CameraFrame(ImplicitlyCopyable):
    """A camera's position, its right, up and back axes, and how far ahead
    its target is."""

    var position: Vector3
    # The camera's local x, y and z in world space: right, up, and the
    # opposite of where it looks. three.js: the columns of `camera.matrix`.
    var right: Vector3
    var above: Vector3
    var back: Vector3
    # The distance from the camera to its target.
    var reach: Float32

    def __init__(
        out self, position: Vector3, target: Vector3, up: Vector3
    ) raises:
        """Take the frame `look_at` makes for a camera.

        Args:
            position: Where the camera is.
            target: What it looks at.
            up: Which way is up.

        Raises:
            Error: If `look_at` refuses the placement.
        """
        var view = look_at(position, target, up)
        self.position = position
        self.right = Vector3(view.get(0, 0), view.get(0, 1), view.get(0, 2))
        self.above = Vector3(view.get(1, 0), view.get(1, 1), view.get(1, 2))
        self.back = Vector3(view.get(2, 0), view.get(2, 1), view.get(2, 2))
        var offset = target - position
        self.reach = offset.length()

    @staticmethod
    def of(camera: PerspectiveCamera) raises -> CameraFrame:
        """Return a perspective camera's frame.

        Args:
            camera: The camera, placed.

        Returns:
            Its frame.

        Raises:
            Error: If `look_at` refuses the placement.
        """
        return CameraFrame(camera.position, camera.target, camera.up)

    @staticmethod
    def of(camera: OrthographicCamera) raises -> CameraFrame:
        """Return an orthographic camera's frame.

        Args:
            camera: The camera, placed.

        Returns:
            Its frame.

        Raises:
            Error: If `look_at` refuses the placement.
        """
        return CameraFrame(camera.position, camera.target, camera.up)

    def forward(self) -> Vector3:
        """Return where the camera looks. three.js: `getWorldDirection`.

        Returns:
            The unit direction.
        """
        return -self.back

    def target(self) -> Vector3:
        """Return the point straight ahead at the target's distance.

        Returns:
            The point.
        """
        return self.position + self.forward() * self.reach

    def to_world(self, local: Vector3) -> Vector3:
        """Return a direction in the camera's axes as a world direction.

        Args:
            local: Along right, up and back.

        Returns:
            The same direction in world space.
        """
        return self.right * local.x + self.above * local.y + self.back * local.z

    def translate(mut self, local: Vector3):
        """Move the camera along its own axes. three.js: `translateX`,
        `translateY` and `translateZ`.

        Args:
            local: How far along right, up and back, in meters.
        """
        self.position = self.position + self.to_world(local)

    def turn(mut self, rotation: Quaternion):
        """Turn the camera about its own axes. three.js:
        `quaternion.multiply(rotation)`.

        Args:
            rotation: The turn, in the camera's axes. Unit length.
        """
        var right = self.to_world(rotation.rotate(Vector3(1, 0, 0)))
        var above = self.to_world(rotation.rotate(Vector3(0, 1, 0)))
        var back = self.to_world(rotation.rotate(Vector3(0, 0, 1)))
        self.right = right
        self.above = above
        self.back = back

    def rotation(self) -> Matrix4:
        """Return the rotation from the camera's axes to the world's. three.js:
        the rotation part of `camera.matrix`.

        Returns:
            The matrix whose columns are right, up and back.
        """
        var matrix = Matrix4()
        matrix.set(
            self.right.x,
            self.above.x,
            self.back.x,
            0,
            self.right.y,
            self.above.y,
            self.back.y,
            0,
            self.right.z,
            self.above.z,
            self.back.z,
            0,
            0,
            0,
            0,
            1,
        )
        return matrix^

    def place(self, mut camera: PerspectiveCamera):
        """Place a perspective camera as this frame says, its up the frame's.

        Args:
            camera: The camera.
        """
        camera.up = self.above
        camera.place(self.position, self.target())

    def place(self, mut camera: OrthographicCamera):
        """Place an orthographic camera as this frame says, its up the
        frame's.

        Args:
            camera: The camera.
        """
        camera.up = self.above
        camera.place(self.position, self.target())
