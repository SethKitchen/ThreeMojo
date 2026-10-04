# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The render view: meshes of a building model for a scene.

`add_building` adds one node for the building and, under it, one mesh per
storey and look. A wall is a slab of its construction's thickness, centered
on its face and extended by half its thickness at each end so that corners
close. Doors and windows are cut through it. A floor, ground or roof slab
hangs below its level by its construction's thickness. A column is a box or
a cylinder. A beam is a box that hangs below its axis. A window is a glass
pane in an aluminum frame, and a door is a timber leaf.

Every vertex carries an `elementId` attribute: the index of the element it
came from in the model, or of the opening plus the element count for a door
or window, or of the furnishing plus the element and opening counts for a
piece of furniture. Furniture is a few boxes per piece, in full detail. A picking ray can read it back. The building node's user data
records the model's name and fingerprint, the detail and what the view
drops, so a baked copy can be checked against its model.

The model is z up; the scene is y up. A model point (x, y, z) is the scene
point (x, z, -y).
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.building.construction import Construction
from extensions.building.fingerprint import fingerprint
from extensions.building.ids import ElementId, StoreyId
from extensions.building.kinds import (
    BEAM,
    BED,
    CHAIR,
    CIRCLE,
    COFFEE_TABLE,
    COLUMN,
    COUNTER,
    DESK,
    DOOR,
    ROOF,
    SINK,
    SLAB,
    SOFA,
    TABLE,
    TOILET,
    WALL,
)
from extensions.building.material import Look, aluminum, glass, timber
from extensions.building.model import Building, WallFrame
from generators.utils import Vec3d
from geometries.earcut import earcut
from materials.material import standard_material
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import cos, pi, sin

# The name of the per-vertex element attribute.
comptime ELEMENT_ID = "elementId"


