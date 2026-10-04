# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Build a reproducible synthetic CARLA model-cache benchmark fixture.

This is a load-size proxy, not a CARLA source asset: 34,992 indexed
triangles, six materials, and one 1024-square RGBA texture with mipmaps.
Run: python3 bench/carla_model_cache_fixture.py /tmp/carla-cache-bench
"""

import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib


def generate(destination):
    """Write a manifest and its self-contained glTF dependencies."""
    destination.mkdir(parents=True, exist_ok=True)
    binary = bytearray()
    views = []
    accessors = []
    primitives = []

    def attribute(values, width, component=5126):
        offset = len(binary)
        code = "f" if component == 5126 else "I"
        binary.extend(struct.pack("<" + code * len(values), *values))
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(binary) - offset})
        accessor = {"bufferView": len(views) - 1, "componentType": component,
                    "count": len(values) // width,
                    "type": {1: "SCALAR", 2: "VEC2", 3: "VEC3"}[width]}
        accessors.append(accessor)
        return len(accessors) - 1

    cells = 54
    extents = (2.3, 0.75, 0.9)
    for face in range(6):
        axis = face // 2
        sign = 1 if face % 2 else -1
        u, v = (axis + 1) % 3, (axis + 2) % 3
        positions, normals, uv, indices = [], [], [], []
        for row in range(cells + 1):
            for column in range(cells + 1):
                point, normal = [0.0] * 3, [0.0] * 3
                point[axis] = sign * extents[axis]
                point[u] = (2 * column / cells - 1) * extents[u]
                point[v] = (2 * row / cells - 1) * extents[v]
                normal[axis] = sign
                positions.extend(point)
                normals.extend(normal)
                uv.extend((column / cells, row / cells))
        for row in range(cells):
            for column in range(cells):
                a = row * (cells + 1) + column
                b = a + cells + 1
                indices.extend((a, a + 1, b, a + 1, b + 1, b))
        primitives.append({"attributes": {"POSITION": attribute(positions, 3),
                                           "NORMAL": attribute(normals, 3),
                                           "TEXCOORD_0": attribute(uv, 2)},
                           "indices": attribute(indices, 1, 5125), "material": face})
    (destination / "vehicle.bin").write_bytes(binary)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    rows = bytearray()
    for y in range(1024):
        rows.append(0)
        for x in range(1024):
            rows.extend((x % 256, y % 256, (x ^ y) % 256, 255))
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1024, 1024, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
    (destination / "vehicle.png").write_bytes(png)
    materials = []
    for tag in ("paint", "heads", "tails", "glass", "rubber", "chrome"):
        materials.append({"extras": {"carla": tag}, "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "roughnessFactor": 0.5}})
    gltf = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}],
            "nodes": [{"mesh": 0}], "buffers": [{"byteLength": len(binary), "uri": "vehicle.bin"}],
            "bufferViews": views, "accessors": accessors, "meshes": [{"primitives": primitives}],
            "materials": materials, "images": [{"uri": "vehicle.png"}],
            "samplers": [{"minFilter": 9987}], "textures": [{"source": 0, "sampler": 0}]}
    (destination / "vehicle.gltf").write_text(json.dumps(gltf, separators=(",", ":")) + "\n")
    files = [{"role": role, "path": name, "url": None,
              "sha256": hashlib.sha256((destination / name).read_bytes()).hexdigest()}
             for role, name in (("model", "vehicle.gltf"), ("support", "vehicle.bin"), ("support", "vehicle.png"))]
    manifest = {"format": 1, "entries": [{"id": "synthetic.vehicle", "kind": "model",
                "license": "CC0-1.0", "author": "ThreeMojo contributors",
                "source": "https://github.com/SethKitchen/ThreeMojo/issues/291",
                "provenance": "Synthetic load-size proxy. No CARLA source data.",
                "forward": "+x", "files": files}], "bindings": {"vehicle.*": "synthetic.vehicle"}}
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"triangles": 6 * cells * cells * 2, "files": files}, indent=2))


if __name__ == "__main__":
    generate(Path(sys.argv[1]))
