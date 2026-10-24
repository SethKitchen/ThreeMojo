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

import atexit
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import carla_gltf_fix as fix  # noqa: E402


def atlas_tag(gltf, out_dir, mesh_path, kind, parts, settings):
    """Return the Mojo bake identity for one ordered material list.

    Args:
        gltf: The package tables.
        out_dir: The directory that holds the texture files.
        mesh_path: The source mesh path.
        kind: `baked` or `impostor`.
        parts: Ordered pairs of geometry digests and material indexes.
        settings: The bake settings that affect the output.

    Returns:
        The atlas tag.

    Raises:
        ValueError: The identity program cannot read an input.
    """
    root = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
    mojo = os.path.join(root, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    request = {
        "gltf": gltf,
        "out_dir": str(out_dir),
        "mesh": mesh_path,
        "kind": kind,
        "parts": [[geometry, int(material)] for geometry, material in parts],
        "settings": settings,
    }
    handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    try:
        json.dump(request, handle)
        handle.close()
        result = subprocess.run(
            ["sh", os.path.join(root, "tools", "tool.sh"), mojo,
             "carla_bake_identity", handle.name],
            text=True, capture_output=True, check=False,
        )
    finally:
        os.remove(handle.name)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "bake identity failed")
    return result.stdout.strip()


BASE = os.path.abspath(os.environ.get("CARLA_EXPORT_DIR", "."))
RAW = os.path.join(BASE, "raw_town")
LAYOUT = os.path.join(BASE, "layout")
MAPS = os.path.join(BASE, "release", "CarlaUE4", "Content", "Carla", "Maps", "OpenDrive")
OUT = os.path.join(BASE, "town_packages")
TOWNS = ["Town01", "Town02", "Town03", "Town04", "Town05", "Town10HD"]

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
# The levels of detail: 0 near, 1 far.
LODS = (0, 1)
# The folder whose meshes are trees, whose far level is an impostor.
TREES = "/Vegetation/Trees/"
# Triangles each mesh adds to the package, for the report.
STATS = {}
CREDIT = "CARLA Team, CARLA Simulator 0.9.16, CC-BY 4.0 (https://carla.org)"


_BUDGET_CACHE = {}
_BUDGET_PROC = None
_BUDGET_ERR = None


def _budget_root():
    """Return the repository root that holds `tools/tool.sh`."""
    return os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))


def _budget_mojo():
    """Return the Mojo compiler, as the Makefile's `TOOL_MOJO` chooses it."""
    path = os.path.join(_budget_root(), ".venv", "bin", "mojo")
    if os.path.isfile(path):
        return path
    return "mojo"


def _budget_close():
    """Stop the budget worker when this process ends."""
    global _BUDGET_PROC
    proc = _BUDGET_PROC
    if proc is None or proc.poll() is not None:
        return
    try:
        proc.stdin.close()
    except Exception:
        pass
    try:
        proc.wait(timeout=5)
    except Exception:
        proc.kill()
    _BUDGET_PROC = None


def _budget_worker():
    """Return the long-lived `carla_town_budget serve` process."""
    global _BUDGET_PROC, _BUDGET_ERR
    if _BUDGET_PROC is not None and _BUDGET_PROC.poll() is None:
        return _BUDGET_PROC
    if _BUDGET_ERR is not None:
        _BUDGET_ERR.close()
    _BUDGET_ERR = tempfile.TemporaryFile()
    _BUDGET_PROC = subprocess.Popen(
        ["sh", os.path.join(_budget_root(), "tools", "tool.sh"), _budget_mojo(),
         "carla_town_budget", "serve"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=_BUDGET_ERR, text=True,
    )
    return _BUDGET_PROC


def _budget_failed(proc):
    """Raise the worker's error text and forget the dead process."""
    global _BUDGET_PROC
    try:
        proc.wait(timeout=5)
    except Exception:
        proc.kill()
    text = ""
    if _BUDGET_ERR is not None:
        _BUDGET_ERR.seek(0)
        text = _BUDGET_ERR.read().decode("utf-8", "replace").strip()
    _BUDGET_PROC = None
    raise ValueError(text or "town budget failed")


def _budget_ask(fields):
    """Return one answer from `tools/carla_town_budget.mojo`."""
    for field in fields:
        if "\t" in field or "\n" in field or "\r" in field:
            raise ValueError("town budget field has a separator")
    key = tuple(fields)
    cached = _BUDGET_CACHE.get(key)
    if cached is not None:
        return cached
    proc = _budget_worker()
    try:
        proc.stdin.write("\t".join(fields) + "\n")
        proc.stdin.flush()
        line = proc.stdout.readline()
    except (BrokenPipeError, ValueError):
        _budget_failed(proc)
    if not line:
        _budget_failed(proc)
    if not line.startswith("ok\t"):
        raise ValueError(line.split("\t", 1)[-1].strip() or "town budget failed")
    value = line[3:]
    if value.endswith("\n"):
        value = value[:-1]
    if value.endswith("\r"):
        value = value[:-1]
    _BUDGET_CACHE[key] = value
    return value


atexit.register(_budget_close)


def object_path(full_name):
    """Return (`Class`, `/Game/A/B`, `B`) from UE4SS's `Class /Game/A/B.B`.

    `tools/carla_town_budget.mojo` splits the name.
    """
    parts = _budget_ask(["object", full_name]).split("\t")
    if len(parts) != 3:
        raise ValueError("town budget object path failed")
    return parts[0], parts[1], parts[2]


def kind_of(mesh_path):
    """Return a mesh's kind, None to leave it out.

    `tools/carla_town_budget.mojo` chooses the kind.
    """
    kind = _budget_ask(["kind", mesh_path])
    if kind == "skip":
        return None
    return kind


def budget(kind, triangles, mesh_path):
    """Return the most triangles one copy of a mesh keeps.

    `tools/carla_town_budget.mojo` chooses the limit. A flat kind keeps
    every triangle: a road's paint is only a few triangles deep.
    """
    if kind is None:
        kind = ""
    return int(_budget_ask(["near", str(kind), str(int(triangles)), str(mesh_path)]))


def far_budget(kind, triangles, mesh_path):
    """Return the most triangles one copy keeps in the far level of
    detail, 0 to leave it out there: what is small at a distance goes.

    `tools/carla_town_budget.mojo` chooses the limit.
    """
    if kind is None:
        kind = ""
    return int(_budget_ask(["far", str(kind), str(int(triangles)), str(mesh_path)]))


# ---- Transforms ------------------------------------------------------------

SWAP = numpy.array([[1.0, 0, 0], [0, 0, 1.0], [0, 1.0, 0]])
_PLACE_PROC = None
_PLACE_ERR = None


def _place_root():
    """Return the repository root that holds `tools/tool.sh`."""
    return os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))


