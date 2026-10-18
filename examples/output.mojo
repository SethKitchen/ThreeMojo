# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read an example's output path, turn one node, and write its PNG.

Each example builds its own scene. This file reads the path from the
first argument, turns one node, and stores the frames. A full circle is
one turn divided across the frames.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.clock import Clock
from core.object3d import NodeId
from core.scene import Scene
from render.apng import encode
from render.framebuffer import Framebuffer
from renderers.renderer import Renderer
from std.pathlib import Path
from std.sys import argv, stderr
from units.si import MILLISECOND, Angle, DEGREE


def example_destination(default_name: String) -> String:
    """Return the first program argument, or `default_name`.

    Args:
        default_name: The path used when the program has no argument.

    Returns:
        The output path.
    """
    var args = argv()
    if len(args) > 1:
        return String(args[1])
    return default_name


def spin_frame(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn `node` about y by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        node: The node to turn.
        step: How much further to turn this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(node).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def spin_pair(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    left: NodeId,
    right: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn two nodes about y by `step` and render one frame.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        left: The first node to turn.
        right: The second node to turn.
        step: How much further to turn this frame.

    Returns:
        The rendered frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    scene.node(left).rotate_y(step)
    scene.node(right).rotate_y(step)
    scene.update()
    return renderer.render(scene, assets, camera)


def _collect_spins(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    frame_count: Int,
) raises -> List[Framebuffer]:
    """Return one full circle of `node`, one frame per step."""
    var step = Angle(Float32(360) / Float32(frame_count), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(frame_count):
        frames.append(spin_frame(renderer, camera, assets, scene, node, step))
    return frames^


def spin_gallery(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    frame_count: Int,
    delay_ms: Int,
    destination: String,
) raises:
    """Turn `node` through one circle and write the frames.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        node: The node to turn about y.
        frame_count: How many frames cover the circle.
        delay_ms: How long each frame is shown, in milliseconds.
        destination: The path of the animated PNG.

    Raises:
        Error: If the scene, the render, or the write is invalid.
    """
    var frames = _collect_spins(
        renderer, camera, assets, scene, node, frame_count
    )
    Path(destination).write_bytes(encode(frames, delay_ms=delay_ms))
    print("Wrote", destination, "-", frame_count, "frames")


def spin_pair_gallery(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    left: NodeId,
    right: NodeId,
    frame_count: Int,
    delay_ms: Int,
    destination: String,
) raises:
    """Turn two nodes through one circle and write the frames.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        left: The first node to turn.
        right: The second node to turn.
        frame_count: How many frames cover the circle.
        delay_ms: How long each frame is shown, in milliseconds.
        destination: The path of the animated PNG.

    Raises:
        Error: If the scene, the render, or the write is invalid.
    """
    var step = Angle(Float32(360) / Float32(frame_count), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(frame_count):
        frames.append(
            spin_pair(renderer, camera, assets, scene, left, right, step)
        )
    Path(destination).write_bytes(encode(frames, delay_ms=delay_ms))
    print("Wrote", destination, "-", frame_count, "frames")


def spin_clip(
    renderer: Renderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    node: NodeId,
    frame_count: Int,
    delay_ms: Int,
    destination: String,
) raises:
    """Turn `node` through one circle and write the frames.

    Args:
        renderer: The renderer to draw with.
        camera: The camera to view through.
        assets: The geometry, materials and textures.
        scene: The persistent scene, edited in place.
        node: The node to turn about y.
        frame_count: How many frames cover the circle.
        delay_ms: How long each frame is shown, in milliseconds.
        destination: The path of the animated PNG.

    Raises:
        Error: If the scene, the render, or the write is invalid.
    """
    var frame_clock = Clock()
    frame_clock.start()
    var frames = _collect_spins(
        renderer, camera, assets, scene, node, frame_count
    )
    write_example(frames, destination, delay_ms, frame_count, frame_clock)


def write_example(
    frames: List[Framebuffer],
    destination: String,
    delay_ms: Int,
    frame_count: Int,
    mut clock: Clock,
) raises:
    """Write `frames` and print how long the render took.

    Args:
        frames: The rendered frames, in order.
        destination: The path of the animated PNG.
        delay_ms: How long each frame is shown, in milliseconds.
        frame_count: How many frames the example says it wrote.
        clock: The clock started before the first frame.

    Raises:
        Error: If the frames cannot be encoded or the path cannot be
            written.
    """
    print(
        '{"frames_ms": ',
        clock.elapsed().to(MILLISECOND),
        "}",
        sep="",
        file=stderr,
    )
    Path(destination).write_bytes(encode(frames, delay_ms=delay_ms))
    print("Wrote", destination, "-", frame_count, "frames")
