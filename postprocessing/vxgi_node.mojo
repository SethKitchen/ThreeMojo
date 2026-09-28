# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Voxel global illumination per pixel: three.js r186's
`examples/jsm/lighting/vxgi/VXGINode.js`.

**The pass.** `VXGINode.render` updates its `VXGIVolume`, then gathers two
images from the frame's depth and normals. The first is the ambient
occlusion, three.js's `getAONode`. The second is the indirect diffuse
irradiance, three.js's `getGINode`.

**A pixel.** The pixel's depth and normal give its point and normal in the
world. `cone_count` cones leave the point, one and a half voxels out along
the normal. Their directions are stratified over the cosine-weighted
hemisphere and turned by interleaved gradient noise. With
`use_temporal_filtering` on, the noise moves with the frame, over a cycle
of 64 frames. The mean radiance of the cones, times pi and
`gi_intensity`, is the irradiance. The occlusion of the cones, weighed by
distance, is the ambient occlusion.

**A pixel with no surface.** A pixel whose depth is the far plane is not
drawn by three.js's pass. It keeps the pass's white clear: one for the
occlusion, and white for the irradiance.

**The debug view.** With `debug` set, a ray walks the voxels from the
camera to the surface. It shows the first voxel with radiance, or with
opacity, at `debug_level`.

**Both backends.** Every pixel is `vxgi_pixel`, on the host here and on
the device in `render.gpu_vxgi`.

