# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's cameras, drawn by ThreeMojo: `CarlaRenderer`.

`rgb_camera_settings` reads the attributes of a `sensor.camera.rgb` or a
`sensor.camera.rgb_fisheye` actor, each at CARLA's default when the actor
lacks it. `CarlaRenderer` holds a scene of the world's town, props and
actors, and `render_rgb` draws what a camera actor sees:

1. `update` gives the scene the world's state: the sky, the sun or the
   moon, the wet road and the lamps from the weather, the traffic
   lights' lamps, and the actors' poses and lamps.
2. The camera stands at the actor's transform. CARLA's `fov` is the
   horizontal field of view, so the three.js camera's vertical one is
   `2 atan(tan(fov / 2) h / w)`.
3. ThreeMojo's renderer draws the scene through its supersampling,
   `supersample` times the size each way, with cascaded sun shadows. On a
   wet road a screen-space reflection pass adds what the puddles mirror.
4. `render_light` splits each pixel's light into the sun's share and the
   sky's, from the sun's shadow maps. Ground-truth ambient occlusion
   darkens the sky's share, and the cloud layer's shadows move the sun's.
5. `render_post` lays the height fog, the haze and the rain over the
   light. The fog scatters the sun only where `render_light`'s light
   shafts say the sun reaches.
6. The exposure is metered from the light (`exposure_mode` "histogram") or
   set by the shutter, the aperture and the ISO ("manual").
7. The composer adds the motion blur, the bloom, the lens flare and the
   chromatic aberration. The bloom's and the flare's thresholds are set
   against the exposure, so the same parts of the image glow by day and
   by night.
8. The white balance scales the light, and the output pass tone maps it
   with ACES filmic at the exposure.
9. The gamma and the lens distortion finish the image.

**Photoscanned assets.** An `AssetRegistry` gives the town, the actors
and the sky what the asset cache holds, and each keeps its procedural
asset for a key the cache lacks. See `assets`.

`render_semantic` and `render_depth` draw CARLA's ground-truth images
through the same rasterizer: every mesh flat in the CityScapes color of
its semantic tag, and the depth buffer turned into the distance along the
camera's axis. `semantic_tags` gives each mesh its tag.

**Exposure.** A camera's EV100 is `log2(N^2 / t)`, with N the f-number
and t the shutter time, less `log2(ISO / 100)`. A reflected-light meter
with calibration constant K sets middle gray, 0.18, at a luminance of
`2^EV100 K / 100` candela per square meter. The histogram mode meters the
frame and clamps its EV100 to `exposure_min_bright` and
`exposure_max_bright`; the manual mode takes the camera's EV100.
`exposure_compensation` adds stops to both. `LUMINANCE_SCALE` says how
many candela per square meter one unit of the renderer's light is.

The town is lit by physical daylight, and a clear noon meters near EV100
15. CARLA's default limits, 10 to 12, frame CARLA's own scenes, which are
dimmer. So the port reads the limits and the manual EV100
`CAMERA_EV_OFFSET` stops higher: a default camera then exposes a physical
noon as CARLA's default camera exposes CARLA's noon.

**White balance** divides by the color of a black body at `temp` and
multiplies by the color at 6500 K, and `tint` moves the green channel.

**A wide-angle lens.** A `rgb_fisheye` camera draws a cube of the scene
around the camera with `renderers.environment.scene_cube`, then reads each
pixel's ray through the sensors tier's `cameras.WideAngleLens`, CARLA's
camera models. The cube has no depth, so the height fog becomes the
renderer's exponential fog, the rain is not drawn, and the reflections
and the motion blur are left out.

**Not mapped.** The filmic curve's `slope`, `toe`, `shoulder`,
`black_clip` and `white_clip`, the depth of field (`focal_distance`,
`min_fstop`, `blade_count`, `blur_amount`, `blur_radius`), the adaptation
speeds, `motion_blur_min_object_screen_size` and
`chromatic_aberration_offset` are read and kept, but ThreeMojo's passes
have no place for them.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import color_background, cube_background
from core.fog import exp2_fog, no_fog
from core.object3d import NodeId, Object3D
from core.scene import Scene
from extensions.carla.actor import ActorId
from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.cameras import WideAngleLens
from extensions.carla.props import Props
from extensions.carla.render_actors import ActorVisuals
from extensions.carla.sensor import (
    DEPTH_FAR,
    SKY,
    SemanticTag,
    UNLABELED,
    cityscapes_color,
    encode_depth,
)
from extensions.carla.render_post import (
    LensSettings,
    ViewRays,
    apply_gains,
    apply_gamma,
    apply_height_fog,
    apply_lens,
    draw_rain,
    luminance,
    metered_luminance,
)
from extensions.carla.assets import AssetRegistry
from extensions.carla.render_light import (
    DaylightSplit,
    ambient_occlusion,
    apply_ambient_occlusion,
    apply_cloud_shadows,
    direct_shares,
    fog_light_shafts,
    sun_maps,
    town_gtao,
)
from extensions.carla.render_sky import (
    SkyLighting,
    build_sky,
    ground_light,
    hdri_sky,
    sky_key,
)
from extensions.carla.sensor_attributes import (
    attribute_bool,
    attribute_float,
    attribute_int,
    attribute_string,
)
from extensions.carla.render_weather import (
    HeightFog,
    NITS_PER_UNIT,
    daylight,
    height_fog,
    light_units,
    sky_illuminance,
    sky_settings,
    moon_color,
    moon_direction,
    moon_intensity,
    rain_settings,
    sun_color,
    sun_direction,
    sun_intensity,
    wet_surface,
)
from extensions.carla.town import Town, TownSettings
from extensions.carla.transform import CarlaTransform
from extensions.carla.weather import WeatherParameters
from extensions.carla.world import World
from lights.light import directional_light
from materials.material import BASIC, DOUBLE_SIDE, Material, MaterialId
from objects.mesh import Mesh
from lights.shadow import PCF_SOFT_SHADOW_MAP
from lights.sun_light import SunLight
from math.vector3 import Vector3
from lights.shadow import ShadowMap
from math.noise import ImprovedNoise
from postprocessing.screen_space import DepthView
from render.target import OUTPUT_NORMAL
from postprocessing.composer import (
    BLOOM,
    EffectComposer,
    LENSFLARE,
    MOTION_BLUR,
    Pass,
    SSR_NODE,
    bloom_pass,
    chromatic_aberration_pass,
    frame_outputs,
    lensflare_pass,
    motion_blur_pass,
    output_pass,
    render_pass,
    ssr_node_pass,
)
from render.color_utils import kelvin_color
from render.antialias import SUPERSAMPLE
from render.cube_texture import CubeTexture
from render.framebuffer import Color, FloatColor, Framebuffer
from render.srgb import srgb_to_linear
from render.target import RenderTarget
from render.texture import Texture
from render.texture_store import NO_TEXTURE, TextureId
from render.tonemap import ACES_FILMIC_TONE_MAPPING, NO_TONE_MAPPING
from renderers.environment import scene_cube
from renderers.renderer import Renderer
from std.math import atan, log2, pow, tan
from units.si import (
    DEGREE,
    METER,
    PER_METER,
    RADIAN,
    Angle,
    InverseLength,
    Length,
)
from units.photometry import NIT
from units.temperature import KELVIN, Temperature

