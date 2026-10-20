# Scan parts

`extensions/scan/parts.mojo` cuts a scanned place into parts: the pieces that stand apart from the ground. Each part can be measured, weighed, stood in a physics world, and copied into another scene as splats. `extensions/scan/terrain.mojo` finds the ground, also on a slope.

![A hillside site of splats with a hall and a tower, drawn with levels of detail, and a copy of the hall beside it](out/scan-parts.png)

The picture comes from `examples/scan_parts.mojo`. With no scan, the example makes a site of 66,356 splats. It is a hillside 60 m on a side, with a hall and a tower on it. The second hall is part 0 of the scan, copied out of the scan and placed again beside it. The example draws both with [levels of detail](Splat-level-of-detail), at about 300 frames a second on four cores.

Give the example the id of a cached scan, or the path of a scan file, to cut that scan.

## The site

The example uses half-meter voxels, and finds the hillside's ground as a surface. It cuts two parts and weighs them as concrete shells:

| Part | Size | Voxels | Mass | Bearing pressure | Tip angle |
|---|---|---|---|---|---|
| 0, the hall | 12.5 m by 10.5 m by 7 m | 1,578 | 473 t | 211 kPa on 22 m^2 | 49 degrees |
| 1, the tower | 4.5 m by 4.5 m by 12.5 m | 840 | 252 t | 309 kPa on 8 m^2 | 18.5 degrees |

Each wall of the hall stands on the slope where it is, so the hall bears on all of its walls. As a rigid body on its bed, the hall settles 2 cm in the first second and then stands still. Its 7,396 splats make the copy.

## Cut a grid into parts

```mojo
var grid = occupancy_grid(splats, frame, options, region)
var ground = terrain_ground(
    grid, TerrainOptions(Length64(2, METER), Area64(2000, SQUARE_METER))
)
var parts = scan_parts_on(grid, ground, 20)
var largest = parts.parts[0]                 # the most voxels
var box = largest.region(grid)               # a ScanRegion, in meters
```

A part is a set of solid voxels above the ground that touch each other through a face. A voxel in its column's ground layer, or below it, is ground. A set of fewer than `min_voxels` voxels is a floater of the scan, and is no part. `parts.labels` gives each voxel's part, or -1 for the ground, empty space and floaters. The parts are in order of size, the largest first.

`scan_parts(grid, PartOptions(layer, min_voxels))` cuts the parts above one layer, such as the floor that `detect_levels` finds in a room. Layer -1 counts no voxel as ground.

## Find the ground of a slope

A room has a flat floor, and `detect_levels` finds it as one layer. A hillside has no flat layer: its ground slopes. `terrain_ground` finds the ground as a surface, a layer for each plan column:

1. The top of a column is its highest solid voxel.
2. Two columns side by side are on one surface when their tops differ by `step` or less. A wall is a larger step, so the roof of a building is a surface of its own.
3. A surface whose plan area is `min_area` or more is ground. A roof is smaller than that, and a hillside is larger.
4. A column of the ground keeps its top. Each other column takes its height from the nearest columns of the ground: the lowest of them. So the ground goes on under a building, at the foot of its lowest wall.

| Option | Meaning |
|---|---|
| `step` | The most that the tops of two columns side by side on one surface differ by. 2 m keeps a slope of up to 63 degrees, and parts a wall. |
| `min_area` | The least plan area of a surface that is ground. Make it more than the largest roof, and less than the hillside. |

| Function | What it gives |
|---|---|
| `terrain_ground` | The ground as a `GroundSurface`, from a grid and `TerrainOptions` |
| `flat_ground` | A ground at one layer, with no tolerance |
| `column_tops` | The highest solid voxel of each column |
| `ground_grid` | The ground as a grid: each column solid up to its layer |

The scan does not see the ground under a building. So the foot of a wall on a slope can be a layer or two above the height that its column takes. A ground surface has a tolerance: the whole layers in one step. A foot that close to the ground bears on it.

## Geometry

| Function | What it gives |
|---|---|
| `ScanPart.count`, `region`, `volume` | The voxels, their box in meters and their volume |
| `part_area` | The area of the faces that face something other than the part |
| `part_grid` | The part alone, as an `OccupancyGrid` of its own box |
| `part_hull` | The corners of a convex hull of the part |

