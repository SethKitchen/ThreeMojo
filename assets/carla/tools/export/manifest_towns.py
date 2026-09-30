# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Write the town packages' entries and bindings into the manifest.

Reads `upload/towns.json`, which `zip_packages.py --packages
town_packages --index towns.json` writes, and replaces every
`carla.town.*` entry. Each entry is one archive: the zip, its sum, and
the members it extracts. Its URL comes from `--urls`, or stays the one
the manifest has when the zip's sum is unchanged, or is null until the
zip is hosted. Each town's binding is `town.<Town>`, the name
`TownSettings.package` takes.

    python manifest_towns.py [--urls URLS.json]

URLS.json maps a zip name, such as `carla.town.town02.zip`, to its URL.
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import carla_assets as tool  # noqa: E402

BASE = os.path.abspath(os.environ.get("CARLA_EXPORT_DIR", "."))
INDEX = os.path.join(BASE, "upload", "towns.json")
PREFIX = "carla.town."

AUTHOR = "CARLA Team (Computer Vision Center)"
SOURCE = "https://github.com/carla-simulator/carla/releases/tag/0.9.16"
PROVENANCE = (
    "CARLA 0.9.16's own town, from the cooked Windows release "
    "(CARLA_0.9.16.zip). A running CARLA server, with UE4SS and "
    "assets/carla/tools/export/layout_dump/main.lua, wrote where the town "
    "places every static mesh; UE Viewer (umodel) build 1590 exported the "
    "meshes and their materials; assets/carla/tools/export/build_towns.py "
    "placed and merged them. The town's OpenDRIVE map is the release's own."
)
CHANGES = (
    "Every static mesh placed as the town places it, in the renderer's "
    "frame; merged by 32 m tile, kind and material; a near and a far "
    "level of detail, trees far off drawn as impostors; meshes simplified "
    "to a triangle budget; materials rebuilt as glTF PBR; textures scaled "
    "to at most 512 pixels; textures that show another company's mark, a "
    "real person or institution, or poster art of unclear origin replaced "
    "by their average color."
)


def town_of(package):
    """Return a package's town name, as CARLA spells it: `Town02`."""
    for member in package["members"]:
        if member.endswith(".xodr"):
            return member[: -len(".xodr")]
    raise SystemExit("a town package has no OpenDRIVE map")


def entry_of(package_id, item, url):
    """Return the manifest entry of one town."""
    folder = f"carla/towns/{package_id}"
    return {
        "id": package_id,
        "kind": "town",
        "title": town_of(item) + " (CARLA)",
        "license": "CC-BY-4.0",
        "author": AUTHOR,
        "source": SOURCE,
        "provenance": PROVENANCE,
        "changes": CHANGES,
        "files": [{
            "role": "archive",
            "url": url,
            "sha256": item["sha256"],
            "path": f"{folder}.zip",
            "extract": [
                {"role": "model" if m == package_id + ".glb" else "support",
                 "member": m, "path": f"{folder}/{m}"}
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
    index = json.load(open(args.index, encoding="utf-8"))
    urls = json.load(open(args.urls, encoding="utf-8")) if args.urls else {}
    old = {e["id"]: e for e in manifest["entries"]}
    kept = [e for e in manifest["entries"] if not e["id"].startswith(PREFIX)]
    added = []
    bindings = manifest.setdefault("bindings", {})
    for package_id, item in sorted(index.items()):
        previous = old.get(package_id)
        url = urls.get(item["zip"])
        if url is None and previous is not None and previous["files"][0]["sha256"] == item["sha256"]:
            url = previous["files"][0]["url"]
        added.append(entry_of(package_id, item, url))
        bindings["town." + town_of(item)] = package_id
    manifest["entries"] = kept + added
    tool.save_manifest(manifest, args.manifest)
    print(f"{len(added)} towns written, {sum(1 for e in added if e['files'][0]['url'])} with a URL")


if __name__ == "__main__":
    main()
