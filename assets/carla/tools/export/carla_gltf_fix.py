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

    python carla_gltf_fix.py EXPORT_ROOT MESH.gltf OUT_DIR NAME [--max-size 1024]
"""

import argparse
import io
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile

from PIL import Image

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


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def mask_channel(pixels, width, height):
    """Return the cut-out channel from `tools/carla_mask_channel.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="mask-channel-")
    try:
        path = os.path.join(folder, "mask.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({
                "width": int(width),
                "height": int(height),
                "pixels": [int(value) for value in pixels],
            }, handle, separators=(",", ":"))
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_mask_channel", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "mask channel failed")
    return json.loads(result.stdout)


def quantize_image(values):
    """Return unit floats as bytes from `tools/carla_image_resize.mojo`.

    Each value is clipped to 0..1, multiplied by 255, and the fraction
    is dropped, as NumPy's ``uint8`` cast does.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="image-bytes-")
    try:
        path = os.path.join(folder, "bytes.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({
                "mode": "bytes",
                "pixels": [float(value) for value in values],
            }, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_image_resize", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "image bytes failed")
    return json.loads(result.stdout)["pixels"]


def resize_image(pixels, width, height, bands, out_width, out_height, mode):
    """Return resized pixels from `tools/carla_image_resize.mojo`.

    `mode` is `lanczos` or `box`. The pixels match Pillow 12.3.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="image-resize-")
    try:
        path = os.path.join(folder, "resize.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({
                "mode": mode,
                "width": int(width),
                "height": int(height),
                "bands": int(bands),
                "out_width": int(out_width),
                "out_height": int(out_height),
                "pixels": [int(value) for value in pixels],
            }, handle, separators=(",", ":"))
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_image_resize", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "image resize failed")
    return json.loads(result.stdout)["pixels"]


def _texture_name(data, image_format):
    """Return `texture_` plus the SHA-256 of `data` from `tools/carla_texture_plan.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="texture-name-")
    try:
        raw = os.path.join(folder, "bytes")
        with open(raw, "wb") as handle:
            handle.write(data)
        request = os.path.join(folder, "name.json")
        with open(request, "w", encoding="utf-8") as handle:
            json.dump({
                "mode": "name",
                "path": raw,
                "format": image_format,
            }, handle, separators=(",", ":"))
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_texture_plan", request],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "texture name failed")
    return json.loads(result.stdout)["name"]


