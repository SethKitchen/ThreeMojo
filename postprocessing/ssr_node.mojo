# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Screen-space reflections as three.js r186's `SSRNode` draws them, from
`examples/jsm/tsl/display/SSRNode.js`, added over the frame as three.js's
SSR examples add them.

**The march.** Each pixel that holds a surface with some metalness sends
a ray along its reflection, `max_distance` long along the view, cut at
the near plane. The ray is walked across the image a pixel apart, times
`quality`. At each step the frame's depth there is read. Where the ray
has passed behind it, and the point there is within `thickness` of the
ray, the ray hit. A hit on a surface that faces away from the ray is
passed over. A hit further from the pixel's plane than `max_distance`
ends the march.

**The reflection.** A hit reads the frame's color there, times the
metalness, times the square of how much of `max_distance` is left, times
three.js's Fresnel term, `(dot(incident, reflected) + 1) / 2`. The light
is capped at `max_luminance` and scaled by `intensity`. The alpha holds
the distance to the hit, in meters, as the node's does.

**The roughness.** The reflections are copied into a mip chain of five
levels. Each level past the first is a box blur of the reflections, a
level's number of pixels apart. The frame reads the chain at the level
its roughness squared gives, times four, as three.js's `getTextureNode`
reads it.

**The stochastic mode.** With `stochastic` on, each pixel with a surface
draws its ray from the GGX lobe of its roughness, by an analytic noise
that moves each frame. `mirror_bias` pulls the ray toward the mirror
direction. The march takes `quality` times 64 steps, closer together near
the pixel by `step_exponent`, and each step is moved by the noise. Every
hit within `thickness` counts. The hit's color is weighed by the lobe's
Fresnel and shadowing. The alpha holds the distance to the hit times the
lobe's dominant factor. The result is not blurred: a denoiser follows it.

**The environment.** A stochastic ray that hits nothing takes the light
of an `EquirectEnvironment` along itself, times `environment_intensity`,
and an alpha of `ENV_RAY_LENGTH`. A map with distributions is sampled by
the power heuristic. A hit near the image's border fades toward that
light over `screen_edge_fade`, or to black with `screen_edge_fade_black`.

**The history.** With a history and the frame's velocities, a hit adds
the last result where the hit was, times one less its alpha: a second
bounce. three.js subtracts the velocity from the coordinate as it is.
Its reprojection node halves the velocity and turns its y over. This
port keeps three.js's subtraction.

**The refinement.** With `binary_refine` on, a hit is bisected eight times
between its step and the step before, toward where the ray first passes
behind the depth.

**Inputs.** The frame's normal attachment gives the normals and its
`OUTPUT_METAL_ROUGH` attachment the metalness and roughness, as the
examples' `mrt` gives them. The frame has no base color attachment. So a
stochastic lobe's base color is white unless a caller gives one, as the
node's is without a `diffuseNode`.

**What differs from three.js.** A stochastic step before the first has a
negative base under `step_exponent`, which a GPU's `pow` does not define.
That step is the ray's start here. A ray whose end has no place on the
image hits nothing. three.js draws a stochastic ray that points into the
surface again. The sampler gives no such ray, so this port draws once.
"""

from math.matrix4 import Matrix4
from math.cross import cross_vectors
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from math.vector4 import Vector4
from math.utils import mix_delta, rec709_luminance
from postprocessing.display_nodes import scaled_size
from postprocessing.importance_sampled_environment import (
    ENV_RAY_LENGTH,
    EquirectEnvironment,
    GgxReflection,
    ggx_reflection_sample,
    sample_environment_brdf,
    sample_environment_mis,
    specular_dominant_factor,
)
from postprocessing.rnoise import analytic_noise4
from postprocessing.sampling import LightView, u_of, v_of
from postprocessing.screen_space import DepthView
from render.color_math import rgb_channels
from render.framebuffer import FloatColor, TRANSPARENT_BLACK
from render.target import RenderTarget
from std.math import floor, isfinite, max, min, pi, pow, sqrt
from units.si import Length, METER


# The blur chain's levels, three.js's five pushed mipmaps, and the level a
# roughness of one reads.
comptime SSR_NODE_LEVELS = 5
comptime SSR_NODE_TOP_LEVEL = SSR_NODE_LEVELS - 1
# `MAX_STEPS`: the steps a stochastic march takes at a quality of one.
comptime SSR_NODE_MAX_STEPS = 64
# How many times a refined hit is bisected.
comptime SSR_NODE_REFINE_STEPS = 8
# The seeds of the march's noise and of the environment's second sample.
comptime SSR_MARCH_NOISE_SEED = 47
comptime SSR_ENVIRONMENT_NOISE_SEED = 59
# Where the noise index starts again, as three.js's `_noiseIndex` does.
comptime SSR_NOISE_INDEX_LIMIT = 0x7FFFFFFF


struct SsrNodeSettings(ImplicitlyCopyable):
    """What an SSR node pass reads, named as three.js names its uniforms,
    with its defaults."""

    # `maxDistance`: how far a ray reaches, and past which a hit is left.
    var max_distance: Length
    # `thickness`: how far from the ray a surface may be and still be hit.
    var thickness: Length
    # `intensity`: what the reflections are scaled by.
    var intensity: Float32
    # `maxLuminance`: the brightest a reflection may be.
    var max_luminance: Float32
    # `quality`: the share of a pixel's steps the march takes.
    var quality: Float32
    # `blurQuality`: the box blur's reach, in taps each way.
    var blur_quality: Int
    # `resolutionScale`: the reflections' size, a share of the frame's.
    var resolution_scale: Float32
    # `reflectNonMetals`: whether a surface with no metalness reflects.
    var reflect_non_metals: Bool
    # Whether the roughness picks a level of the blur chain: the example
    # passes a `roughnessNode`. Off, the reflections are read as they are.
    var use_roughness: Bool
    # `stochastic`: whether each ray is drawn from the GGX lobe.
    var stochastic: Bool
    # `mirrorBias`: how far a stochastic ray is pulled toward the mirror
    # direction, zero to one.
    var mirror_bias: Float32
    # `stepExponent`: how much closer together a stochastic march's steps
    # are near the pixel. One spaces them evenly.
    var step_exponent: Float32
    # `binaryRefine`: whether a hit is bisected toward the crossing.
    var binary_refine: Bool
    # `screenEdgeFade`: how wide the fade at the image's border is, as a
    # share of the image.
    var screen_edge_fade: Float32
    # `screenEdgeFadeBlack`: whether the fade goes to black, and not to the
    # environment's light.
    var screen_edge_fade_black: Bool
    # `environmentIntensity`: what the environment's light is scaled by.
    var environment_intensity: Float32
    # Whether the pass runs the SSR denoise example's
    # `TemporalReprojectNode` and `RecurrentDenoiseNode` over the
    # stochastic reflections. See `postprocessing.temporal_denoise`.
    var denoise: Bool
    # The noise's frame, three.js's `_noiseIndex`. A composer pass moves it
    # on before each frame.
    var noise_index: Int

    def __init__(out self):
        """Start with three.js's defaults."""
        self.max_distance = Length(1, METER)
        self.thickness = Length(0.1, METER)
        self.intensity = 1
        self.max_luminance = 10
        self.quality = 0.5
        self.blur_quality = 2
        self.resolution_scale = 1
        self.reflect_non_metals = False
        self.use_roughness = True
        self.stochastic = False
        self.mirror_bias = 0.5
        self.step_exponent = 2
        self.binary_refine = False
        self.screen_edge_fade = 0.2
        self.screen_edge_fade_black = False
        self.environment_intensity = Float32(pi)
        self.denoise = False
        self.noise_index = 0