# How many semantic tags CARLA names.
comptime SEMANTIC_TAGS = 30
# The luminance of one unit of the renderer's light.
comptime LUMINANCE_SCALE = NITS_PER_UNIT
# The stops a camera's EV100 limits and manual EV100 are read higher by.
comptime CAMERA_EV_OFFSET = Float32(3)
# The gray a meter aims the mean at.
comptime MIDDLE_GRAY = Float32(0.18)
# What CARLA's bloom and lens-flare intensities are scaled by.
comptime BLOOM_GAIN = Float32(0.35)
comptime FLARE_GAIN = Float32(0.15)
# What CARLA's chromatic aberration intensity is scaled by.
comptime ABERRATION_GAIN = Float32(1)
# The exposed luminance a pixel must pass to bloom, and to cast ghosts.
comptime BLOOM_THRESHOLD = Float32(1.2)
comptime FLARE_THRESHOLD = Float32(9)
# How much of the ambient occlusion counts.
comptime AO_STRENGTH = Float32(1)
# How strongly a wet road mirrors in the screen-space reflections.
comptime WET_REFLECTION = Float32(0.9)
# How near and far a camera sees.
comptime CAMERA_NEAR = Length(0.12, METER)
comptime CAMERA_FAR = Length(1500, METER)
# How far in front of the camera the sun's shadows reach. Past it the
# light has no shadow, as three.js's sun fades its last cascade out. A
# shorter reach packs the cascades' texels nearer the camera, and a
# town package's far tiles cast nothing.
comptime SUN_SHADOW_REACH = Length(150, METER)


@fieldwise_init
struct ExposureMode(Equatable, ImplicitlyCopyable, Writable):
    """How a camera sets its exposure: CARLA's `exposure_mode`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for histogram or manual.

        Returns:
            Whether the value is 0 or 1.
        """
        return self.value == 0 or self.value == 1

    def write_to(self, mut writer: Some[Writer]):
        """Write the mode's number.

        Args:
            writer: The destination.
        """
        writer.write("ExposureMode(", self.value, ")")


comptime HISTOGRAM_EXPOSURE = ExposureMode(0)
comptime MANUAL_EXPOSURE = ExposureMode(1)


struct RgbCameraSettings(Copyable, Movable, Writable):
    """The attributes of CARLA's RGB camera, with CARLA's defaults."""

    var image_width: Int
    var image_height: Int
    # The horizontal field of view.
    var fov: Angle
    var enable_postprocess_effects: Bool
    var gamma: Float32
    var exposure_mode: ExposureMode
    # Stops added to the exposure.
    var exposure_compensation: Float32
    # The shutter time is one over this, in seconds.
    var shutter_speed: Float32
    var iso: Float32
    var fstop: Float32
    # EV100 limits of the histogram exposure.
    var exposure_min_bright: Float32
    var exposure_max_bright: Float32
    var exposure_speed_up: Float32
    var exposure_speed_down: Float32
    var calibration_constant: Float32
    var bloom_intensity: Float32
    var lens_flare_intensity: Float32
    var motion_blur_intensity: Float32
    var motion_blur_max_distortion: Float32
    var motion_blur_min_object_screen_size: Float32
    var chromatic_aberration_intensity: Float32
    var chromatic_aberration_offset: Float32
    var temp: Temperature
    var tint: Float32
    var slope: Float32
    var toe: Float32
    var shoulder: Float32
    var black_clip: Float32
    var white_clip: Float32
    var focal_distance: Length
    var min_fstop: Float32
    var blade_count: Int
    var blur_amount: Float32
    var blur_radius: Float32
    var lens: LensSettings
    # The wide-angle lens of a fisheye camera; None for a pinhole camera.
    var wide_angle: Optional[WideAngleLens]

    def __init__(out self):
        """Start at CARLA's defaults for `sensor.camera.rgb`."""
        self.image_width = 800
        self.image_height = 600
        self.fov = Angle(90, DEGREE)
        self.enable_postprocess_effects = True
        self.gamma = 2.2
        self.exposure_mode = HISTOGRAM_EXPOSURE
        self.exposure_compensation = 0
        self.shutter_speed = 200
        self.iso = 100
        self.fstop = 1.4
        self.exposure_min_bright = 10
        self.exposure_max_bright = 12
        self.exposure_speed_up = 3
        self.exposure_speed_down = 1
        self.calibration_constant = 16
        self.bloom_intensity = 0.675
        self.lens_flare_intensity = 0.1
        self.motion_blur_intensity = 0.45
        self.motion_blur_max_distortion = 0.35
        self.motion_blur_min_object_screen_size = 0.1
        self.chromatic_aberration_intensity = 0
        self.chromatic_aberration_offset = 0
        self.temp = Temperature(6500, KELVIN)
        self.tint = 0
        self.slope = 0.88
        self.toe = 0.55
        self.shoulder = 0.26
        self.black_clip = 0
        self.white_clip = 0.04
        self.focal_distance = Length(1000, METER)
        self.min_fstop = 1.2
        self.blade_count = 5
        self.blur_amount = 1
        self.blur_radius = 0
        self.lens = LensSettings(-1, 0, 0.08, 0.08, 5, 0)
        self.wide_angle = None

    def write_to(self, mut writer: Some[Writer]):
        """Write the image size and the field of view.

        Args:
            writer: The destination.
        """
        writer.write(
            "RgbCameraSettings(",
            self.image_width,
            "x",
            self.image_height,
            ", fov=",
            self.fov.to(DEGREE),
            ")",
        )