def _texture_plan(path, color, max_size, width, height, masked):
    """Return the packaged size and encoding from `tools/carla_texture_plan.mojo`.

    A neutral file name becomes an 8 pixel square before the size limit.
    `masked` keeps an optimized PNG and does not use the neutral names.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="texture-plan-")
    try:
        request = os.path.join(folder, "plan.json")
        with open(request, "w", encoding="utf-8") as handle:
            json.dump({
                "mode": "fit" if masked else "texture",
                "path": path,
                "color": bool(color),
                "max": int(max_size),
                "width": int(width),
                "height": int(height),
            }, handle, separators=(",", ":"))
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_texture_plan", request],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "texture plan failed")
    return json.loads(result.stdout)


def _save_texture(package, image, plan):
    """Encode `image` with the format and options in `plan`."""
    options = {}
    if plan["quality"] >= 0:
        options["quality"] = int(plan["quality"])
    if plan["optimize"]:
        options["optimize"] = True
    return package._write_texture(image, plan["format"], **options)


def _pillow_resize(image, size, mode):
    """Return `image` resized to `size` by the Mojo Pillow filter."""
    if image.mode not in ("L", "RGB", "RGBA"):
        filt = Image.Resampling.LANCZOS if mode == "lanczos" else Image.Resampling.BOX
        return image.resize(size, filt)
    bands = {"L": 1, "RGB": 3, "RGBA": 4}[image.mode]
    pixels = resize_image(
        list(image.tobytes()), image.width, image.height, bands,
        size[0], size[1], mode,
    )
    return Image.frombytes(image.mode, size, bytes(pixels))


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

    def _write_texture(self, image, image_format, **options):
        """Name each packaged texture by its encoded bytes.

        Different source paths can have the same stem, and one color can
        have several masks. Neither case may overwrite a previous image:
        near materials and memoized far-bake inputs still refer to it.
        Equal encoded images can safely share a name across source paths.
        """
        with io.BytesIO() as output:
            image.save(output, format=image_format, **options)
            data = output.getvalue()
        name = _texture_name(data, image_format)
        os.makedirs(os.path.join(self.out_dir, "textures"), exist_ok=True)
        with open(os.path.join(self.out_dir, "textures", name), "wb") as target:
            target.write(data)
        return "textures/" + name

    def texture(self, source, color):
        """Return the texture index for image file `source`, adding it. A
        texture that a neutral name selects becomes a small image of its
        average color, under a plain name. `tools/carla_texture_plan.mojo`
        names those textures and chooses the fitted size."""
        key = (source, color)
        if key in self.images:
            return self.images[key]
        image = Image.open(source)
        plan = _texture_plan(
            source, color, self.max_size, image.width, image.height, False,
        )
        if plan["neutral"]:
            rgb = image.convert("RGB")
            average = resize_image(
                list(rgb.tobytes()), rgb.width, rgb.height, 3, 1, 1, "box",
            )
            image = Image.new("RGB", (8, 8), tuple(average))
        if plan["resize"]:
            image = _pillow_resize(image, (plan["width"], plan["height"]), "lanczos")
        uri = _save_texture(self, image.convert("RGB"), plan)
        self.gltf["images"].append({"uri": uri})
        self.gltf["textures"].append({"sampler": 0, "source": len(self.gltf["images"]) - 1})
        index = len(self.gltf["textures"]) - 1
        self.images[key] = index
        return index

    def masked_texture(self, color, mask):
        """Return the texture index of an RGBA image: the color of image
        file `color`, and an alpha from image file `mask`. The mask is its
        alpha channel when it has one, and otherwise its most black and
        white channel: CARLA's foliage packs a leaf's cut-out into one
        channel of an RGB image."""
        key = (color, mask, "masked")
        if key in self.images:
            return self.images[key]
        rgb = Image.open(color).convert("RGB")
        source = Image.open(mask)
        if source.mode in ("RGBA", "LA"):
            alpha = source.getchannel("A")
        else:
            # `tools/carla_mask_channel.mojo` chooses the cut-out channel.
            rgb_mask = source.convert("RGB")
            chosen = mask_channel(
                list(rgb_mask.tobytes()), rgb_mask.width, rgb_mask.height,
            )
            alpha = Image.frombytes(
                "L", rgb_mask.size, bytes(chosen["pixels"]),
            )
        alpha = _pillow_resize(alpha, rgb.size, "lanczos")
        image = rgb.copy()
        image.putalpha(alpha)
        plan = _texture_plan("", False, self.max_size, image.width, image.height, True)
        if plan["resize"]:
            image = _pillow_resize(image, (plan["width"], plan["height"]), "lanczos")
        uri = _save_texture(self, image, plan)
        self.gltf["images"].append({"uri": uri})
        self.gltf["textures"].append({"sampler": 0, "source": len(self.gltf["images"]) - 1})
        index = len(self.gltf["textures"]) - 1
        self.images[key] = index
        return index


def _material_plan(name, mat_text, props_text, pngs):
    """Return the Mojo factor and texture decisions for one material."""
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
    mojo = os.path.join(root, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    request = {"name": name, "mat": mat_text, "props": props_text, "pngs": list(pngs)}
    handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
    try:
        json.dump(request, handle)
        handle.close()
        result = subprocess.run(
            ["sh", os.path.join(root, "tools", "tool.sh"), mojo,
             "carla_gltf_material", handle.name],
            text=True, capture_output=True, check=False,
        )
    finally:
        os.remove(handle.name)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "material plan failed")
    return json.loads(result.stdout)


def rebuild(package, material, mats, props, pngs, report):
    """Rewrite one glTF material from UModel's files."""
    name = material.get("name", "")
    mat_text = None
    if name in mats:
        with open(mats[name], encoding="utf-8", errors="replace") as handle:
            mat_text = handle.read()
    props_text = None
    if name in props:
        with open(props[name], encoding="utf-8", errors="replace") as handle:
            props_text = handle.read()
    decision = _material_plan(name, mat_text, props_text, pngs)
    pbr = {
        "baseColorFactor": decision["baseColorFactor"],
        "metallicFactor": decision["metallicFactor"],
        "roughnessFactor": decision["roughnessFactor"],
    }
    for step in decision["textures"]:
        kind = step["kind"]
        if kind == "color":
            pbr["baseColorTexture"] = {"index": package.texture(pngs[step["stem"]], True)}
        elif kind == "normal":
            material["normalTexture"] = {"index": package.texture(pngs[step["stem"]], False)}
        elif kind == "masked":
            pbr["baseColorTexture"] = {
                "index": package.masked_texture(pngs[step["color"]], pngs[step["mask"]]),
            }
        elif kind == "orm":
            index = package.texture(pngs[step["stem"]], False)
            pbr["metallicRoughnessTexture"] = {"index": index}
            material["occlusionTexture"] = {"index": index}
    material["pbrMetallicRoughness"] = pbr
    if "alphaMode" in decision:
        material["alphaMode"] = decision["alphaMode"]
    if "alphaCutoff" in decision:
        material["alphaCutoff"] = decision["alphaCutoff"]
    if decision.get("doubleSided"):
        material["doubleSided"] = True
    if "extras" in decision:
        material["extras"] = decision["extras"]
    material.pop("extensions", None)
    parent, textures = decision["report"]
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


