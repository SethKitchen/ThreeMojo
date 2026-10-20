# Scanned buildings

`extensions/scan/` and `extensions/building/scan/` turn a Gaussian splat scan of a real building into a canonical building model with a static collider. They also cut it into [parts](Scan-parts) to weigh, simulate and use again. The model has storeys, walls, slabs and a roof of a reusable [construction kit](Construction-kits). The structural, [bearing](Bearing-walls), thermal and render views and the IFC writer then read the scan as they read a procedural tower. `tools/building_scans.mojo` downloads the scans, from SuperSplat and from any other URL, because they are too large for git.

![A building model fitted to a scan of a two-storey room, turning](out/scanned-buildings.png)

The picture comes from `examples/building_scan.mojo` with no scan argument: a scan of a two-storey room that the example makes. Give it the id of a cached scan to fit that scan.

![A hillside site of splats with a hall and a tower, drawn with levels of detail, and a copy of the hall beside it](out/scan-parts.png)

`examples/scan_parts.mojo` finds the ground of a scanned site, cuts the scan into [parts](Scan-parts) and weighs them. It stands the largest part on its bed in a physics world. Then it draws the scan on every core, with [levels of detail](Splat-level-of-detail), and a copy of the part beside it. With no scan, it makes a hillside site with a hall and a tower. The C ABI's splat app draws a scan on a GPU; see [C ABI and hosts](C-ABI-and-hosts).

## The scans

| Id | Place | Source |
|---|---|---|
| `reading-room` | A reading room | SuperSplat scene `9d370db9` |
| `studio-11` | A studio apartment, made in Unreal Engine 5 | SuperSplat scene `c37cb759` |

The SuperSplat scenes are not pinned yet: their scene pages could not be read from where the manifest was made. Pin one with `building_scans fetch ID --pin` on a machine that can reach `superspl.at`. To add another scan, see [How to add a scanned building](How-to-add-a-scanned-building).

## Modules

