# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Temporal reprojection anti-aliasing: three.js r186's `TRAANode`, from
`examples/jsm/tsl/display/TRAANode.js` and `tsl/utils/TAAUtils.js`.

Each frame the camera is moved by a fraction of a pixel, the next of 32
Halton offsets, and the scene is drawn with its depth and its velocity.
The velocity is measured with the projection before the move, so the move
is not motion. Then each pixel mixes the frame into the history, the
pixel's last result, read where the velocity says the pixel was:

- The pixel's 3 by 3 neighbors give the closest and the farthest depth.
  The velocity is read at the closest.
- The history is kept where its place is on the image and the surface
  there was not uncovered since: the last frame's depth, moved into this
  frame's view, is not more than `depth_threshold` nearer. An edge, where
  the neighbors' depths differ by more than `edge_depth_diff`, keeps it
  too.
- The history is clipped to the box of the neighbors' mean and deviation,
  three.js's variance clipping.
- At least 5 percent of the new frame goes in, more for a velocity that
  is a fraction of a pixel and for a fast one, and all of it where the
  history is not kept. The mix is weighted down where the light is
  bright, three.js's flicker reduction.

**What differs from three.js.** A neighbor past the edge of the image is
the edge pixel, as WebGPU's robust `textureLoad` clamps it. The first
frame's last depth is zero, as a fresh WebGPU depth texture reads.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.scene import Scene
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from postprocessing.antialiasing import JitteredCamera
from postprocessing.display_nodes import luminance_of
from postprocessing.sampling import LightView, Untracked
from postprocessing.screen_space import DepthView
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


# How many offsets the jitter walks through, three.js's
# `computeHaltonOffsets( 32 )`.
comptime TRAA_JITTERS = 32


def halton(index: Int, base: Int) -> Float32:
    """Return the Halton sequence's number at an index in a base, three.js's
    `halton`.

    Args:
        index: The index, from one.
        base: The base, two or three here.

    Returns:
        The number, from zero to one.
    """
    var fraction = Float64(1)
    var result = Float64(0)
    var at = index
    while at > 0:
        fraction /= Float64(base)
        result += fraction * Float64(at % base)
        at = at // base
    return Float32(result)


def traa_jitter(index: Int) -> Vector2:
    """Return the offset of a frame in the jitter, three.js's
    `_haltonOffsets[ index ]`: the Halton numbers of `index + 1` in bases
    two and three.

    Args:
        index: The frame's place in the jitter, from zero.

    Returns:
        The offset, zero to one each way. The camera moves by it less a
        half, in pixels.
    """
    return Vector2(halton(index + 1, 2), halton(index + 1, 3))


struct TraaSettings(Copyable, Movable):
    """What a TRAA pass reads, with three.js's defaults, and what it keeps
    between frames."""

    # `depthThreshold`: how much nearer the last frame's surface may be
    # before the pixel counts as uncovered, in window depth.
    var depth_threshold: Float32
    # `edgeDepthDiff`: how far apart the neighbors' depths are at an edge.
    var edge_depth_diff: Float32
    # `maxVelocityLength`: the motion, in pixels, at which the new frame
    # takes over.
    var max_velocity_length: Float32
    # `useSubpixelCorrection`.
    var use_subpixel_correction: Bool
    # Which offset the next frame's camera takes, three.js's
    # `_jitterIndex`.
    var jitter_index: Int
    # The last result, straight, row by row from the top, and its size:
    # three.js's history target. Empty before the first frame.
    var history: List[FloatColor]
    var history_width: Int
    var history_height: Int
    # The last frame's window depth, three.js's `_previousDepthNode`.
    # Empty before the first frame, which reads zero.
    var previous_depth: List[Float32]
    # The camera's world matrix and its projection's inverse, this frame
    # and the last: three.js's `_cameraWorldMatrix`,
    # `_cameraProjectionMatrixInverse` and their previous copies.
    var camera_world: Matrix4
    var projection_inverse: Matrix4
    var previous_camera_world: Matrix4
    var previous_projection_inverse: Matrix4

    def __init__(out self):
        """Start with three.js's defaults and no history."""
        self.depth_threshold = 0.0005
        self.edge_depth_diff = 0.001
        self.max_velocity_length = 128
        self.use_subpixel_correction = True
        self.jitter_index = 0
        self.history = List[FloatColor]()
        self.history_width = 0
        self.history_height = 0
        self.previous_depth = List[Float32]()
        self.camera_world = Matrix4()
        self.projection_inverse = Matrix4()
        self.previous_camera_world = Matrix4()
        self.previous_projection_inverse = Matrix4()


