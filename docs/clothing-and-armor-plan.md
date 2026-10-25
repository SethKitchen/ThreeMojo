# Clothing and armor for the humanoid: research and plan

This document surveys how modern games build clothing and armor, which
papers and open source code describe the methods, and how ThreeMojo can
build the same thing on its humanoid. It is a plan, not a feature. Each phase
below becomes a GitHub issue, a README checklist line and a wiki page when the
work starts.

## Recommendation in one paragraph

Build garments as *layers over the skin field*. ThreeMojo already owns the
humanoid as a signed-distance field (`BodySkinField`), a 19-joint rig, geodesic
skin weights and a Verlet hair solver with baked body colliders. A garment is
then a shell of the field below it, offset by its thickness, cut to a set of
body regions, and welded to the skin so it follows every genome and stature.
This is what Roblox's cages, MakeHuman's `mhclo` and Warhorse's adaptive
clothing all approximate from the outside with meshes; ThreeMojo can do it
from the inside with the field. Aesthetics come first: layer order, body
hiding, dye channels, saved outfits, cloth and metal looks, rigid plates on
bones. Motion comes second: spring bones for tassets and capes, then XPBD
cloth that reuses the hair solver. Engineering comes last and stays labeled as
template estimates: mass from areal density and plate thickness, worn mass per
rig segment, locomotion cost, coverage and a penetration-energy model.

## 1. What players like

| Game | What players praise | Pattern to borrow |
| --- | --- | --- |
| Kingdom Come: Deliverance I and II | Historically grounded layers: padding under mail under plate, up to four layers at one body location, 16 clothing slots and 4 weapon slots. Armor changes noise, stealth and how NPCs see you. Blood, grime and damage accumulate. | A layer stack per body region with a strict order. Each layer has a material class. Dirt, blood and damage are data on the garment. |
| Elden Ring and the Souls series ("Fashion Souls") | Players mix pieces from many sets for looks, not stats. Silhouette, cloth motion and material contrast carry a design. | Pieces from different sets must combine without clipping. Capes, skirts and tassets need secondary motion. |
| Monster Hunter World and Wilds (layered armor) | Appearance is separate from stats. Each piece has a primary and a secondary color. Presets save a look. | Decouple the appearance layer from the stat layer. Two or more dye channels per piece. Saved outfits. |
| Final Fantasy XIV (glamour plates) | Up to 20 saved outfits overlay the equipped gear. Dawntrail added a second dye channel and players asked for more. | Design dye channels as N, not two. |
| Cyberpunk 2077 (wardrobe) | Players say transmog transformed the game: several saved looks, any gear for stats. | Same decoupling. |
| Dragon's Dogma 2 | Five slots (two head, torso, legs, cape). Players miss the first game's separate under-layers. Capes that stood off a small body were a visible flaw. | Keep under-layers as real layers. Fit a garment to the body shape. Never scale it. |
| Roblox Layered Clothing | Any garment fits any body, up to 6 layers, no clipping. | A garment is defined relative to the surface below it. Layer order is an integer. |
| Baldur's Gate 3, Ghost of Tsushima | Dyes with several channels, camp clothes as a second outfit, armor that reads as culturally correct. | Dye channels and outfit sets. |

Four things recur in every game that players praise:

1. Looks are a free choice. Appearance is decoupled from function.
2. Pieces from different sources combine without clipping.
3. Color belongs to the player, through several dye channels per piece.
4. Layers read as real. Padding sits under mail under plate, and loose parts move.

## 2. How games build it

### Layered garments on a parametric body

- **Roblox Layered Clothing.** The body carries an *inner* and an *outer cage*
  mesh. Every garment ships the same two cages, deformed to its fit. Cage UVs
  give a vertex-to-vertex correspondence, so a garment authored on the
  reference body is warped onto any body and onto any garment under it. Layer
  order is an integer. Geometry inside the inner cage causes artifacts, and
  geometry outside the outer cage is not deformed. Patents US11615601 and
  US12374067 (conforming to an underlying layer) and US12190427 (hidden surface
  removal for layered clothing) describe the method.
- **MakeHuman `mhclo`.** Each clothing vertex is bound to one triangle of body
  vertices with barycentric weights and an offset. The garment then follows
  every body morph. A `delete_verts` list hides the body faces under the
  garment. Full-body proxies use the same format.
