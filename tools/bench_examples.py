#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Time every example against three.js and, when present, Mojo 1.0."""

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
RESULTS = ROOT / "bench" / "results.json"
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


def node_env() -> dict[str, str]:
    node = which_node()
    env = {}
    if node:
        bindir = str(node.parent)
        env["PATH"] = bindir + os.pathsep + os.environ.get("PATH", "")
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


def host_info(mojo11: Path | None, mojo10: Path | None) -> dict:
    cpu = platform.processor() or platform.machine()
    try:
        cpu = Path("/proc/cpuinfo").read_text(encoding="utf-8")
        for line in cpu.splitlines():
            if line.lower().startswith("model name"):
                cpu = line.split(":", 1)[1].strip()
                break
    except OSError:
        pass
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
        "os": f"{platform.system()} {platform.release()}",
        "cpu": cpu,
        "python": sys.version.split()[0],
        "mojo_1_1": mojo_version(mojo11) if mojo11 else "",
        "mojo_1_0": mojo_version(mojo10) if mojo10 else "",
        "node": node_ver,
    }


def measure(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> dict:
    """Run cmd and return elapsed seconds, peak RSS in KiB, status and stderr."""
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    if Path(TIME_BIN).is_file():
        wrapped = [TIME_BIN, "-f", "TIME_RSS %e %M %x", "--", *cmd]
        proc = subprocess.run(
            wrapped,
            cwd=cwd,
            env=full_env,
            capture_output=True,
            text=True,
            check=False,
        )
        combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
        for line in combined.splitlines():
            match = RSS_LINE.match(line.strip())
            if match:
                elapsed, rss, status = match.groups()
                return {
                    "ok": int(float(status)) == 0,
                    "seconds": float(elapsed),
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
    if value is None:
        return "—"
    return f"{value:.3f}"


def fmt_mib(kib: int | None) -> str:
    if kib is None:
        return "—"
    return f"{kib / 1024:.1f}"


# Lower is better. A 10% gap is a tie. A 30% gap is a large win.
TIE_RATIO = 0.10
WIN_LOT_RATIO = 0.30
CELL_STYLE = {
    "win_lot": ("#14532d", "#ffffff"),
    "win_little": ("#86efac", "#14532d"),
    "tie": ("#fde047", "#422006"),
}


def good_seconds(metric: dict | None) -> float | None:
    if not metric or not metric.get("ok"):
        return None
    value = metric.get("seconds")
    return value if isinstance(value, (int, float)) else None


def good_mib(metric: dict | None) -> float | None:
    if not metric or not metric.get("ok"):
        return None
    kib = metric.get("rss_kib")
    if not isinstance(kib, (int, float)):
        return None
    return kib / 1024.0


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


def paint(text: str, kind: str) -> str:
    if kind == "plain" or kind not in CELL_STYLE:
        return text
    bg, fg = CELL_STYLE[kind]
    body = f"<strong>{text}</strong>" if kind.startswith("win") else text
    return (
        f'<span style="background-color:{bg};color:{fg};padding:0 0.4em">{body}</span>'
    )


def painted_pair(
    left_text: str, right_text: str, left: float | None, right: float | None
) -> tuple[str, str]:
    kind_l, kind_r = compare_pair(left, right)
    return paint(left_text, kind_l), paint(right_text, kind_r)


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


def bench_run(binary: Path, args: list[str], cwd: Path) -> dict:
    return measure([str(binary), *args], cwd=cwd)


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


def bench_threejs(name: str) -> dict:
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
    result = measure(
        [str(node), str(THREEJS / "run.mjs"), name],
        cwd=ROOT,
        env=node_env(),
    )
    backend = ""
    for line in result["output"].splitlines():
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            try:
                payload = json.loads(line)
                backend = payload.get("backend", "")
            except json.JSONDecodeError:
                pass
    result["backend"] = backend
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


def example_table(rows: list[dict], backend: str) -> str:
    lines = [
        "| Example | Size | Frames | ThreeMojo compile (s) | ThreeMojo run (s) | three.js run (s) | ThreeMojo RSS (MiB) | three.js RSS (MiB) |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for row in rows:
        tm = row["threemojo"]
        js = row["threejs"]
        tm_run_ok = tm["compile"].get("ok") and tm["run"].get("ok")
        tm_run = fmt_s(tm["run"]["seconds"]) if tm_run_ok else (
            "compile failed" if not tm["compile"].get("ok") else "run failed"
        )
        tm_rss = fmt_mib(tm["run"].get("rss_kib")) if tm_run_ok else "—"
        js_run = fmt_s(js["seconds"]) if js.get("ok") else "failed"
        js_rss = fmt_mib(js.get("rss_kib")) if js.get("ok") else "—"
        run_l, run_r = painted_pair(
            tm_run,
            js_run,
            good_seconds(tm["run"]) if tm_run_ok else None,
            good_seconds(js),
        )
        rss_l, rss_r = painted_pair(
            tm_rss,
            js_rss,
            good_mib(tm["run"]) if tm_run_ok else None,
            good_mib(js),
        )
        lines.append(
            "| `{name}` | {w}×{h} | {frames} | {c} | {r} | {jr} | {m} | {jm} |".format(
                name=row["name"],
                w=row["width"],
                h=row["height"],
                frames=row["frames"],
                c=fmt_s(tm["compile"]["seconds"]),
                r=run_l,
                jr=run_r,
                m=rss_l,
                jm=rss_r,
            )
        )
    if backend:
        lines.append("")
        lines.append(f"three.js backend for this run: `{backend}`.")
    return "\n".join(lines)


def pair_cells(compile_result: dict | None, run_result: dict | None) -> tuple[str, str, str]:
    if compile_result is None:
        return "not installed", "—", "—"
    compile_s = fmt_s(compile_result["seconds"])
    if not compile_result.get("ok"):
        return compile_s, "refused", "—"
    if run_result is None:
        return compile_s, "—", "—"
    if not run_result.get("ok"):
        return compile_s, "run failed", "—"
    return compile_s, fmt_s(run_result["seconds"]), fmt_mib(run_result["rss_kib"])


def mojo10_row(name: str, left: dict | None, right: dict | None) -> str:
    if left:
        c11, r11, m11 = pair_cells(left["compile"], left.get("run"))
        left_c = good_seconds(left["compile"])
        left_r = good_seconds(left.get("run"))
        left_m = good_mib(left.get("run"))
    else:
        c11, r11, m11 = "—", "—", "—"
        left_c = left_r = left_m = None
    if right and "compile" in right:
        c10, r10, m10 = pair_cells(right["compile"], right.get("run"))
        right_c = good_seconds(right["compile"])
        right_r = good_seconds(right.get("run"))
        right_m = good_mib(right.get("run"))
    elif right is None:
        c10, r10, m10 = "not installed", "—", "—"
        right_c = right_r = right_m = None
    else:
        c10, r10, m10 = pair_cells(right, None)
        right_c = right_r = right_m = None
    c11, c10 = painted_pair(c11, c10, left_c, right_c)
    r11, r10 = painted_pair(r11, r10, left_r, right_r)
    m11, m10 = painted_pair(m11, m10, left_m, right_m)
    return f"| `{name}` | {c11} | {c10} | {r11} | {r10} | {m11} | {m10} |"


def mojo10_table(probe11: dict, probe10: dict | None, examples: list[dict]) -> str:
    lines = [
        "| Program | 1.1 compile (s) | 1.0 compile (s) | 1.1 run (s) | 1.0 run (s) | 1.1 RSS (MiB) | 1.0 RSS (MiB) |",
        "|---|---|---|---|---|---|---|",
        mojo10_row("probe", probe11, probe10),
    ]
    for row in examples:
        lines.append(mojo10_row(row["name"], row["threemojo"], row.get("mojo10")))
    return "\n".join(lines)


def replace_span(text: str, name: str, body: str) -> str:
    start = f"<!-- BENCH:{name} -->"
    end = f"<!-- /BENCH:{name} -->"
    pattern = re.compile(
        re.escape(start) + r".*?" + re.escape(end),
        re.DOTALL,
    )
    block = f"{start}\n{body}\n{end}"
    if not pattern.search(text):
        raise SystemExit(f"Benchmarks.md is missing {start}")
    return pattern.sub(block, text)


def slim_metric(metric: dict | None) -> dict | None:
    if metric is None:
        return None
    kept = {
        key: metric[key]
        for key in ("ok", "seconds", "rss_kib", "status", "backend", "error")
        if key in metric
    }
    if not metric.get("ok"):
        kept["error"] = refused_reason(metric.get("output", "") or metric.get("error", ""))
    return kept


def slim_payload(payload: dict) -> dict:
    slim = {
        "generated_at": payload["generated_at"],
        "host": payload["host"],
        "threejs_backend": payload.get("threejs_backend", ""),
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
                "width": row["width"],
                "height": row["height"],
                "frames": row["frames"],
                "threemojo": {
                    "compile": slim_metric(row["threemojo"]["compile"]),
                    "run": slim_metric(row["threemojo"]["run"]),
                },
                "threejs": slim_metric(row["threejs"]),
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


def write_wiki(payload: dict) -> None:
    host = payload["host"]
    host_md = "\n".join(
        [
            f"- Date: `{payload['generated_at']}`",
            f"- OS: {host['os']}",
            f"- CPU: {host['cpu']}",
            f"- Mojo 1.1: `{host['mojo_1_1'] or 'missing'}`",
            f"- Mojo 1.0: `{host['mojo_1_0'] or 'not installed'}`",
            f"- Node: `{host['node'] or 'missing'}`",
            f"- three.js backend: `{payload.get('threejs_backend') or 'missing'}`",
        ]
    )
    text = WIKI.read_text(encoding="utf-8")
    text = replace_span(text, "HOST", host_md)
    text = replace_span(
        text,
        "EXAMPLES",
        example_table(payload["examples"], payload.get("threejs_backend", "")),
    )
    text = replace_span(
        text,
        "MOJO10",
        mojo10_table(
            payload["probe"]["v11"],
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
        help="Merge into an existing bench/results.json",
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
        help="Rebuild wiki tables from bench/results.json",
    )
    return parser.parse_args()


def emit_tables(payload: dict, write_wiki_page: bool) -> None:
    print(example_table(payload["examples"], payload.get("threejs_backend", "")))
    print()
    print(
        mojo10_table(
            payload["probe"]["v11"],
            payload["probe"].get("v10"),
            payload["examples"],
        )
    )
    if write_wiki_page:
        write_wiki(payload)
        print(f"\nUpdated {WIKI.relative_to(ROOT)}", flush=True)


def main() -> int:
    args = parse_args()
    if args.from_results:
        if not RESULTS.is_file():
            print("bench/results.json is missing. Run the benches first.", file=sys.stderr)
            return 1
        emit_tables(json.loads(RESULTS.read_text(encoding="utf-8")), args.write_wiki)
        return 0
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
        "threejs_backend": "",
        "probe": {},
        "mojo10_refused": 0,
        "mojo10_total": 0,
    }

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

        js = {
            "ok": False,
            "seconds": None,
            "rss_kib": None,
            "status": 0,
            "backend": "",
            "output": "skipped",
        }
        if not args.skip_threejs:
            js = bench_threejs(name)
            if js.get("backend"):
                payload["threejs_backend"] = js["backend"]
            print(
                f"  three.js {fmt_s(js['seconds'])}s  rss {fmt_mib(js['rss_kib'])} MiB  {js.get('backend') or 'failed'}",
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
                "width": item["width"],
                "height": item["height"],
                "frames": item["frames"],
                "threemojo": {"compile": compile_result, "run": run_result},
                "threejs": js,
                "mojo10": mojo10_example,
            }
        )

    slim = slim_payload(payload)
    if args.merge and RESULTS.is_file():
        previous = json.loads(RESULTS.read_text(encoding="utf-8"))
        by_name = {row["name"]: row for row in previous.get("examples", [])}
        for row in slim["examples"]:
            by_name[row["name"]] = row
        slim["examples"] = [
            by_name[item["name"]] for item in CATALOG if item["name"] in by_name
        ]
        if previous.get("probe"):
            slim["probe"] = previous["probe"] | slim.get("probe", {})
        slim["host"] = slim["host"] or previous.get("host", {})
        slim["threejs_backend"] = slim.get("threejs_backend") or previous.get(
            "threejs_backend", ""
        )
        payload["examples"] = slim["examples"]
        payload["probe"] = slim["probe"]
        payload["host"] = slim["host"]
        payload["threejs_backend"] = slim["threejs_backend"]
    RESULTS.write_text(json.dumps(slim, indent=2) + "\n", encoding="utf-8")
    print(f"\nWrote {RESULTS.relative_to(ROOT)}", flush=True)
    print()
    emit_tables(slim if args.merge else payload, args.write_wiki)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
