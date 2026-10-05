# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The building model as IFC4, written and read.

`write_ifc` writes a model as an IFC4 STEP file: a project with SI units, a
site, a building, its storeys and spaces, and its walls, slabs, columns,
beams, openings, doors and windows. Each solid is an extruded area: a
polygon, a rectangle, an I-shape or a circle swept along a direction.
Materials carry their physical properties in property sets, and each wall
and slab carries its construction as a material layer set. Windows carry
their glazing. Each storey carries its height as a gross-height quantity.

`read_ifc` reads such a file back into a model. It rebuilds the cell
complex from the space outlines, so the walls and slabs come from the
topology, as `assemble` makes them. It then gives each wall and slab the
name and construction of the file element that lies on the same place,
and adds the named columns, beams, doors, windows and furniture. The
round-trip tests compare fields directly as well as fingerprints. Exact
exchange uses the supported order and layout from `assemble` and `add_*`,
not arbitrary collection reordering or unused struct fields.

A file from another program can be read when its spaces are extruded
polygons on storeys. Elements that do not match a face of the rebuilt
complex keep the first construction. A material with no properties takes
the library values of the material its name suggests.

The mapping follows the IFC4 schema of buildingSMART International,
published as ISO 16739-1:2018.
"""

from std.math import atan2, cos, isfinite, pi, sin, sqrt
from extensions.building.construction import (
    Construction,
    Glazing,
    Layer,
)
from extensions.building.fingerprint import fingerprint
from extensions.building.ids import (
    ConstructionId,
    ElementId,
    MaterialId,
    SpaceId,
    StoreyId,
)
from extensions.building.ifc.step import (
    StepFile,
    DERIVED,
    INTEGER,
    LIST,
    REAL,
    REFERENCE,
    STRING,
    UNSET,
    parse,
)
from extensions.building.kinds import (
    BEAM,
    FurnitureKind,
    CIRCLE,
    COLUMN,
    DOOR,
    ElementKind,
    I_SHAPE,
    OFFICE,
    RECTANGLE,
    ROOF,
    SLAB,
    SpaceUse,
    WALL,
    WINDOW,
)
from extensions.building.material import (
    BuildingMaterial,
    Look,
    aluminum,
    brick,
    concrete,
    glass,
    gypsum_board,
    mineral_wool,
    steel,
    timber,
)
from extensions.building.model import (
    Building,
    ConstructionSet,
    Section,
    Site,
    SpacePlan,
    StoreyPlan,
    assemble,
)
from extensions.topology.arrangement import Point2
from extensions.topology.loops import split_bridged, vector_area
from generators.utils import Vec3d
from units.si import (
    Angle64,
    DEGREE,
    DEGREE64,
    Density64,
    GIGAPASCAL,
    JOULE_PER_KILOGRAM_KELVIN,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    PASCAL,
    PER_KELVIN,
    Pressure64,
    RADIAN,
    SpecificHeatCapacity64,
    ThermalConductivity64,
    ThermalExpansion64,
    ThermalTransmittance64,
    WATT_PER_METER_KELVIN,
    WATT_PER_SQUARE_METER_KELVIN,
)

comptime _GUID_ALPHABET = (
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_$"
)


def _mix(value: UInt64) -> UInt64:
    """The SplitMix64 finalizer: a bijective scramble of 64 bits."""
    var z = value + 0x9E3779B97F4A7C15
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB
    return z ^ (z >> 31)


def ifc_guid(seed: UInt64, index: Int) -> String:
    """Return a deterministic IFC GlobalId: 128 bits in 22 characters.

    The first character holds the top two bits and each later character
    holds six, in the alphabet of the IFC standard.

    Args:
        seed: The model's fingerprint, or any 64-bit seed.
        index: The number of this id within the file.

    Returns:
        The 22-character id.
    """
    var high = _mix(seed ^ _mix(UInt64(index) * 2 + 1))
    var low = _mix(high ^ UInt64(index))
    var out = String(_GUID_ALPHABET[byte=Int(high >> 62)])
    # 126 more bits: 62 from high, then 64 from low.
    var bits = List[Int]()
    var i = 61
    while i >= 0:
        bits.append(Int((high >> UInt64(i)) & 1))
        i -= 1
    i = 63
    while i >= 0:
        bits.append(Int((low >> UInt64(i)) & 1))
        i -= 1
    var k = 0
    while k < 126:
        var v = 0
        for b in range(6):  # pragma: no branch
            v = v * 2 + bits[k + b]
        out += String(_GUID_ALPHABET[byte=v])
        k += 6
    return out^


struct _Writer(Movable):
    """A STEP file under construction, with the shared placements."""

    var f: StepFile
    var seed: UInt64
    var guids: Int
    var context: Int

    def __init__(out self, seed: UInt64):
        self.f = StepFile()
        self.seed = seed
        self.guids = 0
        self.context = 0

    def guid(mut self) -> Int:
        self.guids += 1
        return self.f.string(ifc_guid(self.seed, self.guids))

    def point3(mut self, p: Vec3d) raises -> Int:
        var coordinates = self.f.reals([p.x, p.y, p.z])
        return self.f.add("IFCCARTESIANPOINT", [coordinates])

    def point2(mut self, x: Float64, y: Float64) raises -> Int:
        var coordinates = self.f.reals([x, y])
        return self.f.add("IFCCARTESIANPOINT", [coordinates])

    def direction3(mut self, d: Vec3d) raises -> Int:
        var ratios = self.f.reals([d.x, d.y, d.z])
        return self.f.add("IFCDIRECTION", [ratios])

    def placement3(mut self, origin: Vec3d, z: Vec3d, x: Vec3d) raises -> Int:
        var o = self.f.reference(self.point3(origin))
        var a = self.f.reference(self.direction3(z))
        var r = self.f.reference(self.direction3(x))
        return self.f.add("IFCAXIS2PLACEMENT3D", [o, a, r])

    def placement2(mut self, x: Float64, y: Float64) raises -> Int:
        var o = self.f.reference(self.point2(x, y))
        return self.f.add("IFCAXIS2PLACEMENT2D", [o, self.f.unset()])

    def local(mut self, relative: Int, placement: Int) -> Int:
        var rel = self.f.reference(relative) if relative > 0 else self.f.unset()
        return self.f.add(
            "IFCLOCALPLACEMENT", [rel, self.f.reference(placement)]
        )

    def body(mut self, solid: Int) -> Int:
        var items = self.f.references([solid])
        var representation = self.f.add(
            "IFCSHAPEREPRESENTATION",
            [
                self.f.reference(self.context),
                self.f.string("Body"),
                self.f.string("SweptSolid"),
                items,
            ],
        )
        var reps = self.f.references([representation])
        return self.f.add(
            "IFCPRODUCTDEFINITIONSHAPE", [self.f.unset(), self.f.unset(), reps]
        )

    def extrusion(
        mut self, profile: Int, position: Int, depth: Float64
    ) raises -> Int:
        var up = self.direction3(Vec3d(0, 0, 1))
        return self.f.add(
            "IFCEXTRUDEDAREASOLID",
            [
                self.f.reference(profile),
                self.f.reference(position),
                self.f.reference(up),
                self.f.real(depth),
            ],
        )

    def polyline(mut self, points: List[Vec3d]) raises -> Int:
        var ids = List[Int]()
        for i in range(len(points)):  # pragma: no branch
            ids.append(self.point2(points[i].x, points[i].y))
        ids.append(ids[0])
        return self.f.add("IFCPOLYLINE", [self.f.references(ids)])

    def polygon_profile(
        mut self, outer: List[Vec3d], holes: List[List[Vec3d]]
    ) raises -> Int:
        var curve = self.polyline(outer)
        if len(holes) == 0:
            return self.f.add(
                "IFCARBITRARYCLOSEDPROFILEDEF",
                [
                    self.f.enumeration("AREA"),
                    self.f.unset(),
                    self.f.reference(curve),
                ],
            )
        var inner = List[Int]()
        for h in range(len(holes)):  # pragma: no branch
            inner.append(self.polyline(holes[h]))
        return self.f.add(
            "IFCARBITRARYPROFILEDEFWITHVOIDS",
            [
                self.f.enumeration("AREA"),
                self.f.unset(),
                self.f.reference(curve),
                self.f.references(inner),
            ],
        )

    def rectangle(
        mut self, cx: Float64, cy: Float64, x: Float64, y: Float64
    ) raises -> Int:
        var position = self.placement2(cx, cy)
        return self.f.add(
            "IFCRECTANGLEPROFILEDEF",
            [
                self.f.enumeration("AREA"),
                self.f.unset(),
                self.f.reference(position),
                self.f.real(x),
                self.f.real(y),
            ],
        )

    def section(mut self, s: Section, cy: Float64) raises -> Int:
        if s.shape == CIRCLE:
            var position = self.placement2(0, cy)
            return self.f.add(
                "IFCCIRCLEPROFILEDEF",
                [
                    self.f.enumeration("AREA"),
                    self.f.unset(),
                    self.f.reference(position),
                    self.f.real(s.width.value / 2),
                ],
            )
        if s.shape == I_SHAPE:
            var position = self.placement2(0, cy)
            return self.f.add(
                "IFCISHAPEPROFILEDEF",
                [
                    self.f.enumeration("AREA"),
                    self.f.unset(),
                    self.f.reference(position),
                    self.f.real(s.width.value),
                    self.f.real(s.depth.value),
                    self.f.real(s.web_thickness.value),
                    self.f.real(s.flange_thickness.value),
                    self.f.unset(),
                    self.f.unset(),
                    self.f.unset(),
                ],
            )
        return self.rectangle(0, cy, s.width.value, s.depth.value)

    def single(
        mut self, name: String, type_name: String, value: Float64
    ) raises -> Int:
        var typed = self.f.typed(type_name, self.f.real(value))
        return self.f.add(
            "IFCPROPERTYSINGLEVALUE",
            [self.f.string(name), self.f.unset(), typed, self.f.unset()],
        )

    def material_properties(
        mut self, name: String, var properties: List[Int], material: Int
    ) -> Int:
        return self.f.add(
            "IFCMATERIALPROPERTIES",
            [
                self.f.string(name),
                self.f.unset(),
                self.f.references(properties),
                self.f.reference(material),
            ],
        )

    def relation(mut self, var name: String, var arguments: List[Int]) -> Int:
        var all = List[Int]()
        all.append(self.guid())
        all.append(self.f.unset())
        all.append(self.f.unset())
        all.append(self.f.unset())
        for i in range(len(arguments)):  # pragma: no branch
            all.append(arguments[i])
        return self.f.add(name^, all^)

    def product(
        mut self,
        var name: String,
        label: String,
        object_type: Optional[String],
        placement: Int,
        shape: Optional[Int],
        var rest: List[Int],
    ) -> Int:
        var all = List[Int]()
        all.append(self.guid())
        all.append(self.f.unset())
        all.append(self.f.string(label))
        all.append(self.f.unset())
        all.append(
            self.f.string(
                object_type.value()
            ) if object_type else self.f.unset()
        )
        all.append(self.f.reference(placement))
        all.append(self.f.reference(shape.value()) if shape else self.f.unset())
        for i in range(len(rest)):  # pragma: no branch
            all.append(rest[i])
        return self.f.add(name^, all^)


def _compound(angle: Float64) -> List[Int]:
    """Return an angle in degrees as IFC's degrees, minutes, seconds and
    millionths of a second, all of one sign."""
    var sign = -1 if angle < 0 else 1
    var micro = Int(abs(angle) * 3600e6 + 0.5)
    var degrees = micro // 3600000000
    micro -= degrees * 3600000000
    var minutes = micro // 60000000
    micro -= minutes * 60000000
    var seconds = micro // 1000000
    micro -= seconds * 1000000
    return [sign * degrees, sign * minutes, sign * seconds, sign * micro]


def write_ifc(building: Building, timestamp: String) raises -> String:
    """Return a building model as an IFC4 STEP file.

    Args:
        building: The model. It must validate.
        timestamp: The time stamp for the header, such as
            `2026-01-01T00:00:00`. A fixed stamp gives the same file for
            the same model.

    Returns:
        The file's text.

    Raises:
        Error: If the model does not validate.
    """
    building.validate()
    var seed = fingerprint(building)
    var w = _Writer(seed)
    # The header.
    w.f.add_header(
        "FILE_DESCRIPTION",
        [
            w.f.list([w.f.string("ViewDefinition [ReferenceView]")]),
            w.f.string("2;1"),
        ],
    )
    w.f.add_header(
        "FILE_NAME",
        [
            w.f.string(building.name),
            w.f.string(timestamp),
            w.f.list([w.f.string("")]),
            w.f.list([w.f.string("")]),
            w.f.string("ThreeMojo"),
            w.f.string("ThreeMojo building extension"),
            w.f.string(""),
        ],
    )
    w.f.add_header("FILE_SCHEMA", [w.f.list([w.f.string("IFC4")])])
    # Units and the geometric context.
    var units = List[Int]()
    var unit_names: List[String] = [
        "LENGTHUNIT",
        "AREAUNIT",
        "VOLUMEUNIT",
        "PLANEANGLEUNIT",
    ]
    var si_names: List[String] = [
        "METRE",
        "SQUARE_METRE",
        "CUBIC_METRE",
        "RADIAN",
    ]
    for i in range(4):  # pragma: no branch
        units.append(
            w.f.add(
                "IFCSIUNIT",
                [
                    w.f.derived(),
                    w.f.enumeration(unit_names[i]),
                    w.f.unset(),
                    w.f.enumeration(si_names[i]),
                ],
            )
        )
    var assignment = w.f.add("IFCUNITASSIGNMENT", [w.f.references(units)])
    var world = w.placement3(Vec3d(0, 0, 0), Vec3d(0, 0, 1), Vec3d(1, 0, 0))
    var north = building.site.north.to(RADIAN)
    var north_ratios = w.f.reals([-sin(north), cos(north)])
    var true_north = w.f.add("IFCDIRECTION", [north_ratios])
    w.context = w.f.add(
        "IFCGEOMETRICREPRESENTATIONCONTEXT",
        [
            w.f.unset(),
            w.f.string("Model"),
            w.f.integer(3),
            w.f.real(1e-5),
            w.f.reference(world),
            w.f.reference(true_north),
        ],
    )
    var project = w.f.add(
        "IFCPROJECT",
        [
            w.guid(),
            w.f.unset(),
            w.f.string(building.name),
            w.f.unset(),
            w.f.unset(),
            w.f.unset(),
            w.f.unset(),
            w.f.references([w.context]),
            w.f.reference(assignment),
        ],
    )
    # The site and the building.
    var site_place = w.local(0, world)
    var lat = _compound(building.site.latitude.to(DEGREE64))
    var lon = _compound(building.site.longitude.to(DEGREE64))
    var lat_values = List[Int]()
    var lon_values = List[Int]()
    for i in range(4):  # pragma: no branch
        lat_values.append(w.f.integer(lat[i]))
        lon_values.append(w.f.integer(lon[i]))
    var site = w.product(
        "IFCSITE",
        "site",
        None,
        site_place,
        None,
        [
            w.f.unset(),
            w.f.enumeration("ELEMENT"),
            w.f.list(lat_values^),
            w.f.list(lon_values^),
            w.f.real(building.site.elevation.value),
            w.f.unset(),
            w.f.unset(),
        ],
    )
    # The exact angles, which the compound angles and the true-north
    # direction only approximate.
    var site_set = w.f.add(
        "IFCPROPERTYSET",
        [
            w.guid(),
            w.f.unset(),
            w.f.string("ThreeMojo_Site"),
            w.f.unset(),
            w.f.references(
                [
                    w.single(
                        "Latitude",
                        "IFCPLANEANGLEMEASURE",
                        building.site.latitude.value,
                    ),
                    w.single(
                        "Longitude",
                        "IFCPLANEANGLEMEASURE",
                        building.site.longitude.value,
                    ),
                    w.single(
                        "North",
                        "IFCPLANEANGLEMEASURE",
                        building.site.north.value,
                    ),
                ]
            ),
        ],
    )
    _ = w.relation(
        "IFCRELDEFINESBYPROPERTIES",
        [w.f.references([site]), w.f.reference(site_set)],
    )
    var building_place = w.local(site_place, world)
    var ifc_building = w.product(
        "IFCBUILDING",
        building.name,
        None,
        building_place,
        None,
        [
            w.f.unset(),
            w.f.enumeration("ELEMENT"),
            w.f.unset(),
            w.f.unset(),
            w.f.unset(),
        ],
    )
    _ = w.relation(
        "IFCRELAGGREGATES", [w.f.reference(project), w.f.references([site])]
    )
    _ = w.relation(
        "IFCRELAGGREGATES",
        [w.f.reference(site), w.f.references([ifc_building])],
    )
    # Storeys, each with its height.
    var storey_ids = List[Int]()
    var storey_places = List[Int]()
    for s in range(len(building.storeys)):
        ref storey = building.storeys[s]
        var origin = w.placement3(
            Vec3d(0, 0, storey.elevation.value), Vec3d(0, 0, 1), Vec3d(1, 0, 0)
        )
        var place = w.local(building_place, origin)
        var id = w.product(
            "IFCBUILDINGSTOREY",
            storey.name,
            None,
            place,
            None,
            [
                w.f.unset(),
                w.f.enumeration("ELEMENT"),
                w.f.real(storey.elevation.value),
            ],
        )
        var height = w.f.add(
            "IFCQUANTITYLENGTH",
            [
                w.f.string("GrossHeight"),
                w.f.unset(),
                w.f.unset(),
                w.f.real(storey.height.value),
                w.f.unset(),
            ],
        )
        var quantities = w.f.add(
            "IFCELEMENTQUANTITY",
            [
                w.guid(),
                w.f.unset(),
                w.f.string("Qto_BuildingStoreyBaseQuantities"),
                w.f.unset(),
                w.f.unset(),
                w.f.references([height]),
            ],
        )
        _ = w.relation(
            "IFCRELDEFINESBYPROPERTIES",
            [w.f.references([id]), w.f.reference(quantities)],
        )
        storey_ids.append(id)
        storey_places.append(place)
    if len(storey_ids) > 0:
        _ = w.relation(
            "IFCRELAGGREGATES",
            [w.f.reference(ifc_building), w.f.references(storey_ids)],
        )
    # Materials, with their properties.
    var material_ids = List[Int]()
    for m in range(len(building.materials)):
        ref material = building.materials[m]
        var id = w.f.add(
            "IFCMATERIAL", [w.f.string(material.name), w.f.unset(), w.f.unset()]
        )
        material_ids.append(id)
        _ = w.material_properties(
            "Pset_MaterialCommon",
            [
                w.single(
                    "MassDensity",
                    "IFCMASSDENSITYMEASURE",
                    material.density.value,
                )
            ],
            id,
        )
        _ = w.material_properties(
            "Pset_MaterialMechanical",
            [
                w.single(
                    "YoungModulus",
                    "IFCMODULUSOFELASTICITYMEASURE",
                    material.elastic_modulus.value,
                ),
                w.single(
                    "PoissonRatio", "IFCRATIOMEASURE", material.poisson_ratio
                ),
                w.single(
                    "ThermalExpansionCoefficient",
                    "IFCTHERMALEXPANSIONCOEFFICIENTMEASURE",
                    material.thermal_expansion.value,
                ),
            ],
            id,
        )
        _ = w.material_properties(
            "Pset_MaterialThermal",
            [
                w.single(
                    "SpecificHeatCapacity",
                    "IFCSPECIFICHEATCAPACITYMEASURE",
                    material.specific_heat.value,
                ),
                w.single(
                    "ThermalConductivity",
                    "IFCTHERMALCONDUCTIVITYMEASURE",
                    material.conductivity.value,
                ),
            ],
            id,
        )
        var look = material.look
        _ = w.material_properties(
            "ThreeMojo_Material",
            [
                w.single(
                    "Strength", "IFCPRESSUREMEASURE", material.strength.value
                ),
                w.single("Red", "IFCNORMALISEDRATIOMEASURE", Float64(look.red)),
                w.single(
                    "Green", "IFCNORMALISEDRATIOMEASURE", Float64(look.green)
                ),
                w.single(
                    "Blue", "IFCNORMALISEDRATIOMEASURE", Float64(look.blue)
                ),
                w.single(
                    "Roughness",
                    "IFCNORMALISEDRATIOMEASURE",
                    Float64(look.roughness),
                ),
                w.single(
                    "Metalness",
                    "IFCNORMALISEDRATIOMEASURE",
                    Float64(look.metalness),
                ),
                w.single(
                    "Transmission",
                    "IFCNORMALISEDRATIOMEASURE",
                    Float64(look.transmission),
                ),
            ],
            id,
        )
    # Constructions, as layer sets.
    var layer_set_ids = List[Int]()
    for c in range(len(building.constructions)):
        ref construction = building.constructions[c]
        var layers = List[Int]()
        # A valid construction has a layer.
        for k in range(len(construction.layers)):  # pragma: no branch
            ref layer = construction.layers[k]
            layers.append(
                w.f.add(
                    "IFCMATERIALLAYER",
                    [
                        w.f.reference(material_ids[layer.material.value]),
                        w.f.real(layer.thickness.value),
                        w.f.unset(),
                        w.f.unset(),
                        w.f.unset(),
                        w.f.unset(),
                        w.f.unset(),
                    ],
                )
            )
        layer_set_ids.append(
            w.f.add(
                "IFCMATERIALLAYERSET",
                [
                    w.f.references(layers),
                    w.f.string(construction.name),
                    w.f.unset(),
                ],
            )
        )
    # Spaces, aggregated by storey.
    var storey_spaces = List[List[Int]]()
    var storey_elements = List[List[Int]]()
    for _ in range(len(building.storeys)):
        storey_spaces.append(List[Int]())
        storey_elements.append(List[Int]())
    var space_ids = List[Int]()
    var space_places = List[Int]()
    for sp in range(len(building.spaces)):
        ref space = building.spaces[sp]
        var s = space.storey.value
        var outline = List[Vec3d]()
        for k in range(len(space.outline)):  # pragma: no branch
            outline.append(Vec3d(space.outline[k].x, space.outline[k].y, 0))
        var profile = w.polygon_profile(outline, List[List[Vec3d]]())
        var position = w.placement3(
            Vec3d(0, 0, 0), Vec3d(0, 0, 1), Vec3d(1, 0, 0)
        )
        var solid = w.extrusion(
            profile, position, building.storeys[s].height.value
        )
        var place = w.local(storey_places[s], position)
        var id = w.product(
            "IFCSPACE",
            space.name,
            space.use.name(),
            place,
            w.body(solid),
            [
                w.f.unset(),
                w.f.enumeration("ELEMENT"),
                w.f.enumeration("SPACE"),
                w.f.unset(),
            ],
        )
        storey_spaces[s].append(id)
        space_ids.append(id)
        space_places.append(place)
    for s in range(len(building.storeys)):
        if len(storey_spaces[s]) > 0:
            _ = w.relation(
                "IFCRELAGGREGATES",
                [
                    w.f.reference(storey_ids[s]),
                    w.f.references(storey_spaces[s]),
                ],
            )
    # Elements.
    var element_ids = List[Int]()
    var element_places = List[Int]()
    var by_construction = List[List[Int]]()
    for _ in range(len(building.constructions)):
        by_construction.append(List[Int]())
    var by_material = List[List[Int]]()
    for _ in range(len(building.materials)):
        by_material.append(List[Int]())
    for e in range(len(building.elements)):
        ref element = building.elements[e]
        var s = element.storey.value
        var elevation = building.storeys[s].elevation.value
        var id: Int
        var place: Int
        if element.kind == WALL:
            var frame = building.wall_frame(ElementId(e))
            var t = (
                building.constructions[element.construction.value().value]
                .thickness()
                .value
            )
            var origin = frame.origin - Vec3d(0, 0, elevation)
            var axes = w.placement3(origin, Vec3d(0, 0, 1), frame.along)
            place = w.local(storey_places[s], axes)
            var profile = w.rectangle(frame.length / 2, 0, frame.length, t)
            var position = w.placement3(
                Vec3d(0, 0, 0), Vec3d(0, 0, 1), Vec3d(1, 0, 0)
            )
            var solid = w.extrusion(profile, position, frame.height)
            var predefined = "SOLIDWALL" if building.is_exterior(
                ElementId(e)
            ) else "PARTITIONING"
            id = w.product(
                "IFCWALL",
                element.name,
                None,
                place,
                w.body(solid),
                [w.f.unset(), w.f.enumeration(predefined)],
            )
        elif element.kind == SLAB or element.kind == ROOF:
            var t = (
                building.constructions[element.construction.value().value]
                .thickness()
                .value
            )
            var points = building.topology.complex.face_points(element.faces[0])
            var parts = split_bridged(points)
            var z = points[0].z - elevation
            place = w.local(storey_places[s], world)
            var profile = w.polygon_profile(parts.outer, parts.holes)
            var position = w.placement3(
                Vec3d(0, 0, z - t), Vec3d(0, 0, 1), Vec3d(1, 0, 0)
            )
            var solid = w.extrusion(profile, position, t)
            var predefined = "ROOF" if element.kind == ROOF else "FLOOR"
            id = w.product(
                "IFCSLAB",
                element.name,
                None,
                place,
                w.body(solid),
                [w.f.unset(), w.f.enumeration(predefined)],
            )
        else:
            var section = element.section.value()
            var axis = element.end - element.start
            var length = axis.length()
            var origin = element.start - Vec3d(0, 0, elevation)
            var cy = Float64(0)
            var axes: Int
            var entity = "IFCCOLUMN"
            var predefined = "COLUMN"
            if element.kind == COLUMN:
                axes = w.placement3(origin, Vec3d(0, 0, 1), Vec3d(0, -1, 0))
            else:
                var along = axis.normalized()
                var across = Vec3d(0, 0, 1).cross(along)
                axes = w.placement3(origin, along, across)
                var depth = (
                    section.width.value if section.shape
                    == CIRCLE else section.depth.value
                )
                cy = -depth / 2
                entity = "IFCBEAM"
                predefined = "BEAM"
            place = w.local(storey_places[s], axes)
            var profile = w.section(section, cy)
            var position = w.placement3(
                Vec3d(0, 0, 0), Vec3d(0, 0, 1), Vec3d(1, 0, 0)
            )
            var solid = w.extrusion(profile, position, length)
            id = w.product(
                entity,
                element.name,
                None,
                place,
                w.body(solid),
                [w.f.unset(), w.f.enumeration(predefined)],
            )
            by_material[element.material.value().value].append(id)
            var axis_set = w.f.add(
                "IFCPROPERTYSET",
                [
                    w.guid(),
                    w.f.unset(),
                    w.f.string("ThreeMojo_Member"),
                    w.f.unset(),
                    w.f.references(
                        [
                            w.single(
                                "StartX", "IFCLENGTHMEASURE", element.start.x
                            ),
                            w.single(
                                "StartY", "IFCLENGTHMEASURE", element.start.y
                            ),
                            w.single("EndX", "IFCLENGTHMEASURE", element.end.x),
                            w.single("EndY", "IFCLENGTHMEASURE", element.end.y),
                        ]
                    ),
                ],
            )
            _ = w.relation(
                "IFCRELDEFINESBYPROPERTIES",
                [w.f.references([id]), w.f.reference(axis_set)],
            )
        if element.construction:
            by_construction[element.construction.value().value].append(id)
        element_ids.append(id)
        element_places.append(place)
        storey_elements[s].append(id)
    # Openings, and the doors and windows in them.
    for o in range(len(building.openings)):
        ref opening = building.openings[o]
        var host = opening.host.value
        var t = (
            building.constructions[
                building.elements[host].construction.value().value
            ]
            .thickness()
            .value
        )
        var w_width = opening.width.value
        var w_height = opening.height.value
        var axes = w.placement3(
            Vec3d(opening.offset.value, 0, opening.sill.value),
            Vec3d(0, 0, 1),
            Vec3d(1, 0, 0),
        )
        var place = w.local(element_places[host], axes)
        var profile = w.rectangle(w_width / 2, 0, w_width, t + 0.1)
        var position = w.placement3(
            Vec3d(0, 0, 0), Vec3d(0, 0, 1), Vec3d(1, 0, 0)
        )
        var solid = w.extrusion(profile, position, w_height)
        var void_id = w.product(
            "IFCOPENINGELEMENT",
            String(opening.name, " opening"),
            None,
            place,
            w.body(solid),
            [w.f.unset(), w.f.enumeration("OPENING")],
        )
        _ = w.relation(
            "IFCRELVOIDSELEMENT",
            [w.f.reference(element_ids[host]), w.f.reference(void_id)],
        )
        var filler_place = w.local(place, world)
        var filler: Int
        if opening.kind == DOOR:
            filler = w.product(
                "IFCDOOR",
                opening.name,
                None,
                filler_place,
                None,
                [
                    w.f.unset(),
                    w.f.real(w_height),
                    w.f.real(w_width),
                    w.f.enumeration("DOOR"),
                    w.f.enumeration("SINGLE_SWING_LEFT"),
                    w.f.unset(),
                ],
            )
        else:
            filler = w.product(
                "IFCWINDOW",
                opening.name,
                None,
                filler_place,
                None,
                [
                    w.f.unset(),
                    w.f.real(w_height),
                    w.f.real(w_width),
                    w.f.enumeration("WINDOW"),
                    w.f.enumeration("SINGLE_PANEL"),
                    w.f.unset(),
                ],
            )
            var g = opening.glazing.value()
            var common = w.f.add(
                "IFCPROPERTYSET",
                [
                    w.guid(),
                    w.f.unset(),
                    w.f.string("Pset_WindowCommon"),
                    w.f.unset(),
                    w.f.references(
                        [
                            w.single(
                                "ThermalTransmittance",
                                "IFCTHERMALTRANSMITTANCEMEASURE",
                                g.u_value.value,
                            )
                        ]
                    ),
                ],
            )
            var glazing = w.f.add(
                "IFCPROPERTYSET",
                [
                    w.guid(),
                    w.f.unset(),
                    w.f.string("Pset_DoorWindowGlazingType"),
                    w.f.unset(),
                    w.f.references(
                        [
                            w.single(
                                "SolarHeatGainTransmittance",
                                "IFCNORMALISEDRATIOMEASURE",
                                g.solar_heat_gain,
                            ),
                            w.single(
                                "VisibleLightTransmittance",
                                "IFCNORMALISEDRATIOMEASURE",
                                g.visible_transmittance,
                            ),
                        ]
                    ),
                ],
            )
            _ = w.relation(
                "IFCRELDEFINESBYPROPERTIES",
                [w.f.references([filler]), w.f.reference(common)],
            )
            _ = w.relation(
                "IFCRELDEFINESBYPROPERTIES",
                [w.f.references([filler]), w.f.reference(glazing)],
            )
        _ = w.relation(
            "IFCRELFILLSELEMENT",
            [w.f.reference(void_id), w.f.reference(filler)],
        )
        storey_elements[building.elements[host].storey.value].append(filler)
    # Furniture, contained in its space.
    var space_furniture = List[List[Int]]()
    for _ in range(len(building.spaces)):
        space_furniture.append(List[Int]())
    for f in range(len(building.furnishings)):
        ref item = building.furnishings[f]
        var sp = item.space.value
        var angle = item.rotation.value
        var axes = w.placement3(
            Vec3d(item.center.x, item.center.y, 0),
            Vec3d(0, 0, 1),
            Vec3d(cos(angle), sin(angle), 0),
        )
        var place = w.local(space_places[sp], axes)
        var profile = w.rectangle(0, 0, item.width.value, item.depth.value)
        var position = w.placement3(
            Vec3d(0, 0, 0), Vec3d(0, 0, 1), Vec3d(1, 0, 0)
        )
        var solid = w.extrusion(profile, position, item.height.value)
        var id = w.product(
            "IFCFURNITURE",
            item.name,
            item.kind.name(),
            place,
            w.body(solid),
            [w.f.unset(), w.f.unset()],
        )
        var exact = w.f.add(
            "IFCPROPERTYSET",
            [
                w.guid(),
                w.f.unset(),
                w.f.string("ThreeMojo_Furnishing"),
                w.f.unset(),
                w.f.references(
                    [
                        w.single("CenterX", "IFCLENGTHMEASURE", item.center.x),
                        w.single("CenterY", "IFCLENGTHMEASURE", item.center.y),
                        w.single("Rotation", "IFCPLANEANGLEMEASURE", angle),
                    ]
                ),
            ],
        )
        _ = w.relation(
            "IFCRELDEFINESBYPROPERTIES",
            [w.f.references([id]), w.f.reference(exact)],
        )
        space_furniture[sp].append(id)
    for sp in range(len(building.spaces)):
        if len(space_furniture[sp]) > 0:
            _ = w.relation(
                "IFCRELCONTAINEDINSPATIALSTRUCTURE",
                [
                    w.f.references(space_furniture[sp]),
                    w.f.reference(space_ids[sp]),
                ],
            )
    for s in range(len(building.storeys)):
        if len(storey_elements[s]) > 0:
            _ = w.relation(
                "IFCRELCONTAINEDINSPATIALSTRUCTURE",
                [
                    w.f.references(storey_elements[s]),
                    w.f.reference(storey_ids[s]),
                ],
            )
    for c in range(len(building.constructions)):
        if len(by_construction[c]) > 0:
            _ = w.relation(
                "IFCRELASSOCIATESMATERIAL",
                [
                    w.f.references(by_construction[c]),
                    w.f.reference(layer_set_ids[c]),
                ],
            )
    for m in range(len(building.materials)):
        if len(by_material[m]) > 0:
            _ = w.relation(
                "IFCRELASSOCIATESMATERIAL",
                [
                    w.f.references(by_material[m]),
                    w.f.reference(material_ids[m]),
                ],
            )
    return w.f.write()


# --- reading ------------------------------------------------------------------


@fieldwise_init
struct _Frame(ImplicitlyCopyable):
    """A placement: an origin and three unit axes, in model coordinates."""

    var origin: Vec3d
    var x: Vec3d
    var y: Vec3d
    var z: Vec3d

    def point(self, p: Vec3d) -> Vec3d:
        return self.origin + self.x * p.x + self.y * p.y + self.z * p.z

    def direction(self, d: Vec3d) -> Vec3d:
        return self.x * d.x + self.y * d.y + self.z * d.z

    def then(self, inner: _Frame) -> _Frame:
        return _Frame(
            self.point(inner.origin),
            self.direction(inner.x),
            self.direction(inner.y),
            self.direction(inner.z),
        )


struct _Reader(Movable):
    """A parsed file and the relations the reader needs."""

    var f: StepFile
    var parent_of: Dict[Int, Int]
    var container: Dict[Int, Int]
    var material_of: Dict[Int, Int]
    var properties_of: Dict[Int, List[Int]]

    def __init__(out self, var f: StepFile) raises:
        self.f = f^
        self.parent_of = Dict[Int, Int]()
        self.container = Dict[Int, Int]()
        self.material_of = Dict[Int, Int]()
        self.properties_of = Dict[Int, List[Int]]()
        for rel in self.f.all_of("IFCRELAGGREGATES"):
            var relating = self.ref_arg(rel, 4)
            for item in self.f.as_list(self.arg(rel, 5)):
                self.parent_of[self.f.as_reference(item)] = relating
        for rel in self.f.all_of("IFCRELCONTAINEDINSPATIALSTRUCTURE"):
            var structure = self.ref_arg(rel, 5)
            for item in self.f.as_list(self.arg(rel, 4)):
                self.container[self.f.as_reference(item)] = structure
        for rel in self.f.all_of("IFCRELASSOCIATESMATERIAL"):
            var relating = self.ref_arg(rel, 5)
            for item in self.f.as_list(self.arg(rel, 4)):
                self.material_of[self.f.as_reference(item)] = relating
        for rel in self.f.all_of("IFCRELDEFINESBYPROPERTIES"):
            var definition = self.ref_arg(rel, 5)
            for item in self.f.as_list(self.arg(rel, 4)):
                var target = self.f.as_reference(item)
                if target not in self.properties_of:
                    self.properties_of[target] = List[Int]()
                self.properties_of[target].append(definition)

    def arg(self, id: Int, position: Int) raises -> Int:
        return self.f.untyped(self.f.argument(id, position))

    def ref_arg(self, id: Int, position: Int) raises -> Int:
        return self.f.as_reference(self.arg(id, position))

    def is_unset(self, id: Int, position: Int) raises -> Bool:
        return self.f.kind_of(self.arg(id, position)) == UNSET

    def real_arg(self, id: Int, position: Int) raises -> Float64:
        return self.f.as_real(self.arg(id, position))

    def name_arg(self, id: Int, position: Int) raises -> String:
        """Read a label that may be unset, as empty text."""
        var value = self.arg(id, position)
        if self.f.kind_of(value) == UNSET:
            return String("")
        return self.f.as_string(value)

    def name(self, id: Int) raises -> String:
        return self.f.entity(id).name

    def coordinates(self, point: Int) raises -> Vec3d:
        var items = self.f.as_list(self.arg(point, 0))
        var c: List[Float64] = [0, 0, 0]
        for i in range(min(3, len(items))):  # pragma: no branch
            c[i] = self.f.as_real(items[i])
        return Vec3d(c[0], c[1], c[2])

    def placement(self, id: Int) raises -> _Frame:
        """Resolve an IFCAXIS2PLACEMENT3D or an IFCAXIS2PLACEMENT2D."""
        var kind = self.name(id)
        var origin = self.coordinates(self.ref_arg(id, 0))
        var z = Vec3d(0, 0, 1)
        var x = Vec3d(1, 0, 0)
        if kind == "IFCAXIS2PLACEMENT2D":
            if not self.is_unset(id, 1):
                x = self.coordinates(self.ref_arg(id, 1))
        elif kind == "IFCAXIS2PLACEMENT3D":
            if not self.is_unset(id, 1):
                z = self.coordinates(self.ref_arg(id, 1)).normalized()
            if not self.is_unset(id, 2):
                x = self.coordinates(self.ref_arg(id, 2))
        else:
            raise Error(String("Unsupported placement ", kind))
        # Make x perpendicular to z, as the schema does.
        x = (x - z * x.dot(z)).normalized()
        return _Frame(origin, x, z.cross(x), z)

    def local(self, id: Int) raises -> _Frame:
        """Resolve an IFCLOCALPLACEMENT through its chain."""
        var visited = Dict[Int, Bool]()
        var chain = List[_Frame]()
        var current = id
        # Each successful step visits a distinct entity. The extra step
        # must find the root, a repeated id, or an invalid reference.
        # A nonnegative entity count plus one makes this range nonempty.
        for _ in range(len(self.f.entities) + 1):  # pragma: no branch
            if current in visited:
                raise Error("A local placement chain contains a cycle")
            if self.name(current) != "IFCLOCALPLACEMENT":
                raise Error(
                    "A local placement must reference IFCLOCALPLACEMENT"
                )
            visited[current] = True
            chain.append(self.placement(self.ref_arg(current, 1)))
            if self.is_unset(current, 0):
                break
            current = self.ref_arg(current, 0)
        # Compose from the root down, in the same order as nested frames.
        var frame = chain.pop()
        while len(chain) > 0:
            frame = frame.then(chain.pop())
        return frame

    def solid(self, product: Int) raises -> Int:
        """Return the first IFCEXTRUDEDAREASOLID of a product's shape."""
        if self.is_unset(product, 6):
            raise Error("A product has no shape")
        for rep in self.f.as_list(self.arg(self.ref_arg(product, 6), 2)):
            for item in self.f.as_list(self.arg(self.f.as_reference(rep), 3)):
                var id = self.f.as_reference(item)
                if self.name(id) == "IFCEXTRUDEDAREASOLID":
                    return id
        raise Error("A product has no extruded solid")

    def solid_frame(self, product: Int, solid: Int) raises -> _Frame:
        """Return the frame a product's solid is drawn in."""
        return self.local(self.ref_arg(product, 5)).then(
            self.placement(self.ref_arg(solid, 1))
        )

    def polyline(self, curve: Int, frame: _Frame) raises -> List[Vec3d]:
        """Return a closed polyline's corners, without the closing one."""
        if self.name(curve) != "IFCPOLYLINE":
            raise Error("A profile curve must be a polyline")
        var out = List[Vec3d]()
        for item in self.f.as_list(self.arg(curve, 0)):
            out.append(frame.point(self.coordinates(self.f.as_reference(item))))
        if len(out) > 1 and out[0].distance_to(out[len(out) - 1]) == 0:
            _ = out.pop()
        return out^

    def values(
        self, target: Int, set_name: String
    ) raises -> Dict[String, Float64]:
        """Return the real single values of a target's property set."""
        var out = Dict[String, Float64]()
        if target not in self.properties_of:
            return out^
        for definition in self.properties_of[target]:  # pragma: no branch
            if self.name(definition) != "IFCPROPERTYSET":
                continue
            if self.name_arg(definition, 2) != set_name:
                continue
            self._collect(self.f.as_list(self.arg(definition, 4)), out)
        return out^

    def _collect(self, items: List[Int], mut out: Dict[String, Float64]) raises:
        for item in items:
            var prop = self.f.as_reference(item)
            if self.name(prop) != "IFCPROPERTYSINGLEVALUE":
                continue
            if self.is_unset(prop, 2):
                continue
            out[self.name_arg(prop, 0)] = self.real_arg(prop, 2)


