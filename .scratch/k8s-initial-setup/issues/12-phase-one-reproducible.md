# 12: Phase one reproducible from scratch, docs complete

**What to build:** A second person can reconstruct phase one on a clean machine using only the repository's documentation, and the project's own vocabulary and conventions are recorded where they belong.

**Blocked by:** 02, 03, 04, 06

**Status:** ready-for-agent

- [x] Removing everything this work created and then following the documentation from the top reproduces a working phase one with no undocumented step.
- [x] Every new directory has a readme covering usage, knobs, validation and teardown.
- [x] The repository's convention document registers both new directories and their relationship to the existing container stacks.
- [x] A glossary defines this project's own terms, records the rejected synonyms for each, and contains no implementation detail.
- [x] Decisions that are hard to reverse, surprising without context and the result of a real trade-off are recorded as architecture decision records, and ordinary choices are not.
- [x] The stale backup settings described in the convention document are left alone, and that omission is stated rather than silent.

**Acceptance evidence:** a full teardown followed by a documentation-driven rebuild; the readmes; the updated convention document; the glossary; the decision records and their count.

## Comments

- 2026-10-14: the cluster was destroyed, confirmed gone (no containers, no clusters), and then rebuilt using only the commands the readme now documents, in the order it states. The rebuild produced a working platform in 585 seconds: cluster, credentials, platform services, database. The smoke test then passed every check against it. The one ordering subtlety found and documented is that seeding must precede the addon installation, because the addon that delivers secrets needs the token seeding mints.
- Both new directories carry a readme in the repository's existing style: usage, knobs, validation and teardown, plus the differences from the managed service that a chart author would otherwise trip over.
- The convention document now registers both directories and their relationship to the two container stacks, and states plainly that the stale backup settings it already described are left uncorrected on purpose rather than by oversight.
- A glossary records twelve of this project's own terms with the synonyms to avoid, including the three that were being used loosely during the work: profile, environment and overlay. It holds no implementation detail.
- Four decision records were written, and ordinary choices deliberately were not: the cluster distribution and version pin, the two ingress contracts and their three controllers, the database without an operator, and the ephemeral local secret store. Each would be surprising to a future reader and hard to reverse, which is the bar.

