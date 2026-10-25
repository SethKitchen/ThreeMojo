# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Read environment objects from a running CARLA server.

`tools/carla_town_environment.mojo` writes the rounded file. This client
needs the CARLA wheel of the same release.
"""

import argparse
import json
import sys


def main(argv=None):
    """Print the map names, or one town's raw objects."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--town", default="")
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=2000)
    args = parser.parse_args(argv)
    import carla  # the release's client, installed from its wheel

    client = carla.Client(args.host, args.port)
    client.set_timeout(120.0)
    if args.list:
        names = sorted(item.rsplit("/", 1)[-1] for item in client.get_available_maps())
        json.dump(names, sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0
    world = client.load_world(args.town)
    world.tick() if world.get_settings().synchronous_mode else world.wait_for_tick()
    items = world.get_environment_objects(carla.CityObjectLabel.Any)
    objects = []
    for item in items:
        box = item.bounding_box
        objects.append({
            "id": item.id,
            "name": item.name,
            "label": str(item.type),
            "location": [item.transform.location.x, item.transform.location.y,
                         item.transform.location.z],
            "rotation": [item.transform.rotation.pitch, item.transform.rotation.yaw,
                         item.transform.rotation.roll],
            "box_center": [box.location.x, box.location.y, box.location.z],
            "box_extent": [box.extent.x, box.extent.y, box.extent.z],
            "box_rotation": [box.rotation.pitch, box.rotation.yaw, box.rotation.roll],
        })
    json.dump({
        "town": args.town,
        "map": world.get_map().name,
        "carla": client.get_server_version(),
        "objects": objects,
    }, sys.stdout, separators=(",", ":"), allow_nan=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
