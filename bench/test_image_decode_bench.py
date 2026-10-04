# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Python-only harness checks. These do not compile or run Mojo."""

import argparse
import contextlib
import io
import json
import os
import signal
import select
import subprocess
import time
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

import image_decode_bench as bench
import image_decode_fixture as fixture

HELPER = os.environ.get("THREEMOJO_RUSAGE_HELPER")
REQUIRES_HELPER = unittest.skipUnless(HELPER, "Parent must compile the C helper; set THREEMOJO_RUSAGE_HELPER")


class Fixtures(unittest.TestCase):
    def test_fnv_vectors(self):
        self.assertEqual(fixture.fnv64(b""), 14695981039346656037)
        self.assertEqual(fixture.fnv64(b"a"), 12638187200555641996)

    def test_adversarial_jobs(self):
        sizes = fixture.dimensions("stride_skew", 16, 4)
        self.assertEqual([i for i, n in enumerate(sizes) if n == 768], [0, 4, 8, 12])
        sizes = fixture.dimensions("batch_boundary", 16, 4)
        self.assertEqual([i for i, n in enumerate(sizes) if n == 768], [3, 4, 11, 12])

    def test_png_crc_and_pixels(self):
        pixels = fixture.rgba(16, 3)
        encoded = fixture.png(16, pixels)
        self.assertEqual(encoded, fixture.png(16, fixture.rgba(16, 3)))
        self.assertEqual(encoded[:8], b"\x89PNG\r\n\x1a\n")
        at, compressed = 8, bytearray()
        while at < len(encoded):
            size = struct.unpack_from(">I", encoded, at)[0]
            kind, data = encoded[at + 4:at + 8], encoded[at + 8:at + 8 + size]
            checksum = struct.unpack_from(">I", encoded, at + 8 + size)[0]
            self.assertEqual(checksum, zlib.crc32(kind + data))
            if kind == b"IDAT":
                compressed.extend(data)
            at += 12 + size
        raw = zlib.decompress(compressed)
        self.assertEqual(raw, b"".join(b"\0" + pixels[y * 64:(y + 1) * 64] for y in range(16)))

    def test_gltf_and_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = fixture.generate(root, count=3, datasets=["uniform_tiny"])
            data = result["datasets"][0]
            gltf = bench.read_json(root / "uniform_tiny/scene.gltf")
            manifest = bench.read_json(root / "uniform_tiny/manifest.json")
            self.assertEqual(len(gltf["images"]), 3)
            self.assertEqual(len(gltf["meshes"][0]["primitives"]), 3)
            self.assertEqual(len(manifest["bindings"]), 3)
            self.assertEqual(data["expected"]["base_bytes"], 3 * 16 * 16 * 4)
            self.assertEqual(data["expected"]["payload_bytes"], 3 * (256 + 64 + 16 + 4 + 1) * 4)
            for item in data["files"]:
                path = root / "uniform_tiny" / item["path"]
                self.assertEqual(path.stat().st_size, item["bytes"])
                self.assertEqual(bench.sha(path), item["sha256"])


