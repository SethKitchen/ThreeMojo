<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# CARLA quantity boundary inventory (#333)

The public scalar inventory is reviewed per declaration. It replaces the
422-row name-filter scan. The review starts from `main` `2d81e959` and
includes the issue #333 working source on October 12, 2026. It records
what each value means, its exact typed entry or view, its raw adapter,
and why raw storage remains where it does.

The [TSV inventory](carla-quantity-inventory-333.tsv) is the per-symbol
record. An inventory pass is not a compiler, runtime, coverage, or
numerical-certificate pass. Those checks must qualify the final source.

## Review coverage

The review reads declarations in all 125 Mojo modules under
`extensions/carla/`. The current inventory has 2,219 rows from 80 modules:
1,146 parameters, 671 fields, and 402 returns. It includes:

- Every public `Float32` and `Float64` field, parameter, and return.
- Floating scalars inside public lists, dictionaries, tuples, and SIMD types.
- Already-typed quantity fields, parameters, and returns, including physics,
  temperature, and photometry types.
- Integer event clocks, sensor point rates, recorder dates, and CAM wire
  records. Their neighboring count and confidence fields are classified too.

No name filter selects these floating-point rows. In particular, `a`, `c`,
`d`, `b`, `max`, `value`, `input`, `size`, `rise`, `blur_amount`, and tuple
results are reviewed. Public fieldwise constructors are represented by their
fields. Authored overloads have separate rows and source-line references.

Private types, private functions, function-local variables, and constructors
that require the private `_RawSI` capability are implementation details.
The inventory does not count them as application entry points. Integer IDs,
ordinary counts, Boolean flags, strings, constants, and opaque composite
objects are outside the scalar-quantity list. A re-export retains the
contract at its defining module; this scan does not duplicate declarations
outside `extensions/carla/`.

| Classification | Rows | Disposition |
|---|---:|---|
| Typed boundary | 1,047 | The signature fixes dimension and precision. |
| Explicit raw adapter | 366 | A named unit or source-format boundary. |
| Source compatibility field | 143 | Raw layout with an identified typed entry or view. |
| Wire field | 85 | Retain the encoded width, unit, scale, and sentinel. |
| Internal state | 64 | A named simulation, controller, or rendering cache. |
| Packed geometry stream | 2 | The `cuboid` position and texture-coordinate buffers. |
| Dimensionless control | 370 | A ratio, normalized coordinate, gain, or reference-scale value. |
| Generic numeric utility | 77 | Its dimension depends on its caller or model convention. |
| Source code or logarithmic value | 63 | A tagged source value, ETSI code, or radio log representation. |
| Unimplemented source setting | 2 | CARLA sleep controls are stored but not simulated. |

Each TSV row supplies a source file and declaration line. Its classification
is a reviewed decision, not a classification inferred from the filename.
The rationale includes the source contract where the declaration provides
one. A raw wire field or mutable quantity field is not itself a certificate
that its value is finite or in range.

## Existing merged boundaries

These are retained work on `main`, not new issue #333 changes:

- `units.si` provides the Float64 quantity family. `Length64`, `Duration64`,
  and the other 64-bit quantities cannot implicitly mix with Float32 quantities.
- `Timestamp` takes `Duration64`. `Timestamp.from_seconds` is the explicit
  raw adapter. `elapsed`, `delta`, and `platform` are checked Float64 views.
- The three #696 entries already use quantities:
  `DVSCamera.simulate` and `LaneInvasionSensor.tick` take `Duration64`;
  `World.get_traffic_lights_from_waypoint` takes `Length64`.
- `LaneInvasionEvent` and `SensorMeasurement` retain raw timestamp fields
  with checked `elapsed` views. Their storage precision does not change.
- `EpisodeSettings.fixed_delta_seconds` already uses `Duration`.
  `EpisodeSettings.check` already refuses infinity in this baseline.

World timing remains Float64 seconds in stored state. A snapshot exposes
that state through `Timestamp`. The DVS camera retains an integer nanosecond
clock and Float64 per-pixel timestamps in seconds. The public tick is typed.
The integer and floating event clocks must not be confused.

## Map and polynomial boundaries

The default map, Road, MapBuilder, geometry, and road-record scalar entry
points use quantities. Meter station and distance values retain Float64
precision. The TSV names each exact entry and adapter. The main patterns are:

- Map and Road queries use `Length64`; explicit `_meters` adapters retain
  source callers. A squared-distance result uses `Area` or `Area64` at the
  precision of its source computation.
- MapBuilder's typed methods use `_si` source adapters. Road and lane speed
  records use explicitly named `_opendrive` adapters when the input carries
  a source speed unit or keyword.
- Record constructors take quantities. `from_si`, `from_meters`, and
  `from_coefficients` name their raw source alternatives. The old raw
  constructor bodies require the private `_RawSI` capability.
