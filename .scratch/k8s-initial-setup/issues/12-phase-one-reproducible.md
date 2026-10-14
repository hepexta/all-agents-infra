# 12: Phase one reproducible from scratch, docs complete

**What to build:** A second person can reconstruct phase one on a clean machine using only the repository's documentation, and the project's own vocabulary and conventions are recorded where they belong.

**Blocked by:** 02, 03, 04, 06

**Status:** ready-for-agent

- [ ] Removing everything this work created and then following the documentation from the top reproduces a working phase one with no undocumented step.
- [ ] Every new directory has a readme covering usage, knobs, validation and teardown.
- [ ] The repository's convention document registers both new directories and their relationship to the existing container stacks.
- [ ] A glossary defines this project's own terms, records the rejected synonyms for each, and contains no implementation detail.
- [ ] Decisions that are hard to reverse, surprising without context and the result of a real trade-off are recorded as architecture decision records, and ordinary choices are not.
- [ ] The stale backup settings described in the convention document are left alone, and that omission is stated rather than silent.

**Acceptance evidence:** a full teardown followed by a documentation-driven rebuild; the readmes; the updated convention document; the glossary; the decision records and their count.
