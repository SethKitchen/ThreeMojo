# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The glare of a bright light seen through a lens, from three.js
`examples/jsm/objects/Lensflare.js`.

A lens flare stands at a node, usually a light's. After the scene is drawn,
it finds where the node lands on the image and how much of it the scene
hides. Then it draws its elements, each a textured square, along the line
from that point through the center of the image, added to the light that
is there.

**How much is hidden.** three.js copies the sixteen by sixteen pixels
around the point, draws a magenta square there at the light's depth, and
copies them again. Where the square passed the depth test, the copy is
magenta; elsewhere it is the scene. Nine pixels of the copy give the
visibility: the mean red, times one minus the mean green, times the mean
blue. This port asks the depth test of the same nine pixels, and reads the
scene's pixel, as the display shows it, where the test fails. The scene's
own colors leak into the answer, as they do in three.js.

**The update is a call.** three.js runs this in the flare's
`onBeforeRender`, as the last object of the frame. Here the caller draws the
scene into a target and then calls `render` on the target.

**The elements are a scene of their own.** Each element is a mesh with a
shader material, drawn by an orthographic camera that sees normalized
device space, with additive blending. three.js draws them with a raw shader
that writes `gl_Position` in that space. The GLSL subset writes it in
three.js's standard form, so the square is placed by its node instead. As
in three.js, the elements are drawn at a device depth of zero: three.js
sets only `x` and `y` of their `screenPosition`.

Where this port differs:

- The element's color is light, encoded when the target is resolved.
  three.js's raw shader writes it to the drawing buffer without an encode.
- The flare reads a target drawn with `STANDARD_DEPTH`, and refuses another
  depth mode.
"""

from cameras.camera import Camera
from cameras.orthographic_camera import OrthographicCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION, UV
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from core.scene import Scene
from materials.glsl import compile_shader_material
from materials.material import ADDITIVE, MaterialId, shader_material
from materials.nodes import NodeProgramId
from math.vector3 import Vector3
from objects.mesh import Mesh
from objects.reflector import view_renderer
from render.framebuffer import Color
from render.raster_state import STANDARD_DEPTH
from render.target import RenderTarget
from render.texture_store import TextureId
from renderers.renderer import Renderer
from std.math import isfinite
from units.si import Length, METER

# The side of the square the occlusion is read from, in pixels.
comptime OCCLUSION_SIZE = 16
# Where three.js's vertex shader reads the occlusion map, as texels of a
# nearest-filtered sixteen-texel square: 0.1, 0.5 and 0.9 of the way.
comptime _SAMPLES: List[Int] = [1, 8, 14]
# What the square three.js draws to test the depth writes: magenta.
comptime _PROBE = Color(255, 0, 255)

comptime LENSFLARE_VERTEX = """
varying vec2 vUV;

void main() {
    vUV = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4( position, 1.0 );
}
"""

# `LensflareElement.Shader`'s fragment shader. The visibility is a uniform:
# three.js reads it from the occlusion map in the vertex shader, and the
# subset reads no texture there. It is one number for the whole element.
comptime LENSFLARE_FRAGMENT = """
uniform sampler2D map;
uniform vec3 color;
uniform float visibility;

varying vec2 vUV;

void main() {
    vec4 texel = texture2D( map, vUV );
    texel.a *= visibility;
    gl_FragColor = texel;
    gl_FragColor.rgb *= color;
}
"""


def lensflare_geometry() raises -> BufferGeometry:
    """Return three.js's `Lensflare.Geometry`: a square from -1 to 1, with
    coordinates from 0 to 1, as two triangles.

    Returns:
        The geometry.

    Raises:
        Error: Never in practice: the numbers are fixed.
    """
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0], 3),
    )
    geometry.set_attribute(
        String(UV), BufferAttribute([0, 0, 1, 0, 1, 1, 0, 1], 2)
    )
    geometry.set_index([0, 1, 2, 0, 2, 3])
    return geometry^


struct LensflareElement(ImplicitlyCopyable):
    """One square of a lens flare, three.js's `LensflareElement`."""

    # The image the square shows.
    var texture: TextureId
    # How wide the square is, in pixels.
    var size: Float32
    # Where the square is along the line from the light, through the
    # center of the image: 0 at the light, 1 at the point opposite it.
    var distance: Float32
    # What the image is multiplied by, as authored in sRGB.
    var color: Color

    def __init__(
        out self,
        texture: TextureId,
        size: Float32 = 1,
        distance: Float32 = 0,
        color: Color = Color(255, 255, 255),
    ) raises:
        """Create an element.

        Args:
            texture: The image the square shows.
            size: How wide the square is, in pixels.
            distance: Where the square is along the flare's line.
            color: What the image is multiplied by, as authored in sRGB.

        Raises:
            Error: If the size or the distance is not finite.
        """
        if not (isfinite(size) and isfinite(distance)):
            raise Error(
                "A lens flare element's size and distance must be finite"
            )
        self.texture = texture
        self.size = size
        self.distance = distance
        self.color = color