@fieldwise_init
struct RenderDetail(Equatable, ImplicitlyCopyable, Writable):
    """How much of a building the render view draws."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the two details.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value == 0 or self.value == 1


# The envelope only: exterior walls, roofs and the ground, with windows as
# flush panes and no cut openings, interior or frame.
comptime MASSING = RenderDetail(0)
# Every element, with doors and windows cut through their walls.
comptime FULL = RenderDetail(1)


@fieldwise_init
struct RenderOptions(ImplicitlyCopyable):
    """What `add_building` draws."""

    var detail: RenderDetail
    # Draw storeys up to this one and nothing above it, for a cutaway; or
    # -1 for every storey. A cutaway leaves out the top storey's roof.
    var top_storey: Int

    @staticmethod
    def default() -> RenderOptions:
        """Return full detail for every storey.

        Returns:
            The options.
        """
        return RenderOptions(FULL, -1)


struct RenderedBuilding(Movable):
    """What `add_building` added."""

    var root: NodeId
    var meshes: Int
    var triangles: Int

    def __init__(out self, root: NodeId, meshes: Int, triangles: Int):
        """Hold a summary.

        Args:
            root: The building's node.
            meshes: How many meshes were added.
            triangles: How many triangles they hold.
        """
        self.root = root
        self.meshes = meshes
        self.triangles = triangles


# Looks that the model does not hold: they belong to the doors and windows.
comptime _GLASS = -1
comptime _FRAME = -2
comptime _DOOR = -3
comptime _WOOD = -4
comptime _FABRIC = -5
comptime _CERAMIC = -6
comptime _METAL = -7


struct _Bucket(Movable):
    """The triangles of one storey and one look."""

    var storey: Int
    var look: Int
    var positions: List[Float32]
    var normals: List[Float32]
    var uvs: List[Float32]
    var ids: List[Float32]

    def __init__(out self, storey: Int, look: Int):
        self.storey = storey
        self.look = look
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.uvs = List[Float32]()
        self.ids = List[Float32]()

    def vertex(mut self, p: Vec3d, n: Vec3d, u: Float64, v: Float64, id: Int):
        """Add one vertex, converting z up to y up."""
        self.positions.append(Float32(p.x))
        self.positions.append(Float32(p.z))
        self.positions.append(Float32(-p.y))
        self.normals.append(Float32(n.x))
        self.normals.append(Float32(n.z))
        self.normals.append(Float32(-n.y))
        self.uvs.append(Float32(u))
        self.uvs.append(Float32(v))
        self.ids.append(Float32(id))


struct _Mesher(Movable):
    """Buckets of triangles, filled element by element."""

    var buckets: List[_Bucket]

    def __init__(out self):
        self.buckets = List[_Bucket]()

    def bucket(mut self, storey: Int, look: Int) -> Int:
        """Return the index of the bucket for a storey and a look."""
        for i in range(len(self.buckets)):
            if (
                self.buckets[i].storey == storey
                and self.buckets[i].look == look
            ):
                return i
        self.buckets.append(_Bucket(storey, look))
        return len(self.buckets) - 1

    def quad(
        mut self,
        b: Int,
        p0: Vec3d,
        p1: Vec3d,
        p2: Vec3d,
        p3: Vec3d,
        id: Int,
    ):
        """Add a planar quad, counterclockwise seen from its front.

        Its UVs are meters along its first and last edges.
        """
        var e1 = p1 - p0
        var e2 = p3 - p0
        var n = e1.cross(e2).normalized()
        var w = e1.length()
        var h = e2.length()
        ref bucket = self.buckets[b]
        bucket.vertex(p0, n, 0, 0, id)
        bucket.vertex(p1, n, w, 0, id)
        bucket.vertex(p2, n, w, h, id)
        bucket.vertex(p0, n, 0, 0, id)
        bucket.vertex(p2, n, w, h, id)
        bucket.vertex(p3, n, 0, h, id)

    def cap(
        mut self,
        b: Int,
        origin: Vec3d,
        e1: Vec3d,
        e2: Vec3d,
        flat: List[Float64],
        holes: List[Int],
        front: Bool,
        id: Int,
    ) raises:
        """Add a polygon with holes in the plane of `e1` and `e2`.

        `flat` holds the outline then each hole as x, y pairs in that
        plane. The normal is e1 x e2 when `front`, else its opposite.
        """
        var triangles = earcut(flat, holes)
        var n = e1.cross(e2).normalized()
        if not front:
            n = n * -1.0
        ref bucket = self.buckets[b]
        var t = 0
        while t + 2 < len(triangles):
            var i0 = triangles[t]
            var i1 = triangles[t + 1]
            var i2 = triangles[t + 2]
            var ax = flat[2 * i0]
            var ay = flat[2 * i0 + 1]
            var bx = flat[2 * i1]
            var by = flat[2 * i1 + 1]
            var cx = flat[2 * i2]
            var cy = flat[2 * i2 + 1]
            var area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
            if (area < 0) == front:
                var hold = i1
                i1 = i2
                i2 = hold
            var corner = [i0, i1, i2]
            for k in range(3):  # pragma: no branch
                var x = flat[2 * corner[k]]
                var y = flat[2 * corner[k] + 1]
                bucket.vertex(origin + e1 * x + e2 * y, n, x, y, id)
            t += 3


def _color(value: Float32) -> UInt8:
    """Return a look channel from zero to one as a byte."""
    return UInt8(Int(value * 255 + 0.5))


def _look(building: Building, look: Int) -> Look:
    """Return the look of a bucket."""
    if look == _GLASS:
        return glass().look
    if look == _FRAME:
        return aluminum().look
    if look == _DOOR or look == _WOOD:
        return timber().look
    if look == _FABRIC:
        return Look(0.24, 0.3, 0.38, 0.95, 0, 0)
    if look == _CERAMIC:
        return Look(0.93, 0.93, 0.92, 0.2, 0, 0)
    if look == _METAL:
        return aluminum().look
    return building.materials[look].look


def _surface_look(building: Building, construction: Construction) -> Int:
    """Return the material index of a construction's visible face: the
    inside layer, the last."""
    return construction.layers[len(construction.layers) - 1].material.value


def _wall(
    mut mesher: _Mesher,
    building: Building,
    wall: ElementId,
    storey: Int,
    detail: RenderDetail,
) raises:
    """Add a wall with its openings cut."""
    var frame = building.wall_frame(wall)
    ref element = building.elements[wall.value]
    ref construction = building.constructions[
        element.construction.value().value
    ]
    var t = construction.thickness().value
    var extra = t / 2
    var look = _surface_look(building, construction)
    var b = mesher.bucket(storey, look)
    var length = frame.length
    var height = frame.height
    var openings = building.openings_of(wall)
    var cut = detail == FULL
    # The outline, then each opening as a hole.
    var flat = List[Float64]()
    flat.append(-extra)
    flat.append(0)
    flat.append(length + extra)
    flat.append(0)
    flat.append(length + extra)
    flat.append(height)
    flat.append(-extra)
    flat.append(height)
    var holes = List[Int]()
    if cut:
        for i in range(len(openings)):
            ref o = building.openings[openings[i].value]
            var u0 = o.offset.value
            var v0 = o.sill.value
            var u1 = u0 + o.width.value
            var v1 = v0 + o.height.value
            holes.append(len(flat) // 2)
            flat.append(u0)
            flat.append(v0)
            flat.append(u0)
            flat.append(v1)
            flat.append(u1)
            flat.append(v1)
            flat.append(u1)
            flat.append(v0)
    var id = wall.value
    var front = frame.point(0, 0, t / 2)
    var back = frame.point(0, 0, -t / 2)
    # The outside face of an exterior wall shows the outside layer. The
    # normal points to the face's positive side.
    ref face = building.topology.complex.faces[element.faces[0].value]
    var outside = mesher.bucket(storey, construction.layers[0].material.value)
    var front_bucket = b
    var back_bucket = b
    if not face.positive:
        front_bucket = outside
    elif not face.negative:
        back_bucket = outside
    mesher.cap(
        front_bucket, front, frame.along, frame.up, flat, holes, True, id
    )
    mesher.cap(back_bucket, back, frame.along, frame.up, flat, holes, False, id)
    # The ends, the bottom and the top.
    var w0 = -t / 2
    var w1 = t / 2
    var u0 = -extra
    var u1 = length + extra
    mesher.quad(
        b,
        frame.point(u0, 0, w0),
        frame.point(u0, 0, w1),
        frame.point(u0, height, w1),
        frame.point(u0, height, w0),
        id,
    )
    mesher.quad(
        b,
        frame.point(u1, 0, w1),
        frame.point(u1, 0, w0),
        frame.point(u1, height, w0),
        frame.point(u1, height, w1),
        id,
    )
    mesher.quad(
        b,
        frame.point(u0, height, w0),
        frame.point(u0, height, w1),
        frame.point(u1, height, w1),
        frame.point(u1, height, w0),
        id,
    )
    mesher.quad(
        b,
        frame.point(u0, 0, w1),
        frame.point(u0, 0, w0),
        frame.point(u1, 0, w0),
        frame.point(u1, 0, w1),
        id,
    )
    for i in range(len(openings)):
        _opening(mesher, building, openings[i].value, frame, t, storey, cut, id)


def _opening(
    mut mesher: _Mesher,
    building: Building,
    index: Int,
    frame: WallFrame,
    t: Float64,
    storey: Int,
    cut: Bool,
    wall_id: Int,
) raises:
    """Add an opening's reveals and its door or window."""
    ref o = building.openings[index]
    var id = len(building.elements) + index
    var u0 = o.offset.value
    var v0 = o.sill.value
    var u1 = u0 + o.width.value
    var v1 = v0 + o.height.value
    var w0 = -t / 2
    var w1 = t / 2
    if cut:
        # The reveals face into the opening.
        var look = _surface_look(
            building,
            building.constructions[
                building.elements[o.host.value].construction.value().value
            ],
        )
        var r = mesher.bucket(storey, look)
        mesher.quad(
            r,
            frame.point(u0, v0, w1),
            frame.point(u0, v0, w0),
            frame.point(u0, v1, w0),
            frame.point(u0, v1, w1),
            wall_id,
        )
        mesher.quad(
            r,
            frame.point(u1, v0, w0),
            frame.point(u1, v0, w1),
            frame.point(u1, v1, w1),
            frame.point(u1, v1, w0),
            wall_id,
        )
        mesher.quad(
            r,
            frame.point(u0, v1, w1),
            frame.point(u0, v1, w0),
            frame.point(u1, v1, w0),
            frame.point(u1, v1, w1),
            wall_id,
        )
        mesher.quad(
            r,
            frame.point(u0, v0, w0),
            frame.point(u0, v0, w1),
            frame.point(u1, v0, w1),
            frame.point(u1, v0, w0),
            wall_id,
        )
    if o.kind == DOOR:
        if not cut:
            return
        var leaf = mesher.bucket(storey, _DOOR)
        _box_in_frame(mesher, leaf, frame, u0, u1, v0, v1, -0.02, 0.02, id)
        return
    # A window: a pane on both faces, and a frame when cut.
    var pane = mesher.bucket(storey, _GLASS)
    var w = w1 + 0.001 if not cut else Float64(0)
    mesher.quad(
        pane,
        frame.point(u0, v0, w),
        frame.point(u1, v0, w),
        frame.point(u1, v1, w),
        frame.point(u0, v1, w),
        id,
    )
    var back = -w
    mesher.quad(
        pane,
        frame.point(u1, v0, back),
        frame.point(u0, v0, back),
        frame.point(u0, v1, back),
        frame.point(u1, v1, back),
        id,
    )
    if cut:
        var f = mesher.bucket(storey, _FRAME)
        var s = min(0.05, min(u1 - u0, v1 - v0) / 4)
        _box_in_frame(mesher, f, frame, u0, u1, v0, v0 + s, -0.04, 0.04, id)
        _box_in_frame(mesher, f, frame, u0, u1, v1 - s, v1, -0.04, 0.04, id)
        _box_in_frame(mesher, f, frame, u0, u0 + s, v0, v1, -0.04, 0.04, id)
        _box_in_frame(mesher, f, frame, u1 - s, u1, v0, v1, -0.04, 0.04, id)


