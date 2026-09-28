# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The denoiser three.js r186 runs after its screen-space passes:
`TemporalReprojectNode` and `RecurrentDenoiseNode`, from
`examples/jsm/tsl/display/`, in their diffuse mode.

**The reprojection.** Each pixel with a surface reads the history where
its velocity says it was, from four texels. Each texel weighs by its
bilinear share and by how well the last frame's surface there matches:
its distance from the pixel's plane and its normal. The history is
clipped toward the box of the 3 by 3 neighbors' mean and deviation, in
YCoCg and scaled down by luminance. The confidence falls with the clip,
with fast motion, and where the reprojection stretches the image, which
three.js measures with the derivatives of the history's coordinate. The
result keeps the history's color and, in alpha, one over the frames it
holds, at most `max_frames`.

**The denoise.** Each pixel then takes eight taps on a Vogel disk in the
plane of its surface, turned by an analytic noise and scaled by its AO,
its depth and how many frames it holds. Each tap weighs by its raw
signal's luminance, the alpha source, its distance from the pixel's
plane and its normal. The disk shrinks and skews toward the taps that
weigh most. The denoised history and the denoised raw signal are mixed by
Karis's weights, the raw signal taking one over the frames.

**The loop.** The denoised result is the next frame's history, as the
example's `setHistoryTexture( denoise )` makes it. The first frame's
history is the raw signal, and its last depth, normals and camera are its
own.