def check_traa(settings: TraaSettings) raises:
    """Refuse settings no TRAA pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If a threshold is negative or not finite, or the velocity
            length is not positive.
    """
    if not (
        isfinite(settings.depth_threshold)
        and isfinite(settings.edge_depth_diff)
        and settings.depth_threshold >= 0
        and settings.edge_depth_diff >= 0
    ):
        raise Error(
            "A TRAA pass's depth thresholds must be finite and not negative"
        )
    if not (
        isfinite(settings.max_velocity_length)
        and settings.max_velocity_length > 0
    ):
        raise Error("A TRAA pass's velocity length must be positive")


struct TraaFrame(ImplicitlyCopyable):
    """The numbers one frame's resolve reads, three.js's uniforms."""

    var width: Int
    var height: Int
    var near: Float32
    var far: Float32
    var perspective: Bool
    # This frame's view matrix, three.js's `_cameraWorldMatrixInverse`.
    var view: Matrix4
    # The last frame's camera world matrix and projection inverse.
    var previous_camera_world: Matrix4
    var previous_projection_inverse: Matrix4
    var depth_threshold: Float32
    var edge_depth_diff: Float32
    var max_velocity_length: Float32
    var use_subpixel_correction: Bool

    def __init__(
        out self,
        width: Int,
        height: Int,
        near: Float32,
        far: Float32,
        perspective: Bool,
        view: Matrix4,
        settings: TraaSettings,
    ):
        """Gather a frame's numbers.

        Args:
            width: The frame's width in pixels.
            height: Its height.
            near: The camera's near distance, in meters.
            far: Its far distance.
            perspective: Whether the camera's projection divides by
                distance.
            view: The camera's view matrix this frame.
            settings: The pass's settings and the last frame's matrices.
        """
        self.width = width
        self.height = height
        self.near = near
        self.far = far
        self.perspective = perspective
        self.view = view
        self.previous_camera_world = settings.previous_camera_world
        self.previous_projection_inverse = settings.previous_projection_inverse
        self.depth_threshold = settings.depth_threshold
        self.edge_depth_diff = settings.edge_depth_diff
        self.max_velocity_length = settings.max_velocity_length
        self.use_subpixel_correction = settings.use_subpixel_correction


struct FloatPlane(ImplicitlyCopyable):
    """Floats a pixel, row by row from the top, read as `textureLoad`
    reads them: clamped at the edges. The host builds one over a list;
    the view does not own the floats."""

    var floats: Pointer[Float32, Untracked]
    var width: Int
    var height: Int
    var lanes: Int

    def __init__(
        out self, values: List[Float32], width: Int, height: Int, lanes: Int
    ):
        """View a list.

        Args:
            values: `lanes` floats a pixel. The list must outlive the view.
            width: The width in pixels.
            height: The height in pixels.
            lanes: How many floats a pixel holds.
        """
        self.floats = values.unsafe_ptr().unsafe_origin_cast[Untracked]()
        self.width = width
        self.height = height
        self.lanes = lanes

    def load(self, x: Int, y: Int, lane: Int) -> Float32:
        """Return one float of a pixel, the edge pixel's past the edge.

        Args:
            x: The column.
            y: The row, down from the top.
            lane: Which of the pixel's floats.

        Returns:
            The float.
        """
        var cx = min(max(x, 0), self.width - 1)
        var cy = min(max(y, 0), self.height - 1)
        return self.floats[
            unsafe_offset=(cy * self.width + cx) * self.lanes + lane
        ]


def _load(view: LightView, x: Int, y: Int) -> FloatColor:
    """Return a pixel, the edge pixel's past the edge: `textureLoad`."""
    return view.at(
        min(max(x, 0), view.width - 1), min(max(y, 0), view.height - 1)
    )


