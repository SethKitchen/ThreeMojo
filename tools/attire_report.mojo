# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Print the template estimates of an outfit on the six-foot template.

    mojo run -I . tools/attire_report.mojo [--outfit NAME] [--file PATH]
        [--triangles N] [--body-kg KG]

`--outfit` names an outfit of `outfit_named`: `peasant`, `man-at-arms` or
`knight`, the default. `--file` reads an outfit saved by `outfit_json`
instead. `--triangles` sets the humanoid's triangle budget, 30,000 by
default. `--body-kg` sets the body's own mass for the locomotion cost,
80 kg by default.

The report is one JSON object on standard output: each garment's mass,
the total, the locomotion cost, the coverage of each region, the
protection at six points against a 60 J and a 130 J blow, the noise and
the visibility. Every number is a template estimate; see the wiki page
Attire estimates.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.attire.estimate import attire_report
from extensions.attire.outfit import Outfit, dress
from extensions.attire.preset import outfit_from_json, outfit_named
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from renderers.renderer import available_workers
from units.si import FOOT, KILOGRAM, Length, Mass

comptime USAGE = (
    "usage: attire_report.mojo [--outfit NAME] [--file PATH]"
    " [--triangles N] [--body-kg KG]"
)


def _refuse(message: String):
    """Print a message and the usage, and exit with status two."""
    print("attire_report.mojo: error: " + message, file=stderr)
    print(USAGE, file=stderr)
    exit(2)


def main() raises:
    var args = argv()
    var name = String("knight")
    var file = String()
    var triangles = 30000
    var body = Float32(80)
    var k = 1
    while k < len(args):
        var option = String(args[k])
        if option == "--help" or option == "-h":
            print(USAGE)
            return
        if k + 1 >= len(args):
            _refuse(option + " needs a value")
            return
        var value = String(args[k + 1])
        if option == "--outfit":
            name = value
        elif option == "--file":
            file = value
        elif option == "--triangles":
            triangles = Int(value)
        elif option == "--body-kg":
            body = Float32(Float64(value))
        else:
            _refuse("unknown option " + option)
            return
        k += 2
    var outfit: Outfit
    if file:
        outfit = outfit_from_json(Path(file).read_text())
    else:
        outfit = outfit_named(name)
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = add_game_humanoid(
        scene,
        assets,
        root,
        HumanoidSpec(Length(6.0, FOOT), MALE),
        triangles,
        workers=available_workers(),
    )
    var bare = assets.geometries.get(
        scene.skinned_meshes[person.skins[0]].geometry
    ).clone()
    var dressed = dress(scene, assets, person, outfit)
    var record = attire_report(
        bare, person.rig, outfit, dressed, Mass(body, KILOGRAM)
    )
    print(record.to_json())
