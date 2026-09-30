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

CARLA's vehicles are CC BY 4.0, so each image or video that shows them must credit them. Print the credit list:

```sh
python3 assets/carla/tools/carla_assets.py credits --output CREDITS.md
```

## The CARLA vehicles

The manifest has 41 vehicles from the CARLA 0.9.16 release. Each vehicle is one zip of about 1 to 8 MB, 132 MB in total. The zip holds a glTF file, its buffer and its textures. The model faces plus x, stands on y = 0 and is in meters.

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

## Host the vehicle zips

The zips are too large to commit. Each one is hosted as a file, and the manifest holds its URL. Until a zip has a URL, its URL is `null` and `fetch` reports it as `unhosted`. The sum is in the manifest. You can put a zip at its cache path by hand, and the next `fetch` verifies it and extracts it.

To add the URLs:

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

`export_vehicles.py` reads each vehicle blueprint for the meshes it names. It exports the skeletal body and the static glass and lights, then merges them into one glTF file. `carla_gltf_fix.py` then rebuilds each material from the parameters that UModel writes beside the mesh. It uses the base color, normal and ORM maps, the car paint's color and translucent glass. It scales each texture to 1024 pixels or less.

Use the cooked release, not the carla-content repository. The repository holds uncooked assets, and UModel cannot read an uncooked mesh.

## Why not Poly Haven

Poly Haven has no CARLA vehicles. CARLA's own models are in the CARLA release, in Unreal's format, under CC BY 4.0. The manifest still uses Poly Haven and ambientCG for textures, skies and the tree, because CARLA's towns do not ship those as open files.
