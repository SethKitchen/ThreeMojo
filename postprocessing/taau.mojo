# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Temporal anti-aliasing with upscaling: three.js r186's `TAAUNode`, from
`examples/jsm/tsl/display/TAAUNode.js`, with the scene pass it reads.

Each frame the scene is drawn at `resolution_scale` of the output's size,
through the camera moved by the next of 32 Halton offsets less a half, in
input pixels. The velocity is measured without the move. Then each output
pixel is resolved against the history, which is kept at the output's size:

- The output pixel's center is found in input pixels. The nearest jittered
  input sample is the closest tap.
- The 3 by 3 taps round it give the closest and the farthest depth, and
  the velocity is read at the closest, as TRAA reads it.
- The same nine taps rebuild the frame's color, each weighed by
  `exp(-2.29 d^2)`, a Gaussian stand-in for a Blackman-Harris window of
  its distance from the output pixel. They give the mean and the
  deviation the history is clipped to.
- A thin feature, whose color is unlike the mean, locks the history
  against the clip where the depth did not change.
- At least `current_frame_weight` of the new frame goes in, more for fast
  motion, and all of it where the history is not kept. three.js's flicker
  reduction mixes the two.

**What three.js does that this keeps.** The resolve writes its lock to a
target with one attachment, so the lock history stays at the seed's zero
and the lock is the gated thin feature alone. The luminance ratio of a
thin feature divides by the mean's luminance; where every tap is black,
this port reads the ratio as zero where a GPU gives a NaN.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.scene import Scene
from math.matrix4 import Matrix4
from math.smoothstep import smoothstep
from math.vector3 import Vector3
from postprocessing.antialiasing import JitteredCamera
from postprocessing.display_nodes import exp_f, luminance_of, scaled_size
from postprocessing.sampling import LightView
from postprocessing.screen_space import DepthView
from postprocessing.traa import (
    FloatPlane,
    TRAA_JITTERS,
    clip_aabb,
    flicker_reduction,
    traa_jitter,
)
from render.framebuffer import FloatColor
from render.target import (
    FLOAT_TARGET,
    OUTPUT_COLOR,
    OUTPUT_VELOCITY,
    RenderTarget,
)
from renderers.renderer import Renderer
from units.si import Length, METER
from std.math import floor, isfinite, max, min, sqrt


struct TaauSettings(Copyable, Movable):
    """What a TAAU pass reads, with three.js's defaults, and what it keeps
    between frames."""

    # `depthThreshold`, `edgeDepthDiff` and `maxVelocityLength`, as TRAA's.
    var depth_threshold: Float32
    var edge_depth_diff: Float32
    var max_velocity_length: Float32
    # `currentFrameWeight`: the new frame's least share.
    var current_frame_weight: Float32
    # The share of the output's size the scene is drawn at.
    var resolution_scale: Float32
    # `_jitterIndex`.
    var jitter_index: Int
    # The last result, straight, at the output's size, and that size.
    var history: List[FloatColor]
    var history_width: Int
    var history_height: Int
    # The last frame's window depth, at the input's size, and that size.
    var previous_depth: List[Float32]
    var previous_width: Int
    var previous_height: Int
    # The camera's world matrix and its projection's inverse, this frame
    # and the last.
    var camera_world: Matrix4
    var projection_inverse: Matrix4
    var previous_camera_world: Matrix4
    var previous_projection_inverse: Matrix4

    def __init__(out self):
        """Start with three.js's defaults and no history."""
        self.depth_threshold = 0.0005
        self.edge_depth_diff = 0.001
        self.max_velocity_length = 128
        self.current_frame_weight = 0.025
        self.resolution_scale = 0.5
        self.jitter_index = 0
        self.history = List[FloatColor]()
        self.history_width = 0
        self.history_height = 0
        self.previous_depth = List[Float32]()
        self.previous_width = 0
        self.previous_height = 0
        self.camera_world = Matrix4()
        self.projection_inverse = Matrix4()
        self.previous_camera_world = Matrix4()
        self.previous_projection_inverse = Matrix4()


