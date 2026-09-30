# Torso

`add_torso` attaches the vertebrae, the ribs, the sternum, the shoulder girdle, their joint tissues and the torso's muscles, vessels, nerves, lymphatics and skin.

![A six-foot male body, arms and head included, turns twice: bones, joint tissues and muscles on the left, the skin on the right](out/torso.png)

The torso shares the pelvis frame. The origin is the midpoint of the two hip joint centers. Plus y is proximal, plus x is body-right and plus z is anterior. The package is `extensions/humanoid/skeleton/torso/`. See [Pelvis](Pelvis) for the base it stands on.

This is not a three.js port. See [Extensions](Extensions).

A quality level sets how many triangles the body holds. See [Mesh quality](Mesh-quality).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.torso.body import add_body
from extensions.humanoid.skeleton.torso.contents import BOTH, SKIN
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
```

`add_torso` attaches the torso's layers under a parent node. Hang it from the same node as the pelvis. `add_body` attaches the torso, the pelvis, both legs and feet, both arms and hands, and the neck and the head. It draws one skin from the head down to the wrists, and a skin for each hand. Pass `contents` to pick the layers. Combine layers with `plus`.

| Value | Draws |
|---|---|
| `BONES` | The seventeen vertebrae, twenty-four ribs, the sternum, and the clavicles and scapulae. |
| `LIGAMENTS` | The intervertebral discs, the costal cartilages, two spinal ligaments and the shoulder girdle's joints. |
| `MUSCLES` | Named torso muscles. |
| `VESSELS` | Arteries and veins. |
| `LYMPH` | The cisterna chyli, the thoracic duct and two node groups. |
| `NERVES` | The spinal cord and the named nerves. |
| `SKIN` | Skin envelope. |
| `BOTH` | Bones, ligaments and muscles. |
| `ALL` | Every named layer. |

A bare integer is a compile error. The neck and the head are on their own page; see [Head](Head). The thoracic and abdominal organs are not modeled. The arms hang from the shoulder girdle; see [Arm](Arm).

## Size

Every landmark is authored in centimeters on the six-foot male template. Stature scales it. The values are template parameters. They are not a cited osteometric table. A female template is 8% narrower and 5% shallower through the chest.

The column stands on the pelvis's sacral promontory, so it meets the sacrum for either sex. On the six-foot male template, T1 lies about 52 cm above the hip joint centers. The humeral heads lie 18.5 cm to either side of the midline.

## Bones

| Part | Shape |
|---|---|
| `T1` to `T12` | Thoracic vertebrae. |
| `L1` to `L5` | Lumbar vertebrae. |
| `STERNUM` | The manubrium, the body and the xiphoid as one plate. |
| `RIB_1` to `RIB_12` | Paired ribs. |
| `CLAVICLE` | Paired. A flat S from the manubrium to the acromion. |
| `SCAPULA` | Paired. The blade, the spine and the acromion, the coracoid and the glenoid. |

A vertebra is a body, two pedicles and laminae around the canal, a spinous process and two transverse processes. The bodies grow wider and deeper down the column. The column climbs in a lumbar lordosis and a thoracic kyphosis. The thoracic spines slope down steeply in the mid-thorax.

A rib is a spline through its head, its tubercle, its angle and the side of the chest to its costal cartilage. The ribs fall from back to front. The first rib is short and broad. The eleventh and twelfth ribs float: they end at the side.

The clavicle runs from the manubrium out, up and back to the acromion. Its medial two-thirds bow forward and its lateral third bows back. The scapula lies on the back of the chest from the second rib to the seventh, just lateral of the erector spinae. Its glenoid faces out and a little forward, under the acromion. `shoulder_girdle` returns the girdle's landmarks. `upper_arm_point` places a point on the hanging arm.

A thin cortical shell wraps trabecular bone, and the red marrow lives in its pores. `torso_bone_mass` samples the solid on a grid.

## Joint tissues and ligaments

| Part | Paired | Role |
|---|---|---|
| Intervertebral discs | No | Fibrocartilage between each two bodies, and under L5 on the sacrum. |
| Costal cartilages | Yes | From the first ten ribs to the sternum and the costal margin. |
| Anterior longitudinal ligament | No | A wide band down the front of the bodies. |
| Supraspinous ligament | No | Along the tips of the spinous processes. |
| Sternoclavicular joint | Yes | The disc and the capsule between the clavicle and the manubrium. |
| Acromioclavicular joint | Yes | The capsule between the clavicle and the acromion. |
| Coracoclavicular ligament | Yes | The conoid and the trapezoid, from the coracoid up to the clavicle. |

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
| Serratus anterior | Slips from the upper ribs around the chest wall to the scapula's medial border. |
| Pectoralis major | A thick belly from the sternum, the cartilages and the clavicle to a tendon on the humerus. |
| Latissimus dorsi | A broad sheet from the spines and the fascia to a tendon that twists under the arm to the humerus. |
| Trapezius | From the thoracic spines and the base of the neck to the scapular spine, the acromion and the clavicle. |
| Rhomboids | The minor and the major, from the upper thoracic spines to the scapula's medial border. |
| Pectoralis minor | From the third to fifth ribs to the coracoid. |
| Subclavius | Under the clavicle, from the first rib out. |

The diaphragm is unpaired; the other fourteen are paired. The trapezius ends at the base of the neck, where the head's upper trapezius goes on. The waist narrows between the rib cage and the crest. The arm's own muscles are on the [Arm](Arm) page.

## Vessels, nerves and lymph

The thoracic aorta rises from where the heart would be, arches to the left of the spine and descends. It meets the upper abdominal aorta, which meets the pelvis's aorta. The inferior vena cava climbs right of the spine. The azygos vein runs up the right of the bodies. The internal thoracic arteries run behind the cartilages and continue as the epigastric arteries. Intercostal arteries and veins run under the ribs.

The subclavian artery arches over the first rib and under the clavicle to the armpit. The subclavian vein runs in front of it. There the arm's axillary vessels take them over.

The spinal cord runs down the canal from T1 to its conus at the first lumbar disc. The sympathetic trunks run down the rib heads and the lumbar bodies. The intercostal nerves run under the ribs. The iliohypogastric nerve crosses the back of the abdomen toward the groin. The brachial plexus leaves the spine by T1, crosses the first rib behind the subclavian artery and reaches the armpit.

The cisterna chyli lies in front of the first two lumbar bodies. The thoracic duct carries its lymph up toward the neck. Para-aortic nodes lie beside the lumbar aorta. Parasternal nodes follow the internal thoracic vessels. Axillary nodes lie in the fat of the armpit.

Mass uses the physical radius. The mesh uses a wider display radius for the thinnest branches.

## Skin

The torso's skin uses the leg's method. See [Integument](Integument#envelope). The loft runs from below the waist to the base of the neck, and covers the shoulder girdle. It leaves out where the pectoralis major and the latissimus dorsi reach the humerus. The arm's skin covers the folds of the armpit there.

For a male the fat is 14 mm over the abdomen and 8 mm over the chest. For a female it is 24 mm and 15 mm.

A section that stands out from its neighbors puts a kink in the skin. The kink shows as a band of light across the body.

`fit_loft` can relax the sections after it fills the dips. Each relaxing pass blends a section's reach with its neighbors' reach. The skin can move in by at most half its fat, so no solid comes through. The torso uses eight passes. The pelvis and the arms use four.

A female template has breasts over the pectoralis major. Each breast is an ellipsoid of its own, turned a little out and down, in a smooth union with the loft. A loft section is one closed curve around its center, so it cannot dip between the two breasts.

`body_skin_mesh` morphs the lower body's skin into the torso's across the waist, from the widest part of the hips up to the waist. The band is about 10 cm tall, so the flank narrows gradually and not in a step. Past the last full section of each loft, that section goes on straight, so the morph never reads a loft's tapered end.

The neck's skin is a column, and the shoulders' is nearly flat on top. A ridge on each side follows the upper trapezius from the side of the neck down to the acromion. It is a tapered capsule in a smooth union with the body, and it slopes the line from the neck to the shoulder.

Each arm's skin joins that surface in a smooth union at the shoulder. The head's skin joins it in a smooth union at the base of the neck. The body then has one surface, from the head down to the wrists. `add_body` meshes each hand's skin on its own, at its own detail, because a finger is too slim for a grid that spans the body. The hand's skin overlaps the arm's across the wrist.

## Examples

`examples/torso.mojo` draws a six-foot male body twice and writes `out/torso.png`. The left copy shows bones, joint tissues and muscles. The right copy shows the skin. The program also prints the mass of several torso parts.

```bash
.venv/bin/mojo run -I . examples/torso.mojo out/torso.png
```
