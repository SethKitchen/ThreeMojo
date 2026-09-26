# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""More passes: three.js's `BokehPass`, `GlitchPass`, `HalftonePass`,
`MaskPass`, `ClearMaskPass`, `ClearPass`, `TexturePass` and `LUTPass`.

**Bokeh** blurs each pixel by how far its depth is from the focus, with
the 41 taps of three.js's `BokehShader`. **Glitch** shifts the channels
apart, tears rows and columns and adds snow, at random moments, as
`DigitalGlitch` does. **Halftone** redraws each channel as a grid of dots,
lines or squares, as `HalftoneShader` does. **LUT** looks each pixel's
color up in a `Data3DTexture`, as `LUTPass` does.

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

The passes run on the host. Each one's arithmetic for one pixel is a
function of its own, `bokeh_pixel`, `glitch_pixel`, `halftone_pixel`,
`texture_pixel` and `lut_pixel`, which the GPU backend's kernels call as
well; see `render.gpu.GpuComposer`.
"""

from core.layers import Layers
from math.arc_tangent import atan2_float32
from math.sine import fraction, noise_scale, sin_float32
from math.utils import SeededRandom
from math.vector2 import Vector2
from math.vector3 import Vector3
from postprocessing.screen_space import DepthView, glsl_rand
from postprocessing.sampling import LightView, Untracked, u_of, v_of
from render.framebuffer import Color, FloatColor
from render.raster_state import (
    EQUAL_STENCIL_FUNC,
    REPLACE_STENCIL_OP,
    STENCIL_MAX,
    cleared_depth,
    stencil_apply,
    stencil_compare,
)
from render.srgb import linear_to_srgb, srgb_to_linear
from render.target import RenderTarget
from render.texture import Texture
from render.volume_texture import Data3DTexture, VolumeSampler
from std.math import cos, floor, fma, isfinite, pi, sin, sqrt
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


# `BokehShader`'s rings, before each is scaled: sixteen taps at the full
# blur, eight at nine tenths, and eight read at seven tenths and again at
# four tenths.
comptime _BOKEH_FULL_X = SIMD[DType.float32, 16](
    0.0,
    0.15,
    0.29,
    -0.37,
    0.4,
    0.37,
    0.29,
    -0.15,
    0.0,
    -0.15,
    -0.29,
    0.37,
    -0.4,
    -0.37,
    -0.29,
    0.15,
)
comptime _BOKEH_FULL_Y = SIMD[DType.float32, 16](
    0.4,
    0.37,
    0.29,
    0.15,
    0.0,
    -0.15,
    -0.29,
    -0.37,
    -0.4,
    0.37,
    0.29,
    0.15,
    0.0,
    -0.15,
    -0.29,
    -0.37,
)
comptime _BOKEH_NINE_X = SIMD[DType.float32, 8](
    0.15, -0.37, 0.37, -0.15, -0.15, 0.37, -0.37, 0.15
)
comptime _BOKEH_NINE_Y = SIMD[DType.float32, 8](
    0.37, 0.15, -0.15, -0.37, 0.37, 0.15, -0.15, -0.37
)
comptime _BOKEH_INNER_X = SIMD[DType.float32, 8](
    0.29, 0.4, 0.29, 0.0, -0.29, -0.4, -0.29, 0.0
)
comptime _BOKEH_INNER_Y = SIMD[DType.float32, 8](
    0.29, 0.0, -0.29, -0.4, 0.29, 0.0, -0.29, 0.4
)


def bokeh_tap(index: Int) -> Vector2:
    """Return one of the 41 offsets `BokehShader` reads, already scaled by
    its ring: the center, 16 at the full blur, 8 at nine tenths, 8 at
    seven tenths and 8 at four tenths.

    A function rather than a list, so a GPU kernel reads the same numbers
    the host does without a buffer to carry them.

    Args:
        index: Which tap, zero through 40.

    Returns:
        The offset, in units of the blur.
    """
    if index < 1:
        return Vector2(0, 0)
    if index < 17:
        return Vector2(_BOKEH_FULL_X[index - 1], _BOKEH_FULL_Y[index - 1])
    if index < 25:
        return Vector2(
            _BOKEH_NINE_X[index - 17] * 0.9, _BOKEH_NINE_Y[index - 17] * 0.9
        )
    if index < 33:
        return Vector2(
            _BOKEH_INNER_X[index - 25] * 0.7, _BOKEH_INNER_Y[index - 25] * 0.7
        )
    return Vector2(
        _BOKEH_INNER_X[index - 33] * 0.4, _BOKEH_INNER_Y[index - 33] * 0.4
    )


def bokeh_taps() -> List[Vector2]:
    """Return the 41 offsets `BokehShader` reads: `bokeh_tap` in order.

    Returns:
        The offsets, in units of the blur.
    """
    var taps = List[Vector2](capacity=BOKEH_TAPS)
    for index in range(BOKEH_TAPS):  # pragma: no branch
        taps.append(bokeh_tap(index))
    return taps^


def bokeh_reach(
    near: Length,
    far: Length,
    depth: Float32,
    focus: Length,
    aperture: Float32,
    max_blur: Float32,
) -> Float32:
    """Return how far a pixel's taps reach: `BokehShader`'s `dofblur`,
    from values a GPU kernel can hold.

    Args:
        near: The camera's near distance.
        far: The camera's far distance.
        depth: The pixel's window depth.
        focus: The distance in focus.
        aperture: How fast the blur grows away from the focus, in texture
            widths per meter.
        max_blur: The most blur, in texture widths.

    Returns:
        The reach, in texture widths, negative in front of the focus.
    """
    var n = near.value
    var f = far.value
    var z = (n * f) / ((f - n) * depth - f)
    var factor = (focus.value + z) * aperture
    return max(-max_blur, min(max_blur, factor))


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
    return bokeh_reach(
        Length(view.near, METER),
        Length(view.far, METER),
        depth,
        settings.focus,
        settings.aperture,
        settings.max_blur,
    )


def bokeh_pixel(source: LightView, x: Int, y: Int, blur: Float32) -> FloatColor:
    """Return one pixel of `BokehShader`: the average of its 41 taps, the
    vertical offsets scaled by the frame's aspect.

    Args:
        source: The frame before the pass.
        x: The column.
        y: The row, down from the top.
        blur: The pixel's reach, from `bokeh_reach`.

    Returns:
        The blurred light, opaque.
    """
    var u = u_of(x, source.width)
    var v = v_of(y, source.height)
    var aspect = Float32(source.width) / Float32(source.height)
    var sum = FloatColor(0, 0, 0, 0)
    var index = 0
    while index < BOKEH_TAPS:
        var tap = bokeh_tap(index)
        index += 1
        var here = source.sample(u + tap.x * blur, v + tap.y * aspect * blur)
        sum = FloatColor(sum.r + here.r, sum.g + here.g, sum.b + here.b, 0)
    var share = 1 / Float32(BOKEH_TAPS)
    return FloatColor(sum.r * share, sum.g * share, sum.b * share, 1)


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
    var light = LightView(source, width, height)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var slot = y * width + x
            frame.colors[slot] = bokeh_pixel(
                light, x, y, bokeh_blur(view, view.depth[slot], settings)
            )
            frame.data[slot] = False
            x += 1
        y += 1
    # The view does not keep the copy alive; this does.
    _ = source^


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

    The sine is `math.sine.sin_float32`, and the dot and the scale each
    round once, so the host and a kernel give the same noise.

    Args:
        u: The first coordinate.
        v: The second.

    Returns:
        A number from zero up to one.
    """
    var dot = fma(u, Float32(12.9898), v * Float32(78.233))
    return fraction(noise_scale(sin_float32(dot)))


