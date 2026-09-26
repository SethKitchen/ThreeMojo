# Muscles

`muscle_mesh` builds a named skeletal muscle from stature, sex and athleticism. Tapered elliptical sections give each belly independent width and depth.

![A six-foot male right leg as bones, untoned muscle and toned muscle](out/muscles.png)

`extensions/humanoid/athleticism.mojo` holds `UNTONED` and `TONED`. The solids live in `extensions/humanoid/skeleton/leg/muscles/`. `add_leg` can draw bones, muscles, or both. See [Leg](Leg) for the other layers.

This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.contents import MUSCLES
from extensions.humanoid.skeleton.leg.muscles.dimensions import RECTUS_FEMORIS
from extensions.humanoid.skeleton.leg.muscles.geometry import muscle_mesh
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
var quad = muscle_mesh(person, RECTUS_FEMORIS)
```

A two-argument spec stores untoned muscle. `side` picks `RIGHT` or `LEFT`. A right leg is the default.

The solids live in the leg frame. The origin is the tibiofemoral joint line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

## Athleticism

`Athleticism` is `UNTONED` or `TONED`. A bare integer is a compile error.

The templates scale belly radius. They do not change bone length. Untoned muscle uses scale 0.80. Toned muscle uses scale 1.25. Those scales are authored. They are not a cited CSA regression.

## Named parts

The labeled set follows a standard dissection of the lower limb.

| Part | Role |
|---|---|
| `GLUTEUS_MAXIMUS` | Posterior hip to the gluteal tuberosity. |
| `GLUTEUS_MEDIUS` | Iliac analog to the greater trochanter. |
| `TENSOR_FASCIAE_LATAE` | ASIS analog into the iliotibial tract. |
| `ILIOTIBIAL_TRACT` | Fascia from the trochanter to Gerdy's tubercle. |
| `SARTORIUS` | ASIS analog to the pes anserinus. |
| `RECTUS_FEMORIS` | AIIS analog to the patella. |
| `VASTUS_LATERALIS` | Lateral thigh to the patella. |
| `VASTUS_MEDIALIS` | Medial thigh to the patella. |
| `VASTUS_INTERMEDIUS` | Deep anterior femur to the patella. |
| `PECTINEUS` | Pubic analog to the lesser trochanter. |
| `ADDUCTOR_LONGUS` | Pubic analog to the medial femoral shaft. |
| `ADDUCTOR_MAGNUS` | Deep medial thigh to the medial femoral condyle. |
| `GRACILIS` | Pubic analog to the pes anserinus. |
| `BICEPS_FEMORIS` | Ischial analog to the fibular head. |
| `SEMITENDINOSUS` | Ischial analog to the pes anserinus. |
| `SEMIMEMBRANOSUS` | Ischial analog to the medial tibial condyle. |
| `GASTROCNEMIUS` | Both femoral condyles to the Achilles origin. |
| `SOLEUS` | Posterior tibia and fibula to the heel analog. |
| `TIBIALIS_ANTERIOR` | Proximal tibia to the medial midfoot analog. |
| `TIBIALIS_POSTERIOR` | Deep calf to the medial ankle. |
| `EXTENSOR_DIGITORUM_LONGUS` | Fibular head to the anterior ankle. |
| `PERONEUS_LONGUS` | Fibular head to the lateral malleolus. |
| `PERONEUS_BREVIS` | Distal fibula to the lateral malleolus. |
| `ACHILLES_TENDON` | Distal calf to the heel analog. |
| `PATELLAR_TENDON` | Patella to the tibial tuberosity. |

Vastus intermedius and adductor magnus fill the deep thigh compartments. Tibialis posterior fills the deep calf compartment.

Pelvic origins and the heel are authored offsets from the femoral head and the tibial plafond. This template has no pelvis and no foot bones yet.

`MuscleDimensions` is editable. Editing a landmark does not rebuild the others. Call `muscle_dimensions` to resolve a template. Call `validate` before a field, mesh or mass consumes an edited copy.

## Tissue

`muscle_tissue()` holds wet density 1.06 g/cm³ from Mendez and Keys 1960 as a named adult template. Water fraction is 0.75. Passive modulus is 0.02 MPa. Poisson's ratio is 0.45.

`tendon_tissue()` holds wet density 1.12 g/cm³. Water fraction is 0.62. Longitudinal modulus is 500 MPa. The three connective-tissue solids use this tissue.

Water fraction is metadata. Mass uses wet density times envelope volume. Do not scale by one minus water fraction again.

These values are sourced or named research metadata. This extension does not implement a constitutive model.

## Mass

```mojo
from extensions.humanoid.skeleton.leg.muscles.mass import muscle_mass
from units.si import GRAM

var report = muscle_mass(person, RECTUS_FEMORIS)
report.mass.to(GRAM)
```

Toned muscle is heavier than untoned muscle at the same stature, sex and step.

## Layers

`LegContents` selects what `add_leg` attaches.

| Value | Draws |
|---|---|
| `BONES` | Four bones and five knee tissues. |
| `MUSCLES` | The labeled muscles and three connective-tissue solids. |
| `VESSELS` | Arteries and veins. See [Vessels](Vessels). |
| `LYMPH` | Lymph nodes and trunks. See [Lymph](Lymph). |
| `NERVES` | Named peripheral nerves. See [Nerves](Nerves). |
| `SKIN` | Skin envelope. See [Integument](Integument). |
| `HAIR` | Thigh and calf hair shafts. See [Integument](Integument). |
| `BOTH` | Bones, knee tissues and muscles. |
| `INTEGUMENT` | Skin envelope and hair shafts. |
| `ALL` | Every named layer. |

A bare integer is a compile error. Both is the default.

## Example

`examples/muscles.mojo` draws three six foot male right legs. The row is bones, untoned muscle and toned muscle. It writes `out/muscles.png`. Run it with:

```bash
.venv/bin/mojo run -I . examples/muscles.mojo out/muscles.png
```
