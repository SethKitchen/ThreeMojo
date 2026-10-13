#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Check that the reviewed CARLA scalar inventory covers current declarations.

This is a source coverage check, not a numerical or type-safety proof. It does
not infer a physical dimension from an identifier. The TSV owns that review.
"""
from __future__ import annotations

import argparse
import collections
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INVENTORY = Path("docs/validation/carla-quantity-inventory-333.tsv")
INTEGER_RECORDS = {
    ("cameras.mojo", "DVSEvent"),
    ("cameras.mojo", "DVSConfig"),
    ("cameras.mojo", "DVSCamera"),
    ("lidar.mojo", "LidarDescription"),
    ("radar.mojo", "RadarDescription"),
    ("recorder_packets.mojo", "RecorderInfo"),
    ("v2x.mojo", "ReferencePosition"),
    ("v2x.mojo", "HighFrequencyContainer"),
    ("v2x.mojo", "CAM"),
}
INTEGER_SYMBOLS = {
    ("recorder.mojo", "now_seconds", "return"),
    ("recorder.mojo", "Recorder", "start_ns"),
    ("recorder.mojo", "Recorder.begin", "date"),
    ("recorder.mojo", "Recorder.start", "date"),
    ("recorder.mojo", "Recorder.begin_unix_seconds", "date"),
    ("recorder.mojo", "Recorder.start_unix_seconds", "date"),
    ("sensor_manager.mojo", "SensorManager.from_cam_epoch_milliseconds", "generation_delta0"),
    ("v2x.mojo", "CaService.from_cam_epoch_milliseconds", "generation_delta0"),
    ("sensor_manager.mojo", "SensorManager", "generation_delta0"),
    ("sensor_manager.mojo", "SensorManager.__init__", "generation_delta0"),
    ("v2x.mojo", "CaService", "generation_delta0"),
    ("v2x.mojo", "CaService.__init__", "generation_delta0"),
    ("recorder_format.mojo", "c_date", "seconds"),
    ("v2x.mojo", "speed_value", "return"),
    ("v2x.mojo", "speed_value_meters_per_second", "return"),
}


def quantity_names(root: Path) -> set[str]:
    """Read quantity aliases, including physics, temperature and photometry."""
    names = {"Temperature", "Temperature64", "Illuminance", "Luminance",
             "LuminousFlux", "LuminousIntensity"}
    files = list((root / "units").glob("*.mojo"))
    files.append(root / "extensions/physics/quantities.mojo")
    for path in files:
        names.update(re.findall(r"^comptime (\w+)\s*=\s*Quantity\[",
                                path.read_text(), re.M))
    return names


def declarations(root: Path = ROOT) -> tuple[list[dict], dict]:
    """Read public fields and signatures without reading names as dimensions.

    Private types and methods, function locals, and constructors requiring the
    private _RawSI capability are outside the application boundary. Public
    fieldwise constructors are represented by their fields. Generic signatures
    and multiline collection types are included.
    """
    rows, functions = [], {}
    for path in sorted((root / "extensions/carla").rglob("*.mojo")):
        lines = path.read_text().splitlines()
        file = str(path.relative_to(root))
        owner, private, doc, i = "", False, False, 0
        while i < len(lines):
            line = lines[i]
            if line.count('"""') % 2:
                doc = not doc
                i += 1
                continue
            if doc:
                i += 1
                continue
            match = re.match(r"^(?:struct|trait) (\w+)", line)
            if match:
                owner = match[1]
                private = owner.startswith("_")
                i += 1
                continue
            match = re.match(r"^(\s*)def (\w+)", line)
            if match and len(match[1]) <= 4:
                indent, name, start = len(match[1]), match[2], i
                owner = owner if indent else ""
                symbol = f"{owner}.{name}" if owner else name
                signature = line
                while not signature.rstrip().endswith(":") and i + 1 < len(lines):
                    i += 1
                    signature += "\n" + lines[i]
                end = i + 1
                while end < len(lines) and (not lines[end].strip() or
                       len(lines[end]) - len(lines[end].lstrip()) > indent):
                    end += 1
                body = "\n".join(lines[i + 1:end])
                functions[(file, symbol, start + 1)] = (signature, body)
                if ((name.startswith("_") and not name.startswith("__")) or
                    (indent and private) or re.search(r"\b\w+: _RawSI\b", signature)):
                    i += 1
                    continue
                begin = signature.find("(")
                pos, depth = begin + 1, 1
                while depth and pos < len(signature):
                    depth += (signature[pos] == "(") - (signature[pos] == ")")
                    pos += 1
                arguments = signature[begin + 1:pos - 1]
                parts, mark, depth = [], 0, 0
                for j, character in enumerate(arguments + ","):
                    if character in "([":
                        depth += 1
                    elif character in ")]":
                        depth -= 1
                    elif character == "," and depth == 0:
                        parts.append(arguments[mark:j].strip())
                        mark = j + 1
                for part in parts:
                    argument = re.match(r"(?:(?:out|var|mut|ref|read) )?(\w+):\s*(.*)", part, re.S)
                    if argument:
                        raw_type = argument[2].split(" = ")[0].strip()
                        rows.append(dict(file=file, symbol=symbol, member=argument[1],
                                         type=" ".join(raw_type.split()), kind="parameter", line=start + 1))
                result = re.search(r"->\s*(.*):\s*$", signature[pos:], re.S)
                if result:
                    rows.append(dict(file=file, symbol=symbol, member="return",
                                     type=" ".join(result[1].split()), kind="return", line=start + 1))
                i += 1
                continue
            match = re.match(r"^    var (\w+):\s*([^=#]+)", line)
            if match and owner and not private and not match[1].startswith("_"):
                start, raw_type = i, match[2].strip()
                depth = raw_type.count("[") - raw_type.count("]")
                while depth and i + 1 < len(lines):
                    i += 1
                    raw_type += " " + lines[i].strip()
                    depth += lines[i].count("[") - lines[i].count("]")
                rows.append(dict(file=file, symbol=owner, member=match[1],
                                 type=" ".join(raw_type.split()), kind="field", line=start + 1))
            i += 1
    return rows, functions


