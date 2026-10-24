# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Export every CARLA 0.9.16 vehicle to a self-contained glTF package.

For each blueprint id, read the vehicle blueprint's references and ask
UModel for each mesh class. `tools/carla_vehicle_pick.mojo` chooses the
skeletal body and the static glass and lights. The script exports those
meshes to glTF, merges them into one file, and rebuilds the materials
with `carla_gltf_fix.py`.

    python export_vehicles.py [ID ...]
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
# The work folder: the cooked content, UModel and every stage's output.
BASE = os.path.abspath(os.environ.get("CARLA_EXPORT_DIR", "."))
CONTENT = os.path.join(BASE, "cooked", "CarlaUE4", "Content")
UMODEL = os.path.join(BASE, "umodel", "umodel_64.exe")
RAW = os.path.join(BASE, "raw")
PACKAGES = os.path.join(BASE, "packages")
BLUEPRINTS = os.path.join(CONTENT, "Carla", "Blueprints", "Vehicles")

# Blueprint id (`vehicle.<make>.<model>`, from VehicleFactory) -> the
# vehicle blueprint, relative to Blueprints/Vehicles.
VEHICLES = {
    "vehicle.audi.a2": "AudiA2/BP_AudiA2",
    "vehicle.audi.tt": "AudiTT/BP_AudiTT",
    "vehicle.bmw.grandtourer": "BmwGrandTourer/BP_BmwGranTourer",
    "vehicle.micro.microlino": "BmwIsetta/BP_BmwIsetta",
    "vehicle.carlamotors.carlacola": "CarlaCola/BP_CarlaCola",
    "vehicle.chevrolet.impala": "ChevroletImpala/BP_ChevroletImpala",
    "vehicle.citroen.c3": "CitroenC3/BP_CitroenC3",
    "vehicle.dodge.charger_police": "DodgeChargerPolice/BP_DodgeCharger",
    "vehicle.jeep.wrangler_rubicon": "JeepWranglerRubicon/BP_JeepWranglerRubicon",
    "vehicle.mercedes.coupe": "Mercedes/BP_MercedesCoupe",
    "vehicle.mini.cooper_s": "Mini/BP_Mini",
    "vehicle.nissan.micra": "NissanMicra/BP_NissanMicra",
    "vehicle.nissan.patrol": "NissanPatrol/BP_NissanPatrol",
    "vehicle.seat.leon": "SeatLeon/BP_SeatLeon",
    "vehicle.toyota.prius": "ToyotaPrius/BP_ToyotaPrius",
    "vehicle.harley-davidson.low_rider": "2Wheeled/Harley/BP_Harley",
    "vehicle.yamaha.yzf": "2Wheeled/Yamaha/BP_Yamaha",
    "vehicle.kawasaki.ninja": "2Wheeled/KawasakiNinja/BP_KawasakiNinja",
    "vehicle.bh.crossbike": "2Wheeled/CrossBike/BP_CrossBike",
    "vehicle.gazelle.omafiets": "2Wheeled/LeisureBike/BP_LeisureBike",
    "vehicle.diamondback.century": "2Wheeled/RoadBike/BP_RoadBike",
    "vehicle.audi.etron": "AudiETron/BP_Audi_Etron",
    "vehicle.tesla.cybertruck": "Cybertruck/BP_Cybertruck",
    "vehicle.tesla.model3": "Tesla/BP_TeslaM3",
    "vehicle.volkswagen.t2": "VolkswagenT2/BP_VolkswagenT2",
    "vehicle.lincoln.mkz_2017": "LincolnMKZ2017/BP_LincolnMKZ",
    "vehicle.ford.mustang": "Mustang/BP_Mustang66",
    "vehicle.lincoln.mkz_2020": "LincolnMKZ2020/BP_LincolnMKZ2020",
    "vehicle.mercedes.coupe_2020": "MercedesCCC/BP_MercedesCCC",
    "vehicle.dodge.charger_2020": "DodgeCharger2020/Charger2020/BP_Charger2020",
    "vehicle.dodge.charger_police_2020": "DodgeCharger2020/ChargerCop/BP_ChargerCop",
    "vehicle.ford.ambulance": "Ambulance/BP_Ambulance",
    "vehicle.carlamotors.firetruck": "FireTruck/BP_Firetruck",
    "vehicle.vespa.zx125": "2Wheeled/Vespa/BP_Vespa",
    "vehicle.mini.cooper_s_2021": "Mini2021/BP_Mini2021",
    "vehicle.nissan.patrol_2021": "NissanPatrol2021/BP_NissanPatrol2021",
    "vehicle.mercedes.sprinter": "Sprinter/BP_Sprinter",
    "vehicle.ford.crown": "Ford_Crown/BP_Ford_Crown",
    "vehicle.volkswagen.t2_2021": "Volkswagen_T2_2021/BP_VolkswagenT2_2021",
    "vehicle.mitsubishi.fusorosa": "MitsubishiFusoRosa/BP_MitsubishiFusoRosa",
    "vehicle.carlamotors.european_hgv": "European_HGV/BP_European_HGV",
}

