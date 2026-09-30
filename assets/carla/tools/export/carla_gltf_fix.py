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
import json
import os
import re
import shutil
import struct
import sys

from PIL import Image

PAINT_PARENTS = ("M_CarExterior_Master", "M_CarPaint", "CarPaint")


def index_files(root, suffix):
    """Map each file stem under `root` with `suffix` to its path."""
    found = {}
    for base, _, files in os.walk(root):
        for name in files:
            if name.endswith(suffix):
                found.setdefault(name[: -len(suffix)], os.path.join(base, name))
    return found


def read_mat(path):
    """Return the `key=value` pairs of a UModel `.mat` file."""
    pairs = {}
    others = []
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.startswith("Other"):
            others.append(value)
        else:
            pairs[key] = value
    pairs["_others"] = others
    return pairs


def read_props(path):
    """Return the parent, the vector and the scalar parameters of a
    UModel `.props.txt` file, and whether it blends."""
    text = open(path, encoding="utf-8", errors="replace").read()
    parent = ""
    m = re.search(r"^Parent = \w+'([^']+)'", text, re.M)
    if m:
        parent = m.group(1)
    vectors = {}
    for name, r, g, b, a in re.findall(
        r"Name=([^}]+?) \}\s*ParameterValue = \{ R=([-\d.e]+), G=([-\d.e]+), B=([-\d.e]+), A=([-\d.e]+) \}",
        text,
    ):
        vectors[name.strip()] = [float(r), float(g), float(b), float(a)]
    scalars = {}
    for name, value in re.findall(
        r"Name=([^}]+?) \}\s*ParameterValue = ([-\d.e]+)\s", text
    ):
        scalars[name.strip()] = float(value)
    translucent = bool(re.search(r"BlendMode = BLEND_Translucent", text))
    return parent, vectors, scalars, translucent


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


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

    def texture(self, source, color):
        """Return the texture index for image file `source`, adding it."""
        key = (source, color)
        if key in self.images:
            return self.images[key]
        stem = os.path.splitext(os.path.basename(source))[0]
        name = stem + (".jpg" if color else ".png")
        os.makedirs(os.path.join(self.out_dir, "textures"), exist_ok=True)
        target = os.path.join(self.out_dir, "textures", name)
        image = Image.open(source)
        if max(image.size) > self.max_size:
            scale = self.max_size / max(image.size)
            image = image.resize(
                (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
                Image.LANCZOS,
            )
        if color:
            image.convert("RGB").save(target, quality=88)
        else:
            image.convert("RGB").save(target, optimize=True)
        self.gltf["images"].append({"uri": "textures/" + name})
        self.gltf["textures"].append({"sampler": 0, "source": len(self.gltf["images"]) - 1})
        index = len(self.gltf["textures"]) - 1
        self.images[key] = index
        return index


def by_name(name):
    """Return factors for a material UModel could not describe."""
    low = name.lower()
    if "glass" in low or "window" in low:
        return [0.08, 0.1, 0.12, 0.35], 0.0, 0.05, True
    if "rubber" in low or "tire" in low or "tyre" in low:
        return [0.03, 0.03, 0.03, 1], 0.0, 0.9, False
    if "chrome" in low or "polished" in low:
        return [0.9, 0.9, 0.9, 1], 1.0, 0.15, False
    if "alumin" in low or "metal" in low:
        return [0.6, 0.6, 0.62, 1], 1.0, 0.35, False
    if "black" in low:
        return [0.02, 0.02, 0.02, 1], 0.0, 0.6, False
    if "grey" in low or "gray" in low:
        return [0.25, 0.25, 0.25, 1], 0.0, 0.6, False
    if "light" in low:
        return [0.9, 0.9, 0.85, 1], 0.0, 0.2, False
    return [0.5, 0.5, 0.5, 1], 0.0, 0.6, False


def rebuild(package, material, mats, props, pngs, report):
    """Rewrite one glTF material from UModel's files."""
    name = material.get("name", "")
    pbr = {"metallicFactor": 0.0, "roughnessFactor": 0.6}
    factors = by_name(name)
    pbr["baseColorFactor"] = factors[0]
    pbr["metallicFactor"] = factors[1]
    pbr["roughnessFactor"] = factors[2]
    blend = factors[3]
    parent = ""
    if name in props:
        parent, vectors, scalars, translucent = read_props(props[name])
        blend = blend or translucent
        paint = any(p in parent for p in PAINT_PARENTS)
        for key in ("Base Color", "BaseColor", "Color", "Tint", "Paint Color"):
            if key in vectors:
                rgba = vectors[key]
                pbr["baseColorFactor"] = [rgba[0], rgba[1], rgba[2], 1.0]
                break
        if paint:
            pbr["metallicFactor"] = 0.5
            pbr["roughnessFactor"] = 0.3
        for key in ("Roughness", "roughness"):
            if key in scalars:
                pbr["roughnessFactor"] = max(0.0, min(1.0, scalars[key]))
        for key in ("Metallic", "Metalness", "metallic"):
            if key in scalars:
                pbr["metallicFactor"] = max(0.0, min(1.0, scalars[key]))
    else:
        paint = False
    # Glass shows through; its "diffuse" is a dirt or reflection mask,
    # which would paint the windows opaque.
    glass = "glass" in name.lower() or "glass" in parent.lower()
    if glass:
        blend = True
        pbr["baseColorFactor"] = [0.08, 0.1, 0.12, 0.35]
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 0.05
    if name in mats and not paint and not glass:
        entries = read_mat(mats[name])
        diffuse = entries.get("Diffuse")
        if diffuse and diffuse in pngs:
            pbr["baseColorTexture"] = {"index": package.texture(pngs[diffuse], True)}
            pbr["baseColorFactor"] = [1, 1, 1, pbr["baseColorFactor"][3]]
        normal = entries.get("Normal")
        if normal and normal in pngs and "flat" not in normal.lower():
            material["normalTexture"] = {"index": package.texture(pngs[normal], False)}
        packed = [o for o in entries["_others"] + [entries.get("Specular", "")] if o.lower().endswith("_orm")]
        if packed and packed[0] in pngs:
            index = package.texture(pngs[packed[0]], False)
            pbr["metallicRoughnessTexture"] = {"index": index}
            material["occlusionTexture"] = {"index": index}
            pbr["metallicFactor"] = 1.0
            pbr["roughnessFactor"] = 1.0
    # CARLA paints a car from its blueprint's color and lights its lamps
    # from its light state; the tags say which materials those are.
    lamps = "light" in name.lower() and not glass
    if paint or "bodywork" in name.lower():
        material["extras"] = {"carla": "paint"}
    elif lamps:
        # The lamps' texture is white at the front and red at the back;
        # UModel's translucency would make them ghosts.
        material["extras"] = {"carla": "lamps"}
        blend = False
        pbr["baseColorFactor"][3] = 1.0
    material["pbrMetallicRoughness"] = pbr
    if blend:
        material["alphaMode"] = "BLEND"
        pbr["baseColorFactor"][3] = min(pbr["baseColorFactor"][3], 0.4)
    material.pop("extensions", None)
    report.append((name, parent.rsplit("/", 1)[-1], sorted(k for k in pbr if k.endswith("Texture")) + sorted(k for k in material if k.endswith("Texture"))))


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
    lamp = [i for i, m in enumerate(gltf.get("materials", []))
            if m.get("extras", {}).get("carla") == "lamps"]
    if not lamp:
        return data
    xs = []
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            accessor = gltf["accessors"][primitive["attributes"]["POSITION"]]
            xs += [accessor["min"][0], accessor["max"][0]]
    middle = (min(xs) + max(xs)) / 2
    heads = lamp[0]
    gltf["materials"][heads] = {
        "name": "CarlaHeadLamps",
        "pbrMetallicRoughness": {"baseColorFactor": [0.85, 0.85, 0.8, 1], "metallicFactor": 0.0,
                                 "roughnessFactor": 0.15},
        "extras": {"carla": "heads"},
    }
    gltf["materials"].append({
        "name": "CarlaTailLamps",
        "pbrMetallicRoughness": {"baseColorFactor": [0.3, 0.01, 0.01, 1], "metallicFactor": 0.0,
                                 "roughnessFactor": 0.2},
        "extras": {"carla": "tails"},
    })
    tails = len(gltf["materials"]) - 1
    out = bytearray(data)
    for mesh in gltf["meshes"]:
        split = []
        for primitive in mesh["primitives"]:
            if primitive.get("material") not in lamp or "indices" not in primitive:
                split.append(primitive)
                continue
            indices, _ = _read(data, gltf, primitive["indices"])
            positions, _ = _read(data, gltf, primitive["attributes"]["POSITION"])
            parts = ([], [])
            for t in range(0, len(indices) - 2, 3):
                corners = indices[t:t + 3]
                x = sum(positions[3 * c] for c in corners) / 3
                parts[0 if x >= middle else 1].extend(corners)
            for material, part in ((heads, parts[0]), (tails, parts[1])):
                if not part:
                    continue
                out += b"\0" * (-len(out) % 4)
                gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(out),
                                            "byteLength": 4 * len(part), "target": 34963})
                out += struct.pack("<%dI" % len(part), *part)
                gltf["accessors"].append({"bufferView": len(gltf["bufferViews"]) - 1,
                                          "componentType": 5125, "count": len(part), "type": "SCALAR"})
                piece = dict(primitive)
                piece["indices"] = len(gltf["accessors"]) - 1
                piece["material"] = material
                split.append(piece)
        mesh["primitives"] = split
    gltf["buffers"][0]["byteLength"] = len(out)
    return bytes(out)


