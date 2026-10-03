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

    python build_towns.py [TOWN ...] [--max-size 512] [--tile 32]

It writes `town_packages/carla.town.<town>/`: one binary glTF,
`carla.town.<town>.glb`, with its textures inside, and the town's
OpenDRIVE map, `<town>.xodr`. The package names no engine
and no engine path: `check_clean` refuses one that does.
"""

import argparse
import hashlib
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
from bake_identity import BakeIdentity  # noqa: E402

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
# A street lamp's glass: each connected piece of it is one lamp head.
LAMP_GLASS = "_glass_ext"
# Lamps with no glass mesh, whose head is at the top of the mesh.
LAMP_TOPS = ("/SM_Lights/SM_StreetLightWall", "/Chainbarrier/SM_LightPost")
# The `extras` tag of a material that glows when the street lights are on.
LAMP_TAG = {"carla": "lamp"}
# A town's glass: a dark pane, smooth and partly metal, so it mirrors the
# sky and the street.
GLASS_COLOR = (0.05, 0.065, 0.08, 1.0)
GLASS_METAL = 0.6
GLASS_ROUGHNESS = 0.06
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


# Kinds that lie flat on the ground. A road's paint is a decal a few
# triangles deep, which simplifying breaks, and each is cheap, so each
# keeps every triangle at both levels.
FLAT = ("road", "road_line", "sidewalk", "ground", "terrain", "water", "rail")


def budget(kind, triangles, mesh_path):
    """Return the most triangles one copy of a mesh keeps."""
    if kind in FLAT:
        return triangles
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
    collapses. With `borders`, its open edges, the texture seams among
    them, stay in place, so its textures do not tear. Without, it is
    welded first; see `simplify_welded`."""
    import fast_simplification
    faces = primitive["triangles"]
    if not borders:
        return simplify_welded(primitive, target)
    floor = fix.KEEP // 2 if not small else 8
    if len(faces) <= max(target, floor) or (not small and len(faces) < fix.KEEP):
        return primitive
    points = primitive["positions"]
    _, _, collapses = fast_simplification.simplify(
        points, faces.astype(numpy.int32), target_count=max(floor, target),
        return_collapses=True, preserve_border=True)
    new_points, new_faces, mapping = fast_simplification.replay_simplification(
        points, faces.astype(numpy.int32), collapses)
    if len(new_faces) == 0:
        return primitive
    source = numpy.zeros(len(new_points), dtype=numpy.int64)
    source[mapping[::-1]] = numpy.arange(len(mapping))[::-1]
    return {"positions": new_points, "normals": area_normals(new_points, new_faces),
            "uvs": primitive["uvs"][source], "triangles": new_faces.astype(numpy.int64),
            "material": primitive["material"]}


# A far mesh's corners are gathered into cells this fraction of its size.
CLUSTER_DIVISIONS = 200
# The smallest cell, in meters.
CLUSTER_CELL = 0.25


