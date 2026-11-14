# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The denoiser three.js r186 runs after its screen-space passes:
`TemporalReprojectNode` and `RecurrentDenoiseNode`, from
`examples/jsm/tsl/display/`, in their diffuse mode and their specular
mode.

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

**The specular mode.** `SPECULAR_DENOISE` is the mode three.js's SSR
denoise example runs over a stochastic `SSRNode`, whose alpha holds each
ray's length. The reprojection reads the history a second time, where the
point that the ray hit was: the surface moved along the camera's ray by
the mean ray length of the 3 by 3 neighbors. It mixes the two histories.
The hit point's weighs less where the ray lengths differ, where the
normal curves, and where rays reached the environment. A pixel with no
reflection this frame holds one frame less. The denoise then sizes its
disk by the ray length and the roughness, lays it across the reflected
lobe, and weighs each tap by its roughness too.

**The raw signal's size.** The raw signal can be smaller than the frame,
as an SSR pass with a resolution scale draws it. The reprojection reads
it by texel, three.js's `beautyTexelFromScreen`. The denoise reads it
bilinear.

**What differs from three.js.** The derivatives are the difference
across each 2 by 2 quad, as a GPU's fine derivatives are. A normalized
zero vector is zero here, where a GPU gives a NaN; so a surface that faces
the camera takes the denoise's second tangent, as three.js means it to.
A hit point whose place on the last frame is not finite has no place.
The denoise's base color term, `diffusePhi`, is not ported: the frame has
no base color attachment, and the examples give the node none.
"""
from core.ordinal import ordinal_valid, require_valid, require_non_negative

from render.color_math import floor_channels
from math.finite import require_finite_group
from math.matrix4 import Matrix4
from math.norm import squared_length2
from math.sine import fraction
from math.smoothstep import smoothstep
from math.vector2 import Vector2
from math.utils import clamped_texel, edge_index, mix_delta, rec709_luminance
from math.vector3 import Vector3, mix_delta3, reflect_vector
from postprocessing.display_nodes import exp_f
from postprocessing.importance_sampled_environment import ENV_RAY_LENGTH
from postprocessing.traa import variance_gamma
from postprocessing.sampling import LightView, nearest_held_index
from postprocessing.screen_space import DepthView
from render.framebuffer import FloatColor
from std.math import (
    acos,
    atan,
    cos,
    floor,
    isfinite,
    max,
    min,
    pi,
    pow,
    sin,
    sqrt,
)


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
        return ordinal_valid(self.value, 2)


# `'raylength'`: the distance to what a ray hit, three.js's default.
comptime RAY_LENGTH_ALPHA = AlphaSource(0)
# `'ao'`: the ambient occlusion, as an SSGI signal holds it.
comptime AO_ALPHA = AlphaSource(1)
# Anything else: the alpha is not read.
comptime NO_ALPHA = AlphaSource(2)


@fieldwise_init
struct DenoiseMode(Equatable, ImplicitlyCopyable, Writable):
    """Which signal the two nodes filter, three.js's `mode`, as a type
    rather than a string. It does not stop `DenoiseMode(7)`, which
    `check_temporal_denoise` refuses."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the two modes.

        Returns:
            Whether the value names a mode.
        """
        return ordinal_valid(self.value, 1)


# `'diffuse'`: an SSGI's light, three.js's default.
comptime DIFFUSE_DENOISE = DenoiseMode(0)
# `'specular'`: an SSR's reflections, with the ray length in alpha.
comptime SPECULAR_DENOISE = DenoiseMode(1)


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
    # Both nodes' `mode`.
    var mode: DenoiseMode
    # `TemporalReprojectNode`'s `hitPointReprojection`: whether the
    # specular mode reads the history where the ray's hit point was.
    var hit_point_reprojection: Bool
    # `RecurrentDenoiseNode`'s `roughnessPhi`: how much a tap of another
    # roughness is weighed down, in the specular mode.
    var roughness_phi: Float32
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
    var previous_projection: Matrix4
    var previous_projection_inverse: Matrix4

    def __init__(out self):
        """Start with three.js's defaults, the diffuse mode, the SSGI's AO
        in alpha, and no history."""
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
        self.mode = DIFFUSE_DENOISE
        self.hit_point_reprojection = True
        self.roughness_phi = 100
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
        self.previous_projection = Matrix4()
        self.previous_projection_inverse = Matrix4()


def check_temporal_denoise(settings: TemporalDenoiseSettings) raises:
    """Refuse settings no denoiser could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the alpha source is none of the three, the mode is
            neither of the two, a number is not finite, the velocity
            length or the frame limit is not positive, or the frame count
            is negative.
    """
    require_valid(
        settings.alpha_source.is_valid(),
        "A denoiser's alpha source must be one of the three",
    )
    require_valid(
        settings.mode.is_valid(),
        "A denoiser's mode must be diffuse or specular",
    )
    var finite = (
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
        and isfinite(settings.roughness_phi)
    )
    require_finite_group(finite, "A denoiser setting must be finite")
    if not (
        settings.max_velocity_length > 0
        and isfinite(settings.max_velocity_length)
        and settings.max_frames >= 1
        and isfinite(settings.max_frames)
    ):
        raise Error("A denoiser's velocity length and frame limit are positive")
    require_non_negative(
        settings.frame_id, "A denoiser's frame count must not be negative"
    )


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


# --- TemporalReprojectNode ---------------------------------------------------


def require_denoise_extent(width: Int, height: Int) raises:
    """Refuse a denoise frame that is empty or whose pixel count would wrap.

    Nothing. The call returns when both sides are at least one and their
    product fits in an integer.

    Args:
        width: The frame's width in pixels.
        height: The frame's height in pixels.

    Raises:
        Error: If a side is below one, or the pixel count does not fit.
    """
    if width < 1 or height < 1:
        raise Error("A denoise frame must be at least one pixel each way")
    if width > Int.MAX // height:
        raise Error("A denoise frame is larger than this port builds")


struct ReprojectInputs(Movable):
    """What one frame's reprojection reads: the raw signal, the depth, the
    normals and the velocity, this frame's and the last's."""

    var width: Int
    var height: Int
    # The raw signal's own size: the frame's, or smaller.
    var signal_width: Int
    var signal_height: Int
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
        signal_width: Int = 0,
        signal_height: Int = 0,
    ) raises:
        """Gather a frame's inputs.

        Args:
            width: The frame's width in pixels.
            height: Its height.
            signal: The raw signal, one a pixel of its own size, row by
                row from the top.
            history: The last result, `(rgb, 1 / frames)`.
            depth: This frame's window depth.
            previous_depth: The last frame's.
            normals: This frame's view-space normals.
            previous_normals: The last frame's.
            velocities: This frame's velocities.
            signal_width: The raw signal's width in pixels. Zero, with a
                height of zero, is the frame's size.
            signal_height: The raw signal's height.

        Raises:
            Error: If a side is below one, a pixel count does not fit,
                or a list does not have one entry a pixel.
        """
        require_denoise_extent(width, height)
        var count = width * height
        var raw_width = width
        var raw_height = height
        if signal_width != 0 or signal_height != 0:
            require_denoise_extent(signal_width, signal_height)
            raw_width = signal_width
            raw_height = signal_height
        var complete = (
            len(signal) == raw_width * raw_height
            and len(history) == count
            and len(depth) == count
            and len(previous_depth) == count
            and len(normals) == count
            and len(previous_normals) == count
            and len(velocities) == count
        )
        if not complete:
            raise Error("A reprojection needs one of each input a pixel")
        self.width = width
        self.height = height
        self.signal_width = raw_width
        self.signal_height = raw_height
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
        return clamped_texel(x, y, self.width, self.height)

    def signal_texel(self, x: Int, y: Int) -> Tuple[Int, Int]:
        """Return the raw signal's texel under a pixel of the frame:
        three.js's `beautyTexelFromScreen`.

        three.js floors the product in `Float32`. This port divides the
        integers, which is that floor without its rounding.

        Args:
            x: The frame's column, inside the frame.
            y: The frame's row, down from the top, inside the frame.

        Returns:
            The raw signal's column and row. They are the pixel's own when
            the two sizes are the same.
        """
        return (
            x * self.signal_width // self.width,
            y * self.signal_height // self.height,
        )


struct ReprojectCamera(ImplicitlyCopyable):
    """The camera's matrices, this frame and the last:
    `bindTemporalCameraUniforms`."""

    var world: Matrix4
    var view: Matrix4
    var projection_inverse: Matrix4
    var previous_world: Matrix4
    var previous_view: Matrix4
    var previous_projection: Matrix4
    var previous_projection_inverse: Matrix4
    # Where the camera is, in the world: three.js's `worldPosition`.
    var world_position: Vector3

    def __init__(out self, settings: TemporalDenoiseSettings):
        """Take the matrices the loop keeps.

        three.js keeps the camera's own position. This port reads the
        position from the world matrix, which is the same for a camera
        with no parent.

        Args:
            settings: The loop's camera, this frame and the last.
        """
        self.world = settings.world
        self.view = settings.view
        self.projection_inverse = settings.projection_inverse
        self.previous_world = settings.previous_world
        self.previous_view = settings.previous_view
        self.previous_projection = settings.previous_projection
        self.previous_projection_inverse = settings.previous_projection_inverse
        self.world_position = Vector3(
            settings.world.elements[12],
            settings.world.elements[13],
            settings.world.elements[14],
        )


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
    var color = floor_channels(inputs.history[slot])
    var depth = inputs.previous_depth[slot]
    var u = (Float32(edge_index(x, inputs.width)) + 0.5) / Float32(inputs.width)
    var v = (Float32(edge_index(y, inputs.height)) + 0.5) / Float32(
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
    weighed by how well its surface matches: the color of three.js's
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
    return sample_history_confidence(
        inputs, camera, u, v_down, world_position, world_normal, fallback
    )[0]


def sample_history_confidence(
    inputs: ReprojectInputs,
    camera: ReprojectCamera,
    u: Float32,
    v_down: Float32,
    world_position: Vector3,
    world_normal: Vector3,
    fallback: FloatColor,
) -> Tuple[FloatColor, Float32, Float32]:
    """Return the history at a coordinate from its four texels, and how
    well they match: three.js's `sampleHistory4Tap`.

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
        one. Then the best and the worst of the four texels' confidences,
        `tapConfidence` and `minConfidence`.
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
        inputs,
        camera,
        ix,
        iy,
        (1 - fx) * (1 - fy),
        world_position,
        world_normal,
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
    var best = max(max(t00[2], t10[2]), max(t01[2], t11[2]))
    var worst = min(min(t00[2], t10[2]), min(t01[2], t11[2]))
    if not (total > 0.01):
        return (FloatColor(fallback.r, fallback.g, fallback.b, 1), best, worst)
    return (
        FloatColor(
            (t00[0].r + t10[0].r + t01[0].r + t11[0].r) / total,
            (t00[0].g + t10[0].g + t01[0].g + t11[0].g) / total,
            (t00[0].b + t10[0].b + t01[0].b + t11[0].b) / total,
            (t00[0].a + t10[0].a + t01[0].a + t11[0].a) / total,
        ),
        best,
        worst,
    )


