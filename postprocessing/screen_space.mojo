# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Screen-space passes: three.js's `SSAOPass`, `SAOPass`, `SSRPass` and
`OutlinePass`, each reading the depth a render leaves beside its light.

**Depth.** A render target keeps the NDC depth of every pixel, minus one
at the near plane and one at the far, and infinity where nothing was
drawn. `DepthView` turns it into what three.js's shaders read from a depth
texture: the window depth, zero to one, one where nothing was drawn. A
logarithmic or a reversed depth is read back into that same window depth
first, so every pass reads one form whatever the renderer stored. With
the camera's projection it answers the two questions every pass asks: where
a pixel is in view space, and how far away that is.

**Normals.** three.js draws the scene a second time with a
`MeshNormalMaterial` to learn each pixel's normal. This port reads them
from the frame's own normal attachment when it has one -- a render target
with `OUTPUT_NORMAL`, filled in the same pass as the light -- and the
composer gives its frame one whenever a pass here runs. Where a pixel has
no normal, or the frame has no attachment, it reads them from the depth
instead, with the reconstruction three.js's own `GTAOShader` uses: of the
two neighbors on each axis, the one that continues the surface more
smoothly gives the slope. That reconstruction shows a curved surface's
facets, because the depth of a triangle is flat where the attachment
interpolates.

**Randomness.** three.js draws its kernels and seeds from `Math.random`.
This port draws them from `math.utils.SeededRandom`, so a pass with the
same seed gives the same frame.

