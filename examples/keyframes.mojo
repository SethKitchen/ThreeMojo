# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cube posed by an AnimationMixer, not by rotate_y in the loop.

    mojo run -I . examples/keyframes.mojo [path.png]

A clip holds a position track and a rotation track. The mixer writes the
pose each frame from the clock's delta.
"""

from animation.animation_clip import AnimationClip
from animation.animation_mixer import AnimationAction, AnimationMixer
from animation.keyframe_track import KeyframeTrack, POSITION, QUATERNION
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from lights.light import ambient_light, directional_light
from materials.material import Material
from math.quaternion import Quaternion
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Duration, Length, METER, SECOND

comptime DEFAULT_OUTPUT = "out/keyframes.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55
comptime CLIP_SECONDS = Float32(3)


def seconds(values: List[Float32]) -> List[Duration]:
    """Return the given numbers as durations in seconds."""
    var out = List[Duration]()
    for index in range(len(values)):
        out.append(Duration(values[index], SECOND))
    return out^


def frame_at(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    mut mixer: AnimationMixer,
    delta: Duration,
) raises -> Framebuffer:
    """Advance the mixer by `delta` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry and materials.
        scene: The persistent scene the mixer writes into.
        mixer: The mixer playing the clip.
        delta: How far the clip moves this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the mixer, the scene or the render is invalid.
    """
    mixer.update(scene, delta)
    scene.update()
    return renderer.render(scene, assets, camera)


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var renderer = Renderer(WIDTH, HEIGHT, workers=available_workers())
    renderer.set_background(Color(16, 18, 26))

    var assets = Assets()
    var block = assets.geometries.add(cube(Length(0.7, METER)))
    var paint = assets.materials.add(Material(Color(90, 190, 255)))

    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_mesh(Mesh(block, paint, node))

    var lamp = Object3D()
    lamp.set_position(0.5, 0.9, 0.6)
    var lamp_node = scene.add(lamp^)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.69))
    scene.add_light(directional_light(Color(255, 255, 255), lamp_node, 2.51))

    var q0 = Quaternion.identity()
    var q1 = Quaternion.from_axis_angle(Vector3(0, 1, 0), Angle(120.0, DEGREE))
    var q2 = Quaternion.from_axis_angle(Vector3(0, 1, 0), Angle(240.0, DEGREE))
    var slide = KeyframeTrack(
        node,
        POSITION,
        seconds([0, 1.5, 3]),
        [-0.9, 0, 0, 0.9, 0, 0, -0.9, 0, 0],
    )
    var spin = KeyframeTrack(
        node,
        QUATERNION,
        seconds([0, 1, 2, 3]),
        [
            q0.x,
            q0.y,
            q0.z,
            q0.w,
            q1.x,
            q1.y,
            q1.z,
            q1.w,
            q2.x,
            q2.y,
            q2.z,
            q2.w,
            q0.x,
            q0.y,
            q0.z,
            q0.w,
        ],
    )
    var clip = AnimationClip("slide", [slide^, spin^])
    var mixer = AnimationMixer()
    var which = mixer.add(AnimationAction(clip^))
    mixer.action(which).play()

    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.7, 3.2), Vector3(0, 0, 0))

    var delta = Duration(CLIP_SECONDS / Float32(FRAMES), SECOND)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(renderer, camera, assets, scene, mixer, delta))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