def rgb_camera_settings(
    attributes: List[ActorAttributeValue],
) raises -> RgbCameraSettings:
    """Read an RGB camera's settings from its actor's attributes.

    Each attribute the actor lacks, or has with another type, keeps
    CARLA's default, as `sensor_attributes` reads it. A camera with a
    `camera_model` attribute is a fisheye camera, and its lens is
    `WideAngleLens.from_attributes`.

    Args:
        attributes: The camera actor's attributes.

    Returns:
        The settings.

    Raises:
        Error: If the image is not at least one pixel, the field of view
            is not more than 0 and less than 180 degrees (360 for a
            fisheye), or the exposure mode is neither "histogram" nor
            "manual".
    """
    var s = RgbCameraSettings()
    s.image_width = attribute_int(attributes, "image_size_x", 800)
    s.image_height = attribute_int(attributes, "image_size_y", 600)
    if s.image_width < 1 or s.image_height < 1:
        raise Error("A camera's image needs at least one pixel")
    var fisheye = False
    for a in attributes:
        if a.id == "camera_model":
            fisheye = True
    var fov = attribute_float(attributes, "fov", 90)
    var widest = Float32(360) if fisheye else Float32(180)
    if not (fov > 0 and fov < widest):
        raise Error("A camera's fov must be more than 0 and less than 180")
    s.fov = Angle(fov, DEGREE)
    s.enable_postprocess_effects = attribute_bool(
        attributes, "enable_postprocess_effects", True
    )
    s.gamma = attribute_float(attributes, "gamma", s.gamma)
    var mode = attribute_string(attributes, "exposure_mode", "histogram")
    if mode == "manual":
        s.exposure_mode = MANUAL_EXPOSURE
    elif mode != "histogram":
        raise Error("A camera's exposure mode is histogram or manual")
    s.exposure_compensation = attribute_float(
        attributes, "exposure_compensation", s.exposure_compensation
    )
    s.shutter_speed = attribute_float(
        attributes, "shutter_speed", s.shutter_speed
    )
    s.iso = attribute_float(attributes, "iso", s.iso)
    s.fstop = attribute_float(attributes, "fstop", s.fstop)
    s.exposure_min_bright = attribute_float(
        attributes, "exposure_min_bright", s.exposure_min_bright
    )
    s.exposure_max_bright = attribute_float(
        attributes, "exposure_max_bright", s.exposure_max_bright
    )
    s.exposure_speed_up = attribute_float(
        attributes, "exposure_speed_up", s.exposure_speed_up
    )
    s.exposure_speed_down = attribute_float(
        attributes, "exposure_speed_down", s.exposure_speed_down
    )
    s.calibration_constant = attribute_float(
        attributes, "calibration_constant", s.calibration_constant
    )
    s.bloom_intensity = attribute_float(
        attributes, "bloom_intensity", s.bloom_intensity
    )
    s.lens_flare_intensity = attribute_float(
        attributes, "lens_flare_intensity", s.lens_flare_intensity
    )
    s.motion_blur_intensity = attribute_float(
        attributes, "motion_blur_intensity", s.motion_blur_intensity
    )
    s.motion_blur_max_distortion = attribute_float(
        attributes, "motion_blur_max_distortion", s.motion_blur_max_distortion
    )
    s.motion_blur_min_object_screen_size = attribute_float(
        attributes,
        "motion_blur_min_object_screen_size",
        s.motion_blur_min_object_screen_size,
    )
    s.chromatic_aberration_intensity = attribute_float(
        attributes,
        "chromatic_aberration_intensity",
        s.chromatic_aberration_intensity,
    )
    s.chromatic_aberration_offset = attribute_float(
        attributes, "chromatic_aberration_offset", s.chromatic_aberration_offset
    )
    s.tint = attribute_float(attributes, "tint", s.tint)
    s.slope = attribute_float(attributes, "slope", s.slope)
    s.toe = attribute_float(attributes, "toe", s.toe)
    s.shoulder = attribute_float(attributes, "shoulder", s.shoulder)
    s.black_clip = attribute_float(attributes, "black_clip", s.black_clip)
    s.white_clip = attribute_float(attributes, "white_clip", s.white_clip)
    s.min_fstop = attribute_float(attributes, "min_fstop", s.min_fstop)
    s.blur_amount = attribute_float(attributes, "blur_amount", s.blur_amount)
    s.blur_radius = attribute_float(attributes, "blur_radius", s.blur_radius)
    s.temp = Temperature(attribute_float(attributes, "temp", 6500), KELVIN)
    s.focal_distance = Length(
        attribute_float(attributes, "focal_distance", 1000), METER
    )
    s.blade_count = attribute_int(attributes, "blade_count", s.blade_count)
    s.lens = LensSettings(
        attribute_float(attributes, "lens_k", -1),
        attribute_float(attributes, "lens_kcube", 0),
        attribute_float(attributes, "lens_x_size", 0.08),
        attribute_float(attributes, "lens_y_size", 0.08),
        attribute_float(attributes, "lens_circle_falloff", 5),
        attribute_float(attributes, "lens_circle_multiplier", 0),
    )
    if fisheye:
        s.wide_angle = WideAngleLens.from_attributes(attributes)
    return s^


def vertical_fov(horizontal: Angle, width: Int, height: Int) -> Angle:
    """Return the vertical field of view of a horizontal one.

    Args:
        horizontal: CARLA's horizontal field of view.
        width: The image's width.
        height: The image's height.

    Returns:
        `2 atan(tan(horizontal / 2) height / width)`.
    """
    var half = tan(horizontal.to(RADIAN) / 2)
    return Angle(2 * atan(half * Float32(height) / Float32(width)), RADIAN)


