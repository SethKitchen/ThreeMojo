# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check Markdown documentation against the house writing rules.

    mojo run -I . tools/doc_lint.mojo README.md docs/wiki/*.md

The rules come from ASD-STE100, Simplified Technical English:

- A sentence has at most `MAX_WORDS` words.
- A paragraph has at most `MAX_SENTENCES` sentences.
- The words "should", "may" and "might" do not appear. Use "must" for a
  requirement and "can" for a possibility.
- The spelling is American English: "color", "meter", "center", "gray".

Code blocks, tables, headings, badges and HTML comments are not checked.
Inline code and link targets do not count as words. The tool prints one
line per problem and exits with an error when there is at least one.
"""

from std.pathlib import Path
from std.sys import argv

comptime MAX_WORDS = 25
comptime MAX_SENTENCES = 6


def _clean(line: String) -> String:
    """Return `line` with inline code, link targets and emphasis removed."""
    var out = String("")
    var in_code = False
    var in_target = False
    var after_bracket = False
    for cp in line.codepoint_slices():
        var ch = String(cp)
        if in_code:
            if ch == "`":
                in_code = False
                out += "code"
            continue
        if in_target:
            if ch == ")":
                in_target = False
            continue
        if ch == "`":
            in_code = True
            after_bracket = False
            continue
        if ch == "(" and after_bracket:
            in_target = True
            after_bracket = False
            continue
        after_bracket = ch == "]"
        if ch == "[" or ch == "]" or ch == "*" or ch == "!":
            continue
        out += ch
    return out^


def _sentences(text: String) -> List[String]:
    """Split `text` into sentences at a full stop, question or exclamation
    mark that is followed by a space or the end of the text."""
    var chars = List[String]()
    for cp in text.codepoint_slices():
        chars.append(String(cp))
    var sentences = List[String]()
    var current = String("")
    for index in range(len(chars)):
        var ch = chars[index]
        current += ch
        if ch == "." or ch == "?" or ch == "!":
            var at_end = index + 1 == len(chars)
            if at_end or chars[index + 1] == " ":
                sentences.append(current)
                current = String("")
    if String(current.strip()) != "":
        sentences.append(current)
    return sentences^


def _word_count(sentence: String) -> Int:
    """Return how many whitespace-separated words `sentence` holds."""
    var count = 0
    for token in sentence.split(" "):
        if String(token) != "":
            count += 1
    return count


def _is_list_item(stripped: String) -> Bool:
    """Return True if `stripped` starts a Markdown list item."""
    if stripped.startswith("- ") or stripped.startswith("* "):
        return True
    if stripped.startswith("- [") or stripped.startswith("* ["):
        return True
    var digits = 0
    for cp in stripped.codepoint_slices():
        var ch = String(cp)
        if ch >= "0" and ch <= "9":
            digits += 1
            continue
        return digits > 0 and ch == "."
    return False


def _british() -> List[String]:
    """Return British spellings that the documentation must not use.

    Stems, so that a plural or a past tense is caught too. Each is chosen so
    that no American word contains it.
    """
    return [
        "colour",
        "metre",
        "centre",
        "centred",
        "grey",
        "recognise",
        "recognising",
        "behaviour",
        "artefact",
        "travelled",
        "travelling",
        "neighbour",
        "honour",
        "favour",
        "analyse",
        "analysing",
        "maths",
        "judgement",
        "licence",
        "practise",
        "catalogue",
        "whilst",
        "amongst",
        "learnt",
        "orientated",
        "anticlockwise",
        "cancelled",
        "labelled",
        "modelling",
        "optimise",
        "optimising",
        "optimisation",
        "normalise",
        "normalising",
        "normalisation",
        "initialise",
        "initialising",
        "initialisation",
        "minimise",
        "minimising",
        "maximise",
        "maximising",
        "organise",
        "organising",
        "organisation",
        "summarise",
        "summarising",
        "prioritise",
        "prioritising",
        "emphasise",
        "emphasising",
        "characterise",
        "characterising",
        "characterisation",
        "utilise",
        "utilising",
        "utilisation",
        "specialise",
        "specialising",
        "specialisation",
        "standardise",
        "standardising",
        "visualise",
        "visualising",
        "visualisation",
        "serialise",
        "serialising",
        "serialisation",
        "synchronise",
        "synchronising",
        "synchronisation",
        "customise",
        "customising",
        "finalise",
        "finalising",
        "categorise",
        "categorising",
    ]


def _american() -> List[String]:
    """Return the American spelling for each entry of `_british`."""
    return [
        "color",
        "meter",
        "center",
        "centered",
        "gray",
        "recognize",
        "recognizing",
        "behavior",
        "artifact",
        "traveled",
        "traveling",
        "neighbor",
        "honor",
        "favor",
        "analyze",
        "analyzing",
        "math",
        "judgment",
        "license",
        "practice",
        "catalog",
        "while",
        "among",
        "learned",
        "oriented",
        "counterclockwise",
        "canceled",
        "labeled",
        "modeling",
        "optimize",
        "optimizing",
        "optimization",
        "normalize",
        "normalizing",
        "normalization",
        "initialize",
        "initializing",
        "initialization",
        "minimize",
        "minimizing",
        "maximize",
        "maximizing",
        "organize",
        "organizing",
        "organization",
        "summarize",
        "summarizing",
        "prioritize",
        "prioritizing",
        "emphasize",
        "emphasizing",
        "characterize",
        "characterizing",
        "characterization",
        "utilize",
        "utilizing",
        "utilization",
        "specialize",
        "specializing",
        "specialization",
        "standardize",
        "standardizing",
        "visualize",
        "visualizing",
        "visualization",
        "serialize",
        "serializing",
        "serialization",
        "synchronize",
        "synchronizing",
        "synchronization",
        "customize",
        "customizing",
        "finalize",
        "finalizing",
        "categorize",
        "categorizing",
    ]


def _check_paragraph(
    path: String, first_line: Int, text: String, is_item: Bool
) -> List[String]:
    """Return the problems found in one paragraph or list item."""
    var problems = List[String]()
    var place = path + ":" + String(first_line) + ": "
    var sentences = _sentences(text)
    if not is_item and len(sentences) > MAX_SENTENCES:
        problems.append(
            place
            + String(len(sentences))
            + " sentences in one paragraph (limit "
            + String(MAX_SENTENCES)
            + ")"
        )
    for sentence in sentences:
        var words = _word_count(sentence)
        if words > MAX_WORDS:
            problems.append(
                place
                + String(words)
                + " words in one sentence (limit "
                + String(MAX_WORDS)
                + "): "
                + String(sentence.strip())
            )
    var lowered = " " + text.lower() + " "
    for word in ["should", "may", "might"]:
        if lowered.find(" " + word + " ") >= 0:
            problems.append(
                place
                + "'"
                + word
                + "' is not Simplified Technical English; use 'must' or 'can'"
            )
    var british = _british()
    var american = _american()
    for index in range(len(british)):
        if lowered.find(british[index]) >= 0:
            problems.append(
                place
                + "'"
                + british[index]
                + "' is British English; write '"
                + american[index]
                + "'"
            )
    return problems^


def check_file(path: String) raises -> List[String]:
    """Return every problem in the Markdown file at `path`.

    Args:
        path: The file to check.

    Returns:
        One line per problem, empty if the file passes.

    Raises:
        Error: If the file cannot be read.
    """
    var problems = List[String]()
    var text = Path(path).read_text()
    var in_fence = False
    var in_comment = False
    var paragraph = String("")
    var paragraph_line = 0
    var paragraph_is_item = False
    var number = 0
    for raw in text.split("\n"):
        number += 1
        var stripped = String(String(raw).strip())
        if in_comment:
            if stripped.find("-->") >= 0:
                in_comment = False
            continue
        if stripped.startswith("<!--"):
            if stripped.find("-->") < 0:
                in_comment = True
            continue
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        var skip = (
            stripped == ""
            or stripped.startswith("#")
            or stripped.startswith("|")
            or stripped.startswith("[!")
            or stripped.startswith("---")
            or stripped.startswith("<")
        )
        var is_item = _is_list_item(stripped)
        if skip or is_item:
            if paragraph != "":
                problems.extend(
                    _check_paragraph(
                        path, paragraph_line, paragraph, paragraph_is_item
                    )
                )
                paragraph = String("")
            if skip:
                continue
        if paragraph == "":
            paragraph_line = number
            paragraph_is_item = is_item
            paragraph = _clean(stripped)
        else:
            paragraph += " " + _clean(stripped)
    if paragraph != "":
        problems.extend(
            _check_paragraph(path, paragraph_line, paragraph, paragraph_is_item)
        )
    return problems^


def main() raises:
    var args = argv()
    if len(args) < 2:
        raise Error("usage: doc_lint <file.md>...")
    var problems = 0
    for index in range(1, len(args)):
        var found = check_file(String(args[index]))
        for problem in found:
            print(problem)
        problems += len(found)
    if problems > 0:
        raise Error(String(problems) + " documentation problems found")
    print("Documentation follows the rules:", len(args) - 1, "files.")
