# Molecular structures

`extensions/molecule/` reads macromolecular structures from mmCIF and PDB files and builds ideal peptide backbones. It draws a structure as a cartoon ribbon or as a surface, and it measures the solvent accessible area of each atom. It is a library for research and teaching. Its measurements are not validated for drug design or for any clinical use.

![The cartoon ribbon of an ideal peptide, and its solvent excluded surface colored by element and by hydropathy](out/molecule.png)

`examples/molecule.mojo` makes this picture. It builds 30 residues of ideal backbone: a helix, a loop and a strand. The top panel is the ribbon, colored by secondary structure. The middle panel is the solvent excluded surface for a water probe, colored by element. The program also prints the solvent accessible area, 2434 square angstroms.

The bottom panel is the same surface colored by hydropathy. The leucines and alanines of the helix make an orange stripe between its blue glutamates and lysines: the helix is amphipathic.

## Modules

| Module | What it gives |
|---|---|
| `ids` | `AtomId`, `ResidueId`, `ChainId`, `ModelId`, `AtomGroup`, `SecondaryKind`, `AltLocPolicy`, `RibbonColoring`, `SurfaceColoring` and `EnsembleFit` |
| `cif` | `parse_cif`, `read_cif`, `cif_tokens`, `CifBlock` and `is_null` |
| `structure` | `Structure`, `parse_mmcif`, `read_mmcif`, `parse_pdb_structure`, `read_pdb_structure` and `SQUARE_ANGSTROM` |
| `peptide` | `build_peptide`, `place_atom` and `three_letter` |
| `dssp` | `assign_secondary`, `hydrogen_bonds`, `HydrogenBond`, `secondary_from_bonds`, `bond_energy` and `KILOCALORIE_PER_MOLE` |
| `hbonds` | `bond_geometry` |
| `ribbon` | `ribbon_geometry` and `chain_color` |
| `surface` | `accessible_areas`, `molecular_surface`, `excluded_surface`, `distance_transform`, `vdw_radius`, `sphere_points` and `AtomCells` |
| `coloring` | `color_surface`, `atom_color` and `kyte_doolittle` |
| `superpose` | `superpose`, `Superposition`, `rmsd` and `matched_atoms` |
| `ensemble` | `ensemble_fluctuation`, `Fluctuation` and `fluctuation_b_factors` |
| `contacts` | `distance_map`, `DistanceMap` and `map_image` |
| `shape` | `molecular_shape` and `MolecularShape` |
| `accessibility` | `residue_accessibility`, `ResidueAccess` and `max_accessible_area` |
| `interface` | `chain_interface` and `ChainInterface` |
| `pdb_write` | `encode_pdb` |
| `cif_write` | `encode_mmcif` and `cif_value` |
| `dihedral` | `backbone_angles`, `BackboneAngles`, `dihedral`, `ramachandran_image`, `ramachandran_color` and `plot_pixel` |

## Read an mmCIF file

```mojo
var structure = read_mmcif("1abc.cif", FIRST_LOCATION)
for chain in structure.chains:
    print(chain.author, chain.residue_count)
```

`parse_mmcif(text, policy)` reads text that is already in memory. The PDB distributes each entry as an mmCIF file. The older PDB format cannot hold more than 99,999 atoms, and `loaders/pdb.mojo` reads only atoms and bonds from it.

## Read a PDB file

`read_pdb_structure(path, policy)` reads a PDB file into the same `Structure`. `parse_pdb_structure(text, policy)` reads text in memory. The reader takes these records from their fixed columns:

| Record | What it gives |
|---|---|
| `HEADER` | The structure's name, the PDB id in columns 63 to 66 |
| `MODEL` | A new model with its number |
| `ATOM`, `HETATM` | An atom, with its residue and chain |
| `TER` | The end of a chain |
| `HELIX`, `SHEET` | The helices and strands |

A PDB file has only the author's chain letters and residue numbers. Each residue's `seq_id` and `auth_seq_id` are the author's number, and the helices and strands name residues by it. A chain starts at a new letter, after `TER`, or in a new model. A chain that repeats a letter in one model gets a label of the letter and a count, such as `A2`. The waters after `TER` are such a chain, so the helices of chain `A` do not mark them.

