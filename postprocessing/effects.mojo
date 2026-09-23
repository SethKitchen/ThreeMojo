# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""More passes: three.js's `BokehPass`, `GlitchPass`, `HalftonePass`,
`MaskPass`, `ClearMaskPass`, `ClearPass` and `TexturePass`.

**Bokeh** blurs each pixel by how far its depth is from the focus, with
the 41 taps of three.js's `BokehShader`. **Glitch** shifts the channels
apart, tears rows and columns and adds snow, at random moments, as
`DigitalGlitch` does. **Halftone** redraws each channel as a grid of dots,
lines or squares, as `HalftoneShader` does.

**The mask.** three.js's `MaskPass` draws a scene into the stencil buffer
and turns the stencil test on, so the passes after it change only the
pixels the scene covers; `ClearMaskPass` turns the test off. This port
writes the render target's own stencil buffer the same way, one where
the mask's objects cover a pixel and zero elsewhere, and the composer puts
back every pixel whose stencil is not one after each pass. That is the
copy three.js's composer makes after a pass inside a mask.

**Randomness.** three.js draws the glitch from `Math.random`. This port
draws it from `math.utils.SeededRandom`, so a pass with the same seed
gives the same frames.

The passes run on the host, as every pass in `postprocessing` does.
"""

from core.layers import Layers
from math.utils import SeededRandom
from math.vector2 import Vector2
from postprocessing.screen_space import DepthView
from postprocessing.sampling import sample, u_of, v_of
from render.framebuffer import Color, FloatColor
from render.raster_state import (
    EQUAL_STENCIL_FUNC,
    REPLACE_STENCIL_OP,
    STENCIL_MAX,
    stencil_apply,
    stencil_compare,
)
from render.target import RenderTarget
from render.texture import Texture
from std.math import atan2, cos, floor, inf, isfinite, pi, sin, sqrt
from units.si import Angle, Length, METER, RADIAN

# --- bokeh ------------------------------------------------------------------

# `BokehShader` sums this many taps and divides by the count.
comptime BOKEH_TAPS = 41


struct BokehSettings(ImplicitlyCopyable):
    """What `BokehPass` reads, named as three.js names it."""

    # The distance in focus: `focus`.
    var focus: Length
    # How fast the blur grows away from the focus, in texture widths per
    # meter: `aperture`.
    var aperture: Float32
    # The most blur, in texture widths: `maxblur`.
    var max_blur: Float32

    def __init__(out self):
        """Start with three.js's defaults: a focus of one meter, an
        aperture of 0.025 and a largest blur of one."""
        self.focus = Length(1.0, METER)
        self.aperture = 0.025
        self.max_blur = 1.0


def check_bokeh(settings: BokehSettings) raises:
    """Refuse bokeh settings no pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If a setting is negative or not finite.
    """
    if not (
        isfinite(settings.focus.value)
        and isfinite(settings.aperture)
        and isfinite(settings.max_blur)
    ):
        raise Error("A bokeh setting must be finite")
    if (
        settings.focus.value < 0
        or settings.aperture < 0
        or settings.max_blur < 0
    ):
        raise Error("A bokeh setting must not be negative")


def bokeh_taps() -> List[Vector2]:
    """Return the 41 offsets `BokehShader` reads, each already scaled by
    its ring: the center, 16 at the full blur, 8 at nine tenths, 8 at
    seven tenths and 8 at four tenths.

    Returns:
        The offsets, in units of the blur.
    """
    var full: List[Vector2] = [
        Vector2(0.0, 0.4),
        Vector2(0.15, 0.37),
        Vector2(0.29, 0.29),
        Vector2(-0.37, 0.15),
        Vector2(0.4, 0.0),
        Vector2(0.37, -0.15),
        Vector2(0.29, -0.29),
        Vector2(-0.15, -0.37),
        Vector2(0.0, -0.4),
        Vector2(-0.15, 0.37),
        Vector2(-0.29, 0.29),
        Vector2(0.37, 0.15),
        Vector2(-0.4, 0.0),
        Vector2(-0.37, -0.15),
        Vector2(-0.29, -0.29),
        Vector2(0.15, -0.37),
    ]
    var nine: List[Vector2] = [
        Vector2(0.15, 0.37),
        Vector2(-0.37, 0.15),
        Vector2(0.37, -0.15),
        Vector2(-0.15, -0.37),
        Vector2(-0.15, 0.37),
        Vector2(0.37, 0.15),
        Vector2(-0.37, -0.15),
        Vector2(0.15, -0.37),
    ]
    # The seven-tenths ring and the four-tenths ring read the same eight.
    var inner: List[Vector2] = [
        Vector2(0.29, 0.29),
        Vector2(0.4, 0.0),
        Vector2(0.29, -0.29),
        Vector2(0.0, -0.4),
        Vector2(-0.29, 0.29),
        Vector2(-0.4, 0.0),
        Vector2(-0.29, -0.29),
        Vector2(0.0, 0.4),
    ]
    var taps = List[Vector2](capacity=BOKEH_TAPS)
    taps.append(Vector2(0, 0))
    for tap in full:  # pragma: no branch
        taps.append(tap)
    for tap in nine:  # pragma: no branch
        taps.append(Vector2(tap.x * 0.9, tap.y * 0.9))
    for tap in inner:  # pragma: no branch
        taps.append(Vector2(tap.x * 0.7, tap.y * 0.7))
    for tap in inner:  # pragma: no branch
        taps.append(Vector2(tap.x * 0.4, tap.y * 0.4))
    return taps^


def bokeh_blur(
    view: DepthView, depth: Float32, settings: BokehSettings
) -> Float32:
    """Return how far a pixel's taps reach: `BokehShader`'s `dofblur`.

    The window depth becomes a view-space z through three.js's
    `perspectiveDepthToViewZ`, whatever the camera, as `BokehShader`
    defines `PERSPECTIVE_CAMERA`. The focus plus that z, times the
    aperture, clamped to the largest blur either way, is the reach.

    Args:
        view: The frame's depth and the camera's near and far distances.
        depth: The pixel's window depth.
        settings: The focus, the aperture and the largest blur.

    Returns:
        The reach, in texture widths, negative in front of the focus.
    """
    var z = (view.near * view.far) / ((view.far - view.near) * depth - view.far)
    var factor = (settings.focus.value + z) * settings.aperture
    return max(-settings.max_blur, min(settings.max_blur, factor))


def bokeh_light(
    mut frame: RenderTarget, view: DepthView, settings: BokehSettings
):
    """Blur each pixel by how far it is from the focus: three.js's
    `BokehShader`.

    Each pixel is the average of 41 taps around it, their offsets scaled
    by `bokeh_blur` and the vertical ones by the frame's aspect, as
    three.js scales them by the camera's. The taps read the stored light.
    The result is opaque and holds light, as the shader sets alpha to one.

    Args:
        frame: The frame, changed in place.
        view: The frame's depth, drawn through the camera.
        settings: The focus, the aperture and the largest blur.
    """
    var width = frame.width
    var height = frame.height
    var source = frame.colors.copy()
    var taps = bokeh_taps()
    var aspect = Float32(width) / Float32(height)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var slot = y * width + x
            var u = u_of(x, width)
            var v = v_of(y, height)
            var blur = bokeh_blur(view, view.depth[slot], settings)
            var sum = FloatColor(0, 0, 0, 0)
            # Spelled with `while`: a `for` over the taps inside the two
            # loops over the pixels does not finish compiling.
            var index = 0
            while index < BOKEH_TAPS:
                var tap = taps[index]
                index += 1
                var here = sample(
                    source,
                    width,
                    height,
                    u + tap.x * blur,
                    v + tap.y * aspect * blur,
                )
                sum = FloatColor(
                    sum.r + here.r, sum.g + here.g, sum.b + here.b, 0
                )
            var share = 1 / Float32(BOKEH_TAPS)
            frame.colors[slot] = FloatColor(
                sum.r * share, sum.g * share, sum.b * share, 1
            )
            frame.data[slot] = False
            x += 1
        y += 1


# --- glitch -----------------------------------------------------------------

# `DigitalGlitch`'s `col_s`: how wide the torn band is.
comptime GLITCH_BAND = Float32(0.05)
# The largest displacement map, in texels a side. three.js sets none; this
# port refuses a size whose square does not fit a reasonable buffer.
comptime GLITCH_MAX_SIZE = 4096
# `GlitchPass.generateTrigger`: a wild frame comes every 120 to 240 frames.
comptime GLITCH_TRIGGER_LOW = 120
comptime GLITCH_TRIGGER_HIGH = 240
# The generator's state is 32 bits.
comptime GLITCH_STATE_MAX = 0xFFFFFFFF


struct GlitchSettings(ImplicitlyCopyable):
    """What `GlitchPass` keeps: its displacement map's size and seed, the
    generator it draws from, `goWild`, `curF` and `randX`."""

    # The displacement map is this many texels a side: `dt_size`.
    var size: Int
    # The seed the map is drawn from.
    var seed: Int
    # The generator's state, advanced every frame.
    var state: Int
    # Whether every frame is wild: `goWild`.
    var go_wild: Bool
    # Frames since the last wild one: `curF`.
    var frame: Int
    # How many frames apart the wild ones are: `randX`.
    var trigger: Int

    def __init__(out self, size: Int = 64, seed: Int = 0):
        """Start as three.js's constructor does: draw the map, then the
        first trigger, from one generator seeded with `seed`.

        Args:
            size: The map's texels a side, three.js's `dt_size`.
            seed: The generator's seed.
        """
        self.size = size
        self.seed = seed
        self.go_wild = False
        self.frame = 0
        var random = SeededRandom(seed)
        var index = 0
        while index < size * size:
            _ = random.next()
            index += 1
        self.trigger = random.int_in(GLITCH_TRIGGER_LOW, GLITCH_TRIGGER_HIGH)
        self.state = Int(random.state)


def check_glitch(settings: GlitchSettings) raises:
    """Refuse glitch settings no pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the size is outside one through 4096, the state does
            not fit 32 bits, the frame count is negative, or the trigger
            is not positive.
    """
    if settings.size < 1 or settings.size > GLITCH_MAX_SIZE:
        raise Error("A glitch map is one through 4096 texels a side")
    if settings.state < 0 or settings.state > GLITCH_STATE_MAX:
        raise Error("A glitch generator's state is 32 bits")
    if settings.frame < 0:
        raise Error("A glitch frame count must not be negative")
    if settings.trigger < 1:
        raise Error("A glitch trigger must be positive")


def glitch_heightmap(size: Int, seed: Int) -> List[Float32]:
    """Return the displacement map `GlitchPass.generateHeightmap` draws:
    one number from zero to one per texel, row by row from the bottom.

    Args:
        size: Texels a side.
        seed: The generator's seed.

    Returns:
        The map, `size` squared values.
    """
    var random = SeededRandom(seed)
    var values = List[Float32](capacity=max(size * size, 0))
    var index = 0
    while index < size * size:
        values.append(Float32(random.next()))
        index += 1
    return values^


struct GlitchUniforms(ImplicitlyCopyable):
    """What `DigitalGlitch` reads in one frame, named as three.js names
    its uniforms."""

    # Whether the frame is left alone: `byp`.
    var bypass: Bool
    # How far the channels shift apart: `amount`.
    var amount: Float32
    # Which way they shift: `angle`.
    var angle: Angle
    # The frame's noise seed: `seed`.
    var seed: Float32
    # Which way the map pushes, and which way a torn band flips: `seed_x`
    # and `seed_y`.
    var seed_x: Float32
    var seed_y: Float32
    # Where the torn row and column are: `distortion_x` and `distortion_y`.
    var distortion_x: Float32
    var distortion_y: Float32

    def __init__(out self):
        """Start with `DigitalGlitch`'s defaults, not bypassed."""
        self.bypass = False
        self.amount = 0.08
        self.angle = Angle(0.02, RADIAN)
        self.seed = 0.02
        self.seed_x = 0.02
        self.seed_y = 0.02
        self.distortion_x = 0.5
        self.distortion_y = 0.6