- Raw record fields keep their storage. The corresponding `*_quantity`
  method checks the field before returning its quantity. A view rejects
  invalid raw mutation; it does not rewrite the stored value.
- `RoadInfoSpeed` takes `Velocity64` at default construction and retains
  explicit source-unit creation. Its `limit` view preserves the distinction
  between zero, absent, undefined, and unlimited speed.
- A `Signal.value` is sign-type-dependent. `Signal.speed_limit` is the
  checked speed interpretation. A non-speed sign value is not labeled m/s.

`CubicPolynomial` now stores local coefficients and evaluates at `x - s`.
The station-polynomial views assign `a` length, `b` slope, `c` inverse length,
`d` inverse area, and `s` length. `DirectedPoint.pitch` is elevation slope,
whereas its tangent is an angle. These meanings are distinct.

A normalized `paramPoly3` has a separate `NormalizedCubic` type. All four
coefficients are `Length64`, because its parameter `p` is dimensionless.
Its `evaluate` and `tangent` return `Length64`; they check finite `p` in
`[0, 1]`. `NormalizedCubic.from_meters` is the explicit raw coefficient
adapter. This avoids assigning station-polynomial dimensions to normalized
coefficients.

The default `param_poly3` and `with_param_poly3` select arc-length mode and
take `CubicPolynomial`. Their `_normalized` counterparts take
`NormalizedCubic`. MapBuilder has the same explicit split. The source
`*_from_coefficients` and MapBuilder `_si` adapters retain CARLA's tagged
mode and shared raw coefficient representation. Shared storage after that
choice does not erase the public type distinction. `RoadGeometry` keeps
its common polynomial storage private. `u_coefficients` and `v_coefficients`
return explicit source tuples; they do not expose a misleading station-typed
view of normalized coefficients.

The numerical correction is separate from adding quantity wrappers.
The [conditioned cubic review](conditioned-cubic-333.md) records the local
polynomial, its enclosure theorem, its consumers, and its limits.
The [typed successor record](typed-boundary-successor-333.md) records current
source admission. Historical source reconstruction establishes provenance;
it does not prove old and new cubic values are equal.

## Other typed application entries

These omissions from the old scan now have explicit boundaries:

| Family | Typed entry | Explicit raw route |
|---|---|---|
| Recorder frame time | `Recorder.write_frame`, `RecorderFrames.set_frame` with `Duration64` | `write_frame_seconds`, `set_frame_seconds` |
| Recorder time packet | `time_packet` with `Duration64` | `time_packet_seconds` |
| Sensor header | `sensor_header` with `Duration64` | `sensor_header_seconds` |
| Camera packet field of view | `image_data`, `optical_flow_data`, `dvs_data` with `Angle` | `image_data_carla`, `optical_flow_data_degrees`, `dvs_data_degrees` |
| Replay angle and walker speed | `lerp_angle` with `Angle64`; `set_walker_speed` with `Velocity` | `lerp_angle_degrees`, `set_walker_speed_centimeters_per_second` |
| Radar result | `RadarDetection` and `velocity_quantity` | `RadarDetection.from_si` |
| Pedestrian catalog speed | `PedestrianParameters` and `speeds_quantity` with `List[Velocity]` | `from_meters_per_second` |
| Render shape dimensions | Body/cabin helpers, wheel inset, stride, and `loft` | Unit-named `_si` helpers and `loft_meters` |
| Fog extinction | `fog_density_at` returns `InverseLength` | `fog_density_at_per_meter` |
| Mesh generation | Typed start/end station, lane-mark widths | Explicit `_si` methods |
| Controller/sign tick | `PID.run` and `TrafficSign.tick_timers` with `Duration` | `run_seconds`, `tick_timers_seconds` |
| TM geometry | Typed polygon, waypoint, extension, and side-offset results | `_meters` or `_square_meters` methods |
| TM target speed | Typed planning inputs and outputs | `_meters_per_second` methods |

`image_data` selects the source camera encoding explicitly: CARLA uses
raw degrees for a pinhole packet and raw radians for a wide-angle packet.
The raw `image_data_carla` adapter preserves that format choice.

`polygon_distance` returns an optional `Length64`: an empty polygon has no
finite separation. Its explicit meter adapter retains positive infinity.
`CollisionStage.negotiate_collision` returns an optional typed length for
its margin. An absent margin means no yield. Its explicit meter adapter
retains CARLA's positive-infinity no-yield sentinel. Infinity is not silently
certified as an ordinary finite distance.

`agents_misc.from_kmh` returns `Velocity64` from a Float64 input. The separate
`from_kmh_float32` names the old Float32 rounding path. Both check the input
and converted result. `kmh` remains an explicit unit-named output adapter
for the existing Float32 agent velocity.