def selected(root: Path = ROOT) -> tuple[list[dict], dict]:
    """Select every float or quantity, plus exact integer wire/rate records."""
    rows, functions = declarations(root)
    pattern = re.compile(r"\b(?:Float32|Float64|DType\.float32|DType\.float64|" +
                         "|".join(sorted(quantity_names(root))) + r")\b")
    result = []
    for row in rows:
        file = row["file"].split("/")[-1]
        integer = row["type"] in {"Int", "Int32", "UInt32", "UInt64"}
        if (pattern.search(row["type"]) or
            (integer and (file, row["symbol"]) in INTEGER_RECORDS) or
            (file, row["symbol"], row["member"]) in INTEGER_SYMBOLS):
            result.append(row)
    return result, functions


def key(row: dict) -> tuple:
    """Identify each declaration independently of shifting source lines."""
    return tuple(row[name] for name in ("file", "symbol", "member", "type", "kind"))


def main() -> int:
    """Compare declaration multisets and require a complete review per row."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--dump", action="store_true")
    parser.add_argument("--refresh-lines", action="store_true",
                        help="Refresh source lines only after the declaration set matches.")
    args = parser.parse_args()
    rows, _ = selected(args.root)
    if args.dump:
        print(json.dumps(rows, indent=2))
        return 0
    with (args.root / INVENTORY).open(newline="") as stream:
        inventory = list(csv.DictReader(stream, delimiter="\t"))
    expected = collections.Counter(map(key, rows))
    found = collections.Counter(map(key, inventory))
    failures = []
    for item, count in (expected - found).items():
        failures.append(f"Missing {count} declaration(s): {item}")
    for item, count in (found - expected).items():
        failures.append(f"Stale {count} declaration(s): {item}")
    categories = {"typed-boundary", "raw-adapter", "source-field", "wire-field",
                  "internal-state", "stage-kernel", "dimensionless", "generic-numeric",
                  "source-code", "unimplemented-source-setting"}
    for row in inventory:
        if row.get("classification") not in categories:
            failures.append(f"Unreviewed classification: {key(row)}")
        for field in ("unit_or_meaning", "typed_boundary", "raw_adapter", "validation", "rationale"):
            if not row.get(field):
                failures.append(f"Missing {field}: {key(row)}")
    if failures:
        print("\n".join(failures))
        return 1
    if args.refresh_lines:
        current_lines = collections.defaultdict(list)
        for row in rows:
            current_lines[key(row)].append(row["line"])
        for row in inventory:
            row["line"] = current_lines[key(row)].pop(0)
        with (args.root / INVENTORY).open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(inventory[0]),
                                    delimiter="\t", lineterminator="\n")
            writer.writeheader()
            writer.writerows(inventory)
    print(f"PASS: {len(rows)} current public scalar/quantity declarations; all rows have a reviewed disposition.")
    print("This checks inventory coverage only. It does not prove numerical correctness or passing runtime tests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
