# Animal anatomy

Each procedural animal has a skeleton, Hill-type muscles, segment mass and inertia, and a gait timed by dynamic similarity. You can draw it in game mode or in engineering mode. Every quantity carries an SI unit type. Every literature value carries an evidence grade and a source key.

![A horse, a dog and a cheetah walk in game mode on the left and in engineering mode on the right](out/animal_anatomy.png)

## Call it

```mojo
from extensions.anatomy.mode import ENGINEERING_MODE
from extensions.animals.anatomy.body import species_body
from extensions.animals.anatomy.engineering import (
    calibrate,
    calibrated_animal,
    calibrated_mass,
)
from extensions.animals.anatomy.muscles import animal_muscles
from extensions.animals.anatomy.render import materials_in_mode, mesh_in_mode
from extensions.animals.anatomy.stance import standing_loads
from extensions.animals.build import create_animal
from extensions.animals.gait import walk_pose
from extensions.animals.options import Variant, animal_options
from extensions.animals.registry import HORSE

var cal = calibrate(HORSE, Variant(-1))
var base = create_animal(HORSE, animal_options(3))
var horse = calibrated_animal(base, cal)
var mass = calibrated_mass(base, cal)
var muscles = animal_muscles(
    horse.rig, species_body(HORSE).plan, mass.total().mass
)
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
| Numbers | Not for analysis | SI quantities with evidence grades |

`mesh_in_mode` meshes an animal in a mode. `materials_in_mode` gives the materials for each mesh. In engineering mode the skin is translucent, so the skeleton and the muscles show through it.

## Evidence grades

The research for these tables used search-engine extracts. The proxy blocked the full text of the papers, so no value is better than `FROM_TEXT`. Check a value against its source before you rely on it.

| Grade | Meaning |
|---|---|
| `FROM_ABSTRACT` | The number is in the source's own abstract. |
| `FROM_TEXT` | The number is in the source's body, or in a secondary source that quotes it. |
| `CROSS_CHECKED` | As `FROM_TEXT`, and it agrees with the rest of its row, for example `PCSA = m / (rho L)`. |
| `UNVERIFIED` | No source that we read shows the number. |
| `DESIGN` | A modeling choice or a unit conversion, not a measurement. |

`Evidence.is_measured` is True for the first three grades. `Cited` holds a grade and a source key from the reference list below.

## Calibration

The sculpts were drawn to look right. Engineering mode scales each species to its published size.

1. `calibrate` builds a canonical individual: an adult male of the published morph.
2. It measures the sculpt's reference length. For a quadruped mammal, this is the shoulder height. For a bird or a fish, it is the total length. For a frog, a rabbit, a rat, a snake or a spider, it is the body length.
3. The length factor gives the sculpt the published length.
4. The scaled sculpt's mass at the published densities is a prediction. `Calibration.density_factor` is the published mass over that prediction.

`calibrated_animal` scales the sculpt, the rig and the cells. The coat still paints. `calibrated_mass` scales the densities by the density factor. Each segment keeps the share of mass that the geometry gives it. This is how a biomechanist scales segment parameters to a weighed subject. An individual keeps its own size relative to the canonical one, so a juvenile stays small and light.

A morph that is not the published kind gets the length factor but no mass correction. For example, the bear's numbers are for a black bear, so a grizzly has `Calibration.matched` False.

### What the calibration predicts

The calibration uses the adult male. An adult female, drawn on its own, then predicts its mass from its geometry alone. This table compares that prediction with the published female mass.

| Species | Predicted female mass | Published female mass |
|---|---|---|
| Horse | 475 kg | 450 kg |
| Deer | 49 kg | 50 kg |
| Wolf | 44 kg | 45 kg |
| Fox | 4.9 kg | 5.0 kg |
| Dog | 26 kg | 28 kg |
| Shark | 1375 kg | 1400 kg |
| Tarantula | 20.2 g | 20 g |

## Mass and inertia

`sample_mass` samples the posed sculpt on a grid of cubic cells:

- A cell's share of flesh is `clamp(1/2 - d / h, 0, 1)`, with `d` the signed distance of its center and `h` its side.
- Solids of hair, wool and feathers are left out. The furred surfaces are pulled in by the species' coat depth. The coat reaches at most 30 % of a solid's smallest radius, so a thin leg keeps its flesh.
- Each cell takes the density of the solid nearest to it. It is added to the bone that the solid rides.

`extensions/anatomy/inertia.mojo` sums the cells. Each cell is a cuboid and adds its own inertia, `m w^2 / 12` per axis. The parallel-axis theorem moves the tensor to the center of mass. The humanoid's limb segments use the same tally.

`BodyMass.bone` gives one bone's mass, center of mass and inertia. `BodyMass.total` gives the whole body. `BodyMass.reference` measures the reference lengths from the same sample.

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
| Chicken, plucked | 1.044 | `FROM_TEXT` (Hamershock 1993) |
| Flying bird, plucked | 0.965 | `DESIGN`: the middle of 0.880 to 1.050 |
| Fish with a swim bladder | 1.00 | `FROM_TEXT` (Lindsey 2010) |
| Frog | 1.00 | `FROM_TEXT` |
| Shark | 1.05 | `UNVERIFIED` |
| Snake | 1.057 | `DESIGN`: 1.13 with 6.5 % of the body lung |
| Spider | 1.05 | `DESIGN` |

Keratin is 1.30 g/cm^3 (McKittrick 2012). Antler 1.8, tooth 2.1 and the eye 1.01 g/cm^3 are `UNVERIFIED`.

## Muscles

`extensions/anatomy/muscle.mojo` is the shared Hill-type muscle.

- `MuscleArchitecture` holds the belly mass, the optimal fiber length, the pennation angle, the tendon slack length, the specific tension and the density.
- `pcsa` is `m / (rho L0)`. `max_force` is the specific tension times the PCSA.
- The force curves are Thelen's (2003), with the young-adult parameters.
- `isometric_equilibrium` solves the fibers and the tendon at one length.
- `activation_rate` is Thelen's first-order activation.

The default specific tension is 0.3 MPa. The muscle density is 1.06 g/cm^3 (Mendez and Keys 1960).

`animal_muscles` puts the limb muscles of a body plan on an individual's rig. A path starts at an origin, can wrap over via points on any bone, and ends at an insertion. `AnimalMuscle.moment_arms` gives the arm about each crossed joint in any pose. Each arm uses the stretch of the path that spans its joint. A positive arm turns the distal bone backward: it extends the hip and flexes the knee.

### Mammal hind limb

The greyhound's biceps femoris anchors the masses (Williams 2008, `FROM_TEXT`). It is 485 g of a 31.8 kg dog, 1.53 % of body mass a side. The other muscles keep the rat's ratios to the biceps femoris (Eng 2008, Table 1, `CROSS_CHECKED`). Mass scales with body mass, nearly isometrically (Pollock 1994, `FROM_ABSTRACT`). The optimal fiber length is the rat's share of the segment it lies along. The rig gives the segment lengths.

| Muscle | Mass over the biceps femoris | Fiber length over its segment |
|---|---|---|
| Biceps femoris | 1 | 0.83 of the femur |
| Rectus femoris | 0.354 | 0.28 of the femur |
| Vastus lateralis | 0.483 | 0.48 of the femur |
| Gastrocnemius | 0.704 | 0.34 of the tibia |
| Soleus | 0.051 | 0.43 of the tibia |
| Tibialis anterior | 0.248 | 0.36 of the tibia |

### Other muscles

- Mammal fore limb: the triceps brachii is 1.65 % of body mass a side (`UNVERIFIED`). The biceps brachii, the supraspinatus and the superficial digital flexor are `DESIGN` values. The flexor's tendon runs behind the carpus and over the sesamoids, so it holds the wrist and the fetlock.
- Bird: the pectoralis is 6.25 % and the supracoracoideus 0.75 % of body mass a side (Hartman 1961, `FROM_TEXT`). The supracoracoideus lifts the wing over its pulley, the triosseal canal. The wing beats about the body's long axis.
- Frog: the hind limbs hold 33 % of body mass (James 2007, `FROM_TEXT`, *Litoria nasuta*). The plantaris is 19.4 % of that. The cruralis and the semimembranosus are `DESIGN` shares.
- Fish, shark and snake: `axial_muscles` gives each spine joint a muscle a side. Its mass is a share of its segment's sampled mass. The share is 60 % for a fish (`UNVERIFIED`) and 53 % for a shark (Bernal 2003 for the red muscle). It is 30 % for a snake (`DESIGN`).
- Spider: each femur-patella and tibia-metatarsus joint has one flexor. A spider has no extensor at those joints. Hemolymph pressure extends them: `hemolymph_pressure` gives 6.5 kPa at rest and 65 kPa at a peak (Parry 1959; Anderson 1975). The flexors develop 0.5 MPa (Medler 2002).

The attachment offsets are `DESIGN` choices that give each muscle its known action. The tendon slack length makes the fibers optimal in the standing bind pose.

## Standing loads

`standing_loads` gives the static load on each left limb joint of a standing quadruped:

1. Each foot presses at the middle of its sole.
2. The center of mass splits the weight between the fore and the hind feet.
3. About each joint, the foot's push has a moment. The muscles must cancel it.
4. The muscles that oppose the moment share it at one stress, `sigma = M / sum(r_i PCSA_i)`.

`JointLoad` gives the moment, the ground lever, the muscle lever, the effective mechanical advantage (Biewener 1989), the stress and the activation. A joint that its muscles cannot hold at full activation reports `held` False. Tendons and ligaments hold it, as a horse's stay apparatus holds its fetlock.

The moment arms come from `DESIGN` attachments that scale with the segments. So the effective mechanical advantage does not grow with body mass as Biewener's `M^0.26` does.

## Gait timing

`extensions/anatomy/locomotion.mojo` holds dynamic similarity. Animals move alike at equal Froude numbers, `Fr = u^2 / (g h)` (Alexander and Jayes 1983). The stride length is `2.3 Fr^0.3 h` (Alexander 1976, `FROM_TEXT`).

`walk_pose` takes a Froude number. 0.25 is the default, a walk below the walk-trot transition near 0.5. Each foot sweeps 70 % of the stride under the body. A Thoroughbred walks at 1.75 m/s with a 1.9 m stride at 0.93 Hz. A 34 kg dog walks at 1.0 m/s at 1.6 Hz.

## Bulging bellies

Muscle keeps its volume. `flexed` reshapes the sculpt's belly solids for a pose. When a muscle's fibers shorten by a factor `f`, its solids shrink by `f^w` along the muscle and grow by `f^(-w/2)` across it. `w` is 0.5, a `DESIGN` value: the skin and the fat do not bulge. `f` is held to 0.6 to 1.4. The bind pose changes no solid.

`flexed_animal` returns the individual with the reshaped sculpt. Mesh it with the same pose.

## Physics bodies

`segment_bodies` turns each bone with flesh into a dynamic `RigidBody` for `extensions/physics`. Each body has the sampled mass, center of mass and inertia tensor. `to_physics` turns the sculpt's `+y`-up frame into the physics world's `+z`-up frame. The physics world has no joints yet, so the bodies are the segments of a multibody model.

## Species

| Species | Kind | Male, female mass | Reference length | Grade |
|---|---|---|---|---|
| Bear | American black bear | 100, 60 kg | 0.90 m shoulder | `FROM_TEXT` |
| Boar | Central European wild boar | 85, 70 kg | 0.75 m shoulder | `FROM_TEXT` |
| Cat | Domestic cat | 4.5, 3.5 kg | 0.25 m shoulder | `FROM_TEXT` |
| Cheetah | Cheetah | 50, 30 kg | 0.80 m shoulder | `FROM_TEXT` |
| Chicken | White Leghorn | 2.6, 2.0 kg | 0.45 m total | mass `FROM_TEXT`, length `UNVERIFIED` |
| Cow | Holstein-Friesian | 900, 650 kg | 1.45 m shoulder | mass `UNVERIFIED` |
| Crow | American crow | 0.47, 0.43 kg | 0.45 m total | `FROM_TEXT` |
| Deer | White-tailed deer | 70, 50 kg | 0.90 m shoulder | `FROM_TEXT` |
| Dog | Medium herding dog | 35, 28 kg | 0.60 m shoulder | `UNVERIFIED` |
| Eagle | Golden eagle | 3.7, 5.2 kg | 0.85 m total | `FROM_TEXT` |
| Fish | Rainbow trout | 1.0 kg | 0.45 m total | `FROM_TEXT` |
| Fox | Red fox | 6.5, 5.0 kg | 0.40 m shoulder | `FROM_TEXT` |
| Frog | American bullfrog | 0.30 kg | 0.155 m snout-vent | mass `UNVERIFIED` |
| Goat | Saanen dairy goat | 85, 65 kg | 0.85 m shoulder | mass `UNVERIFIED` |
| Horse | Thoroughbred | 500, 450 kg | 1.62 m shoulder | `FROM_TEXT` |
| Lion | African lion | 190, 126 kg | 1.15 m shoulder | `FROM_TEXT` |
| Pig | Large White | 300, 250 kg | 0.90 m shoulder | length `UNVERIFIED` |
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
- The fore-limb muscle masses, the attachments and the coat depths are `DESIGN` values.
- Birds have flight muscles but no leg muscles.
- The physics world has no joints, so the segment bodies do not yet form a chain.

## Types and checks

Each id, kind and mode is a type with `is_valid`: `AnatomyMode`, `Evidence`, `BodyPlan`, `ReferenceKind`, `BodyTissue` and `Segment`. Every boundary that reads one refuses a value that is not valid. The files in `tests/compile_fail/` prove that a bare integer does not compile.

## References

- **Alexander1976**: Alexander, R. McN. Estimates of speeds of dinosaurs. *Nature* 261:129-130, 1976. The stride relation was read as a quotation in later trackway papers.
- **Alexander1979**: Alexander, Jayes, Maloiy and Wathuta. Allometry of the limb bones of mammals from shrews (*Sorex*) to elephant (*Loxodonta*). *J. Zool.* 189:305-314, 1979.
- **AlexanderJayes1983**: Alexander and Jayes. A dynamic similarity hypothesis for the gaits of quadrupedal mammals. *J. Zool.* 201:135-152, 1983.
- **Anderson1975**: Anderson and Prestwich. The fluid pressure pumps of spiders (Chelicerata, Araneae). *Z. Morph. Tiere* 81:257-277, 1975.
- **Bernal2003**: Bernal, Sepulveda, Mathieu-Costello and Graham. Comparative studies of high performance swimming in sharks I. Red muscle morphometrics, vascularization and ultrastructure. *J. Exp. Biol.* 206:2831-2843, 2003.
- **Biewener1989**: Biewener. Scaling body support in mammals: limb posture and muscle mechanics. *Science* 245:45-48, 1989.
- **Dempster1955**: Dempster. Space requirements of the seated operator. WADC Technical Report 55-159, 1955.
- **Eng2008**: Eng, Smallwood, Rainiero, Lahey, Ward and Lieber. Scaling of muscle architecture and fiber types in the rat hindlimb. *J. Exp. Biol.* 211:2336-2345, 2008.
- **Hamershock1993**: Hamershock, Seamans and Bernhardt. Determination of body density for twelve bird species. Technical Report WL-TR-93-3049, Wright Laboratory, 1993. DTIC ADA266452.
- **Hartman1961**: Hartman. Locomotor mechanisms of birds. *Smithsonian Misc. Coll.* 143(1):1-91, 1961.
- **James2007**: James et al., 2007, on the hind-limb muscle of the rocket frog *Litoria nasuta*. PubMed 18190283. Only the PubMed record was read.
- **Lindsey2010**: Lindsey, Smith and Croll. From inflation to flotation: contribution of the swimbladder to whole-body density and swimming depth during development of the zebrafish (*Danio rerio*). *Zebrafish* 7:85-96, 2010.
- **McKittrick2012**: McKittrick, Chen, Bodde, Yang, Novitskaya and Meyers. The structure, functions, and mechanical properties of keratin. *JOM* 64:449-468, 2012.
- **Medler2002**: Medler. Comparative trends in shortening velocity and force production in skeletal muscles. *Am. J. Physiol. Regul. Integr. Comp. Physiol.* 283:R368-R378, 2002.
- **MendezKeys1960**: Mendez and Keys. Density and composition of mammalian muscle. *Metabolism* 9:184-188, 1960.
- **Parry1959**: Parry and Brown. The hydraulic mechanism of the spider leg. *J. Exp. Biol.* 36:423-433, 1959.
- **Pollock1994**: Pollock and Shadwick. Allometry of muscle, tendon, and elastic energy storage capacity in mammals. *Am. J. Physiol.* 266:R1022-R1031, 1994.
- **Thelen2003**: Thelen. Adjustment of muscle mechanics model parameters to simulate dynamic contractions in older adults. *J. Biomech. Eng.* 125:70-77, 2003.
- **Williams2008**: Williams, Wilson, Rhodes, Andrews and Payne. Functional anatomy and muscle moment arms of the pelvic limb of an elite sprinting athlete: the racing greyhound (*Canis familiaris*). *J. Anat.* 213:361-372, 2008.
- **Winter2009**: Winter. *Biomechanics and Motor Control of Human Movement*, 4th ed., Wiley, 2009. The densities were read from two code copies of Table 4.1 that agree.

The species masses and lengths come from field guides and breed sources. These include the Bear Specialist Group, Animal Diversity Web, the San Diego Zoo Wildlife Alliance and the Florida Museum. Breed standards and morphometric studies give the rest. Their keys in `extensions/animals/anatomy/body.mojo` name them.
