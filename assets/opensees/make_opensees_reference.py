"""Run OpenSeesPy on the truss and section models of the structure tests.

The models are those of tests/test_structure_nonlinear.mojo,
tests/test_structure_transient.mojo and tests/test_structure_section.mojo,
with longer paths than their closed forms can check:

- truss_cyclic.txt: the three-bar truss with 1% hardening, pushed down,
  back up past its start and down again under displacement control.
  Steel01 has the bilinear law with kinematic hardening of the port.
- truss_snap.txt: the shallow truss of two corotational bars, pushed
  through its snap.
- oscillator_cyclic.txt: Chopra's elastoplastic oscillator under a
  harmonic force for 300 steps, so that it yields many times.
- chain_ground.txt: two bars and two masses in a line, which yield, under
  a ground acceleration, by UniformExcitation.
- section_beam.txt and section_column.txt: the moment-curvature curves of
  the reinforced concrete beam and of the steel rectangle under an axial
  force, by a fiber section in a zero-length element.

Each file has one line per step. The tests compare the port with each
value. Run it in Linux, with openseespy 3.8 in the Python of the run:

    python3 assets/opensees/make_opensees_reference.py
"""

import math
import os

import openseespy.opensees as ops

HERE = os.path.dirname(os.path.abspath(__file__))


def newton(test="NormDispIncr", tolerance=1e-14):
    """Ask for a Newton iteration that converges to round-off.

    Args:
        test: The convergence test. Where displacement control holds the
            only free degree of freedom, every correction of the
            displacements is zero, so NormDispIncr passes after one
            iteration with the load factor of the predictor. Such a model
            must test the unbalanced force.
        tolerance: The tolerance of the test.
    """
    ops.system("FullGeneral")
    ops.numberer("Plain")
    ops.constraints("Plain")
    ops.test(test, tolerance, 100)
    ops.algorithm("Newton")


def write(name, header, rows):
    """Write one reference file.

    Args:
        name: The file name.
        header: The comment line, without the leading "#".
        rows: The rows of numbers.
    """
    with open(os.path.join(HERE, name), "w") as out:
        out.write("# OpenSeesPy %s, %s\n" % (ops.version(), header))
        for row in rows:
            out.write(" ".join(repr(float(v)) for v in row) + "\n")


def truss_path():
    """Return the displacement steps of the cyclic truss path, in meters."""
    return [-0.001] * 8 + [0.001] * 14 + [-0.001] * 12


def truss_cyclic():
    """The three-bar truss under a cyclic displacement path."""
    ops.wipe()
    ops.model("basic", "-ndm", 3, "-ndf", 3)
    ops.node(1, 0.0, 0.0, 0.0)
    ops.fix(1, 0, 1, 0)
    for n, x in enumerate((-2.0, 0.0, 2.0), 2):
        ops.node(n, x, 0.0, 2.0)
        ops.fix(n, 1, 1, 1)
    ops.uniaxialMaterial("Steel01", 1, 250e6, 200e9, 0.01)
    for e, n in enumerate((2, 3, 4), 1):
        ops.element("Truss", e, n, 1, 1e-3, 1)
    ops.timeSeries("Linear", 1)
    ops.pattern("Plain", 1, 1)
    ops.load(1, 0.0, 0.0, -1.0)
    newton("NormUnbalance", 1e-5)
    rows = []
    for step in truss_path():
        ops.integrator("DisplacementControl", 1, 3, step)
        ops.analysis("Static")
        assert ops.analyze(1) == 0
        rows.append([ops.getLoadFactor(1), ops.nodeDisp(1, 3)]
                    + [ops.eleResponse(e, "axialForce")[0] for e in (1, 2, 3)])
    write("truss_cyclic.txt", "load factor, sag, force of each bar", rows)


