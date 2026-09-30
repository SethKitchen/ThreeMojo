# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A CARLA town as a ThreeMojo scene: roads, paint, buildings, trees, lamps.

`Town` turns a `Map` into meshes and physically based materials. It uses
CARLA's own mesh factory for the road: `generate_mesh` for the lanes,
sidewalks and curbs, `generate_lane_mark_for_road` for the paint, and
`trees_transform` for where the trees stand. The rest is this port's
dressing, placed from the map's lanes:

- **Materials by surface kind.** The road mesh has one group per
  `SurfaceKind`. The town splits it into one mesh per kind, each with
  the kind's material and semantic tag. The road is asphalt, the
  sidewalk and the curb are concrete, the walls are darker concrete, and
  the crosswalk and the lane marks are white or yellow paint. The asphalt
  and the concrete carry the procedural color, roughness and normal maps
  of `render_textures`.
- **Crosswalks** are zebra stripes, 0.5 m wide with 0.5 m gaps, cut from
  each crosswalk outline of `Map.all_crosswalk_zones`.
- **Buildings** stand on lots beside each road outside a junction, back
  from the outer edge of its outermost lane. A lot that comes near
  another road or another lot is left empty. Each building has a row of
  shops on its ground floor, a cornice above it, floors of windows, and
  a parapet round its roof. A ring of tall buildings far out makes the
  skyline.
- **Street lamps** stand at the outer edge of each road's outermost lanes,
  with an arm over the road and a lamp that is a spot light. They light at
  night.
- **The ground** is paving near the roads and a lawn out to the horizon.

`set_weather` wets the road, fills its puddles and lights the lamps and
the windows. See `render_weather` for the mappings. `tags` holds the
semantic tag of each mesh the town adds, for the semantic camera.

**Frames.** The map is in CARLA's frame. Every mesh is placed in
three.js's frame with `mesh_factory.to_three_frame` or
`CarlaTransform.three_matrix`.

The sizes, colors and spacings here are this port's own choices.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    GeometryGroup,
    MaterialIndex,
    NORMAL,
    POSITION,
    UV,
)
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.carla.map import Map, Waypoint
from extensions.carla.mesh_factory import (
    CROSSWALK_SURFACE,
    CURB_SURFACE,
    LaneMarkMesh,
    MeshFactory,
    ROAD_SURFACE,
    SIDEWALK_SURFACE,
    SurfaceKind,
    WALL_SURFACE,
    WHITE_MARK_SURFACE,
    YELLOW_MARK_SURFACE,
    generate_mesh,
    to_three_frame,
    trees_transform,
)
from extensions.carla.assets import (
    AssetRegistry,
    ModelPlacement,
    TownPlacement,
    repeat_model,
    surface_key,
)
from extensions.carla.render_textures import (
    BRICK,
    FACADE_TILE,
    FacadeStyle,
    PANELS,
    SHOPFRONT,
    PLASTER,
    SurfaceMaps,
    asphalt_maps,
    concrete_maps,
    facade_maps,
    foliage_maps,
    grass_maps,
    hash2,
    place,
    puddle_roughness,
)
from extensions.carla.render_weather import (
    PUDDLE_ROUGHNESS,
    WET_ROUGHNESS,
    WetSurface,
    street_lights_on,
    wet_surface,
)
from extensions.carla.road import Road
from extensions.carla.sensor import (
    BUILDING,
    CAR,
    FENCE,
    GROUND,
    POLE,
    RAIL_TRACK,
    ROAD,
    ROAD_LINE,
    SIDEWALK,
    STATIC,
    SemanticTag,
    TERRAIN,
    TRAFFIC_LIGHT,
    TRAFFIC_SIGN,
    VEGETATION,
    WALL,
    WATER,
)
from extensions.carla.world import surface_tag
from extensions.carla.road_info import (
    LANE_ANY,
    LANE_DRIVING,
    LANE_SIDEWALK,
    LaneId,
    RoadId,
    SectionId,
)
from extensions.carla.transform import CarlaRotation, CarlaTransform
from extensions.carla.weather import WeatherParameters
from geometries.box import box
from geometries.cylinder import cylinder
from geometries.plane import plane
from geometries.sphere import sphere
from geometries.rounded_box import rounded_box
from geometries.utils import merge_geometries
from lights.light import spot_light
from materials.material import (
    DOUBLE_SIDE,
    MaterialId,
    standard_material,
)
from math.bounds import Box3
from math.noise import ImprovedNoise
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.color_utils import kelvin_color
from render.cube_texture_store import SCENE_ENVIRONMENT
from render.framebuffer import Color
from render.srgb import linear_to_srgb
from render.texture import Texture
from render.texture_store import TextureId
from std.math import atan2, cos, pow, sin, sqrt
from units.si import DEGREE, METER, RADIAN, Angle, Length
from units.temperature import KELVIN, Temperature

# How many procedural trees share a mesh.
comptime TREES_PER_MESH = 4
# How many surface kinds the road mesh has, and so how many materials.
comptime SURFACE_KINDS = 7
# The meters one asphalt, concrete and lawn tile covers.
comptime ASPHALT_TILE = Length(6, METER)
comptime CONCRETE_TILE = Length(3, METER)
comptime GRASS_TILE = Length(8, METER)
comptime PAVING_TILE = Length(4, METER)
# How far past the roads' corners the skyline starts, and how many
# buildings it has.
comptime SKYLINE_GAP = Length(90, METER)
comptime SKYLINE_COUNT = 40
# How far past the roads the paving and the lawn reach.
comptime PAVING_MARGIN = Length(24, METER)
comptime LAWN_MARGIN = Length(600, METER)
# How tall a building's row of shops is, and the parapet round its roof.
comptime GROUND_FLOOR = Length(4, METER)
comptime PARAPET = Length(0.7, METER)
# How high the paint and the crosswalks stand above the road.
comptime PAINT_LIFT = Float32(0.012)
# A crosswalk stripe's width and the gap after it.
comptime STRIPE = Float32(0.5)
comptime STRIPE_GAP = Float32(0.5)
# A lamp's color and how bright it is when lit.
comptime LAMP_KELVIN = Float32(3000)
comptime LAMP_INTENSITY = Float32(160)
comptime LAMP_GLOW = Float32(6)
# How tall a scanned tree model stands.
comptime TREE_HEIGHT = Float32(8)
# How bright the lit windows are at night.
comptime WINDOW_GLOW = Float32(0.45)
# The dry roughness of each surface kind.
comptime ASPHALT_ROUGHNESS = Float32(1)
comptime CONCRETE_ROUGHNESS = Float32(1)
comptime PAINT_ROUGHNESS = Float32(0.55)


struct TownSettings(Copyable, Movable):
    """How a town is built."""

    # The spacing of the road mesh's rows.
    var resolution: Length
    # Texels on a side of each procedural texture.
    var texture_size: Int
    var buildings: Bool
    var trees: Bool
    var lamps: Bool
    # How far apart the lamps and the trees stand.
    var lamp_spacing: Length
    var tree_spacing: Length
    # How far a building stands back from the outermost lane's edge.
    var setback: Length
    # Which dressing; the same seed builds the same town.
    var seed: Int
    # The CARLA town whose package to draw, such as `Town02`, or empty for
    # none. When the registry's cache holds `town.<package>`, the package
    # stands in for the procedural roads, ground, buildings, trees and
    # lamps.
    var package: String
    # How far from a package tile's center its near meshes show.
    var near_distance: Length

    def __init__(out self):
        """Start with a detailed town: 1 m rows, 512-texel textures,
        every kind of dressing, and no package."""
        self.resolution = Length(1, METER)
        self.texture_size = 512
        self.buildings = True
        self.trees = True
        self.lamps = True
        self.lamp_spacing = Length(24, METER)
        self.tree_spacing = Length(12, METER)
        self.setback = Length(4, METER)
        self.seed = 1
        self.package = String()
        self.near_distance = Length(50, METER)


