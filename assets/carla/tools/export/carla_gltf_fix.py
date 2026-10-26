# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Turn a UModel glTF export of a CARLA vehicle into a self-contained,
textured glTF package.

UModel writes each material's textures and parameters beside the mesh, as
`<material>.mat` and `<material>.props.txt`, and leaves the glTF's
materials with factors only. This script reads those files and rebuilds
each material as glTF PBR:

- `Diffuse` becomes the base color texture, `Normal` the normal texture,
  and a texture named `*_ORM` both the occlusion and the
  metallic-roughness texture (glTF's own packing: R occlusion, G
  roughness, B metalness).
- A material whose parent is CARLA's car paint takes the `Base Color`
  vector as its factor and no texture: the paint's textures are a dirt
  and flake layer, not the paint.
- Glass is translucent; rubber, chrome, aluminium and plastic take
  factors from their names.

Textures are copied beside the glTF, scaled down to at most `--max-size`
pixels, color textures as JPEG and data textures as PNG.

    sh tools/tool.sh .venv/bin/mojo carla_gltf_package EXPORT_ROOT MESH.gltf OUT_DIR NAME [--max-size 1024]
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

# A primitive of fewer triangles is not simplified: a badge, a mirror.
KEEP = 400


def index_files(root, suffix):
    """Map each file stem under `root` with `suffix` to its path.

    `tools/carla_file_index.mojo` walks the directory. The first file of a
    stem is kept.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    result = subprocess.run(
        ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
         "carla_file_index", root, suffix],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "file index failed")
    return json.loads(result.stdout)


def _mat_tool(kind, path):
    """Return JSON from `tools/carla_mat_text.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    result = subprocess.run(
        ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
         "carla_mat_text", kind, path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "material text failed")
    return json.loads(result.stdout)


def read_mat(path):
    """Return the `key=value` pairs of a UModel `.mat` file.

    `tools/carla_mat_text.mojo` reads the file. Keys that start with
    `Other` are collected in `_others`.
    """
    return _mat_tool("mat", path)


def read_props(path):
    """Return the parent, the vector and the scalar parameters of a
    UModel `.props.txt` file, and whether it blends.

    `tools/carla_mat_text.mojo` reads the file.
    """
    doc = _mat_tool("props", path)
    return doc["parent"], doc["vectors"], doc["scalars"], doc["translucent"], doc["masked"]


def _store_tool(payload):
    """Return the packaged URI from `tools/carla_texture_store.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="texture-store-")
    try:
        path = os.path.join(folder, "store.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"))
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_texture_store", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "texture store failed")
    return json.loads(result.stdout)["uri"]


