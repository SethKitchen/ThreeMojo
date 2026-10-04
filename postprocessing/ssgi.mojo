# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Screen-space global illumination and screen-space shadows: three.js
r186's `SSGINode` and `SSSNode`, from `examples/jsm/tsl/display/`.

**SSGI.** Each pixel with a surface cuts the hemisphere over it into
`slice_count` slices round the view. Along each slice it walks
`step_count` taps each way, farther apart as `exp_factor` says. Each tap
is a point of the depth. The angles from the pixel to the tap's front and
to its back, `thickness` behind it, cover a span of 32 sectors of the
slice, a bit field. The sectors a tap covers first, and no tap before it,
occlude the pixel and send it the tap's light: the tap's color, times the
cosine at the pixel and at the tap, times the share of the sectors. The
ambient occlusion is the share of the sectors covered, to the power of
`ao_intensity`. The indirect light is scaled by `gi_intensity` and held
at a luminance of seven.

**SSS.** Each pixel with a surface walks a ray toward the main light,
`max_distance` long, across the image a pixel apart, times `quality`. A
step where the ray is behind the depth by less than `thickness` shadows
the pixel by `shadow_intensity`.

**The coordinate.** Both nodes run on three.js's WebGPU `uv()`, which
grows down, and its `screenCoordinate`, pixels from the top left. So do
these functions.

**What the composer does with them.** three.js's examples mix the AO and
the indirect light with the scene pass and its diffuse color. The frame
has no diffuse color attachment, so the SSGI pass takes the frame's own
color for it: `frame * ao + frame * gi`. The SSS pass multiplies the
frame's light by the shadow. The AO is stored in eight bits, as three.js's
`RedFormat` target stores it. The indirect light is kept as a float, where
three.js packs it into 11, 11 and 10 bits.

## Numerical range correction

Finite norm-dependent directions and lengths use scale-safe arithmetic.
Extreme finite results can differ from direct three.js r180 arithmetic.
See `docs/wiki/Norm-consumers.md` for the changed operations, retained
limits, and explicit zero and nonfinite rules.
"""

from math.norm import length2
from animation.keyframe_track import LightIndex
from core.scene import NO_PARENT, Scene
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from postprocessing.display_nodes import luminance_of
from postprocessing.filter_nodes import interleaved_gradient_noise
from postprocessing.sampling import LightView
from postprocessing.screen_space import DepthView, glsl_rand
from render.framebuffer import FloatColor
from render.target import RenderTarget, UNSIGNED_BYTE_TARGET, stored
from std.bit import pop_count
from std.math import acos, ceil, cos, floor, isfinite, max, min, pi, pow, sin
from std.math import sqrt
from units.si import Length, METER


# `MAX_RAY`: how many sectors a slice's bit field has.
comptime SSGI_SECTORS = 32
# `_temporalRotations` over 360, and `_spatialOffsets`: what each frame of
# the temporal filter turns the slices and offsets the taps by.
comptime SSGI_ROTATIONS = SIMD[DType.float32, 8](
    60.0 / 360.0,
    300.0 / 360.0,
    180.0 / 360.0,
    240.0 / 360.0,
    120.0 / 360.0,
    0,
    0,
    0,
)
comptime SPATIAL_OFFSETS = SIMD[DType.float32, 4](0, 0.5, 0.25, 0.75)
# The luminance the indirect light is held at, `maxLuminance`.
comptime SSGI_MAX_LUMINANCE = Float32(7)


struct SsgiSettings(ImplicitlyCopyable):
    """What an SSGI pass reads, named as three.js names its uniforms, with
    its defaults."""

    var slice_count: Int
    var step_count: Int
    var ao_intensity: Float32
    var gi_intensity: Float32
    var radius: Float32
    var use_screen_space_sampling: Bool
    var exp_factor: Float32
    var thickness: Length
    var use_linear_thickness: Bool
    var backface_lighting: Float32
    var use_temporal_filtering: Bool
    # three.js's `frameId`, which the temporal filter reads: the composer
    # counts the pass's frames.
    var frame_id: Int
    # Whether the pass runs the SSGI example's denoiser, three.js's
    # `TemporalReprojectNode` and `RecurrentDenoiseNode`, over the raw
    # signal before it is mixed in. See `postprocessing.temporal_denoise`.
    var denoise: Bool

    def __init__(out self):
        """Start with three.js's defaults."""
        self.slice_count = 1
        self.step_count = 12
        self.ao_intensity = 1
        self.gi_intensity = 10
        self.radius = 12
        self.use_screen_space_sampling = True
        self.exp_factor = 2
        self.thickness = Length(1, METER)
        self.use_linear_thickness = False
        self.backface_lighting = 0
        self.use_temporal_filtering = True
        self.frame_id = 0
        self.denoise = False