def _box_in_frame(
    mut mesher: _Mesher,
    b: Int,
    frame: WallFrame,
    u0: Float64,
    u1: Float64,
    v0: Float64,
    v1: Float64,
    w0: Float64,
    w1: Float64,
    id: Int,
):
    """Add a box given by ranges in a wall's frame."""
    _box(
        mesher,
        b,
        frame.point(u0, v0, w0),
        frame.along * (u1 - u0),
        frame.up * (v1 - v0),
        frame.normal * (w1 - w0),
        id,
    )


def _box(
    mut mesher: _Mesher,
    b: Int,
    o: Vec3d,
    a: Vec3d,
    c: Vec3d,
    d: Vec3d,
    id: Int,
):
    """Add a box from a corner and three edges, right-handed: a x c is d's
    direction."""
    var p000 = o
    var p100 = o + a
    var p010 = o + c
    var p110 = o + a + c
    var p001 = o + d
    var p101 = o + a + d
    var p011 = o + c + d
    var p111 = o + a + c + d
    mesher.quad(b, p001, p101, p111, p011, id)
    mesher.quad(b, p100, p000, p010, p110, id)
    mesher.quad(b, p000, p001, p011, p010, id)
    mesher.quad(b, p101, p100, p110, p111, id)
    mesher.quad(b, p010, p011, p111, p110, id)
    mesher.quad(b, p000, p100, p101, p001, id)


