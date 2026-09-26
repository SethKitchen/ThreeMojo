# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A scene drawn as SVG paths, from three.js
`examples/jsm/renderers/SVGRenderer.js`.

`SVGRenderer.render` projects the scene with `renderers.projector` and
writes one path for each run of elements that share a style, as three.js
does. The result is an `SvgImage`: the document's size, its background and
its paths. `SvgImage.text` writes the SVG file.

- **Faces.** A basic material is its color, times the face's first vertex
  color with vertex colors. A Lambert, Phong, standard or physical
  material is lit by three.js's flat rule: the ambient lights, and each
  directional and point light by the face normal at the face's center. A
  normal material shows the normal in the camera's space. A wireframe is
  stroked, and anything else is filled. With `overdraw` above zero, each
  edge is pushed out by that many pixels to hide the seams.
- **Lines.** A basic material is stroked one pixel wide with round caps,
  and dashed when it has a gap.
- **Sprites and points.** A square of the sprite's size on screen, or of
  the point's size times the material's size, filled with the color.

**The numbers.** A coordinate is written as JavaScript writes a number,
or with `set_precision` digits after the point, as `toFixed` writes it.
A color is converted to linear and back to sRGB as three.js converts it,
and written as `rgb(r,g,b)`.

**Where three.js's quirks are kept.** The ambient lights are summed
without their intensity. A directional light shines from its node's
position toward the origin, whatever its target. A point light's falloff
is measured from the face to the unit direction toward the light, not to
the light, as three.js reuses one vector for both. A face of another
material, such as a toon or a depth material, takes the color of the last
face drawn before it, white at first. A path that is not cleared is kept:
with `auto_clear` off and no background color, each render adds its paths
to the last. A path is crisp only if it was first made at low quality.

**Where this port differs.** Mojo has no DOM, so `SVGObject` is not
ported, and `SvgImage` holds what three.js writes into its element. The
precision is checked when it is set, where three.js throws when it
writes a number.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.background import COLOR_BACKGROUND
from core.scene import Scene
from lights.light import AMBIENT, DIRECTIONAL, POINT, Light
from loaders.js_number import js_float32_text, js_number_text, js_to_fixed
from materials.material import (
    BASIC,
    LAMBERT,
    Material,
    NORMALS,
    PHONG,
    PHYSICAL,
    STANDARD,
)
from render.framebuffer import Color
from renderers.projector import (
    Matrix,
    RENDERABLE_FACE,
    RENDERABLE_LINE,
    RenderData,
    Renderable,
    Vec,
    apply_normal,
    project_scene,
)
from std.math import floor, pow, sqrt


struct SvgQuality(Equatable, ImplicitlyCopyable, Writable):
    """How a path is drawn, three.js's `setQuality( 'high' )` or
    `setQuality( 'low' )`, as a type rather than a bare int.

    The type does not stop `SvgQuality(9)`, so `set_quality` asks
    `is_valid`.
    """

    var value: Int

    def __init__(out self, value: Int):
        """Wrap a quality number.

        Args:
            value: The quality.
        """
        self.value = value

    def __eq__(self, other: Self) -> Bool:
        """Return True for the same quality.

        Args:
            other: The other quality.

        Returns:
            Whether they are equal.
        """
        return self.value == other.value

    def is_valid(self) -> Bool:
        """Return True if this is `LOW_QUALITY` or `HIGH_QUALITY`.

        Returns:
            Whether it is.
        """
        return self.value == 0 or self.value == 1

    def write_to(self, mut writer: Some[Writer]):
        """Write the quality's name.

        Args:
            writer: Where to write it.
        """
        if self.value == 0:
            writer.write("LOW_QUALITY")
        elif self.value == 1:
            writer.write("HIGH_QUALITY")
        else:
            writer.write("SvgQuality(", self.value, ")")


# Each new path is crisp, `shape-rendering="crispEdges"`: three.js's
# `setQuality( 'low' )`.
comptime LOW_QUALITY = SvgQuality(0)
# Each new path is smoothed by the viewer: three.js's default.
comptime HIGH_QUALITY = SvgQuality(1)


@fieldwise_init
struct SvgPath(Copyable, Movable):
    """One `path` element: its outline, its style, and whether it is
    crisp."""

    var d: String
    var style: String
    var crisp: Bool


