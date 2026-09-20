# Patella

`patella` builds a patella mesh from a humanoid's stature and sex.

![Four patellas of different stature and sex turn under a lamp](out/patella.png)

`extensions/humanoid/skeleton/leg/patella/{dimensions,geometry,mass}.mojo`. Shared field, isosurface and occupancy code lives under `extensions/humanoid/skeleton/`.

This is not a three.js port. See [Extensions](Extensions) and [Femur](Femur).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.patella.geometry import patella
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var bone = patella(person)
```

`side` picks `RIGHT` or `LEFT`. A right patella is the default. `detail` sets the marching-tetrahedra grid. Twenty-four is the default. Eight is the least. Sixty-four is the most.

The bone stands on y. The origin is the centroid. Plus y is proximal. Plus x is lateral. Plus z is anterior. A left patella is the right shape with x flipped.

## Size

The patella has no Trotter and Gleser line. Height, width and thickness are authored sex-specific ratios of stature. They are template parameters. They are not a cited osteometric table.

| Measure | Male ratio of stature | Female ratio of stature | Role |
|---|---|---|---|
| Height, proximal to distal | 0.0253 | 0.0240 | Authored template ratio |
| Width, medial to lateral | 0.0248 | 0.0236 | Authored template ratio |
| Thickness, anterior to posterior | 0.0123 | 0.0118 | Authored template ratio |

A six foot male gets a patella about 46 mm high, 45 mm wide and 22 mm thick on this template.

`patella_dimensions(stature, sex, side)` returns the sizes and landmarks without building a mesh.

The accepted stature interval is 1.2 m through 2.5 m. That is the software range.

## Shape

The solid is a triangular sesamoid. A proximal base meets a distal apex. The anterior face is convex. The posterior face holds two articular facets and a vertical ridge. The lateral facet is the larger of the two.

The mesh is a tapered shield with a broad base and a narrow apex. Its posterior ridge separates the facets. The mesh is a marching-tetrahedra isosurface. Connectivity and smooth normals come from the sampled field.

`PatellaDimensions` is editable. Editing a length does not rebuild landmarks. Call `patella_dimensions` to resolve a template. Call `validate` before a field, mesh or mass consumes an edited copy.

## Landmarks

`PatellaDimensions` stores attachment and articular points in meters, as a `Vector3` always does.

| Member | Meaning |
|---|---|
| `apex` | Distal point. |
| `base` | Proximal border. |
| `ridge` | Posterior vertical ridge. |

`patella_distance(dimensions, point)` is the signed distance in meters. Negative is inside.

## Bone tissue

Tissue data is the same as the femur. See [Femur](Femur#bone-tissue). The patella has no marrow cavity.

## Mass and weight

The mesh is the outer surface. A thin cortical shell wraps a trabecular interior. `patella_mass(spec)` samples the field. Each cell is empty, cortical region or trabecular region.

Apparent density already includes porosity. The mass formula applies that factor once.

```mojo
from extensions.humanoid.skeleton.leg.patella.mass import patella_mass
from units.si import GRAM, NEWTON, POUND_FORCE

var report = patella_mass(person)
report.mass.to(GRAM)
report.weight().to(NEWTON)
report.weight().to(POUND_FORCE)
```

`report.solid_tissue` is the tissue volume after porosity. `report.mass` is bone-tissue mass.

The report does not estimate a mineral-component mass.

A six foot male at a 5 mm step has about 30 g of bone tissue. That is 0.30 N, or 0.067 lbf, on Earth. The value is a grid-sampled estimate under the template tissues. It is not a proven upper bound.

Left and right patellas match in mass at the same step, within sampling error.

## Limits

Stature must lie in 1.2 m through 2.5 m. `Sex` must be `MALE` or `FEMALE`. `BodySide` must be `RIGHT` or `LEFT`. A bare integer is a compile error. Edited zero or non-finite dimensions fail at `validate`.

## Example

`examples/patella.mojo` draws four patellas in a row and writes `out/patella.png`. The row is a five foot female, a five foot six female, a six foot male and a six foot six male. Run it with:

```bash
.venv/bin/mojo run -I . examples/patella.mojo out/patella.png
```