def surface_color(kind: SurfaceKind) raises -> Color:
    """Return the dry color a surface kind's material multiplies its map by.

    Args:
        kind: The surface.

    Returns:
        White for the textured road and concrete, a darker gray for a
        wall, off-white paint for a crosswalk and a white mark, and yellow
        paint for a yellow mark.

    Raises:
        Error: If the kind is not valid.
    """
    if not kind.is_valid():
        raise Error("A surface kind must be one of the seven")
    if kind == WALL_SURFACE:
        return Color(170, 166, 160)
    if kind == CROSSWALK_SURFACE or kind == WHITE_MARK_SURFACE:
        return Color(226, 226, 220)
    if kind == YELLOW_MARK_SURFACE:
        return Color(226, 170, 40)
    return Color(255, 255, 255)


def surface_roughness(kind: SurfaceKind) raises -> Float32:
    """Return the dry roughness a surface kind's material scales its map by.

    Args:
        kind: The surface.

    Returns:
        One for the asphalt and the concrete, whose maps hold the
        roughness, and `PAINT_ROUGHNESS` for the paint.

    Raises:
        Error: If the kind is not valid.
    """
    if not kind.is_valid():
        raise Error("A surface kind must be one of the seven")
    if kind == ROAD_SURFACE:
        return ASPHALT_ROUGHNESS
    if kind.value <= WALL_SURFACE.value:
        return CONCRETE_ROUGHNESS
    return PAINT_ROUGHNESS


def wet_color(dry: Color, wet: WetSurface) -> Color:
    """Return a surface's color when wet.

    The color is darkened in linear light, by `WetSurface.albedo_scale`.

    Args:
        dry: The dry color, in sRGB.
        wet: How wet the surface is.

    Returns:
        The wet color, in sRGB.
    """
    var scale = wet.albedo_scale()
    return Color(
        _darker(dry.r, scale), _darker(dry.g, scale), _darker(dry.b, scale)
    )


def _darker(channel: UInt8, scale: Float32) -> UInt8:
    """Return an sRGB byte scaled in linear light."""
    var linear = pow(Float32(channel) / 255, Float32(2.2)) * scale
    return UInt8(Int(pow(linear, Float32(1) / Float32(2.2)) * 255 + 0.5))


struct TownMaterials(Copyable, Movable):
    """The materials a town wears."""

    # One per `SurfaceKind`, in kind order.
    var surfaces: List[MaterialId]
    var ground: MaterialId
    var paving: MaterialId
    # One per `FacadeStyle`, in style order; the last is the shop front.
    var facades: List[MaterialId]
    var roof: MaterialId
    # The cornices and parapets.
    var trim: MaterialId
    var trunk: MaterialId
    var leaves: MaterialId
    var metal: MaterialId
    var lamp: MaterialId

    def __init__(out self):
        """Start with no materials; `Town` fills them."""
        self.surfaces = List[MaterialId]()
        self.ground = MaterialId(0)
        self.paving = MaterialId(0)
        self.facades = List[MaterialId]()
        self.roof = MaterialId(0)
        self.trim = MaterialId(0)
        self.trunk = MaterialId(0)
        self.leaves = MaterialId(0)
        self.metal = MaterialId(0)
        self.lamp = MaterialId(0)

    def surface(self, kind: SurfaceKind) raises -> MaterialId:
        """Return the material a surface kind wears.

        Args:
            kind: The surface.

        Returns:
            Its material.

        Raises:
            Error: If the kind is not valid or the town has no materials.
        """
        if not kind.is_valid() or kind.value >= len(self.surfaces):
            raise Error("The town has no material for that surface kind")
        return self.surfaces[kind.value]


@fieldwise_init
struct Lot(ImplicitlyCopyable, Writable):
    """Where a building stands, in CARLA's frame."""

    # The middle of its footprint, on the ground.
    var center: Vector3
    # Which way its front faces: the road's heading there.
    var yaw: Angle
    # Along the road, across it and up.
    var width: Length
    var depth: Length
    var height: Length
    var style: FacadeStyle

    def write_to(self, mut writer: Some[Writer]):
        """Write the lot.

        Args:
            writer: The destination.
        """
        writer.write(
            "Lot(",
            self.center.x,
            ", ",
            self.center.y,
            ", w=",
            self.width.to(METER),
            ", h=",
            self.height.to(METER),
            ")",
        )


@fieldwise_init
struct LampPost(ImplicitlyCopyable):
    """Where a street lamp stands, in CARLA's frame."""

    # The foot of the pole, on the ground.
    var foot: Vector3
    # The unit direction from the pole over the road.
    var inward: Vector3


def roadside(
    road: Road, s: Float64, right: Bool
) raises -> Optional[Tuple[Vector3, Vector3]]:
    """Return the outer edge of a road's outermost lane and the way out.

    Args:
        road: The road.
        s: Meters along it; clamped to the road.
        right: True for the right side of the reference line, False for
            the left.

    Returns:
        The edge's point at s and the unit direction away from the road,
        both in CARLA's frame and level; None when the road has no lane on
        that side there.

    Raises:
        Error: If a lane's records are missing.
    """
    var section = 0
    # A road has at least one lane section.
    for index in range(len(road.sections)):  # pragma: no branch
        if road.sections[index].s <= s:
            section = index
    ref lanes = road.sections[section].lanes
    var lane = 0 if right else len(lanes) - 1
    if lanes[lane].id.value == 0:
        return None
    var corners = road.lane_corners(section, lane, s)
    var outer = corners[0] if right else corners[1]
    var inner = corners[1] if right else corners[0]
    var away = Vector3(outer.x - inner.x, outer.y - inner.y, 0)
    away.normalize()
    return (Vector3(outer.x, outer.y, outer.z), away)


def _clear_of_roads(map: Map, center: Vector3, radius: Float32) raises -> Bool:
    """Return True when a circle is clear of every driving lane and
    sidewalk of the map."""
    var found = map.closest_waypoint_on_road(
        center, LANE_DRIVING | LANE_SIDEWALK
    )
    if not Bool(found):
        return True
    var w = found.value()
    var at = map.compute_transform(w).location
    var gap = Vector3(at.x - center.x, at.y - center.y, 0).length()
    return gap - Float32(map.lane_width_meters(w)) / 2 > radius


