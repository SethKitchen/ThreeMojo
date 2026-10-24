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
import hashlib
import io
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

from PIL import Image

# Textures that show another company's mark, a real person or a real
# institution, or poster art of unclear origin. CARLA's license covers its
# own work, not these, so each becomes one flat color: its average.
NEUTRAL = re.compile(
    r"^(bmw_logo|vh_car_mercedesbenzcoupe_mercedestopmat_basecolor|vh_car_minicoopers_minimat"
    r"|t_carlacola_d|vh_truck_carlacola_bodyworkmat_basecolor|t_billboard_d|sm_banner_|t_banner)", re.I)
# A primitive of fewer triangles is not simplified: a badge, a mirror.
KEEP = 400


def index_files(root, suffix):
    """Map each file stem under `root` with `suffix` to its path."""
    found = {}
    for base, _, files in os.walk(root):
        for name in files:
            if name.endswith(suffix):
                found.setdefault(name[: -len(suffix)], os.path.join(base, name))
    return found


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
        suffix = ".jpg" if image_format == "JPEG" else ".png"
        name = "texture_" + hashlib.sha256(data).hexdigest() + suffix
        os.makedirs(os.path.join(self.out_dir, "textures"), exist_ok=True)
        with open(os.path.join(self.out_dir, "textures", name), "wb") as target:
            target.write(data)
        return "textures/" + name

    def texture(self, source, color):
        """Return the texture index for image file `source`, adding it. A
        texture that `NEUTRAL` names becomes a small image of its average
        color, under a plain name."""
        key = (source, color)
        if key in self.images:
            return self.images[key]
        stem = os.path.splitext(os.path.basename(source))[0]
        neutral = bool(NEUTRAL.search(stem))
        image = Image.open(source)
        if neutral:
            average = image.convert("RGB").resize((1, 1), Image.BOX).getpixel((0, 0))
            image = Image.new("RGB", (8, 8), average)
        if max(image.size) > self.max_size:
            scale = self.max_size / max(image.size)
            image = image.resize(
                (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
                Image.LANCZOS,
            )
        if color:
            uri = self._write_texture(image.convert("RGB"), "JPEG", quality=88)
        else:
            uri = self._write_texture(image.convert("RGB"), "JPEG" if neutral else "PNG", optimize=True)
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
            channels = source.convert("RGB").split()

            def crispness(channel):
                histogram = channel.histogram()
                return sum(histogram[:16]) + sum(histogram[240:])

            alpha = max(channels, key=crispness)
        alpha = alpha.resize(rgb.size, Image.LANCZOS)
        image = rgb.copy()
        image.putalpha(alpha)
        if max(image.size) > self.max_size:
            scale = self.max_size / max(image.size)
            image = image.resize(
                (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
                Image.LANCZOS,
            )
        uri = self._write_texture(image, "PNG", optimize=True)
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


def _read(data, gltf, accessor_index):
    """Return an accessor's values as a flat list, and its width."""
    accessor = gltf["accessors"][accessor_index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    form = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}[accessor["componentType"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    count = accessor["count"] * width
    return list(struct.unpack_from("<%d%s" % (count, form), data, start)), width


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


def _append(out, gltf, values, form, component, kind, target):
    """Append values to the buffer as a new view and accessor, and return
    the accessor's index."""
    out += b"\0" * (-len(out) % 4)
    raw = struct.pack("<%d%s" % (len(values), form), *values)
    gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(out), "byteLength": len(raw),
                                "target": target})
    out += raw
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[kind]
    accessor = {"bufferView": len(gltf["bufferViews"]) - 1, "componentType": component,
                "count": len(values) // width, "type": kind}
    if kind == "VEC3" and form == "f":
        accessor["min"] = [min(values[i::3]) for i in range(3)]
        accessor["max"] = [max(values[i::3]) for i in range(3)]
    gltf["accessors"].append(accessor)
    return len(gltf["accessors"]) - 1


def decimate(gltf, data, budget):
    """Bring a model's triangles down to about `budget`, and return the
    buffer with the new primitives' data added.

    Each primitive is simplified alone with quadric error collapses (the
    fast-simplification package), so no material bleeds into another, and
    its open edges stay put: glTF splits a vertex along a texture seam, so
    the seams are edges and the textures do not tear. Every primitive
    gives up the same share. One of fewer than `KEEP` triangles is kept
    whole, and so is a cut-out one, a tree's leaves: each leaf is a card
    of two triangles, all edge, which a collapse would tear. Each new
    vertex takes the texture coordinates and the tangent of an old vertex
    that collapsed into it.
    """
    import numpy
    import fast_simplification

    def fixed(primitive):
        material = gltf["materials"][primitive["material"]] if "material" in primitive else {}
        count = gltf["accessors"][primitive["indices"]]["count"] // 3
        return count < KEEP or material.get("alphaMode") == "MASK"

    total = kept = 0
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            count = gltf["accessors"][primitive["indices"]]["count"] // 3
            total += count
            kept += count if fixed(primitive) else 0
    if total <= budget or total == kept:
        return data
    keep = max(0.05, (budget - kept) / (total - kept))
    out = bytearray(data)
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            if fixed(primitive):
                continue
            indices, _ = _read(data, gltf, primitive["indices"])
            count = len(indices) // 3
            positions, _ = _read(data, gltf, primitive["attributes"]["POSITION"])
            points = numpy.array(positions, dtype=numpy.float64).reshape(-1, 3)
            faces = numpy.array(indices, dtype=numpy.int32).reshape(-1, 3)
            target = max(KEEP // 2, int(count * keep))
            _, _, collapses = fast_simplification.simplify(
                points, faces, target_count=target, return_collapses=True, preserve_border=True)
            new_points, new_faces, mapping = fast_simplification.replay_simplification(
                points, faces, collapses)
            if len(new_faces) == 0:
                continue
            source = {}
            for old, new in enumerate(mapping):
                source.setdefault(int(new), old)
            attributes = {"POSITION": _append(out, gltf, [float(v) for v in new_points.reshape(-1)],
                                              "f", 5126, "VEC3", 34962)}
            if "NORMAL" in primitive["attributes"]:
                # The collapses moved the vertices, so an old vertex's normal
                # no longer fits: each normal is its faces' again, weighted
                # by their areas. A hard edge is two vertices in glTF, so it
                # stays hard.
                corners = new_points[new_faces]
                face = numpy.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
                normals = numpy.zeros_like(new_points)
                for k in range(3):
                    numpy.add.at(normals, new_faces[:, k], face)
                length = numpy.linalg.norm(normals, axis=1, keepdims=True)
                normals = numpy.where(length > 1e-12, normals / numpy.maximum(length, 1e-12), [0.0, 1.0, 0.0])
                attributes["NORMAL"] = _append(out, gltf, [float(v) for v in normals.reshape(-1)],
                                               "f", 5126, "VEC3", 34962)
            for name, accessor_index in primitive["attributes"].items():
                if name in ("POSITION", "NORMAL"):
                    continue
                values, width = _read(data, gltf, accessor_index)
                accessor = gltf["accessors"][accessor_index]
                if accessor["componentType"] != 5126:
                    continue
                picked = []
                for new in range(len(new_points)):
                    old = source.get(new, 0)
                    picked += values[old * width:(old + 1) * width]
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


def dedupe_materials(gltf):
    """Keep one material of each name. The merge gives each primitive its
    own copy, so a car's glass is twenty materials."""
    _gltf_tool(gltf, b"", "dedupe")


def strip_skin(gltf, data):
    """Turn a skinned glTF into plain meshes at its bind pose, and return
    the buffer without the bytes nothing reads any more.

    A CARLA vehicle is a skeletal mesh whose bones only turn the wheels
    and open the doors. At rest its bones are where the mesh was bound,
    and the mesh's node is the origin, so the vertices already stand
    where the car stands. The skin, the joints and the weights go; the
    bone nodes stay as named markers of the wheels.
    """
    return _gltf_tool(gltf, data, "strip")


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