`part_grid` gives a grid that every reader of a grid reads. `collision_triangles(part_grid(...))` is the part's mesh, and `add_scan_collider` makes it a static collider of its own.

`part_hull` takes, along each of 124 directions, the voxel corner that reaches furthest. Their hull holds every face of the part's box and of its 45 degree cuts. It is a little inside the convex hull of every voxel.

## Engineering

```mojo
var kit = construction_kit(CONCRETE_KIT)
var mass = part_mass(grid, parts, 0, kit.materials[0].density, PART_SHELL)
var footing = part_footing(grid, parts, 0, mass, gravity)
```

`part_mass` weighs a part at a density. Each voxel is a cube of that density. It gives the mass, the center of mass in building coordinates, and the inertia tensor about that center. The inertia adds each cube's own inertia, `m a^2 / 6` about each axis for an edge `a`. So a part of whole voxels has the exact inertia of the solid it fills.

A scan sees surfaces, so the fill must be chosen:

| Fill | What is weighed | Use it for |
|---|---|---|
| `PART_SHELL` | The solid voxels alone: a shell one voxel thick | A building, whose inside is air |
| `PART_SOLID` | The solid voxels and the voxels they enclose | A solid object, such as a rock, a pier or a statue |

A shell's mass is right when its walls are about one voxel thick. When they are not, scale it by the wall thickness over the voxel edge. A 1 m voxel over 0.3 m walls weighs the walls about three times over.

`part_footing` takes the weight down to the ground. The foot of a column of a part is its lowest voxel in that column. The part bears on each foot that is one layer above its column's ground layer, or higher by no more than the ground's tolerance. A part that touches no ground bears on its lowest layer.

| Field | Meaning |
|---|---|
| `base` | The lowest layer of the feet it bears on |
| `area` | The plan area of those feet |
| `pressure` | The weight over that area |
| `margin` | How far the center of mass's plan point is inside the edge of the feet's convex hull. It is negative outside it. |
| `tip` | How far the part can lean before its center of mass passes that edge. The height is from the lowest foot. |

`stands()` is True when the margin is above zero. A part whose center of mass is outside its base, such as a cantilever without its support, does not stand.

## Physics

`part_body` makes a part a dynamic `RigidBody` of its mass. The body's origin is the part's center of mass, and its shape is the convex hull of `part_hull`. `extensions.physics` gives a convex shape the center and inertia of a solid of one density, so the body's center and inertia are the hull's.

```mojo
var body = world.add_body(part_body(grid, parts, 0, mass, material))
_ = add_scan_collider(world, part_bed(grid, parts, 0, mass), material)
```

A convex body cannot stand on rough ground, because its hull holds some of that ground. `part_bed` gives the ground of `ground_grid`, less each voxel that the hull overlaps. The body rests where its hull meets the ground, as in a pit cut to fit it. On the whole ground of the test slope, the hull is pushed out of the ground. On its bed, it moves less than 1 mm.

`tests/test_scan_parts.mojo` checks the tip angle in a physics world. A pillar 1 m by 1 m by 5 m has a tip angle of 11.3 degrees. Leaned up to 11 degrees on its edge and let go, it falls back. Leaned 12 degrees or more, it falls over.

## Use a part again

```mojo
var copy = part_splats(splats, frame, grid, parts, 0, 1)
var node = scene.add(placed)                 # any position and turn
var again = GaussianSplat(copy^, node)
```

`part_splats` copies the splats of a part out of the scan, with their covariances, colors and harmonics bytes, in the scan's coordinates. A splat is the part's when a voxel of the part is within `reach` voxels of the voxel that holds its center. A node of its own places the copy anywhere, in this scene or another. The renderer evaluates the harmonics in the node's own space, so the view-dependent colors turn with the node.

The construction kits are the other reusable half: a part of a scanned concrete building and a generated concrete block share the concrete kit. See [Construction kits](Construction-kits).

## Limits

- Faces join voxels; edges and corners do not. Two parts that touch only at an edge are two parts.
- A part that stands on another part, such as a dome on a drum, is one part with it.
- A roof that joins the ground in small steps, as on a building built into a slope, is ground.
- Under a building, the ground is the lowest of the nearest ground. On a slope, the part can take in some ground on its upper side.
- The mass is only as good as the scan's scale and the kit's density. A scale error of a factor `s` changes the mass by `s^3`.
- The body's center and inertia are the hull's, not the voxels'.