def check_ssr_node(settings: SsrNodeSettings) raises:
    """Refuse settings no SSR node pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If a number is not finite, the distance or the scale is not
            positive, the thickness is negative, the blur's reach is
            negative, or the blur's reach is above 2047. Also if the
            mirror bias is outside zero to one, the step exponent is not
            positive, the border fade, the environment's intensity or the
            noise index is negative, or the pass denoises reflections that
            are not stochastic.
    """
    if not (
        isfinite(settings.max_distance.value)
        and isfinite(settings.thickness.value)
        and isfinite(settings.intensity)
        and isfinite(settings.max_luminance)
        and isfinite(settings.quality)
        and isfinite(settings.resolution_scale)
    ):
        raise Error("An SSR node setting must be finite")
    if settings.max_distance.value <= 0 or settings.resolution_scale <= 0:
        raise Error("An SSR node's distance and scale must be positive")
    if settings.thickness.value < 0 or settings.blur_quality < 0:
        raise Error("An SSR node's thickness and blur must not be negative")
    if settings.blur_quality > 2047:
        raise Error("An SSR blur's reach is larger than this port takes")
    if not (settings.mirror_bias >= 0 and settings.mirror_bias <= 1):
        raise Error("An SSR node's mirror bias is from zero to one")
    if not (settings.step_exponent > 0 and isfinite(settings.step_exponent)):
        raise Error("An SSR node's step exponent must be positive and finite")
    if not (
        settings.screen_edge_fade >= 0 and isfinite(settings.screen_edge_fade)
    ):
        raise Error("An SSR node's border fade must be finite, not negative")
    if not (
        settings.environment_intensity >= 0
        and isfinite(settings.environment_intensity)
    ):
        raise Error(
            "An SSR node's environment intensity must be finite, not negative"
        )
    if settings.noise_index < 0:
        raise Error("An SSR node's noise index must not be negative")
    if settings.denoise and not settings.stochastic:
        raise Error("An SSR node denoises its stochastic reflections only")


def next_noise_index(index: Int) -> Int:
    """Return the noise index of the next frame, as three.js's
    `updateBefore` moves `_noiseIndex` on.

    Args:
        index: This frame's index.

    Returns:
        One more, starting again at 2147483647.
    """
    return (index + 1) % SSR_NOISE_INDEX_LIMIT


