# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Measure what a varied crowd of game humanoids costs, person by person.

    mojo run -I . bench/crowd_bench.mojo [people] [frames] [triangles] [cards]

Each person takes a calling, a sex, a genome, a stature, an outfit, a
hairstyle, a beard and, by chance, a cloak from a seed of their own. The
crowd stands in rows ten wide and four meters apart, walking in place,
and the camera looks along the rows from in front. The defaults are 40
people, 8 frames, a skin budget of 16,000 triangles and 400 cards.

It prints, for each person on average, the time to build the humanoid,
to dress it and to hang its cloak, the memory it holds, and the
triangles it draws. For each frame it prints the time to animate the
skeletons, to move the cloaks, to move and shade the hair, and to draw
the frame at 1280 by 720 on the CPU. A cloak or a groom farther than
15 m from the camera rides its bone and is not simulated, as a game
would; the bench says how many did. `move_cloaks` and `move_hair` move
the near ones at once, on every thread.

The memory is the resident set read from `/proc/self/status`, so it is
zero on a machine without one. The numbers describe the machine that
runs it.
"""

from animation.animation_mixer import AnimationAction, AnimationMixer
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.attire.cloth import CLOAK_REACH, Cloak, add_cloak, move_cloaks
from extensions.attire.drape import dressed_colliders
from extensions.attire.mix import (
    calling_beard,
    calling_cloak,
    calling_hair,
    dressed_as,
    mixed_calling,
    mixed_sex,
)
from extensions.attire.outfit import dress
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import random_genome
from extensions.humanoid.rig.clips import walk_clip
from extensions.humanoid.rig.game import GameHumanoid, add_game_humanoid
from extensions.humanoid.rig.game_hair import (
    HAIR_REACH,
    GameHairMotion,
    move_hair,
)
from extensions.humanoid.rig.joints import CHEST
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.simulation import HairWind
from extensions.humanoid.spec import HumanoidSpec
from lights.light import ambient_light, directional_light
from math.vector3 import Vector3
from render.framebuffer import Color
from renderers.renderer import Renderer, available_workers
from std.sys import argv
from std.time import perf_counter_ns
from tools._example_output import gallery_camera
from units.si import DEGREE, INCH, METER, SECOND, Angle, Duration, Length

comptime WIDTH = 1280
comptime HEIGHT = 720
comptime ROW = 10
comptime ACROSS = Float32(0.8)
comptime BETWEEN_ROWS = Float32(4.0)
comptime FIRST_SEED = 1000


def _resident_mb() -> Float64:
    """Return the process's resident memory in megabytes, or zero."""
    try:
        var text = open("/proc/self/status", "r").read()
        for line in text.split("\n"):
            if line.startswith("VmRSS:"):
                var parts = String(line).split()
                return Float64(Int(String(parts[1]))) / 1024.0
    except:
        pass
    return 0


def _seconds(start: Int) -> Float64:
    """Return the seconds since `start`, a `perf_counter_ns` reading."""
    return Float64(perf_counter_ns() - start) / 1e9