- **Kingdom Come: Deliverance I** (GDC Europe 2015, Tomas Barak, Warhorse).
  An "adaptive clothing system" adapts several layers so they do not overlap.
  It casts rays from the outer layer to the layer below and moves vertices
  out, at a quality comparable to hand-made assets.
- **Kingdom Come: Deliverance II** (GDC 2025, Gabor Molnar, Warhorse).
  Material atlasing, ID maps, material propagation, UV-space decals, hiding
  groups, LODs, an armor layering system, and blood, grime and damage. The
  goal was fewer draw calls and less memory for many layered characters.
- **Unreal Engine Mutable** (UE 5.5 beta plugin). A node graph merges mesh
  sections and textures, layers body and garments, and clips or hides unseen
  parts with *Clip Mesh With Mesh* and *Clip Morph* modifiers. Users report
  artifacts when clipping meets a body-morph reshape.
- **inZOI masking.** Outfits declare *drawing regions*, *covering regions*
  and *body regions*. Body regions hide the skin under a shirt or a shoe.
  Group IDs bundle regions.

### Secondary motion

- **VRM `VRMC_springBone`.** An open glTF extension. A bone chain is a damped
  spring with stiffness, drag, gravity and sphere or capsule colliders.
  `three-vrm` implements it in TypeScript under MIT.
- **Unity Magica Cloth 2.** *BoneCloth* drives a chain of transforms and
  *MeshCloth* drives the vertices of a skinned mesh, both on a position-based
  solver.
- **Unreal Chaos Cloth.** A *MaxDistance* weight map limits how far a particle
  may leave its skinned position, and 0 makes it kinematic. A *Backstop*
  distance and radius keep particles outside a sphere behind the skinned
  surface. Kinematic colliders are capsules on bones.

### Cloth solvers

- Müller et al., *Position Based Dynamics* (2007). Positions, constraint
  projection, Gauss-Seidel. Stiffness depends on the iteration count.
- Macklin, Müller and Chentanez, *XPBD* (MIG 2016). Compliance makes
  stiffness independent of iteration count and time step.
- Macklin et al., *Small Steps in Physics Simulation* (SCA 2019). Many
  substeps with one iteration each beat one step with many iterations.
- Kim, Chentanez and Müller-Fischer, *Long Range Attachments* (SCA 2012). One
  constraint from each particle to its attachment on the kinematic body keeps
  a garment inextensible. The standard trick for game garments.
- Fratarcangeli, Tibaldo and Pellacini, *Vivace* (TOG 2016). Parallel
  Gauss-Seidel by randomized graph coloring each frame. The GPU path.
- Baraff and Witkin, *Large Steps in Cloth Simulation* (1998). Implicit
  integration with a modified conjugate gradient. Blender's cloth modifier is
  in this family. Offline quality, not the game path.
- Learned: Grigorev et al., *HOOD* (CVPR 2023) and *ContourCraft* (SIGGRAPH
  2024) predict garment motion on any body with a graph network and resolve
  intersections with a contour loss. *CAPE* is a generative clothed-body model
  on SMPL. Research licenses. Read for ideas, do not port.

### Garment construction

- Korosteleva and Sorkine-Hornung, *GarmentCode* (2023), `pygarment` on PyPI,
  MIT. A domain-specific language for parametric sewing patterns: panels,
  edges, stitches and interfaces, with the GarmentCodeData set of
  made-to-measure garments. The model for a procedural garment grammar.

### Open source code worth reading

| Project | Language | License | Use |
| --- | --- | --- | --- |
| InteractiveComputerGraphics/PositionBasedDynamics | C++ | MIT | Reference PBD and XPBD cloth: distance, bending and FEM constraints |
| pixiv/three-vrm | TypeScript | MIT | Spring bones and colliders, the VRM 1.0 schema |
| three.js `physics_ammo_cloth`, `webgl_physics_volume` | JavaScript | MIT | The API shape three.js users expect for soft bodies |
| cannon-es cloth example | JavaScript | MIT | Verlet particle cloth with distance constraints |
| vitalight/Velvet | CUDA | MIT | XPBD cloth that reproduces FleX behavior |
| nitronoid/csb | C++14 | MIT | Cloth and soft bodies with PBD on triangle meshes |
| maria-korosteleva/GarmentCode | Python | MIT | Parametric sewing patterns |
| MakeHuman and MPFB2 | Python | AGPL and GPL | The `mhclo` format. Read the format, do not copy code |
| Blender cloth modifier | C | GPL | Implicit solver reference. Read, do not copy |