def _slab(
    mut mesher: _Mesher, building: Building, slab: ElementId, storey: Int
) raises:
    """Add a floor, ground or roof slab below its face."""
    ref element = building.elements[slab.value]
    ref construction = building.constructions[
        element.construction.value().value
    ]
    var t = construction.thickness().value
    var look = _surface_look(building, construction)
    if element.kind == ROOF:
        look = construction.layers[0].material.value
    var b = mesher.bucket(storey, look)
    var face = element.faces[0]
    var points = building.topology.complex.face_points(face)
    var z = points[0].z
    var flat = List[Float64]()
    for i in range(len(points)):  # pragma: no branch
        flat.append(points[i].x)
        flat.append(points[i].y)
    var id = slab.value
    var top = Vec3d(0, 0, z)
    var bottom = Vec3d(0, 0, z - t)
    var ex = Vec3d(1, 0, 0)
    var ey = Vec3d(0, 1, 0)
    mesher.cap(b, top, ex, ey, flat, List[Int](), True, id)
    mesher.cap(b, bottom, ex, ey, flat, List[Int](), False, id)
    # The edges, except a bridge, which the loop runs both ways.
    var n = len(points)
    for i in range(n):  # pragma: no branch
        var p = points[i]
        var q = points[(i + 1) % n]
        var bridge = False
        for k in range(n):  # pragma: no branch
            if (
                points[k].distance_to(q) == 0
                and points[(k + 1) % n].distance_to(p) == 0
            ):
                bridge = True
        if bridge:
            continue
        # The loop is counterclockwise from above, so the outward side of
        # p to q is to its right.
        mesher.quad(
            b,
            Vec3d(q.x, q.y, z - t),
            Vec3d(p.x, p.y, z - t),
            Vec3d(p.x, p.y, z),
            Vec3d(q.x, q.y, z),
            id,
        )


