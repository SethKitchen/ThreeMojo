# Vessels

`vessel_mesh` builds a named lower-limb artery or vein. Connected centerlines preserve the major arterial branches and venous junctions.

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

The labeled set follows the standard adult lower-limb courses.

| Part | Role |
|---|---|
| `FEMORAL_ARTERY` | Femoral triangle through the adductor canal and hiatus. |
| `POPLITEAL_ARTERY` | Adductor hiatus through the posterior knee to the tibial branch point. |
| `ANTERIOR_TIBIAL_ARTERY` | Branch point through the proximal interosseous route and anterior leg. |
| `POSTERIOR_TIBIAL_ARTERY` | Branch point through the deep posterior leg and behind the medial malleolus. |
| `FIBULAR_ARTERY` | Posterior tibial branch along the deep posterior fibula. |
| `PERONEAL_ARTERY` | Compatibility name for `FIBULAR_ARTERY`. |
| `FEMORAL_VEIN` | Popliteal continuation through the adductor hiatus to the groin. |
| `POPLITEAL_VEIN` | Deep-vein confluence through the posterior knee. |
| `GREAT_SAPHENOUS_VEIN` | Anterior medial malleolus, medial leg and knee, then femoral vein. |
| `SMALL_SAPHENOUS_VEIN` | Posterior lateral malleolus and calf, then popliteal vein. |

The femoral artery ends exactly where the popliteal artery starts. Both tibial arteries start at the popliteal branch point.

The fibular artery branches from the proximal posterior tibial path. The saphenous veins end exactly on their deep-vein junctions.

Radii remain diagrammatic so marching tetrahedra can show each vessel. The centerlines and junctions carry the anatomical meaning.

`is_artery` returns True for the five named arteries.

## Tissue

`arterial_tissue()` and `venous_tissue()` hold wet density 1.06 g/cm³ as a named whole-blood template. Water fraction is 0.80.

Arterial circumferential modulus is 0.50 MPa. Venous circumferential modulus is 0.30 MPa. Poisson's ratio is 0.45.

Water fraction is metadata. Mass uses wet density times envelope volume. Do not scale by one minus water fraction again.

These values are named research metadata. This extension does not implement a constitutive model.

## Sources

- [Femoral artery, StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK538262/)
- [Popliteal artery, StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK537125/)
- [Lower-extremity venous drainage, NCBI Bookshelf](https://www.ncbi.nlm.nih.gov/books/NBK27332/)
- [Saphenous neurovasculature, StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK541045/)

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
