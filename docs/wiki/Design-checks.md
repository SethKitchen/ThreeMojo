# Design checks

`extensions/design/` checks building members and foundations by the US design codes. Steel beams, columns and connections follow AISC 360-16 (ASD). Sawn lumber and bolts follow the NDS 2018. Concrete walls, footings and anchors follow ACI 318-19. Wind pressure follows ASCE/SEI 7.

Continuous beams use the solver of [Frame analysis](Frame-analysis). The module also writes the values and the TikZ drawing bodies of a LaTeX calculation package. It builds staged 3D views of a structure, colored by demand-to-capacity ratio.

The checks take and return unit-typed quantities. Inside, they work in the units of the code: pounds, kips, inches and feet.

## Modules

| Module | What it gives |
|---|---|
| `quantities` | `POUND64`, `PSI`, `KIP_INCH`, `KIP_FOOT`, `POUND_FOOT`, `SQUARE_INCH`, `CUBIC_INCH`, `INCH_TO_THE_FOURTH`, `MILE_PER_HOUR` and `POUND_PER_INCH`. `extensions.geotech.quantities` gives `PSF`, `PLF`, `KIP`, `KSI` and `PCF` |
| `kinds` | `WindExposure` (`EXPOSURE_B`, `EXPOSURE_C`, `EXPOSURE_D`) and `AnchorKind` (`CAST_IN`, `POST_INSTALLED`) |
| `steel` | `WideFlange`, `w_shapes` and `w_shape` (W8 to W12), `flexural_strength` (F2, F3), `shear_strength` (G2.1), `web_local_yielding` (J10.2), `web_crippling` (J10.3), `Pipe` and `standard_pipes`, `compression_strength` (E3), `concrete_bearing` (J8), `WideFlange.strong_radius`, `combined_ratio` (H1.1), `fillet_weld_strength` (J2.4), `bolt_shear_strength` (J3.6), `base_plate_thickness` (Design Guide 1) and the ASD safety factors |
| `wood` | `Lumber`, `southern_pine_no2`, `dressed_depth`, `joist_line_load`, `simple_span_check`, `bearing_stress_ratio`, `dowel_bearing_strength` and `bolt_lateral_value` (the yield limit equations) |
| `concrete` | `propped_wall_effects`, `cantilever_wall_effects`, `stress_block_factor`, `tension_strain`, `one_way_shear_strength`, `two_way_shear_stress`, `plain_flexural_strength`, `minimum_wall_steel`, `wall_in_plane_shear_strength`, `plain_bearing_strength`, `plain_two_way_shear_strength`, `square_footing_side` and `strip_footing_width` |
| `anchors` | One anchor by ACI 318-19 chapter 17: `steel_tension_strength`, `steel_shear_strength`, `breakout_tension_strength`, `pullout_strength`, `bond_tension_strength`, `pryout_shear_strength`, `concrete_tension_phi` and the steel and pryout factors |
| `wind` | `exposure_coefficient` (Kz), `elevation_factor` (Ke), `velocity_pressure` (qz), `leeward_wall_coefficient` and `wall_net_pressure` |
| `beams` | `continuous_beam` and `patterned_beam` |
| `latex` | `TexValues`, `group_thousands`, `fixed` and `feet_inches` |
| `tikz` | `TikzBody`, the commands of a drawing in model units |
| `assembly` | `Part`, `Assembly`, `add_assembly`, `ratio_color`, `draw_ratio_legend` and `orbit_eye` |

## Check a member

Each check returns the nominal strength, or the stresses and their ratios. Divide a nominal strength by the safety factor that the module exports.

```mojo
from extensions.design.steel import flexural_strength, w_shape
from extensions.design.quantities import KIP_FOOT
from extensions.geotech.quantities import KSI
from units.si import INCH64, Length64, Pressure64

def main() raises:
    var f = flexural_strength(
        w_shape("W8x18"), Pressure64(50, KSI), Length64(16, INCH64), 1.0
    )
    print(f.allowable().to(KIP_FOOT))  # 42.4, as AISC Manual Table 3-2
```

## Analyze a basement wall

A basement wall spans from the slab at its base to the floor at its top. `propped_wall_effects` takes the span, the height of the soil above the bottom support, the equivalent fluid pressure and a uniform lateral surcharge. It integrates the pressure for the reactions and scans the moment along the span. Soil above the top support loads the wall only up to the span.

Give the result to `flexural_resistance` and `shear_resistance` of `extensions.geotech.concrete`, or to `one_way_shear_strength` here, with the load factor of your code.

## Check an anchor

The functions of `anchors` give the nominal strength of one anchor. Multiply each by its phi. Give the four edge distances of the anchor. Give 1.5 h_ef or more for a side without an edge.

1. Get the steel strength with `steel_tension_strength` or `steel_shear_strength`.
2. Get the concrete breakout with `breakout_tension_strength`. Near three or four edges, the function reduces h_ef as 17.6.2.1.2 tells.
3. For a headed anchor, get `pullout_strength`. For an adhesive anchor, get `bond_tension_strength` with the bond stresses of the product's evaluation report.
4. For shear, get `pryout_shear_strength` from the least concrete tension strength.
5. Use the least value. The concrete is taken as cracked, which is conservative.

## Analyze a continuous beam

`continuous_beam` puts one support at each end of each span and loads each span with its own uniform load. `patterned_beam` puts the dead load on every span and the live load on each of the 2^n patterns of spans. It keeps the worst value of each effect. The moments come from the reactions by statics, so they do not depend on the stiffness. The deflections use E I.

## Write a calculation package

A drawing set and its report quote the same numbers. Collect each number once in a `TexValues`, write it, and `\input` the file in both documents. A `TikzBody` writes a plan or a section in model units. The sheet sets the scale with the `x` and `y` keys of its `tikzpicture`. The style names, such as `wl` and `concfill`, and the `\dimline` and `\dimlinev` macros come from the sheet's preamble.

## Animate a structure

Put each member in an `Assembly` as a `Part`, with its construction stage and its ratio. Call `add_assembly` for each frame:

- A `build` from 0 to the stage count shows the construction sequence. Parts of the current stage come down into place.
- `by_ratio` colors each rated part with `utilization_color`. `draw_ratio_legend` paints the scale into the frame.
- `first_stage` leaves out early stages, such as the ground.

`orbit_eye` turns the camera around the model. The y axis is up.

## Limits

- The steel catalog holds the light W8, W10 and W12 shapes and three standard pipes. Add rows for other shapes.
- `flexural_strength` assumes a compact web. Every catalog W shape has one for Fy up to 65 ksi.
- `southern_pine_no2` holds 2-inch Southern Pine No. 2 only. Other species and grades need their own `Lumber`.
- `anchors` checks one anchor. A group of anchors, shear breakout toward an edge and supplementary reinforcement are not covered.
- The wind functions cover the main wind force resisting system of a rigid low building. Components and cladding are not covered.
- These are checks, not a design code. An engineer must choose the loads, the combinations and the limits.
