# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A procedural terracotta skyscraper, from three.js
`examples/jsm/generators/city/SkyscraperGenerator.js`.

The tower stands on a footprint: a rectangle with one corner cut at 45
degrees. Each edge of the footprint is a face with its own frame: `u`
along the edge, `v` up and `n` out. The tower is three tiers, a base, a
shaft and a crown, and each tier is cut into floors and bays. The crown
steps back from the shaft by a setback.

A few authored pieces, a window, a pier, a pinnacle, a unit box and a
unit quad, are placed many times by a matrix each. The ground floor is a
row of shopfronts, or on a few towers a pointed-arch arcade. Everything is
baked into one geometry without an index, and every vertex carries a
`partId` that names its zone, so one material can shade the whole tower.
The glass also carries the room behind it, for the interior mapping of
three.js's material.

The seed picks the tower's style: its footprint, its tier split, its
piers and its arches. A parameter the caller sets overrides its seeded
value. The rest of the tower follows from hashes of the floor and the face,
so the same parameters give the same tower as three.js.

The masonry sizes snap to the brick module, three tenths of a meter high
and six tenths long, so the procedural brickwork of three.js's material
lines up. The material itself is not ported.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from generators.utils import (
    PART_ID,
    PartId,
    Vec3d,
    basis_matrix,
    check_finite,
    generator_random,
    meters,
)
from geometries.box import box
from geometries.extrude import extrude
from geometries.lathe import lathe
from geometries.plane import plane
from geometries.shape import shape_geometry
from geometries.utils import merge_geometries
from math.matrix4 import Matrix4
from math.path import Path, Shape
from math.utils import SeededRandom
from math.vector2 import Vector2
from std.math import floor, pi, sin, sqrt
from units.si import Angle, Length, METER, RADIAN

# The zones of a skyscraper, three.js's `PartId`.
comptime WALL = PartId(0)
comptime PIER = PartId(1)
comptime FRAME = PartId(2)
comptime ORNAMENT = PartId(3)
comptime GLASS = PartId(4)
comptime AC = PartId(5)
comptime SHOPGLASS = PartId(6)
comptime STORE = PartId(7)
comptime AWNING = PartId(8)

# The fraction of a floor the glazed opening takes. The rest is the
# spandrel band.
comptime WINDOW_HEIGHT_RATIO = 0.62
# The width of the flat frame round the glazing, in meters.
comptime WINDOW_BORDER = 0.1
# The brick module, in meters.
comptime BRICK_HEIGHT = 0.3
comptime BRICK_LENGTH = 0.6

# The names of the interior-mapping attributes, as three.js names them.
comptime ROOM_CENTER = "roomCenter"
comptime ROOM_SIZE = "roomSize"

def building_palette() -> List[Int]:
    """Return the palette three.js picks a tower's masonry color from,
    `buildingPalette`: limestone and pale stone most often, then buff,
    brick, granite and a few accents.

    Returns:
        The colors, as hex sRGB.
    """
    return [
        0xA8553C,
        0x9C4A34,
        0x8A6A52,
        0x7D6450,
        0xC4A370,
        0xB89A6F,
        0xC2B183,
        0xC6C0B2,
        0xC6C0B2,
        0xBDB7A8,
        0xD1CCBE,
        0xB4AFA1,
        0x9A988F,
        0x8B8983,
        0xA5A39A,
        0xDBD6CB,
        0x7C868D,
    ]


@fieldwise_init
struct BaseStyle(Equatable, ImplicitlyCopyable, Writable):
    """What a tower's ground floor is, three.js's `baseStyle`, as a type
    rather than a string: a row of shopfronts or a grand arcade.
    `SkyscraperGenerator.layout` stops another value with `is_valid`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the two styles."""
        return self.value == 0 or self.value == 1


comptime ARCADE = BaseStyle(0)
comptime STOREFRONT = BaseStyle(1)


def pick_building_color(seed: Int) -> Int:
    """Return a tower's masonry color from its seed, three.js's
    `pickBuildingColor`.

    Args:
        seed: The tower's seed.

    Returns:
        The color, as hex sRGB, from `building_palette`.
    """
    var h = abs(sin(Float64(seed) * 12.9898) * 43758.5453)
    var palette = building_palette()
    return palette[Int(floor((h - floor(h)) * Float64(len(palette))))]


@fieldwise_init
struct Affine(ImplicitlyCopyable):
    """A placement in `Float64`: three columns and a translation, as
    three.js's `Matrix4` holds one in `Float64`."""

    var x_axis: Vec3d
    var y_axis: Vec3d
    var z_axis: Vec3d
    var position: Vec3d

    def point(self, p: Vec3d) -> Vec3d:
        """Return a point carried by the placement.

        Args:
            p: The point.

        Returns:
            The placed point.
        """
        return (
            self.x_axis * p.x + self.y_axis * p.y + self.z_axis * p.z
        ) + self.position

    def normal_turn(self) -> Affine:
        """Return the matrix that carries a normal, the inverse transpose
        of the linear part, three.js's `getNormalMatrix`. A placement that
        collapses a dimension gives zeros, as three.js's does.

        Returns:
            The normal matrix, with no translation.
        """
        var a = self.x_axis
        var b = self.y_axis
        var c = self.z_axis
        var bc = b.cross(c)
        var det = a.dot(bc)
        var inverse = 1.0 / det if det != 0 else 0.0
        var zero = Vec3d(0, 0, 0)
        return Affine(
            bc * inverse, c.cross(a) * inverse, a.cross(b) * inverse, zero
        )

    def matrix4(self) -> Matrix4:
        """Return the placement rounded to `Float32`.

        Returns:
            The matrix.
        """
        return basis_matrix(
            self.x_axis, self.y_axis, self.z_axis, self.position
        )


@fieldwise_init
struct WindowRoom(ImplicitlyCopyable):
    """The room a pane looks into, for interior mapping: its center on the
    glass and its width and height, in meters."""

    var center: Vec3d
    var width: Float64
    var height: Float64


@fieldwise_init
struct Bays(ImplicitlyCopyable):
    """How bays fit along a face: their count and width, and the margin
    left at each end."""

    var count: Int
    var margin: Float64
    var width: Float64