A short line can leave out the occupancy, the B-factor and the element. The occupancy is then 1 and the B-factor 0. The element then comes from the atom name, as the PDB convention gives it. A name with column 13 blank holds a one-letter element in column 14, so ` CA ` is carbon. A name that starts in column 13 holds a two-letter element there, so `CA  ` is calcium.

## Write a PDB file

`encode_pdb(structure)` writes a structure as the text of a PDB file, for other molecular viewers. Use it for a structure that this extension built or moved, such as an ideal peptide or a superposed model.

```mojo
Path("model.pdb").write_text(encode_pdb(structure))
```

The file holds `ATOM` and `HETATM` records in the fixed columns of the wwPDB format version 3.3, with `TER` after each chain and `END`. Two or more models are written between `MODEL` and `ENDMDL`. The helices and strands of the first model become `HELIX` and `SHEET` records. A name of up to four characters is the PDB id of a `HEADER`, and a longer name is a `TITLE`.

Coordinates have three decimals in angstroms, and the occupancy and the B-factor two. A chain id must be one character. A name or a number that does not fit its columns is refused.

## Write an mmCIF file

`encode_mmcif(structure)` writes a structure as the text of an mmCIF file. Use it when a structure does not fit the PDB format. Examples are more than 99999 atoms, a chain id of two characters, and a long atom name.

```mojo
Path("model.cif").write_text(encode_mmcif(structure))
```

The file is one data block, `data_` and the structure's name, or `data_unnamed` for a structure without one. It holds these categories:

| Category | What it holds |
|---|---|
| `_entry` | The structure's name as `id` |
| `_struct_conf` | A `HELX_P` row for each run of helix residues of the first model |
| `_struct_sheet_range` | A row for each run of strand residues of the first model, each in a sheet of its own |
| `_atom_site` | One row per atom, with every column that `parse_mmcif` reads |

A helix or a strand names its first and last residues by the label ids and the insertion codes. It names them again by the author ids, as wwPDB files do. Coordinates have three decimals in angstroms, and the occupancy and the B-factor two. A residue whose `seq_id` is zero, such as a water, gets the null `label_seq_id` `.`.

`cif_value(text)` gives a value as a CIF token. A value that is empty, holds a blank, or starts like a name, a comment or a reserved word such as `loop_` goes in quotes. It goes in single quotes, or in double quotes when it holds a single quote and a blank. A value that holds a line end is refused.

## The structure

A `Structure` holds four lists: `models`, `chains`, `residues` and `atoms`. A model holds a run of chains, a chain holds a run of residues, and a residue holds a run of atoms. Each run is a first index and a count. An id such as `ResidueId(3)` is an index into its list.

| Type | Fields |
|---|---|
| `Model` | `number`, `first_chain`, `chain_count` |
| `Chain` | `label`, `author`, `model`, `first_residue`, `residue_count` |
| `Residue` | `name`, `seq_id`, `auth_seq_id`, `insertion`, `chain`, `first_atom`, `atom_count`, `secondary` |
| `Atom` | `name`, `element`, `serial`, `group`, `alt`, `position`, `occupancy`, `b_factor`, `residue` |

Positions are in meters, as the rest of the project keeps them. Read them in angstroms with `ANGSTROM` from `extensions/chemistry/quantities.mojo`. A B-factor is an `Area64`. Read it with `SQUARE_ANGSTROM`.

`find_atom(residue, name)` gives the first atom of a residue with a name, or `AtomId(-1)`. `model_atoms(model)` gives the first atom and the atom count of a model. `bounds(model)` gives the corners of a model's atom centers.

## What the reader takes

The reader takes the first data block. It reads the `_atom_site` table. These columns must be present:

| Column | Field |
|---|---|
| `group_PDB` | `group`: `ATOM` or `HETATM` |
| `type_symbol` | `element` |
| `label_atom_id` | `name` |
| `label_comp_id` | The residue `name` |
| `label_asym_id` | The chain `label` |
| `label_seq_id` | The residue `seq_id`. A null gives zero. |
| `Cartn_x`, `Cartn_y`, `Cartn_z` | `position` |

These columns are optional:

| Column | Field | Without it |
|---|---|---|
| `id` | `serial` | The row number |
| `label_alt_id` | `alt` | `.` |
| `auth_asym_id` | The chain `author` | The chain label |
| `auth_seq_id` | The residue `auth_seq_id` | The `label_seq_id` |
| `pdbx_PDB_ins_code` | The residue `insertion` | `?` |
| `occupancy` | `occupancy` | 1 |
| `B_iso_or_equiv` | `b_factor` | 0 |
| `pdbx_PDB_model_num` | The model `number` | 1 |