class Package:
    """The glTF being rebuilt and the textures it has gathered."""

    def __init__(self, gltf, out_dir, max_size):
        self.gltf = gltf
        self.out_dir = out_dir
        self.max_size = max_size
        self.images = {}
        gltf["images"] = []
        gltf["textures"] = []
        gltf["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]

    def _add_texture(self, uri, key):
        """Record one packaged URI and return its texture index."""
        self.gltf["images"].append({"uri": uri})
        self.gltf["textures"].append({"sampler": 0, "source": len(self.gltf["images"]) - 1})
        index = len(self.gltf["textures"]) - 1
        self.images[key] = index
        return index

    def texture(self, source, color):
        """Return the texture index for image file `source`, adding it. A
        texture that a neutral name selects becomes a small image of its
        average color, under a plain name.

        `tools/carla_texture_store.mojo` writes the file. Equal encoded
        images share one name. A later image does not replace an earlier
        file."""
        key = (source, color)
        if key in self.images:
            return self.images[key]
        uri = _store_tool({
            "op": "color",
            "out_dir": self.out_dir,
            "max_size": int(self.max_size),
            "source": source,
            "color": bool(color),
        })
        return self._add_texture(uri, key)

    def masked_texture(self, color, mask):
        """Return the texture index of an RGBA image: the color of image
        file `color`, and an alpha from image file `mask`. The mask is its
        alpha channel when it has one, and otherwise its most black and
        white channel: CARLA's foliage packs a leaf's cut-out into one
        channel of an RGB image.

        `tools/carla_texture_store.mojo` writes the file."""
        key = (color, mask, "masked")
        if key in self.images:
            return self.images[key]
        uri = _store_tool({
            "op": "masked",
            "out_dir": self.out_dir,
            "max_size": int(self.max_size),
            "color": color,
            "mask": mask,
        })
        return self._add_texture(uri, key)


def _rebuild_tool(payload):
    """Return one rebuilt material from `tools/carla_gltf_rebuild.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="gltf-rebuild-")
    try:
        path = os.path.join(folder, "rebuild.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_gltf_rebuild", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "material rebuild failed")
    return json.loads(result.stdout)


def _cache_rows(package):
    """Return the textures `package` has already stored."""
    rows = []
    for key, index in package.images.items():
        if len(key) == 3:
            rows.append({
                "op": "masked",
                "source": key[0],
                "color": False,
                "mask": key[1],
                "index": int(index),
            })
        else:
            rows.append({
                "op": "color",
                "source": key[0],
                "color": bool(key[1]),
                "mask": "",
                "index": int(index),
            })
    return rows


def rebuild(package, material, mats, props, pngs, report, town=False):
    """Rewrite one glTF material from UModel's files.

    `tools/carla_gltf_rebuild.mojo` applies the factors and writes each
    texture. `town` true drops vehicle tags and makes a glass pane.
    """
    name = material.get("name", "")
    mat_text = None
    if name in mats:
        with open(mats[name], encoding="utf-8", errors="replace") as handle:
            mat_text = handle.read()
    props_text = None
    if name in props:
        with open(props[name], encoding="utf-8", errors="replace") as handle:
            props_text = handle.read()
    result = _rebuild_tool({
        "material": material,
        "mat": mat_text,
        "props": props_text,
        "pngs": pngs,
        "out_dir": package.out_dir,
        "max_size": int(package.max_size),
        "texture_count": len(package.gltf["textures"]),
        "cache": _cache_rows(package),
        "town": bool(town),
    })
    material.clear()
    material.update(result["material"])
    for uri in result["images"]:
        package.gltf["images"].append({"uri": uri})
        package.gltf["textures"].append(
            {"sampler": 0, "source": len(package.gltf["images"]) - 1}
        )
    for item in result["cache_add"]:
        if item["op"] == "masked":
            package.images[(item["source"], item["mask"], "masked")] = item["index"]
        else:
            package.images[(item["source"], bool(item["color"]))] = item["index"]
    parent, textures = result["report"]
    report.append((name, parent, textures))


def _read_tool(data, gltf, accessor_index):
    """Return JSON from `tools/carla_gltf_read.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="gltf read ")
    try:
        path = os.path.join(folder, "read.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({
                "bytes": list(data),
                "accessors": gltf["accessors"],
                "bufferViews": gltf["bufferViews"],
                "accessor": accessor_index,
            }, handle)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_gltf_read", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "accessor read failed")
    return json.loads(result.stdout)


def _read(data, gltf, accessor_index):
    """Return an accessor's values as a flat list, and its width.

    `tools/carla_gltf_read.mojo` reads the buffer.
    """
    doc = _read_tool(data, gltf, accessor_index)
    return doc["values"], doc["width"]


def split_lamps(gltf, data):
    """Split each lamp primitive into the front lamps and the rear lamps,
    and return the buffer with their indices added.

    CARLA's lamp material reads an eight-color mask through each lamp's
    texture coordinates to tell its light apart: position, beams, brake,
    reverse, blinkers and fog. Which color is which is inside CARLA's
    master material, which UE Viewer does not export. The model faces plus
    x, so a triangle in front of the model's middle is a head lamp and one
    behind it a tail lamp: `"extras": {"carla": "heads"}` and `"tails"`.
    The lamps then glow white and red, as the town's own cars do.
    """
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
    mojo = os.path.join(root, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    work = tempfile.mkdtemp(prefix="gltf lamps ")
    try:
        source_gltf = os.path.join(work, "in.gltf")
        source_bin = os.path.join(work, "in.bin")
        out_gltf = os.path.join(work, "out.gltf")
        out_bin = os.path.join(work, "out.bin")
        with open(source_gltf, "w", encoding="utf-8") as handle:
            json.dump(gltf, handle)
        with open(source_bin, "wb") as handle:
            handle.write(data)
        result = subprocess.run(
            ["sh", os.path.join(root, "tools", "tool.sh"), mojo,
             "carla_gltf_lamps", source_gltf, source_bin, out_gltf, out_bin],
            text=True, capture_output=True, check=False,
        )
        if result.returncode != 0:
            raise ValueError(result.stderr.strip() or "lamp split failed")
        with open(out_gltf, encoding="utf-8") as handle:
            updated = json.load(handle)
        gltf.clear()
        gltf.update(updated)
        with open(out_bin, "rb") as handle:
            return handle.read()
    finally:
        shutil.rmtree(work)


def _append_tool(payload):
    """Return JSON from `tools/carla_gltf_append.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="gltf append ")
    try:
        path = os.path.join(folder, "append.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_gltf_append", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "buffer append failed")
    return json.loads(result.stdout)