**What differs from three.js.** The derivatives are the difference
across each 2 by 2 quad, as a GPU's fine derivatives are. A normalized
zero vector is zero here, where a GPU gives a NaN; so a surface that faces
the camera takes the denoise's second tangent, as three.js means it to.
The specular mode, which reprojects the hit point along the ray length an
SSR pass leaves in alpha, is not ported.
"""

from math.matrix4 import Matrix4
from math.smoothstep import smoothstep
from math.vector2 import Vector2
from math.vector3 import Vector3
from postprocessing.display_nodes import exp_f, luminance_of
from postprocessing.sampling import LightView
from postprocessing.screen_space import DepthView
from render.framebuffer import FloatColor
from std.math import atan, cos, floor, isfinite, max, min, pi, pow, sin
from std.math import sqrt


# three.js's `EPSILON`.
comptime TSL_EPSILON = Float32(1e-6)
# `ENV_RAY_LENGTH_THRESHOLD`: a ray length past this is the environment.
comptime ENV_RAY_LENGTH_THRESHOLD = Float32(1e3)
# `VARIANCE_CLIP_LUMA_SCALE`.
comptime VARIANCE_CLIP_LUMA_SCALE = Float32(10)
# `KERNEL_SAMPLES`, `NOISE_ROTATION_SEED`, `WORLD_RADIUS_SCALE`,
# `AO_EDGE_STOPPING_BIAS`, `AGGRESSIVITY_RADIUS_MIN`, `EXP_WEIGHT_SCALE`
# and `NORMAL_ENCODING_ERROR`.
comptime KERNEL_SAMPLES = 8
comptime NOISE_ROTATION_SEED = 83
comptime WORLD_RADIUS_SCALE = Float32(0.1)
comptime AO_EDGE_STOPPING_BIAS = Float32(0.05)
comptime AGGRESSIVITY_RADIUS_MIN = Float32(0.001)
comptime EXP_WEIGHT_SCALE = Float32(4)
comptime NORMAL_ENCODING_ERROR = Float32(1.5 / 255.0)
# `FLICKER_COV_GATE_MIN` and `FLICKER_COV_GATE_MAX`.
comptime FLICKER_COV_GATE_MIN = Float32(0.1)
comptime FLICKER_COV_GATE_MAX = Float32(2)


@fieldwise_init
struct AlphaSource(Equatable, ImplicitlyCopyable, Writable):
    """What the raw signal's alpha holds, three.js's `alphaSource`, as a
    type rather than a string. It does not stop `AlphaSource(7)`, which
    `check_temporal_denoise` refuses."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three sources.

        Returns:
            Whether the value names a source.
        """
        return self.value >= 0 and self.value <= 2


# `'raylength'`: the distance to what a ray hit, three.js's default.
comptime RAY_LENGTH_ALPHA = AlphaSource(0)
# `'ao'`: the ambient occlusion, as an SSGI signal holds it.
comptime AO_ALPHA = AlphaSource(1)
# Anything else: the alpha is not read.
comptime NO_ALPHA = AlphaSource(2)


struct TemporalDenoiseSettings(Copyable, Movable):
    """What the two nodes read, named as three.js names their uniforms, with
    their defaults, and what the loop keeps between frames."""

    # `TemporalReprojectNode`'s `maxVelocityLength`, `maxFrames`,
    # `clampIntensity` and `flickerSuppression`.
    var max_velocity_length: Float32
    var max_frames: Float32
    var clamp_intensity: Float32
    var flicker_suppression: Float32
    # `RecurrentDenoiseNode`'s `lumaPhi`, `depthPhi`, `normalPhi`,
    # `radius`, `alphaPhi`, `adapt`, `smoothDisocclusions`, `strength`,
    # `alphaSource`, `flickerSuppression` and `adaptiveTrust`.
    var luma_phi: Float32
    var depth_phi: Float32
    var normal_phi: Float32
    var radius: Float32
    var alpha_phi: Float32
    var adapt: Float32
    var smooth_disocclusions: Bool
    var strength: Float32
    var alpha_source: AlphaSource
    var denoise_flicker_suppression: Float32
    var adaptive_trust: Float32
    # The noise's frame, three.js's `frameId`.
    var frame_id: Int
    # The last denoised result, `(rgb, 1 / frames)`, and its size.
    var history: List[FloatColor]
    var history_width: Int
    var history_height: Int
    # The last frame's window depth and view-space normals.
    var previous_depth: List[Float32]
    var previous_normals: List[Vector3]
    # The camera's world, view, projection and projection inverse, this
    # frame and the last: `bindTemporalCameraUniforms`.
    var world: Matrix4
    var view: Matrix4
    var projection: Matrix4
    var projection_inverse: Matrix4
    var previous_world: Matrix4
    var previous_view: Matrix4
    var previous_projection_inverse: Matrix4

    def __init__(out self):
        """Start with three.js's defaults, the SSGI's AO in alpha, and no
        history."""
        self.max_velocity_length = 128
        self.max_frames = 32
        self.clamp_intensity = 1
        self.flicker_suppression = 1
        self.luma_phi = 5
        self.depth_phi = 5
        self.normal_phi = 5
        self.radius = 5
        self.alpha_phi = 1
        self.adapt = 0.5
        self.smooth_disocclusions = True
        self.strength = 0.25
        self.alpha_source = AO_ALPHA
        self.denoise_flicker_suppression = 1
        self.adaptive_trust = 0
        self.frame_id = 0
        self.history = List[FloatColor]()
        self.history_width = 0
        self.history_height = 0
        self.previous_depth = List[Float32]()
        self.previous_normals = List[Vector3]()
        self.world = Matrix4()
        self.view = Matrix4()
        self.projection = Matrix4()
        self.projection_inverse = Matrix4()
        self.previous_world = Matrix4()
        self.previous_view = Matrix4()
        self.previous_projection_inverse = Matrix4()


def check_temporal_denoise(settings: TemporalDenoiseSettings) raises:
    """Refuse settings no denoiser could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the alpha source is none of the three, a number is not
            finite, the velocity length or the frame limit is not
            positive, or the frame count is negative.
    """
    if not settings.alpha_source.is_valid():
        raise Error("A denoiser's alpha source must be one of the three")
    if not (
        isfinite(settings.clamp_intensity)
        and isfinite(settings.flicker_suppression)
        and isfinite(settings.luma_phi)
        and isfinite(settings.depth_phi)
        and isfinite(settings.normal_phi)
        and isfinite(settings.radius)
        and isfinite(settings.alpha_phi)
        and isfinite(settings.adapt)
        and isfinite(settings.strength)
        and isfinite(settings.denoise_flicker_suppression)
        and isfinite(settings.adaptive_trust)
    ):
        raise Error("A denoiser setting must be finite")
    if not (
        settings.max_velocity_length > 0
        and isfinite(settings.max_velocity_length)
        and settings.max_frames >= 1
        and isfinite(settings.max_frames)
    ):
        raise Error("A denoiser's velocity length and frame limit are positive")
    if settings.frame_id < 0:
        raise Error("A denoiser's frame count must not be negative")


# --- shared arithmetic -------------------------------------------------------


def inverse_view_normal(normal: Vector3, view: Matrix4) -> Vector3:
    """Return three.js's `transformNormalByInverseViewMatrix`: a view-space
    normal turned into the world, `normalize( vec4( n, 0 ) * view )`.

    Args:
        normal: The normal, in the camera's space.
        view: The camera's view matrix.

    Returns:
        The world-space normal.
    """
    ref e = view.elements
    var turned = Vector3(
        normal.x * e[0] + normal.y * e[1] + normal.z * e[2],
        normal.x * e[4] + normal.y * e[5] + normal.z * e[6],
        normal.x * e[8] + normal.y * e[9] + normal.z * e[10],
    )
    turned.normalize()
    return turned


def view_position(
    u: Float32, v_down: Float32, depth: Float32, inverse: Matrix4
) -> Vector3:
    """Return three.js's `getViewPosition` on a coordinate that grows down.

    Args:
        u: Across.
        v_down: Down.
        depth: The window depth.
        inverse: The projection's inverse.

    Returns:
        The view-space point.
    """
    return inverse.transform_point(
        Vector3(u * 2 - 1, (1 - v_down) * 2 - 1, depth * 2 - 1)
    )


def screen_position(point: Vector3, projection: Matrix4) -> Vector2:
    """Return three.js's `getScreenPosition`: a view-space point's texture
    coordinate, down from the top.

    Args:
        point: The point, in the camera's space.
        projection: The projection.

    Returns:
        The coordinate.
    """
    var clip = projection.transform_point(point)
    return Vector2(clip.x * 0.5 + 0.5, 1 - (clip.y * 0.5 + 0.5))


def to_ycocg(r: Float32, g: Float32, b: Float32) -> Vector3:
    """Return a color in TemporalReprojectNode's YCoCg.

    Args:
        r: Red.
        g: Green.
        b: Blue.

    Returns:
        Luma, orange and green chroma.
    """
    return Vector3(
        r * 0.25 + g * 0.5 + b * 0.25,
        r * 0.5 - b * 0.5,
        -r * 0.25 + g * 0.5 - b * 0.25,
    )


def from_ycocg(c: Vector3) -> Vector3:
    """Return a YCoCg color in red, green and blue.

    Args:
        c: Luma, orange and green chroma.

    Returns:
        The color.
    """
    return Vector3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z)


def clip_to_aabb(history: Vector3, low: Vector3, high: Vector3) -> Vector3:
    """Return a point clipped toward the middle of a box, as far as it lies
    outside: three.js's `clipToAABB`.

    Args:
        history: The point.
        low: The box's low corner.
        high: The box's high corner.

    Returns:
        The point, or where the line to it leaves the box.
    """
    var mid = (high + low) * 0.5
    var ext = (high - low) * 0.5 + Vector3(1e-7, 1e-7, 1e-7)
    var off = history - mid
    var most = max(
        abs(off.x / ext.x), max(abs(off.y / ext.y), abs(off.z / ext.z))
    )
    if most > 1:
        return mid + off / most
    return history


def _load(colors: LightView, x: Int, y: Int) -> FloatColor:
    """Return a texel, the edge texel's past the edge: `textureLoad`."""
    return colors.at(
        min(max(x, 0), colors.width - 1), min(max(y, 0), colors.height - 1)
    )


