# Extensions

`extensions/` holds content that is not a three.js port. Core stays a port of three.js. Water, plants, buildings, a humanoid and driving simulation live here, in a folder per subject.

The first subject is the humanoid. The leg bones are the femur, tibia, fibula and patella, plus the knee tissues. Named muscles, vessels, lymph, nerves, skin and hair complete that limb. `assemble_leg` connects the limb. The foot adds twenty-six bones and the soft tissues distal to the plafond. `assemble_foot` connects that foot.

The attire subject dresses the game humanoid. Each garment is a shell of the wearer's own skin, cut at clean hems and layered from the skin out. Plate rides its bones, cloaks and scabbards swing, and estimates give mass, cost and protection. See [Garments](Garments), [Outfits and armor](Outfits-and-armor), [Cloth and spring bones](Cloth-and-spring-bones) and [Attire estimates](Attire-estimates).

The water subject ports Clearwater. See [Water](Water).

The vegetation subject grows a summer meadow: grass in clusters with levels of detail, wind, poppies, leafy trees, boulders and a painted sky. See [Vegetation](Vegetation) and [Why grass is drawn in clusters](Why-grass-is-drawn-in-clusters).

The village subject joins the meadow, buildings and water in one scene. Houses of the building model and a building cut out of a scan stand on lots where nothing grows, beside a pond of Clearwater water. See [Village](Village) and [Village houses](Village-houses). Dressed people and animals wander the village, and a player walks through it in front of a third-person camera. See [Village walk](Village-walk).

The animals subject ports procedural-animals: 24 species sculpted as distance fields, posed and painted. See [Animals](Animals). Its distance field sculpting and meshing live in `extensions/sdf/`, so other subjects can use them. Its anatomy, mass and muscles build on `extensions/anatomy/`, which the humanoid shares. See [Animal anatomy](Animal-anatomy).

The building subject generates buildings for engineering analysis and for games from one canonical model. It has shared numerics, a cell complex, the building model, IFC exchange and procedural towers and interiors. Frame, shell and energy analysis read the same model. See [Why buildings have one canonical model](Why-buildings-have-one-canonical-model).

The scan subject reads splat scans of real places, in SOG and other formats, and puts them in meters with z up. It fills an occupancy grid that gives a static collider, and cuts the grid into parts to weigh, simulate and use again. It also cleans a scan, walks a physics capsule through it, and makes a scan of any rendered scene. The building subject fits a building model of a reusable construction kit to the grid, and takes the gravity load down its walls. A pinned manifest downloads the scans, and a GPU draws one at 50 frames a second at 1920 by 1080. See [Scanned buildings](Scanned-buildings), [Scan parts](Scan-parts), [Cleaning and orienting scans](Cleaning-and-orienting-scans), [Walking through a scan](Walking-through-a-scan), [GPU splats](GPU-splats) and [Virtual scans](Virtual-scans).

The castle subject builds a moated brick castle from a plan and draws it under the sun of a date and an hour. It ships the plan of Wijnendale Castle in West Flanders. It checks the wind on its donjon, the arch of its bridge, its quay wall, the water of its moat and its shadows. See [Castle](Castle) and [Castle analysis](Castle-analysis). The castle also stands in a [landscape](Landscape) of mountains, woods and lakes, beside a church that was scanned as Gaussian splats.

The geotech subject analyzes earth-retaining walls: earth and water pressure, LRFD stability and slip circles. The visual subject draws engineering results with meshes, labels and textures. See [Retaining walls](Retaining-walls) and [Engineering views](Engineering-views).

The chemistry subject is a library for the steps of a process. It models the thermodynamic, phase, kinetic, physical and engineering requirements that turn a material into a product. Each step has an operating window, and new constraints and data plug in. It also solves equilibria, draws process maps and solves flowsheets. See [Process chemistry](Process-chemistry) and [Why a process runs where it does](Why-a-process-runs-where-it-does).

The imaging subject reads DICOM images and stacks them into volumes with physical spacing. It draws a volume by ray casting, and it labels, measures and overlays regions on slices. See [Medical imaging](Medical-imaging).

The molecule subject reads mmCIF structures, builds ideal peptides, and draws ribbons and surfaces. See [Molecular structures](Molecular-structures).

The fem subject solves static elasticity on tetrahedral meshes, from a box or from the voxels of a label. See [Tetrahedral FEM](Tetrahedral-FEM). These three subjects are for research and teaching. They are not medical devices.

The CARLA subject ports the CARLA driving simulator without its game engine and its network transport. It covers maps, physics, the world, sensors, traffic, agents, recording and rendering. See [CARLA](CARLA).