| Module | What it gives |
|---|---|
| `scan/scene` | `ScanScene`, `SplatModel` and `splat_model_from_comments` |
| `scan/files` | `read_scan`, `parse_scan`, `scan_format` and `ScanFormat`; see [Compressed PLY files](Compressed-PLY-files#scan-files) |
| `scan/sog` | `read_sog`, `parse_sog` and `parse_sog_bundle`; see [SOG files](SOG-files) |
| `scan/compressed_ply` | `read_compressed_ply`, `parse_compressed_ply` and `is_compressed_ply`; see [Compressed PLY files](Compressed-PLY-files) |
| `scan/parts` | `scan_parts`, `scan_parts_on`, `part_mass`, `part_footing`, `part_body`, `part_bed` and `part_splats`; see [Scan parts](Scan-parts) |
| `scan/terrain` | `terrain_ground`, `TerrainOptions`, `GroundSurface`, `flat_ground` and `ground_grid`; see [Scan parts](Scan-parts#find-the-ground-of-a-slope) |
| `scan/frame` | `ScanFrame`, `ScanAxis`, `ScaleSource`, `supersplat_frame`, `estimate_heading` and `AxisMap` |
| `scan/occupancy` | `OccupancyGrid`, `OccupancyOptions`, `ScanRegion`, `trimmed_region` and `occupancy_grid` |
| `scan/colliders` | `collision_triangles`, `scan_collider` and `add_scan_collider` |
| `building/scan/levels` | `detect_levels`, `ScanLevels`, `LevelOptions` and `is_floor_face` |
| `building/scan/fit` | `fit_building`, `ScanFit` and `ScanFitOptions` |
| `building/scan/catalog` | `ScanCatalog`, `ScanEntry` and `space_use` |
| `building/kits` | `construction_kit` and `KitKind`; see [Construction kits](Construction-kits) |
| `building/views/bearing` | `bearing_check` and `element_mass`; see [Bearing walls](Bearing-walls) |

## Fit a scan

Read the splats and the frame. Turn the frame by the walls' heading. Fill a grid, find the levels and fit the model.

```mojo
var catalog = ScanCatalog.open(CATALOG_MANIFEST, CATALOG_CACHE)
var entry = catalog.find("studio-11")
var splats = read_scan(catalog.scene("studio-11").value()).geometry.copy()
var frame = entry.frame
frame.heading = estimate_heading(splats, frame)
var options = default_occupancy_options()
var region = trimmed_region(splats, frame, options)
var grid = occupancy_grid(splats, frame, options, region)
var levels = detect_levels(grid, default_level_options())
var fit = fit_building(
    grid,
    levels,
    construction_kit(entry.kit),
    frame.scale,
    ScanFitOptions("studio", site, entry.use, 0.01, default_level_options()),
)
var check = bearing_check(fit.building, default_bearing_options())
```

`fit.notes` says what a reader must know before using a number from the model. Read them. `fit.fill` gives the share of each storey's plan that the scan saw as floor.

## Collide with a scan

`add_scan_collider` adds one static triangle mesh body to a `PhysicsWorld`. Its triangles are the exposed faces of the grid's solid voxels, in building coordinates.

```mojo
var world = PhysicsWorld()
_ = add_scan_collider(world, grid, PhysicsMaterial.default())
```

A face is exposed when the voxel beyond it is empty or outside the grid. In each slice and direction, the exposed faces merge into rectangles, so a flat floor is two triangles. Each triangle's front faces out of the solid, as a mesh shape reads it.

A scan holds surfaces, not solids. A solid voxel is a shell one voxel thick. A fast small body can pass through it between two steps. Set the world's `collision_detection` to `SPHERE_MESH_CCD` for one. See [Continuous collision](Continuous-collision).

## The frame

A `ScanFrame` maps scan coordinates to building coordinates: meters, z up, +y north. It takes away `origin`, reads the building axes along `up` and `north`, multiplies by `unit`, and turns the plan by `heading`. +x is north cross up, so the axes are always right-handed.

`supersplat_frame` is the frame of a scene that looks upright in SuperSplat: up along the scan's -y, north along -z, one unit to the meter. SuperSplat shows a SOG or PLY scene turned half a turn about z, as the PlayCanvas engine shows a PLY file.

A photo scan has no scale of its own. `scale` is a `ScaleSource`:

| Source | Meaning |
|---|---|
| `SCALE_DECLARED` | A publisher's convention, such as one unit to the meter, that nobody checked |
| `SCALE_MEASURED` | A person measured a length in the place and in the scan |
| `SCALE_ASSUMED` | A length was assumed, such as a storey height or a published size, and matched to the scan |

`fit_building` writes a note for a declared or assumed scale. A load or a mass grows with the cube of a scale error.

`estimate_heading` finds the walls' plan angle. A wall splat is at least four times longer than thick, in plan and up the wall. Each one adds its opacity, times how much longer than thick it is, to the bin of its long axis's angle. The angle is modulo a quarter turn, in one-degree bins. The weighted mean angle of the five heaviest neighboring bins gives the heading, from -45 to +45 degrees.

## The occupancy grid

An `OccupancyGrid` divides a box of building coordinates into cubes of one edge, the voxels. Each splat adds its opacity to the voxel of its center. It also adds it to the voxels within one standard deviation along each axis, up to `reach` voxels on each side. A voxel whose sum reaches `solid_weight` is solid.

| Option | Default | Effect |
|---|---|---|
| `voxel` | 0.1 m | The voxel edge |
| `min_opacity` | 0.25 | A fainter splat adds nothing; most floaters are faint |
| `solid_weight` | 0.5 | The summed opacity of a solid voxel |
| `reach` | 2 | The most voxels a splat reaches on each side |
| `trim` | 0.005 | The share of splats left out at each end of each axis by `trimmed_region` |
| `max_voxels` | 2^27 | A region that needs more voxels is refused |

The grid is dense, four bytes a voxel. Grow the voxel for a large scan, such as a cathedral. The example doubles it until the region fits.

## Floors and ceilings

`detect_levels` looks down each column of voxels. A solid voxel with an empty voxel above it has a face that looks up. It is a floor face when the next solid voxel above it is at least `min_clear` above it. A ceiling face is the same, upside down.

This rule leaves out two faces that look like floors. The face on top of the highest ceiling looks up at nothing. The top of a ceiling, under the unseen inside of a slab, has the floor above it too close.

| Option | Default | Effect |
|---|---|---|
| `min_fraction` | 0.25 | The least share of the plan columns that a floor or a ceiling covers |
| `min_storey` | 2 m | Floors closer than this are one floor |
| `min_clear` | 1 m | The least empty height above a floor face or below a ceiling face |

A layer is a floor when its count of floor faces reaches `min_fraction` of the solid plan columns. Of floors closer than `min_storey`, the layer with the most faces stays, and a tie keeps the lower layer. A table top covers too little of the plan to count.

A drone flies around a building, not through it, so no floor has a ceiling above it. Then the lowest layer whose upward faces reach `min_fraction` is the ground, and `ScanLevels.exterior` is True.

## The fitted model

`fit_building` makes one storey for each floor, and one space for each storey.

- A storey ends at the next floor. The top storey ends at the first ceiling above its floor, or at the top of the scan.
- A storey's plan is the rectangle that holds its floor faces. A fraction `trim` of those columns is left out at each end of each axis.
- An outside scan's plan holds the columns with a solid voxel at least half of `min_storey` above the ground.
- The walls, slabs and roof come from `assemble`, with the kit's construction set.

Furniture hides the floor under it, so the rectangle is the floor and not only what the scan saw. A wall's voxels lie on both sides of the wall's surface, so the plan of a room is its inside, less half a voxel.

## The catalog and the tool

`assets/building_scans/manifest.json` names each scan: its source, credit, license, kit, use, frame and files. A scan's files are one `splat` file of any format that `read_scan` reads, or a SOG folder: one `meta` file and its `image` files.

`scene` is a SuperSplat scene id, or null for a scan from elsewhere. `ScanCatalog.open` reads the manifest as typed entries. It refuses a kit, a use or a frame that the kits and frames refuse. `ScanEntry.file` is the file that reads the scan. `catalog.scene(id)` gives its path in the cache, or nothing.

`tools/building_scans.mojo` downloads and checks the files, with the rules of `tools/carla_assets.mojo`:

```bash
sh tools/tool.sh .venv/bin/mojo building_scans check
sh tools/tool.sh .venv/bin/mojo building_scans status
sh tools/tool.sh .venv/bin/mojo building_scans fetch [ID ...] [--pin | --offline]
sh tools/tool.sh .venv/bin/mojo building_scans verify [ID ...] [--strict]
sh tools/tool.sh .venv/bin/mojo building_scans credits [--all]
```

- An entry with no files is resolved only with `--pin`. The tool reads its SuperSplat scene page, finds the `contentUrl` that its viewer loads, and adds the scene's `meta.json` and images as files. An entry with no files and no scene is an error.
- A file is written to the cache only after its SHA-256 matches. A verified file is never overwritten.
- A file with no sum is fetched only with `--pin`, which writes the sum into the manifest.
- A file whose URL is null is not hosted. Put it in the cache by hand, and the next fetch verifies it.

The tool refuses every license other than CC BY 4.0 and CC0 1.0. A CC BY-ND scene forbids changes, and a CC BY-NC scene forbids commercial use. See [How to add a scanned building](How-to-add-a-scanned-building).

## Credits

`building_scans credits` prints the credit of each cached scan. `assets/building_scans/ATTRIBUTION.md` holds the credit of every entry. Credit the author, link the source and the license, and say what you changed, when you share a scan or a render of it.

## Limits

- Each storey has one space, and its plan is a rectangle on the building axes. Interior walls are not found.
- A sloped roof, a dome or a vault is the top of a storey, not a roof shape.
- The constructions come from the kit. They are assumed, not measured.
- The scale of a scan is only as good as its source. See the table of scale sources.
- An outside scan gives one storey from the ground to the top. A hillside has no flat ground layer: find its ground with `terrain_ground` and cut its parts with `scan_parts_on`, as `examples/scan_parts.mojo` does.
- The grid is dense, so a large scan needs a larger voxel.

See [Why scans become building models](Why-scans-become-building-models) for the reasons behind the design.
