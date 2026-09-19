# Fibula

`fibula` builds a fibula mesh from a humanoid's stature and sex.

![Four fibulas of different stature and sex turn under a lamp](out/fibula.png)

`extensions/humanoid/skeleton/leg/fibula/{dimensions,geometry,mass}.mojo`. Shared field, isosurface and occupancy code lives under `extensions/humanoid/skeleton/`.

This is not a three.js port. See [Extensions](Extensions) and [Tibia](Tibia).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.fibula.geometry import fibula
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var bone = fibula(person)
```

`side` picks `RIGHT` or `LEFT`. A right fibula is the default. `detail` sets the marching-tetrahedra grid along the bone. Twenty-four is the default. Eight is the least. Sixty-four is the most.

The bone stands on y. The origin is mid-shaft. Plus y is proximal. Plus x is lateral. Plus z is anterior. A left fibula is the right shape with x flipped.

## Length

Length is a modeling choice. Trotter and Gleser 1952 predict stature from fibular length. This template inverts that published line.

That inverse is not the regression of fibula length on stature. The two estimates agree only when the relationship is effectively exact.

| Sex | Published line, lengths in cm |
|---|---|
| Male | `stature = 2.68 * fibula + 71.78` |
| Female | `stature = 2.93 * fibula + 59.61` |

Those are the American White adult formulae from 1952. A six foot male gets a fibula of 41.46 cm on this line.

`fibula_dimensions(stature, sex, side)` returns the lengths and landmarks without building a mesh.

The accepted stature interval is 1.2 m through 2.5 m. That is the software range. It is not the calibration range of the 1952 sample.

## Shape

The other linear measures are sex-specific ratios of that length. They are authored template parameters. They are not a cited osteometric table.

| Measure | Male ratio | Female ratio | Role |
|---|---|---|---|
| Head diameter | 0.062 | 0.058 | Authored landmark ratio |
| Midshaft anteroposterior diameter | 0.028 | 0.026 | Authored landmark ratio |
| Midshaft mediolateral diameter | 0.024 | 0.022 | Authored landmark ratio |
| Malleolus AP | 0.055 | 0.052 | Authored landmark ratio |
| Malleolus ML | 0.040 | 0.038 | Authored landmark ratio |
| Malleolus height | 0.072 | 0.068 | Authored construction |
| Styloid length | 0.022 | 0.020 | Authored construction |
| Lateral bow | 0.012 | 0.011 | Authored construction |

The shaft is a thin ellipse. The AP and ML diameters are independent. A proximal head and styloid meet a distal lateral malleolus.

The mesh is a marching-tetrahedra isosurface of that field. Connectivity comes from the field.

`FibulaDimensions` is editable. Editing a length does not rebuild landmarks. Call `fibula_dimensions` to resolve a template. Call `validate` before a field, mesh or mass consumes an edited copy.

## Landmarks

`FibulaDimensions` stores joint and attachment points in meters, as a `Vector3` always does.

| Member | Meaning |
|---|---|
| `head_center` | Proximal head. |
| `styloid` | Proximal styloid process. |
| `lateral_malleolus` | Distal lateral process. |

`fibula_distance(dimensions, point)` is the signed distance in meters. Negative is inside.

## Bone tissue

Tissue data is the same as the femur. See [Femur](Femur#bone-tissue).

## Mass and weight

The mesh is the outer surface. The interior is not solid cortical bone. `fibula_mass(spec)` samples the field. Each cell is empty, cortical region, trabecular region or marrow.

Apparent density already includes porosity. The mass formula applies that factor once.

```mojo
from extensions.humanoid.skeleton.leg.fibula.mass import fibula_mass
from units.si import GRAM, NEWTON, POUND_FORCE

var report = fibula_mass(person)
report.mass.to(GRAM)
report.weight().to(NEWTON)
report.weight().to(POUND_FORCE)
```

`report.envelope` is the volume inside the surface, including marrow. `report.solid_tissue` is the tissue volume after porosity. `report.mass` is bone-tissue mass.

The report does not estimate a mineral-component mass. It does not estimate whole-bone mass with marrow.

The value is a grid-sampled estimate under the template tissues. It is not a proven upper bound. A thin shaft needs a finer step than a femur for a stable left and right comparison.

Left and right fibulas match in mass at the same step, within sampling error.

## Limits

Stature must lie in 1.2 m through 2.5 m. `Sex` must be `MALE` or `FEMALE`. `BodySide` must be `RIGHT` or `LEFT`. A bare integer is a compile error. Edited zero or non-finite dimensions fail at `validate`.

## Example

`examples/fibula.mojo` draws four fibulas in a row and writes `out/fibula.png`. The row is a five foot female, a five foot six female, a six foot male and a six foot six male. Run it with:

```bash
.venv/bin/mojo run -I . examples/fibula.mojo out/fibula.png
```
