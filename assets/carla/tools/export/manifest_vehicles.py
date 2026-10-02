# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Write the exported CARLA vehicles into the asset manifest.

`zip_packages.py` writes `upload/index.json`: each vehicle's zip, its
sum, its size and its members. This script makes one model entry per
vehicle, with the zip as its archive, and binds each blueprint id to its
entry. A vehicle keeps its URL from the manifest, or takes one from
`--urls`, or has a null URL until its zip is hosted.

    python manifest_vehicles.py [--urls URLS.json]

URLS.json maps a zip name, such as `vehicle.audi.a2.zip`, to its URL. A
Google Drive share link is fine: the fetch tool turns it into a download.
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import carla_assets as tool  # noqa: E402

BASE = os.path.abspath(os.environ.get("CARLA_EXPORT_DIR", "."))
INDEX = os.path.join(BASE, "upload", "index.json")
PREFIX = "carla."

AUTHOR = "CARLA Team (Computer Vision Center)"
SOURCE = "https://github.com/carla-simulator/carla/releases/tag/0.9.16"
PROVENANCE = (
    "CARLA 0.9.16's own vehicle, from the cooked Windows release "
    "(CARLA_0.9.16.zip). UE Viewer (umodel) build 1590 exported the "
    "blueprint's skeletal body and its static glass and lights to glTF; "
    "assets/carla/tools/export/ merged them and rebuilt the materials. "
    "The uncooked carla-content repository holds the same meshes, but "
    "UE Viewer cannot read uncooked meshes."
)
CHANGES = (
    "Exported from Unreal Engine 4.26 to glTF 2.0; the body and its "
    "attachments merged into one file; materials rebuilt as glTF PBR "
    "from their Unreal parameters; textures scaled to at most 1024 "
    "pixels."
)

# Names the blueprint id's make and model do not spell out.
TITLES = {
    "vehicle.bh.crossbike": "BH Crossbike",
    "vehicle.bmw.grandtourer": "BMW Grand Tourer",
    "vehicle.carlamotors.carlacola": "CarlaCola Truck",
    "vehicle.carlamotors.european_hgv": "European HGV",
    "vehicle.carlamotors.firetruck": "Fire Truck",
    "vehicle.harley-davidson.low_rider": "Harley-Davidson Low Rider",
    "vehicle.mini.cooper_s": "Mini Cooper S",
    "vehicle.mini.cooper_s_2021": "Mini Cooper S 2021",
    "vehicle.lincoln.mkz_2017": "Lincoln MKZ 2017",
    "vehicle.lincoln.mkz_2020": "Lincoln MKZ 2020",
    "vehicle.mitsubishi.fusorosa": "Mitsubishi Fuso Rosa",
    "vehicle.tesla.model3": "Tesla Model 3",
    "vehicle.vespa.zx125": "Vespa ZX 125",
    "vehicle.volkswagen.t2": "Volkswagen T2",
    "vehicle.volkswagen.t2_2021": "Volkswagen T2 2021",
    "vehicle.yamaha.yzf": "Yamaha YZF",
}

# Blueprint ids with no 0.9.16 vehicle of their own: the older 0.9 names
# and the Unreal 5 names of the catalog, each bound to the 0.9.16
# vehicle it names.
ALIASES = {
    "vehicle.dodge.charger": "vehicle.dodge.charger_2020",
    "vehicle.dodgecop.charger": "vehicle.dodge.charger_police_2020",
    "vehicle.taxi.ford": "vehicle.ford.crown",
    "vehicle.lincoln.mkz": "vehicle.lincoln.mkz_2020",
    "vehicle.mini.cooper": "vehicle.mini.cooper_s_2021",
    "vehicle.sprinter.mercedes": "vehicle.mercedes.sprinter",
    "vehicle.carlacola.actors": "vehicle.carlamotors.carlacola",
    "vehicle.firetruck.actors": "vehicle.carlamotors.firetruck",
    "vehicle.ambulance.ford": "vehicle.ford.ambulance",
    "vehicle.fuso.mitsubishi": "vehicle.mitsubishi.fusorosa",
}


def title_of(vehicle_id):
    """Return a vehicle's display name."""
    if vehicle_id in TITLES:
        return TITLES[vehicle_id]
    _, make, model = vehicle_id.split(".", 2)
    words = [make.capitalize()] + [w.upper() if len(w) <= 2 else w.capitalize() for w in model.split("_")]
    return " ".join(words)


def role_of(member, vehicle_id):
    """Return the role of one member of a vehicle's zip."""
    return "model" if member == vehicle_id + ".gltf" else "support"


def entry_of(vehicle_id, item, url):
    """Return the manifest entry of one vehicle."""
    folder = f"carla/vehicles/{vehicle_id}"
    return {
        "id": PREFIX + vehicle_id,
        "kind": "model",
        "title": title_of(vehicle_id) + " (CARLA)",
        "license": "CC-BY-4.0",
        "author": AUTHOR,
        "source": SOURCE,
        "provenance": PROVENANCE,
        "changes": CHANGES,
        "forward": "+x",
        "files": [{
            "role": "archive",
            "url": url,
            "sha256": item["sha256"],
            "path": f"{folder}.zip",
            "extract": [
                {"role": role_of(m, vehicle_id), "member": m, "path": f"{folder}/{m}"}
                for m in item["members"]
            ],
        }],
    }


def main(argv=None):
    """Update the manifest."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", default=str(tool.MANIFEST))
    parser.add_argument("--index", default=INDEX)
    parser.add_argument("--urls")
    args = parser.parse_args(argv)
    manifest = tool.load_manifest(args.manifest)
    with open(args.index, encoding="utf-8") as source:
        index = json.load(source)
    urls = {}
    if args.urls:
        with open(args.urls, encoding="utf-8") as source:
            urls = json.load(source)
    old = {e["id"]: e for e in manifest["entries"]}
    kept = [e for e in manifest["entries"] if not e["id"].startswith(PREFIX + "vehicle.")]
    added = []
    for vehicle_id, item in sorted(index.items()):
        previous = old.get(PREFIX + vehicle_id)
        url = urls.get(item["zip"])
        if url is None and previous is not None and previous["files"][0]["sha256"] == item["sha256"]:
            url = previous["files"][0]["url"]
        added.append(entry_of(vehicle_id, item, url))
    manifest["entries"] = kept + added
    bindings = manifest.setdefault("bindings", {})
    for vehicle_id in index:
        bindings[vehicle_id] = PREFIX + vehicle_id
    for alias, vehicle_id in ALIASES.items():
        if vehicle_id in index:
            bindings[alias] = PREFIX + vehicle_id
    # The other keys keep their order; the vehicles follow, sorted, and
    # the vehicle wildcard comes after them.
    vehicles = sorted(k for k in bindings if k.startswith("vehicle.") and k != "vehicle.*")
    order = [k for k in bindings if not k.startswith(("vehicle.", "walker."))]
    order += vehicles + ["vehicle.*"] + [k for k in bindings if k.startswith("walker.")]
    manifest["bindings"] = {k: bindings.get(k) for k in order}
    removed = set(old) - {entry["id"] for entry in manifest["entries"]}
    for key, value in manifest["bindings"].items():
        if value in removed:
            manifest["bindings"][key] = None
    tool.save_manifest(manifest, args.manifest)
    hosted = sum(1 for e in added if e["files"][0]["url"])
    print(f"{len(added)} vehicles written, {hosted} with a URL, {len(manifest['bindings'])} bindings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
