# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Post-processing: passes over the light a frame leaves in a target,
three.js's `EffectComposer` from `examples/jsm/postprocessing/` and the
passes and shaders beside it.

**What a pass is.** A render leaves linear light in a `RenderTarget`. A
pass reads every pixel of it and writes every pixel back: a blur, a bloom,
a film grain, a dot screen, a sepia, a vignette, a gray, a trail, a copy at
an opacity, the tone mapping curve, or an anti-aliasing: FXAA, SMAA, or
jittered samples averaged at once (SSAA) or over frames (TAA); see
`postprocessing.antialiasing`. Four more read the depth beside the light:
ambient occlusion (SSAO and SAO), reflections (SSR) and an outline around
chosen objects; see `postprocessing.screen_space`. Seven more blur by depth,
glitch, halftone, mask, clear, lay a texture over the frame and grade it
through a color lookup table; see `postprocessing.effects`. The composer runs its passes in
order on one target and resolves it once at the end. three.js ping-pongs
between two targets because a shader cannot read the texture it writes;
a pass here reads the whole target before it writes, so one target serves.

**Where the curve is.** three.js applies its tone mapping in an
`OutputPass`, not in the render, once a composer is in use. So does this:
the composer resolves through no curve of its own, and `output_pass` puts
the renderer's curve wherever it is asked for, in the order it is asked,
on the light of every pixel that holds light. A composer without one shows
the light as it is, as three.js does.

**What operates on what.** A blur, a bloom, a copy and a trail work on the
premultiplied light, where a sum is a sum. A color transform -- the sepia,
the gray, the dot screen, the vignette, the grain and the curve -- works on
the straight color of each pixel and premultiplies it back, as a shader
sees a straight texel. Alpha is kept by every pass but the copy, which
scales it as three.js's `CopyShader` scales the whole texel.

The passes run on the host. The GPU backend draws bytes, not light, and
has no target a pass could read; see `docs/wiki/Post-processing.md`.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.layers import Layers
from core.scene import Scene
from math.smoothstep import smoothstep
from math.utils import SeededRandom
from math.vector2 import Vector2
from postprocessing.antialiasing import (
    JITTER_LEVELS,
    JitteredCamera,
    fxaa_light,
    jitter_offsets,
    smaa_light,
)
from postprocessing.effects import (
    BokehSettings,
    FrameCopy,
    GlitchSettings,
    HalftoneSettings,
    MaskSettings,
    bokeh_light,
    check_bokeh,
    check_glitch,
    check_halftone,
    clear_light,
    glitch_heightmap,
    glitch_light,
    glitch_uniforms,
    halftone_light,
    keep_outside_mask,
    lut_light,
    mask_stencil,
    texture_light,
)
from postprocessing.sampling import clamped_tap, mix, sample, u_of, v_of
from postprocessing.screen_space import (
    DepthView,
    OutlineSettings,
    SaoSettings,
    SsaoSettings,
    SsrSettings,
    check_outline,
    check_sao,
    check_ssao,
    check_ssr,
    outline_light,
    sao_light,
    ssao_light,
    ssr_light,
)
from render.antialias import SUPERSAMPLE
from render.framebuffer import Color, FloatColor, Framebuffer
from render.target import RenderTarget
from render.texture_store import NO_TEXTURE, TextureId
from render.tonemap import NO_TONE_MAPPING, ToneMapping, tone_map
from render.volume_texture_store import NO_DATA_3D_TEXTURE, Data3DTextureId
from renderers.renderer import Renderer
from std.math import cos, exp, floor, isfinite, sin
from units.si import Angle, Duration, Length, METER, RADIAN, SECOND


@fieldwise_init
struct PassKind(Equatable, ImplicitlyCopyable, Writable):
    """What a pass does, as a type rather than a bare int.

    three.js has a class per pass and this has a tag, for the reason
    `Material` has one: a composer holds one list of one type. The type
    stops a bare integer at compile time; it does not stop `PassKind(27)`,
    which `check_pass` refuses.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the twenty-seven kinds there are."""
        return (
            self == RENDER
            or self == COPY
            or self == BLUR
            or self == BLOOM
            or self == FILM
            or self == DOT_SCREEN
            or self == SEPIA
            or self == VIGNETTE
            or self == LUMINOSITY
            or self == AFTERIMAGE
            or self == OUTPUT
            or self == FXAA
            or self == SMAA
            or self == SSAA_RENDER
            or self == TAA_RENDER
            or self == SSAO
            or self == SAO
            or self == SSR
            or self == OUTLINE
            or self == BOKEH
            or self == GLITCH
            or self == HALFTONE
            or self == MASK
            or self == CLEAR_MASK
            or self == CLEAR
            or self == TEXTURE
            or self == LUT
        )


# Draw the scene, clearing first: three.js's `RenderPass`.
comptime RENDER = PassKind(0)
# Scale every channel by an opacity: `ShaderPass(CopyShader)`.
comptime COPY = PassKind(1)
# A nine-tap blur across and then down: `ShaderPass(HorizontalBlurShader)`
# followed by `ShaderPass(VerticalBlurShader)`.
comptime BLUR = PassKind(2)
# Bright light bleeding over its edges: `UnrealBloomPass`.
comptime BLOOM = PassKind(3)
# Grain, and gray if asked: `FilmPass`.
comptime FILM = PassKind(4)
# A halftone of dots: `DotScreenPass`.
comptime DOT_SCREEN = PassKind(5)
# An old photograph's tint: `ShaderPass(SepiaShader)`.
comptime SEPIA = PassKind(6)
# Darkened corners: `ShaderPass(VignetteShader)`.
comptime VIGNETTE = PassKind(7)
# Gray by luminance: `ShaderPass(LuminosityShader)`.
comptime LUMINOSITY = PassKind(8)
# The last frame fading under this one: `AfterimagePass`.
comptime AFTERIMAGE = PassKind(9)
# The renderer's tone mapping curve: `OutputPass`.
comptime OUTPUT = PassKind(10)
# Smooth the edges by their luminance: `FXAAPass`.
comptime FXAA = PassKind(11)
# Smooth the edges by their shape: `SMAAPass`.
comptime SMAA = PassKind(12)
# Draw the scene several times, each jittered, and average: `SSAARenderPass`.
comptime SSAA_RENDER = PassKind(13)
# The same, or over many frames, a few samples a frame: `TAARenderPass`.
comptime TAA_RENDER = PassKind(14)
# Draw the scene and darken where surfaces are hemmed in: `SSAOPass`.
comptime SSAO = PassKind(15)
# Darken by scalable ambient occlusion: `SAOPass`.
comptime SAO = PassKind(16)
# Draw the scene and lay reflections over it: `SSRPass`.
comptime SSR = PassKind(17)
# A glowing edge around chosen objects: `OutlinePass`.
comptime OUTLINE = PassKind(18)
# Blur by distance from the focus: `BokehPass`.
comptime BOKEH = PassKind(19)
# Shift, tear and snow at random moments: `GlitchPass`.
comptime GLITCH = PassKind(20)
# Each channel as a grid of dots: `HalftonePass`.
comptime HALFTONE = PassKind(21)
# Let the passes after it change only what some objects cover: `MaskPass`.
comptime MASK = PassKind(22)
# Let every pass change every pixel again: `ClearMaskPass`.
comptime CLEAR_MASK = PassKind(23)
# Clear the frame to a color: `ClearPass`.
comptime CLEAR = PassKind(24)
# Add a texture over the frame: `TexturePass`.
comptime TEXTURE = PassKind(25)
# Grade the frame through a color lookup table: `LUTPass`.
comptime LUT = PassKind(26)