def check_ssgi(settings: SsgiSettings) raises:
    """Refuse settings no SSGI pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If a count is below one, a number is not finite, the radius
            or the step's growth is not positive, or the frame count is
            negative.
    """
    if settings.slice_count < 1 or settings.step_count < 1:
        raise Error("An SSGI pass needs a slice and a step")
    var finite = (
        isfinite(settings.ao_intensity)
        and isfinite(settings.gi_intensity)
        and isfinite(settings.radius)
        and isfinite(settings.exp_factor)
        and isfinite(settings.thickness.value)
        and isfinite(settings.backface_lighting)
    )
    if not finite:
        raise Error("An SSGI pass setting must be finite")
    if not (settings.radius > 0 and settings.exp_factor > 0):
        raise Error("An SSGI pass's radius and step growth must be positive")
    if settings.frame_id < 0:
        raise Error("An SSGI pass's frame count must not be negative")


# --- reading the frame, down from the top -------------------------------------


struct ScreenInputs(Movable):
    """What the two nodes read: the frame's light, straight, its depth, and
    its view-space normals, each on a texture coordinate that grows down."""

    var colors: List[FloatColor]
    var normals: List[FloatColor]
    var view: DepthView
    var width: Int
    var height: Int

    def __init__(out self, frame: RenderTarget, var view: DepthView) raises:
        """Gather a frame's inputs.

        Args:
            frame: The frame. Its normal attachment gives the normals; a
                frame without one takes them from the depth.
            view: The frame's depth.

        Raises:
            Error: If the depth view is not the frame's size.
        """
        if view.width != frame.width or view.height != frame.height:
            raise Error("An SSGI pass's depth must be the frame's size")
        self.width = frame.width
        self.height = frame.height
        self.colors = List[FloatColor](capacity=frame.width * frame.height)
        self.normals = List[FloatColor](capacity=frame.width * frame.height)
        var kept = frame.has_normals()
        var rebuilt = List[Vector3]()
        if not kept:
            rebuilt = view.normals()
        for slot in range(frame.width * frame.height):  # pragma: no branch
            self.colors.append(frame.straight_at(slot))
            var n = rebuilt[slot] if not kept else frame.normals[slot]
            self.normals.append(FloatColor(n.x, n.y, n.z, 0))
        self.view = view^

    def depth(self, u: Float32, v_down: Float32) -> Float32:
        """Return the window depth at a coordinate, nearest.

        Args:
            u: Across.
            v_down: Down.

        Returns:
            The window depth.
        """
        return self.view.depth_at(u, 1 - v_down)

    def position(self, u: Float32, v_down: Float32, depth: Float32) -> Vector3:
        """Return three.js's `getViewPosition`.

        Args:
            u: Across.
            v_down: Down.
            depth: The window depth.

        Returns:
            The view-space point.
        """
        return self.view.position(u, 1 - v_down, depth)

    def normal(self, u: Float32, v_down: Float32) -> Vector3:
        """Return the normal read bilinear and made unit length.

        Args:
            u: Across.
            v_down: Down.

        Returns:
            The view-space normal, or zero where none was written.
        """
        var view = LightView(self.normals, self.width, self.height)
        var tap = view.tap(
            u * Float32(self.width) - 0.5, v_down * Float32(self.height) - 0.5
        )
        var n = Vector3(tap.r, tap.g, tap.b)
        var size = n.length()
        if size == 0:
            return n
        return n * (1 / size)

    def color(self, u: Float32, v_down: Float32) -> FloatColor:
        """Return the light read bilinear, straight.

        Args:
            u: Across.
            v_down: Down.

        Returns:
            The color.
        """
        var view = LightView(self.colors, self.width, self.height)
        return view.tap(
            u * Float32(self.width) - 0.5, v_down * Float32(self.height) - 0.5
        )