struct SvgImage(Movable):
    """What `SVGRenderer.render` leaves in three.js's `domElement`."""

    var width: Int
    var height: Int
    # The `viewBox` attribute: the image centered on the origin.
    var view_box: String
    # The `background-color` style, as `rgb(r,g,b)`, or empty for none.
    var background: String
    var paths: List[SvgPath]

    def __init__(
        out self,
        width: Int,
        height: Int,
        view_box: String,
        background: String,
        var paths: List[SvgPath],
    ):
        """Hold a document.

        Args:
            width: Its width in pixels.
            height: Its height in pixels.
            view_box: Its `viewBox` attribute.
            background: Its background color, or empty.
            paths: Its paths, in order.
        """
        self.width = width
        self.height = height
        self.view_box = view_box
        self.background = background
        self.paths = paths^

    def text(self) -> String:
        """Return the document as an SVG file.

        Returns:
            The text.
        """
        var out = String('<svg xmlns="http://www.w3.org/2000/svg" viewBox="')
        out += self.view_box + '" width="' + String(self.width)
        out += '" height="' + String(self.height) + '"'
        if self.background.byte_length() > 0:
            out += ' style="background-color:' + self.background + '"'
        out += ">\n"
        for path in self.paths:
            out += '<path d="' + path.d + '" style="' + path.style + '"'
            if path.crisp:
                out += ' shape-rendering="crispEdges"'
            out += "/>\n"
        out += "</svg>\n"
        return out^


def srgb_to_linear(channel: UInt8) -> Float64:
    """Return an sRGB byte as a linear number, three.js's `SRGBToLinear`.

    Args:
        channel: The byte.

    Returns:
        The linear value, from zero to one.
    """
    var c = Float64(channel) / 255
    if c < 0.04045:
        return c * 0.0773993808
    return pow(c * 0.9478672986 + 0.0521327014, 2.4)


def color_style(color: Vec) raises -> String:
    """Return a linear color as three.js's `getStyle` writes it in sRGB:
    `rgb(r,g,b)`, each rounded and not clamped.

    Args:
        color: The color, linear, red, green and blue.

    Returns:
        The style.

    Raises:
        Error: If a number cannot be written.
    """
    var out = String("rgb(")
    for k in range(3):  # pragma: no branch
        var c = color[k]
        var s = c * 12.92 if c < 0.0031308 else 1.055 * pow(c, 0.41666) - 0.055
        if k > 0:
            out += ","
        out += js_number_text(floor(s * 255 + 0.5))
    return out + ")"


def _linear(color: Color) -> Vec:
    """Return a stored color as three.js holds it, linear."""
    return Vec(
        srgb_to_linear(color.r),
        srgb_to_linear(color.g),
        srgb_to_linear(color.b),
        0,
    )


def _expand(mut a: Vec, mut b: Vec, pixels: Float64):
    """Push two corners apart along their edge, three.js's `expand`."""
    var x = b[0] - a[0]
    var y = b[1] - a[1]
    var det = x * x + y * y
    if det == 0:
        return
    var idet = pixels / sqrt(det)
    x *= idet
    y *= idet
    b[0] += x
    b[1] += y
    a[0] -= x
    a[1] -= y


def _touches(
    xs: List[Float64], ys: List[Float64], wide: Float64, high: Float64
) -> Bool:
    """Return whether the box around some points touches the image,
    three.js's `Box2.intersectsBox`."""
    var low_x = xs[0]
    var high_x = xs[0]
    var low_y = ys[0]
    var high_y = ys[0]
    for k in range(1, len(xs)):  # pragma: no branch
        low_x = min(low_x, xs[k])
        high_x = max(high_x, xs[k])
        low_y = min(low_y, ys[k])
        high_y = max(high_y, ys[k])
    return not (
        high_x < -wide or low_x > wide or high_y < -high or low_y > high
    )


