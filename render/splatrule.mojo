# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a Gaussian splat projects and what it covers, in arithmetic both
backends share.

`render.pointrule` is this module's neighbor for points, and it exists
for the same reason: the CPU pass and the GPU kernel must agree exactly,
so the rule lives in one place and both import it. `splat_alpha` and
`splat_depth_passes` allocate nothing and raise nothing, so they compile
for a device. `project_splat` runs on the host, as the transform of every
other primitive does.

## The projection

`project_splat` is three.js's `GaussianSplat` vertex shader. The splat's
3D covariance is carried into view space by the model-view matrix,
`W C W^T`, and onto the screen by the Jacobian of the perspective divide
at the splat's center, `J (W C W^T) J^T`. `KERNEL_2D_SIZE` is added to
the diagonal of that 2D covariance, a low-pass filter of about a third of
a pixel, and the opacity is scaled by `sqrt(det / det')`, so a splat does
not grow brighter when the filter widens it. The 2D covariance's
eigenvectors are the axes of the splat's ellipse on the screen, and the
square roots of its eigenvalues are its standard deviations in pixels,
held at `MAX_SCREEN_SPACE_SPLAT_SIZE` at most.

three.js draws each splat as a quad two standard deviations out along
both axes. A splat is not drawn when its center is behind
`NEAREST_VIEW_Z`, outside the near and far planes, or further than
`CLIP_XY` times `w` to a side, which keeps a splat that reaches into the
view from its edge.

## The fragment

