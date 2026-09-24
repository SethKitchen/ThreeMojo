# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The axes of a camera's view in a corner of the image, from three.js
`examples/jsm/helpers/ViewHelper.js`.

Three sticks and six disks, drawn in a square of `VIEW_HELPER_DIM` pixels
in the bottom right corner, turned against the camera so they show which
way the world's axes point. The x, y and z sticks are red, green and blue,
and a colored disk ends each. A faint black disk marks each negative axis.
A click on a disk turns the camera, over time, to look along that axis at
`center` from where it stands.

**The camera.** three.js reads and writes `camera.position` and
`camera.quaternion`. A camera here is placed by a position, a target and
an up, so the helper reads and writes a `controls.camera_frame.CameraFrame`:
take one with `CameraFrame.of(camera)`, and put it back with
`CameraFrame.place(camera)`. The frame's `reach`, the distance to its
target, is kept.

**Drawing.** three.js clears the depth and draws the helper into a
viewport over the image. Here `render` draws it into a target of its own,
cleared to a transparent black, and blends that over the corner of the
image, pixel by pixel, as source over. The blend of the helper's own
translucent disks over transparent black, then over the image, is the
blend of each over the image, so the result is the same.

**The click.** three.js casts a ray from its orthographic camera through
the click and asks which disk sprite it meets first. The camera looks
straight down -z, so a sprite is a square one unit wide at its position,
facing the camera, and the ray meets it where the click falls inside that
square. `axis_at` asks that of each disk, and takes the nearest the
camera, the first in three.js's order on a tie.