# three.js's `LuminosityHighPassShader` fades a pixel in over this much
# luminance above the threshold.
comptime BLOOM_SMOOTH_WIDTH = Float32(0.01)
# How many halved copies `UnrealBloomPass` blurs, and what each weighs.
comptime BLOOM_LEVELS = 5
# The dot screen measures its pattern over a fixed 256 by 256 grid, as
# three.js's `DotScreenPass` sets `tSize` once and never resizes it.
comptime DOT_SCREEN_SIZE = Float32(256)
# `AfterimageShader` keeps only the channels of the last frame above this.
comptime AFTERIMAGE_FLOOR = Float32(0.1)
# The weights three.js's blur shaders give their nine taps, four to each
# side of the pixel, summing to one.
comptime BLUR_WEIGHTS = SIMD[DType.float32, 8](
    0.051, 0.0918, 0.12245, 0.1531, 0.1633, 0.1531, 0.12245, 0.0918
)
comptime BLUR_LAST_WEIGHT = Float32(0.051)
# How many jittered samples `TAARenderPass` accumulates over frames: its
# sixth and largest pattern.
comptime TAA_SAMPLES = 32
# `SSAARenderPass`'s `roundingRange`: how far its unbiased weights spread.
comptime SSAA_ROUNDING_RANGE = Float32(1.0 / 32.0)


struct Pass(Copyable, Movable):
    """One step of a composer: its kind, whether it runs, and every
    setting any kind reads, named as three.js names them.

    Each kind reads the settings its builder takes and leaves the rest at
    their defaults. Build one with `render_pass`, `copy_pass`, `blur_pass`,
    `bloom_pass`, `film_pass`, `dot_screen_pass`, `sepia_pass`,
    `vignette_pass`, `luminosity_pass`, `afterimage_pass`, `output_pass`,
    `fxaa_pass`, `smaa_pass`, `ssaa_render_pass`, `taa_render_pass`,
    `ssao_pass`, `sao_pass`, `ssr_pass`, `outline_pass`, `bokeh_pass`,
    `glitch_pass`, `halftone_pass`, `mask_pass`, `clear_mask_pass`,
    `clear_pass`, `texture_pass` or `lut_pass`, and change a
    setting afterward as three.js changes a
    pass's uniforms; `EffectComposer.render` checks each again.
    """

    var kind: PassKind
    # three.js's `Pass.enabled`: a pass that is off is skipped.
    var enabled: Bool
    # The copy's opacity, the bloom's strength, the film's intensity, the
    # sepia's amount, the vignette's darkness or the afterimage's damp.
    var strength: Float32
    # The blur's spread in pixels per tap, or the bloom's radius, zero
    # to one.
    var radius: Float32
    # The bloom's luminance threshold.
    var threshold: Float32
    # The vignette's offset.
    var offset: Float32
    # The dot screen's scale.
    var scale: Float32
    # The dot screen's angle.
    var angle: Angle
    # The dot screen's center, in its 256-texel grid.
    var center: Vector2
    # Whether the film pass grays the frame.
    var grayscale: Bool
    # The film pass's noise seed, advanced by `EffectComposer.render`.
    var time: Float32
    # The supersampled passes' `sampleLevel`: two to this many samples,
    # zero through five.
    var sample_level: Int
    # Whether the supersampled passes vary each sample's weight so their
    # rounding cancels: `SSAARenderPass.unbiased`.
    var unbiased: Bool
    # Whether a TAA pass accumulates over frames: `TAARenderPass.accumulate`.
    var accumulate: Bool
    # How many of the TAA pass's samples are in, or minus one to start
    # over on the next frame: `TAARenderPass.accumulateIndex`.
    var accumulate_index: Int
    # What an SSAO, an SAO, an SSR or an outline pass reads; see
    # `postprocessing.screen_space`.
    var ssao: SsaoSettings
    var sao: SaoSettings
    var ssr: SsrSettings
    var outline: OutlineSettings
    # What a bokeh, a glitch, a halftone or a mask pass reads; see
    # `postprocessing.effects`.
    var bokeh: BokehSettings
    var glitch: GlitchSettings
    var halftone: HalftoneSettings
    var mask: MaskSettings
    # The clear pass's color and alpha, in sRGB: three.js's `clearColor`
    # and `clearAlpha`.
    var clear_color: Color
    # The texture pass's image, in the assets `render` is given; its
    # opacity is `strength`.
    var texture: TextureId
    # The LUT pass's table, in the assets `render` is given; its
    # intensity is `strength`.
    var lut: Data3DTextureId

    def __init__(out self, kind: PassKind):
        """Start a pass of `kind` with every setting at its default.

        Args:
            kind: What the pass does.
        """
        self.kind = kind
        self.enabled = True
        self.strength = 1.0
        self.radius = 1.0
        self.threshold = 0.0
        self.offset = 1.0
        self.scale = 1.0
        self.angle = Angle(1.57, RADIAN)
        self.center = Vector2(0.5, 0.5)
        self.grayscale = False
        self.time = 0.0
        self.sample_level = 0
        self.unbiased = True
        self.accumulate = False
        self.accumulate_index = -1
        self.ssao = SsaoSettings()
        self.sao = SaoSettings()
        self.ssr = SsrSettings()
        self.outline = OutlineSettings()
        self.bokeh = BokehSettings()
        self.glitch = GlitchSettings()
        self.halftone = HalftoneSettings()
        self.mask = MaskSettings()
        self.clear_color = Color(0, 0, 0, 0)
        self.texture = NO_TEXTURE
        self.lut = NO_DATA_3D_TEXTURE


def check_pass(step: Pass) raises:
    """Refuse a pass no kind could run.

    Args:
        step: The pass.

    Raises:
        Error: If the kind is none of the twenty-seven; a strength, radius,
            threshold, offset, scale, angle or time is not finite; a
            strength, radius, threshold, offset or scale is negative; a
            bloom's radius or an afterimage's damp is above one; the sample
            level is outside zero through five; or the accumulate index is
            outside minus one through 32; or a texture pass names no
            texture, or a LUT pass no table. Everything `check_ssao`, `check_sao`, `check_ssr`,
            `check_outline`, `check_bokeh`, `check_glitch` and
            `check_halftone` raise.
    """
    if not step.kind.is_valid():
        raise Error("A pass kind must be one of the twenty-seven named kinds")
    if not (
        isfinite(step.strength)
        and isfinite(step.radius)
        and isfinite(step.threshold)
        and isfinite(step.offset)
        and isfinite(step.scale)
        and isfinite(step.angle.value)
        and isfinite(step.time)
        and isfinite(step.center.x)
        and isfinite(step.center.y)
    ):
        raise Error("A pass setting must be finite")
    if (
        step.strength < 0
        or step.radius < 0
        or step.threshold < 0
        or step.offset < 0
        or step.scale < 0
    ):
        raise Error("A pass setting must not be negative")
    if step.kind == BLOOM and step.radius > 1:
        raise Error("A bloom's radius runs from zero to one")
    if step.kind == AFTERIMAGE and step.strength > 1:
        raise Error("An afterimage's damp runs from zero to one")
    if step.sample_level < 0 or step.sample_level >= JITTER_LEVELS:
        raise Error("A sample level runs from zero to five")
    if step.accumulate_index < -1 or step.accumulate_index > TAA_SAMPLES:
        raise Error("An accumulate index runs from minus one to 32")
    check_ssao(step.ssao)
    check_sao(step.sao)
    check_ssr(step.ssr)
    check_outline(step.outline)
    check_bokeh(step.bokeh)
    check_glitch(step.glitch)
    check_halftone(step.halftone)
    if step.kind == TEXTURE and step.texture.value < 0:
        raise Error("A texture pass must name a texture")
    if step.kind == LUT and step.lut.value < 0:
        raise Error("A LUT pass must name a 3D texture")


def render_pass() -> Pass:
    """Return a pass that draws the scene, clearing the frame first:
    three.js's `RenderPass`.

    Returns:
        The pass.
    """
    return Pass(RENDER)


def copy_pass(opacity: Float32 = 1.0) raises -> Pass:
    """Return a pass that scales every channel of every pixel: three.js's
    `CopyShader`, alpha included.

    Args:
        opacity: What to scale by. One copies.

    Returns:
        The pass.

    Raises:
        Error: If the opacity is negative or not finite.
    """
    var step = Pass(COPY)
    step.strength = opacity
    check_pass(step)
    return step^