## Exact integer epoch adapters

Absolute source dates stay integer counters. They do not become an elapsed
`Duration64` through a conversion that can lose integers above `2^53`.

- `Recorder.begin` and `Recorder.start` use the current date. Their
  `begin_unix_seconds` and `start_unix_seconds` adapters accept exact integer
  seconds since 1970-01-01 UTC. Nonnegative values retain signed i64 bits.
  The conventional `-1` sentinel selects now. Other negative values retain
  the pre-existing negative-means-now behavior.
- `SensorManager()` and the default `CaService` constructor use CAM epoch
  offset zero. Their `from_cam_epoch_milliseconds` factories accept exact
  signed integer milliseconds since 2004-01-01 UTC. Pre-epoch negative
  values remain supported. CAM encoding retains its existing modulo rule.
- `RecorderInfo.date`, each `generation_delta0` field, and the recorder's
  monotonic `start_ns` retain their source or internal integer storage.

`tests/test_carla_epoch_adapters.mojo` covers signed i64 wire round trips,
large odd values above `2^53`, both signed endpoints, recorder sentinels,
default constructors, CAM epoch storage and encoding, and unchanged typed
CAM interval and owner checks. Four `carla_epoch333_*` negative fixtures
require the named source route for an arbitrary integer epoch. The existing
CAM interval negative fixtures still test interval types, not an argument-count
error. These tests are added controls, not a claimed native pass.

## Retained raw values and their reasons

The TSV does not use a blanket exemption for publicly named traffic-manager
stage helpers. Their dimensional scalar entries and results have typed
wrappers and explicit raw adapters. The private stage kernels retain the
upstream arithmetic order.

Raw simulation state still includes wheel compression, force, angular speed,
torque, and mass; Ackermann state; navigation and traffic-manager clocks;
replay clocks; and render caches. These rows identify the typed control,
tick, or telemetry entry that owns them. `WheelState.lat_slip` is radians,
`spin` is radians per second, and `Navigation.yaw_walkers` is degrees.
They are not dimensionless controls.

Raw wire and source records retain their existing representation:

- Recorder physics uses centimeters, centimeters per second, degrees, rpm,
  and the source mechanical units. `from_control` converts from typed setup.
- `LogVector` stores locations, rotations, and generic vector records.
  Its scalar norm has the record's units; it is not always a length.
- CAM integers include scales, saturation, availability flags, and reserved
  values. They must remain codes rather than ordinary SI integers.
- Sensor point rates remain exact CARLA integer samples per second. The
  description checks the rate; a typed `Duration` converts it to a ray count.
- `SceneHit.distance` is a ray parameter measured in direction-vector lengths.
  Infinity means a miss. It is not unconditionally a distance in meters.
- `cuboid` appends packed vertex and texture-coordinate buffers in meters.
  Its normal buffer is dimensionless. These are mesh attribute streams.

The following controls are also distinct:

- Image pixel coordinates and blur radius are not world distances.
  Lens radius divided by focal length, NDC depth, pose blend, percentages,
  and normalized controller commands remain scalar controls.
- Mesh `vertex_width_resolution` is a transverse vertex count.
- RGB depth-blur `blur_amount` is kilometers and has a checked `Length` view.
  Exposure adaptation rates are stops per second and use `Frequency`.
- `camera_exposure` takes renderer-scale luminance and returns an exposure
  multiplier. EV100 results are logarithmic exposure values.
- Generic vector norms, rounding, random draws, curve evaluators, PID gains,
  and fixed-convention lens coefficients have no one physical dimension.
  PID gains are not asserted to be dimensionless across different loops.
- Radio power, gain, fading, and loss retain dBm, dBi, and dB conventions.
  They are not linear SI watts.
- The unused CARLA sleep controls retain opaque source semantics. This port
  does not put bodies to sleep; the inventory does not invent their units.

The [configuration review](carla-configuration-quantities-333.md) and
[geodesy/V2X review](carla-geodesy-quantities-333.md) give the detailed domain,
conversion, precision, and source-unit contracts. They also record remaining
behavior limits, including the pre-existing focal-distance scale discrepancy.

## Static coverage check and validation limits

Run the inventory check after source edits:

```sh
python3 tools/check_carla_quantity_inventory_333.py
```

The checker independently scans declarations and compares their multiset
with the TSV. It refuses missing or stale declarations and missing review
columns. It does not choose a dimension or a disposition. New declarations
need a source review. `--refresh-lines` refreshes source-line references only
when the declaration set still matches, for example after formatting.

The current static inventory check passes. It covers declarations only.
No Mojo compiler, runtime, or coverage process was run to prepare this
inventory. The integrated work must separately qualify the type-negative
controls, invalid-value tests, source successors, runtime limits, and coverage.
Existing type annotations alone do not prove all mutable legacy state valid.