class Measurement(unittest.TestCase):
    def test_resource_guards(self):
        with patch.object(bench, "read_optional", return_value="MemAvailable: 1024 kB"):
            with self.assertRaisesRegex(RuntimeError, "below 3 GiB"):
                bench.resource_guard(".")
        with patch.object(bench, "read_optional", return_value="MemAvailable: 9999999 kB"):
            with patch.object(bench.shutil, "disk_usage", return_value=argparse.Namespace(free=1)):
                with self.assertRaisesRegex(RuntimeError, "below 2 GiB"):
                    bench.resource_guard(".")

    @REQUIRES_HELPER
    def test_protocol_runner_with_python_stub(self):
        # This checks the runner protocol, not native image loading performance.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture.generate(root / "fixtures", count=2, datasets=["uniform_tiny"])
            stub = root / "protocol_stub.py"
            stub.write_text("#!" + sys.executable + "\n" +
                "import json, pathlib, sys\n"
                "root = pathlib.Path(sys.argv[1]).parent\n"
                "expected = json.loads((root / 'fixtures.json').read_text())['datasets'][0]['expected']\n"
                "parts = ['result', 'api', sys.argv[2], 'workers', sys.argv[3], 'runtime_parallelism', '4', 'load_ns', '100']\n"
                "for k, v in expected.items(): parts.extend([k, str(v)])\n"
                "parts.extend(['all_fnv64', '1', 'shape_fnv64', '1'])\n"
                "print(' '.join(parts))\n")
            stub.chmod(0o755)
            build_path = root / "fake-build.json"
            bench.write_json(build_path, {"status": "complete",
                "rusage_helper": {"binary": HELPER, "binary_sha256": bench.sha(HELPER)}, "variants": {
                name: {"binary": str(stub), "binary_sha256": bench.sha(stub)}
                for name in ("baseline", "dynamic")}})
            args = argparse.Namespace(build=build_path, fixtures=root / "fixtures",
                destination=root / "protocol-output", baseline="baseline", repetitions=1,
                datasets=None, workers=[1, 2], apis=["gltf"], seed=505, timeout=5)
            with contextlib.redirect_stdout(io.StringIO()):
                bench.run(args)
            metadata = bench.read_json(args.destination / "metadata.json")
            self.assertEqual(metadata["status"], "complete")
            self.assertEqual(metadata["completed_rows"], 4)
            self.assertEqual(len((args.destination / "raw.jsonl").read_text().splitlines()), 4)
            self.assertEqual(len((args.destination / "validated.jsonl").read_text().splitlines()), 4)

    def test_rusage_marker_parser(self):
        unit = "KiB" if sys.platform.startswith("linux") else "bytes"
        multiplier = 1024 if unit == "KiB" else 1
        record = {"schema": 1, "rss_unit": unit, "maxrss_raw": 7,
                  "peak_rss_bytes": 7 * multiplier}
        marker = bench.RUSAGE_MARKER + json.dumps(record) + "\n"
        parsed, stderr = bench.parse_rusage("native diagnostic\n" + marker)
        self.assertEqual(parsed, record)
        self.assertEqual(stderr, "native diagnostic\n")
        with self.assertRaises(ValueError):
            bench.parse_rusage(marker + marker)
        with self.assertRaises(ValueError):
            bench.parse_rusage("native diagnostic only")

    @REQUIRES_HELPER
    def test_true_rss_independent_of_python_parent_heap(self):
        before = [bench.measure(["/bin/true"], 10, ".", HELPER) for _ in range(3)]
        memory = bytearray(128 * 1024 * 1024)
        memory[::4096] = b"x" * len(memory[::4096])
        after = [bench.measure(["/bin/true"], 10, ".", HELPER) for _ in range(3)]
        self.assertEqual(memory[0], ord("x"))  # Keep the enlarged heap live through all launches.
        for row in before + after:
            self.assertEqual(row["exit_code"], 0)
            self.assertIsNone(row["measurement_error"])
        self.assertLess(max(row["peak_rss_bytes"] for row in after),
                        max(row["peak_rss_bytes"] for row in before) + 16 * 1024 * 1024)
        self.assertLess(max(row["peak_rss_bytes"] for row in after), 64 * 1024 * 1024)

    @REQUIRES_HELPER
    def test_native_errors_propagate(self):
        row = bench.measure([sys.executable, "-c", "raise SystemExit(23)"], 10, ".", HELPER)
        self.assertEqual(row["exit_code"], 23)
        self.assertEqual(row["native_exit_code"], 23)
        row = bench.measure([sys.executable, "-c", "import os,signal; os.kill(os.getpid(),signal.SIGTERM)"], 10, ".", HELPER)
        self.assertEqual(row["exit_code"], -signal.SIGTERM)
        self.assertEqual(row["native_exit_code"], -signal.SIGTERM)
        row = bench.measure(["/path/that/does/not/exist/image_decode"], 10, ".", HELPER)
        self.assertEqual(row["exit_code"], 127)
        self.assertIsNotNone(row["measurement_error"])
        self.assertNotEqual(row["rusage"]["exec_errno"], 0)

    def test_parser(self):
        parsed = bench.parse_output("result api gltf workers 4 load_ns 123\n")
        self.assertEqual(parsed, {"api": "gltf", "workers": 4, "load_ns": 123})
        with self.assertRaises(ValueError):
            bench.parse_output("result api gltf workers 1 workers 2")

    @REQUIRES_HELPER
    def test_per_child_rss(self):
        # Large first, small second: a cumulative children high-water mark
        # would incorrectly give the second process the first one's memory.
        code = ("import sys; a=bytearray(int(sys.argv[1])*1024*1024); "
                "a[::4096]=b'x'*len(a[::4096]); print('rss-test')")
        big = bench.measure([sys.executable, "-c", code, "64"], 10, ".", HELPER)
        small = bench.measure([sys.executable, "-c", code, "1"], 10, ".", HELPER)
        self.assertEqual(big["exit_code"], 0)
        self.assertEqual(small["exit_code"], 0)
        self.assertGreater(big["peak_rss_bytes"], small["peak_rss_bytes"] + 24 * 1024 * 1024)

    @REQUIRES_HELPER
    @unittest.skipUnless(sys.platform.startswith("linux") and hasattr(os, "pidfd_open")
                         and hasattr(signal, "pidfd_send_signal"),
                         "Linux pidfds are required for reuse-safe descendant lifetime checks")
    def test_timeout_terminates_native_and_descendant(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / "timeout_tree.py"
            script.write_text(
                "import json, os, pathlib, subprocess, sys, time\n"
                "root, role = pathlib.Path(sys.argv[1]), sys.argv[2]\n"
                "stat = pathlib.Path('/proc/self/stat').read_text().rsplit(')', 1)[1].split()\n"
                "identity = {'pid': os.getpid(), 'starttime': stat[19]}\n"
                "temporary = root / (role + '.tmp')\n"
                "temporary.write_text(json.dumps(identity))\n"
                "temporary.replace(root / (role + '.json'))\n"
                "if role == 'native': subprocess.Popen([sys.executable, __file__, str(root), 'descendant'])\n"
                "while True: time.sleep(10)\n")
            actual_popen = subprocess.Popen
            handles = []

            def ready_popen(*args, **kwargs):
                # Wait for both identities before starting the tested wait timeout.
                # This does not change measure's timeout or killpg implementation.
                child = actual_popen(*args, **kwargs)
                try:
                    deadline = time.monotonic() + 5
                    files = [root / (role + ".json") for role in ("native", "descendant")]
                    while not all(path.exists() for path in files):
                        if child.poll() is not None:
                            raise AssertionError("Supervisor exited before both descendants started")
                        if time.monotonic() >= deadline:
                            raise AssertionError("Timeout fixture did not become ready")
                        time.sleep(0.01)
                    for path in files:
                        identity = json.loads(path.read_text())
                        handle = os.pidfd_open(identity["pid"])
                        handles.append(handle)
                        stat = Path(f"/proc/{identity['pid']}/stat").read_text().rsplit(")", 1)[1].split()
                        self.assertEqual(stat[19], identity["starttime"])
                        ready = select.poll()
                        ready.register(handle, select.POLLIN)
                        self.assertEqual(ready.poll(0), [])
                    return child
                except BaseException:
                    try:
                        os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    child.wait()
                    raise

            try:
                with patch.object(bench.subprocess, "Popen", side_effect=ready_popen):
                    row = bench.measure([sys.executable, str(script), str(root), "native"],
                                        0.05, directory, HELPER)
                self.assertTrue(row["timed_out"])
                self.assertNotEqual(row["exit_code"], 0)
                self.assertIsNone(row["peak_rss_bytes"])
                self.assertEqual(len(handles), 2)
                pending = set(handles)
                deaths = select.poll()
                for handle in handles:
                    deaths.register(handle, select.POLLIN)
                deadline = time.monotonic() + 2
                while pending and time.monotonic() < deadline:
                    for handle, events in deaths.poll(50):
                        if events & (select.POLLIN | select.POLLHUP):
                            pending.discard(handle)
                            deaths.unregister(handle)
                self.assertFalse(pending, "Native child or descendant survived timeout killpg")
            finally:
                # pidfds refer to the original processes even if numeric PIDs recur.
                for handle in handles:
                    try:
                        signal.pidfd_send_signal(handle, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    os.close(handle)

    def test_summary_pairs(self):
        rows = []
        for repetition in range(3):
            for variant, ns in (("baseline", 100), ("dynamic", 50)):
                native = {key: 1 for key in bench.CHECK_FIELDS}
                native.update(load_ns=ns, runtime_parallelism=4, base_bytes=400)
                rows.append({"dataset": "test", "api": "gltf", "workers": 4,
                             "variant": variant, "repetition": repetition,
                             "peak_rss_bytes": 100, "native": native})
        summary = bench.summarize(rows, "baseline")
        dynamic = next(row for row in summary if row["variant"] == "dynamic")
        self.assertEqual(dynamic["paired_speedup_vs_baseline"]["median"], 2)
        self.assertEqual(dynamic["base_megapixels_per_second"]["median"], 2000)
        self.assertEqual(dynamic["load_ns"]["n"], 3)


class RejectedEvidence(unittest.TestCase):
    def prepare(self, root):
        fixture.generate(root / "fixtures", count=2, datasets=["uniform_tiny"])
        helper = root / "helper-placeholder"
        helper.write_bytes(b"helper recorded bytes")
        variants = {}
        for label in ("baseline", "dynamic"):
            binary = root / label
            binary.write_bytes(b"native recorded bytes")
            variants[label] = {"binary": str(binary), "binary_sha256": bench.sha(binary)}
        record = {"status": "complete", "rusage_helper": {
            "binary": str(helper), "binary_sha256": bench.sha(helper)}, "variants": variants}
        build = root / "build.json"
        bench.write_json(build, record)
        args = argparse.Namespace(build=build, fixtures=root / "fixtures",
            destination=root / "results", baseline="baseline", repetitions=1,
            datasets=None, workers=[1], apis=["gltf"], seed=505, timeout=5)
        expected = bench.read_json(args.fixtures / "fixtures.json")["datasets"][0]["expected"]
        return args, expected

    def measured_row(self, expected, changes=None):
        native = dict(expected, api="gltf", workers=1, runtime_parallelism=4,
                      load_ns=100, all_fnv64=17, shape_fnv64=19)
        native.update(changes or {})
        line = "result " + " ".join(f"{key} {value}" for key, value in native.items()) + "\n"
        return {"exit_code": 0, "timed_out": False, "measurement_error": None,
                "stdout": line, "stderr": "", "peak_rss_bytes": 100}

    def test_tampered_fixture_hash_rejected_before_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args, _ = self.prepare(root)
            path = args.fixtures / "uniform_tiny/image-0000.png"
            content = bytearray(path.read_bytes())
            content[-1] ^= 1  # Same length: this specifically tests SHA-256 admission.
            path.write_bytes(content)
            with patch.object(bench, "measure") as measure:
                with self.assertRaisesRegex(RuntimeError, "Fixture changed"):
                    bench.run(args)
                measure.assert_not_called()

    def test_tampered_native_or_helper_binary_rejected_before_launch(self):
        for label in ("baseline", "helper-placeholder"):
            with self.subTest(binary=label), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                args, _ = self.prepare(root)
                path = root / label
                content = bytearray(path.read_bytes())
                content[0] ^= 1
                path.write_bytes(content)
                pattern = "Binary changed since build" if label == "baseline" else "RSS supervisor binary changed"
                with patch.object(bench, "measure") as measure:
                    with self.assertRaisesRegex(RuntimeError, pattern):
                        bench.run(args)
                    measure.assert_not_called()

    def test_incorrect_base_hash_rejected_by_fixture_oracle(self):
        with tempfile.TemporaryDirectory() as directory:
            args, expected = self.prepare(Path(directory))
            row = self.measured_row(expected, {"base_fnv64": expected["base_fnv64"] ^ 1})
            with patch.object(bench, "measure", return_value=row):
                with contextlib.redirect_stdout(io.StringIO()):
                    with self.assertRaisesRegex(RuntimeError, "Fixture oracle failed.*base_fnv64"):
                        bench.run(args)
            metadata = bench.read_json(args.destination / "metadata.json")
            self.assertEqual(metadata["status"], "failed")
            self.assertEqual(metadata["completed_rows"], 0)
            self.assertEqual(len((args.destination / "raw.jsonl").read_text().splitlines()), 1)

    def test_incorrect_all_mip_or_shape_hash_rejected(self):
        for field in ("all_fnv64", "shape_fnv64"):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                args, expected = self.prepare(Path(directory))
                rows = [self.measured_row(expected), self.measured_row(expected, {field: 99})]
                with patch.object(bench, "measure", side_effect=rows):
                    with contextlib.redirect_stdout(io.StringIO()):
                        with self.assertRaisesRegex(RuntimeError, "Output differs across variants/workers/trials"):
                            bench.run(args)
                metadata = bench.read_json(args.destination / "metadata.json")
                self.assertEqual(metadata["status"], "failed")
                self.assertEqual(metadata["completed_rows"], 1)
                self.assertEqual(len((args.destination / "raw.jsonl").read_text().splitlines()), 2)
                self.assertEqual(len((args.destination / "validated.jsonl").read_text().splitlines()), 1)

    def test_invalid_rss_units_and_conversion_rejected(self):
        unit = "KiB" if sys.platform.startswith("linux") else "bytes"
        multiplier = 1024 if unit == "KiB" else 1
        correct = {"schema": 1, "rss_unit": unit, "maxrss_raw": 7,
                   "peak_rss_bytes": 7 * multiplier}
        for changes in ({"rss_unit": "MiB"}, {"peak_rss_bytes": 7 * multiplier + 1},
                        {"maxrss_raw": -1, "peak_rss_bytes": -multiplier}):
            with self.subTest(changes=changes):
                record = dict(correct, **changes)
                with self.assertRaises(ValueError):
                    bench.parse_rusage(bench.RUSAGE_MARKER + json.dumps(record) + "\n")

    def test_native_supervisor_status_disagreement_rejected(self):
        unit = "KiB" if sys.platform.startswith("linux") else "bytes"
        multiplier = 1024 if unit == "KiB" else 1
        for exit_status, native_signal in ((23, 0), (-1, signal.SIGTERM)):
            with self.subTest(exit_status=exit_status, native_signal=native_signal):
                usage = {"schema": 1, "rss_unit": unit, "maxrss_raw": 7,
                         "peak_rss_bytes": 7 * multiplier, "user_seconds": 0,
                         "system_seconds": 0, "minor_faults": 0, "major_faults": 0,
                         "voluntary_context_switches": 0, "involuntary_context_switches": 0,
                         "native_exit_status": exit_status, "native_signal": native_signal,
                         "exec_errno": 0}

                def dishonest_supervisor(*args, **kwargs):
                    kwargs["stderr"].write((bench.RUSAGE_MARKER + json.dumps(usage) + "\n").encode())
                    return argparse.Namespace(returncode=0, wait=lambda timeout: 0)

                with patch.object(bench.subprocess, "Popen", side_effect=dishonest_supervisor):
                    with patch.object(bench, "resource_guard", return_value={}):
                        row = bench.measure(["unexecuted-native"], 1, ".", "unexecuted-helper")
                self.assertIn("did not propagate", row["measurement_error"])
                self.assertEqual(row["exit_code"], 0)


if __name__ == "__main__":
    unittest.main()