The passes run on the host, as every pass in `postprocessing` does.
"""

from core.layers import Layers
from math.matrix4 import Matrix4
from math.sine import fraction, noise_scale, sin_float32
from math.utils import SeededRandom
from math.vector3 import Vector3
from postprocessing.sampling import sample, u_of, v_of
from render.framebuffer import FloatColor
from render.raster_state import (
    LOGARITHMIC_DEPTH,
    REVERSED_DEPTH,
    STANDARD_DEPTH,
    DepthMode,
    cleared_depth,
    is_nearer,
    log_depth_factor,
)
from render.target import RenderTarget
from render.texture import Texture
from render.texture_store import NO_TEXTURE, TextureId
from std.math import cos, exp, exp2, floor, fma, isfinite, pi, sin, sqrt
from units.si import Duration, Length, METER, SECOND


@fieldwise_init
struct ScreenSpaceOutput(Equatable, ImplicitlyCopyable, Writable):
    """What a screen-space pass leaves in the frame, as a type rather than
    a bare int: three.js's `SSAOPass.OUTPUT`, `SAOPass.OUTPUT` and
    `SSRPass.OUTPUT` in one.

    The type stops a bare integer at compile time; it does not stop
    `ScreenSpaceOutput(6)`, which the checks refuse.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the six outputs there are."""
        return (
            self == DEFAULT_OUTPUT
            or self == EFFECT_OUTPUT
            or self == BLUR_OUTPUT
            or self == BEAUTY_OUTPUT
            or self == DEPTH_OUTPUT
            or self == NORMAL_OUTPUT
        )


# The effect over the frame: three.js's `OUTPUT.Default`.
comptime DEFAULT_OUTPUT = ScreenSpaceOutput(0)
# The effect alone, before its blur: `OUTPUT.SSAO`, `OUTPUT.SAO` and
# `OUTPUT.SSR`.
comptime EFFECT_OUTPUT = ScreenSpaceOutput(1)
# The effect alone, after its blur: `OUTPUT.Blur`.
comptime BLUR_OUTPUT = ScreenSpaceOutput(2)
# The frame as it came in: `OUTPUT.Beauty`.
comptime BEAUTY_OUTPUT = ScreenSpaceOutput(3)
# One minus the linear depth, as gray: `OUTPUT.Depth`.
comptime DEPTH_OUTPUT = ScreenSpaceOutput(4)
# The view-space normal, packed to zero through one: `OUTPUT.Normal`.
comptime NORMAL_OUTPUT = ScreenSpaceOutput(5)

# `SSAOPass`'s noise texture is four by four texels, repeated.
comptime SSAO_NOISE_SIZE = 4
# `SSAOBlurShader` averages the five by five texels around a pixel.
comptime SSAO_BLUR_REACH = 2
# `SAOShader`'s `NUM_SAMPLES` and `NUM_RINGS`.
comptime SAO_SAMPLES = 7
comptime SAO_RINGS = 4
# three.js's `EPSILON`: a window depth this near one is the background.
comptime SAO_EPSILON = Float32(1e-6)
# `SSRBlurShader`'s weights for the pixel and for each of its four
# neighbors.
comptime SSR_BLUR_CENTER = Float32(0.2)
comptime SSR_BLUR_SIDE = Float32(0.2)
# `OutlinePass`'s `MAX_EDGE_THICKNESS` and `MAX_EDGE_GLOW`: how many taps
# each side its two blurs take.
comptime OUTLINE_MAX_THICKNESS = 4
comptime OUTLINE_MAX_GLOW = 4
# `OutlinePass` detects edges on a copy of the mask at this fraction of
# the frame's size, and blurs the glow at half that again.
comptime OUTLINE_DOWNSAMPLE = 2


# --- depth ------------------------------------------------------------------


struct DepthView(Movable):
    """A frame's depth as three.js's screen-space shaders read a depth
    texture, with the camera that drew it.
    """

    var width: Int
    var height: Int
    # The window depth of every pixel, row by row from the top: zero at the
    # near plane, one at the far plane and where nothing was drawn.
    var depth: List[Float32]
    # The camera's projection, three.js's `cameraProjectionMatrix`.
    var projection: Matrix4
    # Its inverse, three.js's `cameraInverseProjectionMatrix`.
    var inverse: Matrix4
    # The camera's near and far distances, in meters.
    var near: Float32
    var far: Float32
    # Whether the projection divides by distance: three.js's
    # `PERSPECTIVE_CAMERA`.
    var perspective: Bool
    # The view-space normals the frame was drawn with, row by row from the
    # top, zero where no surface wrote one: `RenderTarget.normals`. Empty
    # when the frame has no normal attachment.
    var drawn: List[Vector3]

    def __init__(
        out self,
        ndc_depth: List[Float32],
        width: Int,
        height: Int,
        projection: Matrix4,
        near: Length,
        far: Length,
        mode: DepthMode = STANDARD_DEPTH,
        normals: List[Vector3] = List[Vector3](),
    ) raises:
        """Read a render target's depth through the camera that drew it.

        Each stored depth is read back into the window depth of the
        projection. A reversed depth is one minus itself. A logarithmic
        depth gives back its `w`, `2^((d + 1) / logDepthBufFC) - 1`, which
        the projection turns into a window depth. Under a projection that
        does not divide by distance a logarithmic depth is the standard
        one, as the renderer stores it there.

        Args:
            ndc_depth: One stored depth per pixel, row by row from the top,
                the mode's clear where nothing was drawn:
                `RenderTarget.depth`.
            width: The frame's width in pixels.
            height: The frame's height in pixels.
            projection: The camera's projection matrix.
            near: The camera's near distance.
            far: The camera's far distance.
            mode: How the depth is stored: `RenderTarget.depth_mode`.
            normals: The target's normal attachment,
                `RenderTarget.normals`, or empty, the default, to
                reconstruct every normal from the depth.

        Raises:
            Error: If a size is not positive, the depth or a non-empty
                list of normals does not have one entry per pixel, the
                distances are not finite or the near one is not in front
                of the far one, the projection cannot be inverted, or the
                depth mode is none of the three.
        """
        if width <= 0 or height <= 0:
            raise Error("A depth view's size must be positive")
        if len(ndc_depth) != width * height:
            raise Error("A depth view needs one depth per pixel")
        if len(normals) != 0 and len(normals) != width * height:
            raise Error("A depth view needs one normal per pixel or none")
        if not (
            isfinite(near.value)
            and isfinite(far.value)
            and near.value < far.value
        ):
            raise Error("A depth view's near distance must be before its far")
        if projection.determinant() == 0:
            raise Error("A depth view's projection must be invertible")
        if not mode.is_valid():
            raise Error("A depth mode that is none of the three")
        self.width = width
        self.height = height
        self.projection = projection
        self.inverse = projection
        self.inverse.invert()
        self.near = near.value
        self.far = far.value
        # A perspective projection puts minus the distance in w.
        self.perspective = projection.elements[11] != 0
        var logarithmic = mode == LOGARITHMIC_DEPTH and self.perspective
        var factor = log_depth_factor(far.value)
        self.depth = List[Float32](capacity=width * height)
        for slot in range(width * height):  # pragma: no branch
            # Both sizes are positive, so the loop runs.
            var z = ndc_depth[slot]
            var window = Float32(1)
            if isfinite(z):
                window = z * 0.5 + 0.5
                if mode == REVERSED_DEPTH:
                    window = 1 - z
                if logarithmic:
                    var w = exp2((z + 1) / factor) - 1
                    var seen = projection.transform_point(Vector3(0, 0, -w))
                    window = seen.z * 0.5 + 0.5
            self.depth.append(window)
        self.drawn = normals.copy()

    def slot_at(self, u: Float32, v: Float32) -> Int:
        """Return the pixel a texture coordinate falls in, held at the
        edges: a depth texture read with `NearestFilter` and
        `ClampToEdgeWrapping`, as three.js reads one.

        Args:
            u: Across, zero at the left edge.
            v: Up, zero at the bottom edge.

        Returns:
            The pixel's index, row by row from the top.
        """
        var px = max(
            Float32(0), min(Float32(self.width - 1), u * Float32(self.width))
        )
        var py = max(
            Float32(0),
            min(Float32(self.height - 1), v * Float32(self.height)),
        )
        return (self.height - 1 - Int(py)) * self.width + Int(px)

    def depth_at(self, u: Float32, v: Float32) -> Float32:
        """Return the window depth at a texture coordinate: three.js's
        `getDepth`.

        Args:
            u: Across, zero at the left edge.
            v: Up, zero at the bottom edge.

        Returns:
            The window depth of the pixel there.
        """
        return self.depth[self.slot_at(u, v)]

    def position(self, u: Float32, v: Float32, depth: Float32) -> Vector3:
        """Return the view-space point at a texture coordinate and a window
        depth: three.js's `getViewPosition`.

        three.js multiplies the NDC point by the clip w first; the inverse
        projection's divide gives the same point.

        Args:
            u: Across, zero at the left edge.
            v: Up, zero at the bottom edge.
            depth: The window depth.

        Returns:
            The point, in the camera's space.
        """
        return self.inverse.transform_point(
            Vector3(u * 2 - 1, v * 2 - 1, depth * 2 - 1)
        )

    def view_z(self, depth: Float32) -> Float32:
        """Return the view-space z of a window depth, negative in front of
        the camera: three.js's `getViewZ`.

        Args:
            depth: The window depth.

        Returns:
            The z, in meters.
        """
        return self.position(0.5, 0.5, depth).z

    def linear_depth(self, view_z: Float32) -> Float32:
        """Return a view-space z as a fraction of the way from the near
        plane to the far: three.js's `viewZToOrthographicDepth`.

        Args:
            view_z: The z, negative in front of the camera.

        Returns:
            Zero at the near plane and one at the far.
        """
        return (view_z + self.near) / (self.near - self.far)

    def _texel(self, x: Int, y: Int) -> Float32:
        """Return the window depth at a pixel counted up from the bottom:
        `texelFetch` on a depth texture, which reads zero past the edge
        under WebGL's robust access. A neighbor of zero depth continues no
        surface, so a pixel at the edge takes its slope from inside."""
        var inside = x >= 0 and x < self.width and y >= 0 and y < self.height
        if not inside:
            return 0
        return self.depth[(self.height - 1 - y) * self.width + x]

    def normal_at(self, x: Int, y: Int) -> Vector3:
        """Return the view-space normal at a pixel, reconstructed from the
        depth: three.js's `GTAOShader` `computeNormalFromDepth`.

        Along each axis the pass takes the neighbor that continues the
        surface better: the one whose depth is nearer to the straight line
        through the next two. The normal is the cross of the two slopes.

        Args:
            x: The column.
            y: The row, counted down from the top.

        Returns:
            The unit normal, facing the camera.
        """
        var up = self.height - 1 - y
        var c0 = self._texel(x, up)
        var l2 = self._texel(x - 2, up)
        var l1 = self._texel(x - 1, up)
        var r1 = self._texel(x + 1, up)
        var r2 = self._texel(x + 2, up)
        var b2 = self._texel(x, up - 2)
        var b1 = self._texel(x, up - 1)
        var t1 = self._texel(x, up + 1)
        var t2 = self._texel(x, up + 2)
        var dl = abs((2 * l1 - l2) - c0)
        var dr = abs((2 * r1 - r2) - c0)
        var db = abs((2 * b1 - b2) - c0)
        var dt = abs((2 * t1 - t2) - c0)
        var u = u_of(x, self.width)
        var v = v_of(y, self.height)
        var du = 1 / Float32(self.width)
        var dv = 1 / Float32(self.height)
        var center = self.position(u, v, c0)
        var dpdx: Vector3
        if dl < dr:
            dpdx = center - self.position(u - du, v, l1)
        else:
            dpdx = self.position(u + du, v, r1) - center
        var dpdy: Vector3
        if db < dt:
            dpdy = center - self.position(u, v - dv, b1)
        else:
            dpdy = self.position(u, v + dv, t1) - center
        dpdx.cross(dpdy)
        dpdx.normalize()
        return dpdx

    def normals(self) -> List[Vector3]:
        """Return the normal of every pixel, row by row from the top: the
        one the frame was drawn with where it has one, and otherwise the
        one `normal_at` reconstructs from the depth.

        Returns:
            One unit normal per pixel.
        """
        var out = List[Vector3](capacity=self.width * self.height)
        var kept = len(self.drawn) != 0
        var y = 0
        while y < self.height:
            var x = 0
            while x < self.width:
                var normal = Vector3(0, 0, 0)
                if kept:
                    normal = self.drawn[y * self.width + x]
                if normal.length() == 0:
                    normal = self.normal_at(x, y)
                out.append(normal)
                x += 1
            y += 1
        return out^


def show_values(mut frame: RenderTarget, values: List[Float32]):
    """Write one value per pixel as opaque gray light: what three.js's
    passes copy to the screen for an effect or a depth output.

    Args:
        frame: The frame, replaced.
        values: One value per pixel.
    """
    for slot in range(len(frame.colors)):  # pragma: no branch
        var value = values[slot]
        frame.colors[slot] = FloatColor(value, value, value, 1)
        frame.data[slot] = False


def show_depth(mut frame: RenderTarget, view: DepthView):
    """Write one minus each pixel's linear depth as gray: three.js's
    `SSAODepthShader`, the `OUTPUT.Depth` of every screen-space pass.

    Args:
        frame: The frame, replaced.
        view: The frame's depth.
    """
    var values = List[Float32](capacity=len(view.depth))
    for slot in range(len(view.depth)):  # pragma: no branch
        values.append(1 - view.linear_depth(view.view_z(view.depth[slot])))
    show_values(frame, values)


def show_normals(mut frame: RenderTarget, normals: List[Vector3]):
    """Write each pixel's normal packed to zero through one, as three.js's
    `packNormalToRGB` packs it for `OUTPUT.Normal`.

    Args:
        frame: The frame, replaced.
        normals: One unit normal per pixel.
    """
    for slot in range(len(frame.colors)):  # pragma: no branch
        var n = normals[slot]
        frame.colors[slot] = FloatColor(
            n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1
        )
        frame.data[slot] = False


def multiply_light(mut frame: RenderTarget, values: List[Float32]):
    """Scale the light of every pixel by a value, alpha kept: three.js's
    copy with `DstColorFactor` and `ZeroFactor`, how SSAO and SAO lay their
    occlusion over the frame.

    Args:
        frame: The frame, changed in place.
        values: One factor per pixel.
    """
    for slot in range(len(frame.colors)):  # pragma: no branch
        frame.colors[slot] = frame.colors[slot].scaled(values[slot])


def _check_output(output: ScreenSpaceOutput) raises:
    """Refuse an output that is none of the six."""
    if not output.is_valid():
        raise Error("A screen-space output must be one of the six named")


# --- SSAO -------------------------------------------------------------------


struct SsaoSettings(ImplicitlyCopyable):
    """What `SSAOPass` reads, named as three.js names it."""

    # How far the kernel reaches from the surface: `kernelRadius`.
    var kernel_radius: Length
    # How many samples the kernel holds: `kernelSize`.
    var kernel_size: Int
    # The least and the most a sample may sit behind the surface, as a
    # fraction of the near-to-far range, to occlude: `minDistance` and
    # `maxDistance`.
    var min_distance: Float32
    var max_distance: Float32
    # The seed of the kernel and of the noise.
    var seed: Int
    # What the pass leaves: `output`.
    var output: ScreenSpaceOutput

    def __init__(out self):
        """Start with three.js's defaults: a radius of eight, 32 samples,
        and occlusion between 0.005 and 0.1 of the range."""
        self.kernel_radius = Length(8.0, METER)
        self.kernel_size = 32
        self.min_distance = 0.005
        self.max_distance = 0.1
        self.seed = 0
        self.output = DEFAULT_OUTPUT


def check_ssao(settings: SsaoSettings) raises:
    """Refuse SSAO settings no pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the output is none of the six, the radius or a distance
            is negative or not finite, or the kernel is empty.
    """
    _check_output(settings.output)
    if not (
        isfinite(settings.kernel_radius.value)
        and isfinite(settings.min_distance)
        and isfinite(settings.max_distance)
    ):
        raise Error("An SSAO setting must be finite")
    if (
        settings.kernel_radius.value < 0
        or settings.min_distance < 0
        or settings.max_distance < 0
    ):
        raise Error("An SSAO setting must not be negative")
    if settings.kernel_size < 1:
        raise Error("An SSAO kernel holds at least one sample")


def ssao_kernel(size: Int, seed: Int) raises -> List[Vector3]:
    """Return the hemisphere of samples SSAO tests: three.js's
    `generateSampleKernel`.

    Each sample is a random direction above the surface, scaled so the
    samples crowd toward the center: the `i`th of `n` by the mix from a
    tenth to one at `(i / n)` squared.

    Args:
        size: How many samples.
        seed: The seed of the generator the directions come from.

    Returns:
        The samples, in the surface's tangent space, `z` along the normal.

    Raises:
        Error: If the size is not positive.
    """
    if size < 1:
        raise Error("An SSAO kernel holds at least one sample")
    var random = SeededRandom(seed)
    var kernel = List[Vector3](capacity=size)
    var index = 0
    while index < size:
        var x = Float32(random.next()) * 2 - 1
        var y = Float32(random.next()) * 2 - 1
        var z = Float32(random.next())
        var direction = Vector3(x, y, z)
        direction.normalize()
        var scale = Float32(index) / Float32(size)
        scale = 0.1 + 0.9 * scale * scale
        kernel.append(direction * scale)
        index += 1
    return kernel^


def ssao_noise(seed: Int) -> List[Float32]:
    """Return the four by four values SSAO turns its kernel by, one per
    pixel and repeated across the frame: three.js's
    `generateRandomKernelRotations`.

    three.js passes two random numbers through simplex noise. This draws
    the value from minus one to one directly.

    Args:
        seed: The seed of the generator.

    Returns:
        Sixteen values, row by row from the bottom.
    """
    var random = SeededRandom(seed)
    var noise = List[Float32](capacity=SSAO_NOISE_SIZE * SSAO_NOISE_SIZE)
    for _ in range(SSAO_NOISE_SIZE * SSAO_NOISE_SIZE):  # pragma: no branch
        noise.append(Float32(random.next()) * 2 - 1)
    return noise^


def ssao_occlusion(
    view: DepthView,
    normals: List[Vector3],
    kernel: List[Vector3],
    noise: List[Float32],
    radius: Length,
    min_distance: Float32,
    max_distance: Float32,
) -> List[Float32]:
    """Return how much light reaches each pixel past its surroundings:
    three.js's `SSAOShader`.

    The kernel is turned about the pixel's normal by the noise, scaled by
    the radius and set on the pixel's surface. A sample occludes when the
    frame's depth where it lands is in front of it by more than the least
    distance and less than the most, both as fractions of the range.

    Args:
        view: The frame's depth.
        normals: One view-space normal per pixel.
        kernel: The samples; see `ssao_kernel`.
        noise: Sixteen values; see `ssao_noise`.
        radius: How far the kernel reaches.
        min_distance: The least depth a sample may be hidden by.
        max_distance: The most.

    Returns:
        One minus the share of the samples occluded, per pixel: one where
        nothing was drawn.
    """
    var out = List[Float32](capacity=view.width * view.height)
    var y = 0
    while y < view.height:
        var x = 0
        while x < view.width:
            out.append(
                _ssao_pixel(
                    view,
                    normals,
                    kernel,
                    noise,
                    radius.value,
                    min_distance,
                    max_distance,
                    x,
                    y,
                )
            )
            x += 1
        y += 1
    return out^


def _ssao_pixel(
    view: DepthView,
    normals: List[Vector3],
    kernel: List[Vector3],
    noise: List[Float32],
    radius: Float32,
    min_distance: Float32,
    max_distance: Float32,
    x: Int,
    y: Int,
) -> Float32:
    """Return one pixel of `ssao_occlusion`."""
    var slot = y * view.width + x
    var depth = view.depth[slot]
    if depth == 1:
        return 1
    var center = view.position(u_of(x, view.width), v_of(y, view.height), depth)
    var normal = normals[slot]
    var up = view.height - 1 - y
    var turn = noise[
        (up % SSAO_NOISE_SIZE) * SSAO_NOISE_SIZE + x % SSAO_NOISE_SIZE
    ]
    var random = Vector3(turn, turn, turn)
    var tangent = random - normal * random.dot(normal)
    var length = tangent.length()
    # three.js normalizes a zero vector to not-a-number, which occludes
    # nothing.
    if not length > 0:
        return 1
    tangent = tangent * (1 / length)
    var bitangent = normal
    bitangent.cross(tangent)
    var occluded = 0
    var index = 0
    while index < len(kernel):
        var k = kernel[index]
        var offset = tangent * k.x + bitangent * k.y + normal * k.z
        var point = center + offset * radius
        var ndc = view.projection.transform_point(point)
        var found = view.depth_at(ndc.x * 0.5 + 0.5, ndc.y * 0.5 + 0.5)
        var real = view.linear_depth(view.view_z(found))
        var delta = view.linear_depth(point.z) - real
        var hidden = delta > min_distance and delta < max_distance
        if hidden:
            occluded += 1
        index += 1
    return 1 - min(Float32(1), Float32(occluded) / Float32(len(kernel)))


def ssao_blur(values: List[Float32], width: Int, height: Int) -> List[Float32]:
    """Return each value averaged with the five by five around it, held at
    the edges: three.js's `SSAOBlurShader`.

    Args:
        values: One value per pixel.
        width: The frame's width in pixels.
        height: The frame's height in pixels.

    Returns:
        The averages.
    """
    var out = List[Float32](length=width * height, fill=0)
    var taps = Float32((2 * SSAO_BLUR_REACH + 1) * (2 * SSAO_BLUR_REACH + 1))
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var sum = Float32(0)
            var j = -SSAO_BLUR_REACH
            while j <= SSAO_BLUR_REACH:
                var i = -SSAO_BLUR_REACH
                while i <= SSAO_BLUR_REACH:
                    var column = max(0, min(width - 1, x + i))
                    var row = max(0, min(height - 1, y + j))
                    sum += values[row * width + column]
                    i += 1
                j += 1
            out[y * width + x] = sum / taps
            x += 1
        y += 1
    return out^


def ssao_light(
    mut frame: RenderTarget, view: DepthView, settings: SsaoSettings
) raises:
    """Darken the frame where its surfaces are hemmed in: three.js's
    `SSAOPass` after its beauty render.

    The occlusion is worked out per pixel, blurred five by five, and
    multiplies the light. The other outputs replace the frame.

    Args:
        frame: The frame, changed in place.
        view: Its depth.
        settings: The pass's settings.

    Raises:
        Error: Everything `check_ssao` raises, or if the frame and the
            depth are not one size.
    """
    check_ssao(settings)
    if frame.width != view.width or frame.height != view.height:
        raise Error("An SSAO frame and its depth must be one size")
    var output = settings.output
    if output == BEAUTY_OUTPUT:
        return
    if output == DEPTH_OUTPUT:
        show_depth(frame, view)
        return
    var normals = view.normals()
    if output == NORMAL_OUTPUT:
        show_normals(frame, normals)
        return
    var occlusion = ssao_occlusion(
        view,
        normals,
        ssao_kernel(settings.kernel_size, settings.seed),
        ssao_noise(settings.seed),
        settings.kernel_radius,
        settings.min_distance,
        settings.max_distance,
    )
    if output == EFFECT_OUTPUT:
        show_values(frame, occlusion)
        return
    var blurred = ssao_blur(occlusion, view.width, view.height)
    if output == BLUR_OUTPUT:
        show_values(frame, blurred)
        return
    multiply_light(frame, blurred)


# --- SAO --------------------------------------------------------------------


struct SaoSettings(ImplicitlyCopyable):
    """What `SAOPass` reads, named as three.js names its `params`."""

    # `saoBias`: what each sample's occlusion is lowered by.
    var bias: Float32
    # `saoIntensity`: what the sum is scaled by.
    var intensity: Float32
    # `saoScale`: how fast occlusion falls off with distance, per far
    # distance.
    var scale: Float32
    # `saoKernelRadius`: how far the seven samples reach, in pixels.
    var kernel_radius: Float32
    # `saoMinResolution`: a slope below this, times the far distance, does
    # not occlude.
    var min_resolution: Float32
    # `saoBlur`: whether the occlusion is blurred.
    var blur: Bool
    # `saoBlurRadius`: how many pixels each side the blur reaches.
    var blur_radius: Int
    # `saoBlurStdDev`: the blur's standard deviation, in pixels.
    var blur_std_dev: Float32
    # `saoBlurDepthCutoff`: a neighbor this far from the pixel, as a
    # fraction of the near-to-far range, stops the blur on its side.
    var blur_depth_cutoff: Float32
    # The seed of the per-frame `randomSeed`, advanced every frame.
    var seed: Int
    # `output`.
    var output: ScreenSpaceOutput

    def __init__(out self):
        """Start with three.js's defaults."""
        self.bias = 0.5
        self.intensity = 0.18
        self.scale = 1.0
        self.kernel_radius = 100.0
        self.min_resolution = 0.0
        self.blur = True
        self.blur_radius = 8
        self.blur_std_dev = 4.0
        self.blur_depth_cutoff = 0.01
        self.seed = 0
        self.output = DEFAULT_OUTPUT