def _floor0(color: FloatColor) -> FloatColor:
    """Return a color with its negative channels raised to zero."""
    return FloatColor(
        max(color.r, 0), max(color.g, 0), max(color.b, 0), max(color.a, 0)
    )


# --- TemporalReprojectNode ---------------------------------------------------


struct ReprojectInputs(Movable):
    """What one frame's reprojection reads: the raw signal, the depth, the
    normals and the velocity, this frame's and the last's."""

    var width: Int
    var height: Int
    var signal: List[FloatColor]
    var history: List[FloatColor]
    var depth: List[Float32]
    var previous_depth: List[Float32]
    var normals: List[Vector3]
    var previous_normals: List[Vector3]
    var velocities: List[Vector2]

    def __init__(
        out self,
        width: Int,
        height: Int,
        var signal: List[FloatColor],
        var history: List[FloatColor],
        var depth: List[Float32],
        var previous_depth: List[Float32],
        var normals: List[Vector3],
        var previous_normals: List[Vector3],
        var velocities: List[Vector2],
    ) raises:
        """Gather a frame's inputs.

        Args:
            width: The frame's width in pixels.
            height: Its height.
            signal: The raw signal, one a pixel, row by row from the top.
            history: The last result, `(rgb, 1 / frames)`.
            depth: This frame's window depth.
            previous_depth: The last frame's.
            normals: This frame's view-space normals.
            previous_normals: The last frame's.
            velocities: This frame's velocities.

        Raises:
            Error: If a list does not have one entry a pixel.
        """
        var count = width * height
        if not (
            len(signal) == count
            and len(history) == count
            and len(depth) == count
            and len(previous_depth) == count
            and len(normals) == count
            and len(previous_normals) == count
            and len(velocities) == count
        ):
            raise Error("A reprojection needs one of each input a pixel")
        self.width = width
        self.height = height
        self.signal = signal^
        self.history = history^
        self.depth = depth^
        self.previous_depth = previous_depth^
        self.normals = normals^
        self.previous_normals = previous_normals^
        self.velocities = velocities^

    def slot(self, x: Int, y: Int) -> Int:
        """Return a texel's slot, the edge texel's past the edge.

        Args:
            x: The column.
            y: The row, down from the top.

        Returns:
            The slot.
        """
        return min(max(y, 0), self.height - 1) * self.width + min(
            max(x, 0), self.width - 1
        )


struct ReprojectCamera(ImplicitlyCopyable):
    """The camera's matrices, this frame and the last:
    `bindTemporalCameraUniforms`."""

    var world: Matrix4
    var view: Matrix4
    var projection_inverse: Matrix4
    var previous_world: Matrix4
    var previous_view: Matrix4
    var previous_projection_inverse: Matrix4

    def __init__(out self, settings: TemporalDenoiseSettings):
        """Take the matrices the loop keeps.

        Args:
            settings: The loop's camera, this frame and the last.
        """
        self.world = settings.world
        self.view = settings.view
        self.projection_inverse = settings.projection_inverse
        self.previous_world = settings.previous_world
        self.previous_view = settings.previous_view
        self.previous_projection_inverse = settings.previous_projection_inverse


def _history_tap(
    inputs: ReprojectInputs,
    camera: ReprojectCamera,
    x: Int,
    y: Int,
    share: Float32,
    world_position: Vector3,
    world_normal: Vector3,
) -> Tuple[FloatColor, Float32, Float32]:
    """Return one texel of the history weighed by how well its surface
    matches: three.js's `sampleBilinearTap`. The color is already weighed.
    """
    var slot = inputs.slot(x, y)
    var color = _floor0(inputs.history[slot])
    var depth = inputs.previous_depth[slot]
    var u = (Float32(min(max(x, 0), inputs.width - 1)) + 0.5) / Float32(
        inputs.width
    )
    var v = (Float32(min(max(y, 0), inputs.height - 1)) + 0.5) / Float32(
        inputs.height
    )
    var seen = view_position(u, v, depth, camera.previous_projection_inverse)
    var world = camera.previous_world.transform_point(seen)
    var normal = inverse_view_normal(
        inputs.previous_normals[slot], camera.previous_view
    )
    var plane = abs((world - world_position).dot(world_normal)) / abs(seen.z)
    var normal_confidence = smoothstep(0.95, 0.999, normal.dot(world_normal))
    var confidence = (1 - smoothstep(0, 0.01, plane)) * normal_confidence
    var weight = share * confidence
    return (
        FloatColor(
            color.r * weight,
            color.g * weight,
            color.b * weight,
            color.a * weight,
        ),
        weight,
        confidence,
    )


