# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Create a bounded Town PBR reuse fixture from deterministic local inputs."""

import hashlib
import json
from pathlib import Path
import shutil
import struct
import sys
import zlib


def generate(destination, map_path):
    """Write one PNG, nine surface bindings, the map and their input hashes."""
    destination.mkdir(parents=True, exist_ok=True)

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data)))

    rows = bytearray()
    for y in range(512):
        rows.append(0)
        for x in range(512):
            rows.extend((x % 256, y % 256, (x ^ y) % 256, 255))
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 512, 512, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
    (destination / "pbr.png").write_bytes(data)
    sha = hashlib.sha256(data).hexdigest()
    roles = ["albedo", "roughness", "normal", "ao"]
    keys = ["surface." + name for name in [
        "road", "sidewalk", "curb", "wall", "crosswalk", "white_mark", "yellow_mark"
    ]] + ["ground.grass", "ground.paving"]
    manifest = {
        "format": 1,
        "entries": [{
            "id": "shared.surface",
            "kind": "texture_set",
            "license": "CC0-1.0",
            "author": "ThreeMojo contributors",
            "source": "https://github.com/SethKitchen/ThreeMojo/issues/336",
            "provenance": (
                "Synthetic payload-ownership fixture. One deterministic "
                "512-square PNG is reused by four PBR roles and nine Town "
                "surface bindings. No external asset download."
            ),
            "tile_meters": 2,
            "files": [
                {"role": role, "path": "pbr.png", "url": None, "sha256": sha}
                for role in roles
            ],
        }],
        "bindings": {key: "shared.surface" for key in keys},
    }
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    shutil.copyfile(map_path, destination / "town.xodr")
    record = {
        "image_size": [512, 512],
        "channels": 4,
        "roles": roles,
        "bindings": keys,
        "files": {
            name: hashlib.sha256((destination / name).read_bytes()).hexdigest()
            for name in ["pbr.png", "manifest.json", "town.xodr"]
        },
    }
    (destination / "INPUTS.json").write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps(record, indent=2))


if __name__ == "__main__":
    generate(Path(sys.argv[1]), Path(sys.argv[2]))