def building_lots(map: Map, settings: TownSettings) raises -> List[Lot]:
    """Return the lots of a town's buildings.

    Along each side of each road outside a junction, a lot every 10 to
    18 m, 12 m deep, 6 to 24 m tall, set back `settings.setback` from the
    outer edge. A lot within 1 m of a lane or another lot is dropped.

    Args:
        map: The map.
        settings: The setback and the seed.

    Returns:
        The lots.

    Raises:
        Error: If a map query fails.
    """
    var lots = List[Lot]()
    for road in map.roads:
        if road.is_junction:
            continue
        # A constant count, more than zero.
        for side in range(2):  # pragma: no branch
            var s = Float64(2)
            var n = 0
            while s < road.length - 6:
                var h = hash2(road.id.value, n * 2 + side, settings.seed)
                var width = Float32(10) + h * 8
                var mid = min(s + Float64(width) / 2, road.length)
                var found = roadside(road, mid, side == 0)
                if not Bool(found):
                    break
                var edge = found.value()
                var depth = Float32(12)
                var back = settings.setback.to(METER) + depth / 2
                var center = edge[0] + edge[1] * back
                var radius = sqrt(width * width + depth * depth) / 2
                var free = _clear_of_roads(map, center, radius - depth / 2)
                for other in lots:
                    var gap = Vector3(
                        other.center.x - center.x, other.center.y - center.y, 0
                    ).length()
                    if gap < radius + other.width.to(METER) / 2 + 1:
                        free = False
                if free:
                    var tangent = road.directed_point(mid).tangent
                    lots.append(
                        Lot(
                            Vector3(center.x, center.y, edge[0].z),
                            Angle(Float32(-tangent), RADIAN),
                            Length(width, METER),
                            Length(depth, METER),
                            Length(
                                6
                                + hash2(n, road.id.value, settings.seed + 3)
                                * 18,
                                METER,
                            ),
                            FacadeStyle((n + side + road.id.value) % 3),
                        )
                    )
                s += Float64(width) + 1.5
                n += 1
    return lots^


def skyline_lots(bounds: Box3, count: Int, seed: Int) raises -> List[Lot]:
    """Return a ring of tall buildings far around a town, for its skyline.

    The lots stand evenly round a circle `SKYLINE_GAP` past the corners
    of the roads' box, each pushed out by up to 120 m, turned to face the
    middle, 18 to 42 m wide, 20 m deep and 20 to 80 m tall.

    Args:
        bounds: The roads' box, in CARLA's frame.
        count: How many lots; at least one.
        seed: Which skyline.

    Returns:
        The lots.

    Raises:
        Error: If the count is less than one.
    """
    if count < 1:
        raise Error("A skyline needs at least one building")
    var middle = (bounds.min + bounds.max) * Float32(0.5)
    var corner = Vector3(
        bounds.max.x - middle.x, bounds.max.y - middle.y, 0
    ).length()
    var lots = List[Lot]()
    # The count is checked to be one or more.
    for k in range(count):  # pragma: no branch
        var turn = (Float32(k) + hash2(k, 1, seed) * 0.6) / Float32(count)
        var angle = turn * Float32(6.283185307179586)
        var reach = corner + SKYLINE_GAP.to(METER) + hash2(k, 2, seed) * 120
        var at = Vector3(
            middle.x + cos(angle) * reach, middle.y + sin(angle) * reach, 0
        )
        lots.append(
            Lot(
                Vector3(at.x, at.y, bounds.min.z),
                Angle(angle + Float32(1.5707963267948966), RADIAN),
                Length(18 + hash2(k, 3, seed) * 24, METER),
                Length(20, METER),
                Length(20 + hash2(k, 4, seed) * 60, METER),
                FacadeStyle(k % 3),
            )
        )
    return lots^


def lamp_posts(map: Map, spacing: Length) raises -> List[LampPost]:
    """Return where a town's street lamps stand.

    On each side of each road outside a junction, a lamp every `spacing`,
    starting half a spacing in, 0.4 m inside the outermost lane's outer
    edge.

    Args:
        map: The map.
        spacing: How far apart. It must be positive.

    Returns:
        The lamps.

    Raises:
        Error: If the spacing is not positive, or a map query fails.
    """
    if not (spacing.to(METER) > 0):
        raise Error("Street lamps need a positive spacing")
    var step = Float64(spacing.to(METER))
    var posts = List[LampPost]()
    for road in map.roads:
        if road.is_junction:
            continue
        # A constant count, more than zero.
        for side in range(2):  # pragma: no branch
            var s = step / 2
            while s < road.length:
                var found = roadside(road, s, side == 0)
                if not Bool(found):
                    break
                var edge = found.value()
                var inward = Vector3(-edge[1].x, -edge[1].y, 0)
                posts.append(LampPost(edge[0] + inward * 0.4, inward))
                s += step
    return posts^


def crosswalk_stripes(zones: List[Vector3]) raises -> BufferGeometry:
    """Return the zebra stripes of crosswalks, in CARLA's frame.

    The zones are closed outlines one after another, each ending on its
    first corner, as `Map.all_crosswalk_zones` gives them. Each outline of
    four corners gets stripes `STRIPE` wide with `STRIPE_GAP` between,
    across its longer side, each running the length of its shorter side.
    Any other outline is left out.

    Args:
        zones: The outlines.

    Returns:
        The stripes, `PAINT_LIFT` above the outline, facing up, in one
        group of `CROSSWALK_SURFACE`. Empty for no crosswalk.

    Raises:
        Error: Never for finite corners; the geometry's checks are passed
            on.
    """
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var index = List[Int]()
    var start = 0
    for i in range(1, len(zones)):
        if not (zones[i] == zones[start]):
            continue
        if i - start == 4:
            var a = zones[start]
            var side_one = zones[start + 1] - a
            var side_two = zones[start + 3] - a
            var along = side_one
            var across = side_two
            if side_two.length() > side_one.length():
                along = side_two
                across = side_one
            var length = along.length()
            var unit = along * (1 / length)
            var t = Float32(0.25)
            while t + STRIPE <= length:
                var p0 = a + unit * t
                var p1 = p0 + unit * STRIPE
                var corners: List[Vector3] = [p0, p1, p1 + across, p0 + across]
                var first = len(positions) // 3
                # Four corners.
                for c in corners:  # pragma: no branch
                    positions.extend([c.x, c.y, c.z + PAINT_LIFT])
                    normals.extend([Float32(0), Float32(0), Float32(1)])
                    uvs.extend([c.x, c.y])
                # Face up in CARLA's left-handed frame, whatever the turn.
                var up = unit.x * across.y - unit.y * across.x
                if up > 0:
                    index.extend(
                        [
                            first,
                            first + 1,
                            first + 2,
                            first,
                            first + 2,
                            first + 3,
                        ]
                    )
                else:
                    index.extend(
                        [
                            first,
                            first + 2,
                            first + 1,
                            first,
                            first + 3,
                            first + 2,
                        ]
                    )
                t += STRIPE + STRIPE_GAP
        start = i + 1
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    geometry.set_attribute(NORMAL, BufferAttribute(normals^, 3))
    geometry.set_attribute(UV, BufferAttribute(uvs^, 2))
    var count = len(index)
    geometry.set_index(index^)
    geometry.add_group(0, count, CROSSWALK_SURFACE.material())
    return geometry^


