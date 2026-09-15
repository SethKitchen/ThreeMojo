# How to write documentation

Documentation in this project follows four standards. This guide says what each one asks of you. `make docs-check` enforces the rules a tool can check.

## Where documentation lives

| Document | Location | Published as |
|---|---|---|
| README | `README.md` | The repository front page |
| Contributing guide | `CONTRIBUTING.md` | GitHub's contributing link |
| Wiki pages | `docs/wiki/*.md` | The GitHub wiki, on every push to `main` |
| API reference | Docstrings in the source | `make docstrings` audits them |

Edit wiki pages in `docs/wiki/`, never in the wiki itself. The CI workflow overwrites the wiki from the repository. This is the DocOps rule: documentation is code, reviewed and tested with the code.

## Choose the page type

Follow [Diátaxis](https://diataxis.fr). Each page has one job:

| Type | Job | Name pattern |
|---|---|---|
| Tutorial | Teach by doing, step by step, with a guaranteed result | `Tutorial-<goal>` |
| How-to guide | Solve one task for a reader who knows the basics | `How-to-<task>` |
| Reference | State what exists and how to call it | The feature name |
| Explanation | Say why the design is what it is | `Why-<topic>` or `The-<event>` |

Do not mix the types. A reference page does not teach. A tutorial does not explain the design. Link to the other page instead.

## Put the main point first

Use the inverse pyramid. The first sentence of a page says what the page gives the reader. The first sentence of a section states the conclusion. Details and history come after.

## Write in Simplified Technical English

Follow ASD-STE100:

- Write short sentences. Use at most 20 words in an instruction and 25 in a description.
- Write one instruction per sentence. Use the imperative: "Run `make check`."
- Use the active voice and the present tense.
- Use "must" for a requirement and "can" for a possibility. Do not use "should", "may" or "might".
- Use one term for one thing. A scene node is a "node". A texture is a "texture", not an "image".
- Keep paragraphs to six sentences and one topic.
- Put code, file names and commands in code spans.

## Check the rules

```bash
make docs-check
```

The tool reports each sentence over the limit, each paragraph over six sentences, and each forbidden word. It skips code blocks, tables and headings.

## Publish the wiki

The CI workflow publishes `docs/wiki/` on every push to `main`. To publish by hand:

```bash
make wiki-publish
```

GitHub creates the wiki repository when someone saves its first page in the browser. That step happens once.