A new model starts where the model number changes. A new chain starts where `label_asym_id` changes. A new residue starts where `label_seq_id`, `auth_seq_id`, the insertion code or the residue name changes. Two waters with a null `label_seq_id` are two residues when their `auth_seq_id` differs.

## Alternate locations

An atom can have more than one position in a crystal. Each position has an alternate location, such as `A` or `B`, and an occupancy.

| Policy | Atoms kept |
|---|---|
| `ALL_LOCATIONS` | Every atom |
| `FIRST_LOCATION` | The atoms with no alternate location, and in each residue the atoms of the first alternate location in the file |

## Secondary structure

The reader marks helices from `_struct_conf`. A row is a helix when its `conf_type_id` starts with `HELX`. It marks strands from `_struct_sheet_range`. Each row names a chain by `beg_label_asym_id` and a run of residues by `beg_label_seq_id` and `end_label_seq_id`. The marks apply to every model. Other residues are `COIL`.

## Assign secondary structure

`assign_secondary(structure, model)` replaces the secondary structure of a model's residues with the one that its backbone hydrogen bonds make. Use it for a file with no helix and strand records, such as a structure prediction. The method is the core of DSSP, by Kabsch and Sander.

```mojo
var structure = read_pdb_structure("predicted.pdb", FIRST_LOCATION)
assign_secondary(structure, ModelId(0))
```

The energy of a bond from the N-H of one residue to the C=O of another is DSSP's electrostatic model, in kcal/mol. A bond exists below -0.5. The H of a residue is 1 angstrom from its N, along the direction from the O to the C of the residue before. A chain's first residue and a proline have no H.

| Pattern | Gives |
|---|---|
| Two 4-turns in a row, at `i - 1` and `i` | A helix from `i` to `i + 3` |
| Two bridges of one kind in a row | A strand at all four residues |

A 4-turn at `i` is a bond from the C=O of `i` to the N-H of `i + 4`. A bridge pairs two residues three or more apart. It is antiparallel when they bond to each other, or when their outer neighbors do. It is parallel when the bonds run past each residue to the next. A helix wins over a strand. A residue without all of N, CA, C and O is coil.

`secondary_from_bonds(bonds, count)` applies the patterns to a matrix of bonds, so a caller can supply bonds from another source.

## Draw hydrogen bonds

The backbone hydrogen bonds make a helix and pair the strands of a sheet. `hydrogen_bonds(structure, model)` lists them as DSSP finds them, and `bond_geometry` draws them.

```mojo
var bonds = hydrogen_bonds(structure, ModelId(0))
for bond in bonds:
    print(bond.donor.value, bond.acceptor.value, bond.energy.to(KILOCALORIE_PER_MOLE))
var sticks = bond_geometry(structure, bonds, Length64(0.1, ANGSTROM), 8)
```

A `HydrogenBond` holds its donor residue, the N-H, its acceptor residue, the C=O, and its energy as a `MolarEnergy64`. Only a bond below -0.5 kcal/mol is listed. The N-H right after a C=O shares its peptide plane, so DSSP does not pair them. In an alpha helix, the N-H of residue `i + 4` bonds to the C=O of residue `i`.

`bond_geometry(structure, bonds, radius, sides)` draws each bond as a dashed tube from the N of its donor to the O of its acceptor, in light orange. Draw it over a ribbon: the bonds of a helix run along its axis.

## Measure backbone angles

Three torsions set the shape of the backbone at each residue. `backbone_angles(structure, model)` gives them, and `ramachandran_image` plots them.

```mojo
var angles = backbone_angles(structure, ModelId(0))
for entry in angles:
    if entry.has_phi and entry.has_psi:
        print(entry.residue.value, entry.phi.to(DEGREE64), entry.psi.to(DEGREE64))
var plot = ramachandran_image(structure, angles, 360)
```

| Angle | Atoms |
|---|---|
| phi | C of `i - 1`, N, CA, C |
| psi | N, CA, C, N of `i + 1` |
| omega | CA, C, N of `i + 1`, CA of `i + 1` |

A `BackboneAngles` holds a residue and its three angles as `Angle64` values, from -180 to 180 degrees. A flag tells if the residue has each angle. A residue needs its N, CA and C, or it has no entry. A neighbor counts only in the same chain, and only when its C to N distance is 2.5 angstroms or less, as in DSSP. The first residue of a chain has no phi. The last has no psi and no omega.

