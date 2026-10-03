# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How far a published number was checked before it went into code.

An engineering result is only as good as its inputs. Every literature
value in an anatomy table carries an `Evidence` grade and a source key,
so a caller can refuse inputs it does not trust:

- `FROM_ABSTRACT`: the number is in the source's own abstract.
- `FROM_TEXT`: the number is in the source's body or in a secondary
  source that quotes it. Check it against the original before you rely
  on it.
- `CROSS_CHECKED`: read in the source's own table, and it agrees with
  the other values of its row, for example `PCSA = m cos a / (rho L)`.
  The arithmetic of a search extract alone is not enough.
- `UNVERIFIED`: a remembered or a requested value that no source we
  read shows.
- `DESIGN`: a modeling choice or a unit conversion, not a measurement.
"""


@fieldwise_init
struct Evidence(Equatable, ImplicitlyCopyable, Writable):
    """How far a value was checked against its source."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this is a named grade.

        Returns:
            True for the five grades.
        """
        return self.value >= 0 and self.value <= 4

    def is_measured(self) -> Bool:
        """Return whether a source we read shows the value.

        Returns:
            True for `FROM_ABSTRACT`, `FROM_TEXT` and `CROSS_CHECKED`.
        """
        return self.value >= 0 and self.value <= 2


comptime FROM_ABSTRACT = Evidence(0)
comptime FROM_TEXT = Evidence(1)
comptime CROSS_CHECKED = Evidence(2)
comptime UNVERIFIED = Evidence(3)
comptime DESIGN = Evidence(4)


def evidence_label(grade: Evidence) raises -> String:
    """Return the name of a grade.

    Args:
        grade: The grade.

    Returns:
        Its name, as the documentation spells it.

    Raises:
        Error: If the grade is not named.
    """
    if not grade.is_valid():
        raise Error("Evidence must be a named grade")
    var names: List[String] = [
        "from abstract",
        "from text",
        "cross-checked",
        "unverified",
        "design",
    ]
    return names[grade.value]


@fieldwise_init
struct Cited(Copyable, Movable, Writable):
    """Where a value comes from and how far it was checked."""

    var evidence: Evidence
    # A key into the wiki's reference list, such as "Eng2008".
    var source: String