The project already ports MIT code with a notice in `THIRD-PARTY-NOTICES.md`
(the hair solver from Frostbitten). Any port from the MIT rows above follows
the same path. The GPL and AGPL rows are reading material only.

## 3. Numbers for an engineering layer

| Quantity | Value | Source |
| --- | --- | --- |
| Hand-weapon blow energy | 60 to 130 J | Williams |
| Arrow energy to defeat mild steel plate | about 55 J at 1 mm, 175 J at 2 mm | Williams, as quoted; secondary sources disagree |
| Arrow energy to defeat mail over a padded jack | about 120 J | Williams, as quoted |
| Breastplate thickness | 1 to 2.5 mm early; 1.9 mm average around 1500; infantry plates to 3 mm by 1550 | Lazar and Kraner 2019; Wikipedia |
| Mail hauberk mass | 9.3 kg, 10 kg, 11.1 kg | Cleveland Museum of Art, Harvard, 15th century |
| Mail ring count | about 24,000 rings in 1.5 kg | One archaeological leg piece |
| Full plate field harness | 15 to 25 kg; 30 to 50 kg including tournament suits | Several |
| Padded jack | 18 to 30 layers of linen; a gambeson is two layers around a filling | Wikipedia, museum suppliers |
| Locomotion cost in armor | 2.1 to 2.3 times unloaded walking, 1.9 times unloaded running; higher than the same mass on the trunk | Askew, Formenti and Minetti, Proc. R. Soc. B 2012 |
| Steel density | 7,850 kg/m³ | Standard |
| Linen areal density | about 0.15 to 0.25 kg/m² per layer | Textile standard |

These are template estimates. The `Evidence` and `Cited` types in
`extensions/anatomy/evidence.mojo` already exist to carry a citation with a
number. Each constant above gets one.

## 4. What ThreeMojo already has

| Need | Existing piece | Where |
| --- | --- | --- |
| A body to dress | `BodySkinField`, `body_skin_mesh`, `PartedBody` | `extensions/humanoid/skeleton/torso/body.mojo` |
| Body shape parameters | `HumanoidSpec` (stature, sex, athleticism), `Genome` with 43 genes | `extensions/humanoid/spec.mojo`, `genome.mojo` |
| A rig | `HumanoidRig`, 19 `Joint` values with `is_valid`, `joint_parent` | `extensions/humanoid/rig/joints.mojo` |
| Weights | `skin_weights` (geodesic, top 4), `rigid_weights` (one bone), `carry_attributes` | `extensions/humanoid/rig/weights.mojo`, `rig/game.mojo` |
| Body regions | 14 `BodyRegion` values, `region_map` from vertex to region | `extensions/humanoid/canonical.mojo`, `correspondence.mojo` |
| An attachment pattern | The `holder` node under the HEAD bone for eyes and hair | `extensions/humanoid/rig/game.mojo` |
| Mesh from a field | `mesh_field`, `mesh_surface`, `project_to_surface`, `MeshField` | `extensions/humanoid/skeleton/isosurface.mojo`, `surface_nets.mojo`, `mesh_field.mojo` |
| Sectional fit | `fit_loft`, `Loft` | `extensions/humanoid/skeleton/loft.mojo` |
| Triangle budgets | `fit_triangle_budget`, `Quality`, `BODY_SHARE`, `HAIR_SHARE` | `extensions/humanoid/skeleton/simplify.mojo`, `quality.mojo` |
| Skinned rendering | `SkinnedMesh`, `Skeleton`, `bind_skeleton`, skinning in `prepare` shared by both rasterizers | `objects/skinned_mesh.mojo`, `objects/skeleton.mojo`, `core/deform.mojo` |
| Cloth look | `PHYSICAL` material with `sheen`, `sheen_color`, `sheen_roughness` | `materials/material.mojo`, `lights/physical_layers.mojo` |
| Metal look | `metalness`, `roughness`, `anisotropy`, `clearcoat`, normal and bump maps | same |
| A particle solver with body colliders | `HairSimulation` (Verlet, length, shape and distance-field constraints), `HairBody`, `HairCollider` | `extensions/humanoid/skeleton/head/hair/simulation.mojo`, `groom.mojo`, `collider.mojo` |
| Rigid bodies and shapes | `RigidBody`, `ShapeKind` with `CAPSULE`, `PhysicsWorld`, CCD | `extensions/physics/` |
| Units | `Length`, `Mass`, `Density`, `Energy`, `Pressure`, `Force`, `Angle` | `units/si.mojo` |
| Segment mass | `SegmentInertia`, `InertiaTally` | `extensions/anatomy/inertia.mojo` |
| Interchange | glTF skins, morphs, sheen and anisotropy extensions, `extras` | `loaders/gltf.mojo`, `exporters/gltf.mojo` |
| Sealed bakes | `write_sealed_bake`, `require_sealed_bake`, geometry digest | `extensions/humanoid/bake.mojo` |
| Use gate | `HumanoidUse`: `VISUAL_USE` passes, `ENGINEERING_USE` is refused | `extensions/humanoid/fidelity.mojo` |
| Precedent for a kit of layered materials | `construction_kit`, `kit.check()` | `extensions/building/kits.mojo` |

