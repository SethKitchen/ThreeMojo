# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two eyes made from one camera, from three.js `src/cameras/StereoCamera.js`.

A stereo pair is one camera moved half an eye's separation to each side,
with each eye's frustum skewed back toward the shared point of focus so
the two images converge there: three.js's `StereoCamera.update`. This is
that arithmetic, and it produces two placed `PerspectiveCamera`s, `left`
and `right`, to draw with -- through an `ArrayCamera` for a side-by-side
image, or one at a time.

## The arithmetic

three.js's, term for term. Each eye is offset along the camera's own x
axis by half `eye_separation`. Each eye's projection is the camera's,
with both side edges moved at the near plane by

    eye_separation / 2 * near / focus

toward the other eye, so the two frustums cross at `focus`: the left
eye's edges move right and the right eye's move left. That is the
`view_shift` a `PerspectiveCamera` carries, and the reason it carries
one. The field of view, the planes and the layers are the camera's own;
the aspect is the camera's times this camera's `aspect`, which three.js
keeps at one and a side-by-side image sets to a half.

## Where the eyes look

three.js sets each eye's world matrix to the camera's times an offset,
so an eye looks where the camera looks, only from a little to one side.
`update` reads the camera's view from the scene, as `Renderer` does, so
a camera riding a node is handled as a placed one is, and places each
eye to look along the camera's own forward with its own up.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.scene import Scene
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from units.si import Angle, DEGREE, Length, METER

# three.js's `eyeSep`: the distance between two human eyes.
comptime DEFAULT_EYE_SEPARATION = Length(0.064, METER)
# three.js's `PerspectiveCamera.focus`: where the two eyes converge.
comptime DEFAULT_FOCUS = Length(10.0, METER)


struct StereoCamera(Movable):
    """A left and a right eye, made from one camera by `update`."""

    # How far apart the eyes are.
    var eye_separation: Length
    # How far in front of the camera the two eyes' views cross.
    var focus: Length
    # What the camera's aspect is multiplied by for each eye: one for two
    # whole images, a half for a side-by-side pair in one image.
    var aspect: Float32
    # The two eyes, as `update` last placed them.
    var left: PerspectiveCamera
    var right: PerspectiveCamera

    def __init__(
        out self,
        eye_separation: Length = DEFAULT_EYE_SEPARATION,
        focus: Length = DEFAULT_FOCUS,
        aspect: Float32 = 1.0,
    ) raises:
        """Create a stereo camera whose eyes have not been placed yet.

        Args:
            eye_separation: How far apart the eyes are. three.js's default
                is 64 millimeters.
            focus: How far in front of the camera the eyes' views cross.
                three.js's default is ten meters.
            aspect: What the camera's aspect is multiplied by for each
                eye. One, the default, as in three.js.

        Raises:
            Error: If the separation is negative, or the focus or the
                aspect is not positive.
        """
        if eye_separation.value < 0:
            raise Error("An eye separation cannot be negative")
        if focus.value <= 0:
            raise Error("A stereo focus must be in front of the camera")
        if aspect <= 0:
            raise Error("A stereo aspect must be positive")
        self.eye_separation = eye_separation
        self.focus = focus
        self.aspect = aspect
        # Placeholders until `update`: three.js's `cameraL` and `cameraR`
        # are default cameras too until the first update.
        self.left = PerspectiveCamera(
            Angle(50.0, DEGREE), 1.0, Length(0.1, METER), Length(2000.0, METER)
        )
        self.right = self.left

    def update(mut self, camera: PerspectiveCamera, scene: Scene) raises:
        """Place both eyes from `camera` as it stands.

        Args:
            camera: The camera between the eyes: its field of view, its
                planes, its layers, and where it is and which way it
                faces. Placed, or riding a node of `scene`.
            scene: The scene, updated, for a camera riding a node.

        Raises:
            Error: If the camera's view cannot be read -- see
                `PerspectiveCamera.view_matrix_in` -- or an eye's frustum
                is degenerate.
        """
        # The camera's own frame in the world: the inverse of its view.
        var to_world = camera.view_matrix_in(scene)
        to_world.invert()
        ref e = to_world.elements
        var across = Vector3(e[0], e[1], e[2])
        var up = Vector3(e[4], e[5], e[6])
        # The camera looks down its own -z.
        var forward = Vector3(-e[8], -e[9], -e[10])
        var eye = Vector3(e[12], e[13], e[14])
        var half = self.eye_separation.value / 2
        # How far each frustum's edges move at the near plane so the two
        # cross at the focus: three.js's `eyeSepOnProjection`.
        var skew = Length(half * camera.near.value / self.focus.value, METER)
        var aspect = camera.aspect * self.aspect
        self.left = _eye(camera, aspect, skew, eye - across * half, forward, up)
        self.right = _eye(
            camera, aspect, -skew, eye + across * half, forward, up
        )


def _eye(
    camera: PerspectiveCamera,
    aspect: Float32,
    shift: Length,
    position: Vector3,
    forward: Vector3,
    up: Vector3,
) raises -> PerspectiveCamera:
    """Return one eye: the camera's frustum at `aspect`, skewed by `shift`,
    placed at `position` looking along `forward`."""
    var eye = PerspectiveCamera(
        camera.fov, aspect, camera.near, camera.far, view_shift=shift
    )
    eye.place(position, position + forward)
    eye.up = up
    eye.layers = camera.layers
    return eye^