def _history_uv(inputs: ReprojectInputs, x: Int, y: Int) -> Vector2:
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
        rec709_luminance(color.r, color.g, color.b)
        * flicker
        * VARIANCE_CLIP_LUMA_SCALE
        + 1
    )
    return to_ycocg(color.r / scale, color.g / scale, color.b / scale)


def ray_length_stats(
    inputs: ReprojectInputs, x: Int, y: Int
) -> Tuple[Float32, Float32, Float32]:
    """Return what three.js's `collectNeighborhood` gathers from the alpha
    of a pixel's 3 by 3 raw neighbors, where an SSR pass leaves each ray's
    length.

    Args:
        inputs: The frame's inputs.
        x: The frame's column.
        y: The frame's row, down from the top.

    Returns:
        The mean length of the rays that hit a surface, or
        `ENV_RAY_LENGTH` when none did. Then the share of the nine rays
        that reached the environment. Then the deviation of the lengths
        that hit, at least a thousandth.
    """
    var texel = inputs.signal_texel(x, y)
    var view = LightView(
        inputs.signal, inputs.signal_width, inputs.signal_height
    )
    # The pixel, then its eight neighbors in three.js's order.
    var offsets = SIMD[DType.int32, 16](
        -1, -1, -1, 1, 1, -1, 1, 1, 1, 0, 0, -1, 0, 1, -1, 0
    )
    var total = Float32(0)
    var count = Float32(0)
    var mean = Float32(0)
    var m2 = Float32(0)
    for at in range(9):  # pragma: no branch
        var column = texel[0]
        var row = texel[1]
        if at > 0:
            column += Int(offsets[at * 2 - 2])
            row += Int(offsets[at * 2 - 1])
        var alpha = max(view.load(column, row).a, Float32(0))
        if alpha < ENV_RAY_LENGTH_THRESHOLD:
            total += alpha
            count += 1
            var delta = alpha - mean
            mean += delta / count
            m2 += delta * (alpha - mean)
    var ray_length = ENV_RAY_LENGTH
    if count >= 0.5:
        ray_length = total / max(count, Float32(1e-4))
    var deviation = max(sqrt(m2 / max(count, Float32(1))), Float32(1e-3))
    return (ray_length, 1 - count / 9, deviation)