`dihedral(a, b, c, d)` gives the torsion of any four points, with the IUPAC sign. Seen along the bond from `b` to `c`, the angle is positive when the far bond turns clockwise from the near bond.

`ramachandran_image(structure, angles, size)` plots psi against phi. Phi runs from -180 degrees at the left to 180 at the right. Psi runs from 180 at the top to -180 at the bottom. Each residue with both angles is a dot, red for a helix, gold for a strand and gray for a coil. Gray lines mark zero.

Helices gather near (-60, -45), and strands near (-120, 130). A trans peptide bond has an omega near 180 degrees, and a cis bond has an omega near 0.

## CIF text

The tokens follow CIF 1.1. A `#` starts a comment. A value in single or double quotes ends at a matching quote that a blank follows, so `'O'Brien'` is one value. A line that starts with `;` opens a text field, and the next line that starts with `;` closes it.

`parse_cif(text)` returns a `CifBlock`. A name is not case sensitive. `column(tag)` returns the values of a name, one for each row of its table. A single name and value is a table of one row. `column_or(tag, fallback, rows)` returns a fallback when the name is absent. `is_null(value)` is true for `.` and `?`.

## Build a peptide

`build_peptide(sequence, kinds)` places the backbone of a sequence. Each residue gets N, CA, C and O, and CB when it is not glycine. The bond lengths and angles are the ideal values of Engh and Huber. The secondary structure of each residue sets its torsions:

| Kind | phi (degrees) | psi (degrees) |
|---|---|---|
| `HELIX` | -57 | -47 |
| `STRAND` | -139 | 135 |
| `COIL` | -75 | 145 |

Every peptide bond is trans. `place_atom(a, b, c, bond, angle, torsion)` places each atom from the three before it by the natural extension reference frame. CB comes from the ideal formula that trRosetta uses, which gives an L-amino acid.

These torsions make ideal shapes. They do not fold a chain: the strands of a built peptide do not pair. A real fold comes from an experiment or from a structure prediction.

## Draw a ribbon

`ribbon_geometry(structure, model, coloring, samples, sides)` returns the cartoon of every chain of a model. A ribbon follows a Catmull-Rom spline through the CA atoms. The O atom of each residue gives the direction across the ribbon. A direction that turns more than a right angle from the residue before is flipped, so the ribbon does not twist.

| Kind | Half width (angstroms) | Half thickness (angstroms) |
|---|---|---|
| `HELIX` | 1.2 | 0.25 |
| `STRAND` | 1.0 | 0.25 |
| `COIL` | 0.3 | 0.3 |

The last residue of a strand ends in an arrow. The arrow starts 1.7 angstroms wide and narrows to a point. A chain breaks where two CA atoms in a row are more than 4.2 angstroms apart, or where a residue has no CA.

`BY_STRUCTURE` colors helices red, strands gold and coils gray. `BY_CHAIN` gives each chain one of eight colors. The colors are linear, as the renderer needs them.

## Measure accessible areas

`accessible_areas(structure, model, probe, points)` gives the solvent accessible area of each atom. It uses the method of Shrake and Rupley.

1. Each atom is a sphere of its van der Waals radius plus the probe radius.
2. `points` points spread over each sphere by the golden-section spiral.
3. A point is accessible when no other sphere holds it.
4. The area is the area of the sphere times the fraction of accessible points.

A probe of 1.4 angstroms is a water molecule. The radii are from Bondi:

| Element | Radius (angstroms) |
|---|---|
| H | 1.20 |
| C | 1.70 |
| N | 1.55 |
| O | 1.52 |
| F | 1.47 |
| P, S | 1.80 |
| Cl | 1.75 |
| Se | 1.90 |
| Br | 1.85 |
| I | 1.98 |

Any other element gets 1.8 angstroms.

## Find buried residues

`residue_accessibility(structure, model, areas)` adds the atom areas of each residue. It also gives the relative solvent accessibility (RSA): the area over the largest area that the residue can have.

```mojo
var areas = accessible_areas(structure, ModelId(0), Length64(1.4, ANGSTROM), 500)
for entry in residue_accessibility(structure, ModelId(0), areas):
    if entry.has_relative and entry.buried(0.25):
        print(structure.residues[entry.residue.value].name, entry.relative)
```