def nearest_texel(
    values: Pointer[Float32, Untracked], size: Int, u: Float32, v: Float32
) -> Float32:
    """Return a square map's texel at a texture coordinate, as a
    `DataTexture` with `NearestFilter` and `ClampToEdgeWrapping` reads it.

    Args:
        values: The map, `size` squared values, the rows running up from
            the bottom. The memory must outlive the call.
        size: Texels a side.
        u: Across, zero to one.
        v: Up, zero to one.

    Returns:
        The texel.
    """
    var top = Float32(size - 1)
    var column = Int(max(Float32(0), min(top, floor(u * Float32(size)))))
    var row = Int(max(Float32(0), min(top, floor(v * Float32(size)))))
    return values[unsafe_offset=row * size + column]


def glitch_pixel(
    source: LightView,
    heightmap: Pointer[Float32, Untracked],
    size: Int,
    uniforms: GlitchUniforms,
    shift_x: Float32,
    shift_y: Float32,
    x: Int,
    y: Int,
) -> FloatColor:
    """Return one pixel of three.js's `DigitalGlitch`, not bypassed.

    The host takes the shift's cosine and sine once a frame, so both
    backends read the same two numbers.

    Args:
        source: The frame before the pass.
        heightmap: The displacement map, `size` squared values.
        size: The map's texels a side.
        uniforms: The frame's uniforms.
        shift_x: How far the channels shift across: the amount times the
            cosine of the angle.
        shift_y: How far they shift up: the amount times the sine.
        x: The column.
        y: The row, down from the top.

    Returns:
        The torn, shifted and snowed light.
    """
    var width = source.width
    var height = source.height
    var seed = uniforms.seed
    var u = u_of(x, width)
    var v = v_of(y, height)
    # `gl_FragCoord` counts up from the bottom left, at centers.
    var xs = floor((Float32(x) + 0.5) / 0.5)
    var ys = floor((Float32(height - 1 - y) + 0.5) / 0.5)
    var disp = nearest_texel(heightmap, size, u * seed * seed, v * seed * seed)
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
    var red = source.sample(px + shift_x, py + shift_y)
    var middle = source.sample(px, py)
    var blue = source.sample(px - shift_x, py - shift_y)
    var snow = (
        200 * uniforms.amount * sine_hash(xs * seed, ys * seed * 50) * 0.2
    )
    return FloatColor(
        red.r + snow, middle.g + snow, blue.b + snow, middle.a + snow
    )


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
    var light = LightView(source, width, height)
    var map = heightmap.unsafe_ptr().unsafe_origin_cast[Untracked]()
    var shift_x = uniforms.amount * cos(uniforms.angle.value)
    var shift_y = uniforms.amount * sin(uniforms.angle.value)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            frame.colors[y * width + x] = glitch_pixel(
                light, map, size, uniforms, shift_x, shift_y, x, y
            )
            x += 1
        y += 1
    # The views do not keep the copy alive; this does.
    _ = source^


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
    # The size the grid is laid over, in pixels: the shader's `width` and
    # `height`, which `HalftonePass.setSize` sets. Zero, the default,
    # takes the frame's own size, as the composer's `setSize` gives it.
    var width: Float32
    var height: Float32

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
        self.width = 0
        self.height = 0

    def set_size(mut self, width: Float32, height: Float32):
        """Lay the grid over another size than the frame's, three.js's
        `HalftonePass.setSize`.

        Args:
            width: The width, in pixels; zero for the frame's.
            height: The height, in pixels; zero for the frame's.
        """
        self.width = width
        self.height = height


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
        and isfinite(settings.width)
        and isfinite(settings.height)
    ):
        raise Error("A halftone setting must be finite")
    if settings.width < 0 or settings.height < 0:
        raise Error("A halftone size must not be negative")
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
        var theta = atan2_float32(p.y - coord.y, p.x - coord.x) - angle
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
    source: LightView,
    point: Vector2,
    radius: Float32,
    width: Float32 = 0,
    height: Float32 = 0,
) -> FloatColor:
    """Return the light around a grid point: `HalftoneShader`'s
    `getSample`, the point and eight taps on a ring about it, averaged.

    Args:
        source: The frame, row by row from the top.
        point: The grid point, in pixels up from the bottom left.
        radius: The grid's spacing; the ring is two thirds of it.
        width: The size the grid is laid over, the shader's `width`; zero
            for the frame's.
        height: Its `height`; zero for the frame's.

    Returns:
        The average of nine bilinear reads.
    """
    var w = width if width > 0 else Float32(source.width)
    var h = height if height > 0 else Float32(source.height)
    var tex = source.sample(point.x / w, point.y / h)
    var base = sine_hash(floor(point.x), floor(point.y)) * HALFTONE_PI2
    var step = HALFTONE_PI2 / Float32(HALFTONE_SAMPLES)
    var dist = radius * 0.66
    var i = 0
    while i < HALFTONE_SAMPLES:
        var r = base + step * Float32(i)
        var here = source.sample(
            (point.x + cos(r) * dist) / w, (point.y + sin(r) * dist) / h
        )
        tex = FloatColor(
            tex.r + here.r, tex.g + here.g, tex.b + here.b, tex.a + here.a
        )
        i += 1
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