struct SsrNodeFrame(ImplicitlyCopyable):
    """The views and numbers one frame's march reads."""

    var color: LightView
    var normals: LightView
    var metal_rough: LightView
    var width: Int
    var height: Int
    var camera_world: Matrix4
    var projection: Matrix4
    var perspective: Bool
    var near: Float32
    var far: Float32
    # The surfaces' base color, three.js's `diffuseNode`, read only when
    # `has_diffuse` is on.
    var diffuse: LightView
    var has_diffuse: Bool
    # The last result, `(rgb, share)`, and the frame's velocities in red
    # and green, three.js's `historyTexture` and `velocityTexture`. Read
    # only when `has_history` is on.
    var history: LightView
    var velocity: LightView
    var has_history: Bool

    def __init__(
        out self,
        color: LightView,
        normals: LightView,
        metal_rough: LightView,
        width: Int,
        height: Int,
        camera_world: Matrix4,
        projection: Matrix4,
        near: Float32,
        far: Float32,
    ):
        """Gather a frame's inputs, with no base color and no history.

        Args:
            color: The frame, straight.
            normals: The view-space normals, in red, green and blue.
            metal_rough: The metalness in red and the roughness in green.
            width: The reflections' width in pixels.
            height: Their height.
            camera_world: The camera's world matrix.
            projection: The camera's projection.
            near: The camera's near distance, in meters.
            far: Its far distance.
        """
        self.color = color
        self.normals = normals
        self.metal_rough = metal_rough
        self.width = width
        self.height = height
        self.camera_world = camera_world
        self.projection = projection
        self.perspective = projection.elements[11] != 0
        self.near = near
        self.far = far
        self.diffuse = color
        self.has_diffuse = False
        self.history = color
        self.velocity = color
        self.has_history = False

    def with_diffuse(self, diffuse: LightView) -> Self:
        """Return the frame with a base color, three.js's `diffuseNode`.

        Args:
            diffuse: The surfaces' base color, in red, green and blue.

        Returns:
            The frame, whose stochastic lobes that color tints.
        """
        var out = self
        out.diffuse = diffuse
        out.has_diffuse = True
        return out

    def with_history(self, history: LightView, velocity: LightView) -> Self:
        """Return the frame with a history, as three.js's `setHistory`
        gives it one.

        Args:
            history: The last result, `(rgb, share)`.
            velocity: The frame's velocities, in red and green.

        Returns:
            The frame, whose hits add a second bounce.
        """
        var out = self
        out.history = history
        out.velocity = velocity
        out.has_history = True
        return out


def _normal_at(view: LightView, u: Float32, v_down: Float32) -> Vector3:
    """Return the normal at a place, bilinear and made unit length."""
    var tap = view.sample(u, 1 - v_down)
    var n = Vector3(tap.r, tap.g, tap.b)
    var size = n.length()
    if size == 0:
        return n
    return n * (1 / size)


def _view_z(frame: SsrNodeFrame, depth: Float32) -> Float32:
    """Return the view z of a window depth: three.js's
    `perspectiveDepthToViewZ` or `orthographicDepthToViewZ`."""
    if frame.perspective:
        return (frame.near * frame.far) / (
            (frame.far - frame.near) * depth - frame.far
        )
    return depth * (frame.near - frame.far) - frame.near


def screen_border_factor(
    u: Float32, v: Float32, border_width: Float32
) -> Float32:
    """Return three.js's `computeScreenBorderFactor`: how much of a
    reflection is kept near the image's border.

    Args:
        u: Across, zero to one.
        v: Down or up, zero to one.
        border_width: How wide the fade is, as a share of the image. It
            is at least a ten-thousandth.

    Returns:
        Zero at the border and one from `border_width` inward: two
        smoothsteps of the distance to the nearest edge, to the power of
        an eighth.
    """
    var border = max(border_width, Float32(1e-4))
    var edge = min(min(u, 1 - u), min(v, 1 - v))
    var t = smoothstep(0, border, edge)
    return pow(smoothstep(0, 1, t), Float32(0.125))


@fieldwise_init
struct _SsrRay(ImplicitlyCopyable):
    """One pixel's ray, in the camera's space and across the image."""

    # The pixel's surface and the ray's end: three.js's `viewPosition` and
    # `d1viewPosition`.
    var here: Vector3
    var far_end: Vector3
    # Where the ray starts on the image, in pixels, and one step along it.
    var d0x: Float32
    var d0y: Float32
    var step_x: Float32
    var step_y: Float32
    # How many steps the march counts, `totalStep`.
    var total: Int
    # The ray's longer side on the image, in pixels, at least one.
    var length: Float32
    # The noise that moves a stochastic step, `noise.z`.
    var jitter: Float32


@fieldwise_init
struct _SsrHit(ImplicitlyCopyable):
    """Where a march ended."""

    # One if the ray hit, and zero if not.
    var found: Int
    # The hit's texture coordinate, down from the top, and its depth.
    var u: Float32
    var v: Float32
    var depth: Float32
    # The ray's share at the step before the hit and at the hit.
    var low: Float32
    var high: Float32


def _ray_z(frame: SsrNodeFrame, ray: _SsrRay, s: Float32) -> Float32:
    """Return the ray's view z at a share of its length: three.js's
    `reflectRayZAt`, linear in one over z under a perspective camera."""
    if frame.perspective:
        var recip_near = 1 / ray.here.z
        var recip_far = 1 / ray.far_end.z
        return 1 / (recip_near + s * (recip_far - recip_near))
    return ray.here.z + s * (ray.far_end.z - ray.here.z)


def _refine(
    frame: SsrNodeFrame, view: DepthView, ray: _SsrRay, hit: _SsrHit
) -> _SsrHit:
    """Bisect a hit between its step and the step before, toward where
    the ray first passes behind the depth: three.js's `binaryRefine`."""
    var w = Float32(frame.width)
    var h = Float32(frame.height)
    var low = hit.low
    var high = hit.high
    for _ in range(SSR_NODE_REFINE_STEPS):  # pragma: no branch
        var mid = (low + high) * 0.5
        var along = mid * Float32(ray.total)
        var d = view.depth_at(
            (ray.d0x + ray.step_x * along) / w,
            1 - (ray.d0y + ray.step_y * along) / h,
        )
        if _ray_z(frame, ray, mid) <= _view_z(frame, d):
            high = mid
        else:
            low = mid
    var along = high * Float32(ray.total)
    var u = (ray.d0x + ray.step_x * along) / w
    var v = (ray.d0y + ray.step_y * along) / h
    return _SsrHit(1, u, v, view.depth_at(u, 1 - v), low, high)


