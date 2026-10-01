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
import subprocess
import sys

BASE = os.path.abspath(os.environ.get("CARLA_EXPORT_DIR", "."))
CONTENT = os.path.join(BASE, "release", "CarlaUE4", "Content")
UMODEL = os.path.join(BASE, "umodel", "umodel_64.exe")
LAYOUT = os.path.join(BASE, "layout")
RAW = os.path.join(BASE, "raw_town")
TOWNS = ["Town01", "Town02", "Town03", "Town04", "Town05", "Town10HD"]
# Packages per UModel run, and the most seconds one run may take.
BATCH = 40
LIMIT = 55


def object_path(full_name):
    """Return `/Game/A/B` from UE4SS's `Class /Game/A/B.B`."""
    return full_name.split(" ", 1)[1].rsplit(".", 1)[0]


def rows(town):
    """Return a town's layout lines."""
    with open(os.path.join(LAYOUT, town + ".jsonl"), encoding="utf-8") as lines:
        return [json.loads(line) for line in lines]


def wanted(towns):
    """Return the meshes and the materials the towns place, as `/Game/...`
    paths, without the engine's."""
    meshes, materials = set(), set()
    for town in towns:
        for row in rows(town):
            meshes.add(object_path(row["mesh"]))
            materials.update(object_path(m) for m in row["materials"] if m)
    game = lambda paths: sorted(p for p in paths if p.startswith("/Game/"))
    return game(meshes), game(materials)


def relative(game_path):
    """Return a `/Game/...` path as the cooked package UModel loads."""
    return game_path[len("/Game/"):] + ".uasset"


def exported(game_path, suffix):
    """Return whether a package's export is already in RAW."""
    return os.path.exists(os.path.join(RAW, *game_path[len("/Game/"):].split("/")) + suffix)


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


def main(argv=None):
    """Export what the towns need."""
    towns = (argv if argv is not None else sys.argv[1:]) or TOWNS
    meshes, materials = wanted(towns)
    todo = [(p, True) for p in meshes if not exported(p, ".gltf")]
    todo += [(p, False) for p in materials if not exported(p, ".mat")]
    print(len(meshes), "meshes,", len(materials), "materials,", len(todo), "to export", flush=True)
    for kind in (True, False):
        paths = [p for p, mesh in todo if mesh == kind]
        for start in range(0, len(paths), BATCH):
            run(paths[start:start + BATCH], kind)
            print("exported", min(start + BATCH, len(paths)), "of", len(paths),
                  "meshes" if kind else "materials", flush=True)
    missing = [p for p in meshes if not exported(p, ".gltf")]
    missing += [p for p in materials if not exported(p, ".mat")]
    print(len(missing), "not exported", flush=True)
    for path in missing[:20]:
        print("  ", path)


if __name__ == "__main__":
    main()
