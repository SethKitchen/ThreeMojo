# Village

`Village` stands houses and a scanned building on the meadow, beside a pond of still water. A character can walk into each house at its front door.

![Houses of fieldstone, timber framing, brick and boards stand in wind-bent grass beyond a small pond, with trees, cliffs and mountains behind](out/village.png)

`examples/village.mojo` draws this picture. The modules live in `extensions/village/`. A village joins three subjects in one scene:

- the meadow of [Vegetation](Vegetation),
- the houses of [Village houses](Village-houses), and the scans of [Scanned buildings](Scanned-buildings),
- the Clearwater water of [Water](Water).

See [Extensions](Extensions). To put people and animals in the village and walk through it, see [Village walk](Village-walk).

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

`Village.terrain` gives what carries and stops a character: the ground, and each house's walls, floor and steps. The furniture and the scanned building are solid lots. `Village.doors` holds every door. See [Village houses](Village-houses#where-a-character-can-walk).

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
| `house.mojo` | `Facade`, `HouseParameters`, `fieldstone`, `lime_plaster`, `front_wall`, `house_model`, `house_lot` and `footing`. |
| `house_view.mojo` | `Hinge`, `StandingHouse`, `door_leaf`, `facade_look` and `stand_house`. |
| `interior.mojo` | `Doorway`, `HouseInterior` and `house_interior`. |
| `terrain.mojo` | `WallSpan`, `Floor`, `Terrain`, `wall_push` and `view_entry`. |
| `doors.mojo` | `Doors`. |
| `props.mojo` | `PropKind`, `Prop`, `StandingProps` and `stand_props`. |
| `sheet.mojo` | `Sheet`. |
| `dressing.mojo` | `Glow`, `warm`, `warmth`, `prism`, `rug`, `patchwork`, `table_setting`, `jars`, `books`, `lantern` and `herbs`. |
| `gathering.mojo` | `GatherKind`, `Spot`, `GatherParameters`, `Satchel` and `Gathering`. See [Village gathering](Village-gathering). |
| `hud.mojo` | `draw_hud`, `draw_text` and the prompts. See [Village gathering](Village-gathering#the-heads-up-display). |
| `day.mojo` | `DayCycle` and `dim_water`. See [Village day and night](Village-day). |
| `skills.mojo` | `SkillKind`, `Skills`, `skill_of`, `level_of`, `ore_strikes`, `forage_bonus` and `fish_haste`. See [Village skills](Village-skills). |
| `combat.mojo`, `battle.mojo`, `foes.mojo`, `arms.mojo`, `blade.mojo`, `slashes.mojo`, `battle_hud.mojo` | The player's sword, the bandits and the dummies, and what a fight shows. See [Village combat](Village-combat). |
| `critters.mojo` | `Haunt`, `default_haunts`, `wing_color` and `Critters`. See [Village critters](Village-critters). |
| `talk.mojo` | `ErrandState`, `Errand`, `Speaker`, `default_speakers` and `Talk`. See [Village errands](Village-errands). |
| `weather.mojo` | `WeatherKind`, `WeatherLook`, `weather_look`, `cloud_cover` and `Weather`. See [Village weather](Village-weather). |
| `surfaces.mojo` | The textures, `HouseLooks` and `house_looks`. |
| `scanned.mojo` | `CutBuilding`, `cut_building`, `grid_voxel`, `linear_splats`, `scan_lot` and `stand_scan`. |
| `village.mojo` | `HousePlacement`, `VillageParameters` and `Village`. |

## The default village

`VillageParameters()` holds the meadow of [Vegetation](Vegetation), with these additions:

| Part | Where it stands |
|---|---|
| A pond 12 meters across and 1.2 meters deep | Right of the trail, 11 meters ahead of the camera. |
| A stone cottage of one story, 7 by 5.5 meters, under slates | Left of the trail, about 25 meters away, turned 80 degrees. |
| A framed cottage of one story, 6.5 by 5 meters | Left of the trail, about 60 meters away, turned 70 degrees. |
| A framed house of two stories, 8 by 6 meters | Right of the trail, about 55 meters away, turned -80 degrees. |
| A brick house of two stories, 9 by 7 meters | On the left, about 75 meters away, turned 20 degrees. |
| A boarded barn of one story 4.2 meters tall, 13 by 8 meters | Ahead, about 90 meters away, turned -12 degrees. |
| The scanned building, if there is one | On the right, about 110 meters away, turned 28 degrees. |

The houses' textures are 128 texels on a side.

### Oaks

The village's open and round trees grow as oaks. `oak` gives a tree an oak's wood and keeps its crown and its leaves:

| Part | The meadow's tree | An oak |
|---|---|---|
| Twig tips, and so by the pipe model the trunk and the limbs | As thick as the crown says | Twice as thick |
| The thinnest wood drawn | As the crown says | Twice as thick, so the same branches are drawn |
| Flare at the trunk's foot | As the crown says | Twice as much, at most 3 |
| Bark | Pale with dark patches | Gray-brown, with dark furrows four times as close |

The meadow's own scene keeps its pale trees. See [Vegetation](Vegetation).

The water's ocean spectrum is 256 texels on a side, and its glare is 128 texels. Its caustic grid is 64, as in the still, and its caustic texture is 256 texels on a side. The water's clock starts at 5 seconds, as the Clearwater page's does.

## Props

`VillageParameters.props` lists the things that stand about the village. Each `Prop` is a `PropKind`, a place, a turn and a length. `stand_props` draws them with the houses' materials, in one mesh for each material.

| Kind | What it is | Its length |
|---|---|---|
| `WELL` | A round stone wall, two posts, a beam, a little roof and a bucket | Its radius |
| `BARREL` | Oak staves with two iron hoops | Its radius |
| `CRATE` | A box of boards with slats on its edges | Its side |
| `HAY_BALE` | A bale of hay, tied with two cords | Its length |
| `FENCE` | Posts at most 2 meters apart, and two rails, a meter tall | Its length |
| `BENCH` | A plank on two trestles | Its length |
| `WOODPILE` | Split logs stacked under a board lid, their ends out, 0.6 meters deep and 1.15 meters tall | Its length |

The default village has a well and a bench by the trail, and barrels, crates and hay before the barn. A fence closes a garden behind the stone cottage, and a bench stands before the framed house. A woodpile stands outside the hearth's gable of each house with a hearth: `woodpile_by` places it, and `hearthed` says which houses have one. Each prop but a fence is a solid lot of the terrain, and each fence is a wall span. The residents' routes keep off the props.

## Lots

Each building stands on a `Lot`: its footprint, turned about +y. `Village` puts the lots into `MeadowParameters.lots` before it builds the meadow. So no grass grows on a lot or on the bare apron around it, and no tree or bush stands there. The ground under a lot is mottled dirt. See [Ponds and lots](Vegetation#ponds-and-lots).

A worn footpath 0.8 meters wide leads from each house's front door to the trail. `door_path` gives it as two lots with narrow aprons. The first runs 3.5 meters straight out from the door. The second runs on to the nearest point of the trail. A door with no trail within 60 meters, or on ground with no trail, has only the first.

## Houses

Each house is a canonical building model with a hall, a front door, windows and furniture. The village draws it with its own view, on a stone plinth, under a gable roof. See [Village houses](Village-houses).

## Scanned buildings

A scan of a building also holds its ground: paths, graves, a lawn or a street. `cut_building` keeps only the building:

1. It fills an occupancy grid of the scan. `grid_voxel` starts the voxel at the size that you give, and doubles it until the grid holds at most 4,194,304 voxels.
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
- A house is a box of stories under one gable roof. It has no porch and no wing. Its upper stories have no stairs.
- A scanned building's splats are lit by the scan's own light, not by the meadow's sun. They cast no shadow.
- A lot keeps plants off the ground, but it does not level the ground. The plinth and the sunk foot fill the slope.
