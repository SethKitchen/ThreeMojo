# Animal anatomy

Each procedural animal has a template skeleton, Hill-type muscles, sampled segment mass and inertia, and a kinematic gait. You can inspect it in game mode or in engineering display mode. The quantities carry SI unit types. These models are not validated for engineering, clinical or animal-care decisions.

The source grades say how far each reference value was checked against its source. `model_evidence()` returns `DESIGN` for the selected body template, calibration and generated muscles. A checked source value does not validate the sculpt, its tissue assignment or a different species.

![A horse, a dog and a cheetah walk in game mode on the left and in engineering mode on the right](out/animal_anatomy.png)

## Call it

```mojo
from extensions.anatomy.mode import ENGINEERING_MODE
from extensions.animals.anatomy.engineering import (
    calibrate,
    calibrated_animal,
    calibrated_mass,
)
from extensions.animals.anatomy.muscles import species_muscles
from extensions.animals.anatomy.render import materials_in_mode, mesh_in_mode
from extensions.animals.anatomy.stance import standing_loads
from extensions.animals.build import create_animal
from extensions.animals.gait import walk_pose
from extensions.animals.options import Variant, animal_options
from extensions.animals.registry import HORSE

# The selected body parameters are an explicit template estimate.
var cal = calibrate(HORSE, Variant(-1), allow_estimates=True)
var base = create_animal(HORSE, animal_options(3))
var horse = calibrated_animal(base, cal)
var mass = calibrated_mass(base, cal)
var muscles = species_muscles(horse.rig, HORSE, mass.total().mass)
var loads = standing_loads(horse, mass, muscles)
var pose = walk_pose(horse.rig, 0.25)
var meshes = mesh_in_mode(horse, muscles, pose, ENGINEERING_MODE)
var materials = materials_in_mode(ENGINEERING_MODE)
```

`examples/animal_anatomy.mojo` renders a horse, a dog and a cheetah in both modes. It also prints their mass, center of mass, stride and standing joint loads. `make out/animal_anatomy.png` runs it.

## Game mode and engineering mode

`AnatomyMode` names the two modes. It lives in `extensions/anatomy/mode.mojo`, so other subjects can use it.

| | Game mode | Engineering mode |
|---|---|---|
| Meshes | One painted mesh | Skin, skeleton and muscles |
| Surface | Painted coat, fur normals, baked occlusion | Flat tissue colors, no noise, no baked light |
| Coat | Drawn | Left out of the skin and of the mass |
| Muscles | Bellies bulge in the sculpt | Each belly is an ellipsoid of the muscle's volume |
| Numbers | Visual template | Inspectable SI estimates; no validated engineering capability |

`mesh_in_mode` meshes an animal in a mode. `materials_in_mode` gives the materials for each mesh. In engineering mode the skin is translucent, so the skeleton and the muscles show through it.

## Evidence grades

