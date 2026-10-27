# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Production modules do not consume the containing objective model."""

from std.pathlib import Path
from std.testing import TestSuite, assert_raises

from tools._process import run_program
from tools._optional_model_consumers import (
    containing_model_consumers,
    require_observed_consumers,
)


def _make(root: String, relative: String, text: String) raises:
    """Write one file under `root`.

    Args:
        root: The temporary repository.
        relative: The path inside `root`.
        text: The file text.

    Raises:
        Error: The directory cannot be created.
    """
    var slash = relative.rfind("/")
    var parent = root
    if slash >= 0:
        parent = root + "/" + String(relative[byte=0:slash])
    var made = run_program(["mkdir", "-p", parent], 10.0)
    if made.status != 0:
        raise Error(made.output)
    Path(root + "/" + relative).write_text(text)


def test_the_live_tree_has_no_containing_model_consumer() raises:
    """Production modules keep the objective model inside its own file."""
    containing_model_consumers(".")


def test_a_reintroduced_containing_model_consumer_is_refused() raises:
    """An executable model name or a removed search name is refused."""
    var clean = "/tmp/optional-model-consumers-clean"
    _make(
        clean,
        "extensions/carla/curve_objective_model.mojo",
        "def _try_objective_model():\n    pass\n",
    )
    _make(
        clean,
        "extensions/carla/note.mojo",
        "# _try_objective_model stays in a comment\n",
    )
    _make(
        clean,
        "extensions/carla/text.mojo",
        'def show():\n    var label = "_try_objective_model"\n',
    )
    _make(
        clean,
        "tests/caller.mojo",
        "def use():\n    var model = _try_objective_model\n",
    )
    _make(
        clean,
        ".hidden/caller.mojo",
        "def use():\n    var model = _try_objective_model\n",
    )
    _make(
        clean,
        "extensions/carla/render_actors.mojo",
        "def place():\n    var cached_models = 0\n",
    )
    containing_model_consumers(clean)
    var consumer = "/tmp/optional-model-consumers-call"
    _make(
        consumer,
        "extensions/carla/extra.mojo",
        "def use():\n    var model = _try_objective_model\n",
    )
    with assert_raises(
        contains=(
            "optional runtime contract: containing-objective model production "
            "consumer reintroduced: extensions/carla/extra.mojo"
        )
    ):
        containing_model_consumers(consumer)
    var search = "/tmp/optional-model-consumers-search"
    _make(
        search,
        "extensions/carla/lane_refinement.mojo",
        "def _run():\n    var cached_model = None\n",
    )
    with assert_raises(
        contains=(
            "optional runtime contract: containing-objective model search "
            "state reintroduced"
        )
    ):
        containing_model_consumers(search)


def test_observed_consumers_use_the_supplied_text() raises:
    """The observed list is checked in order, including an empty list."""
    require_observed_consumers("[]")
    require_observed_consumers(
        '[{"path":"extensions/carla/curve_objective_model.mojo","text":'
        + '"def _try_objective_model():\\n    pass\\n"},'
        + '{"path":"extensions/carla/note.mojo","text":'
        + '"def show():\\n    var label = 1\\n"}]'
    )
    with assert_raises(
        contains=(
            "optional runtime contract: containing-objective model production "
            "consumer reintroduced: extensions/carla/extra.mojo"
        )
    ):
        require_observed_consumers(
            '[{"path":"extensions/carla/note.mojo","text":"def show():\\n   '
            ' pass\\n"},'
            + '{"path":"extensions/carla/extra.mojo","text":'
            + '"def use():\\n    var model = _try_objective_model\\n"}]'
        )
    with assert_raises(
        contains=(
            "optional runtime contract: containing-objective model search "
            "state reintroduced"
        )
    ):
        require_observed_consumers(
            '[{"path":"extensions/carla/lane_refinement.mojo","text":'
            + '"def _run():\\n    var cached_model = None\\n"}]'
        )


def main() raises:
    """Run the containing-model consumer tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