def _get(
    values: Dict[String, Float64], key: String, default: Float64
) -> Float64:
    """Return a property value, or a default when the file has none."""
    return values.get(key, default)


def _material_by_name(name: String) -> BuildingMaterial:
    """Return the library material a name suggests, concrete by default."""
    var lower = name.lower()
    var words: List[String] = [
        "steel",
        "timber",
        "wood",
        "brick",
        "masonry",
        "gypsum",
        "plaster",
        "wool",
        "insulation",
        "glass",
        "alumin",
    ]
    var which: List[Int] = [1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7]
    var library = [
        concrete(),
        steel(),
        timber(),
        brick(),
        gypsum_board(),
        mineral_wool(),
        glass(),
        aluminum(),
    ]
    for i in range(len(words)):  # pragma: no branch
        if lower.find(words[i]) >= 0:
            return library[which[i]].copy()
    return library[0].copy()


def _use_by_name(name: String) -> SpaceUse:
    """Return the space use whose name matches, or office."""
    var lower = name.lower()
    for i in range(12):  # pragma: no branch
        if SpaceUse(i).name() == lower:
            return SpaceUse(i)
    return OFFICE


def _plan_area_and_centroid(points: List[Vec3d]) -> Vec3d:
    """Return a polygon's plan centroid with its signed area as z."""
    var area = Float64(0)
    var cx = Float64(0)
    var cy = Float64(0)
    var n = len(points)
    for i in range(n):  # pragma: no branch
        var a = points[i]
        var b = points[(i + 1) % n]
        var cross = a.x * b.y - b.x * a.y
        area += cross
        cx += (a.x + b.x) * cross
        cy += (a.y + b.y) * cross
    return Vec3d(cx / (3 * area), cy / (3 * area), area / 2)