def _with_history(
    frame: SsrNodeFrame, u: Float32, v_down: Float32, color: FloatColor
) -> FloatColor:
    """Return a hit's color with the last result where the hit was added:
    three.js's `reprojectHitPointHistory`."""
    if not frame.has_history:
        return color
    var moved = frame.velocity.sample(u, 1 - v_down)
    var bounce = frame.history.sample(u - moved.r, 1 - (v_down - moved.g))
    var decay = 1 - bounce.a
    return FloatColor(
        color.r + bounce.r * decay,
        color.g + bounce.g * decay,
        color.b + bounce.b * decay,
        color.a,
    )


def _mirror_pixel(
    frame: SsrNodeFrame,
    view: DepthView,
    x: Int,
    y: Int,
    settings: SsrNodeSettings,
) -> FloatColor:
    """Return one pixel of the node's mirror reflections: one ray along
    the reflection, a step a pixel."""
    var w = Float32(frame.width)
    var h = Float32(frame.height)
    # The node's `uv`, down from the top.
    var u = (Float32(x) + 0.5) / w
    var v_down = (Float32(y) + 0.5) / h
    var depth = view.depth_at(u, 1 - v_down)
    if depth >= 1:
        return TRANSPARENT_BLACK
    var here = view.position(u, 1 - v_down, depth)
    var world = frame.camera_world.transform_point(here)
    var normal = _normal_at(frame.normals, u, v_down)
    var incident = Vector3(0, 0, -1)
    if frame.perspective:
        incident = here * (1 / here.length())
    var metalness = frame.metal_rough.sample(u, 1 - v_down).r
    if not settings.reflect_non_metals and metalness <= 0:
        return TRANSPARENT_BLACK
    # GLSL's `reflect`, made unit length.
    var reflected = incident - normal * (2 * normal.dot(incident))
    reflected = reflected * (1 / reflected.length())
    var reach = settings.max_distance.value / (-incident).dot(normal)
    var far_end = here + reflected * reach
    if frame.perspective and far_end.z > -frame.near:
        var t = (-frame.near - here.z) / reflected.z
        far_end = here + reflected * t
    var d0x = u * w
    var d0y = v_down * h
    var clip_x = frame.projection.transform_point(far_end)
    var d1x = (clip_x.x * 0.5 + 0.5) * w
    var d1y = (1 - (clip_x.y * 0.5 + 0.5)) * h
    var x_len = d1x - d0x
    var y_len = d1y - d0y
    # A ray whose end has no place on the image, a surface seen edge on,
    # reflects nothing: its step count would mean nothing.
    if not (isfinite(x_len) and isfinite(y_len)):
        return TRANSPARENT_BLACK
    var quality = min(max(settings.quality, 0), 1)
    var total = max(Int(max(abs(x_len), abs(y_len)) * quality), 1)
    var step_x = x_len / Float32(total)
    var step_y = y_len / Float32(total)
    var recip_near = 1 / here.z
    var recip_far = 1 / far_end.z
    # An `Int` and not a `Bool`: a flag raised in a loop and read after it
    # hangs the compiler; see the wiki's "The Mojo compiler hang".
    var found = 0
    var hit_u = Float32(0)
    var hit_v = Float32(0)
    var hit_depth = Float32(0)
    var hit_step = 0
    for i in range(1, total):
        var s = Float32(i) / Float32(total)
        var sx = d0x + step_x * Float32(i)
        var sy = d0y + step_y * Float32(i)
        if sx < 0 or sx > w or sy < 0 or sy > h:
            break
        var su = sx / w
        var sv = sy / h
        var d = view.depth_at(su, 1 - sv)
        var scene_z = _view_z(frame, d)
        var ray_z: Float32
        if frame.perspective:
            ray_z = 1 / (recip_near + s * (recip_far - recip_near))
        else:
            ray_z = here.z + s * (far_end.z - here.z)
        if ray_z > scene_z:
            continue
        var there = view.position(su, 1 - sv, d)
        var away = (
            cross_vectors(there - here, there - far_end).length()
            / (far_end - here).length()
        )
        var beside = view.position(su + 1 / w, 1 - sv, d)
        var tk = max((beside.x - there.x) * 3, settings.thickness.value)
        if away > tk:
            continue
        var facing = _normal_at(frame.normals, su, sv)
        if reflected.dot(facing) >= 0:
            continue
        if normal.dot(there) - normal.dot(here) > settings.max_distance.value:
            break
        found = 1
        hit_u = su
        hit_v = sv
        hit_depth = d
        hit_step = i
        break
    if found == 0:
        return TRANSPARENT_BLACK
    if settings.binary_refine:
        var refined = _refine(
            frame,
            view,
            _SsrRay(here, far_end, d0x, d0y, step_x, step_y, total, 1, 0),
            _SsrHit(
                1,
                hit_u,
                hit_v,
                hit_depth,
                Float32(hit_step - 1) / Float32(total),
                Float32(hit_step) / Float32(total),
            ),
        )
        hit_u = refined.u
        hit_v = refined.v
        hit_depth = refined.depth
    var hit = view.position(hit_u, 1 - hit_v, hit_depth)
    var plane_distance = normal.dot(hit) - normal.dot(here)
    # The march left each hit past the ray's reach. A refined hit can be
    # past it, and reflects nothing.
    if plane_distance > settings.max_distance.value:
        return TRANSPARENT_BLACK
    var world_distance = (
        world - frame.camera_world.transform_point(hit)
    ).length()
    var seen = _with_history(
        frame, hit_u, hit_v, frame.color.sample(hit_u, 1 - hit_v)
    )
    var ratio = 1 - plane_distance / settings.max_distance.value
    var fresnel = (incident.dot(reflected) + 1) / 2
    var weight = metalness * ratio * ratio * fresnel
    var r = seen.r * weight
    var g = seen.g * weight
    var b = seen.b * weight
    var light = max(rec709_luminance(r, g, b), 1e-4)
    var cap = min(settings.max_luminance / light, 1) * settings.intensity
    return FloatColor(
        max(r * cap, 0),
        max(g * cap, 0),
        max(b * cap, 0),
        max(world_distance, 0),
    )