@fieldwise_init
struct FaceFrame(ImplicitlyCopyable):
    """One face of the tower, three.js's `FaceFrame`: an origin at one end
    of a footprint edge, `u` along the edge, `v` up, `n` out, and the
    edge's length in meters."""

    var origin: Vec3d
    var u: Vec3d
    var v: Vec3d
    var n: Vec3d
    var length: Float64

    def point(self, u: Float64, v: Float64, w: Float64) -> Vec3d:
        """Return a point of the face frame in the tower's space.

        Args:
            u: How far along the edge.
            v: How far up.
            w: How far out.

        Returns:
            The point.
        """
        return self.origin + self.u * u + self.v * v + self.n * w

    def matrix(self, u: Float64, v: Float64, w: Float64) -> Affine:
        """Return the placement of a piece authored with x across, y up
        and z out, at a point of the face.

        Args:
            u: How far along the edge.
            v: How far up.
            w: How far out.

        Returns:
            The placement.
        """
        return Affine(self.u, self.v, self.n, self.point(u, v, w))

    def box(
        self,
        u: Float64,
        v: Float64,
        w: Float64,
        size_u: Float64,
        size_v: Float64,
        size_n: Float64,
    ) -> Affine:
        """Return the placement of the unit box stretched to a size and
        centered at a point of the face, three.js's `boxMatrix`.

        Args:
            u: How far along the edge.
            v: How far up.
            w: How far out.
            size_u: The size along the edge.
            size_v: The size up.
            size_n: The size out.

        Returns:
            The placement.
        """
        return Affine(
            self.u * size_u,
            self.v * size_v,
            self.n * size_n,
            self.point(u, v, w),
        )

    def bays(self, bay_width: Float64) -> Bays:
        """Return how many bays of a width fit, with the rest split into
        the two end margins.

        Args:
            bay_width: The width of a bay.

        Returns:
            The bays. One at least.
        """
        var count = max(1, Int(floor(self.length / bay_width)))
        return Bays(
            count, (self.length - Float64(count) * bay_width) / 2, bay_width
        )


struct SkyscraperParameters(Copyable, Movable):
    """The parameters of a tower, three.js's `SkyscraperGenerator.defaults`
    and the seeded style.

    A field of `Optional` type is part of the style. Left empty, it takes
    the value the seed draws for it, three.js's `randomStyle`.
    """

    var seed: Int
    # The height asked for. The built height rounds to whole floors.
    var total_height: Length
    var floor_height: Length
    var bay_width: Length
    # A string course every this many floors of the shaft; zero for none.
    var string_course_every: Int
    # The cut corner: its size, and which corner, each sign one or minus
    # one. Zero picks no corner.
    var chamfer_width: Length
    var chamfer_corner_x: Int
    var chamfer_corner_z: Int
    # How far the crown steps back, in bays.
    var setback_depth: Float64
    # The share of shaft windows with an air conditioner.
    var ac_chance: Float64
    var footprint_width: Optional[Length]
    var footprint_depth: Optional[Length]
    # The shares of the floors that the base and the crown take.
    var base_fraction: Optional[Float64]
    var crown_fraction: Optional[Float64]
    var pier_width: Optional[Length]
    var pier_depth: Optional[Length]
    var window_reveal: Optional[Length]
    var string_course_height: Optional[Length]
    # An arch spans this many bays.
    var arch_bay_width_ratio: Optional[Float64]
    var arch_rise: Optional[Float64]
    var base_style: Optional[BaseStyle]

    def __init__(out self):
        """Create three.js's default tower, its style left to the seed."""
        self.seed = 35
        self.total_height = Length(140, METER)
        self.floor_height = Length(4, METER)
        self.bay_width = Length(2.6, METER)
        self.string_course_every = 6
        self.chamfer_width = Length(4, METER)
        self.chamfer_corner_x = 1
        self.chamfer_corner_z = 1
        self.setback_depth = 1.5
        self.ac_chance = 0.12
        self.footprint_width = None
        self.footprint_depth = None
        self.base_fraction = None
        self.crown_fraction = None
        self.pier_width = None
        self.pier_depth = None
        self.window_reveal = None
        self.string_course_height = None
        self.arch_bay_width_ratio = None
        self.arch_rise = None
        self.base_style = None


def _js_round(value: Float64) -> Float64:
    """Return JavaScript's `Math.round`: halves go up."""
    return floor(value + 0.5)


def _length_or(value: Optional[Length], seeded: Float64) -> Float64:
    """Return a length the caller set, in meters, or the seeded value."""
    return meters(value.value()) if value else seeded


def _number_or(value: Optional[Float64], seeded: Float64) -> Float64:
    """Return a number the caller set, or the seeded value."""
    return value.value() if value else seeded


