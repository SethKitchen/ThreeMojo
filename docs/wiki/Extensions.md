# Extensions

`extensions/` holds content that is not a three.js port. Core stays a port of three.js. Water, plants, buildings and a humanoid live here, in a folder per subject.

The first subject is the humanoid. The first bone is the femur. See [Femur](Femur).

## Layout

```text
extensions/
  humanoid/
    spec.mojo          HumanoidSpec: stature and sex
    sex.mojo           MALE, FEMALE
    side.mojo          RIGHT, LEFT
    skeleton/
      leg/
        femur/
          dimensions.mojo   osteometry and the implicit solid
          geometry.mojo     the mesh
```

Import from the module that defines the symbol. Do not put original content in `geometries/` or `objects/`. Those packages follow three.js.

## Rules

The house rules still apply. Quantities carry units. A kind is a type with `is_valid`. Tests cover every branch. Documentation follows the writing rules. `make check` must pass.

Scale from measured data. A humanoid is a stature and a sex. Each bone reads those and sizes itself. Do not hard-code a length in meters when a formula exists.

## Add one

1. Open an issue.
2. Put the module under `extensions/<subject>/`.
3. Write tests in `tests/test_<name>.mojo`.
4. Write a wiki page in `docs/wiki/`.
5. Tick the box in the README Extensions list.
6. Run `make check`.