def blur_pass(spread: Float32 = 1.0) raises -> Pass:
    """Return a pass that blurs across and then down, nine taps each way:
    three.js's `HorizontalBlurShader` and `VerticalBlurShader`, one after
    the other.

    Args:
        spread: How many pixels apart the taps are. three.js's `h` and
            `v` are a five-hundred-and-twelfth of the frame; one pixel
            here.

    Returns:
        The pass.

    Raises:
        Error: If the spread is negative or not finite.
    """
    var step = Pass(BLUR)
    step.radius = spread
    check_pass(step)
    return step^


def bloom_pass(
    strength: Float32 = 1.0, radius: Float32 = 0.0, threshold: Float32 = 0.0
) raises -> Pass:
    """Return a pass that lets bright light bleed over its edges:
    three.js's `UnrealBloomPass`.

    The light above `threshold` is blurred at five halved sizes, the
    blurs are weighted and summed, and the sum is added to the frame.

    Args:
        strength: What the sum is scaled by.
        radius: How much the larger blurs weigh against the smaller, zero
            to one. Zero weighs the smallest most, as three.js does.
        threshold: The luminance a pixel must reach to bloom.

    Returns:
        The pass.

    Raises:
        Error: If a setting is negative or not finite, or the radius is
            above one.
    """
    var step = Pass(BLOOM)
    step.strength = strength
    step.radius = radius
    step.threshold = threshold
    check_pass(step)
    return step^


def film_pass(intensity: Float32 = 0.5, grayscale: Bool = False) raises -> Pass:
    """Return a pass that adds grain, and grays if asked: three.js's
    `FilmPass`.

    The grain is a hash of each pixel's coordinate and the pass's `time`,
    which `EffectComposer.render` advances by the frame time it is given.

    Args:
        intensity: How much grain, zero to one. Zero leaves the light.
        grayscale: Whether to gray the frame by luminance afterward.

    Returns:
        The pass.

    Raises:
        Error: If the intensity is negative or not finite.
    """
    var step = Pass(FILM)
    step.strength = intensity
    step.grayscale = grayscale
    check_pass(step)
    return step^


def dot_screen_pass(
    center: Vector2 = Vector2(0.5, 0.5),
    angle: Angle = Angle(1.57, RADIAN),
    scale: Float32 = 1.0,
) raises -> Pass:
    """Return a pass that turns the frame into a halftone of dots:
    three.js's `DotScreenPass`.

    Args:
        center: Where the pattern is measured from, in the 256-texel grid
            three.js measures it over.
        angle: The pattern's angle.
        scale: How fine the dots are.

    Returns:
        The pass.

    Raises:
        Error: If the scale is negative, or a setting is not finite.
    """
    var step = Pass(DOT_SCREEN)
    step.center = center
    step.angle = angle
    step.scale = scale
    check_pass(step)
    return step^


def sepia_pass(amount: Float32 = 1.0) raises -> Pass:
    """Return a pass that tints the frame like an old photograph:
    three.js's `SepiaShader`.

    Args:
        amount: How far toward sepia, zero to one.

    Returns:
        The pass.

    Raises:
        Error: If the amount is negative or not finite.
    """
    var step = Pass(SEPIA)
    step.strength = amount
    check_pass(step)
    return step^


def vignette_pass(
    offset: Float32 = 1.0, darkness: Float32 = 1.0
) raises -> Pass:
    """Return a pass that darkens the corners: three.js's `VignetteShader`.

    Args:
        offset: How far in from the corners the darkening reaches.
        darkness: How dark the corners go, zero to one.

    Returns:
        The pass.

    Raises:
        Error: If a setting is negative or not finite.
    """
    var step = Pass(VIGNETTE)
    step.offset = offset
    step.strength = darkness
    check_pass(step)
    return step^


def luminosity_pass() -> Pass:
    """Return a pass that grays the frame by luminance: three.js's
    `LuminosityShader`.

    Returns:
        The pass.
    """
    return Pass(LUMINOSITY)


def afterimage_pass(damp: Float32 = 0.96) raises -> Pass:
    """Return a pass that keeps the last frame fading under this one:
    three.js's `AfterimagePass`.

    Args:
        damp: What the last frame is scaled by each frame, zero to one.

    Returns:
        The pass.

    Raises:
        Error: If the damp is negative, above one or not finite.
    """
    var step = Pass(AFTERIMAGE)
    step.strength = damp
    check_pass(step)
    return step^


def output_pass() -> Pass:
    """Return a pass that applies the renderer's tone mapping curve to the
    light of every pixel that holds light: three.js's `OutputPass`.

    Returns:
        The pass.
    """
    return Pass(OUTPUT)


def fxaa_pass() -> Pass:
    """Return a pass that smooths jagged edges by their luminance:
    three.js's `FXAAPass`.

    Put it after the `output_pass`, as three.js's examples do, so it sees
    the light the curve leaves rather than the light the render leaves.

    Returns:
        The pass.
    """
    return Pass(FXAA)


def smaa_pass() -> Pass:
    """Return a pass that smooths jagged edges by their shape: three.js's
    `SMAAPass`.

    Put it after the `output_pass`, as three.js's examples do.

    Returns:
        The pass.
    """
    return Pass(SMAA)


def ssaa_render_pass(
    sample_level: Int = 4, unbiased: Bool = True
) raises -> Pass:
    """Return a pass that draws the scene once per jittered sample and
    averages the samples: three.js's `SSAARenderPass`.

    Args:
        sample_level: Zero through five, for 1, 2, 4, 8, 16 or 32 samples.
        unbiased: Whether to vary each sample's weight a little about the
            mean, as three.js does, so rounding cancels.

    Returns:
        The pass.

    Raises:
        Error: If the sample level is outside zero through five.
    """
    var step = Pass(SSAA_RENDER)
    step.sample_level = sample_level
    step.unbiased = unbiased
    check_pass(step)
    return step^


def taa_render_pass(
    sample_level: Int = 0, accumulate: Bool = False
) raises -> Pass:
    """Return a pass that draws jittered samples and, once asked to,
    accumulates 32 of them over many frames: three.js's `TAARenderPass`.

    While `accumulate` is off it is an `ssaa_render_pass` of its sample
    level. Turned on, it draws two to the sample level of the 32 samples
    each frame, shows their running sum over the frame it drew when it
    started, and keeps the sum once all 32 are in. Set `accumulate_index`
    to minus one, or turn `accumulate` off, when the scene or the camera
    moves.

    Args:
        sample_level: Zero through five: how many samples a frame draws.
        accumulate: Whether to accumulate over frames.

    Returns:
        The pass.

    Raises:
        Error: If the sample level is outside zero through five.
    """
    var step = Pass(TAA_RENDER)
    step.sample_level = sample_level
    step.accumulate = accumulate
    check_pass(step)
    return step^


def ssao_pass(
    kernel_radius: Length = Length(8.0, METER),
    min_distance: Float32 = 0.005,
    max_distance: Float32 = 0.1,
) raises -> Pass:
    """Return a pass that draws the scene and darkens it where its surfaces
    are hemmed in: three.js's `SSAOPass`.

    Put it where a `render_pass` goes: it draws the frame itself, as
    three.js's does. Change `ssao.kernel_size`, `ssao.seed` or
    `ssao.output` afterward.

    Args:
        kernel_radius: How far from the surface the samples reach.
        min_distance: The least a sample must be hidden by to occlude, as
            a fraction of the camera's near-to-far range.
        max_distance: The most.

    Returns:
        The pass.

    Raises:
        Error: Everything `check_ssao` raises.
    """
    var step = Pass(SSAO)
    step.ssao.kernel_radius = kernel_radius
    step.ssao.min_distance = min_distance
    step.ssao.max_distance = max_distance
    check_pass(step)
    return step^


