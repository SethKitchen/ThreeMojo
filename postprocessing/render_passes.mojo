# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Passes that draw the frame anew: three.js's `RenderPixelatedPass`,
`RenderTransitionPass` and `CubeTexturePass`.

**Pixelated.** `RenderPixelatedPass` draws the scene into a target a
pixel size smaller each way, with its depth and its normals, and shows it
with the nearest texel. Where the depth or the normal jumps between
neighboring texels, it darkens or lightens the texel to draw an edge.

**Transition.** `RenderTransitionPass` draws two scenes and mixes them,
evenly or by a texture's red channel against a moving threshold.

**Cube texture.** `CubeTexturePass` draws a cube texture as the camera
sees it, in the direction of each pixel's ray, over the frame.

The composer draws the scenes; see `postprocessing.composer`. The
functions here take what it drew. Each one's arithmetic for one pixel is a
function of its own.
"""

from cameras.camera import Camera
from core.scene import Scene
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from postprocessing.sampling import u_of, v_of
from postprocessing.effects import texture_pixel
from postprocessing.screen_space import DepthView
from render.cube_texture import CubeTexture
from render.framebuffer import FloatColor
from render.target import RenderTarget
from render.texture import Texture
from std.math import floor, isfinite

# --- pixelated ----------------------------------------------------------------


struct PixelatedSettings(ImplicitlyCopyable):
    """What `RenderPixelatedPass` reads, named as three.js names it."""

    # `pixelSize`: how many frame pixels one drawn texel covers each way.
    var pixel_size: Int
    # `normalEdgeStrength`: how much a normal edge lightens: 0.3.
    var normal_edge_strength: Float32
    # `depthEdgeStrength`: how much a depth edge darkens: 0.4.
    var depth_edge_strength: Float32

    def __init__(out self, pixel_size: Int = 6):
        """Start with three.js's defaults.

        Args:
            pixel_size: How many frame pixels one drawn texel covers.
        """
        self.pixel_size = pixel_size
        self.normal_edge_strength = 0.3
        self.depth_edge_strength = 0.4


def check_pixelated(settings: PixelatedSettings) raises:
    """Refuse pixelated settings no pass could use.

    Args:
        settings: The settings.

    Raises:
        Error: If the pixel size is below one, or a strength is negative or
            not finite.
    """
    if settings.pixel_size < 1:
        raise Error("A pixel size is at least one")
    if not (
        isfinite(settings.normal_edge_strength)
        and isfinite(settings.depth_edge_strength)
    ):
        raise Error("An edge strength must be finite")
    if settings.normal_edge_strength < 0 or settings.depth_edge_strength < 0:
        raise Error("An edge strength must not be negative")


def pixelated_size(size: Int, pixel_size: Int) -> Int:
    """Return the drawn width or height: three.js's `(size / pixelSize) | 0`,
    and at least one.

    Args:
        size: The frame's width or height.
        pixel_size: The pixel size, at least one.

    Returns:
        The drawn size.
    """
    return max(1, size // pixel_size)


def _unpacked(normal: Vector3) -> Vector3:
    """Return a normal as a `MeshNormalMaterial` target reads back through
    `rgb * 2 - 1`: the normal itself, or minus one each way where nothing
    was drawn and the target holds black."""
    if normal.length() == 0:
        return Vector3(-1, -1, -1)
    return normal


struct PixelatedTexels(Movable):
    """What a pixelated pass drew: its window depth and its view-space
    normals, one texel each, row by row from the top."""

    var width: Int
    var height: Int
    var depth: List[Float32]
    var normals: List[Vector3]

    def __init__(out self, drawn: RenderTarget, view: DepthView):
        """Take what a small target drew.

        Args:
            drawn: The small target.
            view: Its depth, read through the camera that drew it.
        """
        self.width = drawn.width
        self.height = drawn.height
        self.depth = view.depth.copy()
        self.normals = List[Vector3](capacity=drawn.width * drawn.height)
        for slot in range(drawn.width * drawn.height):  # pragma: no branch
            var normal = Vector3(0, 0, 0)
            if drawn.has_normals():
                normal = drawn.normals[slot]
            self.normals.append(_unpacked(normal))

    def _slot(self, x: Int, y: Int) -> Int:
        """Return a texel's index, held at the edges; `y` counts up."""
        var cx = min(max(x, 0), self.width - 1)
        var cy = min(max(y, 0), self.height - 1)
        return (self.height - 1 - cy) * self.width + cx

    def depth_at(self, x: Int, y: Int) -> Float32:
        """Return the depth of a texel, held at the edges.

        Args:
            x: The column.
            y: The row, up from the bottom.

        Returns:
            The window depth.
        """
        return self.depth[self._slot(x, y)]

    def normal_at(self, x: Int, y: Int) -> Vector3:
        """Return the normal of a texel, held at the edges.

        Args:
            x: The column.
            y: The row, up from the bottom.

        Returns:
            The view-space normal.
        """
        return self.normals[self._slot(x, y)]