struct _Corners(ImplicitlyCopyable):
    """One channel of `halftone_sample` at a cell's four points, in order:
    red, green or blue, whichever the cell is for."""

    var r: SIMD[DType.float32, 4]
    var g: SIMD[DType.float32, 4]
    var b: SIMD[DType.float32, 4]

    def __init__(
        out self, a: FloatColor, b: FloatColor, c: FloatColor, d: FloatColor
    ):
        """Gather the four samples by channel."""
        self.r = SIMD[DType.float32, 4](a.r, b.r, c.r, d.r)
        self.g = SIMD[DType.float32, 4](a.g, b.g, c.g, d.g)
        self.b = SIMD[DType.float32, 4](a.b, b.b, c.b, d.b)


def _corners(
    source: LightView,
    cell: HalftoneCell,
    radius: Float32,
    width: Float32,
    height: Float32,
) -> _Corners:
    """Return `halftone_sample` at a cell's four points, by channel."""
    return _Corners(
        halftone_sample(source, cell.p1, radius, width, height),
        halftone_sample(source, cell.p2, radius, width, height),
        halftone_sample(source, cell.p3, radius, width, height),
        halftone_sample(source, cell.p4, radius, width, height),
    )


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


def halftone_pixel(
    source: LightView, x: Int, y: Int, settings: HalftoneSettings
) -> FloatColor:
    """Return one pixel of three.js's `HalftoneShader`, not disabled.

    Args:
        source: The frame before the pass.
        x: The column.
        y: The row, down from the top.
        settings: The shape, the grids and the blending.

    Returns:
        The halftone, opaque.
    """
    var width = source.width
    var height = source.height
    var size_x = settings.width if settings.width > 0 else Float32(width)
    var size_y = settings.height if settings.height > 0 else Float32(height)
    var radius = settings.radius
    var aa = radius * 0.5 if radius < 2.5 else Float32(1.25)
    var p = Vector2(u_of(x, width) * size_x, v_of(y, height) * size_y)
    var cell_r = reference_cell(
        p, settings.rotate_r.value, radius, settings.scatter
    )
    var cell_g = reference_cell(
        p, settings.rotate_g.value, radius, settings.scatter
    )
    var cell_b = reference_cell(
        p, settings.rotate_b.value, radius, settings.scatter
    )
    var at_r = _corners(source, cell_r, radius, size_x, size_y)
    var at_g = _corners(source, cell_g, radius, size_x, size_y)
    var at_b = _corners(source, cell_b, radius, size_x, size_y)
    var r = _dot_color(at_r.r, cell_r, p, settings.rotate_r.value, aa, settings)
    var g = _dot_color(at_g.g, cell_g, p, settings.rotate_g.value, aa, settings)
    var b = _dot_color(at_b.b, cell_b, p, settings.rotate_b.value, aa, settings)
    var under = source.at(x, y)
    r = halftone_blend(r, under.r, settings.blending, settings.blending_mode)
    g = halftone_blend(g, under.g, settings.blending, settings.blending_mode)
    b = halftone_blend(b, under.b, settings.blending, settings.blending_mode)
    if settings.grayscale:
        var gray = (r + b + g) / 3
        r = gray
        g = gray
        b = gray
    return FloatColor(r, g, b, 1)


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
    var light = LightView(source, width, height)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var slot = y * width + x
            frame.colors[slot] = halftone_pixel(light, x, y, settings)
            frame.data[slot] = False
            x += 1
        y += 1
    # The view does not keep the copy alive; this does.
    _ = source^


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


