# Femur

`femur` builds a femur mesh from a humanoid's stature and sex.

![Four femurs of different stature and sex turn under a lamp](out/femur.png)

`extensions/humanoid/spec.mojo`, `extensions/humanoid/sex.mojo`, `extensions/humanoid/side.mojo`, `extensions/humanoid/skeleton/tissue.mojo`, `extensions/humanoid/skeleton/bone.mojo`, `extensions/humanoid/skeleton/leg/femur/dimensions.mojo`, `extensions/humanoid/skeleton/leg/femur/geometry.mojo` and `extensions/humanoid/skeleton/leg/femur/mass.mojo`.

This is not a three.js port. See [Extensions](Extensions) and [Why extensions sit beside the port](Why-extensions-sit-beside-the-port).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.femur.geometry import femur
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var bone = femur(person)
```

`side` picks `RIGHT` or `LEFT`. A right femur is the default. `detail` sets the marching-tetrahedra grid along the bone. Twenty-four is the default. Eight is the least. Sixty-four is the most.

The bone stands on y. The origin is mid-shaft. Plus y is proximal. Plus x is lateral. Plus z is anterior. A left femur is the right shape with x flipped.

## Length

Length is a modeling choice. Trotter and Gleser 1952 predict stature from maximum femoral length. This template inverts that published line.

That inverse is not the regression of femur length on stature. The two estimates agree only when the relationship is effectively exact.

| Sex | Published line, lengths in cm |
|---|---|
| Male | `stature = 2.38 * femur + 61.41` |
| Female | `stature = 2.47 * femur + 54.10` |

Those are the American White adult formulae from 1952. Forensic tools use them when no population is named. Later samples report different coefficients. This template keeps this pair as its named default.

A six foot male gets a femur of 51.04 cm on this line.

`femur_dimensions(stature, sex, side)` returns the lengths, angles and landmarks without building a mesh.

The accepted stature interval is 1.2 m through 2.5 m. That is the software range. It is not the calibration range of the 1952 sample.

## Shape

The other linear measures are sex-specific ratios of that length. They are authored template parameters. They are not a cited osteometric table.

| Measure | Male ratio | Female ratio | Role |
|---|---|---|---|
| Head diameter | 0.1030 | 0.0977 | Authored landmark ratio |
| Neck length, shaft axis to head center | 0.1073 | 0.1065 | Authored landmark ratio |
| Bicondylar width | 0.1803 | 0.1736 | Authored landmark ratio |
| Midshaft anteroposterior diameter | 0.0631 | 0.0602 | Authored landmark ratio |
| Midshaft mediolateral diameter | 0.0579 | 0.0567 | Authored landmark ratio |
| Greater trochanter offset | 0.0687 | 0.0648 | Authored construction |
| Lesser trochanter offset | 0.0386 | 0.0370 | Authored construction |
| Anterior bow | 0.0129 | 0.0120 | Authored construction |

Neck-shaft angle, anteversion and the bicondylar angle are authored adult means for the two templates.

The code builds the shaft frame first. It then places the neck relative to that frame, including anteversion. `measured_neck_shaft_angle` reads the generated centerlines. It compares that angle with the reported template value.

The shaft cross-section is an ellipse. The AP and ML diameters are independent.

The solid is a smooth union of anatomical parts. A bowed shaft, a neck and a spherical head meet both trochanters. Both condyles, a patellar surface, a linea aspera and a notch complete the distal end. The mesh is a marching-tetrahedra isosurface of that field. Connectivity comes from the field.

`FemurDimensions` is editable. Editing a length does not rebuild landmarks. Call `femur_dimensions` to resolve a template. Call `validate` before a field, mesh or mass consumes an edited copy.

## Landmarks

`FemurDimensions` stores joint and attachment points in meters, as a `Vector3` always does.

| Member | Meaning |
|---|---|
| `head_center` | Hip joint. |
| `neck_base` | Where the neck meets the shaft. |
| `greater_trochanter` | Lateral attachment. |
| `lesser_trochanter` | Posteromedial attachment. |
| `medial_condyle` | Distal medial articular center. |
| `lateral_condyle` | Distal lateral articular center. |

`femur_distance(dimensions, point)` is the signed distance in meters. Negative is inside.

## Bone tissue

`cortical_tissue()` and `trabecular_tissue()` hold density, porosity and longitudinal moduli. The values come from Morgan, Unnikrishnan and Hussein 2018 ([PMC6053074](https://pmc.ncbi.nlm.nih.gov/articles/PMC6053074/)).

Tissue density is 2.0 g/cm³ for both tissues. Apparent density is tissue density times one minus porosity.

| Tissue | Porosity | Apparent density | Longitudinal moduli |
|---|---|---|---|
| Cortical | 0.10 | 1.8 g/cm³ | 17.9 GPa and 18.16 GPa |
| Trabecular | 0.80 | 0.40 g/cm³ | 400 MPa |

Cortical porosity in the paper is 5% to 15%. The template uses the middle. Table 1 of that review lists two cortical longitudinal moduli from different footnotes. It does not label them tension and compression.

Poisson's ratio 0.62 is a directional cortical figure. It is not an isotropic elastic constant. Do not form a bulk modulus from E and ν with the isotropic formula.

These values are sourced research metadata. This extension does not implement a constitutive model.

`BoneKind` is `CORTICAL` or `TRABECULAR`. A bare integer is a compile error. Tissue data lives in `tissue.mojo`. The visual maps live in `bone.mojo`.

## Mass and weight

The mesh is the outer surface. The interior is not solid cortical bone. `femur_mass(spec)` samples the field. Each cell is empty, cortical region, trabecular region or marrow.

Apparent density already includes porosity. The mass formula applies that factor once.

```mojo
from extensions.humanoid.skeleton.leg.femur.mass import femur_mass
from units.si import GRAM, NEWTON, POUND_FORCE

var report = femur_mass(person)
report.mass.to(GRAM)
report.weight().to(NEWTON)
report.weight().to(POUND_FORCE)
```

`report.envelope` is the volume inside the surface, including marrow. `report.cortical_region` and `report.trabecular_region` include pore space. `report.solid_tissue` is the tissue volume after porosity. `report.mass` is bone-tissue mass.

The report does not estimate a mineral-component mass. That would need a mineral fraction. It does not estimate whole-bone mass with marrow.

A six foot male at a 5 mm step has about 960 g of bone tissue. That is 9.4 N, or 2.1 lbf, on Earth. The value is a grid-sampled estimate under the template tissues. A 20 mm step gave about 1011 g. A 2 mm step gave about 965 g. The estimate is not a proven upper bound.

Left and right femurs match in mass at the same step, within sampling error.

## Look

`bone_albedo` is a procedural sRGB map of dry cortical bone. `bone_roughness` is a linear roughness map. Both are visual approximations. Bone is a dielectric. Metalness is zero.

`MeshStandardMaterial` is not ported. `bone_phong` draws the albedo with a dim highlight until that kind exists. The current renderer does not consume the roughness map as a full PBR material.

## Limits

Stature must lie in 1.2 m through 2.5 m. `Sex` must be `MALE` or `FEMALE`. `BodySide` must be `RIGHT` or `LEFT`. A bare integer is a compile error. Edited zero or non-finite dimensions fail at `validate`.

## Example

`examples/femur.mojo` draws four femurs in a row and writes `out/femur.png`. The row is a five foot female, a five foot six female, a six foot male and a six foot six male. Run it with:

```bash
.venv/bin/mojo run -I . examples/femur.mojo out/femur.png
```
