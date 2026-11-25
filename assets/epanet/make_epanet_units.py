# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write what single functions of the EPANET solver give for set states.

    python3 make_epanet_units.py EPANET units.txt > units.expected

EPANET is a checkout of commit 57d8bd8ad60e89b57f2a1ac591f05c8e13589866
of https://github.com/OpenWaterAnalytics/EPANET, the source of the library
that `make_epanet.py` names. The script copies its `src` and `include`
folders to a temporary folder. It removes `static` from the start of the
lines of `hydstatus.c`, `hydsolver.c` and `hydcoeffs.c`, so that
`epanet_units.c` can call their functions. Then it builds
`epanet_units.c` with the library source and runs it on `units.txt`.

Some states of the solver are hard to reach from an input file: a valve
at a singular node, a leak that has not converged, a pressure driven
demand that does not match its pressure. `units.txt` sets such a state
on a network of `cases.txt` and calls one function. Its lines are:

- `net NAME`: open case NAME of `cases.txt`, open the hydraulics, set
  their starting state and solve the first step.
- `set ARRAY INDEX VALUE`: set one value of the solver, in its internal
  units. ARRAY is `flow`, `head`, `status`, `setting`, `demandflow`,
  `fulldemand`, `nodedemand`, `emitterflow`, `leakageflow`, `km` or
  `tankv`.
- `call FUNCTION ARGS`: call a function. The output repeats the line,
  then `=` and what the function gives. Each number has 17 significant
  digits, so it is exact.

The `net` and `set` lines are repeated in the output.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OPENED = ["hydstatus.c", "hydsolver.c", "hydcoeffs.c"]


def build(epanet, work):
    """Build `epanet_units` in a folder and return its path."""
    src = os.path.join(work, "src")
    shutil.copytree(os.path.join(epanet, "src"), src)
    for name in OPENED:
        path = os.path.join(src, name)
        text = open(path).read()
        open(path, "w").write(re.sub(r"(?m)^static ", "", text))
    sources = [os.path.join(src, n) for n in sorted(os.listdir(src)) if n.endswith(".c")]
    sources += [os.path.join(src, "util", n) for n in sorted(os.listdir(os.path.join(src, "util")))
                if n.endswith(".c")]
    program = os.path.join(work, "epanet_units")
    subprocess.check_call(["cc", "-O2", "-o", program, "-I", os.path.join(epanet, "include"), "-I", src,
                           "-I", os.path.join(src, "util"), os.path.join(HERE, "epanet_units.c")]
                          + sources + ["-lm"])
    return program


def main():
    """Build the program and run it on the command file."""
    epanet = sys.argv[1]
    commands = sys.argv[2]
    with tempfile.TemporaryDirectory() as work:
        program = build(epanet, work)
        cases = os.path.join(HERE, "cases.txt")
        with open(commands) as f:
            run = subprocess.run([program, cases], stdin=f, cwd=work, capture_output=True, text=True)
    if run.returncode != 0:
        sys.exit("epanet_units failed after:\n" + "\n".join(run.stdout.splitlines()[-3:]))
    sys.stdout.write(run.stdout)


main()
