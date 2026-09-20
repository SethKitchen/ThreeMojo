# Vessels

`vessel_mesh` builds a named artery or vein from stature, sex and athleticism. Tapered circular tubes follow the muscle landmarks.

![A six-foot male right leg turns with bones and named arteries and veins](out/vessels.png)

The solids live in `extensions/humanoid/skeleton/leg/vessels/`. `add_leg` can draw them with `VESSELS`. See [Leg](Leg).

This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.contents import BONES, VESSELS
from extensions.humanoid.skeleton.leg.vessels.dimensions import FEMORAL_ARTERY
from extensions.humanoid.skeleton.leg.vessels.geometry import vessel_mesh
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var artery = vessel_mesh(person, FEMORAL_ARTERY)
```

`side` picks `RIGHT` or `LEFT`. A right leg is the default.

The solids live in the leg frame. The origin is the tibiofemoral joint line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

## Named parts

The labeled set follows a standard dissection of the lower-limb vessels.

| Part | Role |
|---|---|
| `FEMORAL_ARTERY` | Inguinal analog to the adductor hiatus analog. |
| `POPLITEAL_ARTERY` | Popliteal fossa behind the knee. |
| `ANTERIOR_TIBIAL_ARTERY` | Anterior compartment to the ankle. |
| `POSTERIOR_TIBIAL_ARTERY` | Deep posterior compartment to the medial malleolus. |
| `PERONEAL_ARTERY` | Lateral deep calf to the lateral malleolus. |
| `FEMORAL_VEIN` | Beside the femoral artery. |
| `POPLITEAL_VEIN` | Beside the popliteal artery. |
| `GREAT_SAPHENOUS_VEIN` | Medial superficial path from ankle to groin. |
| `SMALL_SAPHENOUS_VEIN` | Posterior superficial path from ankle to knee. |

Paths and radii are authored ratios of stature. They are template parameters. They are not a cited vessel-diameter table.

`is_artery` returns True for the five named arteries.

## Tissue

`arterial_tissue()` and `venous_tissue()` hold wet density 1.06 g/cm³ as a named whole-blood template. Water fraction is 0.80.

Arterial circumferential modulus is 0.50 MPa. Venous circumferential modulus is 0.30 MPa. Poisson's ratio is 0.45.

Water fraction is metadata. Mass uses wet density times envelope volume. Do not scale by one minus water fraction again.

These values are named research metadata. This extension does not implement a constitutive model.

## Mass

```mojo
from extensions.humanoid.skeleton.leg.vessels.mass import vessel_mass
from units.si import GRAM

var report = vessel_mass(person, FEMORAL_ARTERY)
report.mass.to(GRAM)
```

## Example

`examples/vessels.mojo` draws one six foot male right leg. The layers are bones and vessels. It writes `out/vessels.png`. Run it with:

```bash
.venv/bin/mojo run -I . examples/vessels.mojo out/vessels.png
```
