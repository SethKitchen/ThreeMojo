"""Run OpenFOAM icoFoam on the lid-driven cavity of tests/test_cfd_flow.mojo.

The cavity is 1 m a side, the lid moves at 1 m/s and the kinematic
viscosity is 0.01 m^2/s, so the Reynolds number is 100. The case uses
the central scheme (Gauss linear), PISO with two correctors and the
time step of the test, as the port does. icoFoam runs until the flow no
longer changes, then this script writes the velocity at each cell
center to cavity_<n>.txt.

It needs Docker and the image opencfd/openfoam-default:2406. Run it in
Linux from any folder:

    python3 assets/cfd/make_cavity_reference.py

Each output line is "i k u v" for the cell in column i and row k, both
counted from 0 at the lower left corner.
"""

import os
import re
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
IMAGE = "opencfd/openfoam-default:2406"
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


def case(folder, cells, dt, end):
    """Write the cavity case.

    Args:
        folder: The case folder.
        cells: The number of cells on a side.
        dt: The time step in seconds.
        end: The end time in seconds.
    """
    write(folder, "system/blockMeshDict", "dictionary", """
scale 1;
vertices ((0 0 0) (1 0 0) (1 1 0) (0 1 0) (0 0 0.1) (1 0 0.1) (1 1 0.1) (0 1 0.1));
blocks (hex (0 1 2 3 4 5 6 7) (%d %d 1) simpleGrading (1 1 1));
boundary
(
    lid { type wall; faces ((3 7 6 2)); }
    walls { type wall; faces ((0 4 7 3) (2 6 5 1) (1 5 4 0)); }
    sides { type empty; faces ((0 3 2 1) (4 5 6 7)); }
);
""" % (cells, cells))
    write(folder, "system/controlDict", "dictionary", """
application icoFoam;
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
""" % (end, dt, end))
    write(folder, "system/fvSchemes", "dictionary", """
ddtSchemes { default Euler; }
gradSchemes { default Gauss linear; }
divSchemes { default none; div(phi,U) Gauss linear; }
laplacianSchemes { default Gauss linear orthogonal; }
interpolationSchemes { default linear; }
snGradSchemes { default orthogonal; }
""")
    write(folder, "system/fvSolution", "dictionary", """
solvers
{
    p { solver PCG; preconditioner DIC; tolerance 1e-12; relTol 0; }
    pFinal { $p; }
    U { solver smoothSolver; smoother symGaussSeidel; tolerance 1e-12; relTol 0; }
}
PISO { nCorrectors 2; nNonOrthogonalCorrectors 0; pRefCell 0; pRefValue 0; }
""")
    write(folder, "constant/transportProperties", "dictionary", """
nu 0.01;
""")
    write(folder, "0/U", "volVectorField", """
dimensions [0 1 -1 0 0 0 0];
internalField uniform (0 0 0);
boundaryField
{
    lid { type fixedValue; value uniform (1 0 0); }
    walls { type noSlip; }
    sides { type empty; }
}
""")
    write(folder, "0/p", "volScalarField", """
dimensions [0 2 -2 0 0 0 0];
internalField uniform 0;
boundaryField
{
    lid { type zeroGradient; }
    walls { type zeroGradient; }
    sides { type empty; }
}
""")


def run(cells, dt, end):
    """Run icoFoam and return the cell velocities.

    Args:
        cells: The number of cells on a side.
        dt: The time step in seconds.
        end: The end time in seconds.

    Returns:
        A list of (u, v), with the column index changing fastest.
    """
    folder = tempfile.mkdtemp(prefix="cavity-")
    try:
        case(folder, cells, dt, end)
        subprocess.run(
            ["docker", "run", "--rm", "-v", folder + ":/case", "-w", "/case",
             "-u", "%d:%d" % (os.getuid(), os.getgid()), IMAGE,
             "bash", "-lc",
             "cd /case && blockMesh > log.blockMesh && icoFoam > log.icoFoam"],
            check=True)
        text = open(os.path.join(folder, "%g" % end, "U")).read()
        body = text[text.index("internalField"):]
        count = int(re.search(r"List<vector>\s*(\d+)", body).group(1))
        rows = re.findall(r"\(([^()]+)\)", body[body.index("(") + 1:])[:count]
        assert count == cells * cells and len(rows) == count
        return [tuple(float(x) for x in r.split()[:2]) for r in rows]
    finally:
        shutil.rmtree(folder, ignore_errors=True)


def main():
    """Write the reference of each grid."""
    for cells in (8, 16):
        # The time step of the port's test: 5 s over the number of cells.
        # The steady flow of icoFoam depends on the time step, so the two
        # must be the same. From 100 s to 200 s the flow changes by 3e-13.
        dt = 5.0 / cells
        values = run(cells, dt, 200.0)
        with open(os.path.join(HERE, "cavity_%d.txt" % cells), "w") as out:
            out.write("# icoFoam 2406, %d x %d cells, dt %g s, t 200 s\n"
                      % (cells, cells, dt))
            for n, (u, v) in enumerate(values):
                out.write("%d %d %r %r\n" % (n % cells, n // cells, u, v))
        print("cavity_%d.txt" % cells)


if __name__ == "__main__":
    main()