def sao_pass(
    intensity: Float32 = 0.18,
    scale: Float32 = 1.0,
    kernel_radius: Float32 = 100.0,
    blur: Bool = True,
) raises -> Pass:
    """Return a pass that darkens the frame by scalable ambient occlusion:
    three.js's `SAOPass`.

    Put it after a `render_pass`. It draws the scene's depth itself and
    darkens the frame it is given. Its other `params` are the fields of
    `sao`.

    Args:
        intensity: What the occlusion is scaled by: `saoIntensity`.
        scale: How fast it falls off with distance: `saoScale`.
        kernel_radius: How far the samples reach, in pixels:
            `saoKernelRadius`.
        blur: Whether the occlusion is blurred: `saoBlur`.

    Returns:
        The pass.

    Raises:
        Error: Everything `check_sao` raises.
    """
    var step = Pass(SAO)
    step.sao.intensity = intensity
    step.sao.scale = scale
    step.sao.kernel_radius = kernel_radius
    step.sao.blur = blur
    check_pass(step)
    return step^


def ssr_pass(
    opacity: Float32 = 0.5,
    max_distance: Length = Length(180.0, METER),
    thickness: Length = Length(0.018, METER),
) raises -> Pass:
    """Return a pass that draws the scene and lays what each surface
    reflects over it: three.js's `SSRPass`.

    Put it where a `render_pass` goes: it draws the frame itself, as
    three.js's does. Every surface reflects. The other settings are the
    fields of `ssr`.

    Args:
        opacity: How much of a reflection shows, at most.
        max_distance: How far from a surface a reflection is looked for.
        thickness: How thick each surface is taken to be.

    Returns:
        The pass.

    Raises:
        Error: Everything `check_ssr` raises.
    """
    var step = Pass(SSR)
    step.ssr.opacity = opacity
    step.ssr.max_distance = max_distance
    step.ssr.thickness = thickness
    check_pass(step)
    return step^


def outline_pass(
    selection: Layers,
    edge_strength: Float32 = 3.0,
    edge_thickness: Float32 = 1.0,
) raises -> Pass:
    """Return a pass that draws a glowing edge around the objects on some
    layers: three.js's `OutlinePass`.

    three.js takes a list of objects. This takes the layers they are on:
    the pass draws through a camera that sees those layers alone. Put it
    after a `render_pass`. The edge colors, the glow and the pulse are the
    fields of `outline`. The pulse follows the frame time `render` is
    given.

    Args:
        selection: The layers whose objects are outlined. An empty set
            outlines nothing.
        edge_strength: What the edge is scaled by.
        edge_thickness: How far the edge's narrow blur reaches.

    Returns:
        The pass.

    Raises:
        Error: Everything `check_outline` raises.
    """
    var step = Pass(OUTLINE)
    step.outline.selection = selection
    step.outline.edge_strength = edge_strength
    step.outline.edge_thickness = edge_thickness
    check_pass(step)
    return step^


def bokeh_pass(
    focus: Length = Length(1.0, METER),
    aperture: Float32 = 0.025,
    max_blur: Float32 = 1.0,
) raises -> Pass:
    """Return a pass that blurs the frame by each pixel's distance from the
    focus: three.js's `BokehPass`.

    Put it after a `render_pass`. It draws the scene's depth itself and
    blurs the frame it is given.

    Args:
        focus: The distance in focus.
        aperture: How fast the blur grows away from the focus.
        max_blur: The most blur, in texture widths.

    Returns:
        The pass.

    Raises:
        Error: Everything `check_bokeh` raises.
    """
    var step = Pass(BOKEH)
    step.bokeh.focus = focus
    step.bokeh.aperture = aperture
    step.bokeh.max_blur = max_blur
    check_pass(step)
    return step^


def glitch_pass(size: Int = 64, seed: Int = 0) raises -> Pass:
    """Return a pass that shifts the channels apart, tears the frame and
    adds snow at random moments: three.js's `GlitchPass`.

    Every frame `render` draws advances it. Set `glitch.go_wild` to glitch
    every frame hard.

    Args:
        size: How many texels a side the displacement map has: three.js's
            `dt_size`.
        seed: The seed of the map and of every frame's draw.

    Returns:
        The pass.

    Raises:
        Error: Everything `check_glitch` raises.
    """
    var step = Pass(GLITCH)
    step.glitch = GlitchSettings(size, seed)
    check_pass(step)
    return step^


def halftone_pass(radius: Float32 = 4.0) raises -> Pass:
    """Return a pass that redraws each channel as a grid of dots:
    three.js's `HalftonePass`.

    The shape, the angles, the scatter and the blending are the fields of
    `halftone`.

    Args:
        radius: How many pixels apart the dots are.

    Returns:
        The pass.

    Raises:
        Error: Everything `check_halftone` raises.
    """
    var step = Pass(HALFTONE)
    step.halftone.radius = radius
    check_pass(step)
    return step^


def mask_pass(selection: Layers, inverse: Bool = False) -> Pass:
    """Return a pass after which the passes change only what the objects
    on some layers cover: three.js's `MaskPass`.

    three.js takes a scene. This takes the layers its objects are on, as
    `outline_pass` does. A `clear_mask_pass` ends the mask.

    Args:
        selection: The layers whose objects make the mask.
        inverse: Whether the passes change what the objects do not cover.

    Returns:
        The pass.
    """
    var step = Pass(MASK)
    step.mask.selection = selection
    step.mask.inverse = inverse
    return step^


def clear_mask_pass() -> Pass:
    """Return a pass after which the passes change every pixel again:
    three.js's `ClearMaskPass`.

    Returns:
        The pass.
    """
    return Pass(CLEAR_MASK)


def clear_pass(color: Color = Color(0, 0, 0, 0)) -> Pass:
    """Return a pass that clears the frame to a color: three.js's
    `ClearPass`.

    Args:
        color: The color and its alpha, in sRGB. Transparent black, as
            three.js's defaults are.

    Returns:
        The pass.
    """
    var step = Pass(CLEAR)
    step.clear_color = color
    return step^


def texture_pass(texture: TextureId, opacity: Float32 = 1.0) raises -> Pass:
    """Return a pass that adds a texture over the frame: three.js's
    `TexturePass`.

    Args:
        texture: The image, in the assets `render` is given.
        opacity: What the texture is scaled by.

    Returns:
        The pass.

    Raises:
        Error: If the texture is `NO_TEXTURE`, or the opacity is negative
            or not finite.
    """
    var step = Pass(TEXTURE)
    step.texture = texture
    step.strength = opacity
    check_pass(step)
    return step^


def lut_pass(lut: Data3DTextureId, intensity: Float32 = 1.0) raises -> Pass:
    """Return a pass that grades the frame through a color lookup table:
    three.js's `LUTPass`.

    Put it after the `output_pass`, as three.js's examples do: a `.cube`
    table maps the colors a display shows. See
    `postprocessing.effects.lut_light`.

    Args:
        lut: The table, in the assets' `data_3d_textures`; three.js's
            `lut`. `loaders.lut_cube.read_lut_cube` reads one.
        intensity: How far toward the lookup, one replacing the color:
            three.js's `intensity`.

    Returns:
        The pass.

    Raises:
        Error: If the table is `NO_DATA_3D_TEXTURE`, or the intensity is
            negative or not finite.
    """
    var step = Pass(LUT)
    step.lut = lut
    step.strength = intensity
    check_pass(step)
    return step^


struct TaaMemory(Copyable, Movable):
    """What a TAA pass keeps between frames: three.js's `_holdRenderTarget`
    and `_sampleRenderTarget`.
    """

    # The frame drawn when accumulation started, which fills in for the
    # samples not in yet.
    var hold: List[FloatColor]
    # Which of its pixels held data.
    var hold_data: List[Bool]
    # Its depths.
    var hold_depth: List[Float32]
    # The samples drawn so far, each weighted by one in 32.
    var sum: List[FloatColor]

    def __init__(out self):
        """Start with nothing held."""
        self.hold = List[FloatColor]()
        self.hold_data = List[Bool]()
        self.hold_depth = List[Float32]()
        self.sum = List[FloatColor]()


