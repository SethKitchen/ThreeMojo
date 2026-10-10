# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A low-poly fleet of cars, from three.js
`examples/jsm/generators/city/CarGenerator.js`.

A car's body is lofted through cross sections along its length. Each
section is interpolated from a short profile table, and extra sections
round each axle cut a circular wheel arch into the sill. Flat panels make
the windscreens and the side windows, lofts make the roof, lathes make the
tyres and the rims, and circles the hubs and the wheel wells.

There are two bodies, a sedan and an SUV, and a third for the taxi paint:
the sedan with a roof sign. A car in the taxi's yellow always takes the
taxi; the others split between the sedan and the SUV by a hash of their
place in the list, so a row of parked cars reads as different vehicles.
Each body is one geometry, placed once for each of its cars, with each
car's paint as per-instance data.

Every car stands on its wheels at y equals zero, centered in x and z, and
faces +z. The material is not ported.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from generators.street_furniture import unit_vectors_turn
from generators.utils import (
    Instances,
    PART_ID,
    PartId,
    Vec3d,
    angle_radians as _a,
    length_meters as _l,
    part,
)
from geometries.box import box
from geometries.circle import circle
from geometries.lathe import lathe
from geometries.loft import loft
from geometries.utils import merge_geometries
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.color_spaces import srgb_to_linear_three
from std.math import cos, pi, sqrt

# A car's parts.
comptime CAR_BODY = PartId(0)
comptime CAR_WINDOW = PartId(1)
comptime CAR_TYRE = PartId(2)
comptime CAR_ALLOY = PartId(3)
comptime CAR_TRIM = PartId(4)
comptime CAR_MIRROR = PartId(5)
comptime CAR_SIGN = PartId(6)
comptime CAR_FRONT = PartId(7)
comptime CAR_REAR = PartId(8)

# The paint that takes the taxi body, three.js's `CarGenerator.taxiColor`.
comptime TAXI_COLOR = 0xF5C518


@fieldwise_init
struct BodyType(Equatable, ImplicitlyCopyable, Writable):
    """Which body a car has, three.js's body keys, as a type rather than a
    string. `car_spec` stops another value with `is_valid`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three bodies.

        Returns:
            Whether the body is the sedan, the SUV or the taxi.
        """
        return self.value >= 0 and self.value < 3


comptime SEDAN = BodyType(0)
comptime SUV = BodyType(1)
comptime TAXI = BodyType(2)


struct CarSpec(Copyable, Movable):
    """The shape of one body, three.js's `BODY_SPECS` entry, in meters.

    `body` holds the profile table, four numbers a row from the front:
    the z of the section, its half width, the height of its shoulder and
    the height of its deck. The corners of the cabin are x, y and z, the
    x a half width. `pillars` are the z of the pillars between the side
    windows, and `lamps` the heights of the front and rear lamps.
    """

    var body: List[Float64]
    var front_base: Vec3d
    var front_roof: Vec3d
    var rear_base: Vec3d
    var rear_roof: Vec3d
    var wheel_radius: Float64
    var wheel_z: Float64
    var wheel_x: Float64
    var pillars: List[Float64]
    var lamps: List[Float64]
    var sign: Bool
    var rails: Bool

    def __init__(out self, body: BodyType) raises:
        """Create the spec of a body.

        Args:
            body: Which body.

        Raises:
            Error: If the body is not one there is.
        """
        if not body.is_valid():
            raise Error("A car body must be the sedan, the SUV or the taxi")
        if body == SUV:
            self.body = [
                2.30,
                0.84,
                0.84,
                0.99,
                2.15,
                0.94,
                0.94,
                1.10,
                1.40,
                0.98,
                1.02,
                1.17,
                0.76,
                0.96,
                1.04,
                1.19,
                -0.45,
                0.96,
                1.05,
                1.20,
                -1.40,
                0.98,
                1.03,
                1.21,
                -2.16,
                0.94,
                0.94,
                1.16,
                -2.30,
                0.84,
                0.86,
                1.03,
            ]
            self.front_base = Vec3d(0.86, 1.15, 0.78)
            self.front_roof = Vec3d(0.76, 1.73, 0.18)
            self.rear_base = Vec3d(0.87, 1.15, -2.12)
            self.rear_roof = Vec3d(0.77, 1.75, -1.66)
            self.wheel_radius = 0.39
            self.wheel_z = 1.40
            self.wheel_x = 0.87
            self.pillars = [-0.30, -1.16]
            self.lamps = [0.91, 0.94]
            self.rails = True
        else:
            self.body = [
                2.25,
                0.79,
                0.67,
                0.79,
                2.11,
                0.89,
                0.78,
                0.91,
                1.38,
                0.94,
                0.87,
                1.00,
                0.75,
                0.92,
                0.89,
                1.025,
                -0.45,
                0.92,
                0.91,
                1.04,
                -1.38,
                0.94,
                0.88,
                1.06,
                -2.10,
                0.89,
                0.77,
                0.97,
                -2.25,
                0.81,
                0.70,
                0.85,
            ]
            self.front_base = Vec3d(0.82, 0.99, 0.78)
            self.front_roof = Vec3d(0.69, 1.45, 0.12)
            self.rear_base = Vec3d(0.83, 1.02, -1.15)
            self.rear_roof = Vec3d(0.71, 1.47, -0.72)
            self.wheel_radius = 0.35
            self.wheel_z = 1.38
            self.wheel_x = 0.83
            self.pillars = [-0.30]
            self.lamps = [0.71, 0.76]
            self.rails = False
        self.sign = body == TAXI

    def rows(self) -> Int:
        """Return how many rows the profile table has.

        Returns:
            The count.
        """
        return len(self.body) // 4

    def at(self, row: Int, column: Int) -> Float64:
        """Return one number of the profile table.

        Args:
            row: Which row, from the front.
            column: Which number: z, half width, shoulder or deck.

        Returns:
            The number.
        """
        return self.body[row * 4 + column]