def sample_history(
    inputs: ReprojectInputs,
    camera: ReprojectCamera,
    u: Float32,
    v_down: Float32,
    world_position: Vector3,
    world_normal: Vector3,
    fallback: FloatColor,
) -> FloatColor:
    """Return the history at a coordinate from its four texels, each
    weighed by how well its surface matches: three.js's
    `sampleHistory4Tap`.

    Args:
        inputs: The frame's inputs.
        camera: The camera's matrices.
        u: Across.
        v_down: Down.
        world_position: The pixel's surface, in the world.
        world_normal: Its normal, in the world.
        fallback: The raw signal, which stands in where no texel matches.

    Returns:
        The history, `(rgb, 1 / frames)`, or the fallback with an alpha of
        one.
    """
    var px = u * Float32(inputs.width) - 0.5
    var py = v_down * Float32(inputs.height) - 0.5
    var fx0 = floor(px)
    var fy0 = floor(py)
    var ix = Int(fx0)
    var iy = Int(fy0)
    var fx = px - fx0
    var fy = py - fy0
    var t00 = _history_tap(
        inputs, camera, ix, iy, (1 - fx) * (1 - fy), world_position, world_normal
    )
    var t10 = _history_tap(
        inputs, camera, ix + 1, iy, fx * (1 - fy), world_position, world_normal
    )
    var t01 = _history_tap(
        inputs, camera, ix, iy + 1, (1 - fx) * fy, world_position, world_normal
    )
    var t11 = _history_tap(
        inputs, camera, ix + 1, iy + 1, fx * fy, world_position, world_normal
    )
    var total = t00[1] + t10[1] + t01[1] + t11[1]
    if not (total > 0.01):
        return FloatColor(fallback.r, fallback.g, fallback.b, 1)
    return FloatColor(
        (t00[0].r + t10[0].r + t01[0].r + t11[0].r) / total,
        (t00[0].g + t10[0].g + t01[0].g + t11[0].g) / total,
        (t00[0].b + t10[0].b + t01[0].b + t11[0].b) / total,
        (t00[0].a + t10[0].a + t01[0].a + t11[0].a) / total,
    )


def _history_uv(
    inputs: ReprojectInputs, x: Int, y: Int
) -> Vector2:
    """Return where a pixel was, `uv - velocity * (0.5, -0.5)`."""
    var slot = inputs.slot(x, y)
    var moved = inputs.velocities[slot]
    return Vector2(
        (Float32(x) + 0.5) / Float32(inputs.width) - moved.x * 0.5,
        (Float32(y) + 0.5) / Float32(inputs.height) + moved.y * 0.5,
    )


def stretch_confidence(inputs: ReprojectInputs, x: Int, y: Int) -> Float32:
    """Return how little the reprojection stretches the image at a pixel:
    three.js's `reprojectionStretchConfidence`, the smaller singular value
    of the history coordinate's derivatives, in pixels, held at one.

    The derivatives are the differences across the pixel's 2 by 2 quad,
    as a GPU's fine `dFdx` and `dFdy` take them.

    Args:
        inputs: The frame's inputs.
        x: The column.
        y: The row, down from the top.

    Returns:
        The confidence, zero to one.
    """
    var left = x - (x % 2)
    var top = y - (y % 2)
    var here = _history_uv(inputs, left, y)
    var across = _history_uv(inputs, left + 1, y)
    var above = _history_uv(inputs, x, top)
    var below = _history_uv(inputs, x, top + 1)
    var w = Float32(inputs.width)
    var h = Float32(inputs.height)
    var jx = Vector2((across.x - here.x) * w, (across.y - here.y) * h)
    var jy = Vector2((below.x - above.x) * w, (below.y - above.y) * h)
    var det = jx.x * jy.y - jx.y * jy.x
    var fro2 = jx.x * jx.x + jx.y * jx.y + jy.x * jy.x + jy.y * jy.y
    var disc = sqrt(max(fro2 * fro2 * 0.25 - det * det, 0))
    var sig_min = sqrt(max(fro2 * 0.5 - disc, 0))
    return min(max(sig_min, 0), 1)


def _dampened(color: FloatColor, flicker: Float32) -> Vector3:
    """Return a color scaled down by its luminance and in YCoCg, as
    `collectNeighborhood` reads each texel."""
    var scale = (
        luminance_of(color.r, color.g, color.b)
        * flicker
        * VARIANCE_CLIP_LUMA_SCALE
        + 1
    )
    return to_ycocg(color.r / scale, color.g / scale, color.b / scale)