def _place_mojo():
    """Return the Mojo compiler, as the Makefile's `TOOL_MOJO` chooses it."""
    path = os.path.join(_place_root(), ".venv", "bin", "mojo")
    if os.path.isfile(path):
        return path
    return "mojo"


def _place_close():
    """Stop the placement worker when this process ends."""
    global _PLACE_PROC
    proc = _PLACE_PROC
    if proc is None or proc.poll() is not None:
        return
    try:
        proc.stdin.close()
    except Exception:
        pass
    try:
        proc.wait(timeout=5)
    except Exception:
        proc.kill()
    _PLACE_PROC = None


def _place_worker():
    """Return the long-lived `carla_town_place serve` process."""
    global _PLACE_PROC, _PLACE_ERR
    if _PLACE_PROC is not None and _PLACE_PROC.poll() is None:
        return _PLACE_PROC
    if _PLACE_ERR is not None:
        _PLACE_ERR.close()
    _PLACE_ERR = tempfile.TemporaryFile()
    _PLACE_PROC = subprocess.Popen(
        ["sh", os.path.join(_place_root(), "tools", "tool.sh"), _place_mojo(),
         "carla_town_place", "serve"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=_PLACE_ERR, text=True,
    )
    return _PLACE_PROC


def _tile_cell(rows, tile):
    """Return the tile column and row for one copy's matrix.

    `tools/carla_town_place.mojo` floors the origin. The origin is the
    matrix translation in centimeters.
    """
    proc = _place_worker()
    try:
        proc.stdin.write(
            "cell\t"
            + json.dumps(float(rows[3][0]))
            + "\t"
            + json.dumps(float(rows[3][1]))
            + "\t"
            + json.dumps(float(tile))
            + "\n"
        )
        proc.stdin.flush()
        line = proc.stdout.readline()
    except (BrokenPipeError, ValueError):
        _place_failed(proc)
    if not line:
        _place_failed(proc)
    if line.startswith("ERR\t"):
        raise ValueError(line[4:].strip() or "tile failed")
    column, row = line.strip().split("\t")
    return int(column), int(row)


def _place_failed(proc):
    """Raise the worker's error text and forget the dead process."""
    global _PLACE_PROC
    try:
        proc.wait(timeout=5)
    except Exception:
        proc.kill()
    text = ""
    if _PLACE_ERR is not None:
        _PLACE_ERR.seek(0)
        text = _PLACE_ERR.read().decode("utf-8", "replace").strip()
    _PLACE_PROC = None
    raise ValueError(text or "town placement failed")


def _place_ask(payload):
    """Return one answer from `tools/carla_town_place.mojo`."""
    proc = _place_worker()
    try:
        proc.stdin.write(json.dumps(payload, separators=(",", ":"), allow_nan=False) + "\n")
        proc.stdin.flush()
        line = proc.stdout.readline()
    except (BrokenPipeError, ValueError):
        _place_failed(proc)
    if not line:
        _place_failed(proc)
    if line.startswith("ERR\t"):
        raise ValueError(line[4:].strip() or "town placement failed")
    return json.loads(line)


atexit.register(_place_close)


def rotation_rows(pitch, yaw, roll):
    """Return Unreal's rotation matrix for a rotator, in its row-vector
    convention (a point is a row, multiplied on the left).

    `tools/carla_town_place.mojo` builds the matrix.
    """
    matrix = _place_ask({"op": "matrix", "pitch": pitch, "yaw": yaw, "roll": roll,
                         "scale": [1, 1, 1], "location": [0, 0, 0]})
    return numpy.array(matrix, dtype=numpy.float64)[:3, :3]


def component_rows(row):
    """Return a component's world matrix in Unreal's row-vector
    convention, in centimeters: scale, then rotate, then move.

    `tools/carla_town_place.mojo` builds the matrix.
    """
    pitch, yaw, roll = row["rotation"]
    matrix = _place_ask({"op": "matrix", "pitch": pitch, "yaw": yaw, "roll": roll,
                         "scale": list(row["scale"]), "location": list(row["location"])})
    return numpy.array(matrix, dtype=numpy.float64)


_FRAME = None


def _frame_worker():
    """Return the long-lived `tools/carla_town_frame.mojo` process."""
    global _FRAME
    if _FRAME is not None and _FRAME.poll() is None:
        return _FRAME
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    _FRAME = subprocess.Popen(
        ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
         "carla_town_frame", "serve"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
    )
    return _FRAME


def _close_frame():
    """Stop the frame worker when the process exits."""
    worker = _FRAME
    if worker is None or worker.poll() is not None:
        return
    worker.stdin.close()
    worker.wait(timeout=5)
    worker.stdout.close()


atexit.register(_close_frame)


def _frame_ask(matrix):
    """Return `linear` and `move` for one 4×4 matrix."""
    worker = _frame_worker()
    worker.stdin.write(json.dumps(matrix) + "\n")
    worker.stdin.flush()
    line = worker.stdout.readline()
    if not line:
        raise ValueError("town frame stopped")
    if line.startswith("err\t"):
        raise ValueError(line[4:].strip())
    return json.loads(line)


def to_three(rows):
    """Return (A, t): an Unreal row-vector matrix as the map that takes a
    point of an exported mesh (three.js frame, meters) to the world
    (three.js frame, meters): world = A @ point + t.

    `tools/carla_town_frame.mojo` converts the matrix.
    """
    matrix = numpy.asarray(rows, dtype=numpy.float64).reshape(4, 4)
    doc = _frame_ask(matrix.tolist())
    return (
        numpy.array(doc["linear"], dtype=numpy.float64),
        numpy.array(doc["move"], dtype=numpy.float64),
    )


def bend(points, normals, spline):
    """Bend mesh points (three.js frame, meters) along a spline mesh
    component's curve, as Unreal's spline mesh does, and return them in
    the component's frame, in Unreal's axes and centimeters.

    `tools/carla_town_bend.mojo` bends the points.
    """
    folder = tempfile.mkdtemp(prefix="town-bend-")
    try:
        request = os.path.join(folder, "bend.json")
        payload = {
            "points": numpy.asarray(points, dtype=float).reshape(-1, 3).tolist(),
            "normals": numpy.asarray(normals, dtype=float).reshape(-1, 3).tolist(),
            "forward_axis": int(spline["forward_axis"]),
            "start": list(spline["start"]),
            "end": list(spline["end"]),
            "start_tangent": list(spline["start_tangent"]),
            "end_tangent": list(spline["end_tangent"]),
            "start_roll": float(spline["start_roll"]),
            "end_roll": float(spline["end_roll"]),
            "start_scale": list(spline["start_scale"]),
            "end_scale": list(spline["end_scale"]),
        }
        with open(request, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        root = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
        mojo = os.path.join(root, ".venv", "bin", "mojo")
        if not os.path.isfile(mojo):
            mojo = "mojo"
        result = subprocess.run(
            ["sh", os.path.join(root, "tools", "tool.sh"), mojo,
             "carla_town_bend", request],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise ValueError(result.stderr.strip() or "town bend failed")
        bent = json.loads(result.stdout)
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    return (numpy.array(bent["points"], dtype=numpy.float64),
            numpy.array(bent["normals"], dtype=numpy.float64))


# ---- Meshes ----------------------------------------------------------------

def read_gltf(path):
    """Return a UModel glTF's primitives: positions, normals, texture
    coordinates, triangles and material name, as numpy arrays.

    `tools/carla_town_mesh.mojo` reads the buffer. A missing normal is
    `[0, 1, 0]`, and a missing texture coordinate is zero.
    """
    root = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
    mojo = os.path.join(root, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    result = subprocess.run(
        ["sh", os.path.join(root, "tools", "tool.sh"), mojo, "carla_town_mesh", path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town mesh failed")
    primitives = []
    for item in json.loads(result.stdout):
        primitives.append({
            "positions": numpy.array(item["positions"], dtype=numpy.float64),
            "normals": numpy.array(item["normals"], dtype=numpy.float64),
            "uvs": numpy.array(item["uvs"], dtype=numpy.float64),
            "triangles": numpy.array(item["triangles"], dtype=numpy.int64),
            "material": item["material"],
        })
    return primitives


_CUBE_TEXT = None


def _cube_text():
    """Return the engine cube JSON from `tools/carla_town_cube.mojo`."""
    root = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
    mojo = os.path.join(root, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    result = subprocess.run(
        ["sh", os.path.join(root, "tools", "tool.sh"), mojo, "carla_town_cube"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town cube failed")
    return result.stdout


def cube():
    """Return a one-meter box centered on its origin: the engine's cube,
    drawn from scratch.

    `tools/carla_town_cube.mojo` chooses the corners. Each call returns
    new arrays, so a caller can move one copy.
    """
    global _CUBE_TEXT
    if _CUBE_TEXT is None:
        _CUBE_TEXT = _cube_text()
    doc = json.loads(_CUBE_TEXT)
    return [{"positions": numpy.array(doc["positions"], dtype=numpy.float64),
             "normals": numpy.array(doc["normals"], dtype=numpy.float64),
             "uvs": numpy.array(doc["uvs"], dtype=numpy.float64),
             "triangles": numpy.array(doc["triangles"], dtype=numpy.int64),
             "material": doc["material"]}]


def _town_simplify(payload):
    """Return JSON from `tools/carla_town_simplify.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-simplify-")
    try:
        path = os.path.join(folder, "mesh.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_simplify", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town simplify failed")
    return json.loads(result.stdout)


def _simplified(doc):
    """Return one simplified primitive as arrays."""
    return {
        "positions": numpy.array(doc["positions"], dtype=numpy.float64),
        "normals": numpy.array(doc["normals"], dtype=numpy.float64),
        "uvs": numpy.array(doc["uvs"], dtype=numpy.float64),
        "triangles": numpy.array(doc["triangles"], dtype=numpy.int64),
        "material": doc["material"],
    }


def _mesh_payload(primitive, mode, target, small=False):
    """Return the JSON fields shared by both simplification modes."""
    return {
        "mode": mode,
        "positions": numpy.asarray(primitive["positions"], dtype=float).reshape(-1, 3).tolist(),
        "uvs": numpy.asarray(primitive["uvs"], dtype=float).reshape(-1, 2).tolist(),
        "triangles": numpy.asarray(primitive["triangles"]).reshape(-1, 3).tolist(),
        "material": primitive["material"],
        "target": int(target),
        "small": bool(small),
        "keep": int(fix.KEEP),
    }


def simplify(primitive, target, borders=True, small=False):
    """Return a primitive lowered to about `target` triangles by quadric
    collapses. With `borders`, its open edges, the texture seams among
    them, stay in place, so its textures do not tear. Without, it is
    welded first; see `simplify_welded`.

    `tools/carla_town_simplify.mojo` collapses the mesh.
    """
    if not borders:
        return simplify_welded(primitive, target)
    doc = _town_simplify(_mesh_payload(primitive, "border", target, small))
    if doc.get("same"):
        return primitive
    return _simplified(doc)


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

    `tools/carla_town_simplify.mojo` welds the corners, collapses the
    mesh, and copies each new triangle's texture from one original
    triangle.
    """
    doc = _town_simplify(_mesh_payload(primitive, "weld", target))
    if doc.get("same"):
        return primitive
    if doc.get("empty"):
        return None
    return _simplified(doc)


def _card_seed(mesh_path, index, lod):
    """Return the leaf-card seed from `tools/carla_town_cards.mojo`.

    The seed is `zlib.crc32` of the mesh path, plus the part index, plus
    7919 times the level of detail.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-seed-")
    try:
        request = os.path.join(folder, "seed.json")
        with open(request, "w", encoding="utf-8") as handle:
            json.dump({
                "mode": "seed",
                "path": mesh_path,
                "index": int(index),
                "lod": int(lod),
            }, handle, separators=(",", ":"), ensure_ascii=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_cards", request],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "leaf card seed failed")
    return int(json.loads(result.stdout)["seed"])


def _cards_tool(primitive, keep, seed):
    """Return JSON from `tools/carla_town_cards.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-cards-")
    try:
        request = os.path.join(folder, "cards.json")
        payload = {
            "positions": numpy.asarray(primitive["positions"], dtype=float).reshape(-1, 3).tolist(),
            "normals": numpy.asarray(primitive["normals"], dtype=float).reshape(-1, 3).tolist(),
            "uvs": numpy.asarray(primitive["uvs"], dtype=float).reshape(-1, 2).tolist(),
            "triangles": numpy.asarray(primitive["triangles"]).reshape(-1, 3).tolist(),
            "keep": float(keep),
            "seed": int(seed),
        }
        with open(request, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_cards", request],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "leaf cards failed")
    return json.loads(result.stdout)


def thin_cards(primitive, keep, seed):
    """Return a cut-out primitive with about `keep` of its cards, each
    kept card grown about its center so the canopy stays as full. A card
    is a piece of connected triangles: a leaf, or a spray of leaves.

    `tools/carla_town_cards.mojo` chooses and grows the cards.
    """
    doc = _cards_tool(primitive, keep, seed)
    if doc.get("unchanged"):
        return primitive
    return {"positions": numpy.array(doc["positions"], dtype=numpy.float64),
            "normals": numpy.array(doc["normals"], dtype=numpy.float64),
            "uvs": numpy.array(doc["uvs"], dtype=numpy.float64),
            "triangles": numpy.array(doc["triangles"], dtype=numpy.int64),
            "material": primitive["material"]}


# ---- Impostors -------------------------------------------------------------

# Texels a side of an impostor's view, and samples each covered texel takes.
IMPOSTOR_SIZE = 256
IMPOSTOR_SAMPLES = 4
# The light an impostor's texels are shaded by, three.js frame: high and
# from the side, as the sun is most of the day. `tools/carla_town_impostor.mojo`
# normalizes it.
_IMPOSTOR_LIGHT = None


def _albedo(library, material):
    """Return a material's base color image as float RGBA, and its
    factor.

    `tools/carla_image.mojo` reads the file and divides each byte by 255.
    """
    entry = library.gltf["materials"][material]
    pbr = entry.get("pbrMetallicRoughness", {})
    factor = numpy.array(pbr.get("baseColorFactor", [1, 1, 1, 1]), dtype=numpy.float64)
    texture = pbr.get("baseColorTexture")
    if texture is None:
        return None, factor
    source = library.gltf["textures"][texture["index"]]["source"]
    path = os.path.join(library.package.out_dir, library.gltf["images"][source]["uri"])
    _, width, height, rgba = fix.open_image(path)
    values = fix.unit_rgba(rgba)
    image = numpy.array(values, dtype=numpy.float64).reshape(height, width, 4)
    return image, factor


def _raster_tool(parts, library, request):
    """Return one view from `tools/carla_town_splat.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-splat-")
    try:
        path = os.path.join(folder, "view.json")
        payload = dict(request)
        items = []
        for part, material in parts:
            image, factor = _albedo(library, material)
            entry = library.gltf["materials"][material]
            item = {
                "positions": numpy.asarray(part["positions"], dtype=float).reshape(-1, 3).tolist(),
                "normals": numpy.asarray(part["normals"], dtype=float).reshape(-1, 3).tolist(),
                "uvs": numpy.asarray(part["uvs"], dtype=float).reshape(-1, 2).tolist(),
                "triangles": numpy.asarray(part["triangles"]).reshape(-1, 3).tolist(),
                "factor": numpy.asarray(factor, dtype=float).reshape(4).tolist(),
                "cut": float(entry.get("alphaCutoff", 0.5)),
                "masked": entry.get("alphaMode") == "MASK",
            }
            if image is not None:
                item["image"] = {
                    "width": int(image.shape[1]),
                    "height": int(image.shape[0]),
                    "rgba": numpy.asarray(image, dtype=float).reshape(-1).tolist(),
                }
            items.append(item)
        payload["parts"] = items
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_splat", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "splat failed")
    return json.loads(result.stdout)


def _splat(parts, library, across, left, width, top, height, rows, fill=False):
    """Return one view of a tree, drawn across axis `across` (0 for x,
    2 for z) and down y from `top`: RGBA floats, `rows` by
    `IMPOSTOR_SIZE` texels. Each triangle is sampled at random points, as
    many as it covers texels times `IMPOSTOR_SAMPLES`, and the nearest
    sample that the cut-out keeps colors each texel.

    `tools/carla_town_splat.mojo` draws the view. With `fill`, an empty
    texel takes the mean color of the covered texels.
    """
    request = {
        "mode": "axis",
        "columns": IMPOSTOR_SIZE,
        "rows": int(rows),
        "samples": IMPOSTOR_SAMPLES,
        "cap": 4096,
        "seed": 7,
        "across": int(across),
        "left": float(left),
        "top": float(top),
        "span_u": float(width),
        "span_v": float(height),
        "light": impostor_light(),
    }
    if fill:
        request["fill"] = True
    return numpy.array(_raster_tool(parts, library, request), dtype=numpy.float64)


def impostor_light():
    """Return the unit impostor light from `tools/carla_town_impostor.mojo`."""
    global _IMPOSTOR_LIGHT
    if _IMPOSTOR_LIGHT is None:
        _IMPOSTOR_LIGHT = _impostor_tool({"mode": "light"})
    return _IMPOSTOR_LIGHT


def _impostor_tool(payload):
    """Return JSON from `tools/carla_town_impostor.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-impostor-")
    try:
        path = os.path.join(folder, "impostor.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_impostor", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "impostor failed")
    return json.loads(result.stdout)


def impostor(parts, library, out_dir, name):
    """Return a tree's far level, two quads that cross on its trunk, each
    showing a picture of the tree drawn from its near level; and the
    picture's material. `parts` are the tree's primitives, each with its
    material's index.

    `tools/carla_town_impostor.mojo` sizes the views, builds the quads, and
    fills the empty texels. `tools/carla_image_pack.mojo` resizes and joins
    the two pictures. `tools/carla_png.mojo` writes the picture.
    """
    frame = _impostor_tool({
        "mode": "frame",
        "parts": [
            numpy.asarray(part["positions"], dtype=float).reshape(-1, 3).tolist()
            for part, _ in parts
        ],
        "size": IMPOSTOR_SIZE,
    })
    views = []
    for view in frame["views"]:
        image = _splat(parts, library, view["across"], view["left"], view["width"],
                       view["top"], view["height"], view["rows"], fill=True)
        # A texel the tree does not cover takes the mean color of those it
        # does, so filtering at the edge of a leaf does not darken it.
        views.append(numpy.asarray(image, dtype=float).tolist())
    # `tools/carla_image_pack.mojo` stores the floats as bytes, resizes
    # each view, and joins the two pictures.
    pixels, width, height = fix.pack_atlas(views, IMPOSTOR_SIZE)
    tag = library._bake_tag(name, "impostor", parts)
    os.makedirs(os.path.join(out_dir, "textures"), exist_ok=True)
    with open(os.path.join(out_dir, "textures", tag + ".png"), "wb") as handle:
        handle.write(fix.save_png(pixels, width, height, "RGBA", True))
    gltf = library.gltf
    gltf["images"].append({"uri": "textures/" + tag + ".png"})
    gltf["textures"].append({"sampler": 0, "source": len(gltf["images"]) - 1})
    gltf["materials"].append({
        "name": tag,
        "pbrMetallicRoughness": {"baseColorTexture": {"index": len(gltf["textures"]) - 1},
                                 "metallicFactor": 0.0, "roughnessFactor": 0.9},
        "alphaMode": "MASK", "alphaCutoff": 0.5, "doubleSided": True})
    material = len(gltf["materials"]) - 1
    # Lit from above, as a crown is: the picture holds its own shading.
    return {"positions": numpy.array(frame["positions"], dtype=numpy.float64),
            "normals": numpy.array(frame["normals"], dtype=numpy.float64),
            "uvs": numpy.array(frame["uvs"], dtype=numpy.float64),
            "triangles": numpy.array(frame["triangles"], dtype=numpy.int64),
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


def _dilate_tool(image, covered, passes):
    """Return JSON from `tools/carla_town_dilate.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town dilate ")
    try:
        path = os.path.join(folder, "view.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({
                "image": numpy.asarray(image, dtype=numpy.float64).tolist(),
                "covered": numpy.asarray(covered, dtype=bool).tolist(),
                "passes": int(passes),
            }, handle)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_dilate", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "dilate failed")
    return json.loads(result.stdout)


def _dilate(image, covered, passes=6):
    """Spread the covered texels' colors into the uncovered ones next to
    them, so filtering at a view's edge does not bleed the background.

    `tools/carla_town_dilate.mojo` spreads the colors.
    """
    values = _dilate_tool(image, covered, passes)
    if len(numpy.shape(image)) == 0:
        return numpy.asarray(image, dtype=numpy.float64).copy()
    return numpy.array(values, dtype=numpy.float64)


def _view(parts, library, forward, right, up, low_r, low_u, width, height, columns, rows):
    """Return one orthographic view of a mesh's albedo, `rows` by
    `columns` texels, looking down `-forward`, as `_splat` draws a tree's,
    with no light: the renderer lights the far mesh itself.

    `tools/carla_town_splat.mojo` draws the view.
    """
    doc = _raster_tool(parts, library, {
        "mode": "ortho",
        "columns": int(columns),
        "rows": int(rows),
        "samples": 3,
        "cap": 8192,
        "seed": 11,
        "right": numpy.asarray(right, dtype=float).reshape(3).tolist(),
        "up": numpy.asarray(up, dtype=float).reshape(3).tolist(),
        "forward": numpy.asarray(forward, dtype=float).reshape(3).tolist(),
        "low_r": float(low_r),
        "low_u": float(low_u),
        "height": float(height),
        "span_u": float(width),
        "span_v": float(height),
    })
    image = numpy.array(doc, dtype=numpy.float64)
    return _dilate(image[:, :, :3], image[:, :, 3] > 0)


def _join_tool(parts):
    """Return JSON from `tools/carla_town_join.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    payload = {"parts": []}
    for part, _material in parts:
        payload["parts"].append({
            "positions": numpy.asarray(part["positions"], dtype=float).reshape(-1, 3).tolist(),
            "normals": numpy.asarray(part["normals"], dtype=float).reshape(-1, 3).tolist(),
            "uvs": numpy.asarray(part["uvs"], dtype=float).reshape(-1, 2).tolist(),
            "triangles": numpy.asarray(part["triangles"]).reshape(-1, 3).tolist(),
        })
    folder = tempfile.mkdtemp(prefix="town-join-")
    try:
        path = os.path.join(folder, "join.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_join", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "join failed")
    return json.loads(result.stdout)


def _atlas_tool(payload):
    """Return JSON from `tools/carla_town_atlas.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-atlas-")
    try:
        path = os.path.join(folder, "atlas.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_atlas", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "atlas failed")
    return json.loads(result.stdout)


def baked_building(parts, library, out_dir, name, target):
    """Return a building's far level and its material: its mesh gathered
    and collapsed to about `target` triangles, all its primitives as one,
    wearing an atlas of five views of its near level, from each side and
    from above. Each far triangle reads the view that faces it most, so
    its windows and its trim are pictures, not geometry.

    `tools/carla_town_join.mojo` joins the primitives. `tools/carla_town_atlas.mojo`
    sizes the views and writes the texture coordinates. `tools/carla_image_pack.mojo`
    stores the picture as bytes. `tools/carla_jpeg.mojo` writes the picture.
    """
    joined = _join_tool(parts)
    whole = {
        "positions": numpy.array(joined["positions"], dtype=numpy.float64),
        "normals": numpy.array(joined["normals"], dtype=numpy.float64),
        "uvs": numpy.array(joined["uvs"], dtype=numpy.float64),
        "triangles": numpy.array(joined["triangles"], dtype=numpy.int64),
        "material": name,
    }
    far = simplify_welded(whole, target)
    if far is None:
        return None, None
    if far is whole:
        flat = _atlas_tool({
            "mode": "flat",
            "positions": numpy.asarray(whole["positions"], dtype=float).reshape(-1, 3).tolist(),
            "triangles": numpy.asarray(whole["triangles"]).reshape(-1, 3).tolist(),
        })
        far = {"positions": numpy.array(flat["positions"], dtype=numpy.float64),
               "normals": numpy.array(flat["normals"], dtype=numpy.float64),
               "triangles": numpy.array(flat["triangles"], dtype=numpy.int64),
               "material": name}
    spans = _atlas_tool({
        "mode": "spans",
        "positions": numpy.asarray(whole["positions"], dtype=float).reshape(-1, 3).tolist(),
        "density": BAKE_DENSITY,
        "most": BAKE_MOST,
        "views": [{"right": list(right), "up": list(up)} for _, right, up in BAKE_VIEWS],
    })
    cells = []
    for (forward, right, up), span in zip(BAKE_VIEWS, spans):
        image = _view(parts, library, forward, right, up, span["low_r"], span["low_u"],
                      span["width"], span["height"], span["columns"], span["rows"])
        cells.append((image, (span["low_r"], span["high_r"]), (span["low_u"], span["high_u"])))
    views = []
    for (forward, right, up), (image, span_r, span_u) in zip(BAKE_VIEWS, cells):
        views.append({
            "forward": list(forward),
            "right": list(right),
            "up": list(up),
            "span_r": [float(span_r[0]), float(span_r[1])],
            "span_u": [float(span_u[0]), float(span_u[1])],
            "image": numpy.asarray(image, dtype=float).tolist(),
        })
    packed = _atlas_tool({
        "mode": "pack",
        "positions": numpy.asarray(far["positions"], dtype=float).reshape(-1, 3).tolist(),
        "normals": numpy.asarray(far["normals"], dtype=float).reshape(-1, 3).tolist(),
        "views": views,
    })
    stored = fix.pack_quantize(packed["atlas"])
    tag = library._bake_tag(name, "baked", parts, target)
    os.makedirs(os.path.join(out_dir, "textures"), exist_ok=True)
    with open(os.path.join(out_dir, "textures", tag + ".jpg"), "wb") as handle:
        handle.write(fix.save_jpeg(
            stored["pixels"], stored["width"], stored["height"], "RGB", 85, False,
        ))
    gltf = library.gltf
    gltf["images"].append({"uri": "textures/" + tag + ".jpg"})
    gltf["textures"].append({"sampler": 0, "source": len(gltf["images"]) - 1})
    gltf["materials"].append({
        "name": tag,
        "pbrMetallicRoughness": {"baseColorTexture": {"index": len(gltf["textures"]) - 1},
                                 "metallicFactor": 0.0, "roughnessFactor": 0.85},
        "doubleSided": True})
    far["uvs"] = numpy.array(packed["uvs"], dtype=numpy.float64)
    far["material"] = tag
    return far, len(gltf["materials"]) - 1


def _digest_field(values, integral):
    """Return one field as a shape and C-order values."""
    array = numpy.ascontiguousarray(values, dtype="<i8" if integral else "<f8")
    return {
        "shape": [int(dim) for dim in array.shape],
        "values": array.reshape(-1).tolist(),
    }


def geometry_digests(primitives):
    """Return the SHA-256 of each primitive, in order.

    Each field is hashed as its JSON shape plus the little-endian
    contiguous array bytes. An empty dimension contributes no payload
    bytes. `tools/carla_geometry_digest.mojo` packs the arrays and
    does the hash.
    """
    if not primitives:
        return []
    payload = {"primitives": []}
    for primitive in primitives:
        payload["primitives"].append({
            field: _digest_field(primitive[field], field == "triangles")
            for field in ("positions", "normals", "uvs", "triangles")
        })
    root = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
    mojo = os.path.join(root, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    handle = tempfile.NamedTemporaryFile(
        "w", suffix=".json", delete=False, encoding="utf-8",
    )
    path = handle.name
    try:
        json.dump(payload, handle, separators=(",", ":"), allow_nan=True)
        handle.close()
        result = subprocess.run(
            ["sh", os.path.join(root, "tools", "tool.sh"), mojo,
             "carla_geometry_digest", path],
            text=True, capture_output=True, check=False,
        )
    finally:
        os.remove(path)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "geometry digest failed")
    lines = result.stdout.splitlines()
    if len(lines) != len(primitives):
        raise ValueError("geometry digest count mismatch")
    return lines


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
        self._bake_out = out_dir
        self._bake_geometry = {}

    def _bake_tag(self, mesh_path, kind, parts, target=None):
        """Hash ordered, immutable geometry and resolved material inputs.

        The arrays and material tables stay fixed during one build. Hash
        each primitive once, with fixed byte order and widths, independent
        of its original array layout. Keep its reference to prevent object
        id reuse. Placement transforms are applied after cache lookup.
        """
        pending = []
        pending_ids = []
        seen = set()
        for primitive, _material in parts:
            identity = id(primitive)
            if identity not in self._bake_geometry and identity not in seen:
                seen.add(identity)
                pending.append(primitive)
                pending_ids.append(identity)
        if pending:
            digests = geometry_digests(pending)
            for identity, primitive, digest in zip(pending_ids, pending, digests):
                self._bake_geometry[identity] = (primitive, digest)
        ordered = []
        for primitive, material in parts:
            ordered.append((self._bake_geometry[id(primitive)][1], material))
        if kind == "baked":
            settings = [target, BAKE_DENSITY, BAKE_MOST, BAKE_VIEWS, CLUSTER_CELL, CLUSTER_DIVISIONS]
        else:
            settings = [IMPOSTOR_SIZE, IMPOSTOR_SAMPLES, impostor_light()]
        return atlas_tag(self.gltf, self._bake_out, mesh_path, kind, ordered, settings)

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
            # `tools/carla_gltf_rebuild.mojo` drops vehicle tags. A glass
            # blend becomes the town's dark pane.
            fix.rebuild(
                self.package, material, self.mats, self.props, self.pngs, [],
                town=True,
            )
        self.gltf["materials"].append(material)
        self.index[name] = len(self.gltf["materials"]) - 1
        self.masked[name] = material.get("alphaMode") == "MASK"
        return self.index[name]


def slot_materials(row, primitives):
    """Return each primitive's material name for one component: the
    component's material for that slot, by name where UModel named it and
    by position otherwise. A runtime material instance falls back to the
    mesh's own material for the slot.

    `tools/carla_town_slots.mojo` chooses the names.
    """
    folder = tempfile.mkdtemp(prefix="town-slots-")
    try:
        request = os.path.join(folder, "slots.json")
        with open(request, "w", encoding="utf-8") as handle:
            json.dump({"materials": [m if m else None for m in row["materials"]],
                       "own": [primitive["material"] for primitive in primitives]},
                      handle, separators=(",", ":"), allow_nan=False)
        root = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
        mojo = os.path.join(root, ".venv", "bin", "mojo")
        if not os.path.isfile(mojo):
            mojo = "mojo"
        result = subprocess.run(
            ["sh", os.path.join(root, "tools", "tool.sh"), mojo,
             "carla_town_slots", request],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise ValueError(result.stderr.strip() or "town slots failed")
        return json.loads(result.stdout)
    finally:
        shutil.rmtree(folder, ignore_errors=True)


# ---- Building --------------------------------------------------------------

def _share(payload):
    """Return JSON from `tools/carla_town_share.mojo`.

    `grass` keeps one copy in ten. `factors` shares each kind's cap.
    `goal` is the far building target, at least 8.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-share-")
    try:
        path = os.path.join(folder, "share.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_share", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town share failed")
    return json.loads(result.stdout)


def limit_of(kind, total, mesh_path, lod):
    """Return the most triangles one copy of a mesh keeps at a level of
    detail, before the town's cap for its kind."""
    return budget(kind, total, mesh_path) if lod == 0 else far_budget(kind, total, mesh_path)


def lower(primitive, kind, mesh_path, index, total, masked, lod, factor=1.0):
    """Return one primitive of a mesh at a level of detail, or None.
    `factor` is the share of its budget that the town's cap for its kind
    leaves it."""
    # `tools/carla_simplify_target.mojo` chooses the share. A zero budget
    # keeps nothing. A masked mesh keeps leaf cards.
    chosen = fix.simplify_target({
        "mode": "share",
        "budget": int(limit_of(kind, total, mesh_path, lod)),
        "factor": float(factor),
        "triangles": len(primitive["triangles"]),
        "total": int(total),
        "masked": bool(masked),
        "keep": int(fix.KEEP),
    })
    if chosen["action"] == "none":
        return None
    if chosen["action"] == "cards":
        return thin_cards(primitive, chosen["keep"], _card_seed(mesh_path, index, lod))
    if chosen["action"] == "whole":
        return primitive
    return simplify(primitive, chosen["target"], borders=lod == 0, small=chosen["small"])


def _spline_place(local, normals, triangles, rows):
    """Return a bent mesh placed by `tools/carla_town_spline.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-spline-")
    try:
        request = os.path.join(folder, "spline.json")
        payload = {
            "matrix": numpy.asarray(rows, dtype=float).reshape(4, 4).tolist(),
            "positions": numpy.asarray(local, dtype=float).reshape(-1, 3).tolist(),
            "normals": numpy.asarray(normals, dtype=float).reshape(-1, 3).tolist(),
            "triangles": numpy.asarray(triangles).reshape(-1, 3).tolist(),
        }
        with open(request, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_spline", request],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        message = result.stderr.strip() or "spline placement failed"
        if "singular" in message:
            raise numpy.linalg.LinAlgError(message)
        raise ValueError(message)
    placed = json.loads(result.stdout)
    return (numpy.array(placed["points"], dtype=numpy.float64),
            numpy.array(placed["normals"], dtype=numpy.float64),
            numpy.array(placed["triangles"], dtype=numpy.int64))


def place(part, row, rows):
    """Return a primitive's points, normals and triangles placed by one
    copy's world matrix, in the three.js frame.

    A rigid copy is placed by `tools/carla_town_place.mojo`.
    A bent spline mesh is placed by `tools/carla_town_spline.mojo`.
    """
    if "spline" not in row:
        folder = tempfile.mkdtemp(prefix="town-place-")
        try:
            request = os.path.join(folder, "place.json")
            with open(request, "w", encoding="utf-8") as handle:
                json.dump({"matrix": rows.tolist(), "positions": part["positions"].tolist(),
                           "normals": part["normals"].tolist(),
                           "triangles": part["triangles"].tolist()},
                          handle, separators=(",", ":"), allow_nan=False)
            proc = _place_worker()
            try:
                proc.stdin.write("apply\t" + request + "\n")
                proc.stdin.flush()
                line = proc.stdout.readline()
            except (BrokenPipeError, ValueError):
                _place_failed(proc)
            if not line:
                _place_failed(proc)
            if line.startswith("ERR\t"):
                raise ValueError(line[4:].strip() or "town placement failed")
            placed = json.loads(line)
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        return (numpy.array(placed["points"], dtype=numpy.float64),
                numpy.array(placed["normals"], dtype=numpy.float64),
                numpy.array(placed["triangles"], dtype=numpy.int64))
    local, normals = bend(part["positions"], part["normals"], row["spline"])
    return _spline_place(local, normals, part["triangles"], rows)


def _lamp_world(heads, linear, move):
    """Return lamp heads placed by `tools/carla_town_lamps.mojo`.

    The map is `heads @ linear.T + move`, in the three.js frame.
    """
    return _lamps_request({
        "heads": numpy.asarray(heads, dtype=float).reshape(-1, 3).tolist(),
        "linear": numpy.asarray(linear, dtype=float).reshape(3, 3).tolist(),
        "move": numpy.asarray(move, dtype=float).reshape(3).tolist(),
    })


def _lamps_request(payload):
    """Return JSON from `tools/carla_town_lamps.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    fd, path = tempfile.mkstemp(prefix="carla-town-lamps-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_lamps", path],
            capture_output=True, text=True,
        )
    finally:
        os.remove(path)
    if result.returncode != 0:
        message = result.stderr.strip() or "lamp heads failed"
        if "index out of range" in message:
            raise IndexError(message)
        raise ValueError(message)
    return json.loads(result.stdout)


def _lamps_tool(primitives, mesh_path):
    """Return JSON from `tools/carla_town_lamps.mojo`."""
    payload = {"mesh": mesh_path, "primitives": []}
    for primitive in primitives:
        payload["primitives"].append({
            "positions": primitive["positions"].tolist(),
            "triangles": primitive["triangles"].tolist(),
        })
    heads = _lamps_request(payload)
    if heads is None:
        return None
    return numpy.array(heads, dtype=numpy.float64)


def lamp_heads(primitives, mesh_path):
    """Return where a lamp mesh's heads are, in its own frame.

    `tools/carla_town_lamps.mojo` finds each connected piece of glass,
    or the top of a lamp that has no glass. The result is None when
    the mesh is not a lamp.
    """
    return _lamps_tool(primitives, mesh_path)


def _rows_tool(path):
    """Return JSON from `tools/carla_town_rows.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    result = subprocess.run(
        ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
         "carla_town_rows", path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        if not os.path.isfile(path):
            raise FileNotFoundError(path)
        raise ValueError(result.stderr.strip() or "layout read failed")
    return json.loads(result.stdout)


def rows_of(town):
    """Return a town's layout rows.

    `tools/carla_town_rows.mojo` reads the file.
    """
    return _rows_tool(os.path.join(LAYOUT, town + ".jsonl"))


def _copies_tool(payload):
    """Return matrices from `tools/carla_town_copies.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town copies ")
    try:
        path = os.path.join(folder, "row.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_copies", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "placements failed")
    return json.loads(result.stdout)


def placements(row):
    """Return each copy's Unreal row-vector world matrix.

    `tools/carla_town_copies.mojo` builds the matrices.
    """
    payload = {
        "scale": list(row["scale"]),
        "rotation": list(row["rotation"]),
        "location": list(row["location"]),
    }
    if "instances" in row:
        payload["instances"] = [list(flat) for flat in row["instances"]]
    return [numpy.array(matrix, dtype=numpy.float64) for matrix in _copies_tool(payload)]


def _export_file(root, game_path, suffix):
    """Return the exported path from `tools/carla_town_paths.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    result = subprocess.run(
        ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
         "carla_town_paths", "export", root, game_path, suffix],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "export path failed")
    return result.stdout.rstrip("\n")


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
                path = _export_file(RAW, mesh_path, ".gltf")
                meshes[mesh_path] = read_gltf(path) if os.path.exists(path) else []
        primitives = meshes[mesh_path]
        if not primitives:
            continue
        copies = placements(row)
        if "/Vegetation/Grass/" in mesh_path:
            kept = _share({"mode": "grass", "start": grass, "count": len(copies)})
            grass = kept["next"]
            copies = [copies[index] for index in kept["indices"]]
        total = sum(len(p["triangles"]) for p in primitives)
        for lod in LODS:
            planned[(kind, lod)] = planned.get((kind, lod), 0) + limit_of(kind, total, mesh_path, lod) * len(copies)
        jobs.append((row, mesh_path, kind, primitives, copies))
    # Each kind gives up the same share of every mesh's budget to keep
    # under the town's cap: a forest of eight thousand pines thins them all.
    items = [{"kind": kind, "lod": lod, "count": count} for (kind, lod), count in planned.items()]
    shared = _share({"mode": "factors", "items": items})["factors"]
    factors = {(item["kind"], item["lod"]): factor for item, factor in zip(items, shared)}
    for row, mesh_path, kind, primitives, copies in jobs:
        names = slot_materials(row, primitives)
        first_visible = next((i for i, name in enumerate(names) if name != GRID), None)
        if mesh_path not in heads_of:
            heads_of[mesh_path] = lamp_heads(primitives, mesh_path)
        heads = heads_of[mesh_path]
        if heads is not None:
            for rows in copies:
                linear, move = to_three(rows)
                lamps.extend(_lamp_world(heads, linear, move))
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
                    goal = _share({
                        "mode": "goal",
                        "limit": int(limit_of(kind, total, mesh_path, 1)),
                        "factor": float(factors[(kind, 1)]),
                    })["goal"]
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
                    # `tools/carla_town_place.mojo` floors that origin.
                    cell = _tile_cell(rows, tile)
                    group = groups.setdefault((lod, kind, cell, part_material), [[], [], [], []])
                    # `tools/carla_town_buffers.mojo` rounds to float32 and
                    # shifts each copy's triangles by the copies before it.
                    group[0].append(points)
                    group[1].append(normals)
                    group[2].append(part["uvs"])
                    group[3].append(triangles)
    # The town's own road network, so a package brings the map it stands on.
    shutil.copy(os.path.join(MAPS, town + ".xodr"), os.path.join(out_dir, town + ".xodr"))
    return write(town, name, out_dir, library, groups, lamps)


def write(town, name, out_dir, library, groups, lamps):
    """Write the glTF and its buffer, and return the triangle counts of
    the two levels of detail and the node count.

    `tools/carla_town_write.mojo` packs the vertices, writes the loose
    glTF and packs the binary glTF.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    payload = {"out_dir": out_dir, "name": name, "gltf": library.gltf, "groups": [], "lamps": []}
    for (lod, kind, cell, material), group in groups.items():
        payload["groups"].append({
            "lod": int(lod),
            "kind": kind,
            "cell": [int(cell[0]), int(cell[1])],
            "material": int(material),
            "positions": [numpy.asarray(chunk, dtype=float).reshape(-1, 3).tolist() for chunk in group[0]],
            "normals": [numpy.asarray(chunk, dtype=float).reshape(-1, 3).tolist() for chunk in group[1]],
            "uvs": [numpy.asarray(chunk, dtype=float).reshape(-1, 2).tolist() for chunk in group[2]],
            "triangles": [numpy.asarray(chunk).reshape(-1, 3).tolist() for chunk in group[3]],
        })
    for head in lamps:
        payload["lamps"].append([float(value) for value in head])
    folder = tempfile.mkdtemp(prefix="town-write-")
    try:
        path = os.path.join(folder, "write.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_write", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        message = result.stderr.strip()
        if message.startswith("carla_town_write: "):
            message = message[len("carla_town_write: "):]
        if message.startswith("unclean "):
            raise SystemExit(message)
        raise ValueError(message or "town write failed")
    doc = json.loads(result.stdout)
    return doc["triangles"], doc["nodes"]


def to_glb(out_dir, name):
    """Pack a package's glTF, its buffer and its textures into one binary
    glTF, `<name>.glb`, and remove the loose files. A town is then two
    files, the glb and its OpenDRIVE map, and its manifest entry lists
    two members, not a thousand.

    `tools/carla_town_glb.mojo` writes the binary glTF.
    """
    root = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
    mojo = os.path.join(root, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    result = subprocess.run(
        ["sh", os.path.join(root, "tools", "tool.sh"), mojo,
         "carla_town_glb", out_dir, name],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town glb failed")


def check_clean(out_dir):
    """Refuse a package that names an engine or an engine path, in its
    glTF or in a file name.

    `tools/carla_town_clean.mojo` reads the names and the text.
    """
    root = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
    mojo = os.path.join(root, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    result = subprocess.run(
        ["sh", os.path.join(root, "tools", "tool.sh"), mojo,
         "carla_town_clean", out_dir],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or "town package is unclean")


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