The RSA is about 0 for a buried residue and about 1 for a residue in the open. A residue with an RSA below a cutoff, such as 0.2 or 0.25, is often called buried. `entry.buried(cutoff)` tells which side of the cutoff a residue is on.

The largest areas are the theoretical values of Tien and others (2013), for a residue in an extended chain of three. `max_accessible_area(name)` gives the value of one of the twenty standard amino acids. Another residue, such as a water or a ligand, has its area but no RSA, and `has_relative` is false.

## Measure a chain interface

Two chains that bind cover part of each other's surface. `chain_interface(structure, model, first, second, probe, points)` gives the area that they bury, and the residues that bury it.

```mojo
var face = chain_interface(structure, ModelId(0), ChainId(0), ChainId(1), Length64(1.4, ANGSTROM), 500)
print(face.total().to(SQUARE_ANGSTROM), "square angstroms buried")
for row in range(len(face.residues)):
    print(face.residues[row].value, face.buried(row).to(SQUARE_ANGSTROM))
```

The buried surface area is `ASA(A alone) + ASA(B alone) - ASA(A with B)`, over the atoms of the two chains. Other chains of the model do not count. Each accessible area uses the same points on each sphere alone and with the other chain. So no atom gains area, and each buried area is zero or more.

A `ChainInterface` holds each atom of both chains with its buried area, and each residue that buries area with its sum. `face.total()` gives the buried area of the interface. Some studies report half of it, the area that each side loses on average.

## Draw a surface

`molecular_surface(structure, model, probe, spacing)` returns the solvent accessible surface as a mesh. It samples the distance to the nearest grown sphere on a grid of the given spacing. It meshes the zero set of that distance by marching tetrahedra. Each vertex takes the CPK color of the atom whose sphere it lies on.

A probe of zero gives the van der Waals surface.

## Draw the excluded surface

`excluded_surface(structure, model, probe, spacing)` returns the solvent excluded surface: the surface where a rolling probe touches the atoms. Molecular viewers show this surface by default. It follows each atom's van der Waals sphere where the probe touches one atom. It fills each crevice that the probe is too large to enter with a smooth, concave patch.

The probe's center can reach the points outside every grown sphere. The surface is the set of points one probe radius from that region. The distance to that region comes from three bounds:

1. The depth into the deepest grown sphere is a lower bound.
2. Where the point straight out from that sphere's center is outside every other sphere, the depth is exact. This covers the convex patches.
3. In a crevice between two spheres, the distance to the circle where they meet is exact when no third sphere holds the circle's nearest point.

Elsewhere, an exact Euclidean distance transform of the grid gives the distance to the nearest reachable grid point. That distance, less the point's own distance to the spheres, is an upper bound within one step of the true distance. This is the method of EDTSurf, with exact corrections.

`distance_transform(seeds, px, py, pz)` is the transform of Felzenszwalb and Huttenlocher, run along x, then y, then z. It gives the squared distance to the nearest seed in grid steps, and the index of that seed.

## Superpose two models

Superpose two models before you compare them, such as two models of an NMR ensemble, or a crystal structure and a prediction.

```mojo
var pairs = matched_atoms(crystal, ModelId(0), predicted, ModelId(0), "CA")
var fixed = List[V3]()
var moving = List[V3]()
for pair in pairs:
    fixed.append(crystal.atoms[pair[0]].position)
    moving.append(predicted.atoms[pair[1]].position)
var fit = superpose(fixed, moving)
print(fit.rmsd.to(METER) / Length64(1.0, ANGSTROM).to(METER), "angstroms")
```

`superpose(fixed, moving)` gives the rotation and the translation that put the moving points on the fixed points with the least root mean square deviation (RMSD). This is the problem of Kabsch. The method is Horn's: the best rotation is the unit quaternion of the largest eigenvalue of a 4 by 4 matrix. A quaternion is always a proper rotation, so the fit never mirrors a set. The sets need three or more points.

`fit.apply(p)` moves a point, and `fit.rmsd` is the deviation after the move. `rmsd(fixed, moving)` gives the deviation without a move.

`matched_atoms(fixed, model, moving, model, name)` pairs the atoms of one name, such as `CA`. Two atoms pair when their chains have one label, and their residues one number and insertion code. Of alternate locations, the first in the file pairs.

## Measure the spread of an ensemble