struct EffectComposer(Movable):
    """The passes a frame goes through, in order: three.js's
    `EffectComposer`.

    ```
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(bloom_pass(1.5, 0.4, 0.85))
    composer.add_pass(output_pass())
    var image = composer.render(renderer, scene, assets, camera)
    ```
    """

    var passes: List[Pass]
    # What an afterimage pass saw last, one entry per pass and empty for
    # every other kind and before the first frame.
    var memories: List[List[FloatColor]]
    # What a TAA pass has accumulated, one entry per pass and empty for
    # every other kind and before the first frame.
    var accumulations: List[TaaMemory]

    def __init__(out self):
        """Start with no passes."""
        self.passes = List[Pass]()
        self.memories = List[List[FloatColor]]()
        self.accumulations = List[TaaMemory]()

    def add_pass(mut self, var step: Pass) raises:
        """Append a pass: three.js's `addPass`.

        Args:
            step: The pass.

        Raises:
            Error: Everything `check_pass` raises.
        """
        check_pass(step)
        self.passes.append(step^)
        self.memories.append(List[FloatColor]())
        self.accumulations.append(TaaMemory())

    def insert_pass(mut self, var step: Pass, index: Int) raises:
        """Put a pass before the one at `index`: three.js's `insertPass`.

        Args:
            step: The pass.
            index: Where it goes, zero through the count.

        Raises:
            Error: Everything `check_pass` raises, or if the index is
                outside zero through the count.
        """
        check_pass(step)
        if index < 0 or index > len(self.passes):
            raise Error("A pass is inserted at zero through the count")
        self.passes.insert(index, step^)
        self.memories.insert(index, List[FloatColor]())
        self.accumulations.insert(index, TaaMemory())

    def remove_pass(mut self, index: Int) raises:
        """Take a pass out: three.js's `removePass`.

        Args:
            index: Which, in order.

        Raises:
            Error: If the index is outside the passes.
        """
        if index < 0 or index >= len(self.passes):
            raise Error("There is no pass at that index")
        _ = self.passes.pop(index)
        _ = self.memories.pop(index)
        _ = self.accumulations.pop(index)

    def pass_count(self) -> Int:
        """Return how many passes there are."""
        return len(self.passes)

    def reset(mut self):
        """Forget what every afterimage pass saw, so the next frame
        starts a fresh trail: three.js's `reset`. Every TAA pass forgets
        its samples too, and starts accumulating again.
        """
        for index in range(len(self.memories)):
            self.memories[index] = List[FloatColor]()
            self.accumulations[index] = TaaMemory()

    def render[
        C: Camera
    ](
        mut self,
        renderer: Renderer,
        scene: Scene,
        assets: Assets,
        camera: C,
        delta_time: Float32 = 0.0,
    ) raises -> Framebuffer:
        """Run every enabled pass in order on one frame and return it:
        three.js's `render`.

        The frame starts cleared to the renderer's background. A render
        pass draws the scene into it, through the renderer's antialias
        when that is on. Every other pass reads and writes the light. The
        frame is resolved once at the end, through no curve: an
        `output_pass` is where the renderer's curve is applied.

        Args:
            renderer: What a render pass draws with, and whose size,
                background, workers and curve the frame takes.
            scene: The transform hierarchy, and the meshes and lights in it.
            assets: The geometry, materials and textures the meshes name.
            camera: The camera a render pass projects through.
            delta_time: How many seconds since the last frame, which
                advances each film pass's grain. Zero holds the grain.

        Returns:
            The rendered image.

        Raises:
            Error: Everything `check_pass` raises for a pass changed since
                it was added, everything `Renderer.render_into` raises,
                if a texture or a table a pass names is not in the assets
                or fails its `validate`, or if the frame time is negative
                or not finite.
        """
        if not isfinite(delta_time) or delta_time < 0:
            raise Error("A frame time is a non-negative number of seconds")
        var frame = RenderTarget(
            renderer.width, renderer.height, renderer.background
        )
        # Whether a mask pass has run with no clear mask pass after it:
        # three.js's `maskActive`.
        var mask_active = False
        for index in range(len(self.passes)):
            check_pass(self.passes[index])
            ref step = self.passes[index]
            if not step.enabled:
                continue
            if step.kind == MASK:
                _mask(frame, step, renderer, scene, assets, camera)
                mask_active = True
                continue
            if step.kind == CLEAR_MASK:
                mask_active = False
                continue
            var saved = FrameCopy()
            if mask_active:
                saved = FrameCopy(frame)
            if step.kind == RENDER:
                _draw(frame, renderer, scene, assets, camera)
            elif step.kind == COPY:
                copy_light(frame, step.strength)
            elif step.kind == BLUR:
                blur_light(frame, step.radius)
            elif step.kind == BLOOM:
                bloom_light(frame, step.strength, step.radius, step.threshold)
            elif step.kind == FILM:
                self.passes[index].time += delta_time
                film_light(
                    frame,
                    step.strength,
                    step.grayscale,
                    self.passes[index].time,
                )
            elif step.kind == DOT_SCREEN:
                dot_screen_light(frame, step.center, step.angle, step.scale)
            elif step.kind == SEPIA:
                sepia_light(frame, step.strength)
            elif step.kind == VIGNETTE:
                vignette_light(frame, step.offset, step.strength)
            elif step.kind == LUMINOSITY:
                luminosity_light(frame)
            elif step.kind == AFTERIMAGE:
                afterimage_light(frame, self.memories[index], step.strength)
            elif step.kind == FXAA:
                fxaa_light(frame)
            elif step.kind == SMAA:
                smaa_light(frame)
            elif step.kind == SSAA_RENDER:
                frame = supersample(
                    renderer,
                    scene,
                    assets,
                    camera,
                    step.sample_level,
                    step.unbiased,
                )
            elif step.kind == SSAO:
                _draw(frame, renderer, scene, assets, camera)
                ssao_light(frame, _depth_view(frame, camera), step.ssao)
            elif step.kind == SAO:
                var drawn = RenderTarget(
                    renderer.width, renderer.height, renderer.background
                )
                _draw(drawn, renderer, scene, assets, camera)
                # three.js draws a fresh `randomSeed` every frame.
                var random = SeededRandom(step.sao.seed)
                var random_seed = Float32(random.next())
                self.passes[index].sao.seed = Int(random.state)
                sao_light(
                    frame,
                    _depth_view(drawn, camera),
                    self.passes[index].sao,
                    random_seed,
                )
            elif step.kind == SSR:
                _draw(frame, renderer, scene, assets, camera)
                ssr_light(frame, _depth_view(frame, camera), step.ssr)
            elif step.kind == OUTLINE:
                self.passes[index].time += delta_time
                _outline(
                    frame,
                    self.passes[index],
                    renderer,
                    scene,
                    assets,
                    camera,
                )
            elif step.kind == TAA_RENDER:
                taa_render(
                    frame,
                    self.passes[index],
                    self.accumulations[index],
                    renderer,
                    scene,
                    assets,
                    camera,
                )
            elif step.kind == BOKEH:
                var depth = RenderTarget(
                    renderer.width, renderer.height, renderer.background
                )
                _draw(depth, renderer, scene, assets, camera)
                bokeh_light(frame, _depth_view(depth, camera), step.bokeh)
            elif step.kind == GLITCH:
                var uniforms = glitch_uniforms(self.passes[index].glitch)
                ref glitch = self.passes[index].glitch
                glitch_light(
                    frame,
                    glitch_heightmap(glitch.size, glitch.seed),
                    glitch.size,
                    uniforms,
                )
            elif step.kind == HALFTONE:
                halftone_light(frame, step.halftone)
            elif step.kind == CLEAR:
                clear_light(frame, step.clear_color)
            elif step.kind == TEXTURE:
                texture_light(
                    frame, assets.textures.get(step.texture), step.strength
                )
            elif step.kind == LUT:
                lut_light(
                    frame, assets.data_3d_textures.get(step.lut), step.strength
                )
            else:
                # `OUTPUT`: the only kind left once `check_pass` has had
                # its say.
                output_light(
                    frame, renderer.tone_curve(), renderer.tone_mapping_exposure
                )
            if mask_active:
                keep_outside_mask(frame, saved)
        return frame.resolve(renderer.workers, NO_TONE_MAPPING, 1.0)


