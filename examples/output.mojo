# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read an example's output path, turn one node, and write its PNG.

Each example builds its own scene. This file reads the path from the
first argument, turns one node for a frame, and stores the frames.
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
from units.si import MILLISECOND, Angle


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
