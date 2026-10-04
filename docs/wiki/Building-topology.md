# Building topology

`extensions/topology/` builds a cell complex from storey plans. Each room is a cell. Two rooms that share a wall share one face, and a floor is one face with a room above and a room below. The building model, the structural view and the thermal view read adjacency from this complex.

## Modules

| Module | What it gives |
|---|---|
| `ids` | `VertexId`, `EdgeId`, `FaceId`, `CellId` and `RegionId` |
| `weld` | `Welder`, which merges points within a tolerance |
| `arrangement` | `Point2`, `Region`, `arrange` and the polygon helpers `polygon_area` and `contains` |
| `complex` | `CellComplex`, `Face`, `Edge` and `FaceKind` |
| `storeys` | `build_storeys` and `StoreyComplex` |

Coordinates are in meters, z up. A plan point (x, y) lies at height z.

## Build a complex from plans

Give one plan per storey and one more level than storeys. A plan is a list of `Region` values on layer zero. Each region has an id that is unique on its storey.

```mojo
var ground = List[Region]()
ground.append(Region(0, RegionId(0), [Point2(0, 0), Point2(4, 0), Point2(4, 4), Point2(0, 4)]))
ground.append(Region(0, RegionId(1), [Point2(4, 0), Point2(8, 0), Point2(8, 4), Point2(4, 4)]))
var plans = List[List[Region]]()
plans.append(ground^)
var levels = [Length64(0, METER), Length64(3, METER)]
var built = build_storeys(levels, plans, Length64(1e-6, METER))
built.complex.validate()
var room = built.cell_of(0, RegionId(0)).value()
```

`build_storeys` makes these faces:

| Face | Source | Sides |
|---|---|---|
| Wall | Each plan edge with different regions on its two sides | The two rooms, or a room and the outside |
| Floor | Each face of the overlay of a plan on the plan below | The room below and the room above |
| Ground | Each face of the first plan | The outside below, the room above |
| Roof | Each face of the last plan, and each part of a lower plan with nothing above | The room below, the outside above |

A plan can differ from the plan below it. The overlay splits each floor where the two plans cross. A vertex of one plan that lies on an edge of the other splits the wall along that edge too, so every cell is closed.

## Query the complex

| Method | Returns |
|---|---|
| `faces_of(cell)` | The faces that bound a cell |
| `other_side(face, cell)` | The cell across a face, or None for the outside |
| `neighbors(cell)` | The cells that share a face with a cell, once each |
| `shared_faces(a, b)` | The faces between two cells |
| `exterior_faces(cell)` | The faces of a cell with the outside across them |
| `face_area(face)`, `face_normal(face)`, `face_centroid(face)` | The area, the unit normal toward the positive side, and the mean corner |
| `outward_normal(face, cell)` | The unit normal that points out of a cell |
| `cell_volume(cell)` | The volume, by the divergence theorem |
| `validate()` | Nothing. It raises if a cell is not closed. |

Each face has a `kind`: `VERTICAL` for a wall or `HORIZONTAL` for a floor, a ground or a roof. `StoreyComplex.face_level` gives each wall's storey and each horizontal face's level. Level i is the bottom of storey i.

A face's loop winds counterclockwise seen from its positive side. The `positive` cell is on the side the normal points to. The `negative` cell is behind the face.

## Arrange polygons in a plane

`arrange(regions, layers, tolerance)` cuts the plane by the edges of every region. It splits edges where they cross, where an end touches another edge, and where two edges overlap. It returns the vertices, the edges with the face on each side, and the bounded faces.

Each bounded face has one label per layer: the region that covers it, or `NO_REGION`. Regions of one layer must not overlap. Regions of different layers can overlap. `build_storeys` uses two layers for each floor: the plan below and the plan above.

A component inside a face of another component gets a bridge edge. The bridge joins the inner component's leftmost corner to the nearest corner it can see. The face then has one loop that runs along the bridge in both directions. A smaller crown above a shaft makes such a face.

## Errors

| Case | Function |
|---|---|
| A region has fewer than three corners, a short edge, no area, or crosses or touches itself | `arrange`, `build_storeys` |
| Two regions of one layer overlap | `arrange`, `build_storeys` |
| A region id repeats on a storey | `build_storeys` |
| The levels do not increase, or their count is not one more than the storeys | `build_storeys` |
| A face has fewer than three corners, repeats a corner, or has one cell on both sides | `CellComplex.add_face` |
| An id is out of range | Every `CellComplex` query |

## Limits

- Cells are prisms between two levels. A sloped roof or a double-height room that spans storeys is not a cell of this complex.
- A plan region is a simple polygon. A room with a hole in it is not supported. A region can stand inside an uncovered court.
- The arrangement compares every pair of edges. A plan with thousands of edges is slow.
- Points closer than the tolerance are one point. Keep features of a plan larger than the tolerance.

## References

- de Berg, Cheong, van Kreveld and Overmars, "Computational Geometry: Algorithms and Applications", 3rd edition, 2008, chapter 2.
- O'Rourke, "Computational Geometry in C", 2nd edition, 1998, section 1.6.
- Aish and Pratap, "Spatial information modeling of buildings using non-manifold topology with ASM and DesignScript", 2013.