def building_geometry(
    width: Length, depth: Length, height: Length
) raises -> BufferGeometry:
    """Return a building's walls, roof, shop fronts and trim, standing on
    the origin.

    x runs along the width, y up and z along the depth. The texture
    coordinates are in meters: along the wall and up it, so a facade tile
    repeats at world scale. The ground floor, `GROUND_FLOOR` tall, is a
    row of shops; a cornice runs round the building above it, and a
    parapet `PARAPET` tall rims the roof.

    Args:
        width: Along x. Positive.
        depth: Along z. Positive.
        height: Up. More than `GROUND_FLOOR`.

    Returns:
        The upper walls in group 0, the roof in group 1, the shop fronts
        in group 2 and the cornice and the parapet in group 3.

    Raises:
        Error: If a size is not positive, or the height is not more than
            the ground floor.
    """
    var w = width.to(METER) / 2
    var d = depth.to(METER) / 2
    var h = height.to(METER)
    var g = GROUND_FLOOR.to(METER)
    if not (w > 0 and d > 0 and h > g):
        raise Error(
            "A building needs a positive width and depth, and a height"
            " above its ground floor"
        )
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var index = List[Int]()
    # Each wall: a corner, the way along it, its length and its normal.
    var walls: List[Tuple[Vector3, Vector3, Float32, Vector3]] = [
        (Vector3(-w, 0, d), Vector3(1, 0, 0), 2 * w, Vector3(0, 0, 1)),
        (Vector3(w, 0, d), Vector3(0, 0, -1), 2 * d, Vector3(1, 0, 0)),
        (Vector3(w, 0, -d), Vector3(-1, 0, 0), 2 * w, Vector3(0, 0, -1)),
        (Vector3(-w, 0, -d), Vector3(0, 0, 1), 2 * d, Vector3(-1, 0, 0)),
    ]
    var counts = List[Int]()
    # The upper walls, then the shop fronts.
    # A constant count, more than zero.
    for storey in range(2):  # pragma: no branch
        var low = g if storey == 0 else Float32(0)
        var high = h if storey == 0 else g
        # Four walls.
        for wall in walls:  # pragma: no branch
            var a = wall[0] + Vector3(0, low, 0)
            var b = a + wall[1] * wall[2]
            var rise = high - low
            _quad(
                positions,
                normals,
                uvs,
                index,
                [a, b, b + Vector3(0, rise, 0), a + Vector3(0, rise, 0)],
                wall[3],
                [
                    Vector2(0, 0),
                    Vector2(wall[2], 0),
                    Vector2(wall[2], rise),
                    Vector2(0, rise),
                ],
            )
        counts.append(len(index))
        if storey == 0:
            _quad(
                positions,
                normals,
                uvs,
                index,
                [
                    Vector3(-w, h, d),
                    Vector3(w, h, d),
                    Vector3(w, h, -d),
                    Vector3(-w, h, -d),
                ],
                Vector3(0, 1, 0),
                [
                    Vector2(-w, d),
                    Vector2(w, d),
                    Vector2(w, -d),
                    Vector2(-w, -d),
                ],
            )
            counts.append(len(index))
    var ledge = Float32(0.2)
    cuboid(
        positions,
        normals,
        uvs,
        index,
        Vector3(-w - ledge, g - 0.15, -d - ledge),
        Vector3(w + ledge, g + 0.15, d + ledge),
    )
    var top = h + PARAPET.to(METER)
    var t = Float32(0.25)
    cuboid(
        positions,
        normals,
        uvs,
        index,
        Vector3(-w, h, d - t),
        Vector3(w, top, d),
    )
    cuboid(
        positions,
        normals,
        uvs,
        index,
        Vector3(-w, h, -d),
        Vector3(w, top, -d + t),
    )
    cuboid(
        positions,
        normals,
        uvs,
        index,
        Vector3(-w, h, -d + t),
        Vector3(-w + t, top, d - t),
    )
    cuboid(
        positions,
        normals,
        uvs,
        index,
        Vector3(w - t, h, -d + t),
        Vector3(w, top, d - t),
    )
    var geometry = BufferGeometry()
    geometry.set_attribute(POSITION, BufferAttribute(positions^, 3))
    geometry.set_attribute(NORMAL, BufferAttribute(normals^, 3))
    geometry.set_attribute(UV, BufferAttribute(uvs^, 2))
    var count = len(index)
    geometry.set_index(index^)
    # counts: after the upper walls, after the roof, after the shops.
    geometry.add_group(0, counts[0], MaterialIndex(0))
    geometry.add_group(counts[0], counts[1] - counts[0], MaterialIndex(1))
    geometry.add_group(counts[1], counts[2] - counts[1], MaterialIndex(2))
    geometry.add_group(counts[2], count - counts[2], MaterialIndex(3))
    return geometry^


def cuboid(
    mut positions: List[Float32],
    mut normals: List[Float32],
    mut uvs: List[Float32],
    mut index: List[Int],
    low: Vector3,
    high: Vector3,
):
    """Append the six faces of a box between two corners, facing out.

    Each face's texture coordinates are in meters across it.

    Args:
        positions: The positions, extended.
        normals: The normals, extended.
        uvs: The texture coordinates, extended.
        index: The index, extended.
        low: The corner of the least x, y and z.
        high: The corner of the greatest.
    """
    var x0 = low.x
    var y0 = low.y
    var z0 = low.z
    var x1 = high.x
    var y1 = high.y
    var z1 = high.z
    var dx = x1 - x0
    var dy = y1 - y0
    var dz = z1 - z0
    # Each face's four corners, counter-clockwise seen from outside.
    var corners: List[Vector3] = [
        Vector3(x0, y0, z1),
        Vector3(x1, y0, z1),
        Vector3(x1, y1, z1),
        Vector3(x0, y1, z1),
        Vector3(x1, y0, z0),
        Vector3(x0, y0, z0),
        Vector3(x0, y1, z0),
        Vector3(x1, y1, z0),
        Vector3(x1, y0, z1),
        Vector3(x1, y0, z0),
        Vector3(x1, y1, z0),
        Vector3(x1, y1, z1),
        Vector3(x0, y0, z0),
        Vector3(x0, y0, z1),
        Vector3(x0, y1, z1),
        Vector3(x0, y1, z0),
        Vector3(x0, y1, z1),
        Vector3(x1, y1, z1),
        Vector3(x1, y1, z0),
        Vector3(x0, y1, z0),
        Vector3(x0, y0, z0),
        Vector3(x1, y0, z0),
        Vector3(x1, y0, z1),
        Vector3(x0, y0, z1),
    ]
    var normal: List[Vector3] = [
        Vector3(0, 0, 1),
        Vector3(0, 0, -1),
        Vector3(1, 0, 0),
        Vector3(-1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, -1, 0),
    ]
    var sizes: List[Vector2] = [
        Vector2(dx, dy),
        Vector2(dx, dy),
        Vector2(dz, dy),
        Vector2(dz, dy),
        Vector2(dx, dz),
        Vector2(dx, dz),
    ]
    # Six faces.
    for f in range(6):  # pragma: no branch
        var size = sizes[f]
        _quad(
            positions,
            normals,
            uvs,
            index,
            [
                corners[f * 4],
                corners[f * 4 + 1],
                corners[f * 4 + 2],
                corners[f * 4 + 3],
            ],
            normal[f],
            [
                Vector2(0, 0),
                Vector2(size.x, 0),
                Vector2(size.x, size.y),
                Vector2(0, size.y),
            ],
        )


def _quad(
    mut positions: List[Float32],
    mut normals: List[Float32],
    mut uvs: List[Float32],
    mut index: List[Int],
    corners: List[Vector3],
    normal: Vector3,
    coordinates: List[Vector2],
):
    """Append one quad, wound counter-clockwise seen from its normal."""
    var first = len(positions) // 3
    # A constant count, more than zero.
    for k in range(4):  # pragma: no branch
        positions.extend([corners[k].x, corners[k].y, corners[k].z])
        normals.extend([normal.x, normal.y, normal.z])
        uvs.extend([coordinates[k].x, coordinates[k].y])
    index.extend([first, first + 1, first + 2, first, first + 2, first + 3])


