# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's `road/MeshFactory` and the mesh half of `road/Map`.

The factory turns a map's lanes into triangles. It walks each lane every
`resolution` meters and puts a row of vertices across the lane: two for a
plain strip, `vertex_width_resolution` for a tessellated lane, and six for
a sidewalk, whose row runs down the outer curb, across the top and down
the inner curb. A lane that lies on one straight record gets only its two
end rows. Walls stand on a section's outermost edges. Lane marks are
strips of paint, solid or broken into dashes of three resolutions with
gaps of three. Junction lanes are smoothed together so that their heights
meet. The map functions at the end chunk a whole map, place its trees,
and draw its crosswalks.

**Output.** Every function returns a ThreeMojo `BufferGeometry` in CARLA's
frame (x forward, y right, z up, in meters), with the positions CARLA
computes. It adds what a renderer and a collider need:

- `normal`: per-vertex normals from `compute_vertex_normals`. Every face
  is wound the same way, so a road's normals point up and a curb's or a
  wall's point away from the solid.
- `uv`: coordinates in meters. On a lane u is the offset from lane 0,
  plus to the right, and v is s along the road, so a texture tiles at
  world scale across lanes and along the road. On a curb or a wall u is
  the height. On a crosswalk u and v are x and y.
- `uv1`: CARLA's own grid coordinates, where CARLA writes any: on a
  tessellated lane and on a sidewalk.
- one group per surface kind, whose material index is a `SurfaceKind`:
  road, sidewalk top, curb, wall, crosswalk, and the white and yellow
  paint. CARLA names the first two and the crosswalk as materials; the
  rest are this port's, so a renderer can tell every surface apart.

`to_three_frame` turns a geometry into three.js's frame for drawing.

**Differences from CARLA.** Within a geometry the triangles of one kind
come together, in CARLA's order, so a sidewalk's curb triangles follow its
top triangles where CARLA interleaves them row by row. The link triangles
that `ConcatMesh` adds wear the kind of the column they join, where CARLA
leaves them outside every material. A crosswalk outline wound clockwise
is turned so that its face points up. CARLA loops forever over a lane
with no road mark at its section's start; this stops. A part without
CARLA grid coordinates joins one with them with zeros. A junction of more
than two connections is built from its lanes, where CARLA runs marching
cubes from the third-party MeshReconstruction library; its sidewalks
follow CARLA's rule for such a junction.

Source: CARLA 1360bb9, `LibCarla/source/carla/road/MeshFactory.cpp`,
`road/Map.cpp` and `geom/Mesh.cpp`.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    GeometryGroup,
    MaterialIndex,
    NORMAL,
    POSITION,
    UV,
    UV1,
)
from extensions.carla.map import Map
from extensions.carla.math import make_unit_vector
from extensions.carla.road import Road
from extensions.carla.road_info import (
    BROKEN,
    JuncId,
    LANE_DRIVING,
    LANE_NONE,
    LANE_SIDEWALK,
    LaneId,
    LaneMarking,
    LaneType,
    RoadId,
    SOLID,
    info_at,
)
from extensions.carla.rtree import PointCloudRtree
from extensions.carla.transform import CarlaTransform
from math.bounds import Box3
from math.vector2 import Vector2
from math.vector3 import Vector3
from units.si import Length, METER

# CARLA's `EPSILON` and `MESH_EPSILON`: 10 and 50 double epsilons.
comptime EPSILON = 10.0 * 2.220446049250313e-16
comptime MESH_EPSILON = 50.0 * 2.220446049250313e-16


# --- surface kinds ------------------------------------------------------------


@fieldwise_init
struct SurfaceKind(Equatable, ImplicitlyCopyable, Writable):
    """What a group of triangles is: its material index in the geometry."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for one of the seven kinds."""
        return self.value >= 0 and self.value <= 6

    def material(self) -> MaterialIndex:
        """Return the kind as a geometry group's material index.

        Returns:
            The material index with the same number.
        """
        return MaterialIndex(self.value)


# A lane's driving surface: CARLA's "road" material.
comptime ROAD_SURFACE = SurfaceKind(0)
# The top of a sidewalk: CARLA's "sidewalk" material.
comptime SIDEWALK_SURFACE = SurfaceKind(1)
# The sides of a sidewalk, down to one meter below it.
comptime CURB_SURFACE = SurfaceKind(2)
# A safety wall on a section's outer edge.
comptime WALL_SURFACE = SurfaceKind(3)
# A crosswalk: CARLA's "crosswalk" material.
comptime CROSSWALK_SURFACE = SurfaceKind(4)
# White paint: every lane mark but the center line's.
comptime WHITE_MARK_SURFACE = SurfaceKind(5)
# Yellow paint: the center line's mark.
comptime YELLOW_MARK_SURFACE = SurfaceKind(6)


def surface_name(kind: SurfaceKind) raises -> String:
    """Return a surface kind's material name.

    Args:
        kind: The kind.

    Returns:
        "road", "sidewalk" and "crosswalk" as CARLA names them, and
        "curb", "wall", "white" and "yellow" for the others.

    Raises:
        Error: If the kind is not valid.
    """
    if not kind.is_valid():
        raise Error("Surface kind is not valid")
    var names: List[String] = [
        "road",
        "sidewalk",
        "curb",
        "wall",
        "crosswalk",
        "white",
        "yellow",
    ]
    return names[kind.value]


# --- parameters -----------------------------------------------------------------


struct OpendriveGenerationParameters(Copyable, Movable):
    """CARLA's `rpc::OpendriveGenerationParameters`, with its defaults."""

    # The spacing of the rows of vertices along a lane.
    var vertex_distance: Length
    # The longest piece of road one chunk holds.
    var max_road_length: Length
    var wall_height: Length
    # How far a junction's driving lanes widen on each side.
    var additional_width: Length
    # How many vertices a tessellated lane has across.
    var vertex_width_resolution: Float64
    var simplification_percentage: Float32
    var smooth_junctions: Bool
    var enable_mesh_visibility: Bool
    var enable_pedestrian_navigation: Bool

    def __init__(out self):
        """Create CARLA's defaults: 2 m rows, 50 m chunks, 1 m walls, 0.6 m
        junction widening, 4 vertices across, and every switch on."""
        self.vertex_distance = Length(2.0, METER)
        self.max_road_length = Length(50.0, METER)
        self.wall_height = Length(1.0, METER)
        self.additional_width = Length(0.6, METER)
        self.vertex_width_resolution = 4.0
        self.simplification_percentage = 20.0
        self.smooth_junctions = True
        self.enable_mesh_visibility = True
        self.enable_pedestrian_navigation = True


struct RoadParameters(Copyable, Movable):
    """CARLA's `MeshFactory::RoadParameters`, with its defaults."""

    var resolution: Length
    var max_road_len: Length
    var extra_lane_width: Length
    var wall_height: Length
    var vertex_width_resolution: Float32
    # Smoothing: neighbors farther than this weigh nothing.
    var max_weight_distance: Length
    var same_lane_weight_multiplier: Float32
    var lane_ends_multiplier: Float32

    def __init__(out self):
        """Create CARLA's defaults: 2 m, 50 m, 1 m, 0.6 m, 4, 5 m, 2 and 2."""
        self.resolution = Length(2.0, METER)
        self.max_road_len = Length(50.0, METER)
        self.extra_lane_width = Length(1.0, METER)
        self.wall_height = Length(0.6, METER)
        self.vertex_width_resolution = 4.0
        self.max_weight_distance = Length(5.0, METER)
        self.same_lane_weight_multiplier = 2.0
        self.lane_ends_multiplier = 2.0


# --- building a geometry ------------------------------------------------------


struct _Draft(Movable):
    # The geometry being built: positions in CARLA's frame, meter UVs,
    # CARLA's UVs if any, and triangles with a kind each.
    var positions: List[Vector3]
    var uvs: List[Vector2]
    var grid: List[Vector2]
    var has_grid: Bool
    var index: List[Int]
    var kinds: List[Int]

    def __init__(out self):
        self.positions = List[Vector3]()
        self.uvs = List[Vector2]()
        self.grid = List[Vector2]()
        self.has_grid = False
        self.index = List[Int]()
        self.kinds = List[Int]()

    def add(mut self, position: Vector3, uv: Vector2):
        self.positions.append(position)
        self.uvs.append(uv)

    def triangle(mut self, a: Int, b: Int, c: Int, kind: SurfaceKind):
        self.index.append(a)
        self.index.append(b)
        self.index.append(c)
        self.kinds.append(kind.value)

    def strip(mut self, first: Int, kind: SurfaceKind):
        # `Mesh::AddTriangleStrip` over the vertices from `first` on.
        for k in range(len(self.positions) - first - 2):
            if k % 2 == 0:
                self.triangle(first + k, first + k + 1, first + k + 2, kind)
            else:
                self.triangle(first + k + 2, first + k + 1, first + k, kind)

    def append(mut self, other: _Draft):
        # `Mesh::operator+=`.
        var base = len(self.positions)
        if other.has_grid and not self.has_grid:
            for _ in range(base):
                self.grid.append(Vector2(0, 0))
            self.has_grid = True
        self.positions.extend(other.positions.copy())
        self.uvs.extend(other.uvs.copy())
        if self.has_grid:
            if other.has_grid:
                self.grid.extend(other.grid.copy())
            else:
                for _ in range(len(other.positions)):
                    self.grid.append(Vector2(0, 0))
        for i in other.index:
            self.index.append(i + base)
        self.kinds.extend(other.kinds.copy())