def truss_snap():
    """The shallow truss of two corotational bars, through its snap."""
    ops.wipe()
    ops.model("basic", "-ndm", 3, "-ndf", 3)
    ops.node(1, -2.0, 0.0, 0.0)
    ops.node(2, 2.0, 0.0, 0.0)
    ops.node(3, 0.0, 0.0, 0.2)
    ops.fix(1, 1, 1, 1)
    ops.fix(2, 1, 1, 1)
    ops.fix(3, 1, 1, 0)
    ops.uniaxialMaterial("Elastic", 1, 200e9)
    ops.element("corotTruss", 1, 1, 3, 1e-3, 1)
    ops.element("corotTruss", 2, 2, 3, 1e-3, 1)
    ops.timeSeries("Linear", 1)
    ops.pattern("Plain", 1, 1)
    ops.load(3, 0.0, 0.0, -1.0)
    newton("NormUnbalance", 1e-5)
    rows = []
    for _ in range(50):
        ops.integrator("DisplacementControl", 3, 3, -0.01)
        ops.analysis("Static")
        assert ops.analyze(1) == 0
        rows.append([ops.getLoadFactor(1), ops.nodeDisp(3, 3),
                     ops.eleResponse(1, "axialForce")[0]])
    write("truss_snap.txt", "load factor, apex displacement, bar force",
          rows)


def oscillator_load(step):
    """Return the force factor of the harmonic load at a step.

    Args:
        step: The step, from 1.

    Returns:
        sin(2 pi t / 0.8) at t = 0.1 step, for 2 s, then zero.
    """
    t = 0.1 * step
    return math.sin(2 * math.pi * t / 0.8) if t <= 2.0 + 1e-12 else 0.0


def oscillator_cyclic():
    """Chopra's elastoplastic oscillator under a harmonic force."""
    ops.wipe()
    ops.model("basic", "-ndm", 3, "-ndf", 3)
    ops.node(1, 0.0, 0.0, 0.0)
    ops.node(2, 1.0, 0.0, 0.0)
    ops.fix(1, 1, 1, 1)
    ops.fix(2, 0, 1, 1)
    ops.mass(2, 0.2533, 0.0, 0.0)
    ops.uniaxialMaterial("Steel01", 1, 7.5, 10.0, 0.0)
    ops.element("Truss", 1, 1, 2, 1.0, 1)
    steps = 300
    ops.timeSeries("Path", 1, "-dt", 0.1,
                   "-values", 0.0, *[oscillator_load(s)
                                     for s in range(1, steps + 1)])
    ops.pattern("Plain", 1, 1)
    ops.load(2, 10.0, 0.0, 0.0)
    omega = math.sqrt(10 / 0.2533)
    ops.rayleigh(2 * 0.05 * omega, 0.0, 0.0, 0.0)
    newton()
    ops.integrator("Newmark", 0.5, 0.25)
    ops.analysis("Transient")
    rows = []
    for step in range(1, steps + 1):
        assert ops.analyze(1, 0.1) == 0
        rows.append([ops.getTime(), oscillator_load(step),
                     ops.nodeDisp(2, 1)])
    write("oscillator_cyclic.txt", "time, load factor, displacement", rows)


def ground_acceleration(step):
    """Return the ground acceleration at a step, in m/s^2.

    Args:
        step: The step, from 1.

    Returns:
        A sum of three sines that fades out after 4 s.
    """
    t = 0.02 * step
    fade = 1.0 if t <= 4.0 else max(0.0, 1.0 - (t - 4.0))
    return fade * (3.0 * math.sin(2 * math.pi * 1.1 * t)
                   + 2.0 * math.sin(2 * math.pi * 2.7 * t + 0.4)
                   + 1.0 * math.sin(2 * math.pi * 5.3 * t + 1.1))


def chain_ground():
    """Two bars and two masses in a line under a ground motion."""
    ops.wipe()
    ops.model("basic", "-ndm", 3, "-ndf", 3)
    ops.node(1, 0.0, 0.0, 0.0)
    ops.node(2, 1.0, 0.0, 0.0)
    ops.node(3, 2.0, 0.0, 0.0)
    ops.fix(1, 1, 1, 1)
    ops.fix(2, 0, 1, 1)
    ops.fix(3, 0, 1, 1)
    ops.mass(2, 2.0, 0.0, 0.0)
    ops.mass(3, 1.0, 0.0, 0.0)
    ops.uniaxialMaterial("Steel01", 1, 15.0, 1000.0, 0.05)
    ops.uniaxialMaterial("Steel01", 2, 8.0, 600.0, 0.02)
    # A Truss has no stiffness damping unless -doRayleigh asks for it.
    ops.element("Truss", 1, 1, 2, 1.0, 1, "-doRayleigh", 1)
    ops.element("Truss", 2, 2, 3, 1.0, 2, "-doRayleigh", 1)
    steps = 300
    ops.timeSeries("Path", 1, "-dt", 0.02,
                   "-values", 0.0, *[ground_acceleration(s)
                                     for s in range(1, steps + 1)])
    ops.pattern("UniformExcitation", 1, 1, "-accel", 1)
    ops.rayleigh(0.2, 0.0, 0.002, 0.0)
    newton()
    ops.integrator("Newmark", 0.5, 0.25)
    ops.analysis("Transient")
    rows = []
    for step in range(1, steps + 1):
        assert ops.analyze(1, 0.02) == 0
        rows.append([ops.getTime(), ground_acceleration(step),
                     ops.nodeDisp(2, 1), ops.nodeDisp(3, 1)])
    write("chain_ground.txt", "time, ground acceleration, relative "
          "displacement of nodes 2 and 3", rows)