def check_sao(settings: SaoSettings) raises:
    """Refuse SAO settings no pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the output is none of the six, a setting is not finite,
            the intensity, minimum resolution, blur radius or depth cutoff
            is negative, or the scale, kernel radius or standard deviation
            is not positive.
    """
    _check_output(settings.output)
    if not (
        isfinite(settings.bias)
        and isfinite(settings.intensity)
        and isfinite(settings.scale)
        and isfinite(settings.kernel_radius)
        and isfinite(settings.min_resolution)
        and isfinite(settings.blur_std_dev)
        and isfinite(settings.blur_depth_cutoff)
    ):
        raise Error("An SAO setting must be finite")
    if (
        settings.intensity < 0
        or settings.min_resolution < 0
        or settings.blur_radius < 0
        or settings.blur_depth_cutoff < 0
    ):
        raise Error("An SAO setting must not be negative")
    if not (
        settings.scale > 0
        and settings.kernel_radius > 0
        and settings.blur_std_dev > 0
    ):
        raise Error("An SAO scale, kernel radius and deviation are positive")


def glsl_rand(u: Float32, v: Float32) -> Float32:
    """Return three.js's `rand` from its `common` chunk: the fractional
    part of a large sine of the coordinate's dot with a fixed vector,
    taken modulo pi first.

    The sine is `math.sine.sin_float32`, and each multiply that feeds an
    add rounds once, so the host and a kernel give the same noise.

    Args:
        u: The first coordinate.
        v: The second.

    Returns:
        A number from zero up to one.
    """
    var dt = fma(u, Float32(12.9898), v * Float32(78.233))
    var sn = fma(-Float32(pi), floor(dt / Float32(pi)), dt)
    return fraction(noise_scale(sin_float32(sn)))


