# Integument

`skin_mesh` builds the skin envelope of one leg. `hair_mesh` builds a named cluster of short shafts on the thigh or the calf.

![A six-foot male right leg turns as a skin envelope with short hair](out/integument.png)

The skin solid lives in `extensions/humanoid/skeleton/leg/skin/`. The hair solids live in `extensions/humanoid/skeleton/leg/hair/`. `add_leg` can draw them with `SKIN`, `HAIR` or `INTEGUMENT`. See [Leg](Leg).

This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.contents import INTEGUMENT
from extensions.humanoid.skeleton.leg.hair.dimensions import THIGH_HAIR
from extensions.humanoid.skeleton.leg.hair.geometry import hair_mesh
from extensions.humanoid.skeleton.leg.skin.geometry import skin_mesh
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE)
var envelope = skin_mesh(person)
var shafts = hair_mesh(person, THIGH_HAIR)
```

`side` picks `RIGHT` or `LEFT`. A right leg is the default.

The solids live in the leg frame. The origin is the tibiofemoral joint line. Plus y is proximal. Plus x is body-right. Plus z is anterior.

The envelope is a stocking around the glute, thigh, knee and calf. Athleticism scales the radii. Toned skin is thicker.

Hair shafts are authored thicker than live hair so the isosurface can hold them. `THIGH_HAIR` sits on the anterior thigh. `CALF_HAIR` sits on the posterior calf.

## Tissue

`skin_tissue()` holds wet density 1.10 g/cm³ as a named dermis template. Water fraction is 0.70. Compressive modulus is 0.20 MPa. Poisson's ratio is 0.45.

`hair_tissue()` holds wet density 1.32 g/cm³ as a named keratin template. Water fraction is 0.12. Longitudinal modulus is 2000 MPa. Poisson's ratio is 0.35.

Water fraction is metadata. Mass uses wet density times envelope volume. Do not scale by one minus water fraction again.

These values are named research metadata. This extension does not implement a constitutive model.

## Mass

```mojo
from extensions.humanoid.skeleton.leg.hair.mass import hair_mass
from extensions.humanoid.skeleton.leg.skin.mass import skin_mass
from units.si import GRAM

var skin_report = skin_mass(person)
var hair_report = hair_mass(person, THIGH_HAIR)
skin_report.mass.to(GRAM)
```

## Example

`examples/integument.mojo` draws one six foot male right leg. The layers are skin and hair. It writes `out/integument.png`. Run it with:

```bash
.venv/bin/mojo run -I . examples/integument.mojo out/integument.png
```
