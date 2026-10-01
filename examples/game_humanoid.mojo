# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A humanoid as a game uses it: baked once, loaded fast, animated.

    mojo run -I . examples/game_humanoid.mojo [path.png] [baked.glb] [triangles]

The page is Game humanoid. The first run builds a six-foot man's skin
on a skeleton, with a budget of triangles, and bakes it to a glTF file
with its five clips: idle, walk, run, jump and wave. Every run loads
that file, as a game would, and plays the clips in turn, each fading
into the next. It prints how long the build, the bake and the load
took, and how many frames a second it rendered.

The optional second argument is the baked file; the default is
`out/humanoid.glb`. Delete it to bake again. The optional third is the
budget of triangles for the skin; the default is 10000.
"""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import (
    ONCE,
    AnimationAction,
    AnimationMixer,
)
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from exporters.gltf import GLB, write_gltf
from extensions.humanoid.rig.clips import (
    idle_clip,
    jump_clip,
    run_clip,
    walk_clip,
    wave_clip,
)
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from lights.light import ambient_light, directional_light
from loaders.gltf import read_gltf
from math.vector3 import Vector3
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from std.time import perf_counter_ns
from units.si import DEGREE, FOOT, METER, SECOND, Angle, Duration, Length

comptime DEFAULT_OUTPUT = "out/game_humanoid.png"
comptime DEFAULT_BAKED = "out/humanoid.glb"
comptime DEFAULT_TRIANGLES = 10000
comptime WIDTH = 640
comptime HEIGHT = 360
comptime FPS = 24
# The order the clips play in, how long each plays, and how long each
# fades into the next, in seconds.
comptime ORDER: List[String] = ["idle", "walk", "run", "jump", "wave", "idle"]
comptime HOLD: List[Float32] = [2.0, 2.2, 2.1, 1.4, 2.0, 1.0]
comptime FADE = Float32(0.3)


def _seconds_since(start: Int) -> Float64:
    """Return the seconds since `start`, a `perf_counter_ns` reading."""
    return Float64(perf_counter_ns() - start) / 1e9


def _bake(path: String, triangles: Int) raises:
    """Build the humanoid and its clips, and write them to `path`."""
    var start = perf_counter_ns()
    var assets = Assets()
    var scene = Scene()
    var root = scene.add(Object3D())
    var person = add_game_humanoid(
        scene,
        assets,
        root,
        HumanoidSpec(Length(6.0, FOOT), MALE),
        triangles,
        workers=available_workers(),
    )
    var clips = List[AnimationClip]()
    clips.append(idle_clip(person.bones, person.rig))
    clips.append(walk_clip(person.bones, person.rig))
    clips.append(run_clip(person.bones, person.rig))
    clips.append(jump_clip(person.bones, person.rig))
    clips.append(wave_clip(person.bones, person.rig))
    print("Built in", _seconds_since(start), "s")
    var written = perf_counter_ns()
    write_gltf(path, scene, assets, GLB, animations=clips^)
    print("Baked", path, "in", _seconds_since(written), "s")


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])
    var baked = String(DEFAULT_BAKED)
    if len(args) > 2:
        baked = String(args[2])
    var triangles = DEFAULT_TRIANGLES
    if len(args) > 3:
        triangles = Int(String(args[3]))
    if not Path(baked).exists():
        _bake(baked, triangles)

    # What a game does: load the baked humanoid and its clips.
    var start = perf_counter_ns()
    var assets = Assets()
    var scene = Scene()
    var model = read_gltf(baked, scene, assets)
    print("Loaded in", _seconds_since(start), "s")
    var mixer = AnimationMixer()
    var actions = List[Int]()
    for name in materialize[ORDER]():
        var found = -1
        for k in range(len(model.animations)):
            if model.animations[k].name == name:
                found = k
        if found < 0:
            raise Error("The baked file has no clip named " + name)
        actions.append(
            mixer.add(AnimationAction(model.animations[found].copy()))
        )
    mixer.action(actions[3]).set_loop(ONCE)
    mixer.action(actions[3]).clamp_when_finished = True
    mixer.action(actions[0]).play()

    var sun = Object3D()
    sun.set_position(1.0, 1.6, 2.2)
    var sun_node = scene.add(sun^)
    scene.add_light(directional_light(Color(255, 242, 226), sun_node, 2.4))
    scene.add_light(ambient_light(Color(200, 210, 255), 0.45))
    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(24, 25, 28))
    var camera = PerspectiveCamera(
        Angle(35.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.05, METER),
        Length(30.0, METER),
    )
    camera.place(Vector3(-2.1, 0.1, 2.7), Vector3(0.0, -0.05, 0.0))

    var holds = materialize[HOLD]()
    var frames = List[Framebuffer]()
    var playing = 0
    var until = holds[0]
    var t = Float32(0)
    var rendering = Float64(0)
    var total = Float32(0)
    for h in holds:
        total += h
    var count = Int(total * FPS)
    var step = Duration(Float32(1) / Float32(FPS), SECOND)
    for frame in range(count):
        if t >= until and playing + 1 < len(actions):
            # The next clip starts from its beginning as the last fades.
            var next = actions[playing + 1]
            mixer.action(next).reset()
            mixer.action(next).play()
            mixer.cross_fade_from(
                next, actions[playing], Duration(FADE, SECOND)
            )
            playing += 1
            until += holds[playing]
        var drawn = perf_counter_ns()
        mixer.update(scene, step)
        scene.update()
        frames.append(renderer.render(scene, assets, camera))
        if frame > 0:
            rendering += _seconds_since(drawn)
        t += Float32(1) / Float32(FPS)
    print(
        "Rendered",
        count,
        "frames at",
        Float64(count - 1) / rendering,
        "frames a second",
    )
    Path(destination).write_bytes(encode(frames, delay_ms=1000 // FPS))
    print("Wrote", destination)
