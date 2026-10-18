# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read an example's output path, turn a node, and write its PNG.

Each example builds its own scene. This file reads the path from the
first argument, turns a node, and stores the frames. A full circle is
one turn divided across the frames. An example that built its own frames
can write them here. It can also copy one tile into a sheet, light a
scene and spin it, or hang a part on a turning node.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.clock import Clock
from core.object3d import NodeId, Object3D
from core.scene import Scene
from math.vector3 import Vector3
from examples.preview import add_sky_and_sun
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer, available_workers
from std.pathlib import Path
from std.sys import argv, stderr
from units.si import MILLISECOND, Angle, DEGREE


def hang_centered(
    mut scene: Scene, x: Float32, height: Float32, center: Vector3
) raises -> Tuple[NodeId, NodeId]:
    """Return a turning node at `x` and a child that cancels `center`.

    The child sits so that `center`, in the part's frame, lands on the
    turning node's axis.

    Args:
        scene: The scene that receives the nodes.
        x: Position along the row, in meters.
        height: Height of the part's middle above the floor.
        center: The part's middle in its own frame, in meters.

    Returns:
        The turning node, then the child to attach the part to.

    Raises:
        Error: If the scene refuses a node.
    """
    var pivot = Object3D()
    pivot.set_position(x, height, 0)
    var pivot_id = scene.add(pivot^)
    var holder = Object3D()
    holder.set_position(-center.x, -center.y, -center.z)
    return (pivot_id, scene.attach(holder^, pivot_id))


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
    write_frames(frames, destination, delay_ms, frame_count)


def spin_daylight(
    width: Int,
    height: Int,
    background: Color,
    fill: Float32,
    sun: Float32,
    mut scene: Scene,
    assets: Assets,
    node: NodeId,
    camera: PerspectiveCamera,
    frame_count: Int,
    delay_ms: Int,
    destination: String,
) raises:
    """Light `scene`, turn `node` through one circle, and write the frames.

    Args:
        width: The image width in pixels.
        height: The image height in pixels.
        background: The color behind the scene.
        fill: The sky fill strength.
        sun: The sun strength.
        scene: The persistent scene, edited in place.
        assets: The geometry, materials and textures.
        node: The node to turn about y.
        camera: The camera to view through.
        frame_count: How many frames cover the circle.
        delay_ms: How long each frame is shown, in milliseconds.
        destination: The path of the animated PNG.

    Raises:
        Error: If the scene, the render, or the write is invalid.
    """
    var renderer = Renderer(width, height, workers=available_workers())
    renderer.set_background(background)
    add_sky_and_sun(scene, fill, sun)
    spin_gallery(
        renderer,
        camera,
        assets,
        scene,
        node,
        frame_count,
        delay_ms,
        destination,
    )


def build_and_spin[
    build: def(mut Scene, mut Assets) raises thin -> NodeId,
    camera: def() raises thin -> PerspectiveCamera,
](
    width: Int,
    height: Int,
    background: Color,
    fill: Float32,
    sun: Float32,
    frame_count: Int,
    delay_ms: Int,
    destination: String,
) raises:
    """Build a scene, light it, turn its root, and write the frames.

    Parameters:
        build: Adds the model and returns the node to turn.
        camera: Returns the placed camera.

    Args:
        width: The image width in pixels.
        height: The image height in pixels.
        background: The color behind the scene.
        fill: The sky fill strength.
        sun: The sun strength.
        frame_count: How many frames cover the circle.
        delay_ms: How long each frame is shown, in milliseconds.
        destination: The path of the animated PNG.

    Raises:
        Error: If the build, the scene, the render, or the write is invalid.
    """
    var assets = Assets()
    var scene = Scene()
    var root = build(scene, assets)
    spin_daylight(
        width,
        height,
        background,
        fill,
        sun,
        scene,
        assets,
        root,
        camera(),
        frame_count,
        delay_ms,
        destination,
    )


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
    write_frames(frames, destination, delay_ms, frame_count)


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
    write_frames(frames, destination, delay_ms, frame_count)


def write_frames(
    frames: List[Framebuffer],
    destination: String,
    delay_ms: Int,
    frame_count: Int,
) raises:
    """Write `frames` as an animated PNG.

    Args:
        frames: The rendered frames, in order.
        destination: The path of the animated PNG.
        delay_ms: How long each frame is shown, in milliseconds.
        frame_count: How many frames the message reports.

    Raises:
        Error: If the frames cannot be encoded or the path cannot be
            written.
    """
    Path(destination).write_bytes(encode(frames, delay_ms=delay_ms))
    print("Wrote", destination, "-", frame_count, "frames")


def blit(mut sheet: Framebuffer, piece: Framebuffer, x0: Int, y0: Int):
    """Copy a tile into the sheet.

    Args:
        sheet: The whole picture.
        piece: One tile.
        x0: The tile's left column in the sheet.
        y0: The tile's top row in the sheet.
    """
    var channels = len(piece.pixels) // (piece.width * piece.height)
    for y in range(piece.height):
        for x in range(piece.width):
            var src = (y * piece.width + x) * channels
            var dst = ((y0 + y) * sheet.width + x0 + x) * channels
            for c in range(channels):
                sheet.pixels[dst + c] = piece.pixels[src + c]


def main():
    # The other examples import this file. This entry lets the build check it.
    return