The gamepad subject ports the gamepad subsystem of SDL. It reads Xbox, PlayStation, Nintendo and other controllers on Linux and through a host's own gamepad API, and names their controls by position. It runs their rumble, lights, motion sensors and touchpads. See [Gamepads](Gamepads).

The warp subject ports WarpFactory. It finds the stress-energy tensor that a warp drive metric needs, and checks the energy conditions. It adds exact derivatives, more metrics, energy totals, curvilinear grids and geodesics. See [Warp drives](Warp-drives).

The Streamline subject types NVIDIA's DLSS 4.5 Super Resolution and Ray Reconstruction: modes, presets, options, per-frame constants and buffer checks. It has a CPU fallback upscaler, and a native Windows host that runs both features through `sl.interposer`. See [Streamline](Streamline).

See [Femur](Femur), [Tibia](Tibia), [Fibula](Fibula), [Patella](Patella), [Knee](Knee) and [Muscles](Muscles). See [Vessels](Vessels), [Lymph](Lymph), [Nerves](Nerves), [Integument](Integument), [Leg](Leg) and [Foot](Foot).

## Layout

```text
extensions/
  attire/
    kinds.mojo         slots, layers, fabrics, articulations, dyes and wear
    quantities.mojo    ArealDensity
    fabric.mojo        each fabric's constants and look
    cover.mojo         what a garment covers, joint by joint
    mesh_ops.mojo      weld, cut along a level, merge
    shell.mojo         a garment's shell from the skin
    garment.mojo       Garment and the wardrobe
    dye.mojo           dye patterns, wear and paint
    surface.mojo       texture coordinates and bump maps
    plates.mojo        rigid plate and lames
    outfit.mojo        Outfit and dress
    binding.mojo       garments made elsewhere, fitted to any body
    sockets.mojo       named places that ride bones
    props.mojo         a heater shield, a sword in its scabbard
    preset.mojo        saved outfits and dressed bakes
    springs.mojo       VRM-style spring chains
    cloth.mojo         XPBD cloth and cloaks
    cloth_gpu.mojo     the cloth solve on a GPU
    estimate.mojo      mass, cost, coverage and protection
  humanoid/
    spec.mojo          HumanoidSpec: stature, sex, athleticism and genome
    genome.mojo        Genome, Gene, Expression, inheritance
    rig/
      joints.mojo      the nineteen joints of a game skeleton
      weights.mojo     skin weights measured over the skin
      clips.mojo       idle, walk, run, jump and wave
      game.mojo        a skinned humanoid on its skeleton
    sex.mojo           MALE, FEMALE
    side.mojo          RIGHT, LEFT
    athleticism.mojo   UNTONED, TONED
    skeleton/
      bone.mojo        PBR maps and a Phong stand-in
      field.mojo       signed-distance primitives
      isosurface.mojo  marching tetrahedra
      surface_nets.mojo smooth narrow-band skin meshes
      sculpt.mojo      clay: ellipsoids, capsules and hollows
      morph.mojo       how a genome reshapes the head
      complexion.mojo  skin, hair and iris pigment and maps
      occupancy.mojo   tissue fill and mass tally
      look.mojo        cartilage, meniscus, ligament, muscle, vessel, lymph, nerve, skin, hair and eye looks
      soft_tissue.mojo grid-sampled soft-tissue mass
      leg/
        assembly.mojo  one connected limb
        contents.mojo  named layer bits
        femur/     dimensions, geometry, mass
        tibia/     dimensions, geometry, mass
        fibula/    dimensions, geometry, mass
        patella/   dimensions, geometry, mass
        knee/      cartilage, menisci, collaterals
        muscles/   named skeletal muscles
        vessels/   arteries and veins
        lymph/     nodes and trunks
        nerves/    peripheral nerves
        skin/      envelope
        hair/      thigh and calf shafts
      foot/
        assembly.mojo  one connected foot
        contents.mojo  named layer bits
        chain.mojo     shared segments and tubes
        bones/     twenty-six bones
        ligaments/ ankle and foot ligaments
        muscles/   tendons and intrinsic bellies
        vessels/   arteries and veins
        lymph/     lymphatic trunks
        nerves/    peripheral nerves
        skin/      envelope
        hair/      dorsal and digital shafts
  anatomy/
    tissue.mojo      bone density, porosity and moduli
    soft_tissue.mojo named hydrated-tissue density
    inertia.mojo     mass, center and inertia, tallied cell by cell
    muscle.mojo      Hill-type muscle, Thelen's curves, moment arms
    locomotion.mojo  Froude number, stride length and frequency
    mode.mojo        game mode and engineering mode
    evidence.mojo    how far a published value was checked
  sdf/
    vector.mojo    Vec3d helpers, frames and rigid transforms
    ids.mojo       primitive kinds, bones, tags and surface parts
    field.mojo     primitives, smooth unions and carvers
    sculpt.mojo    aimed ellipsoids and Catmull-Rom tubes
    mesher.mojo    narrow-band surface nets
  animals/
    parts.mojo     the named surface parts of an animal
    kit.mojo       eyes and head-local frames
    rig.mojo       joints, bones and poses
    warp.mojo      seeded proportion warps
    coat.mojo      surface classes, palettes and eyes
    build.mojo     create, pose, mesh, paint and occlude
    gait.mojo      the walk cycle
    registry.mojo  the 24 species
    species/       one sculpt, rig and coat per species
    anatomy/       published sizes, tissues, mass, muscles, standing
                   loads, bulging bellies, engineering layers, physics
  water/
    spectrum.mojo  ocean spectrum and dispersion
    ripple.mojo    local wave equation
    caustics.mojo  refracted-grid caustics
    frame.mojo     one shaded picture
    pebbles.mojo   the pebble photograph
    filter.mojo    mipmaps and anisotropy
  vegetation/
    kinds.mojo     plant kinds and cluster fates
    checks.mojo    shared range checks
    noise.mojo     a lattice hash and value noise
    wind.mojo      traveling gusts, a sway and a flutter
    blade.mojo     one blade, and a buffer of many
    ground.mojo    hills, grass masks, ground and mountains
    field.mojo     clusters, levels of detail, the blade stream
    limbs.mojo     branches grown by space colonization
    foliage.mojo   leaves, the light through a crown, and its wind
    litter.mojo    fallen leaves, twigs and pebbles
    crown.mojo     leafy trees and bushes
    rock.mojo      boulders
    sky.mojo       Preetham's sky with clouds, in a cube
    meadow.mojo    the whole scene, frame by frame
  carla/
    transform.mojo, math.mojo, geo.mojo, ...   frames and geometry
    opendrive.mojo, map.mojo, mesh_factory.mojo  OpenDRIVE maps
    physics/                                     rigid bodies, vehicles, walkers
    world.mojo, actor.mojo, blueprint.mojo, ...  the world and its actors
    radar.mojo, imu.mojo, sensor_manager.mojo, ... sensors
    traffic_manager*.mojo                        the traffic manager
    agents*.mojo, navigation*.mojo               agents and walker navigation
    recorder*.mojo, replayer*.mojo               the recorder
    town.mojo, render_*.mojo, camera_render.mojo rendering
  castle/
    kinds.mojo                             materials, roof kinds and provenance
    plan.mojo, wijnendale.mojo             the plan, and the plan of Wijnendale
    masonry.mojo                           masonry strength and stiffness
    wind.mojo, arch.mojo                   wind on the donjon, arch limit analysis
    moat_wall.mojo, moat_water.mojo        the quay wall and the water of the moat
    sun.mojo, shadow.mojo                  the sun over the site and its shadows
    parts.mojo, render.mojo                the mesh view of a plan
    look.mojo, textures.mojo               the materials and their maps
    reflect.mojo, sky.mojo, scene.mojo     the moat as a mirror, the sky, the scene
    trees.mojo, crowns.mojo, forest.mojo   trees, far crowns and woods
    landscape.mojo, landscape_mesh.mojo    the ground from meadow to mountains
  streamline/
    kinds.mojo      modes, presets and buffer kinds
    options.mojo    the options of Super Resolution and Ray Reconstruction
    sizing.mojo     render size and the check of Streamline's reply
    jitter.mojo     the jitter sequence
    constants.mojo  the per-frame constants from two cameras
    tags.mojo       the check of a frame's tagged buffers
    upscaler.mojo   the upscaler trait and a CPU fallback
    bundle.mojo     the frames that the native host reads, and its result
    native/         the Direct3D 12 host and its build script, for Windows
  warp/
    kinds.mojo, quantities.mojo, grid.mojo     kinds, units and the grid
    tensor.mojo, three_plus_one.mojo           tensor fields and the 3+1 split
    metrics.mojo, warp_shell.mojo              the metrics of WarpFactory
    natario.mojo, krasnikov.mojo               more metrics
    fell_heisenberg.mojo                       the positive-energy soliton
    curvilinear.mojo                           spherical and cylindrical metrics
    derivatives.mojo, solver.mojo              the Einstein equations
    gpu.mojo                                   the Einstein equations on a GPU
    jet.mojo, analytic.mojo                    exact derivatives
    frame.mojo, conditions.mojo, scalars.mojo  the analysis
    totals.mojo, geodesics.mojo                totals, geodesics, the passenger view
    flow.mojo, evaluation.mojo, plot.mojo      flow lines, one call, planes
  chemistry/
    quantities.mojo       molar values, amounts, pressures, angstroms
    kinds.mojo            phases, requirement kinds, checks and hazards
    elements.mojo         elements, atomic weights, formulas and their parser
    thermo.mojo           NASA-7, NASA-9 and Shomate fits, species, substances
    chemkin.mojo          CHEMKIN thermo files, read and written
    cea.mojo              a reader for NASA CEA thermo.inp files
    fitting.mojo          NASA-7 fits to tabulated data
    catalog.mojo          built-in substances
    reaction.mojo         reactions, their driving force, equilibria, uncertainty
    requirement.mojo      the Constraint trait and the built-in requirements
    window.mojo           operating windows for any constraint
    step.mojo             process steps and their reports
    equilibrium.mojo      multiphase chemical equilibrium
    maps.mojo             scans, Ellingham diagrams and predominance maps
    kinetics.mojo         Arrhenius rates and the shrinking core
    transport.mojo        evaporation, case depth and heating time
    electrochemistry.mojo cell voltages, Faraday's law and cell energy
    optics.mojo           the color of a thin film on a metal
    solution.mojo         binary solutions and their phase boundaries
    balance.mojo          stream enthalpies and heat duties
    flowsheet.mojo        units joined by streams, with recycle
    routes.mojo           the search for reaction routes
    materials.mojo        expansion curves, melting points, eutectics
    coating.mojo          coating stress, peeling, buckling and thermal shock
    crystal.mojo          a CIF reader, unit cells and bonds
    plot.mojo             chart axes for process figures
    production.mojo       the cost of a batch of grown crystals
    processes/            worked processes: titanium, diamond, lime, hpht, mpcvd
  imaging/
    ids.mojo              transfer syntaxes, slice axes, render modes, labels
    image_volume.mojo     a scalar grid with spacing, origin and axes
    dicom.mojo            the DICOM Part 10 reader
    dicom_write.mojo      the DICOM writer
    series.mojo           slice stacks, and volumes cut into slices
    nifti.mojo            NIfTI-1 volumes and label maps, read and written
    phantom.mojo          the Shepp-Logan head phantom
    transfer.mojo         windows and transfer functions
    raycast.mojo          the CPU volume ray caster
    labels.mojo           label maps, thresholds, region growing, surfaces
    measure.mojo          label statistics and distances
    overlay.mojo          slices, label overlays and measurement lines
    reformat.mojo         oblique slices on any plane
  molecule/
    ids.mojo              atom, residue, chain and model ids and kinds
    cif.mojo              the CIF tokenizer and data blocks
    structure.mojo        the mmCIF structure reader
    peptide.mojo          ideal peptide backbones
    dssp.mojo             helices and strands from hydrogen bonds
    ribbon.mojo           cartoon ribbons
    surface.mojo          accessible areas and surface meshes
  fem/
    ids.mojo              node, element and material ids, and axes
    mesh.mojo             tetrahedral meshes, box and voxel meshers
    elasticity.mojo       isotropic linear elastic tetrahedra
    static.mojo           supports, loads and the static solve
    post.mojo             the deformed surface colored by stress
    export.mojo           meshes and results as VTK files
```

Import from the module that defines the symbol. Do not put original content in `geometries/` or `objects/`. Those packages follow three.js.

## Rules

The house rules still apply. Quantities carry units. A kind is a type with `is_valid`. Tests cover every branch. Documentation follows the writing rules. `make check` must pass.

Scale from a named template. A humanoid is a stature, a sex and an athleticism. Each bone reads stature and sex and sizes itself.

Each muscle also reads athleticism. Vessels, lymph and nerves follow shared anatomical landmarks. Skin fits cross-sections around every modeled system. The foot uses those same rules distal to the tibial plafond.

Hair roots project onto that fitted skin. Do not hard-code a length in meters when a published relationship exists.

## Add one

1. Open an issue.
2. Put the module under `extensions/<subject>/`.
3. Write tests in `tests/test_<name>.mojo`.
4. Write a wiki page in `docs/wiki/`.
5. Tick the box in the README Extensions list.
6. Run `make check`.