def _read_materials(
    r: _Reader, mut materials: List[BuildingMaterial]
) raises -> Dict[Int, Int]:
    """Read every IFCMATERIAL with its properties."""
    var index = Dict[Int, Int]()
    for id in r.f.all_of("IFCMATERIAL"):
        index[id] = len(materials)
        var m = _material_by_name(r.name_arg(id, 0))
        m.name = r.name_arg(id, 0)
        materials.append(m^)
    var values = Dict[Int, Dict[String, Float64]]()
    for id in r.f.all_of("IFCMATERIALPROPERTIES"):
        var owner = r.ref_arg(id, 3)
        if owner not in index:
            continue
        if owner not in values:
            values[owner] = Dict[String, Float64]()
        r._collect(r.f.as_list(r.arg(id, 2)), values[owner])
    for entry in values.items():
        ref m = materials[index[entry.key]]
        ref v = entry.value
        m.density = Density64(_get(v, "MassDensity", m.density.value))
        m.elastic_modulus = Pressure64(
            _get(v, "YoungModulus", m.elastic_modulus.value)
        )
        m.poisson_ratio = _get(v, "PoissonRatio", m.poisson_ratio)
        m.thermal_expansion = ThermalExpansion64(
            _get(v, "ThermalExpansionCoefficient", m.thermal_expansion.value)
        )
        m.specific_heat = SpecificHeatCapacity64(
            _get(v, "SpecificHeatCapacity", m.specific_heat.value)
        )
        m.conductivity = ThermalConductivity64(
            _get(v, "ThermalConductivity", m.conductivity.value)
        )
        m.strength = Pressure64(_get(v, "Strength", m.strength.value))
        m.look.red = Float32(_get(v, "Red", Float64(m.look.red)))
        m.look.green = Float32(_get(v, "Green", Float64(m.look.green)))
        m.look.blue = Float32(_get(v, "Blue", Float64(m.look.blue)))
        m.look.roughness = Float32(
            _get(v, "Roughness", Float64(m.look.roughness))
        )
        m.look.metalness = Float32(
            _get(v, "Metalness", Float64(m.look.metalness))
        )
        m.look.transmission = Float32(
            _get(v, "Transmission", Float64(m.look.transmission))
        )
    return index^


