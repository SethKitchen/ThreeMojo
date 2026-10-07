#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Time cataloged examples against three.js and, when present, Mojo 1.0."""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = json.loads((ROOT / "bench" / "catalog.json").read_text(encoding="utf-8"))
BUILD = ROOT / "bench" / "build"
SCRATCH = ROOT / "bench" / "scratch"
# One result file and one set of tables for each kind of host. A run on a
# Mac must not overwrite the Linux numbers, and the reverse.
PLATFORMS = {"linux": "Linux", "macos": "macOS"}


def this_platform() -> str:
    return "macos" if sys.platform == "darwin" else "linux"


def results_path(platform_key: str) -> Path:
    return ROOT / "bench" / f"results-{platform_key}.json"


WIKI = ROOT / "docs" / "wiki" / "Benchmarks.md"
THREEJS = ROOT / "bench" / "threejs"
TIME_BIN = "/usr/bin/time"
RSS_LINE = re.compile(r"^TIME_RSS (\S+) (\S+) (\S+)\s*$")


def which_mojo(default: Path) -> Path | None:
    if default.is_file():
        return default
    found = shutil.which("mojo")
    return Path(found) if found else None


def which_node() -> Path | None:
    home_node = Path.home() / "node" / "bin" / "node"
    if home_node.is_file():
        return home_node
    found = shutil.which("node")
    if found and "nvm4w" not in found and not found.endswith(".exe"):
        return Path(found)
    return None


def which_npm() -> Path | None:
    home_npm = Path.home() / "node" / "bin" / "npm"
    if home_npm.is_file():
        return home_npm
    found = shutil.which("npm")
    if found and "nvm4w" not in found and not found.endswith(".cmd"):
        return Path(found)
    return None


_GLES_DIR: Path | None = None
_GLES_LOOKED = False


def gles_dir() -> Path | None:
    """Return a directory that holds `libGLESv2.so.2`, or none.

    `webgl-node` loads that soname. Ubuntu keeps it in `libgles2`. A
    checkout without root can still fetch the dispatcher with
    `apt-get download`, which does not install it.
    """
    global _GLES_DIR, _GLES_LOOKED
    if _GLES_LOOKED:
        return _GLES_DIR
    _GLES_LOOKED = True
    names = ("libGLESv2.so.2", "libGLESv2.so.2.1.0")
    candidates = [
        THREEJS / "lib",
        Path.home() / "gles-lib",
        Path("/usr/lib/x86_64-linux-gnu"),
        Path("/usr/lib64"),
        Path("/usr/lib"),
    ]
    for folder in candidates:
        for name in names:
            if (folder / name).exists():
                link = folder / "libGLESv2.so.2"
                if not link.exists() and name != "libGLESv2.so.2":
                    try:
                        link.symlink_to(name)
                    except OSError:
                        continue
                _GLES_DIR = folder
                return folder
    if sys.platform != "linux":
        return None
    if shutil.which("apt-get") is None or shutil.which("dpkg-deb") is None:
        return None
    dest = THREEJS / "lib"
    dest.mkdir(parents=True, exist_ok=True)
    fetched = subprocess.run(
        ["apt-get", "download", "libgles2"],
        cwd=dest,
        capture_output=True,
        text=True,
        check=False,
    )
    if fetched.returncode != 0:
        return None
    debs = list(dest.glob("libgles2_*.deb"))
    if not debs:
        return None
    extracted = subprocess.run(
        ["dpkg-deb", "-x", str(debs[0]), str(dest / "extract")],
        capture_output=True,
        text=True,
        check=False,
    )
    if extracted.returncode != 0:
        return None
    found = list((dest / "extract").rglob("libGLESv2.so.*"))
    if not found:
        return None
    library = found[0]
    stored = dest / library.name
    if not stored.exists():
        stored.write_bytes(library.read_bytes())
    link = dest / "libGLESv2.so.2"
    if not link.exists():
        link.symlink_to(stored.name)
    _GLES_DIR = dest
    return dest


def node_env() -> dict[str, str]:
    node = which_node()
    env = {}
    if node:
        bindir = str(node.parent)
        env["PATH"] = bindir + os.pathsep + os.environ.get("PATH", "")
    folder = gles_dir()
    if folder is not None:
        current = os.environ.get("LD_LIBRARY_PATH", "")
        parts = [str(folder)]
        if current:
            parts.append(current)
        env["LD_LIBRARY_PATH"] = os.pathsep.join(parts)
    return env


def mojo_version(binary: Path) -> str:
    out = subprocess.run(
        [str(binary), "--version"],
        capture_output=True,
        text=True,
        check=False,
    )
    text = (out.stdout or out.stderr or "").strip().splitlines()
    return text[0] if text else "unknown"


def sysctl(name: str) -> str:
    out = subprocess.run(
        ["sysctl", "-n", name], capture_output=True, text=True, check=False
    )
    return out.stdout.strip() if out.returncode == 0 else ""


def cpu_name() -> str:
    """Return the processor's marketing name, with its core count on macOS.

    Linux names it in `/proc/cpuinfo`. macOS has no such file, and
    `platform.processor()` says only `arm`, so `sysctl` names it there.
    """
    if sys.platform == "darwin":
        brand = sysctl("machdep.cpu.brand_string") or platform.machine()
        cores = sysctl("hw.logicalcpu")
        return f"{brand}, {cores} cores" if cores else brand
    try:
        for line in Path("/proc/cpuinfo").read_text(encoding="utf-8").splitlines():
            if line.lower().startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or platform.machine()


def os_name() -> str:
    if sys.platform == "darwin":
        return f"macOS {platform.mac_ver()[0]} ({platform.machine()})"
    return f"{platform.system()} {platform.release()}"


