# Arm

`add_arm` attaches one arm: the humerus, the radius and the ulna, their joint tissues, and the arm's muscles, vessels, nerves, lymphatics, skin and hair.

![A six-foot male right arm and hand turn twice: bones, joint tissues and muscles on the left, the skin and the hair on the right](out/arm.png)

The arm shares the pelvis frame. The origin is the midpoint of the two hip joint centers. Plus y is proximal, plus x is body-right and plus z is anterior. The package is `extensions/humanoid/skeleton/arm/`. The arm hangs from the scapula of the [Torso](Torso). The hand hangs from the arm's wrist; see [Hand](Hand).

This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.sex import MALE
from extensions.humanoid.side import LEFT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.arm.assembly import add_arm
from extensions.humanoid.skeleton.arm.contents import ALL, BONES, MUSCLES
from extensions.humanoid.skeleton.arm.limb import add_upper_limb
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
```

`add_arm` attaches one arm under a parent node. Hang it from the same node as the torso. Pass `side` to pick the right or the left arm. Pass `contents` to pick the layers, and combine layers with `plus`. `add_upper_limb` attaches an arm and its hand with the same layers.

| Value | Draws |
|---|---|
| `BONES` | The humerus, the radius and the ulna. |
| `LIGAMENTS` | The shoulder's and the elbow's joint tissues, and the interosseous membrane. |
| `MUSCLES` | Named muscles of the shoulder, the arm and the forearm. |
| `VESSELS` | Arteries and veins. |
| `LYMPH` | Two node groups and two bundles of collecting vessels. |
| `NERVES` | The five terminal nerves of the brachial plexus. |
| `SKIN` | Skin envelope. |
| `HAIR` | Representative hair shafts. |
| `BOTH` | Bones, ligaments and muscles. |
| `ALL` | Every named layer. |

A bare integer is a compile error.

## Pose and size

The arm stands in the anatomical position. It hangs at the side, the elbow is straight and the palm faces forward. The upper arm turns about six degrees out from the side, so its skin clears the chest. The forearm turns out a little more at the elbow: seven degrees for a man and ten for a woman.

Every part is authored in centimeters on the six-foot male template, in a frame that hangs straight down. `ArmFrame` places a point of the upper arm, the forearm or the hand. Stature scales every length. A narrower female shoulder moves the arm in without thinning it. The values are template parameters. They are not a cited osteometric table.

On the six-foot template the humerus is about 36 cm long, the radius 27 cm and the ulna 29 cm. These lengths lie near the ratios that Trotter and Gleser fit to stature.

## Bones

| Part | Shape |
|---|---|
| `HUMERUS` | The head and the tubercles, the shaft, and the flat lower end with the trochlea and the capitulum. |
| `RADIUS` | The head under the capitulum, the bowed shaft and the wide lower end with its styloid. |
| `ULNA` | The olecranon and the coronoid around the trochlea, the tapering shaft, the head and the styloid. |

The forearm is supinated, so the radius lies lateral of the ulna. A cortical shell wraps trabecular bone. `arm_bone_mass` samples the solid on a grid.

## Joint tissues and ligaments

| Part | Role |
|---|---|
| Glenoid labrum | A fibrocartilage ring around the socket's rim. |
| Articular cartilage | Pads on the humeral head, the glenoid, the trochlea, the capitulum and the radial head. |
| Coracohumeral ligament | From the coracoid to the greater tubercle. |
| Glenohumeral ligaments | The superior, middle and inferior bands of the capsule. |
| Ulnar collateral ligament | From the medial epicondyle to the coronoid and the olecranon. |
| Radial collateral ligament | From the lateral epicondyle to the annular ligament. |
| Annular ligament | A ring around the radial neck. |
| Interosseous membrane | A thin sheet between the radius and the ulna. |

## Muscles

| Group | Muscles |
|---|---|
| Shoulder | Deltoid, supraspinatus, infraspinatus, teres minor, subscapularis, teres major, coracobrachialis. |
| Arm | Biceps brachii, brachialis, triceps brachii. |
| Forearm, front | Pronator teres, flexor carpi radialis, palmaris longus, flexor carpi ulnaris, the two finger flexors, flexor pollicis longus, pronator quadratus. |
| Forearm, back | Brachioradialis, the two radial wrist extensors, extensor digitorum, extensor digiti minimi, extensor carpi ulnaris, anconeus, supinator. |
| Thumb and index | Abductor pollicis longus, extensor pollicis brevis and longus, extensor indicis. |

A muscle is one or more sweeps of elliptical stations: a head, a belly and a tendon. Each station is authored on the scapula or the clavicle, or on the upper arm, the forearm or the hand. A forearm muscle that ends on a wrist bone carries its tendon there. The long tendons to the fingers are the hand's. Belly radii scale with athleticism; tendon radii do not.

## Vessels, nerves and lymph

The axillary artery continues the torso's subclavian artery through the armpit. It becomes the brachial artery, which divides at the elbow into the radial and the ulnar arteries. Two brachial veins follow the artery, and the axillary vein becomes the subclavian vein. The cephalic vein climbs the lateral side and the basilic vein the medial side. The median cubital vein joins them across the front of the elbow.

The axillary, musculocutaneous, radial, median and ulnar nerves leave the torso's brachial plexus in the armpit. The radial nerve spirals behind the humerus and divides at the elbow. The median nerve runs through the carpal tunnel. The ulnar nerve passes behind the medial epicondyle.

The medial collecting vessels follow the basilic vein to the cubital nodes, then to the axillary nodes. The lateral ones follow the cephalic vein to the deltopectoral nodes. Mass uses the physical radius. The mesh uses a wider display radius for the thinnest branches.

## Skin and hair

The arm's skin uses the leg's method. See [Integument](Integument#envelope). The loft runs from just below the wrist to the top of the deltoid. For a man the fat is 6 mm over the upper arm and 4 mm over the forearm. For a woman it is 12 mm and 7 mm.

The muscles on the scapula are left to the torso's skin. So is anything more than 4 cm in from the shoulder joint's center. `add_body` joins both arms' skins to the torso's in a smooth union. The hand's skin reaches up over the lower forearm, so no gap shows at the wrist.

Eight shafts stand for the hair of the upper arm, and eight for the forearm's. Each shaft rises from the skin and lies down the arm.

## Examples

`examples/arm.mojo` draws a six-foot male right arm and hand twice and writes `out/arm.png`. The left copy shows bones, joint tissues and muscles. The right copy shows the skin and the hair. The program also prints the mass of several arm parts.

```bash
.venv/bin/mojo run -I . examples/arm.mojo out/arm.png
```