def _read_site(r: _Reader) raises -> Site:
    """Read the site's location and true north."""
    var site = Site(Angle64(0), Angle64(0), Length64(0), Angle64(0))
    for context in r.f.all_of("IFCGEOMETRICREPRESENTATIONCONTEXT"):
        if not r.is_unset(context, 5):
            var d = r.coordinates(r.ref_arg(context, 5))
            site.north = Angle64(atan2(-d.x, d.y), RADIAN)
    for s in r.f.all_of("IFCSITE"):
        var angles = List[Float64]()
        for position in range(9, 11):  # pragma: no branch
            var total = Float64(0)
            if not r.is_unset(s, position):
                var parts = r.f.as_list(r.arg(s, position))
                var scales: List[Float64] = [1, 60, 3600, 3600e6]
                for k in range(min(4, len(parts))):
                    total += Float64(r.f.as_integer(parts[k])) / scales[k]
            angles.append(total)
        site.latitude = Angle64(angles[0], DEGREE64)
        site.longitude = Angle64(angles[1], DEGREE64)
        if not r.is_unset(s, 11):
            site.elevation = Length64(r.real_arg(s, 11), METER)
        var exact = r.values(s, "ThreeMojo_Site")
        site.latitude = Angle64(_get(exact, "Latitude", site.latitude.value))
        site.longitude = Angle64(_get(exact, "Longitude", site.longitude.value))
        site.north = Angle64(_get(exact, "North", site.north.value))
    return site


