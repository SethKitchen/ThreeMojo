# Leg

`assemble_leg` places the femur, tibia, fibula, patella, the knee tissues and the named muscles in one connected frame. `add_leg` can also attach vessels, lymph, nerves, skin and hair.

![A six-foot male right leg turns, with bones, knee tissues and muscles connected](out/leg.png)

`extensions/humanoid/skeleton/leg/assembly.mojo` stores the origin of each bone frame in the leg frame. The knee tissues and the later layers already live in that frame. See [Femur](Femur), [Tibia](Tibia), [Fibula](Fibula), [Patella](Patella), [Knee](Knee), [Muscles](Muscles), [Vessels](Vessels), [Lymph](Lymph), [Nerves](Nerves) and [Integument](Integument).

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

`add_leg` attaches the selected layers under a parent node. Pass `contents=BONES`, `contents=MUSCLES` or `contents=BOTH`. Combine layers with `plus`. Both is the default.

| Value | Draws |
|---|---|
| `BONES` | Four bones and five knee tissues. |
| `MUSCLES` | The labeled muscles and three connective-tissue solids. |
| `VESSELS` | Arteries and veins. |
| `LYMPH` | Lymph nodes and trunks. |
| `NERVES` | Named peripheral nerves. |
| `SKIN` | Skin envelope. |
| `HAIR` | Thigh and calf hair shafts. |
| `BOTH` | Bones, knee tissues and muscles. |
| `INTEGUMENT` | Skin envelope and hair shafts. |
| `ALL` | Every named layer. |

A bare integer is a compile error. Skin hides the inner layers when drawn with them. Use `INTEGUMENT` for skin and hair. Use `BONES.plus(VESSELS)` for a vessel gallery.

The skin layer fits cross-sections around every modeled entity. Tests require every vessel, lymphatic route and nerve station to remain below that surface.

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

## Ankle

`ankle_center()` returns the tibial plafond in the leg frame. That point is the origin of the foot. Pass it as `origin` to `add_foot`. See [Foot](Foot).

## Limb

`examples/limb.mojo` draws one right leg and its foot, twice. The left copy has bones and muscles and no skin. The right copy is the skin envelope. The foot uses `ankle_center()` as its origin. The picture is `out/limb.png`.

![A six-foot male right leg and foot turn twice, once open and once in skin](out/limb.png)

Run it with:

```bash
.venv/bin/mojo run -I . examples/limb.mojo out/limb.png
```