def _depth_edge(texels: PixelatedTexels, x: Int, y: Int) -> Float32:
    """Return `depthEdgeIndicator`: zero, one half or one, as the four
    neighbors lie behind the texel."""
    var depth = texels.depth_at(x, y)
    var diff = Float32(0)
    diff += min(max(texels.depth_at(x + 1, y) - depth, 0), 1)
    diff += min(max(texels.depth_at(x - 1, y) - depth, 0), 1)
    diff += min(max(texels.depth_at(x, y + 1) - depth, 0), 1)
    diff += min(max(texels.depth_at(x, y - 1) - depth, 0), 1)
    return floor(smoothstep(Float32(0.01), Float32(0.02), diff) * 2) / 2


def _neighbor_normal_edge(
    texels: PixelatedTexels, x: Int, y: Int, dx: Int, dy: Int
) -> Float32:
    """Return `neighborNormalEdgeIndicator` for one neighbor."""
    var depth = texels.depth_at(x, y)
    var normal = texels.normal_at(x, y)
    var depth_diff = texels.depth_at(x + dx, y + dy) - depth
    var neighbor = texels.normal_at(x + dx, y + dy)
    var normal_diff = (
        (normal.x - neighbor.x)
        + (normal.y - neighbor.y)
        + (normal.z - neighbor.z)
    )
    var normal_indicator = min(
        max(smoothstep(Float32(-0.01), Float32(0.01), normal_diff), 0), 1
    )
    # `clamp(sign(depthDiff * .25 + .0025), 0.0, 1.0)`: one where the
    # neighbor is not in front by more than a hundredth.
    var depth_indicator = Float32(0)
    if depth_diff * 0.25 + 0.0025 > 0:
        depth_indicator = 1
    return (1 - normal.dot(neighbor)) * depth_indicator * normal_indicator


def _normal_edge(texels: PixelatedTexels, x: Int, y: Int) -> Float32:
    """Return `normalEdgeIndicator`: one where the four neighbors' normal
    edges add to a tenth or more."""
    var indicator = (
        _neighbor_normal_edge(texels, x, y, 0, -1)
        + _neighbor_normal_edge(texels, x, y, 0, 1)
        + _neighbor_normal_edge(texels, x, y, -1, 0)
        + _neighbor_normal_edge(texels, x, y, 1, 0)
    )
    if indicator < 0.1:
        return 0
    return 1


def pixelated_strength(
    texels: PixelatedTexels, x: Int, y: Int, settings: PixelatedSettings
) -> Float32:
    """Return what one drawn texel is scaled by: `RenderPixelatedPass`'s
    shader. A depth edge darkens by its strength; otherwise a normal edge
    lightens by its own.

    Args:
        texels: What the pass drew.
        x: The texel's column.
        y: The texel's row, up from the bottom.
        settings: The two strengths.

    Returns:
        The factor.
    """
    var depth_edge = Float32(0)
    if settings.depth_edge_strength > 0:
        depth_edge = _depth_edge(texels, x, y)
    var normal_edge = Float32(0)
    if settings.normal_edge_strength > 0:
        normal_edge = _normal_edge(texels, x, y)
    if depth_edge > 0:
        return 1 - settings.depth_edge_strength * depth_edge
    return 1 + settings.normal_edge_strength * normal_edge


