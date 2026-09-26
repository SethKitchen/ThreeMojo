# Integument

`skin_mesh` fits skin around every modeled leg system. `hair_mesh` places representative shafts directly on that derived surface.

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

## Envelope

`SkinField` first builds the bones, knee tissues, muscles, vessels, lymphatics and nerves. It does not use an independent stocking silhouette.

The field collects actual primitive stations in ten transverse slabs from the iliac landmark to the ankle. Each fitted section encloses those stations.

Smooth elliptical segments join the fitted sections. This removes gaps between structures while retaining the measured anatomical extents.

The male template adds 7.3 mm over the thigh and 5.5 mm over the calf. The female template adds 15.0 mm and 11.1 mm.

The knee interpolates those values. These measured means represent subcutaneous tissue over the modeled fascia.

Tests require every vessel, lymphatic route and nerve station to lie below the fitted skin. Hair roots use ray projection onto the final surface.

## Hair

`THIGH_HAIR` spans the hip-to-knee axis. `CALF_HAIR` spans the knee-to-ankle axis.

Each group samples six circumferential directions. This avoids treating one strip of skin as the normal distribution.

The physical field uses a 29 μm thigh diameter and a 42 μm calf diameter. Hair mass uses analytic capsule volume at these dimensions.

The mesh uses an explicitly diagrammatic radius because a 320 by 240 raster cannot show a 29 μm shaft. The six shafts do not represent density.

Lower-limb hair distribution varies between people. The groups demonstrate rooted geometry and do not define a population pattern.

## Tissue

`skin_tissue()` holds wet density 1.10 g/cm³ as a named dermis template. Water fraction is 0.70. Compressive modulus is 0.20 MPa. Poisson's ratio is 0.45.

`hair_tissue()` holds wet density 1.32 g/cm³ as a named keratin template. Water fraction is 0.12. Longitudinal modulus is 2000 MPa. Poisson's ratio is 0.35.

The dermal shell is 1.8 mm thick. Skin mass samples only that shell, not the full volume inside the leg.

Water fraction is metadata. Mass uses wet density times tissue volume. Do not scale by one minus water fraction again.

These values are named research metadata. This extension does not implement a constitutive model.

## Sources

- [Extremity skin, fat and muscle reference data](https://www.nature.com/articles/sdata2018193)
- [Anterior-thigh subcutaneous and fascia thickness](https://www.mdpi.com/2409-9279/2/3/58)
- [Sex-specific thigh and calf fat thickness](https://doi.org/10.2399/ana.14.037)
- [Healthy-adult skin thickness by body site](https://pmc.ncbi.nlm.nih.gov/articles/PMC9838783/)
- [Hair follicle size by body site](https://doi.org/10.1046/j.0022-202x.2003.22110.x)
- [Lower-limb terminal-hair patterns](https://doi.org/10.1002/ajpa.1330290115)

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