def _member(
    mut mesher: _Mesher, building: Building, member: ElementId, storey: Int
) raises:
    """Add a column or a beam."""
    ref element = building.elements[member.value]
    var section = element.section.value()
    var b = mesher.bucket(storey, element.material.value().value)
    var axis = element.end - element.start
    var along = axis.normalized()
    # The depth runs along x for a column; a beam's depth is vertical.
    var depth_dir = Vec3d(1, 0, 0)
    var width_dir = Vec3d(0, 1, 0)
    var start = element.start
    var w = section.width.value
    var d = section.depth.value
    if element.kind == BEAM:
        depth_dir = Vec3d(0, 0, 1)
        width_dir = depth_dir.cross(along).normalized()
        start = start - depth_dir * (d / 2)
    var id = member.value
    if section.shape == CIRCLE:
        var segments = 12
        var r = w / 2
        for k in range(segments):  # pragma: no branch
            var a0 = 2 * pi * Float64(k) / Float64(segments)
            var a1 = 2 * pi * Float64(k + 1) / Float64(segments)
            var p0 = (
                start + depth_dir * (r * cos(a0)) + width_dir * (r * sin(a0))
            )
            var p1 = (
                start + depth_dir * (r * cos(a1)) + width_dir * (r * sin(a1))
            )
            mesher.quad(b, p0, p1, p1 + axis, p0 + axis, id)
        return
    var o = start - depth_dir * (d / 2) - width_dir * (w / 2)
    _box(mesher, b, o, depth_dir * d, width_dir * w, axis, id)


def _part(
    mut mesher: _Mesher,
    b: Int,
    origin: Vec3d,
    right: Vec3d,
    front: Vec3d,
    x0: Float64,
    x1: Float64,
    y0: Float64,
    y1: Float64,
    z0: Float64,
    z1: Float64,
    id: Int,
):
    """Add one box of a piece of furniture, given in the piece's frame."""
    var corner = origin + right * x0 + front * y0 + Vec3d(0, 0, z0)
    _box(
        mesher,
        b,
        corner,
        right * (x1 - x0),
        front * (y1 - y0),
        Vec3d(0, 0, z1 - z0),
        id,
    )


def _legs(
    mut mesher: _Mesher,
    b: Int,
    origin: Vec3d,
    right: Vec3d,
    front: Vec3d,
    hw: Float64,
    hd: Float64,
    top: Float64,
    id: Int,
):
    """Add four legs under a top."""
    var t = 0.05
    var xs = [-hw + 0.03, hw - 0.03 - t]
    var ys = [-hd + 0.03, hd - 0.03 - t]
    for i in range(2):  # pragma: no branch
        for k in range(2):  # pragma: no branch
            _part(
                mesher,
                b,
                origin,
                right,
                front,
                xs[i],
                xs[i] + t,
                ys[k],
                ys[k] + t,
                0,
                top,
                id,
            )