`splat_alpha` is three.js's fragment shader. A pixel center's offset from
the splat's center is measured in standard deviations along each axis,
`u` and `v`. A pixel with `u^2 + v^2` above 4 is discarded, and every
other pixel takes the splat's color at the opacity `a exp(-(u^2 + v^2) /
2)`. The quad's corners are at `u` and `v` of plus or minus two, so the
disc of radius two is inside it and the discard decides coverage alone.

A splat tests depth and writes none, as three.js's material does: it is
hidden by an opaque surface in front of it and hides nothing behind it.
`splat_depth_passes` is the test, three.js's default less-or-equal, turned
round under `REVERSED_DEPTH`.
"""

from math.matrix4 import Matrix4
from math.vector3 import Vector3
from render.raster_state import (
    DepthMode,
    LOGARITHMIC_DEPTH,
    REVERSED_DEPTH,
)
from std.math import atan2, cos, exp, log2, max, min, sin, sqrt

# The low-pass filter added to the 2D covariance's diagonal, in pixels
# squared.
comptime KERNEL_2D_SIZE = Float32(0.3)
# The largest standard deviation a splat has on the screen, in pixels.
comptime MAX_SCREEN_SPACE_SPLAT_SIZE = Float32(1024)
# How far past the edge of the view, as a share of `w`, a center can be.
comptime CLIP_XY = Float32(1.4)
# The nearest a center's view-space z can be, in meters.
comptime NEAREST_VIEW_Z = Float32(-0.01)
# The square of how many standard deviations out a splat is drawn.
comptime SPLAT_RADIUS_SQ = Float32(4)

# How a `ProjectedSplat` is laid out in the flat float buffer the kernel
# reads, one lane per field.
comptime SPLAT_X = 0
comptime SPLAT_Y = 1
comptime SPLAT_DEPTH = 2
comptime SPLAT_AXIS_X = 3
comptime SPLAT_AXIS_Y = 4
comptime SPLAT_SCALE1 = 5
comptime SPLAT_SCALE2 = 6
comptime SPLAT_R = 7
comptime SPLAT_G = 8
comptime SPLAT_B = 9
comptime SPLAT_A = 10
comptime SPLAT_FLOATS = 11


@fieldwise_init
struct ProjectedSplat(ImplicitlyCopyable):
    """A splat on the screen: what three.js's vertex shader hands its
    quad's fragments."""

    # The center, in pixels: x to the right and y down from the top left.
    var x: Float32
    var y: Float32
    # The depth it is tested with, as the target stores depth.
    var depth: Float32
    # The ellipse's first axis, unit length, with y up the screen. The
    # second axis is this one turned a quarter to the left.
    var axis_x: Float32
    var axis_y: Float32
    # The standard deviations along the two axes, in pixels.
    var scale1: Float32
    var scale2: Float32
    # The color, linear and between zero and one, and the opacity.
    var r: Float32
    var g: Float32
    var b: Float32
    var a: Float32

    def append_to(self, mut flat: List[Float32]):
        """Append this splat's lanes, in the order `SPLAT_X` and the rest
        name them.

        Args:
            flat: The buffer to append to.
        """
        flat.append(self.x)
        flat.append(self.y)
        flat.append(self.depth)
        flat.append(self.axis_x)
        flat.append(self.axis_y)
        flat.append(self.scale1)
        flat.append(self.scale2)
        flat.append(self.r)
        flat.append(self.g)
        flat.append(self.b)
        flat.append(self.a)


@always_inline
def splat_alpha(splat: ProjectedSplat, x: Int, y: Int) -> Float32:
    """Return the opacity a splat gives a pixel, three.js's fragment
    shader.

    Args:
        splat: The splat.
        x: The pixel's column.
        y: The pixel's row, down from the top.

    Returns:
        `a exp(-r^2 / 2)` at the pixel's center, or zero where `r^2` is
        above 4 and three.js discards the fragment.
    """
    var dx = Float32(x) + 0.5 - splat.x
    var dy = splat.y - (Float32(y) + 0.5)
    var u = (dx * splat.axis_x + dy * splat.axis_y) / splat.scale1
    var v = (dy * splat.axis_x - dx * splat.axis_y) / splat.scale2
    var r2 = u * u + v * v
    if r2 > SPLAT_RADIUS_SQ:
        return 0
    return exp(r2 * -0.5) * splat.a


@always_inline
def splat_depth_passes(
    mode: DepthMode, depth: Float32, stored: Float32
) -> Bool:
    """Return whether a splat's fragment passes the depth test.

    Args:
        mode: How the target stores depth.
        depth: The splat's depth.
        stored: The depth the pixel holds.

    Returns:
        `depth <= stored`, three.js's `LessEqualDepth`, with the sides
        swapped under `REVERSED_DEPTH`.
    """
    if mode == REVERSED_DEPTH:
        return stored <= depth
    return depth <= stored


def splat_reach(splat: ProjectedSplat) -> Tuple[Float32, Float32]:
    """Return how far the splat's quad reaches from its center.

    Args:
        splat: The splat.

    Returns:
        The quad's half width and half height in pixels: every pixel the
        splat covers has its center within them.
    """
    var ax = abs(splat.axis_x)
    var ay = abs(splat.axis_y)
    return (
        2 * (ax * splat.scale1 + ay * splat.scale2),
        2 * (ay * splat.scale1 + ax * splat.scale2),
    )


def stored_splat_depth(
    mode: DepthMode, ndc_z: Float32, w: Float32, log_scale: Float32
) -> Float32:
    """Return the depth a splat is tested with, as
    `render.raster_state.fragment_depth` stores a fragment's.

    Args:
        mode: How the target stores depth.
        ndc_z: The center's NDC depth.
        w: The center's clip `w`.
        log_scale: `log_depth_factor` of the camera's far distance, read
            under `LOGARITHMIC_DEPTH`.

    Returns:
        The NDC depth, the logarithmic depth or the reversed depth.
    """
    if mode == LOGARITHMIC_DEPTH:
        return log_scale * log2(1 + w) - 1
    if mode == REVERSED_DEPTH:
        return (1 - ndc_z) * 0.5
    return ndc_z


@fieldwise_init
struct SplatView(ImplicitlyCopyable):
    """What `project_splat` needs of the camera and the target."""

    # The view matrix times the object's world matrix.
    var model_view: Matrix4
    # The camera's projection.
    var projection: Matrix4
    # The target's size in pixels.
    var width: Int
    var height: Int
    # How the target stores depth, and the log factor it reads.
    var depth_mode: DepthMode
    var log_scale: Float32


def _dot(a: Vector3, b: Vector3) -> Float32:
    """Return a dot product, as the shader's `dot`.

    Args:
        a: One vector.
        b: The other.

    Returns:
        The dot product.
    """
    return a.x * b.x + a.y * b.y + a.z * b.z


def project_splat(
    center: Vector3,
    covariance: List[Float32],
    at: Int,
    color: FloatRgba,
    view: SplatView,
) -> Optional[ProjectedSplat]:
    """Put one splat on the screen, three.js's `GaussianSplat` vertex
    shader.

    Args:
        center: The splat's center, in the object's space.
        covariance: The covariances, six floats a splat.
        at: Where this splat's six floats start.
        color: Its color between zero and one, before the clamp, and its
            opacity.
        view: The camera and the target.

    Returns:
        The splat on the screen, or none where three.js moves it off the
        screen: a center behind `NEAREST_VIEW_Z`, past the near or far
        plane, or further than `CLIP_XY` times `w` to a side.
    """
    ref m = view.model_view.elements
    ref p = view.projection.elements
    var vx = m[0] * center.x + m[4] * center.y + m[8] * center.z + m[12]
    var vy = m[1] * center.x + m[5] * center.y + m[9] * center.z + m[13]
    var vz = m[2] * center.x + m[6] * center.y + m[10] * center.z + m[14]
    var vw = m[3] * center.x + m[7] * center.y + m[11] * center.z + m[15]
    var cx = p[0] * vx + p[4] * vy + p[8] * vz + p[12] * vw
    var cy = p[1] * vx + p[5] * vy + p[9] * vz + p[13] * vw
    var cz = p[2] * vx + p[6] * vy + p[10] * vz + p[14] * vw
    var cw = p[3] * vx + p[7] * vy + p[11] * vz + p[15] * vw
    var limit = cw * CLIP_XY
    if vz >= NEAREST_VIEW_Z or cz < -cw or cz > cw:
        return None
    if cx < -limit or cx > limit or cy < -limit or cy > limit:
        return None
    var r0 = Vector3(m[0], m[4], m[8])
    var r1 = Vector3(m[1], m[5], m[9])
    var r2 = Vector3(m[2], m[6], m[10])
    var cov0 = Vector3(covariance[at], covariance[at + 1], covariance[at + 2])
    var cov1 = Vector3(
        covariance[at + 1], covariance[at + 3], covariance[at + 4]
    )
    var cov2 = Vector3(
        covariance[at + 2], covariance[at + 4], covariance[at + 5]
    )
    var vc0 = Vector3(_dot(r0, cov0), _dot(r0, cov1), _dot(r0, cov2))
    var vc1 = Vector3(_dot(r1, cov0), _dot(r1, cov1), _dot(r1, cov2))
    var vc2 = Vector3(_dot(r2, cov0), _dot(r2, cov1), _dot(r2, cov2))
    var c00 = _dot(vc0, r0)
    var c01 = _dot(vc0, r1)
    var c02 = _dot(vc0, r2)
    var c11 = _dot(vc1, r1)
    var c12 = _dot(vc1, r2)
    var c22 = _dot(vc2, r2)
    var inv_z = 1 / min(vz, NEAREST_VIEW_Z)
    var inv_z2 = inv_z * inv_z
    var fx = Float32(view.width) * 0.5 * p[0]
    var fy = Float32(view.height) * 0.5 * p[5]
    var j00 = -fx * inv_z
    var j11 = -fy * inv_z
    var j02 = fx * vx * inv_z2
    var j12 = fy * vy * inv_z2
    var a_base = j00 * j00 * c00 + j00 * j02 * c02 * 2 + j02 * j02 * c22
    var b = (
        j00 * j11 * c01 + j00 * j12 * c02 + j02 * j11 * c12 + (j02 * j12 * c22)
    )
    var c_base = j11 * j11 * c11 + j11 * j12 * c12 * 2 + j12 * j12 * c22
    var a = a_base + KERNEL_2D_SIZE
    var c = c_base + KERNEL_2D_SIZE
    var det_base = a_base * c_base - b * b
    var det = a * c - b * b
    var alpha_scale = sqrt(max(det_base / max(det, 0.000001), 0))
    var half_trace = (a + c) * 0.5
    var half_gap = (a - c) * 0.5
    var radius = sqrt(max(half_gap * half_gap + b * b, 0.0000001))
    var lambda1 = max(half_trace + radius, 0.0000001)
    var lambda2 = max(half_trace - radius, 0.0000001)
    # three.js keeps the axis at (1, 0) for a radius of 0.00001 or less,
    # which the floor above never lets it be.
    var angle = atan2(b * 2, a - c) * 0.5
    var axis_x = cos(angle)
    var axis_y = sin(angle)
    return ProjectedSplat(
        (cx / cw + 1) * 0.5 * Float32(view.width),
        (1 - cy / cw) * 0.5 * Float32(view.height),
        stored_splat_depth(view.depth_mode, cz / cw, cw, view.log_scale),
        axis_x,
        axis_y,
        min(sqrt(lambda1), MAX_SCREEN_SPACE_SPLAT_SIZE),
        min(sqrt(lambda2), MAX_SCREEN_SPACE_SPLAT_SIZE),
        min(max(color.r, 0), 1),
        min(max(color.g, 0), 1),
        min(max(color.b, 0), 1),
        color.a * alpha_scale,
    )


@fieldwise_init
struct FloatRgba(ImplicitlyCopyable):
    """A color and an opacity as four floats, before any clamp."""

    var r: Float32
    var g: Float32
    var b: Float32
    var a: Float32
