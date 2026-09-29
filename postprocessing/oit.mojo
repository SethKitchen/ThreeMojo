# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Weighted blended order-independent transparency: three.js r186's
`OITPassNode`, from `examples/jsm/tsl/display/OITPassNode.js`.

The pass draws the scene without its order-independent objects first:
each object whose material is transparent, with normal blending and no
transmission. Then it weighs every transparent fragment in front of that
frame's depth, whatever its order:

- The accumulation adds `(rgb * a, a) * w`, where `w` is three.js's
  default weight, `a * clamp(0.03 / ((z / 200)^4 + 1e-5), 0.01, 3000)`,
  for `z` the fragment's distance along the view.
- The revealage multiplies `1 - a`: how much of the frame shows through.
- The composite is `mix(accum.rgb / max(accum.a, 1e-5), frame.rgb,
  revealage)`, with the frame's alpha.

**One fragment a draw.** three.js blends every fragment of a transparent
object into its accumulation targets. This port draws each
order-independent draw alone and weighs what it leaves at each pixel: the
object's fragments there blended over transparent black, at the nearest
fragment's depth. For an object that does not cover itself, such as a
pane or a closed convex shape seen from outside, that is each fragment.
The revealage is kept as a float, where three.js keeps eight bits.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.scene import Scene
from postprocessing.screen_space import DepthView
from render.framebuffer import Color, FloatColor
from render.rasterizer import DRAW_SPLATS
from render.target import FLOAT_TARGET, RenderTarget
from renderers.draw_filter import NO_OIT_DRAWS, ONE_OIT_DRAW, oit_capable
from renderers.renderer import Renderer
from std.math import max, min, pow
from units.si import Length, METER


def oit_weight(alpha: Float32, distance: Float32) -> Float32:
    """Return three.js's default weight of a fragment.

    Args:
        alpha: The fragment's alpha.
        distance: How far along the view the fragment is, in meters:
            `-positionView.z`.

    Returns:
        `alpha * clamp(0.03 / ((distance / 200)^4 + 1e-5), 0.01, 3000)`.
    """
    var far = pow(distance / 200, Float32(4))
    return alpha * min(max(0.03 / (far + 1e-5), Float32(0.01)), Float32(3000))


struct OitAccumulation(Movable):
    """What three.js's two accumulation targets hold: the weighted light
    and its weighted alpha, and the revealage, one pixel each."""

    var accum: List[FloatColor]
    var revealage: List[Float32]

    def __init__(out self, count: Int):
        """Start cleared: no light, and all of the frame showing, as three.js
        clears `accum` to transparent black and `revealage` to one.

        Args:
            count: How many pixels.
        """
        self.accum = List[FloatColor](length=count, fill=FloatColor(0, 0, 0, 0))
        self.revealage = List[Float32](length=count, fill=1)

    def add(mut self, slot: Int, light: FloatColor, distance: Float32):
        """Weigh one fragment in: its blend modes, `One, One` into the
        accumulation and `Zero, OneMinusSrcColor` into the revealage.

        Args:
            slot: The pixel.
            light: The fragment's light, premultiplied: `(rgb * a, a)`.
            distance: How far along the view it is, in meters.
        """
        var w = oit_weight(light.a, distance)
        var held = self.accum[slot]
        self.accum[slot] = FloatColor(
            held.r + light.r * w,
            held.g + light.g * w,
            held.b + light.b * w,
            held.a + light.a * w,
        )
        self.revealage[slot] = self.revealage[slot] * (1 - light.a)


def oit_composite(
    beauty: FloatColor, accum: FloatColor, revealage: Float32
) -> FloatColor:
    """Return three.js's composite of the frame and the accumulation.

    Args:
        beauty: The frame without the order-independent objects, straight.
        accum: The weighted light and alpha.
        revealage: How much of the frame shows through.

    Returns:
        The pixel, straight, with the frame's alpha.
    """
    var share = max(accum.a, Float32(1e-5))
    var r = accum.r / share
    var g = accum.g / share
    var b = accum.b / share
    return FloatColor(
        r + (beauty.r - r) * revealage,
        g + (beauty.g - g) * revealage,
        b + (beauty.b - b) * revealage,
        beauty.a,
    )


def oit_draw_count[
    C: Camera
](renderer: Renderer, scene: Scene, assets: Assets, camera: C) raises -> Int:
    """Return how many of a frame's draws are order-independent.

    Args:
        renderer: What the scene is drawn with.
        scene: The transform hierarchy, and the meshes and lights in it.
        assets: The geometry, materials and textures the meshes name.
        camera: The camera.

    Returns:
        The count.

    Raises:
        Error: Everything `Renderer.prepare_frame` raises.
    """
    var prepared = renderer.prepare_frame(scene, assets, camera)
    var count = 0
    for index in range(len(prepared.items)):
        if prepared.items[index].kind == DRAW_SPLATS:
            continue
        if oit_capable(assets.materials.get(prepared.items[index].material)):
            count += 1
    return count


def oit_render[
    C: Camera
](
    mut frame: RenderTarget,
    renderer: Renderer,
    scene: Scene,
    assets: Assets,
    camera: C,
) raises:
    """Draw one frame of three.js's `OITPassNode` into `frame`: the scene
    without its order-independent objects, then those objects weighed over
    it.

    Args:
        frame: The composer's frame: its light, depth and attachments are
            replaced by the first draw's.
        renderer: What the scene is drawn with.
        scene: The transform hierarchy, and the meshes and lights in it.
        assets: The geometry, materials and textures the meshes name.
        camera: The camera.

    Raises:
        Error: Everything `Renderer.render_into` raises.
    """
    var w = frame.width
    var h = frame.height
    var base = renderer.resized(w, h)
    base.draw_filter = NO_OIT_DRAWS
    base.render_into(frame, scene, assets, camera)
    var opaque = DepthView(
        frame.depth,
        w,
        h,
        camera.projection_matrix(),
        Length(camera.near_distance(), METER),
        Length(camera.far_distance(), METER),
        frame.depth_mode,
    )
    var sums = OitAccumulation(w * h)
    var count = oit_draw_count(base, scene, assets, camera)
    base.draw_filter = ONE_OIT_DRAW
    for index in range(count):
        base.oit_draw = index
        var drawn = RenderTarget(w, h, Color(0, 0, 0, 0), FLOAT_TARGET)
        base.render_into(drawn, scene, assets, camera)
        var seen = DepthView(
            drawn.depth,
            w,
            h,
            camera.projection_matrix(),
            Length(camera.near_distance(), METER),
            Length(camera.far_distance(), METER),
            drawn.depth_mode,
        )
        for slot in range(w * h):  # pragma: no branch
            var light = drawn.colors[slot]
            var depth = seen.depth[slot]
            # A fragment that is there and not behind the frame's depth,
            # three.js's `LessEqualDepth` against the shared depth buffer.
            if light.a > 0 and depth <= opaque.depth[slot]:
                var distance = -seen.view_z(depth)
                sums.add(slot, light, distance)
    for slot in range(w * h):  # pragma: no branch
        frame.colors[slot] = oit_composite(
            frame.straight_at(slot), sums.accum[slot], sums.revealage[slot]
        ).premultiplied()
        frame.data[slot] = False
