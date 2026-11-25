"""Run OpenFOAM buoyantBoussinesqPimpleFoam on the cavity of de Vahl Davis.

The cases are those of tests/test_cfd_heat.mojo. The cavity is 1 m a
side, 12 cells a side. The west wall is at 300.5 K, the east wall at
299.5 K, and the other two walls are insulated. The kinematic viscosity
is 0.71 m^2/s, the thermal diffusivity is 1 m^2/s and the expansion is
1/K, so the Prandtl number is 0.71 and the gravity is 0.71 times the
Rayleigh number. The solver runs PISO with two correctors (one outer
corrector), with the scheme and the time step of each test, until the
flow no longer changes. This script then writes u, v and T at each cell
center to convection_<case>.txt.

It needs Docker and the image opencfd/openfoam-default:2406. Run it in
Linux from any folder:

    python3 assets/cfd/make_convection_reference.py

Each output line is "i k u v T" for the cell in column i and row k, both
counted from 0 at the lower left corner.
"""

import os
import re
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGE = "opencfd/openfoam-default:2406"
CELLS = 12
HEADER = """FoamFile
{
    version 2.0;
    format ascii;
    class %s;
    object %s;
}
"""


def write(folder, path, cls, body):
    """Write one OpenFOAM dictionary.

    Args:
        folder: The case folder.
        path: The path of the file in the case.
        cls: The class of the dictionary.
        body: The text after the header.
    """
    full = os.path.join(folder, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as out:
        out.write(HEADER % (cls, os.path.basename(path)) + body)


def case(folder, rayleigh, scheme, dt, end):
    """Write the cavity case.

    Args:
        folder: The case folder.
        rayleigh: The Rayleigh number.
        scheme: The convection scheme, "linear" or "upwind".
        dt: The time step in seconds.
        end: The end time in seconds.
    """
    write(folder, "system/blockMeshDict", "dictionary", """
scale 1;
vertices ((0 0 0) (1 0 0) (1 1 0) (0 1 0) (0 0 0.1) (1 0 0.1) (1 1 0.1) (0 1 0.1));
blocks (hex (0 1 2 3 4 5 6 7) (%d %d 1) simpleGrading (1 1 1));
boundary
(
    hot { type wall; faces ((0 4 7 3)); }
    cold { type wall; faces ((2 6 5 1)); }
    insulated { type wall; faces ((3 7 6 2) (1 5 4 0)); }
    sides { type empty; faces ((0 3 2 1) (4 5 6 7)); }
);
""" % (CELLS, CELLS))
    write(folder, "system/controlDict", "dictionary", """
application buoyantBoussinesqPimpleFoam;
startFrom startTime;
startTime 0;
stopAt endTime;
endTime %g;
deltaT %g;
writeControl runTime;
writeInterval %g;
purgeWrite 1;
writeFormat ascii;
writePrecision 17;
timeFormat general;
timePrecision 8;
runTimeModifiable false;
adjustTimeStep no;
""" % (end, dt, end))
    write(folder, "system/fvSchemes", "dictionary", """
ddtSchemes { default Euler; }
gradSchemes { default Gauss linear; }
divSchemes
{
    default none;
    div(phi,U) Gauss %s;
    div(phi,T) Gauss %s;
    div((nuEff*dev2(T(grad(U))))) Gauss linear;
}
laplacianSchemes { default Gauss linear orthogonal; }
interpolationSchemes { default linear; }
snGradSchemes { default orthogonal; }
""" % (scheme, scheme))
    write(folder, "system/fvSolution", "dictionary", """
solvers
{
    p_rgh { solver PCG; preconditioner DIC; tolerance 1e-12; relTol 0; }
    p_rghFinal { $p_rgh; }
    "(U|T)" { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-12; relTol 0; }
    "(U|T)Final" { $U; }
}
PIMPLE
{
    momentumPredictor yes;
    nOuterCorrectors 1;
    nCorrectors 2;
    nNonOrthogonalCorrectors 0;
    pRefCell 0;
    pRefValue 0;
}
""")
    write(folder, "constant/transportProperties", "dictionary", """
transportModel Newtonian;
nu 0.71;
beta 1;
TRef 300;
Pr 0.71;
Prt 0.85;
""")
    write(folder, "constant/turbulenceProperties", "dictionary", """
simulationType laminar;
""")
    write(folder, "constant/g", "uniformDimensionedVectorField", """
dimensions [0 1 -2 0 0 0 0];
value (0 %r 0);
""" % (-0.71 * rayleigh))
    walls = "hot|cold|insulated"
    write(folder, "0/U", "volVectorField", """
dimensions [0 1 -1 0 0 0 0];
internalField uniform (0 0 0);
boundaryField
{
    "(%s)" { type noSlip; }
    sides { type empty; }
}
""" % walls)
    write(folder, "0/T", "volScalarField", """
dimensions [0 0 0 1 0 0 0];
internalField uniform 300;
boundaryField
{
    hot { type fixedValue; value uniform 300.5; }
    cold { type fixedValue; value uniform 299.5; }
    insulated { type zeroGradient; }
    sides { type empty; }
}
""")
    for name, kind in (("p_rgh", "fixedFluxPressure"), ("p", "calculated")):
        write(folder, "0/" + name, "volScalarField", """
dimensions [0 2 -2 0 0 0 0];
internalField uniform 0;
boundaryField
{
    "(%s)" { type %s; value uniform 0; }
    sides { type empty; }
}
""" % (walls, kind))
    write(folder, "0/alphat", "volScalarField", """
dimensions [0 2 -1 0 0 0 0];
internalField uniform 0;
boundaryField
{
    "(%s)" { type calculated; value uniform 0; }
    sides { type empty; }
}
""" % walls)


def field(folder, end, name, count):
    """Read the cell values of one field.

    Args:
        folder: The case folder.
        end: The time of the field.
        name: The name of the field.
        count: The number of cells.

    Returns:
        A list with the components of each cell.
    """
    text = open(os.path.join(folder, "%g" % end, name)).read()
    body = text[text.index("internalField"):text.index("boundaryField")]
    start = body.index("(")
    inner = body[start + 1:body.rindex(")")]
    if "vector" in body[:start]:
        rows = re.findall(r"\(([^()]+)\)", inner)
        values = [tuple(float(x) for x in r.split()) for r in rows]
    else:
        values = [(float(x),) for x in inner.split()]
    assert len(values) == count, (name, len(values))
    return values


def run(rayleigh, scheme, dt, end):
    """Run the solver and return the cell values.

    Args:
        rayleigh: The Rayleigh number.
        scheme: The convection scheme.
        dt: The time step in seconds.
        end: The end time in seconds.

    Returns:
        A list of (u, v, T), with the column index changing fastest.
    """
    folder = tempfile.mkdtemp(prefix="convection-")
    try:
        case(folder, rayleigh, scheme, dt, end)
        subprocess.run(
            ["docker", "run", "--rm", "-v", folder + ":/case", "-w", "/case",
             "-u", "%d:%d" % (os.getuid(), os.getgid()), IMAGE,
             "bash", "-lc",
             "cd /case && blockMesh > log.blockMesh && "
             "buoyantBoussinesqPimpleFoam > log.solver"],
            check=True)
        count = CELLS * CELLS
        u = field(folder, end, "U", count)
        t = field(folder, end, "T", count)
        return [(a[0], a[1], b[0]) for a, b in zip(u, t)]
    finally:
        shutil.rmtree(folder, ignore_errors=True)


# The name, Rayleigh number, scheme and time step of each test.
CASES = (
    ("ra1000", 1000.0, "linear", 0.02),
    ("ra10000", 10000.0, "upwind", 0.005),
)


def main():
    """Write the reference of each case."""
    for name, rayleigh, scheme, dt in CASES:
        values = run(rayleigh, scheme, dt, 20.0)
        with open(os.path.join(HERE, "convection_%s.txt" % name), "w") as out:
            out.write("# buoyantBoussinesqPimpleFoam 2406, Ra %g, %s, "
                      "dt %g s, t 20 s\n" % (rayleigh, scheme, dt))
            for n, (u, v, temp) in enumerate(values):
                out.write("%d %d %r %r %r\n"
                          % (n % CELLS, n // CELLS, u, v, temp))
        print("convection_%s.txt" % name)


if __name__ == "__main__":
    main()
