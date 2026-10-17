# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Render at the size DLSS asks for, and upscale it on the CPU.

    mojo run -I . examples/streamline.mojo [path.png]

The page is Streamline. Three images sit side by side. On the left is a
Balanced-mode render, 58 percent of each side, stretched to the output with
the nearest texel. In the middle is the same render through
`SpatialUpscaler`, the fallback that runs where DLSS cannot. On the right is
the scene rendered at the full output size, the image that any upscaler aims
for. The row below magnifies the boxed part of each image five times.

This is the CPU fallback and not DLSS. It is not in the gallery.

    mojo run -I . examples/streamline.mojo --frames DIR

writes what a Streamline harness needs to run DLSS on the same scene: the
jittered renders, their depth, the jitter that `frame_constants` hands to
Streamline, and the full-size render and the fallback's result to compare
with. `docs/validation/streamline/evaluate_frames.cpp` reads them.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, UV
from core.object3d import Object3D
from core.scene import Scene
from extensions.streamline.constants import CameraSnapshot, frame_constants
from extensions.streamline.jitter import jitter_offset, jitter_phase_count
from extensions.streamline.kinds import (
    MODE_BALANCED,
    MOTION_PIXELS,
    SUPER_RESOLUTION,
)
from extensions.streamline.sizing import FrameSize, estimated_render_size
from extensions.streamline.upscaler import SpatialUpscaler, Upscaler
from extensions.visual.overlay import CENTER, LEFT, Overlay, fill_rect
from geometries.plane import plane
from geometries.torus import torus_knot
from lights.light import ambient_light, directional_light
from materials.material import DOUBLE_SIDE, Material
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.antialiasing import JitteredCamera
from render.apng import encode
from render.framebuffer import Color, FloatColor, Framebuffer
from render.texture import BILINEAR, REPEAT, checkerboard
from renderers.renderer import Renderer, available_workers
from std.math import isfinite
from std.pathlib import Path
from std.sys import argv
from units.si import Angle, DEGREE, Length, METER

comptime DEFAULT_OUTPUT = "out/streamline.png"
comptime FONT = "assets/ttf/kenpixel.ttf"
comptime OUTPUT_WIDTH = 480
comptime OUTPUT_HEIGHT = 270
comptime GAP = 8
comptime HEADER = 40
comptime ZOOM = 5
# The boxed part of each image: its top left, in output pixels. It is
# OUTPUT_WIDTH / ZOOM wide and OUTPUT_HEIGHT / ZOOM high.
comptime CROP_X = 196
comptime CROP_Y = 92
comptime BACKGROUND = Color(14, 16, 24)
comptime LABEL = Color(235, 238, 245)
comptime BOX = Color(255, 214, 64)


def floor_geometry() raises -> BufferGeometry:
    """Return a floor whose texture coordinates count tiles of 0.4 meter."""
    var sheet = plane(Length(40.0, METER), Length(60.0, METER))
    var tiled = List[Float32]()
    ref uvs = sheet.attribute_view(String(UV))
    for vertex in range(uvs.count()):
        tiled.append(uvs.component(vertex, 0) * 40.0 / 0.4)
        tiled.append(uvs.component(vertex, 1) * 60.0 / 0.4)
    sheet.set_attribute(String(UV), BufferAttribute(tiled^, 2))
    return sheet^


def make_camera() raises -> PerspectiveCamera:
    """Return the camera of the scene. Its framing does not depend on the
    size of the render."""
    var camera = PerspectiveCamera(
        Angle(40.0, DEGREE),
        Float32(OUTPUT_WIDTH) / Float32(OUTPUT_HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0.95, 2.75), Vector3(0, 0.5, 0))
    return camera^