def sao_sample_occlusion(
    center: Vector3,
    normal: Vector3,
    point: Vector3,
    scale_per_far: Float32,
    min_resolution_far: Float32,
    bias: Float32,
) -> Float32:
    """Return how much one sample occludes the pixel: three.js's
    `getOcclusion`.

    Args:
        center: The pixel's view-space point.
        normal: The pixel's view-space normal.
        point: The sample's view-space point.
        scale_per_far: The scale over the far distance.
        min_resolution_far: The minimum resolution times the far distance.
        bias: What the occlusion is lowered by.

    Returns:
        The sample's occlusion, never negative. Zero for a sample at the
        pixel's own point, where three.js divides zero by zero.
    """
    var delta = point - center
    var screen = scale_per_far * delta.length()
    if screen == 0:
        return 0
    var raw = (normal.dot(delta) - min_resolution_far) / screen - bias
    return max(Float32(0), raw) / (1 + screen * screen)


def sao_occlusion(
    view: DepthView,
    normals: List[Vector3],
    settings: SaoSettings,
    random_seed: Float32,
) -> List[Float32]:
    """Return one minus the ambient occlusion of every pixel: three.js's
    `SAOShader`.

    Seven samples spiral out from the pixel over four turns, their start
    turned by a hash of the pixel and the seed. Each sample on a surface
    adds its occlusion; the average is scaled by the intensity.

    Args:
        view: The frame's depth.
        normals: One view-space normal per pixel.
        settings: The pass's settings.
        random_seed: The frame's seed, three.js's `randomSeed`.

    Returns:
        One minus the occlusion per pixel: one where nothing was drawn, or
        where no sample landed on a surface.
    """
    var out = List[Float32](capacity=view.width * view.height)
    var y = 0
    while y < view.height:
        var x = 0
        while x < view.width:
            out.append(_sao_pixel(view, normals, settings, random_seed, x, y))
            x += 1
        y += 1
    return out^