def glitch_uniforms(mut settings: GlitchSettings) -> GlitchUniforms:
    """Draw one frame's uniforms and advance the pass: three.js's
    `GlitchPass.render` before it draws.

    A frame whose count is a multiple of the trigger, or every frame when
    `go_wild` is on, is wild: a large shift and a wide tear, and a new
    trigger. The first fifth of the frames after it glitch a little. The
    rest are bypassed. The draws come in three.js's order.

    Args:
        settings: The pass's state, advanced.

    Returns:
        The uniforms.
    """
    var random = SeededRandom(0)
    random.state = UInt32(settings.state)
    var uniforms = GlitchUniforms()
    uniforms.seed = Float32(random.next())
    var phase = settings.frame % settings.trigger
    if phase == 0 or settings.go_wild:
        uniforms.amount = Float32(random.next()) / 30
        uniforms.angle = Angle(
            random.float_in(-Float32(pi), Float32(pi)), RADIAN
        )
        uniforms.seed_x = random.float_in(-1, 1)
        uniforms.seed_y = random.float_in(-1, 1)
        uniforms.distortion_x = random.float_in(0, 1)
        uniforms.distortion_y = random.float_in(0, 1)
        settings.frame = 0
        settings.trigger = random.int_in(
            GLITCH_TRIGGER_LOW, GLITCH_TRIGGER_HIGH
        )
    elif Float32(phase) < Float32(settings.trigger) / 5:
        uniforms.amount = Float32(random.next()) / 90
        uniforms.angle = Angle(
            random.float_in(-Float32(pi), Float32(pi)), RADIAN
        )
        uniforms.distortion_x = random.float_in(0, 1)
        uniforms.distortion_y = random.float_in(0, 1)
        uniforms.seed_x = random.float_in(-0.3, 0.3)
        uniforms.seed_y = random.float_in(-0.3, 0.3)
    else:
        # three.js asks `goWild == false` here, which the first branch
        # has already made true.
        uniforms.bypass = True
    settings.frame += 1
    settings.state = Int(random.state)
    return uniforms