# --- SSGINode ----------------------------------------------------------------


def gtao_fast_acos(value: Float32) -> Float32:
    """Return three.js's `GTAOFastAcos` of one number: an arc cosine to
    within a hundredth of a radian.

    Args:
        value: The cosine, from minus one to one.

    Returns:
        The angle, in radians.
    """
    var angle = abs(value) * Float32(-0.156583) + Float32(pi / 2)
    angle *= sqrt(1 - abs(value))
    if value >= 0:
        return angle
    return Float32(pi) - angle


def glsl_sign(x: Float32) -> Float32:
    """Return GLSL's `sign`.

    Args:
        x: The number.

    Returns:
        One, minus one, or zero for zero.
    """
    if x > 0:
        return 1
    if x < 0:
        return -1
    return 0


def occluded_sectors(start: Float32, span: Float32) -> UInt32:
    """Return the bit field of sectors a tap covers, before the ones taken
    already are masked off: three.js's `angleHorizonBitfield` shifted by
    `startHorizonInt`.

    Args:
        start: The span's first sector, as a share of the slice.
        span: How much of the slice it covers.

    Returns:
        The bits.
    """
    var first = UInt32(Int(start * Float32(SSGI_SECTORS)))
    var count = Int(ceil(span * Float32(SSGI_SECTORS)))
    if count <= 0:
        return 0
    # A span that covers a sector starts inside the slice, so the shift is
    # below 32.
    var field = UInt32(0xFFFFFFFF) >> UInt32(SSGI_SECTORS - count)
    return field << first


struct SsgiFrame(ImplicitlyCopyable):
    """The numbers one frame's SSGI reads, three.js's uniforms."""

    var step_radius: Float32
    var radius_vs: Float32
    var temporal_direction: Float32
    var temporal_offset: Float32

    def __init__(
        out self,
        step_radius: Float32,
        radius_vs: Float32,
        temporal_direction: Float32,
        temporal_offset: Float32,
    ):
        """Gather a frame's numbers.

        Args:
            step_radius: The step's reach, `stepRadius`.
            radius_vs: `radiusVS`.
            temporal_direction: `_temporalDirection`.
            temporal_offset: `_temporalOffset`.
        """
        self.step_radius = step_radius
        self.radius_vs = radius_vs
        self.temporal_direction = temporal_direction
        self.temporal_offset = temporal_offset


def ssgi_temporal(settings: SsgiSettings) -> Tuple[Float32, Float32]:
    """Return the slices' turn and the taps' offset for a frame: three.js's
    `_temporalDirection` and `_temporalOffset`, or one and one with the
    temporal filter off.

    Args:
        settings: The frame's count and whether the filter is on.

    Returns:
        The turn and the offset.
    """
    if not settings.use_temporal_filtering:
        return (Float32(1), Float32(1))
    return (
        SSGI_ROTATIONS[settings.frame_id % 6],
        SPATIAL_OFFSETS[settings.frame_id % 4],
    )


