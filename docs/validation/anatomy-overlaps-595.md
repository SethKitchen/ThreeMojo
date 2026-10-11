# Canonical anatomy overlaps (#595)

No bone, knee or neighboring-spine pair of the canonical template now has a sampled common interior at 5, 3 or 2 mm. Before the repair, 55 pairs had one. Five zero-volume interface rules removed them. No rule changes a measured or cited input. This is template geometry evidence. It is not clearance, biomechanical validation or a clinical or engineering acceptance.

The lower-limb tissue pairs of #596 are outside this work. The template report retains 329 of their findings, unallowlisted.

## Source and scope

The spec is the canonical male, 1.8288 m, right side, untoned, template genome. The grids are 5, 3 and 2 mm. The tool checks all 532 legacy pairs at each grid: 435 bone pairs, 30 knee pairs and 67 neighboring-spine pairs. It tracks the 36 pairs that #595 lists and each pair with a sampled common interior.

- Compiler: `Mojo 1.1.0 (8189361e)`, flags `--Werror --num-threads 1 -I .`
- Unrepaired localization: `anatomy-overlaps-595-before.json`, produced at commit `58b181c`
  - Source SHA-256: `d984741bb8496a606e68649a5f6428107baa195e0aaca99ddf470985fdf06529`
  - File SHA-256: `fd1f2d1de0c62b4a8a78a69cf0ec8a099da542c6958441c71f68fcb5a1aeb03e`
  - That commit changes no anatomy. Its template-report measurements equal those of `058cbbc`.
- Repaired evidence: `anatomy-overlaps-595.json` and `anatomy-template-report.json`. Both record the current source digest. `tools/test_anatomy_overlaps.py` refuses a stale binding.

A probe digest identifies one build. Another machine can produce different binary bytes.

## Reproduce

Run from the repository root with pinned Mojo 1.1.0:

```sh
python3 tools/anatomy_validity.py --build --output .cache/anatomy-report.json
python3 tools/anatomy_overlaps.py --output .cache/anatomy-overlaps.json
python3 -m unittest discover -s tools -p 'test_anatomy_*.py'
```

The second command reuses the probe that the first command built. To reproduce the unrepaired localization, check out `58b181c` and run the same commands.

## What the localization records

For each tracked pair and grid, the tool repeats `diagnose_pair` and records:

- The sample count, the common-interior count and the sampled volume
- The witness point: the cell center with the smallest `max(first, second)` field value
- The box of common-interior cell centers
- A refined point and both field values there. Two local cubes around the witness find it, at one sixteenth and one 256th of the grid width

A negative refined value is a point inside both fields. The fields are signed by construction, so the sign is exact up to float32 roundoff. The value is not a penetration depth. The refinement is local. A nonnegative value does not prove clearance elsewhere.

## Findings before the repair

| Grid | Bone pairs | Knee pairs | Spine pairs |
|---|---|---|---|
| 5 mm | 21 | 14 | 1 |
| 3 mm | 28 | 17 | 5 |
| 2 mm | 33 | 17 | 5 |

Every one of the 55 pairs has a refined point at least 0.6 mm inside both fields. None is a roundoff artifact. The 5 mm grid missed 19 pairs. These are the proximal tibiofibular joint, four more tarsal, tarsometatarsal and intermetatarsal contacts, seven toe joints, four cervical pillar pairs and three knee tissue pairs.

The C2/C3 grid witness of −1.15e-6 m was a grid artifact, not near-contact. The refined point lies 2.5 mm inside both fields, 15.5 mm to each side of the midline, at the articular pillars. The 3 and 2 mm grids sample 12 and 34 common-interior cells there.

Examples from the issue, at 5 mm (sampled cells, refined value at the deepest grid):

- Tibia/talus: 14 cells, −3.0 mm, at the talar dome under the plafond; the 5 and 3 mm witnesses lie at the medial malleolus
- Medial cuneiform/first metatarsal: 17 cells, −5.9 mm, at the tarsometatarsal joint
- Femur/MCL: 28 cells, −6.7 mm, beside the authored femoral attachment
- Tibia/LCL: 2 cells, −2.0 mm, where the LCL band passes the lateral tibial condyle

The JSON file gives the witness point, hit box and refined point of each pair at each grid.

## Classification

Each class is a judgment about the authored representation. No class is a measured biological tolerance.

