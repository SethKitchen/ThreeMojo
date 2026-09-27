# Foot

`assemble_foot` places the twenty-six bones, the ankle ligaments and the foot muscles in one frame.

![A six-foot male right foot turns, with bones, ligaments and muscles connected](out/foot.png)

The origin is the tibial plafond. Plus y is proximal. Plus x is body-right. Plus z is anterior. The package is `extensions/humanoid/skeleton/foot/`. See [Leg](Leg) for the limb that meets this foot.

This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.foot.assembly import add_foot, assemble_foot
from extensions.humanoid.skeleton.foot.contents import BOTH
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var leg = assemble_leg(person)
var foot = assemble_foot(person)
```

`side` picks `RIGHT` or `LEFT`. A right foot is the default.

`add_foot` attaches the selected layers under a parent node. Pass `origin` from `ankle_center()` so the foot meets a leg. Pass `contents=BONES`, `contents=LIGAMENTS`, `contents=MUSCLES` or `contents=BOTH`. Combine layers with `plus`. Both is the default.

| Value | Draws |
|---|---|
| `BONES` | Twenty-six bones. |
| `LIGAMENTS` | Named ankle and foot ligaments. |
| `MUSCLES` | Extrinsic tendons and intrinsic bellies. |
| `VESSELS` | Arteries and veins. |
| `LYMPH` | Lymphatic trunks. Named nodes stay in the leg. |
| `NERVES` | Named peripheral nerves. |
| `SKIN` | Skin envelope. |
| `HAIR` | Dorsal and digital hair shafts. |
| `BOTH` | Bones, ligaments and muscles. |
| `INTEGUMENT` | Skin envelope and hair shafts. |
| `ALL` | Every named layer. |

A bare integer is a compile error. Skin hides the inner layers when you draw them together. Draw skin and hair with `INTEGUMENT`.

## Size

Length, breadth and ankle height are authored sex-specific ratios of stature. They are template parameters. They are not a cited osteometric table.

| Measure | Male ratio of stature | Female ratio of stature | Role |
|---|---|---|---|
| Length, heel to second toe | 0.152 | 0.146 | Authored template ratio |
| Breadth | 0.058 | 0.054 | Authored template ratio |
| Ankle height | 0.048 | 0.046 | Authored template ratio |

Each landmark is authored as three fractions. The first is of foot length, forward of the heel's skin. The second is of breadth, lateral of the midline. The third is of ankle height, above the ground. The heel's skin lies `HEEL_SKIN`, 0.245 of a foot length, behind the tibial plafond. The malleoli stand about a quarter of the way along a standing foot.

| Landmark | Forward of the heel's skin | Above the ground |
|---|---|---|
| Calcaneal tuberosity, `heel` | 0.085 L | 0.34 H |
| Talar body, under the plafond | 0.25 L | 0.80 H |
| Navicular | 0.445 L | 0.57 H |
| Cuboid | 0.44 L | 0.36 H |
| First metatarsal head | 0.745 L | 0.16 H |
| Second metatarsal head | 0.775 L | 0.14 H |
| Fifth metatarsal head | 0.68 L | 0.13 H |
| Second toe tip | 0.96 L | 0.10 H |

L is foot length. H is ankle height. The navicular stands higher than the cuboid, so the medial arch rises over the lateral column. The metatarsal heads fall in a cascade: the second reaches farthest. The toes shorten from the second to the fifth.

The heel landmark matches the leg Achilles insertion. The malleoli come from the tibia and the fibula. A left foot mirrors x.

## Bones

The talus is a body, a neck and a head, with a lateral process. The calcaneus is a tuberosity, a body and an anterior process, with the shelf that holds the talus. The navicular is two masses. The cuboid and the cuneiforms are rounded blocks. There is no marrow cavity. A cortical shell wraps trabecular bone.

A metatarsal is a broad base, a narrow shaft and a round head. The second metatarsal base sits proximal of the first. The second metatarsal head is the longest of the five.

The hallux has two phalanges. Toes two through five have three. A phalanx starts past the head before it, so each joint keeps its cartilage space.

## Ligaments

Ten named groups cross the ankle and the tarsus. Radii are authored round sections of stature. They are not a cited width table.

| Part | Bands |
|---|---|
| Anterior talofibular | Lateral malleolus to the talar neck. |
| Calcaneofibular | Lateral malleolus to the lateral calcaneus. |
| Posterior talofibular | Lateral malleolus to the posterior talus. |
| Deltoid | Three bands from the medial malleolus. |
| Spring ligament | Sustentaculum to the navicular. |
| Long plantar | Heel to the cuboid, then to the third metatarsal base. |
| Short plantar | Anterior calcaneus to the cuboid. |
| Bifurcate | Anterior calcaneus to the navicular and the cuboid. |
| Talocalcaneal interosseous | Talar body to the sustentaculum. |
| Lisfranc | Medial cuneiform to the second metatarsal, and lateral cuneiform to the third. |

Mass uses the physical bands. The mesh uses those same radii.

## Muscles

Nine extrinsic tendons enter the foot. Twelve intrinsic bellies fill the sole and the dorsum. Belly radii scale with athleticism. Tendon radii do not. `FIBULARIS_*` is the canonical name. `PERONEUS_*` is an alias.

The calcaneal tendon runs nearly vertically behind the ankle into the upper back of the tuberosity. The leg's copy of the tendon passes through the same two points. The extensor tendons lie on the dorsum: over the cuneiforms, along each metatarsal and over its head, to the toe. The long flexors pass under the metatarsal heads.

Tendon meshes use a diagrammatic minimum radius. Mass keeps the physical radius.

## Vessels

Six arteries and three veins serve the foot. Mass uses the physical radius. The mesh uses a wider display radius.

| Part | Role |
|---|---|
| Dorsalis pedis | Dorsal artery from the ankle to the first web. |
| Arcuate artery | Dorsal arch toward the fifth metatarsal. |
| Posterior tibial | Artery behind the medial malleolus. |
| Medial plantar | Artery toward the hallux. |
| Lateral plantar | Artery toward the fifth metatarsal. |
| Plantar arch | Deep plantar connection. |
| Dorsal venous arch | Superficial vein across the metatarsal heads. |
| Great saphenous | Superficial vein in front of the medial malleolus. |
| Small saphenous | Superficial vein behind the lateral malleolus. |

Superficial veins sit in the skin fit. Deep arteries do not set the outer bulk.

## Lymph

Four lymphatic trunks drain the foot. Named nodes stay in the leg. Mass uses the physical radius. The mesh uses a wider display radius.

| Part | Role |
|---|---|
| Dorsal lymphatics | Network across the dorsum. |
| Plantar lymphatics | Network along the sole. |
| Medial collectors | Trunk in front of the medial malleolus. |
| Lateral collectors | Trunk behind the lateral malleolus. |

## Nerves

Seven nerves enter the foot. `DEEP_PERONEAL_NERVE` is an alias of `DEEP_FIBULAR_NERVE`. `SUPERFICIAL_PERONEAL_NERVE` is an alias of `SUPERFICIAL_FIBULAR_NERVE`.

| Part | Role |
|---|---|
| Tibial | Nerve behind the medial malleolus. |
| Medial plantar | Nerve toward the hallux. |
| Lateral plantar | Nerve toward the fifth metatarsal. |
| Deep fibular | Dorsal nerve in the first web. |
| Superficial fibular | Two dorsal branches to the toes. |
| Sural | Lateral dorsal nerve. |
| Saphenous | Medial dorsal nerve. |

## Integument

### Skin

The skin fits the modeled solids with the leg's method. See [Integument](Integument#envelope). One loft runs from behind the heel to the toe webs, at 0.80 of foot length. Five more run along the toes, one each. A toe's loft takes only the solids in its own lane, so the toes stay apart.

The cover is 0.0028 of stature over the dorsum and the sides, and 0.0022 over the toes. Pads under the heel, the lateral column, the metatarsal heads and the toe pulps carry the skin to the ground. The medial arch does not reach it.

Two columns over the distal tibia and fibula close the ankle at one height. The leg's skin covers that top. Draw the leg and the foot in one skin with `add_limb_skin`. See [Integument](Integument#one-skin-for-a-limb).

Display radii do not move the skin. Hair roots lie on the fitted skin. Dorsal hair and digital hair are the two groups.

Physical hair radius is an authored adult mean. The mesh draws a wider shaft so the gallery can show it. Mass uses the physical radius.

## Examples

`examples/foot.mojo` draws one six foot male right foot and writes `out/foot.png`. `examples/limb.mojo` draws that foot on its leg, with skin and without it. It writes `out/limb.png`. Run the foot gallery with:

```bash
.venv/bin/mojo run -I . examples/foot.mojo out/foot.png
```
