# Extensions

`extensions/` holds content that is not a three.js port. Core stays a port of three.js. Water, plants, buildings, a humanoid and driving simulation live here, in a folder per subject.

The first subject is the humanoid. The leg bones are the femur, tibia, fibula and patella, plus the knee tissues. Named muscles, vessels, lymph, nerves, skin and hair complete that limb. `assemble_leg` connects the limb. The foot adds twenty-six bones and the soft tissues distal to the plafond. `assemble_foot` connects that foot.

The water subject ports Clearwater. See [Water](Water).

The vegetation subject grows a summer meadow: grass in clusters with levels of detail, wind, poppies, leafy trees, boulders and a painted sky. See [Vegetation](Vegetation) and [Why grass is drawn in clusters](Why-grass-is-drawn-in-clusters).

The village subject joins the meadow, buildings and water in one scene. Houses of the building model and a building cut out of a scan stand on lots where nothing grows, beside a pond of Clearwater water. See [Village](Village).

The animals subject ports procedural-animals: 24 species sculpted as distance fields, posed and painted. See [Animals](Animals). Its distance field sculpting and meshing live in `extensions/sdf/`, so other subjects can use them. Its anatomy, mass and muscles build on `extensions/anatomy/`, which the humanoid shares. See [Animal anatomy](Animal-anatomy).

The building subject generates buildings for engineering analysis and for games from one canonical model. It has shared numerics, a cell complex, the building model, IFC exchange and procedural towers and interiors. Frame, shell and energy analysis read the same model. See [Why buildings have one canonical model](Why-buildings-have-one-canonical-model).

The scan subject reads splat scans of real places, in SOG and other formats, and puts them in meters with z up. It fills an occupancy grid that gives a static collider, and cuts the grid into parts to weigh, simulate and use again. It also cleans a scan and walks a physics capsule through it. The building subject fits a building model of a reusable construction kit to the grid, and takes the gravity load down its walls. A pinned manifest downloads the scans, and a GPU draws one at 50 frames a second at 1920 by 1080. See [Scanned buildings](Scanned-buildings), [Scan parts](Scan-parts), [Cleaning and orienting scans](Cleaning-and-orienting-scans), [Walking through a scan](Walking-through-a-scan) and [GPU splats](GPU-splats).

The geotech subject analyzes earth-retaining walls: earth and water pressure, LRFD stability and slip circles. The visual subject draws engineering results with meshes, labels and textures. See [Retaining walls](Retaining-walls) and [Engineering views](Engineering-views).

The CARLA subject ports the CARLA driving simulator without its game engine and its network transport. It covers maps, physics, the world, sensors, traffic, agents, recording and rendering. See [CARLA](CARLA).

The gamepad subject ports the gamepad subsystem of SDL. It reads Xbox, PlayStation, Nintendo and other controllers on Linux and through a host's own gamepad API, and names their controls by position. It runs their rumble, lights, motion sensors and touchpads. See [Gamepads](Gamepads).

The Streamline subject types NVIDIA's DLSS 4.5 Super Resolution and Ray Reconstruction: modes, presets, options, per-frame constants and buffer checks. It has a CPU fallback upscaler. It does not run DLSS yet. See [Streamline](Streamline).

See [Femur](Femur), [Tibia](Tibia), [Fibula](Fibula), [Patella](Patella), [Knee](Knee) and [Muscles](Muscles). See [Vessels](Vessels), [Lymph](Lymph), [Nerves](Nerves), [Integument](Integument), [Leg](Leg) and [Foot](Foot).

## Layout

```text
extensions/
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
  streamline/
    kinds.mojo      modes, presets and buffer kinds
    options.mojo    the options of Super Resolution and Ray Reconstruction
    sizing.mojo     render size and the check of Streamline's reply
    jitter.mojo     the jitter sequence
    constants.mojo  the per-frame constants from two cameras
    tags.mojo       the check of a frame's tagged buffers
    upscaler.mojo   the upscaler trait and a CPU fallback
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