def mask_stencil(
    mut frame: RenderTarget,
    depth: List[Float32],
    inverse: Bool,
    clear: Bool = True,
):
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
        clear: Whether the stencil is cleared first, three.js's `clear`.
            Not cleared, a pixel the objects do not cover keeps its
            stencil, so a mask adds to the one before it.
    """
    var write = 0 if inverse else 1
    var cleared = 1 if inverse else 0
    for slot in range(len(frame.stencil)):  # pragma: no branch
        var covered = isfinite(depth[slot])
        if not covered and not clear:
            continue
        var value = write if covered else cleared
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
    the color, the depth and the stencil. The depth is cleared in the
    frame's own depth mode.

    Args:
        frame: The frame, replaced.
        color: The color, in sRGB, with its alpha: three.js's `clearColor`
            and `clearAlpha`.
    """
    var value = FloatColor(srgb=color).premultiplied()
    for slot in range(len(frame.colors)):  # pragma: no branch
        frame.colors[slot] = value
        frame.depth[slot] = cleared_depth(frame.depth_mode)
        frame.data[slot] = False
        frame.stencil[slot] = 0


def texture_overlay(
    texture: Texture, width: Int, height: Int
) -> List[FloatColor]:
    """Return a texture sampled at the center of every pixel of a frame,
    through its own wrap and filter: what a texture pass adds.

    The texels do not depend on the frame, so the GPU backend samples
    them here, on the host, and adds them on the device.

    Args:
        texture: The image.
        width: The frame's width in pixels.
        height: The frame's height in pixels.

    Returns:
        One texel per pixel, row by row from the top.
    """
    var texels = List[FloatColor](capacity=width * height)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            texels.append(texture.sample(u_of(x, width), v_of(y, height)))
            x += 1
        y += 1
    return texels^


def texture_pixel(
    base: FloatColor, texel: FloatColor, opacity: Float32
) -> FloatColor:
    """Return one pixel of three.js's `TexturePass`: the texel scaled by
    the opacity, drawn over the pixel.

    three.js draws `CopyShader`, `opacity * texel`, with
    `premultipliedAlpha` set, and makes the material transparent only
    below an opacity of one. Below one it blends premultiplied over, so
    the pixel keeps one minus the scaled texel's alpha of what it held.
    At one or more there is no blending, and the scaled texel replaces
    the pixel.

    Args:
        base: The pixel's light, premultiplied.
        texel: The texture at the pixel's center, read as premultiplied,
            as three.js's blend reads it.
        opacity: What the texture is scaled by.

    Returns:
        The blended light, premultiplied.
    """
    var drawn = FloatColor(
        texel.r * opacity,
        texel.g * opacity,
        texel.b * opacity,
        texel.a * opacity,
    )
    if opacity >= 1:
        return drawn
    var keep = 1 - drawn.a
    return FloatColor(
        drawn.r + base.r * keep,
        drawn.g + base.g * keep,
        drawn.b + base.b * keep,
        drawn.a + base.a * keep,
    )


def texture_light(mut frame: RenderTarget, texture: Texture, opacity: Float32):
    """Draw a texture over the frame: three.js's `TexturePass`, which
    draws `CopyShader` with premultiplied normal blending.

    Every channel of the texture at each pixel's center, alpha included,
    is scaled by the opacity and drawn over the frame; see
    `texture_pixel`. The result holds light.

    Args:
        frame: The frame, changed in place.
        texture: The image, sampled through its own wrap and filter.
        opacity: What the texture is scaled by.
    """
    var texels = texture_overlay(texture, frame.width, frame.height)
    for slot in range(len(frame.colors)):  # pragma: no branch
        frame.colors[slot] = texture_pixel(
            frame.colors[slot], texels[slot], opacity
        )
        frame.data[slot] = False


# --- lut --------------------------------------------------------------------


