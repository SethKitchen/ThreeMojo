# How to add a feature

This guide takes a three.js feature from an open issue to a ticked box in the README. Every step has a check that `make check` enforces.

## 1. Take the issue

Every feature in the [README checklist](https://github.com/SethKitchen/ThreeMojo#features) has an issue. Comment on the open issue you take. Open a new issue for a feature that is not listed.

## 2. Write the module

Put the module in the package that matches three.js: `geometries/`, `helpers/`, `lights/`, `materials/`, `cameras/`, `core/`, `math/` or `render/`. Keep three.js names where Mojo allows them.

Follow the house rules:

- Give every quantity a unit type. A length is a `Length`, an angle is an `Angle`.
- Make every id, mode and kind a type with an `is_valid` method. Refuse a wrong value at the boundary that reads it.
- Write a docstring with `Args`, `Returns` and `Raises` on every public symbol.
- Keep the CPU and GPU rasterizers in step. Shared arithmetic lives in a module that both can import, such as `render/fillrule.mojo`.

## 3. Write the tests

Create or extend `tests/test_<module>.mojo`. Cover every line, every branch and every condition. Add:

- A test that constructs a wrong value inside the right type, and asserts the refusal.
- A file in `tests/compile_fail/` for each new type that replaces a bare integer.
- A parity test in `tests/test_gpu.mojo` when the change touches shading or sampling.

## 4. Run the checks

```bash
make check
make coverage
```

Both must pass. `make coverage` lists what a test has not reached.

## 5. Write the documentation

1. Add or update the reference page in `docs/wiki/`. Describe what the feature is and how to call it.
2. Add an explanation page when the design has a reason that is not obvious.
3. Run `make docs-check`.

Follow [How to write documentation](How-to-write-documentation).

## 6. Update the README

Tick the box in the feature checklist. Link it to the wiki page. Keep the issue number.

## 7. Commit

Write the commit message as a statement. Reference the issue with `Closes #N`. Run `make check` one more time before you push.
