# Knee

`knee_mesh` builds the articular cartilage, both menisci and both collateral ligaments from a humanoid's stature and sex.

![A right knee shows natural ivory cartilage, menisci and collateral ligaments](out/knee.png)

`extensions/humanoid/skeleton/leg/knee/{dimensions,geometry,mass}.mojo`. Shared field and isosurface code lives under `extensions/humanoid/skeleton/`. Soft-tissue density lives in `soft_tissue.mojo`. The visual look lives in `look.mojo`.

This is not a three.js port. See [Extensions](Extensions), [Femur](Femur) and [Leg](Leg).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.knee.geometry import articular_cartilage
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var cartilage = articular_cartilage(person)
```

Named wrappers build each solid: `articular_cartilage`, `medial_meniscus`, `lateral_meniscus`, `medial_collateral` and `lateral_collateral`. `side` picks `RIGHT` or `LEFT`. A right knee is the default.

`detail` sets the marching-tetrahedra grid. Twenty-four is the default. Eight is the least. Sixty-four is the most.

The solids live in the leg frame. The origin is the tibiofemoral joint line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

`KneePart` names the five solids. A bare integer is a compile error.

## Cartilage thickness

Thickness at the six foot male template uses Shepherd and Seedhom 1999 as named adult means.

| Surface | Six foot male mean | Role |
|---|---|---|
| Femoral condyles | 2.2 mm | Shepherd and Seedhom 1999 |
| Tibial plateau | 2.5 mm | Shepherd and Seedhom 1999 |
| Patella | 3.3 mm | Shepherd and Seedhom 1999 |

Other statures scale those thicknesses in proportion to stature. That scale is an authored template rule. It is not a cited stature regression. The female template uses slightly smaller ratios of stature.

The solid uses a thin patch on each femoral condyle, the trochlea, each tibial plateau and the posterior patella. Thickness uses Shepherd and Seedhom 1999. Each patch footprint is an authored template.

`knee_dimensions(stature, sex, side)` returns the lengths and landmarks without building a mesh.

The accepted stature interval is 1.2 m through 2.5 m. That is the software range.

## Menisci and collaterals

Meniscus size and collateral size are authored sex-specific ratios of stature. They are template parameters. They are not a cited osteometric table.

The medial meniscus is a C-shaped ring on the medial plateau. The posterior horn is the thicker end. The lateral meniscus is more circular. The opening of each C faces the intercondylar notch.

The MCL is a capsule from the medial femoral epicondyle to the medial tibia. The LCL is a capsule from the lateral femoral epicondyle to the fibular head.

`KneeDimensions` is editable. Editing a length does not rebuild landmarks. Call `knee_dimensions` to resolve a template. Call `validate` before a field, mesh or mass consumes an edited copy.

## Soft tissue

`cartilage_tissue()`, `meniscus_tissue()` and `ligament_tissue()` hold wet density, water fraction and a compressive modulus.

Cartilage water fraction 0.75 is the middle of the 60% to 85% range in Mow, Kuei, Lai and Armstrong 1980. Wet density 1.12 g/cm³ is a named adult template inside the published 1.06 to 1.16 g/cm³ range. It is not a cited table cell.

Meniscus water fraction 0.70 follows Fithian, Kelly and Mow 1990. Wet density 1.10 g/cm³ is a named template.

Ligament wet density 1.12 g/cm³ and water fraction 0.65 are named adult templates.

Water fraction is metadata. Wet density already describes the hydrated tissue. Mass uses wet density times envelope volume. Do not scale by one minus water fraction again.

These values are sourced or named research metadata. This extension does not implement a constitutive model.

`SoftTissueKind` is `CARTILAGE`, `LIGAMENT` or `MENISCUS`. `SoftOccupancy` is `SOFT_EMPTY` or `SOFT_FILL`. A bare integer is a compile error.

## Mass and weight

`articular_cartilage_mass(spec)` samples the field. Each cell is empty or filled. The default step is 2 mm.

```mojo
from extensions.humanoid.skeleton.leg.knee.mass import articular_cartilage_mass
from units.si import GRAM, NEWTON, POUND_FORCE

var report = articular_cartilage_mass(person)
report.mass.to(GRAM)
report.weight().to(NEWTON)
report.weight().to(POUND_FORCE)
```

`report.envelope` is the volume inside the surface. `report.mass` is wet-tissue mass. Each patch overlaps the adjacent bone enough to prevent a rendering gap. The value is a grid-sampled estimate. It is not a proven upper bound.

Named mass wrappers exist for each of the five solids.

## Look

`cartilage_phong` is opaque warm ivory. `meniscus_phong` is natural off-white fibrocartilage. `ligament_phong` is pale fibrous tissue. All three are visual approximations.

## Limits

Stature must lie in 1.2 m through 2.5 m. `Sex` must be `MALE` or `FEMALE`. `BodySide` must be `RIGHT` or `LEFT`. `KneePart` must name one of the five solids. Edited zero or non-finite dimensions fail at `validate`.

## Example

`examples/knee.mojo` draws a close view of one six foot male right knee and writes `out/knee.png`. Run it with:

```bash
.venv/bin/mojo run -I . examples/knee.mojo out/knee.png
```

The connected-leg figures live on [Leg](Leg).
