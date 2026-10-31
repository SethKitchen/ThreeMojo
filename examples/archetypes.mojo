# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Seven callings, each as a man and a woman, with their hair in motion.

    mojo run -I . examples/archetypes.mojo [path.png] [frames] [cards]

The page is Outfits and armor. A farmer, a barbarian, a royal, a wizard,
a warlock, a ranger and a warrior stand side by side, the men in front
and the women behind. Each person's seed picks a genome, a stature, the
dyes, the metals and the headwear of their calling, and a hairstyle.
Each man's calling picks his beard. Each person's hair is cards of
fibers that `GameHairMotion` moves with the head and shades for the
lights. Half walk in place and half stand at ease while the camera
passes along the front row. It writes `out/archetypes.png` and prints
how long the building, the dressing and the frames took.

The optional second argument is how many frames to draw, one or more.
The default is 36. The optional third argument is the cards of hair on
each head; zero draws each hair's shell alone. The default is 500.
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
    BARBARIAN,
    FARMER,
    RANGER,
    ROYAL,
    WARLOCK,
    WARRIOR,
    WIZARD,
    Calling,
    calling_label,
    dressed_as,
)
from extensions.attire.outfit import dress
from extensions.humanoid.athleticism import TONED, UNTONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.rig.clips import idle_clip, walk_clip
from extensions.humanoid.rig.game import GameHumanoid, add_game_humanoid
from extensions.humanoid.rig.game_hair import GameHairMotion
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.skeleton.head.hair.beard import (
    CHIN_STRAP,
    CLEAN_SHAVEN,
    FORKED_BEARD,
    GOATEE,
    LONG_BEARD,
    MUSTACHE,
    SHORT_BEARD,
    Beard,
)
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.simulation import HairWind
from extensions.humanoid.skeleton.head.hair.styles import (
    BRAID,
    BUN,
    GROWN,
    HALF_UP,
    LONG,
    PONYTAIL,
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

comptime DEFAULT_OUTPUT = "out/archetypes.png"
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FPS = 24
comptime DEFAULT_FRAMES = 36
comptime DEFAULT_CARDS = 500
comptime TRIANGLES = 16000
# The seed of the first person; each next one adds nine.
comptime FIRST_SEED = 5
# The sun, from where it shines, as the studio places it.
comptime SUN = Vector3(1.4, 3.6, 3.0)


def _seconds_since(start: Int) -> Float64:
    """Return the seconds since `start`, a `perf_counter_ns` reading."""
    return Float64(perf_counter_ns() - start) / 1e9


def _callings() -> List[Calling]:
    """Return the seven callings, left to right."""
    return [FARMER, BARBARIAN, ROYAL, WIZARD, WARLOCK, RANGER, WARRIOR]


def _beard(calling: Calling) -> Beard:
    """Return the beard a man of a calling grows."""
    if calling == WIZARD:
        return LONG_BEARD
    if calling == BARBARIAN:
        return FORKED_BEARD
    if calling == ROYAL:
        return SHORT_BEARD
    if calling == RANGER or calling == WARLOCK:
        return GOATEE
    if calling == FARMER:
        return MUSTACHE
    return CHIN_STRAP


def _style(calling: Calling, woman: Bool, seed: Int) -> HairStyle:
    """Return the hairstyle of a person of a calling."""
    if not woman:
        if calling == BARBARIAN or calling == WIZARD:
            return LONG
        return GROWN
    var styles: List[HairStyle] = [LONG, BRAID, PONYTAIL, HALF_UP, BUN]
    return styles[seed % len(styles)]


def main() raises:
    var args = argv()
    var destination = example_destination(String(DEFAULT_OUTPUT))
    var frames_wanted = DEFAULT_FRAMES
    if len(args) > 2:
        frames_wanted = max(1, Int(String(args[2])))
    var cards = DEFAULT_CARDS
    if len(args) > 3:
        cards = max(0, Int(String(args[3])))
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
    var people = List[GameHumanoid]()
    var specs = List[HumanoidSpec]()
    var building = Float64(0)
    var dressing = Float64(0)
    var callings = _callings()
    var count = len(callings)
    for index in range(2 * count):
        var row = index // count
        var column = index % count
        var calling = callings[column]
        var woman = row == 1
        var seed = FIRST_SEED + 9 * index
        var sex: Sex = FEMALE if woman else MALE
        var build = TONED
        if calling == WIZARD or calling == ROYAL or calling == WARLOCK:
            build = UNTONED
        # Men from five feet eight to six feet two, women from five feet
        # three to five feet nine.
        var inches = (68 if not woman else 63) + seed % 7
        var spec = HumanoidSpec(
            Length(Float32(inches), INCH), sex, build, random_genome(seed)
        )
        var beard = CLEAN_SHAVEN if woman else _beard(calling)
        var x = (
            Float32(column) - Float32(count - 1) / 2
        ) * 0.66 + 0.33 * Float32(row)
        var z = -1.1 * Float32(row)
        var at = scene.add(Object3D())
        var start = perf_counter_ns()
        var person = add_game_humanoid(
            scene,
            assets,
            at,
            spec,
            TRIANGLES,
            hair_style=_style(calling, woman, seed),
            workers=workers,
            beard=beard,
            cards=cards,
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
        _ = dress(scene, assets, person, dressed_as(calling, sex, seed))
        dressing += _seconds_since(start)
        print(index, calling_label(calling), "woman" if woman else "man")
        # Half walk in place and half stand at ease, each at a pace and
        # a phase of their own.
        var clip = walk_clip(person.bones, person.rig)
        if (index + row) % 2 == 1:
            clip = idle_clip(person.bones, person.rig)
        var action = AnimationAction(clip^)
        action.time_scale = 0.85 + 0.05 * Float32(seed % 6)
        action.phase = 0.37 * Float32(index)
        var k = mixer.add(action^)
        mixer.action(k).play()
        people.append(person^)
        specs.append(spec)
    print(
        "Built the people in", building, "s and dressed them in", dressing, "s"
    )

    cast_received_shadows(scene)
    studio_floor(scene, assets, Length(16.0, METER))
    studio_sun(scene, SUN.x, SUN.y, SUN.z, Length(7.0, METER))
    scene.add_light(ambient_light(Color(200, 210, 255), 0.1))
    scene.update()
    var motions = List[GameHairMotion]()
    for index in range(len(people)):
        motions.append(GameHairMotion(scene, people[index], specs[index]))
    var sun = SUN
    sun.normalize()
    var lights = List[HairLight]()
    lights.append(HairLight(sun, Vector3(2.3, 2.2, 2.0)))
    var ambient = Vector3(0.12, 0.12, 0.13)
    var breeze = Vector3(1.0, 0.0, 0.4)
    breeze.normalize()

    var step = Duration(Float32(1) / Float32(FPS), SECOND)
    var frames = List[Framebuffer]()
    var start = perf_counter_ns()
    for frame in range(frames_wanted):
        if frame > 0:
            mixer.update(scene, step)
        scene.update()
        var share = Float32(frame) / Float32(max(1, frames_wanted - 1))
        var turn = Float32(-0.4) + Float32(0.8) * share
        var eye = Vector3(4.5 * sin(turn) + 0.2, 1.5, 4.5 * cos(turn) - 0.3)
        for index in range(len(people)):
            motions[index].update(
                scene,
                assets,
                people[index],
                lights,
                eye,
                ambient,
                HairWind(breeze, 0.25),
            )
        var camera = gallery_camera(
            WIDTH,
            HEIGHT,
            eye,
            Vector3(0.15, 1.05, -0.55),
            field_of_view=Angle(38.0, DEGREE),
            near=Length(0.05, METER),
            far=Length(30.0, METER),
        )
        frames.append(renderer.render(scene, assets, camera))
    print("Drew", frames_wanted, "frames in", _seconds_since(start), "s")
    Path(destination).write_bytes(encode(frames, delay_ms=1000 // FPS))
    print("Wrote", destination)
