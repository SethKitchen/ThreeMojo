# Village

`Village` stands houses and a scanned building on the meadow, beside a pond of still water.

![A brick house and a timber barn with gable roofs stand in wind-bent grass beyond a small pond, with trees, cliffs and mountains behind](out/village.png)

`examples/village.mojo` draws this picture. The modules live in `extensions/village/`. A village joins three subjects in one scene:

- the meadow of [Vegetation](Vegetation),
- the building models of [Building model](Building-model) and [Scanned buildings](Scanned-buildings),
- the Clearwater water of [Water](Water).

See [Extensions](Extensions).

## Draw one frame

```mojo
from core.assets import Assets
from core.scene import Scene
from extensions.vegetation.meadow import meadow_camera, meadow_renderer
from extensions.village.village import Village, VillageParameters
from extensions.water.pebbles import pebble_bed
from render.jpeg import decode
from std.pathlib import Path
from units.si import METER, SECOND, Duration, Length

var renderer = meadow_renderer(1280, 720)
var assets = Assets()
var scene = Scene()
var parameters = VillageParameters()
var bed = pebble_bed(decode(Path("assets/pebbles.jpg").read_bytes()))
var village = Village(scene, assets, renderer, parameters, bed^, None)
var camera = meadow_camera(parameters.meadow, 1280, 720, Length(0.0, METER))
_ = village.update(scene, assets, camera, Duration(2.0, SECOND))
var image = village.render(renderer, scene, assets, camera)
```

`Village` adds the meadow, the houses and the scanned building to the scene. `None` gives a village with no scanned building. `update` grows the grass for one camera and one time, and moves the water's clock on to that time. Call `update` before each `render`.

`render` draws the scene, and then composes the pond's water into the picture. Do not draw the scene with `renderer.render` alone: that picture has no water.

## Add a scanned building

Fetch a scan first. Then give its id to the example:

```sh
sh tools/tool.sh .venv/bin/mojo building_scans fetch seem-church
mojo run -I . examples/village.mojo out/village-church.png seem-church
```

The id names a scan in `assets/building_scans/manifest.json`. A path to a scan file that `extensions.scan.files` reads works too. A scan's license can require a credit. See [Scanned buildings](Scanned-buildings).

In code, cut the building out of its scan, and give it to `Village`:

```mojo
from extensions.scan.files import read_scan
from extensions.village.scanned import cut_building

var cut = cut_building(read_scan(path).geometry, frame, Length(0.5, METER))
var village = Village(scene, assets, renderer, parameters, bed^, cut^)
```

On a four-core Linux host, the example cuts the Seem church out of its scan in 1.2 seconds. The village builds in 3.2 seconds. The render takes about 20 seconds at 1280 by 720, with the church or without it.

## The parts

| Module | Holds |
|---|---|
| `house.mojo` | `HouseParameters`, `house_model`, `gable_roof`, `house_lot` and `stand_house`. |
| `scanned.mojo` | `CutBuilding`, `cut_building`, `linear_splats`, `scan_lot` and `stand_scan`. |
| `village.mojo` | `HousePlacement`, `VillageParameters` and `Village`. |

## The default village

`VillageParameters()` holds the meadow of [Vegetation](Vegetation), with these additions:

| Part | Where it stands |
|---|---|
| A pond 12 meters across and 1.2 meters deep | Right of the trail, 11 meters ahead of the camera. |
| A brick house of two storeys, 9 by 7 meters | On the left, about 75 meters away, turned 20 degrees. |
| A timber barn of one storey 4.2 meters tall, 13 by 8 meters | Ahead, about 90 meters away, turned -12 degrees. |
| The scanned building, if there is one | On the right, about 110 meters away, turned 28 degrees. |

The water's ocean spectrum is 256 texels on a side, and its glare is 128 texels. Its caustic grid is 64, as in the still, and its caustic texture is 256 texels on a side. The water's clock starts at 5 seconds, as the Clearwater page's does.

## Lots

Each building stands on a `Lot`: its footprint, turned about +y. `Village` puts the lots into `MeadowParameters.lots` before it builds the meadow. So no grass grows on a lot or on the bare apron round it, and no tree or bush stands there. The ground under a lot is mottled dirt. See [Ponds and lots](Vegetation#ponds-and-lots).

## Houses

`house_model` assembles a building model with `extensions.building.model.assemble`. Each storey is one living room, as wide and as deep as the house.

| Construction | Layers |
|---|---|
| Outside wall | 12 centimeters of the cladding, 10 centimeters of mineral wool, 1.25 centimeters of gypsum board |
| Inside wall | 10 centimeters of gypsum board |
| Slab | 20 centimeters of concrete |

`add_windows` cuts a row of double-glazed windows in each outside wall. A window is 1.3 meters tall, its sill is 0.9 meters up, and the row has one window each 2.6-meter bay. `add_doors` gives each room a door 1 meter wide and 2.1 meters tall.

`stand_house` adds the model's meshes to the scene with `add_building`, and turns the house by its lot. Then it adds two meshes of its own:

- **A plinth.** The ground floor stands at the highest ground under the four corners. A stone plinth fills the gap down to the lowest corner, and 40 centimeters below it. It is 15 centimeters wider than the walls on each side.
- **A gable roof.** A building model's roof is flat. With a `pitch` above zero, `stand_house` sets a gable roof on it. The ridge runs along the house's width, at the middle of its depth. The two slopes of red tiles reach 35 centimeters past the walls. A gable of the `gable` color closes each end. A `pitch` of zero keeps the flat roof.

## Scanned buildings

A scan of a building also holds its ground: paths, graves, a lawn or a street. `cut_building` keeps only the building:

1. It fills an occupancy grid of the scan. The voxel starts at the size that you give, and it doubles until the grid holds at most 4,194,304 voxels.
2. It finds the ground as a terrain surface of column tops. The surface must cover a quarter of the plan, and two columns of it differ by 2 meters at most.
3. It cuts the grid into parts above the ground, of 20 voxels or more. See [Scan parts](Scan-parts).
4. It copies the splats of the largest part.

A scan of a room has its floor as its ground, so do not use one for a village.

`stand_scan` stands the cut building as one Gaussian splat object. The middle of its footprint stands at the point that you give, and the building is turned about +y. Its foot is 15 centimeters below the lowest ground under its corners, so no gap shows on a slope.

A scan's colors are sRGB, as a screen shows them. The renderer blends splats as linear light, and tone maps the frame after. So `stand_scan` gives the scene a copy of the splats from `linear_splats`. Each color byte of the copy is linear light, and its opacity is kept. The copy has no spherical harmonics, because their shading adds to the sRGB color and has no exact linear form. The building keeps its colors and loses its sheen, which changes with the view.

## Water

The pond's water is a `WaterScene`. Its sun is the meadow's sun, so the water's glints agree with the grass's shadows.

`render` composes the water into the picture at the ground's `water_level`. The water is an endless plane, and the composition tests it against the depth of each pixel. The ground outside the basin lies above the water, so the water shows only in the basin. Grass and trees in front of the water keep their pixels.

`update` moves the water's clock on to the frame's time. An earlier time leaves the clock where it is, because the water's state moves only forward.

## Limits

- The water does not reflect the houses, the trees or the sky cube. It reflects the Clearwater sky.
- A house is a box of storeys under one gable roof. It has no porch, chimney or wing.
- A scanned building's splats are lit by the scan's own light, not by the meadow's sun. They cast no shadow.
- A lot keeps plants off the ground, but it does not level the ground. The plinth and the sunk foot fill the slope.
