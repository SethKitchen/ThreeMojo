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

This is not a three.js port. The code is in `extensions/attire/springs.mojo` and `extensions/attire/cloth.mojo`.

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

A GPU kernel can run the same schedule. This repository does not have one yet, because the CPU solve of a cloak takes under a millisecond a frame. A GPU kernel is worth it for many cloaks, or for a garment of many thousand particles.

## Cloaks

`add_cloak(scene, assets, person, cut)` hangs a cloak from the shoulders. Its top row wraps the back of the neck from one shoulder to the other and is pinned to the chest bone. The cloth starts as a half cone round the back. Step it a few times at rest to let it settle.

`CloakCut` sets the length, the width, the particles across and down, the fabric and the dye. The default is a wool cloak to below the knee, 13 particles across and 20 down. `Cloak.step` reads where the chest bone and the colliders' bones are, steps the cloth, and writes the cloak's mesh.

## Tests

`tests/test_attire_springs.mojo` and `tests/test_attire_cloth.mojo` cover this page.
