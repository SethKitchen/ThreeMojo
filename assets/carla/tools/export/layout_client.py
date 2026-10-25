# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Load one CARLA town and ask the layout mod to write it.

`tools/carla_town_layout.mojo` starts the server and calls this client.
The client needs the CARLA wheel of the same release.
"""

import argparse
import time


def main(argv=None):
    """Connect, load `town`, and write the request file."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--town", required=True)
    parser.add_argument("--request", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--seconds", type=float, required=True)
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=2000)
    args = parser.parse_args(argv)
    import carla  # the release's client, installed from its wheel

    end = time.time() + args.seconds
    client = None
    while time.time() < end:
        try:
            client = carla.Client(args.host, args.port)
            client.set_timeout(5.0)
            client.get_server_version()
            break
        except RuntimeError:
            client = None
            time.sleep(min(2.0, max(0.0, end - time.time())))
    if client is None:
        return 2
    client.set_timeout(max(5.0, end - time.time()))
    world = client.load_world(args.town)
    world.wait_for_tick()
    with open(args.request, "w", encoding="utf-8") as handle:
        handle.write(args.target.replace("\\", "/") + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