An NMR structure is an ensemble of models, and a simulation gives a series of snapshots. The root mean square fluctuation (RMSF) of an atom shows how far it moves over the models. `ensemble_fluctuation` gives it.

```mojo
var spread = ensemble_fluctuation(structure, "CA", ModelId(0), FIT_TO_REFERENCE)
for row in range(spread.count()):
    print(spread.atoms[row].value, spread.fluctuation(row).to(ANGSTROM))
fluctuation_b_factors(structure, spread)
color_surface(surface, structure, ModelId(0), COLOR_BY_B_FACTOR)
```

The RMSF of an atom is `sqrt(mean(|x_k - mean(x)|^2))` over the models `k`. The result has one row for each atom of the reference model with the name that every model has. Atoms pair as `matched_atoms` pairs them.

`FIT_TO_REFERENCE` first superposes each model on the reference model by the compared atoms, so a rigid move does not count. This needs three shared atoms. `AS_GIVEN` uses the coordinates of the file, such as snapshots that were fitted before. `spread.deviation(model)` gives the RMSD of a model from the reference after the fit.

`fluctuation_b_factors(structure, spread)` writes each RMSF into the reference model as an isotropic B-factor, `B = 8 pi^2 RMSF^2 / 3`. Each atom of the residue gets it. The B-factor coloring of a surface then shows the mobile parts in red.

## Measure size and shape

`molecular_shape(structure, model)` gives the size and shape of a model:

| Field | What it holds |
|---|---|
| `mass` | The sum of the standard atomic weights, a `MolarMass64` |
| `center` | The mass center, in meters |
| `radius_of_gyration` | The root mean square distance of the mass from its center, as small-angle scattering measures it |
| `axes` | The three principal axes, unit and square, the longest first |
| `extents` | The root mean square distance of the mass along each axis |

Each atom weighs its element's standard atomic weight. The axes are the eigenvectors of the gyration tensor, the weighted mean of `(r - c)(r - c)^T`. A globular protein has three similar extents. A helix or a fiber has one large extent and two small ones. An element without a standard weight, such as an unknown `X`, is refused.

## Map distances and contacts

A distance map shows a fold at a glance. A helix is a band along the diagonal, two strands that pair make a line across it, and two domains make blocks. A contact map does not change when a model turns, so structure prediction compares contact maps.

```mojo
var map = distance_map(structure, ModelId(0), "CA")
var contacts = map.contacts(Length64(8, ANGSTROM), 6)
Path("map.png").write_bytes(encode(map_image(map, Length64(20, ANGSTROM))))
```

`distance_map(structure, model, name)` takes one atom of each residue, such as `CA` or `CB`. A residue without the atom has no row. `map.distance(row, column)` gives the distance of one pair, and `map.residues` gives the residue of each row.

`map.contacts(cutoff, separation)` gives the pairs of rows closer than the cutoff, each pair once. Two residues of one chain must be at least `separation` residues apart. Residues of two chains always count. `map_image(map, far)` draws one pixel per pair: dark blue at zero distance, and white at `far` and beyond.

## Color a surface

A surface comes with CPK colors. `color_surface(geometry, structure, model, coloring)` colors it again by another property of the atom under each vertex:

| `SurfaceColoring` | What the color shows |
|---|---|
| `COLOR_BY_ELEMENT` | The CPK color of the element |
| `COLOR_BY_B_FACTOR` | Blue at the least B-factor of the model, white halfway and red at the largest |
| `COLOR_BY_CHAIN` | The chain, in the palette of the ribbons |
| `COLOR_BY_HYDROPATHY` | Blue at -4.5 on the Kyte-Doolittle scale, white at 0 and orange at +4.5 |

```mojo
var surface = excluded_surface(structure, model, probe, spacing)
color_surface(surface, structure, model, COLOR_BY_HYDROPATHY)
```

Each vertex takes the color of the atom whose van der Waals sphere is nearest it. A grid of cells, `AtomCells`, finds that atom. A residue that is not one of the twenty amino acids, such as water or a ligand, is gray in the hydropathy coloring. `kyte_doolittle(name)` gives the value of one residue, and `atom_color` gives the sRGB color of one atom. `chain_color(index)` gives the palette color of a chain.

The B-factor coloring shows the flexible parts of a crystal structure. A high B-factor can also show disorder or a poor model. The hydropathy coloring shows oily and charged patches. It does not compute an electrostatic potential.

