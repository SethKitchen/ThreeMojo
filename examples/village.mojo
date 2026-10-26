# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A village on the meadow: houses, a scanned building and a pond, in the
wind-bent grass.

    mojo run -I . examples/village.mojo [path.png] [SCAN]

The page is Village. With no SCAN the village has a brick house, a timber
barn and a pond, so it runs with no download and its picture is always
the same. SCAN is the id of a cached scan in
`assets/building_scans/manifest.json`, or the path of a scan file that
`extensions.scan.files` reads. Its building is cut out of its ground and
stands on the meadow too. Fetch a scan first:

    sh tools/tool.sh .venv/bin/mojo building_scans fetch seem-church

The program prints, as JSON, how long each step took and what the frame
drew.
"""

from tools._example_output import example_destination

from core.assets import Assets
from core.clock import Clock
from core.scene import Scene
from extensions.building.scan.catalog import (
    CATALOG_CACHE,
    CATALOG_MANIFEST,
    ScanCatalog,
)
from extensions.scan.files import read_scan
from extensions.scan.frame import supersplat_frame
from extensions.vegetation.meadow import meadow_camera, meadow_renderer
from extensions.village.scanned import CutBuilding, cut_building
from extensions.village.village import Village, VillageParameters
from extensions.water.pebbles import pebble_bed
from render.jpeg import decode
from render.png import encode
from std.pathlib import Path
from std.sys import argv, stderr
from units.si import METER, MILLISECOND, SECOND, Duration, Length

comptime DEFAULT_OUTPUT = "out/village.png"
comptime PEBBLES = "assets/pebbles.jpg"
comptime WIDTH = 1280
comptime HEIGHT = 720
# The voxel a scan's grid starts from, in meters.
comptime VOXEL = Float32(0.5)


def _scan(words: List[String]) raises -> Optional[CutBuilding]:
    """Return the building of the scan the command line names, or None.

    Args:
        words: The command line.

    Returns:
        The building cut out of its scan, or None with no SCAN.

    Raises:
        Error: If a named scan is not cached, or cannot be read or cut.
    """
    if len(words) < 3:
        return None
    var wanted = words[2]
    var catalog = ScanCatalog.open(CATALOG_MANIFEST, CATALOG_CACHE)
    for entry in catalog.entries:
        if entry.id == wanted:
            var path = catalog.scene(wanted)
            if not path:
                raise Error(
                    "The scan '"
                    + wanted
                    + "' is not cached: sh tools/tool.sh .venv/bin/mojo"
                    " building_scans fetch "
                    + wanted
                )
            return cut_building(
                read_scan(path.value()).geometry,
                entry.frame,
                Length(VOXEL, METER),
            )
    return cut_building(
        read_scan(wanted).geometry, supersplat_frame(), Length(VOXEL, METER)
    )


def main() raises:
    var words = List[String]()
    for word in argv():
        words.append(String(word))
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var clock = Clock()
    clock.start()
    var scan = _scan(words)
    var cut = clock.elapsed().to(MILLISECOND)
    var renderer = meadow_renderer(WIDTH, HEIGHT)
    var assets = Assets()
    var scene = Scene()
    var parameters = VillageParameters()
    var bed = pebble_bed(decode(Path(PEBBLES).read_bytes()))
    var village = Village(scene, assets, renderer, parameters, bed^, scan^)
    var built = clock.elapsed().to(MILLISECOND) - cut
    var camera = meadow_camera(
        parameters.meadow, WIDTH, HEIGHT, Length(0.0, METER)
    )
    var frame = Clock()
    frame.start()
    var stats = village.update(scene, assets, camera, Duration(2.0, SECOND))
    var prepared = frame.elapsed().to(MILLISECOND)
    var image = village.render(renderer, scene, assets, camera)
    var drawn = frame.elapsed().to(MILLISECOND) - prepared
    Path(destination).write_bytes(encode(image))
    print(
        '{"scan_ms": ',
        cut,
        ', "build_ms": ',
        built,
        ', "prepare_ms": ',
        prepared,
        ', "render_ms": ',
        drawn,
        ', "houses": ',
        len(village.houses),
        ', "scanned": ',
        "true" if village.scanned else "false",
        ', "blades": ',
        stats.blades,
        ', "grass_triangles": ',
        stats.triangles,
        "}",
        sep="",
        file=stderr,
    )
    print("Wrote", destination)