def project_world_to_uv(
    world: Vector3, previous_view: Matrix4, previous_projection: Matrix4
) -> Vector2:
    """Return three.js's `projectWorldToUV`: where a point in the world
    was on the last frame, as a texture coordinate that grows down.

    Args:
        world: The point.
        previous_view: The last frame's view matrix.
        previous_projection: The last frame's projection.

    Returns:
        The coordinate, or `(-1, -1)` where the point's clip w is within
        a hundred-thousandth of zero. A coordinate that is not finite is
        `(-1, -1)` too.
    """
    var seen = previous_view.transform_point(world)
    if not (abs(previous_projection.transform_w(seen)) > 1e-5):
        return Vector2(-1, -1)
    var ndc = previous_projection.transform_point(seen)
    var u = ndc.x * 0.5 + 0.5
    var v = 1 - (ndc.y * 0.5 + 0.5)
    # An infinity less an infinity is not a number, so one test serves.
    if not isfinite(abs(u) + abs(v)):
        return Vector2(-1, -1)
    return Vector2(u, v)


def reproject_hit_point(
    origin: Vector3,
    ray_length: Float32,
    camera_position: Vector3,
    previous_view: Matrix4,
    previous_projection: Matrix4,
) -> Vector2:
    """Return three.js's `reprojectHitPoint`: where the point a
    reflection shows was on the last frame.

    The point is the surface moved along the camera's ray by the ray
    length. So a reflection moves across the image as the thing it shows
    moves, and not as its surface moves.

    Args:
        origin: The surface, in the world.
        ray_length: How far the reflected ray went, in meters.
        camera_position: The camera, in the world.
        previous_view: The last frame's view matrix.
        previous_projection: The last frame's projection.

    Returns:
        The coordinate, down from the top, or `(-1, -1)`.
    """
    var ray = origin - camera_position
    ray.normalize()
    return project_world_to_uv(
        origin + ray * ray_length, previous_view, previous_projection
    )