def _horizon(
    inputs: ScreenInputs,
    right: Bool,
    mut occluded: UInt32,
    frame: SsgiFrame,
    here: Vector3,
    step_u: Float32,
    step_v: Float32,
    initial_step: Float32,
    u: Float32,
    v: Float32,
    view_dir: Vector3,
    normal: Vector3,
    n: Float32,
    settings: SsgiSettings,
) -> Vector3:
    """Return one side of a slice's light: three.js's `horizonSampling`."""
    var uv_dir_u = Float32(1) if right else Float32(-1)
    var uv_dir_v = Float32(-1) if right else Float32(1)
    var sampling = Float32(1) if right else Float32(-1)
    var color = Vector3(0, 0, 0)
    var backface = settings.backface_lighting
    # At least one step, so the loop runs.
    for i in range(settings.step_count):  # pragma: no branch
        var fi = Float32(i)
        var offset = (
            pow(
                abs(frame.step_radius * (fi + initial_step) / frame.radius_vs),
                settings.exp_factor,
            )
            * frame.radius_vs
        )
        var reach = max(offset, fi + 1)
        var su = u + step_u * reach * uv_dir_u
        var sv = v + step_v * reach * uv_dir_v
        if su <= 0 or sv <= 0 or su >= 1 or sv >= 1:
            break
        var there = inputs.position(su, sv, inputs.depth(su, sv))
        var to_tap = there - here
        to_tap.normalize()
        var multiplier = Float32(1)
        if settings.use_linear_thickness:
            multiplier = min(max(-there.z / inputs.view.far, 0), 1) * 100
        var to_back = (
            there - view_dir * (multiplier * settings.thickness.value) - here
        )
        to_back.normalize()
        var front = gtao_fast_acos(min(max(to_tap.dot(view_dir), -1), 1))
        var back = gtao_fast_acos(min(max(to_back.dot(view_dir), -1), 1))
        var h_front = min(
            max((sampling * -front - (n - Float32(pi / 2))) / Float32(pi), 0),
            1,
        )
        var h_back = min(
            max((sampling * -back - (n - Float32(pi / 2))) / Float32(pi), 0),
            1,
        )
        var low = h_back if right else h_front
        var high = h_front if right else h_back
        var field = occluded_sectors(low, high - low) & ~occluded
        occluded = occluded | field
        var covered = Int(pop_count(field))
        if covered == 0:
            continue
        var light = inputs.color(su, sv)
        if luminance_of(light.r, light.g, light.b) <= 0.001:
            continue
        var facing = min(max(normal.dot(to_tap), 0), 1)
        if facing <= 0.001:
            continue
        var tap_normal = inputs.normal(su, sv)
        var toward = tap_normal.dot(-to_tap)
        var lit: Float32
        if backface > 0 and tap_normal.dot(view_dir) > 0:
            lit = abs(toward) * backface if toward < 0 else abs(toward)
        else:
            lit = min(max(toward, 0), 1)
        var share = Float32(covered) / Float32(SSGI_SECTORS) * facing * lit
        color = color + Vector3(light.r, light.g, light.b) * share
    return color


def ssgi_pixel(
    inputs: ScreenInputs, x: Int, y: Int, settings: SsgiSettings
) -> FloatColor:
    """Return one pixel of three.js's `SSGINode`.

    Args:
        inputs: The frame's light, depth and normals.
        x: The column.
        y: The row, down from the top.
        settings: The pass's settings.

    Returns:
        The indirect light in red, green and blue and the ambient
        occlusion in alpha: white with no light where the pixel holds no
        surface, as three.js's target is cleared.
    """
    var w = inputs.width
    var h = inputs.height
    var u = (Float32(x) + 0.5) / Float32(w)
    var v = (Float32(y) + 0.5) / Float32(h)
    var depth = inputs.depth(u, v)
    if depth >= 1:
        return FloatColor(1, 1, 1, 1)
    var here = inputs.position(u, v, depth)
    var normal = inputs.normal(u, v)
    var view_dir = -here
    view_dir.normalize()
    var temporal = ssgi_temporal(settings)
    var noise_offset = Float32(((y - x) & 3)) * 0.25
    var noise_direction = interleaved_gradient_noise(
        Float32(x) + 0.5, Float32(y) + 0.5
    )
    var jitter = temporal[0] * 0.02
    var shifted = noise_offset + temporal[1]
    var initial_step = (shifted - floor(shifted)) + glsl_rand(
        (u + jitter) * 2 - 1, (v + jitter) * 2 - 1
    )
    var steps = Float32(settings.step_count)
    var step_radius: Float32
    if settings.use_screen_space_sampling:
        step_radius = settings.radius * (Float32(w) / 2) / 16
    else:
        var half_proj = Float32(h) * inputs.view.projection.elements[5] / 4
        step_radius = max(settings.radius * half_proj / -here.z, steps)
    step_radius /= steps + 1
    var radius_vs = max(Float32(1), steps - 1) * step_radius
    var frame = SsgiFrame(step_radius, radius_vs, temporal[0], temporal[1])
    var slices = Float32(settings.slice_count)
    var ao = Float32(0)
    var color = Vector3(0, 0, 0)
    for i in range(settings.slice_count):  # pragma: no branch
        var angle = (Float32(i) + noise_direction + temporal[0]) * (
            Float32(pi) / slices
        )
        var slice_dir = Vector3(cos(angle), sin(angle), 0)
        var step_u = slice_dir.x / Float32(w)
        var step_v = slice_dir.y / Float32(h)
        var plane_normal = slice_dir
        plane_normal.cross(view_dir)
        plane_normal.normalize()
        var tangent = view_dir
        tangent.cross(plane_normal)
        var projected = normal - plane_normal * normal.dot(plane_normal)
        var projected_unit = projected
        projected_unit.normalize()
        var cos_n = min(max(projected_unit.dot(view_dir), -1), 1)
        var n = -glsl_sign(projected.dot(tangent)) * acos(cos_n)
        var occluded = UInt32(0)
        color = color + _horizon(
            inputs,
            True,
            occluded,
            frame,
            here,
            step_u,
            step_v,
            initial_step,
            u,
            v,
            view_dir,
            normal,
            n,
            settings,
        )
        color = color + _horizon(
            inputs,
            False,
            occluded,
            frame,
            here,
            step_u,
            step_v,
            initial_step,
            u,
            v,
            view_dir,
            normal,
            n,
            settings,
        )
        ao += Float32(Int(pop_count(occluded))) / Float32(SSGI_SECTORS)
    ao /= slices
    ao = min(max(pow(1 - min(max(ao, 0), 1), settings.ao_intensity), 0), 1)
    color = color * (settings.gi_intensity / slices)
    var shown = luminance_of(color.x, color.y, color.z)
    if shown > SSGI_MAX_LUMINANCE:
        color = color * (SSGI_MAX_LUMINANCE / shown)
    return FloatColor(
        color.x, color.y, color.z, stored(ao, UNSIGNED_BYTE_TARGET)
    )