def check_taau(settings: TaauSettings) raises:
    """Refuse settings no TAAU pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If a threshold is negative or not finite, the velocity length
            is not positive, the frame weight is outside zero to one, or
            the resolution scale is outside zero to one.
    """
    var thresholds = (
        isfinite(settings.depth_threshold)
        and isfinite(settings.edge_depth_diff)
        and settings.depth_threshold >= 0
        and settings.edge_depth_diff >= 0
    )
    if not thresholds:
        raise Error(
            "A TAAU pass's depth thresholds must be finite and not negative"
        )
    if not (
        isfinite(settings.max_velocity_length)
        and settings.max_velocity_length > 0
    ):
        raise Error("A TAAU pass's velocity length must be positive")
    if not (
        settings.current_frame_weight >= 0
        and settings.current_frame_weight <= 1
    ):
        raise Error("A TAAU pass's frame weight must be from zero to one")
    if not (settings.resolution_scale > 0 and settings.resolution_scale <= 1):
        raise Error("A TAAU pass's resolution scale must be in (0, 1]")


struct TaauFrame(ImplicitlyCopyable):
    """The numbers one frame's resolve reads, three.js's uniforms."""

    var in_width: Int
    var in_height: Int
    var out_width: Int
    var out_height: Int
    var jitter_x: Float32
    var jitter_y: Float32
    var near: Float32
    var far: Float32
    var perspective: Bool
    # This frame's view matrix, three.js's `_cameraWorldMatrixInverse`.
    var view: Matrix4
    var previous_camera_world: Matrix4
    var previous_projection_inverse: Matrix4
    var depth_threshold: Float32
    var edge_depth_diff: Float32
    var max_velocity_length: Float32
    var current_frame_weight: Float32

    def __init__(
        out self,
        in_width: Int,
        in_height: Int,
        out_width: Int,
        out_height: Int,
        jitter_x: Float32,
        jitter_y: Float32,
        near: Float32,
        far: Float32,
        perspective: Bool,
        view: Matrix4,
        settings: TaauSettings,
    ):
        """Gather a frame's numbers.

        Args:
            in_width: The input's width in pixels.
            in_height: The input's height.
            out_width: The output's width in pixels.
            out_height: The output's height.
            jitter_x: The offset across, in input pixels, less a half.
            jitter_y: The offset down.
            near: The camera's near distance, in meters.
            far: Its far distance.
            perspective: Whether the projection divides by distance.
            view: The camera's view matrix this frame.
            settings: The pass's settings and the last frame's matrices.
        """
        self.in_width = in_width
        self.in_height = in_height
        self.out_width = out_width
        self.out_height = out_height
        self.jitter_x = jitter_x
        self.jitter_y = jitter_y
        self.near = near
        self.far = far
        self.perspective = perspective
        self.view = view
        self.previous_camera_world = settings.previous_camera_world
        self.previous_projection_inverse = settings.previous_projection_inverse
        self.depth_threshold = settings.depth_threshold
        self.edge_depth_diff = settings.edge_depth_diff
        self.max_velocity_length = settings.max_velocity_length
        self.current_frame_weight = settings.current_frame_weight


def previous_window_depth(
    previous: FloatPlane,
    u: Float32,
    v_down: Float32,
    near: Float32,
    far: Float32,
    perspective: Bool,
    previous_projection_inverse: Matrix4,
    previous_camera_world: Matrix4,
    view: Matrix4,
) -> Float32:
    """Return the last frame's depth at a place, moved into this frame's
    view: three.js's `samplePreviousDepth`, reading the nearest texel.

    Args:
        previous: The last frame's window depth.
        u: Across, zero at the left.
        v_down: Down, zero at the top.
        near: The camera's near distance, in meters.
        far: Its far distance.
        perspective: Whether the projection divides by distance.
        previous_projection_inverse: The last frame's projection inverse.
        previous_camera_world: The last frame's camera world matrix.
        view: This frame's view matrix.

    Returns:
        The depth, in this frame's window depth.
    """
    var x = Int(floor(u * Float32(previous.width)))
    var y = Int(floor(v_down * Float32(previous.height)))
    var depth = previous.load(x, y, 0)
    var clip = Vector3(u * 2 - 1, (1 - v_down) * 2 - 1, depth * 2 - 1)
    var seen = previous_projection_inverse.transform_point(clip)
    var world = previous_camera_world.transform_point(seen)
    var view_z = view.transform_point(world).z
    if perspective:
        return ((near + view_z) * far) / ((far - near) * view_z)
    return (view_z + near) / (near - far)