def sine_hash(u: Float32, v: Float32) -> Float32:
    """Return the `rand` that `DigitalGlitch` and `HalftoneShader` define
    for themselves: the fractional part of a large sine of the
    coordinate's dot with a fixed vector, with no reduction modulo pi.

    Args:
        u: The first coordinate.
        v: The second.

    Returns:
        A number from zero up to one.
    """
    var s = sin(u * 12.9898 + v * 78.233) * 43758.5453
    return s - floor(s)


def _nearest(
    values: List[Float32], size: Int, u: Float32, v: Float32
) -> Float32:
    """Return a square map's texel at a texture coordinate, as a
    `DataTexture` with `NearestFilter` and `ClampToEdgeWrapping` reads it.
    The rows run up from the bottom."""
    var top = Float32(size - 1)
    var column = Int(max(Float32(0), min(top, floor(u * Float32(size)))))
    var row = Int(max(Float32(0), min(top, floor(v * Float32(size)))))
    return values[row * size + column]


def glitch_light(
    mut frame: RenderTarget,
    heightmap: List[Float32],
    size: Int,
    uniforms: GlitchUniforms,
):
    """Shift the channels apart, tear a row and a column, push the frame
    by the displacement map and add snow: three.js's `DigitalGlitch`.

    A bypassed frame is left as it is. The taps read the stored light,
    and the snow is added to all four channels, as the shader adds it.

    Args:
        frame: The frame, changed in place.
        heightmap: The displacement map, `size` squared values.
        size: The map's texels a side.
        uniforms: The frame's uniforms.
    """
    if uniforms.bypass:
        return
    var width = frame.width
    var height = frame.height
    var source = frame.colors.copy()
    var seed = uniforms.seed
    var shift_x = uniforms.amount * cos(uniforms.angle.value)
    var shift_y = uniforms.amount * sin(uniforms.angle.value)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var u = u_of(x, width)
            var v = v_of(y, height)
            # `gl_FragCoord` counts up from the bottom left, at centers.
            var xs = floor((Float32(x) + 0.5) / 0.5)
            var ys = floor((Float32(height - 1 - y) + 0.5) / 0.5)
            var disp = _nearest(
                heightmap, size, u * seed * seed, v * seed * seed
            )
            var px = u
            var py = v
            if (
                py < uniforms.distortion_x + GLITCH_BAND
                and py > uniforms.distortion_x - GLITCH_BAND * seed
            ):
                if uniforms.seed_x > 0:
                    py = 1 - (py + uniforms.distortion_y)
                else:
                    py = uniforms.distortion_y
            if (
                px < uniforms.distortion_y + GLITCH_BAND
                and px > uniforms.distortion_y - GLITCH_BAND * seed
            ):
                if uniforms.seed_y > 0:
                    px = uniforms.distortion_x
                else:
                    px = 1 - (px + uniforms.distortion_x)
            px += disp * uniforms.seed_x * (seed / 5)
            py += disp * uniforms.seed_y * (seed / 5)
            var red = sample(source, width, height, px + shift_x, py + shift_y)
            var middle = sample(source, width, height, px, py)
            var blue = sample(source, width, height, px - shift_x, py - shift_y)
            var snow = (
                200
                * uniforms.amount
                * sine_hash(xs * seed, ys * seed * 50)
                * 0.2
            )
            frame.colors[y * width + x] = FloatColor(
                red.r + snow, middle.g + snow, blue.b + snow, middle.a + snow
            )
            x += 1
        y += 1