def _draw[
    C: Camera
](
    mut frame: RenderTarget,
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: C,
) raises:
    """Draw the scene into `frame` as `Renderer.render` would before it
    resolves: supersampled and averaged down when the renderer
    antialiases, straight in when it does not."""
    if renderer.antialias:
        var big = renderer.supersampled()
        var drawn = RenderTarget(big.width, big.height, renderer.background)
        big.render_into(drawn, scene, assets, camera)
        frame = drawn.downsampled(SUPERSAMPLE)
        return
    renderer.render_into(frame, scene, assets, camera)


def _depth_view[C: Camera](drawn: RenderTarget, camera: C) raises -> DepthView:
    """Return a target's depth read through the camera that drew it."""
    return DepthView(
        drawn.depth,
        drawn.width,
        drawn.height,
        camera.projection_matrix(),
        Length(camera.near_distance(), METER),
        Length(camera.far_distance(), METER),
    )


def _outline[
    C: Camera
](
    mut frame: RenderTarget,
    step: Pass,
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: C,
) raises:
    """Run an outline pass: draw the scene's depth, and the depth of the
    selected layers alone through the same camera, and outline what the
    second holds. A selection of no layers outlines nothing, as three.js's
    pass does with no selected objects."""
    var selection = step.outline.selection
    if selection.mask == 0:
        return
    var everything = RenderTarget(
        renderer.width, renderer.height, renderer.background
    )
    _draw(everything, renderer, scene, assets, camera)
    var chosen = JitteredCamera(
        camera, scene, 0, 0, renderer.width, renderer.height
    )
    chosen.layers = selection
    var picked = RenderTarget(
        renderer.width, renderer.height, renderer.background
    )
    _draw(picked, renderer, scene, assets, chosen)
    outline_light(
        frame,
        everything.depth,
        picked.depth,
        step.outline,
        Duration(step.time, SECOND),
    )


def _mask[
    C: Camera
](
    mut frame: RenderTarget,
    step: Pass,
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: C,
) raises:
    """Run a mask pass: draw the selected layers alone through the same
    camera and write where they cover into the frame's stencil. The
    frame's light and depth are left alone, as three.js's `MaskPass`
    turns off the color and the depth writes."""
    var chosen = JitteredCamera(
        camera, scene, 0, 0, renderer.width, renderer.height
    )
    chosen.layers = step.mask.selection
    var picked = RenderTarget(
        renderer.width, renderer.height, renderer.background
    )
    _draw(picked, renderer, scene, assets, chosen)
    mask_stencil(frame, picked.depth, step.mask.inverse)


def supersample[
    C: Camera
](
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: C,
    sample_level: Int,
    unbiased: Bool,
) raises -> RenderTarget:
    """Draw the scene once per jittered sample of a level and return the
    weighted sum: three.js's `SSAARenderPass.render`.

    Each sample is drawn as a render pass draws, cleared to the renderer's
    background, through `JitteredCamera`, and added in by its weight. The
    weights are one over the count. Unbiased, they are spread evenly over
    a thirty-second about that, as three.js spreads them, and still sum to
    one. A pixel is data only if it is data in every sample, and its depth
    is the nearest.

    Args:
        renderer: What to draw with, and whose size and background to take.
        scene: The transform hierarchy, and the meshes and lights in it.
        assets: The geometry, materials and textures the meshes name.
        camera: The camera to jitter.
        sample_level: Zero through five, for 1, 2, 4, 8, 16 or 32 samples.
        unbiased: Whether to spread the weights.

    Returns:
        The averaged frame.

    Raises:
        Error: Everything `jitter_offsets` and `Renderer.render_into` raise.
    """
    var offsets = jitter_offsets(sample_level)
    var count = len(offsets)
    var frame = RenderTarget(
        renderer.width, renderer.height, renderer.background
    )
    var pixels = len(frame.colors)
    for slot in range(pixels):  # pragma: no branch
        frame.colors[slot] = FloatColor(0, 0, 0, 0)
        frame.data[slot] = True
    for index in range(count):  # pragma: no branch
        var weight = 1 / Float32(count)
        if unbiased:
            weight += SSAA_ROUNDING_RANGE * (
                -0.5 + (Float32(index) + 0.5) / Float32(count)
            )
        var drawn = _jittered(renderer, scene, assets, camera, offsets[index])
        for slot in range(pixels):  # pragma: no branch
            var sum = frame.colors[slot]
            var add = drawn.colors[slot]
            frame.colors[slot] = FloatColor(
                sum.r + add.r * weight,
                sum.g + add.g * weight,
                sum.b + add.b * weight,
                sum.a + add.a * weight,
            )
            frame.data[slot] = frame.data[slot] and drawn.data[slot]
            frame.depth[slot] = min(frame.depth[slot], drawn.depth[slot])
    return frame^


def _jittered[
    C: Camera
](
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: C,
    offset: Vector2,
) raises -> RenderTarget:
    """Return the scene drawn as a render pass draws it, the camera's view
    moved by `offset` pixels."""
    var frame = RenderTarget(
        renderer.width, renderer.height, renderer.background
    )
    var moved = JitteredCamera(
        camera, scene, offset.x, offset.y, renderer.width, renderer.height
    )
    _draw(frame, renderer, scene, assets, moved)
    return frame^


def taa_render[
    C: Camera
](
    mut frame: RenderTarget,
    mut step: Pass,
    mut memory: TaaMemory,
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: C,
) raises:
    """Run one frame of a TAA pass: three.js's `TAARenderPass.render`.

    Not accumulating, the frame is `supersample` at the pass's level and
    the index goes back to minus one. Accumulating, a first frame, or one
    of another size, is supersampled and held, and the index starts at
    zero. Then, while fewer than 32 samples are in, up to two to the level
    of them are drawn, each weighted one in 32. The frame is their sum
    plus the held frame weighted by what is still missing. The held frame's
    data flags and depths are kept.

    Args:
        frame: The frame, replaced.
        step: The pass, whose index advances.
        memory: What the pass holds between frames.
        renderer: What to draw with.
        scene: The transform hierarchy, and the meshes and lights in it.
        assets: The geometry, materials and textures the meshes name.
        camera: The camera to jitter.

    Raises:
        Error: Everything `supersample` raises.
    """
    if not step.accumulate:
        frame = supersample(
            renderer, scene, assets, camera, step.sample_level, step.unbiased
        )
        step.accumulate_index = -1
        return
    var pixels = renderer.width * renderer.height
    if step.accumulate_index == -1 or len(memory.hold) != pixels:
        var held = supersample(
            renderer, scene, assets, camera, step.sample_level, step.unbiased
        )
        memory.hold = held.colors.copy()
        memory.hold_data = held.data.copy()
        memory.hold_depth = held.depth.copy()
        memory.sum = List[FloatColor](
            length=pixels, fill=FloatColor(0, 0, 0, 0)
        )
        step.accumulate_index = 0
    var weight = 1 / Float32(TAA_SAMPLES)
    var offsets = jitter_offsets(JITTER_LEVELS - 1)
    var per_frame = 1 << step.sample_level
    var drawn = 0
    while drawn < per_frame and step.accumulate_index < TAA_SAMPLES:
        var jittered = _jittered(
            renderer, scene, assets, camera, offsets[step.accumulate_index]
        )
        for slot in range(pixels):  # pragma: no branch
            var sum = memory.sum[slot]
            var add = jittered.colors[slot]
            memory.sum[slot] = FloatColor(
                sum.r + add.r * weight,
                sum.g + add.g * weight,
                sum.b + add.b * weight,
                sum.a + add.a * weight,
            )
        step.accumulate_index += 1
        drawn += 1
    var missing = 1 - Float32(step.accumulate_index) * weight
    frame = RenderTarget(renderer.width, renderer.height, renderer.background)
    for slot in range(pixels):  # pragma: no branch
        var sum = memory.sum[slot]
        var held = memory.hold[slot]
        frame.colors[slot] = FloatColor(
            sum.r + held.r * missing,
            sum.g + held.g * missing,
            sum.b + held.b * missing,
            sum.a + held.a * missing,
        )
    frame.data = memory.hold_data.copy()
    frame.depth = memory.hold_depth.copy()


