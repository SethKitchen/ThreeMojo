# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Write where each CARLA town places every mesh: its layout.

The Python API names each environment object but not its mesh, and the
cooked levels do not say either in a form UE Viewer reads. A running
server knows both. This script installs `layout_dump/main.lua` as a mod of
UE4SS (https://github.com/UE4SS-RE/RE-UE4SS, experimental build 3.0.1-1152
or later: 3.0.1 crashes CARLA 0.9.16) in the release's binary folder, and
for each town:

1. starts the server with `-nullrhi`, so it draws nothing and does not use
   the GPU;
2. loads the town;
3. asks the mod for a dump, and waits for it;
4. stops the server.

Each server runs at most `--limit` seconds and is then stopped, whatever
it is doing. The layout of a town is `layout/<town>.jsonl`: one line per
static mesh component, with its mesh, its materials, its world transform
and its instances, in centimeters and degrees.

    python dump_layout.py [TOWN ...] [--limit 60]

Put UE4SS's `dwmapi.dll` and `ue4ss/` folder in
`release/CarlaUE4/Binaries/Win64/` first. The CARLA client wheel must be
installed, as for `dump_environment.py`.
"""

import argparse
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.abspath(os.environ.get("CARLA_EXPORT_DIR", "."))
BINARIES = os.path.join(BASE, "release", "CarlaUE4", "Binaries", "Win64")
SERVER = os.path.join(BINARIES, "CarlaUE4-Win64-Shipping.exe")
MOD = os.path.join(BINARIES, "ue4ss", "Mods", "LayoutDump")
REQUEST = os.path.join(BINARIES, "layout_dump_request.txt")
OUT = os.path.join(BASE, "layout")
TOWNS = ["Town01", "Town02", "Town03", "Town04", "Town05", "Town10HD_Opt"]


def install():
    """Copy the mod into UE4SS's mods and enable only it."""
    if not os.path.isdir(os.path.join(BINARIES, "ue4ss")):
        raise SystemExit("UE4SS is not in " + BINARIES)
    os.makedirs(os.path.join(MOD, "Scripts"), exist_ok=True)
    shutil.copy(os.path.join(HERE, "layout_dump", "main.lua"), os.path.join(MOD, "Scripts", "main.lua"))
    with open(os.path.join(BINARIES, "ue4ss", "Mods", "mods.json"), "w") as mods:
        mods.write('[{"mod_name": "LayoutDump", "mod_enabled": true}]\n')
    with open(os.path.join(BINARIES, "ue4ss", "Mods", "mods.txt"), "w") as mods:
        mods.write("LayoutDump : 1\n")


def connect(carla, seconds):
    """Return a client once the server answers, within `seconds`."""
    end = time.time() + seconds
    while time.time() < end:
        try:
            client = carla.Client("localhost", 2000)
            client.set_timeout(5.0)
            client.get_server_version()
            return client
        except RuntimeError:
            time.sleep(2)
    return None


def dump(carla, town, limit):
    """Dump one town with one server run of at most `limit` seconds."""
    target = os.path.join(OUT, (town[: -len("_Opt")] if town.endswith("_Opt") else town) + ".jsonl")
    for path in (target, target + ".done", target + ".progress", REQUEST):
        if os.path.exists(path):
            os.remove(path)
    start = time.time()
    server = subprocess.Popen([SERVER, "CarlaUE4", "-nullrhi"], cwd=BINARIES,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        client = connect(carla, limit)
        if client is None:
            return "the server did not answer"
        client.set_timeout(max(5.0, limit - (time.time() - start)))
        world = client.load_world(town)
        world.wait_for_tick()
        with open(REQUEST, "w") as request:
            request.write(target.replace("\\", "/") + "\n")
        while time.time() - start < limit:
            if os.path.exists(target + ".done"):
                return open(target + ".done").read().strip()
            if server.poll() is not None:
                return "the server stopped while reading " + open(target + ".progress").read().splitlines()[-1]
            time.sleep(1)
        return "out of time"
    finally:
        server.kill()
        server.wait()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("towns", nargs="*")
    parser.add_argument("--limit", type=float, default=60.0)
    args = parser.parse_args(argv)
    import carla  # the release's client, installed from its wheel

    install()
    os.makedirs(OUT, exist_ok=True)
    for town in args.towns or TOWNS:
        print(town + ":", dump(carla, town, args.limit), flush=True)


if __name__ == "__main__":
    main()