def _check_length_unit(r: _Reader) raises:
    """Require one unprefixed meter length unit in the project's assignment.

    Other assigned quantities do not change coordinates. Unassigned unit
    entities do not define the project's lengths and are not inspected.
    """
    var projects = r.f.all_of("IFCPROJECT")
    if len(projects) != 1:
        raise Error("The file must have exactly one project with length units")
    if r.is_unset(projects[0], 8):
        raise Error("The project must assign length units in meters")
    var assignment = r.ref_arg(projects[0], 8)
    if r.name(assignment) != "IFCUNITASSIGNMENT":
        raise Error("The project's units must reference IFCUNITASSIGNMENT")
    var lengths = 0
    for item in r.f.as_list(r.arg(assignment, 0)):
        var unit = r.f.as_reference(item)
        var kind = r.name(unit)
        # These unit categories cannot define a project's length unit.
        if kind == "IFCMONETARYUNIT" or kind == "IFCDERIVEDUNIT":
            continue
        var named = (
            kind == "IFCSIUNIT"
            or kind == "IFCCONVERSIONBASEDUNIT"
            or kind == "IFCCONVERSIONBASEDUNITWITHOFFSET"
            or kind == "IFCCONTEXTDEPENDENTUNIT"
        )
        if not named:
            raise Error("Unsupported entity in the project's unit assignment")
        if r.f.as_enumeration(r.arg(unit, 1)) != "LENGTHUNIT":
            continue
        lengths += 1
        if lengths > 1:
            raise Error("The project must assign exactly one length unit")
        if kind != "IFCSIUNIT":
            raise Error(
                "The assigned length unit must be meters, with no conversion"
            )
        if (
            r.f.kind_of(r.arg(unit, 0)) != DERIVED
            or not r.is_unset(unit, 2)
            or r.f.as_enumeration(r.arg(unit, 3)) != "METRE"
        ):
            raise Error(
                "The assigned length unit must be meters, with no prefix"
            )
    if lengths != 1:
        raise Error("The project must assign exactly one length unit")