struct Lensflare(Movable):
    """A lens flare at a node, three.js's `Lensflare`.

    Add elements with `add_element`. After each frame is drawn into a
    target, call `render` on the target.
    """

    # The node the flare stands at: a light's, usually.
    var node: NodeId
    # The square every element is drawn with, in `assets.geometries`.
    var geometry: GeometryId
    # The elements, in the order they are drawn.
    var elements: List[LensflareElement]
    # Each element's program and material.
    var programs: List[NodeProgramId]
    var materials: List[MaterialId]

    def __init__(out self, mut assets: Assets, node: NodeId) raises:
        """Create a lens flare with no elements and add its square to the
        stores.

        Args:
            assets: The stores. The square is added.
            node: The node the flare stands at.

        Raises:
            Error: Never in practice.
        """
        self.node = node
        self.geometry = assets.geometries.add(lensflare_geometry())
        self.elements = List[LensflareElement]()
        self.programs = List[NodeProgramId]()
        self.materials = List[MaterialId]()

    def add_element(
        mut self, mut assets: Assets, element: LensflareElement
    ) raises:
        """Add an element, three.js's `addElement`, and its program and
        material to the stores.

        Args:
            assets: The stores.
            element: The element.

        Raises:
            Error: If the element's texture is not in the stores.
        """
        _ = assets.textures.get(element.texture)
        var program = compile_shader_material(
            LENSFLARE_VERTEX, LENSFLARE_FRAGMENT
        )
        program.set_texture("map", element.texture)
        program.set_uniform("color", element.color)
        program.set_uniform("visibility", Float32(1))
        var id = assets.programs.add(program^)
        var material = shader_material(id, transparent=True)
        material.blending = ADDITIVE
        material.depth_write = False
        self.elements.append(element)
        self.programs.append(id)
        self.materials.append(assets.materials.add(material))

    def render[
        C: Camera
    ](
        self,
        renderer: Renderer,
        mut target: RenderTarget,
        scene: Scene,
        mut assets: Assets,
        camera: C,
    ) raises -> Bool:
        """Draw the flare into a target the scene was drawn into, three.js's
        `onBeforeRender`.

        Nothing is drawn when the node is behind the camera, or so near the
        edge of the viewport that the square of sixteen pixels around it
        leaves the viewport.

        Args:
            renderer: The renderer the scene was drawn with. Its viewport
                places the flare.
            target: The target the scene was drawn into, not yet resolved.
            scene: The scene, updated.
            assets: The stores. Each element's `visibility` is set.
            camera: The camera the scene was drawn through.

        Returns:
            True if the elements were drawn.

        Raises:
            Error: If the renderer's depth mode is not `STANDARD_DEPTH`, the
                node is not in the scene, or the draw raises.
        """
        if renderer.depth_mode != STANDARD_DEPTH:
            raise Error("A lens flare reads a target of standard depth only")
        var view = camera.view_matrix_in(scene)
        var seen = view.transform_point(scene.world_position(self.node))
        if seen.z > 0:
            return False
        var screen = camera.projection_matrix().transform_point(seen)
        var port = renderer.viewport
        var half_width = Float64(port.width) / 2.0
        var half_height = Float64(port.height) / 2.0
        var corner_x = (
            Float64(port.x) + Float64(screen.x) * half_width + half_width - 8
        )
        var corner_y = (
            Float64(port.y) + Float64(screen.y) * half_height + half_height - 8
        )
        if not _in_valid_area(
            corner_x, corner_y, port.x, port.y, port.width, port.height
        ):
            return False
        var visibility = self.visibility(
            renderer, target, assets, Int(corner_x), Int(corner_y), screen.z
        )
        var overlay = Scene()
        var inverse_aspect = Float64(port.height) / Float64(port.width)
        var toward_x = -Float64(screen.x) * 2
        var toward_y = -Float64(screen.y) * 2
        for index in range(len(self.elements)):
            ref element = self.elements[index]
            ref program = assets.programs.get(self.programs[index])
            program.set_uniform("visibility", visibility)
            var size = Float64(element.size) / Float64(port.height)
            var held = Object3D()
            held.set_position(
                Float32(
                    Float64(screen.x) + toward_x * Float64(element.distance)
                ),
                Float32(
                    Float64(screen.y) + toward_y * Float64(element.distance)
                ),
                -1,
            )
            held.set_scale(Float32(size * inverse_aspect), Float32(size), 1)
            var node = overlay.add(held^)
            overlay.add_mesh(
                Mesh(
                    self.geometry,
                    self.materials[index],
                    node,
                    frustum_culled=False,
                )
            )
        overlay.update()
        var device = OrthographicCamera(
            Length(-1.0, METER),
            Length(1.0, METER),
            Length(1.0, METER),
            Length(-1.0, METER),
            Length(0.0, METER),
            Length(2.0, METER),
        )
        var drawer = view_renderer(renderer, target.width, target.height)
        drawer.clipping_planes.clear()
        drawer.auto_clear = False
        drawer.viewport = port
        drawer.render_into(target, overlay, assets, device)
        return True

    def visibility(
        self,
        renderer: Renderer,
        target: RenderTarget,
        assets: Assets,
        corner_x: Int,
        corner_y: Int,
        depth: Float32,
    ) raises -> Float32:
        """Return how much of the flare the scene lets through, three.js's
        `vVisibility`.

        Args:
            renderer: The renderer the scene was drawn with, for the curve
                a failed pixel is shown through.
            target: The target the scene was drawn into.
            assets: The stores, for a custom curve's program.
            corner_x: The left column of the square of sixteen pixels,
                counted from the left.
            corner_y: The bottom row of the square, counted up from the
                bottom.
            depth: The light's depth in normalized device space.

        Returns:
            The mean red, times one minus the mean green, times the mean
            blue, of the nine pixels three.js reads.

        Raises:
            Error: If the custom curve's program is not in the stores.
        """
        var curve = renderer.curve_program(assets)
        var red = Float32(0)
        var green = Float32(0)
        var blue = Float32(0)
        for i in materialize[_SAMPLES]():  # pragma: no branch
            for j in materialize[_SAMPLES]():  # pragma: no branch
                var x = corner_x + i
                var row = target.height - 1 - (corner_y + j)
                var shown = Color(0, 0, 0)
                if _on_target(x, row, target.width, target.height):
                    shown = _PROBE
                    if depth > target.depth_at(x, row):
                        shown = target.shown(
                            x,
                            row,
                            renderer.tone_curve(),
                            renderer.tone_mapping_exposure,
                            curve,
                            renderer.output_encoding(),
                        )
                red += Float32(shown.r) / 255
                green += Float32(shown.g) / 255
                blue += Float32(shown.b) / 255
        return red / 9 * (1 - green / 9) * (blue / 9)


def _in_valid_area(
    x: Float64, y: Float64, left: Int, bottom: Int, width: Int, height: Int
) -> Bool:
    """Return True if a square's corner leaves the square inside the
    viewport, three.js's `validArea.containsPoint`."""
    return (
        x >= Float64(left)
        and x <= Float64(left + width - OCCLUSION_SIZE)
        and y >= Float64(bottom)
        and y <= Float64(bottom + height - OCCLUSION_SIZE)
    )


def _on_target(x: Int, row: Int, width: Int, height: Int) -> Bool:
    """Return True if a pixel is on the target."""
    return x >= 0 and x < width and row >= 0 and row < height
