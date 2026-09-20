# Nerves

`nerve_mesh` builds a named lower-limb nerve. Connected centerlines preserve the sciatic bifurcation and the saphenous branch.

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

The labeled set follows the major adult lower-limb nerve courses.

| Part | Role |
|---|---|
| `FEMORAL_NERVE` | Beneath the inguinal ligament into the anterior thigh. |
| `SCIATIC_NERVE` | Posterior gluteal and thigh route to the popliteal-fossa apex. |
| `TIBIAL_NERVE` | Sciatic branch through the posterior knee and behind the medial malleolus. |
| `COMMON_FIBULAR_NERVE` | Sciatic branch along biceps femoris and around the fibular neck. |
| `COMMON_PERONEAL_NERVE` | Compatibility name for `COMMON_FIBULAR_NERVE`. |
| `SAPHENOUS_NERVE` | Femoral branch through the adductor canal and medial leg. |
| `SURAL_NERVE` | Distal-calf union through the posterior calf to the lateral malleolus. |

The sciatic endpoint equals both terminal-branch origins. The femoral field shares its saphenous branch point.

Nerve radii remain diagrammatic so marching tetrahedra can show them. The centerlines and branch topology carry the anatomical meaning.

## Tissue

`nerve_tissue()` holds wet density 1.04 g/cm³ as a named adult template. Water fraction is 0.77. Longitudinal modulus is 0.50 MPa. Poisson's ratio is 0.40.

Water fraction is metadata. Mass uses wet density times envelope volume. Do not scale by one minus water fraction again.

These values are named research metadata. This extension does not implement a constitutive model.

## Sources

- [Femoral nerve, StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK556065/)
- [Common fibular nerve, StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK532968/)
- [Tibial nerve and popliteal relations, StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK537028/)
- [Saphenous nerve, StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK541045/)
- [Sural nerve, StatPearls](https://www.ncbi.nlm.nih.gov/books/NBK546638/)
- [Sciatic nerve course and bifurcation](https://teachmeanatomy.info/lower-limb/nerves/sciatic-nerve/)

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