def _floor0(color: FloatColor) -> FloatColor:
    """Return a color with its negative channels raised to zero."""
    return FloatColor(
        max(color.r, 0), max(color.g, 0), max(color.b, 0), max(color.a, 0)
    )


def clip_aabb(
    current: FloatColor,
    history: FloatColor,
    low: FloatColor,
    high: FloatColor,
) -> FloatColor:
    """Return the history clipped toward the middle of a color box, as far
    as it lies outside: three.js's `clipAABB`.

    Args:
        current: The color whose alpha the box's middle takes.
        history: The history color.
        low: The box's low corner.
        high: The box's high corner.

    Returns:
        The history, or the point where the line to it leaves the box.
    """
    var mid_r = (high.r + low.r) * 0.5
    var mid_g = (high.g + low.g) * 0.5
    var mid_b = (high.b + low.b) * 0.5
    var ext_r = (high.r - low.r) * 0.5 + 1e-7
    var ext_g = (high.g - low.g) * 0.5 + 1e-7
    var ext_b = (high.b - low.b) * 0.5 + 1e-7
    var v_r = history.r - mid_r
    var v_g = history.g - mid_g
    var v_b = history.b - mid_b
    var v_a = history.a - current.a
    var most = max(abs(v_r / ext_r), max(abs(v_g / ext_g), abs(v_b / ext_b)))
    if most > 1:
        return FloatColor(
            mid_r + v_r / most,
            mid_g + v_g / most,
            mid_b + v_b / most,
            current.a + v_a / most,
        )
    return history


def flicker_reduction(
    current: FloatColor, history: FloatColor, weight: Float32
) -> FloatColor:
    """Return the new frame and the history mixed by a weight, each scaled
    down by its brightness: three.js's `flickerReduction`.

    Args:
        current: The new frame's color.
        history: The history's color.
        weight: The new frame's share, before the scaling.

    Returns:
        The mix.
    """
    var squeeze_now = 1 / (max(current.r, max(current.g, current.b)) + 1)
    var squeeze_then = 1 / (max(history.r, max(history.g, history.b)) + 1)
    var light_now = luminance_of(
        current.r * squeeze_now,
        current.g * squeeze_now,
        current.b * squeeze_now,
    )
    var light_then = luminance_of(
        history.r * squeeze_then,
        history.g * squeeze_then,
        history.b * squeeze_then,
    )
    var weight_now = weight / (light_now + 1)
    var weight_then = (1 - weight) / (light_then + 1)
    var total = max(weight_now + weight_then, 0.00001)
    return FloatColor(
        (current.r * weight_now + history.r * weight_then) / total,
        (current.g * weight_now + history.g * weight_then) / total,
        (current.b * weight_now + history.b * weight_then) / total,
        (current.a * weight_now + history.a * weight_then) / total,
    )


def subpixel_correction(
    offset_u: Float32, offset_v: Float32, width: Int, height: Int
) -> Float32:
    """Return how much of a pixel's velocity is a fraction of a pixel,
    zero to one: three.js's `subpixelCorrection`.

    Args:
        offset_u: The velocity across, in texture coordinates.
        offset_v: The velocity down, in texture coordinates.
        width: The frame's width in pixels.
        height: Its height.

    Returns:
        The share.
    """
    var tx = offset_u * Float32(width)
    var ty = offset_v * Float32(height)
    var px = abs(tx - floor(tx))
    var py = abs(ty - floor(ty))
    var wx = max(px, 1 - px)
    var wy = max(py, 1 - py)
    return (1 - wx * wy) / 0.75


def _previous_depth(
    previous: FloatPlane, u: Float32, v_down: Float32, frame: TraaFrame
) -> Float32:
    """Return the last frame's depth at a place, moved into this frame's
    view: three.js's `samplePreviousDepth`. The depth texture is read at
    the nearest texel."""
    var x = Int(floor(u * Float32(previous.width)))
    var y = Int(floor(v_down * Float32(previous.height)))
    var depth = previous.load(x, y, 0)
    # three.js's `getViewPosition`, in WebGL's clip space.
    var clip = Vector3(u * 2 - 1, (1 - v_down) * 2 - 1, depth * 2 - 1)
    var seen = frame.previous_projection_inverse.transform_point(clip)
    var world = frame.previous_camera_world.transform_point(seen)
    var view_z = frame.view.transform_point(world).z
    if frame.perspective:
        return ((frame.near + view_z) * frame.far) / (
            (frame.far - frame.near) * view_z
        )
    return (view_z + frame.near) / (frame.near - frame.far)


