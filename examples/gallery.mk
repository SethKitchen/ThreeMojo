# The gallery: one line per image that `make animation` renders. Each line is
#     $(call gallery,IMAGE,EXAMPLE[,EXTRA PREREQUISITES])
# and renders out/IMAGE.png with examples/EXAMPLE.mojo, then compresses it.
# Add an example's image here, not in the Makefile. The Makefile keeps only
# the few recipes that need other steps, such as written credits.

$(call gallery,spin,spin)
$(call gallery,cube,cube)
$(call gallery,cubes,cubes)
# Two frames, perspective-correct and affine, of the same prepared triangles.
$(call gallery,uv,uv)
# A checkerboard cube: scene graph, culling, depth, uv and sampling together.
$(call gallery,textured,textured)
# Translucent panes over a solid cube: blending, sorting and linear light.
$(call gallery,glass,glass)
# A receding floor, half mipmapped and half not: minification and aliasing.
$(call gallery,floor,floor)
# Three colored lamps on a coarse sphere: many lights, and per-fragment shading.
$(call gallery,lamps,lamps)
$(call gallery,rotations,rotations)
$(call gallery,cameras,ortho)
$(call gallery,geometry,geometry)
$(call gallery,instances,instances)
$(call gallery,raycast,raycast)
$(call gallery,curves,curves)
$(call gallery,keyframes,keyframes)
$(call gallery,skinning,skinning)
$(call gallery,phong,phong)
$(call gallery,fog,fog)
$(call gallery,culling,culling)
$(call gallery,clipping,clipping)
$(call gallery,gpu_backend,gpu_backend)
$(call gallery,exposure,exposure)
$(call gallery,model,model,assets/cube.obj)
$(call gallery,math,orbit)
$(call gallery,units,clock)
$(call gallery,chain,chain)
$(call gallery,additive,additive)
$(call gallery,normals,normals)
$(call gallery,fragments,fragments)
$(call gallery,coverage,edges)
$(call gallery,lines,lines)
# A grid, the axes, a box around a cube and a second camera's frustum.
$(call gallery,helpers,outlines)
# A split screen: two viewports and two scissors drawing into one target.
$(call gallery,split,split)
# A chrome ball under a sky, reflecting a cube camera's view of two boxes.
$(call gallery,mirror,mirror)
# Ten spheres from chalk to mirror and from dielectric to metal, under a sky.
$(call gallery,physical,physical)
$(call gallery,sprites,sprites)
$(call gallery,stereo,stereo)
$(call gallery,television,television)
# A cube's shadow swings across a floor as a directional lamp orbits.
$(call gallery,shadows,shadows)
# A ribbon eight pixels wide, drawn as triangles, turns with a box.
$(call gallery,wide,wide)
# Bloom and a vignette over a dark knot and two emissive spheres.
$(call gallery,postprocessing,bloom)
# Translate handles on a cube, redrawn as the camera orbits.
$(call gallery,controls,gizmo)
# A scene written as three.js JSON and read back before it is drawn.
$(call gallery,scenejson,json_scene)
# A knot written to glTF and read back before it is drawn.
$(call gallery,exporters,reloaded)
# A glass sphere refracts three colored boxes.
$(call gallery,transmission,gem)
# Distance from a point, packed into the color of a sphere.
$(call gallery,distance,distance)
# Three cubes in fog. The middle material has fog turned off.
$(call gallery,unfogged,unfogged)
# A float color attachment above a normal attachment.
$(call gallery,targets,targets)
# Sheen, iridescence and anisotropy on three spheres.
$(call gallery,layers,layers)
# A node graph tints a sphere and pushes its vertices.
$(call gallery,nodes,graph)
# Clearcoat bands and a specular color map on two spheres.
$(call gallery,coats,coats)
# A metal ball whose sky was written as scene JSON and read back.
$(call gallery,environment,skyjson)
# Preetham's daylight sky, with the sun crossing above a sphere.
$(call gallery,sky,daylight)
# One box, a different material on each face.
$(call gallery,faces,faces)
# The Utah teapot, from the geometry addons.
$(call gallery,teapot,utah)
# Two metaballs joined by marching cubes.
$(call gallery,blobs,blobs)
# A morph flip-book beside a gyroscope.
$(call gallery,animated,flipbook)
# A ripple field computed one step a frame.
$(call gallery,computation,ripples)
# A light map that gathers a walking lamp.
$(call gallery,lightmap,baked)
# An SVG drawing of an icosahedron and a box, filled into a PNG.
$(call gallery,svg,diagram)
# An LDraw model loaded from the parts library.
$(call gallery,models,bricks,assets/ldraw/scene.mpd)
# A height field from simplex noise.
$(call gallery,mathaddons,terrain)
# An override material, refused by the middle sphere.
$(call gallery,hooks,override)
# An inflated knob on a turning sphere.
$(call gallery,sculptor,clay)
# Voronoi cells on a turning sphere.
$(call gallery,tslfunctions,cells)
# A cloud of Gaussian splats.
$(call gallery,gaussian,cloud)
# Bounced light in a colored corner.
$(call gallery,vxgi,bounce)
# A low sun and its two shadow cascades.
$(call gallery,lighting,sunlight)
# A vase skinned through loft sections.
$(call gallery,lofts,vase)
# A tree grown from a seed.
$(call gallery,generators,sapling)
# Points stepped by a compute kernel.
$(call gallery,computenodes,particles)
# A small building model, cut away above its ground floor.
$(call gallery,building-model,building_model)
# The cells of a cell complex, pulled apart.
$(call gallery,building-topology,room_cells)
# A tower read back from its IFC file.
$(call gallery,ifc-exchange,exchange)
# A seeded tower as a building model.
$(call gallery,procedural-towers,towers)
# A furnished floor of homes, cut away.
$(call gallery,floor-plans-and-interiors,interiors)
# A tower frame swaying in its first mode.
$(call gallery,frame-analysis,frame_modes)
# A plate bending under a pressure.
$(call gallery,shell-analysis,plate)
# Rooms through a summer day, by temperature.
$(call gallery,building-energy,heat)
# The lowest modes of a chain of springs.
$(call gallery,numerics,spring_modes)
$(call gallery,femur,femur)
$(call gallery,tibia,tibia)
$(call gallery,fibula,fibula)
$(call gallery,patella,patella)
$(call gallery,knee,knee)
$(call gallery,muscles,muscles)
$(call gallery,leg,leg)
$(call gallery,legs,legs)
$(call gallery,foot,foot)
$(call gallery,limb,limb)
$(call gallery,vessels,vessels)
$(call gallery,lymph,lymph)
$(call gallery,nerves,nerves)
$(call gallery,integument,integument)
# The lower body: the pelvis, both legs and both feet, with skin and without.
$(call gallery,pelvis,pelvis)
# A body below the neck, arms included, with skin and without.
$(call gallery,torso,torso)
# An arm and its hand, with skin and without.
$(call gallery,arm,arm)
# A hand and its fingers, with skin and without.
$(call gallery,hand,hand)
# A neck and a head, with skin and without.
$(call gallery,head,head)
$(call gallery,water,water,assets/pebbles.jpg)
# Every procedural animal, one to a tile, turning.
$(call gallery,animals,animals)
# A wolf walks one stride, re-meshed in each pose.
$(call gallery,walk,walk)
# Game mode beside engineering mode, at real size and walking speed.
$(call gallery,animal_anatomy,animal_anatomy)
$(call gallery,game_humanoid,game_humanoid)
$(call gallery,hairstyles,hairstyles)
$(call gallery,genomes,genomes)
$(call gallery,family,family)
$(call gallery,talking,talking)
$(call gallery,expressions,expressions)
# The CPU fallback upscaler beside the full-size render. It is not DLSS, and no image of it is tracked.
$(call gallery,streamline,streamline)
