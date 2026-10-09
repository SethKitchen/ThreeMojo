# CARLA lane borders

The OpenDRIVE reader gives a border-only lane its width from its borders. CARLA 1360bb9 stores `<border>` records and does not read them, so it gives such a lane zero width. This port evaluates them. A lane with `<width>` records is unchanged.

## What a border is

ASAM OpenDRIVE 1.8.1, section 11.6.2, defines a `<border>` as a lane's outer limit. It is a t-coordinate from the reference line:

```
t_border(ds) = a + b ds + c ds^2 + d ds^3
```

`ds` is the distance from the record's start. The record starts at its `sOffset` from the start of its `<laneSection>`.

## How the reader makes widths

For each lane that has borders and no widths, the reader adds width records:

- The width of lane 1 or -1 is the distance from the reference line to its border.
- The width of lane `n` is the distance from the border of lane `n - 1` (or `n + 1` on the right) to its own border.
- A width piece starts at the section's start and where either border record starts in the section. Each piece is the difference of the two border cubics, re-expanded about the piece's start.
- Left lanes measure the width as `outer - inner`, and right lanes measure it as `inner - outer`.

All later geometry reads these width records: the lane center, heading and pitch, the waypoint queries, the certified search and the mesh. The `<border>` records also stay in the map, as CARLA stores them.

## Precedence

If a lane has both `<width>` and `<border>` records, the reader uses the widths, as ASAM requires. That lane gets no border widths.

## What the reader refuses

`load_opendrive` raises for a lane section that:

- puts border-only lanes in the same group as lanes with widths (ASAM rule `exclusive_width_border`)
- uses border-only lanes on a road with a nonzero `<laneOffset>` (ASAM rule `exclusive_offset_border`). A `<laneOffset>` with all-zero coefficients is allowed as a compatibility extension; ASAM forbids the element even when all coefficients are zero.
- has a border-only lane whose first border starts after the section's start
- has a border-only lane whose inner lane has no borders
- has a zero length and border-only lanes
- has a border that crosses its inner border, which makes a negative width (ASAM rule `overlap_with_inner_lanes`). The reader checks the least value of each width cubic on its piece, at the ends and at the cubic's critical points. It allows one nanometer of rounding where two borders meet. The derivative solver retains small roots and uses exponent-tagged product sums for the discriminant. It refuses nonfinite coefficients or an evaluation outside the numeric range.

## Limits

- The reader accepts out-of-order border records and records before the section start for compatibility. ASAM requires ordered records with nonnegative offsets. These accepted cases are not claims of ASAM validity.

- The width pieces are cubics in double precision. A Taylor shift of a border record far from its start can round the coefficients. The reference evaluation in CARLA has the same kind of rounding.
- The reader does not compare borders with a lane height, superelevation or crossfall record.

Source: `extensions/carla/opendrive.mojo`, `_border_widths`. Tests: `tests/test_carla_lane_borders.mojo`. Issue: [#577](https://github.com/SethKitchen/ThreeMojo/issues/577).