def simplify_welded(primitive, target):
    """Return a primitive lowered to about `target` triangles for the far
    level of detail.

    A merged building is cut into many texture islands, each a piece of
    its own, and it is also thousands of separate trims and frames. A
    quadric collapse never removes a piece, so it stops far short. So the
    corners are first gathered into cells, a `CLUSTER_DIVISIONS`th of the
    mesh's size and at least `CLUSTER_CELL` wide, and each cell's corners
    become one at their mean: a small piece collapses to nothing, and a
    wall stays a wall. Then the joined mesh is collapsed to the target
    with its edges free to move.

    Each new triangle is flat, its corners apart, and takes its texture
    coordinates from one original triangle, by `transfer_uvs`.
    """
    import fast_simplification
    faces = primitive["triangles"]
    if len(faces) <= max(target, 8):
        return primitive
    positions = primitive["positions"]
    size = numpy.linalg.norm(positions.max(axis=0) - positions.min(axis=0))
    cell = max(CLUSTER_CELL, size / CLUSTER_DIVISIONS)
    _, gathered = numpy.unique(numpy.floor(positions / cell).astype(numpy.int64), axis=0, return_inverse=True)
    gathered = gathered.reshape(-1)
    sums = numpy.zeros((gathered.max() + 1, 3))
    numpy.add.at(sums, gathered, positions)
    points = sums / numpy.bincount(gathered)[:, None]
    joined = gathered[faces]
    whole = (joined[:, 0] != joined[:, 1]) & (joined[:, 1] != joined[:, 2]) & (joined[:, 0] != joined[:, 2])
    joined = joined[whole]
    # Two pieces that met in the same cells leave the same triangle twice.
    _, once = numpy.unique(numpy.sort(joined, axis=1), axis=0, return_index=True)
    joined = joined[numpy.sort(once)]
    if len(joined) == 0:
        return None
    if len(joined) > max(target, 8):
        _, _, collapses = fast_simplification.simplify(
            points, joined.astype(numpy.int32), target_count=max(8, target),
            return_collapses=True, preserve_border=False)
        points, joined, _ = fast_simplification.replay_simplification(
            points, joined.astype(numpy.int32), collapses)
        if len(joined) == 0:
            return None
        # A collapse puts a vertex where its error is least, which on a
        # thin or flat piece can be far outside the building: a sliver
        # that casts a long shadow. Every vertex stays in the mesh's box.
        low, high = positions.min(axis=0), positions.max(axis=0)
        points = numpy.clip(points, low, high)
    corners = points[joined]
    # A collapse can leave a vertex that is not finite; its triangles go.
    corners = corners[numpy.isfinite(corners).all(axis=(1, 2))]
    if len(corners) == 0:
        return None
    face = numpy.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
    face /= numpy.maximum(numpy.linalg.norm(face, axis=1, keepdims=True), 1e-12)
    uvs, facing = transfer_uvs(primitive, corners, face)
    # Gathering corners can turn a triangle over, and a face turned away
    # is culled, a hole: each faces as the original it reads its texture
    # from.
    over = numpy.einsum("nd,nd->n", face, facing) < 0
    corners[over] = corners[over][:, ::-1]
    uvs[over] = uvs[over][:, ::-1]
    face[over] = -face[over]
    return {"positions": corners.reshape(-1, 3), "normals": numpy.repeat(face, 3, axis=0),
            "uvs": uvs.reshape(-1, 2), "triangles": numpy.arange(3 * len(corners)).reshape(-1, 3),
            "material": primitive["material"]}