def read_ifc(text: String, tolerance: Length64) raises -> Building:
    """Return the building model of an IFC4 STEP file.

    Args:
        text: The file's text.
        tolerance: Plan points closer than this are one point.

    Returns:
        The model, with the complex rebuilt from the space outlines.

    Raises:
        Error: If the text is not STEP, the schema is not IFC4, the project
            does not assign exactly one supported meter length unit, a
            placement chain has a cycle or wrong kind, a space or member
            has an unsupported form or no storey, or the model does not
            validate.
    """
    var r = _Reader(parse(text))
    var schema = String("")
    for i in range(len(r.f.header)):
        if r.f.header[i].name == "FILE_SCHEMA":
            if len(r.f.header[i].arguments) != 1:
                raise Error("The IFC4 FILE_SCHEMA needs one schema list")
            for item in r.f.as_list(r.f.header[i].arguments[0]):
                schema = r.f.as_string(item).upper()
    if schema != "IFC4":
        raise Error("The file's schema must be IFC4")
    _check_length_unit(r)
    var materials = List[BuildingMaterial]()
    var material_index = _read_materials(r, materials)
    # Constructions from layer sets.
    var constructions = List[Construction]()
    var construction_index = Dict[Int, Int]()
    for id in r.f.all_of("IFCMATERIALLAYERSET"):
        construction_index[id] = len(constructions)
        var layers = List[Layer]()
        for item in r.f.as_list(r.arg(id, 0)):
            var layer = r.f.as_reference(item)
            var material = r.ref_arg(layer, 0)
            if material not in material_index:
                raise Error("A material layer names no material")
            layers.append(
                Layer(
                    MaterialId(material_index[material]),
                    Length64(r.real_arg(layer, 1), METER),
                )
            )
        constructions.append(Construction(r.name_arg(id, 1), layers^))
    if len(constructions) == 0:
        materials.append(concrete())
        constructions.append(
            Construction(
                "default slab",
                [Layer(MaterialId(len(materials) - 1), Length64(0.2, METER))],
            )
        )
    var site = _read_site(r)
    var name = String("building")
    for id in r.f.all_of("IFCBUILDING"):
        name = r.name_arg(id, 2)
    # Storeys, by elevation.
    var storey_list = r.f.all_of("IFCBUILDINGSTOREY")
    var elevations = List[Float64]()
    for id in storey_list:
        var elevation = r.local(r.ref_arg(id, 5)).origin.z
        if not r.is_unset(id, 9):
            elevation = r.real_arg(id, 9)
        elevations.append(elevation)
    var order = List[Int]()
    for i in range(len(storey_list)):
        var k = len(order)
        order.append(i)
        while k > 0 and elevations[order[k - 1]] > elevations[i]:
            order[k] = order[k - 1]
            k -= 1
        order[k] = i
    var storey_of = Dict[Int, Int]()
    for k in range(len(order)):
        storey_of[storey_list[order[k]]] = k
    # Spaces, grouped by storey in file order.
    var space_plans = List[List[SpacePlan]]()
    var space_depth = List[Float64]()
    for _ in range(len(order)):
        space_plans.append(List[SpacePlan]())
        space_depth.append(0)
    var file_spaces = List[Int]()
    for id in r.f.all_of("IFCSPACE"):
        var parent = r.parent_of.get(id, -1)
        if parent not in storey_of:
            raise Error("A space must belong to a storey")
        var s = storey_of[parent]
        var solid = r.solid(id)
        var at = r.solid_frame(id, solid)
        var profile = r.ref_arg(solid, 0)
        if r.name(profile) != "IFCARBITRARYCLOSEDPROFILEDEF":
            raise Error("A space profile must be a closed polyline")
        var points = r.polyline(r.ref_arg(profile, 2), at)
        var outline = List[Point2]()
        for k in range(len(points)):  # pragma: no branch
            outline.append(Point2(points[k].x, points[k].y))
        space_depth[s] = max(space_depth[s], r.real_arg(solid, 3))
        var use = _use_by_name(r.name_arg(id, 4))
        space_plans[s].append(SpacePlan(r.name_arg(id, 2), use, outline^))
        file_spaces.append(id)
    # Storey heights: the gross height, or the gap to the next storey, or
    # the depth of its spaces.
    var plans = List[StoreyPlan]()
    for k in range(len(order)):
        var id = storey_list[order[k]]
        var height = space_depth[k]
        if k + 1 < len(order):
            height = elevations[order[k + 1]] - elevations[order[k]]
        if id in r.properties_of:
            for definition in r.properties_of[id]:  # pragma: no branch
                if r.name(definition) != "IFCELEMENTQUANTITY":
                    continue
                for item in r.f.as_list(r.arg(definition, 5)):
                    var quantity = r.f.as_reference(item)
                    if r.name_arg(quantity, 0) == "GrossHeight":
                        height = r.real_arg(quantity, 3)
        plans.append(
            StoreyPlan(
                r.name_arg(id, 2),
                Length64(height, METER),
                space_plans[k].copy(),
            )
        )
    var base = Length64(0, METER)
    if len(order) > 0:
        base = Length64(elevations[order[0]], METER)
    var first = ConstructionId(0)
    var building = assemble(
        name,
        site,
        base,
        plans,
        materials^,
        constructions^,
        ConstructionSet(first, first, first, first, first),
        tolerance,
    )
    var tol = tolerance.to(METER)
    var file_wall = _match_surfaces(
        r, building, storey_of, construction_index, tol
    )
    _read_members(r, building, storey_of, material_index)
    _read_openings(r, building, file_wall)
    _read_furniture(r, building, file_spaces, storey_of)
    building.validate()
    return building^


