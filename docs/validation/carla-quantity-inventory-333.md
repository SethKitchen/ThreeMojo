# CARLA quantity boundary inventory (#333)

This is a preliminary candidate scan of the public CARLA APIs that still
expose a dimensional value as a raw `Float32` or `Float64`. It is not yet a
reviewed classification of each symbol, so the issue's inventory item stays
open. It sorts them into groups, and each
group has its own migration rule. Issue
[#333](https://github.com/SethKitchen/ThreeMojo/issues/333) tracks the work.

## Method

A script scanned every public struct field, function parameter and return in
`extensions/carla/` at `main` `01c7c8e8`. It kept the names that suggest a
dimension, such as distance, width, time, speed, angle, `s`, `x` or a unit
suffix. A private name, one with a leading underscore, is not public. The
scan found 422 candidates. It is a name filter, so it also lists some
dimensionless values, such as PID gains and the DVS log-intensity
thresholds. [`carla-quantity-inventory-333.tsv`](carla-quantity-inventory-333.tsv)
holds every candidate: its file, symbol, raw type, kind and group. The group
comes from the file alone; a per-symbol review can move a candidate.

The precision-preserving contract exists already. `units.si` defines
`Length64`, `Duration64` and the other `Float64` quantities. A `Float64`
quantity keeps every digit, and a `Float32` quantity is a separate type
that cannot mix with it.

| Group | Entries | Rule |
|---|---:|---|
| Pinned OpenDRIVE and map geometry | 206 | Migrate only with successor pins |
| Internal and hot-loop SI scalars | 94 | Keep raw; a typed public wrapper first |
| Geodesy and V2X | 53 | Keep CARLA's raw fields; add typed accessors |
| Serialized compatibility fields | 41 | Keep raw; the byte format is fixed |
| Runtime time and distance boundaries | 28 | Migrate to `Duration64` and `Length64` |

## Runtime time and distance boundaries

These are the boundaries that a user calls with a time or a distance
during a run. They migrate first, because they are outside the pinned map
geometry. They still need a proof successor: the lane oracle's
`border-parser-successor.json` and `winner-sign-query-migration.json` pin
almost every file in `extensions/carla/` as an unchanged live consumer.

| Boundary | State |
|---|---|
| `Timestamp(frame, elapsed, delta, platform)` | `Duration64`, already on `main` |
| `Timestamp.from_seconds` | The named raw adapter, already on `main` |
| `EpisodeSettings.fixed_delta_seconds` | `Duration`; `check` refuses infinity |
| `DVSCamera.simulate(image, elapsed)` | `Duration64`, this change |
| `LaneInvasionSensor.tick(map, frame, timestamp, transform)` | `Duration64`, this change |
| `World.get_traffic_lights_from_waypoint(waypoint, distance)` | `Length64`, this change |
| `World.elapsed_seconds`, `World.delta_seconds` | Raw fields that mirror CARLA; `Timestamp` is the typed view |
| `Navigation.delta_seconds`, `Navigation.time_to_unblock` | Internal crowd state |
| `ALSM.current_time`, `ALSM.elapsed_last_actor_destruction` | Internal traffic manager state |

Each migrated boundary refuses a nonfinite or negative value with an error.
The event camera also refuses a time above 9.2e9 seconds, about 291 years.
Its Float32 interpolation can overshoot a tick by about 8 * 2^-24 of the
tick, and a stored event time goes to seconds and back. Below the cap each
result keeps wide headroom inside an `Int`. The tests feed a microsecond tick one
million seconds into a run, and the input digits survive in the event
times and the lane invasion timestamp. This keeps the input precision. It
does not make the event interpolation exact: CARLA's camera narrows the
tick's nanoseconds to `Float32`, and the port does the same.

Nine compile-fail fixtures check that each boundary refuses a raw
`Float64`, the wrong dimension and the `Float32` quantity.

## Pinned OpenDRIVE and map geometry

`map_builder.mojo`, `road_info.mojo`, `map.mojo`, `road.mojo`,
`geometry.mojo` and `polynomial.mojo` are pinned by the CARLA lane oracle in
`tools/carla_lane_oracle/`. They expose road `s`, lane widths, offsets and
waypoint distances in raw `Float64`, as CARLA does. A change to any of
these files needs successor contracts for each pinned digest. The owner of
the lane-oracle machinery must agree to the successor first.

One numerical defect is in this group. `CubicPolynomial(3.5, 0, 0, 1, s=1e6)`
re-expands its coefficients about zero, as CARLA does. At `x = 1e6` the
expanded terms cancel, and `evaluate` returns 0 instead of 3.5. A typed
`Length64` alone does not fix it. The fix keeps the local coefficients and
evaluates at `x - s`. That changes the computed bits for every road, so it
needs new oracle pins. Its migration and the typed map queries belong in
one coordinated successor change.

## Geodesy and V2X

`GeoLocation`, `Ellipsoid`, `OffsetTransform` and the projection parameter
records keep CARLA's raw degree and meter fields. The georeference string
round trip depends on those fields. `GeoLocation` already has typed
`latitude_angle` and `longitude_angle` accessors. GNSS and CAM noise records
hold standard deviations and biases in CARLA's raw units. The rule for this
group is a typed accessor or adapter beside each raw field, not a field
change.

## Serialized compatibility fields

`recorder_packets.mojo`, `recorder_physics.mojo`, the recorder's
`write_frame` and the replayer's clock fields mirror CARLA's recorder file
format. The sensor data headers mirror CARLA's serialized sensor bytes. A
field type there is part of a byte layout, so it stays raw. A typed view can
wrap a record where a runtime caller needs one.

## Internal and hot-loop SI scalars

The vehicle and walker physics, the traffic manager's planning, collision,
PID and map stages, the render helpers, the camera exposure and lens
models, and the 2D math helpers use `Float32` scalars in SI units. They port
CARLA's `float` arithmetic one to one. Most are internal state of a public
struct rather than an input that a user supplies. Where a user does supply
one, the migration adds a typed constructor or setter and keeps the raw
field for the arithmetic. `WeatherParameters`, `RgbCameraSettings`,
`WideAngleLens` and `GnssDescription` are the next candidates.

## Remaining acceptance work

- The pinned map group, together with the conditioned cubic evaluation.
- Typed constructors for the user-supplied configuration records.
- A reviewed classification of each candidate in the scan.
- The traffic manager's `ActorId` input audit, which the issue lists as
  separate work.