def _ray_fraction(
    ray: _SsrRay, settings: SsrNodeSettings, index: Float32
) -> Float32:
    """Return how far along a stochastic ray a step is, zero to one:
    three.js's `sampleFraction`.

    It is the step's share, moved by the noise, to the power of
    `step_exponent`, and at least a pixel a step. A negative share has no
    power on a GPU, and reads as the pixel's floor here."""
    var floor_share = index / ray.length
    var base = (index + (ray.jitter - 0.5)) / Float32(ray.total)
    if base < 0:
        return floor_share
    return max(pow(base, settings.step_exponent), floor_share)


def _scatter_march(
    frame: SsrNodeFrame,
    view: DepthView,
    ray: _SsrRay,
    settings: SsrNodeSettings,
) -> _SsrHit:
    """Walk a stochastic ray across the image until it passes behind the
    depth, within the thickness of the surface there."""
    var w = Float32(frame.width)
    var h = Float32(frame.height)
    # An `Int` and not a `Bool`, as in `_mirror_pixel`.
    var found = 0
    var hit_u = Float32(0)
    var hit_v = Float32(0)
    var hit_depth = Float32(0)
    var low = Float32(0)
    var high = Float32(0)
    for i in range(1, ray.total):
        var s = _ray_fraction(ray, settings, Float32(i))
        var along = s * Float32(ray.total)
        var sx = ray.d0x + ray.step_x * along
        var sy = ray.d0y + ray.step_y * along
        if sx < 0 or sx > w or sy < 0 or sy > h:
            break
        var su = sx / w
        var sv = sy / h
        var d = view.depth_at(su, 1 - sv)
        if _ray_z(frame, ray, s) > _view_z(frame, d):
            continue
        var there = view.position(su, 1 - sv, d)
        var away = (
            cross_vectors(there - ray.here, there - ray.far_end).length()
            / (ray.far_end - ray.here).length()
        )
        var beside = view.position(su + 1 / w, 1 - sv, d)
        var tk = max((beside.x - there.x) * 3, settings.thickness.value)
        if away > tk:
            continue
        found = 1
        hit_u = su
        hit_v = sv
        hit_depth = d
        low = _ray_fraction(ray, settings, Float32(i - 1))
        high = s
        break
    return _SsrHit(found, hit_u, hit_v, hit_depth, low, high)


def _scatter_lobe(
    frame: SsrNodeFrame,
    normal: Vector3,
    view_dir: Vector3,
    surface: FloatColor,
    u: Float32,
    v_down: Float32,
    noise: Vector4,
    settings: SsrNodeSettings,
) -> GgxReflection:
    """Return a stochastic pixel's ray, drawn from its GGX lobe.

    three.js draws a ray that points into the surface again, with other
    numbers. The sampler bounds its cap so that no ray does: the
    reflection's cosine with the normal is `2 (v.h) (h.n) - v.n`, and the
    bound keeps that at zero or above. So this port draws once."""
    var xi_y = mix_delta(noise.y, 0, settings.mirror_bias * sqrt(noise.w))
    var albedo = Vector3(1, 1, 1)
    if frame.has_diffuse:
        albedo = rgb_channels(frame.diffuse.sample(u, 1 - v_down))
    return ggx_reflection_sample(
        normal, view_dir, surface.g, surface.r, albedo, noise.x, xi_y
    )


def _environment_light(
    frame: SsrNodeFrame,
    environment: Optional[EquirectEnvironment],
    lobe: GgxReflection,
    normal: Vector3,
    view_dir: Vector3,
    x: Int,
    y: Int,
    settings: SsrNodeSettings,
) -> Vector3:
    """Return the environment's light along a stochastic ray, times
    `environment_intensity`: three.js's `sampleEnvReflection`. Black
    without an environment."""
    if not environment:
        return Vector3(0, 0, 0)
    ref env = environment.value()
    if len(env.marginal) > 0:
        var xi = analytic_noise4(
            x, y, settings.noise_index, SSR_ENVIRONMENT_NOISE_SEED
        )
        return (
            sample_environment_mis(
                env,
                frame.camera_world,
                lobe.reflect_dir,
                normal,
                view_dir,
                lobe.alpha,
                lobe.f0,
                xi.z,
                xi.w,
            )
            * settings.environment_intensity
        )
    return (
        sample_environment_brdf(
            env,
            frame.camera_world,
            lobe.reflect_dir,
            normal,
            view_dir,
            lobe.alpha,
            lobe.f0,
        )
        * settings.environment_intensity
    )