def render(
    width: Int, height: Int, jitter: Vector2 = Vector2(0, 0)
) raises -> Framebuffer:
    """Render the scene at a size. The framing does not depend on the size.

    Args:
        width: The width in pixels.
        height: The height in pixels.
        jitter: How far the view moves, in pixels, across and down.

    Returns:
        The frame.

    Raises:
        Error: If the scene or the render is invalid.
    """
    var renderer = Renderer(width, height, workers=available_workers())
    renderer.set_background(Color(20, 24, 38))

    var assets = Assets()
    var knot = assets.geometries.add(
        torus_knot(Length(0.62, METER), Length(0.075, METER), 220, 10, 3, 5)
    )
    var floor = assets.geometries.add(floor_geometry())
    var board = assets.textures.add(
        checkerboard(
            64,
            8,
            Color(238, 238, 244),
            Color(40, 74, 150),
            REPEAT,
            BILINEAR,
            mipmapped=True,
        )
    )
    var metal = assets.materials.add(Material(Color(255, 170, 70)))
    var tiled = assets.materials.add(
        Material(Color(255, 255, 255), board, DOUBLE_SIDE)
    )

    var scene = Scene()
    var knot_object = Object3D()
    knot_object.set_position(0, 0.55, 0)
    knot_object.set_euler(
        Angle(18.0, DEGREE), Angle(24.0, DEGREE), Angle(0.0, DEGREE)
    )
    scene.add_mesh(Mesh(knot, metal, scene.add(knot_object^)))
    var ground = Object3D()
    ground.set_position(0, -0.35, -22)
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    scene.add_mesh(Mesh(floor, tiled, scene.add(ground^)))

    var sun = Object3D()
    sun.set_position(1.2, 2.4, 2.0)
    scene.add_light(ambient_light(Color(255, 255, 255), 0.42))
    scene.add_light(
        directional_light(Color(255, 244, 228), scene.add(sun^), 2.2)
    )
    scene.update()

    var camera = JitteredCamera(
        make_camera(), scene, jitter.x, jitter.y, width, height
    )
    return renderer.render(scene, assets, camera)


def to_colors(frame: Framebuffer) raises -> List[FloatColor]:
    """Return a frame as linear colors, row by row from the top."""
    var colors = List[FloatColor](capacity=frame.width * frame.height)
    for y in range(frame.height):
        for x in range(frame.width):
            colors.append(FloatColor(srgb=frame.get_pixel(x, y)))
    return colors^