def ssgi_signal(
    inputs: ScreenInputs, settings: SsgiSettings
) -> List[FloatColor]:
    """Return `SSGINode`'s two targets at every pixel, row by row from the
    top: the indirect light in red, green and blue and the AO in alpha.

    Args:
        inputs: The frame's light, depth and normals.
        settings: The pass's settings.

    Returns:
        One value a pixel.
    """
    var out = List[FloatColor](capacity=inputs.width * inputs.height)
    for y in range(inputs.height):  # pragma: no branch
        for x in range(inputs.width):  # pragma: no branch
            out.append(ssgi_pixel(inputs, x, y, settings))
    return out^


def ssgi_composite(mut frame: RenderTarget, signal: List[FloatColor]):
    """Mix the SSGI into the frame: `frame * ao + frame * gi`, the frame's
    color standing in for the example's diffuse color.

    Args:
        frame: The frame, changed in place.
        signal: The indirect light and the AO at every pixel.
    """
    for slot in range(len(frame.colors)):  # pragma: no branch
        var color = frame.straight_at(slot)
        var gi = signal[slot]
        frame.colors[slot] = FloatColor(
            color.r * gi.a + color.r * gi.r,
            color.g * gi.a + color.g * gi.g,
            color.b * gi.a + color.b * gi.b,
            color.a,
        ).premultiplied()
        frame.data[slot] = False


# --- SSSNode -----------------------------------------------------------------


struct SssSettings(ImplicitlyCopyable):
    """What an SSS pass reads, named as three.js names its uniforms, with
    its defaults."""

    # The main light, one of the scene's `lights`.
    var light: LightIndex
    var max_distance: Length
    var thickness: Length
    var shadow_intensity: Float32
    var quality: Float32
    var use_temporal_filtering: Bool
    var frame_id: Int

    def __init__(out self):
        """Start with three.js's defaults and the scene's first light."""
        self.light = LightIndex(0)
        self.max_distance = Length(0.1, METER)
        self.thickness = Length(0.01, METER)
        self.shadow_intensity = 1
        self.quality = 0.5
        self.use_temporal_filtering = False
        self.frame_id = 0


def check_sss(settings: SssSettings) raises:
    """Refuse settings no SSS pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the light index is negative, a number is not finite, or
            the frame count is negative.
    """
    if not settings.light.is_valid():
        raise Error("An SSS pass's light must not be negative")
    var finite = (
        isfinite(settings.max_distance.value)
        and isfinite(settings.thickness.value)
        and isfinite(settings.shadow_intensity)
        and isfinite(settings.quality)
    )
    if not finite:
        raise Error("An SSS pass setting must be finite")
    if settings.frame_id < 0:
        raise Error("An SSS pass's frame count must not be negative")


