# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Zip each vehicle package for upload, and write its sha256 and members.

    python zip_packages.py

Writes `upload/<id>.zip` for each package and `upload/index.json` with
each zip's sha256, its size and the members to extract.
"""

import hashlib
import json
import os
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
# The work folder: the cooked content, UModel and every stage's output.
BASE = os.path.abspath(os.environ.get("CARLA_EXPORT_DIR", "."))
PACKAGES = os.path.join(BASE, "packages")
UPLOAD = os.path.join(BASE, "upload")

os.makedirs(UPLOAD, exist_ok=True)
index = {}
for vehicle_id in sorted(os.listdir(PACKAGES)):
    folder = os.path.join(PACKAGES, vehicle_id)
    if not os.path.isdir(folder):
        continue
    target = os.path.join(UPLOAD, vehicle_id + ".zip")
    members = []
    # A fixed date and order, so the same package zips to the same sum.
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for base, _, files in sorted(os.walk(folder)):
            for name in sorted(files):
                full = os.path.join(base, name)
                rel = os.path.relpath(full, folder).replace("\\", "/")
                info = zipfile.ZipInfo(rel, date_time=(2025, 9, 16, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, open(full, "rb").read())
                members.append(rel)
    digest = hashlib.sha256(open(target, "rb").read()).hexdigest()
    index[vehicle_id] = {
        "zip": vehicle_id + ".zip",
        "sha256": digest,
        "bytes": os.path.getsize(target),
        "members": members,
    }
json.dump(index, open(os.path.join(UPLOAD, "index.json"), "w"), indent=1)
total = sum(e["bytes"] for e in index.values())
print(f"{len(index)} zips, {total / 1e6:.1f} MB, largest {max(e['bytes'] for e in index.values()) / 1e6:.1f} MB")
