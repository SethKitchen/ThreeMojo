# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Export every CARLA 0.9.16 vehicle to a self-contained glTF package.

For each blueprint id, read the vehicle blueprint's references, ask UModel
which are skeletal and which are static meshes, export the skeletal body
and the static attachments it shows (glass, lights) to glTF, merge them
into one file, and rebuild the materials with `carla_gltf_fix.py`.

    python export_vehicles.py [ID ...]
"""

import json
import os
import re
import shutil
import subprocess
import sys

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


def find_blueprint(relative):
    """Return the blueprint file, matching its name without case."""
    folder = os.path.join(BLUEPRINTS, os.path.dirname(relative))
    want = os.path.basename(relative).lower() + ".uasset"
    for name in os.listdir(folder):
        if name.lower() == want:
            return os.path.join(folder, name)
    # Otherwise the folder's one vehicle blueprint: not a wheel's.
    for name in sorted(os.listdir(folder)):
        low = name.lower()
        if low.startswith("bp_") and low.endswith(".uasset") and not re.search(r"_(f|r)(l|r)?w\.uasset$", low):
            return os.path.join(folder, name)
    raise FileNotFoundError(relative)


def references(blueprint):
    """Return the `/Game/Carla/Static/...` packages a blueprint names."""
    data = open(blueprint, "rb").read()
    return sorted(
        set(m.decode() for m in re.findall(rb"/Game/Carla/Static/[A-Za-z0-9_/\-]+", data))
    )


def package_file(game_path):
    """Return the cooked `.uasset` for a `/Game/...` package, or None.

    A name's number is stored apart from it, so a blueprint can name
    `SK_Volkswagen_T2` for the package `SK_Volkswagen_T2_2021`: a missing
    name falls back to the one package in its folder that extends it.
    """
    rel = game_path[len("/Game/"):] + ".uasset"
    path = os.path.join(CONTENT, *rel.split("/"))
    if os.path.exists(path):
        return path
    folder = os.path.dirname(path)
    stem = os.path.basename(game_path) + "_"
    if os.path.isdir(folder):
        found = [n for n in os.listdir(folder) if n.startswith(stem) and n.endswith(".uasset")
                 and not re.search(r"skeleton|physics", n, re.I)]
        if len(found) == 1:
            return os.path.join(folder, found[0])
    return None


def game_path_of(path):
    """Return the `/Game/...` package path of a cooked `.uasset`."""
    rel = os.path.relpath(path, CONTENT).replace("\\", "/")[: -len(".uasset")]
    return "/Game/" + rel


def export_class(game_path):
    """Return the class of a package's main export, as UModel lists it."""
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
        for line in run.stdout.splitlines():
            parts = line.split()
            if len(parts) >= 5 and parts[-1] == name:
                kind = parts[-2]
                break
    _classes[game_path] = kind
    return kind


def export(game_path):
    """Export one package to glTF under RAW and return the glTF path."""
    rel = os.path.relpath(package_file(game_path), CONTENT).replace("\\", "/")
    subprocess.run(
        [UMODEL, "-game=ue4.26", "-path=" + CONTENT, "-export", "-gltf", "-png", "-out=" + RAW, rel],
        capture_output=True, text=True, errors="replace",
    )
    name = os.path.basename(rel)[: -len(".uasset")]
    folder = os.path.join(RAW, *rel.split("/")[:-1])
    path = os.path.join(folder, name + ".gltf")
    return path if os.path.exists(path) else None


def load(path):
    gltf = json.load(open(path))
    data = open(os.path.join(os.path.dirname(path), gltf["buffers"][0]["uri"]), "rb").read()
    return gltf, bytearray(data)


def merge(base, extra):
    """Append glTF `extra` (a static mesh) into `base`, both loaded."""
    a, abin = base
    b, bbin = extra
    while len(abin) % 4:
        abin.append(0)
    shift = len(abin)
    abin.extend(bbin)
    view0 = len(a["bufferViews"])
    for view in b["bufferViews"]:
        view = dict(view)
        view["buffer"] = 0
        view["byteOffset"] = view.get("byteOffset", 0) + shift
        a["bufferViews"].append(view)
    acc0 = len(a["accessors"])
    for accessor in b["accessors"]:
        accessor = dict(accessor)
        accessor["bufferView"] += view0
        a["accessors"].append(accessor)
    mat0 = len(a.get("materials", []))
    a.setdefault("materials", []).extend(b.get("materials", []))
    mesh0 = len(a["meshes"])
    for mesh in b["meshes"]:
        mesh = json.loads(json.dumps(mesh))
        for primitive in mesh["primitives"]:
            primitive["attributes"] = {k: v + acc0 for k, v in primitive["attributes"].items()}
            if "indices" in primitive:
                primitive["indices"] += acc0
            if "material" in primitive:
                primitive["material"] += mat0
        a["meshes"].append(mesh)
    node0 = len(a["nodes"])
    for node in b["nodes"]:
        node = dict(node)
        if "mesh" in node:
            node["mesh"] += mesh0
        if "children" in node:
            node["children"] = [c + node0 for c in node["children"]]
        a["nodes"].append(node)
    roots = b["scenes"][b.get("scene", 0)]["nodes"]
    a["scenes"][a.get("scene", 0)]["nodes"].extend(r + node0 for r in roots)
    a["buffers"][0]["byteLength"] = len(abin)


def build(vehicle_id):
    blueprint = find_blueprint(VEHICLES[vehicle_id])
    refs = [r for r in references(blueprint) if "/Pedestrian/" not in r]
    skeletal = [r for r in refs if export_class(r) == "SkeletalMesh"]
    static = [
        r for r in refs
        if export_class(r) == "StaticMesh"
        and not re.search(r"_sc_|/sm_sc|_prop$", r, re.I)
    ]
    if not skeletal:
        # A rig the blueprint does not name, in a folder it does.
        folders = sorted(set(os.path.dirname(package_file(r)) for r in refs if package_file(r)))
        for folder in folders:
            for name in sorted(os.listdir(folder)):
                if name.endswith(".uasset") and not re.search(r"skeleton|physics", name, re.I):
                    candidate = game_path_of(os.path.join(folder, name))
                    if export_class(candidate) == "SkeletalMesh":
                        skeletal.append(candidate)
    if not skeletal:
        return None, "no skeletal mesh among " + ", ".join(os.path.basename(r) for r in refs)
    skeletal.sort(key=lambda r: os.path.getsize(package_file(r)[:-7] + ".uexp"), reverse=True)
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