def pixelated_light(
    mut frame: RenderTarget,
    drawn: RenderTarget,
    view: DepthView,
    settings: PixelatedSettings,
):
    """Show a small drawing of the scene over the whole frame, each texel a
    block of pixels with its edges drawn: three.js's `RenderPixelatedPass`.

    Each frame pixel reads the nearest drawn texel, as three.js's targets
    read with `NearestFilter`. The texel, alpha included, is scaled by
    `pixelated_strength`. The frame takes the texel's data flag and its
    stored depth.

    Args:
        frame: The frame, replaced.
        drawn: The scene drawn at `pixelated_size` each way, with a normal
            attachment.
        view: The small target's depth, through the camera that drew it.
        settings: The strengths.
    """
    var texels = PixelatedTexels(drawn, view)
    var factors = List[Float32](capacity=drawn.width * drawn.height)
    for ty in range(drawn.height):  # pragma: no branch
        for tx in range(drawn.width):  # pragma: no branch
            factors.append(
                pixelated_strength(texels, tx, drawn.height - 1 - ty, settings)
            )
    frame.depth_mode = drawn.depth_mode
    for y in range(frame.height):  # pragma: no branch
        var ty = min(
            Int(floor(v_of(y, frame.height) * Float32(drawn.height))),
            drawn.height - 1,
        )
        for x in range(frame.width):  # pragma: no branch
            var tx = min(
                Int(floor(u_of(x, frame.width) * Float32(drawn.width))),
                drawn.width - 1,
            )
            var source = (drawn.height - 1 - ty) * drawn.width + tx
            var slot = y * frame.width + x
            var texel = drawn.colors[source]
            var k = factors[source]
            frame.colors[slot] = FloatColor(
                texel.r * k, texel.g * k, texel.b * k, texel.a * k
            )
            frame.data[slot] = drawn.data[source]
            frame.depth[slot] = drawn.depth[source]


# --- transition ---------------------------------------------------------------


struct TransitionSettings(ImplicitlyCopyable):
    """What `RenderTransitionPass` reads, named as three.js names it."""

    # `mixRatio`: zero shows the second scene, one the first.
    var mix_ratio: Float32
    # `threshold`: how soft the texture's edge is: 0.1.
    var threshold: Float32
    # `useTexture`: whether the texture's red channel leads the mix.
    var use_texture: Bool

    def __init__(out self):
        """Start with three.js's defaults: a ratio of zero, a threshold of
        a tenth, and the texture on."""
        self.mix_ratio = 0
        self.threshold = 0.1
        self.use_texture = True


def check_transition(settings: TransitionSettings) raises:
    """Refuse transition settings no pass could use.

    Args:
        settings: The settings.

    Raises:
        Error: If a setting is not finite, or the threshold is not
            positive, where three.js divides by it.
    """
    if not (isfinite(settings.mix_ratio) and isfinite(settings.threshold)):
        raise Error("A transition setting must be finite")
    if settings.threshold <= 0:
        raise Error("A transition threshold must be positive")


def _mixed(a: FloatColor, b: FloatColor, t: Float32) -> FloatColor:
    """Return GLSL's `mix` of two colors."""
    return FloatColor(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t,
        a.a + (b.a - a.a) * t,
    )