def camera_ev100(settings: RgbCameraSettings) -> Float32:
    """Return a camera's EV100 from its shutter, aperture and ISO.

    Args:
        settings: The camera.

    Returns:
        `log2(N^2 / t) - log2(ISO / 100)`, with t one over the shutter
        speed.
    """
    return log2(
        settings.fstop * settings.fstop * settings.shutter_speed
    ) - log2(settings.iso / 100)


def metered_ev100(luminance: Float32, calibration: Float32) -> Float32:
    """Return the EV100 a reflected-light meter reads for a luminance.

    Args:
        luminance: The metered luminance, in the renderer's light.
        calibration: The meter's calibration constant K.

    Returns:
        `log2(L 100 / K)`, with L in candela per square meter.
    """
    return log2(luminance * LUMINANCE_SCALE.to(NIT) * 100 / calibration)


def ev100_exposure(
    ev100: Float32, calibration: Float32, compensation: Float32
) -> Float32:
    """Return what the renderer's light is scaled by at an EV100.

    Args:
        ev100: The exposure value.
        calibration: The meter's calibration constant K.
        compensation: Stops to add.

    Returns:
        Middle gray over the luminance the EV100 puts at middle gray,
        times two to the compensation.
    """
    var target = (
        pow(Float32(2), ev100) * calibration / 100 / LUMINANCE_SCALE.to(NIT)
    )
    return MIDDLE_GRAY / target * pow(Float32(2), compensation)


def camera_exposure(settings: RgbCameraSettings, metered: Float32) -> Float32:
    """Return a camera's exposure for a frame.

    Args:
        settings: The camera.
        metered: The frame's metered luminance, read in histogram mode.

    Returns:
        The histogram mode's exposure, the metered EV100 clamped to the
        camera's bright limits, or the manual mode's, the camera's EV100;
        the limits and the camera's EV100 each `CAMERA_EV_OFFSET` higher.
    """
    var ev = camera_ev100(settings) + CAMERA_EV_OFFSET
    if settings.exposure_mode == HISTOGRAM_EXPOSURE:
        ev = min(
            max(
                metered_ev100(metered, settings.calibration_constant),
                settings.exposure_min_bright + CAMERA_EV_OFFSET,
            ),
            settings.exposure_max_bright + CAMERA_EV_OFFSET,
        )
    return ev100_exposure(
        ev, settings.calibration_constant, settings.exposure_compensation
    )


def white_balance(temp: Temperature, tint: Float32) raises -> FloatColor:
    """Return the channel gains of a white balance.

    Args:
        temp: The light the camera is balanced for.
        tint: Moves green, from -1 (more green) to 1 (less).

    Returns:
        The color of a black body at 6500 K over the color at `temp`,
        with green scaled by `1 - tint / 4`, all over their green.

    Raises:
        Error: If the temperature is not a number.
    """
    var reference = kelvin_color(Temperature(6500, KELVIN))
    var source = kelvin_color(temp)
    var r = reference.r / max(source.r, Float32(1e-4))
    var g = reference.g / max(source.g, Float32(1e-4)) * (1 - tint / 4)
    var b = reference.b / max(source.b, Float32(1e-4))
    return FloatColor(r / g, 1, b / g)


def camera_passes(
    settings: RgbCameraSettings, wetness: Float32
) raises -> List[Pass]:
    """Return the composer passes of a camera, before the tone curve.

    The first pass draws the scene. A screen-space reflection pass follows
    on a road wetter than a fifth. With the post-process effects on, the
    motion blur, the bloom, the lens flare and the chromatic aberration
    follow, each only when its intensity is above zero.

    Args:
        settings: The camera.
        wetness: How wet the road is, zero to one.

    Returns:
        The passes, in order. The first is the render pass.

    Raises:
        Error: If a pass refuses its settings.
    """
    var passes = List[Pass]()
    passes.append(render_pass())
    if wetness > 0.2:
        var ssr = ssr_node_pass(
            Length(40, METER),
            Length(0.4, METER),
            WET_REFLECTION * wetness,
            0.5,
            2,
            True,
        )
        ssr.ssr_node.reflect_non_metals = True
        passes.append(ssr^)
    if not settings.enable_postprocess_effects:
        return passes^
    if settings.motion_blur_intensity > 0:
        passes.append(motion_blur_pass(settings.motion_blur_intensity, 8))
    if settings.bloom_intensity > 0:
        passes.append(
            bloom_pass(
                settings.bloom_intensity * BLOOM_GAIN, 0.4, BLOOM_THRESHOLD
            )
        )
    if settings.lens_flare_intensity > 0:
        var flare = lensflare_pass(8.0, 4, 0.25, 25, 4)
        flare.display.ghost_tint_r = settings.lens_flare_intensity * FLARE_GAIN
        flare.display.ghost_tint_g = settings.lens_flare_intensity * FLARE_GAIN
        flare.display.ghost_tint_b = settings.lens_flare_intensity * FLARE_GAIN
        passes.append(flare^)
    if settings.chromatic_aberration_intensity > 0:
        passes.append(
            chromatic_aberration_pass(
                settings.chromatic_aberration_intensity * ABERRATION_GAIN
            )
        )
    return passes^


def _srgb_byte(value: Float32) -> UInt8:
    """Return a linear share as an sRGB byte."""
    return UInt8(
        Int(pow(min(max(value, 0), 1), Float32(1) / Float32(2.2)) * 255 + 0.5)
    )


def _color_of(linear: FloatColor) -> Color:
    """Return the sRGB color of a linear one, each channel held to one."""
    var top = max(max(linear.r, linear.g), max(linear.b, Float32(1e-6)))
    var scale = min(Float32(1) / top, Float32(1))
    return Color(
        _srgb_byte(linear.r * scale),
        _srgb_byte(linear.g * scale),
        _srgb_byte(linear.b * scale),
    )