## Verification

The tests check these results:

- A built helix has CA atoms 3.80 angstroms apart.
- The hydrogen bond from O of residue `i` to N of residue `i + 4` is 2.8 to 3.3 angstroms.
- A built alpha helix of 14 residues gives DSSP's pattern: coil at each end and helix between.
- Crafted bond matrices give antiparallel and parallel ladders by each rule, and a lone bridge gives none.
- A PDB fixture gives the expected chains, residues, elements and secondary structure. It holds two models, waters and an ion after `TER`, an insertion code and alternate locations.
- CB is 1.527 angstroms from CA.
- One atom with a probe has the whole area of its grown sphere.
- Two carbons 3 angstroms apart each lose a cap of `2 pi R h`. The measured area matches to within one percent with 2000 points.
- Every vertex of a van der Waals surface lies within 0.06 angstroms of an atom sphere, at a spacing of 0.3 angstroms.
- One atom's excluded surface is its van der Waals sphere, to within the chords of a 0.4 angstrom grid.
- Two carbons 3 angstroms apart have an excluded surface with a neck of 1.313 angstroms, the analytic radius, to within 0.03 angstroms.
- The distance transform is exact on a grid with one seed.
- A ribbon of `n` residues has `(n - 1) samples + 1` rings, and every normal is a unit vector.
- An ideal peptide and a file of two models with alternate locations and hetero atoms read back the same after `encode_mmcif`. So does a structure with a chain id of two characters, an atom name of six and a residue number of 123456. gemmi 0.7.5 read the written files with their models, atoms, helices, strands and insertion codes. Biopython 1.88 read the same atoms. That check is not part of the test suite.
- An ideal peptide reads back the same after `encode_pdb`, to the 0.001 angstrom of three decimals. So does a file of two models with alternate locations and hetero atoms.
- Torsions of four points have the IUPAC sign: 0 for cis, 180 for trans, and +90 when the far bond turns clockwise. An ideal peptide gives the phi and psi of each of its kinds, and an omega of 180 degrees, to 1e-6 degrees. A residue without an N, a CA or a C has no entry. A chain break of 10 angstroms ends the angles at each side. A peptide of 20 residues got up to 0.3 angstroms of noise per coordinate and was written as a PDB file. Its angles match Biopython 1.88 to within 1e-4 degrees. That check is not part of the test suite.
- An ideal helix of 14 residues has 10 hydrogen bonds, each from residue `i + 4` to residue `i`. A strand has none.
- A carbon and an oxygen 5 angstroms apart have their mass center at the share `m_O / (m_C + m_O)`. Their radius of gyration is `L sqrt(m1 m2) / (m1 + m2)`, along the bond.
- Neighbor CA atoms of an ideal peptide are 3.8 angstroms apart. An alpha helix has its CA contacts within 8 angstroms at `i + 3` and `i + 4` only, and a strand has none.
- A superposition recovers a known rotation and shift to 1e-12, with a proper rotation. It does not reach a mirror image. A small turn away from the fit gives a larger RMSD. On 40 noisy points, its RMSD matches numpy's SVD solution to 16 digits. That check is not part of the test suite.
- Over three models as given, one CA moved by `+d` and `-d` has an RMSF of `d sqrt(2/3)`, and every other CA has none. Its residue gets the B-factor `16 pi^2 d^2 / 9`. Models that differ by rigid moves fit to an RMSF below 1e-9 angstroms. Five models with up to 0.5 angstroms of noise per coordinate match a numpy fit by SVD to 2e-15 angstroms. That check is not part of the test suite.
- The largest areas are the 20 values of Tien and others. A residue's area is the sum of its atoms, and its RSA is that sum over the largest area. The middle of a built helix is more buried than its ends. On a peptide of 12 residues with 2000 points per sphere, the areas match Biopython 1.88's Shrake-Rupley to 0.1 percent. That check is not part of the test suite.
- Two carbons in two chains 3 angstroms apart each bury a cap of `2 pi R h`, within 1 percent with 2000 points. Chains 20 angstroms apart bury nothing, and a third chain does not change the interface of the other two. On two helices 9 angstroms apart, the buried area of each residue matches Biopython 1.88's Shrake-Rupley to 0.001 square angstroms. That check is not part of the test suite.
- A vertex takes the color of the nearest atom sphere, also far from every atom. On the excluded surface of an isoleucine and an arginine, each colors its own part orange or blue.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| A quoted value or a text field has no end | `cif_tokens`, `parse_cif`, `parse_mmcif` |
| Two chains of an interface are one chain, are not in the model, or have no atoms | `chain_interface`, `ChainInterface` |
| The areas do not fit the atoms of the model, a residue is not a standard amino acid, or a cutoff is not positive | `residue_accessibility`, `max_accessible_area`, `ResidueAccess` |
| An ensemble has fewer than two models, too few shared atoms, or a bad fit or reference | `ensemble_fluctuation`, `Fluctuation` |
| A structure has no model or no atom, its name holds a blank, or a value holds a line end or both kinds of closing quote | `encode_mmcif`, `cif_value` |
| No data block, a stray value, or a loop that does not fill its rows | `parse_cif`, `parse_mmcif` |
| A needed column is missing, or a value is not a number | `parse_mmcif` |
| An id names no entry | `require_atom`, `find_atom`, `bounds`, `ribbon_geometry` |
| A code is not a standard amino acid | `build_peptide`, `three_letter` |
| A count, a probe or a spacing is out of range | `ribbon_geometry`, `accessible_areas`, `molecular_surface` |
| A surface coloring is not valid, or an atom is not in the model | `color_surface`, `atom_color` |
| A bond radius or side count is out of range, or a bond's residue has no N or O | `bond_geometry` |
| Two sets differ in size, hold fewer than three points, or are not finite | `superpose`, `rmsd` |
| No residue has the atom, a row is outside the map, or a cutoff or separation is out of range | `distance_map`, `DistanceMap`, `map_image` |
| Three points of a torsion are in a line, or a plot size is not from 64 to 2048 pixels | `dihedral`, `backbone_angles`, `ramachandran_image` |

