# Lymph

`lymph_mesh` builds a named lymph-node group or trunk from stature, sex and athleticism. Nodes are blended spheres. Trunks are tapered tubes.

![A six-foot male right leg turns with bones, lymph nodes and lymphatic trunks](out/lymph.png)

The solids live in `extensions/humanoid/skeleton/leg/lymph/`. `add_leg` can draw them with `LYMPH`. See [Leg](Leg).

This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.contents import BONES, LYMPH
from extensions.humanoid.skeleton.leg.lymph.dimensions import INGUINAL_NODES
from extensions.humanoid.skeleton.leg.lymph.geometry import lymph_mesh
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var nodes = lymph_mesh(person, INGUINAL_NODES)
```

`side` picks `RIGHT` or `LEFT`. A right leg is the default.

The solids live in the leg frame. The origin is the tibiofemoral joint line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

## Named parts

The labeled set is the inguinal nodes, the popliteal nodes, a superficial trunk and a deep trunk.

| Part | Role |
|---|---|
| `INGUINAL_NODES` | Three nodes near the inguinal analog. |
| `POPLITEAL_NODES` | Three nodes in the popliteal fossa. |
| `SUPERFICIAL_LYMPHATICS` | Medial trunk beside the great saphenous vein. |
| `DEEP_LYMPHATICS` | Deep trunk beside the femoral and popliteal vessels. |

Paths and radii are authored ratios of stature. They are template parameters.

`is_node_group` returns True for the inguinal and popliteal clusters.

## Tissue

`lymph_tissue()` holds wet density 1.01 g/cm³ as a named near-water template. Water fraction is 0.95. Compressive modulus is 0.02 MPa. Poisson's ratio is 0.45.

Water fraction is metadata. Mass uses wet density times envelope volume. Do not scale by one minus water fraction again.

These values are named research metadata. This extension does not implement a constitutive model.

## Mass

```mojo
from extensions.humanoid.skeleton.leg.lymph.mass import lymph_mass
from units.si import GRAM

var report = lymph_mass(person, INGUINAL_NODES)
report.mass.to(GRAM)
```

## Example

`examples/lymph.mojo` draws one six foot male right leg. The layers are bones and lymph. It writes `out/lymph.png`. Run it with:

```bash
.venv/bin/mojo run -I . examples/lymph.mojo out/lymph.png
```