def _floor0(color: FloatColor) -> FloatColor:
    """Return a color with its negative channels raised to zero."""
    return FloatColor(
        max(color.r, 0), max(color.g, 0), max(color.b, 0), max(color.a, 0)
    )


def taau_pixel(
    beauty: LightView,
    history: LightView,
    depth: FloatPlane,
    previous_depth: FloatPlane,
    velocity: FloatPlane,
    x: Int,
    y: Int,
    frame: TaauFrame,
) -> FloatColor:
    """Return one output pixel of three.js's TAAU resolve.

    Args:
        beauty: The new frame, straight, at the input's size.
        history: The last result, straight, at the output's size.
        depth: The new frame's window depth, at the input's size.
        previous_depth: The last frame's window depth.
        velocity: The new frame's velocity, two floats a pixel.
        x: The output column.
        y: The output row, down from the top.
        frame: The frame's numbers.

    Returns:
        The result, straight.
    """
    var u = (Float32(x) + 0.5) / Float32(frame.out_width)
    var v_down = (Float32(y) + 0.5) / Float32(frame.out_height)
    var p_x = u * Float32(frame.in_width)
    var p_y = v_down * Float32(frame.in_height)
    # `round`: the nearest jittered input sample.
    var tap_x = Int(floor(p_x - (0.5 + frame.jitter_x) + 0.5))
    var tap_y = Int(floor(p_y - (0.5 + frame.jitter_y) + 0.5))
    var closest = Float32(2)
    var closest_x = tap_x
    var closest_y = tap_y
    var farthest = Float32(-1)
    # Nine neighbors, fixed, across then down as three.js's loops run.
    for dx in range(-1, 2):  # pragma: no branch
        for dy in range(-1, 2):  # pragma: no branch
            var d = depth.load(tap_x + dx, tap_y + dy, 0)
            if d < closest:
                closest = d
                closest_x = tap_x + dx
                closest_y = tap_y + dy
            if d > farthest:
                farthest = d
    var offset_u = velocity.load(closest_x, closest_y, 0) * 0.5
    var offset_v = velocity.load(closest_x, closest_y, 1) * -0.5
    var history_u = u - offset_u
    var history_v = v_down - offset_v
    var then = previous_window_depth(
        previous_depth,
        history_u,
        history_v,
        frame.near,
        frame.far,
        frame.perspective,
        frame.previous_projection_inverse,
        frame.previous_camera_world,
        frame.view,
    )
    var valid_uv = (
        history_u >= 0 and history_v >= 0 and history_u <= 1 and history_v <= 1
    )
    var edge = farthest - closest > frame.edge_depth_diff
    var uncovered = closest - then > frame.depth_threshold
    var kept = valid_uv and (edge or not uncovered)
    # The nine taps, row by row, as three.js lists them.
    var sum_r = Float32(0)
    var sum_g = Float32(0)
    var sum_b = Float32(0)
    var sum_a = Float32(0)
    var total = Float32(0)
    # Plain floats, not two `FloatColor`s: a struct built again in two
    # nested loops and read after them hangs codegen. See
    # docs/wiki/The-Mojo-compiler-hang.md.
    var m1_r = Float32(0)
    var m1_g = Float32(0)
    var m1_b = Float32(0)
    var m1_a = Float32(0)
    var m2_r = Float32(0)
    var m2_g = Float32(0)
    var m2_b = Float32(0)
    var m2_a = Float32(0)
    for oy in range(-1, 2):  # pragma: no branch
        for ox in range(-1, 2):  # pragma: no branch
            var tx = tap_x + ox
            var ty = tap_y + oy
            var cx = Float32(tx) + 0.5 + frame.jitter_x
            var cy = Float32(ty) + 0.5 + frame.jitter_y
            var ddx = p_x - cx
            var ddy = p_y - cy
            var w = exp_f((ddx * ddx + ddy * ddy) * -2.29)
            var c = _floor0(
                beauty.at(
                    min(max(tx, 0), beauty.width - 1),
                    min(max(ty, 0), beauty.height - 1),
                )
            )
            sum_r += c.r * w
            sum_g += c.g * w
            sum_b += c.b * w
            sum_a += c.a * w
            total += w
            m1_r += c.r
            m1_g += c.g
            m1_b += c.b
            m1_a += c.a
            m2_r += c.r * c.r
            m2_g += c.g * c.g
            m2_b += c.b * c.b
            m2_a += c.a * c.a
    var m1 = FloatColor(m1_r, m1_g, m1_b, m1_a)
    var m2 = FloatColor(m2_r, m2_g, m2_b, m2_a)
    var share = max(total, Float32(1e-5))
    var current = FloatColor(
        sum_r / share, sum_g / share, sum_b / share, sum_a / share
    )
    var n = Float32(9)
    var mean = FloatColor(m1.r / n, m1.g / n, m1.b / n, m1.a / n)
    var moved_x = (u - history_u) * Float32(frame.in_width)
    var moved_y = (v_down - history_v) * Float32(frame.in_height)
    var motion = min(
        max(
            sqrt(moved_x * moved_x + moved_y * moved_y)
            / frame.max_velocity_length,
            0,
        ),
        1,
    )
    var gamma = 0.5 + 0.5 * (1 - motion) * (1 - motion)
    var spread = FloatColor(
        sqrt(max(m2.r / n - mean.r * mean.r, 0)) * gamma,
        sqrt(max(m2.g / n - mean.g * mean.g, 0)) * gamma,
        sqrt(max(m2.b / n - mean.b * mean.b, 0)) * gamma,
        sqrt(max(m2.a / n - mean.a * mean.a, 0)) * gamma,
    )
    var low = FloatColor(
        mean.r - spread.r,
        mean.g - spread.g,
        mean.b - spread.b,
        mean.a - spread.a,
    )
    var high = FloatColor(
        mean.r + spread.r,
        mean.g + spread.g,
        mean.b + spread.b,
        mean.a + spread.a,
    )
    var past = history.tap(
        history_u * Float32(history.width) - 0.5,
        history_v * Float32(history.height) - 0.5,
    )
    var clipped = clip_aabb(mean, past, low, high)
    var current_luma = luminance_of(current.r, current.g, current.b)
    var mean_luma = luminance_of(mean.r, mean.g, mean.b)
    var ratio = Float32(0)
    if mean_luma > 0:
        ratio = abs(current_luma - mean_luma) / mean_luma
    var thin = smoothstep(0, 0.2, ratio)
    var changed = abs(closest - then) > frame.depth_threshold
    var can_lock = valid_uv and not changed
    var lock = thin if can_lock else Float32(0)
    var locked = FloatColor(
        clipped.r + (past.r - clipped.r) * lock,
        clipped.g + (past.g - clipped.g) * lock,
        clipped.b + (past.b - clipped.b) * lock,
        clipped.a + (past.a - clipped.a) * lock,
    )
    var weight = Float32(1)
    if kept:
        weight = min(max(frame.current_frame_weight + motion, 0), 1)
    return flicker_reduction(current, locked, weight)


