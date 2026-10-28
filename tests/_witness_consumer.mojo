# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Restore the witness-format consumer through its recorded endpoints."""

from tools._sha256 import sha256_hex


def _split(text: String) -> List[String]:
    """Split `text` into lines that keep their endings.

    Args:
        text: The source.

    Returns:
        The lines. A trailing newline stays on the last line.
    """
    var lines = List[String]()
    var rest = text
    while True:
        var at = rest.find("\n")
        if at < 0:
            if rest.byte_length() > 0:
                lines.append(rest)
            return lines^
        var end = at + 1
        lines.append(String(rest[byte=:end]))
        var tail = String(rest[byte=end:])
        rest = tail


def _join(lines: List[String]) -> String:
    """Join lines that already keep their endings.

    Args:
        lines: The lines.

    Returns:
        The source.
    """
    var out = ""
    for line in lines:
        out += line
    return out


def _apply(
    text: String,
    starts: List[Int],
    stops: List[Int],
    currents: List[String],
    replacements: List[String],
    path: String,
) raises -> String:
    """Apply line edits from the highest start.

    Args:
        text: The newer source.
        starts: The first line of each edit.
        stops: The line after each edit.
        currents: The newer text of each edit.
        replacements: The older text of each edit.
        path: The module, named when an edit does not match.

    Returns:
        The older source.

    Raises:
        Error: An edit does not match `text`.
    """
    var lines = _split(text)
    var order = List[Int]()
    for index in range(len(starts)):
        order.append(index)
    var slot = 0
    while slot < len(order):
        var best = slot
        var look = slot + 1
        while look < len(order):
            if starts[order[look]] > starts[order[best]]:
                best = look
            look += 1
        var tmp = order[slot]
        order[slot] = order[best]
        order[best] = tmp
        slot += 1
    for index in order:
        var start = starts[index]
        var stop = stops[index]
        var found = ""
        var line = start
        while line < stop:
            found += lines[line]
            line += 1
        if found != currents[index]:
            raise Error("witness consumer: edit does not match: " + path)
        var next = List[String]()
        var kept = 0
        while kept < start:
            next.append(lines[kept])
            kept += 1
        var added = _split(replacements[index])
        for piece in added:
            next.append(piece)
        while stop < len(lines):
            next.append(lines[stop])
            stop += 1
        lines = next^
    return _join(lines)


def _edits_mid(
    mut starts: List[Int],
    mut stops: List[Int],
    mut currents: List[String],
    mut replacements: List[String],
):
    """Fill the edits from the live text to the mid text.

    Args:
        starts: The first line of each edit.
        stops: The line after each edit.
        currents: The newer text of each edit.
        replacements: The older text of each edit.
    """
    starts.append(114)
    stops.append(118)
    currents.append(
        "                physical = (self.root/path).read_bytes()\n          "
        "      self.assertEqual(bindings[path], cleanup.sha(physical))\n     "
        "           self.assertEqual(cleanup.sha(fixtures.typed_current_bytes"
        "(path, physical)),\n                                 witness.AFTER_S"
        "HA256[path])\n"
    )
    replacements.append(
        "                self.assertEqual(bindings[path], witness.AFTER_SHA25"
        "6[path])\n"
    )


def _edits_qualification(
    mut starts: List[Int],
    mut stops: List[Int],
    mut currents: List[String],
    mut replacements: List[String],
):
    """Fill the edits from the mid text to the qualification text.

    Args:
        starts: The first line of each edit.
        stops: The line after each edit.
        currents: The newer text of each edit.
        replacements: The older text of each edit.
    """
    starts.append(109)
    stops.append(113)
    currents.append(
        "                physical = (self.root/path).read_bytes()\n          "
        "      self.assertEqual(bindings[path], cleanup.sha(physical))\n     "
        "           self.assertEqual(cleanup.sha(fixtures.typed_current_bytes"
        "(path, physical)),\n                                 edge['after_sha"
        "256'])\n"
    )
    replacements.append(
        "                self.assertEqual(bindings[path], edge['after_sha256'"
        "])\n"
    )