def sss_light_direction(
    scene: Scene, light: LightIndex, view: Matrix4
) raises -> Vector3:
    """Return the direction toward a light in the camera's space: three.js's
    `cameraViewMatrix.transformDirection( lightPosition - lightTargetPosition )`.

    Args:
        scene: The scene.
        light: Which of its lights.
        view: The camera's view matrix.

    Returns:
        The unit direction.

    Raises:
        Error: If the scene has no such light, or its node or target is not
            in the scene.
    """
    if light.value >= len(scene.lights):
        raise Error("An SSS pass's light must be one of the scene's")
    ref shining = scene.lights[light.value]
    var aimed = Vector3(0, 0, 0)
    if shining.target != NO_PARENT:
        aimed = scene.world_position(shining.target)
    var toward = scene.world_position(shining.node) - aimed
    toward.transform_direction(view)
    return toward


def _view_z_of(view: DepthView, depth: Float32) -> Float32:
    """Return three.js's `perspectiveDepthToViewZ` or
    `orthographicDepthToViewZ`, by the camera."""
    if view.perspective:
        return (view.near * view.far) / (
            (view.far - view.near) * depth - view.far
        )
    return (view.near - view.far) * depth - view.near


def sss_pixel(
    inputs: ScreenInputs,
    x: Int,
    y: Int,
    toward: Vector3,
    settings: SssSettings,
) -> Float32:
    """Return one pixel of three.js's `SSSNode`.

    Args:
        inputs: The frame's depth.
        x: The column.
        y: The row, down from the top.
        toward: The direction toward the light, in the camera's space.
        settings: The pass's settings.

    Returns:
        One less the shadow: one where lit, and one where the pixel holds
        no surface, as three.js's target is cleared to white.
    """
    var w = Float32(inputs.width)
    var h = Float32(inputs.height)
    var u = (Float32(x) + 0.5) / w
    var v = (Float32(y) + 0.5) / h
    var depth = inputs.depth(u, v)
    if depth >= 1:
        return 1
    var start = inputs.position(u, v, depth)
    var end = start + toward * settings.max_distance.value
    var d0x = Float32(x) + 0.5
    var d0y = Float32(y) + 0.5
    var clip = inputs.view.projection.transform_point(end)
    var d1x = (clip.x * 0.5 + 0.5) * w
    var d1y = (1 - (clip.y * 0.5 + 0.5)) * h
    var x_len = d1x - d0x
    var y_len = d1y - d0y
    var total = length2(x_len, y_len)
    var steps = Int(
        max(abs(x_len), abs(y_len)) * min(max(settings.quality, 0), 1)
    )
    var x_span = x_len / Float32(steps)
    var y_span = y_len / Float32(steps)
    var temporal = Float32(0)
    var frame = Float32(0)
    if settings.use_temporal_filtering:
        temporal = SPATIAL_OFFSETS[settings.frame_id % 4]
        frame = Float32(settings.frame_id)
    var noise = interleaved_gradient_noise(d0x, d0y) + temporal
    var offset = (noise - floor(noise)) + glsl_rand(u + frame, v + frame)
    for i in range(steps):
        var px = d0x + x_span * (Float32(i) + offset)
        var py = d0y + y_span * (Float32(i) + offset)
        if px < 0 or px > w or py < 0 or py > h:
            break
        var there = _view_z_of(inputs.view, inputs.depth(px / w, py / h))
        var dx = px - d0x
        var dy = py - d0y
        var s = length2(dx, dy) / total
        var ray_z = start.z + (end.z - start.z) * s
        var delta = there - ray_z
        if delta > 0 and delta < settings.thickness.value:
            return 1 - settings.shadow_intensity
    return 1


def sss_light(
    mut frame: RenderTarget,
    inputs: ScreenInputs,
    toward: Vector3,
    settings: SssSettings,
):
    """Multiply the frame's light by `SSSNode`'s shadow.

    Args:
        frame: The frame, changed in place.
        inputs: The frame's depth.
        toward: The direction toward the light, in the camera's space.
        settings: The pass's settings.
    """
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var slot = y * frame.width + x
            var shade = sss_pixel(inputs, x, y, toward, settings)
            var color = frame.colors[slot]
            frame.colors[slot] = FloatColor(
                color.r * shade, color.g * shade, color.b * shade, color.a
            )
            frame.data[slot] = False