def _draft_of(geometry: BufferGeometry) raises -> _Draft:
    var out = _Draft()
    if not geometry.has_attribute(POSITION):
        return out^
    ref position = geometry.attribute_view(POSITION)
    ref uv = geometry.attribute_view(UV)
    for i in range(position.count()):
        out.add(
            position.vector3(i),
            Vector2(uv.component(i, 0), uv.component(i, 1)),
        )
    if geometry.has_attribute(UV1):
        out.has_grid = True
        ref grid = geometry.attribute_view(UV1)
        for i in range(grid.count()):
            out.grid.append(Vector2(grid.component(i, 0), grid.component(i, 1)))
    for group in geometry.groups:
        var first = group.start // 3
        var end = (group.start + group.count) // 3
        # A group holds one triangle at least.
        for t in range(first, end):  # pragma: no branch
            out.triangle(
                geometry.index[3 * t],
                geometry.index[3 * t + 1],
                geometry.index[3 * t + 2],
                SurfaceKind(group.material_index.value),
            )
    return out^


def _finish(draft: _Draft) raises -> BufferGeometry:
    # The triangles of each kind together, in order, one group a kind.
    var geometry = BufferGeometry()
    var data = List[Float32]()
    var uv = List[Float32]()
    for i in range(len(draft.positions)):
        data.append(draft.positions[i].x)
        data.append(draft.positions[i].y)
        data.append(draft.positions[i].z)
        uv.append(draft.uvs[i].x)
        uv.append(draft.uvs[i].y)
    geometry.set_attribute(POSITION, BufferAttribute(data^, 3))
    geometry.set_attribute(UV, BufferAttribute(uv^, 2))
    if draft.has_grid:
        var grid = List[Float32]()
        for g in draft.grid:
            grid.append(g.x)
            grid.append(g.y)
        geometry.set_attribute(UV1, BufferAttribute(grid^, 2))
    var index = List[Int]()
    # Seven kinds, always.
    for kind in range(7):  # pragma: no branch
        var start = len(index)
        for t in range(len(draft.kinds)):
            if draft.kinds[t] == kind:
                index.append(draft.index[3 * t])
                index.append(draft.index[3 * t + 1])
                index.append(draft.index[3 * t + 2])
        if len(index) > start:
            geometry.groups.append(
                GeometryGroup(start, len(index) - start, MaterialIndex(kind))
            )
    geometry.set_index(index^)
    geometry.compute_vertex_normals()
    return geometry^


def _join(parts: List[BufferGeometry]) raises -> BufferGeometry:
    var out = _Draft()
    for k in range(len(parts)):
        out.append(_draft_of(parts[k]))
    return _finish(out)


def append_geometry(mut into: BufferGeometry, part: BufferGeometry) raises:
    """Add one geometry to another, CARLA's `Mesh::operator+=`.

    Args:
        into: The geometry that grows.
        part: The geometry added after it.

    Raises:
        Error: If a geometry lacks its positions or UVs.
    """
    var draft = _draft_of(into)
    draft.append(_draft_of(part))
    into = _finish(draft)


def concat_geometry(
    mut into: BufferGeometry,
    part: BufferGeometry,
    link: Int,
    kinds: List[SurfaceKind],
) raises:
    """Add a geometry and stitch it on, CARLA's `Mesh::ConcatMesh`.

    The last `link` vertices of `into` and the first `link` of `part` are
    joined by a row of quads. The quad between columns i and i + 1 wears
    `kinds[i]`.

    Args:
        into: The geometry that grows.
        part: The geometry added after it.
        link: How many vertices across a row is.
        kinds: The surface kind of each quad of the stitch, `link - 1` of
            them.

    Raises:
        Error: If a geometry lacks its positions or UVs, `kinds` is too
            short, or `into` has fewer than `link` vertices while `part`
            has some.
    """
    if len(kinds) < link - 1:
        raise Error("A stitch needs a kind for each quad")
    var draft = _draft_of(into)
    var other = _draft_of(part)
    if len(other.positions) == 0:
        into = _finish(draft)
        return
    var count = len(draft.positions)
    if count < link:
        raise Error("A stitch needs a row of vertices to join")
    var start = count - link
    for i in range(1, link):
        var kind = kinds[i - 1]
        # CARLA's indices count from one.
        draft.triangle(start + i - 1, start + i, count + i - 1, kind)
        draft.triangle(start + i, count + i, count + i - 1, kind)
    draft.append(other)
    into = _finish(draft)