def _v(x: Float64, y: Float64, z: Float64) -> Vector3:
    """Return a point rounded to `Float32`."""
    return Vector3(Float32(x), Float32(y), Float32(z))


def body_stations(spec: CarSpec) -> List[Float64]:
    """Return the z of every section of the body, from the front: the
    profile's own, and seven round each axle that shape the arch.

    Args:
        spec: The body.

    Returns:
        The stations, each once, in descending order.
    """
    var radius = spec.wheel_radius + 0.055
    var stations = List[Float64]()
    for row in range(spec.rows()):  # pragma: no branch
        _add_station(stations, spec.at(row, 0))
    for axle in [-spec.wheel_z, spec.wheel_z]:  # pragma: no branch
        for i in range(7):  # pragma: no branch
            _add_station(stations, axle + radius * cos(Float64(i) / 6 * pi))
    sort(stations)
    stations.reverse()
    return stations^


def _add_station(mut stations: List[Float64], z: Float64):
    """Add a station unless it is there already, as a `Set` keeps it."""
    var seen = 0
    for i in range(len(stations)):
        seen += 1 if stations[i] == z else 0
    if seen == 0:
        stations.append(z)


def body_section(spec: CarSpec, z: Float64) -> List[Vector3]:
    """Return one cross section of the body, interpolated from the profile
    table, with the sill lifted round a wheel.

    Args:
        spec: The body.
        z: Where along the car.

    Returns:
        The ten points of the section, the right half and its mirror.
    """
    var radius = spec.wheel_radius + 0.055
    var index = 0
    while index < spec.rows() - 2 and z < spec.at(index + 1, 0):
        index += 1
    var t = (z - spec.at(index, 0)) / (
        spec.at(index + 1, 0) - spec.at(index, 0)
    )
    var w = spec.at(index, 1) + (spec.at(index + 1, 1) - spec.at(index, 1)) * t
    var shoulder = (
        spec.at(index, 2) + (spec.at(index + 1, 2) - spec.at(index, 2)) * t
    )
    var deck = (
        spec.at(index, 3) + (spec.at(index + 1, 3) - spec.at(index, 3)) * t
    )
    var distance = abs(abs(z) - spec.wheel_z)
    var sill = (
        spec.wheel_radius
        + sqrt(max(0.0, radius * radius - distance * distance)) if distance
        <= radius else 0.28
    )
    var right: List[Vec3d] = [
        Vec3d(w * 0.82, sill, z),
        Vec3d(w * 0.97, sill + (shoulder - sill) * 0.12, z),
        Vec3d(w, shoulder, z),
        Vec3d(w * 0.91, deck - 0.025, z),
        Vec3d(w * 0.52, deck, z),
    ]
    # three.js's `[ ...right, ...mirrored reversed right ].reverse()`.
    var section = List[Vector3]()
    for i in range(5):  # pragma: no branch
        var p = right[i]
        section.append(_v(-p.x, p.y, p.z))
    for i in range(5):  # pragma: no branch
        var p = right[4 - i]
        section.append(_v(p.x, p.y, p.z))
    return section^