def dedupe_materials(gltf):
    """Keep one material of each name. The merge gives each primitive its
    own copy, so a car's glass is twenty materials."""
    first = {}
    kept = []
    new_index = []
    for material in gltf.get("materials", []):
        name = material.get("name", "")
        if name not in first:
            first[name] = len(kept)
            kept.append(material)
        new_index.append(first[name])
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            if "material" in primitive:
                primitive["material"] = new_index[primitive["material"]]
    if kept:
        gltf["materials"] = kept


def strip_skin(gltf, data):
    """Turn a skinned glTF into plain meshes at its bind pose, and return
    the buffer without the bytes nothing reads any more.

    A CARLA vehicle is a skeletal mesh whose bones only turn the wheels
    and open the doors. At rest its bones are where the mesh was bound,
    and the mesh's node is the origin, so the vertices already stand
    where the car stands. The skin, the joints and the weights go; the
    bone nodes stay as named markers of the wheels.
    """
    for node in gltf["nodes"]:
        node.pop("skin", None)
    gltf.pop("skins", None)
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]
            # Unreal's vertex colors are masks for its materials, not
            # colors: glTF would multiply them into the paint.
            for key in [k for k in attributes if k.startswith(("JOINTS_", "WEIGHTS_", "COLOR_"))]:
                del attributes[key]
    # Keep the accessors a primitive reads, and the views they read.
    used = []
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            used += list(primitive["attributes"].values())
            if "indices" in primitive:
                used.append(primitive["indices"])
    accessor_of = {old: new for new, old in enumerate(sorted(set(used)))}
    accessors = [gltf["accessors"][old] for old in sorted(accessor_of)]
    view_of = {}
    views = []
    out = bytearray()
    for accessor in accessors:
        old = accessor["bufferView"]
        if old not in view_of:
            view = dict(gltf["bufferViews"][old])
            start = view.get("byteOffset", 0)
            out += b"\0" * (-len(out) % 4)
            chunk = data[start:start + view["byteLength"]]
            view["byteOffset"] = len(out)
            out += chunk
            view_of[old] = len(views)
            views.append(view)
        accessor["bufferView"] = view_of[old]
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            primitive["attributes"] = {k: accessor_of[v] for k, v in primitive["attributes"].items()}
            if "indices" in primitive:
                primitive["indices"] = accessor_of[primitive["indices"]]
    gltf["accessors"] = accessors
    gltf["bufferViews"] = views
    out += b"\0" * (-len(out) % 4)
    gltf["buffers"] = [{"uri": gltf["buffers"][0]["uri"], "byteLength": len(out)}]
    return bytes(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("export_root")
    parser.add_argument("mesh")
    parser.add_argument("out_dir")
    parser.add_argument("name")
    parser.add_argument("--max-size", type=int, default=1024)
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
    with open(os.path.join(args.out_dir, args.name + ".bin"), "wb") as out:
        out.write(data)
    gltf["buffers"][0]["uri"] = args.name + ".bin"
    gltf["asset"]["generator"] = "UE Viewer (umodel) build 1590, materials by carla_gltf_fix.py"
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
