# Cloth and spring bones

Two solvers give an outfit secondary motion. A spring chain swings a scabbard, a plume or a tasset from one bone. A cloth solver drapes and swings a cloak from the shoulders. Both keep off the body with capsules on its bones.

```mojo
var cloak = add_cloak(scene, assets, person)
var sword = add_spring_chain(scene, person.bones[HIPS.value], [hip, hip + drop])
sword.colliders = body_colliders(person)
# Each frame:
mixer.update(scene, step)
scene.update()
cloak.step(scene, assets, step, available_workers())
scene.update()
sword.step(scene, step)
scene.update()
```

This is not a three.js port. The code is in `extensions/attire/springs.mojo`, `extensions/attire/cloth.mojo` and `extensions/attire/drape.mojo`.

## Spring chains

A spring chain is the spring bone of the VRM 1.0 format, `VRMC_springBone`. `three-vrm` implements it for three.js. Each step, for each joint from the root out, the chain does five things.

1. The joint's tail keeps the motion it had, less its drag.
2. It springs toward its rest direction and falls under gravity, each times the step's length.
3. It is put back at its bone's length from the joint's head.
4. Each collider pushes it out, and it is put back at its length. This happens four times, where VRM does it once.
5. The joint turns so its bone points at the tail.

`SpringSettings` uses VRM's names and units.

| Setting | VRM name | Default |
|---|---|---|
| `stiffness` | `stiffness` | 1.0 per second |
| `gravity` | `gravityPower` | 0.5 m/s |
| `gravity_direction` | `gravityDir` | straight down |
| `drag` | `dragForce` | 0.4 |
| `radius` | `hitRadius` | 0.02 m |

`add_spring_chain(scene, parent, points, settings)` hangs joints from a node. Hang a mesh from `chain.nodes[0]` and it swings with the chain. Call `scene.update()` before each chain's step and after it. A chain has two or more joints. `SpringChain` refuses fewer, or an offset count that does not match the joints.

`body_colliders(person)` gives capsules on the trunk and the limbs and a sphere on the head, sized for the person's stature. They stand for the body roughly, within a few centimeters of the skin.

A chain keeps its settings in the user data of its first node, under `SPRING_KEY`. A glTF export writes them as that node's extras, and `chain_settings` reads them back after a load. `vrm_spring_json` writes chains in the shape of `VRMC_springBone`. It names nodes by name, not by index, so a tool that writes the VRM file turns the names into indices.

## Cloth

The cloth solver is extended position-based dynamics, XPBD. Each frame is cut into substeps, and each substep makes one pass over the constraints, as "Small Steps in Physics Simulation" steps it.

- Each particle moves on by its velocity and falls under gravity.
- Each constraint keeps two particles at their rest distance. Its compliance, in meters per newton, says how far it gives.
- Structural and shear constraints keep the cloth from stretching. Bending constraints join particles two apart.
- A pinned particle follows its target. A free particle is tethered to its nearest pin, never farther from it than at rest. These are the long range attachments of Kim, Chentanez and Müller-Fischer.
- A free particle is pushed out of each capsule.

`ClothSettings` holds the substeps, the gravity, the damping, the two compliances and the thickness. The defaults suit a wool cloak at thirty frames a second. `ClothSolver.step` checks the settings again, so it refuses a setting that changed after the cloth was made.

## The coloring and parallel solve

The constraints are colored so that no two of one color share a particle. This is the method of Vivace, by Fratarcangeli, Tibaldo and Pellacini. `color_constraints` colors them greedily. The constraints of one color are solved at once, each on its own two particles. So a step gives the same result, bit for bit, on one thread or on many. `test_many_threads_settle_the_cloth_as_one_does` checks this on a sheet of 1,600 particles.

## On a GPU

`GpuCloth` steps a `ClothSolver` on a GPU, with the same substeps and the same colors. Make it once from the cloth, then call its `step` where you call the cloth's own.

