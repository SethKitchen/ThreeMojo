# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The parts that a castle is built of, as triangles.

A part is geometry with the depth of the real thing. A wall is a plate with
the openings cut through it, so a window has a reveal as deep as the wall is
thick. A window has a stone surround, a sill, a frame, a mullion and a pane
set back in the opening. A round wall is a ring of such plates, and a crown
is a ring of corbels under a parapet of merlons.

Points are in the z-up frame of `MeshBuilder`, in meters: x east, y north,
z up. The builders are in a `Kit`, one for each material, so that a part
adds a brick to one and a stone to another and a mesh view draws each with
its own material.

A surface that carries a texture takes its color from the texture, and the
vertex color tints it. A surface with no texture takes its color from the
vertex color.
"""

from std.math import cos, floor, isfinite, pi, pow, sin, sqrt
from core.buffer_geometry import BufferGeometry
from extensions.castle.kinds import (
    BARK,
    BRICK,
    FOLIAGE,
    GLASS,
    GRAVEL,
    LAWN,
    METAL,
    Material,
    SLATE,
    STONE,
    WATER,
    WOOD,
)
from extensions.castle.plan import Point
from extensions.visual.mesh import MeshBuilder
from generators.utils import Vec3d

# The thickness of a wall, in meters, that the openings are cut through.
comptime WALL_THICKNESS = 0.55
# The height of the rise of an equilateral pointed arch over its width.
comptime _OGIVE = 0.8660254


@fieldwise_init
struct MaterialMesh(Movable):
    """The geometry of one material of the view."""

    # What the surfaces are made of.
    var material: Material
    # The triangles, with a color at each vertex.
    var geometry: BufferGeometry


struct Kit(Movable):
    """One builder of triangles for each material."""

    var brick: MeshBuilder
    var stone: MeshBuilder
    var slate: MeshBuilder
    var water: MeshBuilder
    var lawn: MeshBuilder
    var gravel: MeshBuilder
    var foliage: MeshBuilder
    var glass: MeshBuilder
    var wood: MeshBuilder
    var metal: MeshBuilder
    var bark: MeshBuilder

    def __init__(out self):
        """Start with no triangles."""
        self.brick = MeshBuilder()
        self.stone = MeshBuilder()
        self.slate = MeshBuilder()
        self.water = MeshBuilder()
        self.lawn = MeshBuilder()
        self.gravel = MeshBuilder()
        self.foliage = MeshBuilder()
        self.glass = MeshBuilder()
        self.wood = MeshBuilder()
        self.metal = MeshBuilder()
        self.bark = MeshBuilder()

    def triangles(self) -> Int:
        """Return how many triangles the kit holds.

        Returns:
            The sum over every material.
        """
        return (
            self.brick.count()
            + self.stone.count()
            + self.slate.count()
            + self.water.count()
            + self.lawn.count()
            + self.gravel.count()
            + self.foliage.count()
            + self.glass.count()
            + self.wood.count()
            + self.metal.count()
            + self.bark.count()
        )

    def meshes(self) raises -> List[MaterialMesh]:
        """Return one geometry for each material that has triangles.

        Returns:
            The geometries, in the order of the materials.

        Raises:
            Error: If a geometry cannot be built.
        """
        var result = List[MaterialMesh]()
        if self.brick.count() > 0:
            result.append(MaterialMesh(BRICK, self.brick.geometry()))
        if self.stone.count() > 0:
            result.append(MaterialMesh(STONE, self.stone.geometry()))
        if self.slate.count() > 0:
            result.append(MaterialMesh(SLATE, self.slate.geometry()))
        if self.water.count() > 0:
            result.append(MaterialMesh(WATER, self.water.geometry()))
        if self.lawn.count() > 0:
            result.append(MaterialMesh(LAWN, self.lawn.geometry()))
        if self.gravel.count() > 0:
            result.append(MaterialMesh(GRAVEL, self.gravel.geometry()))
        if self.foliage.count() > 0:
            result.append(MaterialMesh(FOLIAGE, self.foliage.geometry()))
        if self.glass.count() > 0:
            result.append(MaterialMesh(GLASS, self.glass.geometry()))
        if self.wood.count() > 0:
            result.append(MaterialMesh(WOOD, self.wood.geometry()))
        if self.metal.count() > 0:
            result.append(MaterialMesh(METAL, self.metal.geometry()))
        if self.bark.count() > 0:
            result.append(MaterialMesh(BARK, self.bark.geometry()))
        return result^


def srgb(red: Int, green: Int, blue: Int) -> Vec3d:
    """Return a color given in sRGB bytes, as linear components.

    Args:
        red: The red byte, 0 to 255.
        green: The green byte.
        blue: The blue byte.

    Returns:
        The linear color, each channel zero to one.
    """
    return Vec3d(_linear(red), _linear(green), _linear(blue))


def _linear(byte: Int) -> Float64:
    """Return the linear value of an sRGB byte."""
    var c = Float64(byte) / 255.0
    if c <= 0.04045:
        return c / 12.92
    return pow((c + 0.055) / 1.055, 2.4)


def white() -> Vec3d:
    """Return the tint that leaves a texture as it is.

    Returns:
        Linear white.
    """
    return Vec3d(1.0, 1.0, 1.0)


def unit_noise(x: Float64, y: Float64, seed: Int) -> Float64:
    """Return a repeatable number from 0 up to 1 for a place.

    Args:
        x: The first coordinate.
        y: The second coordinate.
        seed: Where the numbers start.

    Returns:
        A number in 0 up to 1.
    """
    var h = sin(x * 12.9898 + y * 78.233 + Float64(seed) * 37.719) * 43758.5453
    return h - floor(h)


def signed_area(outline: List[Point]) -> Float64:
    """Return half the signed area of an outline: positive if it runs
    counterclockwise.

    Args:
        outline: The corners.

    Returns:
        The area, in m^2, with the sign of the winding.
    """
    var twice = Float64(0)
    var count = len(outline)
    for at in range(count):  # pragma: no branch
        var p = outline[at]
        var q = outline[(at + 1) % count]
        twice += p.x.value * q.y.value - q.x.value * p.y.value
    return twice / 2


def at_height(at: Point, z: Float64) -> Vec3d:
    """Return a point of the plan at a height.

    Args:
        at: The point of the plan.
        z: The height.

    Returns:
        The point in 3D.
    """
    return Vec3d(at.x.value, at.y.value, z)


def box_at(
    mut mesh: MeshBuilder,
    center: Vec3d,
    ax: Vec3d,
    ay: Vec3d,
    az: Vec3d,
    hx: Float64,
    hy: Float64,
    hz: Float64,
    color: Vec3d,
):
    """Add a box with half the sizes along three unit axes.

    Args:
        mesh: The builder.
        center: The middle of the box.
        ax: The first axis, a unit vector.
        ay: The second axis, a unit vector at right angles to the first.
        az: The third axis, a unit vector at right angles to both.
        hx: Half the size along the first axis.
        hy: Half the size along the second.
        hz: Half the size along the third.
        color: The linear color.
    """
    var corners = List[Vec3d]()
    for k in range(8):
        var sx = 1.0 if (k & 1) != 0 else -1.0
        var sy = 1.0 if (k & 2) != 0 else -1.0
        var sz = 1.0 if (k & 4) != 0 else -1.0
        corners.append(
            center + ax * (sx * hx) + ay * (sy * hy) + az * (sz * hz)
        )
    mesh.oriented(corners[1], corners[3], corners[7], ax, color)
    mesh.oriented(corners[1], corners[7], corners[5], ax, color)
    mesh.oriented(corners[0], corners[2], corners[6], ax * -1.0, color)
    mesh.oriented(corners[0], corners[6], corners[4], ax * -1.0, color)
    mesh.oriented(corners[2], corners[3], corners[7], ay, color)
    mesh.oriented(corners[2], corners[7], corners[6], ay, color)
    mesh.oriented(corners[0], corners[1], corners[5], ay * -1.0, color)
    mesh.oriented(corners[0], corners[5], corners[4], ay * -1.0, color)
    mesh.oriented(corners[4], corners[5], corners[7], az, color)
    mesh.oriented(corners[4], corners[7], corners[6], az, color)
    mesh.oriented(corners[0], corners[1], corners[3], az * -1.0, color)
    mesh.oriented(corners[0], corners[3], corners[2], az * -1.0, color)


def _push(
    mut mesh: MeshBuilder,
    p: Vec3d,
    n: Vec3d,
    uv: Tuple[Float64, Float64],
    color: Vec3d,
):
    """Add one vertex with its own texture coordinates."""
    mesh.positions.append(Float32(p.x))
    mesh.positions.append(Float32(p.z))
    mesh.positions.append(Float32(-p.y))
    mesh.normals.append(Float32(n.x))
    mesh.normals.append(Float32(n.z))
    mesh.normals.append(Float32(-n.y))
    mesh.uvs.append(Float32(uv[0]))
    mesh.uvs.append(Float32(uv[1]))
    mesh.colors.append(Float32(color.x))
    mesh.colors.append(Float32(color.y))
    mesh.colors.append(Float32(color.z))


def tri_uv(
    mut mesh: MeshBuilder,
    a: Vec3d,
    b: Vec3d,
    c: Vec3d,
    na: Vec3d,
    nb: Vec3d,
    nc: Vec3d,
    uva: Tuple[Float64, Float64],
    uvb: Tuple[Float64, Float64],
    uvc: Tuple[Float64, Float64],
    color: Vec3d,
):
    """Add a triangle with a normal and texture coordinates at each corner.

    The triangle is turned so that its front faces where the normals point.

    Args:
        mesh: The builder.
        a: The first corner.
        b: The second corner.
        c: The third corner.
        na: The normal at a.
        nb: The normal at b.
        nc: The normal at c.
        uva: The texture coordinates at a, in meters.
        uvb: The texture coordinates at b.
        uvc: The texture coordinates at c.
        color: The linear color.
    """
    var cross = (b - a).cross(c - a)
    if not (cross.length() > 1e-12):
        return
    if cross.dot(na + nb + nc) < 0:
        _push(mesh, a, na, uva, color)
        _push(mesh, c, nc, uvc, color)
        _push(mesh, b, nb, uvb, color)
    else:
        _push(mesh, a, na, uva, color)
        _push(mesh, b, nb, uvb, color)
        _push(mesh, c, nc, uvc, color)


def _planar(
    origin: Vec3d, u_axis: Vec3d, v_axis: Vec3d, p: Vec3d
) -> Tuple[Float64, Float64]:
    """Return the texture coordinates of a point, from two axes in meters."""
    var d = p - origin
    return (d.dot(u_axis), d.dot(v_axis))


def quad_uv(
    mut mesh: MeshBuilder,
    a: Vec3d,
    b: Vec3d,
    c: Vec3d,
    d: Vec3d,
    facing: Vec3d,
    color: Vec3d,
    origin: Vec3d,
    u_axis: Vec3d,
    v_axis: Vec3d,
):
    """Add a flat quad whose texture runs along two chosen axes.

    Args:
        mesh: The builder.
        a: The first corner.
        b: The second corner.
        c: The third corner.
        d: The fourth corner.
        facing: A direction that the front must face.
        color: The linear color.
        origin: The point where both texture coordinates are zero.
        u_axis: The unit direction of u, in meters.
        v_axis: The unit direction of v, in meters.
    """
    var cross = (b - a).cross(c - a)
    if not (cross.length() > 1e-12):
        return
    var n = cross.normalized()
    if n.dot(facing) < 0:
        n = n * -1.0
    var ua = _planar(origin, u_axis, v_axis, a)
    var ub = _planar(origin, u_axis, v_axis, b)
    var uc = _planar(origin, u_axis, v_axis, c)
    var ud = _planar(origin, u_axis, v_axis, d)
    tri_uv(mesh, a, b, c, n, n, n, ua, ub, uc, color)
    tri_uv(mesh, a, c, d, n, n, n, ua, uc, ud, color)


@fieldwise_init
struct Opening(Copyable, Movable):
    """A window or a doorway in a wall."""

    # The distance of its middle from the start of the wall.
    var at: Float64
    # The height of its lower edge.
    var sill: Float64
    # Its width and its height to the springing of an arch, or to its top.
    var width: Float64
    var height: Float64
    # Whether its head is a pointed arch.
    var pointed: Bool
    # Whether it has glass. An opening with none is a doorway.
    var glazed: Bool


def opening_polygon(
    at: Float64,
    sill: Float64,
    width: Float64,
    height: Float64,
    pointed: Bool,
    grow: Float64,
) -> List[Tuple[Float64, Float64]]:
    """Return the outline of an opening, grown outward by a margin.

    A pointed head is two arcs, each of the radius of the width, that meet
    at the top: the equilateral arch of the Gothic.

    Args:
        at: The distance of its middle along the wall.
        sill: The height of its lower edge.
        width: Its width.
        height: Its height.
        pointed: Whether its head is a pointed arch.
        grow: The margin added on the sides, the top and the sill.

    Returns:
        The corners, counterclockwise, in (along, up).
    """
    var half = width / 2 + grow
    var low = sill - grow
    var high = sill + height + grow
    var points = List[Tuple[Float64, Float64]]()
    points.append((at - half, low))
    points.append((at + half, low))
    if not pointed:
        points.append((at + half, high))
        points.append((at - half, high))
        return points^
    var span = 2.0 * half
    var spring = max(high - _OGIVE * span, low + 0.3)
    points.append((at + half, spring))
    var steps = 5
    for step in range(1, steps + 1):  # pragma: no branch
        var turn = (pi / 3.0) * Float64(step) / Float64(steps)
        points.append((at - half + span * cos(turn), spring + span * sin(turn)))
    for step in range(steps - 1, -1, -1):  # pragma: no branch
        var turn = pi - (pi / 3.0) * Float64(step) / Float64(steps)
        points.append((at + half + span * cos(turn), spring + span * sin(turn)))
    return points^


def _fill(
    mut kit: Kit, o: Opening, origin: Vec3d, along: Vec3d, away: Vec3d
) raises:
    """Add the stone surround, the sill, the frame and the glass of an
    opening, or the dark of a doorway."""
    var up = Vec3d(0, 0, 1)
    var inner = opening_polygon(o.at, o.sill, o.width, o.height, o.pointed, 0.0)
    var outer = opening_polygon(
        o.at, o.sill, o.width, o.height, o.pointed, 0.17
    )
    var holes = List[List[Tuple[Float64, Float64]]]()
    holes.append(inner.copy())
    kit.stone.plate(
        outer,
        holes,
        origin + away * 0.07,
        along,
        up,
        away * -0.07,
        white(),
    )
    var middle = origin + along * o.at
    box_at(
        kit.stone,
        Vec3d(middle.x, middle.y, o.sill - 0.1) + away * 0.13,
        along,
        away,
        up,
        o.width / 2 + 0.27,
        0.15,
        0.07,
        white(),
    )
    if not o.glazed:
        # The dark of a passage behind a doorway.
        kit.wood.plate(
            inner,
            List[List[Tuple[Float64, Float64]]](),
            origin - away * 1.4,
            along,
            up,
            away * -0.02,
            srgb(10, 9, 8),
        )
        return
    kit.glass.plate(
        inner,
        List[List[Tuple[Float64, Float64]]](),
        origin - away * 0.3,
        along,
        up,
        away * -0.02,
        srgb(20, 28, 36),
    )
    var rim = List[List[Tuple[Float64, Float64]]]()
    rim.append(
        opening_polygon(o.at, o.sill, o.width, o.height, o.pointed, -0.05)
    )
    var paint = srgb(46, 54, 50)
    kit.wood.plate(
        inner, rim, origin - away * 0.28, along, up, away * -0.05, paint
    )
    var base = Vec3d(middle.x, middle.y, 0) - away * 0.27
    if o.width > 0.7:
        box_at(
            kit.wood,
            base + Vec3d(0, 0, o.sill + o.height / 2),
            along,
            away,
            up,
            0.025,
            0.04,
            o.height / 2,
            paint,
        )
    if o.height > 1.3:
        box_at(
            kit.wood,
            base + Vec3d(0, 0, o.sill + o.height * 0.62),
            along,
            away,
            up,
            o.width / 2,
            0.04,
            0.025,
            paint,
        )


def wall(
    mut kit: Kit,
    stone: Bool,
    p: Vec3d,
    q: Vec3d,
    away: Vec3d,
    bottom: Float64,
    top: Float64,
    openings: List[Opening],
    color: Vec3d,
    gable: Float64 = 0.0,
) raises:
    """Add a wall from one foot to another, with its openings cut through.

    Args:
        kit: The builders.
        stone: True for dressed stone, false for brick.
        p: The start of the foot, at any height.
        q: The end of the foot.
        away: The horizontal unit direction that the wall faces.
        bottom: The height of the foot.
        top: The height of the eave.
        openings: The windows and doors, each inside the wall.
        color: The linear tint.
        gable: The height of a gable's peak over the middle, or zero for a
            plain top.

    Raises:
        Error: If the plate cannot be triangulated.
    """
    var run = Vec3d(q.x - p.x, q.y - p.y, 0)
    var length = run.length()
    if not (length > 1e-6):
        return
    var along = run * (1.0 / length)
    var up = Vec3d(0, 0, 1)
    var origin = Vec3d(p.x, p.y, 0)
    var outline = List[Tuple[Float64, Float64]]()
    outline.append((0.0, bottom))
    outline.append((length, bottom))
    outline.append((length, top))
    if gable > top:
        outline.append((length / 2, gable))
    outline.append((0.0, top))
    var holes = List[List[Tuple[Float64, Float64]]]()
    for o in openings:
        holes.append(
            opening_polygon(o.at, o.sill, o.width, o.height, o.pointed, 0.0)
        )
    if stone:
        kit.stone.plate(
            outline, holes, origin, along, up, away * -WALL_THICKNESS, color
        )
    else:
        kit.brick.plate(
            outline, holes, origin, along, up, away * -WALL_THICKNESS, color
        )
    for o in openings:
        _fill(kit, o, origin, along, away)


def window_row(
    length: Float64,
    margin: Float64,
    pitch: Float64,
    width: Float64,
    height: Float64,
    sill: Float64,
    pointed: Bool,
) -> List[Opening]:
    """Return windows spaced evenly along a wall at one height.

    Args:
        length: The length of the wall.
        margin: The least distance from a window's middle to either end.
        pitch: The wish for the distance between windows.
        width: The width of each window.
        height: The height of each window.
        sill: The height of the lower edge.
        pointed: Whether the heads are pointed arches.

    Returns:
        The windows, or none if the wall is too short for one.
    """
    var result = List[Opening]()
    var room = length - 2.0 * margin
    if room < 0:
        return result^
    var count = Int(room / pitch) + 1
    for k in range(count):  # pragma: no branch
        var at = length / 2.0
        if count > 1:
            at = margin + room * Float64(k) / Float64(count - 1)
        result.append(Opening(at, sill, width, height, pointed, True))
    return result^


def ring_band(
    mut mesh: MeshBuilder,
    cx: Float64,
    cy: Float64,
    radius: Float64,
    z0: Float64,
    z1: Float64,
    ledge: Float64,
    facets: Int,
    color: Vec3d,
):
    """Add a ring of stone round a round tower, with a ledge on top.

    Args:
        mesh: The builder.
        cx: The east coordinate of the tower's axis.
        cy: The north coordinate.
        radius: The outer radius of the band.
        z0: The height of its foot.
        z1: The height of its top.
        ledge: The width of the sloping top, from the outer edge inward.
        facets: The number of flat sides of the ring.
        color: The linear color.
    """
    var up = Vec3d(0, 0, 1)
    for at in range(facets):  # pragma: no branch
        var t0 = 2.0 * pi * Float64(at) / Float64(facets)
        var t1 = 2.0 * pi * Float64(at + 1) / Float64(facets)
        var middle = (t0 + t1) / 2
        var away = Vec3d(cos(middle), sin(middle), 0)
        var p = Vec3d(cx + radius * cos(t0), cy + radius * sin(t0), 0)
        var q = Vec3d(cx + radius * cos(t1), cy + radius * sin(t1), 0)
        var inner = radius - ledge
        var pi_ = Vec3d(cx + inner * cos(t0), cy + inner * sin(t0), 0)
        var qi = Vec3d(cx + inner * cos(t1), cy + inner * sin(t1), 0)
        var drop = Vec3d(0, 0, z0)
        var rise = Vec3d(0, 0, z1)
        mesh.oriented(p + drop, q + drop, q + rise, away, color)
        mesh.oriented(p + drop, q + rise, p + rise, away, color)
        # The top slopes back to the wall.
        mesh.oriented(
            p + rise, q + rise, qi + rise + up * 0.0, away + up * 1.5, color
        )
        mesh.oriented(p + rise, qi + rise, pi_ + rise, away + up * 1.5, color)


def round_wall(
    mut kit: Kit,
    cx: Float64,
    cy: Float64,
    radius: Float64,
    bottom: Float64,
    top: Float64,
    facets: Int,
    stone: Bool,
    color: Vec3d,
    levels: List[Float64],
    stride: Int,
    phase: Int,
    slit: Float64,
) raises:
    """Add the wall of a round tower, a ring of flat plates with slit
    windows.

    Args:
        kit: The builders.
        cx: The east coordinate of the tower's axis.
        cy: The north coordinate.
        radius: The radius to the foot of each plate's middle.
        bottom: The height of the foot.
        top: The height of the eave.
        facets: The number of plates round the tower.
        stone: True for stone, false for brick.
        color: The linear tint.
        levels: The heights of the sills of the slits.
        stride: Every stride-th plate has slits, or none if zero.
        phase: Which plate of each stride is the first.
        slit: The width of a slit.

    Raises:
        Error: If a plate cannot be triangulated.
    """
    for at in range(facets):  # pragma: no branch
        var t0 = 2.0 * pi * Float64(at) / Float64(facets)
        var t1 = 2.0 * pi * Float64(at + 1) / Float64(facets)
        var middle = (t0 + t1) / 2
        var away = Vec3d(cos(middle), sin(middle), 0)
        var p = Vec3d(cx + radius * cos(t0), cy + radius * sin(t0), 0)
        var q = Vec3d(cx + radius * cos(t1), cy + radius * sin(t1), 0)
        var run = (q - p).length()
        var openings = List[Opening]()
        if stride > 0 and (at + phase) % stride == 0 and run > slit + 0.55:
            for level in levels:  # pragma: no branch
                openings.append(Opening(run / 2, level, slit, 1.25, True, True))
        wall(kit, stone, p, q, away, bottom, top, openings, color)


def corbel_ring(
    mut mesh: MeshBuilder,
    cx: Float64,
    cy: Float64,
    radius: Float64,
    top: Float64,
    count: Int,
    color: Vec3d,
):
    """Add a ring of stepped corbels under a projecting parapet.

    Args:
        mesh: The builder.
        cx: The east coordinate of the tower's axis.
        cy: The north coordinate.
        radius: The radius of the wall that the corbels stand away from.
        top: The height of the underside of the parapet.
        count: How many corbels.
        color: The linear color.
    """
    var up = Vec3d(0, 0, 1)
    for at in range(count):  # pragma: no branch
        var turn = 2.0 * pi * (Float64(at) + 0.5) / Float64(count)
        var away = Vec3d(cos(turn), sin(turn), 0)
        var along = Vec3d(-sin(turn), cos(turn), 0)
        var centre = Vec3d(cx, cy, 0)
        for step in range(3):
            var reach = 0.12 * Float64(step + 1)
            var z = top - 0.15 - 0.27 * Float64(2 - step)
            box_at(
                mesh,
                centre + away * (radius + reach / 2 - 0.02) + Vec3d(0, 0, z),
                away,
                along,
                up,
                reach / 2 + 0.02,
                0.17,
                0.135,
                color,
            )


def round_crown(
    mut kit: Kit,
    cx: Float64,
    cy: Float64,
    radius: Float64,
    top: Float64,
    merlon: Float64,
) raises:
    """Add the crown of a round tower: corbels, a projecting parapet with
    merlons, and a leaded floor.

    Args:
        kit: The builders.
        cx: The east coordinate of the tower's axis.
        cy: The north coordinate.
        radius: The radius of the wall.
        top: The height of the top of the wall.
        merlon: The height of a merlon over the floor.

    Raises:
        Error: If a mesh cannot be built.
    """
    var up = Vec3d(0, 0, 1)
    var facets = max(12, Int(2.0 * pi * radius / 0.7))
    var count = max(8, Int(2.0 * pi * radius / 0.75))
    corbel_ring(kit.stone, cx, cy, radius, top - 0.05, count, white())
    var reach = radius + 0.42
    ring_band(kit.stone, cx, cy, reach, top - 0.45, top, 0.0, facets, white())
    # The floor of the walk, then the merlons round its edge.
    var centre = Vec3d(cx, cy, top)
    var lead = srgb(88, 94, 98)
    for at in range(facets):  # pragma: no branch
        var t0 = 2.0 * pi * Float64(at) / Float64(facets)
        var t1 = 2.0 * pi * Float64(at + 1) / Float64(facets)
        var p = centre + Vec3d(reach * cos(t0), reach * sin(t0), 0)
        var q = centre + Vec3d(reach * cos(t1), reach * sin(t1), 0)
        kit.metal.oriented(centre, p, q, up, lead)
    var merlons = max(8, Int(2.0 * pi * reach / 1.4))
    for at in range(merlons):  # pragma: no branch
        var turn = 2.0 * pi * (Float64(at) + 0.5) / Float64(merlons)
        var away = Vec3d(cos(turn), sin(turn), 0)
        var along = Vec3d(-sin(turn), cos(turn), 0)
        var width = 2.0 * pi * reach / Float64(merlons) * 0.58
        box_at(
            kit.brick,
            centre + away * (reach - 0.28) + Vec3d(0, 0, merlon / 2),
            away,
            along,
            up,
            0.28,
            width / 2,
            merlon / 2,
            white(),
        )
        box_at(
            kit.stone,
            centre + away * (reach - 0.28) + Vec3d(0, 0, merlon + 0.05),
            away,
            along,
            up,
            0.33,
            width / 2 + 0.04,
            0.05,
            white(),
        )


def finial(
    mut mesh: MeshBuilder, x: Float64, y: Float64, z: Float64, height: Float64
):
    """Add a metal finial: a spike on a small ball.

    Args:
        mesh: The builder.
        x: The east coordinate of its foot.
        y: The north coordinate.
        z: The height of its foot.
        height: Its height.
    """
    var iron = srgb(46, 48, 50)
    var base = Vec3d(x, y, z)
    var ball = height * 0.16
    var sides = 6
    # A ball, as a double pyramid, and a thin spike above it.
    var low = base + Vec3d(0, 0, ball)
    var mid = base + Vec3d(0, 0, ball * 2.0)
    var tip = base + Vec3d(0, 0, height)
    for at in range(sides):  # pragma: no branch
        var t0 = 2.0 * pi * Float64(at) / Float64(sides)
        var t1 = 2.0 * pi * Float64(at + 1) / Float64(sides)
        var r = ball * 0.8
        var p = low + Vec3d(r * cos(t0), r * sin(t0), 0)
        var q = low + Vec3d(r * cos(t1), r * sin(t1), 0)
        var away = (p + q) * 0.5 - low
        mesh.oriented(p, q, mid, away + Vec3d(0, 0, 0.5), iron)
        mesh.oriented(p, q, base, away - Vec3d(0, 0, 0.5), iron)
        var s = ball * 0.22
        var a = mid + Vec3d(s * cos(t0), s * sin(t0), 0)
        var b = mid + Vec3d(s * cos(t1), s * sin(t1), 0)
        mesh.oriented(a, b, tip, (a + b) * 0.5 - mid, iron)


def spire(
    mut kit: Kit,
    cx: Float64,
    cy: Float64,
    radius: Float64,
    z0: Float64,
    height: Float64,
    facets: Int,
    seed: Int,
):
    """Add a slate spire over a round tower, with a finial.

    The spire flares at its foot, as a spire does, and its slates run in
    courses round it.

    Args:
        kit: The builders.
        cx: The east coordinate of the tower's axis.
        cy: The north coordinate.
        radius: The radius of the spire at its foot.
        z0: The height of its foot.
        height: The height of its tip over its foot.
        facets: The number of sides.
        seed: Where the random numbers start.
    """
    var apex = Vec3d(cx, cy, z0 + height)
    var slope = Vec3d(0, 0, radius)
    var slant = sqrt(radius * radius + height * height)
    var tint = 0.92 + 0.14 * unit_noise(cx, cy, seed)
    var color = Vec3d(tint, tint, tint)
    # The flare: a short steeper skirt, then the cone proper.
    var rings = List[Float64]()
    rings.append(radius)
    rings.append(radius * 0.93)
    var heights = List[Float64]()
    heights.append(0.0)
    heights.append(height * 0.06)
    for at in range(facets):  # pragma: no branch
        var t0 = 2.0 * pi * Float64(at) / Float64(facets)
        var t1 = 2.0 * pi * Float64(at + 1) / Float64(facets)
        var away0 = Vec3d(cos(t0), sin(t0), 0)
        var away1 = Vec3d(cos(t1), sin(t1), 0)
        var lean = radius / height
        var n0 = (away0 + Vec3d(0, 0, lean)).normalized()
        var n1 = (away1 + Vec3d(0, 0, lean)).normalized()
        var u0 = t0 * radius
        var u1 = t1 * radius
        var p0 = Vec3d(cx + radius * away0.x, cy + radius * away0.y, z0)
        var p1 = Vec3d(cx + radius * away1.x, cy + radius * away1.y, z0)
        # The distance up the slope is the second texture coordinate.
        tri_uv(
            kit.slate,
            p0,
            p1,
            apex,
            n0,
            n1,
            (n0 + n1).normalized(),
            (u0, 0.0),
            (u1, 0.0),
            ((u0 + u1) / 2, slant),
            color,
        )
    finial(kit.metal, cx, cy, z0 + height - 0.1, 1.5)
    _ = slope


def ridge_cap(mut mesh: MeshBuilder, a: Vec3d, b: Vec3d, width: Float64):
    """Add a leaded cap along a ridge.

    Args:
        mesh: The builder.
        a: The start of the ridge.
        b: The end of the ridge.
        width: The width of the cap.
    """
    var run = Vec3d(b.x - a.x, b.y - a.y, 0)
    var length = run.length()
    if not (length > 1e-6):
        return
    var along = run * (1.0 / length)
    var across = Vec3d(-along.y, along.x, 0)
    var middle = (a + b) * 0.5
    box_at(
        mesh,
        middle + Vec3d(0, 0, 0.1),
        along,
        across,
        Vec3d(0, 0, 1),
        length / 2,
        width / 2,
        0.1,
        srgb(110, 116, 120),
    )


def chimney(
    mut kit: Kit, x: Float64, y: Float64, z: Float64, height: Float64
) raises:
    """Add a brick chimney stack with a stone cap and two pots.

    Args:
        kit: The builders.
        x: The east coordinate of its middle.
        y: The north coordinate.
        z: The height of its foot, inside the roof.
        height: The height of the stack.
    """
    var east = Vec3d(1, 0, 0)
    var north = Vec3d(0, 1, 0)
    var up = Vec3d(0, 0, 1)
    box_at(
        kit.brick,
        Vec3d(x, y, z + height / 2),
        east,
        north,
        up,
        0.5,
        0.5,
        height / 2,
        white(),
    )
    box_at(
        kit.stone,
        Vec3d(x, y, z + height + 0.08),
        east,
        north,
        up,
        0.6,
        0.6,
        0.09,
        white(),
    )
    var clay = srgb(150, 78, 52)
    for k in range(2):
        var offset = -0.22 + 0.44 * Float64(k)
        box_at(
            kit.brick,
            Vec3d(x + offset, y, z + height + 0.5),
            east,
            north,
            up,
            0.13,
            0.13,
            0.32,
            clay,
        )


def dormer(
    mut kit: Kit,
    foot: Vec3d,
    away: Vec3d,
    slope: Float64,
    width: Float64,
    seed: Int,
) raises:
    """Add a dormer window with a gable of its own on a sloping roof.

    Args:
        kit: The builders.
        foot: The point of the roof under the middle of the dormer's front.
        away: The horizontal unit direction that the roof faces.
        slope: How far the roof rises for each meter back from the eave.
        width: The width of the dormer's front.
        seed: Where the random numbers start.
    """
    var up = Vec3d(0, 0, 1)
    var along = Vec3d(-away.y, away.x, 0)
    var half = width / 2
    var wall_top = foot.z + 1.35
    var peak = wall_top + half * 1.15
    var deep = (peak - foot.z) / slope
    var start = foot - along * half
    var end = foot + along * half
    var openings = List[Opening]()
    openings.append(Opening(half, foot.z + 0.35, width * 0.46, 0.8, True, True))
    wall(
        kit,
        False,
        Vec3d(start.x, start.y, 0),
        Vec3d(end.x, end.y, 0),
        away,
        foot.z - 0.45,
        wall_top,
        openings,
        white(),
        peak,
    )
    var slate = Vec3d(0.95, 0.95, 0.95)
    var back = away * -deep
    for side in range(2):
        var sign = -1.0 if side == 0 else 1.0
        var edge = foot + along * (sign * (half + 0.1))
        # The cheek of the dormer: a triangle between the front, the roof
        # and the level of the eave of the dormer's roof.
        var a = Vec3d(edge.x, edge.y, foot.z - 0.45)
        var b = Vec3d(edge.x, edge.y, wall_top)
        var c = Vec3d(
            edge.x + back.x * (1.35 / slope * 1.0),
            edge.y + back.y * (1.35 / slope * 1.0),
            wall_top,
        )
        var n = along * sign
        tri_uv(
            kit.slate,
            a,
            b,
            c,
            n,
            n,
            n,
            (0.0, 0.0),
            (0.0, 1.35),
            (1.35 / slope, 1.35),
            slate,
        )
        # The slope of the dormer's roof, from its eave to its ridge.
        var eave = foot + along * (sign * (half + 0.12)) + away * 0.18
        var e0 = Vec3d(eave.x, eave.y, wall_top - 0.1)
        var e1 = Vec3d(eave.x + back.x, eave.y + back.y, wall_top - 0.1)
        var r0 = Vec3d(foot.x + away.x * 0.18, foot.y + away.y * 0.18, peak)
        var r1 = Vec3d(foot.x + back.x, foot.y + back.y, peak)
        quad_uv(
            kit.slate,
            e0,
            e1,
            r1,
            r0,
            along * sign + up,
            slate,
            e0,
            Vec3d(back.x, back.y, 0).normalized(),
            (r0 - e0).normalized(),
        )
    ridge_cap(
        kit.metal,
        Vec3d(foot.x + away.x * 0.18, foot.y + away.y * 0.18, peak),
        Vec3d(foot.x + back.x, foot.y + back.y, peak),
        0.18,
    )
    finial(kit.metal, foot.x + away.x * 0.15, foot.y + away.y * 0.15, peak, 0.7)
    _ = seed


def merlon_row(
    mut kit: Kit,
    p: Vec3d,
    q: Vec3d,
    away: Vec3d,
    z: Float64,
    height: Float64,
):
    """Add a corbel table and a crenellated parapet along one edge.

    Args:
        kit: The builders.
        p: The start of the edge, at any height.
        q: The end of the edge.
        away: The horizontal unit direction that the edge faces.
        z: The height of the top of the wall.
        height: The height of a merlon.
    """
    var run = Vec3d(q.x - p.x, q.y - p.y, 0)
    var length = run.length()
    if not (length > 1.0):
        return
    var along = run * (1.0 / length)
    var up = Vec3d(0, 0, 1)
    var base = Vec3d(p.x, p.y, 0)
    # The corbels, then the band they carry, which stands away from the wall.
    var corbels = max(2, Int(length / 0.9))
    for k in range(corbels):  # pragma: no branch
        var offset = (Float64(k) + 0.5) * length / Float64(corbels)
        var at = base + along * offset
        for step in range(3):
            var reach = 0.12 * Float64(step + 1)
            box_at(
                kit.stone,
                at
                + away * (reach / 2 - 0.02)
                + Vec3d(0, 0, z - 0.5 - 0.27 * Float64(2 - step)),
                along,
                away,
                up,
                0.17,
                reach / 2 + 0.02,
                0.135,
                white(),
            )
    box_at(
        kit.stone,
        base + along * (length / 2) + away * 0.2 + Vec3d(0, 0, z - 0.2),
        along,
        away,
        up,
        length / 2 + 0.4,
        0.4,
        0.2,
        white(),
    )
    var merlons = max(2, Int(length / 1.5))
    for k in range(merlons):  # pragma: no branch
        var offset = (Float64(k) + 0.5) * length / Float64(merlons)
        var at = base + along * offset
        var width = length / Float64(merlons) * 0.58
        box_at(
            kit.brick,
            at + away * 0.18 + Vec3d(0, 0, z + height / 2),
            along,
            away,
            up,
            width / 2,
            0.27,
            height / 2,
            white(),
        )
        box_at(
            kit.stone,
            at + away * 0.18 + Vec3d(0, 0, z + height + 0.05),
            along,
            away,
            up,
            width / 2 + 0.04,
            0.31,
            0.05,
            white(),
        )
