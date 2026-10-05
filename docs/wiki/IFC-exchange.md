# IFC exchange

`extensions/building/ifc/` writes the [building model](Building-model) as an IFC4 STEP file and reads one back. The round-trip tests compare model fields directly and check the fingerprint. They cover the site, names, storeys, spaces, elements, openings, furniture, materials, constructions and rebuilt topology.

![A small tower read back from its IFC file, cut away above its first storey, turns under a lamp](out/ifc-exchange.png)

## Modules

| Module | What it gives |
|---|---|
| `step` | `StepFile`, `StepValue`, `StepEntity`, `StepKind`, `parse`, `format_real` and `encode_string`: the physical file of ISO 10303-21 |
| `ifc4` | `write_ifc`, `read_ifc` and `ifc_guid` |

## Write and read a file

```mojo
var text = write_ifc(building, "2026-01-01T00:00:00")
Path("office.ifc").write_text(text)
var back = read_ifc(text, Length64(1e-6, METER))
```

`write_ifc` validates the model first. The time stamp goes into the header. A fixed time stamp gives the same file for the same model. Each GlobalId comes from the model's fingerprint and a counter, so the ids are stable too.

`read_ifc` rebuilds the cell complex from the space outlines with `assemble`. It then gives each wall and slab the name and construction of the file element at the same place. It adds the columns, beams, doors, windows and furniture with their names.

## What is written

| Model | IFC4 |
|---|---|
| Units | `IfcSIUnit`: metre, square metre, cubic metre and radian |
| Site | `IfcSite` with its latitude, longitude and elevation, and true north in the context |
| Building and storeys | `IfcBuilding`, `IfcBuildingStorey` with its elevation, and a `GrossHeight` quantity |
| Space | `IfcSpace`: an extruded polygon, with its use as the object type |
| Wall | `IfcWall`: an extruded rectangle in the wall's frame |
| Slab and roof | `IfcSlab` with `FLOOR` or `ROOF`: an extruded polygon, with voids where the face has holes |
| Column and beam | `IfcColumn` and `IfcBeam`: an extruded rectangle, I-shape or circle profile |
| Opening | `IfcOpeningElement`, `IfcRelVoidsElement` and `IfcRelFillsElement` |
| Door and window | `IfcDoor` and `IfcWindow` with their overall sizes |
| Glazing | `Pset_WindowCommon` and `Pset_DoorWindowGlazingType` |
| Furniture | `IfcFurniture` in its space: an extruded rectangle, with its kind as the object type |
| Material | `IfcMaterial` with `Pset_MaterialCommon`, `Pset_MaterialMechanical` and `Pset_MaterialThermal` |
| Construction | `IfcMaterialLayerSet`, associated with each wall and slab |
| Containment | `IfcRelAggregates` and `IfcRelContainedInSpatialStructure` |

Beams hang below their axes. A circular beam profile is offset by half its diameter. Rectangle and I-shape profiles are offset by half their depth.

Four property sets keep values that IFC4 has no exact place for. `ThreeMojo_Material` keeps the strength and the look. `ThreeMojo_Member` keeps the exact plan points of a column or beam axis. `ThreeMojo_Furnishing` keeps the exact center and rotation of a piece of furniture. `ThreeMojo_Site` keeps the exact latitude, longitude and north angle. A reader that does not know them ignores them.

## Read a file from another program

`read_ifc` reads a file when its spaces are extruded polygons on storeys. It follows placement chains, including unset axes and 2D profile placements. It checks each local placement reference and refuses a cycle. Traversal is iterative and bounded by the number of entities in the file.

| Missing in the file | What the reader does |
|---|---|
| A storey's gross height | It uses the gap to the next storey, or the depth of the storey's spaces. |
| A storey's elevation | It uses the storey's placement. |
| A material's properties | It uses the library material that the name suggests: steel, timber, brick, gypsum, insulation, glass or aluminum. Any other name gives concrete. |
| A space's use | It uses `OFFICE`. |
| A material layer set | It makes one concrete construction, 0.2 m thick. |
| A window's glazing | It uses 1.6 W/(m² K), a solar heat gain coefficient of 0.4 and a visible transmittance of 0.7. |

A wall or slab that matches no face of the rebuilt complex keeps the first construction. An opening in such a wall is skipped. The reader skips a piece of furniture that is not in a space or has no rectangle profile. It also skips one whose object type is not a furniture kind.

## STEP files

`parse` reads a physical file. It refuses malformed text and gives the line of the error. `StepFile.write` writes it back. A real is written with the shortest digits that read back to the same number. A string escapes every character outside printable ASCII as `\X2\` or `\X4\`.

STEP value nesting is limited to 256 containers. Lists and typed values share this limit. The outer attribute list of each header entry or entity counts as one container. The parser raises an `Error` with the line number before it descends past this limit. The limit applies independently to each attribute path.

## Errors

| Case | Function |
|---|---|
| The text is not a well-formed STEP file | `parse`, `read_ifc` |
| A STEP value exceeds 256 nested containers, including its outer attribute list | `parse`, `read_ifc` |
| The schema is not IFC4 | `read_ifc` |
| The project or its unit assignment is missing or ambiguous | `read_ifc` |
| The assigned length unit is missing, repeated, prefixed, conversion-based or not meters | `read_ifc` |
| A local placement chain contains a cycle or a reference of the wrong kind | `read_ifc` |
| A space is not on a storey, or its profile is not a closed polyline | `read_ifc` |
| A column or beam is not on a storey, has no material, or has an unknown profile | `read_ifc` |
| A product has no extruded solid, or a profile curve is not a polyline | `read_ifc` |
| The model does not validate | `write_ifc`, `read_ifc` |

## Limits

- The reader supports only extruded solids. It does not read boundary representations, Boolean results, swept disks or mapped items.
- The reader rebuilds walls and slabs from spaces. A wall with no space on either side is not read.
- The file must have one project with one assigned length unit: unprefixed meters. The reader follows `IfcProject.UnitsInContext` to its `IfcUnitAssignment`. It does not convert feet or other length units. Unassigned units and units for other quantities do not change this check.
- Exact round trips apply to the supported order and layout made by `assemble` and `add_*`, with the section fields used by its shape. The file preserves customized names, site values, materials and glazing. It does not preserve arbitrary collection reordering or unused extra struct fields.
- The reader rebuilds topology with the supplied tolerance. Use the original model tolerance for an exact topology round trip. An empty model without constructions receives the documented default construction.
- The look of a material leaves IFC only through `ThreeMojo_Material`. The file has no `IfcSurfaceStyle`.
- The writer writes the Reference View subset of entities that this table lists. It is not a certified IFC exporter.

The mapping follows the IFC4 schema of buildingSMART International, published as ISO 16739-1:2018.