def build_body(spec: CarSpec) raises -> BufferGeometry:
    """Return the lofted body, three.js's `buildBody`: capped at both
    ends, the front cap tagged as the front and the rear as the rear.

    Args:
        spec: The body.

    Returns:
        The body, indexed, with a `partId`.

    Raises:
        Error: If the body cannot be lofted.
    """
    var stations = body_stations(spec)
    var sections = List[List[Vector3]]()
    for i in range(len(stations)):  # pragma: no branch
        sections.append(body_section(spec, stations[i]))
    var geometry = part(loft(sections, True, True, True), CAR_BODY)
    var ids = geometry.clone_attribute(String(PART_ID))
    ref normals = geometry.attribute_view(String(NORMAL))
    for i in range(normals.count()):  # pragma: no branch
        var nz = normals.component(i, 2)
        var id = CAR_FRONT if nz > 0.9999 else (
            CAR_REAR if nz < -0.9999 else CAR_BODY
        )
        ids.set_component(i, 0, Float32(id.value))
    geometry.set_attribute(String(PART_ID), ids^)
    return geometry^


def panel(
    corners: List[Vec3d], id: PartId, curved: Bool
) raises -> BufferGeometry:
    """Return a window panel on four corners, three.js's `panel`. A curved
    panel is cut four by two and bowed, as a windscreen is.

    Args:
        corners: The four corners, in order round the panel.
        id: The panel's part.
        curved: Whether it bows.

    Returns:
        The panel, indexed, its texture coordinates spanning it.

    Raises:
        Error: If the part code is not one there is.
    """
    var columns = 4 if curved else 1
    var rows = 2 if curved else 1
    var normal = (
        (corners[1] - corners[0]).cross(corners[3] - corners[0]).normalized()
    )
    var positions = List[Float32]()
    var uvs = List[Float32]()
    var index = List[Int]()
    for y in range(rows + 1):  # pragma: no branch
        var v = Float64(y) / Float64(rows)
        for x in range(columns + 1):  # pragma: no branch
            var u = Float64(x) / Float64(columns)
            var p = (
                corners[0]
                .lerp(corners[1], u)
                .lerp(corners[3].lerp(corners[2], u), v)
            )
            var arch = 4 * u * (1 - u)
            var lift = arch * v * 0.035 if curved else 0.0
            var bow = arch * 4 * v * (1 - v) * 0.025 if curved else 0.0
            p = Vec3d(p.x, p.y + lift, p.z) + normal * bow
            positions.append(Float32(p.x))
            positions.append(Float32(p.y))
            positions.append(Float32(p.z))
            uvs.append(Float32(u))
            uvs.append(Float32(v))
            if x < columns and y < rows:
                var a = y * (columns + 1) + x
                var b = a + 1
                var d = a + columns + 1
                var c = d + 1
                index.append(a)
                index.append(b)
                index.append(d)
                index.append(b)
                index.append(c)
                index.append(d)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uvs^, 2))
    geometry.set_index(index^)
    geometry.compute_vertex_normals()
    return part(geometry, id)


def _corner(point: Vec3d, side: Float64) -> Vec3d:
    """Return a cabin corner on one side."""
    return Vec3d(point.x * side, point.y, point.z)


def _roof(spec: CarSpec) raises -> BufferGeometry:
    """Return the roof, an open loft across the two roof edges."""
    var sections = List[List[Vector3]]()
    for edge in [spec.front_roof, spec.rear_roof]:  # pragma: no branch
        var row = List[Vector3]()
        for i in range(5):  # pragma: no branch
            var u = Float64(i) / 4
            row.append(
                _v(
                    (u * 2 - 1) * edge.x,
                    edge.y + 4 * u * (1 - u) * 0.035,
                    edge.z,
                )
            )
        sections.append(row^)
    return part(loft(sections, False), CAR_BODY)


