# CARLA geodesy and V2X quantities (#333)

Checked quantity boundaries retain CARLA's stored units and precision.
This review covers all 47 geodesy and V2X rows assigned to
`geo.mojo` and `v2x.mojo` in the original inventory. The GNSS configuration
review is in [CARLA configuration quantities](carla-configuration-quantities-333.md).
The source baseline is ThreeMojo `2d81e959`.

## Boundary contract

Geographic records retain raw Float64 degree and meter fields. Their
default dimensional constructors take `Angle64` and `Length64`.
`from_degrees_meters`, `Ellipsoid.from_meters`, and
`OffsetTransform.from_meters_radians` are explicit raw adapters. They
check values before returning a record. They store raw inputs directly.
They do not route raw degree values through radians and back.

The typed angle views use Float64 radian arithmetic. They do not use the
Float32 scale in `DEGREE`. A conversion between degrees and radians can
round by Float64 arithmetic. It is not a bit-exact degree round trip.

The existing `latitude_angle` and `longitude_angle` methods remain
Float32 views and now reject invalid values. The Float64 views have a
`64` suffix. CARLA frame vectors remain Float32 meter coordinates.

Latitude must be between -90 and 90 degrees. Longitude can be any finite
value because projection code wraps a longitude difference. Altitudes and
offsets can have either sign. An axis must be positive.

An inverse flattening must exceed one; positive infinity denotes a sphere. A
semi-minor axis must not exceed its semi-major axis. A transverse
Mercator scale must be positive. These checks do not certify a projection
formula at a singular input or replace its existing numerical contract.

Projection arithmetic and GNSS output use private raw construction.
This preserves existing results, including a noisy coordinate outside a
geographic domain. The raw parser fields and serialized GNSS doubles do
not change. A checked typed view refuses invalid raw state.

V2X link distances and antenna heights use `Length64` at the public
scalar input boundary. Unit-named raw adapters apply the same checks.
The private CARLA scalar formulas retain their arithmetic order. A
public adapter rejects a nonfinite result, including overflow or a
singular two-ray configuration. The private channel hot loop keeps its
existing behavior.

CAM noise fields remain Float32. Angle setters explicitly convert to
CARLA degrees. Angular velocity stays radians per second. Paired setters
check every input before they change a field. A deviation is nonnegative;
a bias can have either sign. Acceleration component setters use three
`Acceleration` values and update the raw vector together.

The radio's raw configuration frequency remains Float32 GHz.
`PropagationParams.carrier_frequency` and its setter use Float32 hertz
and reject conversion overflow or a positive value that underflows to
zero GHz. `PathLossModel.carrier_frequency` returns the existing Float64
hertz state as `Frequency64`. CAM constructor intervals use Float32
`Duration`; the existing internal Float32 timestamp rounding is unchanged.

## Reviewed inventory rows