# --- halftone ---------------------------------------------------------------


@fieldwise_init
struct HalftoneShape(Equatable, ImplicitlyCopyable, Writable):
    """What a halftone draws each channel with, as a type rather than a
    bare int: `HalftoneShader`'s `shape`, with its numbering.

    The type stops a bare integer at compile time; it does not stop
    `HalftoneShape(5)`, which `check_halftone` refuses.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four shapes there are.

        Returns:
            Whether the value names a shape.
        """
        return self.value >= 1 and self.value <= 4


# Round dots: `SHAPE_DOT`.
comptime HALFTONE_DOT = HalftoneShape(1)
# Dots stretched along the grid: `SHAPE_ELLIPSE`.
comptime HALFTONE_ELLIPSE = HalftoneShape(2)
# Lines along the grid: `SHAPE_LINE`.
comptime HALFTONE_LINE = HalftoneShape(3)
# Squares turned with the grid: `SHAPE_SQUARE`.
comptime HALFTONE_SQUARE = HalftoneShape(4)


@fieldwise_init
struct HalftoneBlending(Equatable, ImplicitlyCopyable, Writable):
    """How a halftone mixes with the frame under it, as a type rather than
    a bare int: `HalftoneShader`'s `blendingMode`, with its numbering.

    The type stops a bare integer at compile time; it does not stop
    `HalftoneBlending(6)`, which `check_halftone` refuses.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the five modes there are.

        Returns:
            Whether the value names a blending mode.
        """
        return self.value >= 1 and self.value <= 5


# A straight mix: `BLENDING_LINEAR`.
comptime HALFTONE_LINEAR = HalftoneBlending(1)
# The product: `BLENDING_MULTIPLY`.
comptime HALFTONE_MULTIPLY = HalftoneBlending(2)
# The sum, held at one: `BLENDING_ADD`.
comptime HALFTONE_ADD = HalftoneBlending(3)
# The lighter of the two: `BLENDING_LIGHTER`.
comptime HALFTONE_LIGHTER = HalftoneBlending(4)
# The darker of the two: `BLENDING_DARKER`.
comptime HALFTONE_DARKER = HalftoneBlending(5)

# `HalftoneShader`'s `SQRT2_MINUS_ONE` and `SQRT2_HALF_MINUS_ONE`.
comptime SQRT2_MINUS_ONE = Float32(0.41421356)
comptime SQRT2_HALF_MINUS_ONE = Float32(0.20710678)
# Its `PI2`.
comptime HALFTONE_PI2 = Float32(6.28318531)
# Its `samples`: each corner reads itself and this many around it.
comptime HALFTONE_SAMPLES = 8