def traa_pixel(
    beauty: LightView,
    history: LightView,
    depth: FloatPlane,
    previous_depth: FloatPlane,
    velocity: FloatPlane,
    x: Int,
    y: Int,
    frame: TraaFrame,
) -> FloatColor:
    """Return one pixel of three.js's TRAA resolve.

    Args:
        beauty: The new frame, straight.
        history: The last result, straight.
        depth: The new frame's window depth, one float a pixel.
        previous_depth: The last frame's window depth.
        velocity: The new frame's velocity, two floats a pixel.
        x: The column.
        y: The row, down from the top.
        frame: The frame's numbers.

    Returns:
        The result, straight.
    """
    var w = frame.width
    var h = frame.height
    # The pixel's texture coordinate, down from the top as three.js's
    # WebGPU `uv()` runs.
    var u = (Float32(x) + 0.5) / Float32(w)
    var v_down = (Float32(y) + 0.5) / Float32(h)
    # The closest and farthest depths of the 3 by 3 neighbors.
    var closest = Float32(2)
    var closest_x = 0
    var closest_y = 0
    var farthest = Float32(-1)
    # Nine neighbors, fixed.
    for dx in range(-1, 2):  # pragma: no branch
        for dy in range(-1, 2):  # pragma: no branch
            var d = depth.load(x + dx, y + dy, 0)
            if d < closest:
                closest = d
                closest_x = x + dx
                closest_y = y + dy
            if d > farthest:
                farthest = d
    # The velocity, from normalized device coordinates to a texture
    # coordinate that grows down.
    var offset_u = velocity.load(closest_x, closest_y, 0) * 0.5
    var offset_v = velocity.load(closest_x, closest_y, 1) * -0.5
    var history_u = u - offset_u
    var history_v = v_down - offset_v
    var then = _previous_depth(previous_depth, history_u, history_v, frame)
    var valid_uv = (
        history_u >= 0 and history_v >= 0 and history_u <= 1 and history_v <= 1
    )
    var edge = farthest - closest > frame.edge_depth_diff
    var uncovered = closest - then > frame.depth_threshold
    var kept = valid_uv and (edge or not uncovered)
    var current = beauty.at(x, y)
    var past = history.tap(
        history_u * Float32(w) - 0.5, history_v * Float32(h) - 0.5
    )
    var moved_x = (u - history_u) * Float32(w)
    var moved_y = (v_down - history_v) * Float32(h)
    var motion = min(
        max(
            sqrt(moved_x * moved_x + moved_y * moved_y)
            / frame.max_velocity_length,
            0,
        ),
        1,
    )
    var weight = Float32(0.05)
    if frame.use_subpixel_correction:
        weight += subpixel_correction(offset_u, offset_v, w, h) * 0.25
    weight = min(max(weight + motion, 0), 1) if kept else Float32(1)
    # Variance clipping, over the pixel and its eight neighbors.
    var gamma = 0.5 + (1 - 0.5) * (1 - motion) * (1 - motion)
    var m1 = current
    var m2 = FloatColor(
        current.r * current.r,
        current.g * current.g,
        current.b * current.b,
        current.a * current.a,
    )
    var offsets = SIMD[DType.int32, 16](
        -1, -1, -1, 1, 1, -1, 1, 1, 1, 0, 0, -1, 0, 1, -1, 0
    )
    for at in range(8):  # pragma: no branch
        var near = _floor0(
            _load(
                beauty, x + Int(offsets[at * 2]), y + Int(offsets[at * 2 + 1])
            )
        )
        m1 = FloatColor(
            m1.r + near.r, m1.g + near.g, m1.b + near.b, m1.a + near.a
        )
        m2 = FloatColor(
            m2.r + near.r * near.r,
            m2.g + near.g * near.g,
            m2.b + near.b * near.b,
            m2.a + near.a * near.a,
        )
    var n = Float32(9)
    var mean = FloatColor(m1.r / n, m1.g / n, m1.b / n, m1.a / n)
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
    # The mean clamped into the box is the mean: only its alpha is read.
    var clipped = clip_aabb(mean, past, low, high)
    return flicker_reduction(current, clipped, weight)


