# CARLA assets

The CARLA town can use real assets in place of its procedural ones: photoscanned road textures, sky panoramas and CARLA's own vehicle models. The manifest, `assets/carla/manifest.json`, lists each asset. The tool `assets/carla/tools/carla_assets.py` downloads the assets into `.cache/carla-assets/` and checks the SHA-256 sum of each file. Git ignores the cache. A build or a test does not need the assets: when an asset is not in the cache, the renderer uses its procedural asset.

## Fetch the assets

1. Check the manifest:

   ```sh
   python3 assets/carla/tools/carla_assets.py check
   ```

2. Download each asset that has a URL and a sum:

   ```sh
   python3 assets/carla/tools/carla_assets.py fetch
   ```

3. See which entries the cache holds:

   ```sh
   python3 assets/carla/tools/carla_assets.py status
   ```

To fetch one entry, give its id, for example `fetch carla.vehicle.audi.a2`. The tool writes a file only after its sum matches. It never writes over a file that is already verified.

## Credit the assets

The 41 vehicles and six towns are CC BY 4.0. Shared renders and asset
packages must carry their applicable credits, source links, license link
and conversion notices. The code license does not replace the asset license.

The committed [attribution catalog](https://github.com/SethKitchen/ThreeMojo/blob/main/assets/carla/ATTRIBUTION.md)
lists all 47 entries and credits the 11 CC0 entries as a courtesy.
It is a complete catalog, not a list of assets proven present in one image.

The three CARLA gallery targets write a `.credits.md` file beside the
output. Keep it with the gallery and its component images when sharing them.
For a direct example run, generate that file yourself:

```sh
python3 assets/carla/tools/carla_assets.py credits --all --output out/carla.credits.md
```

After editing the manifest, update the committed catalog:

```sh
python3 assets/carla/tools/carla_assets.py credits --all --output assets/carla/ATTRIBUTION.md
```

`make test-tools` checks that the catalog still matches the manifest.
Hosting durability is tracked in [#309](https://github.com/SethKitchen/ThreeMojo/issues/309).
The current share links are not a durable distribution guarantee.

## The CARLA vehicles

The manifest has 41 vehicles from the CARLA 0.9.16 release. Each vehicle is one zip of about 1 to 8 MB, 125 MB in total. The zip holds a glTF file, its buffer and its textures. The model faces plus x, stands on y = 0 and is in meters.

Each model is simplified to about 35,000 triangles. CARLA's own models have 5,000 to 140,000. The renderer draws each triangle into the frame and into every shadow cascade, so this halves the time of a view with seven cars.

Each model tags some of its materials in its `extras`, as `{"carla": "paint"}`, `"heads"` or `"tails"`. The town gives the paint the color of the blueprint's `color` attribute, as CARLA does. The head lamps and the tail lamps glow with the vehicle's light state.

The entry id is the blueprint id with the prefix `carla.`, for example `carla.vehicle.audi.a2`. The binding table maps each blueprint id to its entry. It also maps the older names and the Unreal 5 names to the 0.9.16 vehicle that they name:

| Blueprint id | Entry |
|---|---|
| `vehicle.dodge.charger` | `carla.vehicle.dodge.charger_2020` |
| `vehicle.dodgecop.charger` | `carla.vehicle.dodge.charger_police_2020` |
| `vehicle.taxi.ford` | `carla.vehicle.ford.crown` |
| `vehicle.lincoln.mkz` | `carla.vehicle.lincoln.mkz_2020` |
| `vehicle.mini.cooper` | `carla.vehicle.mini.cooper_s_2021` |
| `vehicle.sprinter.mercedes` | `carla.vehicle.mercedes.sprinter` |
| `vehicle.carlacola.actors` | `carla.vehicle.carlamotors.carlacola` |
| `vehicle.firetruck.actors` | `carla.vehicle.carlamotors.firetruck` |
| `vehicle.ambulance.ford` | `carla.vehicle.ford.ambulance` |
| `vehicle.fuso.mitsubishi` | `carla.vehicle.mitsubishi.fusorosa` |

CARLA 0.9.16 has no mining truck. `vehicle.miningtruck.miningtruck` uses the procedural vehicle.

The `tree` key is bound to null. The Poly Haven tree has 1.6 million triangles, which is too many to plant along a street.

## Host the vehicle zips

The zips are too large to commit. Each one is a file in a shared Google Drive folder, and the manifest holds its share link and its sum. `fetch` downloads a zip, checks its sum and extracts it. A zip without a URL has the URL `null`, and `fetch` reports it as `unhosted`. You can put a zip at its cache path by hand, and the next `fetch` verifies it and extracts it.

To add the URLs after you rebuild the zips:

1. Upload each zip. Share each one with anyone who has the link.
2. Write a JSON file that maps each zip name to its share link:

   ```json
   {"vehicle.audi.a2.zip": "https://drive.google.com/file/d/FILE_ID/view?usp=sharing"}
   ```

3. Write the URLs into the manifest:

   ```sh
   python3 assets/carla/tools/export/manifest_vehicles.py --urls urls.json
   ```

The fetch tool changes a Google Drive share link into Drive's download link. When a host sends a web page in place of the file, the tool stops with an error. Drive does this for a file that is not shared.

## Rebuild the vehicle zips

CARLA's vehicles are Unreal Engine 4.26 assets. The scripts in `assets/carla/tools/export/` change them to glTF. They run on Windows, because UE Viewer (UModel) is a Windows program.

1. Make a work folder. Set `CARLA_EXPORT_DIR` to it.
2. Put UModel build 1590 at `umodel/umodel_64.exe`.
3. Extract `CarlaUE4/Content/` from `CARLA_0.9.16.zip` into `cooked/`. You need `Carla/Static/Car`, `Carla/Static/Vehicles`, `Carla/Static/GenericMaterials`, `Carla/Static/Dynamic` and `Carla/Blueprints/Vehicles`.
4. Run the export, the zip and the manifest scripts:

   ```sh
   python export_vehicles.py
   python zip_packages.py
   python manifest_vehicles.py
   ```

`export_vehicles.py` reads each vehicle blueprint for the meshes it names. It exports the skeletal body and the static glass and lights, then merges them into one glTF file. `carla_gltf_fix.py` then does these steps:

1. It rebuilds each material from the parameters that UModel writes beside the mesh. It uses the base color, normal and ORM maps, the car paint's color and translucent glass. It scales each texture to 1024 pixels or less.
2. It removes the skin, because the town takes plain meshes. It removes Unreal's vertex colors, because they are masks and not colors.
3. It splits the lamps into head lamps and tail lamps. CARLA's lamp material reads an eight-color mask, and UModel does not export what the colors mean. So a lamp in front of the model's middle is a head lamp, and a lamp behind it is a tail lamp.
4. It simplifies the model to `--budget` triangles, 35,000 by default, one primitive at a time. The seams stay where they are, so the textures do not tear. The normals are made again from the simplified faces.

The simplification needs the `fast-simplification` Python package.

Use the cooked release, not the carla-content repository. The repository holds uncooked assets, and UModel cannot read an uncooked mesh.

## The CARLA towns

Each town package holds one CARLA town as CARLA builds it. It has the town's buildings, streets, sidewalks, plants, poles, fences, props and parked vehicles, each where the town puts it. The packages are Town01, Town02, Town03, Town04, Town05 and Town10HD, as `carla.town.<town>.zip`.

A package is two files: one binary glTF file, `carla.town.<town>.glb`, with its buffer and its textures inside, and the town's OpenDRIVE map, `<town>.xodr`. The positions are in the renderer's frame, in meters: three.js x, y and z are CARLA's x, z and y. So the package goes at the origin, with no turn and no scale.

The meshes are merged by tile, by kind and by material. A tile is 32 meters square. Each node has two tags in its `extras`:

| Tag | Values |
|---|---|
| `carla_kind` | `building`, `road`, `road_line`, `sidewalk`, `ground`, `terrain`, `water`, `rail`, `wall`, `fence`, `vegetation`, `pole`, `traffic_light`, `traffic_sign`, `parked_vehicle`, `prop` |
| `carla_lod` | `0` for near, `1` for far |

The near level keeps the detail that a camera sees close up. The far level keeps what shows at a distance. It leaves out the grass, the bushes, the props, the parked vehicles, the signs and the lamps' glass. A far tree is an impostor: two quads that cross on its trunk. Each quad shows a picture of the tree, drawn from its near level from the front or from the side, with its leaves cut out.

A far building is a baked proxy. Its corners are gathered into cells a 200th of its size, and the joined mesh is simplified. Its near level is drawn from each side and from above into one picture, and each far triangle shows the view that faces it. So its windows and its trim are in the picture, not in the geometry. The picture holds no light: the renderer lights the proxy.

A town's glass is a dark, smooth, partly metal pane that reflects its surroundings. A see-through window has nothing behind it, so a tower would show the sky through its windows.

The scene's `extras` list the head of each street lamp, as `carla_lamps`: three numbers for each lamp, in the renderer's frame. The lamps' glass has the material tag `{"carla": "lamp"}`. A renderer draws each tile at one level, chosen by the tile's distance to the camera.

Each mesh keeps a share of its triangles, by its kind. Each town also has a cap for each kind at each level. A town can have more than its cap, as Town04 has with its eight thousand pines. Then every mesh of that kind gives up the same share. A tree gives up leaf cards, and each card that stays grows, so the crown stays full. Other meshes are simplified, and their texture seams stay where they are.

Some textures in CARLA's content show a company's mark, a real person, a real institution or a poster of unclear origin. CARLA's license covers CARLA's own work, not these. Each one becomes one flat color, its average. `NEUTRAL` in `carla_gltf_fix.py` names them, and the vehicle packages use the same list.

A package names no engine and no engine path. `build_towns.py` stops with an error when it finds one.

## Rebuild the town packages

The towns are made in three steps. They run on Windows, like the vehicle scripts.

1. Dump each town's layout from a running server:

   ```sh
   python dump_layout.py
   ```

   The Python API does not say which mesh each object uses, and UModel cannot read the cooked levels. So `dump_layout.py` runs CARLA with UE4SS, a scripting runtime, and a Lua mod, `layout_dump/main.lua`. The mod writes each static mesh component: its mesh, its materials, its transform and its instances. The server runs with `-nullrhi`, so it does not use the GPU. Each run stops after `--limit` seconds, 60 by default.

   Use UE4SS experimental build 3.0.1-1152 or later. Version 3.0.1 stops CARLA 0.9.16 at start.

2. Export every mesh and material that the layouts name:

   ```sh
   python export_towns.py
   ```

   It reads the release's own `CarlaUE4/Content`, not `cooked/`. It does not export the engine's own content, which is licensed for use in the engine only. `build_towns.py` draws its own box for the engine's cube.

3. Build and zip the packages:

   ```sh
   python build_towns.py [--top 20]
   python zip_packages.py --packages town_packages --index towns.json
   python manifest_towns.py [--urls urls.json]
   ```

   `manifest_towns.py` writes each town's entry and its binding, `town.<town>`. The URLs file is the same form as the vehicles'.

   `--top` lists the meshes that add the most triangles to each town.

The build needs the `numpy`, `scipy`, `fast-simplification` and `Pillow` Python packages.

## Why not Poly Haven

Poly Haven has no CARLA vehicles or towns. CARLA's own models are in the CARLA release, in Unreal's format, under CC BY 4.0. The manifest still uses Poly Haven and ambientCG for the procedural town's textures and skies.

## Verify extracted files

Run `python3 assets/carla/tools/carla_assets.py verify` to check the cache.
For each verified archive, the tool also compares its extracted files with
its members. A changed extracted file is reported as a mismatch. `fetch`
refuses to overwrite it. Remove that file explicitly, then run `fetch` to
restore the verified member. Do this after a package update if an old
extracted file remains in the cache.
