# Bearing walls

`extensions/building/views/bearing.mojo` takes the gravity load of a building down its walls, storey by storey, and compares it with what the walls can carry. A masonry or stone building carries its floors and roof on its walls. `structural_view` drops the walls, so it cannot check such a building. `bearing_check` can.

![A building model fitted to a scan of a two-storey room, turning](out/scanned-buildings.png)

## Check a building

```mojo
var check = bearing_check(building, default_bearing_options())
for storey in check.storeys:
    print(storey.storey.value, storey.demand.to(NEWTON), storey.capacity.to(NEWTON))
print(check.utilization(), check.mass.to(KILOGRAM))
var mass = element_mass(building, ElementId(3))
```

`check.storeys` holds one `StoreyBearing` for each storey, from the lowest up. `utilization()` is the demand over the capacity. A storey with no wall capacity gives infinity. `check.notes` says what the check leaves out for this building.

## How the load is taken

- **Mass.** An element with a construction weighs its area times the sum of each layer's density times its thickness. A wall loses the area of its openings. A column or a beam weighs its section area times its length times its material's density.
- **Dead load.** The weight of the walls of the storey and every storey above, of the floors above it, and of the roofs from that storey up. A ground slab rests on the ground and loads no wall.
- **Live load.** Each floor above the storey times the largest live load of its storey's spaces, and each roof times the roof live load. The loads are those of `live_load` in [Frame analysis](Frame-analysis), from ASCE/SEI 7-16.
- **Capacity.** Each wall bears on its strongest layer. Its net length is its face's area over its storey's height, less its openings' widths. The capacity is the resistance factor times the strength times the net length times the layer's thickness.
- **Demand.** `dead_factor` times the dead load plus `live_factor` times the live load.

| Option | Default | Source |
|---|---|---|
| `gravity` | 9.80665 m/s² | Standard gravity |
| `dead_factor` | 1.2 | ASCE/SEI 7-16, section 2.3.1 |
| `live_factor` | 1.6 | ASCE/SEI 7-16, section 2.3.1 |
| `resistance_factor` | 0.6 | Unreinforced masonry in axial compression, TMS 402/602-16 |

## A worked check

A masonry box of [Construction kits](Construction-kits), 4 m by 5 m and 3 m high:

| Part | Mass |
|---|---|
| Walls: 54 m² at 669 kg/m² | 36,126 kg |
| Roof: 20 m² at 56 kg/m² | 1,120 kg |
| Ground slab: 20 m² at 480 kg/m² | 9,600 kg |

The walls carry the walls and the roof: 37,246 kg, or 365 kN. The roof's live load is 0.96 kPa on 20 m², or 19.2 kN. The demand is 1.2 x 365 + 1.6 x 19.2 = 469 kN. The walls are 18 m of 365 mm brick at 10 MPa: 0.6 x 10 MPa x 18 m x 0.365 m = 39,420 kN. The utilization is 1.2 percent. `tests/test_building_bearing.mojo` checks these numbers.

## Limits

This is an average, not a design check. The load spreads over a storey's walls by bearing area. The check has no tributary areas, eccentricity, slenderness, buckling, lateral load or soil. A column or a beam adds its weight, and the walls carry all of it. The materials and the loads are typical values. Use the result as a first look at whether a scanned or generated building can stand.
