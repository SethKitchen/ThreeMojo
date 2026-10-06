# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Prepare, build, and measure serial, paired #505 image-loading experiments.

Subcommands never run implicitly. 'stride' writes a source-only copy. 'build'
compiles serially. 'run' invokes already built programs, one process at a time.
A low-RSS C supervisor obtains the native child's wait4 usage. Python's
immediate-child maxRSS is never used as decoder memory evidence.
"""

import argparse
from collections import defaultdict
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
BASELINE_REVISION = "51b4424ceef57fef1f8a5e787c583126f999baf5"
IGNORED = {".git", ".venv", ".cache", "build", "__pycache__"}
RUSAGE_MARKER = "THREEMOJO_RUSAGE_V1 "
MIN_AVAILABLE_BYTES = 3 * 1024**3
MIN_DISK_BYTES = 2 * 1024**3
CHECK_FIELDS = ("textures", "base_bytes", "payload_bytes", "mip_levels",
                "all_fnv64", "base_fnv64", "shape_fnv64")


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def source_files(root):
    return sorted(path for path in root.rglob("*.mojo")
                  if not IGNORED.intersection(path.relative_to(root).parts))


def source_record(root):
    root = Path(root).resolve()
    files = {path.relative_to(root).as_posix(): sha(path) for path in source_files(root)}
    if not files:
        raise ValueError(f"No Mojo sources: {root}")
    digest = hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return {"root": str(root), "mojo_tree_sha256": digest, "files": files}


def named(values):
    result = {}
    for value in values:
        label, separator, target = value.partition("=")
        if not separator or not label or not target or label in result:
            raise ValueError(f"Expected unique LABEL=VALUE: {value}")
        if not label.replace("_", "").replace("-", "").isalnum():
            raise ValueError(f"Unsafe label: {label}")
        result[label] = target
    return result


def prepare_stride(args):
    source = args.source.resolve()
    destination = args.destination.resolve()
    if destination.exists():
        raise FileExistsError("Stride destination must be new")
    before = source_record(source)
    destination.mkdir(parents=True)
    for path in source_files(source):
        target = destination / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    module = destination / "loaders/image_batch.mojo"
    original = module.read_text(encoding="utf-8")
    start = original.index("def _claim_decode(")
    end = original.index("\ndef decode_textures[", start)
    worker = '''async def _decode_worker[
    Source: TextureDecodeSource
](
    source: Pointer[Source, ImmutAnyOrigin],
    first: Int,
    stride: Int,
    count: Int,
    results: MutPointer[Optional[Texture], MutAnyOrigin],
    errors: MutPointer[Optional[String], MutAnyOrigin],
):
    """Experimental fixed-stride worker; deliberately no dynamic claims."""
    for index in range(first, count, stride):
        try:
            results[unsafe_offset=index] = source[].decode(index)
        except e:
            errors[unsafe_offset=index] = String(e)

'''
    modified = original[:start] + worker + original[end:]
    replacements = {
        "from std.atomic import Atomic\n": "",
        "    var next: Int64 = 0\n": "    var active = decode_batch_size(count, workers)\n",
        "    for _ in range(decode_batch_size(count, workers)):\n": "    for worker in range(active):\n",
        "                Pointer(to=next).unsafe_origin_cast[MutAnyOrigin](),\n":
            "                worker,\n                active,\n",
        "    _ = next\n": "    _ = active\n",
        "Decode indexed images with a bounded, work-conserving queue.":
            "Decode indexed images with experimental fixed-stride workers.",
        "    One worker reads one image at a time. A free worker claims the next\n"
        "    image without waiting for slower workers. Inputs must stay fixed for\n":
            "    One worker reads its fixed source-index stride one image at a time.\n"
            "    It cannot take another worker's jobs. Inputs must stay fixed for\n",
    }
    for old, new in replacements.items():
        if modified.count(old) != 1:
            raise ValueError(f"Candidate scheduler changed; inspect replacement: {old!r}")
        modified = modified.replace(old, new)
    module.write_text(modified, encoding="utf-8")
    after_source = source_record(source)
    if before != after_source:
        raise RuntimeError("Candidate changed during stride snapshot; create a new snapshot")
    after = source_record(destination)
    changed = [path for path in before["files"] if before["files"][path] != after["files"][path]]
    if changed != ["loaders/image_batch.mojo"]:
        raise RuntimeError(f"Unexpected stride source changes: {changed}")
    record = {"schema": 1, "created_utc": now(), "kind": "experimental fixed-stride persistent workers",
              "candidate": before, "stride": after, "changed_files": changed,
              "note": "Benchmark control only; not a proposed production scheduler."}
    write_json(destination / "stride-provenance.json", record)
    print(json.dumps({"stride_source": str(destination), "sha256": after["mojo_tree_sha256"]}))


def resource_guard(directory):
    """Stop before a launch when memory or workspace free space is unsafe."""
    free_disk = shutil.disk_usage(directory).free
    meminfo = read_optional("/proc/meminfo")
    available = None
    if meminfo:
        for line in meminfo.splitlines():
            if line.startswith("MemAvailable:"):
                available = int(line.split()[1]) * 1024
                break
    if sys.platform.startswith("linux") and available is None:
        raise RuntimeError("Cannot verify MemAvailable before launching a process")
    if available is not None and available < MIN_AVAILABLE_BYTES:
        raise RuntimeError(f"Resource guard: MemAvailable {available / 2**30:.2f} GiB is below 3 GiB")
    if free_disk < MIN_DISK_BYTES:
        raise RuntimeError(f"Resource guard: workspace free {free_disk / 2**30:.2f} GiB is below 2 GiB")
    return {"mem_available_bytes": available, "workspace_free_bytes": free_disk,
            "minimum_mem_available_bytes": MIN_AVAILABLE_BYTES,
            "minimum_workspace_free_bytes": MIN_DISK_BYTES}



def build_helper(compiler, destination, timeout):
    """Compile and hash the small native RSS supervisor in the parent lane."""
    compiler = Path(compiler).resolve()
    destination = Path(destination).resolve()
    source = destination / "image_decode_rusage.c"
    binary = destination / "image_decode_rusage"
    if source.exists() or binary.exists():
        raise FileExistsError("RSS helper destination already exists; use a fresh build directory")
    shutil.copy2(HERE / "image_decode_rusage.c", source)
    resource_guard(destination)
    version = subprocess.run([str(compiler), "--version"], check=True, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.strip()
    command = [str(compiler), "-O2", "-std=c11", "-Wall", "-Wextra", "-Werror",
               str(source), "-o", str(binary)]
    launch_resources = resource_guard(destination)
    with (destination / "rusage.build.log").open("w") as log:
        subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
    return {"binary": str(binary), "binary_sha256": sha(binary),
            "source": str(source), "source_sha256": sha(source), "command": command,
            "compiler": {"path": str(compiler), "version": version},
            "launch_resources": launch_resources,
            "protocol": "THREEMOJO_RUSAGE_V1", "created_utc": now()}


def build_rusage(args):
    """Add a verified helper build to an existing native build record."""
    path = args.build.resolve()
    record = read_json(path)
    if record.get("status") != "complete":
        raise ValueError("An existing completed native build record is required")
    if "rusage_helper" in record:
        raise ValueError("Build record already has an RSS helper")
    for info in record["variants"].values():
        if sha(info["binary"]) != info["binary_sha256"]:
            raise RuntimeError("Native binary changed since its build record")
    record["rusage_helper"] = build_helper(args.cc, path.parent, args.timeout)
    record["rss_harness_updated_utc"] = now()
    write_json(path, record)
    print("RSS_HELPER", record["rusage_helper"]["binary"])


def build(args):
    sources = named(args.source)
    revisions = named(args.revision)
    destination = args.destination.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    driver = destination / "image_decode.mojo"
    shutil.copy2(HERE / "image_decode.mojo", driver)
    compiler = args.mojo.resolve()
    resource_guard(destination)
    version = subprocess.run([str(compiler), "--version"], check=True, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.strip()
    record = {"schema": 1, "status": "building", "created_utc": now(), "toolchain": {"path": str(compiler), "version": version},
              "driver_sha256": sha(driver), "runner_sha256": sha(__file__), "variants": {}}
    write_json(destination / "build.json", record)
    record["rusage_helper"] = build_helper(args.cc, destination, args.timeout)
    write_json(destination / "build.json", record)
    flags = ["--Werror", *(args.flag or ["-O3"])]
    for label, root in sources.items():
        before = source_record(root)
        executable = destination / label
        command = [str(compiler), "build", *flags, "-I", before["root"],
                   str(driver), "-o", str(executable)]
        print("BUILD", label, " ".join(command), flush=True)
        launch_resources = resource_guard(destination)
        started = time.monotonic()
        with (destination / f"{label}.build.log").open("w") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                    cwd=before["root"], timeout=args.timeout)
        after = source_record(root)
        if before != after:
            raise RuntimeError(f"Source changed during {label} build; record rejected")
        if result.returncode:
            raise RuntimeError(f"Build failed: {destination / (label + '.build.log')}")
        record["variants"][label] = {"binary": str(executable), "binary_sha256": sha(executable),
                                     "source": before, "command": command,
                                     "build_seconds": time.monotonic() - started,
                                     "launch_resources": launch_resources,
                                     "revision": revisions.get(label, "uncommitted source snapshot")}
        write_json(destination / "build.json", record)
    if "dynamic" in record["variants"] and "stride" in record["variants"]:
        dynamic = record["variants"]["dynamic"]["source"]["files"]
        stride = record["variants"]["stride"]["source"]["files"]
        if set(dynamic) != set(stride):
            raise RuntimeError("Dynamic and stride file lists differ; refresh stride from the final candidate")
        changed = [path for path in dynamic if dynamic[path] != stride[path]]
        if changed != ["loaders/image_batch.mojo"]:
            raise RuntimeError(f"Experimental control differs outside its scheduler: {changed}; refresh stride")
    record["status"] = "complete"
    write_json(destination / "build.json", record)
    print("BUILD_RECORD", destination / "build.json")


def read_optional(path):
    try:
        return Path(path).read_text(encoding="utf-8").strip()
    except OSError:
        return None


def host_record():
    cpuinfo = read_optional("/proc/cpuinfo")
    models = sorted({line.split(":", 1)[1].strip() for line in (cpuinfo or "").splitlines()
                     if line.startswith(("model name", "Hardware"))})
    return {"platform": platform.platform(), "machine": platform.machine(), "python": sys.version,
            "processor": platform.processor(), "cpu_models": models,
            "logical_cpu_count": os.cpu_count(),
            "affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
            "load_average": os.getloadavg() if hasattr(os, "getloadavg") else None,
            "meminfo": read_optional("/proc/meminfo"),
            "cgroup_cpu_max": read_optional("/sys/fs/cgroup/cpu.max"),
            "cgroup_memory_max": read_optional("/sys/fs/cgroup/memory.max"),
            "cgroup_cpuset": read_optional("/sys/fs/cgroup/cpuset.cpus.effective"),
            "cpu0_governor": read_optional("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"),
            "runtime_environment": {key: os.environ[key] for key in (
                "MODULAR_NUM_THREADS", "MOJO_NUM_THREADS", "OMP_NUM_THREADS",
                "OMP_THREAD_LIMIT", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
                "MODULAR_THREAD_BUSY_WAIT_US") if key in os.environ}}


def parse_rusage(stderr):
    """Read one exact supervisor record and retain the native stderr text."""
    lines = stderr.splitlines(keepends=True)
    markers = [line for line in lines if line.startswith(RUSAGE_MARKER)]
    if len(markers) != 1:
        raise ValueError("Expected exactly one RSS supervisor marker")
    result = json.loads(markers[0][len(RUSAGE_MARKER):])
    expected = "KiB" if sys.platform.startswith("linux") else "bytes" if sys.platform == "darwin" else None
    if expected is None or result.get("rss_unit") != expected or result.get("schema") != 1:
        raise ValueError("Unsupported RSS supervisor platform, units, or schema")
    multiplier = 1024 if expected == "KiB" else 1
    if result["maxrss_raw"] < 0 or result["peak_rss_bytes"] != result["maxrss_raw"] * multiplier:
        raise ValueError("Invalid RSS supervisor unit conversion")
    return result, "".join(line for line in lines if not line.startswith(RUSAGE_MARKER))


def measure(command, timeout, directory, helper):
    """Measure the C supervisor's child, never Python's immediate-child RSS."""
    launch_resources = resource_guard(directory)
    wrapper_command = [str(Path(helper).resolve()), "--", *command]
    with tempfile.TemporaryFile() as output, tempfile.TemporaryFile() as errors:
        started = time.monotonic_ns()
        child = subprocess.Popen(wrapper_command, stdout=output, stderr=errors,
                                 cwd=directory, start_new_session=True)
        timed_out = False
        try:
            child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
        except BaseException:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
            raise
        wall_ns = time.monotonic_ns() - started
        output.seek(0)
        errors.seek(0)
        full_stderr = errors.read().decode("utf-8", errors="replace")
        result = {"command": command, "native_command": command,
                  "wrapper_command": wrapper_command, "exit_code": child.returncode,
                  "timed_out": timed_out, "launch_resources": launch_resources,
                  "wall_ns": wall_ns, "peak_rss_bytes": None,
                  "stdout": output.read().decode("utf-8", errors="replace"),
                  "stderr": full_stderr, "wrapper_stderr": full_stderr,
                  "measurement_error": None}
        try:
            usage, native_stderr = parse_rusage(full_stderr)
            result["rusage"] = usage
            result["stderr"] = native_stderr
            for key in ("peak_rss_bytes", "user_seconds", "system_seconds",
                        "minor_faults", "major_faults", "voluntary_context_switches",
                        "involuntary_context_switches"):
                result[key] = usage[key]
            native_code = -usage["native_signal"] if usage["native_signal"] else usage["native_exit_status"]
            result["native_exit_code"] = native_code
            if native_code != child.returncode:
                raise ValueError("Supervisor did not propagate the native exit/signal status")
            if usage["exec_errno"]:
                raise ValueError("Native exec failed with errno " + str(usage["exec_errno"]))
        except (ValueError, KeyError, TypeError) as error:
            result["measurement_error"] = str(error)
        return result


def parse_output(stdout):
    lines = [line for line in stdout.splitlines() if line.startswith("result ")]
    if len(lines) != 1:
        raise ValueError("Expected exactly one native result line")
    parts = lines[0].split()[1:]
    if len(parts) % 2:
        raise ValueError("Malformed native key/value result")
    result = dict(zip(parts[::2], parts[1::2]))
    if len(result) * 2 != len(parts):
        raise ValueError("Duplicate native output keys")
    return {key: value if key == "api" else int(value) for key, value in result.items()}


def distribution(values):
    middle = statistics.median(values)
    return {"n": len(values), "median": middle, "min": min(values), "max": max(values),
            "mad": statistics.median(abs(value - middle) for value in values)}


def summarize(rows, baseline):
    groups = defaultdict(list)
    pairs = defaultdict(dict)
    for row in rows:
        key = (row["dataset"], row["api"], row["workers"], row["variant"])
        groups[key].append(row)
        pairs[(row["dataset"], row["api"], row["workers"], row["repetition"])][row["variant"]] = row
    result = []
    for (dataset, api, workers, variant), group in sorted(groups.items()):
        item = {"dataset": dataset, "api": api, "workers": workers, "variant": variant,
                "load_ns": distribution([r["native"]["load_ns"] for r in group]),
                "peak_rss_bytes": distribution([r["peak_rss_bytes"] for r in group]),
                "images_per_second": distribution([r["native"]["textures"] * 1e9 / r["native"]["load_ns"]
                                                   for r in group]),
                "base_megapixels_per_second": distribution([r["native"]["base_bytes"] * 250 / r["native"]["load_ns"]
                                                            for r in group]),
                "runtime_parallelism": sorted({r["native"]["runtime_parallelism"] for r in group}),
                "checksums": {field: group[0]["native"][field] for field in CHECK_FIELDS}}
        speedups, rss_ratios = [], []
        for row in group:
            pair = pairs[(dataset, api, workers, row["repetition"])]
            if baseline in pair:
                base = pair[baseline]
                speedups.append(base["native"]["load_ns"] / row["native"]["load_ns"])
                rss_ratios.append(row["peak_rss_bytes"] / base["peak_rss_bytes"])
        if speedups:
            item["paired_speedup_vs_" + baseline] = distribution(speedups)
            item["paired_rss_ratio_vs_" + baseline] = distribution(rss_ratios)
        result.append(item)
    return result


def run(args):
    build_record = read_json(args.build)
    if build_record.get("status") != "complete":
        raise ValueError("Build record is incomplete or failed")
    fixtures = read_json(args.fixtures / "fixtures.json")
    variants = build_record["variants"]
    helper_record = build_record.get("rusage_helper")
    if not helper_record:
        raise ValueError("RSS helper missing; run build-rusage before measuring. Old smoke RSS is invalid.")
    helper = helper_record["binary"]
    if sha(helper) != helper_record["binary_sha256"]:
        raise RuntimeError("RSS supervisor binary changed since its build record")
    if args.baseline not in variants or len(variants) < 2:
        raise ValueError("Need a named baseline and at least one comparison variant")
    destination = args.destination.resolve()
    destination.mkdir(parents=True, exist_ok=False)
    if args.repetitions < 1:
        raise ValueError("repetitions must be positive")
    for label, info in variants.items():
        if sha(info["binary"]) != info["binary_sha256"]:
            raise RuntimeError(f"Binary changed since build: {label}")
    datasets = {entry["name"]: entry for entry in fixtures["datasets"]}
    selected = args.datasets or list(datasets)
    for name in selected:
        for entry in datasets[name]["files"]:
            path = args.fixtures / datasets[name]["path"] / entry["path"]
            if path.stat().st_size != entry["bytes"] or sha(path) != entry["sha256"]:
                raise RuntimeError(f"Fixture changed: {path}")
    workers = args.workers
    cases = []
    for name in selected:
        choices = workers or [1, 2, 4, datasets[name]["count"] + 1]
        for worker in dict.fromkeys(choices):
            if worker < 1:
                raise ValueError("worker counts must be positive")
            cases.extend((name, api, worker) for api in args.apis)
    metadata = {"schema": 1, "started_utc": now(), "status": "running", "host": host_record(),
                "build": build_record, "fixtures_manifest_sha256": sha(args.fixtures / "fixtures.json"),
                "fixtures": fixtures, "repetitions": args.repetitions, "seed": args.seed,
                "runner_sha256": sha(__file__), "requested_variants": list(variants),
                "measurement": "low-RSS C fork/exec/wait4 supervisor; one fresh native child per row; serial paired runs",
                "invalid_prior_method": "Direct Python-child wait4 RSS can retain parent heap high-water floors; do not cite old smoke RSS",
                "timer_scope": "read_gltf including JSON/geometry, or preload excluding AssetRegistry.open",
                "page_cache": "all case inputs read into OS page cache before each paired trial",
                "runtime": "parallelism_level queried before timing; no task/decode warm-up",
                "rss_scope": "entire process including setup and post-timer checksums, not isolated scratch",
                "planned_rows": len(cases) * args.repetitions * len(variants)}
    write_json(destination / "metadata.json", metadata)
    rows, oracles, global_shapes = [], {}, {}
    labels = list(variants)
    rng = random.Random(args.seed)
    try:
        with (destination / "raw.jsonl").open("w", encoding="utf-8") as raw:
            for repetition in range(args.repetitions):
                order = list(cases)
                rng.shuffle(order)
                for case_index, (dataset, api, worker) in enumerate(order):
                    fixture = datasets[dataset]
                    folder = (args.fixtures / fixture["path"]).resolve()
                    # Explicit warm-page-cache experiment. The native process is fresh.
                    for entry in fixture["files"]:
                        with (folder / entry["path"]).open("rb") as stream:
                            while stream.read(256 * 1024):
                                pass
                    # With three variants and three trials every variant leads once.
                    offset = (repetition + cases.index((dataset, api, worker))) % len(labels)
                    variant_order = labels[offset:] + labels[:offset]
                    for variant in variant_order:
                        command = [variants[variant]["binary"], str(folder), api, str(worker)]
                        row = measure(command, args.timeout, folder, helper)
                        row.update({"dataset": dataset, "api": api, "workers": worker,
                                    "variant": variant, "repetition": repetition,
                                    "recorded_utc": now(), "case_order": case_index,
                                    "variant_order": variant_order.index(variant)})
                        if row["exit_code"] or row["timed_out"] or row["measurement_error"]:
                            raw.write(json.dumps(row) + "\n")
                            raw.flush()
                            raise RuntimeError(f"Native process failed: {dataset}/{api}/{worker}/{variant}")
                        # Save evidence before validation, including a malformed result.
                        raw.write(json.dumps(row) + "\n")
                        raw.flush()
                        row["native"] = parse_output(row["stdout"])
                        native = row["native"]
                        if native["api"] != api or native["workers"] != worker or native["load_ns"] <= 0:
                            raise RuntimeError("Native result does not match the request")
                        for key, expected in fixture["expected"].items():
                            if native[key] != expected:
                                raise RuntimeError(f"Fixture oracle failed: {dataset} {key}: {native[key]} != {expected}")
                        signature = tuple(native[key] for key in CHECK_FIELDS)
                        key = (dataset, api)
                        if key in oracles and oracles[key] != signature:
                            raise RuntimeError(f"Output differs across variants/workers/trials: {key}")
                        oracles[key] = signature
                        # Opaque albedo fixtures have equal pixel/mip output in both APIs.
                        if dataset in global_shapes and global_shapes[dataset] != signature:
                            raise RuntimeError(f"glTF/registry pixel or mip outputs differ: {dataset}")
                        global_shapes[dataset] = signature
                        rows.append(row)
                        with (destination / "validated.jsonl").open("a", encoding="utf-8") as validated:
                            validated.write(json.dumps(row) + "\n")
                        print(f"{len(rows)}/{metadata['planned_rows']} {dataset} {api} w={worker} "
                              f"{variant} {native['load_ns'] / 1e6:.3f} ms "
                              f"RSS={row['peak_rss_bytes'] / 2**20:.2f} MiB", flush=True)
                        write_json(destination / "summary.json", summarize(rows, args.baseline))
        metadata["status"] = "complete"
    except BaseException as error:
        metadata["status"] = "failed"
        metadata["error"] = str(error)
        raise
    finally:
        metadata["finished_utc"] = now()
        metadata["completed_rows"] = len(rows)
        metadata["host_after"] = host_record()
        write_json(destination / "metadata.json", metadata)
    print("RESULTS", destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    stride = sub.add_parser("stride", help="write a source-only experimental candidate copy")
    stride.add_argument("--source", type=Path, required=True)
    stride.add_argument("--destination", type=Path, required=True)
    stride.set_defaults(function=prepare_stride)
    compile_parser = sub.add_parser("build", help="parent-owned serial compilation lane")
    compile_parser.add_argument("--mojo", type=Path, required=True)
    compile_parser.add_argument("--cc", type=Path, default=Path("/usr/bin/cc"))
    compile_parser.add_argument("--source", action="append", required=True, metavar="LABEL=PATH")
    compile_parser.add_argument("--revision", action="append", default=[], metavar="LABEL=REVISION")
    compile_parser.add_argument("--destination", type=Path, required=True)
    compile_parser.add_argument("--flag", action="append", help="compiler option; use --flag=-O3; --Werror is always added")
    compile_parser.add_argument("--timeout", type=float, default=1800)
    compile_parser.set_defaults(function=build)
    helper_parser = sub.add_parser("build-rusage", help="compile the RSS helper for existing native binaries")
    helper_parser.add_argument("--build", type=Path, required=True)
    helper_parser.add_argument("--cc", type=Path, default=Path("/usr/bin/cc"))
    helper_parser.add_argument("--timeout", type=float, default=120)
    helper_parser.set_defaults(function=build_rusage)
    measure_parser = sub.add_parser("run", help="measure fresh binaries serially")
    measure_parser.add_argument("--build", type=Path, required=True)
    measure_parser.add_argument("--fixtures", type=Path, required=True)
    measure_parser.add_argument("--destination", type=Path, required=True)
    measure_parser.add_argument("--baseline", default="baseline")
    measure_parser.add_argument("--repetitions", type=int, default=3)
    measure_parser.add_argument("--workers", nargs="+", type=int)
    measure_parser.add_argument("--datasets", nargs="+")
    measure_parser.add_argument("--apis", nargs="+", choices=("gltf", "registry"), default=["gltf", "registry"])
    measure_parser.add_argument("--seed", type=int, default=505)
    measure_parser.add_argument("--timeout", type=float, default=120)
    measure_parser.set_defaults(function=run)
    args = parser.parse_args()
    args.function(args)


if __name__ == "__main__":
    main()
