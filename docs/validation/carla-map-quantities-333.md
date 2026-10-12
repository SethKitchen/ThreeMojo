<!--
Copyright (c) 2026 Seth Kitchen, PE
SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
-->

# CARLA dimensional boundaries: map, geometry and compatibility

This review accompanies issue #333. The source base is main commit
`2d81e959db3bc72b44a89aca3c072bce3274fb1e`. The complete per-symbol inventory is
[carla-quantity-inventory-333.tsv](carla-quantity-inventory-333.tsv). That table,
not a name-based candidate count, is the acceptance inventory.

## Public map and road values

Road stations, query distances, OpenDRIVE positions and scalar physical results
use the Float64 `Length64` family. Headings use `Angle64`. Map traversal and
sampling reject nonfinite and nonpositive steps before traversal; waypoint
sampling also refuses a step that cannot advance the represented station.
Signal searches accept finite nonnegative distances. Float64 stations do not
pass through a Float32 quantity on their way to endpoint comparisons.

`Map.lane_width` returns `Length64`. The named `lane_width_float32` view retains
the existing narrow client result. Geometry and lane-edge algorithms that
already produce Float32 coordinates retain that layout and expose `Length`
results. This change makes their units explicit; it does not improve the
precision of their underlying coordinates. The OpenDRIVE builder also retains
CARLA's Float32 start-Location rounding for geometry x/y, even though the
compatibility record exposes those rounded values as Float64. Round-trip
controls distinguish that conversion from unchanged wide road stations,
widths and elevation coefficients. In particular it makes no claim
about contact accuracy at arbitrary world origins with Float32 body positions.

`MapBuilder` groups validate scalar inputs before appending a record. Public
record constructors take quantities; source fields remain their original types.
Checked quantity views validate mutable source scalars when read. The existing
OpenDRIVE speed record keeps its original source number, unit text and distinct
numeric/no-limit/undefined/missing states. Its default constructor takes a
`Velocity64` and stores m/s; source-unit factories retain the original text and
numbers. Zero is not treated as a missing speed limit.

## Conditioned cubics and parameter dimensions

A station cubic stores local coefficients and evaluates with `x - s` before
Horner arithmetic. The coefficient dimensions are length, one, inverse length
and inverse area. Its tangent is dimensionless. The origin is a `Length64`.
This corrects cancellation caused by expanding local coefficients around a
large global origin. It intentionally differs numerically from that old graph.
The independent enclosure review is in
[conditioned-cubic-333.md](conditioned-cubic-333.md).

A normalized paramPoly3 instead uses a dimensionless parameter. Its separate
`NormalizedCubic` type has four `Length64` coefficients and a length-valued
tangent with respect to that parameter. Its checked evaluation range is [0, 1].
The default typed `param_poly3` / `with_param_poly3` and corresponding builder
method select arc-length parameterization; the `_normalized` methods require
`NormalizedCubic`. The two coefficient families cannot be interchanged.

The original CARLA geometry record still stores raw coefficients and an explicit
parameter mode. The `*_from_coefficients` adapters validate that mode and every
coefficient before sampling. A source builder accepts `arcLength`, `normalized`,
or the omitted-source empty string, which retains CARLA's normalized default.
An unknown nonempty mode is refused. Shared polynomial storage is private;
`u_coefficients` and `v_coefficients` expose explicitly raw coefficient tuples.
It cannot expose station-typed coefficient views for a normalized profile.

Sampled geometry constructors validate mutable base records before work. Their
positive `max_samples` budget defaults to 4,194,304 and counts actual samples.
Public spiral evaluation has a matching positive `max_steps` limit. Work that
cannot make representable progress, would overflow a count, or exhausts its
budget is refused explicitly rather than returned as degenerate geometry. Mesh
station and width sampling likewise checks progress and bounds work. A sampled
geometry query also checks that its stored sample sequence is complete, finite
and increasing.

## Explicit compatibility adapters

Named adapters such as `from_si`, `from_coefficients`, `*_meters`, `*_seconds`,
`*_degrees`, and `*_meters_per_second` make source units explicit and check their
finite/domain contract. There is no implicit Float64 or narrower-quantity
conversion into the new map-facing quantity parameters. Private `_RawSI`
construction and underscore-prefixed scalar kernels serve internal algorithms
and historical malformed-record test controls; they are not public input
validation routes.

Recorded sensor timestamps and frame times use `Duration64`, with explicit
seconds adapters retaining Float64 wire bits. Frame counter refusal occurs
before changing its id, duration or elapsed time. Sensor image field-of-view
adapters retain CARLA's exact wire convention: pinhole degrees and wide-angle
vertical radians. The typed image entry selects that convention explicitly.
Recorded walker speeds retain centimeters per second in their named adapter.

The existing Float32 sensor, rendering, mesh and traffic-manager algorithms
retain their arithmetic. Their public values use the matching quantity types;
explicit scalar adapters and private hot-loop kernels preserve existing
serialized layouts and fixture arithmetic. Empty polygon separation and a
collision negotiation that does not yield have explicit absent typed results;
the documented raw adapters retain their positive-infinity sentinel. Infinity
is not accepted as an ordinary finite distance or speed.

## Acceptance evidence

The dedicated map boundary suite covers constructors, checked field views,
builder refusal state, map/road query endpoints, large stations, adjacent
representable values and OpenDRIVE round trips. The conditioned suite uses
independent local-polynomial references and interval containment controls,
including extreme stored coefficient bits and rounded-kernel origin guards.
The supplemental suite covers time and image serialization, source-unit replay
controls, typed physical results and the two paramPoly3 coefficient families.
Negative compile fixtures exercise raw scalars, wrong dimensions and wrong
precision without accepting unrelated compilation errors.

Source review, native compilation, runtime execution, strict negative-diagnostic
review and aggregate proof/coverage gates are separate acceptance steps. A
component diagnostic pass is not a completed issue or an aggregate pass; the
final validation record must identify the exact accepted source revision.