def _edits_typed(
    mut starts: List[Int],
    mut stops: List[Int],
    mut currents: List[String],
    mut replacements: List[String],
):
    """Fill the edits from the qualification text to the typed text.

    Args:
        starts: The first line of each edit.
        stops: The line after each edit.
        currents: The newer text of each edit.
        replacements: The older text of each edit.
    """
    starts.append(154)
    stops.append(170)
    currents.append(
        "        # Observe the real current checker without invalidating its "
        "code seal.\n        census = cleanup.guard.production_mojo_paths\n  "
        "      calls = []\n        def reject_census(frame, event, value):\n "
        "           if event == 'call' and frame.f_code is census.__code__:\n"
        "                calls.append(True)\n                raise AssertionE"
        "rror('extra census')\n        previous = sys.getprofile()\n        t"
        "ry:\n            sys.setprofile(reject_census)\n            with sel"
        "f.assertRaisesRegex(AssertionError, 'extra census'):\n              "
        "  list(census(self.root))\n            self.assertEqual(calls, [True"
        "])\n            # Python disables a profile callback after it raises"
        ". Rearm it for\n            # the actual positive; any real census c"
        "all must still fail.\n            sys.setprofile(reject_census)\n"
    )
    replacements.append(
        "        with patch.object(cleanup.guard, 'production_mojo_paths', si"
        "de_effect=AssertionError('extra census')):\n"
    )
    starts.append(171)
    stops.append(174)
    currents.append(
        "            self.assertEqual(calls, [True])\n        finally:\n     "
        "       sys.setprofile(previous)\n"
    )
    replacements.append("")
    starts.append(176)
    stops.append(189)
    currents.append(
        "        with patch.object(cleanup.guard, 'production_mojo_paths', si"
        "de_effect=AssertionError('extra census')):\n            with self.as"
        "sertRaisesRegex(cleanup.ContractError, 'executing function changed')"
        ":\n                cleanup._witness_format_bindings(self.root)\n    "
        "    # The original pre-typed leaf still accepts the original monkeyp"
        "atch\n        # control, proving its no-census behavior independentl"
        "y of this edge.\n        historical = fixtures.copy_historical_bound"
        "ary_root(self, ROOT)\n        with patch.object(cleanup.guard, 'prod"
        "uction_mojo_paths', side_effect=AssertionError('extra census')):\n  "
        "          old_bindings = cleanup._witness_format_bindings(historical"
        ")\n        self.assertEqual(set(old_bindings), set(self.paths))\n   "
        "     self.assertNotIn('math/scaled_products.mojo', old_bindings)\n  "
        "      for root, actual in ((self.root, bindings), (historical, old_b"
        "indings)):\n            self.assertEqual(actual, {name: cleanup.sha("
        "(root/name).read_bytes())\n                                      for"
        " name in self.paths})\n"
    )
    replacements.append("")
    starts.append(191)
    stops.append(202)
    currents.append(
        "        current = self.root\n        try:\n            for cohort in"
        " ('pr760', 'common758'):\n                self.root = (current if co"
        "hort == 'pr760' else\n                             fixtures.copy_com"
        "mon758_boundary_root(self, ROOT))\n                with self.subTest"
        "(cohort=cohort):\n                    self._check_alias_paths_and_na"
        "tive_module_shadows_refuse(cohort)\n        finally:\n            se"
        "lf.root = current\n\n    def _check_alias_paths_and_native_module_sh"
        "adows_refuse(self, cohort):\n"
    )
    replacements.append("")
    starts.append(219)
    stops.append(224)
    currents.append(
        "        created = []\n        parent = shadow.parent\n        while "
        "not parent.exists():\n            created.append(parent)\n          "
        "  parent = parent.parent\n"
    )
    replacements.append("")
    starts.append(226)
    stops.append(236)
    currents.append(
        "        try:\n            reason = ('PR760 exact dependency closure "
        "changed' if cohort == 'pr760'\n                      else 'resolver'"
        ")\n            with self.assertRaisesRegex(ValueError, reason):\n   "
        "             cleanup.verify(self.root)\n        finally:\n          "
        "  shadow.unlink()\n            for parent in created:\n             "
        "   parent.rmdir()\n        cleanup.verify(self.root, exact=True)\n"
    )
    replacements.append(
        "        with self.assertRaisesRegex(ValueError, 'resolver'):\n      "
        "      cleanup.verify(self.root)\n"
    )
    starts.append(255)
    stops.append(266)
    currents.append(
        "        current = self.root\n        try:\n            for cohort in"
        " ('pr760', 'common758'):\n                self.root = (current if co"
        "hort == 'pr760' else\n                             fixtures.copy_com"
        "mon758_boundary_root(self, ROOT))\n                with self.subTest"
        "(cohort=cohort):\n                    self._check_full_gate_late_pro"
        "of_input_mutation(cohort)\n        finally:\n            self.root ="
        " current\n\n    def _check_full_gate_late_proof_input_mutation(self,"
        " cohort):\n"
    )
    replacements.append("")
    starts.append(275)
    stops.append(280)
    currents.append(
        "            # PR760 consumes inventory within its image admission; t"
        "he same late\n            # mutation meets its physical reread befor"
        "e the outer final sweep.\n            reason = ('PR760 source change"
        "d after consumption: ' + target.relative_to(self.root).as_posix()\n "
        "                     if cohort == 'pr760' else 'input changed during"
        " verification')\n            with patch.object(cleanup, 'inventory',"
        " late), self.assertRaisesRegex(ValueError, reason):\n"
    )
    replacements.append(
        "            with patch.object(cleanup, 'inventory', late), self.asse"
        "rtRaisesRegex(ValueError, 'input changed during verification'):\n"
    )