def _furniture(
    mut mesher: _Mesher, building: Building, index: Int, storey: Int
) raises:
    """Add one piece of furniture as a few boxes."""
    ref item = building.furnishings[index]
    var id = len(building.elements) + len(building.openings) + index
    var angle = item.rotation.value
    var right = Vec3d(cos(angle), sin(angle), 0)
    var front = Vec3d(-sin(angle), cos(angle), 0)
    var z = building.storeys[storey].elevation.value
    var origin = Vec3d(item.center.x, item.center.y, z)
    var hw = item.width.value / 2
    var hd = item.depth.value / 2
    var h = item.height.value
    var wood = mesher.bucket(storey, _WOOD)
    var kind = item.kind
    if kind == DESK or kind == TABLE or kind == COFFEE_TABLE:
        _part(
            mesher,
            wood,
            origin,
            right,
            front,
            -hw,
            hw,
            -hd,
            hd,
            h - 0.04,
            h,
            id,
        )
        var metal = mesher.bucket(storey, _METAL)
        _legs(mesher, metal, origin, right, front, hw, hd, h - 0.04, id)
    elif kind == CHAIR:
        var fabric = mesher.bucket(storey, _FABRIC)
        _part(
            mesher,
            fabric,
            origin,
            right,
            front,
            -hw,
            hw,
            -hd,
            hd,
            0.42,
            0.47,
            id,
        )
        _part(
            mesher,
            fabric,
            origin,
            right,
            front,
            -hw,
            hw,
            -hd,
            -hd + 0.06,
            0.47,
            h,
            id,
        )
        var metal = mesher.bucket(storey, _METAL)
        _legs(mesher, metal, origin, right, front, hw, hd, 0.42, id)
    elif kind == BED:
        _part(mesher, wood, origin, right, front, -hw, hw, -hd, hd, 0, 0.3, id)
        _part(
            mesher,
            wood,
            origin,
            right,
            front,
            -hw,
            hw,
            -hd,
            -hd + 0.06,
            0.3,
            1.0,
            id,
        )
        var fabric = mesher.bucket(storey, _FABRIC)
        _part(
            mesher,
            fabric,
            origin,
            right,
            front,
            -hw + 0.03,
            hw - 0.03,
            -hd + 0.06,
            hd - 0.03,
            0.3,
            h,
            id,
        )
    elif kind == SOFA:
        var fabric = mesher.bucket(storey, _FABRIC)
        _part(
            mesher, fabric, origin, right, front, -hw, hw, -hd, hd, 0, 0.42, id
        )
        _part(
            mesher,
            fabric,
            origin,
            right,
            front,
            -hw,
            hw,
            -hd,
            -hd + 0.2,
            0.42,
            h,
            id,
        )
        _part(
            mesher,
            fabric,
            origin,
            right,
            front,
            -hw,
            -hw + 0.15,
            -hd + 0.2,
            hd,
            0.42,
            0.6,
            id,
        )
        _part(
            mesher,
            fabric,
            origin,
            right,
            front,
            hw - 0.15,
            hw,
            -hd + 0.2,
            hd,
            0.42,
            0.6,
            id,
        )
    elif kind == TOILET:
        var ceramic = mesher.bucket(storey, _CERAMIC)
        _part(
            mesher,
            ceramic,
            origin,
            right,
            front,
            -hw,
            hw,
            -hd + 0.2,
            hd,
            0,
            0.4,
            id,
        )
        _part(
            mesher,
            ceramic,
            origin,
            right,
            front,
            -hw,
            hw,
            -hd,
            -hd + 0.2,
            0,
            h,
            id,
        )
    elif kind == SINK or kind == COUNTER:
        _part(
            mesher,
            wood,
            origin,
            right,
            front,
            -hw,
            hw,
            -hd,
            hd,
            0,
            h - 0.05,
            id,
        )
        var ceramic = mesher.bucket(storey, _CERAMIC)
        _part(
            mesher,
            ceramic,
            origin,
            right,
            front,
            -hw,
            hw,
            -hd,
            hd,
            h - 0.05,
            h,
            id,
        )
    else:
        _part(mesher, wood, origin, right, front, -hw, hw, -hd, hd, 0, h, id)


