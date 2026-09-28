# Torso

`add_torso` attaches the vertebrae, the ribs, the sternum, their joint tissues and the torso's muscles, vessels, nerves, lymphatics and skin.

![A six-foot male body below the neck turns twice: bones, joint tissues and muscles on the left, one skin on the right](out/torso.png)

The torso shares the pelvis frame. The origin is the midpoint of the two hip joint centers. Plus y is proximal, plus x is body-right and plus z is anterior. The package is `extensions/humanoid/skeleton/torso/`. See [Pelvis](Pelvis) for the base it stands on.

This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.torso.body import add_body
from extensions.humanoid.skeleton.torso.contents import BOTH, SKIN
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
```

`add_torso` attaches the torso's layers under a parent node. Hang it from the same node as the pelvis. `add_body` attaches the torso, the pelvis, both legs and both feet. It draws one skin over all of them. Pass `contents` to pick the layers. Combine layers with `plus`.

| Value | Draws |
|---|---|
| `BONES` | The seventeen vertebrae, twenty-four ribs and the sternum. |
| `LIGAMENTS` | The intervertebral discs, the costal cartilages and two spinal ligaments. |
| `MUSCLES` | Named torso muscles. |
| `VESSELS` | Arteries and veins. |
| `LYMPH` | The cisterna chyli, the thoracic duct and two node groups. |
| `NERVES` | The spinal cord and the named nerves. |
| `SKIN` | Skin envelope. |
| `BOTH` | Bones, ligaments and muscles. |
| `ALL` | Every named layer. |

A bare integer is a compile error. The arms, the shoulder girdle, the neck and the head are not modeled. The thoracic and abdominal organs are not modeled either.

## Size

Every landmark is authored in centimeters on the six-foot male template. Stature scales it. The values are template parameters. They are not a cited osteometric table. A female template is 8% narrower and 5% shallower through the chest.

The column stands on the pelvis's sacral promontory, so it meets the sacrum for either sex. On the six-foot male template, T1 lies about 52 cm above the hip joint centers.

## Bones

| Part | Shape |
|---|---|
| `T1` to `T12` | Thoracic vertebrae. |
| `L1` to `L5` | Lumbar vertebrae. |
| `STERNUM` | The manubrium, the body and the xiphoid as one plate. |
| `RIB_1` to `RIB_12` | Paired ribs. |

A vertebra is a body, two pedicles and laminae around the canal, a spinous process and two transverse processes. The bodies grow wider and deeper down the column. The column climbs in a lumbar lordosis and a thoracic kyphosis. The thoracic spines slope down steeply in the mid-thorax.

A rib is a spline through its head, its tubercle, its angle and the side of the chest to its costal cartilage. The ribs fall from back to front. The first rib is short and broad. The eleventh and twelfth ribs float: they end at the side.

A thin cortical shell wraps trabecular bone, and the red marrow lives in its pores. `torso_bone_mass` samples the solid on a grid.

## Joint tissues and ligaments

| Part | Paired | Role |
|---|---|---|
| Intervertebral discs | No | Fibrocartilage between each two bodies, and under L5 on the sacrum. |
| Costal cartilages | Yes | From the first ten ribs to the sternum and the costal margin. |
| Anterior longitudinal ligament | No | A wide band down the front of the bodies. |
| Supraspinous ligament | No | Along the tips of the spinous processes. |

## Muscles

| Part | Role |
|---|---|
| Rectus abdominis | A strap from the pelvis's rectus to the fifth to seventh cartilages. |
| External oblique | The flank from the lower ribs down, and the front toward the rectus. |
| Internal oblique | The internal oblique and the transversus, drawn as one deep layer. |
| Erector spinae | From the pelvis's erector up beside the spines to the upper thorax. |
| Quadratus lumborum | From the crest to the twelfth rib. |
| Psoas major | From beside the first lumbar bodies down to the pelvis's psoas. |
| Diaphragm | A dome over the abdomen, with two crura on the lumbar bodies. |
| Intercostals | The muscles of every intercostal space, drawn as one. |
| Serratus anterior | Slips from the upper ribs back toward the scapula. |
| Pectoralis major | A thick belly from the sternum and the cartilages toward the arm. |
| Latissimus dorsi | A broad sheet from the spines and the fascia toward the arm. |
| Trapezius | Its middle and lower parts, from the thoracic spines toward the scapula. |

The diaphragm is unpaired; the other eleven are paired. The pectoralis major, the latissimus dorsi, the trapezius and the serratus anterior end where the arm or the scapula would take them. The waist narrows between the rib cage and the crest.

## Vessels, nerves and lymph

The thoracic aorta rises from where the heart would be, arches to the left of the spine and descends. It meets the upper abdominal aorta, which meets the pelvis's aorta. The inferior vena cava climbs right of the spine. The azygos vein runs up the right of the bodies. The internal thoracic arteries run behind the cartilages and continue as the epigastric arteries. Intercostal arteries and veins run under the ribs.

The spinal cord runs down the canal from T1 to its conus at the first lumbar disc. The sympathetic trunks run down the rib heads and the lumbar bodies. The intercostal nerves run under the ribs. The iliohypogastric nerve crosses the back of the abdomen toward the groin.

The cisterna chyli lies in front of the first two lumbar bodies. The thoracic duct carries its lymph up toward the neck. Para-aortic nodes lie beside the lumbar aorta. Parasternal nodes follow the internal thoracic vessels.

Mass uses the physical radius. The mesh uses a wider display radius for the thinnest branches.

## Skin

The torso's skin uses the leg's method. See [Integument](Integument#envelope). The loft runs from below the waist to the top of the chest. For a male the fat is 14 mm over the abdomen and 8 mm over the chest. For a female it is 24 mm and 15 mm. A female template carries breast tissue over the pectoralis major.

`body_skin_mesh` morphs the lower body's skin into the torso's across the waist. The body below the neck then has one surface. The skin ends in a cut at the top of the chest, where the neck and the shoulders would begin.

## Examples

`examples/torso.mojo` draws a six-foot male body below the neck twice and writes `out/torso.png`. The left copy shows bones, joint tissues and muscles. The right copy shows one skin. The program also prints the mass of several torso parts.

```bash
.venv/bin/mojo run -I . examples/torso.mojo out/torso.png
```