def transition_pixel(
    first: FloatColor,
    second: FloatColor,
    texel: FloatColor,
    settings: TransitionSettings,
) -> FloatColor:
    """Return one pixel of `RenderTransitionPass`'s shader.

    With the texture, the mix is the texture's red above a threshold that
    sweeps from below zero to above one as `mix_ratio` goes from zero to
    one, over `threshold`, clamped. Without it, the second scene is mixed
    toward the first by `mix_ratio`, as the shader spells it:
    `mix(texel2, texel1, mixRatio)`.

    Args:
        first: The first scene's light at the pixel, premultiplied.
        second: The second scene's.
        texel: The texture at the pixel; its red is read.
        settings: The ratio, the threshold and the switch.

    Returns:
        The mix, premultiplied.
    """
    if settings.use_texture:
        var r = settings.mix_ratio * (1 + settings.threshold * 2) - (
            settings.threshold
        )
        var t = min(
            max((texel.r - r) * (1 / settings.threshold), Float32(0)),
            Float32(1),
        )
        return _mixed(first, second, t)
    return _mixed(second, first, settings.mix_ratio)


def transition_light(
    mut frame: RenderTarget,
    first: RenderTarget,
    second: RenderTarget,
    texels: List[FloatColor],
    settings: TransitionSettings,
):
    """Mix two drawn scenes into the frame: three.js's
    `RenderTransitionPass`.

    Args:
        frame: The frame, replaced.
        first: The first scene, drawn.
        second: The second scene, drawn.
        texels: The texture at each pixel's center, row by row from the
            top; read only with `use_texture` on.
        settings: The ratio, the threshold and the switch.
    """
    for slot in range(len(frame.colors)):  # pragma: no branch
        var texel = FloatColor(0, 0, 0, 0)
        if settings.use_texture:
            texel = texels[slot]
        frame.colors[slot] = transition_pixel(
            first.light_at(slot), second.light_at(slot), texel, settings
        )
        frame.data[slot] = False
        frame.depth[slot] = first.depth[slot]
    frame.depth_mode = first.depth_mode


# --- cube texture -------------------------------------------------------------


def cube_overlay[
    C: Camera
](
    sky: CubeTexture, camera: C, scene: Scene, width: Int, height: Int
) raises -> List[FloatColor]:
    """Return the cube texture in the direction of each pixel's ray,
    premultiplied: what `CubeTexturePass` draws.

    three.js draws a box around a camera that has the camera's projection
    and turn but stands at the origin. Each pixel's ray is unprojected into
    view space and turned into the world, as `Renderer.backdrop` reads a
    cube background, so the camera's position changes nothing. A cube
    texture is read through three.js's `tFlip` of minus one, as
    `CubeTexture.sample` reads it.

    Args:
        sky: The cube texture.
        camera: The camera the frame is drawn through.
        scene: The scene the camera's placement is read from.
        width: The frame's width in pixels.
        height: The frame's height in pixels.

    Returns:
        One texel per pixel, row by row from the top.

    Raises:
        Error: If the camera's matrices cannot be built.
    """
    var unproject = camera.projection_matrix()
    unproject.invert()
    var to_world = camera.view_matrix_in(scene)
    to_world.invert()
    var texels = List[FloatColor](capacity=width * height)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var ndc_x = u_of(x, width) * 2 - 1
            var ndc_y = v_of(y, height) * 2 - 1
            var near = unproject.transform_point(Vector3(ndc_x, ndc_y, -1))
            var far = unproject.transform_point(Vector3(ndc_x, ndc_y, 1))
            texels.append(
                sky.sample(
                    to_world.transform_direction(far - near)
                ).premultiplied()
            )
    return texels^


def cube_texture_light(
    mut frame: RenderTarget, overlay: List[FloatColor], opacity: Float32
):
    """Draw a cube texture over the frame: three.js's `CubeTexturePass`.

    The cube's alpha is scaled by the opacity. Below an opacity of one,
    three.js blends by it with `NormalBlending`; at one it writes the cube
    as it is. That is `texture_pixel` of the premultiplied texel, as the
    texture pass draws. The result holds light.

    Args:
        frame: The frame, changed in place.
        overlay: The cube at each pixel, premultiplied: `cube_overlay`.
        opacity: What the cube's alpha is scaled by.
    """
    for slot in range(len(frame.colors)):  # pragma: no branch
        frame.colors[slot] = texture_pixel(
            frame.colors[slot], overlay[slot], opacity
        )
        frame.data[slot] = False