struct SkyscraperStyle(Copyable, Movable):
    """A tower's parameters after the seed has filled the style and the
    masonry sizes have snapped to the brick module. Lengths are in
    meters."""

    var total_height: Float64
    var floor_height: Float64
    var window_height: Float64
    var bay_width: Float64
    var pier_width: Float64
    var pier_depth: Float64
    var window_reveal: Float64
    var string_course_height: Float64
    var string_course_every: Int
    var footprint_width: Float64
    var footprint_depth: Float64
    var base_fraction: Float64
    var crown_fraction: Float64
    var chamfer_width: Float64
    var chamfer_corner_x: Int
    var chamfer_corner_z: Int
    var setback_depth: Float64
    var ac_chance: Float64
    var arch_bay_width_ratio: Float64
    var arch_rise: Float64
    var base_style: BaseStyle

    def __init__(out self, p: SkyscraperParameters) raises:
        """Fill the style from the seed, three.js's `randomStyle`, let the
        caller's parameters override it, and snap to the brick module.

        Args:
            p: The parameters.

        Raises:
            Error: If the base style or a chamfer corner is not one there
                is, or a size is not positive and finite.
        """
        var random = generator_random(p.seed)
        var base = 0.10 + random.next() * 0.07
        var crown = 0.08 + random.next() * 0.08
        var width = 26 + random.next() * 18
        var depth = 20 + random.next() * 14
        var pier_width = 0.4 + random.next() * 0.4
        var pier_depth = 0.3 + random.next() * 0.3
        var reveal = 0.12 + random.next() * 0.1
        var course = 0.5 + random.next() * 0.5
        var arch_ratio = _js_round(1.5 + random.next() * 1.5)
        var arch_rise = 0.4 + random.next() * 0.5
        var style = ARCADE if random.next() < 0.22 else STOREFRONT
        self.base_style = p.base_style.value() if p.base_style else style
        if not self.base_style.is_valid():
            raise Error("A base style must be the arcade or the storefront")
        if abs(p.chamfer_corner_x) > 1 or abs(p.chamfer_corner_z) > 1:
            raise Error("A chamfer corner must be minus one, zero or one")
        self.footprint_width = _length_or(p.footprint_width, width)
        self.footprint_depth = _length_or(p.footprint_depth, depth)
        self.base_fraction = _number_or(p.base_fraction, base)
        self.crown_fraction = _number_or(p.crown_fraction, crown)
        self.pier_depth = _length_or(p.pier_depth, pier_depth)
        self.window_reveal = _length_or(p.window_reveal, reveal)
        self.string_course_height = _length_or(p.string_course_height, course)
        self.arch_bay_width_ratio = _number_or(p.arch_bay_width_ratio, arch_ratio)
        self.arch_rise = _number_or(p.arch_rise, arch_rise)
        self.string_course_every = p.string_course_every
        self.chamfer_width = meters(p.chamfer_width)
        self.chamfer_corner_x = p.chamfer_corner_x
        self.chamfer_corner_z = p.chamfer_corner_z
        self.setback_depth = p.setback_depth
        self.ac_chance = p.ac_chance
        var sizes = [
            meters(p.total_height),
            meters(p.floor_height),
            meters(p.bay_width),
            self.footprint_width,
            self.footprint_depth,
        ]
        for i in range(len(sizes)):  # pragma: no branch
            if not (sizes[i] > 0 and sizes[i] < 1e9):
                raise Error("A tower's sizes must be positive and finite")
        check_finite(
            self.base_fraction
            + self.crown_fraction
            + self.pier_depth
            + self.window_reveal
            + self.string_course_height
            + self.arch_bay_width_ratio
            + self.arch_rise
            + self.chamfer_width
            + self.setback_depth
            + self.ac_chance,
            "A tower's style",
        )
        # Snap to the brick module: a course pair a step up, a brick a
        # step along.
        var v_module = BRICK_HEIGHT * 2
        self.floor_height = max(
            v_module * 3, _js_round(meters(p.floor_height) / v_module) * v_module
        )
        self.window_height = (
            _js_round(self.floor_height * WINDOW_HEIGHT_RATIO / v_module)
            * v_module
        )
        self.bay_width = max(
            BRICK_LENGTH * 3,
            _js_round(meters(p.bay_width) / BRICK_LENGTH) * BRICK_LENGTH,
        )
        self.pier_width = max(
            BRICK_LENGTH,
            _js_round(_length_or(p.pier_width, pier_width) / BRICK_LENGTH)
            * BRICK_LENGTH,
        )
        self.total_height = meters(p.total_height)


def build_footprint(
    width: Float64,
    depth: Float64,
    chamfer: Float64,
    corner_x: Int,
    corner_z: Int,
) -> List[Vec3d]:
    """Return a rectangle centered on the origin with one corner cut at
    45 degrees, three.js's `buildFootprint`.

    Args:
        width: The size along x, in meters.
        depth: The size along z, in meters.
        chamfer: How far the cut runs along each edge, in meters. Zero
            cuts nothing.
        corner_x: Which corner is cut: the sign of its x.
        corner_z: The sign of its z.

    Returns:
        The corners in the ground plane, y zero, in three.js's order.
    """
    var hw = width / 2
    var hd = depth / 2
    var c = min(chamfer, min(hw, hd))
    var corners = [
        Vec3d(hw, 0, hd),
        Vec3d(-hw, 0, hd),
        Vec3d(-hw, 0, -hd),
        Vec3d(hw, 0, -hd),
    ]
    var sign_x = [1, -1, -1, 1]
    var sign_z = [1, 1, -1, -1]
    var points = List[Vec3d]()
    for i in range(4):  # pragma: no branch
        var corner = corners[i]
        if c > 0 and sign_x[i] == corner_x and sign_z[i] == corner_z:
            var before = corners[(i + 3) % 4]
            var after = corners[(i + 1) % 4]
            points.append(corner.lerp(before, c / corner.distance_to(before)))
            points.append(corner.lerp(after, c / corner.distance_to(after)))
        else:
            points.append(corner)
    return points^


def build_faces(points: List[Vec3d]) -> List[FaceFrame]:
    """Return a face frame per edge of a footprint, three.js's
    `buildFaces`.

    Args:
        points: The footprint, centered on the origin.

    Returns:
        The frames, `n` pointing away from the origin and `u` so that the
        basis is a pure turn.
    """
    var faces = List[FaceFrame]()
    var up = Vec3d(0, 1, 0)
    for i in range(len(points)):
        var a = points[i]
        var b = points[(i + 1) % len(points)]
        var edge = Vec3d(b.z - a.z, 0, -(b.x - a.x)).normalized()
        var mid = Vec3d((a.x + b.x) / 2, 0, (a.z + b.z) / 2)
        var n = edge if edge.dot(mid) >= 0 else edge * -1.0
        var u = up.cross(n).normalized()
        var origin = a if (b - a).dot(u) > 0 else b
        faces.append(FaceFrame(origin, u, up, n, a.distance_to(b)))
    return faces^


def _floor_hash(f: Int, frame: FaceFrame, k: Float64) -> Float64:
    """Return a stable hash of a floor and a face, three.js's
    `floorHash`."""
    var s = (
        sin(
            Float64(f) * 12.9898
            + frame.origin.x * 0.07
            + frame.origin.z * 0.131
            + k
        )
        * 43758.5453
    )
    return s - floor(s)


def _fraction(value: Float64) -> Float64:
    """Return the part of a number past its floor."""
    return value - floor(value)