## Limits

- The PDB reader does not read `CONECT`, `ANISOU` or `SEQRES` records, or the hybrid-36 numbers of very large files.
- The reader keeps the first data block only. It does not read anisotropic displacements, bonds or the chemical component dictionary.
- The readers do not infer secondary structure themselves. Call `assign_secondary` for a file without helix and strand records.
- `assign_secondary` does not report 3-10 or pi helices, turns, bends, isolated bridges or beta bulges.
- Ribbons need CA atoms. Nucleic acids have no ribbon.
- An ensemble is fitted on one reference model. The fit is not iterated to the mean of the models.
- A Ramachandran plot shows the angles only. It does not draw the favored and allowed regions of a reference set, and it does not validate a model.
- Where three or more spheres make a crevice, the excluded surface uses the grid bound. It can lie up to one grid step outside the true surface there.
- A surface grid holds at most 2^24 points. A large structure needs a larger spacing.

## References

- Westbrook and others, "PDBx/mmCIF Ecosystem: Foundational Semantic Tools for Structural Biology", 2022.
- Hall, Allen and Brown, "The Crystallographic Information File (CIF)", 1991.
- wwPDB, "Atomic Coordinate Entry Format Description", version 3.3, 2012.
- Tien, Meyer, Sydykova, Spielman and Wilke, "Maximum allowed solvent accessibilities of residues in proteins", 2013.
- Engh and Huber, "Accurate bond and angle parameters for X-ray protein structure refinement", 1991.
- Parsons and others, "Practical conversion from torsion space to Cartesian space for in silico protein synthesis", 2005.
- Yang and others, "Improved protein structure prediction using predicted interresidue orientations", 2020.
- Shrake and Rupley, "Environment and exposure to solvent of protein atoms", 1973.
- Bondi, "van der Waals volumes and radii", 1964.
- Connolly, "Solvent-accessible surfaces of proteins and nucleic acids", 1983.
- Xu and Zhang, "Generating triangulated macromolecular surfaces by Euclidean distance transform", 2009.
- Felzenszwalb and Huttenlocher, "Distance transforms of sampled functions", 2012.
- Richardson, "The anatomy and taxonomy of protein structure", 1981.
- Kabsch and Sander, "Dictionary of protein secondary structure: pattern recognition of hydrogen-bonded and geometrical features", 1983.
- Kyte and Doolittle, "A simple method for displaying the hydropathic character of a protein", 1982.
- Kabsch, "A solution for the best rotation to relate two sets of vectors", 1976.
- Horn, "Closed-form solution of absolute orientation using unit quaternions", 1987.
