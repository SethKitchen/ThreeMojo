# Why the engineering solvers are original code

ThreeMojo has solvers that follow well known engineering programs. The EPANET and MODFLOW solvers are translations of their source, because their licenses allow it. Each other solver is new code that implements a published method. This page says which program each solver follows, how far it goes, and why the code is original or a translation.

## What follows what

| Program | What it does | ThreeMojo module | Page |
|---|---|---|---|
| OpenSees | Newmark time history with Rayleigh damping and ground motion | `extensions/structure/dynamic.mojo` | [Frame analysis](Frame-analysis#follow-a-model-in-time) |
| OpenSees | Geometric stiffness and P-Delta | `extensions/structure/buckling.mojo` | [Frame analysis](Frame-analysis#solve-with-second-order-effects) |
| OpenSees | Uniaxial steel, truss elements, Newton iteration, load control and displacement control | `extensions/structure/nonlinear.mojo` | [Frame analysis](Frame-analysis#follow-a-truss-past-yield) |
| OpenSees | Corotational truss | `extensions/structure/nonlinear.mojo` | [Frame analysis](Frame-analysis#large-displacements) |
| OpenSees | Nonlinear time history | `extensions/structure/transient.mojo` | [Frame analysis](Frame-analysis#a-truss-in-time) |
| OpenSees | Fiber sections with Concrete01 and Steel01 | `extensions/structure/section.mojo` | [Frame analysis](Frame-analysis#find-the-moment-curvature-curve-of-a-section) |
| OpenSees | Response spectrum analysis | `extensions/structure/spectrum.mojo` | [Frame analysis](Frame-analysis#combine-modes-with-a-response-spectrum) |
| CalculiX | Input decks of `C3D4` and `C3D10` elements | `extensions/fem/deck.mojo` | [Tetrahedral FEM](Tetrahedral-FEM#read-and-write-calculix-decks) |
| CalculiX | The `*BUCKLE` procedure, for frames | `extensions/structure/buckling.mojo` | [Frame analysis](Frame-analysis#find-buckling-loads) |
| OpenFOAM | icoFoam: laminar incompressible flow by PISO | `extensions/cfd/flow.mojo` | [Finite-volume flow](Finite-volume-flow) |
| OpenFOAM | buoyantBoussinesqPimpleFoam: heat and buoyancy | `extensions/cfd/heat.mojo` | [Finite-volume flow](Finite-volume-flow#carry-heat) |
| EPANET | The engine of EPANET 2.3.6: input files, hydraulics over time and water quality. This is a translation. | `extensions/epanet/` | [Pipe networks](Pipe-networks) |
| HEC-RAS | Steady profiles by the standard step method | `extensions/hydraulics/channel.mojo` | [Open channels](Open-channels) |
| MODFLOW | The groundwater flow model and the IMS solver of MODFLOW 6: input files, steady and transient flow, and the Newton formulation. This is a translation. | `extensions/groundwater/` | [Groundwater flow](Groundwater-flow) |

The project already had the base of these solvers. [Tetrahedral FEM](Tetrahedral-FEM) has static, modal and thermal analysis of solids. [Frame analysis](Frame-analysis) and [Shell analysis](Shell-analysis) have linear frames and shells. [Numerics](Numerics) has the sparse matrices and the factorizations.

## The licenses

A translation of source code is a derived work. It keeps the license of its source.

| Program | License | What it means here |
|---|---|---|
| OpenFOAM | GNU GPL, version 3 | A translation must have the GPL. |
| CalculiX | GNU GPL, version 2 or later | A translation must have the GPL. |
| OpenSees | A license of the Regents of the University of California | Read its terms before any use of its source. |
| EPANET | Public domain for version 2.0, and the MIT license from version 2.2 | A translation is allowed. `extensions/epanet/` translates version 2.3.6 and keeps its notice. |
| HEC-RAS | Free software of the US Army Corps of Engineers | Its source is not published. Its manuals give its methods. |
| MODFLOW | Public domain, from the US Geological Survey, and CC0 1.0 worldwide | A translation is allowed. `extensions/groundwater/` translates MODFLOW 6 and keeps its notice. Libraries that it bundles under the LGPL are not translated. |

ThreeMojo has the PolyForm Noncommercial license, with a commercial license beside it. Code under the GPL cannot have those terms. So a translation of OpenFOAM or of CalculiX cannot be part of this project.

A method is not source code. An algorithm in a paper or a textbook is free to implement. Each solver here, except EPANET and MODFLOW, implements a method from its first publication or from a textbook. Each module names that reference in its docstring. The names of some options follow the program, because users know them: `average_acceleration`, `*CLOAD`, PISO.

EPANET and MODFLOW are the exceptions. The MIT license of EPANET allows a translation into a project with other terms, if the translation keeps the notice. MODFLOW 6 is in the public domain. A translation gives the same numbers as the program, and a test can check each of them.

So `extensions/epanet/` translates the C source of EPANET 2.3.6, and `extensions/groundwater/` translates the Fortran source of MODFLOW 6. THIRD-PARTY-NOTICES.md has their notices. The other solvers stay original code.

## What "follows" means

A page that says that a solver follows a program makes three claims:

- The solver solves the same equations with the same method, within the limits that the page lists.
- The tests compare the solver with closed forms and with published benchmarks. Examples are the tables of Chopra, the cavity of Ghia, Ghia and Shin, the cavity of de Vahl Davis and the worked channel of Chow.
- The code shares no source with the program. This claim does not apply to EPANET and MODFLOW, which are translations.

The page does not claim these things:

- It does not claim the same numbers as the program. No test runs OpenSees, CalculiX, OpenFOAM or HEC-RAS. Where a formula differs, the page says so. The [Open channels](Open-channels#differences-from-hec-ras) page has a section on the differences. EPANET and MODFLOW are the exceptions. Their tests compare each translation with the real program. [Pipe networks](Pipe-networks#validation) and [Groundwater flow](Groundwater-flow#validation) list them.
- It does not claim the scope of the program. Each solver covers a small part. The Limits section of each page says what is missing.
- It does not claim engineering validity. A checked box in the README records implemented scope. A design needs the review of an engineer.

## How to compare with the program

`deck_text` writes a `StaticProblem` as a CalculiX input deck. Run that deck in CalculiX to compare a result. The other solvers take the same physical inputs as their programs, so a small case can be entered in both by hand.

A difference that a comparison finds is a useful issue. Give the input of both programs and the two results.

## References

- McKenna, Scott and Fenves, "Nonlinear finite-element analysis software architecture using object composition", Journal of Computing in Civil Engineering, 2010: OpenSees.
- Dhondt, "The Finite Element Method for Three-Dimensional Thermomechanical Applications", Wiley, 2004: CalculiX.
- Weller, Tabor, Jasak and Fureby, "A tensorial approach to computational continuum mechanics using object-oriented techniques", Computers in Physics, 1998: OpenFOAM.
- Rossman, "EPANET 2 Users Manual", EPA/600/R-00/057, US Environmental Protection Agency, 2000.
- Brunner, "HEC-RAS River Analysis System Hydraulic Reference Manual", US Army Corps of Engineers, 2016.
- McDonald and Harbaugh, "A modular three-dimensional finite-difference ground-water flow model", US Geological Survey, 1988: MODFLOW.