struct HalftoneSettings(ImplicitlyCopyable):
    """What `HalftonePass` reads, named as three.js names its
    parameters."""

    # `shape`.
    var shape: HalftoneShape
    # The grid's spacing and the largest dot, in pixels: `radius`.
    var radius: Float32
    # Each channel's grid angle: `rotateR`, `rotateG` and `rotateB`.
    var rotate_r: Angle
    var rotate_g: Angle
    var rotate_b: Angle
    # How far each dot strays from its grid point, zero to one of half a
    # cell: `scatter`.
    var scatter: Float32
    # How much of the halftone shows over the frame, zero to one:
    # `blending`.
    var blending: Float32
    # `blendingMode`.
    var blending_mode: HalftoneBlending
    # Whether the three channels are averaged to gray: `greyscale`.
    var grayscale: Bool
    # Whether the pass leaves the frame alone: `disable`.
    var disable: Bool

    def __init__(out self):
        """Start with `HalftoneShader`'s defaults: dots four pixels apart,
        the grids at 15, 30 and 45 degrees, no scatter, and the halftone
        alone."""
        self.shape = HALFTONE_DOT
        self.radius = 4.0
        self.rotate_r = Angle(Float32(pi) / 12, RADIAN)
        self.rotate_g = Angle(Float32(pi) / 12 * 2, RADIAN)
        self.rotate_b = Angle(Float32(pi) / 12 * 3, RADIAN)
        self.scatter = 0.0
        self.blending = 1.0
        self.blending_mode = HALFTONE_LINEAR
        self.grayscale = False
        self.disable = False


def check_halftone(settings: HalftoneSettings) raises:
    """Refuse halftone settings no pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the shape or the blending mode is none of those named, a
            setting is not finite, the radius is not positive, the scatter
            is negative, or the blending is outside zero to one.
    """
    if not settings.shape.is_valid():
        raise Error("A halftone shape must be one of the four named")
    if not settings.blending_mode.is_valid():
        raise Error("A halftone blending mode must be one of the five named")
    if not (
        isfinite(settings.radius)
        and isfinite(settings.rotate_r.value)
        and isfinite(settings.rotate_g.value)
        and isfinite(settings.rotate_b.value)
        and isfinite(settings.scatter)
        and isfinite(settings.blending)
    ):
        raise Error("A halftone setting must be finite")
    if settings.radius <= 0:
        raise Error("A halftone radius must be positive")
    if settings.scatter < 0:
        raise Error("A halftone scatter must not be negative")
    if settings.blending < 0 or settings.blending > 1:
        raise Error("A halftone blending runs from zero to one")


def _hypot(x: Float32, y: Float32) -> Float32:
    """Return the length of (x, y): the shader's `hypot`."""
    return sqrt(x * x + y * y)


def _glsl_mod(x: Float32, y: Float32) -> Float32:
    """Return GLSL's `mod`: `x` less `y` times the floor of their ratio."""
    return x - y * floor(x / y)


def dot_radius_distance(
    shape: HalftoneShape,
    channel: Float32,
    coord: Vector2,
    normal: Vector2,
    p: Vector2,
    angle: Float32,
    rad_max: Float32,
) -> Float32:
    """Return how far inside a corner's dot a point is: `HalftoneShader`'s
    `distanceToDotRadius`.

    Args:
        shape: The dot's shape.
        channel: The channel's value at the corner, which sizes the dot.
        coord: The corner, in pixels.
        normal: The grid's direction.
        p: The point, in pixels.
        angle: The grid's angle, in radians.
        rad_max: The largest dot, in pixels.

    Returns:
        The dot's radius less the point's distance: positive inside.
    """
    var dist = _hypot(coord.x - p.x, coord.y - p.y)
    var rad = channel
    if shape == HALFTONE_DOT:
        rad = (abs(rad) ** 1.125) * rad_max
    elif shape == HALFTONE_ELLIPSE:
        rad = (abs(rad) ** 1.125) * rad_max
        if dist != 0:
            var dot_p = abs(
                (p.x - coord.x) / dist * normal.x
                + (p.y - coord.y) / dist * normal.y
            )
            dist = (dist * (1 - SQRT2_HALF_MINUS_ONE)) + (
                dot_p * dist * SQRT2_MINUS_ONE
            )
    elif shape == HALFTONE_LINE:
        rad = (abs(rad) ** 1.5) * rad_max
        var dot_p = (p.x - coord.x) * normal.x + (p.y - coord.y) * normal.y
        dist = _hypot(normal.x * dot_p, normal.y * dot_p)
    else:
        # `HALFTONE_SQUARE`, the only shape left once it is checked.
        var theta = atan2(p.y - coord.y, p.x - coord.x) - angle
        var sin_t = abs(sin(theta))
        var cos_t = abs(cos(theta))
        rad = abs(rad) ** 1.4
        var corner = (rad - sin_t * rad) if sin_t > cos_t else (
            rad - cos_t * rad
        )
        rad = rad_max * (rad + corner)
    return rad - dist