_classes = {}


def _paths_tool(kind, *args):
    """Return text from `tools/carla_vehicle_paths.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    result = subprocess.run(
        ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
         "carla_vehicle_paths", kind, *args],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        if kind == "blueprint":
            raise FileNotFoundError(name)
        raise ValueError(result.stderr.strip() or "vehicle path failed")
    return result.stdout.rstrip("\n")


def find_blueprint(relative):
    """Return the blueprint file, matching its name without case.

    `tools/carla_vehicle_paths.mojo` finds the file.
    """
    return _paths_tool("blueprint", BLUEPRINTS, relative)


def _refs_tool(path):
    """Return JSON from `tools/carla_vehicle_refs.mojo`."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    result = subprocess.run(
        ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
         "carla_vehicle_refs", path],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "vehicle references failed")
    return json.loads(result.stdout)


def references(blueprint):
    """Return the `/Game/Carla/Static/...` packages a blueprint names.

    `tools/carla_vehicle_refs.mojo` reads the file.
    """
    return _refs_tool(blueprint)


def package_file(game_path):
    """Return the cooked `.uasset` for a `/Game/...` package, or None.

    A name's number is stored apart from it, so a blueprint can name
    `SK_Volkswagen_T2` for the package `SK_Volkswagen_T2_2021`: a missing
    name falls back to the one package in its folder that extends it.

    `tools/carla_vehicle_paths.mojo` finds the file.
    """
    found = _paths_tool("package", CONTENT, game_path)
    return found or None


def game_path_of(path):
    """Return the `/Game/...` package path of a cooked `.uasset`.

    `tools/carla_vehicle_paths.mojo` reads the path.
    """
    return _paths_tool("game", CONTENT, path)