def normal_curvature(
    inputs: ReprojectInputs, view: Matrix4, x: Int, y: Int
) -> Float32:
    """Return three.js's `curvatureFactor`: the length of the world
    normal's `fwidth`, times fifty, held at one.

    The derivatives are the differences across the pixel's 2 by 2 quad,
    as `stretch_confidence` takes them.

    Args:
        inputs: The frame's inputs.
        view: The camera's view matrix.
        x: The column.
        y: The row, down from the top.

    Returns:
        Zero on a flat surface, up to one where the normal turns.
    """
    var left = x - (x % 2)
    var top = y - (y % 2)
    var across = inverse_view_normal(
        inputs.normals[inputs.slot(left + 1, y)], view
    ) - inverse_view_normal(inputs.normals[inputs.slot(left, y)], view)
    var down = inverse_view_normal(
        inputs.normals[inputs.slot(x, top + 1)], view
    ) - inverse_view_normal(inputs.normals[inputs.slot(x, top)], view)
    var spread = Vector3(
        abs(across.x) + abs(down.x),
        abs(across.y) + abs(down.y),
        abs(across.z) + abs(down.z),
    )
    return min(max(spread.length() * 50, Float32(0)), Float32(1))


def _in_unit(uv: Vector2) -> Bool:
    """Return True if a coordinate is on the image, edges included."""
    return min(uv.x, uv.y) >= 0 and max(uv.x, uv.y) <= 1


