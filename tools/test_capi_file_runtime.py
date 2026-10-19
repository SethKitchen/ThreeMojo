# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check the no-files runtime for LLVM emitted on macOS and Linux."""

import ctypes
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


RUNTIME = Path(__file__).resolve().parents[1] / "examples/capi/mwrt.c"


class CapiFileRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which("cc")
        if compiler is None:
            raise unittest.SkipTest("the C runtime test needs cc")
        directory = tempfile.TemporaryDirectory(prefix="threemojo-capi-files-")
        cls.addClassCleanup(directory.cleanup)
        root = Path(directory.name)
        # This section has no wasm intrinsics. Compile the actual functions
        # on the host so both host ABIs can be checked without a wasm compiler.
        text = RUNTIME.read_text(encoding="utf-8")
        files = text.split("/* ---- 3. Files:", 1)[1]
        files = files.split("/* ---- 4. TaskGroup", 1)[0]
        files = files.split("*/", 1)[1]
        source = root / "files.c"
        source.write_text("#include <stdint.h>\n" + files, encoding="utf-8")
        library = root / "files.so"
        subprocess.run(
            [compiler, "-shared", "-fPIC", str(source), "-o", str(library)],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        )
        cls.runtime = ctypes.CDLL(str(library))

    def test_both_errno_accessors_report_no_such_file(self):
        pointers = []
        for name in ("__error", "__errno_location"):
            accessor = getattr(self.runtime, name)
            accessor.argtypes = []
            accessor.restype = ctypes.POINTER(ctypes.c_int)
            pointer = accessor()
            self.assertEqual(pointer.contents.value, 2, name)
            pointers.append(ctypes.addressof(pointer.contents))
        self.assertEqual(pointers[0], pointers[1])

    def test_stat_fails_without_writing_either_platform_layout(self):
        for name in ("stat", "lstat", "__xstat", "__lxstat"):
            with self.subTest(name=name):
                stat = getattr(self.runtime, name)
                stat.restype = ctypes.c_int
                types = [ctypes.c_char_p, ctypes.c_void_p]
                arguments = [b"missing.spz", None]
                if name.startswith("__"):
                    types.insert(0, ctypes.c_int)
                    arguments.insert(0, 0)
                stat.argtypes = types
                # Linux's versioned entry points have an extra first argument.
                # Neither layout is valid on wasm; failed stat must leave it alone.
                buffer = (ctypes.c_ubyte * 512)(*([0xA5] * 512))
                arguments[-1] = ctypes.cast(buffer, ctypes.c_void_p)
                self.assertEqual(stat(*arguments), -1)
                self.assertEqual(bytes(buffer), bytes([0xA5] * 512))
                # No field may be accessed even when the output is null.
                arguments[-1] = None
                self.assertEqual(stat(*arguments), -1)


if __name__ == "__main__":
    unittest.main()