def traa_render[
    C: Camera
](
    mut frame: RenderTarget,
    mut settings: TraaSettings,
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: C,
) raises:
    """Draw one frame of TRAA into `frame`: the scene through the camera
    moved by the next offset, its velocity measured without the move, and
    the resolve against the history. three.js's `TRAANode` with the scene
    pass before it.

    Args:
        frame: The composer's frame: its light and depth are replaced.
        settings: The pass's settings, and its history, which moves on.
        renderer: What the scene is drawn with. Its velocity history is
            the pass's.
        scene: The transform hierarchy, and the meshes and lights in it.
        assets: The geometry, materials and textures the meshes name.
        camera: The camera, before the move.

    Raises:
        Error: Everything `check_traa` and `Renderer.render_into` raise.
    """
    check_traa(settings)
    var w = renderer.width
    var h = renderer.height
    var jitter = traa_jitter(settings.jitter_index)
    var moved = JitteredCamera(
        camera, scene, jitter.x - 0.5, jitter.y - 0.5, w, h
    )
    var drawn = RenderTarget(
        w, h, renderer.background, FLOAT_TARGET, [OUTPUT_COLOR, OUTPUT_VELOCITY]
    )
    renderer.set_velocity_projection(camera.projection_matrix())
    try:
        renderer.render_into(drawn, scene, assets, moved)
    finally:
        renderer.set_velocity_projection(None)
    # three.js's `updateBefore`: the last frame's matrices, then this one's.
    settings.previous_camera_world = settings.camera_world
    settings.previous_projection_inverse = settings.projection_inverse
    var world = moved.view
    world.invert()
    settings.camera_world = world
    var unprojects = moved.projection
    unprojects.invert()
    settings.projection_inverse = unprojects
    var beauty = List[FloatColor](capacity=w * h)
    var velocities = List[Float32](capacity=w * h * 2)
    # The renderer's size is positive, so the loop runs.
    for slot in range(w * h):  # pragma: no branch
        beauty.append(drawn.straight_at(slot))
        velocities.append(drawn.velocities[slot].x)
        velocities.append(drawn.velocities[slot].y)
    # A new size starts the history over from this frame, as three.js
    # copies the beauty into it, and forgets the last depth.
    if settings.history_width != w or settings.history_height != h:
        settings.history = beauty.copy()
        settings.history_width = w
        settings.history_height = h
        settings.previous_depth = List[Float32]()
    if len(settings.previous_depth) == 0:
        settings.previous_depth = List[Float32](length=w * h, fill=0)
    var window = DepthView(
        drawn.depth,
        w,
        h,
        moved.projection,
        Length(moved.near, METER),
        Length(moved.far, METER),
        drawn.depth_mode,
    ).depth.copy()
    var numbers = TraaFrame(
        w,
        h,
        moved.near,
        moved.far,
        moved.projection.elements[11] != 0,
        moved.view,
        settings,
    )
    var beauty_view = LightView(beauty, w, h)
    var history_view = LightView(settings.history, w, h)
    var depth = FloatPlane(window, w, h, 1)
    var previous = FloatPlane(settings.previous_depth, w, h, 1)
    var motion = FloatPlane(velocities, w, h, 2)
    var result = List[FloatColor](capacity=w * h)
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            result.append(
                traa_pixel(
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
    for slot in range(w * h):  # pragma: no branch
        frame.colors[slot] = result[slot].premultiplied()
        frame.data[slot] = False
        frame.depth[slot] = drawn.depth[slot]
    frame.depth_mode = drawn.depth_mode
    settings.history = result^
    settings.previous_depth = window^
    # three.js's `clearViewOffset`: the next offset.
    settings.jitter_index = (settings.jitter_index + 1) % TRAA_JITTERS