def specular_history(
    inputs: ReprojectInputs,
    camera: ReprojectCamera,
    x: Int,
    y: Int,
    back: Vector2,
    surface: Tuple[FloatColor, Float32, Float32],
    world_position: Vector3,
    world_normal: Vector3,
    input: FloatColor,
    motion: Float32,
    settings: TemporalDenoiseSettings,
) -> Tuple[FloatColor, Float32, Float32]:
    """Return three.js's `resolveSpecularHistory`: the history where the
    surface was, mixed with the history where the ray's hit point was.

    Args:
        inputs: The frame's inputs.
        camera: The camera's matrices.
        x: The column.
        y: The row, down from the top.
        back: Where the surface was, `historyUV`.
        surface: The history there, from `sample_history_confidence`.
        world_position: The pixel's surface, in the world.
        world_normal: Its normal, in the world.
        input: The pixel's raw signal.
        motion: How far the pixel moved, zero to one, `motionFactor`.
        settings: The node's settings.

    Returns:
        The mixed history, with the surface history's alpha. Then its
        confidence. Then how far the hit point's history is trusted,
        before the environment's share is taken off.
    """
    var stats = ray_length_stats(inputs, x, y)
    var hit_uv = reproject_hit_point(
        world_position,
        stats[0],
        camera.world_position,
        camera.previous_view,
        camera.previous_projection,
    )
    var hit = sample_history_confidence(
        inputs,
        camera,
        hit_uv.x,
        hit_uv.y,
        world_position,
        world_normal,
        input,
    )
    var hit_confidence = Float32(0)
    if _in_unit(hit_uv) and settings.hit_point_reprojection:
        hit_confidence = hit[1]
    var surface_confidence = Float32(0)
    if _in_unit(back):
        surface_confidence = surface[1]
    var edge = 1 - min(stats[2] * min(motion * 100, Float32(1)) * 3.5, 1)
    var curvature = normal_curvature(inputs, camera.view, x, y)
    var trust = hit[2] * edge * (1 - curvature) * hit_confidence
    var w_hit = trust * (1 - stats[1] * stats[1])
    var w_surface = (1 - w_hit) * surface_confidence
    var w_sum = max(w_hit + w_surface, TSL_EPSILON)
    var from_hit = floor_channels(hit[0])
    var from_surface = floor_channels(surface[0])
    var mixed = Vector3(
        (from_hit.r * w_hit + from_surface.r * w_surface) / w_sum,
        (from_hit.g * w_hit + from_surface.g * w_surface) / w_sum,
        (from_hit.b * w_hit + from_surface.b * w_surface) / w_sum,
    )
    var confidence = (
        hit_confidence * w_hit + surface_confidence * w_surface
    ) / w_sum
    # A blend near black means neither history was usable.
    if mixed.length() < TSL_EPSILON:
        return (FloatColor(input.r, input.g, input.b, 1), confidence, trust)
    return (
        FloatColor(mixed.x, mixed.y, mixed.z, surface[0].a),
        confidence,
        trust,
    )