def stretch(frame: Framebuffer, size: FrameSize) raises -> Framebuffer:
    """Return a frame stretched to a size with the nearest texel."""
    var result = Framebuffer(size.width, size.height, BACKGROUND)
    for y in range(size.height):
        for x in range(size.width):
            var u = min(x * frame.width // size.width, frame.width - 1)
            var v = min(y * frame.height // size.height, frame.height - 1)
            result.set_pixel(x, y, frame.get_pixel(u, v))
    return result^


def from_colors(
    colors: List[FloatColor], size: FrameSize
) raises -> Framebuffer:
    """Return linear colors as a frame."""
    var result = Framebuffer(size.width, size.height, BACKGROUND)
    for y in range(size.height):
        for x in range(size.width):
            result.set_pixel(x, y, colors[y * size.width + x].encode())
    return result^


def paste(
    mut sheet: Framebuffer, frame: Framebuffer, left: Int, top: Int
) raises:
    """Copy a frame into the sheet."""
    for y in range(frame.height):
        for x in range(frame.width):
            sheet.set_pixel(left + x, top + y, frame.get_pixel(x, y))


def paste_zoomed(
    mut sheet: Framebuffer, frame: Framebuffer, left: Int, top: Int
) raises:
    """Copy the boxed part of a frame into the sheet, magnified."""
    for y in range(OUTPUT_HEIGHT):
        for x in range(OUTPUT_WIDTH):
            sheet.set_pixel(
                left + x,
                top + y,
                frame.get_pixel(CROP_X + x // ZOOM, CROP_Y + y // ZOOM),
            )


def draw_box(mut sheet: Framebuffer, left: Int, top: Int) raises:
    """Outline the boxed part of an image."""
    var x0 = Float64(left + CROP_X)
    var y0 = Float64(top + CROP_Y)
    var x1 = x0 + Float64(OUTPUT_WIDTH // ZOOM)
    var y1 = y0 + Float64(OUTPUT_HEIGHT // ZOOM)
    fill_rect(sheet, x0 - 1, y0 - 1, x1 + 1, y0, BOX)
    fill_rect(sheet, x0 - 1, y1, x1 + 1, y1 + 1, BOX)
    fill_rect(sheet, x0 - 1, y0, x0, y1, BOX)
    fill_rect(sheet, x1, y0, x1 + 1, y1, BOX)


def depth_bytes(frame: Framebuffer) -> List[UInt8]:
    """Return a frame's depth as 16-bit fractions, low byte first. A pixel
    that nothing drew is one."""
    var bytes = List[UInt8](capacity=2 * frame.width * frame.height)
    for at in range(frame.width * frame.height):
        var depth = frame.depth[at]
        var scaled = 65535
        if isfinite(depth):
            scaled = Int(max(Float32(0), min(Float32(1), depth)) * 65535)
        bytes.append(UInt8(scaled & 255))
        bytes.append(UInt8(scaled >> 8))
    return bytes^


def write_frames(directory: String) raises:
    """Write the frames a Streamline harness feeds to DLSS.

    Args:
        directory: An existing directory.

    Raises:
        Error: If a frame cannot be rendered or a file cannot be written.
    """
    var output = FrameSize(OUTPUT_WIDTH, OUTPUT_HEIGHT)
    var size = estimated_render_size(MODE_BALANCED, output)
    var count = jitter_phase_count(size, output)
    var snapshot = CameraSnapshot(make_camera(), Scene())
    var meta = String(size.width) + " " + String(size.height) + " "
    meta += String(output.width) + " " + String(output.height) + " "
    meta += String(count) + "\n"
    for index in range(count):
        var offset = jitter_offset(index, count)
        # What Streamline is told: `frame_constants` negates the offset.
        var constants = frame_constants(
            snapshot, snapshot, size, offset, MOTION_PIXELS, index == 0
        )
        meta += String(constants.jitter_offset.x) + " "
        meta += String(constants.jitter_offset.y) + "\n"
        var frame = render(size.width, size.height, offset)
        Path(directory + "/color_" + String(index) + ".rgba").write_bytes(
            frame.pixels
        )
        Path(directory + "/depth_" + String(index) + ".u16").write_bytes(
            depth_bytes(frame)
        )
    Path(directory + "/meta.txt").write_text(meta)

    var plain = render(size.width, size.height)
    var native = render(output.width, output.height)
    Path(directory + "/native.rgba").write_bytes(native.pixels)
    var upscaled = from_colors(
        SpatialUpscaler().evaluate(
            SUPER_RESOLUTION, to_colors(plain), size, output
        ),
        output,
    )
    Path(directory + "/fallback.rgba").write_bytes(upscaled.pixels)
    print(
        "Wrote",
        count,
        "frames of",
        size.width,
        "by",
        size.height,
        "to",
        directory,
    )


def main() raises:
    var args = argv()
    if len(args) > 2 and String(args[1]) == "--frames":
        write_frames(String(args[2]))
        return
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var output = FrameSize(OUTPUT_WIDTH, OUTPUT_HEIGHT)
    var size = estimated_render_size(MODE_BALANCED, output)
    var small = render(size.width, size.height)
    var native = render(output.width, output.height)

    var upscaler = SpatialUpscaler()
    var upscaled = from_colors(
        upscaler.evaluate(SUPER_RESOLUTION, to_colors(small), size, output),
        output,
    )
    var stretched = stretch(small, output)

    var step = OUTPUT_WIDTH + GAP
    var width = 3 * OUTPUT_WIDTH + 2 * GAP
    var height = HEADER + OUTPUT_HEIGHT + GAP + OUTPUT_HEIGHT
    var sheet = Framebuffer(width, height, BACKGROUND)
    var top = HEADER
    var bottom = HEADER + OUTPUT_HEIGHT + GAP
    paste(sheet, stretched, 0, top)
    paste(sheet, upscaled, step, top)
    paste(sheet, native, 2 * step, top)
    paste_zoomed(sheet, stretched, 0, bottom)
    paste_zoomed(sheet, upscaled, step, bottom)
    paste_zoomed(sheet, native, 2 * step, bottom)
    for column in range(3):
        draw_box(sheet, column * step, top)

    var font = Overlay.from_ttf(FONT)
    var names = List[String]()
    names.append("Stretched " + String(size.width) + "x" + String(size.height))
    names.append("Spatial upscaler")
    names.append("Native " + String(output.width) + "x" + String(output.height))
    for column in range(3):
        font.text(
            sheet,
            names[column],
            Float64(column * step + OUTPUT_WIDTH // 2),
            Float64(HEADER - 12),
            15.0,
            LABEL,
            CENTER,
        )
        font.text(
            sheet,
            String(ZOOM) + "x",
            Float64(column * step + 8),
            Float64(bottom + OUTPUT_HEIGHT - 10),
            14.0,
            BOX,
            LEFT,
        )

    var frames = List[Framebuffer]()
    frames.append(sheet^)
    Path(destination).write_bytes(encode(frames))
    print(
        "Wrote",
        destination,
        "- render",
        size.width,
        "by",
        size.height,
        "to",
        output.width,
        "by",
        output.height,
    )