def _wheel(
    mut parts: List[BufferGeometry], spec: CarSpec, side: Float64, z: Float64
) raises:
    """Add one wheel: the tyre, the rim's lip, the hub and the dark well
    behind it."""
    var r = spec.wheel_radius
    var rim = r * 0.64
    var width = r * 0.68
    var x = side * spec.wheel_x
    var profile: List[Vector2] = [
        Vector2(Float32(r * 0.93), Float32(-width * 0.44)),
        Vector2(Float32(r), Float32(-width * 0.12)),
        Vector2(Float32(r * 0.98), Float32(width * 0.27)),
        Vector2(Float32(rim + 0.014), Float32(width * 0.44)),
    ]
    var tyre = lathe(profile, 24)
    tyre.rotate_z(_a(-side * pi / 2))
    tyre.translate(_l(x), _l(r), _l(z))
    var lip_profile: List[Vector2] = [
        Vector2(Float32(rim + 0.014), Float32(width * 0.44)),
        Vector2(Float32(rim), Float32(width * 0.29)),
    ]
    var lip = lathe(lip_profile, 24)
    lip.rotate_z(_a(-side * pi / 2))
    lip.translate(_l(x), _l(r), _l(z))
    var hub = circle(_l(rim), 24)
    var center = hub.clone_attribute(String(POSITION))
    center.set_component(0, 2, -0.015)
    hub.set_attribute(String(POSITION), center^)
    hub.compute_vertex_normals()
    hub.rotate_y(_a(side * pi / 2))
    hub.translate(_l(x + side * width * 0.29), _l(r), _l(z))
    var well = circle(_l(r + 0.06), 8, _a(0), _a(pi))
    well.rotate_y(_a(side * pi / 2))
    well.translate(_l(x - side * (width * 0.5 + 0.02)), _l(r), _l(z))
    parts.append(part(tyre, CAR_TYRE))
    parts.append(part(lip, CAR_ALLOY))
    parts.append(part(hub, CAR_ALLOY))
    parts.append(part(well, CAR_TRIM))


def _rails(spec: CarSpec, side: Float64) raises -> BufferGeometry:
    """Return one roof rail of an SUV, a capped loft of four small
    rectangles."""
    var tfr = _corner(spec.front_roof, 1)
    var trr = _corner(spec.rear_roof, 1)
    var sections = List[List[Vector3]]()
    var stops: List[Float64] = [0.06, 0.13, 0.87, 0.94]
    for i in range(4):  # pragma: no branch
        var t = stops[i]
        var z = tfr.z + (trr.z - tfr.z) * t
        var roof_width = tfr.x + (trr.x - tfr.x) * t
        var bow = 1 - (0.63 / roof_width) * (0.63 / roof_width)
        var rise = 0.005 if i == 0 or i == 3 else 0.05
        var y = tfr.y + (trr.y - tfr.y) * t + bow * 0.035 + rise
        var x = side * 0.63
        var row: List[Vector3] = [
            _v(x - 0.022, y + 0.018, z),
            _v(x + 0.022, y + 0.018, z),
            _v(x + 0.022, y - 0.018, z),
            _v(x - 0.022, y - 0.018, z),
        ]
        sections.append(row^)
    return part(loft(sections, True, True, True), CAR_TRIM)


def _sign(spec: CarSpec) raises -> BufferGeometry:
    """Return the taxi's roof sign, a capped loft of two rectangles."""
    var roof_y = (spec.front_roof.y + spec.rear_roof.y) / 2 + 0.04
    var sections = List[List[Vector3]]()
    var widths: List[Float64] = [0.16, 0.20]
    var depths: List[Float64] = [0.065, 0.095]
    var heights: List[Float64] = [roof_y + 0.1, roof_y]
    for i in range(2):  # pragma: no branch
        var w = widths[i]
        var d = depths[i]
        var y = heights[i]
        var row: List[Vector3] = [
            _v(w, y, d - 0.2),
            _v(-w, y, d - 0.2),
            _v(-w, y, -d - 0.2),
            _v(w, y, -d - 0.2),
        ]
        sections.append(row^)
    return part(loft(sections, True, True, True), CAR_SIGN)