def temporal_reproject_pixel(
    inputs: ReprojectInputs,
    camera: ReprojectCamera,
    x: Int,
    y: Int,
    settings: TemporalDenoiseSettings,
) -> FloatColor:
    """Return one pixel of three.js's `TemporalReprojectNode`, diffuse.

    Args:
        inputs: The frame's inputs.
        camera: The camera's matrices.
        x: The column.
        y: The row, down from the top.
        settings: The node's settings.

    Returns:
        The history, clipped, `(rgb, 1 / frames)`; black with an alpha of
        one where the pixel holds no surface, as the cleared target reads.
    """
    var w = inputs.width
    var h = inputs.height
    var slot = y * w + x
    var depth = inputs.depth[slot]
    if depth >= 1:
        return FloatColor(0, 0, 0, 1)
    var input = _floor0(inputs.signal[slot])
    var flicker = settings.flicker_suppression
    # `collectNeighborhood`: the pixel and its eight neighbors.
    var m1 = _dampened(input, flicker)
    var m2 = Vector3(m1.x * m1.x, m1.y * m1.y, m1.z * m1.z)
    var offsets = SIMD[DType.int32, 16](
        -1, -1, -1, 1, 1, -1, 1, 1, 1, 0, 0, -1, 0, 1, -1, 0
    )
    var view = LightView(inputs.signal, w, h)
    for at in range(8):  # pragma: no branch
        var near = _floor0(
            _load(view, x + Int(offsets[at * 2]), y + Int(offsets[at * 2 + 1]))
        )
        var c = _dampened(near, flicker)
        m1 = m1 + c
        m2 = m2 + Vector3(c.x * c.x, c.y * c.y, c.z * c.z)
    var mean = m1 * (1.0 / 9.0)
    var deviation = Vector3(
        sqrt(max(m2.x / 9 - mean.x * mean.x, 0)),
        sqrt(max(m2.y / 9 - mean.y * mean.y, 0)),
        sqrt(max(m2.z / 9 - mean.z * mean.z, 0)),
    )
    var u = (Float32(x) + 0.5) / Float32(w)
    var v = (Float32(y) + 0.5) / Float32(h)
    var world_normal = inverse_view_normal(inputs.normals[slot], camera.view)
    var seen = view_position(u, v, depth, camera.projection_inverse)
    var world_position = camera.world.transform_point(seen)
    var moved = inputs.velocities[slot]
    var off_x = moved.x * 0.5 * Float32(w)
    var off_y = -moved.y * 0.5 * Float32(h)
    var motion = min(
        max(
            sqrt(off_x * off_x + off_y * off_y) / settings.max_velocity_length,
            0,
        ),
        1,
    )
    var back = _history_uv(inputs, x, y)
    var history = sample_history(
        inputs, camera, back.x, back.y, world_position, world_normal, input
    )
    var confidence = Float32(1)
    var trust = Float32(0)
    var a = max(history.a, TSL_EPSILON)
    var stretch = stretch_confidence(inputs, x, y)
    confidence *= stretch * stretch
    var gamma = 0.5 + 0.5 * (1 - motion) * (1 - motion)
    # `applyVarianceClipping`.
    var low = mean - deviation * gamma
    var high = mean + deviation * gamma
    var scale = (
        luminance_of(history.r, history.g, history.b)
        * flicker
        * VARIANCE_CLIP_LUMA_SCALE
        + 1
    )
    var clipped = from_ycocg(
        clip_to_aabb(
            to_ycocg(history.r / scale, history.g / scale, history.b / scale),
            low,
            high,
        )
    ) * scale
    var clamp_intensity = (
        settings.clamp_intensity
        * max(min(motion * 10, 1), Float32(0.25))
        * (1 + min(max((1 - stretch) + (1 - trust), 0), 1))
    )
    var original = Vector3(history.r, history.g, history.b)
    var mixed = original + (clipped - original) * clamp_intensity
    confidence *= exp_f(-(original - clipped).length() * clamp_intensity * 30)
    confidence *= 1 + (trust * 0.05 + 0.95 - 1) * min(max(motion * 100, 0), 1)
    if confidence < TSL_EPSILON:
        mixed = Vector3(input.r, input.g, input.b)
    var frames = min(1 / a * confidence + 1, settings.max_frames)
    return FloatColor(mixed.x, mixed.y, mixed.z, 1 / frames)


# --- RecurrentDenoiseNode ----------------------------------------------------


def analytic_noise(x: Int, y: Int, index: Int) -> Float32:
    """Return the first channel of three.js's `bindAnalyticNoise` with the
    denoiser's seed: an R4 low-discrepancy sequence over a 32-pixel tile,
    moved each frame.

    Args:
        x: The column.
        y: The row, down from the top.
        index: The frame, three.js's `frameId`.

    Returns:
        A number from zero up to one.
    """
    var at = Float32(index + NOISE_ROTATION_SEED)
    var ox = at * Float32(0.7548776662)
    var oy = at * Float32(0.5698402910)
    var shift_x = floor((ox - floor(ox)) * 32)
    var shift_y = floor((oy - floor(oy)) * 32)
    var cx = Float32(x) + shift_x
    var cy = Float32(y) + shift_y
    cx = cx - floor(cx / 32) * 32
    cy = cy - floor(cy / 32) * 32
    comptime P = 1.32471795724474602596
    var t = (
        cx * Float32(1 / P)
        + cy * Float32(1 / (P * P))
        + Float32(NOISE_ROTATION_SEED)
    )
    var r = t * Float32(P) * Float32(1 / P)
    return r - floor(r)


def vogel_disk(index: Int, radius: Float32) -> Vector2:
    """Return three.js's `vogelDisk` point of eight.

    Args:
        index: Which point, zero to seven.
        radius: The disk's radius.

    Returns:
        The point.
    """
    var i = Float32(index) + 0.5
    var theta = i * Float32(2.399827721492203)
    var r = radius * sqrt(i / 8)
    return Vector2(cos(theta) * r, sin(theta) * r)


def lobe_normal_falloff(
    roughness: Float32, aggressivity: Float32, inv_normal_phi: Float32
) -> Float32:
    """Return three.js's `lobeNormalFalloff`: how sharply the normal weight
    falls as two normals part.

    Args:
        roughness: The surface's roughness.
        aggressivity: How hard the denoise works, zero to one.
        inv_normal_phi: One less `normalPhi`.

    Returns:
        The falloff.
    """
    var start = inv_normal_phi * inv_normal_phi
    var percent = min(
        max(start + (0 - start) * sqrt(aggressivity), Float32(0.1)),
        Float32(0.99),
    )
    var alpha = roughness * roughness
    var tan_half = alpha * sqrt(percent / max(1 - percent, Float32(1e-6)))
    var half_angle = max(atan(tan_half), NORMAL_ENCODING_ERROR)
    var inv = 1 / half_angle
    return inv * inv * (2 * EXP_WEIGHT_SCALE)


def hit_dist_factor(
    ray_length: Float32, view_z: Float32, tan_half_fov: Float32
) -> Float32:
    """Return three.js's `computeHitDistFactor`: a ray length over the
    frustum's height at the pixel's distance, held at one.

    Args:
        ray_length: The ray's length, in meters.
        view_z: The pixel's distance along the view.
        tan_half_fov: The tangent of half the vertical field of view.

    Returns:
        The share, zero to one.
    """
    return min(
        max(ray_length / max(2 * view_z * tan_half_fov, Float32(1e-6)), 0), 1
    )


