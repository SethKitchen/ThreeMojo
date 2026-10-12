# CARLA configuration quantity review (#333)

The four configuration modules retain their CARLA storage and use checked
quantity boundaries for dimensional input. This review covers all 29 rows
for these modules in the original name-filter inventory. It also records
public dimensional symbols that the filter omitted.

The source baseline is ThreeMojo `2d81e959`. Float32 configuration values
use `Angle`, `Length`, and `Frequency`. A Float64 quantity cannot enter a
Float32 adapter implicitly. No record field changes its storage type.

## Boundary contract

- `WeatherParameters` takes two angles and one length. Its named
  `from_carla` adapter takes CARLA's degree and meter fields. Both reject
  nonfinite values. Finite clamp inputs and the -1 preset sentinel remain
  valid. `validate` checks a record after direct field edits.
- `RgbCameraSettings` has checked typed views and setters for shutter
  speed, both exposure adaptation rates, and depth-blur distance. Shutter
  speed must be positive. The other three values must be nonnegative.
  The attribute reader applies the same raw-value domain checks.
- `WideAngleLens` has a checked fade-angle view and setter. It accepts
  finite, nonnegative angles. The setter rejects a degree conversion that
  overflows Float32 before it changes the raw field.
- `GnssDescription` has a typed full constructor, six checked views, and
  three paired noise setters. Standard deviations must be nonnegative.
  Biases can have either sign. Every value must be finite after conversion
  to CARLA's Float32 degrees or meters. Each paired setter checks both
  inputs before it writes either field.
- The public Kannala-Brandt polynomial and derivative take `Angle`.
  Their private raw helpers keep the existing radian arithmetic and order.
- `DVSConfig.refractory_duration` returns `Duration64`. Its setter uses
  Float64 seconds times 1e9 and truncates toward zero to integer
  nanoseconds. It accepts zero through 9.2e9 seconds, the existing event
  clock limit. No Float32 conversion occurs. The raw `Int` count remains
  exact. Its Float64 view can round a large count; it does not promise an
  exact integer round trip beyond Float64 precision.

The compatibility fields remain writable because CARLA records and
attribute readers use those units. Application code can use the checked
quantity methods. A view rejects invalid raw state instead of treating
that state as a valid physical quantity.

## Reviewed inventory rows

The symbols below are the exact entries in the original inventory.

| File | Symbol | Reviewed meaning and disposition |
|---|---|---|
| `camera_render.mojo` | `RgbCameraSettings.shutter_speed` | Reciprocal seconds. Raw compatibility field; `shutter_frequency` and `set_shutter_speed` use `Frequency`. |
| `camera_render.mojo` | `RgbCameraSettings.exposure_speed_up` | Exposure stops per second. A stop is dimensionless; typed `Frequency` view and setter. |
| `camera_render.mojo` | `RgbCameraSettings.exposure_speed_down` | Exposure stops per second. Typed `Frequency` view and setter. |
| `camera_render.mojo` | `RgbCameraSettings.motion_blur_max_distortion` | Percentage of screen width. Dimensionless; stays raw. |
| `camera_render.mojo` | `RgbCameraSettings.motion_blur_min_object_screen_size` | Percentage of screen width. Dimensionless; stays raw. |
| `camera_render.mojo` | `RgbCameraSettings.chromatic_aberration_offset` | Normalized image radius. Dimensionless; stays raw. |
| `camera_render.mojo` | `RgbCameraSettings.blur_radius` | Image pixels at a reference resolution. An image coordinate, not a physical length; stays raw. |
| `camera_render.mojo` | `metered_ev100 ->` | A logarithmic exposure value. Dimensionless; stays raw. |
| `camera_render.mojo` | `camera_exposure(metered)` | Renderer-scale luminance. It is converted to EV100 inside the helper; stays raw. |
| `cameras.mojo` | `compute_angle(distance)` | Radius divided by focal length. Dimensionless; stays raw. |
| `cameras.mojo` | `compute_distance ->` | Focal length in image pixels. Not a meter length; stays raw. |
| `cameras.mojo` | `WideAngleLens.focal_length` | Focal length in image pixels. Not a meter length; stays raw. |
| `cameras.mojo` | `WideAngleLens.fov_fade_size` | Degrees. Raw compatibility field with `fade_angle` and `set_fov_fade_size`. |
| `cameras.mojo` | `WideAngleLens.pixel_ray(x)` | Image column coordinate in pixels. Stays raw. |
| `cameras.mojo` | `WideAngleLens.pixel_ray(y)` | Image row coordinate in pixels. Stays raw. |
| `cameras.mojo` | `DVSConfig.positive_threshold` | Intensity or log-intensity threshold. Dimensionless; stays raw. |
| `cameras.mojo` | `DVSConfig.negative_threshold` | Intensity or log-intensity threshold. Dimensionless; stays raw. |
| `cameras.mojo` | `DVSConfig.sigma_positive_threshold` | Standard deviation in the same intensity scale. Dimensionless; stays raw. |
| `cameras.mojo` | `DVSConfig.sigma_negative_threshold` | Standard deviation in the same intensity scale. Dimensionless; stays raw. |
| `cameras.mojo` | `DVSCamera.simulate(elapsed_seconds)` | Already takes checked `Duration64`; the scan predates that migration. |
| `gnss.mojo` | `GnssDescription.latitude_stddev` | Float32 degrees. Typed constructor, `latitude_stddev_angle`, and paired setter. |
| `gnss.mojo` | `GnssDescription.latitude_bias` | Float32 degrees. Typed constructor, `latitude_bias_angle`, and paired setter. |
| `gnss.mojo` | `GnssDescription.longitude_stddev` | Float32 degrees. Typed constructor, `longitude_stddev_angle`, and paired setter. |
| `gnss.mojo` | `GnssDescription.longitude_bias` | Float32 degrees. Typed constructor, `longitude_bias_angle`, and paired setter. |
| `gnss.mojo` | `GnssDescription.altitude_stddev` | Float32 meters. Typed constructor, `altitude_stddev_length`, and paired setter. |
| `gnss.mojo` | `GnssDescription.altitude_bias` | Float32 meters. Typed constructor, `altitude_bias_length`, and paired setter. |
| `weather.mojo` | `WeatherParameters.__init__(sun_azimuth_degrees)` | Replaced by `sun_azimuth: Angle`; raw degrees move to `from_carla`. |
| `weather.mojo` | `WeatherParameters.__init__(sun_altitude_degrees)` | Replaced by `sun_altitude: Angle`; raw degrees move to `from_carla`. |
| `weather.mojo` | `WeatherParameters.__init__(fog_distance_meters)` | Replaced by `fog_distance: Length`; raw meters move to `from_carla`. |