def _edits_bound(
    mut starts: List[Int],
    mut stops: List[Int],
    mut currents: List[String],
    mut replacements: List[String],
):
    """Fill the edits from the typed text to the bound text.

    Args:
        starts: The first line of each edit.
        stops: The line after each edit.
        currents: The newer text of each edit.
        replacements: The older text of each edit.
    """
    starts.append(19)
    stops.append(26)
    currents.append(
        "    @classmethod\n    def setUpClass(cls):\n        import _full_aud"
        "it_test_fixtures as historical_fixtures\n        owner = type('Histo"
        "ricalClassFixture', (), {\n            'addCleanup': staticmethod(cl"
        "s.addClassCleanup)})()\n        cls.historical_root = historical_fix"
        "tures.copy_historical_boundary_root(owner, ROOT)\n\n"
    )
    replacements.append("")
    starts.append(28)
    stops.append(31)
    currents.append(
        "        record = cleanup.read_record(self.historical_root)\n        "
        "for path in witness.SOURCE_PATHS:\n            current = (self.histo"
        "rical_root/path).read_bytes().decode('utf-8')\n"
    )
    replacements.append(
        "        record = cleanup.read_record(ROOT)\n        for path in witn"
        "ess.SOURCE_PATHS:\n            current = (ROOT/path).read_bytes().de"
        "code('utf-8')\n"
    )
    starts.append(46)
    stops.append(47)
    currents.append(
        "            current = (self.historical_root/path).read_text()\n"
    )
    replacements.append("            current = (ROOT/path).read_text()\n")
    starts.append(57)
    stops.append(58)
    currents.append(
        "            current = (self.historical_root/path).read_text()\n"
    )
    replacements.append("            current = (ROOT/path).read_text()\n")
    starts.append(83)
    stops.append(84)
    currents.append(
        "                         hashlib.sha256((self.historical_root/LEAF)."
        "read_bytes()).hexdigest())\n"
    )
    replacements.append(
        "                         hashlib.sha256((ROOT/LEAF).read_bytes()).he"
        "xdigest())\n"
    )
    starts.append(106)
    stops.append(112)
    currents.append(
        "            if path in cleanup.typed_boundary.EDGES:\n              "
        "  edge = cleanup.typed_boundary.edge(path)\n                self.ass"
        "ertEqual(edge['before_sha256'], witness.AFTER_SHA256[path])\n       "
        "         self.assertEqual(bindings[path], edge['after_sha256'])\n   "
        "         else:\n                self.assertEqual(bindings[path], wit"
        "ness.AFTER_SHA256[path])\n"
    )
    replacements.append(
        "            self.assertEqual(bindings[path], witness.AFTER_SHA256[pa"
        "th])\n"
    )
    starts.append(117)
    stops.append(120)
    currents.append(
        "        # Formatting-only endpoints belong to the named historical g"
        "raph.\n        # All other physical controls in this class retain th"
        "e current root.\n        self.root = fixtures.copy_historical_bounda"
        "ry_root(self, ROOT)\n"
    )
    replacements.append("")