def host_info(mojo11: Path | None, mojo10: Path | None) -> dict:
    cpu = cpu_name()
    node = which_node()
    node_ver = ""
    if node:
        node_ver = subprocess.run(
            [str(node), "--version"],
            capture_output=True,
            text=True,
            check=False,
            env={**os.environ, **node_env()},
        ).stdout.strip()
    return {
        "os": os_name(),
        "cpu": cpu,
        "python": sys.version.split()[0],
        "mojo_1_1": mojo_version(mojo11) if mojo11 else "",
        "mojo_1_0": mojo_version(mojo10) if mojo10 else "",
        "node": node_ver,
    }


BSD_REAL = re.compile(r"^\s*([0-9.]+)\s+real\b", re.MULTILINE)
BSD_RSS = re.compile(r"^\s*(\d+)\s+maximum resident set size")


def measure(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> dict:
    """Run cmd and return elapsed seconds, peak RSS in KiB, status and stderr.

    GNU time takes a format string; BSD time, which macOS ships, prints a
    fixed report under `-l` with the peak in bytes. Both are read here, so
    the page can be refreshed on either kind of machine.
    """
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    if Path(TIME_BIN).is_file():
        if sys.platform == "darwin":
            wrapped = [TIME_BIN, "-l", *cmd]
        else:
            wrapped = [TIME_BIN, "-f", "TIME_RSS %e %M %x", "--", *cmd]
        # The clock is this process's, to the microsecond: both `time`s
        # print the elapsed time to two decimals, which cannot tell a
        # ten-millisecond run from a nineteen-millisecond one. `time`
        # is kept for the peak resident set, which only it can report.
        started = time.perf_counter()
        proc = subprocess.run(
            wrapped,
            cwd=cwd,
            env=full_env,
            capture_output=True,
            text=True,
            check=False,
        )
        elapsed = round(time.perf_counter() - started, 4)
        combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
        if sys.platform == "darwin":
            rss = None
            for line in combined.splitlines():
                peak = BSD_RSS.match(line)
                if peak:
                    rss = int(peak.group(1)) // 1024
            if BSD_REAL.search(combined):
                return {
                    "ok": proc.returncode == 0,
                    "seconds": elapsed,
                    "rss_kib": rss,
                    "status": proc.returncode,
                    "output": combined,
                }
        for line in combined.splitlines():
            match = RSS_LINE.match(line.strip())
            if match:
                _, rss, status = match.groups()
                return {
                    "ok": int(float(status)) == 0,
                    "seconds": elapsed,
                    "rss_kib": int(float(rss)),
                    "status": int(float(status)),
                    "output": combined,
                }
        return {
            "ok": proc.returncode == 0,
            "seconds": None,
            "rss_kib": None,
            "status": proc.returncode,
            "output": combined,
        }

    started = time.perf_counter()
    proc = subprocess.run(
        cmd, cwd=cwd, env=full_env, capture_output=True, text=True, check=False
    )
    return {
        "ok": proc.returncode == 0,
        "seconds": time.perf_counter() - started,
        "rss_kib": None,
        "status": proc.returncode,
        "output": (proc.stdout or "") + "\n" + (proc.stderr or ""),
    }


def fmt_s(value: float | None) -> str:
    """Round a displayed duration so sub-tenth noise does not look exact."""
    if value is None:
        return "—"
    magnitude = abs(value)
    if magnitude >= 10:
        return f"{value:.1f}"
    if magnitude >= 0.1:
        return f"{value:.2f}"
    return f"{value:.3f}"


def fmt_mib(kib: int | None) -> str:
    if kib is None:
        return "—"
    return f"{kib / 1024:.0f}"


def fmt_ratio(value: float) -> str:
    if value >= 10:
        return f"{value:.0f}"
    if value >= 1:
        return f"{value:.1f}"
    return f"{value:.2f}"


# Lower is better. A 10% gap is a tie. A 30% gap is a large win.
TIE_RATIO = 0.10
WIN_LOT_RATIO = 0.30


def good_seconds(metric: dict | None) -> float | None:
    if not metric or not metric.get("ok"):
        return None
    value = metric.get("seconds")
    return value if isinstance(value, (int, float)) else None


def compare_pair(left: float | None, right: float | None) -> tuple[str, str]:
    if left is None or right is None:
        return "plain", "plain"
    if left <= 0 or right <= 0:
        return "plain", "plain"
    if left < right:
        gap = (right - left) / left
        if gap < TIE_RATIO:
            return "tie", "tie"
        if gap < WIN_LOT_RATIO:
            return "win_little", "plain"
        return "win_lot", "plain"
    if right < left:
        gap = (left - right) / right
        if gap < TIE_RATIO:
            return "tie", "tie"
        if gap < WIN_LOT_RATIO:
            return "plain", "win_little"
        return "plain", "win_lot"
    return "tie", "tie"


def winner_name(
    left: float | None, right: float | None, left_label: str, right_label: str
) -> str:
    """Name the faster side. A gap under 10% is a tie."""
    kind_l, kind_r = compare_pair(left, right)
    if kind_l == "tie":
        return "tie"
    if kind_l.startswith("win"):
        return left_label
    if kind_r.startswith("win"):
        return right_label
    return "—"


def median(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    mid = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2


def _tally(pairs: list[tuple[float, float]]) -> dict:
    """Count wins for the left value. Lower is better. Also keep right/left."""
    mojo = mojo_lot = other = other_lot = ties = 0
    ratios: list[float] = []
    for left, right in pairs:
        if left <= 0:
            continue
        ratios.append(right / left)
        kind_l, kind_r = compare_pair(left, right)
        if kind_l == "win_lot":
            mojo += 1
            mojo_lot += 1
        elif kind_l == "win_little":
            mojo += 1
        elif kind_r == "win_lot":
            other += 1
            other_lot += 1
        elif kind_r == "win_little":
            other += 1
        else:
            ties += 1
    return {
        "mojo": mojo,
        "mojo_lot": mojo_lot,
        "other": other,
        "other_lot": other_lot,
        "ties": ties,
        "ratio": median(ratios),
        "count": mojo + other + ties,
    }


def ensure_dirs() -> None:
    if BUILD.exists() and not BUILD.is_dir():
        BUILD.unlink()
    BUILD.mkdir(parents=True, exist_ok=True)
    SCRATCH.mkdir(parents=True, exist_ok=True)


_THREEJS_READY = False


def example_run_args(item: dict, dest: Path) -> tuple[list[str], Path]:
    if item.get("hardcoded_out"):
        work = SCRATCH / item["name"]
        (work / "out").mkdir(parents=True, exist_ok=True)
        return [], work
    args = []
    for token in item.get("args", ["DEST"]):
        args.append(str(dest) if token == "DEST" else token)
    return args, ROOT


def bench_compile(mojo: Path, src: Path, binary: Path) -> dict:
    ensure_dirs()
    binary.parent.mkdir(parents=True, exist_ok=True)
    if binary.exists():
        if binary.is_dir():
            shutil.rmtree(binary)
        else:
            binary.unlink()
    return measure(
        [str(mojo), "build", "-I", ".", "-o", str(binary), str(src)],
        cwd=ROOT,
    )


# How many times a built binary is run for one number. The first launch of
# a freshly built executable on macOS pays a system check of several hundred
# milliseconds that has nothing to do with the program, and any run can be
# disturbed; the fastest of a few is the program.
RUNS = 3


def read_payload(output: str) -> tuple[str, float | None, float | None]:
    """Return the backend, the frames and the import time a run printed.

    three.js and every ThreeMojo example print one JSON line. The frames are
    the draw loop alone, timed inside the process, so both sides leave out
    starting the process, building the scene and writing a file.
    """
    backend = ""
    frames_seconds = None
    import_seconds = None
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            backend = payload.get("backend", backend)
            if isinstance(payload.get("frames_ms"), (int, float)):
                frames_seconds = payload["frames_ms"] / 1000.0
            if isinstance(payload.get("import_ms"), (int, float)):
                import_seconds = payload["import_ms"] / 1000.0
    return backend, frames_seconds, import_seconds


def bench_run(binary: Path, args: list[str], cwd: Path) -> dict:
    """Run a built binary `RUNS` times and return the fastest run."""
    best = None
    for _ in range(RUNS):
        result = measure([str(binary), *args], cwd=cwd)
        if not result["ok"]:
            return result
        result["frames_seconds"] = read_payload(result["output"])[1]
        if best is None or (
            result["seconds"] is not None
            and (best["seconds"] is None or result["seconds"] < best["seconds"])
        ):
            best = result
    return best


def ensure_threejs() -> bool:
    global _THREEJS_READY
    if _THREEJS_READY:
        return True
    if which_node() is None:
        return False
    if (THREEJS / "node_modules" / "three").exists():
        _THREEJS_READY = True
        return True
    npm = which_npm()
    if npm is None:
        return False
    print("Installing bench/threejs packages...", flush=True)
    proc = subprocess.run(
        [str(npm), "install", "--omit=dev"],
        cwd=THREEJS,
        env={**os.environ, **node_env()},
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        print(proc.stdout)
        print(proc.stderr, file=sys.stderr)
        return False
    ready = (THREEJS / "node_modules" / "three").exists()
    _THREEJS_READY = ready
    return ready


def bench_threejs(name: str, backend_name: str) -> dict:
    if not ensure_threejs():
        return {
            "ok": False,
            "seconds": None,
            "rss_kib": None,
            "status": 127,
            "backend": "",
            "output": "node or npm is missing",
        }
    node = which_node()
    if node is None:
        return {
            "ok": False,
            "seconds": None,
            "rss_kib": None,
            "status": 127,
            "backend": "",
            "output": "node is missing",
        }
    result = None
    for _ in range(RUNS):
        run = measure(
            [str(node), str(THREEJS / "run.mjs"), name, backend_name],
            cwd=ROOT,
            env=node_env(),
        )
        if not run["ok"]:
            result = run
            break
        if result is None or (
            run["seconds"] is not None
            and (result["seconds"] is None or run["seconds"] < result["seconds"])
        ):
            result = run
    backend, frames_seconds, import_seconds = read_payload(result["output"])
    result["backend"] = backend
    # The frames alone and the import of three.js, timed inside the Node
    # process, so the table can show the drawing apart from the process.
    result["frames_seconds"] = frames_seconds
    result["import_seconds"] = import_seconds
    return result


def find_mojo10() -> Path | None:
    candidates = []
    env = os.environ.get("MOJO_1_0")
    if env:
        candidates.append(Path(env))
    candidates.append(ROOT / ".venv-mojo10" / "bin" / "mojo")
    candidates.append(Path.home() / ".venvs" / "mojo10" / "bin" / "mojo")
    for path in candidates:
        if path.is_file():
            return path
    return None


def bench_baselines(mojo: Path) -> dict:
    """Time a Mojo program that does nothing and a Node process that does
    nothing, so a reader can tell the process from the frames."""
    noop = BUILD / "noop"
    compiled = bench_compile(mojo, ROOT / "bench" / "noop.mojo", noop)
    mojo_run = (
        bench_run(noop, [], ROOT)
        if compiled["ok"] and noop.is_file()
        else {"ok": False, "seconds": None, "rss_kib": None, "status": 1}
    )
    node = which_node()
    node_run = {"ok": False, "seconds": None, "rss_kib": None, "status": 127}
    if node is not None:
        for _ in range(RUNS):
            run = measure([str(node), "-e", ""], ROOT, env=node_env())
            if not run["ok"]:
                node_run = run
                break
            if node_run["seconds"] is None or (
                run["seconds"] is not None and run["seconds"] < node_run["seconds"]
            ):
                node_run = run
    return {"mojo": mojo_run, "node": node_run}


def bench_probe(mojo: Path, src: Path, binary: Path) -> dict:
    compiled = bench_compile(mojo, src, binary)
    ran = (
        bench_run(binary, [], ROOT)
        if compiled["ok"] and binary.is_file()
        else {
            "ok": False,
            "seconds": None,
            "rss_kib": None,
            "status": compiled["status"],
            "output": compiled["output"],
        }
    )
    return {"compile": compiled, "run": ran}


def refused_reason(output: str) -> str:
    for line in output.splitlines():
        stripped = line.strip()
        if stripped and "Crashpad" not in stripped:
            return stripped[:120]
    return "refused"


def measurement_label(row: dict) -> str:
    """Show a recorded row date without upgrading legacy aggregate metadata."""
    date = row.get("measured_on")
    if not isinstance(date, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
        return "unknown"
    if row.get("measurement_date_source") != "direct":
        return f"unknown (legacy: {date})"
    return date


def require_same_measurement_host(previous: dict, host: dict) -> None:
    """Refuse partial refreshes that would relabel another host's results."""
    old = previous.get("host") if isinstance(previous, dict) else None
    if not isinstance(old, dict) or not all(
        isinstance(old.get(key), str)
        and old[key].strip().lower() not in ("", "unknown", "missing", "not installed")
        for key in ("cpu", "os", "mojo_1_1")
    ) or old != host:
        raise ValueError("Cannot merge results with different or missing host/toolchain metadata")


def merge_measurements(previous: dict, fresh: dict) -> dict:
    """Keep prior row dates and replace only the newly measured examples."""
    require_same_measurement_host(previous, fresh["host"])
    merged = dict(fresh)
    by_name = {}
    for original in previous.get("examples", []):
        row = dict(original)
        if "measured_on" not in row:
            row["measured_on"] = previous.get("generated_at")
            row["measurement_date_source"] = "legacy aggregate"
        by_name[row["name"]] = row
    for original in fresh["examples"]:
        row = dict(original)
        row["measured_on"] = fresh["generated_at"]
        row["measurement_date_source"] = "direct"
        by_name[row["name"]] = row
    merged["examples"] = [by_name[item["name"]] for item in CATALOG if item["name"] in by_name]
    merged["probe"] = previous.get("probe", {}) | fresh.get("probe", {})
    merged["baselines"] = previous.get("baselines", {}) | fresh.get("baselines", {})
    merged["threejs_webgl"] = any((row.get("threejs_webgl") or {}).get("ok") for row in merged["examples"])
    compared = [row["mojo10"] for row in merged["examples"] if row.get("mojo10")]
    merged["mojo10_total"] = len(compared)
    merged["mojo10_refused"] = sum(not row.get("compile", row).get("ok") for row in compared)
    return merged


def _draw_cells(row: dict, webgl_ok: bool) -> tuple[str, str, str, str, str, str]:
    """Return compile, three draw cells, the winner and Mojo RSS."""
    tm = row["threemojo"]
    flat = row.get("threejs_flat") or row.get("threejs") or {}
    web = row.get("threejs_webgl") or {}
    tm_ok = bool(tm["compile"].get("ok") and tm["run"].get("ok"))
    compile_s = fmt_s(tm["compile"].get("seconds")) if tm["compile"].get("ok") else "failed"
    tm_frames = tm["run"].get("frames_seconds") if tm_ok else None
    flat_frames = flat.get("frames_seconds") if flat.get("ok") else None
    web_frames = web.get("frames_seconds") if web.get("ok") else None
    if webgl_ok and web.get("ok") and web_frames is not None:
        rival_frames = web_frames
        rival_label = "WebGL"
    elif flat.get("ok") and flat_frames is not None:
        rival_frames = flat_frames
        rival_label = "cpu-flat"
    else:
        rival_frames = None
        rival_label = "WebGL"
    winner = winner_name(tm_frames, rival_frames, "Mojo", rival_label)
    rss = fmt_mib(tm["run"].get("rss_kib")) if tm_ok else "—"
    return (
        compile_s,
        fmt_s(tm_frames),
        fmt_s(flat_frames) if flat.get("ok") else "unavailable",
        fmt_s(web_frames) if web.get("ok") else "unavailable",
        winner,
        rss,
    )


def example_table(rows: list[dict], webgl_ok: bool, legacy_date: str | None = None) -> str:
    lines = [
        "| Example | Size | Frames | Compile (s) | Mojo draw (s) | cpu-flat draw (s) | WebGL draw (s) | Draw winner | Mojo RSS (MiB) | Measured |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for row in rows:
        compile_s, mojo_draw, flat_draw, web_draw, winner, rss = _draw_cells(row, webgl_ok)
        recorded = measurement_label(row)
        if recorded == "unknown" and isinstance(legacy_date, str):
            recorded = measurement_label(
                {"measured_on": legacy_date, "measurement_date_source": "legacy aggregate"}
            )
        lines.append(
            "| `{name}` | {w}×{h} | {frames} | {compile_s} | {mojo_draw} | {flat_draw} | {web_draw} | {winner} | {rss} | {recorded} |".format(
                name=row["name"],
                w=row["width"],
                h=row["height"],
                frames=row["frames"],
                compile_s=compile_s,
                mojo_draw=mojo_draw,
                flat_draw=flat_draw,
                web_draw=web_draw,
                winner=winner,
                rss=rss,
                recorded=recorded,
            )
        )
    lines.append("")
    lines.append("A legacy date is from an older aggregate file; its per-row measurement date is unknown.")
    lines.append("")
    lines.append("Draw time is the frame loop inside the process.")
    lines.append("A gap under 10% is a tie.")
    lines.append("cpu-flat is a flat color fill with a depth test.")
    if webgl_ok:
        lines.append("WebGL is the three.js draw used for the language comparison.")
    else:
        lines.append("WebGL did not load, so the draw winner uses cpu-flat.")
    return "\n".join(lines)


def _both_ran(left: dict | None, right: dict | None) -> bool:
    if not left or not right or "compile" not in right:
        return False
    left_ok = left.get("compile", {}).get("ok") and (left.get("run") or {}).get("ok")
    right_ok = right.get("compile", {}).get("ok") and (right.get("run") or {}).get("ok")
    return bool(left_ok and right_ok)


def mojo10_row(name: str, left: dict | None, right: dict | None) -> str:
    left_c = good_seconds((left or {}).get("compile"))
    right_c = good_seconds((right or {}).get("compile"))
    left_r = good_seconds((left or {}).get("run"))
    right_r = good_seconds((right or {}).get("run"))
    return (
        f"| `{name}` | {fmt_s(left_c)} | {fmt_s(right_c)} | "
        f"{winner_name(left_c, right_c, '1.1', '1.0')} | "
        f"{fmt_s(left_r)} | {fmt_s(right_r)} | "
        f"{winner_name(left_r, right_r, '1.1', '1.0')} |"
    )


def mojo10_table(probe11: dict, probe10: dict | None, examples: list[dict]) -> str:
    lines = [
        "| Program | 1.1 compile (s) | 1.0 compile (s) | Compile winner | 1.1 run (s) | 1.0 run (s) | Run winner |",
        "|---|---|---|---|---|---|---|",
    ]
    ran = 0
    refused = 0
    if _both_ran(probe11, probe10):
        lines.append(mojo10_row("probe", probe11, probe10))
        ran += 1
    elif probe10 is None:
        lines.append("| `probe` | — | not installed | — | — | — | — |")
    else:
        refused += 1
    for row in examples:
        if _both_ran(row.get("threemojo"), row.get("mojo10")):
            lines.append(mojo10_row(row["name"], row["threemojo"], row.get("mojo10")))
            ran += 1
        elif row.get("mojo10"):
            refused += 1
    lines.append("")
    lines.append(f"Programs in this table: {ran}.")
    lines.append(f"Refused catalog rows: {refused}.")
    lines.append("A refused compile is not a faster compile.")
    lines.append("Those rows stay out of this table.")
    return "\n".join(lines)


def _frame_pairs(rows: list[dict], key: str) -> list[tuple[float, float]]:
    pairs = []
    for row in rows:
        tm = row["threemojo"]["run"]
        other = row.get(key) or {}
        left = tm.get("frames_seconds") if tm.get("ok") else None
        right = other.get("frames_seconds") if other.get("ok") else None
        if isinstance(left, (int, float)) and isinstance(right, (int, float)):
            pairs.append((float(left), float(right)))
    return pairs


def _seconds(metric: dict | None) -> float | None:
    value = good_seconds(metric)
    return float(value) if isinstance(value, (int, float)) else None


def score_report(payload: dict, platform_key: str) -> str:
    """State who wins, in short sentences, without a colored cell per number."""
    rows = payload.get("examples") or []
    title = PLATFORMS.get(platform_key, platform_key)
    lines = [f"### {title}", ""]
    webgl_ok = bool(payload.get("threejs_webgl"))
    language_key = "threejs_webgl" if webgl_ok else "threejs_flat"
    language_name = "WebGL" if webgl_ok else "cpu-flat"
    language = _tally(_frame_pairs(rows, language_key))
    if language["count"] == 0:
        lines.append("This file has no ThreeMojo draw times.")
        lines.append("The draw winner stays blank until the next measurement.")
    else:
        lines.append(
            f"{language_name} is the language comparison on this host."
        )
        if language["mojo"]:
            lines.append(
                f"ThreeMojo wins {language['mojo']} draws, {language['mojo_lot']} of them by 30% or more."
            )
        if language["other"]:
            lines.append(
                f"{language_name} wins {language['other']} draws, {language['other_lot']} of them by 30% or more."
            )
        if language["ties"] == 1:
            lines.append("1 draw is within 10% and counts as a tie.")
        elif language["ties"]:
            lines.append(f"{language['ties']} draws are within 10% and count as ties.")
        if language["ratio"] is not None:
            lines.append(
                f"The median {language_name} draw takes {fmt_ratio(language['ratio'])} times the ThreeMojo draw."
            )
    lines.append("")
    flat = _tally(_frame_pairs(rows, "threejs_flat"))
    if flat["count"] and language_key != "threejs_flat":
        lines.append("cpu-flat is a flat color fill. It is not the same work.")
        if flat["ratio"] is not None:
            lines.append(
                f"The median cpu-flat draw takes {fmt_ratio(flat['ratio'])} times the ThreeMojo draw."
            )
        lines.append("")
    mojo_rss = []
    web_rss = []
    mojo_lower = 0
    rss_compared = 0
    mojo_run = []
    web_run = []
    compiles = []
    for row in rows:
        tm = row["threemojo"]
        if tm["compile"].get("ok"):
            seconds = _seconds(tm["compile"])
            if seconds is not None:
                compiles.append(seconds)
        if tm["run"].get("ok"):
            seconds = _seconds(tm["run"])
            if seconds is not None:
                mojo_run.append(seconds)
            kib = tm["run"].get("rss_kib")
            if isinstance(kib, (int, float)):
                mojo_rss.append(kib / 1024.0)
        rival = row.get(language_key) or {}
        if rival.get("ok") and tm["run"].get("ok"):
            left = tm["run"].get("rss_kib")
            right = rival.get("rss_kib")
            if isinstance(left, (int, float)) and isinstance(right, (int, float)):
                rss_compared += 1
                if left < right:
                    mojo_lower += 1
            rival_seconds = _seconds(rival)
            if rival_seconds is not None:
                web_run.append(rival_seconds)
            if isinstance(right, (int, float)):
                web_rss.append(right / 1024.0)
    if rss_compared:
        lines.append(
            f"ThreeMojo uses less memory on {mojo_lower} of {rss_compared} examples."
        )
    mojo_med = median(mojo_rss)
    web_med = median(web_rss)
    if mojo_med is not None and web_med is not None:
        lines.append(
            f"The median resident set is {mojo_med:.0f} MiB for ThreeMojo and {web_med:.0f} MiB for {language_name}."
        )
    elif mojo_med is not None:
        lines.append(f"The median ThreeMojo resident set is {mojo_med:.0f} MiB.")
    lines.append("")
    lines.append("Whole-process time includes startup and writing the image.")
    if median(mojo_run) is not None:
        lines.append(f"The median ThreeMojo process takes {fmt_s(median(mojo_run))} s.")
    if median(web_run) is not None:
        lines.append(
            f"The median {language_name} process takes {fmt_s(median(web_run))} s."
        )
    baselines = payload.get("baselines") or {}
    mojo_base = _seconds(baselines.get("mojo"))
    node_base = _seconds(baselines.get("node"))
    if mojo_base is not None:
        lines.append(f"A Mojo program that does nothing takes {fmt_s(mojo_base)} s.")
    if node_base is not None:
        lines.append(f"A Node process that does nothing takes {fmt_s(node_base)} s.")
    if median(compiles) is not None:
        lines.append(f"The median Mojo 1.1 compile takes {fmt_s(median(compiles))} s.")
    lines.append("")
    version_pairs_c = []
    version_pairs_r = []
    refused = 0
    probe10 = (payload.get("probe") or {}).get("v10")
    probe11 = (payload.get("probe") or {}).get("v11")
    shared = []
    if probe11 or probe10:
        shared.append((probe11, probe10))
    for row in rows:
        if row.get("mojo10"):
            shared.append((row.get("threemojo"), row.get("mojo10")))
    if not any(item[1] for item in shared):
        lines.append("Mojo 1.0 is not installed on this host.")
    else:
        for left, right in shared:
            if _both_ran(left, right):
                version_pairs_c.append(
                    (good_seconds(left["compile"]), good_seconds(right["compile"]))
                )
                version_pairs_r.append(
                    (good_seconds(left["run"]), good_seconds(right["run"]))
                )
            elif right:
                refused += 1
        compile_tally = _tally(version_pairs_c)
        run_tally = _tally(version_pairs_r)
        lines.append(
            f"Mojo 1.0 runs {compile_tally['count']} programs."
        )
        lines.append(f"Refused programs: {refused}.")
        lines.append("A refused compile is not a faster compile.")
        if compile_tally["count"]:
            if compile_tally["mojo"]:
                lines.append(
                    f"On those programs, Mojo 1.1 compiles faster on {compile_tally['mojo']} of {compile_tally['count']}."
                )
            if compile_tally["other"]:
                lines.append(
                    f"Mojo 1.0 compiles faster on {compile_tally['other']} of {compile_tally['count']}."
                )
            if compile_tally["ties"] == 1:
                lines.append("1 compile is within 10%.")
            elif compile_tally["ties"]:
                lines.append(f"{compile_tally['ties']} compiles are within 10%.")
            lines.append("")
            if run_tally["mojo"]:
                lines.append(
                    f"Mojo 1.1 runs faster on {run_tally['mojo']} of {run_tally['count']}."
                )
            if run_tally["other"]:
                lines.append(
                    f"Mojo 1.0 runs faster on {run_tally['other']} of {run_tally['count']}."
                )
            if run_tally["ties"] == 1:
                lines.append("1 run is within 10%.")
            elif run_tally["ties"]:
                lines.append(f"{run_tally['ties']} runs are within 10%.")
    measured = len(rows)
    lines.append("")
    lines.append(f"The catalog lists {len(CATALOG)} examples.")
    lines.append(f"This host measures {measured} of them.")
    return "\n".join(lines)


def cross_report() -> str:
    """Compare the two saved hosts by median ratio. Dates stay visible."""
    paths = {key: results_path(key) for key in PLATFORMS}
    if not all(path.is_file() for path in paths.values()):
        return "One host has no results file. The machine comparison waits for that file."
    loaded = {
        key: json.loads(path.read_text(encoding="utf-8")) for key, path in paths.items()
    }
    linux_rows = {row["name"]: row for row in loaded["linux"].get("examples", [])}
    mac_rows = {row["name"]: row for row in loaded["macos"].get("examples", [])}
    run_ratios = []
    compile_ratios = []
    for name, linux in linux_rows.items():
        mac = mac_rows.get(name)
        if not mac:
            continue
        linux_run = _seconds(linux["threemojo"]["run"])
        mac_run = _seconds(mac["threemojo"]["run"])
        if linux_run and mac_run:
            run_ratios.append(linux_run / mac_run)
        linux_compile = _seconds(linux["threemojo"]["compile"])
        mac_compile = _seconds(mac["threemojo"]["compile"])
        if linux_compile and mac_compile:
            compile_ratios.append(linux_compile / mac_compile)
    run_med = median(run_ratios)
    compile_med = median(compile_ratios)
    linux_date = loaded["linux"].get("generated_at", "unknown")
    mac_date = loaded["macos"].get("generated_at", "unknown")
    lines = []
    if run_med is not None:
        lines.append(
            f"The macOS host runs the shared examples a median of {fmt_ratio(run_med)} times faster than the Linux host."
        )
    if compile_med is not None:
        lines.append(
            f"It compiles them a median of {fmt_ratio(compile_med)} times faster."
        )
    lines.append(f"The Linux date is {linux_date}. The macOS date is {mac_date}.")
    lines.append("The source can differ between those dates.")
    lines.append(f"The comparison uses {len(run_ratios)} shared examples.")
    return "\n".join(lines)


def replace_span(text: str, name: str, body: str) -> str:
    start = f"<!-- BENCH:{name} -->"
    end = f"<!-- /BENCH:{name} -->"
    # A lambda, so a backslash in a measured error is not read as a group.
    pattern = re.compile(
        re.escape(start) + r".*?" + re.escape(end),
        re.DOTALL,
    )
    block = f"{start}\n{body}\n{end}"
    if not pattern.search(text):
        raise SystemExit(f"Benchmarks.md is missing {start}")
    return pattern.sub(lambda _: block, text)


def slim_metric(metric: dict | None) -> dict | None:
    if metric is None:
        return None
    kept = {
        key: metric[key]
        for key in (
            "ok",
            "seconds",
            "rss_kib",
            "status",
            "backend",
            "frames_seconds",
            "import_seconds",
            "error",
        )
        if key in metric
    }
    if not metric.get("ok"):
        kept["error"] = refused_reason(metric.get("output", "") or metric.get("error", ""))
    return kept


def slim_payload(payload: dict) -> dict:
    slim = {
        "generated_at": payload["generated_at"],
        "host": payload["host"],
        "threejs_webgl": payload.get("threejs_webgl", False),
        "baselines": {
            key: slim_metric(value)
            for key, value in payload.get("baselines", {}).items()
        },
        "mojo10_refused": payload["mojo10_refused"],
        "mojo10_total": payload["mojo10_total"],
        "probe": {},
        "examples": [],
    }
    for key, value in payload["probe"].items():
        slim["probe"][key] = {
            "compile": slim_metric(value["compile"]),
            "run": slim_metric(value["run"]),
        }
    for row in payload["examples"]:
        slim["examples"].append(
            {
                "name": row["name"],
                "measured_on": row.get("measured_on", payload["generated_at"]),
                "measurement_date_source": row.get("measurement_date_source", "direct"),
                "width": row["width"],
                "height": row["height"],
                "frames": row["frames"],
                "threemojo": {
                    "compile": slim_metric(row["threemojo"]["compile"]),
                    "run": slim_metric(row["threemojo"]["run"]),
                },
                "threejs_flat": slim_metric(row.get("threejs_flat") or row.get("threejs") or {}),
                "threejs_webgl": slim_metric(row.get("threejs_webgl") or {}),
                "mojo10": (
                    {
                        "compile": slim_metric(row["mojo10"]["compile"]),
                        "run": slim_metric(row["mojo10"].get("run")),
                    }
                    if row.get("mojo10") and "compile" in (row.get("mojo10") or {})
                    else row.get("mojo10")
                ),
            }
        )
    return slim


def baseline_lines(payload: dict) -> list[str]:
    baselines = payload.get("baselines") or {}
    mojo = baselines.get("mojo") or {}
    node = baselines.get("node") or {}
    return [
        f"- A Mojo program that does nothing: `{fmt_s(good_seconds(mojo))}` s",
        f"- A Node process that does nothing: `{fmt_s(good_seconds(node))}` s",
    ]


def write_wiki(payload: dict, platform_key: str) -> None:
    host = payload["host"]
    host_md = "\n".join(
        [
            f"- Latest refresh: `{payload['generated_at']}`",
            f"- OS: {host['os']}",
            f"- CPU: {host['cpu']}",
            f"- Mojo 1.1: `{host['mojo_1_1'] or 'missing'}`",
            f"- Mojo 1.0: `{host['mojo_1_0'] or 'not installed'}`",
            f"- Node: `{host['node'] or 'missing'}`",
            "- three.js backends: "
            + (
                "`cpu-flat` and `webgl`"
                if payload.get("threejs_webgl")
                else "`cpu-flat` (`webgl` did not load)"
            ),
        ]
        + baseline_lines(payload)
    )
    text = WIKI.read_text(encoding="utf-8")
    text = replace_span(text, f"HOST:{platform_key}", host_md)
    text = replace_span(text, f"SCORE:{platform_key}", score_report(payload, platform_key))
    text = replace_span(text, "CROSS", cross_report())
    text = replace_span(
        text,
        f"EXAMPLES:{platform_key}",
        example_table(
            payload["examples"],
            bool(payload.get("threejs_webgl")),
            payload.get("generated_at"),
        ),
    )
    text = replace_span(
        text,
        f"MOJO10:{platform_key}",
        mojo10_table(
            payload["probe"].get("v11") or {},
            payload["probe"].get("v10"),
            payload["examples"],
        ),
    )
    WIKI.write_text(text, encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--only",
        help="Comma-separated example names to measure",
    )
    parser.add_argument(
        "--merge",
        action="store_true",
        help="Merge into this host's existing bench/results-<platform>.json",
    )
    parser.add_argument(
        "--skip-threejs",
        action="store_true",
        help="Skip the three.js runner",
    )
    parser.add_argument(
        "--skip-mojo10",
        action="store_true",
        help="Skip the Mojo 1.0 comparison",
    )
    parser.add_argument(
        "--write-wiki",
        action="store_true",
        default=True,
        help="Update docs/wiki/Benchmarks.md tables",
    )
    parser.add_argument(
        "--no-write-wiki",
        action="store_false",
        dest="write_wiki",
    )
    parser.add_argument(
        "--from-results",
        action="store_true",
        help="Rebuild wiki tables from bench/results-<platform>.json",
    )
    parser.add_argument(
        "--platform",
        choices=sorted(PLATFORMS),
        default=this_platform(),
        help="Which host's tables --from-results rebuilds (default: this host)",
    )
    return parser.parse_args()


def emit_tables(payload: dict, write_wiki_page: bool, platform_key: str) -> None:
    print(example_table(
        payload["examples"],
        bool(payload.get("threejs_webgl")),
        payload.get("generated_at"),
    ))
    print()
    print(
        mojo10_table(
            payload["probe"]["v11"],
            payload["probe"].get("v10"),
            payload["examples"],
        )
    )
    if write_wiki_page:
        write_wiki(payload, platform_key)
        print(f"\nUpdated {WIKI.relative_to(ROOT)}", flush=True)


def main() -> int:
    args = parse_args()
    results = results_path(args.platform)
    if args.from_results:
        if not results.is_file():
            print(
                f"{results.relative_to(ROOT)} is missing. Run the benches first.",
                file=sys.stderr,
            )
            return 1
        emit_tables(
            json.loads(results.read_text(encoding="utf-8")),
            args.write_wiki,
            args.platform,
        )
        return 0
    if args.platform != this_platform():
        print("--platform only applies with --from-results.", file=sys.stderr)
        return 2
    ensure_dirs()
    mojo11 = which_mojo(ROOT / ".venv" / "bin" / "mojo")
    if mojo11 is None:
        print("Mojo 1.1 is missing. Create .venv/ first.", file=sys.stderr)
        return 1
    mojo10 = None if args.skip_mojo10 else find_mojo10()
    items = CATALOG
    if args.only:
        wanted = [name.strip() for name in args.only.split(",") if name.strip()]
        items = [item for item in CATALOG if item["name"] in wanted]
        missing = [name for name in wanted if name not in {item["name"] for item in items}]
        if missing:
            print(f"unknown example: {', '.join(missing)}", file=sys.stderr)
            return 2

    payload = {
        "generated_at": time.strftime("%Y-%m-%d"),
        "host": host_info(mojo11, mojo10),
        "examples": [],
        "threejs_webgl": False,
        "baselines": {},
        "probe": {},
        "mojo10_refused": 0,
        "mojo10_total": 0,
    }

    previous = None
    if args.merge and results.is_file():
        previous = json.loads(results.read_text(encoding="utf-8"))
        try:
            require_same_measurement_host(previous, payload["host"])
        except ValueError as error:
            print(str(error) + ". Keep a separate full results file.", file=sys.stderr)
            return 2

    print("== baselines ==", flush=True)
    payload["baselines"] = bench_baselines(mojo11)
    print(
        "  mojo noop {m}s  node noop {n}s".format(
            m=fmt_s(payload["baselines"]["mojo"]["seconds"]),
            n=fmt_s(payload["baselines"]["node"]["seconds"]),
        ),
        flush=True,
    )

    print("== probe (Mojo 1.1) ==", flush=True)
    payload["probe"]["v11"] = bench_probe(
        mojo11, ROOT / "bench" / "probe.mojo", BUILD / "probe11"
    )
    print(
        "  compile {c}s  run {r}s  rss {m} MiB".format(
            c=fmt_s(payload["probe"]["v11"]["compile"]["seconds"]),
            r=fmt_s(payload["probe"]["v11"]["run"]["seconds"]),
            m=fmt_mib(payload["probe"]["v11"]["run"]["rss_kib"]),
        ),
        flush=True,
    )

    if mojo10:
        print("== probe (Mojo 1.0) ==", flush=True)
        payload["probe"]["v10"] = bench_probe(
            mojo10, ROOT / "bench" / "mojo10" / "probe.mojo", BUILD / "probe10"
        )
        print(
            "  compile {c}s  run {r}s  rss {m} MiB".format(
                c=fmt_s(payload["probe"]["v10"]["compile"]["seconds"]),
                r=fmt_s(payload["probe"]["v10"]["run"]["seconds"]),
                m=fmt_mib(payload["probe"]["v10"]["run"]["rss_kib"]),
            ),
            flush=True,
        )
    else:
        print("== probe (Mojo 1.0) skipped: compiler not installed ==", flush=True)

    for item in items:
        name = item["name"]
        print(f"== {name} ==", flush=True)
        binary = BUILD / name
        dest = SCRATCH / f"{name}.png"
        compile_result = bench_compile(mojo11, ROOT / item["src"], binary)
        print(f"  1.1 compile {fmt_s(compile_result['seconds'])}s", flush=True)
        run_args, cwd = example_run_args(item, dest)
        if compile_result["ok"] and binary.is_file():
            run_result = bench_run(binary, run_args, cwd)
        else:
            run_result = {
                "ok": False,
                "seconds": None,
                "rss_kib": None,
                "status": compile_result["status"],
                "output": compile_result["output"],
            }
        print(
            f"  1.1 run {fmt_s(run_result['seconds'])}s  rss {fmt_mib(run_result['rss_kib'])} MiB",
            flush=True,
        )

        skipped = {
            "ok": False,
            "seconds": None,
            "rss_kib": None,
            "status": 0,
            "backend": "",
            "output": "skipped",
        }
        flat = skipped
        web = skipped
        if not args.skip_threejs:
            flat = bench_threejs(name, "cpu-flat")
            web = bench_threejs(name, "webgl")
            if web.get("ok"):
                payload["threejs_webgl"] = True
            print(
                "  cpu-flat {f}s  webgl {w}  {note}".format(
                    f=fmt_s(flat["seconds"]),
                    w=fmt_s(web["seconds"]) + "s" if web.get("ok") else "unavailable",
                    note=web.get("backend") or "cpu-flat",
                ),
                flush=True,
            )

        mojo10_example = None
        if mojo10:
            payload["mojo10_total"] += 1
            compiled10 = bench_compile(
                mojo10, ROOT / item["src"], BUILD / f"{name}10"
            )
            binary10 = BUILD / f"{name}10"
            if compiled10["ok"] and binary10.is_file():
                dest10 = SCRATCH / f"{name}10.png"
                run_args10, cwd10 = example_run_args(item, dest10)
                if item.get("hardcoded_out"):
                    cwd10 = SCRATCH / f"{name}10"
                    (cwd10 / "out").mkdir(parents=True, exist_ok=True)
                ran10 = bench_run(binary10, run_args10, cwd10)
            else:
                payload["mojo10_refused"] += 1
                ran10 = {
                    "ok": False,
                    "seconds": None,
                    "rss_kib": None,
                    "status": compiled10["status"],
                    "output": compiled10["output"],
                }
            mojo10_example = {"compile": compiled10, "run": ran10}
            print(
                "  1.0 compile {c}s  run {r}s  rss {m} MiB".format(
                    c=fmt_s(compiled10["seconds"]),
                    r=fmt_s(ran10["seconds"]),
                    m=fmt_mib(ran10["rss_kib"]),
                ),
                flush=True,
            )

        payload["examples"].append(
            {
                "name": name,
                "measured_on": payload["generated_at"],
                "measurement_date_source": "direct",
                "width": item["width"],
                "height": item["height"],
                "frames": item["frames"],
                "threemojo": {"compile": compile_result, "run": run_result},
                "threejs_flat": flat,
                "threejs_webgl": web,
                "mojo10": mojo10_example,
            }
        )
        results.write_text(
            json.dumps(slim_payload(payload), indent=2) + "\n", encoding="utf-8"
        )

    slim = slim_payload(payload)
    if previous is not None:
        slim = merge_measurements(previous, slim)
    results.write_text(json.dumps(slim, indent=2) + "\n", encoding="utf-8")
    print(f"\nWrote {results.relative_to(ROOT)}", flush=True)
    print()
    emit_tables(slim if args.merge else payload, args.write_wiki, args.platform)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