def lumpy_crown(radius: Length, seed: Int) raises -> BufferGeometry:
    """Return a tree's crown: a sphere with its surface pushed in and out.

    Each corner moves along its direction by Perlin's improved noise at
    two scales, up to a quarter of the radius. The sphere keeps its
    shared corners, so the crown's normals stay smooth.

    Args:
        radius: The crown's radius before the push.
        seed: Which lumps.

    Returns:
        The crown, centered on the origin, indexed.

    Raises:
        Error: If the radius is not positive.
    """
    if not (radius.to(METER) > 0):
        raise Error("A crown needs a positive radius")
    var crown = sphere(radius, 20, 14)
    var noise = ImprovedNoise()
    var positions = List[Float32]()
    var r = radius.to(METER)
    var shift = Float64(seed) * 7.31
    ref position = crown.attribute_view(POSITION)
    # A sphere has corners.
    for i in range(position.count()):  # pragma: no branch
        var p = position.vector3(i)
        var x = Float64(p.x / r)
        var y = Float64(p.y / r)
        var z = Float64(p.z / r)
        var lump = (
            noise.noise(x * 1.7 + shift, y * 1.7, z * 1.7) * 0.7
            + noise.noise(x * 4.1, y * 4.1 + shift, z * 4.1) * 0.3
        )
        var push = 1 + Float32(lump) * Float32(0.45)
        positions.extend([p.x * push, p.y * push, p.z * push])
    crown.set_attribute(POSITION, BufferAttribute(positions^, 3))
    crown.compute_vertex_normals()
    return crown^


def _pose(location: Vector3, yaw: Angle) -> Matrix4:
    """Return the three.js matrix of a CARLA location and yaw."""
    return CarlaTransform(
        Length(location.x, METER),
        Length(location.y, METER),
        Length(location.z, METER),
        CarlaRotation(Angle(0, DEGREE), yaw, Angle(0, DEGREE)),
    ).three_matrix()


def _placed(
    var geometry: BufferGeometry, matrix: Matrix4
) raises -> BufferGeometry:
    """Return a geometry moved by a matrix."""
    geometry.apply_matrix4(matrix)
    return geometry.to_non_indexed()


def _translated(
    var geometry: BufferGeometry, x: Float32, y: Float32, z: Float32
) raises -> BufferGeometry:
    """Return a geometry moved by an offset, in meters."""
    geometry.translate(Length(x, METER), Length(y, METER), Length(z, METER))
    return geometry^


