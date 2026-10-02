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

The templates scale belly radius. They do not change bone length. Untoned muscle uses scale 0.80. Toned muscle uses scale 1.00, so it carries about half again the volume. Studies of trained and untrained adults report gaps of about that size.

The scales are authored. They are not a cited regression.

## Volume

Untoned muscle is calibrated toward typical adult muscle volumes measured by MRI, such as those of Handsfield et al. (2014), scaled to height. The table gives the sampled volume of a six-foot untoned male at a 4 mm step. Treat each value as approximate. People differ by a quarter or more.

| Muscle | Volume (cm³) |
|---|---|
| Gluteus maximus | 815 |
| Gluteus medius | 272 |
| Tensor fasciae latae | 79 |
| Sartorius | 180 |
| Rectus femoris | 321 |
| Vastus lateralis | 617 |
| Vastus medialis | 441 |
| Vastus intermedius | 445 |
| Pectineus | 75 |
| Adductor longus | 188 |
| Adductor magnus | 602 |
| Gracilis | 119 |
| Biceps femoris | 318 |
| Semitendinosus | 230 |
| Semimembranosus | 292 |
| Gastrocnemius | 466 |
| Soleus | 499 |
| Tibialis anterior | 159 |
| Tibialis posterior | 109 |
| Extensor digitorum longus | 103 |
| Peroneus longus | 124 |
| Peroneus brevis | 55 |
| Flexor hallucis longus | 128 |
| Flexor digitorum longus | 69 |
| Extensor hallucis longus | 40 |

### Packing

The authored bellies do not fill the space around the bones by themselves. `muscle_dimensions` packs them. The belly stations nearest a bone go first. Each moves straight toward its bone until it presses into a bone, or a belly already placed at a similar height. A press of `PACK_OVERLAP`, 15 percent of the two reaches, is allowed, because muscle is soft. Attachments do not move.

Above the knee the bellies pack toward the femoral shaft. Below it each packs toward the nearer of the tibia and the fibula, so the lateral compartment settles on the fibula.

A belly that meets no neighbor then spreads into a sheet. It widens around its bone and thins away from it, up to 1.6 times, and keeps its cross-sectional area. A muscle spreads as far as its tightest station allows, so it widens evenly along its length. Then it packs inward again. `MuscleDimensions.bellies` holds each station's move and spread. A `MuscleField` applies them.

The gluteus medius is below the reported mean. It is a thin fan, and a fuller belly would bulge. The soleus runs down to the calcaneal tendon a hand's breadth above the heel.

## Named parts

The labeled set follows a standard dissection of the lower limb.

| Part | Role |
|---|---|
| `GLUTEUS_MAXIMUS` | Back of the ilium and the sacrum, behind the hip, to the gluteal tuberosity. |
| `GLUTEUS_MEDIUS` | Outer ilium below the crest to the greater trochanter. |
| `TENSOR_FASCIAE_LATAE` | Anterior superior iliac spine into the iliotibial tract. |
| `ILIOTIBIAL_TRACT` | Fascia from the trochanter to Gerdy's tubercle. |
| `SARTORIUS` | Anterior superior iliac spine to the pes anserinus. |
| `RECTUS_FEMORIS` | Anterior inferior iliac spine to the patella. |
| `VASTUS_LATERALIS` | Lateral thigh to the patella. |
| `VASTUS_MEDIALIS` | Medial thigh to the patella. |
| `VASTUS_INTERMEDIUS` | Deep anterior femur to the patella. |
| `PECTINEUS` | Pectineal line of the pubis to the lesser trochanter. |
| `ADDUCTOR_LONGUS` | Front of the pubic body to the medial femoral shaft. |
| `ADDUCTOR_MAGNUS` | Deep medial thigh to the medial femoral condyle. |
| `GRACILIS` | Inferior pubic ramus to the pes anserinus. |
| `BICEPS_FEMORIS` | Ischial tuberosity to the fibular head. |
| `SEMITENDINOSUS` | Ischial tuberosity to the pes anserinus. |
| `SEMIMEMBRANOSUS` | Ischial tuberosity to the medial tibial condyle. |
| `GASTROCNEMIUS` | Both femoral condyles to the Achilles origin. |
| `SOLEUS` | Posterior tibia and fibula to the heel analog. |
| `TIBIALIS_ANTERIOR` | Proximal tibia to the medial midfoot analog. |
| `TIBIALIS_POSTERIOR` | Deep calf to the medial ankle. |
| `EXTENSOR_DIGITORUM_LONGUS` | Fibular head to the anterior ankle. |
| `PERONEUS_LONGUS` | Fibular head, along the fibula's lateral surface, then behind the lateral malleolus. |
| `PERONEUS_BREVIS` | Behind the distal fibula, then behind the lateral malleolus. |
| `FLEXOR_HALLUCIS_LONGUS` | Back of the fibula's lower two thirds to behind the ankle: the lowest belly of the calf. |
| `FLEXOR_DIGITORUM_LONGUS` | Back of the tibia to behind the medial malleolus. |
| `EXTENSOR_HALLUCIS_LONGUS` | Front of the fibula's middle half to the front of the ankle. |
| `ACHILLES_TENDON` | Distal calf to the heel analog. |
| `PATELLAR_TENDON` | Patella to the tibial tuberosity. |

Vastus intermedius and adductor magnus fill the deep thigh compartments. Tibialis posterior fills the deep calf compartment.

### Origins on the pelvis

The pelvic origins come from the pelvis that holds the femur. See [Pelvis](Pelvis). Each landmark keeps its offset from the right hip joint center. A left leg mirrors that offset.

| Landmark | Where on the pelvis | Muscles |
|---|---|---|
| `asis` | Anterior superior iliac spine | Tensor, sartorius |
| `aiis` | Anterior inferior iliac spine | Rectus femoris |
| `iliac` | Iliac tubercle | Gluteus medius, and the top of the leg's skin |
| `psis`, `sacral` | Posterior superior spine and the sacrum's lateral border | Gluteus maximus |
| `ischial` | Low on the back of the ischial tuberosity | The hamstrings, adductor magnus |
| `pubis` | Front of the pubic body | Adductor longus |
| `pectineal` | Pectineal line | Pectineus |
| `pubic_arch` | Inferior pubic ramus | Gracilis, adductor magnus |

The heel comes from the foot's calcaneal tuberosity.

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