def add_building(
    mut scene: Scene,
    mut assets: Assets,
    building: Building,
    options: RenderOptions,
) raises -> RenderedBuilding:
    """Add meshes of a building model to a scene.

    Args:
        scene: The scene to add the building's node and meshes to.
        assets: The store for the geometries and materials.
        building: The model.
        options: The detail and the top storey to draw.

    Returns:
        The building's node and the number of meshes and triangles.

    Raises:
        Error: If the detail is not valid, the top storey is out of range,
            or the model's ids do not agree.
    """
    if not options.detail.is_valid():
        raise Error("A render detail must be massing or full")
    var top = options.top_storey
    if top < -1 or top >= len(building.storeys):
        raise Error("The top storey must be -1 or a storey of the model")
    var mesher = _Mesher()
    for i in range(len(building.elements)):
        ref element = building.elements[i]
        var storey = element.storey.value
        # A cutaway leaves out what is above its top storey, and the top
        # storey's roof, which would hide its rooms.
        if top >= 0 and (
            storey > top or (storey == top and element.kind == ROOF)
        ):
            continue
        var id = ElementId(i)
        if options.detail == MASSING:
            var envelope = (
                element.kind == WALL
                or element.kind == ROOF
                or element.kind == SLAB
            )
            if not (envelope and building.is_exterior(id)):
                continue
        if element.kind == WALL:
            _wall(mesher, building, id, storey, options.detail)
        elif element.kind == SLAB or element.kind == ROOF:
            _slab(mesher, building, id, storey)
        else:
            _member(mesher, building, id, storey)
    if options.detail == FULL:
        for i in range(len(building.furnishings)):
            var storey = building.spaces[
                building.furnishings[i].space.value
            ].storey.value
            if top >= 0 and storey > top:
                continue
            _furniture(mesher, building, i, storey)
    var root_node = Object3D()
    root_node.name = building.name
    root_node.user_data.set_string("model", building.name)
    root_node.user_data.set_string(
        "fingerprint", hex(Int(fingerprint(building)))
    )
    root_node.user_data.set_string(
        "detail", "full" if options.detail == FULL else "massing"
    )
    root_node.user_data.set_number("topStorey", Float64(top))
    root_node.user_data.set_string(
        "dropped",
        (
            "layers inside constructions, physical properties,"
            " structural and thermal data; walls are centered on faces"
        ),
    )
    var root = scene.add(root_node^)
    var triangles = 0
    for i in range(len(mesher.buckets)):
        ref bucket = mesher.buckets[i]
        triangles += len(bucket.positions) // 9
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(bucket.positions.copy(), 3)
        )
        geometry.set_attribute(
            String(NORMAL), BufferAttribute(bucket.normals.copy(), 3)
        )
        geometry.set_attribute(
            String(UV), BufferAttribute(bucket.uvs.copy(), 2)
        )
        geometry.set_attribute(
            String(ELEMENT_ID), BufferAttribute(bucket.ids.copy(), 1)
        )
        var look = _look(building, bucket.look)
        var transparent = look.transmission > 0
        var material = standard_material(
            Color(_color(look.red), _color(look.green), _color(look.blue)),
            roughness=look.roughness,
            metalness=look.metalness,
            opacity=1 - look.transmission * 0.7,
            transparent=transparent,
        )
        var node = Object3D()
        node.name = String("storey ", bucket.storey, " look ", bucket.look)
        node.user_data.set_number("storey", Float64(bucket.storey))
        node.parent = root
        var mesh_node = scene.add(node^)
        scene.add_mesh(
            Mesh(
                assets.geometries.add(geometry^),
                assets.materials.add(material),
                mesh_node,
            )
        )
    return RenderedBuilding(root, len(mesher.buckets), triangles)
