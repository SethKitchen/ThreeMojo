# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What a `CSM` cuts and where its lights look, drawn as lines and planes,
from three.js `examples/jsm/csm/CSMHelper.js`.

`CSMHelper.lines` gives three parts as segments in world space:

- The camera's frustum as the cascades see it, out to `max_far`: its far
  and near rectangles and the four edges between them. White.
- A box around each cascade's far rectangle, one ten-thousandth of a meter
  deep. White.
- Each cascade light's shadow box: what its shadow camera sees. Yellow.

`CSMHelper.planes` gives a see-through rectangle on each cascade's far
face, one geometry per cascade, for `csm_plane_material`.

The three switches are three.js's `displayFrustum`, `displayPlanes` and
`displayShadowBounds`. The frustum switch shows the frustum, the cascade
boxes and, with the planes switch, the planes.

**Where this differs from three.js.** three.js's helper is a group that
copies the camera's position, turn and scale; here the parts come out in
world space, through the camera's world frame. They are the same for a
camera outside a group. three.js takes each shadow box from its light's
shadow camera, which a render moves; so its boxes lag the lights by a
frame. Here each box is where the light stands now, which is where the
next render puts it. three.js's `updateVisibility` is gone: the switches
are read at each call.

three.js sets a shadow box from `bottom` to `top` along x and from `left`
to `right` along y, the two swapped. A `CSM` keeps its shadow cameras
square, so the swap moves nothing. This keeps it.
"""

from cameras.camera import Camera
from cameras.orthographic_camera import OrthographicCamera
from core.buffer_geometry import BufferGeometry
from core.scene import Scene
from geometries.plane import plane
from helpers.box import append_box_edges
from helpers.segments import Segments
from lights.csm import CSM
from materials.material import BASIC, DOUBLE_SIDE, Material
from math.bounds import Box3
from math.matrix4 import Matrix4, compose
from math.quaternion import Quaternion
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from units.si import Length, METER

# three.js's colors: white for the frustum and the cascades, yellow for the
# shadow boxes.
comptime CSM_FRUSTUM_COLOR = Color(0xFF, 0xFF, 0xFF)
comptime CSM_SHADOW_COLOR = Color(0xFF, 0xFF, 0x00)
# How thick a cascade's box and plane are, three.js's `1e-4`.
comptime CSM_SLAB = Float32(1.0e-4)
# How much of what is behind a cascade plane shows through it.
comptime CSM_PLANE_OPACITY = Float32(0.1)


def csm_plane_material() raises -> Material:
    """Return the material three.js draws the cascade planes with.

    Returns:
        White and unlit, a tenth opaque, both sides drawn, and no depth
        written.

    Raises:
        Error: Never; the settings are in range.
    """
    var material = Material(
        Color(255, 255, 255),
        kind=BASIC,
        opacity=CSM_PLANE_OPACITY,
        transparent=True,
    )
    material.side = DOUBLE_SIDE
    material.depth_write = False
    return material^


struct CSMHelper(Copyable, Movable):
    """Draws a `CSM`'s frustum, cascades and shadow boxes, three.js's
    `CSMHelper`."""

    # three.js's `displayFrustum`: the frustum and the cascade boxes.
    var display_frustum: Bool
    # three.js's `displayPlanes`: the cascade planes, if the frustum shows.
    var display_planes: Bool
    # three.js's `displayShadowBounds`: the shadow boxes.
    var display_shadow_bounds: Bool

    def __init__(out self):
        """Show everything, three.js's defaults."""
        self.display_frustum = True
        self.display_planes = True
        self.display_shadow_bounds = True

    def lines[
        C: Camera
    ](self, csm: CSM, scene: Scene, camera: C) raises -> BufferGeometry:
        """Return the frustum, the cascade boxes and the shadow boxes as
        segments in world space, three.js's `update`.

        Args:
            csm: The cascades, after `update`.
            scene: The scene holding the cascades' lights, updated.
            camera: The camera the cascades slice.

        Returns:
            Two points a segment, with a `color` attribute in linear
            light, in three.js's order: the frustum's twelve edges, then
            for each cascade its box's twelve and its shadow box's twelve.

        Raises:
            Error: If a cascade's light or its target is gone from the
                scene, or the camera's view is refused.
        """
        var segments = Segments()
        var world = _camera_world(camera, scene)
        var white = FloatColor(srgb=CSM_FRUSTUM_COLOR)
        var yellow = FloatColor(srgb=CSM_SHADOW_COLOR)
        if self.display_frustum:
            ref main = csm.main_frustum
            var corners: List[Vector3] = [
                main.far[0],
                main.far[3],
                main.far[2],
                main.far[1],
                main.near[0],
                main.near[3],
                main.near[2],
                main.near[1],
            ]
            var edges: List[Int] = [
                0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4,
                0, 4, 1, 5, 2, 6, 3, 7,
            ]  # fmt: skip
            # Twelve edges, always.
            for at in range(0, len(edges), 2):  # pragma: no branch
                segments.add(
                    world.transform_point(corners[edges[at]]),
                    world.transform_point(corners[edges[at + 1]]),
                    white,
                )
        # A `CSM` has at least one cascade.
        for index in range(csm.cascades):  # pragma: no branch
            if self.display_frustum:
                ref far = csm.frustums[index].far
                var top = far[0]
                top.z += CSM_SLAB
                _box(segments, Box3(far[2], top), world, white)
            if self.display_shadow_bounds:
                ref light = scene.lights[csm.lights[index]]
                ref shadow = light.shadow
                var eye = OrthographicCamera(
                    shadow.left,
                    shadow.right,
                    shadow.top,
                    shadow.bottom,
                    shadow.near,
                    shadow.far,
                )
                eye.place(
                    scene.world_position(light.node),
                    scene.world_position(light.target),
                )
                var bounds = Box3(
                    Vector3(
                        shadow.bottom.to(METER),
                        shadow.left.to(METER),
                        -shadow.far.to(METER),
                    ),
                    Vector3(
                        shadow.top.to(METER),
                        shadow.right.to(METER),
                        -shadow.near.to(METER),
                    ),
                )
                _box(segments, bounds, _camera_world(eye, scene), yellow)
        return segments.geometry()

    def planes[
        C: Camera
    ](self, csm: CSM, scene: Scene, camera: C) raises -> List[BufferGeometry]:
        """Return a rectangle on each cascade's far face, in world space,
        three.js's `cascadePlanes`.

        Args:
            csm: The cascades, after `update_frustums`.
            scene: The scene the camera can ride, updated.
            camera: The camera the cascades slice.

        Returns:
            One two-triangle geometry per cascade, for
            `csm_plane_material`. None unless the frustum and the planes
            both show.

        Raises:
            Error: If the camera's view is refused.
        """
        var shown = List[BufferGeometry]()
        if not (self.display_frustum and self.display_planes):
            return shown^
        var world = _camera_world(camera, scene)
        # A `CSM` has at least one cascade.
        for index in range(csm.cascades):  # pragma: no branch
            ref far = csm.frustums[index].far
            var size = far[0] - far[2]
            var place = world
            place.multiply(
                compose(
                    (far[0] + far[2]) * 0.5,
                    Quaternion.identity(),
                    Vector3(size.x, size.y, CSM_SLAB),
                )
            )
            var face = plane(Length(1.0, METER), Length(1.0, METER))
            face.apply_matrix4(place)
            shown.append(face^)
        return shown^


def _camera_world[C: Camera](camera: C, scene: Scene) raises -> Matrix4:
    """Return a camera's world frame: its view turned back."""
    var world = camera.view_matrix_in(scene)
    world.invert()
    return world


def _box(mut segments: Segments, box: Box3, world: Matrix4, color: FloatColor):
    """Add a box's twelve edges, carried to the world, three.js's
    `Box3Helper`."""
    var ends = List[Float32]()
    append_box_edges(ends, box)
    # Twelve edges, always.
    for at in range(0, len(ends), 6):  # pragma: no branch
        segments.add(
            world.transform_point(
                Vector3(ends[at], ends[at + 1], ends[at + 2])
            ),
            world.transform_point(
                Vector3(ends[at + 3], ends[at + 4], ends[at + 5])
            ),
            color,
        )
