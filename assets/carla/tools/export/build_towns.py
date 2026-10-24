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


# ---- Impostors -------------------------------------------------------------

# Texels a side of an impostor's view, and samples each covered texel takes.
IMPOSTOR_SIZE = 256
IMPOSTOR_SAMPLES = 4
# The light an impostor's texels are shaded by, three.js frame: high and
# from the side, as the sun is most of the day. `tools/carla_town_impostor.mojo`
# normalizes it.
_IMPOSTOR_LIGHT = None


def _albedo_tool(payload):
    """Return a material's base color from `tools/carla_town_albedo.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-albedo-")
    try:
        path = os.path.join(folder, "albedo.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_albedo", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town albedo failed")
    return json.loads(result.stdout)


def _colored_part(part, material, library):
    """Return one mesh part with its base color for a picture."""
    color = _albedo_tool({
        "out_dir": library.package.out_dir,
        "material": library.gltf["materials"][material],
        "textures": library.gltf.get("textures", []),
        "images": library.gltf.get("images", []),
    })
    entry = library.gltf["materials"][material]
    item = {
        "positions": numpy.asarray(part["positions"], dtype=float).reshape(-1, 3).tolist(),
        "normals": numpy.asarray(part["normals"], dtype=float).reshape(-1, 3).tolist(),
        "uvs": numpy.asarray(part["uvs"], dtype=float).reshape(-1, 2).tolist(),
        "triangles": numpy.asarray(part["triangles"]).reshape(-1, 3).tolist(),
        "factor": color["factor"],
        "cut": float(entry.get("alphaCutoff", 0.5)),
        "masked": entry.get("alphaMode") == "MASK",
    }
    if "image" in color:
        item["image"] = color["image"]
    return item



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


def _tree_tool(payload):
    """Return the crossing quads from `tools/carla_town_tree.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-tree-")
    try:
        path = os.path.join(folder, "tree.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_tree", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town tree failed")
    return json.loads(result.stdout)


def impostor(parts, library, out_dir, name):
    """Return a tree's far level, two quads that cross on its trunk, each
    showing a picture of the tree drawn from its near level; and the
    picture's material. `parts` are the tree's primitives, each with its
    material's index.

    `tools/carla_town_tree.mojo` draws the two views, writes the PNG, and
    builds the quads. The picture holds its own shading.
    """
    items = [_colored_part(part, material, library) for part, material in parts]
    tag = library._bake_tag(name, "impostor", parts)
    os.makedirs(os.path.join(out_dir, "textures"), exist_ok=True)
    frame = _tree_tool({
        "size": IMPOSTOR_SIZE,
        "samples": IMPOSTOR_SAMPLES,
        "out": os.path.join(out_dir, "textures", tag + ".png"),
        "parts": items,
    })
    material = _append_picture(
        library.gltf, "impostor", tag, "textures/" + tag + ".png"
    )
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


def _attach(payload):
    """Return JSON from `tools/carla_town_attach.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-attach-")
    try:
        path = os.path.join(folder, "attach.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_attach", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town attach failed")
    return json.loads(result.stdout)


def _append_picture(gltf, kind, name, uri):
    """Append one picture and return its material index.

    `tools/carla_town_attach.mojo` builds the image, the texture and the
    material from the counts already in the package.
    """
    record = _attach({
        "mode": "picture",
        "kind": kind,
        "name": name,
        "uri": uri,
        "images": len(gltf["images"]),
        "textures": len(gltf["textures"]),
        "materials": len(gltf["materials"]),
    })
    gltf["images"].append(record["image"])
    gltf["textures"].append(record["texture"])
    gltf["materials"].append(record["material"])
    return record["index"]



def _bake_tool(payload):
    """Return texture coordinates from `tools/carla_town_bake.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-bake-")
    try:
        path = os.path.join(folder, "bake.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_bake", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town bake failed")
    return json.loads(result.stdout)


def baked_building(parts, library, out_dir, name, target):
    """Return a building's far level and its material: its mesh gathered
    and collapsed to about `target` triangles, all its primitives as one,
    wearing an atlas of five views of its near level, from each side and
    from above. Each far triangle reads the view that faces it most, so
    its windows and its trim are pictures, not geometry.

    `tools/carla_town_join.mojo` joins the primitives. `tools/carla_town_bake.mojo`
    draws the five views and writes the JPEG.
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
        flat = _bake_tool({
            "mode": "flat",
            "positions": numpy.asarray(whole["positions"], dtype=float).reshape(-1, 3).tolist(),
            "triangles": numpy.asarray(whole["triangles"]).reshape(-1, 3).tolist(),
        })
        far = {"positions": numpy.array(flat["positions"], dtype=numpy.float64),
               "normals": numpy.array(flat["normals"], dtype=numpy.float64),
               "triangles": numpy.array(flat["triangles"], dtype=numpy.int64),
               "material": name}
    items = [_colored_part(part, material, library) for part, material in parts]
    tag = library._bake_tag(name, "baked", parts, target)
    os.makedirs(os.path.join(out_dir, "textures"), exist_ok=True)
    packed = _bake_tool({
        "out": os.path.join(out_dir, "textures", tag + ".jpg"),
        "density": BAKE_DENSITY,
        "most": BAKE_MOST,
        "whole": {
            "positions": numpy.asarray(whole["positions"], dtype=float).reshape(-1, 3).tolist(),
        },
        "far": {
            "positions": numpy.asarray(far["positions"], dtype=float).reshape(-1, 3).tolist(),
            "normals": numpy.asarray(far["normals"], dtype=float).reshape(-1, 3).tolist(),
        },
        "parts": items,
        "views": [
            {"forward": list(forward), "right": list(right), "up": list(up)}
            for forward, right, up in BAKE_VIEWS
        ],
    })
    index = _append_picture(library.gltf, "baked", tag, "textures/" + tag + ".jpg")
    far["uvs"] = numpy.array(packed["uvs"], dtype=numpy.float64)
    far["material"] = tag
    return far, index


def _digest_field(values, integral):
    """Return one field as a nested array, or a shaped empty field."""
    array = numpy.ascontiguousarray(values, dtype="<i8" if integral else "<f8")
    if array.size == 0:
        return {
            "shape": [int(dim) for dim in array.shape],
            "values": [],
        }
    return array.tolist()


def geometry_digests(primitives):
    """Return the SHA-256 of each primitive, in order.

    Each field is hashed as its JSON shape plus the little-endian
    contiguous array bytes. An empty dimension contributes no payload
    bytes. `tools/carla_geometry_digest.mojo` packs a nested array in
    that same order and does the hash.
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
        chosen = _attach({"mode": "resolve", "name": name or ""})
        if chosen["action"] == "plain":
            material = chosen["material"]
        else:
            # `tools/carla_gltf_rebuild.mojo` drops vehicle tags. A glass
            # blend becomes the town's dark pane.
            material = {"name": name}
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


def _lower_tool(payload):
    """Return JSON from `tools/carla_town_lower.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-lower-")
    try:
        path = os.path.join(folder, "lower.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_lower", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town lower failed")
    return json.loads(result.stdout)


def lower(primitive, kind, mesh_path, index, total, masked, lod, factor=1.0):
    """Return one primitive of a mesh at a level of detail, or None.
    `factor` is the share of its budget that the town's cap for its kind
    leaves it.

    `tools/carla_town_lower.mojo` chooses that level. A zero budget keeps
    nothing. A masked mesh keeps leaf cards. Level 0 keeps open edges.
    """
    doc = _lower_tool({
        "positions": numpy.asarray(primitive["positions"], dtype=float).reshape(-1, 3).tolist(),
        "normals": numpy.asarray(primitive["normals"], dtype=float).reshape(-1, 3).tolist(),
        "uvs": numpy.asarray(primitive["uvs"], dtype=float).reshape(-1, 2).tolist(),
        "triangles": numpy.asarray(primitive["triangles"]).reshape(-1, 3).tolist(),
        "material": primitive["material"],
        "kind": kind if kind is not None else "",
        "mesh": mesh_path,
        "index": int(index),
        "total": int(total),
        "masked": bool(masked),
        "lod": int(lod),
        "factor": float(factor),
        "keep": int(fix.KEEP),
    })
    if doc["action"] == "none":
        return None
    if doc["action"] == "whole":
        return primitive
    return {
        "positions": numpy.array(doc["positions"], dtype=numpy.float64),
        "normals": numpy.array(doc["normals"], dtype=numpy.float64),
        "uvs": numpy.array(doc["uvs"], dtype=numpy.float64),
        "triangles": numpy.array(doc["triangles"], dtype=numpy.int64),
        "material": primitive["material"],
    }


def _lamp_copies(heads, copies):
    """Return every copy's lamp heads in the renderer frame.

    `tools/carla_town_lamps.mojo` converts each matrix and places the
    heads. The map is `heads @ linear.T + move`.
    """
    return _lamps_request({
        "heads": numpy.asarray(heads, dtype=float).reshape(-1, 3).tolist(),
        "matrices": [
            numpy.asarray(rows, dtype=float).reshape(4, 4).tolist()
            for rows in copies
        ],
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


def _plan(payload):
    """Return JSON from `tools/carla_town_plan.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-plan-")
    try:
        path = os.path.join(folder, "plan.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_plan", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town plan failed")
    return json.loads(result.stdout)


def _group(payload):
    """Return placed groups from `tools/carla_town_group.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="town-group-")
    try:
        path = os.path.join(folder, "group.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, separators=(",", ":"), allow_nan=False)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_town_group", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        message = result.stderr.strip()
        if message.startswith("carla_town_group: "):
            message = message[len("carla_town_group: "):]
        if "singular" in message:
            raise numpy.linalg.LinAlgError(message)
        raise ValueError(message or "town group failed")
    return json.loads(result.stdout)["groups"]


def build(town, max_size, tile):
    """Write one town's package, and return the triangle counts of its
    two levels of detail and its node count.

    `tools/carla_town_plan.mojo` chooses which meshes stay and which far
    level each one uses. `tools/carla_town_group.mojo` places each copy
    and merges copies that share a tile, a kind and a material.
    """
    name = "carla.town." + town.lower()
    out_dir = os.path.join(OUT, name)
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir)
    library = Library(out_dir, max_size)
    meshes = {}
    lowered = {}
    pending = []
    # Each lamp head, in the three.js frame, and each lamp mesh's heads.
    lamps = []
    heads_of = {}
    visible = []
    for row in rows_of(town):
        if not row["visible"]:
            continue
        _, mesh_path, _ = object_path(row["mesh"])
        visible.append((row, mesh_path))
    chosen = _plan({
        "mode": "select",
        "rows": [{"mesh": mesh_path, "visible": True} for _, mesh_path in visible],
    })["rows"]
    prepared = []
    for slot in chosen:
        row, mesh_path = visible[slot]
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
        prepared.append({
            "row": row,
            "mesh": mesh_path,
            "primitives": primitives,
            "copies": copies,
            "materials": slot_materials(row, primitives),
            "triangles": sum(len(p["triangles"]) for p in primitives),
        })
    plan = _plan({
        "mode": "jobs",
        "rows": [{
            "mesh": item["mesh"],
            "copies": len(item["copies"]),
            "triangles": int(item["triangles"]),
            "materials": item["materials"],
        } for item in prepared],
    })
    for item, job in zip(prepared, plan["jobs"]):
        row = item["row"]
        mesh_path = item["mesh"]
        primitives = item["primitives"]
        names = item["materials"]
        kind = job["kind"]
        copies = [item["copies"][index] for index in job["copies"]]
        if mesh_path not in heads_of:
            heads_of[mesh_path] = lamp_heads(primitives, mesh_path)
        heads = heads_of[mesh_path]
        if heads is not None and copies:
            lamps.extend(_lamp_copies(heads, copies))
        total = item["triangles"]
        for part in job["parts"]:
            index = part["index"]
            material_name = part["material"]
            primitive = primitives[index]
            material = library.material(material_name)
            if job["lamp_glass"]:
                library.gltf["materials"][material]["extras"] = dict(LAMP_TAG)
            for level in part["levels"]:
                if level["action"] == "skip":
                    continue
                lod = level["lod"]
                part_material = material
                if level["action"] == "baked":
                    # A building's far level is its baked proxy, made once
                    # for all its primitives.
                    parts = [(p, library.material(n)) for p, n in zip(primitives, names) if n != GRID]
                    goal = level["goal"]
                    key = library._bake_tag(mesh_path, "baked", parts, goal)
                    if key not in lowered:
                        lowered[key] = baked_building(parts, library, out_dir, mesh_path, goal)
                    part_mesh, part_material = lowered[key]
                elif level["action"] == "impostor":
                    # A tree's far level is its impostor, drawn once for
                    # all its primitives.
                    parts = [(p, library.material(n)) for p, n in zip(primitives, names) if n != GRID]
                    key = library._bake_tag(mesh_path, "impostor", parts)
                    if key not in lowered:
                        lowered[key] = impostor(parts, library, out_dir, mesh_path)
                    part_mesh, part_material = lowered[key]
                else:
                    key = (mesh_path, index, material_name, lod)
                    if key not in lowered:
                        lowered[key] = lower(primitive, kind, mesh_path, index, total,
                                             library.masked[material_name], lod, level["factor"])
                    part_mesh = lowered[key]
                if part_mesh is None:
                    continue
                STATS[mesh_path] = STATS.get(mesh_path, 0) + len(part_mesh["triangles"]) * len(copies)
                one_copies = []
                for rows in copies:
                    entry = {
                        "matrix": numpy.asarray(rows, dtype=float).reshape(4, 4).tolist(),
                    }
                    if "spline" in row:
                        entry["spline"] = row["spline"]
                    one_copies.append(entry)
                pending.append({
                    "lod": int(lod),
                    "kind": kind,
                    "material": int(part_material),
                    "positions": numpy.asarray(part_mesh["positions"], dtype=float).reshape(-1, 3).tolist(),
                    "normals": numpy.asarray(part_mesh["normals"], dtype=float).reshape(-1, 3).tolist(),
                    "uvs": numpy.asarray(part_mesh["uvs"], dtype=float).reshape(-1, 2).tolist(),
                    "triangles": numpy.asarray(part_mesh["triangles"]).reshape(-1, 3).tolist(),
                    "copies": one_copies,
                })
    grouped = _group({"tile": float(tile), "parts": pending})
    # The town's own road network, so a package brings the map it stands on.
    shutil.copy(os.path.join(MAPS, town + ".xodr"), os.path.join(out_dir, town + ".xodr"))
    return write(town, name, out_dir, library, grouped, lamps)


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
    payload = {"out_dir": out_dir, "name": name, "gltf": library.gltf, "groups": groups, "lamps": []}
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