def moment_curvature(name, build, axial, last, steps):
    """Run a moment-curvature analysis of a fiber section.

    Args:
        name: The file name.
        build: A function that defines section 1.
        axial: The axial force, tension positive, in newtons.
        last: The last curvature, in 1/m.
        steps: The number of steps.
    """
    ops.wipe()
    ops.model("basic", "-ndm", 2, "-ndf", 3)
    ops.node(1, 0.0, 0.0)
    ops.node(2, 0.0, 0.0)
    ops.fix(1, 1, 1, 1)
    ops.fix(2, 0, 1, 0)
    build()
    ops.element("zeroLengthSection", 1, 1, 2, 1)
    newton("NormUnbalance", 1e-4)
    ops.timeSeries("Constant", 1)
    ops.pattern("Plain", 1, 1)
    ops.load(2, axial, 0.0, 0.0)
    ops.integrator("LoadControl", 1.0)
    ops.analysis("Static")
    assert ops.analyze(1) == 0
    ops.loadConst("-time", 0.0)
    ops.timeSeries("Linear", 2)
    ops.pattern("Plain", 2, 2)
    ops.load(2, 0.0, 0.0, 1.0)
    # OpenSees measures the axial strain and the moment about the centroid
    # of the fiber areas. The port measures them about y = 0. With yc the
    # centroid, the strain at y = 0 is the strain at yc plus yc times the
    # curvature, and the moment about y = 0 is that about yc less yc N.
    data = ops.eleResponse(1, "section", "fiberData")
    areas = data[2::5]
    centroid = sum(y * a for y, a in zip(data[0::5], areas)) / sum(areas)
    rows = [[0.0, ops.nodeDisp(2, 1), 0.0]]
    for _ in range(steps):
        ops.integrator("DisplacementControl", 2, 3, last / steps)
        ops.analysis("Static")
        assert ops.analyze(1) == 0
        kappa = ops.nodeDisp(2, 3)
        rows.append([kappa, ops.nodeDisp(2, 1) + centroid * kappa,
                     ops.getLoadFactor(2) - centroid * axial])
    write(name, "curvature, axial strain and moment about y = 0", rows)


def beam_section():
    """The reinforced concrete beam of the section tests."""
    ops.uniaxialMaterial("Concrete01", 1, -30e6, -0.002, -6e6, -0.006)
    ops.uniaxialMaterial("Steel01", 2, 420e6, 200e9, 0.0)
    ops.section("Fiber", 1)
    ops.patch("rect", 1, 100, 1, -0.25, -0.15, 0.25, 0.15)
    ops.fiber(-0.19, 0.0, 1500e-6, 2)


def column_section():
    """The steel rectangle of the section tests."""
    ops.uniaxialMaterial("Steel01", 1, 250e6, 200e9, 0.0)
    ops.section("Fiber", 1)
    ops.patch("rect", 1, 400, 1, -0.1, -0.05, 0.1, 0.05)


def main():
    """Write every reference."""
    truss_cyclic()
    truss_snap()
    oscillator_cyclic()
    chain_ground()
    moment_curvature("section_beam.txt", beam_section, 0.0, 0.06, 120)
    yield_curvature = 2 * 250e6 / (200e9 * 0.2)
    moment_curvature("section_column.txt", column_section,
                     -0.4 * 250e6 * 0.02, 40 * yield_curvature, 80)
    ops.wipe()
    print("written")


if __name__ == "__main__":
    main()