struct SkyscraperParts(Movable):
    """Every placement of every piece of a tower, before the bake.

    Each list holds the placements of one piece, three.js's accumulators
    in `build`. Piers of equal height share one geometry, so they are
    kept by height: `pier_keys[i]` is a height in millimeters and
    `piers[i]` its placements, in the order the heights were first met.
    `extras` holds the geometry built once for this tower: the arcade and
    the two roof slabs, in the tower's space.
    """

    var style: SkyscraperStyle
    var floors: Int
    var base_floors: Int
    var crown_floors: Int
    var shaft_floors: Int
    var use_arcade: Bool
    var footprint: List[Vec3d]
    var crown_footprint: List[Vec3d]
    var windows: List[Affine]
    var glass: List[Affine]
    var glass_rooms: List[WindowRoom]
    var back_walls: List[Affine]
    var bands: List[Affine]
    var shop_glass: List[Affine]
    var shop_rooms: List[WindowRoom]
    var mullions: List[Affine]
    var store_bands: List[Affine]
    var awnings: List[Affine]
    var pier_keys: List[Int]
    var piers: List[List[Affine]]
    var trim: List[Affine]
    var ac_units: List[Affine]
    var finials: List[Affine]
    var extras: List[BufferGeometry]

    def __init__(out self, var style: SkyscraperStyle):
        """Create an empty set of parts for a style.

        Args:
            style: The resolved style.
        """
        self.style = style^
        self.floors = 0
        self.base_floors = 0
        self.crown_floors = 0
        self.shaft_floors = 0
        self.use_arcade = False
        self.footprint = List[Vec3d]()
        self.crown_footprint = List[Vec3d]()
        self.windows = List[Affine]()
        self.glass = List[Affine]()
        self.glass_rooms = List[WindowRoom]()
        self.back_walls = List[Affine]()
        self.bands = List[Affine]()
        self.shop_glass = List[Affine]()
        self.shop_rooms = List[WindowRoom]()
        self.mullions = List[Affine]()
        self.store_bands = List[Affine]()
        self.awnings = List[Affine]()
        self.pier_keys = List[Int]()
        self.piers = List[List[Affine]]()
        self.trim = List[Affine]()
        self.ac_units = List[Affine]()
        self.finials = List[Affine]()
        self.extras = List[BufferGeometry]()

    def pier_count(self) -> Int:
        """Return how many piers there are, of every height.

        Returns:
            The count.
        """
        var count = 0
        for i in range(len(self.piers)):
            count += len(self.piers[i])
        return count

    def add_pier(
        mut self, frame: FaceFrame, u: Float64, bottom: Float64, height: Float64
    ):
        """Place a pier, filed under its height.

        Args:
            frame: The face.
            u: How far along the face.
            bottom: Its base.
            height: Its height.
        """
        var key = Int(_js_round(height * 1000))
        var slot = -1
        for i in range(len(self.pier_keys)):
            slot = i if self.pier_keys[i] == key else slot
        if slot < 0:
            slot = len(self.pier_keys)
            self.pier_keys.append(key)
            self.piers.append(List[Affine]())
        self.piers[slot].append(frame.matrix(u, bottom, 0))


def _add_wall(
    mut target: List[Affine],
    frame: FaceFrame,
    bottom: Float64,
    top: Float64,
):
    """Place the thin wall that closes the volume behind a face, three.js's
    `addWall` with its thickness of 0.8 and its front at -0.6."""
    var h = top - bottom
    target.append(
        frame.box(
            frame.length / 2,
            bottom + h / 2,
            -0.6 - 0.4,
            frame.length + 1.6,
            h,
            0.8,
        )
    )


def _add_spandrel_bands(
    mut parts: SkyscraperParts,
    frame: FaceFrame,
    bottom: Float64,
    height: Float64,
):
    """Place the bands at every floor line of a tier, three.js's
    `addSpandrelBands`. The end bands are clipped to the tier."""
    ref s = parts.style
    var floors = max(1, Int(_js_round(height / s.floor_height)))
    var fh = height / Float64(floors)
    var band_height = s.floor_height - s.window_height
    var band_length = max(0.2, frame.length - 0.6)
    var v_top = bottom + height
    for f in range(floors + 1):  # pragma: no branch
        var center = bottom + Float64(f) * fh
        var top = min(center + band_height / 2, v_top)
        var low = max(center - band_height / 2, bottom)
        var h = top - low
        # three.js skips a band of no height. The snap keeps the window
        # below the floor, `0.62 f + 0.3 < f` for any floor of 1.8 meters
        # or more, so every band has a height.
        if h <= 0:  # pragma: no branch
            continue
        parts.bands.append(
            frame.box(
                frame.length / 2, (top + low) / 2, -0.3, band_length, h, 0.6
            )
        )


def _add_cornice(
    mut target: List[Affine],
    frame: FaceFrame,
    bottom: Float64,
    height: Float64,
    depth: Float64,
):
    """Place a two-step cornice band round a face, three.js's
    `addCornice`."""
    target.append(
        frame.box(
            frame.length / 2,
            bottom + height * 0.275,
            depth / 2,
            frame.length,
            height * 0.55,
            depth,
        )
    )
    target.append(
        frame.box(
            frame.length / 2,
            bottom + height * 0.775,
            depth * 0.85,
            frame.length,
            height * 0.45,
            depth * 1.7,
        )
    )


def _add_windows(
    mut parts: SkyscraperParts,
    frame: FaceFrame,
    bottom: Float64,
    height: Float64,
    with_ac: Bool,
):
    """Place a tier's windows, their glass and rooms, and the air
    conditioners on some shaft windows, three.js's `addWindows`."""
    ref s = parts.style
    var bays = frame.bays(s.bay_width)
    var floors = max(1, Int(_js_round(height / s.floor_height)))
    var fh = height / Float64(floors)
    var ac_w = min((s.bay_width - s.pier_width) * 0.55, 0.66)
    var ac_h = ac_w * 0.6
    var ac_d = ac_w * 0.5
    var ac_v = -s.window_height / 2 + ac_h / 2 + WINDOW_BORDER
    var ac_fits = ac_w >= (bays.width - s.pier_width) * 0.34
    var place_ac = with_ac and ac_fits
    var reveal = s.window_reveal
    var ac_chance = s.ac_chance
    for f in range(floors):  # pragma: no branch
        var cy = bottom + (Float64(f) + 0.5) * fh
        var room_bays = 3 if _floor_hash(f, frame, 0) > 0.5 else 2
        var room_phase = Int(floor(_floor_hash(f, frame, 1) * Float64(room_bays)))
        for b in range(bays.count):  # pragma: no branch
            var cx = bays.margin + (Float64(b) + 0.5) * bays.width
            parts.windows.append(frame.matrix(cx, cy, 0))
            parts.glass.append(frame.matrix(cx, cy, -reveal))
            var room = (b + room_phase) // room_bays
            var first = max(0, room * room_bays - room_phase)
            var last = min(bays.count, (room + 1) * room_bays - room_phase)
            var span = Float64(last - first)
            parts.glass_rooms.append(
                WindowRoom(
                    frame.point(
                        bays.margin + (Float64(first) + span / 2) * bays.width,
                        cy,
                        -reveal,
                    ),
                    span * bays.width,
                    fh - 1,
                )
            )
            var r = _fraction(
                sin(
                    Float64(f) * 41.3
                    + Float64(b) * 12.7
                    + frame.origin.x * 0.13
                    + frame.origin.z * 0.31
                )
                * 43758.5453
            )
            if place_ac and r < ac_chance:
                parts.ac_units.append(
                    frame.box(
                        cx,
                        cy + ac_v,
                        ac_d / 2 - reveal + 0.04,
                        ac_w,
                        ac_h,
                        ac_d,
                    )
                )


