# Molecular structures

`extensions/molecule/` reads macromolecular structures from mmCIF and PDB files and builds ideal peptide backbones. It draws a structure as a cartoon ribbon or as a surface, and it measures the solvent accessible area of each atom. It is a library for research and teaching. Its measurements are not validated for drug design or for any clinical use.

![The cartoon ribbon of an ideal peptide, and its solvent excluded surface colored by element](out/molecule.png)

`examples/molecule.mojo` makes this picture. It builds 30 residues of ideal backbone: a helix, a loop and a strand. The top panel is the ribbon, colored by secondary structure. The bottom panel is the solvent excluded surface for a water probe, colored by element. The program also prints the solvent accessible area, 2434 square angstroms.

## Modules

| Module | What it gives |
|---|---|
| `ids` | `AtomId`, `ResidueId`, `ChainId`, `ModelId`, `AtomGroup`, `SecondaryKind`, `AltLocPolicy` and `RibbonColoring` |
| `cif` | `parse_cif`, `read_cif`, `cif_tokens`, `CifBlock` and `is_null` |
| `structure` | `Structure`, `parse_mmcif`, `read_mmcif`, `parse_pdb_structure`, `read_pdb_structure` and `SQUARE_ANGSTROM` |
| `peptide` | `build_peptide`, `place_atom` and `three_letter` |
| `dssp` | `assign_secondary`, `secondary_from_bonds` and `bond_energy` |
| `ribbon` | `ribbon_geometry` |
| `surface` | `accessible_areas`, `molecular_surface`, `excluded_surface`, `distance_transform`, `vdw_radius` and `sphere_points` |

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

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| A quoted value or a text field has no end | `cif_tokens`, `parse_cif`, `parse_mmcif` |
| No data block, a stray value, or a loop that does not fill its rows | `parse_cif`, `parse_mmcif` |
| A needed column is missing, or a value is not a number | `parse_mmcif` |
| An id names no entry | `require_atom`, `find_atom`, `bounds`, `ribbon_geometry` |
| A code is not a standard amino acid | `build_peptide`, `three_letter` |
| A count, a probe or a spacing is out of range | `ribbon_geometry`, `accessible_areas`, `molecular_surface` |

## Limits

- The PDB reader does not read `CONECT`, `ANISOU` or `SEQRES` records, or the hybrid-36 numbers of very large files.
- The reader keeps the first data block only. It does not read anisotropic displacements, bonds or the chemical component dictionary.
- The readers do not infer secondary structure themselves. Call `assign_secondary` for a file without helix and strand records.
- `assign_secondary` does not report 3-10 or pi helices, turns, bends, isolated bridges or beta bulges.
- Ribbons need CA atoms. Nucleic acids have no ribbon.
- Where three or more spheres make a crevice, the excluded surface uses the grid bound. It can lie up to one grid step outside the true surface there.
- A surface grid holds at most 2^24 points. A large structure needs a larger spacing.

## References

- Westbrook and others, "PDBx/mmCIF Ecosystem: Foundational Semantic Tools for Structural Biology", 2022.
- Hall, Allen and Brown, "The Crystallographic Information File (CIF)", 1991.
- wwPDB, "Atomic Coordinate Entry Format Description", version 3.3, 2012.
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
