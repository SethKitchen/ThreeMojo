"""Write CalculiX decks of a cantilever and run CalculiX CrunchiX on them.

Each deck is a steel beam, 4 m long and 1 m by 1 m in section, fixed at
x = 0. A box mesh of 8 by 2 by 2 cubes is cut into six tetrahedra per
cube. The decks are:

- cantilever_c3d4.inp: four-node elements, a load at the tip and gravity.
- cantilever_c3d10.inp: ten-node elements, a pressure on the top faces
  and a side load at one corner of the tip.

The script runs ccx 2.21 on each deck and writes the displacement of
each node to <deck>.expected, one line "node ux uy uz" in meters.
tests/test_fem_calculix.mojo reads the same decks with the port and
compares the displacements.

It needs ccx on the path. Run it in Linux from any folder:

    python3 assets/calculix/make_calculix_reference.py
"""

import itertools
import os
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
L, W, H = 4.0, 1.0, 1.0
NX, NY, NZ = 8, 2, 2


def corner_nodes():
    """Return the corner node coordinates and their numbers.

    Returns:
        A dictionary from (i, j, k) to (number, x, y, z).
    """
    nodes = {}
    number = 1
    for k in range(NZ + 1):
        for j in range(NY + 1):
            for i in range(NX + 1):
                nodes[(i, j, k)] = (number, L * i / NX, W * j / NY,
                                    H * k / NZ)
                number += 1
    return nodes


def volume(p):
    """Return six times the signed volume of a tetrahedron.

    Args:
        p: The four corner points.

    Returns:
        The triple product of the three edges from the first corner.
    """
    a = [p[1][n] - p[0][n] for n in range(3)]
    b = [p[2][n] - p[0][n] for n in range(3)]
    c = [p[3][n] - p[0][n] for n in range(3)]
    return (a[0] * (b[1] * c[2] - b[2] * c[1])
            - a[1] * (b[0] * c[2] - b[2] * c[0])
            + a[2] * (b[0] * c[1] - b[1] * c[0]))


def tetrahedra(nodes):
    """Cut each cube into six tetrahedra along its main diagonal.

    Args:
        nodes: The corner nodes.

    Returns:
        A list of four corner keys per element, each with a positive
        volume.
    """
    out = []
    unit = ((1, 0, 0), (0, 1, 0), (0, 0, 1))
    for k in range(NZ):
        for j in range(NY):
            for i in range(NX):
                for order in itertools.permutations(range(3)):
                    path = [(i, j, k)]
                    for axis in order:
                        last = path[-1]
                        path.append(tuple(last[n] + unit[axis][n]
                                          for n in range(3)))
                    points = [nodes[q][1:] for q in path]
                    if volume(points) < 0:
                        path[1], path[2] = path[2], path[1]
                    out.append(path)
    return out


# The corners of each face, in the face numbering of CalculiX.
FACES = ((0, 1, 2), (0, 3, 1), (1, 3, 2), (2, 3, 0))
# The edges of a ten-node element, in the node order of CalculiX.
EDGES = ((0, 1), (1, 2), (2, 0), (0, 3), (1, 3), (2, 3))


def deck(quadratic):
    """Return the text of one deck.

    Args:
        quadratic: True for ten-node elements.

    Returns:
        The deck.
    """
    nodes = corner_nodes()
    elements = tetrahedra(nodes)
    coords = {v[0]: v[1:] for v in nodes.values()}
    numbers = [[nodes[q][0] for q in e] for e in elements]
    mids = {}
    if quadratic:
        next_number = len(coords) + 1
        for e in numbers:
            for a, b in EDGES:
                key = (min(e[a], e[b]), max(e[a], e[b]))
                if key not in mids:
                    pa, pb = coords[e[a]], coords[e[b]]
                    coords[next_number] = tuple((pa[n] + pb[n]) / 2
                                                for n in range(3))
                    mids[key] = next_number
                    next_number += 1
    lines = ["*HEADING", "A cantilever, %s" % ("C3D10" if quadratic
                                               else "C3D4"),
             "*NODE, NSET=Nall"]
    for n in sorted(coords):
        lines.append("%d, %r, %r, %r" % ((n,) + coords[n]))
    lines.append("*ELEMENT, TYPE=%s, ELSET=Eall"
                 % ("C3D10" if quadratic else "C3D4"))
    for number, e in enumerate(numbers, 1):
        row = list(e)
        if quadratic:
            row += [mids[(min(e[a], e[b]), max(e[a], e[b]))]
                    for a, b in EDGES]
        lines.append("%d, %s" % (number, ", ".join(str(n) for n in row)))
    fixed = [n for n in sorted(coords) if coords[n][0] == 0.0]
    lines.append("*NSET, NSET=Fixed")
    lines += ["%d," % n for n in fixed]
    lines += ["*MATERIAL, NAME=Steel", "*ELASTIC", "2.0e11, 0.3",
              "*DENSITY", "7850.", "*SOLID SECTION, ELSET=Eall, MATERIAL=Steel",
              "*BOUNDARY", "Fixed, 1, 3", "*STEP", "*STATIC"]
    tip = [n for n in sorted(coords) if coords[n][0] == L]
    if quadratic:
        lines.append("*DLOAD")
        for number, e in enumerate(numbers, 1):
            for face, corners in enumerate(FACES, 1):
                if all(coords[e[c]][2] == H for c in corners):
                    lines.append("%d, P%d, 1.0e6" % (number, face))
        corner = [n for n in tip if coords[n][1] == 0.0 and
                  coords[n][2] == H][0]
        lines += ["*CLOAD", "%d, 2, 2.0e5" % corner]
    else:
        lines.append("*CLOAD")
        lines += ["%d, 3, %r" % (n, -9.0e5 / len(tip)) for n in tip]
        lines += ["*DLOAD", "Eall, GRAV, 9.81, 0., 0., -1."]
    lines += ["*NODE PRINT, NSET=Nall", "U", "*END STEP", ""]
    return "\n".join(lines)


def displacements(dat):
    """Read the displacements of a .dat file.

    Args:
        dat: The text of the file.

    Returns:
        A list of (node, ux, uy, uz).
    """
    out = []
    reading = False
    for line in dat.splitlines():
        if line.strip().startswith("displacements"):
            reading = True
            continue
        if reading:
            words = line.split()
            if len(words) == 4:
                out.append((int(words[0]),) + tuple(float(w)
                                                    for w in words[1:]))
            elif out:
                break
    return out


def main():
    """Write each deck and its reference."""
    for name, quadratic in (("cantilever_c3d4", False),
                            ("cantilever_c3d10", True)):
        text = deck(quadratic)
        with open(os.path.join(HERE, name + ".inp"), "w") as out:
            out.write(text)
        folder = tempfile.mkdtemp(prefix="calculix-")
        try:
            shutil.copy(os.path.join(HERE, name + ".inp"), folder)
            subprocess.run(["ccx", "-i", name], cwd=folder, check=True,
                           stdout=subprocess.DEVNULL)
            rows = displacements(open(os.path.join(folder,
                                                   name + ".dat")).read())
        finally:
            shutil.rmtree(folder, ignore_errors=True)
        with open(os.path.join(HERE, name + ".expected"), "w") as out:
            out.write("# ccx 2.21, node ux uy uz in meters\n")
            for row in rows:
                out.write("%d %r %r %r\n" % row)
        print(name, len(rows), "nodes")


if __name__ == "__main__":
    main()
