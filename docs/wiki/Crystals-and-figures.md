# Crystals and figures

`extensions/chemistry/crystal.mojo` reads crystal structures from CIF text and places their atoms. `plot.mojo` draws charts of process chemistry on a frame. The gallery's chemistry figures use both.

This page is a reference. For the rest of the library, see [Process chemistry](Process-chemistry).

![Diamond and graphite turn side by side: a network of four bonds per atom, and flat sheets of hexagons](out/crystal.png)

## Read a CIF file

CIF is the Crystallographic Information File of the IUCr. A CIF file gives a unit cell, the symmetry operations of its space group, and the atoms of the asymmetric unit. `read_cif(text)` reads the first data block. It applies each operation to each atom site, and keeps each different position in the cell once.

```mojo
from std.pathlib import Path
from extensions.chemistry.crystal import bonds, read_cif
from extensions.chemistry.quantities import ANGSTROM
from units.si import GRAM_PER_CUBIC_CENTIMETER, Length64

var diamond = read_cif(Path("diamond.cif").read_text())
diamond.density().to(GRAM_PER_CUBIC_CENTIMETER)   # 3.516
var atoms = diamond.block(1, 1, 1)                 # 18 atoms
var links = bonds(atoms, Length64(1.3, ANGSTROM), Length64(1.6, ANGSTROM))
```

The reader takes these items:

| Item | Use |
|---|---|
| `_cell_length_a`, `_b`, `_c` | The edges, in angstroms |
| `_cell_angle_alpha`, `_beta`, `_gamma` | The angles, in degrees |
| `_space_group_symop_operation_xyz` or `_symmetry_equiv_pos_as_xyz` | The operations, such as `-y,x-y,z+1/2`. Without them, the identity is the only operation |
| `_atom_site_fract_x`, `_y`, `_z` | The positions, as fractions of the edges |
| `_atom_site_type_symbol` or `_atom_site_label` | The element, from the leading letters, so `Ti1` is titanium and `O2-` is oxygen |

A number can carry its uncertainty in parentheses, as in `3.5668(2)`. The reader ignores the uncertainty and the occupancy. It reads comments, quoted values and text fields, and it refuses an unknown element or a broken loop with the line number.

## Place the atoms

A `Crystal` gives:

- `volume()`, from the edges and the angles of any cell, triclinic included.
- `density()`, the mass of the cell's atoms over its volume.
- `place(u, v, w)`, the Cartesian point of a fractional position. Edge a lies along x, and edge b lies in the x-y plane.
- `block(na, nb, nc)`, the atoms of a block of cells. Atoms on the far faces are included, so a block of one cell shows all eight corners.

`bonds(positions, shortest, longest)` gives each pair of positions in a range of distance, the lower index first.

| Crystal | Atoms per cell | Bond | Density |
|---|---|---|---|
| Diamond, a = 3.5668 angstroms | 8 | a sqrt(3) / 4 = 1.5445 angstroms | 3.516 g/cm³, handbook 3.515 |
| Graphite, P6_3/mmc, 24 operations | 4 | a / sqrt(3) = 1.4226 angstroms | 2.261 g/cm³, handbook 2.26 |
| Rock salt, a = 5.64 angstroms | 8 | a / 2 = 2.82 angstroms | |

`examples/crystal.mojo` draws diamond and graphite as spheres and rods. Diamond's bonds go out in four directions, so it is hard. Graphite's bonds lie in flat sheets 3.36 angstroms apart, so the sheets slide.

## Charts

An `Axes` maps a box of data onto a box of pixels, with y up. Its methods draw in data units:

| Method | Draws |
|---|---|
| `frame(frame, font, x_title, y_title, size, color)` | The box, the ticks, their numbers and the titles |
| `line(frame, xs, ys, width, color)` | A line through points |
| `band(frame, x_low, x_high, y_low, y_high, color)` | A filled box |
| `cells(frame, map, colors)` | Each node of a `LabelMap` in the color of its label |

`nice_ticks` picks round ticks: steps of 1, 2 or 5 times a power of ten. `tick_text` writes a tick with the decimals its step needs. The cells of a map fall on whole pixels, so the boxes that touch do not blend twice. The axes do not clip, so keep the data inside the box.

## The gallery figures

| Image | Example | Page |
|---|---|---|
| `out/ellingham.png` | `examples/ellingham.mojo` | [Process maps](Process-maps) |
| `out/predominance.png` | `examples/predominance.mojo` | [Process maps](Process-maps#predominance-maps) |
| `out/process-windows.png` | `examples/process_windows.mojo` | [Why a process runs where it does](Why-a-process-runs-where-it-does) |
| `out/anodizing.png` | `examples/anodizing.mojo` | [Electrolysis and film color](Electrolysis-and-film-color#film-color) |
| `out/kroll-loop.png` | `examples/kroll_loop.mojo` | [Flowsheets and routes](Flowsheets-and-routes) |
| `out/crystal.png` | `examples/crystal.mojo` | This page |

`make out/NAME.png` renders one image and compresses it. The figures share one dark surface and one order of series colors, in `tools/_chemistry_figure.mojo`. Every series also carries a label, so no reader needs the color alone.
