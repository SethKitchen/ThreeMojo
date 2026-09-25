# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A roller coaster's track, its lifters, its shadow, and a sky and trees
around it, from three.js `examples/jsm/misc/RollerCoaster.js`.

Each function samples a curve at `divisions` even steps of its length, as
three.js's `getPointAt` does, and builds triangles between one step and
the next.

| Function | three.js | What it holds |
|---|---|---|
| `roller_coaster_geometry` | `RollerCoasterGeometry` | Three rails and a sleeper at every second step, with `normal` and `color` |
| `roller_coaster_lifters_geometry` | `RollerCoasterLiftersGeometry` | A post from each step down to the ground, with `normal` |
| `roller_coaster_shadow_geometry` | `RollerCoasterShadowGeometry` | A flat band under the track, on the ground |
| `sky_geometry` | `SkyGeometry` | A hundred flat clouds |
| `trees_geometry` | `TreesGeometry` | Crossed triangles standing on a landscape, with `color` |

The track turns about y to follow the curve and tilts with it; the band
and the lifters only turn about y. A step above ten meters has a
crossbar and two posts; a lower one has one post.

three.js works in doubles and stores floats, and so does this. The sky and
the trees draw random numbers from `Math.random`; here they come from a
`SeededRandom`, in three.js's order. three.js's geometry first takes four
numbers for its uuid; a geometry here has no uuid and takes none.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, COLOR, NORMAL, POSITION
from core.raycaster import Raycaster
from core.scene import Scene
from math.space_curve import (
    ARC_LENGTH_DIVISIONS,
    Point3,
    SpaceCurve,
    cross3,
    lengths_of,
    normalized3,
    point3,
    u_to_t,
)
from math.utils import SeededRandom
from math.vector3 import Vector3
from render.color_spaces import srgb_to_linear_three
from std.math import atan2, cos, pi, sin

# The rail colors, three.js's `color1` and `color2`.
comptime _WHITE = SIMD[DType.float64, 4](1, 1, 1, 0)
comptime _YELLOW = SIMD[DType.float64, 4](1, 1, 0, 0)


def _turn(axis: Point3, angle: Float64) -> Point3:
    """Return three.js's `setFromAxisAngle`: a quaternion as x, y, z, w."""
    var half = angle / 2
    var s = sin(half)
    return Point3(axis[0] * s, axis[1] * s, axis[2] * s, cos(half))


def _apply(q: Point3, v: Point3) -> Point3:
    """Return three.js's `applyQuaternion`, in doubles."""
    var tx = 2 * (q[1] * v[2] - q[2] * v[1])
    var ty = 2 * (q[2] * v[0] - q[0] * v[2])
    var tz = 2 * (q[0] * v[1] - q[1] * v[0])
    return point3(
        v[0] + q[3] * tx + q[1] * tz - q[2] * ty,
        v[1] + q[3] * ty + q[2] * tx - q[0] * tz,
        v[2] + q[3] * tz + q[0] * ty - q[1] * tx,
    )


def _push(mut out: List[Float32], v: Point3):
    """Append a point's three numbers as floats."""
    out.append(Float32(v[0]))
    out.append(Float32(v[1]))
    out.append(Float32(v[2]))


def _point_at[
    C: SpaceCurve
](curve: C, lengths: List[Float64], u: Float64) raises -> Point3:
    """Return three.js's `getPointAt(u)`, from the curve's length table."""
    return curve.point3(u_to_t(lengths, u))


def _tangent_at[
    C: SpaceCurve
](curve: C, lengths: List[Float64], u: Float64) raises -> Point3:
    """Return three.js's `getTangentAt(u)`, from the curve's length table."""
    return curve.tangent3(u_to_t(lengths, u))


def _check(divisions: Int) raises:
    """Refuse fewer than one division."""
    if divisions < 1:
        raise Error("A roller coaster needs one division or more")


def _ring(sides: Int, radius: Float64) -> List[Point3]:
    """Return three.js's tube outline: `sides` points round a circle."""
    var out = List[Point3]()
    for i in range(sides):  # pragma: no branch
        var angle = Float64(i) / Float64(sides) * 2 * pi
        out.append(point3(sin(angle) * radius, cos(angle) * radius, 0))
    return out^


