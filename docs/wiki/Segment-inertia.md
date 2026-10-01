# Segment inertia

`segment_inertia` returns the mass, the center of mass and the inertia tensor of a thigh, a shank or a foot. These are estimates for the authored template. They are not validated inertial properties of a real person.

The module is `extensions/humanoid/skeleton/limb/inertia.mojo`. This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.limb.inertia import THIGH, segment_inertia
from units.si import FOOT, KILOGRAM, KILOGRAM_SQUARE_METER, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var thigh = segment_inertia(person, THIGH)
thigh.mass.to(KILOGRAM)
thigh.xx.to(KILOGRAM_SQUARE_METER)
```

`segment` is `THIGH`, `SHANK` or `FOOT_SEGMENT`. A bare integer is a compile error. `side` picks `RIGHT` or `LEFT`. `step` is the grid cell, 2 mm through 20 mm, 5 mm by default.

The result lives in the leg frame. The origin is the tibiofemoral joint line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

| Member | Meaning |
|---|---|
| `mass` | The segment's mass. |
| `center` | The center of mass, in meters. |
| `xx`, `yy`, `zz` | The moments of inertia about the center of mass, along the frame's axes. |
| `xy`, `xz`, `yz` | The off-diagonal entries of the tensor: minus the products of inertia. |
| `length` | Joint center to joint center, or heel to toe for the foot. |
| `gyration(moment)` | The radius of gyration of one moment. |

## Method

The integral runs over the one skin of the limb. See [Integument](Integument#one-skin-for-a-limb). Each grid cell takes the density of what fills it.

| Fill | Density |
|---|---|
| The dermis | 1.10 g/cm³, `skin_tissue` |
| Cortical or trabecular bone | The bone's apparent density |
| Marrow | 0.92 g/cm³: adult yellow marrow is mostly fat |
| A muscle belly | 1.06 g/cm³, `muscle_tissue` |
| A tendon | 1.12 g/cm³, `tendon_tissue` |
| Everything else | 0.92 g/cm³, `adipose_tissue` |

Knee tissues, foot ligaments, vessels, lymphatics and nerves count as fat. Their volume is small, and their densities lie within a fifth of fat's.

The segments follow de Leva (1996). Horizontal planes through the hip joint's center, the knee's and the lateral malleolus cut the limb. The knee's center is the middle of the femoral condyles.

## Values

A six-foot untoned male at a 5 mm step:

| Segment | Mass | Center of mass | Radii of gyration, across and along |
|---|---|---|---|
| Thigh | 9.9 kg | 45% of its length from the hip | 29% and 14% of its length |
| Shank | 5.5 kg | 45% from the knee | 29% and 10% |
| Foot | 1.5 kg | 42% from the heel | 24% and 12% |

De Leva reports 41%, 45% and 44% for the three centers, and radii of 33% and 15%, 25% and 10%, and 26% and 12%. The centers and the radii agree within a few points. The shank is heavy against the thigh: 0.55 of it, where de Leva reports 0.31. The calf and the ankle are still fuller than a typical man's.

## Limits

Stature must lie in 1.2 m through 2.5 m. `Sex` must be `MALE` or `FEMALE`. `BodySide` must be `RIGHT` or `LEFT`. This integral covers only the thigh, shank and foot. It does not return whole-body mass or inertia.

For engineering use, validate the geometry, tissue assignments and segment boundaries against the intended subject and task. Check grid convergence at more than one step size. A nonzero result or a passing rendering test does not establish physical accuracy.

The skin loft is a geometric envelope. It is not a measured tissue boundary. Small tissues use the density approximations listed above. Per-part solids can overlap. Do not sum their mass reports to estimate whole-body mass. The model has no constitutive law, muscle activation, joint-contact solver or uncertainty estimate.

Animation, facial shape changes and mesh simplification do not update this integral. Keep the anatomical spec and physical model separate from visual meshes. Do not compute physical properties from diagrammatically widened vessels, baked textures or a game mesh.
