# Nerves

`nerve_mesh` builds a named peripheral nerve from stature, sex and athleticism. Tapered circular tubes follow the muscle landmarks.

![A six-foot male right leg turns with bones and named peripheral nerves](out/nerves.png)

The solids live in `extensions/humanoid/skeleton/leg/nerves/`. `add_leg` can draw them with `NERVES`. See [Leg](Leg).

This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.contents import BONES, NERVES
from extensions.humanoid.skeleton.leg.nerves.dimensions import SCIATIC_NERVE
from extensions.humanoid.skeleton.leg.nerves.geometry import nerve_mesh
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var sciatic = nerve_mesh(person, SCIATIC_NERVE)
```

`side` picks `RIGHT` or `LEFT`. A right leg is the default.

The solids live in the leg frame. The origin is the tibiofemoral joint line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

## Named parts

The labeled set is the femoral, sciatic, tibial, common peroneal, saphenous and sural nerves.

| Part | Role |
|---|---|
| `FEMORAL_NERVE` | Inguinal analog toward the anterior thigh. |
| `SCIATIC_NERVE` | Ischial analog to the lateral femoral condyle. |
| `TIBIAL_NERVE` | Popliteal fossa to the medial malleolus. |
| `COMMON_PERONEAL_NERVE` | Lateral condyle to the fibular head. |
| `SAPHENOUS_NERVE` | Medial thigh to the medial malleolus. |
| `SURAL_NERVE` | Posterior calf to the lateral malleolus. |

Paths and radii are authored ratios of stature. They are template parameters.

## Tissue

`nerve_tissue()` holds wet density 1.04 g/cm³ as a named adult template. Water fraction is 0.77. Longitudinal modulus is 0.50 MPa. Poisson's ratio is 0.40.

Water fraction is metadata. Mass uses wet density times envelope volume. Do not scale by one minus water fraction again.

These values are named research metadata. This extension does not implement a constitutive model.

## Mass

```mojo
from extensions.humanoid.skeleton.leg.nerves.mass import nerve_mass
from units.si import GRAM

var report = nerve_mass(person, SCIATIC_NERVE)
report.mass.to(GRAM)
```

## Example

`examples/nerves.mojo` draws one six foot male right leg. The layers are bones and nerves. It writes `out/nerves.png`. Run it with:

```bash
.venv/bin/mojo run -I . examples/nerves.mojo out/nerves.png
```