def _scatter_hit_light(
    frame: SsrNodeFrame,
    view: DepthView,
    hit: _SsrHit,
    here: Vector3,
    normal: Vector3,
    view_dir: Vector3,
    surface: FloatColor,
    lobe: GgxReflection,
    x: Int,
    y: Int,
    settings: SsrNodeSettings,
    environment: Optional[EquirectEnvironment],
) -> FloatColor:
    """Return what a stochastic ray's hit gives, before the luminance cap:
    the color there, faded at the image's border and weighed by the lobe,
    and the distance to the hit times the lobe's dominant factor."""
    var there = view.position(hit.u, 1 - hit.v, hit.depth)
    var world = frame.camera_world.transform_point(here)
    var distance = (
        world - frame.camera_world.transform_point(there)
    ).length() * specular_dominant_factor(lobe.n_dot_v, surface.g)
    var gathered = rgb_channels(
        _with_history(frame, hit.u, hit.v, frame.color.sample(hit.u, 1 - hit.v))
    )
    if settings.screen_edge_fade_black:
        gathered = gathered * screen_border_factor(
            hit.u, hit.v, settings.screen_edge_fade
        )
    else:
        var glossiness = 1 - min(surface.g / 0.25, Float32(1))
        var kept = screen_border_factor(
            hit.u, hit.v, settings.screen_edge_fade * glossiness
        )
        if kept < 1:
            var past = _environment_light(
                frame, environment, lobe, normal, view_dir, x, y, settings
            )
            gathered = past + (gathered - past) * kept
    return FloatColor(
        gathered.x * lobe.sample_weight.x,
        gathered.y * lobe.sample_weight.y,
        gathered.z * lobe.sample_weight.z,
        distance,
    )


def _scatter_pixel(
    frame: SsrNodeFrame,
    view: DepthView,
    x: Int,
    y: Int,
    settings: SsrNodeSettings,
    environment: Optional[EquirectEnvironment],
) -> FloatColor:
    """Return one pixel of the node's stochastic reflections: one ray
    drawn from the pixel's GGX lobe, a fixed count of steps."""
    var w = Float32(frame.width)
    var h = Float32(frame.height)
    var u = (Float32(x) + 0.5) / w
    var v_down = (Float32(y) + 0.5) / h
    var depth = view.depth_at(u, 1 - v_down)
    if depth >= 1:
        return TRANSPARENT_BLACK
    var here = view.position(u, 1 - v_down, depth)
    var normal = _normal_at(frame.normals, u, v_down)
    var incident = Vector3(0, 0, -1)
    if frame.perspective:
        incident = here * (1 / here.length())
    var view_dir = -incident
    view_dir.normalize()
    var surface = frame.metal_rough.sample(u, 1 - v_down)
    var noise = analytic_noise4(
        x, y, settings.noise_index, SSR_MARCH_NOISE_SEED
    )
    var lobe = _scatter_lobe(
        frame, normal, view_dir, surface, u, v_down, noise, settings
    )
    var reflected = lobe.reflect_dir
    var reach = settings.max_distance.value / (-incident).dot(normal)
    var far_end = here + reflected * reach
    if frame.perspective and far_end.z > -frame.near:
        var t = (-frame.near - here.z) / reflected.z
        far_end = here + reflected * t
    var d0x = u * w
    var d0y = v_down * h
    var clip_x = frame.projection.transform_point(far_end)
    var x_len = (clip_x.x * 0.5 + 0.5) * w - d0x
    var y_len = (1 - (clip_x.y * 0.5 + 0.5)) * h - d0y
    var hit = _SsrHit(0, 0, 0, 0, 0, 0)
    # A ray whose end has no place on the image hits nothing.
    if isfinite(x_len) and isfinite(y_len):
        var quality = min(max(settings.quality, 0), 1)
        var total = Int(max(quality * Float32(SSR_NODE_MAX_STEPS), Float32(1)))
        var ray = _SsrRay(
            here,
            far_end,
            d0x,
            d0y,
            x_len / Float32(total),
            y_len / Float32(total),
            total,
            max(max(abs(x_len), abs(y_len)), Float32(1)),
            noise.z,
        )
        hit = _scatter_march(frame, view, ray, settings)
        if hit.found == 1 and settings.binary_refine:
            hit = _refine(frame, view, ray, hit)
    var out: FloatColor
    if hit.found == 1:
        out = _scatter_hit_light(
            frame,
            view,
            hit,
            here,
            normal,
            view_dir,
            surface,
            lobe,
            x,
            y,
            settings,
            environment,
        )
    else:
        var beyond = _environment_light(
            frame, environment, lobe, normal, view_dir, x, y, settings
        )
        if settings.screen_edge_fade_black:
            beyond = beyond * screen_border_factor(
                u, v_down, settings.screen_edge_fade
            )
        out = FloatColor(beyond.x, beyond.y, beyond.z, ENV_RAY_LENGTH)
    var light = max(rec709_luminance(out.r, out.g, out.b), 1e-4)
    var cap = min(settings.max_luminance / light, 1) * settings.intensity
    return FloatColor(
        max(out.r * cap, 0),
        max(out.g * cap, 0),
        max(out.b * cap, 0),
        max(out.a, 0),
    )