def _geometry(
    var positions: List[Float32],
    var normals: List[Float32],
    var colors: List[Float32],
) raises -> BufferGeometry:
    """Return a geometry of the attributes given, each left out when
    empty."""
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    if len(normals) > 0:
        geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    if len(colors) > 0:
        geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return geometry^


struct _Track(Movable):
    """What `roller_coaster_geometry` builds as it goes."""

    var positions: List[Float32]
    var normals: List[Float32]
    var colors: List[Float32]
    var point: Point3
    var previous: Point3
    var turn: Point3
    var previous_turn: Point3

    def __init__(out self, start: Point3):
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.colors = List[Float32]()
        self.point = start
        self.previous = start
        self.turn = Point3(0, 0, 0, 1)
        self.previous_turn = _turn(point3(0, 1, 0), pi / 2)

    def _color(mut self, color: SIMD[DType.float64, 4], count: Int):
        """Append one color `count` times."""
        for _ in range(count):  # pragma: no branch
            _push(self.colors, color)

    def draw_shape(
        mut self, shape: List[Point3], color: SIMD[DType.float64, 4]
    ):
        """Append a flat shape's two faces, three.js's `drawShape`."""
        var back = _apply(self.turn, point3(0, 0, -1))
        for j in range(len(shape)):  # pragma: no branch
            _push(self.positions, _apply(self.turn, shape[j]) + self.point)
            _push(self.normals, back)
        var front = _apply(self.turn, point3(0, 0, 1))
        for j in range(len(shape) - 1, -1, -1):  # pragma: no branch
            _push(self.positions, _apply(self.turn, shape[j]) + self.point)
            _push(self.normals, front)
        self._color(color, 2 * len(shape))

    def extrude_shape(
        mut self,
        shape: List[Point3],
        offset: Point3,
        color: SIMD[DType.float64, 4],
    ):
        """Append a tube's walls from the last step to this one, three.js's
        `extrudeShape`."""
        var count = len(shape)
        for j in range(count):  # pragma: no branch
            var one = shape[j]
            var two = shape[(j + 1) % count]
            var v1 = _apply(self.turn, one + offset) + self.point
            var v2 = _apply(self.turn, two + offset) + self.point
            var v3 = _apply(self.previous_turn, two + offset) + self.previous
            var v4 = _apply(self.previous_turn, one + offset) + self.previous
            for v in [v1, v2, v4, v2, v3, v4]:  # pragma: no branch
                _push(self.positions, v)
            var n1 = normalized3(_apply(self.turn, one))
            var n2 = normalized3(_apply(self.turn, two))
            var n3 = normalized3(_apply(self.previous_turn, two))
            var n4 = normalized3(_apply(self.previous_turn, one))
            for n in [n1, n2, n4, n2, n3, n4]:  # pragma: no branch
                _push(self.normals, n)
            self._color(color, 6)


def roller_coaster_geometry[
    C: SpaceCurve
](curve: C, divisions: Int) raises -> BufferGeometry:
    """Return a roller coaster's track along a curve, three.js's
    `RollerCoasterGeometry`.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The track's path.
        divisions: How many steps along it.

    Returns:
        A geometry of triangles with `position`, `normal` and `color`.

    Raises:
        Error: If there is no division, or the curve refuses a point.
    """
    _check(divisions)
    var lengths = lengths_of(curve, ARC_LENGTH_DIVISIONS)
    var track = _Track(_point_at(curve, lengths, 0))
    var step: List[Point3] = [
        point3(-0.225, 0, 0),
        point3(0, -0.050, 0),
        point3(0, -0.175, 0),
        point3(0, -0.050, 0),
        point3(0.225, 0, 0),
        point3(0, -0.175, 0),
    ]
    var tube1 = _ring(5, 0.06)
    var tube2 = _ring(6, 0.025)
    for i in range(1, divisions + 1):  # pragma: no branch
        track.point = _point_at(curve, lengths, Float64(i) / Float64(divisions))
        var forward = normalized3(track.point - track.previous)
        var right = normalized3(cross3(point3(0, 1, 0), forward))
        var up = cross3(forward, right)
        track.turn = _turn(up, atan2(forward[0], forward[2]))
        if i % 2 == 0:
            track.draw_shape(step, _YELLOW)
        track.extrude_shape(tube1, point3(0, -0.125, 0), _YELLOW)
        track.extrude_shape(tube2, point3(0.2, 0, 0), _WHITE)
        track.extrude_shape(tube2, point3(-0.2, 0, 0), _WHITE)
        track.previous = track.point
        track.previous_turn = track.turn
    return _geometry(
        track.positions.copy(), track.normals.copy(), track.colors.copy()
    )