def to_three_frame(geometry: BufferGeometry) raises -> BufferGeometry:
    """Return a CARLA-frame geometry in three.js's frame, ready to draw.

    y and z swap in the positions and the normals, and each triangle is
    wound the other way, since the swap turns the frame inside out.

    Args:
        geometry: A geometry from this module.

    Returns:
        The same surface in three.js's frame, with its groups.

    Raises:
        Error: If the geometry has no positions.
    """
    var out = geometry.clone()
    var positions = List[Float32]()
    var normals = List[Float32]()
    ref position = geometry.attribute_view(POSITION)
    ref normal = geometry.attribute_view(NORMAL)
    for i in range(position.count()):
        var p = position.vector3(i)
        positions.extend([p.x, p.z, p.y])
        var n = normal.vector3(i)
        normals.extend([n.x, n.z, n.y])
    out.set_attribute(POSITION, BufferAttribute(positions^, 3))
    out.set_attribute(NORMAL, BufferAttribute(normals^, 3))
    var index = List[Int]()
    for t in range(len(geometry.index) // 3):
        index.append(geometry.index[3 * t])
        index.append(geometry.index[3 * t + 2])
        index.append(geometry.index[3 * t + 1])
    out.set_index(index^)
    return out^


# --- the factory --------------------------------------------------------------


@fieldwise_init
struct LaneMarkMesh(Movable):
    """A lane mark's geometry and the color CARLA gives it."""

    var geometry: BufferGeometry
    # "white" or "yellow", CARLA's `outinfo` entry.
    var color: String


struct OrderedMeshes(Movable):
    """Meshes grouped by lane type, CARLA's `std::map<LaneType, ...>`.

    The types are in order of their number, as a `std::map` keeps them.
    """

    var types: List[LaneType]
    var meshes: List[List[BufferGeometry]]

    def __init__(out self):
        """Start with no types."""
        self.types = List[LaneType]()
        self.meshes = List[List[BufferGeometry]]()

    def slot(mut self, lane_type: LaneType) -> Int:
        """Return a type's place, adding it if it is new.

        Args:
            lane_type: The lane type.

        Returns:
            Its index in `types` and `meshes`.
        """
        var at = 0
        while at < len(self.types) and self.types[at].value < lane_type.value:
            at += 1
        if at < len(self.types) and self.types[at] == lane_type:
            return at
        self.types.insert(at, lane_type)
        self.meshes.insert(at, List[BufferGeometry]())
        return at

    def find(self, lane_type: LaneType) -> Int:
        """Return a type's place.

        Args:
            lane_type: The lane type.

        Returns:
            Its index, or -1 if it has no meshes.
        """
        for i in range(len(self.types)):
            if self.types[i] == lane_type:
                return i
        return -1


struct MeshFactory(Movable):
    """CARLA's `geom::MeshFactory`."""

    var road_param: RoadParameters

    def __init__(out self):
        """Create a factory with CARLA's `RoadParameters` defaults."""
        self.road_param = RoadParameters()

    def __init__(out self, params: OpendriveGenerationParameters):
        """Create a factory from generation parameters, as CARLA's does.

        Args:
            params: The resolution, chunk length, widening, wall height
                and vertices across come from here.
        """
        self.road_param = RoadParameters()
        self.road_param.resolution = params.vertex_distance
        self.road_param.max_road_len = params.max_road_length
        self.road_param.extra_lane_width = params.additional_width
        self.road_param.wall_height = params.wall_height
        self.road_param.vertex_width_resolution = Float32(
            params.vertex_width_resolution
        )

    def _resolution(self) raises -> Float64:
        if not (self.road_param.resolution.value > 0.0):
            raise Error("Mesh resolution must be positive")
        return Float64(self.road_param.resolution.value)

    def _width_vertices(self) -> Int:
        if self.road_param.vertex_width_resolution >= 2.0:
            return Int(self.road_param.vertex_width_resolution)
        return 2

    def _stations(
        self, road: Road, section: Int, s_start: Float64, s_end: Float64
    ) raises -> List[Float64]:
        # The rows a lane's strip takes: every resolution from the start,
        # or only the start on a straight lane, then its end if the last
        # row falls short of it.
        var step = self._resolution()
        var out = List[Float64]()
        var s = s_start
        if road.lane_is_straight(section):
            out.append(s)
        else:
            while True:
                out.append(s)
                s += step
                if not (s < s_end):
                    break
        if s_end - (s - step) > EPSILON:
            out.append(s_end - MESH_EPSILON)
        return out^

    def _rows(self, s_start: Float64, s_end: Float64) raises -> List[Float64]:
        # The rows of a tessellated lane or a sidewalk: no straight case.
        var step = self._resolution()
        var out = List[Float64]()
        var s = s_start
        while True:
            out.append(s)
            s += step
            if not (s < s_end):
                break
        if s_end - (s - step) > EPSILON:
            out.append(s_end - MESH_EPSILON)
        return out^

    def _lane_s(self, road: Road, section: Int) -> Tuple[Float64, Float64]:
        var start = road.sections[section].s
        return (start + EPSILON, start + road.section_length(section) - EPSILON)

    def _extra(self) -> Float32:
        return self.road_param.extra_lane_width.value

    def _surface(self, road: Road, section: Int, lane: Int) -> SurfaceKind:
        if road.sections[section].lanes[lane].type == LANE_SIDEWALK:
            return SIDEWALK_SURFACE
        return ROAD_SURFACE

    # --- lanes ------------------------------------------------------------

    def _lane_draft(
        self,
        road: Road,
        section: Int,
        lane: Int,
        s_start: Float64,
        s_end: Float64,
    ) raises -> _Draft:
        var draft = _Draft()
        if road.sections[section].lanes[lane].id.value == 0:
            return draft^
        var stations = self._stations(road, section, s_start, s_end)
        # There is one station at least.
        for s in stations:  # pragma: no branch
            var edges = road.lane_corners(section, lane, s, self._extra())
            var offsets = road.lane_edge_offsets(
                section, lane, s, self._extra()
            )
            draft.add(edges[0], Vector2(offsets[0], Float32(s)))
            draft.add(edges[1], Vector2(offsets[1], Float32(s)))
        draft.strip(0, self._surface(road, section, lane))
        return draft^

    def generate_lane(
        self,
        road: Road,
        section: Int,
        lane: Int,
        s_start: Float64,
        s_end: Float64,
    ) raises -> BufferGeometry:
        """Return a lane's strip from one s to another, `Generate(lane, a, b)`.

        Args:
            road: The road.
            section: The section's index.
            lane: The lane's index in the section.
            s_start: Where to start, in meters along the road.
            s_end: Where to end.

        Returns:
            Two vertices a row. Lane 0 has none.

        Raises:
            Error: If the resolution is not positive, or a record is
                missing.
        """
        return _finish(self._lane_draft(road, section, lane, s_start, s_end))

    def generate_whole_lane(
        self, road: Road, section: Int, lane: Int
    ) raises -> BufferGeometry:
        """Return a lane's whole strip, `Generate(lane)`.

        Args:
            road: The road.
            section: The section's index.
            lane: The lane's index in the section.

        Returns:
            The strip from just inside the section's start to just inside
            its end.

        Raises:
            Error: If `generate_lane` would.
        """
        var span = self._lane_s(road, section)
        return self.generate_lane(road, section, lane, span[0], span[1])

    def _tesselated_draft(
        self,
        road: Road,
        section: Int,
        lane: Int,
        s_start: Float64,
        s_end: Float64,
    ) raises -> _Draft:
        var draft = _Draft()
        if road.sections[section].lanes[lane].id.value == 0:
            return draft^
        draft.has_grid = True
        var across = self._width_vertices()
        var gaps = Float32(across - 1)
        var rows = self._rows(s_start, s_end)
        # There is one row at least.
        for row in range(len(rows)):  # pragma: no branch
            var s = rows[row]
            var edges = road.lane_corners(section, lane, s, self._extra())
            var offsets = road.lane_edge_offsets(
                section, lane, s, self._extra()
            )
            var step = (edges[1] - edges[0]) / gaps
            var du = (offsets[1] - offsets[0]) / gaps
            var vertex = edges[0]
            # There are two vertices across at least.
            for i in range(across):  # pragma: no branch
                draft.add(
                    vertex, Vector2(offsets[0] + du * Float32(i), Float32(s))
                )
                draft.grid.append(Vector2(Float32(i), Float32(row)))
                vertex = vertex + step
        var kind = self._surface(road, section, lane)
        for i in range(len(rows) - 1):
            # There are two vertices across at least.
            for j in range(across - 1):  # pragma: no branch
                var a = j + i * across
                var c = j + (i + 1) * across
                draft.triangle(a, a + 1, c, kind)
                draft.triangle(a + 1, c + 1, c, kind)
        return draft^

    def generate_tesselated(
        self,
        road: Road,
        section: Int,
        lane: Int,
        s_start: Float64,
        s_end: Float64,
    ) raises -> BufferGeometry:
        """Return a lane with several vertices across, `GenerateTesselated`.

        Args:
            road: The road.
            section: The section's index.
            lane: The lane's index in the section.
            s_start: Where to start, in meters along the road.
            s_end: Where to end.

        Returns:
            `vertex_width_resolution` vertices a row, at least two, and
            CARLA's grid coordinates in `uv1`. Lane 0 has none.

        Raises:
            Error: If the resolution is not positive, or a record is
                missing.
        """
        return _finish(
            self._tesselated_draft(road, section, lane, s_start, s_end)
        )

    def generate_whole_tesselated(
        self, road: Road, section: Int, lane: Int
    ) raises -> BufferGeometry:
        """Return a whole lane tessellated, `GenerateTesselated(lane)`.

        Args:
            road: The road.
            section: The section's index.
            lane: The lane's index in the section.

        Returns:
            The lane, as `generate_tesselated` makes it.

        Raises:
            Error: If `generate_tesselated` would.
        """
        var span = self._lane_s(road, section)
        return self.generate_tesselated(road, section, lane, span[0], span[1])

    def _sidewalk_draft(
        self,
        road: Road,
        section: Int,
        lane: Int,
        s_start: Float64,
        s_end: Float64,
    ) raises -> _Draft:
        var draft = _Draft()
        if road.sections[section].lanes[lane].id.value == 0:
            return draft^
        draft.has_grid = True
        var rows = self._rows(s_start, s_end)
        var down = Vector3(0, 0, 1)
        # There is one row at least.
        for row in range(len(rows)):  # pragma: no branch
            var s = rows[row]
            var e = road.lane_corners(section, lane, s, self._extra())
            var t = road.lane_edge_offsets(section, lane, s, self._extra())
            var v = Float32(s)
            var low = e[0] - down
            var high = e[1] - down
            draft.add(low, Vector2(low.z, v))
            draft.add(e[0], Vector2(e[0].z, v))
            draft.add(e[0], Vector2(t[0], v))
            draft.add(e[1], Vector2(t[1], v))
            draft.add(e[1], Vector2(e[1].z, v))
            draft.add(high, Vector2(high.z, v))
            # The list is a constant and not empty.
            for u in [0, 1, 1, 2, 2, 3]:  # pragma: no branch
                draft.grid.append(Vector2(Float32(u), Float32(row)))
        var top = self._surface(road, section, lane)
        for i in range(len(rows) - 1):
            # The list is a constant and not empty.
            for j in [0, 2, 4]:  # pragma: no branch
                var kind = top if j == 2 else CURB_SURFACE
                var a = j + i * 6
                var c = j + (i + 1) * 6
                draft.triangle(a, a + 1, c, kind)
                draft.triangle(a + 1, c + 1, c, kind)
        return draft^

    def generate_sidewalk(
        self,
        road: Road,
        section: Int,
        lane: Int,
        s_start: Float64,
        s_end: Float64,
    ) raises -> BufferGeometry:
        """Return a lane as a raised block, `GenerateSidewalk(lane, a, b)`.

        Each row is six vertices: one meter below the first edge, the
        first edge twice, the second edge twice, and one meter below it.
        The top wears the sidewalk kind on a sidewalk lane and the road
        kind on any other; the two sides wear the curb kind.

        Args:
            road: The road.
            section: The section's index.
            lane: The lane's index in the section.
            s_start: Where to start, in meters along the road.
            s_end: Where to end.

        Returns:
            The block, with CARLA's coordinates 0 to 3 across in `uv1`.
            Lane 0 has none.

        Raises:
            Error: If the resolution is not positive, or a record is
                missing.
        """
        return _finish(
            self._sidewalk_draft(road, section, lane, s_start, s_end)
        )

    def generate_whole_sidewalk(
        self, road: Road, section: Int, lane: Int
    ) raises -> BufferGeometry:
        """Return a whole lane as a raised block, `GenerateSidewalk(lane)`.

        Args:
            road: The road.
            section: The section's index.
            lane: The lane's index in the section.

        Returns:
            The block, as `generate_sidewalk` makes it.

        Raises:
            Error: If `generate_sidewalk` would.
        """
        var span = self._lane_s(road, section)
        return self.generate_sidewalk(road, section, lane, span[0], span[1])

    def generate_section_sidewalks(
        self, road: Road, section: Int
    ) raises -> BufferGeometry:
        """Return every lane of a section as a block, `GenerateSidewalk(ls)`.

        Args:
            road: The road.
            section: The section's index.

        Returns:
            The blocks, in order of lane id.

        Raises:
            Error: If `generate_sidewalk` would.
        """
        var draft = _Draft()
        var span = self._lane_s(road, section)
        for lane in range(len(road.sections[section].lanes)):
            draft.append(
                self._sidewalk_draft(road, section, lane, span[0], span[1])
            )
        return _finish(draft)

    def generate_section(
        self, road: Road, section: Int
    ) raises -> BufferGeometry:
        """Return every lane of a section, `Generate(lane_section)`.

        Args:
            road: The road.
            section: The section's index.

        Returns:
            The lanes' strips, in order of lane id.

        Raises:
            Error: If `generate_lane` would.
        """
        var draft = _Draft()
        var span = self._lane_s(road, section)
        for lane in range(len(road.sections[section].lanes)):
            draft.append(
                self._lane_draft(road, section, lane, span[0], span[1])
            )
        return _finish(draft)

    def generate_road(self, road: Road) raises -> BufferGeometry:
        """Return every lane of a road, `Generate(road)`.

        Args:
            road: The road.

        Returns:
            The lanes' strips, section by section.

        Raises:
            Error: If `generate_lane` would.
        """
        var draft = _Draft()
        for section in range(len(road.sections)):
            var span = self._lane_s(road, section)
            for lane in range(len(road.sections[section].lanes)):
                draft.append(
                    self._lane_draft(road, section, lane, span[0], span[1])
                )
        return _finish(draft)

    # --- walls ------------------------------------------------------------

    def _wall_draft(
        self,
        road: Road,
        section: Int,
        lane: Int,
        s_start: Float64,
        s_end: Float64,
        right: Bool,
    ) raises -> _Draft:
        var draft = _Draft()
        if road.sections[section].lanes[lane].id.value == 0:
            return draft^
        var up = Vector3(0, 0, self.road_param.wall_height.value)
        var stations = self._stations(road, section, s_start, s_end)
        # There is one station at least.
        for s in stations:  # pragma: no branch
            var edges = road.lane_corners(section, lane, s, self._extra())
            var v = Float32(s)
            if Bool(right):
                var top = edges[0] + up
                draft.add(top, Vector2(top.z, v))
                draft.add(edges[0], Vector2(edges[0].z, v))
            else:
                var top = edges[1] + up
                draft.add(edges[1], Vector2(edges[1].z, v))
                draft.add(top, Vector2(top.z, v))
        draft.strip(0, WALL_SURFACE)
        return draft^

    def generate_right_wall(
        self,
        road: Road,
        section: Int,
        lane: Int,
        s_start: Float64,
        s_end: Float64,
    ) raises -> BufferGeometry:
        """Return a wall on a lane's first edge, `GenerateRightWall`.

        Args:
            road: The road.
            section: The section's index.
            lane: The lane's index in the section.
            s_start: Where to start, in meters along the road.
            s_end: Where to end.

        Returns:
            A strip `wall_height` high. Lane 0 has none.

        Raises:
            Error: If the resolution is not positive, or a record is
                missing.
        """
        return _finish(
            self._wall_draft(road, section, lane, s_start, s_end, True)
        )

    def generate_left_wall(
        self,
        road: Road,
        section: Int,
        lane: Int,
        s_start: Float64,
        s_end: Float64,
    ) raises -> BufferGeometry:
        """Return a wall on a lane's second edge, `GenerateLeftWall`.

        Args:
            road: The road.
            section: The section's index.
            lane: The lane's index in the section.
            s_start: Where to start, in meters along the road.
            s_end: Where to end.

        Returns:
            A strip `wall_height` high. Lane 0 has none.

        Raises:
            Error: If the resolution is not positive, or a record is
                missing.
        """
        return _finish(
            self._wall_draft(road, section, lane, s_start, s_end, False)
        )

    def _walls_draft(
        self, road: Road, section: Int, s_start: Float64, s_end: Float64
    ) raises -> _Draft:
        # The outermost lanes on each side; a side with only lane 0 names
        # a lane that is not there.
        ref lanes = road.sections[section].lanes
        if len(lanes) == 0:
            raise Error("A section needs lanes for walls")
        var first = lanes[0].id.value
        var last = lanes[len(lanes) - 1].id.value
        var min_lane = 1 if first == 0 else first
        var max_lane = -1 if last == 0 else last
        var draft = _Draft()
        # The section has lanes.
        for lane in range(len(lanes)):  # pragma: no branch
            if lanes[lane].id.value == max_lane:
                draft.append(
                    self._wall_draft(road, section, lane, s_start, s_end, False)
                )
            if lanes[lane].id.value == min_lane:
                draft.append(
                    self._wall_draft(road, section, lane, s_start, s_end, True)
                )
        return draft^

    def generate_walls(self, road: Road, section: Int) raises -> BufferGeometry:
        """Return a section's two safety walls, `GenerateWalls`.

        The left wall stands on the last lane's second edge and the right
        wall on the first lane's first edge, over the whole section.

        Args:
            road: The road.
            section: The section's index.

        Returns:
            The walls.

        Raises:
            Error: If the section has no lanes, or `generate_right_wall`
                would raise.
        """
        var span = self._lane_s(road, section)
        return _finish(self._walls_draft(road, section, span[0], span[1]))

    # --- chunks -----------------------------------------------------------

    def _chunks(
        self, road: Road, section: Int
    ) raises -> List[Tuple[Float64, Float64, Bool]]:
        # The runs of `max_road_len` a long section is cut into, then the
        # rest, which is marked.
        if not (self.road_param.max_road_len.value > 0.0):
            raise Error("The chunk length must be positive")
        var out = List[Tuple[Float64, Float64, Bool]]()
        var start = road.sections[section].s
        var length = road.section_length(section)
        var max_len = Float64(self.road_param.max_road_len.value)
        var s = start + EPSILON
        var s_end = start + length - EPSILON
        while s + max_len < s_end:
            out.append((s, s + max_len, False))
            s += max_len
        if s_end - s > EPSILON:
            out.append((s, s_end, True))
        return out^

    def _is_long(self, road: Road, section: Int) -> Bool:
        return not (
            road.section_length(section)
            < Float64(self.road_param.max_road_len.value)
        )

    def generate_section_with_max_len(
        self, road: Road, section: Int
    ) raises -> List[BufferGeometry]:
        """Return a section cut into chunks, `GenerateWithMaxLen(section)`.

        Args:
            road: The road.
            section: The section's index.

        Returns:
            The whole section as one geometry if it is shorter than
            `max_road_len`, else one geometry per chunk of every lane.

        Raises:
            Error: If `generate_lane` would.
        """
        var out = List[BufferGeometry]()
        if not self._is_long(road, section):
            out.append(self.generate_section(road, section))
            return out^
        for chunk in self._chunks(road, section):
            var draft = _Draft()
            for lane in range(len(road.sections[section].lanes)):
                draft.append(
                    self._lane_draft(road, section, lane, chunk[0], chunk[1])
                )
            out.append(_finish(draft))
        return out^

    def generate_with_max_len(self, road: Road) raises -> List[BufferGeometry]:
        """Return a road cut into chunks, `GenerateWithMaxLen(road)`.

        Args:
            road: The road.

        Returns:
            Each section's chunks, section by section.

        Raises:
            Error: If `generate_lane` would.
        """
        var out = List[BufferGeometry]()
        for section in range(len(road.sections)):
            out.extend(self.generate_section_with_max_len(road, section))
        return out^

    def generate_section_walls_with_max_len(
        self, road: Road, section: Int
    ) raises -> List[BufferGeometry]:
        """Return a section's walls in chunks, `GenerateWallsWithMaxLen`.

        Args:
            road: The road.
            section: The section's index.

        Returns:
            The walls as one geometry, or one per chunk.

        Raises:
            Error: If `generate_walls` would.
        """
        var out = List[BufferGeometry]()
        if not self._is_long(road, section):
            out.append(self.generate_walls(road, section))
            return out^
        for chunk in self._chunks(road, section):
            out.append(
                _finish(self._walls_draft(road, section, chunk[0], chunk[1]))
            )
        return out^

    def generate_walls_with_max_len(
        self, road: Road
    ) raises -> List[BufferGeometry]:
        """Return a road's walls in chunks, `GenerateWallsWithMaxLen(road)`.

        Args:
            road: The road.

        Returns:
            Each section's wall chunks, section by section.

        Raises:
            Error: If `generate_walls` would.
        """
        var out = List[BufferGeometry]()
        for section in range(len(road.sections)):
            out.extend(self.generate_section_walls_with_max_len(road, section))
        return out^

    def generate_all_with_max_len(
        self, road: Road
    ) raises -> List[BufferGeometry]:
        """Return a road's chunks with their walls, `GenerateAllWithMaxLen`.

        A road outside a junction gets walls, each wall chunk joined to its
        road chunk.

        Args:
            road: The road.

        Returns:
            The chunks.

        Raises:
            Error: If `generate_lane` or `generate_walls` would.
        """
        var out = self.generate_with_max_len(road)
        if road.is_junction:
            return out^
        # The walls are cut where the lanes are, so there are as many wall
        # chunks as road chunks, and CARLA's other case never happens.
        var walls = self.generate_walls_with_max_len(road)
        for i in range(len(walls)):
            append_geometry(out[i], walls[i])
        return out^

    def _ordered_part(
        self,
        road: Road,
        section: Int,
        lane: Int,
        s_start: Float64,
        s_end: Float64,
    ) raises -> BufferGeometry:
        if road.sections[section].lanes[lane].type == LANE_DRIVING:
            return self.generate_tesselated(road, section, lane, s_start, s_end)
        return self.generate_sidewalk(road, section, lane, s_start, s_end)

    def _link_width(self, lane_type: LaneType) -> Int:
        if lane_type == LANE_DRIVING:
            return self._width_vertices()
        if lane_type == LANE_SIDEWALK:
            return 6
        return 2

    def _link_kinds(self, lane_type: LaneType) -> List[SurfaceKind]:
        # The kind of each quad across a stitch: a driving lane's grid is
        # all road; a block is curb, curb, top, curb, curb, of which a
        # link of two keeps the first.
        var out = List[SurfaceKind]()
        if lane_type == LANE_DRIVING:
            # A grid is two vertices across at least.
            for _ in range(self._width_vertices() - 1):  # pragma: no branch
                out.append(ROAD_SURFACE)
            return out^
        var top = (
            SIDEWALK_SURFACE if lane_type == LANE_SIDEWALK else ROAD_SURFACE
        )
        out = [CURB_SURFACE, CURB_SURFACE, top, CURB_SURFACE, CURB_SURFACE]
        return out^

    def generate_lane_section_ordered(
        self, road: Road, section: Int, mut result: OrderedMeshes
    ) raises:
        """Add each lane of a section by type, `GenerateLaneSectionOrdered`.

        A driving lane is tessellated; any other lane is a block. The lane
        at place i goes in as a new mesh when its type's list is no longer
        than i, and is stitched onto mesh i otherwise, as CARLA does.

        Args:
            road: The road.
            section: The section's index.
            result: The meshes by type, which grow.

        Raises:
            Error: If a lane's mesh cannot be made.
        """
        var span = self._lane_s(road, section)
        for lane in range(len(road.sections[section].lanes)):
            var lane_type = road.sections[section].lanes[lane].type
            var part = self._ordered_part(road, section, lane, span[0], span[1])
            var slot = result.slot(lane_type)
            if len(result.meshes[slot]) <= lane:
                result.meshes[slot].append(part^)
            else:
                concat_geometry(
                    result.meshes[slot][lane],
                    part,
                    self._link_width(lane_type),
                    self._link_kinds(lane_type),
                )

    def generate_section_ordered_with_max_len(
        self, road: Road, section: Int
    ) raises -> OrderedMeshes:
        """Return a section's lanes by type in chunks.

        This is `GenerateOrderedWithMaxLen(lane_section)`. A long section's
        later chunks are stitched onto the earlier ones by the same rule
        as `generate_lane_section_ordered`, and the last chunk is added
        without stitching, as in CARLA.

        Args:
            road: The road.
            section: The section's index.

        Returns:
            The meshes by type.

        Raises:
            Error: If a lane's mesh cannot be made.
        """
        var out = OrderedMeshes()
        if not self._is_long(road, section):
            self.generate_lane_section_ordered(road, section, out)
            return out^
        for chunk in self._chunks(road, section):
            for lane in range(len(road.sections[section].lanes)):
                var lane_type = road.sections[section].lanes[lane].type
                var part = self._ordered_part(
                    road, section, lane, chunk[0], chunk[1]
                )
                var slot = out.slot(lane_type)
                if len(out.meshes[slot]) <= lane:
                    out.meshes[slot].append(part^)
                elif chunk[2]:
                    append_geometry(out.meshes[slot][lane], part)
                else:
                    concat_geometry(
                        out.meshes[slot][lane],
                        part,
                        self._link_width(lane_type),
                        self._link_kinds(lane_type),
                    )
        return out^

    def generate_ordered_with_max_len(self, road: Road) raises -> OrderedMeshes:
        """Return a road's lanes by type, `GenerateOrderedWithMaxLen(road)`.

        CARLA joins the sections with `std::map::insert`, which keeps a
        type's meshes from the first section that has it and drops the
        later sections' meshes of that type. This port does the same.

        Args:
            road: The road.

        Returns:
            The meshes by type.

        Raises:
            Error: If a lane's mesh cannot be made.
        """
        var out = OrderedMeshes()
        for section in range(len(road.sections)):
            var part = self.generate_section_ordered_with_max_len(road, section)
            for i in range(len(part.types)):
                if out.find(part.types[i]) >= 0:
                    continue
                var slot = out.slot(part.types[i])
                # A type is listed with one mesh at least.
                for k in range(len(part.meshes[i])):  # pragma: no branch
                    out.meshes[slot].append(part.meshes[i][k].clone())
        return out^

    def generate_all_ordered_with_max_len(
        self, road: Road, mut roads: OrderedMeshes
    ) raises:
        """Add a road's lanes by type, `GenerateAllOrderedWithMaxLen`.

        Args:
            road: The road.
            roads: The meshes by type, which grow.

        Raises:
            Error: If a lane's mesh cannot be made.
        """
        var result = self.generate_ordered_with_max_len(road)
        for i in range(len(result.types)):
            var slot = roads.slot(result.types[i])
            # A type is listed with one mesh at least.
            for k in range(len(result.meshes[i])):  # pragma: no branch
                roads.meshes[slot].append(result.meshes[i][k].clone())

    # --- junction smoothing ---------------------------------------------------

    def merge_and_smooth(
        self, lane_meshes: List[BufferGeometry]
    ) raises -> BufferGeometry:
        """Smooth the heights where junction lanes meet, `MergeAndSmooth`.

        Each vertex but the first three and last two of its lane moves
        toward its 20 nearest neighbors' heights, 100 times, by half the
        weighted mean difference. A neighbor weighs one over its distance,
        twice that in the same lane, and twice again if it is a lane end;
        none past `max_weight_distance`.

        Args:
            lane_meshes: One geometry per lane.

        Returns:
            The lanes, joined, with the new heights.

        Raises:
            Error: If a geometry lacks its positions or UVs.
        """
        var drafts = List[_Draft]()
        var tree = PointCloudRtree()
        var owner = List[Int]()
        var fixed = List[Bool]()
        var flat = List[Tuple[Int, Int]]()
        for m in range(len(lane_meshes)):
            drafts.append(_draft_of(lane_meshes[m]))
            var n = len(drafts[m].positions)
            for i in range(n):
                tree.insert_element(drafts[m].positions[i], len(flat))
                flat.append((m, i))
                owner.append(m)
                fixed.append(i < 2 or i >= n - 2)
        var movers = List[Int]()
        var neighbors = List[List[Int]]()
        var weights = List[List[Float64]]()
        for v in range(len(flat)):
            var m = flat[v][0]
            var i = flat[v][1]
            var n = len(drafts[m].positions)
            if not (i > 2 and i < n - 2):
                continue
            var point = drafts[m].positions[i]
            var near = List[Int]()
            var weight = List[Float64]()
            var nearest = tree.get_nearest_neighbours(point, 20)
            # The tree holds the point itself.
            for found in nearest:  # pragma: no branch
                var other = found.value
                if other == v:
                    continue
                var w = self._weight(
                    point,
                    drafts[flat[other][0]].positions[flat[other][1]],
                    m == owner[other],
                    fixed[other],
                )
                if w > 0.0:
                    near.append(other)
                    weight.append(w)
            movers.append(v)
            neighbors.append(near^)
            weights.append(weight^)
        # A hundred passes, always.
        for _ in range(100):  # pragma: no branch
            for k in range(len(movers)):
                var v = movers[k]
                var z = drafts[flat[v][0]].positions[flat[v][1]].z
                var sum = 0.0
                var total = 0.0
                for j in range(len(neighbors[k])):
                    var other = neighbors[k][j]
                    var oz = drafts[flat[other][0]].positions[flat[other][1]].z
                    sum += Float64(oz - z) * weights[k][j]
                    total += weights[k][j]
                var laplacian = sum / total if total > 0.0 else 0.0
                drafts[flat[v][0]].positions[flat[v][1]].z += Float32(
                    0.5 * laplacian
                )
        var out = _Draft()
        for k in range(len(drafts)):
            out.append(drafts[k])
        return _finish(out)

    def _weight(
        self, a: Vector3, b: Vector3, same_lane: Bool, fixed: Bool
    ) -> Float64:
        # `ComputeVertexWeight`.
        var d = (a - b).length()
        if d > self.road_param.max_weight_distance.value:
            return 0.0
        if Float64(abs(d)) < EPSILON:
            return 0.0
        var weight = min(max(Float32(1.0) / d, Float32(0)), Float32(100000.0))
        if same_lane:
            weight *= self.road_param.same_lane_weight_multiplier
            if fixed:
                weight *= self.road_param.lane_ends_multiplier
        return Float64(weight)

    # --- lane marks -------------------------------------------------------

    def compute_edges_for_lanemark(
        self,
        road: Road,
        section: Int,
        lane: Int,
        s: Float64,
        width: Float64,
        extra_width: Float32,
    ) raises -> Tuple[Vector3, Vector3]:
        """Return a mark's two edges, `ComputeEdgesForLanemark`.

        The mark runs from the lane's first edge toward its second, one
        mark width. A lane of no width borrows the direction of the first
        lane of its section that has one.

        Args:
            road: The road.
            section: The section's index.
            lane: The lane's index in the section.
            s: The distance along the road, in meters.
            width: The mark's width, in meters.
            extra_width: The junction widening to pass on.

        Returns:
            The lane's first edge and the mark's other edge.

        Raises:
            Error: If a record is missing.
        """
        var edges = road.lane_corners(section, lane, s, extra_width)
        var director = Vector3(0, 0, 0)
        if edges[0] != edges[1]:
            director = edges[1] - edges[0]
            director = director / director.length()
        else:
            var count = len(road.sections[section].lanes)
            # The section holds the lane itself.
            for other in range(count):  # pragma: no branch
                var e = road.lane_corners(section, other, s, extra_width)
                if e[0] != e[1]:
                    director = e[1] - e[0]
                    director = director / director.length()
                    break
        return (edges[0], edges[0] + director * Float32(width))

    def _mark_quad(
        self, mut draft: _Draft, first: Vector3, second: Vector3, s: Float64
    ):
        var width = (second - first).length()
        draft.add(first, Vector2(0, Float32(s)))
        draft.add(second, Vector2(width, Float32(s)))

    def _center_edges(
        self, road: Road, s: Float64, width: Float64
    ) raises -> Tuple[Vector3, Vector3]:
        var right = road.directed_point(s)
        var left = right
        right.apply_lateral_offset(Length(Float32(width * 0.5), METER))
        left.apply_lateral_offset(Length(Float32(width * -0.5), METER))
        return (
            Vector3(Float32(right.x), Float32(-right.y), Float32(right.z)),
            Vector3(Float32(left.x), Float32(-left.y), Float32(left.z)),
        )

    def _marks(
        self, road: Road, section: Int, lane: Int, center: Bool
    ) raises -> Optional[LaneMarkMesh]:
        var draft = _Draft()
        var kind = YELLOW_MARK_SURFACE if center else WHITE_MARK_SURFACE
        var step = self._resolution()
        var s_start = road.sections[section].s
        var s_end = s_start + road.section_length(section)
        var s = s_start
        ref marks = road.sections[section].lanes[lane].info.marks
        while True:
            var found = info_at(marks, s)
            if not Bool(found):
                # CARLA would loop forever here.
                break
            var info = LaneMarking(found.value())
            var base = len(draft.positions)
            if info.type == SOLID:
                var e: Tuple[Vector3, Vector3]
                if center:
                    e = self._center_edges(road, s, info.width)
                else:
                    e = self.compute_edges_for_lanemark(
                        road, section, lane, s, info.width, 0.0
                    )
                self._mark_quad(draft, e[0], e[1], s)
                draft.triangle(base, base + 1, base + 2, kind)
                draft.triangle(base + 1, base + 3, base + 2, kind)
                s += step
            elif info.type == BROKEN:
                var e = self.compute_edges_for_lanemark(
                    road, section, lane, s, info.width, self._extra()
                )
                self._mark_quad(draft, e[0], e[1], s)
                s = min(s + step * 3.0, s_end)
                e = self.compute_edges_for_lanemark(
                    road, section, lane, s, info.width, self._extra()
                )
                self._mark_quad(draft, e[0], e[1], s)
                draft.triangle(base, base + 1, base + 2, kind)
                draft.triangle(base + 1, base + 3, base + 2, kind)
                s += step * 3.0
            else:
                s += step
            if not (s < s_end):
                break
        if len(draft.positions) == 0:
            return None
        # A mark was found at a smaller s, so one holds at s too.
        var width = LaneMarking(info_at(marks, s).value()).width
        var e: Tuple[Vector3, Vector3]
        if center:
            e = self._center_edges(road, s, width)
        else:
            e = self.compute_edges_for_lanemark(
                road, section, lane, s_end, width, 0.0
            )
        self._mark_quad(draft, e[0], e[1], s_end if not center else s)
        var color = "yellow" if center else "white"
        return LaneMarkMesh(_finish(draft), color)

    def generate_lane_marks_for_not_center_line(
        self, road: Road, section: Int, lane: Int
    ) raises -> Optional[LaneMarkMesh]:
        """Return the paint on a lane's first edge.

        This is `GenerateLaneMarksForNotCenterLine`. Solid paint is a strip
        of rows every resolution; broken paint is dashes of three
        resolutions with gaps of three. CARLA draws no other type. A row
        closes the paint at the section's end. The index of one step can
        reach into the next step's vertices, as CARLA's does.

        Args:
            road: The road.
            section: The section's index.
            lane: The lane's index in the section.

        Returns:
            The paint, or None where CARLA adds no mesh.

        Raises:
            Error: If the resolution is not positive, or a record is
                missing.
        """
        return self._marks(road, section, lane, False)

    def generate_lane_marks_for_center_line(
        self, road: Road, section: Int, lane: Int
    ) raises -> Optional[LaneMarkMesh]:
        """Return the paint on lane 0, `GenerateLaneMarksForCenterLine`.

        Solid paint is centered on lane 0. Broken paint runs from lane 0
        toward the first lane of the section that has a width, as CARLA's
        does.

        Args:
            road: The road.
            section: The section's index.
            lane: Lane 0's index in the section.

        Returns:
            The paint, or None where CARLA adds no mesh.

        Raises:
            Error: If the resolution is not positive, or a record is
                missing.
        """
        return self._marks(road, section, lane, True)

    def generate_lane_mark_for_road(
        self,
        road: Road,
        mut inout: List[LaneMarkMesh],
        mut outinfo: List[String],
    ) raises:
        """Add a road's lane marks, `GenerateLaneMarkForRoad`.

        Each driving lane adds its mark and the word "white"; each lane 0
        of type none adds its mark and "yellow". CARLA adds the word even
        when it adds no mesh, so the two lists can differ in length; a
        `LaneMarkMesh` carries its own color.

        Args:
            road: The road.
            inout: The marks, which grow.
            outinfo: CARLA's colors, which grow.

        Raises:
            Error: If a mark cannot be made.
        """
        for section in range(len(road.sections)):
            for lane in range(len(road.sections[section].lanes)):
                ref the_lane = road.sections[section].lanes[lane]
                if the_lane.id.value != 0:
                    if the_lane.type == LANE_DRIVING:
                        var mark = self.generate_lane_marks_for_not_center_line(
                            road, section, lane
                        )
                        if Bool(mark):
                            inout.append(mark.take())
                        outinfo.append("white")
                elif the_lane.type == LANE_NONE:
                    var mark = self.generate_lane_marks_for_center_line(
                        road, section, lane
                    )
                    if Bool(mark):
                        inout.append(mark.take())
                    outinfo.append("yellow")


# --- the map's meshes ---------------------------------------------------------


def _junction_lanes(
    map: Map, factory: MeshFactory, junction: Int, sidewalks: Bool
) raises -> Tuple[List[BufferGeometry], List[BufferGeometry]]:
    # Each lane of each connecting road, the sidewalks apart if asked.
    var lanes = List[BufferGeometry]()
    var walks = List[BufferGeometry]()
    for connection in map.junctions[junction].connections:
        ref road = map.road(connection.connecting_road)
        for section in range(len(road.sections)):
            for lane in range(len(road.sections[section].lanes)):
                var mesh = factory.generate_whole_lane(road, section, lane)
                if (
                    sidewalks
                    and road.sections[section].lanes[lane].type == LANE_SIDEWALK
                ):
                    walks.append(mesh^)
                else:
                    lanes.append(mesh^)
    return (lanes^, walks^)


def generate_mesh(
    map: Map,
    distance: Length,
    extra_width: Length = Length(0.6, METER),
    smooth_junctions: Bool = True,
) raises -> BufferGeometry:
    """Return the whole road surface of a map, `Map::GenerateMesh`.

    Args:
        map: The map.
        distance: The spacing of rows along each lane. It must be
            positive.
        extra_width: How far a junction's driving lanes widen.
        smooth_junctions: Whether to smooth the junctions' heights.

    Returns:
        Every road outside a junction, then every junction.

    Raises:
        Error: If the distance is not positive, or a lane's mesh cannot be
            made.
    """
    if not (distance.value > 0.0):
        raise Error("Mesh resolution must be positive")
    var factory = MeshFactory()
    factory.road_param.resolution = distance
    factory.road_param.extra_lane_width = extra_width
    var parts = List[BufferGeometry]()
    for road in map.roads:
        if not road.is_junction:
            parts.append(factory.generate_road(road))
    for j in range(len(map.junctions)):
        var split = _junction_lanes(map, factory, j, False)
        if smooth_junctions:
            parts.append(factory.merge_and_smooth(split[0]))
        else:
            parts.append(_join(split[0]))
    return _join(parts)


def generate_chunked_mesh(
    map: Map, params: OpendriveGenerationParameters
) raises -> List[BufferGeometry]:
    """Return a map's surface in square chunks, `GenerateChunkedMesh`.

    Each road outside a junction is cut with its walls, each junction is
    one piece, and each piece joins the chunk of a grid of
    `max_road_length` squares that holds its first vertex. A piece with no
    vertices is left out, where CARLA reads past its end.

    Args:
        map: The map.
        params: The generation parameters.

    Returns:
        The chunks, row by row of the grid.

    Raises:
        Error: If the map gives no piece, or a lane's mesh cannot be made.
    """
    var factory = MeshFactory(params)
    var pieces = List[BufferGeometry]()
    for road in map.roads:
        if not road.is_junction:
            pieces.extend(factory.generate_all_with_max_len(road))
    for j in range(len(map.junctions)):
        var split = _junction_lanes(map, factory, j, True)
        var merged: BufferGeometry
        if params.smooth_junctions:
            merged = factory.merge_and_smooth(split[0])
        else:
            merged = _join(split[0])
        for k in range(len(split[1])):
            append_geometry(merged, split[1][k])
        pieces.append(merged^)
    var firsts = List[Vector3]()
    var kept = List[Int]()
    for i in range(len(pieces)):
        if pieces[i].vertex_count() > 0:
            firsts.append(pieces[i].attribute_view(POSITION).vector3(0))
            kept.append(i)
    if len(kept) == 0:
        raise Error("The map gives no mesh to chunk")
    var low = firsts[0]
    var high = firsts[0]
    # One piece was kept at least.
    for p in firsts:  # pragma: no branch
        low.x = min(low.x, p.x)
        low.y = min(low.y, p.y)
        high.x = max(high.x, p.x)
        high.y = max(high.y, p.y)
    var size = params.max_road_length.value
    var nx = Int((high.x - low.x) / size) + 1
    var ny = Int((high.y - low.y) / size) + 1
    var cells = List[_Draft]()
    # The grid has one cell at least.
    for _ in range(nx * ny):  # pragma: no branch
        cells.append(_Draft())
    # One piece was kept at least.
    for k in range(len(kept)):  # pragma: no branch
        var x = Int((firsts[k].x - low.x) / size)
        var y = Int((firsts[k].y - low.y) / size)
        cells[x + nx * y].append(_draft_of(pieces[kept[k]]))
    var out = List[BufferGeometry]()
    # The grid has one cell at least.
    for k in range(len(cells)):  # pragma: no branch
        out.append(_finish(cells[k]))
    return out^


def filter_junctions_by_position(
    map: Map, low: Vector3, high: Vector3
) -> List[JuncId]:
    """Return the junctions CARLA keeps for a region, `FilterJunctionsByPosition`.

    CARLA keeps a junction whose center has `low.x < x < high.x` and
    `low.y > y > high.y`: its y test runs the other way.

    Args:
        map: The map.
        low: The region's first corner, in CARLA's frame.
        high: Its second corner.

    Returns:
        The kept junctions, in order of id.
    """
    var out = List[JuncId]()
    for junction in map.junctions:
        var at = junction.location()
        if low.x < at.x and at.x < high.x and low.y > at.y and at.y > high.y:
            out.append(junction.id)
    return out^


def filter_roads_by_position(
    map: Map, low: Vector3, high: Vector3
) raises -> List[RoadId]:
    """Return the roads CARLA keeps for a region, `FilterRoadsByPosition`.

    A road is placed by its first section's innermost lane, -1 on a
    right-hand road and 1 on a left-hand one, or else its innermost
    driving lane, at half the section's length, and kept by the same test
    as `filter_junctions_by_position`.

    Args:
        map: The map.
        low: The region's first corner, in CARLA's frame.
        high: Its second corner.

    Returns:
        The kept roads, in order of id.

    Raises:
        Error: If a road has no section, or a lane's records are missing.
    """
    var out = List[RoadId]()
    for road in map.roads:
        if len(road.sections) == 0:
            raise Error("A road needs a lane section")
        ref section = road.sections[0]
        var lane = section.lane_index(LaneId(-1 if road.is_rht else 1))
        if lane < 0:
            var best = 2147483647
            for i in range(len(section.lanes)):
                var id = section.lanes[i].id.value
                if (
                    id != 0
                    and section.lanes[i].type == LANE_DRIVING
                    and abs(id) < best
                ):
                    best = abs(id)
                    lane = i
        if lane < 0:
            continue
        var s = section.s + road.section_length(0) * 0.5
        var at = road.lane_transform(0, lane, s).location
        if low.x < at.x and at.x < high.x and low.y > at.y and at.y > high.y:
            out.append(road.id)
    return out^


def generate_single_junction(
    map: Map,
    factory: MeshFactory,
    id: JuncId,
    mut out: OrderedMeshes,
) raises:
    """Add one junction's surface and sidewalks, `GenerateSingleJunction`.

    The driving surface is the connecting lanes, tessellated and joined.
    A junction of more than two connections keeps only the sidewalks whose
    middle is not on a driving lane, as CARLA's does; CARLA also builds
    that junction's surface with marching cubes from a third-party
    library, which this port leaves out.

    Args:
        map: The map.
        factory: The factory.
        id: The junction.
        out: The meshes by type, which gain one driving and one sidewalk
            mesh.

    Raises:
        Error: If the junction or a lane's mesh is missing.
    """
    ref junction = map.junction(id)
    var many = len(junction.connections) > 2
    var lanes = _Draft()
    var walks = _Draft()
    for connection in junction.connections:
        ref road = map.road(connection.connecting_road)
        for section in range(len(road.sections)):
            for lane in range(len(road.sections[section].lanes)):
                ref the_lane = road.sections[section].lanes[lane]
                if the_lane.type != LANE_SIDEWALK:
                    lanes.append(
                        _draft_of(
                            factory.generate_whole_tesselated(
                                road, section, lane
                            )
                        )
                    )
                    continue
                if many:
                    var s = (
                        the_lane.distance + road.section_length(section) * 0.5
                    )
                    var w = map.waypoint_xodr(
                        road.id, the_lane.id, Length(Float32(s), METER)
                    )
                    if not Bool(w):
                        raise Error("A junction sidewalk has no middle")
                    var place = map.compute_transform(w.value()).location
                    if Bool(map.waypoint(place)):
                        continue
                walks.append(
                    _draft_of(
                        factory.generate_whole_sidewalk(road, section, lane)
                    )
                )
    out.meshes[out.slot(LANE_DRIVING)].append(_finish(lanes))
    out.meshes[out.slot(LANE_SIDEWALK)].append(_finish(walks))


def generate_ordered_chunked_mesh_in_locations(
    map: Map,
    params: OpendriveGenerationParameters,
    low: Vector3,
    high: Vector3,
) raises -> OrderedMeshes:
    """Return a region's meshes by lane type.

    This is `GenerateOrderedChunkedMeshInLocations`: the kept roads' lanes
    by type, then the kept junctions'. CARLA builds them on threads; this
    builds them in order.

    Args:
        map: The map.
        params: The generation parameters.
        low: The region's first corner, in CARLA's frame.
        high: Its second corner.

    Returns:
        The meshes by type.

    Raises:
        Error: If a mesh cannot be made.
    """
    var factory = MeshFactory(params)
    var roads = OrderedMeshes()
    for id in filter_roads_by_position(map, low, high):
        ref road = map.road(id)
        if not road.is_junction:
            factory.generate_all_ordered_with_max_len(road, roads)
    var junctions = OrderedMeshes()
    for id in filter_junctions_by_position(map, low, high):
        generate_single_junction(map, factory, id, junctions)
    for i in range(len(junctions.types)):
        var slot = roads.slot(junctions.types[i])
        # A type is listed with one mesh at least.
        for k in range(len(junctions.meshes[i])):  # pragma: no branch
            roads.meshes[slot].append(junctions.meshes[i][k].clone())
    return roads^


@fieldwise_init
struct TreeTransform(Copyable, Movable):
    """Where a tree stands and the road type beside it."""

    var transform: CarlaTransform
    # The lane's speed record's type, or "Town".
    var type: String


def trees_transform(
    map: Map,
    low: Vector3,
    high: Vector3,
    distance_between_trees: Length,
    distance_from_border: Length,
    s_offset: Length = Length(0.0, METER),
) raises -> List[TreeTransform]:
    """Return where trees stand along the roads, `Map::GetTreesTransform`.

    On each section of each kept road outside a junction, trees stand
    every `distance_between_trees` beside the outermost right driving
    lane, or the outermost left one where there is no right one, a
    distance out from its outer edge, facing the way the lane runs.

    Args:
        map: The map.
        low: The region's first corner, in CARLA's frame.
        high: Its second corner.
        distance_between_trees: The spacing along the road. It must be
            positive.
        distance_from_border: How far out from the lane's edge.
        s_offset: Where along each section to start.

    Returns:
        The trees.

    Raises:
        Error: If the spacing is not positive, or a lane's records are
            missing.
    """
    if not (distance_between_trees.value > 0.0):
        raise Error("The distance between trees must be positive")
    var out = List[TreeTransform]()
    comptime tiny = 1.0e-4
    for id in filter_roads_by_position(map, low, high):
        ref road = map.road(id)
        if road.is_junction:
            continue
        # A kept road has a section.
        for sec in range(len(road.sections)):  # pragma: no branch
            ref section = road.sections[sec]
            var min_lane = 0
            var max_lane = 0
            for lane in section.lanes:
                if lane.type == LANE_DRIVING:
                    var lid = lane.id.value
                    # LaneSection stores IDs in ascending order. The first
                    # negative driving lane is already the outermost one.
                    if lid < 0 and min_lane == 0:
                        min_lane = lid
                    elif lid > 0:
                        # The lanes come in order of id, so a later one
                        # is farther out.
                        max_lane = lid
            var outer = min_lane if min_lane != 0 else max_lane
            if outer == 0:
                continue
            var ln = section.lane_index(LaneId(outer))
            var s = section.s + Float64(s_offset.value)
            var s_end = section.s + road.section_length(sec)
            while s < s_end:
                if road.lane_width(sec, ln, s) != 0.0:
                    var edges = road.lane_corners(sec, ln, s, 0.0)
                    var d = edges[1] - edges[0]
                    var squared = (
                        Float64(d.x) * Float64(d.x)
                        + Float64(d.y) * Float64(d.y)
                        + Float64(d.z) * Float64(d.z)
                    )
                    if squared <= tiny * tiny:
                        s += Float64(distance_between_trees.value)
                        continue
                    var positive = outer > 0
                    var outer_corner = edges[1] if positive else edges[0]
                    var inner_corner = edges[0] if positive else edges[1]
                    var outward = make_unit_vector(outer_corner - inner_corner)
                    var position = (
                        outer_corner + outward * distance_from_border.value
                    )
                    var rotation = road.lane_transform(sec, ln, s).rotation
                    var speed = info_at(section.lanes[ln].info.speeds, s)
                    var type = String("Town")
                    if Bool(speed):
                        type = speed.value().type
                    var placed = CarlaTransform(
                        Length(position.x, METER),
                        Length(position.y, METER),
                        Length(position.z, METER),
                        rotation,
                    )
                    out.append(TreeTransform(placed, type))
                s += Float64(distance_between_trees.value)
    return out^


def all_crosswalk_mesh(map: Map) raises -> BufferGeometry:
    """Return every crosswalk as triangle fans, `GetAllCrosswalkMesh`.

    Each outline from `all_crosswalk_zones` closes where a corner repeats
    its first; an outline that never closes is left out, as in CARLA.

    Args:
        map: The map.

    Returns:
        The fans, in the crosswalk kind.

    Raises:
        Error: If `all_crosswalk_zones` would.
    """
    var zones = map.all_crosswalk_zones()
    var draft = _Draft()
    if len(zones) == 0:
        return _finish(draft)
    var start = 0
    var i = 0
    var fan = List[Vector3]()
    while True:
        if i != 0 and zones[start] == zones[i]:
            _fan(draft, fan)
            fan.clear()
            if i >= len(zones) - 1:
                break
            i += 1
            start = i
        fan.append(zones[i])
        i += 1
        if not (i < len(zones)):
            break
    return _finish(draft)


def _fan(mut draft: _Draft, corners: List[Vector3]):
    # `Mesh::AddTriangleFan`, turned to face up.
    var area = Float32(0)
    # A fan starts with its first corner.
    for k in range(len(corners)):  # pragma: no branch
        var a = corners[k]
        var b = corners[(k + 1) % len(corners)]
        area += a.x * b.y - b.x * a.y
    var first = len(draft.positions)
    # A fan starts with its first corner.
    for c in corners:  # pragma: no branch
        draft.add(c, Vector2(c.x, c.y))
    for k in range(1, len(corners) - 1):
        if area < 0.0:
            draft.triangle(first, first + k + 1, first + k, CROSSWALK_SURFACE)
        else:
            draft.triangle(first, first + k, first + k + 1, CROSSWALK_SURFACE)


def generate_line_markings(
    map: Map,
    params: OpendriveGenerationParameters,
    low: Vector3,
    high: Vector3,
    mut outinfo: List[String],
) raises -> List[LaneMarkMesh]:
    """Return the lane marks of a region's roads, `GenerateLineMarkings`.

    Args:
        map: The map.
        params: The generation parameters.
        low: The region's first corner, in CARLA's frame.
        high: Its second corner.
        outinfo: CARLA's colors, which grow.

    Returns:
        The marks of each kept road outside a junction.

    Raises:
        Error: If a mark cannot be made.
    """
    var factory = MeshFactory(params)
    var out = List[LaneMarkMesh]()
    for id in filter_roads_by_position(map, low, high):
        ref road = map.road(id)
        if not road.is_junction:
            factory.generate_lane_mark_for_road(road, out, outinfo)
    return out^


def junctions_bounding_boxes(map: Map) -> List[Box3]:
    """Return each junction's box, half as big again, `GetJunctionsBoundingBoxes`.

    Args:
        map: The map.

    Returns:
        One box per junction, in order of id, with the same center and
        1.5 times the extent.

    """
    var out = List[Box3]()
    for junction in map.junctions:
        var center = junction.location()
        var extent = junction.extent() * 1.5
        out.append(Box3(center - extent, center + extent))
    return out^
