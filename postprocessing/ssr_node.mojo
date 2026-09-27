# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Screen-space reflections as three.js r186's `SSRNode` draws them, from
`examples/jsm/tsl/display/SSRNode.js`, added over the frame as three.js's
SSR example adds them.

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

**Inputs.** The frame's normal attachment gives the normals and its
`OUTPUT_METAL_ROUGH` attachment the metalness and roughness, as the
example's `mrt` gives them.

**Not ported.** The node's stochastic mode, its environment sampling, its
history and its binary refinement are left out: the example leaves them
off.
"""

from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from postprocessing.display_nodes import luminance_of, scaled_size
from postprocessing.sampling import LightView, u_of, v_of
from postprocessing.screen_space import DepthView
from render.framebuffer import FloatColor
from render.target import RenderTarget
from std.math import floor, isfinite, max, min
from units.si import Length, METER


# The blur chain's levels, three.js's five pushed mipmaps, and the level a
# roughness of one reads.
comptime SSR_NODE_LEVELS = 5
comptime SSR_NODE_TOP_LEVEL = SSR_NODE_LEVELS - 1


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


def check_ssr_node(settings: SsrNodeSettings) raises:
    """Refuse settings no SSR node pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If a number is not finite, the distance or the scale is not
            positive, the thickness is negative, or the blur's reach is
            negative.
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
        """Gather a frame's inputs.

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


def _normal_at(view: LightView, u: Float32, v_down: Float32) -> Vector3:
    """Return the normal at a place, bilinear and made unit length."""
    var tap = view.sample(u, 1 - v_down)
    var n = Vector3(tap.r, tap.g, tap.b)
    var size = n.length()
    if size == 0:
        return n
    return n * (1 / size)


def _cross(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product."""
    return Vector3(
        a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x
    )


def _view_z(frame: SsrNodeFrame, depth: Float32) -> Float32:
    """Return the view z of a window depth: three.js's
    `perspectiveDepthToViewZ` or `orthographicDepthToViewZ`."""
    if frame.perspective:
        return (frame.near * frame.far) / (
            (frame.far - frame.near) * depth - frame.far
        )
    return depth * (frame.near - frame.far) - frame.near


def ssr_node_pixel(
    frame: SsrNodeFrame,
    view: DepthView,
    x: Int,
    y: Int,
    settings: SsrNodeSettings,
) -> FloatColor:
    """Return one pixel of `SSRNode`'s reflections, unblurred.

    Args:
        frame: The frame's views and numbers.
        view: The frame's depth.
        x: The column of the reflections.
        y: The row, down from the top.
        settings: The pass's settings.

    Returns:
        The reflected light and, in alpha, the distance to the hit. Zero
        where there is no surface, no metalness or no hit.
    """
    var w = Float32(frame.width)
    var h = Float32(frame.height)
    # The node's `uv`, down from the top.
    var u = (Float32(x) + 0.5) / w
    var v_down = (Float32(y) + 0.5) / h
    var depth = view.depth_at(u, 1 - v_down)
    if depth >= 1:
        return FloatColor(0, 0, 0, 0)
    var here = view.position(u, 1 - v_down, depth)
    var world = frame.camera_world.transform_point(here)
    var normal = _normal_at(frame.normals, u, v_down)
    var incident = Vector3(0, 0, -1)
    if frame.perspective:
        incident = here * (1 / here.length())
    var metalness = frame.metal_rough.sample(u, 1 - v_down).r
    if not settings.reflect_non_metals and metalness <= 0:
        return FloatColor(0, 0, 0, 0)
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
        return FloatColor(0, 0, 0, 0)
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
            _cross(there - here, there - far_end).length()
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
        break
    if found == 0:
        return FloatColor(0, 0, 0, 0)
    var hit = view.position(hit_u, 1 - hit_v, hit_depth)
    var plane_distance = normal.dot(hit) - normal.dot(here)
    var world_distance = (
        world - frame.camera_world.transform_point(hit)
    ).length()
    var seen = frame.color.sample(hit_u, 1 - hit_v)
    var ratio = 1 - plane_distance / settings.max_distance.value
    var fresnel = (incident.dot(reflected) + 1) / 2
    var weight = metalness * ratio * ratio * fresnel
    var r = seen.r * weight
    var g = seen.g * weight
    var b = seen.b * weight
    var light = max(luminance_of(r, g, b), 1e-4)
    var cap = min(settings.max_luminance / light, 1) * settings.intensity
    return FloatColor(
        max(r * cap, 0),
        max(g * cap, 0),
        max(b * cap, 0),
        max(world_distance, 0),
    )


def ssr_node_blur(
    source: LightView, width: Int, height: Int, size: Int, separation: Int
) -> List[FloatColor]:
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
    """
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


def ssr_node_light(
    mut frame: RenderTarget,
    view: DepthView,
    camera_world: Matrix4,
    settings: SsrNodeSettings,
) raises:
    """Add `SSRNode`'s reflections to the frame, read through its blur
    chain at each pixel's roughness where the settings ask.

    Args:
        frame: The frame. It must have a normal attachment and an
            `OUTPUT_METAL_ROUGH` one.
        view: The frame's depth, and the camera's projection.
        camera_world: The camera's world matrix.
        settings: The pass's settings.

    Raises:
        Error: If the frame lacks either attachment.
    """
    if not (frame.has_normals() and frame.has_metal_roughs()):
        raise Error(
            "An SSR node reads the frame's normal and metalness attachments"
        )
    var w = frame.width
    var h = frame.height
    var straight = List[FloatColor](capacity=w * h)
    var turned = List[FloatColor](capacity=w * h)
    var surfaces = List[FloatColor](capacity=w * h)
    for slot in range(w * h):  # pragma: no branch
        straight.append(frame.straight_at(slot))
        var n = frame.normals[slot]
        turned.append(FloatColor(n.x, n.y, n.z, 0))
        var s = frame.metal_roughs[slot]
        surfaces.append(FloatColor(s.x, s.y, 0, 0))
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
    var reflections = List[FloatColor](capacity=width * height)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            reflections.append(ssr_node_pixel(inputs, view, x, y, settings))
    # The chain: the reflections, then a blur a level's pixels apart at
    # each smaller level.
    var levels = List[List[FloatColor]]()
    var sizes = List[Int]()
    for level in range(SSR_NODE_LEVELS):  # pragma: no branch
        if level == 0:
            levels.append(reflections.copy())
        else:
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
            if settings.use_roughness:
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
                added = FloatColor(
                    a.r + (b.r - a.r) * t,
                    a.g + (b.g - a.g) * t,
                    a.b + (b.b - a.b) * t,
                    0,
                )
            else:
                added = LightView(reflections, width, height).sample(u, v)
            var slot = y * w + x
            var was = straight[slot]
            frame.colors[slot] = FloatColor(
                was.r + added.r, was.g + added.g, was.b + added.b, was.a
            ).premultiplied()
            frame.data[slot] = False
    _ = straight^
    _ = turned^
    _ = surfaces^
    _ = reflections^
    _ = levels^