Each literature value carries one of five grades. Most of the muscle, density and Thelen values were read in the table of the paper itself. The code and this page give that table and its page. A value read only in a search-result extract or a secondary source stays at `FROM_TEXT` at best. [Sources that could not be read](#sources-that-could-not-be-read) lists what is still to check.

`SpeciesBody.mass_source` and `length_source` keep the provenance of each reference size. Muscle `share_source` and `fiber_source` keep the reference inputs. The separate `model_evidence()` reports `DESIGN`. Selected representative sizes, cross-species ratios, attachment paths and individualized architecture are modeling choices. That holds whatever the grade of the numbers they start from.

| Grade | Meaning |
|---|---|
| `FROM_ABSTRACT` | The number is in the source's own abstract. |
| `FROM_TEXT` | The number is in the source's body, or in a secondary source that quotes it. |
| `CROSS_CHECKED` | Read in the source's own table, and it agrees with the rest of its row, for example `PCSA = m cos a / (rho L)`. The arithmetic of an extract alone is not enough. |
| `UNVERIFIED` | No source that we read shows the number. |
| `DESIGN` | A modeling choice or a unit conversion, not a measurement. |

`Evidence.is_measured` is True for the first three grades. `Cited` holds a grade and a source key from the reference list below.

## Calibration

The sculpts are visual models. Calibration maps a canonical individual to a selected reference size and mass. Matching a prescribed mass is normalization, not an independent test of accuracy.

The calibration records its species and reference morph. It refuses use on another species or morph and refuses a second calibration of the same individual. A morph value of -1 permits only the coat-only variants that share one reference kind. Every numeric boundary rejects invalid or nonfinite input.

1. `calibrate` builds a canonical individual: an adult male of the published morph.
2. `reference_length` measures an authored analytic envelope landmark, independently of the occupancy grid. For a quadruped mammal, this is the shoulder height. For a bird or a fish, it is the total length. For a frog, a rabbit, a rat, a snake or a spider, it is the body length.
3. The length factor maps this DESIGN landmark to the selected reference length.
4. It samples the scaled sculpt, with the physical coat depth unchanged. This gives `predicted_mass` before normalization. Multiplying the unscaled mass by scale cubed is not equivalent when coat depth is fixed.
5. `Calibration.density_factor` is the selected reference mass over that sampled prediction. At the canonical resolution, the normalized canonical mass equals the target by construction.

`calibrated_animal` scales the sculpt, the rig and the cells. The coat still paints. `calibrated_mass` scales the densities by the density factor. Each segment keeps the share of mass that the geometry gives it. An individual keeps its own size relative to the canonical one, so a juvenile stays small and light.

Every current selected body template has `DESIGN` parameter evidence and requires `calibrate(..., allow_estimates=True)`. A matched morph and measured source values do not bypass this gate. Unmatched morphs and unverified reference inputs also require opt-in. Opt-in permits inspection of a template estimate; it does not mark the result validated. Raw visual and game construction remains available without this calibration opt-in.

An unmatched morph gets its own length factor but no mass correction from a different reference kind. For example, the bear reference describes a black bear. A grizzly has `Calibration.matched` False. `matched` means only that the named reference kind agrees, not that anatomy or accuracy was validated.

### Landmark convention

`reference_length` uses analytic ellipsoid supports and round-cone end spheres. Fins use their polygon vertices and thickness envelope. Lenses use a conservative local rectangle. Carvers and smooth blends do not change this authored envelope. The classification selects withers, body or total-length solids. It does not measure eroded flesh.

The landmark scales consistently with geometry. It is independent of voxel spacing. It is also a DESIGN convention, not proof that the visible surface or a biological landmark has the cited dimension. Voxel-sampled extents are reported separately and can disagree, especially for thin animals.

### What calibration does not establish

The canonical male mass is an input to normalization. It cannot also serve as independent validation. Female and juvenile outputs retain authored geometric proportions. Their agreement with a reference mass does not establish a measured growth or sex-specific model. No accuracy claim or universal sampling tolerance is made here.

### What the calibration predicts

The calibration uses the adult male. An adult female, drawn on her own, then predicts her mass from her geometry alone. This table compares that prediction with the published female mass. As the section above says, agreement is not validation.

The check calibrates each species with `calibrate(id, Variant(-1), allow_estimates=True)`. It draws the female with `animal_options(1, quality=CROWD, sex=FEMALE, age=ADULT)` and the published morph, and weighs her with `calibrated_mass` at 60 cells a reference length.

| Species | Predicted female mass | Published female mass | Ratio |
|---|---|---|---|
| Bear | 61.0 kg | 60 kg | 1.02 |
| Boar | 52.4 kg | 70 kg | 0.75 |
| Cat | 3.26 kg | 3.5 kg | 0.93 |
| Cheetah | 40.9 kg | 30 kg | 1.36 |
| Chicken | 1.40 kg | 1.705 kg | 0.82 |
| Cow | 531 kg | 680 kg | 0.78 |
| Crow | 0.381 kg | 0.43 kg | 0.89 |
| Deer | 49.3 kg | 50 kg | 0.99 |
| Dog | 25.9 kg | 27 kg | 0.96 |
| Eagle | 5.05 kg | 5.2 kg | 0.97 |
| Fish | 0.818 kg | 1.0 kg | 0.82 |
| Fox | 4.97 kg | 5.0 kg | 0.99 |
| Frog | 0.386 kg | 0.30 kg | 1.29 |
| Goat | 50.9 kg | 65 kg | 0.78 |
| Horse | 457 kg | 450 kg | 1.02 |
| Lion | 132 kg | 126 kg | 1.05 |
| Pig | 232 kg | 250 kg | 0.93 |
| Rabbit | 1.67 kg | 1.8 kg | 0.93 |
| Rat | 0.198 kg | 0.25 kg | 0.79 |
| Shark | 1455 kg | 1400 kg | 1.04 |
| Sheep | 67.1 kg | 80 kg | 0.84 |
| Snake | 0.317 kg | 0.5 kg | 0.63 |
| Spider | 23.6 g | 20 g | 1.18 |
| Wolf | 44.1 kg | 45 kg | 0.98 |

Nine species fall within 5 %. The fish, the frog, the rabbit and the snake have one published mass for both sexes. Their rows measure only how the sculpt draws a female. The cheetah's published female is the least certain value: the five weighed cheetahs of Hudson et al. 2011a, Table 1, are males of 27.5 to 32.0 kg and females of 29.5 and 45.5 kg.

## Mass and inertia

`sample_mass` samples the posed sculpt on a grid of cubic cells:

- A cell's share of flesh is `clamp(1/2 - d / h, 0, 1)`, with `d` the signed distance of its center and `h` its side.
- Solids of hair, wool and feathers are left out. The furred surfaces are pulled in by the species' coat depth. The coat reaches at most 30 % of a solid's smallest radius, so a thin leg keeps its flesh.
- Each cell selects the nearest flesh part after that part's coat erosion. It then takes the selected solid's density. It is added to the bone that the solid rides.

`extensions/anatomy/inertia.mojo` sums the cells. Each cell is a cuboid and adds its own inertia, `m w^2 / 12` per axis. The parallel-axis theorem moves the tensor to the center of mass. The humanoid's limb segments use the same tally. The original `extensions.humanoid.skeleton.tissue` and `soft_tissue` import paths re-export the shared types and factories, so existing humanoid callers retain type identity.

The sampler checks primitive indexes, finite geometry and bounded grid dimensions before integer conversion or worker writes. A cone has two radii; its unused third radius does not remove coat erosion. Public tally addition rejects negative mass and invalid cell geometry. The result checks finite SI output and a physically admissible central tensor.

`BodyMass.bone` gives one bone's mass, center of mass and inertia. `BodyMass.total` gives the whole body. `BodyMass.reference` returns voxel-sampled extents. Thin features can be unresolved; a missing or nonpositive extent raises an error. These extents are not used for calibration or dimensional validation. Use `reference_length` for the separately defined template landmark.

### Densities

A mammal's segment takes Dempster's density for the homologous human segment (Dempster 1955, as tabulated in Winter 2009, Table 4.1). Applying human values to a quadruped is a `DESIGN` choice.

| Segment | Density (g/cm^3) |
|---|---|
| Head and neck | 1.11 |
| Thorax | 0.92 |
| Abdomen and pelvis | 1.01 |
| Upper arm | 1.07 |
| Forearm | 1.13 |
| Hand | 1.16 |
| Thigh | 1.05 |
| Leg and tail | 1.09 |
| Foot | 1.10 |

The other body plans take one whole-body density.

| Body plan | Density (g/cm^3) | Grade |
|---|---|---|
| Chicken, plucked | 1.044 | `FROM_TEXT` (Hamershock 1993, Table 3, p. 11) |
| Flying bird, plucked | 0.968 | `DESIGN`: the mean of the eleven wild species of Hamershock 1993, Table 3, p. 11, which range from 0.880 to 1.050 |
| Fish with a swim bladder | 1.00 | `FROM_TEXT` (Lindsey 2010) |
| Frog | 1.00 | `DESIGN`: a near-water whole-body approximation |
| Shark | 1.05 | `UNVERIFIED` |
| Snake | 1.057 | `DESIGN`: 1.13 with 6.5 % of the body lung |
| Spider | 1.05 | `DESIGN` |

Keratin is 1.30 g/cm^3 (McKittrick 2012). Antler 1.8, tooth 2.1 and the eye 1.01 g/cm^3 are `UNVERIFIED`.

## Muscles

`extensions/anatomy/muscle.mojo` is the shared Hill-type muscle.

- `MuscleArchitecture` holds the belly mass, the optimal fiber length, the pennation angle, the tendon slack length, the specific tension and the density.
- `pcsa` is `m / (rho L0)`. `max_force` is the specific tension times the PCSA.
- The force curves are Thelen's (2003), with the young-adult parameters. The passive shape factor is 5 (Appendix, p. 75). The passive strain at `F0` is 0.6 (Table 1, p. 71). The tendon strain at `F0` is 0.04 (p. 71). The code used a shape factor of 4 before the paper was read.
- `isometric_equilibrium` solves the fibers and the tendon at one length.
- `activation_rate` is Thelen's first-order activation.

The default specific tension is 0.3 MPa. The muscle density is 1.06 g/cm^3 (Mendez and Keys 1960).

`animal_muscles` puts the limb muscles of a body plan on an individual's rig. A path starts at an origin, can wrap over via points on any bone, and ends at an insertion. `AnimalMuscle.moment_arms` gives the arm about each crossed joint in any pose. Each arm uses the stretch of the path that spans its joint. A positive arm turns the distal bone backward: it extends the hip and flexes the knee.

### Mammal hind limb

The greyhound's biceps femoris anchors the masses. It is 485 g of a 31.8 kg dog, 1.53 % of body mass a side (`CROSS_CHECKED`). The muscle is in Williams 2008a, Table 1, on page 364, and the dogs' mass is in its Methods, on page 362.

The other muscles keep the rat's ratios to the biceps femoris and the rat's pennation (Eng 2008, Table 1, `CROSS_CHECKED`). The table is on page 2339. In each row, `PCSA = m cos a / (rho L)` with Eng's density of 1.056 g/cm^3 agrees with the published PCSA. Mass scales with body mass, nearly isometrically (Pollock 1994, `FROM_ABSTRACT`).

The optimal fiber length is the rat's share of the segment it lies along. The segment lengths are those of the rat rig: a 41 mm femur and a 46.2 mm tibia.

| Muscle | Mass over the biceps femoris | Fiber length over its segment | Pennation |
|---|---|---|---|
| Biceps femoris | 1 | 0.83 of the femur | 3.6° |
| Rectus femoris | 0.354 | 0.28 of the femur | 25.4° |
| Vastus lateralis | 0.483 | 0.48 of the femur | 10.0° |
| Gastrocnemius, both heads | 0.704 | 0.34 of the tibia | 14.1° |
| Soleus | 0.050 | 0.43 of the tibia | 3.9° |
| Tibialis anterior | 0.248 | 0.36 of the tibia | 12.8° |

A muscle of two or three heads sums their masses. Its fiber length is the mass-weighted harmonic mean of theirs, so its PCSA is the sum of theirs. Its pennation is the mass-weighted mean.

### Mammal fore limb

The greyhound gives the fore limb (Williams 2008b, Table 1, p. 375, seven dogs of 31.4 kg, `CROSS_CHECKED`). The triceps brachii is its long head, because only that head crosses both the shoulder and the elbow. The fiber length is a share of the dogs' humerus, 19.75 cm, or radius, 22.75 cm (Table 3, p. 376, `FROM_TEXT`).

| Muscle | Mass | Share of body mass | Fiber length | Pennation |
|---|---|---|---|---|
| Triceps brachii, long head | 341 g | 1.09 % | 6.5 cm | 31° |
| Biceps brachii | 54.1 g | 0.17 % | 1.8 cm | 41° |
| Supraspinatus | 150 g | 0.48 % | 5.9 cm | 18° |
| Superficial digital flexor | 18.3 g | 0.058 % | 1.2 cm | 41° |

### Species tables

`species_muscles` and `species_specs` put in a species' own table where one exists. `animal_muscles` and `plan_muscles` keep the plan's muscles. A species row gives an absolute fiber length. It scales with the cube root of body mass from the source's mean, as Payne 2005, Table 5, normalizes it.

| Species | Source | Muscles | Grade |
|---|---|---|---|
| Dog | Williams 2008a, Table 1, p. 364 (31.8 kg greyhounds). The soleus is from Hudson 2011a, Table 3, p. 367 (greyhounds of 27.3 kg). | Hind limb | `CROSS_CHECKED` |
| Cheetah | Hudson 2011a, Table 3, p. 367, and 2011b, Table 2, p. 378. The body mass, 33.1 kg, is the mean of the five weighed cheetahs (Table 1). | Hind and fore limb | `FROM_TEXT`: the means of ratios do not give the mean PCSA. The pennation is the greyhound's, `DESIGN`, because the tables give none. |
| Horse | Payne 2005, Table 4, p. 561. The body mass, 510 kg, is the mean of Table 3. | Hind limb | `CROSS_CHECKED` |
| Rat | Eng 2008, Table 1, p. 2339. The body mass, 323 g, is on p. 2337. | Hind limb | `CROSS_CHECKED` |
| Chicken | Hartman 1961, Table 1, p. 45 | Flight muscles | `FROM_TEXT` |
| Crow | Hartman 1961, Table 1, p. 71 | Flight muscles | `FROM_TEXT` |
| Eagle | Hartman 1961, Table 1, p. 43 | Flight muscles | `FROM_TEXT` |

### Other muscles

- Mammal fore limb: the superficial digital flexor's tendon runs behind the carpus and over the sesamoids, so it holds the wrist and the fetlock.
- Bird: the pectoralis is 7.5 % and the supracoracoideus 0.75 % of body mass a side. These are the medians of Hartman 1961, Table 3, p. 89, halved because Hartman weighed both sides (`FROM_TEXT`). The species rows come from Hartman's Table 1. The White Leghorn's pectoral muscles are 10.6 % of body mass (20 birds, p. 45), split 8.78 to 3.50 as in the one bird weighed by muscle. The American crow's are 14.2 % (*Corvus brachyrhynchos pascuus*, 3 birds, p. 71), split as in *Cyanocorax affinis* on the same page. Hartman has no golden eagle, so the eagle takes the mean of five accipitrids on p. 43: a pectoralis of 13.4 % and a supracoracoideus of 0.49 %. The fiber lengths are `DESIGN` shares of the humerus. The supracoracoideus lifts the wing over its pulley, the triosseal canal. The wing beats about the body's long axis.
- Frog: the hind limbs hold 33 % of body mass (James 2008, abstract, `FROM_ABSTRACT` for that number, *Litoria nasuta*). The plantaris is 19.4 % of that (`FROM_TEXT`). The cruralis and the semimembranosus are `DESIGN` shares.
- Fish, shark and snake: `axial_muscles` gives each spine joint a muscle a side. Its mass is a share of its segment's sampled mass. The share is 60 % for a fish (`UNVERIFIED`) and 53 % for a shark (Bernal 2003 for the red muscle). It is 30 % for a snake (`DESIGN`).
- Spider: each femur-patella and tibia-metatarsus joint has one flexor. A spider has no extensor at those joints. Hemolymph pressure extends them: `hemolymph_pressure` gives 6.5 kPa at rest and 65 kPa at a peak (Parry 1959; Anderson 1975). The flexors develop 0.5 MPa (Medler 2002).

The attachment offsets are `DESIGN` choices that give each muscle its known action. The tendon slack length makes the fibers optimal in the standing bind pose.

## Standing loads

`standing_loads` gives the static load on each left limb joint of a standing quadruped:

1. Each foot presses at the middle of its sole.
2. The center of mass splits the weight between the fore and the hind feet.
3. About each joint, the foot's push and every distal segment's downward weight have moments. The muscles must cancel their sum.
4. The muscles that oppose the net moment share one fiber stress. Their tendon force includes the cosine of pennation. The least specific tension among the participating muscles limits the shared stress. Muscle ordering does not change the result.

`JointLoad` gives the moment, the ground lever, the muscle lever, the effective mechanical advantage (Biewener 1989), the stress and the activation. A nonzero demand that its muscles cannot hold at full activation reports `held` False. Zero required moment reports `held` True with zero activation. This does not prove that tendons, ligaments or any other passive structure can supply the missing moment. Those structures are not modeled.

This is a symmetric sagittal-plane estimate. It does not solve lateral balance, contact pressure, tendon compliance or three-dimensional stability.

The moment arms come from `DESIGN` attachments that scale with the segments. So the effective mechanical advantage does not grow with body mass as Biewener's `M^0.26` does.

## Gait timing

`extensions/anatomy/locomotion.mojo` holds dynamic similarity. Animals move alike at equal Froude numbers, `Fr = u^2 / (g h)` (Alexander and Jayes 1983). The stride length is `2.3 Fr^0.3 h` (Alexander 1976, `FROM_TEXT`).

`walk_pose` takes a Froude number. The default 0.25 is a design choice. Reference stride, frequency and speed are dynamic-similarity estimates, not a validated locomotion model.

`walk_stride` caps the visual stride at the shortest reachable two-link stance sweep. The pose compensates root bob at planted feet. The animal walks in place. Its equivalent translation speed is visual stride times reference frequency.

`walk_pose_at` takes a `Duration`, so different animals advance on one physical timeline at their own reference frequencies. The comparison gallery plays once because their periods differ.

Each foot sweeps 70 % of the stride under the body. This duty factor is a `DESIGN` value: Alexander and Jayes 1983 give duty factor against Froude number, but no copy of the paper was readable.

## Bulging bellies

The engineering muscle belly uses its assigned mass and density to define an ellipsoid volume. The game sculpt uses an approximate visual bulge. `flexed` reshapes the tagged solids for a pose.

When a muscle's fibers shorten by a factor `f`, its solids shrink by `f^w` along the muscle and grow by `f^(-w/2)` across it. `w` is 0.5, a `DESIGN` value: the skin and the fat do not bulge. `f` is held to 0.6 to 1.4. The bind pose changes no solid.

Ellipsoid factors have product one. Cone radii change while endpoints stay fixed, so cones and smooth unions do not conserve tissue volume.

`flexed_animal` returns a marked visual-only individual with the reshaped sculpt. Mesh it with the same pose. `sample_mass` and `calibrated_mass` refuse this visual-only geometry. Sample the original calibrated anatomy instead.

## Skeleton

`skeleton_model` draws a round cone along each bone. A mammal's long bones take the measured mid-shaft radius over length. This is half the mid-shaft diameter over the bone length, the mean of five cheetahs and three greyhounds (Hudson 2011a, Table 1, p. 364; Hudson 2011b, Table 1, p. 377; `FROM_TEXT`).

| Bone | Radius over length |
|---|---|
| Femur | 0.0385 |
| Tibia | 0.036 |
| Humerus | 0.0456 |
| Radius | 0.0337 |

One share serves every size, because a long bone's length and diameter scale alike, `M^0.35` and `M^0.36` (Alexander 1979, `FROM_ABSTRACT`). The other bones' shares are `DESIGN` values.

## Physics bodies

`segment_bodies` turns each bone with flesh into a dynamic `RigidBody` for `extensions/physics`. Each body has the sampled mass, center of mass and inertia tensor. `to_physics` turns the sculpt's `+y`-up frame into the physics world's `+z`-up frame. The physics world has no joints yet, so the bodies are the segments of a multibody model.

## Species

All selected masses and reference lengths below are `DESIGN` parameters. The final column records only the grade of the cited source.

| Species | Kind | Selected male, female mass | Selected reference length | Source grade |
|---|---|---|---|---|
| Bear | American black bear | 100, 60 kg | 0.90 m shoulder | `FROM_TEXT` |
| Boar | Central European wild boar | 85, 70 kg | 0.75 m shoulder | `FROM_TEXT` |
| Cat | Domestic cat | 4.5, 3.5 kg | 0.25 m shoulder | `FROM_TEXT` |
| Cheetah | Cheetah | 50, 30 kg | 0.80 m shoulder | `FROM_TEXT` |
| Chicken | White Leghorn | 2.43, 1.705 kg | 0.45 m total | mass `FROM_TEXT` (Hartman 1961, Table 1, p. 45), length `UNVERIFIED` |
| Cow | Holstein-Friesian | 900, 680 kg | 1.47 m shoulder | mass `UNVERIFIED`: Holstein USA gives the cow, 1500 lb, and only an upper bound for the bull. The height is the cow's. |
| Crow | American crow | 0.47, 0.43 kg | 0.45 m total | `FROM_TEXT` |
| Deer | White-tailed deer | 70, 50 kg | 0.90 m shoulder | `FROM_TEXT` |
| Dog | German Shepherd Dog | 35, 27 kg | 0.625 m shoulder | `FROM_TEXT`: the middles of FCI-Standard No. 166, p. 8 |
| Eagle | Golden eagle | 3.7, 5.2 kg | 0.85 m total | `FROM_TEXT` |
| Fish | Rainbow trout | 1.0 kg | 0.45 m total | `FROM_TEXT` |
| Fox | Red fox | 6.5, 5.0 kg | 0.40 m shoulder | `FROM_TEXT` |
| Frog | American bullfrog | 0.30 kg | 0.155 m snout-vent | mass `UNVERIFIED`: the sources found give only an upper bound, 0.5 kg |
| Goat | Saanen dairy goat | 85, 65 kg | 0.94 m shoulder, the buck's | mass `UNVERIFIED`: NSW DPI gives only the doe's minimum, 64 kg |
| Horse | Thoroughbred | 500, 450 kg | 1.62 m shoulder | `FROM_TEXT`. Payne 2005, Table 3, p. 561, weighed five Thoroughbreds of 480 to 600 kg, 1.47 to 1.57 m tall, sex not given. |
| Lion | African lion | 190, 126 kg | 1.15 m shoulder | `FROM_TEXT` |
| Pig | Large White | 300, 250 kg | 0.90 m shoulder | length `UNVERIFIED`. 2068 Large White sows of 100 kg stand 0.614 m (Hong 2021, Table 1). Isometric scaling to 300 kg gives 0.886 m. |
| Rabbit | European rabbit | 1.8 kg | 0.38 m head-body | `FROM_TEXT` |
| Rat | Norway rat | 0.30, 0.25 kg | 0.21 m head-body | `FROM_TEXT` |
| Shark | White shark | 850, 1400 kg | 3.7 m total | `FROM_TEXT` |
| Sheep | Suffolk | 130, 80 kg | 0.70 m shoulder | `FROM_TEXT` |
| Snake | Corn snake | 0.5 kg | 0.87 m snout-vent | `FROM_TEXT` |
| Spider | Mexican redknee tarantula | 12, 20 g | 0.055 m body | `FROM_TEXT` |
| Wolf | Gray wolf | 55, 45 kg | 0.80 m shoulder | `FROM_TEXT` |

## Limits

- The muscle paths are straight lines between attachments and via points. They do not wrap around bone surfaces.
- The tendons are rigid when bellies bulge. The static solve, `isometric_equilibrium`, has an elastic tendon.
- The individual muscle architecture, selected representative body parameters, attachments and coat depths are `DESIGN` values. Source evidence is recorded separately.
- The cheetah takes the greyhound's pennation. The horse and the rat take the plan's fore limb, because their sources have no fore-limb table.
- Birds have flight muscles but no leg muscles.
- The physics world has no joints, so the segment bodies do not yet form a chain
- A normalized total mass does not validate segment fractions, centers, tensors, tissue densities or muscle capacity
- The engineering display grants no validated engineering capability

## Types and checks

Each id, kind and mode is a type with `is_valid`: `AnatomyMode`, `Evidence`, `BodyPlan`, `ReferenceKind`, `BodyTissue` and `Segment`. Every boundary that reads one refuses a value that is not valid. The files in `tests/compile_fail/` prove that a bare integer does not compile.

## Sources that could not be read

These sources are behind a paywall, and no open copy was found. The values that rely on them keep their grade.

- Alexander 1979 and 1981, and Alexander and Jayes 1983, in *J. Zool.* The bone exponents come from the 1979 abstract. The duty factor stays `DESIGN`.
- Sacks and Roy 1982 (cat hind limb) and Lieber and Blevins 1989 (rabbit hind limb), in *J. Morphol.* The cat and the rabbit keep the plan's muscles.
- James and Wilson 2008, in *Physiol. Biochem. Zool.* Only the abstract was read.

Paxton 2010 was read. It measures broiler and junglefowl hind limbs, and the bird plan has no leg muscles, so the code does not use it.

## References

- **Alexander1976**: Alexander, R. McN. Estimates of speeds of dinosaurs. *Nature* 261:129-130, 1976. The stride relation was read as a quotation in later trackway papers.
- **Alexander1979**: Alexander, Jayes, Maloiy and Wathuta. Allometry of the limb bones of mammals from shrews (*Sorex*) to elephant (*Loxodonta*). *J. Zool.* 189:305-314, 1979. Only the abstract was read.
- **Alexander1981**: Alexander, Jayes, Maloiy and Wathuta. Allometry of the leg muscles of mammals. *J. Zool.* 194:539-552, 1981. Not read.
- **AlexanderJayes1983**: Alexander and Jayes. A dynamic similarity hypothesis for the gaits of quadrupedal mammals. *J. Zool.* 201:135-152, 1983. Not read.
- **Anderson1975**: Anderson and Prestwich. The fluid pressure pumps of spiders (Chelicerata, Araneae). *Z. Morph. Tiere* 81:257-277, 1975.
- **Bernal2003**: Bernal, Sepulveda, Mathieu-Costello and Graham. Comparative studies of high performance swimming in sharks I. Red muscle morphometrics, vascularization and ultrastructure. *J. Exp. Biol.* 206:2831-2843, 2003.
- **Biewener1989**: Biewener. Scaling body support in mammals: limb posture and muscle mechanics. *Science* 245:45-48, 1989.
- **Dempster1955**: Dempster. Space requirements of the seated operator. WADC Technical Report 55-159, 1955.
- **Eng2008**: Eng, Smallwood, Rainiero, Lahey, Ward and Lieber. Scaling of muscle architecture and fiber types in the rat hindlimb. *J. Exp. Biol.* 211:2336-2345, 2008. doi:10.1242/jeb.017640. Read in full: Table 1, p. 2339; the rats' mass, p. 2337.
- **FCI166**: Fédération Cynologique Internationale. FCI-Standard No. 166, German Shepherd Dog. Read in full: size and weight, p. 8.
- **Hamershock1993**: Hamershock, Seamans and Bernhardt. Determination of body density for twelve bird species. Technical Report WL-TR-93-3049, Wright Laboratory, 1993. DTIC ADA266452. Read in full: Table 3, p. 11.
- **Hartman1961**: Hartman. Locomotor mechanisms of birds. *Smithsonian Misc. Coll.* 143(1):1-91, 1961. Read in full: Table 1, pp. 43, 45 and 71; Table 3, p. 89; Methods, p. 2.
- **Holstein**: Holstein Association USA, breed history page. Read only as a search-result extract.
- **Hudson2011a**: Hudson, Corr, Payne-Davis, Clancy, Lane and Wilson. Functional anatomy of the cheetah (*Acinonyx jubatus*) hindlimb. *J. Anat.* 218:363-374, 2011. doi:10.1111/j.1469-7580.2010.01310.x, PMC3077520. Read in full: Table 1, p. 364; Table 3, p. 367.
- **Hudson2011b**: Hudson, Corr, Payne-Davis, Clancy, Lane and Wilson. Functional anatomy of the cheetah (*Acinonyx jubatus*) forelimb. *J. Anat.* 218:375-385, 2011. doi:10.1111/j.1469-7580.2011.01344.x, PMC3077521. Read in full: Table 1, p. 377; Table 2, p. 378.
- **James2008**: James and Wilson. Explosive jumping: extreme morphological and physiological specializations of Australian rocket frogs (*Litoria nasuta*). *Physiol. Biochem. Zool.* 81:176-185, 2008. PubMed 18190283. Only the abstract was read.
- **Lindsey2010**: Lindsey, Smith and Croll. From inflation to flotation: contribution of the swimbladder to whole-body density and swimming depth during development of the zebrafish (*Danio rerio*). *Zebrafish* 7:85-96, 2010.
- **McKittrick2012**: McKittrick, Chen, Bodde, Yang, Novitskaya and Meyers. The structure, functions, and mechanical properties of keratin. *JOM* 64:449-468, 2012.
- **Medler2002**: Medler. Comparative trends in shortening velocity and force production in skeletal muscles. *Am. J. Physiol. Regul. Integr. Comp. Physiol.* 283:R368-R378, 2002.
- **MendezKeys1960**: Mendez and Keys. Density and composition of mammalian muscle. *Metabolism* 9:184-188, 1960.
- **NSWDPI**: NSW Department of Primary Industries. Goat breeds: Saanen. Read only as a search-result extract.
- **Parry1959**: Parry and Brown. The hydraulic mechanism of the spider leg. *J. Exp. Biol.* 36:423-433, 1959.
- **Paxton2010**: Paxton, Anthony, Corr and Hutchinson. The effects of selective breeding on the architectural properties of the pelvic limb in broiler chickens: a comparative study across modern and ancestral populations. *J. Anat.* 217:153, 2010. PMC2913024. Read, not used.
- **Payne2005**: Payne, Hutchinson, Robilliard, Smith and Wilson. The pelvic limb anatomy of horses (*Equus caballus*). *J. Anat.* 206:557-574, 2005. PMC1571521. Read in full: Tables 3 and 4, p. 561.
- **Pollock1994**: Pollock and Shadwick. Allometry of muscle, tendon, and elastic energy storage capacity in mammals. *Am. J. Physiol.* 266:R1022-R1031, 1994.
- **Thelen2003**: Thelen. Adjustment of muscle mechanics model parameters to simulate dynamic contractions in older adults. *J. Biomech. Eng.* 125:70-77, 2003. doi:10.1115/1.1531112. Read in full: Table 1, p. 71; Appendix, p. 75.
- **Hong2021**: Hong, Ye, Dong, Li, Yan, Cai, Liu, Tan and Wu. Genome-wide association study for body length, body height, and total teat number in Large White pigs. *Front. Genet.* 12:650370, 2021. PMC8366400. Read in full: Table 1.
- **Williams2008a**: Williams, Wilson, Rhodes, Andrews and Payne. Functional anatomy and muscle moment arms of the pelvic limb of an elite sprinting athlete: the racing greyhound (*Canis familiaris*). *J. Anat.* 213:361-372, 2008. PMC2644771. Read in full: Methods, p. 362; Table 1, p. 364; Table 3, p. 366.
- **Williams2008b**: Williams, Wilson, Daynes, Peckham and Payne. Functional anatomy and muscle moment arms of the thoracic limb of an elite sprinting athlete: the racing greyhound (*Canis familiaris*). *J. Anat.* 213:373-382, 2008. PMC2644772. Read in full: Methods, p. 374; Table 1, p. 375; Table 3, p. 376.
- **Winter2009**: Winter. *Biomechanics and Motor Control of Human Movement*, 4th ed., Wiley, 2009. The densities were read from two code copies of Table 4.1 that agree.

The other species masses and lengths come from field guides and breed sources. These include the Bear Specialist Group, Animal Diversity Web, the San Diego Zoo Wildlife Alliance and the Florida Museum. They were read as search-result extracts, so their grade is `FROM_TEXT` at best. Their keys in `extensions/animals/anatomy/body.mojo` name them.