def _append(out, gltf, values, form, component, kind, target):
    """Append values to the buffer as a new view and accessor, and return
    the accessor's index.

    `tools/carla_gltf_append.mojo` packs the bytes.
    """
    doc = _append_tool({
        "length": len(out),
        "viewIndex": len(gltf["bufferViews"]),
        "accessorIndex": len(gltf["accessors"]),
        "values": [float(value) if form == "f" else int(value) for value in values],
        "form": form,
        "component": component,
        "kind": kind,
        "target": target,
    })
    out += bytes(doc["bytes"])
    gltf["bufferViews"].append(doc["view"])
    gltf["accessors"].append(doc["accessor"])
    return doc["index"]


def collapse_source(mapping, count):
    """Return the first old corner that collapsed into each new corner.

    `tools/carla_collapse_map.mojo` reads the map. A new corner nobody
    reached stays 0.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="collapse-map-")
    try:
        path = os.path.join(folder, "map.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({
                "mapping": [int(value) for value in mapping],
                "count": int(count),
            }, handle, separators=(",", ":"))
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_collapse_map", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "collapse map failed")
    return json.loads(result.stdout)["source"]


def collapse_gather(source, values, width):
    """Return the texture values of the corners in `source`.

    `tools/carla_collapse_map.mojo` copies them. `source[new]` is the old
    corner whose `width` values are copied.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="collapse-gather-")
    try:
        path = os.path.join(folder, "gather.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({
                "source": [int(value) for value in source],
                "values": [float(value) for value in values],
                "width": int(width),
            }, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_collapse_map", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "collapse gather failed")
    return json.loads(result.stdout)["values"]


