# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Write the manifest's Poly Haven entries from Poly Haven's own API.

For each asset in `ASSETS`, read its name, its authors, its scanned size
and its files from api.polyhaven.com, and write its entry: a texture
set's maps and its tile size (the scan's width), an HDRI's panorama, or
a model's glTF with every file the glTF names. Then download each file
into the cache, check it against the MD5 sum the API gives, and write
its SHA-256 sum into the manifest.

    python polyhaven_entries.py [--resolution 2k]
"""

import argparse
import datetime
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import carla_assets as tool  # noqa: E402

API = "https://api.polyhaven.com"

# id -> (kind, forward axis for a model).
ASSETS = {
    "asphalt_02": ("texture_set", None),
    "concrete_pavement": ("texture_set", None),
    "concrete_floor_02": ("texture_set", None),
    "leafy_grass": ("texture_set", None),
    "patterned_paving": ("texture_set", None),
    "kloofendal_48d_partly_cloudy_puresky": ("hdri", None),
    "kloofendal_overcast_puresky": ("hdri", None),
    "belfast_sunset_puresky": ("hdri", None),
    "island_tree_01": ("model", "+z"),
    "concrete_road_barrier": ("model", "+x"),
}
# The map roles and the API's names for them.
MAPS = [("albedo", "Diffuse", "jpg"), ("normal", "nor_gl", "jpg"), ("roughness", "Rough", "jpg"),
        ("ao", "AO", "jpg"), ("displacement", "Displacement", "png")]


def get(path):
    """Return the API's JSON answer for `path`."""
    request = urllib.request.Request(API + path, headers={"User-Agent": tool.AGENT})
    for attempt in range(tool.ATTEMPTS):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError:
            raise
        except OSError:
            if attempt + 1 == tool.ATTEMPTS:
                raise
            time.sleep(tool.BACKOFF_SECONDS * (attempt + 1))


def authors(info):
    """Return the credit line of an asset's authors."""
    return ", ".join(info["authors"])


def entry_of(asset_id, kind, forward, resolution, today):
    """Return an entry and the MD5 sum the API gives for each of its paths."""
    info = get("/info/" + asset_id)
    files = get("/files/" + asset_id)
    md5 = {}
    entry = {
        "id": asset_id,
        "kind": kind,
        "title": info["name"],
        "license": "CC0-1.0",
        "author": authors(info),
        "source": "https://polyhaven.com/a/" + asset_id,
        "provenance": f"Poly Haven, {resolution}. The name, the authors, the size and the files "
                      f"are from api.polyhaven.com, read on {today}; each file matched the MD5 sum "
                      "the API gives before its SHA-256 sum was written here.",
        "files": [],
    }

    def add(role, item, path):
        entry["files"].append({"role": role, "url": item["url"], "sha256": None, "path": path})
        md5[path] = item["md5"]

    if kind == "texture_set":
        entry["tile_meters"] = round(info["dimensions"][0] / 1000.0, 3)
        for role, name, form in MAPS:
            if name in files:
                item = files[name][resolution][form]
                add(role, item, f"{asset_id}/{os.path.basename(item['url'])}")
    elif kind == "hdri":
        item = files["hdri"][resolution]["hdr"]
        add("hdri", item, f"{asset_id}/{os.path.basename(item['url'])}")
    else:
        entry["forward"] = forward
        gltf = files["gltf"][resolution]["gltf"]
        add("model", gltf, f"{asset_id}/{os.path.basename(gltf['url'])}")
        for relative, item in sorted(gltf["include"].items()):
            add("support", item, f"{asset_id}/{relative}")
    return entry, md5


def md5_of(path):
    """Return a file's MD5 sum."""
    digest = hashlib.md5()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1 << 16), b""):
            digest.update(block)
    return digest.hexdigest()


def main(argv=None):
    """Rewrite the Poly Haven entries, fetch them and pin them."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--manifest", default=str(tool.MANIFEST))
    parser.add_argument("--cache", default=str(tool.CACHE))
    parser.add_argument("--resolution", default="2k")
    args = parser.parse_args(argv)
    manifest = tool.load_manifest(args.manifest)
    today = datetime.date.today().isoformat()
    cache = tool.Path(args.cache)
    fresh = {}
    for asset_id, (kind, forward) in ASSETS.items():
        entry, md5 = entry_of(asset_id, kind, forward, args.resolution, today)
        for item in entry["files"]:
            status = tool.fetch_file(item, cache, pin=True)
            found = md5_of(cache / item["path"])
            if found != md5[item["path"]]:
                raise tool.FetchError(f"{item['url']}: MD5 {found} is not the API's {md5[item['path']]}")
            print(f"{status:9} {item['path']}")
        fresh[asset_id] = entry
    # Replace the old Poly Haven entries in place, and add the new ones
    # before the first entry that is not from Poly Haven.
    old = [e for e in manifest["entries"] if e["source"].startswith("https://polyhaven.com/")]
    rest = [e for e in manifest["entries"] if e not in old]
    manifest["entries"] = list(fresh.values()) + rest
    gone = {e["id"] for e in old} - set(fresh)
    for key, value in manifest["bindings"].items():
        if value in gone:
            manifest["bindings"][key] = None
    tool.save_manifest(manifest, args.manifest)
    print(f"{len(fresh)} Poly Haven entries written; dropped {sorted(gone)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