def _sao_pixel(
    view: DepthView,
    normals: List[Vector3],
    settings: SaoSettings,
    random_seed: Float32,
    x: Int,
    y: Int,
) -> Float32:
    """Return one pixel of `sao_occlusion`."""
    var slot = y * view.width + x
    var depth = view.depth[slot]
    if depth >= 1 - SAO_EPSILON:
        return 1
    var u = u_of(x, view.width)
    var v = v_of(y, view.height)
    var center = view.position(u, v, depth)
    var normal = normals[slot]
    var turn = Float32(2 * pi)
    var angle_step = turn * Float32(SAO_RINGS) / Float32(SAO_SAMPLES)
    var angle = glsl_rand(u + random_seed, v + random_seed) * turn
    var step_u = settings.kernel_radius / Float32(SAO_SAMPLES * view.width)
    var step_v = settings.kernel_radius / Float32(SAO_SAMPLES * view.height)
    var radius_u = step_u
    var radius_v = step_v
    var sum = Float32(0)
    var weight = Float32(0)
    var index = 0
    while index < SAO_SAMPLES:
        var su = u + cos(angle) * radius_u
        var sv = v + sin(angle) * radius_v
        radius_u += step_u
        radius_v += step_v
        angle += angle_step
        index += 1
        var found = view.depth_at(su, sv)
        if found >= 1 - SAO_EPSILON:
            continue
        sum += sao_sample_occlusion(
            center,
            normal,
            view.position(su, sv, found),
            settings.scale / view.far,
            settings.min_resolution * view.far,
            settings.bias,
        )
        weight += 1
    if weight == 0:
        return 1
    return 1 - sum * (settings.intensity / weight)


def blur_weights(radius: Int, std_dev: Float32) -> List[Float32]:
    """Return the Gaussian weights of taps zero through `radius` pixels
    out: three.js's `BlurShaderUtils.createSampleWeights`.

    Args:
        radius: The farthest tap.
        std_dev: The standard deviation, in pixels.

    Returns:
        One weight per tap, the center first.
    """
    var weights = List[Float32](capacity=radius + 1)
    for tap in range(radius + 1):  # pragma: no branch
        # A radius is never negative, so the center tap is always there.
        var x = Float32(tap)
        weights.append(
            exp(-(x * x) / (2 * std_dev * std_dev))
            / (sqrt(Float32(2 * pi)) * std_dev)
        )
    return weights^


def depth_limited_blur(
    values: List[Float32],
    view: DepthView,
    weights: List[Float32],
    cutoff: Float32,
    across: Bool,
) -> List[Float32]:
    """Blur one value per pixel along one axis, stopping each side at the
    first neighbor whose distance differs by more than `cutoff`: three.js's
    `DepthLimitedBlurShader`.

    Args:
        values: One value per pixel.
        view: The frame's depth.
        weights: The weight of each tap, the center first.
        cutoff: The largest difference in distance the blur crosses, in
            meters.
        across: True to blur along rows, False along columns.

    Returns:
        The blurred values: one where nothing was drawn.
    """
    var width = view.width
    var height = view.height
    var out = List[Float32](length=width * height, fill=1)
    var reach = len(weights) - 1
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var slot = y * width + x
            var depth = view.depth[slot]
            var column = x
            x += 1
            # Where nothing was drawn three.js discards, and the target
            # keeps its white clear.
            if depth >= 1 - SAO_EPSILON:
                continue
            var center = -view.view_z(depth)
            var total = weights[0]
            var sum = values[slot] * total
            var stopped_ahead = False
            var stopped_behind = False
            var tap = 1
            while tap <= reach:
                var w = weights[tap]
                var ahead: Int
                var behind: Int
                if across:
                    ahead = y * width + min(width - 1, column + tap)
                    behind = y * width + max(0, column - tap)
                else:
                    ahead = max(0, y - tap) * width + column
                    behind = min(height - 1, y + tap) * width + column
                var far_ahead = abs(-view.view_z(view.depth[ahead]) - center)
                stopped_ahead = stopped_ahead or far_ahead > cutoff
                if not stopped_ahead:
                    sum += values[ahead] * w
                    total += w
                var far_behind = abs(-view.view_z(view.depth[behind]) - center)
                stopped_behind = stopped_behind or far_behind > cutoff
                if not stopped_behind:
                    sum += values[behind] * w
                    total += w
                tap += 1
            out[slot] = sum / total
        y += 1
    return out^


def sao_light(
    mut frame: RenderTarget,
    view: DepthView,
    settings: SaoSettings,
    random_seed: Float32,
) raises:
    """Darken the frame by scalable ambient occlusion: three.js's
    `SAOPass`.

    The occlusion is worked out per pixel, blurred down and then across
    by the depth-limited blur if asked, and multiplies the light. The other
    outputs replace the frame.

    Args:
        frame: The frame, changed in place.
        view: The depth of the scene as the camera sees it.
        settings: The pass's settings.
        random_seed: The frame's seed, three.js's `randomSeed`.

    Raises:
        Error: Everything `check_sao` raises, or if the frame and the depth
            are not one size.
    """
    check_sao(settings)
    if frame.width != view.width or frame.height != view.height:
        raise Error("An SAO frame and its depth must be one size")
    var output = settings.output
    if output == BEAUTY_OUTPUT:
        return
    if output == DEPTH_OUTPUT:
        show_depth(frame, view)
        return
    var normals = view.normals()
    if output == NORMAL_OUTPUT:
        show_normals(frame, normals)
        return
    var occlusion = sao_occlusion(view, normals, settings, random_seed)
    if output == EFFECT_OUTPUT:
        show_values(frame, occlusion)
        return
    if settings.blur:
        var weights = blur_weights(settings.blur_radius, settings.blur_std_dev)
        var cutoff = settings.blur_depth_cutoff * (view.far - view.near)
        var down = depth_limited_blur(occlusion, view, weights, cutoff, False)
        occlusion = depth_limited_blur(down, view, weights, cutoff, True)
    if output == BLUR_OUTPUT:
        show_values(frame, occlusion)
        return
    multiply_light(frame, occlusion)


# --- SSR --------------------------------------------------------------------


struct SsrSettings(ImplicitlyCopyable):
    """What `SSRPass` reads, named as three.js names it."""

    # `opacity`: how much of a reflection shows, at most.
    var opacity: Float32
    # `maxDistance`: how far from the surface a reflection is looked for.
    var max_distance: Length
    # `thickness`: how thick each surface is taken to be.
    var thickness: Length
    # `infiniteThick`: whether anything behind a surface counts as a hit.
    var infinite_thick: Bool
    # `distanceAttenuation`: whether a reflection fades with distance.
    var distance_attenuation: Bool
    # `fresnel`: whether a reflection fades as the view meets the surface
    # square on.
    var fresnel: Bool
    # `blur`: whether the reflections are blurred.
    var blur: Bool
    # `output`.
    var output: ScreenSpaceOutput
    # `selects`, as a set of layers: when `selective` is on, only the
    # objects on them reflect, as three.js's metalness mask has it. Off by
    # default, when every surface reflects, as three.js's `selects` of
    # `null` has it.
    var selective: Bool
    var selects: Layers
    # `bouncing`: whether the reflections are read from the frame the pass
    # made last time, so they gather bounces frame by frame.
    var bouncing: Bool

    def __init__(out self):
        """Start with three.js's defaults."""
        self.selective = False
        self.selects = Layers(UInt32(0))
        self.bouncing = False
        self.opacity = 0.5
        self.max_distance = Length(180.0, METER)
        self.thickness = Length(0.018, METER)
        self.infinite_thick = False
        self.distance_attenuation = True
        self.fresnel = True
        self.blur = True
        self.output = DEFAULT_OUTPUT