def karis_blend(
    denoised: Vector3,
    raw: Vector3,
    a: Float32,
    flicker: Float32,
    trust: Float32,
    mean_luma: Float32,
    deviation_luma: Float32,
) -> Vector3:
    """Return three.js's `karisTemporalBlend`: the denoised history and the
    denoised raw signal mixed by their shares, each weighed down by its
    brightness.

    Args:
        denoised: The denoised history.
        raw: The denoised raw signal.
        a: The raw signal's share, one over the frames.
        flicker: `flickerSuppression`.
        trust: `adaptiveTrust`.
        mean_luma: The raw neighbors' mean luminance.
        deviation_luma: Their deviation.

    Returns:
        The blend.
    """
    var cov = deviation_luma / max(mean_luma, Float32(1e-4))
    var suppress = min(max(cov * trust * (1 - a), 0), Float32(0.9))
    var a_trust = a * (1 - suppress)
    var noisy = smoothstep(FLICKER_COV_GATE_MIN, FLICKER_COV_GATE_MAX, cov)
    var effective = flicker * ((1 - trust) + (1 - (1 - trust)) * noisy)
    var w_hist = (1 - a_trust) / (
        luminance_of(denoised.x, denoised.y, denoised.z) * effective * 10 + 1
    )
    var w_raw = a_trust / (luminance_of(raw.x, raw.y, raw.z) * effective * 10 + 1)
    return (denoised * w_hist + raw * w_raw) / max(w_hist + w_raw, TSL_EPSILON)


struct DenoiseInputs(Movable):
    """What one frame's recurrent denoise reads: the reprojected history,
    the raw signal, the depth and the normals, and the camera."""

    var width: Int
    var height: Int
    var history: List[FloatColor]
    var raw: List[FloatColor]
    var depth: List[Float32]
    var normals: List[FloatColor]
    var view: Matrix4
    var projection: Matrix4
    var projection_inverse: Matrix4
    var tan_half_fov: Float32

    def __init__(
        out self,
        width: Int,
        height: Int,
        var history: List[FloatColor],
        var raw: List[FloatColor],
        var depth: List[Float32],
        normals: List[Vector3],
        view: Matrix4,
        projection: Matrix4,
    ) raises:
        """Gather a frame's inputs.

        Args:
            width: The frame's width in pixels.
            height: Its height.
            history: The reprojection's result, `(rgb, 1 / frames)`.
            raw: The raw signal.
            depth: The window depth.
            normals: The view-space normals.
            view: The camera's view matrix.
            projection: Its projection.

        Raises:
            Error: If a list does not have one entry a pixel, or the
                projection cannot be inverted.
        """
        var count = width * height
        if not (
            len(history) == count
            and len(raw) == count
            and len(depth) == count
            and len(normals) == count
        ):
            raise Error("A denoise needs one of each input a pixel")
        if projection.determinant() == 0:
            raise Error("A denoise's projection must be invertible")
        self.width = width
        self.height = height
        self.history = history^
        self.raw = raw^
        self.depth = depth^
        self.normals = List[FloatColor](capacity=count)
        for slot in range(count):  # pragma: no branch
            ref n = normals[slot]
            self.normals.append(FloatColor(n.x, n.y, n.z, 0))
        self.view = view
        self.projection = projection
        self.projection_inverse = projection
        self.projection_inverse.invert()
        # three.js's `tan( fov / 2 )`, from the projection's second column.
        self.tan_half_fov = 1 / projection.elements[5]

    def sample(self, colors: List[FloatColor], u: Float32, v: Float32) -> FloatColor:
        """Return a list read bilinear at a coordinate that grows down,
        held at the edges.

        Args:
            colors: The history, the raw signal or the normals.
            u: Across.
            v: Down.

        Returns:
            The blend.
        """
        return LightView(colors, self.width, self.height).tap(
            u * Float32(self.width) - 0.5, v * Float32(self.height) - 0.5
        )

    def depth_at(self, u: Float32, v: Float32) -> Float32:
        """Return the window depth at a coordinate, nearest.

        Args:
            u: Across.
            v: Down.

        Returns:
            The depth.
        """
        var x = min(max(Int(floor(u * Float32(self.width))), 0), self.width - 1)
        var y = min(
            max(Int(floor(v * Float32(self.height))), 0), self.height - 1
        )
        return self.depth[y * self.width + x]

    def normal(self, u: Float32, v: Float32) -> Vector3:
        """Return the normal read bilinear, as three.js unpacks it, not
        made unit length.

        Args:
            u: Across.
            v: Down.

        Returns:
            The view-space normal.
        """
        var n = self.sample(self.normals, u, v)
        return Vector3(n.r, n.g, n.b)


def _neighborhood(
    inputs: DenoiseInputs,
    u: Float32,
    v: Float32,
    center: FloatColor,
    settings: TemporalDenoiseSettings,
) -> Tuple[Float32, Float32, Float32, Bool]:
    """Return three.js's `getNeighborhoodStats` over the raw signal: the
    mean ray length, the luminance's mean and deviation, and whether a
    ray reached the environment."""
    var rl_sum = Float32(0)
    var rl_weight = Float32(0)
    var mean = Float32(0)
    var m2 = Float32(0)
    var count = Float32(0)
    var env = False
    var du = SIMD[DType.float32, 8](0, -1, 1, 0, 0, 0, 0, 0)
    var dv = SIMD[DType.float32, 8](0, 0, 0, -1, 1, 0, 0, 0)
    for at in range(5):  # pragma: no branch
        var sample = center
        if at > 0:
            sample = _floor0(
                inputs.sample(
                    inputs.raw,
                    u + du[at] / Float32(inputs.width),
                    v + dv[at] / Float32(inputs.height),
                )
            )
        if settings.alpha_source == RAY_LENGTH_ALPHA:
            var rl = sample.a
            if rl > ENV_RAY_LENGTH_THRESHOLD:
                rl = 0.25
                env = True
            var w = 1 / (rl + 0.001)
            rl_sum += rl * w
            rl_weight += w
        if settings.adaptive_trust > 0:
            var luma = luminance_of(sample.r, sample.g, sample.b)
            count += 1
            var delta = luma - mean
            mean += delta / count
            m2 += delta * (luma - mean)
    var average = Float32(1)
    if settings.alpha_source == RAY_LENGTH_ALPHA:
        average = rl_sum / rl_weight
    return (average, mean, sqrt(m2 / max(count, 1)), env)


