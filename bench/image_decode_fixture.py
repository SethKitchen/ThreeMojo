# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Create deterministic, offline image-loading fixtures using the standard library."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib

FNV_OFFSET = 14695981039346656037
FNV_PRIME = 1099511628211
MASK64 = (1 << 64) - 1
DATASETS = ("uniform_tiny", "uniform_medium", "stride_skew", "batch_boundary")


def fnv64(data, state=FNV_OFFSET):
    for value in data:
        state = ((state ^ value) * FNV_PRIME) & MASK64
    return state


def dimensions(dataset, count, alignment):
    """Return sizes in job order; large jobs test two scheduling failure modes."""
    if dataset == "uniform_tiny":
        return [16] * count
    if dataset == "uniform_medium":
        return [256] * count
    if dataset == "stride_skew":
        # With W=alignment, every large job belongs to stride worker zero.
        return [768 if i % alignment == 0 else 64 for i in range(count)]
    if dataset == "batch_boundary":
        # Large jobs sit on both sides of alternating batch boundaries.
        return [768 if i % (2 * alignment) in (alignment - 1, alignment)
                else 64 for i in range(count)]
    raise ValueError(dataset)


def rgba(size, seed):
    result = bytearray(size * size * 4)
    at = 0
    for y in range(size):
        for x in range(size):
            result[at:at + 4] = bytes(((17 * x + 29 * y + 13 * seed) & 255,
                                      (x ^ y ^ seed) & 255,
                                      (7 * x + 11 * y + 3 * seed) & 255, 255))
            at += 4
    return result


def png(size, pixels):
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data)))
    stride = size * 4
    raw = b"".join(b"\0" + pixels[y * stride:(y + 1) * stride]
                   for y in range(size))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, level=6)) + chunk(b"IEND", b""))


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def mip_shape(size):
    sizes = []
    while True:
        sizes.append(size)
        if size == 1:
            return sizes
        size = max(1, size // 2)


def generate_one(root, dataset, count, alignment):
    destination = root / dataset
    destination.mkdir(parents=True, exist_ok=False)
    entries, images, textures, materials, files = [], [], [], [], []
    bindings = {}
    base_hash = FNV_OFFSET
    base_bytes = payload_bytes = levels = 0
    sizes = dimensions(dataset, count, alignment)
    for index, size in enumerate(sizes):
        name = f"image-{index:04d}.png"
        pixels = rgba(size, index + 1)
        base_hash = fnv64(pixels, base_hash)
        encoded = png(size, pixels)
        (destination / name).write_bytes(encoded)
        digest = hashlib.sha256(encoded).hexdigest()
        chain = mip_shape(size)
        base_bytes += len(pixels)
        payload_bytes += sum(level * level * 4 for level in chain)
        levels += len(chain)
        files.append({"path": name, "bytes": len(encoded), "sha256": digest,
                      "width": size, "height": size, "job": index})
        images.append({"uri": name})
        textures.append({"source": index, "sampler": 0})
        materials.append({"pbrMetallicRoughness": {
            "baseColorTexture": {"index": index}, "roughnessFactor": 0.5}})
        identifier = f"synthetic.image.{index:04d}"
        entries.append({"id": identifier, "kind": "texture_set", "license": "CC0-1.0",
                        "author": "ThreeMojo contributors", "source": "synthetic",
                        "provenance": "Deterministic benchmark pixels; no external source data.",
                        "tile_meters": 1,
                        "files": [{"role": "albedo", "path": name, "sha256": digest}]})
        bindings[f"surface.{index:04d}"] = identifier
    # Every material is used by a real triangle. Geometry is deliberately small.
    binary = struct.pack("<15f3H", 0, 0, 0, 1, 0, 0, 0, 1, 0,
                         0, 0, 1, 0, 0, 1, 0, 1, 2)
    (destination / "triangle.bin").write_bytes(binary)
    gltf = {"asset": {"version": "2.0"}, "scene": 0,
            "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
            "buffers": [{"uri": "triangle.bin", "byteLength": len(binary)}],
            "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36},
                            {"buffer": 0, "byteOffset": 36, "byteLength": 24},
                            {"buffer": 0, "byteOffset": 60, "byteLength": 6}],
            "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3,
                           "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]},
                          {"bufferView": 1, "componentType": 5126, "count": 3,
                           "type": "VEC2"},
                          {"bufferView": 2, "componentType": 5123, "count": 3,
                           "type": "SCALAR"}],
            "meshes": [{"primitives": [
                {"attributes": {"POSITION": 0, "TEXCOORD_0": 1}, "indices": 2,
                 "material": index} for index in range(count)]}],
            "images": images, "textures": textures, "materials": materials,
            "samplers": [{"magFilter": 9729, "minFilter": 9987,
                          "wrapS": 10497, "wrapT": 10497}]}
    write_json(destination / "scene.gltf", gltf)
    write_json(destination / "manifest.json",
               {"format": 1, "entries": entries, "bindings": bindings})
    for name in ("triangle.bin", "scene.gltf", "manifest.json"):
        content = (destination / name).read_bytes()
        files.append({"path": name, "bytes": len(content),
                      "sha256": hashlib.sha256(content).hexdigest()})
    return {"name": dataset, "path": dataset, "count": count,
            "alignment_workers": alignment, "sizes": sizes,
            "slow_jobs": [index for index, size in enumerate(sizes) if size == 768],
            "expected": {"textures": count, "base_bytes": base_bytes,
                         "payload_bytes": payload_bytes, "mip_levels": levels,
                         "base_fnv64": base_hash},
            "compressed_bytes": sum(f["bytes"] for f in files if f["path"].endswith(".png")),
            "files": files}


def generate(root, count=16, alignment=4, datasets=DATASETS):
    if count < 1 or alignment < 2:
        raise ValueError("count must be positive; alignment must be at least two")
    root = Path(root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    if (root / "fixtures.json").exists():
        raise FileExistsError("Use a new fixture directory; do not overwrite recorded inputs")
    manifest = {"schema": 1, "generator_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "zlib_version": zlib.ZLIB_VERSION, "zlib_runtime_version": zlib.ZLIB_RUNTIME_VERSION,
                "png": "RGBA8, opaque, filter zero, zlib level six",
                "datasets": [generate_one(root, name, count, alignment) for name in datasets]}
    write_json(root / "fixtures.json", manifest)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--count", type=int, default=16)
    parser.add_argument("--alignment", type=int, default=4)
    parser.add_argument("--datasets", nargs="+", choices=DATASETS, default=DATASETS)
    args = parser.parse_args()
    result = generate(args.destination, args.count, args.alignment, args.datasets)
    print(json.dumps({"fixtures": str(args.destination.resolve()),
                      "datasets": [{k: v for k, v in data.items() if k != "files"}
                                   for data in result["datasets"]]}, indent=2))


if __name__ == "__main__":
    main()