def check_ssr(settings: SsrSettings) raises:
    """Refuse SSR settings no pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the output is none of the six, a setting is not finite,
            the opacity is outside zero to one, the thickness is negative,
            or the reach is not positive.
    """
    _check_output(settings.output)
    if not (
        isfinite(settings.opacity)
        and isfinite(settings.max_distance.value)
        and isfinite(settings.thickness.value)
    ):
        raise Error("An SSR setting must be finite")
    if settings.opacity < 0 or settings.opacity > 1:
        raise Error("An SSR opacity runs from zero to one")
    if settings.thickness.value < 0:
        raise Error("An SSR thickness must not be negative")
    if not settings.max_distance.value > 0:
        raise Error("An SSR reach must be positive")


def _to_screen(view: DepthView, point: Vector3) -> Vector3:
    """Return a view-space point in pixels up from the bottom left:
    three.js's `viewPositionToXY`."""
    var ndc = view.projection.transform_point(point)
    return Vector3(
        (ndc.x + 1) / 2 * Float32(view.width),
        (ndc.y + 1) / 2 * Float32(view.height),
        0,
    )


def _line_distance(point: Vector3, a: Vector3, b: Vector3) -> Float32:
    """Return how far a point is from the line through `a` and `b`:
    three.js's `pointToLineDistance`."""
    var arm = point - a
    arm.cross(point - b)
    return arm.length() / (b - a).length()


def ssr_reflections(
    view: DepthView,
    colors: List[FloatColor],
    normals: List[Vector3],
    settings: SsrSettings,
) -> List[FloatColor]:
    """Return what each pixel reflects, and how strongly: three.js's
    `SSRShader`.

    A ray leaves the pixel's surface mirrored about its normal and is
    walked across the screen a pixel at a time, out to the reach. The first
    surface it passes behind, within the thickness and facing it, is what
    the pixel reflects. The strength fades with the distance and with how
    square on the view meets the surface, if asked.

    Args:
        view: The frame's depth.
        colors: The frame's light.
        normals: One view-space normal per pixel.
        settings: The pass's settings.

    Returns:
        Per pixel, the reflected light, premultiplied as the frame is, and
        the strength in alpha. Transparent black where nothing is reflected.
    """
    var out = List[FloatColor](capacity=view.width * view.height)
    var y = 0
    while y < view.height:
        var x = 0
        while x < view.width:
            out.append(_ssr_pixel(view, colors, normals, settings, x, y))
            x += 1
        y += 1
    return out^


def _ssr_pixel(
    view: DepthView,
    colors: List[FloatColor],
    normals: List[Vector3],
    settings: SsrSettings,
    x: Int,
    y: Int,
) -> FloatColor:
    """Return one pixel of `ssr_reflections`."""
    var none = FloatColor(0, 0, 0, 0)
    var width = view.width
    var height = view.height
    var res_x = Float32(width)
    var res_y = Float32(height)
    var slot = y * width + x
    var depth = view.depth[slot]
    # three.js asks whether the distance reaches the far plane; in window
    # depth that is a depth of one, which is where nothing was drawn.
    if depth >= 1:
        return none
    var u = u_of(x, width)
    var v = v_of(y, height)
    var origin = view.position(u, v, depth)
    var normal = normals[slot]
    var incident = Vector3(0, 0, -1)
    if view.perspective:
        incident = origin
        incident.normalize()
    var reflected = incident - normal * (2 * normal.dot(incident))
    var facing = -incident.dot(normal)
    # A surface seen edge on, or from behind, reflects nothing: three.js
    # divides by this and walks a ray of no finite end.
    if not facing > 0:
        return none
    var reach = settings.max_distance.value
    var end = origin + reflected * (reach / facing)
    var behind_eye = view.perspective and end.z > -view.near
    if behind_eye:
        var t = (-view.near - origin.z) / reflected.z
        end = origin + reflected * t
    var d0x = u * res_x
    var d0y = v * res_y
    var d1 = _to_screen(view, end)
    var x_len = d1.x - d0x
    var y_len = d1.y - d0y
    var total_len = sqrt(x_len * x_len + y_len * y_len)
    var total_step = max(abs(x_len), abs(y_len))
    var x_span = x_len / total_step
    var y_span = y_len / total_step
    # three.js's `MAX_STEP`, the frame's diagonal, and its break once the
    # walk reaches the end.
    var max_step = Float32(Int(sqrt(Float32(width * width + height * height))))
    var steps = min(total_step, max_step)
    var i = Float32(0)
    while i < steps:
        var px = d0x + i * x_span
        var py = d0y + i * y_span
        i += 1
        var outside = px < 0 or px > res_x or py < 0 or py > res_y
        if outside:
            return none
        var dx = px - d0x
        var dy = py - d0y
        var s = sqrt(dx * dx + dy * dy) / total_len
        var su = px / res_x
        var sv = py / res_y
        var found = view.depth_at(su, sv)
        if found >= 1:
            continue
        var found_z = view.view_z(found)
        var hit_point = view.position(su, sv, found)
        var ray_z = origin.z + s * (end.z - origin.z)
        if view.perspective:
            var start = 1 / origin.z
            ray_z = 1 / (start + s * (1 / end.z - start))
        if not ray_z <= found_z:
            continue
        var away = _line_distance(hit_point, origin, end)
        var beside = view.position(su + 1 / res_x, sv, found)
        var thick = max((beside.x - hit_point.x) * 3, settings.thickness.value)
        var hit = settings.infinite_thick or away <= thick
        if not hit:
            continue
        if reflected.dot(normals[view.slot_at(su, sv)]) >= 0:
            continue
        var distance = normal.dot(hit_point - origin)
        if distance > reach:
            return none
        var strength = settings.opacity
        if settings.distance_attenuation:
            var ratio = 1 - distance / reach
            strength *= ratio * ratio
        if settings.fresnel:
            strength *= (incident.dot(reflected) + 1) / 2
        var seen = sample(colors, width, height, su, sv)
        return FloatColor(seen.r, seen.g, seen.b, strength)
    return none


def ssr_blur(
    source: List[FloatColor], width: Int, height: Int
) -> List[FloatColor]:
    """Return the reflections blurred with their four neighbors, each
    weighed by its strength: three.js's `SSRBlurShader`.

    Args:
        source: The reflections, strength in alpha.
        width: The frame's width in pixels.
        height: The frame's height in pixels.

    Returns:
        The blurred reflections. Where no neighbor reflects anything, the
        light is black, which three.js leaves divided by zero.
    """
    var out = List[FloatColor](
        length=width * height, fill=FloatColor(0, 0, 0, 0)
    )
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var c = source[y * width + x]
            var l = source[y * width + max(0, x - 1)]
            var r = source[y * width + min(width - 1, x + 1)]
            var b = source[min(height - 1, y + 1) * width + x]
            var t = source[max(0, y - 1) * width + x]
            var a = (
                c.a * SSR_BLUR_CENTER + (l.a + r.a + b.a + t.a) * SSR_BLUR_SIDE
            )
            var sum = FloatColor(
                c.r * c.a * SSR_BLUR_CENTER
                + (l.r * l.a + r.r * r.a + b.r * b.a + t.r * t.a)
                * SSR_BLUR_SIDE,
                c.g * c.a * SSR_BLUR_CENTER
                + (l.g * l.a + r.g * r.a + b.g * b.a + t.g * t.a)
                * SSR_BLUR_SIDE,
                c.b * c.a * SSR_BLUR_CENTER
                + (l.b * l.a + r.b * r.a + b.b * b.a + t.b * t.a)
                * SSR_BLUR_SIDE,
                a,
            )
            if a > 0:
                sum = FloatColor(sum.r / a, sum.g / a, sum.b / a, a)
            out[y * width + x] = sum
            x += 1
        y += 1
    return out^