What is missing:

- A garment type, a layer order, a slot and an outfit.
- Body hiding under a garment.
- Dye channels and an ID mask.
- Typed sockets on the rig.
- An areal-density quantity.
- A cloth solver. The hair solver is a strand solver with no triangle, bending
  or attachment constraints.
- Spring bones.
- Dual-quaternion skinning. Not needed for the first phases.
- A multi-material `SkinnedMesh`. Not needed: one skinned mesh per garment,
  all bound to the same skeleton.

## 5. Architecture

Everything new lives in `extensions/attire/`. The name avoids the overloaded
`cloth`, which the materials code uses for the sheen lobe, and `clothing`,
which CARLA uses for walker colors. No `Makefile` change is needed: the
`LIB_SOURCES` glob picks up `extensions/`, and `tests/test_attire_*.mojo` are
picked up by `TESTS`.

### 5.1 Types (every one has `is_valid` and a `tests/compile_fail/` file)

| Type | Values or shape | Role |
| --- | --- | --- |
| `Slot` | HEAD, FACE, NECK, TORSO, ARMS, HANDS, WAIST, LEGS, FEET, BACK, and the WEAPON slots | Where a piece goes. Mirrors the 16 + 4 of KCD. |
| `Layer` | SKIN = 0, UNDER, MID, OUTER, ARMOR, OVER | Order at one location. Padding is MID, mail is OUTER, plate is ARMOR, a cloak is OVER. |
| `CoverMask` | A bitset over the 14 `BodyRegion` values | Which regions a garment covers. Reuses `canonical.mojo`. |
| `FabricKind` | LINEN, WOOL, SILK, LEATHER, FELT, MAIL, PLATE, and a few more | Selects look and physical constants. |
| `Fabric` | `kind`, `areal_density: ArealDensity`, `thickness: Length`, `stiffness: Stiffness`, `evidence: Cited` | A quantity set. `ArealDensity` is `Quantity[-2, 1, 0, 0]`, defined in `extensions/attire/quantities.mojo` on the pattern of `geotech/quantities.mojo`. |
| `Garment` | `slot`, `layer`, `cover`, `fabric`, geometry, UVs, `DyeMask`, `bound: Binding` | One piece. |
| `Binding` | Per vertex: skin triangle index, barycentric weights, normal offset `Length` | The `mhclo` idea. Lets a garment follow any genome and stature. |
| `DyeChannel` | 0 to 3 | Index into the mask texture. |
| `Outfit` | `List[Garment]` with `check()` | Validates slot and layer uniqueness and layer order. Serializes to glTF `extras.threemojo_outfit` and a JSON preset. |
| `Socket` | CROWN, BACK, LEFT_HIP, RIGHT_HIP, LEFT_SHOULDER, RIGHT_SHOULDER, BELT_FRONT, and more | A named point on the rig with a parent `Joint`, an offset and an orientation. The typed version of the `holder` node. |
| `Plate` | `socket`, `thickness: Length`, `density: Density`, geometry | A rigid armor piece bound with `rigid_weights`. |
| `Lame` | A chain of `Plate` values with hinge limits | Articulated tassets and gauntlets. |

