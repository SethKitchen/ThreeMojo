# Pelvis

`assemble_pelvis` places the four pelvic bones, their ligaments and joint tissues, and the pelvic muscles in one frame.

![A six-foot male lower body turns twice: bones, ligaments and muscles on the left, one skin on the right](out/pelvis.png)

The origin is the midpoint of the two hip joint centers. Plus y is proximal. Plus x is body-right. Plus z is anterior. The package is `extensions/humanoid/skeleton/pelvis/`. See [Leg](Leg) and [Foot](Foot) for the limbs that hang from it.

This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.skeleton.pelvis.assembly import assemble_pelvis
from extensions.humanoid.skeleton.pelvis.contents import BOTH
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var pelvis = assemble_pelvis(person)
var hip = pelvis.hip_center(RIGHT)
var knee = pelvis.leg_origin(LEFT)
```

`hip_center` gives a femoral head's center. `leg_origin` gives the position of a leg frame. At that position, the leg's femoral head sits in its socket.

`add_pelvis` attaches the selected layers under a parent node. `add_lower_body` attaches the pelvis, both legs and both feet, and draws one skin over them. Pass `contents` to pick the layers. Combine layers with `plus`. `BOTH` is the default.

| Value | Draws |
|---|---|
| `BONES` | The two hip bones, the sacrum and the coccyx. |
| `LIGAMENTS` | Named ligaments, the labrum, the socket's cartilage and the interpubic disc. |
| `MUSCLES` | Named pelvic muscles, on both sides. |
| `VESSELS` | Arteries and veins. |
| `LYMPH` | Node groups and the iliac lymphatic trunk. |
| `NERVES` | Named nerves. |
| `SKIN` | Skin envelope. |
| `BOTH` | Bones, ligaments and muscles. |
| `ALL` | Every named layer. |

A bare integer is a compile error.

## Size

The hip joint centers come from the regression of Harrington and colleagues (2007). That regression predicts each center from the width between the anterior superior iliac spines. A sex-specific ratio of stature picks that width.

| Measure | Male | Female | Role |
|---|---|---|---|
| Width between the anterior superior spines | 0.131 S | 0.146 S | Authored template ratio |
| Pelvic depth, front spines to back spines | 0.085 S | 0.085 S | Authored template ratio |
| Joint center, lateral of the spine | 0.33 W + 7.3 mm | 0.33 W + 7.3 mm | Harrington 2007 |
| Joint center, below the spine | 0.30 W + 10.9 mm | 0.30 W + 10.9 mm | Harrington 2007 |
| Joint center, behind the spine | 0.24 D + 9.9 mm | 0.24 D + 9.9 mm | Harrington 2007 |

S is stature. W is the width between the spines. D is the pelvic depth. The millimeter terms scale with stature from a 1.75 m adult. A six-foot male gets joint centers about 17 cm apart.

Every other landmark is an authored ratio of stature. The ratios are template parameters. They are not a cited osteometric table. A female template is 8% wider and 6% shorter. Her pubic arch and her ischial spines are 7% wider again, and her sacrum curves less.

The socket opens laterally, down and forward. It is inclined 45° from vertical and anteverted 17° in the male template. The female template uses 47° and 20°.

## Bones

| Part | Shape |
|---|---|
| Right and left hip bones | The fused ilium, ischium and pubis. |
| Sacrum | A curved wedge of five elliptical stations, with a median crest. |
| Coccyx | A short tapered chain that curls forward. |

The iliac wing is a fan of thin plates from above the socket to the crest. The wing is thickest above the socket and thin in the iliac fossa. The crest is thickest at the iliac tubercle.

Capsules form the columns and rami. They give the thick posterior ilium, the rim of the greater sciatic notch, the arcuate line and the ischial spine. The superior and inferior pubic rami and the ischial ramus ring the obturator foramen.

A cup holds the femoral head. Three joints stay open:

- The socket keeps a joint space of 0.0019 S around the femoral head.
- The sacroiliac joint keeps 0.0012 S between the ilium and the sacrum.
- The pubic symphysis keeps 0.0014 S either side of the midline.

A thin cortical shell wraps trabecular bone. There is no modeled marrow cavity, so the red marrow lives in the trabecular pores. `pelvis_bone_mass` samples the solid on a grid.

## Ligaments and joint tissues

| Part | Role |
|---|---|
| Anterior sacroiliac | Two bands across the front of the joint. |
| Posterior sacroiliac | From the posterior spines to the sacral tubercles, with the interosseous band. |
| Sacrotuberous | From the posterior spine and the sacral border to the ischial tuberosity. |
| Sacrospinous | From the ischial spine to the lower sacrum. |
| Iliolumbar | From the back of the crest toward the fifth lumbar vertebra. |
| Inguinal | From the anterior superior spine to the pubic tubercle. |
| Iliofemoral | The Y ligament, in two limbs over the front of the hip. |
| Pubofemoral | From the superior ramus to the femoral neck. |
| Ischiofemoral | From behind the socket over the back of the neck. |
| Acetabular labrum | A fibrocartilage ring on the socket's rim. |
| Acetabular cartilage | Hyaline cartilage that lines the socket. It leaves the fossa bare. |
| Interpubic disc | Fibrocartilage in the symphysis. It lies on the midline. |

Every part except the disc is paired. Mass uses each part's own tissue. The bands use ligament. The labrum and the disc use fibrocartilage. The lining uses hyaline cartilage.

## Muscles

Fourteen muscles are paired, one of each on each side. Radii are authored in centimeters on the six-foot male template, then scaled by stature and athleticism.

| Part | Role |
|---|---|
| Iliacus | A fan in the iliac fossa. It meets the psoas in front of the hip. |
| Psoas major | From beside the lumbar spine, over the brim, to the lesser trochanter. |
| Piriformis | From the front of the sacrum, out through the greater sciatic foramen. |
| Obturator internus | A fan on the obturator membrane. Its tendon turns around the ischium. |
| Gemelli | The superior and inferior gemelli beside that tendon. |
| Quadratus femoris | A flat quadrilateral from the tuberosity to the femur. |
| Obturator externus | Under the femoral neck to the trochanteric fossa. |
| Gluteus minimus | A fan on the outer ilium, deep to the gluteus medius. |
| Levator ani | The pelvic floor, a funnel down to the midline and the coccyx. |
| Coccygeus | From the ischial spine to the lower sacrum. |
| Rectus abdominis | A flat strap from the pubic crest up the front. |
| Abdominal wall | The obliques and the transversus above the crest, drawn as one layer. |
| Quadratus lumborum | From the back of the crest up beside the spine. |
| Erector spinae | The erector spinae and the multifidus over the sacrum. |

The trunk is not modeled yet. The psoas and the trunk-wall muscles end a short way above the crest. The gluteus maximus and medius, the tensor and the thigh muscles belong to the leg. Their origins come from this pelvis. See [Muscles](Muscles#origins-on-the-pelvis).

## Vessels

The abdominal aorta divides in front of the fourth lumbar vertebra. Each common iliac artery divides at the pelvic brim. The external iliac artery runs to the leg's femoral artery. The internal iliac artery gives the gluteal, internal pudendal and obturator branches.

| Part | Paired | Role |
|---|---|---|
| Abdominal aorta | No | A little left of the midline. |
| Common, external and internal iliac arteries | Yes | The trunk to the leg and the pelvis. |
| Superior and inferior gluteal arteries | Yes | Out above and below the piriformis. |
| Internal pudendal artery | Yes | Around the ischial spine to the perineum. |
| Obturator artery | Yes | Out through the obturator canal. |
| Median sacral artery | No | Down the front of the sacrum. |
| Inferior vena cava | No | Right of the midline. |
| Common, external and internal iliac veins | Yes | The return from the leg and the pelvis. |

Both common iliac veins join the vena cava right of the midline. The left vein crosses the midline to reach it. Mass uses the physical radius. The mesh uses a wider display radius.

## Lymph

Four node groups follow the vessels: external iliac, internal iliac, common iliac and sacral. Five representative nodes stand for each group. The iliac lymphatic trunk runs from the leg's highest inguinal node to the lumbar nodes beside the aorta.

## Nerves

The lumbar roots are not modeled. Each lumbar nerve starts beside the spine, where the psoas would release it.

| Part | Role |
|---|---|
| Lumbosacral trunk | Over the sacral ala to the plexus. |
| Sacral plexus | On the piriformis, then the sciatic nerve out below it to the thigh. |
| Femoral nerve | Between the psoas and the iliacus, under the inguinal ligament. |
| Obturator nerve | Along the side wall and out through the obturator canal. |
| Superior gluteal nerve | Above the piriformis, between the gluteus medius and minimus. |
| Inferior gluteal nerve | Below the piriformis into the gluteus maximus. |
| Pudendal nerve | Around the sacrospinous ligament to the perineum. |
| Lateral femoral cutaneous nerve | Across the iliacus, out beside the anterior superior spine. |

The sciatic and femoral nerves end where the leg's nerves begin.

## Skin

The pelvic skin uses the leg's method. See [Integument](Integument#envelope). The loft runs from just below the pubic arch to a little above the crest. It fits both hip bones, the sacrum and the coccyx, the pelvic muscles, and the top of each leg. The cover is 11 mm of fat for a male and 20 mm for a female, plus 1.8 mm of dermis.

Below the pubic arch the thighs part, and each leg's own skin covers its thigh. `lower_body_skin_mesh` meshes the smooth union of the pelvic skin and both limbs' skins. The lower body then has one surface.

External genitalia and pubic hair are not modeled. The pelvic organs are not modeled either.

## Examples

`examples/pelvis.mojo` draws a six-foot male lower body twice and writes `out/pelvis.png`. The left copy shows bones, ligaments and muscles. The right copy shows one skin. The program also prints the mass of several pelvic parts.

```bash
.venv/bin/mojo run -I . examples/pelvis.mojo out/pelvis.png
```
