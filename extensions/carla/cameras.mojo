# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's ground-truth cameras, cast against any `RayScene`, its
wide-angle lens models, and its event camera.

**Lens models.** The six camera models, the Kannala-Brandt polynomial and
its Newton solve, and the focal length a field of view gives are CARLA's
simulator plugin, `Carla/Util/CameraModelUtil.cpp`. How the attributes
set them up is `Carla/Actor/ActorBlueprintFunctionLibrary.cpp`,
`SetCamera` for a wide-angle camera: the field of view is vertical, and
the focal length is in pixels, from the image height. A pixel's ray is
`SceneCaptureSensor_WideAngleLens.cpp`'s `FindFaceIndex`: with (u, v) the
pixel's offset from the image center over the focal length, the angle
from forward is the model's angle of |(u, v)|, and the ray leans toward
(u, -v). CARLA renders six cube faces and resamples them in a compute
shader that is not in its source. This port casts each pixel's ray
directly instead, and makes these choices where the shader is missing:

- With `fov_mask`, a pixel whose angle from forward is more than half the
  field of view is black. With `fov_fade_size` in degrees, the pixels
  within that much of the edge fade linearly to black.
- With `equirectangular`, pixel column x looks at longitude (x / width
  * 2 - 1) pi plus `longitude_offset`, and row y at latitude (1 - y /
  height * 2) pi / 2.
- With `perspective`, the image is the pinhole view of the same vertical
  field of view.

**Images.** One ray through the center of each pixel, as
`extensions.carla.capture` casts:

- Depth: the planar depth, packed by `sensor.encode_depth`. A miss is the
  full 1000 m.
- Semantic segmentation: the tag in red, as CARLA's raw image holds it.
- Instance segmentation: `image_convert.encode_instance` of the tag and
  the low 16 bits of the actor id, CARLA's `GetActorLabelColor`.
- Normals: the surface normal in the camera's view frame (x right, y up,
  z toward the camera), each part from -1 to 1 stored from 0 to 255, as
  `image_convert.decode_normal` reads it. A miss is the zero normal.
- Optical flow: the move of each pixel's point since the last frame, in
  normalized device units (x right, y down, 2 across the image). The
  point moves back by its velocity times the tick, and the last frame's
  camera projects it. `image_convert.encode_flow_image` colors it.
- Shaded: a stand-in for the RGB image that the event camera needs,
  this port's own. The tag's CityScapes color times 0.2 + 0.8 of the
  cosine between the ray and the surface normal. A miss is the sky's
  color.

