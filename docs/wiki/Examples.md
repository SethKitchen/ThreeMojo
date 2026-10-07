# Examples

`examples/`. Each example is one program that renders one image or animation into `out/`. `make animation` renders all of them except `carla.mojo` and `carla_town.mojo`.

Run one by hand:

```bash
mkdir -p out
.venv/bin/mojo run -I . examples/cubes.mojo out/cubes.png
```

| Example | Output | Page |
|---|---|---|
| `triangle.mojo` | `triangle.png` | The smallest program that draws. |
| `spin.mojo` | `spin.png` | [Image files](Image-files) |
| `cube.mojo` | `cube.png` | [Why a software rasterizer](Why-a-software-rasterizer) |
| `cubes.mojo` | `cubes.png` | [Scene graph](Scene-graph) |
| `uv.mojo` | `uv.png` | [Why interpolation is perspective-correct](Why-interpolation-is-perspective-correct) |
| `textured.mojo` | `textured.png` | [Textures](Textures) |
| `glass.mojo` | `glass.png` | [Why transparency is sorted](Why-transparency-is-sorted) |
| `floor.mojo` | `floor.png` | [Why mipmaps](Why-mipmaps) |
| `photo.mojo` | `photo.png` | A decoded PNG on a cube. The README figure. |
| `lamps.mojo` | `lamps.png` | [Lights](Lights) |
| `first_scene.mojo` | `first_scene.png` | [Render your first scene](Tutorial-Render-your-first-scene) |
| `lit_scene.mojo` | `lit_scene.png` | [Light, texture and animate](Tutorial-Light-texture-and-animate) |
| `rotations.mojo` | `rotations.png` | [Rotations](Rotations) |
| `ortho.mojo` | `cameras.png` | [Cameras](Cameras) |
| `stereo.mojo` | `stereo.png` | [Cameras](Cameras#stereocamera) |
| `geometry.mojo` | `geometry.png` | [Geometry](Geometry) |
| `instances.mojo` | `instances.png` | [Meshes and assets](Meshes-and-assets) |
| `raycast.mojo` | `raycast.png` | [Raycasting](Raycasting) |
| `curves.mojo` | `curves.png` | [Curves and paths](Curves) |
| `lines.mojo` | `lines.png` | [Lines](Lines) |
| `sprites.mojo` | `sprites.png` | [Points and sprites](Points-and-sprites) |
| `television.mojo` | `television.png` | [Textures](Textures#from-a-render) |
| `mirror.mojo` | `mirror.png` | [Textures](Textures#cube-textures) |
| `outlines.mojo` | `helpers.png` | [Helpers](Helpers) |
| `keyframes.mojo` | `keyframes.png` | [Animation](Animation) |
| `skinning.mojo` | `skinning.png` | [Skinning](Skinning) |
| `phong.mojo` | `phong.png` | [Materials](Materials) |
| `physical.mojo` | `physical.png` | [Materials](Materials#standard-and-physical) |
| `fog.mojo` | `fog.png` | [Fog](Fog) |
| `culling.mojo` | `culling.png` | [Renderer](Renderer) |
| `split.mojo` | `split.png` | [Renderer](Renderer#viewport-and-scissor) |
| `clipping.mojo` | `clipping.png` | [Rasterization](Rasterization) |
| `gpu_backend.mojo` | `gpu_backend.png` | [GPU backend](GPU-backend) |
| `exposure.mojo` | `exposure.png` | [Render target and framebuffer](Render-target-and-framebuffer) |
| `model.mojo` | `model.png` | [Model files](Model-files) |
| `orbit.mojo` | `math.png` | [Math](Math) |
| `clock.mojo` | `units.png` | [Units](Units) |
| `chain.mojo` | `chain.png` | [Why the scene graph is an array](Why-the-scene-graph-is-an-array) |
| `additive.mojo` | `additive.png` | [Why color is linear](Why-color-is-linear) |
| `normals.mojo` | `normals.png` | [Why a normal is not a color](Why-a-normal-is-not-a-color) |
| `fragments.mojo` | `fragments.png` | [Why shading is per fragment](Why-shading-is-per-fragment) |
| `edges.mojo` | `coverage.png` | [Why coverage uses fixed point](Why-coverage-uses-fixed-point) |
| `shadows.mojo` | `shadows.png` | [Lights](Lights#shadows) |
| `wide.mojo` | `wide.png` | [Lines](Lines#wide-lines) |
| `bloom.mojo` | `postprocessing.png` | [Post-processing](Post-processing) |
| `gizmo.mojo` | `controls.png` | [Windowing and controls](Windowing-and-controls) |
| `json_scene.mojo` | `scenejson.png` | [Scene JSON](Scene-JSON) |
| `reloaded.mojo` | `exporters.png` | [Exporters](Exporters) |
| `gem.mojo` | `transmission.png` | [Materials](Materials#transmission) |
| `distance.mojo` | `distance.png` | [Materials](Materials#meshdistancematerial) |
| `unfogged.mojo` | `unfogged.png` | [Materials](Materials#fog-switch) |
| `targets.mojo` | `targets.png` | [Render target and framebuffer](Render-target-and-framebuffer#float-render-targets) |
| `layers.mojo` | `layers.png` | [Materials](Materials#sheen) |
| `graph.mojo` | `nodes.png` | [Node materials](Node-materials) |
| `basis.mojo` | `ktx2.png` | [Textures](Textures#ktx2-and-compressed-formats) |
| `coats.mojo` | `coats.png` | [Materials](Materials#specular-and-clearcoat-maps) |
| `skyjson.mojo` | `environment.png` | [Scene JSON](Scene-JSON#cube-textures) |
| `daylight.mojo` | `sky.png` | [Scene objects](Scene-objects#sky) |
| `faces.mojo` | `faces.png` | [Meshes and assets](Meshes-and-assets#several-materials) |
| `utah.mojo` | `teapot.png` | [Geometry addons](Geometry-addons#teapot) |
| `blobs.mojo` | `blobs.png` | [Scene objects](Scene-objects#marching-cubes) |
| `flipbook.mojo` | `animated.png` | [Animated objects](Animated-objects) |
| `ripples.mojo` | `computation.png` | [GPU computation](GPU-computation) |
| `baked.mojo` | `lightmap.png` | [Progressive light map](Progressive-light-map) |
| `diagram.mojo` | `svg.png` | [SVG renderer](SVG-renderer) |
| `bricks.mojo` | `models.png` | [More model files](More-model-files) |
| `terrain.mojo` | `mathaddons.png` | [Math addons](Math-addons) |
| `override.mojo` | `hooks.png` | [Renderer hooks and material flags](Renderer-hooks-and-material-flags) |
| `clay.mojo` | `sculptor.png` | [Sculptor](Sculptor) |
| `cells.mojo` | `tslfunctions.png` | [TSL functions](TSL-functions) |
| `cloud.mojo` | `gaussian.png` | [Gaussian splats](Gaussian-splats) |
| `bounce.mojo` | `vxgi.png` | [Voxel global illumination](Voxel-global-illumination) |
| `sunlight.mojo` | `lighting.png` | [Lighting addons](Lighting-addons) |
| `vase.mojo` | `lofts.png` | [Lofts and clipping groups](Lofts-and-clipping-groups) |
| `sapling.mojo` | `generators.png` | [Procedural generators](Procedural-generators) |
| `particles.mojo` | `computenodes.png` | [Compute nodes](Compute-nodes) |
| `towers.mojo` | `procedural-towers.png` | [Procedural towers](Procedural-towers) |
| `interiors.mojo` | `floor-plans-and-interiors.png` | [Floor plans and interiors](Floor-plans-and-interiors) |
| `room_cells.mojo` | `building-topology.png` | [Building topology](Building-topology) |
| `building_model.mojo` | `building-model.png` | [Building model](Building-model) |
| `exchange.mojo` | `ifc-exchange.png` | [IFC exchange](IFC-exchange) |
| `frame_modes.mojo` | `frame-analysis.png` | [Frame analysis](Frame-analysis) |
| `plate.mojo` | `shell-analysis.png` | [Shell analysis](Shell-analysis) |
| `heat.mojo` | `building-energy.png` | [Building energy](Building-energy) |
| `spring_modes.mojo` | `numerics.png` | [Numerics](Numerics) |
| `audio_game_humanoid.mojo` | `audio-character.glb` | [Audio-aligned game faces](Audio-aligned-game-faces) |
| `carla_towns.mojo` | `carla_towns.png` | [CARLA rendering](CARLA-rendering) |
| `femur.mojo` | `femur.png` | [Femur](Femur) |
| `tibia.mojo` | `tibia.png` | [Tibia](Tibia) |
| `fibula.mojo` | `fibula.png` | [Fibula](Fibula) |
| `patella.mojo` | `patella.png` | [Patella](Patella) |
| `knee.mojo` | `knee.png` | [Knee](Knee) |
| `muscles.mojo` | `muscles.png` | [Muscles](Muscles) |
| `leg.mojo` | `leg.png` | [Leg](Leg) |
| `legs.mojo` | `legs.png` | [Leg](Leg) |
| `foot.mojo` | `foot.png` | [Foot](Foot) |
| `limb.mojo` | `limb.png` | [Leg](Leg) |
| `vessels.mojo` | `vessels.png` | [Vessels](Vessels) |
| `lymph.mojo` | `lymph.png` | [Lymph](Lymph) |
| `nerves.mojo` | `nerves.png` | [Nerves](Nerves) |
| `integument.mojo` | `integument.png` | [Integument](Integument) |
| `pelvis.mojo` | `pelvis.png` | [Pelvis](Pelvis) |
| `torso.mojo` | `torso.png` | [Torso](Torso) |
| `arm.mojo` | `arm.png` | [Arm](Arm) |
| `hand.mojo` | `hand.png` | [Hand](Hand) |
| `head.mojo` | `head.png` | [Head](Head) |
| `genomes.mojo` | `genomes.png` | [Genome](Genome) |
| `family.mojo` | `family.png` | [Genome](Genome) |
| `expressions.mojo` | `expressions.png` | [Head](Head) |
| `talking.mojo` | `talking.png` | [Head](Head) |
| `hairstyles.mojo` | `hairstyles.png` | [Head](Head) |
| `game_humanoid.mojo` | `game_humanoid.png` | [Game humanoid](Game-humanoid) |
| `water.mojo` | `water.png` | [Water](Water) |
| `animals.mojo` | `animals.png` | [Animals](Animals) |
| `walk.mojo` | `walk.png` | [Animals](Animals) |
| `animal_anatomy.mojo` | `animal_anatomy.png` | [Animal anatomy](Animal-anatomy) |
| `carla.mojo` | `carla.png` | [CARLA](CARLA) |
| `carla_town.mojo` | `carla_town.png` | [CARLA rendering](CARLA-rendering) |

`photo.mojo` takes the image path first: `examples/photo.mojo assets/brick.png out/photo.png`.

`pelvis.mojo`, `torso.mojo`, `arm.mojo`, `hand.mojo`, `head.mojo`, `genomes.mojo`, `family.mojo`, `expressions.mojo`, `talking.mojo` and `hairstyles.mojo` take a mesh quality after the path: `low`, `medium`, `high` or `xhigh`. See [Mesh quality](Mesh-quality).

```bash
.venv/bin/mojo run -I . examples/torso.mojo out/torso.png low
```

`make animation` does not render the two CARLA examples. Run them by hand: `mojo run -I . examples/carla.mojo out/carla.png` and `mojo run -I . examples/carla_town.mojo out/carla_town.png`.

`viewer.mojo` writes no file. It opens a window in the terminal, and `make viewer` runs it. See [Windowing and controls](Windowing-and-controls).

Animated outputs are APNG files. A browser or VS Code plays them. A viewer that does not know APNG shows the first frame.

## Benchmarks

`tools/bench_examples.py` times the catalog against three.js and, when installed, Mojo 1.0.
[Benchmarks](Benchmarks) names every other CPU bench and records who wins.
The refresh command is in [How to measure examples](How-to-measure-examples).

## Tools

| Program | Shows |
|---|---|
| `tools/gpu_status.py` | Whether an accelerator is present. |
| `tools/doc_lint.mojo` | Whether the documentation follows the writing rules. |
