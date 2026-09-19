# Femur

`femur` builds a femur mesh from a humanoid's stature and sex. Thickness, length, neck angle and the condyles all follow from those two facts.

![A six-foot male femur turns under a lamp](out/femur.png)

`extensions/humanoid/spec.mojo`, `extensions/humanoid/sex.mojo`, `extensions/humanoid/side.mojo`, `extensions/humanoid/skeleton/leg/femur/dimensions.mojo` and `extensions/humanoid/skeleton/leg/femur/geometry.mojo`.

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

`side` picks `RIGHT` or `LEFT`. A right femur is the default. `detail` is how many segments the capsule uses around and along. Twenty-four is the default. Eight is the least. Sixty-four is the most.

The bone stands on y. The origin is mid-shaft. Plus y is proximal. Plus x is lateral. Plus z is anterior. A left femur is the right shape with x flipped.

## Length

Length is maximum femoral length from Trotter and Gleser 1952. The paper gives stature from the bone. This inverts the line.

| Sex | Formula, lengths in cm |
|---|---|
| Male | `stature = 2.38 * femur + 61.41` |
| Female | `stature = 2.47 * femur + 54.10` |

Those are the American White adult lines. Forensic tools use them when no population is named. A six foot male therefore has a femur of 51.04 cm.

`femur_dimensions(stature, sex, side)` returns the lengths, angles and landmarks without building a mesh.

## Shape

Every other linear measure is a sex-specific ratio of that length:

| Measure | Male ratio | Female ratio |
|---|---|---|
| Head diameter | 0.1030 | 0.0977 |
| Neck length, shaft axis to head center | 0.1073 | 0.1065 |
| Bicondylar width | 0.1803 | 0.1736 |
| Midshaft anteroposterior diameter | 0.0631 | 0.0602 |
| Midshaft mediolateral diameter | 0.0579 | 0.0567 |
| Greater trochanter offset | 0.0687 | 0.0648 |
| Lesser trochanter offset | 0.0386 | 0.0370 |
| Anterior bow | 0.0129 | 0.0120 |

Neck-shaft angle, anteversion and the bicondylar angle are the usual adult means. They differ by a few degrees between the templates.

The solid is a smooth union of anatomical parts. A bowed shaft, a neck and a spherical head meet both trochanters. Both condyles, a patellar surface, a linea aspera and a notch complete the distal end. The mesh is a capsule shrink-wrapped onto the zero set of that field.

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

## Limits

Stature must lie in 1.2 m through 2.5 m. The formulas are adult. `Sex` must be `MALE` or `FEMALE`. `BodySide` must be `RIGHT` or `LEFT`. A bare integer is a compile error.

## Example

`examples/femur.mojo` draws a six foot male femur. Run it with:

```bash
.venv/bin/mojo run -I . examples/femur.mojo out/femur.png
```