- **Unintended articular interior** (38 pairs). Two bones meet at a joint. Real bones there have articular surfaces, and the template has no joint space. This covers 31 foot joints, the talocrural joint, the proximal tibiofibular joint and the five cervical pillar pairs C2/C3 through C6/C7.
- **Unintended layer interior** (8 pairs). Cartilage or a meniscus lies on a bone or on the cartilage. Femur, tibia and patella with the cartilage; femur with each meniscus; tibia with the medial meniscus; the cartilage with each meniscus.
- **Attachment representation** (4 pairs). A ligament end lies at its authored attachment landmark inside a bone: femur/MCL, femur/LCL and fibula/LCL. The deep MCL attaches to the medial meniscus. The template has one MCL band, so MCL/medial meniscus is in this class too. The attachment is real anatomy. The shared volume is not.
- **Unintended path interior** (5 pairs). A ligament passes through a field that it does not attach to at that place. Tibia/MCL lies at the joint line, far above the tibial attachment at −52 mm. The LCL does not attach to the tibia or the lateral meniscus. Both collaterals pass through the cartilage lens.

## Repair

No positive-volume allowance was justified, so none was added. Each rule makes the later field give way to the earlier one. The two fields then share a zero-thickness interface and no interior. `anatomy-provenance.json` lists the rules under `interface_rules`.

| Rule | Pairs | What changes |
|---|---|---|
| `foot_articulation_precedence` | 31 | A foot bone gives way to each articulating foot bone before it in `named_foot_bones`. That is the segment accounting's bone order. `foot_articulations` lists 36 joints. |
| `talus_yields_to_tibia` | 1 | The talus gives way to the placed tibia. |
| `fibula_yields_to_tibia` | 1 | The fibula gives way to the placed tibia. |
| `knee_tissue_precedence` | 17 | Knee tissues give way to the four leg bones, then to the cartilage, then to the menisci. |
| `cervical_pillar_endplane_extent` | 5 | Each rounded cervical pillar ends at its body endplane levels. Neighboring pillars then keep the disc height apart. |

The cervical rule shortens an authored primitive. The other four rules clip a field and change no landmark, radius or thickness. The cited cartilage thicknesses are unchanged. The removed cartilage was the part of the authored lens inside the bone. A collateral end still lies at its authored attachment landmark.

The foot rule follows the accounting order and not a bisector. The earlier bone keeps its whole authored solid. The tibia precedes the talus and the fibula in the same order.

## Results after the repair

At 5, 3 and 2 mm, no legacy pair has a sampled common interior. Each bone and knee issue pair has a refined value from 0 to 2.9e-8 m: the fields meet at a surface. C2/C3 has a refined value of 2.0 mm: the pillars now keep the disc height apart. The template report has no bone, knee or spine finding. All 23 body/disc endplane checks pass. All independent controls pass.

Native tests sample each interface. `test_foot.mojo` checks every listed joint on both sides at 2 mm, and the talus against the tibia. `test_fibula.mojo` checks the proximal tibiofibular joint at 1 mm on both sides. `test_knee.mojo` checks all knee tissues against the bones and each other at 3 mm on both sides. `test_head.mojo` checks C2/C3 through C6/C7 at 2 mm.

## Accounting

The thigh and shank estimates are unchanged at all three grids. The foot estimate changes:

| Grid | Mass before | Mass after | Center shift (x, y, z) |
|---|---|---|---|
| 20 mm | 1.49812 kg | 1.52052 kg | −0.20, +0.16, +0.36 mm |
| 10 mm | 1.46288 kg | 1.46848 kg | +0.01, +0.04, −0.08 mm |
| 5 mm | 1.46501 kg | 1.47446 kg | +0.00, +0.07, −0.01 mm |

At 5 mm, cortical mass rises by 12.2 g and trabecular mass falls by 2.7 g. A clipped bone gets the cortical shell rule at its new interface surface. The largest tensor entry changes by 2.5e-5 kg m². All tensor checks pass. The composed lower-limb mass at 5 mm changes from 16.7323 kg to 16.7418 kg.

Per-part masses at 2 mm fall where a part lost a buried or shared volume:

- Knee cartilage: 11.4 g to 8.8 g
- Medial and lateral menisci: 6.1 g to 2.4 g, and 4.5 g to 2.7 g
- MCL and LCL: 11.9 g to 7.3 g, and 4.4 g to 1.4 g
- Foot bones in total: 332.2 g to 326.9 g
- Each of C2 through C7: 1.7 g to 1.9 g less, from the shorter pillars

The fibula changes by less than 0.01 g. A few small bones gain a little mass from the cortical shell rule at their new surface.

## Uncertainty and limits

- No acceptance threshold, biological tolerance or clearance certification is claimed.
- Every interface has zero thickness. Joint space, foot articular cartilage, attachment fibrocartilage and deep and superficial MCL layers are not modeled.
- The precedence order is an accounting rule, not a measured articular surface.
- An interface between differently placed frames is exact only to float32 coordinate roundoff. The largest refined value at a clipped interface here is below 2.9e-8 m.
- No sampled hit does not prove no overlap. A refinement is local to the grid witness.
- The tissue pairs of #596 keep 329 unallowlisted findings. Muscle, ligament, vessel, nerve and lymphatic interfaces are not classified here.
- Whole-body, dynamic, posed and visual geometry remain outside this evidence.
