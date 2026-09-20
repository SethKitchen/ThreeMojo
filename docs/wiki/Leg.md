# Leg

`assemble_leg` places the femur, tibia, fibula, patella, the knee tissues and the named muscles in one connected frame.

![A six-foot male right leg turns, with bones, knee tissues and muscles connected](out/leg.png)

`extensions/humanoid/skeleton/leg/assembly.mojo` stores the origin of each bone frame in the leg frame. The knee tissues and the muscles already live in that frame. See [Femur](Femur), [Tibia](Tibia), [Fibula](Fibula), [Patella](Patella), [Knee](Knee) and [Muscles](Muscles).

This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.assembly import assemble_leg, add_leg
from extensions.humanoid.skeleton.leg.contents import BONES, MUSCLES, BOTH
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
var pose = assemble_leg(person)
var hip = pose.hip_center()
```

`side` picks `RIGHT` or `LEFT`. A right leg is the default.

The origin is the tibiofemoral joint line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

The distal femoral condyle surface sits at plus the femoral cartilage thickness. The tibial eminence sits at minus the tibial cartilage thickness. The fibular head sits just lateral and slightly distal of the tibial lateral condyle. The patella sits just anterior of the trochlea.

`add_leg` attaches the selected layers under a parent node. Pass `contents=BONES`, `contents=MUSCLES` or `contents=BOTH`. Both is the default.

`HumanoidSpec` stores stature, sex and athleticism. A two-argument spec uses untoned muscle.

## Pose

`LegAssembly` holds each bone's dimensions, the knee dimensions, the muscle dimensions, and four origins.

| Member | Meaning |
|---|---|
| `femur_origin` | Femur mid-shaft in the leg frame. |
| `tibia_origin` | Tibia mid-shaft in the leg frame. |
| `fibula_origin` | Fibula mid-shaft in the leg frame. |
| `patella_origin` | Patella centroid in the leg frame. |
| `hip_center()` | Femoral head. |
| `ankle_center()` | Tibial plafond. |

A left leg mirrors a right leg across the body midline.

## Examples

`examples/leg.mojo` draws one six foot male right leg and writes `out/leg.png`. Run it with:

```bash
.venv/bin/mojo run -I . examples/leg.mojo out/leg.png
```

`examples/legs.mojo` draws both legs. Femoral heads sit at plus and minus ten centimeters. It writes `out/legs.png`.

![Both six-foot male legs turn with bones and muscles, hips set ten centimeters from the midline](out/legs.png)

Run it with:

```bash
.venv/bin/mojo run -I . examples/legs.mojo out/legs.png
```