def _class_tool(name, listing):
    """Return the class from `tools/carla_umodel_class.mojo`, or None."""
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
    mojo = os.path.join(repo, ".venv", "bin", "mojo")
    if not os.path.isfile(mojo):
        mojo = "mojo"
    folder = tempfile.mkdtemp(prefix="umodel-class-")
    try:
        path = os.path.join(folder, "list.txt")
        with open(path, "w", encoding="utf-8", errors="replace") as handle:
            handle.write(listing)
        result = subprocess.run(
            ["sh", os.path.join(repo, "tools", "tool.sh"), mojo,
             "carla_umodel_class", name, path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "umodel class failed")
    return result.stdout.rstrip("\n") or None


def export_class(game_path):
    """Return the class of a package's main export, as UModel lists it.

    `tools/carla_umodel_class.mojo` reads the listing.
    """
    if game_path in _classes:
        return _classes[game_path]
    path = package_file(game_path)
    kind = None
    if path:
        rel = os.path.relpath(path, CONTENT).replace("\\", "/")
        run = subprocess.run(
            [UMODEL, "-game=ue4.26", "-path=" + CONTENT, "-list", rel],
            capture_output=True, text=True, errors="replace",
        )
        name = os.path.basename(path)[: -len(".uasset")]
        kind = _class_tool(name, run.stdout)
    _classes[game_path] = kind
    return kind


def export(game_path):
    """Export one package to glTF under RAW and return the glTF path.

    `tools/carla_vehicle_paths.mojo` names that glTF file.
    """
    package = package_file(game_path)
    rel = os.path.relpath(package, CONTENT).replace("\\", "/")
    subprocess.run(
        [UMODEL, "-game=ue4.26", "-path=" + CONTENT, "-export", "-gltf", "-png", "-out=" + RAW, rel],
        capture_output=True, text=True, errors="replace",
    )
    path = _paths_tool("gltf", RAW, CONTENT, package)
    return path if os.path.exists(path) else None


def load(path):
    gltf = json.load(open(path))
    data = open(os.path.join(os.path.dirname(path), gltf["buffers"][0]["uri"]), "rb").read()
    return gltf, bytearray(data)


def _tool_root():
    """Return the repository root that holds `tools/tool.sh`."""
    return os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))


def _tool_mojo():
    """Return the Mojo compiler, as the Makefile's `TOOL_MOJO` chooses it."""
    path = os.path.join(_tool_root(), ".venv", "bin", "mojo")
    if os.path.isfile(path):
        return path
    return "mojo"


