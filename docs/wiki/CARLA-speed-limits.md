# OpenDRIVE speed limits

Speed records keep their source values and units. Runtime code converts a
speed through a checked Velocity64 boundary. Float32 simulation conversion
is a separate step. This page describes a bounded correction to CARLA
1360bb9. It does not establish full ASAM schema validation or complete
quantity typing for the rest of the CARLA API.

## Road and lane records

An omitted road or lane speed unit means m/s. The supported explicit units
are m/s, km/h and mph. These rules follow the ASAM OpenDRIVE speed definitions
for [roads](https://publications.pages.asam.net/standards/ASAM_OpenDRIVE/ASAM_OpenDRIVE_Specification/v1.8.1/specification/10_roads/10_04_road_type.html)
and [lanes](https://publications.pages.asam.net/standards/ASAM_OpenDRIVE/ASAM_OpenDRIVE_Specification/v1.8.1/specification/11_lanes/11_07_lane_properties.html).
An explicit empty unit or an unsupported unit is refused.

`RoadInfoSpeed` keeps the original number, unit and max text. Its kind states
whether the record is numeric, has no limit, is undefined, or has no speed
element. A numeric zero remains a real zero limit. The road keywords do not
become a zero limit. Lane limits must be numeric, finite and nonnegative.

`RoadInfoSpeed.limit` returns an Optional Velocity64. A numeric record returns
a quantity, including zero. Other road kinds return None. Read the kind to
distinguish those states. `Map.speed_limit_at` selects a lane limit before a
road limit. It checks mutable record data when it reads the limit.

The format defines the road keywords separately in
[ASAM's max-speed type](https://publications.pages.asam.net/standards/ASAM_OpenDRIVE/ASAM_OpenDRIVE_Specification/v1.8.1/specification/16_annexes/map_uml_data_types.html).
The existing record type used for tree placement remains unchanged.

Numeric speed text must match the complete decimal or exponent form from
[XML Schema double](https://www.w3.org/TR/xmlschema11-2/#double).
A leading sign, a decimal point and one signed exponent are supported.
At least one mantissa digit is required. An exponent requires digits.

The parser refuses language suffixes such as `0f` and malformed forms such
as `+.`, `1..0`, `1e2e3` and `0+0`. Earlier conversion accepted those forms.
This correction can reject malformed maps that previously loaded.
Valid decimal values, signed zero and nonzero-underflow rejection are unchanged.

## Signals and simulation

`Signal` retains its raw value, unit and whether a value was supplied.
`Signal.speed_limit` requires a numeric speed signal with an explicit
supported unit. A missing or invalid speed unit is not guessed. Unrelated
traffic-light and stop/yield payloads retain the existing parser behavior.
For example, traffic-light value -1 and stop-sign value 0 can keep an empty
unit because they are not interpreted as physical speeds.

ASAM requires a unit with a signal value. See its
[signal definition](https://publications.pages.asam.net/standards/ASAM_OpenDRIVE/ASAM_OpenDRIVE_Specification/1.8.0/specification/14_signals/14_01_introduction.html).
This parser enforces the physical speed boundary, not every signal rule in
the full schema.

`simulation_speed` accepts Velocity64 and returns the existing Float32
Velocity. It refuses nonfinite values, negative values, overflow and
underflow to zero. Conversion never changes the source record or wire unit.
A speed of 45 mph becomes 20.1168 m/s, equivalent to 72.42048 km/h.

The world uses the checked signal speed when it creates a sign. The traffic
manager compares desired and landmark speeds in m/s. The previous mixed
comparison could treat a desired 5 m/s as the number 18 in an m/s comparison.
The corrected result can change braking and scenario playback.

Give-way anticipation uses lane speed before road speed. A real zero stops
further anticipation. A missing, undefined or unrestricted road record uses
the existing finite 40 m/s fallback. Correct unit conversion can change
trigger extents. Cached road geometry and recorder byte layouts are unchanged.

## Verification contract

Equivalent source units must give the same physical speed. Tests compare
m/s, km/h and mph through parsing, graph-cache restoration, world sign
creation, landmark planning and scenario replay. They also distinguish
zero from road keywords and refuse unsupported units and invalid numbers.
The focused controls do not replace final combined checks and coverage.
