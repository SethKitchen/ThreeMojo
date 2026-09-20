# Tibia

`tibia` builds a tibia mesh from a humanoid's stature and sex.

![Four tibias of different stature and sex turn under a lamp](out/tibia.png)

`extensions/humanoid/skeleton/leg/tibia/{dimensions,geometry,mass}.mojo`. Shared field, isosurface and occupancy code lives under `extensions/humanoid/skeleton/`.

This is not a three.js port. See [Extensions](Extensions) and [Femur](Femur).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.tibia.geometry import tibia
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var bone = tibia(person)
```

`side` picks `RIGHT` or `LEFT`. A right tibia is the default. `detail` sets the marching-tetrahedra grid along the bone. Twenty-four is the default. Eight is the least. Sixty-four is the most.

The bone stands on y. The origin is mid-shaft. Plus y is proximal. Plus x is lateral. Plus z is anterior. A left tibia is the right shape with x flipped.

## Length

Length is a modeling choice. Trotter and Gleser 1952 predict stature from tibial length. This template inverts that published line.

That inverse is not the regression of tibia length on stature. The two estimates agree only when the relationship is effectively exact.

| Sex | Published line, lengths in cm |
|---|---|
| Male | `stature = 2.52 * tibia + 78.62` |
| Female | `stature = 2.90 * tibia + 61.53` |

Those are the American White adult formulae from 1952. Trotter omitted the medial malleolus from the length she used. This template still inverts the published coefficients. The generated solid includes an authored medial malleolus beyond that length.

A six foot male gets a tibia of 41.37 cm on this line.

`tibia_dimensions(stature, sex, side)` returns the lengths, angles and landmarks without building a mesh.

The accepted stature interval is 1.2 m through 2.5 m. That is the software range. It is not the calibration range of the 1952 sample.

## Shape

The other linear measures are sex-specific ratios of that length. They are authored template parameters. They are not a cited osteometric table.

| Measure | Male ratio | Female ratio | Role |
|---|---|---|---|
| Proximal ML width | 0.182 | 0.174 | Authored landmark ratio |
| Proximal AP depth | 0.118 | 0.112 | Authored landmark ratio |
| Midshaft anteroposterior diameter | 0.072 | 0.068 | Authored landmark ratio |
| Midshaft mediolateral diameter | 0.054 | 0.052 | Authored landmark ratio |
| Distal ML width | 0.128 | 0.122 | Authored landmark ratio |
| Tuberosity offset | 0.032 | 0.030 | Authored construction |
| Malleolus drop | 0.038 | 0.036 | Authored construction |
| Anterior bow | 0.008 | 0.007 | Authored construction |

Torsion and plateau retroversion are authored adult means. The male template uses 23 degrees of external torsion and 7 degrees of retroversion. The female template uses 27 degrees and 8 degrees.

The code builds the plateau first. It then twists the distal end. `measured_torsion` reads the generated distal chord.

The shaft cross-section is an ellipse. The AP and ML diameters are independent.

The solid is a smooth union of anatomical parts. A bowed shaft meets a flat plateau, both condyles and the intercondylar eminence. A broad ridge joins the tibial tuberosity to the shaft. A plafond and medial malleolus form the distal end. A fibular notch is cut from the distal lateral face. Connectivity and smooth normals come from the sampled field.

`TibiaDimensions` is editable. Editing a length does not rebuild landmarks. Call `tibia_dimensions` to resolve a template. Call `validate` before a field, mesh or mass consumes an edited copy.

## Landmarks

`TibiaDimensions` stores joint and attachment points in meters, as a `Vector3` always does.

| Member | Meaning |
|---|---|
| `medial_condyle` | Proximal medial plateau center. |
| `lateral_condyle` | Proximal lateral plateau center. |
| `eminence` | Intercondylar eminence. |
| `tuberosity` | Anterior attachment. |
| `plafond` | Distal tibial plafond. |
| `medial_malleolus` | Distal medial process. |
| `fibular_notch` | Distal lateral notch for the fibula. |

`tibia_distance(dimensions, point)` is the signed distance in meters. Negative is inside.

## Bone tissue

Tissue data is the same as the femur. See [Femur](Femur#bone-tissue).

## Mass and weight

The mesh is the outer surface. The interior is not solid cortical bone. `tibia_mass(spec)` samples the field. Each cell is empty, cortical region, trabecular region or marrow.

Apparent density already includes porosity. The mass formula applies that factor once.

```mojo
from extensions.humanoid.skeleton.leg.tibia.mass import tibia_mass
from units.si import GRAM, NEWTON, POUND_FORCE

var report = tibia_mass(person)
report.mass.to(GRAM)
report.weight().to(NEWTON)
report.weight().to(POUND_FORCE)
```

`report.envelope` is the volume inside the surface, including marrow. `report.cortical_region` and `report.trabecular_region` include pore space. `report.solid_tissue` is the tissue volume after porosity. `report.mass` is bone-tissue mass.

The report does not estimate a mineral-component mass. It does not estimate whole-bone mass with marrow.

A six foot male at a 5 mm step has about 450 g of bone tissue. That is 4.4 N, or 0.99 lbf, on Earth. The value is a grid-sampled estimate under the template tissues. It is not a proven upper bound.

Left and right tibias match in mass at the same step, within sampling error.

## Limits

Stature must lie in 1.2 m through 2.5 m. `Sex` must be `MALE` or `FEMALE`. `BodySide` must be `RIGHT` or `LEFT`. A bare integer is a compile error. Edited zero or non-finite dimensions fail at `validate`.

## Example

`examples/tibia.mojo` draws four tibias in a row and writes `out/tibia.png`. The row is a five foot female, a five foot six female, a six foot male and a six foot six male. Run it with:

```bash
.venv/bin/mojo run -I . examples/tibia.mojo out/tibia.png
```
