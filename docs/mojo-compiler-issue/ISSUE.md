# [BUG] Codegen hangs on a Bool loop flag read after nested `for` loops; identical Int counter builds in 1s

## Bug description

A `Bool` local that is set to the constant `True` inside a `for` loop body
and read after the loop causes `mojo build` to run for minutes without
finishing when the loops are nested. The same program with the flag changed
to an `Int` counter (`+= 1` in the body, `> 0` at the read) builds in about
one second.

Type-checking is not affected — `mojo doc` on the hanging file completes in
under a second — so this appears to be in codegen rather than parsing or
elaboration.

Bisecting a larger instrumented file showed that *removing only the
after-loop read* of the flag is enough to make it build; the assignment inside
the loop alone is fine. Copying the flag to a fresh local immediately before
the read does not help. Marking the callee `@no_inline` does not help.

## Steps to reproduce

`repro_bool.mojo`:

```mojo
@no_inline
def observe(id: StaticString, value: Bool) -> Bool:
    print(id, value)
    return value


def build(rings: Int, columns: Int) -> Int:
    var data = List[Float32]()
    var outer_a = False
    for ring in range(rings + 1):
        outer_a = True
        var inner_a = False
        for column in range(columns + 1):
            inner_a = True
            var x = Float32(ring) * Float32(column)
            data.append(x)
            data.append(x * 2)
            data.append(x * 3)
        _ = observe("inner_a", inner_a)
    _ = observe("outer_a", outer_a)

    var index = List[Int]()
    var outer_b = False
    for ring in range(rings):
        outer_b = True
        var inner_b = False
        for column in range(columns):
            inner_b = True
            var top = ring * (columns + 1) + column
            if ring != 0:
                index.append(top)
                index.append(top + 1)
            if ring != rings - 1:
                index.append(top + columns + 1)
        _ = observe("inner_b", inner_b)
    _ = observe("outer_b", outer_b)
    return len(data) + len(index)


def main():
    print(build(8, 12))
```

```
$ mojo build -o /tmp/b repro_bool.mojo
# does not finish; killed after 25s (and after several minutes in the
# original program)
```

`repro_int.mojo` is the same file with each flag changed as follows:

```
var outer_a = False   ->   var outer_a = 0
outer_a = True        ->   outer_a += 1
observe("x", flag)    ->   observe("x", flag > 0)
```

```
$ mojo build -o /tmp/i repro_int.mojo
# ~1s, and the binary runs correctly
```

## Expected behavior

Both variants compile in comparable time. A `Bool` that is only ever assigned
a constant inside a loop is not an unusual shape — it is the natural way to
write "did this loop run at all?".

## Actual behavior

The `Bool` variant's build does not complete within any time I waited for
(minutes). The `Int` variant builds in about a second.

## Environment

- Mojo 1.0.0 (`ed45d567`), installed with `uv pip install mojo` into a venv
- macOS 25.6 (Darwin 25.6.0), Apple M4 Max
- `mojo doc` on `repro_bool.mojo`: completes in < 1s
- `mojo build` on `repro_bool.mojo`: does not complete

## Context

Found while building a coverage tool that rewrites Mojo sources with probes.
Its "did this `for` loop run zero times?" probe emitted exactly this flag
pattern, and every instrumented module with nested loops stopped building.
Switching the emitted flag to an `Int` counter fixed all of them.