def _add_piers(
    mut parts: SkyscraperParts,
    frame: FaceFrame,
    bottom: Float64,
    height: Float64,
):
    """Place a pier on every bay edge but the far end, which the next face
    places, three.js's `addPiers`."""
    var bays = frame.bays(parts.style.bay_width)
    for i in range(bays.count):  # pragma: no branch
        parts.add_pier(
            frame, bays.margin + Float64(i) * bays.width, bottom, height
        )


def _add_storefront(
    mut parts: SkyscraperParts, frame: FaceFrame, height: Float64
):
    """Place the ground floor's shopfronts, three.js's `addStorefront`: a
    bulkhead and a signboard along the face, and per shop a pier, the
    display glass, two mullions and, on about half, an awning."""
    var bulkhead = 0.5
    var fascia = min(0.9, height * 0.22)
    var glass_height = height - fascia - bulkhead
    var length = frame.length
    parts.store_bands.append(
        frame.box(length / 2, bulkhead / 2, 0, length, bulkhead, 0.55)
    )
    parts.store_bands.append(
        frame.box(length / 2, height - fascia / 2, 0.08, length, fascia, 0.72)
    )
    _add_wall(parts.back_walls, frame, 0, height)
    var bays = frame.bays(max(4.0, parts.style.bay_width * 2))
    var cy = bulkhead + glass_height / 2
    for i in range(bays.count):  # pragma: no branch
        var x0 = bays.margin + Float64(i) * bays.width
        var cx = x0 + bays.width / 2
        parts.add_pier(frame, x0, 0, height)
        var gw = bays.width - parts.style.pier_width - 0.12
        parts.shop_glass.append(frame.box(cx, cy, -0.18, gw, glass_height, 1))
        parts.shop_rooms.append(
            WindowRoom(frame.point(cx, cy, -0.18), gw, glass_height)
        )
        parts.mullions.append(
            frame.box(x0 + bays.width / 3, cy, 0, 0.08, glass_height, 0.16)
        )
        parts.mullions.append(
            frame.box(x0 + bays.width * 2 / 3, cy, 0, 0.08, glass_height, 0.16)
        )
        var r = _fraction(
            sin(
                Float64(i) * 23.7
                + frame.origin.x * 0.21
                + frame.origin.z * 0.11
            )
            * 43758.5453
        )
        if r < 0.5:
            parts.awnings.append(
                frame.box(
                    cx, height - fascia - 0.12, 0.7, bays.width - 0.3, 0.14, 1.3
                )
            )


def _affine_geometry(
    var geometry: BufferGeometry, placement: Affine
) raises -> BufferGeometry:
    """Return a geometry moved by a placement."""
    geometry.apply_matrix4(placement.matrix4())
    return geometry^


def _arch_reveals(
    holes: List[Path], depth: Float64, curve_segments: Int
) raises -> BufferGeometry:
    """Return the inner walls of the arch openings, each hole's outline
    swept back by the wall's thickness, three.js's `buildArchReveals`."""
    var positions = List[Float32]()
    var normals = List[Float32]()
    var uvs = List[Float32]()
    var d = Float32(depth)
    for h in range(len(holes)):  # pragma: no branch
        var points = holes[h].sample(curve_segments)
        for i in range(len(points) - 1):  # pragma: no branch
            var a = points[i]
            var b = points[i + 1]
            var dx = Float64(b.x) - Float64(a.x)
            var dy = Float64(b.y) - Float64(a.y)
            var length = sqrt(dx * dx + dy * dy)
            var inverse = 1 / (length if length != 0 else 1.0)
            var corners: List[Float32] = [
                a.x, a.y, 0, a.x, a.y, -d, b.x, b.y, -d,
                a.x, a.y, 0, b.x, b.y, -d, b.x, b.y, 0,
            ]
            positions.extend(corners^)
            for _ in range(6):  # pragma: no branch
                normals.append(Float32(dy * inverse))
                normals.append(Float32(-dx * inverse))
                normals.append(0)
                uvs.append(0)
                uvs.append(0)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    return geometry^


def _add_arcade(
    mut parts: SkyscraperParts, frame: FaceFrame, height: Float64
) raises:
    """Build the base storey as a wall pierced by pointed arches, with a
    dark plane set behind the openings, three.js's `addArcade`."""
    ref s = parts.style
    var arch_width = s.bay_width * s.arch_bay_width_ratio
    var bays = frame.bays(arch_width)
    var sill = height * 0.04
    var spring = height * 0.55
    var apex = min(height * 0.96, spring + (arch_width / 2) * (0.8 + s.arch_rise))
    var length = Float32(frame.length)
    var outline = Path(Vector2(0, 0))
    outline.line_to(Vector2(length, 0))
    outline.line_to(Vector2(length, Float32(height)))
    outline.line_to(Vector2(0, Float32(height)))
    outline.line_to(Vector2(0, 0))
    var shape = Shape(outline^)
    for i in range(bays.count):  # pragma: no branch
        var cx = bays.margin + (Float64(i) + 0.5) * arch_width
        var hw = arch_width * 0.34
        var left = Float32(cx - hw)
        var right = Float32(cx + hw)
        var hole = Path(Vector2(left, Float32(sill)))
        hole.line_to(Vector2(left, Float32(spring)))
        hole.quadratic_to(
            Vector2(left, Float32(apex)), Vector2(Float32(cx), Float32(apex))
        )
        hole.quadratic_to(
            Vector2(right, Float32(apex)), Vector2(right, Float32(spring))
        )
        hole.line_to(Vector2(right, Float32(sill)))
        hole.line_to(Vector2(left, Float32(sill)))
        shape.add_hole(hole^)
    var thickness = 1.1
    var curve_segments = 8
    var front = shape_geometry(shape, curve_segments).to_non_indexed()
    var reveals = _arch_reveals(shape.holes, thickness, curve_segments)
    var wall = merge_geometries([front^, reveals^])
    parts.extras.append(_affine_geometry(wall^, frame.matrix(0, 0, 0)))
    var back = plane(
        Length(length, METER), Length(Float32(height), METER)
    ).to_non_indexed()
    parts.extras.append(
        _affine_geometry(
            back^,
            frame.matrix(frame.length / 2, height / 2, -thickness - 0.4),
        )
    )