def main() raises:
    var args = argv()
    var count = 40
    if len(args) > 1:
        count = max(1, Int(String(args[1])))
    var frames = 8
    if len(args) > 2:
        frames = max(1, Int(String(args[2])))
    var triangles = 16000
    if len(args) > 3:
        triangles = max(0, Int(String(args[3])))
    var cards = 400
    if len(args) > 4:
        cards = max(0, Int(String(args[4])))
    var workers = available_workers()
    var assets = Assets()
    var scene = Scene()
    var mixer = AnimationMixer()
    var people = List[GameHumanoid]()
    var specs = List[HumanoidSpec]()
    var cloaks = List[Cloak]()
    var building = Float64(0)
    var dressing = Float64(0)
    var draping = Float64(0)
    var before = _resident_mb()
    for index in range(count):
        var seed = FIRST_SEED + 37 * index
        var calling = mixed_calling(seed)
        var sex = mixed_sex(seed)
        var inches = (63 if sex == FEMALE else 68) + seed % 7
        var spec = HumanoidSpec(
            Length(Float32(inches), INCH), sex, TONED, random_genome(seed)
        )
        var at = scene.add(Object3D())
        scene.node(at).set_position(
            (Float32(index % ROW) - Float32(ROW - 1) / 2) * ACROSS,
            0,
            -Float32(index // ROW) * BETWEEN_ROWS,
        )
        var start = perf_counter_ns()
        var person = add_game_humanoid(
            scene,
            assets,
            at,
            spec,
            triangles,
            hair_style=calling_hair(calling, sex, seed),
            workers=workers,
            beard=calling_beard(calling, sex, seed),
            cards=cards,
        )
        building += _seconds(start)
        start = perf_counter_ns()
        var outfit = dressed_as(calling, sex, seed)
        var dressed = dress(scene, assets, person, outfit)
        dressing += _seconds(start)
        start = perf_counter_ns()
        var cut = calling_cloak(calling, sex, seed)
        if cut:
            var over = dressed_colliders(person, outfit, dressed)
            scene.update()
            cloaks.append(add_cloak(scene, assets, person, cut.take(), over))
        draping += _seconds(start)
        var action = AnimationAction(walk_clip(person.bones, person.rig))
        action.phase = 0.37 * Float32(index)
        var k = mixer.add(action^)
        mixer.action(k).play()
        mixer.action(k).fade_in(Duration(0.5, SECOND))
        people.append(person^)
        specs.append(spec)
    var built = _resident_mb()
    var drawn = 0
    for mesh in scene.skinned_meshes:
        drawn += assets.geometries.get(mesh.geometry).triangle_count()
    for mesh in scene.meshes:
        drawn += assets.geometries.get(mesh.geometry).triangle_count()
    var n = Float64(count)
    print("people", count, "workers", workers, "budget", triangles)
    print("cards", cards)
    print("build per person, s", building / n)
    print("dress per person, s", dressing / n)
    print("cloaks", len(cloaks), "hung in, s", draping)
    print("memory per person, MB", (built - before) / n)
    print("triangles per person", drawn // count)

    scene.update()
    var start = perf_counter_ns()
    var motions = List[GameHairMotion]()
    for index in range(count):
        motions.append(GameHairMotion(scene, people[index], specs[index]))
    print("hair motion per person, s", _seconds(start) / n)
    print("memory before drawing, MB", _resident_mb())
    var sun = Vector3(1.4, 3.6, 3.0)
    sun.normalize()
    var lights = List[HairLight]()
    lights.append(HairLight(sun, Vector3(2.3, 2.2, 2.0)))
    var key = Object3D()
    key.set_position(sun.x, sun.y, sun.z)
    var key_node = scene.add(key^)
    scene.add_light(directional_light(Color(255, 242, 226), key_node, 2.6))
    scene.add_light(ambient_light(Color(200, 210, 255), 0.3))
    var renderer = Renderer(WIDTH, HEIGHT, workers=workers)
    var eye = Vector3(0, 1.6, 6.0)
    var camera = gallery_camera(
        WIDTH,
        HEIGHT,
        eye,
        Vector3(0, 1.0, -4.0),
        field_of_view=Angle(50.0, DEGREE),
        near=Length(0.05, METER),
        far=Length(60.0, METER),
    )
    var step = Duration(Float32(1) / Float32(24), SECOND)
    var animating = Float64(0)
    var stepping = Float64(0)
    var grooming = Float64(0)
    var drawing = Float64(0)
    scene.update()
    for _ in range(frames):
        start = perf_counter_ns()
        mixer.update(scene, step)
        scene.update()
        animating += _seconds(start)
        start = perf_counter_ns()
        move_cloaks(cloaks, scene, assets, step, eye, workers)
        stepping += _seconds(start)
        start = perf_counter_ns()
        move_hair(
            motions,
            scene,
            assets,
            people,
            lights,
            eye,
            Vector3(0.12, 0.12, 0.13),
            HairWind(Vector3(1, 0, 0), 0.2),
            workers,
        )
        grooming += _seconds(start)
        start = perf_counter_ns()
        _ = renderer.render(scene, assets, camera)
        drawing += _seconds(start)
    var f = Float64(frames)
    var near = 0
    var near_cloaks = 0
    for index in range(count):
        var chest = scene.world_matrix(people[index].bones[CHEST.value])
        if (chest.transform_point(Vector3(0, 0, 0)) - eye).length() <= (
            HAIR_REACH
        ):
            near += 1
    for k in range(len(cloaks)):
        var anchor = scene.world_matrix(cloaks[k].anchor)
        if (anchor.transform_point(Vector3(0, 0, 0)) - eye).length() <= (
            CLOAK_REACH
        ):
            near_cloaks += 1
    print("people within reach", near, "cloaks stepped", near_cloaks)
    print("animate per frame, ms", animating / f * 1000)
    print("cloaks per frame, ms", stepping / f * 1000)
    print("hair per frame, ms", grooming / f * 1000)
    print("draw per frame, ms", drawing / f * 1000)
    print("memory after drawing, MB", _resident_mb())
