# 10: Optional schema initialisation and explicit restore

**What to build:** An operator can optionally pre-seed a fresh database with the platform schema without the application running, and can explicitly restore a dump, while an ordinary restart never rolls data back.

**Blocked by:** 09

**Status:** ready-for-agent

- [x] With initialisation off, a fresh install contains none of the platform tables, and the application remains the only writer of schema.
- [x] With initialisation on, a fresh install contains the expected platform tables, sourced from the one existing schema definition rather than from a copy, and no second copy of that definition exists in the repository as a result of this work.
- [x] Restoring a chosen dump replaces the contents of the target database.
- [x] Restore is triggered only by an explicit action, never by installing, upgrading or restarting.
- [x] A row written after the last dump is still present after a restart, proving no automatic rollback exists in the cluster.
- [x] The documentation explains why the container stack's restore-on-start behaviour was deliberately not carried over, including that a readiness probe would otherwise report ready while a restore was still overwriting writes.

**Acceptance evidence:** a fresh install with initialisation off and its table listing; the same with initialisation on; a restore run and its effect; the written row surviving a restart; the explanation in the documentation.

## Comments

- 2026-10-14: two explicit jobs were added, for initialising schema and for restoring a dump, both off by default and both applied by a script rather than by the release. That is deliberate for a second reason beyond the obvious one: a job that has already run cannot be modified, so a release-managed one would make every subsequent upgrade fail.
- Initialisation was verified both ways. With it off the database held only the table a previous check had created, and none of the platform tables. With it on, fifteen platform tables appeared. The definition was not copied: the mounted configuration object is byte-for-byte the size of the single existing schema file, and the repository still contains exactly one schema definition.
- The restore replaced rather than merged, which was shown by writing a row and a whole table after the dump was taken and confirming both were absent afterwards while the platform tables came back. The restore job removes itself, and the sentinel it uses is cleared even on failure.
- A row written before a restart was still present afterwards, which is the observation that would have failed if any restore-on-start behaviour had crept in from the container stack.
- Two defects were found here, one mine and one real. Mine: an earlier verification was confounded because the objects I called "written after the dump" had been created before it, so the dump legitimately contained them and the restore appeared to do nothing. The real one: the restore's drop and create ran through a client that reports success even when a statement fails, so a failed create would have turned the restore into a silent merge. Failures are now fatal, and both halves of that lesson are recorded in the script.

