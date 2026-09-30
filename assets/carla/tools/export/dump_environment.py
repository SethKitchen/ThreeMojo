# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Write where every building, prop and plant of each CARLA town stands.

UE Viewer exports CARLA's static meshes, but not where a town places
them: that is in each town's level, which it cannot read. A running
CARLA server can say. This script connects to one, loads each town, and
writes `environment/<town>.json`: every environment object's name, its
semantic label, its transform and its box, in CARLA's frame (meters,
degrees, z up, left-handed).

    CarlaUE4.exe -RenderOffScreen -quality-level=Low
    python dump_environment.py [TOWN ...] [--host localhost] [--port 2000]

It needs CARLA's Python client of the same version: the wheel in the
release's `PythonAPI/carla/dist/`.
"""

import argparse
import json
import os
import sys
import time

BASE = os.path.abspath(os.environ.get("CARLA_EXPORT_DIR", "."))
OUT = os.path.join(BASE, "environment")


def vector(v):
    """Return a CARLA vector as a list."""
    return [round(v.x, 4), round(v.y, 4), round(v.z, 4)]


def rotation(r):
    """Return a CARLA rotation as [pitch, yaw, roll], in degrees."""
    return [round(r.pitch, 4), round(r.yaw, 4), round(r.roll, 4)]


def record(item):
    """Return one environment object as a JSON-ready dict."""
    box = item.bounding_box
    return {
        "id": item.id,
        "name": item.name,
        "label": str(item.type),
        "location": vector(item.transform.location),
        "rotation": rotation(item.transform.rotation),
        "box_center": vector(box.location),
        "box_extent": vector(box.extent),
        "box_rotation": rotation(box.rotation),
    }


def main(argv=None):
    """Dump each town."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("towns", nargs="*")
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=2000)
    args = parser.parse_args(argv)
    import carla  # the release's client, installed from its wheel

    client = carla.Client(args.host, args.port)
    client.set_timeout(120.0)
    towns = args.towns or sorted(m.rsplit("/", 1)[-1] for m in client.get_available_maps())
    os.makedirs(OUT, exist_ok=True)
    for town in towns:
        target = os.path.join(OUT, town + ".json")
        if os.path.exists(target):
            print("kept", target)
            continue
        start = time.time()
        world = client.load_world(town)
        world.tick() if world.get_settings().synchronous_mode else world.wait_for_tick()
        items = world.get_environment_objects(carla.CityObjectLabel.Any)
        data = {
            "town": town,
            "map": world.get_map().name,
            "carla": client.get_server_version(),
            "objects": [record(i) for i in items],
        }
        with open(target, "w", encoding="utf-8") as out:
            json.dump(data, out, indent=0)
        print(f"{town}: {len(items)} objects in {time.time() - start:.0f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