def _slab(
    footprint: List[Vec3d], y: Float64, thickness: Float64
) raises -> BufferGeometry:
    """Return a thin cap following a footprint's outline, inset a little so
    its edge tucks behind the facade, three.js's `slab`."""
    var inset = 0.8
    var cx = 0.0
    var cz = 0.0
    var area = 0.0
    var count = len(footprint)
    for i in range(count):  # pragma: no branch
        var a = footprint[i]
        var b = footprint[(i + 1) % count]
        cx += a.x
        cz += a.z
        area += a.x * b.z - b.x * a.z
    cx /= Float64(count)
    cz /= Float64(count)
    var outline = Path()
    for k in range(count):  # pragma: no branch
        var p = footprint[count - 1 - k] if area < 0 else footprint[k]
        var dx = cx - p.x
        var dz = cz - p.z
        var d = sqrt(dx * dx + dz * dz)
        var scale = inset / (d if d != 0 else 1.0)
        var point = Vector2(Float32(p.x + dx * scale), Float32(p.z + dz * scale))
        if k == 0:
            outline.move_to(point)
        else:
            outline.line_to(point)
    var start = outline.first
    outline.line_to(start)
    var geometry = extrude(Shape(outline^), Length(Float32(thickness), METER))
    geometry.rotate_x(Angle(Float32(pi / 2), RADIAN))
    geometry.translate(
        Length(0, METER), Length(Float32(y - 0.2), METER), Length(0, METER)
    )
    return geometry^


def _box_part(
    width: Float64, height: Float64, depth: Float64, x: Float64, y: Float64, z: Float64
) raises -> BufferGeometry:
    """Return a box of a size moved to a point, without an index."""
    var geometry = box(
        Length(Float32(width), METER),
        Length(Float32(height), METER),
        Length(Float32(depth), METER),
    )
    geometry.translate(
        Length(Float32(x), METER),
        Length(Float32(y), METER),
        Length(Float32(z), METER),
    )
    return geometry.to_non_indexed()


def pier_geometry(style: SkyscraperStyle, height: Float64) raises -> BufferGeometry:
    """Return the pier module: a wide pier with a slimmer pilaster on its
    face, stopping short of the top, three.js's `buildPierGeometry`.

    Args:
        style: The tower's style, for the pier's width and depth.
        height: The pier's height, in meters.

    Returns:
        The pier, without an index, its base at y equals zero.

    Raises:
        Error: If a size is not positive.
    """
    var w = style.pier_width
    var d = style.pier_depth
    var pilaster = max(1.0, height - 0.6)
    return merge_geometries(
        [
            _box_part(w, height, d * 0.6, 0, height / 2, d * 0.3),
            _box_part(
                w * 0.55, pilaster, d * 0.45, 0, pilaster / 2, d * 0.6 + d * 0.225
            ),
        ]
    )


def _reveal_wall(
    x: Float64, y: Float64, rx: Float64, ry: Float64, width: Float64, height: Float64, depth: Float64
) raises -> BufferGeometry:
    """Return one reveal wall of a window opening, set back to the
    glazing."""
    var wall = plane(Length(Float32(width), METER), Length(Float32(height), METER))
    wall.rotate_x(Angle(Float32(rx), RADIAN))
    wall.rotate_y(Angle(Float32(ry), RADIAN))
    wall.translate(
        Length(Float32(x), METER),
        Length(Float32(y), METER),
        Length(Float32(-depth / 2), METER),
    )
    return wall.to_non_indexed()


def window_geometry(style: SkyscraperStyle) raises -> BufferGeometry:
    """Return the window module, three.js's `buildWindowGeometry`: the
    flat frame round the glazing hole, the four reveal walls back to the
    glass and one glazing bar.

    Args:
        style: The tower's style.

    Returns:
        The window, without an index, centered on its opening.

    Raises:
        Error: If the opening is too small for its frame.
    """
    var w = style.bay_width - style.pier_width
    var h = style.window_height
    var depth = style.window_reveal
    var iw = w / 2 - WINDOW_BORDER
    var ih = h / 2 - WINDOW_BORDER
    var ow = Float32(w / 2)
    var oh = Float32(h / 2)
    var outline = Path(Vector2(-ow, -oh))
    outline.line_to(Vector2(ow, -oh))
    outline.line_to(Vector2(ow, oh))
    outline.line_to(Vector2(-ow, oh))
    outline.line_to(Vector2(-ow, -oh))
    var shape = Shape(outline^)
    var x = Float32(iw)
    var y = Float32(ih)
    var hole = Path(Vector2(-x, -y))
    hole.line_to(Vector2(-x, y))
    hole.line_to(Vector2(x, y))
    hole.line_to(Vector2(x, -y))
    hole.line_to(Vector2(-x, -y))
    shape.add_hole(hole^)
    var transom = plane(
        Length(Float32(iw * 2), METER), Length(Float32(0.05), METER)
    )
    transom.translate(
        Length(0, METER),
        Length(Float32(h * 0.04), METER),
        Length(Float32(-depth + 0.02), METER),
    )
    return merge_geometries(
        [
            shape_geometry(shape).to_non_indexed(),
            _reveal_wall(-iw, 0, 0, pi / 2, depth, ih * 2, depth),
            _reveal_wall(iw, 0, 0, -pi / 2, depth, ih * 2, depth),
            _reveal_wall(0, -ih, -pi / 2, 0, iw * 2, depth, depth),
            _reveal_wall(0, ih, pi / 2, 0, iw * 2, depth, depth),
            transom.to_non_indexed(),
        ]
    )