## Symbols omitted by the name filter

| Symbol or family | Reviewed meaning and disposition |
|---|---|
| `RgbCameraSettings.blur_amount` | Raw depth-blur distance in kilometers. `depth_blur_distance` and `set_depth_blur_distance` use `Length`. The getter rejects a meter conversion that overflows Float32. |
| `kannala_brandt_polynomial(theta)` | Public radian input becomes `Angle`. The normalized radial output stays raw. |
| `kannala_brandt_derivative(theta)` | Public radian input becomes `Angle`. The numeric derivative of the radian-based model stays raw. |
| `DVSConfig.refractory_period_ns` | Exact CARLA integer nanoseconds. Checked `Duration64` view and setter retain the field. |
| `DVSEvent.t` | Serialized integer event nanoseconds. Retained without a lossy field conversion. |
| `DVSCamera.current_time`, `last_event_timestamp` | Internal event-clock state in nanoseconds and Float64 seconds. Public simulation input is `Duration64`. |
| `RgbCameraSettings.fov`, `WideAngleLens.fov`, `longitude_offset` | Already `Angle`. |
| `RgbCameraSettings.focal_distance`, `temp` | Already `Length` and `Temperature`. The existing attribute scale is unchanged. |
| `WeatherParameters.sun_azimuth_angle`, `sun_altitude_angle`, `fog_distance` | Already typed fields. The full constructor now matches them. |
| `optical_flow(delta)` | Already `Duration`. |
| Remaining weather scalar fields | Percentages or empirical scattering/falloff factors. Their existing clamp semantics remain unchanged. |
| Remaining RGB and lens scalar controls | Exposure values, ISO rating, f-numbers, tone-curve coefficients, intensity factors, and normalized image factors. No physical-length type is added. |
| `metered_ev100(luminance)`, exposure helpers, `set_thresholds` | Internal light-scale arithmetic. The module declares its physical luminance scale separately as `NITS_PER_UNIT`. |
| `PixelRay.weight`, direction components, normal encoding, grayscale, DVS reference intensities | Weights, unit-vector components, colors, or intensity values. No dimensional scalar boundary is introduced. |
| Integer image dimensions, pixel coordinates, seeds, enum values, blade counts | Counts or identifiers. They are not physical distances or durations. |

## Source checks and unchanged behavior

The module sources identify the CARLA files used by the port. The reviewed
[CARLA camera setter source](https://raw.githubusercontent.com/carla-simulator/carla/0.9.16/Unreal/CarlaUE4/Plugins/Carla/Source/Carla/Sensor/SceneCaptureSensor.cpp)
maps depth blur to `DepthOfFieldDepthBlurAmount`.
The [engine field reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/Engine/FPostProcessSettings?application_version=5.5)
defines that field in kilometers and its radius in pixels.
The [engine exposure reference](https://dev.epicgames.com/documentation/en-us/unreal-engine/auto-exposure-eye-adaptation?application_version=4.27)
defines adaptation rates in stops per second.
These source checks prevent the word "amount" from hiding a length and the
word "radius" from turning image pixels into meters.

The [CARLA sensor reference](https://carla.readthedocs.io/en/0.9.16/ref_sensors/)
defines `focal_distance` in centimeters. The existing port stores an
attribute of 1000 as `Length(1000, METER)`, and its tests require that
behavior. This boundary-only change does not alter that pre-existing
scale discrepancy or the default render result. A scale correction needs
its own behavior review.

Weather presets, clamping, GNSS noise order, serialized fields, and the
Kannala-Brandt arithmetic retain their existing values and order. Negative
RGB adaptation rates and depth-blur distances are now refused at the
attribute boundary. This is an intentional domain check.

## Validation

`tests/test_carla_configuration_quantities.mojo` covers typed construction,
unit conversions, raw storage, nonfinite values, negative domains,
conversion overflow, transactional setters, weather sentinels and clamps,
Float32 low bits, signed zero, and Float64 refractory time.

Thirty `carla_config_*` compile-fail fixtures cover raw values, wrong
dimensions, and wrong precision at ten configuration boundaries. The
existing weather and camera-model tests use the named raw weather adapter
and typed angles respectively.

Compiler, runtime, diagnostics, and coverage results must be recorded by
the integrated validation run. This source review does not itself claim a
passing aggregate check.
