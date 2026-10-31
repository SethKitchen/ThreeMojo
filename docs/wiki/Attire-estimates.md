# Attire estimates

These functions estimate what an outfit weighs, where it weighs, what it costs to walk in, what it covers and what it stops. They are template estimates for a game. Each constant has an `Evidence` grade and a source. The humanoid's engineering use stays refused. See [Humanoid fidelity](Humanoid-fidelity).

```bash
.venv/bin/mojo run -I . tools/attire_report.mojo --outfit knight
```

This is not a three.js port. The code is in `extensions/attire/estimate.mojo`.

## Mass

`garment_mass(piece, fabric)` is a garment's area times its fabric's areal density. A garment weighs its whole shell, the parts that the garments over it hide too. `dress` keeps each whole shell in `Dressed.shells`.

Mail's areal density is set so a hauberk on the six-foot template weighs 9.3 kg. That is the weight of a 15th-century hauberk at the Cleveland Museum of Art. Plate is 2 mm of steel at 7,850 kg/m³.

`worn_tallies(outfit, dressed)` splits each triangle's mass among the joints by its skin weights. It gives one `InertiaTally` per joint, at rest, in the pelvis frame. Add them to the body's own segments with `InertiaTally.add`. `outfit_mass(tallies)` gives the total.

On the template, the `knight` outfit weighs about 40 kg. Askew, Formenti and Minetti give 30 to 50 kg for a field harness.

## Locomotion cost

`locomotion_cost(tallies, body)` estimates the metabolic cost of walking in an outfit, as a multiple of walking unloaded.

| Where the load is | Cost per unit of its share of body mass |
|---|---|
| trunk and head | 1.0 |
| arms | 1.0 |
| legs | 4.5 |

A load on the legs costs more than one on the trunk, as Askew, Formenti and Minetti found. The coefficients are a design choice. They are set for a 40 kg harness on a 75 kg man, 30 percent of it on the legs. Walking in it costs about 2.1 times as much. That is the low end of the study's 2.1 to 2.3 for walking.

## Coverage

`coverage(skin, rig, outfit)` gives the share of each body region's skin that an outfit covers, by area. Pass the skin before `dress` changes it. A region with no skin on that mesh has zero; the body mesh has no hands, which are meshes of their own.

## Protection

`protection(outfit, rig, joint, along, blow)` passes a blow's energy through the layers over one point, from the outside in. The blow lands on a joint's bone, a fraction `along` of the way down it. A garment is a layer there when it covers that point at least by half. Each layer takes the energy it needs to be pierced. The blow stops in the first layer that takes all it has left.

| Fabric | Energy to pierce | Grade | Source |
|---|---|---|---|
| `LINEN` | 5 J | design | textile practice |
| `WOOL`, `SILK` | 6 J | design | textile practice |
| `VELVET` | 8 J | design | textile practice |
| `LEATHER` | 20 J | design | textile practice |
| `PADDING` | 40 J | from text | Williams |
| `MAIL` | 80 J | from text | Williams |
| `PLATE` | 175 J at 2 mm, with the square of the thickness | from text | Williams |
| `STRAW` | 3 J | design | textile practice |
| `FELT` | 10 J | design | textile practice |
| `FUR` | 15 J | design | textile practice |

Alan Williams's tests give 60 to 130 J for a hand blow and about 120 J for an arrow through mail over a padded jack. They give about 55 J at 1 mm and 175 J at 2 mm for mild steel plate. The square law is fitted to 2 mm, so it gives about 44 J at 1 mm. Secondary sources disagree on some of these figures. Check them against the original before you rely on them.

`Protection` holds the `BlowOutcome`, `STOPPED` or `PIERCED`, the garment that stopped the blow, and the energy left.

## Noise and visibility

`noise(outfit)` and `visibility(outfit)` are zero-through-one hooks for a game's stealth, as Kingdom Come: Deliverance has them.

- Noise: plate rings at 0.5, mail rattles at 0.3, leather creaks at 0.06, padding at 0.03, and cloth at 0.01. The sum is held to one.
- Visibility: the outermost garment of each slot shows. Its primary dye's brightness counts, and polished plate adds 0.3.

## The report

`attire_report` gathers every estimate for one dressed outfit into one record. `tools/attire_report.mojo` builds the six-foot template, dresses it, and prints the record as JSON. The options are `--outfit`, `--file`, `--triangles` and `--body-kg`. The record says `"template_estimate": true` and gives each garment's grade and source.

## Sources

- Askew, Formenti and Minetti, "Limitations imposed by wearing armour on Medieval soldiers' locomotor performance", Proc. R. Soc. B, 2012.
- Alan Williams, "The Knight and the Blast Furnace", 2003, and his tests as quoted by later writers.
- Lazar and Kraner, a study of the thickness of eight breastplates, 2019.
- The Cleveland Museum of Art, hauberks of the 15th century.

## Tests

`tests/test_attire_estimate.mojo` covers this page.