def set_thresholds(mut composer: EffectComposer, exposure: Float32):
    """Set the bloom's and the lens flare's thresholds against an exposure.

    Args:
        composer: The composer; its bloom and lens flare passes change.
        exposure: What the light is scaled by before the tone curve.

    The thresholds become `BLOOM_THRESHOLD` and `FLARE_THRESHOLD` over the
    exposure, so a pixel blooms when its exposed light passes them.
    """
    # The render pass always comes first.
    for index in range(len(composer.passes)):  # pragma: no branch
        if composer.passes[index].kind == BLOOM:
            composer.passes[index].threshold = BLOOM_THRESHOLD / exposure
        elif composer.passes[index].kind == LENSFLARE:
            composer.passes[index].display.flare_threshold = (
                FLARE_THRESHOLD / exposure
            )


def daylight_split(weather: WeatherParameters) -> DaylightSplit:
    """Return the sun's and the sky's light of a weather.

    Args:
        weather: The weather.

    Returns:
        `sun_intensity`, the sky's `sky_illuminance` in the renderer's
        units, the light on level ground from `render_sky.ground_light`,
        and the sun's direction.
    """
    return DaylightSplit(
        sun_intensity(weather),
        light_units(sky_illuminance(weather)),
        ground_light(weather),
        sun_direction(weather),
    )