struct HalftoneCell(ImplicitlyCopyable):
    """The four grid points around a pixel for one channel:
    `HalftoneShader`'s `Cell`, less its samples."""

    # The grid's direction.
    var normal: Vector2
    # The nearest grid point, and the three that close the square with it.
    var p1: Vector2
    var p2: Vector2
    var p3: Vector2
    var p4: Vector2

    def __init__(out self):
        """Start with every point at the origin."""
        self.normal = Vector2(1, 0)
        self.p1 = Vector2(0, 0)
        self.p2 = Vector2(0, 0)
        self.p3 = Vector2(0, 0)
        self.p4 = Vector2(0, 0)


def reference_cell(
    p: Vector2, grid_angle: Float32, step: Float32, scatter: Float32
) -> HalftoneCell:
    """Return the grid square a point is in: `HalftoneShader`'s
    `getReferenceCell`, with the origin at the bottom left.

    Args:
        p: The point, in pixels up from the bottom left.
        grid_angle: The grid's angle, in radians.
        step: The grid's spacing, in pixels.
        scatter: How far the nearest point strays, zero to one.

    Returns:
        The four grid points.
    """
    var cell = HalftoneCell()
    var n = Vector2(cos(grid_angle), sin(grid_angle))
    var threshold = step * 0.5
    var dot_normal = n.x * p.x + n.y * p.y
    var dot_line = -n.y * p.x + n.x * p.y
    var offset = Vector2(n.x * dot_normal, n.y * dot_normal)
    var offset_normal = _glsl_mod(_hypot(offset.x, offset.y), step)
    var normal_dir = Float32(1) if dot_normal < 0 else Float32(-1)
    var normal_scale = (
        -offset_normal if offset_normal < threshold else step - offset_normal
    ) * normal_dir
    var offset_line = _glsl_mod(_hypot(p.x - offset.x, p.y - offset.y), step)
    var line_dir = Float32(1) if dot_line < 0 else Float32(-1)
    var line_scale = (
        -offset_line if offset_line < threshold else step - offset_line
    ) * line_dir
    cell.normal = n
    cell.p1 = Vector2(
        p.x - n.x * normal_scale + n.y * line_scale,
        p.y - n.y * normal_scale - n.x * line_scale,
    )
    if scatter != 0:
        var off_mag = scatter * threshold * 0.5
        var off_angle = (
            sine_hash(floor(cell.p1.x), floor(cell.p1.y)) * HALFTONE_PI2
        )
        cell.p1 = Vector2(
            cell.p1.x + cos(off_angle) * off_mag,
            cell.p1.y + sin(off_angle) * off_mag,
        )
    var normal_step = normal_dir * (
        step if offset_normal < threshold else -step
    )
    var line_step = line_dir * (step if offset_line < threshold else -step)
    cell.p2 = Vector2(
        cell.p1.x - n.x * normal_step, cell.p1.y - n.y * normal_step
    )
    cell.p3 = Vector2(cell.p1.x + n.y * line_step, cell.p1.y - n.x * line_step)
    cell.p4 = Vector2(
        cell.p1.x - n.x * normal_step + n.y * line_step,
        cell.p1.y - n.y * normal_step - n.x * line_step,
    )
    return cell


def halftone_sample(
    colors: List[FloatColor],
    width: Int,
    height: Int,
    point: Vector2,
    radius: Float32,
) -> FloatColor:
    """Return the light around a grid point: `HalftoneShader`'s
    `getSample`, the point and eight taps on a ring about it, averaged.

    Args:
        colors: The frame's pixels, row by row from the top.
        width: The frame's width in pixels.
        height: The frame's height in pixels.
        point: The grid point, in pixels up from the bottom left.
        radius: The grid's spacing; the ring is two thirds of it.

    Returns:
        The average of nine bilinear reads.
    """
    var w = Float32(width)
    var h = Float32(height)
    var tex = sample(colors, width, height, point.x / w, point.y / h)
    var base = sine_hash(floor(point.x), floor(point.y)) * HALFTONE_PI2
    var step = HALFTONE_PI2 / Float32(HALFTONE_SAMPLES)
    var dist = radius * 0.66
    for i in range(HALFTONE_SAMPLES):  # pragma: no branch
        var r = base + step * Float32(i)
        var here = sample(
            colors,
            width,
            height,
            (point.x + cos(r) * dist) / w,
            (point.y + sin(r) * dist) / h,
        )
        tex = FloatColor(
            tex.r + here.r, tex.g + here.g, tex.b + here.b, tex.a + here.a
        )
    var share = 1 / (Float32(HALFTONE_SAMPLES) + 1)
    return FloatColor(
        tex.r * share, tex.g * share, tex.b * share, tex.a * share
    )


def _dot_coverage(distance: Float32, aa: Float32) -> Float32:
    """Return how much of a pixel a dot covers: the shader's
    `dist > 0 ? clamp(dist / aa, 0, 1) : 0`, which is the clamp alone
    because `aa` is positive."""
    return max(Float32(0), min(Float32(1), distance / aa))