**Event camera.** `DVSCamera` is CARLA's simulator plugin, `Carla/Sensor/
DVSCamera.cpp`: the log intensity of each pixel is compared with the
last frame's, and each crossing of the contrast threshold since the last
event gives an event with a time interpolated in the tick. The events
are sorted by time. CARLA's sort is not stable; this one is.
"""


from extensions.carla.blueprint import ActorAttributeValue
from extensions.carla.image_convert import (
    InstanceId,
    encode_instance,
)
from extensions.carla.sensor import (
    CameraIntrinsics,
    DEPTH_FAR,
    SKY,
    SemanticTag,
    cityscapes_color,
    encode_depth,
)
from extensions.carla.sensor_attributes import (
    attribute_bool,
    attribute_float,
    validate_sensor_float,
    validate_sensor_nonnegative,
    validate_sensor_positive,
    attribute_int,
    attribute_string,
)
from extensions.carla.sensor_noise import SensorRandom
from extensions.carla.sensor_rays import RayScene
from extensions.carla.transform import CarlaTransform
from math.vector3 import Vector3
from render.framebuffer import (
    Color,
    Framebuffer,
)
from std.math import (
    asin,
    atan,
    atan2,
    cos,
    isfinite,
    log,
    sin,
    sqrt,
    tan,
)
from units.si import (
    DEGREE,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Duration64,
    Length,
    METER,
)

comptime _PI = Float32(3.14159265358979323846)
# CARLA's Newton steps for the Kannala-Brandt angle.
comptime KANNALA_BRANDT_SOLVER_ITERATIONS = 32


@fieldwise_init
struct CameraModel(Equatable, ImplicitlyCopyable, Writable):
    """A wide-angle lens model, CARLA's `ECameraModel`."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the six models.

        Returns:
            Whether the value is from 0 to 5.
        """
        return self.value >= 0 and self.value <= 5


comptime PERSPECTIVE = CameraModel(0)
comptime STEREOGRAPHIC = CameraModel(1)
comptime EQUIDISTANT = CameraModel(2)
comptime EQUISOLID = CameraModel(3)
comptime ORTHOGRAPHIC = CameraModel(4)
comptime KANNALA_BRANDT = CameraModel(5)


def camera_model_of(name: String) -> CameraModel:
    """Return the model a `camera_model` attribute names.

    Args:
        name: "perspective", "stereographic", "equidistant", "equisolid",
            "orthographic" or "kannala-brandt", as CARLA spells them.

    Returns:
        The model, or `PERSPECTIVE` for any other text, CARLA's default.
    """
    var names: List[String] = [
        "perspective",
        "stereographic",
        "equidistant",
        "equisolid",
        "orthographic",
        "kannala-brandt",
    ]
    # The list is a constant and not empty.
    for i in range(len(names)):  # pragma: no branch
        if names[i] == name:
            return CameraModel(i)
    return PERSPECTIVE


def kannala_brandt_polynomial(
    theta: Float32, coefficients: List[Float32]
) -> Float32:
    """Return theta (1 + k0 theta^2 + k1 theta^4 + ...),
    `ComputeCameraPolynomial`.

    Args:
        theta: The angle from forward, in radians.
        coefficients: The coefficients k0, k1 and on.

    Returns:
        The distance from the image center over the focal length.
    """
    var result = Float32(1)
    var theta2 = theta * theta
    var theta_n = Float32(1)
    for k in coefficients:
        theta_n *= theta2
        result += k * theta_n
    return result * theta


def kannala_brandt_derivative(
    theta: Float32, coefficients: List[Float32]
) -> Float32:
    """Return the polynomial's derivative, `ComputeCameraPolynomialDerivative`.

    Args:
        theta: The angle from forward, in radians.
        coefficients: The coefficients k0, k1 and on.

    Returns:
        1 + 3 k0 theta^2 + 5 k1 theta^4 + ...
    """
    var result = Float32(1)
    var theta2 = theta * theta
    var theta_n = theta2
    var a = Float32(3)
    for k in coefficients:
        result += a * k * theta_n
        a += 2
        theta_n *= theta2
    return result


def _check_model(model: CameraModel) raises:
    if not model.is_valid():
        raise Error("A camera model must name one of six models")


def compute_angle(
    model: CameraModel, distance: Float32, coefficients: List[Float32]
) raises -> Angle:
    """Return the angle from forward of a ray, `ComputeAngle`.

    Args:
        model: The lens model.
        distance: The pixel's distance from the image center over the
            focal length.
        coefficients: The Kannala-Brandt coefficients.

    Returns:
        The angle atan(d), 2 atan(d / 2), d, 2 asin(d / 2), asin(d), or the
        Kannala-Brandt angle after 32 Newton steps from d. The sines are
        clamped to -1 through 1.

    Raises:
        Error: If the model is not valid.
    """
    _check_model(model)
    var d = distance
    if model == PERSPECTIVE:
        return Angle(atan(d), RADIAN)
    if model == STEREOGRAPHIC:
        return Angle(atan(d * 0.5) * 2, RADIAN)
    if model == EQUIDISTANT:
        return Angle(d, RADIAN)
    if model == EQUISOLID:
        return Angle(asin(min(max(d * 0.5, -1), 1)) * 2, RADIAN)
    if model == ORTHOGRAPHIC:
        return Angle(asin(min(max(d, -1), 1)), RADIAN)
    var theta = d
    # The step count is a positive constant.
    for _ in range(KANNALA_BRANDT_SOLVER_ITERATIONS):  # pragma: no branch
        var n = d - kannala_brandt_polynomial(theta, coefficients)
        var slope = -kannala_brandt_derivative(theta, coefficients)
        theta -= n / slope
    return Angle(theta, RADIAN)


def compute_distance(
    model: CameraModel,
    angle: Angle,
    image_height: Int,
    coefficients: List[Float32],
) raises -> Float32:
    """Return the focal length that fits a field of view to an image
    height, `ComputeDistance`.

    Args:
        model: The lens model.
        angle: The vertical field of view.
        image_height: The image's height, in pixels.
        coefficients: The Kannala-Brandt coefficients.

    Returns:
        The focal length in pixels: half the height over the model's
        distance for half the angle.

    Raises:
        Error: If the model is not valid.
    """
    _check_model(model)
    var r = Float32(image_height) * 0.5
    var half = angle.to(RADIAN) * 0.5
    if model == PERSPECTIVE:
        return r / tan(half)
    if model == STEREOGRAPHIC:
        return r / (tan(half * 0.5) * 2)
    if model == EQUIDISTANT:
        return r / half
    if model == EQUISOLID:
        return r / (sin(half * 0.5) * 2)
    if model == ORTHOGRAPHIC:
        return r / sin(half)
    return r / kannala_brandt_polynomial(half, coefficients)


@fieldwise_init
struct PixelRay(ImplicitlyCopyable):
    """A pixel's ray in the camera's own frame, and how much it counts."""

    # Forward, right and up; unit length.
    var direction: Vector3
    # 1 in the image, 0 where a mask blacks the pixel out.
    var weight: Float32


struct WideAngleLens(Copyable, Movable):
    """A wide-angle camera's lens, `ASceneCaptureSensor_WideAngleLens`."""

    var model: CameraModel
    var coefficients: List[Float32]
    var width: Int
    var height: Int
    # The vertical field of view.
    var fov: Angle
    # In pixels.
    var focal_length: Float32
    var perspective: Bool
    var equirectangular: Bool
    var fov_mask: Bool
    # In degrees.
    var fov_fade_size: Float32
    var longitude_offset: Angle

    def __init__(
        out self,
        model: CameraModel,
        var coefficients: List[Float32],
        width: Int,
        height: Int,
        fov: Angle,
    ) raises:
        """Create a lens whose focal length fits the vertical fov.

        Args:
            model: The lens model.
            coefficients: The Kannala-Brandt coefficients.
            width: Pixels across. It must be positive.
            height: Pixels down. It must be positive.
            fov: The vertical field of view.

        Raises:
            Error: If the model, size, or physical lens settings are invalid.
        """
        if width <= 0 or height <= 0:
            raise Error("A camera image needs a positive size")
        validate_sensor_positive(fov.value, "A camera fov")
        if fov.to(DEGREE) > 360:
            raise Error("A wide-angle camera fov must not exceed 360 degrees")
        for coefficient in coefficients:
            validate_sensor_float(coefficient, "A lens coefficient")
        self.focal_length = compute_distance(model, fov, height, coefficients)
        validate_sensor_positive(self.focal_length, "A camera focal length")
        self.model = model
        self.coefficients = coefficients^
        self.width = width
        self.height = height
        self.fov = fov
        self.perspective = False
        self.equirectangular = False
        self.fov_mask = False
        self.fov_fade_size = 0
        self.longitude_offset = Angle(0, RADIAN)

    @staticmethod
    def from_attributes(
        attributes: List[ActorAttributeValue],
    ) raises -> WideAngleLens:
        """Read a wide-angle camera's lens from its attributes,
        `SetCamera`.

        Args:
            attributes: The actor's attributes.

        Returns:
            The lens: the model, the coefficients (CARLA's defaults for
            Kannala-Brandt), the image size, the fov, a focal length that
            is not zero, and the switches.

        Raises:
            Error: If the image size or physical lens settings are invalid.
        """
        var model = camera_model_of(
            attribute_string(attributes, "camera_model", "perspective")
        )
        var coefficients = List[Float32]()
        if model == KANNALA_BRANDT:
            coefficients = [
                attribute_float(attributes, "k0", 0.08309221636708493),
                attribute_float(attributes, "k1", 0.01112126630599195),
                attribute_float(attributes, "k2", 0.008587261043925865),
                attribute_float(attributes, "k3", 0.0008542188930970716),
            ]
        var fov = attribute_float(attributes, "fov", 90)
        if fov == 0:
            fov = 90
        var out = WideAngleLens(
            model,
            coefficients^,
            attribute_int(attributes, "image_size_x", 800),
            attribute_int(attributes, "image_size_y", 600),
            Angle(fov, DEGREE),
        )
        var focal = attribute_float(attributes, "focal_length", 0)
        validate_sensor_nonnegative(focal, "focal_length")
        if focal != 0:
            out.focal_length = focal
        out.perspective = attribute_bool(attributes, "perspective", False)
        out.equirectangular = attribute_bool(
            attributes, "equirectangular", False
        )
        out.fov_mask = attribute_bool(attributes, "fov_mask", False)
        if out.equirectangular:
            out.longitude_offset = Angle(
                attribute_float(attributes, "longitude_offset", 0), DEGREE
            )
        if out.fov_mask:
            out.fov_fade_size = attribute_float(attributes, "fov_fade_size", 0)
            validate_sensor_nonnegative(out.fov_fade_size, "fov_fade_size")
        return out^

    def pixel_ray(self, x: Float32, y: Float32) raises -> PixelRay:
        """Return the ray through a point of the image.

        Args:
            x: Pixel column. Use x + 0.5 for the center of pixel x.
            y: Pixel row.

        Returns:
            The ray in the camera's frame and its weight.

        Raises:
            Error: If the model is not valid.
        """
        if self.equirectangular:
            var lon = (
                x / Float32(self.width) * 2 - 1
            ) * _PI + self.longitude_offset.to(RADIAN)
            var lat = (1 - y / Float32(self.height) * 2) * _PI / 2
            return PixelRay(
                Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat)), 1
            )
        # CARLA's center is the integer half of the size.
        var u = x - Float32(self.width // 2)
        var v = y - Float32(self.height // 2)
        if self.perspective:
            var f = compute_distance(
                PERSPECTIVE, self.fov, self.height, self.coefficients
            )
            var d = Vector3(f, u, -v)
            return PixelRay(d / d.length(), 1)
        u /= self.focal_length
        v /= self.focal_length
        var r = sqrt(u * u + v * v)
        var theta = compute_angle(self.model, r, self.coefficients).to(RADIAN)
        var rho = atan2(v, u)
        var weight = Float32(1)
        if self.fov_mask:
            var edge = self.fov.to(RADIAN) / 2 - theta
            if edge < 0:
                weight = 0
            elif self.fov_fade_size > 0:
                weight = min(
                    edge / Angle(self.fov_fade_size, DEGREE).to(RADIAN), 1
                )
        return PixelRay(
            Vector3(cos(theta), sin(theta) * cos(rho), -sin(theta) * sin(rho)),
            weight,
        )


struct CameraGeometry(Copyable, Movable):
    """A camera's rays: a pinhole camera or a wide-angle lens."""

    var width: Int
    var height: Int
    var intrinsics: Optional[CameraIntrinsics]
    var lens: Optional[WideAngleLens]

    @staticmethod
    def pinhole(intrinsics: CameraIntrinsics) -> CameraGeometry:
        """Use a pinhole camera with a horizontal field of view.

        Args:
            intrinsics: Its K matrix.

        Returns:
            The geometry.
        """
        return CameraGeometry(
            intrinsics.width, intrinsics.height, intrinsics, None
        )

    @staticmethod
    def wide_angle(var lens: WideAngleLens) -> CameraGeometry:
        """Use a wide-angle lens.

        Args:
            lens: The lens.

        Returns:
            The geometry.
        """
        var width = lens.width
        var height = lens.height
        return CameraGeometry(width, height, None, lens^)

    def __init__(
        out self,
        width: Int,
        height: Int,
        intrinsics: Optional[CameraIntrinsics],
        var lens: Optional[WideAngleLens],
    ):
        """Create a geometry. Use `pinhole` or `wide_angle`.

        Args:
            width: Pixels across.
            height: Pixels down.
            intrinsics: The pinhole camera, or None.
            lens: The lens, or None.
        """
        self.width = width
        self.height = height
        self.intrinsics = intrinsics
        self.lens = lens^

    def pixel_ray(self, x: Int, y: Int) raises -> PixelRay:
        """Return the ray through the center of a pixel.

        Args:
            x: The column.
            y: The row.

        Returns:
            The unit ray in the camera's frame and its weight.

        Raises:
            Error: If the lens model is not valid.
        """
        var u = Float32(x) + 0.5
        var v = Float32(y) + 0.5
        if Bool(self.lens):
            return self.lens.value().pixel_ray(u, v)
        var k = self.intrinsics.value()
        var d = Vector3(1.0, (u - k.cx) / k.focal, -(v - k.cy) / k.focal)
        return PixelRay(d / d.length(), 1)


@fieldwise_init
struct CameraKind(Equatable, ImplicitlyCopyable, Writable):
    """What a ground-truth camera writes into its image."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the five images.

        Returns:
            Whether the value is from 0 to 4.
        """
        return self.value >= 0 and self.value <= 4


comptime DEPTH_IMAGE = CameraKind(0)
comptime SEMANTIC_IMAGE = CameraKind(1)
comptime INSTANCE_IMAGE = CameraKind(2)
comptime NORMALS_IMAGE = CameraKind(3)
comptime SHADED_IMAGE = CameraKind(4)


def _byte(part: Float32) -> UInt8:
    return UInt8(Int(min(max(part * 0.5 + 0.5, 0), 1) * 255 + 0.5))


def encode_normal(normal: Vector3) -> Color:
    """Store a unit normal as a pixel, the inverse of `decode_normal`.

    Args:
        normal: The normal in the camera's view frame.

    Returns:
        Each part n as the byte round((n + 1) / 2 255).
    """
    return Color(_byte(normal.x), _byte(normal.y), _byte(normal.z))


def _shade(color: Color, light: Float32) -> Color:
    return Color(
        UInt8(Int(Float32(color.r) * light + 0.5)),
        UInt8(Int(Float32(color.g) * light + 0.5)),
        UInt8(Int(Float32(color.b) * light + 0.5)),
    )


def render_camera[
    T: RayScene
](
    mut scene: T,
    kind: CameraKind,
    camera: CarlaTransform,
    geometry: CameraGeometry,
    miss: SemanticTag = SKY,
) raises -> Framebuffer:
    """Cast one ground-truth image.

    Args:
        scene: What the rays meet.
        kind: Which image.
        camera: Where the camera is and where it looks.
        geometry: Its image size and rays.
        miss: The tag of a ray that meets nothing, such as `SKY`.

    Returns:
        The image. A pixel a lens mask blacks out is opaque black.

    Raises:
        Error: If the kind or a tag is not valid, or the scene cannot be
            tested.
    """
    if not kind.is_valid():
        raise Error("A camera kind must name one of five images")
    var out = Framebuffer(geometry.width, geometry.height, Color(0, 0, 0))
    for y in range(geometry.height):  # pragma: no branch
        for x in range(geometry.width):  # pragma: no branch
            var ray = geometry.pixel_ray(x, y)
            if not (ray.weight > 0):
                continue
            var direction = camera.rotation.rotate_vector(ray.direction)
            var hit = scene.cast_ray(camera.location, direction, DEPTH_FAR)
            var color: Color
            if kind == DEPTH_IMAGE:
                var depth = Float32(1000)
                if hit.hit:
                    depth = hit.distance.value * ray.direction.x
                color = encode_depth(Length(depth, METER))
            elif kind == SEMANTIC_IMAGE:
                var tag = hit.tag if hit.hit else miss
                color = Color(UInt8(tag.value), 0, 0)
            elif kind == INSTANCE_IMAGE:
                if hit.hit:
                    color = encode_instance(
                        hit.tag, InstanceId(hit.actor.value & 0xFFFF)
                    )
                else:
                    color = encode_instance(miss, InstanceId(0))
            elif kind == NORMALS_IMAGE:
                var n = Vector3(0, 0, 0)
                if hit.hit:
                    var local = camera.rotation.inverse_rotate_vector(
                        hit.normal
                    )
                    n = Vector3(local.y, local.z, -local.x)
                color = encode_normal(n)
            else:
                if hit.hit:
                    var facing = max(-direction.dot(hit.normal), 0)
                    color = _shade(
                        cityscapes_color(hit.tag), Float32(0.2) + 0.8 * facing
                    )
                else:
                    color = cityscapes_color(miss)
            out.set_pixel(
                x, y, _shade(color, ray.weight) if ray.weight < 1 else color
            )
    return out^


def optical_flow[
    T: RayScene
](
    mut scene: T,
    camera: CarlaTransform,
    previous_camera: CarlaTransform,
    intrinsics: CameraIntrinsics,
    tick: Duration,
) raises -> List[Float32]:
    """Cast one optical flow image.

    Args:
        scene: What the rays meet.
        camera: Where the camera is now.
        previous_camera: Where it was at the last frame.
        intrinsics: Its image size and focal length.
        tick: The time since the last frame.

    Returns:
        Two numbers a pixel, row by row from the top: the move across and
        down since the last frame, in normalized device units. A miss, or
        a point behind the last frame's camera, has no move.

    Raises:
        Error: If the scene cannot be tested.
    """
    var out = List[Float32]()
    var dt = Float32(tick.to(SECOND))
    var w = Float32(intrinsics.width)
    var h = Float32(intrinsics.height)
    for y in range(intrinsics.height):  # pragma: no branch
        for x in range(intrinsics.width):  # pragma: no branch
            var u = Float32(x) + 0.5
            var v = Float32(y) + 0.5
            var hit = scene.cast_ray(
                camera.location, intrinsics.ray(camera, u, v), DEPTH_FAR
            )
            var fx = Float32(0)
            var fy = Float32(0)
            if hit.hit:
                var before = intrinsics.project(
                    previous_camera, hit.point - hit.point_velocity * dt
                )
                if before.z > 0:
                    fx = (u - before.x) / w * 2
                    fy = (v - before.y) / h * 2
            out.append(fx)
            out.append(fy)
    return out^


# --- the event camera ---------------------------------------------------------


struct DVSConfig(ImplicitlyCopyable):
    """An event camera's settings, CARLA's `dvs::Config`."""

    # The contrast thresholds of a rise and of a fall.
    var positive_threshold: Float32
    var negative_threshold: Float32
    var sigma_positive_threshold: Float32
    var sigma_negative_threshold: Float32
    var refractory_period_ns: Int
    var use_log: Bool
    var log_eps: Float32

    def __init__(out self):
        """Create the settings of `sensor.camera.dvs`."""
        self.positive_threshold = 0.3
        self.negative_threshold = 0.3
        self.sigma_positive_threshold = 0
        self.sigma_negative_threshold = 0
        self.refractory_period_ns = 0
        self.use_log = True
        self.log_eps = 0.001

    def validate(self) raises:
        """Reject nonfinite physical settings and invalid domains.

        Raises:
            Error: If a physical setting is nonfinite or outside its domain.
        """
        validate_sensor_positive(
            self.positive_threshold, "An event camera's thresholds"
        )
        validate_sensor_positive(
            self.negative_threshold, "An event camera's thresholds"
        )
        validate_sensor_nonnegative(
            self.sigma_positive_threshold, "sigma_positive_threshold"
        )
        validate_sensor_nonnegative(
            self.sigma_negative_threshold, "sigma_negative_threshold"
        )
        validate_sensor_positive(self.log_eps, "log_eps")
        if self.refractory_period_ns < 0:
            raise Error("An event camera refractory period cannot be negative")

    @staticmethod
    def from_attributes(
        attributes: List[ActorAttributeValue],
    ) raises -> DVSConfig:
        """Read the settings from an actor's attributes, `ADVSCamera::Set`.

        Args:
            attributes: The actor's attributes.

        Returns:
            The settings. A missing threshold is 0.5, CARLA's fallback.

        Raises:
            Error: If a physical setting is nonfinite or outside its domain.
        """
        var c = DVSConfig()
        c.positive_threshold = attribute_float(
            attributes, "positive_threshold", 0.5
        )
        c.negative_threshold = attribute_float(
            attributes, "negative_threshold", 0.5
        )
        c.sigma_positive_threshold = attribute_float(
            attributes, "sigma_positive_threshold", 0
        )
        c.sigma_negative_threshold = attribute_float(
            attributes, "sigma_negative_threshold", 0
        )
        c.refractory_period_ns = attribute_int(
            attributes, "refractory_period_ns", 0
        )
        c.use_log = attribute_bool(attributes, "use_log", True)
        c.log_eps = attribute_float(attributes, "log_eps", 0.001)
        c.validate()
        return c


@fieldwise_init
struct DVSEvent(Equatable, ImplicitlyCopyable, Writable):
    """One brightness change, CARLA's `DVSEvent`."""

    var x: Int
    var y: Int
    # In nanoseconds of simulation time.
    var t: Int
    # True for a rise.
    var pol: Bool

    def write_to(self, mut writer: Some[Writer]):
        """Write the event as CARLA's Python API prints it.

        Args:
            writer: The destination.
        """
        writer.write("Event(x=", self.x, ", y=", self.y, ", t=", self.t)
        writer.write(", pol=", self.pol, ")")


def gray(color: Color) -> Float32:
    """Return a pixel's gray level, `FColorToGrayScaleFloat`.

    Args:
        color: The pixel.

    Returns:
        0.2989 R + 0.587 G + 0.114 B, from 0 to 255.
    """
    return Float32(
        0.2989 * Float64(color.r)
        + 0.587 * Float64(color.g)
        + 0.114 * Float64(color.b)
    )


def _nanoseconds(seconds: Float64) -> Int:
    return Int(seconds * 1e9)


# The most nanoseconds an event time can have: 2**63 - 4096. A stored event
# time goes to seconds and back, which can add up to about 3000 ns, and the
# result must still fit in an `Int`. That is about 292 years.
comptime _MAX_EVENT_NANOSECONDS = Float64(9223372036854771712)


struct DVSCamera(Copyable, Movable):
    """An event camera's memory between frames, `ADVSCamera`."""

    var config: DVSConfig
    var rng: SensorRandom
    var width: Int
    var height: Int
    var last_image: List[Float32]
    var prev_image: List[Float32]
    var ref_values: List[Float32]
    # In seconds; zero for a pixel with no event yet.
    var last_event_timestamp: List[Float64]
    # In nanoseconds.
    var current_time: Int

    def __init__(
        out self, config: DVSConfig, width: Int, height: Int, seed: Int
    ) raises:
        """Create an event camera with no frame yet.

        Args:
            config: Its settings.
            width: Pixels across. It must be positive.
            height: Pixels down. It must be positive.
            seed: The seed of the threshold noise.

        Raises:
            Error: If a size is not positive or the configuration is invalid.
                CARLA loops forever on a threshold of zero.
        """
        if width <= 0 or height <= 0:
            raise Error("An event camera needs a positive size")
        config.validate()
        self.config = config
        self.rng = SensorRandom(seed)
        self.width = width
        self.height = height
        self.last_image = List[Float32]()
        self.prev_image = List[Float32]()
        self.ref_values = List[Float32]()
        self.last_event_timestamp = List[Float64]()
        self.current_time = 0

    def simulate(
        mut self, image: Framebuffer, elapsed: Duration64
    ) raises -> List[DVSEvent]:
        """Compare a frame with the last one, `ADVSCamera::Simulation`.

        Args:
            image: The new RGB frame.
            elapsed: The simulation time of the frame, kept in Float64.

        Returns:
            The events since the last frame, by time. The first frame only
            sets the reference and gives none.

        Raises:
            Error: If the frame's size is not the camera's, or the time is
                not finite, is negative, or has too many nanoseconds for
                an `Int`.
        """
        if image.width != self.width or image.height != self.height:
            raise Error("An event camera's frame must be its size")
        var elapsed_seconds = elapsed.value
        if not (
            isfinite(elapsed_seconds)
            and elapsed_seconds >= 0
            and elapsed_seconds * 1e9 <= _MAX_EVENT_NANOSECONDS
        ):
            raise Error(
                "An event camera's time must be finite, nonnegative and at"
                " most 2**63 - 4096 nanoseconds"
            )
        self.last_image = List[Float32]()
        for y in range(self.height):  # pragma: no branch
            for x in range(self.width):  # pragma: no branch
                var g = gray(image.get_pixel(x, y))
                if self.config.use_log:
                    g = Float32(
                        log(Float64(self.config.log_eps) + Float64(g) / 255.0)
                    )
                self.last_image.append(g)
        var events = List[DVSEvent]()
        if len(self.prev_image) == 0:
            self.ref_values = self.last_image.copy()
            self.prev_image = self.last_image.copy()
            self.last_event_timestamp = List[Float64](
                length=len(self.last_image), fill=0
            )
            self.current_time = _nanoseconds(elapsed_seconds)
            return events^
        var delta_ns = Float32(
            _nanoseconds(elapsed_seconds) - self.current_time
        )
        for y in range(self.height):  # pragma: no branch
            for x in range(self.width):  # pragma: no branch
                var i = self.width * y + x
                var itdt = self.last_image[i]
                var it = self.prev_image[i]
                if not (abs(it - itdt) > 1e-6):
                    continue
                var rise = itdt >= it
                var pol = Float32(1) if rise else Float32(-1)
                var c = (
                    self.config.positive_threshold if rise else self.config.negative_threshold
                )
                var sigma = (
                    self.config.sigma_positive_threshold if rise else self.config.sigma_negative_threshold
                )
                if sigma > 0:
                    c += self.rng.normal(0, sigma)
                    c = max(Float32(0.01), c)
                var cross = self.ref_values[i]
                while True:
                    cross += pol * c
                    var inside = (rise and cross > it and cross <= itdt) or (
                        not rise and cross < it and cross >= itdt
                    )
                    if not inside:
                        break
                    var edt = Int((cross - it) * delta_ns / (itdt - it))
                    var t = self.current_time + edt
                    var last = _nanoseconds(self.last_event_timestamp[i])
                    if t >= last:
                        if (
                            self.last_event_timestamp[i] == 0
                            or t - last >= self.config.refractory_period_ns
                        ):
                            events.append(DVSEvent(x, y, t, rise))
                            self.last_event_timestamp[i] = Float64(t) / 1e9
                        self.ref_values[i] = cross
        self.current_time = _nanoseconds(elapsed_seconds)
        self.prev_image = self.last_image.copy()
        return _by_time(events^)


def _by_time(var events: List[DVSEvent]) -> List[DVSEvent]:
    # Pixel-major runs interleave in time. Merge them stably in O(n log n).
    var count = len(events)
    var scratch = events.copy()
    var width = 1
    while width < count:
        var start = 0
        while start < count:
            var middle = min(start + width, count)
            var end = min(start + 2 * width, count)
            var left = start
            var right = middle
            # start < count and width >= 1 imply end > start.
            for dest in range(start, end):  # pragma: no branch
                if left < middle and (
                    right >= end or events[left].t <= events[right].t
                ):
                    scratch[dest] = events[left]
                    left += 1
                else:
                    scratch[dest] = events[right]
                    right += 1
            start = end
        var previous = events^
        events = scratch^
        scratch = previous^
        width *= 2
    return events^