def _show_reflections(mut frame: RenderTarget, reflections: List[FloatColor]):
    """Write the reflections alone, as three.js copies its SSR target: the
    light at its strength."""
    for slot in range(len(frame.colors)):  # pragma: no branch
        var seen = reflections[slot]
        frame.colors[slot] = FloatColor(
            seen.r * seen.a, seen.g * seen.a, seen.b * seen.a, seen.a
        )
        frame.data[slot] = False


def ssr_light(
    mut frame: RenderTarget,
    view: DepthView,
    settings: SsrSettings,
    selected: List[Bool] = List[Bool](),
    bounced: List[FloatColor] = List[FloatColor](),
) raises:
    """Lay what each surface reflects over the frame: three.js's `SSRPass`
    after its beauty render.

    The reflections are worked out per pixel, blurred twice if asked, and
    laid over the light by their strength, as three.js's `NormalBlending`
    lays them. The other outputs replace the frame.

    Args:
        frame: The frame, changed in place.
        view: Its depth.
        settings: The pass's settings.
        selected: With `settings.selective`, whether each pixel shows a
            selected object; a pixel that does not reflects nothing.
        bounced: With `settings.bouncing`, what the pass made last time,
            which the reflections are read from; empty, the first time,
            for transparent black, as three.js's fresh target holds.

    Raises:
        Error: Everything `check_ssr` raises, or if the frame and the depth
            are not one size.
    """
    check_ssr(settings)
    if frame.width != view.width or frame.height != view.height:
        raise Error("An SSR frame and its depth must be one size")
    var output = settings.output
    if output == BEAUTY_OUTPUT:
        return
    if output == DEPTH_OUTPUT:
        show_depth(frame, view)
        return
    var normals = view.normals()
    if output == NORMAL_OUTPUT:
        show_normals(frame, normals)
        return
    var source = frame.colors.copy()
    if settings.bouncing:
        source = bounced.copy()
        if len(source) != len(frame.colors):
            source = List[FloatColor](
                length=len(frame.colors), fill=FloatColor(0, 0, 0, 0)
            )
    var reflections = ssr_reflections(view, source, normals, settings)
    if settings.selective:
        # three.js's `SELECTIVE`: a pixel of no metalness returns early,
        # and its reflection is the target's clear, transparent black.
        for slot in range(len(reflections)):  # pragma: no branch
            var chosen = slot < len(selected) and selected[slot]
            if not chosen:
                reflections[slot] = FloatColor(0, 0, 0, 0)
    if output == EFFECT_OUTPUT:
        _show_reflections(frame, reflections)
        return
    if settings.blur:
        var once = ssr_blur(reflections, view.width, view.height)
        reflections = ssr_blur(once, view.width, view.height)
    if output == BLUR_OUTPUT:
        _show_reflections(frame, reflections)
        return
    for slot in range(len(frame.colors)):  # pragma: no branch
        var seen = reflections[slot]
        var under = frame.colors[slot]
        var keep = 1 - seen.a
        frame.colors[slot] = FloatColor(
            seen.r * seen.a + under.r * keep,
            seen.g * seen.a + under.g * keep,
            seen.b * seen.a + under.b * keep,
            seen.a + under.a * keep,
        )
        frame.data[slot] = False


# --- outline ----------------------------------------------------------------


struct OutlineSettings(ImplicitlyCopyable):
    """What `OutlinePass` reads, named as three.js names it."""

    # The layers whose objects are outlined: three.js's `selectedObjects`,
    # as a set of layers. None by default, which outlines nothing.
    var selection: Layers
    # `visibleEdgeColor` and `hiddenEdgeColor`, linear.
    var visible_edge_color: FloatColor
    var hidden_edge_color: FloatColor
    # `edgeStrength`: what the outline is scaled by.
    var edge_strength: Float32
    # `edgeGlow`: how much of the wide blur is added.
    var edge_glow: Float32
    # `edgeThickness`: how far the narrow blur reaches.
    var edge_thickness: Float32
    # `pulsePeriod`: how long the outline takes to pulse, or zero for no
    # pulse.
    var pulse_period: Duration
    # `usePatternTexture` and `patternTexture`: whether the selected
    # objects are filled with a pattern, and the texture it is read from,
    # in the assets the composer is given, six times across the frame.
    var use_pattern_texture: Bool
    var pattern_texture: TextureId

    def __init__(out self):
        """Start with three.js's defaults and nothing selected."""
        self.selection = Layers(UInt32(0))
        self.visible_edge_color = FloatColor(1, 1, 1, 1)
        self.hidden_edge_color = FloatColor(0.1, 0.04, 0.02, 1)
        self.edge_strength = 3.0
        self.edge_glow = 0.0
        self.edge_thickness = 1.0
        self.pulse_period = Duration(0.0, SECOND)
        self.use_pattern_texture = False
        self.pattern_texture = NO_TEXTURE


def check_outline(settings: OutlineSettings) raises:
    """Refuse outline settings no pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If a setting or a color channel is not finite or is
            negative, or the thickness is not positive.
    """
    var visible = settings.visible_edge_color
    var hidden = settings.hidden_edge_color
    var channels: List[Float32] = [
        visible.r,
        visible.g,
        visible.b,
        hidden.r,
        hidden.g,
        hidden.b,
        settings.edge_strength,
        settings.edge_glow,
        settings.edge_thickness,
        settings.pulse_period.value,
    ]
    for value in channels:  # pragma: no branch
        # The list is built above with ten entries.
        if not (isfinite(value) and value >= 0):
            raise Error("An outline setting must be finite and not negative")
    if settings.use_pattern_texture and settings.pattern_texture == NO_TEXTURE:
        raise Error("An outline with a pattern must name its texture")
    if not settings.edge_thickness > 0:
        raise Error("An outline's thickness must be positive")


def _outline_blur(
    source: List[FloatColor],
    source_width: Int,
    source_height: Int,
    width: Int,
    height: Int,
    kernel_radius: Float32,
    max_radius: Int,
    across: Bool,
) -> List[FloatColor]:
    """Return `source` blurred along one axis into a `width` by `height`
    image: `OutlinePass`'s separable blur, `max_radius` taps each side
    spread over `kernel_radius` texels of the output, with a sigma of half
    the radius."""
    var out = List[FloatColor](
        length=width * height, fill=FloatColor(0, 0, 0, 0)
    )
    var sigma = kernel_radius / 2
    var step = kernel_radius / Float32(max_radius)
    var du = Float32(0)
    var dv = Float32(0)
    if across:
        du = step / Float32(width)
    else:
        dv = step / Float32(height)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var u = u_of(x, width)
            var v = v_of(y, height)
            var total = _gaussian(0, sigma)
            var sum = sample(source, source_width, source_height, u, v)
            sum = FloatColor(
                sum.r * total, sum.g * total, sum.b * total, sum.a * total
            )
            var tap = 1
            while tap <= max_radius:
                var w = _gaussian(
                    kernel_radius * Float32(tap) / Float32(max_radius), sigma
                )
                var t = Float32(tap)
                var ahead = sample(
                    source, source_width, source_height, u + du * t, v + dv * t
                )
                var behind = sample(
                    source, source_width, source_height, u - du * t, v - dv * t
                )
                sum = FloatColor(
                    sum.r + (ahead.r + behind.r) * w,
                    sum.g + (ahead.g + behind.g) * w,
                    sum.b + (ahead.b + behind.b) * w,
                    sum.a + (ahead.a + behind.a) * w,
                )
                total += 2 * w
                tap += 1
            out[y * width + x] = FloatColor(
                sum.r / total, sum.g / total, sum.b / total, sum.a / total
            )
            x += 1
        y += 1
    return out^