def _extrude_between(
    mut positions: List[Float32],
    mut normals: List[Float32],
    shape: List[Point3],
    turn: Point3,
    start: Point3,
    end: Point3,
):
    """Append a post's walls from one point to another, three.js's
    lifters' `extrudeShape`."""
    var count = len(shape)
    for j in range(count):  # pragma: no branch
        var one = _apply(turn, shape[j])
        var two = _apply(turn, shape[(j + 1) % count])
        for v in [  # pragma: no branch
            one + start,
            two + start,
            one + end,
            two + start,
            two + end,
            one + end,
        ]:
            _push(positions, v)
        var n1 = normalized3(one)
        var n2 = normalized3(two)
        for n in [n1, n2, n1, n2, n2, n1]:  # pragma: no branch
            _push(normals, n)


def roller_coaster_lifters_geometry[
    C: SpaceCurve
](curve: C, divisions: Int) raises -> BufferGeometry:
    """Return the posts that hold a track up, three.js's
    `RollerCoasterLiftersGeometry`.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The track's path.
        divisions: How many steps along it; each has its posts.

    Returns:
        A geometry of triangles with `position` and `normal`.

    Raises:
        Error: If there is no division, or the curve refuses a point.
    """
    _check(divisions)
    var lengths = lengths_of(curve, ARC_LENGTH_DIVISIONS)
    var tube1: List[Point3] = [
        point3(0, 0.05, -0.05),
        point3(0, 0.05, 0.05),
        point3(0, -0.05, 0),
    ]
    var tube2: List[Point3] = [
        point3(-0.05, 0, 0.05),
        point3(-0.05, 0, -0.05),
        point3(0.05, 0, 0),
    ]
    var tube3: List[Point3] = [
        point3(0.05, 0, -0.05),
        point3(0.05, 0, 0.05),
        point3(-0.05, 0, 0),
    ]
    var positions = List[Float32]()
    var normals = List[Float32]()
    var up = point3(0, 1, 0)
    for i in range(1, divisions + 1):  # pragma: no branch
        var u = Float64(i) / Float64(divisions)
        var point = _point_at(curve, lengths, u)
        var tangent = _tangent_at(curve, lengths, u)
        var turn = _turn(up, atan2(tangent[0], tangent[2]))
        var height = point[1]
        if height > 10:
            _extrude_between(
                positions,
                normals,
                tube1,
                turn,
                _apply(turn, point3(-0.75, -0.35, 0)) + point,
                _apply(turn, point3(0.75, -0.35, 0)) + point,
            )
            _extrude_between(
                positions,
                normals,
                tube2,
                turn,
                _apply(turn, point3(-0.7, -0.3, 0)) + point,
                _apply(turn, point3(-0.7, -height, 0)) + point,
            )
            _extrude_between(
                positions,
                normals,
                tube3,
                turn,
                _apply(turn, point3(0.7, -0.3, 0)) + point,
                _apply(turn, point3(0.7, -height, 0)) + point,
            )
        else:
            _extrude_between(
                positions,
                normals,
                tube3,
                turn,
                _apply(turn, point3(0, -0.2, 0)) + point,
                _apply(turn, point3(0, -height, 0)) + point,
            )
    return _geometry(positions^, normals^, List[Float32]())


