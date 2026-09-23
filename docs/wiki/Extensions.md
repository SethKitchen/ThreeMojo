# Extensions

`extensions/` holds content that is not a three.js port. Core stays a port of three.js. Water, plants, buildings and a humanoid live here, in a folder per subject.

The first subject is the humanoid. The leg bones are the femur, tibia, fibula and patella, plus the knee tissues. Named muscles, vessels, lymph, nerves, skin and hair complete that limb. `assemble_leg` connects the limb. The foot adds twenty-six bones and the soft tissues distal to the plafond. `assemble_foot` connects that foot.

The water subject ports Clearwater. See [Water](Water).

See [Femur](Femur), [Tibia](Tibia), [Fibula](Fibula), [Patella](Patella), [Knee](Knee) and [Muscles](Muscles). See [Vessels](Vessels), [Lymph](Lymph), [Nerves](Nerves), [Integument](Integument), [Leg](Leg) and [Foot](Foot).

## Layout

```text
extensions/
  humanoid/
    spec.mojo          HumanoidSpec: stature, sex and athleticism
    sex.mojo           MALE, FEMALE
    side.mojo          RIGHT, LEFT
    athleticism.mojo   UNTONED, TONED
    skeleton/
      tissue.mojo      density, porosity and moduli
      bone.mojo        PBR maps and a Phong stand-in
      field.mojo       signed-distance primitives
      isosurface.mojo  marching tetrahedra
      occupancy.mojo   tissue fill and mass tally
      look.mojo        cartilage, meniscus, ligament, muscle, vessel, lymph, nerve, skin and hair Phong
      soft_tissue.mojo named hydrated-tissue density
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
  water/
    spectrum.mojo  ocean spectrum and dispersion
    ripple.mojo    local wave equation
    caustics.mojo  refracted-grid caustics
    frame.mojo     one shaded picture
    pebbles.mojo   the pebble photograph
    filter.mojo    mipmaps and anisotropy
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