def ssr_node_pixel(
    frame: SsrNodeFrame,
    view: DepthView,
    x: Int,
    y: Int,
    settings: SsrNodeSettings,
    environment: Optional[EquirectEnvironment] = None,
) -> FloatColor:
    """Return one pixel of `SSRNode`'s reflections, unblurred.

    Args:
        frame: The frame's views and numbers.
        view: The frame's depth.
        x: The column of the reflections.
        y: The row, down from the top.
        settings: The pass's settings.
        environment: The map a stochastic ray reads where it hits nothing,
            or none.

    Returns:
        The reflected light and, in alpha, the distance to the hit. Zero
        where there is no surface. A mirror ray also gives zero where
        there is no metalness or no hit. A stochastic ray that hits
        nothing gives the environment's light and `ENV_RAY_LENGTH`.
    """
    if settings.stochastic:
        return _scatter_pixel(frame, view, x, y, settings, environment)
    return _mirror_pixel(frame, view, x, y, settings)


def ssr_node_blur(
    source: LightView, width: Int, height: Int, size: Int, separation: Int
) raises -> List[FloatColor]:
    """Return three.js's `boxBlur` of raw values at another size: the mean
    of a square of `2 * size + 1` taps a side, `separation` of the
    source's pixels apart, at least one.

    Args:
        source: The values, read bilinear as they are.
        width: The output's width in pixels.
        height: Its height.
        size: How many taps each way.
        separation: How many source pixels apart the taps are.

    Returns:
        The blur, row by row from the top.

    Raises:
        Error: If a side is below one, the pixel count does not fit, or
            the reach is above 2047 taps from the center.
    """
    if size > 2047:
        raise Error("An SSR blur's reach is larger than this port takes")
    if width < 1 or height < 1:
        raise Error("An SSR blur must be at least one pixel each way")
    if width > Int.MAX // height:
        raise Error("An SSR blur is larger than this port builds")
    var sep = Float32(max(separation, 1))
    var step_u = sep / Float32(source.width)
    var step_v = sep / Float32(source.height)
    var out = List[FloatColor](capacity=width * height)
    # Two loops here and two in `_box_mean`: four in one function is the
    # nesting that hangs codegen; see `render.target._resolve_blocks`.
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            out.append(
                _box_mean(
                    source,
                    u_of(x, width),
                    v_of(y, height),
                    size,
                    step_u,
                    step_v,
                )
            )
    return out^


def _box_mean(
    source: LightView,
    u: Float32,
    v: Float32,
    size: Int,
    step_u: Float32,
    step_v: Float32,
) -> FloatColor:
    """Return the mean of the square of taps around one place, raw.

    Summed in four floats: a `FloatColor` rebuilt in this nest of loops
    hangs codegen."""
    var r = Float32(0)
    var g = Float32(0)
    var b = Float32(0)
    var a = Float32(0)
    for i in range(-size, size + 1):  # pragma: no branch
        for j in range(-size, size + 1):  # pragma: no branch
            # The node's `uv` grows down.
            var tap = source.sample(
                u + Float32(i) * step_u, v - Float32(j) * step_v
            )
            r += tap.r
            g += tap.g
            b += tap.b
            a += tap.a
    var count = Float32((2 * size + 1) * (2 * size + 1))
    return FloatColor(r / count, g / count, b / count, a / count)


def ssr_node_signal(
    frame: RenderTarget,
    view: DepthView,
    camera_world: Matrix4,
    settings: SsrNodeSettings,
    environment: Optional[EquirectEnvironment] = None,
    history: List[FloatColor] = List[FloatColor](),
) raises -> List[FloatColor]:
    """Return `SSRNode`'s reflections as the node's own target holds
    them, unblurred, at `resolution_scale` of the frame's size.

    Args:
        frame: The frame. It must have a normal attachment and an
            `OUTPUT_METAL_ROUGH` one.
        view: The frame's depth, and the camera's projection.
        camera_world: The camera's world matrix.
        settings: The pass's settings.
        environment: The map a stochastic ray reads where it hits nothing,
            or none.
        history: The last result at the frame's size, `(rgb, share)`, for
            a second bounce, or empty for none. The frame must then have
            a velocity attachment.

    Returns:
        The reflections `(rgb, distance)`, row by row from the top.

    Raises:
        Error: If the frame lacks either attachment, or a history does
            not have one entry a pixel, or the frame has no velocities
            for it.
    """
    if not (frame.has_normals() and frame.has_metal_roughs()):
        raise Error(
            "An SSR node reads the frame's normal and metalness attachments"
        )
    var w = frame.width
    var h = frame.height
    var bounces = len(history) > 0
    if bounces and not (len(history) == w * h and frame.has_velocities()):
        raise Error(
            "An SSR node's history needs one entry a pixel and the frame's"
            " velocities"
        )
    var straight = List[FloatColor](capacity=w * h)
    var turned = List[FloatColor](capacity=w * h)
    var surfaces = List[FloatColor](capacity=w * h)
    var moved = List[FloatColor]()
    for slot in range(w * h):  # pragma: no branch
        straight.append(frame.straight_at(slot))
        var n = frame.normals[slot]
        turned.append(FloatColor(n.x, n.y, n.z, 0))
        var s = frame.metal_roughs[slot]
        surfaces.append(FloatColor(s.x, s.y, 0, 0))
        if bounces:
            var velocity = frame.velocities[slot]
            moved.append(FloatColor(velocity.x, velocity.y, 0, 0))
    var width = scaled_size(w, settings.resolution_scale)
    var height = scaled_size(h, settings.resolution_scale)
    var inputs = SsrNodeFrame(
        LightView(straight, w, h),
        LightView(turned, w, h),
        LightView(surfaces, w, h),
        width,
        height,
        camera_world,
        view.projection,
        view.near,
        view.far,
    )
    if bounces:
        inputs = inputs.with_history(
            LightView(history, w, h), LightView(moved, w, h)
        )
    var reflections = List[FloatColor](capacity=width * height)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            reflections.append(
                ssr_node_pixel(inputs, view, x, y, settings, environment)
            )
    _ = straight^
    _ = turned^
    _ = surfaces^
    _ = moved^
    return reflections^