def glass_geometry(style: SkyscraperStyle) raises -> BufferGeometry:
    """Return the pane that sits inside a window frame, three.js's
    `buildGlassGeometry`.

    Args:
        style: The tower's style.

    Returns:
        The pane, without an index.

    Raises:
        Error: If the opening is too small for its frame.
    """
    return plane(
        Length(Float32(style.bay_width - style.pier_width - WINDOW_BORDER * 2), METER),
        Length(Float32(style.window_height - WINDOW_BORDER * 2), METER),
    ).to_non_indexed()


def finial_geometry(style: SkyscraperStyle) raises -> BufferGeometry:
    """Return the pinnacle that caps the crown, a tapering profile turned
    round its axis, three.js's `buildFinialGeometry`.

    Args:
        style: The tower's style, for its size.

    Returns:
        The pinnacle, without an index.

    Raises:
        Error: If the pier width is not positive.
    """
    var s = Float32(style.pier_width)
    var profile: List[Vector2] = [
        Vector2(0, 0),
        Vector2(s * 0.9, 0),
        Vector2(s * 0.9, s * 0.4),
        Vector2(s * 0.55, s * 1.0),
        Vector2(0, s * 3.2),
    ]
    return lathe(profile, 8).to_non_indexed()


struct _Baked:
    """The attributes of the baked tower, as they grow."""

    var positions: List[Float32]
    var normals: List[Float32]
    var uvs: List[Float32]
    var part_ids: List[Float32]
    var room_centers: List[Float32]
    var room_sizes: List[Float32]

    def __init__(out self):
        self.positions = List[Float32]()
        self.normals = List[Float32]()
        self.uvs = List[Float32]()
        self.part_ids = List[Float32]()
        self.room_centers = List[Float32]()
        self.room_sizes = List[Float32]()

    def add(
        mut self,
        geometry: BufferGeometry,
        placements: List[Affine],
        id: PartId,
        rigid: Bool,
        rooms: List[WindowRoom],
    ) raises:
        """Bake a piece at every placement, three.js's `bakeGroups` for one
        group. A rigid placement turns normals by its own columns."""
        var p = geometry.attribute_view(String(POSITION)).packed()
        var n = geometry.attribute_view(String(NORMAL)).packed()
        var uv = geometry.attribute_view(String(UV)).packed()
        var count = len(p) // 3
        for i in range(len(placements)):
            ref placement = placements[i]
            var turn = placement if rigid else placement.normal_turn()
            var room = rooms[i] if len(rooms) > 0 else WindowRoom(
                Vec3d(0, 0, 0), 0, 0
            )
            for v in range(count):  # pragma: no branch
                var at = placement.point(
                    Vec3d(
                        Float64(p[v * 3]),
                        Float64(p[v * 3 + 1]),
                        Float64(p[v * 3 + 2]),
                    )
                )
                var normal = turn.point(
                    Vec3d(
                        Float64(n[v * 3]),
                        Float64(n[v * 3 + 1]),
                        Float64(n[v * 3 + 2]),
                    )
                ).normalized()
                self.positions.append(Float32(at.x))
                self.positions.append(Float32(at.y))
                self.positions.append(Float32(at.z))
                self.normals.append(Float32(normal.x))
                self.normals.append(Float32(normal.y))
                self.normals.append(Float32(normal.z))
                self.uvs.append(uv[v * 2])
                self.uvs.append(uv[v * 2 + 1])
                self.part_ids.append(Float32(id.value))
                self.room_centers.append(Float32(room.center.x))
                self.room_centers.append(Float32(room.center.y))
                self.room_centers.append(Float32(room.center.z))
                self.room_sizes.append(Float32(room.width))
                self.room_sizes.append(Float32(room.height))

    def geometry(self) raises -> BufferGeometry:
        """Return the baked attributes as one geometry."""
        var geometry = BufferGeometry()
        geometry.set_attribute(
            String(POSITION), BufferAttribute(self.positions.copy(), 3)
        )
        geometry.set_attribute(String(NORMAL), BufferAttribute(self.normals.copy(), 3))
        geometry.set_attribute(String(UV), BufferAttribute(self.uvs.copy(), 2))
        geometry.set_attribute(
            String(PART_ID), BufferAttribute(self.part_ids.copy(), 1)
        )
        geometry.set_attribute(
            String(ROOM_CENTER), BufferAttribute(self.room_centers.copy(), 3)
        )
        geometry.set_attribute(
            String(ROOM_SIZE), BufferAttribute(self.room_sizes.copy(), 2)
        )
        return geometry^