struct CarlaRenderer(Movable):
    """A world's town and actors in a scene, and the cameras that see it."""

    var scene: Scene
    var assets: Assets
    var registry: AssetRegistry
    var town: Town
    var props: Props
    var actors: ActorVisuals
    var sun: SunLight
    # The moon's light, as its index in `Scene.lights`.
    var moon: Int
    var moon_node: NodeId
    var eye: NodeId
    var sky: Optional[SkyLighting]
    var sky_weather: WeatherParameters
    var sky_size: Int
    var workers: Int
    # How many times the size each way an image is drawn at; one for none.
    var supersample: Int
    var frame_count: Int
    var renderer: Renderer
    var sensor_sources: List[MaterialId]
    var sensor_tags: List[Int]
    var sensor_materials: List[MaterialId]
    var coverage_sources: List[TextureId]
    var coverage_maps: List[TextureId]
    var coverage_read: List[TextureId]

    def __init__(
        out self,
        world: World,
        var settings: TownSettings,
        workers: Int = 1,
        sky_size: Int = 128,
        antialias: Bool = True,
        supersample: Int = SUPERSAMPLE,
        var registry: AssetRegistry = AssetRegistry(),
    ) raises:
        """Build a world's town into a new scene.

        Args:
            world: The world; its map is read.
            settings: How to build the town.
            workers: How many threads the renderer draws with.
            sky_size: Texels on a side of each face of the sky's cube.
            antialias: Whether to supersample each image.
            supersample: How many times the size each way to draw at when
                antialiased: 2 for speed, 3 or 4 for stills.
            registry: The photoscanned assets; none by default, so every
                asset is procedural.

        Raises:
            Error: If the supersampling is less than one, or the town
                cannot be built.
        """
        if supersample < 1:
            raise Error("A camera supersamples by one or more")
        self.scene = Scene()
        self.assets = Assets()
        self.registry = registry^
        # The photoscans decode at once, `workers` at a time.
        self.registry.preload(workers)
        self.town = Town(
            world.map, self.scene, self.assets, settings^, self.registry
        )
        self.props = Props(world.map, self.scene, self.assets)
        self.actors = ActorVisuals()
        self.sun = SunLight(self.scene)
        self.sun.shadow.bias = -0.0004
        self.sun.shadow.normal_bias = 0.04
        self.sun.shadow.map_size = 2048
        self.sun.shadow.far = SUN_SHADOW_REACH
        self.moon_node = self.scene.add(Object3D())
        self.moon = len(self.scene.lights)
        self.scene.add_light(
            directional_light(Color(200, 210, 255), self.moon_node, 0)
        )
        self.eye = self.scene.add(Object3D())
        self.sky = None
        self.sky_weather = WeatherParameters()
        self.sky_size = sky_size
        self.workers = workers
        self.supersample = supersample if antialias else 1
        self.frame_count = 0
        self.renderer = Renderer(8, 8, workers)
        self.sensor_sources = List[MaterialId]()
        self.sensor_tags = List[Int]()
        self.sensor_materials = List[MaterialId]()
        self.coverage_sources = List[TextureId]()
        self.coverage_maps = List[TextureId]()
        self.coverage_read = List[TextureId]()

    def update(mut self, world: World) raises:
        """Bring the scene to the world's state: the weather, the traffic
        lights and the actors.

        The sky is drawn again only when the weather changes. It is the
        cached HDRI of `render_sky.sky_key` when the registry holds one,
        and Preetham's sky otherwise.

        Args:
            world: The world.

        Raises:
            Error: If the sky, a material or an actor cannot be updated.
        """
        var weather = world.get_weather()
        self.town.set_weather(self.scene, self.assets, weather)
        self.props.set_states(self.assets, world)
        self.actors.sync(world, self.scene, self.assets, self.registry)
        if not Bool(self.sky) or not (self.sky_weather == weather):
            var scanned = self.registry.cached_entry(sky_key(weather))
            var sky_assets = Assets()
            var sky: SkyLighting
            if Bool(scanned):
                sky = hdri_sky(
                    sky_assets,
                    self.registry.hdri(scanned.value()),
                    weather,
                    self.sky_size,
                )
            else:
                sky = build_sky(
                    self.renderer, sky_assets, weather, self.sky_size
                )
            var background = CubeTexture(
                copy=sky_assets.cube_textures.get(sky.background)
            )
            var environment = CubeTexture(
                copy=sky_assets.cube_textures.get(sky.environment)
            )
            if Bool(self.sky):
                var owned = self.sky.value()
                self.assets.cube_textures.textures[owned.background.value] = (
                    background^
                )
                self.assets.cube_textures.textures[owned.environment.value] = (
                    environment^
                )
                sky.background = owned.background
                sky.environment = owned.environment
            else:
                sky.background = self.assets.cube_textures.add(background^)
                sky.environment = self.assets.cube_textures.add(environment^)
            self.scene.background = cube_background(sky.background)
            self.scene.environment = sky.environment
            self.sky = sky
            self.sky_weather = weather
        var toward = sun_direction(weather)
        self.scene.node(self.sun.node).set_position(
            toward.x * 300, toward.y * 300, toward.z * 300
        )
        self.sun.color = _color_of(sun_color(weather))
        self.sun.intensity = sun_intensity(weather)
        self.sun.cast_shadow = daylight(weather) > 0
        var moon = moon_direction(weather)
        self.scene.node(self.moon_node).set_position(
            moon.x * 300, moon.y * 300, moon.z * 300
        )
        self.scene.lights[self.moon].intensity = moon_intensity(weather)
        self.scene.lights[self.moon].color = _color_of(moon_color())
        self.scene.update()

    def _renderer_for(mut self, settings: RgbCameraSettings) raises:
        """Keep one renderer for the camera's size, so the motion blur can
        see the frame before. It draws at `supersample` times the size."""
        var width = settings.image_width * self.supersample
        var height = settings.image_height * self.supersample
        if self.renderer.width != width or self.renderer.height != height:
            self.renderer = Renderer(width, height, self.workers)
        self.renderer.tone_mapping = ACES_FILMIC_TONE_MAPPING
        self.renderer.shadow_map_type = PCF_SOFT_SHADOW_MAP

    def render_rgb(
        mut self, world: World, camera: ActorId
    ) raises -> Framebuffer:
        """Return the RGB image a camera actor sees now.

        Args:
            world: The world; call `update` after the world changes.
            camera: The camera actor, whose attributes and transform are
                read.

        Returns:
            The image, at the camera's size, in sRGB.

        Raises:
            Error: If the actor is not alive, an attribute is refused, or
                the scene cannot be drawn.
        """
        var settings = rgb_camera_settings(world.actor(camera).attributes)
        if not Bool(self.sky):
            self.update(world)
        self._renderer_for(settings)
        var weather = world.get_weather()
        var passes = camera_passes(settings, wet_surface(weather).wetness)
        var composer = EffectComposer()
        # The render pass is always first.
        for p in passes:  # pragma: no branch
            composer.add_pass(p.copy())
        var flat = PerspectiveCamera(
            Angle(60, DEGREE), 1, CAMERA_NEAR, CAMERA_FAR
        )
        var fisheye = Bool(settings.wide_angle)
        # A wide-angle lens draws a cube and has no pinhole camera: its
        # field of view can pass 180 degrees.
        var view = PerspectiveCamera(
            Angle(60, DEGREE), 1, CAMERA_NEAR, CAMERA_FAR
        ) if fisheye else self._pose_camera(world, camera, settings)
        var frame: RenderTarget
        var first_effect = 1
        if fisheye:
            frame = self._wide_angle(
                settings.wide_angle.value(),
                world.get_transform(camera),
                weather,
            )
        else:
            frame = self._perspective(weather, settings, composer, view)
            if len(passes) > 1 and passes[1].kind == SSR_NODE:
                first_effect = 2
        var exposure = camera_exposure(settings, metered_luminance(frame))
        set_thresholds(composer, exposure)
        for index in range(first_effect, len(passes)):
            if fisheye:
                # A cube has no depth and no motion: only the image
                # effects.
                var kind = passes[index].kind
                if kind != MOTION_BLUR and kind != SSR_NODE:
                    composer.run_step(
                        index,
                        frame,
                        self.renderer,
                        self.scene,
                        self.assets,
                        flat,
                        0.05,
                    )
            else:
                composer.run_step(
                    index,
                    frame,
                    self.renderer,
                    self.scene,
                    self.assets,
                    view,
                    0.05,
                )
        apply_gains(frame, white_balance(settings.temp, settings.tint))
        self.renderer.tone_mapping_exposure = exposure
        composer.add_pass(output_pass())
        composer.run_step(
            len(composer.passes) - 1,
            frame,
            self.renderer,
            self.scene,
            self.assets,
            flat,
            0.05,
        )
        apply_gamma(frame, settings.gamma)
        if settings.enable_postprocess_effects:
            apply_lens(frame, settings.lens)
        self.frame_count += 1
        return frame.resolve(
            self.workers,
            NO_TONE_MAPPING,
            1.0,
            output=self.renderer.output_encoding(),
        )

    def _perspective(
        mut self,
        weather: WeatherParameters,
        settings: RgbCameraSettings,
        mut composer: EffectComposer,
        view: PerspectiveCamera,
    ) raises -> RenderTarget:
        """Return a pinhole camera's light: the scene drawn, reflected,
        occluded, shadowed by the clouds, fogged and rained on. The
        composer's effects are left to the caller."""
        self.sun.update(self.scene, view)
        var outputs = frame_outputs(composer.passes)
        var has_normals = False
        # A frame always writes its color.
        for o in outputs:  # pragma: no branch
            if o == OUTPUT_NORMAL:
                has_normals = True
        if not has_normals:
            outputs.append(OUTPUT_NORMAL)
        var scale = self.supersample
        var frame = RenderTarget(
            settings.image_width * scale,
            settings.image_height * scale,
            self.renderer.background,
            outputs=outputs,
        )
        # The frame's own shadow maps, which the light effects read again.
        var drawn = self.renderer.render_into_keeping_shadows(
            frame, self.scene, self.assets, view
        )
        if scale > 1:
            frame = frame.downsampled(scale)
        if len(composer.passes) > 1 and composer.passes[1].kind == SSR_NODE:
            composer.run_step(
                1, frame, self.renderer, self.scene, self.assets, view, 0.05
            )
        var rays = ViewRays(
            settings.image_width,
            settings.image_height,
            view.projection_matrix(),
            view.view_matrix_in(self.scene),
        )
        var maps = List[ShadowMap]()
        if self.sun.cast_shadow:
            maps = sun_maps(drawn, self.sun.lights)
        var light = daylight_split(weather)
        var shares = direct_shares(frame, rays, maps, light)
        var depth = DepthView(
            frame.depth,
            frame.width,
            frame.height,
            view.projection_matrix(),
            CAMERA_NEAR,
            CAMERA_FAR,
            frame.depth_mode,
            frame.normals,
        )
        apply_ambient_occlusion(
            frame,
            ambient_occlusion(frame, depth, town_gtao()),
            shares,
            AO_STRENGTH,
        )
        apply_cloud_shadows(
            frame,
            rays,
            shares,
            ImprovedNoise(),
            light.direction,
            sky_settings(weather).cloud_cover,
        )
        var fog = height_fog(weather)
        var lit = List[Float32]()
        if len(maps) > 0 and fog.is_on():
            lit = fog_light_shafts(frame, rays, fog, maps, light.direction)
        var tint = sun_color(weather)
        var horizon = self.sky.value().horizon
        apply_height_fog(
            frame,
            rays,
            fog,
            self.assets.cube_textures.get(self.sky.value().background),
            light.direction,
            FloatColor(
                tint.r * light.sun, tint.g * light.sun, tint.b * light.sun
            ),
            Length(0, METER),
            lit,
        )
        var rain = rain_settings(weather)
        if rain.is_on():
            var catch = FloatColor(
                horizon.r * 0.3 + 0.01,
                horizon.g * 0.3 + 0.01,
                horizon.b * 0.3 + 0.012,
            )
            draw_rain(frame, rays, rain, catch, self.frame_count + 1)
        return frame^

    def semantic_tags(self, world: World) raises -> List[SemanticTag]:
        """Return the semantic tag of each mesh of the scene.

        The town's and the props' meshes carry the tags they were built
        with, and each actor's model carries its actor's first tag.

        Args:
            world: The world; the actors' tags are read.

        Returns:
            One tag per mesh in `scene.meshes`, `UNLABELED` for any other.

        Raises:
            Error: If a model's meshes are not in the scene.
        """
        var tags = List[SemanticTag](
            length=len(self.scene.meshes), fill=UNLABELED
        )
        var at = 0
        for tag in self.town.tags:
            tags[at] = tag
            at += 1
        for tag in self.props.tags:
            tags[at] = tag
            at += 1
        self.actors.tag_meshes(world, tags)
        return tags^

    def _coverage_map(mut self, source: TextureId) raises -> TextureId:
        """Keep a white RGB copy of a color map, with identical alpha and
        sampling, refreshed once per capture so dynamic alpha stays current."""
        if source == NO_TEXTURE:
            return NO_TEXTURE
        var slot = -1
        for i in range(len(self.coverage_sources)):
            if self.coverage_sources[i] == source:
                slot = i
                break
        if source in self.coverage_read:
            return self.coverage_maps[slot]
        var texture = Texture(copy=self.assets.textures.get(source))
        # Replace RGB in every mip level; preserve alpha and sampler state.
        for i in range(0, len(texture.pixels), 4):
            texture.pixels[i] = 255
            texture.pixels[i + 1] = 255
            texture.pixels[i + 2] = 255
        for i in range(0, len(texture.data), 4):
            texture.data[i] = 1
            texture.data[i + 1] = 1
            texture.data[i + 2] = 1
        if slot < 0:
            slot = len(self.coverage_sources)
            self.coverage_sources.append(source)
            self.coverage_maps.append(self.assets.textures.add(texture^))
        else:
            self.assets.textures.textures[self.coverage_maps[slot].value] = (
                texture^
            )
        self.coverage_read.append(source)
        return self.coverage_maps[slot]

    def _sensor_material(
        mut self, id: MaterialId, tag: SemanticTag
    ) raises -> MaterialId:
        """Reuse one flat override per source material and tag, retaining
        the source's cutout and sidedness without tinting the tag color."""
        var source = self.assets.materials.get(id)
        var map = NO_TEXTURE
        if (
            source.alpha_test > 0
            or source.alpha_hash
            or source.alpha_to_coverage
        ):
            map = self._coverage_map(source.map)
        var flat = Material(
            cityscapes_color(tag),
            map=map,
            side=source.side,
            opacity=source.opacity,
            kind=BASIC,
            alpha_map=source.alpha_map,
            alpha_test=source.alpha_test,
        )
        flat.visible = source.visible
        flat.alpha_hash = source.alpha_hash
        flat.alpha_to_coverage = source.alpha_to_coverage
        flat.set_clipping_planes(
            source.clipping_planes(),
            source.clip_intersection,
            source.clip_shadows,
        )
        for i in range(len(self.sensor_sources)):
            if (
                self.sensor_sources[i] == id
                and self.sensor_tags[i] == tag.value
            ):
                var cached = self.sensor_materials[i]
                self.assets.materials.materials[cached.value] = flat
                return cached
        var added = self.assets.materials.add(flat)
        self.sensor_sources.append(id)
        self.sensor_tags.append(tag.value)
        self.sensor_materials.append(added)
        return added

    def _ground_truth(
        mut self, world: World, camera: ActorId
    ) raises -> Tuple[RenderTarget, ViewRays]:
        """Draw the scene through a camera actor with each mesh in the
        flat CityScapes color of its tag, and keep its depth.

        Raises:
            Error: If the actor is not alive, an attribute is refused, or
                the scene cannot be drawn.
        """
        var settings = rgb_camera_settings(world.actor(camera).attributes)
        if not Bool(self.sky):
            self.update(world)
        var tags = self.semantic_tags(world)
        var saved = self.scene.meshes.copy()
        var background = self.scene.background
        var view = self._pose_camera(world, camera, settings)
        var renderer = Renderer(
            settings.image_width, settings.image_height, self.workers
        )
        renderer.tone_mapping = NO_TONE_MAPPING
        renderer.local_clipping_enabled = self.renderer.local_clipping_enabled
        renderer.clipping_planes = self.renderer.clipping_planes.copy()
        var frame = RenderTarget(
            settings.image_width, settings.image_height, Color(0, 0, 0)
        )
        self.coverage_read.clear()
        try:
            for i in range(len(saved)):
                var original = saved[i].material
                var flat = self._sensor_material(original, tags[i])
                self.scene.meshes[i].material = flat
                for k in range(len(saved[i].materials)):
                    var group = saved[i].materials[k]
                    var override = self._sensor_material(group, tags[i])
                    self.scene.meshes[i].materials[k] = override
            self.scene.background = color_background(cityscapes_color(SKY))
            renderer.render_into(frame, self.scene, self.assets, view)
        finally:
            self.scene.meshes = saved^
            self.scene.background = background
        var rays = ViewRays(
            settings.image_width,
            settings.image_height,
            view.projection_matrix(),
            view.view_matrix_in(self.scene),
        )
        return (frame^, rays)

    def render_semantic(
        mut self, world: World, camera: ActorId
    ) raises -> Framebuffer:
        """Return the semantic image a camera actor sees now, in the
        CityScapes palette.

        The rasterizer draws each mesh flat in its tag's color, as CARLA's
        semantic camera reads the tags from its renderer's buffers.

        Args:
            world: The world; call `update` after the world changes.
            camera: The camera actor, whose image size, field of view and
                transform are read.

        Returns:
            The image, at the camera's size. The sky is `SKY`'s color.

        Raises:
            Error: If the actor is not alive, an attribute is refused, or
                the scene cannot be drawn.
        """
        var drawn = self._ground_truth(world, camera)
        ref frame = drawn[0]
        var palette = List[FloatColor]()
        # A constant count, more than zero.
        for t in range(SEMANTIC_TAGS):  # pragma: no branch
            var c = cityscapes_color(SemanticTag(t))
            palette.append(
                FloatColor(
                    srgb_to_linear(Float32(c.r) / 255),
                    srgb_to_linear(Float32(c.g) / 255),
                    srgb_to_linear(Float32(c.b) / 255),
                )
            )
        var out = Framebuffer(frame.width, frame.height, Color(0, 0, 0))
        # A frame has at least one pixel.
        for y in range(frame.height):  # pragma: no branch
            for x in range(frame.width):  # pragma: no branch
                var seen = frame.colors[y * frame.width + x]
                var best = 0
                var nearest = Float32(1e30)
                # A constant count, more than zero.
                for t in range(SEMANTIC_TAGS):  # pragma: no branch
                    var p = palette[t]
                    var d = (
                        (p.r - seen.r) * (p.r - seen.r)
                        + (p.g - seen.g) * (p.g - seen.g)
                        + (p.b - seen.b) * (p.b - seen.b)
                    )
                    if d < nearest:
                        nearest = d
                        best = t
                out.set_pixel(x, y, cityscapes_color(SemanticTag(best)))
        return out^

    def render_depth(
        mut self, world: World, camera: ActorId
    ) raises -> Framebuffer:
        """Return the depth image a camera actor sees now, as CARLA packs
        it.

        Args:
            world: The world; call `update` after the world changes.
            camera: The camera actor, whose image size, field of view and
                transform are read.

        Returns:
            The image, at the camera's size: each pixel's depth along the
            camera's forward axis, packed by `encode_depth`. The sky is
            `DEPTH_FAR`.

        Raises:
            Error: If the actor is not alive, an attribute is refused, or
                the scene cannot be drawn.
        """
        var drawn = self._ground_truth(world, camera)
        ref frame = drawn[0]
        var rays = drawn[1]
        var out = Framebuffer(frame.width, frame.height, Color(0, 0, 0))
        # A frame has at least one pixel.
        for y in range(frame.height):  # pragma: no branch
            for x in range(frame.width):  # pragma: no branch
                var depth = frame.depth[y * frame.width + x]
                var planar = DEPTH_FAR
                # A pixel that meets nothing keeps the cleared depth.
                if depth < 1:
                    planar = Length(-rays.view_point(x, y, depth).z, METER)
                out.set_pixel(x, y, encode_depth(planar))
        return out^

    def _pose_camera(
        mut self, world: World, camera: ActorId, settings: RgbCameraSettings
    ) raises -> PerspectiveCamera:
        """Stand the eye at a camera actor and return a camera through
        it."""
        var pose = world.get_transform(camera).camera_matrix()
        ref eye = self.scene.node(self.eye)
        eye.set_rotation_from_matrix(pose)
        eye.set_position(
            pose.elements[12], pose.elements[13], pose.elements[14]
        )
        self.scene.update()
        self._choose_detail(
            Vector3(pose.elements[12], pose.elements[13], pose.elements[14])
        )
        var view = PerspectiveCamera(
            vertical_fov(
                settings.fov, settings.image_width, settings.image_height
            ),
            Float32(settings.image_width) / Float32(settings.image_height),
            CAMERA_NEAR,
            CAMERA_FAR,
        )
        view.attach(self.eye)
        return view^

    def _choose_detail(mut self, eye: Vector3) raises:
        """Show each town package tile at the level of detail for a camera
        at `eye`, in the scene's frame, and stand the package's lights at
        the lamps nearest it. A town with no package has no LODs and no
        lamps, and its scene is left as it is."""
        if len(self.scene.lods) > 0:
            # The levels are chosen on the current scene; moving the lamps
            # leaves it to be updated again.
            self.scene.update_lods(eye)
            self.town.place_lamps(self.scene, eye)
            self.scene.update()

    def _wide_angle(
        mut self,
        lens: WideAngleLens,
        transform: CarlaTransform,
        weather: WeatherParameters,
    ) raises -> RenderTarget:
        """Return a fisheye camera's light, drawn from a cube through its
        lens."""
        var fog = height_fog(weather)
        var before = self.scene.fog
        if fog.density.value > 0:
            self.scene.fog = exp2_fog(
                _color_of(self.sky.value().horizon),
                InverseLength(fog.density.to(PER_METER) * 0.7, PER_METER),
            )
        var at = transform.location
        var cube: CubeTexture
        try:
            self._choose_detail(Vector3(at.x, at.z, at.y))
            cube = scene_cube(
                self.renderer,
                self.scene,
                self.assets,
                CAMERA_NEAR,
                CAMERA_FAR,
                max(lens.height, 16),
                Vector3(at.x, at.z, at.y),
            )
        finally:
            self.scene.fog = before
        var frame = RenderTarget(lens.width, lens.height, Color(0, 0, 0))
        # A lens has at least one pixel.
        for y in range(lens.height):  # pragma: no branch
            for x in range(lens.width):  # pragma: no branch
                var ray = lens.pixel_ray(Float32(x) + 0.5, Float32(y) + 0.5)
                var d = transform.rotation.rotate_vector(ray.direction)
                var seen = cube.sample(Vector3(d.x, d.z, d.y))
                frame.colors[y * lens.width + x] = FloatColor(
                    seen.r * ray.weight,
                    seen.g * ray.weight,
                    seen.b * ray.weight,
                    1,
                )
        return frame^
