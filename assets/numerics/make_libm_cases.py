"""Write libm_cases.txt: results of glibc's pow and log, as bits.

Run on Linux x86-64 with glibc, on a processor with fused multiply-add:

    python3 assets/numerics/make_libm_cases.py

The script compiles libm_cases.c with `cc -fno-builtin`, so that each
call goes to glibc, and runs it. Each line of the output is one call:

    pow X Y RESULT
    log X RESULT

with each double as 16 hexadecimal digits of its bits. The cases are
chosen inputs that reach each branch of the code, and random inputs in
several ranges. tests/test_numerics_libm.mojo compares
extensions/numerics/libm.mojo with each line.
"""

import os
import platform
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    """Build the program, run it and write the cases."""
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        sys.exit("make_libm_cases.py: run this on Linux x86-64 with glibc")
    with open("/proc/cpuinfo") as cpu:
        if " fma " not in cpu.read():
            sys.exit("make_libm_cases.py: glibc must run its fma build")
    with tempfile.TemporaryDirectory() as work:
        program = os.path.join(work, "libm_cases")
        subprocess.run(
            ["cc", "-O1", "-fno-builtin", "-o", program,
             os.path.join(HERE, "libm_cases.c"), "-lm"],
            check=True,
        )
        out = subprocess.run([program], check=True, capture_output=True,
                             text=True).stdout
    version = subprocess.run(["ldd", "--version"], capture_output=True,
                             text=True).stdout.splitlines()[0]
    target = os.path.join(HERE, "libm_cases.txt")
    with open(target, "w", newline="\n") as f:
        f.write("# " + version + "\n")
        f.write(out)
    print("wrote", target, len(out.splitlines()), "cases")


if __name__ == "__main__":
    main()