def merge(base, extra):
    """Append glTF `extra` (a static mesh) into `base`, both loaded.

    `tools/carla_vehicle_merge.mojo` appends the buffer and renumbers
    the views, accessors, materials, meshes and nodes.
    """
    a, abin = base
    b, bbin = extra
    folder = tempfile.mkdtemp(prefix="vehicle-merge-")
    try:
        base_gltf = os.path.join(folder, "base.gltf")
        base_bin = os.path.join(folder, "base.bin")
        extra_gltf = os.path.join(folder, "extra.gltf")
        extra_bin = os.path.join(folder, "extra.bin")
        out_gltf = os.path.join(folder, "out.gltf")
        out_bin = os.path.join(folder, "out.bin")
        with open(base_gltf, "w", encoding="utf-8") as handle:
            json.dump(a, handle)
        with open(base_bin, "wb") as handle:
            handle.write(bytes(abin))
        with open(extra_gltf, "w", encoding="utf-8") as handle:
            json.dump(b, handle)
        with open(extra_bin, "wb") as handle:
            handle.write(bytes(bbin))
        root = _tool_root()
        result = subprocess.run(
            ["sh", os.path.join(root, "tools", "tool.sh"), _tool_mojo(),
             "carla_vehicle_merge", base_gltf, base_bin, extra_gltf, extra_bin,
             out_gltf, out_bin],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise ValueError(result.stderr.strip() or "vehicle merge failed")
        with open(out_gltf, encoding="utf-8") as handle:
            merged = json.load(handle)
        with open(out_bin, "rb") as handle:
            data = handle.read()
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    a.clear()
    a.update(merged)
    abin.clear()
    abin.extend(data)


def _pick_tool(refs, extras):
    """Return the body and glass from `tools/carla_vehicle_pick.mojo`."""
    folder = tempfile.mkdtemp(prefix="vehicle-pick-")
    try:
        path = os.path.join(folder, "pick.json")
        with open(path, "w", encoding="utf-8") as handle:
            json.dump({"refs": refs, "extras": extras}, handle, separators=(",", ":"))
        root = _tool_root()
        result = subprocess.run(
            ["sh", os.path.join(root, "tools", "tool.sh"), _tool_mojo(),
             "carla_vehicle_pick", path],
            capture_output=True, text=True,
        )
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    if result.returncode != 0:
        raise ValueError(result.stderr.strip() or "vehicle pick failed")
    return json.loads(result.stdout)


def _mesh_record(path, kind, size, name=None):
    """Return one mesh record for `tools/carla_vehicle_pick.mojo`."""
    record = {"path": path, "class": kind, "size": int(size)}
    if name is not None:
        record["name"] = name
    return record


def _uexp_size(game_path):
    """Return the cooked `.uexp` size used to choose the body."""
    return os.path.getsize(package_file(game_path)[:-7] + ".uexp")


def _choice_records(named):
    """Return the blueprint meshes, without asking UModel about pedestrians."""
    records = []
    for ref in named:
        if "/Pedestrian/" in ref:
            records.append(_mesh_record(ref, "", 0))
            continue
        kind = export_class(ref) or ""
        size = _uexp_size(ref) if kind == "SkeletalMesh" else 0
        records.append(_mesh_record(ref, kind, size))
    return records


def _folder_records(named):
    """Return skeletal candidates from folders the blueprint already names.

    A file whose name contains `skeleton` or `physics` is left out before
    UModel runs. The comparison ignores case.
    """
    folders = []
    seen = set()
    for ref in named:
        if "/Pedestrian/" in ref:
            continue
        package = package_file(ref)
        if not package:
            continue
        folder = os.path.dirname(package)
        if folder not in seen:
            seen.add(folder)
            folders.append(folder)
    extras = []
    for folder in sorted(folders):
        for name in sorted(os.listdir(folder)):
            if not name.endswith(".uasset") or re.search(r"skeleton|physics", name, re.I):
                continue
            candidate = game_path_of(os.path.join(folder, name))
            kind = export_class(candidate) or ""
            size = _uexp_size(candidate) if kind == "SkeletalMesh" else 0
            extras.append(_mesh_record(candidate, kind, size, name))
    return extras


def build(vehicle_id):
    blueprint = find_blueprint(VEHICLES[vehicle_id])
    named = references(blueprint)
    records = _choice_records(named)
    # `tools/carla_vehicle_pick.mojo` chooses the body and the glass.
    choice = _pick_tool(records, [])
    if choice["error"]:
        choice = _pick_tool(records, _folder_records(named))
    if choice["error"]:
        return None, choice["error"]
    skeletal = choice["skeletal"]
    static = choice["static"]
    body = export(skeletal[0])
    if not body:
        return None, "UModel exported nothing for " + skeletal[0]
    merged = load(body)
    added = []
    for ref in static:
        path = export(ref)
        if path:
            merge(merged, load(path))
            added.append(os.path.basename(ref))
    work = os.path.join(BASE, "merged", vehicle_id)
    os.makedirs(work, exist_ok=True)
    gltf, data = merged
    gltf["buffers"][0]["uri"] = vehicle_id + ".bin"
    open(os.path.join(work, vehicle_id + ".bin"), "wb").write(bytes(data))
    json.dump(gltf, open(os.path.join(work, vehicle_id + ".gltf"), "w"))
    out = os.path.join(PACKAGES, vehicle_id)
    run = subprocess.run(
        [sys.executable, os.path.join(HERE, "carla_gltf_fix.py"), RAW,
         os.path.join(work, vehicle_id + ".gltf"), out, vehicle_id],
        capture_output=True, text=True,
    )
    if run.returncode != 0:
        return None, run.stderr[-400:]
    size = sum(os.path.getsize(os.path.join(b, f)) for b, _, fs in os.walk(out) for f in fs)
    return out, f"{os.path.basename(skeletal[0])} + {len(added)} attachments, {size / 1e6:.1f} MB"


def main():
    ids = sys.argv[1:] or list(VEHICLES)
    for vehicle_id in ids:
        try:
            out, note = build(vehicle_id)
        except Exception as error:  # report and go on to the next
            out, note = None, repr(error)
        print(("OK  " if out else "FAIL") + f" {vehicle_id:36s} {note}", flush=True)


if __name__ == "__main__":
    main()
