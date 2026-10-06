# Procedural towers

`extensions/building/generate/tower.mojo` turns a seed into a tower as a canonical [building model](Building-model). The tower has storeys, rooms, doors, windows, a concrete frame and furniture. A game can render it, and an engineer can analyze its frame and its energy use.

![A seeded tower with a set-back crown turns under a lamp](out/procedural-towers.png)

## Generate a tower

```mojo
var parameters = SkyscraperParameters()
parameters.seed = 35
parameters.total_height = Length(60, METER)
var tower = generate_tower(TowerOptions(parameters^))
```

`generate_tower` reads the seeded style of the procedural skyscraper in `generators/skyscraper.mojo`. The style gives the footprint with its cut corner, the floor height, the bay width and the window height. It also gives the shares of the base and the crown, and the crown's setback. The skyscraper generator itself is unchanged. It still makes its three.js mesh.

| Option | Default | Effect |
|---|---|---|
| `parameters` | The argument | The skyscraper seed and style |
| `shaft` | `OFFICE_FLOOR` | The program of the shaft's storeys: `OFFICE_FLOOR` or `RESIDENTIAL_FLOOR` |
| `plan` | `default_plan_options()` | The corridor width, room widths and core length |
| `furnished` | True | Add furniture with `furnish` |
| `frame` | True | Add columns and beams |

The same options give the same tower. The model's fingerprint is the same each time.

## What it builds

| Part | How |
|---|---|
| Storeys | The total height divided by the floor height, rounded |
| Tiers | The base takes the base share of the storeys and the crown takes the crown share. The shaft takes the rest. |
| Footprints | The skyscraper's footprint. The crown's footprint is set back by the setback depth times the bay width on every side. |
| Floor plans | The first storey is a lobby with shops. The rest of the base and the crown are offices. The shaft has the `shaft` program. Storeys of one tier share one plan from [floor plans](Floor-plans-and-interiors). |
| Constructions | A terracotta wall in the skyscraper's seeded color, gypsum partitions, concrete slabs and an insulated roof |
| Windows | One per bay in every outside wall, at the skyscraper's window height |
| Doors | One per room, and a double entrance to the lobby |
| Frame | 0.5 m concrete columns on one grid for every storey, joined by 0.4 m by 0.6 m beams |
| Furniture | By the rules of [floor plans and interiors](Floor-plans-and-interiors) |

A crown footprint too small for a plan keeps the shaft's footprint, with no setback.

## The column grid

The grid has four lines along the footprint's longest edge: 0.5 m inside each long side, and on each edge of the corridor. Along each line, the columns stand every three bays. A storey gets the columns that stand 0.3 m inside its footprint. Each column gets a beam to the next column along its line and to the column on the next line.

The crown's columns stand on the shaft's columns, because both come from one grid. The [structural view](Frame-analysis) can then carry the crown's loads to the ground.

## Use the tower

```mojo
var scene = Scene()
var assets = Assets()
_ = add_building(scene, assets, tower, RenderOptions(FULL, 3))   # a cutaway
var text = write_ifc(tower, "2026-01-01T00:00:00")               # an IFC file
var frame = structural_view(tower, default_options())            # a frame model
var zones = thermal_view(tower, default_thermal_options(), [])   # a thermal model
```

A 33-storey tower has about 600 rooms, 4,500 elements, 2,900 openings and 5,700 pieces of furniture. On one core it generates in about a quarter of a second.

## Limits

- The footprint is the skyscraper's: a rectangle with one cut corner. The tower has one setback.
- Every storey of a tier has the same plan.
- There are no stairs or lifts as geometry. The core rooms stand for them.
- The frame sizes are fixed. They are not designed for the tower's loads.
- The shaft's program applies to every shaft storey.
