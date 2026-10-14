# 10: Optional schema initialisation and explicit restore

**What to build:** An operator can optionally pre-seed a fresh database with the platform schema without the application running, and can explicitly restore a dump, while an ordinary restart never rolls data back.

**Blocked by:** 09

**Status:** ready-for-agent

- [ ] With initialisation off, a fresh install contains none of the platform tables, and the application remains the only writer of schema.
- [ ] With initialisation on, a fresh install contains the expected platform tables, sourced from the one existing schema definition rather than from a copy, and no second copy of that definition exists in the repository as a result of this work.
- [ ] Restoring a chosen dump replaces the contents of the target database.
- [ ] Restore is triggered only by an explicit action, never by installing, upgrading or restarting.
- [ ] A row written after the last dump is still present after a restart, proving no automatic rollback exists in the cluster.
- [ ] The documentation explains why the container stack's restore-on-start behaviour was deliberately not carried over, including that a readiness probe would otherwise report ready while a restore was still overwriting writes.

**Acceptance evidence:** a fresh install with initialisation off and its table listing; the same with initialisation on; a restore run and its effect; the written row surviving a restart; the explanation in the documentation.