def temporal_reproject_pixel(
    inputs: ReprojectInputs,
    camera: ReprojectCamera,
    x: Int,
    y: Int,
    settings: TemporalDenoiseSettings,
) -> FloatColor:
    """Return one pixel of three.js's `TemporalReprojectNode`, in the
    settings' mode.

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
    var texel = inputs.signal_texel(x, y)
    var input = floor_channels(
        inputs.signal[texel[1] * inputs.signal_width + texel[0]]
    )
    var flicker = settings.flicker_suppression
    # `collectNeighborhood`: the pixel and its eight neighbors.
    var m1 = _dampened(input, flicker)
    var m2 = m1 * m1
    var offsets = SIMD[DType.int32, 16](
        -1, -1, -1, 1, 1, -1, 1, 1, 1, 0, 0, -1, 0, 1, -1, 0
    )
    var view = LightView(
        inputs.signal, inputs.signal_width, inputs.signal_height
    )
    for at in range(8):  # pragma: no branch
        var near = floor_channels(
            view.load(
                texel[0] + Int(offsets[at * 2]),
                texel[1] + Int(offsets[at * 2 + 1]),
            )
        )
        var c = _dampened(near, flicker)
        m1 = m1 + c
        m2 = m2 + c * c
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
            sqrt(squared_length2[DType.float32](off_x, off_y))
            / settings.max_velocity_length,
            0,
        ),
        1,
    )
    var back = _history_uv(inputs, x, y)
    var surface = sample_history_confidence(
        inputs, camera, back.x, back.y, world_position, world_normal, input
    )
    var history = surface[0]
    var confidence = Float32(1)
    var trust = Float32(0)
    var specular = settings.mode == SPECULAR_DENOISE
    if specular:
        var resolved = specular_history(
            inputs,
            camera,
            x,
            y,
            back,
            surface,
            world_position,
            world_normal,
            input,
            motion,
            settings,
        )
        history = resolved[0]
        confidence = resolved[1]
        trust = resolved[2]
    var a = max(history.a, TSL_EPSILON)
    var stretch = stretch_confidence(inputs, x, y)
    confidence *= stretch * stretch
    var gamma = variance_gamma(motion)
    # `applyVarianceClipping`.
    var low = mean - deviation * gamma
    var high = mean + deviation * gamma
    var scale = (
        rec709_luminance(history.r, history.g, history.b)
        * flicker
        * VARIANCE_CLIP_LUMA_SCALE
        + 1
    )
    var clipped = (
        from_ycocg(
            clip_to_aabb(
                to_ycocg(
                    history.r / scale, history.g / scale, history.b / scale
                ),
                low,
                high,
            )
        )
        * scale
    )
    var clamp_intensity = (
        settings.clamp_intensity
        * max(min(motion * 10, 1), Float32(0.25))
        * (1 + min(max((1 - stretch) + (1 - trust), 0), 1))
    )
    var original = Vector3(history.r, history.g, history.b)
    var mixed = mix_delta3(original, clipped, clamp_intensity)
    confidence *= exp_f(-(original - clipped).length() * clamp_intensity * 30)
    confidence *= 1 + (trust * 0.05 + 0.95 - 1) * min(max(motion * 100, 0), 1)
    if confidence < TSL_EPSILON:
        mixed = Vector3(input.r, input.g, input.b)
    var frames = min(1 / a * confidence + 1, settings.max_frames)
    # A black raw signal means that no reflection was found this frame.
    # The denoise adds a frame, so the count goes back by one.
    if specular and Vector3(input.r, input.g, input.b).length() < TSL_EPSILON:
        frames = max(frames - 1, Float32(1))
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
    var shift_x = floor(fraction(ox) * 32)
    var shift_y = floor(fraction(oy) * 32)
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
    return fraction(r)


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


def specular_dominant_direction(
    normal: Vector3, view_dir: Vector3, roughness: Float32
) -> Vector3:
    """Return three.js's `getSpecularDominantDirection`: the reflection
    for a smooth surface, the normal for a rough one, and the mix between.

    Args:
        normal: The surface's normal.
        view_dir: The direction toward the viewer.
        roughness: The surface's roughness.

    Returns:
        The direction, unit length.
    """
    var out = mix_delta3(
        normal, reflect_vector(-view_dir, normal), 1 - roughness
    )
    out.normalize()
    return out


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
        rec709_luminance(denoised.x, denoised.y, denoised.z) * effective * 10
        + 1
    )
    var w_raw = a_trust / (
        rec709_luminance(raw.x, raw.y, raw.z) * effective * 10 + 1
    )
    return (denoised * w_hist + raw * w_raw) / max(w_hist + w_raw, TSL_EPSILON)


struct DenoiseInputs(Movable):
    """What one frame's recurrent denoise reads: the reprojected history,
    the raw signal, the depth and the normals, and the camera."""

    var width: Int
    var height: Int
    var history: List[FloatColor]
    # The raw signal, and its own size: the frame's, or smaller.
    var raw: List[FloatColor]
    var raw_width: Int
    var raw_height: Int
    var depth: List[Float32]
    var normals: List[FloatColor]
    # The metalness in red and the roughness in green, three.js's
    # `metalRoughness`, or empty for none.
    var surfaces: List[FloatColor]
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
        metal_roughs: List[Vector2] = List[Vector2](),
        raw_width: Int = 0,
        raw_height: Int = 0,
    ) raises:
        """Gather a frame's inputs.

        Args:
            width: The frame's width in pixels.
            height: Its height.
            history: The reprojection's result, `(rgb, 1 / frames)`.
            raw: The raw signal, one a pixel of its own size.
            depth: The window depth.
            normals: The view-space normals.
            view: The camera's view matrix.
            projection: Its projection.
            metal_roughs: Each pixel's metalness and roughness, or empty
                for none. Without them, every surface has a metalness of
                zero and a roughness of one, as three.js's node has.
            raw_width: The raw signal's width in pixels. Zero, with a
                height of zero, is the frame's size.
            raw_height: The raw signal's height.

        Raises:
            Error: If a side is below one, a pixel count does not fit, a
                list does not have one entry a pixel, or the projection
                cannot be inverted.
        """
        require_denoise_extent(width, height)
        var count = width * height
        var signal_width = width
        var signal_height = height
        if raw_width != 0 or raw_height != 0:
            require_denoise_extent(raw_width, raw_height)
            signal_width = raw_width
            signal_height = raw_height
        var surfaced = len(metal_roughs)
        var complete = (
            len(history) == count
            and len(raw) == signal_width * signal_height
            and len(depth) == count
            and len(normals) == count
        )
        if not complete or (surfaced != 0 and surfaced != count):
            raise Error("A denoise needs one of each input a pixel")
        if projection.determinant() == 0:
            raise Error("A denoise's projection must be invertible")
        self.width = width
        self.height = height
        self.history = history^
        self.raw = raw^
        self.raw_width = signal_width
        self.raw_height = signal_height
        self.depth = depth^
        self.normals = List[FloatColor](capacity=count)
        self.surfaces = List[FloatColor](capacity=surfaced)
        for slot in range(count):  # pragma: no branch
            ref n = normals[slot]
            self.normals.append(FloatColor(n.x, n.y, n.z, 0))
        for slot in range(surfaced):
            ref m = metal_roughs[slot]
            self.surfaces.append(FloatColor(m.x, m.y, 0, 0))
        self.view = view
        self.projection = projection
        self.projection_inverse = projection
        self.projection_inverse.invert()
        # three.js's `tan( fov / 2 )`, from the projection's second column.
        self.tan_half_fov = 1 / projection.elements[5]

    def sample(
        self, colors: List[FloatColor], u: Float32, v: Float32
    ) -> FloatColor:
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

    def raw_at(self, u: Float32, v: Float32) -> FloatColor:
        """Return the raw signal read bilinear at a coordinate that grows
        down, held at the edges, no channel below zero.

        Args:
            u: Across.
            v: Down.

        Returns:
            The blend.
        """
        return floor_channels(
            LightView(self.raw, self.raw_width, self.raw_height).tap(
                u * Float32(self.raw_width) - 0.5,
                v * Float32(self.raw_height) - 0.5,
            )
        )

    def metal_rough(self, u: Float32, v: Float32) -> Vector2:
        """Return the metalness and the roughness read bilinear: three.js's
        `sampleRoughnessMetalness`.

        Args:
            u: Across.
            v: Down.

        Returns:
            The metalness and the roughness. Zero and one without the
            input.
        """
        if len(self.surfaces) == 0:
            return Vector2(0, 1)
        var surface = self.sample(self.surfaces, u, v)
        return Vector2(surface.r, surface.g)

    def depth_at(self, u: Float32, v: Float32) -> Float32:
        """Return the window depth at a coordinate, nearest.

        Args:
            u: Across.
            v: Down.

        Returns:
            The depth. A coordinate at or past the far edge reads the last
            pixel. A coordinate that is not finite reads the first.
        """
        var x = nearest_held_index(u, self.width)
        var y = nearest_held_index(v, self.height)
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
            sample = inputs.raw_at(
                u + du[at] / Float32(inputs.width),
                v + dv[at] / Float32(inputs.height),
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
            var luma = rec709_luminance(sample.r, sample.g, sample.b)
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
    """Return one pixel of three.js's `RecurrentDenoiseNode`, in the
    settings' mode, with a raw signal, accumulating.

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
    var texel = floor_channels(inputs.sample(inputs.history, u, v))
    var here = view_position(u, v, depth, inputs.projection_inverse)
    var turn = analytic_noise(x, y, settings.frame_id) * 2 * Float32(pi)
    var c = cos(turn)
    var s = sin(turn)
    var frames = 1 / texel.a
    var variance = max(1 / pow(frames, 1 - settings.strength), Float32(0.05))
    var aggressivity = 1 - variance
    var raw = inputs.raw_at(u, v)
    var surface = inputs.metal_rough(u, v)
    var roughness = surface.y
    var specular = settings.mode == SPECULAR_DENOISE
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
    var tangent = Vector3(0, 0, 1)
    var bitangent = normal
    if specular:
        # The disk grows with the ray's length and the roughness, and
        # lies across the reflected lobe.
        world_radius *= rl * abs(here.z)
        world_radius *= max(sqrt(roughness), Float32(0.01))
        var toward = -here
        toward.normalize()
        var dominant = specular_dominant_direction(normal, toward, roughness)
        var reflected = reflect_vector(-dominant, normal)
        tangent = normal
        tangent.cross(reflected)
        tangent.normalize()
        bitangent = reflected
        bitangent.cross(tangent)
        var view_angle = min(
            max(
                acos(min(abs(normal.z), Float32(1))) / Float32(pi * 0.5),
                Float32(0),
            ),
            Float32(1),
        )
        tangent = tangent * mix_delta(Float32(1), roughness, view_angle)
    else:
        world_radius *= average_ao * average_ao * abs(here.z)
        tangent.cross(normal)
        tangent.normalize()
        if tangent.length() < TSL_EPSILON:
            tangent = Vector3(0, 1, 0)
            tangent.cross(normal)
            tangent.normalize()
        bitangent.cross(tangent)
        bitangent.normalize()
    world_radius *= 1 + (AGGRESSIVITY_RADIUS_MIN - 1) * aggressivity
    tangent = tangent * world_radius
    bitangent = bitangent * world_radius
    var shrink = Float32(1)
    var bias = Vector2(0, 0)
    var depth_scale = settings.depth_phi * 500 * abs(normal.z) / abs(here.z)
    var falloff = lobe_normal_falloff(
        roughness, aggressivity, 1 - settings.normal_phi
    )
    var raw_luma = rec709_luminance(raw.r, raw.g, raw.b)
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
        var neighbor = floor_channels(inputs.sample(inputs.history, su, sv))
        var raw_neighbor = inputs.raw_at(su, sv)
        var n_depth = inputs.depth_at(su, sv)
        var there = view_position(su, sv, n_depth, inputs.projection_inverse)
        var n_view_z = abs(there.z)
        var diff = (
            abs(
                rec709_luminance(raw_neighbor.r, raw_neighbor.g, raw_neighbor.b)
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
        if specular:
            diff += (
                abs(roughness - inputs.metal_rough(su, sv).y)
                * settings.roughness_phi
            )
        var n_world = inverse_view_normal(inputs.normal(su, sv), inputs.view)
        var plane = abs((here - there).dot(normal))
        var normal_weight = exp_f((world_normal.dot(n_world) - 1) * falloff)
        var w = (
            exp_f(-(diff * aggressivity + plane * depth_scale)) * normal_weight
        )
        shrink = mix_delta(shrink, w, settings.adapt)
        bias = bias + (dir * (w - 0.5) - bias) * 0.5
        var neighbor_luma = rec709_luminance(
            raw_neighbor.r, raw_neighbor.g, raw_neighbor.b
        )
        var boost = 1 / (neighbor_luma * neighbor_luma + 0.01)
        w *= boost + (1 - boost) * min(frames / 5, 1)
        raw_sum = (
            raw_sum
            + Vector3(raw_neighbor.r, raw_neighbor.g, raw_neighbor.b) * w
        )
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
    metal_roughs: List[Vector2] = List[Vector2](),
    raw_width: Int = 0,
    raw_height: Int = 0,
) raises -> List[FloatColor]:
    """Run one frame of the examples' loop: `TemporalReprojectNode` over the
    raw signal with the last denoised result as its history, then
    `RecurrentDenoiseNode` over that, which becomes the next history.

    Args:
        raw: The raw signal, one a pixel of its own size, row by row from
            the top.
        view: The frame's depth, and the camera's projection.
        normals: The frame's view-space normals.
        velocities: The frame's velocities.
        camera_view: The camera's view matrix.
        settings: The nodes' settings and the loop's history, which moves
            on.
        metal_roughs: Each pixel's metalness and roughness, which the
            denoise reads, or empty for none.
        raw_width: The raw signal's width in pixels. Zero, with a height
            of zero, is the frame's size.
        raw_height: The raw signal's height.

    Returns:
        The denoised signal at the frame's size, `(rgb, share)`.

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
    settings.previous_projection = settings.projection
    settings.previous_projection_inverse = settings.projection_inverse
    var world = camera_view
    world.invert()
    settings.world = world
    settings.view = camera_view
    settings.projection = view.projection
    settings.projection_inverse = view.inverse
    # A new size seeds the history with the raw signal, and the first
    # frame's last depth, normals and camera are its own.
    var seeds = settings.history_width != w or settings.history_height != h
    var seed: List[FloatColor]
    if seeds:
        seed = List[FloatColor](length=count, fill=FloatColor(0, 0, 0, 0))
        settings.previous_depth = view.depth.copy()
        settings.previous_normals = normals.copy()
        settings.previous_world = settings.world
        settings.previous_view = settings.view
        settings.previous_projection = settings.projection
        settings.previous_projection_inverse = settings.projection_inverse
    else:
        seed = settings.history.copy()
    var inputs = ReprojectInputs(
        w,
        h,
        raw.copy(),
        seed^,
        view.depth.copy(),
        settings.previous_depth.copy(),
        normals.copy(),
        settings.previous_normals.copy(),
        velocities.copy(),
        raw_width,
        raw_height,
    )
    if seeds:
        # three.js's seed: each pixel takes the raw texel under it.
        for y in range(h):  # pragma: no branch
            for x in range(w):  # pragma: no branch
                var texel = inputs.signal_texel(x, y)
                inputs.history[y * w + x] = floor_channels(
                    raw[texel[1] * inputs.signal_width + texel[0]]
                )
        settings.history_width = w
        settings.history_height = h
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
        metal_roughs,
        raw_width,
        raw_height,
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