def _gaussian(x: Float32, sigma: Float32) -> Float32:
    """Return three.js's `gaussianPdf`."""
    return 0.39894 * exp(-0.5 * x * x / (sigma * sigma)) / sigma


def outline_mask(
    all_depth: List[Float32],
    selected_depth: List[Float32],
    mode: DepthMode = STANDARD_DEPTH,
) raises -> List[FloatColor]:
    """Return `OutlinePass`'s mask: red zero where a selected object is
    drawn and one elsewhere, green one where that object is hidden behind
    another or nothing is selected.

    three.js draws the other objects' depth and then the selected objects
    against it. The depth of the whole scene is the nearer of the two, so
    a selected surface is hidden exactly where the whole scene is nearer
    than it.

    Args:
        all_depth: The stored depth of the whole scene, per pixel.
        selected_depth: The stored depth of the selected objects alone,
            the mode's clear where none is drawn.
        mode: How both depths are stored, which says what a clear is and
            which of two depths is nearer.

    Returns:
        One mask texel per pixel.

    Raises:
        Error: If the two depths are not one length, or the depth mode is
            none of the three.
    """
    if len(all_depth) != len(selected_depth):
        raise Error("An outline's two depths must be one size")
    if not mode.is_valid():
        raise Error("A depth mode that is none of the three")
    var clear = cleared_depth(mode)
    var mask = List[FloatColor](capacity=len(all_depth))
    for slot in range(len(all_depth)):  # pragma: no branch
        # A frame is never empty.
        var chosen = selected_depth[slot]
        if chosen == clear:
            mask.append(FloatColor(1, 1, 1, 1))
            continue
        var hidden = Float32(0)
        if is_nearer(mode, all_depth[slot], chosen):
            hidden = 1
        mask.append(FloatColor(0, hidden, 1, 1))
    return mask^


def outline_light(
    mut frame: RenderTarget,
    all_depth: List[Float32],
    selected_depth: List[Float32],
    settings: OutlineSettings,
    time: Duration,
    mode: DepthMode = STANDARD_DEPTH,
    pattern: Texture = Texture(),
) raises:
    """Draw a glowing edge around the selected objects: three.js's
    `OutlinePass`.

    The mask is copied down to half the frame's size. Its edges are found
    there, colored by whether the selected surface is seen or hidden, and
    blurred narrow at half size and wide at a quarter. The narrow blur and
    the wide one times the glow, scaled by the strength, are added to the
    light outside the selected objects. Alpha is kept.

    Args:
        frame: The frame, changed in place.
        all_depth: The stored depth of the whole scene, per pixel.
        selected_depth: The stored depth of the selected objects alone.
        settings: The pass's settings.
        time: How long the pass has run, which drives the pulse.
        mode: How both depths are stored; see `outline_mask`.
        pattern: The texture `settings.pattern_texture` names, read when
            `use_pattern_texture` is on. With it, the selected objects are
            filled with one less the pattern's red, half as bright where
            they are hidden, as three.js's overlay adds it.

    Raises:
        Error: Everything `check_outline` and `outline_mask` raise, or if
            the depths are not the frame's size.
    """
    check_outline(settings)
    var width = frame.width
    var height = frame.height
    if len(all_depth) != width * height:
        raise Error("An outline's depth must be the frame's size")
    var mask = outline_mask(all_depth, selected_depth, mode)
    var half_width = (width + 1) // OUTLINE_DOWNSAMPLE
    var half_height = (height + 1) // OUTLINE_DOWNSAMPLE
    var quarter_width = (half_width + 1) // OUTLINE_DOWNSAMPLE
    var quarter_height = (half_height + 1) // OUTLINE_DOWNSAMPLE
    var down = List[FloatColor](capacity=half_width * half_height)
    for y in range(half_height):  # pragma: no branch
        for x in range(half_width):  # pragma: no branch
            down.append(
                sample(
                    mask,
                    width,
                    height,
                    u_of(x, half_width),
                    v_of(y, half_height),
                )
            )
    var visible = settings.visible_edge_color
    var hidden = settings.hidden_edge_color
    var period = settings.pulse_period.value
    if period > 0:
        # three.js reads `performance.now()` in milliseconds.
        var scalar = Float32(1.25 / 2) + cos(
            time.value * 1000 * 0.01 / period
        ) * Float32(0.75 / 2)
        visible = visible.scaled(scalar)
        hidden = hidden.scaled(scalar)
    var edges = List[FloatColor](capacity=half_width * half_height)
    var du = 1 / Float32(half_width)
    var dv = 1 / Float32(half_height)
    for y in range(half_height):  # pragma: no branch
        for x in range(half_width):  # pragma: no branch
            var u = u_of(x, half_width)
            var v = v_of(y, half_height)
            var c1 = sample(down, half_width, half_height, u + du, v)
            var c2 = sample(down, half_width, half_height, u - du, v)
            var c3 = sample(down, half_width, half_height, u, v + dv)
            var c4 = sample(down, half_width, half_height, u, v - dv)
            var diff1 = (c1.r - c2.r) * 0.5
            var diff2 = (c3.r - c4.r) * 0.5
            var d = sqrt(diff1 * diff1 + diff2 * diff2)
            var seen = min(min(c1.g, c2.g), min(c3.g, c4.g))
            var color = hidden
            if 1 - seen > 0.001:
                color = visible
            edges.append(FloatColor(color.r * d, color.g * d, color.b * d, d))
    var thickness = settings.edge_thickness
    var narrow = _outline_blur(
        edges,
        half_width,
        half_height,
        half_width,
        half_height,
        thickness,
        OUTLINE_MAX_THICKNESS,
        True,
    )
    narrow = _outline_blur(
        narrow,
        half_width,
        half_height,
        half_width,
        half_height,
        thickness,
        OUTLINE_MAX_THICKNESS,
        False,
    )
    var wide = _outline_blur(
        narrow,
        half_width,
        half_height,
        quarter_width,
        quarter_height,
        Float32(OUTLINE_MAX_GLOW),
        OUTLINE_MAX_GLOW,
        True,
    )
    wide = _outline_blur(
        wide,
        quarter_width,
        quarter_height,
        quarter_width,
        quarter_height,
        Float32(OUTLINE_MAX_GLOW),
        OUTLINE_MAX_GLOW,
        False,
    )
    var glow = settings.edge_glow
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var u = u_of(x, width)
            var v = v_of(y, height)
            var slot = y * width + x
            var e1 = sample(narrow, half_width, half_height, u, v)
            var e2 = sample(wide, quarter_width, quarter_height, u, v)
            var k = settings.edge_strength * mask[slot].r
            var r = (e1.r + e2.r * glow) * k
            var g = (e1.g + e2.g * glow) * k
            var b = (e1.b + e2.b * glow) * k
            var a = (e1.a + e2.a * glow) * k
            if settings.use_pattern_texture:
                # `visibilityFactor * (1 - maskColor.r) * (1 - patternColor.r)`,
                # the pattern read at six times the coordinate.
                var seen = Float32(1) if 1 - mask[slot].g > 0 else Float32(0.5)
                var fill = (
                    seen
                    * (1 - mask[slot].r)
                    * (1 - pattern.sample(6 * u, 6 * v).r)
                )
                r += fill
                g += fill
                b += fill
                a += fill
            var under = frame.colors[slot]
            frame.colors[slot] = FloatColor(
                under.r + r * a, under.g + g * a, under.b + b * a, under.a
            )