**Not ported.** `setLabels` and `setLabelStyle`, which write text onto the
disks with a 2D canvas. This port has no canvas text. The disks are
unlabeled, as three.js's are by default. `dispose` has no counterpart.
"""

from cameras.orthographic_camera import OrthographicCamera
from controls.camera_frame import CameraFrame
from core.assets import Assets
from core.object3d import NodeId, Object3D, facing
from core.scene import Scene
from geometries.cylinder import cylinder
from materials.material import BASIC, Material, sprite_material
from math.euler import Euler, XYZ
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.sprite import Sprite
from render.blend import NORMAL_MODE
from render.framebuffer import Color
from render.target import RenderTarget
from render.texture import BILINEAR, CLAMP, Texture
from render.srgb import SRGB
from renderers.renderer import Renderer
from std.math import pi
from units.si import Angle, Duration, Length, METER, RADIAN, SECOND


@fieldwise_init
struct ViewAxis(Equatable, ImplicitlyCopyable, Writable):
    """Which disk of the view helper, as a type rather than a bare int:
    three.js's `userData.type` of `posX` to `negZ`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the six disks.

        Returns:
            Whether it is `POSITIVE_X` through `NEGATIVE_Z`.
        """
        return self.value >= 0 and self.value <= 5


# three.js's `posX`, `posY`, `posZ`, `negX`, `negY` and `negZ`, in the
# order of its `interactiveObjects`.
comptime POSITIVE_X = ViewAxis(0)
comptime POSITIVE_Y = ViewAxis(1)
comptime POSITIVE_Z = ViewAxis(2)
comptime NEGATIVE_X = ViewAxis(3)
comptime NEGATIVE_Y = ViewAxis(4)
comptime NEGATIVE_Z = ViewAxis(5)

# How many pixels wide and tall the helper's square is, three.js's `dim`.
comptime VIEW_HELPER_DIM = 128
# How fast the camera turns toward an axis, three.js's `turnRate`: a full
# turn a second.
comptime VIEW_HELPER_TURN_RATE = Float32(2 * pi)
# The texels across a disk's image, and the disk's radius and center in
# them: three.js's 64 by 64 canvas and its `arc( 32, 32, 14 )`.
comptime DISK_IMAGE_SIZE = 64
comptime DISK_RADIUS = Float32(14)
comptime DISK_CENTER = Float32(32)
# How many samples a side each texel of a disk is measured with, for the
# smooth edge a canvas draws.
comptime DISK_SAMPLES = 4
# The opacity of the negative disks, three.js's `0.2`.
comptime NEGATIVE_DISK_OPACITY = Float32(0.2)


def axis_direction(axis: ViewAxis) raises -> Vector3:
    """Return the unit direction a disk stands in.

    Args:
        axis: The disk.

    Returns:
        +x, +y, +z, -x, -y or -z.

    Raises:
        Error: If the axis is none of the six.
    """
    if not axis.is_valid():
        raise Error("A view axis that is none of the six")
    var directions: List[Vector3] = [
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
        Vector3(-1, 0, 0),
        Vector3(0, -1, 0),
        Vector3(0, 0, -1),
    ]
    return directions[axis.value]


def axis_turn(axis: ViewAxis) raises -> Quaternion:
    """Return how a camera is turned to look along a disk's axis toward the
    center: three.js's `targetQuaternion` in `prepareAnimationData`.

    Args:
        axis: The disk.

    Returns:
        The rotation from three.js's Euler angles for that disk.

    Raises:
        Error: If the axis is none of the six.
    """
    if not axis.is_valid():
        raise Error("A view axis that is none of the six")
    var half = Float32(pi * 0.5)
    var angles: List[Vector3] = [
        Vector3(0, half, 0),
        Vector3(-half, 0, 0),
        Vector3(0, 0, 0),
        Vector3(0, -half, 0),
        Vector3(half, 0, 0),
        Vector3(0, Float32(pi), 0),
    ]
    var turn = angles[axis.value]
    return Euler(
        Angle(turn.x, RADIAN), Angle(turn.y, RADIAN), Angle(turn.z, RADIAN), XYZ
    ).to_quaternion()


def disk_image(color: Color) raises -> Texture:
    """Return the image of one disk: three.js's 64 by 64 canvas with a
    filled circle of radius 14 at its center.

    Each texel's alpha is how much of it the circle covers, measured at
    `DISK_SAMPLES` by `DISK_SAMPLES` points, as a canvas smooths the edge.
    Its color is `color` wherever the alpha is not zero, as WebGL reads a
    canvas back with its alpha divided out.

    Args:
        color: The fill, as authored in sRGB.

    Returns:
        The texture, `SRGB`, bilinear, with a mip chain, as three.js's
        `CanvasTexture` is.

    Raises:
        Error: If the texture cannot be built.
    """
    var pixels = List[UInt8]()
    var reach = DISK_RADIUS * DISK_RADIUS
    for row in range(DISK_IMAGE_SIZE):  # pragma: no branch
        for column in range(DISK_IMAGE_SIZE):  # pragma: no branch
            var inside = 0
            for i in range(DISK_SAMPLES):  # pragma: no branch
                for j in range(DISK_SAMPLES):  # pragma: no branch
                    var x = (
                        Float32(column)
                        + (Float32(i) + 0.5) / Float32(DISK_SAMPLES)
                        - DISK_CENTER
                    )
                    var y = (
                        Float32(row)
                        + (Float32(j) + 0.5) / Float32(DISK_SAMPLES)
                        - DISK_CENTER
                    )
                    if x * x + y * y <= reach:
                        inside += 1
            var alpha = UInt8(
                (inside * 255 + DISK_SAMPLES * DISK_SAMPLES // 2)
                // (DISK_SAMPLES * DISK_SAMPLES)
            )
            if alpha == 0:
                pixels.append(0)
                pixels.append(0)
                pixels.append(0)
            else:
                pixels.append(color.r)
                pixels.append(color.g)
                pixels.append(color.b)
            pixels.append(alpha)
    return Texture(
        DISK_IMAGE_SIZE, DISK_IMAGE_SIZE, pixels^, CLAMP, BILINEAR, SRGB, True
    )


def _turn_towards(
    mut turn: Quaternion, target: Quaternion, step: Angle
) -> Bool:
    """Turn toward `target` by at most `step`, three.js's `rotateTowards`,
    and return whether the turn has arrived.

    three.js's `slerp` returns its end exactly at a fraction of one, so
    its `angleTo` then reads zero. `Quaternion.slerp` here computes that
    end, and in `Float32` the angle to it need not read zero. So the end is
    taken exactly here, and arriving is said rather than measured.
    """
    var angle = turn.angle_to(target).to(RADIAN)
    if angle == 0:
        return True
    if step.to(RADIAN) >= angle:
        turn = target
        return True
    turn = turn.slerp(target, step.to(RADIAN) / angle)
    return False


struct ViewHelper(Movable):
    """Axes that show which way a camera looks, and turn it to look along
    one. three.js: `ViewHelper`."""

    # The point the camera turns around, three.js's `center`.
    var center: Vector3
    # Whether a turn is under way, three.js's `animating`. `update` turns
    # the camera while it is set, and clears it on arrival.
    var animating: Bool
    # The helper's own scene, assets and camera: three.js's helper is an
    # `Object3D` drawn through an `OrthographicCamera( -2, 2, 2, -2, 0, 4 )`.
    var scene: Scene
    var assets: Assets
    var camera: OrthographicCamera
    # The node every part hangs from, three.js's `ViewHelper` itself.
    var root: NodeId
    # three.js's `radius`, `q1`, `q2` and `targetQuaternion`.
    var _radius: Float32
    var _q1: Quaternion
    var _q2: Quaternion
    var _target: Quaternion

    def __init__(out self) raises:
        """Build the sticks and the disks, as three.js's constructor does.

        Raises:
            Error: If a part cannot be built.
        """
        self.center = Vector3(0, 0, 0)
        self.animating = False
        self._radius = 0
        self._q1 = Quaternion.identity()
        self._q2 = Quaternion.identity()
        self._target = Quaternion.identity()
        self.scene = Scene()
        self.assets = Assets()
        self.camera = OrthographicCamera(
            Length(-2.0, METER),
            Length(2.0, METER),
            Length(2.0, METER),
            Length(-2.0, METER),
            Length(0.0, METER),
            Length(4.0, METER),
        )
        self.camera.place(Vector3(0, 0, 2), Vector3(0, 0, 0))
        self.root = self.scene.add(Object3D())
        var colors: List[Color] = [
            Color(0xFF, 0x44, 0x66),
            Color(0x88, 0xFF, 0x44),
            Color(0x44, 0x88, 0xFF),
        ]
        # three.js's `CylinderGeometry( 0.04, 0.04, 0.8, 5 )`, turned onto
        # +x and moved to start at the origin. The turn and the move are a
        # node under each stick's node rather than baked into the points.
        var stick = self.assets.geometries.add(
            cylinder(
                Length(0.04, METER), Length(0.04, METER), Length(0.8, METER), 5
            )
        )
        var turns: List[Vector3] = [
            Vector3(0, 0, 0),
            Vector3(0, 0, Float32(pi / 2)),
            Vector3(0, Float32(-pi / 2), 0),
        ]
        # three.js adds x, then z, then y.
        var added: List[Int] = [0, 2, 1]
        for index in added:  # pragma: no branch
            var axis = Object3D()
            axis.parent = self.root
            var turn = turns[index]
            axis.set_euler(
                Angle(turn.x, RADIAN),
                Angle(turn.y, RADIAN),
                Angle(turn.z, RADIAN),
            )
            var holder = self.scene.add(axis^)
            var laid = Object3D()
            laid.parent = holder
            laid.set_position(0.4, 0, 0)
            laid.set_euler(
                Angle(0.0, RADIAN), Angle(0.0, RADIAN), Angle(-pi / 2, RADIAN)
            )
            var placed = self.scene.add(laid^)
            var paint = self.assets.materials.add(
                Material(colors[index], kind=BASIC)
            )
            self.scene.add_mesh(Mesh(stick, paint, placed))
        var negative = self.assets.materials.add(
            sprite_material(
                map=self.assets.textures.add(disk_image(Color(0, 0, 0))),
                opacity=NEGATIVE_DISK_OPACITY,
            )
        )
        for index in range(6):  # pragma: no branch
            var disk = Object3D()
            disk.parent = self.root
            var at = axis_direction(ViewAxis(index))
            disk.set_position(at.x, at.y, at.z)
            var node = self.scene.add(disk^)
            var paint = negative
            if index < 3:
                paint = self.assets.materials.add(
                    sprite_material(
                        map=self.assets.textures.add(disk_image(colors[index]))
                    )
                )
            self.scene.add_sprite(Sprite(paint, node))
        self.scene.update()

    def _orient(mut self, camera: CameraFrame) raises:
        """Turn the helper against the camera, as three.js's `render` sets
        its quaternion to the camera's, inverted."""
        var turn = Quaternion.from_matrix(camera.rotation())
        turn.invert()
        self.scene.node(self.root).quaternion = turn
        self.scene.update()

    def render(
        mut self,
        mut target: RenderTarget,
        camera: CameraFrame,
        workers: Int = 1,
    ) raises:
        """Draw the helper over the bottom right corner of a target, as
        three.js's `render` draws it into a viewport there.

        Args:
            target: The image to draw over. A target smaller than the
                helper gets the part of it that fits.
            camera: The camera the image was drawn through.
            workers: How many threads rasterize the helper.

        Raises:
            Error: If `workers` is less than one or the helper cannot be
                drawn.
        """
        self._orient(camera)
        var renderer = Renderer(VIEW_HELPER_DIM, VIEW_HELPER_DIM, workers)
        renderer.set_background(Color(0, 0, 0, 0))
        var drawn = RenderTarget(
            VIEW_HELPER_DIM, VIEW_HELPER_DIM, Color(0, 0, 0, 0)
        )
        renderer.render_into(drawn, self.scene, self.assets, self.camera)
        var left = target.width - VIEW_HELPER_DIM
        var top = target.height - VIEW_HELPER_DIM
        for row in range(VIEW_HELPER_DIM):  # pragma: no branch
            for column in range(VIEW_HELPER_DIM):  # pragma: no branch
                var x = left + column
                var y = top + row
                if x < 0 or y < 0:
                    continue
                target.blend(
                    x,
                    y,
                    drawn.straight_at(row * VIEW_HELPER_DIM + column),
                    NORMAL_MODE,
                )

    def axis_at(
        mut self,
        x: Float32,
        y: Float32,
        width: Int,
        height: Int,
        camera: CameraFrame,
    ) raises -> Optional[ViewAxis]:
        """Return the disk under a point of the image, if any: the hit
        test of three.js's `handleClick`.

        Args:
            x: Where the point is, in pixels from the image's left edge.
            y: Where the point is, in pixels from the image's top edge.
            width: The image's width in pixels.
            height: The image's height in pixels.
            camera: The camera the image was drawn through.

        Returns:
            The disk nearest the helper's camera under the point, or none.

        Raises:
            Error: If the image has no size.
        """
        if width <= 0 or height <= 0:
            raise Error("A view helper needs an image with a size")
        self._orient(camera)
        var dim = Float32(VIEW_HELPER_DIM)
        # three.js's `mouse`, from the corner the helper is drawn in.
        var mouse_x = (x - (Float32(width) - dim)) / dim * 2 - 1
        var mouse_y = -((y - (Float32(height) - dim)) / dim) * 2 + 1
        # The ray starts on the near plane, two meters in front of the
        # disks' center, and runs down -z.
        var ray_x = mouse_x * 2
        var ray_y = mouse_y * 2
        var found = Optional[ViewAxis]()
        var nearest = Float32(0)
        var turn = self.scene.world_quaternion(self.root)
        for index in range(6):  # pragma: no branch
            var at = turn.rotate(axis_direction(ViewAxis(index)))
            var inside = abs(ray_x - at.x) <= 0.5 and abs(ray_y - at.y) <= 0.5
            var distance = 2 - at.z
            var first = not Bool(found)
            if inside and (first or distance < nearest):
                found = ViewAxis(index)
                nearest = distance
        return found

    def handle_click(
        mut self,
        x: Float32,
        y: Float32,
        width: Int,
        height: Int,
        camera: CameraFrame,
    ) raises -> Bool:
        """Start a turn toward the disk under a click, three.js's
        `handleClick`.

        Args:
            x: Where the click is, in pixels from the image's left edge.
            y: Where the click is, in pixels from the image's top edge.
            width: The image's width in pixels.
            height: The image's height in pixels.
            camera: The camera the image was drawn through.

        Returns:
            True if the click met a disk and a turn began. False if a turn
            is under way already, or the click met no disk.

        Raises:
            Error: If the image has no size.
        """
        if self.animating:
            return False
        var axis = self.axis_at(x, y, width, height, camera)
        if not Bool(axis):
            return False
        self.turn_toward(axis.value(), camera)
        return True

    def turn_toward(mut self, axis: ViewAxis, camera: CameraFrame) raises:
        """Start a turn of the camera toward an axis, three.js's
        `prepareAnimationData` followed by setting `animating`.

        Args:
            axis: The disk to look along.
            camera: The camera to turn, as it stands now.

        Raises:
            Error: If the axis is none of the six.
        """
        var direction = axis_direction(axis)
        self._target = axis_turn(axis)
        self._radius = camera.position.distance_to(self.center)
        var destination = direction * self._radius + self.center
        var up = Vector3(0, 1, 0)
        self._q1 = facing(self.center, camera.position, up, False)
        self._q2 = facing(self.center, destination, up, False)
        self.animating = True

    def update(mut self, delta: Duration, mut camera: CameraFrame) raises:
        """Turn the camera toward the axis by the time that passed, three.js's
        `update`.

        The camera's position moves around `center` on a sphere of the
        radius it started at, and its orientation turns toward the axis's,
        each by at most a full turn a second. Call it while `animating` is
        set, as three.js's editor does.

        Args:
            delta: The time since the last update. Must not be negative.
            camera: The camera to turn, moved and turned in place.

        Raises:
            Error: If `delta` is negative.
        """
        var seconds = delta.to(SECOND)
        if seconds < 0:
            raise Error("A view helper cannot turn by a negative time")
        var step = Angle(seconds * VIEW_HELPER_TURN_RATE, RADIAN)
        var arrived = _turn_towards(self._q1, self._q2, step)
        camera.position = (
            self._q1.rotate(Vector3(0, 0, 1)) * self._radius + self.center
        )
        var turn = Quaternion.from_matrix(camera.rotation())
        _ = _turn_towards(turn, self._target, step)
        camera.right = turn.rotate(Vector3(1, 0, 0))
        camera.above = turn.rotate(Vector3(0, 1, 0))
        camera.back = turn.rotate(Vector3(0, 0, 1))
        if arrived:
            self.animating = False