struct Town(Movable):
    """A map's roads and dressing, in a scene."""

    var materials: TownMaterials
    var settings: TownSettings
    # The asphalt's dry roughness map, and its color, roughness and normal
    # maps' ids.
    var asphalt_roughness: Texture
    var asphalt_roughness_id: TextureId
    # The road, the paint and the ground's nodes.
    var road_node: NodeId
    # Each lamp's spot light, as its index in `Scene.lights`.
    var lamp_lights: List[Int]
    var lots: List[Lot]
    var posts: List[LampPost]
    # The box round the roads, in CARLA's frame.
    var bounds: Box3
    # The wetness the materials were last set for.
    var wet: WetSurface
    # The semantic tag of each mesh the town added, in order.
    var tags: List[SemanticTag]
    # The CARLA town's package, when one stands in for the procedural
    # dressing.
    var package: Optional[TownPlacement]
    # The package's road, paint and ground materials, and each one's dry
    # color and roughness, which the weather wets.
    var wet_materials: List[MaterialId]
    var dry_colors: List[Color]
    var dry_roughness: List[Float32]

    def __init__(
        out self,
        map: Map,
        mut scene: Scene,
        mut assets: Assets,
        var settings: TownSettings,
        registry: AssetRegistry = AssetRegistry(),
    ) raises:
        """Build a map's town into a scene.

        A surface or a tree whose key the registry's cache holds wears the
        photoscanned asset; every other one is procedural. The keys are
        `assets.surface_key` of each road surface, `ground.grass`,
        `ground.paving` and `tree`. When the settings name a package and
        the cache holds `town.<package>`, the package stands in for the
        roads, the paint, the ground, the buildings, the trees and the
        lamps; see `AssetRegistry.place_town`.

        Args:
            map: The map.
            scene: The scene; the town's nodes, meshes and lamps are added.
            assets: The stores; the town's geometry, textures and
                materials are added.
            settings: How to build it.
            registry: The photoscanned assets; none by default.

        Raises:
            Error: If a mesh cannot be made, a map query fails, or a
                cached asset cannot be read.
        """
        self.settings = settings^
        self.materials = TownMaterials()
        self.lamp_lights = List[Int]()
        self.wet = WetSurface(0, 0)
        self.tags = List[SemanticTag]()
        self.package = None
        self.wet_materials = List[MaterialId]()
        self.dry_colors = List[Color]()
        self.dry_roughness = List[Float32]()
        self.lots = List[Lot]()
        self.posts = List[LampPost]()
        self.bounds = road_bounds(map)
        var size = self.settings.texture_size
        var asphalt = asphalt_maps(size, self.settings.seed)
        place(asphalt, ASPHALT_TILE)
        var concrete = concrete_maps(size, 2, self.settings.seed + 2)
        place(concrete, CONCRETE_TILE)
        self.asphalt_roughness = Texture(copy=asphalt.roughness)
        var asphalt_color = assets.textures.add(Texture(copy=asphalt.color))
        self.asphalt_roughness_id = assets.textures.add(
            Texture(copy=asphalt.roughness)
        )
        var asphalt_normal = assets.textures.add(Texture(copy=asphalt.normal))
        var concrete_color = assets.textures.add(Texture(copy=concrete.color))
        var concrete_rough = assets.textures.add(
            Texture(copy=concrete.roughness)
        )
        var concrete_normal = assets.textures.add(Texture(copy=concrete.normal))
        # A constant count, more than zero.
        for k in range(SURFACE_KINDS):  # pragma: no branch
            var kind = SurfaceKind(k)
            var color = surface_color(kind)
            var rough = surface_roughness(kind)
            var material = standard_material(
                color, roughness=rough, env_map=SCENE_ENVIRONMENT
            )
            var scanned = registry.cached_entry(surface_key(kind))
            if Bool(scanned):
                var set = registry.texture_set(scanned.value())
                material = set.dress(assets, material^, set.per_meter())
                if kind == ROAD_SURFACE and set.has_roughness:
                    # The puddles are drawn over the scanned roughness.
                    self.asphalt_roughness = Texture(copy=set.maps.roughness)
                    self.asphalt_roughness.repeat = set.per_meter()
                    self.asphalt_roughness_id = material.roughness_map
            elif kind == ROAD_SURFACE:
                material.map = asphalt_color
                material.roughness_map = self.asphalt_roughness_id
                material.normal_map = asphalt_normal
                material.normal_scale = Vector2(0.7, 0.7)
            elif kind.value <= WALL_SURFACE.value:
                material.map = concrete_color
                material.roughness_map = concrete_rough
                material.normal_map = concrete_normal
            self.materials.surfaces.append(assets.materials.add(material))

        self.road_node = scene.add(Object3D())
        if self.settings.package.byte_length() > 0:
            var packaged = registry.cached_entry(
                "town." + self.settings.package
            )
            if Bool(packaged):
                self._add_package(packaged.value(), scene, assets, registry)
                return
        # The road, from CARLA's mesh factory.
        # One mesh per surface kind, so that each has its own tag.
        var road = to_three_frame(generate_mesh(map, self.settings.resolution))
        # A map with lanes has a road surface.
        for group in road.groups:  # pragma: no branch
            var part = road.clone()
            var index = List[Int](capacity=group.count)
            # A group holds at least one triangle.
            for i in range(
                group.start, group.start + group.count
            ):  # pragma: no branch
                index.append(road.index[i])
            part.set_index(index^)
            part.groups = List[GeometryGroup]()
            var kind = SurfaceKind(group.material_index.value)
            self._add(
                scene,
                surface_tag(kind.value),
                Mesh(
                    assets.geometries.add(part^),
                    self.materials.surface(kind),
                    self.road_node,
                    receive_shadow=True,
                    cast_shadow=True,
                ),
            )
        var factory = MeshFactory()
        factory.road_param.resolution = self.settings.resolution
        var marks = List[LaneMarkMesh]()
        var words = List[String]()
        # The roads have a box, so there is a road.
        for r in map.roads:  # pragma: no branch
            if not r.is_junction:
                factory.generate_lane_mark_for_road(r, marks, words)
        var paint = Object3D()
        paint.set_position(0, PAINT_LIFT, 0)
        var paint_node = scene.add(paint^)
        for i in range(len(marks)):
            self._add(
                scene,
                ROAD_LINE,
                Mesh(
                    assets.geometries.add(to_three_frame(marks[i].geometry)),
                    self.materials.surfaces,
                    paint_node,
                    receive_shadow=True,
                ),
            )
        var stripes = crosswalk_stripes(map.all_crosswalk_zones())
        if len(stripes.index) > 0:
            self._add(
                scene,
                ROAD_LINE,
                Mesh(
                    assets.geometries.add(to_three_frame(stripes)),
                    self.materials.surfaces,
                    self.road_node,
                    receive_shadow=True,
                ),
            )
        var bounds = self.bounds
        self._add_ground(bounds, scene, assets, registry)
        if self.settings.buildings:
            self.lots = building_lots(map, self.settings)
            self._add_buildings(scene, assets)
        if self.settings.trees:
            self._add_trees(map, scene, assets, registry)
        if self.settings.lamps:
            self.posts = lamp_posts(map, self.settings.lamp_spacing)
            self._add_lamps(scene, assets)
        scene.update()

    def _add_package(
        mut self,
        index: Int,
        mut scene: Scene,
        mut assets: Assets,
        registry: AssetRegistry,
    ) raises:
        """Hang the town's package from the road's node, tag its meshes,
        and keep its road surfaces' dry looks for the weather.

        The package's traffic lights and signs are hidden: `Props` draws
        the map's, which change with the world. The procedural dressing
        is turned off, since the package holds its own.
        """
        var placed = registry.place_town(
            index, scene, assets, self.road_node, self.settings.near_distance
        )
        # A package has at least one mesh.
        for k in range(placed.mesh_count):  # pragma: no branch
            var m = placed.first_mesh + k
            var kind = placed.kinds[k]
            self.tags.append(town_kind_tag(kind))
            if kind == "traffic_light" or kind == "traffic_sign":
                var node = scene.meshes[m].node
                scene.node(node).visible = False
            if not town_kind_casts(kind):
                scene.meshes[m].cast_shadow = False
            if (
                kind == "road"
                or kind == "road_line"
                or kind == "sidewalk"
                or kind == "ground"
            ):
                var id = scene.meshes[m].material
                if id not in self.wet_materials:
                    var material = assets.materials.get(id)
                    self.wet_materials.append(id)
                    self.dry_colors.append(material.color)
                    self.dry_roughness.append(material.roughness)
        self.package = placed^
        self.settings.buildings = False
        self.settings.trees = False
        self.settings.lamps = False
        scene.update()

    def _add(
        mut self, mut scene: Scene, tag: SemanticTag, var mesh: Mesh
    ) raises:
        """Add a mesh to the scene and remember its tag."""
        scene.add_mesh(mesh^)
        self.tags.append(tag)

    def _add_ground(
        mut self,
        bounds: Box3,
        mut scene: Scene,
        mut assets: Assets,
        registry: AssetRegistry,
    ) raises:
        """Pave the town `PAVING_MARGIN` past its roads, and lay a lawn
        `LAWN_MARGIN` past them under everything."""
        var grass = grass_maps(
            self.settings.texture_size // 2, self.settings.seed + 4
        )
        var paving = concrete_maps(
            self.settings.texture_size // 2, 4, self.settings.seed + 5
        )
        var tiles: List[Tuple[Float32, Length, Length]] = [
            (Float32(-0.05), LAWN_MARGIN, GRASS_TILE),
            (Float32(-0.02), PAVING_MARGIN, PAVING_TILE),
        ]
        # The lawn and the paving.
        for k in range(2):  # pragma: no branch
            var margin = tiles[k][1].to(METER) * 2
            var across = bounds.max.x - bounds.min.x + margin
            var along = bounds.max.y - bounds.min.y + margin
            var tile = tiles[k][2].to(METER)
            var repeat = Vector2(across / tile, along / tile)
            var surface = standard_material(
                Color(255, 255, 255), roughness=1, env_map=SCENE_ENVIRONMENT
            )
            var scanned = registry.cached_entry(
                "ground.grass" if k == 0 else "ground.paving"
            )
            if Bool(scanned):
                var set = registry.texture_set(scanned.value())
                var per = set.per_meter()
                surface = set.dress(
                    assets, surface^, Vector2(across * per.x, along * per.y)
                )
                if k == 0:
                    self.materials.ground = assets.materials.add(surface)
                else:
                    self.materials.paving = assets.materials.add(surface)
            elif k == 0:
                grass.color.repeat = repeat
                grass.normal.repeat = repeat
                surface.roughness = 0.95
                surface.map = assets.textures.add(Texture(copy=grass.color))
                surface.normal_map = assets.textures.add(
                    Texture(copy=grass.normal)
                )
                self.materials.ground = assets.materials.add(surface)
            else:
                paving.color.repeat = repeat
                paving.roughness.repeat = repeat
                paving.normal.repeat = repeat
                surface.color = Color(236, 230, 220)
                surface.map = assets.textures.add(Texture(copy=paving.color))
                surface.roughness_map = assets.textures.add(
                    Texture(copy=paving.roughness)
                )
                surface.normal_map = assets.textures.add(
                    Texture(copy=paving.normal)
                )
                self.materials.paving = assets.materials.add(surface)
            var node = Object3D()
            node.rotate_x(Angle(-90, DEGREE))
            node.set_position(
                (bounds.min.x + bounds.max.x) / 2,
                bounds.min.z + tiles[k][0],
                (bounds.min.y + bounds.max.y) / 2,
            )
            self._add(
                scene,
                TERRAIN if k == 0 else SIDEWALK,
                Mesh(
                    assets.geometries.add(
                        plane(Length(across, METER), Length(along, METER))
                    ),
                    self.materials.paving if k == 1 else self.materials.ground,
                    scene.add(node^),
                    receive_shadow=True,
                ),
            )

    def _add_buildings(mut self, mut scene: Scene, mut assets: Assets) raises:
        """Add a box with a facade on each lot."""
        var styles: List[FacadeStyle] = [PLASTER, BRICK, PANELS, SHOPFRONT]
        # The list is a constant and not empty.
        for style in styles:  # pragma: no branch
            var maps = facade_maps(
                style, self.settings.texture_size, self.settings.seed + 9
            )
            place(maps, FACADE_TILE)
            var facade = standard_material(
                Color(255, 255, 255),
                roughness=1,
                env_map=SCENE_ENVIRONMENT,
                emissive=Color(255, 214, 160),
                emissive_intensity=0,
            )
            facade.map = assets.textures.add(Texture(copy=maps.color))
            facade.roughness_map = assets.textures.add(
                Texture(copy=maps.roughness)
            )
            facade.normal_map = assets.textures.add(Texture(copy=maps.normal))
            facade.emissive_map = assets.textures.add(
                Texture(copy=maps.emissive)
            )
            self.materials.facades.append(assets.materials.add(facade))
        self.materials.roof = assets.materials.add(
            standard_material(
                Color(70, 70, 72), roughness=0.9, env_map=SCENE_ENVIRONMENT
            )
        )
        self.materials.trim = assets.materials.add(
            standard_material(
                Color(196, 190, 178), roughness=0.8, env_map=SCENE_ENVIRONMENT
            )
        )
        var skyline = skyline_lots(
            self.bounds, SKYLINE_COUNT, self.settings.seed + 21
        )
        # The skyline has a constant count of buildings, more than zero.
        for index in range(len(self.lots) + len(skyline)):  # pragma: no branch
            var near = index < len(self.lots)
            var lot = self.lots[index] if near else skyline[
                index - len(self.lots)
            ]
            var node = Object3D()
            node.set_rotation_from_matrix(_pose(lot.center, lot.yaw))
            var at = lot.center
            node.set_position(at.x, at.z, at.y)
            self._add(
                scene,
                BUILDING,
                Mesh(
                    assets.geometries.add(
                        building_geometry(lot.width, lot.depth, lot.height)
                    ),
                    [
                        self.materials.facades[lot.style.value],
                        self.materials.roof,
                        self.materials.facades[SHOPFRONT.value],
                        self.materials.trim,
                    ],
                    scene.add(node^),
                    cast_shadow=near,
                    receive_shadow=near,
                ),
            )

    def _add_trees(
        mut self,
        map: Map,
        mut scene: Scene,
        mut assets: Assets,
        registry: AssetRegistry,
    ) raises:
        """Add a trunk and a crown where CARLA's `trees_transform` puts
        each tree, or the cached `tree` model, `TREE_HEIGHT` tall."""
        var bounds = road_bounds(map)
        # CARLA's region test reads y the other way round.
        var trees = trees_transform(
            map,
            Vector3(bounds.min.x - 10, bounds.max.y + 10, 0),
            Vector3(bounds.max.x + 10, bounds.min.y - 10, 0),
            self.settings.tree_spacing,
            Length(1.3, METER),
        )
        var scanned = registry.cached_entry("tree")
        if Bool(scanned):
            var first = Optional[ModelPlacement]()
            var k = 0
            for tree in trees:
                var node = Object3D()
                var at = tree.transform.location
                node.set_rotation_from_matrix(
                    _pose(
                        at,
                        Angle(hash2(k, 7, self.settings.seed) * 360, DEGREE),
                    )
                )
                node.set_position(at.x, at.z, at.y)
                var base = scene.add(node^)
                scene.update()
                var placed: ModelPlacement
                if Bool(first):
                    placed = repeat_model(first.value(), scene, base)
                else:
                    placed = registry.place_model(
                        scanned.value(),
                        scene,
                        assets,
                        base,
                        Vector3(TREE_HEIGHT, TREE_HEIGHT, TREE_HEIGHT),
                    )
                    first = placed.copy()
                for _ in range(placed.mesh_count):
                    self.tags.append(VEGETATION)
                k += 1
            return
        self.materials.trunk = assets.materials.add(
            standard_material(
                Color(92, 70, 52), roughness=0.95, env_map=SCENE_ENVIRONMENT
            )
        )
        var foliage = foliage_maps(
            self.settings.texture_size // 2, self.settings.seed + 6
        )
        # A crown's texture coordinates run once around and once down.
        foliage.color.repeat = Vector2(6, 4)
        foliage.normal.repeat = Vector2(6, 4)
        var leaves = standard_material(
            Color(255, 255, 255), roughness=0.8, env_map=SCENE_ENVIRONMENT
        )
        leaves.map = assets.textures.add(Texture(copy=foliage.color))
        leaves.normal_map = assets.textures.add(Texture(copy=foliage.normal))
        self.materials.leaves = assets.materials.add(leaves)
        var trunks = List[BufferGeometry]()
        var crowns = List[BufferGeometry]()
        var node = scene.add(Object3D())
        var n = 0
        for tree in trees:
            var at = tree.transform.location
            var size = Float32(0.8) + hash2(n, 5, self.settings.seed) * 0.5
            var pose = _pose(
                at, Angle(hash2(n, 7, self.settings.seed) * 360, DEGREE)
            )
            trunks.append(
                _placed(
                    _translated(
                        cylinder(
                            Length(0.1, METER),
                            Length(0.16, METER),
                            Length(4.6, METER),
                            8,
                        ),
                        0,
                        2.1,
                        0,
                    ),
                    pose,
                )
            )
            var crown = lumpy_crown(Length(1.5 * size, METER), n)
            crown.scale(1, 1.15, 1)
            crowns.append(
                _placed(_translated(crown^, 0, 4.6 + 1.3 * size, 0), pose)
            )
            # A constant count, more than zero.
            for k in range(3):  # pragma: no branch
                var turn = Float32(k) * 2.1 + hash2(n, k, 3) * 1.2
                var side = lumpy_crown(Length(0.95 * size, METER), n * 3 + k)
                crowns.append(
                    _placed(
                        _translated(
                            side^,
                            cos(turn) * 1.0 * size,
                            4.1 + 0.9 * size + hash2(n, k, 4) * 0.8,
                            sin(turn) * 1.0 * size,
                        ),
                        pose,
                    )
                )
            n += 1
            # A few neighbors to a mesh, so a camera culls the trees it
            # does not see: one mesh for every tree was in every view.
            if n % TREES_PER_MESH == 0 or n == len(trees):
                self._add_tree_meshes(scene, assets, node, trunks, crowns)
                trunks = List[BufferGeometry]()
                crowns = List[BufferGeometry]()

    def _add_tree_meshes(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        node: NodeId,
        trunks: List[BufferGeometry],
        crowns: List[BufferGeometry],
    ) raises:
        """Add a group of trees' trunks and crowns as two meshes."""
        self._add(
            scene,
            VEGETATION,
            Mesh(
                assets.geometries.add(merge_geometries(trunks)),
                self.materials.trunk,
                node,
                cast_shadow=True,
                receive_shadow=True,
            ),
        )
        self._add(
            scene,
            VEGETATION,
            Mesh(
                assets.geometries.add(merge_geometries(crowns)),
                self.materials.leaves,
                node,
                cast_shadow=True,
                receive_shadow=True,
            ),
        )

    def _add_lamps(mut self, mut scene: Scene, mut assets: Assets) raises:
        """Add a pole, an arm and a lamp at each post, with a spot light
        that `set_weather` lights at night."""
        self.materials.metal = assets.materials.add(
            standard_material(
                Color(60, 64, 66),
                roughness=0.45,
                metalness=0.8,
                env_map=SCENE_ENVIRONMENT,
            )
        )
        var glow = kelvin_color(Temperature(LAMP_KELVIN, KELVIN))
        var warm = Color(
            UInt8(Int(linear_to_srgb(glow.r) * 255)),
            UInt8(Int(linear_to_srgb(glow.g) * 255)),
            UInt8(Int(linear_to_srgb(glow.b) * 255)),
        )
        self.materials.lamp = assets.materials.add(
            standard_material(
                Color(200, 200, 190),
                roughness=0.3,
                emissive=warm,
                emissive_intensity=0,
                env_map=SCENE_ENVIRONMENT,
            )
        )
        var poles = List[BufferGeometry]()
        var heads = List[BufferGeometry]()
        for post in self.posts:
            var yaw = Angle(atan2(post.inward.y, post.inward.x), RADIAN)
            var pose = _pose(post.foot, yaw)
            poles.append(
                _placed(
                    _translated(
                        cylinder(
                            Length(0.07, METER),
                            Length(0.1, METER),
                            Length(7.2, METER),
                            10,
                        ),
                        0,
                        3.6,
                        0,
                    ),
                    pose,
                )
            )
            poles.append(
                _placed(
                    _translated(
                        box(
                            Length(1.9, METER),
                            Length(0.08, METER),
                            Length(0.08, METER),
                        ),
                        0.9,
                        7.1,
                        0,
                    ),
                    pose,
                )
            )
            heads.append(
                _placed(
                    _translated(
                        rounded_box(
                            Length(0.7, METER),
                            Length(0.14, METER),
                            Length(0.32, METER),
                            2,
                            Length(0.05, METER),
                        ),
                        1.9,
                        7.02,
                        0,
                    ),
                    pose,
                )
            )
            var bulb = Object3D()
            var at = post.foot + post.inward * 1.9
            bulb.set_position(at.x, at.z + 6.9, at.y)
            var target = Object3D()
            var down = post.foot + post.inward * 3.2
            target.set_position(down.x, down.z, down.y)
            var light = spot_light(
                warm,
                scene.add(bulb^),
                0,
                40,
                Angle(62, DEGREE),
                0.55,
                2,
                scene.add(target^),
            )
            self.lamp_lights.append(len(scene.lights))
            scene.add_light(light)
        if len(poles) == 0:
            return
        var node = scene.add(Object3D())
        self._add(
            scene,
            POLE,
            Mesh(
                assets.geometries.add(merge_geometries(poles)),
                self.materials.metal,
                node,
                cast_shadow=True,
                receive_shadow=True,
            ),
        )
        self._add(
            scene,
            POLE,
            Mesh(
                assets.geometries.add(merge_geometries(heads)),
                self.materials.lamp,
                node,
                cast_shadow=True,
            ),
        )

    def set_weather(
        mut self,
        mut scene: Scene,
        mut assets: Assets,
        weather: WeatherParameters,
    ) raises:
        """Wet the road, fill its puddles, and light the lamps and windows.

        Args:
            scene: The scene; the lamps' intensities change.
            assets: The stores; the surface materials change, and a new
                puddle map is added when the puddles change.
            weather: The weather.

        Raises:
            Error: If a material or a light the town added is gone.
        """
        var wet = wet_surface(weather)
        # A constant count, more than zero.
        for k in range(SURFACE_KINDS):  # pragma: no branch
            var kind = SurfaceKind(k)
            var id = self.materials.surface(kind)
            var material = assets.materials.get(id)
            material.color = wet_color(surface_color(kind), wet)
            material.roughness = wet.roughness(surface_roughness(kind))
            if kind != ROAD_SURFACE and kind.value <= WALL_SURFACE.value:
                # The concrete's map is about 0.82 rough.
                material.roughness = wet.roughness(Float32(0.82)) / Float32(
                    0.82
                )
            assets.materials.materials[id.value] = material
        if not (
            wet.wetness == self.wet.wetness and wet.puddles == self.wet.puddles
        ):
            var road = assets.materials.get(
                self.materials.surface(ROAD_SURFACE)
            )
            road.roughness = 1
            if wet.wetness > 0:
                var puddles = puddle_roughness(
                    self.asphalt_roughness,
                    wet.puddles,
                    wet.roughness(Float32(0.9)),
                    PUDDLE_ROUGHNESS,
                    self.settings.seed + 13,
                )
                puddles.repeat = self.asphalt_roughness.repeat
                road.roughness_map = assets.textures.add(puddles^)
            else:
                road.roughness_map = self.asphalt_roughness_id
            road.color = wet_color(Color(255, 255, 255), wet)
            assets.materials.materials[
                self.materials.surface(ROAD_SURFACE).value
            ] = road
            self.wet = wet
        for k in range(len(self.wet_materials)):
            var id = self.wet_materials[k]
            var material = assets.materials.get(id)
            material.color = wet_color(self.dry_colors[k], wet)
            material.roughness = wet.roughness(self.dry_roughness[k])
            assets.materials.materials[id.value] = material
        var lit = street_lights_on(weather)
        for index in self.lamp_lights:
            scene.lights[index].intensity = LAMP_INTENSITY if lit else 0
        if self.settings.lamps:
            var lamp = assets.materials.get(self.materials.lamp)
            lamp.emissive_intensity = LAMP_GLOW if lit else 0
            assets.materials.materials[self.materials.lamp.value] = lamp
        for id in self.materials.facades:
            var facade = assets.materials.get(id)
            facade.emissive_intensity = WINDOW_GLOW if lit else 0
            assets.materials.materials[id.value] = facade