def transfer_uvs(primitive, corners, normals, candidates=8):
    """Return texture coordinates for new triangles `corners` (n, 3, 3)
    with unit normals `normals`, from the primitive they were simplified
    from.

    Each new triangle takes one original triangle: of the `candidates`
    whose centers are nearest its own, the one that lies nearest its
    plane, facing either way. Its three corners are projected into that
    triangle's plane and take the texture coordinates its own corners
    would give there, so the new triangle reads one texture island, not
    three. Returns the coordinates, three to a triangle, and the normal of
    each triangle's original.
    """
    from scipy.spatial import cKDTree
    faces = primitive["triangles"]
    source = primitive["positions"][faces]
    centers = source.mean(axis=1)
    normal = numpy.cross(source[:, 1] - source[:, 0], source[:, 2] - source[:, 0])
    normal /= numpy.maximum(numpy.linalg.norm(normal, axis=1, keepdims=True), 1e-12)
    count = min(candidates, len(faces))
    _, near = cKDTree(centers).query(corners.mean(axis=1), k=count)
    near = near.reshape(len(corners), count)
    facing = numpy.einsum("nkd,nd->nk", normal[near], normals)
    offset = numpy.abs(numpy.einsum("nkd,nkd->nk", normal[near],
                                    corners.mean(axis=1)[:, None, :] - centers[near]))
    best = near[numpy.arange(len(corners)), numpy.argmin(offset - numpy.abs(facing), axis=1)]
    a, b, c = source[best, 0], source[best, 1], source[best, 2]
    uv = primitive["uvs"][faces[best]]
    e0, e1 = b - a, c - a
    d00 = numpy.einsum("nd,nd->n", e0, e0)
    d01 = numpy.einsum("nd,nd->n", e0, e1)
    d11 = numpy.einsum("nd,nd->n", e1, e1)
    denominator = d00 * d11 - d01 * d01
    denominator = numpy.where(numpy.abs(denominator) > 1e-18, denominator, 1e-18)
    out = numpy.zeros((len(corners), 3, 2))
    for k in range(3):
        e2 = corners[:, k] - a
        d20 = numpy.einsum("nd,nd->n", e2, e0)
        d21 = numpy.einsum("nd,nd->n", e2, e1)
        v = (d11 * d20 - d01 * d21) / denominator
        w = (d00 * d21 - d01 * d20) / denominator
        out[:, k] = (1 - v - w)[:, None] * uv[:, 0] + v[:, None] * uv[:, 1] + w[:, None] * uv[:, 2]
    return out, normal[best]


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
    tag = library._bake_tag(name, "impostor", parts)
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


# ---- Baked far buildings ----------------------------------------------------

