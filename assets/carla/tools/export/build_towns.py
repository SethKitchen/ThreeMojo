# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Bake each CARLA town into one glTF package: every building, street,
plant and prop where the town places it.

`export_towns.py` exports the meshes and the materials. This script reads
each town's layout, lowers each mesh to a triangle budget once, places
every copy in the three.js frame the renderer uses (meters, plus y up:
three.js x, y and z are CARLA's x, z and y), and merges the copies by
tile, by kind and by material, so the renderer culls a tile at a time
and draws few meshes. Each mesh node names its kind in its extras, as
`{"carla_kind": "building"}`, so the renderer can leave out what it
draws itself.

    python build_towns.py [TOWN ...] [--max-size 512] [--tile 64]

It writes `town_packages/carla.town.<town>/`, with the town's OpenDRIVE
map, `<town>.xodr`, beside the glTF. The package names no engine
and no engine path: `check_clean` refuses one that does.
"""

import argparse
import json
import os
import re
import shutil
import struct
import sys
import zlib

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import carla_gltf_fix as fix  # noqa: E402

BASE = os.path.abspath(os.environ.get("CARLA_EXPORT_DIR", "."))
RAW = os.path.join(BASE, "raw_town")
LAYOUT = os.path.join(BASE, "layout")
MAPS = os.path.join(BASE, "release", "CarlaUE4", "Content", "Carla", "Maps", "OpenDrive")
OUT = os.path.join(BASE, "town_packages")
TOWNS = ["Town01", "Town02", "Town03", "Town04", "Town05", "Town10HD"]

# The folder under /Game/Carla/Static/ -> the kind the package tags.
KINDS = {
    "Building": "building", "Bridge": "building", "Wall": "wall", "Fence": "fence",
    "GuardRail": "fence", "Road": "road", "RoadLine": "road_line", "SideWalk": "sidewalk",
    "Ground": "ground", "Terrain": "terrain", "Water": "water", "RailTrack": "rail",
    "Vegetation": "vegetation", "Pole": "pole", "StreetLight": "pole",
    "TrafficLight": "traffic_light", "TrafficSign": "traffic_sign",
    "Car": "parked_vehicle", "Truck": "parked_vehicle", "Motorcycle": "parked_vehicle",
    "Bicycle": "parked_vehicle", "Bus": "parked_vehicle",
    "Static": "prop", "Dynamic": "prop", "Other": "prop",
}
# Folders the renderer draws itself, or that are not scenery.
SKIP = {"Sky", "Particles", "Pedestrian", "Hair", "CubeMaps", "HDRi", "Decals", "TestWindowsParts"}
# Engine materials: the grid marks a brush's hidden faces; the basic
# shape's material is plain.
GRID = "WorldGridMaterial"
PLAIN = "BasicShapeMaterial"
# The levels of detail: 0 near, 1 far.
LODS = (0, 1)
# The most triangles a town keeps of each kind, near and far.
CAPS = {
    "vegetation": (1_200_000, 300_000),
    "building": (1_500_000, 300_000),
    "fence": (250_000, 50_000),
    "pole": (250_000, 50_000),
    "prop": (300_000, 1),
    "parked_vehicle": (200_000, 1),
    "traffic_light": (100_000, 20_000),
}
# The folder whose meshes are trees, whose far level is an impostor.
TREES = "/Vegetation/Trees/"
# One grass leaf in this many is kept: the ground's texture is the lawn.
GRASS_KEEP = 10
# Words that must not appear in a package.
UNCLEAN = re.compile(r"unreal|\bue4\b|\bue5\b|epic games|umodel|/game/|/engine/|\.uasset|\.umap", re.I)
# Triangles each mesh adds to the package, for the report.
STATS = {}
CREDIT = "CARLA Team, CARLA Simulator 0.9.16, CC-BY 4.0 (https://carla.org)"


def object_path(full_name):
    """Return (`Class`, `/Game/A/B`, `B`) from UE4SS's `Class /Game/A/B.B`."""
    cls, path = full_name.split(" ", 1)
    package, _, name = path.rpartition(".")
    return cls, package, name.rsplit(":", 1)[-1].rsplit(".", 1)[-1]


def kind_of(mesh_path):
    """Return a mesh's kind, None to leave it out."""
    parts = mesh_path.split("/")
    if mesh_path.startswith("/Engine/"):
        return "prop"
    folder = parts[4] if len(parts) > 4 and parts[3] == "Static" else ""
    if folder in SKIP:
        return None
    return KINDS.get(folder, "prop")


def budget(kind, triangles, mesh_path):
    """Return the most triangles one copy of a mesh keeps."""
    if kind == "building":
        return max(min(triangles, 2500), triangles // 6)
    if kind == "parked_vehicle":
        return min(triangles, 2500)
    if kind == "vegetation":
        return min(triangles, 800 if "/Bushes/" in mesh_path else 4000)
    if kind in ("pole", "traffic_light", "traffic_sign"):
        return min(triangles, max(400, triangles // 6))
    return min(triangles, max(600, triangles // 4))


# ---- Transforms ------------------------------------------------------------

SWAP = numpy.array([[1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]])


def rotation_rows(pitch, yaw, roll):
    """Return Unreal's rotation matrix for a rotator, in its row-vector
    convention (a point is a row, multiplied on the left)."""
    p, y, r = numpy.radians([pitch, yaw, roll])
    sp, cp, sy, cy, sr, cr = numpy.sin(p), numpy.cos(p), numpy.sin(y), numpy.cos(y), numpy.sin(r), numpy.cos(r)
    return numpy.array([
        [cp * cy, cp * sy, sp],
        [sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, -sr * cp],
        [-(cr * sp * cy + sr * sy), cy * sr - cr * sp * sy, cr * cp],
    ])


def component_rows(row):
    """Return a component's world matrix in Unreal's row-vector
    convention, in centimeters: scale, then rotate, then move."""
    matrix = numpy.eye(4)
    matrix[:3, :3] = numpy.diag(row["scale"]) @ rotation_rows(*row["rotation"])
    matrix[3, :3] = row["location"]
    return matrix


def to_three(rows):
    """Return (A, t): an Unreal row-vector matrix as the map that takes a
    point of an exported mesh (three.js frame, meters) to the world
    (three.js frame, meters): world = A @ point + t."""
    linear = SWAP @ rows[:3, :3].T @ SWAP
    return linear, SWAP @ rows[3, :3] / 100.0


def hermite(p0, t0, p1, t1, a):
    """Return the point and the unit direction of a Hermite curve."""
    a2, a3 = a * a, a * a * a
    point = ((2 * a3 - 3 * a2 + 1)[:, None] * p0 + (a3 - 2 * a2 + a)[:, None] * t0
             + (-2 * a3 + 3 * a2)[:, None] * p1 + (a3 - a2)[:, None] * t1)
    direction = ((6 * a2 - 6 * a)[:, None] * p0 + (3 * a2 - 4 * a + 1)[:, None] * t0
                 + (-6 * a2 + 6 * a)[:, None] * p1 + (3 * a2 - 2 * a)[:, None] * t1)
    length = numpy.linalg.norm(direction, axis=1, keepdims=True)
    return point, direction / numpy.maximum(length, 1e-9)


def bend(points, normals, spline):
    """Bend mesh points (three.js frame, meters) along a spline mesh
    component's curve, as Unreal's spline mesh does, and return them in
    the component's frame, in Unreal's axes and centimeters."""
    local = points[:, [0, 2, 1]] * 100.0
    axis = int(spline["forward_axis"])
    along = local[:, axis]
    low, high = along.min(), along.max()
    alpha = (along - low) / max(high - low, 1e-6)
    start, end = numpy.array(spline["start"]), numpy.array(spline["end"])
    position, direction = hermite(start, numpy.array(spline["start_tangent"]), end,
                                  numpy.array(spline["end_tangent"]), alpha)
    up = numpy.array([0.0, 0.0, 1.0])
    base_x = numpy.cross(up, direction)
    base_x /= numpy.maximum(numpy.linalg.norm(base_x, axis=1, keepdims=True), 1e-9)
    base_y = numpy.cross(direction, base_x)
    roll = spline["start_roll"] + (spline["end_roll"] - spline["start_roll"]) * alpha
    cos, sin = numpy.cos(roll)[:, None], numpy.sin(roll)[:, None]
    x_vec = cos * base_x - sin * base_y
    y_vec = cos * base_y + sin * base_x
    scale = (numpy.array(spline["start_scale"])[None, :]
             + (numpy.array(spline["end_scale"]) - numpy.array(spline["start_scale"]))[None, :] * alpha[:, None])
    # The two axes across the curve, in the order Unreal takes them.
    across = {0: (1, 2), 1: (2, 0), 2: (0, 1)}[axis]
    out = (position + (local[:, across[0]] * scale[:, 0])[:, None] * x_vec
           + (local[:, across[1]] * scale[:, 1])[:, None] * y_vec)
    # Normals: the same frame without the curve's stretch.
    n = normals[:, [0, 2, 1]]
    frames = {0: (direction, x_vec, y_vec), 1: (y_vec, direction, x_vec), 2: (x_vec, y_vec, direction)}[axis]
    bent = n[:, 0:1] * frames[0] + n[:, 1:2] * frames[1] + n[:, 2:3] * frames[2]
    return out, bent


# ---- Meshes ----------------------------------------------------------------

def read_gltf(path):
    """Return a UModel glTF's primitives: positions, normals, texture
    coordinates, triangles and material name, as numpy arrays."""
    gltf = json.load(open(path, encoding="utf-8"))
    data = open(os.path.join(os.path.dirname(path), gltf["buffers"][0]["uri"]), "rb").read()

    def array(index):
        accessor = gltf["accessors"][index]
        view = gltf["bufferViews"][accessor["bufferView"]]
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
        dtype = {5121: numpy.uint8, 5123: numpy.uint16, 5125: numpy.uint32, 5126: numpy.float32}[accessor["componentType"]]
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        values = numpy.frombuffer(data, dtype=dtype, count=accessor["count"] * width, offset=start)
        return values.reshape(-1, width) if width > 1 else values

    primitives = []
    for mesh in gltf["meshes"]:
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]
            positions = array(attributes["POSITION"]).astype(numpy.float64)
            normals = (array(attributes["NORMAL"]).astype(numpy.float64) if "NORMAL" in attributes
                       else numpy.tile([0.0, 1.0, 0.0], (len(positions), 1)))
            uvs = (array(attributes["TEXCOORD_0"]).astype(numpy.float64) if "TEXCOORD_0" in attributes
                   else numpy.zeros((len(positions), 2)))
            triangles = array(primitive["indices"]).astype(numpy.int64).reshape(-1, 3)
            name = gltf["materials"][primitive["material"]].get("name", "") if "material" in primitive else ""
            primitives.append({"positions": positions, "normals": normals, "uvs": uvs,
                               "triangles": triangles, "material": name})
    return primitives


def cube():
    """Return a one-meter box centered on its origin: the engine's cube,
    drawn from scratch."""
    positions, normals, uvs, triangles = [], [], [], []
    for axis in range(3):
        for sign in (-1.0, 1.0):
            normal = numpy.zeros(3)
            normal[axis] = sign
            u, v = numpy.zeros(3), numpy.zeros(3)
            u[(axis + 1) % 3], v[(axis + 2) % 3] = 1.0, 1.0
            if sign < 0:
                u, v = v, u
            base = len(positions)
            for du, dv in ((0, 0), (1, 0), (1, 1), (0, 1)):
                positions.append(0.5 * normal + (du - 0.5) * u + (dv - 0.5) * v)
                normals.append(normal)
                uvs.append((du, dv))
            triangles += [(base, base + 1, base + 2), (base, base + 2, base + 3)]
    return [{"positions": numpy.array(positions), "normals": numpy.array(normals), "uvs": numpy.array(uvs, float),
             "triangles": numpy.array(triangles), "material": PLAIN}]


def area_normals(points, faces):
    """Return each vertex's normal: its faces' normals, weighted by area."""
    corners = points[faces]
    face = numpy.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
    normals = numpy.zeros_like(points)
    for k in range(3):
        numpy.add.at(normals, faces[:, k], face)
    length = numpy.linalg.norm(normals, axis=1, keepdims=True)
    return numpy.where(length > 1e-12, normals / numpy.maximum(length, 1e-12), [0.0, 1.0, 0.0])


def simplify(primitive, target, borders=True, small=False):
    """Return a primitive lowered to about `target` triangles by quadric
    collapses. With `borders`, its open edges (the texture seams) stay in
    place; the far level of detail lets them move, since a seam that
    opens a crack does not show at a distance."""
    import fast_simplification
    faces = primitive["triangles"]
    floor = fix.KEEP // 2 if borders and not small else 8
    if len(faces) <= max(target, floor) or (borders and not small and len(faces) < fix.KEEP):
        return primitive
    points = primitive["positions"]
    _, _, collapses = fast_simplification.simplify(
        points, faces.astype(numpy.int32), target_count=max(floor, target),
        return_collapses=True, preserve_border=borders)
    new_points, new_faces, mapping = fast_simplification.replay_simplification(
        points, faces.astype(numpy.int32), collapses)
    if len(new_faces) == 0:
        return primitive
    source = numpy.zeros(len(new_points), dtype=numpy.int64)
    source[mapping[::-1]] = numpy.arange(len(mapping))[::-1]
    return {"positions": new_points, "normals": area_normals(new_points, new_faces),
            "uvs": primitive["uvs"][source], "triangles": new_faces.astype(numpy.int64),
            "material": primitive["material"]}


def thin_cards(primitive, keep, seed):
    """Return a cut-out primitive with about `keep` of its cards, each
    kept card grown about its center so the canopy stays as full. A card
    is a piece of connected triangles: a leaf, or a spray of leaves."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    faces = primitive["triangles"]
    count = len(primitive["positions"])
    rows = numpy.concatenate([faces[:, 0], faces[:, 1], faces[:, 2]])
    cols = numpy.concatenate([faces[:, 1], faces[:, 2], faces[:, 0]])
    graph = coo_matrix((numpy.ones(len(rows)), (rows, cols)), shape=(count, count))
    pieces, label = connected_components(graph, directed=False)
    if pieces < 8:
        return primitive
    chosen = numpy.random.default_rng(seed).random(pieces) < keep
    face_piece = label[faces[:, 0]]
    faces = faces[chosen[face_piece]]
    if len(faces) == 0:
        return primitive
    used = numpy.unique(faces)
    remap = numpy.full(count, -1)
    remap[used] = numpy.arange(len(used))
    points = primitive["positions"][used]
    piece = label[used]
    sums = numpy.zeros((pieces, 3))
    numpy.add.at(sums, piece, points)
    centers = sums / numpy.maximum(numpy.bincount(piece, minlength=pieces), 1)[:, None]
    grow = min(2.0, 1.0 / numpy.sqrt(max(keep, 1e-3)))
    points = centers[piece] + (points - centers[piece]) * grow
    return {"positions": points, "normals": primitive["normals"][used], "uvs": primitive["uvs"][used],
            "triangles": remap[faces], "material": primitive["material"]}


# ---- Impostors -------------------------------------------------------------

# Texels a side of an impostor's view, and samples each covered texel takes.
IMPOSTOR_SIZE = 256
IMPOSTOR_SAMPLES = 4
# The light an impostor's texels are shaded by, three.js frame: high and
# from the side, as the sun is most of the day.
IMPOSTOR_LIGHT = numpy.array([0.35, 0.85, 0.4]) / numpy.linalg.norm([0.35, 0.85, 0.4])


def _albedo(library, material):
    """Return a material's base color image as float RGBA, and its
    factor."""
    from PIL import Image
    entry = library.gltf["materials"][material]
    pbr = entry.get("pbrMetallicRoughness", {})
    factor = numpy.array(pbr.get("baseColorFactor", [1, 1, 1, 1]), dtype=numpy.float64)
    texture = pbr.get("baseColorTexture")
    if texture is None:
        return None, factor
    source = library.gltf["textures"][texture["index"]]["source"]
    path = os.path.join(library.package.out_dir, library.gltf["images"][source]["uri"])
    return numpy.asarray(Image.open(path).convert("RGBA"), dtype=numpy.float64) / 255.0, factor


def _splat(parts, library, across, left, width, top, height, rows):
    """Return one view of a tree, drawn across axis `across` (0 for x,
    2 for z) and down y from `top`: RGBA floats, `rows` by
    `IMPOSTOR_SIZE` texels. Each triangle is sampled at random points, as
    many as it covers texels times `IMPOSTOR_SAMPLES`, and the nearest
    sample that the cut-out keeps colors each texel."""
    depth_axis = 2 if across == 0 else 0
    scale_u = IMPOSTOR_SIZE / max(width, 1e-6)
    scale_v = rows / max(height, 1e-6)
    rng = numpy.random.default_rng(7)
    xs, ys, zs, colors = [], [], [], []
    for part, material in parts:
        image, factor = _albedo(library, material)
        entry = library.gltf["materials"][material]
        cut = entry.get("alphaCutoff", 0.5)
        masked = entry.get("alphaMode") == "MASK"
        tri = part["triangles"]
        corners = part["positions"][tri]
        u = (corners[:, :, across] - left) * scale_u
        v = (top - corners[:, :, 1]) * scale_v
        area = 0.5 * numpy.abs((u[:, 1] - u[:, 0]) * (v[:, 2] - v[:, 0]) - (u[:, 2] - u[:, 0]) * (v[:, 1] - v[:, 0]))
        counts = numpy.minimum(numpy.maximum(1, numpy.ceil(area * IMPOSTOR_SAMPLES)), 4096).astype(numpy.int64)
        owner = numpy.repeat(numpy.arange(len(corners)), counts)
        a, b = rng.random(len(owner)), rng.random(len(owner))
        flip = a + b > 1
        a[flip], b[flip] = 1 - a[flip], 1 - b[flip]
        w = numpy.stack([1 - a - b, a, b], axis=1)
        depth = numpy.einsum("nk,nk->n", w, corners[owner][:, :, depth_axis])
        uv = numpy.einsum("nk,nkd->nd", w, part["uvs"][tri][owner])
        normal = numpy.einsum("nk,nkd->nd", w, part["normals"][tri][owner])
        normal /= numpy.maximum(numpy.linalg.norm(normal, axis=1, keepdims=True), 1e-9)
        if image is None:
            rgba = numpy.tile(factor, (len(owner), 1))
        else:
            h, wd = image.shape[:2]
            px = (numpy.mod(uv[:, 0], 1.0) * (wd - 1)).astype(numpy.int64)
            py = (numpy.mod(uv[:, 1], 1.0) * (h - 1)).astype(numpy.int64)
            rgba = image[py, px] * factor
        keep = rgba[:, 3] >= cut if masked else numpy.ones(len(owner), dtype=bool)
        rgba[:, :3] *= (0.45 + 0.55 * numpy.abs(normal @ IMPOSTOR_LIGHT))[:, None]
        xs.append(numpy.einsum("nk,nk->n", w, u[owner])[keep])
        ys.append(numpy.einsum("nk,nk->n", w, v[owner])[keep])
        zs.append(depth[keep])
        colors.append(rgba[keep, :3])
    out = numpy.zeros((rows, IMPOSTOR_SIZE, 4))
    if sum(len(x) for x in xs) == 0:
        return out
    x = numpy.concatenate(xs).astype(numpy.int64)
    y = numpy.concatenate(ys).astype(numpy.int64)
    z = numpy.concatenate(zs)
    color = numpy.concatenate(colors)
    inside = (x >= 0) & (x < IMPOSTOR_SIZE) & (y >= 0) & (y < rows)
    x, y, z, color = x[inside], y[inside], z[inside], color[inside]
    # The nearest sample of each texel: the view looks down the depth
    # axis from its positive end.
    texel = y * IMPOSTOR_SIZE + x
    order = numpy.lexsort((-z, texel))
    sorted_texel = texel[order]
    first = numpy.ones(len(order), dtype=bool)
    first[1:] = sorted_texel[1:] != sorted_texel[:-1]
    chosen = order[first]
    out[y[chosen], x[chosen], :3] = color[chosen]
    out[y[chosen], x[chosen], 3] = 1.0
    return out


def impostor(parts, library, out_dir, name):
    """Return a tree's far level, two quads that cross on its trunk, each
    showing a picture of the tree drawn from its near level; and the
    picture's material. `parts` are the tree's primitives, each with its
    material's index."""
    from PIL import Image
    points = numpy.concatenate([p["positions"] for p, _ in parts])
    low, high = points.min(axis=0), points.max(axis=0)
    height = high[1] - low[1]
    views = []
    for across in (0, 2):
        width = high[across] - low[across]
        rows = max(8, int(round(IMPOSTOR_SIZE * height / max(width, 1e-6))))
        view = _splat(parts, library, across, low[across], width, high[1], height, rows)
        # A texel the tree does not cover takes the mean color of those it
        # does, so filtering at the edge of a leaf does not darken it.
        covered = view[:, :, 3] > 0
        if covered.any():
            view[~covered, :3] = view[covered, :3].mean(axis=0)
        picture = Image.fromarray((numpy.clip(view, 0, 1) * 255).astype(numpy.uint8), "RGBA")
        views.append(picture.resize((IMPOSTOR_SIZE, IMPOSTOR_SIZE), Image.LANCZOS))
    atlas = Image.new("RGBA", (2 * IMPOSTOR_SIZE, IMPOSTOR_SIZE))
    atlas.paste(views[0], (0, 0))
    atlas.paste(views[1], (IMPOSTOR_SIZE, 0))
    tag = "impostor_%08x" % zlib.crc32(name.encode())
    os.makedirs(os.path.join(out_dir, "textures"), exist_ok=True)
    atlas.save(os.path.join(out_dir, "textures", tag + ".png"), optimize=True)
    gltf = library.gltf
    gltf["images"].append({"uri": "textures/" + tag + ".png"})
    gltf["textures"].append({"sampler": 0, "source": len(gltf["images"]) - 1})
    gltf["materials"].append({
        "name": tag,
        "pbrMetallicRoughness": {"baseColorTexture": {"index": len(gltf["textures"]) - 1},
                                 "metallicFactor": 0.0, "roughnessFactor": 0.9},
        "alphaMode": "MASK", "alphaCutoff": 0.5, "doubleSided": True})
    material = len(gltf["materials"]) - 1
    center = (low + high) / 2
    positions, uvs = [], []
    # Across x at the trunk's z, then across z at its x; each quad takes
    # its half of the atlas, left to right as its view was drawn.
    for across, half in ((0, 0.0), (2, 0.5)):
        start, end = center.copy(), center.copy()
        start[across], end[across] = low[across], high[across]
        for base, y, u, v in ((start, low[1], 0.0, 1.0), (end, low[1], 0.5, 1.0),
                              (end, high[1], 0.5, 0.0), (start, high[1], 0.0, 0.0)):
            positions.append((base[0], y, base[2]))
            uvs.append((half + u, v))
    # Lit from above, as a crown is: the picture holds its own shading.
    return {"positions": numpy.array(positions), "normals": numpy.tile([0.0, 1.0, 0.0], (8, 1)),
            "uvs": numpy.array(uvs), "triangles": numpy.array([[0, 1, 2], [0, 2, 3], [4, 5, 6], [4, 6, 7]]),
            "material": tag}, material


# ---- Materials -------------------------------------------------------------

class Textures(fix.Package):
    """Every texture as JPEG, a normal or a packed map too: a town has
    hundreds of them. A cut-out keeps its PNG, for its alpha."""

    def texture(self, source, color):
        return fix.Package.texture(self, source, True)


class Library:
    """The package's materials and textures, built from UModel's files."""

    def __init__(self, out_dir, max_size):
        self.gltf = {"materials": []}
        self.package = Textures(self.gltf, out_dir, max_size)
        self.mats = fix.index_files(RAW, ".mat")
        self.props = fix.index_files(RAW, ".props.txt")
        self.pngs = fix.index_files(RAW, ".png")
        self.index = {}
        self.masked = {}

    def material(self, name):
        """Return the glTF index of the material named `name`."""
        if name in self.index:
            return self.index[name]
        material = {"name": name}
        if name == PLAIN or not name or name.startswith("dummy_material"):
            material["name"] = "plain"
            material["pbrMetallicRoughness"] = {"baseColorFactor": [0.5, 0.5, 0.5, 1], "metallicFactor": 0.0,
                                                "roughnessFactor": 0.7}
        else:
            fix.rebuild(self.package, material, self.mats, self.props, self.pngs, [])
            # A vehicle's paint and lamp tags do not apply to a town.
            material.pop("extras", None)
        self.gltf["materials"].append(material)
        self.index[name] = len(self.gltf["materials"]) - 1
        self.masked[name] = material.get("alphaMode") == "MASK"
        return self.index[name]


def slot_materials(row, primitives):
    """Return each primitive's material name for one component: the
    component's material for that slot, by name where UModel named it and
    by position otherwise. A runtime material instance falls back to the
    mesh's own material for the slot."""
    slots = [object_path(m) if m else None for m in row["materials"]]
    names = [s[2] if s else None for s in slots]
    chosen = []
    for i, primitive in enumerate(primitives):
        own = primitive["material"]
        slot = names.index(own) if own in names else (i if i < len(slots) else None)
        if slot is None or slots[slot] is None:
            chosen.append(own)
            continue
        cls, _, name = slots[slot]
        chosen.append(own if cls == "MaterialInstanceDynamic" else name)
    return chosen


# ---- Building --------------------------------------------------------------

def far_budget(kind, triangles, mesh_path):
    """Return the most triangles one copy keeps in the far level of
    detail, 0 to leave it out there: what is small at a distance goes."""
    low = mesh_path.lower()
    if kind in ("prop", "parked_vehicle", "traffic_sign"):
        return 0
    if kind == "vegetation":
        return min(triangles, max(150, triangles // 5)) if "/trees/" in low else 0
    if kind == "building":
        return max(min(triangles, 600), triangles // 25)
    if kind in ("pole", "traffic_light"):
        return 0 if "glass" in low or "leds" in low else min(triangles, max(120, triangles // 12))
    if kind in ("wall", "fence"):
        return min(triangles, max(150, triangles // 10))
    return budget(kind, triangles, mesh_path)


def limit_of(kind, total, mesh_path, lod):
    """Return the most triangles one copy of a mesh keeps at a level of
    detail, before the town's cap for its kind."""
    return budget(kind, total, mesh_path) if lod == 0 else far_budget(kind, total, mesh_path)


def lower(primitive, kind, mesh_path, index, total, masked, lod, factor=1.0):
    """Return one primitive of a mesh at a level of detail, or None.
    `factor` is the share of its budget that the town's cap for its kind
    leaves it."""
    limit = limit_of(kind, total, mesh_path, lod) * factor
    if limit == 0:
        return None
    share = limit / max(total, 1)
    if masked:
        keep = min(1.0, share * 1.15)
        seed = zlib.crc32(mesh_path.encode()) + index + 7919 * lod
        return thin_cards(primitive, keep, seed) if keep < 0.95 else primitive
    # A part under KEEP triangles stays whole unless the town's cap asks
    # for less: a guardrail is thousands of small segments.
    return simplify(primitive, int(len(primitive["triangles"]) * share), borders=lod == 0, small=factor < 1.0)


def place(part, row, rows):
    """Return a primitive's points, normals and triangles placed by one
    copy's world matrix, in the three.js frame."""
    if "spline" in row:
        local, normals = bend(part["positions"], part["normals"], row["spline"])
        world = local @ rows[:3, :3] + rows[3, :3]
        points = world[:, [0, 2, 1]] / 100.0
        normals = (normals @ numpy.linalg.inv(rows[:3, :3]).T)[:, [0, 2, 1]]
        flip = numpy.linalg.det(rows[:3, :3]) < 0
    else:
        linear, move = to_three(rows)
        points = part["positions"] @ linear.T + move
        normals = part["normals"] @ numpy.linalg.inv(linear)
        flip = numpy.linalg.det(linear) < 0
    length = numpy.linalg.norm(normals, axis=1, keepdims=True)
    normals = normals / numpy.maximum(length, 1e-12)
    return points, normals, (part["triangles"][:, ::-1] if flip else part["triangles"])


def rows_of(town):
    with open(os.path.join(LAYOUT, town + ".jsonl"), encoding="utf-8") as lines:
        return [json.loads(line) for line in lines]


def placements(row):
    """Return each copy's Unreal row-vector world matrix."""
    component = component_rows(row)
    if "instances" not in row:
        return [component]
    out = []
    for flat in row["instances"]:
        instance = numpy.array(flat, dtype=numpy.float64).reshape(4, 4)
        out.append(instance @ component)
    return out


def build(town, max_size, tile):
    """Write one town's package, and return the triangle counts of its
    two levels of detail and its node count."""
    name = "carla.town." + town.lower()
    out_dir = os.path.join(OUT, name)
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir)
    library = Library(out_dir, max_size)
    meshes = {}
    lowered = {}
    groups = {}
    grass = 0
    jobs = []
    planned = {}
    for row in rows_of(town):
        if not row["visible"]:
            continue
        _, mesh_path, _ = object_path(row["mesh"])
        kind = kind_of(mesh_path)
        if kind is None:
            continue
        if mesh_path.startswith("/Engine/") and not mesh_path.endswith("/Cube"):
            continue
        if mesh_path not in meshes:
            if mesh_path.startswith("/Engine/"):
                meshes[mesh_path] = cube()
            else:
                path = os.path.join(RAW, *mesh_path[len("/Game/"):].split("/")) + ".gltf"
                meshes[mesh_path] = read_gltf(path) if os.path.exists(path) else []
        primitives = meshes[mesh_path]
        if not primitives:
            continue
        copies = placements(row)
        if "/Vegetation/Grass/" in mesh_path:
            kept = [c for i, c in enumerate(copies) if (grass + i) % GRASS_KEEP == 0]
            grass += len(copies)
            copies = kept
        total = sum(len(p["triangles"]) for p in primitives)
        for lod in LODS:
            planned[(kind, lod)] = planned.get((kind, lod), 0) + limit_of(kind, total, mesh_path, lod) * len(copies)
        jobs.append((row, mesh_path, kind, primitives, copies))
    # Each kind gives up the same share of every mesh's budget to keep
    # under the town's cap: a forest of eight thousand pines thins them all.
    factors = {key: min(1.0, CAPS[key[0]][key[1]] / count) if key[0] in CAPS and count else 1.0
               for key, count in planned.items()}
    for row, mesh_path, kind, primitives, copies in jobs:
        names = slot_materials(row, primitives)
        for index, (primitive, material_name) in enumerate(zip(primitives, names)):
            if material_name == GRID:
                continue
            material = library.material(material_name)
            total = sum(len(p["triangles"]) for p in primitives)
            for lod in LODS:
                part_material = material
                if lod == 1 and TREES in mesh_path:
                    # A tree's far level is its impostor, drawn once for
                    # all its primitives.
                    if index != 0:
                        continue
                    key = (mesh_path, "impostor")
                    if key not in lowered:
                        parts = [(p, library.material(n)) for p, n in zip(primitives, names) if n != GRID]
                        lowered[key] = impostor(parts, library, out_dir, mesh_path)
                    part, part_material = lowered[key]
                else:
                    key = (mesh_path, index, material_name, lod)
                    if key not in lowered:
                        lowered[key] = lower(primitive, kind, mesh_path, index, total,
                                             library.masked[material_name], lod, factors[(kind, lod)])
                    part = lowered[key]
                if part is None:
                    continue
                STATS[mesh_path] = STATS.get(mesh_path, 0) + len(part["triangles"]) * len(copies)
                for rows in copies:
                    points, normals, triangles = place(part, row, rows)
                    # The copy's origin picks its tile, so both levels of
                    # detail of a copy fall in the same tile.
                    origin = rows[3, :3] / 100.0
                    cell = (int(numpy.floor(origin[0] / tile)), int(numpy.floor(origin[1] / tile)))
                    group = groups.setdefault((lod, kind, cell, part_material), [[], [], [], [], 0])
                    group[0].append(points.astype(numpy.float32))
                    group[1].append(normals.astype(numpy.float32))
                    group[2].append(part["uvs"].astype(numpy.float32))
                    group[3].append(triangles + group[4])
                    group[4] += len(points)
    # The town's own road network, so a package brings the map it stands on.
    shutil.copy(os.path.join(MAPS, town + ".xodr"), os.path.join(out_dir, town + ".xodr"))
    return write(town, name, out_dir, library, groups)


def write(town, name, out_dir, library, groups):
    """Write the glTF and its buffer, and return the triangle counts of
    the two levels of detail and the node count."""
    gltf = library.gltf
    gltf["asset"] = {"version": "2.0", "generator": "ThreeMojo build_towns.py", "copyright": CREDIT}
    gltf["scene"] = 0
    gltf["nodes"], gltf["meshes"], gltf["accessors"], gltf["bufferViews"] = [], [], [], []
    blob = bytearray()

    def add(values, component, kind, target):
        while len(blob) % 4:
            blob.append(0)
        data = values.tobytes()
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        accessor = {"bufferView": len(gltf["bufferViews"]) - 1, "componentType": component,
                    "count": len(values) if values.ndim > 1 else values.size, "type": kind}
        if kind == "VEC3" and target == 34962:
            accessor["min"] = values.min(axis=0).tolist()
            accessor["max"] = values.max(axis=0).tolist()
        gltf["accessors"].append(accessor)
        return len(gltf["accessors"]) - 1

    triangles = [0, 0]
    for (lod, kind, cell, material), group in sorted(groups.items(), key=lambda item: item[0]):
        faces = numpy.concatenate(group[3]).astype(numpy.uint32)
        triangles[lod] += len(faces)
        primitive = {"attributes": {"POSITION": add(numpy.concatenate(group[0]), 5126, "VEC3", 34962),
                                    "NORMAL": add(numpy.concatenate(group[1]), 5126, "VEC3", 34962),
                                    "TEXCOORD_0": add(numpy.concatenate(group[2]), 5126, "VEC2", 34962)},
                     "indices": add(faces.reshape(-1), 5125, "SCALAR", 34963), "material": material}
        gltf["meshes"].append({"primitives": [primitive]})
        gltf["nodes"].append({"name": "%s_%d_%d_lod%d" % (kind, cell[0], cell[1], lod), "mesh": len(gltf["meshes"]) - 1,
                              "extras": {"carla_kind": kind, "carla_lod": lod}})
    gltf["scenes"] = [{"nodes": list(range(len(gltf["nodes"])))}]
    gltf["buffers"] = [{"byteLength": len(blob), "uri": name + ".bin"}]
    open(os.path.join(out_dir, name + ".bin"), "wb").write(blob)
    json.dump(gltf, open(os.path.join(out_dir, name + ".gltf"), "w", encoding="utf-8"), separators=(",", ":"))
    check_clean(out_dir)
    return triangles, len(gltf["nodes"])


def check_clean(out_dir):
    """Refuse a package that names an engine or an engine path, in its
    glTF or in a file name."""
    for base, _, files in os.walk(out_dir):
        for name in files:
            if UNCLEAN.search(name):
                raise SystemExit("unclean file name: " + os.path.join(base, name))
            if name.endswith(".gltf") or name.endswith(".xodr"):
                text = open(os.path.join(base, name), encoding="utf-8").read()
                found = UNCLEAN.search(text)
                if found:
                    raise SystemExit("unclean text in %s: %r" % (name, text[max(0, found.start() - 60):found.end() + 60]))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("towns", nargs="*")
    parser.add_argument("--max-size", type=int, default=512)
    parser.add_argument("--tile", type=float, default=64.0)
    parser.add_argument("--top", type=int, default=0, help="list the meshes that add the most triangles")
    args = parser.parse_args(argv)
    for town in args.towns or TOWNS:
        (near, far), nodes = build(town, args.max_size, args.tile)
        size = sum(os.path.getsize(os.path.join(b, f)) for b, _, fs in os.walk(os.path.join(OUT, "carla.town." + town.lower())) for f in fs)
        print("%s: %s triangles near, %s far, %d meshes, %.1f MB" % (town, format(near, ","), format(far, ","), nodes, size / 1e6), flush=True)
        for mesh_path, count in sorted(STATS.items(), key=lambda item: -item[1])[:args.top]:
            print("  %10s  %s" % (format(count, ","), mesh_path.rsplit("/Static/", 1)[-1]))
        STATS.clear()


if __name__ == "__main__":
    main()
