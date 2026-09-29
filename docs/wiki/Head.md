# Head

`add_head` attaches the neck and the head: the seven cervical vertebrae, the skull, the mandible, the teeth and the hyoid, and their joint tissues. It also attaches the muscles of the neck, the jaw and the face, and the head's vessels, nerves, lymph nodes, skin and hair.

![A six-foot male neck and head turn twice: bones, joint tissues and muscles on the left, the skin and the hair on the right](out/head.png)

The neck and the head share the pelvis frame. The origin is the midpoint of the two hip joint centers. Plus y is proximal, plus x is body-right and plus z is anterior. The package is `extensions/humanoid/skeleton/head/`. The neck stands on the first thoracic vertebra of the [Torso](Torso).

This is not a three.js port. See [Extensions](Extensions).

A quality level sets how many triangles the body holds. See [Mesh quality](Mesh-quality).

## Call it

```mojo
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.assembly import add_head
from extensions.humanoid.skeleton.head.contents import ALL, BONES
from extensions.humanoid.skeleton.head.frame import head_dimensions
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
var dims = head_dimensions(person.stature, person.sex)
var atlas = dims.centers[0]
```

`add_head` attaches the neck and the head under a parent node. Hang them from the same node as the torso. Pass `contents` to pick the layers. The layers are the arm's: see [Arm](Arm#call-it). `add_body` attaches the head as well, with the torso's layers, and its one skin covers the head; see [Torso](Torso).

A bare integer is a compile error, for a bone, a part or a layer.

## Pose and size

The head sits on the atlas with the Frankfort plane level, so the eyes look straight ahead. The neck climbs from the first thoracic vertebra in a gentle lordosis.

On the six-foot male template, the top of the skull is 84.4 cm above the hip joint centers. The eyes are at 72.5 cm and the chin is at 60.5 cm. Stature scales every length. A female template is narrower and shallower, as the torso's is. The values are template parameters. They are not a cited anthropometric table.

## Bones

| Part | Bones |
|---|---|
| Cervical vertebrae | `C1`, the atlas, to `C7` |
| Skull | `SKULL`: the vault, the base and the face |
| Jaw | `MANDIBLE` and `TEETH`, both rows |
| Throat | `HYOID` |

The atlas is a ring with two lateral masses. The axis carries the dens up through the atlas's front arch. C3 to C6 have short forked spines. The spine of C7 is long.

The vault is a thin dome of bone about seven millimeters thick. The face is one solid with the orbits and the nasal opening cut out. The mandible is a U of bone with a ramus and a condyle on each side. The condyles sit in front of the ear canals. The occipital condyles sit on the atlas.

## Joint tissues and cartilages

| Part | Role |
|---|---|
| `CERVICAL_DISCS` | A disc under each body from C2 down, the last on T1. |
| `NUCHAL_LIGAMENT` | A thin sheet in the midline, from the occiput down the spines to C7. |
| `ATLANTO_OCCIPITAL_JOINTS` | The capsules between the occipital condyles and the atlas. |
| `TEMPOROMANDIBULAR_JOINT` | The disc of one jaw joint. It is paired. |
| `LARYNX` | The thyroid cartilage's two plates and the cricoid's ring. |
| `TRACHEA` | The windpipe, down to the root of the neck. |

## Muscles

| Group | Parts |
|---|---|
| Neck | Sternocleidomastoid, upper trapezius, splenius capitis, semispinalis capitis, levator scapulae, scalenes, longus colli. |
| Throat | The infrahyoid straps and the suprahyoid floor of the mouth. |
| Jaw | Masseter and temporalis. |
| Face | Frontalis, orbicularis oculi, zygomaticus major and orbicularis oris. |

The upper trapezius meets the torso's trapezius at the base of the neck. The levator scapulae reaches the scapula's superior angle. The suprahyoid floor and the orbicularis oris cross the midline. The rest are paired.

## Vessels, nerves and lymph

The common carotid artery rises beside the trachea and forks at the level of the hyoid. The external carotid gives the facial artery and ends as the superficial temporal artery. The vertebral artery climbs through the transverse processes and loops over the atlas. The internal jugular vein runs down beside the carotid. The external jugular vein runs down across the sternocleidomastoid.

The cervical spinal cord runs up the vertebral canal. The vagus nerve runs down in the carotid sheath. The phrenic nerve runs down the front of the anterior scalene. The cervical plexus fans out from behind the sternocleidomastoid. The facial nerve fans forward through the parotid.

The deep cervical nodes lie in a chain along the internal jugular vein. The submandibular, parotid, occipital and supraclavicular nodes are small groups.

## Skin and hair

The head's skin is sculpted, not lofted. A face is not convex: the eyes sit in sockets, and the chin overhangs the throat. The cranium is an ellipsoid a scalp's thickness outside the vault. A broad blend joins it to the face, the jaw, the cheekbones and the neck. A tight blend adds the nose, the lips, the eyelids, the brow and the ears. The modeled anatomy stays inside the skin.

The scalp's hair is drawn as its volume: a shell about nine millimeters thick, cut back to a hairline. Its mass is its volume times `HAIR_PACKING`, one tenth, for the air between the shafts. Each eyebrow is a short arc.

## Examples

`examples/head.mojo` draws a six-foot male neck and head twice and writes `out/head.png`. The left copy shows the bones, the joint tissues and the muscles. The right copy shows the skin and the hair. The program also prints the mass of several head parts.

```bash
.venv/bin/mojo run -I . examples/head.mojo out/head.png
```
