# CARLA quantity boundary inventory (#333)

This is the reviewed inventory of the public CARLA APIs that expose a
dimensional value as a raw `Float32` or `Float64`. Each of the 422 scan
candidates now has a reviewed dimension, class and decision. The document
also holds the audit of the traffic manager's `ActorId` input boundaries.
Issue [#333](https://github.com/SethKitchen/ThreeMojo/issues/333) tracks the
work. The issue stays open: the pinned map group, the user configuration
records and the `ActorId` defects below still need source changes.

## Method

A script scanned every public struct field, function parameter and return in
`extensions/carla/` at `main` `01c7c8e8`. It kept the names that suggest a
dimension, such as distance, width, time, speed, angle, `s`, `x` or a unit
suffix. A private name, one with a leading underscore, is not public. The
scan found 422 candidates.

The review at `main` `8c933ab` adds four columns to
[`carla-quantity-inventory-333.tsv`](carla-quantity-inventory-333.tsv):

| Column | Content |
|---|---|
| `type_at_head` | The declared type at `8c933ab`, read from the source |
| `dimension` | The physical dimension, or `none` for a ratio, gain or count |
| `reviewed_class` | The class below that sets the rule |
| `decision` | What to do with the symbol, or `done` and how |

The scan columns stay as they were. The scan `group` came from the file
alone. The `reviewed_class` is the result of a per-symbol review, and it
moves 31 candidates out of scope as dimensionless.

The precision-preserving contract exists already. `units.si` defines
`Length64`, `Duration64` and the other `Float64` quantities. A `Float64`
quantity keeps every digit, and a `Float32` quantity is a separate type
that cannot mix with it.

| Reviewed class | Entries | Rule |
|---|---:|---|
| `pinned map geometry` | 210 | Migrate to `Length64` only with successor pins |
| `serialized` | 42 | Keep raw; the byte format is fixed |
| `internal state` | 35 | Keep raw; no user supplies it |
| `geodesy raw field` | 32 | Keep CARLA's raw field; add a typed accessor |
| `dimensionless` | 31 | Out of scope; no unit type applies |
| `internal SI scalar` | 30 | Keep raw; a hot-loop or render helper |
| `user configuration` | 25 | Add a typed constructor; keep the raw field |
| `raw mirror` | 10 | Done; a checked typed view exists |
| `typed` | 4 | Done; the boundary takes a quantity |
| `raw adapter` | 3 | Done; the named raw adapter |

## Traffic manager ActorId audit

Most traffic manager input boundaries refuse an id that `ActorId.is_valid`
refuses. Six do not refuse it, or refuse it only after they change state.
The internal integer dictionaries are not evidence of a wrong id: every key
enters through a checked boundary. The one exception is the registration
defect in row 2.

The audit gives each public boundary in `traffic_manager*.mojo` three bad
ids: `ActorId(-1)`, `ActorId(1 << 32)` and `ActorId(999)`, a valid id that
names no actor. `tests/test_carla_traffic_manager_actor_ids.mojo` checks
each boundary that refuses. A scratch probe of the same calls gave the
results in the "Defect" rows.

| # | Boundary | Out-of-range id | Valid id, no actor | Finding |
|---:|---|---|---|---|
| 1 | The 22 per-actor setters of `TrafficManagerLocal` and `Parameters` | Raises before a change | Stored, as CARLA keys settings by id | Correct |
| 2 | `TrafficManagerLocal.register_vehicles` | Raises, but earlier ids in the list stay inserted and are not noted by the ALSM | Raises, but the id stays registered until the next `ALSM.update` | Defect: partial change |
| 3 | `TrafficManagerLocal.unregister_vehicles` | Raises only at `TrackTraffic.delete_actor`, after the id set, its counter, the buffers and the stages change | Ignored, as CARLA does | Defect: partial change |
| 4 | `TrafficManagerLocal.get_next_action`, `get_action_buffer` | Returns `ROAD_OPTION_VOID` or an empty list | The same | Defect: silent |
| 5 | `ActorSet.remove` | Ignored; the counter moves | Ignored; the counter moves, as CARLA does | Defect: silent |
| 6 | `ActorSet.destroy` | Ignored | Ignored | Defect: silent |
| 7 | `ActorSet.insert` | Raises; earlier ids in the list stay inserted | Inserted | Partial change; see row 2 |
| 8 | `Parameters` getters, such as `get_lane_offset` | Returns the global default | Returns the global default | Silent query; no state changes |
| 9 | `ActorSet.contains`, `SimulationState.contains_actor` | False | False | Correct; an out-of-range id is never a member |
| 10 | `Parameters.remove_actor` | Raises | Ignored | Correct |
| 11 | `set_simulate_physics`, `is_physics_enabled`, `check_all_frozen` | Raises in `World` | Raises in `World` | Correct |
| 12 | `apply_batch` with any command | Raises in `World` at the bad command; earlier commands apply, as in CARLA's `ApplyBatchSync` | The same | Correct |
| 13 | `apply_vehicle_control`, `apply_transform`, `set_vehicle_light_state` | Stores the id; `apply_batch` checks it | The same | Correct; the reader checks |
| 14 | `TrackTraffic` writers and `SimulationState.add_actor` | Raises before a change | Stored | Correct |
| 15 | `SimulationState` getters | Raises "does not track" | Raises "does not track" | Correct |
| 16 | `SimulationState.remove_actor`, `TrackTraffic.get_overlapping_vehicles`, `TrafficManagerShared.buffer` | Ignored, or an empty list | The same | Silent query or no-op |
| 17 | `remove_actor` of the localization, collision, light and motion stages | Ignored | Ignored | Internal; only `ALSM.remove_actor` calls them |

### Fixes

The fix for rows 2 to 6 is in `extensions/carla/traffic_manager.mojo`:

- `register_vehicles` must check each id with `is_valid` and `World.actor`
  before it changes the set. Then it inserts the ids and notes each one.
- `unregister_vehicles` must check each id before it removes one.
- `get_next_action` and `get_action_buffer` must raise for an out-of-range
  id. A valid id without a path keeps the documented void result.
- `ActorSet.remove` and `ActorSet.destroy` must check each id before the
  counter moves.

Rows 8 and 16 are queries that do not change state. A strict reading of
"every boundary that reads one checks it" also makes them raise. That
change adds `raises` to about 25 getters and to their callers in the
stages, so it is a separate change.

This change does not edit `traffic_manager.mojo`. The CARLA lane oracle
pins the file in `border-parser-successor.json` and
`winner-sign-query-migration.json`. A change needs an edge in
`tools/carla_lane_oracle/consumer-successor-ledger.json`. The ledger's
digest is pinned twice: in `consumer_successor_ledger.py` and in
`full_audit_cleanup_contracts.py` (`CONSUMER_LEDGER_SHA256`), and the
second file also pins the first. Open PR #739 owns
`full_audit_cleanup_contracts.py`. The fix must wait until #739 merges, or
its owner must take the two digest updates.

## Precision-narrowing typed boundaries

The review found typed boundaries that take a `Float32` quantity and widen
it into a `Float64` computation. The `Float32` input loses the digits
before the `Float64` arithmetic starts. Each one must take the `Float64`
quantity of the same dimension.

| Boundary | Input | Effect |
|---|---|---|
| `RoadGeometry.__init__(kind, s, x, y, heading, length)` and the `arc`, `spiral` helpers | `Length`, `InverseLength` | CARLA takes `double`. Start coordinates near 1e6 m keep only 0.0625 m steps. The `Float64` overload is exact |
| `RoadGeometry.pos_from_dist(dist)` | `Length` | CARLA's `PosFromDist` takes a `double` |
| `EpisodeSettings.fixed_delta_seconds`, read by `World.tick` | `Duration` | CARLA stores a `double`. A `Float32` step of 0.05 s is 0.0500000007 s, so one million ticks drift about 0.75 ms from CARLA's clock |
| `Navigation.update_crowd(manager, delta)` | `Duration` | CARLA reads the `double` delta of the episode timestamp |
| Agent distances and speeds: `BasicAgent.vehicle_obstacle_detected`, `BasicAgent.generate_lane_change_path`, `is_within_distance`, `BehaviorAgent.car_following_manager`, `LocalPlanner.run_step` | `Length`, `Velocity` | CARLA's Python agents use `double` |

Some typed `Float32` inputs widen into `Float64` arithmetic and are still
correct, because CARLA takes a `float` there:
`Map.waypoint_xodr(road_id, lane_id, s)`,
`DirectedPoint.apply_lateral_offset(offset)` and the `trees_transform`
distances. The navigation mesh margin and cell size follow Recast, which
uses `float`.

The lane oracle pins every file in the table. The migration needs the
same ledger edges as the `ActorId` fixes.

## Runtime time and distance boundaries

These are the boundaries that a user calls with a time or a distance
during a run. They are outside the pinned map geometry, but the lane
oracle pins their files too.

| Boundary | State |
|---|---|
| `Timestamp(frame, elapsed, delta, platform)` | `Duration64`, already on `main` |
| `Timestamp.from_seconds` | The named raw adapter, already on `main` |
| `EpisodeSettings.fixed_delta_seconds` | `Duration`; `check` refuses infinity; see the narrowing table |
| `DVSCamera.simulate(image, elapsed)` | `Duration64`, on `main` |
| `LaneInvasionSensor.tick(map, frame, timestamp, transform)` | `Duration64`, on `main` |
| `World.get_traffic_lights_from_waypoint(waypoint, distance)` | `Length64`, on `main` |
| `LaneInvasionEvent(frame, timestamp, transform, markings)` | `Duration64`; refuses a nonfinite or negative time |
| `LaneInvasionEvent.timestamp` | Raw field that mirrors CARLA; `elapsed()` is the checked typed view |
| `SensorMeasurement.timestamp` | Raw field that the header writes; `elapsed()` is the checked typed view |
| `World.elapsed_seconds`, `World.delta_seconds` | Raw fields that mirror CARLA; `Timestamp` is the typed view |
| `Navigation.delta_seconds`, `Navigation.time_to_unblock` | Internal crowd state |
| `ALSM.current_time`, `ALSM.elapsed_last_actor_destruction` | Internal traffic manager state |

Each migrated boundary refuses a nonfinite or negative value with an error.
The event camera also refuses a time above 9.2e9 seconds, about 291 years.
Its Float32 interpolation can overshoot a tick by about 8 * 2^-24 of the
tick, and a stored event time goes to seconds and back. Below the cap each
result keeps wide headroom inside an `Int`. The tests feed a microsecond
tick one million seconds into a run, and the input digits survive in the
event times and the lane invasion timestamp. This keeps the input
precision. It does not make the event interpolation exact: CARLA's camera
narrows the tick's nanoseconds to `Float32`, and the port does the same.

Nine compile-fail fixtures check that each boundary refuses a raw
`Float64`, the wrong dimension and the `Float32` quantity.

The lane invasion event and the sensor measurement were the last runtime
time records with only a raw field. The event constructor now takes a
`Duration64`. Each record keeps its raw Float64 field and has an `elapsed`
view that checks the field before it returns a `Duration64`. A measurement
also refuses a nonfinite or negative world time before it writes its
header. `tests/test_carla_event_time_quantity.mojo` checks the exact bits
of large, tiny and signed-zero times, a one-microsecond step at about
1.2e8 seconds, and the header round trip. Four more compile-fail fixtures
check the event constructor and the typed view. The lane oracle accepts
these two source changes only as the exact steps in
`tools/carla_lane_oracle/runtime-view-successor.json`. Each step starts at
the after digest of the runtime boundary edge for the same file.

## Pinned OpenDRIVE and map geometry

`map_builder.mojo`, `road_info.mojo`, `map.mojo`, `road.mojo`,
`geometry.mojo`, `polynomial.mojo`, `town.mojo` and the lane-mark edges of
`mesh_factory.mojo` are in this class. They expose road `s`, lane widths,
offsets and waypoint distances in raw `Float64`, as CARLA does. Signal
`pitch` and `roll` are angles, and `RoadInfoSpeed.speed` is a speed. A
change to any of these files needs successor contracts for each pinned
digest. The owner of the lane-oracle machinery must agree to the
successor first.

One numerical defect is in this group. `CubicPolynomial(3.5, 0, 0, 1, s=1e6)`
re-expands its coefficients about zero, as CARLA does. At `x = 1e6` the
expanded terms cancel, and `evaluate` returns 0 instead of 3.5. A typed
`Length64` alone does not fix it. The fix keeps the local coefficients and
evaluates at `x - s`. That changes the computed bits of every record that
starts at a nonzero `s`, so it needs new oracle pins. Its migration and the
typed map queries belong in one coordinated successor change. That change
is still open.

The fix is not a local edit, for two reasons:

- The certificates read the expanded coefficients. `curve_bounds.mojo`
  (`_polynomial_jet`), `lane_value_bounds.mojo` (`_polynomial_value`),
  `junction_bounds.mojo` (`_polynomial_bounds` and its interval form) and
  `Road`'s line-center cubic in `road.mojo` enclose the value of the
  expanded cubic. A conditioned `evaluate` returns 3.5 where that
  enclosure holds only 0, so these bounds must move to the local form in
  the same change. Otherwise they are unsound.
- Thirteen lane oracle records pin `polynomial.mojo`, by whole-file digest,
  token digest, embedded source or selected method. They are
  `border-parser-successor.json`, `canonical-source-correspondence.json`,
  `frozen-arc-producer-migration.json`, `full-audit-cleanup-successor.json`,
  `optional-runtime-migration.json`, `rounded-line-singleton-migration.json`,
  `runtime-source-pins.json`, `seed-count-successor.json`,
  `spiral-graph-correspondence.json`, `sum2-correspondence-migration.json`,
  `supported-source.json`, `translated-parameter-source.json` and
  `winner-sign-query-migration.json`. `tools/coverage_loop_proofs.py` pins
  it too. Three records state that `__init__`, `evaluate` and `tangent`
  are byte-identical to the reviewed proof sources. A conditioned
  evaluation makes that statement false, so each record needs a reviewed
  successor, not a new digest. Each of the thirteen records also pins
  `road.mojo` or a certificate module.

## Geodesy and V2X

`GeoLocation`, `Ellipsoid`, `OffsetTransform` and the projection parameter
records keep CARLA's raw degree and meter fields. The georeference string
round trip depends on those fields. `GeoLocation` already has typed
`latitude_angle` and `longitude_angle` accessors. The altitude and the
projection offsets need `Length64` accessors, and the projection origins
need `Float64` angle accessors. The V2X path loss distances need a
`Length64` adapter. The CAM speeds keep the ETSI encoding.

## User configuration records

`WeatherParameters`, `RgbCameraSettings`, `WideAngleLens`,
`GnssDescription`, `CamNoise` and the mesh generation parameters hold
values that a user supplies. The rule is a typed constructor beside the
raw fields. The raw fields keep CARLA's `float` arithmetic.

## Serialized compatibility fields

`recorder_packets.mojo`, `recorder_physics.mojo`, the recorder's
`write_frame` and the replayer's clock fields mirror CARLA's recorder file
format. The sensor data headers, the radar detection and the semantic
lidar detection mirror CARLA's serialized sensor bytes. A field type there
is part of a byte layout, so it stays raw. A typed view can wrap a record
where a runtime caller needs one.

## Internal state and hot-loop scalars

The vehicle and walker physics, the traffic manager's planning, collision,
PID and map stages, the render helpers and the 2D math helpers use
`Float32` scalars in SI units. They port CARLA's `float` arithmetic one to
one. They are internal state of a public struct, or the result of a
helper, not an input that a user supplies. They stay raw.

## Dimensionless candidates

The name filter also matched 31 values without a dimension: PID gains, the
DVS log-intensity thresholds, exposure values, pixel coordinates, scale
factors, cosines and the replayer's time factor. No unit type applies, and
the issue does not cover them.

## Remaining acceptance work

- The `ActorId` fixes for rows 2 to 6, after PR #739 merges.
- The precision-narrowing boundaries, with the same ledger edges.
- The pinned map group, together with the conditioned cubic evaluation
  and the certificate modules that read its coefficients.
- Typed constructors for the user configuration records.
- Typed accessors for the geodesy raw fields.