### 5.2 Two ways to make a garment

**Procedural, from the field.** `shell(field, fabric, cover, hems)` offsets the
field below by the fabric thickness plus a clearance, intersects it with the
cover regions, cuts hems at section planes, and meshes it with `mesh_field`.
Layer N shells the union of the body field and the fields of the garments
below it. That is the field form of the Roblox cage rule and of Warhorse's ray
casts: no layer can pass through the layer under it, by construction. Each
shell gets UVs from the loft sections (`fit_loft` already walks sections) so
a woven or a mail normal map tiles along the body. A first set of
garments is small: tunic, hose, gambeson, hauberk, coif, boots, cloak.

**Imported, from glTF.** `bind(garment, skin)` finds the nearest skin triangle
for each garment vertex and stores barycentric weights and the normal offset.
`fit(garment, new_skin)` rebuilds the vertices. Weights come from
`carry_attributes` or straight from `skin_weights` on the garment mesh with
the body rig. This is how an artist's Blender garment made on the reference
body reaches any genome. Garments arrive through `read_gltf`, which already
reads skins, sheen and anisotropy.

Both paths produce a `Garment` and go through the same `Outfit`.

### 5.3 Fit and hide

- **Push-out.** After binding, `resolve(outfit)` walks layers from inside out.
  For each vertex of layer N, sample the signed distance of every layer below
  at that point. When it is less than the clearance, move the vertex out along
  the local normal. Baked `HairCollider` grids give the distance in O(1) per
  sample. This is the KCD ray cast, done with a field.
- **Body hiding.** `hide(skin, outfit)` removes a skin triangle when all three
  vertices lie in a covered region and inside the garment shell, with an
  erosion of one triangle ring so the seam never shows. This is `delete_verts`
  and inZOI's body regions. The same rule hides layer N-1 under layer N.
  Per-triangle hiding is cheap and is the right first step. Per-pixel hidden
  surface removal (the Roblox patent) is a later option if seams show.
- **Clipping groups.** `ClippingGroup` planes can cut a sleeve at the wrist
  for a quick test before hems exist.

### 5.4 Looks

- Cloth is `PHYSICAL` with `sheen`, `sheen_roughness` and a woven normal map.
  Velvet, linen and wool differ in sheen color and roughness only.
- Leather is `PHYSICAL` with low `metalness`, a grain normal map and a
  `clearcoat` for polished leather.
- Mail is a normal map plus a `metalness` and `roughness` map on a thin shell.
  Real rings are out of budget; a 24,000-ring leg piece would exceed the whole
  body triangle budget.
- Plate is `metalness` 1, `roughness` by finish, `anisotropy` for brushed
  steel, `clearcoat` for blued steel.
- **Dye channels.** A `DyeMask` texture holds up to four channel weights in
  RGBA. The garment material's `map` is `albedo * sum(weight_i * dye_i)`.
  The first implementation composites the texture at bake time; the node
  material path can do it in the shader later. Four channels beat the two of
  FF XIV and Monster Hunter, which players called too few.
