# Extensions

`extensions/` holds content that is not a three.js port. Core stays a port of three.js. Water, plants, buildings and a humanoid live here, in a folder per subject.

The first subject is the humanoid. The first bones are the femur, tibia, fibula and patella. The knee adds articular cartilage, both menisci and both collateral ligaments. The leg adds named skeletal muscles with an athleticism scale. `assemble_leg` connects one limb. See [Femur](Femur), [Tibia](Tibia), [Fibula](Fibula), [Patella](Patella), [Knee](Knee), [Muscles](Muscles) and [Leg](Leg).

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
      look.mojo        cartilage, meniscus, ligament, muscle and tendon Phong
      soft_tissue.mojo cartilage, meniscus, ligament, muscle and tendon density
      leg/
        assembly.mojo  one connected limb
        contents.mojo  BONES, MUSCLES, BOTH
        femur/     dimensions, geometry, mass
        tibia/     dimensions, geometry, mass
        fibula/    dimensions, geometry, mass
        patella/   dimensions, geometry, mass
        knee/      cartilage, menisci, collaterals
        muscles/   named skeletal muscles
```

Import from the module that defines the symbol. Do not put original content in `geometries/` or `objects/`. Those packages follow three.js.

## Rules

The house rules still apply. Quantities carry units. A kind is a type with `is_valid`. Tests cover every branch. Documentation follows the writing rules. `make check` must pass.

Scale from a named template. A humanoid is a stature, a sex and an athleticism. Each bone reads stature and sex and sizes itself. Each muscle also reads athleticism. Do not hard-code a length in meters when a published relationship exists.

## Add one

1. Open an issue.
2. Put the module under `extensions/<subject>/`.
3. Write tests in `tests/test_<name>.mojo`.
4. Write a wiki page in `docs/wiki/`.
5. Tick the box in the README Extensions list.
6. Run `make check`.