def _dot_color(
    samples: SIMD[DType.float32, 4],
    cell: HalftoneCell,
    p: Vector2,
    angle: Float32,
    aa: Float32,
    settings: HalftoneSettings,
) -> Float32:
    """Return one channel's halftone at a point: `getDotColour` once the
    four corners are sampled."""
    var sum = _dot_coverage(
        dot_radius_distance(
            settings.shape,
            samples[0],
            cell.p1,
            cell.normal,
            p,
            angle,
            settings.radius,
        ),
        aa,
    )
    sum += _dot_coverage(
        dot_radius_distance(
            settings.shape,
            samples[1],
            cell.p2,
            cell.normal,
            p,
            angle,
            settings.radius,
        ),
        aa,
    )
    sum += _dot_coverage(
        dot_radius_distance(
            settings.shape,
            samples[2],
            cell.p3,
            cell.normal,
            p,
            angle,
            settings.radius,
        ),
        aa,
    )
    sum += _dot_coverage(
        dot_radius_distance(
            settings.shape,
            samples[3],
            cell.p4,
            cell.normal,
            p,
            angle,
            settings.radius,
        ),
        aa,
    )
    return min(sum, Float32(1))


def _corners(
    colors: List[FloatColor],
    width: Int,
    height: Int,
    cell: HalftoneCell,
    radius: Float32,
) -> List[FloatColor]:
    """Return `halftone_sample` at a cell's four points, in order."""
    return [
        halftone_sample(colors, width, height, cell.p1, radius),
        halftone_sample(colors, width, height, cell.p2, radius),
        halftone_sample(colors, width, height, cell.p3, radius),
        halftone_sample(colors, width, height, cell.p4, radius),
    ]


def halftone_blend(
    a: Float32, b: Float32, t: Float32, mode: HalftoneBlending
) -> Float32:
    """Return a halftone channel mixed with the frame's: `HalftoneShader`'s
    `blendColour`.

    Args:
        a: The halftone's channel.
        b: The frame's channel.
        t: How much of the halftone shows.
        mode: How the two combine.

    Returns:
        The mix. The linear mode moves from the frame at zero to the
        halftone at one. The others move from the halftone at zero toward
        their combination at one, as three.js's do.
    """
    if mode == HALFTONE_LINEAR:
        return a * t + b * (1 - t)
    var other: Float32
    if mode == HALFTONE_ADD:
        other = min(Float32(1), a + b)
    elif mode == HALFTONE_MULTIPLY:
        other = max(Float32(0), a * b)
    elif mode == HALFTONE_LIGHTER:
        other = max(a, b)
    else:
        # `HALFTONE_DARKER`, the only mode left once it is checked.
        other = min(a, b)
    return a * (1 - t) + other * t


def halftone_light(mut frame: RenderTarget, settings: HalftoneSettings):
    """Redraw each channel as a grid of dots: three.js's
    `HalftoneShader`.

    Each channel has a grid at its own angle, `radius` pixels apart. A
    grid point's dot is sized by the light around it, and a pixel takes
    the coverage of the four dots around it, softened over `aa` pixels.
    The result is mixed with the frame by `blending`, grayed if asked,
    and opaque. A disabled pass leaves the frame alone. The taps read the
    stored light.

    Args:
        frame: The frame, changed in place.
        settings: The shape, the grids and the blending.
    """
    if settings.disable:
        return
    var width = frame.width
    var height = frame.height
    var source = frame.colors.copy()
    var radius = settings.radius
    var aa = radius * 0.5 if radius < 2.5 else Float32(1.25)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var slot = y * width + x
            var p = Vector2(
                u_of(x, width) * Float32(width),
                v_of(y, height) * Float32(height),
            )
            var cell_r = reference_cell(
                p, settings.rotate_r.value, radius, settings.scatter
            )
            var cell_g = reference_cell(
                p, settings.rotate_g.value, radius, settings.scatter
            )
            var cell_b = reference_cell(
                p, settings.rotate_b.value, radius, settings.scatter
            )
            var at_r = _corners(source, width, height, cell_r, radius)
            var at_g = _corners(source, width, height, cell_g, radius)
            var at_b = _corners(source, width, height, cell_b, radius)
            var r = _dot_color(
                SIMD[DType.float32, 4](
                    at_r[0].r, at_r[1].r, at_r[2].r, at_r[3].r
                ),
                cell_r,
                p,
                settings.rotate_r.value,
                aa,
                settings,
            )
            var g = _dot_color(
                SIMD[DType.float32, 4](
                    at_g[0].g, at_g[1].g, at_g[2].g, at_g[3].g
                ),
                cell_g,
                p,
                settings.rotate_g.value,
                aa,
                settings,
            )
            var b = _dot_color(
                SIMD[DType.float32, 4](
                    at_b[0].b, at_b[1].b, at_b[2].b, at_b[3].b
                ),
                cell_b,
                p,
                settings.rotate_b.value,
                aa,
                settings,
            )
            var under = source[slot]
            r = halftone_blend(
                r, under.r, settings.blending, settings.blending_mode
            )
            g = halftone_blend(
                g, under.g, settings.blending, settings.blending_mode
            )
            b = halftone_blend(
                b, under.b, settings.blending, settings.blending_mode
            )
            if settings.grayscale:
                var gray = (r + b + g) / 3
                r = gray
                g = gray
                b = gray
            frame.colors[slot] = FloatColor(r, g, b, 1)
            frame.data[slot] = False
            x += 1
        y += 1