def _encoded(color: FloatColor) -> FloatColor:
    """Return a straight color with its three channels sRGB-encoded."""
    return FloatColor(
        linear_to_srgb(color.r),
        linear_to_srgb(color.g),
        linear_to_srgb(color.b),
        color.a,
    )


def _decoded(color: FloatColor) -> FloatColor:
    """Return a straight color with its three channels sRGB-decoded."""
    return FloatColor(
        srgb_to_linear(color.r),
        srgb_to_linear(color.g),
        srgb_to_linear(color.b),
        color.a,
    )


def lut_color[
    T: VolumeSampler
](color: FloatColor, lut: T, intensity: Float32) -> FloatColor:
    """Return one straight, sRGB-encoded color looked up in a table:
    three.js's `LUTShader`.

    The color is pulled in by half a texel, so zero and one land on the
    centers of the edge texels, and read from the table as a coordinate:
    red across, green up, blue deep. The lookup's color replaces the
    color by `intensity`, and alpha is kept.

    Args:
        color: The color, encoded as the table expects it.
        lut: The table: a `Data3DTexture` on the host, a `DecodedVolume`
            on the GPU. Its size is its width, as three.js's `lutSize` is.
        intensity: How far toward the lookup, one replacing the color.

    Returns:
        The graded color, still encoded.
    """
    var size = Float32(lut.volume_width())
    var pixel_width = 1 / size
    var half_pixel_width = Float32(0.5) / size
    var looked = lut.sample(
        half_pixel_width + color.r * (1 - pixel_width),
        half_pixel_width + color.g * (1 - pixel_width),
        half_pixel_width + color.b * (1 - pixel_width),
    )
    return FloatColor(
        color.r + (looked.r - color.r) * intensity,
        color.g + (looked.g - color.g) * intensity,
        color.b + (looked.b - color.b) * intensity,
        color.a,
    )


def lut_pixel[
    T: VolumeSampler
](color: FloatColor, lut: T, intensity: Float32) -> FloatColor:
    """Return one pixel of three.js's `LUTPass`: the light encoded, looked
    up by `lut_color`, and decoded again.

    Args:
        color: The pixel's light, premultiplied.
        lut: The table.
        intensity: How far toward the lookup, one replacing the color.

    Returns:
        The graded light, premultiplied.
    """
    var base = _encoded(color.unpremultiplied())
    return _decoded(lut_color(base, lut, intensity)).premultiplied()


def lut_light(
    mut frame: RenderTarget, lut: Data3DTexture, intensity: Float32
) raises:
    """Grade the frame through a color lookup table: three.js's `LUTPass`.

    three.js's examples put the `LUTPass` after the `OutputPass`, so the
    shader reads sRGB-encoded color, and a `.cube` table is built for it.
    This frame holds linear light until `resolve` encodes it. So each
    pixel is encoded, looked up by `lut_color`, and decoded again, and the
    encode at the end gives the numbers three.js's shader wrote.

    Args:
        frame: The frame, changed in place.
        lut: The table.
        intensity: How far toward the lookup, one replacing the color.

    Raises:
        Error: Everything `Data3DTexture.validate` raises.
    """
    lut.validate()
    for index in range(len(frame.colors)):  # pragma: no branch
        frame.colors[index] = lut_pixel(frame.colors[index], lut, intensity)


# --- DOFMipMapShader ---------------------------------------------------------


@fieldwise_init
struct DofMipMapSettings(ImplicitlyCopyable):
    """What three.js's `DOFMipMapShader` reads: `focus`, the window depth
    that stays sharp, and `maxblur`, how many mip levels a unit of depth
    away from it blurs by, halved. Both one by default, as in three.js."""

    var focus: Float32
    var max_blur: Float32

    def __init__(out self):
        """Return three.js's defaults."""
        self.focus = 1.0
        self.max_blur = 1.0


def check_dof_mipmap(settings: DofMipMapSettings) raises:
    """Refuse settings the shader could not run.

    Args:
        settings: The settings.

    Raises:
        Error: If either is not finite, or `maxblur` is negative.
    """
    if not (isfinite(settings.focus) and isfinite(settings.max_blur)):
        raise Error("A mip map depth of field's settings must be finite")
    if settings.max_blur < 0:
        raise Error("A mip map depth of field's blur must not be negative")