```mojo
from extensions.attire.cloth_gpu import GpuCloth

var gpu = GpuCloth(cloak.solver)
gpu.step(cloak.solver, Duration(1.0 / 30.0, SECOND))
```

Each substep runs three kernels, as the CPU step runs three loops.

1. `predict_kernel` moves each particle on, one thread to a particle.
2. `relax_kernel` settles one color, one thread to a constraint. It runs once for each color.
3. `settle_kernel` holds each free particle to its tether and pushes it out of each capsule.

The kernels call the CPU solver's own arithmetic: `glide`, `predict`, `relax_pair`, `settle` and `push_out`. So the two solves agree but for the device's fused multiplies and adds. `step` reads the pins' targets, the colliders and the settings from the cloth each time, and writes the particles back to it.

A cloak of a few hundred particles steps in well under a millisecond on the CPU. The GPU pays for itself with many cloaks, or with a garment of many thousand particles.

## Cloaks

`add_cloak(scene, assets, person, cut, over)` hangs a cloak from the shoulders. Its top row wraps the back of the neck from one shoulder to the other and is pinned to the chest bone. The middle of the top row lies at the base of the neck, so the top edge falls along the slope of the shoulders. The cloth starts as a half cone round the back, out of the colliders. Step it a few times at rest to let it settle.

`CloakCut` sets the length, the width at the top, the particles across and down, the fabric, the dye, a trim, the folds and the flare. The default is a wool cloak to below the knee, 25 particles across and 28 down, in three folds. Its hem is twice as wide as its top, so it has cloth to spare round the legs and falls in folds.

- The top is no wider than the span between the shoulders' joints.
- A trim dyes the hem and the two edges.
- Each fold stands out of the cone, 3.5 cm deep at the hem on the template. Each constraint keeps its length in the folded cloth, so the cloak keeps its folds.
- Each fold needs six columns or more. With fewer, alternate columns hang apart and the hem is jagged. `add_cloak` refuses such a cut.
- The texture coordinates are in meters, so the fabric's weave lies on the cloak as on a garment.
- The sheen takes the cloak's dye. A pale sheen washes a dark cloth out to gray where the light grazes it.

`Cloak.step` reads where the chest bone and the colliders' bones are, steps the cloth, and writes the cloak's mesh.

### Over garments

The body's capsules lie inside a flared robe, a pauldron and a fur mantle, so a cloak falls through them. `dressed_colliders(person, outfit, dressed)` fits capsules to the garments' shells instead. Pass them to `add_cloak` as `over`. The code is in `extensions/attire/drape.mojo`.

1. Each capsule of the body is cut into three parts along its bone.
2. Each vertex of a garment grows a part of the bone that weighs it most: the part whose skin it lies nearest. The neck's vertices grow the chest's parts.
3. A part grows by 12 cm on the template at the most, and to twice its radius at the most. So a wide sleeve does not swing a great capsule through the cloak.
4. A part of the trunk grows to hold the garments' depth alone. The trunk is wider than it is deep, and a round part as wide as the hips stands far off the back.
5. A skirt's vertices below the skirt's top are sliced into bands 4 cm high. A capsule across the hips holds each band, as wide and as deep as the band. A band is deeper by 4 % of its fall below the top, as the legs swing the skirt.
6. A hat grows nothing. A vertex of a hand or a foot grows nothing, as no capsule rides those bones.

Start a walk with `fade_in`. A pose that jumps from rest to a stride moves the skirt's capsules through the settled cloth, and throws the cloth off.

```mojo
var dressed = dress(scene, assets, person, outfit)
var over = dressed_colliders(person, outfit, dressed)
scene.update()
var cloak = add_cloak(scene, assets, person, cloak_of(ROYAL, seed), over)
```

## Tests

`tests/test_attire_springs.mojo`, `tests/test_attire_cloth.mojo` and `tests/test_attire_drape.mojo` cover this page. `tests/test_attire_cloth_gpu.mojo` steps one sheet on the CPU and on a GPU and compares every particle. It runs only on a machine with a GPU. Its bound of two millimeters has not yet been measured on one.