def car_geometry(spec: CarSpec) raises -> BufferGeometry:
    """Return one body's whole car, three.js's `buildCarGeometry`.

    Args:
        spec: The body.

    Returns:
        The car, indexed, with a `partId`.

    Raises:
        Error: If a part cannot be built.
    """
    var parts: List[BufferGeometry] = [build_body(spec)]
    var fl = _corner(spec.front_base, -1)
    var fr = _corner(spec.front_base, 1)
    var rl = _corner(spec.rear_base, -1)
    var rr = _corner(spec.rear_base, 1)
    var tfl = _corner(spec.front_roof, -1)
    var tfr = _corner(spec.front_roof, 1)
    var trl = _corner(spec.rear_roof, -1)
    var trr = _corner(spec.rear_roof, 1)
    parts.append(panel([fl, fr, tfr, tfl], CAR_WINDOW, True))
    parts.append(panel([rr, rl, trl, trr], CAR_WINDOW, True))
    parts.append(panel([fr, rr, trr, tfr], CAR_WINDOW, False))
    parts.append(panel([rl, fl, tfl, trl], CAR_WINDOW, False))
    parts.append(_roof(spec))
    for s in range(2):  # pragma: no branch
        var side = Float64(s * 2 - 1)
        _wheel(parts, spec, side, -spec.wheel_z)
        _wheel(parts, spec, side, spec.wheel_z)
        var mirror = box(_l(0.16), _l(0.1), _l(0.2))
        mirror.rotate_y(_a(side * 0.2))
        mirror.translate(
            _l(side * (spec.at(2, 1) + 0.06)),
            _l(spec.front_base.y + 0.05),
            _l(spec.front_base.z - 0.16),
        )
        parts.append(part(mirror, CAR_MIRROR))
        if spec.rails:
            parts.append(_rails(spec, side))
    if spec.sign:
        parts.append(_sign(spec))
    return merge_geometries(parts)


def body_type_of(index: Int, color: Int) -> BodyType:
    """Return the body a car takes from its place in the fleet and its
    paint, as three.js deals them: the taxi's yellow takes the taxi, and
    about four cars in ten of the rest take the SUV.

    Args:
        index: The car's place in the list, from zero.
        color: Its paint, as hex sRGB.

    Returns:
        The body.
    """
    var hashed = (index * 2654435761) & 0xFFFFFFFF
    return TAXI if color == TAXI_COLOR else (
        SUV if hashed % 100 < 42 else SEDAN
    )


@fieldwise_init
struct CarPlacement(Copyable, Movable):
    """One car to place: where, and its paint as hex sRGB."""

    var matrix: Matrix4
    var color: Int


struct CarGenerator(Movable):
    """Builds the fleet, three.js's `CarGenerator`: one instanced draw a
    body, each car with its own paint."""

    def __init__(out self):
        """Create a generator. three.js's has no parameters."""
        pass

    def build(self, cars: List[CarPlacement]) raises -> List[Instances]:
        """Deal each car a body and place it, three.js's `build`.

        Args:
            cars: The cars.

        Returns:
            One set of instances a body in use, named `Car`, in the order
            the bodies first appear. Each carries its cars' paint, three
            linear numbers a car, three.js's `paintColor` attribute.

        Raises:
            Error: If a body cannot be built.
        """
        var types = List[Int]()
        var groups = List[Instances]()
        for i in range(len(cars)):
            var body = body_type_of(i, cars[i].color)
            var slot = -1
            for k in range(len(types)):
                slot = k if types[k] == body.value else slot
            if slot < 0:
                slot = len(types)
                types.append(body.value)
                var instances = Instances("Car", car_geometry(CarSpec(body)))
                instances.item_size = 3
                instances.cast_shadow = True
                instances.receive_shadow = True
                groups.append(instances^)
            groups[slot].matrices.append(cars[i].matrix)
            var hex = cars[i].color
            for shift in [16, 8, 0]:  # pragma: no branch
                groups[slot].values.append(
                    Float32(
                        srgb_to_linear_three(
                            Float64((hex >> shift) & 0xFF) / 255.0
                        )
                    )
                )
        return groups^