def luminance(color: FloatColor) -> Float32:
    """Return a color's luminance: three.js's `luminance`, rec. 709's
    weights on the linear channels.

    Args:
        color: The color, straight or premultiplied.

    Returns:
        The weighted sum of red, green and blue.
    """
    return 0.2126729 * color.r + 0.7151522 * color.g + 0.0721750 * color.b


def copy_light(mut frame: RenderTarget, opacity: Float32):
    """Scale every channel of every pixel: three.js's `CopyShader`.

    Args:
        frame: The frame, changed in place.
        opacity: What to scale by.
    """
    for index in range(len(frame.colors)):  # pragma: no branch
        ref color = frame.colors[index]
        frame.colors[index] = FloatColor(
            color.r * opacity,
            color.g * opacity,
            color.b * opacity,
            color.a * opacity,
        )


def _blur_along(mut frame: RenderTarget, spread: Float32, across: Bool):
    """Blur the frame with three.js's nine taps along one axis, the taps
    `spread` pixels apart and held at the edges."""
    var width = frame.width
    var height = frame.height
    var source = frame.colors.copy()
    # Spelled with `while`: three nested `for` loops over computed
    # bounds send the compiler into the hang described in
    # docs/wiki/The-Mojo-compiler-hang.md.
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var sum = FloatColor(0, 0, 0, 0)
            var tap = 0
            while tap < 9:
                var weight = BLUR_LAST_WEIGHT
                if tap < 8:
                    weight = BLUR_WEIGHTS[tap]
                var step = Float32(tap - 4) * spread
                var tx = Float32(x)
                var ty = Float32(y)
                if across:
                    tx += step
                else:
                    ty += step
                var here = clamped_tap(source, width, height, tx, ty)
                sum = FloatColor(
                    sum.r + here.r * weight,
                    sum.g + here.g * weight,
                    sum.b + here.b * weight,
                    sum.a + here.a * weight,
                )
                tap += 1
            frame.colors[y * width + x] = sum
            x += 1
        y += 1


def blur_light(mut frame: RenderTarget, spread: Float32):
    """Blur the frame across and then down, nine taps each way: three.js's
    `HorizontalBlurShader` and then its `VerticalBlurShader`.

    Args:
        frame: The frame, changed in place.
        spread: How many pixels apart the taps are.
    """
    _blur_along(frame, spread, True)
    _blur_along(frame, spread, False)


def _gaussian(x: Float32, sigma: Float32) -> Float32:
    """Return three.js's `gaussianPdf`."""
    return 0.39894 * exp(-0.5 * x * x / (sigma * sigma)) / sigma


def _separable_blur(
    source: List[FloatColor],
    source_width: Int,
    source_height: Int,
    width: Int,
    height: Int,
    kernel: Int,
    across: Bool,
) -> List[FloatColor]:
    """Return `source` blurred along one axis into a `width` by `height`
    image: `UnrealBloomPass`'s separable blur at one size, a Gaussian of
    `kernel` taps to each side whose sigma is the kernel."""
    var out = List[FloatColor](
        length=width * height, fill=FloatColor(0, 0, 0, 1)
    )
    var sigma = Float32(kernel)
    var step_u = Float32(0)
    var step_v = Float32(0)
    if across:
        step_u = 1 / Float32(width)
    else:
        step_v = 1 / Float32(height)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var u = u_of(x, width)
            var v = v_of(y, height)
            var weight = _gaussian(0, sigma)
            var center = sample(source, source_width, source_height, u, v)
            var sum = center.scaled(weight)
            var total = weight
            var tap = 1
            while tap < kernel:
                var offset = Float32(tap)
                var w = _gaussian(offset, sigma)
                var ahead = sample(
                    source,
                    source_width,
                    source_height,
                    u + step_u * offset,
                    v + step_v * offset,
                )
                var behind = sample(
                    source,
                    source_width,
                    source_height,
                    u - step_u * offset,
                    v - step_v * offset,
                )
                sum = FloatColor(
                    sum.r + (ahead.r + behind.r) * w,
                    sum.g + (ahead.g + behind.g) * w,
                    sum.b + (ahead.b + behind.b) * w,
                    1,
                )
                total += 2 * w
                tap += 1
            out[y * width + x] = FloatColor(
                sum.r / total, sum.g / total, sum.b / total, 1
            )
            x += 1
        y += 1
    return out^


def _bloom_factor(level: Int, radius: Float32) -> Float32:
    """Return what a bloom level weighs: three.js's `lerpBloomFactor` of
    its `bloomFactors`, one down to a fifth, mirrored about 0.6 by the
    radius."""
    var factor = 1 - 0.2 * Float32(level)
    var mirror = 1.2 - factor
    return factor + (mirror - factor) * radius


def _halved(size: Int) -> Int:
    """Return a size halved and rounded as three.js's `Math.round(x / 2)`
    rounds it: never below one, since no target is narrower than one."""
    return (size + 1) // 2


def bloom_light(
    mut frame: RenderTarget,
    strength: Float32,
    radius: Float32,
    threshold: Float32,
):
    """Add the frame's bright light back over its edges: three.js's
    `UnrealBloomPass`.

    The light whose luminance is above `threshold` is kept, faded in over
    a hundredth; it is blurred at five halved sizes, each blur across and
    then down with a kernel two taps wider than the last; the five are
    weighted by `radius` and summed; and the sum, scaled by `strength`,
    is added to the red, green and blue of every pixel. Alpha is kept.

    Args:
        frame: The frame, changed in place.
        strength: What the sum is scaled by.
        radius: How much the larger blurs weigh against the smaller.
        threshold: The luminance a pixel must reach to bloom.
    """
    var width = frame.width
    var height = frame.height
    var bright = List[FloatColor](
        length=width * height, fill=FloatColor(0, 0, 0, 0)
    )
    for index in range(len(frame.colors)):  # pragma: no branch
        ref color = frame.colors[index]
        var alpha = smoothstep(
            threshold, threshold + BLOOM_SMOOTH_WIDTH, luminance(color)
        )
        bright[index] = FloatColor(
            color.r * alpha, color.g * alpha, color.b * alpha, color.a * alpha
        )
    # Each level blurs the one before it into half its size, the first
    # blurring the bright light at the frame's own size.
    var levels = List[List[FloatColor]]()
    var level_widths = List[Int]()
    var level_heights = List[Int]()
    var source = bright^
    var source_width = width
    var source_height = height
    var level_width = _halved(width)
    var level_height = _halved(height)
    for level in range(BLOOM_LEVELS):  # pragma: no branch
        var kernel = 3 + 2 * level
        var across = _separable_blur(
            source,
            source_width,
            source_height,
            level_width,
            level_height,
            kernel,
            True,
        )
        var down = _separable_blur(
            across,
            level_width,
            level_height,
            level_width,
            level_height,
            kernel,
            False,
        )
        levels.append(down.copy())
        level_widths.append(level_width)
        level_heights.append(level_height)
        source = down^
        source_width = level_width
        source_height = level_height
        level_width = _halved(level_width)
        level_height = _halved(level_height)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var u = u_of(x, width)
            var v = v_of(y, height)
            var glow = FloatColor(0, 0, 0, 0)
            var level = 0
            while level < BLOOM_LEVELS:
                var weight = _bloom_factor(level, radius) * strength
                var here = sample(
                    levels[level],
                    level_widths[level],
                    level_heights[level],
                    u,
                    v,
                )
                glow = FloatColor(
                    glow.r + here.r * weight,
                    glow.g + here.g * weight,
                    glow.b + here.b * weight,
                    0,
                )
                level += 1
            var index = y * width + x
            ref color = frame.colors[index]
            frame.colors[index] = FloatColor(
                color.r + glow.r, color.g + glow.g, color.b + glow.b, color.a
            )
            x += 1
        y += 1