struct SkyscraperGenerator(Movable):
    """Generates a tripartite terracotta tower, three.js's
    `SkyscraperGenerator`.

    three.js returns a mesh named `Skyscraper`. The material is not
    ported, so `build` returns the baked geometry, and `layout` returns
    the placements before the bake.
    """

    var parameters: SkyscraperParameters

    def __init__(out self):
        """Create a generator with three.js's default tower."""
        self.parameters = SkyscraperParameters()

    def __init__(out self, var parameters: SkyscraperParameters):
        """Create a generator with given parameters.

        Args:
            parameters: The tower.
        """
        self.parameters = parameters^

    def layout(self) raises -> SkyscraperParts:
        """Lay the tower out: its tiers, faces, floors and bays, and every
        placement of every piece.

        Returns:
            The parts.

        Raises:
            Error: If the parameters are refused; see `SkyscraperStyle`.
        """
        var parts = SkyscraperParts(SkyscraperStyle(self.parameters))
        ref s = parts.style
        var floors = max(3, Int(_js_round(s.total_height / s.floor_height)))
        var base_floors = max(1, Int(_js_round(Float64(floors) * s.base_fraction)))
        var crown_floors = max(
            1, Int(_js_round(Float64(floors) * s.crown_fraction))
        )
        var shaft_floors = max(1, floors - base_floors - crown_floors)
        var base_height = Float64(base_floors) * s.floor_height
        var crown_height = Float64(crown_floors) * s.floor_height
        var shaft_height = Float64(shaft_floors) * s.floor_height
        s.total_height = base_height + shaft_height + crown_height
        parts.floors = floors
        parts.base_floors = base_floors
        parts.crown_floors = crown_floors
        parts.shaft_floors = shaft_floors
        var base_top = base_height
        var shaft_top = base_height + shaft_height
        parts.footprint = build_footprint(
            s.footprint_width,
            s.footprint_depth,
            s.chamfer_width,
            s.chamfer_corner_x,
            s.chamfer_corner_z,
        )
        var faces = build_faces(parts.footprint)
        var inset = s.setback_depth * s.bay_width
        parts.crown_footprint = build_footprint(
            max(s.bay_width * 2, s.footprint_width - inset * 2),
            max(s.bay_width * 2, s.footprint_depth - inset * 2),
            max(0.0, s.chamfer_width - inset),
            s.chamfer_corner_x,
            s.chamfer_corner_z,
        )
        var crown_faces = build_faces(parts.crown_footprint)
        var course = s.string_course_height
        var crown_cornice = course * 1.6
        var ground = s.floor_height
        parts.use_arcade = (
            s.base_style == ARCADE and base_height > ground * 1.5
        )
        var total = s.total_height
        var every = s.string_course_every
        var parapet_depth = s.pier_depth
        var bay_width = s.bay_width
        _add_tier(parts, faces, base_top, shaft_height, shaft_height, True)
        _add_tier(
            parts,
            crown_faces,
            shaft_top,
            crown_height,
            crown_height - crown_cornice,
            False,
        )
        if not parts.use_arcade and base_height > ground + 0.1:
            _add_tier(
                parts,
                faces,
                ground,
                base_height - ground,
                base_height - ground,
                False,
            )
        for i in range(len(faces)):  # pragma: no branch
            if parts.use_arcade:
                _add_arcade(parts, faces[i], base_height)
            else:
                _add_storefront(parts, faces[i], ground)
            _add_cornice(parts.trim, faces[i], base_top - course, course, 0.5)
        var f = every
        while every > 0 and f < shaft_floors:
            for i in range(len(faces)):  # pragma: no branch
                _add_cornice(
                    parts.trim,
                    faces[i],
                    base_top + Float64(f) * ground - course * 0.5,
                    course,
                    0.3,
                )
            f += every
        for i in range(len(crown_faces)):  # pragma: no branch
            ref frame = crown_faces[i]
            _add_cornice(
                parts.trim, frame, total - crown_cornice, crown_cornice, 0.9
            )
            parts.trim.append(
                frame.box(
                    frame.length / 2,
                    total + 0.7,
                    parapet_depth * 0.4,
                    frame.length,
                    1.4,
                    parapet_depth * 0.8,
                )
            )
            var bays = frame.bays(bay_width)
            for b in range(bays.count):  # pragma: no branch
                var top = frame.point(
                    bays.margin + Float64(b) * bays.width,
                    total,
                    parapet_depth * 0.5,
                )
                parts.finials.append(
                    Affine(Vec3d(1, 0, 0), Vec3d(0, 1, 0), Vec3d(0, 0, 1), top)
                )
        parts.extras.append(_slab(parts.footprint, shaft_top, 0.6))
        parts.extras.append(_slab(parts.crown_footprint, total, 0.6))
        return parts^

    def build(self) raises -> BufferGeometry:
        """Lay the tower out and bake it into one geometry, three.js's
        `build`.

        The pieces are baked in three.js's draw order: the facade front to
        back, and the walls behind it last.

        Returns:
            A geometry without an index, with `position`, `normal`, `uv`,
            `partId`, `roomCenter` and `roomSize` attributes.

        Raises:
            Error: If the parameters are refused; see `SkyscraperStyle`.
        """
        var parts = self.layout()
        return bake(parts)


def bake(parts: SkyscraperParts) raises -> BufferGeometry:
    """Bake a tower's placements into one geometry, three.js's
    `bakeGroups` over its groups in draw order.

    Args:
        parts: The laid-out tower.

    Returns:
        The geometry; see `SkyscraperGenerator.build`.

    Raises:
        Error: If a module cannot be built from the style.
    """
    ref s = parts.style
    var unit_box = box(
        Length(1, METER), Length(1, METER), Length(1, METER)
    ).to_non_indexed()
    var unit_plane = plane(Length(1, METER), Length(1, METER)).to_non_indexed()
    var none = List[WindowRoom]()
    var baked = _Baked()
    baked.add(window_geometry(s), parts.windows, FRAME, True, none)
    baked.add(glass_geometry(s), parts.glass, GLASS, True, parts.glass_rooms)
    baked.add(unit_plane, parts.shop_glass, SHOPGLASS, False, parts.shop_rooms)
    baked.add(unit_box, parts.mullions, FRAME, False, none)
    baked.add(unit_box, parts.store_bands, STORE, False, none)
    baked.add(unit_box, parts.awnings, AWNING, False, none)
    baked.add(unit_box, parts.bands, WALL, False, none)
    for i in range(len(parts.pier_keys)):  # pragma: no branch
        baked.add(
            pier_geometry(s, Float64(parts.pier_keys[i]) / 1000),
            parts.piers[i],
            PIER,
            True,
            none,
        )
    baked.add(unit_box, parts.trim, WALL, False, none)
    baked.add(unit_box, parts.ac_units, AC, False, none)
    baked.add(finial_geometry(s), parts.finials, ORNAMENT, True, none)
    var identity: List[Affine] = [
        Affine(Vec3d(1, 0, 0), Vec3d(0, 1, 0), Vec3d(0, 0, 1), Vec3d(0, 0, 0))
    ]
    for i in range(len(parts.extras)):  # pragma: no branch
        baked.add(parts.extras[i], identity, WALL, True, none)
    baked.add(unit_box, parts.back_walls, WALL, False, none)
    return baked.geometry()


def _add_tier(
    mut parts: SkyscraperParts,
    faces: List[FaceFrame],
    bottom: Float64,
    height: Float64,
    pier_height: Float64,
    with_ac: Bool,
):
    """Place one tier's facade on every face: windows, the wall behind
    them, the spandrel bands and the piers."""
    for i in range(len(faces)):  # pragma: no branch
        _add_windows(parts, faces[i], bottom, height, with_ac)
        _add_wall(parts.back_walls, faces[i], bottom, bottom + height)
        _add_spandrel_bands(parts, faces[i], bottom, height)
        _add_piers(parts, faces[i], bottom, pier_height)
