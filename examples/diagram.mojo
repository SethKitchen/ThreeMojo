# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An icosahedron and a box, drawn flat as SVG and shown as pixels.

    mojo run -I . examples/diagram.mojo [path.png]

The page is SVG renderer. `SVGRenderer` writes one path a face, lit flat.
This program fills those paths into a frame so the figure can be a PNG.
The pair turns one whole turn.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.polyhedron import icosahedron
from lights.light import ambient_light, directional_light
from loaders.svg import parse_path_data
from loaders.svg_path import SvgVector
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.apng import encode
from render.framebuffer import Color, Framebuffer
from renderers.svg_renderer import SVGRenderer, SvgImage
from std.math import abs, ceil, floor
from std.pathlib import Path
from std.sys import argv
from units.si import DEGREE, METER, Angle, Length

comptime DEFAULT_OUTPUT = "out/svg.png"
comptime WIDTH = 240
comptime HEIGHT = 180
comptime FRAMES = 36
comptime DELAY_MS = 55


def _byte(value: Int) -> UInt8:
    """Return `value` clamped into a color byte.

    Args:
        value: A channel, which may lie outside zero to 255.

    Returns:
        The byte.
    """
    if value < 0:
        return 0
    if value > 255:
        return 255
    return UInt8(value)


def _rgb(style: String) -> Color:
    """Return the first `rgb()` color in an SVG style.

    Args:
        style: A path style or a background style.

    Returns:
        The color, white when the style has no `rgb()`.
    """
    var bytes = style.as_bytes()
    if len(bytes) < 4:
        return Color(255, 255, 255)
    var start = -1
    for i in range(len(bytes) - 3):
        if (
            bytes[i] == 114
            and bytes[i + 1] == 103
            and bytes[i + 2] == 98
            and bytes[i + 3] == 40
        ):
            start = i + 4
            break
    if start < 0:
        return Color(255, 255, 255)
    var numbers = List[Int]()
    var current = 0
    var seen = False
    var negative = False
    for i in range(start, len(bytes)):
        var c = bytes[i]
        if c == 45:
            negative = True
            continue
        if c >= 48 and c <= 57:
            current = current * 10 + Int(c) - 48
            seen = True
            continue
        if seen:
            if negative:
                current = -current
            numbers.append(current)
            current = 0
            seen = False
            negative = False
        if c == 41:
            break
    if seen:
        if negative:
            current = -current
        numbers.append(current)
    var red = 255
    var green = 255
    var blue = 255
    if len(numbers) > 0:
        red = numbers[0]
    if len(numbers) > 1:
        green = numbers[1]
    if len(numbers) > 2:
        blue = numbers[2]
    return Color(_byte(red), _byte(green), _byte(blue))


def _cross(
    ax: Float64,
    ay: Float64,
    bx: Float64,
    by: Float64,
    px: Float64,
    py: Float64,
) -> Float64:
    """Return which side of the edge from `a` to `b` the point `p` is on.

    Args:
        ax: The edge start, x.
        ay: The edge start, y.
        bx: The edge end, x.
        by: The edge end, y.
        px: The point, x.
        py: The point, y.

    Returns:
        Positive on one side, negative on the other, zero on the edge.
    """
    return (bx - ax) * (py - ay) - (by - ay) * (px - ax)


def _fill_triangle(
    mut image: Framebuffer,
    ax: Float64,
    ay: Float64,
    bx: Float64,
    by: Float64,
    cx: Float64,
    cy: Float64,
    color: Color,
) raises:
    """Fill one triangle in pixel space.

    Args:
        image: The frame to paint.
        ax: The first corner, x.
        ay: The first corner, y.
        bx: The second corner, x.
        by: The second corner, y.
        cx: The third corner, x.
        cy: The third corner, y.
        color: The fill.

    Raises:
        Error: If a pixel write falls outside the frame.
    """
    var left = ax
    var right = ax
    var top = ay
    var bottom = ay
    if bx < left:
        left = bx
    if cx < left:
        left = cx
    if bx > right:
        right = bx
    if cx > right:
        right = cx
    if by < top:
        top = by
    if cy < top:
        top = cy
    if by > bottom:
        bottom = by
    if cy > bottom:
        bottom = cy
    var x0 = Int(floor(left))
    var x1 = Int(ceil(right))
    var y0 = Int(floor(top))
    var y1 = Int(ceil(bottom))
    if x0 < 0:
        x0 = 0
    if y0 < 0:
        y0 = 0
    if x1 >= image.width:
        x1 = image.width - 1
    if y1 >= image.height:
        y1 = image.height - 1
    if x0 > x1 or y0 > y1:
        return
    for y in range(y0, y1 + 1):
        var py = Float64(y) + 0.5
        for x in range(x0, x1 + 1):
            var px = Float64(x) + 0.5
            var w0 = _cross(bx, by, cx, cy, px, py)
            var w1 = _cross(cx, cy, ax, ay, px, py)
            var w2 = _cross(ax, ay, bx, by, px, py)
            var positive = w0 >= 0 and w1 >= 0 and w2 >= 0
            var negative = w0 <= 0 and w1 <= 0 and w2 <= 0
            if positive or negative:
                image.set_pixel(x, y, color)