**Where this port differs.** three.js adds the two images to the lighting
of the next draw, through `builtinAOContext` and `builtinGIContext`.
`vxgi_light` lays them over a drawn frame instead: the light times the
occlusion, plus the diffuse color times the irradiance over pi. The
normals are the frame's, or the ones `DepthView` reconstructs.
"""

from core.assets import Assets
from core.scene import Scene
from lights.vxgi_cone_tracer import (
    Lanes,
    UNBOUNDED,
    Untracked,
    VxgiGrid,
    cosine_direction,
    floats_of,
    fract,
    interleaved_gradient_noise,
    intersect_volume,
    sample_volume,
    tangent_frame,
    trace_cone,
)
from lights.vxgi_volume import CONE_STEPS, VXGI_PI, VXGIVolume
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from postprocessing.screen_space import DepthView
from render.framebuffer import FloatColor
from render.target import RenderTarget
from std.math import exp2, floor, isfinite, pow, tan
from units.si import Angle, DEGREE, Length, METER


@fieldwise_init
struct VxgiDebug(Equatable, ImplicitlyCopyable, Writable):
    """What the debug view shows, three.js's `debug` uniform, as a type
    rather than a bare int.

    `VXGINode.validate` refuses `VxgiDebug(3)` with `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three views."""
        return (
            self == VXGI_DEBUG_OFF
            or self == VXGI_DEBUG_RADIANCE
            or self == VXGI_DEBUG_OPACITY
        )


# The irradiance and the occlusion, three.js's `0`.
comptime VXGI_DEBUG_OFF = VxgiDebug(0)
# The first voxel with radiance along the view, three.js's `1`.
comptime VXGI_DEBUG_RADIANCE = VxgiDebug(1)
# The first voxel with opacity along the view, three.js's `2`.
comptime VXGI_DEBUG_OPACITY = VxgiDebug(2)

# How far the noise moves each frame, three.js's `TEMPORAL_SHIFT`.
comptime TEMPORAL_SHIFT = Float32(5.588238)
# The frames the noise cycles over, three.js's `TEMPORAL_CYCLE`.
comptime TEMPORAL_CYCLE = 64
# The steps of the debug walk, three.js's `512`.
comptime DEBUG_STEPS = 512
# The radiance or opacity the debug walk stops at, three.js's `0.01`.
comptime DEBUG_THRESHOLD = Float32(0.01)
# The second noise's offset, three.js's `vec2( 5.588238, 3.14159 )`.
comptime ELEVATION_SHIFT_X = Float32(5.588238)
comptime ELEVATION_SHIFT_Y = Float32(3.14159)

# Where each value is in the floats `VXGINode.params` returns.
comptime PARAM_INVERSE = 0
comptime PARAM_WORLD = 16
comptime PARAM_CONES = 32
comptime PARAM_TAN_HALF = 33
comptime PARAM_GI_INTENSITY = 34
comptime PARAM_AO_INTENSITY = 35
comptime PARAM_AO_MIN = 36
comptime PARAM_AO_DISTANCE = 37
comptime PARAM_NORMAL_OFFSET = 38
comptime PARAM_DEBUG = 39
comptime PARAM_DEBUG_LEVEL = 40
comptime PARAM_FRAME = 41
comptime PARAM_TRACE_DISTANCE = 42
comptime PARAM_WIDTH = 43
comptime PARAM_HEIGHT = 44
# How many floats the parameters hold.
comptime VXGI_PARAMS = 45


def _point(
    params: Pointer[Float32, Untracked], at: Int, point: Vector3
) -> Vector3:
    """Return a point through a matrix held in the parameters, divided by
    its w: `Matrix4.transform_point`, from floats."""
    var x = point.x
    var y = point.y
    var z = point.z
    var w = (
        params[unsafe_offset=at + 3] * x
        + params[unsafe_offset=at + 7] * y
        + params[unsafe_offset=at + 11] * z
        + params[unsafe_offset=at + 15]
    )
    var inv = Float32(1)
    if w != 0:
        inv = Float32(1) / w
    return Vector3(
        (
            params[unsafe_offset=at] * x
            + params[unsafe_offset=at + 4] * y
            + params[unsafe_offset=at + 8] * z
            + params[unsafe_offset=at + 12]
        )
        * inv,
        (
            params[unsafe_offset=at + 1] * x
            + params[unsafe_offset=at + 5] * y
            + params[unsafe_offset=at + 9] * z
            + params[unsafe_offset=at + 13]
        )
        * inv,
        (
            params[unsafe_offset=at + 2] * x
            + params[unsafe_offset=at + 6] * y
            + params[unsafe_offset=at + 10] * z
            + params[unsafe_offset=at + 14]
        )
        * inv,
    )


def _direction(
    params: Pointer[Float32, Untracked], at: Int, direction: Vector3
) -> Vector3:
    """Return a direction through a matrix held in the parameters:
    `Matrix4.transform_direction`, from floats."""
    var x = direction.x
    var y = direction.y
    var z = direction.z
    return Vector3(
        params[unsafe_offset=at] * x
        + params[unsafe_offset=at + 4] * y
        + params[unsafe_offset=at + 8] * z,
        params[unsafe_offset=at + 1] * x
        + params[unsafe_offset=at + 5] * y
        + params[unsafe_offset=at + 9] * z,
        params[unsafe_offset=at + 2] * x
        + params[unsafe_offset=at + 6] * y
        + params[unsafe_offset=at + 10] * z,
    )


def _debug_view(
    grid: VxgiGrid,
    opacity: Pointer[Float32, Untracked],
    radiance: Pointer[Float32, Untracked],
    params: Pointer[Float32, Untracked],
    world: Vector3,
) -> Vector3:
    """Return what the debug view shows at a pixel: the first voxel along
    the view from the camera with radiance, or with opacity, at the debug
    level. Black where none is met before the surface."""
    var eye = Vector3(
        params[unsafe_offset=PARAM_WORLD + 12],
        params[unsafe_offset=PARAM_WORLD + 13],
        params[unsafe_offset=PARAM_WORLD + 14],
    )
    var toward = world - eye
    var surface_distance = toward.length()
    toward.normalize()
    var level = params[unsafe_offset=PARAM_DEBUG_LEVEL]
    var shows_radiance = params[unsafe_offset=PARAM_DEBUG] == Float32(
        VXGI_DEBUG_RADIANCE.value
    )
    var texel = grid.voxel_size * exp2(level)
    var cells = Vector3(
        grid.volume_size.x / texel,
        grid.volume_size.y / texel,
        grid.volume_size.z / texel,
    )
    var span = intersect_volume(grid, eye, toward)
    var far = min(span[1], surface_distance)
    var t = span[0]
    for _ in range(DEBUG_STEPS):  # pragma: no branch
        if t >= far:
            break
        var point = eye + toward * t
        var uvw = Vector3(
            (
                floor(
                    (point.x - grid.bounds_min.x) / grid.volume_size.x * cells.x
                )
                + 0.5
            )
            / cells.x,
            (
                floor(
                    (point.y - grid.bounds_min.y) / grid.volume_size.y * cells.y
                )
                + 0.5
            )
            / cells.y,
            (
                floor(
                    (point.z - grid.bounds_min.z) / grid.volume_size.z * cells.z
                )
                + 0.5
            )
            / cells.z,
        )
        if shows_radiance:
            var light = sample_volume(radiance, grid, uvw, level)
            if light[3] > DEBUG_THRESHOLD:
                return Vector3(
                    light[0] / light[3],
                    light[1] / light[3],
                    light[2] / light[3],
                )
        else:
            var seen = sample_volume(opacity, grid, uvw, level)
            if seen[3] > DEBUG_THRESHOLD:
                return Vector3(seen[0], seen[1], seen[2])
        t += texel * 0.25
    return Vector3(0, 0, 0)


def vxgi_pixel(
    grid: VxgiGrid,
    opacity: Pointer[Float32, Untracked],
    radiance: Pointer[Float32, Untracked],
    params: Pointer[Float32, Untracked],
    depth: Float32,
    normal: Vector3,
    x: Int,
    y: Int,
) -> Lanes:
    """Return one pixel of the pass: three.js's `VXGINode` material.

    Args:
        grid: The volume's grid.
        opacity: Its opacity chain.
        radiance: Its radiance chain.
        params: The floats `VXGINode.params` returns.
        depth: The pixel's window depth, zero to one.
        normal: Its view-space normal.
        x: Its column.
        y: Its row, down from the top.

    Returns:
        The irradiance, red, green and blue, and the occlusion. White and
        one where the depth is the far plane.
    """
    if depth >= 1:
        return Lanes(1, 1, 1, 1)
    var width = params[unsafe_offset=PARAM_WIDTH]
    var height = params[unsafe_offset=PARAM_HEIGHT]
    var u = (Float32(x) + 0.5) / width
    var v = 1 - (Float32(y) + 0.5) / height
    var seen = _point(
        params, PARAM_INVERSE, Vector3(u * 2 - 1, v * 2 - 1, depth * 2 - 1)
    )
    var world = _point(params, PARAM_WORLD, seen)
    # The debug view replaces the gathered light, so no cone is traced.
    if params[unsafe_offset=PARAM_DEBUG] > 0:
        var shown = _debug_view(grid, opacity, radiance, params, world)
        return Lanes(shown.x, shown.y, shown.z, 1)
    var facing = normal
    facing.normalize()
    var turned = _direction(params, PARAM_WORLD, facing)
    turned.normalize()
    var shift = params[unsafe_offset=PARAM_FRAME] * TEMPORAL_SHIFT
    var sx = Float32(x) + 0.5 + shift
    var sy = Float32(y) + 0.5 + shift
    var rotation = interleaved_gradient_noise(sx, sy)
    var elevation = interleaved_gradient_noise(
        sx + ELEVATION_SHIFT_X, sy + ELEVATION_SHIFT_Y
    )
    var frame = tangent_frame(turned)
    var count = Int(params[unsafe_offset=PARAM_CONES])
    var tan_half = params[unsafe_offset=PARAM_TAN_HALF]
    var reach = params[unsafe_offset=PARAM_TRACE_DISTANCE]
    var ao_distance = params[unsafe_offset=PARAM_AO_DISTANCE]
    var origin = world + turned * (
        grid.voxel_size * params[unsafe_offset=PARAM_NORMAL_OFFSET]
    )
    var red = Float32(0)
    var green = Float32(0)
    var blue = Float32(0)
    var occlusion = Float32(0)
    for cone in range(count):  # pragma: no branch
        var u1 = (Float32(cone) + elevation) / Float32(count)
        var u2 = fract(Float32(cone) * Float32(0.618034) + rotation)
        var direction = cosine_direction(frame[0], frame[1], turned, u1, u2)
        var gathered = trace_cone(
            grid,
            opacity,
            radiance,
            True,
            origin,
            direction,
            tan_half,
            reach,
            ao_distance,
            True,
            CONE_STEPS,
        )
        red += gathered.red
        green += gathered.green
        blue += gathered.blue
        occlusion += gathered.ao
    var scale = params[unsafe_offset=PARAM_GI_INTENSITY] * VXGI_PI
    red = red / Float32(count) * scale
    green = green / Float32(count) * scale
    blue = blue / Float32(count) * scale
    var open = max(Float32(0), min(Float32(1), 1 - occlusion / Float32(count)))
    var low = params[unsafe_offset=PARAM_AO_MIN]
    var ao = low + (1 - low) * pow(
        open, params[unsafe_offset=PARAM_AO_INTENSITY]
    )
    return Lanes(red, green, blue, ao)


struct VxgiFrame(Movable):
    """What a VXGI pass gathers: three.js's AO and GI textures."""

    var width: Int
    var height: Int
    # One occlusion a pixel, row by row from the top, zero to one.
    var ao: List[Float32]
    # One irradiance a pixel, its alpha one.
    var gi: List[FloatColor]

    def __init__(out self, width: Int, height: Int):
        """Start a frame of no pixels.

        Args:
            width: Its width in pixels.
            height: Its height in pixels.
        """
        self.width = width
        self.height = height
        self.ao = List[Float32](capacity=width * height)
        self.gi = List[FloatColor](capacity=width * height)

    def add(mut self, pixel: Lanes):
        """Append one pixel, as `vxgi_pixel` returns it.

        Args:
            pixel: The irradiance and the occlusion.
        """
        self.ao.append(pixel[3])
        self.gi.append(FloatColor(pixel[0], pixel[1], pixel[2], 1))


struct VXGINode(Movable):
    """Voxel global illumination as a pass: three.js's `VXGINode`. See the
    module docstring."""

    # The voxel volume. Set its bounds, layers and bounces here.
    var volume: VXGIVolume
    # How many cones a pixel traces, three.js's `coneCount`.
    var cone_count: Int
    # The aperture of each cone, three.js's `coneAngle`.
    var cone_angle: Angle
    # How strong the irradiance is, three.js's `giIntensity`.
    var gi_intensity: Float32
    # The power the occlusion is raised to, three.js's `aoIntensity`.
    var ao_intensity: Float32
    # The darkest the occlusion gets, three.js's `aoMinVisibility`.
    var ao_min_visibility: Float32
    # The distance at which an occluder counts half, three.js's
    # `aoDistance`. Zero turns the falloff off.
    var ao_distance: Length
    # How far the cones start from the surface, in voxels, three.js's
    # `normalOffset`.
    var normal_offset: Float32
    # The debug view, three.js's `debug`, and the level it shows.
    var debug: VxgiDebug
    var debug_level: Float32
    # Whether the noise moves with the frame, three.js's
    # `useTemporalFiltering`.
    var use_temporal_filtering: Bool

    def __init__(out self, resolution: Int = 128):
        """Make a pass with three.js's defaults.

        Args:
            resolution: Voxels along the longest axis of the volume.
        """
        self.volume = VXGIVolume(resolution)
        self.cone_count = 3
        self.cone_angle = Angle(40.0, DEGREE)
        self.gi_intensity = 1
        self.ao_intensity = 1
        self.ao_min_visibility = 0
        self.ao_distance = Length(1.0, METER)
        self.normal_offset = 1.5
        self.debug = VXGI_DEBUG_OFF
        self.debug_level = 0
        self.use_temporal_filtering = True

    def validate(self) raises:
        """Refuse settings three.js's pass cannot use.

        Raises:
            Error: If there are no cones, the aperture is not between zero
                and a half turn, a number is not finite, the distance is
                negative, or the debug view is none of the three.
        """
        if self.cone_count < 1:
            raise Error("A VXGI pass needs at least one cone")
        var degrees = self.cone_angle.to(DEGREE)
        if not (isfinite(degrees) and degrees > 0 and degrees < 180):
            raise Error("A VXGI cone must open between 0 and 180 degrees")
        var numbers = (
            isfinite(self.gi_intensity)
            and isfinite(self.ao_intensity)
            and isfinite(self.ao_min_visibility)
            and isfinite(self.normal_offset)
            and isfinite(self.debug_level)
        )
        if not numbers:
            raise Error("A VXGI pass's settings must be finite")
        if not (
            isfinite(self.ao_distance.value) and self.ao_distance.value >= 0
        ):
            raise Error("A VXGI pass's occlusion distance must be zero or more")
        if not self.debug.is_valid():
            raise Error("A VXGI debug view that is none of the three")

    def params(
        self,
        view: DepthView,
        camera_world: Matrix4,
        frame_id: Int,
    ) -> List[Float32]:
        """Return the pass's numbers as `vxgi_pixel` reads them.

        Args:
            view: The frame's depth, and the camera's projection.
            camera_world: The camera's world matrix.
            frame_id: The frame's number, for the moving noise.

        Returns:
            `VXGI_PARAMS` floats.
        """
        var out = List[Float32](capacity=VXGI_PARAMS)
        for at in range(16):  # pragma: no branch
            out.append(view.inverse.elements[at])
        for at in range(16):  # pragma: no branch
            out.append(camera_world.elements[at])
        var frame = 0
        if self.use_temporal_filtering:
            frame = frame_id % TEMPORAL_CYCLE
        out.extend(
            [
                Float32(self.cone_count),
                tan(self.cone_angle.value * 0.5),
                self.gi_intensity,
                self.ao_intensity,
                self.ao_min_visibility,
                self.ao_distance.value,
                self.normal_offset,
                Float32(self.debug.value),
                self.debug_level,
                Float32(frame),
                self.volume.trace_distance(),
                Float32(view.width),
                Float32(view.height),
            ]
        )
        return out^

    def gather(
        self,
        view: DepthView,
        normals: List[Vector3],
        camera_world: Matrix4,
        frame_id: Int,
    ) raises -> VxgiFrame:
        """Return the occlusion and irradiance of every pixel from the
        volume as it stands, on the host.

        Args:
            view: The frame's depth, and the camera's projection.
            normals: One view-space normal a pixel: `DepthView.normals`.
            camera_world: The camera's world matrix.
            frame_id: The frame's number, for the moving noise.

        Returns:
            The two images.

        Raises:
            Error: If the settings are refused by `validate`, or there is
                not one normal a pixel.
        """
        self.validate()
        if len(normals) != view.width * view.height:
            raise Error("A VXGI pass needs one normal a pixel")
        var numbers = self.params(view, camera_world, frame_id)
        var frame = VxgiFrame(view.width, view.height)
        var seen = floats_of(self.volume.opacity)
        var light = floats_of(self.volume.radiance)
        var at = floats_of(numbers)
        for slot in range(view.width * view.height):  # pragma: no branch
            frame.add(
                vxgi_pixel(
                    self.volume.grid,
                    seen,
                    light,
                    at,
                    view.depth[slot],
                    normals[slot],
                    slot % view.width,
                    slot // view.width,
                )
            )
        # The pointer does not keep the numbers alive; this does.
        _ = numbers^
        return frame^

    def render(
        mut self,
        view: DepthView,
        camera_world: Matrix4,
        scene: Scene,
        assets: Assets,
        frame_id: Int = 0,
    ) raises -> VxgiFrame:
        """Update the volume, then gather the occlusion and the irradiance
        of every pixel, on the host: three.js's `updateBefore`.

        Args:
            view: The frame's depth, and the camera's projection.
            camera_world: The camera's world matrix.
            scene: The scene the frame shows. It must be current.
            assets: Where its meshes' geometries, materials and textures
                are.
            frame_id: The frame's number, for the moving noise.

        Returns:
            The two images.

        Raises:
            Error: Anything `validate`, `VXGIVolume.update` or `gather`
                raises.
        """
        self.validate()
        self.volume.update(scene, assets)
        return self.gather(view, view.normals(), camera_world, frame_id)


def vxgi_light(
    mut frame: RenderTarget, gathered: VxgiFrame, diffuse: List[FloatColor]
) raises:
    """Lay a VXGI pass over a drawn frame: its light times the occlusion,
    plus the diffuse color times the irradiance over pi, as three.js's
    `BRDF_Lambert` weighs indirect irradiance. The alpha is kept.

    Args:
        frame: The frame, changed in place.
        gathered: The pass's images, the frame's size.
        diffuse: One diffuse color a pixel, row by row from the top.

    Raises:
        Error: If the images or the colors are not the frame's size.
    """
    var count = frame.width * frame.height
    if gathered.width != frame.width or gathered.height != frame.height:
        raise Error("A VXGI pass must be the frame's size")
    if len(diffuse) != count:
        raise Error("A VXGI pass needs one diffuse color a pixel")
    for slot in range(count):  # pragma: no branch
        var was = frame.straight_at(slot)
        var ao = gathered.ao[slot]
        var gi = gathered.gi[slot]
        var paint = diffuse[slot]
        frame.colors[slot] = FloatColor(
            was.r * ao + paint.r * gi.r / VXGI_PI,
            was.g * ao + paint.g * gi.g / VXGI_PI,
            was.b * ao + paint.b * gi.b / VXGI_PI,
            was.a,
        ).premultiplied()
        frame.data[slot] = False