def frame_mips(
    colors: List[FloatColor], width: Int, height: Int
) -> List[List[FloatColor]]:
    """Return a frame's mip chain, as `generateMipmap` builds it: each level
    half the last, floored, down to one pixel, every pixel the mean of the
    two by two it covers, held at the last row and column.

    Args:
        colors: The frame, premultiplied.
        width: Its width.
        height: Its height.

    Returns:
        The levels, the frame itself first.
    """
    var levels = List[List[FloatColor]]()
    levels.append(colors.copy())
    var w = width
    var h = height
    while w > 1 or h > 1:
        var next_w = max(w // 2, 1)
        var next_h = max(h // 2, 1)
        ref above = levels[len(levels) - 1]
        var level = List[FloatColor](capacity=next_w * next_h)
        for y in range(next_h):  # pragma: no branch
            for x in range(next_w):  # pragma: no branch
                var x0 = min(x * 2, w - 1)
                var x1 = min(x * 2 + 1, w - 1)
                var y0 = min(y * 2, h - 1)
                var y1 = min(y * 2 + 1, h - 1)
                var a = above[y0 * w + x0]
                var b = above[y0 * w + x1]
                var c = above[y1 * w + x0]
                var d = above[y1 * w + x1]
                level.append(
                    FloatColor(
                        (a.r + b.r + c.r + d.r) / 4,
                        (a.g + b.g + c.g + d.g) / 4,
                        (a.b + b.b + c.b + d.b) / 4,
                        (a.a + b.a + c.a + d.a) / 4,
                    )
                )
        levels.append(level^)
        w = next_w
        h = next_h
    return levels^


def mip_sample(
    levels: List[List[FloatColor]],
    width: Int,
    height: Int,
    u: Float32,
    v: Float32,
    level: Float32,
) -> FloatColor:
    """Return a trilinear read of a mip chain: bilinear on the two levels
    around `level`, mixed, as `LINEAR_MIPMAP_LINEAR` reads a texture.

    Args:
        levels: The chain, `frame_mips`.
        width: The first level's width.
        height: Its height.
        u: Across, zero to one.
        v: Up, zero to one.
        level: Which level, fractional; held between the first and the
            last.

    Returns:
        The light there.
    """
    var last = Float32(len(levels) - 1)
    var at = max(Float32(0), min(level, last))
    var low = Int(floor(at))
    var high = min(low + 1, len(levels) - 1)
    var t = at - Float32(low)
    var low_w = max(width >> low, 1)
    var low_h = max(height >> low, 1)
    var high_w = max(width >> high, 1)
    var high_h = max(height >> high, 1)
    var a = LightView(levels[low], low_w, low_h).sample(u, v)
    var b = LightView(levels[high], high_w, high_h).sample(u, v)
    return FloatColor(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t,
        a.a + (b.a - a.a) * t,
    )


def dof_mipmap_light(
    mut frame: RenderTarget, depth: DepthView, settings: DofMipMapSettings
):
    """Blur each pixel by how far its depth is from the focus: three.js's
    `DOFMipMapShader`, which reads the frame at a mip level of
    `2 * maxblur * abs(focus - depth)`.

    The shader writes the texel's color with an alpha of one; the frame
    holds premultiplied light, so the texel is unpremultiplied first.

    Args:
        frame: The frame, changed in place.
        depth: The scene's depth, as `depth_view` draws it.
        settings: The focus and the blur.
    """
    var levels = frame_mips(frame.colors, frame.width, frame.height)
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var u = u_of(x, frame.width)
            var v = v_of(y, frame.height)
            var z = depth.depth_at(u, v)
            var level = 2 * settings.max_blur * abs(settings.focus - z)
            var color = mip_sample(
                levels, frame.width, frame.height, u, v, level
            ).unpremultiplied()
            frame.colors[y * frame.width + x] = FloatColor(
                color.r, color.g, color.b, 1
            )


# --- BokehShader2 ------------------------------------------------------------

# `BokehShader2`'s fixed numbers, as the shader spells them.
comptime _NDOF_START = Float32(1.0)
comptime _NDOF_DIST = Float32(2.0)
comptime _FDOF_START = Float32(1.0)
comptime _FDOF_DIST = Float32(3.0)
comptime _COC = Float32(0.03)
comptime _VIGN_OUT = Float32(1.3)
comptime _VIGN_IN = Float32(0.0)
comptime _VIGN_FADE = Float32(22.0)
comptime _DB_SIZE = Float32(1.25)
comptime _FEATHER = Float32(0.4)


struct Bokeh2Settings(ImplicitlyCopyable):
    """What three.js's `BokehShader2` reads: its uniforms, named as three.js
    names them, with its defaults, and its `RINGS` and `SAMPLES` defines,
    three and four as three.js's depth of field example sets them.

    `texture_width` and `texture_height` of zero read the frame's own
    size. three.js starts them at one and has the caller set them.
    """

    var texture_width: Float32
    var texture_height: Float32
    # The focal plane's distance in meters, read when `shader_focus` is
    # off, and the lens's focal length in millimeters and f-stop.
    var focal_depth: Float32
    var focal_length: Float32
    var fstop: Float32
    var max_blur: Float32
    var show_focus: Bool
    var manual_dof: Bool
    var vignetting: Bool
    var depth_blur: Bool
    # The highlight threshold and gain, the edge bias and the fringe.
    var threshold: Float32
    var gain: Float32
    var bias: Float32
    var fringe: Float32
    # The camera's near and far planes, in meters.
    var znear: Float32
    var zfar: Float32
    var dithering: Float32
    var pentagon: Bool
    # Whether the focal plane is the depth at `focus_u`, `focus_v`.
    var shader_focus: Bool
    var focus_u: Float32
    var focus_v: Float32
    var rings: Int
    var samples: Int

    def __init__(out self):
        """Return three.js's defaults."""
        self.texture_width = 0
        self.texture_height = 0
        self.focal_depth = 1.0
        self.focal_length = 24.0
        self.fstop = 0.9
        self.max_blur = 1.0
        self.show_focus = False
        self.manual_dof = False
        self.vignetting = False
        self.depth_blur = False
        self.threshold = 0.5
        self.gain = 2.0
        self.bias = 0.5
        self.fringe = 0.7
        self.znear = 0.1
        self.zfar = 100
        self.dithering = 0.0001
        self.pentagon = False
        self.shader_focus = True
        self.focus_u = 0
        self.focus_v = 0
        self.rings = 3
        self.samples = 4


def check_bokeh2(settings: Bokeh2Settings) raises:
    """Refuse settings the shader could not run.

    Args:
        settings: The settings.

    Raises:
        Error: If a number is not finite; a texture size is negative; the
            near plane is not in front of the far one; or there are fewer
            than one ring or one sample.
    """
    var finite = (
        isfinite(settings.texture_width)
        and isfinite(settings.texture_height)
        and isfinite(settings.focal_depth)
        and isfinite(settings.focal_length)
        and isfinite(settings.fstop)
        and isfinite(settings.max_blur)
        and isfinite(settings.threshold)
        and isfinite(settings.gain)
        and isfinite(settings.bias)
        and isfinite(settings.fringe)
        and isfinite(settings.znear)
        and isfinite(settings.zfar)
        and isfinite(settings.dithering)
        and isfinite(settings.focus_u)
        and isfinite(settings.focus_v)
    )
    if not finite:
        raise Error("A bokeh 2 setting must be finite")
    if settings.texture_width < 0 or settings.texture_height < 0:
        raise Error("A bokeh 2 texture size must not be negative")
    if not (settings.znear > 0 and settings.zfar > settings.znear):
        raise Error("A bokeh 2 near plane must lie in front of its far plane")
    if settings.rings < 1 or settings.samples < 1:
        raise Error("A bokeh 2 needs a ring and a sample at least")


def _smoothstep(edge0: Float32, edge1: Float32, x: Float32) -> Float32:
    """Return GLSL's `smoothstep`, its edges in either order."""
    var t = min(max((x - edge0) / (edge1 - edge0), Float32(0)), Float32(1))
    return t * t * (3 - 2 * t)


def bokeh2_penta(pw: Float32, ph: Float32, rings: Int) -> Float32:
    """Return `BokehShader2`'s `penta`: how far a tap lies inside a
    pentagon, feathered, zero to one.

    Args:
        pw: The tap's offset across, in rings.
        ph: Its offset up.
        rings: How many rings there are.

    Returns:
        The shape's weight for the tap.
    """
    var scale = Float32(rings) - 1.3
    var inorout = Float32(-4)
    inorout += _smoothstep(-_FEATHER, _FEATHER, pw + scale)
    inorout += _smoothstep(
        -_FEATHER, _FEATHER, 0.309016994 * pw + 0.951056516 * ph + scale
    )
    inorout += _smoothstep(
        -_FEATHER, _FEATHER, -0.809016994 * pw + 0.587785252 * ph + scale
    )
    inorout += _smoothstep(
        -_FEATHER, _FEATHER, -0.809016994 * pw - 0.587785252 * ph + scale
    )
    inorout += _smoothstep(
        -_FEATHER, _FEATHER, 0.309016994 * pw - 0.951056516 * ph + scale
    )
    return min(max(inorout, Float32(0)), Float32(1))


def _linearize(depth: Float32, znear: Float32, zfar: Float32) -> Float32:
    """Return `BokehShader2`'s `linearize`: a window depth as meters."""
    return -zfar * znear / (depth * (zfar - znear) - zfar)


def _bdepth(
    depth: DepthView, u: Float32, v: Float32, tw: Float32, th: Float32
) -> Float32:
    """Return `BokehShader2`'s `bdepth`: the depth blurred by a three by
    three tent. The shader spells its third offset `vec2( wh.x -wh.y )`,
    which puts the difference in both lanes, and so does this."""
    var wx = 1 / tw * _DB_SIZE
    var wy = 1 / th * _DB_SIZE
    var dx: List[Float32] = [-wx, 0, wx - wy, -wx, 0, wx, -wx, 0, wx]
    var dy: List[Float32] = [-wy, -wy, wx - wy, 0, 0, 0, wy, wy, wy]
    var kernel: List[Float32] = [1, 2, 1, 2, 4, 2, 1, 2, 1]
    var d = Float32(0)
    for i in range(9):  # pragma: no branch
        d += depth.depth_at(u + dx[i], v + dy[i]) * kernel[i] / 16
    return d


def _bokeh2_color(
    source: LightView,
    u: Float32,
    v: Float32,
    blur: Float32,
    settings: Bokeh2Settings,
    tw: Float32,
    th: Float32,
) -> Vector3:
    """Return `BokehShader2`'s `color`: a tap fringed by the blur, its
    highlights raised."""
    var fx = 1 / tw * settings.fringe * blur
    var fy = 1 / th * settings.fringe * blur
    var r = source.sample(u, v + fy).r
    var g = source.sample(u - 0.866 * fx, v - 0.5 * fy).g
    var b = source.sample(u + 0.866 * fx, v - 0.5 * fy).b
    var lum = r * 0.299 + g * 0.587 + b * 0.114
    var thresh = max((lum - settings.threshold) * settings.gain, Float32(0))
    var lift = thresh * blur
    return Vector3(r + r * lift, g + g * lift, b + b * lift)


def bokeh2_pixel(
    source: LightView,
    depth: DepthView,
    x: Int,
    y: Int,
    settings: Bokeh2Settings,
) -> FloatColor:
    """Return one pixel of three.js's `BokehShader2`.

    Args:
        source: The frame, premultiplied.
        depth: The scene's depth, as `depth_view` draws it.
        x: The column.
        y: The row, down from the top.
        settings: The uniforms and the ring and sample counts.

    Returns:
        The pixel, opaque.
    """
    var tw = settings.texture_width
    var th = settings.texture_height
    if tw == 0:
        tw = Float32(source.width)
    if th == 0:
        th = Float32(source.height)
    var u = u_of(x, source.width)
    var v = v_of(y, source.height)
    var z = _linearize(depth.depth_at(u, v), settings.znear, settings.zfar)
    if settings.depth_blur:
        z = _linearize(
            _bdepth(depth, u, v, tw, th), settings.znear, settings.zfar
        )
    var f_depth = settings.focal_depth
    if settings.shader_focus:
        f_depth = _linearize(
            depth.depth_at(settings.focus_u, settings.focus_v),
            settings.znear,
            settings.zfar,
        )
    var blur: Float32
    if settings.manual_dof:
        var a = z - f_depth
        var far = (a - _FDOF_START) / _FDOF_DIST
        var near = (-a - _NDOF_START) / _NDOF_DIST
        blur = far if a > 0 else near
    else:
        var f = settings.focal_length
        var d = f_depth * 1000
        var o = z * 1000
        var a = (o * f) / (o - f)
        var b = (d * f) / (d - f)
        var c = (d - f) / (d * settings.fstop * _COC)
        blur = abs(a - b) * c
    blur = min(max(blur, Float32(0)), Float32(1))
    var noise_x = glsl_rand(u, v) * settings.dithering * blur
    var noise_y = glsl_rand(u + 0.4, v + 0.6) * settings.dithering * blur
    var w = 1 / tw * blur * settings.max_blur + noise_x
    var h = 1 / th * blur * settings.max_blur + noise_y
    var here = source.sample(u, v)
    var col = Vector3(here.r, here.g, here.b)
    if blur >= 0.05:
        var s = Float32(1)
        var rings = Float32(settings.rings)
        for i in range(1, settings.rings + 1):  # pragma: no branch
            var ring_samples = i * settings.samples
            var step = Float32(pi) * 2 / Float32(ring_samples)
            for j in range(ring_samples):  # pragma: no branch
                var pw = cos(Float32(j) * step) * Float32(i)
                var ph = sin(Float32(j) * step) * Float32(i)
                var p = Float32(1)
                if settings.pentagon:
                    p = bokeh2_penta(pw, ph, settings.rings)
                # `mix( 1.0, i / rings, bias )`.
                var weight = (1 + (Float32(i) / rings - 1) * settings.bias) * p
                var tap = _bokeh2_color(
                    source, u + pw * w, v + ph * h, blur, settings, tw, th
                )
                col = col + tap * weight
                s += weight
        col = col * (1 / s)
    if settings.show_focus:
        var edge = 0.002 * z
        var m = min(max(_smoothstep(0, edge, blur), Float32(0)), Float32(1))
        var e = min(max(_smoothstep(1 - edge, 1, blur), Float32(0)), Float32(1))
        var warm = (1 - m) * 0.6
        col = Vector3(
            col.x + (1 - col.x) * warm,
            col.y + (0.5 - col.y) * warm,
            col.z + (0 - col.z) * warm,
        )
        var cool = ((1 - e) - (1 - m)) * 0.2
        col = Vector3(
            col.x + (0 - col.x) * cool,
            col.y + (0.5 - col.y) * cool,
            col.z + (1 - col.z) * cool,
        )
    if settings.vignetting:
        var du = u - 0.5
        var dv = v - 0.5
        var dist = sqrt(du * du + dv * dv)
        var fade = settings.fstop / _VIGN_FADE
        var shade = min(
            max(
                _smoothstep(_VIGN_OUT + fade, _VIGN_IN + fade, dist),
                Float32(0),
            ),
            Float32(1),
        )
        col = col * shade
    return FloatColor(col.x, col.y, col.z, 1)


def bokeh2_light(
    mut frame: RenderTarget, depth: DepthView, settings: Bokeh2Settings
):
    """Run three.js's `BokehShader2` over the frame, every pixel reading
    the frame as it was before the pass.

    Args:
        frame: The frame, changed in place.
        depth: The scene's depth, as `depth_view` draws it.
        settings: The uniforms and the ring and sample counts.
    """
    var before = frame.colors.copy()
    var view = LightView(before, frame.width, frame.height)
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            frame.colors[y * frame.width + x] = bokeh2_pixel(
                view, depth, x, y, settings
            )
    # The view does not keep the copy alive; this does.
    _ = before^