# The views a far building's picture is drawn from: toward the viewer, and
# the image's right and up, in the three.js frame.
BAKE_VIEWS = (
    ((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)),
    ((-1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0, 0.0)),
    ((0.0, 0.0, 1.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
    ((0.0, 0.0, -1.0), (-1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
    ((0.0, 1.0, 0.0), (1.0, 0.0, 0.0), (0.0, 0.0, -1.0)),
)
# Texels a meter each view is drawn at, and the most a side of one view.
BAKE_DENSITY = 6.0
BAKE_MOST = 512


def _dilate(image, covered, passes=6):
    """Spread the covered texels' colors into the uncovered ones next to
    them, so filtering at a view's edge does not bleed the background."""
    image = image.copy()
    covered = covered.copy()
    for _ in range(passes):
        if covered.all():
            break
        grown = covered.copy()
        total = numpy.zeros_like(image)
        count = numpy.zeros(covered.shape)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            shifted = numpy.roll(numpy.roll(covered, dy, axis=0), dx, axis=1)
            colors = numpy.roll(numpy.roll(image, dy, axis=0), dx, axis=1)
            take = shifted & ~covered
            total[take] += colors[take]
            count[take] += 1
            grown |= take
        fill = (count > 0) & ~covered
        image[fill] = total[fill] / count[fill][:, None]
        covered = grown
    if not covered.all() and covered.any():
        image[~covered] = image[covered].mean(axis=0)
    return image


def _view(parts, library, forward, right, up, low_r, low_u, width, height, columns, rows):
    """Return one orthographic view of a mesh's albedo, `rows` by
    `columns` texels, looking down `-forward`, as `_splat` draws a tree's,
    with no light: the renderer lights the far mesh itself."""
    forward, right, up = numpy.array(forward), numpy.array(right), numpy.array(up)
    rng = numpy.random.default_rng(11)
    xs, ys, zs, colors = [], [], [], []
    scale_u = columns / max(width, 1e-6)
    scale_v = rows / max(height, 1e-6)
    for part, material in parts:
        image, factor = _albedo(library, material)
        entry = library.gltf["materials"][material]
        masked = entry.get("alphaMode") == "MASK"
        cut = entry.get("alphaCutoff", 0.5)
        tri = part["triangles"]
        corners = part["positions"][tri]
        u = (corners @ right - low_r) * scale_u
        v = (low_u + height - corners @ up) * scale_v
        area = 0.5 * numpy.abs((u[:, 1] - u[:, 0]) * (v[:, 2] - v[:, 0]) - (u[:, 2] - u[:, 0]) * (v[:, 1] - v[:, 0]))
        counts = numpy.minimum(numpy.maximum(1, numpy.ceil(area * 3)), 8192).astype(numpy.int64)
        owner = numpy.repeat(numpy.arange(len(corners)), counts)
        a, b = rng.random(len(owner)), rng.random(len(owner))
        flip = a + b > 1
        a[flip], b[flip] = 1 - a[flip], 1 - b[flip]
        w = numpy.stack([1 - a - b, a, b], axis=1)
        depth = numpy.einsum("nk,nk->n", w, (corners @ forward)[owner])
        uv = numpy.einsum("nk,nkd->nd", w, part["uvs"][tri][owner])
        if image is None:
            rgba = numpy.tile(factor, (len(owner), 1))
        else:
            h, wd = image.shape[:2]
            px = (numpy.mod(uv[:, 0], 1.0) * (wd - 1)).astype(numpy.int64)
            py = (numpy.mod(uv[:, 1], 1.0) * (h - 1)).astype(numpy.int64)
            rgba = image[py, px] * factor
        keep = rgba[:, 3] >= cut if masked else numpy.ones(len(owner), dtype=bool)
        xs.append(numpy.einsum("nk,nk->n", w, u[owner])[keep])
        ys.append(numpy.einsum("nk,nk->n", w, v[owner])[keep])
        zs.append(depth[keep])
        colors.append(rgba[keep, :3])
    out = numpy.zeros((rows, columns, 3))
    covered = numpy.zeros((rows, columns), dtype=bool)
    if sum(len(x) for x in xs):
        x = numpy.concatenate(xs).astype(numpy.int64)
        y = numpy.concatenate(ys).astype(numpy.int64)
        z = numpy.concatenate(zs)
        color = numpy.concatenate(colors)
        inside = (x >= 0) & (x < columns) & (y >= 0) & (y < rows)
        x, y, z, color = x[inside], y[inside], z[inside], color[inside]
        texel = y * columns + x
        # The nearest sample to the viewer, who stands at the far end of
        # `forward`.
        order = numpy.lexsort((-z, texel))
        sorted_texel = texel[order]
        first = numpy.ones(len(order), dtype=bool)
        first[1:] = sorted_texel[1:] != sorted_texel[:-1]
        chosen = order[first]
        out[y[chosen], x[chosen]] = color[chosen]
        covered[y[chosen], x[chosen]] = True
    return _dilate(out, covered)


def baked_building(parts, library, out_dir, name, target):
    """Return a building's far level and its material: its mesh gathered
    and collapsed to about `target` triangles, all its primitives as one,
    wearing an atlas of five views of its near level, from each side and
    from above. Each far triangle reads the view that faces it most, so
    its windows and its trim are pictures, not geometry."""
    from PIL import Image
    whole = {
        "positions": numpy.concatenate([p["positions"] for p, _ in parts]),
        "normals": numpy.concatenate([p["normals"] for p, _ in parts]),
        "uvs": numpy.concatenate([p["uvs"] for p, _ in parts]),
        "triangles": numpy.concatenate([p["triangles"] + sum(len(q["positions"]) for q, _ in parts[:i])
                                        for i, (p, _) in enumerate(parts)]),
        "material": name,
    }
    far = simplify_welded(whole, target)
    if far is None:
        return None, None
    if far is whole:
        corners = whole["positions"][whole["triangles"]]
        face = numpy.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
        face /= numpy.maximum(numpy.linalg.norm(face, axis=1, keepdims=True), 1e-12)
        far = {"positions": corners.reshape(-1, 3), "normals": numpy.repeat(face, 3, axis=0),
               "triangles": numpy.arange(3 * len(corners)).reshape(-1, 3), "material": name}
    low, high = whole["positions"].min(axis=0), whole["positions"].max(axis=0)
    cells = []
    for forward, right, up in BAKE_VIEWS:
        r, u = numpy.array(right), numpy.array(up)
        span_r = sorted([low @ r, high @ r])
        span_u = sorted([low @ u, high @ u])
        # The box's corners give each view's extent along its axes.
        box = numpy.array([[x, y, z] for x in (low[0], high[0]) for y in (low[1], high[1]) for z in (low[2], high[2])])
        span_r = (float((box @ r).min()), float((box @ r).max()))
        span_u = (float((box @ u).min()), float((box @ u).max()))
        width, height = span_r[1] - span_r[0], span_u[1] - span_u[0]
        density = min(BAKE_DENSITY, BAKE_MOST / max(width, height, 1e-6))
        columns = max(4, int(numpy.ceil(width * density)))
        rows = max(4, int(numpy.ceil(height * density)))
        image = _view(parts, library, forward, right, up, span_r[0], span_u[0], width, height, columns, rows)
        cells.append((image, span_r, span_u))
    # One row of the five views, each at its own size.
    atlas_w = sum(c[0].shape[1] for c in cells)
    atlas_h = max(c[0].shape[0] for c in cells)
    atlas = numpy.zeros((atlas_h, atlas_w, 3))
    offsets = []
    x = 0
    for image, _, _ in cells:
        atlas[: image.shape[0], x: x + image.shape[1]] = image
        offsets.append(x)
        x += image.shape[1]
    # Each far triangle reads the view whose forward its face meets most.
    corners = far["positions"].reshape(-1, 3, 3)
    face = far["normals"].reshape(-1, 3, 3)[:, 0]
    forwards = numpy.array([f for f, _, _ in BAKE_VIEWS])
    pick = numpy.argmax(face @ forwards.T, axis=1)
    uvs = numpy.zeros((len(corners), 3, 2))
    for k, (forward, right, up) in enumerate(BAKE_VIEWS):
        mine = pick == k
        if not mine.any():
            continue
        image, span_r, span_u = cells[k]
        r, u = numpy.array(right), numpy.array(up)
        fr = (corners[mine] @ r - span_r[0]) / max(span_r[1] - span_r[0], 1e-6)
        fu = (span_u[1] - corners[mine] @ u) / max(span_u[1] - span_u[0], 1e-6)
        uvs[mine, :, 0] = (offsets[k] + numpy.clip(fr, 0, 1) * image.shape[1]) / atlas_w
        uvs[mine, :, 1] = numpy.clip(fu, 0, 1) * image.shape[0] / atlas_h
    tag = library._bake_tag(name, "baked", parts, target)
    os.makedirs(os.path.join(out_dir, "textures"), exist_ok=True)
    Image.fromarray((numpy.clip(atlas, 0, 1) * 255).astype(numpy.uint8), "RGB").save(
        os.path.join(out_dir, "textures", tag + ".jpg"), quality=85)
    gltf = library.gltf
    gltf["images"].append({"uri": "textures/" + tag + ".jpg"})
    gltf["textures"].append({"sampler": 0, "source": len(gltf["images"]) - 1})
    gltf["materials"].append({
        "name": tag,
        "pbrMetallicRoughness": {"baseColorTexture": {"index": len(gltf["textures"]) - 1},
                                 "metallicFactor": 0.0, "roughnessFactor": 0.85},
        "doubleSided": True})
    far["uvs"] = uvs.reshape(-1, 2)
    far["material"] = tag
    return far, len(gltf["materials"]) - 1


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
        self._bake_identity = BakeIdentity(self.gltf, out_dir)
        self._bake_geometry = {}

    def _bake_tag(self, mesh_path, kind, parts, target=None):
        """Hash ordered, immutable geometry and resolved material inputs.

        The arrays and material tables stay fixed during one build. Hash
        each primitive once, with fixed byte order and widths, independent
        of its original array layout. Keep its reference to prevent object
        id reuse. Placement transforms are applied after cache lookup.
        """
        ordered = []
        for primitive, material in parts:
            identity = id(primitive)
            if identity not in self._bake_geometry:
                digest = hashlib.sha256()
                for field in ("positions", "normals", "uvs", "triangles"):
                    values = numpy.ascontiguousarray(primitive[field], dtype="<i8" if field == "triangles" else "<f8")
                    digest.update(json.dumps([field, values.shape], separators=(",", ":")).encode())
                    digest.update(memoryview(values).cast("B"))
                self._bake_geometry[identity] = (primitive, digest.hexdigest())
            ordered.append((self._bake_geometry[identity][1], material))
        if kind == "baked":
            settings = [target, BAKE_DENSITY, BAKE_MOST, BAKE_VIEWS, CLUSTER_CELL, CLUSTER_DIVISIONS]
        else:
            settings = [IMPOSTOR_SIZE, IMPOSTOR_SAMPLES, IMPOSTOR_LIGHT.tolist()]
        return self._bake_identity.key(mesh_path, kind, ordered, settings)

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
            if material.get("alphaMode") == "BLEND" and "glass" in name.lower():
                # A town's glass has nothing behind it: a see-through tower
                # shows the sky through its windows. So it is a dark,
                # smooth pane that mirrors its surroundings, as CARLA's is.
                material.pop("alphaMode")
                pbr = material.setdefault("pbrMetallicRoughness", {})
                pbr.pop("baseColorTexture", None)
                pbr["baseColorFactor"] = list(GLASS_COLOR)
                pbr["metallicFactor"] = GLASS_METAL
                pbr["roughnessFactor"] = GLASS_ROUGHNESS
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
        return max(min(triangles, 300), triangles // 60)
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


def lamp_heads(primitives, mesh_path):
    """Return where a lamp mesh's heads are, in its own frame: the middle
    of each connected piece of its glass, or the top of a lamp with no
    glass. None for a mesh that is not a lamp."""
    if mesh_path.endswith(LAMP_GLASS):
        from scipy.sparse import coo_matrix
        from scipy.sparse.csgraph import connected_components
        points = numpy.concatenate([p["positions"] for p in primitives])
        faces = numpy.concatenate([p["triangles"] + sum(len(q["positions"]) for q in primitives[:i])
                                   for i, p in enumerate(primitives)])
        # Corners that share a place are one, so a piece is whole.
        _, welded = numpy.unique(numpy.round(points * 1000.0).astype(numpy.int64), axis=0, return_inverse=True)
        welded = welded.reshape(-1)
        joined = welded[faces]
        count = welded.max() + 1
        rows = numpy.concatenate([joined[:, 0], joined[:, 1]])
        cols = numpy.concatenate([joined[:, 1], joined[:, 2]])
        pieces, label = connected_components(
            coo_matrix((numpy.ones(len(rows)), (rows, cols)), shape=(count, count)), directed=False)
        heads = []
        for piece in range(pieces):
            inside = points[label[welded] == piece]
            heads.append((inside.min(axis=0) + inside.max(axis=0)) / 2)
        return numpy.array(heads)
    if mesh_path.endswith(LAMP_TOPS):
        points = numpy.concatenate([p["positions"] for p in primitives])
        low, high = points.min(axis=0), points.max(axis=0)
        return numpy.array([[(low[0] + high[0]) / 2, high[1] - 0.15, (low[2] + high[2]) / 2]])
    return None


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
    # Each lamp head, in the three.js frame, and each lamp mesh's heads.
    lamps = []
    heads_of = {}
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
        first_visible = next((i for i, name in enumerate(names) if name != GRID), None)
        if mesh_path not in heads_of:
            heads_of[mesh_path] = lamp_heads(primitives, mesh_path)
        heads = heads_of[mesh_path]
        if heads is not None:
            for rows in copies:
                linear, move = to_three(rows)
                lamps.extend((heads @ linear.T + move).tolist())
        for index, (primitive, material_name) in enumerate(zip(primitives, names)):
            if material_name == GRID:
                continue
            material = library.material(material_name)
            if "_glass_" in mesh_path and "/StreetLights/" in mesh_path:
                library.gltf["materials"][material]["extras"] = dict(LAMP_TAG)
            total = sum(len(p["triangles"]) for p in primitives)
            for lod in LODS:
                part_material = material
                if lod == 1 and kind == "building":
                    # A building's far level is its baked proxy, made once
                    # for all its primitives.
                    if index != first_visible:
                        continue
                    parts = [(p, library.material(n)) for p, n in zip(primitives, names) if n != GRID]
                    goal = max(8, int(limit_of(kind, total, mesh_path, 1) * factors[(kind, 1)]))
                    key = library._bake_tag(mesh_path, "baked", parts, goal)
                    if key not in lowered:
                        lowered[key] = baked_building(parts, library, out_dir, mesh_path, goal)
                    part, part_material = lowered[key]
                elif lod == 1 and TREES in mesh_path:
                    # A tree's far level is its impostor, drawn once for
                    # all its primitives.
                    if index != first_visible:
                        continue
                    parts = [(p, library.material(n)) for p, n in zip(primitives, names) if n != GRID]
                    key = library._bake_tag(mesh_path, "impostor", parts)
                    if key not in lowered:
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
    return write(town, name, out_dir, library, groups, lamps)


def write(town, name, out_dir, library, groups, lamps):
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
    # Each street lamp's head, three numbers each, for the lights at night.
    gltf["scenes"] = [{"nodes": list(range(len(gltf["nodes"]))),
                       "extras": {"carla_lamps": [round(v, 3) for head in lamps for v in head]}}]
    gltf["buffers"] = [{"byteLength": len(blob), "uri": name + ".bin"}]
    open(os.path.join(out_dir, name + ".bin"), "wb").write(blob)
    json.dump(gltf, open(os.path.join(out_dir, name + ".gltf"), "w", encoding="utf-8"), separators=(",", ":"))
    check_clean(out_dir)
    to_glb(out_dir, name)
    return triangles, len(gltf["nodes"])


def to_glb(out_dir, name):
    """Pack a package's glTF, its buffer and its textures into one binary
    glTF, `<name>.glb`, and remove the loose files. A town is then two
    files, the glb and its OpenDRIVE map, and its manifest entry lists
    two members, not a thousand."""
    gltf_path = os.path.join(out_dir, name + ".gltf")
    gltf = json.load(open(gltf_path, encoding="utf-8"))
    blob = bytearray(open(os.path.join(out_dir, name + ".bin"), "rb").read())
    for image in gltf.get("images", []):
        while len(blob) % 4:
            blob.append(0)
        data = open(os.path.join(out_dir, image["uri"]), "rb").read()
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)})
        blob.extend(data)
        mime = "image/png" if image["uri"].endswith(".png") else "image/jpeg"
        image.clear()
        image.update({"bufferView": len(gltf["bufferViews"]) - 1, "mimeType": mime})
    while len(blob) % 4:
        blob.append(0)
    gltf["buffers"] = [{"byteLength": len(blob)}]
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    with open(os.path.join(out_dir, name + ".glb"), "wb") as out:
        out.write(struct.pack("<III", 0x46546C67, 2, total))
        out.write(struct.pack("<II", len(text), 0x4E4F534A))
        out.write(text)
        out.write(struct.pack("<II", len(blob), 0x004E4942))
        out.write(blob)
    os.remove(gltf_path)
    os.remove(os.path.join(out_dir, name + ".bin"))
    shutil.rmtree(os.path.join(out_dir, "textures"), ignore_errors=True)


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
    parser.add_argument("--tile", type=float, default=32.0)
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