def _fill_polygon(
    mut image: Framebuffer, points: List[SvgVector], color: Color
) raises:
    """Fill a polygon as a fan of triangles.

    Args:
        image: The frame to paint.
        points: The corners, in pixels. A repeated closing point is dropped.
        color: The fill.

    Raises:
        Error: If a pixel write falls outside the frame.
    """
    var count = len(points)
    if count > 1:
        var last = points[count - 1]
        var first = points[0]
        var closed = (
            abs(last[0] - first[0]) < 1e-4 and abs(last[1] - first[1]) < 1e-4
        )
        if closed:
            count -= 1
    if count < 3:
        return
    var origin = points[0]
    for index in range(1, count - 1):
        var b = points[index]
        var c = points[index + 1]
        _fill_triangle(
            image, origin[0], origin[1], b[0], b[1], c[0], c[1], color
        )


def _rasterize(drawn: SvgImage) raises -> Framebuffer:
    """Fill an SVG document's paths into a frame.

    Args:
        drawn: The document `SVGRenderer.render` returned.

    Returns:
        The frame. Its background is the document's background.

    Raises:
        Error: If a path cannot be read, or a pixel write falls outside.
    """
    var image = Framebuffer(drawn.width, drawn.height, _rgb(drawn.background))
    var half_x = Float64(drawn.width) * 0.5
    var half_y = Float64(drawn.height) * 0.5
    for path in drawn.paths:
        if path.style.find("fill:none") >= 0:
            continue
        var shape = parse_path_data(path.d)
        var color = _rgb(path.style)
        for sub in shape.sub_paths:
            var points = sub.get_points(1)
            var placed = List[SvgVector]()
            for point in points:
                placed.append(SvgVector(point[0] + half_x, point[1] + half_y))
            _fill_polygon(image, placed, color)
    return image^


def frame_at(
    mut svg: SVGRenderer,
    camera: PerspectiveCamera,
    assets: Assets,
    mut scene: Scene,
    pivot: NodeId,
    step: Angle,
) raises -> Framebuffer:
    """Turn the pair, draw it as SVG, and fill that drawing.

    Args:
        svg: The SVG renderer.
        camera: The camera, placed in front of the pair.
        assets: The geometries and materials.
        scene: The persistent scene, edited in place.
        pivot: The node the pair rides.
        step: How much further the pair turns.

    Returns:
        The filled frame.

    Raises:
        Error: If the draw or a path cannot be read.
    """
    scene.node(pivot).rotate_y(step)
    return _rasterize(svg.render(scene, assets, camera))


def main() raises:
    var args = argv()
    var destination = String(DEFAULT_OUTPUT)
    if len(args) > 1:
        destination = String(args[1])

    var svg = SVGRenderer(WIDTH, HEIGHT)
    svg.set_clear_color(Color(16, 18, 26))
    svg.set_precision(2)

    var assets = Assets()
    var gem = assets.geometries.add(icosahedron(Length(0.72, METER)))
    var block = assets.geometries.add(cube(Length(0.7, METER)))
    var orange = assets.materials.add(Material(Color(214, 122, 66)))
    var blue = assets.materials.add(Material(Color(64, 122, 196)))

    var scene = Scene()
    var pivot = scene.add(Object3D())
    var left = Object3D()
    left.set_position(-0.38, 0.05, 0)
    scene.add_mesh(Mesh(gem, orange, scene.attach(left^, pivot)))
    var right = Object3D()
    right.set_position(0.72, -0.18, 0.12)
    scene.add_mesh(Mesh(block, blue, scene.attach(right^, pivot)))

    var lamp = Object3D()
    lamp.set_position(1.5, 2.1, 1.7)
    scene.add_light(ambient_light(Color(78, 84, 98), 1))
    scene.add_light(
        directional_light(Color(255, 246, 232), scene.add(lamp^), 1.7)
    )

    var camera = PerspectiveCamera(
        Angle(38.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    camera.place(Vector3(0.2, 0.7, 2.7), Vector3(0.1, 0, 0))

    var step = Angle(Float32(360) / Float32(FRAMES), DEGREE)
    var frames = List[Framebuffer]()
    for _ in range(FRAMES):
        frames.append(frame_at(svg, camera, assets, scene, pivot, step))

    Path(destination).write_bytes(encode(frames, delay_ms=DELAY_MS))
    print("Wrote", destination, "-", FRAMES, "frames")
