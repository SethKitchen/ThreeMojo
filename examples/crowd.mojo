# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A crowd of eight, each of a genome and a calling of their own.

    mojo run -I . examples/crowd.mojo [path.png] [frames]

The page is Outfits and armor. The eight callings stand together: a
peasant, a goodwife, an archer, a monk, a merchant, a noblewoman, a
man-at-arms and a knight. Each person's seed picks a genome and a
stature, and `calling_outfit` dresses them for their calling, dyed by
the seed. The women wear their
hair long, in a braid or in a bun. The crowd stands in two rows and
walks in place, each at a pace of their own, while the camera passes
along the front row. It writes `out/crowd.png` and prints how long the
building, the dressing and the frames took.

The optional second argument is how many frames to draw, one or more.
The default is 48.
"""

from tools._example_output import example_destination, gallery_camera
from tools._example_studio import (
    cast_received_shadows,
    studio_floor,
    studio_sun,
)

from animation.animation_mixer import AnimationAction, AnimationMixer
from core.assets import Assets
from core.buffer_geometry import POSITION
from core.object3d import Object3D
from core.scene import Scene
from environments.room_environment import room_environment
from extensions.attire.mix import (
    GOODWIFE,
    NOBLEWOMAN,
    Calling,
    calling_label,
    calling_outfit,
)
from extensions.attire.outfit import dress
from extensions.humanoid.genome import random_genome
from extensions.humanoid.rig.clips import idle_clip, walk_clip
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.skeleton.head.hair.styles import (
    BRAID,
    BUN,
    GROWN,
    LONG,
    HairStyle,
)
from extensions.humanoid.spec import HumanoidSpec
from lights.light import ambient_light
from lights.shadow import PCF_SOFT_SHADOW_MAP
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from render.tonemap import ACES_FILMIC_TONE_MAPPING
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer, available_workers
from std.math import cos, sin
from std.pathlib import Path
from std.sys import argv
from std.time import perf_counter_ns
from units.si import (
    DEGREE,
    INCH,
    METER,
    SECOND,
    Angle,
    Duration,
    Length,
)

comptime DEFAULT_OUTPUT = "out/crowd.png"
comptime WIDTH = 480
comptime HEIGHT = 270
comptime FPS = 24
comptime DEFAULT_FRAMES = 48
comptime PEOPLE = 8
comptime TRIANGLES = 14000
# The seed of the first person; each next one adds seven.
comptime FIRST_SEED = 3


def _seconds_since(start: Int) -> Float64:
    """Return the seconds since `start`, a `perf_counter_ns` reading."""
    return Float64(perf_counter_ns() - start) / 1e9


def _seed_of(index: Int) -> Int:
    """Return the seed of the crowd's `index`th person."""
    return FIRST_SEED + 7 * index


def main() raises:
    var args = argv()
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var frames_wanted = DEFAULT_FRAMES
    if len(args) > 2:
        frames_wanted = max(1, Int(String(args[2])))
    var workers = available_workers()
    var renderer = Renderer(WIDTH, HEIGHT, workers=workers)
    renderer.set_background(Color(20, 21, 24))
    renderer.tone_mapping = ACES_FILMIC_TONE_MAPPING
    renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP
    var assets = Assets()
    var room = room_environment(assets)
    room.update()
    var lighting = pmrem_from_scene(renderer, room, assets, size=64)
    var scene = Scene()
    scene.environment = assets.cube_textures.add(lighting^)
    scene.environment_intensity = 0.7

    var mixer = AnimationMixer()
    var building = Float64(0)
    var dressing = Float64(0)
    var long_hair: List[HairStyle] = [LONG, BRAID, BUN]
    for index in range(PEOPLE):
        var seed = _seed_of(index)
        var calling = Calling(index)
        var sex = MALE
        var style = GROWN
        if calling == GOODWIFE or calling == NOBLEWOMAN:
            sex = FEMALE
            style = long_hair[seed % len(long_hair)]
        var genome = random_genome(seed)
        # Statures from five feet one to six feet one.
        var stature = Length(Float32(61 + seed % 13), INCH)
        var row = index // (PEOPLE // 2)
        var column = index % (PEOPLE // 2)
        var x = (Float32(column) - 1.5) * 1.05 + 0.5 * Float32(row)
        var z = -1.3 * Float32(row)
        var at = scene.add(Object3D())
        var start = perf_counter_ns()
        var person = add_game_humanoid(
            scene,
            assets,
            at,
            HumanoidSpec(stature, sex, genome=genome),
            TRIANGLES,
            hair_style=style,
            workers=workers,
        )
        building += _seconds_since(start)
        # Stand the soles on the floor.
        ref skin = assets.geometries.get(
            scene.skinned_meshes[person.skins[0]].geometry
        )
        ref placed = skin.attribute_view(String(POSITION))
        var lowest = Float32(1e9)
        for v in range(placed.count()):
            lowest = min(lowest, placed.vector3(v).y)
        scene.node(at).set_position(x, -lowest, z)
        start = perf_counter_ns()
        _ = dress(scene, assets, person, calling_outfit(calling, seed))
        dressing += _seconds_since(start)
        print(index, calling_label(calling))
        # Half walk in place and half stand at ease, each at a pace and
        # a phase of their own.
        var clip = walk_clip(person.bones, person.rig)
        if index % 2 == 1:
            clip = idle_clip(person.bones, person.rig)
        var action = AnimationAction(clip^)
        action.time_scale = 0.85 + 0.05 * Float32(seed % 6)
        action.phase = 0.37 * Float32(index)
        var k = mixer.add(action^)
        mixer.action(k).play()
    print("Built the crowd in", building, "s and dressed it in", dressing, "s")

    cast_received_shadows(scene)
    studio_floor(scene, assets, Length(14.0, METER))
    studio_sun(scene, 1.4, 3.6, 3.0, Length(6.0, METER))
    scene.add_light(ambient_light(Color(200, 210, 255), 0.1))

    var step = Duration(Float32(1) / Float32(FPS), SECOND)
    var frames = List[Framebuffer]()
    var start = perf_counter_ns()
    for frame in range(frames_wanted):
        if frame > 0:
            mixer.update(scene, step)
        scene.update()
        var share = Float32(frame) / Float32(max(1, frames_wanted - 1))
        var turn = Float32(-0.45) + Float32(0.9) * share
        var eye = Vector3(5.2 * sin(turn) + 0.25, 1.35, 5.2 * cos(turn) - 0.4)
        var camera = gallery_camera(
            WIDTH,
            HEIGHT,
            eye,
            Vector3(0.25, 0.9, -0.65),
            field_of_view=Angle(36.0, DEGREE),
            near=Length(0.05, METER),
            far=Length(30.0, METER),
        )
        frames.append(renderer.render(scene, assets, camera))
    print("Drew", frames_wanted, "frames in", _seconds_since(start), "s")
    Path(destination).write_bytes(encode(frames, delay_ms=1000 // FPS))
    print("Wrote", destination)