def _area_normals(points, faces):
    """Return area-weighted normals from `tools/carla_area_normals.mojo`."""
    import numpy
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="area normals ")
    try:
        path = os.path.join(folder, "mesh.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({
                "points": numpy.asarray(points, dtype=float).reshape(-1, 3).tolist(),
                "faces": numpy.asarray(faces).reshape(-1, 3).tolist(),
            }, handle)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_area_normals", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "area normals failed")
    values = json.loads(result.stdout)
    if not values:
        return numpy.zeros((0, 3))
    return numpy.array(values, dtype=numpy.float64)


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

    Each primitive is simplified alone with quadric error collapses, so
    no material bleeds into another, and its open edges stay put:
    `tools/carla_simplify.mojo` records the collapses and replays them.
    glTF splits a
    vertex along a texture seam, so
    the seams are edges and the textures do not tear. Every primitive
    gives up the same share. `tools/carla_simplify_target.mojo` chooses
    that share. One of fewer than `KEEP` triangles is kept
    whole, and so is a cut-out one, a tree's leaves: each leaf is a card
    of two triangles, all edge, which a collapse would tear. Each new
    vertex takes the texture coordinates and the tangent of an old vertex
    that collapsed into it. `tools/carla_collapse_map.mojo` keeps the
    first of those old vertices and copies its values.
    """
    import numpy

    def fixed(primitive):
        material = gltf["materials"][primitive["material"]] if "material" in primitive else {}
        count = gltf["accessors"][primitive["indices"]]["count"] // 3
        return count < KEEP or material.get("alphaMode") == "MASK"

    counts = []
    fixed_flags = []
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            count = gltf["accessors"][primitive["indices"]]["count"] // 3
            counts.append(count)
            fixed_flags.append(bool(fixed(primitive)))
    chosen = simplify_target({
        "mode": "vehicle",
        "counts": counts,
        "fixed": fixed_flags,
        "budget": int(budget),
        "keep": int(KEEP),
    })
    if chosen["skip"]:
        return data
    out = bytearray(data)
    slot = 0
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            target = chosen["targets"][slot]
            slot += 1
            if fixed(primitive):
                continue
            indices, _ = _read(data, gltf, primitive["indices"])
            positions, _ = _read(data, gltf, primitive["attributes"]["POSITION"])
            points = numpy.array(positions, dtype=numpy.float64).reshape(-1, 3)
            faces = numpy.array(indices, dtype=numpy.int32).reshape(-1, 3)
            collapses = quadric_collapses(points, faces, target, True)
            new_points, new_faces, mapping = replay_mesh(points, faces, collapses)
            if len(new_faces) == 0:
                continue
            source = collapse_source(mapping, len(new_points))
            attributes = {"POSITION": _append(out, gltf, [float(v) for v in new_points.reshape(-1)],
                                              "f", 5126, "VEC3", 34962)}
            if "NORMAL" in primitive["attributes"]:
                # The collapses moved the vertices, so an old vertex's normal
                # no longer fits: each normal is its faces' again, weighted
                # by their areas. A hard edge is two vertices in glTF, so it
                # stays hard. `tools/carla_area_normals.mojo` weights them.
                normals = _area_normals(new_points, new_faces)
                attributes["NORMAL"] = _append(out, gltf, [float(v) for v in normals.reshape(-1)],
                                               "f", 5126, "VEC3", 34962)
            for name, accessor_index in primitive["attributes"].items():
                if name in ("POSITION", "NORMAL"):
                    continue
                values, width = _read(data, gltf, accessor_index)
                accessor = gltf["accessors"][accessor_index]
                if accessor["componentType"] != 5126:
                    continue
                picked = collapse_gather(source, values, width)
                attributes[name] = _append(out, gltf, picked, "f", 5126, accessor["type"], 34962)
            primitive["attributes"] = attributes
            primitive["indices"] = _append(out, gltf, [int(v) for v in new_faces.reshape(-1)],
                                           "I", 5125, "SCALAR", 34963)
    gltf["buffers"][0]["byteLength"] = len(out)
    return compact(gltf, bytes(out))


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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("export_root")
    parser.add_argument("mesh")
    parser.add_argument("out_dir")
    parser.add_argument("name")
    parser.add_argument("--max-size", type=int, default=1024)
    parser.add_argument("--budget", type=int, default=35000,
                        help="the triangles a model is simplified to; 0 keeps them all")
    args = parser.parse_args()
    mats = index_files(args.export_root, ".mat")
    props = index_files(args.export_root, ".props.txt")
    pngs = index_files(args.export_root, ".png")
    pngs.update({k: v for k, v in index_files(args.export_root, ".tga").items() if k not in pngs})
    gltf = json.load(open(args.mesh))
    if os.path.isdir(args.out_dir):
        shutil.rmtree(args.out_dir)
    os.makedirs(args.out_dir)
    package = Package(gltf, args.out_dir, args.max_size)
    report = []
    dedupe_materials(gltf)
    for material in gltf.get("materials", []):
        rebuild(package, material, mats, props, pngs, report)
    source_bin = os.path.join(os.path.dirname(args.mesh), gltf["buffers"][0]["uri"])
    data = split_lamps(gltf, strip_skin(gltf, open(source_bin, "rb").read()))
    if args.budget > 0:
        data = decimate(gltf, data, args.budget)
    with open(os.path.join(args.out_dir, args.name + ".bin"), "wb") as out:
        out.write(data)
    gltf["buffers"][0]["uri"] = args.name + ".bin"
    gltf["asset"]["generator"] = "ThreeMojo carla_gltf_fix.py"
    gltf["asset"]["copyright"] = "CARLA Team, CC-BY 4.0"
    if not gltf["images"]:
        for key in ("images", "textures", "samplers"):
            gltf.pop(key)
    with open(os.path.join(args.out_dir, args.name + ".gltf"), "w") as out:
        json.dump(gltf, out, indent=1)
    for name, parent, textures in report:
        print(f"  {name:45s} {parent:28s} {' '.join(textures)}")


if __name__ == "__main__":
    main()
