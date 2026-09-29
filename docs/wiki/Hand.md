# Hand

`add_hand` attaches one hand and its fingers: the carpals, the metacarpals and the phalanges, and their joint tissues. It also attaches the hand's muscles, tendons, vessels, nerves, lymphatics, skin and hair.

![A six-foot male right hand turns twice: bones, joint tissues, muscles and tendons on the left, the skin and the hair on the right](out/hand.png)

The hand shares the pelvis frame. The origin is the midpoint of the two hip joint centers. Plus y is proximal, plus x is body-right and plus z is anterior. The package is `extensions/humanoid/skeleton/hand/`. The hand hangs from the wrist of the [Arm](Arm).

This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.arm.frame import arm_dimensions
from extensions.humanoid.skeleton.hand.assembly import add_hand
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    INDEX,
    finger_joints,
)
from extensions.humanoid.skeleton.hand.contents import ALL, BONES
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
var dims = arm_dimensions(person.stature, person.sex)
var knuckles = finger_joints(dims, INDEX)
```

`add_hand` attaches one hand under a parent node. Hang it from the same node as the arm. Pass `side` to pick the right or the left hand. Pass `contents` to pick the layers. The layers are the arm's: see [Arm](Arm#call-it).

A bare integer is a compile error, for a bone, a finger or a layer.

## Pose and size

The hand stands in the anatomical position. The palm faces forward and the fingers point down, a little apart. The thumb stands forward of the palm and out to the side. The hand turns with the forearm.

The middle finger reaches about 20 cm below the wrist on the six-foot male template. Stature scales every length. The values are template parameters. They are not a cited osteometric table.

## Bones and fingers

| Part | Bones |
|---|---|
| Proximal carpal row | `SCAPHOID`, `LUNATE`, `TRIQUETRUM`, `PISIFORM` |
| Distal carpal row | `TRAPEZIUM`, `TRAPEZOID`, `CAPITATE`, `HAMATE` |
| Metacarpals | `METACARPAL_1` to `METACARPAL_5`, from the thumb out |
| Proximal phalanges | `PROXIMAL_PHALANX_1` to `PROXIMAL_PHALANX_5` |
| Middle phalanges | `MIDDLE_PHALANX_2` to `MIDDLE_PHALANX_5` |
| Distal phalanges | `DISTAL_PHALANX_1` to `DISTAL_PHALANX_5` |

The thumb has no middle phalanx. `Finger` names a digit: `THUMB`, `INDEX`, `MIDDLE`, `RING` or `LITTLE`. `finger_bones` returns a digit's bones, from the wrist out. `finger_joints` returns its joint centers and the tip of its distal phalanx.

A long bone spans two joints of its digit's chain and stops short of each. The gap it leaves is the joint space. A carpal is one knob, or two for the longer ones.

## Joint tissues and ligaments

| Part | Role |
|---|---|
| Flexor retinaculum | A band that arches over the carpal tunnel. |
| Extensor retinaculum | A band across the back of the wrist. |
| Palmar aponeurosis | A fan from the wrist to the base of each finger. |
| Collateral ligaments | Two at each knuckle and each finger joint. |
| Volar plates | One in front of each of those joints. |
| Joint cartilage | The radiocarpal joint's face, and a pad in each joint of the digits. |
| Triangular fibrocartilage | A disc between the ulna's head and the carpus. |

## Muscles and tendons

| Group | Parts |
|---|---|
| Thenar | Abductor pollicis brevis, flexor pollicis brevis, opponens pollicis, adductor pollicis. |
| Hypothenar | Abductor digiti minimi, flexor digiti minimi, opponens digiti minimi. |
| Between the metacarpals | The lumbricals, the dorsal interossei and the palmar interossei. |
| Long tendons | The flexor tendons of the fingers, the flexor pollicis longus tendon, the extensor tendons and the thumb's extensor tendons. |

The long tendons follow each digit's joint chain, in front of the bones or behind them. Their meshes widen the thinnest tendons, so they show on a coarse grid. Mass uses the physical radius.

## Vessels, nerves and lymph

The ulnar artery ends in the superficial palmar arch. The radial artery crosses the back of the wrist and ends in the deep palmar arch. A palmar digital artery runs along either side of each digit. On the back of the hand, the dorsal venous network gathers the dorsal digital veins.

The median nerve sends its recurrent branch into the thenar muscles and fans into the digital nerves of the thumb's side. The ulnar nerve divides into a superficial and a deep branch. The radial nerve's superficial branch crosses the back of the wrist. A proper palmar digital nerve runs along either side of each digit.

A fine plexus drains the palm around to the back of the hand. A collecting vessel from each digit runs up the back of the hand toward the wrist.

## Skin and hair

The palm and each digit fit their own loft. The palm's loft runs from a few centimeters above the wrist to the knuckles. It also slices the lower forearm, so it meets the arm's skin at the same girth. Each digit's loft runs from its knuckle to a little past its fingertip. The palm's pad thins toward the knuckles, so no ledge shows there.

A smooth union joins the palm and the five digits. The web between two fingers rises only where the fingers meet the palm. Six shafts stand for the hair on the back of the hand, and one for each finger's.

## Examples

`examples/hand.mojo` draws a six-foot male right hand twice and writes `out/hand.png`. The left copy shows bones, joint tissues, muscles and tendons. The right copy shows the skin and the hair. The program also prints the mass of several hand parts.

```bash
.venv/bin/mojo run -I . examples/hand.mojo out/hand.png
```
