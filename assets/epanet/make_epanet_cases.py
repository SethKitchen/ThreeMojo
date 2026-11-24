# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the results of EPANET for each case of a case file.

    python3 make_epanet_cases.py LIBRARY cases.txt > cases.expected

LIBRARY is the EPANET library that `make_epanet.py` names. A line
`#### NAME` starts a case. The lines after it, to the next case, are a
small input file.

For each case the output has a line `case NAME`, then `open CODE` with
the code of `EN_open`. A case that does not open has a line
`error CODE LINE` for each input error in the report. LINE is the input
line, trimmed. A case
that opens has the lines of `make_epanet.py`, up to the first call that
fails. That call has a line with its name and its error code. A case
whose name starts with `together_` runs the hydraulics and the water
quality together, as `simulate_together` does.
"""

import ctypes
import os
import re
import sys
import tempfile

from make_epanet import Failed, simulate, simulate_together

ERROR = re.compile(r"^  (?:Input )?Error (\d+): ")


def cases(path):
    """Return the name and the text of each case in a case file."""
    out = []
    for line in open(path):
        if line.startswith("#### "):
            out.append([line[5:].strip(), ""])
        elif out:
            out[-1][1] += line
    return out


def report_errors(path):
    """Print the code and the input line of each error in a report."""
    lines = open(path).read().split("\n")
    for i, line in enumerate(lines):
        m = ERROR.match(line)
        if m and m.group(1) != "200" and i + 1 < len(lines):
            print("error", m.group(1), lines[i + 1].strip())


def main():
    lib = ctypes.CDLL(sys.argv[1])
    with tempfile.TemporaryDirectory() as work:
        inp = os.path.join(work, "case.inp")
        rpt = os.path.join(work, "case.rpt")
        for name, text in cases(sys.argv[2]):
            open(inp, "w").write(text)
            project = ctypes.c_void_p()
            lib.EN_createproject(ctypes.byref(project))
            code = lib.EN_open(project, inp.encode(), rpt.encode(), b"")
            print("case", name)
            print("open", code)
            if code <= 100:
                try:
                    if name.startswith("together_"):
                        simulate_together(lib, project)
                    else:
                        simulate(lib, project)
                except Failed:
                    pass
            lib.EN_close(project)
            lib.EN_deleteproject(project)
            if code > 100:
                report_errors(rpt)


if __name__ == "__main__":
    main()