def simplify_target(payload):
    """Return JSON from `tools/carla_simplify_target.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="simplify-target-")
    try:
        path = os.path.join(folder, "target.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_simplify_target", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "simplify target failed")
    return json.loads(result.stdout)


def quadric_collapses(points, faces, target, border=True):
    """Return quadric collapses from `tools/carla_simplify.mojo`.

    `border` true keeps every open edge. The pairs are `[keep, drop]`.
    """
    import numpy

    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="simplify-")
    try:
        path = os.path.join(folder, "mesh.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({
                "points": numpy.asarray(points, dtype=float).reshape(-1, 3).tolist(),
                "triangles": numpy.asarray(faces).reshape(-1, 3).tolist(),
                "target": int(target),
                "border": bool(border),
            }, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_simplify", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "simplify failed")
    return numpy.asarray(json.loads(result.stdout)["collapses"], dtype=numpy.int32)


def replay_mesh(points, faces, collapses):
    """Return the points, triangles and old-to-new map after the collapses.

    `tools/carla_simplify.mojo` replays them. It rounds each point to
    float32, as `replay_simplification` does, then rebuilds the triangles.
    """
    import numpy

    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="simplify-replay-")
    try:
        path = os.path.join(folder, "replay.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({
                "mode": "replay",
                "points": numpy.asarray(points, dtype=float).reshape(-1, 3).tolist(),
                "triangles": numpy.asarray(faces).reshape(-1, 3).tolist(),
                "collapses": numpy.asarray(collapses).reshape(-1, 2).tolist(),
            }, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_simplify", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "replay failed")
    parsed = json.loads(result.stdout)
    return (
        numpy.array(parsed["points"], dtype=numpy.float64).reshape(-1, 3),
        numpy.array(parsed["triangles"], dtype=numpy.int64).reshape(-1, 3),
        numpy.array(parsed["mapping"], dtype=numpy.int64),
    )


def decimate(gltf, data, budget):
    """Bring a model's triangles down to about `budget`, and return the
    buffer with the new primitives' data added.

    `tools/carla_gltf_decimate.mojo` simplifies each free part on its own,
    so no material bleeds into another. A part of fewer than `KEEP`
    triangles stays whole, and so does a cut-out one: each leaf is a card
    of two triangles, all edge, which a collapse would tear. Open edges
    stay put, so the textures do not tear. Every free part gives up the
    same share of `budget`.
    """
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
    mojo = os.path.join(root, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    work = tempfile.mkdtemp(prefix="gltf decimate ")
    try:
        source_gltf = os.path.join(work, "in.gltf")
        source_bin = os.path.join(work, "in.bin")
        out_gltf = os.path.join(work, "out.gltf")
        out_bin = os.path.join(work, "out.bin")
        with open(source_gltf, "w", encoding="utf-8") as handle:
            json.dump(gltf, handle)
        with open(source_bin, "wb") as handle:
            handle.write(data)
        result = subprocess.run(
            ["sh", os.path.join(root, "tools", "tool.sh"), mojo,
             "carla_gltf_decimate", str(int(budget)), str(int(KEEP)),
             source_gltf, source_bin, out_gltf, out_bin],
            text=True, capture_output=True, check=False,
        )
        if result.returncode != 0:
            raise ValueError(result.stderr.strip() or "decimate failed")
        with open(out_gltf, encoding="utf-8") as handle:
            updated = json.load(handle)
        gltf.clear()
        gltf.update(updated)
        with open(out_bin, "rb") as handle:
            return handle.read()
    finally:
        shutil.rmtree(work)


def _gltf_tool(gltf, data, mode):
    """Run one Mojo glTF buffer step and update `gltf` in place."""
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
    mojo = os.path.join(root, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    work = tempfile.mkdtemp(prefix="gltf compact ")
    try:
        source_gltf = os.path.join(work, "in.gltf")
        source_bin = os.path.join(work, "in.bin")
        out_gltf = os.path.join(work, "out.gltf")
        out_bin = os.path.join(work, "out.bin")
        with open(source_gltf, "w", encoding="utf-8") as handle:
            json.dump(gltf, handle)
        with open(source_bin, "wb") as handle:
            handle.write(data)
        result = subprocess.run(
            ["sh", os.path.join(root, "tools", "tool.sh"), mojo,
             "carla_gltf_compact", mode, source_gltf, source_bin, out_gltf, out_bin],
            text=True, capture_output=True, check=False,
        )
        if result.returncode != 0:
            raise ValueError(result.stderr.strip() or "glTF compact failed")
        with open(out_gltf, encoding="utf-8") as handle:
            updated = json.load(handle)
        gltf.clear()
        gltf.update(updated)
        with open(out_bin, "rb") as handle:
            return handle.read()
    finally:
        shutil.rmtree(work)


def _dedupe_tool(gltf):
    """Return JSON from `tools/carla_gltf_dedupe.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="gltf dedupe ")
    try:
        path = os.path.join(folder, "mesh.gltf")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(gltf, handle)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_gltf_dedupe", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "material dedupe failed")
    return json.loads(result.stdout)


def dedupe_materials(gltf):
    """Keep one material of each name.

    The merge gives each primitive its own copy, so a car's glass is
    twenty materials. `tools/carla_gltf_dedupe.mojo` keeps the first name.
    """
    updated = _dedupe_tool(gltf)
    gltf.clear()
    gltf.update(updated)


def _skin_tool(gltf):
    """Return JSON from `tools/carla_gltf_skin.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="gltf skin ")
    try:
        path = os.path.join(folder, "mesh.gltf")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(gltf, handle)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_gltf_skin", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "skin strip failed")
    return json.loads(result.stdout)


def strip_skin(gltf, data):
    """Turn a skinned glTF into plain meshes at its bind pose, and return
    the buffer without the bytes nothing reads any more.

    A CARLA vehicle is a skeletal mesh whose bones only turn the wheels
    and open the doors. At rest its bones are where the mesh was bound,
    and the mesh's node is the origin, so the vertices already stand
    where the car stands. The skin, the joints and the weights go; the
    bone nodes stay as named markers of the wheels.

    `tools/carla_gltf_skin.mojo` removes the skin data. Unreal's vertex
    colors are masks and not colors, so they go too.
    """
    updated = _skin_tool(gltf)
    gltf.clear()
    gltf.update(updated)
    return compact(gltf, data)


def compact(gltf, data):
    """Return the buffer with only the bytes a primitive reads, and point
    the views and accessors at their new places."""
    return _gltf_tool(gltf, data, "compact")