struct SVGRenderer(Movable):
    """Draws a scene as SVG paths, three.js's `SVGRenderer`."""

    var width: Int
    var height: Int
    # Clear the paths before each render, three.js's `autoClear`.
    var auto_clear: Bool
    # Sort the objects, and then the elements, far to near, as three.js's
    # `sortObjects` and `sortElements` do.
    var sort_objects: Bool
    var sort_elements: Bool
    # How many pixels each face's edges are pushed out, three.js's
    # `overdraw`. Zero leaves the faces as they are.
    var overdraw: Float64
    # How many digits after the point each coordinate is written with, or
    # -1 to write it as JavaScript does.
    var precision: Int
    var quality: SvgQuality
    var clear_color: Color
    # three.js's `info.render`: the faces drawn by the last render, and
    # three times as many vertices.
    var vertices: Int
    var faces: Int
    # The document: its background and its paths.
    var background: String
    var paths: List[SvgPath]
    # three.js's pool of path elements: whether each was made crisp.
    var _pool: List[Bool]
    var _path_count: Int
    # The color of the last face drawn, three.js's `_color`.
    var _color: Vec

    def __init__(out self, width: Int = 0, height: Int = 0):
        """Create a renderer at three.js's defaults: sorted, cleared to
        white, with an overdraw of half a pixel, at high quality.

        Args:
            width: The image's width in pixels.
            height: The image's height in pixels.
        """
        self.width = width
        self.height = height
        self.auto_clear = True
        self.sort_objects = True
        self.sort_elements = True
        self.overdraw = 0.5
        self.precision = -1
        self.quality = HIGH_QUALITY
        self.clear_color = Color(255, 255, 255)
        self.vertices = 0
        self.faces = 0
        self.background = String()
        self.paths = List[SvgPath]()
        self._pool = List[Bool]()
        self._path_count = 0
        self._color = Vec(1, 1, 1, 0)

    def set_size(mut self, width: Int, height: Int):
        """Size the image, three.js's `setSize`.

        Args:
            width: The width in pixels.
            height: The height in pixels.
        """
        self.width = width
        self.height = height

    def set_precision(mut self, precision: Int) raises:
        """Write each coordinate with this many digits after the point,
        three.js's `setPrecision`.

        Args:
            precision: The digits, from 0 to 100, or -1 for none.

        Raises:
            Error: If the digits are out of that range, where three.js's
                `toFixed` throws.
        """
        if precision < -1 or precision > 100:
            raise Error(
                "An SVG precision must be from 0 to 100 digits, or -1 for none"
            )
        self.precision = precision

    def set_quality(mut self, quality: SvgQuality) raises:
        """Set whether new paths are crisp, three.js's `setQuality`.

        Args:
            quality: `LOW_QUALITY` or `HIGH_QUALITY`.

        Raises:
            Error: If the quality is neither.
        """
        if not quality.is_valid():
            raise Error("An SVG quality must be LOW_QUALITY or HIGH_QUALITY")
        self.quality = quality

    def set_clear_color(mut self, color: Color):
        """Set the background a clear shows, three.js's `setClearColor`.

        Args:
            color: The color.
        """
        self.clear_color = color

    def clear(mut self) raises:
        """Take out every path and show the clear color, three.js's
        `clear`.

        Raises:
            Error: If the color cannot be written.
        """
        self._remove_paths()
        self.background = color_style(_linear(self.clear_color))

    def view_box(self) raises -> String:
        """Return the `viewBox` attribute, as three.js's `setSize` writes
        it.

        Returns:
            The attribute.

        Raises:
            Error: If a number cannot be written.
        """
        var half_x = Float64(self.width) / 2
        var half_y = Float64(self.height) / 2
        return (
            js_number_text(-half_x)
            + " "
            + js_number_text(-half_y)
            + " "
            + String(self.width)
            + " "
            + String(self.height)
        )

    def image(self) raises -> SvgImage:
        """Return the document as it stands.

        Returns:
            The size, the background and the paths.

        Raises:
            Error: If a number cannot be written.
        """
        return SvgImage(
            self.width,
            self.height,
            self.view_box(),
            self.background,
            self.paths.copy(),
        )

    def _remove_paths(mut self):
        """three.js's `removeChildNodes`."""
        self._path_count = 0
        self.paths.clear()

    def _write(self, value: Float64) raises -> String:
        """Write a coordinate, three.js's `convert`."""
        if self.precision >= 0:
            return js_to_fixed(value, self.precision)
        return js_number_text(value)

    def _flush(mut self, mut path: String, mut style: String):
        """Close the path being built, three.js's `flushPath`."""
        if path.byte_length() > 0:
            var id = self._path_count
            self._path_count += 1
            if id >= len(self._pool):
                self._pool.append(self.quality == LOW_QUALITY)
            self.paths.append(SvgPath(path, style, self._pool[id]))
        path = String()
        style = String()

    def _add(
        mut self,
        new_style: String,
        new_path: String,
        mut path: String,
        mut style: String,
    ):
        """Add to the path being built, or start another, three.js's
        `addPath`."""
        if style == new_style:
            path += new_path
        else:
            self._flush(path, style)
            style = new_style
            path = new_path

    def render[
        C: Camera
    ](mut self, mut scene: Scene, assets: Assets, camera: C) raises -> SvgImage:
        """Draw a scene, three.js's `render`.

        Args:
            scene: The scene. Its world matrices are brought up to date.
            assets: Its geometries and materials.
            camera: The camera.

        Returns:
            The document.

        Raises:
            Error: If the scene names a geometry, a material or a node its
                stores do not have, or the camera cannot be placed.
        """
        if scene.background.kind == COLOR_BACKGROUND:
            self._remove_paths()
            self.background = color_style(_linear(scene.background.color))
        elif self.auto_clear:
            self.clear()
        self.vertices = 0
        self.faces = 0
        scene.update()
        var view = camera.view_matrix_in(scene)
        var data = project_scene(
            scene,
            assets,
            camera.projection_matrix(),
            view,
            self.sort_objects,
            self.sort_elements,
        )
        var normal_view = Matrix(view).normal_matrix()
        var ambient = Vec(0)
        for i in data.lights:
            if scene.lights[i].kind == AMBIENT:
                ambient += _linear(scene.lights[i].color)
        var half_x = Float64(self.width) / 2
        var half_y = Float64(self.height) / 2
        var path = String()
        var style = String()
        for element in data.elements:
            ref material = assets.materials.get(element.material)
            if material.opacity == 0:
                continue
            if element.kind == RENDERABLE_FACE:
                self._face(
                    element,
                    material,
                    scene,
                    data,
                    ambient,
                    normal_view,
                    half_x,
                    half_y,
                    path,
                    style,
                )
            elif element.kind == RENDERABLE_LINE:
                self._line(element, material, half_x, half_y, path, style)
            else:
                self._sprite(element, material, half_x, half_y, path, style)
        self._flush(path, style)
        return self.image()

    def _sprite(
        mut self,
        element: Renderable,
        material: Material,
        half_x: Float64,
        half_y: Float64,
        mut path: String,
        mut style: String,
    ) raises:
        """Draw a sprite or a point, three.js's `renderSprite`."""
        var x = element.x * half_x
        var y = element.y * -half_y
        var scale_x = element.scale_x * half_x
        var scale_y = element.scale_y * half_y
        if element.is_point:
            scale_x *= Float64(material.point_size.pixels)
            scale_y *= Float64(material.point_size.pixels)
        var outline = (
            "M"
            + self._write(x - scale_x * 0.5)
            + ","
            + self._write(y - scale_y * 0.5)
            + "h"
            + self._write(scale_x)
            + "v"
            + self._write(scale_y)
            + "h"
            + self._write(-scale_x)
            + "z"
        )
        var look = String()
        if material.kind == BASIC:
            look = (
                "fill:"
                + color_style(_linear(material.color))
                + ";fill-opacity:"
                + js_float32_text(material.opacity)
            )
        self._add(look, outline, path, style)

    def _line(
        mut self,
        element: Renderable,
        material: Material,
        half_x: Float64,
        half_y: Float64,
        mut path: String,
        mut style: String,
    ) raises:
        """Draw a segment if it touches the image, three.js's
        `renderLine`."""
        var xs: List[Float64] = [
            element.vertices[0].screen[0] * half_x,
            element.vertices[1].screen[0] * half_x,
        ]
        var ys: List[Float64] = [
            element.vertices[0].screen[1] * -half_y,
            element.vertices[1].screen[1] * -half_y,
        ]
        if not _touches(xs, ys, half_x, half_y):
            return
        if material.kind != BASIC:
            return
        var outline = (
            "M"
            + self._write(xs[0])
            + ","
            + self._write(ys[0])
            + "L"
            + self._write(xs[1])
            + ","
            + self._write(ys[1])
        )
        var look = (
            "fill:none;stroke:"
            + color_style(_linear(material.color))
            + ";stroke-opacity:"
            + js_float32_text(material.opacity)
            + ";stroke-width:1;stroke-linecap:round"
        )
        if material.gap_size.value > 0:
            look += (
                ";stroke-dasharray:"
                + js_float32_text(material.dash_size.value)
                + ","
                + js_float32_text(material.gap_size.value)
            )
        self._add(look, outline, path, style)

    def _face(
        mut self,
        element: Renderable,
        material: Material,
        scene: Scene,
        data: RenderData,
        ambient: Vec,
        normal_view: List[Float64],
        half_x: Float64,
        half_y: Float64,
        mut path: String,
        mut style: String,
    ) raises:
        """Draw a face if it is between the near and far planes and
        touches the image, three.js's `renderFace3`."""
        for k in range(3):  # pragma: no branch
            var z = element.vertices[k].screen[2]
            if z < -1 or z > 1:
                return
        var scale = Vec(half_x, -half_y, 1, 1)
        var c1 = element.vertices[0].screen * scale
        var c2 = element.vertices[1].screen * scale
        var c3 = element.vertices[2].screen * scale
        if self.overdraw > 0:
            _expand(c1, c2, self.overdraw)
            _expand(c2, c3, self.overdraw)
            _expand(c3, c1, self.overdraw)
        var xs: List[Float64] = [c1[0], c2[0], c3[0]]
        var ys: List[Float64] = [c1[1], c2[1], c3[1]]
        # three.js checks that the face touches the image here. The
        # projector keeps only faces whose box touches the clip box, which
        # is the image, and the overdraw only makes a face bigger, so every
        # face that gets here touches it.
        self.vertices += 3
        self.faces += 1
        var outline = String("M")
        for k in range(3):  # pragma: no branch
            if k > 0:
                outline += "L"
            outline += self._write(xs[k]) + "," + self._write(ys[k])
        outline += "z"
        if material.kind == BASIC:
            self._color = _linear(material.color)
            if material.vertex_colors:
                self._color *= element.colors[0]
        elif (
            material.kind == LAMBERT
            or material.kind == PHONG
            or material.kind == STANDARD
            or material.kind == PHYSICAL
        ):
            var diffuse = _linear(material.color)
            if material.vertex_colors:
                diffuse *= element.colors[0]
            var lit = ambient
            var center = (
                element.vertices[0].world
                + element.vertices[1].world
                + element.vertices[2].world
            ) * (1.0 / 3.0)
            for i in data.lights:
                lit += _light(scene, scene.lights[i], center, element.normal)
            self._color = lit * diffuse + _linear(material.emissive)
        elif material.kind == NORMALS:
            var n = apply_normal(normal_view, element.normal)
            self._color = n * 0.5 + 0.5
        var look: String
        var shown = color_style(self._color)
        var opacity = js_float32_text(material.opacity)
        if material.wireframe:
            look = (
                "fill:none;stroke:"
                + shown
                + ";stroke-opacity:"
                + opacity
                + ";stroke-width:1;stroke-linecap:round;stroke-linejoin:round"
            )
        else:
            look = "fill:" + shown + ";fill-opacity:" + opacity
        self._add(look, outline, path, style)