def ssr_node_add(
    mut frame: RenderTarget, light: List[FloatColor], width: Int, height: Int
) raises:
    """Add an image's red, green and blue to the frame, read bilinear at
    each of the frame's pixels: three.js's `scenePassColor.add( ssr.rgb )`.

    Args:
        frame: The frame.
        light: The image, row by row from the top.
        width: The image's width in pixels.
        height: Its height.

    Raises:
        Error: If a size is below one, or the image does not have one
            entry a pixel.
    """
    if width < 1 or height < 1 or len(light) != width * height:
        raise Error("An SSR node adds an image of one entry a pixel")
    var w = frame.width
    var h = frame.height
    var source = LightView(light, width, height)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var added = source.sample(u_of(x, w), v_of(y, h))
            var slot = y * w + x
            var was = frame.straight_at(slot)
            frame.colors[slot] = FloatColor(
                was.r + added.r, was.g + added.g, was.b + added.b, was.a
            ).premultiplied()
            frame.data[slot] = False


def ssr_node_light(
    mut frame: RenderTarget,
    view: DepthView,
    camera_world: Matrix4,
    settings: SsrNodeSettings,
    environment: Optional[EquirectEnvironment] = None,
) raises:
    """Add `SSRNode`'s reflections to the frame. Mirror reflections are
    read through their blur chain at each pixel's roughness where the
    settings ask. Stochastic reflections are added as they are.

    Args:
        frame: The frame. It must have a normal attachment and an
            `OUTPUT_METAL_ROUGH` one.
        view: The frame's depth, and the camera's projection.
        camera_world: The camera's world matrix.
        settings: The pass's settings.
        environment: The map a stochastic ray reads where it hits nothing,
            or none.

    Raises:
        Error: If the frame lacks either attachment.
    """
    var reflections = ssr_node_signal(
        frame, view, camera_world, settings, environment
    )
    var w = frame.width
    var h = frame.height
    var straight = List[FloatColor](capacity=w * h)
    var surfaces = List[FloatColor](capacity=w * h)
    for slot in range(w * h):  # pragma: no branch
        straight.append(frame.straight_at(slot))
        var s = frame.metal_roughs[slot]
        surfaces.append(FloatColor(s.x, s.y, 0, 0))
    var width = scaled_size(w, settings.resolution_scale)
    var height = scaled_size(h, settings.resolution_scale)
    # three.js blurs a mirror's reflections only: `stochastic === false`
    # and a `roughnessNode`.
    var blurred = settings.use_roughness and not settings.stochastic
    # The chain: the reflections, then a blur a level's pixels apart at
    # each smaller level.
    var levels = List[List[FloatColor]]()
    var sizes = List[Int]()
    for level in range(SSR_NODE_LEVELS):  # pragma: no branch
        if level == 0:
            levels.append(reflections.copy())
        elif blurred:
            var level_w = max(width >> level, 1)
            var level_h = max(height >> level, 1)
            levels.append(
                ssr_node_blur(
                    LightView(reflections, width, height),
                    level_w,
                    level_h,
                    settings.blur_quality,
                    level,
                )
            )
        sizes.append(max(width >> level, 1))
        sizes.append(max(height >> level, 1))
    var surface_view = LightView(surfaces, w, h)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var u = u_of(x, w)
            var v = v_of(y, h)
            var added: FloatColor
            if blurred:
                var rough = surface_view.sample(u, v).g
                var lod = min(
                    max(rough * rough * Float32(SSR_NODE_TOP_LEVEL), 0),
                    Float32(SSR_NODE_TOP_LEVEL),
                )
                var low = Int(floor(lod))
                var high = min(low + 1, SSR_NODE_TOP_LEVEL)
                var t = lod - Float32(low)
                var a = LightView(
                    levels[low], sizes[low * 2], sizes[low * 2 + 1]
                ).sample(u, v)
                var b = LightView(
                    levels[high], sizes[high * 2], sizes[high * 2 + 1]
                ).sample(u, v)
                var mixed = a.mix(b, t)
                added = FloatColor(mixed.r, mixed.g, mixed.b, 0)
            else:
                added = LightView(reflections, width, height).sample(u, v)
            var slot = y * w + x
            var was = straight[slot]
            frame.colors[slot] = FloatColor(
                was.r + added.r, was.g + added.g, was.b + added.b, was.a
            ).premultiplied()
            frame.data[slot] = False
    _ = straight^
    _ = surfaces^
    _ = reflections^
    _ = levels^