- **Wear.** A second RGBA mask carries dirt, blood, wet and damage weights
  (KCD II's systems). Phase 2 stores and composites them. Nothing accumulates
  them yet.
- **Decals.** `decal(...)` exists for heraldry on a surcoat.
- **Triangle budget.** Garments take a share like `BODY_SHARE` and
  `HAIR_SHARE`. `fit_triangle_budget` decimates each garment separately.
- **Draw calls.** One `SkinnedMesh` per garment, all on one `Skeleton`. A
  full outfit of eight pieces is eight draws. Measure before atlasing.

### 5.5 Sockets and rigid armor

- `sockets(rig)` places every `Socket` from `HumanoidRig` landmarks, as the
  `holder` node is placed from `rig.at(HEAD)` today.
- `attach(scene, humanoid, socket, node)` parents a node under
  `bones[socket.joint]` with the socket offset, so a helmet, a scabbard or a
  pauldron rides a bone with no weights.
- `Plate` geometry is a shell of the field under it, like a garment, then
  bound rigidly with `rigid_weights`. A cuirass is one plate on CHEST. A
  pauldron is one on UPPER_ARM. A `Lame` chain is several plates whose hinge
  axes come from the two neighboring joints, so a tasset folds as the thigh
  lifts.

### 5.6 Motion (phase 3)

- **Spring bones first.** A `SpringChain` is a chain of extra nodes under a
  parent bone with stiffness, drag, gravity and a radius, colliding against
  capsules placed on the rig joints. It is the VRM `VRMC_springBone` model
  and reads and writes that extension through the glTF loader and exporter.
  It carries a cloak hem, a tasset, a tabard tail, a scabbard, a plume. Most
  of what players see move in armor is this, not cloth.
- **Cloth second.** `ClothSolver` generalizes `HairSimulation`: particles,
  Verlet integration, substeps with one iteration each (Small Steps), distance
  constraints with XPBD compliance, dihedral bending, long range attachments
  to the skinned rest position, a `MaxDistance` weight per particle (0 is
  kinematic, the Chaos Cloth rule), and collision against the `HairCollider`
  body grid plus the garment shells below. The collider grid moves with the
  rig by sampling in the bind pose through the inverse of the blended bone
  matrix, which `skin_pose` already produces. A cape or a skirt is the use
  case. The solver runs on the CPU first. The GPU path colors the constraint
  graph (Vivace) and must agree with the CPU in a parity test, as the
  rasterizers do.
- The 5 s test limit shapes the design: tests use a 200-particle cape and 10
  substeps, and check invariants (edge length, no penetration of the body
  grid, energy decay), not frames.

### 5.7 Engineering (phase 4)

All results are labeled template estimates and cite their `Evidence`. The
humanoid's `ENGINEERING_USE` refusal stays in force; attire reports are a
separate, visual-use-level estimate on the pattern of
`tools/anatomy_validity.mojo`.

- `garment_mass(garment)` is area times `areal_density` for fabric and volume
  times `density` for a plate. A hauberk comes out near the museum 9 to 11 kg
  when the mail fabric constant is set from them.
- `worn_mass(outfit, rig)` splits each garment's mass over the rig segments by
  the `Binding` and adds it to `SegmentInertia` through `InertiaTally`. Then
  the clips (`walk_clip`, `run_clip`) can read a heavier limb.
- `locomotion_cost(outfit)` applies the Askew factors by worn mass and
  distribution. Limb mass costs more than trunk mass, as the paper found.
- `coverage(outfit)` returns the covered share of each `BodyRegion`.
- `protection(outfit, region, blow: Energy)` compares the blow energy with
  the layered threshold: plate by thickness from the Williams table, mail
  over padding at about 120 J, padding alone lower. It returns a typed
  `Protection` result with the stopping layer or `PENETRATED`.
- `noise(outfit)` and `visibility(outfit)` are simple sums by `FabricKind`
  for the KCD-style stealth hooks. Games can replace them.

### 5.8 Bakes and interchange

- A dressed humanoid is baked by `write_sealed_bake` after the garments are
  added, so the geometry digest covers them. `require_sealed_bake` keeps
  working unchanged.
- The outfit is stored in `extras.threemojo_outfit` with the slot, layer,
  fabric, dye colors and the `spec_fingerprint` it was fitted to. A fit for
  another fingerprint is refused and must be rebuilt, as the fidelity maps
  refuse unsupported paths today.
- Spring chains export as `VRMC_springBone`, so a dressed humanoid plays in
  `three-vrm` with its cloak moving.

## 6. Phases

Each phase is one issue, one README line under `### Extensions` next to
`Integument` and `Genome`, one wiki page in `docs/wiki/` with a link in
`_Sidebar.md`, one example in `examples/` with a gallery line, 100 % coverage
and tests under 5 s.

| Phase | Deliverable | Depends on |
| --- | --- | --- |
| 0. Spike (one PR, no new types in public API) | A procedural tunic shelled from `BodySkinField` on the game humanoid, skin hidden under it, drawn by both rasterizers. Proves the shell, the hide and the budget split. | nothing |
| 1. Garments | `Slot`, `Layer`, `CoverMask`, `FabricKind`, `Fabric`, `ArealDensity`, `Garment`, `Binding`, `shell`, `bind`, `fit`, `resolve`, `hide`. Procedural tunic, hose, gambeson, coif, boots. Imported glTF garment fitted to two genomes in a test. Wiki page *Garments*. | 0 |
| 2. Outfits and looks | `Outfit` with `check()`, `DyeChannel` and `DyeMask`, wear masks, cloth, leather, mail and plate materials, `Socket`, `attach`, `Plate`, `Lame`, hauberk and cuirass, outfit presets in JSON and glTF extras, the sealed bake. Example: a dressed family of genomes in the same outfit. Wiki page *Outfits and armor*. | 1 |
| 3. Motion | `SpringChain` with capsule colliders and `VRMC_springBone` in and out. `ClothSolver` on the CPU with the cape as the example. GPU cloth with the parity test. Wiki page *Cloth and spring bones*. | 2 |
| 4. Engineering | `garment_mass`, `worn_mass` into `SegmentInertia`, `locomotion_cost`, `coverage`, `protection`, `noise`, `visibility`, each with `Evidence`. A report tool on the pattern of `anatomy_validity`. Wiki page *Attire estimates*. | 2 |

Phases 3 and 4 are independent and can run in parallel.

## 7. Decisions and risks

- **Field shell before mesh cages.** The field is already there and makes the
  no-clipping rule structural. A cage system would be a second body
  representation to keep in step with the genome. Imported garments still
  work through `Binding`.
- **Per-triangle hiding first.** It is cheap and testable. Per-pixel hidden
  surface removal waits until a seam shows in the gallery.
- **Spring bones before cloth.** They cover most visible armor motion at a
  fraction of the cost, and they interchange through VRM.
- **No dual-quaternion skinning.** Linear blend is fine for a shell that sits
  on the skin. Revisit if plate edges candy-wrap at the shoulder.
- **One material per garment.** Avoids a multi-material `SkinnedMesh`. Cost
  is draw calls, which are measured in phase 2 before any atlasing.
- **Engineering stays an estimate.** The fidelity gate refuses engineering
  use of the humanoid. Attire estimates follow the anatomy-validity pattern
  and cite sources. Historical numbers disagree; the tables carry ranges.
- **Licenses.** Port only MIT code (PositionBasedDynamics, three-vrm, Velvet)
  with a notice in `THIRD-PARTY-NOTICES.md`. MakeHuman and Blender are read
  for their formats and ideas only.
- **Test time.** Shelling the full body field is the slow step. Tests shell a
  limb at low detail and check the full body in the example and the gallery.
- **Bake digests.** Adding a garment to a sealed bake changes its digest by
  design. Dress first, seal second.

## 8. Sources

Games and talks

- GDC Vault, *Adaptive Clothing System in Kingdom Come: Deliverance*, Tomas Barak, Warhorse, GDC Europe 2015. https://gdcvault.com/play/1022771/Adaptive-Clothing-System-in-Kingdom
- GDC Vault, *Dressed to Quest: Achieving Dynamic, Efficient Characters in Kingdom Come: Deliverance II*, Gabor Molnar, Warhorse, GDC 2025. https://gdcvault.com/play/1035519/Dressed-to-Quest-Achieving-Dynamic
- Kingdom Come forum, *Layering system and medieval clothing explained*. https://forum.kingdomcomerpg.com/t/layering-system-and-medieval-clothing-explained-lots-of-pictures/9396
- Roblox Creator Hub, *Layered clothing example* and *Caging best practices*. https://create.roblox.com/docs/resources/beyond-the-dark/layered-clothing and https://create.roblox.com/docs/art/accessories/caging-best-practices
- Roblox `WrapLayer` reference. https://create.roblox.com/docs/reference/engine/classes/WrapLayer
- Patents US11615601, US12374067, US12190427 (layered clothing). https://patents.google.com/patent/US11615601 https://patents.google.com/patent/US12374067 https://patents.google.com/patent/US12190427
- inZOI ModKit, *Masking System*. https://mod-docs.playinzoi.com/ModKit/project/CAZ/Guide/03.%20Masking%20System.html
- Epic, *Using Mutable and MetaHumans*. https://dev.epicgames.com/documentation/unreal-engine/using-mutable-and-metahumans-in-unreal-engine
- Epic, Chaos Cloth *SimulationMaxDistanceConfig* and *SimulationBackstopConfig*. https://dev.epicgames.com/documentation/unreal-engine/node-reference/Dataflow/SimulationMaxDistanceConfig
- VRM, *Spring bone*. https://vrm.dev/univrm1/vrm1_tutorial/springbone
- Steam, Monster Hunter Wilds layered appearance discussion. https://steamcommunity.com/app/2246340/discussions/0/596270305199047658
- Destructoid, FF XIV dye channels. https://destructoid.com/final-fantasy-xiv-fans-are-losing-their-minds-a-little-over-how-dye-channels-work-on-specific-clothes
- Gameranx, Shadow of the Erdtree armor. https://gameranx.com/features/id/503064/article/shadow-of-the-erdtree-10-best-armor-sets-where-to-find-them/
- Steam, Dragon's Dogma 2 slot discussion. https://steamcommunity.com/app/2054970/discussions/0/4289188517341039084/
- Laptop Mag on Dragon's Dogma 2 capes. https://laptopmag.com/gaming/i-hate-dragons-dogma-2s-character-creator-and-its-not-for-the-reason-you-think
- MakeHuman, *MakeClothes* and the `mhclo` pipeline. https://static.makehumancommunity.org/assets/creatingassets/makeclothes/clothes.html

Papers

- Müller, Heidelberger, Hennix, Ratcliff, *Position Based Dynamics*, 2007.
- Macklin, Müller, Chentanez, *XPBD: Position-Based Simulation of Compliant Constrained Dynamics*, MIG 2016.
- Macklin et al., *Small Steps in Physics Simulation*, SCA 2019. https://diglib.eg.org/bitstreams/5ccd0aa4-edd9-48a1-8ed5-1c50d227a37a/download
- Kim, Chentanez, Müller-Fischer, *Long Range Attachments*, SCA 2012. https://diglib.eg.org/handle/10.2312/SCA.SCA12.305-310
- Fratarcangeli, Tibaldo, Pellacini, *Vivace*, ACM TOG 35(6), 2016. https://research.chalmers.se/publication/507089
- Baraff, Witkin, *Large Steps in Cloth Simulation*, SIGGRAPH 1998. https://www.cs.cornell.edu/courses/cs667/2005sp/readings/baraff98.pdf
- Grigorev, Black, Hilliges, *HOOD*, CVPR 2023. https://openaccess.thecvf.com/content/CVPR2023/papers/Grigorev_HOOD_Hierarchical_Graphs_for_Generalized_Modelling_of_Clothing_Dynamics_CVPR_2023_paper.pdf
- Grigorev et al., *ContourCraft*, SIGGRAPH 2024. https://arxiv.org/abs/2405.09522
- Ma et al., *CAPE*, CVPR 2020. https://research-collection.ethz.ch/bitstream/20.500.11850/466890/1/CAPE_paper.pdf
- Korosteleva, Sorkine-Hornung, *GarmentCode*, SIGGRAPH Asia 2023. https://arxiv.org/html/2306.03642v2 and https://pypi.org/project/pygarment/

Code

- https://github.com/InteractiveComputerGraphics/PositionBasedDynamics
- https://github.com/pixiv/three-vrm
- https://github.com/vitalight/Velvet
- https://github.com/nitronoid/csb
- https://github.com/maria-korosteleva/GarmentCode
- three.js examples `physics_ammo_cloth` and `webgl_physics_volume`

Engineering numbers

- Alan Williams, *The Knight and the Blast Furnace*, and his monograph on medieval armor manufacture. https://emono.unibas.ch/sonderpublikationen-abbs/catalog/download/105/205/1538
- myArmoury threads quoting Williams. https://myarmoury.com/talk/viewtopic.php?p=244604
- Askew, Formenti, Minetti, *Limitations imposed by wearing armour on Medieval soldiers' locomotor performance*, Proc. R. Soc. B 2012. https://pmc.ncbi.nlm.nih.gov/articles/PMC3248716
- Lazar, Kraner, breastplate thickness study, 2019. https://journals.iaepan.pl/fah/article/view/1765
- Cleveland Museum of Art hauberks. https://www.clevelandart.org/art/95865 and https://www.clevelandart.org/art/95874
- Wikipedia, *Hauberk*, *Breastplate*, *Gambeson*.