def recurrent_denoise_pixel(
    inputs: DenoiseInputs,
    x: Int,
    y: Int,
    settings: TemporalDenoiseSettings,
) -> FloatColor:
    """Return one pixel of three.js's `RecurrentDenoiseNode`, diffuse, with
    a raw signal, accumulating.

    Args:
        inputs: The frame's inputs.
        x: The column.
        y: The row, down from the top.
        settings: The node's settings.

    Returns:
        The denoised signal and, in alpha, the raw signal's share; black
        with an alpha of one where the pixel holds no surface.
    """
    var u = (Float32(x) + 0.5) / Float32(inputs.width)
    var v = (Float32(y) + 0.5) / Float32(inputs.height)
    var depth = inputs.depth_at(u, v)
    if depth >= 1:
        return FloatColor(0, 0, 0, 1)
    var normal = inputs.normal(u, v)
    var world_normal = inverse_view_normal(normal, inputs.view)
    var texel = _floor0(inputs.sample(inputs.history, u, v))
    var here = view_position(u, v, depth, inputs.projection_inverse)
    var turn = analytic_noise(x, y, settings.frame_id) * 2 * Float32(pi)
    var c = cos(turn)
    var s = sin(turn)
    var frames = 1 / texel.a
    var variance = max(
        1 / pow(frames, 1 - settings.strength), Float32(0.05)
    )
    var aggressivity = 1 - variance
    var raw = _floor0(inputs.sample(inputs.raw, u, v))
    var view_z = abs(here.z)
    var stats = _neighborhood(inputs, u, v, raw, settings)
    var rl = stats[0]
    var mean_luma = stats[1]
    var deviation_luma = stats[2]
    var env = stats[3]
    var hit_factor = Float32(1)
    if settings.alpha_source == RAY_LENGTH_ALPHA:
        hit_factor = hit_dist_factor(rl, view_z, inputs.tan_half_fov)
    var denoised = Vector3(texel.r, texel.g, texel.b)
    var total = Float32(1)
    var frame_sum = frames
    var frame_weight = Float32(1)
    var raw_sum = Vector3(raw.r, raw.g, raw.b)
    var raw_weight = Float32(1)
    if raw_sum.length() < 0.0001:
        raw_sum = Vector3(0, 0, 0)
        raw_weight = 0
    var is_ao = settings.alpha_source == AO_ALPHA
    var average_ao = raw.a if is_ao else Float32(1)
    var mapped_ao = pow(average_ao, Float32(0.1)) if is_ao else Float32(0)
    var world_radius = settings.radius * WORLD_RADIUS_SCALE
    world_radius *= average_ao * average_ao * abs(here.z)
    world_radius *= 1 + (AGGRESSIVITY_RADIUS_MIN - 1) * aggressivity
    var tangent = Vector3(0, 0, 1)
    tangent.cross(normal)
    tangent.normalize()
    if tangent.length() < TSL_EPSILON:
        tangent = Vector3(0, 1, 0)
        tangent.cross(normal)
        tangent.normalize()
    var bitangent = normal
    bitangent.cross(tangent)
    bitangent.normalize()
    tangent = tangent * world_radius
    bitangent = bitangent * world_radius
    var shrink = Float32(1)
    var bias = Vector2(0, 0)
    var depth_scale = settings.depth_phi * 500 * abs(normal.z) / abs(here.z)
    var falloff = lobe_normal_falloff(1, aggressivity, 1 - settings.normal_phi)
    var raw_luma = luminance_of(raw.r, raw.g, raw.b)
    for i in range(KERNEL_SAMPLES):  # pragma: no branch
        var base = vogel_disk(i, 1)
        var base_length = base.length()
        var dir = base / base_length
        var skew = Float32(0)
        if bias.dot(bias) > 0.001:
            skew = settings.adapt * aggressivity
        var pulled = Vector2(max(bias.x, TSL_EPSILON), max(bias.y, TSL_EPSILON))
        pulled = pulled / pulled.length()
        var skewed = dir + (pulled - dir) * skew
        var reach = skewed * (base_length * shrink)
        var ox = c * reach.x + s * reach.y
        var oy = -s * reach.x + c * reach.y
        var there_point = here + bitangent * ox + tangent * oy
        var at = screen_position(there_point, inputs.projection)
        var su = min(max(1 - abs(1 - abs(at.x)), 0), 1)
        var sv = min(max(1 - abs(1 - abs(at.y)), 0), 1)
        var neighbor = _floor0(inputs.sample(inputs.history, su, sv))
        var raw_neighbor = _floor0(inputs.sample(inputs.raw, su, sv))
        var n_depth = inputs.depth_at(su, sv)
        var there = view_position(su, sv, n_depth, inputs.projection_inverse)
        var n_view_z = abs(there.z)
        var diff = (
            abs(
                luminance_of(raw_neighbor.r, raw_neighbor.g, raw_neighbor.b)
                - raw_luma
            )
            * settings.luma_phi
            * 10
        )
        if is_ao:
            var neighbor_ao = pow(raw_neighbor.a, Float32(0.1))
            diff += (
                mapped_ao
                / (mapped_ao + neighbor_ao + AO_EDGE_STOPPING_BIAS)
                * settings.alpha_phi
                * aggressivity
            )
        elif settings.alpha_source == RAY_LENGTH_ALPHA:
            var neighbor_factor = hit_dist_factor(
                raw_neighbor.a, n_view_z, inputs.tan_half_fov
            )
            var ray_factor = (
                abs(hit_factor - neighbor_factor)
                * settings.alpha_phi
                / abs(here.z)
            )
            if raw_neighbor.a > ENV_RAY_LENGTH_THRESHOLD and env:
                ray_factor = 1
            diff += ray_factor
        var n_world = inverse_view_normal(inputs.normal(su, sv), inputs.view)
        var plane = abs((here - there).dot(normal))
        var normal_weight = exp_f((world_normal.dot(n_world) - 1) * falloff)
        var w = exp_f(-(diff * aggressivity + plane * depth_scale)) * normal_weight
        shrink = shrink + (w - shrink) * settings.adapt
        bias = bias + (dir * (w - 0.5) - bias) * 0.5
        var neighbor_luma = luminance_of(
            raw_neighbor.r, raw_neighbor.g, raw_neighbor.b
        )
        var boost = 1 / (neighbor_luma * neighbor_luma + 0.01)
        w *= boost + (1 - boost) * min(frames / 5, 1)
        raw_sum = raw_sum + Vector3(raw_neighbor.r, raw_neighbor.g, raw_neighbor.b) * w
        raw_weight += w
        denoised = denoised + Vector3(neighbor.r, neighbor.g, neighbor.b) * w
        total += w
        if settings.smooth_disocclusions and neighbor.a > texel.a:
            var share = w * 0.33
            frame_sum += 1 / neighbor.a * share
            frame_weight += share
    denoised = denoised / max(total, TSL_EPSILON)
    denoised = Vector3(
        max(denoised.x, TSL_EPSILON),
        max(denoised.y, TSL_EPSILON),
        max(denoised.z, TSL_EPSILON),
    )
    raw_sum = raw_sum / max(raw_weight, TSL_EPSILON)
    var computed = frame_sum / max(frame_weight, TSL_EPSILON)
    var a = 1 / max(computed, TSL_EPSILON)
    var blended = karis_blend(
        denoised,
        raw_sum,
        a,
        settings.denoise_flicker_suppression,
        settings.adaptive_trust,
        mean_luma,
        deviation_luma,
    )
    return FloatColor(blended.x, blended.y, blended.z, a)