| Symbol | Meaning and disposition |
|---|---|
| `GeoLocation.latitude_degrees` | Raw Float64 degrees. Checked `latitude_angle64`; the existing `latitude_angle` is an explicit Float32 view. |
| `GeoLocation.longitude_degrees` | Raw Float64 degrees. Checked `longitude_angle64`; the existing `longitude_angle` is an explicit Float32 view. |
| `GeoLocation.altitude_meters` | Raw Float64 meters. Checked `altitude_length` returns `Length64`. |
| `Ellipsoid.a_meters` | Raw Float64 meters. Checked `semi_major_axis` returns `Length64`. |
| `Ellipsoid.b_meters ->` | Explicit raw meter compatibility output. Checked `semi_minor_axis` returns `Length64`. |
| `Ellipsoid.from_b(b_meters)` | Default setter now takes `Length64`. `from_b_meters` is the checked raw adapter. |
| `OffsetTransform.offset_x_meters` | Raw Float64 meters. Checked `x_offset` returns `Length64`. |
| `OffsetTransform.offset_y_meters` | Raw Float64 meters. Checked `y_offset` returns `Length64`. |
| `OffsetTransform.offset_z_meters` | Raw Float64 meters. Checked `z_offset` returns `Length64`. |
| `OffsetTransform.offset_cos_h` | Cosine of the negative heading. Dimensionless computed state; stays raw. |
| `OffsetTransform.offset_sin_h` | Sine of the negative heading. Dimensionless computed state; stays raw. |
| `OffsetTransform.__init__(x_meters)` | Typed `Length64` input. Explicit checked `from_meters_radians` adapter retains the raw units. |
| `OffsetTransform.__init__(y_meters)` | Typed `Length64` input. Explicit checked `from_meters_radians` adapter retains the raw units. |
| `OffsetTransform.__init__(z_meters)` | Typed `Length64` input. Explicit checked `from_meters_radians` adapter retains the raw units. |
| `OffsetTransform.__init__(heading_radians)` | Typed `Angle64` input. Explicit checked `from_meters_radians` adapter retains radian arithmetic. |
| `UtmZone.central_meridian_degrees ->` | Explicit raw degree compatibility output. `central_meridian_angle` checks the zone and returns `Angle64`. |
| `TransverseMercatorParams.lat_0_degrees` | Raw Float64 degrees. Typed constructor and checked `lat_0_angle` view use `Angle64`. |
| `TransverseMercatorParams.lon_0_degrees` | Raw Float64 degrees. Typed constructor and checked `lon_0_angle` view use `Angle64`. |
| `TransverseMercatorParams.x_0_meters` | Raw Float64 meters. Typed constructor and checked `x_0_length` view use `Length64`. |
| `TransverseMercatorParams.y_0_meters` | Raw Float64 meters. Typed constructor and checked `y_0_length` view use `Length64`. |
| `LambertConformalConicParams.lat_0_degrees` | Raw Float64 degrees. Typed constructor and checked `lat_0_angle` view use `Angle64`. |
| `LambertConformalConicParams.lat_1_degrees` | Raw Float64 degrees. Typed constructor and checked `lat_1_angle` view use `Angle64`. |
| `LambertConformalConicParams.lat_2_degrees` | Raw Float64 degrees. Typed constructor and checked `lat_2_angle` view use `Angle64`. |
| `LambertConformalConicParams.lon_0_degrees` | Raw Float64 degrees. Typed constructor and checked `lon_0_angle` view use `Angle64`. |
| `LambertConformalConicParams.x_0_meters` | Raw Float64 meters. Typed constructor and checked `x_0_length` view use `Length64`. |
| `LambertConformalConicParams.y_0_meters` | Raw Float64 meters. Typed constructor and checked `y_0_length` view use `Length64`. |
| `PathLossModel.wavelength` | Raw Float64 meter arithmetic state. Checked `wavelength_length` returns `Length64`. |
| `PathLossModel.winner(distance)` | Default input is `Length64`. Explicit checked `winner_meters` adapter keeps Float64 meter arithmetic. |
| `PathLossModel.two_ray(distance)` | Default input is `Length64`. Explicit checked `two_ray_meters` adapter keeps Float64 meter arithmetic. |
| `PathLossModel.two_ray_simple(distance)` | Default input is `Length64`. Explicit checked `two_ray_simple_meters` adapter keeps Float64 meter arithmetic. |
| `PathLossModel.loss(distance)` | Default input is `Length64`. Explicit checked `loss_meters` adapter keeps Float64 meter arithmetic. |
| `speed_value(speed)` | Signed Float32 meter-per-second input. Default function takes `Velocity`. Explicit `speed_value_meters_per_second` adapter retains the ETSI sentinel and saturation rules. |
| `round_half_away(x)` | Generic rounding input. Dimensionless numeric helper; stays raw. |
| `CamNoise.latitude_stddev` | Raw CARLA Float32 storage. Checked `latitude_stddev_angle` view and transactional `set_latitude_noise` use `Angle`. |
| `CamNoise.longitude_stddev` | Raw CARLA Float32 storage. Checked `longitude_stddev_angle` view and transactional `set_longitude_noise` use `Angle`. |
| `CamNoise.latitude_bias` | Raw CARLA Float32 storage. Checked `latitude_bias_angle` view and transactional `set_latitude_noise` use `Angle`. |
| `CamNoise.longitude_bias` | Raw CARLA Float32 storage. Checked `longitude_bias_angle` view and transactional `set_longitude_noise` use `Angle`. |
| `CamNoise.altitude_stddev` | Raw CARLA Float32 storage. Checked `altitude_stddev_length` view and transactional `set_altitude_noise` use `Length`. |
| `CamNoise.altitude_bias` | Raw CARLA Float32 storage. Checked `altitude_bias_length` view and transactional `set_altitude_noise` use `Length`. |
| `CamNoise.velocity_stddev` | Raw Float32 meters per second. Checked `velocity_stddev_velocity` and `set_velocity_noise` use `Velocity`. |
| `CamNoise.yaw_rate_stddev` | Raw CARLA Float32 storage. Checked `yaw_rate_stddev_angular_velocity` view and transactional `set_yaw_rate_noise` use `AngularVelocity`. |
| `CamNoise.yaw_rate_bias` | Raw CARLA Float32 storage. Checked `yaw_rate_bias_angular_velocity` view and transactional `set_yaw_rate_noise` use `AngularVelocity`. |
| `CaService.last_cam_timestamp` | Internal time or motion history. Retains CARLA arithmetic precision. Callers configure typed `Duration` constructor intervals and use the existing typed tick. |
| `CaService.last_low_cam_timestamp` | Internal time or motion history. Retains CARLA arithmetic precision. Callers configure typed `Duration` constructor intervals and use the existing typed tick. |
| `CaService.elapsed` | Internal time or motion history. Retains CARLA arithmetic precision. Callers configure typed `Duration` constructor intervals and use the existing typed tick. |
| `CaService.vehicle_speed` | Internal time or motion history. Retains CARLA arithmetic precision. Callers configure typed `Duration` constructor intervals and use the existing typed tick. |
| `CaService.last_cam_speed` | Internal time or motion history. Retains CARLA arithmetic precision. Callers configure typed `Duration` constructor intervals and use the existing typed tick. |