def town_kind_casts(kind: String) -> Bool:
    """Return True for a town package's kind of mesh that casts the sun's
    shadow: a building, a wall, a plant or a parked vehicle.

    A flat surface only receives, since it would fill every texel of the
    sun's maps and shade nothing. A pole, a fence, a sign or a small prop
    casts a shadow a few texels wide that costs as much to draw as a
    building's.

    Args:
        kind: A node's `carla_kind`.

    Returns:
        Whether meshes of the kind cast.
    """
    return (
        kind == "building"
        or kind == "wall"
        or kind == "vegetation"
        or kind == "parked_vehicle"
    )


def town_kind_tag(kind: String) -> SemanticTag:
    """Return the semantic tag of a town package's kind of mesh.

    Args:
        kind: A node's `carla_kind`, as `build_towns.py` writes it.

    Returns:
        CARLA's tag for it; `STATIC` for a prop or a kind this does not
        know.
    """
    if kind == "building":
        return BUILDING
    if kind == "road":
        return ROAD
    if kind == "road_line":
        return ROAD_LINE
    if kind == "sidewalk":
        return SIDEWALK
    if kind == "ground":
        return GROUND
    if kind == "terrain":
        return TERRAIN
    if kind == "water":
        return WATER
    if kind == "rail":
        return RAIL_TRACK
    if kind == "wall":
        return WALL
    if kind == "fence":
        return FENCE
    if kind == "vegetation":
        return VEGETATION
    if kind == "pole":
        return POLE
    if kind == "traffic_light":
        return TRAFFIC_LIGHT
    if kind == "traffic_sign":
        return TRAFFIC_SIGN
    if kind == "parked_vehicle":
        return CAR
    return STATIC


def road_bounds(map: Map) raises -> Box3:
    """Return the box around the start, middle and end of every road's
    reference line.

    Args:
        map: The map.

    Returns:
        The box, in CARLA's frame.

    Raises:
        Error: If the map has no roads.
    """
    var bounds = Box3.empty()
    for road in map.roads:
        # Three points.
        for k in range(3):  # pragma: no branch
            var s = road.length * Float64(k) / 2
            bounds.expand_by_point(road.directed_point(s).to_carla().location)
    if bounds.is_empty():
        raise Error("The map has no roads")
    return bounds
