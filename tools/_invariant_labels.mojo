# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the coverage-invariant pin files and the successor message.

The live records still come from the repository. These names only say which
pin file is runtime, which pin file is the guard, and which message a
changed successor uses.
"""

from tools._migration_records import migration_records
from tools._python_json import PyJson


def invariant_labels() -> String:
    """Return the pin file names, the prior record, and the messages.

    Returns:
        JSON with `filenames`, `after`, `before`, `successor`, `prior`, and
        `oracle` in that order.
    """
    return (
        '{"filenames":["runtime-source-pins.json","sum2-guard-pins.json"],'
        + '"after":"after","before":"before",'
        + '"successor":"complete successor changed: ",'
        + '"prior":"tools/carla_lane_oracle/frozen-arc-producer-migration.json",'
        + '"oracle":"tools/carla_lane_oracle"}'
    )


def invariant_labels_with_migration() raises -> String:
    """Read the invariant labels, then the migration record.

    Returns:
        JSON with `labels` and `migration`. `labels` is first.

    Raises:
        Error: The migration record cannot be read. The labels are read
            before the migration record.
    """
    var labels = invariant_labels()
    var records = PyJson.parse(migration_records())
    var item = records.at(records.root, "invariant")
    return (
        '{"labels":'
        + labels
        + ',"migration":{"path":"'
        + records.text(records.at(item, "path"))
        + '","sha":"'
        + records.text(records.at(item, "sha"))
        + '"}}'
    )