## Symbols omitted by the name filter

| Symbol or family | Meaning and disposition |
|---|---|
| `GeoLocation`, `Ellipsoid`, projection fieldwise constructors | Replaced by typed constructors and explicit checked raw adapters. No generic raw overload remains. |
| `Ellipsoid.f_inv`, `f`, `e2`, `ep2` | Flattening and eccentricity ratios. Dimensionless; retain their CARLA values. |
| `TransverseMercatorParams.k` | Dimensionless scale. Checked positive in the typed and explicit raw construction paths. |
| `PropagationParams.frequency_ghz`, `PathLossModel.frequency` | Frequency. Checked Float32 configuration and Float64 channel views preserve the different storage semantics. |
| `PathLossModel.two_ray`, `two_ray_simple`, `loss` antenna heights | Float64 meter inputs now take `Length64`; named raw adapters remain. |
| `PathLossModel.vehicle_loss(d1, d2, h)` | Two positive distances and a signed edge height now take `Length64`. |
| `path_state(reference_z)` | Float32 reference height now takes `Length`; `path_state_meters` is the checked raw adapter. |
| `CamNoise.heading_stddev`, `heading_bias` | Float32 degrees. Checked `Angle` views and a paired setter. |
| `CamNoise.acceleration_stddev` | Raw Float32 meter-per-second-squared vector. Checked three-quantity view and transactional component setter. |
| `CaService.gen_cam_min`, `gen_cam_max` constructor inputs | Float32 seconds now take `Duration`. Stored intervals and adaptive `gen_cam` remain raw internal state. |
| Propagation power, sensitivity, gain, fading, loss, and received power | CARLA logarithmic dBm, dBi, and dB representations. Not linear SI power quantities. Retain named raw compatibility values. |
| CAM integer coordinates, speed, acceleration, yaw rate, time, and confidence fields | ETSI wire codes with scale, saturation, and unavailable sentinels. Retain the integer format. |
| Generic rounding, scenario identifiers, counts, flags, normalized headings | Dimensionless values or identifiers. No physical unit wrapper is added. |
| Private projection, channel, and CAM arithmetic | Internal CARLA SI scalar state. Retains its original operation order and precision. |

## Verification

`tests/test_carla_geo_quantity.mojo` checks large and tiny Float64 meter
values, low-bit geographic coordinates, signed zero, and exact serialized
GNSS bytes. It also checks parsed low bits, explicit unit conversion,
typed views, and Float32 component bits. Refusal controls cover invalid raw
mutations, domain rejection, conversion overflow, and transactional noise
setters.

Existing CARLA geometry and sensor tests keep their numerical expectations. Two
comparison-only invalid ellipsoid and scale inputs become distinct valid
values because the new constructors reject the original invalid inputs.

Thirty-six `carla_geo_*` negative fixtures cover raw input, the wrong
dimension, and the wrong precision at twelve boundaries. The compiler
must first build a valid control, then report the expected error inside
each fixture. A dependency error does not establish type safety.

The integrated validation record must provide the pinned compiler,
formatter, diagnostics, runtime, and coverage results. This source review
does not claim a full aggregate pass.
