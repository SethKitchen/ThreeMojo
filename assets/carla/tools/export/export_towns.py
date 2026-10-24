# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Export every mesh and material that CARLA's towns place, with UModel.

`dump_layout.lua`, run inside a CARLA server by UE4SS, writes each town's
layout to `layout/<town>.jsonl`: one line per static mesh component, with
its mesh, its materials, its world transform and its instances. This
script exports each mesh and each material that the layouts name, once,
to `raw_town/`. `build_towns.py` then bakes each town into a package.

    python export_towns.py [TOWN ...]

A mesh or a material that is already exported is kept. Content under
`/Engine/` is not exported: it is Epic's, licensed for use inside the
engine only. `build_towns.py` draws a box of its own for the engine's
cube.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

BASE = os.path.abspath(os.environ.get("CARLA_EXPORT_DIR", "."))
CONTENT = os.path.join(BASE, "release", "CarlaUE4", "Content")
UMODEL = os.path.join(BASE, "umodel", "umodel_64.exe")
LAYOUT = os.path.join(BASE, "layout")
RAW = os.path.join(BASE, "raw_town")
TOWNS = ["Town01", "Town02", "Town03", "Town04", "Town05", "Town10HD"]
# Packages per UModel run, and the most seconds one run may take.
BATCH = 40
LIMIT = 55


def _paths_tool(arguments):
    """Return the text from `tools/carla_town_paths.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    result = subprocess.run(
        ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
         "carla_town_paths", *arguments],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "town paths failed")
    return result.stdout


def object_path(full_name):
    """Return `/Game/A/B` from UE4SS's `Class /Game/A/B.B`.

    `tools/carla_town_paths.mojo` reads the name.
    """
    return _paths_tool(["object", full_name]).rstrip("\n")


def rows(town):
    """Return a town's layout lines."""
    with open(os.path.join(LAYOUT, town + ".jsonl"), encoding="utf-8") as lines:
        return [json.loads(line) for line in lines]


def wanted(towns):
    """Return the meshes and the materials the towns place, as `/Game/...`
    paths, without the engine's.

    `tools/carla_town_paths.mojo` reads the layouts.
    """
    arguments = ["wanted"]
    for town in towns:
        arguments.append(os.path.join(LAYOUT, town + ".jsonl"))
    doc = json.loads(_paths_tool(arguments))
    return doc["meshes"], doc["materials"]


def relative(game_path):
    """Return a `/Game/...` path as the cooked package UModel loads.

    `tools/carla_town_paths.mojo` reads the path.
    """
    return _paths_tool(["relative", game_path]).rstrip("\n")


def _pending(meshes, materials):
    """Return the packages that are not exported yet.

    `tools/carla_town_paths.mojo` skips a file that is already present
    and groups the rest into batches of `BATCH`.
    """
    folder = tempfile.mkdtemp(prefix="town-pending-")
    try:
        path = os.path.join(folder, "pending.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({
                "root": RAW,
                "batch": BATCH,
                "meshes": list(meshes),
                "materials": list(materials),
            }, handle, separators=(",", ":"))
        return json.loads(_paths_tool(["pending", path]))
    finally:
        shutil.rmtree(folder, ignore_errors=True)


def run(batch, mesh):
    """Export one batch of packages. A run that takes too long is split."""
    command = [UMODEL, "-game=ue4.26", "-path=" + CONTENT, "-export", "-png", "-out=" + RAW]
    if mesh:
        command.append("-gltf")
    command.append(relative(batch[0]))
    command += ["-pkg=" + relative(p) for p in batch[1:]]
    try:
        subprocess.run(command, capture_output=True, text=True, errors="replace", timeout=LIMIT)
    except subprocess.TimeoutExpired:
        if len(batch) == 1:
            print("gave up on", batch[0], file=sys.stderr)
            return
        half = len(batch) // 2
        run(batch[:half], mesh)
        run(batch[half:], mesh)


def _export_batches(batches, mesh, label):
    """Export each batch and print how many of `label` are done."""
    total = sum(len(batch) for batch in batches)
    done = 0
    for batch in batches:
        run(batch, mesh)
        done += len(batch)
        print("exported", done, "of", total, label, flush=True)


def main(argv=None):
    """Export what the towns need."""
    towns = (argv if argv is not None else sys.argv[1:]) or TOWNS
    meshes, materials = wanted(towns)
    plan = _pending(meshes, materials)
    print(len(meshes), "meshes,", len(materials), "materials,", plan["todo"], "to export", flush=True)
    _export_batches(plan["mesh_batches"], True, "meshes")
    _export_batches(plan["material_batches"], False, "materials")
    again = _pending(meshes, materials)
    missing = again["meshes"] + again["materials"]
    print(len(missing), "not exported", flush=True)
    for path in missing[:20]:
        print("  ", path)


if __name__ == "__main__":
    main()
