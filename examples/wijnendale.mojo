# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wijnendale Castle in autumn, seen from the air.

    mojo run -I . examples/wijnendale.mojo [path.png]

The page is Castle. `wijnendale` is the plan: towers, ranges, a gatehouse,
a moat and a bridge in meters. `add_castle` draws it. The sun stands where
it stood over Torhout at 15:30 on 19 October, from the equations of Duffie
and Beckman. The camera looks north from above the moat, as the aerial
photograph does.
"""

from tools._example_output import (
    example_destination,
    gallery_camera,
    gallery_renderer,
)

from core.assets import Assets
from core.fog import linear_fog
from core.object3d import Object3D
from core.scene import Scene
from extensions.castle.plan import PlanPoint, wijnendale
from extensions.castle.render import CastleOptions, add_castle
from extensions.castle.sun import castle_sun, scene_direction
from extensions.energy.solar import day_of_year
from geometries.plane import plane
from lights.light import ambient_light, directional_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from math.vector3 import Vector3
from objects.reflector import Reflector
from objects.sky import Sky
from render.framebuffer import Color
from render.png import encode
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from std.pathlib import Path
from units.si import (
    DEGREE,
    HOUR,
    METER,
    Angle,
    Duration64,
    Length,
    Length64,
)

comptime DEFAULT_OUTPUT = "out/castle.png"
comptime WIDTH = 480
comptime HEIGHT = 600


def main() raises:
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var plan = wijnendale()
    var assets = Assets()
    var scene = Scene()
    var eye = Vector3(6, 50, 108)
    var options = CastleOptions.default()
    options.water = False
    options.clearing = PlanPoint(
        Length64(Float64(eye.x), METER), Length64(Float64(-eye.z), METER)
    )
    options.clearing_radius = Length64(58.0, METER)
    var castle = add_castle(scene, assets, plan, options)
    print(
        plan.name,
        "-",
        castle.meshes,
        "meshes,",
        castle.triangles,
        "triangles",
    )

    var sun = castle_sun(
        plan,
        day_of_year(10, 19),
        Duration64(15.5, HOUR),
        Duration64(2.0, HOUR),
    )
    var toward = scene_direction(sun)

    var dome = Object3D()
    dome.set_scale(4400, 4400, 4400)
    var sky_node = scene.add(dome^)
    var sky = Sky(assets, sky_node)
    scene.add_mesh(sky.mesh)
    assets.programs.get(sky.program).set_uniform(
        "sunPosition",
        Vector3(Float32(toward.x), Float32(toward.y), Float32(toward.z)),
    )
    assets.programs.get(sky.program).set_uniform("turbidity", Float32(2.5))
    assets.programs.get(sky.program).set_uniform("rayleigh", Float32(1.6))
    assets.materials.materials[sky.mesh.material.value].fog = False

    # The water is a mirror at the level of the moat.
    var water = Object3D()
    water.rotate_x(Angle(-90.0, DEGREE))
    water.set_position(
        Float32(plan.moat.center.x.value),
        Float32(-plan.moat.freeboard.value),
        Float32(-plan.moat.center.y.value),
    )
    var water_node = scene.add(water^)
    var mirror = Reflector(
        assets,
        assets.geometries.add(
            plane(Length(130.0, METER), Length(110.0, METER))
        ),
        water_node,
        color=Color(104, 128, 126),
        texture_width=WIDTH,
        texture_height=HEIGHT,
        multisample=0,
    )
    scene.add_mesh(mirror.mesh)

    var lamp = Object3D()
    lamp.set_position(
        Float32(toward.x) * 160,
        Float32(toward.y) * 160,
        Float32(toward.z) * 160,
    )
    var lamp_node = scene.add(lamp^)
    var light = directional_light(Color(255, 232, 196), lamp_node, 3.4)
    light.cast_shadow = True
    light.shadow.map_size = 2048
    light.shadow.bias = -0.0005
    light.shadow.normal_bias = 0.15
    light.shadow.set_extent(Length(70.0, METER))
    light.shadow.near = Length(40.0, METER)
    light.shadow.far = Length(300.0, METER)
    scene.add_light(light)
    scene.add_light(ambient_light(Color(176, 198, 232), 0.75))

    var haze = Color(176, 192, 208)
    scene.fog = linear_fog(haze, Length(300.0, METER), Length(3000.0, METER))
    var renderer = gallery_renderer(WIDTH, HEIGHT, haze)
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    renderer.set_tone_mapping(ACES_FILMIC_TONE_MAPPING, Float32(0.8))
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        eye,
        Vector3(13, 8, -2),
        field_of_view=Angle(55.0, DEGREE),
        near=Length(1.0, METER),
        far=Length(4000.0, METER),
    )
    scene.update()
    _ = mirror.update(renderer, scene, assets, camera)
    var image = renderer.render(scene, assets, camera)
    Path(destination).write_bytes(encode(image))
    print("Wrote", destination)
