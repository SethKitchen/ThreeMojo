# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Six cameras at one point, from three.js `src/cameras/CubeCamera.js`.

A cube camera stands at one point and looks out along each axis in turn,
six square views with a ninety degree field of view that together see
everything around it. What the six see is a `CubeTexture`, the environment
from that point, which is what a mirror ball reflects: three.js's
`CubeCamera.update(renderer, scene)` renders the six into a cube render
target, and `Renderer.render_cube` renders them into six images and returns
the cube texture built from them.

**The faces are what `render.cube_texture` reads.** Each face camera looks
along `face_forward` with `face_up` as its up, which is three.js's own
table of six ups, and the sampler reads the faces back with the same two
tables. So a cube rendered here reflects the scene it was rendered from with
no flip in between; see `render.cube_texture`.

three.js's face cameras have a field of view of minus ninety degrees, which
turns each view a half turn, and WebGL stores a render from the bottom row
up. A face of three.js's cube render target is thus a face here with each
row mirrored. It samples it with `flipEnvMap` of one, through OpenGL's
left-handed table, so each texel stands for the same direction in both.

**The mirror hides itself with layers.** A cube camera at the center of a
sphere sees the inside of the sphere and nothing else. three.js's examples
set the sphere's `visible` off around the update; here the camera has
`layers` of its own, as every camera has, and a mesh on a layer the cube
camera does not draw is not in its faces. Put the mirror on a layer of its
own and the main camera on both.

The camera is placed by `position` alone, since it looks every way at
once, or rides a scene node as the other cameras can. `near` and `far` are
a `Length`, as every camera's are.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from math.vector3 import Vector3
from render.cube_texture import FACE_COUNT, face_forward, face_up
from units.si import Angle, DEGREE, Length

# Each face sees a quarter turn across, so six faces see everything.
comptime FACE_FOV = Angle(90.0, DEGREE)


struct CubeCamera(ImplicitlyCopyable):
    """A camera that sees everything around one point, as six faces."""

    var near: Length
    var far: Length
    # The width and height of each face, in pixels: three.js's
    # `WebGLCubeRenderTarget` size.
    var size: Int
    var position: Vector3
    # The scene node this camera rides, or `NO_PARENT` for a placed one.
    # While attached, `position` is not read.
    var node: NodeId
    # Which layers the six faces draw, three.js's `camera.layers`, copied
    # to each face camera. Layer zero alone until told otherwise.
    var layers: Layers

    def __init__(out self, near: Length, far: Length, size: Int) raises:
        """Create a cube camera at the origin, drawing layer zero.

        Args:
            near: Distance to each face's near clipping plane.
            far: Distance to each face's far clipping plane.
            size: The width and height of each face, in pixels.

        Raises:
            Error: If the size is not positive, the near plane is not in
                front of the camera, or the far plane is not beyond it.
        """
        if size <= 0:
            raise Error("A cube camera's faces need a positive size")
        if near.value <= 0:
            raise Error("The near plane must be in front of the camera")
        if far.value <= near.value:
            raise Error("The far plane must be beyond the near plane")
        self.near = near
        self.far = far
        self.size = size
        self.position = Vector3(0, 0, 0)
        self.node = NO_PARENT
        self.layers = Layers()

    def place(mut self, position: Vector3):
        """Move the camera to `position`, letting go of any node it rode.

        Args:
            position: Where the camera stands, in world space.
        """
        self.position = position
        self.node = NO_PARENT

    def attach(mut self, node: NodeId):
        """Ride `node`, standing wherever the scene puts it.

        Only the node's world position is read: the six faces look along
        the world axes whichever way the node is turned, as three.js's do,
        since a cube texture is sampled in world space.

        Args:
            node: The scene node to ride.
        """
        self.node = node

    def eye(self, scene: Scene) raises -> Vector3:
        """Return where the camera stands, in world space.

        Args:
            scene: The scene, updated, for a camera riding one of its nodes.

        Returns:
            `position` for a placed camera, or the node's world origin.

        Raises:
            Error: If the node is not in the scene, or the scene is stale.
        """
        if self.node == NO_PARENT:
            return self.position
        return scene.world_position(self.node)

    def face_camera(self, face: Int, scene: Scene) raises -> PerspectiveCamera:
        """Return the camera that draws one face.

        A square ninety degree view from where this camera stands, looking
        along `face_forward` with `face_up` up and drawing this camera's
        layers: what `Renderer.render_cube` renders each face through.

        Args:
            face: `POSITIVE_X` through `NEGATIVE_Z`.
            scene: The scene, updated, for a camera riding one of its nodes.

        Returns:
            The face's camera, placed.

        Raises:
            Error: If the face is none of the six, the node is not in the
                scene, or the scene is stale.
        """
        if face < 0 or face >= FACE_COUNT:
            raise Error("A cube has six faces")
        var camera = PerspectiveCamera(FACE_FOV, 1.0, self.near, self.far)
        var stand = self.eye(scene)
        camera.up = face_up(face)
        camera.place(stand, stand + face_forward(face))
        camera.layers = self.layers
        return camera^