def _match_surfaces(
    r: _Reader,
    mut building: Building,
    storey_of: Dict[Int, Int],
    construction_index: Dict[Int, Int],
    tol: Float64,
) raises -> Dict[Int, Int]:
    """Give each matched wall and slab its file name and construction.

    Return the model wall of each file wall.
    """
    var file_wall = Dict[Int, Int]()
    for id in r.f.all_of("IFCWALL") + r.f.all_of("IFCSLAB"):
        var s = storey_of.get(r.container.get(id, -1), -1)
        if s < 0:
            continue
        var solid = r.solid(id)
        var at = r.solid_frame(id, solid)
        var profile = r.ref_arg(solid, 0)
        var profile_kind = r.name(profile)
        var found_element = -1
        if r.name(id) == "IFCWALL":
            if profile_kind != "IFCRECTANGLEPROFILEDEF":
                continue
            var centre = r.placement(r.ref_arg(profile, 2))
            var half = r.real_arg(profile, 3) / 2
            var a = at.point(centre.origin - centre.x * half)
            var b = at.point(centre.origin + centre.x * half)
            for e in range(len(building.elements)):
                ref element = building.elements[e]
                if element.kind != WALL or element.storey.value != s:
                    continue
                var frame = building.wall_frame(ElementId(e))
                var p = frame.origin
                var q = frame.point(frame.length, 0, 0)
                var forward = p.distance_to(a) + q.distance_to(b)
                var backward = p.distance_to(b) + q.distance_to(a)
                if min(forward, backward) <= 2 * tol:
                    found_element = e
            file_wall[id] = found_element
        else:
            var closed = profile_kind == "IFCARBITRARYCLOSEDPROFILEDEF"
            if not closed and profile_kind != "IFCARBITRARYPROFILEDEFWITHVOIDS":
                continue
            var outer = _plan_area_and_centroid(
                r.polyline(r.ref_arg(profile, 2), at)
            )
            var top = at.point(Vec3d(0, 0, r.real_arg(solid, 3))).z
            for e in range(len(building.elements)):
                ref element = building.elements[e]
                if element.kind != SLAB and element.kind != ROOF:
                    continue
                var points = building.topology.complex.face_points(
                    element.faces[0]
                )
                var mine = _plan_area_and_centroid(split_bridged(points).outer)
                if abs(points[0].z - top) + mine.distance_to(outer) <= 2 * tol:
                    found_element = e
        var layers = construction_index.get(r.material_of.get(id, -1), -1)
        if found_element >= 0:
            building.elements[found_element].name = r.name_arg(id, 2)
            if layers >= 0:
                building.elements[found_element].construction = ConstructionId(
                    layers
                )
    return file_wall^