def _fract(value: Float32) -> Float32:
    """Return GLSL's `fract`: what is left above the floor."""
    return value - floor(value)


def _rand(u: Float32, v: Float32) -> Float32:
    """Return three.js's `rand`: the fractional part of a large sine of
    the coordinate's dot with a fixed vector."""
    return _fract(sin(u * 12.9898 + v * 78.233) * 43758.5453)


def film_light(
    mut frame: RenderTarget, intensity: Float32, grayscale: Bool, time: Float32
):
    """Add grain to the frame, and gray it if asked: three.js's
    `FilmShader`.

    Each pixel's straight color is brightened by itself times a hash of
    its coordinate and the time, from a tenth to one and a tenth, and
    the brightened color is mixed in by `intensity`. Alpha is kept.

    Args:
        frame: The frame, changed in place.
        intensity: How much of the grain shows, zero to one.
        grayscale: Whether to gray the result by luminance.
        time: The grain's seed.
    """
    var width = frame.width
    var height = frame.height
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var index = y * width + x
            var base = frame.colors[index].unpremultiplied()
            var noise = _rand(u_of(x, width) + time, v_of(y, height) + time)
            var grain = noise + 0.1
            if grain > 1:
                grain = 1
            var color = FloatColor(
                base.r + base.r * grain,
                base.g + base.g * grain,
                base.b + base.b * grain,
                base.a,
            )
            color = mix(base, color, intensity)
            if grayscale:
                var gray = luminance(color)
                color = FloatColor(gray, gray, gray, base.a)
            frame.colors[index] = color.premultiplied()
            x += 1
        y += 1


def dot_screen_light(
    mut frame: RenderTarget, center: Vector2, angle: Angle, scale: Float32
):
    """Turn the frame into a halftone of dots: three.js's
    `DotScreenShader`.

    Each pixel's straight color becomes its average, stretched ten times
    about a half, plus a sine grid turned by `angle` and scaled by `scale`
    over a 256-texel square, as three.js's pass measures it. Alpha is
    kept. The result runs past black and white and is clamped when the
    frame is resolved.

    Args:
        frame: The frame, changed in place.
        center: Where the grid is measured from, in that square.
        angle: The grid's angle.
        scale: How fine the dots are.
    """
    var width = frame.width
    var height = frame.height
    var s = sin(angle.value)
    var c = cos(angle.value)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var index = y * width + x
            var base = frame.colors[index].unpremultiplied()
            var tx = u_of(x, width) * DOT_SCREEN_SIZE - center.x
            var ty = v_of(y, height) * DOT_SCREEN_SIZE - center.y
            var px = (c * tx - s * ty) * scale
            var py = (s * tx + c * ty) * scale
            var pattern = sin(px) * sin(py) * 4
            var average = (base.r + base.g + base.b) / 3
            var value = average * 10 - 5 + pattern
            frame.colors[index] = FloatColor(
                value, value, value, base.a
            ).premultiplied()
            x += 1
        y += 1


def sepia_light(mut frame: RenderTarget, amount: Float32):
    """Tint the frame like an old photograph: three.js's `SepiaShader`.

    Args:
        frame: The frame, changed in place.
        amount: How far toward sepia, zero to one.
    """
    for index in range(len(frame.colors)):  # pragma: no branch
        var base = frame.colors[index].unpremultiplied()
        var r = (
            base.r * (1 - 0.607 * amount)
            + base.g * (0.769 * amount)
            + base.b * (0.189 * amount)
        )
        var g = (
            base.r * (0.349 * amount)
            + base.g * (1 - 0.314 * amount)
            + base.b * (0.168 * amount)
        )
        var b = (
            base.r * (0.272 * amount)
            + base.g * (0.534 * amount)
            + base.b * (1 - 0.869 * amount)
        )
        if r > 1:
            r = 1
        if g > 1:
            g = 1
        if b > 1:
            b = 1
        frame.colors[index] = FloatColor(r, g, b, base.a).premultiplied()


def vignette_light(mut frame: RenderTarget, offset: Float32, darkness: Float32):
    """Darken the frame's corners: three.js's `VignetteShader`.

    Each pixel's straight color is mixed toward one minus `darkness` by
    the square of its distance from the center, that distance scaled by
    `offset`. Alpha is kept.

    Args:
        frame: The frame, changed in place.
        offset: How far in from the corners the darkening reaches.
        darkness: How dark the corners go.
    """
    var width = frame.width
    var height = frame.height
    var edge = FloatColor(1 - darkness, 1 - darkness, 1 - darkness, 0)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var index = y * width + x
            var base = frame.colors[index].unpremultiplied()
            var u = (u_of(x, width) - 0.5) * offset
            var v = (v_of(y, height) - 0.5) * offset
            var mixed = mix(base, edge, u * u + v * v)
            frame.colors[index] = FloatColor(
                mixed.r, mixed.g, mixed.b, base.a
            ).premultiplied()
            x += 1
        y += 1


def luminosity_light(mut frame: RenderTarget):
    """Gray the frame by luminance: three.js's `LuminosityShader`.

    Args:
        frame: The frame, changed in place.
    """
    for index in range(len(frame.colors)):  # pragma: no branch
        var base = frame.colors[index].unpremultiplied()
        var gray = luminance(base)
        frame.colors[index] = FloatColor(
            gray, gray, gray, base.a
        ).premultiplied()


def afterimage_light(
    mut frame: RenderTarget, mut memory: List[FloatColor], damp: Float32
):
    """Keep the last frame fading under this one: three.js's
    `AfterimageShader`.

    Each channel of the last frame above a tenth is scaled by `damp`, and
    each channel of this frame is the larger of its own and that. The
    result is what the next frame sees as its last. A first frame, or one
    of another size, starts the trail.

    Args:
        frame: The frame, changed in place.
        memory: What the pass saw last, replaced by the result.
        damp: What the last frame is scaled by.
    """
    if len(memory) == len(frame.colors):
        for index in range(len(frame.colors)):  # pragma: no branch
            ref old = memory[index]
            ref new = frame.colors[index]
            frame.colors[index] = FloatColor(
                _trail(new.r, old.r, damp),
                _trail(new.g, old.g, damp),
                _trail(new.b, old.b, damp),
                _trail(new.a, old.a, damp),
            )
    memory = frame.colors.copy()


def _trail(new: Float32, old: Float32, damp: Float32) -> Float32:
    """Return one channel of `AfterimageShader`: the new value, or the
    old one damped when it was above the floor and is still the larger."""
    var kept = Float32(0)
    if old > AFTERIMAGE_FLOOR:
        kept = old * damp
    if kept > new:
        return kept
    return new


def output_light(
    mut frame: RenderTarget, curve: ToneMapping, exposure: Float32
):
    """Apply a tone mapping curve to the light of every pixel that holds
    light: three.js's `OutputPass`, less its encode, which `resolve` does.

    Args:
        frame: The frame, changed in place.
        curve: Which curve; `NO_TONE_MAPPING` changes nothing.
        exposure: What the light is scaled by first.
    """
    if curve == NO_TONE_MAPPING:
        return
    for index in range(len(frame.colors)):  # pragma: no branch
        if frame.data[index]:
            continue
        var base = frame.colors[index].unpremultiplied()
        frame.colors[index] = tone_map(base, curve, exposure).premultiplied()