# --- the loop ----------------------------------------------------------------


def temporal_denoise(
    raw: List[FloatColor],
    view: DepthView,
    normals: List[Vector3],
    velocities: List[Vector2],
    camera_view: Matrix4,
    mut settings: TemporalDenoiseSettings,
) raises -> List[FloatColor]:
    """Run one frame of the example's loop: `TemporalReprojectNode` over the
    raw signal with the last denoised result as its history, then
    `RecurrentDenoiseNode` over that, which becomes the next history.

    Args:
        raw: The raw signal, one a pixel, row by row from the top.
        view: The frame's depth, and the camera's projection.
        normals: The frame's view-space normals.
        velocities: The frame's velocities.
        camera_view: The camera's view matrix.
        settings: The nodes' settings and the loop's history, which moves
            on.

    Returns:
        The denoised signal, `(rgb, share)`.

    Raises:
        Error: Everything `check_temporal_denoise` raises, or if an input
            does not have one entry a pixel.
    """
    check_temporal_denoise(settings)
    var w = view.width
    var h = view.height
    var count = w * h
    # `updateFromCamera`: the last frame's matrices, then this one's.
    settings.previous_world = settings.world
    settings.previous_view = settings.view
    settings.previous_projection_inverse = settings.projection_inverse
    var world = camera_view
    world.invert()
    settings.world = world
    settings.view = camera_view
    settings.projection = view.projection
    settings.projection_inverse = view.inverse
    # A new size seeds the history with the raw signal, and the first
    # frame's last depth, normals and camera are its own.
    if settings.history_width != w or settings.history_height != h:
        settings.history = List[FloatColor](capacity=count)
        for slot in range(count):  # pragma: no branch
            settings.history.append(_floor0(raw[slot]))
        settings.history_width = w
        settings.history_height = h
        settings.previous_depth = view.depth.copy()
        settings.previous_normals = normals.copy()
        settings.previous_world = settings.world
        settings.previous_view = settings.view
        settings.previous_projection_inverse = settings.projection_inverse
    var inputs = ReprojectInputs(
        w,
        h,
        raw.copy(),
        settings.history.copy(),
        view.depth.copy(),
        settings.previous_depth.copy(),
        normals.copy(),
        settings.previous_normals.copy(),
        velocities.copy(),
    )
    var camera = ReprojectCamera(settings)
    var reprojected = List[FloatColor](capacity=count)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            reprojected.append(
                temporal_reproject_pixel(inputs, camera, x, y, settings)
            )
    var denoise = DenoiseInputs(
        w,
        h,
        reprojected^,
        raw.copy(),
        view.depth.copy(),
        normals,
        camera_view,
        view.projection,
    )
    var result = List[FloatColor](capacity=count)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            result.append(recurrent_denoise_pixel(denoise, x, y, settings))
    settings.history = result.copy()
    settings.previous_depth = view.depth.copy()
    settings.previous_normals = normals.copy()
    settings.frame_id += 1
    return result^