def roller_coaster_shadow_geometry[
    C: SpaceCurve
](curve: C, divisions: Int) raises -> BufferGeometry:
    """Return a flat band on the ground under a track, three.js's
    `RollerCoasterShadowGeometry`.

    Parameters:
        C: The type of the curve.

    Args:
        curve: The track's path.
        divisions: How many steps along it.

    Returns:
        A geometry of triangles with `position` only, at y = 0.

    Raises:
        Error: If there is no division, or the curve refuses a point.
    """
    _check(divisions)
    var lengths = lengths_of(curve, ARC_LENGTH_DIVISIONS)
    var positions = List[Float32]()
    var up = point3(0, 1, 0)
    var previous = _point_at(curve, lengths, 0)
    previous[1] = 0
    var previous_turn = _turn(up, pi / 2)
    for i in range(1, divisions + 1):  # pragma: no branch
        var point = _point_at(curve, lengths, Float64(i) / Float64(divisions))
        point[1] = 0
        var forward = point - previous
        var turn = _turn(up, atan2(forward[0], forward[2]))
        var v1 = _apply(turn, point3(-0.3, 0, 0)) + point
        var v2 = _apply(turn, point3(0.3, 0, 0)) + point
        var v3 = _apply(previous_turn, point3(0.3, 0, 0)) + previous
        var v4 = _apply(previous_turn, point3(-0.3, 0, 0)) + previous
        for v in [v1, v2, v4, v2, v3, v4]:  # pragma: no branch
            _push(positions, v)
        previous = point
        previous_turn = turn
    return _geometry(positions^, List[Float32](), List[Float32]())


def sky_geometry(mut random: SeededRandom) raises -> BufferGeometry:
    """Return a hundred flat square clouds, three.js's `SkyGeometry`.

    Args:
        random: Where the random numbers come from, four a cloud.

    Returns:
        A geometry of triangles with `position` only, each cloud 50 to 100
        meters up.

    Raises:
        Error: Never; the positions are whole points.
    """
    var positions = List[Float32]()
    for _ in range(100):  # pragma: no branch
        var x = random.next() * 800 - 400
        var y = random.next() * 50 + 50
        var z = random.next() * 800 - 400
        var size = random.next() * 40 + 20
        for corner in [  # pragma: no branch
            point3(x - size, y, z - size),
            point3(x + size, y, z - size),
            point3(x - size, y, z + size),
            point3(x + size, y, z - size),
            point3(x + size, y, z + size),
            point3(x - size, y, z + size),
        ]:
            _push(positions, corner)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    return geometry^


def trees_geometry(
    scene: Scene, assets: Assets, mut random: SeededRandom
) raises -> BufferGeometry:
    """Return trees standing on a landscape, three.js's `TreesGeometry`.

    Two thousand places are drawn in a square 500 meters wide. A ray from
    50 meters up down to each finds the landscape; where it meets nothing
    no tree stands. Each tree is two crossed triangles, a random height, in
    a random green.

    Args:
        scene: The landscape: every mesh in it is hit, as three.js's
            `intersectObject` hits the landscape and its children.
        assets: Where the landscape's geometry is.
        random: Where the random numbers come from, in three.js's order.

    Returns:
        A geometry of triangles with `position` and `color`, in linear
        light.

    Raises:
        Error: If the landscape cannot be hit: a mesh names something the
            assets do not have, or the scene is stale.
    """
    var positions = List[Float32]()
    var colors = List[Float32]()
    for _ in range(2000):  # pragma: no branch
        var x = random.next() * 500 - 250
        var z = random.next() * 500 - 250
        var ray = Raycaster(
            Vector3(Float32(x), 50, Float32(z)), Vector3(0, -1, 0)
        )
        var hits = ray.intersect_scene(scene, assets)
        if len(hits) == 0:
            continue
        var y = Float64(hits[0].point.y)
        var height = random.next() * 5 + 0.5
        var angle = random.next() * pi * 2
        for _ in range(2):  # pragma: no branch
            for corner in [  # pragma: no branch
                point3(x + sin(angle), y, z + cos(angle)),
                point3(x, y + height, z),
                point3(x + sin(angle + pi), y, z + cos(angle + pi)),
            ]:
                _push(positions, corner)
            angle += pi / 2
        var shade = random.next() * 0.1
        var green = SIMD[DType.float64, 4](
            srgb_to_linear_three(0.2 + shade),
            srgb_to_linear_three(0.4 + shade),
            0,
            0,
        )
        for _ in range(6):  # pragma: no branch
            _push(colors, green)
    return _geometry(positions^, List[Float32](), colors^)