def taau_render[
    C: Camera
](
    mut frame: RenderTarget,
    mut settings: TaauSettings,
    small: Renderer,
    scene: Scene,
    assets: Assets,
    camera: C,
) raises:
    """Draw one frame of TAAU into `frame`: the scene at the input's size
    through the camera moved by the next offset, and the resolve against
    the history at the frame's size.

    Args:
        frame: The composer's frame: its light and depth are replaced.
        settings: The pass's settings, and its history, which moves on.
        small: What the scene is drawn with, at the input's size, sharing
            the composer's renderer's velocity history; see
            `Renderer.resized`.
        scene: The transform hierarchy, and the meshes and lights in it.
        assets: The geometry, materials and textures the meshes name.
        camera: The camera, before the move.

    Raises:
        Error: Everything `check_taau` and `Renderer.render_into` raise.
    """
    check_taau(settings)
    var in_w = small.width
    var in_h = small.height
    var out_w = frame.width
    var out_h = frame.height
    var jitter = traa_jitter(settings.jitter_index)
    var jx = jitter.x - 0.5
    var jy = jitter.y - 0.5
    var moved = JitteredCamera(camera, scene, jx, jy, in_w, in_h)
    var drawn = RenderTarget(
        in_w,
        in_h,
        small.background,
        FLOAT_TARGET,
        [OUTPUT_COLOR, OUTPUT_VELOCITY],
    )
    small.set_velocity_projection(camera.projection_matrix())
    try:
        small.render_into(drawn, scene, assets, moved)
    finally:
        small.set_velocity_projection(None)
    settings.previous_camera_world = settings.camera_world
    settings.previous_projection_inverse = settings.projection_inverse
    var world = moved.view
    world.invert()
    settings.camera_world = world
    var unprojects = moved.projection
    unprojects.invert()
    settings.projection_inverse = unprojects
    var beauty = List[FloatColor](capacity=in_w * in_h)
    var velocities = List[Float32](capacity=in_w * in_h * 2)
    for slot in range(in_w * in_h):  # pragma: no branch
        beauty.append(drawn.straight_at(slot))
        velocities.append(drawn.velocities[slot].x)
        velocities.append(drawn.velocities[slot].y)
    var beauty_view = LightView(beauty, in_w, in_h)
    # A new output size seeds the history with the beauty read bilinear at
    # the output's pixels, as three.js's seed material does.
    if settings.history_width != out_w or settings.history_height != out_h:
        var seed = List[FloatColor](capacity=out_w * out_h)
        for y in range(out_h):  # pragma: no branch
            for x in range(out_w):  # pragma: no branch
                seed.append(
                    beauty_view.tap(
                        (Float32(x) + 0.5) / Float32(out_w) * Float32(in_w)
                        - 0.5,
                        (Float32(y) + 0.5) / Float32(out_h) * Float32(in_h)
                        - 0.5,
                    )
                )
        settings.history = seed^
        settings.history_width = out_w
        settings.history_height = out_h
    # A depth of another size is forgotten, as a fresh WebGPU depth
    # texture reads zero.
    if settings.previous_width != in_w or settings.previous_height != in_h:
        settings.previous_depth = List[Float32](length=in_w * in_h, fill=0)
        settings.previous_width = in_w
        settings.previous_height = in_h
    var window = DepthView(
        drawn.depth,
        in_w,
        in_h,
        moved.projection,
        Length(moved.near, METER),
        Length(moved.far, METER),
        drawn.depth_mode,
    ).depth.copy()
    var numbers = TaauFrame(
        in_w,
        in_h,
        out_w,
        out_h,
        jx,
        jy,
        moved.near,
        moved.far,
        moved.projection.elements[11] != 0,
        moved.view,
        settings,
    )
    var history_view = LightView(settings.history, out_w, out_h)
    var depth = FloatPlane(window, in_w, in_h, 1)
    var previous = FloatPlane(settings.previous_depth, in_w, in_h, 1)
    var motion = FloatPlane(velocities, in_w, in_h, 2)
    var result = List[FloatColor](capacity=out_w * out_h)
    for y in range(out_h):  # pragma: no branch
        for x in range(out_w):  # pragma: no branch
            result.append(
                taau_pixel(
                    beauty_view,
                    history_view,
                    depth,
                    previous,
                    motion,
                    x,
                    y,
                    numbers,
                )
            )
    _ = beauty^
    _ = velocities^
    for y in range(out_h):  # pragma: no branch
        for x in range(out_w):  # pragma: no branch
            var slot = y * out_w + x
            frame.colors[slot] = result[slot].premultiplied()
            frame.data[slot] = False
            var sx = min(x * in_w // out_w, in_w - 1)
            var sy = min(y * in_h // out_h, in_h - 1)
            frame.depth[slot] = drawn.depth[sy * in_w + sx]
    frame.depth_mode = drawn.depth_mode
    settings.history = result^
    settings.previous_depth = window^
    settings.jitter_index = (settings.jitter_index + 1) % TRAA_JITTERS


def taau_input_size(size: Int, scale: Float32) -> Int:
    """Return the input's side for an output side, as three.js's scene
    pass rounds it at its resolution scale.

    Args:
        size: The output's side, in pixels.
        scale: The resolution scale.

    Returns:
        The input's side, at least one.
    """
    return scaled_size(size, scale)