def _dot(a: Vec, b: Vec) -> Float64:
    """Return the dot product of two directions, as three.js adds it."""
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _unit(v: Vec) -> Vec:
    """Return a direction scaled to length one, three.js's `normalize`."""
    var length = sqrt(_dot(v, v))
    return v * (1 / (length if length != 0 and length == length else 1))


def _light(scene: Scene, light: Light, center: Vec, normal: Vec) raises -> Vec:
    """Return what one light adds to a face, three.js's `calculateLight`."""
    if light.kind != DIRECTIONAL and light.kind != POINT:
        return Vec(0)
    var world = scene.world_matrix(light.node)
    var place = Vec(
        Float64(world.elements[12]),
        Float64(world.elements[13]),
        Float64(world.elements[14]),
        0,
    )
    var amount: Float64
    if light.kind == DIRECTIONAL:
        amount = _dot(normal, _unit(place))
        if amount <= 0:
            return Vec(0)
    else:
        # three.js's `lightPosition` is `_vector3`, which the direction
        # overwrites, so the distance is measured to the direction.
        var toward = _unit(place - center)
        amount = _dot(normal, toward)
        if amount <= 0:
            return Vec(0)
        if light.distance != 0:
            var gap = center - toward
            amount *= 1 - min(
                sqrt(_dot(gap, gap)) / Float64(light.distance), 1.0
            )
        if amount == 0:
            return Vec(0)
    return _linear(light.color) * (amount * Float64(light.intensity))
