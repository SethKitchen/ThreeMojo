# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The canonical building model.

A `Building` holds storeys, spaces, elements and openings over one cell
complex. `assemble` builds it from storey plans: each space is a cell,
each wall face of the complex is a wall element, and each floor, ground
and roof face is a slab or roof element. Columns, beams and openings are
added after.

The model is the one source that every view reads. A render view, a
structural view, a thermal view and an exchange file each derive their
own form from it and record what they drop.

Coordinates are meters, z up. The x axis points east and the y axis points
north unless `Site.north` says otherwise.
"""

from std.math import isfinite
from extensions.building.construction import Construction, Glazing
from extensions.building.ids import (
    ConstructionId,
    ElementId,
    FurnishingId,
    MaterialId,
    OpeningId,
    SpaceId,
    StoreyId,
)
from extensions.building.kinds import (
    BEAM,
    FurnitureKind,
    CIRCLE,
    COLUMN,
    DOOR,
    ElementKind,
    I_SHAPE,
    OpeningKind,
    RECTANGLE,
    ROOF,
    SLAB,
    SectionShape,
    SpaceUse,
    WALL,
    WINDOW,
)
from extensions.building.material import BuildingMaterial
from extensions.topology.arrangement import Point2, Region, contains
from extensions.topology.complex import HORIZONTAL, VERTICAL
from extensions.topology.ids import CellId, FaceId, RegionId
from extensions.topology.storeys import StoreyComplex, build_storeys
from generators.utils import Vec3d
from std.math import cos, pi, sin
from units.si import (
    Angle64,
    Area64,
    DEGREE,
    Length64,
    METER,
    RADIAN,
    SQUARE_METER,
    SecondMomentOfArea64,
    Volume64,
    CUBIC_METER,
    METER_TO_THE_FOURTH,
)


@fieldwise_init
struct Site(ImplicitlyCopyable):
    """Where the building stands."""

    var latitude: Angle64
    var longitude: Angle64
    var elevation: Length64
    # The angle from the model's +y axis to true north, counterclockwise
    # seen from above.
    var north: Angle64

    def check(self) raises:
        """Refuse a site that is not on the Earth.

        Raises:
            Error: If the latitude is outside -90 to 90 degrees, the
                longitude outside -180 to 180, or a value is not finite.
        """
        var lat = self.latitude.to(DEGREE)
        var lon = self.longitude.to(DEGREE)
        if not (lat >= -90 and lat <= 90):
            raise Error("A latitude must be from -90 to 90 degrees")
        if not (lon >= -180 and lon <= 180):
            raise Error("A longitude must be from -180 to 180 degrees")
        if not (
            isfinite(self.elevation.to(METER))
            and isfinite(self.north.to(RADIAN))
        ):
            raise Error("A site elevation and north must be finite")


struct Storey(Copyable, Movable):
    """A storey: its name, the height of its floor and its height."""

    var name: String
    var elevation: Length64
    var height: Length64

    def __init__(
        out self, var name: String, elevation: Length64, height: Length64
    ):
        """Create a storey.

        Args:
            name: A name for people and for exchange files.
            elevation: The height of its floor.
            height: From its floor to the floor above.
        """
        self.name = name^
        self.elevation = elevation
        self.height = height


struct Space(Copyable, Movable):
    """A room: a cell of the complex, on a storey, with a use."""

    var name: String
    var storey: StoreyId
    var use: SpaceUse
    var cell: CellId
    var outline: List[Point2]

    def __init__(
        out self,
        var name: String,
        storey: StoreyId,
        use: SpaceUse,
        cell: CellId,
        var outline: List[Point2],
    ):
        """Create a space.

        Args:
            name: A name for people and for exchange files.
            storey: The storey it is on.
            use: What it is used for.
            cell: Its cell in the complex.
            outline: Its plan polygon, as given to `assemble`.
        """
        self.name = name^
        self.storey = storey
        self.use = use
        self.cell = cell
        self.outline = outline^


@fieldwise_init
struct Section(ImplicitlyCopyable):
    """The cross-section of a frame member.

    A rectangle uses the width and the depth. A circle uses the width as
    its diameter. An I-shape has two flanges of the width and the flange
    thickness, and a web of the web thickness between them. The depth is
    the overall depth, in the plane of strong-axis bending.
    """

    var shape: SectionShape
    var width: Length64
    var depth: Length64
    var flange_thickness: Length64
    var web_thickness: Length64

    def check(self) raises:
        """Refuse a section that cannot be made.

        Raises:
            Error: If the shape is not valid, a used dimension is not
                positive and finite, or an I-shape's plates do not fit.
        """
        if not self.shape.is_valid():
            raise Error("A section shape must be a rectangle, an I or a circle")
        var b = self.width.to(METER)
        var d = self.depth.to(METER)
        if not (b > 0 and isfinite(b)):
            raise Error("A section width must be positive and finite")
        if self.shape == CIRCLE:
            return
        if not (d > 0 and isfinite(d)):
            raise Error("A section depth must be positive and finite")
        if self.shape == I_SHAPE:
            var tf = self.flange_thickness.to(METER)
            var tw = self.web_thickness.to(METER)
            if not (tf > 0 and 2 * tf < d and tw > 0 and tw < b):
                raise Error("An I-shape's flanges and web must fit its size")

    def area(self) -> Area64:
        """Return the area of the section.

        Returns:
            The cross-sectional area.
        """
        var b = self.width.to(METER)
        var d = self.depth.to(METER)
        if self.shape == CIRCLE:
            return Area64(pi * b * b / 4)
        if self.shape == I_SHAPE:
            var tf = self.flange_thickness.to(METER)
            var tw = self.web_thickness.to(METER)
            return Area64(2 * b * tf + (d - 2 * tf) * tw)
        return Area64(b * d)

    def strong_inertia(self) -> SecondMomentOfArea64:
        """Return the second moment of area for bending in the depth.

        Returns:
            The second moment about the axis parallel to the width.
        """
        var b = self.width.to(METER)
        var d = self.depth.to(METER)
        if self.shape == CIRCLE:
            return SecondMomentOfArea64(pi * b * b * b * b / 64)
        if self.shape == I_SHAPE:
            var tf = self.flange_thickness.to(METER)
            var tw = self.web_thickness.to(METER)
            var inner = d - 2 * tf
            return SecondMomentOfArea64(
                (b * d * d * d - (b - tw) * inner * inner * inner) / 12
            )
        return SecondMomentOfArea64(b * d * d * d / 12)

    def weak_inertia(self) -> SecondMomentOfArea64:
        """Return the second moment of area for bending in the width.

        Returns:
            The second moment about the axis parallel to the depth.
        """
        var b = self.width.to(METER)
        var d = self.depth.to(METER)
        if self.shape == CIRCLE:
            return SecondMomentOfArea64(pi * b * b * b * b / 64)
        if self.shape == I_SHAPE:
            var tf = self.flange_thickness.to(METER)
            var tw = self.web_thickness.to(METER)
            var inner = d - 2 * tf
            return SecondMomentOfArea64(
                (2 * tf * b * b * b + inner * tw * tw * tw) / 12
            )
        return SecondMomentOfArea64(d * b * b * b / 12)

    def torsion_constant(self) -> SecondMomentOfArea64:
        """Return Saint-Venant's torsion constant.

        A circle is exact. A rectangle uses the series approximation
        a b³ (1/3 - 0.21 (b/a) (1 - b⁴/(12 a⁴))) with a the longer side,
        within 0.2% of the exact value.
        An I-shape is the sum of its thin plates, b t³ / 3 each.

        Returns:
            The torsion constant.
        """
        var b = self.width.to(METER)
        var d = self.depth.to(METER)
        if self.shape == CIRCLE:
            return SecondMomentOfArea64(pi * b * b * b * b / 32)
        if self.shape == I_SHAPE:
            var tf = self.flange_thickness.to(METER)
            var tw = self.web_thickness.to(METER)
            return SecondMomentOfArea64(
                (2 * b * tf * tf * tf + (d - 2 * tf) * tw * tw * tw) / 3
            )
        var long_side = max(b, d)
        var short_side = min(b, d)
        var r = short_side / long_side
        return SecondMomentOfArea64(
            long_side
            * short_side
            * short_side
            * short_side
            * (1.0 / 3.0 - 0.21 * r * (1 - r * r * r * r / 12))
        )


def rectangle(width: Length64, depth: Length64) -> Section:
    """Return a solid rectangular section.

    Args:
        width: The width.
        depth: The depth, in the plane of strong-axis bending.

    Returns:
        The section.
    """
    return Section(RECTANGLE, width, depth, Length64(0), Length64(0))


def i_shape(
    width: Length64,
    depth: Length64,
    flange_thickness: Length64,
    web_thickness: Length64,
) -> Section:
    """Return a doubly symmetric I-section.

    Args:
        width: The flange width.
        depth: The overall depth.
        flange_thickness: The thickness of each flange.
        web_thickness: The thickness of the web.

    Returns:
        The section.
    """
    return Section(I_SHAPE, width, depth, flange_thickness, web_thickness)


struct Element(Copyable, Movable):
    """A wall, slab, roof, column or beam.

    A wall, slab or roof lies on faces of the complex and has a
    construction. A column or beam lies on an axis from `start` to `end`
    and has a section and a material.
    """

    var name: String
    var kind: ElementKind
    var storey: StoreyId
    var faces: List[FaceId]
    var construction: Optional[ConstructionId]
    var material: Optional[MaterialId]
    var section: Optional[Section]
    var start: Vec3d
    var end: Vec3d

    def __init__(
        out self,
        var name: String,
        kind: ElementKind,
        storey: StoreyId,
        var faces: List[FaceId],
        construction: Optional[ConstructionId],
        material: Optional[MaterialId],
        section: Optional[Section],
        start: Vec3d,
        end: Vec3d,
    ):
        """Create an element. `Building` makes these.

        Args:
            name: A name for people and for exchange files.
            kind: What it is.
            storey: The storey it belongs to.
            faces: The faces it lies on, for a wall, slab or roof.
            construction: Its layers, for a wall, slab or roof.
            material: Its material, for a column or beam.
            section: Its cross-section, for a column or beam.
            start: The start of its axis, in meters, for a column or beam.
            end: The end of its axis, in meters, for a column or beam.
        """
        self.name = name^
        self.kind = kind
        self.storey = storey
        self.faces = faces^
        self.construction = construction
        self.material = material
        self.section = section
        self.start = start
        self.end = end


struct Opening(Copyable, Movable):
    """A door or window in a wall.

    The opening is a rectangle in the wall's frame: `offset` along the
    wall's base from its start, `sill` up from its base.
    """

    var name: String
    var kind: OpeningKind
    var host: ElementId
    var offset: Length64
    var sill: Length64
    var width: Length64
    var height: Length64
    var glazing: Optional[Glazing]

    def __init__(
        out self,
        var name: String,
        kind: OpeningKind,
        host: ElementId,
        offset: Length64,
        sill: Length64,
        width: Length64,
        height: Length64,
        glazing: Optional[Glazing],
    ):
        """Create an opening. `Building.add_opening` makes these.

        Args:
            name: A name for people and for exchange files.
            kind: A door or a window.
            host: The wall it is in.
            offset: From the wall's start along its base to the opening.
            sill: From the wall's base up to the opening.
            width: The opening's width.
            height: The opening's height.
            glazing: The window unit, for a window.
        """
        self.name = name^
        self.kind = kind
        self.host = host
        self.offset = offset
        self.sill = sill
        self.width = width
        self.height = height
        self.glazing = glazing


struct Furnishing(Copyable, Movable):
    """A piece of furniture: a box standing on its space's floor.

    The box is `width` along its own x axis, `depth` along its own y axis
    and `height` up. Its front faces its own +y axis. `rotation` turns it
    counterclockwise about its center, seen from above.
    """

    var name: String
    var kind: FurnitureKind
    var space: SpaceId
    var center: Point2
    var rotation: Angle64
    var width: Length64
    var depth: Length64
    var height: Length64

    def __init__(
        out self,
        var name: String,
        kind: FurnitureKind,
        space: SpaceId,
        center: Point2,
        rotation: Angle64,
        width: Length64,
        depth: Length64,
        height: Length64,
    ):
        """Create a furnishing. `Building.add_furnishing` makes these.

        Args:
            name: A name for people and for exchange files.
            kind: What it is.
            space: The space it stands in.
            center: Its center in plan, in meters.
            rotation: Its turn about its center, counterclockwise.
            width: Its size along its own x axis.
            depth: Its size along its own y axis, front to back.
            height: Its height.
        """
        self.name = name^
        self.kind = kind
        self.space = space
        self.center = center
        self.rotation = rotation
        self.width = width
        self.depth = depth
        self.height = height

    def corners(self) -> List[Point2]:
        """Return the corners of its footprint, counterclockwise.

        Returns:
            Four plan points, in meters.
        """
        var c = cos(self.rotation.to(RADIAN))
        var s = sin(self.rotation.to(RADIAN))
        var hw = self.width.to(METER) / 2
        var hd = self.depth.to(METER) / 2
        var local: List[Point2] = [
            Point2(-hw, -hd),
            Point2(hw, -hd),
            Point2(hw, hd),
            Point2(-hw, hd),
        ]
        var out = List[Point2](capacity=4)
        for i in range(4):  # pragma: no branch
            var p = local[i]
            out.append(
                Point2(
                    self.center.x + c * p.x - s * p.y,
                    self.center.y + s * p.x + c * p.y,
                )
            )
        return out^


def quads_apart(a: List[Point2], b: List[Point2]) -> Bool:
    """Return True if two convex quadrilaterals do not overlap.

    By the separating axis theorem, they are apart when the projections on
    the normal of some edge do not overlap. Touching is not overlap.

    Args:
        a: The first quadrilateral's four corners, in order.
        b: The second quadrilateral's four corners, in order.

    Returns:
        Whether they share no interior point.
    """
    for pass_index in range(2):  # pragma: no branch
        ref shape = a if pass_index == 0 else b
        for i in range(4):  # pragma: no branch
            var p = shape[i]
            var q = shape[(i + 1) % 4]
            var nx = q.y - p.y
            var ny = p.x - q.x
            var a_low = Float64.MAX
            var a_high = -Float64.MAX
            var b_low = Float64.MAX
            var b_high = -Float64.MAX
            for k in range(4):  # pragma: no branch
                var pa = a[k].x * nx + a[k].y * ny
                var pb = b[k].x * nx + b[k].y * ny
                a_low = min(a_low, pa)
                a_high = max(a_high, pa)
                b_low = min(b_low, pb)
                b_high = max(b_high, pb)
            var scale = abs(nx) + abs(ny)
            if a_high <= b_low + 1e-9 * scale or b_high <= a_low + 1e-9 * scale:
                return True
    return False


def _inside(outline: List[Point2], p: Point2, tolerance: Float64) -> Bool:
    """Return True if a point is inside a polygon or within a tolerance of
    its boundary."""
    if contains(outline, p):
        return True
    var n = len(outline)
    for i in range(n):  # pragma: no branch
        var a = outline[i]
        var b = outline[(i + 1) % n]
        var d = b - a
        var t = max(0.0, min(1.0, (p - a).dot(d) / d.dot(d)))
        var foot = Point2(a.x + t * d.x, a.y + t * d.y)
        var offset = p - foot
        if offset.dot(offset) <= tolerance * tolerance:
            return True
    return False


@fieldwise_init
struct WallFrame(ImplicitlyCopyable):
    """A wall face's own frame.

    `origin` is the start of the wall's base. `along` runs along the base,
    `up` is +z, and `normal` points to the wall face's positive side.
    """

    var origin: Vec3d
    var along: Vec3d
    var up: Vec3d
    var normal: Vec3d
    var length: Float64
    var height: Float64

    def point(self, u: Float64, v: Float64, w: Float64) -> Vec3d:
        """Return a point given in the wall's frame.

        Args:
            u: Meters along the base.
            v: Meters up.
            w: Meters along the normal.

        Returns:
            The point in model coordinates.
        """
        return self.origin + self.along * u + self.up * v + self.normal * w


struct SpacePlan(Copyable, Movable):
    """A space to assemble: a name, a use and a plan polygon."""

    var name: String
    var use: SpaceUse
    var outline: List[Point2]

    def __init__(
        out self, var name: String, use: SpaceUse, var outline: List[Point2]
    ):
        """Create a space plan.

        Args:
            name: A name for people and for exchange files.
            use: What the space is used for.
            outline: Its plan polygon, in meters.
        """
        self.name = name^
        self.use = use
        self.outline = outline^


struct StoreyPlan(Copyable, Movable):
    """A storey to assemble: a name, a height and its spaces."""

    var name: String
    var height: Length64
    var spaces: List[SpacePlan]

    def __init__(
        out self,
        var name: String,
        height: Length64,
        var spaces: List[SpacePlan],
    ):
        """Create a storey plan.

        Args:
            name: A name for people and for exchange files.
            height: From its floor to the floor above.
            spaces: Its spaces. They must not overlap.
        """
        self.name = name^
        self.height = height
        self.spaces = spaces^


@fieldwise_init
struct ConstructionSet(ImplicitlyCopyable):
    """The constructions `assemble` gives each kind of face."""

    var exterior_wall: ConstructionId
    var interior_wall: ConstructionId
    var ground_slab: ConstructionId
    var floor: ConstructionId
    var roof: ConstructionId


struct Building(Movable):
    """The canonical building model."""

    var name: String
    var site: Site
    var storeys: List[Storey]
    var spaces: List[Space]
    var elements: List[Element]
    var openings: List[Opening]
    var furnishings: List[Furnishing]
    var materials: List[BuildingMaterial]
    var constructions: List[Construction]
    var topology: StoreyComplex
    # The element on each face of the complex, or -1.
    var face_element: List[Int]

    def __init__(
        out self,
        var name: String,
        site: Site,
        var materials: List[BuildingMaterial],
        var constructions: List[Construction],
        var topology: StoreyComplex,
    ):
        """Hold an empty model over a complex. `assemble` makes these.

        Args:
            name: A name for people and for exchange files.
            site: Where it stands.
            materials: Its materials.
            constructions: Its constructions.
            topology: Its cell complex.
        """
        self.name = name^
        self.site = site
        self.storeys = List[Storey]()
        self.spaces = List[Space]()
        self.elements = List[Element]()
        self.openings = List[Opening]()
        self.furnishings = List[Furnishing]()
        self.materials = materials^
        self.constructions = constructions^
        self.topology = topology^
        self.face_element = List[Int]()

    # --- checks -----------------------------------------------------------

    def check_storey(self, id: StoreyId) raises:
        """Refuse a storey id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last storey.
        """
        if not id.is_valid() or id.value >= len(self.storeys):
            raise Error("A storey id is out of range")

    def check_space(self, id: SpaceId) raises:
        """Refuse a space id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last space.
        """
        if not id.is_valid() or id.value >= len(self.spaces):
            raise Error("A space id is out of range")

    def check_element(self, id: ElementId) raises:
        """Refuse an element id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last element.
        """
        if not id.is_valid() or id.value >= len(self.elements):
            raise Error("An element id is out of range")

    def check_opening(self, id: OpeningId) raises:
        """Refuse an opening id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last opening.
        """
        if not id.is_valid() or id.value >= len(self.openings):
            raise Error("An opening id is out of range")

    def check_furnishing(self, id: FurnishingId) raises:
        """Refuse a furnishing id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last furnishing.
        """
        if not id.is_valid() or id.value >= len(self.furnishings):
            raise Error("A furnishing id is out of range")

    def check_material(self, id: MaterialId) raises:
        """Refuse a material id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last material.
        """
        if not id.is_valid() or id.value >= len(self.materials):
            raise Error("A material id is out of range")

    def check_construction(self, id: ConstructionId) raises:
        """Refuse a construction id that is not in range.

        Args:
            id: The id.

        Raises:
            Error: If it is negative or past the last construction.
        """
        if not id.is_valid() or id.value >= len(self.constructions):
            raise Error("A construction id is out of range")

    # --- frame members and openings ----------------------------------------

    def add_column(
        mut self,
        storey: StoreyId,
        at: Point2,
        section: Section,
        material: MaterialId,
    ) raises -> ElementId:
        """Add a column from a storey's floor to the floor above.

        Args:
            storey: The storey.
            at: Its plan position, in meters.
            section: Its cross-section. The depth runs along x.
            material: Its material.

        Returns:
            The new element.

        Raises:
            Error: If an id is out of range, the section is not valid, or
                the position is not finite.
        """
        self.check_storey(storey)
        self.check_material(material)
        section.check()
        if not (isfinite(at.x) and isfinite(at.y)):
            raise Error("A column position must be finite")
        ref s = self.storeys[storey.value]
        var z0 = s.elevation.to(METER)
        var z1 = z0 + s.height.to(METER)
        self.elements.append(
            Element(
                String("column ", len(self.elements)),
                COLUMN,
                storey,
                List[FaceId](),
                None,
                material,
                section,
                Vec3d(at.x, at.y, z0),
                Vec3d(at.x, at.y, z1),
            )
        )
        return ElementId(len(self.elements) - 1)

    def add_beam(
        mut self,
        storey: StoreyId,
        start: Point2,
        end: Point2,
        section: Section,
        material: MaterialId,
    ) raises -> ElementId:
        """Add a beam that carries the floor above a storey.

        The axis lies at the top of the storey, the level of the floor
        above. A render view hangs the member below that level.

        Args:
            storey: The storey under the beam.
            start: One end in plan, in meters.
            end: The other end in plan, in meters.
            section: Its cross-section.
            material: Its material.

        Returns:
            The new element.

        Raises:
            Error: If an id is out of range, the section is not valid, an
                end is not finite, or the ends are the same point.
        """
        self.check_storey(storey)
        self.check_material(material)
        section.check()
        if not (
            isfinite(start.x)
            and isfinite(start.y)
            and isfinite(end.x)
            and isfinite(end.y)
        ):
            raise Error("A beam's ends must be finite")
        var d = end - start
        if d.dot(d) <= 1e-12:
            raise Error("A beam's ends must differ")
        ref s = self.storeys[storey.value]
        var z = s.elevation.to(METER) + s.height.to(METER)
        self.elements.append(
            Element(
                String("beam ", len(self.elements)),
                BEAM,
                storey,
                List[FaceId](),
                None,
                material,
                section,
                Vec3d(start.x, start.y, z),
                Vec3d(end.x, end.y, z),
            )
        )
        return ElementId(len(self.elements) - 1)

    def wall_frame(self, wall: ElementId) raises -> WallFrame:
        """Return the frame of a wall element's face.

        Args:
            wall: The wall.

        Returns:
            Its frame: the base start, the directions and the size.

        Raises:
            Error: If the id is out of range or the element is not a wall.
        """
        self.check_element(wall)
        ref element = self.elements[wall.value]
        if element.kind != WALL:
            raise Error("The element is not a wall")
        var face = element.faces[0]
        var points = self.topology.complex.face_points(face)
        var a = points[0]
        var z0 = a.z
        # The base runs from the first corner to the last corner at z0.
        var k = 1
        while points[k + 1].z == z0:
            k += 1
        var b = points[k]
        var top = points[k + 1].z
        var along = (b - a).normalized()
        var normal = self.topology.complex.face_normal(face)
        return WallFrame(
            a, along, Vec3d(0, 0, 1), normal, a.distance_to(b), top - z0
        )

    def add_opening(
        mut self,
        kind: OpeningKind,
        wall: ElementId,
        offset: Length64,
        sill: Length64,
        width: Length64,
        height: Length64,
        glazing: Optional[Glazing],
    ) raises -> OpeningId:
        """Add a door or a window to a wall.

        Args:
            kind: `DOOR` or `WINDOW`.
            wall: The wall.
            offset: From the wall's start along its base.
            sill: From the wall's base up. Zero for a door.
            width: The opening's width.
            height: The opening's height.
            glazing: The window unit. Required for a window.

        Returns:
            The new opening.

        Raises:
            Error: If the kind is not valid, the host is not a wall, a size
                is not positive and finite, the opening does not fit the
                wall, it overlaps another opening, a door does not start at
                the floor, or a window has no glazing.
        """
        if not kind.is_valid():
            raise Error("An opening kind must be a door or a window")
        var frame = self.wall_frame(wall)
        var u0 = offset.to(METER)
        var v0 = sill.to(METER)
        var w = width.to(METER)
        var h = height.to(METER)
        if not (w > 0 and h > 0 and isfinite(w) and isfinite(h)):
            raise Error("An opening's size must be positive and finite")
        if not (u0 >= 0 and v0 >= 0):
            raise Error("An opening must lie inside its wall")
        if u0 + w > frame.length + 1e-9 or v0 + h > frame.height + 1e-9:
            raise Error("An opening must lie inside its wall")
        if kind == DOOR and v0 != 0:
            raise Error("A door must start at the floor")
        if kind == WINDOW:
            if not glazing:
                raise Error("A window needs a glazing")
            glazing.value().check()
        for i in range(len(self.openings)):
            ref other = self.openings[i]
            if other.host != wall:
                continue
            var ou = other.offset.to(METER)
            var ov = other.sill.to(METER)
            var apart = (
                u0 >= ou + other.width.to(METER)
                or ou >= u0 + w
                or v0 >= ov + other.height.to(METER)
                or ov >= v0 + h
            )
            if not apart:
                raise Error("Two openings in one wall must not overlap")
        self.openings.append(
            Opening(
                String(kind.name(), " ", len(self.openings)),
                kind,
                wall,
                offset,
                sill,
                width,
                height,
                glazing,
            )
        )
        return OpeningId(len(self.openings) - 1)

    def add_furnishing(
        mut self,
        kind: FurnitureKind,
        space: SpaceId,
        center: Point2,
        rotation: Angle64,
        width: Length64,
        depth: Length64,
        height: Length64,
    ) raises -> FurnishingId:
        """Add a piece of furniture to a space.

        Args:
            kind: What it is.
            space: The space it stands in.
            center: Its center in plan, in meters.
            rotation: Its turn about its center, counterclockwise.
            width: Its size along its own x axis.
            depth: Its size along its own y axis, front to back.
            height: Its height.

        Returns:
            The new furnishing.

        Raises:
            Error: If the kind is not valid, the space id is out of range, a
                size is not positive and finite, the position or rotation is
                not finite, the footprint leaves the space, or it overlaps
                another furnishing.
        """
        if not kind.is_valid():
            raise Error("A furniture kind is not valid")
        self.check_space(space)
        var sizes = [width.to(METER), depth.to(METER), height.to(METER)]
        for i in range(3):  # pragma: no branch
            if not (sizes[i] > 0 and isfinite(sizes[i])):
                raise Error("A furnishing's size must be positive and finite")
        if not (
            isfinite(center.x)
            and isfinite(center.y)
            and isfinite(rotation.to(RADIAN))
        ):
            raise Error("A furnishing's place must be finite")
        var item = Furnishing(
            String(kind.name(), " ", len(self.furnishings)),
            kind,
            space,
            center,
            rotation,
            width,
            depth,
            height,
        )
        var corners = item.corners()
        ref outline = self.spaces[space.value].outline
        for i in range(4):  # pragma: no branch
            if not _inside(outline, corners[i], 1e-9):
                raise Error("A furnishing must stand inside its space")
        for i in range(len(self.furnishings)):
            if self.furnishings[i].space != space:
                continue
            if not quads_apart(corners, self.furnishings[i].corners()):
                raise Error("Two furnishings must not overlap")
        self.furnishings.append(item^)
        return FurnishingId(len(self.furnishings) - 1)

    # --- queries ----------------------------------------------------------

    def element_of_face(self, face: FaceId) raises -> Optional[ElementId]:
        """Return the element that lies on a face, if any.

        Args:
            face: A face of the complex.

        Returns:
            The element, or None.

        Raises:
            Error: If the face id is out of range.
        """
        if not face.is_valid() or face.value >= len(self.face_element):
            raise Error("A face id is out of range")
        var index = self.face_element[face.value]
        if index < 0:
            return None
        return ElementId(index)

    def elements_of_space(self, space: SpaceId) raises -> List[ElementId]:
        """Return the walls, slabs and roofs that bound a space.

        Args:
            space: The space.

        Returns:
            The elements on the faces of its cell, in face order.

        Raises:
            Error: If the id is out of range.
        """
        self.check_space(space)
        var out = List[ElementId]()
        var faces = self.topology.complex.faces_of(
            self.spaces[space.value].cell
        )
        for i in range(len(faces)):  # pragma: no branch
            var element = self.element_of_face(faces[i])
            if element:
                out.append(element.value())
        return out^

    def openings_of(self, wall: ElementId) raises -> List[OpeningId]:
        """Return the openings in a wall.

        Args:
            wall: The wall.

        Returns:
            Its openings, in the order they were added.

        Raises:
            Error: If the id is out of range.
        """
        self.check_element(wall)
        var out = List[OpeningId]()
        for i in range(len(self.openings)):
            if self.openings[i].host == wall:
                out.append(OpeningId(i))
        return out^

    def space_neighbors(self, space: SpaceId) raises -> List[SpaceId]:
        """Return the spaces that share a face with a space.

        Args:
            space: The space.

        Returns:
            The neighboring spaces, once each.

        Raises:
            Error: If the id is out of range.
        """
        self.check_space(space)
        var cells = self.topology.complex.neighbors(
            self.spaces[space.value].cell
        )
        var out = List[SpaceId]()
        for i in range(len(cells)):
            out.append(SpaceId(cells[i].value))
        return out^

    def floor_area(self, space: SpaceId) raises -> Area64:
        """Return the floor area of a space.

        Args:
            space: The space.

        Returns:
            The area of its plan polygon.

        Raises:
            Error: If the id is out of range.
        """
        self.check_space(space)
        var cell = self.spaces[space.value].cell
        var faces = self.topology.complex.faces_of(cell)
        var total = Float64(0)
        for i in range(len(faces)):  # pragma: no branch
            ref face = self.topology.complex.faces[faces[i].value]
            if (
                face.kind == HORIZONTAL
                and face.positive
                and face.positive.value() == cell
            ):
                total += self.topology.complex.face_area(faces[i])
        return Area64(total, SQUARE_METER)

    def volume(self, space: SpaceId) raises -> Volume64:
        """Return the volume of a space.

        Args:
            space: The space.

        Returns:
            The volume of its cell.

        Raises:
            Error: If the id is out of range.
        """
        self.check_space(space)
        return Volume64(
            self.topology.complex.cell_volume(self.spaces[space.value].cell),
            CUBIC_METER,
        )

    def gross_floor_area(self) raises -> Area64:
        """Return the sum of the floor areas of every space.

        Returns:
            The total floor area.

        Raises:
            Error: Never, for a model made by `assemble`.
        """
        var total = Area64(0)
        for i in range(len(self.spaces)):
            total = total + self.floor_area(SpaceId(i))
        return total

    def is_exterior(self, element: ElementId) raises -> Bool:
        """Return True if an element has the outside on one side.

        A column or a beam is never exterior.

        Args:
            element: The element.

        Returns:
            Whether a face of the element has no cell on one side.

        Raises:
            Error: If the id is out of range.
        """
        self.check_element(element)
        ref faces = self.elements[element.value].faces
        for i in range(len(faces)):
            ref face = self.topology.complex.faces[faces[i].value]
            if not face.positive or not face.negative:
                return True
        return False

    def validate(self) raises:
        """Refuse a model whose parts do not agree.

        Raises:
            Error: If a cell is not closed, a material or construction is
                not valid, or an id in any part is out of range.
        """
        self.site.check()
        self.topology.complex.validate()
        for i in range(len(self.materials)):
            self.materials[i].check()
        for i in range(len(self.constructions)):
            self.constructions[i].check(self.materials)
        for i in range(len(self.spaces)):
            self.check_storey(self.spaces[i].storey)
            if not self.spaces[i].use.is_valid():
                raise Error("A space use is not valid")
        for i in range(len(self.elements)):
            ref element = self.elements[i]
            self.check_storey(element.storey)
            if not element.kind.is_valid():
                raise Error("An element kind is not valid")
            if element.construction:
                self.check_construction(element.construction.value())
            if element.material:
                self.check_material(element.material.value())
        for i in range(len(self.openings)):
            self.check_element(self.openings[i].host)
        for i in range(len(self.furnishings)):
            self.check_space(self.furnishings[i].space)
            if not self.furnishings[i].kind.is_valid():
                raise Error("A furniture kind is not valid")


def assemble(
    var name: String,
    site: Site,
    base: Length64,
    plans: List[StoreyPlan],
    var materials: List[BuildingMaterial],
    var constructions: List[Construction],
    defaults: ConstructionSet,
    tolerance: Length64,
) raises -> Building:
    """Return a building model from storey plans.

    Each space becomes a cell. Each wall face becomes a wall element: an
    exterior wall where the outside is on one side, an interior wall
    between two spaces. Each horizontal face becomes a ground slab, a
    floor or a roof.

    Args:
        name: A name for people and for exchange files.
        site: Where it stands.
        base: The elevation of the first storey's floor.
        plans: The storeys, from the lowest up.
        materials: The materials the constructions use.
        constructions: The constructions the elements use.
        defaults: Which construction each kind of face gets.
        tolerance: Plan points closer than this are one point.

    Returns:
        The model, without columns, beams or openings.

    Raises:
        Error: If the site, a material or a construction is not valid, a
            default construction id is out of range, a storey height is
            not positive and finite, a space use is not valid, or the plans
            do not form a valid cell complex.
    """
    site.check()
    for i in range(len(materials)):
        materials[i].check()
    for i in range(len(constructions)):
        constructions[i].check(materials)
    var defaults_list = [
        defaults.exterior_wall,
        defaults.interior_wall,
        defaults.ground_slab,
        defaults.floor,
        defaults.roof,
    ]
    for i in range(len(defaults_list)):  # pragma: no branch
        var id = defaults_list[i]
        if not id.is_valid() or id.value >= len(constructions):
            raise Error("A default construction id is out of range")
    var levels = List[Length64]()
    var z = base
    levels.append(z)
    var regions = List[List[Region]]()
    for s in range(len(plans)):
        var h = plans[s].height.to(METER)
        if not (h > 0 and isfinite(h)):
            raise Error("A storey height must be positive and finite")
        z = z + plans[s].height
        levels.append(z)
        var plan = List[Region]()
        for r in range(len(plans[s].spaces)):
            if not plans[s].spaces[r].use.is_valid():
                raise Error("A space use is not valid")
            plan.append(
                Region(0, RegionId(r), plans[s].spaces[r].outline.copy())
            )
        regions.append(plan^)
    var topology = build_storeys(levels, regions, tolerance)
    var building = Building(name^, site, materials^, constructions^, topology^)
    for s in range(len(plans)):
        building.storeys.append(
            Storey(plans[s].name, levels[s], plans[s].height)
        )
    # Spaces in cell order: cell i is space i.
    for c in range(building.topology.complex.cell_count()):
        var s = building.topology.cell_storey[c]
        var r = building.topology.cell_region[c].value
        ref plan = plans[s].spaces[r]
        building.spaces.append(
            Space(
                plan.name,
                StoreyId(s),
                plan.use,
                CellId(c),
                plan.outline.copy(),
            )
        )
    ref complex = building.topology.complex
    for f in range(len(complex.faces)):
        ref face = complex.faces[f]
        var level = building.topology.face_level[f]
        var kind = WALL
        var construction = defaults.interior_wall
        var storey = level
        if face.kind == VERTICAL:
            if not face.positive or not face.negative:
                construction = defaults.exterior_wall
        elif not face.positive:
            kind = ROOF
            construction = defaults.roof
            storey = level - 1
        elif not face.negative:
            kind = SLAB
            construction = (
                defaults.ground_slab if level == 0 else defaults.floor
            )
        else:
            kind = SLAB
            construction = defaults.floor
        var faces = List[FaceId]()
        faces.append(FaceId(f))
        building.face_element.append(len(building.elements))
        building.elements.append(
            Element(
                String(kind.name(), " ", len(building.elements)),
                kind,
                StoreyId(storey),
                faces^,
                construction,
                None,
                None,
                Vec3d(0, 0, 0),
                Vec3d(0, 0, 0),
            )
        )
    return building^