comptime _PATH = "tools/carla_lane_oracle/test_witness_format_contracts.py"
"""The witness-format consumer."""
comptime _LIVE = (
    "0f6f81acd262946a8b84fd100f0522d2973325cf712f480eb6476e63e4f0b282"
)
"""The live consumer digest."""
comptime _MID = (
    "ac1dcd518c3a6681ca0e161081b9bb26ccdf2a3e4217266d5a5ecd1c52f3e203"
)
"""The digest one edit before the qualification endpoint."""
comptime _QUALIFICATION = (
    "82f7e13e72b4f99ccad63d5dfe55fc0a73c898120b43ed8416b0731489ea6f84"
)
"""The qualification endpoint digest."""
comptime _TYPED = (
    "ad002f1255ae4f545a5cbfb3b8abf3f8e883a2637656248a232b297032b178de"
)
"""The typed-boundary after digest."""
comptime _BOUND = (
    "aa279a2131c68601f9e2f3c7347d88b612d7284adab4e2258c90c4e2b432d571"
)
"""The witness bound-input digest."""


def _digest(text: String) -> String:
    """Return the SHA-256 of `text`.

    Args:
        text: The source.

    Returns:
        The digest.
    """
    return sha256_hex(text.as_bytes())


def _step(
    text: String,
    starts: List[Int],
    stops: List[Int],
    currents: List[String],
    replacements: List[String],
    expected: String,
) raises -> String:
    """Apply one recorded step and require its digest.

    Args:
        text: The newer source.
        starts: The first line of each edit.
        stops: The line after each edit.
        currents: The newer text of each edit.
        replacements: The older text of each edit.
        expected: The digest of the older source.

    Returns:
        The older source.

    Raises:
        Error: The step misses its digest.
    """
    var older = _apply(text, starts, stops, currents, replacements, _PATH)
    if _digest(older) != expected:
        raise Error("witness consumer: restored digest changed")
    return older


def restored_witness_qualification(text: String) raises -> String:
    """Restore the qualification endpoint from the live witness test.

    Args:
        text: The live witness test.

    Returns:
        The qualification endpoint.

    Raises:
        Error: The live file or a restored step misses its digest.
    """
    if _digest(text) != _LIVE:
        raise Error("witness consumer: live module changed")
    var starts = List[Int]()
    var stops = List[Int]()
    var currents = List[String]()
    var replacements = List[String]()
    _edits_mid(starts, stops, currents, replacements)
    var mid = _step(text, starts, stops, currents, replacements, _MID)
    starts.clear()
    stops.clear()
    currents.clear()
    replacements.clear()
    _edits_qualification(starts, stops, currents, replacements)
    return _step(mid, starts, stops, currents, replacements, _QUALIFICATION)


def restored_witness_typed_after(text: String) raises -> String:
    """Restore the typed-boundary witness module from the live file.

    Args:
        text: The live witness test.

    Returns:
        The typed-boundary after module.

    Raises:
        Error: The live file or a restored step misses its digest.
    """
    var qualification = restored_witness_qualification(text)
    var starts = List[Int]()
    var stops = List[Int]()
    var currents = List[String]()
    var replacements = List[String]()
    _edits_typed(starts, stops, currents, replacements)
    return _step(qualification, starts, stops, currents, replacements, _TYPED)


def restored_witness_bound(text: String) raises -> String:
    """Restore the bound witness module from the typed-boundary after text.

    Args:
        text: The typed-boundary after module.

    Returns:
        The bound witness module.

    Raises:
        Error: `text` is not that endpoint, or the restored digest misses.
    """
    if _digest(text) != _TYPED:
        raise Error("witness consumer: typed endpoint changed")
    var starts = List[Int]()
    var stops = List[Int]()
    var currents = List[String]()
    var replacements = List[String]()
    _edits_bound(starts, stops, currents, replacements)
    return _step(text, starts, stops, currents, replacements, _BOUND)


def witness_endpoint(text: String) -> Int:
    """Return 2 for the qualification endpoint and 1 for the typed endpoint.

    Args:
        text: A witness module.

    Returns:
        `2`, `1`, or `0` when `text` is neither endpoint.
    """
    var digest = _digest(text)
    if digest == _QUALIFICATION:
        return 2
    if digest == _TYPED:
        return 1
    return 0