def _read_members(
    r: _Reader,
    mut building: Building,
    storey_of: Dict[Int, Int],
    material_index: Dict[Int, Int],
) raises:
    """Add the file's columns and beams, in file order."""
    # A file that reaches this point has a storey, so it has entities.
    for i in range(len(r.f.entities)):  # pragma: no branch
        var id = r.f.entities[i].id
        var kind = r.f.entities[i].name
        if kind != "IFCCOLUMN" and kind != "IFCBEAM":
            continue
        var s = storey_of.get(r.container.get(id, -1), -1)
        if s < 0:
            raise Error("A column or beam must be in a storey")
        var material = material_index.get(r.material_of.get(id, -1), -1)
        if material < 0:
            raise Error("A column or beam needs a material")
        var solid = r.solid(id)
        var at = r.solid_frame(id, solid)
        var section = _section(r, r.ref_arg(solid, 0))
        var tip = at.point(Vec3d(0, 0, r.real_arg(solid, 3)))
        # Exact axis points, when the file has them.
        var exact = r.values(id, "ThreeMojo_Member")
        var start = Point2(
            _get(exact, "StartX", at.origin.x),
            _get(exact, "StartY", at.origin.y),
        )
        var end = Point2(_get(exact, "EndX", tip.x), _get(exact, "EndY", tip.y))
        var element: ElementId
        if kind == "IFCCOLUMN":
            element = building.add_column(
                StoreyId(s), start, section, MaterialId(material)
            )
        else:
            element = building.add_beam(
                StoreyId(s), start, end, section, MaterialId(material)
            )
        building.elements[element.value].name = r.name_arg(id, 2)


def _read_openings(
    r: _Reader, mut building: Building, file_wall: Dict[Int, Int]
) raises:
    """Add the doors and windows of the file's openings."""
    var filler_of = Dict[Int, Int]()
    for rel in r.f.all_of("IFCRELFILLSELEMENT"):
        filler_of[r.ref_arg(rel, 4)] = r.ref_arg(rel, 5)
    for rel in r.f.all_of("IFCRELVOIDSELEMENT"):
        var wall = r.ref_arg(rel, 4)
        var void_id = r.ref_arg(rel, 5)
        var host = file_wall.get(wall, -1)
        var filler = filler_of.get(void_id, -1)
        if host < 0 or filler < 0:
            continue
        var wall_place = r.ref_arg(wall, 5)
        var void_place = r.ref_arg(void_id, 5)
        var height = r.real_arg(filler, 8)
        var width = r.real_arg(filler, 9)
        var wall_frame = r.local(wall_place)
        var opening_frame = r.local(void_place)
        var own = opening_frame.origin - wall_frame.origin
        var offset = own.dot(wall_frame.x)
        var sill = own.dot(wall_frame.z)
        # An opening drawn the other way along the wall starts at its far
        # end.
        if opening_frame.x.dot(wall_frame.x) < 0:
            offset -= width
        if (
            not r.is_unset(void_place, 0)
            and r.ref_arg(void_place, 0) == wall_place
        ):
            # Placed in the wall's own frame: read the numbers as written.
            var written = r.placement(r.ref_arg(void_place, 1)).origin
            offset = written.x
            sill = written.z
        var model_frame = building.wall_frame(ElementId(host))
        if model_frame.along.dot(wall_frame.x) < 0:
            offset = model_frame.length - offset - width
        var kind = DOOR
        var glazing = Optional[Glazing](None)
        if r.name(filler) == "IFCWINDOW":
            kind = WINDOW
            var common = r.values(filler, "Pset_WindowCommon")
            var glass_type = r.values(filler, "Pset_DoorWindowGlazingType")
            glazing = Glazing(
                ThermalTransmittance64(
                    _get(common, "ThermalTransmittance", 1.6)
                ),
                _get(glass_type, "SolarHeatGainTransmittance", 0.4),
                _get(glass_type, "VisibleLightTransmittance", 0.7),
            )
        var opening = building.add_opening(
            kind,
            ElementId(host),
            Length64(offset, METER),
            Length64(sill, METER),
            Length64(width, METER),
            Length64(height, METER),
            glazing,
        )
        building.openings[opening.value].name = r.name_arg(filler, 2)


def _section(r: _Reader, profile: Int) raises -> Section:
    """Return the section of a column or beam profile."""
    var kind = r.name(profile)
    var zero = Length64(0, METER)
    if kind == "IFCRECTANGLEPROFILEDEF":
        return Section(
            RECTANGLE,
            Length64(r.real_arg(profile, 3), METER),
            Length64(r.real_arg(profile, 4), METER),
            zero,
            zero,
        )
    if kind == "IFCISHAPEPROFILEDEF":
        return Section(
            I_SHAPE,
            Length64(r.real_arg(profile, 3), METER),
            Length64(r.real_arg(profile, 4), METER),
            Length64(r.real_arg(profile, 6), METER),
            Length64(r.real_arg(profile, 5), METER),
        )
    if kind == "IFCCIRCLEPROFILEDEF":
        return Section(
            CIRCLE,
            Length64(2 * r.real_arg(profile, 3), METER),
            zero,
            zero,
            zero,
        )
    raise Error(String("Unsupported member profile ", kind))


def _read_furniture(
    r: _Reader,
    mut building: Building,
    file_spaces: List[Int],
    storey_of: Dict[Int, Int],
) raises:
    """Add the file's furniture to the spaces that contain it."""
    # Model spaces are in cell order: by storey, then in file order.
    var model_space = Dict[Int, Int]()
    var counts = List[Int]()
    for _ in range(len(storey_of)):
        counts.append(0)
    var firsts = List[Int]()
    var running = 0
    for s in range(len(building.storeys)):
        firsts.append(running)
        for sp in range(len(building.spaces)):
            if building.spaces[sp].storey.value == s:
                running += 1
    for i in range(len(file_spaces)):
        var s = storey_of[r.parent_of[file_spaces[i]]]
        model_space[file_spaces[i]] = firsts[s] + counts[s]
        counts[s] += 1
    for id in r.f.all_of("IFCFURNITURE"):
        var space = model_space.get(r.container.get(id, -1), -1)
        if space < 0:
            continue
        var solid = r.solid(id)
        var at = r.solid_frame(id, solid)
        var profile = r.ref_arg(solid, 0)
        if r.name(profile) != "IFCRECTANGLEPROFILEDEF":
            continue
        var kind = FurnitureKind(-1)
        var type_name = r.name_arg(id, 4).lower()
        for k in range(13):  # pragma: no branch
            if FurnitureKind(k).name() == type_name:
                kind = FurnitureKind(k)
        if not kind.is_valid():
            continue
        var exact = r.values(id, "ThreeMojo_Furnishing")
        var center = Point2(
            _get(exact, "CenterX", at.origin.x),
            _get(exact, "CenterY", at.origin.y),
        )
        var rotation = _get(exact, "Rotation", atan2(at.x.y, at.x.x))
        var furnishing = building.add_furnishing(
            kind,
            SpaceId(space),
            center,
            Angle64(rotation, RADIAN),
            Length64(r.real_arg(profile, 3), METER),
            Length64(r.real_arg(profile, 4), METER),
            Length64(r.real_arg(solid, 3), METER),
        )
        building.furnishings[furnishing.value].name = r.name_arg(id, 2)