# --- mask, clear and texture -------------------------------------------------


struct MaskSettings(ImplicitlyCopyable):
    """What `MaskPass` reads: which objects make the mask, and whether it
    is turned inside out."""

    # The layers whose objects cover the mask. three.js takes a scene.
    var selection: Layers
    # Whether the passes after it change what the objects do not cover:
    # `inverse`.
    var inverse: Bool

    def __init__(out self):
        """Start with no layers, not inverted."""
        self.selection = Layers(UInt32(0))
        self.inverse = False


def mask_stencil(mut frame: RenderTarget, depth: List[Float32], inverse: Bool):
    """Write the mask into the frame's stencil buffer: three.js's
    `MaskPass`, which replaces the stencil with one where the mask's
    objects are drawn and clears it to zero elsewhere, or the other way
    round when inverted. The light and the depth are left alone, as
    `MaskPass` turns off the color and the depth writes.

    Args:
        frame: The frame, whose stencil is replaced.
        depth: The mask's objects drawn alone, one NDC depth per pixel; a
            pixel is covered where the depth is finite.
        inverse: Whether to write zero where covered and one elsewhere.
    """
    var write = 0 if inverse else 1
    var clear = 1 if inverse else 0
    for slot in range(len(frame.stencil)):  # pragma: no branch
        var value = write if isfinite(depth[slot]) else clear
        frame.stencil[slot] = UInt8(
            stencil_apply(REPLACE_STENCIL_OP, 0, value, STENCIL_MAX)
        )


def inside_mask(stored: Int) -> Bool:
    """Return True if a pixel's stencil lets a masked pass change it: the
    test `MaskPass` leaves on, `EQUAL` to one through every bit.

    Args:
        stored: The pixel's stencil value.

    Returns:
        Whether the value is one.
    """
    return stencil_compare(EQUAL_STENCIL_FUNC, 1, stored, STENCIL_MAX)


struct FrameCopy(Movable):
    """What a frame held before a pass inside a mask: the light, the data
    flags, the depth and the stencil, to put back outside the mask."""

    var colors: List[FloatColor]
    var data: List[Bool]
    var depth: List[Float32]
    var stencil: List[UInt8]

    def __init__(out self):
        """Hold nothing: no mask is active."""
        self.colors = List[FloatColor]()
        self.data = List[Bool]()
        self.depth = List[Float32]()
        self.stencil = List[UInt8]()

    def __init__(out self, frame: RenderTarget):
        """Copy what a frame holds.

        Args:
            frame: The frame.
        """
        self.colors = frame.colors.copy()
        self.data = frame.data.copy()
        self.depth = frame.depth.copy()
        self.stencil = frame.stencil.copy()


def keep_outside_mask(mut frame: RenderTarget, saved: FrameCopy):
    """Put back every pixel a masked pass must not change, and the whole
    stencil: what three.js's stencil test and its composer's copy after a
    pass inside a mask do together.

    Args:
        frame: The frame after the pass, changed in place.
        saved: The frame before the pass.
    """
    for slot in range(len(saved.stencil)):  # pragma: no branch
        if not inside_mask(Int(saved.stencil[slot])):
            frame.colors[slot] = saved.colors[slot]
            frame.data[slot] = saved.data[slot]
            frame.depth[slot] = saved.depth[slot]
    frame.stencil = saved.stencil.copy()


def clear_light(mut frame: RenderTarget, color: Color):
    """Clear the frame to a color: three.js's `ClearPass`, which clears
    the color, the depth and the stencil.

    Args:
        frame: The frame, replaced.
        color: The color, in sRGB, with its alpha: three.js's `clearColor`
            and `clearAlpha`.
    """
    var value = FloatColor(srgb=color).premultiplied()
    for slot in range(len(frame.colors)):  # pragma: no branch
        frame.colors[slot] = value
        frame.depth[slot] = inf[DType.float32]()
        frame.data[slot] = False
        frame.stencil[slot] = 0


def texture_light(mut frame: RenderTarget, texture: Texture, opacity: Float32):
    """Add a texture over the frame: three.js's `TexturePass`, which draws
    `CopyShader` with additive blending.

    Every channel of the texture at each pixel's center, alpha included,
    is scaled by the opacity and added to the frame. The result holds
    light.

    Args:
        frame: The frame, changed in place.
        texture: The image, sampled through its own wrap and filter.
        opacity: What the texture is scaled by.
    """
    var width = frame.width
    var height = frame.height
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var slot = y * width + x
            var texel = texture.sample(u_of(x, width), v_of(y, height))
            var base = frame.colors[slot]
            frame.colors[slot] = FloatColor(
                base.r + texel.r * opacity,
                base.g + texel.g * opacity,
                base.b + texel.b * opacity,
                base.a + texel.a * opacity,
            )
            frame.data[slot] = False
            x += 1
        y += 1
