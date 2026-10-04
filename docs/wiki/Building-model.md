# Building model

`extensions/building/` holds one canonical model of a building. The render view, the structural view, the thermal view and IFC exchange all read it. A `Building` holds storeys, spaces, elements, openings, materials and constructions over one [cell complex](Building-topology).

![A two-storey building, cut away above its ground floor, turns under a lamp](out/building-model.png)

Coordinates are meters, z up. The x axis points east and the y axis points north, unless `Site.north` turns true north.

## Modules

| Module | What it gives |
|---|---|
| `ids` | `StoreyId`, `SpaceId`, `ElementId`, `OpeningId`, `MaterialId` and `ConstructionId` |
| `kinds` | `ElementKind`, `OpeningKind`, `SpaceUse` and `SectionShape` |
| `material` | `BuildingMaterial`, `Look` and the library: `concrete`, `steel`, `timber`, `brick`, `gypsum_board`, `mineral_wool`, `glass` and `aluminum` |
| `construction` | `Construction`, `Layer`, `Glazing`, `FlowDirection` and the ISO 6946 film resistances |
| `model` | `Building`, `assemble`, `Site`, `Storey`, `Space`, `Element`, `Opening`, `Section`, `WallFrame`, `SpacePlan`, `StoreyPlan` and `ConstructionSet` |
| `fingerprint` | `fingerprint`, a 64-bit hash of the model's content |
| `views/render` | `add_building`, which adds meshes to a scene |
| `ifc` | [IFC exchange](IFC-exchange) |

## Assemble a model

Give the storey plans, the materials, the constructions and the construction for each kind of face. `assemble` builds the cell complex. It makes one space per plan polygon, one wall element per wall face and one slab or roof element per horizontal face.

```mojo
var plans = List[StoreyPlan]()
var ground = List[SpacePlan]()
ground.append(SpacePlan("office", OFFICE, [Point2(0, 0), Point2(6, 0), Point2(6, 5), Point2(0, 5)]))
plans.append(StoreyPlan("ground", Length64(3.5, METER), ground^))
var building = assemble(
    "office", site, Length64(0, METER), plans, materials^, constructions^,
    ConstructionSet(exterior, partition, ground_slab, floor, roof),
    Length64(1e-6, METER),
)
```

| Face | Element | Construction |
|---|---|---|
| Wall with the outside on one side | `WALL` | `exterior_wall` |
| Wall between two spaces | `WALL` | `interior_wall` |
| Floor of the first storey | `SLAB` | `ground_slab` |
| Floor between two spaces, or under an overhang | `SLAB` | `floor` |
| Face with the outside above it | `ROOF` | `roof` |

Then add frame members and openings:

| Method | Adds |
|---|---|
| `add_column(storey, at, section, material)` | A column from the storey's floor to the floor above. Its depth runs along x. |
| `add_beam(storey, start, end, section, material)` | A beam whose axis lies at the top of the storey |
| `add_opening(kind, wall, offset, sill, width, height, glazing)` | A door or a window in a wall, placed in the wall's frame |

`add_opening` refuses an opening that does not fit its wall, overlaps another opening, or is a door that does not start at the floor. A window needs a `Glazing`.

## Read the model

| Method | Returns |
|---|---|
| `floor_area(space)`, `volume(space)` | The area and volume of a space |
| `gross_floor_area()` | The sum of the floor areas |
| `space_neighbors(space)` | The spaces that share a face with a space |
| `elements_of_space(space)` | The walls, slabs and roofs that bound a space |
| `element_of_face(face)` | The element on a face of the complex |
| `openings_of(wall)` | The doors and windows in a wall |
| `wall_frame(wall)` | The wall's base start, its directions and its size |
| `is_exterior(element)` | Whether an element has the outside on one side |
| `validate()` | Nothing. It raises if a part does not agree with the others. |

## Materials and constructions

A `BuildingMaterial` holds a density, an elastic modulus, Poisson's ratio, a strength, a thermal conductivity, a specific heat, a thermal expansion and a `Look`. A structural solver, a thermal solver and a renderer each read the same material. The library values are typical values from ISO 10456 and the Eurocodes. They are not design values.

A `Construction` is a list of layers from the outside face to the inside face. `u_value(materials, direction)` gives the thermal transmittance by ISO 6946. It adds the layer resistances and the two surface films:

| Direction | Inside film, m² K/W | Outside film, m² K/W |
|---|---|---|
| `HORIZONTAL_FLOW`, a wall | 0.13 | 0.04 |
| `UPWARD_FLOW`, a roof | 0.10 | 0.04 |
| `DOWNWARD_FLOW`, a floor | 0.17 | 0.04 |

`heat_capacity_per_area(materials)` gives the heat that one square meter stores per kelvin.

A `Glazing` is a window unit by the simple glazing model: a U-value, a solar heat gain coefficient and a visible transmittance.

## Frame sections

A `Section` is a rectangle, a doubly symmetric I or a circle. It gives the area, the two second moments of area and Saint-Venant's torsion constant. The torsion constant of a rectangle comes from a series that is within 0.2% of the exact value. The torsion constant of an I adds its plates, b t³ / 3 each.

## Render the model

`add_building(scene, assets, building, options)` adds one node for the building and one mesh per storey and look under it. It returns the node and the counts of meshes and triangles.

| Option | Effect |
|---|---|
| `RenderOptions(FULL, -1)` | Every element, with doors and windows cut through their walls |
| `RenderOptions(MASSING, -1)` | Exterior walls, roofs and exposed slabs only, with flush window panes |
| `RenderOptions(FULL, k)` | Storeys up to `k` only, for a cutaway |

Each vertex carries an `elementId` attribute: the element index, or the opening index plus the element count. The building node's user data records `model`, `fingerprint`, `detail`, `topStorey` and `dropped`. A game can compare the fingerprint with the model's fingerprint to tell whether a baked mesh is current.

The model is z up and the scene is y up. A model point (x, y, z) is the scene point (x, z, -y).

## Limits

- A wall is drawn centered on its face, and extended by half its thickness at each end. Walls overlap at corners, and the inside layer can show in a thin seam at an outside corner.
- The render view draws a construction's outside and inside layers on the two faces of a wall. It does not draw the layers between them.
- A beam is drawn below its axis. A column is drawn as a box or a cylinder; an I-section is drawn as its bounding box.
- The model has no stairs, ramps, curtain-wall mullions or sloped roofs.
- Element names come from their kind and index. Renaming them changes the fingerprint.

See [Why buildings have one canonical model](Why-buildings-have-one-canonical-model).
